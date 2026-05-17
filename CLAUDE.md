# Claude Code Guide

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
