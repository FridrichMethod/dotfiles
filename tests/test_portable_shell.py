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

    def run_shell(self, source, command, shell="bash", extra=None):
        copy = Path(self.temp.name) / "source"
        copy.write_text(source)
        env = dict(self.env, **(extra or {}))
        flags = ["--norc", "--noprofile"] if shell == "bash" else ["-f"]
        result = subprocess.run([shutil.which(shell), *flags, "-c",
                                 ('shopt -s expand_aliases; ' if shell == 'bash' else '') + '. "$1"; ' + command, shell, str(copy)],
                                env=env, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
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
