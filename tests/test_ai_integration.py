"""Dotfiles-content halves of the coding-agent-kit suites, on the real files.

The launcher and helper suites live in coding-agent-kit and run there on the
kit's own fixtures. These cases read what only dotfiles owns: the fzf-tab
preview, the alias files and the settings.json commands that run the kit's
Claude helpers. The cases that run the kit need an installed one:
DOTFILES_TEST_KIT_HOME names a home it is installed in, as its installer lays
it out (launchers in .local/bin, zsh completions in
.local/share/zsh/site-functions, helpers in .claude/coding-agent-kit; on
native Windows, the helpers only); CI
installs the real kit there through scripts/payload-update.sh. Without it
those cases skip. The fixtures are the parts of the launcher suites' setUp
they read; they reach the kit only through its installed paths.
"""

import json
import os
from pathlib import Path
import re
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
KIT_HOME = Path(os.environ["DOTFILES_TEST_KIT_HOME"]) if os.environ.get("DOTFILES_TEST_KIT_HOME") else None
SOURCE = KIT_HOME / ".local" if KIT_HOME else None
# The installed release, whose bin/ the launcher links point into.
KIT = SOURCE and (SOURCE / "bin/codex-as").resolve().parents[1]
needs_kit = unittest.skipUnless(KIT_HOME, "no installed coding-agent-kit (DOTFILES_TEST_KIT_HOME)")
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
    # The kit's install.ps1 installs only the Claude helpers on native Windows.
    if not KIT_HOME:
        return
    if os.name == "nt":
        if not (KIT_HOME / ".claude/coding-agent-kit/statusline.cjs").is_file():
            raise RuntimeError(f"DOTFILES_TEST_KIT_HOME={KIT_HOME} has no installed coding-agent-kit helpers.")
    elif not (SOURCE / "bin/codex-as").is_file():
        raise RuntimeError(f"DOTFILES_TEST_KIT_HOME={KIT_HOME} has no installed coding-agent-kit launcher.")


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
        # Linked as the kit's installer links it: the launcher finds its
        # release, and so its lib/, through the link; a copy would stand alone.
        if KIT_HOME:
            (self.command_bin / "codex-as").symlink_to(SOURCE / "bin/codex-as")
        self.cwd = self.base / "current working directory"
        self.cwd.mkdir()
        self.env = os.environ.copy()
        # No configuration of the caller's coding-agent-kit is in reach.
        for name in (*ENV_CONFLICTS, "CODEX_HOME", "CODEX_SQLITE_HOME", "PYTHONPATH", "BASH_ENV", "ENV", "ZDOTDIR",
                     "XDG_CONFIG_HOME", "XDG_STATE_HOME", "CODING_AGENT_KIT_CONFIG", "CODING_AGENT_KIT_COLOR",
                     "CODING_AGENT_KIT_USAGE_FILE", "CODING_AGENT_KIT_TOKEN_ID", "CODING_AGENT_KIT_CLAUDE_PID",
                     "CLAUDE_CODE_OAUTH_TOKEN"):
            self.env.pop(name, None)
        self.env.update(HOME=str(self.home), PATH=os.pathsep.join((str(self.command_bin), self.env["PATH"])))


class CodexAs(IsolatedHome):
    @needs_kit
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
            self.assertIn("Details and manual repair: ", result.stdout)


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

    @needs_kit
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

    @needs_kit
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
        # A hang below fails with its traceback, not the CI job's timeout. An alarm, not a
        # watchdog thread: forking a multi-threaded process can deadlock the child.
        def hung(signum, frame):
            signal.alarm(10)  # again, should the cleanup of the session hang too
            raise TimeoutError("the real fzf-tab case hung")
        self.addCleanup(signal.signal, signal.SIGALRM, signal.signal(signal.SIGALRM, hung))
        self.addCleanup(signal.alarm, 0)
        signal.alarm(120)
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
            f"fpath=({KIT_HOME}/.local/share/zsh/site-functions $fpath)\n"
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
                output = b""
                try:
                    deadline = time.monotonic() + 20
                    while b"READY> " not in output and time.monotonic() < deadline:
                        if select.select([fd], [], [], 0.1)[0]:
                            output += os.read(fd, 4096)
                    os.write(fd, line)
                    while not log.exists() and time.monotonic() < deadline:
                        if select.select([fd], [], [], 0.1)[0]:
                            output += os.read(fd, 4096)
                    time.sleep(0.5)
                finally:
                    # The session pty.fork started (its pid is the process group too): only
                    # the test's own zsh and what it ran. The terminal is closed before the
                    # wait: on macOS and the BSDs the last close of a terminal with unread
                    # output can wait for it to drain, and nothing would read it.
                    try:
                        os.killpg(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    os.close(fd)
                    os.waitpid(pid, 0)
                shown = output.decode(errors="replace")[-2000:]
                self.assertTrue(log.exists(), "fzf-tab never ran the fake fzf; the terminal showed:\n" + shown)
                self.assertEqual(log.read_text().splitlines(), expected, shown)


SETTINGS = ROOT / "common/claude/.claude/settings.json"
# The Claude helpers the kit's installer puts in ~/.claude/coding-agent-kit/.
HELPERS = KIT_HOME / ".claude/coding-agent-kit" if KIT_HOME else None
HELPER_PATH = re.compile(r"/\.claude/coding-agent-kit/([^/'\"\s]+)")


def bash_tool(command):
    return {"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": command}}


# Where settings.json wires each delivered helper, and for each run the JSON
# Claude Code writes to its stdin there (inputs as in the kit's own suite),
# the exit status, and the stream that must carry output (None: neither may).
# A command that cannot load its helper exits 1 instead.
HELPER_RUNS = {
    "statusline.cjs": ("statusLine", [({"model": {"display_name": "Opus"}}, 0, "stdout")]),
    "notify.cjs": ("Notification", [({"hook_event_name": "Notification", "notification_type": "idle_prompt"},
                                     0, "stdout")]),
    "check-git-hooks.cjs": ("PreToolUse", [(bash_tool("git status"), 0, None),
                                           (bash_tool("git commit --no-verify -m test"), 2, "stderr")]),
}


def wired_helpers():
    """(event, command, helper) for the status line and each hook command loading a helper from ~/.claude/coding-agent-kit/."""
    settings = json.loads(SETTINGS.read_text(encoding="utf-8"))
    commands = [("statusLine", settings.get("statusLine", {}).get("command", ""))]
    commands += [(event, hook.get("command", "")) for event, groups in settings.get("hooks", {}).items()
                 for group in groups for hook in group.get("hooks", [])]
    return [(event, command, name) for event, command in commands for name in HELPER_PATH.findall(command)]


class ClaudeHelperWiring(unittest.TestCase):
    def test_settings_wire_each_helper_where_its_runs_say(self):
        wired = wired_helpers()
        self.assertEqual(sorted({name for _, _, name in wired}), sorted(HELPER_RUNS),
                         "settings.json must load exactly the helpers of HELPER_RUNS from ~/.claude/coding-agent-kit/")
        for event, command, name in wired:
            self.assertEqual(event, HELPER_RUNS[name][0], command)

    @needs_kit
    def test_settings_wire_exactly_the_installed_helpers(self):
        delivered = sorted(path.name for path in HELPERS.iterdir())
        for name in delivered:
            self.assertTrue((HELPERS / name).is_file(), f"{HELPERS / name} is not a file")
        self.assertEqual(sorted({name for _, _, name in wired_helpers()}), delivered,
                         "settings.json must load exactly the helpers the installed coding-agent-kit delivers")


class ClaudeHelperCommands(IsolatedHome):
    @needs_kit
    @unittest.skipIf(os.name == "nt", "a POSIX shell runs the commands; tests/claude-customizations.cjs covers Windows")
    def test_settings_commands_run_the_installed_helpers_through_a_shell(self):
        if not shutil.which("node", path=self.env["PATH"]):
            self.skipTest("node not installed")
        # A pre-commit run exports the GIT_DIR of the commit in progress; the
        # status line runs git.
        env = {key: value for key, value in self.env.items() if not key.startswith("GIT_")}

        def run(command, stdin):
            # As Claude Code runs a status line or hook command: the exact
            # string through a shell, the event JSON on stdin.
            return subprocess.run(command, shell=True, cwd=self.cwd, env=env, input=json.dumps(stdin),
                                  capture_output=True, text=True, timeout=60)

        wired = wired_helpers()
        self.assertTrue(wired, "settings.json loads no helper from ~/.claude/coding-agent-kit/")
        installed = self.home / ".claude/coding-agent-kit"
        # Before the install, each command looks for its helper under the
        # spaced HOME and finds none.
        for _, command, name in wired:
            self.assertIn(name, HELPER_RUNS, f"{command} loads no helper the coding-agent-kit delivers")
            first_stdin = HELPER_RUNS[name][1][0][0]
            result = run(command, first_stdin)
            self.assertEqual((result.returncode, result.stdout), (1, ""), command)
            self.assertIn(str(installed / name), result.stderr)
        installed.mkdir(parents=True)
        for path in HELPERS.iterdir():
            shutil.copyfile(path, installed / path.name)  # as the kit's installer copies them
        for _, command, name in wired:
            for stdin, status, stream in HELPER_RUNS[name][1]:
                with self.subTest(helper=name, stdin=stdin):
                    result = run(command, stdin)
                    self.assertEqual(result.returncode, status, result.stderr)
                    if stream:
                        self.assertTrue(getattr(result, stream).strip(), f"{name} wrote nothing to {stream}")
                    else:
                        self.assertEqual((result.stdout, result.stderr), ("", ""))


if __name__ == "__main__":
    unittest.main()
