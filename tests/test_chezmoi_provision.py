"""Native provisioning uses verified tools without the legacy parser runtime."""

import os
import hashlib
import io
from pathlib import Path
import shutil
import subprocess
import tempfile
import tarfile
import unittest


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
            "DOTFILES_AUTO_UPDATE": "0", "DOTFILES_PAYLOAD_AUTO_UPDATE": "0",
            "DOTFILES_SYNC_PYTHON": str(self.base / "forbidden-python"),
            "BOOTSTRAP_UNAME_S": "Linux", "BOOTSTRAP_UNAME_M": "x86_64",
        }

    def run_script(self, script, *args):
        return subprocess.run(
            [shutil.which("bash"), str(ROOT / script), *args], env=self.env,
            text=True, capture_output=True, stdin=subprocess.DEVNULL, check=False,
        )

    def test_native_setup_default_excludes_sync_and_stow_steps(self):
        result = self.run_script("setup-host.sh", "--host", "lab-ubuntu", "--list")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("S4-chezmoi", result.stdout)
        self.assertIn("H7-native", result.stdout)
        self.assertNotIn("S4-setup-sync", result.stdout)
        self.assertNotIn("H7-stow", result.stdout)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_legacy_setup_is_explicit(self):
        result = self.run_script("setup-host.sh", "--legacy-stow", "--host", "lab-ubuntu", "--list")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("S4-setup-sync", result.stdout)
        self.assertIn("H7-stow", result.stdout)
        self.assertNotIn("S4-chezmoi", result.stdout)

    def test_native_doctor_does_not_require_stow_or_sync_runtime(self):
        result = self.run_script("doctor.sh", "--host", "lab-ubuntu", "--list")
        self.assertEqual(result.returncode, 0, result.stderr)
        ids = {line.split("\t")[0] for line in result.stdout.splitlines()}
        self.assertIn("chezmoi", ids)
        self.assertIn("native-config", ids)
        self.assertTrue({"stow", "stow-links", "venv-sync"}.isdisjoint(ids))
        self.assertEqual(list(self.home.iterdir()), [])

    def test_legacy_doctor_retains_sync_checks(self):
        result = self.run_script("doctor.sh", "--legacy-stow", "--host", "lab-ubuntu", "--list")
        self.assertEqual(result.returncode, 0, result.stderr)
        ids = {line.split("\t")[0] for line in result.stdout.splitlines()}
        self.assertTrue({"stow", "stow-links", "venv-sync"}.issubset(ids))
        self.assertNotIn("chezmoi", ids)

    def test_native_handoff_only_prints_reviewed_procedure(self):
        result = self.run_script("setup-host.sh", "--host", "lab-ubuntu", "--print-manual")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("docs/chezmoi-migration/takeover.md", result.stdout)
        self.assertNotIn("HUMAN-BEGIN H7-stow", result.stdout)
        self.assertNotIn("init --apply", result.stdout)
        self.assertEqual(list(self.home.iterdir()), [])

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
        repo, executable = self.archive_fixture()
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        destination = self.home / ".local/bin/chezmoi"
        self.assertEqual(destination.read_bytes(), executable)
        self.assertTrue(os.access(destination, os.X_OK))
        self.assertFalse((repo / ".venv-sync").exists())
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
        self.assertNotIn("venv-sync", result.stdout)
        self.assertNotIn("stow-links", result.stdout)
        self.assertEqual(sorted(str(path.relative_to(self.home)) for path in self.home.rglob("*")), before)


if __name__ == "__main__":
    unittest.main()
