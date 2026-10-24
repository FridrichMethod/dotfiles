#!/bin/sh
# Keep the payload repos (coding-agent-kit, PyMOLScripts, awesome-skills)
# installed and current through the install and update commands of
# config/payloads.tsv; each repo owns its installation and locking, this hook
# only decides when to call it (docs/payloads.md has the whole contract).
#
# Sourced from the interactive rc files, once per session it runs
# `sh scripts/payload-update.sh --auto`: an absent item installs in the
# foreground; a refresh whose days row has passed, and any retry six hours
# after a failure (ITEM.failed, reported by every later session and the
# doctor), runs in one detached background run (--worker) into payload.log.
# `--now [ITEM...]` (the sync-payloads alias) runs items in the foreground
# whatever their state and exits 1 when one failed. Knobs:
# DOTFILES_PAYLOAD_AUTO_UPDATE=0 (no automatic runs), DOTFILES_PAYLOAD_ITEMS
# (default: kit pymol skills), DOTFILES_PAYLOAD_TIMEOUT (seconds per
# download, default 60), DOTFILES_DIR; AWESOME_SKILLS_AUTO_UPDATE=0 leaves
# skills out of the automatic runs until 2027-01-31.

case ${1-} in
    --auto | --now | --worker) ;;
    *)
        # Sourced from an interactive rc file.
        case $- in
            *i*) ;;
            *) return 0 2>/dev/null || exit 0 ;;
        esac
        if [ -z "${_DOTFILES_PAYLOAD_CHECKED-}" ]; then
            _DOTFILES_PAYLOAD_CHECKED=1
            export _DOTFILES_PAYLOAD_CHECKED
            if [ "${DOTFILES_PAYLOAD_AUTO_UPDATE:-1}" != 0 ]; then
                sh "${DOTFILES_DIR:-$HOME/dotfiles}/scripts/payload-update.sh" --auto || :
            fi
        fi
        return 0 2>/dev/null || exit 0
        ;;
esac

set -fu
mode=$1
shift
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
if [ -r "$repo/lib/terminal.sh" ]; then
    # shellcheck source=lib/terminal.sh
    . "$repo/lib/terminal.sh"
else
    dotfiles_log() { printf '[dotfiles] [%s] %s\n' "$1" "$2" >&2; }
fi
# fail MESSAGE: --now exits 1; an automatic run never fails the shell.
fail() {
    dotfiles_log error "$1"
    [ "$mode" != --auto ] || exit 0
    exit 1
}
case ${HOME-} in
    /*) ;;
    *) fail 'payload-update: HOME must be an absolute path.' ;;
esac
config=$repo/config/payloads.tsv
[ -r "$config" ] || fail "payload-update: missing $config."
state=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/payload
(umask 077 && mkdir -p "$state") || fail "payload-update: cannot create $state."
tab=$(printf '\t')
timeout=${DOTFILES_PAYLOAD_TIMEOUT:-60}
case $timeout in
    '' | 0 | *[!0-9]*) timeout=60 ;;
esac
connect=10
[ "$timeout" -ge 10 ] || connect=$timeout

# field ITEM FIELD: set value to config's ITEM<TAB>FIELD row; 1 without one.
field() {
    while IFS= read -r line || [ -n "$line" ]; do
        case $line in
            "$1$tab$2$tab"*)
                value=${line#"$1$tab$2$tab"}
                return 0
                ;;
        esac
    done <"$config"
    value=
    return 1
}

# payload_script INTERPRETER SOURCE [ARG...]: run SOURCE with ARG, stdin
# closed, and return its status. A URL is first downloaded into a temporary
# file, within the timeout; after one failed download a run tries no other.
download='' offline=''
trap '[ -z "$download" ] || rm -f "$download"' 0
trap 'exit 1' HUP INT TERM
payload_script() {
    interpreter=$1 source=$2
    shift 2
    if ! command -v "$interpreter" >/dev/null 2>&1; then
        dotfiles_log error "$interpreter is not installed; it runs $source"
        return 1
    fi
    case $source in
        *://*)
            if [ -n "$offline" ]; then
                dotfiles_log error "skipped $source: a download already failed in this run"
                return 1
            fi
            offline=1
            download=$(mktemp "${TMPDIR:-/tmp}/dotfiles-payload.XXXXXX") || return 1
            if command -v curl >/dev/null 2>&1; then
                curl -fsSL --connect-timeout "$connect" --max-time "$timeout" -o "$download" -- "$source" && offline=
            elif command -v wget >/dev/null 2>&1; then
                wget -q -T "$timeout" -t 1 -O "$download" -- "$source" && offline=
            else
                dotfiles_log error "neither curl nor wget is installed; cannot download $source"
                return 1
            fi
            if [ -n "$offline" ] || [ ! -s "$download" ]; then
                dotfiles_log error "cannot download $source (within ${timeout}s)"
                return 1
            fi
            set -- "$download" "$@"
            ;;
        *)
            if [ ! -f "$source" ]; then
                dotfiles_log error "$source is missing"
                return 1
            fi
            set -- "$source" "$@"
            ;;
    esac
    script_status=0
    "$interpreter" "$@" </dev/null || script_status=$?
    [ -z "$download" ] || rm -f "$download"
    download=
    return "$script_status"
}

# installed ITEM: its unix-probe row succeeds.
installed() {
    field "$1" unix-probe || return 1
    (eval "$value") >/dev/null 2>&1
}

# stowed ITEM: a path of its stow-links row (PACKAGE PATH...) is still a link
# into the retired common/PACKAGE, which the repo's installer refuses; sets
# value to that path.
stowed() {
    field "$1" stow-links || return 1
    # shellcheck disable=SC2086 # a word list; set -f keeps it from globbing
    set -- $value
    package=$1
    shift
    for path; do
        case $(readlink "$HOME/$path" 2>/dev/null) in
            *"common/$package/"*)
                value=$path
                return 0
                ;;
        esac
    done
    return 1
}

# record FILE: set last and code to the time and status FILE starts with.
record() {
    last='' code=''
    IFS=' ' read -r last code _ 2>/dev/null <"$1" || :
    case $last in
        '' | *[!0-9]*) return 1 ;;
    esac
}

# run ITEM: install ITEM when absent, else update it; stamp a success and
# record a failure. Sets status to the command's exit status and returns it.
run() {
    status=1
    if stowed "$1"; then
        dotfiles_log warn "$1: ~/$value is still a link the retired Stow package made, which its installer refuses; run $repo/stow-all.sh with this host first (the next login's automatic stow does), then sync-payloads $1"
        return 1
    fi
    action=update doing=updating
    installed "$1" || action=install doing='installing (later updates run in the background)'
    field kit channel
    # shellcheck disable=SC2034 # for the evaluated command
    channel=$value
    field "$1" person-status
    person=$value
    if ! field "$1" "unix-$action" && ! field "$1" unix-install; then
        dotfiles_log error "$1: config/payloads.tsv has no unix-install row"
        return 1
    fi
    dotfiles_log step "$1: $doing"
    start=0 status=0
    [ "$mode" != --worker ] || start=$(wc -l <"$state/payload.log")
    eval "$value" || status=$?
    case $status in
        0)
            if (umask 077 && date +%s >"$state/$1.stamp.tmp" && mv -f "$state/$1.stamp.tmp" "$state/$1.stamp" &&
                rm -f "$state/$1.failed"); then
                dotfiles_log ok "$1: $action done"
            else
                dotfiles_log error "$1: cannot record the success in $state"
                status=1
            fi
            return "$status"
            ;;
        75)
            dotfiles_log info "$1: another run holds its lock; the next session tries again"
            return 75
            ;;
        "$person") dotfiles_log error "$1: stopped for a person (exit $status): do what its message says, then run sync-payloads $1" ;;
        *) dotfiles_log error "$1: $action failed (exit $status); retry with: sync-payloads $1" ;;
    esac
    (
        umask 077
        date +"%s $status" >"$state/$1.failed"
        [ "$mode" != --worker ] || tail -n "+$((start + 1))" "$state/payload.log" | tail -n 20 >>"$state/$1.failed"
    ) || dotfiles_log error "$1: cannot record the failure in $state"
    return "$status"
}

if [ "$#" -eq 0 ]; then
    # shellcheck disable=SC2086 # a word list; set -f keeps it from globbing
    set -- ${DOTFILES_PAYLOAD_ITEMS-kit pymol skills}
fi
for item in "$@"; do
    field "$item" days ||
        fail "payload-update: unknown item '$item'; config/payloads.tsv names kit, pymol and skills."
done

if [ "$mode" != --auto ]; then
    failed=0
    for item in "$@"; do
        run "$item" || [ "$status" = 75 ] || failed=1
    done
    exit "$failed"
fi

# --auto: a first install now; a due refresh, and any retry six hours after
# a failure, in one detached background run.
case "${AWESOME_SKILLS_AUTO_UPDATE-} $* " in
    "0 "*" skills "*)
        dotfiles_log warn 'AWESOME_SKILLS_AUTO_UPDATE=0 leaves skills out until 2027-01-31, when it stops working; set DOTFILES_PAYLOAD_ITEMS="kit pymol" instead'
        # shellcheck disable=SC2046 # a word list; set -f keeps it from globbing
        set -- $(for item in "$@"; do [ "$item" = skills ] || printf '%s\n' "$item"; done)
        ;;
esac
now=$(date +%s)
later=
for item in "$@"; do
    if record "$state/$item.failed"; then
        field "$item" person-status
        what=failed hint=
        [ "$code" != "$value" ] || what='stopped for a person' hint=' and do what it asks'
        dotfiles_log warn "$item: its last run $what (exit $code, see $state/$item.failed); run sync-payloads $item$hint"
        [ $((now - last)) -lt 21600 ] || later="$later $item"
    elif ! installed "$item"; then
        run "$item" || :
    else
        field "$item" days
        case $value in
            '' | *[!0-9]*) value=1 ;;
        esac
        if ! record "$state/$item.stamp" || [ $((now - last)) -ge $((value * 86400)) ]; then
            later="$later $item"
        fi
    fi
done
[ -n "$later" ] || exit 0
# Started from here, the run never enters the shell's job table.
# shellcheck disable=SC2086 # a word list
sh "$repo/scripts/payload-update.sh" --worker $later </dev/null >"$state/payload.log" 2>&1 &
exit 0
