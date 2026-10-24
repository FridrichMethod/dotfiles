# Installer validation contract

`stow-all.sh` preserves common-before-host Stow ordering and its existing
`--restow --no-folding` flags. GNU Stow and the readable repository `.stowrc`
are required before any write, so missing target/ignore defaults cannot send
Stow to its default parent-of-package-directory target. Before any AI helper writes to the
target, it invokes every selected helper with `--check`. The checks validate
the parser runtime and portable/live documents without creating directories,
materializing files, or modifying the tracked baseline.

After both stows succeeded it removes the links Stow made from the two
packages that the payload repos replaced (`common/coding-agent-kit`,
`common/pymol`), each only while it is a symlink whose text is exactly the one
Stow wrote, dangling or not, so a refused dry run or a failed stow leaves
them in place; a failed removal stops it before the applied revision is
recorded. It never runs a payload repo's installer
([payloads.md](payloads.md#migration)).

Provision the parser explicitly with `./setup-sync.sh` once per clone (see
`config-sync.md`). Login and automatic update never install dependencies. A
missing runtime or malformed later input must leave earlier live files and
the applied revision untouched.

Preflight is not a multi-file transaction. A later filesystem failure can
leave earlier files applied, but the installer must fail without acknowledging
that revision. Each sync helper is responsible for safe individual file
replacement and retries must be idempotent.

SSH permission cleanup skips dangling optional snippets regardless of their
filename order. An actual chmod failure still fails the installation. The
fcitx5 profile helper rejects directory and special-file targets, and retains
legacy symlinks until the replacement is fully staged. Failed staging or
replacement leaves the old profile accessible and cannot advance applied state.
