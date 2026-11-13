"""Expected targets (tests/fixtures/chezmoi/targets.tsv), independent of source templates."""

import json
from dataclasses import dataclass
import os
from pathlib import Path
import shutil
import subprocess

from chezmoi_support import ChezmoiFixture


ROOT = Path(__file__).resolve().parents[1]
ROLES = ("generic", "mac", "wsl-ubuntu", "lab-ubuntu", "sherlock", "marlowe", "win")
COUNTS = dict(zip(ROLES, (50, 57, 56, 59, 55, 55, 27)))
AI_MUTABLE = {".claude/settings.json", ".codex/config.toml"}
TARGETS = ROOT / "tests/fixtures/chezmoi/targets.tsv"
HEADER = ["target", "hosts", "source", "mode", "shell"]
MODES = {"regular", "executable", "private"}
SHELLS = {"-", "sh", "bash", "zsh"}
# Source inputs that are never targets: role variants and portable AI policy.
HIDDEN_INPUTS = ("home/.hosts/", "home/.policy/")


@dataclass(frozen=True)
class Entry:
    destination: str
    hosts: frozenset
    source: str  # canonical bytes, relative to the repository root, for one role
    mode: str
    shell: str

    def applies(self, role):
        return role in self.hosts


def role_set(hosts):
    if hosts == "all":
        return frozenset(ROLES)
    if hosts == "unix":
        return frozenset(ROLES) - {"win"}
    roles = hosts.split(",")
    if not roles or any(role not in ROLES for role in roles) or len(set(roles)) != len(roles):
        raise ValueError(f"invalid hosts cell: {hosts!r}")
    return frozenset(roles)


def target_rows():
    """(destination, hosts, source pattern, mode, shell) rows, validated for shape."""
    lines = [line.rstrip("\n") for line in TARGETS.read_text(encoding="ascii").splitlines()
             if line.strip() and not line.startswith("#")]
    if not lines or lines[0].split("\t") != HEADER:
        raise ValueError(f"{TARGETS.name} must start with the header {HEADER}")
    rows = []
    for line in lines[1:]:
        cells = line.split("\t")
        if len(cells) != len(HEADER) or cells[3] not in MODES or cells[4] not in SHELLS:
            raise ValueError(f"malformed target row: {line!r}")
        rows.append((cells[0], role_set(cells[1]), cells[2], cells[3], cells[4]))
    return rows


def expected_entries(role):
    return {destination: Entry(destination, hosts, source.replace("{host}", role), mode, shell)
            for destination, hosts, source, mode, shell in target_rows() if role in hosts}


def fixture_git_env(env=None):
    # Never inherit a caller's repository, index, hooks or global configuration.
    clean = {key: value for key, value in (os.environ if env is None else env).items()
             if not key.upper().startswith("GIT_")}
    clean.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
    return clean


def tracked_home():
    """{path: git mode} of every tracked path under home/."""
    git = shutil.which("git")
    if git is None:
        raise RuntimeError("git prerequisite: target verification requires git")
    result = subprocess.run([git, "ls-files", "--stage", "-z", "--", "home"],
                            cwd=ROOT, env=fixture_git_env(), check=True,
                            capture_output=True, timeout=30)
    modes = {}
    for record in result.stdout.decode("utf-8").split("\0"):
        if record:
            metadata, path = record.split("\t", 1)
            mode, _oid, stage = metadata.split()
            if stage != "0":
                raise AssertionError(f"Unmerged source path: {path}")
            modes[path] = mode
    return modes


def target_problems(rows, tracked):
    problems = []
    destinations = [row[0] for row in rows]
    if len(destinations) != len(set(destinations)):
        problems.append("a target is listed twice")
    readers = {}
    for destination, hosts, source, _mode, _shell in rows:
        variant = "{host}" in source
        if variant != source.startswith("home/.hosts/{host}/") or (variant and "generic" in hosts):
            problems.append(f"{destination}: only an overlay role list may read home/.hosts/{{host}}/")
        for role in sorted(hosts):
            resolved = source.replace("{host}", role)
            if resolved not in tracked:
                problems.append(f"{destination}: {resolved} is not a tracked source for {role}")
            readers.setdefault(resolved, set()).add(destination)
    for path in tracked:
        if path.startswith(HIDDEN_INPUTS) and len(readers.get(path, ())) != 1:
            problems.append(f"{path} must be the source of exactly one target")
    for directory in {path.split("/")[2] for path in tracked if path.startswith("home/.hosts/")}:
        if directory not in ROLES[1:]:
            problems.append(f"home/.hosts/{directory}/ is not a role with an overlay")
    for role, count in COUNTS.items():
        if sum(role in row[1] for row in rows) != count:
            problems.append(f"incorrect target count for {role}")
    return problems


def copy_controls(destination):
    # home/ includes the never-deployed inputs under .hosts/ and .policy/.
    for name in (".chezmoiroot", ".chezmoiversion"):
        shutil.copyfile(ROOT / name, destination / name)
    shutil.copytree(ROOT / "home", destination / "home")


def prepare_source(fixture, role):
    copy_controls(fixture.source)
    fixture.config.write_text(f'[data]\nhost = "{role}"\n', encoding="utf-8")


def snapshot(directory):
    return {path.relative_to(directory).as_posix(): (path.read_bytes(), path.stat().st_mode & 0o777)
            for path in directory.rglob("*") if path.is_file()}


class SourceFixture(ChezmoiFixture):
    """Complete candidate fixture; OS overrides are supplemental evidence."""

    def __init__(self, host, os_override=None):
        super().__init__()
        self.host = host
        self.os_override = os_override

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
