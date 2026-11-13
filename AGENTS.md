# Agent Guide

This repository stores cross-platform dotfiles deployed by chezmoi on all six
hosts ([hosts](docs/hosts.md)).

## Scope and layout

- The chezmoi source is `home/` (`.chezmoiroot`); source names encode `$HOME` paths and attributes (`dot_`, `executable_`, `private_`, `empty_`), and `home/.chezmoiignore` selects each role's targets.
- Keep persistent worktrees in `.worktrees/`. Follow the global guides for temporary work, preservation and post-integration cleanup.
- Do not store task reports, logs, downloaded artifacts or diagnostic bundles in `.git/`. After acceptance, record concise conclusions in canonical docs as statements of the current state (no dates, commit, job or run IDs, or run narrative) and remove completed task artifacts. Preserve active payload ownership manifests and libraries, recovery credentials, and recovery state still needed for unfinished changes.
- Role variants live in `home/.hosts/<role>/<target path>`, read raw by one-line role-keyed templates; portable AI policy lives in `home/.policy/`. chezmoi never deploys a source dot-directory. Other Linux distributions use the `generic` role.
- One source file per target: plain files stay plain (no `.tmpl`, even with `{{` inside), and `tests/fixtures/chezmoi/targets.tsv` lists every target.
- Root scripts are person-facing setup/check entry points; `scripts/` contains login and person-run hooks, `lib/` sourced/imported code, and `config/` their data. Place files by their caller.


## Required conventions

- Keep secrets and machine-specific absolute paths out of version control.
- Write documentation, guides and skills in English using printable ASCII, tabs and line breaks only; the English-documentation hook enforces the character set. Payload repos use their own checks.
- Preserve the layering: shared `home/` files first, then the role variant from `home/.hosts/<role>/`.
- Update `README.md`, setup-host/doctor usage and script comments together when setup behavior changes.

## Weight and dependencies

These files are installed on every host, including fresh machines and clusters, so they must run on what a host already has and stay small enough to audit.

- Runtime helpers use only POSIX sh/Bash, ordinary POSIX utilities, Python 3.11+ stdlib (`python3 -I -B`) and the wrapped tool. No added pip packages, environments, Node, compiler, service or daemon. Tool installation belongs to setup-host.
- Missing optional tools narrow features; a missing required tool fails once with its name, without a traceback or partial run.
- Forward to native tools, requiring only a minimum version. Internal sockets/protocols/locks are best effort: warn and fall back to native behavior; block or ask only to prevent lost work.
- Keep helpers proportional and auditable. Prefer native features over a custom protocol client, journal or lock scheme; justify any such addition and its tests.
- Tests use unittest, real shells and fake third-party CLIs in temporary homes, with no network beyond loopback fixtures or access to real credentials/daemons. Optional real tools skip cleanly if absent; internet, credentials and Docker are opt-in (`tests/e2e/run.sh`).
- Linux CI checks prerequisites, then runs full pre-commit once for all behavior/lint checks. Keep developer hooks scoped by files and fast; pure parsing stays in-process, shells/children cover exec, signals, umask, TTY and modes. Preserve macOS and native Windows behavior passes; do not claim speedups without measurement.

## Working commands

- Check a host (read-only, offline): `./dotfiles doctor --host <host>` (Windows: `.\dotfiles.ps1 doctor --host win`)
- Day-zero install, plan first: `./dotfiles setup --host <host> --check`, then without `--check` (Windows: `.\dotfiles.ps1 setup --host win --check`, then without `--check`)
- First deployment: follow the H7-deploy/HW-deploy blocks (`docs/bootstrap.md`; a new home takes Fresh home by hand).
- Install or update payload repos: `dotfiles payloads sync [ITEM...]` or the interactive `sync-payloads` shortcut. Before deployment/configuration, run `CHECKOUT/dotfiles payloads sync` (Windows: `& CHECKOUT\dotfiles.ps1 payloads sync`, unelevated).
- Run tests: `./dotfiles dev test --ci`; run checks: `./dotfiles dev check` (formatters may edit files). Compatibility backends keep their existing interfaces: doctor/setup scripts, payload hooks and tests/run.*.
- Installed launchers use only the validated home's configured sourceDir, including help. Recover missing/invalid configuration through an explicit checkout entrypoint. Windows discovery requires the manual User PATH procedure in `docs/bootstrap.md`; profiles and setup never persist PATH.

## Verification

Keep this guide below 28,000 bytes; move explanatory material to canonical docs, never omit substantive rules.

After modifying any file, run `pre-commit run --all-files` to ensure changes pass CI checks before committing.

chezmoi owns deployment; the floors it depends on and why they hold are in
[dependencies](docs/dependencies.md#version-floors). Preserve unsupported-input
refusal, exact AI ownership/policy parity and the pinned WebP/terminfo bytes.
Maintenance blocks dotfiles updates AND payload runs
([maintenance](docs/updates.md#maintenance)). First apply is not an
ownership guard: review exact targets and private snapshots first. Host installs
follow exact candidate CI gates; commits/publication require active
authorization. Enroll only privately selected static secrets with explicit
recipients/bootstrap/recovery ([secrets](docs/secrets.md)); no plaintext,
identities or recurring OAuth state in source. Never force routine
apply. Pin `--exclude=dirs` on file apply/update to preserve shared
parents; the tested release has no effective config-key equivalent. Prepare only
exact missing directories with the reviewed directory-only apply
([missing parents](docs/bootstrap.md#preparing-missing-parents)). Future
missing parents require that preparation before retry; a failure is not
transactional. Review local umask and existing private-parent modes before
install/enrollment.

`tests/test_markdown_links.py` keeps every relative Markdown link and `#anchor`
in tracked Markdown resolving.

## Shell conventions

- Keep POSIX logic in `home/dot_profile`, `home/dot_aliases` and the role files under `home/.hosts/*/.config/sh/`.
- Use Bash/Zsh-specific syntax only in matching shell files.
- Preserve override sourcing patterns from shared files:
  - `~/.aliases` (`home/dot_aliases`) sources `~/.config/sh/.aliases`
  - `~/.profile` (`home/dot_profile`) sources `~/.config/sh/.profile`
- Keep startup flow quiet and idempotent; avoid duplicate side effects.
- PATH belongs in `~/.profile` (`home/dot_profile`), which prepends `$HOME/bin` and `$HOME/.local/bin` behind a duplicate guard. `~/.zshrc` (`home/dot_zshrc`) sources `~/.profile` near its top, right after the `typeset -U` block, so zsh inherits it too. Add new entries there, or in a role `home/.hosts/*/.config/sh/.profile`, never by appending to a shell rc.
- Discard installer-appended PATH blocks in deployed rc files by default. Express their intent portably via `$HOME` and duplicate guards in the profile; do not retain machine-home literals or repeated exports.
- Keep nvm free of the oh-my-zsh nvm plugin, lazy wrappers and `.nvmrc` auto-switching. Resolve default aliases with the read builtin in the profile without sourcing nvm; support exact/partial/node/stable and chains, leaving `lts/-N` unresolved. Support only `~/.nvm` and `${XDG_CONFIG_HOME:-~/.config}/nvm`. Keep PATH uniqueness scoped to zsh setup, fpath/INFOPATH unique, nvm ahead of brew/conda before oh-my-zsh, inherited NVM_BIN parent order intact, and no command-hash rebuild after plugins. `custom/nvm.zsh` loads `--no-use` and completion and repairs only brew-plugin reordering. Set plugin options before oh-my-zsh loads; pre-source ssh-agent options. See [shell startup](docs/shell.md).
- Do not use here-documents, here-strings or process substitution anywhere in `doctor.sh`, `setup-host.sh`, `lib/terminal.sh` or `lib/bootstrap/*.sh`, including apply-only paths. Bash 3.2 otherwise creates temp files or retains descriptors. Use BOOTSTRAP_NL splitting, bootstrap_split and pipes/bootstrap_text_has; keep bootstrap-manifest enforcement.
- Follow pre-commit shell style:
  - Bash: `shfmt -i 4 -ci -ln bash`
  - POSIX: `shfmt -i 4 -ci -ln posix`
  - Zsh: `shfmt -i 4 -ci -ln zsh` (needs shfmt 3.13+, the first release with a zsh dialect)

## Bootstrap and doctor

- Only `setup-host.sh` and `setup-host.ps1` install third-party tools, and only when a person runs them. The payload commands (`sync-payloads`, `scripts/payload-update.* --now`) install and update only the three payload repos, through each repo's own documented installer. Profiles and the dotfiles login update install nothing.
- setup-host never runs sudo, chsh, conda/micromamba shell init or git lfs install, nor edits rc files; print HUMAN blocks instead. Each line is a `# ` note or self-contained command. A person runs privileged lines, or approves each visible top-level agent command; never hide them in a script or `sh -c`. Printed digest-gate lines and the shared-prefix `(cd /tmp && sudo -u OWNER ...)` form are single commands. Never chown a shared Homebrew prefix. It writes nothing inside the checkout. S2-brew-bundle skips entries already satisfying their tools.tsv probe or alias via apt, conda or OS.
- Doctor without --online/--smoke and setup-host --check stay offline and write-free. --online runs only three auth probes and may write the tools' own state; --smoke may write zsh caches. Always set GH_TELEMETRY=0 and TLDR_AUTO_UPDATE_DISABLED=1 for probes, including --version. Keep empty-home real-tool and stateful-fake no-write tests; see [guarantees](docs/bootstrap.md#guarantees).
- What setup-host cannot settle safely becomes a blocking judgment block, never a guess: dotfiles applied before the oh-my-zsh clone, a formula or cask that a Brewfile's `# conflicts: FORMULA OTHER...` or `# conflicts: cask TOKEN OTHER...` line names (checked by keg or `Caskroom` before any brew command, only where brew bundle installs the entry), and an `nvm.sh` that is not the pinned checkout without local changes (it is never sourced).
- `config/bootstrap/` owns installer SHA256 pins (bat theme included), tool floors and clone branches. git-clones.tsv tracks upstream default branches, never commits; clone only missing repositories and do not fetch, pull, repin or dirty-check existing ones. Retain the manual update loop and trust limits in [bootstrap.md](docs/bootstrap.md#s3-clones-oh-my-zsh-theme-and-plugin-clones). Keep step-heading, tool-ID and mirrored-skill parity tests; update manifests, not copied pin inventories.
- Verify every setup-host download before use except inspect rows, which a person reads first. HUMAN execution uses digest gates and installers use no-rc flags (PROFILE=/dev/null, NONINTERACTIVE=1). Preserve the documented distinction between pinned downloads/default-branch clones and package managers' current versions.
- First-party project skills live only in `.claude/skills/` and `.agents/skills/`, with identical bodies.
- Provisioning shells export DOTFILES_AUTO_UPDATE=0. Test entrypoints use tests/lib/environment.sh/.ps1 to clear inherited DOTFILES_, _DOTFILES_, AWESOME_SKILLS_, _AWESOME_SKILLS_, CODING_AGENT_KIT_ and _CODING_AGENT_KIT_ prefixes plus XDG_STATE_HOME/XDG_DATA_HOME; preserve DOTFILES_TEST_* inputs. Fixture Git must drop repository/index overrides before mutation. Keep focused linked-worktree isolation and hook-selection tests; do not scan upstream implementation or mirror every variable in every entrypoint.
- Without `--host` (or the doctor's `--platform`), the host is the `[data]` `host` line of the home's `~/.config/chezmoi/chezmoi.toml`, read as text (malformed: exit 2 asking for `--host`); nothing else selects one, and a home without that config exits 2. `generic` there means: the doctor checks the detected platform without an overlay and warns; setup-host exits 2 asking for `--host`. The Windows twins check `win`.
- HPC environments are built only inside a Slurm allocation, never under `$SCRATCH`.

## Git and SSH conventions

- Keep shared Git config in `home/dot_gitconfig`.
- Keep host-local Git overrides in `home/.hosts/*/.gitconfig_local`.
- Preserve include chain: `[include] path = ~/.gitconfig_local`.
- Keep SSH root config minimal in `home/dot_ssh/config`:
  - `Include ~/.ssh/config.d/*.conf`
- Keep SSH targets split by concern in `.ssh/config.d/*.conf`.
- Do not commit secrets or private key material.

## AI assistant configuration

- Keep shared user-global files in these sources; `.claude/settings.json` `claudeMdExcludes` keeps both guides from loading as nested project guides:
  - `home/dot_claude/CLAUDE.md`
  - `home/.policy/claude-settings.json` (read by `home/dot_claude/modify_private_settings.json`)
  - `home/dot_codex/AGENTS.md`
  - `home/.policy/codex-config.toml` (read by `home/dot_codex/modify_private_config.toml`)
  - `home/dot_codex/rules/portable.rules`
- coding-agent-kit owns Unix launchers, completions and Claude Node helpers under `~/.claude/coding-agent-kit/`; dotfiles ships no kit config. Linux/macOS/WSL only: no Windows install/check rows. Native Windows runs no helper and the commands exit 0; Unix missing helpers fail visibly. Preserve these platform guards.
- Keep the global `CLAUDE.md` and `AGENTS.md` aligned unless a tool-specific semantic difference requires divergence.
- The repository root `CLAUDE.md` is only an `@AGENTS.md` import stub for Claude Code; `AGENTS.md` is the single repository guide for every agent. Add or change repository policy in `AGENTS.md`, never in the stub.
- Set Project instructions to `claude-md-and-agents-md` under both pluginConfigs IDs, agents-md@builtin and cc-plugin-agents-md@builtin (pre-2.1.285 clients use the former; newer clients accept either). Keep native ancestor loading and the CLAUDE.md stub for old clients.
- Shared settings may contain portable preferences, permission rules, plugin identifiers, and remote marketplace declarations.
- Do not declare `model` in the portable Claude `settings.json`; the modify template refuses it, since a shared `model` would undo each host's `/model` choice. Model selection stays machine-local; `effortLevel` and the rest remain shared.
- Preserve Claude permission tiers and authoritative arrays: ask holds only sudo; deny holds sudo pip/pip3, sudo rm, and the exact `rm -rf /`, `rm -fr /`, `rm -rf ~`, `rm -fr ~` patterns. Never add trailing wildcards to those rm denials. Reviewed installs/network/Git/GitHub operations remain in allow. This accepted broad policy is not a prompt to redesign permissions; its rationale is in [ai-config.md](docs/ai-config.md#permission-policy-rationale).
- Keep ordinary rm/rm -rf, git clean and npx out of all three arrays so auto mode uses its classifier. Tune autoMode.allow/soft_deny prose, preserving literal `$defaults`, rather than moving commands into ask. Built-in critical-path and work-discard checks remain in force; see the policy rationale.
- Keep autoMode.classifyAllShell=true: Bash allow rules cannot bypass auto-mode review. Do not add allow rules to cure classifier false positives. Protected-path checks precede allow rules; Claude must not loosen these arrays or apply them to live settings unaided: a human applies both steps.
- Preserve the accepted broad-allow tradeoff. Reconsider narrower argument-anchored network/install/remote-mutation rules only when the host threat model changes; do not silently change the policy during unrelated work.
- Do not vendor third-party Markdown payloads copied into `~/.claude/rules/`; plugin checkouts may be used as an audit source, but Claude does not load plugin-bundled rules automatically. Keep reviewed cross-host instructions in the global `CLAUDE.md`.
- Never track credentials, OAuth state, sessions, histories, project trust, caches, downloaded plugins, generated memories, runtime marketplace paths, or machine-specific absolute paths.
- Codex config.toml and Claude settings.json deploy through the two modify templates as private regular files, portable keys winning and live-only state retained; see [AI configuration](docs/ai-config.md).
- Keep reviewed Codex exec-policy guardrails in `home/dot_codex/rules/portable.rules`; chezmoi apply deploys it as an ordinary file without touching host-local `default.rules`. Portable rules may add targeted `prompt` safeguards but must not grant broad cross-host `allow` prefixes or use `forbidden`; exceptionally destructive actions require explicit user pre-authorization through the global Codex instructions.
- When shared config, permission or rule behavior changes, update the portable sources, README and focused tests together.
- A target has one owner. Keep one portable policy file per tool in `home/.policy/`; never add a host-specific second copy.
- Keep third-party skill payloads out of dotfiles; awesome-skills' own installer, which sync-payloads runs, owns only its installed copies under `~/.claude/skills/`, `~/.codex/skills/` and `~/.agents/skills/awesome-skills/` (Codex reads both roots) on each host.

## Payload repos

- coding-agent-kit, PyMOLScripts and awesome-skills own their installation, update, selection and locking. Dotfiles calls them only through the commands in `config/payloads.tsv`, the one place naming their URLs, paths, commands and the kit channel (`0.7`), and the items a platform has (an item without a `windows-install` row, the kit, is not available on native Windows: no default item there, and naming it is an info, exit 0); a channel or command change is a reviewed change of that file (`docs/payloads.md`). No submodules, bump workflows or consumer-side pins.
- `scripts/payload-update.sh` and `.ps1` keep one contract: a person runs them in the foreground (`--now`/`-Now` or `sync-payloads`, which needs and follows the validated chezmoi config); any other call prints one usage line and exits 2; no login, schedule, stamp, record or lock of their own; exit 75 is no failure, others exit 1 with a retry line (`sync-payloads` only where it would run that hook, else the hook's own quoted `--now`/`-Now` line); downloads bounded by `DOTFILES_PAYLOAD_TIMEOUT`, each staged alone in a fresh private temporary directory removed afterwards and never piped into a shell, one failed download ending the run's downloads. `tests/payload-update.sh` covers it.

## Login updates and terminal output

- Keep status output in lib/terminal.sh/.ps1, with DOTFILES_COLOR=auto|always|never; nonempty NO_COLOR and TERM=dumb disable it. Preserve plain redirected logs, PowerShell stream capture and caller preferences. Add no formatting dependency.

- Interactive logins update only a home whose `~/.config/chezmoi/chezmoi.toml` names it and a dotfiles checkout in one top-level `sourceDir` and `destDir` line as chezmoi init writes them (validated, text only, by `lib/chezmoi-guard.sh`/`.ps1`), after the maintenance check, through that checkout's `scripts/chezmoi-update.sh`/`.ps1` ([updates.md](docs/updates.md)); a home without that config runs nothing and prints nothing, an invalid one warns once, and there is no checkout fallback. `DOTFILES_AUTO_UPDATE=0` disables the hook. Windows runs only the private `~/.local/bin/chezmoi.exe`, never a PATH match.
- The source holds regular files only, so Windows clones need no `core.symlinks`.

## Windows

- chezmoi deploys regular files unelevated, after [Fresh Windows home by hand](docs/bootstrap.md#fresh-windows-home-by-hand) checks both actual profile paths and the ordinary user reviews the destination parents' ACLs; no dotfiles code registers an elevated or scheduled task (agents' one-off tasks follow [hosts](docs/hosts.md#win)).
- Windows receives only the shared targets that `home/.chezmoiignore` does not exclude for `win`, as the hosts column of `tests/fixtures/chezmoi/targets.tsv` pins, so a new shared target reaches Windows unless excluded. Git Bash sources `~/.bashrc` and `~/.bash_profile`, so the POSIX shell files must stay out of a Windows `$HOME`; let a target reach Windows only for tools that run natively there.
- Windows targets live under `home/` like every other target, including `Documents/PowerShell/` and `AppData/Local/Packages/`, both under `$HOME`.
- Windows Terminal `settings.json` is a regular file chezmoi applies; a UI save is destination drift to reconcile ([shell](docs/shell.md)). Edits need a Terminal restart.
- Keep machine-specific user-profile paths out of tracked Windows files: write `Join-Path $HOME ...`, not `C:\Users\<name>\...`. Both PowerShell profiles load conda lazily through a `function global:conda` stub; `conda init powershell` would add an eager, absolute-path hook block, so treat it as drift to fix, not to commit.
- Keep PowerShell interactive setup in the then-branch of one `if ($IsInteractive -and -not $IsAgentSession)` block. Compute IsInteractive once from console stdin/stdout and PSReadLine; piped input, -File/-Command and -NonInteractive must skip setup, hooks and code-page changes. Match agent detection to zsh. The update hook stays in the interactive tail (agent terminals retain it); no payload hook runs there, and sync-payloads/sync-skills run only when typed (windows-install rows only). Probe optional executables on PATH, not Get-Command. Initialize oh-my-posh after key handlers, then zoxide, then a LASTEXITCODE-restoring prompt wrapper. Keep both lazy conda stubs/completers identical: remove the stub before hook execution, restore it if loading fails, and support mid-line completion. Preserve powershell-profile tests and [shell behavior](docs/shell.md).
- The oh-my-posh theme lives at `home/dot_config/oh-my-posh/prompt.omp.json` (a plain file: it contains `{{`) and is written for the installed oh-my-posh: keep `$schema` pinned to that release's tag (the MSIX package can update itself through App Installer, so re-check the pin), keep the file ASCII with `\uXXXX` glyph escapes, and re-render it after upgrading oh-my-posh.
- Windows Terminal `settings.json` stays strict JSON and ASCII. Keep machine-generated fragment GUIDs out of it; disable duplicate dynamic profile sources with `disabledProfileSources` instead, and never disable `Windows.Terminal.PowershellCore`.
- `.gitattributes` pins `eol=lf` because Git for Windows enables `core.autocrlf` in its system config. Files that must keep CRLF are marked `-text` individually: `home/dot_wslconfig` and `home/mount.vbs` keep CRLF.

## Workflows and checks

- Keep workflow definitions in `.github/workflows/*.yml`.
- `ci.yml` runs on pull requests, on pushes to `main` and on pushes to `ci/**` branches. Land a change by pushing it to a `ci/**` branch (and an `e2e-ci/**` branch when bootstrap or e2e behavior changes), then fast-forwarding `main` to that exact green commit and deleting the branches. Each host's deployed checkout stays on a clean `main` tracking `origin/main` (work happens in worktrees or clones), and the login update applies whatever that checkout's branch holds, so a host only ever receives commits CI passed on all three systems.
- Agents land their own changes this way without a pull request and without asking before each push, merge or kit release, once the local checks (`tests/run.sh --ci`, `pre-commit run --all-files`) and every job of that `ci.yml` run are green. They still ask before anything this guide forbids or that cannot be undone: moving or deleting a tag, rewriting `main`, or deleting someone else's work.
- Agents may roll landed changes out to the six hosts by [docs/hosts.md](docs/hosts.md).
- Pin action versions and avoid unnecessary matrix complexity.
- Keep CI aligned with `.pre-commit-config.yaml` tools:
  - `shellcheck`
  - `shfmt`
  - `stylua`
  - basic hygiene hooks
- If CI behavior affects contributors, update `README.md` in the same change.

- Sherlock toolkit installation and project integration belong to its standalone repository and each consumer project. Dotfiles ships only version-free global guidance.
