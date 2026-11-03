"""Executable bounded takeover/recovery recipes, using only synthetic homes."""

import json
import os
from pathlib import Path
import platform
import shutil
import stat
import tomllib
import unittest

from chezmoi_source_support import SourceFixture, expected_entries, snapshot


class TakeoverRecoveryTests(unittest.TestCase):
    def missing_directories(self, fixture):
        # This is the bounded operator recipe, not an automatic directory writer.
        result = fixture.run("managed", "--include=dirs", "--nul-path-separator")
        self.assertEqual(result.returncode, 0, result.stderr)
        missing = []
        for relative in filter(None, result.stdout.split("\0")):
            target = fixture.destination / relative
            try:
                metadata = target.lstat()
            except FileNotFoundError:
                missing.append(target)
                continue
            reparse = getattr(metadata, "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT
            if not stat.S_ISDIR(metadata.st_mode) or reparse:
                raise ValueError("foreign directory target: stop before native preparation")
        return missing

    def prepare_directories(self, fixture, missing):
        # An empty argument list would select all directories, including existing
        # shared parents. Never run the preparation command without exact targets.
        if missing:
            prepared = fixture.run("apply", "--include=dirs", "--recursive=false",
                                   *(str(path) for path in missing))
            self.assertEqual(prepared.returncode, 0, prepared.stderr)

    @unittest.skipIf(os.name == "nt", "Unix directory modes; Windows ACL evidence is separate")
    def test_operator_prepares_only_missing_parents_and_preserves_existing_modes(self):
        role = self.role()
        with SourceFixture(role) as fixture:
            fixture.config.write_text(f'umask = 0o077\n[data]\nhost = "{role}"\n'
                                      'enrollStaticSecrets = true\n', encoding="utf-8")
            secret_source = fixture.source / "home/private_dot_secrets"
            # Discard only this fixture's copied ciphertext before opting in;
            # the permission recipe must never need production identities.
            if secret_source.exists():
                shutil.rmtree(secret_source)
            secret_source.mkdir()
            (secret_source / "private_operator-probe").write_bytes(b"synthetic private probe\n")
            modes = {".config": 0o770, ".ssh": 0o700, ".claude": 0o700,
                     ".codex": 0o700, ".config/tmux": 0o777}
            for relative, mode in modes.items():
                target = fixture.destination / relative
                target.mkdir(parents=True, exist_ok=True)
                target.chmod(mode)
            sibling = fixture.destination / ".config/tmux/operator-owned"
            sibling.write_bytes(b"unmanaged sibling\n")
            sibling.chmod(0o640)
            mutable = fixture.destination / ".claude/settings.json"
            mutable.write_bytes(b'{"model":"synthetic-local-model"}\n')
            mutable.chmod(0o600)
            initialized = fixture.run("init")
            self.assertEqual(initialized.returncode, 0, initialized.stderr)
            self.assertEqual(tomllib.loads(fixture.config.read_text())["umask"], 0o077)
            before = snapshot(fixture.source)
            missing = self.missing_directories(fixture)
            self.assertIn(fixture.destination / ".secrets", missing)
            self.assertTrue(all(not os.path.lexists(path) for path in missing))
            self.assertTrue(all(fixture.destination / relative not in missing for relative in modes))
            self.prepare_directories(fixture, missing)
            for path in missing:
                self.assertTrue(path.is_dir())
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o700)
            self.assertFalse((fixture.destination / ".secrets/operator-probe").exists())
            first_apply = None
            for _ in range(2):
                applied = fixture.run("apply", "--exclude=dirs")
                self.assertEqual(applied.returncode, 0, applied.stderr)
                for relative, mode in modes.items():
                    self.assertEqual(stat.S_IMODE((fixture.destination / relative).stat().st_mode), mode,
                                     relative)
                self.assertEqual(stat.S_IMODE(mutable.stat().st_mode), 0o600)
                self.assertEqual(json.loads(mutable.read_text())["model"], "synthetic-local-model")
                self.assertEqual(sibling.read_bytes(), b"unmanaged sibling\n")
                self.assertEqual(stat.S_IMODE(sibling.stat().st_mode), 0o640)
                current = snapshot(fixture.destination)
                self.assertEqual(set(current), set(expected_entries(role)) |
                                 {".secrets/operator-probe", ".config/tmux/operator-owned"})
                if first_apply is not None:
                    self.assertEqual(current, first_apply)
                first_apply = current
            self.assertEqual(self.missing_directories(fixture), [])
            self.prepare_directories(fixture, [])
            for relative, mode in modes.items():
                self.assertEqual(stat.S_IMODE((fixture.destination / relative).stat().st_mode), mode)
            secret = fixture.destination / ".secrets/operator-probe"
            self.assertEqual(secret.read_bytes(), b"synthetic private probe\n")
            self.assertEqual(stat.S_IMODE(secret.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(secret.parent.stat().st_mode), 0o700)
            diff = fixture.run("diff", "--exclude=dirs")
            self.assertEqual(diff.returncode, 0, diff.stderr)
            self.assertEqual(diff.stdout, "")
            self.assertEqual(snapshot(fixture.source), before)
            # A future source addition needs a new reviewed preparation. Failure
            # can follow earlier successful writes; this is not a transaction.
            future = fixture.source / "home/dot_config/operator-new"
            future.mkdir()
            (future / "probe").write_bytes(b"future synthetic file\n")
            failed = fixture.run("apply", "--exclude=dirs")
            self.assertNotEqual(failed.returncode, 0)
            self.assertFalse(os.path.lexists(fixture.destination / ".config/operator-new"))

    @unittest.skipIf(os.name == "nt", "Unix dangling directory link; Windows ACL evidence is separate")
    def test_operator_refuses_dangling_directory_instead_of_preparing_it(self):
        with SourceFixture(self.role()) as fixture:
            target = fixture.destination / ".config/tmux"
            target.parent.mkdir()
            foreign = fixture.root / "absent foreign directory"
            target.symlink_to(foreign, target_is_directory=True)
            self.assertFalse(target.exists())
            self.assertTrue(os.path.lexists(target))
            with self.assertRaisesRegex(ValueError, "foreign directory target"):
                self.missing_directories(fixture)
            self.assertTrue(target.is_symlink())
            self.assertEqual(os.readlink(target), str(foreign))
            self.assertFalse(foreign.exists())
            self.assertFalse((fixture.destination / ".ssh").exists())

    def role(self):
        return {"Windows": "win", "Darwin": "mac"}.get(platform.system(), "lab-ubuntu")

    def owned_link(self, fixture, relative):
        entry = expected_entries(fixture.host)[relative]
        owner = fixture.source / entry.source
        target = fixture.destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        try:
            target.symlink_to(owner)
        except OSError as exc:
            if os.name == "nt":
                self.skipTest(f"Windows token cannot create synthetic legacy symlink: {exc.winerror}")
            raise
        return target, owner

    def backup(self, fixture, target, owner):
        # Operator checks the exact owner BEFORE opening the referent.
        if not target.is_symlink() or target.resolve(strict=True) != owner.resolve(strict=True):
            raise ValueError("foreign target: stop before snapshot or native apply")
        root = fixture.root / "private recovery"
        root.mkdir(mode=0o700, exist_ok=True)
        name = str(len(list(root.iterdir())))
        content = root / (name + ".bytes")
        content.write_bytes(target.read_bytes())
        content.chmod(0o600)
        metadata = root / (name + ".json")
        metadata.write_text(json.dumps({"target": str(target), "link": os.readlink(target),
                                        "mode": owner.stat().st_mode & 0o777}))
        metadata.chmod(0o600)
        return content, metadata

    def mark(self, fixture):
        guard = fixture.destination / ".config/dotfiles/native"
        guard.parent.mkdir(parents=True, exist_ok=True)
        guard.write_text(f"dotfiles-chezmoi-v1\n{fixture.destination}\n{fixture.source}\n")
        guard.chmod(0o600)
        return guard

    def test_exact_owned_links_convert_individually_and_repeat_apply_converges(self):
        with SourceFixture(self.role()) as fixture:
            targets = [self.owned_link(fixture, relative) for relative in
                       (".gitconfig", ".claude/settings.json", ".codex/config.toml")]
            snapshots = [self.backup(fixture, target, owner) for target, owner in targets]
            guard = self.mark(fixture)
            for (target, owner), (saved, _metadata) in zip(targets, snapshots):
                before = owner.read_bytes()
                # The only force operation is this exact reviewed, backed-up link.
                applied = fixture.run("apply", "--exclude=dirs", "--force", str(target))
                self.assertEqual(applied.returncode, 0, applied.stderr)
                self.assertFalse(target.is_symlink())
                self.assertEqual(owner.read_bytes(), before)
                self.assertEqual(saved.read_bytes(), before)
            self.prepare_directories(fixture, self.missing_directories(fixture))
            result = fixture.run("apply", "--exclude=dirs")
            self.assertEqual(result.returncode, 0, result.stderr)
            again = fixture.run("apply", "--exclude=dirs")
            self.assertEqual(again.returncode, 0, again.stderr)
            diff = fixture.run("diff", "--exclude=dirs", str(fixture.destination / ".gitconfig"))
            self.assertEqual(diff.returncode, 0, diff.stderr)
            self.assertEqual(diff.stdout, "")
            self.assertTrue(guard.is_file())

    def test_partial_takeover_keeps_later_app_edit_and_original_backup(self):
        with SourceFixture(self.role()) as fixture:
            target, owner = self.owned_link(fixture, ".claude/settings.json")
            original_link = os.readlink(target)
            saved, metadata = self.backup(fixture, target, owner)
            guard = self.mark(fixture)
            self.assertEqual(fixture.run("apply", "--exclude=dirs", "--force", str(target)).returncode, 0)
            # A subsequent app save happens after the original snapshot.
            current = json.loads(target.read_bytes())
            current["model"] = "post-backup-app-edit"
            target.write_text(json.dumps(current))
            edited = target.read_bytes()
            broken = fixture.destination / ".codex/config.toml"
            broken.parent.mkdir(parents=True, exist_ok=True)
            broken.write_bytes(b"local_time = 12:34:56\n")
            failure = fixture.run("apply", "--exclude=dirs", str(broken))
            self.assertNotEqual(failure.returncode, 0)
            self.assertEqual(broken.read_bytes(), b"local_time = 12:34:56\n")
            # Recovery snapshots the current file separately, compares, and leaves
            # the new writer in control when restoring a link would lose an edit.
            recovery = saved.parent / "current-after-failure.bytes"
            shutil.copyfile(target, recovery)
            recovery.chmod(0o600)
            self.assertNotEqual(recovery.read_bytes(), saved.read_bytes())
            self.assertEqual(recovery.read_bytes(), edited)
            self.assertEqual(target.read_bytes(), edited)
            self.assertEqual(saved.read_bytes(), owner.read_bytes())
            self.assertEqual(json.loads(metadata.read_text())["link"], original_link)
            self.assertFalse(target.is_symlink())
            self.assertTrue(guard.is_file())

    def test_foreign_link_is_preserved_without_import_or_force(self):
        with SourceFixture(self.role()) as fixture:
            target, owner = self.owned_link(fixture, ".gitconfig")
            target.unlink()  # Fixture construction, not an operator repair.
            foreign = fixture.root / "foreign-source"
            foreign.write_bytes(b"[fixture]\nforeign=true\n")
            target.symlink_to(foreign)
            self.assertNotEqual(target.resolve(strict=True), owner.resolve(strict=True))
            # The operator rejects it BEFORE native apply: a fresh native state
            # does not yet provide an old-state conflict baseline.
            with self.assertRaisesRegex(ValueError, "foreign target"):
                self.backup(fixture, target, owner)
            self.assertTrue(target.is_symlink())
            self.assertEqual(target.read_bytes(), foreign.read_bytes())
            self.assertFalse((fixture.root / "private recovery").exists())

    def test_fresh_native_state_is_not_a_first_apply_ownership_guard(self):
        with SourceFixture(self.role()) as fixture:
            target, _owner = self.owned_link(fixture, ".gitconfig")
            # Characterization only: this is why operator ownership preflight is
            # mandatory. It is never used as a real takeover recipe.
            result = fixture.run("apply", "--exclude=dirs", str(target))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(target.is_symlink())


if __name__ == "__main__":
    unittest.main()
