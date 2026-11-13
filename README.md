# Dotfiles

Cross-platform configuration for macOS, WSL/Ubuntu, Stanford Sherlock, Marlowe
and native Windows, deployed by chezmoi as regular files from the source
state in `home/`. Each home selects its role through explicit local
`[data].host`. Secret enrollment is explicit and encrypted; mutable
auth/runtime state stays local.

## Quick Start

Clone once per home/platform. Role selection uses explicit local
`[data].host`; the checkout is the source chezmoi reads and stays available for updates.
The six hosts, their access rules and their known limits are in
[hosts](docs/hosts.md).
The [PowerShell 7 console procedure](docs/hosts.md#powershell-7-console-acceptance)
distinguishes a real ordinary-user PowerShell console from a noninteractive
task. Genuine [fresh-machine acceptance](docs/bootstrap.md#acceptance-checklist)
is a separate check with its own status.

```sh
git clone https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles
./dotfiles doctor --host mac
./dotfiles setup --host mac --check
./dotfiles setup --host mac
```

Replace `mac` with `wsl-ubuntu`, `lab-ubuntu`, `sherlock` or `marlowe`.
setup-host installs tools and prints HUMAN blocks for commands it does not run,
including sudo, authentication, allocations and login-shell changes. It
provisions verified chezmoi 2.74.0+ (the floors the design depends on, and
why, are in [dependencies](docs/dependencies.md#version-floors);
`config/bootstrap/tools.tsv` holds every tool floor the doctor checks).
Follow the HUMAN blocks; H7-deploy points to the first deployment, which a new
home follows by
[Fresh home by hand](docs/bootstrap.md#fresh-home-by-hand)
([bootstrap playbook](docs/bootstrap.md#h7-deploy-first-apply)): it keeps
private copies of the files the first apply replaces and stops on anything
it does not expect at a managed path.
File apply and login updates use `--exclude=dirs` to preserve existing shared
parent permissions. Prepare only inspected missing directories through the
[directory-only procedure](docs/bootstrap.md#preparing-missing-parents); plain
apply can change existing parent modes.

On other Linux, check with `./dotfiles doctor --platform other` and follow the
[other-Linux procedure](docs/bootstrap.md#x-other-linux-other-linux-distributions);
its `home_deploy generic` writes `[data].host = "generic"` into the local
chezmoi config.
setup-host requires a supported explicit host. Do not build HPC environments
outside a Slurm allocation or under scratch.

### On Windows

Use a Windows-side NTFS clone and PowerShell 7+. WSL keeps a separate clone and
uses the Unix installer.

```powershell
git clone https://github.com/FridrichMethod/dotfiles.git $HOME\dotfiles
cd $HOME\dotfiles
.\dotfiles.ps1 doctor --host win
.\dotfiles.ps1 setup --host win --check
.\dotfiles.ps1 setup --host win
```

Follow the HW-* HUMAN blocks; HW-deploy points to the first deployment, which a new
home follows by
[Fresh Windows home by hand](docs/bootstrap.md#fresh-windows-home-by-hand).
Updates write regular files unelevated, without a scheduled task or UAC prompt.
Fresh Windows home by hand checks both actual PowerShell profile paths; check
the ordinary user's ACLs on the destination parents before it, since a new
file inherits its parent's ACL. See
[the Windows quick start](docs/bootstrap.md#native-windows) and
[login updates](docs/updates.md).
After deployment, follow the explicit [User PATH procedure](docs/bootstrap.md#windows-command-discovery)
for bare `dotfiles` discovery in a fresh PowerShell 7 process, including `-NoProfile`.
Before that, use `& "$HOME/.local/bin/dotfiles.ps1" doctor --host win`.

### Bootstrapping with Claude Code or Codex

Invoke `/dotfiles-bootstrap` in Claude Code or `$dotfiles-bootstrap` in Codex.
The [mirrored project skill](.agents/skills/dotfiles-bootstrap/SKILL.md) follows
the playbook, diagnoses and plans before applying, and hands HUMAN blocks to
you. It never authenticates for you or hides privileged commands in a script.
For a session outside the clone, use the
[agent prompt](docs/bootstrap.md#prompt-for-an-agent-started-outside-the-clone).

## Command line

Use `./dotfiles` from a Unix checkout or `.\dotfiles.ps1` from a Windows
PowerShell 7 checkout, even before a home has chezmoi configuration. An explicit
path such as `~/dotfiles/dotfiles doctor --host mac` also works outside the clone.
After deployment, Unix finds `dotfiles` on `~/.local/bin` in its profile PATH;
Windows uses the manual [User PATH procedure](docs/bootstrap.md#windows-command-discovery).
Installed launchers select only the checkout named by the validated home
`~/.config/chezmoi/chezmoi.toml`; they never select from cwd or a fallback.
If configuration or the dispatcher is unavailable, including for help, recover
with `CHECKOUT/dotfiles` or `& CHECKOUT\dotfiles.ps1` explicitly.

| Command | Purpose |
| --- | --- |
| `doctor` | Check tools; offline and write-free by default |
| `setup` | Install tools; `--check` plans offline without writes; exit 3 means work remains |
| `payloads sync [ITEM...]` | Install or update selected payload repositories in the foreground |
| `dev test [--ci] [--check-prerequisites]` | Run tests, or check their prerequisites |
| `dev check` | Run `pre-commit run --all-files` from the selected checkout; formatters may edit files and behavior tests run once |
| `help [COMMAND...]`, `--help`, `-h` | Built-in help; runs no backend or installer |

| Command | Both platforms | Unix only | Windows only |
| --- | --- | --- | --- |
| `doctor` | `--host`, `--tier`, `--tsv`, `--quiet`, `--online` | `--platform`, `--smoke`, `--list` | None |
| `setup` | `--host`, `--tier`, `--check`, `--yes`, `--print-manual` | `--only`, `--skip`, `--keep-going`, `--list` | `--what-if`, `--confirm` |
| `dev test` | `--ci`, `--check-prerequisites` | None | None |

Every command accepts help. No arguments, bare `payloads`, and bare `dev` show
help and exit 0. Unknown command paths/options, unsupported platform options,
and missing/empty values exit 2 before execution. Use exact lowercase command
and long-option names; values accept `--name VALUE` or `--name=VALUE`. Repeated
scalar values use the last one; booleans are idempotent; Unix `--only`/`--skip`
remain repeatable. `--flag=true` is unsupported. Quote comma lists in PowerShell:
`dotfiles doctor --tier 'core,cli,ai'`. PowerShell arguments must be strings;
raw arrays and objects are rejected with exit 2.

The entrypoint platform determines the backend; `--host win` on Unix does not
start Windows execution. The CLI preserves backend streams and exit codes.
`dev check` accepts no extra pre-commit arguments and does not also run
`dev test`. Neither developer command installs dependencies. Payload defaults,
item validation, upstream lock exit 75 handling, retries and download bounds
remain in the [payload backend](docs/payloads.md); maintenance blocks execution.
The original `doctor.sh`, `setup-host.sh`, `doctor.ps1`, `setup-host.ps1` and
`scripts/payload-update.*` interfaces remain supported compatibility entrypoints,
with their existing native parameters and HUMAN/retry output.

## Source layout

| Path | Purpose |
| --- | --- |
| [home](home/) | chezmoi source (`.chezmoiroot`): one file per target under its chezmoi source name (`dot_`, `executable_`, `private_`, `empty_`) |
| `home/.hosts/<role>/` | Role variants of `~/.config/{sh,bash,zsh}` rc files, `~/.gitconfig_local` and `~/.ssh/config.d/legacy.conf`, read raw by one-line role-keyed templates |
| `home/.policy/` | Portable Claude and Codex policy, read raw by the two modify templates |
| `home/.chezmoiignore` | The targets of each role: `generic`, `mac`, `wsl-ubuntu`, `lab-ubuntu`, `sherlock`, `marlowe`, `win` |

chezmoi never deploys a source dot-directory, so `.hosts/` and `.policy/` stay
inputs. Git overrides use `~/.gitconfig_local`; SSH delegates to
`~/.ssh/config.d/*.conf`. A target has exactly one source file; native Windows
deploys 27 regular files and no POSIX shell files. The
[dependency guide](docs/dependencies.md) explains required and optional tools;
`config/bootstrap/` owns installation inventories and versions.

## tmux

The shared tmux 3.4+ configuration uses TPM, resurrect, continuum and fzf,
with a Catppuccin Mocha appearance, text extraction, clipboard helpers,
a floating scratch terminal and a custom which-key menu; older tmux is unsupported.
Plugins are provisioned through setup-host's S3-clones step; startup installs
nothing. Recovery restores layouts and directories without restarting programs
or saving pane contents. See [tmux setup, keys and limits](docs/shell.md#tmux).
The which-key new-window and split actions preserve quoted paths and literal
tmux formats; regression checks run in Linux CI against tmux 3.4, and their
real-macOS tmux 3.8 coverage is in [hosts](docs/hosts.md#known-limits).

## Auto-update Hooks

Interactive login checks once per session and calls
chezmoi update with explicit paths, `--exclude=dirs`, fast-forward-only Git, closed stdin and
conflict handling. It refuses dirty source, a missing or empty state database and OneDrive
source writes; failures warn and leave the shell usable. It updates only the
checkout `~/.config/chezmoi/chezmoi.toml` names (its `sourceDir`); a home
without that config runs no updater and prints nothing; see
[login updates](docs/updates.md).
A persistent [maintenance marker](docs/updates.md#maintenance) pauses the
update hook and explicit payload runs.
Windows Terminal needs a restart to load settings changes.

| Variable | Effect |
| --- | --- |
| `DOTFILES_AUTO_UPDATE=0` | Disable the dotfiles login updater |
| `DOTFILES_COLOR` | `auto`, `always` or `never`; NO_COLOR/TERM=dumb disable color |

Set opt-outs before shell startup. Do not run a manual apply while a login
update runs. [Shell startup](docs/shell.md) covers nvm, conda, PATH ordering,
PowerShell key bindings, encoding and prompts.
PowerShell checks OneDrive paths and inherited Git/chezmoi environment
prefixes with ordinal case-insensitive comparisons. Its history secret filter
uses culture-invariant matching, including under Turkish and Azerbaijani
cultures, while vendor-specific case-sensitive patterns retain their behavior.

## AI Assistant Configuration

The repository [AGENTS.md](AGENTS.md) contains project rules; [CLAUDE.md](CLAUDE.md)
only imports it. Keep the guide below 28,000 bytes. User-global Claude/Codex
instructions live in `home/dot_claude/CLAUDE.md` and `home/dot_codex/AGENTS.md`,
portable settings in `home/.policy/`.

Both global guides place persistent agent worktrees in the current project's
`.worktrees/` directory; brief disposable work may use `/tmp`. Keep unfinished
work and handoffs in durable storage. After integration and validation, release
active users and remove completed worktrees and their merged task branches.
Git ignores `.worktrees/`; OneDrive checkouts retain their independent-clone
exception.

Claude settings and Codex config are merged into mutable regular files.
Portable values win while credentials, host-only settings and
runtime state stay local. Codex rules deploy as an ordinary file without
touching `default.rules`. The modify templates use chezmoi's builtin JSON/TOML
functions. Read [AI configuration](docs/ai-config.md) before policy edits.
Authenticate separately on every host. Never commit tokens, histories, trust,
caches, generated memories or machine-specific absolute paths.

[coding-agent-kit](https://github.com/FridrichMethod/coding-agent-kit) supplies
account launchers, completions and Claude helpers on Linux, macOS and WSL.
Dotfiles holds only their configuration; the kit itself lives in its own
repository.
Native Windows does not install/check the kit: the helper commands run no
helper there and exit 0; missing Unix helpers fail visibly. Launcher/account
operation belongs to the kit's own documentation.
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
Codex config to change the shared layout; other TUI preferences remain local. A
live edit of an owned key stops login updates at that file until it is
[reconciled](docs/ai-config.md#reconciling-an-owned-key).

## Payload repos

`dotfiles payloads sync` calls each repository's own installer:
[coding-agent-kit](https://github.com/FridrichMethod/coding-agent-kit),
[PyMOLScripts](https://github.com/FridrichMethod/PyMOLScripts) and
[awesome-skills](https://github.com/FridrichMethod/awesome-skills).
`config/payloads.tsv` owns platform selection and kit channel (currently 0.7).
There are no submodules or consumer-side source pins.

awesome-skills manages its own copies under `~/.claude/skills/`,
`~/.codex/skills/` and `~/.agents/skills/awesome-skills/`; Codex reads both of
its roots. Selection and migration stay with that repository's installer.

No login, profile or schedule installs or refreshes the payload repos. A person
runs `dotfiles payloads sync` (or `sync-payloads`), which installs absent items
and updates installed ones in the foreground and keeps no state. The installed
launcher runs the hook of the checkout the
validated chezmoi config names and refuses a config the guard refuses; a home
without that config names no checkout, so run
`<checkout>/dotfiles payloads sync` explicitly. Exit 75 (another run
holds the repository's lock) is no failure. Exit 3 for configured
person-status items requires following the upstream installer's message;
locally edited PyMOL rc files are preserved.
Exit 3 and other failures print a retry line, and the run exits 1. This remains two
rolling PyMOL rc copies, not a version manager. Downloads are bounded and run
from fresh private staging directories, never from a pipe. See the
[payload contract](docs/payloads.md) for bounds, selection, trust and the
usage error any other call gets.

```sh
dotfiles payloads sync [kit] [pymol] [skills]  # foreground: install or update
sync-payloads [kit] [pymol] [skills]            # interactive shortcut
sync-skills                           # sync-payloads skills
```

On native Windows use `dotfiles payloads sync`, these profile functions, or
`& CHECKOUT\dotfiles.ps1 payloads sync` in an ordinary, unelevated PowerShell. It manages PyMOLScripts and
awesome-skills, not the kit.
The [sherlock-kit](https://github.com/FridrichMethod/sherlock-kit) toolkit is
separate: consumer projects pin/install their own.

## Checks and contribution

```sh
# Install the selected chezmoi test release, or name an already verified binary:
export DOTFILES_TEST_CHEZMOI=/path/to/chezmoi
pre-commit install
./dotfiles dev test --ci
./dotfiles dev check
pre-commit run --hook-stage manual gitleaks-history
```

Tests use isolated homes and fakes. Native macOS and Windows jobs provide
platform evidence, and Linux CI runs the real-tmux tests with Ubuntu 24.04's
tmux 3.4, the floor, and fails if they would skip
(`DOTFILES_TEST_REQUIRE_TMUX=1`); local skips do not establish native
behavior. The
[testing guide](docs/testing.md) explains prerequisites, focused suites, CI,
optional real-kit fixtures and opt-in bootstrap e2e tests. See the
[coverage matrix](tests/COVERAGE.md) for source-to-test mapping.

The hosted Windows bootstrap E2E temporarily pauses only the installed OMP
package's App Installer updates, then verifies restoration. This keeps the
run out of App Installer's unattended update-interaction path, where package
activation can wait after updates resume, while preserving the real package,
doctor assertions and timeouts. It does not validate App Installer
update scheduling or ordinary-user interactive behavior; see the
[runner qualifications](docs/testing.md#host-matrix-and-fidelity).

The [AI configuration](docs/ai-config.md#modify-templates) documents
serialization, preserved Claude/Codex input, exact ownership and refusal of
unsupported inputs. CI requires verified v2.74.0; local chezmoi probes skip if
chezmoi is absent, while an invalid explicit path fails. Enrolling selected
secrets or a host follows [secrets](docs/secrets.md); fixture passes are not
real-host outcomes ([hosts](docs/hosts.md)).

To add a configuration file, add it under `home/` with its chezmoi source name
(a role-specific variant goes to `home/.hosts/<role>/<target>` behind a one-line
role-keyed template; a new template also joins `ROLE_TEMPLATES` in
`tests/test_chezmoi_source_state.py`). Add its row to
`tests/fixtures/chezmoi/targets.tsv`, update the counts in
`tests/chezmoi_source_support.py` (for a shell file also the per-role `LINTED`
counts in `tests/test_chezmoi_rendered.py`, for a tmux file `TMUX_FILES` in
`tests/test_tmux.py`), and add a `home/.chezmoiignore` role entry unless it
applies to every role. A file containing `{{` stays plain;
use `.tmpl` only for a real template. If it introduces a new parent
directory, plan the reviewed per-host `apply --include=dirs --recursive=false`
preparation ([Preparing missing parents](docs/bootstrap.md#preparing-missing-parents))
before landing. Also check each applicable host for an existing
unmanaged file at the new path: the login update stops on it as a first-target
conflict until it is reconciled
([Editing and adding files](docs/updates.md#editing-and-adding-files)). For a
file that applies on Windows, name its parent's ACL model first (see
[New targets](docs/updates.md#new-targets)). Every home
receives the change through the login update. Keep secrets local, code in
its shell dialect and documentation in English ASCII. Follow
[AGENTS.md](AGENTS.md) for manifest changes, checks and landing policy.

## License

[MIT](LICENSE).
