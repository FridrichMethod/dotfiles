"""Unix CLI boundary checks using isolated, harmless backend scripts."""

import os
from pathlib import Path
import pty
import select
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
        self.base = Path(self.temporary.name)
        self.repo = self.base / "checkout with spaces;literal"
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
        for backend in ("doctor.sh", "setup-host.sh", "scripts/payload-update.sh", "tests/run.sh"):
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
        for arguments, target in ((("doctor",), self.repo / "doctor.sh"),
                                  (("setup",), self.repo / "setup-host.sh"),
                                  (("payloads", "sync"), self.repo / "scripts/payload-update.sh"),
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
        self.write("setup-host.sh", r'''#!/bin/bash
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
