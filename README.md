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
- **Cross-host AI defaults**: global Claude Code and Codex instructions, permissions, reasoning effort, and portable plugin declarations live in `common/`.
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

- [AI Assistant Configuration](#ai-assistant-configuration)
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
| **AI Assistants** | Claude Code and OpenAI Codex global defaults |
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
│   ├── claude/                   ~/.claude/CLAUDE.md + portable settings sync
│   ├── codex/                    ~/.codex/AGENTS.md + portable config sync
│   ├── conda/                    .condarc
│   ├── git/                      .gitconfig (with [include] ~/.gitconfig_local)
│   ├── kitty/                    Kitty terminal
│   ├── pymol/PyMOLScripts/       submodule — daily auto-update via Actions
│   ├── sh/                       POSIX .profile + .aliases (sourced by bash/zsh)
│   ├── ssh/                      minimal ~/.ssh/config + Include config.d/*.conf
│   ├── tcsh/                     .tcshrc
│   ├── tmux/                     .tmux.conf
│   ├── vim/                      .vimrc
│   ├── wezterm/                  .wezterm.lua
│   ├── xonsh/                    .xonshrc
│   └── zsh/                      .zshrc, .zshenv, .zprofile, .p10k.zsh
│
├── mac/                          macOS overrides
├── wsl-ubuntu/                   WSL 2 Ubuntu overrides
├── lab-ubuntu/                   lab Ubuntu (Fcitx5 IME + claude helper)
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
| **AI Assistants** | Claude Code (`CLAUDE.md`, `settings.json`), OpenAI Codex (`AGENTS.md`, `config.toml`) |
| **Utilities** | Aria2 |
| **Input (Linux)** | Fcitx5 (lab-ubuntu only) |

## Hosts

| Host | Platform | Overlay packages | Files |
|---|---|---|---:|
| [`mac/`](mac/) | macOS | `bash`, `git`, `sh`, `ssh`, `zsh` | 7 |
| [`wsl-ubuntu/`](wsl-ubuntu/) | WSL 2 | `bash`, `git`, `sh`, `ssh`, `zsh` | 6 |
| [`lab-ubuntu/`](lab-ubuntu/) | Ubuntu (lab) | `bash`, `claude`, `fcitx5`, `git`, `sh`, `ssh`, `zsh` | 11 |
| [`sherlock/`](sherlock/) | Stanford HPC | `bash`, `sh`, `terminfo`, `zsh` | 5 |
| [`marlowe/`](marlowe/) | Marlowe HPC | `bash`, `git`, `sh`, `zsh` | 5 |
| [`fedora/`](fedora/) | Fedora | `bash`, `zsh` (placeholders) | — |
| [`ubuntu/`](ubuntu/) | Ubuntu desktop | `bash`, `zsh` (placeholders) | — |
| [`win/`](win/) | Windows | `wezterm`, `wsl` | 3 |
| [`common/`](common/) | _shared baseline_ | 16 packages | 48 |

## How Stow Layering Works

```text
   common/zsh/.zshrc        ──stow──▶  ~/.zshrc            (baseline)
   common/git/.gitconfig    ──stow──▶  ~/.gitconfig        (baseline)
   common/claude/.claude/*  ──stow──▶  ~/.claude/*         (AI baseline)
   common/codex/.codex/*    ──stow──▶  ~/.codex/*          (AI baseline)
   mac/git/.gitconfig_local ──stow──▶  ~/.gitconfig_local  (host override, [include]'d)
   mac/ssh/.ssh/config.d/*  ──stow──▶  ~/.ssh/config.d/*   (host-specific endpoints)
```

1. **`common/`** is stowed first — every package, every host. Shared baseline.
2. **`<host>/`** is stowed second — overrides where the machine differs.
3. `stow --no-folding` symlinks **individual files**, not whole directories, so the two layers compose cleanly.
4. SSH permissions are re-asserted on every run (`700` on `~/.ssh`, `600` on `config` files) so `sshd` stays happy.

> **Git overrides** flow through `[include] path = ~/.gitconfig_local` — the shared `.gitconfig` includes the host file if it exists.
> **SSH overrides** flow through `Include ~/.ssh/config.d/*.conf` — the shared root config delegates to per-concern fragments.
>
> Stow does not merge two files that target the same path. If a host needs a different complete `settings.json` or `config.toml`, move that file from `common/<tool>/` to `<host>/<tool>/`; do not define the same target in both layers.

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

## AI Assistant Configuration

### Repository guides

| File | Audience |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | [Claude Code](https://claude.com/claude-code) |
| [`AGENTS.md`](AGENTS.md) | OpenAI Codex and any agent following the [`AGENTS.md`](https://agents.md) convention |

These root files describe how agents should work **inside this repository**. They are separate from the user-global files stowed into `$HOME`.

### User-global configuration

| Tracked source | Stow target | Synchronized baseline |
|---|---|---|
| [`common/claude/.claude/CLAUDE.md`](common/claude/.claude/CLAUDE.md) | `~/.claude/CLAUDE.md` | Personal instructions across Claude Code projects |
| [`common/claude/.claude/settings.json`](common/claude/.claude/settings.json) | merged into `~/.claude/settings.json` | Permission allowlist, `xhigh`, fullscreen TUI, model, disabled commit/PR attribution, hooks, voice, portable plugin and marketplace declarations |
| [`common/codex/.codex/AGENTS.md`](common/codex/.codex/AGENTS.md) | `~/.codex/AGENTS.md` | Personal instructions across Codex projects |
| [`common/codex/.codex/config.toml`](common/codex/.codex/config.toml) | merged into `~/.codex/config.toml` | `workspace-write`, `auto_review`, network access, `xhigh`, multi-agent, memories |

The Git-stored versions of these files are safe to share across macOS, Linux, and WSL because they contain no credentials or machine-specific absolute paths. Some settings remain **capability-dependent**:

- Claude Code attribution is disabled with empty `attribution.commit` and `attribution.pr` strings; this supersedes the deprecated `includeCoAuthoredBy` setting.
- Codex has no active attribution setting; the aligned global instruction files prohibit `Co-Authored-By`, generated-with lines, and other AI attribution.
- Claude Code fullscreen TUI, `xhigh`, and plugins require a sufficiently recent client; `xhigh` falls back when the selected model does not support it. Plugin declarations are portable, but each host still downloads its own plugin cache.
- Codex `auto_review`, multi-agent, memories, and network access can be constrained by the installed Codex version, selected model, account entitlement, sandbox implementation, or organization policy.
- `project_doc_fallback_filenames = ["CLAUDE.md"]` lets Codex use a project `CLAUDE.md` only when that directory has no `AGENTS.md` or `AGENTS.override.md`; it does not make the two instruction systems identical.

#### Mutable Claude Code state

Claude Code rewrites `~/.claude/settings.json` at runtime (plugin toggles, permission edits, model selection, per-project `additionalDirectories`), and that file carries machine-specific absolute paths. The live file is intentionally a regular machine-local file rather than a Stow symlink.

[`.stowrc`](.stowrc) excludes the tracked portable baseline from Stow. [`stow-all.sh`](stow-all.sh) instead runs [`common/claude/.local/bin/claude-settings-sync`](common/claude/.local/bin/claude-settings-sync), which deep-merges the portable baseline into the live file: portable keys win on conflict, while live-only keys such as `permissions.additionalDirectories` and any runtime state are preserved. The helper migrates the previous symlink layout without creating a backup and fails closed on a missing or malformed baseline, an unparseable live file, or a host with neither `jq` nor `python3`. Rerun `./stow-all.sh <host>` after pulling portable setting changes.

#### Mutable Codex Desktop state

Codex Desktop also writes host-local values such as plugin state, MCP commands, runtime marketplace paths, notification helpers, and UI preferences into the live `~/.codex/config.toml`. That live file is intentionally a regular machine-local file rather than a Stow symlink.

[`.stowrc`](.stowrc) excludes the tracked portable baseline from Stow. [`stow-all.sh`](stow-all.sh) instead runs [`common/codex/.local/bin/codex-config-sync`](common/codex/.local/bin/codex-config-sync), which merges the portable allowlist into the live file while preserving runtime-only top-level keys, table entries, and tables. The helper also migrates the previous symlink layout without creating a backup and fails closed if a required portable key disappears. Rerun `./stow-all.sh <host>` after pulling portable setting changes.

The following state is intentionally **not synchronized**: credentials and OAuth tokens, `~/.claude.json`, sessions and histories, project trust, caches, downloaded plugins, Codex databases, Desktop UI state, per-project absolute paths, MCP commands containing host paths, marketplace runtime paths, and generated memories. Authenticate separately on every host.

Third-party skills are also not stored in this repository. [`awesome-skills-update.sh`](awesome-skills-update.sh) installs and refreshes `~/.claude/skills/` and `~/.codex/skills/` independently on each host.

After cloning on a new machine:

```bash
./stow-all.sh <host>
sync-skills
# Then authenticate Claude Code and Codex on this host.
```

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
- **AI configs are shared baselines**: keep credentials, caches, sessions, project trust, absolute host paths, and generated memories out of `common/claude` and `common/codex`.
- **Claude live state is merged**: keep the `.stowrc` exclusion, `claude-settings-sync`, and the portable `settings.json` aligned whenever shared Claude settings change; keep machine-specific paths out of the tracked baseline.
- **Codex live state is merged**: keep the `.stowrc` exclusion, `codex-config-sync`, and the portable key allowlist aligned whenever shared Codex settings change.
- **fcitx5 profile is materialized**: fcitx5 rewrites `~/.config/fcitx5/profile` at runtime, so `.stowrc` excludes it and `fcitx5-profile-sync` writes the tracked baseline as a machine-local regular file; the baseline is authoritative and re-asserted on stow.
- **One Stow owner per target**: a host-specific AI config must replace, not duplicate, the corresponding file in `common/`.
- **POSIX vs Bash vs Zsh**: shared logic lives in `common/sh/`; Bash/Zsh-specific syntax stays in matching shell files.
- **CI mirrors local**: every commit is checked with the same `shellcheck`/`shfmt`/`stylua` you run via `pre-commit`.
- **Verification**: after edits, run `pre-commit run --all-files` before committing.

## License

[MIT](LICENSE) — see the file for the full text.

<div align="center">
<sub>Built with <a href="https://www.gnu.org/software/stow/">GNU Stow</a> · CI by <a href="https://docs.github.com/actions">GitHub Actions</a> · Polished with <a href="https://pre-commit.com/">pre-commit</a></sub>
</div>
