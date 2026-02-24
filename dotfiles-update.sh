#!/bin/sh
# dotfiles-update.sh — check for upstream dotfiles changes on login.
#
# Uses an exported env var (_DOTFILES_CHECKED) as a session marker so the
# check runs exactly once per login session: subshells and tmux panes
# inherit the marker and skip instantly, while a fresh SSH session (clean
# environment) triggers a new check.
#
# Configurable variables (set before sourcing):
#   DOTFILES_DIR             repo path  (default: ~/dotfiles)
#   DOTFILES_AUTO_UPDATE     set to 0 to disable

# Only run in interactive shells
case $- in
    *i*) ;;
    *) return 2>/dev/null || exit 0 ;;
esac

# Skip if already checked in this session
[ -z "$_DOTFILES_CHECKED" ] || return 2>/dev/null || exit 0

_dotfiles_update_check() {
    [ "${DOTFILES_AUTO_UPDATE:-1}" != "0" ] || return 0

    _df_dir="${DOTFILES_DIR:-$HOME/dotfiles}"

    [ -d "$_df_dir/.git" ] || return 0

    git -C "$_df_dir" fetch --quiet 2>/dev/null || return 0

    # shellcheck disable=SC1083
    _df_behind=$(git -C "$_df_dir" rev-list --count "HEAD..@{upstream}" 2>/dev/null) || return 0
    [ "$_df_behind" -gt 0 ] 2>/dev/null || return 0

    printf '\033[1;33m[dotfiles]\033[0m %s new commit(s) available — pulling...\n' "$_df_behind"
    if git -C "$_df_dir" pull --ff-only --quiet 2>/dev/null; then
        printf '\033[1;32m[dotfiles]\033[0m Pulled successfully.\n'
        printf '\033[1;33m[dotfiles]\033[0m Run \033[1mstow-all.sh\033[0m to re-stow and apply changes.\n'
    else
        printf '\033[1;31m[dotfiles]\033[0m Fast-forward pull failed. Resolve manually in \033[1m%s\033[0m.\n' "$_df_dir"
    fi
}

_dotfiles_update_check
export _DOTFILES_CHECKED=1
unset -f _dotfiles_update_check
unset _df_dir _df_behind
