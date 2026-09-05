#!/bin/bash

set -euo pipefail

# Exercise both login implementations with isolated homes and mocked mutations.
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SH_UPDATER="$REPO_ROOT/dotfiles-update.sh"
PS_UPDATER="$REPO_ROOT/dotfiles-update.ps1"
PS_HELPER="$REPO_ROOT/dotfiles-auto-stow.ps1"
PS_PROFILE="$REPO_ROOT/win/powershell/Documents/PowerShell/profile.ps1"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-update-hooks.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM

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
printf '%s\n' "$HOME" "$(uname -s)" "$1" "$(cat meta/head)" >meta/dotfiles-sync-unix
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
            . "$SH_UPDATER"
            [ "$(trap -p EXIT)" = "$before_trap" ] || printf "trap-leaked\n"
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
fi

echo "update-hooks=PASS"
