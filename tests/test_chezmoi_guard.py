"""Legacy writers cannot reclaim an explicitly handed-over destination."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipIf(os.name == "nt", "POSIX wrapper execution")
class WriterGuardTests(unittest.TestCase):
    def test_root_ancestor_does_not_become_a_windows_unc_path(self):
        # Git Bash treats //.config as UNC, not the local POSIX root.
        # Record the actual shell predicates without querying a network path.
        command = '[() { printf "%s\\n" "$2"; return 1; }; . "$1"; '
        command += 'dotfiles_native_owned /; dotfiles_maintenance_active /'
        result = subprocess.run(["bash", "--noprofile", "--norc", "-c", command,
                                 "guard", str(ROOT / "lib/chezmoi-guard.sh")],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.stdout.splitlines(), ["/.config/dotfiles/native"] * 2 +
                         ["/.config/dotfiles/maintenance"] * 2)

    def test_native_binding_requires_exactly_three_terminated_lines(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary).resolve()
            marker = home / ".config/dotfiles/native"
            marker.parent.mkdir(parents=True)
            (home / ".chezmoiroot").write_text("home\n")
            binding = f"dotfiles-chezmoi-v1\n{home}\n{home}\n".encode()
            for data, expected in ((binding, 0), (binding + b"unterminated", 1),
                                   (binding + b"\n", 1), (binding[:-1], 1)):
                with self.subTest(data=data):
                    marker.write_bytes(data)
                    result = subprocess.run(["sh", "-c", '. "$1"; dotfiles_native_source "$2"',
                                             "guard", str(ROOT / "lib/chezmoi-guard.sh"), str(home)],
                                            capture_output=True, timeout=15)
                    self.assertEqual(result.returncode, expected)

    def test_logins_start_no_payload_run_and_keep_the_update_dispatch(self):
        # No profile path runs a payload hook, the bound source's or a stale
        # DOTFILES_DIR's, with or without Sherlock's overlay, whose site rule
        # forbids detached login-node workers; the update dispatch stays. zsh
        # (the .zshrc tail) is in the native takeover suite.
        with tempfile.TemporaryDirectory() as temporary:
            # macOS TMPDIR may use /var rather than canonical /private/var.
            root = Path(temporary).resolve()
            home, source, stale = (root / name for name in ("home", "source", "stale"))
            trace = root / "trace"
            for path in (home / ".config/dotfiles", home / ".config/sh", source / "scripts",
                         source / "lib", stale / "scripts"):
                path.mkdir(parents=True)
            (source / ".chezmoiroot").write_text("home\n")
            shutil.copyfile(ROOT / "lib/chezmoi-guard.sh", source / "lib/chezmoi-guard.sh")
            for checkout, name in ((source, "bound"), (stale, "stale")):
                for hook in ("chezmoi-update", "dotfiles-update", "payload-update"):
                    (checkout / f"scripts/{hook}.sh").write_text(f'printf "%s\\n" "{name} {hook}" >>"$TRACE"\n')
            marker, overlay = home / ".config/dotfiles/native", home / ".config/sh/.profile"
            env = {"HOME": str(home), "PATH": os.defpath, "TERM": "dumb", "SCRATCH": "",
                   "DOTFILES_DIR": str(stale), "TRACE": str(trace)}
            for sherlock in (False, True):
                if sherlock:
                    shutil.copyfile(ROOT / "sherlock/sh/.config/sh/.profile", overlay)
                for native in (True, False):
                    if native:
                        marker.write_text(f"dotfiles-chezmoi-v1\n{home}\n{source}\n")
                    else:
                        marker.unlink()
                    for shell in ("sh", "bash"):
                        with self.subTest(sherlock=sherlock, native=native, shell=shell):
                            trace.unlink(missing_ok=True)
                            flags = ["--noprofile", "--norc"] if shell == "bash" else []
                            result = subprocess.run([shell, *flags, "-i", "-c", '. "$1"', "profile",
                                                     str(ROOT / "common/sh/.profile")],
                                                    env=env, stdin=subprocess.DEVNULL, capture_output=True,
                                                    text=True, timeout=15)
                            self.assertEqual(result.returncode, 0, result.stderr)
                            self.assertEqual(trace.read_text().splitlines(),
                                             ["bound chezmoi-update" if native else "stale dotfiles-update"])

    def test_sync_payload_commands_run_only_the_validated_native_source(self):
        # sync-payloads/sync-skills resolve the hook as the login dispatcher
        # does: a valid marker's source wins over a stale DOTFILES_DIR, whose
        # guard and hook never run; an invalid marker refuses before any hook;
        # maintenance surfaces the bound hook's own refusal before any state.
        # tests/shell-profile.sh covers an unmarked home's DOTFILES_DIR.
        # Absolute paths: the children run with PATH=os.defpath, which may lack a
        # shell found here (an HPC login env provides zsh).
        shells = {name: path for name in ("sh", "bash", "zsh") if (path := shutil.which(name))}
        refusal = "[dotfiles] [error] Native home binding is invalid; payload update refused.\n"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            home, source, stale = (root / name for name in ("home", "bound source", "stale"))
            trace, state = root / "trace", root / "state"
            for path in (home / ".config/dotfiles", source / "scripts", source / "lib",
                         stale / "scripts", stale / "lib"):
                path.mkdir(parents=True)
            (source / ".chezmoiroot").write_text("home\n")
            shutil.copyfile(ROOT / "lib/chezmoi-guard.sh", source / "lib/chezmoi-guard.sh")
            for checkout, name in ((source, "bound"), (stale, "stale")):
                (checkout / "scripts/payload-update.sh").write_text(
                    f'printf "{name} %s\\n" "$*" >>"$TRACE"\nexit 4\n')
            (stale / "lib/chezmoi-guard.sh").write_text('printf "stale-guard\\n" >>"$TRACE"\n')
            marker = home / ".config/dotfiles/native"
            valid = f"dotfiles-chezmoi-v1\n{home}\n{source}\n".encode()
            env = {"HOME": str(home), "PATH": os.defpath, "DOTFILES_DIR": str(stale),
                   "TRACE": str(trace), "XDG_STATE_HOME": str(state)}
            # eval: zsh does not expand an alias defined earlier in one -c string.
            code = ('[ -z "${BASH_VERSION-}" ] || shopt -s expand_aliases; . "$1"; '
                    'eval "sync-payloads kit pymol"; first=$?; eval sync-skills; '
                    'printf "%s %s\\n" "$first" "$?"')

            def run(shell):
                trace.unlink(missing_ok=True)
                result = subprocess.run([shells[shell], *(["-f"] if shell == "zsh" else []), "-c", code,
                                         "aliases", str(ROOT / "common/sh/.aliases")],
                                        env=env, stdin=subprocess.DEVNULL, capture_output=True,
                                        text=True, timeout=15)
                return result, trace.read_text().splitlines() if trace.exists() else []

            def bind(content=None, kind="file"):
                if marker.is_symlink() or marker.is_file():
                    marker.unlink()
                elif marker.is_dir():
                    marker.rmdir()
                if kind == "symlink":
                    (root / "linked marker").write_bytes(valid)
                    marker.symlink_to(root / "linked marker")
                elif kind == "directory":
                    marker.mkdir()
                elif content is not None:
                    marker.write_bytes(content)

            invalid = {"unterminated extra": (valid + b"extra", "file"),
                       "other version": (valid.replace(b"-v1", b"-v2"), "file"),
                       "relative source": (f"dotfiles-chezmoi-v1\n{home}\nstale\n".encode(), "file"),
                       "other home": (f"dotfiles-chezmoi-v1\n{root}\n{source}\n".encode(), "file"),
                       "symlink": (None, "symlink"), "directory": (None, "directory")}
            for shell in shells:
                with self.subTest(shell=shell, binding="valid non-default source"):
                    bind(valid)
                    result, events = run(shell)
                    self.assertEqual((result.stdout, result.stderr), ("4 4\n", ""))
                    self.assertEqual(events, ["bound --now kit pymol", "bound --now skills"])
                for name, (content, kind) in invalid.items():
                    with self.subTest(shell=shell, binding=name):
                        bind(content, kind)
                        result, events = run(shell)
                        self.assertEqual((result.stdout, result.stderr), ("1 1\n", refusal * 2))
                        self.assertEqual(events, [])
            bind(valid)
            (home / ".config/dotfiles/maintenance").touch()
            shutil.copyfile(ROOT / "scripts/payload-update.sh", source / "scripts/payload-update.sh")
            for shell in shells:
                with self.subTest(shell=shell, binding="maintenance"):
                    result, events = run(shell)
                    self.assertEqual(result.stdout, "1 1\n")
                    self.assertEqual(result.stderr,
                                     "dotfiles: payload update refused during maintenance.\n" * 2)
                    self.assertEqual(events, [])
                    self.assertFalse(state.exists())

    def test_maintenance_refuses_an_explicit_payload_run_before_it_starts(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            marker = home / ".config/dotfiles/maintenance"
            marker.parent.mkdir(parents=True)
            marker.touch()
            env = {"HOME": str(home), "PATH": os.defpath, "XDG_STATE_HOME": str(home / "state")}
            result = subprocess.run(["sh", str(ROOT / "scripts/payload-update.sh"), "--now", "not-a-payload"],
                                    env=env, stdin=subprocess.DEVNULL, capture_output=True, timeout=15)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stderr, b"dotfiles: payload update refused during maintenance.\n")
            self.assertEqual(sorted(path.name for path in home.iterdir()), [".config"])

    def test_direct_backend_refuses_before_portable_migration_write(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            marker = home / ".config/dotfiles/native"
            marker.parent.mkdir(parents=True)
            marker.write_text("partial")
            source = home / "portable.toml"
            source.write_bytes((ROOT / "common/codex/.codex/config.toml").read_bytes() + b'\nlocal = true\n')
            live = home / ".codex/config.toml"
            live.parent.mkdir()
            live.write_bytes(b'local = false\n')
            before = source.read_bytes(), live.read_bytes()
            result = subprocess.run([os.environ.get("DOTFILES_SYNC_PYTHON", sys.executable),
                                     "-I", "-B", str(ROOT / "lib/config_sync.py"),
                                     "codex-config-sync", "--migrate-portable", str(source), str(live)],
                                    stdin=subprocess.DEVNULL, capture_output=True, timeout=15)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"legacy write refused", result.stderr)
            self.assertEqual((source.read_bytes(), live.read_bytes()), before)

    def test_four_explicit_live_writers_refuse_native_and_maintenance_homes(self):
        cases = (
            ("common/claude/.local/bin/claude-settings-sync", b'{"permissions":{"allow":[],"ask":[]}}', ".claude/settings.json", b'{}'),
            ("common/codex/.local/bin/codex-config-sync", (ROOT / "common/codex/.codex/config.toml").read_bytes(), ".codex/config.toml", b'local = true\n'),
            ("common/codex/.local/bin/codex-rules-sync", b'prefix_rule(pattern=["fixture"], decision="prompt")\n', ".codex/rules/portable.rules", b'# old\n'),
            ("lab-ubuntu/fcitx5/.local/bin/fcitx5-profile-sync", b'[Groups/0]\nName=Default\n', ".config/fcitx5/profile", b'# old\n'),
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for marker in ("native", "maintenance"):
                for wrapper, portable, relative, live_bytes in cases:
                    with self.subTest(marker=marker, wrapper=wrapper):
                        home = root / marker / Path(wrapper).name
                        guard = home / ".config/dotfiles" / marker
                        guard.parent.mkdir(parents=True)
                        guard.write_text("incomplete handover\n")
                        live = home / relative
                        live.parent.mkdir(parents=True, exist_ok=True)
                        live.write_bytes(live_bytes)
                        source = home.parent / (Path(wrapper).name + "-portable")
                        source.write_bytes(portable)
                        env = {"HOME": str(root / "unrelated-home"), "PATH": os.defpath,
                               "DOTFILES_SYNC_PYTHON": os.environ.get("DOTFILES_SYNC_PYTHON", sys.executable)}
                        result = subprocess.run(["sh", str(ROOT / wrapper), str(source), str(live)],
                                                env=env, stdin=subprocess.DEVNULL, capture_output=True,
                                                timeout=15)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn(b"legacy write refused", result.stderr)
                        self.assertEqual(live.read_bytes(), live_bytes)
                        self.assertEqual(source.read_bytes(), portable)

    def test_guard_uses_destination_not_operator_home_and_resolves_parent_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            protected = root / "native home"
            marker = protected / ".config/dotfiles/native"
            marker.parent.mkdir(parents=True)
            marker.write_text("incomplete")
            target_parent = protected / ".claude"
            target_parent.mkdir()
            alias = root / "alias"
            alias.symlink_to(target_parent, target_is_directory=True)
            free = root / "free"
            free.mkdir()
            env = {"HOME": str(protected), "PATH": os.defpath}
            for target, expected in ((free / "config", 0), (alias / "settings.json", 1)):
                result = subprocess.run(["sh", "-c", '. "$1"; dotfiles_legacy_write_allowed "$2"',
                                         "guard", str(ROOT / "lib/chezmoi-guard.sh"), str(target)],
                                        env=env, capture_output=True, timeout=15)
                self.assertEqual(result.returncode, expected, result.stderr)


if __name__ == "__main__":
    unittest.main()
