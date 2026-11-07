#!/bin/bash

set -euo pipefail

# Isolate inherited configuration while preserving explicit test inputs.
# shellcheck source=tests/lib/environment.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/environment.sh"

# Keep fixture Git independent of a commit hook's repository and index.
dotfiles_test_clear_git_environment

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
    for file in "${OUT-}" "${ERR-}" "${EVENTS-}"; do
        [[ -z "$file" || ! -f "$file" ]] || {
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
cp "$REPO_ROOT/scripts/payload-update.sh" "$FIXTURE/scripts/"
# The guard and .chezmoiroot make the fixture a source a home can be bound to.
cp "$REPO_ROOT/lib/terminal.sh" "$REPO_ROOT/lib/chezmoi-guard.sh" "$FIXTURE/lib/"
printf 'home\n' >"$FIXTURE/.chezmoiroot"
sed "s#https://raw.githubusercontent.com/FridrichMethod/#file://$REMOTE/#g" \
    "$REPO_ROOT/config/payloads.tsv" >"$FIXTURE/config/payloads.tsv"
grep -q "file://$REMOTE/coding-agent-kit/main/install.sh" "$FIXTURE/config/payloads.tsv" ||
    fail 'config/payloads.tsv no longer downloads the kit from raw.githubusercontent.com/FridrichMethod'
if grep -q 'https\?://' "$FIXTURE/config/payloads.tsv"; then
    fail 'config/payloads.tsv names a URL outside raw.githubusercontent.com/FridrichMethod'
fi
# Every field of config/payloads.tsv is one the hooks read.
unknown_fields=$(awk -F '\t' '!/^#/ && NF && $2 !~ /^(channel|(unix|windows)-(probe|install|update)|person-status)$/ { print NR ": " $1 " " $2 }' \
    "$REPO_ROOT/config/payloads.tsv")
[[ -z "$unknown_fields" ]] || fail "config/payloads.tsv has a field no hook reads: $unknown_fields"

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
# record-cwd NAME: a fake's working directory in EVENTS.NAME-cwd and, with
# PROBE_GIT set, in EVENTS.NAME-git the repository git discovers from there
# (empty when none), as the real installers' repository-less git calls would.
cat >"$TEST_TMP/bin/record-cwd" <<'SH'
#!/bin/sh
pwd -P >"$EVENTS.$1-cwd"
[ -n "${PROBE_GIT-}" ] || exit 0
unset GIT_DIR GIT_WORK_TREE GIT_CEILING_DIRECTORIES
git rev-parse --absolute-git-dir >"$EVENTS.$1-git" 2>/dev/null || :
SH
# The kit's bootstrap installs a managed root whose current/install.sh is the
# update command, and the three Claude helpers. Every fake records its
# working directory with record-cwd.
cat >"$REMOTE/coding-agent-kit/main/install.sh" <<'SH'
#!/bin/sh
printf 'kit-install [%s] stdin=[%s]\n' "$*" "$(cat)" >>"$EVENTS"
record-cwd kit
[ "${FAKE_KIT_STATUS:-0}" = 0 ] || exit "$FAKE_KIT_STATUS"
root=${XDG_DATA_HOME:-$HOME/.local/share}/coding-agent-kit
mkdir -p "$root/current" "$HOME/.claude/coding-agent-kit"
printf '%s\n' '#!/bin/sh' 'printf "kit-update [%s]\n" "$*" >>"$EVENTS"' 'record-cwd kit' \
    'echo "kit-update: fake output" >&2' 'exit "${FAKE_KIT_STATUS:-0}"' >"$root/current/install.sh"
for helper in statusline notify check-git-hooks; do
    : >"$HOME/.claude/coding-agent-kit/$helper.cjs"
done
SH
# PyMOLScripts' and awesome-skills' installers read a configs/ or scripts/
# directory beside themselves as a checkout's, so their fakes record the
# directory they run from: its path, mode and entries. FAKE_PYMOL_DELAY makes
# PyMOL's take that many seconds before it marks itself finished.
cat >"$REMOTE/PyMOLScripts/main/install.sh" <<'SH'
#!/bin/sh
printf 'pymol-install [%s]\n' "$*" >>"$EVENTS"
here=$(dirname -- "$0")
printf '%s\n%s\n%s\n' "$here" "$(ls -ld -- "$here" | cut -c1-10)" "$(ls -A -- "$here")" >"$EVENTS.pymol-dir"
record-cwd pymol
if [ -n "${FAKE_PYMOL_DELAY-}" ]; then
    sleep "$FAKE_PYMOL_DELAY"
    : >"$EVENTS.pymol-finished"
fi
[ "${FAKE_PYMOL_STATUS:-0}" = 0 ] || exit "$FAKE_PYMOL_STATUS"
: >"$HOME/.pymolrc"
: >"$HOME/.pymolrc.py"
SH
cat >"$REMOTE/awesome-skills/main/install.sh" <<'SH'
#!/bin/bash
printf 'skills-install [%s] bash=%s\n' "$*" "${BASH_VERSION:+yes}" >>"$EVENTS"
here=$(dirname -- "$0")
printf '%s\n%s\n%s\n' "$here" "$(ls -ld -- "$here" | cut -c1-10)" "$(ls -A -- "$here")" >"$EVENTS.skills-dir"
record-cwd skills
[ "${FAKE_SKILLS_STATUS:-0}" = 0 ] || exit "$FAKE_SKILLS_STATUS"
mkdir -p "$HOME/.local/share/awesome-skills"
printf '{}\n' >"$HOME/.local/share/awesome-skills/claude.json"
SH
chmod +x "$TEST_TMP/bin/curl" "$TEST_TMP/bin/record-cwd"

CASE=0
# new_home: a fresh HOME and event log for the next case.
new_home() {
    CASE=$((CASE + 1))
    HOME_DIR=$TEST_TMP/home$CASE
    EVENTS=$TEST_TMP/events$CASE
    OUT=$TEST_TMP/out$CASE
    ERR=$TEST_TMP/err$CASE
    mkdir -p "$HOME_DIR"
    : >"$EVENTS"
}

# in_env COMMAND...: COMMAND in the case's home, with the fakes and only the
# system tools on PATH.
in_env() {
    env HOME="$HOME_DIR" PATH="$TEST_TMP/bin:/usr/bin:/bin" EVENTS="$EVENTS" \
        REAL_CURL="$REAL_CURL" TMPDIR="$TEST_TMP" "$@"
}

# [VAR=VALUE...] now ITEM...: run the hook as sync-payloads does; sets STATUS.
now() {
    STATUS=0
    in_env sh "$FIXTURE/scripts/payload-update.sh" --now "$@" >"$OUT" 2>"$ERR" || STATUS=$?
}

expect_events() {
    [[ "$(grep -v '^curl$' "$EVENTS" || :)" == "$1" ]] || fail "expected events: $1"
}
expect_text() {
    grep -Fq -- "$2" "$1" || fail "${1##*/} lacks: $2"
}
expect_line() {
    grep -Fxq -- "$2" "$1" || fail "${1##*/} lacks the line: $2"
}
# expect_no_state: no run wrote payload state of its own into the case's
# home.
expect_no_state() {
    [[ ! -e "$HOME_DIR/.local/state" ]] || fail "$1 created $HOME_DIR/.local/state"
}
# wait_for COMMAND...: COMMAND succeeds within ten seconds.
wait_for() {
    local attempt
    for ((attempt = 0; attempt < 200; attempt++)); do
        "$@" 2>/dev/null && return 0
        sleep 0.05
    done
    fail "timed out waiting for: $*"
}

USAGE='dotfiles: usage: sh scripts/payload-update.sh --now [ITEM...]'

# Nothing installs a payload repo unless a person runs it. Any call without
# --now first, a bare item or an unknown argument, is a usage error: one line
# on stderr and exit 2 before anything else, under maintenance too, with no
# event and no state.
new_home
mkdir -p "$HOME_DIR/.config/dotfiles"
for maintenance in '' 1; do
    [[ -z "$maintenance" ]] || : >"$HOME_DIR/.config/dotfiles/maintenance"
    for mode in '' kit '--help' '--bogus --now kit' 'kit --now'; do
        STATUS=0
        # shellcheck disable=SC2086 # the mode's words
        in_env sh "$FIXTURE/scripts/payload-update.sh" $mode >"$OUT" 2>"$ERR" || STATUS=$?
        [[ "$STATUS" == 2 && ! -s "$OUT" && "$(cat "$ERR")" == "$USAGE" ]] ||
            fail "a call with [$mode]${maintenance:+ under maintenance} was not a usage error (exit $STATUS)"
    done
done
rm "$HOME_DIR/.config/dotfiles/maintenance"
expect_events ''
expect_no_state 'a call without --now'

# A login runs none either: it only dispatches the update.
in_env bash --noprofile --norc -i -c '. "$1"' _ "$REPO_ROOT/home/dot_profile" >"$OUT" 2>"$ERR" ||
    fail 'home/dot_profile failed'
expect_events ''
expect_no_state 'a login'

# --now installs the default items in config order, the kit on the declared
# channel, stdin closed; an installed item runs its update command (the
# kit's installed current/install.sh --update, the others' install command).
# It keeps no state of its own.
new_home
now
[[ "$STATUS" == 0 ]] || fail '--now failed'
expect_events "kit-install [--channel 0.7] stdin=[]
pymol-install []
skills-install [] bash=yes"
expect_line "$OUT" '[dotfiles] [step] kit: installing'
expect_line "$OUT" '[dotfiles] [ok] skills: install done'
[[ -z "$(find "$TEST_TMP" -maxdepth 1 -name 'dotfiles-payload.*')" ]] || fail 'a download was left behind'
: >"$EVENTS"
now
expect_events 'kit-update [--update --channel 0.7]
pymol-install []
skills-install [] bash=yes'
expect_line "$OUT" '[dotfiles] [step] kit: updating'
expect_line "$OUT" '[dotfiles] [ok] kit: update done'
expect_no_state '--now'

# --now never detaches: every installer runs in the foreground, so the run
# returns only once its installer has finished. Together with the login
# above, no payload process outlives a session (Sherlock's site rule).
new_home
FAKE_PYMOL_DELAY=1 now pymol
[[ "$STATUS" == 0 && -e "$EVENTS.pymol-finished" ]] || fail '--now returned before its installer finished'

# DOTFILES_PAYLOAD_ITEMS selects the default items; empty selects none; an
# unknown item fails before anything runs.
new_home
DOTFILES_PAYLOAD_ITEMS='skills kit' now
expect_events 'skills-install [] bash=yes
kit-install [--channel 0.7] stdin=[]'
: >"$EVENTS"
DOTFILES_PAYLOAD_ITEMS='' now
[[ "$STATUS" == 0 ]] || fail 'an empty selection failed'
expect_events ''
DOTFILES_PAYLOAD_ITEMS='kit nope' now
[[ "$STATUS" == 1 ]] || fail 'an unknown item in the selection was accepted'
now nope
[[ "$STATUS" == 1 ]] || fail '--now accepted an unknown item'
expect_text "$ERR" "unknown item 'nope'"
expect_events ''

# A failed install says how to retry and fails the run, and the other items
# still run; nothing is recorded. Exit 75 (another run holds the repo's
# lock) is no failure. An exit with the item's person-status row
# (awesome-skills' 3: an interrupted update it cannot undo alone;
# PyMOLScripts' 3: a locally edited rc file it will not overwrite) is worded
# as one that waits for a person; the same exit from an item without that
# row is an ordinary failure.
new_home
FAKE_KIT_STATUS=1 now
[[ "$STATUS" == 1 ]] || fail '--now did not fail for a failed item'
expect_events 'kit-install [--channel 0.7] stdin=[]
pymol-install []
skills-install [] bash=yes'
expect_text "$ERR" '[dotfiles] [error] kit: install failed (exit 1); retry with: sync-payloads kit'
FAKE_PYMOL_STATUS=75 now pymol
[[ "$STATUS" == 0 ]] || fail '--now failed on exit 75'
expect_line "$OUT" '[dotfiles] [info] pymol: another run holds its lock; run sync-payloads pymol again once it has finished'
FAKE_SKILLS_STATUS=3 now skills
[[ "$STATUS" == 1 ]] || fail '--now did not fail for an exit that waits for a person'
expect_text "$ERR" '[dotfiles] [error] skills: stopped for a person (exit 3): do what its message says, then run sync-payloads skills'
FAKE_KIT_STATUS=3 now kit
expect_text "$ERR" '[dotfiles] [error] kit: install failed (exit 3); retry with: sync-payloads kit'
FAKE_PYMOL_STATUS=3 now pymol
[[ "$STATUS" == 1 ]] || fail 'a PyMOL exit 3 was not a failure'
expect_text "$ERR" '[dotfiles] [error] pymol: stopped for a person (exit 3): do what its message says, then run sync-payloads pymol'
expect_no_state 'a failed run'

# A download that stalls (a 127.0.0.1 port that accepts and never answers)
# ends within DOTFILES_PAYLOAD_TIMEOUT, and the run tries no other download,
# so a person waits once.
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
STATUS=0
in_env DOTFILES_PAYLOAD_TIMEOUT=3 sh "$STALLED/scripts/payload-update.sh" --now >"$OUT" 2>"$ERR" || STATUS=$?
elapsed=$(($(date +%s) - started))
[[ "$elapsed" -lt 7 ]] || fail "a stalled download held the run for ${elapsed}s"
[[ "$STATUS" == 1 ]] || fail 'a stalled download did not fail the run'
expect_text "$ERR" "cannot download http://127.0.0.1:$(cat "$TEST_TMP/port")/coding-agent-kit/main/install.sh (within 3s)"
expect_text "$ERR" "skipped http://127.0.0.1:$(cat "$TEST_TMP/port")/PyMOLScripts/main/install.sh: a download already failed in this run"
[[ "$(grep -c '^curl$' "$EVENTS")" == 1 ]] || fail 'the run tried a second download'
kill "$STALL"
wait "$STALL" 2>/dev/null || :
STALL=
rm -r "$STALLED"

# A download runs alone in a fresh directory of TMPDIR that only this user can
# enter, removed after the run: what another user planted in a shared TMPDIR
# (a configs/.pymolrc.py, a scripts/install_skills.py) is never beside it.
new_home
mkdir "$TEST_TMP/configs" "$TEST_TMP/scripts"
printf 'planted\n' >"$TEST_TMP/configs/.pymolrc.py"
printf 'planted\n' >"$TEST_TMP/scripts/install_skills.py"
now pymol skills
[[ "$STATUS" == 0 ]] || fail 'the staged installers failed'
for item in pymol skills; do
    { read -r here && read -r mode && entries=$(cat); } <"$EVENTS.$item-dir" || fail "the $item fake left no record"
    case $here in
        "$TEST_TMP"/dotfiles-payload.*) ;;
        *) fail "$item ran from $here, not from a fresh directory of TMPDIR" ;;
    esac
    [[ "$mode" == drwx------ ]] || fail "$item ran from a directory with mode $mode"
    [[ "$entries" == install.sh ]] || fail "$item's directory held more than its script: $entries"
    [[ ! -e "$here" ]] || fail "$item's staging directory was left behind"
done
rm -r "$TEST_TMP/configs" "$TEST_TMP/scripts"
# A failed installer leaves its directory behind neither.
new_home
FAKE_PYMOL_STATUS=1 now pymol
read -r here <"$EVENTS.pymol-dir"
[[ "$STATUS" == 1 && -n "$here" && ! -e "$here" ]] || fail 'a failed installer left its staging directory behind'

# Every installer runs in /, a download as well as an installed script (the
# kit's update), never in the caller's working directory, which may be a
# shared one (a shell started in /tmp) or hold a project's json.py:
# awesome-skills' remote bootstrap runs python3 -c, which imports from its
# working directory first.
new_home
mkdir "$TEST_TMP/caller"
printf 'planted\n' >"$TEST_TMP/caller/json.py"
pushd "$TEST_TMP/caller" >/dev/null
now kit pymol skills
popd >/dev/null
[[ "$STATUS" == 0 ]] || fail 'the installs from a planted working directory failed'
for item in kit pymol skills; do
    read -r cwd <"$EVENTS.$item-cwd" || fail "the $item fake recorded no working directory"
    [[ "$cwd" == / ]] || fail "$item's download ran in $cwd, not in /"
done
pushd "$TEST_TMP/caller" >/dev/null
now kit
popd >/dev/null
[[ "$STATUS" == 0 && "$(cat "$EVENTS.kit-cwd")" == / ]] || fail "the kit's installed update ran in $(cat "$EVENTS.kit-cwd"), not in /"
rm -r "$TEST_TMP/caller"
# Nor in its staging directory: that lies in TMPDIR, where another user can
# create TMPDIR/.git, and git looks for a repository by walking up from its
# working directory, as the kit's installer's git ls-remote outside any
# repository does. The plant has this user as owner here, which stands for a
# host whose safe.directory is * (lab-ubuntu's .gitconfig_local).
if PATH=/usr/bin:/bin git --version >/dev/null 2>&1; then
    new_home
    PATH=/usr/bin:/bin git -c init.defaultBranch=main init -q -- "$TEST_TMP/plant"
    mv "$TEST_TMP/plant/.git" "$TEST_TMP/.git"
    mkdir "$TEST_TMP/plant/probe"
    found=$(cd "$TEST_TMP/plant/probe" && unset GIT_DIR GIT_WORK_TREE GIT_CEILING_DIRECTORIES &&
        PATH=/usr/bin:/bin git rev-parse --absolute-git-dir 2>/dev/null) || :
    [[ -n "$found" && "$found" -ef "$TEST_TMP/.git" ]] ||
        fail "git does not find the planted $TEST_TMP/.git from below it (found [$found]); the check proves nothing"
    PROBE_GIT=1 now kit pymol skills
    [[ "$STATUS" == 0 ]] || fail 'the installs beside a planted TMPDIR/.git failed'
    for item in kit pymol skills; do
        found=$(cat "$EVENTS.$item-git") || fail "the $item fake did not probe git"
        [[ -z "$found" || ! "$found" -ef "$TEST_TMP/.git" ]] ||
            fail "git run by the $item installer found the planted $TEST_TMP/.git from $(cat "$EVENTS.$item-cwd")"
    done
    rm -rf "$TEST_TMP/.git" "$TEST_TMP/plant"
else
    printf 'SKIP: no git in /usr/bin or /bin; the planted TMPDIR/.git case did not run.\n' >&2
fi

# A relative TMPDIR names a directory of the caller's: the download is
# staged there under its absolute path, and the installer still runs in /.
new_home
mkdir -p "$TEST_TMP/caller/tmp"
pushd "$TEST_TMP/caller" >/dev/null
STATUS=0
in_env TMPDIR=tmp sh "$FIXTURE/scripts/payload-update.sh" --now pymol >"$OUT" 2>"$ERR" || STATUS=$?
popd >/dev/null
[[ "$STATUS" == 0 && "$(cat "$EVENTS.pymol-cwd")" == / ]] || fail "a relative TMPDIR run failed or ran in $(cat "$EVENTS.pymol-cwd")"
read -r here <"$EVENTS.pymol-dir"
case $here in
    "$TEST_TMP"/caller/tmp/dotfiles-payload.*) ;;
    *) fail "pymol was staged in $here, not in the caller's relative TMPDIR" ;;
esac
rm -r "$TEST_TMP/caller"

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

# The aliases run the --now mode through the home binding's source;
# sync-skills is sync-payloads skills.
new_home
mkdir -p "$HOME_DIR/.config/dotfiles"
printf 'dotfiles-chezmoi-v1\n%s\n%s\n' "$HOME_DIR" "$FIXTURE" >"$HOME_DIR/.config/dotfiles/native"
in_env bash --noprofile --norc -c 'shopt -s expand_aliases; . "$1"
sync-skills
sync-payloads pymol' _ "$REPO_ROOT/home/dot_aliases" >"$OUT" 2>"$ERR" || fail 'the aliases failed'
expect_events 'skills-install [] bash=yes
pymol-install []'

# The kit's zsh completions: .zshrc puts their directory on fpath before
# oh-my-zsh's compinit.
ZSHRC=$REPO_ROOT/home/dot_zshrc
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

python3 -I -B "$REPO_ROOT/tests/test_payload_download.py"

printf 'payload-update=PASS\n'
