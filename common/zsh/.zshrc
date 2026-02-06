#!/bin/zsh

source "$HOME/.profile"

# --------------- Interactive Shell Settings ---------------

# Enable the subsequent settings only in interactive sessions
case $- in
    *i*) ;;
    *) return ;;
esac

# Disable software flow control
# This prevents Ctrl-S from freezing the terminal
# Should be set at the very top of interactive session settings
stty -ixon

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-$(print -P %n).zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-$(print -P %n).zsh"
fi

# Recursive globbing: "**" works by default in zsh
setopt extended_glob
setopt globstarshort
setopt glob_dots

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

# Download files/dirs from remote -> local ~/Downloads/
download() {
    if (( $# == 0 )); then
        print -u2 "usage: download <file_or_dir> [more_files_or_dirs...]"
        return 2
    fi

    if ! command -v kitten >/dev/null 2>&1; then
        print -u2 "download: 'kitten' not found. Tip: login using 'kitten ssh user@host' (recommended) or install kitty/kitten on this remote."
        return 127
    fi

    # NOTE:
    # - Destination 'Downloads/' is interpreted on the RECEIVING side (your local machine).
    # - Do NOT use ~/Downloads here; it will be expanded on the remote and may map to /home/... on local.
    kitten transfer \
        --transmit-deltas \
        --compress=auto \
        --confirm-paths=no \
        "$@" \
        Downloads/
}

# --------------- Oh My Zsh ---------------

# Oh My Zsh setup
export ZSH="$HOME/.oh-my-zsh"

# Disable compinit to suppress insecure warnings
ZSH_DISABLE_COMPFIX=true

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"

ENABLE_CORRECTION="true"
COMPLETION_WAITING_DOTS="true"
HIST_STAMPS="mm/dd/yyyy"

# Update automatically without asking
zstyle ':omz:update' mode auto

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
    # fzf-tab-source  # config manually
    # gitfast  # deprecated?
    # thefuck  # for fun
    # timer  # p10k has builtin timer
    # z  # conflicts with zoxide
    # zsh-completions  # configured below using manual fpath addition
    # zsh-history-substring-search  # fzf provides better functionality
    # zsh-interactive-cd  # fzf-tab provides better functionality
    # zsh-navigation-tools  # conflicts with fzf-tab
    # zsh-syntax-highlighting  # conflicts with fast-syntax-highlighting

    1password
    aliases
    brew
    colored-man-pages
    conda
    conda-zsh-completion
    copybuffer
    copyfile
    copypath
    docker
    emacs
    emoji
    extract
    gh
    git
    git-lfs
    github
    gitignore
    golang
    history
    kitty
    man
    node
    npm
    nvm
    pip
    python
    rsync
    rust
    ssh
    sudo
    tailscale
    tldr
    tmux
    uv
    vscode
    web-search
    you-should-use
    zoxide
)

# Host-specific interactive config (plugins, fpath filters, etc.)
if [[ -r "$HOME/.config/zsh/.zshrc" ]]; then
    source "$HOME/.config/zsh/.zshrc"
fi

# Keep the order of following plugins
plugins+=(
    fzf
    fzf-tab
    zsh-autosuggestions
    fast-syntax-highlighting
)

# bat theme
export BAT_THEME="Catppuccin Mocha"

# Plugin configuration below are automatically loaded in $ZSH_CUSTOM/...
# conda-zsh-completion
# fzf
# fzf-tab
# nvm
# ssh-agent
# zsh-autosuggestions

# Load the zsh-completions plugin
# See https://github.com/zsh-users/zsh-completions/blob/master/README.md
fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src

# Source Oh My Zsh
source $ZSH/oh-my-zsh.sh

# source alias file if it exists
if [[ -r "$HOME/.zsh_aliases" ]]; then
    source "$HOME/.zsh_aliases"
fi

# Disable special dirs
# This should be set after sourcing oh-my-zsh to override its default setting
zstyle ':completion:*' special-dirs false

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
