#!/bin/zsh

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/home/fridrichmethod/miniconda3/bin/conda' 'shell.zsh' 'hook' 2>/dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/home/fridrichmethod/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/home/fridrichmethod/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/home/fridrichmethod/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
  debian_chroot=$(cat /etc/debian_chroot)
fi

typeset -ga plugins

# Host-specific plugins (added before order-sensitive plugins)
plugins+=(
    snap
    ssh-agent
    ubuntu
)
