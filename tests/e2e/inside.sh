#!/bin/bash
# tests/e2e/inside.sh: the in-container (or, on the macOS runner, native)
# half of the opt-in end-to-end bootstrap suite. It plays the person who
# bootstraps a fresh machine from docs/bootstrap.md: clones the read-only
# source checkout at E2E_REV into $HOME/dotfiles, runs the doctor and
# setup-host, runs the HUMAN blocks the policy in lib/blocks.sh allows,
# stows, starts a login shell, and audits that sudo, chsh and stow were only
# ever called inside those blocks. tests/e2e/run.sh starts it; it never runs
# against a workstation's own home: it refuses unless it is in a container
# (/.dockerenv), on Darwin with E2E_NATIVE=1 (the macos runner), or given
# E2E_SANDBOX_HOME under the temp dir (the unit test's seam, Linux or Darwin).
#
#   E2E_HOST=<host> E2E_REV=<sha> E2E_SRC=<checkout> E2E_OUT=<dir> inside.sh
#
# Writes E2E_OUT/summary.tsv ("<n>\t<step>\t<pass|fail|skip|note>\t<seconds>
# \t<detail>"), steps/NN-<step>.{log,out,err}, env.txt, log/timeline,
# snapshots/. Exit 0 when every step passed, 1 when one failed, 2 for a
# usage error or refusal. Bash 3.2 and BSD userland; see lib/common.sh.

set -u

E2E_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
# shellcheck source=tests/e2e/lib/common.sh
. "$E2E_DIR/lib/common.sh"
# shellcheck source=tests/e2e/lib/blocks.sh
. "$E2E_DIR/lib/blocks.sh"
# shellcheck source=tests/e2e/lib/assert.sh
. "$E2E_DIR/lib/assert.sh"
# shellcheck source=tests/e2e/lib/steps.sh
. "$E2E_DIR/lib/steps.sh"
# shellcheck source=tests/e2e/lib/flow-unix.sh
. "$E2E_DIR/lib/flow-unix.sh"
# shellcheck source=tests/e2e/lib/flow-other.sh
. "$E2E_DIR/lib/flow-other.sh"

# The host env keys inside.sh reads. One already exported by the caller
# wins over the file (the unit test points E2E_LOGIN_ZSH at a stub).
E2E_FLOW_KEYS='E2E_USER E2E_HOME E2E_FLOW E2E_PROFILE E2E_SETUP_HOST E2E_DOCTOR_ARGS E2E_SUDO
E2E_ALLOC_ENV E2E_LOGIN_ZSH E2E_NEGATIVE E2E_PACKAGES E2E_PKG_INSTALL E2E_SNAPSHOT_PRUNE'

# e2e_load_host_env FILE: source FILE, then put back every flow key the
# environment already had.
e2e_load_host_env() {
    local key saved=''
    for key in $E2E_FLOW_KEYS; do
        if eval "[ \"\${$key+set}\" = set ]"; then
            saved="$saved $key"
            eval "E2E_PRESET_$key=\${$key}"
        fi
    done
    # shellcheck source=/dev/null
    . "$1" || e2e_die "cannot source $1"
    for key in $saved; do
        eval "$key=\${E2E_PRESET_$key}"
    done
}

# e2e_physical PATH: PATH with links resolved (no readlink -f on macOS).
e2e_physical() {
    (cd -- "$1" 2>/dev/null && pwd -P)
}

# --- arguments and refusals (exit 2) -----------------------------------------

[ $# -eq 0 ] || e2e_die 'inside.sh takes no arguments; it reads E2E_HOST, E2E_REV, E2E_SRC and E2E_OUT'
[ -n "${E2E_HOST:-}" ] || e2e_die 'E2E_HOST is unset (lab-ubuntu, wsl-ubuntu, other, sherlock, marlowe or mac)'
case $E2E_HOST in
    *[!a-z-]*) e2e_die "E2E_HOST is not a host name: $E2E_HOST" ;;
esac
[ -f "$E2E_DIR/hosts/$E2E_HOST.env" ] || e2e_die "no tests/e2e/hosts/$E2E_HOST.env"
[ "$E2E_HOST" != win ] || e2e_die 'the win host is driven by tests/e2e/run.ps1, not by inside.sh'
e2e_load_host_env "$E2E_DIR/hosts/$E2E_HOST.env"
case ${E2E_FLOW:-} in
    unix | other) ;;
    *) e2e_die "hosts/$E2E_HOST.env sets no E2E_FLOW the harness knows (unix or other)" ;;
esac

[ -n "${E2E_SRC:-}" ] || e2e_die 'E2E_SRC is unset (the source checkout)'
[ -d "$E2E_SRC" ] || e2e_die "E2E_SRC is not a directory: $E2E_SRC"
E2E_SRC=$(e2e_physical "$E2E_SRC") || e2e_die "cannot enter E2E_SRC $E2E_SRC"
git -C "$E2E_SRC" -c "safe.directory=$E2E_SRC" rev-parse --git-dir >/dev/null 2>&1 ||
    e2e_die "E2E_SRC is not a git checkout: $E2E_SRC"
[ -n "${E2E_REV:-}" ] || e2e_die 'E2E_REV is unset (the commit to test)'
case $E2E_REV in
    *[!0-9a-f]*) e2e_die "E2E_REV is not a 40-hex commit: $E2E_REV" ;;
esac
[ "${#E2E_REV}" -eq 40 ] || e2e_die "E2E_REV is not a 40-hex commit: $E2E_REV"
git -C "$E2E_SRC" -c "safe.directory=$E2E_SRC" cat-file -e "$E2E_REV^{commit}" 2>/dev/null ||
    e2e_die "E2E_REV $E2E_REV is not a commit of $E2E_SRC"
if [ "${E2E_ALLOW_DIRTY:-}" != 1 ]; then
    dirty=$(git -C "$E2E_SRC" -c "safe.directory=$E2E_SRC" --no-optional-locks status --porcelain 2>/dev/null) ||
        e2e_die "git status fails in $E2E_SRC"
    [ -z "$dirty" ] || e2e_die "E2E_SRC has uncommitted changes (E2E_ALLOW_DIRTY=1 overrides): $(e2e_one_line "$dirty" 200)"
fi
[ -n "${E2E_OUT:-}" ] || e2e_die 'E2E_OUT is unset (the output directory)'
mkdir -p "$E2E_OUT/log" "$E2E_OUT/steps" "$E2E_OUT/snapshots" "$E2E_OUT/tmp" || e2e_die "cannot create $E2E_OUT"
E2E_OUT=$(e2e_physical "$E2E_OUT") || e2e_die "cannot enter E2E_OUT"
[ -w "$E2E_OUT" ] || e2e_die "E2E_OUT is not writable: $E2E_OUT"

# Containment: a container, the macOS runner, or the unit test's sandbox
# home. Nothing else; a workstation's real home is never bootstrapped.
E2E_RUN_USER=$(id -un 2>/dev/null) || E2E_RUN_USER=${USER:-}
[ -n "$E2E_RUN_USER" ] || e2e_die 'cannot tell the running user (id -un)'
E2E_MODE=''
if [ -n "${E2E_SANDBOX_HOME:-}" ]; then
    case $E2E_SANDBOX_HOME in
        /*) ;;
        *) e2e_die "E2E_SANDBOX_HOME must be absolute: $E2E_SANDBOX_HOME" ;;
    esac
    tmp_root=$(e2e_physical "${TMPDIR:-/tmp}") || e2e_die 'cannot enter the temp dir'
    mkdir -p "$E2E_SANDBOX_HOME" || e2e_die "cannot create E2E_SANDBOX_HOME $E2E_SANDBOX_HOME"
    sandbox=$(e2e_physical "$E2E_SANDBOX_HOME") || e2e_die "cannot enter E2E_SANDBOX_HOME"
    case $sandbox in
        "$tmp_root"/?*) ;;
        *) e2e_die "E2E_SANDBOX_HOME must lie under the temp dir $tmp_root: $sandbox" ;;
    esac
    real_home=$(e2e_physical "$HOME") || real_home=$HOME
    [ "$sandbox" != "$real_home" ] || e2e_die "E2E_SANDBOX_HOME is the real HOME: $sandbox"
    HOME=$sandbox
    export HOME
    E2E_MODE=sandbox
elif [ -f /.dockerenv ]; then
    E2E_MODE=container
elif [ "${E2E_NATIVE:-}" = 1 ] && [ "$(uname -s)" = Darwin ]; then
    E2E_MODE=native
else
    e2e_die 'refusing to run outside a container: no /.dockerenv, not Darwin with E2E_NATIVE=1, no E2E_SANDBOX_HOME'
fi
if [ "$E2E_MODE" != sandbox ]; then
    # The env file says who runs in the image or on the runner; a mismatch
    # means a different machine, whose home must stay untouched.
    [ "$E2E_RUN_USER" = "${E2E_USER:-}" ] ||
        e2e_die "running as $E2E_RUN_USER, but hosts/$E2E_HOST.env expects ${E2E_USER:-?}"
    [ "$HOME" = "${E2E_HOME:-}" ] ||
        e2e_die "HOME is $HOME, but hosts/$E2E_HOST.env expects ${E2E_HOME:-?}"
fi
[ -d "$HOME" ] && [ -w "$HOME" ] || e2e_die "HOME is not a writable directory: $HOME"
E2E_CLONE=$HOME/dotfiles
[ ! -e "$E2E_CLONE" ] || e2e_die "$E2E_CLONE exists already; the flow needs a fresh home"
# The images are Linux; the sandbox seam also serves the unit test on the
# macOS runner, whose /bin/bash 3.2 runs tests/run.sh.
case $E2E_MODE:$(uname -s) in
    container:Linux | sandbox:Linux | sandbox:Darwin | native:Darwin) ;;
    *) e2e_die "a $E2E_MODE run does not work on $(uname -s)" ;;
esac

# --- the run -----------------------------------------------------------------

# The PATH a fresh login shell starts with; on the mac runner the wrappers
# (tests/e2e/wrappers, installed by the images at /usr/local/bin) go first.
if [ "$(uname -s)" = Darwin ]; then
    E2E_SYS_PATH=/usr/bin:/bin:/usr/sbin:/sbin
else
    E2E_SYS_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
fi
if [ "$E2E_MODE" = native ]; then
    E2E_WRAP_BIN=$E2E_OUT/bin
    mkdir -p "$E2E_WRAP_BIN"
    for tool in sudo chsh stow; do
        if [ -f "$E2E_SRC/tests/e2e/wrappers/$tool" ]; then
            cp "$E2E_SRC/tests/e2e/wrappers/$tool" "$E2E_WRAP_BIN/$tool" && chmod 755 "$E2E_WRAP_BIN/$tool"
        else
            e2e_log "warning: no tests/e2e/wrappers/$tool to install; the wrappers audit will miss $tool"
        fi
    done
    PATH=$E2E_WRAP_BIN:$PATH
    E2E_SYS_PATH=$E2E_WRAP_BIN:$E2E_SYS_PATH
    export PATH
fi
export E2E_OUT E2E_SRC E2E_REV E2E_HOST
e2e_find_timeout
: >"$E2E_OUT/summary.tsv"
: >"$E2E_OUT/log/timeline"
e2e_write_env "$E2E_MODE"
E2E_LOGIN_SHELL_START=$(e2e_login_shell_of)
e2e_log "host $E2E_HOST ($E2E_FLOW flow, $E2E_MODE) as $E2E_RUN_USER in $HOME; source $E2E_SRC at ${E2E_REV:0:12}; output $E2E_OUT"

case $E2E_FLOW in
    unix) e2e_flow_unix ;;
    other) e2e_flow_other ;;
esac

e2e_log "$E2E_HOST: $E2E_PASSES pass, $E2E_FAILS fail, $E2E_SKIPS skip; summary $E2E_OUT/summary.tsv"
[ "$E2E_FAILS" = 0 ] || exit 1
exit 0
