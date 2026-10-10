# Agent Guide

This repository stores cross-platform dotfiles managed with GNU Stow.

## Scope and layout

- Shared defaults live in `common/`.
- Host overlays live in `mac/`, `sherlock/`, `wsl-ubuntu/`, `lab-ubuntu/`, `marlowe/`, and `win/`. Other Linux distributions have no overlay; they stow `common/` only.
- Packages mirror `$HOME` paths (for example `.config/...`, `.ssh/...`).
- Non-package code is split by who calls it. The repo root holds only the entry
  points a person types on a fresh clone (`stow-all.sh`, `stow-all.ps1`,
  `setup-sync.sh`, `setup-sync.ps1`, `doctor.sh`, `doctor.ps1`, `setup-host.sh`,
  `setup-host.ps1`, `setup-sherlock-kit.sh`, `setup-sherlock-kit.ps1`,
  `setup-sherlock-adapters.sh`, `setup-sherlock-adapters.ps1`); `scripts/` holds
  hooks the environment invokes on its own (login profiles, the Windows
  scheduled task); `lib/` holds code that is only sourced or imported, never
  executed directly; `config/` holds the data those entry points read. Put a
  new file where its caller says it belongs, and keep `.stowrc` at the root
  because GNU Stow reads it from the working directory.

## Required conventions

- Keep secrets and machine-specific absolute paths out of version control.
- Preserve the Stow flow: `common/` first, host second.
- Update `README.md` and `stow-all.sh` usage together when setup behavior changes.

## Working commands

- Provision AI-sync parser once per clone: `./setup-sync.sh` (Windows: `./setup-sync.ps1`), with Python 3.11+.
- Check a host (read-only, offline): `./doctor.sh --host <host>` (Windows: `.\doctor.ps1`)
- Day-zero install, plan first: `./setup-host.sh --host <host> --check`, then without `--check` (Windows: `.\setup-host.ps1 -Check`, then `.\setup-host.ps1`)
- Stow configs: `./stow-all.sh [host-dir]`
- Initialize submodule: `git submodule update --init --recursive`
- Run checks: `pre-commit run --all-files`

## Verification

After modifying any file, run `pre-commit run --all-files` to ensure changes pass CI checks before committing.

## Shell conventions

- Keep POSIX logic in `common/sh/` and host `*/sh/` paths.
- Use Bash/Zsh-specific syntax only in matching shell files.
- Preserve override sourcing patterns from shared files:
  - `common/sh/.aliases` sources `~/.config/sh/.aliases`
  - `common/sh/.profile` sources `~/.config/sh/.profile`
- Keep startup flow quiet and idempotent; avoid duplicate side effects.
- PATH belongs in `common/sh/.profile`, which prepends `$HOME/bin` and `$HOME/.local/bin` behind a duplicate guard. `common/zsh/.zshrc` sources `~/.profile` near its top, right after the `typeset -U` block, so zsh inherits it too. Add new entries there, or in a host `*/sh/.profile`, never by appending to a shell rc.
- Third-party installers (Codex, Claude Code, nvm, conda) append PATH blocks to `~/.zshrc`, which is a Stow symlink, so the edit lands in `common/zsh/.zshrc` and shows up as a dirty repo. Default to discarding them: they re-export a directory `.profile` already added, without its duplicate guard, so PATH grows on every nested shell, and they hardcode one machine's home (`/home/<user>/...`) into a baseline stowed to hosts with different usernames and home roots. Keep only the intent, expressed portably via `$HOME` in the profile.
- nvm runs without the oh-my-zsh `nvm` plugin, so there are no lazy node/npm wrappers and no `.nvmrc` auto-switch: `common/sh/.profile` resolves nvm's `default` alias (chains, exact, partial, `node`/`stable`; `lts/-N` is left unresolved) with the `read` builtin and puts that bin on PATH for every shell and script. `common/zsh/.zshrc` keeps `path`/`PATH` unique only while it sets them up (`~/.profile`, the host rc, then the nvm block), moves nvm's bin ahead of brew/conda just before `source $ZSH/oh-my-zsh.sh` (no command-hash rebuild after the plugins), and in a shell that inherited `NVM_BIN` restores the parent's order instead; `fpath`/`INFOPATH` stay unique. `custom/nvm.zsh` only runs `nvm.sh --no-use`, loads its completion, and moves nvm ahead again when oh-my-zsh's brew plugin (macOS) put Homebrew's bin first. Only the official installer layouts (`~/.nvm`, `${XDG_CONFIG_HOME:-~/.config}/nvm`) are supported, not Homebrew-installed nvm. Plugin options that oh-my-zsh plugins read while loading must be set before `source $ZSH/oh-my-zsh.sh`, because `$ZSH_CUSTOM/*.zsh` is sourced only after every plugin (`.zshrc` pre-sources `ssh-agent.zsh` for that reason).
- `doctor.sh`, `setup-host.sh`, `lib/terminal.sh` and `lib/bootstrap/*.sh` use no here-documents, here-strings or process substitution, apply-only code included: Bash 3.2 (macOS `/bin/bash`) backs every here-document and here-string with a temporary file in `P_tmpdir` whatever `TMPDIR` says, which breaks the read-only modes' write-nothing contract, and keeps each process substitution's descriptor open until the outermost function returns. Split lines with `BOOTSTRAP_NL` parameter expansion, fields with `bootstrap_split`, and pipe text into a command (`bootstrap_text_has` for `grep -q`); `tests/bootstrap-manifest.sh` enforces it.
- Follow pre-commit shell style:
  - Bash: `shfmt -i 4 -ci -ln bash`
  - POSIX: `shfmt -i 4 -ci -ln posix`
  - Zsh: `shfmt -i 4 -ci -ln zsh` (needs shfmt 3.13+, the first release with a zsh dialect)

## Bootstrap and doctor

- Profiles, stow and the auto-update hooks never install a tool; only `setup-host.sh` and `setup-host.ps1` do, and only when a person runs them.
- `setup-host` never runs `sudo`, `chsh`, `stow`, `stow-all`, `conda init`, `micromamba shell init` or `git lfs install`, and never edits an rc file; it prints those as HUMAN blocks. Every block line is a `# ` note or a self-contained command. A `sudo` block is run by the person or, after explicit approval, each line as one visible top-level agent command, never wrapped in `sh -c` or a script; a printed digest gate (`printf ... | sha256sum -c --status - && <command>`) is one such line. Its only write inside the checkout is `.venv-sync`, through `./setup-sync.sh`.
- `./doctor.sh` without `--online` or `--smoke`, and `setup-host --check`, never write and never touch the network; `--online` runs the three auth probes, which go online and may write the tools' own state (claude rewrites `~/.claude.json`), and `--smoke` starts a zsh that may write its own caches. Every probe runs gh with `GH_TELEMETRY=0` (recent gh writes a device id on any command), and `tests/doctor.sh` runs the real doctor and manifest against the test machine's tools with an empty home to prove it.
- What setup-host cannot settle safely becomes a blocking judgment block, never a guess: oh-my-zsh stowed before its clone, a formula or cask that a Brewfile's `# conflicts: FORMULA OTHER...` or `# conflicts: cask TOKEN OTHER...` line names (checked by keg or `Caskroom` before any brew command, only where brew bundle installs the entry), and an `nvm.sh` that is not the pinned checkout without local changes (it is never sourced).
- `config/bootstrap/` is the single source of what the bootstrap installs: downloads are sha256-pinned in `installers.tsv` (the Catppuccin bat theme file included), and the oh-my-zsh, theme and plugin clones of `git-clones.tsv` track their upstream default branch, like oh-my-zsh's own auto-update (its `ref` column names that branch, never a commit). setup-host clones only a missing one and never modifies an existing clone (no fetch, pull, re-pin or dirty check); `docs/bootstrap.md` S3-clones gives the manual update loop. Unpinned plugin code runs in every shell, the same trust model as oh-my-zsh's auto-update. `docs/bootstrap.md`, `docs/dependencies.md` and both skills are parity-tested by `tests/bootstrap-manifest.sh`; change pins and branches there, not in docs.
- Every download setup-host makes itself is verified against its pin before use (only `inspect` rows, read by a person first, have none), a HUMAN block runs a downloaded script only behind a digest gate, and installers run with their no-rc flags (`PROFILE=/dev/null`, `NONINTERACTIVE=1`). Package managers (Homebrew, apt, conda-forge, winget, PSGallery and oh-my-posh's font installer) install their own current versions; the docs' Guarantees name them.
- First-party project skills live only in `.claude/skills/` and `.agents/skills/`, with identical bodies.
- Provisioning shells export `DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0`. Every test entry point (`tests/*.sh`, `tests/run.ps1`) unsets those and the other dotfiles knobs first, from the one list in `tests/run.sh`; `tests/test-entrypoints.sh` checks each entry point against it and that it covers every `DOTFILES_*`/`AWESOME_SKILLS_*` name in a tracked file outside `tests/`, `docs/`, `.github/` and Markdown, so a knob a new file reads goes on that list too.
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
- Keep the global `CLAUDE.md` and `AGENTS.md` aligned unless a tool-specific semantic difference requires divergence.
- The repository root `CLAUDE.md` is only an `@AGENTS.md` import stub for Claude Code; `AGENTS.md` is the single repository guide for every agent. Add or change repository policy in `AGENTS.md`, never in the stub.
- Keep the portable `pluginConfigs` Project instructions set to `claude-md-and-agents-md` under both `agents-md@builtin` and `cc-plugin-agents-md@builtin`. Do not restore the default or remove the `CLAUDE.md` stub: native ancestor loading covers subdirectory launches, while the stub covers older clients without native `AGENTS.md` support. Clients before 2.1.285 recognize only the legacy plugin ID.
- Shared settings may contain portable preferences, permission rules, plugin identifiers, and remote marketplace declarations.
- Do not declare `model` in the portable Claude `settings.json`. The sync asserts every key it declares, so a shared `model` would silently undo each host's `/model` choice on the next stow. Model selection stays machine-local; `effortLevel` and the rest remain shared.
- Claude's portable permission arrays are tiered by what each tier can actually enforce, because `ask` is the weakest tier, not the strongest: a matching `ask` rule prompts a human even in auto mode, and even when a `PreToolUse` hook returns `"allow"`, so it takes a destructive command out of the classifier's hands and hands it to a tired human instead. `permissions.ask` therefore holds only `sudo` (root, no ceiling on damage, and every invocation deserves a human). `permissions.deny` — evaluated first, absolute, unwaivable — holds `sudo pip`/`sudo pip3` plus the irrecoverable extremes `sudo rm` and the exact strings `rm -rf /`, `rm -fr /`, `rm -rf ~`, `rm -fr ~`. Keep those `rm` patterns exact: a trailing `*` matches any text, so `Bash(rm -rf /*)` would deny every absolute-path recursive removal with no prompt to recover through. Everything else — installs, network fetches, git operations including `push`, and GitHub actions including `pr merge`/`release create` — lives in `permissions.allow`; the portable arrays are authoritative over ad-hoc live edits.
- Ordinary `rm`, `rm -rf`, `git clean`, and `npx` are deliberately in none of the three arrays, so auto mode routes them to the classifier ("everything else goes to the classifier"). Three built-in backstops make that safe and are not configurable: `rm`/`rmdir` targeting a critical path (filesystem root, a direct child of the root, `$HOME`, the working directory and its parents, a `"$DIR"/*` glob, a Windows drive root) always goes to the classifier and can be approved by no allow rule and no hook `"allow"`, including when hidden inside `$(...)` or `<(...)`; Claude Code runs `git status` itself before work-discarding commands such as `rm -rf` and `git reset --hard` and shows the classifier whether staged, modified or untracked work exists; and a classifier denial lands in `/permissions` under **Recently denied** for retry with `r`, with auto mode pausing after 3 consecutive or 20 total blocks. Tune the classifier through the prose `autoMode.allow` and `autoMode.soft_deny` arrays rather than by moving commands back into `ask`, and always keep the literal `"$defaults"` entry — omitting it discards the entire built-in list for that section.
- `autoMode.classifyAllShell` is `true`, which suspends every Bash allow rule while auto mode is active. Do not try to fix a classifier false positive by adding a `permissions.allow` rule; it will be ignored in auto mode. Protected-path writes (anything under `.claude`, `.git`, and the rest of that list) are stricter still: allow rules "do not pre-approve protected-path writes", because the safety check runs before allow rules are evaluated. In practice this means Claude cannot loosen these arrays or run `claude-settings-sync` against `~/.claude/settings.json` on its own — a human applies those two steps.
- Security note: an automated review flagged the broad `allow` patterns above (network transfer via `curl`/`wget`/`ssh`/`scp`/`rsync`, code loaders via `source`/`.`/`tee`, package installers, and remote-mutating `git push`/`gh api`/`gh pr merge`) as a permission-bypass risk, recommending they stay in `ask` or be replaced with narrow, argument-anchored rules (for example, `curl` limited to specific hosts, `pip install` limited to `-r requirements.txt` in-tree). This is a knowingly accepted tradeoff, not an oversight: the risk was walked through category by category before the change, and `sudo` stays in `ask` while `sudo rm`, `sudo pip` and the irrecoverable `rm` spellings sit in `deny`, specifically because their damage is unbounded or irrecoverable in a way the allowed commands are not. Revisit toward the narrower, argument-anchored form if this host's threat model changes.
- Do not vendor third-party Markdown payloads copied into `~/.claude/rules/`; plugin checkouts may be used as an audit source, but Claude does not load plugin-bundled rules automatically. Keep reviewed cross-host instructions in the global `CLAUDE.md`.
- Never track credentials, OAuth state, sessions, histories, project trust, caches, downloaded plugins, generated memories, runtime marketplace paths, or machine-specific absolute paths.
- Preserve the portable/live split for Codex: `.stowrc` excludes `common/codex/.codex/config.toml` from Stow, and `stow-all.sh` runs `common/codex/.local/bin/codex-config-sync` to merge it into the mutable regular file at `~/.codex/config.toml`.
- Preserve the portable/live split for Claude: `.stowrc` excludes `common/claude/.claude/settings.json` from Stow, and `stow-all.sh` runs `common/claude/.local/bin/claude-settings-sync` to deep-merge it into the mutable regular file at `~/.claude/settings.json`. Portable keys win; live-only keys (for example the machine-specific `permissions.additionalDirectories`, plus any runtime state Claude Code writes) are preserved.
- Keep reviewed Codex exec-policy guardrails in `common/codex/.codex/rules/portable.rules`; `codex-rules-sync` materializes it without touching host-local `default.rules`. Portable rules may add targeted `prompt` safeguards but must not grant broad cross-host `allow` prefixes or use `forbidden`; exceptionally destructive actions require explicit user pre-authorization through the global Codex instructions.
- Keep all three AI sync helpers fail-closed. Update their sources, README documentation, and focused tests together when shared config, permission, or rule behavior changes. Keep machine-specific absolute paths (for example `permissions.additionalDirectories`) out of the portable `settings.json`.
- Keep structured merges in `lib/config_sync.py`; only TOML sync and the full runtime check require pinned `tomlkit`, while JSON/rules use the Python standard library. Do not reintroduce AWK/regex TOML parsing or a second JSON engine. Normal sync never rewrites the portable source; baseline cleanup is an explicit migration. Never broaden existing regular-file Unix permissions.
- Installers must run every selected AI helper with read-only `--check` before any apply; `--quiet` suppresses successful helper chatter, never errors. Provision `.venv-sync` or an explicitly selected interpreter in advance; profiles and automatic updates must never install dependencies.
- Stow cannot merge two files targeting the same path. If a host requires a different complete `settings.json` or `config.toml`, move that file from `common/<tool>/` to `<host>/<tool>/`; do not define it in both layers.
- Keep third-party skill payloads out of dotfiles; `scripts/awesome-skills-update.sh` owns `~/.claude/skills/` and `~/.codex/skills/` on each host.

## Stow and update scripts

- Keep status formatting in `lib/terminal.sh` / `lib/terminal.ps1`, with TTY-aware `DOTFILES_COLOR=auto|always|never`; nonempty `NO_COLOR` and `TERM=dumb` disable color. Preserve plain redirected logs by default, PowerShell stream capture, and caller shell/preferences. Under `auto`, treat a descriptor that Powerlevel10k's instant prompt captured as a terminal: it replays the capture file verbatim, and the check is `__p9k_instant_prompt_active` plus a numeric, still-a-terminal `__p9k_fd_1`/`__p9k_fd_2` (a non-numeric operand makes dash's `-t` print to stderr, which sourcing must never do). Every other hidden terminal stays plain. Do not add terminal formatting dependencies.

- `stow-all.sh` is the canonical setup command. Before any sync helper writes, it refuses to stow a package that links into `~/.oh-my-zsh` until `~/.oh-my-zsh/oh-my-zsh.sh` exists (`DOTFILES_STOW_WITHOUT_OH_MY_ZSH=1` overrides) and stops when a Stow dry run (`stow -n`) finds a conflict. Native Windows stows no zsh package and adopts conflicting files, so `stow-all.ps1` has neither check.
- Keep order stable: stow `common/` packages first, then optional host packages.
- Preserve Stow flags unless intentionally migrating behavior:
  - `--restow --no-folding`
- Keep `.stowrc` as global defaults (`--target=~` and ignore patterns).
- Do not shell-quote `.stowrc` option values. GNU Stow parses the file directly, and Stow 2.3.1 treats quote characters around `--ignore=` regexes literally; keep the focused test that stows into a temporary target with materialized files already present.
- `.stowrc` also excludes app-rewritten or helper-materialized files that `stow-all.sh` writes as machine-local regular files instead of symlinks: Codex `config.toml` and Claude `settings.json` (merged, portable keys win), Codex `portable.rules` (materialized without touching `default.rules`), and the fcitx5 `profile` (materialized wholesale, since it holds nothing machine-specific). Add any new such file to both the `.stowrc` ignore list and matching POSIX/Windows sync steps, and keep its helper fail-closed.
- Keep `scripts/dotfiles-update.sh` POSIX `sh` and session-safe via `_DOTFILES_CHECKED`. `scripts/dotfiles-update.ps1` is its PowerShell counterpart, invoked from the tail of `win/powershell/Documents/PowerShell/profile.ps1`; keep the two in contract parity (`DOTFILES_DIR`, `DOTFILES_AUTO_UPDATE`, `_DOTFILES_CHECKED`, fast-forward only, automatic stow after successful updates with remembered host, clean-tree protection, locking and failed-stow retries) and keep `tests/update-hooks.sh` passing. The PowerShell profile calls its counterpart only in an interactive console (`$IsInteractive`: console stdin and stdout, PSReadLine loaded). The script itself also skips redirected stdout, since every `pwsh -Command ...` call loads the profile, and must not set `$ErrorActionPreference` to `Stop`, which would let a failed `git fetch` abort the whole profile on PowerShell 7.4+.
- Automatic stow is enabled by default; `DOTFILES_AUTO_STOW=0` keeps pull-only behavior and `DOTFILES_AUTO_UPDATE=0` disables the entire hook. Unix must remember the explicitly installed host or use `DOTFILES_HOST`, never guess a Linux/cluster overlay. Store host/applied-revision state only in local Git metadata, bound to the home/platform. Windows automatic stow must run elevated through `scripts/dotfiles-auto-stow.ps1` or its explicitly registered current-user task; do not launch login-time UAC prompts. Failed or partial installs must not advance applied state. Keep executable update-hook tests for both shells.
- When setup behavior changes, update both script comments and `README.md`.

## Windows

- `stow-all.ps1` is the canonical setup command on native Windows; `stow-all.sh` rejects the `win` host and points at it. GNU Stow needs Perl and POSIX symlink semantics, so it is not used there.
- Keep the two installers semantically aligned: `--target=~`, `--no-folding`, restow idempotency, the same ignore sources (`.stowrc` `--ignore=` lines plus per-package `.stow-local-ignore`), and the same portable/live sync steps. `stow-all.ps1` parses `.stowrc` rather than restating its patterns and invokes the same `claude-settings-sync`, `codex-config-sync`, and `codex-rules-sync` helpers through Git Bash (fail-closed when Git Bash or the helpers' own dependencies are missing); never fork the ignore list or reimplement the helpers.
- `stow-all.ps1` stows an explicit allowlist of `common/` packages, not every package. Git Bash sources `~/.bashrc` and `~/.bash_profile`, so the POSIX shell packages must stay out of a Windows `$HOME`. Extend `$CommonPackages` only for tools that run natively on Windows.
- `win/` packages mirror `$HOME` paths like every other package, including `Documents\PowerShell\` and `AppData\Local\Packages\`. No installer special-casing is needed because both live under `$HOME`.
- Windows Terminal `settings.json` is a plain Stow symlink: Terminal resolves symlinks before its atomic save (`til::io::write_utf8_string_to_file_atomic`), so UI saves write through the link. This has been true since v1.10.2383.0. Never use a hard link, which the same atomic rename would sever. Hot reload does not fire through a symlink, so edits need a Terminal restart.
- Run `stow-all.ps1` from an elevated PowerShell. Links created without elevation can be rejected with `error 448: the path cannot be traversed because it contains an untrusted mount point` by processes enforcing RedirectionGuard, including current Windows OpenSSH installations, while remaining readable in an ordinary local PowerShell. Local readability and a matching target are not proof of trust. The installer uses a separate process with RedirectionGuard enforcement to probe links, without changing the calling shell's mitigation policy; failed or unavailable probes fail closed. Repair rejected links when elevated and warn otherwise. Repo-side symlinks (`common/pymol/.pymolrc*`) require the same check and must retain their **relative** target text when repaired so Git stays clean. Keep each file's backup/removal and replacement under one `ShouldProcess` decision; declined operations prevent applied-state acknowledgement and fail `-Strict`.
- Keep machine-specific user-profile paths out of tracked Windows files: write `Join-Path $HOME ...`, not `C:\Users\<name>\...`. Both PowerShell profiles load conda lazily through a `function global:conda` stub; `conda init powershell` would add an eager, absolute-path hook block, so treat it as drift to fix, not to commit.
- Keep interactive PowerShell setup inside the profile's single `if ($IsInteractive -and -not $IsAgentSession)` block, in its then-branch, where `$IsInteractive = -not [Console]::IsOutputRedirected -and -not [Console]::IsInputRedirected -and (Get-Module PSReadLine)` is computed once and also gates the update hook at the tail (agent terminals keep the update, as in zsh); commands piped to stdin (`| pwsh`, `-Command -`, `-File -`) skip both. Under the redirected stdout of every `pwsh -Command` call, prediction setup and `Import-Module CompletionPredictor` fail or hang, and `Microsoft.WinGet.CommandNotFound` stalls for about 30 s; the console host imports PSReadLine before the profile only for sessions that will read input, so console-attached `-File`/`-Command`/`-NonInteractive` runs skip setup too and never change the shared console code page. `$IsAgentSession` mirrors zsh's `_is_agent_session` with the same variables joined by `-or`; the test parses `common/zsh/.zshrc` to keep the two in parity. Profiles never install modules or apps. Optional executables are listed in `docs/dependencies.md` and probed on `PATH` rather than with `Get-Command`, which takes about 0.45 s per missing name. oh-my-posh initializes after every other PSReadLine key handler, because it owns Enter and Ctrl+C, and zoxide after oh-my-posh, because it wraps the prompt; a final prompt wrapper then restores `$LASTEXITCODE`, which `zoxide add` resets. Both profiles carry the identical conda stub (it removes itself before running the hook, so a failing `Conda.psm1` cannot recurse, and puts itself back when the hook did not load it) and completer. `tests/powershell-profile.ps1` enforces these rules.
- The oh-my-posh theme lives at `win/oh-my-posh/.config/oh-my-posh/prompt.omp.json` and is written for the installed oh-my-posh: keep `$schema` pinned to that release's tag (the MSIX package can update itself through App Installer, so re-check the pin), keep the file ASCII with `\uXXXX` glyph escapes, and re-render it after upgrading oh-my-posh.
- Windows Terminal `settings.json` stays strict JSON and ASCII. Keep machine-generated fragment GUIDs out of it; disable duplicate dynamic profile sources with `disabledProfileSources` instead, and never disable `Windows.Terminal.PowershellCore`.
- `.gitattributes` pins `eol=lf` because Git for Windows enables `core.autocrlf` in its system config. Files that must keep CRLF are marked `-text` individually.
- While this clone has a ref checked out that predates the `win/` packages, the stowed `~/.gitconfig_local` symlink dangles, and Git for Windows treats a global-config `[include]` of a dangling symlink as a fatal parse error — every git command on the machine fails, and a `git switch` can even tear mid-flight (worktree updated, `HEAD` not). To operate git inside such a window, point `GIT_CONFIG_GLOBAL` at an empty file; checking `main` back out restores the include target and heals git.

## Workflows and checks

- Keep workflow definitions in `.github/workflows/*.yml`.
- Pin action versions and avoid unnecessary matrix complexity.
- Keep CI aligned with `.pre-commit-config.yaml` tools:
  - `shellcheck`
  - `shfmt`
  - `stylua`
  - basic hygiene hooks
- Keep PyMOL submodule automation isolated in `update-pymolscripts-submodule.yml`.
- If CI behavior affects contributors, update `README.md` in the same change.
