#!/bin/bash

set -euo pipefail

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
    ai-config-sync.sh
    codex-config-sync.sh
    fcitx5-profile-sync.sh
    stow-all.sh
    update-hooks.sh
    awesome-skills-update.sh
    windows-installer.sh
)

for test_name in "${tests[@]}"; do
    printf '==> %s\n' "$test_name"
    "$TEST_DIR/$test_name"
done

echo "test-suite=PASS"
