# Marlowe stand-in for the e2e suite: Ubuntu 24.04 with Ubuntu's lmod
# package, as a login node has it, the baseline tools such a node ships
# (git, curl, locales with en_US.UTF-8 generated, man-db, bsdextrautils for
# `column`, ssh, ca-certificates), no sudo package at all (the denying
# wrapper stands in its place), a user under /users whose home holds
# /etc/skel's .bashrc and .profile, a writable /scratch/m000191 (where the
# marlowe overlay points SCRATCH), and docker/site/marlowe.sh in
# /etc/profile.d, which exports nothing. /etc/profile.d/lmod.sh exports
# LMOD_DIR for every login shell, which setup-host requires on a cluster
# host, and /usr/share/lmod/lmod/init/zsh is what the marlowe zsh rc sources.
# Build context is tests/e2e/; tests/e2e/run.sh passes E2E_USER and E2E_HOME
# from the host's env file and E2E_UID=$(id -u), so the user owns the
# /e2e/out it mounts.
FROM ubuntu:24.04

ARG E2E_USER
ARG E2E_UID
ARG E2E_HOME

RUN DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        lmod git curl locales man-db bsdextrautils openssh-client ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8

# The image's own `ubuntu` account (uid 1000) is not on a cluster and would
# collide with a build uid of 1000. ~/.cache and $SCRATCH/.cache/conda/pkgs
# exist so that a --cache run's bind mounts under them do not leave
# root-owned parents the bootstrap and the stowed overlay (XDG_CACHE_HOME
# under $SCRATCH) could not write in; /e2e/out is where run.sh mounts the
# run's output.
RUN if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi \
    && mkdir -p "$(dirname "$E2E_HOME")" \
    && useradd -m -d "$E2E_HOME" -u "$E2E_UID" -s /bin/bash "$E2E_USER" \
    && install -d -m 700 "$E2E_HOME/.cache" \
    && install -d /scratch/m000191/.cache/conda/pkgs \
    && chown -R "$E2E_USER:" "$E2E_HOME/.cache" /scratch/m000191 \
    && mkdir -p /e2e/src /e2e/out \
    && chown "$E2E_USER:" /e2e/out

# Ubuntu's /etc/profile leaves USER and LOGNAME to login(1); docker/site/login.sh
# sets them for the login shells the harness starts (the overlay's cache
# paths end in $USER).
COPY docker/site/login.sh /etc/profile.d/e2e-login.sh
COPY docker/site/marlowe.sh /etc/profile.d/e2e-site.sh
COPY wrappers/sudo-deny /usr/local/bin/sudo
COPY wrappers/chsh wrappers/stow /usr/local/bin/
RUN chmod 644 /etc/profile.d/e2e-login.sh /etc/profile.d/e2e-site.sh \
    && chmod 755 /usr/local/bin/sudo /usr/local/bin/chsh /usr/local/bin/stow
