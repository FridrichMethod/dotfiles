"""The stowed tmux config loads TPM offline and agrees with bootstrap.

Use a private server and a fake TPM: no user's server, plugins, shell startup
files or network are reached. Real upstream plugin smoke checks are manual.
"""
import csv
import os
import re
import shlex
import shutil
import socket
import subprocess
import sys
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
CUSTOM_PLUGINS = {
    "catppuccin/tmux": ("catppuccin-tmux", "catppuccin.tmux"),
    "laktak/extrakto": ("extrakto", "extrakto.tmux"),
    "tmux-plugins/tmux-yank": ("tmux-yank", "yank.tmux"),
    "omerxx/tmux-floax": ("tmux-floax", "floax.tmux"),
    "alexwforsythe/tmux-which-key": ("tmux-which-key", "plugin.sh.tmux"),
    "tmux-plugins/tmux-cpu": ("tmux-cpu", "cpu.tmux"),
    "tmux-plugins/tmux-battery": ("tmux-battery", "battery.tmux"),
}


def manifest(name):
    with (ROOT / "config/bootstrap" / name).open() as source:
        return {row["id"]: row for row in csv.DictReader(
            (line for line in source if line.strip() and not line.startswith("#")),
            delimiter="\t",
        )}


class PluginProvisioning(unittest.TestCase):
    def test_custom_plugins_have_matching_unix_installation_and_probes(self):
        clones, probes = manifest("git-clones.tsv"), manifest("tools.tsv")
        config = "\n".join(path.read_text() for path in
                           (ROOT / "common/tmux").rglob("*.conf"))
        for plugin, (identifier, entry) in CUSTOM_PLUGINS.items():
            with self.subTest(plugin=plugin):
                self.assertIn(plugin, config)
                self.assertIn(identifier, clones)
                self.assertIn(identifier, probes)
                destination = f"$HOME/.tmux/plugins/{plugin.split('/')[1]}"
                self.assertEqual(clones[identifier]["dest"], destination)
                self.assertEqual(clones[identifier]["url"], f"https://github.com/{plugin}.git")
                self.assertEqual(clones[identifier]["hosts"], "unix")
                self.assertEqual(probes[identifier]["probe"], f"file:{destination}/{entry}")
                self.assertEqual(probes[identifier]["hosts"], "unix")
                self.assertEqual(probes[identifier]["doc"], "S3-clones")

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


class VersionFloor(unittest.TestCase):
    def test_manifest_floor_replaces_runtime_version_gates(self):
        # The config uses tmux 3.4 menu styles, popups and display-menu without
        # checks; hpc-login-env.yml mirrors this floor (test_bootstrap_manifest).
        for path in sorted((ROOT / "common/tmux").rglob("*")):
            if path.is_file():
                with self.subTest(path=str(path.relative_to(ROOT))):
                    self.assertNotRegex(path.read_text(encoding="utf-8"),
                                        r"#\{version\}|tmux\s+-V")
        self.assertEqual(manifest("tools.tsv")["tmux"]["floor"], "3.4")


@unittest.skipUnless(TMUX and os.name == "posix", "optional real tmux is unavailable")
class TmuxConfiguration(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="tmux-", dir="/tmp")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.home = self.root / "home with spaces"
        self.home.mkdir()
        self.config = self.home / ".tmux.conf"
        shutil.copytree(ROOT / "common/tmux", self.home, dirs_exist_ok=True)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        # Config shell commands need the native tool on this isolated PATH.
        (self.bin / "tmux").symlink_to(TMUX)
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

    def test_native_theme_and_copy_keys_work_without_any_plugins(self):
        self.source()
        self.assertIn("bg=default", self.option("status-style"))
        self.assertIn("#cba6f7", self.option("pane-active-border-style"))
        self.assertEqual(self.option("mode-keys"), "vi")
        self.assertIn("copy-selection", self.tmux("list-keys", "-T", "copy-mode-vi", "y"))
        self.assertIn("COPY", self.option("status-left"))
        self.assertIn("ZOOM", self.option("status-left"))
        self.assertEqual(self.option("set-clipboard"), "on")
        # Reload must preserve every native pane and the ordinary previous-window key.
        before = self.tmux("list-panes", "-a", "-F", "#{pane_id}")
        self.source()
        self.assertEqual(before, self.tmux("list-panes", "-a", "-F", "#{pane_id}"))
        self.assertIn("previous-window", self.tmux("list-keys", "-T", "prefix", "p"))

    def test_metric_jobs_survive_plugin_status_rewriters_with_spaces_in_home(self):
        scripts = self.home / ".tmux/plugins/tmux-cpu/scripts"
        scripts.mkdir(parents=True)
        for metric in ("cpu", "ram"):
            script = scripts / f"{metric}_percentage.sh"
            script.write_text('#!/bin/sh\nprintf "42%%"\n')
            script.chmod(0o755)
        self.source()
        # CPU, battery and continuum read status via show-options before
        # writing it back. This exposes tmux's literal-dollar escaping.
        for _ in range(3):
            self.tmux("set-option", "-g", "status-right", self.option("status-right"))
        commands = re.findall(r"#\((python3 .*?)\)", self.option("status-right"))
        self.assertGreaterEqual(len(commands), 2)
        for command in commands:
            expanded = self.tmux("display-message", "-p", command)
            result = subprocess.run(expanded, shell=True, env=self.env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "42%")

    def test_menu_autobuild_is_disabled_without_startup_installers(self):
        self.source()
        self.assertEqual(self.option("@tmux-which-key-disable-autobuild"), "1")
        self.assertFalse((self.home / ".tmux/plugins/tmux-which-key").exists())
        binding = self.tmux("list-keys", "-T", "prefix", "Space")
        self.assertIn("display-menu", binding)
        self.assertIn("+Sessions", binding)

    def test_floor_features_load_unconditionally(self):
        self.source()
        self.assertEqual(self.option("@tpm_plugins").split()[-3:], [
            "alexwforsythe/tmux-which-key", "catppuccin/tmux", "omerxx/tmux-floax"])
        for name, value in {
            "popup-style": "bg=#1e1e2e,fg=#cdd6f4", "popup-border-style": "fg=#cba6f7",
            "popup-border-lines": "rounded", "menu-style": "bg=#1e1e2e,fg=#cdd6f4",
            "menu-selected-style": "bg=#cba6f7,fg=#1e1e2e,bold",
            "menu-border-style": "fg=#cba6f7", "menu-border-lines": "rounded",
            "@extrakto_clip_mode": "bg",
        }.items():
            with self.subTest(option=name):
                self.assertEqual(self.option(name), value)
        # FloaX's corrected bindings load only once its shipped script exists.
        self.assertEqual(self.tmux("list-keys", "-T", "prefix", "M-f", check=False), "")
        floax = self.home / ".tmux/plugins/tmux-floax/scripts/floax.sh"
        floax.parent.mkdir(parents=True)
        floax.write_text("#!/bin/sh\n")
        floax.chmod(0o755)
        # Like tmux-yank, extrakto's OSC 52 choice must see a session-only SSH
        # client; tmux expands "$VAR" itself from the global environment.
        self.tmux("set-environment", "-t", "fixture", "SSH_CONNECTION", "fixture-ssh")
        self.source()
        self.assertEqual(self.option("@extrakto_clip_mode"), "tmux_osc52")
        self.assertIn("scripts/floax.sh", self.tmux("list-keys", "-T", "prefix", "M-f"))
        tools = shlex.split(self.tmux("display-message", "-p", "#{@wk_menu_tools}"))
        self.assertIn("Floating shell (M-f)", tools)

    def test_optional_plugin_registration_is_idempotent_and_remote_aware(self):
        for command in ("fzf", "pbcopy"):
            executable = self.bin / command
            executable.write_text("#!/bin/sh\nexit 0\n")
            executable.chmod(0o755)
        self.source()
        first = self.option("@tpm_plugins").split()
        self.assertIn("laktak/extrakto", first)
        self.assertIn("tmux-plugins/tmux-yank", first)
        self.source()
        self.assertEqual(first, self.option("@tpm_plugins").split())
        self.assertEqual(len(first), len(set(first)))
        # Sessions retain removals from update-environment, which override a
        # server-global value. Model the SSH client's session environment.
        self.tmux("set-environment", "-t", "fixture", "SSH_CONNECTION",
                  "127.0.0.1 1234 127.0.0.1 22")
        self.source()
        self.assertNotIn("tmux-plugins/tmux-yank", self.option("@tpm_plugins").split())

    def test_remote_reload_removes_previous_desktop_clipboard_bindings(self):
        for table, key in (("prefix", "y"), ("prefix", "Y"),
                           ("copy-mode", "MouseDragEnd1Pane"),
                           ("copy-mode-vi", "MouseDragEnd1Pane")):
            self.tmux("bind-key", "-T", table, key, "run-shell", "desktop-clipboard-marker")
        self.tmux("set-environment", "-t", "fixture", "SSH_CONNECTION", "fixture-ssh")
        self.source()
        self.assertNotIn("desktop-clipboard-marker", self.tmux("list-keys"))

    def test_menu_actions_preserve_quoted_directory_without_executing_its_text(self):
        self.source()
        directory = self.root / 'space \\"; set -g @cwd-injected yes; #'
        directory.mkdir()
        origin = self.tmux("new-window", "-P", "-F", "#{pane_id}",
                           "-c", str(directory), "/bin/sh")
        for menu, label in (("windows", "New here"),
                            ("panes", "Split side by side"),
                            ("panes", "Split top / bottom")):
            with self.subTest(action=label):
                items = shlex.split(self.tmux("display-message", "-p", f"#{{@wk_menu_{menu}}}"))
                action = items[items.index(label) + 2]
                # display-menu expands the action's formats before parsing it.
                expanded = self.tmux("display-message", "-p", "-t", origin, action)
                command = self.root / "menu-action.conf"
                command.write_text(expanded + "\n")
                before = set(self.tmux("list-panes", "-a", "-F", "#{pane_id}").splitlines())
                self.tmux("source-file", str(command))
                after = set(self.tmux("list-panes", "-a", "-F", "#{pane_id}").splitlines())
                self.assertEqual(len(after - before), 1)
                pane = (after - before).pop()
                self.assertEqual(self.tmux("display-message", "-p", "-t", pane,
                                           "#{pane_current_path}"), str(directory))
                self.assertEqual(self.option("@cwd-injected"), "")

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


@unittest.skipUnless(os.name == "posix", "Unix-only metric forwarder")
class MetricForwarding(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="tmux-metric-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.home = self.root / "home with spaces"
        self.home.mkdir()
        self.scripts = self.home / ".tmux/plugins/tmux-cpu/scripts"
        self.scripts.mkdir(parents=True)
        script = self.scripts / "cpu_percentage.sh"
        script.write_text('#!/bin/sh\nprintf "%s" "$TMPDIR" > "$HOME/forwarded-tmpdir"\nprintf "42%%"\n')
        script.chmod(0o755)
        self.env = {"HOME": str(self.home), "PATH": "/usr/bin:/bin",
                    "TMPDIR": str(self.root / "shared-temp")}
        self.forwarder = ROOT / "common/tmux/.config/tmux/metric.py"

    def run_metric(self, argument="cpu"):
        result = subprocess.run([sys.executable, "-I", "-B", str(self.forwarder), argument],
                                env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        return result.stdout

    def test_upstream_metric_uses_private_cache_without_changing_host_tmpdir(self):
        self.assertEqual(self.run_metric(), "42%")
        cache = Path((self.home / "forwarded-tmpdir").read_text())
        self.assertNotEqual(str(cache), self.env["TMPDIR"])
        self.assertEqual(cache.stat().st_mode & 0o777, 0o700)
        self.assertEqual(cache.stat().st_uid, os.getuid())
        self.assertEqual(self.env["TMPDIR"], str(self.root / "shared-temp"))

    def test_symlink_or_shared_cache_is_refused_without_running_upstream(self):
        cache = self.home / ".cache/tmux-metrics"
        cache.parent.mkdir()
        outside = self.root / "outside"
        outside.mkdir()
        cache.symlink_to(outside, target_is_directory=True)
        self.assertEqual(self.run_metric(), "")
        self.assertFalse((self.home / "forwarded-tmpdir").exists())
        cache.unlink()
        cache.mkdir(mode=0o755)
        cache.chmod(0o755)
        self.assertEqual(self.run_metric(), "")
        self.assertEqual(cache.stat().st_mode & 0o777, 0o755)
        self.assertFalse((self.home / "forwarded-tmpdir").exists())

if __name__ == "__main__":
    unittest.main()
