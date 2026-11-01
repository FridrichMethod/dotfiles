#!/bin/bash

set -euo pipefail

# Isolate inherited configuration while preserving explicit test inputs.
# shellcheck source=tests/lib/environment.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/environment.sh"

# Run the unit test of the native Windows end-to-end driver
# (tests/e2e-harness.ps1: tests/e2e/run.ps1 and tests/e2e/lib/*.ps1 against
# stubs) wherever pwsh exists. It is portable, so Linux and macOS runners
# exercise it too; the real driver runs only in the opt-in bootstrap-e2e job.
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v pwsh >/dev/null 2>&1; then
    printf 'SKIP: Windows end-to-end driver checks (pwsh unavailable).\n'
    exit 0
fi
pwsh -NoProfile -NonInteractive -File "$REPO_ROOT/tests/e2e-harness.ps1"
echo "e2e-harness-windows=PASS"
