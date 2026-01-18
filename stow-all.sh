#!/bin/bash

set -euo pipefail

# Usage: ./stow-all.sh [host-dir]
# Example: ./stow-all.sh wsl-ubuntu
# If no host-dir is provided, only stow common.
HOST="${1:-}"

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

echo "Stowing common packages:"
if compgen -G "${COMMON_DIR}"'/*/' >/dev/null; then
    common_pkgs=$(basename -a "${COMMON_DIR}"/*/)
    # shellcheck disable=SC2086
    echo $common_pkgs
    # shellcheck disable=SC2086
    stow --restow -d "$COMMON_DIR" $common_pkgs
fi

if [[ -n "$HOST" ]]; then
    echo "Stowing host-specific packages:"
    if compgen -G "${HOST_DIR}"'/*/' >/dev/null; then
        host_pkgs=$(basename -a "${HOST_DIR}"/*/)
        # shellcheck disable=SC2086
        echo $host_pkgs
        # shellcheck disable=SC2086
        stow --restow -d "$HOST_DIR" $host_pkgs
    fi
fi
