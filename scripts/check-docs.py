"""Check English ASCII documentation in this repo and its local submodules."""

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys


DOCUMENT = re.compile(
    r"(\.(md|markdown|mdx|rst|txt)$|(^|/)(README|CHANGELOG|CONTRIBUTING|AUTHORS|LICENSE|NOTICE)(\.[^/]*)?$)",
    re.IGNORECASE,
)
DISALLOWED = re.compile(r"[^\x09\x0a\x0d\x20-\x7e]")


def git(repo, root, *args):
    env = os.environ.copy()
    root_index = env.get("GIT_INDEX_FILE") if repo == root else None
    for variable in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR",
                     "GIT_PREFIX", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES"):
        env.pop(variable, None)
    if root_index:
        env["GIT_INDEX_FILE"] = str(Path(root_index).absolute())
    result = subprocess.run(["git", "-C", str(repo), *args], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, env=env, check=False)
    if result.returncode:
        raise ValueError(result.stderr.decode("utf-8", errors="replace").strip())
    return result.stdout


def report(message):
    print(message.encode("ascii", errors="backslashreplace").decode("ascii"), file=sys.stderr)


def location(name, prefix):
    return f"{name}:{prefix.count(chr(10)) + 1}:{len(prefix) - prefix.rfind(chr(10))}:"


def check_document(path, name):
    try:
        raw = path.read_bytes()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError as error:
            prefix = raw[:error.start].decode("utf-8")
            report(f"{location(name, prefix)} documentation must be UTF-8 and ASCII.")
            return 1
        match = DISALLOWED.search(text)
        if match:
            report(f"{location(name, text[:match.start()])} U+{ord(match[0]):04X} is not permitted; "
                   "use English ASCII documentation.")
            return 1
    except OSError as error:
        report(f"{name}: cannot read documentation: {error}")
        return 1
    return 0


def check_repository(repo, root):
    failures = 0
    entries = git(repo, root, "ls-files", "--stage", "-z").split(b"\0")
    submodules = set()
    for entry in entries:
        if entry:
            metadata, name = entry.split(b"\t", 1)
            if metadata.split()[0] == b"160000":
                submodules.add(os.fsdecode(name))
    names = git(repo, root, "ls-files", "--cached", "--others", "--exclude-standard", "-z")
    for name in sorted({os.fsdecode(item) for item in names.split(b"\0") if item} - submodules):
        path = repo / name
        if DOCUMENT.search(name) and os.path.lexists(path):
            failures += check_document(path, path.relative_to(root).as_posix())
    for name in sorted(submodules):
        path = repo / name
        label = path.relative_to(root).as_posix()
        if not (path / ".git").exists():
            report(f"{label}: submodule is not initialized; run git submodule update --init --recursive.")
            failures += 1
            continue
        try:
            failures += check_repository(path, root)
        except (OSError, ValueError) as error:
            report(f"{label}: cannot check submodule documentation: {error}")
            failures += 1
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        return int(bool(check_repository(root, root)))
    except (OSError, ValueError) as error:
        report(f"documentation check failed: {error}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
