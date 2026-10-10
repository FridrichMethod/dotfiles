# shellcheck shell=bash
# Pinned downloads for setup-host.sh. Sourced only; defines functions and
# changes no shell options. Bash 3.2 compatible and `set -u` safe.
# Nothing is ever piped into a shell: bootstrap_fetch stages the download in
# DEST.part, checks its sha256, and only then moves it to DEST.

# bootstrap_fetch_error MESSAGE: report through dotfiles_log when the caller
# sourced lib/terminal.sh, else on stderr.
bootstrap_fetch_error() {
    if declare -F dotfiles_log >/dev/null 2>&1; then
        dotfiles_log error "$*"
    else
        printf 'bootstrap_fetch: %s\n' "$*" >&2
    fi
}

# bootstrap_sha256 FILE: print the lowercase sha256 of FILE, from sha256sum or
# else `shasum -a 256`. The file is read on stdin, so no file name is ever
# escaped into the output. Returns 1 without a tool or a readable FILE.
bootstrap_sha256() {
    local line
    [ -f "$1" ] && [ -r "$1" ] || return 1
    if command -v sha256sum >/dev/null 2>&1; then
        line=$(sha256sum <"$1") || return 1
    elif command -v shasum >/dev/null 2>&1; then
        line=$(shasum -a 256 <"$1") || return 1
    else
        return 1
    fi
    line=${line%% *}
    case $line in
        *[!0-9a-f]* | '') return 1 ;;
    esac
    [ "${#line}" -eq 64 ] || return 1
    printf '%s\n' "$line"
}

# bootstrap_fetch [--inspect] URL DEST SHA256: download the https URL to
# DEST.part with curl (wget as the fallback), verify SHA256, then move it to
# DEST. On a mismatch DEST.part is removed, DEST is left untouched, and the
# expected and actual digests are reported. SHA256 "-" (an unpinnable vendor
# script that a person reads before running) needs the explicit --inspect.
# Returns 0 on success, 1 on a download or digest failure, 2 on misuse.
bootstrap_fetch() {
    local inspect=0 url dest sha part actual
    if [ "${1:-}" = --inspect ]; then
        inspect=1
        shift
    fi
    if [ "$#" -ne 3 ]; then
        bootstrap_fetch_error 'usage: bootstrap_fetch [--inspect] URL DEST SHA256'
        return 2
    fi
    url=$1
    dest=$2
    sha=$3
    part=$dest.part
    case $url in
        https://*) ;;
        *)
            bootstrap_fetch_error "refusing a non-https download: $url"
            return 2
            ;;
    esac
    case $sha in
        -)
            if [ "$inspect" != 1 ]; then
                bootstrap_fetch_error "refusing an unpinned download without --inspect: $url"
                return 2
            fi
            ;;
        *[!0-9a-f]*)
            bootstrap_fetch_error "invalid sha256 for $url: $sha"
            return 2
            ;;
        *)
            if [ "${#sha}" -ne 64 ]; then
                bootstrap_fetch_error "invalid sha256 for $url: $sha"
                return 2
            fi
            ;;
    esac
    case $dest in
        '' | */)
            bootstrap_fetch_error "invalid download destination: $dest"
            return 2
            ;;
    esac

    mkdir -p -- "$(dirname -- "$dest")" || return 1
    rm -f -- "$part" || return 1
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --proto '=https' --tlsv1.2 --retry 3 -o "$part" "$url" </dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q --https-only -O "$part" "$url" </dev/null
    else
        bootstrap_fetch_error "neither curl nor wget is installed; cannot download $url"
        return 1
    fi || {
        rm -f -- "$part"
        bootstrap_fetch_error "download failed: $url"
        return 1
    }

    if [ "$sha" != - ]; then
        if ! actual=$(bootstrap_sha256 "$part"); then
            rm -f -- "$part"
            bootstrap_fetch_error "cannot compute sha256 (no sha256sum or shasum) for $url"
            return 1
        fi
        if [ "$actual" != "$sha" ]; then
            rm -f -- "$part"
            bootstrap_fetch_error "sha256 mismatch for $url: expected $sha, actual $actual"
            return 1
        fi
    fi
    mv -f -- "$part" "$dest" || {
        rm -f -- "$part"
        return 1
    }
}
