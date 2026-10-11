#!/bin/bash

# Host-side driver of the opt-in end-to-end bootstrap suite. For each host it
# builds that host's image from tests/e2e/docker/ (build context tests/e2e/),
# then runs tests/e2e/inside.sh in a container as the host's user, with this
# checkout mounted read-only at /e2e/src and a fresh output directory at
# /e2e/out, and prints one table row per host. mac runs natively on a Mac
# with E2E_NATIVE=1 (no Docker); win is driven by tests/e2e/run.ps1. Each
# host's values (image, Dockerfile, build args, user, home, container env)
# come from tests/e2e/hosts/<host>.env, written by the harness.
#
#   run.sh [-j N] [--cache DIR] [--keep] [--out DIR] [--no-build] <host>... | all
#
# Exit 0 when every host passed, 1 when one failed, 2 for a usage error or a
# refusal (root, dirty checkout, linked worktree or submodule checkout, no
# docker, a --no-build image whose user has another uid, mac off a Mac, win).
# Knobs: E2E_ALLOW_DIRTY=1 runs from a checkout with uncommitted changes (the
# clone is still HEAD: only tests/e2e/ changes, which the harness reads from
# this working tree, are exercised uncommitted), E2E_KEEP=1 is --keep,
# E2E_CACHE_DIR is --cache. Bash 3.2 compatible (the macOS runner's
# /bin/bash): no mapfile, associative arrays or `wait -n`; BSD userland safe.
# SIGPIPE may be ignored on CI runners: every pipeline below ends in a reader
# that consumes all its input (tee, sed).

set -euo pipefail

E2E_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
SRC=$(cd -- "$E2E_DIR/../.." && pwd -P)
HOSTS_ALL='lab-ubuntu wsl-ubuntu other sherlock marlowe'
HOSTS_KNOWN="$HOSTS_ALL mac win"
MAX_JOBS=2
CONTAINER_SRC=/e2e/src
CONTAINER_OUT=/e2e/out

# The env file keys this driver reads; load_env clears them before sourcing
# so one host's values never carry over to the next (the harness reads the
# E2E_FLOW, E2E_PROFILE and other keys itself).
ENV_KEYS='E2E_IMAGE E2E_DOCKERFILE E2E_BUILD_ARGS E2E_PLATFORM_FLAG E2E_USER E2E_HOME
E2E_CONTAINER_ENV E2E_NATIVE_ONLY E2E_ALLOC_ENV'

usage() {
    printf 'Usage: %s [-j N] [--cache DIR] [--keep] [--out DIR] [--no-build] <host>... | all\n' "${0##*/}"
    printf '  hosts: %s (all), mac (natively, on a Mac with E2E_NATIVE=1); win: tests/e2e/run.ps1\n' "$HOSTS_ALL"
    printf '  -j N        run up to N containers at once (1 or 2; default 1)\n'
    printf '  --cache DIR mount package caches from DIR (apt, dnf, libdnf5, homebrew, conda-pkgs)\n'
    printf '  --keep      keep each container after its run (docker rm it yourself)\n'
    printf '  --out DIR   put the <host>-<UTC time> run dirs in DIR (default tests/e2e/out)\n'
    printf '  --no-build  reuse an existing image instead of building it (its user must have your uid)\n'
    printf '  run it as a regular user from a plain clone: a linked worktree or submodule checkout is refused\n'
}

die() {
    local code=$1
    shift
    printf 'run.sh: %s\n' "$*" >&2
    exit "$code"
}

usage_error() {
    printf 'run.sh: %s\n' "$*" >&2
    usage >&2
    exit 2
}

log() {
    printf '[e2e] %s\n' "$*"
}

# --- options ---------------------------------------------------------------

jobs=1
cache=${E2E_CACHE_DIR:-}
keep=0
[ "${E2E_KEEP:-}" != 1 ] || keep=1
out_root=''
build=1
hosts=''
while [ $# -gt 0 ]; do
    case $1 in
        -j)
            [ $# -ge 2 ] || usage_error '-j needs a value'
            jobs=$2
            shift 2
            ;;
        -j?*)
            jobs=${1#-j}
            shift
            ;;
        --cache)
            [ $# -ge 2 ] || usage_error '--cache needs a directory'
            cache=$2
            shift 2
            ;;
        --cache=*)
            cache=${1#--cache=}
            shift
            ;;
        --keep)
            keep=1
            shift
            ;;
        --out)
            [ $# -ge 2 ] || usage_error '--out needs a directory'
            out_root=$2
            shift 2
            ;;
        --out=*)
            out_root=${1#--out=}
            shift
            ;;
        --no-build)
            build=0
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        all)
            hosts="$hosts $HOSTS_ALL"
            shift
            ;;
        -*) usage_error "unknown option: $1" ;;
        *)
            hosts="$hosts $1"
            shift
            ;;
    esac
done

case $jobs in
    '' | *[!0-9]*) usage_error "-j needs a number, not '$jobs'" ;;
esac
[ "$jobs" -ge 1 ] && [ "$jobs" -le "$MAX_JOBS" ] ||
    usage_error "-j $jobs: at most $MAX_JOBS containers run at once (each run takes an hour and a core)"
[ -n "$hosts" ] || usage_error 'no host given'

# Dedupe, keep order, refuse unknown names before anything runs.
selected=()
for host in $hosts; do
    case " $HOSTS_KNOWN " in
        *" $host "*) ;;
        *) usage_error "unknown host '$host'; hosts: $HOSTS_KNOWN" ;;
    esac
    case " ${selected[*]-} " in
        *" $host "*) continue ;;
    esac
    selected+=("$host")
done
for host in "${selected[@]}"; do
    [ "$host" != win ] || die 2 'win is driven by tests/e2e/run.ps1 (PowerShell 7); use tests/e2e/run.ps1'
done

# --- the driver's user -----------------------------------------------------

# The images create their user with this uid (useradd refuses 0) so that it
# owns the mounted /e2e/out, and mac bootstraps the home of the user running
# it; a root run would fail late, in the image build or inside the container.
[ "$(id -u)" != 0 ] ||
    die 2 'run as a regular user, not root: the container user is created with your uid so it owns the mounted /e2e/out (useradd refuses uid 0), and mac bootstraps the home of the user running it'

# --- source checkout -------------------------------------------------------

if [ "${E2E_ALLOW_DIRTY:-}" != 1 ]; then
    dirty=$(git -C "$SRC" status --porcelain) || die 2 "git status failed in $SRC"
    if [ -n "$dirty" ]; then
        printf '%s\n' "$dirty" | sed -n '1,10p' >&2
        die 2 "the source checkout $SRC has uncommitted changes (above); commit them, or set E2E_ALLOW_DIRTY=1 to run anyway (the container clones HEAD, so uncommitted changes outside tests/e2e/ are not tested; the harness itself runs from this working tree)"
    fi
fi
E2E_REV=$(git -C "$SRC" rev-parse HEAD) || die 2 "git rev-parse HEAD failed in $SRC"
case $E2E_REV in
    *[!0-9a-f]*) die 2 "unexpected HEAD '$E2E_REV' in $SRC" ;;
esac
[ "${#E2E_REV}" -eq 40 ] || die 2 "unexpected HEAD '$E2E_REV' in $SRC"

# --- per-host values -------------------------------------------------------

# load_env HOST: source tests/e2e/hosts/HOST.env after clearing the keys this
# driver reads, so a key the file leaves out is empty, not the last host's.
load_env() {
    local file=$E2E_DIR/hosts/$1.env key
    [ -f "$file" ] ||
        die 2 "no $file: the harness defines host '$1' there (tests/e2e/hosts/<host>.env); is tests/e2e/inside.sh in this checkout?"
    for key in $ENV_KEYS; do
        unset "$key"
    done
    # shellcheck source=/dev/null # plain KEY=value assignments per host
    . "$file"
}

# Parallel arrays indexed by selection order (Bash 3.2 has no associative
# arrays): the env values each host needs, its out dir, and its run state.
h_host=() h_image=() h_dockerfile=() h_build_args=() h_platform=() h_user=() h_home=()
h_cenv=() h_native=() h_alloc=() h_out=() h_pid=() h_start=() h_end=() h_rc=() h_done=()
count=0
need_docker=0
for host in "${selected[@]}"; do
    load_env "$host"
    h_host[count]=$host
    h_image[count]=${E2E_IMAGE:-}
    h_dockerfile[count]=${E2E_DOCKERFILE:-}
    h_build_args[count]=${E2E_BUILD_ARGS:-}
    h_platform[count]=${E2E_PLATFORM_FLAG:-}
    h_user[count]=${E2E_USER:-}
    h_home[count]=${E2E_HOME:-}
    h_cenv[count]=${E2E_CONTAINER_ENV:-}
    h_native[count]=${E2E_NATIVE_ONLY:-}
    h_alloc[count]=${E2E_ALLOC_ENV:-}
    h_done[count]=0
    if [ "${h_native[count]}" = 1 ]; then
        [ "$(uname -s)" = Darwin ] && [ "${E2E_NATIVE:-}" = 1 ] ||
            die 2 "$host runs natively on macOS only: on a Mac, E2E_NATIVE=1 $0 $host (it bootstraps the home of the user running it)"
    else
        need_docker=1
        [ -n "${h_image[count]}" ] && [ -n "${h_dockerfile[count]}" ] && [ -n "${h_user[count]}" ] ||
            die 2 "tests/e2e/hosts/$host.env needs E2E_IMAGE, E2E_DOCKERFILE and E2E_USER"
        [ -f "$E2E_DIR/docker/${h_dockerfile[count]}" ] ||
            die 2 "tests/e2e/hosts/$host.env names E2E_DOCKERFILE=${h_dockerfile[count]}, which is not in tests/e2e/docker/"
    fi
    count=$((count + 1))
done
if [ "$need_docker" = 1 ]; then
    command -v docker >/dev/null 2>&1 ||
        die 2 'docker is required for the container hosts (install Docker, or run only mac natively)'
    # inside.sh clones /e2e/src, so the mount must hold the whole repository:
    # a linked worktree's .git is a file naming a directory outside the mount.
    [ -d "$SRC/.git" ] ||
        die 2 "$SRC is a linked worktree or submodule checkout (its .git is a file that points outside it), which the container cannot follow; run from a plain clone"
fi

# --- output directories ----------------------------------------------------

[ -n "$out_root" ] || out_root=$E2E_DIR/out
mkdir -p "$out_root" || die 2 "cannot create $out_root"
out_root=$(cd -- "$out_root" && pwd -P)
if [ -n "$cache" ]; then
    # Every directory cache_args mounts, made here as the user: docker would
    # create a missing bind source itself, owned by root.
    mkdir -p "$cache/apt" "$cache/dnf" "$cache/libdnf5" "$cache/homebrew" "$cache/conda-pkgs" ||
        die 2 "cannot create the cache dir $cache"
    cache=$(cd -- "$cache" && pwd -P)
fi
stamp=$(date -u +%Y%m%dT%H%M%SZ)
i=0
while [ "$i" -lt "$count" ]; do
    h_out[i]=$out_root/${h_host[i]}-$stamp
    # log/ must exist before the run: sudo appends to log/sudo.log inside
    # it, and the empty file is made here, as the user, so root's appends
    # leave a file the user (in the container and on this host) can read.
    mkdir -p "${h_out[i]}/log" || die 2 "cannot create ${h_out[i]}/log"
    [ "${h_native[i]}" = 1 ] || : >"${h_out[i]}/log/sudo.log"
    i=$((i + 1))
done

# --- images ----------------------------------------------------------------

# image_user_uid INDEX: the uid the existing image of host INDEX gives its
# user (`id -u <user>` in a throwaway container), or nothing when the image
# cannot say; an image built for another uid cannot write the mounted
# /e2e/out, and inside.sh would only report "cannot create /e2e/out".
image_user_uid() {
    local i=$1 args=(run --rm --entrypoint id)
    [ -z "${h_platform[i]}" ] || args+=(--platform "${h_platform[i]}")
    docker "${args[@]}" "${h_image[i]}" -u "${h_user[i]}" 2>/dev/null </dev/null
}

# build_image INDEX: docker build the image of host INDEX, its output
# streamed and copied to log/docker-build.log of every selected host that
# uses the same image. --no-build keeps an image that already exists, when
# its user has this driver's uid.
build_image() {
    local i=$1 image=${h_image[$1]} logs=() j kv args=() seconds image_uid
    j=0
    while [ "$j" -lt "$count" ]; do
        [ "${h_image[j]}" != "$image" ] || logs+=("${h_out[j]}/log/docker-build.log")
        j=$((j + 1))
    done
    if [ "$build" = 0 ] && docker image inspect "$image" >/dev/null 2>&1; then
        image_uid=$(image_user_uid "$i") || image_uid=''
        case $image_uid in
            '' | *[!0-9]*) image_uid='' ;;
        esac
        [ "$image_uid" = "$(id -u)" ] ||
            die 2 "the existing image $image gives ${h_user[i]} uid ${image_uid:-unknown}, not your $(id -u), so it could not write the mounted /e2e/out; drop --no-build to rebuild it for this user"
        log "using the existing image $image (--no-build; ${h_user[i]} has uid $image_uid there, as here)"
        printf 'using the existing image %s (--no-build; %s has uid %s there)\n' "$image" "${h_user[i]}" "$image_uid" |
            tee "${logs[@]}" >/dev/null
        return 0
    fi
    [ "$build" = 1 ] || log "no image $image yet; building it despite --no-build"
    [ -z "${h_platform[i]}" ] || args+=(--platform "${h_platform[i]}")
    for kv in ${h_build_args[i]}; do
        args+=(--build-arg "$kv")
    done
    log "building $image from tests/e2e/docker/${h_dockerfile[i]}"
    seconds=$(date +%s)
    docker build --build-arg "E2E_UID=$(id -u)" ${args[@]+"${args[@]}"} \
        -t "$image" -f "$E2E_DIR/docker/${h_dockerfile[i]}" "$E2E_DIR" 2>&1 | tee "${logs[@]}" ||
        die 1 "docker build of $image failed (log: ${logs[0]})"
    log "built $image in $(($(date +%s) - seconds))s"
}

# Each image once, in selection order: lab-ubuntu and wsl-ubuntu share one.
built=''
i=0
while [ "$i" -lt "$count" ]; do
    if [ "${h_native[i]}" != 1 ]; then
        case " $built " in
            *" ${h_image[i]} "*) ;;
            *)
                build_image "$i"
                built="$built ${h_image[i]}"
                ;;
        esac
    fi
    i=$((i + 1))
done

# --- one run ---------------------------------------------------------------

# image_scratch INDEX: the SCRATCH the host's image gives its login shells
# (docker/site/sherlock.sh; the marlowe overlay sets /scratch/$PROJECT_ID
# itself and ubuntu-lmod.Dockerfile creates that dir), for expanding the
# cache path in E2E_ALLOC_ENV; empty for a host without one.
image_scratch() {
    case ${h_host[$1]} in
        sherlock) printf '/scratch/users/%s\n' "${h_user[$1]}" ;;
        marlowe) printf '/scratch/m000191\n' ;;
        *) printf '\n' ;;
    esac
}

# cache_args INDEX: set CACHE_ARGS to the -v arguments of a --cache run: the
# apt, dnf (dnf4's /var/cache/dnf on Rocky, dnf5's /var/cache/libdnf5 on
# Fedora 44) and Homebrew caches for every image, and the conda package
# cache at the CONDA_PKGS_DIRS that E2E_ALLOC_ENV names on an hpc host, with
# its $SCRATCH and $USER expanded to the image's values. Never the home's
# ~/.cache/dotfiles-bootstrap or ~/.nvm: the bootstrap's own downloads are
# part of the test.
CACHE_ARGS=()
cache_args() {
    local i=$1 scratch conda='' kv pattern
    CACHE_ARGS=(-v "$cache/apt:/var/cache/apt/archives" -v "$cache/dnf:/var/cache/dnf"
        -v "$cache/libdnf5:/var/cache/libdnf5")
    [ -z "${h_home[i]}" ] || CACHE_ARGS+=(-v "$cache/homebrew:${h_home[i]}/.cache/Homebrew")
    for kv in ${h_alloc[i]}; do
        case $kv in
            CONDA_PKGS_DIRS=*) conda=${kv#CONDA_PKGS_DIRS=} ;;
        esac
    done
    [ -n "$conda" ] || return 0
    scratch=$(image_scratch "$i")
    pattern='$SCRATCH'
    conda=${conda//"$pattern"/$scratch}
    pattern='${SCRATCH}'
    conda=${conda//"$pattern"/$scratch}
    pattern='$USER'
    conda=${conda//"$pattern"/${h_user[i]}}
    pattern='${USER}'
    conda=${conda//"$pattern"/${h_user[i]}}
    case $conda in
        /*) CACHE_ARGS+=(-v "$cache/conda-pkgs:$conda") ;;
        *) printf 'run.sh: [%s] not mounting the conda cache: CONDA_PKGS_DIRS expands to %s\n' "${h_host[i]}" "$conda" >&2 ;;
    esac
}

# container_name INDEX: the name every container gets, so an interrupt can
# docker kill it and --keep leaves something a person can find.
container_name() {
    printf 'dotfiles-e2e-%s-%s\n' "${h_host[$1]}" "$stamp"
}

# run_container INDEX: the contract's docker run, with a tee into
# log/container.log and a [host] prefix on the terminal. Returns the
# container's exit status (inside.sh: 0 passed, 1 failed, 2 refused).
run_container() {
    local i=$1 host=${h_host[$1]} out=${h_out[$1]} name args=() kv rc=0
    name=$(container_name "$i")
    args=(run --init -u "${h_user[i]}" --name "$name")
    [ "$keep" = 1 ] || args+=(--rm)
    [ -z "${h_platform[i]}" ] || args+=(--platform "${h_platform[i]}")
    args+=(-e "E2E_HOST=$host" -e "E2E_REV=$E2E_REV" -e "E2E_SRC=$CONTAINER_SRC" -e "E2E_OUT=$CONTAINER_OUT")
    [ -z "${E2E_ALLOW_DIRTY:-}" ] || args+=(-e "E2E_ALLOW_DIRTY=$E2E_ALLOW_DIRTY")
    for kv in ${h_cenv[i]}; do
        args+=(-e "$kv")
    done
    args+=(-v "$SRC:$CONTAINER_SRC:ro" -v "$out:$CONTAINER_OUT")
    if [ -n "$cache" ]; then
        cache_args "$i"
        args+=("${CACHE_ARGS[@]}")
    fi
    args+=("${h_image[i]}" bash -lc "$CONTAINER_SRC/tests/e2e/inside.sh")
    printf 'docker %s\n' "${args[*]}" >"$out/log/docker-run.cmd"
    if docker "${args[@]}" 2>&1 | tee "$out/log/container.log" | sed "s/^/[$host] /"; then
        rc=0
    else
        rc=${PIPESTATUS[0]}
    fi
    [ "$keep" != 1 ] || log "[$host] kept container $name (docker cp / docker commit it; docker rm $name when done)"
    return "$rc"
}

# run_native INDEX: mac. inside.sh runs on this machine, as this user, with
# the same variables the container gets; it refuses unless E2E_NATIVE=1 on
# Darwin, checked above.
run_native() {
    local i=$1 host=${h_host[$1]} out=${h_out[$1]} rc=0
    if E2E_SRC=$SRC E2E_OUT=$out E2E_REV=$E2E_REV E2E_HOST=$host "$SRC/tests/e2e/inside.sh" 2>&1 |
        tee "$out/log/native.log" | sed "s/^/[$host] /"; then
        rc=0
    else
        rc=${PIPESTATUS[0]}
    fi
    return "$rc"
}

# run_host INDEX: one host, in a background subshell; its exit status is the
# host's result.
run_host() {
    if [ "${h_native[$1]}" = 1 ]; then
        run_native "$1"
    else
        run_container "$1"
    fi
}

# --- scheduling ------------------------------------------------------------

# Up to $jobs runs at once. Bash 3.2 has no `wait -n`, so finished jobs are
# found with kill -0 and reaped with `wait <pid>`, which returns their status.
pids_running() {
    local i=0 list=''
    while [ "$i" -lt "$started" ]; do
        [ "${h_done[i]}" = 1 ] || list="$list ${h_pid[i]}"
        i=$((i + 1))
    done
    printf '%s\n' "$list"
}

# on_signal: a background subshell dies with its signal, but the docker
# client and the container it started would live on; kill the containers by
# name first (--rm then removes them; --keep leaves them stopped).
on_signal() {
    local i=0
    trap - INT TERM
    while [ "$i" -lt "$started" ]; do
        if [ "${h_done[i]}" = 0 ] && [ "${h_native[i]}" != 1 ]; then
            docker kill "$(container_name "$i")" >/dev/null 2>&1 || true
        fi
        i=$((i + 1))
    done
    # shellcheck disable=SC2046 # the pid list is space-separated by construction
    kill $(pids_running) 2>/dev/null || true
    wait 2>/dev/null || true
    die 1 'interrupted; the running containers were killed'
}
started=0
finished=0
trap on_signal INT TERM

while [ "$finished" -lt "$count" ]; do
    while [ "$started" -lt "$count" ] && [ $((started - finished)) -lt "$jobs" ]; do
        i=$started
        log "[${h_host[i]}] starting; output in ${h_out[i]}"
        h_start[i]=$(date +%s)
        run_host "$i" &
        h_pid[i]=$!
        started=$((started + 1))
    done
    reaped=0
    i=0
    while [ "$i" -lt "$started" ]; do
        if [ "${h_done[i]}" = 0 ] && ! kill -0 "${h_pid[i]}" 2>/dev/null; then
            rc=0
            wait "${h_pid[i]}" || rc=$?
            h_rc[i]=$rc
            h_end[i]=$(date +%s)
            h_done[i]=1
            finished=$((finished + 1))
            reaped=1
            log "[${h_host[i]}] exit $rc after $((h_end[i] - h_start[i]))s"
        fi
        i=$((i + 1))
    done
    [ "$reaped" = 1 ] || sleep 1
done
trap - INT TERM

# --- table -----------------------------------------------------------------

status=0
printf '\n%-12s %-8s %8s  %s\n' host result seconds out-dir
i=0
while [ "$i" -lt "$count" ]; do
    case ${h_rc[i]} in
        0) result=pass ;;
        1) result=fail ;;
        2) result=refused ;;
        *) result="exit-${h_rc[i]}" ;;
    esac
    [ "${h_rc[i]}" = 0 ] || status=1
    printf '%-12s %-8s %8s  %s\n' "${h_host[i]}" "$result" "$((h_end[i] - h_start[i]))" "${h_out[i]}"
    i=$((i + 1))
done
exit "$status"
