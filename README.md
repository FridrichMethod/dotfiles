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
./stow-all.sh mac          # or: wsl-ubuntu, lab-ubuntu, sherlock, marlowe, fedora, ubuntu
```

```powershell
.\stow-all.ps1 win         # native Windows (elevated PowerShell 7+)
```

---

## Highlights

- **One command** to install everything on a fresh machine — `./stow-all.sh <host>`, or `.\stow-all.ps1 win` on native Windows.
- **Layered configs**: `common/` is the baseline; `<host>/` overrides where machines differ.
- **Cross-host AI defaults**: global Claude Code and Codex instructions, curated permissions, guarded exec policies, reasoning effort, and portable plugin declarations live in `common/`.
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

### On Windows

GNU Stow needs Perl and POSIX symlink semantics, so native Windows uses `stow-all.ps1` instead — same layering, same `.stowrc` ignores, same idempotency. Run it from an **elevated** PowerShell 7+:

```powershell
git clone --recurse-submodules https://github.com/FridrichMethod/dotfiles.git $HOME\dotfiles
cd $HOME\dotfiles
.\stow-all.ps1 win        # add -WhatIf for a dry run
```

Clone onto an NTFS drive, not into a WSL distro: a Windows symlink cannot point at a file inside ext4. A WSL distro keeps its own clone and uses `./stow-all.sh wsl-ubuntu` as usual.

**Why elevated?** Developer Mode (Settings → System → For developers) also lets the script create symlinks without elevation, but a symlink created by a non-elevated process is an *untrusted* reparse point. Windows refuses to traverse one for a file open whose token is a network logon — exactly what OpenSSH public-key auth produces — so inside an `ssh` session every stowed dotfile fails with `The path cannot be traversed because it contains an untrusted mount point` (error 448) while the same links resolve fine in a local session. That is not cosmetic: git dies with `fatal: unknown error occurred while reading the configuration files` because `~/.gitconfig` is unreadable. Neither `Get-Item` nor `fsutil reparsepoint query` can tell a trusted link from an untrusted one — tag, flags and substitute name are byte-identical — only the owner differs (`BUILTIN\Administrators` versus your user SID).

Like `stow-all.sh`, the Windows installer first synchronizes the portable Claude/Codex baselines into the live `~/.claude/settings.json`, `~/.codex/config.toml`, and `~/.codex/rules/portable.rules` (via the same helpers, run through Git Bash), then stows. Windows-only differences from the POSIX installer:

- **`common/` is an allowlist, not a glob.** Only `claude`, `codex`, `conda`, `git`, `pymol`, `ssh`, and `wezterm` are stowed; extend `$CommonPackages` in the script for anything else. Git Bash sources `~/.bashrc` and `~/.bash_profile`, so linking the Linux shell packages into a Windows `$HOME` would break it.
- **Pre-existing files are adopted, not clobbered.** A file that already matches the repo (ignoring line endings) is replaced by its link silently; one that differs is moved to `<name>.stow-backup-<timestamp>` first.
- **Untrusted symlinks are repaired, not skipped.** A link already pointing at the right file is normally left alone, but a matching target says nothing about whether Windows will follow the link, so each one is opened to check. Untrusted links are rewritten when the run is elevated (counted as `repaired:`) and reported as warnings when it is not.

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
│   ├── claude/                   ~/.claude/CLAUDE.md + portable settings/permissions
│   ├── codex/                    ~/.codex/AGENTS.md + portable config/exec rules
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
├── win/                          Windows (PowerShell profiles, Terminal, WSL)
│
├── .github/workflows/            ci.yml + daily submodule sync
├── .gitattributes                LF everywhere (Windows clones set autocrlf)
├── .pre-commit-config.yaml       shellcheck · shfmt · stylua · hygiene
├── .stowrc                       Stow defaults (--target=~, ignores)
├── stow-all.sh                   one-command installer (POSIX)
├── stow-all.ps1                  one-command installer (Windows)
├── dotfiles-update.sh            session-once auto-pull on shell login
├── dotfiles-update.ps1           the same hook, for PowerShell on Windows
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
| **AI Assistants** | Claude Code (`CLAUDE.md`, `settings.json`), OpenAI Codex (`AGENTS.md`, `config.toml`, `portable.rules`) |
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
| [`win/`](win/) | Windows | `git`, `powershell`, `ssh`, `terminal`, `wsl` | 8 |
| [`common/`](common/) | _shared baseline_ | 16 packages | 50 |

## How Stow Layering Works

```text
   common/zsh/.zshrc        ──stow──▶  ~/.zshrc            (baseline)
   common/git/.gitconfig    ──stow──▶  ~/.gitconfig        (baseline)
   common/claude/.claude/CLAUDE.md ──stow──▶ ~/.claude/CLAUDE.md
   common/codex/.codex/AGENTS.md   ──stow──▶ ~/.codex/AGENTS.md
   settings/config/rules baselines ──sync──▶ mutable live files
   mac/git/.gitconfig_local ──stow──▶  ~/.gitconfig_local  (host override, [include]'d)
   mac/ssh/.ssh/config.d/*  ──stow──▶  ~/.ssh/config.d/*   (host-specific endpoints)
```

1. **`common/`** is stowed first — every package, every host. Shared baseline.
2. **`<host>/`** is stowed second — overrides where the machine differs.
3. `stow --no-folding` symlinks **individual files**, not whole directories, so the two layers compose cleanly.
4. SSH permissions are re-asserted on every run (`700` on `~/.ssh`, `600` on `config` files) so `sshd` stays happy.

`.stowrc` is parsed directly by GNU Stow rather than by a shell, so its `--ignore=` regexes are intentionally unquoted. Literal shell quote characters prevent those exclusions from matching on GNU Stow 2.3.1.

> **Git overrides** flow through `[include] path = ~/.gitconfig_local` — the shared `.gitconfig` includes the host file if it exists.
> **SSH overrides** flow through `Include ~/.ssh/config.d/*.conf` — the shared root config delegates to per-concern fragments.
>
> Stow does not merge two files that target the same path. If a host needs a different complete `settings.json` or `config.toml`, move that file from `common/<tool>/` to `<host>/<tool>/`; do not define the same target in both layers.

## Auto-update Hooks

Two small hooks run on each interactive shell login, and the pull hook has a PowerShell twin for Windows. All are session-throttled, so subshells and tmux panes never re-run them.

<details open>
<summary><strong><code>dotfiles-update.sh</code></strong> — pulls this repo when behind</summary>

Fetches the remote, fast-forwards if behind, updates submodules, and automatically re-stows the selected host. Sourced from `common/zsh/.zshrc` (zsh) and `common/sh/.profile` (bash/POSIX login shells). Automatic updates skip working trees with local file changes, including submodule changes; they never stash, reset, or discard work.

First run the installer once on each Unix checkout to remember its host (Linux, macOS, WSL, and cluster overlays use the same flow):

```bash
./stow-all.sh mac           # or wsl-ubuntu, lab-ubuntu, sherlock, marlowe, fedora, ubuntu
./stow-all.sh               # explicitly remember common-only setup instead
```

The installer stores the selected host and last successfully applied commit in local Git metadata, bound to the home and platform. Existing installations need this one-time setup after pulling the new updater, or an explicit `DOTFILES_HOST` override. The hook does not guess which Linux/cluster overlay to use. Use a separate checkout for each home/platform.

| Variable | Default | Effect |
|---|---|---|
| `DOTFILES_AUTO_UPDATE` | `1` | `0` disables the entire login update hook |
| `DOTFILES_AUTO_STOW` | `1` | `0` keeps pull enabled but skips automatic stow |
| `DOTFILES_DIR` | `~/dotfiles` | repository path |
| `DOTFILES_HOST` | remembered host; `win` on Windows | explicit host override; empty means common only |

Set these variables before the update hook runs. A failed stow does not advance the applied commit: later fresh sessions retry even if there are no new remote commits or fetch is offline. A lock serializes automatic update/stow operations across shells; callers' shell traps are preserved. State remains in Git metadata and is not committed. Interrupted submodule updates are retried only when a pending marker matches HEAD; user-selected submodule revisions are otherwise preserved.

Session marker: `_DOTFILES_CHECKED` is exported so nested shells skip; a fresh login with a clean environment checks again. Successful stow updates files on disk; start a new shell/application to load the settings. Windows Terminal needs a restart.

**On Windows** — `dotfiles-update.ps1` runs at the end of `win/powershell/Documents/PowerShell/profile.ps1` and skips redirected stdout. Register the worker once from **elevated PowerShell 7+**, using the same Windows account as your ordinary shell:

```powershell
cd "$HOME\dotfiles"
.\stow-all.ps1 win
.\dotfiles-auto-stow.ps1 -Register
```

The on-demand task runs as that user with `Interactive` logon and `Highest` privileges, using `pwsh -NoProfile -NonInteractive -WindowStyle Hidden`. Registration explicitly authorizes the checkout's updated installer scripts to run with administrator privileges. It stores no password, uses the user's home, allows battery operation, and ignores overlapping task starts. Task names include a checkout/user hash. No UAC prompt is launched from the login hook; ordinary shells enqueue work, while elevated shells can apply directly. The interactive task requires that user to be logged on to Windows.

The worker verifies the requested revision, home, host and clean working tree again under the update lock before running `stow-all.ps1 -Strict`. Any installer warning or failed portable sync prevents marking the revision as applied. A queued task is not reported as a completed stow. Inspect its result and last-run log with:

```powershell
. .\dotfiles-auto-stow.ps1
Get-ScheduledTaskInfo -TaskName (Get-DotfilesTaskName $PWD.Path)
Get-Content (Join-Path (Get-DotfilesStateDirectory $PWD.Path) 'restow.log')
```

Set `DOTFILES_AUTO_STOW=0` before the login hook to stop automatic stow. To remove the registered worker entirely, from elevated PowerShell in the same checkout:

```powershell
. .\dotfiles-auto-stow.ps1
Unregister-ScheduledTask -TaskName (Get-DotfilesTaskName $PWD.Path)
```

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
./tests/run.sh                  # dynamic behavior tests for core automation
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
| [`common/claude/.claude/settings.json`](common/claude/.claude/settings.json) | merged into `~/.claude/settings.json` | Default `auto` mode with shell classification, `xhigh`, status line, notifications, fullscreen TUI, disabled attribution, hooks, voice, portable plugins |
| [`common/claude/.claude/dotfiles/`](common/claude/.claude/dotfiles/) | `~/.claude/dotfiles/` | Local Node.js helpers for the status line, notifications, and Git hook checks |
| [`common/codex/.codex/AGENTS.md`](common/codex/.codex/AGENTS.md) | `~/.codex/AGENTS.md` | Personal instructions across Codex projects |
| [`common/codex/.codex/config.toml`](common/codex/.codex/config.toml) | merged into `~/.codex/config.toml` | `gpt-6-astra` with `xhigh`, `workspace-net` (`:workspace` + public network), `on-request` + `auto_review`, multi-agent, memories |
| [`common/codex/.codex/rules/portable.rules`](common/codex/.codex/rules/portable.rules) | materialized as `~/.codex/rules/portable.rules` | Prompt-only guardrails for recursive deletion, destructive Git/disk operations, and privilege escalation |

The Git-stored versions of these files are safe to share across macOS, Linux, and WSL because they contain no credentials or machine-specific absolute paths. Some settings remain **capability-dependent**:

- Claude Code attribution is disabled with empty `attribution.commit` and `attribution.pr` strings; this supersedes the deprecated `includeCoAuthoredBy` setting.
- Claude Code starts new sessions with `permissions.defaultMode = "auto"`. [Auto mode](https://code.claude.com/docs/en/permission-modes) requires a supported client, model, and account configuration; organization policy can disable it. Explicit CLI or higher-precedence settings can override the default. `skipAutoPermissionPrompt` only skips the opt-in prompt; it does not select the mode.
- Codex has no active attribution setting; the aligned global instruction files prohibit `Co-Authored-By`, generated-with lines, and other AI attribution.
- Claude Code fullscreen TUI, `xhigh`, and plugins require a sufficiently recent client; `xhigh` falls back when the selected model does not support it. Plugin declarations are portable, but each host still downloads its own plugin cache.
- Codex permission profiles, the network proxy, `auto_review`, multi-agent, and memories can be constrained by the installed Codex version, selected model, account entitlement, sandbox implementation, or organization policy.
- `project_doc_fallback_filenames = ["CLAUDE.md"]` lets Codex use a project `CLAUDE.md` only when that directory has no `AGENTS.md` or `AGENTS.override.md`; it does not make the two instruction systems identical.

#### Mutable Claude Code state

Claude Code rewrites `~/.claude/settings.json` at runtime (plugin toggles, permission edits, model selection, per-project `additionalDirectories`), and that file carries machine-specific absolute paths. The live file is intentionally a regular machine-local file rather than a Stow symlink.

[`.stowrc`](.stowrc) excludes the tracked portable baseline from Stow. [`stow-all.sh`](stow-all.sh) instead runs [`common/claude/.local/bin/claude-settings-sync`](common/claude/.local/bin/claude-settings-sync), which deep-merges the portable baseline into the live file: portable keys win on conflict, while live-only keys such as `permissions.additionalDirectories` and any runtime state are preserved. The portable `permissions.allow` and `permissions.ask` arrays are authoritative, so a later stow removes ad-hoc live permission rules that are not part of the reviewed cross-host policy. The helper migrates the previous symlink layout without creating a backup and fails closed on a missing or malformed baseline, an unparseable live file, or a host with neither `jq` nor `python3`. Rerun `./stow-all.sh <host>` after pulling portable setting changes.

The baseline sets [`autoMode.classifyAllShell = true`](https://code.claude.com/docs/en/auto-mode-config#route-all-shell-commands-through-the-classifier), so shell allow rules are suspended in auto mode and shell commands go through classifier review. This adds classifier latency; explicit ask/deny rules still apply. Other permission modes retain their existing allow rules. The setting requires Claude Code v2.1.193 or later.

Claude's local helpers require Node.js 18 or newer on `PATH` (Git is optional for the status line):

- **Status line:** shows the active model, reported effort, project and Git branch (or detached commit), context usage, and estimated session cost. For example: `Opus | xhigh | dotfiles (main) | ctx 38% | ~$1.23`. Missing usage/cost data shows `?`; cost is Claude's estimate, not an invoice. It performs only bounded Git ref reads, without scanning the worktree or contacting the network. See the [status-line reference](https://code.claude.com/docs/en/statusline).
- **Notifications:** `permission_prompt` and `idle_prompt` events emit [Claude's `terminalSequence`](https://code.claude.com/docs/en/hooks#emit-terminal-notifications), using OSC 99 for Kitty, OSC 777 for Ghostty/Warp/rxvt, or OSC 9 for iTerm2/WezTerm/Windows Terminal. The terminal handles desktop delivery, including remote sessions when terminal identification is available. Enable notifications for the terminal in OS settings; unsupported terminals and non-interactive sessions may ignore them. The notice contains only the project name and a fixed status, never prompt or command contents. The plugin's existing Stop notification remains separate.
- **Git hook checks:** a local `PreToolUse` helper replaces per-Bash `npx block-no-verify@1.1.2` execution. It blocks common `--no-verify`, commit `-n`, and `-c core.hooksPath=...` forms without npm startup or downloads. This is a conservative text check, not a shell parser; quoted text can trigger it, and indirect bypasses are outside its scope. Successful checks do not grant permission or skip the classifier.
- **Plugin hooks:** the enabled Everything Claude Code plugin owns its SessionStart, Stop, and SessionEnd hooks. Empty portable arrays remove the old copied registrations during sync; disabling the plugin disables those lifecycle features. This prevents stale copies after plugin updates, rather than assuming a speedup from copies Claude may already deduplicate.

Run `./stow-all.sh <host>` (`.\stow-all.ps1 win` on Windows) to link the helpers and sync these defaults, then start a new Claude session. `effortLevel` remains `xhigh`, and model selection remains machine-local. Run `node --test tests/claude-customizations.cjs` for focused checks; the same checks are included in pre-commit and `./tests/run.sh`.

Third-party Markdown payloads copied into `~/.claude/rules/` are not vendored: Claude's plugin system does not load plugin-bundled rules automatically, and the audited `everything-claude-code` copies included conflicting global requirements such as automatic commit/push, unconditional parallel agents, and an 80% coverage floor. [`CLAUDE.md`](common/claude/.claude/CLAUDE.md) remains the reviewed cross-host instruction source.

#### Mutable Codex Desktop state

Codex Desktop also writes host-local values such as plugin state, MCP commands, runtime marketplace paths, notification helpers, and UI preferences into the live `~/.codex/config.toml`. That live file is intentionally a regular machine-local file rather than a Stow symlink.

[`.stowrc`](.stowrc) excludes the tracked config and rules baselines from Stow. [`stow-all.sh`](stow-all.sh) runs [`common/codex/.local/bin/codex-config-sync`](common/codex/.local/bin/codex-config-sync), which merges the portable config allowlist into the live file while preserving runtime-only top-level keys, table entries, and tables. It also runs [`common/codex/.local/bin/codex-rules-sync`](common/codex/.local/bin/codex-rules-sync), which atomically materializes the reviewed cross-host policy as `~/.codex/rules/portable.rules` without touching Codex-generated `default.rules` or other host-local rule files.

The portable baseline sets `model = "gpt-6-astra"`, `model_reasoning_effort = "xhigh"`, and `plan_mode_reasoning_effort = "xhigh"`. The [Plan-mode override](https://developers.openai.com/codex/config-reference) sets Plan mode to `xhigh` as well; without it, Plan mode uses its own built-in preset default. Each sync reapplies these top-level defaults; model and reasoning settings in host-local profiles are preserved.

The portable baseline selects `default_permissions = "workspace-net"` with `approval_policy = "on-request"` and `approvals_reviewer = "auto_review"`. The named profile extends `:workspace`, so writes inside the active workspace and system temporary directories proceed without approval. Its network proxy allows any public destination without review while retaining the default block on local and private network targets. Writes outside the workspace and other escalations still route to the separate automatic reviewer. The sync helper deliberately removes legacy `sandbox_mode` and `[sandbox_workspace_write]` values so they cannot shadow the selected permission profile.

Codex applies the most restrictive matching rule across active files. The portable policy uses only targeted `prompt` rules: `git clean`, `git reset --hard`, recursive or forced deletion, irreversible overwrite and disk-management tools, and privilege escalation route to automatic review. Simple file deletion, empty-directory removal, moves, routine workspace execution, package managers, and ordinary Git/GitHub operations do not incur this second review layer. Exec-policy has one shell reviewer setting rather than a per-command reviewer selector, so the global `AGENTS.md` requires the main agent to obtain explicit user authorization before catastrophic targets such as a filesystem, home, workspace, repository root, mount point, device, or broad ambiguous glob. No portable rule is `forbidden`, so an explicitly authorized operation remains reviewable rather than permanently blocked. Rerun `./stow-all.sh <host>` after pulling portable policy changes.

The following state is intentionally **not synchronized**: credentials and OAuth tokens, `~/.claude.json`, sessions and histories, project trust, caches, downloaded plugins, third-party copies under `~/.claude/rules/`, Codex-generated `~/.codex/rules/default.rules`, Codex databases, Desktop UI state, per-project absolute paths, MCP commands containing host paths, marketplace runtime paths, and generated memories. Authenticate separately on every host.

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
- **Codex exec policy is layered**: keep reviewed cross-host guardrails in `portable.rules`; leave generated or project/host-specific approvals in the untracked `default.rules`.
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
