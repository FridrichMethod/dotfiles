# Cross-platform testing

The CI workflow uses three explicit operating-system jobs. Tests operate on
temporary repositories and targets; they must not install into the runner's
real user profile.

| Job | Mandatory checks | Provisioning |
| --- | --- | --- |
| `ubuntu-24.04` | `./tests/run.sh --ci`, full `pre-commit run --all-files` | Python 3.11, Node 24, GNU Stow; pre-commit installs its pinned hooks |
| `macos-15` | `/bin/bash ./tests/run.sh --ci` | Python 3.12, Node 24, GNU Stow; retain system Bash and BSD utilities |
| `windows-2025` | `./tests/run.ps1 -CI` in native PowerShell | Python 3.12 and Node 24; Git and PowerShell come from the runner and are checked explicitly |

The Unix entrypoint checks Bash, POSIX sh, Git, Python and Node before starting.
All jobs explicitly run `setup-sync.sh` or `setup-sync.ps1` to provision the
hash-pinned configuration parser. Both entrypoints validate this runtime and
require the shared Python backend tests, including safe replacement failures.
In CI mode GNU Stow is required too, so its real symlink fixture cannot silently
skip. On developer machines, `./tests/run.sh` reports a missing optional Stow
integration check, installed-Codex exec-policy check, or PowerShell check.
Codex is not installed merely to test dotfiles; its optional executable-policy
probes supplement the always-run repository rule assertions.

Every Unix test entry point (`tests/*.sh`) starts by unsetting the dotfiles
knobs, and `tests/run.ps1` removes the same list: `DOTFILES_AUTO_UPDATE`,
`DOTFILES_AUTO_STOW`, `DOTFILES_HOST`, `DOTFILES_DIR`, `DOTFILES_COLOR`,
`DOTFILES_STOW_WITHOUT_OH_MY_ZSH`, the `AWESOME_SKILLS_*` controls and both
session markers. The bootstrap playbook tells people to export
`DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0` while provisioning, and a
test or `pre-commit run` started from such a shell must behave as in CI; each
case sets the knobs it exercises. `tests/test-entrypoints.sh` checks that every
entry point carries the same list, that it covers every `DOTFILES_*` and
`AWESOME_SKILLS_*` name in a tracked file outside `tests/`, `docs/`,
`.github/` and Markdown, whatever reads it (shell, PowerShell or Python;
`DOTFILES_SYNC_PYTHON` excepted, since `tests/run.sh` provisions it), and that
a suite passes under those exports.

PowerShell is optional in the Unix jobs. When present, the existing shell suite
runs the PowerShell parser, terminal-output, installer confirmation, update behavior and PowerShell profile/prompt-theme contract tests. The Windows job invokes
PowerShell behavior tests directly and fails if any assigned suite fails; it
does not depend on Bash discovering an optional PowerShell executable.

`tests/terminal.sh` exercises actual Unix pseudo-terminals as well as redirected
stdout/stderr, including forced color, `NO_COLOR`, `TERM=dumb`, literal percent
signs and silent sourcing. `tests/terminal.ps1` covers the matching PowerShell
policy, pipeline/stream behavior and preference isolation. When pwsh is present,
the Unix terminal suite also runs it on a real PTY to cover same-console `*>`
redirection, even with PowerShell's ANSI rendering preference. Installers are tested
with quiet helpers; errors and failed-install retries must remain observable.

`tests/powershell-profile.ps1` checks the tracked PowerShell profiles and the
oh-my-posh theme without loading the live profile. It walks the AST to pin the
exact interactive guard and keep setup in its then-branch, checks agent-session
parity against `common/zsh/.zshrc`, keeps the conda stub lazy (removed before
the hook runs) and identical in both profiles, installs out of the profile and
Windows PowerShell 5.1 syntax ASCII-only. It unit-tests the history filter in
both directions, the eza glob expansion and the `$LASTEXITCODE` prompt wrapper,
parses and completes conda under Windows PowerShell 5.1, dot-sources the
PowerShell 7 profile in a redirected child with a fake home and a 60 s timeout,
and renders the primary, transient and secondary prompts with any inherited
oh-my-posh session removed and a temporary cache, failing on rendered template
errors (unknown segment types are not detectable in oh-my-posh 31.6).

`tests/shell-profile.sh` also resolves nvm's `default` alias forms against a
fake `NVM_DIR` under sh, dash, Bash and Zsh (including bash `failglob`), checks
that `custom/nvm.zsh` loads nvm with `--no-use`, and runs `common/zsh/.zshrc`
three levels deep with a fake `brew shellenv` and conda prepends: PATH, FPATH
and INFOPATH stay identical, nvm stays ahead in a fresh shell, a parent's order
(activated env or brew first) is kept, a conda-style activate and deactivate
keeps an entry already on PATH, and nothing assigns PATH after oh-my-zsh.
It also evaluates the fzf-tab tldr previews of `custom/fzf-tab.zsh`, as
fzf-tab does, with a fake C client (Homebrew's `tldr`, which takes only `-C`)
and a fake tlrc (only `--color always`): both must show the colored page, a
client's missing-page error must never reach the preview, and the C client
must never run without `TLDR_AUTO_UPDATE_DISABLED`, without which the real one
fetches a missing page from GitHub.

The day-zero bootstrap has four suites. `tests/bootstrap-manifest.sh`
unit-tests the sourced `lib/bootstrap/{manifest,platform,version}.sh` and runs
the standard-library validator `tests/test_bootstrap_manifest.py`, which checks
`config/bootstrap/`, the step headings of `docs/bootstrap.md`, the tool table
of `docs/dependencies.md` and the two identical project skills.
`tests/doctor.sh` and `tests/setup-host.sh` run the entry points under `env -i`
against fixture checkouts, homes and Homebrew prefixes with stubbed tools and
local clone remotes. Network commands outside `--online` fail the doctor
suite; `sudo`, `chsh`, `stow`, `apt-get`, `conda` and `git lfs` are tripwires in
the installer suite; find snapshots prove that the doctor and
`setup-host.sh --check` write nothing. `tests/doctor.sh` also runs the real
`./doctor.sh` with the real manifest against the test machine's own tools
(`--platform debian` and `--platform other` with `--tsv`, an empty temporary
`HOME`): every line must keep the TSV contract, the exit code must be 0 or 1,
and the home, `TMPDIR` and checkout must stay unchanged, so a runner whose
tools print unexpected versions or write state on `--version` fails CI. The
checkout scan skips `.git`, where any other git process may write meanwhile;
the fixture cases cover the doctor's own git. An empty home cannot show
writes that depend on state, so fixture fakes model them: gh writes its
device id unless `GH_TELEMETRY=0`, and the tldr C client refreshes a stale
page cache unless `TLDR_AUTO_UPDATE_DISABLED` is set.
`tests/bootstrap-windows.sh` runs `tests/bootstrap.ps1`, the Windows twins
against shims, wherever pwsh exists and prints a `SKIP:` line otherwise; the
Windows job runs that suite and the validator from `tests/run.ps1`. None of
them downloads anything or touches the runner's home. Fresh-machine runs are
the [acceptance checklist](bootstrap.md#acceptance-checklist), not CI.

`tests/host-overlays.sh` sources the `wsl-ubuntu` and `lab-ubuntu` zsh and bash
overlays in a clean environment with a missing, a non-executable and a fake
Linuxbrew, so a shell started before Linuxbrew exists stays silent and the
`brew shellenv` line applies only once brew can run.

Run either entrypoint from any working directory. To check prerequisites only:

```sh
./tests/run.sh --ci --check-prerequisites
```

```powershell
pwsh -NoProfile -NonInteractive -File ./tests/run.ps1 -CI -CheckPrerequisites
```

`tests/run.ps1` without `-CI` also runs portable PowerShell behavior tests on
Linux/macOS, including actual confirmation prompts with a scripted host. It starts child processes with `-NoProfile`, isolating test mocks
and avoiding live profile side effects. The `-CI` switch requires native
Windows so an accidentally misplaced job cannot masquerade as native coverage.

Unix jobs also run `tests/unix-installer.sh`: a temporary checkout and local
bare remote exercise actual Git pull, actual Stow and applied-state recording.
The Windows entrypoint runs `tests/windows-installer.ps1` on native Windows,
using a disposable target for actual Git Bash helpers and NTFS links. POSIX
permission/inode assertions stay on Unix; NTFS/link behavior stays on Windows.

Ordinary hosted-runner tests do not establish OpenSSH network-logon symlink
trust or real Task Scheduler behavior; those remain explicitly scoped
environment checks, documented in `windows-installer.md` and
`update-contract.md`.
