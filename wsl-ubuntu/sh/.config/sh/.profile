#!/bin/sh

# >>> juliaup initialize >>>

# !! Contents within this block are managed by juliaup !!

case ":$PATH:" in
    *:/home/fridrichmethod/.juliaup/bin:*) ;;

    *)
        export PATH=/home/fridrichmethod/.juliaup/bin${PATH:+:${PATH}}
        ;;
esac

# <<< juliaup initialize <<<

# texlive setup
case ":$PATH:" in
    *:/usr/local/texlive/2024/bin/x86_64-linux:*) ;;
    *) export PATH="/usr/local/texlive/2024/bin/x86_64-linux:$PATH" ;;
esac
case ":${MANPATH-}:" in
    *:/usr/local/texlive/2024/texmf-dist/doc/man:*) ;;
    *) export MANPATH="/usr/local/texlive/2024/texmf-dist/doc/man${MANPATH:+:${MANPATH}}" ;;
esac
case ":${INFOPATH-}:" in
    *:/usr/local/texlive/2024/texmf-dist/doc/info:*) ;;
    *) export INFOPATH="/usr/local/texlive/2024/texmf-dist/doc/info${INFOPATH:+:${INFOPATH}}" ;;
esac

# GROMACS setup
GMXRC="/usr/local/gromacs/bin/GMXRC"
if [ -f "$GMXRC" ]; then
    # shellcheck source=/dev/null
    . "$GMXRC"
fi

# wsl browser
export BROWSER="wslview"

# Mount across distros (WSL only)
if [ -n "${WSL_DISTRO_NAME:-}" ] && [ ! -d /mnt/wsl/"${WSL_DISTRO_NAME}" ]; then
    mkdir -p /mnt/wsl/"${WSL_DISTRO_NAME}"
    wsl.exe -d "${WSL_DISTRO_NAME}" -u root mount --bind / /mnt/wsl/"${WSL_DISTRO_NAME}"
fi
