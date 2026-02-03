#!/bin/sh

# texlive setup
export PATH=/usr/local/texlive/2025/bin/x86_64-linux:"$PATH"
export MANPATH=/usr/local/texlive/2025/texmf-dist/doc/man:"$MANPATH"
export INFOPATH=/usr/local/texlive/2025/texmf-dist/doc/info:"$INFOPATH"

# GROMACS setup
GMXRC="/apps/gromacs-2026.0/bin/GMXRC"
if [ -f "$GMXRC" ]; then
    . "$GMXRC"
fi
