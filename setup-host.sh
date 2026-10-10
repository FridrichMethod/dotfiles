#!/bin/bash

set -euo pipefail

# Usage: ./setup-host.sh --host HOST [--tier LIST|all] [--check] [--yes]
#            [--only ID]... [--skip ID]... [--keep-going] [--list] [--print-manual]
# Example: ./setup-host.sh --host lab-ubuntu --check
# Installs what the stowed configs assume, step by step in the order of
# docs/bootstrap.md, from the pinned sources in config/bootstrap/. It never
# runs sudo, chsh, stow, ./stow-all.sh, conda init, micromamba shell init or
# git lfs install, and never writes an rc file or a tracked file: those are
# printed as HUMAN blocks for a person (or one visible top-level agent
# command). The only write inside the checkout is .venv-sync, made by
# ./setup-sync.sh. --check writes nothing and makes no network calls.
# Exit: 0 every selected step done (non-blocking HUMAN reminders may still
# print), 1 a step failed, 2 usage or refusal (also as root, or on a machine
# that is not HOST), 3 work remains: a blocking HUMAN step pending, or auto
# steps left to apply (--check, a declined prompt).
# The win host uses setup-host.ps1 from PowerShell instead.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
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

usage() {
    printf '%s\n' \
        'Usage: ./setup-host.sh --host HOST [options]' \
        '' \
        'Installs the day-zero tools for HOST without sudo, then prints the HUMAN' \
        'blocks (sudo, sign-in, ./stow-all.sh) that a person runs. See docs/bootstrap.md.' \
        '' \
        '  --host HOST       mac, wsl-ubuntu, lab-ubuntu, sherlock or marlowe; defaults' \
        '                    to DOTFILES_HOST or the host ./stow-all.sh recorded;' \
        '                    common only (a set but empty DOTFILES_HOST, or a' \
        '                    common-only install ./stow-all.sh recorded) needs --host.' \
        '                    The win host uses setup-host.ps1.' \
        '  --tier LIST|all   comma list of core, cli, ai, desktop, contributor, host' \
        '                    (default core,cli,ai)' \
        '  --check           print one plan line per step and the pending HUMAN blocks;' \
        '                    writes nothing and makes no network calls' \
        '  --yes             apply without asking (required when stdin is not a terminal)' \
        '  --only ID         run only this step (repeatable)' \
        '  --skip ID         skip this step (repeatable)' \
        '  --keep-going      continue after a failed step' \
        '  --list            print the steps for HOST: id, kind, tier, blocking' \
        '  --print-manual    print every HUMAN block for HOST, pending or not' \
        '  -h, --help        show this help' \
        '' \
        'Plan lines: <step-id> <done|todo|human|skip|failed> <detail>' \
        'HUMAN blocks: HUMAN-BEGIN <step-id> <kind> ... HUMAN-END (printed, never run);' \
        "              '# ' lines are notes, every other line one self-contained command" \
        'Exit: 0 every selected step is done or not applicable (non-blocking' \
        '        HUMAN blocks may still be printed)' \
        '      1 a step failed' \
        '      2 usage or refusal (unknown host, win, root, not this platform,' \
        '        no terminal without --yes, invalid manifest)' \
        '      3 work remains: a blocking HUMAN step pending, or auto steps still to' \
        '        apply (--check, a declined prompt, or waiting on a HUMAN step)' \
        'Run it as your user, never with sudo.'
}

usage_error() {
    dotfiles_log error "$1"
    dotfiles_log error 'run ./setup-host.sh --help for usage'
    exit 2
}

for lib in manifest platform version checks fetch steps steps-guard steps-common steps-human \
    steps-packages steps-files steps-runtimes steps-archives; do
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
# S2-brew-bundle judges a Brewfile entry with the doctor's own probe.
# shellcheck source=lib/bootstrap/checks.sh
. "$REPO_ROOT/lib/bootstrap/checks.sh"
# shellcheck source=lib/bootstrap/fetch.sh
. "$REPO_ROOT/lib/bootstrap/fetch.sh"
# shellcheck source=lib/bootstrap/steps.sh
. "$REPO_ROOT/lib/bootstrap/steps.sh"
# shellcheck source=lib/bootstrap/steps-guard.sh
. "$REPO_ROOT/lib/bootstrap/steps-guard.sh"
# shellcheck source=lib/bootstrap/steps-common.sh
. "$REPO_ROOT/lib/bootstrap/steps-common.sh"
# shellcheck source=lib/bootstrap/steps-human.sh
. "$REPO_ROOT/lib/bootstrap/steps-human.sh"
# shellcheck source=lib/bootstrap/steps-packages.sh
. "$REPO_ROOT/lib/bootstrap/steps-packages.sh"
# shellcheck source=lib/bootstrap/steps-files.sh
. "$REPO_ROOT/lib/bootstrap/steps-files.sh"
# shellcheck source=lib/bootstrap/steps-runtimes.sh
. "$REPO_ROOT/lib/bootstrap/steps-runtimes.sh"
# shellcheck source=lib/bootstrap/steps-archives.sh
. "$REPO_ROOT/lib/bootstrap/steps-archives.sh"

# No here-documents or here-strings here or in the libraries: Bash 3.2 backs
# each one with a temporary file, and --check writes nothing (see
# lib/bootstrap/manifest.sh). Lines are split with parameter expansion,
# fields with bootstrap_split.

HOST=''
TIERS=core,cli,ai
MODE=apply
MODE_FLAG=''
YES=0
KEEP_GOING=0
ONLY=''
SKIP=''

set_mode() {
    if [[ -n "$MODE_FLAG" && "$MODE_FLAG" != "$2" ]]; then
        usage_error "$MODE_FLAG and $2 cannot be combined"
    fi
    MODE=$1
    MODE_FLAG=$2
}

need_value() {
    [[ $# -ge 2 && -n "$2" ]] || usage_error "$1 needs a value"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --host)
            need_value "$@"
            HOST=$2
            shift 2
            ;;
        --host=*)
            HOST=${1#*=}
            shift
            ;;
        --tier)
            need_value "$@"
            TIERS=$2
            shift 2
            ;;
        --tier=*)
            TIERS=${1#*=}
            shift
            ;;
        --only)
            need_value "$@"
            ONLY="$ONLY,$2"
            shift 2
            ;;
        --only=*)
            ONLY="$ONLY,${1#*=}"
            shift
            ;;
        --skip)
            need_value "$@"
            SKIP="$SKIP,$2"
            shift 2
            ;;
        --skip=*)
            SKIP="$SKIP,${1#*=}"
            shift
            ;;
        --check)
            set_mode check --check
            shift
            ;;
        --list)
            set_mode list --list
            shift
            ;;
        --print-manual)
            set_mode manual --print-manual
            shift
            ;;
        --yes)
            YES=1
            shift
            ;;
        --keep-going)
            KEEP_GOING=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) usage_error "unknown argument: $1" ;;
    esac
done

# Everything installs into the invoking user's home; as root it would land
# in /root, or leave root-owned files in a home that sudo kept. The sudo
# steps are HUMAN blocks a person runs.
if [[ "$(id -u 2>/dev/null || true)" == 0 ]]; then
    dotfiles_log error 'run ./setup-host.sh as your user, not root (no sudo); the sudo steps are printed as HUMAN blocks'
    exit 2
fi

# A set but empty DOTFILES_HOST, and without DOTFILES_HOST a common-only
# install that ./stow-all.sh recorded for this home, mean common only (as the
# login updater reads them), and there is no --platform here: every step
# needs an overlay.
COMMON_ONLY_HINT='setup-host needs one: pass --host HOST (mac, wsl-ubuntu, lab-ubuntu, sherlock or marlowe), or follow X-other-linux in docs/bootstrap.md'
if [[ -z "$HOST" ]] && bootstrap_host_env_empty; then
    usage_error "DOTFILES_HOST is set but empty, which means common only (no host overlay); $COMMON_ONLY_HINT"
fi
if [[ -z "$HOST" && -z "${DOTFILES_HOST:-}" ]] && bootstrap_recorded_common_only "$REPO_ROOT"; then
    usage_error "./stow-all.sh recorded a common-only install for this home (no host overlay); $COMMON_ONLY_HINT"
fi
if [[ -z "$HOST" ]]; then
    HOST=$(bootstrap_resolve_host "$REPO_ROOT") ||
        usage_error 'no host: pass --host HOST (mac, wsl-ubuntu, lab-ubuntu, sherlock or marlowe)'
fi
if [[ "$HOST" == win ]]; then
    dotfiles_log error "the 'win' host is set up from Windows, not from POSIX."
    dotfiles_log error 'Run this in PowerShell from the repo root instead: .\setup-host.ps1'
    exit 2
fi
PROFILE=$(bootstrap_profile_for_host "$HOST") ||
    usage_error "unknown host: $HOST (expected mac, wsl-ubuntu, lab-ubuntu, sherlock or marlowe)"

# comma_items LIST: the items of a comma list, one per line (empty ones too).
comma_items() {
    local rest=$1
    while :; do
        printf '%s\n' "${rest%%,*}"
        [[ "$rest" == *,* ]] || break
        rest=${rest#*,}
    done
}

if [[ "$TIERS" != all ]]; then
    lines=$(comma_items "$TIERS")$BOOTSTRAP_NL
    while [[ -n "$lines" ]]; do
        tier=${lines%%"$BOOTSTRAP_NL"*}
        lines=${lines#*"$BOOTSTRAP_NL"}
        case $tier in
            core | cli | ai | desktop | contributor | host) ;;
            *) usage_error "unknown tier: '$tier' (core, cli, ai, desktop, contributor, host or all)" ;;
        esac
    done
fi

# The run state that the step libraries read; a lint run without those files
# on its command line cannot see the reads.
# shellcheck disable=SC2034
{
    STEPS_ROOT=$REPO_ROOT
    STEPS_HOST=$HOST
    STEPS_PROFILE=$PROFILE
    STEPS_ARCH=$(bootstrap_arch) || true
    STEPS_MODE=$MODE
    STEPS_TIERS=$TIERS
    STEPS_ONLY=${ONLY:+$ONLY,}
    STEPS_SKIP=${SKIP:+$SKIP,}
    STEPS_YES=$YES
    STEPS_KEEP_GOING=$KEEP_GOING
}
bootstrap_init "$REPO_ROOT"

lines=$(comma_items "${ONLY#,}${ONLY:+,}${SKIP#,}")$BOOTSTRAP_NL
while [[ -n "$lines" ]]; do
    id=${lines%%"$BOOTSTRAP_NL"*}
    lines=${lines#*"$BOOTSTRAP_NL"}
    [[ -n "$id" ]] || continue
    steps_has "$id" || usage_error "unknown step for $HOST: '$id' (see ./setup-host.sh --host $HOST --list)"
done

if [[ "$MODE" == list ]]; then
    steps_list
    exit 0
fi

steps_validate_manifests || exit 2

if [[ "$MODE" == manual ]]; then
    steps_print_manual
    exit 0
fi

mismatch=$(steps_platform_mismatch)
if [[ -n "$mismatch" ]]; then
    dotfiles_log error "refusing: $mismatch"
    exit 2
fi

if [[ "$MODE" == apply && "$YES" != 1 && ! -t 0 ]]; then
    dotfiles_log error 'refusing to apply without a terminal: pass --yes, or --check for a read-only plan'
    exit 2
fi

# Provisioning never triggers the login updaters, git prompts or Homebrew
# auto-update, hints and cleanup. Older brew bundle wrote Brewfile.lock.json
# next to the Brewfile, inside this checkout. --check never runs brew.
# S2-brew-bundle probes each Brewfile tool as the doctor does, running the
# version flag of its tools.tsv row (gh --version, tldr --version), and a
# tool a step starts may run them too: recent gh releases answer any
# command, --version included, by writing ~/.local/state/gh/device-id unless
# GH_TELEMETRY=0, and the tldr C client (Homebrew's tldr formula), once its
# page cache is two weeks old, answers any command but --update by
# downloading the tldr-pages archive into ~/.tldrc unless
# TLDR_AUTO_UPDATE_DISABLED is set.
export DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0 GIT_TERMINAL_PROMPT=0 NONINTERACTIVE=1 \
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
    HOMEBREW_BUNDLE_NO_LOCK=1 GH_TELEMETRY=0 GH_NO_UPDATE_NOTIFIER=1 TLDR_AUTO_UPDATE_DISABLED=1
steps_extend_path

if [[ "$MODE" == check ]]; then
    dotfiles_log step "Plan for $HOST ($PROFILE, tiers $TIERS); --check writes nothing"
else
    dotfiles_log step "Setting up $HOST ($PROFILE, tiers $TIERS) from $REPO_ROOT"
fi
steps_run
exit "$STEPS_EXIT"
