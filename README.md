# .dotfiles

**Cross-platform dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/).** One repo. Many machines. Zero friction.

[![CI](https://img.shields.io/github/actions/workflow/status/FridrichMethod/dotfiles/ci.yml?label=CI&style=flat-square)](https://github.com/FridrichMethod/dotfiles/actions)
[![License](https://img.shields.io/github/license/FridrichMethod/dotfiles?style=flat-square)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/FridrichMethod/dotfiles?style=flat-square)](https://github.com/FridrichMethod/dotfiles/commits/main)

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Structure](#structure)
- [Packages](#packages)
- [Hosts](#hosts)
- [How It Works](#how-it-works)
- [Auto-update Hooks](#auto-update-hooks)
- [Pre-commit Hooks](#pre-commit-hooks)
- [AI Assistant Guides](#ai-assistant-guides)
- [Adding a New Package](#adding-a-new-package)
- [License](#license)

## Overview

Shared defaults live in `common/`. Host-specific overlays layer on top, so
each machine gets exactly the config it needs — no conditionals, no templating.

## Quick Start

```bash
git clone https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles
git submodule update --init --recursive
./stow-all.sh <host-dir>   # e.g. mac, wsl-ubuntu, sherlock
```

> `.stowrc` sets `--target=~`, so Stow links everything into your home directory.

## Structure

```
dotfiles/
├── common/          shared defaults (stowed first)
│   ├── aria2/
│   ├── bash/
│   ├── conda/
│   ├── git/
│   ├── kitty/
│   ├── pymol/       submodule — auto-updated daily via GitHub Actions
│   ├── sh/
│   ├── ssh/
│   ├── tcsh/
│   ├── vim/
│   ├── wezterm/
│   ├── xonsh/
│   └── zsh/
│
├── mac/             macOS overrides
├── wsl-ubuntu/      WSL Ubuntu overrides
├── lab-ubuntu/      lab Ubuntu overrides
├── fedora/          Fedora overrides
├── ubuntu/          Ubuntu overrides
├── sherlock/        Stanford Sherlock HPC
├── marlowe/         host overrides
├── win/             Windows-side config (WezTerm, .wslconfig)
│
├── stow-all.sh             one-command installer
├── dotfiles-update.sh      session-once auto-pull on shell startup
├── awesome-skills-update.sh weekly Claude/Codex skill sync from github.com/FridrichMethod/awesome-skills
└── .stowrc                 Stow defaults (target = ~)
```

## Packages

| Category | Tools |
|----------|-------|
| **Shell** | Zsh, Bash, POSIX sh, tcsh, xonsh |
| **Terminal** | Kitty, WezTerm |
| **Editor** | Vim |
| **Version Control** | Git, SSH |
| **Science** | Conda, PyMOL scripts |
| **Utilities** | Aria2 |

## Hosts

| Host | Platform | Layers |
|------|----------|--------|
| `mac` | macOS | bash, git, sh, ssh, zsh |
| `wsl-ubuntu` | WSL 2 | bash, git, sh, ssh, zsh |
| `lab-ubuntu` | Ubuntu (lab) | bash, git, sh, ssh, zsh |
| `fedora` | Fedora | bash, zsh |
| `ubuntu` | Ubuntu | bash, zsh |
| `sherlock` | Stanford HPC | bash, sh, zsh |
| `marlowe` | Custom host | bash, sh, zsh |
| `win` | Windows | wezterm, wsl |

## How It Works

```
common/zsh/.zshrc  ──stow──▶  ~/.zshrc
mac/git/.gitconfig ──stow──▶  ~/.gitconfig   (overrides common)
```

1. **`common/`** is stowed first — shared baseline for every machine.
2. **`<host>/`** is stowed second — host-specific files override or extend common.
3. Stow runs with `--no-folding`, so individual files are linked (not entire directories).

## Auto-update Hooks

Two small shell hooks run automatically on each interactive shell login — both are session-throttled, so they don't slow down every subshell or tmux pane.

### `dotfiles-update.sh`

Fetches this repo and fast-forwards when behind, then nudges you to re-stow and reload the shell. Sourced from `common/zsh/.zshrc` (zsh) and `common/sh/.profile` (bash/POSIX login shells).

Disable with `export DOTFILES_AUTO_UPDATE=0`.

### `awesome-skills-update.sh`

Keeps `~/.claude/skills/` and `~/.codex/skills/` in sync with [github.com/FridrichMethod/awesome-skills](https://github.com/FridrichMethod/awesome-skills) — a curated collection of ~1,668 Claude Code / Codex skills for AI4Protein, bioinformatics, AI development, and academic writing.

#### Requirements

The upstream installer is `curl … | bash`, so the host needs `bash`, `curl`, `tar`, and `rsync`. The hook is defensive: it silently no-ops when `curl` is missing, and the upstream installer prints a clear "Missing required tool: X" if `tar` or `rsync` is missing — failed runs do **not** advance the stamp, so the sync retries automatically once the dep is installed.

All four are pre-installed on macOS and most Linux desktop distros. The one tool you might need to add on a minimal Linux box is `rsync`:

| Platform | Install command |
|---|---|
| Debian / Ubuntu / WSL Ubuntu | `sudo apt-get install -y curl tar rsync` |
| Fedora / RHEL | `sudo dnf install -y curl tar rsync` |
| Arch | `sudo pacman -S --needed curl tar rsync` |
| macOS (Homebrew) | `brew install rsync` (curl/tar/bash are built-in) |
| Stanford Sherlock | `module load system rsync` (curl/tar are in base PATH) |
| Conda envs | `conda install -c conda-forge rsync curl tar` |

After install, force a sync to confirm everything works:

```bash
sync-skills
```

#### Behavior

| Aspect | Default |
|---|---|
| First-time install | Foreground (you see the curl progress) |
| Refresh interval | Every **7 days** |
| Subsequent refreshes | **Background** — never blocks shell startup |
| Lockfile | `$XDG_CACHE_HOME/awesome-skills/in-progress.pid` prevents parallel syncs from concurrent shells |
| Log | `$XDG_CACHE_HOME/awesome-skills/last.log` (or `~/.cache/awesome-skills/last.log`) |
| Failure handling | Stamp not advanced → retries next shell session |
| Manual trigger | `sync-skills` alias |

#### Env knobs

| Variable | Default | Effect |
|---|---|---|
| `AWESOME_SKILLS_AUTO_UPDATE` | `1` | set to `0` to disable entirely |
| `AWESOME_SKILLS_REFRESH_DAYS` | `7` | change the throttle window |
| `AWESOME_SKILLS_FORCE` | `0` | set to `1` to bypass throttle once |
| `AWESOME_SKILLS_BG` | `1` | set to `0` to run synchronously |
| `AWESOME_SKILLS_INSTALLER_URL` | upstream `install.sh` | point at a fork or branch |

Run a manual sync any time:

```bash
sync-skills
```

## Pre-commit Hooks

Optional but recommended — keeps configs clean before every commit:

```bash
pip install pre-commit   # or: brew install pre-commit
pre-commit install
pre-commit run --all-files
```

| Hook | Scope |
|------|-------|
| **shellcheck** | `.sh`, `.bash*` |
| **shfmt** | `.sh`, `.bash*`, `.zsh*` |
| **stylua** | `*.lua` |
| **built-in** | whitespace, EOF, merge conflicts, YAML, JSON, TOML |

## AI Assistant Guides

- [`CLAUDE.md`](CLAUDE.md) — guidance for Claude Code.
- [`AGENTS.md`](AGENTS.md) — guidance for OpenAI Codex and other agents following the `AGENTS.md` convention.

Both files are self-contained and cover repo scope, required conventions, working commands, verification, and per-topic conventions (shell, Git/SSH, Stow, workflows). Editor-specific tooling configs (such as `.cursor/`) are local-only and not tracked.

## Adding a New Package

```bash
# 1. Create the package directory mirroring $HOME paths
mkdir -p common/newtool/.config/newtool

# 2. Add your config files
cp ~/.config/newtool/config.toml common/newtool/.config/newtool/

# 3. Stow it
stow --dir=common newtool
```

## License

[MIT](LICENSE)
