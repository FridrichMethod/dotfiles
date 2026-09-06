# Behavioral test coverage

`./tests/run.sh` is the Unix entry point; `./tests/run.ps1` is the PowerShell
entry point. CI requires `--ci` on Unix and `-CI` on native Windows. Provision
the pinned parser with `setup-sync.sh` / `setup-sync.ps1` first. The pre-commit
hooks run the same focused Unix tests when their production sources change.

Shell line-coverage is not used as a hard gate: these programs mix sourced
POSIX shell, Bash, Python, Node, child processes, and PowerShell, for
which one percentage would omit meaningful branches. Coverage is tracked as a
source-to-test behavior matrix instead.

| Production target | Test | Covered behavior |
| --- | --- | --- |
| `lib/config_sync.py` and sync runtime/wrappers | `test_config_sync.py`, `config-sync.sh` | parsed TOML multiline/quoted/dotted/inline/AoT forms, required/retired ownership, JSON authoritative arrays and type-sensitive no-op, source immutability, explicit migration, read-only preflight, invalid/unreadable inputs, adjacent replacement and failure cleanup, stricter permissions retained on no-op/write, quiet success but visible errors, JSON/rules with stdlib-only runtime |
| `common/sh/.profile` | `shell-profile.sh` | unset/empty/explicit MANPATH, repeated sourcing in sh/Bash/Zsh, actual default man-page lookup when installed |
| `lib/terminal.sh`, `lib/terminal.ps1` | `terminal.sh`, `terminal.ps1` | TTY versus redirected output, color overrides, NO_COLOR and dumb terminals, literal messages, silent sourcing, PowerShell stream capture and preference isolation |
| `setup-sync.sh` / `setup-sync.ps1` | `test_config_sync.py`, CI setup steps | explicit pinned runtime, dependency validation, no runtime auto-install, unsafe environment reuse rejection |
| `common/claude/.local/bin/claude-settings-sync` | `ai-config-sync.sh` | portable-wins deep merge, live-only state, malformed/mistyped input, fresh and empty live files, permissions, idempotence, legacy symlink |
| `common/claude/.claude/dotfiles/*.cjs` | `claude-customizations.cjs` | status-line fallbacks and Git branches, terminal notification routing and escaping, Git bypass blocks and allowed commands, portable launchers with spaced paths; desktop delivery needs an interactive terminal |
| `common/codex/.local/bin/codex-config-sync` | `codex-config-sync.sh` | portable public-network profile ownership, runtime top-level/table/array-table preservation, legacy sandbox removal, removed compatibility flags, fresh live file, permissions, idempotence, missing-key failure, legacy symlink |
| `common/codex/.local/bin/codex-rules-sync` | `ai-config-sync.sh` | create/no-op, empty source failure, sibling preservation, permissions, matching legacy symlink, prompt-only/no-forbidden invariants, low-friction command coverage |
| `lab-ubuntu/fcitx5/.local/bin/fcitx5-profile-sync` | `fcitx5-profile-sync.sh` | create, authoritative replace, no-op inode, permissions, missing source, legacy symlink, staging/replacement failure preservation, directory/symlink-directory/FIFO rejection |
| `stow-all.sh` | `stow-all.sh`, `unix-installer.sh` | Windows/unknown-host rejection, common-before-host order, host overrides, all-input preflight before any apply, sync failures, exact Stow flags, SSH modes and final dangling snippet, real local-remote Git pull to real Stow and applied-state recording, spaced targets, unchanged sources |
| `scripts/dotfiles-update.sh` | `update-hooks.sh`, `unix-installer.sh` | session/disable/nounset guards, fast-forward and dirty/diverged Git cases, automatic stow, missing/mismatched acknowledgement, home/platform/host/HEAD binding, retry without new commits, two-process lock contention, real Git/Stow update |
| `scripts/awesome-skills-update.sh` | `awesome-skills-update.sh` | nounset/session/disable guards, actual manual alias after startup, consecutive forced syncs, first sync, download/installer failures, success stamp, throttle, live/stale/idle locks, incomplete-lock diagnostics, real simultaneous contenders, worker ownership after launcher exit, missing curl, cleanup |
| `stow-all.ps1`, `lib/windows-link-trust.ps1` | `windows-installer.sh`, `windows-installer.ps1`, `windows-installer-controls.ps1` | actual ShouldProcess accept/decline, backup preservation, Strict and applied-state handling, injected trust/repair failures, source/parse contract plus mandatory native Windows disposable-target link/adopt/backup/ignore/no-op/WhatIf/Strict and real shared-helper integration |
| `scripts/dotfiles-update.ps1`, `scripts/dotfiles-auto-stow.ps1` and PowerShell profile | `update-hooks.ps1`, `update-hooks.sh` | executable real-Git fast-forward/dirty-submodule/retry/home-binding/state/lock cases; installer, elevation and scheduled-task dispatch mocked; redirected profile and failure containment |
| `tests/run.sh`, `tests/run.ps1` and CI | `test-entrypoints.sh`, three native CI jobs | required dependencies fail visibly, local optional skips reported, native Windows job cannot run on Unix, shared backend suite required |

Windows updater mocks do not establish actual Task Scheduler execution. The
native installer job exercises NTFS links with the runner's local token, not
OpenSSH network-logon trust. Those require a controlled Windows environment.
Desktop notification delivery still requires an interactive terminal.

Interactive presentation helpers and network transfer aliases are outside this
core automation matrix. Add a row and a focused test when promoting one of them
to a supported automation contract.
