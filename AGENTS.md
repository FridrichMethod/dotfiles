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

## Topic docs

- Shell conventions: `.cursor/shared/shell.md`
- Git and SSH conventions: `.cursor/shared/git-ssh.md`
- Stow and update scripts: `.cursor/shared/stow-scripts.md`
- Workflow and CI conventions: `.cursor/shared/workflows.md`
