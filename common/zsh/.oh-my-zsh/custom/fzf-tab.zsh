#!/bin/zsh

zstyle ':completion:*:git-checkout:*' sort false
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors ${(s.:.)ZLS_COLORS} # use ZLS_COLORS for list colors
zstyle ':completion:*' menu no

zstyle ':fzf-tab:*' switch-group '<' '>'
# FIXME: Use fzf-tmux-popup cause some bugs with fzf-tab
# zstyle ':fzf-tab:*' fzf-command ftb-tmux-popup

# Custom fzf flags
# NOTE: fzf-tab does not follow FZF_DEFAULT_OPTS by default
# To make fzf-tab follow FZF_DEFAULT_OPTS.
# NOTE: This may lead to unexpected behavior since some flags break this plugin. See Aloxaf/fzf-tab#455.
# zstyle ':fzf-tab:*' use-fzf-default-opts yes
zstyle ':fzf-tab:*' fzf-flags \
    --ansi \
    --tmux center,80% \
    --border \
    --height 60% \
    --layout reverse \
    --padding 1,2 \
    --style full \
    --header-label ' Item Type ' \
    --input-label ' Input ' \
    --preview-label ' Preview ' \
    --preview-window right,60%,wrap,border \
    --color 'border:#aaaaaa,label:#cccccc' \
    --color 'header-border:#6699cc,header-label:#99ccff' \
    --color 'input-border:#996666,input-label:#ffcccc' \
    --color 'list-border:#669966,list-label:#99cc99' \
    --color 'preview-border:#9999cc,preview-label:#ccccff' \
    --bind 'result:transform-list-label:
        if [[ -z $FZF_QUERY ]]; then
            echo " $FZF_MATCH_COUNT items "
        else
            echo " $FZF_MATCH_COUNT matches for [ $FZF_QUERY ] "
        fi'

# Custom key bindings
zstyle ':fzf-tab:*' fzf-bindings \
    'tab:accept' \
    'shift-tab:toggle+down' \
    'ctrl-a:toggle-all'

# Default preview
zstyle ':fzf-tab:complete:*' fzf-preview '[[ -e "$realpath" ]] && my-fzf-preview.sh "$realpath" || echo "$desc" | bat --color=always --language=zsh --style=plain --wrap=character'

# Custom previews for specific commands

# kill
zstyle ':completion:*:*:*:*:processes' command "ps -u $USER -o pid,user,comm -w -w"
zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-preview \
    '[[ $group == "[process ID]" ]] && ps --pid=$word -o cmd --no-headers -w -w'
zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-flags --preview-window=down:3:wrap

# systemd
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview 'SYSTEMD_COLORS=1 systemctl status $word'

# environment variable
zstyle ':fzf-tab:complete:(-command-|-parameter-|-brace-parameter-|export|unset|expand):*' \
    fzf-preview 'echo ${(P)word}'

# git
zstyle ':fzf-tab:complete:git-(add|diff|restore):*' fzf-preview \
    'git diff $word | delta'
zstyle ':fzf-tab:complete:git-log:*' fzf-preview \
    'git log --color=always $word'
zstyle ':fzf-tab:complete:git-help:*' fzf-preview \
    'git help $word | bat -plman --color=always'
zstyle ':fzf-tab:complete:git-show:*' fzf-preview \
    'case "$group" in
    "commit tag") git show --color=always $word ;;
    *) git show --color=always $word | delta ;;
    esac'
zstyle ':fzf-tab:complete:git-checkout:*' fzf-preview \
    'case "$group" in
    "modified file") git diff $word | delta ;;
    "recent commit object name") git show --color=always $word | delta ;;
    *) git log --color=always $word ;;
    esac'

# brew
zstyle ':fzf-tab:complete:brew-(install|uninstall|search|info):*-argument-rest' fzf-preview 'HOMEBREW_COLOR=1 brew info $word'

# tldr
zstyle ':fzf-tab:complete:tldr:argument-1' fzf-preview 'tldr --color always $word'

# commands
zstyle ':fzf-tab:complete:-command-:*' fzf-preview \
    '(out=$(tldr --color always "$word" 2>/dev/null) && echo "$out") || \
    (man -w "$word" >/dev/null 2>&1 && MANWIDTH=$((FZF_PREVIEW_COLUMNS < 40 ? 80 : FZF_PREVIEW_COLUMNS)) man -P cat "$word" 2>/dev/null | col -bx | bat --language=man --color=always --style=plain --wrap=character) || \
    (out=$(which "$word" 2>/dev/null) && echo "$out" | bat --color=always --language=zsh --style=plain --wrap=character) || \
    (out="${(P)word}"; [[ -n "$out" ]] && echo "$out" | bat --color=always --language=zsh --style=plain --wrap=character) || \
    echo "$desc" | bat --color=always --language=zsh --style=plain --wrap=character'

# conda
zstyle ':fzf-tab:complete:conda:*' fzf-preview \
    '# Check if the selected word is a path to an environment
    for p in "$realpath" "$word"; do
        if [[ -d "$p" ]]; then
            if [[ -d "$p/conda-meta" ]]; then
                conda env export -p "$p" | bat --color=always --language=yaml --style=plain --wrap=character
                exit
            else
                # If it is a directory but not a conda env, preview its contents
                my-fzf-preview.sh "$p"
                exit
            fi
        fi
    done

    # Otherwise, treat it as an environment name
    base="$(conda info --base 2>/dev/null)"
    for p in "$base/envs/$word" "$HOME/.conda/envs/$word"; do
        if [[ -d "$p/conda-meta" ]]; then
            conda env export -p "$p" | bat --color=always --language=yaml --style=plain --wrap=character
            exit
        fi
    done

    # Special case for "base" environment
    if [[ "$word" == "base" ]]; then
        conda env export -p "$base" | bat --color=always --language=yaml --style=plain --wrap=character
        exit
    fi

    # Fallback: just show the description
    echo "$desc" | bat --color=always --language=zsh --style=plain --wrap=character'
