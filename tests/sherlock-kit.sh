#!/bin/sh
set -eu

# Hermetic: the provisioning exports (DOTFILES_AUTO_UPDATE=0 and the like,
# docs/bootstrap.md) and other dotfiles knobs never reach the code under
# test from the caller; each case sets what it needs.
unset DOTFILES_AUTO_UPDATE DOTFILES_AUTO_STOW DOTFILES_HOST DOTFILES_DIR _DOTFILES_CHECKED \
    DOTFILES_STOW_WITHOUT_OH_MY_ZSH DOTFILES_COLOR AWESOME_SKILLS_AUTO_UPDATE AWESOME_SKILLS_FORCE \
    AWESOME_SKILLS_BG AWESOME_SKILLS_INSTALLER_URL AWESOME_SKILLS_REFRESH_DAYS _AWESOME_SKILLS_CHECKED

test_root=$(CDPATH='' cd -P -- "$(dirname -- "$0")/.." && pwd)
test_python=${DOTFILES_SYNC_PYTHON:-python3}
"$test_python" -I -B -m unittest discover -s "$test_root/tests" -p test_sherlock_kit_integration.py -v
"$test_python" -I -B "$test_root/lib/sherlock_kit_integration.py" --check
