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
# loads the nvm function itself on first use (oh-my-zsh nvm plugin, lazy).
# Follows alias files (default -> lts/* -> lts/krypton -> v24.11.1) with the
# read builtin; a default that names no installed version adds nothing.
_nvm_root="${NVM_DIR:-$HOME/.nvm}"
if [ -z "${NVM_BIN-}" ] && [ -r "$_nvm_root/alias/default" ]; then
    _nvm_version=default
    _nvm_hops=0
    while [ ! -d "$_nvm_root/versions/node/$_nvm_version" ] &&
        [ -r "$_nvm_root/alias/$_nvm_version" ] && [ "$_nvm_hops" -lt 8 ]; do
        IFS= read -r _nvm_version <"$_nvm_root/alias/$_nvm_version" || [ -n "$_nvm_version" ]
        _nvm_hops=$((_nvm_hops + 1))
    done
    if [ -n "$_nvm_version" ] && [ -d "$_nvm_root/versions/node/$_nvm_version/bin" ]; then
        case ":$PATH:" in
            *":$_nvm_root/versions/node/$_nvm_version/bin:"*) ;;
            *) export PATH="$_nvm_root/versions/node/$_nvm_version/bin:$PATH" ;;
        esac
    fi
    unset _nvm_version _nvm_hops
fi
unset _nvm_root

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

# Dotfiles auto-update check (bash/sh only; zsh runs it at end of .zshrc)
if [ -z "${ZSH_VERSION:-}" ]; then
    _df_update="${DOTFILES_DIR:-$HOME/dotfiles}/scripts/dotfiles-update.sh"
    if [ -r "$_df_update" ]; then
        # shellcheck source=/dev/null
        . "$_df_update"
    fi
    unset _df_update

    # Awesome-skills weekly sync (bash/sh only; zsh sources from .zshrc tail)
    _as_update="${DOTFILES_DIR:-$HOME/dotfiles}/scripts/awesome-skills-update.sh"
    if [ -r "$_as_update" ]; then
        # shellcheck source=/dev/null
        . "$_as_update"
    fi
    unset _as_update
fi
