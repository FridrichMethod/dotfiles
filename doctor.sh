#!/bin/bash

set -euo pipefail

# Usage: ./doctor.sh [--host HOST | --platform PLATFORM] [--tier LIST|all]
#                    [--tsv] [--quiet] [--online] [--smoke] [--list]
# Example: ./doctor.sh --host lab-ubuntu
# Reports which day-zero tools from config/bootstrap/tools.tsv this machine
# has, plus structural checks (locale, .venv-sync, submodule, stow links, PATH
# order, rc-file pollution, oh-my-zsh order, Homebrew nvm). Read-only and
# offline: it installs nothing, writes nothing and uses no network unless
# --online (auth status probes) or --smoke (an interactive zsh) asks for it.
# The host defaults to DOTFILES_HOST, then to the host ./stow-all.sh recorded
# for this home; it is never guessed. The win host is checked by doctor.ps1.
# Exit: 0 every required tier ok, 1 a required row missing or outdated or a
# structural error, 2 usage error, invalid manifest, unknown host or win.
# docs/bootstrap.md explains each step id the report cites.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -r "$REPO_ROOT/lib/terminal.sh" ]]; then
    # shellcheck source=lib/terminal.sh
    . "$REPO_ROOT/lib/terminal.sh"
else
    dotfiles_log() {
        case $1 in
            warn | error) printf '[dotfiles] [%s] %s\n' "$1" "$2" >&2 ;;
            *) printf '[dotfiles] [%s] %s\n' "$1" "$2" ;;
        esac
    }
fi

for lib in manifest platform version checks; do
    if [[ ! -r "$REPO_ROOT/lib/bootstrap/$lib.sh" ]]; then
        dotfiles_log error "missing library: $REPO_ROOT/lib/bootstrap/$lib.sh"
        exit 2
    fi
done
# shellcheck source=lib/bootstrap/manifest.sh
. "$REPO_ROOT/lib/bootstrap/manifest.sh"
# shellcheck source=lib/bootstrap/platform.sh
. "$REPO_ROOT/lib/bootstrap/platform.sh"
# shellcheck source=lib/bootstrap/version.sh
. "$REPO_ROOT/lib/bootstrap/version.sh"
# shellcheck source=lib/bootstrap/checks.sh
. "$REPO_ROOT/lib/bootstrap/checks.sh"

# git never refreshes the index or takes other optional locks, in this
# process or in any git a probed tool runs (brew --version runs git describe).
export GIT_OPTIONAL_LOCKS=0

usage() {
    cat <<'EOF'
Usage: ./doctor.sh [--host HOST | --platform PLATFORM] [options]

Read-only, offline check of the day-zero tools in config/bootstrap/tools.tsv
and of the structural setup (locale, venv-sync, submodule, stow-links,
path-order, rc-pollution, omz-order, nvm-homebrew).

Host selection (default: DOTFILES_HOST, else the host ./stow-all.sh recorded):
  --host HOST         mac, wsl-ubuntu, lab-ubuntu, sherlock or marlowe
                      (win: pwsh -File doctor.ps1 -Host win)
  --platform PLATFORM macos, debian, hpc or other: rows for every host only,
                      without a host overlay

Options:
  --tier LIST|all     required tiers, comma list of core, cli, ai, desktop,
                      contributor, host (default core,cli,ai); rows of other
                      tiers report warn instead of missing or outdated
  --tsv               print only TSV: status, id, tier, detail, fix
  --quiet             print only rows that need attention, then the summary
  --online            also run gh auth status, claude auth status and
                      codex login status (failures are warn)
  --smoke             also run zsh -ic true with the update hooks off and
                      report missing plugins, commands and files (may write
                      shell caches)
  --list              print the applicable rows (id, tier, probe, floor, doc)
                      without probing
  -h, --help          show this help

Statuses: ok outdated missing warn skip human. Fixes cite docs/bootstrap.md.
Exit: 0 every required tier ok; 1 a required row missing or outdated, or a
structural error; 2 usage error, invalid manifest, unknown host or win.
EOF
}

usage_error() {
    dotfiles_log error "$1"
    dotfiles_log error 'Run ./doctor.sh --help for usage.'
    exit 2
}

known_hosts_line() {
    local hosts
    hosts=$(bootstrap_known_hosts | tr '\n' ' ')
    printf '%s\n' "${hosts% }"
}

reject_win() {
    dotfiles_log error "the 'win' host is checked from Windows, not from POSIX."
    dotfiles_log error 'Run this in PowerShell from the repo root instead: pwsh -File doctor.ps1 -Host win'
    exit 2
}

HOST=
HOST_SET=0
PLATFORM=
TIERS=core,cli,ai
TSV=0
QUIET=0
ONLINE=0
SMOKE=0
LIST=0

while [[ $# -gt 0 ]]; do
    option=$1
    value=
    case $option in
        --host=* | --platform=* | --tier=*)
            value=${option#*=}
            option=${option%%=*}
            [[ -n "$value" ]] || usage_error "$option needs a value."
            ;;
        --host | --platform | --tier)
            [[ $# -ge 2 && -n "${2:-}" ]] || usage_error "$option needs a value."
            value=$2
            shift
            ;;
    esac
    case $option in
        --host)
            HOST=$value
            HOST_SET=1
            ;;
        --platform) PLATFORM=$value ;;
        --tier) TIERS=$value ;;
        --tsv) TSV=1 ;;
        --quiet) QUIET=1 ;;
        --online) ONLINE=1 ;;
        --smoke) SMOKE=1 ;;
        --list) LIST=1 ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) usage_error "unknown argument: $option" ;;
    esac
    shift
done

if [[ $HOST_SET == 1 && -n "$PLATFORM" ]]; then
    usage_error '--host and --platform are mutually exclusive.'
fi

case $TIERS in
    all) ;;
    *)
        rest=$TIERS,
        while [[ -n "$rest" ]]; do
            tier=${rest%%,*}
            rest=${rest#*,}
            case " $BOOTSTRAP_TIER_ORDER " in
                *" $tier "*) ;;
                *) usage_error "unknown tier '$tier' in --tier $TIERS (use all or a comma list of: $BOOTSTRAP_TIER_ORDER)" ;;
            esac
        done
        ;;
esac

if [[ -z "${HOME:-}" ]]; then
    usage_error 'HOME is not set.'
fi

# Host and profile. --platform runs without an overlay: only all/unix rows.
if [[ -n "$PLATFORM" ]]; then
    case $PLATFORM in
        macos | debian | hpc | other) PROFILE=$PLATFORM ;;
        *) usage_error "unknown platform '$PLATFORM' (use macos, debian, hpc or other)" ;;
    esac
    HOST=
else
    if [[ $HOST_SET == 0 ]]; then
        if [[ -n "${DOTFILES_HOST:-}" ]]; then
            [[ "$DOTFILES_HOST" != win ]] || reject_win
            HOST=$(bootstrap_resolve_host "$REPO_ROOT") ||
                usage_error "DOTFILES_HOST='$DOTFILES_HOST' is not a known host (known: $(known_hosts_line))."
        elif bootstrap_find_command git >/dev/null; then
            HOST=$(bootstrap_resolve_host "$REPO_ROOT") || HOST=
        fi
        if [[ -z "$HOST" ]]; then
            usage_error "no host given and none recorded for this home; pass --host HOST (known: $(known_hosts_line)) or --platform PLATFORM."
        fi
    fi
    [[ "$HOST" != win ]] || reject_win
    PROFILE=$(bootstrap_profile_for_host "$HOST") ||
        usage_error "unknown host '$HOST' (known: $(known_hosts_line))."
fi

# Manifest: present, the expected header, and every row well formed.
bootstrap_init "$REPO_ROOT"
TOOLS_TSV=$BOOTSTRAP_CONFIG/tools.tsv
TOOLS_HEADER="id${BOOTSTRAP_TAB}tier${BOOTSTRAP_TAB}hosts${BOOTSTRAP_TAB}probe${BOOTSTRAP_TAB}version_flag${BOOTSTRAP_TAB}floor${BOOTSTRAP_TAB}absent${BOOTSTRAP_TAB}doc"

invalid_manifest() {
    dotfiles_log error "invalid manifest $TOOLS_TSV: $1"
    exit 2
}

[[ -f "$TOOLS_TSV" && -r "$TOOLS_TSV" ]] || invalid_manifest 'missing or unreadable'
header=$(awk '/^#/ { next } /^[ \t\r]*$/ { next } { print; exit }' "$TOOLS_TSV")
[[ "$header" == "$TOOLS_HEADER" ]] || invalid_manifest 'the header is not: id tier hosts probe version_flag floor absent doc'
ALL_ROWS=$(bootstrap_rows "$TOOLS_TSV") || invalid_manifest 'unreadable'
[[ -n "$ALL_ROWS" ]] || invalid_manifest 'no data rows'
# Ids that tools.tsv must not use: the --online and --smoke rows and the
# structural checks.
RESERVED_IDS=' gh-auth claude-auth codex-auth zsh-smoke '
while IFS=' ' read -r id _ <&3; do
    [[ -z "$id" ]] || RESERVED_IDS="$RESERVED_IDS$id "
done 3<<EOF
$BOOTSTRAP_STRUCTURAL_CHECKS
EOF
# Every row's doc step must have a heading in docs/bootstrap.md, the file
# each fix cites (checked only when the file is there).
DOC_STEPS=$(bootstrap_doc_steps "$REPO_ROOT/docs/bootstrap.md") || DOC_STEPS=
SEEN_IDS=' '
while IFS= read -r row <&3; do
    reason=$(bootstrap_tool_row_valid "$row" "$DOC_STEPS") || invalid_manifest "$reason"
    id=${row%%"$BOOTSTRAP_TAB"*}
    case $RESERVED_IDS in
        *" $id "*) invalid_manifest "id $id is reserved for a doctor check" ;;
    esac
    case $SEEN_IDS in
        *" $id "*) invalid_manifest "duplicate id $id" ;;
    esac
    SEEN_IDS="$SEEN_IDS$id "
done 3<<EOF
$ALL_ROWS
EOF
ROWS=$(bootstrap_tool_rows "$HOST") || invalid_manifest 'unreadable'

# Probe what the installers just put in place: a fresh Homebrew and the hpc
# login env stay off PATH until the stowed rc files add them. This changes
# only this process's PATH; path-order judges the caller's PATH.
ORIG_PATH=$PATH
prepend_path() {
    case ":$PATH:" in
        *":$1:"*) ;;
        *) PATH=$1:$PATH ;;
    esac
}
if brew_bin=$(bootstrap_brew_bin); then
    prepend_path "${brew_bin%/brew}"
fi
if [[ $PROFILE == hpc && -d "$HOME/micromamba/envs/login/bin" ]]; then
    prepend_path "$HOME/micromamba/envs/login/bin"
fi
export PATH

if [[ $LIST == 1 ]]; then
    printf 'id\ttier\tprobe\tfloor\tdoc\n'
    while IFS= read -r row <&3; do
        [[ -n "$row" ]] || continue
        IFS=$BOOTSTRAP_TAB read -r id tier _ probe flag floor absent doc <<EOF
$row
EOF
        printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$tier" "$probe" "$floor" \
            "$(bootstrap_doc_ref "$doc" "$PROFILE")"
    done 3<<EOF
$ROWS
EOF
    while IFS=' ' read -r id tier step <&3; do
        [[ -n "$id" ]] || continue
        printf '%s\t%s\tcheck\t-\t%s\n' "$id" "$tier" "$(bootstrap_doc_ref "$step" "$PROFILE")"
    done 3<<EOF
$BOOTSTRAP_STRUCTURAL_CHECKS
EOF
    exit 0
fi

N_OK=0
N_OUTDATED=0
N_MISSING=0
N_WARN=0
N_SKIP=0
N_HUMAN=0
FAILED=0

# report STATUS ID TIER DETAIL STEP [keep]: downgrade missing, outdated and
# human to warn outside the selected tiers (unless "keep"), count, print.
report() {
    local status=$1 id=$2 tier=$3 detail=$4 step=$5 keep=${6:-} level fix
    case $status in
        missing | outdated | human)
            if [[ -z "$keep" ]] && ! bootstrap_tier_selected "$tier" "$TIERS"; then
                status=warn
            fi
            ;;
    esac
    case $status in
        ok)
            level=ok
            N_OK=$((N_OK + 1))
            ;;
        skip)
            level=info
            N_SKIP=$((N_SKIP + 1))
            ;;
        warn)
            level=warn
            N_WARN=$((N_WARN + 1))
            ;;
        outdated)
            level=error
            N_OUTDATED=$((N_OUTDATED + 1))
            ;;
        human)
            level=error
            N_HUMAN=$((N_HUMAN + 1))
            ;;
        *)
            status=missing
            level=error
            N_MISSING=$((N_MISSING + 1))
            ;;
    esac
    [[ $level != error ]] || FAILED=1
    case $status in
        ok | skip) fix=- ;;
        *) fix="docs/bootstrap.md $(bootstrap_doc_ref "$step" "$PROFILE")" ;;
    esac
    if [[ $QUIET == 1 ]]; then
        case $status in
            ok | skip) return 0 ;;
        esac
    fi
    if [[ $TSV == 1 ]]; then
        printf '%s\t%s\t%s\t%s\t%s\n' "$status" "$id" "$tier" "$detail" "$fix"
    elif [[ $fix == - ]]; then
        dotfiles_log "$level" "$tier $id: $detail"
    else
        dotfiles_log "$level" "$tier $id: $detail ($fix)"
    fi
}

# report_result RESULT ID TIER STEP [keep]: split a check's STATUS<TAB>DETAIL.
report_result() {
    local result=$1
    [[ -n "$result" ]] || result="missing${BOOTSTRAP_TAB}check produced no result"
    report "${result%%"$BOOTSTRAP_TAB"*}" "$2" "$3" "${result#*"$BOOTSTRAP_TAB"}" "$4" "${5:-}"
}

if [[ $TSV == 1 ]]; then
    printf 'status\tid\ttier\tdetail\tfix\n'
elif [[ $QUIET == 0 ]]; then
    if [[ -n "$HOST" ]]; then
        dotfiles_log step "Checking host $HOST ($PROFILE); required tiers: $TIERS"
    else
        dotfiles_log step "Checking platform $PROFILE without a host overlay; required tiers: $TIERS"
    fi
fi

# Every row passed bootstrap_tool_row_valid (eight non-empty cells), so a
# tab-IFS read splits it exactly.
while IFS= read -r row <&3; do
    [[ -n "$row" ]] || continue
    IFS=$BOOTSTRAP_TAB read -r id tier _ probe flag floor absent doc <<EOF
$row
EOF
    report_result "$(bootstrap_check_tool "$probe" "$flag" "$floor" "$absent")" "$id" "$tier" "$doc"
done 3<<EOF
$ROWS
EOF

while IFS=' ' read -r id tier step <&3; do
    [[ -n "$id" ]] || continue
    report_result "$(bootstrap_check_structural "$id" "$REPO_ROOT" "$PROFILE" "$ORIG_PATH")" \
        "$id" "$tier" "$step"
done 3<<EOF
$BOOTSTRAP_STRUCTURAL_CHECKS
EOF

if [[ $ONLINE == 1 ]]; then
    report_result "$(bootstrap_check_auth gh)" gh-auth cli H7-auth
    report_result "$(bootstrap_check_auth claude)" claude-auth ai H7-auth
    report_result "$(bootstrap_check_auth codex)" codex-auth ai H7-auth
fi

if [[ $SMOKE == 1 ]]; then
    report_result "$(bootstrap_check_smoke "$ORIG_PATH")" zsh-smoke core H7-doctor keep
fi

if [[ $TSV == 0 ]]; then
    dotfiles_log info "summary: $N_OK ok, $N_OUTDATED outdated, $N_MISSING missing, $N_WARN warn, $N_SKIP skip, $N_HUMAN human (${HOST:-platform $PROFILE}, required tiers: $TIERS)"
fi
exit "$FAILED"
