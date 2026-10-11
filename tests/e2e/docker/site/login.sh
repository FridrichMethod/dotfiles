# shellcheck shell=sh
# What login(1), sshd and the desktop session export on a real machine and
# `docker run -u` does not: USER and LOGNAME. Rocky's and Fedora's
# /etc/profile set them from id themselves; Ubuntu's never does, so
# ubuntu.Dockerfile and ubuntu-lmod.Dockerfile install this file as
# /etc/profile.d/e2e-login.sh. The marlowe overlay puts $USER in its cache
# paths and the harness expands $USER in E2E_ALLOC_ENV. POSIX sh:
# /etc/profile.d files are sourced by sh too.
if [ -z "${USER:-}" ]; then
    USER=$(id -un)
    export USER
fi
if [ -z "${LOGNAME:-}" ]; then
    LOGNAME=$USER
    export LOGNAME
fi
