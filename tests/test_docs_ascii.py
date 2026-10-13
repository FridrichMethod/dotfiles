"""Exercise documentation checks with isolated Git repos and local submodules."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


CHECKER = Path(__file__).resolve().parents[1] / "scripts/check-docs.py"


class DocumentationASCII(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="docs-ascii-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.repo = self.base / "repo with spaces"
        self.repo.mkdir()
        self.env = os.environ.copy()
        self.env.update({
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Fixture",
            "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
            "GIT_COMMITTER_NAME": "Fixture",
            "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
            "GIT_CONFIG_COUNT": "0",
        })
        for name in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"):
            self.env.pop(name, None)
        self.git(self.repo, "-c", "init.templateDir=", "init", "-q")
        self.write(self.repo, "README.md", b"# English documentation\n")
        self.git(self.repo, "add", "README.md")
        self.git(self.repo, "commit", "-qm", "fixture")

    def git(self, repo, *args):
        return subprocess.check_output(["git", "-C", str(repo), *args], env=self.env,
                                       stderr=subprocess.PIPE)

    def write(self, repo, name, data):
        path = repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def check(self, repo=None):
        return subprocess.run([sys.executable, "-B", str(CHECKER), "--root", str(repo or self.repo)],
                              env=self.env, capture_output=True, text=True, timeout=20)

    def submodule(self, parent, name):
        source = self.base / (name.replace("/", "-") + "-source")
        source.mkdir()
        self.git(source, "-c", "init.templateDir=", "init", "-q")
        self.write(source, "README.md", b"# English module\n")
        self.git(source, "add", "README.md")
        self.git(source, "commit", "-qm", "fixture")
        self.git(parent, "-c", "protocol.file.allow=always", "submodule", "add", "-q", str(source), name)
        return parent / name

    def test_ascii_documentation_accepts_markdown_and_standard_whitespace(self):
        self.write(self.repo, "docs/guide.md", b"# Guide\r\n\tUse `codex-as A`.\nA -> B; +-- tree\n")
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_chinese_emoji_smart_punctuation_and_control_characters(self):
        for text in ("\u4e2d\u6587", "\U0001f680", "\u2014", "\x1b", "\x00", "\x7f"):
            with self.subTest(text=ascii(text)):
                self.write(self.repo, "docs/guide.md", ("English\n" + text + "\n").encode())
                result = self.check()
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn("docs/guide.md:2:1:", result.stderr)
                self.assertIn("ASCII", result.stderr)
                self.assertTrue(result.stderr.isascii())

    def test_current_worktree_contents_are_checked_without_staging(self):
        self.write(self.repo, "README.md", "# \u4e2d\u6587\n".encode())
        result = self.check()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("README.md", result.stderr)

    def test_deleted_documentation_does_not_block_the_hook(self):
        (self.repo / "README.md").unlink()
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_all_documentation_formats_are_checked(self):
        for name in ("guide.MD", "guide.markdown", "guide.mdx", "guide.rst", "guide.txt",
                     "README", "README.en", "LICENSE", "CONTRIBUTING", "NOTICE"):
            with self.subTest(name=name):
                path = self.write(self.repo, name, "\u4e2d\u6587\n".encode())
                result = self.check()
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn(name, result.stderr)
                path.unlink()

    def test_ignored_files_and_source_unicode_fixtures_are_outside_documentation_scope(self):
        self.write(self.repo, ".gitignore", b"ignored.md\n")
        self.write(self.repo, "ignored.md", "\u4e2d\u6587\n".encode())
        self.write(self.repo, "fixture.py", "value = '\U0001f680'\n".encode())
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_invalid_utf8_is_rejected_with_a_file_location(self):
        self.write(self.repo, "docs/guide.md", b"English\n\xff\n")
        result = self.check()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("docs/guide.md:2:1:", result.stderr)

    def test_submodule_worktree_documentation_is_checked(self):
        child = self.submodule(self.repo, "vendor/kit")
        self.write(child, "README.md", "English\n\u4e2d\u6587\n".encode())
        result = self.check()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("vendor/kit/README.md:2:1:", result.stderr)
        self.write(child, "README.md", b"English\n")
        self.assertEqual(self.check().returncode, 0)

    def test_nested_submodules_are_checked_recursively(self):
        child = self.submodule(self.repo, "vendor/kit")
        grandchild = self.submodule(child, "nested/leaf")
        self.write(grandchild, "README.md", "\U0001f680\n".encode())
        result = self.check()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("vendor/kit/nested/leaf/README.md:1:1:", result.stderr)

    def test_commit_hook_git_environment_does_not_leak_into_submodules(self):
        self.submodule(self.repo, "vendor/kit")
        self.env.update({
            "GIT_INDEX_FILE": str(self.repo / '.git/index'),
            "GIT_DIR": str(self.repo / '.git'),
            "GIT_WORK_TREE": str(self.repo),
            "GIT_COMMON_DIR": str(self.repo / '.git'),
            "GIT_PREFIX": "",
        })

        result = self.check()

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_uninitialized_submodule_fails_with_setup_instruction(self):
        child = self.submodule(self.repo, "vendor/kit")
        (child / ".git").rename(child / ".git-disabled")
        result = self.check()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("vendor/kit", result.stderr)
        self.assertIn("git submodule update --init --recursive", result.stderr)


if __name__ == "__main__":
    unittest.main()
