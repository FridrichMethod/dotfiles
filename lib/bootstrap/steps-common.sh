# shellcheck shell=bash
# shellcheck disable=SC2034 # the STEP_* and STEPS_* fields are read by the step files
# Shared helpers of the setup-host.sh steps: HUMAN block frames, tools.tsv
# probes, installers.tsv rows and pinned downloads, scratch dirs, PATH, the
# manifest shape check, the platform refusal and P0-preflight. Sourced only
# (after steps.sh); defines functions and changes no shell options.

# steps_text_has OPTIONS PATTERN TEXT: grep OPTIONS (-F, -Ei, ...) for
# PATTERN in TEXT without a pipe (no SIGPIPE under pipefail).
steps_text_has() {
    grep -q "$1" -- "$2" <<EOF
$3
EOF
}

# steps_quote WORD: WORD quoted for a HUMAN block a person pastes.
steps_quote() {
    printf '%q' "$1"
}

# steps_block_begin ID KIND / steps_block_end: the HUMAN block frame. Blocks
# are printed, never executed; `#` lines are notes for the reader.
steps_block_begin() {
    printf 'HUMAN-BEGIN %s %s\n' "$1" "$2"
    printf '# docs/bootstrap.md %s\n' "$(bootstrap_doc_ref "$1" "$STEPS_PROFILE")"
}

steps_block_end() {
    printf '%s\n' HUMAN-END
}

# steps_tool_cell ID COLUMN: one tools.tsv cell of the row ID for this host.
steps_tool_cell() {
    local row
    while IFS= read -r row; do
        case $row in
            "$1$BOOTSTRAP_TAB"*)
                bootstrap_field "$row" "$2"
                return
                ;;
        esac
    done <<EOF
$(bootstrap_tool_rows "$STEPS_HOST")
EOF
    return 1
}

# steps_probe ID: evaluate the tools.tsv probe of ID (command list, file:,
# dir: or env:) and set STEPS_PROBE_FOUND. 1 when absent, 2 for a probe kind
# this installer does not evaluate (font:, psmodule:) or an unknown ID.
steps_probe() {
    local probe rest name path
    STEPS_PROBE_FOUND=
    probe=$(steps_tool_cell "$1" 4) || return 2
    case $probe in
        file:*)
            path=$(bootstrap_expand_path "${probe#file:}") || return 2
            [ -f "$path" ] || return 1
            STEPS_PROBE_FOUND=$path
            ;;
        dir:*)
            path=$(bootstrap_expand_path "${probe#dir:}") || return 2
            [ -d "$path" ] || return 1
            STEPS_PROBE_FOUND=$path
            ;;
        env:*)
            name=${probe#env:}
            case $name in
                '' | [0-9]* | *[!A-Za-z0-9_]*) return 2 ;;
            esac
            [ -n "${!name-}" ] || return 1
            STEPS_PROBE_FOUND=$name
            ;;
        font:* | psmodule:*) return 2 ;;
        *)
            rest=$probe
            while [ -n "$rest" ]; do
                name=${rest%%,*}
                case $rest in
                    *,*) rest=${rest#*,} ;;
                    *) rest= ;;
                esac
                if path=$(command -v "$name" 2>/dev/null) && [ -n "$path" ]; then
                    STEPS_PROBE_FOUND=$path
                    return 0
                fi
            done
            return 1
            ;;
    esac
}

# steps_installer_fields ID: set STEPS_KIND STEPS_URL STEPS_SHA STEPS_DEST
# (expanded, or "-") and STEPS_HUMAN from the installers.tsv row of ID for
# this host and arch. Returns 1 when there is none.
steps_installer_fields() {
    local row id hosts arch tier dest
    row=$(bootstrap_installer_row "$1" "$STEPS_HOST" "$STEPS_ARCH") || return 1
    [ -n "$row" ] || return 1
    IFS="$BOOTSTRAP_TAB" read -r id STEPS_KIND STEPS_URL STEPS_SHA dest hosts arch tier STEPS_HUMAN <<EOF
$row
EOF
    if [ "$dest" = - ]; then
        STEPS_DEST=-
    else
        STEPS_DEST=$(bootstrap_expand_path "$dest") || return 1
    fi
}

# steps_scratch_base / steps_scratch_file ID URL: where downloads that are
# not installed in place are staged (written only in apply mode).
steps_scratch_base() {
    printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-bootstrap"
}

steps_scratch_file() {
    local name=${2##*/}
    name=${name%%\?*}
    case $name in
        '' | . | .. | *[!A-Za-z0-9._-]*) name=download ;;
    esac
    printf '%s/%s/%s\n' "$(steps_scratch_base)" "$1" "$name"
}

# steps_make_scratch ID: create the private scratch dir of ID.
steps_make_scratch() {
    local base
    base=$(steps_scratch_base)
    mkdir -p "$base/$1" || return 1
    chmod 700 "$base" "$base/$1"
}

# steps_has_digest FILE SHA256: 0 when FILE exists with that digest.
steps_has_digest() {
    local have
    [ "$2" != - ] && [ -f "$1" ] || return 1
    have=$(bootstrap_sha256 "$1") || return 1
    [ "$have" = "$2" ]
}

# steps_fetch_pinned URL DEST SHA256: bootstrap_fetch unless DEST already
# holds the pinned digest. SHA256 "-" downloads for inspection.
steps_fetch_pinned() {
    if steps_has_digest "$2" "$3"; then
        return 0
    fi
    if [ "$3" = - ]; then
        bootstrap_fetch --inspect "$1" "$2" -
    else
        bootstrap_fetch "$1" "$2" "$3"
    fi
}

# steps_fetch_installer ID: download the script of installers.tsv row ID to
# its scratch file (a HUMAN block then names that file).
steps_fetch_installer() {
    local path
    if ! steps_installer_fields "$1"; then
        dotfiles_log error "no installers.tsv row for $1 on $STEPS_HOST $STEPS_ARCH"
        return 1
    fi
    path=$(steps_scratch_file "$1" "$STEPS_URL")
    steps_make_scratch "$1" || return 1
    steps_fetch_pinned "$STEPS_URL" "$path" "$STEPS_SHA"
}

# steps_resolve FILE: the physical path FILE ends at after following links.
steps_resolve() {
    local path=$1 target dir count=0
    while [ -L "$path" ] && [ "$count" -lt 40 ]; do
        target=$(readlink "$path") || return 1
        case $target in
            /*) path=$target ;;
            *) path=$(dirname "$path")/$target ;;
        esac
        count=$((count + 1))
    done
    dir=$(cd -P "$(dirname "$path")" 2>/dev/null && pwd) || return 1
    printf '%s/%s\n' "${dir%/}" "${path##*/}"
}

# steps_path_prepend DIR: put an existing DIR first on PATH (this process).
steps_path_prepend() {
    [ -d "$1" ] || return 0
    case ":$PATH:" in
        *":$1:"*) return 0 ;;
    esac
    PATH=$1:$PATH
}

# steps_extend_path: let this run see what the installers put on disk before
# any rc file is stowed: ~/.local/bin, the hpc login env, then Homebrew.
# Nothing is written to an rc file.
steps_extend_path() {
    local brew dir
    if brew=$(bootstrap_brew_bin); then
        dir=${brew%/brew}
        steps_path_prepend "${dir%/bin}/sbin"
        steps_path_prepend "$dir"
    fi
    if [ "$STEPS_PROFILE" = hpc ]; then
        steps_path_prepend "$HOME/micromamba/envs/login/bin"
    fi
    steps_path_prepend "$HOME/.local/bin"
    export PATH
}

# steps_new_dir PARENT NAME: a fresh private temp dir in PARENT, then given
# the mode a plain mkdir would have (umask).
steps_new_dir() {
    local dir mode
    dir=$(mktemp -d "$1/.$2.XXXXXX") || return 1
    mode=$(printf '%o' $((0777 & ~0$(umask))))
    chmod "$mode" "$dir" || {
        rm -rf "$dir"
        return 1
    }
    printf '%s\n' "$dir"
}

# steps_field_count ROW N: 0 when ROW has exactly N tab-separated fields.
steps_field_count() {
    local tabs=${1//[!$BOOTSTRAP_TAB]/}
    [ "${#tabs}" -eq "$(($2 - 1))" ]
}

# steps_invalid MESSAGE: report a manifest problem (exit 2 for the caller).
steps_invalid() {
    dotfiles_log error "invalid manifest: $*"
    return 1
}

# steps_validate_manifests: the shape setup-host relies on before it runs
# anything. tests/test_bootstrap_manifest.py is the full validator.
steps_validate_manifests() {
    local file row id kind url sha dest human ref
    for file in tools.tsv git-clones.tsv installers.tsv; do
        [ -f "$BOOTSTRAP_CONFIG/$file" ] && [ -r "$BOOTSTRAP_CONFIG/$file" ] ||
            steps_invalid "$BOOTSTRAP_CONFIG/$file is missing or unreadable" || return 1
    done
    case $STEPS_PROFILE in
        debian) file=apt/common.txt ;;
        hpc) file=hpc-login-env.yml ;;
        *) file=tools.tsv ;;
    esac
    [ -r "$BOOTSTRAP_CONFIG/$file" ] ||
        steps_invalid "$BOOTSTRAP_CONFIG/$file is missing or unreadable" || return 1
    while IFS= read -r row; do
        [ -n "$row" ] || continue
        steps_field_count "$row" 9 || steps_invalid "installers.tsv row needs 9 fields: $row" || return 1
        IFS="$BOOTSTRAP_TAB" read -r id kind url sha dest _ _ _ human <<EOF
$row
EOF
        case $kind in
            script | binary | archive | file) ;;
            *) steps_invalid "installers.tsv $id: unknown kind $kind" || return 1 ;;
        esac
        case $url in
            https://*) ;;
            *) steps_invalid "installers.tsv $id: url is not https: $url" || return 1 ;;
        esac
        case $sha in
            -) [ "$human" = inspect ] || steps_invalid "installers.tsv $id: sha256 - needs human inspect" || return 1 ;;
            *[!0-9a-f]*) steps_invalid "installers.tsv $id: bad sha256 $sha" || return 1 ;;
            *) [ "${#sha}" -eq 64 ] || steps_invalid "installers.tsv $id: bad sha256 $sha" || return 1 ;;
        esac
        if [ "$dest" != - ] && ! bootstrap_expand_path "$dest" >/dev/null; then
            steps_invalid "installers.tsv $id: unsupported dest $dest" || return 1
        fi
    done <<EOF
$(bootstrap_rows "$BOOTSTRAP_CONFIG/installers.tsv")
EOF
    while IFS= read -r row; do
        [ -n "$row" ] || continue
        steps_field_count "$row" 5 || steps_invalid "git-clones.tsv row needs 5 fields: $row" || return 1
        IFS="$BOOTSTRAP_TAB" read -r id dest url ref _ <<EOF
$row
EOF
        case $url in
            https://*) ;;
            *) steps_invalid "git-clones.tsv $id: url is not https: $url" || return 1 ;;
        esac
        case $id:$ref in
            oh-my-zsh:master) ;;
            *:*[!0-9a-f]* | *:) steps_invalid "git-clones.tsv $id: ref is not a commit: $ref" || return 1 ;;
            *) [ "${#ref}" -eq 40 ] || steps_invalid "git-clones.tsv $id: ref is not a commit: $ref" || return 1 ;;
        esac
        bootstrap_expand_path "$dest" >/dev/null ||
            steps_invalid "git-clones.tsv $id: unsupported dest $dest" || return 1
    done <<EOF
$(bootstrap_rows "$BOOTSTRAP_CONFIG/git-clones.tsv")
EOF
}

# steps_platform_mismatch: print why this machine cannot be STEPS_PROFILE.
steps_platform_mismatch() {
    local os id like
    os=$(bootstrap_os)
    case $STEPS_PROFILE in
        macos)
            [ "$os" = Darwin ] || printf 'host %s is macOS, but this kernel is %s\n' "$STEPS_HOST" "$os"
            ;;
        hpc)
            [ "$os" = Linux ] || printf 'host %s is a Linux cluster, but this kernel is %s\n' "$STEPS_HOST" "$os"
            ;;
        debian)
            if [ "$os" != Linux ]; then
                printf 'host %s is Debian or Ubuntu, but this kernel is %s\n' "$STEPS_HOST" "$os"
                return 0
            fi
            id=$(bootstrap_os_release_value ID)
            like=$(bootstrap_os_release_value ID_LIKE)
            case " $id $like " in
                *' debian '* | *' ubuntu '*) ;;
                *) printf 'host %s needs Debian or Ubuntu, but os-release says ID=%s\n' "$STEPS_HOST" "${id:-unknown}" ;;
            esac
            ;;
    esac
}

step_P0_preflight_check() {
    local glibc platform detail paths path missing=''
    glibc=$(bootstrap_glibc_version)
    platform=$(bootstrap_detect_platform)
    detail="host $STEPS_HOST, profile $STEPS_PROFILE, $(bootstrap_os) $STEPS_ARCH${glibc:+, glibc $glibc}, detected $platform, checkout $STEPS_ROOT"
    if [ -f "$STEPS_ROOT/.gitmodules" ]; then
        paths=$(git config -f "$STEPS_ROOT/.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null </dev/null) || paths=
        while IFS=' ' read -r _ path; do
            [ -n "$path" ] || continue
            [ -e "$STEPS_ROOT/$path/.git" ] || missing="$missing${missing:+ }$path"
        done <<EOF
$paths
EOF
    fi
    if [ -n "$missing" ]; then
        dotfiles_log warn "submodule not checked out ($missing): run git submodule update --init --recursive in $STEPS_ROOT"
        detail="$detail; submodule missing: $missing"
    fi
    if [ -n "${DOTFILES_DIR:-}" ] && [ "$DOTFILES_DIR" != "$STEPS_ROOT" ]; then
        dotfiles_log warn "DOTFILES_DIR is $DOTFILES_DIR, but this checkout is $STEPS_ROOT"
    fi
    STEP_DETAIL=$detail
    return 0
}
