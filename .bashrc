#!/bin/bash

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
shopt -s globstar

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Quickly clean zone identifier files after copy and paste
alias clean_zone_identifier='fd -u -t f -g "*:Zone.Identifier*" -X rm -f'

# tar alias
alias targz='tar -czvf'
alias untargz='tar -xzvf'

# python alias
alias python='python3'

# nvim alias
alias vi='nvim'

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/home/fridrichmethod/miniconda3/bin/conda' 'shell.bash' 'hook' 2>/dev/null)"
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

# Disable auto-activation of base conda environment
# conda config --set auto_activate false

# Disable conda prompt modification
# conda config --set changeps1 False

# >>> mamba initialize >>>
# !! Contents within this block are managed by 'mamba shell init' !!
export MAMBA_EXE='/home/fridrichmethod/miniconda3/bin/mamba'
export MAMBA_ROOT_PREFIX='/home/fridrichmethod/.local/share/mamba'
__mamba_setup="$("$MAMBA_EXE" shell hook --shell bash --root-prefix "$MAMBA_ROOT_PREFIX" 2>/dev/null)"
if [ $? -eq 0 ]; then
  eval "$__mamba_setup"
else
  alias mamba="$MAMBA_EXE" # Fallback on help from mamba activate
fi
unset __mamba_setup
# <<< mamba initialize <<<

# Set the conda and mamba root prefix
export MAMBA_ROOT_PREFIX="$HOME/miniconda3"

# >>> juliaup initialize >>>

# !! Contents within this block are managed by juliaup !!

case ":$PATH:" in
*:/home/fridrichmethod/.juliaup/bin:*) ;;

*)
  export PATH=/home/fridrichmethod/.juliaup/bin${PATH:+:${PATH}}
  ;;
esac

# <<< juliaup initialize <<<

# User configuration
export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# ssh setup
# if [ -z "$SSH_AUTH_SOCK" ]; then
#   eval "$(ssh-agent -s)"
#   ssh-add ~/.ssh/id_rsa
# fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ]; then
  PATH="$HOME/bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ]; then
  PATH="$HOME/.local/bin:$PATH"
fi

# Homebrew setup
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# GPG setup
GPG_TTY=$(tty)
export GPG_TTY

# Neovim setup
export PATH=/opt/nvim-linux-x86_64/bin:$PATH

# CUDA setup
export PATH=/usr/local/cuda/bin:$PATH
# export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# OpenMPI setup
export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu/openmpi/lib:$LD_LIBRARY_PATH

# TeX setup
export PATH=/usr/local/texlive/2024/bin/x86_64-linux:$PATH
export MANPATH=/usr/local/texlive/2024/texmf-dist/doc/man:$MANPATH
export INFOPATH=/usr/local/texlive/2024/texmf-dist/doc/info:$INFOPATH

# wsl browser
export BROWSER=wslview

# GROMACS setup
GMXRC="/usr/local/gromacs/bin/GMXRC"
if [ -f "$GMXRC" ]; then
  source "$GMXRC"
fi

# --------------- Interactive Session Settings ---------------

# Enable the subsequent settings only in interactive sessions
case $- in
*i*) ;;
*) return ;;
esac

# Disable software flow control
stty -ixon

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
  debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
xterm-color | *-256color) color_prompt=yes ;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
  if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
    # We have color support; assume it's compliant with Ecma-48
    # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
    # a case would tend to support setf rather than setaf.)
    color_prompt=yes
  else
    color_prompt=
  fi
fi

if [ "$color_prompt" = yes ]; then
  PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
  PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm* | rxvt*)
  PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
  ;;
*) ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
  test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
  alias ls='ls --color=auto'
  #alias dir='dir --color=auto'
  #alias vdir='vdir --color=auto'

  alias grep='grep --color=auto'
  alias fgrep='fgrep --color=auto'
  alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
  . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# fzf configuration
export FZF_DEFAULT_OPTS="$(
  cat <<'EOF'
--height 60%
--layout=reverse
--style full
--border
--padding 1,2
--input-label ' Input '
--header-label ' File Type '
--preview 'fzf-preview.sh {}'
--bind 'result:transform-list-label:
    if [[ -z $FZF_QUERY ]]; then
        echo " $FZF_MATCH_COUNT items "
    else
        echo " $FZF_MATCH_COUNT matches for [$FZF_QUERY] "
    fi
    '
--bind 'focus:transform-preview-label:[[ -n {} ]] && printf " Previewing [%s] " {}'
--bind 'focus:+transform-header:file --brief {} || echo "No file selected"'
--color 'border:#aaaaaa,label:#cccccc'
--color 'preview-border:#9999cc,preview-label:#ccccff'
--color 'list-border:#669966,list-label:#99cc99'
--color 'input-border:#996666,input-label:#ffcccc'
--color 'header-border:#6699cc,header-label:#99ccff'
--preview-window=right,60%,wrap,border
EOF
)"
export FZF_ALT_C_OPTS="$(
  cat <<'EOF'
--preview 'tree -C -L 1 {} | head -200'
EOF
)"
export FZF_CTRL_R_OPTS="$(
  cat <<'EOF'
--preview 'echo {}'
--bind 'ctrl-y:execute-silent(echo -n {2..} | pbcopy)+abort'
EOF
)"

# Command to run when invoking Ctrl-T
export FZF_CTRL_T_COMMAND='fd --hidden --max-depth 1 --strip-cwd-prefix'

# Options to fzf command
export FZF_COMPLETION_OPTS='--border --info=inline'

# Options for path completion (e.g. vim **<TAB>)
export FZF_COMPLETION_PATH_OPTS='--walker file,dir,follow,hidden'

# Options for directory completion (e.g. cd **<TAB>)
export FZF_COMPLETION_DIR_OPTS='--walker dir,follow'
