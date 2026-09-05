#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-real-install.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM
FIXTURE="$TEST_TMP/checkout with spaces"
TARGET="$TEST_TMP/home with spaces"
SYNC_PYTHON="${DOTFILES_SYNC_PYTHON:-$REPO_ROOT/.venv-sync/bin/python}"
export DOTFILES_SYNC_PYTHON="$SYNC_PYTHON"
# An inherited Git override must never redirect fixture writes to a caller's
# real index/object database or import hooks from a custom template directory.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_COUNT \
    GIT_CONFIG_PARAMETERS GIT_SHALLOW_FILE GIT_REPLACE_REF_BASE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_TEMPLATE_DIR="$TEST_TMP/empty-template"
export GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.invalid

for dependency in git stow python3; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        echo "ERROR: unix-installer requires $dependency" >&2
        exit 1
    fi
done

mkdir -p "$FIXTURE/common" "$FIXTURE/lib" "$TARGET" "$FIXTURE/test-host/sample" "$GIT_TEMPLATE_DIR"
cp "$REPO_ROOT/stow-all.sh" "$REPO_ROOT/dotfiles-update.sh" "$REPO_ROOT/.stowrc" "$FIXTURE/"
cp "$REPO_ROOT/lib/config_sync.py" "$REPO_ROOT/lib/sync-runtime.sh" "$FIXTURE/lib/"
cp -R "$REPO_ROOT/common/codex" "$REPO_ROOT/common/claude" "$FIXTURE/common/"
printf '%s\n' 'host overlay fixture' >"$FIXTURE/test-host/sample/.fixture-host"
git init -q -b main "$FIXTURE"
git -C "$FIXTURE" add common lib test-host stow-all.sh dotfiles-update.sh .stowrc
git -C "$FIXTURE" commit -qm 'Fixture baseline'

run_install() {
    if ! env HOME="$TARGET" bash "$FIXTURE/stow-all.sh" test-host >"$TEST_TMP/install.log" 2>&1; then
        cat "$TEST_TMP/install.log" >&2
        return 1
    fi
}

run_install
[[ -L "$TARGET/.fixture-host" ]]
[[ -L "$TARGET/.local/bin/codex-config-sync" ]]
[[ -f "$TARGET/.codex/config.toml" && ! -L "$TARGET/.codex/config.toml" ]]
[[ -f "$TARGET/.claude/settings.json" && ! -L "$TARGET/.claude/settings.json" ]]
[[ -f "$TARGET/.codex/rules/portable.rules" && ! -L "$TARGET/.codex/rules/portable.rules" ]]
[[ -z "$(git -C "$FIXTURE" status --porcelain)" ]]
STATE="$FIXTURE/.git/dotfiles-sync-unix"
printf '%s\n' "$TARGET" "$(uname -s)" test-host "$(git -C "$FIXTURE" rev-parse HEAD)" >"$TEST_TMP/expected-state"
cmp "$STATE" "$TEST_TMP/expected-state"
cp "$TARGET/.codex/config.toml" "$TEST_TMP/codex-before"
cp "$TARGET/.claude/settings.json" "$TEST_TMP/claude-before"
run_install
cmp "$STATE" "$TEST_TMP/expected-state"
cmp "$TARGET/.codex/config.toml" "$TEST_TMP/codex-before"
cmp "$TARGET/.claude/settings.json" "$TEST_TMP/claude-before"
# Execute the real installed wrapper through a spaced target/repository path.
"$TARGET/.local/bin/codex-config-sync" --check \
    "$FIXTURE/common/codex/.codex/config.toml" "$TARGET/.codex/config.toml"

# Exercise the full local-remote -> pull -> real Stow -> acknowledgement path.
git clone -q --bare "$FIXTURE" "$TEST_TMP/remote.git"
git -C "$FIXTURE" remote add origin "$TEST_TMP/remote.git"
git -C "$FIXTURE" fetch -q origin
git -C "$FIXTURE" branch --set-upstream-to=origin/main main >/dev/null
git clone -q "$TEST_TMP/remote.git" "$TEST_TMP/upstream"
printf '%s\n' 'delivered by automatic stow' >"$TEST_TMP/upstream/test-host/sample/.fixture-new"
git -C "$TEST_TMP/upstream" add test-host/sample/.fixture-new
git -C "$TEST_TMP/upstream" commit -qm 'Fixture update'
git -C "$TEST_TMP/upstream" push -q origin main
if ! env -u _DOTFILES_CHECKED HOME="$TARGET" DOTFILES_DIR="$FIXTURE" \
    DOTFILES_AUTO_UPDATE=1 DOTFILES_AUTO_STOW=1 DOTFILES_HOST=test-host \
    bash --noprofile --norc -ic '. "$DOTFILES_DIR/dotfiles-update.sh"' \
    >"$TEST_TMP/update.log" 2>&1; then
    cat "$TEST_TMP/update.log" >&2
    exit 1
fi
[[ -L "$TARGET/.fixture-new" ]]
grep -Fxq 'delivered by automatic stow' "$TARGET/.fixture-new"
printf '%s\n' "$TARGET" "$(uname -s)" test-host "$(git -C "$FIXTURE" rev-parse HEAD)" >"$TEST_TMP/expected-state"
cmp "$STATE" "$TEST_TMP/expected-state"
[[ -z "$(git -C "$FIXTURE" status --porcelain)" ]]

# A malformed final baseline fails preflight before any earlier sync writes.
printf '%s\n' '{invalid JSON' >"$FIXTURE/common/claude/.claude/settings.json"
if env HOME="$TARGET" bash "$FIXTURE/stow-all.sh" test-host >"$TEST_TMP/invalid.log" 2>&1; then
    echo 'ERROR: malformed Claude baseline passed installer preflight' >&2
    exit 1
fi
cmp "$STATE" "$TEST_TMP/expected-state"
cmp "$TARGET/.codex/config.toml" "$TEST_TMP/codex-before"
cmp "$TARGET/.claude/settings.json" "$TEST_TMP/claude-before"
cp "$REPO_ROOT/common/claude/.claude/settings.json" "$FIXTURE/common/claude/.claude/settings.json"
if env HOME="$TARGET" DOTFILES_SYNC_PYTHON="$TEST_TMP/no-python" \
    bash "$FIXTURE/stow-all.sh" test-host >"$TEST_TMP/dependency.log" 2>&1; then
    echo 'ERROR: missing parser runtime passed installer preflight' >&2
    exit 1
fi
grep -Fq 'Python runtime unavailable' "$TEST_TMP/dependency.log"
cmp "$STATE" "$TEST_TMP/expected-state"
cmp "$TARGET/.codex/config.toml" "$TEST_TMP/codex-before"
cmp "$TARGET/.claude/settings.json" "$TEST_TMP/claude-before"

echo 'unix-installer=PASS'
