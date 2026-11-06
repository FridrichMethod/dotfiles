# Cross-platform testing

The `ci.yml` workflow uses three explicit operating-system jobs. It runs on pull
requests, on pushes to `main` and on pushes to `ci/**` branches, so a change can
be checked on all three before `main` is fast-forwarded to it (a pull request
from a `ci/**` branch runs it twice). Tests operate
on temporary repositories and targets; they must not install into the runner's
real user profile. (The opt-in `bootstrap-e2e.yml` workflow, [below](#end-to-end-bootstrap-opt-in),
is the one exception: it installs for real, into fresh containers and the
macOS and Windows runners' homes.)

| Job | Mandatory checks | Provisioning |
| --- | --- | --- |
| `ubuntu-24.04` | `./tests/run.sh --ci --check-prerequisites`, full `pre-commit run --all-files` once (all shell suites plus Node), then the `gitleaks-history` secret scan of every ref | Python 3.11, Node 24, GNU Stow and tmux from apt, verified chezmoi v2.74.0; full-depth checkout; the real coding-agent-kit, installed into a home of its own; pre-commit installs its pinned hooks |
| `macos-15` | `/bin/bash ./tests/run.sh --ci` | Python 3.12, Node 24, GNU Stow, verified chezmoi v2.74.0; the real coding-agent-kit, as on Linux; fzf-tab cloned from its `config/bootstrap/git-clones.tsv` row into the runner's temp directory as `FZF_TAB_TEST_DIR`; retain system Bash and BSD utilities |
| `windows-2025` | `./tests/run.ps1 -CI` in native PowerShell | Python 3.12, Node 24 and verified chezmoi v2.74.0; no coding-agent-kit, which installs nothing on native Windows; Git and PowerShell come from the runner and are checked explicitly |

Each Unix job first installs the real coding-agent-kit of the channel that
`config/payloads.tsv` declares, with the explicit payload command,
`HOME=$RUNNER_TEMP/kit-home sh scripts/payload-update.sh --now kit`. It then
exports that home as `DOTFILES_TEST_KIT_HOME`, which the cases that need an
installed kit read; without it, as in the Windows job (the kit installs
nothing on native Windows), they skip. The network is used in that step
only, never in a test, and a failed install fails the job. To run them
locally, install the kit into a scratch home the same way, with
`XDG_DATA_HOME`, `XDG_STATE_HOME` and `BASH_COMPLETION_USER_DIR` unset so
nothing reaches your own, and set `DOTFILES_TEST_KIT_HOME` to it.

Both gitleaks hooks read `.gitleaks.toml`, which extends the defaults with
any `sk-ant-<kind><nn>` token family and with any file under a `.secrets`
directory or its native source encoding (`dot_secrets/`, also behind the
`remove_`, `external_`, `exact_`, `private_` and `readonly_` attribute
prefixes); only the age ciphertexts
`home/private_dot_secrets/encrypted_private_claude-<name>.age`, with a
`<name>` of lowercase letters and digits, are allowed there.

The Unix entrypoint checks Bash, POSIX sh, Git, Python and Node before starting.
All jobs explicitly run `setup-sync.sh` or `setup-sync.ps1` to provision the
hash-pinned configuration parser. Both entrypoints validate this runtime and
require the shared Python backend tests, including safe replacement failures.
Suites that run neither the parser nor Stow need only a standard-library
Python 3.11+ (`python3`, or `python` under PowerShell) when run directly or
as pre-commit hooks.
In CI mode GNU Stow is required too, so its real symlink fixture cannot silently
skip. On developer machines, `./tests/run.sh` reports a missing optional Stow
integration check, installed-Codex exec-policy check, or PowerShell check.
Codex is not installed merely to test dotfiles; its optional executable-policy
probes supplement the always-run repository rule assertions.

`tests/chezmoi.sh` and `tests/chezmoi.ps1` run the small stdlib native suite.
`DOTFILES_TEST_CHEZMOI` selects an explicit executable path (invalid paths fail);
otherwise it resolves `chezmoi` on PATH before restricting child PATH. Missing
chezmoi skips locally and fails with `DOTFILES_TEST_REQUIRE_CHEZMOI=1` or CI mode.
CI provisions v2.74.0 through `.github/scripts/install-test-chezmoi.py`, verifying
reviewed official SHA256 digests before extracting only the binary. Downloads
never happen inside the suite. Local provisioning should likewise verify the
selected official artifact; no new sync environment is needed for native tests.

These probes isolate source, destination, configuration, cache, state, HOME and
temporary directories and use only synthetic credentials. Native modifies run
without Python, jq or age on child PATH. Parser hooks exclude only the exact
artificial and production modify templates; native tests parse rendered JSON/TOML
instead. Ordinary portable inputs and ownership data remain linted. Unix permission
assertions do not establish Windows ACL behavior; unavailable native platforms
remain explicit missing evidence. The legacy suites still require their existing
TOMLKit runtime until legacy retirement.

Stage 2 adds exact inventory/target-set and byte/mode/convergence checks for
ordinary source, including empty files, binary assets and Windows CRLF. A real
linked Git worktree with spaces proves literal include paths. Native compatible
roles and supplemental OS-data rendering are reported separately. Rendered shell,
Python, JSON, TOML and Lua output is checked by `test_chezmoi_rendered.py`; optional
installed linters report skips. Canonical legacy paths retain their original
lint hooks during coexistence. The native hook also selects encoded `home/`
templates and their legacy inputs, so filename changes do not bypass checks.

Stage 3 adds actual portable Claude/Codex transforms, typed ownership parity,
numeric/Unicode and TOML temporal refusal, CRLF multiline semantics, invalid
input preservation and complete candidate applies. Native compatible-role
counts are 49/56/55/59/54/54/26 in inventory order, with exactly the two AI targets
added to Stage 2. Shared auth/trust/payload siblings stay unmanaged. Local temporal
refusal tests run on every OS; the historical Unix timezone characterization
skip on Windows remains separate from the cross-platform safety assertions.

Stage 5 adds source and state guards. `test_chezmoi_source_state.py` fails on
a `.chezmoiexternal.*` file or `.chezmoiexternals` directory under `home/`
(externals download whenever the source state is read) and on a `.gitmodules`
or a tracked gitlink. `test_chezmoi_update_config.py` requires the template,
and so init, to write `persistentState` as
`<destDir>/.local/state/chezmoi/chezmoi.boltdb` in slash form (Unix and
Windows destinations), to fold its case variants into that key (a config
holding two of them fails init and is left unchanged), and to add only that
key to a config the previous template wrote; a plain command naming only the
config then shares the bound database without a stray
`chezmoistate.boltdb`, while the updater's explicit `--persistent-state`
still wins. `test_chezmoi_provision.py` resolves a native-owned home's role
for the doctor and setup-host from `[data].host`, ignoring `DOTFILES_HOST`,
reads chezmoi init's real rendering of it, and keeps H7-native done on a
bound home with a stray state database.

On native Windows, `test_chezmoi_takeover_windows.py` also pins the login
updater to `~/.local/bin/chezmoi.exe`: a `chezmoi.com` or `chezmoi.cmd`
earlier on PATH or beside it never runs, a valid exe runs with no chezmoi on
PATH, and a missing exe, a foreign owner, a foreign Modify grant, a symlinked
exe or a junction at `.local\bin` or `.local` each print one warning, naming
`docs/bootstrap.md W1-chezmoi` and no SID, and apply nothing. A unit case,
loading only `lib/chezmoi-guard.ps1` (which also loads under Windows
PowerShell 5.1), accepts foreign read and deny entries and OWNER RIGHTS but
not a foreign owner or append right, a null DACL, or an object, compound or
custom ACE (even for you), which .NET's access rules would skip. A fixture
records that NTFS refuses renaming
`.local\bin` and `.local` while the updater's read handle on the exe is open
and allows renaming `.local\bin` after release (observed on the elevated
hosted `windows-2025` runner). That narrows the swap window, not closes it:
a writer of `~/.local` that swaps a junction in before the open and a
prepared directory back before the re-check can still get another
`chezmoi.exe` started, so these tests do not show the path tamper-proof.

The `english-documentation` hook uses native `pygrep`, configured entirely in
`.pre-commit-config.yaml`, to check selected Markdown, reStructuredText,
plain-text documentation and README-style files in this repository. It checks
staged files on commit and tracked files with `--all-files`. Only printable
ASCII, tabs, carriage returns and newlines are allowed; other characters fail
with a file and line. The hook enforces the character set; English wording is
also a documentation policy and review requirement. The payload repos have
their own independent hooks.

Test entrypoints load `tests/lib/environment.sh` or `.ps1` to clear inherited
DOTFILES_, _DOTFILES_, AWESOME_SKILLS_, _AWESOME_SKILLS_, CODING_AGENT_KIT_ and
_CODING_AGENT_KIT_ variables. Deliberate DOTFILES_TEST_* fixture inputs and the
selected DOTFILES_SYNC_PYTHON remain; XDG_STATE_HOME/XDG_DATA_HOME are cleared.
Cases set the production knobs they exercise explicitly. Launchers also keep
caller XDG_CONFIG_HOME out of reach. New upstream variables therefore require
no copied lists and no scan of the installed kit implementation.

A commit hook may export GIT_DIR and GIT_INDEX_FILE, which git -C does not
supersede. Bash fixture-Git entrypoints call the shared helper to clear the
seven repository/index/object-directory overrides; PowerShell fixture helpers
clear GIT_* overrides. Python Git fixtures sanitize their child environments.
`tests/test_environment.py` tests prefix isolation and runs real disposable
linked-worktree Git operations while checking the parent HEAD, index and
core.bare remain unchanged. `tests/test-entrypoints.sh` invokes that focused
fixture instead of rerunning complete manifest, payload or Windows installer
suites just to establish environment isolation.

The entrypoint test also checks pre-commit's files/exclude selection, the
inputs each named hook must run on (among them the sync engine, the payload
scripts and shim, `lib/chezmoi-guard.*`, `lib/bootstrap/platform.sh`,
`checks.sh` and `steps-human.sh` (the H7-native verdict), `doctor.sh` and
`setup-host.sh`), and coverage of the complete shell-suite
list. The e2e-harness and e2e-harness-windows hooks cover harness
unit/fixture tests; these hooks do not run Docker or install into the real
home. Linux CI first checks prerequisites without running behavior tests,
then performs one full pre-commit behavior/lint pass. macOS retains the
complete tests/run.sh --ci pass with system Bash/BSD tools; native Windows
retains tests/run.ps1 -CI.
Local developer hooks remain scoped to changed sources. These are invocation
boundaries, not a measured claim of elapsed-time improvement.

PowerShell is optional in the Unix jobs. When present, the existing shell suite
runs the PowerShell parser, terminal-output, installer confirmation, update behavior and PowerShell profile/prompt-theme contract tests. The Windows job invokes
PowerShell behavior tests directly and fails if any assigned suite fails; it
does not depend on Bash discovering an optional PowerShell executable.

`tests/powershell-profile.sh` first checks the Windows Terminal
`settings.json` with Python alone: strict ASCII JSON, the Windows PowerShell
and Command Prompt built-in stubs listed and hidden, and
`Windows.Terminal.PowershellCore` never disabled. With pwsh it then parses
`doctor.ps1`, `setup-host.ps1`, `lib/chezmoi-guard.ps1`, `lib/terminal.ps1`,
`scripts/chezmoi-update.ps1`, `scripts/payload-update.ps1`, `tests/run.ps1`
and `tests/terminal.ps1` in one process before it runs
`tests/powershell-profile.ps1`. That is the pwsh 7 parser; Windows PowerShell
5.1 syntax still needs the Windows job.

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
Windows PowerShell 5.1 syntax ASCII-only, and requires that the login tail
runs no payload hook. It runs `sync-payloads` and `sync-skills`, lifted into
a child with a fake home: a valid native marker runs its source's hook, never
a stale `DOTFILES_DIR` checkout or its guard; only an unmarked home uses
`DOTFILES_DIR`; six invalid markers, two linked ones (dangling or to a valid
marker, where a symbolic link can be made) and a bound source without its
guard refuse without running a hook; a checkout without the hook fails with
exit 1; maintenance surfaces the real hook's refusal; the hook's exit status
passes through, and one that ends without `exit` reports 0, not the caller's
`$LASTEXITCODE`.
It unit-tests the history filter in both directions, the eza glob expansion
and the `$LASTEXITCODE` prompt wrapper,
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
fzf-tab does, with a fake C client (the `tldr` formula Homebrew removed in
2026-10, still on hosts that installed it, which takes only `-C`) and a fake
tlrc (only `--color always`): both must show the colored page, a
client's missing-page error must never reach the preview, and the C client
must never run without `TLDR_AUTO_UPDATE_DISABLED`, without which the real one
fetches a missing page from GitHub. Last, it runs `sync-payloads kit pymol`
and `sync-skills` from `common/sh/.aliases` in interactive sh, dash, Bash and
`zsh -f` (without the `interactivecomments` oh-my-zsh sets): a valid native
marker runs its source's hook and an unmarked home `DOTFILES_DIR`'s, with the
arguments and exit status passed through, silently and without leaving a
helper variable. `tests/test_chezmoi_guard.py` adds the refusals under sh,
Bash and zsh: a valid marker's source wins over a stale `DOTFILES_DIR`, whose
guard and hook never run; an invalid marker (an unterminated extra line,
another version, a relative source, another home, a symlink, a directory)
refuses before any hook; and maintenance refuses before any state is
written. It also requires that no login through `common/sh/.profile`, with
or without Sherlock's overlay, runs a payload hook, while the update dispatch
stays.

`tests/test_ai_integration.py` evaluates the account preview of
`custom/fzf-tab.zsh` under the context fzf-tab really looks up; with
`FZF_TAB_TEST_DIR` set to an fzf-tab checkout (the bootstrap clones it to
`~/.oh-my-zsh/custom/plugins/fzf-tab`) it also drives real fzf-tab in an
interactive zsh with a fake fzf. Without that variable the second case skips.
CI's macOS job clones fzf-tab from its `config/bootstrap/git-clones.tsv` row
and sets the variable, so both cases run there; the `ubuntu-24.04` runner has
no zsh, so both skip in the Linux job.

The day-zero bootstrap has four suites. `tests/bootstrap-manifest.sh`
unit-tests the sourced `lib/bootstrap/{manifest,platform,version}.sh` and runs
the standard-library validator `tests/test_bootstrap_manifest.py`, which checks
`config/bootstrap/`, the step headings of `docs/bootstrap.md`, the tool table
of `docs/dependencies.md`, the two identical project skills, and that
`STEPS_REGISTRY` and both modes' step lists in `setup-host.ps1` name only
contract step ids, with every id but the `X-` ones in some list.
`tests/doctor.sh` and `tests/setup-host.sh` run the entry points under `env -i`
against fixture checkouts, homes and Homebrew prefixes with stubbed tools and
local clone remotes. Network commands outside `--online` fail the doctor
suite; `sudo`, `chsh`, `stow`, `apt-get`, `conda` and `git lfs` are tripwires in
the installer suite; find snapshots prove that the doctor and
`setup-host.sh --check` write nothing. Every fixture case runs the native
default. The few legacy-only cases pass `--legacy-stow` (`LegacyStow = $true`
in `tests/bootstrap.ps1`) inside blocks fenced by `# >>> stage6-B1` and
`# <<< stage6-B1` lines, or end with a `# stage6-B1` comment, so the Stage 6
commit that drops the legacy mode deletes them by that marker. The doctor binds
its fixture home to the fixture checkout once the unmarked-home resolution
cases have run. The setup-host fixture serves a pinned chezmoi archive whose
executable answers only `--version` (any other command is a tripwire), so
S4-chezmoi installs it and a full apply ends at H7-native. The doctor reads a
bound home's role from the one quoted `host` line of the `[data]` table of its
local config, ignores the Stow receipt and `DOTFILES_HOST` (legacy only), exits
2 for a missing, repeated, unknown or malformed one, treats `common-only` as
common only, names the cause in its `native-config` row (only another
checkout's binding and a stray `chezmoistate.boltdb`, which it leaves in place,
merely warn) and keeps the offline, write-free and no-`TMPDIR` promises. The
setup-host cases list each host's native step order, print HUMAN text that
names no Stow and rerun notes without a mode flag, take `--host` over
`[data].host`, and let an existing login env satisfy H2-alloc with the AI-sync
interpreter as a tripwire; S6-nerd-font counts a Nerd Font in a system font
directory as installed. `tests/doctor.sh`
also runs the real `./doctor.sh` with the real manifest against the test
machine's own tools, in legacy and native mode (`--platform debian` and
`--platform other` with `--tsv`, an empty temporary `HOME`): every line must
keep the TSV contract, the exit code must be 0 or 1, and the home, `TMPDIR`
and checkout must stay unchanged, so a runner whose tools print unexpected
versions or write state on `--version` fails CI. The
checkout scan skips `.git`, where any other git process may write meanwhile;
the fixture cases cover the doctor's own git. An empty home cannot show
writes that depend on state, so fixture fakes model them: gh writes its
device id unless `GH_TELEMETRY=0`, and the tldr C client refreshes a stale
page cache unless `TLDR_AUTO_UPDATE_DISABLED` is set.
`tests/bootstrap-windows.sh` runs `tests/bootstrap.ps1`, the Windows twins
against shims, wherever pwsh exists and prints a `SKIP:` line otherwise; the
Windows job runs that suite and the validator from `tests/run.ps1`. Its cases
run the native default too (legacy-only ones pass `LegacyStow = $true` inside a
`stage6-B1` block) and mirror the Unix ones (a healthy bound host with gh
telemetry off and no writes, the `native-config` causes, a checkout reached
through a junction or symlink counting as the bound one, HUMAN text without
Stow). The healthy fixture puts a chezmoi shim on PATH and, on Windows, gives
the fixture home a private copy of the real chezmoi (`DOTFILES_TEST_CHEZMOI`,
else PATH's) as `~/.local/bin/chezmoi.exe`, so W1-chezmoi is done and an apply
ends at HW-native; a Windows run without a real chezmoi skips those cases (CI
requires one). There a PATH-only chezmoi, a copy other users may modify and a
junctioned `~/.local/bin` each make `native-config` `human` and W1-chezmoi
todo, with no writes. W1-chezmoi stops before downloading under a linked
`.local` or `.local/bin`. Its other
W1-chezmoi case swaps the archive right after the by-path hash check and
requires a sha256 mismatch with nothing installed, then a clean install that
leaves only `chezmoi.exe`, whose DACL on Windows must be protected and grant
exactly the user, SYSTEM and Administrators full control (a `SKIP:`
elsewhere). None of them downloads anything or touches the runner's home.
Fresh-machine runs are
the opt-in [end-to-end suite](#end-to-end-bootstrap-opt-in) below, which checks
the [acceptance checklist](bootstrap.md#acceptance-checklist) for real.

`tests/host-overlays.sh` checks missing, non-executable and fake Linuxbrew
under isolated Bash and zsh. Its standard-library `test_portable_shell.py`
regressions cover HOME paths containing spaces for conda/mamba/micromamba,
failed-hook fallback aliases preserving executable/argument quoting, conditional
vi=nvim, Juliaup idempotence, macOS supported-prefix Homebrew with nvm ordering,
Ubuntu PATH-selected/custom and per-user Linuxbrew, and Marlowe's durable
CARGO_HOME without eager Cargo directory creation. No live rc, installer or
user credentials are used. Sherlock cache placement remains subject to site
rules; these local shell tests do not establish cluster policy.

`tests/tmux.sh` runs `tests/test_tmux.py`. Its static cases match the plugin
rows to Unix installation and probes and require the `tools.tsv` floor 3.4
with no `#{version}` or `tmux -V` gate under `common/tmux`. With a real tmux
on PATH, the `TmuxConfiguration` class sources the config on a private
socket with a temporary `HOME` (one case with a fake TPM). Among other
things it loads offline, registers which-key, Catppuccin and FloaX and sets
the popup and menu styles without conditions, binds FloaX's keys only once
its script exists, and follows the session environment for the clipboard
(an SSH client's session turns extrakto's OSC 52 on and drops tmux-yank; a
session removal of a server-global `SSH_CONNECTION`, the only gate variable
`update-environment` refreshes, gives `bg`, so a server started over SSH,
which keeps `SSH_CLIENT` and `SSH_TTY` global, stays on OSC 52). That class
skips when tmux is absent or older than 3.4 (unsupported), and fails
instead with `DOTFILES_TEST_REQUIRE_TMUX=1`. The Linux job installs apt's
tmux (3.4 on `ubuntu-24.04`) and sets that variable, so the class runs there
and cannot skip unseen inside the pre-commit pass; the macOS job installs
none.

`tests/stow-ignores.sh` (and `tests/run.ps1`) runs `tests/test_stow_ignores.py`:
it builds a name from each `.gitignore` pattern with no slash but a trailing
one, plus
near misses such as `kept-NAME` and `NAME-kept`, asks `git check-ignore`
which of them git ignores, and requires `.stowrc` to agree as Stow 2.3
(split on spaces), Stow 2.4 (split like a shell, dropping a lone backslash)
and `stow-all.ps1` (case-insensitive and unanchored) read it, and the
installed Stow on a real package (2.3.1 in the Linux job, 2.4 in the macOS
one). Stow cannot tell a directory from a file,
so `build/` also hides a file named `build`; the suite therefore also
requires every tracked package file but the four materialized ones to stay
linked.

`tests/stow-all.sh` and `tests/unix-installer.sh` cover retired Sherlock
links, deleted source parents, generated override retirement, foreign entries,
repeat installs and ignored leftover checkouts. The latter uses real GNU Stow
and the real local-remote updater flow. Windows controls and native installer
fixtures cover the two exact retired launcher links, preview and decline
behavior. Native Windows coverage requires the Windows CI job.

The launcher, configuration and Claude helper suites live in
coding-agent-kit, whose CI runs them on its own fixtures.
`tests/ai-integration.sh` runs `tests/test_ai_integration.py`, the
dotfiles-content cases: the fzf-tab account preview, the alias files and the
real `settings.json`, whose configured status line and hook commands must load their required
helpers from `~/.claude/coding-agent-kit/`, each at its configured event. Extra
upstream helper files or private environment variables are outside this
consumer contract and do not fail the integration tests. The cases that run the kit reach it only through its installed
paths, in the home that `DOTFILES_TEST_KIT_HOME` names (launchers in
`.local/bin`, zsh completions in `.local/share/zsh/site-functions`, helpers in
`.claude/coding-agent-kit`), and skip without it: `codex-as` through the alias
files in Bash and zsh, and each command of `settings.json` run through `sh`
in a temporary home with those helpers, which must exit as Claude Code
expects. The command cases fail without `node`. `tests/run.ps1` runs the same
file natively on Windows, where only the wiring cases run, and
`tests/claude-customizations.cjs` runs the commands without a shell there and
on Unix: with `process.platform` forced to `win32` and to Unix values, against
stand-in helpers, a missing helper exits 0 silently only on `win32` and 1
with its path elsewhere, and a present one runs with its exit status kept on
every platform; and on the installed helpers, skipping without them.

The optional real fzf-tab PTY fixture waits for complete expected preview
output, including the account descriptions, before ending the interaction.
Creating the output file alone is not readiness: the fake fzf may buffer it.
Delayed-output cases keep the same preview assertions; no fixed sleep or
longer arbitrary delay stands in for completion evidence.

`tests/ai-policy.sh` (and `tests/run.ps1`) runs `tests/test_ai_policy.py`,
standard library only, against the portable sources: the exact Claude allow
set and the `ask`/`deny` tiers AGENTS.md fixes, `defaultMode` `auto`,
`autoMode.classifyAllShell` and the literal `$defaults`, `effortLevel`, the
cleared plugin hooks, empty attribution, both agents-md plugin IDs and no
portable `model`; prompt-only portable Codex rules without host paths or
routine commands and with every guardrail; global `CLAUDE.md` and `AGENTS.md`
that differ only in the destructive-action bullets and share one version-free
Stanford Sherlock section; and the root `CLAUDE.md` stub. A mutation case per
check proves it rejects its drift. With Codex on PATH it also asks
`codex execpolicy check` for the expected decisions; otherwise those cases
skip.

`tests/payload-update.sh` drives `scripts/payload-update.sh` against fake
installers served from `file://` URLs: the real `config/payloads.tsv` with its
`https://raw.githubusercontent.com/FridrichMethod/` prefix pointed at a local
directory (a URL anywhere else fails the suite) and a curl that refuses every
other URL but a loopback port. Nothing installs unless a person runs it:
sourcing the hook from an interactive Bash, zsh or sh (directly, from a
function as the old login dispatcher did, and through the
`scripts/awesome-skills-update.sh` shim), a call without `--now` and the
retired `--auto` and `--worker` do nothing, print nothing, write no state and
leave the shell's flags, options and traps alone, and a login through
`common/sh/.profile` runs no installer. `--now` installs the default items in
config order, the kit on the declared channel with stdin closed, runs each
installed item's update command the next time, keeps no state of its own and
returns only once its installer has finished. The suite also covers
`DOTFILES_PAYLOAD_ITEMS` (empty selects none, an unknown item fails before
anything runs); a failed install's retry line and exit 1 while the other
items still run; exit 75 as no failure; the person-status rows; a kit path
still linked into the retired Stow package, which stops the kit but not
PyMOL; a stalled download ending within `DOTFILES_PAYLOAD_TIMEOUT` without a
second download; each download staged alone in a fresh private directory of
`TMPDIR` (under its absolute path when `TMPDIR` is relative), removed
afterwards even when its installer fails; every installer, a download or the
kit's installed update, starting in `/`, outside the caller's working
directory, where git finds no planted `TMPDIR/.git` (dotfiles chooses only the
directory an installer starts in; git it runs from elsewhere is its own); a
failed download, the wget fallback and a host with neither; and the
`sync-payloads` and `sync-skills` aliases. `tests/test_payload_download.py`
adds loopback deadlines for curl, wget (behind `timeout` or `gtimeout`;
without either it fails before any request) and PowerShell, and the
failed-download latch, with no staging or state left behind.
`tests/payload-update.ps1` covers the PowerShell twin the same way, with the
items that have a `windows-install` row (PyMOLScripts and awesome-skills): a
call without `-Now`, or with the retired `-Auto` or `-Worker`, does nothing
and says nothing; a run naming the kit says it is not available there and
runs nothing for it; no run records anything; a download's directory is
private (mode 0700; on Windows an access list that grants only this account
and inherits nothing) and one that cannot be made runs nothing; every
installer, a download or an installed script, runs in `$PSHOME`, out of the
caller's working directory and the download's; and fixture-only rows keep the
`windows-update` and `stow-links` fields covered.
`tests/unix-installer.sh` also runs the [migration](payloads.md#migration) of
a host stowed with both submodules through the real login updater, Git and
Stow: the leftover checkouts stay ignored, the restow removes the 16 retired
links, that login installs no payload repo, the next login changes nothing,
and an explicit `--now kit pymol` then installs both. Where the leftovers
stopped the restow (a checkout without those `.gitignore` lines), the explicit
run refuses the kit with the stow-all advice and fails.

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

## End-to-end bootstrap (opt-in)

`tests/e2e/` runs the day-zero bootstrap for real, from a fresh home, on every
host overlay, the way [Running it with an agent](bootstrap.md#running-it-with-an-agent)
drives it natively, and checks the acceptance criteria below. The setup-host
loop runs until the H7-native handover (HW-native on Windows) is the only step
left; `native-handover` then runs the documented
[Fresh home by hand](bootstrap.md#fresh-home-by-hand) procedure
([Fresh Windows home by hand](bootstrap.md#fresh-windows-home-by-hand)),
extracted from the clone's own `docs/bootstrap.md`, in the sandbox home;
`second-apply` must apply nothing, `check-done` (`--check`, `-Check`) must
exit 0 with nothing left, `native-converged` must find an empty
`native_cz diff --exclude=dirs` (`Invoke-NativeCz` on Windows) with every
managed target a regular file, and `native-fixtures` runs `tests/chezmoi.sh`
or `tests/chezmoi.ps1` with the provisioned chezmoi required. The `other`
host has no overlay: it installs chezmoi with the by-hand line of S4-chezmoi
and deploys the `common-only` role by hand (`native_handover common-only`).
It is opt-in: `./tests/run.sh` never runs it (only the fast unit
tests `tests/e2e-harness.sh` and, wherever pwsh exists,
`tests/e2e-harness.ps1`, which drive the harness and its Windows twin against
stubs), and neither does pre-commit. A run installs packages,
clones plugins and builds a login env, so it needs the network and takes from
ten minutes to an hour per host; [tests/e2e/README.md](../tests/e2e/README.md)
is the short how-to.

### Running it

```sh
./tests/e2e/run.sh lab-ubuntu              # one host, one container
./tests/e2e/run.sh -j 2 sherlock marlowe   # at most two containers at a time
./tests/e2e/run.sh all                     # the five Linux hosts, never mac or win
```

`run.sh [-j N] [--cache DIR] [--keep] [--out DIR] [--no-build] <host>... | all`
needs Docker and a clean source checkout (`E2E_ALLOW_DIRTY=1` overrides; the
container still clones `HEAD`, so only uncommitted `tests/e2e/` changes, which
the harness reads from the working tree, are exercised) that is a plain
clone: a linked `git worktree` or submodule checkout is refused with exit 2
(`run from a plain clone`), because the container mounts only the checkout
and such a checkout's `.git` is a file pointing outside it. Run it as a
regular user, never root: the image user is created with your uid so it owns
the mounted `/e2e/out` (and `useradd` refuses uid 0), and `--no-build` reuses
an existing image only after `id -u <user>` in a throwaway container shows
that user has your uid, since images are shared by everyone on the daemon. It
builds the host's image from `tests/e2e/docker/`, mounts the checkout read-only
at `/e2e/src`, runs `tests/e2e/inside.sh` in a fresh container as the host's
user under `bash -l`, and prints a final table `host result seconds out-dir`.
`-j` is capped at 2 (default 1). `--cache DIR` mounts package caches (apt,
dnf4's `/var/cache/dnf` on Rocky, dnf5's `/var/cache/libdnf5` on Fedora 44,
Homebrew, conda packages) from `DIR`, created as you before the run, so a
repeated run downloads less; it is off by default and stays off for
acceptance runs, which must install exactly what a fresh machine installs.
Outputs land under
`tests/e2e/out/<host>-<UTC timestamp>/` (git-ignored): `summary.tsv` (one
tab-separated row per step, `<n> <step> <pass|fail|skip|note> <seconds>
<detail>`), `steps/NN-<step>.log`, `env.txt` (kernel, `/etc/os-release`,
glibc, tool versions, the timeout binary and the expanded
`E2E_SNAPSHOT_PRUNE`), `log/wrappers.log`, `log/sudo.log`, `log/timeline` and
`snapshots/`. `--keep` leaves the container for `docker exec`. `mac` runs only
natively on Darwin with `E2E_NATIVE=1`, and `win` only through
`tests/e2e/run.ps1`; both happen in CI, below.

### Host matrix and fidelity

| Host | Image or runner | User and home | Flow |
| --- | --- | --- | --- |
| `lab-ubuntu` | `ubuntu:24.04` | `fridrichmethod`, `/home/fridrichmethod` | setup-host loop, `--host lab-ubuntu`, then the fresh-home handover |
| `wsl-ubuntu` | `ubuntu:24.04` with `WSL_DISTRO_NAME=Ubuntu` | the same | setup-host loop, `--host wsl-ubuntu`, then the fresh-home handover |
| `other` | `fedora:44` | the same | X-other-linux by hand, `native_handover common-only`, `--platform other` |
| `sherlock` | `rockylinux:9` plus EPEL Lmod, `linux/amd64` | `zyli2002`, `/home/users/zyli2002` | setup-host loop, `--host sherlock`, then the fresh-home handover |
| `marlowe` | `ubuntu:24.04` plus apt `lmod`, `linux/amd64` | `zyli2002`, `/users/zyli2002` | setup-host loop, `--host marlowe`, then the fresh-home handover |
| `mac` | the `macos-15` runner, natively | `runner`, `/Users/runner` | setup-host loop, `--host mac`, then the fresh-home handover |
| `win` | the `windows-2025` runner, natively | the runner user | `run.ps1`: the PowerShell twins, then Fresh Windows home by hand (elevated) |

Each image has only what a fresh install of that kind has (Ubuntu and Fedora:
`git`, `curl`, `sudo` and certificates; the clusters: Lmod, `git`, `curl` and
the OS utilities), never what the bootstrap installs, and a home made by
`useradd -m`, so the `/etc/skel` rc files are there for the handover to keep
copies of. The setup-host loop is `./setup-host.sh --host H --yes` after
`./doctor.sh --tsv` and `--check`, as [Running it with an agent](bootstrap.md#running-it-with-an-agent)
prescribes; the `other` flow installs the distribution packages with `dnf`,
takes `fetch_pinned` and `clone_listed` from the fenced block of
[Downloads and clones by hand](bootstrap.md#downloads-and-clones-by-hand) and
`native_cz` and `native_handover` from the one of
[Fresh home by hand](bootstrap.md#fresh-home-by-hand), both in the clone
itself, then follows the native
[X-other-linux](bootstrap.md#x-other-linux-other-linux-distributions) sequence
to `native_handover common-only`. What is faked, and what is only an
approximation:

- `sudo` and `chsh` are wrappers in `/usr/local/bin` that append every
  call, with the harness phase it ran in, to `log/wrappers.log` and then run
  the real tool; on the cluster images `sudo` is a denying wrapper, since no
  sudo exists there, as on the real clusters. The Ubuntu and Fedora images
  grant passwordless sudo and make it log to `log/sudo.log` through sudoers. A
  Homebrew or conda prefix prepended to PATH can shadow the wrappers; the sudo
  log and the behavioral signals below still cover those calls. On the `mac`
  runner the workflow installs the same two wrappers in `/usr/local/bin`
  with one `sudo install` before the run, refusing a runner that already has
  one of the two names there (nothing is installed there on the arm64 image;
  Homebrew is `/opt/homebrew`): `/etc/profile` and `/etc/zprofile` run
  `path_helper`, which rebuilds PATH from `/etc/paths` and appends the old
  entries afterwards, so `/usr/local/bin` is the one directory it keeps ahead
  of `/usr/bin`, and the login-shell, doctor-final and doctor-smoke steps
  still reach the wrappers (`/etc/paths.d` would not do: its entries land
  after `/etc/paths`). `inside.sh`'s own copy in `$E2E_OUT/bin` is reached
  only outside login shells. With two copies on PATH, each wrapper skips
  every file that is itself an e2e wrapper when it looks for the real tool,
  so a call is logged once and never bounces between the copies. Stow is no
  longer wrapped ([Stage 6](chezmoi-migration/stage-6-retirement.md) decision
  D-11(a)). Until Stage 6's B1 drops it, `core.Brewfile` and the hpc login
  env still install it, so the suite does not claim that nothing installs Stow;
  `audit-clone-links` instead fails any link under HOME that leads into the
  clone, which is what a stray stow would leave.
- `wsl-ubuntu` is detected through `WSL_DISTRO_NAME` and `/mnt/wsl/Ubuntu`,
  not a Microsoft kernel: there is no Windows interop (`wslview`, the Windows
  credential helper) and no `/etc/wsl.conf`.
- `lab-ubuntu` has no desktop session (the `H1-fcitx5` gui block is skipped)
  and a Linuxbrew the user owns, so the shared-prefix `sudo` block of
  S2-brew-bundle never appears; the default tiers leave the desktop steps out.
- `other` approximates "another Linux" as Fedora alone.
- `sherlock` and `marlowe` have Lmod but no site modulefiles and no Slurm:
  `SLURM_JOB_ID=424242` and `CONDA_PKGS_DIRS` are exported once the `H2-alloc`
  block has been printed; `SCRATCH` points at a writable directory in the
  image once it is set: on `sherlock` the fake site profile exports it (with
  the group paths) from the first login shell, on `marlowe` nothing sets it
  before the handover deploys the overlay, as on the real cluster, and the
  overlay then exports
  `/scratch/m000191`, which the image creates writable, so `E2E_ALLOC_ENV`
  names that path literally; the `S2-modules` block (`ml nodejs/24.13.0`, the
  AI CLI modules) is skipped, and there is no Kerberos. The login env is built
  for real, from conda-forge, inside the container.
- `mac` runs on a GitHub runner that already has the Xcode Command Line Tools,
  Homebrew and many formulae, so `H1-xcode-clt` and `H1-homebrew` are found
  done and never exercised, and S2-brew-bundle installs less than on a blank
  Mac. sudo is passwordless there and keeps no log, so only the wrappers
  (installed in `/usr/local/bin` by the workflow, above) and the behavioral
  signals are audited, and the home snapshots prune
  `$HOME/work`, `$HOME/Library`, the runner's own agent directory
  `$HOME/runners` or `$HOME/actions-runner` (hosted `macos-15` runners come
  in both layouts; its `_diag` logs are appended throughout the job, so a
  snapshot that watched it would fail every no-write step), the
  preinstalled `$HOME/hostedtoolcache` and the media folders `$HOME/Movies`,
  `$HOME/Music` and `$HOME/Pictures`, whose libraries Apple's media daemons
  update on their own (a run saw the TV app's library written during the
  second apply); `env.txt` records the expanded list,
  so a reader of the artifact sees what the no-write checks did not watch.
  The runner ships no `timeout` or `gtimeout`, so the per-command limits of
  `tests/e2e/lib/common.sh` (45 minutes per block line, 60 per apply, 15 per
  read-only run) go through `tests/e2e/timeout.pl`, which keeps GNU
  `timeout`'s contract with the runner's perl (a process group of its own,
  TERM then KILL, exit 124); `env.txt` records which one ran. A hang thus
  fails its step with a `summary.tsv` row instead of running into the job's
  90-minute `timeout-minutes`, as the first CI run's did.
- `win` runs every step under the runner's elevated token, because the
  `windows-2025` runner offers no ordinary one: `winget import` leaves each
  installer's scope to that token (`winget.json` pins none), and `oh-my-posh
  font install` puts fonts where an elevated oh-my-posh puts them. Fresh
  Windows home by hand warns when it runs elevated, and the run records a
  `handover-token` note; the ordinary-token check of the login updater stays
  in per-host acceptance. A winget that needs `Repair-WinGetPackageManager`
  first is recorded as a deviation. `run.ps1` asserts criteria 1 (without
  `--smoke`, which `doctor.ps1` does not have), 2, 3, 4, 6, 7 and 8 (the
  doctor, the no-write `-Tsv` and `-Check` runs, a second `-Yes` that applies
  nothing and a `-Check` with nothing left, a clean clone after every step, a
  silent load of the deployed profile, the payload repos, the documented
  handover and an empty native diff), plus `audit-scheduled-tasks` (no task of
  the dotfiles at the end, the task identities unchanged after the apply loop,
  the tasks the loop added listed in a note) and `audit-sync-venv`. There are
  no negatives and no wrapper, sudo or rc audits there, since there are no
  wrappers and no sudo log. The home snapshots note, rather than fail, a
  change under `AppData\LocalLow\Microsoft\CryptnetUrlCache`: Windows'
  per-user CRL and OCSP cache, which every process of the runner account
  writes, the Actions agent's own HTTPS traffic included (the first CI run
  saw an entry appear during `-Check`, whose probes are all local). The same
  holds for `AppData\Local\Microsoft\TokenBroker\Cache`, the Web Account
  Manager's token cache, which Windows' token broker refreshes on its own (a
  run saw a `.tbres` entry change during `-Check`). `snapshots\<step>.diff`
  keeps both as `noted ...`. `pwsh` is absent from the development machines,
  so the Windows driver, and the Fresh Windows home by hand functions it
  runs, are exercised first in CI.

### HUMAN-block policy

The harness plays the agent of [Running it with an agent](bootstrap.md#running-it-with-an-agent)
with the person's approvals scripted, keyed on the block's step id and kind.
`# ` lines are notes; every other line runs as its own command (`bash -c` from
`$HOME`, stdin closed, a 45-minute timeout through coreutils `timeout` or
`gtimeout`, or on the `mac` runner, which has neither, through
`tests/e2e/timeout.pl`) under `E2E_PHASE=human:<id>`.

| Block | Action |
| --- | --- |
| `H1-apt-core`, `H1-locale`, `H1-linuxbrew`, `H1-homebrew` (`sudo`) | every command line, in order |
| `S5-claude` (`inspect`) | only the digest-gate line, `printf '%s  %s\n' <sha256> <path> \| sha256sum -c --status - && bash <path>` |
| `H7-native` (`judgment`) | handover: never run line by line (its lines are notes); once it alone is pending and a run applied nothing, the loop ends and `native-handover` runs the documented procedure under `human:H7-native` |
| `H2-alloc` (`alloc`) | never run: recorded, and the fake allocation variables are exported for the rest of the run |
| `S2-modules`, `H7-payloads`, `H7-doctor` (`judgment`); `H7-auth` (`auth`); `H1-fcitx5` (`gui`); `H7-chsh` (`chsh`) | skipped and recorded as `skip`: non-blocking, and a person's to do |
| `H1-xcode-clt`; any `S2-brew-bundle` block (the conflict judgment or the shared-prefix `sudo`); `S4-nvm`; `X-recovery`; any other id or kind | **fail**, with the block's text in the detail |

A blocking block the harness refuses is a finding, not something to work
around: a fresh machine should never print it. The loop reruns setup-host after
each block, at most eight times. Exit 3 with a block to act on hands it over;
exit 3 with nothing to act on reruns when the run applied a step (a
`<id> done applied:` line) and ends the loop when H7-native alone is pending
and nothing was applied; any other exit 3 fails as "no progress". Exit 0
before the handover fails, since a fresh home cannot have H7-native done, and
exit 1 or 2 fails naming the step.

On `win`, `run.ps1` plays the same agent against `setup-host.ps1 -Host win
-Yes` (again at most eight runs, with the same verdicts and HW-native as the
handover), with the policy of `tests/e2e/lib/blocks.ps1`, keyed on the same
`<id>:<kind>`:

| Block | Action |
| --- | --- |
| `HW-native` (`judgment`) | handover: never run line by line; once it alone is pending and a run applied nothing, the loop ends and `native-handover` runs Fresh Windows home by hand (`Invoke-NativeHandover -Role win` in a child `pwsh -NoProfile -NonInteractive` from the clone) under `human:HW-native` |
| `HW-clone` (any kind) | **fail**: it blocks the flow, and the harness made and checked the clone itself, so a pending HW-clone means setup-host has not accepted it |
| `HW-execution-policy`, `HW-wsl` (`judgment`); `HW-ssh-agent` (`sudo`); `HW-auth` (`auth`) | skipped and recorded as `skip`: non-blocking, and the person's, since the harness neither decides a security setting, installs WSL, starts a service nor signs in |
| any other id or kind, the retired `HW-stow` and `HW-auto-stow-task` included | **fail**, with the block's text in the detail |

The Windows login-shell step then loads the deployed profile in a child `pwsh`
started without `-NoProfile`, which must exit 0 and print nothing, with the
profile a regular file the handover wrote, the payloads step runs
`scripts\payload-update.ps1 -Now` (criterion 7), and
`E2E_SNAPSHOT_PRUNE` is `;`-separated there, since Windows paths hold drive
letters and colons.

### Acceptance criteria

The eight criteria, and how `inside.sh` asserts each; every failure names its
step in `summary.tsv`:

1. **The doctor passes.** From a login environment (`bash -lc 'exec zsh -il
   -c ...'`), `./doctor.sh --host H` exits 0 for the default tiers, then
   `--smoke` exits 0 (`--platform other` on `other`).
2. **The read-only modes write nothing.** Around `./doctor.sh --tsv`,
   `./setup-host.sh --host H --check` and the `--check` after the handover,
   `TMPDIR` is a fresh empty directory that must stay empty with its mtime
   unchanged, and `find "$HOME" -newer <marker>` (pruning `~/dotfiles/.git`)
   must print nothing, with the entry count unchanged.
3. **A second apply is a no-op.** After the handover, `./setup-host.sh --host
   H --yes` exits 0, prints no `<id> done applied:` line, and the home
   snapshot shows nothing newer; `./setup-host.sh --host H --check` then exits
   0 with no `todo` line.
4. **The checkout stays clean.** `git -C ~/dotfiles status --porcelain` is
   empty after every step; a dirty tree fails that step.
5. **Nothing privileged or stateful ran outside a HUMAN block**, by four
   signals: (a) every `log/wrappers.log` line's phase starts with `human:` or
   `negative:`, with no exemption (the `negative:root-refused` sudo is
   legitimate); (b) where sudo logs (`E2E_SUDO=yes`, the Linux images: macOS
   keeps no sudo.log), every `log/sudo.log` timestamp falls inside a
   `human:*` or `negative:*` window of `log/timeline`, and every non-indented
   line of that log is such a timestamped entry, so a log in a shape the
   audit cannot parse fails it instead of passing unread; (c) no link under
   HOME, outside the clone, resolves into the clone (`audit-clone-links`),
   and `~/dotfiles/.venv-sync` never exists after any step
   (`audit-sync-venv`); (d) the login shell from `getent passwd` (`dscl` on
   macOS) is the same at the start and the end, and the sha256 of
   `~/.bashrc`, `~/.profile`, `~/.bash_profile`, `~/.zshrc`, `~/.zshenv` and
   `~/.zprofile` (those that exist) does not change across any non-human
   step; a change during a `human:*` step, the handover's included, is
   recorded as a note.
6. **A login shell starts clean.** Under `env -i` with the system PATH,
   `bash -lc 'exec <zsh> -il -c exit'` (the login env's zsh on hpc) exits 0
   with empty stdout and empty stderr, apart from what is not a message: on
   stdout, terminal control sequences (Fedora's stock `/etc/zlogout` runs
   `clear` when a login shell exits); on stderr, the two lines only the
   missing terminal causes, the `.zshrc`'s `stty -ixon` complaint and fzf's
   `--zsh` integration restoring its saved options
   (`(eval):1: can't change option: zle`), both silent in a real terminal;
   any `[oh-my-zsh]`, `[dotfiles]`, `[awesome-skills]`, `not found`,
   `permission denied` or `[error]` line is reported verbatim.
7. **The payload repos install for real.** After the login-shell check, the
   `payloads` step (`setup:payloads`) runs the H7-payloads run line from the
   login environment, `sh ~/dotfiles/scripts/payload-update.sh --now`
   (`scripts\payload-update.ps1 -Now` on `win`), on every host, whether or
   not its profile prints the H7-payloads block, which stays a skipped
   reminder where it does: coding-agent-kit (not on `win`, where it installs
   nothing), PyMOLScripts and awesome-skills install from GitHub through each
   repo's own installer, the kit at the newest patch of the channel
   `config/payloads.tsv` declares, within the
   45-minute block limit. It must exit 0, and the doctor's `payloads` row
   (`--tsv`) must then be `ok` and name what it found installed. On Unix it
   is a setup phase, so criterion 5 covers it: an installer that runs sudo,
   links into the clone or changes an rc file fails the audits.
8. **The handover is the documented one and converges.** `native-handover`
   runs the clone's Fresh home by hand functions, which must define exactly
   `native_cz` and `native_handover` and nothing else at the top level, and
   `native_handover H` (or `common-only`) must exit 0 and leave the exact
   binding (`dotfiles-chezmoi-v1`, the physical home, the physical clone,
   mode 0600), a regular local config selecting the role, no maintenance
   marker, no stray `~/.config/chezmoi/chezmoistate.boltdb`, a non-empty bound
   state database, a regular `~/.zshrc` and a byte-identical copy of every rc
   file that existed before in `~/.local/state/dotfiles-fresh-backup`. After
   the payloads, `native-converged` requires an empty
   `native_cz diff --exclude=dirs` and every managed target a regular file.

Each host also runs its negative cases as separate steps
(`negative:<token>`): the platform refusals (`--host wsl-ubuntu --check` in
the lab container and the reverse, `env -u LMOD_DIR -u BASH_ENV` on a cluster
(Lmod's profile.d exports `BASH_ENV`, which every bash script sources on start
and which re-exports `LMOD_DIR`), `sudo -n ./setup-host.sh` as root, each exit
2), `alloc-first` (the first hpc apply exits 3 and prints the `H2-alloc`
block) and `common-only` (after the common-only handover, `./doctor.sh` exits
0 and warns common-only, and `./setup-host.sh --check` without `--host` exits
2).

### Harness code rules

Harness variables use the `E2E_` prefix only (`E2E_HOST`, `E2E_REV`,
`E2E_SRC`, `E2E_OUT`, `E2E_PHASE`, `E2E_NATIVE`, `E2E_SANDBOX_HOME`,
`E2E_ALLOW_DIRTY`, `E2E_KEEP`, `E2E_CACHE_DIR` and the keys of
`tests/e2e/hosts/<host>.env`); never a new `DOTFILES_*`, `AWESOME_SKILLS_*` or
`CODING_AGENT_KIT_*` name, which `tests/test-entrypoints.sh` would require
every test entry point to unset. Every `*.sh` under `tests/` and `tests/e2e/` must run under Bash 3.2
(`/bin/bash` on the macOS runner): no associative arrays, `mapfile`, `${x,,}`,
`declare -n`, `|&` or `&>>`. What runs natively on that runner (`inside.sh`,
`tests/e2e/lib/*.sh`, the wrappers) also uses no here-documents or process
substitution and only BSD-safe utilities: no `find -printf`, `stat -c`,
`readlink -f`, `sed -i` without a suffix or `grep -P`; GNU `date -d` appears
only in the sudo.log audit (`e2e_audit_sudo_log` in `tests/e2e/lib/assert.sh`),
behind a probe that turns the audit into a skip row where it is missing
(macOS, which keeps no sudo.log anyway). GitHub's
runners ignore SIGPIPE, as `tests/run.sh` does with `trap '' PIPE`, so under
`set -o pipefail` no pipe may end in an early-exiting reader (`grep -q`,
`head`, a single `read`) while its writer keeps writing: use
`grep ... >/dev/null`, a `sed -n` that reads everything, or a temp file. The
harness never writes inside the clone it tests.

### CI

`.github/workflows/bootstrap-e2e.yml` runs the suite on demand
(`workflow_dispatch` with `hosts`, a comma list or `all`, and `cache`), every
Sunday at 06:00 UTC, and on a push to an `e2e-ci/**` branch; it is not part of
`ci.yml`. A `plan` job turns the host list into the matrix, because a job-level
`if` cannot see the `matrix` context; the five Linux hosts then run in
containers on `ubuntu-24.04` with `fail-fast: false` and 90 minutes each,
`mac` natively on `macos-15` (`E2E_NATIVE=1 ./tests/e2e/run.sh mac`) and `win`
on `windows-2025` (`./tests/e2e/run.ps1`), the only places those two run;
`tests/run.ps1` parses `tests/e2e/run.ps1` and `tests/e2e/lib/*.ps1` on every
run and then runs `tests/e2e-harness.ps1`, which drives them against stubs
(also from `tests/run.sh` through `tests/e2e-harness-windows.sh`), so the three
`ci.yml` jobs catch a syntax error or a policy regression there before this
workflow does; winget and the real bootstrap run only here. Each
job uploads `tests/e2e/out/**` as the artifact `bootstrap-e2e-<host>`, pass or
fail; one run per ref at a time, without cancelling one in progress. The
`cache` input mounts a scratch directory under the runner's temp, which no
later run sees, so it only saves downloads within one job; acceptance runs
leave it off.

### Real clusters

Sherlock and Marlowe cannot run the containers (no Docker on a login node, and
`E2E_NATIVE` is honoured only on macOS), so the owner runs the native bootstrap
by hand once per cluster, on a fresh account home, and checks the criteria
above the same way. Log in without the RemoteCommand (`ssh sherlock-plain`,
`ssh marlowe-plain`), paste `native_cz` and `native_handover` from
[Fresh home by hand](bootstrap.md#fresh-home-by-hand) into the shell, then:

```sh
uname -a; cat /etc/os-release; ldd --version | head -n 1   # record these with the run
git clone https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles && export DOTFILES_AUTO_UPDATE=0 DOTFILES_PAYLOAD_AUTO_UPDATE=0
./doctor.sh --host sherlock --tsv                           # or marlowe; exit 1 is expected now
marker=$(mktemp) && sleep 1
./setup-host.sh --host sherlock --check                     # exit 3
find "$HOME" -path "$HOME/dotfiles/.git" -prune -o -newer "$marker" -print   # must print nothing
./setup-host.sh --host sherlock                             # light steps; exit 3 at H2-alloc
sh_dev -t 1:00:00                                           # Marlowe: srun --time=1:00:00 --pty bash -l
cd ~/dotfiles && export DOTFILES_AUTO_UPDATE=0 DOTFILES_PAYLOAD_AUTO_UPDATE=0
echo "$SCRATCH"                                             # Sherlock: the site sets it; Marlowe: empty before the handover
export CONDA_PKGS_DIRS="$SCRATCH/.cache/conda/pkgs"         # Sherlock
# Marlowe: export CONDA_PKGS_DIRS="/scratch/m000191/.cache/conda/pkgs/$USER"   # the overlay's value; no site SCRATCH yet
./setup-host.sh --host sherlock                             # builds the login env; exit 3 with only H7-native left
exit                                                        # back to the login node
cd ~/dotfiles && native_handover sherlock                   # H7-native: Fresh home by hand
./setup-host.sh --host sherlock                             # exits 0 and prints no "done applied:" line
git -C ~/dotfiles status --porcelain                        # empty, here and after every step above
exec "$HOME/micromamba/envs/login/bin/zsh" -l               # starts without an error line
sh ~/dotfiles/scripts/payload-update.sh --now               # H7-payloads (criterion 7; no login runs it): exits 0
cd ~/dotfiles && native_cz diff --exclude=dirs              # paste the functions again in this shell; prints nothing
./doctor.sh --host sherlock && ./doctor.sh --host sherlock --smoke
```

Nothing but the HUMAN blocks and the handover changed the home when
`~/.config/dotfiles/native` and the deployed regular files (`~/.zshrc`
among them) appear only after the `native_handover` line, the backup
directory `~/.local/state/dotfiles-fresh-backup` holds the earlier rc files
byte for byte, and `getent passwd "$USER"` still names the same login shell
at the end. Then fill
the run's row of the [acceptance table](bootstrap.md#acceptance-checklist):
the date, the OS and glibc from the first line, the result and any notes,
adding a row for Marlowe.
