#!/bin/bash

set -euo pipefail

# Run the PowerShell profile and prompt theme contract wherever pwsh exists.
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v pwsh >/dev/null 2>&1; then
    printf 'SKIP: PowerShell profile checks (pwsh unavailable).\n'
    exit 0
fi
exec pwsh -NoProfile -NonInteractive -File "$REPO_ROOT/tests/powershell-profile.ps1"
