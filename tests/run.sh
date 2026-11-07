#!/bin/bash

set -euo pipefail

# Isolate inherited configuration while preserving explicit test inputs.
# shellcheck source=tests/lib/environment.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/environment.sh"

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
            printf 'CI mode requires chezmoi for the native fixtures; local optional skips are reported.\n'
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
# The suites import stdlib tomllib; AGENTS.md sets the Python 3.11+ floor.
if command -v python3 >/dev/null 2>&1 &&
    ! python3 -I -B -c 'import sys; sys.exit(sys.version_info < (3, 11))' >/dev/null 2>&1; then
    printf 'ERROR: required test dependency python3 is not Python 3.11 or newer.\n' >&2
    missing=1
fi
if [[ ${DOTFILES_TEST_CHEZMOI+x} == x ]]; then
    if [[ ! -f "$DOTFILES_TEST_CHEZMOI" || ! -x "$DOTFILES_TEST_CHEZMOI" ]]; then
        printf 'ERROR: invalid DOTFILES_TEST_CHEZMOI executable path.\n' >&2
        missing=1
    fi
elif ! command -v chezmoi >/dev/null 2>&1; then
    if [[ "$require_ci" == 1 || ${DOTFILES_TEST_REQUIRE_CHEZMOI:-0} == 1 ]]; then
        printf 'ERROR: CI requires chezmoi for native fixture tests.\n' >&2
        missing=1
    else
        printf 'SKIP: native chezmoi fixtures (install the selected release or set DOTFILES_TEST_CHEZMOI).\n'
    fi
fi
if [[ "$require_ci" == 1 ]]; then
    export DOTFILES_TEST_REQUIRE_CHEZMOI=1
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
    markdown-links.sh
    chezmoi.sh
    terminal.sh
    shell-profile.sh
    tmux.sh
    ai-policy.sh
    ai-integration.sh
    powershell-profile.sh
    payload-update.sh
    bootstrap-manifest.sh
    doctor.sh
    setup-host.sh
    bootstrap-windows.sh
    host-overlays.sh
    e2e-harness.sh
    e2e-harness-windows.sh
)

for test_name in "${tests[@]}"; do
    printf '==> %s\n' "$test_name"
    "$TEST_DIR/$test_name"
done

echo "test-suite=PASS"
