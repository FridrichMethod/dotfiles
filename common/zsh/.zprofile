#!/bin/zsh

# Recursive globbing: "**" works by default in zsh
setopt extended_glob
setopt globstarshort
setopt glob_dots

# User configuration
export MANPATH=/usr/local/man:$MANPATH

# You may need to manually set your language environment
export LANG=en_US.UTF-8

# homebrew setup
if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# cuda setup
if [[ -d /usr/local/cuda/bin ]]; then
    export PATH="/usr/local/cuda/bin:$PATH"
fi

# Set PATH so it includes user's private bin
export PATH=$HOME/bin:$HOME/.local/bin:$PATH

# Load host-specific configuration
if [[ -r "$HOME/.config/zsh/.zprofile" ]]; then
    source "$HOME/.config/zsh/.zprofile"
fi

# Oh My Zsh setup
export ZSH="$HOME/.oh-my-zsh"
