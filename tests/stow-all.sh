#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$REPO_ROOT/stow-all.sh"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-stow-all.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM

FIXTURE="$TEST_TMP/fixture"
FAKE_BIN="$TEST_TMP/bin"
TEST_HOME="$TEST_TMP/home"
EVENT_LOG="$TEST_TMP/events.log"
mkdir -p "$FIXTURE" "$FAKE_BIN" "$TEST_HOME"
cp "$INSTALLER" "$FIXTURE/stow-all.sh"
chmod +x "$FIXTURE/stow-all.sh"

assert_mode() {
    python3 - "$1" "$2" <<'PY'
import os
import sys

actual = os.stat(sys.argv[1]).st_mode & 0o777
expected = int(sys.argv[2], 8)
assert actual == expected, f"{sys.argv[1]}: mode {actual:o}, expected {expected:o}"
PY
}

assert_events() {
    expected="$TEST_TMP/expected-events.log"
    if [ "$#" -eq 0 ]; then
        : >"$expected"
    else
        printf '%s\n' "$@" >"$expected"
    fi
    if ! cmp -s "$expected" "$EVENT_LOG"; then
        echo "ERROR: unexpected installer event sequence" >&2
        diff -u "$expected" "$EVENT_LOG" >&2 || true
        exit 1
    fi
}

cat >"$FAKE_BIN/stow" <<'SH'
#!/bin/sh
{
    printf 'stow:'
    for argument do
        printf '[%s]' "$argument"
    done
    printf '\n'
} >>"$EVENT_LOG"
exit "${STOW_RC:-0}"
SH

cat >"$FAKE_BIN/git" <<'SH'
#!/bin/sh
{
    printf 'git:'
    for argument do
        printf '[%s]' "$argument"
    done
    printf '\n'
} >>"$EVENT_LOG"

if [ "${3:-}" = "--get-regexp" ]; then
    [ "${FILTER_PRESENT:-0}" = "1" ]
    exit
fi
if [ "${3:-}" = "--remove-section" ]; then
    exit 0
fi
exit 91
SH
chmod +x "$FAKE_BIN/stow" "$FAKE_BIN/git"

mkdir -p \
    "$FIXTURE/common/alpha" \
    "$FIXTURE/common/claude/.local/bin" \
    "$FIXTURE/common/claude/.claude" \
    "$FIXTURE/common/codex/.local/bin" \
    "$FIXTURE/common/codex/.codex/rules" \
    "$FIXTURE/host-a/beta" \
    "$FIXTURE/host-a/claude/.claude" \
    "$FIXTURE/host-a/codex/.codex/rules" \
    "$FIXTURE/host-a/fcitx5/.local/bin" \
    "$FIXTURE/host-a/fcitx5/.config/fcitx5"

printf '%s\n' 'common-claude' >"$FIXTURE/common/claude/.claude/settings.json"
printf '%s\n' 'common-codex' >"$FIXTURE/common/codex/.codex/config.toml"
printf '%s\n' 'common-rules' >"$FIXTURE/common/codex/.codex/rules/portable.rules"
printf '%s\n' 'host-claude' >"$FIXTURE/host-a/claude/.claude/settings.json"
printf '%s\n' 'host-codex' >"$FIXTURE/host-a/codex/.codex/config.toml"
printf '%s\n' 'host-rules' >"$FIXTURE/host-a/codex/.codex/rules/portable.rules"
printf '%s\n' 'host-fcitx5' >"$FIXTURE/host-a/fcitx5/.config/fcitx5/profile"

cat >"$TEST_TMP/sync-helper" <<'SH'
#!/bin/sh
name=$(basename "$0")
printf 'sync:%s:[%s][%s]\n' "$name" "$1" "$2" >>"$EVENT_LOG"
[ "${FAIL_SYNC:-}" != "$name" ] || exit 23
SH
for helper in codex-config-sync codex-rules-sync; do
    cp "$TEST_TMP/sync-helper" "$FIXTURE/common/codex/.local/bin/$helper"
done
cp "$TEST_TMP/sync-helper" \
    "$FIXTURE/common/claude/.local/bin/claude-settings-sync"
cp "$TEST_TMP/sync-helper" \
    "$FIXTURE/host-a/fcitx5/.local/bin/fcitx5-profile-sync"
chmod +x \
    "$FIXTURE/common/codex/.local/bin/codex-config-sync" \
    "$FIXTURE/common/codex/.local/bin/codex-rules-sync" \
    "$FIXTURE/common/claude/.local/bin/claude-settings-sync" \
    "$FIXTURE/host-a/fcitx5/.local/bin/fcitx5-profile-sync"

run_fixture() {
    case_name=$1
    shift
    : >"$EVENT_LOG"
    env \
        HOME="$TEST_HOME" \
        PATH="$FAKE_BIN:/usr/bin:/bin" \
        EVENT_LOG="$EVENT_LOG" \
        LC_ALL=C \
        "$@" \
        bash "$FIXTURE/stow-all.sh" \
        >"$TEST_TMP/$case_name.stdout" \
        2>"$TEST_TMP/$case_name.stderr"
}

# Platform and host validation happen before any sync, git, or Stow side effect.
: >"$EVENT_LOG"
if env \
    HOME="$TEST_HOME" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    EVENT_LOG="$EVENT_LOG" \
    bash "$FIXTURE/stow-all.sh" win \
    >"$TEST_TMP/win.stdout" 2>"$TEST_TMP/win.stderr"; then
    echo "ERROR: POSIX installer unexpectedly accepted the win host" >&2
    exit 1
fi
grep -Fq "the 'win' host is installed from Windows" "$TEST_TMP/win.stderr"
grep -Fq '.\stow-all.ps1 win' "$TEST_TMP/win.stderr"
assert_events

if env \
    HOME="$TEST_HOME" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    EVENT_LOG="$EVENT_LOG" \
    bash "$FIXTURE/stow-all.sh" missing-host \
    >"$TEST_TMP/missing-host.stdout" 2>"$TEST_TMP/missing-host.stderr"; then
    echo "ERROR: installer unexpectedly accepted a missing host" >&2
    exit 1
fi
grep -Fq 'host dir not found' "$TEST_TMP/missing-host.stderr"
assert_events

# Common-only setup synchronizes all portable AI baselines before one Stow call.
run_fixture common-only
assert_events \
    "sync:codex-config-sync:[$FIXTURE/common/codex/.codex/config.toml][$TEST_HOME/.codex/config.toml]" \
    "sync:codex-rules-sync:[$FIXTURE/common/codex/.codex/rules/portable.rules][$TEST_HOME/.codex/rules/portable.rules]" \
    "sync:claude-settings-sync:[$FIXTURE/common/claude/.claude/settings.json][$TEST_HOME/.claude/settings.json]" \
    'git:[config][--local][--get-regexp][^filter\.codex-portable\.]' \
    "stow:[--restow][--no-folding][-d][$FIXTURE/common][alpha][claude][codex]"
grep -Fq "Stowing from $FIXTURE" "$TEST_TMP/common-only.stdout"
grep -Fq 'Stowing common packages:' "$TEST_TMP/common-only.stdout"
! grep -Fq 'Stowing host-specific packages:' "$TEST_TMP/common-only.stdout"

# Host baselines override common sources, fcitx5 is host-only, the obsolete Git
# filter is removed when present, and common packages are stowed first.
: >"$EVENT_LOG"
env \
    HOME="$TEST_HOME" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    EVENT_LOG="$EVENT_LOG" \
    FILTER_PRESENT=1 \
    LC_ALL=C \
    bash "$FIXTURE/stow-all.sh" host-a \
    >"$TEST_TMP/host.stdout" 2>"$TEST_TMP/host.stderr"
assert_events \
    "sync:codex-config-sync:[$FIXTURE/host-a/codex/.codex/config.toml][$TEST_HOME/.codex/config.toml]" \
    "sync:codex-rules-sync:[$FIXTURE/host-a/codex/.codex/rules/portable.rules][$TEST_HOME/.codex/rules/portable.rules]" \
    "sync:claude-settings-sync:[$FIXTURE/host-a/claude/.claude/settings.json][$TEST_HOME/.claude/settings.json]" \
    "sync:fcitx5-profile-sync:[$FIXTURE/host-a/fcitx5/.config/fcitx5/profile][$TEST_HOME/.config/fcitx5/profile]" \
    'git:[config][--local][--get-regexp][^filter\.codex-portable\.]' \
    'git:[config][--local][--remove-section][filter.codex-portable]' \
    "stow:[--restow][--no-folding][-d][$FIXTURE/common][alpha][claude][codex]" \
    "stow:[--restow][--no-folding][-d][$FIXTURE/host-a][beta][claude][codex][fcitx5]"
grep -Fq 'Stowing host-specific packages:' "$TEST_TMP/host.stdout"

# A sync failure is fail-closed: later syncs, git mutation, and Stow never run.
: >"$EVENT_LOG"
if env \
    HOME="$TEST_HOME" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    EVENT_LOG="$EVENT_LOG" \
    FAIL_SYNC=codex-config-sync \
    bash "$FIXTURE/stow-all.sh" \
    >"$TEST_TMP/sync-failure.stdout" 2>"$TEST_TMP/sync-failure.stderr"; then
    echo "ERROR: installer ignored a portable sync failure" >&2
    exit 1
fi
assert_events \
    "sync:codex-config-sync:[$FIXTURE/common/codex/.codex/config.toml][$TEST_HOME/.codex/config.toml]"

# SSH permissions apply to the real targets of regular and chained symlinks;
# dangling config snippets are ignored without aborting the restow.
mkdir -p "$TEST_HOME/.ssh/config.d" "$TEST_TMP/ssh-sources/nested"
printf '%s\n' 'Host *' >"$TEST_TMP/ssh-sources/config"
printf '%s\n' 'Host example' >"$TEST_TMP/ssh-sources/nested/example.conf"
ln -s "$TEST_TMP/ssh-sources/config" "$TEST_HOME/.ssh/config"
ln -s "$TEST_TMP/ssh-sources/nested/example.conf" \
    "$TEST_HOME/.ssh/config.d/example.conf"
ln -s "$TEST_TMP/ssh-sources/missing.conf" \
    "$TEST_HOME/.ssh/config.d/dangling.conf"
chmod 777 "$TEST_HOME/.ssh" "$TEST_HOME/.ssh/config.d"
chmod 666 \
    "$TEST_TMP/ssh-sources/config" \
    "$TEST_TMP/ssh-sources/nested/example.conf"
run_fixture ssh-permissions
assert_mode "$TEST_HOME/.ssh" 700
assert_mode "$TEST_HOME/.ssh/config.d" 700
assert_mode "$TEST_TMP/ssh-sources/config" 600
assert_mode "$TEST_TMP/ssh-sources/nested/example.conf" 600
[[ -L "$TEST_HOME/.ssh/config" ]]
[[ -L "$TEST_HOME/.ssh/config.d/example.conf" ]]
[[ -L "$TEST_HOME/.ssh/config.d/dangling.conf" ]]

echo "stow-all=PASS"
