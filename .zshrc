#!/bin/zsh

# Recursive globbing: "**" works by default in zsh
setopt extended_glob
setopt globstarshort
setopt glob_dots

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# tar alias
alias targz='tar -czvf'
alias untargz='tar -xzvf'

# python alias
alias python='python3'

# nvim alias
alias vi='nvim'

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ks='ls'

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# ssh for kitty
alias ssh='TERM=xterm-256color ssh'

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

# User configuration

export MANPATH=/usr/local/man:$MANPATH

# This command sets the DYLD_LIBRARY_PATH environment variable.
# The DYLD_LIBRARY_PATH is used by the dynamic linker on macOS to find dynamic libraries (.dylib files) at runtime.
export DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH:/opt/homebrew/lib

# You may need to manually set your language environment
export LANG=en_US.UTF-8

# MATLAB
export MATLAB=/Applications/MATLAB_R2025b.app/bin

# Schrodinger
export SCHRODINGER=/opt/schrodinger/suites2025-2

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/Users/zhaoyangli/miniconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/Users/zhaoyangli/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/Users/zhaoyangli/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/Users/zhaoyangli/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# --------------- Interactive Session Settings ---------------

# Enable the subsequent settings only in interactive sessions
case $- in
    *i*) ;;
    *) return ;;
esac

# Disable software flow control
stty -ixon

# History settings (zsh)
HISTFILE=~/.zsh_history
HISTSIZE=1000 # in-memory history size
SAVEHIST=2000 # lines to save to HISTFILE

setopt APPEND_HISTORY # append to history file
# setopt INC_APPEND_HISTORY   # uncomment to write incrementally
setopt HIST_IGNORE_SPACE # ignore commands starting with space
setopt HIST_IGNORE_DUPS  # ignore duplicate commands

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )
ZSH_THEME="powerlevel10k/powerlevel10k"

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
    # debian
    # snap
    # thefuck
    # ubuntu
    # z
    # zsh-completions
    # zsh-interactive-cd
    # zsh-navigation-tools
    1password
    aliases
    autopep8
    colored-man-pages
    conda
    copybuffer
    copyfile
    copypath
    docker
    emacs
    emoji
    extract
    fzf
    fzf-tab
    git
    github
    history
    man
    node
    npm
    nvm
    pip
    pylint
    python
    rsync
    rust
    ssh
    sudo
    timer
    tldr
    tmux
    uv
    vscode
    web-search
    you-should-use
    zoxide
    zsh-autosuggestions
    zsh-history-substring-search
    zsh-syntax-highlighting
)

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

# Set the position of the YSU message
export YSU_MESSAGE_POSITION="after"

# disable sort when completing `git checkout`
zstyle ':completion:*:git-checkout:*' sort false
# set descriptions format to enable group support
# NOTE: don't use escape sequences (like '%F{red}%d%f') here, fzf-tab will ignore them
zstyle ':completion:*:descriptions' format '[%d]'
# set list-colors to enable filename colorizing
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
# force zsh not to show completion menu, which allows fzf-tab to capture the unambiguous prefix
zstyle ':completion:*' menu no
# preview directory's content with eza when completing cd
zstyle ':fzf-tab:complete:*' fzf-preview 'fzf-preview.sh $realpath'
# custom fzf flags
# NOTE: fzf-tab does not follow FZF_DEFAULT_OPTS by default
zstyle ':fzf-tab:*' fzf-flags \
    --height=60% \
    --layout=reverse \
    --style=full \
    --border \
    --padding=1,2 \
    --input-label=' Input ' \
    --header-label=' File Type ' \
    --bind='result:transform-list-label: if [[ -z $FZF_QUERY ]]; then echo " $FZF_MATCH_COUNT items "; else echo " $FZF_MATCH_COUNT matches for [$FZF_QUERY] "; fi' \
    --bind='focus:transform-preview-label:[[ -n {} ]] && printf " Previewing [%s] " {}' \
    --bind='focus:+transform-header:file --brief {} || echo "No file selected"' \
    --bind='ctrl-r:change-list-label( Reloading the list )+reload(sleep 2; git ls-files)' \
    --color='border:#aaaaaa,label:#cccccc' \
    --color='preview-border:#9999cc,preview-label:#ccccff' \
    --color='list-border:#669966,list-label:#99cc99' \
    --color='input-border:#996666,input-label:#ffcccc' \
    --color='header-border:#6699cc,header-label:#99ccff' \
    --preview-window=right,60%,wrap,border \
    --bind=tab:accept  # Accept selection with tab
# To make fzf-tab follow FZF_DEFAULT_OPTS.
# NOTE: This may lead to unexpected behavior since some flags break this plugin. See Aloxaf/fzf-tab#455.
# zstyle ':fzf-tab:*' use-fzf-default-opts yes
# switch group using `<` and `>`
zstyle ':fzf-tab:*' switch-group '<' '>'
# use tmux popup for preview
zstyle ':fzf-tab:*' fzf-command ftb-tmux-popup

# NVM setup
zstyle ':omz:plugins:nvm' lazy yes
zstyle ':omz:plugins:nvm' autoload yes
zstyle ':omz:plugins:nvm' silent-autoload yes # optionally remove the output generated by NVM when autoloading

# Load the zsh-completions plugin
fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src
autoload -U compinit && compinit

source $ZSH/oh-my-zsh.sh

# disable special dirs
zstyle ':completion:*' special-dirs false

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
