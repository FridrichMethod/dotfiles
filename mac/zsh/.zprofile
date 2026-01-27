#!/bin/zsh

# Recursive globbing: "**" works by default in zsh
setopt extended_glob
setopt globstarshort
setopt glob_dots

# User configuration
export MANPATH=/usr/local/man:$MANPATH

# You may need to manually set your language environment
export LANG=en_US.UTF-8

# This command sets the DYLD_LIBRARY_PATH environment variable.
# The DYLD_LIBRARY_PATH is used by the dynamic linker on macOS to find dynamic libraries (.dylib files) at runtime.
if [ -z "$DYLD_LIBRARY_PATH" ]; then
    export DYLD_LIBRARY_PATH=/opt/homebrew/lib
else
    export DYLD_LIBRARY_PATH=/opt/homebrew/lib:$DYLD_LIBRARY_PATH
fi

# set PATH so it includes user's private bin
export PATH=$HOME/bin:$HOME/.local/bin:$PATH

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/Users/zhaoyangli/miniconda3/bin/conda' 'shell.zsh' 'hook' 2>/dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/Users/zhaoyangli/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/Users/zhaoyangli/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/Users/zhaoyangli/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# Set mamba root prefix
# mamba is installed and initialized via conda
export MAMBA_ROOT_PREFIX=$HOME/miniconda3

# MATLAB setup
export MATLAB=/Applications/MATLAB_R2025b.app/bin

# Schrodinger suite setup
export SCHRODINGER=/opt/schrodinger/suites2025-2

# Oh My Zsh setup
export ZSH="$HOME/.oh-my-zsh"
