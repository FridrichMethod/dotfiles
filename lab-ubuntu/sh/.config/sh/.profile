#!/bin/sh

# texlive setup
case ":$PATH:" in
    *:/usr/local/texlive/2025/bin/x86_64-linux:*) ;;
    *) export PATH="/usr/local/texlive/2025/bin/x86_64-linux:$PATH" ;;
esac
case ":${MANPATH-}:" in
    *:/usr/local/texlive/2025/texmf-dist/doc/man:*) ;;
    *) export MANPATH="/usr/local/texlive/2025/texmf-dist/doc/man${MANPATH:+:${MANPATH}}" ;;
esac
case ":${INFOPATH-}:" in
    *:/usr/local/texlive/2025/texmf-dist/doc/info:*) ;;
    *) export INFOPATH="/usr/local/texlive/2025/texmf-dist/doc/info${INFOPATH:+:${INFOPATH}}" ;;
esac

# GROMACS setup
GMXRC="/apps/gromacs-2026.0/bin/GMXRC"
if [ -f "$GMXRC" ]; then
    # shellcheck source=/dev/null
    . "$GMXRC"
fi
