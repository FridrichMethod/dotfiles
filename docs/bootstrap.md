# Bootstrapping a host

## What this is

`./doctor.sh` and `./setup-host.sh` (on native Windows, `.\doctor.ps1` and
`.\setup-host.ps1`) are the explicit, fail-closed entry points that take a
fresh machine to the state the stowed configs assume. The doctor is read-only
and offline: for every tool it reports `ok`, `missing` or `outdated` and names
the step below that fixes it. The installer runs pinned, checksummed steps that
need no root, and prints everything that needs a person (sudo, a browser login,
a GUI dialog, a Slurm allocation, a login-shell change, a judgment call) as a
HUMAN block instead of running it. Profiles, `./stow-all.sh` and the login
update hooks never install a tool; only these entry points do, and only when
you run them. (The skill-library hook fetches skills, not tools, and is on by
default once stowed; see [H7-sync-skills](#h7-sync-skills-skill-library-sync).)

[`config/bootstrap/`](../config/bootstrap/) is the single pinned source for
everything they install: [`tools.tsv`](../config/bootstrap/tools.tsv) (what the
doctor checks: tier, hosts, probe, version floor, and the step that fixes each
row), the tiered Brewfiles in [`brew/`](../config/bootstrap/brew/), the apt
lists in [`apt/`](../config/bootstrap/apt/),
[`hpc-login-env.yml`](../config/bootstrap/hpc-login-env.yml),
[`winget.json`](../config/bootstrap/winget.json),
[`git-clones.tsv`](../config/bootstrap/git-clones.tsv) (commit-pinned) and
[`installers.tsv`](../config/bootstrap/installers.tsv) (URL plus sha256). This
playbook links those files instead of repeating their pins.
`tests/bootstrap-manifest.sh` validates them, checks that this file has exactly
one `### <step-id>:` heading per step, and checks that
[dependencies.md](dependencies.md#day-zero-tools) lists every tool.

## Quick start

Every platform runs the same sequence: get git (and, if you want an agent to
drive the rest, one agent CLI), clone with submodules to `~/dotfiles`, diagnose,
preview, apply, handle the HUMAN blocks, stow, start a login shell, and finish
with the smoke test. Pick the host overlay yourself (`mac`, `wsl-ubuntu`,
`lab-ubuntu`, `sherlock`, `marlowe`, `win`); nothing guesses it.

> **Ordering trap: oh-my-zsh must exist before the first `./stow-all.sh`.**
> Stow runs with `--no-folding`, so it creates a real `~/.oh-my-zsh/custom/`
> directory; after that, oh-my-zsh can no longer be cloned into `~/.oh-my-zsh`
> and zsh aborts where `.zshrc` sources `oh-my-zsh.sh`. `./setup-host.sh` clones
> it in [S3-clones](#s3-clones-oh-my-zsh-theme-and-plugin-clones), before you
> stow, and `./stow-all.sh` refuses to stow the zsh package until
> `~/.oh-my-zsh/oh-my-zsh.sh` exists (`DOTFILES_STOW_WITHOUT_OH_MY_ZSH=1`
> overrides that). If stow ran first, use the first recipe in
> [X-recovery](#x-recovery-recovery-recipes).

GNU Stow is not on your PATH before the first stow: it comes from Homebrew on
macOS, Linuxbrew on Ubuntu and the login env on hpc, and each of those reaches
PATH only through the stowed rc files. `./setup-host.sh` adds them to its own
PATH, never to yours. So the first `./stow-all.sh` runs with a one-shot `PATH=`
prefix: the H7-stow block prints it as one line, ready to run, and
[H7-stow](#h7-stow-stow-the-dotfiles) lists it per host. Stow also never
replaces a regular file, and a fresh Linux home already has `~/.bashrc` and
`~/.profile` from `/etc/skel` (RHEL-family clusters also `~/.bash_profile`):
the block lists each such file with an `mv -n` line that moves it aside, to
run before the stow line. Never use `stow --adopt`, which would overwrite the
tracked copies with them.

Keep the login hooks quiet while provisioning, in every shell you use for it:
`export DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0`. Otherwise the
first interactive shell pulls the checkout and starts the unpinned skill sync
in the middle of the bootstrap. The export reaches only the shells that inherit
it: once you have stowed, a new terminal, a new login or an `ssh sherlock` from
a workstation starts without it and runs the skill sync, so decide on
[H7-sync-skills](#h7-sync-skills-skill-library-sync) before you open one.

`./setup-host.sh` exits 3 while work remains: a blocking HUMAN step is pending,
or automatic steps are still to apply. [H7-stow](#h7-stow-stow-the-dotfiles)
blocks, so re-run it after each block until H7-stow is the only one still
blocking, stow with the line its block prints, and run it once more; then it
exits 0 and reprints only the non-blocking blocks (login shell, sign-in, skill
sync, the final doctor run). `--check` exits 3 whenever a step is still to do,
so a `--check` that exits 0 has nothing left to apply.

### macOS

```sh
xcode-select --install          # H1-xcode-clt: git comes with the Command Line Tools (GUI dialog)
git clone --recurse-submodules https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles
export DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0
./doctor.sh --host mac
./setup-host.sh --host mac --check
./setup-host.sh --host mac      # exit 3: run the printed H1-homebrew sudo block yourself
./setup-host.sh --host mac      # again after each block, until only H7-stow still blocks
PATH="/opt/homebrew/bin:$PATH" ./stow-all.sh mac    # H7-stow (Intel: PATH="/usr/local/bin:$PATH")
./setup-host.sh --host mac      # exits 0 now
# H7-sync-skills: decide before you open a new terminal
exec zsh -l
./doctor.sh --host mac --smoke
```

An agent CLI before Homebrew exists: download Claude Code's installer, read it,
then run it (`f=$(mktemp) && curl -fsSL --proto '=https' -o "$f" https://claude.ai/install.sh && less "$f"`,
then `bash "$f"`). Otherwise skip it; the `ai` tier installs the
`claude-code` and `codex` casks.

### Ubuntu and WSL

For `wsl-ubuntu`, first create the distribution from Windows with the literal
name `Ubuntu` ([HW-wsl](#hw-wsl-wsl-distribution), which also covers the
`/etc/wsl.conf` judgment) and work inside it, in its own clone. For
`lab-ubuntu`, start from a desktop session.

```sh
sudo apt-get update
sudo apt-get install -y git curl
git clone --recurse-submodules https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles
export DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0
./doctor.sh --host wsl-ubuntu                 # or lab-ubuntu
./setup-host.sh --host wsl-ubuntu --check
./setup-host.sh --host wsl-ubuntu             # exit 3: sudo blocks H1-apt-core, H1-linuxbrew (and H1-locale)
./setup-host.sh --host wsl-ubuntu             # again after each block (later the S5-claude inspect block),
                                              # until only H7-stow still blocks
# H7-stow: first its mv -n lines (the /etc/skel ~/.bashrc and ~/.profile), then:
PATH="/home/linuxbrew/.linuxbrew/bin:$PATH" ./stow-all.sh wsl-ubuntu   # H7-stow
./setup-host.sh --host wsl-ubuntu             # exits 0 now
chsh -s "$(command -v zsh)"                   # H7-chsh, asks for your password
# H7-sync-skills: decide before you open a new terminal
exec zsh -l
./doctor.sh --host wsl-ubuntu --smoke
```

`lab-ubuntu` adds one sudo block (H1-gh-apt-repo) and one gui step (H1-fcitx5:
`im-config -n fcitx5` as you, then a relogin); add `--tier all` to get kitty and
the Nerd Font. An agent CLI first, if wanted: the Claude Code installer as on
macOS.

### Sherlock and Marlowe

No sudo, no Homebrew, no `chsh`. Log in without the RemoteCommand
(`ssh sherlock-plain` / `ssh marlowe-plain` from a stowed workstation, or
`ssh <SUNetID>@login.sherlock.stanford.edu`); `ssh sherlock` execs the login-env
zsh and fails until [S2-login-env](#s2-login-env-hpc-login-environment) exists.

```sh
cat /etc/os-release; ldd --version | head -n 1     # P0-preflight: record OS and glibc
git clone --recurse-submodules https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles
export DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0
./doctor.sh --host sherlock                        # or marlowe
./setup-host.sh --host sherlock --check
./setup-host.sh --host sherlock                    # light steps on the login node; exit 3 at H2-alloc
sh_dev -t 1:00:00                                  # H2-alloc; Marlowe: an interactive Slurm job
cd ~/dotfiles && export DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0
export CONDA_PKGS_DIRS="$SCRATCH/.cache/conda/pkgs"  # Marlowe: "$SCRATCH/.cache/conda/pkgs/$USER"
./setup-host.sh --host sherlock                    # builds the login env inside the job; exit 3 at H7-stow
exit                                               # back to the login node
# H7-stow: first its mv -n lines (the /etc/skel ~/.bashrc and ~/.bash_profile), then:
PATH="$HOME/micromamba/envs/login/bin:$PATH" ./stow-all.sh sherlock   # H7-stow
./setup-host.sh --host sherlock                    # exits 0 now
# H7-sync-skills: decide before the next login or `ssh sherlock`
exec "$HOME/micromamba/envs/login/bin/zsh" -l
./doctor.sh --host sherlock --smoke
```

`stow` lives in the login env, which is on PATH only once the overlay is
stowed, hence the one-shot `PATH=` prefix. The `CONDA_PKGS_DIRS` line puts
micromamba's package cache where the stowed overlay will put it, under
`$SCRATCH`, instead of `~/micromamba/pkgs` in your home quota; the env itself
stays in your home. From then on `ssh sherlock` from a workstation lands in that
zsh. Agent CLIs come from modules
([S2-modules](#s2-modules-hpc-modules-and-manual-ai-clis)), never from a
long-running agent on a login node.

### Native Windows

Clone onto NTFS, not into WSL. In Windows PowerShell or Terminal:

```powershell
# Settings > System > For developers > Developer Mode: On (HW-clone)
winget install --id Git.Git -e
winget install --id Microsoft.PowerShell -e
# open a new PowerShell 7 (pwsh) window, then:
git clone -c core.symlinks=true --recurse-submodules https://github.com/FridrichMethod/dotfiles.git $HOME\dotfiles
cd $HOME\dotfiles
$env:DOTFILES_AUTO_UPDATE = '0'; $env:AWESOME_SKILLS_AUTO_UPDATE = '0'
.\doctor.ps1 -Host win
.\setup-host.ps1 -Host win -Check
.\setup-host.ps1 -Host win      # exit 3 until HW-stow is done
# in an elevated PowerShell 7 (Run as administrator), from $HOME\dotfiles:
.\stow-all.ps1 win
# open a new terminal, then from $HOME\dotfiles:
.\setup-host.ps1 -Host win      # exits 0 now; prints the non-blocking HW blocks
.\doctor.ps1 -Host win
```

The remaining Windows steps are HUMAN: execution policy, the optional
automatic-stow task, the ssh-agent service, WSL and authentication (`HW-*`
below; `.\setup-host.ps1 -PrintManual` prints them all). An agent CLI first, if
wanted: `winget install --id Anthropic.ClaudeCode -e`.

### Other Linux

There is no Fedora, Arch or generic Ubuntu overlay, and `./setup-host.sh` takes
only `--host`. Stow `common/` only, install packages yourself, and do the four
platform-neutral setup steps by hand
([X-other-linux](#x-other-linux-other-linux-distributions)). Paste `clone_pinned`
and `fetch_pinned` from [Pinned artifacts by hand](#pinned-artifacts-by-hand)
into your shell first:

```sh
# with your package manager: git zsh curl rsync tar file tmux man, python3 >= 3.11, GNU Stow >= 2.3.1,
# and fzf, zoxide, eza, fd and bat at the floors in config/bootstrap/tools.tsv
git clone --recurse-submodules https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles
export DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0
./doctor.sh --platform other
for id in $(awk -F '\t' '/^#/ { next } !h { h = 1; next } { print $1 }' config/bootstrap/git-clones.tsv); do
    clone_pinned "$id" || break                                    # S3-clones, oh-my-zsh first
done
f=$(fetch_pinned bat-theme) && d="$(bat --config-dir)/themes" && mkdir -p "$d" &&
    cp "$f" "$d/Catppuccin Mocha.tmTheme" && bat cache --build    # S3-bat-theme
mkdir -p ~/.vim/undo ~/.vim/tmp                                    # S3-dirs
./setup-sync.sh                                                    # S4-setup-sync
./stow-all.sh                              # H7-stow without a host argument: common only
# H7-sync-skills: decide before you open a new terminal
exec zsh -l
./doctor.sh --platform other --smoke
```

## Contract

### doctor.sh

```text
./doctor.sh (--host H | --platform P) [--tier LIST] [--tsv] [--quiet] [--online] [--smoke]
./doctor.sh --list | --help
```

| Flag | Meaning |
| --- | --- |
| `--host H` | `mac`, `wsl-ubuntu`, `lab-ubuntu`, `sherlock` or `marlowe` (`win` is refused; use `doctor.ps1`). Without it: `DOTFILES_HOST`, else the host `./stow-all.sh` recorded for this home and kernel. Never guessed |
| `--platform P` | `macos`, `debian`, `hpc` or `other`: no overlay, only rows whose hosts are `all` or `unix` |
| `--tier LIST` | Comma list of `core`, `cli`, `ai`, `desktop`, `contributor`, `host`, or `all`. Default `core,cli,ai`; rows in unselected tiers report `warn` and never fail the run |
| `--tsv` | Header `status id tier detail fix`, then 5 tab-separated columns per row; `fix` is `docs/bootstrap.md <step-id>` or `-` |
| `--quiet` | Only rows that are neither `ok` nor `skip`, then the summary |
| `--online` | Adds the only network probes: `gh auth status`, `claude auth status`, `codex login status`. A signed-out tool is `warn` and an absent one `skip`, so an exit 0 does not prove you are signed in |
| `--smoke` | Runs `DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0 zsh -ic true` and fails on `plugin .* not found`, `command not found` or `no such file` in its stderr. The one mode that may write (zsh's own caches) |
| `--list` | The rows and checks that apply, without probing |

Each line reads `[dotfiles] [<level>] <tier> <id>: <detail> (docs/bootstrap.md <step-id>)`,
for example `[dotfiles] [error] core fzf: 0.44.1 < 0.58.0 (docs/bootstrap.md S2-brew-bundle)`;
`ok` and `skip` rows end at the detail. Without `--tsv`, a summary line with
the count of each status closes the report.
Statuses are `ok`, `outdated`, `missing`, `warn`, `skip` and `human`. Besides the
`tools.tsv` rows the doctor runs structural checks: `locale`, `venv-sync`,
`submodule`, `stow-links`, `path-order`, `rc-pollution`, `omz-order` and
`nvm-homebrew`. The step it cites is the one that installs the tool on that
profile: `tools.tsv` names the Ubuntu or macOS step, and on `hpc` the apt and
Brewfile rows point at S2-login-env, nvm/Claude/Codex rows at S2-modules and
the locale check at P0-preflight; on `macos` the apt rows (git-lfs, tmux and
the macOS baseline tools) point at S2-brew-bundle; under `--platform other`
every apt, Homebrew, Brewfile, nvm, Claude, Codex and locale reference points
at X-other-linux; on `windows` they point at the `W1-*` and `HW-*` steps (git
at HW-clone).

| Exit | Meaning |
| --- | --- |
| 0 | No selected-tier row is `missing`, `outdated` or `human`; `warn` and `skip` never fail the run |
| 1 | A selected-tier row, from `tools.tsv` or a structural check, is `missing`, `outdated` or `human` |
| 2 | Usage error, invalid manifest (a malformed `tools.tsv` row, or a doc step without its `###` heading here), unknown host, or `--host win` |

### setup-host.sh

```text
./setup-host.sh [--host H] [--tier LIST] [--check] [--yes]
                [--only STEP]... [--skip STEP]... [--keep-going]
./setup-host.sh [--host H] --list | --print-manual
./setup-host.sh --help
```

| Flag | Meaning |
| --- | --- |
| `--host H` | `mac`, `wsl-ubuntu`, `lab-ubuntu`, `sherlock` or `marlowe`, with the same default as the doctor; `win` is refused (use `setup-host.ps1`). There is no `--platform`: another Linux does the setup steps by hand ([X-other-linux](#x-other-linux-other-linux-distributions)) |
| `--tier LIST` | As for the doctor; default `core,cli,ai` |
| `--check` | One plan line per step, `<step-id> <state> <detail>` with state `done`, `todo`, `human`, `skip` or `failed` (a step held back by a prerequisite shows as `todo` or `human`, its detail starting with `blocked by <step-id>` or `waiting:`), then the pending HUMAN blocks; no writes, no network. Exits 3 while any step is `todo` |
| `--yes` | Apply without asking. Without it, a run in a terminal asks before each automatic step, and a run whose stdin is not a terminal (agents, CI) exits 2 |
| `--only STEP`, `--skip STEP` | Run only, or skip, that step id from this file; both repeat |
| `--keep-going` | Continue past a failed step instead of stopping there; the run still exits 1 |
| `--list` | The steps for this host as TSV: `id`, `kind` (`auto` or a HUMAN kind), `tier`, `blocking` |
| `--print-manual` | Every HUMAN block for this host, pending or not (with the X-recovery block, which applies only when `~/.oh-my-zsh` exists without `oh-my-zsh.sh`), then exit 0 |

Every step runs check, plan, apply, verify; a satisfied step is skipped, so a
second run changes nothing. During apply it exports `DOTFILES_AUTO_UPDATE=0
AWESOME_SKILLS_AUTO_UPDATE=0 GIT_TERMINAL_PROMPT=0 NONINTERACTIVE=1
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1`
(and `HOMEBREW_BUNDLE_NO_LOCK=1`, so an older `brew bundle` writes no
`Brewfile.lock.json` into the checkout).
Before probing anything, both scripts prepend to their own PATH, when they
exist, the bin directory of the Homebrew they find (`/opt/homebrew`,
`/usr/local`, `/home/linuxbrew/.linuxbrew` or `~/.linuxbrew`), then
`~/.local/bin` (micromamba, codex, claude, kitty), then on hpc
`~/micromamba/envs/login/bin`, so the login env comes first on hpc, as in the
stowed shells, and elsewhere what setup-host linked into `~/.local/bin` wins.
(The stowed workstation shells run `brew shellenv` and the conda hook after
`~/.profile`, so there Homebrew and conda come before `~/.local/bin`.) A
pre-stow run thus sees what earlier steps installed; neither script writes
this to an rc file. The doctor's `path-order` check judges the PATH you
started it with: it warns when a command setup-host puts in `~/.local/bin`
(`claude`, `codex`, `micromamba`, `kitty`, `kitten`) is shadowed by another
executable of the same name earlier on PATH (two installs of one tool), the
login env on hpc excepted, or when `~/.local/bin` is missing.
Downloads use `curl -fsSL --proto '=https' --tlsv1.2 --retry 3` into a `.part`
file that must match the pinned sha256 before it is used; a mismatch deletes
it and fails the step. Without curl, pinned downloads fall back to `wget`,
whose digest check still holds; the unpinned `inspect` download needs curl,
because wget follows a redirect to plain http.

| Exit | Meaning |
| --- | --- |
| 0 | Done: every selected step is done or does not apply; non-blocking HUMAN blocks may still be printed |
| 1 | A step failed |
| 2 | Usage error or refusal: unknown host, `win`, run as root (or through sudo), a machine that is not that host (wrong kernel or distribution, a cluster host without `LMOD_DIR`, `wsl-ubuntu` outside WSL, `lab-ubuntu` inside WSL), no terminal without `--yes`, invalid manifest. `--list` and `--print-manual` skip the machine check |
| 3 | Work remains: a blocking HUMAN step is pending, or automatic steps are still to apply (under `--check`, after a declined prompt, or while they wait on a HUMAN step); handle the printed blocks and run it again |

`--list` shows which HUMAN steps block. A pending blocking step (Xcode CLT,
Homebrew, apt packages, Linuxbrew, the Slurm allocation, the Claude Code
installer, stow) holds back the steps that need it and makes the run exit 3.
A prerequisite you `--skip` or decline at the prompt holds back its HUMAN
dependents too (`H7-stow human blocked by S2-brew-bundle (skipped)`); one that
`--tier` or `--only` leaves out does not. Non-blocking blocks (locale, the gh
apt repository, fcitx5, site modules, `chsh`, sign-in, skill sync, the final
doctor run) are printed but leave the exit code alone. Since H7-stow blocks,
every run before the first stow exits 3.

The Windows twins take the same ideas as PowerShell parameters:
`.\doctor.ps1 [-Host win] [-Tier LIST] [-Tsv] [-Quiet] [-Online]` and
`.\setup-host.ps1 [-Host win] [-Tier LIST] [-Check] [-Yes] [-PrintManual] [-WhatIf]`
(`-Host` defaults to `win`). Both need PowerShell 7 and never elevate
themselves. `.\doctor.ps1` exits 0 when no selected-tier check is `missing`,
`outdated` or `human`, 1 when one is, and 2 for a usage error, another host or
an invalid manifest; its structural checks are `venv-sync`, `submodule` and
`core-symlinks`, and `-Online` reports a signed-out tool as `warn`, as on Unix.
`.\setup-host.ps1` exits 3 only while HW-clone or HW-stow is pending; the other
HW blocks are printed but leave the exit code alone. Its `-Check` prints only
plan lines (`<step-id> <done|todo|human|skip> <detail>`, a HUMAN step's detail
ending in `blocks completion` or `does not block`) and uses the same codes, so
todo steps alone exit 0 there. A declined prompt, like a non-interactive run
without `-Yes`, exits 2 and changes nothing.

### HUMAN blocks

The installer prints, and never runs, these blocks on stdout:

```text
HUMAN-BEGIN H1-apt-core sudo
# docs/bootstrap.md H1-apt-core
sudo apt-get update
sudo apt-get install -y --no-install-recommends zsh git git-lfs ...
HUMAN-END
```

The first line names the step and the kind. Every other line up to
`HUMAN-END` is either a note or a command:

- A line that starts with `# ` is a note, shown to the person and never run
  (Unix blocks open with a `# docs/bootstrap.md <step-id>` note).
- Every other line is one self-contained command. It needs no shell variable,
  working directory or other shell state from another line, so each line can
  run as its own top-level command; scripts in the checkout are named by their
  full path. Run them in order, top to bottom: a later line can need a file or
  a cached credential that an earlier one left (the Homebrew block runs
  `sudo -v`, then the installer, then `sudo -k`).
- A line of the form
  `printf '%s  %s\n' <sha256> <path> | sha256sum -c --status - && <command>`
  (`shasum -a 256 -c --status -` on macOS) is a digest gate: `<command>` runs
  only while the file still has that sha256, so the file that was verified or
  read is the file that runs. It is the one place where a block chains two
  commands; run it as printed, as one command.

| Kind | Who runs it | Meaning |
| --- | --- | --- |
| `sudo` | On macOS and Linux, the person, or an agent after the person approves the block in chat. On Windows always the person: the block needs an elevated shell, and agents never elevate | Needs root: system packages, `/home/linuxbrew`, apt sources; on Windows, services |
| `auth` | The person | Browser or device-code login, passwords, keys, Kerberos tickets |
| `gui` | The person | A dialog, a Settings toggle or a relogin (Xcode CLT, Developer Mode, the fcitx5 session) |
| `alloc` | The person | A Slurm allocation; heavy work on hpc runs only inside one |
| `chsh` | The person | Changes the login shell and asks for the password |
| `inspect` | The person reads, then runs | A vendor script that cannot be pinned by digest: read it before it runs |
| `judgment` | The person decides | A choice with tradeoffs: stowing, the skill sync, site modules, the final doctor run, execution policy, WSL |

Any block whose note says it needs an elevated PowerShell (stow, the automatic
stow task, WSL, the ssh-agent service) is the person's to run, whatever its
kind.

### Guarantees

- `./doctor.sh` without `--smoke`, and `./setup-host.sh --check`, write nothing
  anywhere and make no network calls (`--online` adds only the three auth probes).
  The doctor never runs a tool whose version flag writes (the `brew`, `codex`,
  `nvim` and `pre-commit` rows are presence-only), finds fonts by file name
  instead of through `fc-list` (which creates fontconfig caches), and runs the
  `venv-sync` interpreter with `-I -B`, so it writes no bytecode.
- The installer never invokes `sudo`, `chsh`, `stow`, `./stow-all.sh`,
  `conda init`, `micromamba shell init` or `git lfs install`, and never edits an
  rc file. The only write it causes inside the checkout is `.venv-sync`, through
  `./setup-sync.sh`.
- No `curl | sh`: every script is downloaded to a scratch directory first, and
  only `inspect` rows (today just Claude Code's installer) have no digest. A
  HUMAN block runs a downloaded script only behind a digest gate: the pinned
  sha256, or for an `inspect` download the digest of the copy the person read,
  which later runs keep instead of downloading it again.
- Everything a person must do ends up in a HUMAN block; exit 3 means work
  remains: a blocking block is pending, or automatic steps are still to apply.

### Pinned artifacts by hand

The automatic steps below also list a manual equivalent. Those that download or
clone use these two helpers, which read the URL, digest or ref from
`installers.tsv` and `git-clones.tsv` instead of copying them here. Paste them
into the shell you are working in:

```sh
# fetch_pinned ID [ARCH]: download one installers.tsv row into a fresh temporary
# directory, check its sha256 and print the file's path. ARCH: $(uname -m).
fetch_pinned() {
    _row=$(awk -F '\t' -v id="$1" -v arch="${2:-any}" \
        '$1 == id && ($7 == arch || $7 == "any") { print; exit }' \
        "${DOTFILES_DIR:-$HOME/dotfiles}/config/bootstrap/installers.tsv")
    [ -n "$_row" ] || { echo "fetch_pinned: no row for $1 ${2:-any}" >&2; return 1; }
    _url=$(printf '%s\n' "$_row" | cut -f 3)
    _sum=$(printf '%s\n' "$_row" | cut -f 4)
    _dir=$(mktemp -d) || return 1
    _out=$_dir/$(basename "$_url")
    curl -fsSL --proto '=https' --tlsv1.2 --retry 3 -o "$_out" "$_url" || return 1
    if command -v sha256sum >/dev/null 2>&1; then _have=$(sha256sum "$_out"); else _have=$(shasum -a 256 "$_out"); fi
    _have=${_have%% *}
    if [ "$_sum" = - ]; then
        echo "fetch_pinned: $1 is unpinned (sha256 $_have, $(wc -c <"$_out") bytes); read it first" >&2
    elif [ "$_have" != "$_sum" ]; then
        rm -f "$_out"
        echo "fetch_pinned: $1 sha256 $_have, expected $_sum" >&2
        return 1
    fi
    printf '%s\n' "$_out"
}

# clone_pinned ID: make one git-clones.tsv row's clone the way S3-clones does.
clone_pinned() {
    _row=$(awk -F '\t' -v id="$1" '$1 == id { print; exit }' \
        "${DOTFILES_DIR:-$HOME/dotfiles}/config/bootstrap/git-clones.tsv")
    [ -n "$_row" ] || { echo "clone_pinned: no row for $1" >&2; return 1; }
    _dest=$(printf '%s\n' "$_row" | cut -f 2)
    _url=$(printf '%s\n' "$_row" | cut -f 3)
    _ref=$(printf '%s\n' "$_row" | cut -f 4)
    case $_dest in
        '$HOME/'*) _dest=$HOME/${_dest#'$HOME/'} ;;
        '$ZSH_CUSTOM/'*) _dest=${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/${_dest#'$ZSH_CUSTOM/'} ;;
        *) echo "clone_pinned: unsupported dest $_dest" >&2; return 1 ;;
    esac
    if [ -e "$_dest/.git" ]; then
        echo "clone_pinned: $_dest is already a clone; compare its HEAD with $_ref" >&2
        return 0
    fi
    if [ "$1" = oh-my-zsh ]; then
        git clone --depth=1 --branch "$_ref" -c core.eol=lf -c core.autocrlf=false \
            -c fsck.zeroPaddedFilemode=ignore -c fetch.fsck.zeroPaddedFilemode=ignore \
            -c receive.fsck.zeroPaddedFilemode=ignore -c oh-my-zsh.remote=origin \
            -c oh-my-zsh.branch="$_ref" "$_url" "$_dest"
    else
        git init -q "$_dest" && git -C "$_dest" remote add origin "$_url" &&
            git -C "$_dest" fetch --depth=1 origin "$_ref" &&
            git -C "$_dest" checkout -q --detach FETCH_HEAD
    fi
}
```

Per-architecture rows (`micromamba`, `codex`, `kitty`) need `"$(uname -m)"`
as the second argument of `fetch_pinned` (`x86_64` or `aarch64`).

## Running it with an agent

The project skill is `/dotfiles-bootstrap` in Claude Code
(`.claude/skills/dotfiles-bootstrap/`, invoked only on request) and
`$dotfiles-bootstrap` in Codex (`.agents/skills/dotfiles-bootstrap/`). Both are
short and send the agent here. The rules they follow:

- **Host.** The agent asks which overlay this machine is; it never infers one
  from the OS. A machine without an overlay is "other Linux": the doctor takes
  `--platform other`, and the setup steps are the manual ones in
  [X-other-linux](#x-other-linux-other-linux-distributions).
- **Quiet hooks.** Every command runs with
  `DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0`. The person's own new
  terminals do not inherit that; the agent raises
  [H7-sync-skills](#h7-sync-skills-skill-library-sync) before the stow.
- **Plan first.** `./doctor.sh --host H --tsv` and
  `./setup-host.sh --host H --check`, shown to the person, before any apply.
  The apply is `./setup-host.sh --host H --yes`, because an agent's shell has
  no terminal. It writes outside the clone (`~/.oh-my-zsh`, `~/.local`, `~/.nvm`)
  and needs the network, so a sandboxed agent asks to run it with broader
  permissions; approving that one command is expected.
- **Block lines.** Lines starting with `# ` are notes to show the person, not
  commands to run. Every other line is one self-contained command (no variable
  or directory carries over from another line), so the agent runs them in order,
  each as its own command.
- **`sudo` blocks** run only after the person approves the block in chat. Each
  command line is then run as one visible top-level shell command, exactly as
  printed: never wrapped in `sh -c`, never inside a script, never chained to
  another command. The one exception is a digest gate the block prints as a
  single line (`printf ... | sha256sum -c --status - && <command>`): run it as
  printed, as one command. If sudo would ask for a password and the agent's
  shell has no terminal, the person runs the block in their own terminal
  instead. On native Windows a `sudo` block needs an elevated shell, so it is
  always the person's.
- **`auth`, `gui`, `alloc` and `chsh` blocks** are handed to the person, who
  says when they are done. **`inspect`** blocks: the agent shows the script's
  digest, size and contents, then waits. It runs the block's digest-gated
  `bash <path>` line only after the person approves it in chat, as one visible
  top-level command, or leaves it to the person. **`judgment`** blocks: the
  agent explains the choice and lets the person make it.
- **Stow.** `./stow-all.sh H` writes under `~/.claude` and `~/.codex` (and
  links `~/.ssh`). `~/.claude` is a protected path whose writes Claude Code's
  auto mode cannot pre-approve, so the agent runs it only as its own visible
  top-level command that the person approves, or leaves it to the person. Never
  launder it through a wrapper script. Before the first stow, `stow` is not on
  PATH, so the agent runs the H7-stow block's lines exactly as printed: its
  `mv -n` lines first, if it has any (they move aside home files Stow would
  refuse; never `stow --adopt`), then the stow line, the one-shot `PATH=`
  prefix that [H7-stow](#h7-stow-stow-the-dotfiles) gives for the host and the
  clone's `stow-all.sh H`.
- **Exit 3** means work remains: a blocking HUMAN step is pending, or automatic
  steps are still to apply, and H7-stow blocks. The agent re-runs setup-host
  after each block until H7-stow is the only one left, then stows, then runs
  setup-host once more, which exits 0. A `--check` that exits 0 has nothing
  left to do.
- **Never** `git lfs install`, `gh auth setup-git`, `conda init`,
  `micromamba shell init`, the upstream oh-my-zsh installer, rc-file edits,
  commits or pushes. After each installer, `git -C ~/dotfiles status --porcelain`
  stays empty ([X-rc-protection](#x-rc-protection-rc-file-protection)).
- **Done** means `./doctor.sh --host H --smoke` exits 0. The agent reports what
  it installed, which HUMAN blocks remain and any failure with its
  `docs/bootstrap.md <step-id>` reference.

### Prompt for an agent started outside the clone

Paste this into Claude Code or Codex when the session does not start inside
`~/dotfiles` (the project skills only load inside the clone):

```text
Bootstrap this machine with my dotfiles, https://github.com/FridrichMethod/dotfiles.
1. If ~/dotfiles does not exist, clone it with
   git clone --recurse-submodules https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
   (native Windows: follow HW-clone in docs/bootstrap.md first). Work only inside ~/dotfiles.
2. Read ~/dotfiles/docs/bootstrap.md completely. It is the contract; follow it over your defaults.
3. Ask me which host this is: mac, wsl-ubuntu, lab-ubuntu, sherlock, marlowe, win,
   or another Linux (then follow X-other-linux). Never guess.
4. Run every command with DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0.
5. Run ./doctor.sh --host H --tsv and ./setup-host.sh --host H --check and show me the plan.
6. After I agree, run ./setup-host.sh --host H --yes. For each HUMAN block
   (lines starting with "# " are notes for me; every other line is one
   self-contained command, run in order):
   sudo: show it and wait for my approval, then run each command line as its own
   visible top-level command (never sh -c, never a script, never chained, except
   that a printed "printf ... | sha256sum -c --status - && ..." digest gate runs
   as printed, as one command);
   auth, gui, alloc, chsh: hand them to me and wait;
   inspect: show me the script's digest, size and contents and wait; run its
   digest-gated line only after I approve it, or leave it to me;
   judgment: explain the choice and let me decide.
7. Exit 3 means work remains (a blocking HUMAN step, or steps still to apply).
   Re-run setup-host after each block until H7-stow is the only one left. Ask
   me about H7-sync-skills, then run the H7-stow block's lines exactly as printed
   (any mv -n lines, then PATH prefix and stow-all.sh H; never stow --adopt),
   each only as its own visible command after I approve it. Re-run setup-host;
   it should exit 0.
8. Finish with ./doctor.sh --host H --smoke, then report what changed, what is
   still pending, and every failure with its docs/bootstrap.md step id.
Never run git lfs install, gh auth setup-git, conda init or micromamba shell init,
never edit rc files, and never commit or push.
```

## Phase 0: preflight

Each step below lists a read-only **Check**, the **Install** (exact commands,
or automatic via setup-host.sh), a **Verify**, and whether a **Human** is needed
and why.

### P0-preflight: Preflight

Applies to every host. Record what the machine is before installing anything:
OS release, architecture, glibc (conda-forge packages and vendor binaries each
have a minimum), the overlay the person chose, and a complete checkout.

- **Check:** `uname -sm; cat /etc/os-release 2>/dev/null || sw_vers; ldd --version 2>/dev/null | head -n 1; git -C ~/dotfiles submodule status`
- **Install:** clone to `~/dotfiles` with `--recurse-submodules` (the login
  hooks default to `DOTFILES_DIR=$HOME/dotfiles`); for an existing clone without
  submodules, `git -C ~/dotfiles submodule update --init --recursive`.
- **Verify:** no submodule line starts with `-`, and
  `ls -L ~/dotfiles/common/pymol/.pymolrc` resolves; the doctor's `submodule`
  check is `ok`. setup-host's P0-preflight line records the OS, architecture,
  glibc and detected platform, and warns about a missing submodule, a
  `DOTFILES_DIR` that names another checkout, or uncommitted changes in the
  checkout ([X-rc-protection](#x-rc-protection-rc-file-protection)).
- **Human:** yes (judgment: the person names the host overlay, and a clone
  outside `~/dotfiles` also needs `DOTFILES_DIR` exported; setup-host prints no
  block for this step)

On `sherlock` and `marlowe` the doctor's `locale` check points here: the
cluster provides its locales, so a missing `en_US.UTF-8` is the site's to fix
(there is no `sudo locale-gen`); record it with the OS release.

## Phase 1: host prerequisites

These need root or a GUI, so the installer only prints them.

### H1-xcode-clt: Xcode Command Line Tools

Applies to `mac`. Provides `git`, `make` and the compilers Homebrew needs;
`git`, `bash`, `zsh`, `curl`, `rsync`, `tar`, `file`, `col` and `man` are
macOS baseline (manual rows in `tools.tsv`).

- **Check:** `xcode-select -p`
- **Install:** `xcode-select --install`
- **Verify:** `xcode-select -p && git --version`
- **Human:** yes (gui: macOS opens an install dialog)

### H1-homebrew: Homebrew on macOS

Applies to `mac`. Uses the commit-pinned `homebrew` row in
[`installers.tsv`](../config/bootstrap/installers.tsv). A fresh Homebrew stays
off PATH until the stowed zsh loads oh-my-zsh's `brew` plugin, so `doctor.sh`
and `setup-host.sh` prepend the directory of the brew they find to their own
PATH. In a pre-stow shell where you run brew by hand, use
`eval "$(/opt/homebrew/bin/brew shellenv)"` (Intel: `/usr/local/bin/brew`) in
that shell only.

- **Check:** `test -x /opt/homebrew/bin/brew || test -x /usr/local/bin/brew`
  (running `brew --version` can rewrite Homebrew's `.git/describe-cache`, so the
  checks only look for the file)
- **Install:** `setup-host.sh` downloads and checks the script, then prints a
  sudo block with its path. Run its three command lines in order, in one
  terminal: `sudo -v` (non-interactive mode only works with sudo credentials
  already cached); then the digest gate
  `printf '%s  %s\n' <sha256> <path> | shasum -a 256 -c --status - && NONINTERACTIVE=1 /bin/bash <path>`,
  which runs the installer only while it still has the pinned sha256; then
  `sudo -k`. By hand: `f=$(fetch_pinned homebrew)`, then `sudo -v`, then
  `NONINTERACTIVE=1 /bin/bash "$f"` and `sudo -k` in the same terminal.
- **Verify:** `/opt/homebrew/bin/brew --version` (or `/usr/local/bin/brew`)
- **Human:** yes (sudo: the installer creates the Homebrew prefix and needs an
  administrator account)

Never paste the installer's "Next steps" `brew shellenv` lines into an rc file,
never `brew install openssh` (`mac/ssh` uses Apple's `UseKeychain`, which
Homebrew's OpenSSH rejects), and never `brew install nvm` (see
[S4-nvm](#s4-nvm-nvm-and-nodejs)).

### H1-apt-core: apt prerequisites

Applies to `wsl-ubuntu` and `lab-ubuntu`: the packages in
[`apt/common.txt`](../config/bootstrap/apt/common.txt) plus the host's
[`apt/wsl-ubuntu.txt`](../config/bootstrap/apt/wsl-ubuntu.txt) (wslu for
`wslview`, libnotify-bin for `notify-send`) or
[`apt/lab-ubuntu.txt`](../config/bootstrap/apt/lab-ubuntu.txt) (xclip,
wl-clipboard and the fcitx5 set). apt keeps the system pieces (zsh, git,
git-lfs, tmux, man, locales, build tools). The interactive tools come from
Linuxbrew because Ubuntu 24.04's apt is below the floors (fzf 0.44.1,
gh 2.45) and renames bat and fd to `batcat` and `fdfind`.

- **Check:** `grep -hv '^#' config/bootstrap/apt/common.txt config/bootstrap/apt/wsl-ubuntu.txt | xargs dpkg -s >/dev/null && echo ok`
  (use `lab-ubuntu.txt` on lab-ubuntu)
- **Install:** the printed sudo block, which is
  `sudo apt-get update` and then
  `sudo apt-get install -y --no-install-recommends` followed by every package of
  both lists.
- **Verify:** the check prints `ok`; doctor rows `zsh`, `git-lfs`, `tmux`, `col`
  and `man` are `ok`.
- **Human:** yes (sudo: installs system packages)

On `wsl-ubuntu`, Windows PATH entries are appended inside the distribution, so
also confirm that `command -v claude codex node` resolves under your Linux home
or `/home/linuxbrew`, not to a Windows-side shim under `/mnt/c`.

### H1-locale: en_US.UTF-8 locale

Applies to `wsl-ubuntu` and `lab-ubuntu`. `common/sh/.profile` exports
`LANG=en_US.UTF-8`; without the generated locale every shell warns.

- **Check:** `locale -a | grep -qix 'en_US.utf8' && echo ok`
- **Install:** `sudo locale-gen en_US.UTF-8` (printed sudo block)
- **Verify:** the check prints `ok`; the doctor's `locale` check is `ok`.
- **Human:** yes (sudo: writes the system locale archive)

### H1-linuxbrew: Linuxbrew

Applies to `wsl-ubuntu` and `lab-ubuntu`, after H1-apt-core (it needs
build-essential, curl, git, procps and file). Same pinned `homebrew` row as
macOS; on Linux it installs into `/home/linuxbrew/.linuxbrew`. The overlay rc
files guard their `brew shellenv` line, so shells stay quiet before it exists.

- **Check:** `test -x /home/linuxbrew/.linuxbrew/bin/brew && echo ok`
- **Install:** the printed sudo block, the same three lines as on macOS with
  `sha256sum -c --status -` in the digest gate. By hand:
  `f=$(fetch_pinned homebrew)`, `sudo -v`, then `NONINTERACTIVE=1 /bin/bash "$f"`
  and `sudo -k` in the same terminal.
- **Verify:** `/home/linuxbrew/.linuxbrew/bin/brew --version`; doctor row
  `linuxbrew` is `ok`.
- **Human:** yes (sudo: creates `/home/linuxbrew` and gives it to you)

Never append the installer's "Next steps" lines to `~/.bashrc` or `~/.zshrc`;
the overlay already has them.

### H1-gh-apt-repo: GitHub CLI apt repository

Applies to `lab-ubuntu` (row `gh-apt`): its `.gitconfig_local` uses
`!/usr/bin/gh auth git-credential` for github.com, so `/usr/bin/gh` must be the
current GitHub CLI from cli.github.com, not Ubuntu's older package, which
installs the same path. The doctor's `gh-apt` row and this step's check both
run `/usr/bin/gh --version` against the `gh-apt` floor in `tools.tsv`, so
Ubuntu's gh shows as `outdated` and the block stays pending. The Linuxbrew `gh`
stays first on PATH; both share `~/.config/gh`.

- **Check:** `/usr/bin/gh --version | head -n 1; apt-cache policy gh | grep -c cli.github.com`
- **Install:** the printed sudo block. setup-host first downloads the apt
  keyring through the `gh-apt` row of
  [`installers.tsv`](../config/bootstrap/installers.tsv), checks it against the
  sha256 GitHub publishes for it, and stages it under
  `~/.cache/dotfiles-bootstrap/gh-apt` (or
  `$XDG_CACHE_HOME/dotfiles-bootstrap/gh-apt`). The keyring holds GitHub's two
  signing keys, `2C6106201985B60E6C7AC87323F3D4EA75716059` and
  `7F38BBB59D064DBCB3D84D725612B36462313325` (`gpg --show-keys <file>` lists
  them). The block writes the source list as you, then installs the keyring
  with sudo only behind a digest gate on the pinned sha256; stop if that line
  fails. Each line stands alone:

  ```sh
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' "$(dpkg --print-architecture)" > ~/.cache/dotfiles-bootstrap/gh-apt/github-cli.list
  printf '%s  %s\n' <sha256> ~/.cache/dotfiles-bootstrap/gh-apt/githubcli-archive-keyring.gpg | sha256sum -c --status - && sudo install -D -m 0644 ~/.cache/dotfiles-bootstrap/gh-apt/githubcli-archive-keyring.gpg /etc/apt/keyrings/githubcli-archive-keyring.gpg
  sudo install -D -m 0644 ~/.cache/dotfiles-bootstrap/gh-apt/github-cli.list /etc/apt/sources.list.d/github-cli.list
  sudo apt-get update
  sudo apt-get install -y gh
  ```

  By hand: `f=$(fetch_pinned gh-apt)` checks the keyring's digest; then the
  lines above with `"$f"` as the keyring.
- **Verify:** `/usr/bin/gh --version` is at least the `gh-apt` floor in
  `tools.tsv`; doctor row `gh-apt` is `ok`.
- **Human:** yes (sudo: adds an apt signing key and source)

### H1-fcitx5: fcitx5 input method

Applies to `lab-ubuntu`. The fcitx5 packages arrive with H1-apt-core;
`./stow-all.sh lab-ubuntu` later materializes `~/.config/fcitx5/profile`
(pinyin and mozc) as a regular file.

- **Check:** `command -v fcitx5 && grep -s fcitx5 ~/.xinputrc`
- **Install:** `im-config -n fcitx5` (as you, no sudo), then stow, then log out
  and back in.
- **Verify:** after the relogin, `pgrep -x fcitx5` finds the daemon and
  `fcitx5-remote` prints 1 or 2.
- **Human:** yes (gui: run as you, no sudo; the input method starts only after
  you log out and back in)

## Phase 2: package managers and environments

### S2-brew-bundle: Brewfile bundles

Applies to `mac`, `wsl-ubuntu` and `lab-ubuntu`. On macOS the doctor's rows
that Ubuntu gets from apt point here too: git-lfs and tmux come from the core
Brewfile, and the rest (zsh, curl, rsync, tar, file, col, man) are macOS
baseline. One Brewfile per tier in
[`brew/`](../config/bootstrap/brew/): `core` (stow, python, fzf, zoxide, eza,
fd, bat; on macOS also git-lfs and tmux), `cli` (ripgrep, git-delta, tlrc,
chafa, jq, neovim, aria2, uv, gh), `ai` and `desktop` (macOS casks only:
claude-code and codex; kitty, wezterm and the CaskaydiaMono Nerd Font) and
`contributor`. `--no-upgrade` never upgrades what is already installed, so an
old formula shows up as `outdated` in the doctor; upgrade it deliberately with
`brew upgrade <name>`. Never `brew bundle cleanup`.

- **Check:** `HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --no-upgrade --file=config/bootstrap/brew/<tier>.Brewfile`
  for each selected tier. Keep the variable: `brew bundle` otherwise may run
  `brew update` first, which uses the network and writes the Homebrew prefix.
  Before the stow, put brew on PATH first, as H1-homebrew says.
- **Install:** automatic via setup-host.sh, for each selected tier:
  `brew bundle --file=config/bootstrap/brew/<tier>.Brewfile --no-upgrade` with
  `HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_BUNDLE_NO_LOCK=1`.
- **Verify:** `./doctor.sh --host H` shows the Brewfile rows (`python3`, `stow`,
  `fzf`, `eza`, `fd`, `gh`, ...) `ok` with their floors.
- **Human:** no

### S2-micromamba: micromamba

Applies to `sherlock` and `marlowe`. The `micromamba` rows in
[`installers.tsv`](../config/bootstrap/installers.tsv) are a bare static
executable per architecture. One small download, fine on a login node.

- **Check:** `~/.local/bin/micromamba --version`
- **Install:** automatic via setup-host.sh (sha256-checked, mode 755). By hand:
  `f=$(fetch_pinned micromamba "$(uname -m)") && mkdir -p ~/.local/bin && install -m 0755 "$f" ~/.local/bin/micromamba`
- **Verify:** `~/.local/bin/micromamba --version` prints the release named in
  `installers.tsv`.
- **Human:** no

Never run `micromamba shell init` or the micro.mamba.pm script: the overlay rc
files already carry the hook block.

### H2-alloc: Slurm allocation

Applies to `sherlock` and `marlowe`. Solving and unpacking the login env is
sustained work, so it runs on a compute node; setup-host refuses S2-login-env
while `SLURM_JOB_ID` is unset and prints this block.

- **Check:** `echo "${SLURM_JOB_ID:-none}"`
- **Install:** Sherlock: `sh_dev -t 1:00:00`. Marlowe: an interactive job with
  an explicit walltime, for example `srun -t 1:00:00 --pty bash -l` (check the
  partition and account Marlowe requires). Then, inside the job, export the two
  `*_AUTO_UPDATE=0` variables and `CONDA_PKGS_DIRS`
  ([S2-login-env](#s2-login-env-hpc-login-environment)) and re-run setup-host;
  the block prints it with the clone's full path, so it runs from any directory.
- **Verify:** `echo "$SLURM_JOB_ID"` is non-empty and `hostname` is a compute node.
- **Human:** yes (alloc: queueing and resources are the person's call)

### S2-login-env: HPC login environment

Applies to `sherlock` and `marlowe`, inside an allocation. The conda-forge spec
[`hpc-login-env.yml`](../config/bootstrap/hpc-login-env.yml) holds the shell and
CLI toolset (zsh, git, gh, stow, tmux, fzf, eza, bat, fd, ripgrep, nvim, uv,
nodejs, ...), with the floors of `tools.tsv` written as `>=X` and the
conda-forge name traps commented (`nvim`, `fd-find`, `go-shfmt`, `tealdeer`,
`git-delta`). Every workstation's `ssh sherlock` / `ssh marlowe` RemoteCommand
execs `$HOME/micromamba/envs/login/bin/zsh`.

- **Check:** `~/micromamba/envs/login/bin/zsh --version && ~/micromamba/envs/login/bin/python3 --version`
- **Install:** automatic via setup-host.sh:
  `micromamba create -y -r "$HOME/micromamba" -n login -f config/bootstrap/hpc-login-env.yml`.
  After editing the yml, the same with `install` instead of `create`.
  `CONDA_PKGS_DIRS` is inherited. Once stowed, the overlay `.profile` points it
  at a cache under `$SCRATCH`, but the first build runs before the stow, so
  export the overlay's value in the job first; otherwise the cache lands in
  `~/micromamba/pkgs`, inside your home quota (`sh_quota` on Sherlock) and with
  heavy `$HOME` I/O. Sherlock:
  `export CONDA_PKGS_DIRS="$SCRATCH/.cache/conda/pkgs"`; Marlowe:
  `export CONDA_PKGS_DIRS="$SCRATCH/.cache/conda/pkgs/$USER"`. Check
  `echo "$SCRATCH"` first: before the stow only the site sets it, and the
  Marlowe overlay exports its own value.
- **Verify:** `./doctor.sh --host sherlock` shows `login-env` and the tool rows `ok`.
- **Human:** no (after H2-alloc)

Never create the env under `$SCRATCH`: scratch is purged (90 days on Sherlock)
and would take the login shell with it. A package cache there is fine.

### S2-modules: HPC modules and manual AI CLIs

Applies to `sherlock` and `marlowe`, and is where the doctor points for `nvm`,
`node`, `claude` and `codex` on hpc. There is no installer for this step: the
cluster provides Lmod. Sherlock's overlay zsh rc pins the modules it loads;
Marlowe's only initialises Lmod and loads none.

- **Check:** `echo "$LMOD_DIR"; ml spider claude-code codex pi-coding-agent; node --version`
- **Install:** none; `ml <module>` in your own session, or the overlay line for
  pinned modules.
- **Verify:** on Sherlock, in a stowed zsh, `ml list` shows the pinned
  modules; on both, `node --version` meets the `node` floor in `tools.tsv`.
- **Human:** yes (judgment: module availability and versions differ per cluster
  and change over time)

**Node.js.** On `marlowe`, `node` comes from the login env
([S2-login-env](#s2-login-env-hpc-login-environment): conda-forge `nodejs`,
`>=22.0` in the yml; the newest build on 2026-10-09 was 26.x). On `sherlock`,
it comes from Lmod `ml nodejs/24.13.0`, which `sherlock/zsh/.config/zsh/.zshrc`
loads after putting the login env on PATH, so the module wins. There is no nvm
on hpc.

**Lmod pins.** The `ml ...` line in `sherlock/zsh/.config/zsh/.zshrc` names
exact module versions (`ml spider <name>` lists what exists); a bump is a
reviewed change. Marlowe's overlay loads no modules.

**Agent CLIs** are manual rows. Look for site modules with
`ml spider claude-code codex pi-coding-agent` and verify on the host what is
actually there; the Sherlock toolkit's site module is `pi-coding-agent`. If you
install Claude Code yourself into an NFS home instead, set `DISABLE_UPDATES=1`
in the environment it starts from, so sessions on several nodes do not race its
updater over the shared home. Do not leave agents running unattended on login
nodes.

**OS and glibc.** Record `cat /etc/os-release` and `ldd --version` on each
cluster; vendor binaries and conda-forge builds each need a minimum glibc.

## Phase 3: shell framework

### S3-clones: oh-my-zsh, theme and plugin clones

Applies to every Unix host, **before** `./stow-all.sh`. Rows in
[`git-clones.tsv`](../config/bootstrap/git-clones.tsv): oh-my-zsh at
`~/.oh-my-zsh`, powerlevel10k under `$ZSH_CUSTOM/themes`, and fzf-tab,
fast-syntax-highlighting, zsh-autosuggestions, you-should-use,
conda-zsh-completion and zsh-completions under `$ZSH_CUSTOM/plugins`
(`$ZSH_CUSTOM` defaults to `~/.oh-my-zsh/custom`). oh-my-zsh tracks `master`
because `zstyle ':omz:update' mode auto` updates it; every other clone is
pinned to a commit.

- **Check:** `test -f ~/.oh-my-zsh/oh-my-zsh.sh && git -C ~/.oh-my-zsh/custom/plugins/fzf-tab rev-parse HEAD`
  (compare with the `ref` column)
- **Install:** automatic via setup-host.sh. oh-my-zsh is cloned the way its own
  installer does:
  `git clone --depth=1 --branch master -c core.eol=lf -c core.autocrlf=false -c fsck.zeroPaddedFilemode=ignore -c fetch.fsck.zeroPaddedFilemode=ignore -c receive.fsck.zeroPaddedFilemode=ignore -c oh-my-zsh.remote=origin -c oh-my-zsh.branch=master https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh`.
  Every other row: `git init DEST`, `git -C DEST remote add origin URL`,
  `git -C DEST fetch --depth=1 origin REF`, `git -C DEST checkout --detach FETCH_HEAD`.
  By hand: `clone_pinned ID` per row, oh-my-zsh first (the Other Linux quick
  start loops over all of them).
- **Verify:** doctor rows `oh-my-zsh`, `powerlevel10k` and the six plugins are
  `ok`; `git -C DEST rev-parse HEAD` equals each pinned `ref`.
- **Human:** no

A clean clone on another commit is re-pinned; a clone with local changes is
refused (see [X-recovery](#x-recovery-recovery-recipes)). Never run the upstream
oh-my-zsh installer: it replaces `~/.zshrc` and can change your login shell.

On a host that is already set up, an apply re-pins every clean theme and plugin
clone to its commit in `git-clones.tsv`, even when that moves it back from a
newer upstream commit you pulled yourself; oh-my-zsh, which tracks `master`, is
left alone. A clone with local changes is never moved: S3-clones fails and
names it. `--check` shows both beforehand: its S3-clones line lists each clone
to move as `(repin)` (and a missing one as `(clone)`), and a dirty one under
`apply fails for:`.

### S3-bat-theme: bat theme

Applies to every Unix host (Windows: W1-bat-theme). `BAT_THEME` is
`Catppuccin Mocha`, which bat does not ship; the commit-pinned `bat-theme` row
in [`installers.tsv`](../config/bootstrap/installers.tsv) provides it. Needs bat
first (S2-brew-bundle or S2-login-env).

- **Check:** `bat --list-themes | grep -x 'Catppuccin Mocha'`
- **Install:** automatic via setup-host.sh: the file goes to
  `$BAT_CONFIG_DIR/themes/Catppuccin Mocha.tmTheme` (default
  `~/.config/bat/themes`), then `bat cache --build`. By hand:
  `f=$(fetch_pinned bat-theme) && d="$(bat --config-dir)/themes" && mkdir -p "$d" && cp "$f" "$d/Catppuccin Mocha.tmTheme" && bat cache --build`
- **Verify:** the check prints `Catppuccin Mocha`; doctor row `bat-theme` is `ok`.
- **Human:** no

### S3-dirs: Vim state directories

Applies to every Unix host. `common/vim/.vimrc` keeps undo files in
`~/.vim/undo` and swap and backup files in `~/.vim/tmp`.

- **Check:** `test -d ~/.vim/undo && test -d ~/.vim/tmp && echo ok`
- **Install:** automatic via setup-host.sh: `mkdir -p ~/.vim/undo ~/.vim/tmp`
- **Verify:** the check prints `ok`.
- **Human:** no

Editor note: the `vi` alias runs `nvim`, which the `cli` tier installs, but the
repository ships no `~/.config/nvim`; Neovim does not read `.vimrc`, so it starts
with its defaults.

## Phase 4: runtimes

### S4-nvm: nvm and Node.js

Applies to `mac`, `wsl-ubuntu` and `lab-ubuntu` (hpc: S2-modules; Windows:
winget's `OpenJS.NodeJS.LTS`). Node.js is required by the Claude Code hooks and
status line; its floor in `tools.tsv` is 22 (18 and 20 are end of life).
`common/sh/.profile` resolves nvm's `default` alias without sourcing `nvm.sh`,
so the alias must exist.

- **Check:** `test -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" && cat "${NVM_DIR:-$HOME/.nvm}/alias/default" && node --version`
- **Install:** automatic via setup-host.sh with the commit-pinned `nvm` row:
  `NVM_INSTALL_VERSION=<commit> PROFILE=/dev/null bash install.sh`, where
  `<commit>` is the commit in the row's URL. The installer would otherwise
  clone its release tag, which can move; with the commit it fetches exactly
  that commit, and `PROFILE=/dev/null` keeps it out of every rc file.
  setup-host then requires `git -C ~/.nvm rev-parse HEAD` to be that commit
  (and removes a checkout it just made that is not) before it runs
  `nvm install --lts` and `nvm alias default 'lts/*'`. By hand:
  `c=$(awk -F '\t' '$1 == "nvm" { split($3, p, "/"); print p[6]; exit }' ~/dotfiles/config/bootstrap/installers.tsv)`,
  `f=$(fetch_pinned nvm) && NVM_INSTALL_VERSION=$c PROFILE=/dev/null bash "$f"`,
  check that `git -C ~/.nvm rev-parse HEAD` prints `$c`, then
  `. ~/.nvm/nvm.sh && nvm install --lts && nvm alias default 'lts/*'`.
- **Verify:** in a new shell, `command -v node` is under `~/.nvm/versions` and
  `node --version` meets the floor.
- **Human:** no

Never install nvm with Homebrew; the doctor's `nvm-homebrew` check warns about
it and [X-recovery](#x-recovery-recovery-recipes) moves you off it. Install Node
before the first interactive `claude`.

### S4-setup-sync: AI-sync runtime

Applies to every Unix host (Windows: W1-setup-sync). `./setup-sync.sh` creates
the checkout-local `.venv-sync` with the hash-pinned `tomlkit` that
`./stow-all.sh` needs; it is the only write setup-host causes inside the clone.
It needs Python 3.11 or newer.

- **Check:** `~/dotfiles/.venv-sync/bin/python -I -B ~/dotfiles/lib/config_sync.py --runtime-check`
- **Install:** automatic via setup-host.sh. By hand, by platform:
  macOS `./setup-sync.sh --python /opt/homebrew/bin/python3` (Intel:
  `/usr/local/bin/python3`; Apple's `/usr/bin/python3` is too old);
  Ubuntu 24.04 `./setup-sync.sh` (system Python 3.12; on 22.04 use
  `--python /home/linuxbrew/.linuxbrew/bin/python3`);
  hpc `./setup-sync.sh --python "$HOME/micromamba/envs/login/bin/python3"`.
- **Verify:** it prints `AI-sync runtime ready`; the doctor's `venv-sync` check,
  which runs the same `--runtime-check` (on `DOTFILES_SYNC_PYTHON` when that is
  set), is `ok`.
- **Human:** no

## Phase 5: AI CLIs

Authenticate GitHub ([H7-auth](#h7-auth-authentication)) and install Node before
the first interactive `claude`: plugin marketplaces are cloned with your git
credentials and never prompt.

### S5-claude: Claude Code

Applies to `wsl-ubuntu` and `lab-ubuntu` through the `claude` row of
[`installers.tsv`](../config/bootstrap/installers.tsv); macOS uses the
`claude-code` cask (`ai` tier of S2-brew-bundle), hpc S2-modules, Windows
`Anthropic.ClaudeCode` (W1-winget). Anthropic's native installer cannot be
pinned by version or digest, so it is an `inspect` step.

- **Check:** `claude --version`
- **Install:** setup-host.sh downloads `https://claude.ai/install.sh` once to a
  scratch directory (later runs keep that copy; delete it for a fresh one) and
  prints a `HUMAN-BEGIN S5-claude inspect` block with its sha256, size and
  path. Read it: it should fetch Claude Code from Anthropic into your home
  directory and must not call sudo or edit rc files. Then run the block's
  digest gate,
  `printf '%s  %s\n' <sha256> <path> | sha256sum -c --status - && bash <path>`,
  which runs the copy only while it still has the digest the block showed. By
  hand: `f=$(fetch_pinned claude)`, `less "$f"`, `bash "$f"`.
- **Verify:** `claude --version` prints a version and `command -v claude` is
  `~/.local/bin/claude`; `git -C ~/dotfiles status --porcelain` is empty.
- **Human:** yes (inspect: an unpinned vendor script is read before it runs)

### S5-codex: Codex CLI

Applies to `wsl-ubuntu` and `lab-ubuntu` through the per-architecture `codex`
rows of [`installers.tsv`](../config/bootstrap/installers.tsv) (the upstream
`codex-package` musl tarball); macOS uses the `codex` cask, hpc S2-modules,
Windows `OpenAI.Codex`. The tarball is laid out the way OpenAI's installer does
it: extracted to `~/.codex/packages/standalone/releases/<version>-<target>/`
with a relative `codex -> bin/codex` link inside,
`~/.codex/packages/standalone/current` linked to that release, and
`~/.local/bin/codex` linked to `current/bin/codex`. The package bundles its own
`bwrap` (`codex-resources/bwrap`), `rg` and `codex-code-mode-host`, so no apt
`bubblewrap` is needed. OpenAI's `install.sh` is never run.

- **Check:** `codex --version; readlink ~/.local/bin/codex`
- **Install:** automatic via setup-host.sh. By hand (version and target come
  from the package's own `codex-package.json`):

  ```sh
  f=$(fetch_pinned codex "$(uname -m)")
  dest=$HOME/.codex/packages/standalone
  mkdir -p "$dest/releases" ~/.local/bin
  tmp=$(mktemp -d "$dest/.extract.XXXXXX")
  tar -C "$tmp" -xzf "$f"
  rel=$(python3 -I -c 'import json, sys; p = json.load(open(sys.argv[1])); print(p["version"] + "-" + p["target"])' "$tmp/codex-package.json")
  if [ -d "$dest/releases/$rel" ]; then
      rm -rf "$tmp"    # this release is already unpacked
  else
      ln -s bin/codex "$tmp/codex"
      mv "$tmp" "$dest/releases/$rel"
  fi
  ln -sfn "$dest/releases/$rel" "$dest/current"
  ln -sfn "$dest/current/bin/codex" ~/.local/bin/codex
  ```

- **Verify:** `codex --version` reports the release named in `installers.tsv`.
- **Human:** no

On Ubuntu 24.04, AppArmor may restrict the unprivileged user namespaces that
bwrap needs. If Codex reports a sandbox failure, that is a judgment step: read
OpenAI's Linux sandbox documentation and decide on the AppArmor change yourself.

## Phase 6: desktop

Not in the default tiers; select `--tier all` (or add `desktop`).

### S6-nerd-font: Nerd Font

Applies to `lab-ubuntu` through the `nerd-font` row of
[`installers.tsv`](../config/bootstrap/installers.tsv) (a flat archive of
CaskaydiaMono Nerd Font `.ttf` files); macOS uses the
`font-caskaydia-mono-nerd-font` cask, Windows W1-font. On `wsl-ubuntu` the font
belongs to the Windows terminal, not the distribution.

- **Check:** `find ~/.local/share/fonts ~/.fonts /usr/share/fonts /usr/local/share/fonts -maxdepth 4 -iname '*CaskaydiaMonoNerdFont*' 2>/dev/null | head -n 1`
  (macOS: `ls ~/Library/Fonts /Library/Fonts | grep -i CaskaydiaMono`); the
  doctor's `nerd-font` row looks for the same file names, also under
  Homebrew's `share/fonts`.
- **Install:** automatic via setup-host.sh: extract into
  `$XDG_DATA_HOME/fonts/CaskaydiaMonoNerdFont` (default
  `~/.local/share/fonts/...`), then `fc-cache -f`. By hand:
  `f=$(fetch_pinned nerd-font) && d=~/.local/share/fonts/CaskaydiaMonoNerdFont && mkdir -p "$d" && tar -C "$d" -xJf "$f" && fc-cache -f`
- **Verify:** the check prints a font file and `fc-list | grep -i 'CaskaydiaMono Nerd Font'`
  lists the family; prompt and `eza` icons render in kitty and WezTerm.
- **Human:** no

### S6-kitty: kitty

Applies to `lab-ubuntu` through the per-architecture `kitty` rows of
[`installers.tsv`](../config/bootstrap/installers.tsv); macOS uses the `kitty`
cask. The `.txz` has `bin/`, `lib/` and `share/` at its top level.

- **Check:** `kitty --version; readlink ~/.local/bin/kitty`
- **Install:** automatic via setup-host.sh. By hand:
  `f=$(fetch_pinned kitty "$(uname -m)") && mkdir -p ~/.local/kitty.app ~/.local/bin && tar -C ~/.local/kitty.app -xJof "$f" && ln -sf ~/.local/kitty.app/bin/kitty ~/.local/kitty.app/bin/kitten ~/.local/bin/`
- **Verify:** `kitty --version` and `kitten --version` both run.
- **Human:** no (a desktop launcher is optional: copy
  `~/.local/kitty.app/share/applications/kitty.desktop` into
  `~/.local/share/applications/` and fix its paths, as kitty's install docs describe)

`kitten` on remotes: the `download` zsh function and kitty image previews call
`kitten` on the host you ssh into. No manifest installs it on hpc; if you want
them there, unpack the same tarball into your home on that host by hand.

## Phase 7: stow, login shell and authentication

### H7-stow: Stow the dotfiles

Applies to every Unix host (Windows: HW-stow), after S3-clones and
S4-setup-sync. `./stow-all.sh H` runs the Claude and Codex sync helpers (writing
`~/.claude/settings.json`, `~/.codex/config.toml` and
`~/.codex/rules/portable.rules`), links `common/` and then the overlay into
`$HOME`, tightens `~/.ssh` modes and records the host for the doctor and the
login updater. Stow refuses to replace regular files, and Ubuntu's `/etc/skel`
creates `~/.bashrc` and `~/.profile` (RHEL-family homes, such as Sherlock's,
also `~/.bash_profile`). `./stow-all.sh` runs a Stow dry run of every package
before the sync helpers write anything and stops on a conflict, and it refuses
to stow the zsh package before oh-my-zsh is cloned.

Before the first stow, `stow` is not on your PATH: it comes from Homebrew,
Linuxbrew or the login env, which only the stowed rc files put on PATH, and
`./stow-all.sh` stops with "required GNU Stow is missing". Run it, and the dry
run below, with the one-shot prefix for the host:

| Host | Prefix |
| --- | --- |
| `mac` | `PATH="/opt/homebrew/bin:$PATH"` on Apple Silicon, `PATH="/usr/local/bin:$PATH"` on Intel |
| `wsl-ubuntu`, `lab-ubuntu` | `PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"` |
| `sherlock`, `marlowe` | `PATH="$HOME/micromamba/envs/login/bin:$PATH"` |
| other Linux | none, when stow came from the distribution |

The H7-stow block prints the whole command as one line, ready to run: the
prefix (the bin directory of the Homebrew setup-host found, else the default
above), then the clone's `stow-all.sh` by its full path, then the host, for
example `PATH="/home/linuxbrew/.linuxbrew/bin:$PATH" ~/dotfiles/stow-all.sh wsl-ubuntu`
with `~/dotfiles` spelled out. Once stowed, new shells find `stow` without it.

- **Check:** a dry run that lists every conflict, for example on `wsl-ubuntu`:
  `cd ~/dotfiles && PATH="/home/linuxbrew/.linuxbrew/bin:$PATH" stow -n --restow --no-folding -d common $(ls common)`
  (repeat with `-d wsl-ubuntu $(ls wsl-ubuntu)` for the overlay)
- **Install:** the H7-stow block. It first lists every home file Stow would
  refuse, a regular file or a link that leads outside this checkout where a
  package tracks a file (files `.stowrc` ignores are left alone), each with its
  own line, for example `mv -n ~/.bashrc ~/.bashrc.pre-dotfiles`; run those,
  never `stow --adopt` (it would overwrite the tracked copies with the home's
  files), and merge what you still need into the overlay later. Then the
  prefix and `./stow-all.sh H`, for example
  `PATH="/home/linuxbrew/.linuxbrew/bin:$PATH" ./stow-all.sh wsl-ubuntu`.
  `./stow-all.sh` runs the dry run above itself and stops, before it writes
  anything, when one is left.
- **Verify:** `ls -l ~/.zshrc ~/.profile ~/.gitconfig` shows links into
  `~/dotfiles/common/`; in a new shell the doctor's `stow-links` and
  `path-order` checks are `ok` (path-order warns only when a command in
  `~/.local/bin` is shadowed by a second install earlier on PATH: remove the
  one you do not use).
- **Human:** yes (judgment: it rewrites your home's dotfiles and AI settings;
  the person runs it, or approves it as one visible top-level agent command)

### H7-chsh: Login shell

Applies to `mac`, `wsl-ubuntu` and `lab-ubuntu`. macOS has used `/bin/zsh` by
default since Catalina. On hpc there is no `chsh`: zsh is reached through the
workstation's `ssh sherlock` / `ssh marlowe` RemoteCommand, which execs
`~/micromamba/envs/login/bin/zsh -il` (the native Windows ssh config still uses
an older RemoteCommand; the Windows terminal profiles ssh from inside WSL).

- **Check:** macOS `dscl . -read ~ UserShell`; Linux `getent passwd "$USER" | cut -d: -f7`
- **Install:** `chsh -s "$(command -v zsh)"` (the shell must be listed in
  `/etc/shells`; on Ubuntu it is `/usr/bin/zsh`)
- **Verify:** in a new login, `echo "$SHELL"` ends in `/zsh`.
- **Human:** yes (chsh: it asks for your password)

### H7-auth: Authentication

Applies to every Unix host (Windows: HW-auth). Do this before the first
interactive `claude` or `codex`.

- **Check:** `ssh -T git@github.com; gh auth status; claude auth status; codex login status`
  (or `./doctor.sh --host H --online`)
- **Install:**
  - SSH key: `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519` (the stowed ssh config
    uses exactly that file, with `IdentitiesOnly yes`).
  - GitHub: `gh auth login --git-protocol ssh` (browser or device code; it offers
    to upload the public key). Do not run `gh auth setup-git`: it writes
    `git config --global`, which goes through the stowed `~/.gitconfig` into
    `common/git/.gitconfig`. Hosts that need gh as a credential helper already
    name it in their `.gitconfig_local` (lab-ubuntu, marlowe).
  - Claude Code: run `claude` once in a terminal, or `claude auth login`.
  - Codex: `codex login` (`codex login --device-auth` on a headless host).
  - Kerberos for Sherlock and Marlowe: `kinit <SUNetID>@stanford.edu` on the
    workstation (krb5 is a host tool, X-host-tools); the ssh config delegates the
    ticket. The block setup-host prints on sherlock and marlowe also lists
    `kinit`, for a session on the cluster that has no delegated ticket.
  - lab-ubuntu: Git Credential Manager with `credentialStore = gpg` needs a gpg
    key and `pass init <gpg-key-id>`. wsl-ubuntu uses the Windows-side Git
    Credential Manager from Git for Windows.
- **Verify:** `./doctor.sh --host H --online` shows the three auth probes `ok`.
  A signed-out tool shows `warn` and does not fail the run, so read the rows
  rather than the exit code.
- **Human:** yes (auth: browser or device-code logins, passwords and key
  passphrases)

### H7-sync-skills: Skill library sync

Applies to every Unix host. Once stowed, every interactive shell (zsh through
`.zshrc`, bash and sh login shells through `.profile`) sources
`scripts/awesome-skills-update.sh`, which downloads the unpinned `main`
`install.sh` of FridrichMethod/awesome-skills and runs it in the background;
the first run fills `~/.claude/skills` and `~/.codex/skills`, later runs
refresh weekly. It needs bash, curl, tar and rsync.

It is **on by default**: it runs unless `AWESOME_SKILLS_AUTO_UPDATE=0` is in that
shell's environment. The quick start's export reaches only shells that inherit
it, so after the stow a new terminal, a new login, or the first `ssh sherlock`
or `ssh marlowe` from a workstation runs it. It is the one download near the
bootstrap that is not pinned, so decide before the first new shell after the
stow. Every rc file in this repository is tracked, so there is no local file to
turn it off in: to keep it off, export `AWESOME_SKILLS_AUTO_UPDATE=0` in the
environment that the terminal or the ssh session starts with.

- **Check:** `ls ~/.claude/skills ~/.codex/skills 2>/dev/null | head; ls -l "${XDG_CACHE_HOME:-$HOME/.cache}/awesome-skills/last-sync"`
- **Install:** opt-out, as above; nothing to do to keep it on. To run it once
  now, in the foreground: the line the setup-host block prints, which works
  before the stow too and also in a shell that exports
  `AWESOME_SKILLS_AUTO_UPDATE=0`, which even `AWESOME_SKILLS_FORCE=1` obeys:
  `AWESOME_SKILLS_AUTO_UPDATE=1 AWESOME_SKILLS_FORCE=1 AWESOME_SKILLS_BG=0 sh ~/dotfiles/scripts/awesome-skills-update.sh`.
  In a stowed shell without that export, `sync-skills` does the same.
- **Verify:** `ls ~/.claude/skills | wc -l` is non-zero; the log is
  `${XDG_CACHE_HOME:-$HOME/.cache}/awesome-skills/last.log`.
- **Human:** yes (judgment: it is on by default once stowed and runs an unpinned
  script from a branch head; decide before the first new shell after the stow)

### H7-doctor: Final doctor run

Applies to every host. This is the completion gate.

- **Check:** `./doctor.sh --host H --smoke` (Windows: `.\doctor.ps1 -Host win`)
- **Install:** none; follow the step each failing row names, then run it again.
- **Verify:** exit 0. Add `--online` for the auth probes and `--tier all` to see
  the desktop, contributor and host rows.
- **Human:** yes (judgment: setup-host prints it as a non-blocking reminder; the
  person or the agent runs it and decides whether the remaining warnings matter)

## Native Windows

The Windows steps, in the order you run them. Agents never elevate; every
elevated command is the person's.

### HW-clone: Clone with symlinks enabled

The checkout contains symlinks (`common/pymol/.pymolrc*`) that Git for Windows
only creates when `core.symlinks` is true and the process may create symlinks.

- **Check:** `git -C $HOME\dotfiles config core.symlinks; (Get-Item $HOME\dotfiles\common\pymol\.pymolrc).LinkType`
- **Install:** turn on Developer Mode (Settings > System > For developers), then
  `winget install --id Git.Git -e`, `winget install --id Microsoft.PowerShell -e`,
  and in a new `pwsh` window
  `git clone -c core.symlinks=true --recurse-submodules https://github.com/FridrichMethod/dotfiles.git $HOME\dotfiles`.
  Clone onto NTFS, never into a WSL distribution. An existing clone made
  without symlinks: `git -C $HOME\dotfiles config core.symlinks true`, then
  `git -C $HOME\dotfiles checkout -- common/pymol`.
- **Verify:** `core.symlinks` prints `true`, `LinkType` prints `SymbolicLink`,
  and `git -C $HOME\dotfiles status --porcelain` is empty.
- **Human:** yes (gui: Developer Mode is a Settings toggle)

### W1-winget: winget import

Installs the 22 packages of [`winget.json`](../config/bootstrap/winget.json):
PowerShell 7, Git, Python 3.12, Node.js LTS, the CLI tools (fzf, zoxide, eza,
bat, fd, ripgrep, delta, jq, Neovim, uv, gh, tlrc, aria2), oh-my-posh, Windows
Terminal, WezTerm, Claude Code and Codex.

- **Check:** `winget list --id Git.Git -e` (or `.\doctor.ps1 -Host win`)
- **Install:** automatic via setup-host.ps1:
  `winget import --import-file config\bootstrap\winget.json --no-upgrade --ignore-unavailable --accept-package-agreements --accept-source-agreements --disable-interactivity`.
  Already-installed packages count as success; other failures fail the step.
  Open a new terminal afterwards so the new PATH entries apply.
- **Verify:** `.\doctor.ps1 -Host win` shows the winget rows `ok`.
- **Human:** no (setup-host.ps1 runs it; a machine-wide installer may still
  raise a UAC prompt for the person to accept)

### W1-psresources: PowerShell modules

PSFzf, CompletionPredictor and Microsoft.WinGet.CommandNotFound, which the
PowerShell 7 profile uses only when present.

- **Check:** `Get-InstalledPSResource PSFzf, CompletionPredictor, Microsoft.WinGet.CommandNotFound`
- **Install:** automatic via setup-host.ps1, only for the missing ones, one at
  a time with `Install-PSResource -Name <module> -Scope CurrentUser -TrustRepository -AcceptLicense`.
  By hand:
  `Install-PSResource -Name PSFzf, CompletionPredictor, Microsoft.WinGet.CommandNotFound -Scope CurrentUser`
  (PSGallery is untrusted by default, so a manual run asks to confirm).
- **Verify:** the check lists all three.
- **Human:** no

### W1-font: Nerd Font on Windows

Runs only when oh-my-posh is installed (W1-winget).

- **Check:** `Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Fonts", "$env:WINDIR\Fonts" -Filter 'CaskaydiaMono*' -ErrorAction Ignore`
- **Install:** automatic via setup-host.ps1: `oh-my-posh font install CascadiaMono`
- **Verify:** the check lists the font files; restart Windows Terminal and WezTerm.
- **Human:** no

### W1-bat-theme: bat theme on Windows

The same commit-pinned `bat-theme` row as S3-bat-theme, in bat's Windows
config directory.

- **Check:** `Test-Path "$env:APPDATA\bat\themes\Catppuccin Mocha.tmTheme"`
- **Install:** automatic via setup-host.ps1: download with the sha256 check to
  `$env:APPDATA\bat\themes\Catppuccin Mocha.tmTheme`, then `bat cache --build`.
- **Verify:** `bat --list-themes | Select-String -SimpleMatch 'Catppuccin Mocha'`
- **Human:** no

### W1-setup-sync: AI-sync runtime on Windows

- **Check:** `& .\.venv-sync\Scripts\python.exe -I -B lib\config_sync.py --runtime-check`
- **Install:** automatic via setup-host.ps1:
  `.\setup-sync.ps1 -Python <path>`, with the first `python3` or `python` on
  PATH that reports 3.11 or newer; a Microsoft Store alias does not count. When
  there is none, the step fails and says so: open a new terminal so the
  W1-winget PATH applies, or run `.\setup-sync.ps1 -Python <path>` yourself,
  with the path from `py -0p`.
- **Verify:** it prints `AI-sync runtime ready`, and the check passes.
- **Human:** no

### HW-execution-policy: Execution policy

The tracked profiles and scripts are local files, which `RemoteSigned` allows.

- **Check:** `Get-ExecutionPolicy -List`
- **Install:** the block's two lines, one per PowerShell, since PowerShell 7
  and Windows PowerShell 5.1 keep the setting separately:
  `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` (in PowerShell 7) and
  `powershell.exe -NoProfile -Command Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`
  (for 5.1). Skip the second if you never use 5.1.
- **Verify:** `Get-ExecutionPolicy -Scope CurrentUser` prints `RemoteSigned`.
- **Human:** yes (judgment: a security setting)

### HW-stow: Elevated stow

`stow-all.ps1` creates the links; links made without elevation can be rejected
by processes that enforce RedirectionGuard, such as current Windows OpenSSH
(see the README's Windows section).

- **Check:** `.\stow-all.ps1 win -WhatIf` (validates and previews, writes nothing)
- **Install:** in an elevated PowerShell 7 (Run as administrator), from
  `$HOME\dotfiles`: `.\stow-all.ps1 win`. The HW-stow block prints it with the
  clone's full path, `& '<clone>\stow-all.ps1' win`, so it runs from any
  directory.
- **Verify:** `(Get-Item $HOME\.gitconfig).LinkType` prints `SymbolicLink` and
  `.\doctor.ps1 -Host win` passes.
- **Human:** yes (judgment: it rewrites your Windows home's dotfiles and AI
  settings, from an elevated shell, which is always the person's)

Limitation: nothing adds `~\.local\bin` to the Windows PATH, so `shk.cmd` (from
`.\setup-sherlock-kit.ps1`) is not found by name. Call it by its full path, or
add that directory to your user PATH yourself.

### HW-auto-stow-task: Automatic stow task

Optional. The login updater can restow after a pull through a current-user task
that runs this checkout's scripts with highest privileges.

- **Check:** `Get-ScheduledTask -TaskName 'Dotfiles-Restow-*' -ErrorAction Ignore`
- **Install:** in an elevated PowerShell 7: `.\scripts\dotfiles-auto-stow.ps1 -Register`
  (the block names it by its full path, as for HW-stow)
- **Verify:** the check lists one task.
- **Human:** yes (judgment: it grants a checkout script standing elevation)

### HW-ssh-agent: ssh-agent service

The OpenSSH agent ships disabled.

- **Check:** `Get-Service ssh-agent | Select-Object Status, StartType`
- **Install:** elevated: `Set-Service -Name ssh-agent -StartupType Automatic`,
  then `Start-Service ssh-agent`; then, as yourself, `ssh-add $HOME\.ssh\id_ed25519`.
- **Verify:** `ssh-add -l` lists the key.
- **Human:** yes (sudo: changing a service needs an elevated shell)

### HW-wsl: WSL distribution

The WezTerm and Windows Terminal configs open the distribution by the literal
name `Ubuntu` (`WSL:Ubuntu`, `wsl.exe -d Ubuntu`). Inside it, follow the Ubuntu
and WSL quick start with host `wsl-ubuntu`.

- **Check:** `wsl --list --verbose`
- **Install:** elevated: `wsl --install -d Ubuntu`, then reboot if asked.
- **Verify:** `wsl -d Ubuntu -- uname -a`
- **Human:** yes (judgment: optional; it needs an elevated shell and maybe a
  reboot, and the tracked `wsl.conf` needs review, below)

The judgment part: `win/wsl/` stows `.wslconfig`, `wsl.conf` and `mount.vbs`
into your Windows home. `.wslconfig` sizes memory and processors for one
machine; review it. `wsl.conf` takes effect only as `/etc/wsl.conf` inside the
distribution, and the tracked one runs `/usr/local/bin/mount-data.sh`, which
this repository does not ship, and hardcodes a `[user] default=` name. Copy only
what fits this machine into `/etc/wsl.conf` by hand (with sudo), then
`wsl --shutdown`. `mount.vbs` mounts one specific physical disk; do not schedule
it on another machine.

### HW-auth: Windows authentication

- **Check:** `ssh -T git@github.com; gh auth status; claude auth status; codex login status`
  (or `.\doctor.ps1 -Host win -Online`)
- **Install:** `ssh-keygen -t ed25519 -f $HOME\.ssh\id_ed25519`;
  `gh auth login --git-protocol ssh`; Git Credential Manager comes with Git for
  Windows and `win/git/.gitconfig_local` selects it; `claude` once, or
  `claude auth login`; `codex login`. For Sherlock and Marlowe, the terminal
  profiles ssh from inside WSL, so `kinit` there.
- **Verify:** `.\doctor.ps1 -Host win -Online` shows the auth probes `ok`.
- **Human:** yes (auth: browser logins and key passphrases)

## Optional and other platforms

### X-host-tools: Host-specific tools

The `host` tier of `tools.tsv` is reported, never installed: the per-overlay
miniconda prefixes, juliaup, TeX Live, GROMACS, CUDA, MATLAB, Schrodinger,
fcitx5 (H1-fcitx5), wslu and notify-send (H1-apt-core), Kerberos `kinit`, Git
Credential Manager, gpg and pass, Tailscale, and Lmod. A missing one costs only
what the doctor's `absent` text names. The one exception, micromamba with the
`login` env on hpc, is installed by S2-micromamba and S2-login-env. The
overlays' `conda initialize` blocks hardcode one machine's prefix; re-aiming
them is a separate change.

- **Check:** `./doctor.sh --host H --tier host`
- **Install:** each from its vendor or site, at the path the row probes.
- **Verify:** the doctor row turns `ok`.
- **Human:** yes (judgment: licensed or site-specific software)

### X-contributor: Contributor tools

For working on this repository: pre-commit, shfmt (3.13 or newer for the zsh
dialect), shellcheck and stylua. `pre-commit` provisions its own pinned hook
environments; the local binaries are for manual runs.

- **Check:** `./doctor.sh --host H --tier contributor`
- **Install:** mac and Ubuntu: `./setup-host.sh --host H --tier contributor`
  (the [contributor Brewfile](../config/bootstrap/brew/contributor.Brewfile));
  hpc: pre-commit, go-shfmt and shellcheck are in the login env, stylua is
  manual; Windows: `uv tool install pre-commit`.
- **Verify:** `pre-commit run --all-files`
- **Human:** no

### X-other-linux: Other Linux distributions

There are only six overlays; `fedora/` and `ubuntu/` do not exist. On any other
Linux, stow `common/` alone and install the packages yourself. An Ubuntu or
Debian machine that is neither WSL nor the lab desktop can use
`--platform debian` for the doctor's rows. `./setup-host.sh` needs a host
overlay, so its four platform-neutral steps are done by hand; the Other Linux
quick start runs them as one sequence.

- **Check:** `./doctor.sh --platform other` (its apt, Homebrew, nvm, Claude,
  Codex and locale references all point here)
- **Install:** with the distribution's package manager, the equivalents of
  [`apt/common.txt`](../config/bootstrap/apt/common.txt) and the Brewfile tools,
  meeting every floor in [`tools.tsv`](../config/bootstrap/tools.tsv) (distro
  fzf, eza and gh are often older), and the `en_US.UTF-8` locale (`locale-gen`
  or `localedef`, as the distribution does it); or install Homebrew on Linux
  yourself and run
  `HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_BUNDLE_NO_LOCK=1 brew bundle --file=config/bootstrap/brew/<tier>.Brewfile --no-upgrade`
  (then stow needs that brew's directory as its H7-stow prefix). Then, with
  `clone_pinned` and `fetch_pinned` from
  [Pinned artifacts by hand](#pinned-artifacts-by-hand): `clone_pinned ID` for
  every `git-clones.tsv` row, oh-my-zsh first (S3-clones); the by-hand recipe of
  S3-bat-theme; `mkdir -p ~/.vim/undo ~/.vim/tmp` (S3-dirs); `./setup-sync.sh`
  (S4-setup-sync). Finally `./stow-all.sh` with no host.
- **Install, `ai` tier:** the default tiers also check `node` (at the floor in
  `tools.tsv`), `claude` and `codex`. Node: the by-hand recipe of
  [S4-nvm](#s4-nvm-nvm-and-nodejs), or the distribution's Node.js if it meets
  the floor. Claude Code: `f=$(fetch_pinned claude)`, read it, then `bash "$f"`
  ([S5-claude](#s5-claude-claude-code)). Codex: the by-hand recipe of
  [S5-codex](#s5-codex-codex-cli). Until then, `./doctor.sh --platform other --tier core,cli`
  checks the rest.
- **Verify:** `./doctor.sh --platform other --smoke` exits 0.
- **Human:** yes (sudo: distribution packages)

## Appendix: rc-file protection

### X-rc-protection: rc-file protection

`~/.zshrc`, `~/.bashrc`, `~/.profile` and `~/.gitconfig` are Stow symlinks, so
anything a third-party installer appends lands in `common/` and dirties the
checkout. The doctor's `rc-pollution` check looks for `~/.zshrc.pre-oh-my-zsh`,
a `# >>> Codex installer >>>` block and duplicated conda blocks. Keep every
installer away from rc files:

- nvm: `PROFILE=/dev/null`.
- uv's standalone installer: `UV_NO_MODIFY_PATH=1` (the bootstrap installs uv
  with Homebrew, conda-forge or winget instead).
- micromamba's install script: `INIT_YES=no` (the bootstrap uses the bare
  binary), and never `micromamba shell init`.
- OpenAI's Codex installer: `CODEX_NON_INTERACTIVE=1`, and only once
  `~/.local/bin` is already on PATH; otherwise it appends a PATH block (the
  bootstrap never runs it).
- Homebrew: `NONINTERACTIVE=1`, and never paste its `brew shellenv` "Next steps"
  lines.
- Never `git lfs install` (the `lfs` filter is already in `common/git/.gitconfig`
  and the command rewrites the stowed `~/.gitconfig`), never `gh auth setup-git`
  (same file), never `conda init`, never the upstream oh-my-zsh installer.

PATH belongs in `common/sh/.profile`, which already puts `~/.local/bin` first;
AGENTS.md's shell conventions say to discard installer PATH blocks and keep
only their intent there.

setup-host enforces this for its own steps: it records the checkout's state
before each step and fails the step when anything changed, comparing file
content, so an edit to a file that was already modified still fails. Start from
a clean checkout; P0-preflight warns when it is not.

- **Check:** `git -C ~/dotfiles status --porcelain` (must print nothing)
- **Install:** if it lists a file, read `git -C ~/dotfiles diff <file>`. When the
  diff is only an installer's block, discard it with
  `git -C ~/dotfiles restore <file>`; when your own edits are in the same file,
  delete just the block by hand.
- **Verify:** the check prints nothing and the doctor's `rc-pollution` check is `ok`.
- **Human:** yes (judgment: confirm the diff is only the installer's block before
  discarding it)

## Appendix: recovery

### X-recovery: Recovery recipes

- **Check:** `./doctor.sh --host H` (the `omz-order`, `rc-pollution` and
  `nvm-homebrew` checks point here)
- **Install:** the matching recipe below.
- **Verify:** the doctor check that pointed here is `ok`.
- **Human:** yes (judgment: each recipe moves or replaces files)

**oh-my-zsh after stow.** `~/.oh-my-zsh/custom/` exists (Stow made it) but
`~/.oh-my-zsh/oh-my-zsh.sh` does not, so S3-clones refuses. Turn the directory
into the checkout in place, keeping the stowed links:

```sh
git -C ~/.oh-my-zsh init
git -C ~/.oh-my-zsh remote add origin https://github.com/ohmyzsh/ohmyzsh.git
git -C ~/.oh-my-zsh fetch --depth=1 origin master
git -C ~/.oh-my-zsh checkout -b master origin/master
git -C ~/.oh-my-zsh config oh-my-zsh.remote origin
git -C ~/.oh-my-zsh config oh-my-zsh.branch master
```

Then re-run `./setup-host.sh --host H` for the theme and plugin clones. When
S3-clones refuses, setup-host prints this recipe with your paths as an
X-recovery block, with the clone settings of
[S3-clones](#s3-clones-oh-my-zsh-theme-and-plugin-clones) set before the fetch.

**Dirty clone.** S3-clones refuses a theme or plugin clone with local changes.
Look at them (`git -C DEST status`, `git -C DEST diff`), move the directory aside
if you want to keep them (`mv DEST DEST.local`), then
`./setup-host.sh --host H --only S3-clones`. A dirty `~/dotfiles` checkout after
an installer is [X-rc-protection](#x-rc-protection-rc-file-protection).

**Digest mismatch.** setup-host deletes the `.part` file and fails the step with
the expected and actual sha256. Never edit the digest just to make it pass.
Retry once (a proxy or captive portal can serve an HTML page). If the artifact
really changed upstream, or you want a newer release, review the new artifact
(release notes; for a script, its diff against the pinned commit), download it,
compute its digest (`sha256sum FILE`, macOS `shasum -a 256 FILE`), update its
`url` and `sha256` and the `# pinned` date in
[`installers.tsv`](../config/bootstrap/installers.tsv), run
`bash tests/bootstrap-manifest.sh`, commit, and re-run setup-host.

**Homebrew-installed nvm.** `brew list nvm` succeeds and the doctor's
`nvm-homebrew` check warns. Run `brew uninstall nvm` and delete the
`$(brew --prefix nvm)/nvm.sh` lines Homebrew's caveat told you to add (if they
landed in a stowed rc file, `git -C ~/dotfiles status` shows it; see
X-rc-protection). Keep `~/.nvm`, whose `versions/` stay usable, then run
`./setup-host.sh --host mac --only S4-nvm`; the pinned installer turns `~/.nvm`
into its own checkout.

**`~/.zshrc.pre-oh-my-zsh`.** The upstream oh-my-zsh installer ran: it moved
your stowed `~/.zshrc` link to `~/.zshrc.pre-oh-my-zsh`, wrote its template
`~/.zshrc`, and may have changed your login shell. Check with
`ls -l ~/.zshrc ~/.zshrc.pre-oh-my-zsh`; move the template aside
(`mv ~/.zshrc ~/.zshrc.omz-template`); remove `~/.zshrc.pre-oh-my-zsh` only if
it is the link into `~/dotfiles`; then `./stow-all.sh H`, with the
[H7-stow](#h7-stow-stow-the-dotfiles) prefix when `stow` is not on PATH, and, if
needed, [H7-chsh](#h7-chsh-login-shell).

## Acceptance checklist

Not yet run. Each run starts from a fresh machine, follows the quick start for
its platform, and passes when all of these hold:

- `./doctor.sh --host H` (Windows `.\doctor.ps1 -Host win`) exits 0 for the
  default tiers, and `--smoke` exits 0 on Unix.
- `./setup-host.sh --host H --check` wrote nothing: a
  `find "$HOME" -newer <marker>` taken around it is empty.
- A second `./setup-host.sh --host H` installs nothing and exits 0.
- `git -C ~/dotfiles status --porcelain` is empty after every step.
- No step ran sudo, `chsh`, stow or an rc edit outside a HUMAN block.

| Run | Date | Result | Notes |
| --- | --- | --- | --- |
| Fresh macOS VM (Apple Silicon), host `mac` | | not yet run | |
| Fresh WSL `Ubuntu` (24.04), host `wsl-ubuntu` | | not yet run | |
| Sherlock inside `sh_dev`, host `sherlock` | | not yet run | |
| Native Windows 11, elevated stow, host `win` | | not yet run | |
