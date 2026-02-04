#!/bin/zsh

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/users/zyli2002/miniconda3/bin/conda' 'shell.zsh' 'hook' 2>/dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/users/zyli2002/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/users/zyli2002/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/users/zyli2002/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# >>> mamba initialize >>>
# !! Contents within this block are managed by 'micromamba shell init' !!
export MAMBA_EXE='/users/zyli2002/.local/bin/micromamba';
export MAMBA_ROOT_PREFIX='/users/zyli2002/micromamba';
__mamba_setup="$("$MAMBA_EXE" shell hook --shell zsh --root-prefix "$MAMBA_ROOT_PREFIX" 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__mamba_setup"
else
    alias micromamba="$MAMBA_EXE"  # Fallback on help from micromamba activate
fi
unset __mamba_setup
# <<< mamba initialize <<<

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
