# Cross-platform testing

The CI workflow uses three explicit operating-system jobs. Tests operate on
temporary repositories and targets; they must not install into the runner's
real user profile.

| Job | Mandatory checks | Provisioning |
| --- | --- | --- |
| `ubuntu-24.04` | `./tests/run.sh --ci`, full `pre-commit run --all-files` | Python 3.12, Node 24, GNU Stow and jq; pre-commit installs its pinned hooks |
| `macos-15` | `/bin/bash ./tests/run.sh --ci` | Python 3.12, Node 24, GNU Stow and jq; retain system Bash and BSD utilities |
| `windows-2025` | `./tests/run.ps1 -CI` in native PowerShell | Python 3.12 and Node 24; Git and PowerShell come from the runner and are checked explicitly |

The Unix entrypoint checks Bash, POSIX sh, Git, Python and Node before starting.
In CI mode GNU Stow is required too, so its real symlink fixture cannot silently
skip. On developer machines, `./tests/run.sh` reports a missing optional Stow
integration check, installed-Codex exec-policy check, or PowerShell check.
Codex is not installed merely to test dotfiles; its optional executable-policy
probes supplement the always-run repository rule assertions.

PowerShell is optional in the Unix jobs. When present, the existing shell suite
runs the PowerShell parser and update behavior tests. The Windows job invokes
PowerShell behavior tests directly and fails if any assigned suite fails; it
does not depend on Bash discovering an optional PowerShell executable.

Run either entrypoint from any working directory. To check prerequisites only:

```sh
./tests/run.sh --ci --check-prerequisites
```

```powershell
pwsh -NoProfile -NonInteractive -File ./tests/run.ps1 -CI -CheckPrerequisites
```

`tests/run.ps1` without `-CI` also runs portable PowerShell behavior tests on
Linux/macOS. It starts child processes with `-NoProfile`, isolating test mocks
and avoiding live profile side effects. The `-CI` switch requires native
Windows so an accidentally misplaced job cannot masquerade as native coverage.

The shared configuration-backend suite and native Windows installer fixture
are added to these mandatory entrypoints in the installer-integration node of
the [execution plan](plans/sync-hardening.md). Ordinary hosted-runner tests do
not establish OpenSSH network-logon symlink trust or real Task Scheduler
behavior; those remain explicitly scoped environment checks.
