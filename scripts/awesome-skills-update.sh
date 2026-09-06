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
#   AWESOME_SKILLS_FORCE         set to 1 to bypass session/time throttles once
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

# Skip repeated automatic checks, but allow an explicit manual sync even when
# the calling shell has already exported the session marker.
if [ "${AWESOME_SKILLS_FORCE:-0}" != "1" ]; then
    [ -z "${_AWESOME_SKILLS_CHECKED:-}" ] || return 2>/dev/null || exit 0
fi

_awesome_skills_check() {
    [ "${AWESOME_SKILLS_AUTO_UPDATE:-1}" != "0" ] || return 0
    command -v curl >/dev/null 2>&1 || return 0

    _ask_url="${AWESOME_SKILLS_INSTALLER_URL:-https://raw.githubusercontent.com/FridrichMethod/awesome-skills/main/install.sh}"
    _ask_cache="${XDG_CACHE_HOME:-$HOME/.cache}/awesome-skills"
    _ask_stamp="$_ask_cache/last-sync"
    _ask_days="${AWESOME_SKILLS_REFRESH_DAYS:-7}"

    mkdir -p "$_ask_cache" 2>/dev/null || return 0

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

    # A fresh sh process gives the runner its own $$, even when this function
    # was sourced into a shell that exits while a background refresh continues.
    _ask_run() {
        sh -s -- "$_ask_url" "$_ask_cache" "$_ask_first" <<'SH'
url=$1
cache=$2
first=$3
lock="$cache/in-progress.lock"
log="$cache/last.log"
stamp="$cache/last-sync"
installer=

# Honor an active updater started before the directory-lock migration.
legacy_pid=$(cat "$cache/in-progress.pid" 2>/dev/null) || legacy_pid=
case $legacy_pid in
    '' | *[!0-9]*) ;;
    *) kill -0 "$legacy_pid" 2>/dev/null && exit 0 ;;
esac

# mkdir publishes ownership atomically. An incomplete lock is left alone:
# another worker may have acquired it but not yet published its PID.
if mkdir "$lock" 2>/dev/null; then
    printf '%s\n' "$$" >"$lock/pid" || exit 1
else
    owner=$(cat "$lock/pid" 2>/dev/null) || owner=
    case $owner in
        '' | *[!0-9]*)
            printf '[awesome-skills] Sync skipped: incomplete lock at %s; after checking no sync is running, remove it and retry sync-skills.\n' "$lock" >&2
            exit 0
            ;;
    esac
    if [ "$owner" != 0 ] && kill -0 "$owner" 2>/dev/null; then
        exit 0
    fi
    mkdir "$lock/recover" 2>/dev/null || {
        printf '[awesome-skills] Sync skipped: recovery lock at %s; if no sync is running, remove it and retry sync-skills.\n' "$lock/recover" >&2
        exit 0
    }
    trap 'rmdir "$lock/recover" 2>/dev/null || true' 0
    trap 'exit 1' HUP INT TERM
    # Take over in place, after checking again under the recovery lock. The
    # directory persists after completion so delayed readers cannot remove
    # a newly acquired lock during cleanup or stale-owner recovery.
    [ "$(cat "$lock/pid" 2>/dev/null)" = "$owner" ] || exit 0
    if [ "$owner" != 0 ] && kill -0 "$owner" 2>/dev/null; then
        exit 0
    fi
    printf '%s\n' "$$" >"$lock/pid" || exit 1
    rmdir "$lock/recover" || exit 1
    trap - 0 HUP INT TERM
fi

# Zero marks a completed run; do this last so PID reuse cannot suppress a
# future refresh. The lock directory is never removed by a worker.
trap '[ -z "$installer" ] || rm -f "$installer"; printf "%s\n" 0 >"$lock/pid"' 0
trap 'exit 1' HUP INT TERM
if [ "$first" = "1" ]; then
    printf '\033[1;33m[awesome-skills]\033[0m First-time install — fetching skills from %s ...\n' "$url"
else
    printf '\033[1;33m[awesome-skills]\033[0m Refresh interval reached — syncing skills. Log: %s\n' "$log"
fi
installer=$(mktemp "$cache/install.XXXXXX") || exit 1
if curl -fsSL "$url" >"$installer" 2>"$log" &&
    bash "$installer" >>"$log" 2>&1 &&
    touch "$stamp" 2>>"$log"; then
    printf '\033[1;32m[awesome-skills]\033[0m Sync complete.\n'
else
    printf '\033[1;31m[awesome-skills]\033[0m Sync failed — see %s\n' "$log"
    exit 1
fi
SH
    }

    if [ "$_ask_first" = "1" ] || [ "${AWESOME_SKILLS_BG:-1}" = "0" ]; then
        # Run in foreground so user sees first-time progress.
        _ask_run || true
    else
        # Background refresh; do not block shell startup.
        (_ask_run) </dev/null >/dev/null 2>>"$_ask_cache/last.log" &
    fi
}

_awesome_skills_check
export _AWESOME_SKILLS_CHECKED=1
unset -f _awesome_skills_check _ask_run 2>/dev/null
unset _ask_url _ask_cache _ask_stamp _ask_days \
    _ask_now _ask_then _ask_age _ask_thresh _ask_first 2>/dev/null
