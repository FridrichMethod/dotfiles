# Stage 4 operator takeover and recovery

This procedure is for the reviewed compatibility release, with the physical
`common/` and host paths still present. It is not permission to skip candidate
CI, import whole application directories, or force a whole-home apply. The
Stage 4 bridge `9c1a31f` passed exact hosted CI/e2e and reached main. Actual-home
acceptance remains separate: subsequent preflight found that plain native apply
changes existing shared-directory modes. Use the corrected file-only procedure
below only from its reviewed, green release. Final recovery/native release hashes
remain pending that acceptance record.
See [status](status.md) for actual host outcomes and [fleet order](fleet-rollout.md).

The native floor is chezmoi 2.74.0. Bash 3.2, tmux 2.6, PowerShell 7 entrypoints
and PowerShell 5.1's existing profile remain supported at their current floors.
Use separate native Windows and WSL homes/checkouts. An independent local clone
is required for Git writes when the installed checkout is under OneDrive.

## Prepare the reviewed bridge

1. Confirm the candidate's Linux, macOS, Windows and bootstrap e2e gates at its
   exact commit. Preserve all current checkout changes and unpushed commits.
   A fresh clone does not repair existing HOME links or generated overrides.
2. Bring the checkout to the compatible bridge without deleting legacy paths.
   Before this bridge, historical scripts do not understand the marker below.
   Keep `DOTFILES_AUTO_UPDATE=0` and `DOTFILES_PAYLOAD_AUTO_UPDATE=0` in the
   maintenance session, and establish persistent opt-outs in the existing
   user-controlled login environment if the old checkout cannot yet use the
   bridge. Inspect both actual profile callers; do not write through a Stow link
   into tracked source to create a machine-specific opt-out.
3. Once the bridge is available, create the persistent marker below, then verify
   a second fresh process cannot start either hook. Do not convert any target
   until this works. Marker existence is enough, including an invalid file or
   dangling link, so a partial handover remains closed to old writers.

```sh
umask 077
mkdir -p "$HOME/.config/dotfiles"
: > "$HOME/.config/dotfiles/maintenance"
```

Windows uses the same relative path under the actual user profile; create it
unelevated under that user and inspect its inherited ACL. No global task or
wildcard process operation is part of maintenance.

Inspect the checkout's exact `git rev-parse --git-path dotfiles-sync-unix.lock`
and its `pid`, then match owner, start time, full command and ancestry. A PID by
itself may be stale/reused. Let the identified updater finish; do not kill an
unrelated process. Inspect payload `--worker` / `-Worker` command lines and their
exact source checkout too: payload workers have no consumer lock. Recheck after
waiting. A marker prevents new workers; it cannot cancel one already executing.

On Windows, dot-source `scripts/dotfiles-auto-stow.ps1` without switches and use
`Get-DotfilesTaskName -Repo $source`. Inspect that exact task's principal, action
program, arguments and source path. Disable only that matching task, then wait
until its exact owned running action finishes. Refuse an ownership mismatch.
Keep it disabled throughout native operation; deregistration belongs to Stage 6.
The native path never registers or starts an elevated task and never prompts UAC.

Sherlock requires current site/topic rules through the user's existing master;
jobs/transfers use the project's pinned toolkit where applicable. Do not
authenticate, create environments on login nodes, use scratch for environments,
or start a detached updater contrary to site rules. Read Marlowe rules too.

## Resolve the home and inspect exact targets privately

The operator chooses one explicit role: `common-only`, `mac`, `wsl-ubuntu`,
`lab-ubuntu`, `sherlock`, `marlowe`, or `win`. OS detection validates this choice;
`DOTFILES_HOST` does not select native data. Use canonical absolute paths without
line breaks for the source checkout and destination home.

On Windows, query both actual profiles without loading their contents:

```powershell
pwsh -NoProfile -NonInteractive -Command '$PROFILE.CurrentUserAllHosts'
powershell.exe -NoProfile -NonInteractive -Command '$PROFILE.CurrentUserAllHosts'
```

Require `$HOME/Documents/PowerShell/profile.ps1` and
`$HOME/Documents/WindowsPowerShell/profile.ps1` respectively. A redirected
Documents path blocks this fixed mapping until explicitly modeled and retested.
Inspect destination ACLs under the real ordinary user, not merely an administrative
SSH token. Ordinary-user token/ACL validation is a separate recorded gate.

Use [inventory](inventory.md)'s exact selected destination set. For each target,
privately record type, original link text, exact canonical owner, referent bytes,
mode and Windows ACL where applicable. The private backup must be outside the
source tree and protected by 0700/0600 or equivalent reviewed ACLs. Preserve
stricter/read-only modes for explicit review. Stop on directories, unreadable
files, foreign links, unexpected ownership or concurrent source/app edits.

An ordinary link is eligible only when its resolved referent equals that target's
exact inventoried canonical legacy file. A link merely pointing somewhere inside
the checkout is insufficient. Private snapshots must preserve the original link
text as well as the bytes. Review regular-file drift privately before apply.
Do not include whole `.claude`, `.codex`, `.ssh`, `.secrets` or payload directories.

**Fresh-state warning:** native `--error-on-conflict` is not an ownership check.
With no previous native state, v2.74.0 can replace a preexisting symlink, even a
foreign link, on first apply. Stage 1's refusal followed `add --follow` and recorded
state; that result was narrower. Never run first apply to discover foreign links.
Do not use `add --follow` on the two modify templates: it is content import, not
takeover, and may conflict with or replace the intended source representation.

Privately preflight the two AI inputs. Local TOML dates/times/datetimes and JSON
U+FFFD remain unsupported; do not bypass their guards or use TZ as a fix. Native
canonicalization removes TOML layout/comments. Back up and review those changes.
Only a nonsecret explicit target allowlist may be diffed into ordinary logs.
Even native errors may include input text; capture real diagnostics privately.

Review the native umask against every original target mode. Native ordinary files
follow the selected umask; private attributes alone do not protect other files.
For the inspected personal homes, local `umask = 0o077` keeps ordinary files at
0600 and executable files at 0700, avoiding wider access than the existing 0600
targets. Set this in the local native config after review, without changing the
shell's umask or shared parent permissions. Init preserves the local setting.
Existing read-only or otherwise stricter targets still require explicit review.

Inspect historical `AGENTS.override.md` against the exact generated marker in
the old installer; a user-owned override is not removable. Inspect local
`filter.codex-portable`, old opt-outs and exact retired package links. Preserve
custom content, old checkouts and module stores. Do not port automatic historical
repair into the native path or delete residue merely because it is old.

## Initialize and establish one writer

After backups and quiescence, seed the local config with only the explicitly
selected `[data].host` if it does not exist. If it exists, review and edit it
privately instead of overwriting unknown encryption or local settings. The
following paths are fixed by the adapter contract, independent of XDG overrides:

| Purpose | Path |
| --- | --- |
| Source | Canonical repository root, with `.chezmoiroot=home` |
| Destination | Canonical actual home |
| Config | `HOME/.config/chezmoi/chezmoi.toml` |
| Cache | `HOME/.cache/chezmoi` |
| State | `HOME/.local/state/chezmoi/chezmoi.boltdb` |
| Ownership | `HOME/.config/dotfiles/native` |
| Maintenance | `HOME/.config/dotfiles/maintenance` |

Run `init` with the explicit source, destination, config, cache and state arguments
below. It uses the repository template to set the chosen role, source/destination,
regular-file mode, disabled Git auto-add/commit/push and the tested fast-forward-only update command.
The template preserves local age/backend/data and unrelated settings through
native TOML, including repeated init. It canonicalizes formatting and refuses
local TOML date/time/datetime before changing the config, just as the Codex
transform does. Review local encryption configuration after init. No package
installation, secret enrollment or authentication is an apply hook.

```sh
chezmoi --source "$source" --working-tree "$source" \
  --destination "$destination" --config "$config" --cache "$cache" \
  --persistent-state "$state" --mode=file --no-tty --error-on-conflict --force=false \
  --no-pager --use-builtin-diff init </dev/null
```

Before the first managed destination mutation, write the ownership file privately as
exactly three UTF-8 LF-terminated lines: `dotfiles-chezmoi-v1`, canonical
destination, canonical source. It is local metadata, never a managed target or
revision receipt. Keep the maintenance marker in place. Every legacy installer,
sync wrapper/backend, updater and scheduled `-Apply` refuses marked destinations;
direct helper LIVE arguments are checked independently of the invoking HOME.

```sh
printf '%s\n' dotfiles-chezmoi-v1 "$destination" "$source" \
  > "$destination/.config/dotfiles/native"
chmod 600 "$destination/.config/dotfiles/native"
```

Plain native apply also manages directory modes and can broaden an existing
0700 parent or try to chmod a shared, differently owned parent. The supported
operator and login-update commands therefore explicitly exclude directory
entries. There is no effective equivalent configuration key in the tested
release; bare `chezmoi apply` is not this procedure.
Keep `--force=false` explicit on all non-conversion commands, including directory
preparation, regular/full apply and diff; preserved local config may set force.
Only an individually reviewed link conversion replaces it with `--force=true`.

Before file apply, obtain the exact native directory set with the same explicit
arguments and `managed --include=dirs --nul-path-separator`. Inspect each path
relative to the canonical destination, not the current directory, and inspect
every ancestor using lstat, distinguishing an absent path from a dangling
link, Windows junction/reparse point, foreign object or inaccessible parent.
Preserve all existing real directory modes and ACLs. For only the reviewed,
still-absent directories, use native
`apply --include=dirs --recursive=false EXACT_ABSENT_DIR...`; do not pass an
existing shared directory. If the missing list is empty, skip this command:
zero targets would select every directory. Native source attributes create new private parents
at 0700. Recheck absence and ancestors immediately before creation; never use
force. A missing parent cannot be created by the file-only apply below.

Because directory entries are excluded thereafter, verify existing private
secret parents are owned real 0700 directories before enrollment. Exclusion
does not repair an unsafe mode. Never silently chmod a shared existing parent.

Privately dry-run the selected two AI targets with the same explicit arguments
and `apply --exclude=dirs --dry-run TARGET`. After reviewing each exact owned link and its
snapshot, use the same command with `apply --force "$target"` for that single
link only, also passing `--exclude=dirs`. Repeat individually. For ordinary
existing regular files use `apply --exclude=dirs "$target"` after review,
without force. Never force a directory or the
whole home. Native failures may leave earlier targets changed; keep both markers.

Once every target is reviewed, run full `apply --exclude=dirs` with the same
arguments, then run it again and require an empty nonsecret targeted
`diff --exclude=dirs`. On Windows invoke
the equivalent argument array using PowerShell without elevation, with closed
stdin. Keep successful old SSH access until a genuinely fresh ordinary connection
passes; site/MFA master-only checks retain their documented limit.

Run applicable shell/profile/application and fresh-access checks while maintenance
is active. A headless SSH command is not a GUI reload check. Then remove the exact
maintenance file for controlled activation and test the thin updater from a fresh
interactive process with `DOTFILES_AUTO_UPDATE` enabled and `_DOTFILES_CHECKED`
unset; keep payload automatic updates disabled during this probe. A call skipped
by maintenance or an opt-out proves only suppression. Inspect warnings and actual
source/state/target outcomes: the adapter intentionally preserves a usable shell
exit status on failure. Restore maintenance immediately if activation fails.
Only after acceptance restore intended session opt-outs. Keep the native marker
and legacy Windows task disabled. Record actual results for each host separately.

## Updates and edits after takeover

Interactive startup invokes `scripts/chezmoi-update.sh` or `.ps1` once per
session. It uses the marker's source rather than a stale `DOTFILES_DIR`, refuses
dirty tracked/untracked source, missing/empty native state and OneDrive source writes,
and validates the safe native update override before calling it. Routine updates
pin `--mode=file` even when an older local config selected symlinks, and use
`--less-interactive --no-tty --error-on-conflict --force=false` together:
`--error-on-conflict` alone does not protect an existing target newly introduced
by an upstream revision, even with a populated state database. The native
less-interactive mode rejects that first-target conflict while allowing genuinely
absent new targets and ordinary known updates. A source fast-forward can succeed
before apply refuses a target; no whole-home transaction is promised. It disables
credential prompts and uses transport timeouts. Arbitrary user Git hooks are not
a globally bounded execution environment. Errors produce a generic warning;
secret-bearing native output is not printed. A later session may retry.

The update invocation also pins `--exclude=dirs` to preserve shared parent modes
and ACLs. New files under existing prepared parents can update automatically.
An upstream file under a missing parent requires the reviewed directory-only
preparation above before retrying. Such a failure may follow a Git fast-forward
or earlier file changes; it is not a transactional refusal. Do not remove the
exclusion, delete state, or run plain apply to bypass it. Reconcile and require
full file convergence after preparing the exact missing directories.

`DOTFILES_AUTO_UPDATE=0` disables native login updates. `DOTFILES_AUTO_STOW` and
`DOTFILES_HOST` remain legacy-only. Payload lifecycle is unchanged except for
maintenance; its separate Stage 5 decision is still open. No new scheduler,
revision acknowledgement database or background supervisor is introduced.

Regular-file edits no longer write through to Git. During the bridge, ordinary
portable edits belong in the canonical legacy source and then native apply.
Review live app changes with a private targeted diff/merge. Do not blindly
`add` an AI config or replace its modify template with a snapshot of local state.
Source consolidation belongs to Stage 6.

## Recovery preserves edits made since backup

Keep maintenance active and the native marker present after any partial failure.
Snapshot the current target separately before attempting recovery. Compare it
privately with the original snapshot and intended native result. If an app has
edited it, preserve that edit and reconcile under the native writer; never
restore an old symlink over it. The recovery fixture explicitly exercises this.

Only when the current bytes/modes have been reconciled and that exact original
owner is still valid may the operator restore the original link text. Old writers
stay disabled until all restored targets are checked. Removing the native marker
is an explicit last recovery step, never an automatic response to a failed apply.
Do not revert Git and blindly restow, delete native state to clear conflicts, or
discard backups. State loss requires inspected recovery before unattended update.

An offline installation can skip this bridge and pull a future deletion commit;
the support cutoff cannot prevent that. Preserve it, recover from a clean local
clone and exact private snapshots, and prepare HOME destinations individually.
Do not claim that an unobserved or blocked host migrated successfully.
