#!/bin/sh

# Fresh Bash sessions need Homebrew before the interactive shell plugins load.
# Only the two supported macOS installer prefixes are probed.
if ! command -v brew >/dev/null 2>&1; then
    for _mac_brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [ -x "$_mac_brew" ] || continue
        # The shared profile already selected nvm's default. Keep it first,
        # while letting native shellenv place Homebrew ahead of system tools.
        _mac_node_bin=
        case ${PATH%%:*} in
            "${NVM_DIR:-$HOME/.nvm}"/versions/node/*/bin)
                _mac_node_bin=${PATH%%:*}
                PATH=${PATH#*:}
                ;;
        esac
        eval "$("$_mac_brew" shellenv)"
        [ -z "$_mac_node_bin" ] || export PATH="$_mac_node_bin:$PATH"
        break
    done
    unset _mac_brew _mac_node_bin
fi

# This command sets the DYLD_LIBRARY_PATH environment variable.
# The DYLD_LIBRARY_PATH is used by the dynamic linker on macOS to find dynamic libraries (.dylib files) at runtime.
case ":${DYLD_LIBRARY_PATH-}:" in
    *:/opt/homebrew/lib:*) ;;
    *) export DYLD_LIBRARY_PATH="/opt/homebrew/lib${DYLD_LIBRARY_PATH:+:${DYLD_LIBRARY_PATH}}" ;;
esac

# MATLAB setup
if [ -d /Applications/MATLAB_R2025b.app/bin ]; then
    export MATLAB=/Applications/MATLAB_R2025b.app/bin
fi

# Schrodinger suite setup
if [ -d /opt/schrodinger/suites2025-2 ]; then
    export SCHRODINGER=/opt/schrodinger/suites2025-2
fi
