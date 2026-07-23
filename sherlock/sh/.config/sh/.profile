#!/bin/sh

# Scratch groups
export ALICE=/scratch/groups/ayting
export BRIAN=/scratch/groups/btrippe
export MICHAEL=/scratch/groups/mzlin
export POSSU=/scratch/groups/possu

# Home groups
export ALICE_HOME=/home/groups/ayting
export BRIAN_HOME=/home/groups/btrippe
export MICHAEL_HOME=/home/groups/mzlin
export POSSU_HOME=/home/groups/possu

# User tool environment
case ":$PATH:" in
    *":$HOME/micromamba/envs/login/bin:"*) ;;
    *) export PATH="$HOME/micromamba/envs/login/bin:$PATH" ;;
esac

# Cache
if [ -n "$SCRATCH" ]; then
    export APPTAINER_CACHEDIR="$SCRATCH/.cache/apptainercache"
    export APPTAINER_TMPDIR="$SCRATCH/.cache/apptainertmp"
    export CCACHE_DIR="$SCRATCH/.cache/ccache"
    export CCACHE_TEMPDIR="$SCRATCH/.cache/ccache/tmp"
    export CONDA_PKGS_DIRS="$SCRATCH/.cache/conda/pkgs"
    export CUDA_CACHE_PATH="$SCRATCH/.cache/nv/ComputeCache"
    export CUPY_CACHE_DIR="$SCRATCH/.cache/cupy/kernel_cache"
    export GITSTATUS_CACHE_DIR="$SCRATCH/.cache/gitstatus"
    export HF_DATASETS_CACHE="$SCRATCH/.cache/huggingface/datasets"
    export HF_HOME="$SCRATCH/.cache/huggingface"
    export HF_HUB_CACHE="$SCRATCH/.cache/huggingface/hub"
    export NPM_CONFIG_CACHE="$SCRATCH/.cache/npm"
    export PIP_CACHE_DIR="$SCRATCH/.cache/pip"
    export TORCHINDUCTOR_CACHE_DIR="$SCRATCH/.cache/torchinductor"
    export TORCH_EXTENSIONS_DIR="$SCRATCH/.cache/torch_extensions"
    export TORCH_HOME="$SCRATCH/.cache/torch"
    export TRITON_CACHE_DIR="$SCRATCH/.cache/triton"
    export UV_CACHE_DIR="$SCRATCH/.cache/uv"
    export XDG_CACHE_HOME="$SCRATCH/.cache"

    export CARGO_HOME="$SCRATCH/.cargo"
    export GOMODCACHE="$SCRATCH/.cache/go/mod"
    export GOPATH="$SCRATCH/.cache/go/path"

    # Ensure cache/temp dirs exist
    for dir in \
        "$APPTAINER_CACHEDIR" \
        "$APPTAINER_TMPDIR" \
        "$CARGO_HOME" \
        "$CCACHE_DIR" \
        "$CCACHE_TEMPDIR" \
        "$CONDA_PKGS_DIRS" \
        "$CUDA_CACHE_PATH" \
        "$CUPY_CACHE_DIR" \
        "$GITSTATUS_CACHE_DIR" \
        "$GOMODCACHE" \
        "$GOPATH" \
        "$HF_DATASETS_CACHE" \
        "$HF_HOME" \
        "$HF_HUB_CACHE" \
        "$NPM_CONFIG_CACHE" \
        "$PIP_CACHE_DIR" \
        "$TORCHINDUCTOR_CACHE_DIR" \
        "$TORCH_EXTENSIONS_DIR" \
        "$TORCH_HOME" \
        "$TRITON_CACHE_DIR" \
        "$UV_CACHE_DIR" \
        "$XDG_CACHE_HOME"; do
        if [ -n "$dir" ] && [ ! -d "$dir" ]; then
            mkdir -p "$dir"
        fi
    done
fi

# npm global installs. The nodejs module's default prefix is its read-only shared
# software dir, so `npm install -g` fails there. Point it at ~/.local, which
# common/sh/.profile already puts on PATH (binaries land in ~/.local/bin).
export NPM_CONFIG_PREFIX="$HOME/.local"
