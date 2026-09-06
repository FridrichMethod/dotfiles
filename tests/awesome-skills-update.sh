#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATER="$REPO_ROOT/scripts/awesome-skills-update.sh"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-awesome-skills.XXXXXX")"
worker_pids=()
cleanup() {
    local result=$?
    trap - EXIT HUP INT TERM
    # Unblock every mock download even when an assertion fails.
    touch "$TEST_TMP/fresh.release" "$TEST_TMP/stale.release" "$TEST_TMP/background.release"
    for worker_pid in "${worker_pids[@]}"; do
        wait "$worker_pid" 2>/dev/null || true
    done
    if [[ -n "${background_worker_pid:-}" ]]; then
        for ((attempt = 0; attempt < 200; attempt++)); do
            [[ "$(cat "$TEST_TMP/cache-background/awesome-skills/in-progress.lock/pid" 2>/dev/null)" == 0 ]] && break
            sleep 0.05
        done
    fi
    rm -rf "$TEST_TMP"
    exit "$result"
}
trap cleanup EXIT HUP INT TERM

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
    blocked)
        : >"$BLOCK_STARTED"
        while [ ! -f "$BLOCK_RELEASE" ]; do
            sleep 0.05
        done
        printf '%s\n' \
            '#!/bin/sh' \
            'printf "installed\n" >>"$INSTALL_LOG"'
        ;;
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
# installer succeeds, removes its staging file, and exports the marker.
run_hook first-success AWESOME_SKILLS_FORCE=1
assert_single_curl
grep -Fxq 'installed' "$INSTALL_LOG"
[[ -f "$CACHE_ROOT/awesome-skills/last-sync" ]]
grep -Fxq 0 "$CACHE_ROOT/awesome-skills/in-progress.lock/pid"
[[ ! -e "$CACHE_ROOT/awesome-skills/in-progress.lock/recover" ]]
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
grep -Fxq 0 "$CACHE_ROOT/awesome-skills/in-progress.lock/pid"
[[ ! -e "$CACHE_ROOT/awesome-skills/in-progress.lock/recover" ]]
grep -Fq 'Sync failed' "$LAST_STDOUT"

# A downloaded installer failure is also retryable and preserves its log.
: >"$INSTALL_LOG"
run_hook installer-failure AWESOME_SKILLS_FORCE=1 CURL_MODE=installer-failure
assert_single_curl
grep -Fxq 'installer-failed' "$INSTALL_LOG"
[[ ! -e "$CACHE_ROOT/awesome-skills/last-sync" ]]
grep -Fxq 0 "$CACHE_ROOT/awesome-skills/in-progress.lock/pid"
[[ ! -e "$CACHE_ROOT/awesome-skills/in-progress.lock/recover" ]]
grep -Fq 'Sync failed' "$LAST_STDOUT"

# Opt-out and a pre-existing session marker are side-effect free.
run_hook disabled AWESOME_SKILLS_FORCE=1 AWESOME_SKILLS_AUTO_UPDATE=0
[[ ! -s "$CURL_LOG" ]]
grep -Fxq 'marker=1' "$LAST_STDOUT"

run_hook already-checked _AWESOME_SKILLS_CHECKED=1
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

# A live legacy lock suppresses a duplicate run during migration.
active_cache="$TEST_TMP/cache-active-lock/awesome-skills"
mkdir -p "$active_cache"
printf '%s\n' "$$" >"$active_cache/in-progress.pid"
run_hook active-lock AWESOME_SKILLS_FORCE=1
[[ ! -s "$CURL_LOG" ]]
[[ -f "$active_cache/in-progress.pid" ]]

# Explicit force bypasses both an inherited session marker and a recent stamp.
forced_cache="$TEST_TMP/cache-forced-marker/awesome-skills"
mkdir -p "$forced_cache"
: >"$forced_cache/last-sync"
run_hook forced-marker AWESOME_SKILLS_FORCE=1 _AWESOME_SKILLS_CHECKED=1
assert_single_curl

# Repeated forced runs reclaim the idle marker instead of treating PID zero
# as the current process group, and each run performs a fresh installation.
: >"$INSTALL_LOG"
run_hook repeated-force AWESOME_SKILLS_FORCE=1
assert_single_curl
run_hook repeated-force AWESOME_SKILLS_FORCE=1 _AWESOME_SKILLS_CHECKED=1
assert_single_curl
[[ "$(wc -l <"$INSTALL_LOG")" -eq 2 ]]

# Exercise the real alias in a shell whose automatic startup check already ran.
: >"$CURL_LOG"
env HOME="$TEST_TMP/home" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    DOTFILES_DIR="$REPO_ROOT" \
    XDG_CACHE_HOME="$TEST_TMP/cache-alias" \
    AWESOME_SKILLS_INSTALLER_URL="$INSTALLER_URL" \
    _AWESOME_SKILLS_CHECKED=1 \
    CURL_LOG="$CURL_LOG" \
    INSTALL_LOG="$INSTALL_LOG" \
    bash --noprofile --norc -uc '
        shopt -s expand_aliases
        . "$DOTFILES_DIR/common/sh/.aliases"
        eval sync-skills
        test "$_AWESOME_SKILLS_CHECKED" = 1
    ' >"$TEST_TMP/alias.stdout" 2>"$TEST_TMP/alias.stderr"
assert_single_curl
grep -Fq 'Sync complete' "$TEST_TMP/alias.stdout"

# A dead owner is replaced in place. Keeping the directory avoids removal
# races between a stale reader and a newer owner.
stale_lock_cache="$TEST_TMP/cache-stale-lock/awesome-skills"
mkdir -p "$stale_lock_cache/in-progress.lock"
printf '%s\n' '99999999' >"$stale_lock_cache/in-progress.lock/pid"
: >"$INSTALL_LOG"
run_hook stale-lock AWESOME_SKILLS_FORCE=1
assert_single_curl
grep -Fxq 'installed' "$INSTALL_LOG"
[[ -f "$stale_lock_cache/last-sync" ]]
grep -Fxq 0 "$stale_lock_cache/in-progress.lock/pid"
[[ ! -e "$stale_lock_cache/in-progress.lock/recover" ]]

# A directory acquired before its owner has published a PID is never stolen.
incomplete_cache="$TEST_TMP/cache-incomplete-lock/awesome-skills"
mkdir -p "$incomplete_cache/in-progress.lock"
run_hook incomplete-lock AWESOME_SKILLS_FORCE=1
[[ ! -s "$CURL_LOG" ]]
[[ -d "$incomplete_cache/in-progress.lock" ]]
grep -Fq "incomplete lock at $incomplete_cache/in-progress.lock" "$LAST_STDERR"

# Interrupted recovery is fail-closed and explains the concrete recovery path.
recovery_cache="$TEST_TMP/cache-recovery-lock/awesome-skills"
mkdir -p "$recovery_cache/in-progress.lock/recover"
printf '%s\n' 0 >"$recovery_cache/in-progress.lock/pid"
run_hook recovery-lock AWESOME_SKILLS_FORCE=1
[[ ! -s "$CURL_LOG" ]]
grep -Fq "recovery lock at $recovery_cache/in-progress.lock/recover" "$LAST_STDERR"
rmdir "$recovery_cache/in-progress.lock/recover"
run_hook recovery-lock AWESOME_SKILLS_FORCE=1
assert_single_curl

wait_for_file() {
    local path=$1
    for ((attempt = 0; attempt < 200; attempt++)); do
        [[ -f "$path" ]] && return 0
        sleep 0.05
    done
    printf 'ERROR: timed out waiting for %s\n' "$path" >&2
    return 1
}

run_blocked_worker() {
    env -u _AWESOME_SKILLS_CHECKED \
        HOME="$TEST_TMP/home" \
        PATH="$FAKE_BIN:/usr/bin:/bin" \
        XDG_CACHE_HOME="$CONCURRENT_CACHE" \
        AWESOME_SKILLS_INSTALLER_URL="$INSTALLER_URL" \
        AWESOME_SKILLS_FORCE=1 \
        AWESOME_SKILLS_BG="${WORKER_BG:-0}" \
        UPDATER="$UPDATER" \
        CURL_LOG="$CURL_LOG" \
        INSTALL_LOG="$INSTALL_LOG" \
        CURL_MODE=blocked \
        BLOCK_STARTED="$BLOCK_STARTED" \
        BLOCK_RELEASE="$BLOCK_RELEASE" \
        LAUNCHER_PID_FILE="$TEST_TMP/launcher.pid" \
        sh -uc 'printf "%s\n" "$$" >"$LAUNCHER_PID_FILE"; . "$UPDATER"'
}

# Real simultaneous processes must elect just one installer, both on a fresh
# cache and when several contenders observe the same dead owner.
for lock_state in fresh stale; do
    CONCURRENT_CACHE="$TEST_TMP/cache-concurrent-$lock_state"
    BLOCK_STARTED="$TEST_TMP/$lock_state.started"
    BLOCK_RELEASE="$TEST_TMP/$lock_state.release"
    mkdir -p "$CONCURRENT_CACHE/awesome-skills"
    if [[ "$lock_state" == stale ]]; then
        mkdir "$CONCURRENT_CACHE/awesome-skills/in-progress.lock"
        printf '%s\n' '99999999' >"$CONCURRENT_CACHE/awesome-skills/in-progress.lock/pid"
    fi
    : >"$CURL_LOG"
    : >"$INSTALL_LOG"
    worker_pids=()
    for ((worker = 0; worker < 8; worker++)); do
        (
            run_blocked_worker >"$TEST_TMP/$lock_state-$worker.stdout" 2>&1
            : >"$TEST_TMP/$lock_state-$worker.done"
        ) &
        worker_pids+=("$!")
    done
    wait_for_file "$BLOCK_STARTED"
    # Wait for the other seven processes to finish their lock attempt before
    # releasing the holder, even on a heavily loaded host.
    for ((attempt = 0; attempt < 200; attempt++)); do
        completed=0
        for ((worker = 0; worker < 8; worker++)); do
            if [[ -f "$TEST_TMP/$lock_state-$worker.done" ]]; then
                completed=$((completed + 1))
            fi
        done
        [[ "$completed" -eq 7 ]] && break
        sleep 0.05
    done
    [[ "$completed" -eq 7 ]]
    # The holder remains blocked while every competing launcher attempts sync.
    for ((worker = 0; worker < 8; worker++)); do
        run_blocked_worker >"$TEST_TMP/$lock_state-contender-$worker.stdout" 2>&1
    done
    assert_single_curl
    : >"$BLOCK_RELEASE"
    for worker_pid in "${worker_pids[@]}"; do
        wait "$worker_pid"
    done
    assert_single_curl
    [[ "$(wc -l <"$INSTALL_LOG")" -eq 1 ]]
    [[ -f "$CONCURRENT_CACHE/awesome-skills/last-sync" ]]
done

# A background worker must own its lock after its launching shell exits. The
# old code recorded the launcher's $$ and admitted a second running installer.
CONCURRENT_CACHE="$TEST_TMP/cache-background"
BLOCK_STARTED="$TEST_TMP/background.started"
BLOCK_RELEASE="$TEST_TMP/background.release"
mkdir -p "$CONCURRENT_CACHE/awesome-skills"
: >"$CONCURRENT_CACHE/awesome-skills/last-sync"
: >"$CURL_LOG"
: >"$INSTALL_LOG"
WORKER_BG=1 run_blocked_worker >"$TEST_TMP/background.stdout" 2>&1
wait_for_file "$BLOCK_STARTED"
launcher_pid=$(cat "$TEST_TMP/launcher.pid")
background_worker_pid=$(cat "$CONCURRENT_CACHE/awesome-skills/in-progress.lock/pid")
[[ "$background_worker_pid" != "$launcher_pid" ]]
! kill -0 "$launcher_pid" 2>/dev/null
kill -0 "$background_worker_pid"
run_blocked_worker >"$TEST_TMP/background-contender.stdout" 2>&1
assert_single_curl
: >"$BLOCK_RELEASE"
# Wait for the worker to finish staging cleanup and release ownership.
for ((attempt = 0; attempt < 200; attempt++)); do
    [[ "$(cat "$CONCURRENT_CACHE/awesome-skills/in-progress.lock/pid")" == 0 ]] && break
    sleep 0.05
done
grep -Fxq 0 "$CONCURRENT_CACHE/awesome-skills/in-progress.lock/pid"
[[ "$(wc -l <"$INSTALL_LOG")" -eq 1 ]]
assert_single_curl

echo "awesome-skills-update=PASS"
