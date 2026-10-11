#!/bin/bash

set -euo pipefail

# Hermetic: the provisioning exports (DOTFILES_AUTO_UPDATE=0 and the like,
# docs/bootstrap.md) and other dotfiles knobs never reach the code under
# test from the caller; each case sets what it needs.
unset DOTFILES_AUTO_UPDATE DOTFILES_AUTO_STOW DOTFILES_HOST DOTFILES_DIR _DOTFILES_CHECKED \
    DOTFILES_STOW_WITHOUT_OH_MY_ZSH DOTFILES_COLOR AWESOME_SKILLS_AUTO_UPDATE AWESOME_SKILLS_FORCE \
    AWESOME_SKILLS_BG AWESOME_SKILLS_INSTALLER_URL AWESOME_SKILLS_REFRESH_DAYS _AWESOME_SKILLS_CHECKED

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
