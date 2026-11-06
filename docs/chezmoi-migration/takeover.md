# Stage 4 operator takeover and recovery

This procedure is for the reviewed compatibility release, with the physical
`common/` and host paths still present. It is not permission to skip candidate
CI, import whole application directories, or force a whole-home apply. The
corrected Stage 4 release `bf9995809ca7564c0728f87bcbefe91c8a3cc5e0` passed exact
hosted CI/e2e and lab ordinary takeover. It is the supported Stow recovery bridge
and first accepted ordinary-native release. All six hosts have since accepted
takeover: per-host acceptance is in [stage-4-evidence.md](stage-4-evidence.md#actual-fleet-outcomes-separate-from-fixtures),
the current state in [status.md](status.md). Plain native apply changes existing shared
directory modes; use the corrected file-only procedure below.
See [status](status.md) for actual host outcomes and [fleet order](fleet-rollout.md).

The native floor is chezmoi 2.74.0. Bash 3.2, tmux 3.4, PowerShell 7 entrypoints
and PowerShell 5.1's existing profile remain supported at their current floors
(W1-chezmoi and `sync-payloads` included). Use separate native Windows and WSL
homes/checkouts. An independent local clone is required for Git writes when the
installed checkout is under OneDrive.

## Prepare the reviewed bridge

1. Confirm the candidate's Linux, macOS, Windows and bootstrap e2e gates at its
   exact commit. Preserve all current checkout changes and unpushed commits.
   A fresh clone does not repair existing HOME links or generated overrides.
2. Bring the checkout to the compatible bridge without deleting legacy paths.
   Before this bridge, historical scripts do not understand the marker below.
   Keep `DOTFILES_AUTO_UPDATE=0` in the maintenance session, with
   `DOTFILES_PAYLOAD_AUTO_UPDATE=0` for pre-Stage-5 profile code (current code
   ignores it), and establish persistent opt-outs in the existing
   user-controlled login environment if the old checkout cannot yet use the
   bridge. Inspect both actual profile callers; do not write through a Stow link
   into tracked source to create a machine-specific opt-out.
3. Once the bridge is available, create the persistent marker below, then verify
   a second fresh process starts no update or payload run. Do not convert any
   target until this works. Marker existence is enough, including an invalid file
   or dangling link, so a partial handover remains closed to old writers.

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
unrelated process. Payload `--worker` / `-Worker` processes exist only if
pre-Stage-5 code started them before the checkout reached Stage 5, whose
payload-update script ignores those switches. Inspect any such command line
and its exact source checkout too: payload workers have no consumer lock.
Recheck after waiting. A marker prevents new runs; it cannot cancel one already
executing.

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
serialization removes TOML layout/comments when policy changes require output.
A validated typed no-op preserves the original Claude/Codex bytes. Back up and review
actual changes; this does not bypass target ownership or conflict protection.
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

A fresh home, with no earlier dotfiles install, no Stow links, no local native
config and no binding, has no other writer to quiesce: follow
[Fresh home by hand](../bootstrap.md#fresh-home-by-hand) (Windows:
[Fresh Windows home by hand](../bootstrap.md#fresh-windows-home-by-hand))
instead. It runs the commands below with the same explicit arguments, keeps
private copies of the files the first apply replaces, and needs no maintenance
marker; everything else follows this section.

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
the bound state database (`persistentState`, always
`<destination>/.local/state/chezmoi/chezmoi.boltdb`, with a case variant folded
into it; two variants make init refuse), regular-file mode, disabled Git
auto-add/commit/push and the tested fast-forward-only update command.
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
Only an individually reviewed link conversion, or the reviewed one-file
reconcile below, replaces it with `--force=true`.

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
`diff --exclude=dirs`. On Windows invoke `~/.local/bin/chezmoi.exe` by full
path (if it is absent, follow
[W1-chezmoi](../bootstrap.md#w1-chezmoi-windows-native-chezmoi-binary) first)
with the equivalent argument array using PowerShell without elevation,
with closed stdin. Keep successful old SSH access until a genuinely fresh
ordinary connection passes; site/MFA master-only checks retain their documented
limit.

Run applicable shell/profile/application and fresh-access checks while maintenance
is active. A headless SSH command is not a GUI reload check. Then remove the exact
maintenance file for controlled activation and test the thin updater from a fresh
interactive process with `DOTFILES_AUTO_UPDATE` enabled and `_DOTFILES_CHECKED`
unset; no Stage 5 login starts a payload run. A call skipped by maintenance or an
opt-out proves only suppression. Inspect warnings and actual
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
credential prompts. An SSH connect timeout and an HTTPS low-speed abort bound
normal transport failures; an HTTPS connect to a silently blackholed route, or
an SSH session that stalls after connecting, can still wait for OS/curl/SSH
defaults. That limit is accepted; a portable watchdog would be a Stage 5 design
question. Arbitrary user Git hooks are not
a globally bounded execution environment. Errors produce a generic warning;
secret-bearing native output is not printed. A later session may retry.

Run every mutating manual native command (`init`, `apply`, `update`, `add`,
`re-add`, `edit`, `merge`, `forget`, `state`) with the updater's full explicit
argument set: `--source`, `--working-tree`, `--destination`, `--config`,
`--cache` and `--persistent-state` as in `scripts/chezmoi-update.sh`/`.ps1`,
and follow the `--exclude=dirs` and `--force=false` rules above. Explicit paths
keep inherited XDG or chezmoi settings from redirecting a command and win over
the config; the login updaters pass every one. On Windows invoke
`~/.local/bin/chezmoi.exe` by full path, never `chezmoi` through PATH; the login
updater uses only that file and skips with a warning naming
[W1-chezmoi](../bootstrap.md#w1-chezmoi-windows-native-chezmoi-binary) when it
is missing, linked, or owned or writable by an account other than you, SYSTEM
and Administrators. `doctor.ps1` then reports `native-config` as `human` and
`setup-host.ps1` keeps W1-chezmoi todo until a private copy is there.

`home/.chezmoi.toml.tmpl` owns `persistentState`; a host must pick it up only
through a reviewed re-run of the init command above. Until then manual native
commands print `config file template has changed`, which is harmless; do not
answer it with a plain `chezmoi init`. Before the re-init, a command without the
full argument set also uses chezmoi v2.74's separate state database beside the
config, `$HOME/.config/chezmoi/chezmoistate.boltdb`, so a plain `chezmoi apply`
or `chezmoi update` can overwrite local edits without the
changed-since-last-write refusal and later stall the login updater. After
the re-init, plain commands share the bound config, source, destination and
state database, and plain read-only checks (`status --exclude=dirs`,
`diff --exclude=dirs`, `managed`, `data`, `execute-template`) need no path
flags; keep `--force=false` on diff.

On an otherwise healthy bound home, the doctor's native-config row warns,
offline, while that `chezmoistate.boltdb` exists; it never removes the file.
To clear the warning, privately record the file's sha256, mode and owner, run
the reviewed re-init, require both full-argument and plain
`status --exclude=dirs` to be empty, then move the file into a private record
directory; never delete it.

The update invocation also pins `--exclude=dirs` to preserve shared parent modes
and ACLs. New files under existing prepared parents can update automatically.
An upstream file under a missing parent requires the reviewed directory-only
preparation above before retrying. Such a failure may follow a Git fast-forward
or earlier file changes; it is not a transactional refusal. Do not remove the
exclusion, delete state, or run plain apply to bypass it. Reconcile and require
full file convergence after preparing the exact missing directories.

`DOTFILES_AUTO_UPDATE=0` disables native login updates. `DOTFILES_AUTO_STOW` and
`DOTFILES_HOST` remain legacy-only. Payloads are explicit-only (Stage 5 decision
D7): no login, profile or schedule installs or refreshes them, and
`DOTFILES_PAYLOAD_AUTO_UPDATE` is inert. `sync-payloads [ITEM...]` runs
`scripts/payload-update.sh --now` (Windows: `payload-update.ps1 -Now`) from the
validated bound source in the foreground and refuses an invalid binding;
maintenance refuses it too. No new scheduler, revision acknowledgement database
or background supervisor is introduced.

Regular-file edits no longer write through to Git. During the bridge, ordinary
portable edits belong in the canonical legacy source and then native apply.
Review live app changes with a private targeted diff/merge. Do not blindly
`add` an AI config or replace its modify template with a snapshot of local state.
Source consolidation belongs to Stage 6.

### Reconcile an owned AI-config key

Dotfiles owns the Codex and Claude keys listed in
[config-sync.md](../config-sync.md); `tui.status_line` stays owned (Stage 5).
When a live owned value differs from the last applied one, the nonforce login
update stops at that file and later targets stay stale. Causes: a local UI
choice (Codex `/statusline`, a persisted model or effort), or a Codex
app-server that started just before the update and wrote its in-memory copy of
`~/.codex/config.toml` back, as on WSL after `bcf5c0d`. The race does not depend
on the key: any commit that changes rendered Codex config can meet it.

Reconcile one file, never with a routine force:

1. Stop or let idle the Codex app-servers on that host, including those started
   by a remote desktop client on another machine.
2. Privately compare the live file with `chezmoi cat` of the target under the
   full argument set; record only the differing key names.
3. Back up the file privately with its mode and owner.
4. If a differing value is a deliberate local choice, change the tracked
   portable value through a reviewed commit, or accept the portable value.
5. Apply only that target with the full argument set, `--exclude=dirs` and
   `--force`.
6. Verify an empty status, a file equal to its target, and unchanged mode and
   owner; then restart the app-servers stopped in step 1.

Before rolling out a commit that changes rendered `~/.codex/config.toml`, ask
the user to quit Codex desktop apps that connect to the target hosts, and check
each host's status for that file after its first login update.

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
After the bound state database is lost, run no plain read-write chezmoi command
(`init`, `apply`, `update`, `add`, `edit`, `re-add`, `merge`, `forget`,
`state`), even when chezmoi suggests `chezmoi init`: a plain `init` can
recreate the bound database with only its config state, which re-arms the
unattended updater without that recovery. Plain read-only commands (`status`,
`diff`, `managed`, `data`, `execute-template`) are fine.

An offline installation can skip this bridge and pull a future deletion commit;
the support cutoff cannot prevent that. Preserve it, recover from a clean local
clone and exact private snapshots, and prepare HOME destinations individually.
Do not claim that an unobserved or blocked host migrated successfully.
