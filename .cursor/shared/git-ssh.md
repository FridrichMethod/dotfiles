# Git and SSH conventions

- Keep shared Git config in `common/git/.gitconfig`.
- Keep host-local Git overrides in `*/git/.gitconfig_local`.
- Preserve include chain: `[include] path = ~/.gitconfig_local`.
- Keep SSH root config minimal in `common/ssh/.ssh/config`:
  - `Include ~/.ssh/config.d/*.conf`
- Keep SSH targets split by concern in `.ssh/config.d/*.conf`.
- Do not commit secrets or private key material.
