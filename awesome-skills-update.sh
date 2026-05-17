#!/bin/sh
# awesome-skills-update.sh — keep ~/.claude/skills and ~/.codex/skills in sync
# with github.com/FridrichMethod/awesome-skills.
#
# Mirrors the dotfiles-update.sh pattern: sourced from interactive shell rc,
# runs at most once per shell session, and throttles real network work to
# ~weekly. First run on a fresh machine installs everything; subsequent
# sessions are a stat() check and exit.
#
# Configurable variables (set before sourcing):
#   AWESOME_SKILLS_AUTO_UPDATE   set to 0 to disable entirely
#   AWESOME_SKILLS_REFRESH_DAYS  refresh interval (default: 7)
#   AWESOME_SKILLS_FORCE         set to 1 to bypass the time-throttle once
#   AWESOME_SKILLS_BG            set to 0 to run synchronously (default: 1, run in background)
#   AWESOME_SKILLS_INSTALLER_URL override the install.sh URL

# Only run in interactive shells (FORCE=1 bypasses, so the `sync-skills`
# alias works even when expanded into a non-interactive `sh` subprocess).
if [ "${AWESOME_SKILLS_FORCE:-0}" != "1" ]; then
    case $- in
        *i*) ;;
        *) return 2>/dev/null || exit 0 ;;
    esac
fi

# Skip if already checked in this session
[ -z "$_AWESOME_SKILLS_CHECKED" ] || return 2>/dev/null || exit 0

_awesome_skills_check() {
    [ "${AWESOME_SKILLS_AUTO_UPDATE:-1}" != "0" ] || return 0
    command -v curl >/dev/null 2>&1 || return 0

    _ask_url="${AWESOME_SKILLS_INSTALLER_URL:-https://raw.githubusercontent.com/FridrichMethod/awesome-skills/main/install.sh}"
    _ask_cache="${XDG_CACHE_HOME:-$HOME/.cache}/awesome-skills"
    _ask_stamp="$_ask_cache/last-sync"
    _ask_lock="$_ask_cache/in-progress.pid"
    _ask_log="$_ask_cache/last.log"
    _ask_days="${AWESOME_SKILLS_REFRESH_DAYS:-7}"

    mkdir -p "$_ask_cache" 2>/dev/null || return 0

    # Bail if another shell already kicked off a sync recently.
    if [ -f "$_ask_lock" ]; then
        _ask_pid=$(cat "$_ask_lock" 2>/dev/null)
        if [ -n "$_ask_pid" ] && kill -0 "$_ask_pid" 2>/dev/null; then
            return 0
        fi
        rm -f "$_ask_lock" 2>/dev/null
    fi

    # Time-throttle: skip if last successful sync is recent enough.
    if [ "${AWESOME_SKILLS_FORCE:-0}" != "1" ] && [ -f "$_ask_stamp" ]; then
        _ask_now=$(date +%s)
        _ask_then=$(stat -c %Y "$_ask_stamp" 2>/dev/null || stat -f %m "$_ask_stamp" 2>/dev/null)
        if [ -n "$_ask_then" ]; then
            _ask_age=$((_ask_now - _ask_then))
            _ask_thresh=$((_ask_days * 86400))
            [ "$_ask_age" -lt "$_ask_thresh" ] && return 0
        fi
    fi

    _ask_first=0
    [ -f "$_ask_stamp" ] || _ask_first=1

    if [ "$_ask_first" = "1" ]; then
        printf '\033[1;33m[awesome-skills]\033[0m First-time install — fetching skills from %s ...\n' \
            "$_ask_url"
    else
        printf '\033[1;33m[awesome-skills]\033[0m Refresh interval reached — syncing in background. Log: %s\n' \
            "$_ask_log"
    fi

    # Inner runner — used for both fg and bg paths.
    _ask_run() {
        echo "$$" >"$_ask_lock" 2>/dev/null
        if curl -fsSL "$_ask_url" | bash >"$_ask_log" 2>&1; then
            touch "$_ask_stamp"
            rm -f "$_ask_lock"
            return 0
        fi
        rm -f "$_ask_lock"
        return 1
    }

    if [ "$_ask_first" = "1" ] || [ "${AWESOME_SKILLS_BG:-1}" = "0" ]; then
        # Run in foreground so user sees first-time progress.
        if _ask_run; then
            printf '\033[1;32m[awesome-skills]\033[0m Sync complete.\n'
        else
            printf '\033[1;31m[awesome-skills]\033[0m Sync failed — see %s\n' "$_ask_log"
        fi
    else
        # Background refresh; do not block shell startup.
        (_ask_run) </dev/null >/dev/null 2>&1 &
    fi
}

_awesome_skills_check
export _AWESOME_SKILLS_CHECKED=1
unset -f _awesome_skills_check _ask_run 2>/dev/null
unset _ask_url _ask_cache _ask_stamp _ask_lock _ask_log _ask_days \
    _ask_now _ask_then _ask_age _ask_thresh _ask_first _ask_pid 2>/dev/null
