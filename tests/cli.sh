#!/bin/bash

set -euo pipefail

# Isolate inherited configuration while preserving explicit test inputs.
# shellcheck source=tests/lib/environment.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/environment.sh"

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
python3 -I -B "$TEST_DIR/test_cli_unix.py"

if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -NonInteractive -File "$TEST_DIR/cli.ps1"
else
    printf 'SKIP: optional PowerShell CLI checks (mandatory in the native Windows job).\n'
fi
