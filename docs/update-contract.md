# Automatic update and apply contract

The Unix and PowerShell login hooks share the same safety boundary: update
only a clean checkout, use fast-forward-only pulls, preserve explicit host
selection, and acknowledge only an installed revision. An installer returning
success is necessary but is not sufficient evidence that configuration was
fully applied.

## Acknowledgement and retry

Unix stores four newline-delimited fields in the Git metadata path returned by
`git rev-parse --git-path dotfiles-sync-unix`: home, platform (`uname -s`), host,
and applied HEAD. The updater rereads all four fields after `stow-all.sh`
returns zero. Each field must match this apply request, and the checkout HEAD
must still equal the requested revision. Empty common-only hosts are valid;
missing, truncated, foreign-home/platform, wrong-host, or stale-HEAD records
are not successful acknowledgements.

PowerShell uses home-bound `configuration.json` and `request.json` records in
local Git metadata. Its automatic worker verifies the installer acknowledged
the requested host and revision. It never obtains elevation through a login
UAC prompt; use the explicit elevated worker or its registered current-user
task.

Native Windows accepts case variants of `win` at installer/worker boundaries
and canonicalizes them to `win` when saving or dispatching state, including
legacy records. Other host names remain invalid.

Neither updater writes a successful acknowledgement on behalf of the
installer. A failed install, or a zero-exit install which leaves the prior
unapplied state unchanged, remains eligible for retry in a new login session,
even without a new pull. `_DOTFILES_CHECKED` still prevents retry loops inside
the same session. A missing or invalid Unix configuration record cannot
provide a trustworthy remembered host: rerun `stow-all.sh [host-dir]`, or set
`DOTFILES_HOST` explicitly, before automatic installation can resume.

`DOTFILES_AUTO_UPDATE=0` disables the entire hook. `DOTFILES_AUTO_STOW=0` allows
pulls but does not install or acknowledge the new HEAD.
`DOTFILES_HOST` is legacy only: `scripts/dotfiles-update.sh` and `.ps1` read
it, while a native-owned home's `scripts/chezmoi-update.sh`/`.ps1` never does
(its host is `[data].host` in its chezmoi config). An explicitly empty Unix
`DOTFILES_HOST` means common-only installation; other Unix host overlays are
never guessed.

Neither updater runs a submodule command (dotfiles has none) or installs a
payload repo, and no login installs or updates one (a call from an older rc
file or profile to `scripts/payload-update.sh` or `scripts/payload-update.ps1`
does nothing): only a person does, through `sync-payloads` or
`--now`/`-Now`. Those scripts never pull or stow and keep no state; see
[payloads.md](payloads.md).

## Lock scope and remaining boundary

- Unix holds the checkout's metadata-directory lock across fetch, pull,
  installation, and acknowledgement verification.
- PowerShell update and apply workers use the same exclusive file lock. Task
  dispatch hands off to the apply worker, which rechecks its request and
  acquires that lock before changing configuration.
- These locks serialize automatic workers for one checkout. They do not
  serialize different checkouts targeting the same home.
- Direct manual `stow-all.sh` and `stow-all.ps1` invocations do not acquire the
  automatic worker lock. Do not run a manual installer while an automatic
  update/apply is active. Avoid concurrent manual installers as well. Disable
  future login updates when arranging a manual maintenance window; disabling
  the hook does not cancel a worker that is already running.

The acknowledgement check detects incomplete or changed-revision application;
it is not a whole-home transaction or a substitute for cross-installer locks.
Introducing a lock shared by manual and automatic entrypoints needs a separate
reentrant/handoff design, so the worker cannot deadlock its child installer.

## Executable coverage

Status output shares `[dotfiles] [step/ok/warn/error/info]` badges across shells.
`DOTFILES_COLOR=auto` uses terminal detection; `always` forces color and `never`
disables it. Nonempty `NO_COLOR` and `TERM=dumb` always disable color. Redirected
logs remain plain by default. Unix warnings/errors use stderr; PowerShell keeps
host/information-stream capture so the scheduled worker's `*>` log retains them.
Installer warnings retain PowerShell's warning stream and `-WarningAction`
semantics; native warning/error/`WhatIf` rendering follows PowerShell preferences,
not the dotfiles logger's color policy.
Formatting must not alter exit status, updater retry rules or caller preferences.

`tests/update-hooks.sh` checks shell session isolation and injected failure
paths, including malformed or mismatched acknowledgements. It also uses real
temporary Git repositories and local bare remotes for fast-forward updates,
dirty-tree protection, divergent history, failure/no-acknowledgement retry,
and two independent interactive-shell processes contending for one lock.
No real home, live installer, external remote, or credential store is used.

`tests/update-hooks.ps1` exercises the PowerShell worker with temporary Git
repositories and injected installers/elevation/task dispatch. Run it through
`pwsh -NoProfile -NonInteractive -File tests/update-hooks.ps1`. The shell runner
reports an explicit local skip when `pwsh` is unavailable; the Windows CI job
must require the suite. Mocked dispatch and ordinary link tests do not prove
real Task Scheduler execution or OpenSSH network-logon symlink trust.

## Windows worker operations

**On Windows** - on an unmarked (legacy) home, `scripts/dotfiles-update.ps1` runs at the end of `win/powershell/Documents/PowerShell/profile.ps1`, only in an interactive console (not for `-File`/`-Command` scripts, `-NonInteractive` or piped stdin), and skips redirected stdout. A native-owned home runs `scripts/chezmoi-update.ps1` there instead ([takeover.md](chezmoi-migration/takeover.md#updates-and-edits-after-takeover)) and uses no worker: `-Register` and `stow-all.ps1` refuse it. Register the worker once from **elevated PowerShell 7+**, using the same Windows account as your ordinary shell:

```powershell
cd "$HOME\dotfiles"
.\stow-all.ps1 win
.\scripts\dotfiles-auto-stow.ps1 -Register
```

The on-demand task runs as that user with `Interactive` logon and `Highest` privileges, using `pwsh -NoProfile -NonInteractive -WindowStyle Hidden`. It starts the registering pwsh by path, so register from the MSI PowerShell that [HW-clone](bootstrap.md#hw-clone-clone-the-repository) installs: `-Register` refuses a pwsh whose folder is named for its version, such as the MSIX package winget installs by default, and the login hook refuses to start a task whose pwsh is gone. Registration explicitly authorizes the checkout's updated installer scripts to run with administrator privileges. It stores no password, uses the user's home, allows battery operation, and ignores overlapping task starts. Task names include a checkout/user hash. No UAC prompt is launched from the login hook; ordinary shells enqueue work, while elevated shells can apply directly. The interactive task requires that user to be logged on to Windows.

The worker verifies the requested revision, home, host and clean working tree again under the update lock before running `stow-all.ps1 -Strict`. Any installer warning or failed portable sync prevents marking the revision as applied. A queued task is not reported as a completed stow. Inspect its result and last-run log with:

```powershell
. .\scripts\dotfiles-auto-stow.ps1
Get-ScheduledTaskInfo -TaskName (Get-DotfilesTaskName $PWD.Path)
Get-Content (Join-Path (Get-DotfilesStateDirectory $PWD.Path) 'restow.log')
```

Set `DOTFILES_AUTO_STOW=0` before the login hook to stop automatic stow. To remove the registered worker entirely, from elevated PowerShell in the same checkout:

```powershell
. .\scripts\dotfiles-auto-stow.ps1
Unregister-ScheduledTask -TaskName (Get-DotfilesTaskName $PWD.Path)
```
