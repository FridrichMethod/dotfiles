#!/bin/bash

set -euo pipefail

# Hermetic: the provisioning exports (DOTFILES_AUTO_UPDATE=0 and the like,
# docs/bootstrap.md) and other dotfiles knobs never reach the code under
# test from the caller; each case sets what it needs.
unset DOTFILES_AUTO_UPDATE DOTFILES_AUTO_STOW DOTFILES_HOST DOTFILES_DIR _DOTFILES_CHECKED \
    DOTFILES_STOW_WITHOUT_OH_MY_ZSH DOTFILES_COLOR AWESOME_SKILLS_AUTO_UPDATE AWESOME_SKILLS_FORCE \
    AWESOME_SKILLS_BG AWESOME_SKILLS_INSTALLER_URL AWESOME_SKILLS_REFRESH_DAYS _AWESOME_SKILLS_CHECKED

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
[[ -f "$REPO_ROOT/common/codex/coding-agent-kit/lib/config_sync.py" ]] || {
    echo 'ERROR: coding-agent-kit submodule not initialized; run git submodule update --init --recursive.' >&2
    exit 1
}
export DOTFILES_SYNC_PYTHON="$sync_python"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ai-integration.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM

"$sync_python" -I -B -m unittest discover -s "$TEST_DIR" -p 'test_ai_integration.py' -v

# Real-data overlay: the engine suites of the pinned coding-agent-kit tree run
# again with the real settings in place of their frozen fixtures, so every
# change to the data or the gitlink re-validates both against each other.
# The kit is an archive of the committed submodule HEAD; the checkout itself
# is never touched.
sub=$REPO_ROOT/common/codex/coding-agent-kit
kit=$TEST_TMP/kit
mkdir -p "$kit"
# A pre-commit run exports the GIT_DIR and GIT_INDEX_FILE of the commit in
# progress; the archive must read the submodule's own repository.
(
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
        GIT_ALTERNATE_OBJECT_DIRECTORIES
    git -C "$sub" archive --format=tar HEAD
) | tar -x -C "$kit"
cp "$REPO_ROOT/common/codex/.codex/config.toml" "$kit/tests/fixtures/codex-config.toml"
cp "$REPO_ROOT/common/claude/.claude/settings.json" "$kit/tests/fixtures/claude-settings.json"
cp "$REPO_ROOT/common/codex/.codex/rules/portable.rules" "$kit/tests/fixtures/portable.rules"
DOTFILES_SYNC_PYTHON=$sync_python bash "$kit/tests/config-sync.sh"
node --test "$kit/tests/claude-customizations.cjs"
echo "ai-integration-overlay=PASS"
