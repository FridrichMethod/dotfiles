# Agent Guide (Codex)

This repository stores cross-platform dotfiles managed with GNU Stow.

## Scope and layout

- Shared defaults live in `common/`.
- Host overlays live in `mac/`, `sherlock/`, `wsl-ubuntu/`, `lab-ubuntu/`, `marlowe/`, `fedora/`, `ubuntu/`, and `win/`.
- Packages mirror `$HOME` paths (for example `.config/...`, `.ssh/...`).

## Required conventions

- Keep secrets and machine-specific absolute paths out of version control.
- Preserve the Stow flow: `common/` first, host second.
- Update `README.md` and `stow-all.sh` usage together when setup behavior changes.

## Working commands

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
- Follow pre-commit shell style:
  - Bash: `shfmt -i 4 -ci -ln bash`
  - POSIX: `shfmt -i 4 -ci -ln posix`
  - Zsh: `shfmt -i 4 -ci -ln zsh`

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
- Keep the global `CLAUDE.md` and `AGENTS.md` aligned unless a tool-specific semantic difference requires divergence.
- Shared settings may contain portable preferences, permission rules, plugin identifiers, and remote marketplace declarations.
- Do not declare `model` in the portable Claude `settings.json`. The sync asserts every key it declares, so a shared `model` would silently undo each host's `/model` choice on the next stow. Model selection stays machine-local; `effortLevel` and the rest remain shared.
- Never track credentials, OAuth state, sessions, histories, project trust, caches, downloaded plugins, generated memories, runtime marketplace paths, or machine-specific absolute paths.
- Preserve the portable/live split for Codex: `.stowrc` excludes `common/codex/.codex/config.toml` from Stow, and `stow-all.sh` runs `common/codex/.local/bin/codex-config-sync` to merge it into the mutable regular file at `~/.codex/config.toml`.
- Keep the sync helper fail-closed and update its allowlist, README documentation, and portable `config.toml` together when shared Codex keys change.
- Stow cannot merge two files targeting the same path. If a host requires a different complete `settings.json` or `config.toml`, move that file from `common/<tool>/` to `<host>/<tool>/`; do not define it in both layers.
- Keep third-party skill payloads out of dotfiles; `awesome-skills-update.sh` owns `~/.claude/skills/` and `~/.codex/skills/` on each host.

## Stow and update scripts

- `stow-all.sh` is the canonical setup command.
- Keep order stable: stow `common/` packages first, then optional host packages.
- Preserve Stow flags unless intentionally migrating behavior:
  - `--restow --no-folding`
- Keep `.stowrc` as global defaults (`--target=~` and ignore patterns).
- Keep `dotfiles-update.sh` POSIX `sh` and session-safe via `_DOTFILES_CHECKED`.
- When setup behavior changes, update both script comments and `README.md`.

## Windows

- `stow-all.ps1` is the canonical setup command on native Windows; `stow-all.sh` rejects the `win` host and points at it. GNU Stow needs Perl and POSIX symlink semantics, so it is not used there.
- Keep the two installers semantically aligned: `--target=~`, `--no-folding`, restow idempotency, the same ignore sources (`.stowrc` `--ignore=` lines plus per-package `.stow-local-ignore`), and the same portable/live sync steps. `stow-all.ps1` parses `.stowrc` rather than restating its patterns and invokes the same `claude-settings-sync`/`codex-config-sync` helpers through Git Bash (fail-closed when Git Bash or the helpers' own dependencies are missing); never fork the ignore list or reimplement the helpers.
- `stow-all.ps1` stows an explicit allowlist of `common/` packages, not every package. Git Bash sources `~/.bashrc` and `~/.bash_profile`, so the POSIX shell packages must stay out of a Windows `$HOME`. Extend `$CommonPackages` only for tools that run natively on Windows.
- `win/` packages mirror `$HOME` paths like every other package, including `Documents\PowerShell\` and `AppData\Local\Packages\`. No installer special-casing is needed because both live under `$HOME`.
- Windows Terminal `settings.json` is a plain Stow symlink: Terminal resolves symlinks before its atomic save (`til::io::write_utf8_string_to_file_atomic`), so UI saves write through the link. This has been true since v1.10.2383.0. Never use a hard link, which the same atomic rename would sever. Hot reload does not fire through a symlink, so edits need a Terminal restart.
- Keep machine-specific user-profile paths out of tracked Windows files: write `Join-Path $HOME ...`, not `C:\Users\<name>\...`. Re-running `conda init` re-hardcodes its block; treat that as drift to fix, not to commit.
- Guard anything in a PowerShell profile that needs a real console behind `if (-not [Console]::IsOutputRedirected)`. Prediction setup, `Import-Module CompletionPredictor`, and `Install-Module` all fail or hang under the redirected stdout of every `pwsh -Command` call.
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
