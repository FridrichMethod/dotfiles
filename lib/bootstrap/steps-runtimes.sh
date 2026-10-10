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

# steps_nvm_pin: the commit the installers.tsv nvm row pins; 1 without one.
steps_nvm_pin() {
    steps_installer_fields nvm || return 1
    steps_nvm_commit "$STEPS_URL"
}

# steps_nvm_verified DIR PIN: 0 when DIR is an nvm git checkout at PIN with
# no change to a tracked file, so its nvm.sh is the pinned one. Sets
# STEPS_NVM_HEAD to the checkout's HEAD (empty when DIR has no .git).
# Read-only: git takes no optional locks.
steps_nvm_verified() {
    local status
    STEPS_NVM_HEAD=
    [ -e "$1/.git" ] || return 1
    STEPS_NVM_HEAD=$(git -C "$1" rev-parse HEAD 2>/dev/null </dev/null) || STEPS_NVM_HEAD=
    [ -n "$2" ] && [ "$STEPS_NVM_HEAD" = "$2" ] || return 1
    status=$(git --no-optional-locks -C "$1" status --porcelain --untracked-files=no 2>/dev/null </dev/null) ||
        return 1
    [ -z "$status" ]
}

# Done needs no nvm.sh at all: node at the floor and a default alias are
# files. Anything else is finished by sourcing nvm.sh, which happens only for
# the pinned, unmodified checkout; another one (an older install, a checkout
# off the pin, a dir that is not a git checkout) is a judgment block.
step_S4_nvm_check() {
    local dir floor best pin=''
    STEPS_NVM_REFUSAL='' STEPS_NVM_PIN='' STEPS_NVM_HEAD=''
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
    elif [ ! -f "$dir/alias/default" ]; then
        STEP_DETAIL="node $best is installed, but nvm has no default alias"
    else
        STEP_DETAIL="nvm in $dir with node $best and a default alias"
        return 0
    fi
    pin=$(steps_nvm_pin) || pin=
    if steps_nvm_verified "$dir" "$pin"; then
        return 1
    fi
    STEPS_NVM_REFUSAL=$dir
    STEPS_NVM_PIN=$pin
    if [ -z "$STEPS_NVM_HEAD" ]; then
        STEP_DETAIL="$STEP_DETAIL; $dir is not a git checkout, so its nvm.sh cannot be checked against the pinned commit and is not sourced"
    elif [ "$STEPS_NVM_HEAD" != "$pin" ]; then
        STEP_DETAIL="$STEP_DETAIL; $dir is at $STEPS_NVM_HEAD, not the pinned nvm commit ${pin:-(none in installers.tsv)}, so its nvm.sh is not sourced"
    else
        STEP_DETAIL="$STEP_DETAIL; $dir has local changes at the pinned commit, so its nvm.sh is not sourced"
    fi
    return 3
}

# steps_nvm_block DIR PIN HEAD [manual]: the judgment block for an nvm.sh
# setup-host will not source, with the lines that make DIR the pinned,
# unmodified checkout (or, in a note, move it aside for a fresh install).
steps_nvm_block() {
    local q aside
    q=$(steps_quote "$1")
    aside="mv -n $q $(steps_quote "$1.pre-dotfiles")"
    steps_block_begin S4-nvm judgment
    if [ "${4:-}" = manual ]; then
        printf '%s\n' '# applies only when NVM_DIR holds an nvm.sh that is not the pinned, unmodified nvm checkout' \
            '# and node or the default alias is missing: ./setup-host.sh then never sources it and prints this block'
    fi
    if [ "${4:-}" != manual ] && [ -z "$3" ]; then
        printf '# %s has an nvm.sh but is not a git checkout, so setup-host cannot check it against the pinned commit %s\n' "$1" "$2"
        printf '%s\n' '# move it aside; the next ./setup-host.sh run installs the pinned nvm there (move versions/ back to keep its node builds)' \
            "$aside"
    elif [ "${4:-}" != manual ] && [ "$3" = "$2" ]; then
        printf '# %s is at the pinned commit, but tracked files changed, so its nvm.sh is not the pinned one\n' "$1"
        printf '%s\n' "# review the changes; the second line discards them (or move the dir aside instead: $aside)" \
            "git -C $q status --short" "git -C $q checkout -- ."
    else
        printf '# %s is not the pinned nvm commit %s; setup-host never sources an nvm.sh it has not checked\n' "$1" "$2"
        printf '%s\n' "# move it to the pin (versions/ and alias/ stay; git stops if local changes are in the way), or move the dir aside instead: $aside"
        printf 'git -C %s fetch --depth=1 https://github.com/nvm-sh/nvm.git %s\n' "$q" "$2"
        printf 'git -C %s -c advice.detachedHead=false checkout --detach %s\n' "$q" "$2"
    fi
    printf '# then run ./setup-host.sh --host %s again\n' "$STEPS_HOST"
    steps_block_end
}

step_S4_nvm_plan() {
    if [ -n "${STEPS_NVM_REFUSAL:-}" ]; then
        steps_nvm_block "$STEPS_NVM_REFUSAL" "$STEPS_NVM_PIN" "$STEPS_NVM_HEAD"
        return 0
    fi
    printf '%s\n' "pinned nvm install.sh at its pinned commit with PROFILE=/dev/null, then nvm install --lts && nvm alias default 'lts/*'"
}

step_S4_nvm_manual() {
    local dir pin
    # shellcheck disable=SC2016 # a manifest token, expanded by the library
    dir=$(bootstrap_expand_path '$NVM_DIR') || return 0
    pin=$(steps_nvm_pin) || return 0
    steps_nvm_block "$dir" "$pin" '' manual
}

# The installer clones nvm itself, by default from a release tag, which can
# move. NVM_INSTALL_VERSION makes it fetch the commit the installers.tsv URL
# names, by its id. Nothing here sources an nvm.sh unless its checkout is at
# that commit with no change to a tracked file; a checkout this run created
# that is not is removed again.
step_S4_nvm_apply() {
    local dir script commit created=0
    # shellcheck disable=SC2016 # a manifest token, expanded by the library
    dir=$(bootstrap_expand_path '$NVM_DIR') || return 1
    steps_installer_fields nvm || return 1
    if ! commit=$(steps_nvm_commit "$STEPS_URL"); then
        dotfiles_log error "the installers.tsv nvm url must name a 40-hex nvm-sh/nvm commit: $STEPS_URL"
        return 1
    fi
    if [ ! -s "$dir/nvm.sh" ]; then
        script=$(steps_scratch_file nvm "$STEPS_URL")
        steps_make_scratch nvm || return 1
        steps_fetch_pinned "$STEPS_URL" "$script" "$STEPS_SHA" || return 1
        # The installer refuses an NVM_DIR that does not exist yet.
        [ -e "$dir" ] || created=1
        mkdir -p "$dir" || return 1
        if ! NVM_INSTALL_VERSION=$commit PROFILE=/dev/null NVM_DIR=$dir bash "$script" >&2 </dev/null; then
            [ "$created" != 1 ] || rm -rf "$dir"
            return 1
        fi
    fi
    if ! steps_nvm_verified "$dir" "$commit"; then
        [ "$created" != 1 ] || rm -rf "$dir"
        dotfiles_log error "$dir is at ${STEPS_NVM_HEAD:-no commit}, not the pinned nvm commit $commit, or has local changes; nothing sourced its nvm.sh"
        return 1
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
