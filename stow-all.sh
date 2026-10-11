#!/bin/bash

set -euo pipefail

# Usage: ./stow-all.sh [host-dir]
# Example: ./stow-all.sh wsl-ubuntu
# If no host-dir is provided, only stow common.
# Successful setup remembers this home/platform/host for automatic login stow.
# DOTFILES_AUTO_STOW=0 disables automatic stow in the login updater.
# The common Claude package links local Node helpers and syncs its defaults;
# Node.js 22+ must be on PATH when Claude runs the hooks and status line.
# Day-zero prerequisites come from ./setup-host.sh and are checked by ./doctor.sh.
# It refuses to stow the zsh package before oh-my-zsh is cloned, since Stow
# would create a real ~/.oh-my-zsh/custom that blocks the clone
# (DOTFILES_STOW_WITHOUT_OH_MY_ZSH=1 stows anyway), and stops before the AI
# sync helpers write anything when a Stow dry run finds a conflicting file.
# Run ./setup-sync.sh once per clone to provision the AI configuration parser.
# A host whose sherlock-kit package links the toolkit rules from the submodule
# also gets ~/.codex/AGENTS.override.md (portable AGENTS.md plus those rules);
# other hosts have a stale generated one removed. While the submodule is not
# initialized, only that step is skipped with a warning, and the revision is
# not recorded as applied, so the login updater retries it.
# All selected AI inputs are checked before any live configuration is changed.
# A dangling home link that Stow made for a since-deleted package file (today
# only the 0.3 ~/.local/bin/shk) is removed before the Stow dry runs.
# The win host is installed from Windows by stow-all.ps1, not from here.
HOST="${1:-}"
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

if [[ "$HOST" == "win" ]]; then
    dotfiles_log error "the 'win' host is installed from Windows, not from POSIX."
    dotfiles_log error 'Its packages mirror Windows-only paths (Documents\PowerShell, AppData\Local\Packages) that mean nothing in a POSIX $HOME.'
    dotfiles_log error 'Run this in PowerShell from the repo root instead: .\stow-all.ps1 win'
    exit 1
fi

case "$HOST" in
    common | .* | */* | *\\*)
        dotfiles_log error 'host must be a top-level host directory (or omitted for common-only).'
        exit 1
        ;;
esac

dotfiles_log step "Stowing from $REPO_ROOT"

COMMON_DIR="${REPO_ROOT}/common"
HOST_DIR="${REPO_ROOT}/${HOST}"

if [[ ! -d "$COMMON_DIR" ]]; then
    dotfiles_log error "missing common dir: $COMMON_DIR"
    exit 1
fi
if [[ -n "$HOST" && ! -d "$HOST_DIR" ]]; then
    dotfiles_log error "host dir not found: $HOST_DIR"
    exit 1
fi
if [[ ! -f "$REPO_ROOT/.stowrc" || ! -r "$REPO_ROOT/.stowrc" ]]; then
    dotfiles_log error 'required .stowrc is missing or unreadable; refusing to install without target and ignore defaults.'
    exit 1
fi
if ! command -v stow >/dev/null 2>&1; then
    dotfiles_log error 'required GNU Stow is missing; install stow before applying dotfiles.'
    exit 1
fi

# A package that links into ~/.oh-my-zsh (common/zsh) needs the oh-my-zsh
# clone first: with --no-folding, Stow would create a real ~/.oh-my-zsh/custom,
# after which oh-my-zsh can no longer be cloned there and zsh aborts.
NEEDS_OMZ=0
for omz_dir in "$COMMON_DIR"/*/.oh-my-zsh ${HOST:+"$HOST_DIR"/*/.oh-my-zsh}; do
    if [[ -d "$omz_dir" ]]; then
        NEEDS_OMZ=1
    fi
done
if [[ "$NEEDS_OMZ" == 1 && ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" && "${DOTFILES_STOW_WITHOUT_OH_MY_ZSH:-0}" != 1 ]]; then
    if [[ -e "$HOME/.oh-my-zsh" || -L "$HOME/.oh-my-zsh" ]]; then
        dotfiles_log error "$HOME/.oh-my-zsh exists without oh-my-zsh.sh, as after a stow before the oh-my-zsh clone; turn it into the clone first (docs/bootstrap.md X-recovery)."
    else
        dotfiles_log error "oh-my-zsh is not cloned yet, and stowing now would create a real $HOME/.oh-my-zsh/custom that blocks the clone."
        dotfiles_log error "Clone it first: ./setup-host.sh --host ${HOST:-HOST} (S3-clones), or clone_listed oh-my-zsh on another Linux (docs/bootstrap.md X-other-linux)."
    fi
    dotfiles_log error 'Nothing was changed. To stow without oh-my-zsh anyway, rerun with DOTFILES_STOW_WITHOUT_OH_MY_ZSH=1.'
    exit 1
fi

COMMON_PKGS=''
if compgen -G "${COMMON_DIR}"'/*/' >/dev/null; then
    COMMON_PKGS=$(basename -a "${COMMON_DIR}"/*/)
fi
HOST_PKGS=''
if [[ -n "$HOST" ]] && compgen -G "${HOST_DIR}"'/*/' >/dev/null; then
    HOST_PKGS=$(basename -a "${HOST_DIR}"/*/)
fi

cd "$REPO_ROOT" # ensures ./.stowrc is picked up
START_HEAD=$(git rev-parse HEAD 2>/dev/null) || START_HEAD=

# A present package requires its materialized settings and executable helper.
# Stow ignores those settings files, so skipping a missing helper would leave
# stale live settings while falsely recording the entire HEAD as applied.
require_sync() {
    if [[ ! -f "$1" || ! -x "$1" ]]; then
        dotfiles_log error "required sync helper is missing or not executable: $1"
        exit 1
    fi
    if [[ ! -f "$2" || ! -r "$2" ]]; then
        dotfiles_log error "required portable settings are missing or unreadable: $2"
        exit 1
    fi
}

CODEX_SYNC="$COMMON_DIR/codex/.local/bin/codex-config-sync"
CODEX_PORTABLE="$COMMON_DIR/codex/.codex/config.toml"
if [[ -n "$HOST" && -f "$HOST_DIR/codex/.codex/config.toml" ]]; then
    CODEX_PORTABLE="$HOST_DIR/codex/.codex/config.toml"
fi
CODEX_RULES_SYNC="$COMMON_DIR/codex/.local/bin/codex-rules-sync"
CODEX_RULES_PORTABLE="$COMMON_DIR/codex/.codex/rules/portable.rules"
if [[ -n "$HOST" && -f "$HOST_DIR/codex/.codex/rules/portable.rules" ]]; then
    CODEX_RULES_PORTABLE="$HOST_DIR/codex/.codex/rules/portable.rules"
fi
CLAUDE_SYNC="$COMMON_DIR/claude/.local/bin/claude-settings-sync"
CLAUDE_PORTABLE="$COMMON_DIR/claude/.claude/settings.json"
if [[ -n "$HOST" && -f "$HOST_DIR/claude/.claude/settings.json" ]]; then
    CLAUDE_PORTABLE="$HOST_DIR/claude/.claude/settings.json"
fi
# Codex reads one global instructions file, so the host's sherlock-kit rules
# reach it only through a generated override. -L also selects a dangling link,
# which is reported below instead of being mistaken for a host without rules.
CODEX_INSTRUCTIONS_SYNC="$COMMON_DIR/codex/.local/bin/codex-instructions-sync"
CODEX_INSTRUCTIONS_PORTABLE="$COMMON_DIR/codex/.codex/AGENTS.md"
CODEX_INSTRUCTIONS_LIVE="$HOME/.codex/AGENTS.override.md"
SHERLOCK_RULES=''
if [[ -n "$HOST" ]]; then
    host_rules="$HOST_DIR/sherlock-kit/.claude/rules/sherlock-kit.md"
    if [[ -L "$host_rules" || -e "$host_rules" ]]; then
        SHERLOCK_RULES=$host_rules
    fi
fi

# Validate every selected package before any helper changes the live home.
SYNC_CODEX=0
SYNC_CODEX_INSTRUCTIONS=0
CODEX_INSTRUCTIONS_SKIPPED=0
if [[ -d "$COMMON_DIR/codex" || (-n "$HOST" && -d "$HOST_DIR/codex") ]]; then
    require_sync "$CODEX_SYNC" "$CODEX_PORTABLE"
    require_sync "$CODEX_RULES_SYNC" "$CODEX_RULES_PORTABLE"
    require_sync "$CODEX_INSTRUCTIONS_SYNC" "$CODEX_INSTRUCTIONS_PORTABLE"
    SYNC_CODEX=1
    # A local merge or fresh clone leaves the submodule empty and the rules
    # link dangling; the login updater must not fail every stow over that.
    # The skip leaves the install incomplete, so HEAD is not recorded below.
    if [[ -n "$SHERLOCK_RULES" && ! -e "$SHERLOCK_RULES" ]]; then
        dotfiles_log warn 'sherlock-kit submodule not initialized; Codex instructions left unchanged (git submodule update --init --recursive)'
        CODEX_INSTRUCTIONS_SKIPPED=1
    else
        SYNC_CODEX_INSTRUCTIONS=1
    fi
fi
SYNC_CLAUDE=0
if [[ -d "$COMMON_DIR/claude" || (-n "$HOST" && -d "$HOST_DIR/claude") ]]; then
    require_sync "$CLAUDE_SYNC" "$CLAUDE_PORTABLE"
    SYNC_CLAUDE=1
fi
SYNC_FCITX5=0
if [[ -n "$HOST" && -d "$HOST_DIR/fcitx5" ]]; then
    FCITX5_SYNC="$HOST_DIR/fcitx5/.local/bin/fcitx5-profile-sync"
    FCITX5_PORTABLE="$HOST_DIR/fcitx5/.config/fcitx5/profile"
    require_sync "$FCITX5_SYNC" "$FCITX5_PORTABLE"
    SYNC_FCITX5=1
fi

# Hosts without the rules link run the helper without --append: it removes a
# stale generated override and only warns about a file it did not generate.
# $1 is --check for the preflight and absent for the apply step.
sync_codex_instructions() {
    if [[ -n "$SHERLOCK_RULES" ]]; then
        "$CODEX_INSTRUCTIONS_SYNC" --quiet ${1:+"$1"} --append "$SHERLOCK_RULES" \
            "$CODEX_INSTRUCTIONS_PORTABLE" "$CODEX_INSTRUCTIONS_LIVE"
    else
        "$CODEX_INSTRUCTIONS_SYNC" --quiet ${1:+"$1"} \
            "$CODEX_INSTRUCTIONS_PORTABLE" "$CODEX_INSTRUCTIONS_LIVE"
    fi
}

# Validate runtime dependencies and both documents for every selected AI
# helper. A malformed later baseline must not partially apply earlier ones.
# This is a read-only preflight, not a transaction across independent files.
if [[ "$SYNC_CODEX" == 1 || "$SYNC_CLAUDE" == 1 ]]; then
    dotfiles_log step 'Checking selected AI configuration and runtime'
fi
if [[ "$SYNC_CODEX" == 1 ]]; then
    "$CODEX_SYNC" --quiet --check "$CODEX_PORTABLE" "$HOME/.codex/config.toml"
    "$CODEX_RULES_SYNC" --quiet --check "$CODEX_RULES_PORTABLE" \
        "$HOME/.codex/rules/portable.rules"
fi
if [[ "$SYNC_CODEX_INSTRUCTIONS" == 1 ]]; then
    sync_codex_instructions --check
fi
if [[ "$SYNC_CLAUDE" == 1 ]]; then
    "$CLAUDE_SYNC" --quiet --check "$CLAUDE_PORTABLE" "$HOME/.claude/settings.json"
fi

# A link Stow made for a package file this checkout has since deleted stays
# dangling in the home, and the dry run of another stow directory that claims
# its path aborts on it ("existing target is not owned by stow"). Only a
# dangling link whose text names exactly the retired source in this checkout
# is removed; a live link, a foreign link or a file is left for the dry run to
# report. Stow wrote the text between physical paths, so cd -P resolves its
# directory from the link's physical directory; the retired source's own
# directory must still exist. This runs after the read-only preflight.
remove_retired_link() {
    local link=$HOME/$1 text dir
    [[ -L "$link" && ! -e "$link" ]] || return 0
    text=$(readlink "$link")
    # A foreign text may name a directory that does not exist: not retired.
    dir=$(cd -P -- "${link%/*}" && cd -P -- "$(dirname -- "$text")" 2>/dev/null && pwd -P) || return 0
    [[ "$dir/${text##*/}" == "$REPO_PHYSICAL/$2" ]] || return 0
    rm -f -- "$link"
    dotfiles_log info "Removed retired link $link (its source $2 was deleted)"
}
REPO_PHYSICAL=$(pwd -P)
# The 0.3 sherlock-kit launcher; the host sherlock-kit packages link shk now.
# Its directory still holds the codex sync helpers this script runs.
remove_retired_link .local/bin/shk common/codex/.local/bin/shk

# Stow never replaces a regular file (a fresh home's ~/.bashrc and ~/.profile
# from /etc/skel, for one). A dry run of both stows finds every conflict
# before the sync helpers write ~/.claude and ~/.codex. Its simulation notice
# is shown only with the conflicts.
stow_dry_run() {
    local output
    # shellcheck disable=SC2086 # package names are single words
    if ! output=$(stow -n --restow --no-folding -d "$1" $2 2>&1); then
        printf '%s\n' "$output" >&2
        dotfiles_log error "Stow would conflict with the files listed above, so nothing was changed. Move each one aside (for example mv ~/.bashrc ~/.bashrc.pre-dotfiles), never stow --adopt, then rerun (docs/bootstrap.md H7-stow)."
        exit 1
    fi
}
if [[ -n "$COMMON_PKGS" ]]; then
    stow_dry_run "$COMMON_DIR" "$COMMON_PKGS"
fi
if [[ -n "$HOST_PKGS" ]]; then
    stow_dry_run "$HOST_DIR" "$HOST_PKGS"
fi

if [[ "$SYNC_CODEX" == 1 ]]; then
    dotfiles_log step 'Synchronizing portable Codex settings'
    "$CODEX_SYNC" --quiet "$CODEX_PORTABLE" "$HOME/.codex/config.toml"
    dotfiles_log step 'Synchronizing portable Codex rules'
    "$CODEX_RULES_SYNC" --quiet "$CODEX_RULES_PORTABLE" \
        "$HOME/.codex/rules/portable.rules"
fi
if [[ "$SYNC_CODEX_INSTRUCTIONS" == 1 ]]; then
    dotfiles_log step 'Synchronizing host Codex instructions'
    sync_codex_instructions
fi
if [[ "$SYNC_CLAUDE" == 1 ]]; then
    dotfiles_log step 'Synchronizing portable Claude settings'
    "$CLAUDE_SYNC" --quiet "$CLAUDE_PORTABLE" "$HOME/.claude/settings.json"
fi
# fcitx5 rewrites its profile at runtime, so this is a regular file, not a link.
if [[ "$SYNC_FCITX5" == 1 ]]; then
    dotfiles_log step 'Synchronizing fcitx5 profile'
    "$FCITX5_SYNC" "$FCITX5_PORTABLE" "$HOME/.config/fcitx5/profile"
fi
# Remove the obsolete repository-local filter from the previous layout.
if git config --local --get-regexp '^filter\.codex-portable\.' >/dev/null 2>&1; then
    git config --local --remove-section filter.codex-portable
fi

dotfiles_log step 'Stowing common packages:'
if [[ -n "$COMMON_PKGS" ]]; then
    dotfiles_log info "Packages: ${COMMON_PKGS//$'\n'/ }"
    # shellcheck disable=SC2086
    stow --restow --no-folding -d "$COMMON_DIR" $COMMON_PKGS
fi

if [[ -n "$HOST" ]]; then
    dotfiles_log step 'Stowing host-specific packages:'
    if [[ -n "$HOST_PKGS" ]]; then
        dotfiles_log info "Packages: ${HOST_PKGS//$'\n'/ }"
        # shellcheck disable=SC2086
        stow --restow --no-folding -d "$HOST_DIR" $HOST_PKGS
    fi
fi

# Lock down SSH config permissions
# sshd requires 600 on config files and 700 on ~/.ssh; stow preserves repo
# modes through symlinks, so we re-assert them on every restow. `readlink -f`
# canonicalizes both regular files and (chained) symlinks, so chmod always
# lands on the actual tracked file on Linux and macOS alike. Dangling optional
# snippets are skipped even when they are last in the glob order.
if [[ -d "$HOME/.ssh" ]]; then
    chmod 700 "$HOME/.ssh"
    if [[ -e "$HOME/.ssh/config" ]]; then
        target="$(readlink -f "$HOME/.ssh/config" 2>/dev/null || true)"
        if [[ -f "$target" ]]; then
            chmod 600 "$target"
        fi
    fi
    if [[ -d "$HOME/.ssh/config.d" ]]; then
        chmod 700 "$HOME/.ssh/config.d"
        (
            shopt -s nullglob
            for conf in "$HOME"/.ssh/config.d/*.conf; do
                target="$(readlink -f "$conf" 2>/dev/null || true)"
                if [[ -f "$target" ]]; then
                    chmod 600 "$target"
                fi
            done
        )
    fi
fi

# Record only complete installs. A dirty manual setup still remembers the host,
# but cannot claim that the committed HEAD was applied without local changes.
# Neither can a skipped Codex instructions sync: an uninitialized submodule
# looks clean to git status, and an empty HEAD makes the login updater run
# git submodule update --init --recursive and restow at the next login.
# Git resolves this outside the tracked tree and supports linked worktrees.
if SYNC_STATE=$(git rev-parse --git-path dotfiles-sync-unix 2>/dev/null); then
    APPLIED_HEAD=$(git rev-parse HEAD)
    SYNC_STATUS=$(git status --porcelain --untracked-files=normal --ignore-submodules=none)
    if [[ -n "$SYNC_STATUS" || "$APPLIED_HEAD" != "$START_HEAD" || "$CODEX_INSTRUCTIONS_SKIPPED" == 1 ]]; then
        APPLIED_HEAD=
    fi
    (
        umask 077
        STATE_TMP=$(mktemp "${SYNC_STATE}.XXXXXX")
        trap 'rm -f "$STATE_TMP"' EXIT
        printf '%s\n' "$HOME" "$(uname -s)" "$HOST" "$APPLIED_HEAD" >"$STATE_TMP"
        mv -f "$STATE_TMP" "$SYNC_STATE"
    )
fi

dotfiles_log ok "Stow completed (${HOST:-common-only}); open a new shell to load updated config."
