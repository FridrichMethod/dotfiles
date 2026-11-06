#!/bin/bash

set -euo pipefail

# Isolate inherited configuration while preserving explicit test inputs.
# shellcheck source=tests/lib/environment.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/environment.sh"

# Portable AI policy and agent-instruction invariants, with stdlib Python only:
# no chezmoi and no sync runtime. Installed Codex adds exec-policy probes.
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "$TEST_DIR/test_ai_policy.py" ]]; then
    echo 'ERROR: required AI policy test suite is missing.' >&2
    exit 1
fi
python3 -I -B -m unittest discover -s "$TEST_DIR" -p 'test_ai_policy.py' -v
echo "ai-policy=PASS"
