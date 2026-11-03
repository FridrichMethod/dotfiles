"""Executable bounded takeover/recovery recipes, using only synthetic homes."""

import json
import os
from pathlib import Path
import platform
import shutil
import unittest

from chezmoi_source_support import SourceFixture, expected_entries


class TakeoverRecoveryTests(unittest.TestCase):
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
                applied = fixture.run("apply", "--force", str(target))
                self.assertEqual(applied.returncode, 0, applied.stderr)
                self.assertFalse(target.is_symlink())
                self.assertEqual(owner.read_bytes(), before)
                self.assertEqual(saved.read_bytes(), before)
            result = fixture.run("apply")
            self.assertEqual(result.returncode, 0, result.stderr)
            again = fixture.run("apply")
            self.assertEqual(again.returncode, 0, again.stderr)
            diff = fixture.run("diff", str(fixture.destination / ".gitconfig"))
            self.assertEqual(diff.returncode, 0, diff.stderr)
            self.assertEqual(diff.stdout, "")
            self.assertTrue(guard.is_file())

    def test_partial_takeover_keeps_later_app_edit_and_original_backup(self):
        with SourceFixture(self.role()) as fixture:
            target, owner = self.owned_link(fixture, ".claude/settings.json")
            original_link = os.readlink(target)
            saved, metadata = self.backup(fixture, target, owner)
            guard = self.mark(fixture)
            self.assertEqual(fixture.run("apply", "--force", str(target)).returncode, 0)
            # A subsequent app save happens after the original snapshot.
            current = json.loads(target.read_bytes())
            current["model"] = "post-backup-app-edit"
            target.write_text(json.dumps(current))
            edited = target.read_bytes()
            broken = fixture.destination / ".codex/config.toml"
            broken.parent.mkdir(parents=True, exist_ok=True)
            broken.write_bytes(b"local_time = 12:34:56\n")
            failure = fixture.run("apply", str(broken))
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
            result = fixture.run("apply", str(target))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(target.is_symlink())


if __name__ == "__main__":
    unittest.main()
