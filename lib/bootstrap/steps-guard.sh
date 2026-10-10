# shellcheck shell=bash
# shellcheck disable=SC2034 # STEPS_RC and STEPS_ERROR are read by steps.sh
# The rc-pollution guard of setup-host.sh (docs/bootstrap.md X-rc-protection).
# Every auto step and every HUMAN-block download runs through steps_guarded,
# which fails the step when it changed the checkout: an installer appending to
# a stowed rc file (~/.zshrc links into common/zsh/.zshrc) edits a tracked
# file. Sourced only (after steps.sh); defines functions and changes no shell
# options. Bash 3.2 compatible and `set -u` safe.

# steps_git_status: `git status --porcelain` of the checkout with every
# untracked file on its own line and UTF-8 names unquoted. Read-only:
# --no-optional-locks keeps git from refreshing the index.
steps_git_status() {
    git -c core.quotePath=false --no-optional-locks -C "$STEPS_ROOT" status --porcelain \
        --untracked-files=all 2>/dev/null </dev/null
}

# steps_status_snapshot: one line per changed path of the checkout: its
# status line, a tab, then a fingerprint of the content (cksum of a file, the
# target of a link, "-" otherwise). The fingerprint catches a step that edits
# a file which was already modified or untracked, whose status line stays the
# same.
steps_status_snapshot() {
    local status lines line path sum
    if ! status=$(steps_git_status); then
        printf '%s\n' '(git status failed)'
        return 0
    fi
    lines=$status$BOOTSTRAP_NL
    while [ -n "$lines" ]; do
        line=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        [ -n "$line" ] || continue
        path=${line#???}
        case $line in
            R* | C* | ?R* | ?C*) path=${path##* -> } ;;
        esac
        sum=-
        case $path in
            \"*) ;; # a name git still quotes (control characters): status only
            *)
                if [ -L "$STEPS_ROOT/$path" ]; then
                    sum="link $(readlink "$STEPS_ROOT/$path" 2>/dev/null)"
                elif [ -f "$STEPS_ROOT/$path" ]; then
                    sum=$(cksum <"$STEPS_ROOT/$path" 2>/dev/null) || sum=unreadable
                fi
                ;;
        esac
        printf '%s\t%s\n' "$line" "$sum"
    done
}

# steps_status_lost A B: the paths of the snapshot lines of A that B lacks.
steps_status_lost() {
    local nl=$BOOTSTRAP_NL lines line path
    lines=$1$nl
    while [ -n "$lines" ]; do
        line=${lines%%"$nl"*}
        lines=${lines#*"$nl"}
        [ -n "$line" ] || continue
        case "$nl$2$nl" in
            *"$nl$line$nl"*) continue ;;
        esac
        case $line in
            *"$BOOTSTRAP_TAB"*)
                path=${line%%"$BOOTSTRAP_TAB"*}
                path=${path#???}
                ;;
            *) path=$line ;;
        esac
        printf '%s\n' "$path"
    done
}

# steps_status_changes BEFORE AFTER: the paths a step modified, added or
# reverted, space-separated and each listed once.
steps_status_changes() {
    local lines path changed=''
    lines=$(steps_status_lost "$2" "$1")$BOOTSTRAP_NL$(steps_status_lost "$1" "$2")$BOOTSTRAP_NL || true
    while [ -n "$lines" ]; do
        path=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        [ -n "$path" ] || continue
        case " $changed " in
            *" $path "*) ;;
            *) changed="$changed${changed:+ }$path" ;;
        esac
    done
    printf '%s\n' "${changed:-git status changed}"
}

# steps_dirty_summary: empty for a clean checkout, else its first changed
# paths and a count, for the P0-preflight warning. Returns 1 when git status
# fails, which turns the guard blind.
steps_dirty_summary() {
    local status lines line paths='' count=0
    status=$(steps_git_status) || return 1
    lines=$status$BOOTSTRAP_NL
    while [ -n "$lines" ]; do
        line=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        [ -n "$line" ] || continue
        count=$((count + 1))
        [ "$count" -gt 5 ] || paths="$paths${paths:+ }${line#???}"
    done
    [ "$count" -gt 0 ] || return 0
    if [ "$count" -gt 5 ]; then
        printf '%s and %s more\n' "$paths" "$((count - 5))"
    else
        printf '%s\n' "$paths"
    fi
}

# steps_guarded FUNCTION [ARG...]: run FUNCTION in a subshell with errexit,
# then require that the checkout is unchanged, content included. Sets
# STEPS_RC (0 ok) and STEPS_ERROR. Call it as a plain command: inside `if`,
# `||` or `&&`, Bash ignores errexit in the whole call chain, including this
# subshell.
steps_guarded() {
    local before after errexit=0
    case $- in
        *e*) errexit=1 ;;
    esac
    STEPS_ERROR=
    before=$(steps_status_snapshot)
    set +e
    (
        set -e
        "$@"
    )
    STEPS_RC=$?
    [ "$errexit" = 0 ] || set -e
    after=$(steps_status_snapshot)
    if [ "$before" != "$after" ]; then
        STEPS_ERROR="changed files in $STEPS_ROOT: $(steps_status_changes "$before" "$after")"
        STEPS_RC=1
    fi
    return 0
}
