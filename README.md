# Dotfiles

Cross-platform configuration for macOS, WSL/Ubuntu, Stanford Sherlock, Marlowe
and native Windows, moving to native chezmoi regular-file deployment. The Stage 4
compatibility release retains physical GNU Stow sources for existing homes.
Shared defaults in `common/` and host overlays remain canonical through Stage 6.
Secret enrollment is explicit and encrypted; mutable auth/runtime state stays local.

## Quick Start

Clone once per home/platform. Native source selection uses explicit local
`[data].host`; the checkout remains available for updates and literal source reads.
For release/rollout gates and actual host outcomes, read the
[migration status](docs/chezmoi-migration/status.md).

```sh
git clone https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles
./doctor.sh --host mac
./setup-host.sh --host mac --check
./setup-host.sh --host mac
```

Replace `mac` with `wsl-ubuntu`, `lab-ubuntu`, `sherlock` or `marlowe`.
setup-host installs tools and prints HUMAN blocks for commands it does not run,
including sudo, authentication, allocations and login-shell changes. The default
native path explicitly provisions verified chezmoi 2.74.0+ and creates no sync
venv. Follow the HUMAN blocks, then the
[native initialization/takeover procedure](docs/chezmoi-migration/takeover.md).
Existing homes require ownership review and private backups before first apply.
File apply and login updates use `--exclude=dirs` to preserve existing shared
parent permissions. Prepare only inspected missing directories through the
native directory-only procedure; plain apply can change existing parent modes.

For an explicitly retained legacy Stow home only:

```sh
./setup-sync.sh             # Python 3.11+; once per clone, no activation
./stow-all.sh mac
```

Stow checks conflicts before applying shared sync files, but may first remove
exact dangling links from retired Sherlock packages. It does not promise a
whole-home transaction. Failed/partial application never acknowledges a new
revision. See the [bootstrap playbook](docs/bootstrap.md#quick-start) and
[installer contract](docs/installer-contract.md).

Legacy provisioning/doctor use `--legacy-stow`. They refuse native-owned homes.
For native common-only installation on other Linux, select `common-only` in
local chezmoi data and use `./doctor.sh --platform other`; install prerequisites by the
[other-Linux procedure](docs/bootstrap.md#x-other-linux-other-linux-distributions).
setup-host requires a supported explicit host. Do not build HPC environments
outside a Slurm allocation or under scratch.

### On Windows

Use a Windows-side NTFS clone and PowerShell 7+. WSL keeps a separate clone and
uses the Unix installer.

```powershell
git clone https://github.com/FridrichMethod/dotfiles.git $HOME\dotfiles
cd $HOME\dotfiles
.\doctor.ps1 -Host win
.\setup-host.ps1 -Host win -Check
.\setup-host.ps1 -Host win
```

Follow the HW-* HUMAN blocks and the native takeover procedure. Regular-file
native updates run unelevated, without a scheduled restow task or UAC prompt.
Both actual PowerShell profile paths and ordinary-user destination ACLs must be
checked before takeover. Legacy `-LegacyStow` provisioning retains `setup-sync.ps1`
and **elevated** `stow-all.ps1 win`; `-WhatIf` previews and `-Strict` rejects
incomplete installation. Legacy local readability does
not prove link trust: Windows OpenSSH can reject an unelevated link with error
448, "untrusted mount point". The installer checks RedirectionGuard in a
separate process. See [Windows installation](docs/windows-installer.md),
[the Windows quick start](docs/bootstrap.md#native-windows), and
[automatic worker registration](docs/update-contract.md#windows-worker-operations).

### Bootstrapping with Claude Code or Codex

Invoke `/dotfiles-bootstrap` in Claude Code or `$dotfiles-bootstrap` in Codex.
The [mirrored project skill](.agents/skills/dotfiles-bootstrap/SKILL.md) follows
the playbook, diagnoses and plans before applying, and hands HUMAN blocks to
you. It never authenticates for you or hides privileged commands in a script.
For a session outside the clone, use the
[agent prompt](docs/bootstrap.md#prompt-for-an-agent-started-outside-the-clone).

## Hosts and packages

| Layer | Purpose |
| --- | --- |
| [common](common/) | Shells, Git/SSH, terminals, editor, AI defaults and utility configuration |
| [mac](mac/) | macOS paths, shell and connection overrides |
| [wsl-ubuntu](wsl-ubuntu/) | WSL shell, integration and connection overrides |
| [lab-ubuntu](lab-ubuntu/) | Lab Ubuntu, shared applications and fcitx5 |
| [sherlock](sherlock/) | Stanford HPC shell/module settings and terminal data |
| [marlowe](marlowe/) | Marlowe shell, Git and cache settings |
| [win](win/) | PowerShell, Git/SSH, prompt, Terminal and WSL settings |

Packages mirror HOME paths. Stow uses `--restow --no-folding`: individual links
let common and host packages compose. Git overrides use `~/.gitconfig_local`;
SSH delegates to `~/.ssh/config.d/*.conf`. A target has one owner: move a full
host-specific file out of common rather than defining it in both layers.
Legacy Windows (`stow-all.ps1`) stows an explicit common-package allowlist and no
Unix shell packages; native Windows deploys 26 regular files. The
[dependency guide](docs/dependencies.md) explains required and optional tools;
`config/bootstrap/` owns installation inventories and versions.

## tmux

The shared tmux 2.6+ configuration uses TPM, resurrect, continuum and fzf,
with a Catppuccin Mocha appearance, text extraction, clipboard helpers,
a floating scratch terminal and a custom which-key menu on supported versions.
Plugins are provisioned through setup-host's S3-clones step; startup installs
nothing. Recovery restores layouts and directories without restarting programs
or saving pane contents. See [tmux setup, keys and limits](docs/shell.md#tmux).

## Auto-update Hooks

After native handover, interactive login checks once per session and calls
chezmoi update with explicit paths, `--exclude=dirs`, fast-forward-only Git, closed stdin and
conflict handling. It refuses dirty source, missing/empty native state and OneDrive
source writes; failures warn and leave the shell usable. Unmarked homes retain
the legacy updater in the [update contract](docs/update-contract.md). A persistent
maintenance marker blocks both update and payload hooks during takeover.
Windows Terminal still needs a restart to load settings changes.

| Variable | Effect |
| --- | --- |
| `DOTFILES_AUTO_UPDATE=0` | Disable the dotfiles login updater |
| `DOTFILES_AUTO_STOW=0` | Legacy only: permit pulls without automatic restow |
| `DOTFILES_DIR` | Legacy checkout selection; native uses its home-bound marker |
| `DOTFILES_HOST` | Legacy only: override remembered Unix host; native uses local data |
| `DOTFILES_COLOR` | `auto`, `always` or `never`; NO_COLOR/TERM=dumb disable color |
| `DOTFILES_PAYLOAD_AUTO_UPDATE=0` | Disable the separate automatic payload hook |

Set opt-outs before shell startup. Do not run manual and automatic installers
concurrently. [Shell startup](docs/shell.md) covers nvm, conda, PATH ordering,
PowerShell key bindings, encoding and prompts.

## AI Assistant Configuration

The repository [AGENTS.md](AGENTS.md) contains project rules; [CLAUDE.md](CLAUDE.md)
only imports it. Keep the guide below 28,000 bytes. User-global Claude/Codex
instructions and portable settings live under `common/claude` and `common/codex`.

Both global guides place persistent agent worktrees in the current project's
`.worktrees/` directory; brief disposable work may use `/tmp`. Keep unfinished
work and handoffs in durable storage. After integration and validation, release
active users and remove completed worktrees and their merged task branches.
Git and Stow ignore `.worktrees/`; OneDrive checkouts retain their independent-clone
exception.

Claude settings and Codex config are merged into mutable regular files rather
than linked. Portable values win while credentials, host-only settings and
runtime state stay local. Codex rules are materialized without touching
`default.rules`. Native modifies use builtin JSON/TOML functions with no Python,
external jq or sync venv. The following parser selection applies only to legacy
compatibility: provision it explicitly; login never installs it.
A provisioned interpreter that satisfies the selected helper's dependencies
can be selected with DOTFILES_SYNC_PYTHON. Setup, doctor and wrappers share this
choice; an invalid override fails without creating an unused default venv.
See [runtime selection](docs/bootstrap.md#s4-setup-sync-ai-sync-runtime).
Read the [sync contract](docs/config-sync.md) before migrations or policy edits.
Authenticate separately on every host. Never commit tokens, histories, trust,
caches, generated memories or machine-specific absolute paths.

[coding-agent-kit](https://github.com/FridrichMethod/coding-agent-kit) supplies
account launchers, completions and Claude helpers on Linux, macOS and WSL.
Dotfiles keeps their configuration but no copy of the kit implementation.
Native Windows does not install/check the kit: missing helpers exit silently
there, while existing 0.6 helper copies still run; missing Unix helpers fail
visibly. Launcher/account operation belongs to the kit's own documentation.
Claude's status-line command enables the kit's ANSI colors for captured output,
while preserving an explicit `CODING_AGENT_KIT_COLOR` setting. `NO_COLOR` and
`TERM=dumb` disable colors. The renderer lives in the kit; the command and color
preference live in dotfiles.
Claude model selection remains machine-local; its effort, plugins and
permissions are shared. Codex portable model/reasoning defaults live in its
tracked config; host-local profile settings are preserved.
The shared Codex CLI status line shows cumulative session tokens,
alongside model, directory, thread, Git branch, context usage and
weekly limits. Estimated thread cost appears only when supported by the account
(Enterprise workspaces in Codex CLI 0.166.0). Edit `tui.status_line` in the tracked
Codex config to change the shared layout; other TUI preferences remain local.

## Payload repos

The session-once payload hook calls each repository's own installer:
[coding-agent-kit](https://github.com/FridrichMethod/coding-agent-kit),
[PyMOLScripts](https://github.com/FridrichMethod/PyMOLScripts) and
[awesome-skills](https://github.com/FridrichMethod/awesome-skills).
`config/payloads.tsv` owns platform selection and kit channel (currently 0.7).
There are no submodules or consumer-side source pins.

awesome-skills manages its own copies under `~/.claude/skills/`,
`~/.codex/skills/` and `~/.agents/skills/awesome-skills/`; Codex reads both of
its roots. Selection and migration stay with that repository's installer.

Absent items install in the foreground; due updates run in one detached
background process. Success stamps are separate from `ITEM.failed` records;
failures are reported on later sessions and retried in the background after
six hours. Exit 75 writes neither. Exit 3 for configured person-status items
requires following the upstream installer's message; locally edited PyMOL rc
files are preserved. This remains two rolling PyMOL rc copies, not a version
manager. Downloaded scripts run from fresh private staging directories, never
from a pipe. See the [payload contract](docs/payloads.md) for bounds, state,
selection, trust and exact migration behavior.

```sh
sync-payloads [kit] [pymol] [skills]  # foreground, ignore refresh interval
sync-skills
```

On native Windows use these profile functions or `scripts/payload-update.ps1 -Now` in an ordinary, unelevated PowerShell. It manages PyMOLScripts and
awesome-skills, not the kit. Preserve legacy links/checkouts until the documented
[migration conditions](docs/payloads.md#migration) hold; inspect local work
before manual cleanup. [Sherlock toolkit migration](docs/sherlock-kit.md) is
separate: consumer projects pin/install their own toolkit.

## Checks and contribution

```sh
./setup-sync.sh
# Install the selected chezmoi test release, or name an already verified binary:
export DOTFILES_TEST_CHEZMOI=/path/to/chezmoi
pre-commit install
./tests/run.sh --ci
pre-commit run --all-files
pre-commit run --hook-stage manual gitleaks-history
```

Tests use isolated homes and fakes. Native macOS and Windows jobs provide
platform evidence; local skips do not establish native behavior. The
[testing guide](docs/testing.md) explains prerequisites, focused suites, CI,
optional real-kit fixtures and opt-in bootstrap e2e tests. See the
[coverage matrix](tests/COVERAGE.md) for source-to-test mapping.

The [chezmoi migration](docs/chezmoi-migration/status.md) includes native
Claude/Codex modifies, ordinary source under `home/`, explicit local `[data].host`
and Stage 4 guarded takeover/update/provisioning. Native apply needs no sync venv.
The [native contract](docs/config-sync.md#native-configuration-and-stage-4-handover) documents
native serialization for policy changes, preservation of unchanged Claude/Codex input,
exact ownership and safe refusal of unsupported inputs.
CI requires verified v2.74.0; local native probes skip if chezmoi is absent,
while an invalid explicit path fails. Canonical legacy source remains available
and unmarked homes retain the legacy path. Real takeover and selected secret
enrollment require the [Stage 4 procedure](docs/chezmoi-migration/takeover.md)
and recorded release gates; fixture passes are not real-host outcomes.

To add a configuration file, put the canonical file at its HOME path under
`common/<tool>/` or a host overlay; legacy source stays canonical until Stage 6.
Add the matching `home/` literal-include template, its
[inventory](docs/chezmoi-migration/inventory.md) row and stated totals, a
`home/.chezmoiignore` role entry unless it applies to every role, and the exact
counts in `tests/chezmoi_source_support.py`. If it introduces a new parent
directory, plan the reviewed per-host `apply --include=dirs --recursive=false`
preparation from the [takeover procedure](docs/chezmoi-migration/takeover.md)
before landing. Also check each applicable native host for an existing
unmanaged file at the new path: the login update stops on it as a first-target
conflict until it is reconciled under that procedure. For a file that applies
on Windows, name its parent's ACL model first (see
[start-stage-5.md](docs/chezmoi-migration/start-stage-5.md)). Native homes
receive the change through the login update; `stow-all` applies only to legacy
(unmarked) homes. Keep secrets local, code in
its shell dialect and documentation in English ASCII. Follow
[AGENTS.md](AGENTS.md) for manifest changes, checks and landing policy; keep
common-before-host order.

## License

[MIT](LICENSE).
