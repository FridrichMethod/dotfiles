# shellcheck shell=bash
# Version extraction and comparison for doctor.sh and setup-host.sh. Sourced
# only; defines functions and changes no shell options. Bash 3.2 compatible
# and `set -u` safe; no `sort -V`. Bash `local` is dynamically scoped, so a
# caller's IFS (a TSV loop's tab, say) reaches these functions: each one that
# splits words sets its own IFS. No here-documents (see manifest.sh): text
# reaches awk through a pipe, and versions are split by parameter expansion.

# bootstrap_extract_version TEXT: print the first X.Y or X.Y.Z in TEXT (the
# first match `grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1` would give),
# or nothing. Always returns 0, so callers under `set -e` may test for empty.
# awk reads to the end, so the writer never dies of SIGPIPE under pipefail.
bootstrap_extract_version() {
    printf '%s\n' "${1:-}" |
        awk '!found && match($0, /[0-9]+\.[0-9]+(\.[0-9]+)?/) { print substr($0, RSTART, RLENGTH); found = 1 }'
}

# bootstrap_version_parts VERSION: print "MAJOR MINOR PATCH" (missing parts are
# 0, a leading v is dropped, leading zeros are decimal). Returns 1 unless
# VERSION is 1 to 3 dot-separated digit groups.
bootstrap_version_parts() {
    local version=${1#v} major minor='' patch='' rest
    case $version in
        '' | .* | *. | *..* | *[!0-9.]*) return 1 ;;
    esac
    # Digit groups joined by single dots, at most three of them.
    major=${version%%.*}
    rest=${version#"$major"}
    rest=${rest#.}
    if [ -n "$rest" ]; then
        minor=${rest%%.*}
        rest=${rest#"$minor"}
        rest=${rest#.}
        patch=$rest
    fi
    case $patch in
        *.*) return 1 ;;
    esac
    printf '%s %s %s\n' "$((10#$major))" "$((10#${minor:-0}))" "$((10#${patch:-0}))"
}

# bootstrap_version_ge HAVE FLOOR: 0 iff HAVE >= FLOOR, compared as three
# numeric components. 1 when lower, 2 when either side is not a version.
bootstrap_version_ge() {
    local IFS=' ' have floor h1 h2 h3 f1 f2 f3
    have=$(bootstrap_version_parts "${1:-}") || return 2
    floor=$(bootstrap_version_parts "${2:-}") || return 2
    h1=${have%% *} h3=${have##* } f1=${floor%% *} f3=${floor##* }
    h2=${have#* } h2=${h2%% *} f2=${floor#* } f2=${f2%% *}
    if [ "$h1" -ne "$f1" ]; then
        [ "$h1" -gt "$f1" ] && return 0
        return 1
    fi
    if [ "$h2" -ne "$f2" ]; then
        [ "$h2" -gt "$f2" ] && return 0
        return 1
    fi
    [ "$h3" -ge "$f3" ] && return 0
    return 1
}

# bootstrap_tool_version CMD FLAG: run `CMD FLAG </dev/null 2>&1 | head -n 5`
# and print the first version in that output, or nothing (also for FLAG "-"
# or a CMD that fails to run). Always returns 0.
bootstrap_tool_version() {
    local output
    [ "${2:-}" != - ] || return 0
    # Keep what a tool printed even when it exits non-zero (some print their
    # version and fail); sed reads to EOF, so no SIGPIPE under pipefail.
    output=$("$1" "$2" </dev/null 2>&1 | sed -n 1,5p) || true
    bootstrap_extract_version "$output"
}
