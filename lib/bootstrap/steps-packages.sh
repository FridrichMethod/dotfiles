# shellcheck shell=bash
# shellcheck disable=SC2034 # STEP_DETAIL and the STEPS_* fields are read by steps.sh
# Package-manager steps of setup-host.sh: S2-brew-bundle (Brewfiles),
# S2-micromamba and S2-login-env (the hpc login env).
# Checks are read-only and offline; apply functions run in steps_guarded
# and report each failure explicitly. Sourced only (after steps.sh and
# steps-common.sh); defines functions and changes no shell options.

# --- S2-brew-bundle (macos, debian) ----------------------------------------

# A Brewfile entry is satisfied when Homebrew has it (an opt/ link, a
# Caskroom/ dir) or when the tool it installs is already there as the doctor
# judges it (steps_brew_entry_provided), whoever installed it: apt, conda or
# the OS. The goal is a green doctor, not a Homebrew copy of every tool; on a
# shared prefix such a copy would change every account's PATH.

# steps_brew_parse LINE: split one Brewfile line, leading blanks ignored,
# into STEPS_BREW_WORD (tap, brew or cask), STEPS_BREW_NAME (the quoted name,
# tap/name for a tap's formula) and STEPS_BREW_REST (the text after the
# closing quote, where an OS guard sits). 1, all three empty, for a comment
# or any other line.
steps_brew_parse() {
    local line=$1 gap
    STEPS_BREW_WORD='' STEPS_BREW_NAME='' STEPS_BREW_REST=''
    line=${line#"${line%%[![:space:]]*}"}
    case $line in
        tap[[:space:]]*\"*\"* | brew[[:space:]]*\"*\"* | cask[[:space:]]*\"*\"*) ;;
        *) return 1 ;;
    esac
    gap=${line#*[[:space:]]}
    gap=${gap%%\"*}
    case $gap in
        *[![:space:]]*) return 1 ;;
    esac
    STEPS_BREW_WORD=${line%%[[:space:]]*}
    line=${line#*\"}
    STEPS_BREW_NAME=${line%%\"*}
    STEPS_BREW_REST=${line#*\"}
}

# steps_brew_guard_applies TEXT: 0 when the TEXT after an entry's name has no
# OS guard, or the one under which brew bundle installs it on STEPS_PROFILE
# ("if OS.mac?" on macos, "if OS.linux?" elsewhere).
steps_brew_guard_applies() {
    case $1 in
        *'if OS.mac?'*) [ "$STEPS_PROFILE" = macos ] ;;
        *'if OS.linux?'*) [ "$STEPS_PROFILE" != macos ] ;;
    esac
}

# steps_brew_tool_id NAME: the tools.tsv row of this host that the Brewfile
# entry NAME (a tap's formula by its last segment) installs: the row whose id
# is NAME, else the first "# alias: TOOL-ID NAME" whose TOOL-ID has a row
# here. 1 when there is none.
steps_brew_tool_id() {
    local name=${1##*/} ids id
    if steps_tool_row "$name" >/dev/null; then
        printf '%s\n' "$name"
        return 0
    fi
    ids=$(bootstrap_tool_aliases "$name")$BOOTSTRAP_NL || return 1
    while [ -n "$ids" ]; do
        id=${ids%%"$BOOTSTRAP_NL"*}
        ids=${ids#*"$BOOTSTRAP_NL"}
        if [ -n "$id" ] && steps_tool_row "$id" >/dev/null; then
            printf '%s\n' "$id"
            return 0
        fi
    done
    return 1
}

# steps_brew_entry_provided NAME: 0 when the doctor would report the tool of
# the Brewfile entry NAME ok: its tools.tsv row (steps_brew_tool_id) passes
# bootstrap_check_tool, the doctor's own probe (found, and at or above the
# floor when the row has one; an unknown version against a floor does not
# pass). Read-only and offline, as the doctor is: it runs only the row's
# version flag, none for a presence-only row, under the GH_TELEMETRY=0 and
# TLDR_AUTO_UPDATE_DISABLED=1 that setup-host.sh exports.
steps_brew_entry_provided() {
    local id row probe flag floor absent
    id=$(steps_brew_tool_id "$1") || return 1
    row=$(steps_tool_row "$id") || return 1
    bootstrap_split "$BOOTSTRAP_TAB" "$row" _ _ _ probe flag floor absent _
    case $(bootstrap_check_tool "$probe" "$flag" "$floor" "$absent") in
        "ok$BOOTSTRAP_TAB"*) return 0 ;;
    esac
    return 1
}

# steps_brew_entry_missing PREFIX KIND NAME: 0 when PREFIX has no opt/ link
# (brew; Homebrew links aliases there too) or Caskroom/ dir (cask) for NAME
# and its tool is not provided otherwise (steps_brew_entry_provided).
steps_brew_entry_missing() {
    case $2 in
        brew) [ ! -e "$1/opt/${3##*/}" ] || return 1 ;;
        cask) [ ! -d "$1/Caskroom/${3##*/}" ] || return 1 ;;
    esac
    ! steps_brew_entry_provided "$3"
}

# steps_brewfile_filtered FILE: print the Brewfile that brew bundle gets for
# FILE here, built from its lines: every tap line (a bare entry name may come
# from any tap), and each brew or cask entry that applies on STEPS_PROFILE
# and whose tool is not provided otherwise (steps_brew_entry_provided).
# Returns 0 when it left out a provided entry and kept another, so brew
# bundle reads the printed lines (--file=-); 2 when every entry that applies
# here is provided, so brew has nothing to do; 1 when it left out none, or
# cannot read FILE, so brew bundle reads FILE itself, as without the filter.
steps_brewfile_filtered() {
    local text lines line kept='' entries=0 dropped=0
    text=$(cat -- "$1" 2>/dev/null) || return 1
    lines=$text$BOOTSTRAP_NL
    while [ -n "$lines" ]; do
        line=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        steps_brew_parse "$line" || continue
        if [ "$STEPS_BREW_WORD" != tap ]; then
            steps_brew_guard_applies "$STEPS_BREW_REST" || continue
            if steps_brew_entry_provided "$STEPS_BREW_NAME"; then
                dropped=1
                continue
            fi
            entries=$((entries + 1))
        fi
        kept="$kept${line#"${line%%[![:space:]]*}"}$BOOTSTRAP_NL"
    done
    printf '%s' "$kept"
    [ "$dropped" = 1 ] || return 1
    [ "$entries" -gt 0 ] || return 2
}

# steps_brew_bundle BREW FILE ARGS...: run `BREW bundle ARGS` for FILE less
# its provided entries (steps_brewfile_filtered): on FILE itself when none is
# left out, and otherwise on the kept lines through a pipe, as --file=-.
# brew bundle reopens /dev/stdin by path, which works on a pipe for the user
# who made it. No brew runs (status 0) when every entry is provided. Apply
# mode only: brew refreshes its API data over the network even with
# HOMEBREW_NO_AUTO_UPDATE.
steps_brew_bundle() {
    local brew=$1 file=$2 kept rc=0
    shift 2
    kept=$(steps_brewfile_filtered "$file") || rc=$?
    case $rc in
        0) printf '%s' "$kept" | "$brew" bundle "$@" --file=- ;;
        2) return 0 ;;
        *) "$brew" bundle "$@" --file "$file" </dev/null ;;
    esac
}

# steps_brew_pending BREW: the selected Brewfiles that `brew bundle check`
# does not consider satisfied once their provided entries are left out
# (steps_brew_bundle), one per line. Apply mode only.
steps_brew_pending() {
    local brew=$1 lines file
    lines=$(bootstrap_brewfiles "$STEPS_TIERS")$BOOTSTRAP_NL || true
    while [ -n "$lines" ]; do
        file=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        [ -n "$file" ] || continue
        if ! steps_brew_bundle "$brew" "$file" check --no-upgrade >/dev/null 2>&1; then
            printf '%s\n' "$file"
        fi
    done
}

# steps_brewfile_entries FILE KIND [PREFIX]: the KIND (brew or cask)
# entries of FILE that brew bundle installs on STEPS_PROFILE (OS guards
# honoured), space-separated as written (tap/name for a tap's formula); with
# PREFIX, only the missing ones (steps_brew_entry_missing). A read-only,
# offline estimate for --check.
steps_brewfile_entries() {
    local prefix=${3:-} text lines line name found=''
    text=$(cat -- "$1") || return 1
    lines=$text$BOOTSTRAP_NL
    while [ -n "$lines" ]; do
        line=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        steps_brew_parse "$line" || continue
        [ "$STEPS_BREW_WORD" = "$2" ] || continue
        steps_brew_guard_applies "$STEPS_BREW_REST" || continue
        name=$STEPS_BREW_NAME
        if [ -n "$prefix" ] && ! steps_brew_entry_missing "$prefix" "$2" "$name"; then
            continue
        fi
        found="$found${found:+ }$name"
    done
    printf '%s\n' "$found"
}

# steps_brewfile_missing PREFIX FILE: the brew and cask entries of FILE that
# are missing (steps_brew_entry_missing), space-separated.
steps_brewfile_missing() {
    local brews casks
    brews=$(steps_brewfile_entries "$2" brew "$1") || return 1
    casks=$(steps_brewfile_entries "$2" cask "$1") || return 1
    printf '%s\n' "$brews${brews:+${casks:+ }}$casks"
}

# steps_brew_pending_offline PREFIX: the selected Brewfiles with an entry
# missing (steps_brewfile_missing), one per line, without running brew.
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

# steps_brew_missing_detail PREFIX FILES: "core: fzf; cli: jq tldr", the
# missing entries (steps_brewfile_missing) of each of FILES (Brewfile paths,
# one per line); a Brewfile with none named stands alone.
steps_brew_missing_detail() {
    local lines file names detail=''
    lines=$2$BOOTSTRAP_NL
    while [ -n "$lines" ]; do
        file=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        [ -n "$file" ] || continue
        names=$(steps_brewfile_missing "$1" "$file" 2>/dev/null) || names=
        file=${file##*/}
        detail="$detail${detail:+; }${file%.Brewfile}${names:+: $names}"
    done
    printf '%s\n' "$detail"
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
    [ -n "$entry" ] || return 1
    steps_brew_guard_applies "$entry"
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

# steps_brew_owner_line WORDS [ENV]: one self-contained line that runs the
# STEPS_BREW_PREFIX brew with WORDS (already quoted) as STEPS_BREW_OWNER,
# with ENV (VAR=VALUE words) after the Homebrew variables every line sets:
# from /tmp, since brew refuses a working directory its user cannot read, in
# a subshell, so the cd never reaches the reader's shell. A note instead when
# no owner could be named.
steps_brew_owner_line() {
    local brew
    brew=$(steps_quote "$STEPS_BREW_PREFIX/bin/brew")
    if [ -z "$STEPS_BREW_OWNER" ]; then
        printf '# run as the owner of %s, which this run cannot name: %s%s %s\n' \
            "$STEPS_BREW_PREFIX" "${2:+$2 }" "$brew" "$1"
        return 0
    fi
    printf '(cd /tmp && sudo -u %s -H env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1%s %s %s)\n' \
        "$(steps_quote "$STEPS_BREW_OWNER")" "${2:+ $2}" "$brew" "$1"
}

# steps_brew_install_lines MODE FILE: the owner lines that install by name,
# formulae and casks apart, the missing entries of FILE
# (steps_brew_entry_missing; MODE manual: every entry that applies here), no
# line for a kind with none. brew never opens FILE, which the owner may not
# be able to read (a 0600 Brewfile, a closed home), and
# HOMEBREW_NO_INSTALL_UPGRADE=1 leaves an installed one alone, as
# --no-upgrade does. A FILE this user cannot read gets a note instead.
steps_brew_install_lines() {
    local kind names name words prefix=$STEPS_BREW_PREFIX
    [ "$1" != manual ] || prefix=''
    for kind in brew cask; do
        if ! names=$(steps_brewfile_entries "$2" "$kind" "$prefix" 2>/dev/null); then
            printf '# cannot read %s, so this block has no line for it\n' "$2"
            return 0
        fi
        words=''
        while [ -n "$names" ]; do
            bootstrap_split ' ' "$names" name names
            words="$words $(steps_quote "$name")"
        done
        [ -n "$words" ] || continue
        case $kind in
            brew) words="install --formula$words" ;;
            *) words="install --cask$words" ;;
        esac
        steps_brew_owner_line "$words" HOMEBREW_NO_INSTALL_UPGRADE=1
    done
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

# steps_brew_shared_block MODE FILES: the sudo block that installs, as the
# owner of the Homebrew prefix that steps_brew_access found locked, the
# missing entries of each of FILES (Brewfile paths, one per line;
# steps_brew_install_lines). MODE manual names every entry and adds the
# condition under which the block applies.
steps_brew_shared_block() {
    local lines file what='the missing entries of one Brewfile'
    steps_block_begin S2-brew-bundle sudo
    if [ "$1" = manual ]; then
        printf '%s\n' '# applies while you cannot write the Homebrew prefix (one shared with other accounts);' \
            '# ./setup-host.sh then stops S2-brew-bundle before running brew and prints this block for the missing entries'
        what='every entry of one Brewfile that applies here'
    fi
    steps_brew_shared_notes
    printf '# each line installs by name %s, from /tmp: brew never opens the Brewfile or your home, which %s may not be able to read\n' \
        "$what" "${STEPS_BREW_OWNER:-the owner}"
    if [ "$1" != manual ]; then
        printf '%s\n' '# an entry is missing when the prefix lacks it and the doctor does not find its tool installed another way (apt, conda, the OS): no second copy in the shared prefix'
    fi
    printf '%s\n' '# HOMEBREW_NO_INSTALL_UPGRADE=1 leaves an installed formula or cask alone, as brew bundle --no-upgrade does'
    lines=$2$BOOTSTRAP_NL
    while [ -n "$lines" ]; do
        file=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        [ -n "$file" ] || continue
        steps_brew_install_lines "$1" "$file"
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
    if [ -n "$STEPS_BREW_LOCKED" ]; then
        printf '%s\n' "# uninstall each conflicting formula or cask below as the owner; the next ./setup-host.sh run then prints the owner's lines that install the Brewfile one"
    else
        printf '%s\n' '# uninstall each conflicting formula or cask below; the next ./setup-host.sh run then bundles the Brewfile one'
    fi
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
    local files brew prefix pending note lines line kind name other file
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
    steps_load_tools
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
    note=" (offline estimate from $prefix/opt and the doctor's probes)"
    # A prefix this user cannot write: brew bundle would fail, so its owner
    # installs what the offline estimate finds missing, in apply mode too.
    if [ -n "$STEPS_BREW_LOCKED" ]; then
        pending=$(steps_brew_pending_offline "$prefix")
        if [ -z "$pending" ]; then
            STEP_DETAIL="Brewfiles satisfied: $(steps_brewfile_names "$files")$note; $prefix is shared, owned by ${STEPS_BREW_OWNER:-another account}"
            return 0
        fi
        STEPS_BREW_SHARED=$pending
        STEP_DETAIL="you cannot write the shared Homebrew prefix $prefix (owned by ${STEPS_BREW_OWNER:-another account}), so its owner installs the missing entries: $(steps_brew_missing_detail "$prefix" "$pending")$note"
        return 3
    fi
    if [ "$STEPS_MODE" = apply ]; then
        pending=$(steps_brew_pending "$brew")
        note=''
    else
        pending=$(steps_brew_pending_offline "$prefix")
        note="${note%)}; apply runs brew bundle check)"
    fi
    if [ -z "$pending" ]; then
        STEP_DETAIL="Brewfiles satisfied: $(steps_brewfile_names "$files")$note"
        return 0
    fi
    STEP_DETAIL="Brewfile entries to bundle: $(steps_brew_missing_detail "$prefix" "$pending")$note"
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
    printf 'brew bundle --no-upgrade for each config/bootstrap/brew/<tier>.Brewfile, less the entries whose tools the doctor already finds (%s)\n' "$STEP_DETAIL"
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

# Each pending Brewfile goes through steps_brew_bundle: brew bundle
# --no-upgrade still decides what to install, taps what a kept entry needs and
# upgrades nothing, after the conflict guard in the check, but never sees an
# entry whose tool apt, conda or the OS already provides at the doctor's
# floor. The kept lines reach it through a pipe as --file=-, which brew bundle
# reopens as /dev/stdin; that works for this user, unlike the shared-prefix
# owner, who therefore gets names on the command line instead.
step_S2_brew_bundle_apply() {
    local brew lines file
    if ! brew=$(bootstrap_brew_bin); then
        dotfiles_log error 'brew is not installed (H1-homebrew or H1-linuxbrew)'
        return 1
    fi
    steps_brew_access "${brew%/bin/brew}"
    if [ -n "$STEPS_BREW_LOCKED" ]; then
        dotfiles_log error "you cannot write $STEPS_BREW_LOCKED; its owner installs (the S2-brew-bundle sudo block)"
        return 1
    fi
    lines=$(steps_brew_pending "$brew")$BOOTSTRAP_NL || true
    while [ -n "$lines" ]; do
        file=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        [ -n "$file" ] || continue
        steps_brew_bundle "$brew" "$file" --no-upgrade >&2 || {
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
