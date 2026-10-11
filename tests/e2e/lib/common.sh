# shellcheck shell=bash
# shellcheck disable=SC2034 # the run state (E2E_STEP_*, E2E_TIMEOUT_*) is shared with the other lib files
# Shared helpers of tests/e2e/inside.sh: the console log, summary.tsv and the
# per-step logs, the E2E_PHASE timeline, command runs under a timeout, the
# env-file expansions and env.txt. Sourced first; defines functions and the
# run state and changes no shell options. Bash 3.2 and BSD userland (the
# macOS runner runs this natively): no associative arrays, mapfile,
# here-documents or process substitution; no find -printf, stat -c, date -d
# or readlink -f. SIGPIPE may be ignored (GitHub runners), so no pipe here
# ends in a reader that stops before its writer does.

E2E_NL='
'
E2E_TAB=$(printf '\t')

# Run state. inside.sh sets E2E_OUT, E2E_CLONE, E2E_RUN_USER and the host
# env before the first step; the counters feed the last line and the exit
# code. E2E_BROKEN names the step after which the main flow cannot go on.
E2E_STEP_N=0 E2E_STEP_NAME='' E2E_STEP_PHASE='' E2E_STEP_START=0
E2E_STEP_LOG='' E2E_STEP_OUT='' E2E_STEP_ERR=''
E2E_PASSES=0 E2E_FAILS=0 E2E_SKIPS=0
E2E_BROKEN=''
E2E_PHASE=''
# Seconds allowed to one HUMAN block line (the contract's 45 minutes), one
# setup-host apply run and one read-only run (doctor, --check, a login
# shell), under timeout or gtimeout when one exists.
E2E_TIMEOUT_BIN=''
E2E_TIMEOUT_BLOCK=2700 E2E_TIMEOUT_APPLY=3600 E2E_TIMEOUT_CHECK=900

e2e_log() { printf '[e2e] %s\n' "$*" >&2; }

# e2e_die MESSAGE: a usage error or refusal, exit 2.
e2e_die() {
    e2e_log "$*"
    exit 2
}

e2e_now() { date +%s; }
e2e_quote() { printf '%q' "$1"; }

# e2e_has REGEX TEXT: 0 when a line of TEXT matches the extended REGEX.
e2e_has() { printf '%s\n' "$2" | grep -E -- "$1" >/dev/null 2>&1; }

# e2e_last_line FILE: FILE's last line, or nothing.
e2e_last_line() { sed -n '$p' "$1" 2>/dev/null; }

# e2e_one_line TEXT [MAX]: TEXT as one line for a summary.tsv detail: tabs
# become spaces, line breaks " | ", and more than MAX (600) characters end
# in "...".
e2e_one_line() {
    local text max=${2:-600}
    text=$(printf '%s' "$1" | tr '\t' ' ' | awk 'NR > 1 { printf " | " } { printf "%s", $0 }')
    if [ "${#text}" -gt "$max" ]; then
        text="${text:0:$max}..."
    fi
    printf '%s' "$text"
}

# e2e_find_timeout: timeout (coreutils) or gtimeout (Homebrew coreutils on
# macOS), else none: the runs then have no limit.
e2e_find_timeout() {
    local name
    E2E_TIMEOUT_BIN=''
    for name in timeout gtimeout; do
        if command -v "$name" >/dev/null 2>&1; then
            E2E_TIMEOUT_BIN=$name
            return 0
        fi
    done
}

# e2e_sha256 FILE: the file's sha256 (sha256sum, or shasum on macOS).
e2e_sha256() {
    local sum
    if command -v sha256sum >/dev/null 2>&1; then
        sum=$(sha256sum <"$1" 2>/dev/null) || return 1
    else
        sum=$(shasum -a 256 <"$1" 2>/dev/null) || return 1
    fi
    printf '%s\n' "${sum%% *}"
}

# e2e_expand TEXT: TEXT with every $SCRATCH, $USER and $HOME replaced (the
# host env files spell those in single quotes, so they reach inside.sh
# unexpanded). An unset SCRATCH is left in place for the caller to see;
# $USER is the running user by id, since a container may not export USER.
e2e_expand() {
    local text=$1
    [ -z "${SCRATCH+set}" ] || text=${text//\$SCRATCH/$SCRATCH}
    text=${text//\$USER/$E2E_RUN_USER}
    text=${text//\$HOME/$HOME}
    printf '%s\n' "$text"
}

# --- timeline ----------------------------------------------------------------

# e2e_phase_begin PHASE / e2e_phase_end: export E2E_PHASE for the wrappers
# and append "<epoch>\t<begin|end>\t<phase>" to log/timeline. sudo stamps its
# own log with seconds, so a human:* or negative:* window gets a one-second
# gap on each side: a sudo of the neighbouring phase can never share its
# boundary second. The other phases need no gap; the wrappers.log audit
# goes by phase name, not by time.
e2e_phase_begin() {
    case $1 in
        human:* | negative:*) sleep 1 ;;
    esac
    E2E_PHASE=$1
    export E2E_PHASE
    printf '%s\t%s\t%s\n' "$(e2e_now)" begin "$1" >>"$E2E_OUT/log/timeline"
}

e2e_phase_end() {
    printf '%s\t%s\t%s\n' "$(e2e_now)" end "$E2E_PHASE" >>"$E2E_OUT/log/timeline"
    case $E2E_PHASE in
        human:* | negative:*) sleep 1 ;;
    esac
    E2E_PHASE=''
    export E2E_PHASE
}

# --- steps and the summary ---------------------------------------------------

# e2e_record STEP STATUS SECONDS DETAIL: one summary.tsv row
# ("<n>\t<step>\t<pass|fail|skip|note>\t<seconds>\t<detail>") and its console
# line; the counters feed the exit code.
e2e_record() {
    local detail
    detail=$(e2e_one_line "$4")
    printf '%s\t%s\t%s\t%s\t%s\n' "$E2E_STEP_N" "$1" "$2" "$3" "$detail" >>"$E2E_OUT/summary.tsv"
    case $2 in
        pass) E2E_PASSES=$((E2E_PASSES + 1)) ;;
        fail) E2E_FAILS=$((E2E_FAILS + 1)) ;;
        skip) E2E_SKIPS=$((E2E_SKIPS + 1)) ;;
    esac
    printf '[e2e] %02d %-20s %-4s %5ss  %s\n' "$E2E_STEP_N" "$1" "$2" "$3" "$detail" >&2
}

# e2e_step_begin NAME PHASE: open step NAME: its files steps/NN-NAME.{log,
# out,err}, the guards' before-images (assert.sh) and the phase the wrappers
# see while it runs.
e2e_step_begin() {
    local prefix
    E2E_STEP_N=$((E2E_STEP_N + 1))
    E2E_STEP_NAME=$1
    E2E_STEP_PHASE=$2
    E2E_STEP_START=$(e2e_now)
    prefix=$(printf '%s/steps/%02d-%s' "$E2E_OUT" "$E2E_STEP_N" "$1")
    E2E_STEP_LOG=$prefix.log E2E_STEP_OUT=$prefix.out E2E_STEP_ERR=$prefix.err
    : >"$E2E_STEP_LOG"
    e2e_guard_before
    e2e_phase_begin "$2"
}

# e2e_step_end STATUS DETAIL: close the phase, require a clean clone of a
# passing step, run the after-step guards (assert.sh), then record the row
# and any notes the guards left.
e2e_step_end() {
    local status=$1 detail=$2 dirty secs line
    e2e_phase_end
    if [ "$status" = pass ] && dirty=$(e2e_clone_dirty) && [ -n "$dirty" ]; then
        status=fail
        detail="$detail; clone not clean: $(e2e_one_line "$dirty" 200)"
    fi
    e2e_guard_after "$E2E_STEP_NAME" "$E2E_STEP_PHASE"
    secs=$(($(e2e_now) - E2E_STEP_START))
    e2e_record "$E2E_STEP_NAME" "$status" "$secs" "$detail"
    # Each note is "<name>\t<detail>\n", so the rest is empty after the last.
    while [ -n "$E2E_PENDING_NOTES" ]; do
        line=${E2E_PENDING_NOTES%%"$E2E_NL"*}
        E2E_PENDING_NOTES=${E2E_PENDING_NOTES#*"$E2E_NL"}
        [ -z "$line" ] || e2e_note "${line%%"$E2E_TAB"*}" "${line#*"$E2E_TAB"}"
    done
    [ "$status" != fail ] || [ "$E2E_STEP_NAME" != "${E2E_BROKEN:-}" ] || e2e_log "the main flow stops after $E2E_STEP_NAME"
}

# e2e_note NAME DETAIL / e2e_skip NAME DETAIL: a row without a step of its
# own: an observation, or a step that did not run.
e2e_note() {
    E2E_STEP_N=$((E2E_STEP_N + 1))
    e2e_record "$1" note 0 "$2"
}

e2e_skip() {
    E2E_STEP_N=$((E2E_STEP_N + 1))
    e2e_record "$1" skip 0 "$2"
}

# e2e_fail_row NAME DETAIL: a failing verdict without a run of its own (a
# block the policy refuses, the apply loop not converging).
e2e_fail_row() {
    E2E_STEP_N=$((E2E_STEP_N + 1))
    e2e_record "$1" fail 0 "$2"
}

# e2e_or_skip NAME FUNCTION: run FUNCTION as step NAME, unless an earlier
# step broke the flow (then record a skip).
e2e_or_skip() {
    if [ -n "$E2E_BROKEN" ]; then
        e2e_skip "$1" "after $E2E_BROKEN failed"
    else
        "$2"
    fi
}

# --- runs --------------------------------------------------------------------

# e2e_run OUT ERR LIMIT DIR COMMAND...: run COMMAND in DIR with stdin from
# /dev/null, stdout to OUT and stderr to ERR, under LIMIT seconds when a
# timeout binary exists, then copy both into the step log. Returns the
# command's exit code (124 after a timeout).
e2e_run() {
    local out=$1 err=$2 limit=$3 dir=$4 rc=0
    shift 4
    if [ -n "$E2E_TIMEOUT_BIN" ]; then
        set -- "$E2E_TIMEOUT_BIN" "$limit" "$@"
    fi
    (cd "$dir" && exec "$@") </dev/null >"$out" 2>"$err" || rc=$?
    {
        printf -- '--- $ %s\n--- cwd %s, phase %s, exit %s\n' "$*" "$dir" "${E2E_PHASE:--}" "$rc"
        cat "$out"
        printf -- '--- stderr\n'
        cat "$err"
        printf -- '--- end\n'
    } >>"$E2E_STEP_LOG"
    return "$rc"
}

# e2e_tsv_counts FILE: "status=count ..." of a doctor --tsv report.
e2e_tsv_counts() {
    awk -F '\t' 'NR > 1 && NF >= 2 { c[$1]++ } END { for (k in c) printf "%s=%d ", k, c[k] }' "$1" 2>/dev/null
}

# e2e_problem_lines FILE: the first five [error] or [warn] lines of a
# doctor or setup-host log, on one line.
e2e_problem_lines() {
    e2e_one_line "$(grep -E '\[(error|warn)\]' "$1" 2>/dev/null | sed -n 1,5p)" 400
}

# --- env.txt -----------------------------------------------------------------

# e2e_write_env MODE: what the run saw, for whoever reads the artifact: the
# machine, the tools, the timeout binary (none on the mac runner) and the
# paths the HOME snapshots left out.
e2e_write_env() {
    local file=$E2E_OUT/env.txt tool
    {
        printf 'host=%s flow=%s profile=%s mode=%s\n' "$E2E_HOST" "${E2E_FLOW:-}" "${E2E_PROFILE:-}" "$1"
        printf 'E2E_SRC=%s\nE2E_REV=%s\nE2E_OUT=%s\nHOME=%s\n' "$E2E_SRC" "$E2E_REV" "$E2E_OUT" "$HOME"
        printf 'uname: %s\n' "$(uname -a)"
        if [ -r /etc/os-release ]; then
            printf -- '--- /etc/os-release\n'
            cat /etc/os-release
            printf -- '---\n'
        fi
        printf 'ldd: %s\n' "$(ldd --version 2>/dev/null | sed -n 1p)"
        [ ! -r /proc/version ] || printf 'proc/version: %s\n' "$(cat /proc/version)"
        printf 'id: %s\n' "$(id)"
        printf 'PATH=%s\n' "$PATH"
        for tool in git curl bash zsh; do
            if command -v "$tool" >/dev/null 2>&1; then
                printf '%s: %s\n' "$tool" "$("$tool" --version 2>/dev/null | sed -n 1p)"
            else
                printf '%s: not found\n' "$tool"
            fi
        done
        printf 'LMOD_DIR=%s\nSCRATCH=%s\n' "${LMOD_DIR-}" "${SCRATCH-}"
        printf 'timeout=%s\n' "${E2E_TIMEOUT_BIN:-none}"
        printf 'E2E_SNAPSHOT_PRUNE=%s\n' "$(e2e_expand "${E2E_SNAPSHOT_PRUNE:-}")"
    } >"$file"
}
