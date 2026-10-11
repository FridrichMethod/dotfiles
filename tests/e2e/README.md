# End-to-end bootstrap suite

Opt-in: runs the day-zero bootstrap for real, from a fresh home, on every host
overlay, the way the quick starts of [docs/bootstrap.md](../../docs/bootstrap.md#quick-start)
tell a person to, and checks its [acceptance checklist](../../docs/bootstrap.md#acceptance-checklist).
`./tests/run.sh` and pre-commit never run it; they run only the fast unit test
`tests/e2e-harness.sh`, which drives the harness against stubs. The full
description, each host's fidelity caveats, the HUMAN-block policy, the
acceptance criteria and the CI workflow are in
[docs/testing.md](../../docs/testing.md#end-to-end-bootstrap-opt-in).

## Run

```sh
./tests/e2e/run.sh lab-ubuntu                 # one host, one container
./tests/e2e/run.sh -j 2 sherlock marlowe      # at most two containers at a time
./tests/e2e/run.sh all                        # lab-ubuntu wsl-ubuntu other sherlock marlowe
E2E_NATIVE=1 ./tests/e2e/run.sh mac           # macOS only, natively on the machine (CI)
./tests/e2e/run.ps1                           # native Windows (CI)
```

`run.sh [-j N] [--cache DIR] [--keep] [--out DIR] [--no-build] <host>... | all`
needs Docker and a clean source checkout (`E2E_ALLOW_DIRTY=1` overrides; the
container still clones `HEAD`, so only uncommitted `tests/e2e/` changes, which
the harness reads from the working tree, are exercised) that is a plain
clone: a linked `git worktree` or submodule checkout is refused with exit 2
(`run from a plain clone`), because the container mounts only the checkout
and such a checkout's `.git` is a file pointing outside it. Run it as a
regular user, never root: the image user is created with your uid so it owns
the mounted `/e2e/out`. It
builds the image that `hosts/<host>.env` names from `docker/`, mounts the
checkout read-only at `/e2e/src` and the output directory at `/e2e/out`, and
runs `inside.sh` in a fresh container as the host's user under `bash -l`. It
prints a final table, `host result seconds out-dir`, and exits 0 when every
host passed, 1 when one failed, 2 for a usage error or refusal. A run needs
the network and takes from ten minutes to an hour per host.

## Hosts

| Host | Image | User and home |
| --- | --- | --- |
| `lab-ubuntu` | `ubuntu:24.04` | `fridrichmethod`, `/home/fridrichmethod` |
| `wsl-ubuntu` | `ubuntu:24.04`, `WSL_DISTRO_NAME=Ubuntu` | `fridrichmethod`, `/home/fridrichmethod` |
| `other` | `fedora:44` | `fridrichmethod`, `/home/fridrichmethod` |
| `sherlock` | `rockylinux:9` plus EPEL Lmod (`linux/amd64`) | `zyli2002`, `/home/users/zyli2002` |
| `marlowe` | `ubuntu:24.04` plus apt `lmod` (`linux/amd64`) | `zyli2002`, `/users/zyli2002` |
| `mac` | none: the `macos-15` runner | `runner`, `/Users/runner` |
| `win` | none: the `windows-2025` runner, `run.ps1` | the runner user |

## Outputs

`tests/e2e/out/<host>-<UTC timestamp>/` (git-ignored):

- `summary.tsv`: one tab-separated row per step, `<n> <step> <pass|fail|skip|note> <seconds> <detail>`
- `steps/NN-<step>.log`: stdout and stderr of each step
- `env.txt`: kernel, `/etc/os-release`, glibc, `id`, PATH, tool versions, `LMOD_DIR`, `SCRATCH`,
  the timeout binary (`none` on the mac runner) and the paths the HOME snapshots left out
  (`E2E_SNAPSHOT_PRUNE`, expanded)
- `log/wrappers.log`: every `sudo`, `chsh` and `stow` call, with the harness phase it ran in
  (the doctor's `stow --version` probe is logged like any call but is not a finding)
- `log/sudo.log`: sudo's own log (Ubuntu and Fedora images)
- `log/timeline`: `<epoch> <begin|end> <phase>` around every command the harness runs
- `snapshots/`: the `find` listings behind the no-write checks

## Cache

`--cache DIR` (or `E2E_CACHE_DIR`) mounts `DIR/apt`, `DIR/dnf` (dnf4's
`/var/cache/dnf` on Rocky), `DIR/libdnf5` (dnf5's `/var/cache/libdnf5` on
Fedora 44), `DIR/homebrew` and, on the cluster hosts, `DIR/conda-pkgs` into
the container, so a repeated run downloads less; `run.sh` creates them as you
before the run, so Docker never creates one owned by root. Off by default, and off for acceptance
runs, which must install exactly what a fresh machine installs. The checkout's
own `~/.cache/dotfiles-bootstrap` and `~/.nvm` are never mounted.

## Debugging

`--keep` (or `E2E_KEEP=1`) leaves the container in place after the run:
`docker ps -a` lists it, `docker exec -it <id> bash -l` opens a shell as the
host's user, `docker rm -f <id>` removes it. `--no-build` reuses an image that
already exists, after checking (`id -u <user>` in a throwaway container) that
its user has your uid, since images are shared by everyone on the Docker
daemon and one built for another uid could not write the mounted `/e2e/out`;
a mismatch is refused with exit 2. `--out DIR` chooses the output directory. The step that failed
is the first `fail` row of `summary.tsv`, and its log is under `steps/`; a
failed audit names the offending `log/wrappers.log` or `log/sudo.log` line.

## Where the policy lives

Which HUMAN blocks the harness runs, skips or fails on is decided in
`lib/blocks.sh` (Unix) and `lib/blocks.ps1` (Windows), keyed on the block's
step id and kind, and documented in
[docs/testing.md](../../docs/testing.md#human-block-policy). Each host is
described by `hosts/<host>.env`, its image by `docker/`, and the logging
`sudo`, `chsh` and `stow` wrappers by `wrappers/`: the images install them in
`/usr/local/bin`, and on the mac runner the workflow installs them there too,
before any phase opens, because macOS's `path_helper` puts `/usr/local/bin`
ahead of `/usr/bin` in every login shell and demotes any other directory
(`inside.sh`'s own `$E2E_OUT/bin` copy is reached only outside login shells).
The harness never writes inside the clone it tests, and its variables all
start with `E2E_`.
