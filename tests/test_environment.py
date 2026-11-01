"""Focused test-only environment and fixture-Git isolation checks."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH_HELPER = ROOT / "tests/lib/environment.sh"
PS_HELPER = ROOT / "tests/lib/environment.ps1"
SHELLS = ("pwsh",) if os.name == "nt" else ("bash", "pwsh")


class TestEnvironment(unittest.TestCase):
    def test_prefixes_are_isolated_and_explicit_test_inputs_survive(self):
        inherited = {"DOTFILES_FUTURE": "caller", "_DOTFILES_FUTURE": "caller",
                     "AWESOME_SKILLS_FUTURE": "caller", "_AWESOME_SKILLS_FUTURE": "caller",
                     "CODING_AGENT_KIT_FUTURE": "caller", "_CODING_AGENT_KIT_FUTURE": "caller",
                     "XDG_STATE_HOME": "caller", "XDG_DATA_HOME": "caller"}
        preserved = {"DOTFILES_TEST_FUTURE": "fixture", "DOTFILES_SYNC_PYTHON": sys.executable,
                     "FZF_TAB_TEST_DIR": "fixture-plugin", "UNRELATED_TEST_VALUE": "keep"}
        for shell in SHELLS:
            executable = shutil.which(shell)
            if not executable:
                with self.subTest(shell=shell):
                    self.skipTest(f"{shell} unavailable")
                continue
            with self.subTest(shell=shell), tempfile.TemporaryDirectory() as home:
                env = os.environ | inherited | preserved | {
                    "HOME": home, "APPDATA": home, "LOCALAPPDATA": home, "XDG_CACHE_HOME": home,
                    "POWERSHELL_TELEMETRY_OPTOUT": "1", "POWERSHELL_UPDATECHECK": "Off"}
                code = "import json,os; print(json.dumps(dict(os.environ)))"
                if shell == "bash":
                    command = [executable, "-c", '. "$1"; shift; exec "$@"', "_", str(BASH_HELPER),
                               sys.executable, "-I", "-B", "-c", code]
                else:
                    env.update(TEST_ENV_HELPER=str(PS_HELPER), TEST_PYTHON=sys.executable, TEST_CODE=code)
                    command = [executable, "-NoProfile", "-NonInteractive", "-Command",
                               '. $env:TEST_ENV_HELPER; & $env:TEST_PYTHON -I -B -c $env:TEST_CODE']
                result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stderr)
                actual = json.loads(result.stdout)
                for name in inherited:
                    self.assertNotIn(name, actual)
                for name, value in preserved.items():
                    self.assertEqual(actual.get(name), value)

    def test_fixture_git_cannot_modify_the_parent_linked_worktree(self):
        for shell in SHELLS:
            executable = shutil.which(shell)
            if not executable:
                with self.subTest(shell=shell):
                    self.skipTest(f"{shell} unavailable")
                continue
            for relative in (False, True):
                with self.subTest(shell=shell, relative_index=relative), tempfile.TemporaryDirectory() as directory:
                    base = Path(directory)
                    env = {name: value for name, value in os.environ.items() if not name.startswith("GIT_")}
                    env.update(HOME=str(base), APPDATA=str(base), LOCALAPPDATA=str(base), XDG_CACHE_HOME=str(base),
                               POWERSHELL_TELEMETRY_OPTOUT="1", POWERSHELL_UPDATECHECK="Off",
                               GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
                    def git(*args):
                        return subprocess.check_output(["git", "-c", "user.name=Fixture", "-c",
                                                        "user.email=fixture@example.invalid", *map(str, args)],
                                                       env=env, text=True, stderr=subprocess.DEVNULL).strip()
                    parent, linked = base / "parent", base / "linked"
                    git("init", "-q", parent)
                    git("-C", parent, "commit", "-q", "--allow-empty", "-m", "fixture")
                    git("-C", parent, "worktree", "add", "-q", "--detach", linked)
                    git_dir = Path(git("-C", linked, "rev-parse", "--absolute-git-dir"))
                    tracked = [parent / ".git/index", git_dir / "index"]
                    before = [(p.read_bytes() if p.exists() else None) for p in tracked]
                    heads = [git("-C", path, "rev-parse", "HEAD") for path in (parent, linked)]
                    injected = env | {"GIT_DIR": str(git_dir), "GIT_INDEX_FILE": ".git/index" if relative else str(git_dir / "index")}
                    child = base / "child.git"
                    if shell == "bash":
                        command = [executable, "-c", '. "$1"; dotfiles_test_clear_git_environment; git init --bare -q "$2"',
                                   "_", str(BASH_HELPER), str(child)]
                    else:
                        injected.update(TEST_ENV_HELPER=str(PS_HELPER), TEST_GIT_CHILD=str(child))
                        command = [executable, "-NoProfile", "-NonInteractive", "-Command",
                                   '. $env:TEST_ENV_HELPER; Clear-DotfilesTestGitEnvironment; git init --bare -q $env:TEST_GIT_CHILD; exit $LASTEXITCODE']
                    result = subprocess.run(command, cwd=linked, env=injected, text=True, capture_output=True, timeout=20)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(git("-C", child, "rev-parse", "--is-bare-repository"), "true")
                    self.assertEqual(git("-C", parent, "config", "--get", "core.bare"), "false")
                    self.assertEqual([git("-C", p, "rev-parse", "HEAD") for p in (parent, linked)], heads)
                    self.assertEqual([(p.read_bytes() if p.exists() else None) for p in tracked], before)
