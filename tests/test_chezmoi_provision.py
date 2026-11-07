"""Native provisioning uses verified tools without the legacy parser runtime."""

import os
import hashlib
import io
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import tarfile
import unittest

from chezmoi_source_support import SourceFixture


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipIf(os.name == "nt", "Unix provisioning entrypoints")
class NativeProvisionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="dotfiles-native-provision-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        self.env = {
            "HOME": str(self.home), "PATH": "/usr/bin:/bin", "LC_ALL": "C",
            "DOTFILES_AUTO_UPDATE": "0",
            "BOOTSTRAP_UNAME_S": "Linux", "BOOTSTRAP_UNAME_M": "x86_64",
        }

    def run_script(self, script, *args):
        return subprocess.run(
            [shutil.which("bash"), str(ROOT / script), *args], env=self.env,
            text=True, capture_output=True, stdin=subprocess.DEVNULL, check=False,
        )

    def test_setup_list_names_chezmoi_steps(self):
        result = self.run_script("setup-host.sh", "--host", "lab-ubuntu", "--list")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("S4-chezmoi", result.stdout)
        self.assertIn("H7-native", result.stdout)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_unconfigured_home_needs_host(self):
        expected = {"setup-host.sh": "no host: pass --host", "doctor.sh": "no host given"}
        for script, text in expected.items():
            with self.subTest(script=script):
                result = self.run_script(script, "--list")
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertIn(text, result.stderr)
                self.assertEqual(list(self.home.iterdir()), [])

    def test_sherlock_plan_uses_static_binary_for_legacy_glibc(self):
        # The real host has glibc 2.17; the generic v2.74 binary requires 2.34.
        for host, platform in (("sherlock", "linux-musl"), ("marlowe", "linux"),
                               ("lab-ubuntu", "linux"), ("wsl-ubuntu", "linux")):
            with self.subTest(host=host):
                result = subprocess.run(
                    [shutil.which("bash"), "-eu", "-c", '''
for lib in manifest steps-common steps-archives; do
    . "$1/lib/bootstrap/$lib.sh"
done
bootstrap_init "$1"
STEPS_HOST=$2 STEPS_ARCH=x86_64
step_S4_chezmoi_plan
''', "_", str(ROOT), host], cwd=self.home, env=self.env, text=True, capture_output=True,
                    stdin=subprocess.DEVNULL, check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertRegex(result.stdout, rf"chezmoi_[^ ]+_{platform}_amd64\.tar\.gz")
                self.assertIn(str(self.home / ".local/bin/chezmoi"), result.stdout)
                self.assertEqual(list(self.home.iterdir()), [])

    def test_doctor_list_names_chezmoi_checks(self):
        result = self.run_script("doctor.sh", "--host", "lab-ubuntu", "--list")
        self.assertEqual(result.returncode, 0, result.stderr)
        ids = {line.split("\t")[0] for line in result.stdout.splitlines()}
        self.assertIn("chezmoi", ids)
        self.assertIn("native-config", ids)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_native_handoff_only_prints_reviewed_procedure(self):
        result = self.run_script("setup-host.sh", "--host", "lab-ubuntu", "--print-manual")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("# Follow Fresh home by hand in docs/bootstrap.md from this checkout.", result.stdout)
        self.assertNotIn("init --apply", result.stdout)
        self.assertEqual(list(self.home.iterdir()), [])

    def write_config(self, *config_lines, source=ROOT):
        """Give this home a local config naming SOURCE, then CONFIG_LINES."""
        config = self.home / ".config/chezmoi/chezmoi.toml"
        config.parent.mkdir(parents=True, exist_ok=True)
        config.write_text(f'destDir = "{self.home.resolve()}"\nsourceDir = "{source}"\n'
                          + "".join(f"{line}\n" for line in config_lines))

    def home_snapshot(self):
        return sorted((str(path.relative_to(self.home)), path.lstat().st_mtime_ns)
                      for path in self.home.rglob("*"))

    def test_native_role_selects_host_without_receipt_or_environment(self):
        self.write_config("[data]", "host = 'lab-ubuntu'")
        before = self.home_snapshot()
        for script, step in (("doctor.sh", "native-config"), ("setup-host.sh", "H7-native")):
            with self.subTest(script=script):
                explicit = self.run_script(script, "--host", "lab-ubuntu", "--list")
                other = self.run_script(script, "--host", "sherlock", "--list")
                resolved = self.run_script(script, "--list")
                self.assertEqual(resolved.returncode, 0, resolved.stderr)
                self.assertIn(step, resolved.stdout)
                self.assertNotEqual(explicit.stdout, other.stdout)
                self.assertEqual(resolved.stdout, explicit.stdout)
        self.assertEqual(self.home_snapshot(), before)

    def test_native_common_only_role_is_common_only(self):
        os_release = self.base / "os-release"
        os_release.write_text("ID=ubuntu\n")
        self.env["BOOTSTRAP_OS_RELEASE"] = str(os_release)
        self.write_config("[data]", 'host = "common-only"')
        doctor = self.run_script("doctor.sh", "--list")
        self.assertEqual(doctor.returncode, 0, doctor.stderr)
        self.assertIn("selects [data].host common-only (no host overlay): checking as --platform debian",
                      doctor.stderr)
        setup = self.run_script("setup-host.sh", "--list")
        self.assertEqual(setup.returncode, 2, setup.stderr)
        self.assertIn("selects [data].host common-only (no host overlay)", setup.stderr)
        self.assertIn("pass --host HOST", setup.stderr)
        self.assertEqual(self.run_script("setup-host.sh", "--host", "lab-ubuntu", "--list").returncode, 0)

    def test_native_home_without_one_role_requires_host(self):
        for lines in (("[git]", "autoAdd = false"), ("[data]", "host = 'fedora'"),
                      ("[data]", "host = 'mac'", "host = 'lab-ubuntu'")):
            with self.subTest(lines=lines):
                self.write_config(*lines)
                doctor = self.run_script("doctor.sh", "--list")
                self.assertEqual(doctor.returncode, 2, doctor.stderr)
                self.assertIn("selects no single known [data].host; pass --host HOST", doctor.stderr)
                setup = self.run_script("setup-host.sh", "--list")
                self.assertEqual(setup.returncode, 2, setup.stderr)
                self.assertIn("selects no single known [data].host; pass --host HOST", setup.stderr)

    def check_h7_native(self):
        # --check refuses a machine that is not the host: pin Ubuntu (macOS CI).
        os_release = self.base / "os-release"
        os_release.write_text("ID=ubuntu\n")
        self.env["BOOTSTRAP_OS_RELEASE"] = str(os_release)
        return self.run_script("setup-host.sh", "--host", "lab-ubuntu", "--check", "--only", "H7-native")

    def test_configured_home_reports_h7_native_done(self):
        self.write_config("[data]", "host = 'lab-ubuntu'")
        before = self.home_snapshot()
        result = self.check_h7_native()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r"(?m)^H7-native done ")
        self.assertEqual(self.home_snapshot(), before)
        other = self.base / "other-checkout"
        other.mkdir()
        (other / ".chezmoiroot").write_text("home\n")
        self.write_config("[data]", "host = 'lab-ubuntu'", source=other.resolve())
        result = self.check_h7_native()
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r"(?m)^H7-native human ")

    def test_native_role_reader_accepts_chezmoi_init_output(self):
        # The doctor's text reader and the login updater's source lookup
        # against the real init rendering (toToml), also from a seed with a
        # case variant of sourceDir (the template folds it) and mode symlink.
        roles = ("common-only", "mac" if sys.platform == "darwin" else "lab-ubuntu")
        guard = '. "$1/lib/chezmoi-guard.sh"; dotfiles_chezmoi_source "$2"'
        for role in roles:
            for seed in ("", 'SOURCEDIR = "/elsewhere"\nmode = "symlink"\n'):
                with self.subTest(role=role, seed=seed), SourceFixture(role) as fixture:
                    fixture.config.write_text(f'{seed}[data]\nhost = "{role}"\nlocal_canary = "x"\n'
                                              '[data.decoy]\nhost = "win"\n[git]\nautoCommit = true\n')
                    result = fixture.run("init")
                    self.assertEqual(result.returncode, 0, result.stderr)
                    rendered = fixture.config.read_bytes()
                    self.assertIn("[data]", rendered.decode().splitlines())
                    (self.home / ".config/chezmoi").mkdir(parents=True, exist_ok=True)
                    (self.home / ".config/chezmoi/chezmoi.toml").write_bytes(rendered)
                    reader = subprocess.run(
                        [shutil.which("bash"), "-c", '. "$1/lib/bootstrap/platform.sh"; bootstrap_native_host', "_",
                         str(ROOT)], env=self.env, text=True, capture_output=True, stdin=subprocess.DEVNULL,
                        check=False)
                    self.assertEqual(reader.returncode, 0, reader.stderr)
                    self.assertEqual(reader.stdout, f"{role}\n")
                    placed = fixture.destination / ".config/chezmoi/chezmoi.toml"
                    placed.parent.mkdir(parents=True, exist_ok=True)
                    placed.write_bytes(rendered)
                    lookup = subprocess.run(["sh", "-c", guard, "_", str(ROOT), str(fixture.destination)],
                                            text=True, capture_output=True, stdin=subprocess.DEVNULL, check=False)
                    self.assertEqual((lookup.returncode, lookup.stdout, lookup.stderr),
                                     (0, f"{fixture.source}\n", ""))

    def archive_fixture(self, digest_ok=True):
        repo = self.base / "repo"
        shutil.copytree(ROOT / "lib", repo / "lib")
        shutil.copytree(ROOT / "config" / "bootstrap", repo / "config" / "bootstrap")
        archive = self.base / "chezmoi.tar.gz"
        executable = b"#!/bin/sh\nprintf 'chezmoi version v2.74.0\\n'\n"
        with tarfile.open(archive, "w:gz") as bundle:
            info = tarfile.TarInfo("chezmoi")
            info.size, info.mode = len(executable), 0o755
            bundle.addfile(info, io.BytesIO(executable))
        digest = hashlib.sha256(archive.read_bytes()).hexdigest() if digest_ok else "0" * 64
        manifest = repo / "config" / "bootstrap" / "installers.tsv"
        manifest.write_text(
            "id\tkind\turl\tsha256\tdest\thosts\tarch\ttier\thuman\n"
            f"chezmoi\tarchive\thttps://example.invalid/chezmoi.tar.gz\t{digest}\t"
            "$HOME/.local/bin/chezmoi\tlab-ubuntu\tx86_64\tcore\t-\n"
        )
        fake = self.base / "bin"
        fake.mkdir()
        (fake / "curl").write_text(
            "#!/bin/sh\nwhile [ \"$#\" -gt 0 ]; do\n"
            "if [ \"$1\" = -o ]; then shift; out=$1; fi\nshift\ndone\n"
            "cp \"$ARCHIVE\" \"$out\"\n"
        )
        (fake / "curl").chmod(0o755)
        self.env.update(PATH=f"{fake}:/usr/bin:/bin", ARCHIVE=str(archive), FIXTURE_ROOT=str(repo))
        return repo, executable

    def run_install(self):
        return subprocess.run(
            [shutil.which("bash"), "-eu", "-c", '''
for lib in manifest platform version checks fetch steps steps-common steps-archives; do
    . "$FIXTURE_ROOT/lib/bootstrap/$lib.sh"
done
. "$FIXTURE_ROOT/lib/terminal.sh"
bootstrap_init "$FIXTURE_ROOT"
STEPS_ROOT=$FIXTURE_ROOT STEPS_HOST=lab-ubuntu STEPS_PROFILE=debian STEPS_ARCH=x86_64
step_S4_chezmoi_apply
step_S4_chezmoi_check
'''], env=self.env, text=True, capture_output=True, stdin=subprocess.DEVNULL, check=False,
        )

    def test_install_verified_archive_without_parser_or_config_apply(self):
        _repo, executable = self.archive_fixture()
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        destination = self.home / ".local/bin/chezmoi"
        self.assertEqual(destination.read_bytes(), executable)
        self.assertTrue(os.access(destination, os.X_OK))
        self.assertFalse((self.home / ".config").exists())

    def test_wrong_digest_preserves_existing_binary(self):
        self.archive_fixture(digest_ok=False)
        destination = self.home / ".local/bin/chezmoi"
        destination.parent.mkdir(parents=True)
        destination.write_text("old binary")
        result = self.run_install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sha256", result.stderr.lower())
        self.assertEqual(destination.read_text(), "old binary")

    def test_install_refuses_link_destination(self):
        self.archive_fixture()
        outside = self.base / "foreign"
        outside.write_text("foreign binary")
        destination = self.home / ".local/bin/chezmoi"
        destination.parent.mkdir(parents=True)
        destination.symlink_to(outside)
        result = self.run_install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlink", result.stderr)
        self.assertEqual(outside.read_text(), "foreign binary")
        self.assertTrue(destination.is_symlink())

    def test_native_doctor_real_version_probe_is_write_free(self):
        binary = os.environ.get("DOTFILES_TEST_CHEZMOI")
        if not binary or not Path(binary).is_file():
            self.skipTest("DOTFILES_TEST_CHEZMOI is required for the real binary no-write probe")
        repo = self.base / "doctor-repo"
        shutil.copytree(ROOT / "lib", repo / "lib")
        shutil.copytree(ROOT / "config", repo / "config")
        (repo / "docs").mkdir()
        shutil.copy2(ROOT / "docs/bootstrap.md", repo / "docs/bootstrap.md")
        shutil.copy2(ROOT / "doctor.sh", repo / "doctor.sh")
        (repo / "config/bootstrap/tools.tsv").write_text(
            "id\ttier\thosts\tprobe\tversion_flag\tfloor\tabsent\tdoc\n"
            "chezmoi\tcore\tall\tchezmoi\t--version\t2.74.0\tmissing native tool\tS4-chezmoi\n"
        )
        local = self.home / ".local/bin"
        local.mkdir(parents=True)
        (local / "chezmoi").symlink_to(binary)
        before = sorted(str(path.relative_to(self.home)) for path in self.home.rglob("*"))
        result = subprocess.run(
            [shutil.which("bash"), str(repo / "doctor.sh"), "--host", "lab-ubuntu", "--tsv"],
            env=self.env, text=True, capture_output=True, stdin=subprocess.DEVNULL, check=False,
        )
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("ok\tchezmoi\t", result.stdout)
        self.assertEqual(sorted(str(path.relative_to(self.home)) for path in self.home.rglob("*")), before)


if __name__ == "__main__":
    unittest.main()
