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
export MAMBA_EXE='/home/fridrichmethod/miniconda3/bin/mamba';
export MAMBA_ROOT_PREFIX='/home/fridrichmethod/miniconda3';
__mamba_setup="$("$MAMBA_EXE" shell hook --shell zsh --root-prefix "$MAMBA_ROOT_PREFIX" 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__mamba_setup"
else
    alias mamba="$MAMBA_EXE"  # Fallback on help from mamba activate
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
# open in the same directory. Report on every cd (chpwd) and once at the first
# prompt, so the starting directory is known too. Never write to a non-terminal
# or from a subshell: command substitutions must not capture the escape, and
# `( cd dir; ... )` must not report a directory this shell never entered.
# _is_agent_session comes from ~/.zshrc, which sources this file.
if [[ -o interactive && -n ${WT_SESSION:-} && -z ${TERM_PROGRAM:-} ]] &&
    [[ -n ${commands[wslpath]-} ]] && ! _is_agent_session; then
    _wt_report_cwd() {
        [[ -t 1 ]] || return 0
        ((ZSH_SUBSHELL == 0)) || return 0
        local win_pwd
        win_pwd=$(wslpath -w "$PWD" 2>/dev/null) || return 0
        builtin printf '\e]9;9;%s\e\\' "$win_pwd"
    }
    # The first precmd still runs while the Powerlevel10k instant prompt has
    # stdout redirected to its capture file (p10k restores it only after the
    # precmd hooks), so send that one report to the terminal p10k saved.
    _wt_report_cwd_first() {
        add-zsh-hook -d precmd _wt_report_cwd_first
        local fd=${__p9k_fd_1:-}
        if [[ -n ${__p9k_instant_prompt_active:-} && -n $fd && $fd != *[!0-9]* && -t $fd ]]; then
            _wt_report_cwd >&$fd
        else
            _wt_report_cwd
        fi
    }
    autoload -Uz add-zsh-hook
    add-zsh-hook chpwd _wt_report_cwd
    add-zsh-hook precmd _wt_report_cwd_first
fi
