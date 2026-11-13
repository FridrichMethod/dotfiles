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
| `ubuntu-24.04` | `./tests/run.sh --ci --check-prerequisites`, full `pre-commit run --all-files` once (all shell suites plus Node), then the `gitleaks-history` secret scan of every ref | Python 3.11, Node 24, tmux from apt, verified chezmoi v2.74.0; full-depth checkout; the real coding-agent-kit, installed into a home of its own; pre-commit installs its pinned hooks |
| `macos-15` | `/bin/bash ./tests/run.sh --ci` | Python 3.12, Node 24, verified chezmoi v2.74.0; the real coding-agent-kit, as on Linux; fzf-tab cloned from its `config/bootstrap/git-clones.tsv` row into the runner's temp directory as `FZF_TAB_TEST_DIR`; retain system Bash and BSD utilities |
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
directory or its chezmoi source encoding (`dot_secrets/`, also behind the
`remove_`, `external_`, `exact_`, `private_` and `readonly_` attribute
prefixes); only the age ciphertexts
`home/private_dot_secrets/encrypted_private_claude-<name>.age`, with a
`<name>` of lowercase letters and digits, are allowed there.

The Unix entrypoint checks Bash, POSIX sh, Git, Python 3.11+ and Node before
starting, and the PowerShell entrypoint Git, Node and Python 3.11+; a python3
below the floor is a named prerequisite failure. The AI config transforms run
inside chezmoi, so no other parser is provisioned.
On developer machines, `./tests/run.sh` reports a missing optional
installed-Codex exec-policy check, or PowerShell check.
Codex is not installed merely to test dotfiles; its optional executable-policy
probes supplement the always-run repository rule assertions.

`tests/chezmoi.sh` and `tests/chezmoi.ps1` run the small stdlib chezmoi suite.
`DOTFILES_TEST_CHEZMOI` selects an explicit executable path (invalid paths fail);
otherwise it resolves `chezmoi` on PATH before restricting child PATH. Missing
chezmoi skips locally and fails with `DOTFILES_TEST_REQUIRE_CHEZMOI=1` or CI mode.
CI provisions v2.74.0 through `.github/scripts/install-test-chezmoi.py`, verifying
reviewed official SHA256 digests before extracting only the binary. Downloads
never happen inside the suite. Local provisioning should likewise verify the
selected official artifact.

These probes isolate source, destination, configuration, cache, state, HOME and
temporary directories and use only synthetic credentials. The modify templates
run without Python, jq or age on child PATH; the complete apply puts failing
python3, python, jq, node, sh, bash and pwsh stand-ins there and requires that
none runs. Parser hooks exclude only the exact artificial and production modify templates; the chezmoi tests parse rendered JSON/TOML
instead. Ordinary portable inputs and ownership data remain linted. Unix permission
assertions do not establish Windows ACL behavior; unavailable native platforms
remain explicit missing evidence.

The source is materialized under `home/`. `test_chezmoi_source_state.py` checks
every role's exact target set, bytes, modes and convergence against
`tests/fixtures/chezmoi/targets.tsv` (empty files, binary assets and Windows
CRLF included), that only the six role-keyed templates remain and none reads the
working tree, and, in a real linked worktree with spaces, that source-relative
includes of `home/.hosts/` and `home/.policy/` return exact bytes while no
dot-directory becomes a target. Compatible roles and supplemental OS-data
rendering are reported separately. Rendered shell, Python, JSON, TOML and Lua
output is checked by `test_chezmoi_rendered.py`, with the shell dialect taken
from the table; optional installed linters report skips. `test-entrypoints.sh`
requires shellcheck and shfmt to select every shell source the table names, each
variant with `types: [file]`, since identify gives `dot_` names no shell tag.

The AI suites cover actual portable Claude/Codex transforms, typed
ownership parity, numeric/Unicode and TOML temporal refusal, CRLF multiline
semantics, invalid input preservation and complete candidate applies.
Compatible-role counts are 50/57/56/59/55/55/27 in role order, with exactly the
two AI targets added to the ordinary files. Shared auth/trust/payload siblings
stay unmanaged. Local temporal refusal tests run on every OS; the Unix
timezone characterization, which skips on Windows, stays separate from the
cross-platform safety assertions.

Source and state guards: `test_chezmoi_source_state.py` fails on a
`.chezmoiexternal.*` file or `.chezmoiexternals` directory under `home/`
(externals download whenever the source state is read) and on a `.gitmodules` or
a tracked gitlink, and requires that the checkout's own `.gitignore` (not a
personal exclude: `core.excludesFile` is disabled and the match must come from
`.gitignore`) hides Claude Code's machine-local `.claude/settings.local.json`
at the root while `.claude/settings.json` stays tracked (the login updater
refuses an untracked file).
`test_chezmoi_update_config.py` requires the template, and so
init, to write `persistentState` as
`<destDir>/.local/state/chezmoi/chezmoi.boltdb` in slash form (Unix and Windows
destinations) and to fold its case variants into that key (a config holding two
of them fails init and is left unchanged); a plain command naming only the
config then uses that database, while the updater's explicit
`--persistent-state` still wins.
`test_chezmoi_provision.py` resolves a configured home's role for the doctor
and setup-host from `[data].host` alone, reads chezmoi init's real rendering of
it (also from a seed with a case variant of `sourceDir` and `mode = "symlink"`),
requires that `lib/chezmoi-guard.sh` accepts that rendering, and reports
H7-deploy done on a home whose config names this checkout and pending on one
whose config names another.

On native Windows, `test_chezmoi_update_windows.py` also pins the login
updater to `~/.local/bin/chezmoi.exe`: a `chezmoi.com` or `chezmoi.cmd`
earlier on PATH or beside it never runs, a valid exe runs with no chezmoi on
PATH, and a missing exe, a foreign owner, a foreign Modify grant, a symlinked
exe or a junction at `.local\bin` or `.local` each print one warning, naming
`docs/bootstrap.md W1-chezmoi` and no SID, and apply nothing. Its config
cases hold `Get-DotfilesChezmoiPaths` to the form chezmoi init writes there
(`C:/...` values, compared ignoring case and slash direction, a source with
`.git` and `.chezmoiroot`): under Windows PowerShell 5.1 and PowerShell 7 it
accepts the real init output and refuses CRLF, and under PowerShell 7 every
other form refuses (a missing or second line, a case variant, a `workingTree`
key, a quoted key, an escape or backslash, a drive-relative, rooted or UNC
`sourceDir`, a junction path, no `.git`, another home, a directory or dangling
link); the PowerShell 7 profile tail runs only the configured checkout's
updater and warns once for a config the guard refuses. A unit case,
loading only `lib/chezmoi-guard.ps1` (which also loads under Windows
PowerShell 5.1), accepts foreign read and deny entries and OWNER RIGHTS but
not a foreign owner or append right, a null DACL, or an object, compound or
custom ACE (even for you), which .NET's access rules would skip. A fixture,
run on the elevated hosted `windows-2025` runner of `ci.yml`, checks that
NTFS refuses renaming `.local\bin` and `.local` while the updater's read
handle on the exe is open and allows renaming `.local\bin` after release.
That narrows the swap window, not closes it: a writer of `~/.local` that
swaps a junction in before the open and a prepared directory back before the
re-check can still get another `chezmoi.exe` started, so these tests do not
show the path tamper-proof.

The portable PowerShell 7 culture cases in the same file start a fresh process
for each of `en-US`, `tr-TR` and `az-Latn-AZ`. They check all 256 ASCII
OneDrive case spellings, substring matches and near misses before a backend
can run. A real child process proves that every tested case variant of the
`GIT_` and `CHEZMOI_` prefixes is removed while similarly named variables
remain. These cases do not require Windows ACLs; native Windows trust tests
remain separate.

The `english-documentation` hook uses pre-commit's `pygrep` language, configured entirely in
`.pre-commit-config.yaml`, to check selected Markdown, reStructuredText,
plain-text documentation and README-style files in this repository. It checks
staged files on commit and tracked files with `--all-files`. Only printable
ASCII, tabs, carriage returns and newlines are allowed; other characters fail
with a file and line. The hook enforces the character set; English wording is
also a documentation policy and review requirement. The payload repos have
their own independent hooks.

`tests/markdown-links.sh` runs `tests/test_markdown_links.py` on every commit
(its hook has `always_run`, since any deletion or rename can break a link):
every relative link in tracked Markdown resolves to a tracked file or directory
and every `#anchor` matches a GitHub heading slug.

Test entrypoints load `tests/lib/environment.sh` or `.ps1` to clear inherited
DOTFILES_, _DOTFILES_, AWESOME_SKILLS_, _AWESOME_SKILLS_, CODING_AGENT_KIT_ and
_CODING_AGENT_KIT_ variables. Deliberate DOTFILES_TEST_* fixture inputs remain;
XDG_STATE_HOME/XDG_DATA_HOME are cleared.
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
fixture instead of rerunning complete manifest, payload or Windows bootstrap
suites just to establish environment isolation.

The entrypoint test also checks pre-commit's files/exclude selection, the inputs
each named hook must run on (among them the payload scripts,
`lib/chezmoi-guard.*`, `lib/bootstrap/platform.sh`, `checks.sh` and
`steps-human.sh` (the H7-deploy verdict), `doctor.sh` and `setup-host.sh`; the
markdown-links hook runs on every path), and coverage of the complete
shell-suite list. The e2e-harness and e2e-harness-windows hooks cover harness
unit/fixture tests; these hooks do not run Docker or install into the real home.
Linux CI first checks prerequisites without running behavior tests, then
performs one full pre-commit behavior/lint pass. macOS retains the complete
tests/run.sh --ci pass with system Bash/BSD tools; native Windows retains
tests/run.ps1 -CI. Local developer hooks remain scoped to changed sources. These
are invocation boundaries, not a measured claim of elapsed-time improvement.

PowerShell is optional in the Unix jobs. When present, the existing shell suite
runs the PowerShell parser, terminal-output and PowerShell profile/prompt-theme contract tests. The Windows job invokes
PowerShell behavior tests directly and fails if any assigned suite fails; it
does not depend on Bash discovering an optional PowerShell executable.

`tests/cli.sh` runs the Unix CLI suite with temporary homes and fake backends,
checking help without backend probes, strict options, forwarding, exit codes,
explicit checkout paths and installed config-bound routing. It also runs
`tests/cli.ps1` when PowerShell 7 is present; `tests/run.ps1` selects that suite
directly on native Windows. The Windows suite uses real PowerShell processes
for GNU-style option adaptation, streams, stale status, discovery and caller
state isolation. Local skips are not native Windows evidence; final CI must
pass on Windows for the exact candidate.

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
redirection, even with PowerShell's ANSI rendering preference. doctor.ps1 and
setup-host.ps1 keep a plain fallback when lib/terminal.ps1 is missing or broken.

`tests/powershell-profile.ps1` checks the tracked PowerShell profiles and the
oh-my-posh theme without loading the live profile. It walks the AST to pin the
exact interactive guard and keep setup in its then-branch, checks agent-session
parity against `home/dot_zshrc`, keeps the conda stub lazy (removed before
the hook runs) and identical in both profiles, installs out of the profile and
Windows PowerShell 5.1 syntax ASCII-only, and requires that the login tail
runs no payload hook and reads no environment variable. It runs
`sync-payloads` and `sync-skills`, lifted into a child with a fake home: a
valid `~/.config/chezmoi/chezmoi.toml` runs the hook of the checkout it names,
never the checkout at `~\dotfiles` or its guard; a home without a config
refuses with the `-Now` line to run instead; seven invalid configs (a second
`sourceDir`, a literal string, CRLF, a relative `sourceDir`, another home, a
`workingTree` key, a directory), two linked ones (dangling or to a valid
config, where a symbolic link can be made) and a configured checkout without
its guard refuse without running a hook; a configured checkout without the
hook fails with exit 1; maintenance surfaces the real hook's refusal; the hook's exit
status passes through, and one that ends without `exit` reports 0, not the
caller's `$LASTEXITCODE`.
It holds the PowerShell 7.0 floor: every `$PSStyle` use (7.2+) sits in the
then-branch of one interactive if whose condition is
`Get-Variable -Name PSStyle -ValueOnly -ErrorAction Ignore`; that statement
runs cleanly, plainly and in strict mode, in a runspace whose initial state
lacks `$PSStyle` (where the bare assignment must fail), and where pwsh has
`$PSStyle` it colors directories bold blue. Every prediction option
(`-PredictionSource`, `-PredictionViewStyle` and the prediction colors) sits
likewise behind one if that requires PSReadLine 2.2 and PowerShell 7.2.
Replayed against stand-ins for PSReadLine 2.0 to 2.3 on PowerShell 7.0 to
7.4 (stock 7.0 to 7.2 ship PSReadLine 2.0 or 2.1), the profile's PSReadLine
statements set the other options everywhere without an error and the
predictions only where both versions allow them. `tests/powershell-profile.sh`
scans both profiles for the same guards before it hands over to pwsh, so the
rule holds where pwsh is missing too.
It unit-tests the history filter in both directions in fresh processes under
`en-US`, `tr-TR` and `az-Latn-AZ`, preserving case-sensitive vendor patterns,
benign prefix/length boundaries and ordinary commands. All credential-shaped
inputs are synthetic. Separate processes matter because PowerShell's `-match`
regex cache can otherwise reuse a pattern compiled under another culture.
It also tests the eza glob expansion
and the `$LASTEXITCODE` prompt wrapper,
parses and completes conda under Windows PowerShell 5.1, dot-sources the
PowerShell 7 profile in a redirected child with a fake home and a 60 s timeout,
and renders the primary, transient and secondary prompts with any inherited
oh-my-posh session removed and a temporary cache, failing on rendered template
errors (unknown segment types are not detectable in oh-my-posh 31.6).

The updater culture tests and `tests/powershell-profile.ps1` can also be run
by hand under the ordinary token on the existing Windows home
([Ordinary-token candidate checks](hosts.md#ordinary-token-candidate-checks));
nothing runs them there automatically.

These fixtures do not show predictions rendered in an ordinary user's real
console or prove that console's normal profile update hook. The separate
[PowerShell 7 console acceptance](hosts.md#powershell-7-console-acceptance)
covers both on the existing Windows home: a one-off Interactive-logon,
Limited-token task launches a new `pwsh -NoLogo -NoExit` console whose child
must be unelevated with neither stdin nor stdout redirected, and the created
console's history and Completion plugin suggestions in ListView, directory
style and startup/update result are checked there. That host evidence is
separate from both the fixtures and
[fresh-machine acceptance](bootstrap.md#acceptance-checklist).

`tests/shell-profile.sh` also resolves nvm's `default` alias forms against a
fake `NVM_DIR` under sh, dash, Bash and Zsh (including bash `failglob`), checks
that `custom/nvm.zsh` loads nvm with `--no-use`, and runs `home/dot_zshrc`
three levels deep with a fake `brew shellenv` and conda prepends: PATH, FPATH
and INFOPATH stay identical, nvm stays ahead in a fresh shell, a parent's order
(activated env or brew first) is kept, a conda-style activate and deactivate
keeps an entry already on PATH, and nothing assigns PATH after oh-my-zsh.
It also evaluates the fzf-tab tldr previews of `custom/fzf-tab.zsh`, as
fzf-tab does, with a fake C client (tldr-c-client, which takes only `-C`;
its `tldr` keg stays on a host that installed it) and a fake
tlrc (only `--color always`): both must show the colored page, a
client's missing-page error must never reach the preview, and the C client
must never run without `TLDR_AUTO_UPDATE_DISABLED`, without which the real one
fetches a missing page from GitHub. It then runs `sync-payloads kit pymol`
and `sync-skills` from `home/dot_aliases` in interactive sh, dash, Bash and
`zsh -f` (without the `interactivecomments` oh-my-zsh sets): a valid chezmoi
config runs the hook of the checkout it names, never the checkout at
`~/dotfiles`, with the arguments and exit status passed through, silently and
without leaving a helper variable, while a home without a config and an
invalid config run no hook and say so. It also requires that an interactive
login under sh, dash, Bash and zsh runs no updater and prints nothing in a
home without a config, even with a checkout at ~/dotfiles, warns once and
runs nothing for an invalid config, and runs only the configured checkout's
updater for a valid one, without leaving a helper variable.
`tests/test_chezmoi_guard.py` checks `dotfiles_chezmoi_source` under sh, Bash
and zsh: the layout chezmoi init writes (also without a final newline, with
keys after the first table and an indented header) prints the canonical
`sourceDir`, and every other form refuses silently and writes nothing: no
config, a link, a dangling link, a directory, a missing or second `sourceDir`
or `destDir`, either only inside a table, a case variant, a `workingTree` key,
a quoted key, leading blanks, other spacing, a literal string, an escape, a
quote or control character, a trailing comment, CRLF, a multi-line string, an
empty, relative, linked, trailing-slash or dot-segment `sourceDir`, one
without `.chezmoiroot`, another or a linked `destDir` and a byte-order mark;
`HOME=/` never probes the UNC-like `//.config`, and sourcing defines only the
three guard functions. It adds the `sync-payloads` refusals under sh, Bash
and zsh: a valid config's checkout wins over the checkout at `~/dotfiles`,
whose guard and hook never run; a home without a config and an invalid config
(another home, a relative `sourceDir`, a second `sourceDir`, CRLF, a checkout
without its guard, a symlink, a directory) refuse before any hook; and
maintenance refuses before any state is written. It also requires that no
login through `home/dot_profile`, with or without Sherlock's overlay, runs a
payload hook, while a configured home's update dispatch stays; a text check
keeps PowerShell 7-only syntax and an unguarded `$IsWindows` out of
`lib/chezmoi-guard.ps1`; and, wherever pwsh exists (and under Windows
PowerShell 5.1 on Windows), `Get-DotfilesChezmoiPaths` run under en-US, tr-TR
and az-Latn-AZ accepts the init layout and refuses `SOURCEDIR`, `sourceDIR`,
`DESTDIR` and `WORKINGTREE`.

`tests/test_ai_integration.py` evaluates the account preview of
`custom/fzf-tab.zsh` under the context fzf-tab really looks up; with
`FZF_TAB_TEST_DIR` set to an fzf-tab checkout (the bootstrap clones it to
`~/.oh-my-zsh/custom/plugins/fzf-tab`) it also drives real fzf-tab in an
interactive zsh with a fake fzf. Without that variable the second case skips.
CI's macOS job clones fzf-tab from its `config/bootstrap/git-clones.tsv` row
and sets the variable, so both cases run there; the `ubuntu-24.04` runner has
no zsh, so both skip in the Linux job.

The day-zero bootstrap has four suites. `tests/bootstrap-manifest.sh` unit-tests
the sourced `lib/bootstrap/{manifest,platform,version}.sh` and runs the
standard-library validator `tests/test_bootstrap_manifest.py`, which checks
`config/bootstrap/`, the step headings of `docs/bootstrap.md`, the tool table of
`docs/dependencies.md`, the two identical project skills, and that
`STEPS_REGISTRY` and the step lists in `setup-host.ps1` name only contract step
ids, with every id but the `X-` ones in some list. `tests/doctor.sh` and
`tests/setup-host.sh` run the entry points under `env -i` against fixture
checkouts, homes and Homebrew prefixes with stubbed tools and local clone
remotes. Network commands outside `--online` fail the doctor suite; `sudo`,
`chsh`, `apt-get`, `conda` and `git lfs` are tripwires in the installer suite;
find snapshots prove that the doctor and `setup-host.sh --check` write nothing.
The doctor writes its
fixture home's chezmoi config for the fixture checkout once the cases without
a config have run. The
setup-host fixture serves a pinned chezmoi archive whose executable answers only
`--version` (any other command is a tripwire), so S4-chezmoi installs it and a
full apply ends at H7-deploy. The doctor reads a configured home's role from
the one quoted `host` line of the `[data]` table of its local config, also
when the guard refuses the config, exits 2 for a missing, repeated, unknown or
malformed one and for a home without a config and without `--host` or
`--platform`, treats `generic` as no host overlay, names the cause in its
`chezmoi-config` row (absent, a link, a directory, each invalid form, an
unreadable guard; only a config naming another checkout merely warns), gives
the shell-quoted `--now` line wherever `sync-payloads` would refuse, and keeps
the offline, write-free and no-`TMPDIR` promises. The setup-host cases
refuse an unknown argument, check each host's exact step order, take `--host` over
`[data].host`, and let an existing login env satisfy H2-alloc; S6-nerd-font
counts a Nerd Font in a system font directory as installed. `tests/doctor.sh`
also runs the real `./doctor.sh` with the real manifest against the test
machine's own tools (`--platform debian` and `--platform other` with `--tsv`, an
empty temporary `HOME`): every line must keep the TSV contract, the exit code
must be 0 or 1, and the home, `TMPDIR` and checkout must stay unchanged, so a
runner whose tools print unexpected versions or write state on `--version` fails
CI. The checkout scan skips `.git`, where any other git process may write
meanwhile; the fixture cases cover the doctor's own git. An empty home cannot
show writes that depend on state, so fixture fakes model them: gh writes its
device id unless `GH_TELEMETRY=0`, and the tldr C client refreshes a stale page
cache unless `TLDR_AUTO_UPDATE_DISABLED` is set. `tests/bootstrap-windows.sh`
runs `tests/bootstrap.ps1`, the Windows twins against shims, wherever pwsh
exists and prints a `SKIP:` line otherwise; the Windows job runs that suite and
the validator from `tests/run.ps1`. Its cases mirror
the Unix ones (a healthy configured host with gh telemetry off and no writes,
the `chezmoi-config` causes, the quoted `-Now` payload advice wherever
`sync-payloads` refuses, also from a checkout whose path holds a typographic
apostrophe, a checkout reached through a junction or symlink counting as the
configured one). The healthy fixture puts a chezmoi shim on PATH and,
on Windows, gives the fixture home a private copy of the real chezmoi
(`DOTFILES_TEST_CHEZMOI`, else PATH's) as `~/.local/bin/chezmoi.exe`, so
W1-chezmoi is done and an apply ends at HW-deploy; a Windows run without a real
chezmoi skips those cases (CI requires one). There a PATH-only chezmoi, a copy
other users may modify and a junctioned `~/.local/bin` each make `chezmoi-config`
`human` and W1-chezmoi todo, with no writes. W1-chezmoi stops before downloading
under a linked `.local` or `.local/bin`. Its other W1-chezmoi case swaps the
archive right after the by-path hash check and requires a sha256 mismatch with
nothing installed, then a clean install that leaves only `chezmoi.exe`, whose
DACL on Windows must be protected and grant exactly the user, SYSTEM and
Administrators full control (a `SKIP:` elsewhere). None of them downloads
anything or touches the runner's home. Real installer runs use the opt-in
[end-to-end suite](#end-to-end-bootstrap-opt-in) below, which checks the
[automated acceptance criteria](#acceptance-criteria) in containers and hosted
runners. Neither these fixtures, the end-to-end suite, hosted CI nor
existing-host checks substitute for the genuine fresh-machine runs of the
[acceptance checklist](bootstrap.md#acceptance-checklist).

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
with no `#{version}` or `tmux -V` gate in `home/dot_tmux.conf` or
`home/dot_config/tmux/`, and that their file map names every tmux source.
The menu regression first verifies its actual physical working directory,
then checks all three new-window/split actions with quotes, spaces, shell
metacharacters and literal tmux formats in the path. Menu actions defer the
path format to native `-c`, so the path is neither parsed as command text nor
expanded twice. The six-case regression runs in Linux CI with tmux 3.4; the
macOS job installs no tmux, and the regression's real-mac tmux 3.8 coverage
is in [hosts](hosts.md#known-limits).
With a real tmux on PATH, the `TmuxConfiguration` class sources the config on
a private socket with a temporary `HOME` (one case with a fake TPM). Among other
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
stand-in helpers, a command runs no helper on `win32` and exits 0 silently
there, present or not, while elsewhere a missing helper exits 1 with its path
and a present one runs with its exit status kept; and on the installed
helpers, skipping without them.

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
other URL but a loopback port. Every field of `config/payloads.tsv` is one
the hooks read. Nothing installs unless a person runs it: a call without
`--now` first (none, a bare item or an unknown argument, under maintenance
too) prints one usage line on stderr and exits 2; none writes state, and a
login through `home/dot_profile` runs no installer. `--now` installs the
default items in config order, the kit on the declared channel with stdin
closed, runs each installed item's update command the next time, keeps no
state of its own and returns only once its installer has finished. The suite
also covers `DOTFILES_PAYLOAD_ITEMS` (empty selects none, an unknown item
fails before anything runs); a failed install's retry line and exit 1 while
the other items still run; exit 75 as no failure; the person-status rows; a
stalled download ending within `DOTFILES_PAYLOAD_TIMEOUT` without a second
download; each download staged alone in a fresh private directory of
`TMPDIR` (under its absolute path when `TMPDIR` is relative), removed
afterwards even when its installer fails; every installer, a download or the
kit's installed update, starting in `/`, outside the caller's working
directory, where git finds no planted `TMPDIR/.git` (dotfiles chooses only the
directory an installer starts in; git it runs from elsewhere is its own); a
failed download, the wget fallback and a host with neither; and the
`sync-payloads` and `sync-skills` aliases through the fixture's chezmoi
config; and the retry lines, which name `sync-payloads` only where the
config names this checkout and the hook's own quoted `--now` line elsewhere. `tests/test_payload_download.py`
adds loopback deadlines for curl, wget (behind `timeout` or `gtimeout`;
without either it fails before any request) and PowerShell, and the
failed-download latch, with no staging or state left behind. The fixture
completes a direct HTTP readiness exchange before starting a downloader's
deadline; a delayed-server regression keeps fixture startup outside the
one-second download budget. Body deadlines and failed-download assertions
remain unchanged.
`tests/payload-update.ps1` covers the PowerShell twin the same way, with the
items that have a `windows-install` row (PyMOLScripts and awesome-skills): a
call without `-Now` (none, a bare item or an unknown argument) prints one
usage line and exits 2, under maintenance too; a run naming
the kit says it is not available there and runs nothing for it; the retry
line still parses as one command when the checkout's path holds a
typographic apostrophe; no run records anything; a download's directory is private (mode 0700; on Windows an
access list that grants only this account and inherits nothing) and one that
cannot be made runs nothing; every
installer, a download or an installed script, runs in `$PSHOME`, out of the
caller's working directory and the download's; and a fixture-only row keeps
the `windows-update` field covered.

Run either entrypoint from any working directory. To check prerequisites only:

```sh
./dotfiles dev test --ci --check-prerequisites
```

```powershell
.\dotfiles.ps1 dev test --ci --check-prerequisites
```

`tests/run.ps1` without `-CI` also runs portable PowerShell behavior tests on
Linux/macOS. It starts child processes with `-NoProfile`, isolating test mocks
and avoiding live profile side effects. The `-CI` switch requires native
Windows so an accidentally misplaced job cannot masquerade as native coverage.

Native Windows ACL, reparse-point and held-handle checks run only in the Windows job.

## End-to-end bootstrap (opt-in)

`tests/e2e/` runs the day-zero bootstrap for real, from a fresh home, on every
host overlay, the way [Running it with an agent](bootstrap.md#running-it-with-an-agent)
drives it natively, and checks the acceptance criteria below. The setup-host
loop runs until H7-deploy (HW-deploy on Windows) is the only step
left; `home-deploy` then runs the documented
[Fresh home by hand](bootstrap.md#fresh-home-by-hand) procedure
([Fresh Windows home by hand](bootstrap.md#fresh-windows-home-by-hand)),
extracted from the clone's own `docs/bootstrap.md`, in the sandbox home;
`second-apply` must apply nothing, `check-done` (`--check`, `-Check`) must
exit 0 with nothing left, `home-converged` must find an empty
`home_cz diff --exclude=dirs` (`Invoke-HomeCz` on Windows) with every
managed target a regular file, and `chezmoi-fixtures` runs `tests/chezmoi.sh`
or `tests/chezmoi.ps1` with the provisioned chezmoi required. The `other`
host has no overlay: it installs chezmoi with the by-hand line of S4-chezmoi
and deploys the `generic` role by hand (`home_deploy generic`).
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
| `lab-ubuntu` | `ubuntu:24.04` | `fridrichmethod`, `/home/fridrichmethod` | setup-host loop, `--host lab-ubuntu`, then the fresh-home deployment |
| `wsl-ubuntu` | `ubuntu:24.04` with `WSL_DISTRO_NAME=Ubuntu` | the same | setup-host loop, `--host wsl-ubuntu`, then the fresh-home deployment |
| `other` | `fedora:44` | the same | X-other-linux by hand, `home_deploy generic`, `--platform other` |
| `sherlock` | `rockylinux:9` plus EPEL Lmod, `linux/amd64` | `zyli2002`, `/home/users/zyli2002` | setup-host loop, `--host sherlock`, then the fresh-home deployment |
| `marlowe` | `ubuntu:24.04` plus apt `lmod`, `linux/amd64` | `zyli2002`, `/users/zyli2002` | setup-host loop, `--host marlowe`, then the fresh-home deployment |
| `mac` | the `macos-15` runner, natively | `runner`, `/Users/runner` | setup-host loop, `--host mac`, then the fresh-home deployment |
| `win` | the `windows-2025` runner, natively | the runner user | `run.ps1`: the PowerShell twins, then Fresh Windows home by hand (elevated) |

Each image has only what a fresh install of that kind has (Ubuntu and Fedora:
`git`, `curl`, `sudo` and certificates; the clusters: Lmod, `git`, `curl` and
the OS utilities), never what the bootstrap installs, and a home made by
`useradd -m`, so the `/etc/skel` rc files are there for the deployment to keep
copies of. The setup-host loop is `./dotfiles setup --host H --yes` after
`./dotfiles doctor --tsv` and `--check`, as [Running it with an agent](bootstrap.md#running-it-with-an-agent)
prescribes; the `other` flow installs the distribution packages with `dnf`,
takes `fetch_pinned` and `clone_listed` from the fenced block of
[Downloads and clones by hand](bootstrap.md#downloads-and-clones-by-hand) and
`home_cz` and `home_deploy` from the one of
[Fresh home by hand](bootstrap.md#fresh-home-by-hand), both in the clone
itself, then follows the
[X-other-linux](bootstrap.md#x-other-linux-other-linux-distributions) sequence
to `home_deploy generic`. What is faked, and what is only an
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
  so a call is logged once and never bounces between the copies.
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
  before the deployment installs the overlay, as on the real cluster, and the
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
  update on their own (the TV app's library can be written during the
  second apply); `env.txt` records the expanded list,
  so a reader of the artifact sees what the no-write checks did not watch.
  The runner ships no `timeout` or `gtimeout`, so the per-command limits of
  `tests/e2e/lib/common.sh` (45 minutes per block line, 60 per apply, 15 per
  read-only run) go through `tests/e2e/timeout.pl`, which keeps GNU
  `timeout`'s contract with the runner's perl (a process group of its own,
  TERM then KILL, exit 124); `env.txt` records which one ran. A hang thus
  fails its step with a `summary.tsv` row instead of running into the job's
  90-minute `timeout-minutes`.
- `win` runs every step under the default runner account's elevated token:
  `winget import` leaves each
  installer's scope to that token (`winget.json` pins none), and `oh-my-posh
  font install` puts fonts where an elevated oh-my-posh puts them. Fresh
  Windows home by hand warns when it runs elevated, and the run records a
  `deploy-token` note; the ordinary-token check of the login updater stays
  in per-host acceptance, including the separate
  [real-console procedure](hosts.md#powershell-7-console-acceptance) for the
  normal profile hook and rendered predictions. On disposable hosted Windows
  only, the harness pauses the current user's OMP App Installer updates for
  two hours. Preparation runs before the first doctor when OMP is already
  installed and again after canonical setup; absence is a no-op, and the
  doctor retains its verdict. It refuses system policy or an existing pause,
  records ownership before the setter, and preserves the installed package,
  executable hash and other settings. The driver's `finally` explicitly
  resumes updates and verifies those fields; an independent `always()` step
  retries restoration after interruption. No account, service, UAC or
  signature policy is changed. The pause relaxes none of the doctor's
  checks: its 900-second limit and failure conditions stay, and it runs the
  real packaged executable and alias.

  This qualification rests on a paired hosted control run with OMP 31.9.1:
  the package and alias launch promptly while updates are paused, but after
  updates resume, package activation waits in App Installer's
  update-interaction path, so a one-time launch preparation is insufficient.
  Hosted E2E therefore does not cover unattended App Installer update
  scheduling: a green hosted run does not establish unattended activation
  with default, unpaused Windows Server App Installer settings. A winget
  that needs `Repair-WinGetPackageManager` first is recorded as a deviation.
  `run.ps1` asserts criteria 1 (without
  `--smoke`, which `doctor.ps1` does not have), 2, 3, 4, 6, 7 and 8 (the
  doctor, the no-write `-Tsv` and `-Check` runs, a second `-Yes` that applies
  nothing and a `-Check` with nothing left, a clean clone after every step, a
  silent load of the deployed profile, the payload repos, the documented
  deployment and an empty diff), plus `audit-scheduled-tasks` (the task
  identities unchanged after the apply loop, the tasks the loop added listed in
  a note). There are no negatives and no wrapper, sudo or rc audits there, since
  there are no wrappers and no sudo log. The home snapshots note, rather than
  fail, a change under `AppData\LocalLow\Microsoft\CryptnetUrlCache`: Windows'
  per-user CRL and OCSP cache, which every process of the runner account
  writes, the Actions agent's own HTTPS traffic included, so an entry can
  appear even during `-Check`, whose probes are all local. The same holds for
  `AppData\Local\Microsoft\TokenBroker\Cache`, the Web Account Manager's
  token cache, which Windows' token broker refreshes on its own (a `.tbres`
  entry can change during `-Check`). `snapshots\<step>.diff`
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
| `H7-deploy` (`judgment`) | deploy: never run line by line (its lines are notes); once it alone is pending and a run applied nothing, the loop ends and `home-deploy` runs the documented procedure under `human:H7-deploy` |
| `H2-alloc` (`alloc`) | never run: recorded, and the fake allocation variables are exported for the rest of the run |
| `S2-modules`, `H7-payloads`, `H7-doctor` (`judgment`); `H7-auth` (`auth`); `H1-fcitx5` (`gui`); `H7-chsh` (`chsh`) | skipped and recorded as `skip`: non-blocking, and a person's to do |
| `H1-xcode-clt`; any `S2-brew-bundle` block (the conflict judgment or the shared-prefix `sudo`); `S4-nvm`; `X-recovery`; any other id or kind | **fail**, with the block's text in the detail |

A blocking block the harness refuses is a finding, not something to work
around: a fresh machine should never print it. The loop reruns setup-host after
each block, at most eight times. Exit 3 with a block to act on hands it over;
exit 3 with nothing to act on reruns when the run applied a step (a
`<id> done applied:` line) and ends the loop when H7-deploy alone is pending
and nothing was applied; any other exit 3 fails as "no progress". Exit 0
before the deployment fails, since a fresh home cannot have H7-deploy done, and
exit 1 or 2 fails naming the step.

On `win`, `run.ps1` plays the same agent against `dotfiles.ps1 setup --host win
--yes` (again at most eight runs, with the same verdicts and HW-deploy as the
deployment), with the policy of `tests/e2e/lib/blocks.ps1`, keyed on the same
`<id>:<kind>`:

| Block | Action |
| --- | --- |
| `HW-deploy` (`judgment`) | deploy: never run line by line; once it alone is pending and a run applied nothing, the loop ends and `home-deploy` runs Fresh Windows home by hand (`Invoke-HomeDeploy -Role win` in a child `pwsh -NoProfile -NonInteractive` from the clone) under `human:HW-deploy` |
| `HW-clone` (any kind) | **fail**: it blocks the flow, and the harness made and checked the clone itself, so a pending HW-clone means setup-host has not accepted it |
| `HW-execution-policy`, `HW-wsl` (`judgment`); `HW-ssh-agent` (`sudo`); `HW-auth` (`auth`) | skipped and recorded as `skip`: non-blocking, and the person's, since the harness neither decides a security setting, installs WSL, starts a service nor signs in |
| any other id or kind | **fail**, with the block's text in the detail |

After deployment, Unix doctor and payload steps invoke the installed launcher
from the home directory outside the checkout. The fixture deploys the real
launcher as an executable regular file and verifies its bytes and convergence.
Windows payload installation uses the explicit installed script path from home;
the final doctor uses bare `dotfiles` in a fresh `pwsh -NoProfile` child with
home-local bin in a controlled process PATH. Tests never persist User PATH.
Legacy backend refusal/compatibility tests remain in the negative paths.

The Windows login-shell step then loads the deployed profile in a child `pwsh`
started without `-NoProfile`, which must exit 0 and print nothing, with the
profile a regular file the deployment wrote, the payloads step runs
`& "$HOME/.local/bin/dotfiles.ps1" payloads sync` (criterion 7), and
`E2E_SNAPSHOT_PRUNE` is `;`-separated there, since Windows paths hold drive
letters and colons.

### Acceptance criteria

The eight criteria, and how `inside.sh` asserts each; every failure names its
step in `summary.tsv`:

1. **The doctor passes.** From a login environment (`bash -lc 'exec zsh -il
   -c ...'`), `"$HOME/.local/bin/dotfiles" doctor --host H` exits 0 for the default tiers, then
   `--smoke` exits 0 (`--platform other` on `other`).
2. **The read-only modes write nothing.** Around `./dotfiles doctor --tsv`,
   `./dotfiles setup --host H --check` and the `--check` after the deployment,
   `TMPDIR` is a fresh empty directory that must stay empty with its mtime
   unchanged, and `find "$HOME" -newer <marker>` (pruning `~/dotfiles/.git`)
   must print nothing, with the entry count unchanged.
3. **A second apply is a no-op.** After the deployment, `./dotfiles setup --host
   H --yes` exits 0, prints no `<id> done applied:` line, and the home
   snapshot shows nothing newer; `./dotfiles setup --host H --check` then exits
   0 with no `todo` line.
4. **The checkout stays clean.** `git -C ~/dotfiles status --porcelain` is
   empty after every step; a dirty tree fails that step.
5. **Nothing privileged or stateful ran outside a HUMAN block**, by four
   signals: (a) every `log/wrappers.log` line's phase starts with `human:` or
   `negative:` (the `negative:root-refused` sudo is legitimate); (b) where sudo
   logs (`E2E_SUDO=yes`, the Linux images: macOS keeps no sudo.log), every
   `log/sudo.log` timestamp falls inside a `human:*` or `negative:*` window of
   `log/timeline`, and every non-indented line of that log is such a
   timestamped entry, so a log in a shape the audit cannot parse fails it
   instead of passing unread; (c) no link under HOME, outside the clone,
   resolves into the clone (`audit-clone-links`); (d) the login shell from
   `getent passwd` (`dscl` on macOS) is the same at the start and the end, and
   the sha256 of `~/.bashrc`, `~/.profile`, `~/.bash_profile`, `~/.zshrc`,
   `~/.zshenv` and `~/.zprofile` (those that exist) does not change across any
   non-human step; a change during a `human:*` step, the deployment's included,
   is recorded as a note.
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
   `payloads` step (`setup:payloads`) uses the public CLI from the
   login environment, `"$HOME/.local/bin/dotfiles" payloads sync`
   (`& "$HOME/.local/bin/dotfiles.ps1" payloads sync` on `win`), on every host, whether or
   not its profile prints the H7-payloads block, which stays a skipped
   reminder where it does: coding-agent-kit (not on `win`, where it installs
   nothing), PyMOLScripts and awesome-skills install from GitHub through each
   repo's own installer, the kit at the newest patch of the channel
   `config/payloads.tsv` declares, within the
   45-minute block limit. It must exit 0, and the doctor's `payloads` row
   (`--tsv`) must then be `ok` and name what it found installed. On Windows,
   both the installer and doctor must exit 0 before an `ok` payloads row
   naming installed items can pass; doctor failures report their own exit
   code and the existing 900-second check limit. On Unix it
   is a setup phase, so criterion 5 covers it: an installer that runs sudo,
   links into the clone or changes an rc file fails the audits.
8. **The deployment is the documented one and converges.** `home-deploy`
   runs the clone's Fresh home by hand functions, which must define exactly
   `home_cz` and `home_deploy` and nothing else at the top level, and
   `home_deploy H` (or `generic`) must exit 0 and leave a regular
   local config that the clone's guard accepts as naming the physical home and
   the physical clone and that selects the role, no maintenance marker,
   a non-empty state database, a regular `~/.zshrc` and a byte-identical
   copy of every rc file that existed before in
   `~/.local/state/dotfiles-fresh-backup`. After the payloads,
   `home-converged` requires an empty `home_cz diff --exclude=dirs` and
   every managed target a regular file.

Each host also runs its negative cases as separate steps
(`negative:<token>`): the platform refusals (`--host wsl-ubuntu --check` in
the lab container and the reverse, `env -u LMOD_DIR -u BASH_ENV` on a cluster
(Lmod's profile.d exports `BASH_ENV`, which every bash script sources on start
and which re-exports `LMOD_DIR`), `sudo -n ./setup-host.sh` as root, each exit
2), `alloc-first` (the first hpc apply exits 3 and prints the `H2-alloc`
block) and `generic` (after the generic deployment, `./doctor.sh` exits
0 and warns generic, and `./setup-host.sh --check` without `--host` exits
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
Windows retains a 90-minute run limit inside a 95-minute job, reserving time
for the independent three-minute App Installer restoration and upload.
Each policy worker has a 45-second execution limit; the existing process
wrapper can additionally spend 30 seconds terminating and 30 draining it.
Restoration invokes one such worker, within the independent cleanup budget.
`tests/run.ps1` parses the E2E entry scripts and `tests/e2e/lib/*.ps1` on every
run and then runs `tests/e2e-harness.ps1`, which drives them against stubs
(also from `tests/run.sh` through `tests/e2e-harness-windows.sh`), so the three
`ci.yml` jobs catch a syntax error or a policy regression there before this
workflow does. The App Installer policy worker is also parsed by native
Windows PowerShell 5.1. Fixtures cover both preparation checkpoints,
foreign-policy refusal, ownership persisted before a partial setter failure,
idempotent restoration, retained doctor exit 124, restoration drift and
the real driver's `finally` block after an escaped exception. Winget and
the real bootstrap run only here. Each
job uploads `tests/e2e/out/**` as the artifact `bootstrap-e2e-<host>`, pass or
fail; one run per ref at a time, without cancelling one in progress. The
`cache` input mounts a scratch directory under the runner's temp, which no
later run sees, so it only saves downloads within one job; acceptance runs
leave it off.

### Real clusters

Sherlock and Marlowe cannot run the containers (no Docker on a login node, and
`E2E_NATIVE` is honoured only on macOS). For a separately requested genuine
fresh-cluster acceptance run, the owner runs the bootstrap by hand on a fresh
account home and checks the criteria above the same way. Log in without the
RemoteCommand (`ssh sherlock-plain`,
`ssh marlowe-plain`), paste `home_cz` and `home_deploy` from
[Fresh home by hand](bootstrap.md#fresh-home-by-hand) into the shell, then:

```sh
uname -a; cat /etc/os-release; ldd --version | head -n 1   # record these with the run
git clone https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles && export DOTFILES_AUTO_UPDATE=0
./dotfiles doctor --host sherlock --tsv                           # or marlowe; exit 1 is expected now
marker=$(mktemp) && sleep 1
./dotfiles setup --host sherlock --check                     # exit 3
find "$HOME" -path "$HOME/dotfiles/.git" -prune -o -newer "$marker" -print   # must print nothing
./dotfiles setup --host sherlock                             # light steps; exit 3 at H2-alloc
sh_dev -t 1:00:00                                           # Marlowe: srun --time=1:00:00 --pty bash -l
cd ~/dotfiles && export DOTFILES_AUTO_UPDATE=0
echo "$SCRATCH"                                             # Sherlock: the site sets it; Marlowe: empty before the deployment
export CONDA_PKGS_DIRS="$SCRATCH/.cache/conda/pkgs"         # Sherlock
# Marlowe: export CONDA_PKGS_DIRS="/scratch/m000191/.cache/conda/pkgs/$USER"   # the overlay's value; no site SCRATCH yet
./dotfiles setup --host sherlock                             # builds the login env; exit 3 with only H7-deploy left
exit                                                        # back to the login node
cd ~/dotfiles && home_deploy sherlock                       # H7-deploy: Fresh home by hand
./dotfiles setup --host sherlock                             # exits 0 and prints no "done applied:" line
git -C ~/dotfiles status --porcelain                        # empty, here and after every step above
exec "$HOME/micromamba/envs/login/bin/zsh" -l               # starts without an error line
"$HOME/.local/bin/dotfiles" payloads sync               # H7-payloads (criterion 7; no login runs it): exits 0
cd ~/dotfiles && home_cz diff --exclude=dirs                # paste the functions again in this shell; prints nothing
./dotfiles doctor --host sherlock && ./dotfiles doctor --host sherlock --smoke
```

Nothing but the HUMAN blocks and the deployment changed the home when
`~/.config/chezmoi/chezmoi.toml` and the deployed regular files (`~/.zshrc`
among them) appear only after the `home_deploy` line, the backup
directory `~/.local/state/dotfiles-fresh-backup` holds the earlier rc files
byte for byte, and `getent passwd "$USER"` still names the same login shell
at the end. Then record the result in the Status cell of that cluster's row
in the [acceptance table](bootstrap.md#acceptance-checklist), with the OS and
glibc from the first line and any limitation.
