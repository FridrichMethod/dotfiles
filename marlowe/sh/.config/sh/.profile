#!/bin/sh

# Scratch
export PROJECT_ID=m000191
export PROJECTS=/projects/$PROJECT_ID
export SCRATCH=/scratch/$PROJECT_ID

# Cache
export APPTAINER_CACHEDIR="$SCRATCH/apptainercache/$USER"
export CCACHE_DIR="$SCRATCH/.cache/ccache/$USER"
export CCACHE_TEMPDIR="$SCRATCH/.cache/ccache/tmp/$USER"
export CONDA_PKGS_DIRS="$SCRATCH/.cache/conda/pkgs/$USER"
export CUDA_CACHE_PATH="$SCRATCH/.cache/nv/ComputeCache/$USER"
export CUPY_CACHE_DIR="$SCRATCH/.cache/cupy/kernel_cache/$USER"
export GITSTATUS_CACHE_DIR="$SCRATCH/.cache/gitstatus/$USER"
export HF_DATASETS_CACHE="$SCRATCH/.cache/huggingface/datasets/$USER"
export HF_HOME="$SCRATCH/.cache/huggingface/$USER"
export HF_HUB_CACHE="$SCRATCH/.cache/huggingface/hub/$USER"
export PIP_CACHE_DIR="$SCRATCH/.cache/pip/$USER"
export TEMP="$SCRATCH/.tmp/$USER"
export TMP="$SCRATCH/.tmp/$USER"
export TMPDIR="$SCRATCH/.tmp/$USER"
export TORCHINDUCTOR_CACHE_DIR="$SCRATCH/.cache/torchinductor/$USER"
export TORCH_EXTENSIONS_DIR="$SCRATCH/.cache/torch_extensions/$USER"
export TORCH_HOME="$SCRATCH/.cache/torch/$USER"
export TRITON_CACHE_DIR="$SCRATCH/.cache/triton/$USER"
export UV_CACHE_DIR="$SCRATCH/.cache/uv/$USER"
export XDG_CACHE_HOME="$SCRATCH/.cache/$USER"

# Ensure cache/temp dirs exist
for dir in \
  "$APPTAINER_CACHEDIR" \
  "$CCACHE_DIR" \
  "$CCACHE_TEMPDIR" \
  "$CONDA_PKGS_DIRS" \
  "$CUDA_CACHE_PATH" \
  "$CUPY_CACHE_DIR" \
  "$GITSTATUS_CACHE_DIR" \
  "$HF_DATASETS_CACHE" \
  "$HF_HOME" \
  "$HF_HUB_CACHE" \
  "$PIP_CACHE_DIR" \
  "$TEMP" \
  "$TMP" \
  "$TMPDIR" \
  "$TORCHINDUCTOR_CACHE_DIR" \
  "$TORCH_EXTENSIONS_DIR" \
  "$TORCH_HOME" \
  "$TRITON_CACHE_DIR" \
  "$UV_CACHE_DIR" \
  "$XDG_CACHE_HOME"
do
  if [ -n "$dir" ] && [ ! -d "$dir" ]; then
    mkdir -p "$dir"
  fi
done
