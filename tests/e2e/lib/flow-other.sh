# shellcheck shell=bash
# shellcheck disable=SC2034 # E2E_BROKEN is read by common.sh and steps.sh
# The other-Linux flow of tests/e2e/inside.sh (Fedora, no overlay): the
# native docs/bootstrap.md X-other-linux route done as the person does it:
# the distribution's packages, the fetch_pinned and clone_listed helpers
# taken from the clone's own docs, the clone loop, the bat theme, the vim
# dirs, the by-hand S4-chezmoi line, then the common-only role deployed by
# hand (native_handover common-only, Fresh home by hand), the login shell,
# the payload repos, the native convergence check, the doctor, the
# common-only negatives, the isolated native fixtures and the audits.
# Sourced after steps.sh; same portability rules.

E2E_HELPERS='' # the helper functions extracted from docs/bootstrap.md
# The by-hand S4-chezmoi line of docs/bootstrap.md, byte for byte (the
# harness checks the doc still holds it): the generic Linux archive of the
# first installers.tsv row for the architecture, its one executable written
# beside the target and moved into place.
E2E_CHEZMOI_LINE='f=$(fetch_pinned chezmoi "$(uname -m)") && mkdir -p "$HOME/.local/bin" && tar -xzOf "$f" chezmoi >"$HOME/.local/bin/chezmoi.new" && chmod 755 "$HOME/.local/bin/chezmoi.new" && mv -f "$HOME/.local/bin/chezmoi.new" "$HOME/.local/bin/chezmoi"'

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
# fetch_pinned and clone_listed definitions and nothing else (the rules and
# messages of e2e_extract_fence in steps.sh). Returns 1 with the reason
# printed.
e2e_extract_helpers() {
    e2e_extract_fence "$1" 'Downloads and clones by hand' "$2" fetch_pinned clone_listed
}

# e2e_step_helpers: define the helpers from the clone's docs/bootstrap.md.
e2e_step_helpers() {
    local reason
    e2e_step_begin helpers setup:helpers
    E2E_HELPERS=${E2E_STEP_LOG%.log}.sh
    if reason=$(e2e_extract_helpers "$E2E_CLONE/docs/bootstrap.md" "$E2E_HELPERS" 2>>"$E2E_STEP_LOG"); then
        e2e_step_end pass "fetch_pinned and clone_listed from docs/bootstrap.md ($(grep -c . "$E2E_HELPERS") lines)"
    else
        E2E_BROKEN=helpers
        e2e_step_end fail "docs/bootstrap.md: $reason"
        return 1
    fi
}

# e2e_by_hand NAME COMMAND [VERIFY]: one by-hand step of the quick start:
# COMMAND in the clone, in a bash that sourced the helpers with
# dotfiles_checkout naming the clone; then VERIFY, a function that prints what it found and returns 1 when
# the step did not do its job.
e2e_by_hand() {
    local rc=0 found=''
    e2e_step_begin "$1" "setup:$1"
    e2e_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "$E2E_TIMEOUT_APPLY" "$E2E_CLONE" \
        env dotfiles_checkout="$E2E_CLONE" bash -c ". $(e2e_quote "$E2E_HELPERS") && $2" || rc=$?
    if [ "$rc" != 0 ]; then
        E2E_BROKEN=$1
        e2e_step_end fail "exit $rc: $(e2e_last_line "$E2E_STEP_ERR")"
        return 1
    fi
    if [ -n "${3:-}" ] && ! found=$("$3"); then
        E2E_BROKEN=$1
        e2e_step_end fail "exit 0, but $found"
        return 1
    fi
    e2e_step_end pass "exit 0: $(e2e_one_line "$2" 200)${found:+; $found}"
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

# e2e_chezmoi_version: ~/.local/bin/chezmoi --version names the release the
# clone pins in .chezmoiversion.
e2e_chezmoi_version() {
    local want text
    want=v$(cat "$E2E_CLONE/.chezmoiversion" 2>/dev/null)
    text=$("$HOME/.local/bin/chezmoi" --version 2>&1 </dev/null) || text="exit $?: $text"
    case $text in
        *"$want"*)
            printf '%s\n' "$(e2e_one_line "$text" 120)"
            return 0
            ;;
    esac
    printf 'the chezmoi in ~/.local/bin reports [%s], not %s\n' "$(e2e_one_line "$text" 120)" "$want"
    return 1
}

e2e_step_chezmoi() {
    e2e_by_hand chezmoi "$E2E_CHEZMOI_LINE" e2e_chezmoi_version
}

# e2e_step_handover_common_only: the native handover of the common-only role.
e2e_step_handover_common_only() { e2e_step_native_handover common-only; }

# e2e_flow_other: the whole sequence for a Linux without an overlay.
e2e_flow_other() {
    e2e_step_clone || true
    e2e_or_skip doctor-initial e2e_step_doctor_initial
    e2e_or_skip packages e2e_step_packages
    e2e_or_skip helpers e2e_step_helpers
    e2e_or_skip clones e2e_step_clones
    e2e_or_skip bat-theme e2e_step_bat_theme
    e2e_or_skip dirs e2e_step_dirs
    e2e_or_skip chezmoi e2e_step_chezmoi
    e2e_or_skip native-handover e2e_step_handover_common_only
    e2e_or_skip login-shell e2e_step_login_shell
    e2e_or_skip payloads e2e_step_payloads
    e2e_or_skip native-converged e2e_step_native_converged
    e2e_or_skip doctor-final e2e_step_doctor_final
    e2e_or_skip doctor-smoke e2e_step_doctor_smoke
    e2e_negatives
    e2e_or_skip native-fixtures e2e_step_native_fixtures
    e2e_audits
}
