# shellcheck shell=bash
# shellcheck disable=SC2034 # the run state (STEP_*, STEPS_*) is shared with the step files
# Step registry and runner for setup-host.sh. Sourced only; defines functions
# and changes no shell options (the runner restores errexit after each step).
# Helpers live in steps-common.sh, the rc-pollution guard in steps-guard.sh;
# the steps in steps-human.sh, steps-packages.sh, steps-files.sh,
# steps-runtimes.sh and steps-archives.sh.
# Bash 3.2 compatible and `set -u` safe: no associative arrays, no mapfile.
#
# A step id names four functions, its dashes turned into underscores:
#   step_<id>_check   read-only and offline. Sets STEP_DETAIL and returns
#                     0 done, 1 pending, 2 not applicable here, 3 a person
#                     must act first (a judgment block), 4 waiting on a
#                     prerequisite that STEP_DETAIL names.
#   step_<id>_plan    an auto step's one-line action, or a HUMAN step's block.
#   step_<id>_apply   an auto step's install, or the download a HUMAN block
#                     then runs. Optional for HUMAN steps.
#   step_<id>_verify  optional; by default the check must pass after apply.
# apply and verify run in a subshell with errexit; the rc-pollution guard
# (steps_guarded) then requires the checkout to be unchanged, content included.
#
# The caller sets STEPS_ROOT (physical checkout path), STEPS_HOST,
# STEPS_PROFILE, STEPS_ARCH, STEPS_MODE (check, apply or manual), STEPS_TIERS,
# STEPS_ONLY and STEPS_SKIP (",id,id," lists), STEPS_YES and STEPS_KEEP_GOING.

# id kind tier blocking scopes. kind is auto or a HUMAN kind. Tier "-" means
# the step runs whatever --tier selects. blocking "yes" marks a HUMAN step
# whose pending state stops its dependents and makes the run exit 3. scopes
# are profiles or hosts.
STEPS_REGISTRY='P0-preflight auto - - macos,debian,hpc
H1-xcode-clt gui - yes macos
H1-homebrew sudo - yes macos
H1-apt-core sudo - yes debian
H1-locale sudo - no debian
H1-linuxbrew sudo - yes debian
H1-gh-apt-repo sudo cli no lab-ubuntu
H1-fcitx5 gui - no lab-ubuntu
S2-brew-bundle auto - - macos,debian
S2-micromamba auto core - hpc
H2-alloc alloc core yes hpc
S2-login-env auto core - hpc
S2-modules judgment ai no hpc
S3-clones auto core - macos,debian,hpc
S3-bat-theme auto core - macos,debian,hpc
S3-dirs auto core - macos,debian,hpc
S4-nvm auto ai - macos,debian
S4-setup-sync auto core - macos,debian,hpc
S5-claude inspect ai yes debian
S5-codex auto ai - debian
S6-nerd-font auto desktop - lab-ubuntu
S6-kitty auto desktop - lab-ubuntu
H7-stow judgment - yes macos,debian,hpc
H7-chsh chsh - no macos,debian
H7-auth auth - no macos,debian,hpc
H7-sync-skills judgment - no macos,debian,hpc
H7-doctor judgment - no macos,debian,hpc'

# Run state shared by the step files; steps_run resets the lists.
STEP_DETAIL=''
STEP_KIND='' STEP_TIER='' STEP_BLOCKING=''
STEPS_KIND='' STEPS_URL='' STEPS_SHA='' STEPS_DEST='' STEPS_HUMAN='' STEPS_ARCHIVE=''
STEPS_PROBE_FOUND='' STEPS_OMZ_RECOVERY='' STEPS_RC=0 STEPS_ERROR='' STEPS_EXIT=0
STEPS_FAILED='' STEPS_PENDING='' STEPS_HELD='' STEPS_TODO='' STEPS_STOPPED=''

# steps_rows: "id kind tier blocking" for every registry step of STEPS_HOST.
steps_rows() {
    local id kind tier blocking scopes
    while IFS=' ' read -r id kind tier blocking scopes; do
        [ -n "$id" ] || continue
        case ",$scopes," in
            *",$STEPS_PROFILE,"* | *",$STEPS_HOST,"*) ;;
            *) continue ;;
        esac
        printf '%s %s %s %s\n' "$id" "$kind" "$tier" "$blocking"
    done <<EOF
$STEPS_REGISTRY
EOF
}

# steps_ids: the step ids of STEPS_HOST, space-separated, in phase order.
steps_ids() {
    local id rest ids=''
    while IFS=' ' read -r id rest; do
        if [ -n "$id" ]; then
            ids="$ids${ids:+ }$id"
        fi
    done <<EOF
$(steps_rows)
EOF
    printf '%s\n' "$ids"
}

# steps_has ID: 0 when ID is a step of STEPS_HOST.
steps_has() {
    case " $(steps_ids) " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

# steps_meta ID: set STEP_KIND, STEP_TIER and STEP_BLOCKING from the registry.
steps_meta() {
    local id kind tier blocking
    while IFS=' ' read -r id kind tier blocking; do
        if [ "$id" = "$1" ]; then
            STEP_KIND=$kind
            STEP_TIER=$tier
            STEP_BLOCKING=$blocking
            return 0
        fi
    done <<EOF
$(steps_rows)
EOF
    return 1
}

# steps_set FIELD ID VALUE / steps_get FIELD ID: per-step run state, kept in
# STEPS_<FIELD>_<id> variables because Bash 3.2 has no associative arrays.
steps_set() {
    printf -v "STEPS_${1}_${2//-/_}" '%s' "$3"
}

steps_get() {
    local name="STEPS_${1}_${2//-/_}"
    printf '%s' "${!name-}"
}

# steps_needs ID: the steps that must be done before ID on this profile.
steps_needs() {
    case $STEPS_PROFILE:$1 in
        macos:H1-homebrew | macos:S3-clones | macos:S4-nvm) echo H1-xcode-clt ;;
        macos:S2-brew-bundle) echo H1-homebrew ;;
        macos:S4-setup-sync) echo S2-brew-bundle ;;
        macos:H7-stow | debian:H7-stow) echo S3-clones S2-brew-bundle S4-setup-sync ;;
        debian:S2-brew-bundle) echo H1-linuxbrew ;;
        debian:H7-chsh) echo H1-apt-core ;;
        debian:H1-linuxbrew | debian:S3-clones | debian:S3-bat-theme | debian:S4-* | \
            debian:S5-* | debian:S6-*)
            echo H1-apt-core
            ;;
        hpc:S2-login-env) echo S2-micromamba H2-alloc ;;
        hpc:S4-setup-sync) echo S2-login-env ;;
        hpc:H7-stow) echo S3-clones S2-login-env S4-setup-sync ;;
    esac
}

# steps_blocker ID KIND: print the first prerequisite that stops ID. A failed
# or blocked prerequisite, or a pending blocking HUMAN one, stops every step;
# a HUMAN step also waits for auto prerequisites that are still to do, or
# that --skip or a declined prompt left undone, so the run never hands out
# ./stow-all.sh before its prerequisites ran.
steps_blocker() {
    local IFS=' ' need state
    for need in $(steps_needs "$1"); do
        state=$(steps_get STATE "$need")
        case $state in
            failed | blocked)
                printf '%s\n' "$need"
                return 0
                ;;
            human)
                if [ "$(steps_get BLOCKING "$need")" = yes ]; then
                    printf '%s\n' "$need"
                    return 0
                fi
                ;;
            todo)
                if [ "$2" != auto ]; then
                    printf '%s\n' "$need"
                    return 0
                fi
                ;;
            skipped | declined)
                if [ "$2" != auto ]; then
                    printf '%s (%s)\n' "$need" "$state"
                    return 0
                fi
                ;;
        esac
    done
    return 1
}

# steps_selection ID TIER: 0 when the options select ID, else print why not
# and return 3 for --skip, 1 for --only and --tier.
steps_selection() {
    case $STEPS_SKIP in
        *",$1,"*)
            printf '%s\n' 'skipped by --skip'
            return 3
            ;;
    esac
    [ "$1" != P0-preflight ] || return 0
    if [ -n "$STEPS_ONLY" ]; then
        case $STEPS_ONLY in
            *",$1,"*) return 0 ;;
        esac
        printf '%s\n' 'not selected by --only'
        return 1
    fi
    [ "$2" != - ] || return 0
    bootstrap_tier_selected "$2" "$STEPS_TIERS" && return 0
    printf 'tier %s not selected\n' "$2"
    return 1
}

# steps_verify FN: the step's verify function, else its check must pass.
steps_verify() {
    if declare -F "step_${1}_verify" >/dev/null; then
        "step_${1}_verify"
        return
    fi
    STEP_DETAIL=
    "step_${1}_check" || {
        dotfiles_log error "verify failed: $STEP_DETAIL"
        return 1
    }
}

# steps_plan_text FN: an auto step's one-line plan.
steps_plan_text() {
    local text=$STEP_DETAIL
    if declare -F "step_${1}_plan" >/dev/null; then
        text=$("step_${1}_plan")
    fi
    printf '%s' "$text" | tr '\n\t' '  '
}

# steps_confirm ID PLAN: ask on the terminal; 0 only for yes.
steps_confirm() {
    local reply=''
    printf '%s: %s\nApply %s? [y/N] ' "$1" "$2" "$1" >&2
    IFS= read -r reply || reply=
    case $reply in
        y | Y | yes | Yes | YES) return 0 ;;
    esac
    return 1
}

# steps_finish_step ID STATE DETAIL [KIND [BLOCKING]]: record STATE and print
# the plan line "<id> <done|todo|human|skip|failed> <detail>". blocked shows
# as todo for an auto KIND, else as human; skipped (--skip) and declined (the
# prompt) show as skip. Work left undone is collected in STEPS_TODO (auto
# steps) and STEPS_HELD (blocking HUMAN steps); either makes the run exit 3.
steps_finish_step() {
    local id=$1 state=$2 detail shown
    detail=$(printf '%s' "$3" | tr '\n\t' '  ')
    steps_set STATE "$id" "$state"
    case $state in
        blocked)
            if [ "${4:-auto}" = auto ]; then
                shown=todo
                STEPS_TODO="$STEPS_TODO${STEPS_TODO:+ }$id"
            else
                shown=human
                [ "${5:-yes}" != yes ] || STEPS_HELD="$STEPS_HELD${STEPS_HELD:+ }$id"
            fi
            ;;
        todo | declined)
            if [ "$state" = todo ]; then shown=todo; else shown=skip; fi
            STEPS_TODO="$STEPS_TODO${STEPS_TODO:+ }$id"
            ;;
        skipped) shown=skip ;;
        failed)
            shown=failed
            STEPS_FAILED="$STEPS_FAILED${STEPS_FAILED:+ }$id"
            dotfiles_log error "$id failed: $detail"
            [ "$STEPS_KEEP_GOING" = 1 ] || STEPS_STOPPED=$id
            ;;
        *) shown=$state ;;
    esac
    printf '%s %s %s\n' "$id" "$shown" "$detail"
}

# steps_run_human ID FN BLOCKING PREPARE: a pending HUMAN step. In apply mode
# and with PREPARE yes, its apply function stages what the block runs (a
# verified download). An auto step that needs a person (check 3) passes no.
steps_run_human() {
    if [ "$STEPS_MODE" = apply ] && [ "$4" = yes ] && declare -F "step_${2}_apply" >/dev/null; then
        steps_guarded "step_${2}_apply"
        if [ "$STEPS_RC" != 0 ]; then
            steps_finish_step "$1" failed "${STEPS_ERROR:-could not prepare the HUMAN block}"
            return 0
        fi
    fi
    steps_set BLOCKING "$1" "$3"
    STEPS_PENDING="$STEPS_PENDING${STEPS_PENDING:+ }$1"
    [ "$3" != yes ] || STEPS_HELD="$STEPS_HELD${STEPS_HELD:+ }$1"
    steps_finish_step "$1" human "$STEP_DETAIL"
}

# steps_run_auto ID FN: apply a pending auto step, verify it, guard the
# checkout, and refresh PATH for the steps after it.
steps_run_auto() {
    local id=$1 fn=$2 plan
    plan=$(steps_plan_text "$fn")
    if [ "$STEPS_YES" != 1 ] && ! steps_confirm "$id" "$plan"; then
        steps_finish_step "$id" declined "declined: $plan"
        return 0
    fi
    dotfiles_log step "$id: $plan"
    steps_guarded "step_${fn}_apply"
    if [ "$STEPS_RC" = 0 ]; then
        steps_guarded steps_verify "$fn"
    fi
    if [ "$STEPS_RC" != 0 ]; then
        steps_finish_step "$id" failed "${STEPS_ERROR:-$plan}"
        return 0
    fi
    steps_extend_path
    steps_finish_step "$id" 'done' "applied: $plan"
}

# steps_run_one ID KIND TIER BLOCKING: select, check, then plan or apply.
steps_run_one() {
    local id=$1 kind=$2 tier=$3 blocking=$4 fn reason rc=0 blocker prepare=yes
    fn=${id//-/_}
    STEP_DETAIL=
    reason=$(steps_selection "$id" "$tier") || rc=$?
    case $rc in
        0) ;;
        3)
            steps_finish_step "$id" skipped "$reason"
            return 0
            ;;
        *)
            steps_finish_step "$id" skip "$reason"
            return 0
            ;;
    esac
    "step_${fn}_check" || rc=$?
    case $rc in
        0)
            steps_finish_step "$id" 'done' "$STEP_DETAIL"
            return 0
            ;;
        2)
            steps_finish_step "$id" skip "$STEP_DETAIL"
            return 0
            ;;
        3)
            kind=judgment
            blocking=yes
            prepare=no
            ;;
        4)
            steps_finish_step "$id" blocked "waiting: $STEP_DETAIL" "$kind" "$blocking"
            return 0
            ;;
    esac
    if blocker=$(steps_blocker "$id" "$kind"); then
        steps_finish_step "$id" blocked "blocked by $blocker: $STEP_DETAIL" "$kind" "$blocking"
        return 0
    fi
    if [ "$kind" != auto ]; then
        steps_run_human "$id" "$fn" "$blocking" "$prepare"
    elif [ "$STEPS_MODE" = apply ]; then
        steps_run_auto "$id" "$fn"
    else
        steps_finish_step "$id" todo "$STEP_DETAIL"
    fi
}

# steps_rerun: the command that continues this run.
steps_rerun() {
    printf './setup-host.sh --host %s' "$STEPS_HOST"
    [ "$STEPS_TIERS" = core,cli,ai ] || printf ' --tier %s' "$STEPS_TIERS"
    printf '\n'
}

# steps_run: run every step of the host in phase order, print the pending
# HUMAN blocks, and set STEPS_EXIT: 0 when every selected step is done or not
# applicable, 1 when one failed, 3 when work remains (HUMAN steps pending, or
# auto steps left to apply by --check, a declined prompt or a HUMAN step).
# Call it as a plain command (see steps_guarded).
steps_run() {
    local IFS=' ' id kind tier blocking fn after=''
    STEPS_FAILED='' STEPS_PENDING='' STEPS_HELD='' STEPS_TODO='' STEPS_STOPPED=''
    for id in $(steps_ids); do
        if [ -n "$STEPS_STOPPED" ]; then
            break
        fi
        steps_meta "$id"
        kind=$STEP_KIND tier=$STEP_TIER blocking=$STEP_BLOCKING
        steps_run_one "$id" "$kind" "$tier" "$blocking"
    done
    for id in $STEPS_PENDING; do
        fn=${id//-/_}
        "step_${fn}_plan"
    done
    if [ -n "$STEPS_FAILED" ]; then
        STEPS_EXIT=1
        [ -z "$STEPS_STOPPED" ] || dotfiles_log error "stopped after $STEPS_STOPPED failed; rerun with --keep-going to continue past failures"
        dotfiles_log error "failed steps: $STEPS_FAILED"
        return 0
    fi
    STEPS_EXIT=0
    if [ -n "$STEPS_HELD" ]; then
        STEPS_EXIT=3
        after='after the HUMAN blocks, '
        dotfiles_log warn "HUMAN steps pending: $STEPS_HELD; run the HUMAN blocks above, then rerun $(steps_rerun)"
    fi
    if [ -n "$STEPS_TODO" ]; then
        STEPS_EXIT=3
        if [ "$STEPS_MODE" = check ]; then
            dotfiles_log warn "steps to apply: $STEPS_TODO; ${after}rerun $(steps_rerun) without --check"
        else
            dotfiles_log warn "steps not applied: $STEPS_TODO; ${after}rerun $(steps_rerun)"
        fi
    fi
    [ "$STEPS_EXIT" != 0 ] || dotfiles_log ok "setup-host: nothing blocking remains for $STEPS_HOST"
}

# steps_list: the registry of STEPS_HOST (id, kind, tier, blocking).
steps_list() {
    local id kind tier blocking
    printf 'id\tkind\ttier\tblocking\n'
    while IFS=' ' read -r id kind tier blocking; do
        printf '%s\t%s\t%s\t%s\n' "$id" "$kind" "$tier" "$blocking"
    done <<EOF
$(steps_rows)
EOF
}

# steps_print_manual: every HUMAN block of STEPS_HOST, pending or not. Reads
# manifests only (no probes, downloads or writes).
steps_print_manual() {
    local IFS=' ' id fn
    STEPS_MODE=manual
    for id in $(steps_ids); do
        fn=${id//-/_}
        steps_meta "$id"
        if [ "$STEP_KIND" != auto ]; then
            "step_${fn}_plan"
        elif declare -F "step_${fn}_manual" >/dev/null; then
            "step_${fn}_manual"
        fi
    done
}
