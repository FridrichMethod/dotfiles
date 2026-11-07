#!/bin/bash

set -euo pipefail

# Isolate inherited configuration while preserving explicit test inputs.
# shellcheck source=tests/lib/environment.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/environment.sh"

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-shell-profile.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT
mkdir "$TEST_TMP/home"
# Cases that reset PATH to /usr/bin:/bin run each shell by the full path found
# here: an HPC login env or Homebrew may provide one only outside it.
ZSH_BIN=$(command -v zsh 2>/dev/null) || ZSH_BIN=

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
        env -u NVM_DIR -u NVM_BIN HOME="$TEST_TMP/home" \
            "$test_shell" -c '
                if [ "$2" = unset ]; then unset MANPATH; else export MANPATH="$2"; fi
                . "$1"
                [ "$MANPATH" = "$3" ] || exit 1
                . "$1"
                [ "$MANPATH" = "$3" ]
            ' profile "$REPO_ROOT/home/dot_profile" "$initial_manpath" "$expected"
    done
    # When a native man and its system pages are installed, also check actual
    # lookup behavior instead of relying only on the MANPATH representation.
    env -u NVM_DIR -u NVM_BIN HOME="$TEST_TMP/home" \
        "$test_shell" -c '
            unset MANPATH
            if command -v man >/dev/null 2>&1 && before=$(man -w ls 2>/dev/null); then
                . "$1"
                after=$(man -w ls)
                [ "$before" = "$after" ]
            fi
        ' profile "$REPO_ROOT/home/dot_profile"
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
# requires silence and no leaked helper names. FAILGLOB=1 (bash only) turns
# failglob on first and requires it to stay on.
nvm_case() {
    local label=$1 test_shell=$2 home=$3 expected_bin=$4 expected_dir=$5
    shift 5
    if env -u NVM_DIR -u NVM_BIN -u NVM_INC -u XDG_CONFIG_HOME "$@" \
        HOME="$home" PATH=/usr/bin:/bin \
        "$test_shell" -c '
            if [ -n "${FAILGLOB-}" ]; then shopt -s failglob; fi
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
            if [ -n "${FAILGLOB-}" ]; then shopt -q failglob || { echo "failglob off"; exit 1; }; fi
        ' profile "$REPO_ROOT/home/dot_profile" "$expected_bin" "$expected_dir" \
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
lts/-1 -
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
    if [ "${test_shell##*/}" = bash ]; then
        printf 'v23\n' >"$nvm_dir/alias/default"
        nvm_case "failglob, nothing installed matches" "$test_shell" "$TEST_TMP/home" "" \
            "$nvm_dir" NVM_DIR="$nvm_dir" FAILGLOB=1
        printf '24\n' >"$nvm_dir/alias/default"
        nvm_case "failglob" "$test_shell" "$TEST_TMP/home" "$(node_bin v24.11.1)" "$nvm_dir" \
            NVM_DIR="$nvm_dir" FAILGLOB=1
    fi
    # Without NVM_DIR the profile finds ~/.nvm, then $XDG_CONFIG_HOME/nvm
    # (~/.config/nvm), and exports it; with neither it sets nothing.
    nvm_case "HOME/.nvm" "$test_shell" "$TEST_TMP/nvm-home" "$(node_bin v24.11.1)" "$nvm_dir"
    nvm_case "HOME/.config/nvm" "$test_shell" "$TEST_TMP/xdg-home" \
        "$TEST_TMP/xdg-home/.config/nvm/versions/node/v24.11.1/bin" \
        "$TEST_TMP/xdg-home/.config/nvm"
    nvm_case "no nvm" "$test_shell" "$TEST_TMP/home" "" unset
done

# home/dot_oh-my-zsh/custom/nvm.zsh loads nvm without `nvm use`. Only
# when a later `brew shellenv` (oh-my-zsh's brew plugin on macOS) has put
# Homebrew's bin ahead of nvm's does it move nvm's bin back, just ahead of
# Homebrew's. Otherwise it must not assign PATH, which would empty the
# command hash table: a hashed marker command has to survive.
if [ -n "$ZSH_BIN" ]; then
    # shellcheck disable=SC2016
    printf '%s\n' 'print -r -- "$*" >>"$NVM_DIR/nvm.sh.args"' 'nvm() { :; }' >"$nvm_dir/nvm.sh"
    if ! env -u NVM_BIN -u NVM_INC -u HOMEBREW_PREFIX NVM_DIR="$nvm_dir" HOME="$TEST_TMP/home" \
        "$ZSH_BIN" -f -c '
            nvm_zsh=$1 node_bin=$2
            NVM_BIN=$node_bin HOMEBREW_PREFIX=/opt/brew
            PATH=/opt/x:/opt/brew/bin:/opt/brew/sbin:$node_bin:/usr/bin:/bin
            source $nvm_zsh
            [[ $PATH == /opt/x:$node_bin:/opt/brew/bin:/opt/brew/sbin:/usr/bin:/bin ]] ||
                { print -r -- "PATH=$PATH"; exit 1 }
            [[ $(<$NVM_DIR/nvm.sh.args) == --no-use ]] || exit 1
            (( ! ${#chpwd_functions} )) || exit 1
            hash _marker=/bin/sh
            source $nvm_zsh
            [[ $PATH == /opt/x:$node_bin:/opt/brew/bin:/opt/brew/sbin:/usr/bin:/bin ]] || exit 1
            [[ $(<$NVM_DIR/nvm.sh.args) == --no-use ]] || exit 1
            (( $+commands[_marker] )) || { print "PATH assigned"; exit 1 }
            unset NVM_BIN
            PATH=/opt/brew/bin:/usr/bin:/bin:$node_bin
            hash _marker=/bin/sh
            source $nvm_zsh
            [[ $PATH == /opt/brew/bin:/usr/bin:/bin:$node_bin ]] && (( $+commands[_marker] ))
        ' nvm-zsh "$REPO_ROOT/home/dot_oh-my-zsh/custom/nvm.zsh" "$(node_bin v24.11.1)" \
        2>&1; then
        echo "FAIL nvm.zsh" >&2
        nvm_failures=$((nvm_failures + 1))
    fi
fi

# home/dot_zshrc in three nested interactive shells. The host rc runs a
# fake `brew shellenv` that, like Homebrew's, prints nothing only while PATH
# starts with its bin:sbin, then prepends a condabin once per process tree,
# as conda's hook does, and a login env's bin every time, as Sherlock's does;
# Homebrew's bin holds another node. A stub oh-my-zsh runs `brew shellenv`
# when brew is not on PATH, as its brew plugin does, then hashes a marker
# command and sources custom/nvm.zsh. Every level must end with the same
# PATH, FPATH and INFOPATH, no duplicate in PATH, nvm's default node first,
# and no PATH assignment after oh-my-zsh. After startup PATH keeps
# duplicates: a simulated `conda activate` (prepend) and `conda deactivate`
# (drop the first copy) of the login env, through PATH and again through
# path, leaves PATH as it was. An env, or Homebrew's bin, that the first
# shell put ahead of node stays ahead in nested shells. On macOS (mac: no
# `brew shellenv` in the host rc) the brew plugin puts Homebrew's bin ahead
# in the first shell, and nvm.zsh moves nvm's back ahead of it. Without nvm
# nothing restores the order that `brew shellenv` changes in the second
# shell, but PATH must still not grow.
if [ -n "$ZSH_BIN" ]; then
    zhome=$TEST_TMP/zsh-home brew=$TEST_TMP/brew
    mkdir -p "$zhome/.config/zsh" "$zhome/.oh-my-zsh/custom" "$brew/bin" "$brew/sbin" \
        "$TEST_TMP/condabin" "$TEST_TMP/env/bin" "$TEST_TMP/login/bin"
    ln -s "$REPO_ROOT/home/dot_profile" "$zhome/.profile"
    ln -s "$REPO_ROOT/home/dot_zshrc" "$zhome/.zshrc"
    ln -s "$REPO_ROOT/home/dot_oh-my-zsh/custom/nvm.zsh" "$zhome/.oh-my-zsh/custom/"
    for node in "$brew/bin/node" "$TEST_TMP/env/bin/node"; do
        printf '#!/bin/sh\n' >"$node"
        chmod +x "$node"
    done
    # shellcheck disable=SC2016
    {
        printf '#!/bin/sh\n'
        printf 'case "$PATH:" in "%s/bin:%s/sbin:"*) exit 0 ;; esac\n' "$brew" "$brew"
        printf 'echo '\''export HOMEBREW_PREFIX="%s"'\''\n' "$brew"
        printf 'echo '\''export PATH="%s/bin:%s/sbin${PATH+:$PATH}"'\''\n' "$brew" "$brew"
        printf 'echo '\''fpath[1,0]="%s/share/zsh/site-functions"; export FPATH'\''\n' "$brew"
        printf 'echo '\''export INFOPATH="%s/share/info:${INFOPATH:-}"'\''\n' "$brew"
    } >"$brew/bin/brew"
    chmod +x "$brew/bin/brew"
    # shellcheck disable=SC2016
    printf '%s\n' "[[ -n \${MAC-} ]] || eval \"\$('$brew/bin/brew' shellenv)\"" \
        'if [[ -z ${CONDA_SHLVL+x} ]]; then' \
        "    export CONDA_SHLVL=0 PATH='$TEST_TMP/condabin':\$PATH" \
        'fi' \
        "export PATH='$TEST_TMP/login/bin':\$PATH" >"$zhome/.config/zsh/.zshrc"
    # shellcheck disable=SC2016
    printf '%s\n' "((\$+commands[brew])) || eval \"\$('$brew/bin/brew' shellenv)\"" \
        'hash _omz_marker=/bin/sh' 'for f in $ZSH/custom/*.zsh; do source $f; done' \
        >"$zhome/.oh-my-zsh/oh-my-zsh.sh"
    # shellcheck disable=SC2016
    printf '%s\n' \
        '(($+commands[_omz_marker])) || print -r -- "L$LVL: PATH assigned after oh-my-zsh"' \
        '((!$+_zshrc_brew_ahead && !$+_zshrc_parent_path)) || print -r -- "L$LVL: leaked"' \
        "p0=\$PATH login='$TEST_TMP/login/bin'" \
        'export PATH=$login:$PATH' \
        'p=("${(@s.:.)PATH}") && p[${p[(ie)$login]}]=() && export PATH=${(j.:.)p}' \
        'path[1,0]=$login && path[${path[(ie)$login]}]=()' \
        '[[ $PATH == "$p0" ]] || print -r -- "L$LVL: conda deactivate dropped $login"' \
        '[[ -z $ACTIVATE || $LVL != 1 ]] || path=("$ACTIVATE" "${(@)path:#$ACTIVATE}")' \
        'print -rl -- "$PATH" "$FPATH" "$INFOPATH" "$NVM_BIN" "${commands[node]}" >$OUT$LVL' \
        '((LVL < 3)) || return 0' \
        'LVL=$((LVL + 1)) "$TEST_ZSH" -d -i -c '\''source $NEST'\''' >"$TEST_TMP/nest.zsh"
    printf '24\n' >"$nvm_dir/alias/default"
    nvm_bin=$(node_bin v24.11.1)
    for variant in default env brew-first mac no-nvm; do
        out=$TEST_TMP/nested-$variant activate='' nvm_home=$nvm_dir same=1 mac='' want_noise=''
        head=$nvm_bin: want_nvm_bin=$nvm_bin node=$nvm_bin/node
        case $variant in
            env) activate=$TEST_TMP/env/bin head=$activate:$nvm_bin: node=$activate/node ;;
            brew-first) activate=$brew/bin head=$activate:$nvm_bin: node=$activate/node ;;
            mac) mac=1 head=$nvm_bin:$brew/bin: want_noise='L1: PATH assigned after oh-my-zsh' ;;
            no-nvm) nvm_home=$TEST_TMP/no-nvm head='' want_nvm_bin='' node=$brew/bin/node same=2 ;;
        esac
        noise=$(env -i HOME="$zhome" PATH=/usr/bin:/bin TERM=dumb NVM_DIR="$nvm_home" \
            NEST="$TEST_TMP/nest.zsh" OUT="$out" TEST_ZSH="$ZSH_BIN" \
            ACTIVATE="$activate" MAC="$mac" LVL=1 "$ZSH_BIN" -d -i -c 'source $NEST' </dev/null 2>&1 |
            grep -v '^stty: ' || true)
        ok=1
        [ "$noise" = "$want_noise" ] && cmp -s "$out$same" "${out}2" && cmp -s "$out$same" "${out}3" ||
            ok=0
        for level in 1 2 3; do
            [ -f "$out$level" ] && [ -z "$(sed -n 1p "$out$level" | tr : '\n' | sort | uniq -d)" ] ||
                ok=0
        done
        if [ "$ok" = 1 ]; then
            case $(sed -n 1p "${out}1") in "$head"*) ;; *) ok=0 ;; esac
            [ "$(sed -n 4p "${out}1")" = "$want_nvm_bin" ] && [ "$(sed -n 5p "${out}1")" = "$node" ] ||
                ok=0
        fi
        if [ "$ok" = 0 ]; then
            printf 'FAIL nested .zshrc (%s): %s\n' "$variant" "$noise" >&2
            for level in 1 2 3; do sed "s/^/  L$level: /" "$out$level" >&2 || true; done
            nvm_failures=$((nvm_failures + 1))
        fi
    done
    # Sourced by a non-interactive shell, .zshrc stops after ~/.profile, and
    # PATH must not stay unique there either.
    # shellcheck disable=SC2016
    if ! env -i HOME="$zhome" PATH=/usr/bin:/bin NVM_DIR="$nvm_dir" \
        "$ZSH_BIN" -d -c 'source ~/.zshrc && [[ ${(t)path}${(t)PATH} != *unique* ]]' 2>&1; then
        echo "FAIL non-interactive .zshrc left PATH unique" >&2
        nvm_failures=$((nvm_failures + 1))
    fi
fi

# home/dot_oh-my-zsh/custom/fzf-tab.zsh: both tldr previews color the page
# with every tldr client. tlrc and tealdeer take `--color always`; the C
# client (the tldr formula Homebrew removed, still on hosts that installed
# it) takes a bare -C and, given `--color always ls`, looks up a page named
# "always-ls", prints "This page doesn't exist yet!" and exits 1. Each fake
# prints the colored page only for the arguments its client accepts, and that
# error for any other. The C client goes online (a page its cache lacks, a
# cache two weeks old) unless TLDR_AUTO_UPDATE_DISABLED is set, so its fake
# logs every call made without it, and no preview may make one. The previews
# are evaluated as fzf-tab does, in zsh with $word and $desc set.
preview_failures=0
TLDR_ONLINE_LOG=$TEST_TMP/tldr-online.log
if [ -n "$ZSH_BIN" ]; then
    # write_tldr DIR ACCEPTED [ONLINE_LOG]: a fake tldr in DIR that accepts
    # only ACCEPTED and, given ONLINE_LOG, appends to it the arguments of each
    # call made without TLDR_AUTO_UPDATE_DISABLED.
    write_tldr() {
        mkdir -p "$1"
        {
            printf '#!/bin/sh\naccepted=%s\nonline_log=%s\n' "'$2'" "'${3:-}'"
            cat <<'SH'
if [ -n "$online_log" ] && [ -z "${TLDR_AUTO_UPDATE_DISABLED+set}" ]; then
    printf '%s\n' "$*" >>"$online_log"
fi
if [ "$*" = "$accepted" ]; then
    printf '\033[1mls\033[0m\nList directory contents.\n'
    exit 0
fi
echo "This page doesn't exist yet!"
exit 1
SH
        } >"$1/tldr"
        chmod +x "$1/tldr"
    }
    # preview DIR CONTEXT WORD: stdout of the fzf-preview zstyle for CONTEXT,
    # evaluated with the fake tldr of DIR first on PATH.
    preview() {
        env -i HOME="$TEST_TMP/home" PATH="$1:/usr/bin:/bin" TERM=dumb \
            "$ZSH_BIN" -f -c '
                source $1
                zstyle -s $2 fzf-preview preview || exit 97
                word=$3 desc=$3
                eval "$preview"
            ' fzf-tab "$REPO_ROOT/home/dot_oh-my-zsh/custom/fzf-tab.zsh" "$2" "$3" 2>/dev/null
    }
    want=$(printf '\033[1mls\033[0m\nList directory contents.')
    for client in 'c:-C ls' 'tlrc:--color always ls'; do
        dir=$TEST_TMP/tldr-${client%%:*}
        online_log=
        [ "${client%%:*}" != c ] || online_log=$TLDR_ONLINE_LOG
        write_tldr "$dir" "${client#*:}" "$online_log"
        for context in ':fzf-tab:complete:tldr:argument-1' ':fzf-tab:complete:-command-:'; do
            got=$(preview "$dir" "$context" ls || true)
            if [ "$got" != "$want" ]; then
                printf 'FAIL fzf-tab %s preview with the %s client: %s\n' "$context" "${client%%:*}" \
                    "$(printf '%s' "$got" | od -c | head -n 3)" >&2
                preview_failures=$((preview_failures + 1))
            fi
            # A page no client has never shows a client's error text.
            case $(preview "$dir" "$context" no-such-page || true) in
                *"doesn't exist"*)
                    printf 'FAIL fzf-tab %s preview printed the %s client error\n' "$context" "${client%%:*}" >&2
                    preview_failures=$((preview_failures + 1))
                    ;;
            esac
        done
    done
    got=$(preview "$TEST_TMP/tldr-c" ':fzf-tab:complete:tldr:argument-1' no-such-page || true)
    if [ -n "$got" ]; then
        printf 'FAIL fzf-tab tldr preview of a missing page printed: %s\n' "$got" >&2
        preview_failures=$((preview_failures + 1))
    fi
    if [ -s "$TLDR_ONLINE_LOG" ]; then
        printf 'FAIL fzf-tab previews ran the C client without TLDR_AUTO_UPDATE_DISABLED: %s\n' \
            "$(tr '\n' ';' <"$TLDR_ONLINE_LOG")" >&2
        preview_failures=$((preview_failures + 1))
    fi
fi

# sync-payloads and sync-skills (home/dot_aliases) in each interactive
# shell, zsh without interactivecomments too (oh-my-zsh sets it, a bare zsh
# does not): a valid chezmoi config runs its source's hook, never the checkout
# at ~/dotfiles, with the arguments and exit status passed through; a home
# without a config and a config the guard refuses run no hook and say so,
# once per call. Sourcing is silent and leaves no helper variable behind.
sync_failures=0 sync_home=$TEST_TMP/sync-home
sync_refusals='[dotfiles] [error] Payload update needs ~/.config/chezmoi/chezmoi.toml; without it run sh CHECKOUT/scripts/payload-update.sh --now [ITEM...] instead.
[dotfiles] [error] ~/.config/chezmoi/chezmoi.toml does not name this home and a dotfiles checkout; payload update refused.'
mkdir -p "$sync_home/.config/chezmoi"
for checkout in "$TEST_TMP/configured" "$sync_home/dotfiles"; do
    mkdir -p "$checkout/scripts" "$checkout/lib"
    printf '%s\n' "printf '${checkout##*/} %s\\n' \"\$*\" >>\"\$SYNC_TRACE\"" 'exit 4' \
        >"$checkout/scripts/payload-update.sh"
done
printf 'home\n' >"$TEST_TMP/configured/.chezmoiroot"
cp "$REPO_ROOT/lib/chezmoi-guard.sh" "$TEST_TMP/configured/lib/"
# sync_config SOURCE: the config chezmoi init writes, naming SOURCE.
sync_config() {
    printf 'destDir = "%s"\nsourceDir = "%s"\n\n[data]\n  host = "lab-ubuntu"\n' \
        "$(cd -P "$sync_home" && pwd -P)" "$1" >"$sync_home/.config/chezmoi/chezmoi.toml"
}
for test_shell in sh dash bash zsh; do
    # The cases run with PATH=/usr/bin:/bin, so run the shell by full path.
    test_shell_path=$(command -v "$test_shell") || continue
    case $test_shell in
        bash) sync_flags=(--noprofile --norc -i) ;;
        zsh) sync_flags=(-f -i) ;;
        *) sync_flags=(-i) ;;
    esac
    for home_kind in configured unconfigured invalid; do
        rm -f "$sync_home/.config/chezmoi/chezmoi.toml" "$TEST_TMP/sync-trace"
        case $home_kind in
            configured) sync_config "$(cd -P "$TEST_TMP/configured" && pwd -P)" ;;
            invalid) sync_config "$(cd -P "$TEST_TMP/configured" && pwd -P)/" ;;
        esac
        # shellcheck disable=SC2016
        out=$(env -i HOME="$sync_home" PATH=/usr/bin:/bin TERM=dumb \
            SYNC_TRACE="$TEST_TMP/sync-trace" "$test_shell_path" "${sync_flags[@]}" -c '. "$1"
                eval "sync-payloads kit pymol"; first=$?; eval sync-skills
                printf "%s %s %s\n" "$first" "$?" "$({ if [ -n "${BASH_VERSION-}" ]; then compgen -v; else set; fi; } | grep -c "^_df_")"' aliases \
            "$REPO_ROOT/home/dot_aliases" </dev/null 2>"$TEST_TMP/sync-err") || :
        case $home_kind in
            unconfigured) sync_refusal=${sync_refusals%%$'\n'*} ;;
            *) sync_refusal=${sync_refusals#*$'\n'} ;;
        esac
        refusals=$(grep -c -F -x -e "$sync_refusal" "$TEST_TMP/sync-err" || :)
        noise=$(grep -v -F -x -e "$sync_refusal" "$TEST_TMP/sync-err" |
            grep -v -e 'job control' -e 'terminal process group' -e "access tty" -e '^stty: ' || :)
        trace=$(cat "$TEST_TMP/sync-trace" 2>/dev/null || :)
        if [ "$home_kind" = configured ]; then
            expected_out='4 4 0' expected_refusals=0 expected_trace="configured --now kit pymol"$'\n'"configured --now skills"
        else
            expected_out='1 1 0' expected_refusals=2 expected_trace=''
        fi
        if [ "$out" != "$expected_out" ] || [ "$refusals" != "$expected_refusals" ] || [ -n "$noise" ] ||
            [ "$trace" != "$expected_trace" ]; then
            printf 'FAIL sync-payloads %s (%s): out=[%s] refusals=[%s] noise=[%s] trace=[%s]\n' "$home_kind" \
                "$test_shell" "$out" "$refusals" "$noise" "$(printf '%s' "$trace" | tr '\n' ';')" >&2
            sync_failures=$((sync_failures + 1))
        fi
    done
done

# The login update through home/dot_profile (sh, dash, Bash) and the ~/.zshrc
# tail (zsh): a home without a chezmoi config runs no updater, not even one
# of a checkout at ~/dotfiles, and prints nothing; a config the guard refuses
# warns once and runs nothing; a valid config runs only its source's updater.
# No helper variable is left behind.
login_failures=0 login_home=$TEST_TMP/login-home
login_warning='[dotfiles] [warn] ~/.config/chezmoi/chezmoi.toml does not name this home and a dotfiles checkout; automatic updates skipped.'
mkdir -p "$login_home/dotfiles/scripts" "$login_home/.oh-my-zsh" "$login_home/.config/chezmoi" \
    "$TEST_TMP/login-source/scripts" "$TEST_TMP/login-source/lib"
printf 'home\n' >"$TEST_TMP/login-source/.chezmoiroot"
cp "$REPO_ROOT/lib/chezmoi-guard.sh" "$TEST_TMP/login-source/lib/"
for hook in chezmoi-update payload-update; do
    # shellcheck disable=SC2016
    printf 'printf "%%s\\n" %s >>"$LOGIN_TRACE"\n' "$hook" >"$login_home/dotfiles/scripts/$hook.sh"
    # shellcheck disable=SC2016
    printf 'printf "%%s\\n" "source %s" >>"$LOGIN_TRACE"\n' "$hook" >"$TEST_TMP/login-source/scripts/$hook.sh"
done
ln -s "$REPO_ROOT/home/dot_profile" "$login_home/.profile"
ln -s "$REPO_ROOT/home/dot_zshrc" "$login_home/.zshrc"
: >"$login_home/.oh-my-zsh/oh-my-zsh.sh"
login_source=$(cd -P "$TEST_TMP/login-source" && pwd -P)
for test_shell in sh dash bash zsh; do
    # The cases run with PATH=/usr/bin:/bin, so run the shell by full path.
    test_shell_path=$(command -v "$test_shell") || continue
    # Variables only: Bash's set also prints function bodies.
    login_leaks='{ if [ -n "${BASH_VERSION-}" ]; then compgen -v; else set; fi; } | grep -c "^_df_" || :'
    case $test_shell in
        bash) login_args=(--noprofile --norc -i -c ". \"\$HOME/.profile\"; $login_leaks") ;;
        zsh) login_args=(-d -i -c "$login_leaks") ;;
        *) login_args=(-i -c ". \"\$HOME/.profile\"; $login_leaks") ;;
    esac
    for state in unconfigured invalid configured; do
        rm -f "$TEST_TMP/login-trace" "$login_home/.config/chezmoi/chezmoi.toml"
        case $state in
            invalid) printf 'destDir = "%s"\nsourceDir = "%s"\n' "$(cd -P "$TEST_TMP" && pwd -P)" "$login_source" \
                >"$login_home/.config/chezmoi/chezmoi.toml" ;;
            configured) printf 'destDir = "%s"\nsourceDir = "%s"\n' "$(cd -P "$login_home" && pwd -P)" "$login_source" \
                >"$login_home/.config/chezmoi/chezmoi.toml" ;;
        esac
        login_rc=0
        out=$(env -i HOME="$login_home" PATH=/usr/bin:/bin TERM=dumb LOGIN_TRACE="$TEST_TMP/login-trace" \
            "$test_shell_path" "${login_args[@]}" </dev/null 2>"$TEST_TMP/login-err") || login_rc=$?
        warnings=$(grep -c -F -x -e "$login_warning" "$TEST_TMP/login-err" || :)
        noise=$(grep -v -F -x -e "$login_warning" "$TEST_TMP/login-err" |
            grep -v -e 'job control' -e 'terminal process group' -e "access tty" -e '^stty: ' || :)
        trace=$(cat "$TEST_TMP/login-trace" 2>/dev/null || :)
        case $state in
            unconfigured) expected_warnings=0 expected_trace='' ;;
            invalid) expected_warnings=1 expected_trace='' ;;
            configured) expected_warnings=0 expected_trace='source chezmoi-update' ;;
        esac
        if [ "$login_rc" != 0 ] || [ "$out" != 0 ] || [ "$warnings" != "$expected_warnings" ] || [ -n "$noise" ] ||
            [ "$trace" != "$expected_trace" ]; then
            printf 'FAIL %s login (%s): rc=%s out=[%s] warnings=[%s] noise=[%s] trace=[%s]\n' "$state" "$test_shell" \
                "$login_rc" "$out" "$warnings" "$noise" "$(printf '%s' "$trace" | tr '\n' ';')" >&2
            login_failures=$((login_failures + 1))
        fi
    done
done

[ "$nvm_failures" = 0 ] && [ "$preview_failures" = 0 ] && [ "$sync_failures" = 0 ] &&
    [ "$login_failures" = 0 ] || exit 1
echo "shell-profile=PASS"
