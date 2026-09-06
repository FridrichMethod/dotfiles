#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-shell-profile.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT
mkdir "$TEST_TMP/home"

# Source the actual profile in empty homes so host overlays and login hooks
# cannot affect either the test or the developer's session.
for test_shell in sh bash zsh; do
    command -v "$test_shell" >/dev/null 2>&1 || continue
    for initial_manpath in unset '' '/opt/manuals:/usr/share/man' '/usr/local/man:/opt/manuals:'; do
        expected='/usr/local/man:'
        case "$initial_manpath" in
            /opt/*) expected="/usr/local/man:$initial_manpath" ;;
            /usr/local/*) expected="$initial_manpath" ;;
        esac
        env HOME="$TEST_TMP/home" DOTFILES_DIR="$TEST_TMP/no-checkout" \
            "$test_shell" -c '
                if [ "$2" = unset ]; then unset MANPATH; else export MANPATH="$2"; fi
                . "$1"
                [ "$MANPATH" = "$3" ] || exit 1
                . "$1"
                [ "$MANPATH" = "$3" ]
            ' profile "$REPO_ROOT/common/sh/.profile" "$initial_manpath" "$expected"
    done
    # When a native man and its system pages are installed, also check actual
    # lookup behavior instead of relying only on the MANPATH representation.
    env HOME="$TEST_TMP/home" DOTFILES_DIR="$TEST_TMP/no-checkout" \
        "$test_shell" -c '
            unset MANPATH
            if command -v man >/dev/null 2>&1 && before=$(man -w ls 2>/dev/null); then
                . "$1"
                after=$(man -w ls)
                [ "$before" = "$after" ]
            fi
        ' profile "$REPO_ROOT/common/sh/.profile"
done

echo "shell-profile=PASS"
