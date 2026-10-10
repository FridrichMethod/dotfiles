# shellcheck shell=bash
# Manifest access for doctor.sh and setup-host.sh. Sourced only; defines
# functions and changes no shell options. Bash 3.2 compatible and `set -u`
# safe. Manifest data is split with parameter expansion and awk, never eval'd:
# tests/test_bootstrap_manifest.py validates config/bootstrap, and this file
# trusts what it validated.

BOOTSTRAP_TAB=$(printf '\t')
BOOTSTRAP_TIER_ORDER='core cli ai desktop contributor host'

# bootstrap_init ROOT: set BOOTSTRAP_ROOT and, unless a test preset it,
# BOOTSTRAP_CONFIG=ROOT/config/bootstrap.
bootstrap_init() {
    BOOTSTRAP_ROOT=$1
    BOOTSTRAP_CONFIG=${BOOTSTRAP_CONFIG:-$BOOTSTRAP_ROOT/config/bootstrap}
}

# bootstrap_rows FILE: print the data rows unchanged, without comment lines,
# blank lines or the header (the first other line). Returns 1 if unreadable.
bootstrap_rows() {
    [ -f "$1" ] && [ -r "$1" ] || return 1
    awk '
        /^#/ { next }
        /^[ \t\r]*$/ { next }
        !seen_header { seen_header = 1; next }
        { print }
    ' "$1"
}

# bootstrap_field LINE N: print tab-separated field N (1-based) of LINE.
bootstrap_field() {
    local rest=$1 index=1
    while [ "$index" -lt "$2" ]; do
        case $rest in
            *"$BOOTSTRAP_TAB"*) rest=${rest#*"$BOOTSTRAP_TAB"} ;;
            *) return 1 ;;
        esac
        index=$((index + 1))
    done
    printf '%s\n' "${rest%%"$BOOTSTRAP_TAB"*}"
}

# bootstrap_expand_path TOKENIZED: print the path with its leading token
# expanded. Supported tokens: $HOME $ZSH_CUSTOM $NVM_DIR $XDG_CONFIG_HOME
# $XDG_DATA_HOME $BAT_CONFIG_DIR, each alone or followed by "/". Returns 1 for
# any other "$", a leading "~", a ".." segment, or an empty HOME.
# shellcheck disable=SC2016 # the tokens are literal manifest text
bootstrap_expand_path() {
    local input=$1 base rest home=${HOME:-}
    [ -n "$home" ] || return 1
    case $input in
        '$HOME' | '$HOME/'*)
            base=$home
            rest=${input#'$HOME'}
            ;;
        '$ZSH_CUSTOM' | '$ZSH_CUSTOM/'*)
            base=${ZSH_CUSTOM:-${ZSH:-$home/.oh-my-zsh}/custom}
            rest=${input#'$ZSH_CUSTOM'}
            ;;
        '$NVM_DIR' | '$NVM_DIR/'*)
            base=${NVM_DIR:-$home/.nvm}
            rest=${input#'$NVM_DIR'}
            ;;
        '$XDG_CONFIG_HOME' | '$XDG_CONFIG_HOME/'*)
            base=${XDG_CONFIG_HOME:-$home/.config}
            rest=${input#'$XDG_CONFIG_HOME'}
            ;;
        '$XDG_DATA_HOME' | '$XDG_DATA_HOME/'*)
            base=${XDG_DATA_HOME:-$home/.local/share}
            rest=${input#'$XDG_DATA_HOME'}
            ;;
        '$BAT_CONFIG_DIR' | '$BAT_CONFIG_DIR/'*)
            # bat itself honours BAT_CONFIG_DIR before its XDG default.
            base=${BAT_CONFIG_DIR:-${XDG_CONFIG_HOME:-$home/.config}/bat}
            rest=${input#'$BAT_CONFIG_DIR'}
            ;;
        *)
            base=
            rest=$input
            ;;
    esac
    case $rest in
        *'$'* | '~'* | .. | ../* | */.. | */../*) return 1 ;;
    esac
    printf '%s%s\n' "$base" "$rest"
}

# bootstrap_host_matches HOSTS HOST: 0 when HOSTS is "all", or "unix" and
# HOST is not win, or a comma list naming HOST. An empty HOST (platform mode)
# matches only "all" and "unix".
bootstrap_host_matches() {
    local hosts=$1 host=${2:-}
    case $hosts in
        all) return 0 ;;
        unix)
            [ "$host" != win ]
            return
            ;;
    esac
    [ -n "$host" ] || return 1
    case ",$hosts," in
        *",$host,"*) return 0 ;;
    esac
    return 1
}

# bootstrap_tier_selected TIER SELECTION: SELECTION is "all" or a comma list.
bootstrap_tier_selected() {
    case $2 in
        all) return 0 ;;
    esac
    case ",$2," in
        *",$1,"*) return 0 ;;
    esac
    return 1
}

# bootstrap_rows_for_host FILE COLUMN HOST: data rows whose hosts column
# matches HOST.
bootstrap_rows_for_host() {
    local file=$1 column=$2 host=${3:-} rows line hosts
    rows=$(bootstrap_rows "$file") || return 1
    [ -n "$rows" ] || return 0
    while IFS= read -r line; do
        hosts=$(bootstrap_field "$line" "$column") || continue
        if bootstrap_host_matches "$hosts" "$host"; then
            printf '%s\n' "$line"
        fi
    done <<EOF
$rows
EOF
}

# bootstrap_tool_rows HOST: tools.tsv rows applicable to HOST.
bootstrap_tool_rows() {
    bootstrap_rows_for_host "$BOOTSTRAP_CONFIG/tools.tsv" 3 "${1:-}"
}

# bootstrap_clone_rows HOST: git-clones.tsv rows applicable to HOST.
bootstrap_clone_rows() {
    bootstrap_rows_for_host "$BOOTSTRAP_CONFIG/git-clones.tsv" 5 "${1:-}"
}

# bootstrap_installer_row ID HOST ARCH: print the one installers.tsv row for ID
# that applies to HOST and whose arch is ARCH or "any" (an exact arch wins).
# Returns 1 when there is none.
bootstrap_installer_row() {
    local id=$1 host=${2:-} arch=${3:-} rows exact='' generic='' line
    rows=$(bootstrap_installer_rows_for "$id" "$host") || return 1
    [ -n "$rows" ] || return 1
    while IFS= read -r line; do
        case $(bootstrap_field "$line" 7) in
            "$arch") [ -n "$exact" ] || exact=$line ;;
            any) [ -n "$generic" ] || generic=$line ;;
        esac
    done <<EOF
$rows
EOF
    if [ -n "$exact" ]; then
        printf '%s\n' "$exact"
    elif [ -n "$generic" ]; then
        printf '%s\n' "$generic"
    else
        return 1
    fi
}

# bootstrap_installer_rows_for ID HOST: every installers.tsv row for ID that
# applies to HOST, any arch.
bootstrap_installer_rows_for() {
    local id=$1 line
    bootstrap_rows_for_host "$BOOTSTRAP_CONFIG/installers.tsv" 6 "${2:-}" |
        while IFS= read -r line; do
            case $line in
                "$id$BOOTSTRAP_TAB"*) printf '%s\n' "$line" ;;
            esac
        done
}

# bootstrap_list_packages FILE: package names from an apt list, one per line.
bootstrap_list_packages() {
    [ -f "$1" ] && [ -r "$1" ] || return 1
    awk '
        { sub(/\r$/, "") }
        /^[ \t]*#/ { next }
        { gsub(/^[ \t]+|[ \t]+$/, "") }
        $0 != "" { print }
    ' "$1"
}

# bootstrap_apt_packages HOST: apt/common.txt then apt/HOST.txt (if present).
bootstrap_apt_packages() {
    local host=${1:-}
    bootstrap_list_packages "$BOOTSTRAP_CONFIG/apt/common.txt" || return 1
    case $host in
        '' | */* | .*) return 0 ;;
    esac
    if [ -f "$BOOTSTRAP_CONFIG/apt/$host.txt" ]; then
        bootstrap_list_packages "$BOOTSTRAP_CONFIG/apt/$host.txt"
    fi
}

# bootstrap_brewfiles TIERS: existing Brewfile paths for the selected tiers,
# in tier order (core cli ai desktop contributor), whatever order TIERS uses.
bootstrap_brewfiles() {
    local tier
    for tier in $BOOTSTRAP_TIER_ORDER; do
        bootstrap_tier_selected "$tier" "$1" || continue
        if [ -f "$BOOTSTRAP_CONFIG/brew/$tier.Brewfile" ]; then
            printf '%s\n' "$BOOTSTRAP_CONFIG/brew/$tier.Brewfile"
        fi
    done
}

# bootstrap_doc_ref STEP PROFILE: the step a profile's reader should follow.
bootstrap_doc_ref() {
    case $2:$1 in
        hpc:S2-brew-bundle) printf '%s\n' S2-login-env ;;
        hpc:S4-nvm | hpc:S5-claude | hpc:S5-codex) printf '%s\n' S2-modules ;;
        windows:S2-brew-bundle | windows:S4-nvm | windows:S5-claude | windows:S5-codex)
            printf '%s\n' W1-winget
            ;;
        windows:S3-bat-theme) printf '%s\n' W1-bat-theme ;;
        windows:S6-nerd-font) printf '%s\n' W1-font ;;
        windows:S4-setup-sync) printf '%s\n' W1-setup-sync ;;
        windows:H7-stow) printf '%s\n' HW-stow ;;
        windows:H7-auth) printf '%s\n' HW-auth ;;
        *) printf '%s\n' "$1" ;;
    esac
}
