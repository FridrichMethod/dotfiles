# shellcheck shell=bash
# shellcheck disable=SC2034 # STEP_DETAIL and the STEPS_* fields are read by steps.sh
# Package-manager steps of setup-host.sh: S2-brew-bundle (Brewfiles),
# S2-micromamba and S2-login-env (the hpc login env).
# Checks are read-only and offline; apply functions run in steps_guarded
# and report each failure explicitly. Sourced only (after steps.sh and
# steps-common.sh); defines functions and changes no shell options.

# --- S2-brew-bundle (macos, debian) ----------------------------------------

# steps_brew_pending BREW: the selected Brewfiles that `brew bundle check`
# does not consider satisfied, one per line. Apply mode only: brew refreshes
# its API data over the network even with HOMEBREW_NO_AUTO_UPDATE.
steps_brew_pending() {
    local brew=$1 lines file
    lines=$(bootstrap_brewfiles "$STEPS_TIERS")$BOOTSTRAP_NL || true
    while [ -n "$lines" ]; do
        file=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        [ -n "$file" ] || continue
        if ! "$brew" bundle check --no-upgrade --file "$file" >/dev/null 2>&1 </dev/null; then
            printf '%s\n' "$file"
        fi
    done
}

# steps_brewfile_missing PREFIX FILE: the brew and cask entries of FILE with
# no opt/ link or Caskroom/ dir under PREFIX, space-separated. A read-only,
# offline estimate for --check (Homebrew links opt/ for aliases too).
steps_brewfile_missing() {
    local prefix=$1 entries lines line kind name rest missing=''
    entries=$(sed -nE 's/^[[:space:]]*(brew|cask)[[:space:]]+"([^"]+)"[[:space:]]*(.*)$/\1 \2 \3/p' "$2") ||
        return 1
    lines=$entries$BOOTSTRAP_NL
    while [ -n "$lines" ]; do
        line=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        bootstrap_split ' ' "$line" kind name rest
        [ -n "$kind" ] || continue
        case $rest in
            *'if OS.mac?'*) [ "$STEPS_PROFILE" = macos ] || continue ;;
            *'if OS.linux?'*) [ "$STEPS_PROFILE" != macos ] || continue ;;
        esac
        name=${name##*/}
        case $kind in
            brew) [ -e "$prefix/opt/$name" ] && continue ;;
            cask) [ -d "$prefix/Caskroom/$name" ] && continue ;;
        esac
        missing="$missing${missing:+ }$name"
    done
    printf '%s\n' "$missing"
}

# steps_brew_pending_offline PREFIX: the selected Brewfiles with an entry
# missing from PREFIX, one per line, without running brew.
steps_brew_pending_offline() {
    local lines file
    lines=$(bootstrap_brewfiles "$STEPS_TIERS")$BOOTSTRAP_NL || true
    while [ -n "$lines" ]; do
        file=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        [ -n "$file" ] || continue
        if [ -n "$(steps_brewfile_missing "$1" "$file")" ]; then
            printf '%s\n' "$file"
        fi
    done
}

# steps_brewfile_names FILES: "core cli" from Brewfile paths.
steps_brewfile_names() {
    local lines file names=''
    lines=$1$BOOTSTRAP_NL
    while [ -n "$lines" ]; do
        file=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        [ -n "$file" ] || continue
        file=${file##*/}
        names="$names${names:+ }${file%.Brewfile}"
    done
    printf '%s\n' "$names"
}

# steps_brew_declared_conflicts: "FORMULA OTHER BREWFILE" for every pair that
# a selected Brewfile declares with a "# conflicts: FORMULA OTHER..." line:
# Homebrew refuses to install FORMULA while OTHER is installed (its
# conflicts_with), and brew bundle then fails with no more than that.
# tests/test_bootstrap_manifest.py validates the lines.
steps_brew_declared_conflicts() {
    local files decls file decl formula others other
    files=$(bootstrap_brewfiles "$STEPS_TIERS")$BOOTSTRAP_NL || true
    while [ -n "$files" ]; do
        file=${files%%"$BOOTSTRAP_NL"*}
        files=${files#*"$BOOTSTRAP_NL"}
        [ -n "$file" ] || continue
        decls=$(sed -n 's/^# conflicts: //p' "$file")$BOOTSTRAP_NL || continue
        while [ -n "$decls" ]; do
            decl=${decls%%"$BOOTSTRAP_NL"*}
            decls=${decls#*"$BOOTSTRAP_NL"}
            bootstrap_split ' ' "$decl" formula others
            while [ -n "$others" ]; do
                bootstrap_split ' ' "$others" other others
                if steps_safe_formula "$formula" && steps_safe_formula "$other"; then
                    printf '%s %s %s\n' "$formula" "$other" "${file##*/}"
                fi
            done
        done
    done
}

# steps_safe_formula NAME: 0 for a formula name that is a single path segment.
steps_safe_formula() {
    case $1 in
        '' | .* | *[!a-z0-9@+._-]*) return 1 ;;
    esac
}

# steps_brew_keg PREFIX NAME: 0 when formula NAME has a keg under PREFIX's
# Cellar, or under $HOMEBREW_CELLAR when that is set. Read-only and offline.
steps_brew_keg() {
    [ -d "$1/Cellar/$2" ] && return 0
    [ -n "${HOMEBREW_CELLAR:-}" ] && [ -d "$HOMEBREW_CELLAR/$2" ]
}

# steps_brew_conflicts PREFIX: the declared pairs that would stop brew bundle
# here: OTHER has a keg while FORMULA has neither a keg nor an opt/ link.
steps_brew_conflicts() {
    local lines line formula other
    lines=$(steps_brew_declared_conflicts)$BOOTSTRAP_NL || true
    while [ -n "$lines" ]; do
        line=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        bootstrap_split ' ' "$line" formula other _
        [ -n "$other" ] || continue
        if [ -e "$1/opt/$formula" ] || steps_brew_keg "$1" "$formula"; then
            continue
        fi
        if steps_brew_keg "$1" "$other"; then
            printf '%s\n' "$line"
        fi
    done
}

# steps_brew_conflict_block MODE PAIRS: the judgment block that uninstalls
# each conflicting formula of PAIRS ("FORMULA OTHER BREWFILE" lines). MODE
# manual lists every declared pair with the condition under which it applies.
steps_brew_conflict_block() {
    local brew lines line formula other file seen=' '
    brew=$(steps_quote "$(steps_brew_default)")
    steps_block_begin S2-brew-bundle judgment
    if [ "$1" = manual ]; then
        printf '%s\n' '# applies only when a conflicting formula below is installed and the Brewfile formula is not;' \
            '# ./setup-host.sh then stops S2-brew-bundle before running brew and prints this block'
    fi
    lines=$2$BOOTSTRAP_NL
    while [ -n "$lines" ]; do
        line=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        bootstrap_split ' ' "$line" formula other file
        [ -n "$file" ] || continue
        printf '# Homebrew does not install %s (%s) while the %s formula is installed (conflicts_with), so brew bundle would fail\n' \
            "$formula" "$file" "$other"
    done
    printf '%s\n' '# uninstall each conflicting formula below; the next ./setup-host.sh run then bundles the Brewfile one'
    lines=$2$BOOTSTRAP_NL
    while [ -n "$lines" ]; do
        line=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        bootstrap_split ' ' "$line" formula other file
        [ -n "$other" ] || continue
        case $seen in
            *" $other "*) continue ;;
        esac
        seen="$seen$other "
        printf '%s uninstall --formula %s\n' "$brew" "$other"
    done
    steps_block_end
}

step_S2_brew_bundle_check() {
    local files brew pending note='' lines line formula other file
    STEPS_BREW_CONFLICTS=
    files=$(bootstrap_brewfiles "$STEPS_TIERS")
    if [ -z "$files" ]; then
        STEP_DETAIL="no Brewfile for tiers $STEPS_TIERS"
        return 2
    fi
    if ! brew=$(bootstrap_brew_bin); then
        STEP_DETAIL="brew is not installed; Brewfiles: $(steps_brewfile_names "$files")"
        return 1
    fi
    # Before any brew command: a conflicting formula is a person's call.
    STEPS_BREW_CONFLICTS=$(steps_brew_conflicts "${brew%/bin/brew}")
    if [ -n "$STEPS_BREW_CONFLICTS" ]; then
        STEP_DETAIL=
        lines=$STEPS_BREW_CONFLICTS$BOOTSTRAP_NL
        while [ -n "$lines" ]; do
            line=${lines%%"$BOOTSTRAP_NL"*}
            lines=${lines#*"$BOOTSTRAP_NL"}
            bootstrap_split ' ' "$line" formula other file
            [ -n "$file" ] || continue
            STEP_DETAIL="$STEP_DETAIL${STEP_DETAIL:+; }the installed $other formula conflicts with $formula ($file)"
        done
        STEP_DETAIL="$STEP_DETAIL; brew bundle would fail, so uninstall it first"
        return 3
    fi
    if [ "$STEPS_MODE" = apply ]; then
        pending=$(steps_brew_pending "$brew")
    else
        pending=$(steps_brew_pending_offline "${brew%/bin/brew}")
        note=" (offline estimate from ${brew%/bin/brew}/opt; apply runs brew bundle check)"
    fi
    if [ -z "$pending" ]; then
        STEP_DETAIL="Brewfiles satisfied: $(steps_brewfile_names "$files")$note"
        return 0
    fi
    STEP_DETAIL="Brewfiles to bundle: $(steps_brewfile_names "$pending")$note"
    return 1
}

step_S2_brew_bundle_plan() {
    if [ -n "${STEPS_BREW_CONFLICTS:-}" ]; then
        steps_brew_conflict_block pending "$STEPS_BREW_CONFLICTS"
        return 0
    fi
    printf 'brew bundle --no-upgrade --file config/bootstrap/brew/<tier>.Brewfile (%s)\n' "$STEP_DETAIL"
}

step_S2_brew_bundle_manual() {
    local pairs
    pairs=$(steps_brew_declared_conflicts)
    [ -z "$pairs" ] || steps_brew_conflict_block manual "$pairs"
}

step_S2_brew_bundle_apply() {
    local brew lines file
    if ! brew=$(bootstrap_brew_bin); then
        dotfiles_log error 'brew is not installed (H1-homebrew or H1-linuxbrew)'
        return 1
    fi
    lines=$(steps_brew_pending "$brew")$BOOTSTRAP_NL || true
    while [ -n "$lines" ]; do
        file=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        [ -n "$file" ] || continue
        "$brew" bundle --no-upgrade --file "$file" >&2 </dev/null || {
            dotfiles_log error "brew bundle failed for $file"
            return 1
        }
    done
}

# --- S2-micromamba (hpc) ---------------------------------------------------

# steps_micromamba_bin: the pinned micromamba if installed, else one on PATH.
steps_micromamba_bin() {
    if steps_installer_fields micromamba && [ -x "$STEPS_DEST" ]; then
        printf '%s\n' "$STEPS_DEST"
        return 0
    fi
    command -v micromamba 2>/dev/null
}

step_S2_micromamba_check() {
    local found
    if ! steps_installer_fields micromamba; then
        STEP_DETAIL="no installers.tsv micromamba row for $STEPS_HOST $STEPS_ARCH"
        return 2
    fi
    # Present is enough: checks run no installed tool (some write state).
    if [ -x "$STEPS_DEST" ]; then
        STEP_DETAIL="micromamba at $STEPS_DEST"
        return 0
    fi
    if found=$(command -v micromamba 2>/dev/null) && [ -n "$found" ]; then
        STEP_DETAIL="micromamba on PATH at $found"
        return 0
    fi
    STEP_DETAIL="micromamba is not installed; pinned binary goes to $STEPS_DEST"
    return 1
}

step_S2_micromamba_plan() {
    steps_installer_fields micromamba || return 0
    printf 'download %s (sha256 %s) to %s\n' "$STEPS_URL" "$STEPS_SHA" "$STEPS_DEST"
}

step_S2_micromamba_apply() {
    steps_installer_fields micromamba || return 1
    bootstrap_fetch "$STEPS_URL" "$STEPS_DEST" "$STEPS_SHA" || return 1
    chmod 755 "$STEPS_DEST"
}

step_S2_micromamba_verify() {
    steps_installer_fields micromamba || return 1
    [ -x "$STEPS_DEST" ] && "$STEPS_DEST" --version >/dev/null 2>&1 </dev/null
}

# --- S2-login-env (hpc, allocation only) -----------------------------------

# steps_physical PATH: PATH with its deepest existing ancestor made physical.
steps_physical() {
    local path=${1%/} rest=''
    [ -n "$path" ] || path=/
    while [ ! -d "$path" ]; do
        rest="/${path##*/}$rest"
        path=${path%/*}
        [ -n "$path" ] || path=/
    done
    path=$(cd -P "$path" 2>/dev/null && pwd) || path=${1%/}
    printf '%s%s\n' "${path%/}" "$rest"
}

# steps_under_scratch PATH: 0 when PATH lies under $SCRATCH or
# $GROUP_SCRATCH, which are purged; prints the variable name.
steps_under_scratch() {
    local name base path physical
    path=${1%/}
    physical=$(steps_physical "$1")
    for name in SCRATCH GROUP_SCRATCH; do
        base=${!name-}
        base=${base%/}
        [ -n "$base" ] || continue
        case "$path/" in
            "$base"/*)
                printf '%s\n' "$name"
                return 0
                ;;
        esac
        case "$physical/" in
            "$(steps_physical "$base")"/*)
                printf '%s\n' "$name"
                return 0
                ;;
        esac
    done
    return 1
}

step_S2_login_env_check() {
    if steps_probe login-env; then
        STEP_DETAIL="login env at ${STEPS_PROBE_FOUND%/bin/zsh}"
        return 0
    fi
    STEP_DETAIL="create the login env from config/bootstrap/hpc-login-env.yml in $HOME/micromamba"
    return 1
}

step_S2_login_env_plan() {
    printf 'micromamba create -y -r %s -n login -f config/bootstrap/hpc-login-env.yml\n' "$HOME/micromamba"
}

step_S2_login_env_apply() {
    local root=$HOME/micromamba micromamba where
    if ! bootstrap_in_allocation; then
        dotfiles_log error 'refusing to build the login env outside a Slurm allocation (H2-alloc)'
        return 1
    fi
    if where=$(steps_under_scratch "$HOME") || where=$(steps_under_scratch "$root"); then
        dotfiles_log error "refusing to build the login env under \$$where, which is purged: $root"
        return 1
    fi
    if ! micromamba=$(steps_micromamba_bin); then
        dotfiles_log error 'micromamba is not installed (S2-micromamba)'
        return 1
    fi
    "$micromamba" create -y -r "$root" -n login -f "$BOOTSTRAP_CONFIG/hpc-login-env.yml" >&2 </dev/null
}
