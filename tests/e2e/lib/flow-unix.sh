# shellcheck shell=bash
# shellcheck disable=SC2034 # E2E_APPLY1_OUT and E2E_APPLY1_RC are read by steps.sh (alloc-first)
# The unix flow of tests/e2e/inside.sh: clone, doctor-initial, the no-write
# --check, the setup-host apply loop with its HUMAN blocks, the second apply,
# the login shell, the final doctor runs, the negatives and the audits: the
# docs/bootstrap.md quick start, driven the way "Running it with an agent"
# says an agent drives it. Sourced after steps.sh; same portability rules.

E2E_SKIPPED_BLOCKS=' ' # block ids already recorded as skip
E2E_ALLOC_DONE=0

# e2e_step_check_nowrite: ./setup-host.sh --host H --check plans (exit 3
# while work remains, 0 when nothing is left) and writes nothing.
e2e_step_check_nowrite() {
    local rc=0 problems
    e2e_step_begin check-nowrite check:check-nowrite
    e2e_nowrite_begin check-nowrite
    e2e_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "$E2E_TIMEOUT_CHECK" "$E2E_CLONE" \
        env TMPDIR="$E2E_NW_TMP" ./setup-host.sh --host "$E2E_SETUP_HOST" --check || rc=$?
    problems=$(e2e_nowrite_end check-nowrite)
    case $rc in
        0 | 3)
            if [ -n "$problems" ]; then
                e2e_step_end fail "exit $rc; $problems"
            else
                e2e_step_end pass "exit $rc; $(grep -c ' todo ' "$E2E_STEP_OUT") todo, $(grep -c ' human ' "$E2E_STEP_OUT") human; no writes"
            fi
            ;;
        *) e2e_step_end fail "exit $rc: $(e2e_failure_detail "$E2E_STEP_OUT" "$E2E_STEP_ERR")${problems:+; $problems}" ;;
    esac
}

# e2e_block_text FILE: a block's lines for a detail.
e2e_block_text() {
    e2e_one_line "$(cat "$1")" 400
}

# e2e_blocks_actionable DIR: 0 when a block of DIR gives e2e_handle_blocks
# something to do: a runnable block, the alloc block before E2E_ALLOC_ENV
# was exported, or a block the policy refuses (reported there with its
# text). Only skips, or an alloc block seen before, mean no progress.
# Prints "<id> <kind> <action>" per block.
e2e_blocks_actionable() {
    local count n row id kind action progress=1
    count=$(e2e_blocks_count "$1")
    n=0
    while [ "$n" -lt "$count" ]; do
        n=$((n + 1))
        row=$(e2e_block_row "$1" "$n")
        id=${row%% *} kind=${row#* }
        action=$(e2e_block_policy "$id" "$kind")
        printf '%s %s %s\n' "$id" "$kind" "$action"
        case $action in
            run-* | fail) progress=0 ;;
            alloc) [ "$E2E_ALLOC_DONE" = 1 ] || progress=0 ;;
        esac
    done
    return "$progress"
}

# e2e_handle_alloc ID FILE: the H2-alloc block is never run; the expanded
# E2E_ALLOC_ENV is exported once for the rest of the run, as the person
# inside an allocation would have it. A second H2-alloc block means the
# stand-in did not satisfy the step.
e2e_handle_alloc() {
    local exports word
    if [ "$E2E_ALLOC_DONE" = 1 ]; then
        E2E_BROKEN=$1
        e2e_fail_row "$1" "the alloc block came back after E2E_ALLOC_ENV was exported: $(e2e_block_text "$2")"
        return 1
    fi
    if ! exports=$(e2e_alloc_exports "${E2E_ALLOC_ENV:-}"); then
        E2E_BROKEN=$1
        e2e_fail_row "$1" "$E2E_BLOCK_ERROR"
        return 1
    fi
    for word in $exports; do
        export "${word?}"
    done
    E2E_ALLOC_DONE=1
    E2E_STEP_N=$((E2E_STEP_N + 1))
    e2e_record "$1" pass 0 "never run; exported $exports for the rest of the run; block: $(e2e_block_text "$2")"
}

# e2e_run_block ID KIND ACTION FILE: the lines ACTION selects from the block,
# each as its own `bash -c LINE` in HOME with stdin closed, in order, under
# E2E_PHASE=human:ID, as the agent rules run an approved block. The first
# failing line fails the step and stops the flow.
e2e_run_block() {
    local id=$1 kind=$2 action=$3 file=$4 lines rest line count=0 rc
    if ! lines=$(e2e_block_lines "$action" "$E2E_SETUP_HOST" "$file"); then
        E2E_BROKEN=$id
        e2e_fail_row "$id" "$kind block refused: $E2E_BLOCK_ERROR; block: $(e2e_block_text "$file")"
        return 1
    fi
    e2e_step_begin "$id" "human:$id"
    {
        printf -- '--- block\n'
        cat "$file"
    } >>"$E2E_STEP_LOG"
    # $(...) dropped the final newline; each line must end in one to be cut.
    rest=$lines${lines:+$E2E_NL}
    while [ -n "$rest" ]; do
        line=${rest%%"$E2E_NL"*}
        rest=${rest#*"$E2E_NL"}
        [ -n "$line" ] || continue
        count=$((count + 1))
        rc=0
        e2e_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "$E2E_TIMEOUT_BLOCK" "$HOME" bash -c "$line" || rc=$?
        if [ "$rc" != 0 ]; then
            E2E_BROKEN=$id
            e2e_step_end fail "line $count exited $rc: $(e2e_one_line "$line" 200); $(e2e_last_line "$E2E_STEP_ERR")"
            return 1
        fi
    done
    e2e_step_end pass "$count line(s) run as printed ($action)"
}

# e2e_handle_blocks DIR: act on an exit-3 run's blocks in printed order.
# Returns 1 once a block fails or is refused (E2E_BROKEN is set).
e2e_handle_blocks() {
    local count n row id kind action
    count=$(e2e_blocks_count "$1")
    n=0
    while [ "$n" -lt "$count" ]; do
        n=$((n + 1))
        row=$(e2e_block_row "$1" "$n")
        id=${row%% *} kind=${row#* }
        action=$(e2e_block_policy "$id" "$kind")
        case $action in
            skip)
                case $E2E_SKIPPED_BLOCKS in
                    *" $id "*) ;;
                    *)
                        E2E_SKIPPED_BLOCKS="$E2E_SKIPPED_BLOCKS$id "
                        e2e_skip "$id" "$kind block left to the person: $(e2e_block_text "$1/$n.block")"
                        ;;
                esac
                ;;
            alloc) e2e_handle_alloc "$id" "$1/$n.block" || return 1 ;;
            run-*) e2e_run_block "$id" "$kind" "$action" "$1/$n.block" || return 1 ;;
            *)
                E2E_BROKEN=$id
                e2e_fail_row "$id" "$kind block the harness must not run: $(e2e_block_text "$1/$n.block")"
                return 1
                ;;
        esac
    done
}

# e2e_apply_loop: ./setup-host.sh --host H --yes until it exits 0, at most
# eight runs. Exit 3 hands the printed blocks to e2e_handle_blocks; a run
# whose blocks are all skips fails as "no progress" (the "HUMAN steps
# pending:" ids from stderr name what setup-host waits for); exit 1 or 2
# fails naming the step setup-host reported.
e2e_apply_loop() {
    local n=0 rc name dir plan
    while [ "$n" -lt 8 ]; do
        n=$((n + 1))
        name=apply-$n
        rc=0
        e2e_step_begin "$name" "setup:$name"
        e2e_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "$E2E_TIMEOUT_APPLY" "$E2E_CLONE" \
            ./setup-host.sh --host "$E2E_SETUP_HOST" --yes || rc=$?
        if [ "$n" = 1 ]; then
            E2E_APPLY1_OUT=$E2E_STEP_OUT E2E_APPLY1_RC=$rc
        fi
        case $rc in
            0)
                e2e_step_end pass "exit 0 after $n run(s); $(grep -c ' done ' "$E2E_STEP_OUT") done, $(grep -c ' skip ' "$E2E_STEP_OUT") skip"
                return 0
                ;;
            3)
                dir=${E2E_STEP_LOG%.log}.blocks
                e2e_blocks_parse "$E2E_STEP_OUT" "$dir"
                if plan=$(e2e_blocks_actionable "$dir"); then
                    e2e_step_end pass "exit 3; blocks: $(e2e_blocks_summary "$dir"); pending: $(e2e_pending_ids "$E2E_STEP_ERR")"
                    e2e_handle_blocks "$dir" || return 1
                else
                    E2E_BROKEN=$name
                    e2e_step_end fail "no progress: exit 3 with no block the harness may run (pending: $(e2e_pending_ids "$E2E_STEP_ERR"); blocks: $(e2e_one_line "$plan" 300))"
                    return 1
                fi
                ;;
            1 | 2)
                E2E_BROKEN=$name
                e2e_step_end fail "exit $rc: $(e2e_failure_detail "$E2E_STEP_OUT" "$E2E_STEP_ERR")"
                return 1
                ;;
            *)
                E2E_BROKEN=$name
                e2e_step_end fail "exit $rc (124 is the ${E2E_TIMEOUT_APPLY}s timeout): $(e2e_last_line "$E2E_STEP_ERR")"
                return 1
                ;;
        esac
    done
    E2E_BROKEN=apply-loop
    e2e_fail_row apply-loop 'eight apply runs without an exit 0'
    return 1
}

# e2e_step_second_apply: one more ./setup-host.sh --host H --yes exits 0,
# applies nothing ("<id> done applied: ..." would be a step that redid its
# work) and writes nothing in HOME.
e2e_step_second_apply() {
    local rc=0 applied problems
    e2e_step_begin second-apply setup:second-apply
    e2e_nowrite_begin second-apply
    e2e_run "$E2E_STEP_OUT" "$E2E_STEP_ERR" "$E2E_TIMEOUT_APPLY" "$E2E_CLONE" \
        ./setup-host.sh --host "$E2E_SETUP_HOST" --yes || rc=$?
    applied=$(grep -E '^[A-Za-z0-9-]+ done applied: ' "$E2E_STEP_OUT" 2>/dev/null) || true
    problems=$(e2e_nowrite_end second-apply)
    if [ "$rc" != 0 ]; then
        e2e_step_end fail "exit $rc, expected 0: $(e2e_failure_detail "$E2E_STEP_OUT" "$E2E_STEP_ERR")"
    elif [ -n "$applied" ]; then
        e2e_step_end fail "a second apply redid work: $(e2e_one_line "$applied" 300)"
    elif [ -n "$problems" ]; then
        e2e_step_end fail "$problems"
    else
        e2e_step_end pass 'exit 0, nothing applied, HOME untouched'
    fi
}

# e2e_flow_unix: the whole sequence for a host with an overlay.
e2e_flow_unix() {
    e2e_step_clone || true
    e2e_or_skip doctor-initial e2e_step_doctor_initial
    e2e_or_skip check-nowrite e2e_step_check_nowrite
    if [ -z "$E2E_BROKEN" ]; then
        e2e_apply_loop || true
    else
        e2e_skip apply-1 "after $E2E_BROKEN failed"
    fi
    e2e_or_skip second-apply e2e_step_second_apply
    e2e_or_skip login-shell e2e_step_login_shell
    e2e_or_skip doctor-final e2e_step_doctor_final
    e2e_or_skip doctor-smoke e2e_step_doctor_smoke
    e2e_negatives
    e2e_audits
}
