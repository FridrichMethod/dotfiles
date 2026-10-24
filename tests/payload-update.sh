#!/bin/bash

set -euo pipefail

# Hermetic: the provisioning exports (DOTFILES_AUTO_UPDATE=0 and the like,
# docs/bootstrap.md) and other dotfiles knobs never reach the code under
# test from the caller; each case sets what it needs.
unset DOTFILES_AUTO_UPDATE DOTFILES_AUTO_STOW DOTFILES_HOST DOTFILES_DIR _DOTFILES_CHECKED \
    DOTFILES_STOW_WITHOUT_OH_MY_ZSH DOTFILES_COLOR DOTFILES_PAYLOAD_AUTO_UPDATE DOTFILES_PAYLOAD_ITEMS \
    DOTFILES_PAYLOAD_TIMEOUT AWESOME_SKILLS_AUTO_UPDATE \
    _DOTFILES_PAYLOAD_CHECKED CODING_AGENT_KIT_CONFIG CODING_AGENT_KIT_COLOR CODING_AGENT_KIT_USAGE_FILE \
    CODING_AGENT_KIT_TOKEN_ID CODING_AGENT_KIT_CLAUDE_PID CODING_AGENT_KIT_REPO_URL XDG_STATE_HOME XDG_DATA_HOME

# scripts/payload-update.sh against fake installers served from file:// URLs:
# the real config/payloads.tsv with its raw.githubusercontent.com prefix
# pointed at a local directory, and a curl that refuses every other scheme.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-payload-update.XXXXXX")"
TEST_TMP=$(cd -P -- "$TEST_TMP" && pwd -P)
cleanup() {
    local result=$?
    trap - EXIT HUP INT TERM
    [[ -z "${STALL:-}" ]] || kill "$STALL" 2>/dev/null || :
    rm -rf "$TEST_TMP"
    exit "$result"
}
trap cleanup EXIT HUP INT TERM

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    for file in "$OUT" "$ERR" "$EVENTS"; do
        [[ ! -f "$file" ]] || {
            printf -- '--- %s\n' "${file##*/}" >&2
            cat -- "$file" >&2
        }
    done
    exit 1
}

REAL_CURL=$(command -v curl) || {
    printf 'ERROR: tests/payload-update.sh needs curl (for file:// URLs).\n' >&2
    exit 1
}
REMOTE=$TEST_TMP/remote
FIXTURE=$TEST_TMP/repo
mkdir -p "$TEST_TMP/bin" "$FIXTURE/scripts" "$FIXTURE/lib" "$FIXTURE/config" \
    "$REMOTE/coding-agent-kit/main" "$REMOTE/PyMOLScripts/main" "$REMOTE/awesome-skills/main"
cp "$REPO_ROOT/scripts/payload-update.sh" "$REPO_ROOT/scripts/awesome-skills-update.sh" "$FIXTURE/scripts/"
cp "$REPO_ROOT/lib/terminal.sh" "$FIXTURE/lib/"
sed "s#https://raw.githubusercontent.com/FridrichMethod/#file://$REMOTE/#g" \
    "$REPO_ROOT/config/payloads.tsv" >"$FIXTURE/config/payloads.tsv"
grep -q "file://$REMOTE/coding-agent-kit/main/install.sh" "$FIXTURE/config/payloads.tsv" ||
    fail 'config/payloads.tsv no longer downloads the kit from raw.githubusercontent.com/FridrichMethod'
if grep -q 'https\?://' "$FIXTURE/config/payloads.tsv"; then
    fail 'config/payloads.tsv names a URL outside raw.githubusercontent.com/FridrichMethod'
fi

cat >"$TEST_TMP/bin/curl" <<'SH'
#!/bin/sh
# Only file:// URLs and the stalled 127.0.0.1 port: a test that would reach
# the network fails instead.
for argument do
    case $argument in
        file://* | http://127.0.0.1:*) ;;
        *://*)
            printf 'network refused: %s\n' "$argument" >&2
            exit 97
            ;;
    esac
done
printf 'curl\n' >>"$EVENTS"
exec "$REAL_CURL" "$@"
SH
# The kit's bootstrap installs a managed root whose current/install.sh is the
# update command, and the three Claude helpers.
cat >"$REMOTE/coding-agent-kit/main/install.sh" <<'SH'
#!/bin/sh
printf 'kit-install [%s] stdin=[%s]\n' "$*" "$(cat)" >>"$EVENTS"
[ "${FAKE_KIT_STATUS:-0}" = 0 ] || exit "$FAKE_KIT_STATUS"
root=${XDG_DATA_HOME:-$HOME/.local/share}/coding-agent-kit
mkdir -p "$root/current" "$HOME/.claude/coding-agent-kit"
printf '%s\n' '#!/bin/sh' 'printf "kit-update [%s]\n" "$*" >>"$EVENTS"' 'echo "kit-update: fake output" >&2' \
    'exit "${FAKE_KIT_STATUS:-0}"' >"$root/current/install.sh"
for helper in statusline notify check-git-hooks; do
    : >"$HOME/.claude/coding-agent-kit/$helper.cjs"
done
SH
cat >"$REMOTE/PyMOLScripts/main/install.sh" <<'SH'
#!/bin/sh
printf 'pymol-install [%s]\n' "$*" >>"$EVENTS"
[ "${FAKE_PYMOL_STATUS:-0}" = 0 ] || exit "$FAKE_PYMOL_STATUS"
: >"$HOME/.pymolrc"
: >"$HOME/.pymolrc.py"
SH
cat >"$REMOTE/awesome-skills/main/install.sh" <<'SH'
#!/bin/bash
printf 'skills-install [%s] bash=%s\n' "$*" "${BASH_VERSION:+yes}" >>"$EVENTS"
[ "${FAKE_SKILLS_STATUS:-0}" = 0 ] || exit "$FAKE_SKILLS_STATUS"
mkdir -p "$HOME/.local/share/awesome-skills"
printf '{}\n' >"$HOME/.local/share/awesome-skills/claude.json"
SH
chmod +x "$TEST_TMP/bin/curl"

CASE=0
# new_home: a fresh HOME and event log for the next case.
new_home() {
    CASE=$((CASE + 1))
    HOME_DIR=$TEST_TMP/home$CASE
    EVENTS=$TEST_TMP/events$CASE
    OUT=$TEST_TMP/out$CASE
    ERR=$TEST_TMP/err$CASE
    STATE=$HOME_DIR/.local/state/dotfiles/payload
    mkdir -p "$HOME_DIR"
    : >"$EVENTS"
}

# in_env COMMAND...: COMMAND in the case's home, with the fakes and only the
# system tools on PATH.
in_env() {
    env HOME="$HOME_DIR" PATH="$TEST_TMP/bin:/usr/bin:/bin" DOTFILES_DIR="$FIXTURE" EVENTS="$EVENTS" \
        REAL_CURL="$REAL_CURL" TMPDIR="$TEST_TMP" "$@"
}

# source_hook SHELL [ENV...]: source the hook from an interactive SHELL, as
# the rc files do, then report its session marker.
source_hook() {
    local shell=$1
    shift
    case $shell in
        bash) set -- "$@" bash --noprofile --norc -i -c ;;
        zsh) set -- "$@" zsh -f -i -c 'setopt extended_glob nounset glob_dots; eval "$1"' zsh ;;
        sh) set -- "$@" sh -i -c ;;
    esac
    in_env "$@" '. "$DOTFILES_DIR/scripts/payload-update.sh"; printf "marker=%s\n" "${_DOTFILES_PAYLOAD_CHECKED-}"' \
        >"$OUT" 2>"$ERR" || fail "sourcing the hook from $shell failed"
    # Only the hook's own log lines reach the terminal, never a shell error.
    if grep -q 'payload-update\.sh' "$ERR"; then
        fail "the hook printed a shell error under $shell"
    fi
}

# [VAR=VALUE...] now ITEM...: run the manual mode; sets STATUS.
now() {
    STATUS=0
    in_env sh "$FIXTURE/scripts/payload-update.sh" --now "$@" >"$OUT" 2>"$ERR" || STATUS=$?
}

events() { cat "$EVENTS"; }
expect_events() {
    [[ "$(grep -v '^curl$' "$EVENTS" || :)" == "$1" ]] || fail "expected events: $1"
}
expect_text() {
    grep -Fq -- "$2" "$1" || fail "${1##*/} lacks: $2"
}
stamp_age() {
    printf '%s\n' "$(($(date +%s) - $2))" >"$STATE/$1.stamp"
}
# wait_for COMMAND...: COMMAND succeeds within ten seconds (a background run).
wait_for() {
    local attempt
    for ((attempt = 0; attempt < 200; attempt++)); do
        "$@" 2>/dev/null && return 0
        sleep 0.05
    done
    fail "timed out waiting for: $*"
}

# A fresh home: the first interactive shell installs every item in the
# foreground, in config order, the kit on the declared channel, stdin closed,
# and stamps each success; the marker reaches the shell.
for shell in bash zsh sh; do
    command -v "$shell" >/dev/null 2>&1 || {
        printf 'SKIP: %s not installed\n' "$shell"
        continue
    }
    new_home
    source_hook "$shell"
    expect_events "kit-install [--channel 0.6] stdin=[]
pymol-install []
skills-install [] bash=yes"
    expect_text "$OUT" 'marker=1'
    expect_text "$OUT" '[dotfiles] [step] kit: installing (later updates run in the background)'
    expect_text "$OUT" '[dotfiles] [ok] skills: install done'
    for item in kit pymol skills; do
        [[ -s "$STATE/$item.stamp" ]] || fail "$shell: no $item stamp after its install"
    done
    [[ ! -e "$STATE/payload.log" ]] || fail "$shell: a first install started a background run"
    [[ -z "$(find "$TEST_TMP" -maxdepth 1 -name 'dotfiles-payload.*')" ]] || fail 'a download was left behind'
done

# Once installed and fresh, a new session does nothing at all.
: >"$EVENTS"
source_hook bash
expect_events ''
[[ ! -e "$STATE/payload.log" ]] || fail 'a fresh install started a background run'

# Once per session, opt-out, non-interactive: nothing runs.
new_home
source_hook bash _DOTFILES_PAYLOAD_CHECKED=1
expect_events ''
source_hook bash DOTFILES_PAYLOAD_AUTO_UPDATE=0
expect_events ''
expect_text "$OUT" 'marker=1'
in_env sh -c '. "$DOTFILES_DIR/scripts/payload-update.sh"; printf "marker=%s\n" "${_DOTFILES_PAYLOAD_CHECKED-}"' >"$OUT" 2>"$ERR"
expect_events ''
expect_text "$OUT" 'marker='
# A nested interactive shell inherits the marker: no second attempt, even at
# an item the first one failed to install.
in_env DOTFILES_PAYLOAD_ITEMS=pymol FAKE_PYMOL_STATUS=1 bash --noprofile --norc -i -c \
    '. "$DOTFILES_DIR/scripts/payload-update.sh"; bash --noprofile --norc -i -c ". \"\$DOTFILES_DIR/scripts/payload-update.sh\""' \
    >"$OUT" 2>"$ERR"
expect_events 'pymol-install []'

# DOTFILES_PAYLOAD_ITEMS selects the items; empty selects none.
new_home
source_hook bash DOTFILES_PAYLOAD_ITEMS='skills kit'
expect_events 'skills-install [] bash=yes
kit-install [--channel 0.6] stdin=[]'
new_home
source_hook bash DOTFILES_PAYLOAD_ITEMS=
expect_events ''
new_home
source_hook bash DOTFILES_PAYLOAD_ITEMS='kit nope'
expect_events ''
expect_text "$ERR" "unknown item 'nope'"

# An installed item whose interval passed is refreshed in one detached
# background run, with the update command (the kit's installed
# current/install.sh --update, the others' install command), into the log.
new_home
source_hook bash
: >"$EVENTS"
stamp_age kit 86400
stamp_age pymol 3600
stamp_age skills $((6 * 86400))
source_hook bash
wait_for grep -q 'kit: update done' "$STATE/payload.log"
expect_events 'kit-update [--update --channel 0.6]'
[[ ! -s "$OUT" || "$(cat "$OUT")" == marker=1 ]] || fail 'a background refresh printed in the shell'
stamp_age skills $((7 * 86400))
stamp_age pymol 86400
: >"$EVENTS"
source_hook bash
wait_for grep -q 'skills: update done' "$STATE/payload.log"
expect_events 'pymol-install []
skills-install [] bash=yes'

# A failed first install writes no stamp but ITEM.failed (time and exit
# status), says how to retry and never fails the shell. Every later session
# prints one line about it and does not retry it in the foreground; six
# hours after the failure it is retried in the background, and a success
# removes the record. Exit 75 (another run holds the repo's lock) is
# neither.
new_home
source_hook bash FAKE_KIT_STATUS=1
expect_text "$ERR" '[dotfiles] [error] kit: install failed (exit 1); retry with: sync-payloads kit'
expect_text "$OUT" 'marker=1'
[[ ! -e "$STATE/kit.stamp" && -e "$STATE/pymol.stamp" ]] || fail 'a failed install was stamped'
read -r _ code <"$STATE/kit.failed"
[[ "$code" == 1 ]] || fail 'the failure record lacks the exit status'
: >"$EVENTS"
source_hook bash
expect_events ''
expect_text "$ERR" "[dotfiles] [warn] kit: its last run failed (exit 1, see $STATE/kit.failed); run sync-payloads kit"
[[ ! -e "$STATE/payload.log" ]] || fail 'a fresh failure was retried'
printf '%s 1\n' "$(($(date +%s) - 21600))" >"$STATE/kit.failed"
source_hook bash
wait_for grep -q 'kit: install done' "$STATE/payload.log"
expect_events 'kit-install [--channel 0.6] stdin=[]'
[[ ! -e "$STATE/kit.failed" && -e "$STATE/kit.stamp" ]] || fail 'a success kept the failure record'
# A failed background run keeps the end of its output in the record, which
# the next session reports.
stamp_age kit 86400
source_hook bash FAKE_KIT_STATUS=4
wait_for grep -q 'kit-update: fake output' "$STATE/kit.failed"
read -r _ code <"$STATE/kit.failed"
[[ "$code" == 4 ]] || fail 'a background failure recorded the wrong status'
expect_text "$STATE/kit.failed" '[dotfiles] [error] kit: update failed (exit 4); retry with: sync-payloads kit'
source_hook bash
expect_text "$ERR" "[dotfiles] [warn] kit: its last run failed (exit 4, see $STATE/kit.failed)"
stamp_age pymol 86400
: >"$EVENTS"
FAKE_PYMOL_STATUS=75 now pymol
[[ "$STATUS" == 0 ]] || fail '--now failed on exit 75'
expect_text "$OUT" 'pymol: another run holds its lock'
[[ "$(cat "$STATE/pymol.stamp")" -lt "$(($(date +%s) - 3600))" && ! -e "$STATE/pymol.failed" ]] ||
    fail 'exit 75 was stamped or recorded'

# --now runs the named items whatever their intervals, records and the
# opt-out; it fails for a failed item and an unknown one.
new_home
DOTFILES_PAYLOAD_AUTO_UPDATE=0 now kit
[[ "$STATUS" == 0 ]] || fail '--now kit failed'
expect_events 'kit-install [--channel 0.6] stdin=[]'
: >"$EVENTS"
now kit
expect_events 'kit-update [--update --channel 0.6]'
FAKE_KIT_STATUS=3 now skills kit
[[ "$STATUS" == 1 ]] || fail '--now did not fail for a failed item'
now nope
[[ "$STATUS" == 1 ]] || fail '--now accepted an unknown item'
expect_text "$ERR" "unknown item 'nope'"

# An exit with the item's person-status row (awesome-skills' 3: an
# interrupted update it cannot undo alone) is worded as one that waits for a
# person, in the run and in every later session; the same exit from an item
# without that row is an ordinary failure.
new_home
FAKE_SKILLS_STATUS=3 now skills
[[ "$STATUS" == 1 ]] || fail '--now did not fail for an exit that waits for a person'
expect_text "$ERR" '[dotfiles] [error] skills: stopped for a person (exit 3): do what its message says, then run sync-payloads skills'
[[ -s "$STATE/skills.failed" && ! -e "$STATE/skills.stamp" ]] || fail 'exit 3 was not recorded'
FAKE_KIT_STATUS=3 now kit
expect_text "$ERR" '[dotfiles] [error] kit: install failed (exit 3); retry with: sync-payloads kit'
source_hook bash DOTFILES_PAYLOAD_ITEMS='skills kit'
expect_text "$ERR" "[dotfiles] [warn] skills: its last run stopped for a person (exit 3, see $STATE/skills.failed); run sync-payloads skills and do what it asks"
expect_text "$ERR" "[dotfiles] [warn] kit: its last run failed (exit 3, see $STATE/kit.failed); run sync-payloads kit"
now skills
[[ "$STATUS" == 0 && -e "$STATE/skills.stamp" && ! -e "$STATE/skills.failed" ]] || fail 'a success kept the failure record'

# A legacy link the retired coding-agent-kit Stow package made at a kit
# path: until stow-all removes it, the kit's installer would refuse it, so
# the hook says to run stow-all instead of calling it, and records nothing.
# PyMOL's installer replaces its own old links, so it still runs.
new_home
mkdir -p "$HOME_DIR/.local/bin"
ln -s ../../dotfiles/common/coding-agent-kit/.local/bin/codex-as "$HOME_DIR/.local/bin/codex-as"
source_hook bash DOTFILES_PAYLOAD_ITEMS='kit pymol'
expect_events 'pymol-install []'
expect_text "$ERR" "[dotfiles] [warn] kit: ~/.local/bin/codex-as is still a link the retired Stow package made, which its installer refuses; run $FIXTURE/stow-all.sh with this host first (the next login's automatic stow does), then sync-payloads kit"
[[ ! -e "$STATE/kit.failed" ]] || fail 'a refusal for stow-all was recorded as a failure'
now kit
[[ "$STATUS" == 1 ]] || fail '--now ran the kit past a legacy link'
expect_events 'pymol-install []'
rm "$HOME_DIR/.local/bin/codex-as"
ln -s "$HOME_DIR/elsewhere/codex-as" "$HOME_DIR/.local/bin/codex-as"
now kit
expect_events 'pymol-install []
kit-install [--channel 0.6] stdin=[]'

# AWESOME_SKILLS_AUTO_UPDATE=0, the old hook's opt-out, still leaves skills
# out of the automatic runs, with one notice, until 2027-01-31; a manual
# run and a selection without skills ignore it.
new_home
source_hook bash AWESOME_SKILLS_AUTO_UPDATE=0
expect_events 'kit-install [--channel 0.6] stdin=[]
pymol-install []'
expect_text "$ERR" '[dotfiles] [warn] AWESOME_SKILLS_AUTO_UPDATE=0 leaves skills out until 2027-01-31, when it stops working; set DOTFILES_PAYLOAD_ITEMS="kit pymol" instead'
source_hook bash AWESOME_SKILLS_AUTO_UPDATE=0 DOTFILES_PAYLOAD_ITEMS='kit pymol'
if grep -q AWESOME_SKILLS_AUTO_UPDATE "$ERR"; then fail 'the notice came without skills selected'; fi
: >"$EVENTS"
AWESOME_SKILLS_AUTO_UPDATE=0 now skills
expect_events 'skills-install [] bash=yes'

# A download that stalls (a 127.0.0.1 port that accepts and never answers)
# ends within DOTFILES_PAYLOAD_TIMEOUT, and the run tries no other download,
# so a login waits once; the next session backs off without a download.
python3 -I -c 'import socket, time
s = socket.socket()
s.bind(("127.0.0.1", 0))
s.listen(16)
print(s.getsockname()[1], flush=True)
time.sleep(300)' >"$TEST_TMP/port" &
STALL=$!
wait_for test -s "$TEST_TMP/port"
STALLED=$TEST_TMP/stalled
cp -R "$FIXTURE" "$STALLED"
sed "s#file://$REMOTE/#http://127.0.0.1:$(cat "$TEST_TMP/port")/#g" "$FIXTURE/config/payloads.tsv" >"$STALLED/config/payloads.tsv"
new_home
started=$(date +%s)
source_hook bash DOTFILES_DIR="$STALLED" DOTFILES_PAYLOAD_TIMEOUT=3
elapsed=$(($(date +%s) - started))
[[ "$elapsed" -lt 7 ]] || fail "a stalled download held the shell for ${elapsed}s"
expect_text "$ERR" "cannot download http://127.0.0.1:$(cat "$TEST_TMP/port")/coding-agent-kit/main/install.sh (within 3s)"
expect_text "$ERR" "skipped http://127.0.0.1:$(cat "$TEST_TMP/port")/PyMOLScripts/main/install.sh: a download already failed in this run"
[[ "$(grep -c '^curl$' "$EVENTS")" == 1 ]] || fail 'the run tried a second download'
for item in kit pymol skills; do
    [[ -e "$STATE/$item.failed" ]] || fail "no failure record for $item"
done
: >"$EVENTS"
source_hook bash DOTFILES_DIR="$STALLED" DOTFILES_PAYLOAD_TIMEOUT=3
[[ ! -s "$EVENTS" && ! -e "$STATE/payload.log" ]] || fail 'the next session did not back off'
kill "$STALL"
wait "$STALL" 2>/dev/null || :
STALL=

# A download that fails runs nothing and leaves no temporary file.
new_home
mv "$REMOTE/PyMOLScripts/main/install.sh" "$TEST_TMP/pymol-install.sh"
now pymol
mv "$TEST_TMP/pymol-install.sh" "$REMOTE/PyMOLScripts/main/install.sh"
[[ "$STATUS" == 1 ]] || fail 'a failed download succeeded'
expect_text "$ERR" "cannot download file://$REMOTE/PyMOLScripts/main/install.sh"
expect_events ''
[[ -z "$(find "$TEST_TMP" -maxdepth 1 -name 'dotfiles-payload.*')" ]] || fail 'a failed download was left behind'
# Without curl, wget is tried; without either, the item fails with a message.
mkdir "$TEST_TMP/bare"
for tool in sh bash date mkdir mktemp mv rm cat dirname; do
    ln -s "$(command -v "$tool")" "$TEST_TMP/bare/$tool"
done
STATUS=0
env HOME="$HOME_DIR" PATH="$TEST_TMP/bare" EVENTS="$EVENTS" TMPDIR="$TEST_TMP" \
    "$TEST_TMP/bare/sh" "$FIXTURE/scripts/payload-update.sh" --now pymol >"$OUT" 2>"$ERR" || STATUS=$?
[[ "$STATUS" == 1 ]] || fail 'a run without curl or wget succeeded'
expect_text "$ERR" 'neither curl nor wget is installed'

# The aliases run the manual mode; sync-skills is sync-payloads skills.
new_home
in_env bash --noprofile --norc -c 'shopt -s expand_aliases; . "$1"
sync-skills
sync-payloads pymol' _ "$REPO_ROOT/common/sh/.aliases" >"$OUT" 2>"$ERR" || fail 'the aliases failed'
expect_events 'skills-install [] bash=yes
pymol-install []'

# The rc files source the hook; ~/.profile does for bash (zsh sources it from
# the .zshrc tail, after fpath has the kit's completion directory). The
# transition shim at the old hook's path, which rc files read before the pull
# source, runs it too.
new_home
in_env bash --noprofile --norc -i -c '. "$1"' _ "$REPO_ROOT/common/sh/.profile" >"$OUT" 2>"$ERR" ||
    fail 'common/sh/.profile failed'
expect_events 'kit-install [--channel 0.6] stdin=[]
pymol-install []
skills-install [] bash=yes'
new_home
in_env bash --noprofile --norc -i -c '. "$DOTFILES_DIR/scripts/awesome-skills-update.sh"' >"$OUT" 2>"$ERR" ||
    fail 'the transition shim failed'
expect_events 'kit-install [--channel 0.6] stdin=[]
pymol-install []
skills-install [] bash=yes'
ZSHRC=$REPO_ROOT/common/zsh/.zshrc
grep -Fq '_df_payload="${DOTFILES_DIR:-$HOME/dotfiles}/scripts/payload-update.sh"' "$ZSHRC" ||
    fail '.zshrc does not source scripts/payload-update.sh'
fpath_line=$(grep -n '^fpath+=$HOME/.local/share/zsh/site-functions$' "$ZSHRC" | cut -d: -f1)
omz_line=$(grep -n '^source $ZSH/oh-my-zsh.sh$' "$ZSHRC" | cut -d: -f1)
[[ -n "$fpath_line" && -n "$omz_line" && "$fpath_line" -lt "$omz_line" ]] ||
    fail ".zshrc must put ~/.local/share/zsh/site-functions on fpath before oh-my-zsh's compinit"

# The PowerShell twin, where pwsh is installed (native Windows runs it from
# tests/run.ps1).
if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -NonInteractive -File "$REPO_ROOT/tests/payload-update.ps1"
else
    printf 'SKIP: PowerShell payload hook suite (pwsh unavailable).\n'
fi

printf 'payload-update=PASS\n'
