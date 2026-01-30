#!/bin/zsh

# Set mamba root prefix
# mamba is installed and initialized via conda
export MAMBA_ROOT_PREFIX=/apps/miniconda3

# texlive setup
export PATH=/usr/local/texlive/2025/bin/x86_64-linux:$PATH
export MANPATH=/usr/local/texlive/2025/texmf-dist/doc/man:$MANPATH
export INFOPATH=/usr/local/texlive/2025/texmf-dist/doc/info:$INFOPATH
