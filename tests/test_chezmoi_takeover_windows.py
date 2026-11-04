"""Windows writer handover and native updater behavior in disposable homes."""

import base64
import functools
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


def system32(name):
    return str(Path(os.environ["SYSTEMROOT"]) / "System32" / name)


@functools.cache
def current_user_sid():
    output = subprocess.run([system32("whoami.exe"), "/user", "/fo", "csv", "/nh"], stdin=subprocess.DEVNULL,
                            capture_output=True, text=True, check=True, timeout=30).stdout
    return output.strip().rsplit(",", 1)[1].strip('"')


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
        # The fixture chezmoi stays first on PATH: the updater must not use it.
        self.install_backend()

    def icacls(self, path, *args):
        result = subprocess.run([system32("icacls.exe"), str(path), *args], stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def install_backend(self, path=None):
        # The explicit protected DACL W1-chezmoi writes; the runner's temporary
        # directory ACL is never relied on.
        path = path or self.home / ".local/bin/chezmoi.exe"
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(self.f.binary, path)
        self.icacls(path, "/inheritance:r", "/grant:r", "*" + current_user_sid() + ":(F)",
                    "*S-1-5-18:(F)", "*S-1-5-32-544:(F)")
        return path

    def junction(self, link, target):
        result = self.ps("New-Item -ItemType Junction -Path " + ps_string(link) + " -Target " +
                         ps_string(target) + " | Out-Null")
        self.assertEqual(result.returncode, 0, result.stderr)

    def publish_sample(self, text):
        (self.repo / "home/dot_sample").write_text(text)
        self.git("commit", "-qam", "sample backend change")
        self.git("push", "origin", "main")

    def assert_backend_refused(self, result):
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("[dotfiles] Native update skipped", output)
        self.assertIn("chezmoi.exe", output)
        self.assertIn("docs/bootstrap.md W1-chezmoi", output)
        self.assertEqual(output.count("[dotfiles]"), 1, output)
        self.assertNotIn("S-1-", output)
        self.assertEqual((self.home / ".sample").read_text(), "initial\n")

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

    def test_update_excludes_directories_and_applies_files_in_existing_parent(self):
        self.setup_native()
        parent = self.home / ".managed"
        parent.mkdir()
        acl_before = self.ps("(Get-Acl -LiteralPath " + ps_string(parent) + ").Sddl")
        self.assertEqual(acl_before.returncode, 0, acl_before.stderr)
        source_parent = self.repo / "home/dot_managed"
        source_parent.mkdir()
        (source_parent / "settings").write_text("new nested file\n")
        self.git("add", ".")
        self.git("commit", "-qm", "file in prepared parent")
        self.git("push", "origin", "main")
        trace = self.f.root / "native update arguments.json"
        before = "$script:nativeProcess=(Get-Item Function:Invoke-DotfilesNativeProcess).ScriptBlock;" + \
            "function Invoke-DotfilesNativeProcess {param($Program,$Arguments,$Binding);" + \
            "if($Arguments -contains 'update'){ConvertTo-Json -InputObject @($Arguments) -Compress | " + \
            "Set-Content -LiteralPath " + ps_string(trace) + "};" + \
            "& $script:nativeProcess $Program $Arguments $Binding};"
        result = self.update(before)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("[dotfiles]", result.stdout + result.stderr)
        self.assertIn("--exclude=dirs", json.loads(trace.read_text(encoding="utf-8-sig")))
        self.assertEqual((parent / "settings").read_text(), "new nested file\n")
        self.assertFalse((parent / "settings").is_symlink())
        acl_after = self.ps("(Get-Acl -LiteralPath " + ps_string(parent) + ").Sddl")
        self.assertEqual(acl_after.returncode, 0, acl_after.stderr)
        self.assertEqual(acl_after.stdout, acl_before.stdout)

    def test_update_keeps_explicit_protected_dacl_while_content_updates(self):
        self.setup_native()
        target = self.home / ".sample"
        # Replace inherited entries with one explicit owner entry; native Windows
        # writes in place, so a routine update must not reset this private DACL.
        acl_before = self.ps("$p=" + ps_string(target) + ";$a=Get-Acl -LiteralPath $p;" +
                             "$a.SetAccessRuleProtection($true,$false);" +
                             "$a.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(" +
                             "[System.Security.Principal.WindowsIdentity]::GetCurrent().User," +
                             "'FullControl','Allow'));Set-Acl -LiteralPath $p -AclObject $a;" +
                             "(Get-Acl -LiteralPath $p).Sddl")
        self.assertEqual(acl_before.returncode, 0, acl_before.stderr)
        self.assertIn("D:P", acl_before.stdout)
        sender = self.f.root / "content update sender"
        self.git("clone", str(self.remote), str(sender))
        (sender / "home/dot_sample").write_text("updated\n")
        self.git("commit", "-qam", "update existing target", cwd=sender)
        self.git("push", cwd=sender)
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("[dotfiles]", result.stdout + result.stderr)
        self.assertEqual(target.read_text(), "updated\n")
        self.assertFalse(target.is_symlink())
        acl_after = self.ps("(Get-Acl -LiteralPath " + ps_string(target) + ").Sddl")
        self.assertEqual(acl_after.returncode, 0, acl_after.stderr)
        self.assertEqual(acl_after.stdout, acl_before.stdout)

    def test_update_refuses_new_file_when_managed_parent_is_absent(self):
        self.setup_native()
        sender = self.f.root / "new directory sender"
        self.git("clone", str(self.remote), str(sender))
        source_parent = sender / "home/dot_missing"
        source_parent.mkdir()
        (source_parent / "settings").write_text("new nested file\n")
        self.git("add", ".", cwd=sender)
        self.git("commit", "-qm", "new managed parent", cwd=sender)
        self.git("push", cwd=sender)
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("[dotfiles]", result.stdout + result.stderr)
        self.assertFalse((self.home / ".missing").exists())
        self.assertTrue((self.repo / "home/dot_missing/settings").is_file())
        self.assertEqual((self.home / ".sample").read_text(), "initial\n")

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
        # A login updates; payloads install only through sync-payloads.
        self.assertEqual(trace.read_text().splitlines(), ["dotfiles-update"])
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
        self.assertEqual(trace.read_text().splitlines(), ["native-chezmoi-update"])
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
        # The updater's binary check lives in the guard too and must parse there.
        body = ". " + ps_string(ROOT / "lib/chezmoi-guard.ps1") + ";if(-not(Test-DotfilesNativeOwned " + ps_string(self.home) + ")){throw 'not owned'}" + \
            ";foreach($f in 'Test-DotfilesNativeChezmoiPath','Test-DotfilesTrustedFileSecurity','Open-DotfilesNativeChezmoi')" + \
            "{if(-not(Get-Command $f -CommandType Function -ErrorAction SilentlyContinue)){throw ($f+' missing')}};exit 0"
        encoded = base64.b64encode(body.encode("utf-16le")).decode()
        # Match the PS7 fixture budget, including hosted e2e process startup.
        result = subprocess.run([str(shell), "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
                                cwd=self.f.root, env=self.env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
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

    def test_path_shadows_never_replace_the_provisioned_binary(self):
        self.setup_native()
        local_bin = self.home / ".local/bin"
        earlier = self.f.root / "earlier path entry"
        earlier.mkdir()
        marker = self.f.root / "shadow executed"
        for directory in (earlier, local_bin):
            # PATHEXT puts .COM before .EXE; a PE image runs whatever its extension.
            shutil.copyfile(system32("whoami.exe"), directory / "chezmoi.com")
            (directory / "chezmoi.cmd").write_text("@echo shadow>>\"" + str(marker) + "\"\n")
        self.env["PATH"] = os.pathsep.join((str(earlier), str(local_bin), self.env["PATH"]))
        self.publish_sample("provisioned backend\n")
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("[dotfiles]", result.stdout + result.stderr)
        self.assertFalse(marker.exists())
        self.assertEqual((self.home / ".sample").read_text(), "provisioned backend\n")

    def test_missing_provisioned_binary_warns_without_path_fallback(self):
        self.setup_native()
        (self.home / ".local/bin/chezmoi.exe").unlink()
        self.publish_sample("path fallback must not apply\n")
        self.assert_backend_refused(self.update())

    def test_foreign_owner_or_writer_refuses_the_provisioned_binary(self):
        self.setup_native()
        installed = self.home / ".local/bin/chezmoi.exe"
        self.publish_sample("untrusted backend must not run\n")
        # BUILTIN\Users stands for any other account, such as an app sandbox group.
        for change in (("/grant", "*S-1-5-32-545:(M)"), ("/setowner", "*S-1-5-32-545")):
            installed.unlink()
            self.install_backend()
            self.icacls(installed, *change)
            self.assert_backend_refused(self.update())

    def test_linked_binary_or_parent_directory_is_refused(self):
        self.setup_native()
        local = self.home / ".local"
        installed = local / "bin/chezmoi.exe"
        elsewhere = self.install_backend(self.f.root / "trusted elsewhere/chezmoi.exe")
        self.publish_sample("linked backend must not run\n")
        installed.unlink()
        installed.symlink_to(elsewhere)
        self.assert_backend_refused(self.update())
        installed.unlink()
        installed.parent.rmdir()
        self.junction(installed.parent, elsewhere.parent)
        self.assert_backend_refused(self.update())
        installed.parent.rmdir()
        moved = self.f.root / "moved local"
        local.rename(moved)
        self.install_backend(moved / "bin/chezmoi.exe")
        self.junction(local, moved)
        self.assert_backend_refused(self.update())

    def test_trust_decision_reads_owner_and_dacl_from_the_held_handle(self):
        self.setup_native()
        installed = self.home / ".local/bin/chezmoi.exe"
        # Each step runs directly, so a refusal names its cause. Foreign read and
        # deny entries and OWNER RIGHTS (hosted runners add it) stay acceptable;
        # a foreign owner or a foreign write bit does not. The guard alone
        # provides the check, as the doctor and setup-host load it. A null DACL
        # refuses, and so does each DACL entry .NET's rule projection skips,
        # even for this user: an object ACE with no GUIDs (which the kernel
        # applies like a plain allow entry, and only the entry-type check
        # refuses), a compound ACE and an unknown (custom) ACE type.
        result = self.guard("$p=" + ps_string(installed) +
                            ";if(-not(Test-DotfilesNativeChezmoiPath $p)){throw 'path refused'}" +
                            ";$s=[IO.FileStream]::new($p,'Open','Read','Read')" +
                            ";try{$sd=[IO.FileSystemAclExtensions]::GetAccessControl($s)}finally{$s.Dispose()}" +
                            ";if(-not(Test-DotfilesTrustedFileSecurity $sd)){throw ('trusted copy refused: '+" +
                            "$sd.GetSecurityDescriptorSddlForm('Owner,Access'))}" +
                            ";$users=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')" +
                            ";foreach($r in @('S-1-5-32-545,ReadAndExecute,Allow','S-1-5-32-545,Write,Deny','S-1-3-4,FullControl,Allow'))" +
                            "{$f=$r.Split(',');$sd.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(" +
                            "[Security.Principal.SecurityIdentifier]::new($f[0]),$f[1],$f[2]))}" +
                            ";if(-not(Test-DotfilesTrustedFileSecurity $sd)){throw 'foreign read, deny or OWNER RIGHTS entry refused'}" +
                            ";$owner=$sd.GetOwner([Security.Principal.SecurityIdentifier]);$sd.SetOwner($users)" +
                            ";if(Test-DotfilesTrustedFileSecurity $sd){throw 'foreign owner trusted'};$sd.SetOwner($owner)" +
                            ";$sd.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($users,'AppendData','Allow'))" +
                            ";if(Test-DotfilesTrustedFileSecurity $sd){throw 'foreign append right trusted'}" +
                            ";function ConvertTo-FileSecurity($raw){$b=[byte[]]::new($raw.BinaryLength);$raw.GetBinaryForm($b,0)" +
                            ";$f=[Security.AccessControl.FileSecurity]::new();$f.SetSecurityDescriptorBinaryForm($b);$f}" +
                            ";$me=[Security.Principal.WindowsIdentity]::GetCurrent().User" +
                            ";$n=ConvertTo-FileSecurity ([Security.AccessControl.RawSecurityDescriptor]::new(" +
                            "'O:'+$me.Value+'G:'+$me.Value+'D:NO_ACCESS_CONTROL'))" +
                            ";if(Test-DotfilesTrustedFileSecurity $n){throw 'null DACL trusted'}" +
                            ";foreach($ace in @([Security.AccessControl.ObjectAce]::new('None','AccessAllowed',0x1F01FF,$me," +
                            "'None',[Guid]::Empty,[Guid]::Empty,$false,$null)" +
                            ",[Security.AccessControl.CompoundAce]::new('None',0x1F01FF,'Impersonation',$me)" +
                            ",[Security.AccessControl.CustomAce]::new([Enum]::ToObject([Security.AccessControl.AceType],17)," +
                            "'None',[byte[]]::new(4)))){" +
                            "$acl=[Security.AccessControl.RawAcl]::new([Security.AccessControl.GenericAcl]::AclRevisionDS,2)" +
                            ";$acl.InsertAce(0,[Security.AccessControl.CommonAce]::new('None','AccessAllowed',0x1F01FF,$me,$false,$null))" +
                            ";$acl.InsertAce(1,$ace)" +
                            ";$o=ConvertTo-FileSecurity ([Security.AccessControl.RawSecurityDescriptor]::new(" +
                            "'DiscretionaryAclPresent,SelfRelative',$me,$me,$null,$acl))" +
                            ";$kept=@([Security.AccessControl.RawSecurityDescriptor]::new($o.GetSecurityDescriptorBinaryForm(),0)" +
                            ".DiscretionaryAcl|Where-Object{$_.GetType() -eq $ace.GetType()})" +
                            ";if($kept.Count -ne 1){throw ($ace.GetType().Name+' not kept by .NET')}" +
                            ";if(Test-DotfilesTrustedFileSecurity $o){throw ($ace.GetType().Name+' trusted')}}")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_held_binary_handle_blocks_renaming_its_parent_directories(self):
        # Records the NTFS behavior the updater relies on: while its read-only
        # handle is open, .local\bin and .local cannot be renamed away and replaced.
        self.setup_native()
        local = self.home / ".local"
        moves = [(local / "bin", self.f.root / "bin moved"), (local, self.f.root / "local moved")]
        attempts = ";".join("try{[IO.Directory]::Move(" + ps_string(source) + "," + ps_string(target) +
                            ");'moved'}catch{'refused'}" for source, target in moves)
        release = ("[IO.Directory]::Move(" + ps_string(moves[0][0]) + "," + ps_string(moves[0][1]) + ");" +
                   "[IO.Directory]::Move(" + ps_string(moves[0][1]) + "," + ps_string(moves[0][0]) + ");'released'")
        result = self.ps(". " + ps_string(ROOT / "scripts/chezmoi-update.ps1") +
                         ";$held=Open-DotfilesNativeChezmoi -Destination " + ps_string(self.home) +
                         ";if(-not $held){throw 'provisioned binary refused'};try{" + attempts +
                         "}finally{$held.Dispose()};" + release)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.split(), ["refused", "refused", "released"])

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
