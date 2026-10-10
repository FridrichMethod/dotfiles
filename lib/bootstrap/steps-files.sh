# shellcheck shell=bash
# shellcheck disable=SC2034 # STEP_DETAIL and the STEPS_* fields are read by steps.sh
# Home-file steps of setup-host.sh: S3-clones (pinned git clones),
# S3-bat-theme and S3-dirs.
# Checks are read-only and offline; apply functions run in steps_guarded
# and report each failure explicitly. Sourced only (after steps.sh and
# steps-common.sh); defines functions and changes no shell options.

# --- S3-clones (unix) ------------------------------------------------------

# steps_repo_key URL: host/owner/repo, lower case, for comparing remotes.
steps_repo_key() {
    local url=${1%/}
    url=${url%.git}
    case $url in
        https://* | http://* | ssh://* | git://* | file://*) url=${url#*://} ;;
        *@*:*)
            url=${url#*@}
            url=${url%%:*}/${url#*:}
            ;;
    esac
    url=${url#*@}
    printf '%s\n' "$url" | tr '[:upper:]' '[:lower:]'
}

# steps_clone_state ID DEST URL REF: done, clone, repin, recovery (an
# oh-my-zsh dir without oh-my-zsh.sh), dirty, origin, or foreign.
steps_clone_state() {
    local id=$1 dest=$2 url=$3 ref=$4 origin status head
    if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
        echo clone
        return 0
    fi
    if [ "$id" = oh-my-zsh ]; then
        if [ -f "$dest/oh-my-zsh.sh" ]; then echo 'done'; else echo recovery; fi
        return 0
    fi
    if [ ! -d "$dest" ] || { [ ! -d "$dest/.git" ] && [ ! -f "$dest/.git" ]; }; then
        echo foreign
        return 0
    fi
    origin=$(git -C "$dest" config --get remote.origin.url 2>/dev/null </dev/null) || origin=
    if [ "$(steps_repo_key "$origin")" != "$(steps_repo_key "$url")" ]; then
        echo origin
        return 0
    fi
    if ! status=$(git --no-optional-locks -C "$dest" status --porcelain --untracked-files=no 2>/dev/null </dev/null) ||
        [ -n "$status" ]; then
        echo dirty
        return 0
    fi
    head=$(git -C "$dest" rev-parse HEAD 2>/dev/null </dev/null) || head=
    if [ "$head" = "$ref" ]; then echo 'done'; else echo repin; fi
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
    local rows lines row id dest url ref state pinned=0 todo='' bad=''
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
        state=$(steps_clone_state "$id" "$dest" "$url" "$ref")
        case $state in
            done) pinned=$((pinned + 1)) ;;
            recovery) STEPS_OMZ_RECOVERY=$dest ;;
            clone | repin) todo="$todo${todo:+ }$id ($state)" ;;
            *) bad="$bad${bad:+ }$id ($state)" ;;
        esac
    done
    if [ -n "$STEPS_OMZ_RECOVERY" ]; then
        STEP_DETAIL="$STEPS_OMZ_RECOVERY exists without oh-my-zsh.sh (stow ran before the clone); recover it by hand"
        return 3
    fi
    if [ -z "$todo$bad" ]; then
        STEP_DETAIL="$pinned clones at their pins"
        return 0
    fi
    STEP_DETAIL="${todo:+to clone or re-pin: $todo}${todo:+${bad:+; }}${bad:+apply fails for: $bad}"
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
        printf 'pinned git clones from config/bootstrap/git-clones.tsv: %s\n' "$STEP_DETAIL"
    fi
}

step_S3_clones_manual() {
    printf '%s\n' '# X-recovery applies only when ~/.oh-my-zsh exists without oh-my-zsh.sh'
    steps_omz_recovery_block "$(bootstrap_expand_path "\$HOME/.oh-my-zsh")"
}

# steps_git_pin DIR URL REF MODE: MODE init makes DIR a new repository with
# origin URL; then check out REF detached, fetching it shallowly unless the
# commit is already present.
steps_git_pin() {
    local dir=$1 url=$2 ref=$3 target=FETCH_HEAD head
    if [ "$4" = init ]; then
        git -c init.defaultBranch=main init -q "$dir" </dev/null || return 1
        git -C "$dir" remote add origin "$url" </dev/null || return 1
    fi
    if [ "$4" = repin ] && git -C "$dir" cat-file -e "$ref^{commit}" 2>/dev/null </dev/null; then
        target=$ref
    else
        git -C "$dir" fetch -q --depth=1 origin "$ref" </dev/null || return 1
    fi
    git -c advice.detachedHead=false -C "$dir" checkout -q --detach "$target" </dev/null || return 1
    head=$(git -C "$dir" rev-parse HEAD </dev/null) || return 1
    if [ "$head" != "$ref" ]; then
        dotfiles_log error "$dir is at $head, not the pinned $ref"
        return 1
    fi
}

# steps_clone_apply ID DEST URL REF: bring one clone to its pin.
steps_clone_apply() {
    local id=$1 dest=$2 url=$3 ref=$4 parent tmp
    case $(steps_clone_state "$id" "$dest" "$url" "$ref") in
        done) return 0 ;;
        clone)
            parent=$(dirname "$dest")
            mkdir -p "$parent" || return 1
            if [ "$id" = oh-my-zsh ]; then
                # As the official installer clones it, so its self-update works.
                git clone -q --depth=1 --branch "$ref" -c core.eol=lf -c core.autocrlf=false \
                    -c fsck.zeroPaddedFilemode=ignore -c fetch.fsck.zeroPaddedFilemode=ignore \
                    -c receive.fsck.zeroPaddedFilemode=ignore -c oh-my-zsh.remote=origin \
                    -c "oh-my-zsh.branch=$ref" "$url" "$dest" </dev/null
                return
            fi
            tmp=$(steps_new_dir "$parent" "setup-host-$id") || return 1
            if steps_git_pin "$tmp" "$url" "$ref" init && mv "$tmp" "$dest"; then
                return 0
            fi
            rm -rf "$tmp"
            return 1
            ;;
        repin) steps_git_pin "$dest" "$url" "$ref" repin ;;
        dirty)
            dotfiles_log error "$dest has local changes; commit, stash or move it aside, then rerun"
            return 1
            ;;
        origin)
            dotfiles_log error "$dest is a clone of another remote, not $url; move it aside"
            return 1
            ;;
        recovery)
            dotfiles_log error "$dest exists without oh-my-zsh.sh; follow the X-recovery block"
            return 1
            ;;
        *)
            dotfiles_log error "$dest exists and is not a git checkout; move it aside"
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
        dotfiles_log error "clones not at their pins: $failed"
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
