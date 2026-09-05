#!/bin/bash

set -euo pipefail

# Exercise both login implementations with isolated homes, fake failures,
# real local Git remotes, and independent-process lock contention.
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SH_UPDATER="$REPO_ROOT/dotfiles-update.sh"
PS_UPDATER="$REPO_ROOT/dotfiles-update.ps1"
PS_HELPER="$REPO_ROOT/dotfiles-auto-stow.ps1"
PS_PROFILE="$REPO_ROOT/win/powershell/Documents/PowerShell/profile.ps1"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-update-hooks.XXXXXX")"
REAL_CHILD_PID=
REAL_GATE=
cleanup() {
    if [ -n "$REAL_CHILD_PID" ]; then
        [ ! -d "$REAL_GATE" ] || : >"$REAL_GATE/release"
        wait "$REAL_CHILD_PID" 2>/dev/null || true
    fi
    rm -rf "$TEST_TMP"
}
trap cleanup EXIT HUP INT TERM

for token in _DOTFILES_CHECKED DOTFILES_AUTO_UPDATE DOTFILES_DIR DOTFILES_AUTO_STOW --ff-only 'submodule update'; do
    for f in "$SH_UPDATER" "$PS_UPDATER"; do
        if grep -Fq -e "$token" "$f"; then continue; fi
        if [ "$f" = "$PS_UPDATER" ] && grep -Fq -e "$token" "$PS_HELPER"; then continue; fi
        {
            echo "ERROR: $(basename "$f") lost '$token'" >&2
            exit 1
        }
    done
done
grep -Fq '[Console]::IsOutputRedirected' "$PS_UPDATER"
grep -Fq 'dotfiles-update.ps1' "$PS_PROFILE"
grep -Fq 'PSNativeCommandUseErrorActionPreference = $false' "$PS_UPDATER"

FAKE_BIN="$TEST_TMP/bin"
FAKE_REPO="$TEST_TMP/repo with spaces"
GIT_LOG="$TEST_TMP/git.log"
STOW_LOG="$TEST_TMP/stow.log"
mkdir -p "$FAKE_BIN" "$FAKE_REPO/meta" "$FAKE_REPO/host-a" "$FAKE_REPO/host-b" "$TEST_TMP/home" "$TEST_TMP/no-git"
# Linked worktrees have a .git file, which must not disable the updater.
printf 'gitdir: meta\n' >"$FAKE_REPO/.git"

cat >"$FAKE_BIN/git" <<'SH'
#!/bin/sh
{
    for argument do printf '[%s]' "$argument"; done
    printf '\n'
} >>"$GIT_LOG"
case ${1:-} in
    rev-parse)
        if [ "${2:-}" = --git-path ]; then
            printf '%s/meta/%s\n' "$PWD" "$3"
        else
            cat "$PWD/meta/head"
        fi
        ;;
    status)
        [ "${FAKE_STATUS_RC:-0}" -eq 0 ] || exit "$FAKE_STATUS_RC"
        count=$(cat "$PWD/meta/status-count")
        printf '%s\n' "$((count + 1))" >"$PWD/meta/status-count"
        if [ "$count" -eq 0 ]; then
            printf '%s' "${FAKE_DIRTY:-}"
            case "$*" in
                *--ignore-submodules=none*) printf '%s' "${FAKE_GITLINK_DIRTY:-}" ;;
            esac
        else
            printf '%s' "${FAKE_POST_DIRTY:-}"
        fi
        ;;
    fetch) exit "${FAKE_FETCH_RC:-0}" ;;
    rev-list)
        [ "${FAKE_REV_RC:-0}" -eq 0 ] || exit "$FAKE_REV_RC"
        printf '%s\n' "${FAKE_BEHIND:-0}"
        ;;
    pull)
        [ "${FAKE_PULL_RC:-0}" -eq 0 ] || exit "$FAKE_PULL_RC"
        printf 'new\n' >"$PWD/meta/head"
        ;;
    submodule)
        if [ "${2:-}" = foreach ]; then exit "${FAKE_SUBMODULE_DIRTY:-0}"; fi
        exit "${FAKE_SUBMODULE_RC:-0}"
        ;;
    *) exit 90 ;;
esac
SH
cat >"$FAKE_REPO/stow-all.sh" <<'SH'
#!/bin/sh
printf '[%s]\n' "$1" >>"$STOW_LOG"
[ "${FAKE_STOW_RC:-0}" -eq 0 ] || { echo 'mock stow conflict' >&2; exit "$FAKE_STOW_RC"; }
case ${FAKE_STOW_ACK:-valid} in
    absent) rm -f meta/dotfiles-sync-unix; exit 0 ;;
    unchanged) exit 0 ;;
    incomplete) printf '%s\n' "$HOME" "$(uname -s)" "$1" >meta/dotfiles-sync-unix; exit 0 ;;
esac
printf '%s\n' "${FAKE_ACK_HOME:-$HOME}" "${FAKE_ACK_PLATFORM:-$(uname -s)}" \
    "${FAKE_ACK_HOST-$1}" "${FAKE_ACK_HEAD:-$(cat meta/head)}" >meta/dotfiles-sync-unix
if [ "${FAKE_STOW_ACK:-valid}" = changed-head ]; then printf 'changed-during-stow\n' >meta/head; fi
SH
chmod +x "$FAKE_BIN/git"

run_interactive() {
    case_name=$1
    shift
    : >"$GIT_LOG"
    : >"$STOW_LOG"
    LAST_STDOUT="$TEST_TMP/$case_name.stdout"
    LAST_STDERR="$TEST_TMP/$case_name.stderr"
    env -u _DOTFILES_CHECKED -u DOTFILES_HOST \
        HOME="$TEST_TMP/home" PATH="$FAKE_BIN:/usr/bin:/bin" \
        DOTFILES_DIR="$FAKE_REPO" SH_UPDATER="$SH_UPDATER" \
        FAKE_REPO="$FAKE_REPO" GIT_LOG="$GIT_LOG" STOW_LOG="$STOW_LOG" \
        "$@" bash --noprofile --norc -uic '
            printf "old\n" >"$FAKE_REPO/meta/head"
            printf "0\n" >"$FAKE_REPO/meta/status-count"
            rm -f "$FAKE_REPO/meta/dotfiles-sync-unix.submodules-pending"
            if [ -n "${FAKE_PENDING:-}" ]; then
                printf "%s\n" "$FAKE_PENDING" >"$FAKE_REPO/meta/dotfiles-sync-unix.submodules-pending"
            fi
            rm -f "$FAKE_REPO/meta/dotfiles-sync-unix"
            if [ "${FAKE_CONFIGURED:-1}" = 1 ]; then
                printf "%s\n" "${FAKE_SAVED_HOME:-$HOME}" "${FAKE_PLATFORM:-$(uname -s)}" "${FAKE_HOST-host-a}" "${FAKE_APPLIED-old}" >"$FAKE_REPO/meta/dotfiles-sync-unix"
            fi
            if [ -n "${FAKE_LOCK:-}" ]; then
                mkdir "$FAKE_REPO/meta/dotfiles-sync-unix.lock"
                case $FAKE_LOCK in
                    active) printf "%s\n" "$$" >"$FAKE_REPO/meta/dotfiles-sync-unix.lock/pid" ;;
                    stale)
                        printf "99999999\n" >"$FAKE_REPO/meta/dotfiles-sync-unix.lock/pid"
                        printf "interrupted log\n" >"$FAKE_REPO/meta/dotfiles-sync-unix.lock/stow.log"
                        ;;
                esac
            fi
            trap '\''printf "caller-trap\n"'\'' EXIT
            before_trap=$(trap -p EXIT)
            before_flags=$-
            before_umask=$(umask)
            . "$SH_UPDATER"
            [ "$(trap -p EXIT)" = "$before_trap" ] || printf "trap-leaked\n"
            [ "$-" = "$before_flags" ] || printf "flags-leaked\n"
            [ "$(umask)" = "$before_umask" ] || printf "umask-leaked\n"
            printf "marker=%s\n" "${_DOTFILES_CHECKED:-missing}"
            bash -uc '\''printf "child-marker=%s\\n" "$_DOTFILES_CHECKED"'\''
            if declare -F _dotfiles_update_check >/dev/null || declare -p _df_dir >/dev/null 2>&1; then
                printf "state-leaked\n"
            fi
            if [ -n "${FAKE_LOCK:-}" ]; then
                rm -f "$FAKE_REPO/meta/dotfiles-sync-unix.lock/pid"
                rmdir "$FAKE_REPO/meta/dotfiles-sync-unix.lock" 2>/dev/null || true
            fi
        ' >"$LAST_STDOUT" 2>"$LAST_STDERR"
    grep -Fxq 'marker=1' "$LAST_STDOUT"
    grep -Fxq 'child-marker=1' "$LAST_STDOUT"
    grep -Fxq 'caller-trap' "$LAST_STDOUT"
    ! grep -Fq 'leaked' "$LAST_STDOUT"
    [ ! -d "$FAKE_REPO/meta/dotfiles-sync-unix.lock" ]
}

no_stow() { [ ! -s "$STOW_LOG" ]; }
no_fetch() { ! grep -Fq '[fetch]' "$GIT_LOG"; }
no_pull() { ! grep -Fq '[pull]' "$GIT_LOG"; }
applied_host() { grep -Fxq "[$1]" "$STOW_LOG"; }

# Non-interactive and disabled/session-marked shells cannot touch Git.
: >"$GIT_LOG"
env -u _DOTFILES_CHECKED HOME="$TEST_TMP/home" PATH="$FAKE_BIN:/usr/bin:/bin" \
    SH_UPDATER="$SH_UPDATER" GIT_LOG="$GIT_LOG" \
    bash --noprofile --norc -uc '. "$SH_UPDATER"; test -z "${_DOTFILES_CHECKED:-}"'
[ ! -s "$GIT_LOG" ]
run_interactive already-checked _DOTFILES_CHECKED=1
[ ! -s "$GIT_LOG" ]
run_interactive disabled DOTFILES_AUTO_UPDATE=0
[ ! -s "$GIT_LOG" ]
run_interactive missing-repo DOTFILES_DIR="$TEST_TMP/missing repo"
[ ! -s "$GIT_LOG" ]

run_interactive up-to-date
no_stow
no_pull
! grep -Fq '[dotfiles]' "$LAST_STDOUT"
run_interactive fetch-failure FAKE_FETCH_RC=17
no_stow
no_pull
run_interactive invalid-count FAKE_BEHIND=not-a-number
no_stow
no_pull
run_interactive pull-failure FAKE_BEHIND=2 FAKE_PULL_RC=19
no_stow
grep -Fq 'Fast-forward pull failed' "$LAST_STDOUT"
run_interactive success FAKE_BEHIND=3
applied_host host-a
grep -Fq '[pull][--ff-only][--quiet]' "$GIT_LOG"
grep -Fq '[submodule][update][--init][--recursive][--quiet]' "$GIT_LOG"
grep -Fq 'Stow completed' "$LAST_STDOUT"
[ "$(tail -n 1 "$FAKE_REPO/meta/dotfiles-sync-unix")" = new ]

run_interactive submodule-failure FAKE_BEHIND=1 FAKE_SUBMODULE_RC=20
no_stow
grep -Fq 'Submodule update failed' "$LAST_STDOUT"
[ "$(cat "$FAKE_REPO/meta/dotfiles-sync-unix.submodules-pending")" = new ]
run_interactive user-gitlink FAKE_GITLINK_DIRTY=' M submodule' FAKE_APPLIED=older
no_fetch
no_stow
run_interactive marked-submodule-retry FAKE_GITLINK_DIRTY=' M submodule' FAKE_PENDING=old FAKE_APPLIED=older FAKE_FETCH_RC=1
applied_host host-a
[ ! -e "$FAKE_REPO/meta/dotfiles-sync-unix.submodules-pending" ]
run_interactive wrong-head-marker FAKE_GITLINK_DIRTY=' M submodule' FAKE_PENDING=another-head FAKE_APPLIED=older
no_fetch
no_stow
run_interactive marked-dirty-submodule FAKE_PENDING=old FAKE_SUBMODULE_DIRTY=1 FAKE_APPLIED=older
no_fetch
no_stow
run_interactive disabled-stow FAKE_BEHIND=1 DOTFILES_AUTO_STOW=0
no_stow
grep -Fq '[submodule][update]' "$GIT_LOG"
run_interactive dirty FAKE_DIRTY=' M common/config'
no_fetch
no_stow
run_interactive status-failure FAKE_STATUS_RC=21
no_fetch
no_stow
run_interactive dirty-submodule FAKE_SUBMODULE_DIRTY=1
no_fetch
no_stow
run_interactive concurrent-edit FAKE_BEHIND=1 FAKE_POST_DIRTY='?? new-config'
no_stow

# Retry an unapplied local HEAD even offline, without requiring a new pull.
run_interactive retry-offline FAKE_APPLIED=older FAKE_FETCH_RC=1
applied_host host-a
no_pull
run_interactive retry-no-pull FAKE_APPLIED=older
applied_host host-a
no_pull
run_interactive stow-failure FAKE_APPLIED=older FAKE_STOW_RC=23
applied_host host-a
grep -Fq 'mock stow conflict' "$LAST_STDERR"
grep -Fq 'Stow failed' "$LAST_STDOUT"
[ "$(tail -n 1 "$FAKE_REPO/meta/dotfiles-sync-unix")" = older ]

# Exit zero is not success without complete, correctly bound acknowledgement.
for acknowledgement in absent unchanged incomplete changed-head; do
    run_interactive "ack-$acknowledgement" FAKE_APPLIED=older FAKE_STOW_ACK="$acknowledgement"
    applied_host host-a
    grep -Fq 'Installer did not acknowledge this revision' "$LAST_STDOUT"
    ! grep -Fq 'Stow completed' "$LAST_STDOUT"
done
for binding in FAKE_ACK_HOME FAKE_ACK_PLATFORM FAKE_ACK_HOST FAKE_ACK_HEAD; do
    run_interactive "ack-$binding" FAKE_APPLIED=older "$binding=incorrect"
    applied_host host-a
    grep -Fq 'Installer did not acknowledge this revision' "$LAST_STDOUT"
    ! grep -Fq 'Stow completed' "$LAST_STDOUT"
done

# Common-only is configured; an unknown home/platform/host must not be guessed.
run_interactive common-only FAKE_HOST= FAKE_APPLIED=older
applied_host ''
run_interactive explicit-host DOTFILES_HOST=host-b
applied_host host-b
run_interactive explicit-common DOTFILES_HOST=
applied_host ''
run_interactive unknown-host FAKE_CONFIGURED=0
no_stow
grep -Fq 'once to enable automatic stow' "$LAST_STDOUT"
run_interactive other-home FAKE_SAVED_HOME=/another/home
no_stow
run_interactive other-platform FAKE_PLATFORM=AnotherOS
no_stow
run_interactive invalid-host DOTFILES_HOST=../outside
no_stow
run_interactive missing-host DOTFILES_HOST=missing-host
no_stow
run_interactive windows-host DOTFILES_HOST=win
no_stow

run_interactive locked FAKE_LOCK=active FAKE_APPLIED=older
no_fetch
no_stow
run_interactive stale-lock FAKE_LOCK=stale FAKE_APPLIED=older
applied_host host-a
run_interactive incomplete-lock FAKE_LOCK=incomplete FAKE_APPLIED=older
no_fetch
no_stow
grep -Fq 'Incomplete update lock' "$LAST_STDOUT"

# These cases use actual Git and file://-free local remotes, not mocked Git.
# Nothing can use the operator's Git config, home, hooks, or remote credentials.
REAL_GIT=$(command -v git)
REAL_PATH=$PATH
REAL_CASE_NUMBER=0
: >"$TEST_TMP/gitconfig"
mkdir "$TEST_TMP/empty-git-template"
real_git() {
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_CONFIG_COUNT \
        -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
        -u GIT_CONFIG -u GIT_CONFIG_PARAMETERS -u GIT_SHALLOW_FILE -u GIT_REPLACE_REF_BASE \
        GIT_TEMPLATE_DIR="$TEST_TMP/empty-git-template" \
        HOME="$TEST_TMP/home" GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig" \
        GIT_CONFIG_NOSYSTEM=1 "$REAL_GIT" "$@"
}
new_real_fixture() {
    REAL_CASE_NUMBER=$((REAL_CASE_NUMBER + 1))
    REAL_ROOT="$TEST_TMP/real fixture $REAL_CASE_NUMBER"
    REAL_REMOTE="$REAL_ROOT/remote.git"
    REAL_SEED="$REAL_ROOT/seed"
    REAL_REPO="$REAL_ROOT/checkout with spaces"
    real_git init --bare --quiet --initial-branch=main "$REAL_REMOTE"
    real_git init --quiet --initial-branch=main "$REAL_SEED"
    real_git -C "$REAL_SEED" config user.name 'Dotfiles tests'
    real_git -C "$REAL_SEED" config user.email 'dotfiles-tests@example.invalid'
    mkdir "$REAL_SEED/host-a"
    printf 'host fixture\n' >"$REAL_SEED/host-a/config"
    printf 'initial configuration\n' >"$REAL_SEED/settings.txt"
    cat >"$REAL_SEED/stow-all.sh" <<'SH'
#!/bin/sh
state=$(git rev-parse --git-path dotfiles-sync-unix) || exit 70
printf '[%s]\n' "$1" >>"$state.installs"
if [ -n "${REAL_STOW_GATE:-}" ]; then
    : >"$REAL_STOW_GATE/entered"
    count=0
    while [ ! -f "$REAL_STOW_GATE/release" ]; do
        count=$((count + 1))
        [ "$count" -lt 200 ] || { echo 'Timed out waiting for test gate.' >&2; exit 71; }
        sleep 0.05
    done
fi
[ "${REAL_STOW_FAILURE:-0}" = 0 ] || { echo 'Injected fixture installer failure.' >&2; exit 72; }
[ "${REAL_STOW_NO_ACK:-0}" = 0 ] || exit 0
printf '%s\n' "$HOME" "$(uname -s)" "$1" "$(git rev-parse HEAD)" >"$state"
SH
    real_git -C "$REAL_SEED" add stow-all.sh settings.txt host-a/config
    real_git -C "$REAL_SEED" commit --quiet -m 'Initial test fixture'
    real_git -C "$REAL_SEED" remote add origin "$REAL_REMOTE"
    real_git -C "$REAL_SEED" push --quiet --set-upstream origin main
    real_git clone --quiet "$REAL_REMOTE" "$REAL_REPO"
    real_git -C "$REAL_REPO" config user.name 'Dotfiles tests'
    real_git -C "$REAL_REPO" config user.email 'dotfiles-tests@example.invalid'
    REAL_STATE="$REAL_REPO/.git/dotfiles-sync-unix"
    printf '%s\n' "$TEST_TMP/home" "$(uname -s)" host-a pending >"$REAL_STATE"
}
advance_real_remote() {
    printf 'remote update\n' >>"$REAL_SEED/settings.txt"
    real_git -C "$REAL_SEED" add settings.txt
    real_git -C "$REAL_SEED" commit --quiet -m 'Remote test update'
    real_git -C "$REAL_SEED" push --quiet
}
real_hook() {
    local output_name=$1
    shift
    env -u _DOTFILES_CHECKED -u DOTFILES_HOST -u GIT_DIR -u GIT_WORK_TREE \
        -u GIT_INDEX_FILE -u GIT_CONFIG_COUNT \
        -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
        -u GIT_CONFIG -u GIT_CONFIG_PARAMETERS -u GIT_SHALLOW_FILE -u GIT_REPLACE_REF_BASE \
        GIT_TEMPLATE_DIR="$TEST_TMP/empty-git-template" \
        HOME="$TEST_TMP/home" PATH="$REAL_PATH" \
        GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1 \
        DOTFILES_DIR="$REAL_REPO" DOTFILES_AUTO_UPDATE=1 DOTFILES_AUTO_STOW=1 \
        SH_UPDATER="$SH_UPDATER" "$@" bash --noprofile --norc -uic '
            . "$SH_UPDATER"
            printf "marker=%s\n" "${_DOTFILES_CHECKED:-missing}"
        ' >"$REAL_ROOT/$output_name.stdout" 2>"$REAL_ROOT/$output_name.stderr"
    grep -Fxq 'marker=1' "$REAL_ROOT/$output_name.stdout"
}
assert_real_acknowledged() {
    [ "$(tail -n 1 "$REAL_STATE")" = "$(real_git -C "$REAL_REPO" rev-parse HEAD)" ]
    [ ! -d "$REAL_STATE.lock" ]
    [ -z "$(real_git -C "$REAL_REPO" status --porcelain)" ]
}

new_real_fixture
advance_real_remote
real_hook fast-forward
[ "$(real_git -C "$REAL_REPO" rev-parse HEAD)" = "$(real_git -C "$REAL_SEED" rev-parse HEAD)" ]
grep -Fq 'Stow completed' "$REAL_ROOT/fast-forward.stdout"
assert_real_acknowledged

new_real_fixture
initial_head=$(real_git -C "$REAL_REPO" rev-parse HEAD)
advance_real_remote
printf 'local change\n' >>"$REAL_REPO/settings.txt"
real_hook dirty
[ "$(real_git -C "$REAL_REPO" rev-parse HEAD)" = "$initial_head" ]
[ ! -e "$REAL_STATE.installs" ]
grep -Fq 'Local changes' "$REAL_ROOT/dirty.stdout"

new_real_fixture
advance_real_remote
printf 'local commit\n' >>"$REAL_REPO/settings.txt"
real_git -C "$REAL_REPO" add settings.txt
real_git -C "$REAL_REPO" commit --quiet -m 'Local divergent commit'
local_head=$(real_git -C "$REAL_REPO" rev-parse HEAD)
real_hook diverged
[ "$(real_git -C "$REAL_REPO" rev-parse HEAD)" = "$local_head" ]
[ ! -e "$REAL_STATE.installs" ]
grep -Fq 'Fast-forward pull failed' "$REAL_ROOT/diverged.stdout"

# Three sessions at the same real HEAD: failure, missing acknowledgement, retry.
new_real_fixture
real_hook failed REAL_STOW_FAILURE=1
[ "$(tail -n 1 "$REAL_STATE")" = pending ]
grep -Fq 'Stow failed' "$REAL_ROOT/failed.stdout"
real_hook unacknowledged REAL_STOW_NO_ACK=1
[ "$(tail -n 1 "$REAL_STATE")" = pending ]
grep -Fq 'Installer did not acknowledge this revision' "$REAL_ROOT/unacknowledged.stdout"
! grep -Fq 'Stow completed' "$REAL_ROOT/unacknowledged.stdout"
real_hook retry
[ "$(wc -l <"$REAL_STATE.installs" | tr -d ' ')" = 3 ]
assert_real_acknowledged

# Hold the first actual interactive-shell process inside its installer while
# a second independent shell tries to update the same checkout and home.
new_real_fixture
REAL_GATE="$REAL_REPO/.git/test-gate"
mkdir "$REAL_GATE"
real_hook owner REAL_STOW_GATE="$REAL_GATE" &
REAL_CHILD_PID=$!
gate_attempt=0
while [ ! -f "$REAL_GATE/entered" ]; do
    gate_attempt=$((gate_attempt + 1))
    if [ "$gate_attempt" -ge 200 ]; then
        echo 'ERROR: lock owner did not reach the test gate.' >&2
        exit 1
    fi
    sleep 0.05
done
real_hook contender
[ "$(wc -l <"$REAL_STATE.installs" | tr -d ' ')" = 1 ]
[ "$(tail -n 1 "$REAL_STATE")" = pending ]
[ -d "$REAL_STATE.lock" ]
! grep -Fq '[dotfiles]' "$REAL_ROOT/contender.stdout"
: >"$REAL_GATE/release"
wait "$REAL_CHILD_PID"
REAL_CHILD_PID=
assert_real_acknowledged
real_hook released
[ "$(wc -l <"$REAL_STATE.installs" | tr -d ' ')" = 1 ]
! grep -Fq '[dotfiles]' "$REAL_ROOT/released.stdout"
echo 'unix-update-hooks-real=PASS (fast-forward, dirty, divergence, retry, process lock)'

if command -v pwsh >/dev/null 2>&1; then
    for f in "$PS_UPDATER" "$PS_PROFILE" "$PS_HELPER"; do
        PS_FILE="$f" pwsh -NoProfile -NonInteractive -Command '
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $env:PS_FILE, [ref]$null, [ref]$errors)
            if ($errors) { $errors | ForEach-Object { $_.ToString() }; exit 1 }
        '
    done
    if [ -f "$REPO_ROOT/tests/update-hooks.ps1" ]; then
        PS_FILE="$REPO_ROOT/tests/update-hooks.ps1" pwsh -NoProfile -NonInteractive -Command '$ErrorActionPreference = "Stop"; & $env:PS_FILE; exit 0'
    fi
else
    echo 'windows-update-hooks=SKIP (pwsh not installed; native PowerShell suite required in Windows CI)'
fi

echo "update-hooks=PASS"
