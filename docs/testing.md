# Cross-platform testing

The `ci.yml` workflow uses three explicit operating-system jobs. Tests operate
on temporary repositories and targets; they must not install into the runner's
real user profile. (The opt-in `bootstrap-e2e.yml` workflow, [below](#end-to-end-bootstrap-opt-in),
is the one exception: it installs for real, into fresh containers and the
macOS and Windows runners' homes.)

| Job | Mandatory checks | Provisioning |
| --- | --- | --- |
| `ubuntu-24.04` | `./tests/run.sh --ci`, full `pre-commit run --all-files` | Python 3.11, Node 24, GNU Stow; pre-commit installs its pinned hooks |
| `macos-15` | `/bin/bash ./tests/run.sh --ci` | Python 3.12, Node 24, GNU Stow; retain system Bash and BSD utilities |
| `windows-2025` | `./tests/run.ps1 -CI` in native PowerShell | Python 3.12 and Node 24; Git and PowerShell come from the runner and are checked explicitly |

The Unix entrypoint checks Bash, POSIX sh, Git, Python and Node before starting.
All jobs explicitly run `setup-sync.sh` or `setup-sync.ps1` to provision the
hash-pinned configuration parser. Both entrypoints validate this runtime and
require the shared Python backend tests, including safe replacement failures.
In CI mode GNU Stow is required too, so its real symlink fixture cannot silently
skip. On developer machines, `./tests/run.sh` reports a missing optional Stow
integration check, installed-Codex exec-policy check, or PowerShell check.
Codex is not installed merely to test dotfiles; its optional executable-policy
probes supplement the always-run repository rule assertions.

Every Unix test entry point (`tests/*.sh`) starts by unsetting the dotfiles
knobs, and `tests/run.ps1` removes the same list: `DOTFILES_AUTO_UPDATE`,
`DOTFILES_AUTO_STOW`, `DOTFILES_HOST`, `DOTFILES_DIR`, `DOTFILES_COLOR`,
`DOTFILES_STOW_WITHOUT_OH_MY_ZSH`, the `AWESOME_SKILLS_*` controls and both
session markers. The bootstrap playbook tells people to export
`DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0` while provisioning, and a
test or `pre-commit run` started from such a shell must behave as in CI; each
case sets the knobs it exercises. `tests/test-entrypoints.sh` checks that every
entry point carries the same list, that it covers every `DOTFILES_*` and
`AWESOME_SKILLS_*` name in a tracked file outside `tests/`, `docs/`,
`.github/` and Markdown, whatever reads it (shell, PowerShell or Python;
`DOTFILES_SYNC_PYTHON` excepted, since `tests/run.sh` provisions it), and that
a suite passes under those exports.

PowerShell is optional in the Unix jobs. When present, the existing shell suite
runs the PowerShell parser, terminal-output, installer confirmation, update behavior and PowerShell profile/prompt-theme contract tests. The Windows job invokes
PowerShell behavior tests directly and fails if any assigned suite fails; it
does not depend on Bash discovering an optional PowerShell executable.

`tests/terminal.sh` exercises actual Unix pseudo-terminals as well as redirected
stdout/stderr, including forced color, `NO_COLOR`, `TERM=dumb`, literal percent
signs and silent sourcing. `tests/terminal.ps1` covers the matching PowerShell
policy, pipeline/stream behavior and preference isolation. When pwsh is present,
the Unix terminal suite also runs it on a real PTY to cover same-console `*>`
redirection, even with PowerShell's ANSI rendering preference. Installers are tested
with quiet helpers; errors and failed-install retries must remain observable.

`tests/powershell-profile.ps1` checks the tracked PowerShell profiles and the
oh-my-posh theme without loading the live profile. It walks the AST to pin the
exact interactive guard and keep setup in its then-branch, checks agent-session
parity against `common/zsh/.zshrc`, keeps the conda stub lazy (removed before
the hook runs) and identical in both profiles, installs out of the profile and
Windows PowerShell 5.1 syntax ASCII-only. It unit-tests the history filter in
both directions, the eza glob expansion and the `$LASTEXITCODE` prompt wrapper,
parses and completes conda under Windows PowerShell 5.1, dot-sources the
PowerShell 7 profile in a redirected child with a fake home and a 60 s timeout,
and renders the primary, transient and secondary prompts with any inherited
oh-my-posh session removed and a temporary cache, failing on rendered template
errors (unknown segment types are not detectable in oh-my-posh 31.6).

`tests/shell-profile.sh` also resolves nvm's `default` alias forms against a
fake `NVM_DIR` under sh, dash, Bash and Zsh (including bash `failglob`), checks
that `custom/nvm.zsh` loads nvm with `--no-use`, and runs `common/zsh/.zshrc`
three levels deep with a fake `brew shellenv` and conda prepends: PATH, FPATH
and INFOPATH stay identical, nvm stays ahead in a fresh shell, a parent's order
(activated env or brew first) is kept, a conda-style activate and deactivate
keeps an entry already on PATH, and nothing assigns PATH after oh-my-zsh.
It also evaluates the fzf-tab tldr previews of `custom/fzf-tab.zsh`, as
fzf-tab does, with a fake C client (Homebrew's `tldr`, which takes only `-C`)
and a fake tlrc (only `--color always`): both must show the colored page, a
client's missing-page error must never reach the preview, and the C client
must never run without `TLDR_AUTO_UPDATE_DISABLED`, without which the real one
fetches a missing page from GitHub.

The day-zero bootstrap has four suites. `tests/bootstrap-manifest.sh`
unit-tests the sourced `lib/bootstrap/{manifest,platform,version}.sh` and runs
the standard-library validator `tests/test_bootstrap_manifest.py`, which checks
`config/bootstrap/`, the step headings of `docs/bootstrap.md`, the tool table
of `docs/dependencies.md` and the two identical project skills.
`tests/doctor.sh` and `tests/setup-host.sh` run the entry points under `env -i`
against fixture checkouts, homes and Homebrew prefixes with stubbed tools and
local clone remotes. Network commands outside `--online` fail the doctor
suite; `sudo`, `chsh`, `stow`, `apt-get`, `conda` and `git lfs` are tripwires in
the installer suite; find snapshots prove that the doctor and
`setup-host.sh --check` write nothing. `tests/doctor.sh` also runs the real
`./doctor.sh` with the real manifest against the test machine's own tools
(`--platform debian` and `--platform other` with `--tsv`, an empty temporary
`HOME`): every line must keep the TSV contract, the exit code must be 0 or 1,
and the home, `TMPDIR` and checkout must stay unchanged, so a runner whose
tools print unexpected versions or write state on `--version` fails CI. The
checkout scan skips `.git`, where any other git process may write meanwhile;
the fixture cases cover the doctor's own git. An empty home cannot show
writes that depend on state, so fixture fakes model them: gh writes its
device id unless `GH_TELEMETRY=0`, and the tldr C client refreshes a stale
page cache unless `TLDR_AUTO_UPDATE_DISABLED` is set.
`tests/bootstrap-windows.sh` runs `tests/bootstrap.ps1`, the Windows twins
against shims, wherever pwsh exists and prints a `SKIP:` line otherwise; the
Windows job runs that suite and the validator from `tests/run.ps1`. None of
them downloads anything or touches the runner's home. Fresh-machine runs are
the opt-in [end-to-end suite](#end-to-end-bootstrap-opt-in) below, which checks
the [acceptance checklist](bootstrap.md#acceptance-checklist) for real.

`tests/host-overlays.sh` sources the `wsl-ubuntu` and `lab-ubuntu` zsh and bash
overlays in a clean environment with a missing, a non-executable and a fake
Linuxbrew, so a shell started before Linuxbrew exists stays silent and the
`brew shellenv` line applies only once brew can run.

Run either entrypoint from any working directory. To check prerequisites only:

```sh
./tests/run.sh --ci --check-prerequisites
```

```powershell
pwsh -NoProfile -NonInteractive -File ./tests/run.ps1 -CI -CheckPrerequisites
```

`tests/run.ps1` without `-CI` also runs portable PowerShell behavior tests on
Linux/macOS, including actual confirmation prompts with a scripted host. It starts child processes with `-NoProfile`, isolating test mocks
and avoiding live profile side effects. The `-CI` switch requires native
Windows so an accidentally misplaced job cannot masquerade as native coverage.

Unix jobs also run `tests/unix-installer.sh`: a temporary checkout and local
bare remote exercise actual Git pull, actual Stow and applied-state recording.
The Windows entrypoint runs `tests/windows-installer.ps1` on native Windows,
using a disposable target for actual Git Bash helpers and NTFS links. POSIX
permission/inode assertions stay on Unix; NTFS/link behavior stays on Windows.

Ordinary hosted-runner tests do not establish OpenSSH network-logon symlink
trust or real Task Scheduler behavior; those remain explicitly scoped
environment checks, documented in `windows-installer.md` and
`update-contract.md`.

## End-to-end bootstrap (opt-in)

`tests/e2e/` runs the day-zero bootstrap for real, from a fresh home, on every
host overlay, the way a person following the [quick start](bootstrap.md#quick-start)
would, and checks the acceptance criteria below. It is opt-in: `./tests/run.sh`
never runs it (only the fast unit test `tests/e2e-harness.sh`, which drives the
harness against stubs), and neither does pre-commit. A run installs packages,
clones plugins and builds a login env, so it needs the network and takes from
ten minutes to an hour per host; [tests/e2e/README.md](../tests/e2e/README.md)
is the short how-to.

### Running it

```sh
./tests/e2e/run.sh lab-ubuntu              # one host, one container
./tests/e2e/run.sh -j 2 sherlock marlowe   # at most two containers at a time
./tests/e2e/run.sh all                     # the five Linux hosts, never mac or win
```

`run.sh [-j N] [--cache DIR] [--keep] [--out DIR] [--no-build] <host>... | all`
needs Docker and a clean source checkout (`E2E_ALLOW_DIRTY=1` overrides; the
container still clones `HEAD`, so only uncommitted `tests/e2e/` changes, which
the harness reads from the working tree, are exercised) that is a plain
clone: a linked `git worktree` or submodule checkout is refused with exit 2
(`run from a plain clone`), because the container mounts only the checkout
and such a checkout's `.git` is a file pointing outside it. Run it as a
regular user, never root: the image user is created with your uid so it owns
the mounted `/e2e/out` (and `useradd` refuses uid 0), and `--no-build` reuses
an existing image only after `id -u <user>` in a throwaway container shows
that user has your uid, since images are shared by everyone on the daemon. It
builds the host's image from `tests/e2e/docker/`, mounts the checkout read-only
at `/e2e/src`, runs `tests/e2e/inside.sh` in a fresh container as the host's
user under `bash -l`, and prints a final table `host result seconds out-dir`.
`-j` is capped at 2 (default 1). `--cache DIR` mounts package caches (apt,
dnf4's `/var/cache/dnf` on Rocky, dnf5's `/var/cache/libdnf5` on Fedora 44,
Homebrew, conda packages) from `DIR`, created as you before the run, so a
repeated run downloads less; it is off by default and stays off for
acceptance runs, which must install exactly what a fresh machine installs.
Outputs land under
`tests/e2e/out/<host>-<UTC timestamp>/` (git-ignored): `summary.tsv` (one
tab-separated row per step, `<n> <step> <pass|fail|skip|note> <seconds>
<detail>`), `steps/NN-<step>.log`, `env.txt` (kernel, `/etc/os-release`,
glibc, tool versions, the timeout binary and the expanded
`E2E_SNAPSHOT_PRUNE`), `log/wrappers.log`, `log/sudo.log`, `log/timeline` and
`snapshots/`. `--keep` leaves the container for `docker exec`. `mac` runs only
natively on Darwin with `E2E_NATIVE=1`, and `win` only through
`tests/e2e/run.ps1`; both happen in CI, below.

### Host matrix and fidelity

| Host | Image or runner | User and home | Flow |
| --- | --- | --- | --- |
| `lab-ubuntu` | `ubuntu:24.04` | `fridrichmethod`, `/home/fridrichmethod` | setup-host loop, `--host lab-ubuntu` |
| `wsl-ubuntu` | `ubuntu:24.04` with `WSL_DISTRO_NAME=Ubuntu` | the same | setup-host loop, `--host wsl-ubuntu` |
| `other` | `fedora:44` | the same | X-other-linux by hand, `--platform other` |
| `sherlock` | `rockylinux:9` plus EPEL Lmod, `linux/amd64` | `zyli2002`, `/home/users/zyli2002` | setup-host loop, `--host sherlock` |
| `marlowe` | `ubuntu:24.04` plus apt `lmod`, `linux/amd64` | `zyli2002`, `/users/zyli2002` | setup-host loop, `--host marlowe` |
| `mac` | the `macos-15` runner, natively | `runner`, `/Users/runner` | setup-host loop, `--host mac` |
| `win` | the `windows-2025` runner, natively | the runner user | `run.ps1`: the PowerShell twins, then `HW-stow` |

Each image has only what a fresh install of that kind has (Ubuntu and Fedora:
`git`, `curl`, `sudo` and certificates; the clusters: Lmod, `git`, `curl` and
the OS utilities), never what the bootstrap installs, and a home made by
`useradd -m`, so the `/etc/skel` rc files are there for H7-stow's `mv -n`
lines. The setup-host loop is `./setup-host.sh --host H --yes` after
`./doctor.sh --tsv` and `--check`, as [Running it with an agent](bootstrap.md#running-it-with-an-agent)
prescribes; the `other` flow installs the distribution packages with `dnf`,
takes `fetch_pinned` and `clone_listed` from the fenced block of
[Downloads and clones by hand](bootstrap.md#downloads-and-clones-by-hand) in
the clone itself, then follows the Other Linux quick start to a host-less
`./stow-all.sh`. What is faked, and what is only an approximation:

- `sudo`, `chsh` and `stow` are wrappers in `/usr/local/bin` that append every
  call, with the harness phase it ran in, to `log/wrappers.log` and then run
  the real tool; on the cluster images `sudo` is a denying wrapper, since no
  sudo exists there, as on the real clusters. The Ubuntu and Fedora images
  grant passwordless sudo and make it log to `log/sudo.log` through sudoers. A
  Homebrew or conda prefix prepended to PATH can shadow the wrappers; the sudo
  log and the behavioral signals below still cover those calls. On the `mac`
  runner the workflow installs the same three wrappers in `/usr/local/bin`
  with one `sudo install` before the run, refusing a runner that already has
  one of the three names there (nothing is installed there on the arm64 image;
  Homebrew is `/opt/homebrew`): `/etc/profile` and `/etc/zprofile` run
  `path_helper`, which rebuilds PATH from `/etc/paths` and appends the old
  entries afterwards, so `/usr/local/bin` is the one directory it keeps ahead
  of `/usr/bin`, and the login-shell, doctor-final and doctor-smoke steps
  still reach the wrappers (`/etc/paths.d` would not do: its entries land
  after `/etc/paths`). `inside.sh`'s own copy in `$E2E_OUT/bin` is reached
  only outside login shells.
- `wsl-ubuntu` is detected through `WSL_DISTRO_NAME` and `/mnt/wsl/Ubuntu`,
  not a Microsoft kernel: there is no Windows interop (`wslview`, the Windows
  credential helper) and no `/etc/wsl.conf`.
- `lab-ubuntu` has no desktop session (the `H1-fcitx5` gui block is skipped)
  and a Linuxbrew the user owns, so the shared-prefix `sudo` block of
  S2-brew-bundle never appears; the default tiers leave the desktop steps out.
- `other` approximates "another Linux" as Fedora alone.
- `sherlock` and `marlowe` have Lmod but no site modulefiles and no Slurm:
  `SLURM_JOB_ID=424242` and `CONDA_PKGS_DIRS` are exported once the `H2-alloc`
  block has been printed; `SCRATCH` points at a writable directory in the
  image once it is set: on `sherlock` the fake site profile exports it (with
  the group paths) from the first login shell, on `marlowe` nothing sets it
  before the stow, as on the real cluster, and the overlay then exports
  `/scratch/m000191`, which the image creates writable, so `E2E_ALLOC_ENV`
  names that path literally; the `S2-modules` block (`ml nodejs/24.13.0`, the
  AI CLI modules) is skipped, and there is no Kerberos. The login env is built
  for real, from conda-forge, inside the container.
- `mac` runs on a GitHub runner that already has the Xcode Command Line Tools,
  Homebrew and many formulae, so `H1-xcode-clt` and `H1-homebrew` are found
  done and never exercised, and S2-brew-bundle installs less than on a blank
  Mac. sudo is passwordless there and keeps no log, so only the wrappers
  (installed in `/usr/local/bin` by the workflow, above) and the behavioral
  signals are audited, and the home snapshots prune
  `$HOME/work`, `$HOME/Library`, the runner's own agent directory
  `$HOME/runners` (its `_diag` logs are appended throughout the job, so a
  snapshot that watched it would fail every no-write step) and the
  preinstalled `$HOME/hostedtoolcache`; `env.txt` records the expanded list,
  so a reader of the artifact sees what the no-write checks did not watch.
  The runner ships no `timeout` or `gtimeout`, so the per-command limits of
  `tests/e2e/lib/common.sh` (45 minutes per block line, 60 per apply, 15 per
  read-only run) are inert there, `env.txt` records `timeout=none`, and the
  job's 90-minute `timeout-minutes` is the backstop: a hang shows up as the
  job's cancel, with the step named by `log/timeline` and the partial
  `steps/NN-<step>.{out,err}` rather than by a `summary.tsv` row.
- `win` runs every step, not only `HW-stow`, under the runner's elevated
  token, where the Native Windows quick start has the person elevate only for
  `.\stow-all.ps1 win`: `winget import` leaves each installer's scope to that
  token (`winget.json` pins none), `oh-my-posh font install` puts fonts where
  an elevated oh-my-posh puts them, and the non-elevated untrusted-link
  warn-or-repair path of `stow-all.ps1` is never exercised. A winget that
  needs `Repair-WinGetPackageManager` first is recorded as a deviation.
  `run.ps1` asserts criteria 1 to 4 and 6 (the doctor, the no-write `-Tsv` and
  `-Check` runs, a second `-Yes` that applies nothing, a clean clone after
  every step, a silent load of the stowed profile); criterion 5's four audits
  have no Windows counterpart, since there are no wrappers and no sudo log
  there, and `HW-stow` is judged by its own evidence instead (below). `pwsh`
  is absent from the development machines, so the Windows driver's first
  execution is the CI job.

### HUMAN-block policy

The harness plays the agent of [Running it with an agent](bootstrap.md#running-it-with-an-agent)
with the person's approvals scripted, keyed on the block's step id and kind.
`# ` lines are notes; every other line runs as its own command (`bash -c` from
`$HOME`, stdin closed, a 45-minute timeout where coreutils `timeout` or
`gtimeout` exists, which is the Linux images; the `mac` runner has neither,
`env.txt` records `timeout=none` and only the job's 90-minute
`timeout-minutes` bounds the run) under `E2E_PHASE=human:<id>`.

| Block | Action |
| --- | --- |
| `H1-apt-core`, `H1-locale`, `H1-linuxbrew`, `H1-homebrew` (`sudo`) | every command line, in order |
| `S5-claude` (`inspect`) | only the digest-gate line, `printf '%s  %s\n' <sha256> <path> \| sha256sum -c --status - && bash <path>` |
| `H7-stow` (`judgment`) | only its `mv -n` lines and the single `PATH=... stow-all.sh <host>` line; any other command line in that block fails the run |
| `H2-alloc` (`alloc`) | never run: recorded, and the fake allocation variables are exported for the rest of the run |
| `S2-modules`, `H7-sync-skills`, `H7-doctor` (`judgment`); `H7-auth` (`auth`); `H1-fcitx5` (`gui`); `H7-chsh` (`chsh`) | skipped and recorded as `skip`: non-blocking, and a person's to do |
| `H1-xcode-clt`; any `S2-brew-bundle` block (the conflict judgment or the shared-prefix `sudo`); `S4-nvm`; `X-recovery`; any other id or kind | **fail**, with the block's text in the detail |

A blocking block the harness refuses is a finding, not something to work
around: a fresh machine should never print it. The loop reruns setup-host after
each block, at most eight times; exit 0 ends it, exit 3 without a runnable
block fails as "no progress", and exit 1 or 2 fails naming the step.

On `win`, `run.ps1` plays the same agent against `setup-host.ps1 -Host win
-Yes` (again at most eight runs, exit 3 without a runnable block failing as
"no progress"), with the policy of `tests/e2e/lib/blocks.ps1`, keyed on the
same `<id>:<kind>`:

| Block | Action |
| --- | --- |
| `HW-stow` (`judgment`) | only its single `& '<clone>\stow-all.ps1' win` line, run by a child `pwsh -NoProfile -NonInteractive` from `$HOME` under the runner's elevated token; a block with any other command line, or naming a path other than the clone's `stow-all.ps1`, fails the run. The step passes only when `stow-all.ps1` recorded its applied state and printed no `WARNING:` line |
| `HW-clone` (`gui`) | **fail**: it blocks the flow (setup-host has not accepted the clone), and only the person can turn on Developer Mode |
| `HW-execution-policy`, `HW-auto-stow-task`, `HW-wsl` (`judgment`); `HW-ssh-agent` (`sudo`); `HW-auth` (`auth`) | skipped and recorded as `skip`: non-blocking, and the person's, since the harness neither decides a security setting, grants a task standing elevation, installs WSL, starts a service nor signs in |
| any other id or kind | **fail**, with the block's text in the detail |

The Windows login-shell step then loads the stowed profile in a child `pwsh`
started without `-NoProfile`, which must exit 0 and print nothing, and
`E2E_SNAPSHOT_PRUNE` is `;`-separated there, since Windows paths hold drive
letters and colons.

### Acceptance criteria

The six criteria, and how `inside.sh` asserts each; every failure names its
step in `summary.tsv`:

1. **The doctor passes.** From a login environment (`bash -lc 'exec zsh -il
   -c ...'`), `./doctor.sh --host H` exits 0 for the default tiers, then
   `--smoke` exits 0 (`--platform other` on `other`).
2. **The read-only modes write nothing.** Around `./doctor.sh --tsv` and
   `./setup-host.sh --host H --check`, `TMPDIR` is a fresh empty directory
   that must stay empty with its mtime unchanged, and `find "$HOME" -newer
   <marker>` (pruning `~/dotfiles/.git`) must print nothing, with the entry
   count unchanged.
3. **A second apply is a no-op.** After the loop, `./setup-host.sh --host H
   --yes` exits 0, prints no `<id> done applied:` line, and the home snapshot
   shows nothing newer.
4. **The checkout stays clean.** `git -C ~/dotfiles status --porcelain` is
   empty after every step; a dirty tree fails that step.
5. **Nothing privileged or stateful ran outside a HUMAN block**, by four
   signals: (a) every `log/wrappers.log` line's phase starts with `human:` or
   `negative:`, except a bare `stow --version` or `stow -V`, the doctor's
   `tools.tsv` probe, which is logged on every doctor run but is not a
   finding (the `negative:root-refused` sudo is legitimate); (b) where sudo
   logs (`E2E_SUDO=yes`, the Linux images: macOS keeps no sudo.log), every
   `log/sudo.log` timestamp falls inside a `human:*` or `negative:*` window of
   `log/timeline`, and every non-indented line of that log is such a
   timestamped entry, so a log in a shape the audit cannot parse fails it
   instead of passing unread; (c) the stow state file
   (`git rev-parse --git-path dotfiles-sync-unix`) and the `~/.zshrc` link
   exist only after `human:H7-stow`; (d) the login shell from `getent passwd`
   (`dscl` on macOS) is the same at the start and the end, and the sha256 of
   `~/.bashrc`, `~/.profile`, `~/.bash_profile`, `~/.zshrc`, `~/.zshenv` and
   `~/.zprofile` (those that exist) does not change across any non-human step;
   a change during a `human:*` step is recorded as a note.
6. **A login shell starts clean.** Under `env -i` with the system PATH,
   `bash -lc 'exec <zsh> -il -c exit'` (the login env's zsh on hpc) exits 0
   with empty stdout and empty stderr, apart from what is not a message: on
   stdout, terminal control sequences (Fedora's stock `/etc/zlogout` runs
   `clear` when a login shell exits); on stderr, the two lines only the
   missing terminal causes, the `.zshrc`'s `stty -ixon` complaint and fzf's
   `--zsh` integration restoring its saved options
   (`(eval):1: can't change option: zle`), both silent in a real terminal;
   any `[oh-my-zsh]`, `[dotfiles]`, `[awesome-skills]`, `not found`,
   `permission denied` or `[error]` line is reported verbatim.

Each host also runs its negative cases as separate steps (`negative:<token>`):
the platform refusals (`--host wsl-ubuntu --check` in the lab container and
the reverse, `env -u LMOD_DIR -u BASH_ENV` on a cluster (Lmod's profile.d
exports `BASH_ENV`, which every bash script sources on start and which
re-exports `LMOD_DIR`), `sudo -n ./setup-host.sh` as root, each exit 2), `alloc-first` (the first hpc apply exits 3 and prints the
`H2-alloc` block) and `common-only` (after the host-less stow, `./doctor.sh`
exits 0 and warns common-only, and `./setup-host.sh` without `--host` exits 2).

### Harness code rules

Harness variables use the `E2E_` prefix only (`E2E_HOST`, `E2E_REV`,
`E2E_SRC`, `E2E_OUT`, `E2E_PHASE`, `E2E_NATIVE`, `E2E_SANDBOX_HOME`,
`E2E_ALLOW_DIRTY`, `E2E_KEEP`, `E2E_CACHE_DIR` and the keys of
`tests/e2e/hosts/<host>.env`); never a new `DOTFILES_*` or `AWESOME_SKILLS_*`
name, which `tests/test-entrypoints.sh` would require every test entry point
to unset. Every `*.sh` under `tests/` and `tests/e2e/` must run under Bash 3.2
(`/bin/bash` on the macOS runner): no associative arrays, `mapfile`, `${x,,}`,
`declare -n`, `|&` or `&>>`. What runs natively on that runner (`inside.sh`,
`tests/e2e/lib/*.sh`, the wrappers) also uses no here-documents or process
substitution and only BSD-safe utilities: no `find -printf`, `stat -c`,
`readlink -f`, `sed -i` without a suffix or `grep -P`; GNU `date -d` appears
only in the sudo.log audit (`e2e_audit_sudo_log` in `tests/e2e/lib/assert.sh`),
behind a probe that turns the audit into a skip row where it is missing
(macOS, which keeps no sudo.log anyway). GitHub's
runners ignore SIGPIPE, as `tests/run.sh` does with `trap '' PIPE`, so under
`set -o pipefail` no pipe may end in an early-exiting reader (`grep -q`,
`head`, a single `read`) while its writer keeps writing: use
`grep ... >/dev/null`, a `sed -n` that reads everything, or a temp file. The
harness never writes inside the clone it tests.

### CI

`.github/workflows/bootstrap-e2e.yml` runs the suite on demand
(`workflow_dispatch` with `hosts`, a comma list or `all`, and `cache`), every
Sunday at 06:00 UTC, and on a push to an `e2e-ci/**` branch; it is not part of
`ci.yml`. A `plan` job turns the host list into the matrix, because a job-level
`if` cannot see the `matrix` context; the five Linux hosts then run in
containers on `ubuntu-24.04` with `fail-fast: false` and 90 minutes each,
`mac` natively on `macos-15` (`E2E_NATIVE=1 ./tests/e2e/run.sh mac`) and `win`
on `windows-2025` (`./tests/e2e/run.ps1`), the only places those two run. Each
job uploads `tests/e2e/out/**` as the artifact `bootstrap-e2e-<host>`, pass or
fail; one run per ref at a time, without cancelling one in progress. The
`cache` input mounts a scratch directory under the runner's temp, which no
later run sees, so it only saves downloads within one job; acceptance runs
leave it off.

### Real clusters

Sherlock and Marlowe cannot run the containers (no Docker on a login node, and
`E2E_NATIVE` is honoured only on macOS), so the owner runs the
[Sherlock and Marlowe quick start](bootstrap.md#sherlock-and-marlowe) by hand
once per cluster and checks the criteria above the same way. Log in without
the RemoteCommand (`ssh sherlock-plain`, `ssh marlowe-plain`), then:

```sh
uname -a; cat /etc/os-release; ldd --version | head -n 1   # record these with the run
git clone --recurse-submodules https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles && export DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0
./doctor.sh --host sherlock --tsv                           # or marlowe; exit 1 is expected now
marker=$(mktemp) && sleep 1
./setup-host.sh --host sherlock --check                     # exit 3
find "$HOME" -path "$HOME/dotfiles/.git" -prune -o -newer "$marker" -print   # must print nothing
./setup-host.sh --host sherlock                             # light steps; exit 3 at H2-alloc
sh_dev -t 1:00:00                                           # Marlowe: srun --time=1:00:00 --pty bash -l
cd ~/dotfiles && export DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0
echo "$SCRATCH"                                             # Sherlock: the site sets it; Marlowe: empty before the stow
export CONDA_PKGS_DIRS="$SCRATCH/.cache/conda/pkgs"         # Sherlock
# Marlowe: export CONDA_PKGS_DIRS="/scratch/m000191/.cache/conda/pkgs/$USER"   # the overlay's value; no site SCRATCH yet
./setup-host.sh --host sherlock                             # builds the login env; exit 3 at H7-stow
exit                                                        # back to the login node
# H7-stow block: its mv -n lines, then PATH="$HOME/micromamba/envs/login/bin:$PATH" ./stow-all.sh sherlock
./setup-host.sh --host sherlock                             # exits 0 and prints no "done applied:" line
git -C ~/dotfiles status --porcelain                        # empty, here and after every step above
exec "$HOME/micromamba/envs/login/bin/zsh" -l               # starts without an error line
./doctor.sh --host sherlock && ./doctor.sh --host sherlock --smoke
```

Nothing but the HUMAN blocks ran `stow` or edited an rc file when the stow
state file and the `~/.zshrc` link appear only after the H7-stow line and
`getent passwd "$USER"` still names the same login shell at the end. Then fill
the run's row of the [acceptance table](bootstrap.md#acceptance-checklist):
the date, the OS and glibc from the first line, the result and any notes,
adding a row for Marlowe.
