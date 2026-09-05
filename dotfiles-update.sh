#!/bin/sh
# Check for upstream dotfiles changes once per interactive login session.
# DOTFILES_DIR defaults to ~/dotfiles. DOTFILES_AUTO_UPDATE=0 disables the
# entire hook; DOTFILES_AUTO_STOW=0 keeps pulls but disables automatic setup.
# DOTFILES_HOST overrides the host remembered by a successful stow-all.sh run
# (an explicitly empty value means common-only). No host is guessed.

case $- in
    *i*) ;;
    *) return 2>/dev/null || exit 0 ;;
esac
[ -z "${_DOTFILES_CHECKED:-}" ] || return 2>/dev/null || exit 0

# A subshell isolates variables, umask, and traps from the calling shell.
_dotfiles_update_check() (
    [ "${DOTFILES_AUTO_UPDATE:-1}" != "0" ] || return 0
    command -v git >/dev/null 2>&1 || return 0
    _df_dir="${DOTFILES_DIR:-$HOME/dotfiles}"
    [ -d "$_df_dir" ] || return 0
    cd "$_df_dir" || return 0
    _df_state=$(git rev-parse --git-path dotfiles-sync-unix 2>/dev/null) || return 0
    _df_lock=$(git rev-parse --git-path dotfiles-sync-unix.lock 2>/dev/null) || return 0
    umask 077

    if ! mkdir "$_df_lock" 2>/dev/null; then
        # Recover a dead owner without racing a second recovery process.
        _df_pid=$(cat "$_df_lock/pid" 2>/dev/null) || _df_pid=
        case $_df_pid in
            '' | *[!0-9]*)
                printf '[dotfiles] Incomplete update lock at %s; remove it after checking no update is running.\n' "$_df_lock"
                return 0
                ;;
        esac
        kill -0 "$_df_pid" 2>/dev/null && return 0
        mkdir "$_df_lock/recover" 2>/dev/null || return 0
        if [ "$(cat "$_df_lock/pid" 2>/dev/null)" = "$_df_pid" ] &&
            ! kill -0 "$_df_pid" 2>/dev/null; then
            rm -f "$_df_lock/pid" "$_df_lock/stow.log"
        fi
        rmdir "$_df_lock/recover" 2>/dev/null || return 0
        rmdir "$_df_lock" 2>/dev/null || return 0
        mkdir "$_df_lock" 2>/dev/null || return 0
    fi
    printf '%s\n' "$$" >"$_df_lock/pid"
    trap 'rm -f "$_df_lock/pid" "$_df_lock/stow.log"; rmdir "$_df_lock" 2>/dev/null || true' 0
    trap 'exit 0' HUP INT TERM

    # Only a marker from our own successful pull permits a gitlink mismatch.
    # Otherwise a clean submodule at a user-selected commit is user work too.
    _df_head=$(git rev-parse HEAD 2>/dev/null) || return 0
    _df_pending=$(cat "$_df_state.submodules-pending" 2>/dev/null) || _df_pending=
    _df_ignore=none
    if [ "$_df_pending" = "$_df_head" ]; then
        _df_ignore=all
    fi
    _df_dirty=$(git status --porcelain --untracked-files=normal --ignore-submodules="$_df_ignore" 2>/dev/null) || return 0
    if [ -n "$_df_dirty" ] || ! git submodule foreach --quiet --recursive \
        'status=$(git status --porcelain --untracked-files=normal --ignore-submodules=all) && test -z "$status"' >/dev/null 2>&1; then
        printf '[dotfiles] Local changes in %s; automatic pull and stow skipped.\n' "$_df_dir"
        return 0
    fi

    # Never let a credential prompt block shell startup.
    GIT_TERMINAL_PROMPT=0
    export GIT_TERMINAL_PROMPT
    _df_pulled=0
    if git fetch --quiet 2>/dev/null; then
        # shellcheck disable=SC1083
        _df_behind=$(git rev-list --count "HEAD..@{upstream}" 2>/dev/null) || _df_behind=0
        if [ "$_df_behind" -gt 0 ] 2>/dev/null; then
            printf '[dotfiles] %s new commit(s) available — pulling...\n' "$_df_behind"
            if ! git pull --ff-only --quiet 2>/dev/null; then
                printf '[dotfiles] Fast-forward pull failed. Resolve manually in %s.\n' "$_df_dir"
                return 0
            fi
            printf '[dotfiles] Pulled successfully.\n'
            _df_head=$(git rev-parse HEAD 2>/dev/null) || return 0
            printf '%s\n' "$_df_head" >"$_df_state.submodules-pending" || return 0
            if ! git submodule update --init --recursive --quiet 2>/dev/null; then
                printf '[dotfiles] Submodule update failed; automatic stow will retry next login.\n'
                return 0
            fi
            rm -f "$_df_state.submodules-pending"
            _df_pulled=1
        fi
    fi

    if [ "$_df_pulled" != 1 ] && [ "$_df_pending" = "$_df_head" ]; then
        if ! git submodule update --init --recursive --quiet 2>/dev/null; then
            printf '[dotfiles] Submodule update failed; automatic stow will retry next login.\n'
            return 0
        fi
        rm -f "$_df_state.submodules-pending"
        _df_pulled=1
    fi

    [ "${DOTFILES_AUTO_STOW:-1}" != "0" ] || return 0
    _df_host=
    _df_applied=
    _df_configured=0
    _df_platform=$(uname -s) || return 0
    if [ -f "$_df_state" ]; then
        {
            IFS= read -r _df_saved_home &&
                IFS= read -r _df_saved_platform &&
                IFS= read -r _df_host &&
                IFS= read -r _df_applied
        } <"$_df_state" || _df_saved_home=
        if [ "$_df_saved_home" = "$HOME" ] && [ "$_df_saved_platform" = "$_df_platform" ]; then
            _df_configured=1
        else
            _df_host=
            _df_applied=
        fi
    fi
    if [ "${DOTFILES_HOST+x}" = x ]; then
        [ "$DOTFILES_HOST" = "$_df_host" ] || _df_applied=
        _df_host=$DOTFILES_HOST
        _df_configured=1
    fi
    if [ "$_df_configured" != 1 ]; then
        printf '[dotfiles] Run bash "%s/stow-all.sh" [host-dir] once to enable automatic stow for this home.\n' "$_df_dir"
        return 0
    fi
    case $_df_host in
        win | common | .* | */* | *\\*)
            printf '[dotfiles] Invalid Unix host "%s"; rerun stow-all.sh with a host directory.\n' "$_df_host"
            return 0
            ;;
    esac
    if [ -n "$_df_host" ] && [ ! -d "$_df_host" ]; then
        printf '[dotfiles] Remembered host directory "%s" is missing; rerun stow-all.sh.\n' "$_df_host"
        return 0
    fi
    _df_head=$(git rev-parse HEAD 2>/dev/null) || return 0
    [ "$_df_head" != "$_df_applied" ] || return 0
    if [ "$_df_pulled" != 1 ] && ! git submodule update --init --recursive --quiet 2>/dev/null; then
        printf '[dotfiles] Submodule update failed; automatic stow will retry next login.\n'
        return 0
    fi
    _df_dirty=$(git status --porcelain --untracked-files=normal --ignore-submodules=none 2>/dev/null) || return 0
    if [ -n "$_df_dirty" ]; then
        printf '[dotfiles] Checkout changed during update; automatic stow skipped.\n'
        return 0
    fi
    printf '[dotfiles] Applying dotfiles (%s)...\n' "${_df_host:-common-only}"
    if bash ./stow-all.sh "$_df_host" >"$_df_lock/stow.log" 2>&1; then
        printf '[dotfiles] Stow completed; open a new shell to load updated config.\n'
    else
        cat "$_df_lock/stow.log" >&2
        printf '[dotfiles] Stow failed; fix the error and retry stow-all.sh, or retry next login.\n'
    fi
    rm -f "$_df_lock/stow.log"
)

_dotfiles_update_check || true
export _DOTFILES_CHECKED=1
unset -f _dotfiles_update_check
