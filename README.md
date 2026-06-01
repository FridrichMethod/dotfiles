<div align="center">

# `~/.dotfiles`

**Cross-platform shell, terminal, and tool configs — one repo, eight hosts, zero conditionals.**

Powered by [GNU Stow](https://www.gnu.org/software/stow/). Layered like CSS. Boring on purpose.

<br/>

[![CI](https://img.shields.io/github/actions/workflow/status/FridrichMethod/dotfiles/ci.yml?branch=main&label=CI&logo=github&style=for-the-badge)](https://github.com/FridrichMethod/dotfiles/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/FridrichMethod/dotfiles?style=for-the-badge)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/FridrichMethod/dotfiles?style=for-the-badge&logo=git&logoColor=white)](https://github.com/FridrichMethod/dotfiles/commits/main)
[![Stars](https://img.shields.io/github/stars/FridrichMethod/dotfiles?style=for-the-badge&logo=github)](https://github.com/FridrichMethod/dotfiles/stargazers)

[![Stow](https://img.shields.io/badge/managed_by-GNU_Stow-4EAA25?style=flat-square&logo=gnu&logoColor=white)](https://www.gnu.org/software/stow/)
[![shellcheck](https://img.shields.io/badge/lint-shellcheck-89e051?style=flat-square&logo=gnubash&logoColor=white)](https://www.shellcheck.net/)
[![shfmt](https://img.shields.io/badge/format-shfmt-1f425f?style=flat-square)](https://github.com/mvdan/sh)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-FAB040?style=flat-square&logo=pre-commit&logoColor=white)](https://pre-commit.com/)
[![Conventional Commits](https://img.shields.io/badge/Conventional_Commits-1.0.0-FE5196?style=flat-square&logo=conventionalcommits&logoColor=white)](https://www.conventionalcommits.org/)

<sub>macOS · WSL · Ubuntu · Fedora · Stanford Sherlock HPC · Marlowe · Windows</sub>

</div>

---

```bash
git clone https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles && git submodule update --init --recursive
./stow-all.sh mac          # or: wsl-ubuntu, lab-ubuntu, sherlock, marlowe, fedora, ubuntu, win
```

---

## Highlights

- **One command** to install everything on a fresh machine — `./stow-all.sh <host>`.
- **Layered configs**: `common/` is the baseline; `<host>/` overrides where machines differ.
- **No templating, no conditionals** — Stow symlinks the right files into `$HOME`.
- **Self-healing**: a shell hook checks for upstream changes once per login session and fast-forwards behind branches.
- **Skill sync**: a weekly background hook keeps `~/.claude/skills/` and `~/.codex/skills/` aligned with [awesome-skills](https://github.com/FridrichMethod/awesome-skills) (~1,668 skills).
- **CI-checked**: every push runs `shellcheck`, `shfmt`, `stylua`, and hygiene hooks — same as the local pre-commit.
- **HPC-aware**: Stanford Sherlock and Marlowe overlays handle login-node quirks, module systems, and SLURM-friendly defaults.

## Table of Contents

<!-- markdownlint-disable -->
<table>
<tr><td>

- [Quick Start](#quick-start)
- [At a Glance](#at-a-glance)
- [Architecture](#architecture)
- [Packages](#packages)

</td><td>

- [Hosts](#hosts)
- [How Stow Layering Works](#how-stow-layering-works)
- [Auto-update Hooks](#auto-update-hooks)
- [Pre-commit Hooks](#pre-commit-hooks)

</td><td>

- [AI Assistant Guides](#ai-assistant-guides)
- [Adding a New Package](#adding-a-new-package)
- [Conventions](#conventions)
- [License](#license)

</td></tr>
</table>
<!-- markdownlint-enable -->

## Quick Start

**1.** Clone with submodules:

```bash
git clone --recurse-submodules https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

**2.** Stow your host (always stows `common/` first, then the overlay):

```bash
./stow-all.sh mac
```

**3.** Reload your shell:

```bash
exec $SHELL -l
```

> `.stowrc` sets `--target=~` so every package links into `$HOME`. Stow runs with `--restow --no-folding`, so re-running the installer is safe and idempotent.

## At a Glance

| | |
|---|---|
| **Layout** | `common/` + 8 host overlays |
| **Shells** | Zsh, Bash, POSIX sh, tcsh, xonsh |
| **Terminals** | WezTerm, Kitty |
| **Editor** | Vim |
| **Submodule** | [`PyMOLScripts`](https://github.com/FridrichMethod/PyMOLScripts) — auto-updated daily by GitHub Actions |
| **Install** | One command: `./stow-all.sh <host>` |
| **Update** | On every login (throttled to once per session) |
| **CI** | `shellcheck` · `shfmt` · `stylua` · YAML/JSON/TOML hygiene |

## Architecture

```text
                                      ┌──────────────────────────┐
                                      │     ~/.dotfiles          │
                                      │     (this repo)          │
                                      └────────────┬─────────────┘
                                                   │
                          ┌────────────────────────┼────────────────────────┐
                          ▼                        ▼                        ▼
                ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
                │     common/     │      │     <host>/     │      │   stow-all.sh   │
                │  shared layer   │      │  overlay layer  │      │   installer     │
                └────────┬────────┘      └────────┬────────┘      └────────┬────────┘
                         │                        │                        │
                         └──────────┬─────────────┘                        │
                                    │   stow --restow --no-folding   ◀─────┘
                                    ▼
                              ┌───────────┐
                              │    $HOME  │
                              │  symlinks │
                              └───────────┘
```

<details>
<summary><strong>Full directory tree</strong></summary>

```text
dotfiles/
├── common/                       shared defaults (stowed first)
│   ├── aria2/                    download client
│   ├── bash/                     .bashrc, .bash_aliases, .bash_profile
│   ├── conda/                    .condarc
│   ├── git/                      .gitconfig (with [include] ~/.gitconfig_local)
│   ├── kitty/                    Kitty terminal
│   ├── pymol/PyMOLScripts/       submodule — daily auto-update via Actions
│   ├── sh/                       POSIX .profile + .aliases (sourced by bash/zsh)
│   ├── ssh/                      minimal ~/.ssh/config + Include config.d/*.conf
│   ├── tcsh/                     .tcshrc
│   ├── vim/                      .vimrc
│   ├── wezterm/                  .wezterm.lua
│   ├── xonsh/                    .xonshrc
│   └── zsh/                      .zshrc, .zshenv, .zprofile, .p10k.zsh
│
├── mac/                          macOS overrides
├── wsl-ubuntu/                   WSL 2 Ubuntu overrides
├── lab-ubuntu/                   lab Ubuntu (includes Fcitx5 IME config)
├── sherlock/                     Stanford Sherlock HPC
├── marlowe/                      Marlowe HPC
├── fedora/                       Fedora overrides
├── ubuntu/                       Ubuntu desktop overrides
├── win/                          Windows-side (.wezterm.lua, .wslconfig)
│
├── .github/workflows/            ci.yml + daily submodule sync
├── .pre-commit-config.yaml       shellcheck · shfmt · stylua · hygiene
├── .stowrc                       Stow defaults (--target=~, ignores)
├── stow-all.sh                   one-command installer
├── dotfiles-update.sh            session-once auto-pull on shell login
├── awesome-skills-update.sh      weekly Claude/Codex skill sync
├── CLAUDE.md                     guidance for Claude Code
└── AGENTS.md                     guidance for OpenAI Codex / other agents
```

</details>

## Packages

| Category | Tools |
|---|---|
| **Shell** | Zsh (with Powerlevel10k), Bash, POSIX `sh`, tcsh, xonsh |
| **Terminal** | Kitty, WezTerm |
| **Editor** | Vim |
| **Version Control** | Git, SSH |
| **Science** | Conda (`.condarc`), PyMOL scripts (submodule) |
| **Utilities** | Aria2 |
| **Input (Linux)** | Fcitx5 (lab-ubuntu only) |

## Hosts

| Host | Platform | Overlay packages | Files |
|---|---|---|---:|
| [`mac/`](mac/) | macOS | `bash`, `git`, `sh`, `ssh`, `zsh` | 7 |
| [`wsl-ubuntu/`](wsl-ubuntu/) | WSL 2 | `bash`, `git`, `sh`, `ssh`, `zsh` | 6 |
| [`lab-ubuntu/`](lab-ubuntu/) | Ubuntu (lab) | `bash`, `fcitx5`, `git`, `sh`, `ssh`, `zsh` | 9 |
| [`sherlock/`](sherlock/) | Stanford HPC | `bash`, `sh`, `terminfo`, `zsh` | 5 |
| [`marlowe/`](marlowe/) | Marlowe HPC | `bash`, `sh`, `zsh` | 4 |
| [`fedora/`](fedora/) | Fedora | `bash`, `zsh` (placeholders) | — |
| [`ubuntu/`](ubuntu/) | Ubuntu desktop | `bash`, `zsh` (placeholders) | — |
| [`win/`](win/) | Windows | `wezterm`, `wsl` | 3 |
| [`common/`](common/) | _shared baseline_ | 13 packages | 37 |

## How Stow Layering Works

```text
   common/zsh/.zshrc        ──stow──▶  ~/.zshrc            (baseline)
   common/git/.gitconfig    ──stow──▶  ~/.gitconfig        (baseline)
   mac/git/.gitconfig_local ──stow──▶  ~/.gitconfig_local  (host override, [include]'d)
   mac/ssh/.ssh/config.d/*  ──stow──▶  ~/.ssh/config.d/*   (host-specific endpoints)
```

1. **`common/`** is stowed first — every package, every host. Shared baseline.
2. **`<host>/`** is stowed second — overrides where the machine differs.
3. `stow --no-folding` symlinks **individual files**, not whole directories, so the two layers compose cleanly.
4. SSH permissions are re-asserted on every run (`700` on `~/.ssh`, `600` on `config` files) so `sshd` stays happy.

> **Git overrides** flow through `[include] path = ~/.gitconfig_local` — the shared `.gitconfig` includes the host file if it exists.
> **SSH overrides** flow through `Include ~/.ssh/config.d/*.conf` — the shared root config delegates to per-concern fragments.

## Auto-update Hooks

Two small shell hooks run on each interactive shell login. Both are session-throttled, so subshells and tmux panes never re-run them.

<details open>
<summary><strong><code>dotfiles-update.sh</code></strong> — pulls this repo when behind</summary>

Fetches the remote, fast-forwards if behind, then nudges you to re-stow and reload the shell. Sourced from `common/zsh/.zshrc` (zsh) and `common/sh/.profile` (bash/POSIX login shells).

```bash
[dotfiles] 2 new commit(s) available — pulling...
[dotfiles] Pulled successfully.
[dotfiles] Run stow-all.sh to re-stow, then exec zsh to load updated config.
```

| Variable | Default | Effect |
|---|---|---|
| `DOTFILES_AUTO_UPDATE` | `1` | set to `0` to disable |
| `DOTFILES_DIR` | `~/dotfiles` | repo path |

Session marker: `_DOTFILES_CHECKED` — exported so subshells skip instantly; a fresh SSH session (clean env) triggers a new check.

</details>

<details>
<summary><strong><code>awesome-skills-update.sh</code></strong> — weekly Claude/Codex skill sync</summary>

Keeps `~/.claude/skills/` and `~/.codex/skills/` in sync with [`FridrichMethod/awesome-skills`](https://github.com/FridrichMethod/awesome-skills) — a curated collection of ~1,668 Claude Code / Codex skills for AI4Protein, bioinformatics, AI development, and academic writing.

**Behavior**

| Aspect | Default |
|---|---|
| First-time install | Foreground (you see the curl progress) |
| Refresh interval | Every **7 days** |
| Subsequent refreshes | **Background** — never blocks shell startup |
| Lockfile | `$XDG_CACHE_HOME/awesome-skills/in-progress.pid` |
| Log | `$XDG_CACHE_HOME/awesome-skills/last.log` |
| Failure handling | Stamp not advanced → retries next shell session |
| Manual trigger | `sync-skills` alias |

**Requirements** — `bash`, `curl`, `tar`, `rsync`. The hook silently no-ops if `curl` is missing; the installer errors clearly if `tar`/`rsync` are missing. All four are pre-installed on macOS and most Linux desktop distros. Minimal Linux boxes usually just need `rsync`:

| Platform | Install command |
|---|---|
| Debian / Ubuntu / WSL Ubuntu | `sudo apt-get install -y curl tar rsync` |
| Fedora / RHEL | `sudo dnf install -y curl tar rsync` |
| Arch | `sudo pacman -S --needed curl tar rsync` |
| macOS (Homebrew) | `brew install rsync` (curl/tar/bash are built-in) |
| Stanford Sherlock | `module load system rsync` |
| Conda envs | `conda install -c conda-forge rsync curl tar` |

**Env knobs**

| Variable | Default | Effect |
|---|---|---|
| `AWESOME_SKILLS_AUTO_UPDATE` | `1` | set to `0` to disable entirely |
| `AWESOME_SKILLS_REFRESH_DAYS` | `7` | change the throttle window |
| `AWESOME_SKILLS_FORCE` | `0` | set to `1` to bypass throttle once |
| `AWESOME_SKILLS_BG` | `1` | set to `0` to run synchronously |
| `AWESOME_SKILLS_INSTALLER_URL` | upstream `install.sh` | point at a fork or branch |

Force a sync:

```bash
sync-skills
```

</details>

## Pre-commit Hooks

Optional but recommended — same tools CI runs.

```bash
pip install pre-commit          # or: brew install pre-commit
pre-commit install
pre-commit run --all-files
```

| Hook | Scope |
|---|---|
| **shellcheck** | `.sh`, `.bash*`, `.profile`, `.alias(es)` |
| **shfmt** | `.sh`, `.bash*`, `.zsh*` (4-space indent, indented `case`, language-aware) |
| **stylua** | `*.lua`, `*.luau` |
| **hygiene** | trailing whitespace, EOF, merge conflicts, YAML/JSON/TOML, large files |

## AI Assistant Guides

| File | Audience |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | [Claude Code](https://claude.com/claude-code) |
| [`AGENTS.md`](AGENTS.md) | OpenAI Codex and any agent following the [`AGENTS.md`](https://agents.md) convention |

Both files are self-contained and cover repo scope, required conventions, working commands, verification, and per-topic conventions (shell, Git/SSH, Stow, workflows). Editor-specific tooling configs (such as `.cursor/`) are local-only and not tracked.

## Adding a New Package

```bash
# 1. Mirror the $HOME path inside common/ (or under a host overlay)
mkdir -p common/newtool/.config/newtool

# 2. Add your config
cp ~/.config/newtool/config.toml common/newtool/.config/newtool/

# 3. Stow it
stow --restow --no-folding -d common newtool

# 4. (Or: re-run the installer, which picks up all packages automatically)
./stow-all.sh <host>
```

## Conventions

- **Keep secrets out** of version control — use `*_local` files referenced by `[include]` chains.
- **Stow order is sacred**: `common/` first, host second.
- **POSIX vs Bash vs Zsh**: shared logic lives in `common/sh/`; Bash/Zsh-specific syntax stays in matching shell files.
- **CI mirrors local**: every commit is checked with the same `shellcheck`/`shfmt`/`stylua` you run via `pre-commit`.
- **Verification**: after edits, run `pre-commit run --all-files` before committing.

## License

[MIT](LICENSE) — see the file for the full text.

<div align="center">
<sub>Built with <a href="https://www.gnu.org/software/stow/">GNU Stow</a> · CI by <a href="https://docs.github.com/actions">GitHub Actions</a> · Polished with <a href="https://pre-commit.com/">pre-commit</a></sub>
</div>
