"""Every relative link and #anchor in a tracked Markdown file resolves.

Relative targets must be tracked files or directories, and #anchors GitHub
heading slugs.
"""
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def tracked(root, *paths):
    out = subprocess.run(["git", "ls-files", "-z", "--", *paths], cwd=root,
                         capture_output=True, check=True).stdout
    return sorted(p for p in out.decode("utf-8").split("\0") if p)


FENCE = re.compile(r"^ {0,3}(?:```|~~~)")
HEADING = re.compile(r"^ {0,3}#{1,6}\s+(.*?)\s*#*\s*$")
LINK = re.compile(r"(?<!\\)\[[^\]]*\]\(([^()\s]+)(?:\s+\"[^\"]*\")?\)")
SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


def prose(text):
    lines, fenced = [], False
    for line in text.split("\n"):
        if FENCE.match(line):
            fenced = not fenced
            lines.append("")
        else:
            lines.append("" if fenced else line)
    return "\n".join(lines)


def heading_slugs(text):
    slugs, seen = set(), {}
    for line in prose(text).split("\n"):
        match = HEADING.match(line)
        if match:
            slug = re.sub(r"[^\w\- ]", "", match.group(1).strip().lower()).replace(" ", "-")
            count = seen.get(slug, 0)
            seen[slug] = count + 1
            slugs.add(slug if count == 0 else f"{slug}-{count}")
    return slugs


def relative_links(text):
    body = prose(text)
    for match in LINK.finditer(body):
        if not SCHEME.match(match.group(1)):
            yield body.count("\n", 0, match.start()) + 1, match.group(1)


def resolve(source, target):
    parts = []
    for part in (PurePosixPath(source).parent / target).parts:
        if part == "..":
            if not parts:
                return None
            parts.pop()
        elif part != ".":
            parts.append(part)
    return "/".join(parts)


def broken_links(root, files):
    files = set(files)
    dirs = {str(p) for f in files for p in PurePosixPath(f).parents}
    slugs, problems = {}, []
    for source in sorted(f for f in files if f.endswith(".md")):
        if not (root / source).is_file():
            problems.append(f"{source}: tracked but missing from the work tree")
            continue
        for number, target in relative_links((root / source).read_text(encoding="utf-8")):
            path, _, anchor = target.partition("#")
            dest = resolve(source, path) if path else source
            if dest is None or (dest.rstrip("/") not in files and dest.rstrip("/") not in dirs):
                problems.append(f"{source}:{number}: no tracked target {target}")
                continue
            if anchor and dest.endswith(".md"):
                if dest not in slugs:
                    target_file = root / dest
                    slugs[dest] = heading_slugs(target_file.read_text(encoding="utf-8")) if target_file.is_file() else set()
                if anchor not in slugs[dest]:
                    problems.append(f"{source}:{number}: no heading for {target}")
    return problems


class MarkdownLinkTests(unittest.TestCase):
    def test_heading_slugs_follow_github(self):
        text = ("# T\n## Login updates\n### W1-chezmoi: Provision the binary\n"
                "```sh\n# not a heading\n```\n## Login updates\n## `persistentState` (2026-11-04)\n")
        self.assertEqual(heading_slugs(text), {"t", "login-updates", "login-updates-1",
                                               "w1-chezmoi-provision-the-binary",
                                               "persistentstate-2026-11-04"})

    def test_only_relative_links_outside_code_are_checked(self):
        text = ("[a](x.md#y) [web](https://example.org/z) [m](mailto:a@b)\n```\n[c](inside.md)\n```\n"
                "[wrapped\ntext](../z.md)\n")
        self.assertEqual(list(relative_links(text)), [(1, "x.md#y"), (5, "../z.md")])
        self.assertIsNone(resolve("README.md", "../outside.md"))
        self.assertEqual(resolve("docs/a.md", "../tests/COVERAGE.md"), "tests/COVERAGE.md")

    def test_missing_tracked_markdown_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a.md").write_text("[gone](gone.md)\n[part](gone.md#x)\n", encoding="utf-8")
            problems = broken_links(root, ["a.md", "gone.md"])
        self.assertEqual(problems, ["a.md:2: no heading for gone.md#x", "gone.md: tracked but missing from the work tree"])

    def test_nested_markdown_is_a_link_source_and_target(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "docs").mkdir()
            (root / "docs/r.md").write_text("# Kept\n[gone](../gone.md)\n[part](r.md#nowhere)\n",
                                            encoding="utf-8")
            (root / "a.md").write_text("[ok](docs/r.md#kept)\n[bad](docs/r.md#nowhere)\n",
                                       encoding="utf-8")
            problems = broken_links(root, ["a.md", "docs/r.md"])
        self.assertEqual(problems, ["a.md:2: no heading for docs/r.md#nowhere",
                                    "docs/r.md:2: no tracked target ../gone.md",
                                    "docs/r.md:3: no heading for r.md#nowhere"])

    def test_tracked_markdown_links_and_anchors_resolve(self):
        problems = broken_links(ROOT, tracked(ROOT))
        self.assertEqual(problems, [], "\n" + "\n".join(problems))


if __name__ == "__main__":
    unittest.main()
