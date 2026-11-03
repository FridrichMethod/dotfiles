"""Inventory-derived expectations, independent of candidate source templates."""

from collections import Counter
import json
from dataclasses import dataclass
import os
from pathlib import Path
import re
import shutil
import subprocess

from chezmoi_support import ChezmoiFixture


ROOT = Path(__file__).resolve().parents[1]
ROLES = ("common-only", "mac", "wsl-ubuntu", "lab-ubuntu", "sherlock", "marlowe", "win")
TREES = ("common", *ROLES[1:])
WINDOWS_PACKAGES = {"claude", "codex", "conda", "git", "ssh", "wezterm"}
COUNTS = dict(zip(ROLES, (49, 56, 55, 59, 54, 54, 26)))
AI_MUTABLE = {".claude/settings.json", ".codex/config.toml"}
ROW = re.compile(
    r"^\| `((?:common|mac|sherlock|wsl-ubuntu|lab-ubuntu|marlowe|win)/[^`]+)` "
    r"\| `~/([^`]+)` \| ([^|]+) \| ([OEMXPC]) \| ([^|]+) \| ([^|]+) \| ([^|]+) \|$",
    re.MULTILINE,
)


@dataclass(frozen=True)
class Entry:
    source: str
    destination: str
    hosts: str
    category: str
    representation: str

    def applies(self, role):
        return self.hosts == "A" or self.hosts == role or (self.hosts == "U" and role != "win")


def inventory():
    text = (ROOT / "docs/chezmoi-migration/inventory.md").read_text(encoding="ascii")
    return [Entry(source, target, hosts.strip(), category, representation.strip())
            for source, target, hosts, category, representation, _owner, _retirement in ROW.findall(text)]


def fixture_git_env(env=None):
    # Never inherit a caller's repository, index, hooks or global configuration.
    clean = {key: value for key, value in (os.environ if env is None else env).items()
             if not key.upper().startswith("GIT_")}
    clean.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
    return clean


def indexed_modes():
    git = shutil.which("git")
    if git is None:
        raise RuntimeError("git prerequisite: inventory verification requires git")
    result = subprocess.run([git, "ls-files", "--stage", "-z", "--", *TREES],
                            cwd=ROOT, env=fixture_git_env(), check=True,
                            capture_output=True, timeout=30)
    modes = {}
    for record in result.stdout.decode("utf-8").split("\0"):
        if record:
            metadata, path = record.split("\t", 1)
            mode, _oid, stage = metadata.split()
            if stage != "0":
                raise AssertionError(f"Unmerged inventory path: {path}")
            modes[path] = mode
    return modes


def expected_entries(role):
    return {entry.destination: entry for entry in inventory()
            if entry.applies(role) and entry.category != "C"}


def copy_controls(destination):
    for name in (".chezmoiroot", ".chezmoiversion"):
        shutil.copyfile(ROOT / name, destination / name)
    shutil.copytree(ROOT / "home", destination / "home")


def prepare_source(fixture, role):
    copy_controls(fixture.source)
    for entry in inventory():
        destination = fixture.source / entry.source
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / entry.source, destination)
    fixture.config.write_text(f'[data]\nhost = "{role}"\n', encoding="utf-8")


def snapshot(directory):
    return {path.relative_to(directory).as_posix(): (path.read_bytes(), path.stat().st_mode & 0o777)
            for path in directory.rglob("*") if path.is_file()}


def inventory_problems(entries, modes):
    problems = []
    sources = [entry.source for entry in entries]
    if len(sources) != 95 or Counter(sources) != Counter(modes.keys()):
        problems.append("inventory must contain exactly the 95 indexed package paths once each")
    if Counter(path.split("/", 1)[0] for path in sources) != Counter(
            {"common": 52, "mac": 7, "wsl-ubuntu": 6, "lab-ubuntu": 11,
             "sherlock": 5, "marlowe": 5, "win": 9}):
        problems.append("package counts changed")
    for entry in entries:
        tree, package, relative = entry.source.split("/", 2)
        hosts = ("A" if package in WINDOWS_PACKAGES else "U") if tree == "common" else tree
        if entry.destination != relative or entry.hosts != hosts:
            problems.append(f"incorrect destination/applicability: {entry.source}")
    if Counter(modes.values()) != Counter({"100644": 89, "100755": 6}):
        problems.append("indexed regular/executable modes changed")
    for role, count in COUNTS.items():
        applicable = [entry.destination for entry in entries if entry.applies(role)]
        native = {entry.destination for entry in entries if entry.applies(role)
                  and entry.category != "C"}
        if len(applicable) != len(set(applicable)) or len(native) != count:
            problems.append(f"incorrect unique target set for {role}")
    return problems


class SourceFixture(ChezmoiFixture):
    """Complete candidate fixture; native_os overrides are supplemental evidence."""

    def __init__(self, host, native_os=None):
        super().__init__()
        self.host = host
        self.os_override = native_os

    def __enter__(self):
        super().__enter__()
        try:
            prepare_source(self, self.host)
        except BaseException:
            self._temporary.cleanup()
            raise
        return self

    def run(self, *args, input=None):
        if self.os_override is not None:
            args = ("--override-data", json.dumps({"chezmoi": {"os": self.os_override}}), *args)
        return super().run(*args, input=input)
