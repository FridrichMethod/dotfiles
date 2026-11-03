"""Native candidate source contracts; all state belongs to disposable fixtures."""

import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tomllib
import unittest

from chezmoi_source_support import (
    AI_MUTABLE, COUNTS, ROOT, ROLES, SourceFixture, copy_controls, expected_entries,
    fixture_git_env, indexed_modes, inventory, inventory_problems, snapshot,
)

from chezmoi_support import ChezmoiFixture


class SourceContractTests(unittest.TestCase):
    def test_literal_bridge_in_linked_worktree_with_spaces(self):
        # Catch sourceDir/workingTree confusion and accidental template evaluation.
        git = shutil.which("git")
        self.assertIsNotNone(git, "git is required for the linked-worktree contract")
        with ChezmoiFixture() as fixture:
            repository = fixture.root / "original repository"
            repository.mkdir()
            (repository / "home").mkdir()
            shutil.copyfile(ROOT / ".chezmoiroot", repository / ".chezmoiroot")
            shutil.copyfile(ROOT / ".chezmoiversion", repository / ".chezmoiversion")
            original = b'quotes="literal"\n{{ not_a_template }}\r\n'
            (repository / "canonical.txt").write_bytes(original)
            (repository / "home/dot_probe.tmpl").write_text(
                '{{- include (joinPath .chezmoi.workingTree "canonical.txt") -}}\n',
                encoding="utf-8",
            )
            env = fixture_git_env(fixture.env)
            def run_git(*args):
                subprocess.run([git, "-c", "user.name=Fixture", "-c",
                                "user.email=fixture@example.invalid", "-c",
                                "commit.gpgsign=false", "-c", "core.hooksPath=",
                                *args], cwd=repository, env=env, check=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
            run_git("init", "--template=")
            run_git("add", ".")
            run_git("commit", "-m", "Synthetic bridge fixture")
            linked = fixture.root / "linked worktree with spaces"
            run_git("worktree", "add", "--detach", str(linked))
            fixture.source = linked
            result = fixture.run("apply")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((fixture.destination / ".probe").read_bytes(), original)
            self.assertEqual((repository / "canonical.txt").read_bytes(), original)
            self.assertEqual((linked / "canonical.txt").read_bytes(), original)
            self.assertEqual(fixture.run("diff").stdout, "")

    def test_unselected_invalid_and_incompatible_hosts_fail_before_writing(self):
        compatible = {
            "Linux": {"common-only", "wsl-ubuntu", "lab-ubuntu", "sherlock", "marlowe"},
            "Darwin": {"common-only", "mac"}, "Windows": {"win"},
        }[platform.system()]
        configs = ["", '[data]\nhost = ""\n', '[data]\nhost = "guess"\n',
                   '[data]\nhost = 1\n', '[data]\nhost = true\n',
                   '[data]\nhost = []\n', '[data]\nhost = {}\n']
        configs.extend(f'[data]\nhost = "{role}"\n' for role in ROLES if role not in compatible)
        for config in configs:
            with self.subTest(config=config), ChezmoiFixture() as fixture:
                copy_controls(fixture.source)
                fixture.config.write_text(config, encoding="utf-8")
                fixture.env["DOTFILES_HOST"] = next(iter(compatible))
                result = fixture.run("apply")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("host", result.stderr.lower())
                self.assertEqual(list(fixture.destination.iterdir()), [])

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_inventory_matches_exact_index_paths_applicability_and_counts(self):
        self.assertEqual(inventory_problems(inventory(), indexed_modes()), [])
        # All configuration targets are present; compatibility helpers stay out.
        omitted = {entry.source for entry in inventory() if entry.category == "C"}
        self.assertEqual(omitted, {
            "common/claude/.local/bin/claude-settings-sync",
            "common/codex/.local/bin/codex-config-sync",
            "common/codex/.local/bin/codex-rules-sync",
            "lab-ubuntu/fcitx5/.local/bin/fcitx5-profile-sync",
        })

    def check_role(self, role, os_override=None):
        with SourceFixture(role, native_os=os_override) as fixture:
            expected = expected_entries(role)
            self.assertEqual(len(expected), COUNTS[role])
            self.assertEqual(list(Path(fixture.env["PATH"]).iterdir()), [])
            self.assertFalse((fixture.root / ".venv-sync").exists())
            before = snapshot(fixture.source)
            unsupported = fixture.run("managed", "--include=symlinks,scripts", "--nul-path-separator")
            self.assert_success(unsupported)
            self.assertEqual(unsupported.stdout, "")
            modes = indexed_modes()
            managed = fixture.run("managed", "--include=files", "--nul-path-separator")
            self.assert_success(managed)
            # Native managed output uses platform separators; inventory uses '/'.
            self.assertEqual({path.replace("\\", "/") for path in managed.stdout.split("\0") if path}, set(expected))
            unmanaged = {
                ".ssh/id_fixture": b"synthetic private sibling\n",
                ".ssh/known_hosts": b"synthetic host trust sibling\n",
                ".ssh/config.d/unmanaged.conf": b"synthetic connection sibling\n",
                ".claude/session-state.json": b'{"synthetic":true}\n',
                ".codex/auth.json": b'{"synthetic":"app-owned"}\n',
                ".codex/rules/default.rules": b"synthetic local policy sibling\n",
                ".codex/pets/unmanaged/metadata": b"synthetic local pet\n",
                ".config/fcitx5/conf/unmanaged.conf": b"synthetic app state\n",
                ".oh-my-zsh/oh-my-zsh.sh": b"synthetic external owner\n",
                ".tmux/plugins/unmanaged/plugin": b"synthetic external plugin\n",
            }
            for name, content in unmanaged.items():
                target = fixture.destination / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(content)
            # The native modifies own policy while preserving these live leaves.
            (fixture.destination / ".claude/settings.json").write_bytes(
                b'{"model":"fixture-local","fixture_unknown":{"keep":false}}\n')
            (fixture.destination / ".codex/config.toml").write_bytes(
                b'model = "fixture-local"\n[fixture_unknown]\nkeep = false\n')
            self.assert_success(fixture.run("apply"))
            files = {path.relative_to(fixture.destination).as_posix()
                     for path in fixture.destination.rglob("*") if path.is_file()}
            self.assertEqual(files, set(expected) | set(unmanaged))
            for name, entry in expected.items():
                with self.subTest(target=name):
                    target = fixture.destination / name
                    self.assertFalse(target.is_symlink())
                    if name in AI_MUTABLE:
                        parse = json.loads if name.endswith(".json") else tomllib.loads
                        actual = parse(target.read_bytes().decode("utf-8"))
                        expected_policy = parse((ROOT / entry.source).read_bytes().decode("utf-8"))
                        expected_policy["fixture_unknown"] = {"keep": False}
                        if name.endswith(".json"):
                            expected_policy["model"] = "fixture-local"
                        self.assertEqual(actual, expected_policy, name)
                    else:
                        self.assertEqual(target.read_bytes(), (ROOT / entry.source).read_bytes(), name)
                    if os.name != "nt":
                        mode = target.stat().st_mode & 0o777
                        if name in AI_MUTABLE or name == ".config/fcitx5/profile":
                            self.assertEqual(mode, 0o600, oct(mode))
                        elif modes[entry.source] == "100755":
                            # Native executable attributes respect the caller's
                            # umask: 0700 is valid under umask 077.
                            self.assertEqual(mode & 0o700, 0o700, oct(mode))
                        else:
                            self.assertEqual(mode & 0o111, 0, oct(mode))
            for name, content in unmanaged.items():
                self.assertEqual((fixture.destination / name).read_bytes(), content)
            applied = snapshot(fixture.destination)
            self.assert_success(fixture.run("apply"))
            self.assertEqual(snapshot(fixture.destination), applied)
            diff = fixture.run("diff")
            self.assert_success(diff)
            self.assertEqual(diff.stdout, "")
            self.assertEqual(snapshot(fixture.source), before)

    def test_native_os_compatible_roles_exact_files_bytes_modes_and_convergence(self):
        system = platform.system()
        roles = {"Linux": ("common-only", "wsl-ubuntu", "lab-ubuntu", "sherlock", "marlowe"),
                 "Darwin": ("common-only", "mac"), "Windows": ("win",)}[system]
        for role in roles:
            with self.subTest(native_os=system, role=role):
                self.check_role(role)

    def test_supplemental_all_role_rendering_with_explicit_os_data(self):
        # This tests branch/target coverage only. It is not native Mac/Windows
        # execution, application discovery, Windows ACL or filesystem evidence.
        for role in ROLES:
            simulated_os = "darwin" if role == "mac" else "windows" if role == "win" else "linux"
            with self.subTest(supplemental_os=simulated_os, role=role):
                self.check_role(role, simulated_os)

    def test_raw_assets_have_declared_legacy_owner_and_exact_bytes(self):
        assets = {
            "dot_codex/pets/tom/spritesheet.webp": "common/codex/.codex/pets/tom/spritesheet.webp",
            "dot_terminfo/t/tmux-256color": "sherlock/terminfo/.terminfo/t/tmux-256color",
        }
        for native, legacy in assets.items():
            with self.subTest(asset=native):
                self.assertEqual((ROOT / "home" / native).read_bytes(), (ROOT / legacy).read_bytes())
        # JSON metadata remains text and follows the bridge like other text.
        self.assertFalse((ROOT / "home/dot_codex/pets/tom/pet.json").exists())
        self.assertTrue((ROOT / "home/dot_codex/pets/tom/pet.json.tmpl").is_file())

    def test_crlf_and_zero_byte_contracts_are_real_test_inputs(self):
        for legacy in ("win/wsl/.wslconfig", "win/wsl/mount.vbs"):
            with self.subTest(legacy=legacy):
                content = (ROOT / legacy).read_bytes()
                self.assertIn(b"\r\n", content)
        for name in ("tcsh", "xonsh"):
            self.assertEqual((ROOT / f"common/{name}/.{name}rc").read_bytes(), b"")
            self.assertTrue((ROOT / f"home/empty_dot_{name}rc.tmpl").is_file())

    def test_init_and_native_data_require_explicit_role(self):
        native_role = "win" if os.name == "nt" else "common-only"
        for config in ("", f'[data]\nhost = "{native_role}"\n'):
            with self.subTest(initialized=bool(config)), ChezmoiFixture() as fixture:
                copy_controls(fixture.source)
                fixture.config.write_text(config, encoding="utf-8")
                before = snapshot(fixture.source)
                result = fixture.run("init")
                if not config:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("host", result.stderr.lower())
                else:
                    self.assert_success(result)
                    data = fixture.run("execute-template", "{{ .host }}")
                    self.assert_success(data)
                    self.assertEqual(data.stdout, native_role)
                    paths = fixture.run("execute-template", "{{ .chezmoi.sourceDir }}\n{{ .chezmoi.workingTree }}")
                    self.assert_success(paths)
                    self.assertEqual([Path(line) for line in paths.stdout.splitlines()],
                                     [fixture.source / "home", fixture.source])
                # Native init may create fixture-local Git bookkeeping.
                after = {name: value for name, value in snapshot(fixture.source).items()
                         if not name.startswith(".git/")}
                self.assertEqual(after, before)
                self.assertEqual(list(fixture.destination.iterdir()), [])

    def test_minimum_version_gate_prevents_destination_writes(self):
        self.assertEqual((ROOT / ".chezmoiversion").read_text(encoding="ascii").strip(), "2.74.0")
        with ChezmoiFixture() as fixture:
            (fixture.source / ".chezmoiversion").write_text("999.0.0\n", encoding="ascii")
            (fixture.source / "dot_probe").write_bytes(b"never applied\n")
            result = fixture.run("apply")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("999.0.0", result.stderr)
            self.assertEqual(list(fixture.destination.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
