# Fresh Fedora for the `other` e2e host (X-other-linux: no overlay, the
# setup steps by hand): what a new install has before anything is done (git,
# curl, sudo), one passwordless-sudo user whose home holds /etc/skel's
# .bashrc and .bash_profile, and the e2e wrappers in /usr/local/bin, ahead of
# the real tools on the default PATH. The harness installs the distro
# packages itself through `sudo dnf install`. Build context is tests/e2e/;
# tests/e2e/run.sh passes E2E_USER and E2E_HOME from the host's env file and
# E2E_UID=$(id -u), so the user owns the /e2e/out it mounts.
FROM fedora:44

ARG E2E_USER
ARG E2E_UID
ARG E2E_HOME

RUN dnf -y install git curl sudo \
    && dnf clean all

# ~/.cache exists so that a --cache run's bind mount under it does not leave
# a root-owned parent the bootstrap's scratch dir (~/.cache/dotfiles-bootstrap)
# could not be made in; /e2e/out is where run.sh mounts the run's output.
RUN mkdir -p "$(dirname "$E2E_HOME")" \
    && useradd -m -d "$E2E_HOME" -u "$E2E_UID" -s /bin/bash "$E2E_USER" \
    && install -d -m 700 "$E2E_HOME/.cache" \
    && chown "$E2E_USER:" "$E2E_HOME/.cache" \
    && mkdir -p /e2e/src /e2e/out \
    && chown "$E2E_USER:" /e2e/out

# Passwordless sudo, logged with the year to the mounted output dir so the
# harness can place every sudo in a human:* or negative:* window.
RUN printf 'Defaults logfile=/e2e/out/log/sudo.log\nDefaults log_year\n%s ALL=(ALL) NOPASSWD:ALL\n' "$E2E_USER" \
        >/etc/sudoers.d/e2e \
    && chmod 0440 /etc/sudoers.d/e2e \
    && visudo -c

COPY wrappers/sudo wrappers/chsh wrappers/stow /usr/local/bin/
RUN chmod 755 /usr/local/bin/sudo /usr/local/bin/chsh /usr/local/bin/stow
