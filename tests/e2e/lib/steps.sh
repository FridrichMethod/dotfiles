# shellcheck shell=bash
# shellcheck disable=SC2034 # E2E_HANDOVER_KEPT and E2E_HANDOVER_DETAIL are read by tests/e2e-harness.sh
# The steps both flows of tests/e2e/inside.sh share: the clone, the initial
# read-only doctor run, the native handover through the documented Fresh
# home by hand procedure and its convergence check, the login-shell check,
# the payload repos' install, the final doctor runs from the login
# environment, the negatives, the isolated native fixtures and the closing
# audits. Each step function opens its step, runs, and closes it with a
# verdict; a step the rest depends on sets E2E_BROKEN when it fails, and the
# flows then skip what cannot run. Sourced after assert.sh; same portability
# rules.

E2E_UPSTREAM=https://github.com/FridrichMethod/dotfiles.git
# The first apply run, which the alloc-first negative judges afterwards.
E2E_APPLY1_OUT='' E2E_APPLY1_RC=''
# The Fresh home by hand functions native-handover extracted from the
# clone's docs/bootstrap.md (native-converged reuses them), and the H7-native
# block of the last apply run, which the handover step stands in for.
E2E_HANDOVER='' E2E_HANDOVER_BLOCK=''
E2E_HANDOVER_KEPT=0 E2E_HANDOVER_DETAIL=''

# e2e_step_clone: the clone a person makes, from the read-only source
# checkout at E2E_REV, its origin pointed at GitHub as a real clone has it.
# Everything after it runs with the login and payload hooks off, as
# docs/bootstrap.md asks of every provisioning shell.
e2e_step_clone() {
    local rc=0 o e
    e2e_step_begin clone setup:clone
    o=$E2E_STEP_OUT e=$E2E_STEP_ERR
    e2e_run "$o" "$e" "$E2E_TIMEOUT_CHECK" "$HOME" git clone "$E2E_SRC" "$E2E_CLONE" &&
        e2e_run "$o" "$e" "$E2E_TIMEOUT_CHECK" "$HOME" git -C "$E2E_CLONE" -c advice.detachedHead=false \
            checkout --detach "$E2E_REV" &&
        e2e_run "$o" "$e" "$E2E_TIMEOUT_CHECK" "$HOME" git -C "$E2E_CLONE" remote set-url origin "$E2E_UPSTREAM" ||
        rc=$?
    if [ "$rc" != 0 ]; then
        E2E_BROKEN=clone
        e2e_step_end fail "git exited $rc: $(e2e_last_line "$e")"
        return 1
    fi
    export DOTFILES_AUTO_UPDATE=0 DOTFILES_PAYLOAD_AUTO_UPDATE=0 GIT_TERMINAL_PROMPT=0
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
# then --smoke, from the deployed login environment, exit 0.
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

# e2e_step_payloads: the run line of the H7-payloads block, `sh
# ~/dotfiles/scripts/payload-update.sh --now`, from the deployed login
# environment, as a person runs it: every payload repo
# of config/payloads.tsv installs from the network through its own
# installer, under the block limit, since three installs run in a row. It
# passes when that exits 0 and the doctor's payloads row is then ok and names
# what it found installed. A setup phase, so an installer that edits an rc
# file, links into the clone or runs sudo fails the audits.
e2e_step_payloads() {
    local rc=0 row detail
    e2e_step_begin payloads setup:payloads
    e2e_login_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" 'sh ~/dotfiles/scripts/payload-update.sh --now' \
        "$E2E_TIMEOUT_BLOCK" || rc=$?
    if [ "$rc" != 0 ]; then
        # The hook logs one [error] line per failed item and goes on.
        detail=$(grep -h -F '[error]' "$E2E_STEP_ERR" "$E2E_STEP_OUT" 2>/dev/null | sed -n 1p)
        [ -n "$detail" ] || detail=$(e2e_last_line "$E2E_STEP_ERR")
        e2e_step_end fail "exit $rc (124 is the ${E2E_TIMEOUT_BLOCK}s timeout): $detail"
        return 0
    fi
    e2e_login_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "cd ~/dotfiles && ./doctor.sh $E2E_DOCTOR_ARGS --tsv" || :
    row=$(awk -F '\t' '$2 == "payloads" { print $1 ": " $4 }' "$E2E_STEP_OUT" 2>/dev/null | sed -n 1p)
    case $row in
        'ok: installed: '*) e2e_step_end pass "exit 0; doctor payloads $row" ;;
        *) e2e_step_end fail "exit 0, but the doctor's payloads row is ${row:-missing}" ;;
    esac
}

# --- the native handover -----------------------------------------------------

# e2e_extract_fence DOC HEADING OUT NAME...: the first fenced sh block after
# the line "#... HEADING" of DOC, written to OUT, taken from the clone instead
# of copied here, so the test runs what the playbook prints. It must parse
# under bash -n and sh -n and define each NAME once, as a "NAME() {" line;
# since OUT is sourced before every use, nothing but those definitions may
# run from it: every other line must be a comment, blank, or an indented
# line inside a definition (through the `}` in column 0). A stray top-level
# line, an example invocation or an export, would run unflagged by the
# audits. Returns 1 with the reason printed.
e2e_extract_fence() {
    local doc=$1 heading=$2 out=$3 name count names='' lacks='' alt='' stray
    shift 3
    awk -v heading="$heading" '
        /^#+ / && !seen {
            text = $0
            sub(/^#+ /, "", text)
            if (index(text, heading) == 1) { seen = 1; next }
        }
        seen && !inside && /^```sh/ { inside = 1; next }
        inside && /^```/ { exit }
        inside { print }
    ' "$doc" >"$out"
    if [ ! -s "$out" ]; then
        printf 'no fenced sh block after "%s"\n' "$heading"
        return 1
    fi
    if ! bash -n "$out"; then
        printf 'the fenced sh block does not parse (bash -n)\n'
        return 1
    fi
    if ! sh -n "$out"; then
        printf 'the fenced sh block does not parse (sh -n)\n'
        return 1
    fi
    for name in "$@"; do
        names="$names${names:+ and }$name"
        lacks="$lacks${lacks:+ or }a \"$name() {\""
        alt="$alt${alt:+|}$name"
    done
    for name in "$@"; do
        count=$(grep -cE "^$name\\(\\) \\{\$" "$out") || count=0
        if [ "$count" = 0 ]; then
            printf 'the fenced sh block lacks %s line\n' "$lacks"
            return 1
        fi
        if [ "$count" != 1 ]; then
            printf 'the fenced sh block defines %s %s times\n' "$name" "$count"
            return 1
        fi
    done
    stray=$(awk -v alt="$alt" '
        !infn && $0 ~ ("^(" alt ")\\(\\) \\{$") { infn = 1; next }
        infn && /^\}$/ { infn = 0; next }
        /^#/ || /^[ \t]*$/ { next }
        infn && /^[ \t]/ { next }
        { print; found = 1; exit }
        END { if (infn && !found) print "(a definition without its closing } in column 0)" }
    ' "$out")
    if [ -n "$stray" ]; then
        printf 'a line outside the %s definitions in the fenced sh block: %s\n' "$names" "$stray"
        return 1
    fi
}

# e2e_handover_problems ROLE: the end state Fresh home by hand promises,
# checked after native_handover ROLE: (a) the binding
# ~/.config/dotfiles/native is a regular file of exactly the three lines
# dotfiles-chezmoi-v1, the physical HOME and the physical clone, mode
# -rw-------; (b) the local config is a regular file whose [data] host is
# ROLE; (c) no maintenance marker; (d) no stray state database beside the
# config; (e) the bound state database exists and is not empty; (f) ~/.zshrc
# is a regular file, not a link; (g) every rc file of E2E_RC_FILES that
# existed when the step began (its E2E_RC_BEFORE digest) has a
# byte-identical copy in ~/.local/state/dotfiles-fresh-backup. Sets
# E2E_HANDOVER_DETAIL to the problems ("; "-separated, empty when none) and
# E2E_HANDOVER_KEPT to the number of copies found; returns 1 on a problem.
e2e_handover_problems() {
    local role=$1 marker=$HOME/.config/dotfiles/native config=$HOME/.config/chezmoi/chezmoi.toml
    local keep=$HOME/.local/state/dotfiles-fresh-backup want mode name before out=''
    E2E_HANDOVER_KEPT=0
    if [ ! -f "$marker" ] || [ -L "$marker" ]; then
        out="$out${out:+; }~/.config/dotfiles/native is missing, a link or not a regular file"
    else
        want=$(printf '%s\n%s\n%s' dotfiles-chezmoi-v1 "$(cd -P -- "$HOME" && pwd -P)" "$(cd -P -- "$E2E_CLONE" && pwd -P)")
        if [ "$(wc -l <"$marker" | tr -d ' ')" != 3 ] || [ "$(cat "$marker")" != "$want" ]; then
            out="$out${out:+; }~/.config/dotfiles/native is not the three-line binding of this home to the clone"
        fi
        # shellcheck disable=SC2012 # the mode column only; no stat -c or -f on both userlands
        mode=$(ls -l "$marker" | cut -c1-10)
        [ "$mode" = -rw------- ] || out="$out${out:+; }~/.config/dotfiles/native is $mode, not -rw-------"
    fi
    if [ ! -f "$config" ] || [ -L "$config" ]; then
        out="$out${out:+; }~/.config/chezmoi/chezmoi.toml is missing, a link or not a regular file"
    elif ! grep -E "^[[:space:]]*host[[:space:]]*=[[:space:]]*['\"]${role}['\"]" "$config" >/dev/null 2>&1; then
        out="$out${out:+; }~/.config/chezmoi/chezmoi.toml does not select host $role"
    fi
    if [ -e "$HOME/.config/dotfiles/maintenance" ] || [ -L "$HOME/.config/dotfiles/maintenance" ]; then
        out="$out${out:+; }~/.config/dotfiles/maintenance exists"
    fi
    if [ -e "$HOME/.config/chezmoi/chezmoistate.boltdb" ] || [ -L "$HOME/.config/chezmoi/chezmoistate.boltdb" ]; then
        out="$out${out:+; }~/.config/chezmoi/chezmoistate.boltdb exists (a chezmoi run without the explicit argument set)"
    fi
    [ -s "$HOME/.local/state/chezmoi/chezmoi.boltdb" ] ||
        out="$out${out:+; }~/.local/state/chezmoi/chezmoi.boltdb is missing or empty"
    if [ ! -f "$HOME/.zshrc" ] || [ -L "$HOME/.zshrc" ]; then
        out="$out${out:+; }~/.zshrc is missing, a link or not a regular file"
    fi
    for name in $E2E_RC_FILES; do
        before=$(e2e_rc_pick "$E2E_RC_BEFORE" "$name")
        [ "$before" != missing ] || continue
        if [ -f "$keep/$name" ] && [ ! -L "$keep/$name" ] && [ "$(e2e_sha256 "$keep/$name")" = "$before" ]; then
            E2E_HANDOVER_KEPT=$((E2E_HANDOVER_KEPT + 1))
        else
            out="$out${out:+; }no byte-identical copy of ~/$name in ~/.local/state/dotfiles-fresh-backup"
        fi
    done
    E2E_HANDOVER_DETAIL=$out
    [ -z "$out" ]
}

# e2e_step_native_handover ROLE: H7-native done the way a person does it on
# a fresh home: the clone's docs/bootstrap.md "Fresh home by hand" fence
# (native_cz and native_handover), extracted strictly, then `native_handover
# ROLE` from the clone in one bash, ROLE being E2E_SETUP_HOST or
# common-only. It runs in human:H7-native, the phase whose rc-file changes
# the guard records as a note, and the step log starts with the H7-native
# block it stands in for. It passes when that exits 0 and the end state is
# the documented one (e2e_handover_problems).
e2e_step_native_handover() {
    local role=$1 rc=0 reason phys
    e2e_step_begin native-handover human:H7-native
    if [ -n "$E2E_HANDOVER_BLOCK" ] && [ -f "$E2E_HANDOVER_BLOCK" ]; then
        {
            printf -- '--- block\n'
            cat "$E2E_HANDOVER_BLOCK"
        } >>"$E2E_STEP_LOG"
    fi
    E2E_HANDOVER=${E2E_STEP_LOG%.log}.sh
    # On failure the function prints its reason; stderr goes to the log.
    if ! reason=$(e2e_extract_fence "$E2E_CLONE/docs/bootstrap.md" 'Fresh home by hand' "$E2E_HANDOVER" \
        native_cz native_handover 2>>"$E2E_STEP_LOG"); then
        E2E_BROKEN=native-handover
        e2e_step_end fail "docs/bootstrap.md: $reason"
        return 1
    fi
    e2e_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "$E2E_TIMEOUT_APPLY" "$E2E_CLONE" \
        bash -c ". $(e2e_quote "$E2E_HANDOVER") && native_handover $(e2e_quote "$role")" || rc=$?
    if [ "$rc" != 0 ]; then
        E2E_BROKEN=native-handover
        e2e_step_end fail "native_handover $role exit $rc: $(e2e_last_line "$E2E_STEP_ERR")"
        return 1
    fi
    if ! e2e_handover_problems "$role"; then
        E2E_BROKEN=native-handover
        e2e_step_end fail "native_handover $role exit 0, but $E2E_HANDOVER_DETAIL"
        return 1
    fi
    phys=$(cd -P -- "$E2E_CLONE" && pwd -P)
    e2e_step_end pass "native_handover $role exit 0; $E2E_HANDOVER_KEPT earlier file(s) kept byte for byte; bound to $phys"
}

# e2e_step_check_done: after the handover, ./setup-host.sh --host H --check
# has nothing left: exit 0, no todo line, and no write in TMPDIR or HOME.
e2e_step_check_done() {
    local rc=0 problems todo
    e2e_step_begin check-done check:check-done
    e2e_nowrite_begin check-done
    e2e_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "$E2E_TIMEOUT_CHECK" "$E2E_CLONE" \
        env TMPDIR="$E2E_NW_TMP" ./setup-host.sh --host "$E2E_SETUP_HOST" --check || rc=$?
    problems=$(e2e_nowrite_end check-done)
    todo=$(grep -E '^[A-Za-z0-9-]+ todo ' "$E2E_STEP_OUT" 2>/dev/null) || true
    if [ "$rc" != 0 ]; then
        e2e_step_end fail "exit $rc, expected 0 after the handover (pending: $(e2e_pending_ids "$E2E_STEP_ERR")): $(e2e_failure_detail "$E2E_STEP_OUT" "$E2E_STEP_ERR")${problems:+; $problems}"
    elif [ -n "$todo" ]; then
        e2e_step_end fail "exit 0 with steps still to apply: $(e2e_one_line "$todo" 300)"
    elif [ -n "$problems" ]; then
        e2e_step_end fail "$problems"
    else
        e2e_step_end pass 'exit 0; nothing left to apply; no writes'
    fi
}

# e2e_step_native_converged: with the functions native-handover extracted,
# `native_cz diff --exclude=dirs` from the clone exits 0 and prints nothing
# (after the payload repos ran, so an installer that edits a managed target
# shows here), every `native_cz managed --include=files,symlinks` target is
# a regular file in HOME, and the stray state database is still absent.
e2e_step_native_converged() {
    local rc=0 rel count=0 bad='' headers
    e2e_step_begin native-converged check:native-converged
    if [ -z "$E2E_HANDOVER" ] || [ ! -f "$E2E_HANDOVER" ]; then
        e2e_step_end fail 'no extracted Fresh home by hand functions (native-handover did not run)'
        return 0
    fi
    e2e_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "$E2E_TIMEOUT_CHECK" "$E2E_CLONE" \
        bash -c ". $(e2e_quote "$E2E_HANDOVER") && native_cz diff --exclude=dirs" || rc=$?
    if [ "$rc" != 0 ]; then
        e2e_step_end fail "native_cz diff --exclude=dirs exit $rc: $(e2e_last_line "$E2E_STEP_ERR")"
        return 0
    fi
    if [ -s "$E2E_STEP_OUT" ]; then
        headers=$(grep -E '^diff ' "$E2E_STEP_OUT" 2>/dev/null | sed -n 1,5p)
        [ -n "$headers" ] || headers=$(sed -n 1,3p "$E2E_STEP_OUT")
        e2e_step_end fail "native_cz diff --exclude=dirs is not empty: $(e2e_one_line "$headers" 400)"
        return 0
    fi
    e2e_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "$E2E_TIMEOUT_CHECK" "$E2E_CLONE" \
        bash -c ". $(e2e_quote "$E2E_HANDOVER") && native_cz managed --include=files,symlinks" || rc=$?
    if [ "$rc" != 0 ]; then
        e2e_step_end fail "native_cz managed --include=files,symlinks exit $rc: $(e2e_last_line "$E2E_STEP_ERR")"
        return 0
    fi
    while IFS= read -r rel || [ -n "$rel" ]; do
        [ -n "$rel" ] || continue
        count=$((count + 1))
        if [ ! -f "$HOME/$rel" ] || [ -L "$HOME/$rel" ]; then
            bad="$bad${bad:+ }$rel"
        fi
    done <"$E2E_STEP_OUT"
    if [ -n "$bad" ]; then
        e2e_step_end fail "managed targets that are not regular files: $(e2e_one_line "$bad" 300)"
    elif [ "$count" = 0 ]; then
        e2e_step_end fail 'native_cz managed --include=files,symlinks listed no target'
    elif [ -e "$HOME/.config/chezmoi/chezmoistate.boltdb" ] || [ -L "$HOME/.config/chezmoi/chezmoistate.boltdb" ]; then
        e2e_step_end fail "empty diff, but ~/.config/chezmoi/chezmoistate.boltdb exists"
    else
        e2e_step_end pass "empty diff; $count managed file(s), all regular"
    fi
}

# e2e_step_native_fixtures: tests/chezmoi.sh from the login environment, with
# the provisioned chezmoi required: ~/.local/bin/chezmoi (S4-chezmoi, or the
# by-hand line of the other flow), else the chezmoi on PATH. The native
# suite owns separate temporary source/destination/config/cache/state paths
# and never touches this home.
e2e_step_native_fixtures() {
    local binary='' rc=0
    e2e_step_begin native-fixtures check:native-fixtures
    if [ -x "$HOME/.local/bin/chezmoi" ]; then
        binary=$HOME/.local/bin/chezmoi
    else
        binary=$(command -v chezmoi 2>/dev/null) || binary=''
    fi
    if [ -z "$binary" ]; then
        E2E_BROKEN=native-fixtures
        e2e_step_end fail 'no provisioned chezmoi (~/.local/bin/chezmoi or PATH)'
        return 0
    fi
    if [ ! -f "$E2E_CLONE/tests/test_chezmoi_takeover_recovery.py" ]; then
        E2E_BROKEN=native-fixtures
        e2e_step_end fail 'native takeover/recovery fixture is missing from this checkout'
        return 0
    fi
    # The prepared login environment supplies Python 3.11+ on HPC hosts;
    # the base image's PATH may have an older Python or none at all.
    e2e_login_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" \
        "cd $(e2e_quote "$E2E_CLONE") && env DOTFILES_TEST_CHEZMOI=$(e2e_quote "$binary") DOTFILES_TEST_REQUIRE_CHEZMOI=1 bash tests/chezmoi.sh" \
        "$E2E_TIMEOUT_APPLY" || rc=$?
    if [ "$rc" != 0 ]; then
        E2E_BROKEN=native-fixtures
        e2e_step_end fail "isolated native suite exit $rc: $(e2e_last_line "$E2E_STEP_ERR")"
    else
        e2e_step_end pass 'isolated native source/config/takeover/recovery fixtures passed'
    fi
}

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

# e2e_negative_common_only: after the common-only handover, ./doctor.sh with
# no arguments exits 0 and warns about the common-only role; ./setup-host.sh
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
        e2e_step_end fail "./setup-host.sh --check exited 2 without naming the common-only role: $(e2e_last_line "$E2E_STEP_ERR")"
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
# no link under HOME leads into the clone; (4) no stow is on the login PATH
# but one the machine had before the flow; (5) the AI-sync runtime never
# appeared in the clone; (6) the login shell is unchanged; (7) the rc files
# changed only in human phases. Stow is no longer wrapped: nothing the
# native flow runs installs it, and (3) and (4) catch a stray one.
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

    e2e_step_begin audit-clone-links check:audit-clone-links
    if bad=$(e2e_audit_clone_links); then
        e2e_step_end pass 'no link under HOME leads into the clone'
    else
        e2e_step_end fail "links under HOME that lead into the clone: $(e2e_one_line "$bad" 400)"
    fi

    e2e_step_begin audit-no-stow check:audit-no-stow
    rc=0
    bad=$(e2e_audit_login_stow "$E2E_STEP_OUT" "$E2E_STEP_ERR") || rc=$?
    case $rc in
        0)
            if [ -n "$E2E_STOW_START" ]; then
                e2e_step_end pass "no stow on the login PATH but what the machine had before the run: $(e2e_one_line "$E2E_STOW_START" 200)"
            else
                e2e_step_end pass 'no stow on the login PATH'
            fi
            ;;
        2)
            if [ -n "$E2E_BROKEN" ]; then
                e2e_step_end skip "after $E2E_BROKEN failed: $(e2e_one_line "$bad" 200)"
            else
                e2e_step_end fail "$(e2e_one_line "$bad" 400)"
            fi
            ;;
        *) e2e_step_end fail "stow on the login PATH that the run put there: $(e2e_one_line "$bad" 400)" ;;
    esac

    e2e_step_begin audit-sync-venv check:audit-sync-venv
    if [ -n "$E2E_VENV_VIOLATIONS" ]; then
        e2e_step_end fail "the clone held $E2E_SYNC_VENV after $E2E_VENV_VIOLATIONS"
    else
        e2e_step_end pass "$E2E_SYNC_VENV never appeared in the clone"
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
