"""Windows writer handover and native updater behavior in disposable homes."""

import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest

from chezmoi_support import ChezmoiFixture

ROOT = Path(__file__).resolve().parents[1]


def ps_string(value):
    return "'" + str(value).replace("'", "''") + "'"


@unittest.skipUnless(os.name == "nt", "native Windows takeover requires Windows")
class WindowsTakeoverTests(unittest.TestCase):
    def test_regular_file_mode_overrides_stale_local_symlink_configuration(self):
        self.setup_native()
        self.config.write_text('mode="symlink"\n' + self.config.read_text())
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("skipped or failed", result.stderr)
        self.assertFalse((self.home / ".sample").is_symlink())
        self.assertEqual((self.home / ".sample").read_text(), "initial\n")

    def setUp(self):
        self.fixture = ChezmoiFixture()
        self.f = self.fixture.__enter__()
        self.addCleanup(self.fixture.__exit__, None, None, None)
        self.pwsh = shutil.which("pwsh")
        self.git_exe = shutil.which("git")
        if not self.pwsh or not self.git_exe:
            self.skipTest("PowerShell 7 and Git required")
        self.home = self.f.destination
        self.marker = self.home / ".config/dotfiles/native"
        self.marker.parent.mkdir(parents=True)
        self.repo = self.f.source
        self.env = dict(self.f.env)
        self.env["PATH"] = os.pathsep.join((str(self.f.binary.parent), str(Path(self.git_exe).parent),
                                            str(Path(self.pwsh).parent), os.environ["SYSTEMROOT"] + "\\System32"))
        self.env.update(HOME=str(self.home), USERPROFILE=str(self.home),
                        GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="NUL",
                        GIT_AUTHOR_NAME="Fixture", GIT_COMMITTER_NAME="Fixture",
                        GIT_AUTHOR_EMAIL="fixture@example.invalid", GIT_COMMITTER_EMAIL="fixture@example.invalid")

    def ps(self, body):
        script = "$ErrorActionPreference='Stop';Set-Variable HOME -Value " + ps_string(self.home) + " -Force;" + body + ";exit 0"
        encoded = base64.b64encode(script.encode("utf-16le")).decode()
        return subprocess.run([self.pwsh, "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
                              cwd=self.f.root, env=self.env, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=60)

    def guard(self, body):
        return self.ps(". " + ps_string(ROOT / "lib/chezmoi-guard.ps1") + ";" + body)

    def bind(self):
        self.marker.write_bytes(("dotfiles-chezmoi-v1\n" + str(self.home.resolve()) + "\n" +
                                 str(self.repo.resolve()) + "\n").encode())

    def git(self, *args, cwd=None):
        return subprocess.run([self.git_exe, *args], cwd=cwd or self.repo, env=self.env,
                              stdin=subprocess.DEVNULL, capture_output=True, text=True,
                              check=True, timeout=30).stdout.strip()

    def setup_native(self):
        self.bind()
        (self.repo / "home").mkdir()
        (self.repo / ".chezmoiroot").write_text("home\n")
        (self.repo / "home/dot_sample").write_text("initial\n")
        self.git("init", "--template=", "-b", "main")
        self.git("config", "core.autocrlf", "false")
        self.git("add", ".")
        self.git("commit", "-qm", "synthetic initial")
        self.remote = self.f.root / "remote.git"
        self.git("clone", "--bare", str(self.repo), str(self.remote))
        self.git("remote", "add", "origin", str(self.remote))
        self.git("fetch", "origin")
        self.git("branch", "--set-upstream-to=origin/main", "main")
        config = self.home / ".config/chezmoi/chezmoi.toml"
        config.parent.mkdir(parents=True)
        config.write_text("[git]\nautoAdd=false\nautoCommit=false\nautoPush=false\n"
                          "[update]\ncommand='git'\nargs=['-c','rebase.autoStash=false','-c',"
                          "'merge.autoStash=false','pull','--ff-only','--no-rebase','--no-autostash',"
                          "'--no-recurse-submodules']\nrecurseSubmodules=false\n")
        self.config = config
        self.f.config = config
        self.f.cache = self.home / ".cache/chezmoi"
        self.f.state = self.home / ".local/state/chezmoi/chezmoi.boltdb"
        self.f.cache.mkdir(parents=True)
        self.f.state.parent.mkdir(parents=True)
        # Inspected initial application is an operator action, not unattended update.
        result = self.f.run("apply")
        self.assertEqual(result.returncode, 0, result.stderr)

    def update(self, before="", after=""):
        return self.ps(". " + ps_string(ROOT / "scripts/chezmoi-update.ps1") + ";" + before +
                       "Invoke-DotfilesNativeUpdate -HomePath " + ps_string(self.home) + ";" + after)

    def test_legacy_target_guard_uses_ancestors_and_explicit_target(self):
        self.bind()
        target = self.home / ".codex/config.toml"
        unrelated = self.f.root / "unrelated/config.toml"
        result = self.guard("@( (Test-DotfilesLegacyWriteAllowed -TargetPath " + ps_string(target) +
                            "), (Test-DotfilesLegacyWriteAllowed -TargetPath " + ps_string(unrelated) +
                            ") ) | ConvertTo-Json -Compress")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), [False, True])

    def test_malformed_marker_and_partial_handover_fail_closed(self):
        for value in (b"", b"bad\n", b"dotfiles-chezmoi-v1\nwrong\nwrong\n"):
            self.marker.write_bytes(value)
            result = self.guard("if(Test-DotfilesLegacyWriteAllowed -TargetPath " + ps_string(self.home) +
                                "){throw 'old writer enabled'};try {Get-DotfilesNativeBinding -HomePath " +
                                ps_string(self.home) + " | Out-Null;throw 'binding accepted'}catch{if($_ -match 'binding accepted'){throw}}")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.marker.read_bytes(), value)

    def test_guard_resolves_parent_junction_but_not_final_link(self):
        self.bind()
        alias = self.f.root / "alias"
        result = self.ps("New-Item -ItemType Junction -Path " + ps_string(alias) + " -Target " +
                         ps_string(self.home) + " | Out-Null")
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.guard("Test-DotfilesLegacyWriteAllowed -TargetPath " + ps_string(alias / "new/config") )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "False")

    def test_installer_refuses_marked_explicit_target_before_shouldprocess(self):
        self.bind()
        result = self.ps("& " + ps_string(ROOT / "stow-all.ps1") + " -TargetRoot " +
                         ps_string(self.home) + " -WhatIf -Strict")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("legacy writes are disabled", (result.stdout + result.stderr).lower())
        self.assertFalse((self.home / ".gitconfig").exists())

    def test_scheduled_apply_refuses_before_state_or_task_actions(self):
        self.bind()
        result = self.ps("function Get-ScheduledTask {throw 'task queried'};" +
                         "& " + ps_string(ROOT / "scripts/dotfiles-auto-stow.ps1") + " -Apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("legacy writes are disabled", (result.stdout + result.stderr).lower())
        self.assertNotIn("task queried", result.stdout + result.stderr)

    def test_maintenance_persists_in_fresh_process(self):
        (self.marker.parent / "maintenance").mkdir()
        for _ in range(2):
            result = self.guard("if(-not(Test-DotfilesMaintenance -HomePath " + ps_string(self.home) +
                                ")){throw 'maintenance absent'};if(Test-DotfilesLegacyWriteAllowed -TargetPath " +
                                ps_string(self.home / "new") + "){throw 'legacy enabled'}")
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_binding_rejects_copied_home_and_noncanonical_source(self):
        self.git("init", "--template=")
        (self.repo / ".chezmoiroot").write_text("home\n")
        self.bind()
        result = self.guard("Get-DotfilesNativeBinding -HomePath " + ps_string(self.home) + " | ConvertTo-Json -Compress")
        self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(Path(value["Destination"]), self.home)
        self.assertEqual(Path(value["Source"]), self.repo)
        self.marker.write_text("dotfiles-chezmoi-v1\n" + str(self.f.root) + "\n" + str(self.repo) + "\n")
        result = self.guard("Get-DotfilesNativeBinding -HomePath " + ps_string(self.home))
        self.assertNotEqual(result.returncode, 0)

    def test_native_update_regular_files_without_elevation_or_task(self):
        self.setup_native()
        result = self.update("function Start-ScheduledTask {throw 'task dispatch'};function Test-DotfilesElevated {throw 'elevation'};")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / ".sample").read_text(), "initial\n")
        self.assertFalse((self.home / ".sample").is_symlink())
        self.assertEqual(self.git("stash", "list"), "")

    def test_dirty_tracked_and_untracked_source_prevents_native_write(self):
        self.setup_native()
        for path in (self.repo / "home/dot_sample", self.repo / "untracked"):
            original = path.read_bytes() if path.exists() else None
            path.write_text("local edit\n")
            result = self.update()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("[dotfiles]", result.stdout + result.stderr)
            self.assertEqual((self.home / ".sample").read_text(), "initial\n")
            self.assertEqual(path.read_text(), "local edit\n")
            if original is None:
                path.unlink()
            else:
                path.write_bytes(original)

    def test_unsafe_old_update_configuration_refuses(self):
        self.setup_native()
        self.config.write_text("[update]\ncommand='git'\nargs=['pull','--rebase','--autostash']\n")
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("[dotfiles]", result.stdout + result.stderr)
        self.assertEqual((self.home / ".sample").read_text(), "initial\n")

    def test_optout_maintenance_and_session_guard_skip_update(self):
        self.setup_native()
        for before in ("$env:DOTFILES_AUTO_UPDATE='0';", "$env:_DOTFILES_CHECKED='1';"):
            result = self.update(before)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((self.home / ".sample").read_text(), "initial\n")
        (self.marker.parent / "maintenance").touch()
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / ".sample").read_text(), "initial\n")

    def test_missing_backend_and_conflict_are_nonsecret_warnings(self):
        self.setup_native()
        missing = self.update("$env:PATH='';")
        self.assertEqual(missing.returncode, 0, missing.stderr)
        self.assertIn("[dotfiles]", missing.stdout + missing.stderr)
        self.assertEqual((self.home / ".sample").read_text(), "initial\n")
        self.assertEqual(self.update().returncode, 0)
        (self.home / ".sample").write_text("private conflict canary\n")
        (self.repo / "home/dot_sample").write_text("changed portable\n")
        self.git("add", ".")
        self.git("commit", "-qm", "synthetic changed")
        self.git("push", "origin", "main")
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("[dotfiles]", result.stdout + result.stderr)
        self.assertNotIn("private conflict canary", result.stdout + result.stderr)
        self.assertEqual((self.home / ".sample").read_text(), "private conflict canary\n")

    def test_lost_native_state_refuses_to_replace_a_new_foreign_link(self):
        self.setup_native()
        self.f.state.unlink()
        target = self.home / ".sample"
        target.unlink()
        foreign = self.f.root / "foreign"
        foreign.write_text("foreign bytes\n")
        target.symlink_to(foreign)
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("[dotfiles]", result.stdout + result.stderr)
        self.assertTrue(target.is_symlink())
        self.assertEqual(foreign.read_text(), "foreign bytes\n")

    def test_fast_forward_and_divergence_never_stash_or_rebase(self):
        self.setup_native()
        sender = self.f.root / "sender"
        self.git("clone", str(self.remote), str(sender))
        (sender / "home/dot_sample").write_text("upstream\n")
        self.git("add", ".", cwd=sender)
        self.git("commit", "-qm", "upstream change", cwd=sender)
        self.git("push", cwd=sender)
        self.git("config", "pull.rebase", "true")
        self.git("config", "rebase.autoStash", "true")
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / ".sample").read_text(), "upstream\n")
        self.assertEqual(self.git("stash", "list"), "")
        (self.repo / "local").write_text("local branch\n")
        self.git("add", ".")
        self.git("commit", "-qm", "local divergence")
        head = self.git("rev-parse", "HEAD")
        (sender / "remote").write_text("remote branch\n")
        self.git("add", ".", cwd=sender)
        self.git("commit", "-qm", "remote divergence", cwd=sender)
        self.git("push", cwd=sender)
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("[dotfiles]", result.stdout + result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), head)
        self.assertEqual(self.git("stash", "list"), "")

    def test_marker_directory_and_dangling_link_block_both_writers(self):
        for kind in ("directory", "link"):
            if kind == "directory":
                self.marker.mkdir()
            else:
                self.marker.symlink_to(self.f.root / "absent")
            result = self.guard("if(-not(Test-DotfilesNativeOwned " + ps_string(self.home) +
                                ")){throw 'not owned'};if(Test-DotfilesLegacyWriteAllowed " +
                                ps_string(self.home) + "){throw 'legacy allowed'}")
            self.assertEqual(result.returncode, 0, result.stderr)
            result = self.guard("Get-DotfilesNativeBinding " + ps_string(self.home))
            self.assertNotEqual(result.returncode, 0)
            if kind == "directory":
                self.marker.rmdir()
            else:
                self.marker.unlink()

    def test_profile_dispatch_uses_marker_and_maintenance_in_fresh_shells(self):
        profile = ROOT / "win/powershell/Documents/PowerShell/profile.ps1"
        fake_repo = self.f.root / "profile source"
        (fake_repo / "scripts").mkdir(parents=True)
        (fake_repo / "lib").mkdir()
        shutil.copyfile(ROOT / "lib/chezmoi-guard.ps1", fake_repo / "lib/chezmoi-guard.ps1")
        trace = self.f.root / "dispatch"
        for name in ("dotfiles-update", "chezmoi-update", "payload-update"):
            (fake_repo / ("scripts/" + name + ".ps1")).write_text(
                "Add-Content -LiteralPath " + ps_string(trace) + " -Value '" + name + "'\n")
        body = ("$env:DOTFILES_DIR=" + ps_string(fake_repo) + ";$IsInteractive=$true;" +
                "$ast=[Management.Automation.Language.Parser]::ParseFile(" + ps_string(profile) +
                ",[ref]$null,[ref]$null);$tail=@($ast.EndBlock.Statements | Where-Object " +
                "{ $_ -is [Management.Automation.Language.IfStatementAst] -and " +
                "$_.Extent.Text.StartsWith('if ($IsInteractive)') });" +
                "if($tail.Count -ne 1){throw 'profile tail not found'};Invoke-Expression $tail[0].Extent.Text")
        result = self.ps(body)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(trace.read_text().splitlines(), ["dotfiles-update", "payload-update"])
        trace.unlink()
        # A native source may be independent from a stale DOTFILES_DIR/default.
        native_repo = self.f.root / "bound source"
        (native_repo / "scripts").mkdir(parents=True)
        (native_repo / "lib").mkdir()
        (native_repo / ".git").mkdir()
        (native_repo / ".chezmoiroot").write_text("home\n")
        shutil.copyfile(ROOT / "lib/chezmoi-guard.ps1", native_repo / "lib/chezmoi-guard.ps1")
        for name in ("chezmoi-update", "payload-update"):
            (native_repo / ("scripts/" + name + ".ps1")).write_text(
                "Add-Content -LiteralPath " + ps_string(trace) + " -Value 'native-" + name + "'\n")
        # Even the guard in the retired checkout must never be sourced.
        (fake_repo / "lib/chezmoi-guard.ps1").write_text(
            "Add-Content -LiteralPath " + ps_string(trace) + " -Value 'stale-guard';throw 'stale guard loaded'\n")
        self.marker.write_bytes(("dotfiles-chezmoi-v1\n" + str(self.home) + "\n" + str(native_repo) + "\n").encode())
        result = self.ps(body)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(trace.read_text().splitlines(), ["native-chezmoi-update", "native-payload-update"])
        trace.unlink()
        self.marker.write_text("malformed marker cannot fall back\n")
        result = self.ps(body)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("[dotfiles]", result.stdout + result.stderr)
        self.assertFalse(trace.exists())
        self.marker.unlink()
        for marker_kind in ("directory", "dangling-link"):
            if marker_kind == "directory":
                self.marker.mkdir()
            else:
                self.marker.symlink_to(self.f.root / "missing-marker-referent")
            result = self.ps(body)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("[dotfiles]", result.stdout + result.stderr)
            self.assertFalse(trace.exists())
            if marker_kind == "directory":
                self.marker.rmdir()
            else:
                self.marker.unlink()
        (self.marker.parent / "maintenance").touch()
        for _ in range(2):
            result = self.ps(body)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(trace.exists())

    def test_windows_powershell_can_load_guard_without_version_upgrade(self):
        shell = Path(os.environ["SYSTEMROOT"]) / "System32/WindowsPowerShell/v1.0/powershell.exe"
        if not shell.is_file():
            self.skipTest("Windows PowerShell 5.1 not available")
        self.bind()
        body = ". " + ps_string(ROOT / "lib/chezmoi-guard.ps1") + ";if(-not(Test-DotfilesNativeOwned " + ps_string(self.home) + ")){throw 'not owned'};exit 0"
        encoded = base64.b64encode(body.encode("utf-16le")).decode()
        result = subprocess.run([str(shell), "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
                                env=self.env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_binding_rejects_repository_subdirectory_as_source(self):
        self.setup_native()
        self.marker.write_bytes(("dotfiles-chezmoi-v1\n" + str(self.home) + "\n" +
                                 str(self.repo / "home") + "\n").encode())
        result = self.guard("Get-DotfilesNativeBinding " + ps_string(self.home))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.home / ".sample").read_text(), "initial\n")

    def test_unattended_git_disables_local_hooks_and_fsmonitor(self):
        self.setup_native()
        hooks = self.f.root / "hooks"
        hooks.mkdir()
        trace = self.f.root / "hook invoked"
        payload = "#!/bin/sh\nprintf invoked > '" + trace.as_posix() + "'\n"
        for name in ("post-merge", "monitor"):
            (hooks / name).write_text(payload)
        self.git("config", "core.hooksPath", str(hooks))
        self.git("config", "core.fsmonitor", str(hooks / "monitor"))
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(trace.exists(), "unattended update executed a local Git callback")
        probe = self.ps(". " + ps_string(ROOT / "scripts/chezmoi-update.ps1") +
                        ";$binding=Get-DotfilesNativeBinding " + ps_string(self.home) +
                        ";$r=Invoke-DotfilesNativeProcess " + ps_string(self.git_exe) +
                        " @('config','--get-regexp','^(core.hooksPath|core.fsmonitor|maintenance.auto|gc.auto)$') $binding;" +
                        "$r.Output")
        self.assertEqual(probe.returncode, 0, probe.stderr)
        lines = probe.stdout.lower().splitlines()
        self.assertIn("maintenance.auto false", lines)
        self.assertIn("gc.auto 0", lines)
        self.assertIn("core.fsmonitor false", lines)

    def test_binding_rejects_non_dotfiles_repository_root(self):
        self.setup_native()
        (self.repo / ".chezmoiroot").unlink()
        result = self.guard("Get-DotfilesNativeBinding " + ps_string(self.home))
        self.assertNotEqual(result.returncode, 0)

    def test_local_native_defaults_cannot_force_conflict_or_switch_git_tree(self):
        self.setup_native()
        alternative = self.f.root / "other repository"
        self.git("clone", str(self.remote), str(alternative))
        self.config.write_text("workingTree=" + json.dumps(str(alternative)) +
                               "\nforce=true\nuseBuiltinGit=true\n" + self.config.read_text())
        (self.home / ".sample").write_text("private edited destination\n")
        (self.repo / "home/dot_sample").write_text("new portable\n")
        self.git("add", ".")
        self.git("commit", "-qm", "portable edit")
        self.git("push", "origin", "main")
        previous = self.git("rev-parse", "HEAD", cwd=alternative)
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / ".sample").read_text(), "private edited destination\n")
        self.assertEqual(self.git("rev-parse", "HEAD", cwd=alternative), previous)
        (self.home / ".sample").write_text("initial\n")
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / ".sample").read_text(), "new portable\n")
        self.assertEqual(self.git("rev-parse", "HEAD", cwd=alternative), previous)

    def test_git_worktree_redirect_cannot_escape_native_source_binding(self):
        self.setup_native()
        alternative = self.f.root / "redirected source"
        alternative.mkdir()
        shutil.copytree(self.repo / "home", alternative / "home")
        shutil.copyfile(self.repo / ".chezmoiroot", alternative / ".chezmoiroot")
        sender = self.f.root / "redirect sender"
        self.git("clone", str(self.remote), str(sender))
        (sender / "home/dot_sample").write_text("remote redirected\n")
        self.git("add", ".", cwd=sender)
        self.git("commit", "-qm", "remote redirected", cwd=sender)
        self.git("push", cwd=sender)
        self.git("config", "core.worktree", str(alternative))
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("[dotfiles]", result.stdout + result.stderr)
        self.assertEqual((alternative / "home/dot_sample").read_text(), "initial\n")
        self.assertEqual((self.home / ".sample").read_text(), "initial\n")

    def test_native_backend_uses_provisioned_binary_when_path_omits_it(self):
        self.setup_native()
        installed = self.home / ".local/bin/chezmoi.exe"
        installed.parent.mkdir(parents=True)
        shutil.copyfile(self.f.binary, installed)
        self.env["PATH"] = os.pathsep.join((str(Path(self.git_exe).parent), str(Path(self.pwsh).parent),
                                            os.environ["SYSTEMROOT"] + "\\System32"))
        (self.repo / "home/dot_sample").write_text("installed backend\n")
        self.git("add", ".")
        self.git("commit", "-qm", "backend discovery")
        self.git("push", "origin", "main")
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / ".sample").read_text(), "installed backend\n")
        self.assertEqual(self.git("stash", "list"), "")

    def publish_new_target(self, upstream=True):
        source = self.repo
        if upstream:
            source = self.f.root / "new target sender"
            self.git("clone", str(self.remote), str(source))
        (source / "home/dot_native_new").write_text("new portable target\n")
        self.git("add", ".", cwd=source)
        self.git("commit", "-qm", "new managed target", cwd=source)
        self.git("push", "origin", "main", cwd=source)

    def test_new_upstream_existing_regular_target_is_preserved(self):
        self.setup_native()
        target = self.home / ".native_new"
        target.write_text("private preexisting target\n")
        self.publish_new_target()
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("[dotfiles]", result.stdout + result.stderr)
        self.assertNotIn("private preexisting", result.stdout + result.stderr)
        self.assertEqual(target.read_text(), "private preexisting target\n")
        self.assertTrue((self.repo / "home/dot_native_new").exists())

    def test_new_upstream_equal_content_foreign_link_is_preserved(self):
        self.setup_native()
        target = self.home / ".native_new"
        foreign = self.f.root / "same-content foreign"
        foreign.write_text("new portable target\n")
        target.symlink_to(foreign)
        self.publish_new_target()
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("[dotfiles]", result.stdout + result.stderr)
        self.assertTrue(target.is_symlink())
        self.assertEqual(foreign.read_text(), "new portable target\n")

    def test_already_added_source_preserves_unapproved_existing_target(self):
        self.setup_native()
        target = self.home / ".native_new"
        target.write_text("unapproved local target\n")
        self.publish_new_target(upstream=False)
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("[dotfiles]", result.stdout + result.stderr)
        self.assertEqual(target.read_text(), "unapproved local target\n")

    def test_new_absent_upstream_target_is_applied(self):
        self.setup_native()
        self.publish_new_target()
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / ".native_new").read_text(), "new portable target\n")
        self.assertNotIn("[dotfiles]", result.stdout + result.stderr)

    def test_empty_native_state_preserves_existing_edit(self):
        self.setup_native()
        self.f.state.write_bytes(b"")
        (self.home / ".sample").write_text("private new local edit\n")
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("[dotfiles]", result.stdout + result.stderr)
        self.assertEqual((self.home / ".sample").read_text(), "private new local edit\n")
        self.assertEqual(self.f.state.read_bytes(), b"")
