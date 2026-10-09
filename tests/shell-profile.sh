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
        env -u NVM_DIR -u NVM_BIN HOME="$TEST_TMP/home" DOTFILES_DIR="$TEST_TMP/no-checkout" \
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
    env -u NVM_DIR -u NVM_BIN HOME="$TEST_TMP/home" DOTFILES_DIR="$TEST_TMP/no-checkout" \
        "$test_shell" -c '
            unset MANPATH
            if command -v man >/dev/null 2>&1 && before=$(man -w ls 2>/dev/null); then
                . "$1"
                after=$(man -w ls)
                [ "$before" = "$after" ]
            fi
        ' profile "$REPO_ROOT/common/sh/.profile"
done

# nvm: the profile resolves the default alias the way `nvm use default` does
# and puts that install's bin on PATH. The fake tree's numeric order differs
# from glob order (24.2 < 24.9 < 24.11), and v25.0.0 is an incomplete install
# without bin/node.
nvm_dir="$TEST_TMP/nvm-home/.nvm"
for version in v22.21.1 v24.2.0 v24.9.0 v24.11.1; do
    mkdir -p "$nvm_dir/versions/node/$version/bin"
    printf '#!/bin/sh\n' >"$nvm_dir/versions/node/$version/bin/node"
    chmod +x "$nvm_dir/versions/node/$version/bin/node"
done
mkdir -p "$nvm_dir/versions/node/v25.0.0/bin" "$nvm_dir/alias/lts" "$TEST_TMP/xdg-home/.config"
printf 'lts/krypton\n' >"$nvm_dir/alias/lts/*"
printf 'v24.11.1\n' >"$nvm_dir/alias/lts/krypton"
printf 'v22.21.1\n' >"$nvm_dir/alias/lts/jod"
printf 'v20.19.6\n' >"$nvm_dir/alias/lts/iron"
printf '22\n' >"$nvm_dir/alias/mine"
printf 'cycle-b\n' >"$nvm_dir/alias/cycle-a"
printf 'cycle-a\n' >"$nvm_dir/alias/cycle-b"
ln -s "$nvm_dir" "$TEST_TMP/xdg-home/.config/nvm"
node_bin() { printf '%s/versions/node/%s/bin' "$nvm_dir" "$1"; }

nvm_failures=0
# nvm_case LABEL SHELL HOME EXPECTED_BIN EXPECTED_NVM_DIR [VAR=value...]
# Sources the profile three times: with a parent's NVM_BIN still on PATH
# (adds nothing), without it or with a $STALE_NVM_BIN that is not on PATH
# (adds EXPECTED_BIN, or nothing when empty), and again (no change). Also
# requires silence and no leaked helper names.
nvm_case() {
    local label=$1 test_shell=$2 home=$3 expected_bin=$4 expected_dir=$5
    shift 5
    if env -u NVM_DIR -u NVM_BIN -u NVM_INC -u XDG_CONFIG_HOME "$@" \
        HOME="$home" DOTFILES_DIR="$TEST_TMP/no-checkout" PATH=/usr/bin:/bin \
        "$test_shell" -c '
            NVM_BIN=/bin
            . "$1"
            base=$PATH
            if [ -n "${STALE_NVM_BIN-}" ]; then NVM_BIN=$STALE_NVM_BIN; else unset NVM_BIN; fi
            . "$1"
            [ "$PATH" = "${2:+$2:}$base" ] || { printf "PATH=%s\n" "$PATH"; exit 1; }
            . "$1"
            [ "$PATH" = "${2:+$2:}$base" ] || { printf "second PATH=%s\n" "$PATH"; exit 1; }
            [ "${NVM_DIR-unset}" = "$3" ] || { printf "NVM_DIR=%s\n" "${NVM_DIR-unset}"; exit 1; }
            if leaked=$(set | grep "^_nvm"); then printf "leaked: %s\n" "$leaked"; exit 1; fi
            if command -v _nvm_default_bin >/dev/null 2>&1; then echo "leaked function"; exit 1; fi
        ' profile "$REPO_ROOT/common/sh/.profile" "$expected_bin" "$expected_dir" \
        >"$TEST_TMP/nvm-out" 2>&1 && [ ! -s "$TEST_TMP/nvm-out" ]; then
        return 0
    fi
    printf 'FAIL nvm %s (%s): %s\n' "$label" "$test_shell" "$(cat "$TEST_TMP/nvm-out")" >&2
    nvm_failures=$((nvm_failures + 1))
}

for test_shell in sh dash bash zsh; do
    # The cases run with PATH=/usr/bin:/bin, so pass the shell by full path.
    test_shell=$(command -v "$test_shell") || continue
    # default alias content and the install nvm would use (- for none).
    while read -r default expected; do
        printf '%s\n' "$default" >"$nvm_dir/alias/default"
        if [ "$expected" = - ]; then expected=; else expected=$(node_bin "$expected"); fi
        nvm_case "default=$default" "$test_shell" "$TEST_TMP/home" "$expected" "$nvm_dir" \
            NVM_DIR="$nvm_dir"
    done <<'EOF'
v22.21.1 v22.21.1
22.21.1 v22.21.1
lts/* v24.11.1
lts/jod v22.21.1
node v24.11.1
stable v24.11.1
24 v24.11.1
v24 v24.11.1
24.9 v24.9.0
24.11. v24.11.1
v24.11.1 v24.11.1
mine v22.21.1
2 -
v23 -
24.10 -
v24.11.2 -
lts/iron -
lts/argon -
system -
cycle-a -
EOF
    printf 'v22.21.1' >"$nvm_dir/alias/default"
    nvm_case "default without newline" "$test_shell" "$TEST_TMP/home" \
        "$(node_bin v22.21.1)" "$nvm_dir" NVM_DIR="$nvm_dir"
    : >"$nvm_dir/alias/default"
    nvm_case "empty default" "$test_shell" "$TEST_TMP/home" "" "$nvm_dir" NVM_DIR="$nvm_dir"
    printf '24\n' >"$nvm_dir/alias/default"
    nvm_case "stale NVM_BIN not on PATH" "$test_shell" "$TEST_TMP/home" \
        "$(node_bin v24.11.1)" "$nvm_dir" NVM_DIR="$nvm_dir" STALE_NVM_BIN=/nonexistent/bin
    # Without NVM_DIR the profile finds ~/.nvm, then $XDG_CONFIG_HOME/nvm
    # (~/.config/nvm), and exports it; with neither it sets nothing.
    nvm_case "HOME/.nvm" "$test_shell" "$TEST_TMP/nvm-home" "$(node_bin v24.11.1)" "$nvm_dir"
    nvm_case "HOME/.config/nvm" "$test_shell" "$TEST_TMP/xdg-home" \
        "$TEST_TMP/xdg-home/.config/nvm/versions/node/v24.11.1/bin" \
        "$TEST_TMP/xdg-home/.config/nvm"
    nvm_case "no nvm" "$test_shell" "$TEST_TMP/home" "" unset
done

# common/zsh/.oh-my-zsh/custom/nvm.zsh loads nvm without `nvm use` and moves
# the default node's bin back in front of the Homebrew and conda bins that
# the host rc prepended after ~/.profile ran.
if command -v zsh >/dev/null 2>&1; then
    # shellcheck disable=SC2016
    printf '%s\n' 'print -r -- "$*" >>"$NVM_DIR/nvm.sh.args"' 'nvm() { :; }' >"$nvm_dir/nvm.sh"
    if ! env -u NVM_BIN -u NVM_INC NVM_DIR="$nvm_dir" HOME="$TEST_TMP/home" \
        zsh -f -c '
            nvm_zsh=$1 node_bin=$2
            PATH=/opt/brew/bin:$node_bin:/usr/bin:/bin:$node_bin
            source $nvm_zsh
            [[ $PATH == $node_bin:/opt/brew/bin:/usr/bin:/bin ]] || { print -r -- "PATH=$PATH"; exit 1 }
            [[ $NVM_BIN == $node_bin && $NVM_INC == ${node_bin%/bin}/include/node ]] || exit 1
            [[ $(<$NVM_DIR/nvm.sh.args) == --no-use ]] || exit 1
            (( ! ${#chpwd_functions} )) || exit 1
            source $nvm_zsh
            [[ $PATH == $node_bin:/opt/brew/bin:/usr/bin:/bin ]] || exit 1
            [[ $(<$NVM_DIR/nvm.sh.args) == --no-use ]] || exit 1
            unset NVM_BIN NVM_INC
            PATH=/opt/brew/bin:/usr/bin:/bin
            source $nvm_zsh
            [[ $PATH == /opt/brew/bin:/usr/bin:/bin && -z ${NVM_BIN-} ]]
        ' nvm-zsh "$REPO_ROOT/common/zsh/.oh-my-zsh/custom/nvm.zsh" "$(node_bin v24.11.1)" \
        2>&1; then
        echo "FAIL nvm.zsh" >&2
        nvm_failures=$((nvm_failures + 1))
    fi
fi

[ "$nvm_failures" = 0 ] || exit 1
echo "shell-profile=PASS"
