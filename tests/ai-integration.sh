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
sync_python=${DOTFILES_SYNC_PYTHON:-$TEST_DIR/../.venv-sync/bin/python}
if [[ ! -x "$sync_python" ]]; then
    echo 'ERROR: AI-sync runtime missing; run ./setup-sync.sh explicitly.' >&2
    exit 1
fi
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
export DOTFILES_SYNC_PYTHON="$sync_python"

"$sync_python" -I -B -m unittest discover -s "$TEST_DIR" -p 'test_ai_integration.py' -v
echo "ai-integration=PASS"
