"""Offline integration contracts; no real home, client session or network."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("integration", ROOT / "lib/sherlock_kit_integration.py")
integration = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(integration)


class IntegrationTests(unittest.TestCase):
    def bundle(self):
        return {"identity": dict(self.pin, install_mode="frozen"), "files": {
            "claude/.claude-plugin/plugin.json": '{"name":"sherlock-kit","version":"0.1.0"}\n',
            "claude/skills/sherlock-kit-operate/SKILL.md": "---\nname: sherlock-kit-operate\n---\nUse the frozen shk.\n",
            "codex/skills/sherlock-kit-operate/SKILL.md": "---\nname: sherlock-kit-operate\n---\nUse the frozen shk.\n"}}

    def test_first_party_adapter_preflight_is_read_only_and_copy_is_idempotent(self):
        home = self.temporary_root / "adapter home 文档"
        with mock.patch.object(integration, "adapter_bundle", return_value=self.bundle()):
            integration.install_adapters(self.root, home, Path("synthetic-python"), check_only=True)
            self.assertFalse(home.exists())
            integration.install_adapters(self.root, home, Path("synthetic-python"))
            before = {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in home.rglob("*") if path.is_file()}
            integration.install_adapters(self.root, home, Path("synthetic-python"))
            self.assertEqual(before, {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in home.rglob("*") if path.is_file()})
        self.assertEqual(len(before), 3)
        self.assertFalse((home / ".claude/settings.json").exists())
        self.assertFalse((home / ".codex/config.toml").exists())

    def test_adapter_bundle_identity_extra_hooks_and_local_conflicts_fail_closed(self):
        home = self.temporary_root / "adapter home"
        for kind in ("identity", "extra", "plugin-hooks", "invalid-plugin", "invalid-payload"):
            payload = self.bundle()
            if kind == "identity": payload["identity"]["code_revision"] = "0" * 40
            elif kind == "extra": payload["files"]["claude/hooks/hooks.json"] = "{}"
            elif kind == "plugin-hooks": payload["files"]["claude/.claude-plugin/plugin.json"] = '{"name":"sherlock-kit","hooks":{}}'
            elif kind == "invalid-plugin": payload["files"]["claude/.claude-plugin/plugin.json"] = '[]'
            else: payload["files"]["claude/.claude-plugin/plugin.json"] = 1
            with self.subTest(kind=kind), mock.patch.object(integration, "adapter_bundle", return_value=payload):
                with self.assertRaises(ValueError):
                    integration.install_adapters(self.root, home, Path("synthetic-python"))
            self.assertFalse(home.exists())
        conflict = home / ".codex/skills/sherlock-kit-operate/SKILL.md"
        conflict.parent.mkdir(parents=True)
        conflict.write_text("user-owned content")
        with mock.patch.object(integration, "adapter_bundle", return_value=self.bundle()):
            with self.assertRaisesRegex(ValueError, "differs"):
                integration.install_adapters(self.root, home, Path("synthetic-python"))
        self.assertEqual(conflict.read_text(), "user-owned content")
        self.assertFalse((home / ".claude").exists())

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="shk-dotfiles-tests-")
        self.addCleanup(self.temporary.cleanup)
        # macOS exposes tempfile's /var root through a system symlink. Resolve
        # only the fixture root before creating targets; target links stay unsafe.
        self.temporary_root = Path(self.temporary.name).resolve()
        self.root = self.temporary_root / "dotfiles 文档"
        self.root.mkdir()
        self.projection = (integration.BEGIN + "\n<!-- source: SHERLOCK.md; schema_version: 1; policy_sha256: "
                           + "a" * 64 + " -->\nScoped synthetic policy\n" + integration.END + "\n")
        self.pin = {"repository": "https://example.org/synthetic.git", "schema_version": 1,
                    "code_revision": "b" * 40, "policy_sha256": "a" * 64,
                    "projection_sha256": hashlib.sha256(self.projection.encode()).hexdigest(),
                    "projection": self.projection}
        self.write_pin()
        for relative in integration.INSTRUCTIONS:
            path = self.root / relative
            path.parent.mkdir(parents=True)
            path.write_text("Existing user instructions\n\n" + self.projection, encoding="utf-8")

    def write_pin(self):
        (self.root / "sherlock-kit.pin.json").write_text(json.dumps(self.pin), encoding="utf-8")

    def snapshot(self):
        return {str(path): (path.read_bytes(), path.stat().st_mode, path.stat().st_mtime_ns)
                for path in self.root.rglob("*") if path.is_file()}

    def test_offline_check_without_installed_package_is_read_only(self):
        before = self.snapshot()
        result = subprocess.run([sys.executable, "-I", "-B", str(ROOT / "lib/sherlock_kit_integration.py"),
                                 "--root", str(self.root), "--check"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, self.snapshot())

    def test_digest_and_instruction_mismatch_fail_closed(self):
        self.pin["projection"] += "tampered"
        self.write_pin()
        with self.assertRaises(ValueError):
            integration.check(self.root)
        self.pin["projection"] = self.projection
        self.write_pin()
        path = self.root / integration.INSTRUCTIONS[0]
        path.write_text(path.read_text().replace("synthetic", "changed"))
        with self.assertRaisesRegex(ValueError, "instruction projection mismatch"):
            integration.check(self.root)

    def test_markers_require_explicit_insertion_and_reject_malformed(self):
        for text in ("no markers", integration.END + integration.BEGIN,
                     self.projection + self.projection, integration.BEGIN):
            with self.subTest(text=text), self.assertRaises(ValueError):
                integration.block(text)
        self.assertIsNone(integration.block("existing content", insertion=True))

    def test_update_prevalidates_both_sources_before_writing(self):
        path = self.root / integration.INSTRUCTIONS[1]
        path.write_text("missing markers")
        before = self.snapshot()
        with mock.patch.object(integration, "run", return_value="b" * 40), \
             mock.patch.object(integration, "archive", return_value=self.root), \
             mock.patch.object(integration, "source_policy", return_value={"identity": self.pin,
                                                                         "projection": self.projection}):
            with self.assertRaisesRegex(ValueError, "markers"):
                integration.update(self.root, self.root)
        self.assertEqual(before, self.snapshot())

    def test_update_preserves_unrelated_content_and_requires_matching_identity(self):
        with mock.patch.object(integration, "run", return_value="b" * 40), \
             mock.patch.object(integration, "archive", return_value=self.root), \
             mock.patch.object(integration, "source_policy", return_value={"identity": self.pin,
                                                                         "projection": self.projection}):
            integration.update(self.root, self.root)
        for relative in integration.INSTRUCTIONS:
            self.assertTrue((self.root / relative).read_text().startswith("Existing user instructions\n"))
        frozen = dict(self.pin, install_mode="frozen")
        integration.verify_identity(frozen, self.pin)
        for key in ("code_revision", "policy_sha256", "install_mode"):
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "identity"):
                integration.verify_identity(dict(frozen, **{key: "different"}), self.pin)

    def test_install_reuses_verified_revision_and_keeps_private_pointer(self):
        home = self.temporary_root / "home with spaces"
        revision = home / ".local/share/sherlock-kit/revisions" / self.pin["code_revision"]
        revision.mkdir(parents=True)
        identity = dict(self.pin, install_mode="frozen")
        with mock.patch.object(integration, "installed_identity", return_value=identity), \
             mock.patch.object(integration, "run", side_effect=AssertionError("must not fetch/build")):
            integration.install(self.root, home)
        active = home / ".local/share/sherlock-kit/active.json"
        self.assertEqual(json.loads(active.read_text()), {"revision": self.pin["code_revision"]})
        if os.name != "nt":
            self.assertEqual(active.stat().st_mode & 0o777, 0o600)
        else:
            self.assertIn(str(sys.executable), (home / ".local/bin/shk.cmd").read_text())

    def test_failed_install_and_concurrent_setup_leave_active_unchanged(self):
        home = self.temporary_root / "home"
        revision = home / ".local/share/sherlock-kit/revisions" / self.pin["code_revision"]
        revision.mkdir(parents=True)
        active = revision.parent.parent / "active.json"
        active.write_text('{"revision":"previous"}')
        with mock.patch.object(integration, "installed_identity", return_value={}):
            with self.assertRaisesRegex(ValueError, "identity"):
                integration.install(self.root, home)
        self.assertEqual(active.read_text(), '{"revision":"previous"}')
        lock = revision.parent.parent / ".setup.lock"
        lock.mkdir()
        with self.assertRaisesRegex(ValueError, "already running"):
            integration.install(self.root, home)
        self.assertTrue(lock.is_dir())

    @unittest.skipIf(os.name == "nt", "native link trust covered separately")
    def test_symlinked_installation_and_write_targets_are_rejected(self):
        home = self.temporary_root / "home"
        home.mkdir()
        (home / ".local").symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlinked"):
            integration.install(self.root, home)
        linked = home / "pin"
        linked.symlink_to(self.root / "sherlock-kit.pin.json")
        with self.assertRaisesRegex(ValueError, "symlink"):
            integration.write(linked, "bad")
        (home / ".claude").symlink_to(self.root, target_is_directory=True)
        before = self.snapshot()
        with mock.patch.object(integration, "adapter_bundle", return_value=self.bundle()):
            for check_only in (True, False):
                with self.subTest(check_only=check_only), self.assertRaisesRegex(ValueError, "symlinked adapter"):
                    integration.install_adapters(self.root, home, Path("synthetic-python"), check_only=check_only)
        self.assertEqual(before, self.snapshot())

    def test_launch_sets_advertised_identity_and_executes_frozen_python(self):
        home = self.temporary_root / "home"
        state = home / ".local/share/sherlock-kit"
        state.mkdir(parents=True)
        (state / "active.json").write_text(json.dumps({"revision": self.pin["code_revision"]}))
        with mock.patch.object(integration.Path, "home", return_value=home), \
             mock.patch.object(integration, "installed_identity", return_value=dict(self.pin, install_mode="frozen")), \
             mock.patch.object(integration.os, "environ", {}), \
             mock.patch.object(integration.os, "execv") as execute:
            integration.launch(self.root, ["doctor"])
            self.assertEqual(integration.os.environ["SHERLOCK_KIT_PIN"], str(self.root / "sherlock-kit.pin.json"))
            command = execute.call_args.args[1]
            self.assertEqual(command[1:], ["-I", "-m", "sherlock_kit", "doctor"])

    def test_installers_are_explicit_and_share_backend(self):
        for name in ("setup-sherlock-kit.sh", "setup-sherlock-kit.ps1"):
            text = (ROOT / name).read_text()
            self.assertIn("lib/sherlock_kit_integration.py", text)
            self.assertIn("--install", text)
        for name in ("setup-sherlock-adapters.sh", "setup-sherlock-adapters.ps1"):
            text = (ROOT / name).read_text()
            self.assertIn("lib/sherlock_kit_integration.py", text)
            self.assertIn("--install-adapters", text)
        for name in ("stow-all.sh", "stow-all.ps1", "scripts/dotfiles-update.sh", "scripts/dotfiles-update.ps1"):
            statements = "\n".join(line for line in (ROOT / name).read_text().splitlines()
                                   if not line.lstrip().startswith("#"))
            self.assertNotIn("setup-sherlock-kit", statements)
            self.assertNotIn("setup-sherlock-adapters", statements)
        self.assertFalse((ROOT / "sherlock/claude/.claude/CLAUDE.md").exists())
        self.assertFalse((ROOT / "sherlock/codex/.codex/AGENTS.md").exists())


if __name__ == "__main__":
    unittest.main()
