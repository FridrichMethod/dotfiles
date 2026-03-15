# Stow and update scripts

- `stow-all.sh` is the canonical setup command.
- Keep order stable: stow `common/` packages first, then optional host packages.
- Preserve Stow flags unless intentionally migrating behavior:
  - `--restow --no-folding`
- Keep `.stowrc` as global defaults (`--target=~` and ignore patterns).
- Keep `dotfiles-update.sh` POSIX `sh` and session-safe via `_DOTFILES_CHECKED`.
- When setup behavior changes, update both script comments and `README.md`.
