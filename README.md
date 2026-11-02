# Dotfiles

Cross-platform configuration for macOS, WSL/Ubuntu, Stanford Sherlock, Marlowe
and native Windows, managed with GNU Stow. Shared defaults in `common/` load
before a selected host overlay. Secrets, accounts and application runtime state
stay local.

## Quick Start

Clone once per home/platform and keep the checkout in place: the installed
links and sync wrappers depend on it.

```sh
git clone https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles
./doctor.sh --host mac
./setup-host.sh --host mac --check
./setup-host.sh --host mac
```

Replace `mac` with `wsl-ubuntu`, `lab-ubuntu`, `sherlock` or `marlowe`.
setup-host installs tools and prints HUMAN blocks for commands it does not run,
including sudo, authentication, allocations, login-shell changes and stow.
Follow each block and rerun setup-host until complete. Before the first stow,
clone oh-my-zsh and move aside each conflicting home file as instructed; never
use `stow --adopt`. Use the exact H7-stow line, including its PATH prefix.

On an already provisioned Unix host:

```sh
./setup-sync.sh             # Python 3.11+; once per clone, no activation
./stow-all.sh mac
```

Stow checks conflicts before applying shared sync files, but may first remove
exact dangling links from retired Sherlock packages. It does not promise a
whole-home transaction. Failed/partial application never acknowledges a new
revision. See the [bootstrap playbook](docs/bootstrap.md#quick-start) and
[installer contract](docs/installer-contract.md).

For a common-only installation on other Linux, use `./stow-all.sh` without a
host and `./doctor.sh --platform other`; install prerequisites by the
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

Follow the HW-* HUMAN blocks. An existing machine can run `setup-sync.ps1`
and then `stow-all.ps1 win` from **elevated** PowerShell. Add `-WhatIf` to
preview and `-Strict` to reject incomplete installation. Local readability does
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
Native Windows stows an explicit common-package allowlist and no Unix shell
packages. The [dependency guide](docs/dependencies.md) explains required and
optional tools; `config/bootstrap/` owns installation inventories and versions.

## Auto-update Hooks

Interactive login checks once per session, fast-forwards a clean checkout and
restows its remembered host. It never discards local edits or guesses a Unix
overlay. A failed stow retries on a later login without needing another pull.
The [update contract](docs/update-contract.md) describes locks, receipts and
Windows elevation; Windows Terminal needs a restart to load settings changes.

| Variable | Effect |
| --- | --- |
| `DOTFILES_AUTO_UPDATE=0` | Disable the dotfiles login updater |
| `DOTFILES_AUTO_STOW=0` | Permit pulls without automatic restow |
| `DOTFILES_DIR` | Select the checkout (default `~/dotfiles`) |
| `DOTFILES_HOST` | Override remembered Unix host; empty means common only |
| `DOTFILES_COLOR` | `auto`, `always` or `never`; NO_COLOR/TERM=dumb disable color |
| `DOTFILES_PAYLOAD_AUTO_UPDATE=0` | Disable the separate automatic payload hook |

Set opt-outs before shell startup. Do not run manual and automatic installers
concurrently. [Shell startup](docs/shell.md) covers nvm, conda, PATH ordering,
PowerShell key bindings, encoding and prompts.

## AI Assistant Configuration

The repository [AGENTS.md](AGENTS.md) contains project rules; [CLAUDE.md](CLAUDE.md)
only imports it. Keep the guide below 28,000 bytes. User-global Claude/Codex
instructions and portable settings live under `common/claude` and `common/codex`.

Claude settings and Codex config are merged into mutable regular files rather
than linked. Portable values win while credentials, host-only settings and
runtime state stay local. Codex rules are materialized without touching
`default.rules`. Provision the parser explicitly; login never installs it.
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
Claude model selection remains machine-local; its effort, plugins and
permissions are shared. Codex portable model/reasoning defaults live in its
tracked config; host-local profile settings are preserved.

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

To add a package, mirror its HOME path under `common/<tool>/` or a host overlay,
add its configuration, then rerun the installer. Keep secrets local, code in its
shell dialect and documentation in English ASCII. Follow [AGENTS.md](AGENTS.md)
for manifest changes, checks and landing policy; keep common-before-host order.

## License

[MIT](LICENSE).
