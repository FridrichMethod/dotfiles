"""Exercise portable host configuration in credential-free temporary homes."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PortableShellTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="portable-shell-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / "home with spaces"
        self.home.mkdir()
        self.env = {"HOME": str(self.home), "PATH": "/usr/bin:/bin"}

    def run_shell(self, source, command, shell="bash", extra=None, stderr=""):
        copy = Path(self.temp.name) / "source"
        copy.write_text(source)
        env = dict(self.env, **(extra or {}))
        flags = ["--norc", "--noprofile"] if shell == "bash" else ["-f"]
        result = subprocess.run([shutil.which(shell), *flags, "-c",
                                 ('shopt -s expand_aliases; ' if shell == 'bash' else '') + '. "$1"; ' + command, shell, str(copy)],
                                env=env, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, stderr)
        return result.stdout.strip()

    def test_vi_keeps_native_editor_without_neovim(self):
        bindir = Path(self.temp.name) / "bin"
        bindir.mkdir()
        vi = bindir / "vi"
        vi.write_text("#!/bin/sh\nprintf native\n")
        vi.chmod(0o755)
        source = (ROOT / "home/dot_aliases").read_text()
        self.assertEqual(self.run_shell(source, "eval vi", extra={"PATH": str(bindir)}), "native")
        nvim = bindir / "nvim"
        nvim.write_text("#!/bin/sh\nprintf neovim\n")
        nvim.chmod(0o755)
        self.assertEqual(self.run_shell(source, "eval vi", extra={"PATH": str(bindir)}), "neovim")

    def test_conda_and_mamba_use_current_home(self):
        bindir = self.home / "miniconda3/bin"
        bindir.mkdir(parents=True)
        localbin = self.home / ".local/bin"
        localbin.mkdir(parents=True)
        for target in [bindir / "conda", bindir / "mamba", localbin / "micromamba"]:
            target.write_text("#!/bin/sh\ncase $1 in shell.bash|shell.zsh) echo 'export CONDA_PORTABLE=yes';; shell) echo 'export MAMBA_PORTABLE=yes';; *) exit 1;; esac\n")
            target.chmod(0o755)
        for host in ["mac", "wsl-ubuntu", "sherlock", "marlowe"]:
            for shell in ["bash", "zsh"]:
                if not shutil.which(shell):
                    continue
                with self.subTest(host=host, shell=shell):
                    source = (ROOT / "home/.hosts" / host / f".config/{shell}/.{shell}rc").read_text()
                    source = source.replace("/home/linuxbrew/.linuxbrew", str(Path(self.temp.name) / "absent-brew"))
                    source = source.replace("/usr/share/lmod/lmod/init/zsh", str(Path(self.temp.name) / "absent-lmod"))
                    got = self.run_shell(source, 'printf "%s:%s" "${CONDA_PORTABLE-no}" "${MAMBA_PORTABLE-no}"', shell)
                    self.assertEqual(got, "yes:yes")

    def test_mamba_fallback_quotes_home_with_spaces(self):
        bindir = self.home / "miniconda3/bin"
        bindir.mkdir(parents=True)
        localbin = self.home / ".local/bin"
        localbin.mkdir(parents=True)
        for target in [bindir / "mamba", localbin / "micromamba"]:
            target.write_text("#!/bin/sh\n[ \"$1\" != shell ] || exit 1\nprintf '<%s>' \"$@\"\n")
            target.chmod(0o755)
        for host in ["mac", "wsl-ubuntu", "lab-ubuntu", "sherlock", "marlowe"]:
            for shell in ["bash", "zsh"]:
                if not shutil.which(shell):
                    continue
                with self.subTest(host=host, shell=shell):
                    source = (ROOT / "home/.hosts" / host / f".config/{shell}/.{shell}rc").read_text()
                    source = source.replace("/home/linuxbrew/.linuxbrew", str(Path(self.temp.name) / "absent-brew"))
                    source = source.replace("/apps/miniconda3", str(self.home / "miniconda3"))
                    source = source.replace("/usr/share/lmod/lmod/init/zsh", str(Path(self.temp.name) / "absent-lmod"))
                    command = "micromamba" if host in ["sherlock", "marlowe"] else "mamba"
                    got = self.run_shell(source, "eval '" + command + " \"argument with spaces\"'", shell)
                    self.assertEqual(got, "<argument with spaces>")

    def test_juliaup_home_path_is_idempotent(self):
        source = (ROOT / "home/.hosts/wsl-ubuntu/.config/sh/.profile").read_text()
        got = self.run_shell(source, '. "$1"; printf "%s" "$PATH"')
        self.assertEqual(got.split(":").count(str(self.home / ".juliaup/bin")), 1)

    def test_marlowe_cargo_home_is_durable_and_not_eagerly_created(self):
        scratch = Path(self.temp.name) / "scratch"
        source = (ROOT / "home/.hosts/marlowe/.config/sh/.profile").read_text()
        source = source.replace("/scratch/$PROJECT_ID", str(scratch))
        for extra, want in [({}, "unset"), ({"CARGO_HOME": str(self.home / "cargo")}, str(self.home / "cargo"))]:
            self.assertEqual(self.run_shell(source, 'printf "%s" "${CARGO_HOME-unset}"', extra=extra), want)
            self.assertFalse((scratch / ".cargo").exists(), "shell startup created scratch Cargo home")
            self.assertFalse((self.home / "cargo").exists(), "shell startup created explicit Cargo home")

    def test_marlowe_hf_token_stays_out_of_scratch(self):
        scratch = Path(self.temp.name) / "scratch"
        source = (ROOT / "home/.hosts/marlowe/.config/sh/.profile").read_text()
        source = source.replace("/scratch/$PROJECT_ID", str(scratch))
        explicit = str(self.home / "elsewhere/token")
        for extra, want in [({}, str(self.home / ".config/huggingface/token")), ({"HF_TOKEN_PATH": explicit}, explicit)]:
            self.assertEqual(self.run_shell(source, 'printf "%s" "$HF_TOKEN_PATH"', extra=extra), want)
        self.assertFalse((self.home / ".config/huggingface").exists(), "shell startup created the token directory")

    @unittest.skipUnless(shutil.which("zsh"), "zsh unavailable")
    def test_marlowe_zsh_loads_site_default_modules(self):
        # Site paths become fixtures: Lmod's init file defines a recording
        # `module`, and /etc/bash.bashrc is a file that, like the site's,
        # returns early without PS1.
        root = Path(self.temp.name)
        init = root / "lmod-init.zsh"
        init.write_text("""module() {
    print -r -- "$* [$(/bin/sh -c 'printf %s "${LMOD_SYSTEM_DEFAULT_MODULES-unset}"')]" >>"$MODULE_LOG"
    if [[ -n ${MODULE_FAIL-} ]]; then
        print -ru2 -- "Lmod has detected the following error: fixture"
        return 1
    fi
    export LOADEDMODULES=slurm/slurm/25.05.2:gcc/13.1.0 PATH="$MODULE_BIN:$PATH"
}
""")
        site = root / "site-bashrc"
        site.write_text('[ -z "$PS1" ] && return\nexport LMOD_SYSTEM_DEFAULT_MODULES=slurm,gcc/13.1.0\n')
        stock = root / "stock-bashrc"
        stock.write_text('[ -z "$PS1" ] && return\nshopt -s checkwinsize\n')
        noisy = root / "bash-env"
        noisy.write_text("echo BASH_ENV-NOISE\n")
        log = root / "module.log"
        base = {"MODULEPATH": str(root / "modulefiles"), "MODULE_LOG": str(log), "MODULE_BIN": str(root / "slurm/bin")}
        report = ('print -r -- "${LOADEDMODULES-unset}"; '
                  "/bin/sh -c 'printf \"%s\\n\" \"${LMOD_SYSTEM_DEFAULT_MODULES-unset}\"'; print -r -- \"$PATH\"")
        restore = "--initial_load restore [slurm,gcc/13.1.0]\n"

        def start(site_file, extra=None, stderr=""):
            log.unlink(missing_ok=True)
            source = (ROOT / "home/.hosts/marlowe/.config/zsh/.zshrc").read_text()
            for site_path, fixture in [("/usr/share/lmod/lmod/init/zsh", init), ("/etc/bash.bashrc", site_file)]:
                self.assertIn(site_path, source)
                source = source.replace(site_path, str(fixture))
            got = self.run_shell(source, report, "zsh", dict(base, **(extra or {})), stderr).split("\n")
            return got, log.read_text() if log.exists() else ""

        # BASH_ENV, which /etc/profile points at Lmod's bash init, must not
        # reach the list a throwaway bash prints.
        for name, extra in [("site defaults", {}), ("noisy BASH_ENV", {"BASH_ENV": str(noisy)})]:
            with self.subTest(name):
                (loaded, exported, path), calls = start(site, extra)
                self.assertEqual(calls, restore)
                self.assertEqual((loaded, exported), ("slurm/slurm/25.05.2:gcc/13.1.0", "slurm,gcc/13.1.0"))
                entries = path.split(":")
                self.assertLess(entries.index(str(self.home / "micromamba/envs/login/bin")),
                                entries.index(base["MODULE_BIN"]))
        for name, site_file, extra, want in [
                ("modules already loaded", site, {"LOADEDMODULES": "gcc/13.1.0"}, "slurm,gcc/13.1.0"),
                ("list already exported", site, {"LMOD_SYSTEM_DEFAULT_MODULES": "slurm"}, "slurm"),
                ("no MODULEPATH", site, {"MODULEPATH": ""}, "unset"),
                ("site file names no default", stock, {}, "unset"),
                ("no site file", root / "absent-bashrc", {}, "unset")]:
            with self.subTest(name):
                got, calls = start(site_file, extra)
                self.assertEqual((calls, got[1]), ("", want))
        # A failed load is Lmod's to report; the list stays exported, so a
        # nested shell does not retry, and the rest of the rc file runs.
        got, calls = start(site, {"MODULE_FAIL": "1"}, "Lmod has detected the following error: fixture\n")
        self.assertEqual((calls, got[:2]), (restore, ["unset", "slurm,gcc/13.1.0"]))
        self.assertIn(str(self.home / "micromamba/envs/login/bin"), got[2].split(":"))

    @unittest.skipUnless(shutil.which("zsh"), "zsh unavailable")
    def test_marlowe_zsh_drops_the_brew_plugin(self):
        # The shared rc, interactive, with a role rc and a fake oh-my-zsh that
        # prints the plugin list it would load. Without a terminal, only stty
        # may complain.
        (self.home / ".config/zsh").mkdir(parents=True)
        (self.home / ".oh-my-zsh").mkdir()
        (self.home / ".profile").write_text((ROOT / "home/dot_profile").read_text())
        (self.home / ".oh-my-zsh/oh-my-zsh.sh").write_text('print -rl -- "${plugins[@]}"\n')
        marlowe = (ROOT / "home/.hosts/marlowe/.config/zsh/.zshrc").read_text()
        for site_path in ["/usr/share/lmod/lmod/init/zsh", "/etc/bash.bashrc"]:
            marlowe = marlowe.replace(site_path, str(Path(self.temp.name) / "absent"))

        def plugins(role_rc):
            (self.home / ".config/zsh/.zshrc").write_text(role_rc)
            result = subprocess.run([shutil.which("zsh"), "-f", "-i", "-c", '. "$1"', "zsh", str(ROOT / "home/dot_zshrc")],
                                    env=dict(self.env, TERM="dumb"), stdin=subprocess.DEVNULL, text=True,
                                    capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual([line for line in result.stderr.splitlines() if not line.startswith("stty: ")], [])
            return result.stdout.split()

        shared = plugins("")
        self.assertIn("brew", shared)
        # The rest keeps its order; the role's snap and ubuntu come before
        # fzf, which the shared rc appends after the role rc.
        want = [plugin for plugin in shared if plugin != "brew"]
        want[want.index("fzf"):want.index("fzf")] = ["snap", "ubuntu"]
        self.assertEqual(plugins(marlowe), want)

    def test_linuxbrew_home_and_path_discovery(self):
        prefix = self.home / ".linuxbrew"
        brew = prefix / "bin/brew"
        brew.parent.mkdir(parents=True)
        brew.write_text("#!/bin/sh\n[ \"$1\" = shellenv ] || exit 1\necho 'export BREW_DISCOVERED=yes'\n")
        brew.chmod(0o755)
        for host in ["wsl-ubuntu", "lab-ubuntu"]:
            for shell in ["bash", "zsh"]:
                if not shutil.which(shell):
                    continue
                source = (ROOT / "home/.hosts" / host / f".config/{shell}/.{shell}rc").read_text()
                source = source.replace("/home/linuxbrew/.linuxbrew", str(Path(self.temp.name) / "absent-brew"))
                source = source.replace("/apps/miniconda3", str(Path(self.temp.name) / "absent-conda"))
                for path in ["/usr/bin:/bin", str(prefix / "bin") + ":/usr/bin:/bin"]:
                    with self.subTest(host=host, shell=shell, path=path):
                        got = self.run_shell(source, 'printf "%s" "${BREW_DISCOVERED-no}"', shell, {"PATH": path})
                        self.assertEqual(got, "yes")

    def test_linuxbrew_path_outside_default_prefixes(self):
        bindir = Path(self.temp.name) / "custom-brew/bin"
        bindir.mkdir(parents=True)
        brew = bindir / "brew"
        brew.write_text("#!/bin/sh\n[ \"$1\" = shellenv ] || exit 1\necho 'export BREW_DISCOVERED=custom'\n")
        brew.chmod(0o755)
        for host in ["wsl-ubuntu", "lab-ubuntu"]:
            for shell in ["bash", "zsh"]:
                if not shutil.which(shell):
                    continue
                with self.subTest(host=host, shell=shell):
                    source = (ROOT / "home/.hosts" / host / f".config/{shell}/.{shell}rc").read_text()
                    source = source.replace("/home/linuxbrew/.linuxbrew", str(Path(self.temp.name) / "absent-brew"))
                    source = source.replace("/apps/miniconda3", str(Path(self.temp.name) / "absent-conda"))
                    got = self.run_shell(source, 'printf "%s" "${BREW_DISCOVERED-no}"', shell,
                                         {"PATH": str(bindir) + ":/usr/bin:/bin"})
                    self.assertEqual(got, "custom")

    def test_mac_homebrew_profile(self):
        original = (ROOT / "home/.hosts/mac/.config/sh/.profile").read_text()
        for prefix_name in ["arm", "intel"]:
            prefix = Path(self.temp.name) / prefix_name
            brew = prefix / "bin/brew"
            brew.parent.mkdir(parents=True)
            brew.write_text("""#!/bin/sh
[ "$1" = shellenv ] || exit 1
printf 'export HOMEBREW_PREFIX="%s"; export PATH="%s/bin:%s/sbin:$PATH"\\n' "${0%/bin/brew}" "${0%/bin/brew}" "${0%/bin/brew}"
""")
            brew.chmod(0o755)
            replacements = {"/opt/homebrew": str(prefix) if prefix_name == "arm" else str(prefix / "missing"),
                            "/usr/local": str(prefix) if prefix_name == "intel" else str(prefix / "missing")}
            source = original
            for old, new in replacements.items():
                source = source.replace(old, new)
            nodebin = self.home / ".nvm/versions/node/v24.11.1/bin"
            nodebin.mkdir(parents=True, exist_ok=True)
            got = self.run_shell(source, 'p=$PATH; . "$1"; [ "$PATH" = "$p" ] || exit 9; command -v brew',
                                 extra={"PATH": str(nodebin) + ":/usr/bin:/bin", "NVM_DIR": str(self.home / ".nvm")})
            self.assertEqual(got, str(brew))
            got = self.run_shell(source, 'printf "%s" "$PATH"',
                                 extra={"PATH": str(nodebin) + ":/usr/bin:/bin", "NVM_DIR": str(self.home / ".nvm")})
            self.assertEqual(got.split(":")[:3], [str(nodebin), str(prefix / "bin"), str(prefix / "sbin")])
            brew.chmod(0o644)
            self.assertEqual(self.run_shell(source, 'printf "%s" "$PATH"'), "/usr/bin:/bin")


if __name__ == "__main__":
    unittest.main()
