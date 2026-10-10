# shellcheck shell=bash
# shellcheck disable=SC2034 # STEP_DETAIL and the STEPS_* fields are read by steps.sh
# HUMAN steps of setup-host.sh: read-only checks of what a person must do,
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
        "# finish the installer dialog, then run ./setup-host.sh --host $STEPS_HOST again"
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
# only name the URL and digest.
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
        printf '# ./setup-host.sh --host %s (without --check) downloads %s\n' "$STEPS_HOST" "$STEPS_URL"
        printf '# to the path below and verifies sha256 %s first\n' "$STEPS_SHA"
    fi
    printf '%s\n' "# Homebrew's NONINTERACTIVE mode needs a cached sudo credential" 'sudo -v'
    printf 'NONINTERACTIVE=1 /bin/bash %s\n' "$(steps_quote "$path")"
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
    local IFS=' ' nl='
' package list='' status missing=''
    while IFS= read -r package; do
        case $package in
            '' | -* | *[!A-Za-z0-9.+:-]*) continue ;;
        esac
        list="$list $package"
    done <<EOF
$1
EOF
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
    if steps_text_has -Ei '^en_US\.utf-?8$' "$locales"; then
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

# --- H1-gh-apt-repo (lab-ubuntu, sudo, reminder) ---------------------------

step_H1_gh_apt_repo_check() {
    if steps_probe gh-apt; then
        STEP_DETAIL="$STEPS_PROBE_FOUND is installed"
        return 0
    fi
    STEP_DETAIL='the GitHub CLI apt package (named by .gitconfig_local) is not installed'
    return 1
}

step_H1_gh_apt_repo_plan() {
    local keyring=/etc/apt/keyrings/githubcli-archive-keyring.gpg
    steps_block_begin H1-gh-apt-repo sudo
    printf '%s\n' \
        '# the cli.github.com apt repository; .gitconfig_local runs /usr/bin/gh auth git-credential' \
        'keyring_download=$(mktemp)' \
        "curl -fsSL --proto '=https' --tlsv1.2 -o \"\$keyring_download\" https://cli.github.com/packages/githubcli-archive-keyring.gpg" \
        "sudo install -D -m 0644 \"\$keyring_download\" $keyring" \
        "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=$keyring] https://cli.github.com/packages stable main\" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null" \
        'sudo apt-get update' \
        'sudo apt-get install -y gh'
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
    STEP_DETAIL='S2-login-env builds the login env only inside a Slurm allocation (SLURM_JOB_ID is unset)'
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
    printf '%s\n' '# then, inside the allocation:'
    printf 'cd %s\n' "$(steps_quote "$STEPS_ROOT")"
    printf './setup-host.sh --host %s\n' "$STEPS_HOST"
    steps_block_end
}

# --- S2-modules (hpc, judgment, reminder) ----------------------------------

step_S2_modules_check() {
    if steps_probe claude && steps_probe codex; then
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

step_S5_claude_plan() {
    local path digest size
    steps_block_begin S5-claude inspect
    if ! steps_installer_fields claude; then
        printf '# no installers.tsv claude row for %s\n' "$STEPS_HOST"
        steps_block_end
        return 0
    fi
    path=$(steps_scratch_file claude "$STEPS_URL")
    if [ "$STEPS_MODE" = apply ] && [ -f "$path" ] && digest=$(bootstrap_sha256 "$path"); then
        size=$(wc -c <"$path" | tr -d ' ')
        printf '# downloaded %s (unpinned vendor script)\n' "$STEPS_URL"
        printf '# sha256 %s, %s bytes\n' "$digest" "$size"
    else
        printf '# ./setup-host.sh --host %s (without --check) downloads %s (unpinned)\n' "$STEPS_HOST" "$STEPS_URL"
        printf '%s\n' '# to the path below and prints its sha256 and size'
    fi
    printf '# read %s first, then run:\n' "$(steps_quote "$path")"
    printf 'bash %s\n' "$(steps_quote "$path")"
    printf '%s\n' '# ./doctor.sh then checks the installed claude against tools.tsv'
    steps_block_end
}

# --- H7-stow (judgment, blocking) ------------------------------------------

# steps_stowed: 0 when ~/.zshrc is a stow link into this checkout's common/.
steps_stowed() {
    local link=$HOME/.zshrc resolved
    if [ ! -L "$link" ]; then
        STEP_DETAIL="$link is not a stow link yet"
        return 1
    fi
    resolved=$(steps_resolve "$link") || resolved=
    case $resolved in
        "$STEPS_ROOT/common/"*)
            STEP_DETAIL="$link links into $STEPS_ROOT/common"
            return 0
            ;;
    esac
    STEP_DETAIL="$link points to ${resolved:-a missing file}, not into $STEPS_ROOT/common"
    return 1
}

step_H7_stow_check() {
    steps_stowed && return 0
    if ! steps_probe oh-my-zsh; then
        STEP_DETAIL='oh-my-zsh must be cloned before ./stow-all.sh (S3-clones), or stow creates ~/.oh-my-zsh/custom first'
        return 4
    fi
    return 1
}

step_H7_stow_plan() {
    steps_block_begin H7-stow judgment
    printf '%s\n' '# writes ~/.claude, ~/.codex and ~/.ssh; an agent runs it only as one visible top-level command'
    printf 'cd %s\n' "$(steps_quote "$STEPS_ROOT")"
    printf './stow-all.sh %s\n' "$STEPS_HOST"
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

step_H7_auth_plan() {
    steps_block_begin H7-auth auth
    if [ "$STEPS_MODE" = manual ] || [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        printf '%s\n' 'ssh-keygen -t ed25519'
    fi
    printf '%s\n' 'gh auth login --git-protocol ssh' \
        '# do not run gh auth setup-git: it writes the stowed ~/.gitconfig; .gitconfig_local sets the helper' \
        '# Claude Code signs in on its first interactive run' \
        'claude' \
        '# add --device-auth on a host without a browser' \
        'codex login'
    if [ "$STEPS_PROFILE" = hpc ]; then
        printf '%s\n' 'kinit'
    fi
    steps_block_end
}

# --- H7-sync-skills (judgment, reminder) -----------------------------------

step_H7_sync_skills_check() {
    if [ -f "${XDG_CACHE_HOME:-$HOME/.cache}/awesome-skills/last-sync" ]; then
        STEP_DETAIL='awesome-skills has synced on this host'
        return 0
    fi
    STEP_DETAIL='optional skill library sync has not run'
    return 1
}

step_H7_sync_skills_plan() {
    steps_block_begin H7-sync-skills judgment
    printf '%s\n' \
        '# opt-in: an unpinned curl of awesome-skills main (raw.githubusercontent.com/FridrichMethod/awesome-skills/main/install.sh)' \
        '# that installs into ~/.claude/skills and ~/.codex/skills; after stow the sync-skills alias runs the same'
    printf 'AWESOME_SKILLS_FORCE=1 AWESOME_SKILLS_BG=0 sh %s\n' "$(steps_quote "$STEPS_ROOT/scripts/awesome-skills-update.sh")"
    steps_block_end
}

# --- H7-doctor (judgment, reminder) ----------------------------------------

step_H7_doctor_check() {
    STEP_DETAIL="the completion gate is ./doctor.sh --host $STEPS_HOST"
    return 1
}

step_H7_doctor_plan() {
    steps_block_begin H7-doctor judgment
    printf 'cd %s\n' "$(steps_quote "$STEPS_ROOT")"
    printf './doctor.sh --host %s\n' "$STEPS_HOST"
    printf './doctor.sh --host %s --smoke\n' "$STEPS_HOST"
    steps_block_end
}
