#!/bin/bash

set -euo pipefail

# Usage: ./stow-all.sh <host-dir>
# Example: ./stow-all.sh wsl-ubuntu
HOST="${1:-}"
if [[ -z "$HOST" ]]; then
  echo "Usage: $0 <host-dir>   (e.g., mac | ubuntu | wsl-ubuntu | lab-ubuntu)" >&2
  exit 2
fi

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
echo "Stowing from $REPO_ROOT"

COMMON_DIR="${REPO_ROOT}/common"
HOST_DIR="${REPO_ROOT}/${HOST}"

if [[ ! -d "$COMMON_DIR" ]]; then
  echo "ERROR: missing common dir: $COMMON_DIR" >&2
  exit 1
fi
if [[ ! -d "$HOST_DIR" ]]; then
  echo "ERROR: host dir not found: $HOST_DIR" >&2
  exit 1
fi

cd "$REPO_ROOT" # ensures ./.stowrc is picked up

echo "Stowing common packages:"
# shellcheck disable=SC2046
stow -d "$COMMON_DIR" $(basename -a "${COMMON_DIR}"/*/)

echo "Stowing host-specific packages:"
# shellcheck disable=SC2046
stow -d "$HOST_DIR" $(basename -a "${HOST_DIR}"/*/)
