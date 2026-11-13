# Login updates

A login updates only a home whose chezmoi config names it and a dotfiles
checkout, through that checkout's updater. This page is the contract of that
update, of the manual chezmoi commands that share its state, and of the
maintenance marker that pauses both.

## Trigger

- Only interactive shells update. `~/.profile` (`home/dot_profile`) dispatches
  for sh and Bash; zsh dispatches from the tail of `~/.zshrc`, after ssh-agent
  and the host environment are ready; PowerShell 7 dispatches from the tail of
  its profile, only under `$IsInteractive` (console stdin and stdout and a
  loaded PSReadLine), so `-File`, `-Command`, `-NonInteractive` and piped input
  never update. The Windows PowerShell 5.1 profile has no update hook.
- One attempt per session: the updater exports `_DOTFILES_CHECKED`, and a
  nested shell that inherits it does not try again.
- `DOTFILES_AUTO_UPDATE=0` disables the hook. No other variable selects a
  host or a checkout.
- The deployed hook runs the checkout's updater as the checkout holds it
  before the pull, so a change to the updater or the guard takes effect at
  the login after the one that pulled it.

## Selection

- Maintenance comes first: while `~/.config/dotfiles/maintenance` exists, in
  any form, nothing runs ([Maintenance](#maintenance)).
- The source is the checkout `~/.config/chezmoi/chezmoi.toml` names. The
  profile reads only its first top-level `sourceDir` line, to find that
  checkout's guard (`lib/chezmoi-guard.sh` or `.ps1`), which validates the
  whole config, as text and without running chezmoi, before the checkout's
  `scripts/chezmoi-update.sh` or `.ps1` runs; the updater takes every path
  from the validated result.
- Only the form `chezmoi init` writes through `home/.chezmoi.toml.tmpl`
  passes: a regular file, not a link, whose lines before the first table hold
  exactly one `sourceDir = "VALUE"` and one `destDir = "VALUE"` line at column
  0, with LF line ends and no quote, backslash or control character in VALUE.
  `destDir` is the canonical home; `sourceDir` is a canonical checkout root
  holding `.chezmoiroot` (and `.git` under PowerShell). On Windows the values
  are `C:/...` paths, compared with backslashes and ignoring case. A top-level
  `workingTree` key, any other spelling of the three keys, a line starting
  with a quote and a multi-line string before the first table are refused. A
  hand edit that leaves this form disables updates with a warning; a
  [re-init](#re-init-after-a-config-template-change) restores it once every
  `workingTree` key and any key that needs quotes (a re-init keeps both) and
  any second spelling of a key (a re-init stops at it) are removed by hand.
- A config the guard refuses prints one warning and runs nothing.
- A home without `~/.config/chezmoi/chezmoi.toml` runs nothing and prints
  nothing. There is no fallback to `~/dotfiles`, an environment variable or
  any other checkout.

## Refusals

The updater stops, with a warning and without touching the destination, when:

- the source has tracked or untracked changes (ignored files do not count:
  `home/.chezmoiignore` repeats the `.gitignore` patterns, so none deploys;
  one in `home/.chezmoidata/` is read as data and makes the apply fail);
- the state database (`~/.local/state/chezmoi/chezmoi.boltdb`) is missing or
  empty, because lost state can turn a foreign target into a first apply
  ([Lost state](#lost-state));
- the source path contains OneDrive (use an independent clone on local disk);
- the effective update configuration is not the safe one below;
- on Windows, `~/.local/bin/chezmoi.exe` is missing, a link, or owned or
  writable by an account other than you, SYSTEM and Administrators. Only that
  file runs, never a PATH match
  ([W1-chezmoi](bootstrap.md#w1-chezmoi-chezmoi-binary-on-windows)).

## Invocation

- Every run passes the full explicit argument set: `--source`,
  `--working-tree`, `--destination`, `--config`, `--cache` and
  `--persistent-state` of the home, so inherited XDG or chezmoi settings
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
- `--less-interactive --no-tty --error-on-conflict --force=false` work
  together: `--error-on-conflict` alone does not protect an existing target
  that an upstream revision newly introduces, even with a populated state
  database; less-interactive mode refuses that first-target conflict while it
  allows genuinely absent new targets and ordinary known updates.
- Transport is limited: an SSH connect timeout and an HTTPS low-speed abort
  end normal network failures, and on Windows each chezmoi process, with its
  children, is killed after 60 seconds. An SSH session that stalls after
  connecting, or an HTTPS connect to a silently dropped route, can wait for
  the operating system's defaults.

## Failure

- A failure prints one generic warning; chezmoi's and Git's output, which can
  carry secrets, is never printed.
- On Unix the login warnings go through `lib/terminal.sh` of the checkout
  the guard accepted, so they follow `DOTFILES_COLOR`, `NO_COLOR` and `TERM`;
  a refused config's warning is a plain line, since no code runs from a
  checkout the guard refused.
  Under Powerlevel10k's instant prompt, whose capture file stands in for
  stderr during zsh startup, `~/.zshrc` colors them when the stderr p10k
  saved is a terminal. On Windows they go through `lib/terminal.ps1`'s
  `Write-DotfilesWarning`, on stderr with the same rules.
- The shell stays usable, the PowerShell profile keeps the caller's
  preferences, and the next session retries.
- A source fast-forward can succeed before apply refuses a target. The update
  is not a whole-home transaction.

## New targets

A target added to the source reaches every home through this update,
which stops on it when:

- its parent directory is missing: an operator first prepares exactly that
  directory ([Preparing missing parents](bootstrap.md#preparing-missing-parents)),
  since the update excludes directories;
- an unmanaged file already sits at its path: that first-target conflict
  waits until it is reconciled ([Editing and adding files](#editing-and-adding-files)).

On Windows, a new target under an existing parent inherits that parent's ACL.
Name the parent's ACL model for each new Windows target, and when the parent
is broader than the intended file ACL, materialize the file under a reviewed
protected ACL instead of relying on inheritance.

## Editing and adding files

Deployed files are regular files: an edit of one does not reach Git. Edit
the source instead (ordinary files under `home/`, role variants under
`home/.hosts/<role>/`, portable AI policy under `home/.policy/`), commit,
land it through CI ([AGENTS.md](../AGENTS.md#workflows-and-checks)), and
every home receives it at its next login. `chezmoi edit` of a role-variant
target opens its one-line template, so edit the `.hosts` file instead. To
add a target, follow the checklist in the
[README](../README.md#checks-and-contribution) and [New targets](#new-targets).

A local edit of a deployed target (an application, an installer, a hand
edit) is a change since the last write, at which the next nonforce login
update stops; later targets stay stale until it is resolved. Review it with a
private targeted diff from the clone (`home_cz diff --exclude=dirs TARGET`,
Windows `Invoke-HomeCz @('diff', '--exclude=dirs', TARGET)`), then either:

- keep it: put the change into the source and land it; once the home has
  the new revision, the target matches again; or
- drop it: back the file up privately with its mode, then apply only that
  target with `home_cz apply --exclude=dirs --force TARGET`, never a
  whole-home force.

Never `add` an AI config or replace its modify template with a snapshot of
local state; an owned AI-config key has its own
[reconciliation](ai-config.md#reconciling-an-owned-key).

### Merge and apply

chezmoi's `merge TARGET` opens a three-way merge of the live file, the
source and the target state in a merge tool (vimdiff by default) and writes
the result into the source file; it suits an ordinary file, not a
role-variant template or a modify template. The merge tool needs a terminal,
and `home_cz` and `Invoke-HomeCz` close stdin, so run `merge` from an
interactive terminal in the clone with the same binary (`~/.local/bin/chezmoi`,
else the one on PATH), the same six path flags and `--force=false`, without
either function:

```sh
src=$(pwd -P) && dst=$(cd -P -- "$HOME" && pwd -P) &&
    bin=$dst/.local/bin/chezmoi && { [ -x "$bin" ] || bin=$(command -v chezmoi); } &&
    "$bin" --source "$src" --working-tree "$src" --destination "$dst" \
        --config "$dst/.config/chezmoi/chezmoi.toml" --cache "$dst/.cache/chezmoi" \
        --persistent-state "$dst/.local/state/chezmoi/chezmoi.boltdb" \
        --force=false merge TARGET
```

(On Windows, `~\.local\bin\chezmoi.exe` with the same flags.) Or review
`home_cz diff --exclude=dirs TARGET` and edit the source file by hand.
Either way the result goes into the source only. The live file keeps the
local edit, so it differs from both the last write and the new target, and
the nonforce login update stops at it. Commit what changed and land it; once
the home has that revision, back the live file up privately with its mode,
review `home_cz diff --exclude=dirs TARGET`, and apply only that target with
`home_cz apply --exclude=dirs --force TARGET`. A merge tool can also save the
result into the live file; the target then matches once the revision lands,
as when keeping a change. Run every apply with `--exclude=dirs`; a missing
parent goes through
[Preparing missing parents](bootstrap.md#preparing-missing-parents) first.

### Manual commands

Run every mutating chezmoi command (`init`, `apply`, `update`, `add`,
`re-add`, `edit`, `merge`, `forget`, `state`) with the updater's full
explicit argument set: `--source`, `--working-tree`, `--destination`,
`--config`, `--cache` and `--persistent-state` as in
`scripts/chezmoi-update.sh`/`.ps1`, `--exclude=dirs` on file apply, diff and
update, and `--force=false` except on the single reviewed target of a
reconciliation. Every `update` and file `apply` on a deployed home also
passes the updater's mode flags `--less-interactive --use-builtin-age=true
--use-builtin-git=false`: without `--less-interactive`, a target an upstream
revision newly introduces silently replaces an unmanaged file already at its
path ([Invocation](#invocation)). Only a first apply
([Fresh home by hand](bootstrap.md#fresh-home-by-hand), [Lost state](#lost-state))
omits it, because less-interactive mode refuses every existing file a first
apply has to replace. A forced apply of the single reviewed target does not
need it.

From the clone, `home_cz ARGS...` (Windows `Invoke-HomeCz @(ARGS)`) from
[Fresh home by hand](bootstrap.md#fresh-home-by-hand) passes the six paths and
`--mode=file --no-tty --error-on-conflict --force=false --no-pager
--use-builtin-diff`, with stdin closed, but not the mode flags: write
`home_cz --less-interactive --use-builtin-age=true --use-builtin-git=false
apply --exclude=dirs` (Windows `Invoke-HomeCz @('--less-interactive',
'--use-builtin-age=true', '--use-builtin-git=false', 'apply',
'--exclude=dirs')`). `edit` and `merge` open an editor or a merge tool, so
they run from an interactive terminal with the same paths instead
([Merge and apply](#merge-and-apply)). Explicit paths keep inherited XDG or
chezmoi settings from redirecting a command and win over the config; the
login updaters pass every one. On Windows invoke `~/.local/bin/chezmoi.exe` by
full path, never `chezmoi` through PATH.

The config `chezmoi init` writes names the source, the destination and the
state database (`persistentState`), so plain read-only checks
(`status --exclude=dirs`, `diff --exclude=dirs`, `managed`, `data`,
`execute-template`) need no path flags; keep `--force=false` on diff. Do not
run a manual apply while a login update runs.

## Maintenance

`~/.config/dotfiles/maintenance` (Windows: the same path under the user
profile) is an operational pause switch. While it exists in any form, a
regular file, an invalid file, a directory or a dangling link, the login
hook runs nothing, `sync-payloads` and the payload hooks refuse, and the
doctor's `chezmoi-config` row is `human`. Create it as the user, unelevated:

```sh
umask 077
mkdir -p "$HOME/.config/dotfiles"
: > "$HOME/.config/dotfiles/maintenance"
```

Verify that a fresh interactive process then starts no update. The marker
stops new runs; it cannot cancel one already executing, so let a running
updater finish. Remove the exact file to resume; nothing removes it
automatically, a failed update included.

### Rolling out a breaking change

A landed change that cannot reach a host safely through the deployed hook
(the hook runs the pre-pull updater, see [Trigger](#trigger); or the change
needs a re-init or a directory preparation on each host) rolls out under
maintenance:

1. Put the marker on every host and confirm each by exit status (Unix
   `test -e`, Windows `Test-Path` in a limited-token task,
   [hosts](hosts.md#win)). Push the candidate to its `ci/**` and `e2e-ci/**`
   branches meanwhile, but move `main` only when every marker is confirmed:
   a host that cannot get one blocks the landing, because the next
   interactive login there would run its deployed updater against the new
   `main`.
2. Fast-forward `main` to the green candidate.
3. Per host, one owner at a time: from the checkout, run the update the
   login updater runs, with its explicit arguments
   ([Manual commands](#manual-commands)):

   ```sh
   home_cz --less-interactive --use-builtin-age=true --use-builtin-git=false \
       update --apply --exclude=dirs --recurse-submodules=false
   ```

   (Windows `Invoke-HomeCz` with the same arguments, in a limited-token
   task.) On a partial apply, prepare any missing parent it stopped on and
   reconcile any first-target conflict, then finish with
   `home_cz --less-interactive --use-builtin-age=true --use-builtin-git=false
   apply --exclude=dirs`, never by restoring old code. Then re-init if the
   config template changed. Check that HEAD is the new `main` and
   `home_cz status --exclude=dirs` is empty.
4. Remove the marker and prove the deployed hook and the new updater from a
   fresh interactive shell, as the host's probe method says
   ([hosts](hosts.md#probe-methods)). On win, a limited-token task can launch
   a separate ordinary-user console for this proof
   ([PowerShell 7 console acceptance](hosts.md#powershell-7-console-acceptance)):
   exit 0, no `[dotfiles]` line on stderr, HEAD at `main` and a clean status.
   On failure, restore the marker and finish by explicit commands.
5. Once every host is accepted (step 4 of
   [Rolling out a landed change](hosts.md#rolling-out-a-landed-change)) and
   the landing's `ci/**` and `e2e-ci/**` branches are deleted
   ([AGENTS.md](../AGENTS.md#workflows-and-checks)), prune each host's
   checkout:

   ```sh
   git -C ~/dotfiles fetch --prune origin
   ```

   On Windows run `git -C (Join-Path $HOME dotfiles) fetch --prune origin` in
   a limited-token task, since it writes Git metadata
   ([hosts](hosts.md#win)). The login updater's pull fetches every branch
   and never prunes, so a host that fetched while those branches existed
   keeps their `origin/ci/*` and `origin/e2e-ci/*` refs until this fetch
   removes them. It moves no local branch.

### Re-init after a config-template change

`home/.chezmoi.toml.tmpl` owns `sourceDir`, `destDir`, `persistentState`,
`mode`, the owned `[git]` and `[update]` settings and `[data].host`. After
any byte change to it, every manual chezmoi command on every host prints
`config file template has changed` until a reviewed re-init there; the
warning is harmless, and the answer is never a plain `chezmoi init`. Keep
every change to the template in one commit, so each host re-inits once.

1. Precheck, read-only: a clean checkout at `main`, a regular config (not a
   link or directory), a nonempty state database, no other chezmoi running,
   and an empty `home_cz status --exclude=dirs`.
2. Keep a private copy of the config (under umask 077), its key names, and
   the modes or ACLs of the config and the state database. Copy without
   `cp -p`: Marlowe's filesystem refuses permission and ACL preservation, and
   a copy made under umask 077 is private anyway.
3. Run, from the clone, `home_cz init` (Windows `Invoke-HomeCz @('init')`),
   which passes `--source`, `--working-tree`, `--destination`, `--config`,
   `--cache`, `--persistent-state` and `--mode=file --no-tty
   --error-on-conflict --force=false --no-pager --use-builtin-diff`.
4. Postcheck: the key diff shows only the expected changes; the guard
   accepts the config (from the clone,
   `sh -c '. ./lib/chezmoi-guard.sh && dotfiles_chezmoi_source "$HOME"'`
   prints the clone; Windows
   `. .\lib\chezmoi-guard.ps1; (Get-DotfilesChezmoiPaths -HomePath $HOME).Source`);
   full-argument and plain `status --exclude=dirs` are empty, with empty
   stderr; plain `execute-template '{{ .chezmoi.config.persistentState }}'` names
   `~/.local/state/chezmoi/chezmoi.boltdb`. Roll back by restoring the copy in
   place.

On Windows run it as the ordinary user in a limited-token task
([hosts](hosts.md#win)) and keep the copy under `~/.config`, not `~/.local`.
A re-init resets every value the template owns, folding a single other
spelling of each key, keeps every other key, a top-level `workingTree` key
included, and fails, leaving the config unchanged, when a key the template
owns has two spellings: first remove by hand every spelling of
`workingTree`, the second spelling and any key that needs quotes.

## Lost state

With no state database, chezmoi has no record of what it last wrote: a first
apply then replaces a preexisting file, or even a foreign symlink, without
asking (`--error-on-conflict` is not an ownership check), which is why the
updater refuses a missing or empty database. After the database is lost, run
no plain read-write chezmoi command (`init`, `apply`, `update`, `add`,
`edit`, `re-add`, `merge`, `forget`, `state`), even when chezmoi suggests
`chezmoi init`: a plain `init` can recreate the database with only its config
state, which re-arms the unattended updater without a review. Plain
read-only commands (`status`, `diff`, `managed`, `data`, `execute-template`)
are fine. Recover under maintenance as a first apply: inspect every managed
path privately, keep private copies of the files an apply would replace,
apply with the full argument set and `--exclude=dirs` twice, without
`--less-interactive` (`home_cz apply --exclude=dirs`), require an empty diff,
then remove the marker. Never delete state to clear a conflict.

## Known limits

- On macOS and Windows, where Git matches `.gitignore` case-insensitively, a
  case variant of an ignored name (`dot_zshrc.ORIG`) is ignored by the
  clean-tree check but deploys, since `home/.chezmoiignore` matches case
  exactly. Remove such a file from the checkout.
- Any file in `home/.chezmoidata/`, an editor backup or merge file included,
  is read as template data, so a stray one there stops every run (it fails
  closed) until it is removed.
- The Windows exact-exe check narrows the window in which a writer of
  `~/.local` could swap `chezmoi.exe`, but does not close it
  ([W1-chezmoi](bootstrap.md#w1-chezmoi-chezmoi-binary-on-windows)).

## Not provided

No scheduler, locks, retries within a session, elevation or payload runs.
The payload repos install only when a person runs `dotfiles payloads sync`
or `sync-payloads`; the internal command backends are distinct from the stable
login lifecycle hooks. See
[payloads.md](payloads.md).

## Coverage

- `tests/test_chezmoi_update_unix.py`, `tests/test_chezmoi_update_windows.py`
  and `tests/test_chezmoi_missing_parents.py`: the updaters against real
  local remotes and disposable homes, refusals, divergence, conflicts and the
  PowerShell profile tail.
- `tests/test_chezmoi_update_config.py`: the safe update configuration.
- `tests/test_chezmoi_guard.py`: the config validation (every refusal) and
  the sh and Bash login dispatch, with and without the Sherlock overlay.
- `tests/test_chezmoi_provision.py`: the validation against real `chezmoi
  init` output.
- `tests/shell-profile.sh`: the login dispatch under sh, dash, Bash and zsh:
  quiet without a config, one warning for an invalid one, the configured
  checkout's updater for a valid one.
- `tests/powershell-profile.ps1`: the PowerShell 7 tail's structure and
  placement.
