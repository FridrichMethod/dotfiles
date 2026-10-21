"""Dotfiles-content halves of the coding-agent-kit suites, on the real files.

The launcher suites live in the coding-agent-kit submodule and run there on
frozen fixtures. These cases read what only dotfiles owns: the fzf-tab preview,
the alias files, .stowrc and the package link that delivers codex-as. The
fixtures are the parts of the launcher suites' setUp they read.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "common/codex/.local"
KIT = ROOT / "common/codex/coding-agent-kit"
SHELLS = [shutil.which(name) for name in ("bash", "zsh") if shutil.which(name)]
ENV_CONFLICTS = (
    "CODEX_API_KEY", "CODEX_ACCESS_TOKEN", "OPENAI_API_KEY",
    "OPENAI_IDENTITY_TOKEN_FILE", "OPENAI_ORGANIZATION", "OPENAI_PROJECT", "OPENAI_FEDERATION_RULE_ID",
    "OPENAI_WORKLOAD_IDENTITY_CONTEXT", "CODEX_REFRESH_TOKEN_URL_OVERRIDE",
    "CODEX_REVOKE_TOKEN_URL_OVERRIDE", "CODEX_APP_SERVER_LOGIN_CLIENT_ID",
    "CODEX_APP_SERVER_LOGIN_ISSUER", "CODEX_AUTHAPI_BASE_URL",
    "CODEX_AGENT_IDENTITY_AUTHAPI_BASE_URL", "CODEX_AGENT_IDENTITY_JWKS_BASE_URL",
)


def setUpModule():
    # codex-as is a link into the coding-agent-kit submodule.
    if not (SOURCE / "bin/codex-as").is_file():
        raise RuntimeError("coding-agent-kit submodule not initialized; run git submodule update --init --recursive.")


class IsolatedHome(unittest.TestCase):
    """A temporary HOME with codex-as installed and a credential it must never read."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="codex-as-test-")
        self.addCleanup(self.tmp.cleanup)
        # macOS TMPDIR uses /var -> /private/var; getcwd() reports the physical
        # path. Keep all fixture expectations in that same directory spelling.
        self.base = Path(self.tmp.name).resolve()
        self.home = self.base / "home with spaces"
        self.home.mkdir(mode=0o700)
        self.secret = self.home / ".secrets"
        self.secret.mkdir(mode=0o700)
        credential = self.secret / "codex-A.json"
        credential.write_text('{"tokens": {"access_token": "fabricated-sensitive-access-A"}}')
        credential.chmod(0o600)
        self.command_bin = self.home / ".local/bin"
        self.command_bin.mkdir(parents=True)
        # Linked as Stow links it: the launcher finds its kit, and so its lib/,
        # through the package link; a copy would stand alone.
        (self.command_bin / "codex-as").symlink_to(SOURCE / "bin/codex-as")
        self.cwd = self.base / "current working directory"
        self.cwd.mkdir()
        self.env = os.environ.copy()
        # No configuration of the caller's coding-agent-kit is in reach.
        for name in (*ENV_CONFLICTS, "CODEX_HOME", "CODEX_SQLITE_HOME", "PYTHONPATH", "BASH_ENV", "ENV", "ZDOTDIR",
                     "XDG_CONFIG_HOME", "CODING_AGENT_KIT_CONFIG", "CODING_AGENT_KIT_COLOR"):
            self.env.pop(name, None)
        self.env.update(HOME=str(self.home), PATH=os.pathsep.join((str(self.command_bin), self.env["PATH"])))


class CodexAs(IsolatedHome):
    @unittest.skipIf(os.name == "nt", "POSIX shells and alias files")
    def test_real_alias_files_run_codex_as(self):
        (self.home / ".aliases").write_text("")
        for shell in SHELLS:
            flags = ["-f"] if Path(shell).name == "zsh" else ["--noprofile", "--norc"]
            alias_file = ROOT / ("common/zsh/.zsh_aliases" if Path(shell).name == "zsh" else "common/bash/.bash_aliases")
            command = [shell, *flags, "-c", '. "$1"; . "$1"; codex-as --help', "alias", str(alias_file)]
            result = subprocess.run(command, cwd=self.cwd, env=self.env, stdin=subprocess.DEVNULL, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Concurrent accounts", result.stdout)
            self.assertIn(f"Details and manual repair: {KIT.resolve()}/docs/account-launchers.md\n", result.stdout)


class Enrollment(IsolatedHome):
    @unittest.skipIf(os.name == "nt", "zsh and fzf-tab")
    def test_fzf_preview_never_reads_secret_file(self):
        zsh = shutil.which('zsh')
        if not zsh:
            self.skipTest('zsh not installed')
        preview = ROOT / 'common/zsh/.oh-my-zsh/custom/fzf-tab.zsh'
        command = 'source "$1"; zstyle -s :fzf-tab:complete:codex-as:accounts fzf-preview preview; word=A; realpath="$HOME/.secrets/codex-A.json"; my-fzf-preview.sh() { print "LEAK"; }; eval "$preview"'
        result = subprocess.run([zsh, '-f', '-c', command, 'preview', str(preview)], env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'A\n')

    @unittest.skipIf(os.name == "nt", "GNU Stow")
    def test_real_stow_installs_underscore_completions_and_ignores_appledouble(self):
        stow = shutil.which('stow')
        if not stow:
            self.skipTest('GNU Stow not installed')
        packages = self.base / 'packages'
        target = self.base / 'stowed home'
        target.mkdir(mode=0o700)
        for tool in ('codex', 'claude'):
            shutil.copytree(ROOT / f'common/{tool}', packages / tool)
        apple = packages / 'codex/.local/bin/._fake-appledouble'
        apple.write_text('fixture')
        result = subprocess.run([stow, f'--dir={packages}', f'--target={target}', '--no-folding', 'codex', 'claude'],
                                cwd=ROOT, env=self.env | {'HOME': str(target)}, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for tool in ('codex', 'claude'):
            self.assertTrue((target / f'.oh-my-zsh/custom/completions/_{tool}-as').is_symlink(), 'Stow dropped zsh completion')
        self.assertFalse((target / '.local/bin/._fake-appledouble').exists())


if __name__ == "__main__":
    unittest.main()
