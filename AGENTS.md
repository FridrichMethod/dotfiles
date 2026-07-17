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
- Never track credentials, OAuth state, sessions, histories, project trust, caches, downloaded plugins, generated memories, runtime marketplace paths, or machine-specific absolute paths.
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
