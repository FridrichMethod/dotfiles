#!/bin/bash

set -euo pipefail

# Hermetic: the provisioning exports (DOTFILES_AUTO_UPDATE=0 and the like,
# docs/bootstrap.md) and other dotfiles knobs never reach the code under
# test from the caller; each case sets what it needs.
unset DOTFILES_AUTO_UPDATE DOTFILES_AUTO_STOW DOTFILES_HOST DOTFILES_DIR _DOTFILES_CHECKED \
    DOTFILES_STOW_WITHOUT_OH_MY_ZSH DOTFILES_COLOR AWESOME_SKILLS_AUTO_UPDATE AWESOME_SKILLS_FORCE \
    AWESOME_SKILLS_BG AWESOME_SKILLS_INSTALLER_URL AWESOME_SKILLS_REFRESH_DAYS _AWESOME_SKILLS_CHECKED

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-test-entrypoints.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT
mkdir "$TEST_TMP/bin"

# Deliberately omit optional tools without relying on the host's installed set.
for dependency in bash sh git python3 node dirname; do
    ln -s "$(command -v "$dependency")" "$TEST_TMP/bin/$dependency"
done
if PATH="$TEST_TMP/bin" /bin/bash "$TEST_DIR/run.sh" --ci --check-prerequisites \
    >"$TEST_TMP/ci.stdout" 2>"$TEST_TMP/ci.stderr"; then
    printf 'ERROR: CI accepted a missing Stow integration prerequisite.\n' >&2
    exit 1
fi
grep -Fq 'CI requires stow' "$TEST_TMP/ci.stderr"

PATH="$TEST_TMP/bin" /bin/bash "$TEST_DIR/run.sh" --check-prerequisites \
    >"$TEST_TMP/local.stdout" 2>"$TEST_TMP/local.stderr"
grep -Fq 'SKIP: real GNU Stow integration' "$TEST_TMP/local.stdout"
grep -Fq 'SKIP: optional Unix PowerShell checks' "$TEST_TMP/local.stdout"
grep -Fq 'SKIP: optional installed-Codex exec-policy checks' "$TEST_TMP/local.stdout"
grep -Fxq 'test-prerequisites=PASS' "$TEST_TMP/local.stdout"

rm "$TEST_TMP/bin/node"
if PATH="$TEST_TMP/bin" /bin/bash "$TEST_DIR/run.sh" --check-prerequisites \
    >"$TEST_TMP/missing.stdout" 2>"$TEST_TMP/missing.stderr"; then
    printf 'ERROR: local tests accepted a missing required Node dependency.\n' >&2
    exit 1
fi
grep -Fq 'required test dependency not found: node' "$TEST_TMP/missing.stderr"

if /bin/bash "$TEST_DIR/run.sh" --unknown-option \
    >"$TEST_TMP/option.stdout" 2>"$TEST_TMP/option.stderr"; then
    printf 'ERROR: test entrypoint accepted an unknown option.\n' >&2
    exit 1
else
    [[ "$?" == 2 ]]
fi

# Every entry point drops the same dotfiles knobs, tests/run.ps1 too, and the
# list names every DOTFILES_* and AWESOME_SKILLS_* variable the scripts read
# (but DOTFILES_SYNC_PYTHON, which tests/run.sh provisions), so a shell that
# exports DOTFILES_AUTO_UPDATE=0 while provisioning cannot fail a suite.
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
# knob_list FILE: the names of FILE's "unset DOTFILES_AUTO_UPDATE ..." statement.
knob_list() {
    sed -n '/^unset DOTFILES_AUTO_UPDATE /,/[^\\]$/p' "$1" | tr -d '\\' | tr -s ' ' '\n' |
        grep -v -e '^unset$' -e '^$' | LC_ALL=C sort
}
KNOBS=$(knob_list "$TEST_DIR/run.sh")
[[ -n "$KNOBS" ]] || {
    printf 'ERROR: tests/run.sh has no unset statement for the dotfiles knobs.\n' >&2
    exit 1
}
for test_file in "$TEST_DIR"/*.sh; do
    if [[ "$(knob_list "$test_file")" != "$KNOBS" ]]; then
        printf 'ERROR: %s does not unset the dotfiles knobs that tests/run.sh does.\n' "${test_file#"$REPO_ROOT"/}" >&2
        exit 1
    fi
done
PS_KNOBS=$(awk '/foreach \(\$knob in @\(/ { on = 1 } on { print } on && /\)\) \{/ { exit }' "$TEST_DIR/run.ps1" |
    grep -oE "'[A-Z_]+'" | tr -d "'" | LC_ALL=C sort)
if [[ "$PS_KNOBS" != "$KNOBS" ]]; then
    printf 'ERROR: tests/run.ps1 does not remove the dotfiles knobs that tests/run.sh unsets.\n' >&2
    exit 1
fi
READ_KNOBS=$(
    cd "$REPO_ROOT" &&
        grep -ohE '\$\{?_?(DOTFILES|AWESOME_SKILLS)_[A-Z_]+|\$env:_?(DOTFILES|AWESOME_SKILLS)_[A-Za-z_]+' \
            doctor.sh setup-host.sh stow-all.sh stow-all.ps1 doctor.ps1 setup-host.ps1 \
            scripts/*.sh scripts/*.ps1 lib/*.sh lib/*.ps1 lib/bootstrap/*.sh common/sh/.profile \
            common/zsh/.zshrc win/powershell/Documents/PowerShell/profile.ps1 |
        sed -E 's/^\$(\{|env:)?//' | LC_ALL=C sort -u
)
for knob in $READ_KNOBS; do
    [[ "$knob" != DOTFILES_SYNC_PYTHON ]] || continue
    if ! grep -Fxq -- "$knob" <<<"$KNOBS"; then
        printf 'ERROR: the scripts read %s, which the test entry points do not unset.\n' "$knob" >&2
        exit 1
    fi
done
# The provisioning exports in the caller's shell change nothing.
if ! env DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0 DOTFILES_HOST= _DOTFILES_CHECKED=1 \
    AWESOME_SKILLS_FORCE=1 AWESOME_SKILLS_BG=1 _AWESOME_SKILLS_CHECKED=1 \
    /bin/bash "$TEST_DIR/awesome-skills-update.sh" >"$TEST_TMP/hermetic.stdout" 2>"$TEST_TMP/hermetic.stderr"; then
    cat "$TEST_TMP/hermetic.stdout" "$TEST_TMP/hermetic.stderr" >&2
    printf 'ERROR: tests/awesome-skills-update.sh fails under the provisioning exports.\n' >&2
    exit 1
fi
grep -Fxq 'awesome-skills-update=PASS' "$TEST_TMP/hermetic.stdout"

printf 'test-entrypoints=PASS\n'
