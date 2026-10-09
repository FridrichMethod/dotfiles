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

# GROMACS: export what GMXRC would (bin, lib, man, data, pkg-config) without
# sourcing it. Under zsh, GMXRC.bash runs compinit twice (~0.3 s per shell)
# and leaves `setopt shwordsplit` on for the whole session. Values are plain
# exports, so scripts and child processes still find gmx; the shell rc files
# load gmx completion from $GMXBIN.
if [ -x "/apps/gromacs-2026.0/bin/gmx" ]; then
    export GROMACS_DIR="/apps/gromacs-2026.0"
    export GMXBIN="$GROMACS_DIR/bin" GMXLDLIB="$GROMACS_DIR/lib"
    export GMXMAN="$GROMACS_DIR/share/man" GMXDATA="$GROMACS_DIR/share/gromacs"
    case ":$PATH:" in
        *:"$GMXBIN":*) ;;
        *) export PATH="$GMXBIN:$PATH" ;;
    esac
    case ":${LD_LIBRARY_PATH-}:" in
        *:"$GMXLDLIB":*) ;;
        *) export LD_LIBRARY_PATH="$GMXLDLIB${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" ;;
    esac
    case ":${PKG_CONFIG_PATH-}:" in
        *:"$GMXLDLIB/pkgconfig":*) ;;
        *) export PKG_CONFIG_PATH="$GMXLDLIB/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}" ;;
    esac
    # A trailing colon keeps man's default search path, as GMXRC does.
    case ":${MANPATH-}:" in
        *:"$GMXMAN":*) ;;
        *) export MANPATH="$GMXMAN:${MANPATH-}" ;;
    esac
fi
