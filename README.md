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
├── stow-all.sh      one-command installer
├── dotfiles-update.sh
└── .stowrc          Stow defaults (target = ~)
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
