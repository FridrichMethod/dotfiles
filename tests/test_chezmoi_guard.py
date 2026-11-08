"""Home guards: the source the chezmoi config names, maintenance and login dispatch."""

import base64
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GUARD = ROOT / "lib/chezmoi-guard.sh"
# Absolute paths: the children run with PATH=os.defpath, which may lack a
# shell found here (an HPC login env provides zsh).
SHELLS = {name: path for name in ("sh", "bash", "zsh") if (path := shutil.which(name))}


def config_text(home, source, top="", tables=""):
    # The layout chezmoi init writes (BurntSushi toml): the top-level keys
    # sorted, one 'KEY = "VALUE"' each, then the tables.
    return (f'destDir = "{home}"\nencryption = "age"\nmode = "file"\n'
            f'persistentState = "{home}/.local/state/chezmoi/chezmoi.boltdb"\n'
            f'sourceDir = "{source}"\numask = 63\n{top}\n'
            '[age]\n  identity = "/nonexistent/key.txt"\n\n[data]\n  host = "lab-ubuntu"\n\n'
            '[git]\n  autoAdd = false\n\n[update]\n  command = "git"\n  recurseSubmodules = false\n'
            + tables)


@unittest.skipIf(os.name == "nt", "POSIX shell execution")
class ChezmoiSourceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        # macOS TMPDIR may use /var rather than canonical /private/var.
        self.root = Path(temporary.name).resolve()
        self.home, self.source = self.root / "a home", self.root / "a source"
        self.config = self.home / ".config/chezmoi/chezmoi.toml"
        self.config.parent.mkdir(parents=True)
        (self.source / "home").mkdir(parents=True)
        (self.source / ".chezmoiroot").write_text("home\n")

    def lookup(self, shell="sh", home=None):
        return subprocess.run([SHELLS.get(shell, shell), "-c", '. "$1"; dotfiles_chezmoi_source "$2"', "guard",
                               str(GUARD), str(home or self.home)], capture_output=True, timeout=15,
                              env={"PATH": os.defpath, "HOME": str(self.home)})

    def place(self, data):
        if self.config.is_symlink() or self.config.is_file():
            self.config.unlink()
        elif self.config.is_dir():
            self.config.rmdir()
        if data is not None:
            self.config.write_bytes(data.encode() if isinstance(data, str) else data)

    def test_prints_the_canonical_source_of_the_layout_chezmoi_writes(self):
        valid = config_text(self.home, self.source)
        accepted = {
            "chezmoi layout": valid,
            "no final newline": valid.rstrip("\n"),
            "keys after the first table": valid + 'sourceDir = "/elsewhere"\nworkingTree = "/elsewhere"\n',
            "indented header": valid.replace("\n[age]\n", '\n\t [age]\nsourceDir = "/elsewhere"\n', 1),
            "comment lines": "# sourceDir = \"/elsewhere\"\n" + valid,
        }
        for shell in ("sh", "bash", *(["zsh"] if "zsh" in SHELLS else [])):
            for name, data in accepted.items():
                with self.subTest(shell=shell, config=name):
                    self.place(data)
                    before = sorted(self.root.rglob("*"))
                    result = self.lookup(shell)
                    self.assertEqual((result.returncode, result.stdout, result.stderr),
                                     (0, f"{self.source}\n".encode(), b""))
                    self.assertEqual(sorted(self.root.rglob("*")), before)

    def test_refuses_every_other_form_silently(self):
        valid = config_text(self.home, self.source)
        exact = f'sourceDir = "{self.source}"\n'
        linked_source, linked_home = self.root / "linked source", self.root / "linked home"
        linked_source.symlink_to(self.source)
        linked_home.symlink_to(self.home)
        (self.root / "another home").mkdir()
        (self.root / "plain").mkdir()
        refused = {
            "no sourceDir": valid.replace(exact, ""),
            "no destDir": valid.replace(f'destDir = "{self.home}"\n', ""),
            "two sourceDir lines": valid.replace(exact, exact * 2),
            "two destDir lines": f'destDir = "{self.home}"\n' + valid,
            "sourceDir only in a table": valid.replace(exact, "").replace("[data]\n", "[data]\n" + exact),
            "a case variant beside the key": valid.replace(exact, exact + f'SourceDir = "{self.source}"\n'),
            "a case variant instead": valid.replace("sourceDir =", "sourcedir ="),
            "an upper-case destDir": valid.replace("destDir =", "DESTDIR ="),
            "a workingTree key": valid.replace(exact, exact + f'workingTree = "{self.source}"\n'),
            "a workingtree case variant": valid.replace(exact, exact + f'WORKINGTREE = "{self.source}"\n'),
            "a quoted key": valid.replace("sourceDir =", '"sourceDir" ='),
            "a quoted key beside": valid.replace(exact, exact + "'umask2' = 1\n"),
            "leading blanks": valid.replace(exact, "  " + exact),
            "no spaces around =": valid.replace("sourceDir = ", "sourceDir="),
            "two spaces before =": valid.replace("sourceDir = ", "sourceDir  = "),
            "a literal string": valid.replace(exact, f"sourceDir = '{self.source}'\n"),
            "a backslash escape": valid.replace(exact, f'sourceDir = "{self.source}\\u0000"\n'),
            "a quote in the value": valid.replace(exact, f'sourceDir = "{self.source}" # "\n'),
            "a control character": valid.replace(exact, f'sourceDir = "{self.source}\t"\n'),
            "a trailing comment": valid.replace(exact, f'sourceDir = "{self.source}" # here\n'),
            "CRLF": valid.replace("\n", "\r\n"),
            "a multi-line basic string": valid.replace(exact, 'note = """\n' + exact + '"""\n'),
            "a multi-line literal string": valid.replace(exact, "note = '''\n" + exact + "'''\n"),
            "an empty value": valid.replace(exact, 'sourceDir = ""\n'),
            "a relative source": valid.replace(exact, 'sourceDir = "a source"\n'),
            "a linked source": valid.replace(exact, f'sourceDir = "{linked_source}"\n'),
            "a trailing slash": valid.replace(exact, f'sourceDir = "{self.source}/"\n'),
            "a dot segment": valid.replace(exact, f'sourceDir = "{self.root}/./a source"\n'),
            "no .chezmoiroot": valid.replace(exact, f'sourceDir = "{self.root / "plain"}"\n'),
            "the home subdirectory": valid.replace(exact, f'sourceDir = "{self.source / "home"}"\n'),
            "destDir another home": valid.replace(f'destDir = "{self.home}"', f'destDir = "{self.root / "another home"}"'),
            "destDir a linked path": valid.replace(f'destDir = "{self.home}"', f'destDir = "{linked_home}"'),
            "a byte-order mark": "\ufeff" + valid,
        }
        for shell in ("sh", "bash", *(["zsh"] if "zsh" in SHELLS else [])):
            for name, data in refused.items():
                with self.subTest(shell=shell, config=name):
                    self.place(data)
                    result = self.lookup(shell)
                    self.assertEqual((result.returncode, result.stdout, result.stderr), (1, b"", b""))
        self.place(None)
        for kind in ("absent", "directory", "link", "dangling link"):
            with self.subTest(config=kind):
                if kind == "directory":
                    self.config.mkdir()
                elif kind != "absent":
                    target = self.root / ("saved config" if kind == "link" else "missing config")
                    if kind == "link":
                        target.write_text(valid)
                    self.config.symlink_to(target)
                result = self.lookup()
                self.assertEqual((result.returncode, result.stdout, result.stderr), (1, b"", b""))
                self.place(None)

    def test_root_ancestor_does_not_become_a_windows_unc_path(self):
        # Git Bash treats //.config as UNC, not the local POSIX root.
        # Record the actual shell predicates without querying a network path.
        command = '[() { printf "%s\\n" "$2"; return 1; }; . "$1"; '
        command += 'dotfiles_config_exists /; dotfiles_maintenance_active /; dotfiles_chezmoi_source /'
        result = subprocess.run(["bash", "--noprofile", "--norc", "-c", command, "guard", str(GUARD)],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.stdout.splitlines(), ["/.config/chezmoi/chezmoi.toml"] * 2 +
                         ["/.config/dotfiles/maintenance"] * 2 + ["/.config/chezmoi/chezmoi.toml"])

    def test_sourcing_defines_three_functions_and_writes_nothing(self):
        def shell(code):
            return subprocess.run(["bash", "--noprofile", "--norc", "-c", code, "guard", str(GUARD)],
                                  cwd=self.root, capture_output=True, text=True, timeout=15,
                                  env={"PATH": os.defpath, "HOME": str(self.home)})

        before = shell("compgen -v")
        after = shell('. "$1"; compgen -v; declare -F | sed "s/^declare -f /function /"')
        self.assertEqual((before.stderr, after.stderr), ("", ""))
        # PIPESTATUS appears once a pipeline has run.
        self.assertEqual(sorted(set(after.stdout.splitlines()) - set(before.stdout.splitlines()) - {"PIPESTATUS"}),
                         ["function dotfiles_chezmoi_source", "function dotfiles_config_exists",
                          "function dotfiles_maintenance_active"])
        self.assertEqual(sorted(self.root.rglob("*")), sorted([self.home, self.home / ".config",
                                                               self.config.parent, self.source,
                                                               self.source / "home",
                                                               self.source / ".chezmoiroot"]))


@unittest.skipIf(os.name == "nt", "POSIX shell execution")
class WriterGuardTests(unittest.TestCase):
    def test_logins_start_no_payload_run_and_update_only_a_configured_home(self):
        # No profile path runs a payload hook, with or without Sherlock's
        # overlay, whose site rule forbids detached login-node workers. A
        # configured home runs only its source's updater; an invalid config
        # warns once and runs nothing; a home without a config runs nothing,
        # not even the hooks of a checkout at ~/dotfiles, and prints nothing.
        # zsh (the .zshrc tail) is in tests/shell-profile.sh and the login
        # updater suite.
        with tempfile.TemporaryDirectory() as temporary:
            # macOS TMPDIR may use /var rather than canonical /private/var.
            root = Path(temporary).resolve()
            home, source = root / "home", root / "source"
            default = home / "dotfiles"
            trace = root / "trace"
            for path in (home / ".config/chezmoi", home / ".config/sh", source / "scripts",
                         source / "lib", default / "scripts"):
                path.mkdir(parents=True)
            (source / ".chezmoiroot").write_text("home\n")
            shutil.copyfile(GUARD, source / "lib/chezmoi-guard.sh")
            for checkout, name in ((source, "source"), (default, "default")):
                for hook in ("chezmoi-update", "payload-update"):
                    (checkout / f"scripts/{hook}.sh").write_text(f'printf "%s\\n" "{name} {hook}" >>"$TRACE"\n')
            config, overlay = home / ".config/chezmoi/chezmoi.toml", home / ".config/sh/.profile"
            env = {"HOME": str(home), "PATH": os.defpath, "TERM": "dumb", "SCRATCH": "",
                   "TRACE": str(trace)}
            for sherlock in (False, True):
                if sherlock:
                    shutil.copyfile(ROOT / "home/.hosts/sherlock/.config/sh/.profile", overlay)
                for state in ("configured", "invalid", "unconfigured"):
                    if state == "unconfigured":
                        config.unlink()
                    else:
                        config.write_text(config_text(home, source if state == "configured" else default))
                    for shell in ("sh", "bash"):
                        with self.subTest(sherlock=sherlock, state=state, shell=shell):
                            trace.unlink(missing_ok=True)
                            flags = ["--noprofile", "--norc"] if shell == "bash" else []
                            result = subprocess.run([SHELLS.get(shell, shell), *flags, "-i", "-c", '. "$1"', "profile",
                                                     str(ROOT / "home/dot_profile")],
                                                    env=env, stdin=subprocess.DEVNULL, capture_output=True,
                                                    text=True, timeout=15)
                            self.assertEqual(result.returncode, 0, result.stderr)
                            warnings = [line for line in result.stderr.splitlines() if "[dotfiles]" in line]
                            if state == "configured":
                                self.assertEqual(trace.read_text().splitlines(), ["source chezmoi-update"])
                                self.assertEqual(warnings, [])
                            else:
                                self.assertFalse(trace.exists(), trace.read_text() if trace.exists() else "")
                                self.assertEqual(warnings, [] if state == "unconfigured" else [
                                    "[dotfiles] [warn] ~/.config/chezmoi/chezmoi.toml does not name this home "
                                    "and a dotfiles checkout; automatic updates skipped."])

    def test_sync_payload_commands_run_only_the_validated_config_source(self):
        # sync-payloads/sync-skills resolve the hook as the login dispatcher
        # does: a valid config's source wins over the checkout at ~/dotfiles,
        # whose guard and hook never run; a home without a config and an
        # invalid config refuse before any hook; maintenance surfaces the
        # configured hook's own refusal before any state.
        refusal = ("[dotfiles] [error] ~/.config/chezmoi/chezmoi.toml does not name this home and a "
                   "dotfiles checkout; payload update refused.\n")
        no_config = ("[dotfiles] [error] Payload update needs ~/.config/chezmoi/chezmoi.toml; without it run "
                     "sh CHECKOUT/scripts/payload-update.sh --now [ITEM...] instead.\n")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            home, source = root / "home", root / "configured source"
            other = home / "dotfiles"
            unguarded = root / "unguarded source"
            trace, state = root / "trace", root / "state"
            for path in (home / ".config/chezmoi", source / "scripts", source / "lib",
                         other / "scripts", other / "lib", unguarded / "scripts"):
                path.mkdir(parents=True)
            for checkout in (source, other, unguarded):
                (checkout / ".chezmoiroot").write_text("home\n")
            shutil.copyfile(GUARD, source / "lib/chezmoi-guard.sh")
            for checkout, name in ((source, "source"), (other, "other"), (unguarded, "unguarded")):
                (checkout / "scripts/payload-update.sh").write_text(
                    f'printf "{name} %s\\n" "$*" >>"$TRACE"\nexit 4\n')
            (other / "lib/chezmoi-guard.sh").write_text('printf "other-guard\\n" >>"$TRACE"\n')
            config = home / ".config/chezmoi/chezmoi.toml"
            valid = config_text(home, source)
            env = {"HOME": str(home), "PATH": os.defpath, "TRACE": str(trace), "XDG_STATE_HOME": str(state)}
            # eval: zsh does not expand an alias defined earlier in one -c string.
            code = ('[ -z "${BASH_VERSION-}" ] || shopt -s expand_aliases; . "$1"; '
                    'eval "sync-payloads kit pymol"; first=$?; eval sync-skills; '
                    'printf "%s %s\\n" "$first" "$?"')

            def run(shell):
                trace.unlink(missing_ok=True)
                result = subprocess.run([SHELLS[shell], *(["-f"] if shell == "zsh" else []), "-c", code,
                                         "aliases", str(ROOT / "home/dot_aliases")],
                                        env=env, stdin=subprocess.DEVNULL, capture_output=True,
                                        text=True, timeout=15)
                return result, trace.read_text().splitlines() if trace.exists() else []

            def configure(content=None, kind="file"):
                if config.is_symlink() or config.is_file():
                    config.unlink()
                elif config.is_dir():
                    config.rmdir()
                if kind == "symlink":
                    (root / "linked config").write_text(valid)
                    config.symlink_to(root / "linked config")
                elif kind == "directory":
                    config.mkdir()
                elif content is not None:
                    config.write_text(content)

            exact = f'sourceDir = "{source}"\n'
            invalid = {"other home": (config_text(root, source), "file"),
                       "relative source": (valid.replace(exact, 'sourceDir = "configured source"\n'), "file"),
                       "two sourceDir lines": (valid.replace(exact, exact * 2), "file"),
                       "CRLF": (valid.replace("\n", "\r\n"), "file"),
                       "a source without its guard": (config_text(home, unguarded), "file"),
                       "symlink": (None, "symlink"), "directory": (None, "directory")}
            for shell in SHELLS:
                with self.subTest(shell=shell, config="absent"):
                    configure()
                    result, events = run(shell)
                    self.assertEqual((result.stdout, result.stderr), ("1 1\n", no_config * 2))
                    self.assertEqual(events, [])
                with self.subTest(shell=shell, config="valid non-default source"):
                    configure(valid)
                    result, events = run(shell)
                    self.assertEqual((result.stdout, result.stderr), ("4 4\n", ""))
                    self.assertEqual(events, ["source --now kit pymol", "source --now skills"])
                for name, (content, kind) in invalid.items():
                    with self.subTest(shell=shell, config=name):
                        configure(content, kind)
                        result, events = run(shell)
                        self.assertEqual(events, [])
                        self.assertEqual((result.stdout, result.stderr), ("1 1\n", refusal * 2))
            configure(valid)
            (home / ".config/dotfiles").mkdir()
            (home / ".config/dotfiles/maintenance").touch()
            shutil.copyfile(ROOT / "scripts/payload-update.sh", source / "scripts/payload-update.sh")
            for shell in SHELLS:
                with self.subTest(shell=shell, config="maintenance"):
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


class PowerShellGuardTextTests(unittest.TestCase):
    # lib/chezmoi-guard.ps1 must parse and run under Windows PowerShell 5.1,
    # which the Windows suite loads for real; this text check runs anywhere.
    def test_guard_uses_no_powershell_7_only_syntax_or_api(self):
        text = (ROOT / "lib/chezmoi-guard.ps1").read_text(encoding="utf-8")
        code = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
        code = re.sub(r"'(?:[^']|'')*'|\"(?:[^\"`]|`.)*\"", "''", code)
        # Null-coalescing, pipeline chains and a .NET Core-only path API; a
        # ternary would not parse there either, which the 5.1 load proves.
        for token in ("??", " && ", " || ", "IsPathFullyQualified"):
            with self.subTest(token=token):
                self.assertNotIn(token, code)
        # $IsWindows is undefined there, so every use is guarded first.
        uses = [code[max(0, match.start() - 40):match.end()] for match in re.finditer(r"\$IsWindows\b", code)]
        self.assertTrue(uses)
        for use in uses:
            self.assertTrue(use.endswith("(Test-Path Variable:IsWindows) -and $IsWindows"), use)


def ps_string(value):
    return "'" + str(value).replace("'", "''") + "'"


@unittest.skipUnless(shutil.which("pwsh"), "PowerShell 7 unavailable")
class PowerShellGuardCultureTests(unittest.TestCase):
    # Get-DotfilesChezmoiPaths refuses every other spelling of sourceDir,
    # destDir and workingTree in any culture, as dotfiles_chezmoi_source's
    # spelled-out classes do: under tr-TR and az-Latn-AZ a match that follows
    # the current culture does not fold an ASCII I to i. On Windows, Windows
    # PowerShell 5.1 runs it too.
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        # macOS TMPDIR may use /var rather than canonical /private/var.
        self.root = Path(temporary.name).resolve()
        self.source = self.root / "source"
        (self.source / ".git").mkdir(parents=True)
        (self.source / ".chezmoiroot").write_text("home\n")
        self.shells = [shutil.which("pwsh")]
        desktop = Path(os.environ.get("SYSTEMROOT", "/nonexistent")) / "System32/WindowsPowerShell/v1.0/powershell.exe"
        if os.name == "nt" and desktop.is_file():
            self.shells.append(str(desktop))
        # Windows PowerShell cannot load modules from the pwsh 7 module path
        # this process inherits under tests/chezmoi.ps1, so the child gets no
        # PSModulePath and each shell builds its own.
        self.env = {key: value for key, value in os.environ.items() if key.upper() != "PSMODULEPATH"}
        self.env.update(HOME=str(self.root), POWERSHELL_TELEMETRY_OPTOUT="1",
                        POWERSHELL_UPDATECHECK="Off", XDG_CACHE_HOME=str(self.root / "cache"),
                        XDG_CONFIG_HOME=str(self.root / "config"), XDG_DATA_HOME=str(self.root / "data"))

    @staticmethod
    def form(path):
        # What chezmoi init writes: on Windows forward slashes and an
        # upper-case drive.
        text = path.as_posix()
        return text[0].upper() + text[1:] if os.name == "nt" else text

    def home_with(self, index, line):
        # A home whose config is the init layout plus LINE (@HOME@ is the
        # home's own form) before the tables.
        home = self.root / f"home {index}"
        (home / ".config/chezmoi").mkdir(parents=True)
        (home / ".config/chezmoi/chezmoi.toml").write_bytes(
            (f'destDir = "{self.form(home)}"\nsourceDir = "{self.form(self.source)}"\n' +
             line.replace("@HOME@", self.form(home)) + '\n[data]\n  host = "win"\n').encode())
        return home

    def verdicts(self, shell, culture, homes):
        # The culture's name, whether a current-culture -imatch folds I to i,
        # then 'accepted' or 'refused: MESSAGE' for each home, from one child
        # that sets the culture before it loads the guard.
        script = ("$ErrorActionPreference='Stop'\n"
                  f"try {{ $culture = [Globalization.CultureInfo]::GetCultureInfo('{culture}') }}\n"
                  "catch { 'no-culture'; exit 0 }\n"
                  "[Threading.Thread]::CurrentThread.CurrentCulture = $culture\n"
                  "[Threading.Thread]::CurrentThread.CurrentUICulture = $culture\n"
                  f". {ps_string(ROOT / 'lib/chezmoi-guard.ps1')}\n"
                  "[Threading.Thread]::CurrentThread.CurrentCulture.Name\n"
                  "[string]('I' -imatch '\\Ai\\z')\n"
                  "foreach ($homePath in @(" + ", ".join(ps_string(home) for home in homes) + ")) {\n"
                  "    try { [void](Get-DotfilesChezmoiPaths -HomePath $homePath); 'accepted' }\n"
                  "    catch { 'refused: ' + $_.Exception.Message }\n"
                  "}\nexit 0\n")
        result = subprocess.run([shell, "-NoProfile", "-NonInteractive", "-EncodedCommand",
                                 base64.b64encode(script.encode("utf-16le")).decode()],
                                cwd=self.root, env=self.env, stdin=subprocess.DEVNULL, capture_output=True,
                                text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.splitlines()

    def test_other_key_spellings_are_refused_in_every_culture(self):
        source = self.form(self.source)
        lines = {"the init layout": "", "SOURCEDIR": f'SOURCEDIR = "{source}"\n',
                 "sourceDIR": f'sourceDIR = "{source}"\n', "DESTDIR": 'DESTDIR = "@HOME@"\n',
                 "WORKINGTREE": f'WORKINGTREE = "{source}"\n'}
        homes = {name: self.home_with(index, line) for index, (name, line) in enumerate(lines.items())}
        for shell in self.shells:
            for culture in ("en-US", "tr-TR", "az-Latn-AZ"):
                with self.subTest(shell=shell, culture=culture):
                    output = self.verdicts(shell, culture, homes.values())
                    if output[:1] == ["no-culture"]:
                        self.skipTest(f"{culture} is not available here")
                    # The culture took hold, and a current-culture match
                    # really folds differently there.
                    self.assertEqual(output[:2], [culture, "True" if culture == "en-US" else "False"])
                    self.assertEqual(len(output), 2 + len(homes), output)
                    verdicts = dict(zip(homes, output[2:]))
                    self.assertEqual(verdicts.pop("the init layout"), "accepted")
                    for name, verdict in verdicts.items():
                        self.assertTrue(verdict.startswith("refused: "), f"{name}: {verdict}")


if __name__ == "__main__":
    unittest.main()
