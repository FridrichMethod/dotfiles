#!/bin/zsh

# --------------- Login Shell Settings ---------------

# Locale and base paths
export LANG="en_US.UTF-8"
export MANPATH="/usr/local/man${MANPATH:+:${MANPATH}}"

# Homebrew (Linuxbrew) environment
if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# CUDA setup
if [[ -d /usr/local/cuda/bin ]]; then
    export PATH="/usr/local/cuda/bin:$PATH"
fi

# User binaries first in PATH
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"

# Load host-specific login configuration
if [[ -r "$HOME/.config/zsh/.zprofile" ]]; then
    source "$HOME/.config/zsh/.zprofile"
fi
