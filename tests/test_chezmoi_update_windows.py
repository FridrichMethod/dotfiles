"""Windows login updater and exact-exe trust behavior in disposable homes."""

import base64
import functools
import itertools
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from chezmoi_source_support import SourceFixture
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


@unittest.skipUnless(shutil.which("pwsh"), "PowerShell 7 unavailable")
class PowerShellUpdateCultureTests(unittest.TestCase):
    """Updater decisions before native Windows trust checks, using fake homes."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.pwsh = shutil.which("pwsh")
        essentials = {"SYSTEMROOT", "WINDIR", "COMSPEC", "PATHEXT", "SYSTEMDRIVE", "PATH",
                      "LANG", "LANGUAGE", "TZ"}
        self.env = {key: value for key, value in os.environ.items()
                    if key.upper() in essentials or key.upper().startswith("LC_")}
        self.env.update(HOME=str(self.root), USERPROFILE=str(self.root),
                        POWERSHELL_TELEMETRY_OPTOUT="1", POWERSHELL_UPDATECHECK="Off",
                        XDG_CACHE_HOME=str(self.root / "cache"), XDG_CONFIG_HOME=str(self.root / "config"),
                        XDG_DATA_HOME=str(self.root / "data"), XDG_STATE_HOME=str(self.root / "state"))
        for key in ("APPDATA", "LOCALAPPDATA", "TMP", "TEMP", "TMPDIR"):
            directory = self.root / key.lower()
            directory.mkdir()
            self.env[key] = str(directory)

    def run_culture(self, culture, body):
        script = ("$ErrorActionPreference='Stop'\n"
                  f"$culture = [Globalization.CultureInfo]::GetCultureInfo('{culture}')\n"
                  "[Threading.Thread]::CurrentThread.CurrentCulture = $culture\n"
                  "[Threading.Thread]::CurrentThread.CurrentUICulture = $culture\n"
                  f". {ps_string(ROOT / 'scripts/chezmoi-update.ps1')}\n"
                  "[Threading.Thread]::CurrentThread.CurrentCulture.Name\n" + body)
        result = subprocess.run([self.pwsh, "-NoProfile", "-NonInteractive", "-EncodedCommand",
                                 base64.b64encode(script.encode("utf-16le")).decode()],
                                cwd=self.root, env=self.env, stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")
        output = result.stdout.splitlines()
        self.assertEqual(output[0], culture)
        return json.loads("\n".join(output[1:]))

    def test_onedrive_case_variants_refuse_before_backend_in_every_culture(self):
        # Enumerate all 256 ASCII case spellings. Windows shares the source
        # directory across spellings, but each config preserves its own text.
        names = ["".join(chars) for chars in itertools.product(*[(c.lower(), c.upper()) for c in "onedrive"])]
        names += ["prefixOneDriveSuffix", "OneDrive-backup", "ordinary", "One-Drive"]
        for index, name in enumerate(names):
            source = self.root / name
            (source / ".git").mkdir(parents=True, exist_ok=True)
            (source / ".chezmoiroot").write_text("home\n")
            home = self.root / f"home {index}"
            config = home / ".config/chezmoi/chezmoi.toml"
            config.parent.mkdir(parents=True)
            config.write_bytes((f'destDir = "{home.as_posix()}"\n'
                                f'sourceDir = "{source.as_posix()}"\n').encode())
            state = home / ".local/state/chezmoi/chezmoi.boltdb"
            state.parent.mkdir(parents=True)
            state.write_bytes(b"fixture state: no backend may open it")
        body = (f"$results = @(foreach ($index in 0..{len(names) - 1}) {{\n"
                f"$homePath = Join-Path {ps_string(self.root)} ('home ' + $index)\n")
        body += """
            Remove-Item Env:_DOTFILES_CHECKED -ErrorAction SilentlyContinue
            $errors = [IO.StringWriter]::new()
            $originalError = [Console]::Error
            try {
                [Console]::SetError($errors)
                Invoke-DotfilesChezmoiUpdate -HomePath $homePath
            }
            finally { [Console]::SetError($originalError) }
            $errors.ToString().Trim()
            $errors.Dispose()
        })
        ConvertTo-Json -InputObject $results -Compress
"""
        for culture in ("en-US", "tr-TR", "az-Latn-AZ"):
            with self.subTest(culture=culture):
                output = self.run_culture(culture, body)
                self.assertEqual(len(output), len(names))
                for name, warning in zip(names, output):
                    with self.subTest(source=name):
                        self.assertEqual(warning.count("[dotfiles]"), 1, warning)
                        if name in ("ordinary", "One-Drive"):
                            self.assertIn("W1-chezmoi", warning)
                            self.assertNotIn("independent-clone", warning)
                        else:
                            self.assertIn("independent-clone", warning)

    def test_inherited_environment_prefix_cleanup_is_culture_independent(self):
        removed = ("GIT_DOTFILES_UPPER", "git_dotfiles_lower", "GiT_Dotfiles_Mixed",
                   "CHEZMOI_DOTFILES_UPPER", "chezmoi_dotfiles_lower", "ChEzMoI_Dotfiles_Mixed")
        retained = ("GIT", "CHEZMOI", "GITLIKE_DOTFILES", "CHEZMOILOG_DOTFILES", "NOT_GIT_DOTFILES")
        names = removed + retained
        self.env.update({name: "synthetic-fixture" for name in names})
        # A real child reports only our synthetic names. No environment dump
        # or Git/chezmoi invocation can expose credentials or use host state.
        child = ("import json,os; names=" + repr(names) + "; "
                 "print(json.dumps([name for name in names if name in os.environ]))")
        body = (f"$paths = [pscustomobject]@{{ Source = {ps_string(self.root)}; Destination = {ps_string(self.root)} }}\n"
                f"$result = Invoke-DotfilesUpdateProcess {ps_string(sys.executable)} "
                f"@('-I', '-B', '-c', {ps_string(child)}) $paths\n"
                "if ($result.Code -ne 0) { throw 'environment probe failed' }\n"
                "$result.Output\n")
        for culture in ("en-US", "tr-TR", "az-Latn-AZ"):
            with self.subTest(culture=culture):
                self.assertEqual(self.run_culture(culture, body), list(retained))


@unittest.skipUnless(os.name == "nt", "the Windows login updater requires Windows")
class WindowsUpdateTests(unittest.TestCase):
    def test_regular_file_mode_overrides_a_local_symlink_mode(self):
        self.setup_home()
        self.config.write_text('mode="symlink"\n' + self.config.read_text(), newline="\n")
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
        self.maintenance = self.home / ".config/dotfiles/maintenance"
        self.maintenance.parent.mkdir(parents=True)
        self.config = self.home / ".config/chezmoi/chezmoi.toml"
        self.config.parent.mkdir(parents=True)
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

    @staticmethod
    def chezmoi_path(path):
        # The form chezmoi init writes on Windows: forward slashes, upper-case drive.
        text = Path(path).resolve().as_posix()
        return text[0].upper() + text[1:]

    def top(self, source=None, home=None):
        # The top-level lines chezmoi init writes, which the login updater reads.
        return ('destDir = "' + self.chezmoi_path(home or self.home) + '"\n' +
                'sourceDir = "' + self.chezmoi_path(source or self.repo) + '"\n')

    def configure(self, tables="", source=None, home=None):
        # Always LF: text mode would write CRLF here, which the guard refuses.
        self.config.write_bytes((self.top(source, home) + tables).encode())

    def make_checkout(self, path):
        # What the PowerShell guard requires of a source: .git and .chezmoiroot.
        (path / ".git").mkdir(parents=True, exist_ok=True)
        (path / ".chezmoiroot").write_text("home\n")

    def git(self, *args, cwd=None):
        return subprocess.run([self.git_exe, *args], cwd=cwd or self.repo, env=self.env,
                              stdin=subprocess.DEVNULL, capture_output=True, text=True,
                              check=True, timeout=30).stdout.strip()

    def setup_home(self):
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
        self.configure("[git]\nautoAdd=false\nautoCommit=false\nautoPush=false\n"
                       "[update]\ncommand='git'\nargs=['-c','rebase.autoStash=false','-c',"
                       "'merge.autoStash=false','pull','--ff-only','--no-rebase','--no-autostash',"
                       "'--no-recurse-submodules']\nrecurseSubmodules=false\n")
        self.f.config = self.config
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
        self.assertIn("[dotfiles] [warn] Update skipped", output)
        self.assertIn("chezmoi.exe", output)
        self.assertIn("docs/bootstrap.md W1-chezmoi", output)
        self.assertEqual(output.count("[dotfiles]"), 1, output)
        self.assertNotIn("S-1-", output)
        self.assertEqual((self.home / ".sample").read_text(), "initial\n")

    def update(self, before="", after=""):
        return self.ps(". " + ps_string(ROOT / "scripts/chezmoi-update.ps1") + ";" + before +
                       "Invoke-DotfilesChezmoiUpdate -HomePath " + ps_string(self.home) + ";" + after)

    def paths(self, home=None):
        return self.guard("Get-DotfilesChezmoiPaths -HomePath " + ps_string(home or self.home) +
                          " | ConvertTo-Json -Compress")

    def test_malformed_config_fails_closed(self):
        self.make_checkout(self.repo)
        valid = self.top() + "umask = 63\n\n[data]\n  host = \"win\"\n"
        exact = 'sourceDir = "' + self.chezmoi_path(self.repo) + '"\n'
        destination = 'destDir = "' + self.chezmoi_path(self.home) + '"\n'
        for name, value in (("empty", ""), ("no destDir", valid.replace(destination, "")),
                            ("no sourceDir", valid.replace(exact, "")),
                            ("two sourceDir lines", valid.replace(exact, exact * 2)),
                            ("two destDir lines", valid.replace(destination, destination * 2)),
                            ("sourceDir after a table", valid.replace(exact, "") + exact),
                            ("a case variant", valid.replace("sourceDir =", "SourceDir =")),
                            ("a workingTree key", valid.replace(exact, exact + exact.replace("sourceDir", "workingTree"))),
                            ("a quoted key", valid.replace("sourceDir =", '"sourceDir" =')),
                            ("leading blanks", valid.replace(exact, "  " + exact)),
                            ("a literal string", valid.replace(exact, exact.replace('"', "'"))),
                            ("an escaped value", valid.replace(exact, exact.replace("/", "\\\\"))),
                            ("a backslash value", valid.replace(exact, exact.replace("/", "\\"))),
                            ("a trailing comment", valid.replace(exact, exact[:-1] + " # here\n")),
                            ("a multi-line string", valid.replace(exact, 'note = """\n' + exact + '"""\n')),
                            ("CRLF", valid.replace("\n", "\r\n")),
                            ("a byte-order mark", "\ufeff" + valid),
                            ("a drive-relative source", valid.replace(exact, 'sourceDir = "C:dotfiles"\n')),
                            ("a rooted source", valid.replace(exact, 'sourceDir = "/dotfiles"\n')),
                            ("a UNC source", valid.replace(exact, 'sourceDir = "//server/share"\n'))):
            with self.subTest(config=name):
                self.config.write_bytes(value.encode())
                result = self.paths()
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(self.config.read_bytes(), value.encode())
        for name, value in (("chezmoi layout", valid),
                            ("keys after the first table",
                             valid + 'sourceDir = "C:/elsewhere"\nworkingTree = "C:/elsewhere"\n')):
            with self.subTest(config=name):
                self.config.write_bytes(value.encode())
                result = self.paths()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(Path(json.loads(result.stdout)["Source"]), self.repo)

    def test_maintenance_persists_in_fresh_process(self):
        self.maintenance.mkdir()
        for _ in range(2):
            result = self.guard("if(-not(Test-DotfilesMaintenance -HomePath " + ps_string(self.home) +
                                ")){throw 'maintenance absent'}")
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_config_rejects_copied_home_and_noncanonical_source(self):
        self.git("init", "--template=")
        (self.repo / ".chezmoiroot").write_text("home\n")
        self.configure("[data]\n  host = \"win\"\n")
        result = self.paths()
        self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(Path(value["Destination"]), self.home)
        self.assertEqual(Path(value["Source"]), self.repo)
        self.assertEqual(Path(value["Config"]), self.config)
        # Windows paths compare ignoring case and slash direction.
        lower = str(self.home.resolve())
        result = self.paths(lower[0].lower() + lower[1:])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Path(json.loads(result.stdout)["Source"]), self.repo)
        drive = self.chezmoi_path(self.home)[0]
        self.config.write_bytes(self.config.read_bytes().replace(('destDir = "' + drive).encode(),
                                                                 ('destDir = "' + drive.lower()).encode()))
        self.assertEqual(self.paths().returncode, 0)
        linked = self.f.root / "linked source"
        self.junction(linked, self.repo)
        no_git = self.f.root / "no git"
        no_git.mkdir()
        (no_git / ".chezmoiroot").write_text("home\n")
        for name, kwargs in (("copied home", {"home": self.f.root}), ("junction source", {"source": linked}),
                             ("no .git", {"source": no_git})):
            with self.subTest(config=name):
                self.configure("[data]\n  host = \"win\"\n", **kwargs)
                if name == "junction source":
                    # resolve() would follow the junction: name it as written.
                    self.config.write_bytes(self.config.read_bytes().replace(
                        self.chezmoi_path(self.repo).encode(), (self.chezmoi_path(self.f.root) + "/linked source").encode()))
                self.assertNotEqual(self.paths().returncode, 0)

    def test_update_excludes_directories_and_applies_files_in_existing_parent(self):
        self.setup_home()
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
        trace = self.f.root / "update arguments.json"
        before = "$script:updateProcess=(Get-Item Function:Invoke-DotfilesUpdateProcess).ScriptBlock;" + \
            "function Invoke-DotfilesUpdateProcess {param($Program,$Arguments,$Paths);" + \
            "if($Arguments -contains 'update'){ConvertTo-Json -InputObject @($Arguments) -Compress | " + \
            "Set-Content -LiteralPath " + ps_string(trace) + "};" + \
            "& $script:updateProcess $Program $Arguments $Paths};"
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
        self.setup_home()
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
        self.setup_home()
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

    def test_dirty_tracked_and_untracked_source_prevents_write(self):
        self.setup_home()
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

    def test_unsafe_update_configuration_refuses(self):
        self.setup_home()
        # The fixture's safe config except for its args, so only the args check
        # can refuse it, and a change the source holds that a refused update
        # must not apply.
        self.configure("[git]\nautoAdd=false\nautoCommit=false\nautoPush=false\n"
                       "[update]\ncommand='git'\nargs=['pull','--rebase','--autostash']\n"
                       "recurseSubmodules=false\n")
        self.publish_sample("must not apply\n")
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("[dotfiles]", result.stdout + result.stderr)
        self.assertEqual((self.home / ".sample").read_text(), "initial\n")

    def test_local_update_apply_false_does_not_skip_update(self):
        # Both twins pass update --apply, so the local update.apply value is
        # not part of the contract, as in scripts/chezmoi-update.sh.
        self.setup_home()
        self.config.write_bytes(self.config.read_bytes() + b"apply=false\n")
        self.publish_sample("applied despite update.apply=false\n")
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("[dotfiles]", result.stdout + result.stderr)
        self.assertEqual((self.home / ".sample").read_text(), "applied despite update.apply=false\n")

    def test_optout_maintenance_and_session_guard_skip_update(self):
        self.setup_home()
        # The source holds a change, so a missing guard would apply it.
        self.publish_sample("must not apply\n")
        for before in ("$env:DOTFILES_AUTO_UPDATE='0';", "$env:_DOTFILES_CHECKED='1';"):
            result = self.update(before)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("[dotfiles]", result.stdout + result.stderr)
            self.assertEqual((self.home / ".sample").read_text(), "initial\n")
        self.maintenance.touch()
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / ".sample").read_text(), "initial\n")

    def test_missing_backend_and_conflict_are_nonsecret_warnings(self):
        self.setup_home()
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

    def test_lost_state_refuses_to_replace_a_new_foreign_link(self):
        self.setup_home()
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
        self.setup_home()
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

    def test_config_directory_or_dangling_link_is_refused(self):
        for kind in ("directory", "link"):
            if kind == "directory":
                self.config.mkdir()
            else:
                self.config.symlink_to(self.f.root / "absent")
            result = self.guard("if(-not(Test-DotfilesConfigExists " + ps_string(self.home) +
                                ")){throw 'config absent'}")
            self.assertEqual(result.returncode, 0, result.stderr)
            result = self.guard("Get-DotfilesChezmoiPaths " + ps_string(self.home))
            self.assertNotEqual(result.returncode, 0)
            if kind == "directory":
                self.config.rmdir()
            else:
                self.config.unlink()
        result = self.guard("if(Test-DotfilesConfigExists " + ps_string(self.home) + "){throw 'config present'}")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_profile_dispatch_uses_config_and_maintenance_in_fresh_shells(self):
        profile = ROOT / "home/Documents/PowerShell/profile.ps1"
        # A checkout at ~/dotfiles, with every hook and a real guard: a home
        # without a chezmoi config must still run none of them.
        fake_repo = self.home / "dotfiles"
        (fake_repo / "scripts").mkdir(parents=True)
        (fake_repo / "lib").mkdir()
        shutil.copyfile(ROOT / "lib/chezmoi-guard.ps1", fake_repo / "lib/chezmoi-guard.ps1")
        trace = self.f.root / "dispatch"
        for name in ("chezmoi-update", "payload-update"):
            (fake_repo / ("scripts/" + name + ".ps1")).write_text(
                "Add-Content -LiteralPath " + ps_string(trace) + " -Value '" + name + "'\n")
        body = ("$IsInteractive=$true;" +
                "$ast=[Management.Automation.Language.Parser]::ParseFile(" + ps_string(profile) +
                ",[ref]$null,[ref]$null);$tail=@($ast.EndBlock.Statements | Where-Object " +
                "{ $_ -is [Management.Automation.Language.IfStatementAst] -and " +
                "$_.Extent.Text.StartsWith('if ($IsInteractive)') });" +
                "if($tail.Count -ne 1){throw 'profile tail not found'};Invoke-Expression $tail[0].Extent.Text")
        result = self.ps(body)
        self.assertEqual(result.returncode, 0, result.stderr)
        # A home without a chezmoi config runs nothing and prints nothing.
        self.assertFalse(trace.exists(), trace.read_text() if trace.exists() else "")
        self.assertEqual(result.stdout.strip(), "")
        self.assertEqual(result.stderr.strip(), "")
        # The configured source may live outside ~/dotfiles.
        independent_source = self.f.root / "independent source"
        (independent_source / "scripts").mkdir(parents=True)
        (independent_source / "lib").mkdir()
        self.make_checkout(independent_source)
        shutil.copyfile(ROOT / "lib/chezmoi-guard.ps1", independent_source / "lib/chezmoi-guard.ps1")
        for name in ("chezmoi-update", "payload-update"):
            (independent_source / ("scripts/" + name + ".ps1")).write_text(
                "Add-Content -LiteralPath " + ps_string(trace) + " -Value 'source-" + name + "'\n")
        # The guard in a checkout the config does not name is never sourced.
        (fake_repo / "lib/chezmoi-guard.ps1").write_text(
            "Add-Content -LiteralPath " + ps_string(trace) + " -Value 'other-guard';throw 'other guard loaded'\n")
        self.configure("[data]\n  host = \"win\"\n", source=independent_source)
        result = self.ps(body)
        self.assertEqual(result.returncode, 0, result.stderr)
        # A login updates; payloads install only through sync-payloads.
        self.assertEqual(trace.read_text().splitlines(), ["source-chezmoi-update"])
        trace.unlink()
        # A failing updater leaves the shell usable and the caller's preferences intact.
        updater = independent_source / "scripts/chezmoi-update.ps1"
        saved = updater.read_bytes()
        updater.write_text("throw 'updater failed'\n")
        result = self.ps(body + ";if($ErrorActionPreference -ne 'Stop'){throw 'caller preference changed'};'profile continued'")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("profile continued", result.stdout)
        self.assertIn("[dotfiles] [warn] Profile hooks skipped", result.stderr)
        updater.write_bytes(saved)
        # A config the guard refuses never falls back to another checkout.
        for malformed in (self.top(source=independent_source).split("\n", 1)[0] + "\n[data]\n",
                          self.top(home=self.f.root, source=independent_source)):
            self.config.write_bytes(malformed.encode())
            result = self.ps(body)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((result.stdout + result.stderr).count("[dotfiles]"), 1, result.stderr)
            self.assertFalse(trace.exists())
            # The opt-out silences that warning too.
            result = self.ps("$env:DOTFILES_AUTO_UPDATE='0';" + body)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("[dotfiles]", result.stdout + result.stderr)
            self.assertFalse(trace.exists())
        self.config.unlink()
        for config_kind in ("directory", "dangling-link"):
            if config_kind == "directory":
                self.config.mkdir()
            else:
                self.config.symlink_to(self.f.root / "missing-config-referent")
            result = self.ps(body)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("[dotfiles]", result.stdout + result.stderr)
            self.assertFalse(trace.exists())
            if config_kind == "directory":
                self.config.rmdir()
            else:
                self.config.unlink()
        self.configure("[data]\n  host = \"win\"\n", source=independent_source)
        self.maintenance.touch()
        for _ in range(2):
            result = self.ps(body)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(trace.exists())

    def test_windows_powershell_can_load_guard_without_version_upgrade(self):
        shell = Path(os.environ["SYSTEMROOT"]) / "System32/WindowsPowerShell/v1.0/powershell.exe"
        if not shell.is_file():
            self.skipTest("Windows PowerShell 5.1 not available")
        # The config real chezmoi init writes here, in the source it names.
        with SourceFixture("win") as fixture:
            result = fixture.run("init")
            self.assertEqual(result.returncode, 0, result.stderr)
            rendered = fixture.config.read_bytes()
            # init made the source a Git repository, as the guard requires.
            self.assertTrue((fixture.source / ".git").is_dir())
            target = fixture.destination / ".config/chezmoi/chezmoi.toml"
            target.parent.mkdir(parents=True)
            target.write_bytes(rendered)
            self.assertIn(b'\nsourceDir = "' + self.chezmoi_path(fixture.source).encode() + b'"\n', rendered)
            self.assertNotIn(b"\r", rendered)
            guard = "$ErrorActionPreference='Stop';. " + ps_string(ROOT / "lib/chezmoi-guard.ps1") + ";"
            # The updater's binary check lives in the guard too and must parse there.
            body = (guard + "$p=Get-DotfilesChezmoiPaths -HomePath " + ps_string(fixture.destination) +
                    ";if($p.Source -ne " + ps_string(fixture.source) + "){throw ('source '+$p.Source)}" +
                    ";if(-not(Test-DotfilesConfigExists " + ps_string(fixture.destination) + ")){throw 'config absent'}" +
                    ";foreach($f in 'Test-DotfilesChezmoiPath','Test-DotfilesTrustedFileSecurity','Open-DotfilesChezmoi')" +
                    "{if(-not(Get-Command $f -CommandType Function -ErrorAction SilentlyContinue)){throw ($f+' missing')}}" +
                    ";[IO.File]::WriteAllText(" + ps_string(target) + ",[IO.File]::ReadAllText(" + ps_string(target) +
                    ").Replace(\"`n\",\"`r`n\"))" +
                    ";try{Get-DotfilesChezmoiPaths -HomePath " + ps_string(fixture.destination) +
                    " | Out-Null;throw 'CRLF accepted'}catch{if($_ -match 'CRLF accepted'){throw}}" +
                    ";[IO.File]::WriteAllBytes(" + ps_string(target) + ",[Convert]::FromBase64String('" +
                    base64.b64encode(rendered).decode() + "'));exit 0")
            for executable in (str(shell), self.pwsh):
                with self.subTest(shell=executable):
                    encoded = base64.b64encode(body.encode("utf-16le")).decode()
                    # Match the PS7 fixture budget, including hosted e2e process startup.
                    result = subprocess.run([executable, "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
                                            cwd=fixture.root, env=self.env, stdin=subprocess.DEVNULL,
                                            capture_output=True, text=True, timeout=60)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(target.read_bytes(), rendered)

    def test_config_rejects_repository_subdirectory_as_source(self):
        self.setup_home()
        tables = self.config.read_bytes().decode().split("\n", 2)[2]
        self.configure(tables, source=self.repo / "home")
        result = self.guard("Get-DotfilesChezmoiPaths " + ps_string(self.home))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.home / ".sample").read_text(), "initial\n")

    def test_unattended_git_disables_local_hooks_and_fsmonitor(self):
        self.setup_home()
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
                        ";$paths=Get-DotfilesChezmoiPaths " + ps_string(self.home) +
                        ";$r=Invoke-DotfilesUpdateProcess " + ps_string(self.git_exe) +
                        " @('config','--get-regexp','^(core.hooksPath|core.fsmonitor|maintenance.auto|gc.auto)$') $paths;" +
                        "$r.Output")
        self.assertEqual(probe.returncode, 0, probe.stderr)
        lines = probe.stdout.lower().splitlines()
        self.assertIn("maintenance.auto false", lines)
        self.assertIn("gc.auto 0", lines)
        self.assertIn("core.fsmonitor false", lines)

    def test_config_rejects_non_dotfiles_repository_root(self):
        self.setup_home()
        (self.repo / ".chezmoiroot").unlink()
        result = self.guard("Get-DotfilesChezmoiPaths " + ps_string(self.home))
        self.assertNotEqual(result.returncode, 0)

    def test_local_chezmoi_defaults_cannot_force_conflict_or_switch_git_tree(self):
        self.setup_home()
        alternative = self.f.root / "other repository"
        self.git("clone", str(self.remote), str(alternative))
        text = self.config.read_bytes()
        (self.home / ".sample").write_text("private edited destination\n")
        (self.repo / "home/dot_sample").write_text("new portable\n")
        self.git("add", ".")
        self.git("commit", "-qm", "portable edit")
        self.git("push", "origin", "main")
        previous = self.git("rev-parse", "HEAD", cwd=alternative)
        # A local workingTree key would redirect a later init's sourceDir: refused.
        self.config.write_bytes(b"workingTree = " + json.dumps(str(alternative)).encode() + b"\n" + text)
        head = self.git("rev-parse", "HEAD")
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((result.stdout + result.stderr).count("[dotfiles]"), 1, result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), head)
        self.assertEqual(self.git("rev-parse", "HEAD", cwd=alternative), previous)
        # Local force and useBuiltinGit defaults lose to the explicit flags.
        self.config.write_bytes(b"force = true\nuseBuiltinGit = true\n" + text)
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / ".sample").read_text(), "private edited destination\n")
        (self.home / ".sample").write_text("initial\n")
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / ".sample").read_text(), "new portable\n")
        self.assertEqual(self.git("rev-parse", "HEAD", cwd=alternative), previous)

    def test_git_worktree_redirect_cannot_escape_the_configured_source(self):
        self.setup_home()
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

    def test_backend_uses_provisioned_binary_when_path_omits_it(self):
        self.setup_home()
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
        self.setup_home()
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
        self.setup_home()
        (self.home / ".local/bin/chezmoi.exe").unlink()
        self.publish_sample("path fallback must not apply\n")
        self.assert_backend_refused(self.update())

    def test_foreign_owner_or_writer_refuses_the_provisioned_binary(self):
        self.setup_home()
        installed = self.home / ".local/bin/chezmoi.exe"
        self.publish_sample("untrusted backend must not run\n")
        # BUILTIN\Users stands for any other account, such as an app sandbox group.
        for change in (("/grant", "*S-1-5-32-545:(M)"), ("/setowner", "*S-1-5-32-545")):
            installed.unlink()
            self.install_backend()
            self.icacls(installed, *change)
            self.assert_backend_refused(self.update())

    def test_linked_binary_or_parent_directory_is_refused(self):
        self.setup_home()
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
        self.setup_home()
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
                            ";if(-not(Test-DotfilesChezmoiPath $p)){throw 'path refused'}" +
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
        self.setup_home()
        local = self.home / ".local"
        moves = [(local / "bin", self.f.root / "bin moved"), (local, self.f.root / "local moved")]
        attempts = ";".join("try{[IO.Directory]::Move(" + ps_string(source) + "," + ps_string(target) +
                            ");'moved'}catch{'refused'}" for source, target in moves)
        release = ("[IO.Directory]::Move(" + ps_string(moves[0][0]) + "," + ps_string(moves[0][1]) + ");" +
                   "[IO.Directory]::Move(" + ps_string(moves[0][1]) + "," + ps_string(moves[0][0]) + ");'released'")
        result = self.ps(". " + ps_string(ROOT / "scripts/chezmoi-update.ps1") +
                         ";$held=Open-DotfilesChezmoi -Destination " + ps_string(self.home) +
                         ";if(-not $held){throw 'provisioned binary refused'};try{" + attempts +
                         "}finally{$held.Dispose()};" + release)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.split(), ["refused", "refused", "released"])

    def publish_new_target(self, upstream=True):
        source = self.repo
        if upstream:
            source = self.f.root / "new target sender"
            self.git("clone", str(self.remote), str(source))
        (source / "home/dot_sample_new").write_text("new portable target\n")
        self.git("add", ".", cwd=source)
        self.git("commit", "-qm", "new managed target", cwd=source)
        self.git("push", "origin", "main", cwd=source)

    def test_new_upstream_existing_regular_target_is_preserved(self):
        self.setup_home()
        target = self.home / ".sample_new"
        target.write_text("private preexisting target\n")
        self.publish_new_target()
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("[dotfiles]", result.stdout + result.stderr)
        self.assertNotIn("private preexisting", result.stdout + result.stderr)
        self.assertEqual(target.read_text(), "private preexisting target\n")
        self.assertTrue((self.repo / "home/dot_sample_new").exists())

    def test_new_upstream_equal_content_foreign_link_is_preserved(self):
        self.setup_home()
        target = self.home / ".sample_new"
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
        self.setup_home()
        target = self.home / ".sample_new"
        target.write_text("unapproved local target\n")
        self.publish_new_target(upstream=False)
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("[dotfiles]", result.stdout + result.stderr)
        self.assertEqual(target.read_text(), "unapproved local target\n")

    def test_new_absent_upstream_target_is_applied(self):
        self.setup_home()
        self.publish_new_target()
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / ".sample_new").read_text(), "new portable target\n")
        self.assertNotIn("[dotfiles]", result.stdout + result.stderr)

    def test_refusal_warning_follows_the_color_rules(self):
        # Warnings go to stderr through lib/terminal.ps1: colored on request,
        # plain when color is off (and when auto finds stderr redirected).
        self.setup_home()
        self.f.state.write_bytes(b"")
        warning = "[dotfiles] [warn] Update skipped: the chezmoi state is missing or empty"
        colored = self.update("$env:DOTFILES_COLOR='always';$env:TERM='xterm-256color';"
                              "Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue;")
        self.assertEqual(colored.returncode, 0, colored.stderr)
        self.assertIn("\x1b[33m" + warning, colored.stderr)
        for before in ("$env:DOTFILES_COLOR='never';", "$env:DOTFILES_COLOR='auto';"):
            plain = self.update(before)
            self.assertEqual(plain.returncode, 0, plain.stderr)
            self.assertIn(warning, plain.stderr)
            self.assertNotIn("\x1b[", plain.stderr)

    def test_empty_state_preserves_existing_edit(self):
        self.setup_home()
        self.f.state.write_bytes(b"")
        (self.home / ".sample").write_text("private new local edit\n")
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("[dotfiles]", result.stdout + result.stderr)
        self.assertEqual((self.home / ".sample").read_text(), "private new local edit\n")
        self.assertEqual(self.f.state.read_bytes(), b"")
