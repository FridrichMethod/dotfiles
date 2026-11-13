# shellcheck shell=bash
# shellcheck disable=SC2034 # STEP_DETAIL and the STEPS_* fields are read by steps.sh
# HUMAN steps of scripts/commands/setup.sh: read-only checks of what a person must do,
# and the HUMAN blocks that hand it over. Blocks are printed, never run.
# Sourced only (after steps.sh and steps-common.sh); defines functions and
# changes no shell options.

# --- H1-xcode-clt (macos, gui) ---------------------------------------------

step_H1_xcode_clt_check() {
    local path
    if path=$(xcode-select -p 2>/dev/null </dev/null) && [ -n "$path" ]; then
        STEP_DETAIL="Command Line Tools at $path"
        return 0
    fi
    STEP_DETAIL='the Xcode Command Line Tools (git, clang) are not installed'
    return 1
}

step_H1_xcode_clt_plan() {
    steps_block_begin H1-xcode-clt gui
    printf '%s\n' 'xcode-select --install' \
        "# finish the installer dialog, then run $(steps_quote "$STEPS_ROOT/dotfiles") setup --host $STEPS_HOST again"
    steps_block_end
}

# --- H1-homebrew (macos) and H1-linuxbrew (debian), sudo -------------------

steps_brew_check() {
    local brew
    if brew=$(bootstrap_brew_bin); then
        STEP_DETAIL="brew at $brew"
        return 0
    fi
    STEP_DETAIL='Homebrew is not installed'
    return 1
}

# steps_homebrew_block STEP: the pinned Homebrew installer, run by a person.
# Apply mode downloaded and verified it first; --check and --print-manual
# only name the URL and digest. The run line re-checks the digest itself and
# runs the installer only when it still matches, since the file may have
# changed since the download; sudo -k then drops the cached credential.
steps_homebrew_block() {
    local path
    steps_block_begin "$1" sudo
    if ! steps_installer_fields homebrew; then
        printf '# no installers.tsv homebrew row for %s\n' "$STEPS_HOST"
        steps_block_end
        return 0
    fi
    path=$(steps_scratch_file homebrew "$STEPS_URL")
    if [ "$STEPS_MODE" = apply ] && steps_has_digest "$path" "$STEPS_SHA"; then
        printf '# downloaded %s\n# sha256 %s verified\n' "$STEPS_URL" "$STEPS_SHA"
    else
        printf '# %s setup --host %s (without --check) downloads %s\n' "$(steps_quote "$STEPS_ROOT/dotfiles")" "$STEPS_HOST" "$STEPS_URL"
        printf '# to the path below and verifies sha256 %s first\n' "$STEPS_SHA"
    fi
    printf '%s\n' "# Homebrew's NONINTERACTIVE mode needs a cached sudo credential" 'sudo -v' \
        '# the installer runs only while its sha256 is still the pinned one'
    steps_digest_gate "$STEPS_SHA" "$path" "NONINTERACTIVE=1 /bin/bash $(steps_quote "$path")"
    printf '%s\n' '# drop the cached sudo credential again' 'sudo -k'
    steps_block_end
}

step_H1_homebrew_check() { steps_brew_check; }
step_H1_homebrew_apply() { steps_fetch_installer homebrew; }
step_H1_homebrew_plan() { steps_homebrew_block H1-homebrew; }
step_H1_linuxbrew_check() { steps_brew_check; }
step_H1_linuxbrew_apply() { steps_fetch_installer homebrew; }
step_H1_linuxbrew_plan() { steps_homebrew_block H1-linuxbrew; }

# --- H1-apt-core (debian, sudo) --------------------------------------------

# steps_apt_missing PACKAGES: the packages of the newline list that dpkg does
# not report as installed, space-separated. Read-only (dpkg-query).
steps_apt_missing() {
    local IFS=' ' nl=$BOOTSTRAP_NL lines package list='' status missing=''
    lines=$1$nl
    while [ -n "$lines" ]; do
        package=${lines%%"$nl"*}
        lines=${lines#*"$nl"}
        case $package in
            '' | -* | *[!A-Za-z0-9.+:-]*) continue ;;
        esac
        list="$list $package"
    done
    [ -n "$list" ] || return 0
    # shellcheck disable=SC2016,SC2086 # dpkg format fields; names checked above
    status=$(dpkg-query -W -f='${Package} ${db:Status-Abbrev}\n' $list 2>/dev/null </dev/null) || true
    for package in $list; do
        case "$nl$status" in
            *"$nl$package "?i*) ;;
            *) missing="$missing${missing:+ }$package" ;;
        esac
    done
    printf '%s\n' "$missing"
}

step_H1_apt_core_check() {
    local packages missing
    if ! packages=$(bootstrap_apt_packages "$STEPS_HOST"); then
        STEP_DETAIL='cannot read config/bootstrap/apt/common.txt'
        return 1
    fi
    missing=$(steps_apt_missing "$packages")
    if [ -z "$missing" ]; then
        STEP_DETAIL="$(printf '%s\n' "$packages" | grep -c .) apt packages installed"
        return 0
    fi
    STEP_DETAIL="missing apt packages: $missing"
    return 1
}

step_H1_apt_core_plan() {
    local packages list
    packages=$(bootstrap_apt_packages "$STEPS_HOST") || packages=
    if [ "$STEPS_MODE" = manual ]; then
        list=$(printf '%s\n' "$packages" | tr '\n' ' ')
        list=${list% }
    else
        list=$(steps_apt_missing "$packages")
    fi
    steps_block_begin H1-apt-core sudo
    printf '%s\n' 'sudo apt-get update'
    printf 'sudo apt-get install -y --no-install-recommends %s\n' "$list"
    steps_block_end
}

# --- H1-locale (debian, sudo, reminder) ------------------------------------

step_H1_locale_check() {
    local locales
    locales=$(locale -a 2>/dev/null) || locales=
    if bootstrap_text_has -Ei '^en_US\.utf-?8$' "$locales"; then
        STEP_DETAIL='en_US.UTF-8 is available'
        return 0
    fi
    STEP_DETAIL='en_US.UTF-8 is not generated'
    return 1
}

step_H1_locale_plan() {
    steps_block_begin H1-locale sudo
    printf '%s\n' 'sudo locale-gen en_US.UTF-8'
    steps_block_end
}

# --- H1-fcitx5 (lab-ubuntu, gui, reminder) ---------------------------------

step_H1_fcitx5_check() {
    if [ -f "$HOME/.xinputrc" ] && grep -q fcitx5 "$HOME/.xinputrc" 2>/dev/null; then
        STEP_DETAIL="$HOME/.xinputrc selects fcitx5"
        return 0
    fi
    STEP_DETAIL='fcitx5 is not the selected input method'
    return 1
}

step_H1_fcitx5_plan() {
    steps_block_begin H1-fcitx5 gui
    printf '%s\n' '# the fcitx5 packages come from H1-apt-core (apt/lab-ubuntu.txt)' \
        'im-config -n fcitx5' \
        '# then log out and back in so the session starts fcitx5'
    steps_block_end
}

# --- H2-alloc (hpc, alloc) -------------------------------------------------

step_H2_alloc_check() {
    if steps_probe login-env; then
        STEP_DETAIL='the login env exists; no allocation is needed'
        return 0
    fi
    if bootstrap_in_allocation; then
        STEP_DETAIL="inside Slurm job $SLURM_JOB_ID"
        return 0
    fi
    STEP_DETAIL='S2-login-env builds its env only inside a Slurm allocation (SLURM_JOB_ID is unset)'
    return 1
}

step_H2_alloc_plan() {
    steps_block_begin H2-alloc alloc
    case $STEPS_HOST in
        sherlock) printf '%s\n' 'sh_dev -t 1:00:00' ;;
        *)
            printf '%s\n' \
                '# start an interactive Slurm job with an explicit --time (and the partition your allocation uses), e.g.' \
                'srun --time=1:00:00 --pty bash -l'
            ;;
    esac
    printf '%s\n' '# then, inside the allocation (export CONDA_PKGS_DIRS first, as docs/bootstrap.md S2-login-env says):'
    printf '%s setup --host %s\n' "$(steps_quote "$STEPS_ROOT/dotfiles")" "$STEPS_HOST"
    steps_block_end
}

# --- S2-modules (hpc, judgment, reminder) ----------------------------------

# tools.tsv does not check claude and codex on a cluster (they are optional
# site modules), so this reminder looks them up on PATH itself.
step_S2_modules_check() {
    if command -v claude >/dev/null 2>&1 && command -v codex >/dev/null 2>&1; then
        STEP_DETAIL='claude and codex are on PATH'
        return 0
    fi
    STEP_DETAIL='Claude Code and Codex come from site modules on this cluster, not from setup-host'
    return 1
}

step_S2_modules_plan() {
    steps_block_begin S2-modules judgment
    printf '%s\n' '# the AI CLIs are not installed by setup-host here; find the site modules:' \
        'ml spider claude-code codex pi-coding-agent'
    case $STEPS_HOST in
        sherlock)
            printf '%s\n' '# node: the sherlock overlay rc loads this after the login env, so it wins on PATH' \
                'ml nodejs/24.13.0'
            ;;
        *) printf '%s\n' '# node: conda-forge nodejs from the login env (S2-login-env)' ;;
    esac
    steps_block_end
}

# --- S5-claude (debian, inspect) -------------------------------------------

step_S5_claude_check() {
    if steps_probe claude; then
        STEP_DETAIL="claude at $STEPS_PROBE_FOUND"
        return 0
    fi
    if [ -x "$HOME/.local/bin/claude" ]; then
        STEP_DETAIL="claude at $HOME/.local/bin/claude"
        return 0
    fi
    if ! steps_installer_fields claude; then
        STEP_DETAIL="no installers.tsv claude row for $STEPS_HOST"
        return 2
    fi
    STEP_DETAIL='Claude Code is not installed; its vendor installer is read by a person first'
    return 1
}

step_S5_claude_apply() { steps_fetch_installer claude; }

# The download is kept: setup-host fetches it only while the file is absent,
# so the copy a person read is not replaced by a later run. The run line
# binds that copy to the digest printed here (read-only, so --check shows it
# too once a run has downloaded it).
step_S5_claude_plan() {
    local path quoted digest size
    steps_block_begin S5-claude inspect
    if ! steps_installer_fields claude; then
        printf '# no installers.tsv claude row for %s\n' "$STEPS_HOST"
        steps_block_end
        return 0
    fi
    path=$(steps_scratch_file claude "$STEPS_URL")
    quoted=$(steps_quote "$path")
    if [ "$STEPS_MODE" != manual ] && [ -f "$path" ] && digest=$(bootstrap_sha256 "$path"); then
        size=$(wc -c <"$path" | tr -d ' ')
        printf '# downloaded %s (unpinned vendor script) to %s\n' "$STEPS_URL" "$quoted"
        printf '# sha256 %s, %s bytes; delete the file for a fresh copy\n' "$digest" "$size"
        printf '%s\n' '# read it first; the line below runs it only while its sha256 is still the one above'
        steps_digest_gate "$digest" "$path" "bash $quoted"
    else
        printf '# %s setup --host %s (without --check) downloads %s (unpinned)\n' "$(steps_quote "$STEPS_ROOT/dotfiles")" "$STEPS_HOST" "$STEPS_URL"
        printf '# to %s once, then prints its sha256, its size and a line\n' "$quoted"
        printf '%s\n' '# that runs it only while that sha256 holds; read the file before you run it'
    fi
    printf '# %s doctor then checks the installed claude against tools.tsv\n' "$(steps_quote "$STEPS_ROOT/dotfiles")"
    steps_block_end
}

# --- H7-chsh (macos, debian; chsh, reminder) -------------------------------

steps_login_shell() {
    local user entry
    user=$(id -un 2>/dev/null) || user=${USER:-}
    if command -v getent >/dev/null 2>&1 && entry=$(getent passwd "$user" 2>/dev/null </dev/null) && [ -n "$entry" ]; then
        printf '%s\n' "${entry##*:}"
    elif command -v dscl >/dev/null 2>&1 && entry=$(dscl . -read "/Users/$user" UserShell 2>/dev/null </dev/null); then
        printf '%s\n' "${entry##* }"
    else
        printf '%s\n' "${SHELL:-}"
    fi
}

step_H7_chsh_check() {
    local shell
    shell=$(steps_login_shell)
    case ${shell##*/} in
        zsh)
            STEP_DETAIL="login shell is $shell"
            return 0
            ;;
    esac
    STEP_DETAIL="login shell is ${shell:-unknown}"
    return 1
}

step_H7_chsh_plan() {
    local zsh
    if [ "$STEPS_PROFILE" = macos ]; then
        zsh=/bin/zsh
    elif [ -x /usr/bin/zsh ]; then
        zsh=/usr/bin/zsh
    else
        zsh=$(command -v zsh 2>/dev/null) || zsh=/usr/bin/zsh
    fi
    steps_block_begin H7-chsh chsh
    printf 'chsh -s %s\n' "$(steps_quote "$zsh")"
    steps_block_end
}

# --- H7-auth (auth, reminder) ----------------------------------------------

step_H7_auth_check() {
    STEP_DETAIL='sign in to GitHub, Claude Code and Codex (not checked offline)'
    return 1
}

# On a cluster the AI CLIs exist only when a site module provides them
# (S2-modules), so their sign-in lines are printed only for those on PATH;
# --print-manual names them with that condition.
step_H7_auth_plan() {
    local claude=1 codex=1
    if [ "$STEPS_PROFILE" = hpc ] && [ "$STEPS_MODE" != manual ]; then
        command -v claude >/dev/null 2>&1 || claude=0
        command -v codex >/dev/null 2>&1 || codex=0
    fi
    steps_block_begin H7-auth auth
    if [ "$STEPS_MODE" = manual ] || [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        printf '%s\n' 'ssh-keygen -t ed25519'
    fi
    printf '%s\n' 'gh auth login --git-protocol ssh' \
        '# do not run gh auth setup-git: it rewrites ~/.gitconfig, which the dotfiles manage; .gitconfig_local sets the helper'
    if [ "$STEPS_PROFILE" = hpc ] && [ "$STEPS_MODE" = manual ]; then
        printf '%s\n' '# claude and codex only where a site module provides them (S2-modules)'
    fi
    if [ "$claude" = 1 ]; then
        printf '%s\n' '# Claude Code signs in on its first interactive run' 'claude'
    fi
    if [ "$codex" = 1 ]; then
        printf '%s\n' '# add --device-auth on a host without a browser' 'codex login'
    fi
    if [ "$STEPS_PROFILE" = hpc ]; then
        printf '%s\n' 'kinit'
    fi
    steps_block_end
}

# --- H7-payloads (judgment, reminder) --------------------------------------

# Done once the doctor's payloads check passes: every selected payload repo
# installed, with the kit's Claude helpers.
step_H7_payloads_check() {
    local result
    result=$(bootstrap_check_payloads "$STEPS_ROOT")
    STEP_DETAIL=${result#*"$BOOTSTRAP_TAB"}
    [ "${result%%"$BOOTSTRAP_TAB"*}" = ok ]
}

# Payload installs are person-run through the helper-selected checkout's
# public frontend. A configured home may also use its installed launcher.
# Refused source resolution leaves notes only; no config preserves ROOT.
step_H7_payloads_plan() {
    local source
    steps_block_begin H7-payloads judgment
    printf '%s\n' \
        '# coding-agent-kit, PyMOLScripts and awesome-skills install and update only when a person runs them, through their own installers (config/payloads.tsv); no login installs or refreshes them' \
        "# each is an unpinned download of its repo's main install script from raw.githubusercontent.com/FridrichMethod; the kit then follows the newest patch release of channel $(steps_payload_channel)"
    if ! source=$(bootstrap_payload_source "$STEPS_ROOT"); then
        printf '%s\n' "# maintenance is active, or this checkout cannot resolve this home's ~/.config/chezmoi/chezmoi.toml (the doctor's chezmoi-config row says which); once neither holds, rerun this setup command"
        steps_block_end
        return 0
    fi
    if bootstrap_configured_home; then
        printf '# this home'\''s config names the checkout %s: the line below runs its public frontend\n' \
            "$source"
        if [ -f "$HOME/.local/bin/dotfiles" ] && [ -x "$HOME/.local/bin/dotfiles" ]; then
            printf '%s\n' '# rerun the line below (or sync-payloads [ITEM...] in an interactive shell) to update them later. To install them now, in the foreground:'
        else
            printf '%s\n' '# rerun the line below to update them later. To install them now, in the foreground:'
        fi
    else
        printf '%s\n' '# rerun the line below to update them later (sync-payloads needs ~/.config/chezmoi/chezmoi.toml, which this home lacks). To install them now, in the foreground:'
    fi
    printf '%s payloads sync\n' "$(steps_quote "$source/dotfiles")"
    steps_block_end
}

# steps_payload_channel: the kit channel row of config/payloads.tsv.
steps_payload_channel() {
    local line
    if [ ! -r "$STEPS_ROOT/config/payloads.tsv" ]; then
        printf '%s\n' '?'
        return 0
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        case $line in
            "kit${BOOTSTRAP_TAB}channel$BOOTSTRAP_TAB"*)
                printf '%s\n' "${line#"kit${BOOTSTRAP_TAB}channel$BOOTSTRAP_TAB"}"
                return 0
                ;;
        esac
    done <"$STEPS_ROOT/config/payloads.tsv"
    printf '%s\n' '?'
}

# --- H7-doctor (judgment, reminder) ----------------------------------------

step_H7_doctor_check() {
    STEP_DETAIL="the completion gate is $(steps_quote "$STEPS_ROOT/dotfiles") doctor --host $STEPS_HOST"
    return 1
}

step_H7_doctor_plan() {
    local doctor
    doctor=$(steps_quote "$STEPS_ROOT/dotfiles")
    steps_block_begin H7-doctor judgment
    printf '%s doctor --host %s\n' "$doctor" "$STEPS_HOST"
    printf '%s doctor --host %s --smoke\n' "$doctor" "$STEPS_HOST"
    steps_block_end
}

# --- H7-deploy (operator-owned first apply) --------------------------------
# shellcheck disable=SC2088 # a literal ~ for the reader, never expanded
step_H7_deploy_check() {
    if bootstrap_chezmoi_ready "$STEPS_ROOT"; then
        STEP_DETAIL='~/.config/chezmoi/chezmoi.toml names this home and this checkout; configuration review remains an operator step'
        return 0
    fi
    STEP_DETAIL='follow Fresh home by hand in docs/bootstrap.md to initialize and deploy this home'
    return 1
}

step_H7_deploy_plan() {
    steps_block_begin H7-deploy judgment
    printf '%s\n' \
        '# Follow Fresh home by hand in docs/bootstrap.md from this checkout.' \
        "# Select local [data].host = $STEPS_HOST explicitly; setup-host never initializes or applies configuration." \
        '# Review exact targets and private backups, then initialize with all paths explicit; never use blanket force.'
    steps_block_end
}
