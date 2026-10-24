#!/bin/bash

set -euo pipefail

# Usage: ./stow-all.sh [host-dir]
# Example: ./stow-all.sh wsl-ubuntu
# If no host-dir is provided, only stow common.
# Successful setup remembers this home/platform/host for automatic login stow.
# DOTFILES_AUTO_STOW=0 disables automatic stow in the login updater.
# The claude package syncs Claude's defaults, whose hooks and status line run
# coding-agent-kit's Node helpers from ~/.claude/coding-agent-kit/ (Node.js 22+
# must be on PATH when Claude runs them).
# Day-zero prerequisites come from ./setup-host.sh and are checked by ./doctor.sh.
# It refuses to stow the zsh package before oh-my-zsh is cloned, since Stow
# would create a real ~/.oh-my-zsh/custom that blocks the clone
# (DOTFILES_STOW_WITHOUT_OH_MY_ZSH=1 stows anyway), and stops before the AI
# sync helpers write anything when a Stow dry run finds a conflicting file.
# Run ./setup-sync.sh once per clone to provision the AI configuration parser.
# The payload repos (coding-agent-kit, PyMOLScripts, awesome-skills) are not
# stowed: scripts/payload-update.sh installs them through their own
# installers. This script removes the links Stow made from their two former
# packages, each only while its text is exactly what Stow wrote.
# Retired Sherlock links and generated Codex overrides are removed only when
# their exact historical ownership is established; foreign files are preserved.

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
if [[ "$SYNC_CODEX" == 1 || "$SYNC_CLAUDE" == 1 ]]; then
    dotfiles_log step 'Checking selected AI configuration and runtime'
fi
if [[ "$SYNC_CODEX" == 1 ]]; then
    "$CODEX_SYNC" --quiet --check "$CODEX_PORTABLE" "$HOME/.codex/config.toml"
    "$CODEX_RULES_SYNC" --quiet --check "$CODEX_RULES_PORTABLE" \
        "$HOME/.codex/rules/portable.rules"
fi
if [[ "$SYNC_CLAUDE" == 1 ]]; then
    "$CLAUDE_SYNC" --quiet --check "$CLAUDE_PORTABLE" "$HOME/.claude/settings.json"
fi

# Retire only dangling links to exact deleted package sources. realpath resolves
# existing symlink ancestors but tolerates parents removed with the package.
# Foreign loops or inaccessible paths are preserved, never installation errors.
remove_retired_link() {
    local link=$HOME/$1
    [[ -L "$link" && ! -e "$link" ]] || return 0
    if ! python3 -I -B - "$link" "$REPO_PHYSICAL/$2" <<'PYTHON'
import os
import sys
try:
    link, source = sys.argv[1:]
    target = os.path.join(os.path.dirname(link), os.readlink(link))
    for path in (target, source):
        try:
            os.path.realpath(path, strict=True)
        except FileNotFoundError:
            pass
    resolved = os.path.realpath(target, strict=False)
    expected = os.path.realpath(source, strict=False)
    # realpath(strict=False) leaves a loop unresolved; never claim its ownership.
    if resolved != expected or os.path.islink(resolved):
        sys.exit(1)
except (OSError, ValueError):
    sys.exit(1)
PYTHON
    then
        return 0
    fi
    rm -f -- "$link"
    dotfiles_log info "Removed retired link $link (its source $2 was deleted)"
}
REPO_PHYSICAL=$(pwd -P)
remove_retired_link .local/bin/shk common/codex/.local/bin/shk
remove_retired_link .local/bin/codex-instructions-sync common/codex/.local/bin/codex-instructions-sync
for retired_host in lab-ubuntu wsl-ubuntu sherlock; do
    for retired_path in .claude/rules/sherlock-kit.md .claude/skills/sherlock-kit .agents/skills/sherlock-kit .local/bin/shk; do
        remove_retired_link "$retired_path" "$retired_host/sherlock-kit/$retired_path"
    done
done

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

# Every link Stow made from the two packages that the payload repos replaced,
# by package: their own installers now own these paths (the kit's refuses a
# foreign link at its launcher and completion paths), and ~/.claude/dotfiles,
# the old home of the Claude helpers, is no longer read. A path is removed only
# while it is a symlink whose text is exactly the one Stow wrote for it from
# this checkout's common/, dangling or not: Stow links to the physical stow
# directory, relative to the physical target, through one ../ per directory
# below it. A file, a directory or any other link stays, and so does each
# parent directory but the four that only these packages filled, which go
# once empty. This runs only after both stows succeeded, so a refused dry run
# or a failed stow leaves them in place; a failed removal stops the install
# unrecorded.
RETIRED_PACKAGE_LINKS='coding-agent-kit .claude/dotfiles/check-git-hooks.cjs
coding-agent-kit .claude/dotfiles/notify.cjs
coding-agent-kit .claude/dotfiles/statusline.cjs
coding-agent-kit .local/bin/claude-as
coding-agent-kit .local/bin/codex-as
coding-agent-kit .local/lib/claude-as/launch.py
coding-agent-kit .local/lib/codex-as/check.py
coding-agent-kit .local/lib/codex-as/handoff.py
coding-agent-kit .local/lib/codex-as/launch.py
coding-agent-kit .local/lib/codex-as/layout.py
coding-agent-kit .local/share/bash-completion/completions/claude-as
coding-agent-kit .local/share/bash-completion/completions/codex-as
coding-agent-kit .oh-my-zsh/custom/completions/_claude-as
coding-agent-kit .oh-my-zsh/custom/completions/_codex-as
pymol .pymolrc
pymol .pymolrc.py'
STOW_PATH=$(python3 -I -B -c 'import os, sys; print(os.path.relpath(*map(os.path.realpath, sys.argv[1:])))' \
    "$COMMON_DIR" "$HOME")
while read -r retired_package retired_path; do
    retired_link=$HOME/$retired_path
    [[ -L "$retired_link" ]] || continue
    retired_up=${retired_path//[!\/]/}
    retired_text="${retired_up//\//../}$STOW_PATH/$retired_package/$retired_path"
    [[ "$(readlink -- "$retired_link")" == "$retired_text" ]] || continue
    rm -f -- "$retired_link"
    dotfiles_log info "Removed $retired_link, a link Stow made from the retired $retired_package package"
done <<<"$RETIRED_PACKAGE_LINKS"
for retired_dir in .claude/dotfiles .local/lib/claude-as .local/lib/codex-as .oh-my-zsh/custom/completions; do
    if [[ -d "$HOME/$retired_dir" && ! -L "$HOME/$retired_dir" ]]; then
        rmdir -- "$HOME/$retired_dir" 2>/dev/null || true
    fi
done

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

# Codex gives AGENTS.override.md precedence over AGENTS.md. Retire only the
# exact generated regular file after Stow and SSH permission handling succeed,
# immediately before applied-state recording.
# lstat and O_NOFOLLOW/O_NONBLOCK keep symlinks and FIFOs out of the read path.
python3 -I -B - "$HOME/.codex/AGENTS.override.md" <<'PYTHON'
import os
import stat
import sys
path = sys.argv[1]
marker = b"<!-- Generated by dotfiles codex-instructions-sync. Edit common/codex/.codex/AGENTS.md or the host's sherlock-kit rules, then rerun stow-all.sh. -->"
def warn():
    print(f"stow-all: warning: left foreign {path} unchanged; Codex reads it instead of AGENTS.md; inspect and move it aside manually if obsolete", file=sys.stderr)
try:
    before = os.lstat(path)
except FileNotFoundError:
    sys.exit(0)
except OSError:
    warn()
    sys.exit(0)
if not stat.S_ISREG(before.st_mode):
    warn()
    sys.exit(0)
try:
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        opened = os.fstat(stream.fileno())
        owned = stat.S_ISREG(opened.st_mode) and stream.readline(len(marker) + 2).rstrip(b"\n") == marker
except OSError:
    warn()
    sys.exit(0)
if not owned:
    warn()
    sys.exit(0)
def identity(info):
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns
try:
    unchanged = identity(os.lstat(path)) == identity(before) == identity(opened)
except OSError:
    unchanged = False
if not unchanged:
    sys.exit(f"stow-all: retired override changed during inspection; retry: {path}")
try:
    os.unlink(path)
except OSError as exc:
    sys.exit(f"stow-all: cannot remove generated override {path}: {exc}")
PYTHON

# Record only complete installs. A dirty manual setup still remembers the host,
# but cannot claim that the committed HEAD was applied without local changes,
# and an empty HEAD makes the login updater restow at the next login.
# Git resolves this outside the tracked tree and supports linked worktrees.
if SYNC_STATE=$(git rev-parse --git-path dotfiles-sync-unix 2>/dev/null); then
    APPLIED_HEAD=$(git rev-parse HEAD)
    SYNC_STATUS=$(git status --porcelain --untracked-files=normal)
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

dotfiles_log ok "Stow completed (${HOST:-common-only}); open a new shell to load updated config."
