# shellcheck shell=bash
# Manifest access for doctor.sh and setup-host.sh. Sourced only; defines
# functions and changes no shell options. Bash 3.2 compatible and `set -u`
# safe. Manifest data is split with parameter expansion and awk, never eval'd:
# tests/test_bootstrap_manifest.py validates config/bootstrap, and this file
# trusts what it validated. A caller's IFS (Bash `local` is dynamically
# scoped) never changes a result: every split sets its own IFS.
#
# No here-documents or here-strings, here or in any file doctor.sh and
# setup-host.sh run: Bash 3.2 (macOS /bin/bash) backs each one with a
# temporary file, which the read-only modes must not create. Nor process
# substitution: Bash 3.2 keeps its descriptors open until the outermost
# function returns. Lines and fields are split with parameter expansion
# (BOOTSTRAP_NL, bootstrap_split), and text reaches a command, or a loop that
# only prints, through a pipe (bootstrap_text_has, bootstrap_rows_for_host).
# tests/bootstrap-manifest.sh enforces the rule.

BOOTSTRAP_TAB=$(printf '\t')
BOOTSTRAP_NL='
'
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

# bootstrap_split SEP LINE NAME...: assign the fields of LINE to the NAMEs
# exactly as `IFS=SEP read -r NAME...` would for a one-line LINE and a SEP
# of one space or one tab: leading and trailing SEPs are dropped, a run of
# SEPs separates two fields, the last NAME takes the rest of the line, and
# NAMEs past the last field are set empty. A NAME of _ is skipped. The NAMEs
# are the caller's variables (its locals too); none may start with _bs_.
bootstrap_split() {
    local _bs_sep=$1 _bs_rest=$2 _bs_field
    shift 2
    while :; do
        case $_bs_rest in
            "$_bs_sep"*) _bs_rest=${_bs_rest#"$_bs_sep"} ;;
            *) break ;;
        esac
    done
    while [ "$#" -gt 1 ]; do
        case $_bs_rest in
            *"$_bs_sep"*)
                _bs_field=${_bs_rest%%"$_bs_sep"*}
                _bs_rest=${_bs_rest#*"$_bs_sep"}
                while :; do
                    case $_bs_rest in
                        "$_bs_sep"*) _bs_rest=${_bs_rest#"$_bs_sep"} ;;
                        *) break ;;
                    esac
                done
                ;;
            *)
                _bs_field=$_bs_rest
                _bs_rest=
                ;;
        esac
        [ "$1" = _ ] || printf -v "$1" '%s' "$_bs_field"
        shift
    done
    while :; do
        case $_bs_rest in
            *"$_bs_sep") _bs_rest=${_bs_rest%"$_bs_sep"} ;;
            *) break ;;
        esac
    done
    [ "$#" -eq 0 ] || [ "$1" = _ ] || printf -v "$1" '%s' "$_bs_rest"
}

# bootstrap_text_has OPTIONS PATTERN TEXT: grep OPTIONS (-F, -Ei, ...) for
# PATTERN in the lines of TEXT and return grep's status. pipefail is off in
# the subshell only, so grep -q stopping at its first match of a long TEXT
# never fails the pipe through the writer's SIGPIPE.
bootstrap_text_has() {
    (
        set +o pipefail
        printf '%s\n' "$3" | grep -q "$1" -- "$2"
    )
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
# matches HOST. The loop only prints, so it reads its lines from a pipe in a
# subshell: splitting off one line at a time copies the rest of a whole
# manifest per line, which Bash 3.2 does slowly in a UTF-8 locale.
bootstrap_rows_for_host() {
    local file=$1 column=$2 host=${3:-} rows line hosts
    rows=$(bootstrap_rows "$file") || return 1
    [ -n "$rows" ] || return 0
    printf '%s\n' "$rows" | while IFS= read -r line; do
        hosts=$(bootstrap_field "$line" "$column") || continue
        if bootstrap_host_matches "$hosts" "$host"; then
            printf '%s\n' "$line"
        fi
    done
}

# bootstrap_tool_rows HOST: tools.tsv rows applicable to HOST.
bootstrap_tool_rows() {
    bootstrap_rows_for_host "$BOOTSTRAP_CONFIG/tools.tsv" 3 "${1:-}"
}

# bootstrap_tool_aliases NAME: the TOOL-IDs that tools.tsv installs under
# NAME, from its "# alias: TOOL-ID NAME" declarations, one per line in file
# order. Returns 1 if tools.tsv is unreadable.
bootstrap_tool_aliases() {
    [ -f "$BOOTSTRAP_CONFIG/tools.tsv" ] && [ -r "$BOOTSTRAP_CONFIG/tools.tsv" ] || return 1
    awk -v name="$1" 'index($0, "# alias: ") == 1 && NF == 4 && $4 == name { print $3 }' \
        "$BOOTSTRAP_CONFIG/tools.tsv"
}

# bootstrap_clone_rows HOST: git-clones.tsv rows applicable to HOST.
bootstrap_clone_rows() {
    bootstrap_rows_for_host "$BOOTSTRAP_CONFIG/git-clones.tsv" 5 "${1:-}"
}

# bootstrap_installer_row ID HOST ARCH: print the one installers.tsv row for ID
# that applies to HOST and whose arch is ARCH or "any" (an exact arch wins).
# Returns 1 when there is none.
bootstrap_installer_row() {
    local id=$1 host=${2:-} arch=${3:-} rows exact='' generic='' lines line
    rows=$(bootstrap_installer_rows_for "$id" "$host") || return 1
    [ -n "$rows" ] || return 1
    lines=$rows$BOOTSTRAP_NL
    while [ -n "$lines" ]; do
        line=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        case $(bootstrap_field "$line" 7) in
            "$arch") [ -n "$exact" ] || exact=$line ;;
            any) [ -n "$generic" ] || generic=$line ;;
        esac
    done
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
    local IFS=' ' tier
    for tier in $BOOTSTRAP_TIER_ORDER; do
        bootstrap_tier_selected "$tier" "$1" || continue
        if [ -f "$BOOTSTRAP_CONFIG/brew/$tier.Brewfile" ]; then
            printf '%s\n' "$BOOTSTRAP_CONFIG/brew/$tier.Brewfile"
        fi
    done
}

# bootstrap_doc_ref STEP PROFILE: the step a profile's reader should follow.
# tools.tsv names the debian/macOS step; a profile that installs the tool
# another way points at that way: the login env on hpc (where locales are the
# site's), the Brewfiles on macOS (no apt), X-other-linux for a machine without
# an overlay, and the W1-* and HW-* steps on Windows.
bootstrap_doc_ref() {
    case $2:$1 in
        hpc:S2-brew-bundle | hpc:H1-apt-core) printf '%s\n' S2-login-env ;;
        hpc:H1-locale) printf '%s\n' P0-preflight ;;
        hpc:S4-nvm | hpc:S5-claude | hpc:S5-codex) printf '%s\n' S2-modules ;;
        macos:H1-apt-core) printf '%s\n' S2-brew-bundle ;;
        other:H1-apt-core | other:H1-locale | other:H1-homebrew | other:H1-linuxbrew | \
            other:S2-brew-bundle | other:S4-nvm | other:S5-claude | other:S5-codex)
            printf '%s\n' X-other-linux
            ;;
        windows:P0-preflight) printf '%s\n' HW-clone ;;
        windows:H1-apt-core | windows:S2-brew-bundle | windows:S4-nvm | windows:S5-claude | windows:S5-codex)
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
