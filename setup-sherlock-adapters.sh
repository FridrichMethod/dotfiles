#!/bin/sh
# Explicit first-party adapter delivery; no registration or trust bypass.
set -eu
setup_root=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)
setup_python=${SHERLOCK_KIT_SETUP_PYTHON:-python3}
exec "$setup_python" -I -B "$setup_root/lib/sherlock_kit_integration.py" --install-adapters "$@"
