#!/bin/zsh

# Homebrew (Linuxbrew) environment
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

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

# shfmt: off
# >>> mamba initialize >>>
# !! Contents within this block are managed by 'mamba shell init' !!
export MAMBA_EXE='/home/fridrichmethod/miniconda3/bin/mamba'
export MAMBA_ROOT_PREFIX='/home/fridrichmethod/miniconda3'
__mamba_setup="$("$MAMBA_EXE" shell hook --shell zsh --root-prefix "$MAMBA_ROOT_PREFIX" 2>/dev/null)"
if [ $? -eq 0 ]; then
    eval "$__mamba_setup"
else
    alias mamba="$MAMBA_EXE" # Fallback on help from mamba activate
fi
unset __mamba_setup
# <<< mamba initialize <<<
# shfmt: on

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

# Windows Terminal: report the cwd with OSC 9;9 so duplicated tabs and panes
# open in the same directory. Report from precmd at every prompt, as Microsoft
# documents: the terminal keeps only the last report, which a nested shell, an
# ssh session or a Windows program may have sent, and a chpwd hook would miss
# `cd dir >/dev/null` and `cd -q`. Cache the wslpath conversion per $PWD, so
# only a directory change forks. The first precmd still runs while the
# Powerlevel10k instant prompt has stdout redirected to its capture file, so
# write to the terminal p10k saved.
# _is_agent_session comes from ~/.zshrc, which sources this file.
if [[ -o interactive && -n ${WT_SESSION:-} && -z ${TERM_PROGRAM:-} ]] &&
    [[ -n ${commands[wslpath]-} ]] && ! _is_agent_session; then
    typeset -g _wt_cwd_pwd= _wt_cwd_win=
    _wt_report_cwd() {
        local fd=1
        if [[ -n ${__p9k_instant_prompt_active:-} && ${__p9k_fd_1:-x} != *[!0-9]* ]]; then
            fd=$__p9k_fd_1
        fi
        [[ -t $fd ]] || return 0
        if [[ $PWD != "$_wt_cwd_pwd" ]]; then
            _wt_cwd_pwd=$PWD
            _wt_cwd_win=$(wslpath -w "$PWD" 2>/dev/null) || _wt_cwd_win=
        fi
        [[ -n $_wt_cwd_win ]] || return 0
        builtin printf '\e]9;9;%s\e\\' "$_wt_cwd_win" >&$fd
    }
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _wt_report_cwd
fi
