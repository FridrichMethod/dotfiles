#!/bin/sh

# --------------- Login Shell Settings ---------------

# Locale and base paths
export LANG="en_US.UTF-8"

case ":${MANPATH-}:" in
    *:/usr/local/man:*) ;;
    # An empty entry retains man's default search path when MANPATH was unset.
    *) export MANPATH="/usr/local/man:${MANPATH-}" ;;
esac

# User binaries first in PATH
case ":$PATH:" in
    *":$HOME/bin:$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/bin:$HOME/.local/bin:$PATH" ;;
esac

# nvm: put the default node's bin on PATH without sourcing nvm.sh, whose
# `nvm use default` costs ~0.5 s per shell. npm-installed CLIs (gemini, the
# Neovim node host, tree-sitter) then work in every shell and script; zsh
# also defines the nvm function (common/zsh/.oh-my-zsh/custom/nvm.zsh).
if [ -z "${NVM_DIR-}" ]; then
    if [ -d "$HOME/.nvm" ]; then
        export NVM_DIR="$HOME/.nvm"
    elif [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/nvm" ]; then
        export NVM_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvm"
    fi
fi
# Resolve `default` as `nvm use default` does, with builtins and one glob:
# follow alias files (default -> lts/* -> lts/krypton -> v24.11.1), then take
# an exact version, or the newest install for `node`/`stable` or for a
# partial version (24, v24, 24.11). Sets _nvm_bin; fails when no installed
# version matches, or while a parent shell's `nvm use` bin (NVM_BIN) is
# still on PATH. Relative LTS aliases (lts/-1) are left unresolved, so such
# a default adds nothing.
_nvm_default_bin() {
    # zsh sources this file too: keep a glob that matches nothing literal,
    # as sh does, instead of failing with "no matches found".
    if [ -n "${ZSH_VERSION-}" ]; then
        setopt local_options no_nomatch
    fi
    if [ -n "${NVM_BIN-}" ]; then
        case ":$PATH:" in *":$NVM_BIN:"*) return 1 ;; esac
    fi
    _nvm_version=default
    _nvm_hops=0
    while [ -f "$NVM_DIR/alias/$_nvm_version" ] && [ -r "$NVM_DIR/alias/$_nvm_version" ]; do
        [ "$_nvm_hops" -lt 8 ] || return 1
        IFS= read -r _nvm_version <"$NVM_DIR/alias/$_nvm_version" || [ -n "$_nvm_version" ] || return 1
        _nvm_hops=$((_nvm_hops + 1))
    done
    _nvm_version=${_nvm_version#v}
    case $_nvm_version in
        node | stable) _nvm_version= ;;
        '' | .* | *..* | *[!0-9.]* | *.*.*.*) return 1 ;;
        *.*.?*)
            _nvm_bin=$NVM_DIR/versions/node/v$_nvm_version/bin
            [ -x "$_nvm_bin/node" ]
            return
            ;;
        *) _nvm_version=${_nvm_version%.}. ;;
    esac
    _nvm_bin=
    _nvm_best=-1
    # bash's failglob would print "no match" for a version not installed.
    # shopt is a bash builtin, so this costs no fork.
    _nvm_failglob=
    # shellcheck disable=SC3044
    if [ -n "${BASH_VERSION-}" ] && shopt -q failglob; then
        _nvm_failglob=1
        shopt -u failglob
    fi
    for _nvm_dir in "$NVM_DIR/versions/node/v$_nvm_version"*; do
        _nvm_name=${_nvm_dir##*/v}
        # Only complete vX.Y.Z installs; leading zeros would read as octal.
        case $_nvm_name in
            .* | *. | *..* | *[!0-9.]* | *.*.*.* | 0[0-9]* | *.0[0-9]*) continue ;;
            *.*.*) [ -x "$_nvm_dir/bin/node" ] || continue ;;
            *) continue ;;
        esac
        _nvm_rest=${_nvm_name#*.}
        _nvm_key=$(((${_nvm_name%%.*} * 1000000 + ${_nvm_rest%.*}) * 1000000 + ${_nvm_rest#*.}))
        if [ "$_nvm_key" -gt "$_nvm_best" ]; then
            _nvm_best=$_nvm_key
            _nvm_bin=$_nvm_dir/bin
        fi
    done
    # shellcheck disable=SC3044
    [ -z "$_nvm_failglob" ] || shopt -s failglob
    [ -n "$_nvm_bin" ]
}
if [ -n "${NVM_DIR-}" ] && _nvm_default_bin; then
    case ":$PATH:" in
        *":$_nvm_bin:"*) ;;
        *) export PATH="$_nvm_bin:$PATH" ;;
    esac
fi
unset -f _nvm_default_bin
unset _nvm_version _nvm_hops _nvm_bin _nvm_best _nvm_dir _nvm_name _nvm_rest _nvm_key _nvm_failglob

# CUDA setup
if [ -d /usr/local/cuda/bin ]; then
    case ":$PATH:" in
        *:/usr/local/cuda/bin:*) ;;
        *) export PATH="/usr/local/cuda/bin:$PATH" ;;
    esac
fi

# Load host-specific login configuration
if [ -r "$HOME/.config/sh/.profile" ]; then
    . "$HOME/.config/sh/.profile"
fi

# Both shells use the same home binding. zsh calls this after ssh-agent/env
# setup; bash/sh calls it here. Maintenance survives unrelated future logins.
_dotfiles_login_updates() {
    case $- in *i*) ;; *) return 0 ;; esac
    if [ -e "$HOME/.config/dotfiles/maintenance" ] || [ -L "$HOME/.config/dotfiles/maintenance" ]; then
        return 0
    fi
    _df_hook_root=${DOTFILES_DIR:-$HOME/dotfiles}
    _df_update=$_df_hook_root/scripts/dotfiles-update.sh
    if [ -e "$HOME/.config/dotfiles/native" ] || [ -L "$HOME/.config/dotfiles/native" ]; then
        # Read only enough to locate the shared validator. Any malformed marker
        # prevents both dispatches; it never falls back to the legacy writer.
        if ! _df_hook_root=$(
            [ -f "$HOME/.config/dotfiles/native" ] && [ ! -L "$HOME/.config/dotfiles/native" ] || exit 1
            {
                IFS= read -r _df_version && IFS= read -r _df_home && IFS= read -r _df_root
            } <"$HOME/.config/dotfiles/native" || exit 1
            [ "$_df_version" = dotfiles-chezmoi-v1 ] || exit 1
            [ "${_df_root#/}" != "$_df_root" ] || exit 1
            [ -r "$_df_root/lib/chezmoi-guard.sh" ] || exit 1
            # shellcheck source=/dev/null
            . "$_df_root/lib/chezmoi-guard.sh"
            dotfiles_native_source "$HOME"
        ); then
            printf '%s\n' '[dotfiles] [warn] Native home binding is invalid; automatic updates skipped.' >&2
            unset _df_hook_root _df_update
            return 0
        fi
        _df_update=$_df_hook_root/scripts/chezmoi-update.sh
        if [ ! -r "$_df_update" ]; then
            printf '%s\n' '[dotfiles] [warn] Native updater is unavailable; inspect the source checkout.' >&2
        fi
    fi
    if [ -r "$_df_update" ]; then
        # shellcheck source=/dev/null
        . "$_df_update"
    fi
    # Keep payload scheduling separate from the native dotfiles update policy.
    _df_payload=$_df_hook_root/scripts/payload-update.sh
    if [ -r "$_df_payload" ]; then
        # shellcheck source=/dev/null
        . "$_df_payload"
    fi
    unset _df_hook_root _df_update _df_payload
}
if [ -z "${ZSH_VERSION:-}" ]; then
    _dotfiles_login_updates
    unset -f _dotfiles_login_updates
fi
