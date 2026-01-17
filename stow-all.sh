#!/bin/bash

set -euo pipefail

# Usage: ./stow-all.sh <host-dir>
# Example: ./stow-all.sh wsl-ubuntu
HOST="${1:-}"
if [[ -z "$HOST" ]]; then
  echo "Usage: $0 <host-dir>   (e.g., ubuntu | wsl-ubuntu | mac | lab-ubuntu)" >&2
  exit 2
fi

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
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

list_pkgs() {
  # Stow packages are direct subdirectories of the stow directory;
  # package names cannot contain '/'.
  find "$1" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
}

cd "$REPO_ROOT" # ensures ./.stowrc is picked up

mapfile -t COMMON_PKGS < <(list_pkgs "$COMMON_DIR")
mapfile -t HOST_PKGS < <(list_pkgs "$HOST_DIR")

# Common packages (installed on every machine)
echo "Stowing common packages: ${COMMON_PKGS[*]}"
stow -d "$COMMON_DIR" "${COMMON_PKGS[@]}"

# Host-specific packages
echo "Stowing host-specific packages: ${HOST_PKGS[*]}"
stow -d "$HOST_DIR" "${HOST_PKGS[@]}"
