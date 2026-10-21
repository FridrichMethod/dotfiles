"""Dotfiles-content halves of the coding-agent-kit suites, on the real files.

The launcher suites live in the coding-agent-kit submodule and run there on
frozen fixtures. These cases read what only dotfiles owns: the fzf-tab preview,
the alias files, the Stow ignores and the package link that delivers codex-as. The
fixtures are the parts of the launcher suites' setUp they read.
"""

import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "common/coding-agent-kit/.local"
KIT = ROOT / "common/coding-agent-kit/coding-agent-kit"
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
                     "XDG_CONFIG_HOME", "XDG_STATE_HOME", "CODING_AGENT_KIT_CONFIG", "CODING_AGENT_KIT_COLOR",
                     "CODING_AGENT_KIT_USAGE_FILE", "CODING_AGENT_KIT_TOKEN_ID", "CLAUDE_CODE_OAUTH_TOKEN"):
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


PREVIEW = ROOT / "common/zsh/.oh-my-zsh/custom/fzf-tab.zsh"
# fzf-tab runs the preview with the description of each candidate and these.
FAKE_FZF = r"""
import os, subprocess, sys
preview = next(a[len("--preview="):] for a in sys.argv[1:] if a.startswith("--preview="))
header = next((int(a.split("=", 1)[1]) for a in sys.argv[1:] if a.startswith("--header-lines=")), 0)
lines = [line for line in sys.stdin.read().split("\n")[header:] if line]
with open(os.environ["FAKE_FZF_LOG"], "a") as log:
    for number, line in enumerate(lines):
        selected = os.environ["FAKE_FZF_LOG"] + f".{number}"
        open(selected, "w").write(line)
        result = subprocess.run([os.environ["SHELL"], "-c", preview.replace("{f}", selected)],
                                capture_output=True, text=True)
        shown = line.split("\0")[1] if "\0" in line else line
        log.write("=== " + shown + "\n" + result.stdout + result.stderr)
sys.exit(130)
"""


class Enrollment(IsolatedHome):
    def preview_home(self):
        """Two accounts per launcher, a recorded email and a label, and the launchers on PATH."""
        (self.secret / "codex-B.json").write_text('{"tokens": {"access_token": "fabricated-sensitive-access-B"}}')
        (self.secret / "codex-B.json").chmod(0o600)
        for name in ("work", "play"):
            (self.secret / f"claude-{name}").write_text("sk-ant-oat01-fabricated-sensitive-claude\n")
            (self.secret / f"claude-{name}").chmod(0o600)
        state = self.home / ".local/state/coding-agent-kit/accounts"
        state.mkdir(parents=True, mode=0o700)
        for name, data in (("codex-A.json", {"email": "alice@example.com", "plan": "plus"}),
                           ("claude-work.json", {"label": "Work: billing"})):
            (state / name).write_text(json.dumps(data))
            (state / name).chmod(0o600)
        (self.command_bin / "claude-as").symlink_to(SOURCE / "bin/claude-as")

    @unittest.skipIf(os.name == "nt", "zsh and fzf-tab")
    def test_account_preview_shows_account_info_and_never_reads_a_secret(self):
        zsh = shutil.which("zsh")
        if not zsh:
            self.skipTest("zsh not installed")
        self.preview_home()
        # The context fzf-tab looks up for any argument of the launchers: their
        # completions call _describe without _arguments, so it has no tag.
        command = ('source "$1"; zstyle -s :fzf-tab:complete:"$2": fzf-preview preview; word=$3; group=$4; '
                   'realpath="$HOME/.secrets/codex-$word.json"; my-fzf-preview.sh() { print LEAK; }; eval "$preview"')
        cases = (("codex-as", "A", "[Codex accounts]", "A (Codex)\nemail   alice@example.com\nplan    plus\n"
                  "usage   not recorded yet\n"),
                 ("claude-as", "work", "[Claude accounts]", "work (Claude)\nlabel   Work: billing\nusage   not recorded yet\n"),
                 ("codex-as", "exec", "[Codex arguments]", "exec\n"),
                 ("claude-as", "--print", "[Claude arguments]", "--print\n"),
                 # Not an account (a renamed file, a stale completion): the word itself.
                 ("codex-as", "gone", "[Codex accounts]", "gone\n"))
        for tool, word, group, expected in cases:
            with self.subTest(tool=tool, word=word):
                result = subprocess.run([zsh, "-f", "-c", command, "preview", str(PREVIEW), tool, word, group],
                                        cwd=self.cwd, env=self.env, text=True, capture_output=True)
                self.assertEqual((result.returncode, result.stdout, result.stderr), (0, expected, ""))

    @unittest.skipIf(os.name == "nt", "zsh and fzf-tab")
    def test_real_fzf_tab_previews_accounts_through_the_kit(self):
        # Real fzf-tab (FZF_TAB_TEST_DIR names a checkout; the bootstrap clones
        # it to $ZSH_CUSTOM/plugins/fzf-tab, CI's macOS job to the runner's temp)
        # in an interactive zsh, with dotfiles' zstyles and a fake fzf that runs
        # fzf-tab's own preview command.
        zsh, plugin = shutil.which("zsh"), Path(os.environ.get("FZF_TAB_TEST_DIR", "/nonexistent"))
        if not zsh or not (plugin / "fzf-tab.plugin.zsh").is_file():
            self.skipTest("zsh and an fzf-tab checkout in FZF_TAB_TEST_DIR")
        import pty  # POSIX only: native Windows Python has no termios, so not at module level
        self.preview_home()
        log = self.base / "previews.log"
        # fzf-tab splits its fzf-command on spaces, so not below the spaced HOME.
        fake = self.base / "fake-fzf"
        fake.write_text(f"#!{sys.executable}\n" + FAKE_FZF)
        fake.chmod(0o700)
        leak = self.command_bin / "my-fzf-preview.sh"
        leak.write_text(f"#!/bin/sh\necho LEAK >>'{log}'\n")
        leak.chmod(0o700)
        rc = self.base / "zdotdir"
        rc.mkdir()
        (rc / ".zshrc").write_text(
            f"fpath=({ROOT}/common/coding-agent-kit/.oh-my-zsh/custom/completions $fpath)\n"
            f"autoload -Uz compinit && compinit -u -d '{self.base}/zcompdump'\n"
            f"source '{plugin}/fzf-tab.plugin.zsh'\nsource '{PREVIEW}'\n"
            f"zstyle ':fzf-tab:*' fzf-command '{fake}'\nzstyle ':fzf-tab:*' fzf-flags --ansi\nPS1='READY> '\n")
        # The caller's PATH behind the launchers, as in every other case: they
        # need Python 3.11+, which /usr/bin does not have on a macOS runner.
        env = self.env | {"ZDOTDIR": str(rc), "SHELL": zsh, "TERM": "xterm-256color", "FAKE_FZF_LOG": str(log),
                          "TMPPREFIX": str(self.base / "zsh")}
        for line, expected in ((b"codex-as \t", ["=== A  -- alice@example.com", "A (Codex)", "email   alice@example.com",
                                                 "plan    plus", "usage   not recorded yet",
                                                 "=== B", "B (Codex)", "email   not recorded yet",
                                                 "plan    not recorded yet", "usage   not recorded yet"]),
                               (b"claude-as \t", ["=== play", "play (Claude)", "label   not set (claude-as --set-label play LABEL)",
                                                  "usage   not recorded yet", "=== work  -- Work: billing", "work (Claude)",
                                                  "label   Work: billing", "usage   not recorded yet"])):
            with self.subTest(line=line):
                log.unlink(missing_ok=True)
                pid, fd = pty.fork()
                if pid == 0:
                    os.chdir(self.cwd)
                    # No global rc: a distribution zshrc may run its own compinit, which prompts.
                    os.execve(zsh, [zsh, "--no-globalrcs", "-i"], env)
                try:
                    output, deadline = b"", time.monotonic() + 20
                    while b"READY> " not in output and time.monotonic() < deadline:
                        if select.select([fd], [], [], 0.1)[0]:
                            output += os.read(fd, 4096)
                    os.write(fd, line)
                    while not log.exists() and time.monotonic() < deadline:
                        if select.select([fd], [], [], 0.1)[0]:
                            os.read(fd, 4096)
                    time.sleep(0.5)
                finally:
                    os.kill(pid, 9)  # only the test's own interactive zsh
                    os.waitpid(pid, 0)
                    os.close(fd)
                self.assertTrue(log.exists(), "fzf-tab never ran the fake fzf")
                self.assertEqual(log.read_text().splitlines(), expected)

    @unittest.skipIf(os.name == "nt", "GNU Stow")
    def test_real_stow_installs_underscore_completions_and_ignores_appledouble(self):
        stow = shutil.which('stow')
        if not stow:
            self.skipTest('GNU Stow not installed')
        packages = self.base / 'packages'
        target = self.base / 'stowed home'
        target.mkdir(mode=0o700)
        shutil.copytree(ROOT / 'common/coding-agent-kit', packages / 'coding-agent-kit')
        apple = packages / 'coding-agent-kit/.local/bin/._fake-appledouble'
        apple.write_text('fixture')
        result = subprocess.run([stow, f'--dir={packages}', f'--target={target}', '--no-folding', 'coding-agent-kit'],
                                cwd=ROOT, env=self.env | {'HOME': str(target)}, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for tool in ('codex', 'claude'):
            self.assertTrue((target / f'.oh-my-zsh/custom/completions/_{tool}-as').is_symlink(), 'Stow dropped zsh completion')
        self.assertFalse((target / '.local/bin/._fake-appledouble').exists())
        # The package's own ignore file (and, while it stays, the .stowrc line
        # read from cwd) keeps its submodule checkout unstowed.
        self.assertFalse((target / 'coding-agent-kit').exists())


if __name__ == "__main__":
    unittest.main()
