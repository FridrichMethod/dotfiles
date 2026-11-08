"""Provision the pinned CI-only chezmoi test binary, outside behavioral tests."""

import hashlib
import io
import os
from pathlib import Path
import platform
import tarfile
import urllib.request
import zipfile


VERSION = "2.74.0"
# SHA256 from the official release checksum manifest, reviewed with this version.
ARTIFACTS = {
    ("Linux", "x86_64"): ("linux_amd64.tar.gz", "1b98a567f726f41540414aea4caf912699d53e248b29ccf8369cf553657b2374"),
    ("Darwin", "x86_64"): ("darwin_amd64.tar.gz", "3d30cb05efae2f4a68519d6d0e8856765f2b21a0686e66498ee6d2de7707e5e6"),
    ("Darwin", "arm64"): ("darwin_arm64.tar.gz", "9d89672a597a9333ab47ea5173fcececb85c04864205686a7aa5699c3d8bd98c"),
    ("Windows", "amd64"): ("windows_amd64.zip", "13dee2831d371c6ce2ac30fc9ae1aad4f70c68e7d44700f6129fe4b244ee7a95"),
}


def main():
    key = (platform.system(), platform.machine().lower())
    if key not in ARTIFACTS:
        raise SystemExit(f"Unsupported CI chezmoi test platform: {key}")
    artifact, digest = ARTIFACTS[key]
    name = f"chezmoi_{VERSION}_{artifact}"
    url = f"https://github.com/twpayne/chezmoi/releases/download/v{VERSION}/{name}"
    with urllib.request.urlopen(url, timeout=120) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != digest:
        raise SystemExit(f"SHA256 mismatch: {name}")
    executable = "chezmoi.exe" if key[0] == "Windows" else "chezmoi"
    if artifact.endswith(".zip"):
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            binary = archive.read(executable)
    else:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
            with archive.extractfile(executable) as member:
                binary = member.read()
    destination = Path(os.environ["RUNNER_TEMP"]) / "chezmoi-fixture-bin" / executable
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(binary)
    destination.chmod(0o755)
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
        output.write(f"DOTFILES_TEST_CHEZMOI={destination}\nDOTFILES_TEST_REQUIRE_CHEZMOI=1\n")
    print(f"Verified {name} SHA256 {digest}")


if __name__ == "__main__":
    main()
