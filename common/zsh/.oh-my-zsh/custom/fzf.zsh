#!/bin/zsh

# Options for default fzf behavior
export FZF_DEFAULT_OPTS=$(
  cat <<'EOF'
--tmux center,80%
--border
--height 60%
--layout reverse
--padding 1,2
--style full
--header-label ' Item Type '
--input-label ' Input '
--preview-window right,60%,wrap,border
--color 'border:#aaaaaa,label:#cccccc'
--color 'header-border:#6699cc,header-label:#99ccff'
--color 'input-border:#996666,input-label:#ffcccc'
--color 'list-border:#669966,list-label:#99cc99'
--color 'preview-border:#9999cc,preview-label:#ccccff'
--bind 'ctrl-a:toggle-all'
--bind 'result:transform-list-label:
    if [[ -z $FZF_QUERY ]]; then
        echo " $FZF_MATCH_COUNT items "
    else
        echo " $FZF_MATCH_COUNT matches for [ $FZF_QUERY ] "
    fi'
--bind 'focus:transform-preview-label:
    set -- {}; s="$*";
    if [[ -e "$s" ]]; then
        printf " Previewing [ %s ] " "$(eza --color=always --icons --show-symlinks -d -- "$s" | tr -d "\n")"
    else
        printf " Previewing [ %s ] " "$s"
    fi'
--bind 'focus:+transform-header:
    set -- {}; s="$*";
    if [[ -e "$s" ]]; then
        file --brief -- "$s"
    else
        echo "No file selected"
    fi'
--preview 'my-fzf-preview.sh {}'
EOF
)

# Options for Ctrl-R
export FZF_CTRL_R_OPTS=$(
  cat <<'EOF'
--ansi
--scheme history
--header-label ' Command '
--color header:italic
--header 'Press CTRL-Y to copy command into clipboard'
--bind 'ctrl-y:execute-silent(
    if command -v clip.exe &>/dev/null; then
        echo -n {2..} | clip.exe
    elif command -v pbcopy &>/dev/null; then
        echo -n {2..} | pbcopy
    else
        echo -n {2..} | xclip -selection clipboard
    fi
)+abort'
--bind 'focus:transform-preview-label:[[ -n {} ]] && printf " Previewing [ %s ] " $(echo {1})'
--bind 'focus:+transform-header:echo "Press CTRL-Y to copy command into clipboard"'
--bind 'change:transform-header:[[ $FZF_MATCH_COUNT -eq 0 ]] && echo "No command selected"'
--preview 'echo {2..} | bat --color=always --language=zsh --style=plain --wrap=character'
EOF
)

# Options for Ctrl-T
export FZF_CTRL_T_COMMAND='fd -u --max-depth 1 --strip-cwd-prefix --exclude .git --color=always'
export FZF_CTRL_T_OPTS=$(
  cat <<'EOF'
--ansi
--scheme path
EOF
)

# Options for Alt-C
export FZF_ALT_C_COMMAND='fd --type d -u --follow --strip-cwd-prefix --exclude .git --color=always'
export FZF_ALT_C_OPTS=$(
  cat <<'EOF'
--ansi
--scheme path
EOF
)

# Options to fzf command
export FZF_COMPLETION_OPTS='--border --info=inline'
export FZF_COMPLETION_PATH_OPTS='--walker file,dir,follow,hidden'
export FZF_COMPLETION_DIR_OPTS='--walker dir,follow'
export YSU_MESSAGE_POSITION="after"
