#!/bin/sh

# --------------- Login Shell Settings ---------------

# Locale and base paths
export LANG="en_US.UTF-8"
export MANPATH="/usr/local/man${MANPATH:+:${MANPATH}}"

# User binaries first in PATH
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"

# CUDA setup
if [ -d /usr/local/cuda/bin ]; then
    export PATH="/usr/local/cuda/bin:$PATH"
fi

# Load host-specific login configuration
if [ -r "$HOME/.config/sh/.profile" ]; then
    . "$HOME/.config/sh/.profile"
fi

# Dotfiles auto-update check
_df_update="${DOTFILES_DIR:-$HOME/dotfiles}/dotfiles-update.sh"
if [ -r "$_df_update" ]; then
    . "$_df_update"
fi
unset _df_update
