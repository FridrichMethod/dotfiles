# shellcheck shell=bash
# The steps both flows of tests/e2e/inside.sh share: the clone, the initial
# read-only doctor run, the login-shell check, the final doctor runs from
# the login environment, the negatives and the closing audits. Each step
# function opens its step, runs, and closes it with a verdict; a step the
# rest depends on sets E2E_BROKEN when it fails, and the flows then skip
# what cannot run. Sourced after assert.sh; same portability rules.

E2E_UPSTREAM=https://github.com/FridrichMethod/dotfiles.git
# The first apply run, which the alloc-first negative judges afterwards.
E2E_APPLY1_OUT='' E2E_APPLY1_RC=''

# e2e_step_clone: the clone a person makes, from the read-only source
# checkout at E2E_REV (with its submodules), its origin pointed at GitHub as
# a real clone has it. Everything after it runs with the login hooks off, as
# docs/bootstrap.md asks of every provisioning shell.
e2e_step_clone() {
    local rc=0 o e
    e2e_step_begin clone setup:clone
    o=$E2E_STEP_OUT e=$E2E_STEP_ERR
    e2e_run "$o" "$e" "$E2E_TIMEOUT_CHECK" "$HOME" git clone --recurse-submodules "$E2E_SRC" "$E2E_CLONE" &&
        e2e_run "$o" "$e" "$E2E_TIMEOUT_CHECK" "$HOME" git -C "$E2E_CLONE" -c advice.detachedHead=false \
            checkout --detach "$E2E_REV" &&
        e2e_run "$o" "$e" "$E2E_TIMEOUT_CHECK" "$HOME" git -C "$E2E_CLONE" submodule update --init --recursive &&
        e2e_run "$o" "$e" "$E2E_TIMEOUT_CHECK" "$HOME" git -C "$E2E_CLONE" remote set-url origin "$E2E_UPSTREAM" ||
        rc=$?
    if [ "$rc" != 0 ]; then
        E2E_BROKEN=clone
        e2e_step_end fail "git exited $rc: $(e2e_last_line "$e")"
        return 1
    fi
    export DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0 GIT_TERMINAL_PROMPT=0
    e2e_step_end pass "$(git -C "$E2E_CLONE" rev-parse --short HEAD) at $E2E_CLONE"
}

# e2e_step_doctor_initial: ./doctor.sh E2E_DOCTOR_ARGS --tsv on the fresh
# home exits 1 (tools are missing) and writes nothing, in TMPDIR or HOME.
e2e_step_doctor_initial() {
    local rc=0 problems
    e2e_step_begin doctor-initial check:doctor-initial
    e2e_nowrite_begin doctor-initial
    # shellcheck disable=SC2086 # E2E_DOCTOR_ARGS is a list of words
    e2e_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "$E2E_TIMEOUT_CHECK" "$E2E_CLONE" \
        env TMPDIR="$E2E_NW_TMP" ./doctor.sh $E2E_DOCTOR_ARGS --tsv || rc=$?
    problems=$(e2e_nowrite_end doctor-initial)
    if [ "$rc" != 1 ]; then
        e2e_step_end fail "exit $rc, expected 1 on a fresh home${problems:+; $problems}"
    elif [ -n "$problems" ]; then
        e2e_step_end fail "$problems"
    else
        e2e_step_end pass "exit 1; $(e2e_tsv_counts "$E2E_STEP_OUT")no writes"
    fi
}

# e2e_step_login_shell: a fresh login shell (bash -l, then the host's zsh
# -il) exits 0 and prints nothing.
e2e_step_login_shell() {
    e2e_step_begin login-shell check:login-shell
    if e2e_login_shell_check "$E2E_STEP_OUT" "$E2E_STEP_ERR"; then
        e2e_step_end pass "$E2E_LOGIN_DETAIL; silent"
    else
        e2e_step_end fail "$E2E_LOGIN_DETAIL"
    fi
}

# e2e_step_doctor_final / e2e_step_doctor_smoke: ./doctor.sh E2E_DOCTOR_ARGS,
# then --smoke, from the stowed login environment, exit 0.
e2e_doctor_from_login() {
    local name=$1 extra=$2 rc=0
    e2e_step_begin "$name" "check:$name"
    e2e_login_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "cd ~/dotfiles && ./doctor.sh $E2E_DOCTOR_ARGS$extra" || rc=$?
    if [ "$rc" = 0 ]; then
        e2e_step_end pass "exit 0 from the login shell"
    else
        e2e_step_end fail "exit $rc: $(e2e_problem_lines "$E2E_STEP_OUT")"
    fi
}

e2e_step_doctor_final() { e2e_doctor_from_login doctor-final ''; }
e2e_step_doctor_smoke() { e2e_doctor_from_login doctor-smoke ' --smoke'; }

# --- negatives ---------------------------------------------------------------

# e2e_negative_refusal RC TEXT COMMAND...: COMMAND, in the clone, must exit
# RC and mention TEXT on stderr.
e2e_negative_refusal() {
    local want=$1 text=$2 rc=0
    shift 2
    e2e_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "$E2E_TIMEOUT_CHECK" "$E2E_CLONE" "$@" || rc=$?
    if [ "$rc" != "$want" ]; then
        e2e_step_end fail "exit $rc, expected $want: $(e2e_last_line "$E2E_STEP_ERR")"
    elif ! grep -F -- "$text" "$E2E_STEP_ERR" >/dev/null 2>&1; then
        e2e_step_end fail "exit $rc but stderr lacks [$text]: $(e2e_last_line "$E2E_STEP_ERR")"
    else
        e2e_step_end pass "exit $rc: $(e2e_last_line "$E2E_STEP_ERR")"
    fi
}

# e2e_negative_common_only: after the host-less stow, ./doctor.sh with no
# arguments exits 0 and warns about the common-only install; ./setup-host.sh
# without --host exits 2 for the same reason.
e2e_negative_common_only() {
    local rc=0
    e2e_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "$E2E_TIMEOUT_CHECK" "$E2E_CLONE" ./doctor.sh || rc=$?
    if [ "$rc" != 0 ]; then
        e2e_step_end fail "./doctor.sh exited $rc, expected 0: $(e2e_problem_lines "$E2E_STEP_OUT")"
        return 0
    fi
    if ! grep -F 'common-only' "$E2E_STEP_ERR" >/dev/null 2>&1; then
        e2e_step_end fail './doctor.sh exited 0 without the common-only warning'
        return 0
    fi
    rc=0
    e2e_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "$E2E_TIMEOUT_CHECK" "$E2E_CLONE" ./setup-host.sh --check || rc=$?
    if [ "$rc" != 2 ]; then
        e2e_step_end fail "./setup-host.sh --check without --host exited $rc, expected 2: $(e2e_last_line "$E2E_STEP_ERR")"
    elif ! grep -F 'common-only' "$E2E_STEP_ERR" >/dev/null 2>&1; then
        e2e_step_end fail "./setup-host.sh --check exited 2 without naming the common-only install: $(e2e_last_line "$E2E_STEP_ERR")"
    else
        e2e_step_end pass "./doctor.sh exit 0 with the common-only warning; ./setup-host.sh --check exit 2: $(e2e_last_line "$E2E_STEP_ERR")"
    fi
}

# e2e_negatives: one step per E2E_NEGATIVE token, each in its own
# negative:<token> phase; a token the harness does not know fails.
e2e_negatives() {
    local token host=${E2E_SETUP_HOST:-lab-ubuntu} name
    for token in ${E2E_NEGATIVE:-}; do
        name=negative-$token
        if [ -n "$E2E_BROKEN" ]; then
            e2e_skip "$name" "after $E2E_BROKEN failed"
            continue
        fi
        if [ "$token" = root-refused ] && [ "${E2E_SUDO:-}" != yes ]; then
            e2e_skip "$name" 'no sudo on this host'
            continue
        fi
        e2e_step_begin "$name" "negative:$token"
        case $token in
            wsl-refused) e2e_negative_refusal 2 WSL ./setup-host.sh --host wsl-ubuntu --check ;;
            lab-refused-in-wsl) e2e_negative_refusal 2 WSL ./setup-host.sh --host lab-ubuntu --check ;;
            # Lmod's profile.d also exports BASH_ENV=.../init/bash, which every
            # bash script sources on start, re-exporting LMOD_DIR; a machine
            # without Lmod has neither.
            hpc-no-lmod) e2e_negative_refusal 2 LMOD_DIR env -u LMOD_DIR -u BASH_ENV ./setup-host.sh --host "$host" --check ;;
            # setup-host checks for root before it resolves the host, so a
            # stand-in host serves the other-Linux flow too.
            root-refused) e2e_negative_refusal 2 'not root' sudo -n ./setup-host.sh --host "$host" --check ;;
            alloc-first)
                if [ "$E2E_APPLY1_RC" = 3 ] && grep -Fx 'HUMAN-BEGIN H2-alloc alloc' "$E2E_APPLY1_OUT" >/dev/null 2>&1; then
                    e2e_step_end pass 'the first apply exited 3 with the H2-alloc block'
                else
                    e2e_step_end fail "the first apply exited ${E2E_APPLY1_RC:-?} (expected 3 with an H2-alloc alloc block)"
                fi
                ;;
            common-only) e2e_negative_common_only ;;
            *) e2e_step_end fail "unknown E2E_NEGATIVE token $token" ;;
        esac
    done
}

# --- audits ------------------------------------------------------------------

# e2e_audits: the acceptance audits over the whole run: (1) every wrapper
# call happened in a human:* or negative:* phase, and a host without sudo
# saw no sudo at all; (2) every sudo.log entry falls in such a window; (3)
# the stow state appeared only in human:H7-stow; (4) the login shell is
# unchanged; (5) the rc files changed only in human phases.
e2e_audits() {
    local log=$E2E_OUT/log/wrappers.log sudo_log=$E2E_OUT/log/sudo.log bad rc=0 shell
    e2e_step_begin audit-wrappers check:audit-wrappers
    if [ ! -f "$log" ]; then
        if [ "${E2E_SUDO:-}" = yes ]; then
            e2e_step_end fail 'no log/wrappers.log, although this host runs sudo blocks through the wrappers'
        else
            e2e_step_end pass 'no wrapper call was logged'
        fi
    elif ! bad=$(e2e_audit_wrappers "$log"); then
        e2e_step_end fail "wrapper calls outside human/negative phases: $(e2e_one_line "$bad" 400)"
    elif [ "${E2E_SUDO:-}" != yes ] && ! bad=$(e2e_audit_no_sudo "$log"); then
        e2e_step_end fail "sudo called on a host without sudo: $(e2e_one_line "$bad" 400)"
    else
        e2e_step_end pass "$(grep -c . "$log") wrapper call(s), all in human or negative phases"
    fi

    e2e_step_begin audit-sudo-log check:audit-sudo-log
    if [ "${E2E_SUDO:-}" != yes ] || [ ! -f "$sudo_log" ]; then
        e2e_step_end skip 'no log/sudo.log (no sudo here, or sudo logs elsewhere)'
    else
        bad=$(e2e_audit_sudo_log "$E2E_OUT/log/timeline" "$sudo_log") || rc=$?
        case $rc in
            0) e2e_step_end pass "$(grep -Ec '^[A-Z][a-z]{2} ' "$sudo_log") sudo entries, all inside human/negative windows" ;;
            2) e2e_step_end skip 'no GNU date -d to parse the sudo.log timestamps' ;;
            *) e2e_step_end fail "sudo.log entries outside the human/negative windows: $(e2e_one_line "$bad" 400)" ;;
        esac
    fi

    e2e_step_begin audit-stow-state check:audit-stow-state
    if [ -n "$E2E_STOW_VIOLATIONS" ]; then
        e2e_step_end fail "stow state or ~/.zshrc link changed outside human:H7-stow: $E2E_STOW_VIOLATIONS"
    elif [ "$E2E_STOWED" = 1 ]; then
        e2e_step_end pass 'the stow state file and ~/.zshrc appeared during human:H7-stow only'
    else
        e2e_step_end fail 'the stow never happened'
    fi

    e2e_step_begin audit-login-shell check:audit-login-shell
    shell=$(e2e_login_shell_of)
    if [ "$shell" = "$E2E_LOGIN_SHELL_START" ]; then
        e2e_step_end pass "login shell still $shell"
    else
        e2e_step_end fail "login shell changed from $E2E_LOGIN_SHELL_START to $shell"
    fi

    e2e_step_begin audit-rc-files check:audit-rc-files
    if [ -n "$E2E_RC_VIOLATIONS" ]; then
        e2e_step_end fail "rc files changed outside human phases: $E2E_RC_VIOLATIONS"
    else
        e2e_step_end pass 'rc files changed in human phases only'
    fi
}
