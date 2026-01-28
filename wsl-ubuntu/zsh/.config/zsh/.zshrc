#!/bin/zsh

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
