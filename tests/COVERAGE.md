# Behavioral test coverage

`./tests/run.sh` is the authoritative local entry point. The pre-commit hooks
run the same focused tests when their production sources change.

Shell line-coverage is not used as a hard gate: these programs mix sourced
POSIX shell, Bash, embedded Awk/Python, child processes, and PowerShell, for
which one percentage would omit meaningful branches. Coverage is tracked as a
source-to-test behavior matrix instead.

| Production target | Test | Covered behavior |
| --- | --- | --- |
| `common/claude/.local/bin/claude-settings-sync` | `ai-config-sync.sh` | portable-wins deep merge, live-only state, malformed/mistyped input, fresh and empty live files, permissions, idempotence, legacy symlink |
| `common/codex/.local/bin/codex-config-sync` | `codex-config-sync.sh` | portable public-network profile ownership, runtime top-level/table/array-table preservation, legacy sandbox removal, removed compatibility flags, fresh live file, permissions, idempotence, missing-key failure, legacy symlink |
| `common/codex/.local/bin/codex-rules-sync` | `ai-config-sync.sh` | create/no-op, empty source failure, sibling preservation, permissions, matching legacy symlink, prompt-only/no-forbidden invariants, low-friction command coverage |
| `lab-ubuntu/fcitx5/.local/bin/fcitx5-profile-sync` | `fcitx5-profile-sync.sh` | create, authoritative replace, no-op inode, permissions, missing source, legacy symlink |
| `stow-all.sh` | `stow-all.sh` | Windows/unknown-host rejection, common-before-host order, host overrides, all sync helpers, fail-closed sync, legacy Git filter cleanup, exact Stow flags/packages, SSH target permissions |
| `dotfiles-update.sh` | `update-hooks.sh` | noninteractive/session/disable guards, nounset, missing Git/repository, fetch/rev-list/pull failures, up-to-date/invalid counts, successful pull, best-effort submodules, exported marker and cleanup |
| `awesome-skills-update.sh` | `awesome-skills-update.sh` | nounset/session/disable guards, first sync, download/installer failures, success stamp, throttle, live/stale PID locks, missing curl, cleanup |
| `stow-all.ps1` | `windows-installer.sh` | source contract and optional PowerShell parse check; NTFS link/adopt/backup behavior still requires a native Windows integration job |
| `dotfiles-update.ps1` and PowerShell profile | `update-hooks.sh` | cross-platform contract and optional PowerShell parse check; Git state branches are dynamically covered by the POSIX counterpart only |

Interactive presentation helpers and network transfer aliases are outside this
core automation matrix. Add a row and a focused test when promoting one of them
to a supported automation contract.
