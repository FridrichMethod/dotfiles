"""Stow never links what git ignores, and still links every tracked file.

.stowrc holds a Stow ignore for each .gitignore pattern with no slash but a
trailing one, so a cache, build output or editor file left in a package never
reaches the home. The checks build a name from each such pattern, and near
misses beside it, ask git which of them it ignores, and require the .stowrc
regexes to agree as Stow 2.3 (split on spaces), Stow 2.4 (split like a shell)
and stow-all.ps1 read and apply them, and the installed GNU Stow on a real
package. Standard library only; tests/stow-ignores.sh and tests/run.ps1 run it.
"""
import os
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Top-level directories that hold code, not Stow packages (AGENTS.md); every
# other one is a layer of packages, as stow-all.sh takes it.
NOT_LAYERS = {"config", "docs", "lib", "scripts", "tests"}
# Tracked package files .stowrc keeps out of Stow on purpose: stow-all.sh
# writes each as a machine-local regular file instead.
MATERIALIZED = {".codex/config.toml", ".codex/rules/portable.rules", ".claude/settings.json",
                ".config/fcitx5/profile"}
NESTED = ".config/app/"


def shellwords(line):
    """Text::ParseWords::shellwords, which returns nothing for an unbalanced quote."""
    try:
        return shlex.split(line)
    except ValueError:
        return []


def stowrc_ignores(split):
    """The --ignore regexes of .stowrc as one Stow version compiles them."""
    words = [word for line in (ROOT / ".stowrc").read_text().splitlines() for word in split(line)]
    return [re.compile(f"({word.removeprefix('--ignore=')})\\Z") for word in words if word.startswith("--ignore=")]


def stow_ignores(regexes, path):
    """Whether Stow skips PATH: it tests each directory on the way down, then the file."""
    parts = path.split("/")
    return any(regex.search("/".join(parts[:end])) for end in range(1, len(parts) + 1) for regex in regexes)


def ps1_ignores(path):
    """Whether stow-all.ps1 skips PATH: Get-StowIgnorePattern reads each --ignore=
    line as is, and Test-StowIgnored -match ignores case and anchors nothing,
    tested on the file's whole path, its leaf and, for a pattern with a slash,
    "/PATH"."""
    regexes = [re.compile(line.strip().removeprefix("--ignore=").strip().strip("'\""), re.IGNORECASE)
               for line in (ROOT / ".stowrc").read_text().splitlines() if line.strip().startswith("--ignore=")]
    leaf = path.rsplit("/", 1)[-1]
    return any(regex.search(path) or regex.search(leaf) or ("/" in regex.pattern and regex.search("/" + path))
               for regex in regexes)


READERS = {"Stow 2.3": str.split, "Stow 2.4": shellwords}


def ignorers():
    """Each installer's verdict on a package path, by name."""
    stows = {version: stowrc_ignores(split) for version, split in READERS.items()}
    return {**{version: lambda path, regexes=regexes: stow_ignores(regexes, path) for version, regexes in stows.items()},
            "stow-all.ps1": ps1_ignores}


def gitignore_patterns():
    """The .gitignore patterns that match at any depth, as written."""
    patterns = []
    for line in (ROOT / ".gitignore").read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        if line.startswith("!") or "**" in line or "[!" in line or "[^" in line:
            raise AssertionError(f".gitignore {line!r}: teach tests/test_stow_ignores.py this syntax")
        # A leading or inner slash anchors a pattern to the repository root,
        # so it never matches inside a package on its own.
        if "/" not in line.rstrip("/"):
            patterns.append(line)
    return patterns


def example(pattern):
    """A name PATTERN matches: x for each wildcard, a class's first character."""
    name, index, body = [], 0, pattern.rstrip("/")
    while index < len(body):
        char = body[index]
        if char == "\\":
            index += 1
            name.append(body[index])
        elif char in "*?":
            name.append("x")
        elif char == "[":
            close = body.index("]", index + 2)
            name.append(body[index + 1])
            index = close
        else:
            name.append(char)
        index += 1
    return "".join(name)


def cases():
    """Package paths git ignores, and near misses it keeps, at the top and nested.

    A directory pattern also hides a file of its name from Stow, whose regexes
    cannot tell the two apart; test_tracked_files_are_stowed keeps that from
    ever dropping a tracked file.
    """
    samples, misses = [], []
    for pattern in gitignore_patterns():
        name, below = example(pattern), "/f" if pattern.endswith("/") else ""
        near = [name + "-kept"] if not pattern.rstrip("/").endswith("*") else []
        near += ["kept-" + name] if not pattern.startswith("*") else []
        for prefix in ("", NESTED):
            samples.append(prefix + name + below)
            misses += [prefix + miss + below for miss in near]
    return samples, misses


def git_ignored(paths, scratch):
    """The PATHS that git, reading only this .gitignore, ignores in a package."""
    repo, config = scratch / "repo", scratch / "gitconfig"
    config.write_text("")
    env = os.environ | {"GIT_CONFIG_GLOBAL": str(config), "GIT_CONFIG_NOSYSTEM": "1"}
    subprocess.run(["git", "init", "-q", str(repo)], check=True, env=env)
    shutil.copyfile(ROOT / ".gitignore", repo / ".gitignore")
    # NUL-separated bytes: a text-mode pipe on Windows would end each path in \r.
    result = subprocess.run(["git", "-C", str(repo), "check-ignore", "--no-index", "--stdin", "-z"], env=env,
                            input="".join(f"pkg/{path}\0" for path in paths).encode(), capture_output=True)
    if result.returncode not in (0, 1):
        raise AssertionError(result.stderr.decode(errors="replace"))
    return {path.removeprefix("pkg/") for path in result.stdout.decode().split("\0") if path}


class StowIgnoreTest(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.scratch = Path(scratch.name)
        self.samples, self.misses = cases()

    def test_cases_follow_gitignore(self):
        ignored = git_ignored(self.samples + self.misses, self.scratch)
        self.assertEqual([path for path in self.samples if path not in ignored], [],
                         "example() built a name .gitignore does not match")
        self.assertEqual([path for path in self.misses if path in ignored], [],
                         "cases() built a near miss that .gitignore matches")

    def test_stowrc_ignores_what_git_ignores(self):
        for installer, ignores in ignorers().items():
            with self.subTest(installer):
                self.assertEqual([path for path in self.samples if not ignores(path)], [],
                                 f"{installer} would link these; add their .gitignore patterns to .stowrc")
                self.assertEqual([path for path in self.misses if ignores(path)], [],
                                 f"{installer} would skip these, which git keeps")

    def test_tracked_files_are_stowed(self):
        verdicts = ignorers().values()
        listing = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-s", "-z"], check=True,
                                 capture_output=True, text=True).stdout
        hidden = {}
        for entry in filter(None, listing.split("\0")):
            meta, path = entry.split("\t", 1)
            layer, _, rest = path.partition("/")
            package, _, rest = rest.partition("/")
            if meta.startswith("160000") or not rest or layer.startswith(".") or layer in NOT_LAYERS:
                continue
            if any(ignores(rest) for ignores in verdicts):
                hidden[path] = rest
        self.assertEqual(sorted(path for path, rest in hidden.items() if rest not in MATERIALIZED), [],
                         ".stowrc keeps these tracked files out of the home")
        self.assertEqual(sorted(MATERIALIZED - set(hidden.values())), [],
                         "MATERIALIZED names a file that is no longer tracked or no longer ignored")

    def test_comments_hold_no_option(self):
        # Both Stow versions parse comment lines too and drop their words as
        # package names, but read a word that starts with a dash as an option.
        for number, line in enumerate((ROOT / ".stowrc").read_text().splitlines(), 1):
            if line.startswith("#"):
                for split in READERS.values():
                    self.assertFalse([word for word in split(line) if word.startswith("-")], f".stowrc:{number}")

    @unittest.skipIf(os.name == "nt", "GNU Stow")
    def test_installed_stow_links_only_what_git_keeps(self):
        stow = shutil.which("stow")
        if not stow:
            self.skipTest("GNU Stow not installed")
        package, target = self.scratch / "packages/pkg", self.scratch / "home"
        for path in self.samples + self.misses:
            (package / path).parent.mkdir(parents=True, exist_ok=True)
            (package / path).write_text("fixture\n")
        # A package ignore file replaces Stow's built-in list, which hides *~
        # and #*# by itself, so that only .stowrc decides here.
        (package / ".stow-local-ignore").write_text("^/[.]stow-local-ignore$\n")
        target.mkdir()
        shutil.copyfile(ROOT / ".stowrc", self.scratch / ".stowrc")
        result = subprocess.run([stow, "-n", "-v", "--no-folding", f"--dir={package.parent}", f"--target={target}",
                                 "pkg"], cwd=self.scratch, env=os.environ | {"HOME": str(target)},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        linked = re.findall(r"^LINK: (\S+) => ", result.stderr, re.MULTILINE)
        self.assertEqual(sorted(linked), sorted(self.misses), result.stderr)


if __name__ == "__main__":
    unittest.main()
