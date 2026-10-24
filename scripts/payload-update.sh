#!/bin/sh
# Keep the first-party payload repos (coding-agent-kit, PyMOLScripts,
# awesome-skills) installed and current through each repo's own documented
# install and update command, which config/payloads.tsv names. Each repo owns
# its installation, update, selection and locking; this hook only decides
# when to call it (docs/payloads.md).
#
# Sourced at the tail of common/zsh/.zshrc and, for bash and sh, of
# common/sh/.profile: in an interactive shell, once per session, it runs
# itself as `sh scripts/payload-update.sh --auto`, so its logic never depends
# on the calling shell's dialect or options. An automatic run installs an
# absent item in the foreground, so a person sees the first install, and
# refreshes the installed ones in one detached background run once an item's
# refresh interval (its days row) has passed since its last success. A failed
# or interrupted run records nothing, so the next session tries again.
#
#   sh scripts/payload-update.sh --now [ITEM...]
# runs the given items (default: those of DOTFILES_PAYLOAD_ITEMS) in the
# foreground whatever their intervals, and exits 1 when one failed; the
# sync-payloads and sync-skills aliases call it.
#
# Knobs:
#   DOTFILES_PAYLOAD_AUTO_UPDATE  0 disables the automatic runs (not --now)
#   DOTFILES_PAYLOAD_ITEMS        the items it manages (default: kit pymol
#                                 skills; empty manages none)
#   DOTFILES_DIR                  the checkout the rc files source this from
#                                 (default: ~/dotfiles)
# State, in ${XDG_STATE_HOME:-~/.local/state}/dotfiles/payload/: one stamp per
# item (the time of its last success), worker.pid (the background run, which
# keeps a second one from starting while it lives, for a day at most) and
# payload.log (the
# output of the last background run). The repos' installers lock themselves
# and exit 75 while another run holds the lock; that is neither a success
# nor a failure here.

case ${1-} in
    --auto | --now) ;;
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
self=$repo/scripts/payload-update.sh
if [ -r "$repo/lib/terminal.sh" ]; then
    # shellcheck source=lib/terminal.sh
    . "$repo/lib/terminal.sh"
else
    dotfiles_log() {
        case $1 in
            warn | error) printf '[dotfiles] [%s] %s\n' "$1" "$2" >&2 ;;
            *) printf '[dotfiles] [%s] %s\n' "$1" "$2" ;;
        esac
    }
fi

# fail MESSAGE: an automatic run never fails the shell; --now exits 1.
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
tab=$(printf '\t')

# field ITEM FIELD: set value to the value of config's ITEM<TAB>FIELD row;
# 1 when there is none.
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

# payload_script INTERPRETER SOURCE [ARG...]: run SOURCE with INTERPRETER and
# ARG, stdin closed, and return its status. A URL is downloaded into a
# temporary file first, never piped into the interpreter, so a broken
# download runs nothing.
download=
trap '[ -z "$download" ] || rm -f "$download"' 0
trap 'exit 1' HUP INT TERM
payload_script() {
    interpreter=$1
    source=$2
    shift 2
    if ! command -v "$interpreter" >/dev/null 2>&1; then
        dotfiles_log error "$interpreter is not installed; it runs $source"
        return 1
    fi
    case $source in
        *://*)
            download=$(mktemp "${TMPDIR:-/tmp}/dotfiles-payload.XXXXXX") || return 1
            if command -v curl >/dev/null 2>&1; then
                fetched=curl
                curl -fsSL -o "$download" -- "$source" || fetched=
            elif command -v wget >/dev/null 2>&1; then
                fetched=wget
                wget -q -O "$download" -- "$source" || fetched=
            else
                dotfiles_log error "neither curl nor wget is installed; cannot download $source"
                return 1
            fi
            if [ -z "$fetched" ] || [ ! -s "$download" ]; then
                dotfiles_log error "cannot download $source"
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

# run ITEM: install ITEM when absent, else update it, and stamp a success.
# Sets status to the command's exit status and returns it.
run() {
    action=update
    installed "$1" || action=install
    field kit channel
    # shellcheck disable=SC2034 # for the evaluated command
    channel=$value
    status=1
    if ! field "$1" "unix-$action" && ! field "$1" unix-install; then
        dotfiles_log error "$1: config/payloads.tsv has no unix-install row"
        return 1
    fi
    if [ "$action" = install ]; then
        dotfiles_log step "$1: installing (later updates run in the background)"
    else
        dotfiles_log step "$1: updating"
    fi
    status=0
    eval "$value" || status=$?
    case $status in
        0)
            if (umask 077 && mkdir -p "$state" && date +%s >"$state/$1.stamp.tmp" &&
                mv -f "$state/$1.stamp.tmp" "$state/$1.stamp"); then
                dotfiles_log ok "$1: ${action} done"
            else
                dotfiles_log error "$1: cannot record the success in $state"
                status=1
            fi
            ;;
        75) dotfiles_log info "$1: another run holds its lock; the next session tries again" ;;
        *) dotfiles_log error "$1: $action failed (exit $status); retry with: sync-payloads $1" ;;
    esac
    return "$status"
}

# due ITEM: its last success is at least its days row old (or unrecorded).
due() {
    field "$1" days
    days=$value
    case $days in
        '' | *[!0-9]*) days=1 ;;
    esac
    last=
    IFS= read -r last 2>/dev/null <"$state/$1.stamp" || :
    case $last in
        '' | *[!0-9]*) return 0 ;;
    esac
    [ $((now - last)) -ge $((days * 86400)) ]
}

if [ "$#" -eq 0 ]; then
    # shellcheck disable=SC2086 # a word list; set -f keeps it from globbing
    set -- ${DOTFILES_PAYLOAD_ITEMS-kit pymol skills}
fi
for item in "$@"; do
    field "$item" days ||
        fail "payload-update: unknown item '$item'; config/payloads.tsv names kit, pymol and skills."
done

if [ "$mode" = --now ]; then
    failed=0
    for item in "$@"; do
        run "$item" || [ "$status" = 75 ] || failed=1
    done
    exit "$failed"
fi

# --auto: first installs now, refreshes in one detached background run.
now=$(date +%s)
later=
for item in "$@"; do
    if ! installed "$item"; then
        run "$item" || :
    elif due "$item"; then
        later="$later $item"
    fi
done
[ -n "$later" ] || exit 0
(umask 077 && mkdir -p "$state") || exit 0
# worker.pid: the PID of the last background run and when it started. A
# live one younger than a day blocks a new run; an older one is a reused PID.
pid='' started=''
IFS=' ' read -r pid started 2>/dev/null <"$state/worker.pid" || :
case $pid in
    '' | *[!0-9]*) ;;
    *)
        case $started in
            '' | *[!0-9]*) started=$now ;;
        esac
        if [ $((now - started)) -lt 86400 ] && kill -0 "$pid" 2>/dev/null; then
            exit 0
        fi
        ;;
esac
# The run outlives this process and the shell that started it; started from
# here, it never enters that shell's job table.
# shellcheck disable=SC2086 # a word list
sh "$self" --now $later </dev/null >"$state/payload.log" 2>&1 &
printf '%s %s\n' "$!" "$now" >"$state/worker.pid"
exit 0
