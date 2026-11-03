"""Init must replace native update's default autostash/rebase contract."""

import os
from pathlib import Path
import tomllib
import unittest

from chezmoi_source_support import SourceFixture


class UpdateConfigTests(unittest.TestCase):
    def test_repeat_init_preserves_age_and_unknown_local_configuration(self):
        role = "win" if os.name == "nt" else "common-only"
        with SourceFixture(role) as fixture:
            fixture.config.write_text(
                'mode = "symlink"\nencryption = "age"\n[age]\nidentity = "synthetic-identity"\n'
                'recipients = ["synthetic-recipient"]\n[data]\n'
                f'host = "{role}"\nlocal_canary = "retain"\n'
                'large = 9223372036854775807\n[git]\nautoCommit = true\n'
                'autoPush = true\nlocalCanary = "retain"\n[update]\ncommand = "unsafe"\n', encoding="utf-8")
            for _ in range(2):
                result = fixture.run("init")
                self.assertEqual(result.returncode, 0, result.stderr)
                config = tomllib.loads(fixture.config.read_text())
                self.assertEqual(config["encryption"], "age")
                self.assertEqual(config["mode"], "file")
                self.assertEqual(config["age"], {"identity": "synthetic-identity",
                                               "recipients": ["synthetic-recipient"]})
                self.assertEqual(config["data"]["local_canary"], "retain")
                self.assertEqual(config["data"]["large"], 9223372036854775807)
                self.assertFalse(config["git"]["autoCommit"])
                self.assertFalse(config["git"]["autoPush"])
                self.assertEqual(config["git"]["localCanary"], "retain")
                self.assertEqual(config["update"]["command"], "git")

    def test_init_overrides_case_insensitive_owned_settings(self):
        role = "win" if os.name == "nt" else "common-only"
        with SourceFixture(role) as fixture:
            fixture.config.write_text(f'[data]\nhost="{role}"\n[Git]\nAUTOCOMMIT=true\n'
                                      'autoPush=true\n[Update]\nCOMMAND="unsafe"\n')
            result = fixture.run("init")
            self.assertEqual(result.returncode, 0, result.stderr)
            result = fixture.run("execute-template", '{{ .chezmoi.config.git.autocommit }} '
                                 '{{ .chezmoi.config.git.autopush }} {{ .chezmoi.config.update.command }}')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "false false git")

    def test_local_temporals_refuse_init_without_config_rewrite(self):
        role = "win" if os.name == "nt" else "common-only"
        for value in ("1979-05-27", "07:32:00", "1979-05-27T07:32:00"):
            with self.subTest(value=value), SourceFixture(role) as fixture:
                fixture.config.write_text(f'[data]\nhost = "{role}"\nlocal = {value}\n')
                before = fixture.config.read_bytes()
                result = fixture.run("init")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(fixture.config.read_bytes(), before)

    def test_init_pins_safe_update_and_preserves_explicit_role(self):
        role = "win" if os.name == "nt" else "common-only"
        with SourceFixture(role) as fixture:
            result = fixture.run("init")
            self.assertEqual(result.returncode, 0, result.stderr)
            config = tomllib.loads(fixture.config.read_text())
            self.assertEqual(config["update"], {
                "command": "git", "recurseSubmodules": False,
                "args": ["-c", "rebase.autoStash=false", "-c", "merge.autoStash=false",
                         "pull", "--ff-only", "--no-rebase", "--no-autostash",
                         "--no-recurse-submodules"],
            })
            self.assertEqual(config["git"], {"autoAdd": False, "autoCommit": False, "autoPush": False})
            self.assertEqual(config["data"]["host"], role)
            self.assertEqual(Path(config["sourceDir"]), fixture.source)
            self.assertEqual(Path(config["destDir"]), fixture.destination)
            self.assertEqual(list(fixture.destination.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
