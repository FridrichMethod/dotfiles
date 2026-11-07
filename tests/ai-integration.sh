#!/bin/bash

set -euo pipefail

# Isolate inherited configuration while preserving explicit test inputs.
# shellcheck source=tests/lib/environment.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/environment.sh"

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "$TEST_DIR/test_ai_integration.py" ]]; then
    echo 'ERROR: required AI integration test suite is missing.' >&2
    exit 1
fi
# test_ai_integration.py is standard-library only, so a plain python3 runs it.
command -v python3 >/dev/null 2>&1 || {
    echo 'ERROR: python3 is required for the AI integration tests.' >&2
    exit 1
}
# The cases that run the kit need DOTFILES_TEST_KIT_HOME, a home with an
# installed coding-agent-kit (CI installs the real one), and skip without it.
if [[ -z "${DOTFILES_TEST_KIT_HOME:-}" ]]; then
    printf 'SKIP: installed coding-agent-kit cases (set DOTFILES_TEST_KIT_HOME to enable).\n'
fi
# The settings.json cases run the Claude helpers with node and skip without
# it; this entry point fails instead.
command -v node >/dev/null 2>&1 || {
    echo 'ERROR: node not found; the settings.json cases of the Claude helpers need it.' >&2
    exit 1
}

python3 -I -B -m unittest discover -s "$TEST_DIR" -p 'test_ai_integration.py' -v
echo "ai-integration=PASS"
