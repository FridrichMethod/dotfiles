# Payload repos

Three first-party repositories are installed on every host but are not part
of this one: [coding-agent-kit](https://github.com/FridrichMethod/coding-agent-kit)
(the `codex-as` and `claude-as` account launchers, their completions and the
Claude status line, notification and Git hook check helpers; Linux, macOS and
WSL only, nothing on native Windows),
[PyMOLScripts](https://github.com/FridrichMethod/PyMOLScripts) (the PyMOL
start-up configuration) and
[awesome-skills](https://github.com/FridrichMethod/awesome-skills) (the skill
library of Claude Code and Codex). Each repository owns its installation,
update, selection and locking, and documents one command that installs it and
one that updates it. Dotfiles runs those commands only when a person asks:
`sync-payloads` runs the payload hook, `scripts/payload-update.sh` (Unix) or
`scripts/payload-update.ps1` (native Windows), and
[`config/payloads.tsv`](../config/payloads.tsv) names them. No login, profile
or schedule installs or refreshes them.

There is no submodule, no bump workflow and no pin on the dotfiles side. The
kit follows the newest patch release of the `MAJOR.MINOR` channel that
`config/payloads.tsv` declares (`0.7`); PyMOLScripts and awesome-skills
install from their `main`. What each repository installs, its options and its
own state are in its README; this file covers only how dotfiles calls them.

| Item | Repository | Unix | Native Windows |
| --- | --- | --- | --- |
| `kit` | coding-agent-kit | a managed install of channel `0.7`: `codex-as` and `claude-as` in `~/.local/bin`, their Bash completions in bash-completion's user directory and their zsh completions in `~/.local/share/zsh/site-functions`, and the three helpers in `~/.claude/coding-agent-kit/` | nothing: the kit is not available there (it has no `windows-*` rows), and its launchers never ran natively |
| `pymol` | PyMOLScripts | `~/.pymolrc` and `~/.pymolrc.py` | the same two files in `$HOME` |
| `skills` | awesome-skills | its skill copies under `~/.claude/skills/`, `~/.codex/skills/` and `~/.agents/skills/awesome-skills/`, with selection and visibility managed by its installer | the same, through its `install.ps1` |

`common/claude/.claude/settings.json` runs the helpers by their home-relative
path, for example
`node -e "const f=require('os').homedir()+'/.claude/coding-agent-kit/statusline.cjs';if(process.platform!=='win32'||require('fs').existsSync(f))require(f).main()"`,
so they need Node.js 22 or newer on PATH. On Unix a missing helper stays
visible: the command exits 1, so Claude Code shows no status line and a
non-blocking hook error. On native Windows, where the kit installs nothing,
the command exits 0 silently while the helper is missing (a blank status
line, no hook), and a copy an older kit release (0.6) left in
`~\.claude\coding-agent-kit\` still runs. `common/zsh/.zshrc` appends
`~/.local/share/zsh/site-functions` to `fpath` before oh-my-zsh runs
`compinit`, so the kit's zsh completions load.

## config/payloads.tsv

The one place that names the three repositories: their download URLs, the
paths that show an install, the install and update commands, and the kit
channel. Rows are `ITEM<TAB>FIELD<TAB>VALUE`; lines starting with `#` are
comments, and the first row of an item and field wins.

| Field | Meaning |
| --- | --- |
| `channel` | `kit` only: the coding-agent-kit `MAJOR.MINOR` channel this configuration is written for |
| `unix-probe`, `windows-probe` | succeeds once the item is installed; until then the hook runs its install command, after that its update command |
| `unix-install`, `windows-install` | the first-install command; an item without a `windows-install` row (the kit) is not available on native Windows: it is no default item there, and a run that names it says so (exit 0) |
| `unix-update`, `windows-update` | the update command; without one the install command runs again, which is the update for PyMOLScripts and awesome-skills |
| `person-status` | an exit status with which the repo stops for a person, whose message names what to do; the hook words such a failure as one that waits for a person. `3` for both: PyMOLScripts at a locally edited `~/.pymolrc` or `~/.pymolrc.py`, which it leaves alone (see [the hook](#unix)); awesome-skills where it will not go on alone: an interrupted update it cannot undo because a file it would restore was edited since, an update that would remove many installed skills at once, a Codex skill folder that would pass 1,990 entries, or a Codex folder layout it cannot use; its message names the command to run, such as `--restore` |
| `stow-links` | `PACKAGE PATH...`: home paths that the installer refuses while they are links into the retired dotfiles package `common/PACKAGE` (the kit's launchers and Bash completions); while one is, the hook does not call the installer and says to run `stow-all` |

`unix-*` values are POSIX `sh` and `windows-*` values PowerShell 7, evaluated
by the hook (the sh one with the kit channel in `$channel`) and with one
helper:

- `payload_script INTERPRETER SOURCE [ARG...]` (sh) and
  `Invoke-DotfilesPayloadScript SOURCE [ARG...]` (PowerShell, which runs the
  script in a child `pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File`)
  run SOURCE with ARG and return its exit status. A URL is downloaded first
  (curl, else wget with timeout/gtimeout; PowerShell uses .NET HttpClient), never piped into a shell, so a
  failed or empty download runs nothing. It goes, under the name it was
  published with, into a fresh directory of the temporary directory that
  holds nothing else and that only this user can enter (`mktemp -d` under
  umask 077 in `${TMPDIR:-/tmp}`; on Windows a new subdirectory of `%TEMP%`
  created in one step with an access list that grants this account alone,
  not even SYSTEM, and inherits nothing from `%TEMP%`, so it stays private
  where `TEMP` is a shared `C:\Temp`; when it cannot be made so, nothing
  runs), and that directory is removed afterwards: PyMOLScripts' and
  awesome-skills' installers read files beside themselves as a checkout's,
  so a `configs/` or `scripts/` another user planted in a shared `/tmp`, or
  added during the download, must never be there. Each download is bounded
  by `DOTFILES_PAYLOAD_TIMEOUT` seconds (default 60: curl
  `--connect-timeout 10 --max-time 60`; wget's whole process wrapped by an
  existing `timeout` or `gtimeout`, in addition to its inactivity timeout;
  PowerShell's built-in .NET HttpClient.Timeout covering the entire HTTP(S)
  response body, which is buffered before writing). Wget without a total
  deadline tool fails with a named dependency message: install curl or provide
  timeout/gtimeout explicitly; the hook installs neither. Header receipt or
  intermittent body bytes do not complete a download. An empty HTTP 200 body
  is a download failure too. Once a download fails or is empty, that run tries
  no later installer downloads, so a stalled network holds a run for one
  download deadline, not one per item.
  This deadline covers dotfiles' script download, not networking performed
  inside the upstream installer. Local file:// fixture paths use local copies. A path must be an existing file. On Unix the installer's
  stdin is closed. Every installer, a download or an installed script,
  starts in `/` (PowerShell: in `$PSHOME`, which only whoever could replace
  that pwsh can write) and finds its own files through its path. It never
  runs in the caller's working directory, which may be a shared one too (a
  shell started in `/tmp`) or an untrusted checkout (a VS Code terminal
  starts in its workspace). The upstream installers also own their Python
  import and executable lookup isolation; dotfiles does not rely on their
  internal implementation to choose a neutral starting directory.
  Nor does it run in its download
  directory, whose parent may be shared: git looks for a repository from
  its working directory upwards, so the kit's `git ls-remote`, run outside
  any repository, would read a `/tmp/.git` another user made wherever
  `safe.directory = *` turns git's ownership check off (lab-ubuntu's
  `.gitconfig_local` does). On Unix `/` ends that walk, since only root can
  create `/.git`. On Windows no directory does: from any path on `C:`,
  `$PSHOME` included, git reaches `C:\.git`, which any authenticated user
  can create (CVE-2022-24765), so there only git's own ownership check
  refuses such a repository. Dotfiles chooses only the directory each
  installer starts in; git that an installer runs from another directory is
  that repository's to guard.

Every URL is under `https://raw.githubusercontent.com/FridrichMethod/`:
`tests/payload-update.sh` points that prefix at `file://` fakes and fails on
any other URL, so a test can never reach the network.

## The hook

### Unix

Only a person runs `scripts/payload-update.sh`, in the foreground: no login,
profile, schedule or background process does, and it keeps no state of its
own.

```sh
sync-payloads [kit] [pymol] [skills]                      # common/sh/.aliases; follows the home binding
sync-skills                                               # sync-payloads skills
sh ~/dotfiles/scripts/payload-update.sh --now [ITEM...]   # default: DOTFILES_PAYLOAD_ITEMS
```

`sync-payloads` and `sync-skills` are aliases of interactive shells. In a
native home they run the hook of the source `~/.config/dotfiles/native`
names, validated with that source's `lib/chezmoi-guard.sh` exactly as the
login dispatch in `common/sh/.profile` does; an invalid binding prints
`[dotfiles] [error] Native home binding is invalid; payload update refused.`
and returns 1 without running any checkout's hook. Only an unmarked (legacy)
home runs `${DOTFILES_DIR:-$HOME/dotfiles}/scripts/payload-update.sh`. They
return the hook's status. Under persistent maintenance a `--now` run prints
`dotfiles: payload update refused during maintenance.` and exits 1 before
anything runs.

A run takes the items it is given, else those of `DOTFILES_PAYLOAD_ITEMS`
(unset: all three; set but empty: none), and exits 1 before anything runs
when one is unknown.
For each item in order it runs the install command while the item's probe
fails and the update command once it passes, with stdin closed, and ends the
item with one line:

- exit 0: `kit: install done` or `kit: update done`;
- exit 75, which the kit's and awesome-skills' installers return while
  another run holds their lock (PyMOLScripts takes none): the info line
  `kit: another run holds its lock; run sync-payloads kit again once it has
  finished`, and no failure;
- the item's `person-status`: `skills: stopped for a person (exit 3): do what
  its message says, then run sync-payloads skills`, since the installer's
  message just above names what to do;
- any other status: `kit: install failed (exit 1); retry with: sync-payloads
  kit`.

It exits 1 when an item failed or waits for `stow-all` (below), and 0
otherwise. A failed item is retried only by a person's next run.

PyMOLScripts exits 3 when `~/.pymolrc` or `~/.pymolrc.py` was edited locally
since it last installed them: it writes nothing and its message names the
file, how to see the edit and the command that overrides it. A local edit
therefore stops every `pymol` run the same way until the edit is committed
upstream, reverted, moved to `~/.pymolrc.local.pml` (which PyMOL runs after
both files and the installer never touches), or forced with that command (its
`--force`, `-Force` on Windows, which keeps the edited file as
`NAME.local-<timestamp>`).

An item with a [`stow-links`](#configpayloadstsv) path still linked into its
retired package, which happens while `stow-all` has not run since the pull
(a dirty tree, an unrecorded host, `DOTFILES_AUTO_STOW=0`, a failed stow), is
not handed to its installer, which would refuse the link: the hook prints
`kit: ~/.local/bin/claude-as is still a link the retired Stow package made,
which its installer refuses; run <clone>/stow-all.sh with this host first
(the next login's automatic stow does), then sync-payloads kit` and counts the
item as failed. PyMOLScripts' installer replaces its old links itself, so it
runs. The check stays until Stage 6.

Until Stage 6 a call without `--now` does nothing and returns 0, printing
nothing and leaving no variable, option or trap set: rc files read before the
pull that ended the automatic runs still source the hook without arguments,
and a run they started may still pass the retired `--auto` or `--worker`. So
`sh .../payload-update.sh kit`, without `--now`, does nothing either.

Sherlock's site rules forbid detached login-node workers, and none can start:
no login starts a run (`tests/test_chezmoi_guard.py` checks bash and sh
logins with and without the Sherlock overlay), and `--now` returns only once
its installers have finished (`tests/payload-update.sh`). The overlay needs no
override.

### Native Windows

`scripts/payload-update.ps1` is the twin, and only a person runs it too: the
tail of `win/powershell/Documents/PowerShell/profile.ps1` runs only the update
hook. Its items are those with a `windows-install` row, PyMOLScripts and
awesome-skills: the kit has none, since it installs nothing on native
Windows, so a run that names it, as an argument or in
`DOTFILES_PAYLOAD_ITEMS`, prints `kit: not available on native Windows ...`
and leaves it out without a failure. It keeps the Unix contract:
`DOTFILES_PAYLOAD_ITEMS`, `DOTFILES_PAYLOAD_TIMEOUT`, install or update in the
foreground, an unknown item failing the run, exit 75 no failure, the
`stow-links` check (which says to run `stow-all.ps1` from an elevated
PowerShell 7) and the `person-status` wording. It exits 1 when an item failed
and 0 otherwise, so `$LASTEXITCODE` is the run's status, not an installer's.
Under maintenance a `-Now` run warns
`dotfiles: payload update refused during maintenance.` and exits 1. Until
Stage 6 a call without `-Now` (an older
profile's call without arguments, or an older run's `-Auto` or `-Worker`)
returns at once.

Run it and the functions below from an ordinary PowerShell: an installer run
elevated would leave its git clone owned by Administrators, which Git then
refuses to update from an ordinary shell. From an elevated session they run
but warn first.

```powershell
sync-payloads [pymol] [skills]   # profile functions, defined in interactive non-agent sessions
sync-skills
& $HOME\dotfiles\scripts\payload-update.ps1 -Now [ITEM...]
```

Like their Unix twins, the functions run the hook of the source a native
home's binding names, read from a marker that must be a regular file, not a
reparse point, and validated by that source's `lib/chezmoi-guard.ps1`; an
invalid binding prints
`[dotfiles] Payload update refused: review the native source binding privately.`
and sets `$LASTEXITCODE` to 1 without running a hook. Only an unmarked home
uses `$env:DOTFILES_DIR`, else `~\dotfiles`.

## Knobs

| Variable | Default | Effect |
| --- | --- | --- |
| `DOTFILES_PAYLOAD_ITEMS` | `kit pymol skills` (native Windows: `pymol skills`, the items with a `windows-install` row) | the items a run without arguments installs or updates and the doctor's `payloads` row checks, separated by spaces; set but empty selects none; on native Windows a named item without a `windows-install` row (the kit) is left out |
| `DOTFILES_PAYLOAD_TIMEOUT` | `60` | the bound, in seconds, of each download of an installer script |
| `DOTFILES_DIR` | `~/dotfiles` | in an unmarked (legacy) home, the checkout whose hook `sync-payloads` runs; a native home runs the hook of the source its binding names |

Set them in the environment your terminals and ssh sessions start with: every
rc file in this repository is tracked, so there is no local file to set them
in. The repositories' own variables (for example
`CODING_AGENT_KIT_REPO_URL`, `PYMOLSCRIPTS_REF`, the `SKILLS_*` overrides)
reach their installers unchanged, and on Unix `XDG_DATA_HOME` moves the kit's
managed root, which its probe follows.

`AWESOME_SKILLS_AUTO_UPDATE`, the old skill hook's opt-out, is read by
nothing any more. This page used to promise that the automatic runs and the
doctor would honor `AWESOME_SKILLS_AUTO_UPDATE=0` until 2027-01-31; that
support ended early, in Stage 5 of the chezmoi migration, together with the
automatic runs, and the promise is withdrawn. Name the items on the command
instead, for example `sync-payloads kit pymol`; a shell that still exports
the variable sees `skills` in the doctor's `payloads` row again unless it
sets `DOTFILES_PAYLOAD_ITEMS='kit pymol'`. The old skill hook's other
variables (`AWESOME_SKILLS_FORCE`, `AWESOME_SKILLS_BG`,
`AWESOME_SKILLS_INSTALLER_URL`, `AWESOME_SKILLS_REFRESH_DAYS`,
`_AWESOME_SKILLS_CHECKED`) and those of the automatic runs
(`DOTFILES_PAYLOAD_AUTO_UPDATE`, `_DOTFILES_PAYLOAD_CHECKED`) are read by
nothing either. The provisioning shells of [bootstrap.md](bootstrap.md) and
the setup-host scripts still export `DOTFILES_PAYLOAD_AUTO_UPDATE=0` beside
`DOTFILES_AUTO_UPDATE=0`; that export is inert and stays until Stage 6.

## State

Dotfiles keeps no payload state. A host that had the automatic runs before
Stage 5 may still hold their `ITEM.stamp`, `ITEM.failed` and `payload.log` in
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/payload/` (native Windows:
`%LOCALAPPDATA%\dotfiles\payload\`). Nothing reads or removes them; delete
that directory by hand if you like.

The repositories keep their own state: the kit's managed root in
`${XDG_DATA_HOME:-~/.local/share}/coding-agent-kit/` (Unix only; see
[the kit leaving native Windows](#the-kit-leaves-native-windows) for what a
0.6 install left there), awesome-skills' library in
`${XDG_DATA_HOME:-~/.local/share}/awesome-skills/library` and its selections
and ownership manifests (`claude.json`, `codex.json`) and its lock in
`~/.local/share/awesome-skills/` (Windows both in
`%LOCALAPPDATA%\awesome-skills\`). The `skills` probe passes on a manifest or
the library clone, as awesome-skills documents an install, so an install of
its older tarball installer, whose manifests have the same names, counts too.
PyMOLScripts keeps a copy of the rc files it last installed, which tells a
local edit from an older upstream version (in
`${XDG_STATE_HOME:-~/.local/state}/pymolscripts/`, Windows
`%LOCALAPPDATA%\pymolscripts\`; its README has the details), and takes no
lock: concurrent runs converge.

## Doctor and setup-host

- The doctor's `payloads` row (tier `ai`, step
  [H7-payloads](bootstrap.md#h7-payloads-payload-repos)) runs each selected
  item's probe and, once the kit's passes, checks that the three helpers are
  in `~/.claude/coding-agent-kit/`; `.\doctor.ps1` checks only the items with
  a `windows-install` row, so neither the kit nor its helpers, and names an
  item the file does not know. It names each selected item that waits for
  `stow-all` (`... run <clone>/stow-all.sh <host>, then sync-payloads kit`).
  Missing items end with `run sync-payloads ITEM` (on Unix also
  `sh <clone>/scripts/payload-update.sh --now ITEM`) and, when the kit or one
  of its helpers is missing, with what fails until then. All of it is `warn`,
  never `missing`. It only reads paths and files, never a record of an
  earlier run, so the doctor stays read-only.
- `./setup-host.sh` prints H7-payloads as a non-blocking judgment block until
  the `payloads` row is `ok`. Its run line,
  `sh '<clone>/scripts/payload-update.sh' --now`, installs the selected items
  now and, run again later, updates them, as `sync-payloads` does in an
  interactive shell.
- `./setup-host.sh`, `./stow-all.sh`, `stow-all.ps1` and the login updaters
  never run an installer of a payload repository.

## Trust

Each install command downloads its repository's `main` install script, an
unpinned branch head, over https from raw.githubusercontent.com, the trust
model the old skill hook had. The kit's `main` script only bootstraps: it
installs and then runs the code of a release of the declared channel, and
later updates run that release's own installer. A new kit patch release
therefore reaches a host the next time a person runs `sync-payloads kit`
there, checked only by the kit's own CI and release process. Dotfiles'
`ci.yml` installs the real kit of the channel in its Linux and macOS jobs on
every push and runs the cases that need it ([testing.md](testing.md)), which
shows a breaking patch only after it was released.

## Changing the kit channel

`kit channel` is the `MAJOR.MINOR` line the rest of this configuration is
written for: the helper paths in `settings.json`, the completion directory in
`.zshrc` and the public launcher/install commands it calls. Test entry points
clear inherited kit variable prefixes through `tests/lib/environment.sh` and
`.ps1`, without scanning the kit's implementation. A new minor release
(breaking while the kit is 0.x) is taken through a
reviewed change, landed like any other (a `ci/**` branch, see AGENTS.md):

1. Read the kit's CHANGELOG for the new line and adapt what it changed in this
   repository: `settings.json`, `.zshrc`, the public integration tests and the
   `kit` rows. Preserve shared test-environment isolation.
2. Change the `kit channel` row. The update row passes it too
   (`... --update --channel "$channel"`): a
   host's managed root remembers its channel and a plain `--update` keeps it,
   while a run that names another channel switches to that channel's newest
   release, so an installed host moves at its next `sync-payloads kit`.
3. Push the branch: CI installs the real kit of the new channel and runs the
   installed-kit cases for the required helpers, launcher commands and
   completion wiring. Extra upstream helpers or variable names are allowed.

A host keeps its installed line until a person runs `sync-payloads kit`
there, so run it on every host once the change has landed. A bad patch
release is fixed forward in the kit, with a newer patch (never move a tag);
hosts take it at their next `sync-payloads kit`. Going back to an older line
is a channel change to that line.

## Adapting to the repositories' interfaces

The rows follow the repositories' published README interfaces. Recheck the
commands, exit statuses and persistent probe paths when an upstream release
changes them, including awesome-skills' Windows data root
(`%LOCALAPPDATA%\awesome-skills`). Change the rows in `config/payloads.tsv`
and their contract documentation together, in one reviewed change:

1. Take the commands from the repository's README, the section it names as its
   stable interface, never from its code.
2. For each item, check that the probe tests a path the installer creates and
   keeps for as long as the install exists; that the install row runs the
   documented bootstrap command with the documented arguments and the
   interpreter the README pipes it to (`sh` or `bash`); and that the update
   row runs the documented update command, or is absent when the install
   command is also the update. Do the same for the `windows-*` rows.
3. Run `bash tests/payload-update.sh`, then on a real host `sync-payloads` and
   `./doctor.sh --host <host>` (the `payloads` row), and on Windows
   `sync-payloads` and `.\doctor.ps1`.

A probe that never passes makes every run reinstall the item; a probe that
passes too early makes the hook update an item that was never installed.

## Migration

The change that replaced the two submodules and the weekly skill hook
converges a host's dotfiles in one login; since Stage 5 the payload repos then
install only when a person runs `sync-payloads` there. Git cannot remove a
submodule checkout that holds files, so the two checkouts stay as
[leftovers](#leftover-checkouts).

### Unix

1. The login runs the rc files it read before the pull. Their
   `scripts/dotfiles-update.sh` fetches and fast-forwards; the leftover
   checkouts are ignored, so the tree is clean, and it runs the new
   `./stow-all.sh` for the remembered host.
2. `./stow-all.sh` runs its dry run, syncs the new `settings.json` and
   stows; only then does it remove the 16 links Stow made from the two
   retired packages, each only while it is a symlink whose text is exactly
   the one Stow wrote from this checkout, dangling or not: the 14 of
   `common/coding-agent-kit` (the helpers in `~/.claude/dotfiles/`, the
   launchers in `~/.local/bin/`, the modules in `~/.local/lib/codex-as/` and
   `~/.local/lib/claude-as/`, and the Bash and zsh completions) and the two
   of `common/pymol` (`~/.pymolrc`, `~/.pymolrc.py`). A file, a directory or
   any other link stays. It then removes `~/.claude/dotfiles`,
   `~/.local/lib/claude-as`, `~/.local/lib/codex-as` and
   `~/.oh-my-zsh/custom/completions` if they are empty, and the login
   updater records the applied revision. A refused dry run or a failed stow
   leaves the links in place, and a failed removal stops it before anything
   is recorded, so the next login retries.
3. The same rc files then source `scripts/awesome-skills-update.sh`, the old
   hook's path, which is now a [transition shim](#the-transition-shim) that
   does nothing, so the login installs no payload repo.
4. A person then runs `sync-payloads` (or the H7-payloads line): it installs
   the kit and PyMOL, whose probes fail, and updates awesome-skills, whose
   existing install already passes its probe. A failed item makes the run
   exit 1 with the line to retry with.

The window between the pull and the kit's install is the one in which
Claude Code runs without the kit: `settings.json` already names
`~/.claude/coding-agent-kit/`, so the status line command fails and Claude
shows no status line, and the notification and Git hook check helpers exit 1,
which Claude Code reports as a non-blocking hook error (only exit 2 blocks):
tool calls and prompts go on. It lasts until a person runs
`sync-payloads kit`; meanwhile the doctor's `payloads` row names the kit and
what fails until it is installed.

`tests/unix-installer.sh` runs this login, and the explicit run after it, end
to end with real Git and Stow.

On a host where the login does not stow (`DOTFILES_AUTO_STOW=0`, a dirty
tree, an unrecorded host, a failed stow, or `DOTFILES_AUTO_UPDATE=0` after a
pull by hand), nothing removes the old links, which the kit's installer
refuses: `sync-payloads kit` exits 1 with the line that says to run
`./stow-all.sh` with this host, and the doctor says the same, until it has
run; `sync-payloads kit` then installs the kit. The links stay in place
whenever `./stow-all.sh` stops: it removes them only after both stows
succeeded, so a refused dry run or a failed stow leaves the home as it was.
`AWESOME_SKILLS_AUTO_UPDATE=0` keeps nothing off any more (see
[Knobs](#knobs)).

### Native Windows

1. The login that pulls runs the profile it read before the pull. Its
   `scripts/dotfiles-update.ps1` fast-forwards (the leftover checkouts are
   ignored) and queues the elevated restow, which the `Dotfiles-Restow-*` task
   ([HW-auto-stow-task](bootstrap.md#hw-auto-stow-task-automatic-stow-task))
   or the next elevated `.\stow-all.ps1 win` runs.
2. The new `stow-all.ps1` stows, then removes the links it made from the two
   retired packages, each only while it is a symlink whose text is exactly
   the path it wrote, `<clone>\common\<package>\<path>`, dangling or not.
   Harmless empty legacy directories are left in place. A declined link removal is a
   warning, so the revision is not acknowledged. It installs nothing: an
   installer run elevated would leave Administrators-owned clones.
3. A person then runs `sync-payloads` from an ordinary PowerShell 7, which
   installs PyMOLScripts and awesome-skills where they are absent (the old
   skill hook ran only on Unix; the kit has left native Windows, see below).
   Until the restow has synced the new `settings.json`, the live one still
   names `~\.claude\dotfiles\`, whose links dangle, so Claude's status line
   and hooks fail until then.

### The kit leaves native Windows

coding-agent-kit 0.7 installs nothing on native Windows (it never had
account switching there, only the three helpers), and `config/payloads.tsv`
has no `windows-*` rows for it, so from the pull on the PowerShell hook and
`.\doctor.ps1` leave the kit out. What a 0.6 install left stays, frozen:
`%LOCALAPPDATA%\coding-agent-kit\` and the three helper copies in
`~\.claude\coding-agent-kit\`, which the `settings.json` commands keep
running, and `kit.stamp` or `kit.failed` in `%LOCALAPPDATA%\dotfiles\payload\`,
which nothing reads any more. To remove them, from an ordinary PowerShell 7:

```powershell
pwsh -NoProfile -File "$env:LOCALAPPDATA\coding-agent-kit\install.ps1" -Uninstall -Purge
Remove-Item -LiteralPath "$env:LOCALAPPDATA\dotfiles\payload\kit.stamp", "$env:LOCALAPPDATA\dotfiles\payload\kit.failed" -ErrorAction Ignore
```

Claude Code then shows no status line there and its notification and Git hook
check commands do nothing, without an error, since on native Windows they
exit 0 while a helper is missing. WSL, and an ssh session into a Unix host,
keep the whole kit.

### The transition shim

`scripts/awesome-skills-update.sh` exists only for step 3 on Unix: the rc
files a host read before the pull source that path. It does nothing, and
Stage 6 removes it; a host that logs in after it is gone loses nothing, since
the old rc files only source a readable file.

## Leftover checkouts

| Leftover checkout | Its repository |
| --- | --- |
| `common/codex/coding-agent-kit` (from before the kit moved to its own package) | `.git/modules/common/codex/coding-agent-kit` |
| `common/coding-agent-kit/coding-agent-kit` | `.git/modules/common/codex/coding-agent-kit` (the submodule kept its first name) |
| `common/pymol/PyMOLScripts` | `.git/modules/common/pymol/PyMOLScripts` |
| `common/sherlock-kit/sherlock-kit` ([sherlock-kit.md](sherlock-kit.md)) | `.git/modules/common/sherlock-kit/sherlock-kit` |

A pull across a submodule's removal leaves its checkout on every host where it
was checked out. They are harmless:

- `.gitignore` names each of them, so `git status` stays clean; without those
  lines the login updater would stop at `Checkout changed during update` and
  then at `Local changes` on every later login.
- The `.stowrc` lines `--ignore=^coding-agent-kit(/|$)`,
  `--ignore=^PyMOLScripts(/|$)` and `--ignore=^sherlock-kit(/|$)` keep Stow
  from linking their trees into `$HOME`: `common/coding-agent-kit` and
  `common/pymol` still exist on such a host, holding only the leftover, and
  `./stow-all.sh` stows every directory of `common/` as a package.
- Nothing in dotfiles reports or removes them or their repositories under
  `.git/modules`. `git -C <path> status` and
  `git -C <path> log --branches --not --remotes` show whether one holds work
  of yours.

`git -C ~/dotfiles status --porcelain --ignored -- common` lists each leftover
as an ignored (`!!`) path. Once a checkout holds nothing you want, remove it
with `rm -rf <path>` (`Remove-Item -LiteralPath <path> -Recurse -Force` on
Windows). Its repository under `.git/modules` can go the same way once no
other leftover uses it: both kit leftovers share one, so remove it only after
both checkouts are gone. Keep the `.gitignore` and `.stowrc` lines until no
host has a leftover.

## The kit on a dotfiles host

The kit documents itself in its
[README](https://github.com/FridrichMethod/coding-agent-kit): account views,
login, completion, concurrency, takeover, resume, the account details, the
optional configuration file and the `CODING_AGENT_KIT_*` variables. What
dotfiles adds:

- The settings and the AI config sync engine (`lib/config_sync.py`,
  [config-sync.md](config-sync.md)) stay in this repository; the kit needs
  none of them.
- Dotfiles ships no `${XDG_CONFIG_HOME:-~/.config}/coding-agent-kit/config.toml`,
  so the kit's defaults apply (`codex-as --show-config` prints them). If a host
  ever needs one, let one package of that host's overlay own the whole file,
  never a common file plus a host copy, and set `codex_home` and `secrets_dir`
  before the first enrolment there, because account links are absolute.
- The fzf-tab preview in `common/zsh/.oh-my-zsh/custom/fzf-tab.zsh` shows
  the kit's `--info NAME` for an account, offline and without opening a
  credential, so emails and labels show in previews, screen shares and agent
  transcripts; no token is printed. It calls the older spelling,
  `codex-as --account-info NAME` or `claude-as --account-info NAME`, which
  every release keeps accepting, so it works on a host that still runs 0.6
  until `sync-payloads kit` updates it. By hand, use the kit 0.7 names: `--info`
  (`-i`), `--list` (`-l`), `claude-as --label NAME LABEL` and `--version`
  (`-V`).
- The launchers color their messages by `CODING_AGENT_KIT_COLOR`, not
  `DOTFILES_COLOR`.
- Develop the kit in a clone of its own. Never edit its managed root: its
  `releases/` are exported trees that the next switch replaces.

## Verify

```sh
sync-payloads                                   # each item: install done or update done
./doctor.sh --host <host>                       # payloads ok
ls ~/.claude/coding-agent-kit/                  # check-git-hooks.cjs notify.cjs statusline.cjs
readlink ~/.local/bin/codex-as                  # a path in the kit's managed root, .../current/bin/codex-as
codex-as --version                              # kit 0.7 and later: coding-agent-kit X.Y.Z (managed vX.Y.Z, channel X.Y)
ls -l ~/.pymolrc ~/.pymolrc.py                  # regular files
```

On Windows: `sync-payloads` (PyMOLScripts and awesome-skills) and
`.\doctor.ps1`.

Loopback download fixtures cover a server that stalls after headers and a
trickling body, and empty HTTP 200 responses with the failed-download latch.
Linux PowerShell execution exercises the .NET download path, not native
Windows ACL, process or network behavior; retain native Windows validation
for those platform claims.
