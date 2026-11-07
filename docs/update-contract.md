# Native login update contract

A login updates only a home that native chezmoi owns, through the updater of
the source that home is bound to. This page is the durable contract of that
update; the manual commands, takeover and recovery live in
[takeover.md](chezmoi-migration/takeover.md#updates-and-edits-after-takeover).

## Trigger

- Only interactive shells update. `~/.profile` (`home/dot_profile`) dispatches
  for sh and Bash; zsh dispatches from the tail of `~/.zshrc`, after ssh-agent
  and the host environment are ready; PowerShell 7 dispatches from the tail of
  its profile, only under `$IsInteractive` (console stdin and stdout and a
  loaded PSReadLine), so `-File`, `-Command`, `-NonInteractive` and piped input
  never update. The Windows PowerShell 5.1 profile has no update hook.
- One attempt per session: the updater exports `_DOTFILES_CHECKED`, and a
  nested shell that inherits it does not try again.
- `DOTFILES_AUTO_UPDATE=0` disables the hook.

## Selection

- Maintenance comes first: while `~/.config/dotfiles/maintenance` exists, in
  any form, nothing runs.
- `~/.config/dotfiles/native` must be a regular file of exactly three
  terminated lines: `dotfiles-chezmoi-v1`, the home and an absolute source.
  The profile reads only enough to find that source's guard
  (`lib/chezmoi-guard.sh` or `.ps1`), which validates the whole binding before
  the source's `scripts/chezmoi-update.sh` or `.ps1` runs.
- An invalid binding prints one warning and runs nothing.
- An unmarked home runs nothing and prints nothing. There is no fallback to
  `~/dotfiles`, an environment variable or any other checkout, and a retired
  checkout's guard or updater is never sourced.

## Refusals

The updater stops, with a warning and without touching the destination, when:

- the source has tracked or untracked changes (ignored files do not count);
- the native state database is missing or empty, because lost state can turn
  a foreign target into a first apply (recovery is an inspected maintenance
  action);
- the source path contains OneDrive (use the independent-clone procedure);
- the effective update configuration is not the safe one below;
- on Windows, `~/.local/bin/chezmoi.exe` is missing, a link, or owned or
  writable by an account other than you, SYSTEM and Administrators. Only that
  file runs, never a PATH match
  ([W1-chezmoi](bootstrap.md#w1-chezmoi-windows-native-chezmoi-binary)).

## Invocation

- Every run passes the full explicit argument set: `--source`,
  `--working-tree`, `--destination`, `--config`, `--cache` and
  `--persistent-state` of the bound home, so inherited XDG or chezmoi settings
  cannot redirect it, plus `--mode=file --no-tty --error-on-conflict
  --less-interactive --no-pager --use-builtin-diff --use-builtin-age=true
  --use-builtin-git=false --force=false`.
- Before updating, an `execute-template` check requires the validated
  fast-forward-only update command
  (`git -c rebase.autoStash=false -c merge.autoStash=false pull --ff-only
  --no-rebase --no-autostash --no-recurse-submodules`), no submodule recursion
  and no Git auto add, commit or push.
- The update itself is `update --apply --exclude=dirs
  --recurse-submodules=false`, with stdin closed. Credential helpers, askpass
  programs and Git hooks are disabled, so nothing prompts.
- Transport is bounded: an SSH connect timeout and an HTTPS low-speed abort
  end normal network failures, and on Windows each native process is killed
  after 60 seconds. An SSH session that stalls after connecting can still wait
  for the operating system's defaults.

## Failure

- A failure prints one generic warning; native output, which can carry
  secrets, is never printed.
- The shell stays usable, the PowerShell profile keeps the caller's
  preferences, and the next session retries.
- A source fast-forward can succeed before apply refuses a target. The update
  is not a whole-home transaction.

## New targets

A target added to the source reaches every bound home through this update,
which stops on it when:

- its parent directory is missing: an operator first prepares exactly that
  directory with the reviewed directory-only apply of
  [takeover.md](chezmoi-migration/takeover.md), since the update excludes
  directories;
- an unmanaged file already sits at its path: that first-target conflict
  waits until it is reconciled under the same procedure.

On Windows, a new target under an existing parent inherits that parent's ACL.
Name the parent's ACL model for each new Windows target, and when the parent
is broader than the intended file ACL, materialize the file under a reviewed
protected ACL instead of relying on inheritance.

## Not provided

No scheduler, receipts, locks, retries within a session, elevation or payload
runs. The payload repos install only when a person runs `sync-payloads` or
`scripts/payload-update.sh --now` (`payload-update.ps1 -Now`); see
[payloads.md](payloads.md). Do not run a manual native apply while a login
update runs.

## Coverage

- `tests/test_chezmoi_takeover_unix.py`, `tests/test_chezmoi_takeover_windows.py`
  and `tests/test_chezmoi_takeover_recovery.py`: the updaters against real
  local remotes and disposable homes, refusals, divergence, conflicts and the
  PowerShell profile tail.
- `tests/test_chezmoi_update_config.py`: the safe update configuration.
- `tests/test_chezmoi_guard.py`: binding validation and the sh and Bash login
  dispatch, with and without the Sherlock overlay.
- `tests/shell-profile.sh`: quiet unmarked logins under sh, dash, Bash and zsh.
- `tests/powershell-profile.ps1`: the PowerShell 7 tail's structure and
  placement.
