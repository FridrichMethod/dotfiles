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

# steps_brew_declared_conflicts: "KIND NAME OTHER BREWFILE" (KIND formula or
# cask) for every pair that a selected Brewfile declares, in a
# "# conflicts: FORMULA OTHER..." or "# conflicts: cask TOKEN OTHER..." line:
# Homebrew refuses to install NAME while OTHER is installed (its
# conflicts_with), and brew bundle then fails with no more than that. A pair
# counts only where brew bundle installs NAME (a cask under "if OS.mac?"
# never on Linux). tests/test_bootstrap_manifest.py validates the lines.
steps_brew_declared_conflicts() {
    local files decls file decl kind name others other
    files=$(bootstrap_brewfiles "$STEPS_TIERS")$BOOTSTRAP_NL || true
    while [ -n "$files" ]; do
        file=${files%%"$BOOTSTRAP_NL"*}
        files=${files#*"$BOOTSTRAP_NL"}
        [ -n "$file" ] || continue
        decls=$(sed -n 's/^# conflicts: //p' "$file")$BOOTSTRAP_NL || continue
        while [ -n "$decls" ]; do
            decl=${decls%%"$BOOTSTRAP_NL"*}
            decls=${decls#*"$BOOTSTRAP_NL"}
            kind=formula
            case $decl in
                'cask '*)
                    kind=cask
                    decl=${decl#cask }
                    ;;
            esac
            bootstrap_split ' ' "$decl" name others
            steps_safe_formula "$name" || continue
            steps_brew_entry_applies "$file" "$kind" "$name" || continue
            while [ -n "$others" ]; do
                bootstrap_split ' ' "$others" other others
                if steps_safe_formula "$other"; then
                    printf '%s %s %s %s\n' "$kind" "$name" "$other" "${file##*/}"
                fi
            done
        done
    done
}

# steps_brew_entry_applies FILE KIND NAME: 0 when FILE has a KIND (formula
# or cask) entry NAME that brew bundle installs on STEPS_PROFILE: one
# without an OS guard, or with the matching "if OS.mac?" or "if OS.linux?".
steps_brew_entry_applies() {
    local word=brew entry
    [ "$2" = formula ] || word=cask
    entry=$(awk -v word="$word" -v name="\"$3\"" \
        '$1 == word && $2 == name { print "entry " $0; exit }' "$1") || return 1
    case $entry in
        '') return 1 ;;
        *'if OS.mac?'*) [ "$STEPS_PROFILE" = macos ] ;;
        *'if OS.linux?'*) [ "$STEPS_PROFILE" != macos ] ;;
    esac
}

# steps_safe_formula NAME: 0 for a formula or cask name that is a single
# path segment.
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

# steps_brew_installed PREFIX KIND NAME: 0 when formula NAME has a keg
# (steps_brew_keg) or cask NAME a Caskroom/ dir under PREFIX. Read-only and
# offline.
steps_brew_installed() {
    case $2 in
        cask) [ -d "$1/Caskroom/$3" ] ;;
        *) steps_brew_keg "$1" "$3" ;;
    esac
}

# steps_brew_conflicts PREFIX: the declared pairs that would stop brew bundle
# here: OTHER is installed (a keg, or a Caskroom/ dir) while NAME is not
# (neither a keg nor an opt/ link, or no Caskroom/ dir).
steps_brew_conflicts() {
    local lines line kind name other
    lines=$(steps_brew_declared_conflicts)$BOOTSTRAP_NL || true
    while [ -n "$lines" ]; do
        line=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        bootstrap_split ' ' "$line" kind name other _
        [ -n "$other" ] || continue
        if steps_brew_installed "$1" "$kind" "$name"; then
            continue
        fi
        if [ "$kind" = formula ] && [ -e "$1/opt/$name" ]; then
            continue
        fi
        if steps_brew_installed "$1" "$kind" "$other"; then
            printf '%s\n' "$line"
        fi
    done
}

# steps_brew_repository PREFIX: what `brew --repository` prints, from the
# prefix alone: PREFIX/Homebrew on Linux and for /usr/local (Intel macOS);
# /opt/homebrew (Apple Silicon) and any other macOS prefix are their own
# repository.
steps_brew_repository() {
    case $STEPS_PROFILE:$1 in
        macos:/usr/local) printf '%s\n' /usr/local/Homebrew ;;
        macos:*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$1/Homebrew" ;;
    esac
}

# steps_path_owner PATH: the account that owns PATH: GNU stat, BSD (macOS)
# stat, then ls -ld, whose numeric uid becomes sudo's #UID. Empty when none
# names one. Read-only.
steps_path_owner() {
    local owner
    owner=$(stat -c %U -- "$1" 2>/dev/null </dev/null) ||
        owner=$(stat -f %Su -- "$1" 2>/dev/null </dev/null) || owner=
    case $owner in
        '' | UNKNOWN | *[[:space:]]*)
            owner=$(LC_ALL=C ls -ld -- "$1" 2>/dev/null | awk 'NR == 1 { print $3 }') || owner=
            ;;
    esac
    case $owner in
        '' | *[[:space:]]*) return 0 ;;
        *[!0-9]*) printf '%s\n' "$owner" ;;
        *) printf '#%s\n' "$owner" ;;
    esac
}

# steps_brew_access PREFIX: set STEPS_BREW_PREFIX, STEPS_BREW_LOCKED (the
# Cellar, bin and repository dirs of PREFIX that this user cannot write,
# comma-separated; a missing dir counts as its parent, where brew creates it)
# and STEPS_BREW_OWNER (the owner of the first of them). brew refuses to
# install into a prefix it cannot write, as on a shared Linuxbrew owned by
# another account. Read-only ([ -w ]); call it in the shell that uses them.
steps_brew_access() {
    local dir found
    STEPS_BREW_PREFIX=$1 STEPS_BREW_LOCKED='' STEPS_BREW_OWNER=''
    for dir in "$1/Cellar" "$1/bin" "$(steps_brew_repository "$1")"; do
        found=$dir
        [ -e "$found" ] || found=${found%/*}
        [ ! -w "$found" ] || continue
        [ -n "$STEPS_BREW_LOCKED" ] || STEPS_BREW_OWNER=$(steps_path_owner "$found")
        STEPS_BREW_LOCKED="$STEPS_BREW_LOCKED${STEPS_BREW_LOCKED:+, }$dir"
    done
}

# steps_brew_owner_line WORDS: one self-contained line that runs the
# STEPS_BREW_PREFIX brew with WORDS (already quoted) as STEPS_BREW_OWNER:
# from /tmp, since brew refuses a working directory its user cannot read, in
# a subshell, so the cd never reaches the reader's shell. A note instead when
# no owner could be named.
steps_brew_owner_line() {
    local brew
    brew=$(steps_quote "$STEPS_BREW_PREFIX/bin/brew")
    if [ -z "$STEPS_BREW_OWNER" ]; then
        printf '# run as the owner of %s, which this run cannot name: %s %s\n' "$STEPS_BREW_PREFIX" "$brew" "$1"
        return 0
    fi
    printf '(cd /tmp && sudo -u %s -H env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1 %s %s)\n' \
        "$(steps_quote "$STEPS_BREW_OWNER")" "$brew" "$1"
}

# steps_brew_shared_notes: the notes of a block that runs brew as the owner
# of a prefix this user cannot write.
steps_brew_shared_notes() {
    local owner=${STEPS_BREW_OWNER:-another account}
    printf '# the Homebrew prefix %s is shared and owned by %s; you cannot write %s\n' \
        "$STEPS_BREW_PREFIX" "$owner" "$STEPS_BREW_LOCKED"
    printf '# the lines below run brew as %s and change the prefix for everyone on this machine\n' "$owner"
    printf '# never chown a shared prefix: it belongs to %s and serves every account here\n' "$owner"
}

# steps_brew_shared_block MODE FILES: the sudo block that bundles each of
# FILES (Brewfile paths, one per line) as the owner of the Homebrew prefix
# that steps_brew_access found locked. brew reads each Brewfile on stdin,
# which your shell opens, because the owner may not be able to read your
# home. MODE manual adds the condition under which the block applies.
steps_brew_shared_block() {
    local lines file
    steps_block_begin S2-brew-bundle sudo
    if [ "$1" = manual ]; then
        printf '%s\n' '# applies while you cannot write the Homebrew prefix (one shared with other accounts);' \
            '# ./setup-host.sh then stops S2-brew-bundle before running brew and prints this block for the pending Brewfiles'
    fi
    steps_brew_shared_notes
    printf '# each line installs one Brewfile, read on stdin and run from /tmp, since %s may not be able to read your home\n' \
        "${STEPS_BREW_OWNER:-the owner}"
    lines=$2$BOOTSTRAP_NL
    while [ -n "$lines" ]; do
        file=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        [ -n "$file" ] || continue
        steps_brew_owner_line "bundle --no-upgrade --file=- < $(steps_quote "$file")"
    done
    steps_block_end
}

# steps_brew_conflict_block MODE PAIRS: the judgment block that uninstalls
# each conflicting formula or cask of PAIRS ("KIND NAME OTHER BREWFILE"
# lines), as the prefix's owner when steps_brew_access found it locked.
# MODE manual lists every declared pair with the condition under which it
# applies.
steps_brew_conflict_block() {
    local brew lines line kind name other file seen=' '
    brew=$(steps_quote "$(steps_brew_default)")
    steps_block_begin S2-brew-bundle judgment
    if [ "$1" = manual ]; then
        printf '%s\n' '# applies only when a conflicting formula or cask below is installed and the Brewfile one is not;' \
            '# ./setup-host.sh then stops S2-brew-bundle before running brew and prints this block'
    fi
    [ -z "$STEPS_BREW_LOCKED" ] || steps_brew_shared_notes
    lines=$2$BOOTSTRAP_NL
    while [ -n "$lines" ]; do
        line=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        bootstrap_split ' ' "$line" kind name other file
        [ -n "$file" ] || continue
        printf '# Homebrew does not install %s (%s) while the %s %s is installed (conflicts_with), so brew bundle would fail\n' \
            "$name" "$file" "$other" "$kind"
    done
    printf '%s\n' '# uninstall each conflicting formula or cask below; the next ./setup-host.sh run then bundles the Brewfile one'
    lines=$2$BOOTSTRAP_NL
    while [ -n "$lines" ]; do
        line=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        bootstrap_split ' ' "$line" kind name other file
        [ -n "$other" ] || continue
        case $seen in
            *" $kind:$other "*) continue ;;
        esac
        seen="$seen$kind:$other "
        if [ -n "$STEPS_BREW_LOCKED" ]; then
            steps_brew_owner_line "uninstall --$kind $other"
        else
            printf '%s uninstall --%s %s\n' "$brew" "$kind" "$other"
        fi
    done
    steps_block_end
}

step_S2_brew_bundle_check() {
    local files brew prefix pending note='' lines line kind name other file
    STEPS_BREW_CONFLICTS='' STEPS_BREW_SHARED='' STEPS_BREW_LOCKED='' STEPS_BREW_OWNER=''
    files=$(bootstrap_brewfiles "$STEPS_TIERS")
    if [ -z "$files" ]; then
        STEP_DETAIL="no Brewfile for tiers $STEPS_TIERS"
        return 2
    fi
    if ! brew=$(bootstrap_brew_bin); then
        STEP_DETAIL="brew is not installed; Brewfiles: $(steps_brewfile_names "$files")"
        return 1
    fi
    prefix=${brew%/bin/brew}
    steps_brew_access "$prefix"
    # Before any brew command: a conflicting formula is a person's call.
    STEPS_BREW_CONFLICTS=$(steps_brew_conflicts "$prefix")
    if [ -n "$STEPS_BREW_CONFLICTS" ]; then
        STEP_DETAIL=
        lines=$STEPS_BREW_CONFLICTS$BOOTSTRAP_NL
        while [ -n "$lines" ]; do
            line=${lines%%"$BOOTSTRAP_NL"*}
            lines=${lines#*"$BOOTSTRAP_NL"}
            bootstrap_split ' ' "$line" kind name other file
            [ -n "$file" ] || continue
            STEP_DETAIL="$STEP_DETAIL${STEP_DETAIL:+; }the installed $other $kind conflicts with $name ($file)"
        done
        STEP_DETAIL="$STEP_DETAIL; brew bundle would fail, so uninstall it first"
        return 3
    fi
    # A prefix this user cannot write: brew bundle would fail, so its owner
    # bundles what the offline estimate finds missing, in apply mode too.
    if [ -n "$STEPS_BREW_LOCKED" ]; then
        pending=$(steps_brew_pending_offline "$prefix")
        note=" (offline estimate from $prefix/opt)"
        if [ -z "$pending" ]; then
            STEP_DETAIL="Brewfiles satisfied: $(steps_brewfile_names "$files")$note; $prefix is shared, owned by ${STEPS_BREW_OWNER:-another account}"
            return 0
        fi
        STEPS_BREW_SHARED=$pending
        STEP_DETAIL="you cannot write the shared Homebrew prefix $prefix (owned by ${STEPS_BREW_OWNER:-another account}), so its owner bundles: $(steps_brewfile_names "$pending")$note"
        return 3
    fi
    if [ "$STEPS_MODE" = apply ]; then
        pending=$(steps_brew_pending "$brew")
    else
        pending=$(steps_brew_pending_offline "$prefix")
        note=" (offline estimate from $prefix/opt; apply runs brew bundle check)"
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
    if [ -n "${STEPS_BREW_SHARED:-}" ]; then
        steps_brew_shared_block pending "$STEPS_BREW_SHARED"
        return 0
    fi
    printf 'brew bundle --no-upgrade --file config/bootstrap/brew/<tier>.Brewfile (%s)\n' "$STEP_DETAIL"
}

# The shared-prefix block needs a prefix and its owner, so --print-manual
# prints it only where this user cannot write the prefix brew is in.
step_S2_brew_bundle_manual() {
    local pairs brew
    STEPS_BREW_LOCKED='' STEPS_BREW_OWNER=''
    if brew=$(bootstrap_brew_bin); then
        steps_brew_access "${brew%/bin/brew}"
    fi
    pairs=$(steps_brew_declared_conflicts)
    [ -z "$pairs" ] || steps_brew_conflict_block manual "$pairs"
    [ -z "$STEPS_BREW_LOCKED" ] || steps_brew_shared_block manual "$(bootstrap_brewfiles "$STEPS_TIERS")"
}

step_S2_brew_bundle_apply() {
    local brew lines file
    if ! brew=$(bootstrap_brew_bin); then
        dotfiles_log error 'brew is not installed (H1-homebrew or H1-linuxbrew)'
        return 1
    fi
    steps_brew_access "${brew%/bin/brew}"
    if [ -n "$STEPS_BREW_LOCKED" ]; then
        dotfiles_log error "you cannot write $STEPS_BREW_LOCKED; its owner bundles (the S2-brew-bundle sudo block)"
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
