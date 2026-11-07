"""Native source contracts; all state belongs to disposable fixtures."""

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import subprocess
import tomllib
import unittest

from chezmoi_source_support import (
    AI_MUTABLE, COUNTS, ROOT, ROLES, SourceFixture, copy_controls, expected_entries,
    fixture_git_env, role_set, snapshot, target_problems, target_rows, tracked_home,
)

from chezmoi_support import ChezmoiFixture


KIT_PATHS = (".claude/dotfiles", ".claude/coding-agent-kit", ".local/bin/codex-as", ".local/bin/claude-as")
LEGACY_TREES = ("common", *ROLES[1:])
# The caller's umask, which native apply honors for plain and executable
# files; private files are 0600 whatever it is.
UMASK = os.umask(0o022)
os.umask(UMASK)
# The only templates that remain: one raw role-variant include each.
ROLE_TEMPLATES = {
    "dot_config/bash/dot_bashrc.tmpl": ".config/bash/.bashrc",
    "dot_config/sh/dot_aliases.tmpl": ".config/sh/.aliases",
    "dot_config/sh/dot_profile.tmpl": ".config/sh/.profile",
    "dot_config/zsh/dot_zshrc.tmpl": ".config/zsh/.zshrc",
    "dot_gitconfig_local.tmpl": ".gitconfig_local",
    "dot_ssh/config.d/legacy.conf.tmpl": ".ssh/config.d/legacy.conf",
}
POLICY_INCLUDES = {
    "home/dot_claude/modify_private_settings.json": 'include ".policy/claude-settings.json"',
    "home/dot_codex/modify_private_config.toml": 'include ".policy/codex-config.toml"',
}
RAW_ASSETS = {
    "home/dot_codex/pets/tom/spritesheet.webp": "78179015093038c8d83542c18c1c976932ee6da06ca42b9b231e008e84b2019c",
    "home/dot_terminfo/t/tmux-256color": "55808427614130a53e9a3dcd93519eefb3d017bcc6c0751182d59638517e86cd",
}


def git_in(directory, env, *args):
    git = shutil.which("git")
    if git is None:
        raise RuntimeError("git prerequisite: the linked-worktree contracts require git")
    return subprocess.run([git, "-c", "user.name=Fixture", "-c",
                           "user.email=fixture@example.invalid", "-c",
                           "commit.gpgsign=false", "-c", "core.hooksPath=",
                           *args], cwd=directory, env=env, check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)


def linked_worktree(fixture, files):
    """Commit FILES in "original repository"; return a linked worktree with spaces."""
    repository = fixture.root / "original repository"
    for name in (".chezmoiroot", ".chezmoiversion"):
        (repository / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / name, repository / name)
    for name, content in files.items():
        (repository / name).parent.mkdir(parents=True, exist_ok=True)
        (repository / name).write_bytes(content)
    env = fixture_git_env(fixture.env)
    git_in(repository, env, "init", "--template=")
    git_in(repository, env, "add", ".")
    git_in(repository, env, "commit", "-m", "Synthetic include fixture")
    linked = fixture.root / "linked worktree with spaces"
    git_in(repository, env, "worktree", "add", "--detach", str(linked))
    return repository, linked


class SourceContractTests(unittest.TestCase):
    def test_working_tree_include_in_linked_worktree_with_spaces(self):
        # Guards the init guard's validate-host include (home/.chezmoi.toml.tmpl:1),
        # which keeps .chezmoi.workingTree because the source root does not move.
        # Catch sourceDir/workingTree confusion and accidental template evaluation.
        with ChezmoiFixture() as fixture:
            original = b'quotes="literal"\n{{ not_a_template }}\r\n'
            repository, linked = linked_worktree(fixture, {
                "canonical.txt": original,
                "home/dot_probe.tmpl": b'{{- include (joinPath .chezmoi.workingTree "canonical.txt") -}}\n',
            })
            fixture.source = linked
            result = fixture.run("apply")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((fixture.destination / ".probe").read_bytes(), original)
            self.assertEqual((repository / "canonical.txt").read_bytes(), original)
            self.assertEqual((linked / "canonical.txt").read_bytes(), original)
            self.assertEqual(fixture.run("diff").stdout, "")

    def test_relative_include_reads_hidden_inputs_in_linked_worktree_with_spaces(self):
        # Role variants and policy are raw includes relative to sourceDir (home/),
        # never the template's directory or the working tree, and a source
        # dot-directory is never a target.
        with ChezmoiFixture() as fixture:
            original = b'quotes="literal"\n{{ not_a_template }}\r\n'
            policy = b'{"x": "{{ .host }}"}\n'
            files = {
                "home/.hosts/lab-ubuntu/.config/sh/.profile": original,
                "home/dot_config/sh/.hosts/lab-ubuntu/.config/sh/.profile": b"decoy\n",
                "home/.policy/probe.json": policy,
                "home/dot_config/sh/dot_profile.tmpl":
                    b'{{- include (printf ".hosts/%s/.config/sh/.profile" .host) -}}\n',
                "home/dot_probe.tmpl": b'{{- include ".policy/probe.json" -}}\n',
            }
            repository, linked = linked_worktree(fixture, files)
            fixture.source = linked
            fixture.config.write_text('[data]\nhost = "lab-ubuntu"\n', encoding="utf-8")
            managed = fixture.run("managed", "--include=all", "--nul-path-separator")
            self.assert_success(managed)
            self.assertEqual({path.replace("\\", "/") for path in managed.stdout.split("\0") if path},
                             {".config", ".config/sh", ".config/sh/.profile", ".probe"})
            self.assert_success(fixture.run("apply"))
            self.assertEqual((fixture.destination / ".config/sh/.profile").read_bytes(), original)
            self.assertEqual((fixture.destination / ".probe").read_bytes(), policy)
            alternate = fixture.root / "alternate working tree"
            (alternate / "home/.hosts/lab-ubuntu/.config/sh").mkdir(parents=True)
            (alternate / "home/.hosts/lab-ubuntu/.config/sh/.profile").write_bytes(b"alternate\n")
            self.assert_success(fixture.run("--working-tree", str(alternate), "apply"))
            self.assertEqual((fixture.destination / ".config/sh/.profile").read_bytes(), original)
            self.assertEqual(fixture.run("diff").stdout, "")
            for name, content in files.items():
                self.assertEqual((repository / name).read_bytes(), content)
                self.assertEqual((linked / name).read_bytes(), content)

    def test_source_declares_no_externals(self):
        # Externals download while the source state is read, even with
        # --exclude=externals, through an HTTP client without a timeout; the
        # login updater must stay configuration-only (stage-5-ecosystem.md).
        found = []
        for directory, dirnames, filenames in os.walk(ROOT / "home"):
            found += [name for name in dirnames if name == ".chezmoiexternals"]
            found += [name for name in filenames if name.startswith(".chezmoiexternal.")]
        self.assertEqual(found, [])

    def test_repository_tracks_only_regular_files(self):
        # The doctor no longer diagnoses retired submodule checkouts (D9); the
        # native updater passes --recurse-submodules=false. A tracked symlink
        # becomes a text file holding its target on a Windows clone without
        # core.symlinks, and chezmoi would deploy that text, so the checkout
        # holds regular files only. Under home/ the executable bit sits
        # exactly on the executable_ sources.
        self.assertFalse((ROOT / ".gitmodules").exists())
        listed = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-s", "-z"], check=True,
                                stdout=subprocess.PIPE, text=True, timeout=30).stdout
        modes = {entry.split("\t", 1)[1]: entry.split(" ", 1)[0] for entry in listed.split("\0") if entry}
        self.assertEqual({path: mode for path, mode in modes.items() if mode not in ("100644", "100755")}, {})
        executable = re.compile(r"^(?:create_|modify_)?(?:encrypted_)?(?:private_)?(?:readonly_)?(?:empty_)?executable_")
        wrong = {path: mode for path, mode in modes.items() if path.startswith("home/")
                 and (mode == "100755") != bool(executable.match(PurePosixPath(path).name))}
        self.assertEqual(wrong, {})

    def test_chezmoiignore_mirrors_every_gitignore_pattern(self):
        # chezmoi reads no .gitignore, so whatever git ignores under home/
        # (an editor backup, a merge .orig, a cache) would deploy on the next
        # login update. chezmoi already skips source names starting with a
        # dot; every other unanchored pattern has an unconditional twin.
        patterns = [line for line in (ROOT / ".gitignore").read_text(encoding="utf-8").splitlines()
                    if line and not line.startswith(("#", ".", "/", "!"))]
        ignore = (ROOT / "home/.chezmoiignore").read_text(encoding="utf-8").splitlines()
        twins = [line for line in ignore if line.startswith("**/")]
        # A leading escaped '#' becomes the class [#]: no backslash, which a
        # Windows chezmoi could read as a separator.
        self.assertEqual(twins, ["**/" + re.sub(r"^\\#", "[#]", pattern.rstrip("/")) for pattern in patterns])
        first_section = next(index for index, line in enumerate(ignore) if line.startswith("{{ if "))
        self.assertLess(ignore.index(twins[-1]), first_section, "the twins must apply to every role")

    def test_git_ignored_leftovers_in_the_source_are_no_targets(self):
        strays = ("dot_zshrc~", "dot_gitconfig.orig", "#dot_vimrc#", "dot_vimrc.swp", "dot_tmux.conf.rej",
                  "dot_config/tmux/__pycache__/metric.cpython-312.pyc", "dot_config/kitty/debug.log")
        # Linux data on every runner (supplemental, as below): validate-host
        # refuses lab-ubuntu on a macOS or Windows OS, and lab-ubuntu is the
        # role that manages every stray's neighbour.
        with SourceFixture("lab-ubuntu", native_os="linux") as fixture:
            for stray in strays:
                path = fixture.source / "home" / stray
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"stray\n")
            # NUL-separated bytes: text mode on Windows would send CRLF, and git
            # reads the CR as part of each path.
            ignored = subprocess.run(["git", "-C", str(ROOT), "check-ignore", "--no-index", "-z", "--stdin"],
                                     input=b"".join(f"home/{s}".encode() + b"\0" for s in strays),
                                     capture_output=True, timeout=30, env=fixture_git_env())
            self.assertEqual([p.decode() for p in ignored.stdout.split(b"\0") if p], [f"home/{s}" for s in strays])
            managed = fixture.run("managed", "--include=files", "--nul-path-separator")
            self.assert_success(managed)
            self.assertEqual({path.replace("\\", "/") for path in managed.stdout.split("\0") if path},
                             set(expected_entries("lab-ubuntu")))

    def test_gitignore_keeps_the_host_residue_guards(self):
        # Without these lines the native updater's untracked-file check refuses
        # every login on a host that still holds the residue (D-8, Risk 2).
        # Phase C removes the lines and this test together.
        lines = (ROOT / ".gitignore").read_text(encoding="utf-8").splitlines()
        for pattern in ("/.venv-sync/", "/common/codex/coding-agent-kit/",
                        "/common/coding-agent-kit/coding-agent-kit/", "/common/pymol/PyMOLScripts/",
                        "/common/sherlock-kit/sherlock-kit/"):
            with self.subTest(pattern=pattern):
                self.assertIn(pattern, lines)

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

    def test_target_table_matches_tracked_inputs_roles_and_counts(self):
        # tests/fixtures/chezmoi/targets.tsv is the authority (D-13): every row's
        # per-role source is tracked and every hidden input feeds one target.
        self.assertEqual(target_problems(target_rows(), tracked_home()), [])
        for hosts in ("", "mac,mac", "guess", "unix,win"):
            with self.subTest(hosts=hosts), self.assertRaises(ValueError):
                role_set(hosts)

    def test_every_tracked_source_feeds_a_listed_target(self):
        # The unconditional .chezmoiignore twins match target names, so a new
        # source named like a git-ignored file (a target called build, say)
        # would vanish silently. Every tracked home/ file is a table source,
        # a role template, a policy modify, a chezmoi control file, a hidden
        # input or an enrolled Claude secret; a listed target must then render
        # for its roles (check_role).
        listed = {source for _target, _hosts, source, _mode, _shell in target_rows() if "{host}" not in source}
        known = listed | {"home/" + name for name in ROLE_TEMPLATES} | set(POLICY_INCLUDES) | {
            "home/.chezmoi.toml.tmpl", "home/.chezmoiignore"}
        secret = re.compile(r"home/private_dot_secrets/encrypted_private_claude-[a-z0-9]+[.]age")
        unlisted = [path for path in tracked_home() if path not in known and not secret.fullmatch(path)
                    and not path.startswith(("home/.hosts/", "home/.policy/", "home/.chezmoidata/",
                                             "home/.chezmoitemplates/"))]
        self.assertEqual(unlisted, [])

    def test_only_role_templates_remain_and_none_reads_the_working_tree(self):
        tracked = tracked_home()
        templates = {path.removeprefix("home/") for path in tracked
                     if path.endswith(".tmpl") and path != "home/.chezmoi.toml.tmpl"}
        self.assertEqual(templates, set(ROLE_TEMPLATES))
        for template, target in ROLE_TEMPLATES.items():
            with self.subTest(template=template):
                self.assertEqual((ROOT / "home" / template).read_bytes(),
                                 b'{{- include (printf ".hosts/%s/' + target.encode() + b'" .host) -}}\n')
        self.assertEqual(set(ROLE_TEMPLATES.values()),
                         {row[0] for row in target_rows() if "{host}" in row[2]})
        for path, include in POLICY_INCLUDES.items():
            with self.subTest(modify=path):
                self.assertEqual((ROOT / path).read_text(encoding="utf-8").count(include), 1)
        readers = sorted(path for path in tracked
                         if b".chezmoi.workingTree" in (ROOT / path).read_bytes())
        self.assertEqual(readers, ["home/.chezmoi.toml.tmpl"])

    def test_legacy_trees_and_raw_duplicates_are_gone(self):
        # Git, not the filesystem: ignored retired checkouts may remain (D-8).
        listed = subprocess.run(["git", "ls-files", "-z", "--", *LEGACY_TREES], cwd=ROOT,
                                env=fixture_git_env(), check=True, capture_output=True, timeout=30)
        self.assertEqual(listed.stdout, b"")
        for path, digest in RAW_ASSETS.items():
            with self.subTest(asset=path):
                self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), digest)

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
            managed = fixture.run("managed", "--include=files", "--nul-path-separator")
            self.assert_success(managed)
            # Native managed output uses platform separators; the table uses '/'.
            managed_files = {path.replace("\\", "/") for path in managed.stdout.split("\0") if path}
            # The payload repos install the launchers and Claude helpers; no
            # role manages them.
            self.assertEqual({path for path in managed_files for kit in KIT_PATHS
                              if path == kit or path.startswith(kit + "/")}, set())
            self.assertEqual(managed_files, set(expected))
            directories = fixture.run("managed", "--include=dirs", "--nul-path-separator")
            self.assert_success(directories)
            self.assertEqual({path.replace("\\", "/").split("/", 1)[0]
                              for path in directories.stdout.split("\0") if path} & {".hosts", ".policy"},
                             set())
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
                        if entry.mode == "private":
                            self.assertEqual(mode, 0o600, oct(mode))
                        elif entry.mode == "executable":
                            self.assertEqual(mode, 0o777 & ~UMASK, oct(mode))
                        else:
                            self.assertEqual(mode, 0o666 & ~UMASK, oct(mode))
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

    def test_template_looking_text_stays_plain(self):
        # A .tmpl would parse these braces; check_role proves they render verbatim.
        for path in ("home/dot_config/kitty/kitty.conf", "home/dot_config/oh-my-posh/prompt.omp.json"):
            with self.subTest(source=path):
                self.assertIn(b"{{", (ROOT / path).read_bytes())
                self.assertFalse((ROOT / f"{path}.tmpl").exists())
        self.assertTrue((ROOT / "home/dot_codex/pets/tom/pet.json").is_file())
        self.assertFalse((ROOT / "home/dot_codex/pets/tom/pet.json.tmpl").exists())

    def test_crlf_and_zero_byte_contracts_are_real_test_inputs(self):
        windows = ("home/dot_wslconfig", "home/mount.vbs")
        for path in windows:
            with self.subTest(source=path):
                self.assertIn(b"\r\n", (ROOT / path).read_bytes())
        attributes = subprocess.run(["git", "check-attr", "text", "--", *windows], cwd=ROOT,
                                    env=fixture_git_env(), check=True, capture_output=True,
                                    text=True, timeout=30)
        self.assertEqual(attributes.stdout.splitlines(), [f"{path}: text: unset" for path in windows])
        for name in ("tcsh", "xonsh"):
            with self.subTest(empty=name):
                self.assertEqual((ROOT / f"home/empty_dot_{name}rc").read_bytes(), b"")
                self.assertFalse((ROOT / f"home/empty_dot_{name}rc.tmpl").exists())

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
