# shellcheck shell=bash
# shellcheck disable=SC2034 # E2E_BLOCK_ERROR is read by tests/e2e-harness.sh
# HUMAN block handling of tests/e2e/inside.sh: the parser that splits an
# apply run's stdout into blocks, the "HUMAN steps pending:" reader, the
# policy that says which block lines the harness may run, keyed on (step
# id, kind) and failing closed, and the apply loop's verdict on one run.
# Sourced after common.sh; same portability rules. The policy follows
# docs/bootstrap.md "HUMAN blocks" and "Running it with an agent": the
# harness stands in for the person who approves the sudo and inspect blocks
# and who does the H7-deploy step with the agent, and it can neither
# sign in, answer a dialog, change a login shell nor take a Slurm
# allocation.

# The one line kind the harness runs as printed beyond a sudo block is
# matched by its whole shape, since it becomes a `bash -c LINE`: the
# digest-gated run line of an inspect block (steps_digest_gate in
# lib/bootstrap/steps-common.sh: the sha256 and the %q path into sha256sum
# on Linux or shasum on macOS, then `bash` of that same path and nothing
# after it; E2E_GATE_RE is its head, e2e_gate_line the whole). A path is one
# printf %q word (steps_quote): the characters %q leaves alone, and a
# backslash before any other printable one or a space; the $'...' form %q
# uses for control characters, and anything unescaped that the shell would
# act on, is refused. The H7-deploy block holds notes only: the deploy step runs
# the documented procedure (steps.sh e2e_step_home_deploy), never a
# block line.
E2E_GATE_RE='^printf '\''%s  %s\\n'\'' [0-9a-f]{64} .+ \| (sha256sum|shasum -a 256) -c --status - && bash '
E2E_QWORD_RE='([A-Za-z0-9_./+=:@%,-]|\\[^A-Za-z0-9_/[:space:]]|\\ )+'
E2E_BLOCK_ERROR=''

# e2e_qword WORD: 0 when WORD is one %q-quoted absolute path.
e2e_qword() {
    case $1 in
        /*) e2e_has "^$E2E_QWORD_RE\$" "$1" ;;
        *) return 1 ;;
    esac
}

# e2e_gate_line LINE: 0 when LINE is exactly the gate steps_digest_gate
# prints for one file: "<sha256>  <path>" into one verifier, then `bash
# <path>` with that same %q path and nothing after it. The regex alone ends
# at "bash " and does not bind the path, so it would take `&& bash <other>`,
# a `; ...` tail or an extra pipe stage as the gated line.
e2e_gate_line() {
    local head="printf '%s  %s\\n' " rest sha path verify
    e2e_has "$E2E_GATE_RE" "$1" || return 1
    rest=${1#"$head"}
    [ "$rest" != "$1" ] || return 1
    sha=${rest%% *}
    rest=${rest#"$sha "}
    path=${rest%% | *}
    e2e_qword "$path" || return 1
    for verify in 'sha256sum -c --status -' 'shasum -a 256 -c --status -'; do
        [ "$1" != "$head$sha $path | $verify && bash $path" ] || return 0
    done
    return 1
}

# e2e_blocks_parse STDOUT DIR: write every HUMAN block of STDOUT to
# DIR/<n>.block (its lines between HUMAN-BEGIN and HUMAN-END) and DIR/index
# ("<n>\t<id>\t<kind>" per block, in order). awk copies the lines byte for
# byte, so a %q-quoted path with spaces reaches bash -c as printed.
e2e_blocks_parse() {
    mkdir -p "$2" || return 1
    : >"$2/index"
    awk -v dir="$2" '
        /^HUMAN-BEGIN / {
            n++
            file = dir "/" n ".block"
            printf "" > file
            printf "%d\t%s\t%s\n", n, $2, $3 > (dir "/index")
            inside = 1
            next
        }
        /^HUMAN-END$/ { inside = 0; close(file); next }
        inside { print > file }
    ' "$1"
}

# e2e_blocks_count DIR: how many blocks the index holds.
e2e_blocks_count() {
    grep -c . "$1/index" 2>/dev/null || true
}

# e2e_block_row DIR N: "<id> <kind>" of block N.
e2e_block_row() {
    sed -n "${2}p" "$1/index" | cut -f 2,3 | tr '\t' ' '
}

# e2e_blocks_summary DIR: "id(kind) ..." for a detail line.
e2e_blocks_summary() {
    awk -F '\t' '{ printf "%s%s(%s)", sep, $2, $3; sep = " " }' "$1/index"
}

# e2e_blocks_find DIR ID: the number n of the first block of DIR with step
# id ID (its lines are DIR/n.block); returns 1 when none was printed.
e2e_blocks_find() {
    awk -F '\t' -v id="$2" '$2 == id { print $1; found = 1; exit } END { exit !found }' "$1/index" 2>/dev/null
}

# e2e_pending_ids STDERR: the ids of the "HUMAN steps pending: <ids>;" line
# that steps_run (lib/bootstrap/steps.sh) prints once per run, or nothing.
e2e_pending_ids() {
    sed -n 's/.*HUMAN steps pending: \([^;]*\);.*/\1/p' "$1" | sed -n 1p
}

# e2e_failure_detail STDOUT STDERR: what an exit 1 or 2 run said: the
# "<id> failed <detail>" plan lines and the "failed steps:" line, else the
# last stderr line.
e2e_failure_detail() {
    local text
    text=$(
        grep -E '^[A-Za-z0-9-]+ failed ' "$1" 2>/dev/null
        grep -F 'failed steps:' "$2" 2>/dev/null
    )
    [ -n "$text" ] || text=$(e2e_last_line "$2")
    printf '%s\n' "$text"
}

# e2e_block_policy ID KIND: the harness action for a block. run-all: every
# command line, in order (the sudo blocks a person approves as a whole).
# run-gate: only the digest-gated line (the person read the script; the
# harness runs it as printed). deploy: the H7-deploy block, whose lines
# are notes and are never run line by line; once it alone is pending and a
# run applied nothing, the loop ends and the home-deploy step runs the
# documented Fresh home by hand procedure. alloc: never run; E2E_ALLOC_ENV
# stands in for the allocation. skip: a reminder for the person (sign-in,
# chsh, a dialog, a choice the harness must not make). fail: a block the
# harness must not act on (a GUI installer, a Homebrew conflict or shared
# prefix, a foreign nvm, the oh-my-zsh recovery) and every (id, kind) it does
# not know.
e2e_block_policy() {
    case $1:$2 in
        H1-apt-core:sudo | H1-locale:sudo | H1-linuxbrew:sudo | H1-homebrew:sudo) printf 'run-all\n' ;;
        S5-claude:inspect) printf 'run-gate\n' ;;
        H7-deploy:judgment) printf 'deploy\n' ;;
        H2-alloc:alloc) printf 'alloc\n' ;;
        S2-modules:judgment | H7-payloads:judgment | H7-doctor:judgment | H7-auth:auth | \
            H1-fcitx5:gui | H7-chsh:chsh) printf 'skip\n' ;;
        H1-xcode-clt:* | S2-brew-bundle:* | S4-nvm:* | X-recovery:* | *) printf 'fail\n' ;;
    esac
}

# e2e_block_lines ACTION HOST FILE: the command lines of block FILE that
# ACTION lets the harness run, one per line, in order. A "# " line is a note
# and never counts. run-gate wants exactly one gated line (e2e_gate_line)
# and nothing but notes besides it; every other action (a deploy, a
# skip) selects no line, even from a block of notes only. HOST names the
# host the block was printed for. Returns 1 with the reason in
# E2E_BLOCK_ERROR and printed, since the caller captures the output with
# $(...) and would not see the variable.
e2e_block_lines() {
    local action=$1 file=$3 line selected='' gates=0
    E2E_BLOCK_ERROR=''
    case $action in
        run-all | run-gate) ;;
        *)
            E2E_BLOCK_ERROR="no lines run for action $action"
            printf '%s\n' "$E2E_BLOCK_ERROR"
            return 1
            ;;
    esac
    while IFS= read -r line || [ -n "$line" ]; do
        case $line in
            '# '* | '') continue ;;
        esac
        case $action in
            run-all) selected="$selected$line$E2E_NL" ;;
            run-gate)
                if e2e_gate_line "$line"; then
                    selected="$selected$line$E2E_NL"
                    gates=$((gates + 1))
                else
                    E2E_BLOCK_ERROR="an inspect line the harness may not run: $line"
                fi
                ;;
        esac
        [ -z "$E2E_BLOCK_ERROR" ] || break
    done <"$file"
    if [ -z "$E2E_BLOCK_ERROR" ]; then
        case $action in
            run-gate) [ "$gates" = 1 ] || E2E_BLOCK_ERROR="the inspect block has $gates digest-gated run lines, not 1" ;;
        esac
    fi
    if [ -n "$E2E_BLOCK_ERROR" ]; then
        printf '%s\n' "$E2E_BLOCK_ERROR"
        return 1
    fi
    printf '%s' "$selected"
}

# e2e_loop_next RC PENDING ACTIONABLE APPLIED: the apply loop's verdict on
# one ./setup-host.sh --yes run, as one word, from its exit code RC, the ids
# of its "HUMAN steps pending:" line, whether a printed block gives the
# harness something to do (1) and whether a step applied (1). blocks: exit
# 3 with such a block; rerun: exit 3, nothing to do but a step applied;
# done: exit 3, nothing to do, nothing applied and H7-deploy alone pending,
# the deploy step's turn; stuck: any other exit 3; early: exit 0, which a fresh
# home cannot reach before its first apply; error: exit 1 or 2; timeout:
# anything else (124 after the limit).
e2e_loop_next() {
    case $1 in
        3)
            if [ "$3" = 1 ]; then
                printf 'blocks\n'
            elif [ "$4" = 1 ]; then
                printf 'rerun\n'
            elif [ "$2" = H7-deploy ]; then
                printf 'done\n'
            else
                printf 'stuck\n'
            fi
            ;;
        0) printf 'early\n' ;;
        1 | 2) printf 'error\n' ;;
        *) printf 'timeout\n' ;;
    esac
}

# e2e_alloc_exports TEXT: E2E_ALLOC_ENV expanded and checked: "KEY=value"
# words only, nothing left unexpanded. Returns 1 with E2E_BLOCK_ERROR set and
# printed, since a caller that captures the output with $(...) would not see
# the variable.
e2e_alloc_exports() {
    local expanded word
    E2E_BLOCK_ERROR=''
    expanded=$(e2e_expand "$1")
    if [ -z "$expanded" ]; then
        E2E_BLOCK_ERROR='E2E_ALLOC_ENV is empty, so nothing stands in for the allocation'
    else
        case $expanded in
            *'$'*) E2E_BLOCK_ERROR="E2E_ALLOC_ENV still holds an unexpanded name (is SCRATCH set?): $expanded" ;;
        esac
    fi
    if [ -z "$E2E_BLOCK_ERROR" ]; then
        for word in $expanded; do
            case $word in
                [A-Za-z_]*=*) ;;
                *) E2E_BLOCK_ERROR="E2E_ALLOC_ENV word is not KEY=value: $word" ;;
            esac
            case ${word%%=*} in
                *[!A-Za-z0-9_]*) E2E_BLOCK_ERROR="E2E_ALLOC_ENV word is not KEY=value: $word" ;;
            esac
            [ -z "$E2E_BLOCK_ERROR" ] || break
        done
    fi
    if [ -n "$E2E_BLOCK_ERROR" ]; then
        printf '%s\n' "$E2E_BLOCK_ERROR"
        return 1
    fi
    printf '%s\n' "$expanded"
}
