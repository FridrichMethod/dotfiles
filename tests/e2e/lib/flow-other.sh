# shellcheck shell=bash
# shellcheck disable=SC2034 # E2E_BROKEN is read by common.sh and steps.sh
# The other-Linux flow of tests/e2e/inside.sh (Fedora, no overlay): the
# docs/bootstrap.md "Other Linux" quick start and X-other-linux done as the
# person does them: the distribution's packages, the fetch_pinned and
# clone_listed helpers taken from the clone's own docs, the clone loop, the
# bat theme, the vim dirs, setup-sync, the host-less stow, then the login
# shell, the doctor, the common-only negatives and the audits. Sourced after
# steps.sh; same portability rules.

E2E_HELPERS='' # the helper functions extracted from docs/bootstrap.md

# e2e_step_packages: E2E_PKG_INSTALL E2E_PACKAGES as one sudo line, in the
# human:packages phase (the one place the sudo.log audit allows dnf).
e2e_step_packages() {
    local rc=0
    e2e_step_begin packages human:packages
    e2e_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "$E2E_TIMEOUT_BLOCK" "$HOME" bash -c "$E2E_PKG_INSTALL $E2E_PACKAGES" || rc=$?
    if [ "$rc" != 0 ]; then
        E2E_BROKEN=packages
        e2e_step_end fail "exit $rc: $(e2e_last_line "$E2E_STEP_ERR")"
        return 1
    fi
    e2e_step_end pass "$E2E_PKG_INSTALL $(printf '%s\n' "$E2E_PACKAGES" | wc -w | tr -d ' ') packages"
}

# e2e_extract_helpers DOC FILE: the fenced sh block that follows the
# "Downloads and clones by hand" heading of DOC, written to FILE: the
# fetch_pinned and clone_listed definitions, taken from the clone instead of
# copied here, so the test runs what the playbook prints.
e2e_extract_helpers() {
    awk '
        /^#+ Downloads and clones by hand/ { seen = 1; next }
        seen && !inside && /^```sh/ { inside = 1; next }
        inside && /^```/ { exit }
        inside { print }
    ' "$1" >"$2"
    [ -s "$2" ] || return 1
    bash -n "$2" || return 1
    grep -E '^fetch_pinned\(\)' "$2" >/dev/null && grep -E '^clone_listed\(\)' "$2" >/dev/null
}

# e2e_step_helpers: define the helpers from the clone's docs/bootstrap.md.
e2e_step_helpers() {
    e2e_step_begin helpers setup:helpers
    E2E_HELPERS=${E2E_STEP_LOG%.log}.sh
    if e2e_extract_helpers "$E2E_CLONE/docs/bootstrap.md" "$E2E_HELPERS" 2>>"$E2E_STEP_LOG"; then
        e2e_step_end pass "fetch_pinned and clone_listed from docs/bootstrap.md ($(grep -c . "$E2E_HELPERS") lines)"
    else
        E2E_BROKEN=helpers
        e2e_step_end fail 'docs/bootstrap.md has no usable fenced sh block after "Downloads and clones by hand"'
        return 1
    fi
}

# e2e_by_hand NAME COMMAND: one by-hand step of the quick start: COMMAND in
# the clone, in a bash that sourced the helpers with DOTFILES_DIR set.
e2e_by_hand() {
    local rc=0
    e2e_step_begin "$1" "setup:$1"
    e2e_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "$E2E_TIMEOUT_APPLY" "$E2E_CLONE" \
        env DOTFILES_DIR="$E2E_CLONE" bash -c ". $(e2e_quote "$E2E_HELPERS") && $2" || rc=$?
    if [ "$rc" != 0 ]; then
        E2E_BROKEN=$1
        e2e_step_end fail "exit $rc: $(e2e_last_line "$E2E_STEP_ERR")"
        return 1
    fi
    e2e_step_end pass "exit 0: $(e2e_one_line "$2" 200)"
}

# The quick start's lines, verbatim but for the loop's break turned into a
# failure the step reports.
e2e_step_clones() {
    e2e_by_hand clones 'for id in $(awk -F '"'"'\t'"'"' '"'"'/^#/ { next } !h { h = 1; next } { print $1 }'"'"' config/bootstrap/git-clones.tsv); do clone_listed "$id" || exit 1; done'
}

e2e_step_bat_theme() {
    e2e_by_hand bat-theme 'f=$(fetch_pinned bat-theme) && d="$(bat --config-dir)/themes" && mkdir -p "$d" && cp "$f" "$d/Catppuccin Mocha.tmTheme" && bat cache --build'
}

e2e_step_dirs() {
    e2e_by_hand dirs 'mkdir -p ~/.vim/undo ~/.vim/tmp'
}

e2e_step_setup_sync() {
    e2e_by_hand setup-sync './setup-sync.sh'
}

# e2e_skel_conflicts: the home files ./stow-all.sh would refuse, as H7-stow
# lists them on a host with an overlay (steps_stow_conflicts): a regular file
# in HOME where a common/ package tracks a top-level file of that name (the
# /etc/skel .bashrc, .bash_profile and .profile on a fresh account), one per
# line.
e2e_skel_conflicts() {
    local tracked rest path name
    tracked=$(git -C "$E2E_CLONE" ls-files -- common 2>/dev/null </dev/null)
    rest=$tracked${tracked:+$E2E_NL}
    while [ -n "$rest" ]; do
        path=${rest%%"$E2E_NL"*}
        rest=${rest#*"$E2E_NL"}
        case $path in
            common/*/*/* | '' | */.stow-local-ignore) continue ;;
            common/*/*) name=${path##*/} ;;
            *) continue ;;
        esac
        [ -f "$HOME/$name" ] && [ ! -L "$HOME/$name" ] || continue
        printf '%s\n' "$name"
    done
}

# e2e_step_stow_other: H7-stow without a host: each /etc/skel conflict moved
# aside with its own mv -n, then ./stow-all.sh, all in human:H7-stow.
e2e_step_stow_other() {
    local conflicts rest name rc=0 moved=0
    e2e_step_begin H7-stow human:H7-stow
    conflicts=$(e2e_skel_conflicts)
    rest=$conflicts${conflicts:+$E2E_NL}
    while [ -n "$rest" ]; do
        name=${rest%%"$E2E_NL"*}
        rest=${rest#*"$E2E_NL"}
        [ -n "$name" ] || continue
        e2e_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "$E2E_TIMEOUT_CHECK" "$HOME" \
            bash -c "mv -n $(e2e_quote "$HOME/$name") $(e2e_quote "$HOME/$name.pre-dotfiles")" || rc=$?
        if [ "$rc" != 0 ]; then
            E2E_BROKEN=H7-stow
            e2e_step_end fail "mv -n $name exited $rc: $(e2e_last_line "$E2E_STEP_ERR")"
            return 1
        fi
        moved=$((moved + 1))
    done
    e2e_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "$E2E_TIMEOUT_APPLY" "$E2E_CLONE" ./stow-all.sh || rc=$?
    if [ "$rc" != 0 ]; then
        E2E_BROKEN=H7-stow
        e2e_step_end fail "./stow-all.sh exited $rc: $(e2e_problem_lines "$E2E_STEP_ERR")"
        return 1
    fi
    e2e_step_end pass "$moved skel file(s) moved aside, ./stow-all.sh (common only) exit 0"
}

# e2e_flow_other: the whole sequence for a Linux without an overlay.
e2e_flow_other() {
    e2e_step_clone || true
    e2e_or_skip doctor-initial e2e_step_doctor_initial
    e2e_or_skip packages e2e_step_packages
    e2e_or_skip helpers e2e_step_helpers
    e2e_or_skip clones e2e_step_clones
    e2e_or_skip bat-theme e2e_step_bat_theme
    e2e_or_skip dirs e2e_step_dirs
    e2e_or_skip setup-sync e2e_step_setup_sync
    e2e_or_skip H7-stow e2e_step_stow_other
    e2e_or_skip login-shell e2e_step_login_shell
    e2e_or_skip doctor-final e2e_step_doctor_final
    e2e_or_skip doctor-smoke e2e_step_doctor_smoke
    e2e_negatives
    e2e_audits
}
