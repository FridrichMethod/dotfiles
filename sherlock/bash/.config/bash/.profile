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

# Cache
export APPTAINER_CACHEDIR="$SCRATCH/apptainercache"
export CCACHE_DIR="$SCRATCH/.cache/ccache"
export CCACHE_TEMPDIR="$SCRATCH/.cache/ccache/tmp"
export CONDA_PKGS_DIRS="$SCRATCH/.cache/conda/pkgs"
export CUDA_CACHE_PATH="$SCRATCH/.cache/nv/ComputeCache"
export CUPY_CACHE_DIR="$SCRATCH/.cache/cupy/kernel_cache"
export HF_DATASETS_CACHE="$SCRATCH/.cache/huggingface/datasets"
export HF_HOME="$SCRATCH/.cache/huggingface"
export HF_HUB_CACHE="$SCRATCH/.cache/huggingface/hub"
export PIP_CACHE_DIR="$SCRATCH/.cache/pip"
export TEMP="$SCRATCH/.tmp"
export TMP="$SCRATCH/.tmp"
export TMPDIR="$SCRATCH/.tmp"
export TORCHINDUCTOR_CACHE_DIR="$SCRATCH/.cache/torchinductor"
export TORCH_EXTENSIONS_DIR="$SCRATCH/.cache/torch_extensions"
export TORCH_HOME="$SCRATCH/.cache/torch"
export TRITON_CACHE_DIR="$SCRATCH/.cache/triton"
export UV_CACHE_DIR="$SCRATCH/.cache/uv"
export XDG_CACHE_HOME="$SCRATCH/.cache"
