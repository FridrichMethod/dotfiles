#!/bin/sh

# This command sets the DYLD_LIBRARY_PATH environment variable.
# The DYLD_LIBRARY_PATH is used by the dynamic linker on macOS to find dynamic libraries (.dylib files) at runtime.
if [ -z "$DYLD_LIBRARY_PATH" ]; then
    export DYLD_LIBRARY_PATH=/opt/homebrew/lib
else
    export DYLD_LIBRARY_PATH=/opt/homebrew/lib:"$DYLD_LIBRARY_PATH"
fi

# MATLAB setup
export MATLAB=/Applications/MATLAB_R2025b.app/bin

# Schrodinger suite setup
export SCHRODINGER=/opt/schrodinger/suites2025-2
