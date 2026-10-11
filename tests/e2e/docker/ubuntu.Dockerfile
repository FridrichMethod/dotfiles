# Fresh Ubuntu 24.04 for the lab-ubuntu and wsl-ubuntu e2e hosts: what a new
# workstation or WSL distribution has before the bootstrap runs (the quick
# start's ca-certificates, git, curl and sudo), one passwordless-sudo user
# whose home holds /etc/skel's .bashrc and .profile (the H7-stow `mv -n`
# lines are part of the test), and the e2e wrappers in /usr/local/bin, ahead
# of the real tools on the default PATH. DEBIAN_FRONTEND stays unset in the
# image on purpose: an apt that hangs without a TTY is a finding (the build
# below sets it for its own RUN lines only). Build context is tests/e2e/;
# tests/e2e/run.sh passes E2E_USER and E2E_HOME from the host's env file and
# E2E_UID=$(id -u), so the user owns the /e2e/out it mounts.
FROM ubuntu:24.04

ARG E2E_USER
ARG E2E_UID
ARG E2E_HOME

RUN DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates git curl sudo \
    && rm -rf /var/lib/apt/lists/*

# The image's own `ubuntu` account (uid 1000) is not on a fresh install and
# would collide with a build uid of 1000. ~/.cache exists so that a --cache
# run's bind mount under it does not leave a root-owned parent the
# bootstrap's scratch dir (~/.cache/dotfiles-bootstrap) could not be made in.
# /mnt/wsl/Ubuntu is the bind mount the wsl-ubuntu profile expects (harmless
# on lab-ubuntu); /e2e/out is where run.sh mounts the run's output.
RUN if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi \
    && mkdir -p "$(dirname "$E2E_HOME")" \
    && useradd -m -d "$E2E_HOME" -u "$E2E_UID" -s /bin/bash "$E2E_USER" \
    && install -d -m 700 "$E2E_HOME/.cache" \
    && chown "$E2E_USER:" "$E2E_HOME/.cache" \
    && mkdir -p /e2e/src /e2e/out /mnt/wsl/Ubuntu \
    && chown "$E2E_USER:" /e2e/out

# Passwordless sudo, logged with the year to the mounted output dir so the
# harness can place every sudo in a human:* or negative:* window.
RUN printf 'Defaults logfile=/e2e/out/log/sudo.log\nDefaults log_year\n%s ALL=(ALL) NOPASSWD:ALL\n' "$E2E_USER" \
        >/etc/sudoers.d/e2e \
    && chmod 0440 /etc/sudoers.d/e2e \
    && visudo -c

# Ubuntu's /etc/profile leaves USER and LOGNAME to login(1); docker/site/login.sh
# sets them for the login shells the harness starts.
COPY docker/site/login.sh /etc/profile.d/e2e-login.sh
COPY wrappers/sudo wrappers/chsh wrappers/stow /usr/local/bin/
RUN chmod 644 /etc/profile.d/e2e-login.sh \
    && chmod 755 /usr/local/bin/sudo /usr/local/bin/chsh /usr/local/bin/stow
