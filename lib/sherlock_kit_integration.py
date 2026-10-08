"""Explicit pinned toolkit installation and offline instruction checks."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile

BEGIN = "<!-- SHERLOCK-KIT:BEGIN -->"
END = "<!-- SHERLOCK-KIT:END -->"
INSTRUCTIONS = ("common/claude/.claude/CLAUDE.md", "common/codex/.codex/AGENTS.md")
ADAPTER_TARGETS = {
    "claude/.claude-plugin/plugin.json": ".claude/plugins/sherlock-kit/.claude-plugin/plugin.json",
    "claude/skills/sherlock-kit-operate/SKILL.md": ".claude/plugins/sherlock-kit/skills/sherlock-kit-operate/SKILL.md",
    "codex/skills/sherlock-kit-operate/SKILL.md": ".codex/skills/sherlock-kit-operate/SKILL.md",
}


def run(argv, **kwargs):
    result = subprocess.run(argv, capture_output=True, text=True, **kwargs)
    if result.returncode:
        raise ValueError(f"{argv[0]} failed ({result.returncode}): {result.stderr.strip()}")
    return result.stdout


def write(path, data, mode=0o600):
    path = Path(path)
    if path.is_symlink():
        raise ValueError(f"refusing to write through symlink: {path}")
    if path.exists():
        mode &= path.stat().st_mode & 0o777
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        if os.name != "nt":
            os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def block(text, *, insertion=False):
    starts, ends = text.count(BEGIN), text.count(END)
    if starts == ends == 0 and insertion:
        return None
    if starts != 1 or ends != 1:
        raise ValueError("missing or duplicate SHERLOCK-KIT markers; first insertion requires --insert")
    if BEGIN not in text.splitlines() or END not in text.splitlines():
        raise ValueError("malformed SHERLOCK-KIT marker lines")
    start, end = text.index(BEGIN), text.index(END)
    if end <= start:
        raise ValueError("malformed SHERLOCK-KIT markers")
    return text[start:end + len(END)]


def validate_pin(pin):
    if type(pin.get("schema_version")) is not int or pin["schema_version"] != 1:
        raise ValueError("unsupported pin schema_version")
    for key, length in (("code_revision", 40), ("policy_sha256", 64), ("projection_sha256", 64)):
        if not isinstance(pin.get(key), str) or not re.fullmatch(f"[0-9a-f]{{{length}}}", pin[key]):
            raise ValueError(f"invalid pin {key}")
    projection = pin.get("projection")
    if not isinstance(projection, str) or block(projection) != projection.rstrip("\n"):
        raise ValueError("invalid pinned projection")
    if hashlib.sha256(projection.encode()).hexdigest() != pin["projection_sha256"]:
        raise ValueError("projection digest mismatch")
    provenance = f"<!-- source: SHERLOCK.md; schema_version: {pin['schema_version']}; policy_sha256: {pin['policy_sha256']} -->"
    if provenance not in projection.splitlines():
        raise ValueError("projection policy provenance mismatch")
    if not isinstance(pin.get("repository"), str) or not pin["repository"].startswith("https://"):
        raise ValueError("pin repository must be an HTTPS URL")
    return pin


def pin_read(root):
    return validate_pin(json.loads((root / "sherlock-kit.pin.json").read_text(encoding="utf-8")))


def check(root):
    pin = pin_read(root)
    for relative in INSTRUCTIONS:
        if block((root / relative).read_text(encoding="utf-8")) != pin["projection"].rstrip("\n"):
            raise ValueError(f"instruction projection mismatch: {relative}")
    return pin


def archive(source, revision, destination):
    archive_path = destination / "source.tar"
    with archive_path.open("wb") as handle:
        subprocess.run(["git", "-C", str(source), "archive", revision], stdout=handle, check=True)
    source_dir = destination / "source"
    source_dir.mkdir()
    with tarfile.open(archive_path) as handle:
        handle.extractall(source_dir, filter="data")
    return source_dir


def source_policy(source):
    # Import only the immutable Git archive, never a mutable or installed checkout.
    code = "import json,sys; sys.path.insert(0,sys.argv[1]); from sherlock_kit import policy_identity,policy_projection; print(json.dumps({'identity':policy_identity(),'projection':policy_projection()}))"
    return json.loads(run([sys.executable, "-I", "-B", "-c", code, str(source / "src")]))


def update(root, source, *, insert=False):
    revision = run(["git", "-C", str(source), "rev-parse", "HEAD"]).strip()
    with tempfile.TemporaryDirectory(prefix="shk-policy-") as temporary:
        exported = archive(source, revision, Path(temporary))
        payload = source_policy(exported)
    identity = payload["identity"]
    projection = payload["projection"]
    pin = {"repository": "https://github.com/FridrichMethod/sherlock-kit.git",
           "schema_version": identity["schema_version"], "code_revision": revision,
           "policy_sha256": identity["policy_sha256"],
           "projection_sha256": hashlib.sha256(projection.encode()).hexdigest(),
           "projection": projection}
    validate_pin(pin)
    candidates = []
    for relative in INSTRUCTIONS:
        path = root / relative
        if path.is_symlink():
            raise ValueError(f"refusing symlinked tracked instruction source: {path}")
        text = path.read_text(encoding="utf-8")
        previous = block(text, insertion=insert)
        candidates.append((path, text.rstrip("\n") + "\n\n" + projection.rstrip("\n") + "\n"
                           if previous is None else text.replace(previous, projection.rstrip("\n"))))
    if (root / "sherlock-kit.pin.json").is_symlink():
        raise ValueError("refusing symlinked tracked pin")
    for path, candidate in candidates:
        write(path, candidate, 0o644)
    write(root / "sherlock-kit.pin.json", json.dumps(pin, indent=2) + "\n", 0o644)
    check(root)


def python_at(venv):
    return venv / ("Scripts/python.exe" if os.name == "nt" else "bin/python")


def installed_identity(venv):
    return json.loads(run([str(python_at(venv)), "-I", "-c",
                          "import json; from sherlock_kit import policy_identity; print(json.dumps(policy_identity()))"]))


def adapter_bundle(runtime):
    code = """import json
from importlib import resources
from sherlock_kit import policy_identity
root = resources.files('sherlock_kit_data').joinpath('adapters')
files = {}
def walk(path, prefix=''):
    for child in path.iterdir():
        name = prefix + child.name
        if child.is_dir(): walk(child, name + '/')
        elif child.is_file(): files[name] = child.read_text(encoding='utf-8')
walk(root)
print(json.dumps({'identity':policy_identity(),'files':files}))
"""
    return json.loads(run([str(runtime), "-I", "-B", "-c", code]))


def install_adapters(root, home, runtime, *, check_only=False):
    """Copy first-party payloads from the frozen package; never register/trust hooks."""
    pin = check(root)
    payload = adapter_bundle(runtime)
    verify_identity(payload["identity"], pin)
    files = payload.get("files")
    if not isinstance(files, dict) or set(files) != set(ADAPTER_TARGETS):
        raise ValueError("unsupported or missing frozen adapter bundle; expected the three first-party payloads")
    if any(not isinstance(data, str) or not data for data in files.values()):
        raise ValueError("empty or invalid first-party adapter payload")
    plugin = json.loads(files["claude/.claude-plugin/plugin.json"])
    if not isinstance(plugin, dict) or plugin.get("name") != "sherlock-kit" or "hooks" in plugin:
        raise ValueError("Claude adapter must be namespaced and contain no hook registrations")
    candidates = []
    for relative, target in ADAPTER_TARGETS.items():
        data = files[relative]
        path = home / target
        if path.is_symlink() or any(parent.is_symlink() for parent in path.parents):
            raise ValueError(f"refusing symlinked adapter target: {path}")
        if path.exists() and (not path.is_file() or path.read_text(encoding="utf-8") != data):
            raise ValueError(f"adapter target differs; review local content before explicit replacement: {path}")
        candidates.append((path, data))
    # A changed/untrusted hook remains inactive: this installer owns only payloads.
    if not check_only:
        for path, data in candidates:
            if not path.exists():
                write(path, data)
    print("First-party adapters validated; hook registration/trust remains inactive" if check_only else
          "First-party adapters copied; hook registration/trust remains inactive")


def verify_identity(identity, pin):
    if identity.get("install_mode") != "frozen" or any(identity.get(key) != pin[key]
            for key in ("schema_version", "code_revision", "policy_sha256")):
        raise ValueError("installed toolkit identity does not match advertised pin; rerun explicit setup")


def validate_state_root(value):
    """Validate a locator without creating or resolving its destination."""
    if not isinstance(value, (str, Path)):
        raise ValueError("state_root must be an absolute directory path")
    text = str(value)
    if not text or any(ord(char) < 32 or ord(char) == 127 for char in text):
        raise ValueError("state_root contains invalid path characters")
    path = Path(text)
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError("state_root must be absolute without parent traversal")
    if os.name == "nt" and any(re.search(r'[<>:"|?*]', part) or part.endswith((".", " "))
                              or re.fullmatch(r"(?i)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?", part)
                              for part in path.parts[1:]):
        raise ValueError("state_root contains invalid Windows path components")
    if path.is_symlink() or any(parent.is_symlink() for parent in path.parents):
        raise ValueError("refusing symlinked state_root")
    if any(component.exists() and not component.is_dir() for component in (path, *path.parents)):
        raise ValueError("state_root must identify a directory")
    return text


def active_read(install_root):
    path = install_root / "active.json"
    if path.is_symlink():
        raise ValueError("refusing symlinked active toolkit pointer")
    active = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    if not isinstance(active, dict):
        raise ValueError("invalid active toolkit pointer")
    if "state_root" in active:
        validate_state_root(active["state_root"])
    return active


def install(root, home, source=None, *, state_root=None):
    pin = check(root)
    install_root = home / ".local/share/sherlock-kit"
    versions = install_root / "revisions"
    for path in (home / ".local", home / ".local/share", install_root, versions):
        if path.is_symlink():
            raise ValueError(f"refusing symlinked installation path: {path}")
    if state_root is not None:
        state_root = validate_state_root(state_root)
    active_read(install_root)
    versions.mkdir(parents=True, exist_ok=True)
    if os.name != "nt":
        install_root.chmod(install_root.stat().st_mode & 0o700)
        versions.chmod(versions.stat().st_mode & 0o700)
    lock = install_root / ".setup.lock"
    try:
        lock.mkdir(mode=0o700)
    except FileExistsError:
        raise ValueError(f"setup already running or interrupted; inspect exact lock: {lock}") from None
    try:
        install_locked(root, home, source, pin, install_root, versions, state_root)
    finally:
        lock.rmdir()


def install_locked(root, home, source, pin, install_root, versions, state_root=None):
    # Read under the setup lock so an upgrade preserves the current locator.
    active = active_read(install_root)
    if state_root is None:
        state_root = active.get("state_root")
    revision_path = versions / pin["code_revision"]
    if revision_path.is_symlink():
        raise ValueError("refusing symlinked revision environment")
    if revision_path.exists():
        verify_identity(installed_identity(revision_path), pin)
    else:
        # Keep venv at its final path: console-script shebangs cannot survive a rename.
        with tempfile.TemporaryDirectory(prefix="shk-install-") as temporary:
            temporary = Path(temporary)
            if source is None:
                source = temporary / "checkout"
                run(["git", "clone", "--no-checkout", pin["repository"], str(source)])
            run(["git", "-C", str(source), "cat-file", "-e", pin["code_revision"] + "^{commit}"])
            exported = archive(source, pin["code_revision"], temporary)
            # Build backend records the immutable revision supplied from git archive.
            build_environment = dict(os.environ, SHERLOCK_KIT_BUILD_REVISION=pin["code_revision"])
            run([sys.executable, "-I", "-m", "venv", str(revision_path)])
            try:
                run([str(python_at(revision_path)), "-I", "-m", "pip", "install", "--disable-pip-version-check",
                     "--no-deps", str(exported)], env=build_environment)
                verify_identity(installed_identity(revision_path), pin)
            except Exception:
                # Retain the failed exact directory for inspection; no active pointer changes.
                raise ValueError(f"installation failed; inactive environment retained at {revision_path}")
    if os.name == "nt":
        # No Stow target competes with this native command wrapper.
        launcher = home / ".local/bin/shk.cmd"
        write(launcher, f'@"{sys.executable}" "{root / "common/codex/.local/bin/shk"}" %*\n')
    active = {"revision": pin["code_revision"]}
    if state_root is not None:
        active["state_root"] = state_root
    write(install_root / "active.json", json.dumps(active) + "\n")
    print(f"Installed frozen sherlock-kit {pin['code_revision']} at {revision_path}")


def launch(root, arguments):
    pin = check(root)
    install_root = Path.home() / ".local/share/sherlock-kit"
    active = active_read(install_root)
    revision = active.get("revision", "")
    if not isinstance(revision, str) or not re.fullmatch("[0-9a-f]{40}", revision):
        raise ValueError("invalid active toolkit revision")
    venv = install_root / "revisions" / revision
    identity = installed_identity(venv)
    # Keep diagnostics and recovery available during instruction/executable upgrade gaps.
    try:
        verify_identity(identity, pin)
    except ValueError as exc:
        print(f"shk: {exc}", file=sys.stderr)
    os.environ["SHERLOCK_KIT_PIN"] = str(root / "sherlock-kit.pin.json")
    os.environ["SHERLOCK_KIT_CLAUDE_INSTRUCTIONS"] = str(Path.home() / ".claude/CLAUDE.md")
    os.environ["SHERLOCK_KIT_CODEX_INSTRUCTIONS"] = str(Path.home() / ".codex/AGENTS.md")
    if "state_root" in active:
        os.environ.setdefault("SHERLOCK_KIT_STATE_ROOT", active["state_root"])
    os.execv(str(python_at(venv)), [str(python_at(venv)), "-I", "-m", "sherlock_kit", *arguments])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    choices = parser.add_mutually_exclusive_group(required=True)
    choices.add_argument("--check", action="store_true")
    choices.add_argument("--update-projection", action="store_true")
    choices.add_argument("--install", action="store_true")
    choices.add_argument("--install-adapters", action="store_true")
    parser.add_argument("--source", type=Path)
    parser.add_argument("--state-root", help="absolute local state directory locator; setup does not create it")
    parser.add_argument("--insert", action="store_true")
    parser.add_argument("--target-home", type=Path, default=Path.home())
    parser.add_argument("--runtime", type=Path, help="explicit frozen interpreter for adapter delivery")
    parser.add_argument("--check-adapters", action="store_true", help="read-only adapter preflight with --install-adapters")
    args = parser.parse_args(argv)
    try:
        if sys.version_info < (3, 11):
            raise ValueError("Python 3.11 or newer is required")
        if args.insert and not args.update_projection:
            raise ValueError("--insert requires --update-projection")
        if args.check_adapters and not args.install_adapters:
            raise ValueError("--check-adapters requires --install-adapters")
        if args.state_root is not None and not args.install:
            raise ValueError("--state-root requires --install")
        if args.update_projection:
            if args.source is None:
                raise ValueError("--update-projection requires --source")
            update(args.root, args.source, insert=args.insert)
        elif args.install:
            install(args.root, args.target_home.absolute(), args.source, state_root=args.state_root)
        elif args.install_adapters:
            if args.runtime is None:
                raise ValueError("--install-adapters requires --runtime pointing to the frozen package interpreter")
            install_adapters(args.root, args.target_home.absolute(), args.runtime, check_only=args.check_adapters)
        else:
            check(args.root)
        print("sherlock-kit pin/projection: valid")
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"sherlock-kit: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
