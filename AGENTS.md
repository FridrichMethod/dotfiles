# Agent Guide

This repository stores cross-platform dotfiles with a native chezmoi candidate
and a guarded GNU Stow compatibility path during the Stage 4 bridge.

## Scope and layout

- Shared defaults live in `common/`.
- Keep persistent worktrees in `.worktrees/`. Follow the global guides for temporary work, preservation and post-integration cleanup.
- Host overlays live in `mac/`, `sherlock/`, `wsl-ubuntu/`, `lab-ubuntu/`, `marlowe/`, and `win/`. Other Linux distributions have no overlay; they stow `common/` only.
- Packages mirror `$HOME` paths (for example `.config/...`, `.ssh/...`).
- Root scripts are person-facing setup/check entry points; `scripts/` contains login/scheduled hooks, `lib/` sourced/imported code, and `config/` their data. Place files by their caller. Keep `.stowrc` at the root for GNU Stow.


## Required conventions

- Keep secrets and machine-specific absolute paths out of version control.
- Write documentation, guides and skills in English using printable ASCII, tabs and line breaks only; the English-documentation hook enforces the character set. Payload repos use their own checks.
- Preserve the Stow flow: `common/` first, host second.
- Update `README.md`, `stow-all.sh` usage and script comments together when setup behavior changes.

## Weight and dependencies

These files are installed on every host, including fresh machines and clusters, so they must run on what a host already has and stay small enough to audit.

- Runtime helpers use only POSIX sh/Bash, ordinary POSIX utilities, Python 3.11+ stdlib (`python3 -I -B`) and the wrapped tool. No added pip packages, environments, Node, compiler, service or daemon; the sole exception is explicitly provisioned, pinned tomlkit for TOML sync. Tool installation belongs to setup-host.
- Missing optional tools narrow features; a missing required tool fails once with its name, without a traceback or partial run.
- Forward to native tools, requiring only a minimum version. Internal sockets/protocols/locks are best effort: warn and fall back to native behavior; block or ask only to prevent lost work.
- Keep helpers proportional and auditable. Prefer native features over a custom protocol client, journal or lock scheme; justify any such addition and its tests.
- Tests use unittest, real shells and fake third-party CLIs in temporary homes, with no network beyond loopback fixtures or access to real credentials/daemons. Optional real tools skip cleanly if absent; internet, credentials and Docker are opt-in (`tests/e2e/run.sh`).
- Linux CI checks prerequisites, then runs full pre-commit once for all behavior/lint checks. Keep developer hooks scoped by files and fast; pure parsing stays in-process, shells/children cover exec, signals, umask, TTY and modes. Preserve macOS and native Windows behavior passes; do not claim speedups without measurement.

## Working commands

- Legacy only: provision the AI-sync parser with `./setup-sync.sh` (Windows: `./setup-sync.ps1`), with Python 3.11+.
- Check a host (read-only, offline): `./doctor.sh --host <host>` (Windows: `.\doctor.ps1`)
- Day-zero install, plan first: `./setup-host.sh --host <host> --check`, then without `--check` (Windows: `.\setup-host.ps1 -Check`, then `.\setup-host.ps1`)
- Native initialization/takeover: follow `docs/chezmoi-migration/takeover.md`; legacy Stow remains `./stow-all.sh [host-dir]`.
- Install or update the payload repos now: `sync-payloads [ITEM...]`, or `sh scripts/payload-update.sh --now` (Windows: `scripts/payload-update.ps1 -Now`, unelevated)
- Run checks: `pre-commit run --all-files`

## Verification

Keep this guide below 28,000 bytes; move explanatory material to canonical docs, never omit substantive rules.

After modifying any file, run `pre-commit run --all-files` to ensure changes pass CI checks before committing.

The [chezmoi migration](docs/chezmoi-migration/README.md) is staged. Stage 4 keeps
explicit local `[data].host`, native AI transforms and literal legacy inputs until
Stage 6. Preserve unsupported-input refusal, exact ownership/policy parity and
WebP/terminfo byte parity. New provisioning defaults to native without a sync venv;
`--legacy-stow` / `-LegacyStow` retains the old path. Home-bound native ownership
blocks old writers; maintenance blocks future dotfiles AND payload workers.
Keep legacy paths/runtime for supported old callers until Stage 6. First apply
is not an ownership guard: review exact targets and private snapshots first.
Real takeover follows exact candidate CI gates and existing D11 authority;
commits/publication require active authorization. Enroll only privately selected
static secrets with explicit recipients/bootstrap/recovery; no plaintext,
identities or recurring OAuth state in source. Never force routine apply.
Pin `--exclude=dirs` on native file apply/update to preserve shared parents;
the tested release has no effective config-key equivalent. Prepare only exact
missing directories with reviewed native directory-only apply. Future missing
parents require that preparation before retry; a failure is not transactional.
Review local umask and existing private-parent modes before takeover/enrollment.

## Shell conventions

- Keep POSIX logic in `common/sh/` and host `*/sh/` paths.
- Use Bash/Zsh-specific syntax only in matching shell files.
- Preserve override sourcing patterns from shared files:
  - `common/sh/.aliases` sources `~/.config/sh/.aliases`
  - `common/sh/.profile` sources `~/.config/sh/.profile`
- Keep startup flow quiet and idempotent; avoid duplicate side effects.
- PATH belongs in `common/sh/.profile`, which prepends `$HOME/bin` and `$HOME/.local/bin` behind a duplicate guard. `common/zsh/.zshrc` sources `~/.profile` near its top, right after the `typeset -U` block, so zsh inherits it too. Add new entries there, or in a host `*/sh/.profile`, never by appending to a shell rc.
- Discard installer-appended PATH blocks in stowed rc files by default. Express their intent portably via `$HOME` and duplicate guards in the profile; do not retain machine-home literals or repeated exports.
- Keep nvm free of the oh-my-zsh nvm plugin, lazy wrappers and `.nvmrc` auto-switching. Resolve default aliases with the read builtin in the profile without sourcing nvm; support exact/partial/node/stable and chains, leaving `lts/-N` unresolved. Support only `~/.nvm` and `${XDG_CONFIG_HOME:-~/.config}/nvm`. Keep PATH uniqueness scoped to zsh setup, fpath/INFOPATH unique, nvm ahead of brew/conda before oh-my-zsh, inherited NVM_BIN parent order intact, and no command-hash rebuild after plugins. `custom/nvm.zsh` loads `--no-use` and completion and repairs only brew-plugin reordering. Set plugin options before oh-my-zsh loads; pre-source ssh-agent options. See [shell startup](docs/shell.md).
- Do not use here-documents, here-strings or process substitution anywhere in `doctor.sh`, `setup-host.sh`, `lib/terminal.sh` or `lib/bootstrap/*.sh`, including apply-only paths. Bash 3.2 otherwise creates temp files or retains descriptors. Use BOOTSTRAP_NL splitting, bootstrap_split and pipes/bootstrap_text_has; keep bootstrap-manifest enforcement.
- Follow pre-commit shell style:
  - Bash: `shfmt -i 4 -ci -ln bash`
  - POSIX: `shfmt -i 4 -ci -ln posix`
  - Zsh: `shfmt -i 4 -ci -ln zsh` (needs shfmt 3.13+, the first release with a zsh dialect)

## Bootstrap and doctor

- Only `setup-host.sh` and `setup-host.ps1` install third-party tools, and only when a person runs them. The payload hooks (`scripts/payload-update.*`), which the profiles call, install and update only the three payload repos, through each repo's own documented installer. The profiles themselves, stow and the dotfiles update hooks install nothing.
- setup-host never runs sudo, chsh, stow/stow-all, conda/micromamba shell init or git lfs install, nor edits rc files; print HUMAN blocks instead. Each line is a `# ` note or self-contained command. A person runs privileged lines, or approves each visible top-level agent command; never hide them in a script or `sh -c`. Printed digest-gate lines and the shared-prefix `(cd /tmp && sudo -u OWNER ...)` form are single commands. Never chown a shared Homebrew prefix. The only checkout write is `.venv-sync` via setup-sync. S2-brew-bundle skips entries already satisfying their tools.tsv probe or alias via apt, conda or OS.
- Doctor without --online/--smoke and setup-host --check stay offline and write-free. --online runs only three auth probes and may write native tool state; --smoke may write zsh caches. Always set GH_TELEMETRY=0 and TLDR_AUTO_UPDATE_DISABLED=1 for probes, including --version. Keep empty-home real-tool and stateful-fake no-write tests; see [guarantees](docs/bootstrap.md#guarantees).
- What setup-host cannot settle safely becomes a blocking judgment block, never a guess: oh-my-zsh stowed before its clone, a formula or cask that a Brewfile's `# conflicts: FORMULA OTHER...` or `# conflicts: cask TOKEN OTHER...` line names (checked by keg or `Caskroom` before any brew command, only where brew bundle installs the entry), and an `nvm.sh` that is not the pinned checkout without local changes (it is never sourced).
- `config/bootstrap/` owns installer SHA256 pins (bat theme included), tool floors and clone branches. git-clones.tsv tracks upstream default branches, never commits; clone only missing repositories and do not fetch, pull, repin or dirty-check existing ones. Retain the manual update loop and trust limits in [bootstrap.md](docs/bootstrap.md#s3-clones-oh-my-zsh-theme-and-plugin-clones). Keep step-heading, tool-ID and mirrored-skill parity tests; update manifests, not copied pin inventories.
- Verify every setup-host download before use except inspect rows, which a person reads first. HUMAN execution uses digest gates and installers use no-rc flags (PROFILE=/dev/null, NONINTERACTIVE=1). Preserve the documented distinction between pinned downloads/default-branch clones and package managers' current versions.
- First-party project skills live only in `.claude/skills/` and `.agents/skills/`, with identical bodies.
- Provisioning shells export DOTFILES_AUTO_UPDATE=0 DOTFILES_PAYLOAD_AUTO_UPDATE=0. Test entrypoints use tests/lib/environment.sh/.ps1 to clear inherited DOTFILES_, _DOTFILES_, AWESOME_SKILLS_, _AWESOME_SKILLS_, CODING_AGENT_KIT_ and _CODING_AGENT_KIT_ prefixes plus XDG_STATE_HOME/XDG_DATA_HOME; preserve DOTFILES_TEST_* inputs and DOTFILES_SYNC_PYTHON. Fixture Git must drop repository/index overrides before mutation. Keep focused linked-worktree isolation and hook-selection tests; do not scan upstream implementation or mirror every variable in every entrypoint.
- On Unix, common only means the same everywhere, whether it comes from an empty but set `DOTFILES_HOST` or from a common-only install that `./stow-all.sh` (no host argument) recorded for this home: the login updater stows only `common/`, the doctor checks the detected platform without an overlay and warns, and setup-host exits 2 asking for `--host`. A nonempty `DOTFILES_HOST` overrides the record. The Windows twins `doctor.ps1` and `setup-host.ps1` never read `DOTFILES_HOST` and always check the `win` host.
- HPC environments are built only inside a Slurm allocation, never under `$SCRATCH`.

## Git and SSH conventions

- Keep shared Git config in `common/git/.gitconfig`.
- Keep host-local Git overrides in `*/git/.gitconfig_local`.
- Preserve include chain: `[include] path = ~/.gitconfig_local`.
- Keep SSH root config minimal in `common/ssh/.ssh/config`:
  - `Include ~/.ssh/config.d/*.conf`
- Keep SSH targets split by concern in `.ssh/config.d/*.conf`.
- Do not commit secrets or private key material.

## AI assistant configuration

- Keep shared user-global files in these Stow packages:
  - `common/claude/.claude/CLAUDE.md`
  - `common/claude/.claude/settings.json`
  - `common/codex/.codex/AGENTS.md`
  - `common/codex/.codex/config.toml`
  - `common/codex/.codex/rules/portable.rules`
- coding-agent-kit owns Unix launchers, completions and Claude Node helpers under `~/.claude/coding-agent-kit/`; dotfiles ships no kit config. Linux/macOS/WSL only: no Windows install/check rows. Native Windows missing helpers exit 0 silently, existing 0.6 copies still run, and Unix missing helpers fail visibly. Preserve these platform guards.
- Keep the global `CLAUDE.md` and `AGENTS.md` aligned unless a tool-specific semantic difference requires divergence.
- The repository root `CLAUDE.md` is only an `@AGENTS.md` import stub for Claude Code; `AGENTS.md` is the single repository guide for every agent. Add or change repository policy in `AGENTS.md`, never in the stub.
- Set Project instructions to `claude-md-and-agents-md` under both pluginConfigs IDs, agents-md@builtin and cc-plugin-agents-md@builtin (pre-2.1.285 clients use the former; newer clients accept either). Keep native ancestor loading and the CLAUDE.md stub for old clients.
- Shared settings may contain portable preferences, permission rules, plugin identifiers, and remote marketplace declarations.
- Do not declare `model` in the portable Claude `settings.json`. The sync asserts every key it declares, so a shared `model` would silently undo each host's `/model` choice on the next stow. Model selection stays machine-local; `effortLevel` and the rest remain shared.
- Preserve Claude permission tiers and authoritative arrays: ask holds only sudo; deny holds sudo pip/pip3, sudo rm, and the exact `rm -rf /`, `rm -fr /`, `rm -rf ~`, `rm -fr ~` patterns. Never add trailing wildcards to those rm denials. Reviewed installs/network/Git/GitHub operations remain in allow. This accepted broad policy is not a prompt to redesign permissions; its rationale is in [config-sync.md](docs/config-sync.md#permission-policy-rationale).
- Keep ordinary rm/rm -rf, git clean and npx out of all three arrays so auto mode uses its classifier. Tune autoMode.allow/soft_deny prose, preserving literal `$defaults`, rather than moving commands into ask. Built-in critical-path and work-discard checks remain in force; see the policy rationale.
- Keep autoMode.classifyAllShell=true: Bash allow rules cannot bypass auto-mode review. Do not add allow rules to cure classifier false positives. Protected-path checks precede allow rules; Claude must not loosen these arrays or apply claude-settings-sync to live settings unaided: a human applies both steps.
- Preserve the accepted broad-allow tradeoff. Reconsider narrower argument-anchored network/install/remote-mutation rules only when the host threat model changes; do not silently change the policy during unrelated work.
- Do not vendor third-party Markdown payloads copied into `~/.claude/rules/`; plugin checkouts may be used as an audit source, but Claude does not load plugin-bundled rules automatically. Keep reviewed cross-host instructions in the global `CLAUDE.md`.
- Never track credentials, OAuth state, sessions, histories, project trust, caches, downloaded plugins, generated memories, runtime marketplace paths, or machine-specific absolute paths.
- Codex config.toml and Claude settings.json remain excluded from Stow: their helpers merge into regular mutable live files, portable keys winning and live-only state retained. Preserve .stowrc exclusions and use the shared engine; see [sync contract](docs/config-sync.md).

- Keep reviewed Codex exec-policy guardrails in `common/codex/.codex/rules/portable.rules`; `codex-rules-sync` materializes it without touching host-local `default.rules`. Portable rules may add targeted `prompt` safeguards but must not grant broad cross-host `allow` prefixes or use `forbidden`; exceptionally destructive actions require explicit user pre-authorization through the global Codex instructions.
- Keep all three AI sync helpers fail-closed; when shared config, permission or rule behavior changes, update their sources, README and focused tests together.
- Keep legacy helper merges in `lib/config_sync.py`; only legacy TOML sync and the full runtime check require pinned `tomlkit`, while JSON/rules use the Python standard library. The native candidate uses the Stage 3 contract above and never calls this backend. Do not add custom parsers or a second legacy JSON engine. Normal sync never rewrites portable source; baseline cleanup is an explicit legacy migration. Legacy sync never broadens existing regular-file Unix permissions.
- Installers must run every selected AI helper with read-only `--check` before any apply; `--quiet` suppresses successful helper chatter, never errors. Provision `.venv-sync` or an explicitly selected interpreter in advance; profiles, automatic updates and the payload hooks must never install these dependencies.
- Stow cannot merge two files targeting the same path. If a host requires a different complete `settings.json` or `config.toml`, move that file from `common/<tool>/` to `<host>/<tool>/`; do not define it in both layers.
- Keep third-party skill payloads out of dotfiles; awesome-skills' own installer, which the payload hook runs, owns only its installed copies under `~/.claude/skills/`, `~/.codex/skills/` and `~/.agents/skills/awesome-skills/` (Codex reads both roots) on each host.

## Payload repos

- coding-agent-kit, PyMOLScripts and awesome-skills own their installation, update, selection and locking. Dotfiles calls them only through the commands in `config/payloads.tsv`, the one place naming their URLs, paths, commands and the kit channel (`0.7`), and the items a platform has (an item without a `windows-install` row, the kit, is not available on native Windows: no default item there, and naming it is an info, exit 0, no record); a channel or command change is a reviewed change of that file (`docs/payloads.md`). No submodules, bump workflows or consumer-side pins.
- `scripts/payload-update.sh` and `.ps1` keep one contract: interactive, once per session, absent items in the foreground, refreshes in one detached background run, stamps only on success, exit 75 neither, any other failure recorded in `ITEM.failed` (reported by later sessions and the doctor, retried only in the background six hours later), downloads bounded by `DOTFILES_PAYLOAD_TIMEOUT`, each staged alone in a fresh private temporary directory that is removed afterwards and never piped into a shell, one failed download ending the run's downloads, the installer not called while a `stow-links` path still links into its retired package, no lock of their own. `tests/payload-update.sh` covers it.

## Stow and update scripts

- Keep status output in lib/terminal.sh/.ps1, with DOTFILES_COLOR=auto|always|never; nonempty NO_COLOR and TERM=dumb disable it. Preserve plain redirected logs, PowerShell stream capture and caller preferences. Under auto only, recognize p10k instant-prompt capture through __p9k_instant_prompt_active and a numeric still-terminal saved fd; all other hidden terminals stay plain. Never pass a nonnumeric fd to dash -t. Add no formatting dependency.

- `stow-all.sh` is the legacy setup command, refused for native-owned/maintenance homes. Before any sync helper writes, it refuses packages linking into `~/.oh-my-zsh` until `~/.oh-my-zsh/oh-my-zsh.sh` exists (`DOTFILES_STOW_WITHOUT_OH_MY_ZSH=1` overrides) and stops on Stow dry-run conflicts. Legacy Windows stows no zsh and adopts conflicts, so `stow-all.ps1` has neither check.
- Keep order stable: stow `common/` packages first, then optional host packages.
- Preserve Stow flags unless intentionally migrating behavior:
  - `--restow --no-folding`
- .stowrc owns --target=~ and ignores: mirror every .gitignore pattern with no slash except an optional trailing slash as a whole path component plus descendants. Use character classes for literal metacharacters (`[.]`), end regexes in `$`, and keep Stow 2.3/2.4/PowerShell parity plus tracked-file coverage tests.
- Do not shell-quote `.stowrc` option values. GNU Stow parses the file directly, and Stow 2.3.1 treats quote characters around `--ignore=` regexes literally; keep the focused test that stows into a temporary target with materialized files already present.
- `.stowrc` also excludes app-rewritten or helper-materialized files that `stow-all.sh` writes as machine-local regular files instead of symlinks: Codex `config.toml` and Claude `settings.json` (merged, portable keys win), Codex `portable.rules` (materialized without touching `default.rules`), and the fcitx5 `profile` (materialized wholesale, since it holds nothing machine-specific). Add any new such file to both the `.stowrc` ignore list and matching POSIX/Windows sync steps, and keep its helper fail-closed.
- Keep the Unix updater POSIX sh and the PowerShell twin in parity: DOTFILES_DIR/AUTO_UPDATE, exported _DOTFILES_CHECKED, clean trees, fast-forward only, remembered host, locking, retries and no submodules. PowerShell runs only for interactive consoles, skips redirected stdout and must not set ErrorActionPreference=Stop. Keep update-hooks tests; [update-contract.md](docs/update-contract.md) owns acknowledgement and locking details.
- Automatic stow is enabled by default; `DOTFILES_AUTO_STOW=0` keeps pull-only behavior and `DOTFILES_AUTO_UPDATE=0` disables the entire hook. Unix must remember the explicitly installed host or use `DOTFILES_HOST`, never guess a Linux/cluster overlay. Store host/applied-revision state only in local Git metadata, bound to the home/platform. Windows automatic stow must run elevated through `scripts/dotfiles-auto-stow.ps1` or its explicitly registered current-user task; do not launch login-time UAC prompts. Failed or partial installs must not advance applied state. Keep executable update-hook tests for both shells.
- Packages hold regular files only (`stow-all.ps1` skips a symlink in one with a warning), so Windows clones need no `core.symlinks`. Keep the `.gitignore` lines of the three retired submodule checkouts and the `.stowrc` lines `^coding-agent-kit(/|$)` and `^PyMOLScripts(/|$)` until no host has those leftovers, and the `scripts/awesome-skills-update.sh` shim until every host has logged in once since the change.

## Windows

- `stow-all.ps1` is the legacy Windows command; `stow-all.sh` rejects `win` and points at it. Native chezmoi deploys regular files unelevated after actual profile/ACL preflight; it uses no elevated restow task. GNU Stow is not used on native Windows.
- Keep the two installers semantically aligned: `--target=~`, `--no-folding`, restow idempotency, the same ignore sources (`.stowrc` `--ignore=` lines plus per-package `.stow-local-ignore`), and the same portable/live sync steps. `stow-all.ps1` parses `.stowrc` rather than restating its patterns and invokes the same `claude-settings-sync`, `codex-config-sync`, and `codex-rules-sync` helpers through Git Bash (fail-closed when Git Bash or the helpers' own dependencies are missing); never fork the ignore list or reimplement the helpers.
- `stow-all.ps1` stows an explicit allowlist of `common/` packages, not every package. Git Bash sources `~/.bashrc` and `~/.bash_profile`, so the POSIX shell packages must stay out of a Windows `$HOME`. Extend `$CommonPackages` only for tools that run natively on Windows.
- `win/` packages mirror `$HOME` paths like every other package, including `Documents\PowerShell\` and `AppData\Local\Packages\`. No installer special-casing is needed because both live under `$HOME`.
- Windows Terminal `settings.json` is a plain Stow symlink: Terminal resolves symlinks before its atomic save (`til::io::write_utf8_string_to_file_atomic`), so UI saves write through the link. This has been true since v1.10.2383.0. Never use a hard link, which the same atomic rename would sever. Hot reload does not fire through a symlink, so edits need a Terminal restart.
- Run Windows stow elevated. RedirectionGuard can reject an otherwise locally readable link with error 448, "untrusted mount point". Trust checks run in a separate enforcing process without changing caller mitigations; failed/unavailable probes fail closed. Elevated runs repair rejected links; otherwise warn. Keep backup/removal/replacement under one ShouldProcess decision; declined operations prevent acknowledgement and fail -Strict. See [Windows installer](docs/windows-installer.md).
- Keep machine-specific user-profile paths out of tracked Windows files: write `Join-Path $HOME ...`, not `C:\Users\<name>\...`. Both PowerShell profiles load conda lazily through a `function global:conda` stub; `conda init powershell` would add an eager, absolute-path hook block, so treat it as drift to fix, not to commit.
- Keep PowerShell interactive setup in the then-branch of one `if ($IsInteractive -and -not $IsAgentSession)` block. Compute IsInteractive once from console stdin/stdout and PSReadLine; piped input, -File/-Command and -NonInteractive must skip setup, hooks and code-page changes. Match agent detection to zsh. Update and payload hooks stay in the interactive tail (agent terminals retain them), update first; payloads with windows-install rows only, never auto-install elevated, background pwsh -NoProfile. Probe optional executables on PATH, not Get-Command. Initialize oh-my-posh after key handlers, then zoxide, then a LASTEXITCODE-restoring prompt wrapper. Keep both lazy conda stubs/completers identical: remove the stub before hook execution, restore it if loading fails, and support mid-line completion. Preserve powershell-profile tests and [shell behavior](docs/shell.md).
- The oh-my-posh theme lives at `win/oh-my-posh/.config/oh-my-posh/prompt.omp.json` and is written for the installed oh-my-posh: keep `$schema` pinned to that release's tag (the MSIX package can update itself through App Installer, so re-check the pin), keep the file ASCII with `\uXXXX` glyph escapes, and re-render it after upgrading oh-my-posh.
- Windows Terminal `settings.json` stays strict JSON and ASCII. Keep machine-generated fragment GUIDs out of it; disable duplicate dynamic profile sources with `disabledProfileSources` instead, and never disable `Windows.Terminal.PowershellCore`.
- `.gitattributes` pins `eol=lf` because Git for Windows enables `core.autocrlf` in its system config. Files that must keep CRLF are marked `-text` individually.
- When checking out a pre-win revision on Windows, a dangling stowed ~/.gitconfig_local can make Git fail. Use an empty GIT_CONFIG_GLOBAL during that transition; restore the include by checking the supported branch back out. Do not commit machine-local workarounds.

## Workflows and checks

- Keep workflow definitions in `.github/workflows/*.yml`.
- `ci.yml` runs on pull requests, on pushes to `main` and on pushes to `ci/**` branches. Land a change by pushing it to a `ci/**` branch (and an `e2e-ci/**` branch when bootstrap or e2e behavior changes), then fast-forwarding `main` to that exact green commit and deleting the branches; every host pulls `main` at login, so it only ever receives commits CI passed on all three systems.
- Agents land their own changes this way without a pull request and without asking before each push, merge or kit release, once the local checks (`tests/run.sh --ci`, `pre-commit run --all-files`) and every job of that `ci.yml` run are green. They still ask before anything this guide forbids or that cannot be undone: moving or deleting a tag, rewriting `main`, or deleting someone else's work.
- Pin action versions and avoid unnecessary matrix complexity.
- Keep CI aligned with `.pre-commit-config.yaml` tools:
  - `shellcheck`
  - `shfmt`
  - `stylua`
  - basic hygiene hooks
- If CI behavior affects contributors, update `README.md` in the same change.

- Sherlock toolkit installation and project integration belong to its standalone repository and each consumer project. Dotfiles ships only version-free global guidance. Keep the retired Sherlock checkout ignored; never delete a checkout or its module store automatically. Installer retirement recognizes only exact historical source paths and the frozen generated-override marker; foreign files and links stay untouched.
