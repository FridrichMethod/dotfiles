# Bootstrapping a host

## What this is

`./doctor.sh` and `./setup-host.sh` (on native Windows, `.\doctor.ps1` and
`.\setup-host.ps1`) are the explicit, fail-closed entry points that take a
fresh machine to the state the stowed configs assume. The doctor is read-only
and offline: for every tool it reports `ok`, `missing` or `outdated` and names
the step below that fixes it. The installer runs pinned, checksummed steps that
need no root, and prints everything that needs a person (sudo, a browser login,
a GUI dialog, a Slurm allocation, a login-shell change, a judgment call) as a
HUMAN block instead of running it. Profiles, `./stow-all.sh` and the automatic
update hooks never install anything; only these entry points do, and only when
you run them.

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
> stow. If stow ran first, use the first recipe in
> [X-recovery](#x-recovery-recovery-recipes).

Keep the login hooks quiet while provisioning, in every shell you use for it:
`export DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0`. Otherwise the
first interactive shell pulls the checkout and starts the unpinned skill sync
in the middle of the bootstrap.

### macOS

```sh
xcode-select --install          # H1-xcode-clt: git comes with the Command Line Tools (GUI dialog)
git clone --recurse-submodules https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles
export DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0
./doctor.sh --host mac
./setup-host.sh --host mac --check
./setup-host.sh --host mac      # exit 3: run the printed H1-homebrew sudo block yourself
./setup-host.sh --host mac      # again, until it exits 0
./stow-all.sh mac
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
./setup-host.sh --host wsl-ubuntu             # exit 3: H1-apt-core, H1-locale, H1-linuxbrew (sudo)
./setup-host.sh --host wsl-ubuntu             # after each sudo block, until it exits 0
./stow-all.sh wsl-ubuntu
chsh -s "$(command -v zsh)"                   # H7-chsh, asks for your password
exec zsh -l
./doctor.sh --host wsl-ubuntu --smoke
```

`lab-ubuntu` adds two sudo blocks (H1-gh-apt-repo, H1-fcitx5) and a relogin
for the input method; add `--tier all` to get kitty and the Nerd Font. An agent
CLI first, if wanted: the Claude Code installer as on macOS.

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
./setup-host.sh --host sherlock                    # builds the login env inside the job
exit                                               # back to the login node
PATH="$HOME/micromamba/envs/login/bin:$PATH" ./stow-all.sh sherlock
exec "$HOME/micromamba/envs/login/bin/zsh" -l
./doctor.sh --host sherlock --smoke
```

`stow` lives in the login env, which is on PATH only once the overlay is
stowed, hence the one-shot `PATH=` prefix. From then on `ssh sherlock` from a
workstation lands in that zsh. Agent CLIs come from modules
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
.\setup-host.ps1 -Host win
# in an elevated PowerShell 7 (Run as administrator), from $HOME\dotfiles:
.\stow-all.ps1 win
# open a new terminal, then from $HOME\dotfiles:
.\doctor.ps1 -Host win
```

The remaining Windows steps are HUMAN: execution policy, the optional
automatic-stow task, the ssh-agent service, WSL and authentication (`HW-*`
below). An agent CLI first, if wanted: `winget install --id Anthropic.ClaudeCode -e`.

### Other Linux

There is no Fedora, Arch or generic Ubuntu overlay. Stow `common/` only and
install packages yourself ([X-other-linux](#x-other-linux-other-linux-distributions)):

```sh
# with your package manager: git zsh curl rsync tar file tmux man, python3 >= 3.11, GNU Stow >= 2.3.1
git clone --recurse-submodules https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles
export DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0
./doctor.sh --platform other
./setup-host.sh --platform other --check
./setup-host.sh --platform other           # platform-neutral rows only: clones, bat theme, dirs, setup-sync
./stow-all.sh                              # no host argument: common only
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
| `--quiet` | Only rows that are not `ok` |
| `--online` | Adds the only network probes: `gh auth status`, `claude auth status`, `codex login status` |
| `--smoke` | Runs `DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0 zsh -ic true` and fails on `plugin .* not found`, `command not found` or `no such file` in its stderr. The one mode that may write (zsh's own caches) |
| `--list` | The rows and checks that apply, without probing |

Each line reads `[dotfiles] [<level>] <tier> <id>: <detail> (docs/bootstrap.md <step-id>)`,
for example `[dotfiles] [error] core fzf: 0.44.1 < 0.58.0 (docs/bootstrap.md S2-brew-bundle)`.
Statuses are `ok`, `outdated`, `missing`, `warn`, `skip` and `human`. Besides the
`tools.tsv` rows the doctor runs structural checks: `locale`, `venv-sync`,
`submodule`, `stow-links`, `path-order`, `rc-pollution`, `omz-order` and
`nvm-homebrew`. The step it cites is profile-specific: on `hpc`, Brewfile rows
point at S2-login-env and nvm/Claude/Codex rows at S2-modules; on `windows`,
they point at the `W1-*` and `HW-*` steps.

| Exit | Meaning |
| --- | --- |
| 0 | Every row in the selected tiers is `ok` |
| 1 | A selected-tier row is `missing` or `outdated`, or a structural check failed |
| 2 | Usage error, invalid manifest, unknown host, or `--host win` |

### setup-host.sh

```text
./setup-host.sh (--host H | --platform P) [--tier LIST] [--check] [--yes]
                [--only STEP] [--skip STEP] [--keep-going]
./setup-host.sh --print-manual | --list | --help
```

| Flag | Meaning |
| --- | --- |
| `--host H` / `--platform P` | As for the doctor; `win` is refused |
| `--tier LIST` | As for the doctor; default `core,cli,ai` |
| `--check` | Print the plan and the HUMAN blocks; no writes, no network |
| `--yes` | Required when stdin is not a terminal (agents, CI); without it such a run exits 2 |
| `--only STEP`, `--skip STEP` | Run or skip one step id from this file |
| `--keep-going` | Continue past a failed step; the run still exits 1 |
| `--print-manual` | The rows no manifest installs on this host (OS baseline, Lmod, host tools), with their steps |
| `--list` | The steps for this host, in run order |

Every step runs check, plan, apply, verify; a satisfied step is skipped, so a
second run changes nothing. During apply it exports `DOTFILES_AUTO_UPDATE=0
AWESOME_SKILLS_AUTO_UPDATE=0 GIT_TERMINAL_PROMPT=0 NONINTERACTIVE=1
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1`.
Before probing anything, both scripts prepend to their own PATH the directory of
the Homebrew they find (`/opt/homebrew`, `/usr/local`,
`/home/linuxbrew/.linuxbrew`) and, on hpc, `~/micromamba/envs/login/bin`, so a
pre-stow run sees what earlier steps installed; neither writes that to an rc
file. Downloads use `curl -fsSL --proto '=https' --tlsv1.2 --retry 3` into a
`.part` file that must match the pinned sha256 before it is used; a mismatch
deletes it and fails the step.

| Exit | Meaning |
| --- | --- |
| 0 | Done: every selected step is satisfied |
| 1 | A step failed |
| 2 | Usage error or refusal: unknown host, `win`, no terminal without `--yes`, invalid manifest |
| 3 | HUMAN steps are pending; handle the printed blocks and run it again |

The Windows twins take the same ideas as PowerShell parameters:
`.\doctor.ps1 -Host win [-Tier LIST] [-Tsv] [-Online]` and
`.\setup-host.ps1 -Host win [-Tier LIST] [-Check] [-Yes]`. Both need
PowerShell 7 and never elevate themselves.

### HUMAN blocks

The installer prints, and never runs, these blocks on stdout:

```text
HUMAN-BEGIN H1-apt-core sudo
sudo apt-get update
sudo apt-get install -y --no-install-recommends zsh git git-lfs ...
HUMAN-END
```

The first line names the step and the kind; every line up to `HUMAN-END` is one
command, in order.

| Kind | Who runs it | Meaning |
| --- | --- | --- |
| `sudo` | The person, or an agent after the person approves it in chat | Needs root (on Windows, an elevated shell): system packages, `/home/linuxbrew`, apt sources, services |
| `auth` | The person | Browser or device-code login, passwords, keys, Kerberos tickets |
| `gui` | The person | A dialog or a Settings toggle (Xcode CLT, Developer Mode, UAC) |
| `alloc` | The person | A Slurm allocation; heavy work on hpc runs only inside one |
| `chsh` | The person | Changes the login shell and asks for the password |
| `inspect` | The person reads, then runs | A vendor script that cannot be pinned by digest: read it before it runs |
| `judgment` | The person decides | A choice with tradeoffs: stowing, opt-in sync, `/etc/wsl.conf`, sandbox settings |

### Guarantees

- `./doctor.sh` without `--smoke`, and `./setup-host.sh --check`, write nothing
  anywhere and make no network calls (`--online` adds only the three auth probes).
- The installer never invokes `sudo`, `chsh`, `stow`, `./stow-all.sh`,
  `conda init`, `micromamba shell init` or `git lfs install`, and never edits an
  rc file. The only write it causes inside the checkout is `.venv-sync`, through
  `./setup-sync.sh`.
- No `curl | sh`: every script is downloaded to a scratch directory first, and
  only `inspect` rows (today just Claude Code's installer) have no digest.
- Everything a person must do ends up in a HUMAN block; exit 3 means some are
  still pending.

### Fetching a pinned artifact by hand

The automatic steps below also list a manual equivalent. Those that download use
this helper, which reads the URL and digest from `installers.tsv` instead of
copying them here. Paste it into the shell you are working in:

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
    _out=$(mktemp -d)/$(basename "$_url") || return 1
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
```

Per-architecture rows (`micromamba`, `codex`, `kitty`) need `"$(uname -m)"`
as the second argument (`x86_64` or `aarch64`).

## Running it with an agent

The project skill is `/dotfiles-bootstrap` in Claude Code
(`.claude/skills/dotfiles-bootstrap/`, invoked only on request) and
`$dotfiles-bootstrap` in Codex (`.agents/skills/dotfiles-bootstrap/`). Both are
short and send the agent here. The rules they follow:

- **Host.** The agent asks which overlay this machine is; it never infers one
  from the OS. `--platform other` is the answer for anything without an overlay.
- **Quiet hooks.** Every command runs with
  `DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0`.
- **Plan first.** `./doctor.sh --host H --tsv` and
  `./setup-host.sh --host H --check`, shown to the person, before any apply.
  The apply is `./setup-host.sh --host H --yes`, because an agent's shell has
  no terminal. It writes outside the clone (`~/.oh-my-zsh`, `~/.local`, `~/.nvm`)
  and needs the network, so a sandboxed agent asks to run it with broader
  permissions; approving that one command is expected.
- **`sudo` blocks** run only after the person approves the block in chat. Each
  line is then run as one visible top-level shell command, exactly as printed:
  never wrapped in `sh -c`, never inside a script, never chained to another
  command. If sudo would ask for a password and the agent's shell has no
  terminal, the person runs the block in their own terminal instead.
- **`auth`, `gui`, `alloc` and `chsh` blocks** are handed to the person, who
  says when they are done. **`inspect`** blocks: the agent shows the script's
  digest, size and contents and waits. **`judgment`** blocks: the agent explains
  the choice and lets the person make it.
- **Stow.** `./stow-all.sh H` writes under `~/.claude` and `~/.codex` (and
  links `~/.ssh`). `~/.claude` is a protected path whose writes Claude Code's
  auto mode cannot pre-approve, so the agent runs it only as its own visible
  top-level command that the person approves, or leaves it to the person. Never
  launder it through a wrapper script.
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
   or --platform other. Never guess.
4. Run every command with DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0.
5. Run ./doctor.sh --host H --tsv and ./setup-host.sh --host H --check and show me the plan.
6. After I agree, run ./setup-host.sh --host H --yes. For each HUMAN block:
   sudo: show it and wait for my approval, then run each line as its own visible
   top-level command (never sh -c, never a script, never chained);
   auth, gui, alloc, chsh: hand them to me and wait;
   inspect: show me the script's digest and contents and wait;
   judgment: explain the choice and let me decide.
7. Re-run setup-host until it exits 0. Run ./stow-all.sh H only as its own
   visible command after I approve it.
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
  check is `ok`.
- **Human:** yes (judgment: choose the host overlay; a clone elsewhere also
  needs `DOTFILES_DIR` exported)

## Phase 1: host prerequisites

These need root or a GUI, so the installer only prints them.

### H1-xcode-clt: Xcode Command Line Tools

Applies to `mac`. Provides `git`, `make` and the compilers Homebrew needs;
`git`, `bash`, `zsh`, `curl`, `rsync`, `tar`, `file`, `col` and `man` are
macOS baseline (manual rows in `tools.tsv`).

- **Check:** `xcode-select -p`
- **Install:** `xcode-select --install`
- **Verify:** `xcode-select -p && git --version`
- **Human:** yes (GUI: macOS opens an install dialog)

### H1-homebrew: Homebrew on macOS

Applies to `mac`. Uses the commit-pinned `homebrew` row in
[`installers.tsv`](../config/bootstrap/installers.tsv). A fresh Homebrew stays
off PATH until the stowed zsh loads oh-my-zsh's `brew` plugin, so `doctor.sh`
and `setup-host.sh` prepend the directory of the brew they find to their own
PATH. In a pre-stow shell where you run brew by hand, use
`eval "$(/opt/homebrew/bin/brew shellenv)"` (Intel: `/usr/local/bin/brew`) in
that shell only.

- **Check:** `/opt/homebrew/bin/brew --version || /usr/local/bin/brew --version`
- **Install:** `setup-host.sh` downloads and checks the script, then prints a
  sudo block with its path. By hand: `f=$(fetch_pinned homebrew)`, then
  `sudo -v`, then `NONINTERACTIVE=1 /bin/bash "$f"` in the same terminal
  (non-interactive mode only works with sudo credentials already cached).
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

- **Check:** `/home/linuxbrew/.linuxbrew/bin/brew --version`
- **Install:** the printed sudo block. By hand: `f=$(fetch_pinned homebrew)`,
  `sudo -v`, then `NONINTERACTIVE=1 /bin/bash "$f"` in the same terminal.
- **Verify:** `/home/linuxbrew/.linuxbrew/bin/brew --version`; doctor row
  `linuxbrew` is `ok`.
- **Human:** yes (sudo: creates `/home/linuxbrew` and gives it to you)

Never append the installer's "Next steps" lines to `~/.bashrc` or `~/.zshrc`;
the overlay already has them.

### H1-gh-apt-repo: GitHub CLI apt repository

Applies to `lab-ubuntu` (manual row `gh-apt`): its `.gitconfig_local` uses
`!/usr/bin/gh auth git-credential` for github.com, so `/usr/bin/gh` must be the
current GitHub CLI from cli.github.com, not Ubuntu's older package. The
Linuxbrew `gh` stays first on PATH; both share `~/.config/gh`.

- **Check:** `/usr/bin/gh --version | head -n 1; apt-cache policy gh | grep -c cli.github.com`
- **Install:** download the keyring as yourself, compare it with the
  fingerprint GitHub publishes in
  [its Linux install guide](https://github.com/cli/cli/blob/trunk/docs/install_linux.md),
  then run each sudo line on its own:

  ```sh
  tmp=$(mktemp -d)
  curl -fsSL --proto '=https' -o "$tmp/githubcli-archive-keyring.gpg" https://cli.github.com/packages/githubcli-archive-keyring.gpg
  gpg --show-keys "$tmp/githubcli-archive-keyring.gpg"
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' "$(dpkg --print-architecture)" >"$tmp/github-cli.list"
  sudo install -D -m 0644 "$tmp/githubcli-archive-keyring.gpg" /etc/apt/keyrings/githubcli-archive-keyring.gpg
  sudo install -D -m 0644 "$tmp/github-cli.list" /etc/apt/sources.list.d/github-cli.list
  sudo apt-get update
  sudo apt-get install -y gh
  ```

- **Verify:** `/usr/bin/gh --version` is at least the `gh` floor in `tools.tsv`;
  doctor row `gh-apt` is `ok`.
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
- **Human:** yes (reboot/relogin: the input method starts with the desktop session)

## Phase 2: package managers and environments

### S2-brew-bundle: Brewfile bundles

Applies to `mac`, `wsl-ubuntu` and `lab-ubuntu`. One Brewfile per tier in
[`brew/`](../config/bootstrap/brew/): `core` (stow, python, fzf, zoxide, eza,
fd, bat; on macOS also git-lfs and tmux), `cli` (ripgrep, git-delta, tlrc,
chafa, jq, neovim, aria2, uv, gh), `ai` and `desktop` (macOS casks only:
claude-code and codex; kitty, wezterm and the CaskaydiaMono Nerd Font) and
`contributor`. `--no-upgrade` never upgrades what is already installed, so an
old formula shows up as `outdated` in the doctor; upgrade it deliberately with
`brew upgrade <name>`. Never `brew bundle cleanup`.

- **Check:** `brew bundle check --no-upgrade --file=config/bootstrap/brew/core.Brewfile` (repeat per tier)
- **Install:** automatic via setup-host.sh, for each selected tier:
  `brew bundle --file=config/bootstrap/brew/<tier>.Brewfile --no-upgrade` with
  `HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1`.
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
  partition and account Marlowe requires). Then `cd ~/dotfiles`, export the two
  `*_AUTO_UPDATE=0` variables again and re-run setup-host.
- **Verify:** `echo "$SLURM_JOB_ID"` is non-empty and `hostname` is a compute node.
- **Human:** yes (allocation: queueing and resources are the person's call)

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
  `CONDA_PKGS_DIRS` is inherited: the overlay `.profile` points it at a cache
  under `$SCRATCH` once stowed; before that it defaults to `~/micromamba/pkgs`,
  inside your home quota (`sh_quota` on Sherlock).
- **Verify:** `./doctor.sh --host sherlock` shows `login-env` and the tool rows `ok`.
- **Human:** no (after H2-alloc)

Never create the env under `$SCRATCH`: scratch is purged (90 days on Sherlock)
and would take the login shell with it. A package cache there is fine.

### S2-modules: HPC modules and manual AI CLIs

Applies to `sherlock` and `marlowe`, and is where the doctor points for `nvm`,
`node`, `claude` and `codex` on hpc. There is no installer for this step: the
cluster provides Lmod, and the overlay zsh rc pins the modules it loads.

- **Check:** `echo "$LMOD_DIR"; ml spider claude-code codex pi-coding-agent; node --version`
- **Install:** none; `ml <module>` in your own session, or the overlay line for
  pinned modules.
- **Verify:** in a stowed zsh, `ml list` shows the pinned modules and
  `node --version` meets the `node` floor in `tools.tsv`.
- **Human:** yes (judgment: module availability and versions differ per cluster
  and change over time)

**Node.js.** On `marlowe`, `node` comes from the login env
([S2-login-env](#s2-login-env-hpc-login-environment): conda-forge `nodejs`,
currently 26.x). On `sherlock`, it comes from Lmod `ml nodejs/24.13.0`, which
`sherlock/zsh/.config/zsh/.zshrc` loads after putting the login env on PATH, so
the module wins. There is no nvm on hpc.

**Lmod pins.** The `ml ...` line in each overlay zsh rc names exact module
versions (`ml spider <name>` lists what exists); a bump is a reviewed change.

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
- **Verify:** doctor rows `oh-my-zsh`, `powerlevel10k` and the six plugins are
  `ok`; `git -C DEST rev-parse HEAD` equals each pinned `ref`.
- **Human:** no

A clean clone on another commit is re-pinned; a clone with local changes is
refused (see [X-recovery](#x-recovery-recovery-recipes)). Never run the upstream
oh-my-zsh installer: it replaces `~/.zshrc` and can change your login shell.

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
- **Install:** automatic via setup-host.sh with the tag-pinned `nvm` row:
  `PROFILE=/dev/null bash install.sh` (so it edits no rc file), then
  `nvm install --lts` and `nvm alias default 'lts/*'`. By hand:
  `f=$(fetch_pinned nvm) && PROFILE=/dev/null bash "$f"`, then
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
- **Verify:** it prints `AI-sync runtime ready`; the doctor's `venv-sync` check is `ok`.
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
- **Install:** setup-host.sh downloads `https://claude.ai/install.sh` to a
  scratch directory and prints a `HUMAN-BEGIN S5-claude inspect` block with its
  sha256, size and path. Read it: it should fetch Claude Code from Anthropic
  into your home directory and must not call sudo or edit rc files. Then run
  `bash <path>`. By hand: `f=$(fetch_pinned claude)`, `less "$f"`, `bash "$f"`.
- **Verify:** `claude --version` prints a version and `command -v claude` is
  `~/.local/bin/claude`; `git -C ~/dotfiles status --porcelain` is empty.
- **Human:** yes (judgment, HUMAN kind inspect: an unpinned vendor script is read
  before it runs)

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
  ln -s bin/codex "$tmp/codex"
  mv "$tmp" "$dest/releases/$rel"
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

- **Check:** `fc-list | grep -qi 'CaskaydiaMono Nerd Font' && echo ok`
  (macOS: `ls ~/Library/Fonts /Library/Fonts | grep -i CaskaydiaMono`)
- **Install:** automatic via setup-host.sh: extract into
  `$XDG_DATA_HOME/fonts/CaskaydiaMonoNerdFont` (default
  `~/.local/share/fonts/...`), then `fc-cache -f`. By hand:
  `f=$(fetch_pinned nerd-font) && d=~/.local/share/fonts/CaskaydiaMonoNerdFont && mkdir -p "$d" && tar -C "$d" -xJf "$f" && fc-cache -f`
- **Verify:** the check prints `ok`; prompt and `eza` icons render in kitty and WezTerm.
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
creates `~/.bashrc` and `~/.profile`.

- **Check:** `cd ~/dotfiles && stow -n --restow --no-folding -d common $(ls common)`
  (a dry run that lists every conflict; repeat with the overlay directory)
- **Install:** move conflicting regular files aside (for example
  `mv ~/.bashrc ~/.bashrc.pre-dotfiles`), then `./stow-all.sh H`. On hpc,
  `PATH="$HOME/micromamba/envs/login/bin:$PATH" ./stow-all.sh H`, because `stow`
  lives in the login env.
- **Verify:** `ls -l ~/.zshrc ~/.profile ~/.gitconfig` shows links into
  `~/dotfiles/common/`; the doctor's `stow-links` and `path-order` checks are `ok`.
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
- **Human:** yes (password: `chsh` asks for it)

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
    ticket.
  - lab-ubuntu: Git Credential Manager with `credentialStore = gpg` needs a gpg
    key and `pass init <gpg-key-id>`. wsl-ubuntu uses the Windows-side Git
    Credential Manager from Git for Windows.
- **Verify:** `./doctor.sh --host H --online` shows the three auth probes `ok`.
- **Human:** yes (browser auth, passwords and key passphrases)

### H7-sync-skills: Skill library sync

Applies to every Unix host. Once stowed, every interactive shell sources
`scripts/awesome-skills-update.sh`, which downloads the unpinned `main`
`install.sh` of FridrichMethod/awesome-skills and runs it; the first run fills
`~/.claude/skills` and `~/.codex/skills`, later runs refresh weekly in the
background. It needs bash, curl, tar and rsync. It is the one download near the
bootstrap that is not pinned, so it stays off (`AWESOME_SKILLS_AUTO_UPDATE=0`)
until you decide.

- **Check:** `ls ~/.claude/skills ~/.codex/skills 2>/dev/null | head; ls -l "${XDG_CACHE_HOME:-$HOME/.cache}/awesome-skills/last-sync"`
- **Install:** opt-in: in a stowed shell, `sync-skills` runs it once in the
  foreground; leaving `AWESOME_SKILLS_AUTO_UPDATE` unset enables the weekly hook.
- **Verify:** `ls ~/.claude/skills | wc -l` is non-zero; the log is
  `${XDG_CACHE_HOME:-$HOME/.cache}/awesome-skills/last.log`.
- **Human:** yes (judgment: it runs an unpinned script from a branch head)

### H7-doctor: Final doctor run

Applies to every host. This is the completion gate.

- **Check:** `./doctor.sh --host H --smoke` (Windows: `.\doctor.ps1 -Host win`)
- **Install:** none; follow the step each failing row names, then run it again.
- **Verify:** exit 0. Add `--online` for the auth probes and `--tier all` to see
  the desktop, contributor and host rows.
- **Human:** no

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
  Clone onto NTFS, never into a WSL distribution.
- **Verify:** `core.symlinks` prints `true`, `LinkType` prints `SymbolicLink`,
  and `git -C $HOME\dotfiles status --porcelain` is empty.
- **Human:** yes (GUI: Developer Mode is a Settings toggle)

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
- **Human:** yes (GUI: machine-wide installers can raise a UAC prompt)

### W1-psresources: PowerShell modules

PSFzf, CompletionPredictor and Microsoft.WinGet.CommandNotFound, which the
PowerShell 7 profile uses only when present.

- **Check:** `Get-InstalledPSResource PSFzf, CompletionPredictor, Microsoft.WinGet.CommandNotFound`
- **Install:** automatic via setup-host.ps1, only for the missing ones:
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

- **Check:** `Test-Path .\.venv-sync\Scripts\python.exe`
- **Install:** automatic via setup-host.ps1: `.\setup-sync.ps1`. If `python`
  resolves to the Microsoft Store alias, pass a real interpreter:
  `.\setup-sync.ps1 -Python <path>`, with the path from `py -0p`.
- **Verify:** it prints `AI-sync runtime ready`.
- **Human:** no

### HW-execution-policy: Execution policy

The tracked profiles and scripts are local files, which `RemoteSigned` allows.

- **Check:** `Get-ExecutionPolicy -List`
- **Install:** `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`,
  in each of PowerShell 7 and Windows PowerShell 5.1 that you use (they keep the
  setting separately).
- **Verify:** `Get-ExecutionPolicy -Scope CurrentUser` prints `RemoteSigned`.
- **Human:** yes (judgment: a security setting)

### HW-stow: Elevated stow

`stow-all.ps1` creates the links; links made without elevation can be rejected
by processes that enforce RedirectionGuard, such as current Windows OpenSSH
(see the README's Windows section).

- **Check:** `.\stow-all.ps1 win -WhatIf` (validates and previews, writes nothing)
- **Install:** in an elevated PowerShell 7 (Run as administrator), from
  `$HOME\dotfiles`: `.\stow-all.ps1 win`
- **Verify:** `(Get-Item $HOME\.gitconfig).LinkType` prints `SymbolicLink` and
  `.\doctor.ps1 -Host win` passes.
- **Human:** yes (sudo: it needs an elevated shell)

Limitation: nothing adds `~\.local\bin` to the Windows PATH, so `shk.cmd` (from
`.\setup-sherlock-kit.ps1`) is not found by name. Call it by its full path, or
add that directory to your user PATH yourself.

### HW-auto-stow-task: Automatic stow task

Optional. The login updater can restow after a pull through a current-user task
that runs this checkout's scripts with highest privileges.

- **Check:** `Get-ScheduledTask -TaskName 'Dotfiles-Restow-*' -ErrorAction Ignore`
- **Install:** in an elevated PowerShell 7: `.\scripts\dotfiles-auto-stow.ps1 -Register`
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
- **Human:** yes (sudo, reboot and judgment)

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
- **Human:** yes (browser auth and key passphrases)

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
`--platform debian` for the doctor's rows.

- **Check:** `./doctor.sh --platform other`
- **Install:** with the distribution's package manager, the equivalents of
  [`apt/common.txt`](../config/bootstrap/apt/common.txt) and the Brewfile tools,
  meeting every floor in [`tools.tsv`](../config/bootstrap/tools.tsv) (distro
  fzf, eza and gh are often older); or install Homebrew on Linux yourself and run
  `brew bundle --file=config/bootstrap/brew/<tier>.Brewfile --no-upgrade`. Then
  `./setup-host.sh --platform other` for the platform-neutral steps (clones, bat
  theme, Vim directories, setup-sync) and `./stow-all.sh` with no host.
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

Then re-run `./setup-host.sh --host H` for the theme and plugin clones.

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
it is the link into `~/dotfiles`; then `./stow-all.sh H` and, if needed,
[H7-chsh](#h7-chsh-login-shell).

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
