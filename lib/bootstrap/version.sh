# shellcheck shell=bash
# Version extraction and comparison for doctor.sh and setup-host.sh. Sourced
# only; defines functions and changes no shell options. Bash 3.2 compatible
# and `set -u` safe; no `sort -V`.

# bootstrap_extract_version TEXT: print the first X.Y or X.Y.Z in TEXT (the
# first match `grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1` would give),
# or nothing. Always returns 0, so callers under `set -e` may test for empty.
bootstrap_extract_version() {
    awk 'match($0, /[0-9]+\.[0-9]+(\.[0-9]+)?/) { print substr($0, RSTART, RLENGTH); exit }' <<EOF
${1:-}
EOF
}

# bootstrap_version_parts VERSION: print "MAJOR MINOR PATCH" (missing parts are
# 0, a leading v is dropped, leading zeros are decimal). Returns 1 unless
# VERSION is 1 to 3 dot-separated digit groups.
bootstrap_version_parts() {
    local version=${1#v} major minor patch extra
    case $version in
        '' | .* | *. | *..* | *[!0-9.]*) return 1 ;;
    esac
    IFS=. read -r major minor patch extra <<EOF
$version
EOF
    [ -z "$extra" ] || return 1
    printf '%s %s %s\n' "$((10#$major))" "$((10#${minor:-0}))" "$((10#${patch:-0}))"
}

# bootstrap_version_ge HAVE FLOOR: 0 iff HAVE >= FLOOR, compared as three
# numeric components. 1 when lower, 2 when either side is not a version.
bootstrap_version_ge() {
    local have floor h1 h2 h3 f1 f2 f3
    have=$(bootstrap_version_parts "${1:-}") || return 2
    floor=$(bootstrap_version_parts "${2:-}") || return 2
    read -r h1 h2 h3 <<EOF
$have
EOF
    read -r f1 f2 f3 <<EOF
$floor
EOF
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
