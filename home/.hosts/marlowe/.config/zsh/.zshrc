#!/bin/zsh

# Initialize Lmod module system for zsh.
# Bash gets this from /etc/profile → /etc/profile.d/*.sh, but zsh
# does not source /etc/profile so the `module` function is undefined.
if ((! $+functions[module])) && [[ -f /usr/share/lmod/lmod/init/zsh ]]; then
    source /usr/share/lmod/lmod/init/zsh
fi

# Load the site's default modules (Slurm and the default compiler). Only
# /etc/bash.bashrc names them, in LMOD_SYSTEM_DEFAULT_MODULES, and /etc/profile
# reads that file only for an interactive bash, so a zsh started from another
# shell (the workstation ssh RemoteCommand's `bash -c`, `bash -lc`) inherits
# Lmod's MODULEPATH with nothing loaded. A throwaway bash reads the list: the
# command sets PS1, which a non-interactive bash drops when inherited, and
# empties BASH_ENV, which /etc/profile points at Lmod's bash init. Unless a
# module is already loaded, the list is then loaded as the site's profile
# loads it, before conda and the login env go on PATH so that they stay ahead
# of the module paths. The exported list marks the session: a nested shell, or
# one started from an interactive bash, skips this, so `module purge` holds
# there. Without MODULEPATH, Lmod could not find the modules. Lmod reports a
# failed load itself.
if (($+functions[module])) && [[ -n ${MODULEPATH-} && -z ${LMOD_SYSTEM_DEFAULT_MODULES-} &&
    -r /etc/bash.bashrc ]]; then
    _lmod_default_modules=$(BASH_ENV= /bin/bash --noprofile --norc -c \
        'PS1=1; . "$1" >/dev/null 2>&1; printf %s "${LMOD_SYSTEM_DEFAULT_MODULES-}"' \
        bash /etc/bash.bashrc </dev/null 2>/dev/null)
    if [[ -n $_lmod_default_modules ]]; then
        export LMOD_SYSTEM_DEFAULT_MODULES=$_lmod_default_modules
        if [[ -z ${LOADEDMODULES-} ]]; then
            module --initial_load restore
        fi
    fi
    unset _lmod_default_modules
fi

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$("$HOME/miniconda3/bin/conda" 'shell.zsh' 'hook' 2>/dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
        . "$HOME/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="$HOME/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# shfmt: off
# >>> mamba initialize >>>
# !! Contents within this block are managed by 'micromamba shell init' !!
export MAMBA_EXE="$HOME/.local/bin/micromamba"
export MAMBA_ROOT_PREFIX="$HOME/micromamba"
__mamba_setup="$("$MAMBA_EXE" shell hook --shell zsh --root-prefix "$MAMBA_ROOT_PREFIX" 2>/dev/null)"
if [ $? -eq 0 ]; then
    eval "$__mamba_setup"
else
    alias micromamba='"$MAMBA_EXE"' # Fallback on help from micromamba activate
fi
unset __mamba_setup
# <<< mamba initialize <<<
# shfmt: on

export PATH="$MAMBA_ROOT_PREFIX/envs/login/bin:$PATH"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

typeset -ga plugins

plugins+=(
    snap
    ubuntu
)
