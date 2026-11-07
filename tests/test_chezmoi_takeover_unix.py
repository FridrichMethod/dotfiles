"""Unix takeover boundaries with disposable homes and actual local Git remotes."""

import json
import os
import shutil
import subprocess
import unittest

from chezmoi_source_support import ROOT, fixture_git_env
from chezmoi_support import ChezmoiFixture


UPDATE_ARGS = ["-c", "rebase.autoStash=false", "-c", "merge.autoStash=false",
               "pull", "--ff-only", "--no-rebase", "--no-autostash",
               "--no-recurse-submodules"]


class UpdateFixture(ChezmoiFixture):
    def __enter__(self):
        super().__enter__()
        self.config = self.destination / ".config/chezmoi/chezmoi.toml"
        self.cache = self.destination / ".cache/chezmoi"
        self.state = self.destination / ".local/state/chezmoi/chezmoi.boltdb"
        for directory in (self.config.parent, self.cache, self.state.parent):
            directory.mkdir(parents=True, exist_ok=True)
        # The top-level lines chezmoi init writes, which the login updater reads.
        self.top = f'destDir = "{self.destination}"\nsourceDir = "{self.source}"\n'
        self.config.write_text(self.top + '[data]\nhost="common-only"\n[git]\nautoAdd=false\n'
                               'autoCommit=false\nautoPush=false\n[update]\ncommand="git"\n'
                               f'args={json.dumps(UPDATE_ARGS)}\nrecurseSubmodules=false\n',
                               encoding="utf-8")
        self.env.update(HOME=str(self.destination))
        self.bin = self.root / "tools"
        self.bin.mkdir()
        for name, executable in (("chezmoi", self.binary), ("git", shutil.which("git")),
                                 ("dirname", shutil.which("dirname")), ("false", shutil.which("false"))):
            if executable is None:
                raise unittest.SkipTest(f"Unix takeover prerequisite: {name}")
            (self.bin / name).symlink_to(executable)
        self.env["PATH"] = str(self.bin)
        (self.source / "home").mkdir()
        (self.source / "lib").mkdir()
        shutil.copyfile(ROOT / "lib/chezmoi-guard.sh", self.source / "lib/chezmoi-guard.sh")
        (self.source / "home/dot_sample").write_text("before\n", encoding="utf-8")
        (self.source / ".chezmoiroot").write_text("home\n", encoding="ascii")
        self.git("init", "-b", "main")
        self.commit("initial")
        self.remote = self.root / "remote.git"
        self.git("clone", "--bare", str(self.source), str(self.remote), cwd=self.root)
        self.git("remote", "add", "origin", str(self.remote))
        self.git("fetch", "origin")
        self.git("branch", "--set-upstream-to=origin/main")
        self.producer = self.root / "producer"
        self.git("clone", str(self.remote), str(self.producer), cwd=self.root)
        self.maintenance = self.destination / ".config/dotfiles/maintenance"
        self.maintenance.parent.mkdir(mode=0o700)
        applied = self.run("apply")
        if applied.returncode:
            raise AssertionError("initial inspected native fixture apply failed")
        return self

    def git(self, *args, cwd=None):
        env = fixture_git_env(self.env)
        env.update(GIT_AUTHOR_NAME="Fixture", GIT_AUTHOR_EMAIL="fixture@example.invalid",
                   GIT_COMMITTER_NAME="Fixture", GIT_COMMITTER_EMAIL="fixture@example.invalid")
        result = subprocess.run([shutil.which("git"), *args], cwd=cwd or self.source,
                                env=env, capture_output=True, text=True, timeout=15, check=True)
        return result.stdout.strip()

    def commit(self, message, cwd=None):
        self.git("add", "--all", cwd=cwd)
        self.git("commit", "-m", message, cwd=cwd)

    def advance(self):
        (self.producer / "home/dot_sample").write_text("after\n", encoding="utf-8")
        self.commit("upstream update", self.producer)
        self.git("push", "origin", "main", cwd=self.producer)

    def hook(self, script="scripts/chezmoi-update.sh", code='. "$1"', env=None, interactive=True, input=None):
        selected = ROOT / script
        return subprocess.run(["/bin/bash", "--noprofile", "--norc", "-ic" if interactive else "-c",
                               code, "fixture", str(selected)], cwd=self.root,
                              env={**self.env, **(env or {})}, input=input,
                              **({"stdin": subprocess.DEVNULL} if input is None else {}),
                              capture_output=True, text=True, timeout=25, check=False)


@unittest.skipIf(os.name == "nt", "Unix shells and ownership fixtures")
class UnixTakeoverTests(unittest.TestCase):
    def test_regular_file_mode_overrides_stale_local_symlink_configuration(self):
        with UpdateFixture() as f:
            f.config.write_text('mode="symlink"\n' + f.config.read_text())
            f.advance()
            result = f.hook()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("[dotfiles] [warn]", result.stderr)
            self.assertFalse((f.destination / ".sample").is_symlink())
            self.assertEqual((f.destination / ".sample").read_text(), "after\n")

    def assert_warning(self, result):
        self.assertEqual(result.returncode, 0, "login must stay usable")
        self.assertIn("[dotfiles] [warn]", result.stderr)

    def test_clean_fast_forward_applies_to_the_configured_home_despite_xdg_and_git_overrides(self):
        with UpdateFixture() as f:
            f.advance()
            result = f.hook(env={"XDG_CONFIG_HOME": str(f.root / "wrong-config"),
                                 "XDG_STATE_HOME": str(f.root / "wrong-state"),
                                 "GIT_DIR": str(f.producer / ".git"),
                                 "GIT_WORK_TREE": str(f.producer)})
            self.assertEqual(result.returncode, 0)
            self.assertTrue((f.destination / ".sample").exists(), result.stderr)
            self.assertEqual((f.destination / ".sample").read_text(), "after\n")
            self.assertEqual(f.git("rev-parse", "HEAD"), f.git("rev-parse", "HEAD", cwd=f.producer))
            self.assertTrue(f.state.is_file())
            self.assertFalse((f.root / "wrong-config").exists())
            self.assertFalse((f.root / "wrong-state").exists())

    def test_update_preserves_existing_shared_parent_modes(self):
        for mask in ("002", "022"):
            with self.subTest(umask=mask), UpdateFixture() as f:
                entries = (("dot_ssh", ".ssh", 0o700),
                           ("dot_claude", ".claude", 0o700),
                           ("dot_codex", ".codex", 0o700),
                           ("dot_config/nested", ".config/nested", 0o775))
                (f.destination / ".config").chmod(0o770)
                for source_name, target_name, mode in entries:
                    source = f.producer / "home" / source_name
                    source.mkdir(parents=True)
                    (source / "private_probe").write_text("new managed value\n")
                    target = f.destination / target_name
                    target.mkdir(parents=True, exist_ok=True)
                    target.chmod(mode)
                f.advance()
                for _ in range(2):
                    result = f.hook(code=f'umask {mask}; . "$1"')
                    self.assertEqual(result.returncode, 0)
                    self.assertNotIn("[dotfiles] [warn]", result.stderr)
                    self.assertEqual((f.destination / ".config").stat().st_mode & 0o777, 0o770)
                    for _, target_name, mode in entries:
                        target = f.destination / target_name
                        self.assertEqual(target.stat().st_mode & 0o777, mode)
                        self.assertEqual((target / "probe").read_text(), "new managed value\n")
                        self.assertEqual((target / "probe").stat().st_mode & 0o777, 0o600)
                    self.assertEqual((f.destination / ".sample").read_text(), "after\n")

    def test_update_refuses_missing_new_parent_until_operator_preparation(self):
        for source_name, target_name in (("dot_new-parent", ".new-parent"),
                                         ("private_dot_secrets", ".secrets")):
            with self.subTest(parent=target_name), UpdateFixture() as f:
                source = f.producer / "home" / source_name
                source.mkdir()
                (source / "private_probe").write_text("new managed value\n")
                f.commit("new target under an absent parent", f.producer)
                f.git("push", "origin", "main", cwd=f.producer)
                self.assert_warning(f.hook())
                target = f.destination / target_name
                self.assertFalse(target.exists())
                self.assertFalse(target.is_symlink())
                self.assertEqual((f.destination / ".sample").read_text(), "before\n")
                self.assertTrue(f.config.read_text().startswith(f.top))
                # Native update may fast-forward before the apply refuses.
                self.assertEqual(f.git("rev-parse", "HEAD"), f.git("rev-parse", "HEAD", cwd=f.producer))

    def test_dirty_tracked_and_untracked_source_refuse_without_stash(self):
        for kind in ("tracked", "untracked"):
            with self.subTest(kind=kind), UpdateFixture() as f:
                f.advance()
                changed = f.source / ("home/dot_sample" if kind == "tracked" else "local-notes")
                changed.write_text("keep my source edit\n")
                before = f.git("rev-parse", "HEAD")
                self.assert_warning(f.hook())
                self.assertEqual(f.git("rev-parse", "HEAD"), before)
                self.assertEqual(changed.read_text(), "keep my source edit\n")
                self.assertEqual(f.git("stash", "list"), "")
                self.assertEqual((f.destination / ".sample").read_text(), "before\n")

    def test_divergence_is_not_rebased_even_with_hostile_git_options(self):
        with UpdateFixture() as f:
            f.advance()
            (f.source / "local-notes").write_text("local commit\n")
            f.commit("local independent history")
            for key, value in (("pull.rebase", "true"), ("rebase.autoStash", "true"),
                               ("merge.autoStash", "true"), ("pull.ff", "false")):
                f.git("config", key, value)
            before = f.git("rev-parse", "HEAD")
            self.assert_warning(f.hook())
            self.assertEqual(f.git("rev-parse", "HEAD"), before)
            self.assertEqual(f.git("stash", "list"), "")
            self.assertFalse((f.source / ".git/rebase-merge").exists())
            self.assertFalse((f.source / ".git/MERGE_HEAD").exists())

    def test_old_or_hostile_native_update_config_is_refused_before_git(self):
        for text in ('[data]\nhost="common-only"\n',
                     '[update]\ncommand="git"\nargs=["pull", "--rebase", "--autostash"]\n'):
            with self.subTest(config=text), UpdateFixture() as f:
                f.advance()
                f.config.write_text(f.top + text)
                before = f.git("rev-parse", "HEAD")
                self.assert_warning(f.hook())
                self.assertEqual(f.git("rev-parse", "HEAD"), before)

    def test_destination_conflict_preserves_live_edit_and_silent_failure_warns(self):
        with UpdateFixture() as f:
            self.assertEqual(f.run("apply").returncode, 0)
            target = f.destination / ".sample"
            target.write_text("keep live edit\n")
            f.advance()
            self.assert_warning(f.hook())
            self.assertEqual(target.read_text(), "keep live edit\n")
            self.assertTrue(f.config.read_text().startswith(f.top))
            self.assertEqual(f.git("stash", "list"), "")

    def test_unavailable_remote_warns_without_apply_or_source_changes(self):
        with UpdateFixture() as f:
            f.git("remote", "set-url", "origin", str(f.root / "absent remote"))
            before = f.git("rev-parse", "HEAD")
            self.assert_warning(f.hook())
            self.assertEqual(f.git("rev-parse", "HEAD"), before)
            self.assertEqual((f.destination / ".sample").read_text(), "before\n")

    def test_invalid_config_and_onedrive_refuse_before_state_write(self):
        for kind in ("other-home", "no-source-line", "symlink", "working-tree", "OneDrive"):
            with self.subTest(kind=kind), UpdateFixture() as f:
                f.advance()
                before = f.git("rev-parse", "HEAD")
                state_before = f.state.read_bytes()
                text = f.config.read_text()
                if kind == "other-home":
                    f.config.write_text(text.replace(f'destDir = "{f.destination}"', f'destDir = "{f.root}"'))
                elif kind == "no-source-line":
                    f.config.write_text(text.replace(f'sourceDir = "{f.source}"\n', ""))
                elif kind == "symlink":
                    backup = f.config.with_name("saved-config")
                    f.config.rename(backup)
                    f.config.symlink_to(backup)
                elif kind == "working-tree":
                    # A local workingTree key would redirect a later init's sourceDir.
                    f.config.write_text(f'workingTree = "{f.source}"\n' + text)
                else:
                    moved = f.root / "OneDrive source"
                    f.source.rename(moved)
                    f.source = moved
                    f.config.write_text(text.replace(f'sourceDir = "{f.root / "source state"}"',
                                                     f'sourceDir = "{moved}"'))
                self.assert_warning(f.hook())
                self.assertEqual(f.state.read_bytes(), state_before)
                self.assertEqual(f.git("rev-parse", "HEAD"), before)

    def test_optout_noninteractive_nested_session_and_maintenance_skip(self):
        for option in ("optout", "noninteractive", "nested", "maintenance"):
            with self.subTest(option=option), UpdateFixture() as f:
                f.advance()
                env = {}
                if option == "optout":
                    env["DOTFILES_AUTO_UPDATE"] = "0"
                elif option == "nested":
                    env["_DOTFILES_CHECKED"] = "1"
                elif option == "maintenance":
                    f.maintenance.touch()
                before = f.git("rev-parse", "HEAD")
                state_before = f.state.read_bytes()
                result = f.hook(env=env, interactive=option != "noninteractive")
                self.assertEqual(result.returncode, 0)
                self.assertEqual(f.git("rev-parse", "HEAD"), before)
                self.assertEqual(f.state.read_bytes(), state_before)

    def test_missing_backend_and_nonsecret_failure_are_bounded(self):
        with UpdateFixture() as f:
            state_before = f.state.read_bytes()
            (f.bin / "chezmoi").unlink()
            self.assert_warning(f.hook())
            self.assertEqual(f.state.read_bytes(), state_before)

    def test_lost_native_state_refuses_before_replacing_existing_symlink(self):
        with UpdateFixture() as f:
            target = f.destination / ".sample"
            foreign = f.root / "foreign-file"
            foreign.write_text("preserve foreign target\n")
            target.unlink()
            target.symlink_to(foreign)
            f.state.unlink()
            self.assert_warning(f.hook())
            self.assertTrue(target.is_symlink())
            self.assertEqual(foreign.read_text(), "preserve foreign target\n")
            self.assertFalse(f.state.exists())

    def test_missing_age_identity_and_malformed_ciphertext_preserve_secret_without_output(self):
        for failure in ("missing-identity", "malformed-ciphertext"):
            with self.subTest(failure=failure), UpdateFixture() as f:
                identity = f.root / "synthetic-identity"
                self.assertEqual(f.run("age-keygen", "--use-builtin-age=true", "--output", str(identity)).returncode, 0)
                recipient = f.run("age-keygen", "--convert", str(identity)).stdout.strip()
                config = f.config.read_text()
                f.config.write_text('encryption="age"\n' + config
                                    + f'\n[age]\nidentity={json.dumps(str(identity))}\nrecipients=[{json.dumps(recipient)}]\n')
                canary = "synthetic-private-content\n"
                ciphertext = f.run("encrypt", "--use-builtin-age=true", input=canary)
                self.assertEqual(ciphertext.returncode, 0, "synthetic encryption failed")
                secret_source = f.source / "home/private_dot_secrets"
                secret_source.mkdir()
                (secret_source / "encrypted_private_account.age").write_text(
                    ciphertext.stdout if failure == "missing-identity" else "not age ciphertext\n")
                f.commit("synthetic secret source")
                target = f.destination / ".secrets/account"
                target.parent.mkdir(mode=0o700)
                target.write_text("newer live private value\n")
                target.chmod(0o600)
                if failure == "missing-identity":
                    identity.unlink()
                result = f.hook()
                self.assert_warning(result)
                self.assertEqual(target.read_text(), "newer live private value\n")
                self.assertNotIn(canary.strip(), result.stdout + result.stderr)
                self.assertNotIn("newer live private value", result.stdout + result.stderr)

    def test_failed_native_cli_has_closed_stdin_secret_free_warning_and_once_per_session(self):
        for silent in (False, True):
            with self.subTest(silent=silent), UpdateFixture() as f:
                fake = f.bin / "chezmoi"
                fake.unlink()
                log = f.root / "native-calls"
                fake.write_text('#!/bin/sh\n'
                                'for arg do printf "[%s]" "$arg"; done >>"$CALL_LOG"\n'
                                'printf "\\n" >>"$CALL_LOG"\n'
                                'for arg do if [ "$arg" = execute-template ]; then printf safe; exit 0; fi; done\n'
                                'if IFS= read -r line; then printf "stdin-open\\n" >>"$CALL_LOG"; exit 0; fi\n'
                                'printf "stdin-closed\\n" >>"$CALL_LOG"\n'
                                + ('' if silent else 'printf "synthetic-secret-out\\n"; printf "synthetic-secret-err\\n" >&2\n')
                                + 'exit 1\n')
                fake.chmod(0o700)
                result = f.hook(code='. "$1"; . "$1"; /bin/bash --noprofile --norc -ic \' . "$1"\' nested "$1"',
                                env={"CALL_LOG": str(log)}, input="must not reach backend\n")
                self.assert_warning(result)
                self.assertNotIn("synthetic-secret", result.stdout + result.stderr)
                calls = log.read_text().splitlines()
                self.assertEqual(len(calls), 3)
                self.assertEqual(calls[-1], "stdin-closed")
                self.assertIn(f"[--source][{f.source}]", calls[1])
                self.assertIn(f"[--destination][{f.destination}]", calls[1])
                self.assertIn(f"[--config][{f.config}]", calls[1])
                self.assertIn(f"[--cache][{f.cache}]", calls[1])
                self.assertIn(f"[--persistent-state][{f.state}]", calls[1])
                self.assertIn("[--no-tty][--error-on-conflict]", calls[1])
                self.assertNotIn("[--force]", calls[1])

    def test_profiles_select_the_configured_source_and_maintenance_survives_new_logins(self):
        for shell in ("bash", "zsh"):
            executable = shutil.which(shell)
            if executable is None:
                continue
            with self.subTest(shell=shell), UpdateFixture() as f:
                scripts = f.source / "scripts"
                scripts.mkdir()
                log = f.root / "dispatch-log"
                for name in ("chezmoi-update", "payload-update"):
                    (scripts / f"{name}.sh").write_text(f'printf "%s\\n" {name} >>"$DISPATCH_LOG"\n')
                shutil.copyfile(ROOT / "home/dot_profile", f.destination / ".profile")
                shutil.copyfile(ROOT / "home/dot_zshrc", f.destination / ".zshrc")
                (f.destination / ".oh-my-zsh").mkdir()
                (f.destination / ".oh-my-zsh/oh-my-zsh.sh").touch()
                env = {**f.env, "PATH": os.defpath, "CURSOR_AGENT": "1", "DISPATCH_LOG": str(log)}
                args = [executable, *(["--noprofile", "--norc"] if shell == "bash" else ["-f"]),
                        "-ic", '. "$HOME/.profile"' if shell == "bash" else 'source "$HOME/.zshrc"']
                for maintenance in (False, True, True):
                    if maintenance:
                        f.maintenance.touch()
                        if log.exists():
                            log.unlink()
                    result = subprocess.run(args, env=env, cwd=f.root, stdin=subprocess.DEVNULL,
                                            capture_output=True, text=True, timeout=15)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    if maintenance:
                        self.assertFalse(log.exists())
                    else:
                        self.assertTrue(log.exists(), result.stderr)
                        # A login updates; payloads install only through sync-payloads.
                        self.assertEqual(log.read_text().splitlines(), ["chezmoi-update"])

    def test_noninteractive_profile_skips_invalid_config_quietly(self):
        with UpdateFixture() as f:
            f.config.write_text(f.config.read_text().replace(f.top, ""))
            result = f.hook("home/dot_profile", interactive=False)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout + result.stderr, "")

    def test_new_source_targets_preserve_unrecorded_files_links_and_stricter_modes(self):
        for placement in ("current-source", "upstream"):
            for kind in ("regular", "symlink", "same-symlink", "stricter-mode"):
                with self.subTest(placement=placement, kind=kind), UpdateFixture() as f:
                    root = f.source if placement == "current-source" else f.producer
                    (root / "home/dot_new-target").write_text("new upstream target\n")
                    f.commit("new managed target", root)
                    f.git("push", "origin", "main", cwd=root)
                    target = f.destination / ".new-target"
                    if kind in ("symlink", "same-symlink"):
                        foreign = f.root / "foreign-existing-file"
                        foreign.write_text("new upstream target\n" if kind == "same-symlink" else "foreign bytes\n")
                        target.symlink_to(foreign)
                    else:
                        target.write_text("new upstream target\n" if kind == "stricter-mode" else "existing local file\n")
                        if kind == "stricter-mode":
                            target.chmod(0o400)
                    before = target.is_symlink(), target.read_bytes(), target.stat().st_mode & 0o777
                    self.assert_warning(f.hook())
                    self.assertEqual((target.is_symlink(), target.read_bytes(), target.stat().st_mode & 0o777), before)
                    self.assertEqual(f.git("stash", "list"), "")

    def test_genuinely_absent_upstream_target_is_applied(self):
        with UpdateFixture() as f:
            (f.producer / "home/dot_new-target").write_text("new upstream target\n")
            f.commit("new managed target", f.producer)
            f.git("push", "origin", "main", cwd=f.producer)
            result = f.hook()
            self.assertEqual(result.returncode, 0)
            self.assertNotIn("[dotfiles] [warn]", result.stderr)
            self.assertEqual((f.destination / ".new-target").read_text(), "new upstream target\n")

    def test_empty_native_state_refuses_before_git_or_target_writes(self):
        with UpdateFixture() as f:
            f.state.write_bytes(b"")
            f.advance()
            before = f.git("rev-parse", "HEAD")
            self.assert_warning(f.hook())
            self.assertEqual(f.git("rev-parse", "HEAD"), before)
            self.assertEqual((f.destination / ".sample").read_text(), "before\n")
            self.assertEqual(f.state.read_bytes(), b"")


if __name__ == "__main__":
    unittest.main()
