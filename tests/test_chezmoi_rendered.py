"""Lint deployed bytes so encoded template names cannot evade parser checks."""

import json
import os
import shutil
import subprocess
import sys
import tomllib
import unittest

from chezmoi_source_support import SourceFixture, expected_entries


# Targets with a shell dialect in tests/fixtures/chezmoi/targets.tsv, per role.
LINTED = {"common-only": 21, "mac": 25, "wsl-ubuntu": 25, "lab-ubuntu": 27,
          "sherlock": 25, "marlowe": 25, "win": 0}


class RenderedSourceTests(unittest.TestCase):
    def test_rendered_syntax_and_format(self):
        # Catch invalid includes/whitespace or lost lint coverage after encoding.
        host = "win" if os.name == "nt" else "mac" if sys.platform == "darwin" else "lab-ubuntu"
        with SourceFixture(host) as fixture:
            result = fixture.run("apply")
            self.assertEqual(result.returncode, 0, result.stderr)
            linted = 0
            for target, entry in expected_entries(host).items():
                path = fixture.destination / target
                content = path.read_bytes()
                with self.subTest(target=target):
                    if target.endswith(".json"):
                        json.loads(content)
                    if target.endswith(".toml"):
                        tomllib.loads(content.decode("utf-8"))
                    if target.endswith(".py"):
                        compile(content, target, "exec")
                    shell = None if entry.shell == "-" else entry.shell
                    if shell:
                        linted += 1
                        self.run_optional(fixture, shell, "-n", str(path))
                        upstream = target in (".p10k.zsh", ".local/bin/my-fzf-preview.sh")
                        if shell != "zsh" and not upstream:
                            self.run_optional(fixture, "shellcheck", "--severity=warning", "--shell=" + shell, str(path))
                        if not upstream:
                            self.run_optional(fixture, "shfmt", "-d", "-i", "4", "-ci", "-ln",
                                              "posix" if shell == "sh" else shell, str(path))
                    if target.endswith(".lua"):
                        self.run_optional(fixture, "stylua", "--check", str(path))
            self.assertEqual(linted, LINTED[host])

    def run_optional(self, fixture, tool, *args):
        executable = shutil.which(tool)
        if executable is None:
            # Optional real tools follow existing host availability; visible subtest skip.
            with self.subTest(tool=tool):
                self.skipTest(f"optional rendered lint tool unavailable: {tool}")
            return
        result = subprocess.run([executable, *args], cwd=fixture.root, env=fixture.env,
                                stdin=subprocess.DEVNULL, capture_output=True, text=True,
                                encoding="utf-8", timeout=30, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
