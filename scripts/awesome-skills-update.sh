#!/bin/sh
# Transition shim for scripts/payload-update.sh, which replaced the weekly
# awesome-skills hook. The login that pulls that change still runs the rc
# files it read before the pull, whose tails source this path, so this keeps
# that login converging: stow-all.sh retires the old kit and PyMOL links, and
# the payload hook installs their replacements in the same session. Remove it
# once every host has logged in since (docs/payloads.md, Migration).
_df_payload="${DOTFILES_DIR:-$HOME/dotfiles}/scripts/payload-update.sh"
if [ -r "$_df_payload" ]; then
    # shellcheck source=scripts/payload-update.sh
    . "$_df_payload"
fi
unset _df_payload
