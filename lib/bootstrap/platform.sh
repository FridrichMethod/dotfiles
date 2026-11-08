# shellcheck shell=bash
# Host, profile and platform detection for doctor.sh and setup-host.sh: the
# host a configured home's ~/.config/chezmoi/chezmoi.toml selects.
# Sourced only; defines functions and changes no shell options. Bash 3.2
# compatible and `set -u` safe; nothing here splits words by the caller's IFS.
# No here-documents (see manifest.sh): text reaches awk through a pipe.
# Test overrides: BOOTSTRAP_UNAME_S, BOOTSTRAP_UNAME_M, BOOTSTRAP_OS_RELEASE,
# BOOTSTRAP_PROC_VERSION, BOOTSTRAP_BREW_CANDIDATES.

# bootstrap_known_hosts: the host overlays, one per line.
bootstrap_known_hosts() {
    printf '%s\n' mac wsl-ubuntu lab-ubuntu sherlock marlowe win
}

# bootstrap_profile_for_host HOST: macos, debian, hpc or windows; 2 if unknown.
bootstrap_profile_for_host() {
    case ${1:-} in
        mac) printf '%s\n' macos ;;
        wsl-ubuntu | lab-ubuntu) printf '%s\n' debian ;;
        sherlock | marlowe) printf '%s\n' hpc ;;
        win) printf '%s\n' windows ;;
        *) return 2 ;;
    esac
}

# bootstrap_os: the kernel name (uname -s).
bootstrap_os() {
    if [ -n "${BOOTSTRAP_UNAME_S:-}" ]; then
        printf '%s\n' "$BOOTSTRAP_UNAME_S"
    else
        uname -s
    fi
}

# bootstrap_arch: x86_64 or aarch64. Other machines print uname -m and return 1.
bootstrap_arch() {
    local machine
    if [ -n "${BOOTSTRAP_UNAME_M:-}" ]; then
        machine=$BOOTSTRAP_UNAME_M
    else
        machine=$(uname -m)
    fi
    case $machine in
        x86_64 | amd64) printf '%s\n' x86_64 ;;
        aarch64 | arm64) printf '%s\n' aarch64 ;;
        *)
            printf '%s\n' "$machine"
            return 1
            ;;
    esac
}

# bootstrap_os_release_value KEY: the unquoted value of KEY in os-release,
# read as data (the file is never sourced). Empty when absent.
bootstrap_os_release_value() {
    local file=${BOOTSTRAP_OS_RELEASE:-/etc/os-release} key value
    [ -f "$file" ] && [ -r "$file" ] || return 0
    while IFS='=' read -r key value || [ -n "$key" ]; do
        [ "$key" = "$1" ] || continue
        value=${value%$'\r'}
        case $value in
            \"*\")
                value=${value#\"}
                value=${value%\"}
                ;;
            \'*\')
                value=${value#\'}
                value=${value%\'}
                ;;
        esac
        printf '%s\n' "$value"
        return 0
    done <"$file"
}

# bootstrap_detect_platform: macos, debian, hpc or other. Lmod (LMOD_DIR)
# marks a cluster before os-release is read, since Marlowe runs Ubuntu.
bootstrap_detect_platform() {
    local id like
    case $(bootstrap_os) in
        Darwin)
            printf '%s\n' macos
            return 0
            ;;
        Linux) ;;
        *)
            printf '%s\n' other
            return 0
            ;;
    esac
    if [ -n "${LMOD_DIR:-}" ]; then
        printf '%s\n' hpc
        return 0
    fi
    id=$(bootstrap_os_release_value ID)
    like=$(bootstrap_os_release_value ID_LIKE)
    # Whole-word match on the space-separated ID and ID_LIKE, without word
    # splitting or pathname expansion of os-release data.
    case " $id $like " in
        *' debian '* | *' ubuntu '*) printf '%s\n' debian ;;
        *) printf '%s\n' other ;;
    esac
}

# bootstrap_is_wsl: 0 under WSL (WSL_DISTRO_NAME, or a Microsoft kernel).
bootstrap_is_wsl() {
    local file=${BOOTSTRAP_PROC_VERSION:-/proc/version}
    [ -z "${WSL_DISTRO_NAME:-}" ] || return 0
    [ -f "$file" ] && [ -r "$file" ] || return 1
    grep -qi microsoft "$file"
}

# bootstrap_in_allocation: 0 inside a Slurm job.
bootstrap_in_allocation() {
    [ -n "${SLURM_JOB_ID:-}" ]
}

# bootstrap_glibc_version: glibc X.Y from the first line of `ldd --version`;
# empty on macOS, on musl, or when ldd is missing.
bootstrap_glibc_version() {
    local first
    [ "$(bootstrap_os)" = Linux ] || return 0
    command -v ldd >/dev/null 2>&1 || return 0
    first=$(ldd --version 2>&1 </dev/null | sed -n 1p) || first=
    case $first in
        *[Gg][Ll][Ii][Bb][Cc]* | *'GNU libc'*) ;;
        *) return 0 ;;
    esac
    # awk reads to the end, so the writer never dies of SIGPIPE under pipefail.
    printf '%s\n' "$first" |
        awk '!found && match($0, /[0-9]+\.[0-9]+/) { print substr($0, RSTART, RLENGTH); found = 1 }'
}

# bootstrap_brew_bin: the brew executable this process should use: brew on
# PATH, else the first executable among Homebrew's default prefixes. A fresh
# install stays off PATH until `brew shellenv` runs, which only the dotfiles rc
# files do, so callers prepend the printed file's directory to their own PATH
# before probing or bundling. BOOTSTRAP_BREW_CANDIDATES (colon-separated paths)
# replaces the prefix list for tests. Returns 1 when there is none.
bootstrap_brew_bin() {
    local found rest candidate
    found=$(command -v brew 2>/dev/null) || found=
    case $found in
        /*)
            printf '%s\n' "$found"
            return 0
            ;;
    esac
    rest=${BOOTSTRAP_BREW_CANDIDATES-/opt/homebrew/bin/brew:/usr/local/bin/brew:/home/linuxbrew/.linuxbrew/bin/brew:${HOME:-}/.linuxbrew/bin/brew}
    while [ -n "$rest" ]; do
        candidate=${rest%%:*}
        case $rest in
            *:*) rest=${rest#*:} ;;
            *) rest= ;;
        esac
        if [ -n "$candidate" ] && [ -f "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

# bootstrap_configured_home: 0 when ~/.config/chezmoi/chezmoi.toml exists in
# any form, the existence test of dotfiles_config_exists
# (lib/chezmoi-guard.sh); the chezmoi-config check judges the config. Such a
# home records its role in that config.
bootstrap_configured_home() {
    [ -n "${HOME:-}" ] || return 1
    [ -e "${HOME%/}/.config/chezmoi/chezmoi.toml" ] || [ -L "${HOME%/}/.config/chezmoi/chezmoi.toml" ]
}

# bootstrap_config_host: the role, generic or a known host, that the one
# host = 'ROLE' or host = "ROLE" line in the [data] table of a regular
# ~/.config/chezmoi/chezmoi.toml selects, the forms chezmoi init writes. Read
# as text, never through chezmoi, whose commands may open persistent state.
# Any other spelling, a second host line or an unknown role returns 1.
bootstrap_config_host() {
    local config line table='' value quote rest role='' seen=0
    [ -n "${HOME:-}" ] || return 1
    config=${HOME%/}/.config/chezmoi/chezmoi.toml
    [ -f "$config" ] && [ ! -L "$config" ] && [ -r "$config" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%$'\r'}
        line=${line#"${line%%[![:blank:]]*}"}
        case $line in
            '['*) table=${line%%]*}] ;;
            host[[:blank:]=]*)
                [ "$table" = '[data]' ] || continue
                [ "$seen" = 0 ] || return 1
                seen=1
                value=${line#host}
                value=${value#"${value%%[![:blank:]]*}"}
                case $value in
                    =*) value=${value#=} ;;
                    *) return 1 ;;
                esac
                value=${value#"${value%%[![:blank:]]*}"}
                quote=${value%"${value#?}"}
                case $quote in
                    \' | \") ;;
                    *) return 1 ;;
                esac
                value=${value#?}
                case $value in
                    *"$quote"*) ;;
                    *) return 1 ;;
                esac
                role=${value%%"$quote"*}
                rest=${value#*"$quote"}
                rest=${rest#"${rest%%[![:blank:]]*}"}
                case $rest in
                    '' | '#'*) ;;
                    *) return 1 ;;
                esac
                ;;
        esac
    done <"$config"
    case $role in
        generic | mac | wsl-ubuntu | lab-ubuntu | sherlock | marlowe | win) printf '%s\n' "$role" ;;
        *) return 1 ;;
    esac
}

# bootstrap_recorded_generic: 0 when this home has a local config that
# selects generic (no host overlay).
bootstrap_recorded_generic() {
    bootstrap_configured_home && [ "$(bootstrap_config_host)" = generic ]
}

# bootstrap_resolve_host: the host a configured home's local config selects
# (bootstrap_config_host). Returns 1 on any other home, for an unclear role
# and for generic (bootstrap_recorded_generic tells that case apart).
# Never guesses an overlay.
bootstrap_resolve_host() {
    local host
    bootstrap_configured_home || return 1
    host=$(bootstrap_config_host) || return 1
    [ "$host" != generic ] || return 1
    printf '%s\n' "$host"
}
