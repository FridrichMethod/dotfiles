#!/bin/bash

set -euo pipefail

# Usage: ./stow-all.sh [host-dir]
# Example: ./stow-all.sh wsl-ubuntu
# If no host-dir is provided, only stow common.
# Successful setup remembers this home/platform/host for automatic login stow.
# DOTFILES_AUTO_STOW=0 disables automatic stow in the login updater.
# The common Claude package links local Node helpers and syncs its defaults;
# Node.js 18+ must be on PATH when Claude runs the hooks and status line.
# Run ./setup-sync.sh once per clone to provision the AI configuration parser.
# All selected AI inputs are checked before any live configuration is changed.
# The win host is installed from Windows by stow-all.ps1, not from here.
HOST="${1:-}"

if [[ "$HOST" == "win" ]]; then
    echo "ERROR: the 'win' host is installed from Windows, not from POSIX." >&2
    echo "       Its packages mirror Windows-only paths (Documents\\PowerShell," >&2
    echo "       AppData\\Local\\Packages) that mean nothing in a POSIX \$HOME." >&2
    echo "       Run this in PowerShell from the repo root instead:" >&2
    echo "         .\\stow-all.ps1 win" >&2
    exit 1
fi

case "$HOST" in
    common | .* | */* | *\\*)
        echo "ERROR: host must be a top-level host directory (or omitted for common-only)." >&2
        exit 1
        ;;
esac

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
echo "Stowing from $REPO_ROOT"

COMMON_DIR="${REPO_ROOT}/common"
HOST_DIR="${REPO_ROOT}/${HOST}"

if [[ ! -d "$COMMON_DIR" ]]; then
    echo "ERROR: missing common dir: $COMMON_DIR" >&2
    exit 1
fi
if [[ -n "$HOST" && ! -d "$HOST_DIR" ]]; then
    echo "ERROR: host dir not found: $HOST_DIR" >&2
    exit 1
fi

cd "$REPO_ROOT" # ensures ./.stowrc is picked up
START_HEAD=$(git rev-parse HEAD 2>/dev/null) || START_HEAD=

# A present package requires its materialized settings and executable helper.
# Stow ignores those settings files, so skipping a missing helper would leave
# stale live settings while falsely recording the entire HEAD as applied.
require_sync() {
    if [[ ! -f "$1" || ! -x "$1" ]]; then
        echo "ERROR: required sync helper is missing or not executable: $1" >&2
        exit 1
    fi
    if [[ ! -f "$2" || ! -r "$2" ]]; then
        echo "ERROR: required portable settings are missing or unreadable: $2" >&2
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

# Validate every selected package before any helper changes the live home.
SYNC_CODEX=0
if [[ -d "$COMMON_DIR/codex" || (-n "$HOST" && -d "$HOST_DIR/codex") ]]; then
    require_sync "$CODEX_SYNC" "$CODEX_PORTABLE"
    require_sync "$CODEX_RULES_SYNC" "$CODEX_RULES_PORTABLE"
    SYNC_CODEX=1
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

# Validate runtime dependencies and both documents for every selected AI
# helper. A malformed later baseline must not partially apply earlier ones.
# This is a read-only preflight, not a transaction across independent files.
if [[ "$SYNC_CODEX" == 1 ]]; then
    "$CODEX_SYNC" --check "$CODEX_PORTABLE" "$HOME/.codex/config.toml"
    "$CODEX_RULES_SYNC" --check "$CODEX_RULES_PORTABLE" \
        "$HOME/.codex/rules/portable.rules"
fi
if [[ "$SYNC_CLAUDE" == 1 ]]; then
    "$CLAUDE_SYNC" --check "$CLAUDE_PORTABLE" "$HOME/.claude/settings.json"
fi

if [[ "$SYNC_CODEX" == 1 ]]; then
    echo "Synchronizing portable Codex settings"
    "$CODEX_SYNC" "$CODEX_PORTABLE" "$HOME/.codex/config.toml"
    echo "Synchronizing portable Codex rules"
    "$CODEX_RULES_SYNC" "$CODEX_RULES_PORTABLE" \
        "$HOME/.codex/rules/portable.rules"
fi
if [[ "$SYNC_CLAUDE" == 1 ]]; then
    echo "Synchronizing portable Claude settings"
    "$CLAUDE_SYNC" "$CLAUDE_PORTABLE" "$HOME/.claude/settings.json"
fi
# fcitx5 rewrites its profile at runtime, so this is a regular file, not a link.
if [[ "$SYNC_FCITX5" == 1 ]]; then
    echo "Synchronizing fcitx5 profile"
    "$FCITX5_SYNC" "$FCITX5_PORTABLE" "$HOME/.config/fcitx5/profile"
fi
# Remove the obsolete repository-local filter from the previous layout.
if git config --local --get-regexp '^filter\.codex-portable\.' >/dev/null 2>&1; then
    git config --local --remove-section filter.codex-portable
fi

echo "Stowing common packages:"
if compgen -G "${COMMON_DIR}"'/*/' >/dev/null; then
    common_pkgs=$(basename -a "${COMMON_DIR}"/*/)
    # shellcheck disable=SC2086
    echo $common_pkgs
    # shellcheck disable=SC2086
    stow --restow --no-folding -d "$COMMON_DIR" $common_pkgs
fi

if [[ -n "$HOST" ]]; then
    echo "Stowing host-specific packages:"
    if compgen -G "${HOST_DIR}"'/*/' >/dev/null; then
        host_pkgs=$(basename -a "${HOST_DIR}"/*/)
        # shellcheck disable=SC2086
        echo $host_pkgs
        # shellcheck disable=SC2086
        stow --restow --no-folding -d "$HOST_DIR" $host_pkgs
    fi
fi

# Lock down SSH config permissions
# sshd requires 600 on config files and 700 on ~/.ssh; stow preserves repo
# modes through symlinks, so we re-assert them on every restow. `readlink -f`
# canonicalizes both regular files and (chained) symlinks, so chmod always
# lands on the actual tracked file on Linux and macOS alike.
if [[ -d "$HOME/.ssh" ]]; then
    chmod 700 "$HOME/.ssh"
    if [[ -e "$HOME/.ssh/config" ]]; then
        target="$(readlink -f "$HOME/.ssh/config" 2>/dev/null || true)"
        [[ -f "$target" ]] && chmod 600 "$target"
    fi
    if [[ -d "$HOME/.ssh/config.d" ]]; then
        chmod 700 "$HOME/.ssh/config.d"
        (
            shopt -s nullglob
            for conf in "$HOME"/.ssh/config.d/*.conf; do
                target="$(readlink -f "$conf" 2>/dev/null || true)"
                [[ -f "$target" ]] && chmod 600 "$target"
            done
        )
    fi
fi

# Record only complete installs. A dirty manual setup still remembers the host,
# but cannot claim that the committed HEAD was applied without local changes.
# Git resolves this outside the tracked tree and supports linked worktrees.
if SYNC_STATE=$(git rev-parse --git-path dotfiles-sync-unix 2>/dev/null); then
    APPLIED_HEAD=$(git rev-parse HEAD)
    SYNC_STATUS=$(git status --porcelain --untracked-files=normal --ignore-submodules=none)
    if [[ -n "$SYNC_STATUS" || "$APPLIED_HEAD" != "$START_HEAD" ]]; then
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
