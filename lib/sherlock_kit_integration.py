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


def verify_identity(identity, pin):
    if identity.get("install_mode") != "frozen" or any(identity.get(key) != pin[key]
            for key in ("schema_version", "code_revision", "policy_sha256")):
        raise ValueError("installed toolkit identity does not match advertised pin; rerun explicit setup")


def install(root, home, source=None):
    pin = check(root)
    install_root = home / ".local/share/sherlock-kit"
    versions = install_root / "revisions"
    for path in (home / ".local", home / ".local/share", install_root, versions):
        if path.is_symlink():
            raise ValueError(f"refusing symlinked installation path: {path}")
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
        install_locked(root, home, source, pin, install_root, versions)
    finally:
        lock.rmdir()


def install_locked(root, home, source, pin, install_root, versions):
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
    write(install_root / "active.json", json.dumps({"revision": pin["code_revision"]}) + "\n")
    print(f"Installed frozen sherlock-kit {pin['code_revision']} at {revision_path}")


def launch(root, arguments):
    pin = check(root)
    install_root = Path.home() / ".local/share/sherlock-kit"
    active = json.loads((install_root / "active.json").read_text(encoding="utf-8"))
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
    os.execv(str(python_at(venv)), [str(python_at(venv)), "-I", "-m", "sherlock_kit", *arguments])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    choices = parser.add_mutually_exclusive_group(required=True)
    choices.add_argument("--check", action="store_true")
    choices.add_argument("--update-projection", action="store_true")
    choices.add_argument("--install", action="store_true")
    parser.add_argument("--source", type=Path)
    parser.add_argument("--insert", action="store_true")
    parser.add_argument("--target-home", type=Path, default=Path.home())
    args = parser.parse_args(argv)
    try:
        if sys.version_info < (3, 11):
            raise ValueError("Python 3.11 or newer is required")
        if args.insert and not args.update_projection:
            raise ValueError("--insert requires --update-projection")
        if args.update_projection:
            if args.source is None:
                raise ValueError("--update-projection requires --source")
            update(args.root, args.source, insert=args.insert)
        elif args.install:
            install(args.root, args.target_home.absolute(), args.source)
        else:
            check(args.root)
        print("sherlock-kit pin/projection: valid")
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"sherlock-kit: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
