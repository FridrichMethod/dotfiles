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
export PATH="/usr/local/texlive/2024/bin/x86_64-linux:$PATH"
export MANPATH="/usr/local/texlive/2024/texmf-dist/doc/man:$MANPATH"
export INFOPATH="/usr/local/texlive/2024/texmf-dist/doc/info:$INFOPATH"

# GROMACS setup
GMXRC="/usr/local/gromacs/bin/GMXRC"
if [ -f "$GMXRC" ]; then
    . "$GMXRC"
fi

# wsl browser
export BROWSER="wslview"

# Mount across distros
if [ ! -d /mnt/wsl/"${WSL_DISTRO_NAME}" ]; then
    mkdir -p /mnt/wsl/"${WSL_DISTRO_NAME}"
    wsl.exe -d "${WSL_DISTRO_NAME}" -u root mount --bind / /mnt/wsl/"${WSL_DISTRO_NAME}"
fi
