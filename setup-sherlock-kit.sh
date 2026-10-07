#!/bin/sh
# Explicit frozen toolkit install. Stow, profiles and updates never call this.
set -eu
setup_root=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)
setup_python=${SHERLOCK_KIT_SETUP_PYTHON:-python3}
exec "$setup_python" -I -B "$setup_root/lib/sherlock_kit_integration.py" --install "$@"
