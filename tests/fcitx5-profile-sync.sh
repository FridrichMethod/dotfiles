#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="$REPO_ROOT/lab-ubuntu/fcitx5/.local/bin/fcitx5-profile-sync"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-fcitx5-sync.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM

assert_mode() {
    python3 - "$1" "$2" <<'PY'
import os
import sys

actual = os.stat(sys.argv[1]).st_mode & 0o777
expected = int(sys.argv[2], 8)
assert actual == expected, f"{sys.argv[1]}: mode {actual:o}, expected {expected:o}"
PY
}

assert_status() {
    expected=$1
    shift
    set +e
    "$@" >"$TEST_TMP/status.stdout" 2>"$TEST_TMP/status.stderr"
    actual=$?
    set -e
    if [[ "$actual" -ne "$expected" ]]; then
        echo "ERROR: expected exit $expected, got $actual: $*" >&2
        exit 1
    fi
}

cat >"$TEST_TMP/portable-profile" <<'PROFILE'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=pinyin

[Groups/0/Items/0]
Name=keyboard-us
Layout=
PROFILE

# Fresh install creates the parent and authoritative regular file.
"$SYNC" \
    "$TEST_TMP/portable-profile" \
    "$TEST_TMP/fresh/.config/fcitx5/profile" >/dev/null
cmp -s \
    "$TEST_TMP/portable-profile" \
    "$TEST_TMP/fresh/.config/fcitx5/profile"
assert_mode "$TEST_TMP/fresh/.config/fcitx5/profile" 600

# Runtime rewrites are replaced, while a no-op sync preserves the inode.
printf '%s\n' 'runtime rewrite' >"$TEST_TMP/live-profile"
chmod 644 "$TEST_TMP/live-profile"
"$SYNC" "$TEST_TMP/portable-profile" "$TEST_TMP/live-profile" >/dev/null
cmp -s "$TEST_TMP/portable-profile" "$TEST_TMP/live-profile"
assert_mode "$TEST_TMP/live-profile" 600
live_inode="$(python3 -c 'import os, sys; print(os.stat(sys.argv[1]).st_ino)' "$TEST_TMP/live-profile")"
"$SYNC" "$TEST_TMP/portable-profile" "$TEST_TMP/live-profile" >/dev/null
[[ "$live_inode" == "$(python3 -c 'import os, sys; print(os.stat(sys.argv[1]).st_ino)' "$TEST_TMP/live-profile")" ]]

# Even an identical legacy Stow link must become a machine-local regular file.
mkdir -p "$TEST_TMP/symlink"
cp "$TEST_TMP/portable-profile" "$TEST_TMP/symlink/source-profile"
ln -s source-profile "$TEST_TMP/symlink/live-profile"
source_inode="$(python3 -c 'import os, sys; print(os.stat(sys.argv[1]).st_ino)' "$TEST_TMP/symlink/source-profile")"
"$SYNC" \
    "$TEST_TMP/symlink/source-profile" \
    "$TEST_TMP/symlink/live-profile" >/dev/null
[[ ! -L "$TEST_TMP/symlink/live-profile" ]]
[[ "$source_inode" == "$(python3 -c 'import os, sys; print(os.stat(sys.argv[1]).st_ino)' "$TEST_TMP/symlink/source-profile")" ]]
cmp -s \
    "$TEST_TMP/symlink/source-profile" \
    "$TEST_TMP/symlink/live-profile"

# Missing input and bad arity leave an existing live file untouched.
printf '%s\n' 'keep-me' >"$TEST_TMP/failure-live"
failure_inode="$(python3 -c 'import os, sys; print(os.stat(sys.argv[1]).st_ino)' "$TEST_TMP/failure-live")"
assert_status 1 "$SYNC" "$TEST_TMP/missing-profile" "$TEST_TMP/failure-live"
grep -Fxq 'keep-me' "$TEST_TMP/failure-live"
[[ "$failure_inode" == "$(python3 -c 'import os, sys; print(os.stat(sys.argv[1]).st_ino)' "$TEST_TMP/failure-live")" ]]
assert_status 2 "$SYNC"
assert_status 2 "$SYNC" one two three

echo "fcitx5-profile-sync=PASS"
