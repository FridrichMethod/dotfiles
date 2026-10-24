#!/bin/bash

set -euo pipefail

# Hermetic: the provisioning exports (DOTFILES_AUTO_UPDATE=0 and the like,
# docs/bootstrap.md) and other dotfiles knobs never reach the code under
# test from the caller; each case sets what it needs.
unset DOTFILES_AUTO_UPDATE DOTFILES_AUTO_STOW DOTFILES_HOST DOTFILES_DIR _DOTFILES_CHECKED \
    DOTFILES_STOW_WITHOUT_OH_MY_ZSH DOTFILES_COLOR DOTFILES_PAYLOAD_AUTO_UPDATE DOTFILES_PAYLOAD_ITEMS \
    DOTFILES_PAYLOAD_TIMEOUT AWESOME_SKILLS_AUTO_UPDATE \
    _DOTFILES_PAYLOAD_CHECKED CODING_AGENT_KIT_CONFIG CODING_AGENT_KIT_COLOR CODING_AGENT_KIT_USAGE_FILE \
    CODING_AGENT_KIT_TOKEN_ID CODING_AGENT_KIT_CLAUDE_PID CODING_AGENT_KIT_REPO_URL XDG_STATE_HOME XDG_DATA_HOME

# Run the PowerShell profile and prompt theme contract wherever pwsh exists.
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v pwsh >/dev/null 2>&1; then
    printf 'SKIP: PowerShell profile checks (pwsh unavailable).\n'
    exit 0
fi
exec pwsh -NoProfile -NonInteractive -File "$REPO_ROOT/tests/powershell-profile.ps1"
