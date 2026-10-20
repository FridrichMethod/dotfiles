#!/bin/bash

set -euo pipefail

# Hermetic: the provisioning exports (DOTFILES_AUTO_UPDATE=0 and the like,
# docs/bootstrap.md) and other dotfiles knobs never reach the code under
# test from the caller; each case sets what it needs.
unset DOTFILES_AUTO_UPDATE DOTFILES_AUTO_STOW DOTFILES_HOST DOTFILES_DIR _DOTFILES_CHECKED \
    DOTFILES_STOW_WITHOUT_OH_MY_ZSH DOTFILES_COLOR AWESOME_SKILLS_AUTO_UPDATE AWESOME_SKILLS_FORCE \
    AWESOME_SKILLS_BG AWESOME_SKILLS_INSTALLER_URL AWESOME_SKILLS_REFRESH_DAYS _AWESOME_SKILLS_CHECKED

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$REPO_ROOT/stow-all.sh"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-stow-all.XXXXXX")"
# macOS TMPDIR ends in '/', and /var may itself be a symlink. Compare the
# installer's cd/pwd paths with one physical fixture root, not mktemp's spelling.
TEST_TMP="$(cd -- "$TEST_TMP" && pwd -P)"
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM

FIXTURE="$TEST_TMP/fixture"
FAKE_BIN="$TEST_TMP/bin"
TEST_HOME="$TEST_TMP/home"
EVENT_LOG="$TEST_TMP/events.log"
CHECK_LOG="$TEST_TMP/checks.log"
export CHECK_LOG
# The real codex-instructions-sync needs only a stdlib Python 3.11+; the other
# helpers are fakes that record their calls.
SYNC_PYTHON="${DOTFILES_SYNC_PYTHON:-$REPO_ROOT/.venv-sync/bin/python}"
if [[ ! -x "$SYNC_PYTHON" ]]; then
    echo 'ERROR: AI-sync runtime missing; run ./setup-sync.sh explicitly.' >&2
    exit 1
fi
export DOTFILES_COLOR=auto
mkdir -p "$FIXTURE/.git" "$FAKE_BIN" "$TEST_HOME"
mkdir "$FIXTURE/lib"
cp "$REPO_ROOT/lib/terminal.sh" "$FIXTURE/lib/terminal.sh"
cp "$INSTALLER" "$FIXTURE/stow-all.sh"
cp "$REPO_ROOT/.stowrc" "$FIXTURE/.stowrc"
chmod +x "$FIXTURE/stow-all.sh"

assert_mode() {
    python3 - "$1" "$2" <<'PY'
import os
import sys

actual = os.stat(sys.argv[1]).st_mode & 0o777
expected = int(sys.argv[2], 8)
assert actual == expected, f"{sys.argv[1]}: mode {actual:o}, expected {expected:o}"
PY
}

# A bare "! grep" never fails under set -e; this one does.
refute_grep() {
    if grep -Fq -- "$1" "$2"; then
        echo "ERROR: unexpected '$1' in $2" >&2
        exit 1
    fi
}

assert_events() {
    expected="$TEST_TMP/expected-events.log"
    if [ "$#" -eq 0 ]; then
        : >"$expected"
    else
        printf '%s\n' "$@" >"$expected"
    fi
    if ! cmp -s "$expected" "$EVENT_LOG"; then
        echo "ERROR: unexpected installer event sequence" >&2
        diff -u "$expected" "$EVENT_LOG" >&2 || true
        exit 1
    fi
}

cat >"$FAKE_BIN/stow" <<'SH'
#!/bin/sh
{
    printf 'stow:'
    for argument do
        printf '[%s]' "$argument"
    done
    printf '\n'
} >>"$EVENT_LOG"
if [ "${1:-}" = -n ]; then
    # PROBE_PATH records whether a home path still exists at dry-run time.
    if [ -n "${PROBE_PATH:-}" ]; then
        if [ -e "$PROBE_PATH" ] || [ -L "$PROBE_PATH" ]; then
            echo 'probe:present' >>"$EVENT_LOG"
        else
            echo 'probe:absent' >>"$EVENT_LOG"
        fi
    fi
    [ "${STOW_DRY_RC:-0}" = 0 ] || echo "WARNING! stowing would cause conflicts" >&2
    exit "${STOW_DRY_RC:-0}"
fi
exit "${STOW_RC:-0}"
SH

cat >"$FAKE_BIN/git" <<'SH'
#!/bin/sh
# Metadata reads are tested through their resulting state, not event ordering.
case ${1:-} in
    rev-parse)
        if [ "${2:-}" = --git-path ]; then
            printf '%s/.git/%s\n' "$PWD" "$3"
        else
            printf 'test-head\n'
        fi
        exit 0
        ;;
    status)
        [ "${STATUS_RC:-0}" = 0 ] || exit "$STATUS_RC"
        printf '%s' "${INSTALL_DIRTY:-}"
        exit 0
        ;;
    ls-files)
        # The fixture tracks one link, codex-as into the coding-agent-kit checkout.
        printf '120000 %s 0\tcommon/codex/.local/bin/codex-as\0' 0000000000000000000000000000000000000000
        exit 0
        ;;
esac
{
    printf 'git:'
    for argument do
        printf '[%s]' "$argument"
    done
    printf '\n'
} >>"$EVENT_LOG"

if [ "${3:-}" = "--get-regexp" ]; then
    [ "${FILTER_PRESENT:-0}" = "1" ]
    exit
fi
if [ "${3:-}" = "--remove-section" ]; then
    exit 0
fi
exit 91
SH
chmod +x "$FAKE_BIN/stow" "$FAKE_BIN/git"

mkdir -p \
    "$FIXTURE/common/alpha" \
    "$FIXTURE/common/claude/.local/bin" \
    "$FIXTURE/common/claude/.claude" \
    "$FIXTURE/common/codex/.local/bin" \
    "$FIXTURE/common/codex/.codex/rules" \
    "$FIXTURE/host-a/beta" \
    "$FIXTURE/host-a/claude/.claude" \
    "$FIXTURE/host-a/codex/.codex/rules" \
    "$FIXTURE/host-a/fcitx5/.local/bin" \
    "$FIXTURE/host-a/fcitx5/.config/fcitx5" \
    "$FIXTURE/host-a/sherlock-kit/.claude/rules" \
    "$FIXTURE/rules-fixture"
# The codex-as launcher is a package link into the coding-agent-kit checkout,
# which the installer only warns about while that link dangles.
mkdir -p "$FIXTURE/common/codex/coding-agent-kit/bin"
printf '%s\n' '#!/bin/sh' >"$FIXTURE/common/codex/coding-agent-kit/bin/codex-as"
ln -s ../../coding-agent-kit/bin/codex-as "$FIXTURE/common/codex/.local/bin/codex-as"

printf '%s\n' 'common-claude' >"$FIXTURE/common/claude/.claude/settings.json"
printf '%s\n' 'common-codex' >"$FIXTURE/common/codex/.codex/config.toml"
printf '%s\n' 'common-rules' >"$FIXTURE/common/codex/.codex/rules/portable.rules"
printf '%s\n' 'common-agents' >"$FIXTURE/common/codex/.codex/AGENTS.md"
printf '%s\n' 'fixture-rules' >"$FIXTURE/rules-fixture/workstation.md"
# A host with rules links them from its sherlock-kit package, as from the submodule.
SHERLOCK_RULES="$FIXTURE/host-a/sherlock-kit/.claude/rules/sherlock-kit.md"
ln -s ../../../../rules-fixture/workstation.md "$SHERLOCK_RULES"
printf '%s\n' 'host-claude' >"$FIXTURE/host-a/claude/.claude/settings.json"
printf '%s\n' 'host-codex' >"$FIXTURE/host-a/codex/.codex/config.toml"
printf '%s\n' 'host-rules' >"$FIXTURE/host-a/codex/.codex/rules/portable.rules"
printf '%s\n' 'host-fcitx5' >"$FIXTURE/host-a/fcitx5/.config/fcitx5/profile"

cat >"$TEST_TMP/sync-helper" <<'SH'
#!/bin/sh
name=$(basename "$0")
if [ "$name" != fcitx5-profile-sync ]; then
    [ "${1:-}" = --quiet ] || { echo 'Installer must request quiet backend output.' >&2; exit 21; }
    shift
fi
mode=sync
if [ "${1:-}" = --check ]; then
    mode=check
    shift
fi
extra=
if [ "${1:-}" = --append ]; then
    extra="[--append][$2]"
    shift 2
fi
if [ "$mode" = check ]; then
    printf 'check:%s:%s[%s][%s]\n' "$name" "$extra" "$1" "$2" >>"$CHECK_LOG"
    [ "${FAIL_CHECK:-}" != "$name" ] || exit 22
    exit 0
fi
printf 'sync:%s:%s[%s][%s]\n' "$name" "$extra" "$1" "$2" >>"$EVENT_LOG"
[ "${FAIL_SYNC:-}" != "$name" ] || exit 23
SH
for helper in codex-config-sync codex-rules-sync codex-instructions-sync; do
    cp "$TEST_TMP/sync-helper" "$FIXTURE/common/codex/.local/bin/$helper"
done
cp "$TEST_TMP/sync-helper" \
    "$FIXTURE/common/claude/.local/bin/claude-settings-sync"
cp "$TEST_TMP/sync-helper" \
    "$FIXTURE/host-a/fcitx5/.local/bin/fcitx5-profile-sync"
chmod +x \
    "$FIXTURE/common/codex/.local/bin/codex-config-sync" \
    "$FIXTURE/common/codex/.local/bin/codex-rules-sync" \
    "$FIXTURE/common/codex/.local/bin/codex-instructions-sync" \
    "$FIXTURE/common/claude/.local/bin/claude-settings-sync" \
    "$FIXTURE/host-a/fcitx5/.local/bin/fcitx5-profile-sync"

run_fixture() {
    case_name=$1
    shift
    : >"$EVENT_LOG"
    : >"$CHECK_LOG"
    env \
        HOME="$TEST_HOME" \
        PATH="$FAKE_BIN:/usr/bin:/bin" \
        EVENT_LOG="$EVENT_LOG" \
        LC_ALL=C \
        "$@" \
        bash "$FIXTURE/stow-all.sh" \
        >"$TEST_TMP/$case_name.stdout" \
        2>"$TEST_TMP/$case_name.stderr"
}

# Platform and host validation happen before any sync, git, or Stow side effect.
: >"$EVENT_LOG"
if env \
    HOME="$TEST_HOME" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    EVENT_LOG="$EVENT_LOG" \
    bash "$FIXTURE/stow-all.sh" win \
    >"$TEST_TMP/win.stdout" 2>"$TEST_TMP/win.stderr"; then
    echo "ERROR: POSIX installer unexpectedly accepted the win host" >&2
    exit 1
fi
grep -Fq "the 'win' host is installed from Windows" "$TEST_TMP/win.stderr"
grep -Fq '.\stow-all.ps1 win' "$TEST_TMP/win.stderr"
assert_events

if env \
    HOME="$TEST_HOME" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    EVENT_LOG="$EVENT_LOG" \
    bash "$FIXTURE/stow-all.sh" missing-host \
    >"$TEST_TMP/missing-host.stdout" 2>"$TEST_TMP/missing-host.stderr"; then
    echo "ERROR: installer unexpectedly accepted a missing host" >&2
    exit 1
fi
grep -Fq 'host dir not found' "$TEST_TMP/missing-host.stderr"
assert_events

# Common-only setup synchronizes all portable AI baselines before one Stow call.
mv "$FIXTURE/.stowrc" "$FIXTURE/.stowrc.saved"
if run_fixture missing-stowrc; then
    echo 'ERROR: installer accepted missing target/ignore defaults' >&2
    exit 1
fi
grep -Fq 'required .stowrc is missing or unreadable' "$TEST_TMP/missing-stowrc.stderr"
assert_events
[[ ! -s "$CHECK_LOG" ]]
mv "$FIXTURE/.stowrc.saved" "$FIXTURE/.stowrc"

mkdir "$TEST_TMP/no-stow-bin"
ln -s "$(command -v dirname)" "$TEST_TMP/no-stow-bin/dirname"
if env HOME="$TEST_HOME" PATH="$TEST_TMP/no-stow-bin" EVENT_LOG="$EVENT_LOG" \
    /bin/bash "$FIXTURE/stow-all.sh" >"$TEST_TMP/no-stow.stdout" 2>"$TEST_TMP/no-stow.stderr"; then
    echo 'ERROR: installer accepted missing GNU Stow' >&2
    exit 1
fi
grep -Fq 'required GNU Stow is missing' "$TEST_TMP/no-stow.stderr"
assert_events
[[ ! -s "$CHECK_LOG" ]]

run_fixture common-only
printf '%s\n' \
    "check:codex-config-sync:[$FIXTURE/common/codex/.codex/config.toml][$TEST_HOME/.codex/config.toml]" \
    "check:codex-rules-sync:[$FIXTURE/common/codex/.codex/rules/portable.rules][$TEST_HOME/.codex/rules/portable.rules]" \
    "check:codex-instructions-sync:[$FIXTURE/common/codex/.codex/AGENTS.md][$TEST_HOME/.codex/AGENTS.override.md]" \
    "check:claude-settings-sync:[$FIXTURE/common/claude/.claude/settings.json][$TEST_HOME/.claude/settings.json]" \
    >"$TEST_TMP/expected-checks"
cmp "$CHECK_LOG" "$TEST_TMP/expected-checks"
assert_events \
    "stow:[-n][--restow][--no-folding][-d][$FIXTURE/common][alpha][claude][codex]" \
    "sync:codex-config-sync:[$FIXTURE/common/codex/.codex/config.toml][$TEST_HOME/.codex/config.toml]" \
    "sync:codex-rules-sync:[$FIXTURE/common/codex/.codex/rules/portable.rules][$TEST_HOME/.codex/rules/portable.rules]" \
    "sync:codex-instructions-sync:[$FIXTURE/common/codex/.codex/AGENTS.md][$TEST_HOME/.codex/AGENTS.override.md]" \
    "sync:claude-settings-sync:[$FIXTURE/common/claude/.claude/settings.json][$TEST_HOME/.claude/settings.json]" \
    'git:[config][--local][--get-regexp][^filter\.codex-portable\.]' \
    "stow:[--restow][--no-folding][-d][$FIXTURE/common][alpha][claude][codex]"
grep -Fq "Stowing from $FIXTURE" "$TEST_TMP/common-only.stdout"
grep -Fq 'Synchronizing host Codex instructions' "$TEST_TMP/common-only.stdout"
grep -Fq 'Stowing common packages:' "$TEST_TMP/common-only.stdout"
grep -Fq '[dotfiles] [ok] Stow completed (common-only)' "$TEST_TMP/common-only.stdout"
! grep -q "$(printf '\033')" "$TEST_TMP/common-only.stdout" "$TEST_TMP/common-only.stderr"
! grep -Fq 'Stowing host-specific packages:' "$TEST_TMP/common-only.stdout"

# State binds common-only explicitly to this home and platform, outside Git's
# tracked tree. The applied SHA is written only after every operation succeeds.
STATE="$FIXTURE/.git/dotfiles-sync-unix"
printf '%s\n' "$TEST_HOME" "$(uname -s)" '' 'test-head' >"$TEST_TMP/expected-state"
cmp "$STATE" "$TEST_TMP/expected-state"

# Even the final helper's invalid input or missing parser is caught before the
# first helper writes anything; the previous applied state is untouched.
for helper in codex-config-sync codex-rules-sync codex-instructions-sync claude-settings-sync; do
    if run_fixture preflight-failure "FAIL_CHECK=$helper"; then
        echo "ERROR: installer ignored configuration preflight failure: $helper" >&2
        exit 1
    fi
    assert_events
    cmp "$STATE" "$TEST_TMP/expected-state"
    ! grep -Fq '[dotfiles] [ok] Stow completed' "$TEST_TMP/preflight-failure.stdout"
done

# Host baselines override common sources, fcitx5 is host-only, the obsolete Git
# filter is removed when present, and common packages are stowed first.
# The host's sherlock-kit rules link selects the Codex instructions overlay:
# preflight and apply both pass it with --append.
: >"$EVENT_LOG"
: >"$CHECK_LOG"
env \
    HOME="$TEST_HOME" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    EVENT_LOG="$EVENT_LOG" \
    FILTER_PRESENT=1 \
    LC_ALL=C \
    bash "$FIXTURE/stow-all.sh" host-a \
    >"$TEST_TMP/host.stdout" 2>"$TEST_TMP/host.stderr"
printf '%s\n' \
    "check:codex-config-sync:[$FIXTURE/host-a/codex/.codex/config.toml][$TEST_HOME/.codex/config.toml]" \
    "check:codex-rules-sync:[$FIXTURE/host-a/codex/.codex/rules/portable.rules][$TEST_HOME/.codex/rules/portable.rules]" \
    "check:codex-instructions-sync:[--append][$SHERLOCK_RULES][$FIXTURE/common/codex/.codex/AGENTS.md][$TEST_HOME/.codex/AGENTS.override.md]" \
    "check:claude-settings-sync:[$FIXTURE/host-a/claude/.claude/settings.json][$TEST_HOME/.claude/settings.json]" \
    >"$TEST_TMP/expected-checks"
cmp "$CHECK_LOG" "$TEST_TMP/expected-checks"
HOST_BEFORE=(
    "stow:[-n][--restow][--no-folding][-d][$FIXTURE/common][alpha][claude][codex]"
    "stow:[-n][--restow][--no-folding][-d][$FIXTURE/host-a][beta][claude][codex][fcitx5][sherlock-kit]"
    "sync:codex-config-sync:[$FIXTURE/host-a/codex/.codex/config.toml][$TEST_HOME/.codex/config.toml]"
    "sync:codex-rules-sync:[$FIXTURE/host-a/codex/.codex/rules/portable.rules][$TEST_HOME/.codex/rules/portable.rules]"
)
HOST_INSTRUCTIONS="sync:codex-instructions-sync:[--append][$SHERLOCK_RULES][$FIXTURE/common/codex/.codex/AGENTS.md][$TEST_HOME/.codex/AGENTS.override.md]"
HOST_REST=(
    "sync:claude-settings-sync:[$FIXTURE/host-a/claude/.claude/settings.json][$TEST_HOME/.claude/settings.json]"
    "sync:fcitx5-profile-sync:[$FIXTURE/host-a/fcitx5/.config/fcitx5/profile][$TEST_HOME/.config/fcitx5/profile]"
    'git:[config][--local][--get-regexp][^filter\.codex-portable\.]'
    'git:[config][--local][--remove-section][filter.codex-portable]'
    "stow:[--restow][--no-folding][-d][$FIXTURE/common][alpha][claude][codex]"
    "stow:[--restow][--no-folding][-d][$FIXTURE/host-a][beta][claude][codex][fcitx5][sherlock-kit]"
)
assert_events "${HOST_BEFORE[@]}" "$HOST_INSTRUCTIONS" "${HOST_REST[@]}"
grep -Fq 'Stowing host-specific packages:' "$TEST_TMP/host.stdout"
grep -Fq 'Synchronizing host Codex instructions' "$TEST_TMP/host.stdout"
refute_grep 'sherlock-kit submodule not initialized' "$TEST_TMP/host.stderr"

printf '%s\n' "$TEST_HOME" "$(uname -s)" 'host-a' 'test-head' >"$TEST_TMP/expected-state"
cmp "$STATE" "$TEST_TMP/expected-state"

# A rules link that dangles (the sherlock-kit submodule is not initialized,
# as after a plain local merge) skips only the Codex instructions sync, in
# preflight and apply alike, with a warning; everything else still runs.
# The install is incomplete, so the host is remembered without an applied
# HEAD: the login updater then initializes the submodule and restows.
mv "$FIXTURE/rules-fixture/workstation.md" "$TEST_TMP/workstation.md.saved"
: >"$EVENT_LOG"
: >"$CHECK_LOG"
env \
    HOME="$TEST_HOME" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    EVENT_LOG="$EVENT_LOG" \
    FILTER_PRESENT=1 \
    LC_ALL=C \
    bash "$FIXTURE/stow-all.sh" host-a \
    >"$TEST_TMP/dangling.stdout" 2>"$TEST_TMP/dangling.stderr"
grep -Fxq '[dotfiles] [warn] sherlock-kit submodule not initialized; Codex instructions left unchanged (git submodule update --init --recursive)' \
    "$TEST_TMP/dangling.stderr"
grep -Fq 'check:codex-rules-sync:' "$CHECK_LOG"
refute_grep 'codex-instructions-sync' "$CHECK_LOG"
assert_events "${HOST_BEFORE[@]}" "${HOST_REST[@]}"
refute_grep 'Synchronizing host Codex instructions' "$TEST_TMP/dangling.stdout"
grep -Fq '[dotfiles] [ok] Stow completed (host-a)' "$TEST_TMP/dangling.stdout"
printf '%s\n' "$TEST_HOME" "$(uname -s)" 'host-a' '' >"$TEST_TMP/expected-skipped-state"
cmp "$STATE" "$TEST_TMP/expected-skipped-state"
mv "$TEST_TMP/workstation.md.saved" "$FIXTURE/rules-fixture/workstation.md"
# Once the link resolves again, the next stow is complete and records HEAD.
: >"$EVENT_LOG"
: >"$CHECK_LOG"
env \
    HOME="$TEST_HOME" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    EVENT_LOG="$EVENT_LOG" \
    FILTER_PRESENT=1 \
    LC_ALL=C \
    bash "$FIXTURE/stow-all.sh" host-a \
    >"$TEST_TMP/dangling-healed.stdout" 2>"$TEST_TMP/dangling-healed.stderr"
assert_events "${HOST_BEFORE[@]}" "$HOST_INSTRUCTIONS" "${HOST_REST[@]}"
cmp "$STATE" "$TEST_TMP/expected-state"

# An uninitialized coding-agent-kit submodule (as after a clone without
# --recurse-submodules or a plain local merge) leaves the tracked codex-as
# link dangling. Every sync, preflight included, both dry runs and both stows
# still run, with one warning. The install is incomplete, so the host is
# remembered without an applied HEAD.
mv "$FIXTURE/common/codex/coding-agent-kit/bin/codex-as" "$TEST_TMP/kit-codex-as.saved"
: >"$EVENT_LOG"
: >"$CHECK_LOG"
env \
    HOME="$TEST_HOME" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    EVENT_LOG="$EVENT_LOG" \
    FILTER_PRESENT=1 \
    LC_ALL=C \
    bash "$FIXTURE/stow-all.sh" host-a \
    >"$TEST_TMP/kit-dangling.stdout" 2>"$TEST_TMP/kit-dangling.stderr"
cmp "$CHECK_LOG" "$TEST_TMP/expected-checks"
assert_events "${HOST_BEFORE[@]}" "$HOST_INSTRUCTIONS" "${HOST_REST[@]}"
printf '%s\n' '[dotfiles] [warn] coding-agent-kit links dangle; codex-as, claude-as and the Claude helpers are unavailable until the submodule is checked out (git submodule update --init --recursive)' \
    >"$TEST_TMP/expected-kit-dangling.stderr"
cmp "$TEST_TMP/kit-dangling.stderr" "$TEST_TMP/expected-kit-dangling.stderr"
grep -Fq '[dotfiles] [ok] Stow completed (host-a)' "$TEST_TMP/kit-dangling.stdout"
cmp "$STATE" "$TEST_TMP/expected-skipped-state"
mv "$TEST_TMP/kit-codex-as.saved" "$FIXTURE/common/codex/coding-agent-kit/bin/codex-as"
# Once the link resolves again, the next stow is complete and records HEAD.
: >"$EVENT_LOG"
: >"$CHECK_LOG"
env \
    HOME="$TEST_HOME" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    EVENT_LOG="$EVENT_LOG" \
    FILTER_PRESENT=1 \
    LC_ALL=C \
    bash "$FIXTURE/stow-all.sh" host-a \
    >"$TEST_TMP/kit-restored.stdout" 2>"$TEST_TMP/kit-restored.stderr"
assert_events "${HOST_BEFORE[@]}" "$HOST_INSTRUCTIONS" "${HOST_REST[@]}"
[[ ! -s "$TEST_TMP/kit-restored.stderr" ]]
cmp "$STATE" "$TEST_TMP/expected-state"

# Git can report a clean checkout with core.filemode=false even when a helper
# loses its executable bit. Every required helper must fail before any sync or
# Stow side effect, and the previous successful state must remain unchanged.
for helper in \
    "$FIXTURE/common/codex/.local/bin/codex-config-sync" \
    "$FIXTURE/common/codex/.local/bin/codex-rules-sync" \
    "$FIXTURE/common/codex/.local/bin/codex-instructions-sync" \
    "$FIXTURE/common/claude/.local/bin/claude-settings-sync"; do
    chmod -x "$helper"
    if run_fixture nonexecutable-helper; then
        echo "ERROR: installer skipped a required nonexecutable helper: $helper" >&2
        exit 1
    fi
    grep -Fq 'required sync helper is missing or not executable' "$TEST_TMP/nonexecutable-helper.stderr"
    assert_events
    cmp "$STATE" "$TEST_TMP/expected-state"
    chmod +x "$helper"
done
for source in \
    "$FIXTURE/common/codex/.codex/config.toml" \
    "$FIXTURE/common/codex/.codex/rules/portable.rules" \
    "$FIXTURE/common/codex/.codex/AGENTS.md" \
    "$FIXTURE/common/claude/.claude/settings.json"; do
    mv "$source" "$source.saved"
    if run_fixture missing-source; then
        echo "ERROR: installer skipped a required portable source: $source" >&2
        exit 1
    fi
    grep -Fq 'required portable settings are missing or unreadable' "$TEST_TMP/missing-source.stderr"
    assert_events
    cmp "$STATE" "$TEST_TMP/expected-state"
    mv "$source.saved" "$source"
done

# A selected fcitx5 package also requires both files. Preflight must catch a
# mismatch before any otherwise-valid Codex or Claude sync changes the home.
for dependency in \
    "$FIXTURE/host-a/fcitx5/.local/bin/fcitx5-profile-sync" \
    "$FIXTURE/host-a/fcitx5/.config/fcitx5/profile"; do
    mv "$dependency" "$dependency.saved"
    : >"$EVENT_LOG"
    if env HOME="$TEST_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" EVENT_LOG="$EVENT_LOG" \
        bash "$FIXTURE/stow-all.sh" host-a >"$TEST_TMP/missing-fcitx5.stdout" 2>"$TEST_TMP/missing-fcitx5.stderr"; then
        echo "ERROR: installer skipped a required fcitx5 dependency: $dependency" >&2
        exit 1
    fi
    assert_events
    cmp "$STATE" "$TEST_TMP/expected-state"
    mv "$dependency.saved" "$dependency"
done
# A sync failure is fail-closed: later syncs, git mutation, and Stow never run.
: >"$EVENT_LOG"
if env \
    HOME="$TEST_HOME" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    EVENT_LOG="$EVENT_LOG" \
    FAIL_SYNC=codex-config-sync \
    bash "$FIXTURE/stow-all.sh" \
    >"$TEST_TMP/sync-failure.stdout" 2>"$TEST_TMP/sync-failure.stderr"; then
    echo "ERROR: installer ignored a portable sync failure" >&2
    exit 1
fi
assert_events \
    "stow:[-n][--restow][--no-folding][-d][$FIXTURE/common][alpha][claude][codex]" \
    "sync:codex-config-sync:[$FIXTURE/common/codex/.codex/config.toml][$TEST_HOME/.codex/config.toml]"

cmp "$STATE" "$TEST_TMP/expected-state"

# A file Stow would refuse to replace stops the run before any helper writes.
if run_fixture dry-conflict STOW_DRY_RC=1; then
    echo "ERROR: installer ignored a Stow dry-run conflict" >&2
    exit 1
fi
assert_events "stow:[-n][--restow][--no-folding][-d][$FIXTURE/common][alpha][claude][codex]"
grep -Fq 'WARNING! stowing would cause conflicts' "$TEST_TMP/dry-conflict.stderr"
grep -Fq 'Stow would conflict with the files listed above, so nothing was changed' "$TEST_TMP/dry-conflict.stderr"
grep -Fq 'never stow --adopt' "$TEST_TMP/dry-conflict.stderr"
cmp "$STATE" "$TEST_TMP/expected-state"

# The zsh package links into ~/.oh-my-zsh: without the oh-my-zsh clone, Stow
# would create a real ~/.oh-my-zsh/custom that blocks it, so nothing runs.
cp "$STATE" "$TEST_TMP/state.saved"
mkdir -p "$FIXTURE/common/zsh/.oh-my-zsh/custom"
printf '%s\n' '# fixture custom' >"$FIXTURE/common/zsh/.oh-my-zsh/custom/example.zsh"
if run_fixture omz-missing; then
    echo "ERROR: installer stowed the zsh package before oh-my-zsh was cloned" >&2
    exit 1
fi
assert_events
[[ ! -s "$CHECK_LOG" ]]
grep -Fq 'oh-my-zsh is not cloned yet' "$TEST_TMP/omz-missing.stderr"
grep -Fq 'DOTFILES_STOW_WITHOUT_OH_MY_ZSH=1' "$TEST_TMP/omz-missing.stderr"
cmp "$STATE" "$TEST_TMP/expected-state"
mkdir -p "$TEST_HOME/.oh-my-zsh/custom"
if run_fixture omz-recovery; then
    echo "ERROR: installer stowed into an ~/.oh-my-zsh without oh-my-zsh.sh" >&2
    exit 1
fi
assert_events
grep -Fq 'X-recovery' "$TEST_TMP/omz-recovery.stderr"
run_fixture omz-override DOTFILES_STOW_WITHOUT_OH_MY_ZSH=1
grep -Fq "stow:[--restow][--no-folding][-d][$FIXTURE/common][alpha][claude][codex][zsh]" "$EVENT_LOG"
printf '%s\n' '# fixture oh-my-zsh' >"$TEST_HOME/.oh-my-zsh/oh-my-zsh.sh"
run_fixture omz-cloned
grep -Fq "stow:[--restow][--no-folding][-d][$FIXTURE/common][alpha][claude][codex][zsh]" "$EVENT_LOG"
rm -rf "$FIXTURE/common/zsh" "$TEST_HOME/.oh-my-zsh"
cp "$TEST_TMP/state.saved" "$STATE"

if run_fixture stow-failure STOW_RC=24; then
    echo "ERROR: installer ignored Stow failure" >&2
    exit 1
fi
! grep -Fq '[dotfiles] [ok] Stow completed' "$TEST_TMP/stow-failure.stdout"
cmp "$STATE" "$TEST_TMP/expected-state"
if run_fixture status-failure STATUS_RC=25; then
    echo "ERROR: installer ignored Git status failure" >&2
    exit 1
fi
! grep -Fq '[dotfiles] [ok] Stow completed' "$TEST_TMP/status-failure.stdout"
cmp "$STATE" "$TEST_TMP/expected-state"
run_fixture dirty INSTALL_DIRTY=' M common/config'
printf '%s\n' "$TEST_HOME" "$(uname -s)" '' '' >"$TEST_TMP/expected-state"
cmp "$STATE" "$TEST_TMP/expected-state"

# Entirely absent optional packages need no sync dependencies.
mv "$FIXTURE/common/codex" "$TEST_TMP/saved-codex"
mv "$FIXTURE/common/claude" "$TEST_TMP/saved-claude"
run_fixture absent-packages
assert_events \
    "stow:[-n][--restow][--no-folding][-d][$FIXTURE/common][alpha]" \
    'git:[config][--local][--get-regexp][^filter\.codex-portable\.]' \
    "stow:[--restow][--no-folding][-d][$FIXTURE/common][alpha]"
mv "$TEST_TMP/saved-codex" "$FIXTURE/common/codex"
mv "$TEST_TMP/saved-claude" "$FIXTURE/common/claude"

# SSH permissions apply to the real targets of regular and chained symlinks;
# dangling config snippets are ignored without aborting the restow.
mkdir -p "$TEST_HOME/.ssh/config.d" "$TEST_TMP/ssh-sources/nested"
printf '%s\n' 'Host *' >"$TEST_TMP/ssh-sources/config"
printf '%s\n' 'Host example' >"$TEST_TMP/ssh-sources/nested/example.conf"
ln -s "$TEST_TMP/ssh-sources/config" "$TEST_HOME/.ssh/config"
ln -s "$TEST_TMP/ssh-sources/nested/example.conf" \
    "$TEST_HOME/.ssh/config.d/example.conf"
ln -s "$TEST_TMP/ssh-sources/missing.conf" \
    "$TEST_HOME/.ssh/config.d/z-dangling.conf"
chmod 777 "$TEST_HOME/.ssh" "$TEST_HOME/.ssh/config.d"
chmod 666 \
    "$TEST_TMP/ssh-sources/config" \
    "$TEST_TMP/ssh-sources/nested/example.conf"
run_fixture ssh-permissions
assert_mode "$TEST_HOME/.ssh" 700
assert_mode "$TEST_HOME/.ssh/config.d" 700
assert_mode "$TEST_TMP/ssh-sources/config" 600
assert_mode "$TEST_TMP/ssh-sources/nested/example.conf" 600
[[ -L "$TEST_HOME/.ssh/config" ]]
[[ -L "$TEST_HOME/.ssh/config.d/example.conf" ]]
[[ -L "$TEST_HOME/.ssh/config.d/z-dangling.conf" ]]

grep -Fq '[dotfiles] [ok] Stow completed' "$TEST_TMP/ssh-permissions.stdout"
printf '%s\n' "$TEST_HOME" "$(uname -s)" '' 'test-head' >"$TEST_TMP/expected-state"
cmp "$STATE" "$TEST_TMP/expected-state"

# A home stowed with the 0.3 sherlock-kit launcher keeps ~/.local/bin/shk ->
# ../../<checkout>/common/codex/.local/bin/shk after that file was deleted.
# Stow's dry run of another stow directory refuses such a dangling link as
# "not owned by stow" and aborts the whole install, so the installer removes
# exactly that retired link after the read-only preflight and before the dry
# runs. Its text is resolved from the link's physical directory, as Stow
# wrote it. Anything else at that path is left for Stow to report.
RETIRED="$TEST_HOME/.local/bin/shk"
RETIRED_TEXT=../../../fixture/common/codex/.local/bin/shk
RETIRED_LOG="[dotfiles] [info] Removed retired link $RETIRED (its source common/codex/.local/bin/shk was deleted)"
# assert_link PATH TEXT: PATH is still the symlink TEXT.
assert_link() {
    if [[ ! -L "$1" || "$(readlink "$1")" != "$2" ]]; then
        echo "ERROR: $1 is no longer the link to $2" >&2
        exit 1
    fi
}
mkdir -p "$TEST_HOME/.local/bin"
ln -s "$RETIRED_TEXT" "$RETIRED"
if run_fixture retired-preflight FAIL_CHECK=claude-settings-sync; then
    echo 'ERROR: installer ignored a configuration preflight failure' >&2
    exit 1
fi
assert_link "$RETIRED" "$RETIRED_TEXT"
refute_grep 'Removed retired link' "$TEST_TMP/retired-preflight.stdout"
run_fixture retired PROBE_PATH="$RETIRED"
[[ ! -e "$RETIRED" && ! -L "$RETIRED" ]]
grep -Fxq "$RETIRED_LOG" "$TEST_TMP/retired.stdout"
grep -Fxq 'probe:absent' "$EVENT_LOG"
refute_grep 'probe:present' "$EVENT_LOG"
grep -Fq '[dotfiles] [ok] Stow completed (common-only)' "$TEST_TMP/retired.stdout"
cmp "$STATE" "$TEST_TMP/expected-state"
for spelling in \
    ../bin/../../../fixture/./common/codex//.local/bin/shk \
    "$FIXTURE/common/codex/.local/bin/shk"; do
    ln -s "$spelling" "$RETIRED"
    run_fixture retired-spelling
    [[ ! -e "$RETIRED" && ! -L "$RETIRED" ]]
    grep -Fxq "$RETIRED_LOG" "$TEST_TMP/retired-spelling.stdout"
done
# A home reached through a symlink at another depth: Stow wrote the text
# from the physical directory, so its .. steps climb from there, not from
# the alias.
mkdir -p "$TEST_TMP/deep/er"
ln -s ../../home "$TEST_TMP/deep/er/home-alias"
ln -s "$RETIRED_TEXT" "$RETIRED"
run_fixture retired-alias HOME="$TEST_TMP/deep/er/home-alias"
[[ ! -e "$RETIRED" && ! -L "$RETIRED" ]]
grep -Fxq "[dotfiles] [info] Removed retired link $TEST_TMP/deep/er/home-alias/.local/bin/shk (its source common/codex/.local/bin/shk was deleted)" \
    "$TEST_TMP/retired-alias.stdout"
rm -r "$TEST_TMP/deep"
# A live link to the same path, a dangling link into another checkout, and
# a regular file are not retired links.
printf '%s\n' '#!/bin/sh' >"$FIXTURE/common/codex/.local/bin/shk"
ln -s "$RETIRED_TEXT" "$RETIRED"
run_fixture retired-live PROBE_PATH="$RETIRED"
assert_link "$RETIRED" "$RETIRED_TEXT"
grep -Fxq 'probe:present' "$EVENT_LOG"
refute_grep 'Removed retired link' "$TEST_TMP/retired-live.stdout"
rm "$RETIRED" "$FIXTURE/common/codex/.local/bin/shk"
ln -s ../../../other-checkout/common/codex/.local/bin/shk "$RETIRED"
run_fixture retired-foreign
assert_link "$RETIRED" ../../../other-checkout/common/codex/.local/bin/shk
refute_grep 'Removed retired link' "$TEST_TMP/retired-foreign.stdout"
rm "$RETIRED"
printf '%s\n' 'my own shk' >"$RETIRED"
run_fixture retired-file
[[ -f "$RETIRED" && ! -L "$RETIRED" ]]
grep -Fxq 'my own shk' "$RETIRED"
refute_grep 'Removed retired link' "$TEST_TMP/retired-file.stdout"
rm -r "$TEST_HOME/.local"
cmp "$STATE" "$TEST_TMP/expected-state"

# The real codex-instructions-sync behind the installer: a host with rules
# generates ~/.codex/AGENTS.override.md, a common-only stow removes a stale
# generated one, a foreign override is kept (with a warning without rules,
# fail-closed with them), and a dry-run conflict or a dangling rules link
# leaves the override as it was.
cp "$REPO_ROOT/lib/config_sync.py" "$REPO_ROOT/lib/sync-runtime.sh" "$FIXTURE/lib/"
cp "$REPO_ROOT/common/codex/.local/bin/codex-instructions-sync" "$FIXTURE/common/codex/.local/bin/"
OVERRIDE="$TEST_HOME/.codex/AGENTS.override.md"
MARKER="<!-- Generated by dotfiles codex-instructions-sync. Edit common/codex/.codex/AGENTS.md or the host's sherlock-kit rules, then rerun stow-all.sh. -->"
printf '%s\n' "$MARKER" 'common-agents' '' 'fixture-rules' >"$TEST_TMP/expected-override"

run_real() {
    case_name=$1
    host=$2
    shift 2
    : >"$EVENT_LOG"
    : >"$CHECK_LOG"
    env \
        HOME="$TEST_HOME" \
        PATH="$FAKE_BIN:/usr/bin:/bin" \
        EVENT_LOG="$EVENT_LOG" \
        DOTFILES_SYNC_PYTHON="$SYNC_PYTHON" \
        LC_ALL=C \
        "$@" \
        bash "$FIXTURE/stow-all.sh" ${host:+"$host"} \
        >"$TEST_TMP/$case_name.stdout" \
        2>"$TEST_TMP/$case_name.stderr"
}

run_real real-host host-a
cmp "$OVERRIDE" "$TEST_TMP/expected-override"
[[ -f "$OVERRIDE" && ! -L "$OVERRIDE" ]]
assert_mode "$OVERRIDE" 644
grep -Fq '[dotfiles] [ok] Stow completed (host-a)' "$TEST_TMP/real-host.stdout"
[[ ! -s "$TEST_TMP/real-host.stderr" ]]
run_real real-host-again host-a
cmp "$OVERRIDE" "$TEST_TMP/expected-override"

printf '%s\n' "$MARKER" 'an older generation' >"$OVERRIDE"
run_real real-common ''
[[ ! -e "$OVERRIDE" && ! -L "$OVERRIDE" ]]
grep -Fq '[dotfiles] [ok] Stow completed (common-only)' "$TEST_TMP/real-common.stdout"

printf '%s\n' 'my own override' >"$OVERRIDE"
run_real real-foreign ''
grep -Fq "warning: left foreign $OVERRIDE unchanged" "$TEST_TMP/real-foreign.stderr"
grep -Fxq 'my own override' "$OVERRIDE"
grep -Fq '[dotfiles] [ok] Stow completed (common-only)' "$TEST_TMP/real-foreign.stdout"
cp "$STATE" "$TEST_TMP/real-state"
if run_real real-foreign-rules host-a; then
    echo 'ERROR: installer overwrote or accepted a foreign Codex override on a host with rules' >&2
    exit 1
fi
grep -Fq 'not generated by codex-instructions-sync' "$TEST_TMP/real-foreign-rules.stderr"
assert_events
grep -Fxq 'my own override' "$OVERRIDE"
cmp "$STATE" "$TEST_TMP/real-state"
rm "$OVERRIDE"

if run_real real-conflict host-a STOW_DRY_RC=1; then
    echo 'ERROR: installer ignored a Stow dry-run conflict' >&2
    exit 1
fi
[[ ! -e "$OVERRIDE" ]]
cmp "$STATE" "$TEST_TMP/real-state"

run_real real-before-dangling host-a
cmp "$OVERRIDE" "$TEST_TMP/expected-override"
mv "$FIXTURE/rules-fixture/workstation.md" "$TEST_TMP/workstation.md.saved"
run_real real-dangling host-a
grep -Fxq '[dotfiles] [warn] sherlock-kit submodule not initialized; Codex instructions left unchanged (git submodule update --init --recursive)' \
    "$TEST_TMP/real-dangling.stderr"
cmp "$OVERRIDE" "$TEST_TMP/expected-override"
grep -Fq '[dotfiles] [ok] Stow completed (host-a)' "$TEST_TMP/real-dangling.stdout"
grep -Fq "stow:[--restow][--no-folding][-d][$FIXTURE/host-a][beta][claude][codex][fcitx5][sherlock-kit]" "$EVENT_LOG"
cmp "$STATE" "$TEST_TMP/expected-skipped-state"
mv "$TEST_TMP/workstation.md.saved" "$FIXTURE/rules-fixture/workstation.md"

echo "stow-all=PASS"
