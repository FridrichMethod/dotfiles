"""Init must replace native update's default autostash/rebase contract."""

import json
import os
from pathlib import Path
import subprocess
import tomllib
import unittest

from chezmoi_source_support import SourceFixture


STATE = ".local/state/chezmoi/chezmoi.boltdb"


class UpdateConfigTests(unittest.TestCase):
    def test_repeat_init_preserves_age_and_unknown_local_configuration(self):
        role = "win" if os.name == "nt" else "common-only"
        with SourceFixture(role) as fixture:
            fixture.config.write_text(
                'mode = "symlink"\nencryption = "age"\numask = 0o077\n[age]\nidentity = "synthetic-identity"\n'
                'recipients = ["synthetic-recipient"]\n[data]\n'
                f'host = "{role}"\nlocal_canary = "retain"\n'
                'large = 9223372036854775807\n[git]\nautoCommit = true\n'
                'autoPush = true\nlocalCanary = "retain"\n[update]\ncommand = "unsafe"\n', encoding="utf-8")
            first = None
            for _ in range(2):
                result = fixture.run("init")
                self.assertEqual(result.returncode, 0, result.stderr)
                config = tomllib.loads(fixture.config.read_text())
                self.assertEqual(config["encryption"], "age")
                self.assertEqual(config["mode"], "file")
                self.assertEqual(config["umask"], 0o077)
                self.assertEqual(Path(config["persistentState"]), fixture.destination / STATE)
                self.assertEqual(config["age"], {"identity": "synthetic-identity",
                                               "recipients": ["synthetic-recipient"]})
                self.assertEqual(config["data"]["local_canary"], "retain")
                self.assertEqual(config["data"]["large"], 9223372036854775807)
                self.assertFalse(config["git"]["autoCommit"])
                self.assertFalse(config["git"]["autoPush"])
                self.assertEqual(config["git"]["localCanary"], "retain")
                self.assertEqual(config["update"]["command"], "git")
                if first is not None:
                    self.assertEqual(fixture.config.read_bytes(), first)
                first = fixture.config.read_bytes()

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

    def test_state_aliases_collapse_to_the_owned_key(self):
        role = "win" if os.name == "nt" else "common-only"
        for alias in ("persistentstate", "PersistentState", "PERSISTENTSTATE"):
            with self.subTest(alias=alias), SourceFixture(role) as fixture:
                foreign = (fixture.root / "foreign state.boltdb").as_posix()
                fixture.config.write_text(f'{alias} = "{foreign}"\n[data]\nhost = "{role}"\n',
                                          encoding="utf-8")
                result = fixture.run("init")
                self.assertEqual(result.returncode, 0, result.stderr)
                # Read the file: execute-template reports the fixture's flag instead.
                config = tomllib.loads(fixture.config.read_text())
                self.assertEqual([key for key in config if key.lower() == "persistentstate"],
                                 ["persistentState"])
                self.assertEqual(Path(config["persistentState"]), fixture.destination / STATE)
        with SourceFixture(role) as fixture:
            fixture.config.write_text(f'persistentState = "{fixture.root.as_posix()}/a"\n'
                                      f'persistentstate = "{fixture.root.as_posix()}/b"\n'
                                      f'[data]\nhost = "{role}"\n', encoding="utf-8")
            before = fixture.config.read_bytes()
            result = fixture.run("init")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("duplicate case-insensitive native config key", result.stderr)
            self.assertEqual(fixture.config.read_bytes(), before)

    def test_template_derives_state_from_unix_and_windows_destinations(self):
        role = "win" if os.name == "nt" else "common-only"
        with SourceFixture(role) as fixture:
            template = fixture.source / "home/.chezmoi.toml.tmpl"
            for destination in ("/home/synthetic user", "C:/Users/synthetic user"):
                with self.subTest(destination=destination):
                    result = fixture.run("--override-data", json.dumps({"chezmoi": {"destDir": destination}}),
                                         "execute-template", "--file", str(template))
                    self.assertEqual(result.returncode, 0, result.stderr)
                    config = tomllib.loads(result.stdout)
                    self.assertEqual(config["destDir"], destination)
                    self.assertEqual(config["persistentState"], f"{destination}/{STATE}")

    def test_plain_native_command_shares_the_bound_state_database(self):
        role = "win" if os.name == "nt" else "common-only"
        with SourceFixture(role) as fixture:
            result = fixture.run("init")
            self.assertEqual(result.returncode, 0, result.stderr)
            bound = fixture.destination / STATE
            stray = fixture.config.parent / "chezmoistate.boltdb"
            target = str(fixture.destination / ".gitconfig")
            # The updater's explicit flag still wins over the owned key.
            result = fixture.run("apply", "--exclude=dirs", "--force=false", target)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertGreater(fixture.state.stat().st_size, 0)
            self.assertFalse(os.path.lexists(bound))
            # A plain command names only the config, as a host finds it by default.
            result = subprocess.run(
                [str(fixture.binary), "--config", str(fixture.config), "--no-tty",
                 "apply", "--exclude=dirs", "--force=false", target],
                text=True, encoding="utf-8", capture_output=True, stdin=subprocess.DEVNULL,
                cwd=fixture.root, env=fixture.env, timeout=30, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertGreater(bound.stat().st_size, 0)
            self.assertFalse(os.path.lexists(stray))

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
            # Plain native commands share the updater's state, in slash form on Windows too.
            self.assertEqual(Path(config["persistentState"]), fixture.destination / STATE)
            self.assertNotIn("\\", config["persistentState"])
            # Init never opens the configured database.
            self.assertEqual(list(fixture.destination.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
