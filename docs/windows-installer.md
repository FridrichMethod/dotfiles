# Windows installer integration

`stow-all.ps1` remains the native installer and runs the shared POSIX sync
wrappers through Git Bash, never WSL's `system32\bash.exe`. Run
`setup-sync.ps1` explicitly once to provision the isolated parser runtime.
Installation and automatic update do not download dependencies.

The installer first validates the requested host (`win` or empty), target,
selected AI helpers and inputs, and ignore expressions. All three helpers
must succeed with `--check` before any is invoked in apply mode. Missing
runtime/helper/input and malformed configuration fail even without `-Strict`.
This is preflight plus safe per-file replacement, not a multi-file transaction:
an I/O error during application can still leave a partial installation, which
must not advance applied state and can be retried.

The default target remains the actual Windows user profile. An explicit
absolute non-root `-TargetRoot` supports disposable installations:

```powershell
./stow-all.ps1 win -TargetRoot 'C:\temporary\dotfiles test home' -Strict
./stow-all.ps1 '' -TargetRoot 'C:\temporary\dotfiles test home' -WhatIf
```

A target other than the actual profile never writes the login updater's
configuration/applied revision and does not compare its profile location with
the operator's actual PowerShell profile. `-WhatIf` still validates dependencies
and inputs but creates no target directories, live files, links, backups or
applied-state metadata. `-Strict` also rejects missing package warnings before
application; warnings during linking prevent acknowledgement as before.

`tests/windows-installer.ps1` requires native Windows, Git for Windows, the
provisioned parser runtime and an elevated PowerShell process. It copies a
minimal tracked fixture into temporary paths containing spaces, invokes the
real installer in child processes, and checks actual links and regular files.
The fixture covers common/host ordering, ignore sources, Windows allowlisting,
no-folding materialization, identical-file adoption, collision-resistant
backups, stale and legacy links, no-op sync, dry-run, invalid final input,
missing dependencies and strict failure. All fixture targets are separate from
the real user profile and all fixture trees are removed after the test.
Adoption is byte-identical or strictly decoded UTF-8 differing only by CRLF;
case-only differences and invalid UTF-8 conflicts are backed up, not discarded.

Unix checks in `tests/windows-installer.sh` preserve the source-level trust
guardrails and parse both PowerShell files when `pwsh` is installed. They are
supplemental, not native execution coverage.

Hosted Windows integration does **not** establish the OpenSSH network-logon
token's symlink-trust behavior or real Task Scheduler registration/execution.
Those require a separately scoped Windows environment check. The existing
PowerShell updater suite covers state/task-dispatch contracts with mocks; no
integration fixture modifies the actual user's task registrations or dotfiles.
