#!/bin/sh
# Install or update the payload repos (coding-agent-kit, PyMOLScripts,
# awesome-skills) now, in the foreground, through the install and update
# commands of config/payloads.tsv; each repo owns its installation, updates
# and locking (docs/payloads.md has the whole contract).
#
# `sh scripts/payload-update.sh --now [ITEM...]`, which sync-payloads runs,
# installs each absent item, updates each installed one and exits 1 when one
# failed. Only a person runs it: no login or schedule does, it starts no
# background run and it keeps no state of its own. Knobs:
# DOTFILES_PAYLOAD_ITEMS (the items without arguments; default: kit pymol
# skills), DOTFILES_PAYLOAD_TIMEOUT (seconds per download, default 60).
#
# Until Stage 6, any other call does nothing and returns 0, setting no
# variable or option: rc files read before the pull that ended automatic
# runs still source this file, directly or through
# scripts/awesome-skills-update.sh, and an older run may still pass the
# retired --auto or --worker.

# Persistent operator maintenance refuses an explicit run too.
if [ -e "$HOME/.config/dotfiles/maintenance" ] || [ -L "$HOME/.config/dotfiles/maintenance" ]; then
    if [ "${1-}" = --now ]; then
        printf '%s\n' 'dotfiles: payload update refused during maintenance.' >&2
        return 1 2>/dev/null || exit 1
    fi
    return 0 2>/dev/null || exit 0
fi
[ "${1-}" = --now ] || return 0 2>/dev/null || exit 0

set -fu
shift
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
if [ -r "$repo/lib/terminal.sh" ]; then
    # shellcheck source=lib/terminal.sh
    . "$repo/lib/terminal.sh"
else
    dotfiles_log() { printf '[dotfiles] [%s] %s\n' "$1" "$2" >&2; }
fi
# fail MESSAGE: one error line, then exit 1.
fail() {
    dotfiles_log error "$1"
    exit 1
}
case ${HOME-} in
    /*) ;;
    *) fail 'payload-update: HOME must be an absolute path.' ;;
esac
config=$repo/config/payloads.tsv
[ -r "$config" ] || fail "payload-update: missing $config."
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

# known ITEM: config has a row for ITEM, whatever its field.
known() {
    while IFS= read -r line || [ -n "$line" ]; do
        case $line in
            "$1$tab"*) return 0 ;;
        esac
    done <"$config"
    return 1
}

# payload_script INTERPRETER SOURCE [ARG...]: run SOURCE with ARG, stdin
# closed, and return its status. A URL is first downloaded, within the
# timeout, into a fresh directory that only this user can enter and that holds
# nothing else, removed afterwards: PyMOLScripts' and awesome-skills'
# installers read files beside themselves as a checkout's, which another user
# could plant in a shared TMPDIR. Every script runs in /, which only root can
# write, never in the caller's directory, which may be shared too
# (awesome-skills' installer runs python3 -c, which imports modules from its
# working directory first), nor in the download's, whose parent may be: git,
# which the kit's installer runs outside any repository, looks for one from
# its working directory upwards, so it would read a TMPDIR/.git another user
# made (safe.directory = * turns its ownership check off). The installers
# find their own files through their path. After one failed download a run
# tries no other.
staging='' offline=''
trap '[ -z "$staging" ] || rm -rf "$staging"' 0
trap 'exit 1' HUP INT TERM
unstage() {
    [ -z "$staging" ] || rm -rf "$staging"
    staging=
}
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
            staging=$(umask 077 && mktemp -d "${TMPDIR:-/tmp}/dotfiles-payload.XXXXXX") || return 1
            case $staging in
                /*) ;;
                *) staging=${PWD%/}/$staging ;;
            esac
            # Named as published, so the installer's $0 reads as in its README.
            download=$staging/${source##*/}
            case ${source##*/} in
                '' | .* | *[!A-Za-z0-9._-]*) download=$staging/install ;;
            esac
            download_status=1
            if command -v curl >/dev/null 2>&1; then
                curl -fsSL --connect-timeout "$connect" --max-time "$timeout" -o "$download" -- "$source" && download_status=0
            elif command -v wget >/dev/null 2>&1; then
                # wget's -T bounds idle reads, not the whole response. Use
                # an existing deadline tool; never run it without that bound.
                if command -v timeout >/dev/null 2>&1; then
                    deadline_command=timeout
                elif command -v gtimeout >/dev/null 2>&1; then
                    deadline_command=gtimeout
                else
                    unstage
                    dotfiles_log error "wget requires timeout or gtimeout; install curl instead to download $source"
                    return 1
                fi
                "$deadline_command" "$timeout" wget -q -T "$timeout" -t 1 -O "$download" -- "$source" && download_status=0
            else
                unstage
                dotfiles_log error "neither curl nor wget is installed; cannot download $source"
                return 1
            fi
            if [ "$download_status" != 0 ] || [ ! -s "$download" ]; then
                unstage
                dotfiles_log error "cannot download $source (within ${timeout}s)"
                return 1
            fi
            offline=
            set -- "$download" "$@"
            ;;
        *)
            if [ ! -f "$source" ]; then
                dotfiles_log error "$source is missing"
                return 1
            fi
            case $source in
                /*) ;;
                *) source=${PWD%/}/$source ;;
            esac
            set -- "$source" "$@"
            ;;
    esac
    script_status=0
    (cd / && exec "$interpreter" "$@" </dev/null) || script_status=$?
    unstage
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

# run ITEM: install ITEM when absent, else update it. Sets status to the
# command's exit status and returns it.
run() {
    status=1
    if stowed "$1"; then
        dotfiles_log warn "$1: ~/$value is still a link the retired Stow package made, which its installer refuses; run $repo/stow-all.sh with this host first (the next login's automatic stow does), then sync-payloads $1"
        return 1
    fi
    action=update doing=updating
    installed "$1" || action=install doing=installing
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
    status=0
    eval "$value" || status=$?
    case $status in
        0) dotfiles_log ok "$1: $action done" ;;
        75) dotfiles_log info "$1: another run holds its lock; run sync-payloads $1 again once it has finished" ;;
        "$person") dotfiles_log error "$1: stopped for a person (exit $status): do what its message says, then run sync-payloads $1" ;;
        *) dotfiles_log error "$1: $action failed (exit $status); retry with: sync-payloads $1" ;;
    esac
    return "$status"
}

if [ "$#" -eq 0 ]; then
    # shellcheck disable=SC2086 # a word list; set -f keeps it from globbing
    set -- ${DOTFILES_PAYLOAD_ITEMS-kit pymol skills}
fi
for item in "$@"; do
    known "$item" ||
        fail "payload-update: unknown item '$item'; config/payloads.tsv names kit, pymol and skills."
done

failed=0
for item in "$@"; do
    run "$item" || [ "$status" = 75 ] || failed=1
done
exit "$failed"
