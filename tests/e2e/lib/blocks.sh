# shellcheck shell=bash
# shellcheck disable=SC2034 # E2E_BLOCK_ERROR is read by flow-unix.sh
# HUMAN block handling of tests/e2e/inside.sh: the parser that splits an
# apply run's stdout into blocks, the "HUMAN steps pending:" reader, and the
# policy that says which block lines the harness may run, keyed on (step
# id, kind) and failing closed. Sourced after common.sh; same portability
# rules. The policy follows docs/bootstrap.md "HUMAN blocks" and "Running it
# with an agent": the harness stands in for the person who approves the
# sudo, inspect and stow blocks, and it can neither sign in, answer a
# dialog, change a login shell nor take a Slurm allocation.

# The digest-gated run line of an inspect block (steps_digest_gate in
# lib/bootstrap/steps-common.sh, sha256sum on Linux, shasum on macOS), and
# the two line shapes an H7-stow block may hold: the mv -n lines that move
# /etc/skel files aside and the one-shot PATH prefix plus stow-all.sh HOST.
E2E_GATE_RE='^printf '\''%s  %s\\n'\'' [0-9a-f]{64} .+ \| (sha256sum|shasum -a 256) -c --status - && bash '
E2E_MV_RE='^mv -n '
E2E_STOW_RE='^PATH=.*\$PATH"? .+/stow-all\.sh '
E2E_BLOCK_ERROR=''

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
# harness runs it as printed). run-stow: the mv -n lines and the one
# stow-all.sh line. alloc: never run; E2E_ALLOC_ENV stands in for the
# allocation. skip: a reminder for the person (sign-in, chsh, a dialog, a
# choice the harness must not make). fail: a block the harness must not act
# on (a GUI installer, a Homebrew conflict or shared prefix, a foreign nvm,
# the oh-my-zsh recovery) and every (id, kind) it does not know.
e2e_block_policy() {
    case $1:$2 in
        H1-apt-core:sudo | H1-locale:sudo | H1-linuxbrew:sudo | H1-homebrew:sudo) printf 'run-all\n' ;;
        S5-claude:inspect) printf 'run-gate\n' ;;
        H7-stow:judgment) printf 'run-stow\n' ;;
        H2-alloc:alloc) printf 'alloc\n' ;;
        S2-modules:judgment | H7-sync-skills:judgment | H7-doctor:judgment | H7-auth:auth | \
            H1-fcitx5:gui | H7-chsh:chsh) printf 'skip\n' ;;
        H1-xcode-clt:* | S2-brew-bundle:* | S4-nvm:* | X-recovery:* | *) printf 'fail\n' ;;
    esac
}

# e2e_block_lines ACTION HOST FILE: the command lines of block FILE that
# ACTION lets the harness run, one per line, in order. A "# " line is a note
# and never counts. Returns 1 with the reason in E2E_BLOCK_ERROR when the
# block holds a line the action does not allow or lacks the one line it
# needs: run-gate wants exactly one gated line, run-stow exactly one
# stow-all.sh HOST line and nothing but mv -n lines besides it.
e2e_block_lines() {
    local action=$1 host=$2 file=$3 line selected='' gates=0 stows=0
    E2E_BLOCK_ERROR=''
    while IFS= read -r line || [ -n "$line" ]; do
        case $line in
            '# '* | '') continue ;;
        esac
        case $action in
            run-all) selected="$selected$line$E2E_NL" ;;
            run-gate)
                if e2e_has "$E2E_GATE_RE" "$line"; then
                    selected="$selected$line$E2E_NL"
                    gates=$((gates + 1))
                fi
                ;;
            run-stow)
                if e2e_has "$E2E_MV_RE" "$line"; then
                    selected="$selected$line$E2E_NL"
                elif e2e_has "$E2E_STOW_RE$host\$" "$line"; then
                    selected="$selected$line$E2E_NL"
                    stows=$((stows + 1))
                else
                    E2E_BLOCK_ERROR="an H7-stow line the harness may not run: $line"
                    return 1
                fi
                ;;
            *)
                E2E_BLOCK_ERROR="no lines run for action $action"
                return 1
                ;;
        esac
    done <"$file"
    case $action in
        run-gate)
            if [ "$gates" != 1 ]; then
                E2E_BLOCK_ERROR="the inspect block has $gates digest-gated run lines, not 1"
                return 1
            fi
            ;;
        run-stow)
            if [ "$stows" != 1 ]; then
                E2E_BLOCK_ERROR="the H7-stow block has $stows stow-all.sh $host lines, not 1"
                return 1
            fi
            ;;
    esac
    printf '%s' "$selected"
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
