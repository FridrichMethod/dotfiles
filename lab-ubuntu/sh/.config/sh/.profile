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
    # Under zsh, GMXRC.bash runs a bare `compinit`, which prompts
    # "insecure directories and files ... [y/n]" on every new shell because
    # the linuxbrew completion dirs are owned by another user (tinglab).
    # Force that one call to `compinit -u` (trust & load, no prompt); the
    # wrapper self-replaces with the real compinit, so Oh My Zsh's later
    # `compinit -u` and GROMACS's own gmx completions still work.
    if [ -n "${ZSH_VERSION:-}" ]; then
        compinit() {
            unfunction compinit
            autoload -Uz compinit
            compinit -u "$@"
        }
    fi
    # shellcheck source=/dev/null
    . "$GMXRC"
fi
