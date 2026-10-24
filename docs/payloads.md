# Payload repos

Three first-party repositories are installed on every host but are not part
of this one: [coding-agent-kit](https://github.com/FridrichMethod/coding-agent-kit)
(the `codex-as` and `claude-as` account launchers, their completions and the
Claude status line, notification and Git hook check helpers),
[PyMOLScripts](https://github.com/FridrichMethod/PyMOLScripts) (the PyMOL
start-up configuration) and
[awesome-skills](https://github.com/FridrichMethod/awesome-skills) (the skill
library of Claude Code and Codex). Each repository owns its installation,
update, selection and locking, and documents one command that installs it and
one that updates it. Dotfiles only decides when to run those commands: the
payload hooks `scripts/payload-update.sh` (Unix) and
`scripts/payload-update.ps1` (native Windows) run them, and
[`config/payloads.tsv`](../config/payloads.tsv) names them.

There is no submodule, no bump workflow and no pin on the dotfiles side. The
kit follows the newest patch release of the `MAJOR.MINOR` channel that
`config/payloads.tsv` declares (`0.6`); PyMOLScripts and awesome-skills
install from their `main`. What each repository installs, its options and its
own state are in its README; this file covers only how dotfiles calls them.

| Item | Repository | Unix | Native Windows | Refresh |
| --- | --- | --- | --- | --- |
| `kit` | coding-agent-kit | a managed install of channel `0.6`: `codex-as` and `claude-as` in `~/.local/bin`, their Bash completions in bash-completion's user directory and their zsh completions in `~/.local/share/zsh/site-functions`, and the three helpers in `~/.claude/coding-agent-kit/` | the three helpers only, copied into `~\.claude\coding-agent-kit\` (the launchers do not run natively there) | daily |
| `pymol` | PyMOLScripts | `~/.pymolrc` and `~/.pymolrc.py` | the same two files in `$HOME` | daily |
| `skills` | awesome-skills | the library and the selections of `~/.claude/skills/` and `~/.codex/skills/` | the same, through its `install.ps1` | weekly |

`common/claude/.claude/settings.json` runs the helpers by their home-relative
path, for example
`node -e "require(require('os').homedir() + '/.claude/coding-agent-kit/statusline.cjs').main()"`,
so they need Node.js 22 or newer on PATH. `common/zsh/.zshrc` appends
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
| `days` | the refresh interval: an installed item is updated in the background once its last success is this many days old |
| `unix-probe`, `windows-probe` | succeeds once the item is installed; until then the hook runs its install command, in the foreground |
| `unix-install`, `windows-install` | the first-install command |
| `unix-update`, `windows-update` | the update command; without one the install command runs again, which is the update for PyMOLScripts and awesome-skills |

`unix-*` values are POSIX `sh` and `windows-*` values PowerShell 7, evaluated
by the hook with the channel in `$channel` (`$Channel`) and with one helper:

- `payload_script INTERPRETER SOURCE [ARG...]` (sh) and
  `Invoke-DotfilesPayloadScript SOURCE [ARG...]` (PowerShell, which runs the
  script in a child `pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File`)
  run SOURCE with ARG and return its exit status. A URL is downloaded first
  (curl, else wget; `Invoke-WebRequest`) into a temporary file, never piped
  into a shell, so a failed or empty download runs nothing; the file is
  removed afterwards. A path must be an existing file. On Unix the
  installer's stdin is closed.

Every URL is under `https://raw.githubusercontent.com/FridrichMethod/`:
`tests/payload-update.sh` points that prefix at `file://` fakes and fails on
any other URL, so a test can never reach the network.

## The hook

### Unix

`common/zsh/.zshrc` sources `scripts/payload-update.sh` at its tail, and
`common/sh/.profile` does for bash and sh login shells, each right after
`scripts/dotfiles-update.sh`. Sourced, it does nothing outside an interactive
shell, and runs once per session: it exports `_DOTFILES_PAYLOAD_CHECKED=1`, so
nested shells and tmux panes skip it, and unless `DOTFILES_PAYLOAD_AUTO_UPDATE=0`
it runs `sh "${DOTFILES_DIR:-$HOME/dotfiles}/scripts/payload-update.sh" --auto`,
so its logic never depends on the calling shell's dialect. The automatic run,
for each item of `DOTFILES_PAYLOAD_ITEMS` in order:

- installs an item whose probe fails in the foreground, so a person sees the
  first install;
- queues an installed item whose stamp is at least `days` old, or missing;
- starts the queued items in one detached background run,
  `sh scripts/payload-update.sh --now ITEM...` with its stdin closed and its
  output in `payload.log`, unless the run recorded in `worker.pid` is still
  alive. The run never enters the shell's job table and outlives the shell.

An item's command exiting 0 writes its stamp. Any other status writes none, so
the next session tries again (an item still absent installs in the
foreground again), and prints the line to retry it with, for example
`sync-payloads kit`. Exit 75, the code the kit's and awesome-skills'
installers return while another run holds their lock (PyMOLScripts takes
none), is neither: one info line, no stamp. An automatic run never fails the
shell that started it.

By hand, in the foreground and whatever the intervals or
`DOTFILES_PAYLOAD_AUTO_UPDATE` say:

```sh
sh ~/dotfiles/scripts/payload-update.sh --now [ITEM...]   # default: DOTFILES_PAYLOAD_ITEMS
sync-payloads [kit] [pymol] [skills]                      # the alias in common/sh/.aliases
sync-skills                                               # sync-payloads skills
```

It exits 1 when an item failed or is unknown, and 0 otherwise (exit 75
included).

### Native Windows

`win/powershell/Documents/PowerShell/profile.ps1` calls
`scripts/payload-update.ps1` without arguments at its tail, right after
`scripts/dotfiles-update.ps1`, in the same `if ($IsInteractive)` block, so a
script run, `-Command`, `-NonInteractive` or piped stdin never reaches it; the
script itself also returns when stdout is redirected. It keeps the Unix
contract: once per session through `$env:_DOTFILES_PAYLOAD_CHECKED`,
`DOTFILES_PAYLOAD_AUTO_UPDATE=0`, `DOTFILES_PAYLOAD_ITEMS`, absent items
installed in the foreground, stamps on success only, exit 75 neither. Its
background run is a hidden, detached
`pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File scripts/payload-update.ps1 -Worker ITEM...`
started with `Start-Process`, whose output goes `*>` into `payload.log`, so the
prompt never waits for a download.

It never runs automatically from an elevated session: an installer run there
would leave its git clone owned by Administrators, which Git then refuses to
update from an ordinary shell. An elevated session prints one info line per
absent item and refreshes nothing. For the same reason, run `-Now` and the
functions below from an ordinary PowerShell; from an elevated one they run
but warn first.

```powershell
& $HOME\dotfiles\scripts\payload-update.ps1 -Now [ITEM...]
sync-payloads [kit] [pymol] [skills]   # profile functions, defined in interactive non-agent sessions
sync-skills
```

## Knobs

| Variable | Default | Effect |
| --- | --- | --- |
| `DOTFILES_PAYLOAD_AUTO_UPDATE` | `1` | `0` disables the automatic runs; `--now`, `-Now` and the aliases still run |
| `DOTFILES_PAYLOAD_ITEMS` | `kit pymol skills` | the items the hook and the doctor's `payloads` row manage, separated by spaces; set but empty manages none |
| `DOTFILES_DIR` | `~/dotfiles` | the checkout the rc files source the hook from |
| `_DOTFILES_PAYLOAD_CHECKED` | unset | the exported session marker; a fresh login with a clean environment checks again |

Set them before the hook runs, in the environment your terminals and ssh
sessions start with: every rc file in this repository is tracked, so there is
no local file to set them in. The repositories' own variables (for example
`CODING_AGENT_KIT_REPO_URL`, `PYMOLSCRIPTS_REF`, the `SKILLS_*` overrides)
reach their installers unchanged, and on Unix `XDG_DATA_HOME` moves the kit's
managed root, which its probe follows.

The old skill hook's variables (`AWESOME_SKILLS_AUTO_UPDATE`,
`AWESOME_SKILLS_FORCE`, `AWESOME_SKILLS_BG`, `AWESOME_SKILLS_INSTALLER_URL`,
`AWESOME_SKILLS_REFRESH_DAYS`, `_AWESOME_SKILLS_CHECKED`) are read by nothing
any more. A host that exported `AWESOME_SKILLS_AUTO_UPDATE=0` exports
`DOTFILES_PAYLOAD_AUTO_UPDATE=0` instead, or `DOTFILES_PAYLOAD_ITEMS='kit pymol'`
to keep only the skills off. The provisioning shells of
[docs/bootstrap.md](bootstrap.md#quick-start) export
`DOTFILES_AUTO_UPDATE=0 DOTFILES_PAYLOAD_AUTO_UPDATE=0`.

## State

In `${XDG_STATE_HOME:-~/.local/state}/dotfiles/payload/` (created with umask
077), on native Windows in `%LOCALAPPDATA%\dotfiles\payload\`:

| File | Content |
| --- | --- |
| `ITEM.stamp` | the time of the item's last success, in seconds since the epoch; remove it to make the next session refresh the item |
| `worker.pid` | the PID of the background run and when it started; while that run lives, for a day at most (an older PID is a reused one), no second one starts. The hook's only lock |
| `payload.log` | the output of the last background run, replaced by the next one |

The repositories keep their own state: the kit's managed root in
`${XDG_DATA_HOME:-~/.local/share}/coding-agent-kit/` (Windows
`%LOCALAPPDATA%\coding-agent-kit\`, where `current` is a file and
`install.ps1` the entry point of later runs), awesome-skills' library in
`${XDG_DATA_HOME:-~/.local/share}/awesome-skills/library` and its selections
and ownership manifests (`claude.json`, `codex.json`) and its lock in
`~/.local/share/awesome-skills/` (Windows both in
`%LOCALAPPDATA%\awesome-skills\`). The `skills` probe passes on a manifest or
the library clone, as awesome-skills documents an install, so an install of
its older tarball installer, whose manifests have the same names, counts too.
PyMOLScripts keeps no state and takes no lock: concurrent runs converge.

## Doctor and setup-host

- The doctor's `payloads` row (tier `ai`, step
  [H7-payloads](bootstrap.md#h7-payloads-payload-repos)) runs each selected
  item's probe and, once the kit's passes, checks that the three helpers are
  in `~/.claude/coding-agent-kit/`. A shortfall is `warn`, never `missing`:
  the next interactive shell installs what is missing, and `sync-payloads`
  does it now. The probes only test paths, so the doctor stays read-only.
- The doctor's `submodule` row (tier `core`, step P0-preflight) is `ok` while
  the checkout has no `.gitmodules` and no [leftover checkout](#leftover-checkouts),
  and warns otherwise.
- `./setup-host.sh` prints H7-payloads as a non-blocking judgment block until
  the `payloads` row is `ok`. Its run line,
  `sh '<clone>/scripts/payload-update.sh' --now`, works before the stow and in
  a shell that exports `DOTFILES_PAYLOAD_AUTO_UPDATE=0`.
- Neither `./setup-host.sh`, `./stow-all.sh` nor `stow-all.ps1` ever runs an
  installer of a payload repository.

## Trust

Each install command downloads its repository's `main` install script, an
unpinned branch head, over https from raw.githubusercontent.com, the trust
model the old skill hook had. The kit's `main` script only bootstraps: it
installs and then runs the code of a release of the declared channel, and
later updates run that release's own installer. A new kit patch release
therefore reaches every host at its next daily refresh, checked only by the
kit's own CI and release process. Dotfiles' `ci.yml` installs the real kit of
the channel on every push and runs the cases that need it
([testing.md](testing.md)), which shows a breaking patch only after it was
released.

## Changing the kit channel

`kit channel` is the `MAJOR.MINOR` line the rest of this configuration is
written for: the helper paths in `settings.json`, the completion directory in
`.zshrc` and the `CODING_AGENT_KIT_*` names that every test entry point
unsets. A new minor release (breaking while the kit is 0.x) is taken through a
reviewed change, landed like any other (a `ci/**` branch, see AGENTS.md):

1. Read the kit's CHANGELOG for the new line and adapt what it changed in this
   repository: `settings.json`, `.zshrc`, the unset list of `tests/run.sh`,
   every other test entry point and `tests/run.ps1`, and the `kit` rows.
2. Change the `kit channel` row. The update rows pass it too
   (`... --update --channel "$channel"`, `... -Update -Channel $Channel`): a
   host's managed root remembers its channel and a plain `--update` keeps it,
   while a run that names another channel switches to that channel's newest
   release, so every installed host moves at its next refresh.
3. Push the branch: CI installs the real kit of the new channel and runs the
   installed-kit cases, including the check that the test entry points unset
   every `CODING_AGENT_KIT_*` name the release reads.

Each host then switches at its next refresh, or at once with
`sync-payloads kit`. A bad patch release is fixed forward in the kit, with a
newer patch (never move a tag); hosts take it at their next refresh. Going
back to an older line is a channel change to that line.

## Adapting to the repositories' interfaces

The rows were written against the interface the three repositories agreed on
before they released it, and checked against their draft READMEs: the Windows
data roots (`%LOCALAPPDATA%\coding-agent-kit`, `%LOCALAPPDATA%\awesome-skills`)
and the kit's Windows entry point (`install.ps1` in its managed root) are the
values to re-check first. When a repository documents
its final commands, or later changes them in a release, edit only
`config/payloads.tsv`, in one reviewed change:

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

A probe that never passes makes every session reinstall the item in the
foreground; a probe that passes too early makes the hook update an item that
was never installed.

## Migration

The change that replaced the two submodules and the weekly skill hook
converges on a host in one login. Git cannot remove a submodule checkout that
holds files, so the two checkouts stay as [leftovers](#leftover-checkouts).

### Unix

1. The login runs the rc files it read before the pull. Their
   `scripts/dotfiles-update.sh` fetches and fast-forwards; the leftover
   checkouts are ignored, so the tree is clean, and it runs the new
   `./stow-all.sh` for the remembered host.
2. `./stow-all.sh` removes the 16 links Stow made from the two retired
   packages, each only while it is a symlink whose text is exactly the one
   Stow wrote from this checkout, dangling or not: the 14 of
   `common/coding-agent-kit` (the helpers in `~/.claude/dotfiles/`, the
   launchers in `~/.local/bin/`, the modules in `~/.local/lib/codex-as/` and
   `~/.local/lib/claude-as/`, and the Bash and zsh completions) and the two
   of `common/pymol` (`~/.pymolrc`, `~/.pymolrc.py`). A file, a directory or
   any other link stays. It then removes `~/.claude/dotfiles`,
   `~/.local/lib/claude-as`, `~/.local/lib/codex-as` and
   `~/.oh-my-zsh/custom/completions` if they are empty, stows, syncs the new
   `settings.json` and records the applied revision. A failed removal stops
   it before anything is recorded, so the next login retries.
3. The same rc files then source `scripts/awesome-skills-update.sh`, the old
   hook's path, which is now a transition shim that sources
   `scripts/payload-update.sh`. In that shell the hook installs the kit and
   PyMOL in the foreground (their probes fail), and refreshes awesome-skills
   in the background: its existing install already passes the probe, and it
   has no stamp yet.
4. A failed install writes no stamp; the next interactive shell installs it
   again in the foreground, or run `sync-payloads ITEM`. Until the kit is
   installed, Claude's status line and hooks fail, and the doctor's `payloads`
   row says so.

`tests/unix-installer.sh` runs this login end to end with real Git and Stow.

On a host with `DOTFILES_AUTO_STOW=0` (or `DOTFILES_AUTO_UPDATE=0`, after a
pull by hand), nothing removes the old links: the kit's installer refuses a
link it does not own, Stow's included, so its install fails until you run
`./stow-all.sh <host>` and then `sync-payloads`. A host that kept the skill
sync off with `AWESOME_SKILLS_AUTO_UPDATE=0` must export one of the
[knobs](#knobs) above before that login, or the shim installs all three.

### Native Windows

1. The login that pulls runs the profile it read before the pull. Its
   `scripts/dotfiles-update.ps1` fast-forwards (the leftover checkouts are
   ignored) and queues the elevated restow, which the `Dotfiles-Restow-*` task
   ([HW-auto-stow-task](bootstrap.md#hw-auto-stow-task-automatic-stow-task))
   or the next elevated `.\stow-all.ps1 win` runs.
2. The new `stow-all.ps1` removes the links it made from the two retired
   packages, each only while it is a symlink whose text is exactly the path it
   wrote, `<clone>\common\<package>\<path>`, dangling or not, then the same
   four directories once empty, and stows. It installs nothing: an installer
   run elevated would leave Administrators-owned clones.
3. From the next ordinary interactive PowerShell 7 on, the new profile's
   payload hook installs every absent item in the foreground; on most hosts
   that is all three, since the old skill hook ran only on Unix. Until the
   restow has synced the new `settings.json`, the live one still names
   `~\.claude\dotfiles\`, whose links dangle, so Claude's status line and
   hooks fail until then.

### The transition shim

`scripts/awesome-skills-update.sh` exists only for step 3 on Unix: the rc
files a host read before the pull source that path. Remove it once every host
has logged in since the change. A host that logs in first after it is gone
skips the payload hook in that login (the old rc files only source a readable
file) and installs the payloads one session later.

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
- The doctor's `submodule` row (`./doctor.sh`, `.\doctor.ps1`) warns for each
  one, with the commands that show whether it holds work of yours
  (`git -C <path> status`, `git -C <path> log --branches --not --remotes`) and
  the `rm -rf <path>` (`Remove-Item -LiteralPath <path> -Recurse -Force` on
  Windows) that removes it. Nothing removes a checkout or a repository under
  `.git/modules` automatically.

`git -C ~/dotfiles status --porcelain --ignored -- common` lists each leftover
as an ignored (`!!`) path. Once a checkout holds nothing you want, run the
command the doctor prints. Its repository under `.git/modules` can go the same
way once no other leftover uses it: both kit leftovers share one, so remove
it only after both checkouts are gone. Keep the `.gitignore` and `.stowrc`
lines until no host has a leftover.

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
- The fzf-tab preview in `common/zsh/.oh-my-zsh/custom/fzf-tab.zsh` runs
  `codex-as --account-info NAME` or `claude-as --account-info NAME` for an
  account, offline and without opening a credential, so emails and labels
  show in previews, screen shares and agent transcripts; no token is printed.
- The launchers color their messages by `CODING_AGENT_KIT_COLOR`, not
  `DOTFILES_COLOR`.
- Develop the kit in a clone of its own. Never edit its managed root: its
  `releases/` are exported trees that the next switch replaces.

## Verify

```sh
sync-payloads                                   # each item: installed, updated or already current
./doctor.sh --host <host>                       # payloads ok; submodule ok once no leftover is left
ls ~/.claude/coding-agent-kit/                  # check-git-hooks.cjs notify.cjs statusline.cjs
readlink ~/.local/bin/codex-as                  # a path in the kit's managed root, .../current/bin/codex-as
ls -l ~/.pymolrc ~/.pymolrc.py                  # regular files
cat "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/payload/payload.log"   # the last background refresh
```

On Windows: `sync-payloads`, `.\doctor.ps1`, and
`Get-ChildItem $HOME\.claude\coding-agent-kit`.
