# shellcheck shell=sh
# Fake Sherlock site environment for the e2e image: rocky-lmod.Dockerfile
# installs this file as /etc/profile.d/e2e-site.sh, so every login shell
# (bash -l; zsh through Rocky's /etc/zprofile) sees what the site's own
# profile.d exports on a real login node. The sherlock overlay's rc files
# read SCRATCH for the caches they move out of the home quota, and the
# harness expands $SCRATCH in E2E_ALLOC_ENV (CONDA_PKGS_DIRS). The image
# creates these directories writable by the user. Lmod's own z00_lmod.sh
# provides LMOD_DIR. USER is unset under `docker run -u`; Rocky's
# /etc/profile sets it from id before profile.d runs, and this falls back
# the same way. POSIX sh: /etc/profile.d files are sourced by sh and ksh
# emulation too.
if [ -z "${USER:-}" ]; then
    USER=$(id -un)
    export USER
fi
export SCRATCH=/scratch/users/$USER
export GROUP_HOME=/home/groups/e2e
export GROUP_SCRATCH=/scratch/groups/e2e
export L_SCRATCH=/tmp
