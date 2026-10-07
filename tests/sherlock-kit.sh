#!/bin/sh
set -eu
test_root=$(CDPATH='' cd -P -- "$(dirname -- "$0")/.." && pwd)
test_python=${DOTFILES_SYNC_PYTHON:-python3}
"$test_python" -I -B -m unittest discover -s "$test_root/tests" -p test_sherlock_kit_integration.py -v
"$test_python" -I -B "$test_root/lib/sherlock_kit_integration.py" --check
