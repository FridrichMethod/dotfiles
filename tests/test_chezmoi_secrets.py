"""Disposable native age evidence; no production credentials or secret reports."""

import json
import os
from pathlib import Path
import secrets
import shutil
import stat
import unittest

from chezmoi_support import ChezmoiFixture
from chezmoi_source_support import ROOT, ROLES, SourceFixture, expected_entries, snapshot


FIXTURES = Path(__file__).parent / "fixtures" / "chezmoi" / "secrets"


class NativeSecretTests(unittest.TestCase):
    def assert_success(self, result):
        # Do not put captured encryption/decryption output into failure messages.
        self.assertEqual(result.returncode, 0, "native synthetic age command failed")

    def prepare(self, fixture):
        empty_bin = fixture.root / "empty-bin"
        empty_bin.mkdir(exist_ok=True)
        fixture.env["PATH"] = str(empty_bin)
        identity = fixture.root / "disposable identity.txt"
        self.assert_success(fixture.run("age-keygen", "--output", str(identity), "--use-builtin-age=true"))
        recipient_result = fixture.run("age-keygen", "--convert", str(identity), "--use-builtin-age=true")
        self.assert_success(recipient_result)
        recipient = recipient_result.stdout.strip()
        self.assertTrue(recipient.startswith("age1"))
        self.configure(fixture, identity, [recipient])
        return identity, recipient

    def configure(self, fixture, identity, recipients):
        fixture.config.write_text(
            'encryption = "age"\n[age]\n'
            f"identity = {json.dumps(str(identity))}\n"
            f"recipients = {json.dumps(recipients)}\n",
            encoding="utf-8",
        )

    def encrypt(self, fixture, plaintext, recipient=None):
        args = ["encrypt", "--use-builtin-age=true"]
        if recipient is not None:
            args.extend(["--age-recipient", recipient])
        result = fixture.run(*args, input=plaintext)
        self.assert_success(result)
        self.assertTrue(plaintext not in result.stdout, "synthetic encryption leaked plaintext")
        return result.stdout

    def install_ciphertext(self, fixture, ciphertext, create=False):
        source_parent = fixture.source / "private_dot_secrets"
        source_parent.mkdir(exist_ok=True)
        prefix = "create_" if create else ""
        source = source_parent / f"{prefix}encrypted_private_account.age"
        source.write_text(ciphertext, encoding="utf-8")
        return source, fixture.destination / ".secrets" / "account"

    def install_enrollment_gate(self, fixture, role):
        # Only production controls and disposable ciphertext enter this fixture.
        shutil.copyfile(ROOT / "home/.chezmoiignore", fixture.source / ".chezmoiignore")
        templates = fixture.source / ".chezmoitemplates"
        templates.mkdir()
        shutil.copyfile(ROOT / "home/.chezmoitemplates/validate-host", templates / "validate-host")
        with fixture.config.open("a", encoding="utf-8") as config:
            config.write(f'\n[data]\nhost = "{role}"\nenrollStaticSecrets = true\n')

    def test_unenrolled_and_wrong_host_sources_stay_keyless_with_exact_ordinary_inventory(self):
        for role in ROLES:
            native_os = "darwin" if role == "mac" else "windows" if role == "win" else "linux"
            values = (None, "false") if role in ("mac", "wsl-ubuntu", "lab-ubuntu") else (None, "false", "true")
            for value in values:
                with self.subTest(role=role, opt_in=value), SourceFixture(role, native_os=native_os) as fixture:
                    if value is not None:
                        with fixture.config.open("a", encoding="utf-8") as config:
                            config.write(f"enrollStaticSecrets = {value}\n")
                    parent = fixture.source / "home/private_dot_secrets"
                    parent.mkdir(exist_ok=True)
                    (parent / "encrypted_private_gate-probe.age").write_text("invalid synthetic ciphertext\n")
                    before = snapshot(fixture.source)
                    managed = fixture.run("managed", "--include=files", "--nul-path-separator")
                    self.assert_success(managed)
                    self.assertEqual({p.replace("\\", "/") for p in managed.stdout.split("\0") if p},
                                     set(expected_entries(role)))
                    self.assert_success(fixture.run("apply"))
                    self.assertFalse((fixture.destination / ".secrets").exists())
                    self.assertEqual(snapshot(fixture.source), before)

    def test_enrollment_flag_rejects_non_boolean_data_before_destination_writes(self):
        for value in ('"true"', '"false"', '""', "1", "0", "[]", "{}"):
            with self.subTest(value=value), SourceFixture("lab-ubuntu", native_os="linux") as fixture:
                with fixture.config.open("a", encoding="utf-8") as config:
                    config.write(f"enrollStaticSecrets = {value}\n")
                result = fixture.run("apply")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("enrollStaticSecrets", result.stderr)
                self.assertEqual(list(fixture.destination.iterdir()), [])

    def test_enrolled_supported_hosts_deploy_only_synthetic_private_secrets(self):
        for role in ("mac", "wsl-ubuntu", "lab-ubuntu"):
            with self.subTest(role=role), ChezmoiFixture() as fixture:
                self.prepare(fixture)
                self.install_enrollment_gate(fixture, role)
                canary = secrets.token_hex(32) + "\n"
                source, target = self.install_ciphertext(fixture, self.encrypt(fixture, canary))
                target.parent.mkdir()
                sibling = target.parent / "application-auth.json"
                sibling.write_bytes(b"synthetic app-owned refresh state\n")
                before = snapshot(fixture.source)
                native_os = "darwin" if role == "mac" else "linux"
                for _ in range(2):
                    result = fixture.run("--override-data", json.dumps({"chezmoi": {"os": native_os}}),
                                         "apply", "--use-builtin-age=true")
                    self.assert_success(result)
                    self.assertTrue(canary not in result.stdout + result.stderr)
                    self.assertTrue(target.read_text() == canary)
                    self.assertEqual(sibling.read_bytes(), b"synthetic app-owned refresh state\n")
                self.assertEqual(snapshot(fixture.source), before)
                self.assertFalse(target.is_symlink())
                if os.name != "nt":
                    self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
                    self.assertEqual(stat.S_IMODE(target.parent.stat().st_mode), 0o700)

    def test_enrolled_missing_identity_fails_without_replacing_existing_secret(self):
        with ChezmoiFixture() as fixture:
            identity, _ = self.prepare(fixture)
            self.install_enrollment_gate(fixture, "lab-ubuntu")
            source, target = self.install_ciphertext(fixture, self.encrypt(fixture, "synthetic selected value\n"))
            target.parent.mkdir()
            target.write_text("synthetic existing value\n")
            identity.unlink()
            result = fixture.run("--override-data", '{"chezmoi":{"os":"linux"}}',
                                 "apply", "--use-builtin-age=true")
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(target.read_text(), "synthetic existing value\n")
            self.assertNotIn("synthetic selected value", result.stdout + result.stderr)
            self.assertNotIn("synthetic existing value", result.stdout + result.stderr)

    def test_builtin_age_roundtrip_private_apply_source_and_reporting_boundary(self):
        with ChezmoiFixture() as fixture:
            identity, _ = self.prepare(fixture)
            canary = secrets.token_hex(32) + "\n"
            ciphertext = self.encrypt(fixture, canary)
            decrypted = fixture.run("decrypt", "--use-builtin-age=true", input=ciphertext)
            self.assert_success(decrypted)
            self.assertTrue(decrypted.stdout == canary, "synthetic decrypt mismatch")
            source, target = self.install_ciphertext(fixture, ciphertext)
            shutil.copyfile(FIXTURES / "public.txt", fixture.source / "public.txt")
            source_before = source.read_bytes()

            # Report only an explicit nonsecret target. Ordinary diff is not redaction.
            report = fixture.run("diff", str(fixture.destination / "public.txt"))
            self.assert_success(report)
            self.assertTrue(canary not in report.stdout + report.stderr)
            applied = fixture.run("apply", "--use-builtin-age=true")
            self.assert_success(applied)
            self.assertTrue(canary not in applied.stdout + applied.stderr)
            self.assertTrue(target.read_text(encoding="utf-8") == canary)
            self.assertFalse(target.is_symlink())
            self.assertFalse(identity.is_relative_to(fixture.source))
            if os.name != "nt":
                self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
                self.assertEqual(stat.S_IMODE(target.parent.stat().st_mode), 0o700)
                self.assertEqual(stat.S_IMODE(identity.stat().st_mode), 0o600)
            second = fixture.run("apply", "--use-builtin-age=true")
            self.assert_success(second)
            self.assertTrue(canary not in second.stdout + second.stderr)
            self.assertTrue(target.read_text(encoding="utf-8") == canary)
            self.assertEqual(source.read_bytes(), source_before)
            for path in fixture.source.rglob("*"):
                if path.is_file():
                    self.assertTrue(canary.encode() not in path.read_bytes())
            report = fixture.run("diff", str(fixture.destination / "public.txt"))
            self.assert_success(report)
            self.assertEqual(report.stdout, "")

    def test_missing_identity_malformed_ciphertext_and_unavailable_backend_preserve_secret(self):
        for failure in ("missing-identity", "malformed-ciphertext", "unavailable-external-backend"):
            with self.subTest(failure=failure), ChezmoiFixture() as fixture:
                identity, _ = self.prepare(fixture)
                canary = secrets.token_hex(32) + "\n"
                source, target = self.install_ciphertext(fixture, self.encrypt(fixture, canary))
                target.parent.mkdir()
                existing = secrets.token_hex(32) + "\n"
                target.write_text(existing, encoding="utf-8")
                target.chmod(0o600)
                if failure == "missing-identity":
                    identity.unlink()
                elif failure == "malformed-ciphertext":
                    source.write_text("not age ciphertext\n", encoding="utf-8")
                args = ["apply", "--use-builtin-age=" + ("false" if failure == "unavailable-external-backend" else "true")]
                result = fixture.run(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(target.read_text(encoding="utf-8") == existing)
                self.assertTrue(canary not in result.stdout + result.stderr)
                self.assertTrue(existing not in result.stdout + result.stderr)
                # Fixture.run supplies a finite timeout, no TTY and closed stdin.

    def test_per_file_recipients_can_scope_access_and_shared_recipients_share_access(self):
        with ChezmoiFixture() as fixture:
            first_identity, first_recipient = self.prepare(fixture)
            second_identity = fixture.root / "second disposable identity.txt"
            self.assert_success(fixture.run("age-keygen", "--output", str(second_identity), "--use-builtin-age=true"))
            result = fixture.run("age-keygen", "--convert", str(second_identity), "--use-builtin-age=true")
            self.assert_success(result)
            second_recipient = result.stdout.strip()
            canary = secrets.token_hex(32)
            # Override must replace a different configured default recipient.
            self.configure(fixture, second_identity, [second_recipient])
            scoped = self.encrypt(fixture, canary, first_recipient)
            inaccessible = fixture.run("decrypt", "--use-builtin-age=true", input=scoped)
            self.assertNotEqual(inaccessible.returncode, 0)
            self.assertTrue(canary not in inaccessible.stdout + inaccessible.stderr)
            self.configure(fixture, first_identity, [first_recipient, second_recipient])
            shared = self.encrypt(fixture, canary)
            for identity in (first_identity, second_identity):
                self.configure(fixture, identity, [first_recipient, second_recipient])
                result = fixture.run("decrypt", "--use-builtin-age=true", input=shared)
                self.assert_success(result)
                self.assertTrue(result.stdout == canary)

    def test_create_if_missing_preserves_refresh_but_reseeds_after_logout(self):
        with ChezmoiFixture() as fixture:
            self.prepare(fixture)
            seed = secrets.token_hex(32) + "\n"
            source, target = self.install_ciphertext(fixture, self.encrypt(fixture, seed), create=True)
            source_before = source.read_bytes()
            self.assert_success(fixture.run("apply", "--use-builtin-age=true"))
            self.assertTrue(target.read_text(encoding="utf-8") == seed)
            refreshed = secrets.token_hex(32) + "\n"
            target.write_text(refreshed, encoding="utf-8")
            self.assert_success(fixture.run("apply", "--use-builtin-age=true"))
            self.assertTrue(target.read_text(encoding="utf-8") == refreshed)
            target.unlink()  # Synthetic logout/removal.
            # Remembered deletion is a conflict with our guarded invocation.
            self.assertNotEqual(fixture.run("apply", "--use-builtin-age=true").returncode, 0)
            self.assertFalse(target.exists())
            # Loss/reset of native state bypasses that protection and seeds again.
            fixture.state.unlink()
            self.assert_success(fixture.run("apply", "--use-builtin-age=true"))
            self.assertTrue(target.read_text(encoding="utf-8") == seed)
            self.assertEqual(source.read_bytes(), source_before)


if __name__ == "__main__":
    unittest.main()
