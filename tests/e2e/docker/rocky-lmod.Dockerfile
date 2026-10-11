# Sherlock stand-in for the e2e suite: Rocky Linux 9 with Lmod from EPEL, as
# a login node has it, the baseline tools a cluster image ships (git, curl,
# which, procps, findutils, tar, xz, bzip2, util-linux, man-db, ssh, the
# en_US locale), no sudo package at all (the denying wrapper stands in its
# place), a user under /home/users whose home holds /etc/skel's .bashrc and
# .bash_profile, a writable $SCRATCH, and the fake site environment of
# docker/site/sherlock.sh in /etc/profile.d. Lmod's own z00_lmod.sh exports
# LMOD_DIR for every login shell, which setup-host requires on a cluster
# host. Build context is tests/e2e/; tests/e2e/run.sh passes E2E_USER and
# E2E_HOME from the host's env file and E2E_UID=$(id -u), so the user owns
# the /e2e/out it mounts.
FROM quay.io/rockylinux/rockylinux:9

ARG E2E_USER
ARG E2E_UID
ARG E2E_HOME

# --allowerasing: the base image's curl-minimal conflicts with curl.
RUN dnf -y install epel-release \
    && dnf -y install --allowerasing \
        Lmod git curl which procps-ng findutils tar xz bzip2 util-linux man-db \
        openssh-clients glibc-langpack-en \
    && dnf clean all

# ~/.cache and $SCRATCH/.cache/conda/pkgs exist so that a --cache run's bind
# mounts under them do not leave root-owned parents the bootstrap and the
# stowed overlay (XDG_CACHE_HOME under $SCRATCH) could not write in. The
# group dirs are the ones docker/site/sherlock.sh names; /e2e/out is where
# run.sh mounts the run's output.
RUN mkdir -p "$(dirname "$E2E_HOME")" \
    && useradd -m -d "$E2E_HOME" -u "$E2E_UID" -s /bin/bash "$E2E_USER" \
    && install -d -m 700 "$E2E_HOME/.cache" \
    && install -d "/scratch/users/$E2E_USER/.cache/conda/pkgs" /home/groups/e2e /scratch/groups/e2e \
    && chown -R "$E2E_USER:" "$E2E_HOME/.cache" "/scratch/users/$E2E_USER" /home/groups/e2e /scratch/groups/e2e \
    && mkdir -p /e2e/src /e2e/out \
    && chown "$E2E_USER:" /e2e/out

COPY docker/site/sherlock.sh /etc/profile.d/e2e-site.sh
COPY wrappers/sudo-deny /usr/local/bin/sudo
COPY wrappers/chsh wrappers/stow /usr/local/bin/
RUN chmod 644 /etc/profile.d/e2e-site.sh \
    && chmod 755 /usr/local/bin/sudo /usr/local/bin/chsh /usr/local/bin/stow
