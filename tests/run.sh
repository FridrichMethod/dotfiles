#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

node --test "$TEST_DIR/claude-customizations.cjs"

tests=(
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
