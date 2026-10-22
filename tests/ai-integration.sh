#!/bin/bash

set -euo pipefail

# Hermetic: the provisioning exports (DOTFILES_AUTO_UPDATE=0 and the like,
# docs/bootstrap.md) and other dotfiles knobs never reach the code under
# test from the caller; each case sets what it needs.
unset DOTFILES_AUTO_UPDATE DOTFILES_AUTO_STOW DOTFILES_HOST DOTFILES_DIR _DOTFILES_CHECKED \
    DOTFILES_STOW_WITHOUT_OH_MY_ZSH DOTFILES_COLOR AWESOME_SKILLS_AUTO_UPDATE AWESOME_SKILLS_FORCE \
    AWESOME_SKILLS_BG AWESOME_SKILLS_INSTALLER_URL AWESOME_SKILLS_REFRESH_DAYS _AWESOME_SKILLS_CHECKED \
    CODING_AGENT_KIT_CONFIG CODING_AGENT_KIT_COLOR CODING_AGENT_KIT_USAGE_FILE CODING_AGENT_KIT_TOKEN_ID CODING_AGENT_KIT_CLAUDE_PID XDG_STATE_HOME

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
if [[ ! -f "$TEST_DIR/test_ai_integration.py" ]]; then
    echo 'ERROR: required AI integration test suite is missing.' >&2
    exit 1
fi
sync_python=${DOTFILES_SYNC_PYTHON:-$TEST_DIR/../.venv-sync/bin/python}
if [[ ! -x "$sync_python" ]]; then
    echo 'ERROR: AI-sync runtime missing; run ./setup-sync.sh explicitly.' >&2
    exit 1
fi
# The launchers and Claude helpers are links of the coding-agent-kit package
# into its submodule.
[[ -f "$REPO_ROOT/common/coding-agent-kit/.local/bin/codex-as" && -f "$REPO_ROOT/common/coding-agent-kit/.claude/dotfiles/statusline.cjs" ]] || {
    echo 'ERROR: coding-agent-kit submodule not initialized; run git submodule update --init --recursive.' >&2
    exit 1
}
# The settings.json cases run the Claude helpers with node and skip without
# it; this entry point, which the bump Action runs as gate 4, fails instead.
command -v node >/dev/null 2>&1 || {
    echo 'ERROR: node not found; the settings.json cases of the Claude helpers need it.' >&2
    exit 1
}
export DOTFILES_SYNC_PYTHON="$sync_python"

"$sync_python" -I -B -m unittest discover -s "$TEST_DIR" -p 'test_ai_integration.py' -v
echo "ai-integration=PASS"
