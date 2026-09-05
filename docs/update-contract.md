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

Neither updater writes a successful acknowledgement on behalf of the
installer. A failed install, or a zero-exit install which leaves the prior
unapplied state unchanged, remains eligible for retry in a new login session,
even without a new pull. `_DOTFILES_CHECKED` still prevents retry loops inside
the same session. A missing or invalid Unix configuration record cannot
provide a trustworthy remembered host: rerun `stow-all.sh [host-dir]`, or set
`DOTFILES_HOST` explicitly, before automatic installation can resume.

`DOTFILES_AUTO_UPDATE=0` disables the entire hook. `DOTFILES_AUTO_STOW=0` allows
pulls and submodule updates but does not install or acknowledge the new HEAD.
An explicitly empty Unix `DOTFILES_HOST` means common-only installation;
other Unix host overlays are never guessed.

## Lock scope and remaining boundary

- Unix holds the checkout's metadata-directory lock across fetch, pull,
  submodule synchronization, installation, and acknowledgement verification.
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
