# Shell conventions

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
