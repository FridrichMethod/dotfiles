#!/bin/bash

# Fixture tests for doctor.sh and lib/bootstrap/checks.sh: tool probes and
# floors, tier selection, exit codes, host resolution, TSV shape, structural
# checks, --online/--smoke, and the read-only, offline promise. The fixture
# repo has its own small config/bootstrap/tools.tsv; FAKE_BIN stubs print
# controlled versions. Nothing here reads or writes the runner's real home.

# shellcheck disable=SC2088 # doctor details spell ~ literally
set -euo pipefail

# Hermetic: the provisioning exports (DOTFILES_AUTO_UPDATE=0 and the like,
# docs/bootstrap.md) and other dotfiles knobs never reach the code under
# test from the caller; each case sets what it needs.
unset DOTFILES_AUTO_UPDATE DOTFILES_AUTO_STOW DOTFILES_HOST DOTFILES_DIR _DOTFILES_CHECKED \
    DOTFILES_STOW_WITHOUT_OH_MY_ZSH DOTFILES_COLOR AWESOME_SKILLS_AUTO_UPDATE AWESOME_SKILLS_FORCE \
    AWESOME_SKILLS_BG AWESOME_SKILLS_INSTALLER_URL AWESOME_SKILLS_REFRESH_DAYS _AWESOME_SKILLS_CHECKED

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_GIT=$(command -v git) || {
    echo 'ERROR: git is required for the doctor fixture repo.' >&2
    exit 1
}
# The real codex-instructions-sync that the codex-override row runs needs
# only a standard-library Python 3.11+; the runtime check stays a fake.
SYNC_PYTHON="${DOTFILES_SYNC_PYTHON:-$REPO_ROOT/.venv-sync/bin/python}"
if [[ ! -x "$SYNC_PYTHON" ]]; then
    echo 'ERROR: AI-sync runtime missing; run ./setup-sync.sh explicitly.' >&2
    exit 1
fi
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-doctor.XXXXXX")"
TEST_TMP="$(cd -- "$TEST_TMP" && pwd -P)"
cleanup() {
    chmod -R u+w "$TEST_TMP" 2>/dev/null || true
    rm -rf "$TEST_TMP"
}
trap cleanup EXIT HUP INT TERM

FIXTURE="$TEST_TMP/fixture"
FAKE_BIN="$TEST_TMP/bin"
BREW_BIN="$TEST_TMP/brew/bin"
TEST_HOME="$TEST_TMP/home"
EVENT_LOG="$TEST_TMP/events.log"
OUT="$TEST_TMP/out"
SHELL_TMP="$TEST_TMP/tmp"
mkdir -p "$FIXTURE/lib/bootstrap" "$FIXTURE/config/bootstrap" "$FIXTURE/docs" \
    "$FAKE_BIN" "$BREW_BIN" "$TEST_HOME" "$OUT" "$SHELL_TMP"
cp "$REPO_ROOT/doctor.sh" "$FIXTURE/doctor.sh"
cp "$REPO_ROOT/lib/terminal.sh" "$REPO_ROOT/lib/sync-runtime.sh" "$REPO_ROOT/lib/config_sync.py" \
    "$FIXTURE/lib/"
cp "$REPO_ROOT"/lib/bootstrap/*.sh "$FIXTURE/lib/bootstrap/"
# The real step headings: every doc step a manifest row cites must have one.
cp "$REPO_ROOT/docs/bootstrap.md" "$FIXTURE/docs/bootstrap.md"
chmod +x "$FIXTURE/doctor.sh"
: >"$EVENT_LOG"
ESC=$(printf '\033')

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

# --- fakes ---------------------------------------------------------------

write_fake() {
    cat >"$1"
    chmod +x "$1"
}

write_fake "$FAKE_BIN/git" <<SH
#!/bin/sh
exec "$REAL_GIT" "\$@"
SH

write_fake "$FAKE_BIN/fzf" <<'SH'
#!/bin/sh
printf 'fzf %s\n' "$*" >>"$EVENT_LOG"
printf '%s (fake)\n' "${FZF_VERSION:-0.60.0}"
SH

write_fake "$FAKE_BIN/doctor-alt" <<'SH'
#!/bin/sh
printf 'doctor-alt 1.2.3\n'
SH

write_fake "$FAKE_BIN/doctor-clt" <<'SH'
#!/bin/sh
printf 'doctor-clt %s\n' "$*" >>"$EVENT_LOG"
printf 'doctor-clt 1.0\n'
SH

write_fake "$FAKE_BIN/xcode-select" <<'SH'
#!/bin/sh
[ "${XCODE_OK:-0}" = 1 ]
SH

write_fake "$FAKE_BIN/zsh" <<'SH'
#!/bin/sh
if [ "${1:-}" = --version ]; then
    printf 'zsh 5.9 (fake)\n'
    exit 0
fi
printf 'zsh %s DOTFILES_AUTO_UPDATE=%s AWESOME_SKILLS_AUTO_UPDATE=%s PATH=%s\n' \
    "$*" "${DOTFILES_AUTO_UPDATE-unset}" "${AWESOME_SKILLS_AUTO_UPDATE-unset}" \
    "$PATH" >>"$EVENT_LOG"
[ -z "${SMOKE_STDOUT:-}" ] || printf '%s\n' "$SMOKE_STDOUT"
[ -z "${SMOKE_STDERR:-}" ] || printf '%s\n' "$SMOKE_STDERR" >&2
exit "${SMOKE_RC:-0}"
SH

# gh, claude and codex answer --version locally; anything else is network.
# Like recent real gh releases, the fake gh writes a telemetry device id on
# every command, --version included, unless GH_TELEMETRY=0.
for tool in gh claude codex; do
    telemetry=:
    case $tool in
        gh)
            version='gh version 2.81.0 (2025-09-01)'
            telemetry='[ "${GH_TELEMETRY:-}" = 0 ] || { mkdir -p "$HOME/.local/state/gh" && : >"$HOME/.local/state/gh/device-id"; }'
            ;;
        claude) version='2.1.0 (Claude Code)' ;;
        codex) version='codex-cli 0.161.0' ;;
    esac
    write_fake "$FAKE_BIN/$tool" <<SH
#!/bin/sh
$telemetry
if [ "\${1:-}" = --version ]; then
    printf '%s\n' '$version'
    exit 0
fi
printf 'NETWORK $tool %s\n' "\$*" >>"\$EVENT_LOG"
[ "\${AUTH_OK:-0}" = 1 ]
SH
done
# The tldr C client (Homebrew's tldr formula) checks the age of its page
# cache before it handles --version and, once ~/.tldrc/date is two weeks old,
# first downloads the tldr-pages archive into ~/.tldrc, unless
# TLDR_AUTO_UPDATE_DISABLED is set. The fake takes its cache to be stale.
write_fake "$FAKE_BIN/tldr" <<'SH'
#!/bin/sh
if [ -z "${TLDR_AUTO_UPDATE_DISABLED+set}" ]; then
    printf 'NETWORK tldr update\n' >>"$EVENT_LOG"
    mkdir -p "$HOME/.tldrc/tmp" && : >"$HOME/.tldrc/tmp/main.zip"
    printf 'Local database is older than two weeks, attempting to update it...\n'
fi
if [ "${1:-}" = --version ]; then
    printf 'tldr v1.6.1 (v1.6.1)\n'
    exit 0
fi
printf 'NETWORK tldr %s\n' "$*" >>"$EVENT_LOG"
exit 1
SH
for tool in curl wget; do
    write_fake "$FAKE_BIN/$tool" <<SH
#!/bin/sh
printf 'NETWORK $tool %s\n' "\$*" >>"\$EVENT_LOG"
exit 7
SH
done

# Long outputs: a match early, then far more than a pipe buffer, so a
# `printf | grep -q` check would die of SIGPIPE under pipefail.
write_fake "$FAKE_BIN/locale" <<'SH'
#!/bin/sh
[ "${1:-}" = -a ] || exit 2
printf '%s\n' C C.utf8
[ -z "${LOCALE_EXTRA-en_US.utf8}" ] || printf '%s\n' "${LOCALE_EXTRA-en_US.utf8}"
awk 'BEGIN { for (i = 0; i < 8000; i++) print "xx_XX" i ".utf8" }'
SH

# fc-list would create fontconfig caches; the font check scans file names.
write_fake "$FAKE_BIN/fc-list" <<'SH'
#!/bin/sh
printf 'fc-list %s\n' "$*" >>"$EVENT_LOG"
SH

# A sync interpreter: it passes lib/config_sync.py --runtime-check unless
# SYNC_RUNTIME_RC says otherwise (a venv without tomlkit), and logs the call.
# Any other call (codex-instructions-sync --check) runs in the real Python.
write_fake "$FAKE_BIN/sync-python" <<SH
#!/bin/sh
printf 'sync-python %s\n' "\$*" >>"\$EVENT_LOG"
case " \$* " in
    *" --runtime-check "*) exit "\${SYNC_RUNTIME_RC:-0}" ;;
esac
exec "$SYNC_PYTHON" "\$@"
SH

# A fresh Homebrew prefix that is not on PATH yet.
write_fake "$BREW_BIN/brew" <<'SH'
#!/bin/sh
printf 'Homebrew 4.6.0\n'
SH
write_fake "$BREW_BIN/doctor-brew-only" <<'SH'
#!/bin/sh
printf 'doctor-brew-only 3.0\n'
SH

# --- fixture manifest ----------------------------------------------------

row() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"
}
# shellcheck disable=SC2016 # manifest tokens are literal
{
    printf '# Fixture tools.tsv for tests/doctor.sh\n'
    row id tier hosts probe version_flag floor absent doc
    row git core all git --version - 'cannot clone' P0-preflight
    row fzf core all fzf --version 0.58.0 'Ctrl-R/T, Alt-C and fzf-tab fail' S2-brew-bundle
    row zsh core unix zsh --version - 'no interactive shell' H1-apt-core
    row alt core all doctor-none,doctor-alt --version 1.0 'alt tool missing' S2-brew-bundle
    printf '# a comment between rows\n'
    row brew-only core all doctor-brew-only --version - 'brew tool missing' S2-brew-bundle
    row local-tool core all doctor-local --version - 'local tool missing' S5-codex
    row oh-my-zsh core unix 'file:$HOME/.oh-my-zsh/oh-my-zsh.sh' - - 'zsh aborts' S3-clones
    row demo-plugin core unix 'dir:$ZSH_CUSTOM/plugins/demo/src' - - 'no demo completions' S3-clones
    row bat-theme core all 'file:$BAT_CONFIG_DIR/themes/Catppuccin Mocha.tmTheme' - - 'theme unknown' S3-bat-theme
    row login-tool core sherlock,marlowe doctor-login --version - 'login env tool missing' S2-login-env
    row lmod host sherlock,marlowe env:LMOD_DIR - - 'module is undefined' S2-modules
    row gh cli all gh --version 2.50.0 'gh fails' S2-brew-bundle
    row tldr cli all tldr --version - 'previews fall back to man' S2-brew-bundle
    row file-tool cli lab-ubuntu 'file:$HOME/.fake-file-tool' --version 2.50.0 'file tool fails' X-host-tools
    row claude ai all claude --version - 'Claude Code is unavailable' S5-claude
    row codex ai all codex --version - 'Codex is unavailable' S5-codex
    row desk-tool desktop all doctor-absent-desktop - - 'no terminal' S6-kitty
    row nerd-font desktop mac,lab-ubuntu 'font:CaskaydiaMono Nerd Font' - - 'icons render as boxes' S6-nerd-font
    row psfzf desktop all psmodule:PSFzf - - 'PSReadLine defaults' W1-psresources
    row host-tool host lab-ubuntu doctor-absent-host - - 'host tool missing' X-host-tools
    row mac-clt core mac doctor-clt --version - 'mac tool missing' H1-xcode-clt
    row mac-alt core mac doctor-clt,doctor-alt --version - 'mac alt missing' H1-xcode-clt
    row win-only core win pwsh --version 7.0 'no PowerShell' W1-winget
    printf '# alias: fzf junegunn.fzf\n# manual: git macos\n'
} >"$FIXTURE/config/bootstrap/tools.tsv"

# --- fixture checkout and home -------------------------------------------

# Both submodules of .gitmodules are plain trees here (CI checks out
# coding-agent-kit only), each holding the sentinel files the doctor's
# submodule check requires.
SK_TREE="$FIXTURE/common/sherlock-kit/sherlock-kit"
SK_DATA="$SK_TREE/src/sherlock_kit/data"
mkdir -p "$FIXTURE/common/zsh" "$FIXTURE/common/sh" "$FIXTURE/common/git" \
    "$FIXTURE/common/bash" "$FIXTURE/common/pymol/PyMOLScripts/configs" \
    "$SK_DATA/rules" "$SK_DATA/skills/sherlock-kit" "$SK_TREE/bin" \
    "$FIXTURE/common/codex/.codex" "$FIXTURE/common/codex/.local/bin" "$FIXTURE/.venv-sync/bin"
for file in zsh/.zshrc sh/.profile git/.gitconfig bash/.bashrc; do
    printf '# fixture %s\n' "$file" >"$FIXTURE/common/$file"
done
printf '# fixture pymolrc\n' >"$FIXTURE/common/pymol/PyMOLScripts/configs/.pymolrc"
printf '## Sherlock from this workstation\n\nFixture workstation rules.\n' >"$SK_DATA/rules/workstation.md"
printf '## Sherlock: agent running on Sherlock\n\nFixture cluster rules.\n' >"$SK_DATA/rules/cluster.md"
printf -- '---\nname: sherlock-kit\ndescription: fixture\n---\n' >"$SK_DATA/skills/sherlock-kit/SKILL.md"
printf '#!/bin/sh\n' >"$SK_TREE/bin/shk"
chmod +x "$SK_TREE/bin/shk"
# A coding-agent-kit tree with its eight sentinel files (what the package
# links point at), for the cases with a third .gitmodules entry.
CAK_TREE="$FIXTURE/common/codex/coding-agent-kit"
CAK_SENTINELS='common/codex/.local/bin/codex-as common/claude/.local/bin/claude-as
common/codex/.local/lib/codex-as/launch.py common/claude/.local/lib/claude-as/launch.py
common/claude/.claude/dotfiles/statusline.cjs common/claude/.claude/dotfiles/notify.cjs
common/claude/.claude/dotfiles/check-git-hooks.cjs'
for sentinel in $CAK_SENTINELS; do
    mkdir -p "$CAK_TREE/${sentinel%/*}"
    [ -f "$CAK_TREE/$sentinel" ] || printf '# fixture %s\n' "$sentinel" >"$CAK_TREE/$sentinel"
done
GITMODULES_BOTH='[submodule "common/pymol/PyMOLScripts"]
	path = common/pymol/PyMOLScripts
	url = https://github.com/FridrichMethod/PyMOLScripts.git
	branch = main
[submodule "common/sherlock-kit/sherlock-kit"]
	path = common/sherlock-kit/sherlock-kit
	url = https://github.com/FridrichMethod/sherlock-kit.git
	branch = main'
printf '%s\n' "$GITMODULES_BOTH" >"$FIXTURE/.gitmodules"
# The portable Codex instructions and the real helper that stow-all.sh runs
# to generate ~/.codex/AGENTS.override.md on hosts with sherlock-kit rules.
printf '# Global Working Preferences\n\nFixture portable Codex instructions.\n' \
    >"$FIXTURE/common/codex/.codex/AGENTS.md"
cp "$REPO_ROOT/common/codex/.local/bin/codex-instructions-sync" "$FIXTURE/common/codex/.local/bin/"
cp "$FAKE_BIN/sync-python" "$FIXTURE/.venv-sync/bin/python"
printf '.venv-sync/\n' >"$FIXTURE/.gitignore"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
"$REAL_GIT" -C "$FIXTURE" init -q
"$REAL_GIT" -C "$FIXTURE" add .gitignore .gitmodules common
"$REAL_GIT" -C "$FIXTURE" -c user.name=fixture -c user.email=fixture@example.invalid \
    commit -q -m fixture
STATE_FILE="$FIXTURE/.git/dotfiles-sync-unix"

mkdir -p "$TEST_HOME/.oh-my-zsh/custom/plugins/demo/src" \
    "$TEST_HOME/.config/bat/themes" "$TEST_HOME/.local/bin"
printf '# fixture oh-my-zsh\n' >"$TEST_HOME/.oh-my-zsh/oh-my-zsh.sh"
# What setup-host links into ~/.local/bin (codex, claude, kitty, micromamba).
write_fake "$TEST_HOME/.local/bin/doctor-local" <<'SH'
#!/bin/sh
printf 'doctor-local 2.0\n'
SH
printf 'theme\n' >"$TEST_HOME/.config/bat/themes/Catppuccin Mocha.tmTheme"
# An executable that a file: probe names, with a version floor (file-tool).
write_fake "$TEST_HOME/.fake-file-tool" <<'SH'
#!/bin/sh
printf 'file-tool version %s\n' "${FILE_TOOL_VERSION:-2.81.0}"
SH
ln -s ../fixture/common/zsh/.zshrc "$TEST_HOME/.zshrc"
ln -s ../fixture/common/sh/.profile "$TEST_HOME/.profile"
ln -s "$FIXTURE/common/git/.gitconfig" "$TEST_HOME/.gitconfig"

BASE_PATH="$TEST_HOME/.local/bin:$FAKE_BIN:/usr/bin:/bin"
BASE_ENV=(
    HOME="$TEST_HOME"
    PATH="$BASE_PATH"
    LC_ALL=C
    TERM=xterm-256color
    TMPDIR="$SHELL_TMP"
    EVENT_LOG="$EVENT_LOG"
    BOOTSTRAP_UNAME_S=Linux
    BOOTSTRAP_BREW_CANDIDATES="$BREW_BIN/brew"
    BOOTSTRAP_NVM_KEG_CANDIDATES="$TEST_TMP/kegs/nvm"
    BOOTSTRAP_SYSTEM_FONT_DIRS="$TEST_TMP/system-fonts"
    GIT_CONFIG_GLOBAL=/dev/null
    GIT_CONFIG_NOSYSTEM=1
)

# --- helpers -------------------------------------------------------------

# run_doctor CASE [VAR=VALUE ...] -- [doctor arguments]: a clean environment
# (env -i) plus BASE_ENV and the overrides; stdout/stderr land in $OUT. The
# doctor runs under the Bash running this file ($BASH), so `bash-3.2
# tests/doctor.sh` tests the doctor under Bash 3.2 too.
run_doctor() {
    CASE=$1
    shift
    local vars=()
    while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
        vars+=("$1")
        shift
    done
    [ "$#" -eq 0 ] || shift
    : >"$EVENT_LOG"
    if env -i "${BASE_ENV[@]}" ${vars[@]+"${vars[@]}"} "$BASH" "$FIXTURE/doctor.sh" "$@" \
        >"$OUT/$CASE.out" 2>"$OUT/$CASE.err"; then
        RC=0
    else
        RC=$?
    fi
}

show_case() {
    {
        printf -- '--- %s stdout\n' "$CASE"
        cat "$OUT/$CASE.out"
        printf -- '--- %s stderr\n' "$CASE"
        cat "$OUT/$CASE.err"
        printf -- '--- events\n'
        cat "$EVENT_LOG"
    } >&2
}

case_fail() {
    show_case
    fail "$CASE: $*"
}

assert_rc() { [ "$RC" = "$1" ] || case_fail "exit $RC, expected $1"; }
assert_in() { grep -Fq -- "$2" "$1" || case_fail "${1##*/} lacks [$2]"; }
assert_not_in() { ! grep -Fq -- "$2" "$1" || case_fail "${1##*/} unexpectedly has [$2]"; }
assert_out() { assert_in "$OUT/$CASE.out" "$1"; }
assert_err() { assert_in "$OUT/$CASE.err" "$1"; }
assert_no_out() { assert_not_in "$OUT/$CASE.out" "$1"; }
assert_event() { assert_in "$EVENT_LOG" "$1"; }
assert_no_event() { assert_not_in "$EVENT_LOG" "$1"; }
assert_quiet_events() { [ ! -s "$EVENT_LOG" ] || case_fail "$1"; }

# tsv_field ID COLUMN: column of the TSV row whose id is ID, or <no row>.
tsv_field() {
    awk -F '\t' -v id="$1" -v col="$2" \
        '$2 == id { print $col; found = 1; exit } END { if (!found) print "<no row>" }' "$OUT/$CASE.out"
}

# assert_row ID STATUS [DETAIL_PART [FIX]]: the TSV row's status, a substring
# of its detail (skipped when empty) and its exact fix column.
assert_row() {
    local actual
    actual=$(tsv_field "$1" 1)
    [ "$actual" = "$2" ] || case_fail "$1 status [$actual], expected [$2]"
    if [ -n "${3:-}" ]; then
        actual=$(tsv_field "$1" 4)
        case $actual in
            *"$3"*) ;;
            *) case_fail "$1 detail [$actual] lacks [$3]" ;;
        esac
    fi
    if [ "$#" -ge 4 ]; then
        actual=$(tsv_field "$1" 5)
        [ "$actual" = "$4" ] || case_fail "$1 fix [$actual], expected [$4]"
    fi
}

assert_no_row() { [ "$(tsv_field "$1" 1)" = '<no row>' ] || case_fail "unexpected row $1"; }

# assert_tsv_shape: header, then exactly five tab-separated columns per line
# and only known statuses; no log lines on stdout.
assert_tsv_shape() {
    [ "$(sed -n 1p "$OUT/$CASE.out")" = "$(printf 'status\tid\ttier\tdetail\tfix')" ] ||
        case_fail 'TSV header mismatch'
    awk -F '\t' 'NF != 5 { bad = 1 } END { exit bad }' "$OUT/$CASE.out" ||
        case_fail 'a TSV line does not have five columns'
    awk -F '\t' 'NR > 1 && $1 !~ /^(ok|outdated|missing|warn|skip|human)$/ { bad = 1 } END { exit bad }' \
        "$OUT/$CASE.out" || case_fail 'a TSV status is outside the vocabulary'
    assert_no_out '[dotfiles]'
}

# --- usage errors and host resolution (exit 2, nothing probed) ------------

run_doctor help -- --help
assert_rc 0
assert_out 'Usage: ./doctor.sh'
assert_out '--online'
run_doctor help-short -- -h
assert_rc 0

expect_usage_error() {
    local name=$1 text=$2
    shift 2
    run_doctor "$name" "$@"
    assert_rc 2
    assert_err "$text"
    assert_quiet_events 'probes ran before a usage error'
}

expect_usage_error unknown-option 'unknown argument: --bogus' -- --bogus
expect_usage_error host-without-value '--host needs a value' -- --host
expect_usage_error host-and-platform 'mutually exclusive' -- --host lab-ubuntu --platform debian
expect_usage_error unknown-host "unknown host 'nowhere'" -- --host nowhere
expect_usage_error unknown-platform "unknown platform 'plan9'" -- --platform plan9
expect_usage_error unknown-tier "unknown tier 'gui'" -- --host lab-ubuntu --tier core,gui
expect_usage_error win-host 'pwsh -File doctor.ps1 -Host win' -- --host win
expect_usage_error win-host-equals 'pwsh -File doctor.ps1 -Host win' -- --host=win
expect_usage_error win-env 'pwsh -File doctor.ps1 -Host win' DOTFILES_HOST=win --
expect_usage_error unknown-env "DOTFILES_HOST='nowhere' is not a known host" DOTFILES_HOST=nowhere --
expect_usage_error no-host 'mac wsl-ubuntu lab-ubuntu sherlock marlowe win' --

# The host ./stow-all.sh recorded for this home and kernel.
printf '%s\n' "$TEST_HOME" Linux sherlock test-head >"$STATE_FILE"
run_doctor state-host -- --tsv
assert_rc 1
assert_row login-tool missing
assert_no_row host-tool
run_doctor state-overridden DOTFILES_HOST=lab-ubuntu -- --tsv
assert_rc 0
assert_row host-tool warn
assert_no_row login-tool
printf '%s\n' "$TEST_TMP/elsewhere" Linux sherlock test-head >"$STATE_FILE"
expect_usage_error state-other-home 'none recorded for this home' --
printf '%s\n' "$TEST_HOME" Darwin sherlock test-head >"$STATE_FILE"
expect_usage_error state-other-kernel 'none recorded for this home' --
rm -f "$STATE_FILE"
run_doctor env-host DOTFILES_HOST=lab-ubuntu -- --tsv
assert_rc 0
assert_row host-tool warn

# A set but empty DOTFILES_HOST means common only, as the login updater reads
# it: the detected platform without an overlay, even with a recorded host
# (sherlock would fail on login-tool); --host and --platform still win.
OS_UBUNTU="$TEST_TMP/os-release-ubuntu"
printf 'ID=ubuntu\nID_LIKE=debian\n' >"$OS_UBUNTU"
printf '%s\n' "$TEST_HOME" Linux sherlock test-head >"$STATE_FILE"
run_doctor env-empty DOTFILES_HOST= BOOTSTRAP_OS_RELEASE="$OS_UBUNTU" -- --tsv
assert_rc 0
assert_tsv_shape
assert_err 'DOTFILES_HOST is set but empty, which means common only (no host overlay): checking as --platform debian'
assert_row fzf ok '' -
assert_no_row login-tool
assert_no_row host-tool
run_doctor env-empty-log DOTFILES_HOST= BOOTSTRAP_OS_RELEASE="$OS_UBUNTU" --
assert_rc 0
assert_out 'Checking platform debian without a host overlay'
assert_out '(platform debian, required tiers: core,cli,ai)'
run_doctor env-empty-host DOTFILES_HOST= -- --host lab-ubuntu --tsv
assert_rc 0
assert_row host-tool warn
assert_not_in "$OUT/$CASE.err" 'set but empty'
run_doctor env-empty-platform DOTFILES_HOST= BOOTSTRAP_OS_RELEASE="$OS_UBUNTU" -- --platform other --tsv
assert_rc 0
assert_not_in "$OUT/$CASE.err" 'set but empty'
assert_row zsh ok

# So does a common-only install that ./stow-all.sh recorded (an empty host
# line), as the login updater reads it: the detected platform, with a
# warning, never "none recorded". DOTFILES_HOST, --host and --platform still
# win, and a state that is not all four lines (which the updater ignores)
# records nothing.
printf '%s\n' "$TEST_HOME" Linux '' test-head >"$STATE_FILE"
run_doctor state-common-only BOOTSTRAP_OS_RELEASE="$OS_UBUNTU" -- --tsv
assert_rc 0
assert_tsv_shape
assert_err './stow-all.sh recorded a common-only install for this home (no host overlay): checking as --platform debian'
assert_not_in "$OUT/$CASE.err" 'none recorded'
assert_row fzf ok '' -
assert_no_row login-tool
assert_no_row host-tool
run_doctor state-common-only-list BOOTSTRAP_OS_RELEASE="$OS_UBUNTU" -- --list
assert_rc 0
assert_err 'recorded a common-only install'
run_doctor state-common-only-env DOTFILES_HOST=lab-ubuntu -- --tsv
assert_rc 0
assert_row host-tool warn
assert_not_in "$OUT/$CASE.err" 'common-only'
run_doctor state-common-only-host -- --host lab-ubuntu --tsv
assert_rc 0
assert_row host-tool warn
assert_not_in "$OUT/$CASE.err" 'common-only'
run_doctor state-common-only-empty DOTFILES_HOST= BOOTSTRAP_OS_RELEASE="$OS_UBUNTU" -- --tsv
assert_rc 0
assert_err 'DOTFILES_HOST is set but empty'
assert_not_in "$OUT/$CASE.err" 'recorded a common-only'
printf '%s\n' "$TEST_TMP/elsewhere" Linux '' test-head >"$STATE_FILE"
expect_usage_error state-common-only-other-home 'none recorded for this home' --
printf '%s\n' "$TEST_HOME" Darwin '' test-head >"$STATE_FILE"
expect_usage_error state-common-only-other-kernel 'none recorded for this home' --
printf '%s\n' "$TEST_HOME" Linux '' >"$STATE_FILE"
expect_usage_error state-common-only-truncated 'none recorded for this home' --
rm -f "$STATE_FILE"

# --- baseline: every required row ok ---------------------------------------

run_doctor baseline-tsv -- --host lab-ubuntu --tsv
assert_rc 0
assert_tsv_shape
[ ! -s "$OUT/$CASE.err" ] ||
    case_fail "--tsv wrote to stderr"
for id in git fzf zsh alt brew-only oh-my-zsh demo-plugin bat-theme gh tldr claude codex \
    locale venv-sync submodule stow-links path-order rc-pollution omz-order nvm-homebrew; do
    assert_row "$id" ok '' -
done
assert_row fzf ok "0.60.0 >= 0.58.0 at $FAKE_BIN/fzf"
assert_row alt ok "1.2.3 >= 1.0 at $FAKE_BIN/doctor-alt"
assert_row brew-only ok "at $BREW_BIN/doctor-brew-only"
assert_row bat-theme ok "$TEST_HOME/.config/bat/themes/Catppuccin Mocha.tmTheme"
assert_row tldr ok "1.6.1 at $FAKE_BIN/tldr"
assert_row desk-tool warn 'not found; no terminal' 'docs/bootstrap.md S6-kitty'
assert_row nerd-font warn
assert_row host-tool warn
assert_row psfzf skip '' -
assert_row submodule ok 'common/pymol/PyMOLScripts, common/sherlock-kit/sherlock-kit' -
assert_row codex-override skip 'lab-ubuntu has no sherlock-kit rules' -
for id in login-tool lmod mac-clt mac-alt win-only gh-auth claude-auth codex-auth zsh-smoke; do
    assert_no_row "$id"
done
assert_event 'fzf --version'
assert_no_event 'fc-list'
[ ! -e "$TEST_HOME/.local/state/gh/device-id" ] || case_fail 'gh --version wrote its telemetry device id'
[ ! -e "$TEST_HOME/.tldrc" ] || case_fail 'tldr --version updated its page cache'
assert_event "sync-python -I -B -X utf8 $FIXTURE/lib/config_sync.py --runtime-check"
assert_no_event NETWORK
assert_no_event 'zsh -ic'

run_doctor baseline-log -- --host lab-ubuntu
assert_rc 0
assert_out '[dotfiles] [step] Checking host lab-ubuntu (debian); required tiers: core,cli,ai'
assert_out "[dotfiles] [ok] core fzf: 0.60.0 >= 0.58.0 at $FAKE_BIN/fzf"
assert_out '[dotfiles] [info] desktop psfzf: PowerShell module PSFzf; doctor.ps1 checks it'
assert_err '[dotfiles] [warn] desktop desk-tool: not found; no terminal (docs/bootstrap.md S6-kitty)'
assert_out '[dotfiles] [info] summary: '
assert_out ' 0 outdated, 0 missing, 3 warn, 2 skip, 0 human (lab-ubuntu, required tiers: core,cli,ai)'
assert_no_event NETWORK

# --- versions, missing tools and tiers -------------------------------------

run_doctor outdated-log FZF_VERSION=0.44.1 -- --host lab-ubuntu
assert_rc 1
assert_err "[dotfiles] [error] core fzf: 0.44.1 < 0.58.0 at $FAKE_BIN/fzf (docs/bootstrap.md S2-brew-bundle)"
run_doctor outdated-tsv FZF_VERSION=0.44.1 -- --host lab-ubuntu --tsv
assert_rc 1
assert_row fzf outdated '' 'docs/bootstrap.md S2-brew-bundle'
run_doctor outdated-unselected FZF_VERSION=0.44.1 -- --host lab-ubuntu --tier cli,ai --tsv
assert_rc 0
assert_row fzf warn '0.44.1 < 0.58.0'
run_doctor unparseable-version FZF_VERSION=dev -- --host lab-ubuntu --tsv
assert_rc 0
assert_row fzf warn 'version unknown, need >= 0.58.0'

# Neither alternative of doctor-none,doctor-alt exists (fixture-only names,
# so a runner's own tools cannot satisfy the probe).
mv "$FAKE_BIN/doctor-alt" "$TEST_TMP/doctor-alt.hidden"
run_doctor missing-tool -- --host lab-ubuntu --tsv
assert_rc 1
assert_row alt missing 'not found; alt tool missing' 'docs/bootstrap.md S2-brew-bundle'
run_doctor missing-tool-log -- --host lab-ubuntu
assert_rc 1
assert_err '[dotfiles] [error] core alt: not found; alt tool missing (docs/bootstrap.md S2-brew-bundle)'
mv "$TEST_TMP/doctor-alt.hidden" "$FAKE_BIN/doctor-alt"

run_doctor tier-all -- --host lab-ubuntu --tier all --tsv
assert_rc 1
assert_row desk-tool missing
assert_row nerd-font missing
assert_row host-tool missing
assert_row psfzf skip
assert_row fzf ok
run_doctor tier-desktop -- --host lab-ubuntu --tier core,cli,ai,desktop --tsv
assert_rc 1
assert_row desk-tool missing
assert_row host-tool warn
run_doctor tier-host -- --host lab-ubuntu --tier host --tsv
assert_rc 1
assert_row host-tool missing
assert_row desk-tool warn

# Homebrew's bin joins this process's PATH only; without it the tool is gone.
run_doctor no-brew BOOTSTRAP_BREW_CANDIDATES= -- --host lab-ubuntu --tsv
assert_rc 1
assert_row brew-only missing

# --- probe kinds -----------------------------------------------------------

# Fonts are found by file name (any case, up to four levels deep) in the
# user's, the system's and Homebrew's font directories; fc-list never runs.
mkdir -p "$TEST_TMP/system-fonts/truetype/caskaydia"
printf 'ttf\n' >"$TEST_TMP/system-fonts/truetype/caskaydia/caskaydiamononerdfontmono-bold.ttf"
run_doctor font-system -- --host lab-ubuntu --tier all --tsv
assert_row nerd-font ok "$TEST_TMP/system-fonts/truetype/caskaydia/caskaydiamononerdfontmono-bold.ttf"
assert_no_event 'fc-list'
rm -rf "$TEST_TMP/system-fonts"
mkdir -p "$TEST_TMP/xdg-data/fonts/CaskaydiaMonoNerdFont"
printf 'ttf\n' >"$TEST_TMP/xdg-data/fonts/CaskaydiaMonoNerdFont/CaskaydiaMonoNerdFont-Regular.ttf"
run_doctor font-user "XDG_DATA_HOME=$TEST_TMP/xdg-data" -- --host lab-ubuntu --tier all --tsv
assert_row nerd-font ok 'CaskaydiaMonoNerdFont/CaskaydiaMonoNerdFont-Regular.ttf'
rm -rf "$TEST_TMP/xdg-data"
run_doctor font-absent -- --host lab-ubuntu --tier all --tsv
assert_row nerd-font missing 'no font file named like CaskaydiaMonoNerdFont'

mkdir -p "$TEST_HOME/Library/Fonts"
printf 'ttf\n' >"$TEST_HOME/Library/Fonts/CaskaydiaMonoNerdFont-Regular.ttf"
run_doctor font-mac BOOTSTRAP_UNAME_S=Darwin BOOTSTRAP_CLT_SHIMS= -- --host mac --tsv
assert_row nerd-font ok 'CaskaydiaMonoNerdFont-Regular.ttf'
assert_row locale skip
assert_row mac-clt ok
assert_no_event 'fc-list'
rm -rf "$TEST_HOME/Library"
run_doctor font-mac-missing BOOTSTRAP_UNAME_S=Darwin BOOTSTRAP_CLT_SHIMS= -- --host mac --tier all --tsv
assert_row nerd-font missing

# A file: probe of an executable reports its version against the floor, so
# an older executable at that path is outdated rather than ok.
run_doctor file-version -- --host lab-ubuntu --tsv
assert_row file-tool ok "2.81.0 >= 2.50.0 at $TEST_HOME/.fake-file-tool"
run_doctor file-version-old FILE_TOOL_VERSION=2.45.0 -- --host lab-ubuntu --tsv
assert_rc 1
assert_row file-tool outdated "2.45.0 < 2.50.0 at $TEST_HOME/.fake-file-tool" 'docs/bootstrap.md X-host-tools'
chmod 644 "$TEST_HOME/.fake-file-tool"
run_doctor file-version-not-executable -- --host lab-ubuntu --tsv
assert_rc 1
assert_row file-tool missing "not executable: $TEST_HOME/.fake-file-tool"
chmod 755 "$TEST_HOME/.fake-file-tool"
mv "$TEST_HOME/.fake-file-tool" "$TEST_HOME/.fake-file-tool.saved"
mkdir "$TEST_HOME/.fake-file-tool"
run_doctor file-version-directory -- --host lab-ubuntu --tsv
assert_rc 1
assert_row file-tool missing "no $TEST_HOME/.fake-file-tool"
rmdir "$TEST_HOME/.fake-file-tool"
mv "$TEST_HOME/.fake-file-tool.saved" "$TEST_HOME/.fake-file-tool"

run_doctor zsh-custom "ZSH_CUSTOM=$TEST_TMP/custom" -- --host lab-ubuntu --tsv
assert_rc 1
assert_row demo-plugin missing "no $TEST_TMP/custom/plugins/demo/src; no demo completions"
mkdir -p "$TEST_TMP/custom/plugins/demo/src"
run_doctor zsh-custom-present "ZSH_CUSTOM=$TEST_TMP/custom" -- --host lab-ubuntu --tsv
assert_rc 0
assert_row demo-plugin ok
run_doctor bat-config-dir "BAT_CONFIG_DIR=$TEST_TMP/bat" -- --host lab-ubuntu --tsv
assert_rc 1
assert_row bat-theme missing

# --- hpc: login env PATH, env probes, doc mapping ---------------------------

run_doctor hpc-no-login-env -- --host sherlock --tsv
assert_rc 1
assert_row login-tool missing '' 'docs/bootstrap.md S2-login-env'
assert_row lmod warn
assert_no_row nerd-font
mkdir -p "$TEST_HOME/micromamba/envs/login/bin"
write_fake "$TEST_HOME/micromamba/envs/login/bin/doctor-login" <<'SH'
#!/bin/sh
printf 'doctor-login 1.0\n'
SH
run_doctor hpc-login-env -- --host sherlock --tsv
assert_rc 0
assert_row login-tool ok "$TEST_HOME/micromamba/envs/login/bin/doctor-login"
# On hpc the login env stays ahead of ~/.local/bin, as the overlay puts it.
write_fake "$TEST_HOME/.local/bin/doctor-login" <<'SH'
#!/bin/sh
printf 'doctor-login 9.9\n'
SH
run_doctor hpc-login-first "PATH=$FAKE_BIN:/usr/bin:/bin" -- --host sherlock --tsv
assert_row login-tool ok "1.0 at $TEST_HOME/micromamba/envs/login/bin/doctor-login"
assert_row local-tool ok "at $TEST_HOME/.local/bin/doctor-local"
rm "$TEST_HOME/.local/bin/doctor-login"
run_doctor hpc-lmod LMOD_DIR=/opt/lmod -- --host marlowe --tier all --tsv
assert_row lmod ok
run_doctor hpc-no-lmod -- --host marlowe --tier all --tsv
assert_row lmod missing 'LMOD_DIR is not set; module is undefined'
run_doctor hpc-doc-map FZF_VERSION=0.44.1 -- --host sherlock --tsv
assert_row fzf outdated '' 'docs/bootstrap.md S2-login-env'
mv "$FAKE_BIN/claude" "$TEST_TMP/claude.hidden"
run_doctor hpc-doc-map-claude -- --host sherlock --tsv
assert_row claude missing '' 'docs/bootstrap.md S2-modules'
mv "$TEST_TMP/claude.hidden" "$FAKE_BIN/claude"

# --- platform mode, --list, --quiet, color -----------------------------------

run_doctor platform-debian -- --platform debian --tsv
assert_rc 0
assert_row fzf ok
assert_row codex-override skip 'no host overlay' -
for id in host-tool nerd-font login-tool lmod mac-clt mac-alt win-only; do
    assert_no_row "$id"
done
run_doctor platform-log -- --platform macos
assert_rc 0
assert_out '[dotfiles] [step] Checking platform macos without a host overlay'
assert_out '[dotfiles] [info] core locale: macOS ships en_US.UTF-8'

run_doctor list -- --host lab-ubuntu --list
assert_rc 0
assert_out "$(printf 'id\ttier\tprobe\tfloor\tdoc')"
assert_out "$(printf 'fzf\tcore\tfzf\t0.58.0\tS2-brew-bundle')"
assert_out "$(printf 'host-tool\thost\tdoctor-absent-host\t-\tX-host-tools')"
assert_out "$(printf 'locale\tcore\tcheck\t-\tH1-locale')"
assert_out "$(printf 'nvm-homebrew\tai\tcheck\t-\tS4-nvm')"
assert_out "$(printf 'codex-override\tai\tcheck\t-\tH7-stow')"
assert_no_out login-tool
assert_quiet_events '--list probed tools'
run_doctor list-hpc -- --host sherlock --list
assert_out "$(printf 'fzf\tcore\tfzf\t0.58.0\tS2-login-env')"
assert_out "$(printf 'claude\tai\tclaude\t-\tS2-modules')"
# Each profile's fix is a step that applies there: no apt on macOS or hpc,
# no sudo locale-gen on hpc, and X-other-linux without an overlay.
assert_out "$(printf 'zsh\tcore\tzsh\t-\tS2-login-env')"
assert_out "$(printf 'locale\tcore\tcheck\t-\tP0-preflight')"
run_doctor list-mac -- --host mac --list
assert_out "$(printf 'zsh\tcore\tzsh\t-\tS2-brew-bundle')"
assert_out "$(printf 'fzf\tcore\tfzf\t0.58.0\tS2-brew-bundle')"
run_doctor list-other -- --platform other --list
assert_out "$(printf 'zsh\tcore\tzsh\t-\tX-other-linux')"
assert_out "$(printf 'fzf\tcore\tfzf\t0.58.0\tX-other-linux')"
assert_out "$(printf 'claude\tai\tclaude\t-\tX-other-linux')"
assert_out "$(printf 'locale\tcore\tcheck\t-\tX-other-linux')"
run_doctor list-debian -- --platform debian --list
assert_out "$(printf 'zsh\tcore\tzsh\t-\tH1-apt-core')"

run_doctor quiet -- --host lab-ubuntu --quiet
assert_rc 0
assert_no_out '[dotfiles] [ok]'
assert_no_out '[dotfiles] [step]'
assert_no_out 'psfzf'
assert_err '[dotfiles] [warn] desktop desk-tool'
assert_out '[dotfiles] [info] summary: '
run_doctor quiet-tsv -- --host lab-ubuntu --quiet --tsv
assert_rc 0
assert_tsv_shape
awk -F '\t' 'NR > 1 && ($1 == "ok" || $1 == "skip") { bad = 1 } END { exit bad }' "$OUT/$CASE.out" ||
    case_fail "--quiet printed ok or skip rows"
assert_row desk-tool warn

run_doctor color DOTFILES_COLOR=always -- --host lab-ubuntu
grep -q "$ESC" "$OUT/$CASE.out" ||
    case_fail "DOTFILES_COLOR=always printed no color"
run_doctor no-color DOTFILES_COLOR=always NO_COLOR=1 -- --host lab-ubuntu --tier all
assert_rc 1
! grep -q "$ESC" "$OUT/$CASE.out" "$OUT/$CASE.err" || case_fail "NO_COLOR output has escape sequences"

# --- --online and --smoke ----------------------------------------------------

run_doctor online -- --host lab-ubuntu --online --tsv
assert_rc 0
assert_tsv_shape
assert_row gh-auth warn 'gh is not authenticated' 'docs/bootstrap.md H7-auth'
assert_row claude-auth warn
assert_row codex-auth warn
assert_event 'NETWORK gh auth status'
assert_event 'NETWORK claude auth status'
assert_event 'NETWORK codex login status'
[ "$(grep -c NETWORK "$EVENT_LOG")" = 3 ] ||
    case_fail "--online ran more than the three auth probes"
run_doctor online-ok AUTH_OK=1 -- --host lab-ubuntu --online --tsv
assert_rc 0
assert_row gh-auth ok
assert_row codex-auth ok
mv "$FAKE_BIN/codex" "$TEST_TMP/codex.hidden"
run_doctor online-no-codex -- --host lab-ubuntu --online --tsv
assert_rc 1
assert_row codex missing
assert_row codex-auth skip
assert_no_event 'NETWORK codex'
mv "$TEST_TMP/codex.hidden" "$FAKE_BIN/codex"

run_doctor smoke -- --host lab-ubuntu --smoke --tsv
assert_rc 0
assert_row zsh-smoke ok
assert_event "zsh -ic true DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0 PATH=$BASE_PATH"
assert_no_event NETWORK
run_doctor smoke-plugin "SMOKE_STDERR=[oh-my-zsh] plugin 'fzf-tab' not found" -- \
    --host lab-ubuntu --smoke --tsv
assert_rc 1
assert_row zsh-smoke missing "plugin 'fzf-tab' not found" 'docs/bootstrap.md H7-doctor'
run_doctor smoke-command "SMOKE_STDERR=zsh:1: command not found: eza" -- \
    --host lab-ubuntu --smoke --tier cli
assert_rc 1
assert_err '[dotfiles] [error] core zsh-smoke: zsh -ic true printed 1 finding(s): zsh:1: command not found: eza'
run_doctor smoke-exit SMOKE_RC=3 -- --host lab-ubuntu --smoke --tsv
assert_rc 1
assert_row zsh-smoke missing 'zsh -ic true exited 3'
# oh-my-zsh echoes its own "[oh-my-zsh] plugin 'x' not found", "theme 'x'
# not found" and the zoxide plugin's "zoxide not found" on stdout, so the
# smoke test reads both streams.
run_doctor smoke-stdout-plugin "SMOKE_STDOUT=[oh-my-zsh] plugin 'fzf-tab' not found" -- \
    --host lab-ubuntu --smoke --tsv
assert_rc 1
assert_row zsh-smoke missing "[oh-my-zsh] plugin 'fzf-tab' not found" 'docs/bootstrap.md H7-doctor'
run_doctor smoke-stdout-theme "SMOKE_STDOUT=[oh-my-zsh] theme 'powerlevel10k/powerlevel10k' not found" -- \
    --host lab-ubuntu --smoke --tsv
assert_rc 1
assert_row zsh-smoke missing "theme 'powerlevel10k/powerlevel10k' not found"
run_doctor smoke-stdout-zoxide "SMOKE_STDOUT=[oh-my-zsh] zoxide not found" -- \
    --host lab-ubuntu --smoke --tsv
assert_rc 1
assert_row zsh-smoke missing '[oh-my-zsh] zoxide not found'
# Plugins that report a missing tool themselves spell it without a space
# after "plugin", or as "Cannot find"; a read-only home fails with
# "Permission denied".
run_doctor smoke-tmux "SMOKE_STDERR=zsh tmux plugin: tmux not found. Please install tmux before using this plugin." -- \
    --host lab-ubuntu --smoke --tsv
assert_rc 1
assert_row zsh-smoke missing 'zsh tmux plugin: tmux not found'
run_doctor smoke-fzf "SMOKE_STDERR=[oh-my-zsh] fzf plugin: Cannot find fzf installation directory." -- \
    --host lab-ubuntu --smoke --tsv
assert_rc 1
assert_row zsh-smoke missing 'fzf plugin: Cannot find fzf installation directory.'
run_doctor smoke-permission "SMOKE_STDERR=mkdir: cannot create directory '/x': Permission denied" -- \
    --host lab-ubuntu --smoke --tsv
assert_rc 1
assert_row zsh-smoke missing "cannot create directory '/x': Permission denied"
# A tty-less zsh complains about stty; that line is noise, not a finding.
run_doctor smoke-stty "SMOKE_STDERR=stty: 'standard input': Inappropriate ioctl for device" -- \
    --host lab-ubuntu --smoke --tsv
assert_rc 0
assert_row zsh-smoke ok 'zsh -ic true started without errors'
# Findings on both streams are counted together.
run_doctor smoke-both "SMOKE_STDOUT=[oh-my-zsh] plugin 'fzf-tab' not found" \
    "SMOKE_STDERR=zsh:1: command not found: eza" -- --host lab-ubuntu --smoke --tier cli
assert_rc 1
assert_err '[dotfiles] [error] core zsh-smoke: zsh -ic true printed 2 finding(s): '

# --- structural checks: negative, then back to ok ----------------------------

run_doctor locale-missing LOCALE_EXTRA= -- --host lab-ubuntu --tsv
assert_rc 1
assert_row locale missing '' 'docs/bootstrap.md H1-locale'
run_doctor locale-upper LOCALE_EXTRA=en_US.UTF-8 -- --host lab-ubuntu --tsv
assert_row locale ok

mv "$FIXTURE/.venv-sync" "$TEST_TMP/venv.hidden"
run_doctor venv-missing -- --host lab-ubuntu --tsv
assert_rc 1
assert_row venv-sync missing '' 'docs/bootstrap.md S4-setup-sync'
run_doctor venv-env "DOTFILES_SYNC_PYTHON=$FAKE_BIN/sync-python" -- --host lab-ubuntu --tsv
assert_rc 0
assert_row venv-sync ok
mv "$TEST_TMP/venv.hidden" "$FIXTURE/.venv-sync"
run_doctor venv-env-bad "DOTFILES_SYNC_PYTHON=$TEST_TMP/no-python" -- --host lab-ubuntu --tsv
assert_rc 1
assert_row venv-sync missing "DOTFILES_SYNC_PYTHON='$TEST_TMP/no-python' fails lib/config_sync.py --runtime-check"
# An executable that fails the runtime check (an interrupted setup-sync.sh
# leaves a venv without tomlkit) is missing, as doctor.ps1 and setup-host's
# S4-setup-sync judge it.
run_doctor venv-env-broken "DOTFILES_SYNC_PYTHON=$FAKE_BIN/sync-python" SYNC_RUNTIME_RC=1 -- --host lab-ubuntu --tsv
assert_rc 1
assert_row venv-sync missing "DOTFILES_SYNC_PYTHON='$FAKE_BIN/sync-python' fails lib/config_sync.py --runtime-check" \
    'docs/bootstrap.md S4-setup-sync'
run_doctor venv-broken SYNC_RUNTIME_RC=1 -- --host lab-ubuntu --tsv
assert_rc 1
assert_row venv-sync missing "$FIXTURE/.venv-sync/bin/python fails lib/config_sync.py --runtime-check; rerun ./setup-sync.sh"

mv "$FIXTURE/common/pymol/PyMOLScripts/configs/.pymolrc" "$TEST_TMP/pymolrc.hidden"
run_doctor submodule-missing -- --host lab-ubuntu --tsv
assert_rc 1
assert_row submodule missing \
    'no common/pymol/PyMOLScripts/configs/.pymolrc; the stowed links dangle (git submodule update --init --recursive)' \
    'docs/bootstrap.md P0-preflight'
mv "$TEST_TMP/pymolrc.hidden" "$FIXTURE/common/pymol/PyMOLScripts/configs/.pymolrc"

# Each sherlock-kit sentinel (both rules files, the skill and bin/shk) is
# required on its own; the PyMOL one stays out of the detail.
for sentinel in src/sherlock_kit/data/rules/workstation.md src/sherlock_kit/data/rules/cluster.md \
    src/sherlock_kit/data/skills/sherlock-kit/SKILL.md bin/shk; do
    mv "$SK_TREE/$sentinel" "$TEST_TMP/sentinel.hidden"
    run_doctor "submodule-sherlock-kit-${sentinel##*/}" -- --host lab-ubuntu --tsv
    assert_rc 1
    assert_row submodule missing \
        "no common/sherlock-kit/sherlock-kit/$sentinel; the stowed links dangle (git submodule update --init --recursive)" \
        'docs/bootstrap.md P0-preflight'
    case $(tsv_field submodule 4) in
        *pymolrc* | *', '*) case_fail 'submodule detail names more than the hidden sentinel' ;;
    esac
    mv "$TEST_TMP/sentinel.hidden" "$SK_TREE/$sentinel"
done
# An uninitialized sherlock-kit lists every sentinel it lacks.
mv "$SK_TREE" "$TEST_TMP/sherlock-kit.hidden"
mkdir "$SK_TREE"
run_doctor submodule-sherlock-kit-empty -- --host lab-ubuntu --tsv
assert_rc 1
assert_row submodule missing \
    'no common/sherlock-kit/sherlock-kit/src/sherlock_kit/data/rules/workstation.md, common/sherlock-kit/sherlock-kit/src/sherlock_kit/data/rules/cluster.md, common/sherlock-kit/sherlock-kit/src/sherlock_kit/data/skills/sherlock-kit/SKILL.md, common/sherlock-kit/sherlock-kit/bin/shk;'
# The check follows .gitmodules: without the sherlock-kit entry its absent
# tree is no alarm, a submodule it has no sentinels for needs its .git, and
# a checkout without .gitmodules has nothing to check.
printf '%s\n' '[submodule "common/pymol/PyMOLScripts"]' '	path = common/pymol/PyMOLScripts' \
    '[submodule "common/demo/Demo"]' '    path   =   common/demo/Demo  ' >"$FIXTURE/.gitmodules"
mkdir -p "$FIXTURE/common/demo/Demo"
run_doctor submodule-unknown -- --host lab-ubuntu --tsv
assert_rc 1
assert_row submodule missing 'no common/demo/Demo/.git; the stowed links dangle'
: >"$FIXTURE/common/demo/Demo/.git"
run_doctor submodule-unknown-ok -- --host lab-ubuntu --tsv
assert_rc 0
assert_row submodule ok 'common/pymol/PyMOLScripts, common/demo/Demo'
rm -rf "$FIXTURE/common/demo"
rm "$FIXTURE/.gitmodules"
run_doctor submodule-no-gitmodules -- --host lab-ubuntu --tsv
assert_rc 0
assert_row submodule ok 'no .gitmodules'
printf '%s\n' "$GITMODULES_BOTH" >"$FIXTURE/.gitmodules"
rmdir "$SK_TREE"
mv "$TEST_TMP/sherlock-kit.hidden" "$SK_TREE"
run_doctor submodule-restored -- --host lab-ubuntu --tsv
assert_rc 0
assert_row submodule ok

# With coding-agent-kit as the third entry, its eight sentinels are checked in
# .gitmodules order after the other two, each one on its own, and an
# uninitialized checkout lists all of them.
printf '%s\n' "$GITMODULES_BOTH" '[submodule "common/codex/coding-agent-kit"]' \
    '	path = common/codex/coding-agent-kit' '	url = https://github.com/FridrichMethod/coding-agent-kit.git' \
    '	branch = main' >"$FIXTURE/.gitmodules"
run_doctor submodule-coding-agent-kit -- --host lab-ubuntu --tsv
assert_rc 0
assert_row submodule ok 'common/pymol/PyMOLScripts, common/sherlock-kit/sherlock-kit, common/codex/coding-agent-kit' -
number=0
cak_missing=
for sentinel in $CAK_SENTINELS; do
    number=$((number + 1))
    cak_missing="$cak_missing, common/codex/coding-agent-kit/$sentinel"
    mv "$CAK_TREE/$sentinel" "$TEST_TMP/sentinel.hidden"
    run_doctor "submodule-coding-agent-kit-$number" -- --host lab-ubuntu --tsv
    assert_rc 1
    assert_row submodule missing \
        "no common/codex/coding-agent-kit/$sentinel; the stowed links dangle (git submodule update --init --recursive)" \
        'docs/bootstrap.md P0-preflight'
    case $(tsv_field submodule 4) in
        *', '*) case_fail 'submodule detail names more than the hidden sentinel' ;;
    esac
    mv "$TEST_TMP/sentinel.hidden" "$CAK_TREE/$sentinel"
done
mv "$CAK_TREE" "$TEST_TMP/coding-agent-kit.hidden"
mkdir "$CAK_TREE"
run_doctor submodule-coding-agent-kit-empty -- --host lab-ubuntu --tsv
assert_rc 1
assert_row submodule missing "no ${cak_missing#, }; the stowed links dangle (git submodule update --init --recursive)"
rmdir "$CAK_TREE"
mv "$TEST_TMP/coding-agent-kit.hidden" "$CAK_TREE"
printf '%s\n' "$GITMODULES_BOTH" >"$FIXTURE/.gitmodules"
run_doctor submodule-coding-agent-kit-restored -- --host lab-ubuntu --tsv
assert_rc 0
assert_row submodule ok 'common/pymol/PyMOLScripts, common/sherlock-kit/sherlock-kit' -

# codex-override: on a host whose sherlock-kit package links the toolkit
# rules (wsl-ubuntu here), ~/.codex/AGENTS.override.md must be what
# stow-all.sh generates from the portable AGENTS.md and those rules. The row
# runs the real codex-instructions-sync --check, which never writes.
WSL_RULES="$FIXTURE/wsl-ubuntu/sherlock-kit/.claude/rules/sherlock-kit.md"
OVERRIDE="$TEST_HOME/.codex/AGENTS.override.md"
mkdir -p "${WSL_RULES%/*}" "$TEST_HOME/.codex"
ln -s ../../../../common/sherlock-kit/sherlock-kit/src/sherlock_kit/data/rules/workstation.md "$WSL_RULES"
# sync_override: generate the override as stow-all.sh wsl-ubuntu does.
sync_override() {
    env -i HOME="$TEST_HOME" PATH="$BASE_PATH" DOTFILES_SYNC_PYTHON="$SYNC_PYTHON" \
        "$FIXTURE/common/codex/.local/bin/codex-instructions-sync" --quiet --append "$WSL_RULES" \
        "$FIXTURE/common/codex/.codex/AGENTS.md" "$OVERRIDE"
}

run_doctor codex-absent -- --host wsl-ubuntu --tsv
assert_rc 1
assert_row codex-override missing \
    'no ~/.codex/AGENTS.override.md, so Codex misses the wsl-ubuntu sherlock-kit rules; rerun ./stow-all.sh wsl-ubuntu' \
    'docs/bootstrap.md H7-stow'
assert_event "codex-instructions-sync --check --append $WSL_RULES"

sync_override
run_doctor codex-current -- --host wsl-ubuntu --tsv
assert_rc 0
assert_tsv_shape
assert_row codex-override ok '~/.codex/AGENTS.override.md is current' -
run_doctor codex-current-log -- --host wsl-ubuntu
assert_rc 0
assert_out '[dotfiles] [ok] ai codex-override: generated ~/.codex/AGENTS.override.md is current'

printf 'a hand edit\n' >>"$OVERRIDE"
run_doctor codex-stale -- --host wsl-ubuntu --tsv
assert_rc 1
assert_row codex-override outdated \
    '~/.codex/AGENTS.override.md is stale; rerun ./stow-all.sh wsl-ubuntu' 'docs/bootstrap.md H7-stow'
run_doctor codex-stale-unselected -- --host wsl-ubuntu --tier core,cli --tsv
assert_rc 0
assert_row codex-override warn 'is stale'

# A file the helper did not generate (a hand-written override, a symlink, a
# directory) suppresses ~/.codex/AGENTS.md and the rules; stow-all.sh
# refuses to replace it, so a person decides.
printf '# my own Codex instructions\n' >"$OVERRIDE"
run_doctor codex-foreign -- --host wsl-ubuntu --tsv
assert_rc 1
assert_row codex-override human \
    '~/.codex/AGENTS.override.md was not generated by codex-instructions-sync' 'docs/bootstrap.md H7-stow'
assert_row codex-override human 'Codex reads it instead of ~/.codex/AGENTS.md and the wsl-ubuntu sherlock-kit rules'
grep -Fxq '# my own Codex instructions' "$OVERRIDE" || case_fail 'the doctor changed a foreign override'
rm "$OVERRIDE"
ln -s "$FIXTURE/common/codex/.codex/AGENTS.md" "$OVERRIDE"
run_doctor codex-symlink -- --host wsl-ubuntu --tsv
assert_rc 1
assert_row codex-override human 'was not generated by codex-instructions-sync'
rm "$OVERRIDE"
mkdir "$OVERRIDE"
run_doctor codex-directory -- --host wsl-ubuntu --tsv
assert_rc 1
assert_row codex-override human 'was not generated by codex-instructions-sync'
rmdir "$OVERRIDE"
# An override the helper cannot read is not provably generated either
# ("unreadable, so not provably generated"). Root reads any file.
if [ "$(id -u)" != 0 ]; then
    sync_override
    chmod 000 "$OVERRIDE"
    run_doctor codex-unreadable -- --host wsl-ubuntu --tsv
    chmod 644 "$OVERRIDE"
    assert_rc 1
    assert_row codex-override human 'was not generated by codex-instructions-sync' 'docs/bootstrap.md H7-stow'
    rm "$OVERRIDE"
else
    printf 'SKIP: unreadable Codex override (root reads a mode-000 file).\n'
fi

# An uninitialized submodule leaves the rules link dangling.
sync_override
mv "$SK_DATA/rules/workstation.md" "$TEST_TMP/workstation.hidden"
run_doctor codex-dangling -- --host wsl-ubuntu --tsv
assert_rc 1
assert_row codex-override missing \
    'the wsl-ubuntu sherlock-kit rules link dangles, so ~/.codex/AGENTS.override.md cannot be checked (git submodule update --init --recursive)' \
    'docs/bootstrap.md H7-stow'
assert_row submodule missing 'src/sherlock_kit/data/rules/workstation.md'
mv "$TEST_TMP/workstation.hidden" "$SK_DATA/rules/workstation.md"

# Any other failure of the helper is reported as such, not as a foreign file.
run_doctor codex-no-runtime "DOTFILES_SYNC_PYTHON=$TEST_TMP/no-python" -- --host wsl-ubuntu --tsv
assert_rc 1
assert_row codex-override missing 'codex-instructions-sync --check failed (exit 1): config-sync: Python runtime unavailable'
chmod -x "$FIXTURE/common/codex/.local/bin/codex-instructions-sync"
run_doctor codex-no-helper -- --host wsl-ubuntu --tsv
assert_rc 1
assert_row codex-override missing 'codex-instructions-sync --check failed (exit 126): '
assert_row codex-override missing 'codex-instructions-sync: Permission denied'
chmod +x "$FIXTURE/common/codex/.local/bin/codex-instructions-sync"

# A current override over the local 28 KiB advisory threshold is a warning;
# it does not establish that Codex truncated the global instructions.
awk 'BEGIN { for (i = 0; i < 600; i++) print "- fixture rule line " i " padded to fifty bytes ...." }' \
    >"$TEST_TMP/big-rules.md"
ln -sfn "$TEST_TMP/big-rules.md" "$WSL_RULES"
sync_override
run_doctor codex-oversized -- --host wsl-ubuntu --tsv
assert_rc 0
assert_row codex-override warn 'is current but' 'docs/bootstrap.md H7-stow'
assert_row codex-override warn 'over the local 28 KiB advisory threshold; review context usage'
ln -sfn ../../../../common/sherlock-kit/sherlock-kit/src/sherlock_kit/data/rules/workstation.md "$WSL_RULES"
rm "$TEST_TMP/big-rules.md"
sync_override
run_doctor codex-restored -- --host wsl-ubuntu --tsv
assert_rc 0
assert_row codex-override ok
# A host without the rules link skips the row whatever ~/.codex holds. The
# link and the current override stay for the read-only cases below.
run_doctor codex-other-host -- --host lab-ubuntu --tsv
assert_rc 0
assert_row codex-override skip 'lab-ubuntu has no sherlock-kit rules; Codex reads ~/.codex/AGENTS.md' -

rm "$TEST_HOME/.profile"
run_doctor stow-absent -- --host lab-ubuntu --tsv
assert_rc 1
assert_row stow-links missing '~/.profile is absent' 'docs/bootstrap.md H7-stow'
printf 'regular\n' >"$TEST_HOME/.profile"
run_doctor stow-regular -- --host lab-ubuntu --tsv
assert_row stow-links missing '~/.profile is not a symlink'
rm "$TEST_HOME/.profile"
ln -s ../fixture/common/sh/.gone "$TEST_HOME/.profile"
run_doctor stow-dangling -- --host lab-ubuntu --tsv
assert_row stow-links missing '~/.profile is a dangling symlink'
rm "$TEST_HOME/.profile"
mkdir -p "$TEST_TMP/other/common/sh"
printf 'other\n' >"$TEST_TMP/other/common/sh/.profile"
ln -s "$TEST_TMP/other/common/sh/.profile" "$TEST_HOME/.profile"
run_doctor stow-elsewhere -- --host lab-ubuntu --tsv
assert_rc 0
assert_row stow-links warn "~/.profile -> $TEST_TMP/other/common/sh/.profile"
rm "$TEST_HOME/.profile"
ln -s ../fixture/common/sh/.profile "$TEST_HOME/.profile"

# Homebrew and conda ahead of ~/.local/bin are the overlays' order: only an
# executable that shadows one in ~/.local/bin is reported.
run_doctor path-brew-first "PATH=$BREW_BIN:$TEST_TMP/miniforge3/condabin:$BASE_PATH" -- --host lab-ubuntu --tsv
assert_rc 0
assert_row path-order ok 'no command setup-host puts in ~/.local/bin is shadowed'
# kitty as S6-kitty links it, and a second kitty from conda ahead of it; a
# command setup-host does not manage (doctor-local) is not judged.
write_fake "$TEST_HOME/.local/bin/kitty" <<'SH'
#!/bin/sh
printf 'kitty 0.49.2\n'
SH
mkdir -p "$TEST_TMP/miniforge3/bin"
cp "$TEST_HOME/.local/bin/kitty" "$TEST_HOME/.local/bin/doctor-local" "$TEST_TMP/miniforge3/bin/"
run_doctor path-shadow "PATH=$TEST_TMP/miniforge3/bin:$BASE_PATH" -- --host lab-ubuntu --tsv
assert_rc 0
assert_row path-order warn "1 command(s) in ~/.local/bin are shadowed by an earlier PATH entry: $TEST_TMP/miniforge3/bin/kitty;" \
    'docs/bootstrap.md H7-stow'
rm "$TEST_TMP/miniforge3/bin/doctor-local"
# The same file under another name for its directory is no shadow.
ln -s "$TEST_HOME/.local/bin" "$TEST_TMP/local-alias"
run_doctor path-same-file "PATH=$TEST_TMP/local-alias:$BASE_PATH" -- --host lab-ubuntu --tsv
assert_row path-order ok
rm "$TEST_TMP/local-alias"
# The doctor's own Homebrew prepend never counts against the caller's PATH.
run_doctor path-own-prepend "HOMEBREW_PREFIX=$TEST_TMP/brew" -- --host lab-ubuntu --tsv
assert_row path-order ok
assert_row brew-only ok
run_doctor path-no-local-bin "PATH=$FAKE_BIN:/usr/bin:/bin" -- --host lab-ubuntu --tsv
assert_row path-order warn 'PATH lacks ~/.local/bin'
# ~/.local/bin joins this process's PATH, ahead of Homebrew's bin as in the
# stowed shells, so what setup-host linked there is found before the first
# stow; path-order above still judges the caller's PATH.
assert_rc 0
assert_row local-tool ok "2.0 at $TEST_HOME/.local/bin/doctor-local"
write_fake "$TEST_HOME/.local/bin/doctor-brew-only" <<'SH'
#!/bin/sh
printf 'doctor-brew-only 4.0\n'
SH
run_doctor local-before-brew "PATH=$FAKE_BIN:/usr/bin:/bin" -- --host lab-ubuntu --tsv
assert_row brew-only ok "4.0 at $TEST_HOME/.local/bin/doctor-brew-only"
rm "$TEST_HOME/.local/bin/doctor-brew-only"
# On hpc the login env comes first on purpose, even over ~/.local/bin.
cp "$TEST_TMP/miniforge3/bin/kitty" "$TEST_HOME/micromamba/envs/login/bin/kitty"
LOGIN_FIRST="PATH=$TEST_HOME/micromamba/envs/login/bin:$BASE_PATH"
run_doctor path-login-hpc "$LOGIN_FIRST" -- --host sherlock --tsv
assert_row path-order ok
run_doctor path-login-debian "$LOGIN_FIRST" -- --host lab-ubuntu --tsv
assert_row path-order warn "$TEST_HOME/micromamba/envs/login/bin/kitty"
rm "$TEST_HOME/micromamba/envs/login/bin/kitty" "$TEST_HOME/.local/bin/kitty"

restore_common() {
    "$REAL_GIT" -C "$FIXTURE" checkout -q -- common
    "$REAL_GIT" -C "$FIXTURE" clean -qfd -- common
}

printf 'backup\n' >"$TEST_HOME/.zshrc.pre-oh-my-zsh"
run_doctor rc-pre-omz -- --host lab-ubuntu --tsv
assert_rc 1
assert_row rc-pollution human '~/.zshrc.pre-oh-my-zsh exists' 'docs/bootstrap.md X-rc-protection'
rm "$TEST_HOME/.zshrc.pre-oh-my-zsh"

printf '# >>> Codex installer >>>\nexport PATH=x\n# <<< Codex installer <<<\n' >>"$FIXTURE/common/zsh/.zshrc"
run_doctor rc-codex -- --host lab-ubuntu --tsv
assert_rc 1
assert_row rc-pollution human 'common/zsh/.zshrc has a Codex installer block'
assert_row rc-pollution human '1 uncommitted change(s) under common/, first: common/zsh/.zshrc'
run_doctor rc-codex-unselected -- --host lab-ubuntu --tier cli,ai --tsv
assert_rc 0
assert_row rc-pollution warn
restore_common

printf '# >>> conda initialize >>>\n# <<< conda initialize <<<\n' >>"$FIXTURE/common/sh/.profile"
run_doctor rc-conda -- --host lab-ubuntu --tsv
assert_rc 1
assert_row rc-pollution human 'common/sh/.profile has a conda or mamba initialize block'
restore_common

# shellcheck disable=SC2016 # the nvm installer's literal loader line
printf '%s\n' 'export NVM_DIR="$HOME/.nvm"' \
    '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' \
    >>"$FIXTURE/common/bash/.bashrc"
run_doctor rc-nvm -- --host lab-ubuntu --tsv
assert_rc 1
assert_row rc-pollution human 'common/bash/.bashrc has an nvm installer loader'
restore_common

printf '# local edit\n' >>"$FIXTURE/common/git/.gitconfig"
run_doctor rc-dirty -- --host lab-ubuntu --tsv
assert_rc 0
assert_row rc-pollution warn '1 uncommitted change(s) under common/, first: common/git/.gitconfig'
restore_common
printf 'new\n' >"$FIXTURE/common/new-file"
run_doctor rc-untracked -- --host lab-ubuntu --tsv
assert_row rc-pollution warn 'first: common/new-file'
restore_common

mv "$TEST_HOME/.oh-my-zsh/oh-my-zsh.sh" "$TEST_TMP/omz.hidden"
run_doctor omz-order -- --host lab-ubuntu --tsv
assert_rc 1
assert_row omz-order human '' 'docs/bootstrap.md X-recovery'
assert_row oh-my-zsh missing
mv "$TEST_HOME/.oh-my-zsh" "$TEST_TMP/omz-dir.hidden"
run_doctor omz-absent -- --host lab-ubuntu --tsv
assert_row omz-order ok
assert_row oh-my-zsh missing
mv "$TEST_TMP/omz-dir.hidden" "$TEST_HOME/.oh-my-zsh"
mv "$TEST_TMP/omz.hidden" "$TEST_HOME/.oh-my-zsh/oh-my-zsh.sh"

mkdir -p "$TEST_TMP/kegs/nvm"
run_doctor nvm-homebrew -- --host lab-ubuntu --tsv
assert_rc 0
assert_row nvm-homebrew warn "Homebrew nvm at $TEST_TMP/kegs/nvm is unsupported" 'docs/bootstrap.md S4-nvm'
rmdir "$TEST_TMP/kegs/nvm"

# A macOS developer-tool stub is never executed while the CLT are absent.
run_doctor clt-shim BOOTSTRAP_UNAME_S=Darwin "BOOTSTRAP_CLT_SHIMS=$FAKE_BIN/doctor-clt" -- \
    --host mac --tsv
assert_rc 1
assert_row mac-clt missing 'Command Line Tools are not installed'
assert_row mac-alt ok "at $FAKE_BIN/doctor-alt"
assert_no_event doctor-clt
run_doctor clt-installed BOOTSTRAP_UNAME_S=Darwin "BOOTSTRAP_CLT_SHIMS=$FAKE_BIN/doctor-clt" XCODE_OK=1 -- \
    --host mac --tsv
assert_row mac-clt ok
assert_event 'doctor-clt --version'

# --- invalid manifests (exit 2 before any probe) -----------------------------

# bad_manifest NAME TEXT: tools.tsv is the valid header (except for NAME
# header) plus stdin; the doctor must refuse it with exit 2 before probing.
bad_manifest() {
    local dir="$TEST_TMP/bad-$1"
    mkdir -p "$dir"
    {
        [ "$1" = header ] || row id tier hosts probe version_flag floor absent doc
        cat
    } >"$dir/tools.tsv"
    expect_usage_error "manifest-$1" "$2" "BOOTSTRAP_CONFIG=$dir" -- --host lab-ubuntu
}
mkdir -p "$TEST_TMP/bad-absent"
expect_usage_error manifest-absent 'missing or unreadable' "BOOTSTRAP_CONFIG=$TEST_TMP/bad-absent" -- \
    --host lab-ubuntu
{
    row id tier hosts probe flag floor absent doc
    row git core all git --version - x P0-preflight
} | bad_manifest header 'the header is not'
printf 'git\tcore\tall\tgit\t--version\t-\tP0-preflight\n' |
    bad_manifest columns 'does not have eight tab-separated columns'
row git core all bogus:git --version - x P0-preflight | bad_manifest probe "unknown probe 'bogus:git'"
row git gui all git --version - x P0-preflight | bad_manifest tier "unknown tier 'gui'"
row git core all,fedora git --version - x P0-preflight |
    bad_manifest hosts "names an unknown host in 'all,fedora'"
{
    row git core all git --version - x P0-preflight
    row git cli all git --version - x P0-preflight
} | bad_manifest duplicate 'duplicate id git'
row locale core all locale - - x H1-locale | bad_manifest reserved 'id locale is reserved for a doctor check'
row core-symlinks core all git - - x P0-preflight |
    bad_manifest reserved-windows 'id core-symlinks is reserved for a doctor check'
row zsh-smoke core all zsh - - x P0-preflight | bad_manifest reserved-smoke 'id zsh-smoke is reserved for a doctor check'
row git core all git --version 1.x x P0-preflight | bad_manifest floor "invalid floor '1.x'"
# shellcheck disable=SC2016 # manifest tokens are literal
row rc core all 'file:$PWD/.zshrc' - - x P0-preflight | bad_manifest token 'cannot be expanded'
# Empty cells and stray tabs: a tab-IFS read would merge or drop them and
# accept the row, while the host filter splits on every tab and drops it.
printf 'git\tcore\t\tall\tgit\t--version\t-\tcannot clone\tP0-preflight\n' |
    bad_manifest nine-cells 'row git does not have eight tab-separated columns'
printf '\tgit\tcore\tall\tgit\t--version\t-\tcannot clone\tP0-preflight\n' |
    bad_manifest leading-tab 'row ? does not have eight tab-separated columns'
printf 'git\tcore\tall\tgit\t--version\t-\tcannot clone\tP0-preflight\t\n' |
    bad_manifest trailing-tab 'row git does not have eight tab-separated columns'
printf 'git\tcore\t\tgit\t--version\t-\tcannot clone\tP0-preflight\n' |
    bad_manifest empty-cell 'row git does not have eight tab-separated columns'
row git core all git --version - x NOT-A-STEP |
    bad_manifest doc "row git cites step 'NOT-A-STEP', which has no '### NOT-A-STEP:' heading"
row git core all git --version - x 'P0-preflight:' | bad_manifest doc-chars "invalid doc step 'P0-preflight:'"
# A docs/bootstrap.md without that heading fails closed; without the file the
# doc column is not checked (the fixes then cite a file that is not there).
mv "$FIXTURE/docs/bootstrap.md" "$TEST_TMP/bootstrap.md.hidden"
printf '# Bootstrap\n\n### P0-preflight: Preflight\n' >"$FIXTURE/docs/bootstrap.md"
row git core all git --version - x S2-brew-bundle | bad_manifest doc-heading "cites step 'S2-brew-bundle'"
rm "$FIXTURE/docs/bootstrap.md"
run_doctor docs-absent "BOOTSTRAP_CONFIG=$TEST_TMP/bad-doc" -- --host lab-ubuntu --list
assert_rc 0
assert_out "$(printf 'git\tcore\tgit\t-\tNOT-A-STEP')"
mv "$TEST_TMP/bootstrap.md.hidden" "$FIXTURE/docs/bootstrap.md"

# --- the real manifest passes the doctor's own validation on every host -----

# --list validates config/bootstrap/tools.tsv as every run does, then prints
# without probing, so this catches drift between bootstrap_tool_row_valid,
# tests/test_bootstrap_manifest.py and docs/bootstrap.md.
REAL_CONFIG="BOOTSTRAP_CONFIG=$REPO_ROOT/config/bootstrap"
for host in mac wsl-ubuntu lab-ubuntu sherlock marlowe; do
    run_doctor "real-manifest-$host" "$REAL_CONFIG" -- --host "$host" --list
    assert_rc 0
    assert_not_in "$OUT/$CASE.err" 'invalid manifest'
    assert_out "$(printf 'fzf\tcore\tfzf\t0.58.0\t')"
    assert_out "$(printf 'nvm-homebrew\tai\tcheck\t-\t')"
    assert_quiet_events "--list probed tools with the real manifest on $host"
done
assert_out "$(printf 'lmod\thost\tenv:LMOD_DIR\t-\tS2-modules')"
run_doctor real-manifest-other "$REAL_CONFIG" -- --platform other --list
assert_rc 0
assert_not_in "$OUT/$CASE.err" 'invalid manifest'
assert_out "$(printf 'fzf\tcore\tfzf\t0.58.0\tX-other-linux')"
assert_no_out "$(printf 'pwsh\t')"
assert_quiet_events '--list probed tools with the real manifest on --platform other'

# --- the real doctor on this machine keeps the TSV contract -----------------

# The real ./doctor.sh, config/bootstrap and docs probe the tools of the
# machine running the tests (in CI the runner's) on the caller's PATH, so
# whatever those tools print, every line keeps the TSV contract: the header,
# five columns, a known status, and a fix that is - or a docs/bootstrap.md
# step with a heading. HOME is an empty temporary home (the caller's own home
# changes too often to snapshot), TMPDIR an empty dir with an old mtime, and
# neither of them nor the checkout may change. The checkout scan leaves out its
# git metadata (every .git): another git process (an editor refreshing the
# index, the login updater's fetch, a parallel session) may write there at
# any time, and the read-only fixture cases below already cover the doctor's
# own git, whose find includes the fixture's .git. The exit code depends on
# what this machine has installed: 0 or 1, never 2.
REAL_HOME="$TEST_TMP/real-home"
REAL_TMP="$TEST_TMP/real-tmp"
REAL_REF="$TEST_TMP/real.ref"
REAL_MARKER="$TEST_TMP/real.marker"
mkdir "$REAL_HOME" "$REAL_TMP"
DOC_STEPS=$(sed -n 's/^### \([A-Za-z0-9-]*\):.*/\1/p' "$REPO_ROOT/docs/bootstrap.md")
real_doctor_case() {
    local fix changed
    CASE=$1
    shift
    touch -t 200001010000 "$REAL_HOME" "$REAL_TMP" "$REAL_REF"
    : >"$REAL_MARKER"
    : >"$EVENT_LOG"
    if env -i HOME="$REAL_HOME" PATH="$PATH" TMPDIR="$REAL_TMP" LC_ALL=C TERM=dumb \
        "$BASH" "$REPO_ROOT/doctor.sh" "$@" >"$OUT/$CASE.out" 2>"$OUT/$CASE.err"; then
        RC=0
    else
        RC=$?
    fi
    case $RC in
        0 | 1) ;;
        *) case_fail "exit $RC, expected 0 or 1" ;;
    esac
    assert_tsv_shape
    for id in git locale venv-sync rc-pollution; do
        [ "$(tsv_field "$id" 1)" != '<no row>' ] || case_fail "no $id row"
    done
    awk -F '\t' 'NR > 1 { print $5 }' "$OUT/$CASE.out" | LC_ALL=C sort -u >"$OUT/$CASE.fixes"
    while IFS= read -r fix; do
        case $fix in
            -) ;;
            'docs/bootstrap.md '*)
                printf '%s\n' "$DOC_STEPS" | grep -Fxq -- "${fix#docs/bootstrap.md }" ||
                    case_fail "fix cites a step without a '###' heading: $fix"
                ;;
            *) case_fail "fix is neither - nor docs/bootstrap.md <step>: $fix" ;;
        esac
    done <"$OUT/$CASE.fixes"
    [ -z "$(find "$REAL_HOME" "$REAL_TMP" -mindepth 1 -print)" ] ||
        case_fail "the real doctor wrote into HOME or TMPDIR: $(find "$REAL_HOME" "$REAL_TMP" -mindepth 1 -print)"
    [ -z "$(find "$REAL_HOME" "$REAL_TMP" -maxdepth 0 -newer "$REAL_REF" -print)" ] ||
        case_fail 'the real doctor created and removed a file in HOME or TMPDIR'
    changed=$(find "$REPO_ROOT" -name .git -prune -o -newer "$REAL_MARKER" -print)
    [ -z "$changed" ] || case_fail "the real doctor wrote into the checkout: $changed"
}
real_doctor_case real-debian --platform debian --tsv
real_doctor_case real-other --platform other --tsv

# --- read-only and offline -----------------------------------------------------

MARKER="$TEST_TMP/marker"
: >"$MARKER"
run_doctor ro-log -- --host lab-ubuntu
assert_rc 0
run_doctor ro-all -- --host lab-ubuntu --tier all --tsv
assert_rc 1
run_doctor ro-online -- --host lab-ubuntu --online --quiet
assert_rc 0
run_doctor ro-list -- --host lab-ubuntu --list
assert_rc 0
run_doctor ro-codex -- --host wsl-ubuntu --tsv
assert_rc 0
assert_row codex-override ok
CHANGED=$(find "$TEST_HOME" "$FIXTURE" -newer "$MARKER" -print)
[ -z "$CHANGED" ] || fail "doctor wrote into the fixture or home: $CHANGED"

chmod -R a-w "$TEST_HOME" "$FIXTURE"
run_doctor read-only -- --host lab-ubuntu
assert_rc 0
! grep -Eqi 'permission denied|read-only' "$OUT/$CASE.err" || case_fail "doctor tried to write into a read-only home or checkout"
assert_no_event NETWORK
run_doctor read-only-codex -- --host wsl-ubuntu --tsv
assert_rc 0
assert_row codex-override ok
! grep -Eqi 'permission denied|read-only' "$OUT/$CASE.err" || case_fail "doctor tried to write into a read-only home or checkout"
chmod -R u+w "$TEST_HOME" "$FIXTURE"

# --- no temporary files ----------------------------------------------------

# Every mode but --smoke creates no file in TMPDIR, not even one it removes
# again: TMPDIR is an empty directory with an old mtime, which any file
# created or unlinked there would update. That catches mktemp and the
# here-document files of Bash 4 and later (5.1 and later only for a document
# larger than a pipe buffer). Bash 3.2 puts its here-document files in the
# C library's P_tmpdir whatever TMPDIR says, so bootstrap-manifest.sh scans
# these scripts for here-documents as well.
NO_TMP="$TEST_TMP/no-tmp"
NO_TMP_REF="$TEST_TMP/no-tmp.ref"
mkdir "$NO_TMP"
no_tmp_case() {
    touch -t 200001010000 "$NO_TMP" "$NO_TMP_REF"
    run_doctor "$@"
    [ -z "$(ls -A "$NO_TMP")" ] || case_fail "the doctor left files in TMPDIR: $(ls -A "$NO_TMP")"
    [ -z "$(find "$NO_TMP" -maxdepth 0 -newer "$NO_TMP_REF" -print)" ] ||
        case_fail 'the doctor created and removed a file in TMPDIR'
}
no_tmp_case no-tmp-log TMPDIR="$NO_TMP" -- --host lab-ubuntu
assert_rc 0
no_tmp_case no-tmp-tsv TMPDIR="$NO_TMP" -- --host lab-ubuntu --tier all --tsv
assert_rc 1
no_tmp_case no-tmp-quiet TMPDIR="$NO_TMP" -- --host lab-ubuntu --quiet --online
assert_rc 0
no_tmp_case no-tmp-list TMPDIR="$NO_TMP" -- --host lab-ubuntu --list
assert_rc 0
no_tmp_case no-tmp-platform TMPDIR="$NO_TMP" -- --platform other --tsv
assert_rc 0
no_tmp_case no-tmp-mac TMPDIR="$NO_TMP" BOOTSTRAP_UNAME_S=Darwin -- --host mac --tsv
assert_rc 0
no_tmp_case no-tmp-codex TMPDIR="$NO_TMP" -- --host wsl-ubuntu --tsv
assert_rc 0
assert_row codex-override ok
no_tmp_case no-tmp-help TMPDIR="$NO_TMP" -- --help
assert_rc 0
no_tmp_case no-tmp-usage TMPDIR="$NO_TMP" -- --tier gui
assert_rc 2

echo "doctor=PASS"
