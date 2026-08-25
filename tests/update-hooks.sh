#!/bin/bash

set -euo pipefail

# The two login updaters must keep one contract: same opt-out, same session
# marker, fast-forward only, and never an automatic re-stow. Only the POSIX one
# can be executed here, so the parity checks are static; the PowerShell one
# gets a parse check when pwsh is present (GitHub's Ubuntu runners ship it).

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SH_UPDATER="$REPO_ROOT/dotfiles-update.sh"
PS_UPDATER="$REPO_ROOT/dotfiles-update.ps1"
PS_PROFILE="$REPO_ROOT/win/powershell/Documents/PowerShell/profile.ps1"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-update-hooks.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM

for f in "$SH_UPDATER" "$PS_UPDATER" "$PS_PROFILE"; do
    if [ ! -r "$f" ]; then
        echo "ERROR: missing $f" >&2
        exit 1
    fi
done

# Shared contract, asserted on both implementations.
for token in _DOTFILES_CHECKED DOTFILES_AUTO_UPDATE DOTFILES_DIR --ff-only 'submodule update'; do
    for f in "$SH_UPDATER" "$PS_UPDATER"; do
        if ! grep -Fq -e "$token" "$f"; then
            echo "ERROR: $(basename "$f") lost the '$token' part of the contract" >&2
            exit 1
        fi
    done
done

# Every `pwsh -Command ...` loads the profile, so without the no-console guard
# the hook would fetch on every scripted invocation.
grep -Fq '[Console]::IsOutputRedirected' "$PS_UPDATER"

# The profile must actually reach the updater, and only at the end.
grep -Fq 'dotfiles-update.ps1' "$PS_PROFILE"

# Re-stowing stays manual, and the hint must say elevated: a login shell is not
# elevated, so an automatic or unelevated re-stow would create untrusted links.
if [ "$(grep -c 'stow-all\.ps1' "$PS_UPDATER")" -ne 1 ]; then
    echo "ERROR: dotfiles-update.ps1 should mention stow-all.ps1 exactly once" >&2
    exit 1
fi
if ! grep -Eq "Write-DotfilesNote '.*stow-all\.ps1 from an elevated PowerShell" "$PS_UPDATER"; then
    echo "ERROR: the re-stow hint must be a message and must say elevated" >&2
    exit 1
fi

# 'Stop' would turn a failed git fetch into a terminating error on 7.4+ and
# abort the profile, so the script must opt out and check exit codes instead.
grep -Fq 'PSNativeCommandUseErrorActionPreference = $false' "$PS_UPDATER"

# Execute the POSIX updater against an isolated repository and a stateful fake
# git. This covers the login behavior instead of only matching source tokens.
FAKE_BIN="$TEST_TMP/bin"
FAKE_REPO="$TEST_TMP/repo with spaces"
GIT_LOG="$TEST_TMP/git.log"
mkdir -p "$FAKE_BIN" "$FAKE_REPO/.git" "$TEST_TMP/home" "$TEST_TMP/no-git"

cat >"$FAKE_BIN/git" <<'SH'
#!/bin/sh
{
    for argument do
        printf '[%s]' "$argument"
    done
    printf '\n'
} >>"$GIT_LOG"

case ${3:-} in
    fetch)
        exit "${FAKE_FETCH_RC:-0}"
        ;;
    rev-list)
        [ "${FAKE_REV_RC:-0}" -eq 0 ] || exit "$FAKE_REV_RC"
        printf '%s\n' "${FAKE_BEHIND:-0}"
        ;;
    pull)
        exit "${FAKE_PULL_RC:-0}"
        ;;
    submodule)
        exit "${FAKE_SUBMODULE_RC:-0}"
        ;;
    *)
        exit 90
        ;;
esac
SH
chmod +x "$FAKE_BIN/git"

assert_calls() {
    expected="$TEST_TMP/expected-git.log"
    if [ "$#" -eq 0 ]; then
        : >"$expected"
    else
        printf '%s\n' "$@" >"$expected"
    fi
    if ! cmp -s "$expected" "$GIT_LOG"; then
        echo "ERROR: unexpected git call sequence" >&2
        diff -u "$expected" "$GIT_LOG" >&2 || true
        exit 1
    fi
}

run_interactive() {
    case_name=$1
    shift
    : >"$GIT_LOG"
    LAST_STDOUT="$TEST_TMP/$case_name.stdout"
    LAST_STDERR="$TEST_TMP/$case_name.stderr"
    env -u _DOTFILES_CHECKED \
        HOME="$TEST_TMP/home" \
        PATH="$FAKE_BIN:/usr/bin:/bin" \
        DOTFILES_DIR="$FAKE_REPO" \
        SH_UPDATER="$SH_UPDATER" \
        GIT_LOG="$GIT_LOG" \
        "$@" \
        bash --noprofile --norc -uic '
            . "$SH_UPDATER"
            printf "marker=%s\n" "${_DOTFILES_CHECKED:-missing}"
            bash -uc '\''printf "child-marker=%s\\n" "$_DOTFILES_CHECKED"'\''
            if declare -F _dotfiles_update_check >/dev/null; then
                printf "function-leaked\n"
            fi
            if declare -p _df_dir >/dev/null 2>&1 ||
                declare -p _df_behind >/dev/null 2>&1; then
                printf "variable-leaked\n"
            fi
        ' >"$LAST_STDOUT" 2>"$LAST_STDERR"
}

fetch_call="[-C][$FAKE_REPO][fetch][--quiet]"
rev_call="[-C][$FAKE_REPO][rev-list][--count][HEAD..@{upstream}]"
pull_call="[-C][$FAKE_REPO][pull][--ff-only][--quiet]"
submodule_call="[-C][$FAKE_REPO][submodule][update][--init][--recursive][--quiet]"

# Non-interactive sourcing and a pre-existing session marker are true no-ops.
: >"$GIT_LOG"
env -u _DOTFILES_CHECKED \
    HOME="$TEST_TMP/home" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    DOTFILES_DIR="$FAKE_REPO" \
    SH_UPDATER="$SH_UPDATER" \
    GIT_LOG="$GIT_LOG" \
    bash --noprofile --norc -uc \
    '. "$SH_UPDATER"; printf "marker=%s\n" "${_DOTFILES_CHECKED:-missing}"' \
    >"$TEST_TMP/noninteractive.stdout"
grep -Fxq 'marker=missing' "$TEST_TMP/noninteractive.stdout"
assert_calls

run_interactive already-checked _DOTFILES_CHECKED=1
grep -Fxq 'marker=1' "$LAST_STDOUT"
assert_calls

# Disabled, missing-git, and missing-repository paths still finish cleanly and
# set the exported session marker so nested shells do not retry.
run_interactive disabled DOTFILES_AUTO_UPDATE=0
grep -Fxq 'marker=1' "$LAST_STDOUT"
grep -Fxq 'child-marker=1' "$LAST_STDOUT"
! grep -Fq 'leaked' "$LAST_STDOUT"
assert_calls

: >"$GIT_LOG"
env -u _DOTFILES_CHECKED \
    HOME="$TEST_TMP/home" \
    PATH="$TEST_TMP/no-git" \
    DOTFILES_DIR="$FAKE_REPO" \
    SH_UPDATER="$SH_UPDATER" \
    GIT_LOG="$GIT_LOG" \
    /bin/bash --noprofile --norc -uic \
    '. "$SH_UPDATER"; printf "marker=%s\n" "${_DOTFILES_CHECKED:-missing}"' \
    >"$TEST_TMP/missing-git.stdout" 2>"$TEST_TMP/missing-git.stderr"
grep -Fxq 'marker=1' "$TEST_TMP/missing-git.stdout"
assert_calls

missing_repo="$TEST_TMP/missing repo"
run_interactive missing-repo DOTFILES_DIR="$missing_repo"
grep -Fxq 'marker=1' "$LAST_STDOUT"
assert_calls

# Each early-return branch stops at the exact failed or empty operation.
run_interactive fetch-failure FAKE_FETCH_RC=17
assert_calls "$fetch_call"
! grep -Fq 'pulling' "$LAST_STDOUT"

run_interactive rev-failure FAKE_REV_RC=18
assert_calls "$fetch_call" "$rev_call"
! grep -Fq 'pulling' "$LAST_STDOUT"

run_interactive up-to-date FAKE_BEHIND=0
assert_calls "$fetch_call" "$rev_call"
! grep -Fq 'pulling' "$LAST_STDOUT"

run_interactive invalid-count FAKE_BEHIND=not-a-number
assert_calls "$fetch_call" "$rev_call"
! grep -Fq 'pulling' "$LAST_STDOUT"

run_interactive pull-failure FAKE_BEHIND=2 FAKE_PULL_RC=19
assert_calls "$fetch_call" "$rev_call" "$pull_call"
grep -Fq '2 new commit(s) available' "$LAST_STDOUT"
grep -Fq 'Fast-forward pull failed' "$LAST_STDOUT"
grep -Fq "$FAKE_REPO" "$LAST_STDOUT"
! grep -Fq 'Pulled successfully' "$LAST_STDOUT"

# A successful pull updates submodules best-effort, reports the manual restow,
# and never invokes stow itself.
run_interactive success FAKE_BEHIND=3
assert_calls "$fetch_call" "$rev_call" "$pull_call" "$submodule_call"
grep -Fq '3 new commit(s) available' "$LAST_STDOUT"
grep -Fq 'Pulled successfully' "$LAST_STDOUT"
grep -Fq 'stow-all.sh' "$LAST_STDOUT"
grep -Fq 'exec zsh' "$LAST_STDOUT"
grep -Fxq 'marker=1' "$LAST_STDOUT"
grep -Fxq 'child-marker=1' "$LAST_STDOUT"
! grep -Fq 'leaked' "$LAST_STDOUT"
! grep -Eq '\[stow\]|(^|/)stow([[:space:]]|$)' "$GIT_LOG"

run_interactive submodule-failure FAKE_BEHIND=1 FAKE_SUBMODULE_RC=20
assert_calls "$fetch_call" "$rev_call" "$pull_call" "$submodule_call"
grep -Fq 'Pulled successfully' "$LAST_STDOUT"

if command -v pwsh >/dev/null 2>&1; then
    for f in "$PS_UPDATER" "$PS_PROFILE"; do
        PS_FILE="$f" pwsh -NoProfile -NonInteractive -Command '
            $path = $env:PS_FILE
            if (-not (Test-Path -LiteralPath $path)) {
                Write-Output "file not found at $path"
                exit 1
            }
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $path, [ref]$null, [ref]$errors)
            if ($errors) { $errors | ForEach-Object { $_.ToString() }; exit 1 }
        '
    done
fi

echo "update-hooks=PASS"
