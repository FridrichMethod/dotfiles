#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATER="$REPO_ROOT/awesome-skills-update.sh"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-awesome-skills.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM

FAKE_BIN="$TEST_TMP/bin"
CURL_LOG="$TEST_TMP/curl.log"
INSTALL_LOG="$TEST_TMP/install.log"
INSTALLER_URL="https://example.invalid/portable-installer.sh"
mkdir -p "$FAKE_BIN" "$TEST_TMP/home" "$TEST_TMP/no-curl"

cat >"$FAKE_BIN/curl" <<'SH'
#!/bin/sh
{
    for argument do
        printf '[%s]' "$argument"
    done
    printf '\n'
} >>"$CURL_LOG"

case ${CURL_MODE:-success} in
    success)
        printf '%s\n' \
            '#!/bin/sh' \
            'printf "installed\n" >>"$INSTALL_LOG"'
        ;;
    download-failure)
        # A partial executable payload must not run when curl returns nonzero.
        printf '%s\n' \
            '#!/bin/sh' \
            'printf "partial-ran\n" >>"$INSTALL_LOG"'
        exit 22
        ;;
    installer-failure)
        printf '%s\n' \
            '#!/bin/sh' \
            'printf "installer-failed\n" >>"$INSTALL_LOG"' \
            'exit 9'
        ;;
    *)
        exit 90
        ;;
esac
SH
chmod +x "$FAKE_BIN/curl"

run_hook() {
    case_name=$1
    shift
    CACHE_ROOT="$TEST_TMP/cache-$case_name"
    LAST_STDOUT="$TEST_TMP/$case_name.stdout"
    LAST_STDERR="$TEST_TMP/$case_name.stderr"
    : >"$CURL_LOG"
    env -u _AWESOME_SKILLS_CHECKED \
        HOME="$TEST_TMP/home" \
        PATH="$FAKE_BIN:/usr/bin:/bin" \
        XDG_CACHE_HOME="$CACHE_ROOT" \
        AWESOME_SKILLS_INSTALLER_URL="$INSTALLER_URL" \
        AWESOME_SKILLS_BG=0 \
        UPDATER="$UPDATER" \
        CURL_LOG="$CURL_LOG" \
        INSTALL_LOG="$INSTALL_LOG" \
        "$@" \
        bash --noprofile --norc -uic '
            . "$UPDATER"
            printf "marker=%s\n" "${_AWESOME_SKILLS_CHECKED:-missing}"
            bash -uc '\''printf "child-marker=%s\\n" "$_AWESOME_SKILLS_CHECKED"'\''
            if declare -F _awesome_skills_check >/dev/null ||
                declare -F _ask_run >/dev/null; then
                printf "function-leaked\n"
            fi
            if declare -p _ask_url >/dev/null 2>&1 ||
                declare -p _ask_cache >/dev/null 2>&1 ||
                declare -p _ask_stamp >/dev/null 2>&1 ||
                declare -p _ask_lock >/dev/null 2>&1 ||
                declare -p _ask_installer >/dev/null 2>&1; then
                printf "variable-leaked\n"
            fi
        ' >"$LAST_STDOUT" 2>"$LAST_STDERR"
}

assert_single_curl() {
    grep -Fxq "[-fsSL][$INSTALLER_URL]" "$CURL_LOG"
    [[ "$(wc -l <"$CURL_LOG")" -eq 1 ]]
}

# Ordinary non-interactive shells do not perform a check or consume the
# session marker; AWESOME_SKILLS_FORCE is the explicit bypass for the alias.
: >"$CURL_LOG"
env -u _AWESOME_SKILLS_CHECKED \
    HOME="$TEST_TMP/home" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    XDG_CACHE_HOME="$TEST_TMP/cache-noninteractive" \
    UPDATER="$UPDATER" \
    CURL_LOG="$CURL_LOG" \
    bash --noprofile --norc -uc \
    '. "$UPDATER"; printf "marker=%s\n" "${_AWESOME_SKILLS_CHECKED:-missing}"' \
    >"$TEST_TMP/noninteractive.stdout"
grep -Fxq 'marker=missing' "$TEST_TMP/noninteractive.stdout"
[[ ! -s "$CURL_LOG" ]]

# First install runs synchronously, advances the stamp only after the downloaded
# installer succeeds, removes its lock/staging file, and exports the marker.
run_hook first-success AWESOME_SKILLS_FORCE=1
assert_single_curl
grep -Fxq 'installed' "$INSTALL_LOG"
[[ -f "$CACHE_ROOT/awesome-skills/last-sync" ]]
[[ ! -e "$CACHE_ROOT/awesome-skills/in-progress.pid" ]]
if compgen -G "$CACHE_ROOT/awesome-skills/install.*" >/dev/null; then
    echo "ERROR: downloaded installer staging file leaked" >&2
    exit 1
fi
grep -Fq 'First-time install' "$LAST_STDOUT"
grep -Fq 'Sync complete' "$LAST_STDOUT"
grep -Fxq 'marker=1' "$LAST_STDOUT"
grep -Fxq 'child-marker=1' "$LAST_STDOUT"
! grep -Fq 'leaked' "$LAST_STDOUT"

# A curl failure with a partial payload must not execute it or mark success.
: >"$INSTALL_LOG"
run_hook download-failure AWESOME_SKILLS_FORCE=1 CURL_MODE=download-failure
assert_single_curl
[[ ! -s "$INSTALL_LOG" ]]
[[ ! -e "$CACHE_ROOT/awesome-skills/last-sync" ]]
[[ ! -e "$CACHE_ROOT/awesome-skills/in-progress.pid" ]]
grep -Fq 'Sync failed' "$LAST_STDOUT"

# A downloaded installer failure is also retryable and preserves its log.
: >"$INSTALL_LOG"
run_hook installer-failure AWESOME_SKILLS_FORCE=1 CURL_MODE=installer-failure
assert_single_curl
grep -Fxq 'installer-failed' "$INSTALL_LOG"
[[ ! -e "$CACHE_ROOT/awesome-skills/last-sync" ]]
[[ ! -e "$CACHE_ROOT/awesome-skills/in-progress.pid" ]]
grep -Fq 'Sync failed' "$LAST_STDOUT"

# Opt-out and a pre-existing session marker are side-effect free.
run_hook disabled AWESOME_SKILLS_FORCE=1 AWESOME_SKILLS_AUTO_UPDATE=0
[[ ! -s "$CURL_LOG" ]]
grep -Fxq 'marker=1' "$LAST_STDOUT"

run_hook already-checked \
    AWESOME_SKILLS_FORCE=1 \
    _AWESOME_SKILLS_CHECKED=1
[[ ! -s "$CURL_LOG" ]]
grep -Fxq 'marker=1' "$LAST_STDOUT"

# Missing curl is a clean no-op even under nounset.
: >"$CURL_LOG"
env -u _AWESOME_SKILLS_CHECKED \
    HOME="$TEST_TMP/home" \
    PATH="$TEST_TMP/no-curl" \
    XDG_CACHE_HOME="$TEST_TMP/cache-missing-curl" \
    AWESOME_SKILLS_FORCE=1 \
    UPDATER="$UPDATER" \
    CURL_LOG="$CURL_LOG" \
    /bin/bash --noprofile --norc -uic \
    '. "$UPDATER"; printf "marker=%s\n" "${_AWESOME_SKILLS_CHECKED:-missing}"' \
    >"$TEST_TMP/missing-curl.stdout" 2>"$TEST_TMP/missing-curl.stderr"
grep -Fxq 'marker=1' "$TEST_TMP/missing-curl.stdout"
[[ ! -s "$CURL_LOG" ]]

# A recent stamp throttles network work. An expired stamp refreshes in the
# foreground for deterministic testing when AWESOME_SKILLS_BG=0.
recent_cache="$TEST_TMP/cache-recent/awesome-skills"
mkdir -p "$recent_cache"
: >"$recent_cache/last-sync"
run_hook recent
[[ ! -s "$CURL_LOG" ]]
grep -Fxq 'marker=1' "$LAST_STDOUT"

stale_cache="$TEST_TMP/cache-stale/awesome-skills"
mkdir -p "$stale_cache"
: >"$stale_cache/last-sync"
python3 - "$stale_cache/last-sync" <<'PY'
import os
import sys
import time

old = time.time() - 10 * 86400
os.utime(sys.argv[1], (old, old))
PY
: >"$INSTALL_LOG"
run_hook stale
assert_single_curl
grep -Fxq 'installed' "$INSTALL_LOG"
grep -Fq 'Refresh interval reached' "$LAST_STDOUT"
grep -Fq 'Sync complete' "$LAST_STDOUT"

# A live lock suppresses a duplicate run; a stale PID is removed and retried.
active_cache="$TEST_TMP/cache-active-lock/awesome-skills"
mkdir -p "$active_cache"
printf '%s\n' "$$" >"$active_cache/in-progress.pid"
run_hook active-lock AWESOME_SKILLS_FORCE=1
[[ ! -s "$CURL_LOG" ]]
[[ -f "$active_cache/in-progress.pid" ]]

stale_lock_cache="$TEST_TMP/cache-stale-lock/awesome-skills"
mkdir -p "$stale_lock_cache"
printf '%s\n' '99999999' >"$stale_lock_cache/in-progress.pid"
: >"$INSTALL_LOG"
run_hook stale-lock AWESOME_SKILLS_FORCE=1
assert_single_curl
grep -Fxq 'installed' "$INSTALL_LOG"
[[ -f "$stale_lock_cache/last-sync" ]]
[[ ! -e "$stale_lock_cache/in-progress.pid" ]]

echo "awesome-skills-update=PASS"
