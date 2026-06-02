#!/bin/sh

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
