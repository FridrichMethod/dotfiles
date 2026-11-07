#!/bin/bash

set -euo pipefail

# Isolate inherited configuration while preserving explicit test inputs.
# shellcheck source=tests/lib/environment.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/environment.sh"

# Reads the real checkout's tracked files with the caller's Git environment
# (a commit hook's index included); it creates no fixture repository.
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
python3 -I -B -m unittest discover -s "$TEST_DIR" -p 'test_repository_text.py' -v
echo "repository-text=PASS"
