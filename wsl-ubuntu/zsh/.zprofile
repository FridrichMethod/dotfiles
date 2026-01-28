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
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# set PATH so it includes user's private bin
export PATH=$HOME/bin:$HOME/.local/bin:$PATH

# >>> juliaup initialize >>>

# !! Contents within this block are managed by juliaup !!

path=('/home/fridrichmethod/.juliaup/bin' $path)
export PATH

# <<< juliaup initialize <<<

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/home/fridrichmethod/miniconda3/bin/conda' 'shell.zsh' 'hook' 2>/dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/home/fridrichmethod/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/home/fridrichmethod/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/home/fridrichmethod/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# Set mamba root prefix
# mamba is installed and initialized via conda
export MAMBA_ROOT_PREFIX=$HOME/miniconda3

# cuda setup
export PATH=/usr/local/cuda/bin:$PATH

# texlive setup
export PATH=/usr/local/texlive/2024/bin/x86_64-linux:$PATH
export MANPATH=/usr/local/texlive/2024/texmf-dist/doc/man:$MANPATH
export INFOPATH=/usr/local/texlive/2024/texmf-dist/doc/info:$INFOPATH

# Oh My Zsh setup
export ZSH="$HOME/.oh-my-zsh"

# GROMACS setup
GMXRC="/usr/local/gromacs/bin/GMXRC"
if [ -f "$GMXRC" ]; then
    source "$GMXRC"
fi

# wsl browser
export BROWSER=wslview
