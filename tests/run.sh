#!/bin/bash

set -euo pipefail

# Hermetic: the provisioning exports (DOTFILES_AUTO_UPDATE=0 and the like,
# docs/bootstrap.md) and other dotfiles knobs never reach the code under
# test from the caller; each case sets what it needs.
unset DOTFILES_AUTO_UPDATE DOTFILES_AUTO_STOW DOTFILES_HOST DOTFILES_DIR _DOTFILES_CHECKED \
    DOTFILES_STOW_WITHOUT_OH_MY_ZSH DOTFILES_COLOR AWESOME_SKILLS_AUTO_UPDATE AWESOME_SKILLS_FORCE \
    AWESOME_SKILLS_BG AWESOME_SKILLS_INSTALLER_URL AWESOME_SKILLS_REFRESH_DAYS _AWESOME_SKILLS_CHECKED

# GitHub's runners start jobs with SIGPIPE ignored, so a writer into a pipe
# whose reader stopped early prints "write error: Broken pipe" there instead
# of dying quietly. Ignore it here too, so local runs see what CI sees.
trap '' PIPE

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

require_ci=0
prerequisites_only=0
for argument in "$@"; do
    case "$argument" in
        --ci) require_ci=1 ;;
        --check-prerequisites) prerequisites_only=1 ;;
        --help)
            printf 'Usage: %s [--ci] [--check-prerequisites]\n' "$0"
            printf 'CI mode requires Stow integration; local optional skips are reported.\n'
            exit 0
            ;;
        *)
            printf 'ERROR: unknown test option: %s\n' "$argument" >&2
            exit 2
            ;;
    esac
done

missing=0
for dependency in bash sh git python3 node; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        printf 'ERROR: required test dependency not found: %s\n' "$dependency" >&2
        missing=1
    fi
done
sync_python=${DOTFILES_SYNC_PYTHON:-$TEST_DIR/../.venv-sync/bin/python}
if [[ ! -x "$sync_python" ]]; then
    printf 'ERROR: AI-sync runtime missing; run ./setup-sync.sh explicitly.\n' >&2
    missing=1
elif ! "$sync_python" -I -B "$TEST_DIR/../lib/config_sync.py" --runtime-check; then
    missing=1
fi
export DOTFILES_SYNC_PYTHON="$sync_python"
if ! command -v stow >/dev/null 2>&1; then
    if [[ "$require_ci" == 1 ]]; then
        printf 'ERROR: CI requires stow for real symlink integration tests.\n' >&2
        missing=1
    else
        printf 'SKIP: real GNU Stow integration (install stow to enable).\n'
    fi
fi
if ! command -v pwsh >/dev/null 2>&1; then
    printf 'SKIP: optional Unix PowerShell checks (mandatory in the native Windows job).\n'
fi
if ! command -v codex >/dev/null 2>&1; then
    printf 'SKIP: optional installed-Codex exec-policy checks.\n'
fi
[[ "$missing" == 0 ]] || exit 1
if [[ "$prerequisites_only" == 1 ]]; then
    printf 'test-prerequisites=PASS\n'
    exit 0
fi

node --test "$TEST_DIR/claude-customizations.cjs"

tests=(
    test-entrypoints.sh
    terminal.sh
    shell-profile.sh
    config-sync.sh
    sherlock-kit.sh
    ai-config-sync.sh
    codex-config-sync.sh
    fcitx5-profile-sync.sh
    stow-all.sh
    update-hooks.sh
    powershell-profile.sh
    awesome-skills-update.sh
    windows-installer.sh
    bootstrap-manifest.sh
    doctor.sh
    setup-host.sh
    bootstrap-windows.sh
    host-overlays.sh
)

for test_name in "${tests[@]}"; do
    printf '==> %s\n' "$test_name"
    "$TEST_DIR/$test_name"
done

if command -v stow >/dev/null 2>&1; then
    printf '==> unix-installer.sh\n'
    "$TEST_DIR/unix-installer.sh"
fi

echo "test-suite=PASS"
