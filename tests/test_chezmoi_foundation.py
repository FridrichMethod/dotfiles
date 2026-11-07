"""Black-box deployment probes; no real HOME or application state is used."""

import json
from contextlib import chdir
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from chezmoi_support import ChezmoiFixture


FIXTURES = Path(__file__).parent / "fixtures/chezmoi/foundation"


def snapshot(directory):
    """Capture destination contents and link types without following links."""
    result = {}
    for path in sorted(directory.rglob("*")):
        name = path.relative_to(directory).as_posix()
        if path.is_symlink():
            result[name] = ("symlink", os.readlink(path))
        elif path.is_dir():
            result[name] = ("directory", stat.S_IMODE(path.stat().st_mode) if os.name != "nt" else None)
        else:
            mode = stat.S_IMODE(path.stat().st_mode) if os.name != "nt" else None
            result[name] = ("file", path.read_bytes(), mode)
    return result


class FoundationTests(unittest.TestCase):
    def fixture(self):
        fixture = self.enterContext(ChezmoiFixture())
        shutil.copytree(FIXTURES, fixture.source, dirs_exist_ok=True)
        return fixture

    def successful(self, fixture, *args):
        result = fixture.run(*args)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_regular_file_and_second_apply_converge(self):
        fixture = self.fixture()
        self.successful(fixture, "apply")
        target = fixture.destination / ".sample-config"
        self.assertTrue(target.is_file())
        self.assertFalse(target.is_symlink())
        self.assertEqual(target.read_bytes(), (FIXTURES / "dot_sample-config").read_bytes())
        first = snapshot(fixture.destination)
        self.successful(fixture, "apply")
        self.assertEqual(snapshot(fixture.destination), first)
        self.assertEqual(self.successful(fixture, "diff").stdout, "")

    def test_explicit_paths_ignore_inherited_user_state(self):
        with tempfile.TemporaryDirectory(prefix="chezmoi inherited poison ") as temporary:
            poison = Path(temporary)
            home = poison / "inherited home"
            config = home / ".config/chezmoi/chezmoi.toml"
            config.parent.mkdir(parents=True)
            config.write_text("malformed = [\n", encoding="utf-8")
            sentinel = poison / "sentinel"
            sentinel.write_text("never modify\n", encoding="utf-8")
            inherited = {
                "HOME": str(home),
                "USERPROFILE": str(home),
                "XDG_CONFIG_HOME": str(home / ".config"),
                "XDG_CACHE_HOME": str(poison / "cache"),
                "XDG_DATA_HOME": str(poison / "data"),
                "XDG_STATE_HOME": str(poison / "state"),
                "APPDATA": str(poison / "appdata"),
                "LOCALAPPDATA": str(poison / "localappdata"),
                "CHEZMOI_CONFIG": str(config),
                "CHEZMOI_SOURCE_DIR": str(poison / "source"),
                "CHEZMOI_DEST_DIR": str(poison / "destination"),
                "CHEZMOI_CACHE_DIR": str(poison / "cache"),
                "CHEZMOI_PERSISTENT_STATE": str(poison / "state.db"),
                "CHEZMOI_FUTURE_OVERRIDE": "poison",
                "GIT_DIR": str(poison / "git"),
                "GIT_WORK_TREE": str(poison),
                "GIT_INDEX_FILE": str(sentinel),
                "GIT_CONFIG_GLOBAL": str(config),
                "GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": "core.worktree",
                "GIT_CONFIG_VALUE_0": str(poison),
                "GIT_FUTURE_OVERRIDE": "poison",
                "SSH_AUTH_SOCK": str(poison / "agent.sock"),
                "HTTPS_PROXY": "https://synthetic.invalid",
                "AWS_SECRET_ACCESS_KEY": "synthetic-test-poison",
                "OP_SESSION_synthetic": "synthetic-test-poison",
            }
            before = snapshot(poison)
            with mock.patch.dict(os.environ, inherited):
                fixture = self.fixture()
            self.assertNotEqual(Path(fixture.env["HOME"]), fixture.destination)
            self.assertIn(" ", str(fixture.destination))
            self.assertEqual(fixture.config.read_text(encoding="utf-8"), "")
            for name in ("source", "destination", "config", "cache", "state"):
                self.assertTrue(getattr(fixture, name).is_relative_to(fixture.root))
            self.successful(fixture, "apply")
            expression = "{{ dict"
            for name in inherited:
                expression += f" {json.dumps(name)} (env {json.dumps(name)})"
            expression += " | toJson }}"
            child = json.loads(self.successful(fixture, "execute-template", expression).stdout)
            native_paths = {
                "CHEZMOI_SOURCE_DIR": fixture.source,
                "CHEZMOI_DEST_DIR": fixture.destination,
                "CHEZMOI_CACHE_DIR": fixture.cache,
            }
            for name in inherited:
                if name in native_paths:
                    # Native chezmoi exports its selected directories itself.
                    self.assertEqual(Path(child[name]), native_paths[name])
                elif name.startswith(("CHEZMOI", "GIT_")) or name in (
                    "SSH_AUTH_SOCK", "HTTPS_PROXY", "AWS_SECRET_ACCESS_KEY", "OP_SESSION_synthetic",
                ):
                    self.assertEqual(child[name], "", name)
                else:
                    self.assertTrue(Path(child[name]).is_relative_to(fixture.root), name)
            self.assertTrue(fixture.state.is_file())
            self.assertEqual(snapshot(poison), before)

    def test_destination_drift_is_not_forced(self):
        fixture = self.fixture()
        self.successful(fixture, "apply")
        target = fixture.destination / ".sample-config"
        target.write_text("local destination edit\n", encoding="utf-8")
        (fixture.source / "dot_sample-config").write_text("new portable value\n", encoding="utf-8")
        result = fixture.run("apply")
        # v2.74.0 reports this conflict by exit status without diagnostics.
        self.assertEqual(result.returncode, 1)
        self.assertIn("--error-on-conflict", result.args)
        self.assertIn("--no-tty", result.args)
        self.assertNotIn("--force", result.args)
        self.assertEqual(target.read_text(encoding="utf-8"), "local destination edit\n")

    def test_private_file_and_source_immutability(self):
        fixture = self.fixture()
        before = snapshot(fixture.source)
        self.successful(fixture, "apply")
        target = fixture.destination / ".private-config"
        self.assertEqual(target.read_bytes(), (FIXTURES / "private_dot_private-config").read_bytes())
        self.assertFalse(target.is_symlink())
        if os.name != "nt":
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
        self.assertEqual(snapshot(fixture.source), before)

    def test_dry_run_preserves_destination(self):
        fixture = self.fixture()
        (fixture.destination / "unmanaged").write_text("keep\n", encoding="utf-8")
        before = snapshot(fixture.destination)
        source = snapshot(fixture.source)
        self.successful(fixture, "apply", "--dry-run")
        self.assertEqual(snapshot(fixture.destination), before)
        self.assertEqual(snapshot(fixture.source), source)


class FixturePrerequisiteTests(unittest.TestCase):
    def test_native_child_stdin_is_closed_unless_input_is_explicit(self):
        with ChezmoiFixture() as fixture:
            environment = dict(fixture.env, DOTFILES_TEST_CHEZMOI=str(fixture.binary))
            script = (
                "import json, sys; sys.path.insert(0, sys.argv[1]); "
                "from chezmoi_support import ChezmoiFixture; "
                "fixture = ChezmoiFixture(); "
                "fixture.__enter__(); "
                "result = fixture.run('execute-template'); "
                "fixture.__exit__(None, None, None); "
                "print(json.dumps([result.returncode, result.stdout, result.stderr]))"
            )
            parent = subprocess.run(
                [sys.executable, "-I", "-B", "-c", script, str(Path(__file__).resolve().parent)],
                input="unexpected inherited stdin", text=True, encoding="utf-8",
                capture_output=True, env=environment, cwd=fixture.root, timeout=30, check=False,
            )
            self.assertEqual(parent.returncode, 0, parent.stderr)
            self.assertEqual(json.loads(parent.stdout), [0, "", ""])
            explicit = fixture.run("execute-template", input="explicit {{ 6 }}")
            self.assertEqual(explicit.returncode, 0, explicit.stderr)
            self.assertEqual(explicit.stdout, "explicit 6")

    def test_invalid_explicit_binary_never_falls_back(self):
        with tempfile.TemporaryDirectory(prefix="chezmoi prerequisite ") as temporary:
            with mock.patch.dict(os.environ, {"DOTFILES_TEST_CHEZMOI": str(Path(temporary) / "missing")}):
                with self.assertRaisesRegex(RuntimeError, "DOTFILES_TEST_CHEZMOI"):
                    with ChezmoiFixture():
                        self.fail("invalid explicit executable accepted")

    def test_missing_path_binary_is_an_explicit_skip(self):
        with tempfile.TemporaryDirectory(prefix="chezmoi empty path ") as temporary:
            environment = dict(os.environ)
            environment.pop("DOTFILES_TEST_CHEZMOI", None)
            environment.pop("DOTFILES_TEST_REQUIRE_CHEZMOI", None)
            environment["PATH"] = temporary
            with mock.patch.dict(os.environ, environment, clear=True), chdir(temporary):
                with self.assertRaisesRegex(unittest.SkipTest, "chezmoi"):
                    with ChezmoiFixture():
                        self.fail("missing binary accepted")

    def test_required_missing_binary_fails(self):
        with tempfile.TemporaryDirectory(prefix="chezmoi empty path ") as temporary:
            environment = dict(os.environ)
            environment.pop("DOTFILES_TEST_CHEZMOI", None)
            environment.update(PATH=temporary, DOTFILES_TEST_REQUIRE_CHEZMOI="1")
            with mock.patch.dict(os.environ, environment, clear=True), chdir(temporary):
                with self.assertRaisesRegex(RuntimeError, "chezmoi"):
                    with ChezmoiFixture():
                        self.fail("missing required binary accepted")


if __name__ == "__main__":
    unittest.main()
