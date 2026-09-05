# Installer validation contract

`stow-all.sh` preserves common-before-host Stow ordering and its existing
`--restow --no-folding` flags. GNU Stow and the readable repository `.stowrc`
are required before any write, so missing target/ignore defaults cannot send
Stow to its default parent-of-package-directory target. Before any AI helper writes to the
target, it invokes every selected helper with `--check`. The checks validate
the parser runtime and portable/live documents without creating directories,
materializing files, or modifying the tracked baseline.

Provision the parser explicitly with `./setup-sync.sh` once per clone (see
`config-sync.md`). Login and automatic update never install dependencies. A
missing runtime or malformed later input must leave earlier live files and
the applied revision untouched.

Preflight is not a multi-file transaction. A later filesystem failure can
leave earlier files applied, but the installer must fail without acknowledging
that revision. Each sync helper is responsible for safe individual file
replacement and retries must be idempotent.
