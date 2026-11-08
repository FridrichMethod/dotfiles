"""Executable bounded missing-parent preparation, using only synthetic homes."""

import json
import os
import platform
import shutil
import stat
import tomllib
import unittest

from chezmoi_source_support import SourceFixture, expected_entries, snapshot


class MissingParentTests(unittest.TestCase):
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
                raise ValueError("foreign directory target: stop before preparation")
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

    def test_operator_prepares_every_missing_parent_and_file_apply_converges(self):
        # The portable half of the recipe: no links and no POSIX modes, so it
        # also runs on Windows, where the two cases above skip.
        role = self.role()
        with SourceFixture(role) as fixture:
            before = snapshot(fixture.source)
            missing = self.missing_directories(fixture)
            self.assertTrue(missing)
            self.prepare_directories(fixture, missing)
            self.assertTrue(all(path.is_dir() for path in missing))
            self.assertEqual(self.missing_directories(fixture), [])
            first_apply = None
            for _ in range(2):
                applied = fixture.run("apply", "--exclude=dirs")
                self.assertEqual(applied.returncode, 0, applied.stderr)
                current = snapshot(fixture.destination)
                self.assertEqual(set(current), set(expected_entries(role)))
                if first_apply is not None:
                    self.assertEqual(current, first_apply)
                first_apply = current
            diff = fixture.run("diff", "--exclude=dirs")
            self.assertEqual(diff.returncode, 0, diff.stderr)
            self.assertEqual(diff.stdout, "")
            self.assertEqual(snapshot(fixture.source), before)

    def role(self):
        return {"Windows": "win", "Darwin": "mac"}.get(platform.system(), "lab-ubuntu")


if __name__ == "__main__":
    unittest.main()
