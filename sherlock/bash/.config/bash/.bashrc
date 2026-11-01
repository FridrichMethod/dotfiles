#!/bin/bash

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$("$HOME/miniconda3/bin/conda" 'shell.bash' 'hook' 2>/dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
        . "$HOME/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="$HOME/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# shfmt: off
# >>> mamba initialize >>>
# !! Contents within this block are managed by 'micromamba shell init' !!
export MAMBA_EXE="$HOME/.local/bin/micromamba"
export MAMBA_ROOT_PREFIX="$HOME/micromamba"
__mamba_setup="$("$MAMBA_EXE" shell hook --shell bash --root-prefix "$MAMBA_ROOT_PREFIX" 2>/dev/null)"
if [ $? -eq 0 ]; then
    eval "$__mamba_setup"
else
    alias micromamba='"$MAMBA_EXE"' # Fallback on help from micromamba activate
fi
unset __mamba_setup
# <<< mamba initialize <<<
# shfmt: on

# Auto-load Lmod dev toolchain + Node.js LTS (gcc, cmake, make, cuda, openmpi, node/npm).
# Python is intentionally left to conda/mamba, not a module.
# NOTE: openmpi/5.0.5 is built against gcc/12.4.0 + cuda/12.6.1 and will pin those versions;
# do not bump gcc/cuda here while openmpi is loaded. Use `ml spider <name>` for versions.
if command -v ml >/dev/null 2>&1; then
    ml gcc/12.4.0 cmake/3.31.4 make/4.4 cuda/12.6.1 openmpi/5.0.5 nodejs/24.13.0 2>/dev/null
fi
