#!/bin/sh

# --------------- Login Shell Settings ---------------

# Locale and base paths
export LANG="en_US.UTF-8"

case ":${MANPATH-}:" in
    *:/usr/local/man:*) ;;
    *) export MANPATH="/usr/local/man${MANPATH:+:${MANPATH}}" ;;
esac

# User binaries first in PATH
case ":$PATH:" in
    *":$HOME/bin:$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/bin:$HOME/.local/bin:$PATH" ;;
esac

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
    _df_update="${DOTFILES_DIR:-$HOME/dotfiles}/dotfiles-update.sh"
    if [ -r "$_df_update" ]; then
        # shellcheck source=/dev/null
        . "$_df_update"
    fi
    unset _df_update

    # Awesome-skills weekly sync (bash/sh only; zsh sources from .zshrc tail)
    _as_update="${DOTFILES_DIR:-$HOME/dotfiles}/awesome-skills-update.sh"
    if [ -r "$_as_update" ]; then
        # shellcheck source=/dev/null
        . "$_as_update"
    fi
    unset _as_update
fi
