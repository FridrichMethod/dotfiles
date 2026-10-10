# shellcheck shell=bash
# shellcheck disable=SC2034 # STEP_DETAIL and the STEPS_* fields are read by steps.sh
# Home-file steps of setup-host.sh: S3-clones (git clones of default branches),
# S3-bat-theme and S3-dirs.
# Checks are read-only and offline; apply functions run in steps_guarded
# and report each failure explicitly. Sourced only (after steps.sh and
# steps-common.sh); defines functions and changes no shell options.

# --- S3-clones (unix) ------------------------------------------------------

# Clones track their upstream default branch (the ref column names it): a
# missing one is cloned shallowly from that branch, and an existing git
# checkout is never fetched, moved or checked for local changes, the way
# oh-my-zsh's own auto-update owns ~/.oh-my-zsh. Updating them is a person's
# call (docs/bootstrap.md S3-clones).

# steps_clone_state ID DEST: clone (missing), done (an existing checkout, left
# as it is), recovery (an oh-my-zsh dir without oh-my-zsh.sh) or foreign (it
# exists but is not a git checkout).
steps_clone_state() {
    if [ ! -e "$2" ] && [ ! -L "$2" ]; then
        echo clone
        return 0
    fi
    if [ "$1" = oh-my-zsh ]; then
        if [ -f "$2/oh-my-zsh.sh" ]; then echo 'done'; else echo recovery; fi
        return 0
    fi
    if [ -d "$2" ] && { [ -d "$2/.git" ] || [ -f "$2/.git" ]; }; then
        echo 'done'
    else
        echo foreign
    fi
}

# steps_clone_head DEST: "BRANCH@COMMIT" of the checkout DEST, for the plan
# line only ("detached" for a detached HEAD, "?" when git cannot tell).
# Read-only and offline.
steps_clone_head() {
    local branch commit
    if [ ! -d "$1/.git" ] && [ ! -f "$1/.git" ]; then
        printf '%s\n' 'not a git checkout'
        return 0
    fi
    # symbolic-ref -q exits 1 for a detached HEAD, 128 for an error.
    branch=$(git -C "$1" symbolic-ref -q --short HEAD 2>/dev/null </dev/null) || {
        if [ "$?" = 1 ]; then branch=detached; else branch='?'; fi
    }
    commit=$(git -C "$1" rev-parse -q --verify --short HEAD 2>/dev/null </dev/null) || commit='?'
    printf '%s@%s\n' "${branch:-?}" "${commit:-?}"
}

# steps_clone_rows: git-clones.tsv rows of this host with expanded dests,
# oh-my-zsh first (every other clone lands under its custom/ dir).
steps_clone_rows() {
    local rows lines row id dest rest pass
    rows=$(bootstrap_clone_rows "$STEPS_HOST") || return 1
    for pass in first rest; do
        lines=$rows$BOOTSTRAP_NL
        while [ -n "$lines" ]; do
            row=${lines%%"$BOOTSTRAP_NL"*}
            lines=${lines#*"$BOOTSTRAP_NL"}
            [ -n "$row" ] || continue
            bootstrap_split "$BOOTSTRAP_TAB" "$row" id dest rest
            case $pass:$id in
                first:oh-my-zsh | rest:*) ;;
                *) continue ;;
            esac
            [ "$pass:$id" != rest:oh-my-zsh ] || continue
            dest=$(bootstrap_expand_path "$dest") || return 1
            printf '%s\t%s\t%s\n' "$id" "$dest" "$rest"
        done
    done
}

step_S3_clones_check() {
    local rows lines row id dest url ref present='' count=0 todo='' bad=''
    STEPS_OMZ_RECOVERY=
    if ! rows=$(steps_clone_rows); then
        STEP_DETAIL='cannot read config/bootstrap/git-clones.tsv'
        return 1
    fi
    if [ -z "$rows" ]; then
        STEP_DETAIL="no clones for $STEPS_HOST"
        return 2
    fi
    lines=$rows$BOOTSTRAP_NL
    while [ -n "$lines" ]; do
        row=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        bootstrap_split "$BOOTSTRAP_TAB" "$row" id dest url ref _
        [ -n "$id" ] || continue
        case $(steps_clone_state "$id" "$dest") in
            done)
                count=$((count + 1))
                present="$present${present:+, }$id $(steps_clone_head "$dest")"
                ;;
            recovery) STEPS_OMZ_RECOVERY=$dest ;;
            clone) todo="$todo${todo:+ }$id ($ref)" ;;
            *) bad="$bad${bad:+ }$id" ;;
        esac
    done
    if [ -n "$STEPS_OMZ_RECOVERY" ]; then
        STEP_DETAIL="$STEPS_OMZ_RECOVERY exists without oh-my-zsh.sh (stow ran before the clone); recover it by hand"
        return 3
    fi
    if [ -z "$todo$bad" ]; then
        STEP_DETAIL="$count clones present, left as they are: $present"
        return 0
    fi
    STEP_DETAIL="${todo:+to clone: $todo}${todo:+${bad:+; }}${bad:+apply fails, not a git checkout: $bad}"
    STEP_DETAIL="$STEP_DETAIL${present:+; present, left as they are: $present}"
    return 1
}

# steps_omz_recovery_block DEST: put an oh-my-zsh checkout under the dir that
# ./stow-all.sh created first; the stowed custom/ files stay untracked there.
steps_omz_recovery_block() {
    local dest url='' q lines row key row_url
    dest=$1
    lines=$(bootstrap_clone_rows "$STEPS_HOST")$BOOTSTRAP_NL || true
    while [ -n "$lines" ]; do
        row=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        bootstrap_split "$BOOTSTRAP_TAB" "$row" key _ row_url _ _
        if [ "$key" = oh-my-zsh ]; then
            url=$row_url
            break
        fi
    done
    [ -n "$url" ] || url=https://github.com/ohmyzsh/ohmyzsh.git
    q=$(steps_quote "$dest")
    steps_block_begin X-recovery judgment
    printf '# %s exists without oh-my-zsh.sh: ./stow-all.sh ran before S3-clones.\n' "$dest"
    printf '%s\n' '# Turn it into the oh-my-zsh checkout in place, then rerun ./setup-host.sh:'
    printf 'git -C %s init\n' "$q"
    for key in core.eol=lf core.autocrlf=false fsck.zeroPaddedFilemode=ignore \
        fetch.fsck.zeroPaddedFilemode=ignore receive.fsck.zeroPaddedFilemode=ignore \
        oh-my-zsh.remote=origin oh-my-zsh.branch=master; do
        printf 'git -C %s config %s %s\n' "$q" "${key%%=*}" "${key#*=}"
    done
    printf 'git -C %s remote add origin %s\n' "$q" "$url"
    printf 'git -C %s fetch --depth=1 origin master\n' "$q"
    printf 'git -C %s checkout -b master origin/master\n' "$q"
    steps_block_end
}

step_S3_clones_plan() {
    if [ -n "${STEPS_OMZ_RECOVERY:-}" ]; then
        steps_omz_recovery_block "$STEPS_OMZ_RECOVERY"
    else
        printf 'shallow clones of the branches in config/bootstrap/git-clones.tsv: %s\n' "$STEP_DETAIL"
    fi
}

step_S3_clones_manual() {
    printf '%s\n' '# X-recovery applies only when ~/.oh-my-zsh exists without oh-my-zsh.sh'
    steps_omz_recovery_block "$(bootstrap_expand_path "\$HOME/.oh-my-zsh")"
}

# steps_clone_apply ID DEST URL REF: clone a missing DEST from branch REF;
# leave an existing checkout alone. git clone removes what it created when it
# fails, so a failed clone leaves no partial DEST behind.
steps_clone_apply() {
    local id=$1 dest=$2 url=$3 ref=$4
    case $(steps_clone_state "$id" "$dest") in
        done) return 0 ;;
        clone)
            mkdir -p "$(dirname "$dest")" || return 1
            if [ "$id" = oh-my-zsh ]; then
                # As the official installer clones it, so its self-update works.
                git clone -q --depth=1 --branch "$ref" -c core.eol=lf -c core.autocrlf=false \
                    -c fsck.zeroPaddedFilemode=ignore -c fetch.fsck.zeroPaddedFilemode=ignore \
                    -c receive.fsck.zeroPaddedFilemode=ignore -c oh-my-zsh.remote=origin \
                    -c "oh-my-zsh.branch=$ref" "$url" "$dest" </dev/null
                return
            fi
            git clone -q --depth=1 --branch "$ref" "$url" "$dest" </dev/null
            ;;
        recovery)
            dotfiles_log error "$dest exists without oh-my-zsh.sh; follow the X-recovery block"
            return 1
            ;;
        *)
            dotfiles_log error "$dest exists and is not a git checkout; move it aside, then rerun"
            return 1
            ;;
    esac
}

step_S3_clones_apply() {
    local rows lines row id dest url ref failed=''
    rows=$(steps_clone_rows) || return 1
    lines=$rows$BOOTSTRAP_NL
    while [ -n "$lines" ]; do
        row=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        bootstrap_split "$BOOTSTRAP_TAB" "$row" id dest url ref _
        [ -n "$id" ] || continue
        if ! steps_clone_apply "$id" "$dest" "$url" "$ref"; then
            if [ "$id" = oh-my-zsh ]; then
                # The other clones would create ~/.oh-my-zsh/custom without it.
                dotfiles_log error "oh-my-zsh clone failed; the other clones need it first"
                return 1
            fi
            failed="$failed${failed:+ }$id"
        fi
    done
    if [ -n "$failed" ]; then
        dotfiles_log error "S3-clones failed for: $failed"
        return 1
    fi
}

# --- S3-bat-theme (unix) ---------------------------------------------------

# steps_bat_theme_ok: 0 when the pinned theme file is in place and, if bat is
# installed, bat's cache knows it. Sets STEP_DETAIL.
steps_bat_theme_ok() {
    local name themes
    if [ ! -f "$STEPS_DEST" ]; then
        STEP_DETAIL="missing $STEPS_DEST"
        return 1
    fi
    if ! steps_has_digest "$STEPS_DEST" "$STEPS_SHA"; then
        STEP_DETAIL="$STEPS_DEST differs from the pinned theme"
        return 1
    fi
    if ! command -v bat >/dev/null 2>&1; then
        STEP_DETAIL='theme pinned; bat is not installed, so run bat cache --build once it is'
        return 0
    fi
    name=${STEPS_DEST##*/}
    name=${name%.tmTheme}
    themes=$(bat --list-themes --color=never 2>/dev/null </dev/null) || themes=
    if bootstrap_text_has -F "$name" "$themes"; then
        STEP_DETAIL="theme pinned and known to bat"
        return 0
    fi
    STEP_DETAIL='theme pinned; bat cache --build has not run since'
    return 1
}

step_S3_bat_theme_check() {
    if ! steps_installer_fields bat-theme; then
        STEP_DETAIL="no installers.tsv bat-theme row for $STEPS_HOST"
        return 2
    fi
    steps_bat_theme_ok
}

step_S3_bat_theme_plan() {
    steps_installer_fields bat-theme || return 0
    printf 'install the pinned theme at %s, then bat cache --build\n' "$STEPS_DEST"
}

step_S3_bat_theme_apply() {
    steps_installer_fields bat-theme || return 1
    steps_fetch_pinned "$STEPS_URL" "$STEPS_DEST" "$STEPS_SHA" || return 1
    if command -v bat >/dev/null 2>&1; then
        bat cache --build >&2 </dev/null || return 1
    else
        dotfiles_log warn 'bat is not installed; run bat cache --build once it is'
    fi
}

step_S3_bat_theme_verify() {
    steps_installer_fields bat-theme || return 1
    steps_bat_theme_ok
}

# --- S3-dirs (unix) --------------------------------------------------------

step_S3_dirs_check() {
    if [ -d "$HOME/.vim/undo" ] && [ -d "$HOME/.vim/tmp" ]; then
        STEP_DETAIL="$HOME/.vim/undo and $HOME/.vim/tmp exist"
        return 0
    fi
    STEP_DETAIL="$HOME/.vim/undo or $HOME/.vim/tmp is missing"
    return 1
}

step_S3_dirs_plan() {
    printf '%s\n' 'mkdir -p ~/.vim/undo ~/.vim/tmp'
}

step_S3_dirs_apply() {
    mkdir -p "$HOME/.vim/undo" "$HOME/.vim/tmp"
}
