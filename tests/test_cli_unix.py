"""Unix CLI boundary checks using isolated, harmless backend scripts."""

import os
from pathlib import Path
import pty
import select
import shlex
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]

BACKEND = r'''#!/bin/sh
printf '%s\000' "$@" > "$CLI_ARGV"
pwd -P > "$CLI_CWD"
printf '%s' "${CLI_STDOUT-}"
printf '%s' "${CLI_STDERR-}" >&2
exit "${CLI_STATUS-0}"
'''


class UnixCLI(unittest.TestCase):
    def setUp(self):
        self.assertTrue((ROOT / "dotfiles").is_file(), "absent dispatcher: dotfiles")
        self.temporary = tempfile.TemporaryDirectory(prefix="dotfiles cli ")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.repo = self.base / "checkout with spaces'quote;literal"
        self.repo.mkdir()
        self.cli = self.repo / "dotfiles"
        shutil.copy2(ROOT / "dotfiles", self.cli)
        self.home = self.base / "empty home"
        self.home.mkdir()
        self.bin = self.base / "restricted bin"
        self.bin.mkdir()
        # No Python, chezmoi, Git, installers or real pre-commit on this PATH.
        for name in ("sh", "bash"):
            (self.bin / name).symlink_to(shutil.which(name))
        self.env = {name: value for name, value in os.environ.items()
                    if name not in ("BASH_ENV", "ENV", "CDPATH")}
        self.env.update(HOME=str(self.home), PATH=str(self.bin),
                        CLI_ARGV=str(self.base / "argv"),
                        CLI_CWD=str(self.base / "cwd"), CLI_STDOUT="", CLI_STDERR="",
                        CLI_STATUS="0")
        for backend in ("scripts/commands/doctor.sh", "scripts/commands/setup.sh", "scripts/commands/payloads-sync.sh", "tests/run.sh"):
            self.write(backend, BACKEND)
        self.write_tool("pre-commit", BACKEND)

    def write(self, relative, content):
        path = self.repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def write_tool(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o755)
        return path

    def run_cli(self, *args, env=None, cwd=None, input=None):
        return subprocess.run([str(self.cli), *args], env=self.env | (env or {}),
                              cwd=cwd or self.home, input=input,
                              text=True, capture_output=True, timeout=10)

    def argv(self):
        data = (self.base / "argv").read_bytes()
        return [word.decode() for word in data.split(b"\0")[:-1]] if data else []

    def assert_no_backend(self):
        self.assertFalse((self.base / "argv").exists(), "backend ran for a CLI-only request")

    def test_retired_production_paths_absent(self):
        retired = ("doctor.sh", "setup-host.sh", "scripts/payload-update.sh")
        tracked = subprocess.check_output(
            ["git", "ls-files", "--", *retired], cwd=ROOT, text=True)
        self.assertEqual(tracked, "", "retired paths remain in the staged inventory")
        for relative in retired:
            self.assertFalse(os.path.lexists(ROOT / relative), relative)

    def test_missing_backend_never_uses_retired_path(self):
        for command, backend, retired in (
                (("doctor",), "scripts/commands/doctor.sh", "doctor.sh"),
                (("setup",), "scripts/commands/setup.sh", "setup-host.sh"),
                (("payloads", "sync"), "scripts/commands/payloads-sync.sh", "scripts/payload-update.sh")):
            with self.subTest(command=command):
                target = self.repo / backend
                target.unlink()
                self.write(retired, BACKEND)
                result = self.run_cli(*command)
                self.assertEqual((result.returncode, result.stdout), (1, ""))
                self.assertEqual(len(result.stderr.splitlines()), 1)
                self.assertIn(backend, result.stderr)
                self.assert_no_backend()
                self.write(backend, BACKEND)

    def test_nested_backends_use_their_own_checkout(self):
        for directory in ("lib", "config"):
            shutil.copytree(ROOT / directory, self.repo / directory)
        for relative in ("scripts/commands/doctor.sh", "scripts/commands/setup.sh",
                         "scripts/commands/payloads-sync.sh"):
            shutil.copy2(ROOT / relative, self.repo / relative)
        for command in ("doctor", "setup"):
            result = self.run_cli(command, "--host", "lab-ubuntu", "--list",
                                  env={"PATH": os.environ["PATH"]})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("chezmoi" if command == "doctor" else "H7-deploy", result.stdout)
        result = self.run_cli("payloads", "sync", "not-a-payload",
                              env={"PATH": os.environ["PATH"]})
        self.assertEqual(result.returncode, 1)
        self.assertIn("unknown item", result.stderr)
        self.assertNotIn("missing", result.stderr)

    def test_payload_source_returns_only_selected_root(self):
        self.install_launcher()
        for relative in ("lib/bootstrap/manifest.sh", "lib/bootstrap/platform.sh", "lib/bootstrap/checks.sh"):
            self.write(relative, (ROOT / relative).read_text())
        code = (' . "$1/lib/bootstrap/manifest.sh"; . "$1/lib/bootstrap/platform.sh"; '
                '. "$1/lib/bootstrap/checks.sh"; '
                'bootstrap_payload_source "$1"')

        def selected(status, root):
            result = subprocess.run([shutil.which("bash"), "-c", code, "_", str(self.repo)],
                                    env=self.env, cwd=self.home, text=True, capture_output=True)
            self.assertEqual((result.returncode, result.stdout, result.stderr),
                             (status, "" if root is None else str(root) + "\n", ""))

        selected(0, self.repo)
        other = self.base / "source with 'quote;literal"
        other.mkdir()
        (other / ".chezmoiroot").write_text("home\n")
        self.config.write_text(self.valid_config.replace(str(self.repo), str(other)))
        selected(0, other)
        marker = self.home / ".config/dotfiles/maintenance"
        marker.parent.mkdir()
        marker.touch()
        selected(1, None)
        self.config.unlink()
        selected(0, self.repo)  # Existing early return even during maintenance.
        marker.unlink()
        self.config.write_text("sourceDir = invalid\n")
        selected(1, None)
        self.config.unlink()
        linked = self.base / "linked config"
        linked.write_text(self.valid_config)
        self.config.symlink_to(linked)
        selected(1, None)

    def test_payload_advice_replays_selected_checkout_with_quotes(self):
        self.install_launcher()
        shutil.copytree(ROOT / "lib/bootstrap", self.repo / "lib/bootstrap")
        self.write("config/payloads.tsv", "example\tunix-probe\tfalse\n")
        other = self.base / "other checkout 'quote;literal"
        (other / "scripts/commands").mkdir(parents=True)
        (other / ".chezmoiroot").write_text("home\n")
        shutil.copy2(self.cli, other / "dotfiles")
        (other / "scripts/commands/payloads-sync.sh").write_text(BACKEND)
        code = ('for lib in manifest platform checks steps-common steps-human; do '
                '. "$1/lib/bootstrap/$lib.sh"; done; bootstrap_init "$1"; '
                'STEPS_ROOT=$1; ')
        for selected in (None, self.repo, other):
            with self.subTest(source=selected):
                self.config.unlink(missing_ok=True)
                if selected is not None:
                    self.config.write_text(self.valid_config.replace(str(self.repo), str(selected)))
                env = self.env | {"PATH": os.environ["PATH"], "DOTFILES_PAYLOAD_ITEMS": "example"}
                for operation in ('bootstrap_check_payloads "$1"', "step_H7_payloads_plan"):
                    result = subprocess.run([shutil.which("bash"), "-c", code + operation,
                                             "_", str(self.repo)], env=env, cwd=self.home,
                                            text=True, capture_output=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    if operation.startswith("bootstrap_check"):
                        command = result.stdout.split(": run ", 1)[1].strip()
                        args = shlex.split(command)
                        self.assertEqual(args[-1], "ITEM")
                        args.pop()
                    else:
                        commands = [line for line in result.stdout.splitlines()
                                    if not line.startswith(("#", "HUMAN-"))]
                        self.assertEqual(len(commands), 1, result.stdout)
                        args = shlex.split(commands[0])
                    expected = selected or self.repo
                    self.assertEqual(args, [str(expected / "dotfiles"), "payloads", "sync"])
                    replay = subprocess.run([*args, "literal;$(touch nope)"], env=env,
                                            cwd=self.home, text=True, capture_output=True)
                    self.assertEqual((replay.returncode, replay.stderr), (0, ""))
                    self.assertEqual(self.argv(), ["--now", "literal;$(touch nope)"])

    def test_payload_human_advice_refuses_launcher_directory(self):
        self.install_launcher()
        self.installed.unlink()
        self.installed.mkdir(mode=0o755)
        shutil.copytree(ROOT / "lib/bootstrap", self.repo / "lib/bootstrap")
        code = ('for lib in manifest platform checks steps-common steps-human; do '
                '. "$1/lib/bootstrap/$lib.sh"; done; bootstrap_init "$1"; '
                'STEPS_ROOT=$1; step_H7_payloads_plan')
        result = subprocess.run([shutil.which("bash"), "-c", code, "_", str(self.repo)],
                                env=self.env, cwd=self.home, text=True, capture_output=True)
        self.assertEqual((result.returncode, result.stderr), (0, ""))
        self.assertNotIn("(or sync-payloads", result.stdout)
        commands = [line for line in result.stdout.splitlines()
                    if not line.startswith(("#", "HUMAN-"))]
        self.assertEqual(len(commands), 1, result.stdout)
        self.assertEqual(shlex.split(commands[0]), [str(self.cli), "payloads", "sync"])

    def test_payload_retry_keeps_own_checkout_and_quotes(self):
        self.install_launcher()
        shutil.copy2(ROOT / "scripts/commands/payloads-sync.sh",
                     self.repo / "scripts/commands/payloads-sync.sh")
        self.write("config/payloads.tsv",
                   "example\tunix-probe\tfalse\nexample\tunix-install\tfalse\n")
        other = self.base / "configured elsewhere"
        other.mkdir()
        (other / ".chezmoiroot").write_text("home\n")
        for mode in ("no config", "same", "elsewhere", "missing launcher", "launcher directory"):
            with self.subTest(mode=mode):
                self.config.unlink(missing_ok=True)
                if mode != "no config":
                    selected = other if mode == "elsewhere" else self.repo
                    self.config.write_text(self.valid_config.replace(str(self.repo), str(selected)))
                if mode == "missing launcher":
                    self.installed.unlink()
                elif mode == "launcher directory":
                    self.installed.mkdir(mode=0o755)
                result = self.run_cli("payloads", "sync", "example",
                                      env={"PATH": os.environ["PATH"]})
                self.assertEqual(result.returncode, 1, result.stderr)
                command = result.stderr.split("retry with: ", 1)[1].strip()
                expected = (["sync-payloads", "example"] if mode == "same" else
                            [str(self.cli), "payloads", "sync", "example"])
                self.assertEqual(shlex.split(command), expected)

    def test_help_without_home_config_or_python(self):
        cases = [(), ("--help",), ("-h",), ("help",), ("payloads",), ("dev",)]
        for command in (("doctor",), ("setup",), ("payloads",), ("payloads", "sync"),
                        ("dev",), ("dev", "test"), ("dev", "check")):
            cases.extend([("help", *command), (*command, "--help"), (*command, "-h")])
        for args in cases:
            with self.subTest(args=args):
                result = self.run_cli(*args)
                self.assertEqual((result.returncode, result.stderr), (0, ""))
                self.assertIn("Usage: dotfiles", result.stdout)
                self.assert_no_backend()
        self.assertEqual(list(self.home.iterdir()), [])
        self.assertFalse((self.bin / "python3").exists())

    def test_command_and_option_refusals(self):
        cases = [("Doctor",), ("update",), ("--bogus",), ("--help", "doctor"),
                 ("help", "doctor", "extra"), ("help", "payloads", "nope"),
                 ("help", "dev", "nope"), ("payloads", "nope"), ("dev", "nope"),
                 ("payloads", "sync", "--now"), ("payloads", "sync", "-x"),
                 ("doctor", "literal:--help"), ("setup", "literal:-h"),
                 ("dev", "check", "--ci"), ("dev", "test", "--host", "mac")]
        for command in ("doctor", "setup"):
            cases.extend([(command, "--what-if"), (command, "--confirm"),
                          (command, "--unknown"), (command, "--Host", "mac"),
                          (command, "unexpected")])
        for command, values in (("doctor", ("host", "tier", "platform")),
                                ("setup", ("host", "tier", "only", "skip"))):
            for name in values:
                cases.extend([(command, f"--{name}"), (command, f"--{name}=",),
                              (command, f"--{name}", ""),
                              (command, f"--{name}", "--quiet")])
        for command, flags in (("doctor", ("quiet", "online", "tsv", "list", "smoke")),
                               ("setup", ("yes", "check", "print-manual", "list", "keep-going"))):
            for name in flags:
                cases.append((command, f"--{name}=true"))
        for args in cases:
            with self.subTest(args=args):
                result = self.run_cli(*args)
                self.assertEqual((result.returncode, result.stdout), (2, ""))
                self.assertEqual(len(result.stderr.splitlines()), 1, result.stderr)
                self.assertTrue(result.stderr.startswith("dotfiles:"), result.stderr)
                self.assert_no_backend()

    def test_setup_argv_and_exit_3(self):
        arguments = ["--host", "mac", "--host=lab-ubuntu", "--tier", "core,cli,ai",
                     "--tier=all", "--only", "first step", "--only=second;$(literal)",
                     "--skip", "a*?[x]", "--skip=second", "--check", "--check",
                     "--yes", "--yes", "--keep-going", "--keep-going"]
        result = self.run_cli("setup", *arguments, env={"CLI_STATUS": "3",
                              "CLI_STDOUT": "work remains\n", "CLI_STDERR": "manual steps\n"})
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (3, "work remains\n", "manual steps\n"))
        self.assertEqual(self.argv(), arguments)
        for flag in ("--list", "--print-manual"):
            self.assertEqual(self.run_cli("setup", flag).returncode, 0)
            self.assertEqual(self.argv(), [flag])

    def test_payload_sync_adds_now_once(self):
        for arguments in ([], ["skills"], ["unknown item", "literal;$(touch nope)", "*"],
                          ["literal:--help", "literal:-h"]):
            with self.subTest(arguments=arguments):
                result = self.run_cli("payloads", "sync", *arguments)
                self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))
                self.assertEqual(self.argv(), ["--now", *arguments])
        result = self.run_cli("payloads", "sync", "unknown", env={"CLI_STATUS": "1"})
        self.assertEqual(result.returncode, 1)
        # Upstream lock handling stays in the backend; the frontend preserves its result.
        self.assertEqual(self.run_cli("payloads", "sync", env={"CLI_STATUS": "75"}).returncode, 75)

    def test_doctor_tsv_has_no_banner(self):
        arguments = ["--host=win", "--host", "mac", "--tier=all", "--tier", "core,cli,ai",
                     "--tsv", "--quiet", "--quiet", "--online", "--online", "--smoke", "--list"]
        result = self.run_cli("doctor", *arguments, env={"CLI_STDOUT": "tool\tPASS\n",
                              "CLI_STDERR": "warning\n", "CLI_STATUS": "7"})
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (7, "tool\tPASS\n", "warning\n"))
        self.assertEqual(self.argv(), arguments)
        self.assertEqual(self.run_cli("doctor", "--platform=linux").returncode, 0)
        self.assertEqual(self.argv(), ["--platform=linux"])

    def test_dev_commands_use_selected_checkout(self):
        other = self.base / "other checkout"
        other.mkdir()
        result = self.run_cli("dev", "test", "--ci", "--check-prerequisites", "--ci", cwd=other,
                              env={"CLI_STATUS": "4", "CLI_STDOUT": "test only\n"})
        self.assertEqual((result.returncode, result.stdout, result.stderr), (4, "test only\n", ""))
        self.assertEqual(self.argv(), ["--ci", "--check-prerequisites", "--ci"])
        # tests/run.sh is selected by absolute path, retaining backend cwd behavior.
        self.assertEqual((self.base / "cwd").read_text().strip(), str(other))
        result = self.run_cli("dev", "check", cwd=other,
                              env={"CLI_STATUS": "5", "CLI_STDERR": "check only\n"})
        self.assertEqual((result.returncode, result.stdout, result.stderr), (5, "", "check only\n"))
        self.assertEqual(self.argv(), ["run", "--all-files"])
        self.assertEqual((self.base / "cwd").read_text().strip(), str(self.repo))

    def test_missing_backend_or_tool_fails_once(self):
        for arguments, target in ((("doctor",), self.repo / "scripts/commands/doctor.sh"),
                                  (("setup",), self.repo / "scripts/commands/setup.sh"),
                                  (("payloads", "sync"), self.repo / "scripts/commands/payloads-sync.sh"),
                                  (("dev", "test"), self.repo / "tests/run.sh"),
                                  (("dev", "check"), self.bin / "pre-commit"),
                                  (("doctor",), self.bin / "bash"),
                                  (("payloads", "sync"), self.bin / "sh")):
            with self.subTest(arguments=arguments, target=target):
                renamed = target.with_name(target.name + ".disabled")
                target.rename(renamed)
                try:
                    result = self.run_cli(*arguments)
                finally:
                    renamed.rename(target)
                self.assertEqual((result.returncode, result.stdout), (1, ""))
                self.assertEqual(len(result.stderr.splitlines()), 1, result.stderr)
                self.assertIn(target.name, result.stderr)
                self.assert_no_backend()

    def test_setup_preserves_stdin_tty_and_interrupt(self):
        self.write("scripts/commands/setup.sh", r'''#!/bin/bash
trap 'printf "interrupted\n"; exit 130' INT
if [[ -t 0 && -t 1 && -t 2 ]]; then
    printf 'ready:%s\n' "$$"
else
    exit 9
fi
IFS= read -r answer
printf 'input:%s\n' "$answer"
while :; do IFS= read -r -p 'waiting:' answer; done
''')
        pid, master = pty.fork()
        if pid == 0:
            os.chdir(self.home)
            os.execve(self.cli, [str(self.cli), "setup", "--host", "mac"], self.env)
        reaped = False
        output = b""

        def until(marker):
            nonlocal output
            deadline = time.monotonic() + 10
            while marker not in output:
                self.assertLess(time.monotonic(), deadline, output)
                if select.select([master], [], [], 0.1)[0]:
                    output += os.read(master, 4096)

        try:
            until(f"ready:{pid}\r\n".encode())
            os.write(master, b"literal ; $() *\n")
            until(b"input:literal ; $() *\r\n")
            # read's own prompt synchronizes with its installed signal handler.
            # A printf before read can race Bash's read-handler setup.
            until(b"waiting:")
            os.write(master, b"\x03")
            until(b"interrupted\r\n")
            deadline = time.monotonic() + 10
            while True:
                waited, status = os.waitpid(pid, os.WNOHANG)
                if waited:
                    reaped = True
                    break
                self.assertLess(time.monotonic(), deadline, output)
                time.sleep(0.01)
            self.assertEqual(os.waitstatus_to_exitcode(status), 130)
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)
        finally:
            if not reaped:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(master)

    def install_launcher(self):
        launcher = ROOT / "home/dot_local/bin/executable_dotfiles"
        self.assertTrue(launcher.is_file(), "absent installed launcher")
        self.installed = self.home / ".local/bin/dotfiles"
        self.installed.parent.mkdir(parents=True)
        shutil.copy2(launcher, self.installed)
        (self.repo / ".git").mkdir()
        self.write(".chezmoiroot", "home\n")
        self.write("lib/chezmoi-guard.sh", (ROOT / "lib/chezmoi-guard.sh").read_text())
        self.config = self.home / ".config/chezmoi/chezmoi.toml"
        self.config.parent.mkdir(parents=True)
        self.valid_config = f'destDir = "{self.home}"\nsourceDir = "{self.repo}"\n'
        self.config.write_text(self.valid_config)

    def run_installed(self, *args):
        return subprocess.run([str(self.installed), *args], env=self.env, cwd=self.home,
                              text=True, capture_output=True, timeout=10)

    def test_installed_launcher_selects_configured_worktree_with_spaces(self):
        self.install_launcher()
        # A linked checkout uses a .git file. Neither cwd nor ~/dotfiles is authoritative.
        (self.repo / ".git").rmdir()
        git = shutil.which("git")
        self.assertIsNotNone(git, "git prerequisite for linked-worktree fixture")
        git_env = {key: value for key, value in os.environ.items() if not key.upper().startswith("GIT_")}
        git_env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)

        def fixture_git(*args):
            subprocess.run([git, "-c", "core.hooksPath=", "-c", "commit.gpgsign=false",
                            "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", *args],
                           cwd=self.repo, env=git_env, check=True, capture_output=True, timeout=15)

        fixture_git("init", "--template=")
        fixture_git("add", "--", "dotfiles", ".chezmoiroot", "lib/chezmoi-guard.sh", "scripts/commands/doctor.sh",
                    "scripts/commands/setup.sh", "scripts/commands/payloads-sync.sh", "tests/run.sh")
        fixture_git("commit", "-m", "Synthetic CLI source")
        linked = self.base / "linked worktree with spaces"
        fixture_git("worktree", "add", "--detach", str(linked))
        self.config.write_text(self.valid_config.replace(str(self.repo), str(linked)))
        other = self.home / "dotfiles"
        other.mkdir()
        (other / "dotfiles").write_text("exit 91\n")
        result = self.run_installed("--help")
        self.assertEqual((result.returncode, result.stderr), (0, ""))
        self.assertIn("Usage: dotfiles", result.stdout)
        self.assert_no_backend()
        self.env["CLI_STATUS"] = "3"
        result = self.run_installed("setup", "--host", "mac", "--only", "a step;literal")
        self.assertEqual((result.returncode, result.stdout, result.stderr), (3, "", ""))
        self.assertEqual(self.argv(), ["--host", "mac", "--only", "a step;literal"])

    def test_installed_launcher_refuses_config_and_missing_source_even_for_help(self):
        self.install_launcher()
        cases = {"missing": None, "duplicate": self.valid_config * 2,
                 "foreign home": self.valid_config.replace(str(self.home), str(self.base)),
                 "malformed": self.valid_config.replace('sourceDir = ', 'sourceDir='),
                 "CRLF": self.valid_config.replace("\n", "\r\n")}
        for name, text in cases.items():
            with self.subTest(case=name):
                self.config.unlink(missing_ok=True)
                if text is not None:
                    self.config.write_bytes(text.encode())
                self.assert_installed_refusal()
        self.config.unlink()
        linked = self.base / "linked config"
        linked.write_text(self.valid_config)
        self.config.symlink_to(linked)
        self.assert_installed_refusal()
        self.config.unlink()
        self.config.write_text(self.valid_config)
        for target in (self.repo / "lib/chezmoi-guard.sh", self.cli):
            hidden = target.with_name(target.name + ".hidden")
            target.rename(hidden)
            try:
                self.assert_installed_refusal()
                target.mkdir()
                try:
                    self.assert_installed_refusal()
                finally:
                    target.rmdir()
            finally:
                hidden.rename(target)

    def assert_installed_refusal(self):
        result = self.run_installed("--help")
        self.assertEqual((result.returncode, result.stdout), (1, ""))
        self.assertEqual(len(result.stderr.splitlines()), 1, result.stderr)
        self.assertIn("CHECKOUT/dotfiles", result.stderr)
        self.assert_no_backend()

    def test_legacy_shortcuts_refuse_missing_launcher_without_backend_fallback(self):
        # A configured home with a working old payload hook must still require the launcher.
        (self.repo / ".git").mkdir()
        self.write(".chezmoiroot", "home\n")
        self.write("lib/chezmoi-guard.sh", (ROOT / "lib/chezmoi-guard.sh").read_text())
        config = self.home / ".config/chezmoi/chezmoi.toml"
        config.parent.mkdir(parents=True)
        config.write_text(f'destDir = "{self.home}"\nsourceDir = "{self.repo}"\n')
        result = subprocess.run([shutil.which("sh"), "-c", '. "$1"; eval sync-skills',
                                 "aliases", str(ROOT / "home/dot_aliases")], env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn(".local/bin/dotfiles", result.stderr)
        self.assert_no_backend()


if __name__ == "__main__":
    unittest.main(verbosity=2)
