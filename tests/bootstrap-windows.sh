#!/bin/bash

set -euo pipefail

# Run the Windows bootstrap suite (tests/bootstrap.ps1: lib/bootstrap.ps1,
# doctor.ps1 and setup-host.ps1 against fixtures and shims) wherever pwsh
# exists. It is portable, so Linux and macOS runners exercise it too.
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v pwsh >/dev/null 2>&1; then
    printf 'SKIP: Windows bootstrap checks (pwsh unavailable).\n'
    exit 0
fi
pwsh -NoProfile -NonInteractive -File "$REPO_ROOT/tests/bootstrap.ps1"
echo "bootstrap-windows=PASS"
