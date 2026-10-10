# shellcheck shell=bash
# shellcheck disable=SC2034 # STEP_DETAIL and the STEPS_* fields are read by steps.sh
# Runtime steps of setup-host.sh: S4-nvm (nvm and Node.js) and S4-setup-sync
# (the checkout's .venv-sync, the only write inside the checkout).
# Checks are read-only and offline; apply functions run in steps_guarded
# and report each failure explicitly. Sourced only (after steps.sh and
# steps-common.sh); defines functions and changes no shell options.

# --- S4-nvm (macos, debian) ------------------------------------------------

# steps_nvm_best DIR: the highest node version installed by nvm in DIR.
steps_nvm_best() {
    local candidate version best=''
    for candidate in "$1"/versions/node/v*; do
        [ -x "$candidate/bin/node" ] || continue
        version=${candidate##*/v}
        if [ -z "$best" ] || bootstrap_version_ge "$version" "$best"; then
            best=$version
        fi
    done
    printf '%s\n' "$best"
}

step_S4_nvm_check() {
    local dir floor best
    # shellcheck disable=SC2016 # a manifest token, expanded by the library
    dir=$(bootstrap_expand_path '$NVM_DIR') || return 1
    if [ ! -s "$dir/nvm.sh" ]; then
        STEP_DETAIL="nvm is not installed in $dir"
        return 1
    fi
    floor=$(steps_tool_cell node 6) || floor=-
    [ "$floor" != - ] || floor=22.0
    best=$(steps_nvm_best "$dir")
    if [ -z "$best" ] || ! bootstrap_version_ge "$best" "$floor"; then
        STEP_DETAIL="nvm has no node >= $floor${best:+ (newest is $best)}"
        return 1
    fi
    if [ ! -f "$dir/alias/default" ]; then
        STEP_DETAIL="node $best is installed, but nvm has no default alias"
        return 1
    fi
    STEP_DETAIL="nvm in $dir with node $best and a default alias"
    return 0
}

step_S4_nvm_plan() {
    printf '%s\n' "pinned nvm install.sh at its pinned commit with PROFILE=/dev/null, then nvm install --lts && nvm alias default 'lts/*'"
}

# steps_nvm_commit URL: the 40-hex commit that a commit-pinned
# raw.githubusercontent.com/nvm-sh/nvm/<commit>/install.sh URL names.
steps_nvm_commit() {
    local commit=${1#https://raw.githubusercontent.com/nvm-sh/nvm/}
    [ "$commit" != "$1" ] || return 1
    commit=${commit%%/*}
    case $commit in
        '' | *[!0-9a-f]*) return 1 ;;
    esac
    [ "${#commit}" -eq 40 ] || return 1
    printf '%s\n' "$commit"
}

# The installer clones nvm itself, by default from a release tag, which can
# move. NVM_INSTALL_VERSION makes it fetch the commit the installers.tsv URL
# names, by its id; the checkout must be at that commit before anything here
# sources nvm.sh, and a checkout this run created is removed when it is not.
step_S4_nvm_apply() {
    local dir script commit head created=0
    # shellcheck disable=SC2016 # a manifest token, expanded by the library
    dir=$(bootstrap_expand_path '$NVM_DIR') || return 1
    if [ ! -s "$dir/nvm.sh" ]; then
        steps_installer_fields nvm || return 1
        if ! commit=$(steps_nvm_commit "$STEPS_URL"); then
            dotfiles_log error "the installers.tsv nvm url must name a 40-hex nvm-sh/nvm commit: $STEPS_URL"
            return 1
        fi
        script=$(steps_scratch_file nvm "$STEPS_URL")
        steps_make_scratch nvm || return 1
        steps_fetch_pinned "$STEPS_URL" "$script" "$STEPS_SHA" || return 1
        # The installer refuses an NVM_DIR that does not exist yet.
        [ -e "$dir" ] || created=1
        mkdir -p "$dir" || return 1
        NVM_INSTALL_VERSION=$commit PROFILE=/dev/null NVM_DIR=$dir bash "$script" >&2 </dev/null || return 1
        head=$(git -C "$dir" rev-parse HEAD 2>/dev/null </dev/null) || head=
        if [ "$head" != "$commit" ]; then
            if [ "$created" = 1 ]; then
                rm -rf "$dir"
            fi
            dotfiles_log error "$dir is at ${head:-no commit}, not the pinned nvm commit $commit; nothing sourced it here"
            return 1
        fi
    fi
    # shellcheck disable=SC2016 # expanded by the child bash
    NVM_DIR=$dir bash -c '. "$NVM_DIR/nvm.sh" --no-use && nvm install --lts && nvm alias default "lts/*"' \
        >&2 </dev/null
}

# --- S4-setup-sync (unix) --------------------------------------------------

step_S4_setup_sync_check() {
    local venv=$STEPS_ROOT/.venv-sync
    if [ -f "$venv/pyvenv.cfg" ] && [ -x "$venv/bin/python" ] &&
        "$venv/bin/python" -I -B -X utf8 "$STEPS_ROOT/lib/config_sync.py" --runtime-check >/dev/null 2>&1 </dev/null; then
        STEP_DETAIL="AI-sync runtime ready in $venv"
        return 0
    fi
    STEP_DETAIL="no working AI-sync runtime in $venv"
    return 1
}

# steps_setup_sync_python: the interpreter setup-sync.sh should use, if not
# the python3 on PATH: the login env on hpc, Homebrew's python3 on macOS.
steps_setup_sync_python() {
    local brew
    case $STEPS_PROFILE in
        hpc) printf '%s\n' "$HOME/micromamba/envs/login/bin/python3" ;;
        macos)
            if brew=$(bootstrap_brew_bin) && [ -x "${brew%/brew}/python3" ]; then
                printf '%s\n' "${brew%/brew}/python3"
            fi
            ;;
    esac
}

step_S4_setup_sync_plan() {
    local python
    python=$(steps_setup_sync_python)
    printf './setup-sync.sh%s\n' "${python:+ --python $python}"
}

step_S4_setup_sync_apply() {
    local python
    python=$(steps_setup_sync_python)
    if [ -z "$python" ]; then
        "$STEPS_ROOT/setup-sync.sh" >&2 </dev/null
        return
    fi
    if [ ! -x "$python" ]; then
        dotfiles_log error "missing $python for ./setup-sync.sh"
        return 1
    fi
    "$STEPS_ROOT/setup-sync.sh" --python "$python" >&2 </dev/null
}
