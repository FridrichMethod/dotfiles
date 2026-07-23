#!/bin/zsh

# Initialize Lmod module system for zsh.
# Bash gets this from /etc/profile → /etc/profile.d/*.sh, but zsh
# does not source /etc/profile so the `module` function is undefined.
if (( ! $+functions[module] )) && [[ -f "$LMOD_DIR/../init/zsh" ]]; then
    source "$LMOD_DIR/../init/zsh"
fi

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/home/users/zyli2002/miniconda3/bin/conda' 'shell.zsh' 'hook' 2>/dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/home/users/zyli2002/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/home/users/zyli2002/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/home/users/zyli2002/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# shfmt: off
# >>> mamba initialize >>>
# !! Contents within this block are managed by 'micromamba shell init' !!
export MAMBA_EXE='/home/users/zyli2002/.local/bin/micromamba';
export MAMBA_ROOT_PREFIX='/home/users/zyli2002/micromamba';
__mamba_setup="$("$MAMBA_EXE" shell hook --shell zsh --root-prefix "$MAMBA_ROOT_PREFIX" 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__mamba_setup"
else
    alias micromamba="$MAMBA_EXE"  # Fallback on help from micromamba activate
fi
unset __mamba_setup
# <<< mamba initialize <<<
# shfmt: on

export PATH="$MAMBA_ROOT_PREFIX/envs/login/bin:$PATH"

# Auto-load Lmod dev toolchain + Node.js LTS (gcc, cmake, make, cuda, openmpi, node/npm).
# Python is intentionally left to conda/mamba, not a module.
# NOTE: openmpi/5.0.5 is built against gcc/12.4.0 + cuda/12.6.1 and will pin those versions;
# do not bump gcc/cuda here while openmpi is loaded. Use `ml spider <name>` for versions.
if command -v ml >/dev/null 2>&1; then
    ml gcc/12.4.0 cmake/3.31.4 make/4.4 cuda/12.6.1 openmpi/5.0.5 nodejs/24.13.0 2>/dev/null
fi
