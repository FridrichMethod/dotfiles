"""The stowed tmux config loads TPM offline and agrees with bootstrap.

Use a private server and a fake TPM: no user's server, plugins, shell startup
files or network are reached. Real upstream plugin smoke checks are manual.
"""
import csv
import os
import shlex
import shutil
import socket
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "common/tmux/.tmux.conf"
TMUX = shutil.which("tmux")
PLUGINS = {
    "tmux-plugins/tpm": "tpm",
    "tmux-plugins/tmux-resurrect": "resurrect.tmux",
    "sainnhe/tmux-fzf": "main.tmux",
    "tmux-plugins/tmux-continuum": "continuum.tmux",
}


def manifest(name):
    with (ROOT / "config/bootstrap" / name).open() as source:
        return {row["id"]: row for row in csv.DictReader(
            (line for line in source if line.strip() and not line.startswith("#")),
            delimiter="\t",
        )}


class PluginProvisioning(unittest.TestCase):
    def test_declared_plugins_are_installed_and_probed_on_unix(self):
        # TPM reads @plugin declarations from the config, not show-options
        # (which contains only the final value of the repeated @plugin key).
        declared = []
        for line in CONFIG.read_text().splitlines():
            words = shlex.split(line, comments=True)
            if words[:3] == ["set", "-g", "@plugin"]:
                declared.append(words[3])
        self.assertEqual(declared, list(PLUGINS))
        clones, probes = manifest("git-clones.tsv"), manifest("tools.tsv")
        for plugin, entry in PLUGINS.items():
            with self.subTest(plugin=plugin):
                name = plugin.split("/")[1]
                self.assertIn(name, clones)
                self.assertIn(name, probes)
                destination = f"$HOME/.tmux/plugins/{name}"
                self.assertEqual(clones[name]["dest"], destination)
                self.assertEqual(clones[name]["url"], f"https://github.com/{plugin}.git")
                self.assertEqual(clones[name]["hosts"], "unix")
                self.assertEqual(probes[name]["probe"], f"file:{destination}/{entry}")
                self.assertEqual(probes[name]["hosts"], "unix")
                self.assertEqual(probes[name]["doc"], "S3-clones")


@unittest.skipUnless(TMUX and os.name == "posix", "optional real tmux is unavailable")
class TmuxConfiguration(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="tmux-", dir="/tmp")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.home = self.root / "home with spaces"
        self.home.mkdir()
        self.config = self.home / ".tmux.conf"
        shutil.copyfile(CONFIG, self.config)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for command in ("git", "curl", "wget"):
            executable = self.bin / command
            executable.write_text('#!/bin/sh\necho unexpected-network >> "$HOME/network"\nexit 99\n')
            executable.chmod(0o755)
        self.env = {
            "HOME": str(self.home), "SHELL": "/bin/sh", "TERM": "xterm-256color",
            "PATH": f"{self.bin}:/usr/bin:/bin", "LC_ALL": "C",
            "XDG_CONFIG_HOME": str(self.home / ".config"),
        }
        self.socket = self.root / "socket"
        self.addCleanup(self.stop_server)
        self.tmux("-f", "/dev/null", "new-session", "-d", "-s", "fixture", "/bin/sh")

    def tmux(self, *args, check=True):
        result = subprocess.run(
            [TMUX, "-S", str(self.socket), *args], env=self.env,
            capture_output=True, text=True, timeout=10,
        )
        if check:
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
        return result.stdout.strip()

    def stop_server(self):
        self.tmux("kill-server", check=False)

    def source(self):
        self.tmux("source-file", str(self.config))
        self.assertFalse((self.home / "network").exists(), "config attempted a network install")

    def option(self, name):
        return self.tmux("show-options", "-gqv", name)

    def test_missing_tpm_keeps_native_tmux_usable_offline(self):
        self.source()
        for name, value in {
            "prefix": "C-b", "mouse": "on", "history-limit": "100000",
            "base-index": "1", "pane-base-index": "1", "renumber-windows": "on",
        }.items():
            with self.subTest(option=name):
                self.assertEqual(self.option(name), value)
        self.assertFalse((self.home / ".tmux").exists())
        self.assertEqual(self.tmux("list-sessions", "-F", "#{session_name}"), "fixture")

    def test_recovery_policy_uses_a_concrete_host_directory(self):
        self.source()
        for name, value in {
            "@resurrect-processes": "false",
            "@resurrect-capture-pane-contents": "off",
            "@resurrect-dir": f"~/.local/share/tmux/resurrect/{socket.gethostname()}",
            "@continuum-save-interval": "15",
            "@continuum-restore": "on", "@continuum-boot": "off",
            "status": "on",
        }.items():
            with self.subTest(option=name):
                self.assertEqual(self.option(name), value)
        self.assertEqual(self.tmux("show-environment", "-g", "TMUX_FZF_ORDER"),
                         "TMUX_FZF_ORDER=session|window|pane")

    def test_tpm_uses_bootstrap_directory_and_reloads_with_spaces_in_home(self):
        tpm = self.home / ".tmux/plugins/tpm/tpm"
        tpm.parent.mkdir(parents=True)
        tpm.write_text(
            '#!/bin/sh\n'
            'printf "%s\\n" "$TMUX_PLUGIN_MANAGER_PATH" >> "$HOME/tpm-loaded"\n'
            f'{shlex.quote(TMUX)} set-option -g @test-tpm-loaded yes\n'
        )
        tpm.chmod(0o755)
        self.source()
        self.source()
        self.assertEqual(self.option("@test-tpm-loaded"), "yes")
        self.assertEqual((self.home / "tpm-loaded").read_text().splitlines(),
                         [str(self.home / ".tmux/plugins") + "/"] * 2)
        self.assertEqual(self.tmux("list-sessions", "-F", "#{session_name}"), "fixture")


if __name__ == "__main__":
    unittest.main()
