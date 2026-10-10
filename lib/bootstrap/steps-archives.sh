# shellcheck shell=bash
# shellcheck disable=SC2034 # STEP_DETAIL and the STEPS_* fields are read by steps.sh
# Auto steps of setup-host.sh that unpack pinned release archives:
# S5-codex S6-nerd-font S6-kitty. Each archive is fetched to the scratch dir
# with its sha256 checked before tar reads it. Sourced only (after steps.sh
# and steps-common.sh); defines functions and changes no shell options.

# steps_fetch_archive ID: set the STEPS_* fields of installers.tsv row ID,
# download its archive into the scratch dir and set STEPS_ARCHIVE. Call it
# directly, not in $(...), so the fields reach the caller.
steps_fetch_archive() {
    if ! steps_installer_fields "$1"; then
        dotfiles_log error "no installers.tsv row for $1 on $STEPS_HOST $STEPS_ARCH"
        return 1
    fi
    STEPS_ARCHIVE=$(steps_scratch_file "$1" "$STEPS_URL")
    steps_make_scratch "$1" || return 1
    steps_fetch_pinned "$STEPS_URL" "$STEPS_ARCHIVE" "$STEPS_SHA"
}

# --- S5-codex (debian) -----------------------------------------------------

# steps_json_string FILE KEY: the string value of KEY in a flat JSON object.
steps_json_string() {
    tr ',{}' '\n\n\n' <"$1" |
        sed -n 's/^[[:space:]]*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)"[[:space:]]*$/\1/p' |
        sed -n 1p
}

# steps_safe_name WORD: 0 for a non-empty file name without "/" or a leading ".".
steps_safe_name() {
    case $1 in
        '' | .* | *[!A-Za-z0-9._-]*) return 1 ;;
    esac
}

# steps_codex_bin: the codex this host runs, ~/.local/bin first.
steps_codex_bin() {
    if [ -x "$HOME/.local/bin/codex" ]; then
        printf '%s\n' "$HOME/.local/bin/codex"
        return 0
    fi
    command -v codex 2>/dev/null
}

# steps_codex_package_version BIN: the version in the codex-package.json of
# the release BIN resolves into, read as a file: running `codex --version`
# writes ~/.codex/tmp, which a --check must not do. Empty for other installs.
steps_codex_package_version() {
    local binary release
    binary=$(steps_resolve "$1") || return 0
    release=$(dirname "$(dirname "$binary")")
    [ -f "$release/codex-package.json" ] || return 0
    steps_json_string "$release/codex-package.json" version 2>/dev/null || true
}

step_S5_codex_check() {
    local pin bin have
    if ! steps_installer_fields codex; then
        STEP_DETAIL="no installers.tsv codex row for $STEPS_HOST $STEPS_ARCH"
        return 2
    fi
    pin=$(bootstrap_extract_version "$STEPS_URL")
    if ! bin=$(steps_codex_bin); then
        STEP_DETAIL="codex is not installed; pinned ${pin:-release} goes to $STEPS_DEST"
        return 1
    fi
    have=$(steps_codex_package_version "$bin")
    if [ -z "$have" ]; then
        STEP_DETAIL="codex at $bin is not a codex-package install; ./doctor.sh reports its version"
        return 0
    fi
    if [ -n "$pin" ] && bootstrap_version_ge "$have" "$pin"; then
        STEP_DETAIL="codex $have at $bin"
        return 0
    fi
    STEP_DETAIL="codex $have at $bin is older than the pinned ${pin:-release}"
    return 1
}

step_S5_codex_plan() {
    steps_installer_fields codex || return 0
    printf 'unpack %s into %s/releases, link current and ~/.local/bin/codex\n' "${STEPS_URL##*/}" "$STEPS_DEST"
}

# The upstream codex-package layout, as OpenAI's install.sh lays it out
# (without running that script): releases/<version>-<target> holding the
# flat archive plus the relative link codex -> bin/codex, current -> that
# release, and ~/.local/bin/codex -> current/bin/codex.
step_S5_codex_apply() {
    local archive dest tmp version target release
    steps_fetch_archive codex || return 1
    archive=$STEPS_ARCHIVE
    dest=$STEPS_DEST
    mkdir -p "$dest/releases" || return 1
    tmp=$(steps_new_dir "$dest" extract) || return 1
    if ! tar -xzof "$archive" -C "$tmp" </dev/null; then
        rm -rf "$tmp"
        dotfiles_log error "cannot unpack $archive"
        return 1
    fi
    version=$(steps_json_string "$tmp/codex-package.json" version 2>/dev/null) || version=
    target=$(steps_json_string "$tmp/codex-package.json" target 2>/dev/null) || target=
    if ! steps_safe_name "$version" || ! steps_safe_name "$target"; then
        rm -rf "$tmp"
        dotfiles_log error "codex-package.json has no usable version and target: [$version] [$target]"
        return 1
    fi
    if [ ! -x "$tmp/bin/codex" ]; then
        rm -rf "$tmp"
        dotfiles_log error "the codex package has no executable bin/codex"
        return 1
    fi
    release=$dest/releases/$version-$target
    if [ -d "$release" ]; then
        if ! cmp -s "$release/codex-package.json" "$tmp/codex-package.json"; then
            rm -rf "$tmp"
            dotfiles_log error "$release exists with a different codex-package.json; move it aside"
            return 1
        fi
        rm -rf "$tmp"
    else
        ln -s bin/codex "$tmp/codex" || {
            rm -rf "$tmp"
            return 1
        }
        mv "$tmp" "$release" || {
            rm -rf "$tmp"
            return 1
        }
    fi
    if [ ! -L "$release/codex" ]; then
        ln -s bin/codex "$release/codex" || return 1
    fi
    ln -sfn "$release" "$dest/current" || return 1
    mkdir -p "$HOME/.local/bin" || return 1
    ln -sfn "$dest/current/bin/codex" "$HOME/.local/bin/codex"
}

step_S5_codex_verify() {
    local version output
    steps_installer_fields codex || return 1
    version=$(steps_json_string "$STEPS_DEST/current/codex-package.json" version) || return 1
    output=$("$HOME/.local/bin/codex" --version 2>&1 </dev/null) || return 1
    case $output in
        *"$version"*) return 0 ;;
    esac
    dotfiles_log error "codex --version reports [$output], expected $version"
    return 1
}

# --- S6-nerd-font (lab-ubuntu) ---------------------------------------------

# steps_font_present DIR: 0 when DIR holds the font files, named after DIR
# (CaskaydiaMonoNerdFont-*.ttf), or the user font dirs already have them.
steps_font_present() {
    local dir=$1 prefix found
    prefix=${dir##*/}
    set -- "$dir/$prefix"*.ttf
    [ ! -f "$1" ] || return 0
    found=$(find "${XDG_DATA_HOME:-$HOME/.local/share}/fonts" "$HOME/.fonts" -maxdepth 3 \
        -name "$prefix*.ttf" -print 2>/dev/null </dev/null | sed -n 1p) || found=
    [ -n "$found" ]
}

step_S6_nerd_font_check() {
    if ! steps_installer_fields nerd-font; then
        STEP_DETAIL="no installers.tsv nerd-font row for $STEPS_HOST"
        return 2
    fi
    if steps_font_present "$STEPS_DEST"; then
        STEP_DETAIL="${STEPS_DEST##*/} font files are installed"
        return 0
    fi
    STEP_DETAIL="${STEPS_DEST##*/} is not installed in $STEPS_DEST"
    return 1
}

step_S6_nerd_font_plan() {
    steps_installer_fields nerd-font || return 0
    printf 'unpack %s into %s, then fc-cache -f\n' "${STEPS_URL##*/}" "$STEPS_DEST"
}

step_S6_nerd_font_apply() {
    steps_fetch_archive nerd-font || return 1
    mkdir -p "$STEPS_DEST" || return 1
    tar -C "$STEPS_DEST" -xJof "$STEPS_ARCHIVE" </dev/null || return 1
    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f >&2 </dev/null || return 1
    fi
}

# --- S6-kitty (lab-ubuntu) -------------------------------------------------

# steps_kitty_state: done, or what is missing from the kitty install.
steps_kitty_state() {
    local tool want
    if [ ! -x "$STEPS_DEST/bin/kitty" ]; then
        printf '%s\n' "no kitty in $STEPS_DEST"
        return 1
    fi
    for tool in kitty kitten; do
        want=$(steps_resolve "$STEPS_DEST/bin/$tool") || want=
        if [ -z "$want" ] || [ "$(steps_resolve "$HOME/.local/bin/$tool" 2>/dev/null)" != "$want" ]; then
            printf '%s\n' "$HOME/.local/bin/$tool does not link to $STEPS_DEST/bin/$tool"
            return 1
        fi
    done
    printf '%s\n' "kitty in $STEPS_DEST, linked from $HOME/.local/bin"
}

step_S6_kitty_check() {
    if ! steps_installer_fields kitty; then
        STEP_DETAIL="no installers.tsv kitty row for $STEPS_HOST $STEPS_ARCH"
        return 2
    fi
    STEP_DETAIL=$(steps_kitty_state) && return 0
    return 1
}

step_S6_kitty_plan() {
    steps_installer_fields kitty || return 0
    printf 'unpack %s into %s, link kitty and kitten into ~/.local/bin\n' "${STEPS_URL##*/}" "$STEPS_DEST"
}

step_S6_kitty_apply() {
    local tmp tool
    steps_installer_fields kitty || return 1
    if [ ! -x "$STEPS_DEST/bin/kitty" ]; then
        if [ -e "$STEPS_DEST" ] || [ -L "$STEPS_DEST" ]; then
            dotfiles_log error "$STEPS_DEST exists without bin/kitty; move it aside"
            return 1
        fi
        steps_fetch_archive kitty || return 1
        mkdir -p "$(dirname "$STEPS_DEST")" || return 1
        tmp=$(steps_new_dir "$(dirname "$STEPS_DEST")" kitty-app) || return 1
        if ! tar -C "$tmp" -xJof "$STEPS_ARCHIVE" </dev/null || [ ! -x "$tmp/bin/kitty" ]; then
            rm -rf "$tmp"
            dotfiles_log error "cannot unpack kitty from $STEPS_ARCHIVE"
            return 1
        fi
        mv "$tmp" "$STEPS_DEST" || {
            rm -rf "$tmp"
            return 1
        }
    fi
    mkdir -p "$HOME/.local/bin" || return 1
    for tool in kitty kitten; do
        ln -sfn "$STEPS_DEST/bin/$tool" "$HOME/.local/bin/$tool" || return 1
    done
}
