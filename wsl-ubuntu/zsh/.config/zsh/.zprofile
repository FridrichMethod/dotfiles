#!/bin/zsh

# Recursive globbing: "**" works by default in zsh
setopt extended_glob
setopt globstarshort
setopt glob_dots

# >>> juliaup initialize >>>

# !! Contents within this block are managed by juliaup !!

path=('/home/fridrichmethod/.juliaup/bin' $path)
export PATH

# <<< juliaup initialize <<<

# Set mamba root prefix
# mamba is installed and initialized via conda
export MAMBA_ROOT_PREFIX=$HOME/miniconda3

# texlive setup
export PATH=/usr/local/texlive/2024/bin/x86_64-linux:$PATH
export MANPATH=/usr/local/texlive/2024/texmf-dist/doc/man:$MANPATH
export INFOPATH=/usr/local/texlive/2024/texmf-dist/doc/info:$INFOPATH

# GROMACS setup
GMXRC="/usr/local/gromacs/bin/GMXRC"
if [ -f "$GMXRC" ]; then
    source "$GMXRC"
fi

# wsl browser
export BROWSER=wslview
