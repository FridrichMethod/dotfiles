# Agent-executed rollout on the six target hosts

The Stage 5 rollout of 2026-11-04 is recorded
[below](#stage-5-rollout-as-run-2026-11-04): five Unix hosts reached `dddc718`
through their actual login updater and took the reviewed `persistentState`
re-init; Windows followed the same day through a user-approved limited-token
task ([below](#windows-rollout-as-run-2026-11-04)).

Stage 4 actual acceptance observations are in
[stage-4-evidence.md](stage-4-evidence.md#actual-fleet-outcomes-separate-from-fixtures);
the current per-host state is in [status.md](status.md).
Lab's 59, Mac's 56, WSL's 55 and each cluster's 54 ordinary targets completed native
takeover, repeat convergence and controlled automatic-update activation. Lab,
Mac and WSL passed fresh ordinary SSH; clusters used existing authenticated masters and
do not claim new MFA access.
Their native ownership/state remain. Maintenance was removed at ordinary
acceptance. Mac subsequently accepted its eight-file secret deployment and left
maintenance again. WSL subsequently accepted eight-file deployment and fresh SSH,
restoring automatic updates. Lab accepted eight-file enrollment on `15068b9`,
including 67-target convergence, unchanged ordinary files, actual updater and
fresh WSL-to-Lab SSH; maintenance is off. Marlowe accepted eight-file
secret deployment after checking persisted post-apply bindings and restored
automatic updates. Existing WSL
tmux plugin prerequisites and retired-checkout diagnostics are recorded separately
from ordinary-file acceptance. Sherlock's kit 0.7.0 upgrade passed using the
existing login runtime; its subsequent eight-file enrollment and persisted-binding
acceptance passed on `15068b9`, including empty 62-target diff, actual updater and
existing-master access. Maintenance is off. Windows subsequently accepted all 26
regular targets on `15068b9`, with unchanged parent ACLs, two nonforce repeats,
empty diff, both shell smokes, actual ordinary-token updater/session skip, fresh
SSH and persisted-binding acceptance. Maintenance is off; secret enrollment is
false and the legacy restow task remains disabled. Five exact operator tasks
were cleaned. Native fixtures remain distinct from these actual outcomes. The operator procedure is
[takeover.md](takeover.md). Commit/publication/rollout authority is explicit;
the corrected release `bf99958` passed all three CI 41567805090 jobs and all eight
bootstrap e2e 41567805363 jobs before main landing and actual ordinary takeover.
It is the supported Stow recovery bridge and first accepted ordinary-native
release; source/runtime retirement has not started.
Encrypted source `74985d08` subsequently passed exact CI 41586461636 and bootstrap
e2e 41586462369 before reaching main. This does not itself enable host enrollment.
The native formatting correction `15068b9` passed CI 41684120644 (all three)
and bootstrap e2e 41684121107 (all eight) before main landing and Lab enrollment.

## Authorization and scope

The user explicitly authorized implementing agents to migrate, test and retire
the old dotfiles layout directly on the six target hosts during Stages 4 and 6.
This authorization carries into new sessions. Do not leave reachable-host work
as a later manual task or ask again for blanket migration permission. Stages 1-3
remain isolated implementation work; the planning connection checks did not
install, apply, update or retire anything on a host.

Use existing authorized access and exact, reviewed targets. Authentication/MFA,
privilege escalation, site restrictions, unrelated data and ambiguous ownership
retain their specific boundaries. Report the concrete blocker when one applies.
Do not reset local Git work, remove payload checkouts/module stores or perform
unrelated cleanup under this authorization.

## Observed connection baseline

Planning preflight and follow-up: 2026-11-02 UTC, from lab-ubuntu. Aliases
were read from the current SSH config. No addresses, account names, keys or
private endpoint inventory are copied into this document.

| Target role | Observed access | Consequence for rollout |
| --- | --- | --- |
| mac | Noninteractive SSH command succeeded | Candidate for remote execution; recheck before changes |
| wsl-ubuntu | Noninteractive SSH command succeeded | Separate destination from native Windows |
| lab-ubuntu | Local context confirmed and Mac-to-lab SSH succeeded; lab self-SSH rejected | Operate locally or through the verified Mac client; self-SSH is unnecessary |
| sherlock | Existing user ControlMaster accepted a remote command and site-rule reads | Existing authenticated channel works; no new login/MFA was attempted |
| marlowe | Existing user ControlMaster accepted a remote command | Existing authenticated channel works; no new login/MFA was attempted |
| win | Fresh direct lab-to-Windows SSH succeeded after the user added the lab public key | Direct route available; Mac client route remains a verified alternative |

All five nonlocal targets accepted SSH command execution; lab-ubuntu is accessible
locally and from Mac. These are reachability results, not application smoke tests, deployment
evidence or a promise that access will still work in a later session. Preserve
the distinction between a reused master and a new authenticated connection.

The initial Windows authentication rejection was traced to the missing lab public
key; Mac's key already worked. The user appended the lab key to the effective
administrator authorized-key file. The agent then verified a fresh direct SSH
connection with BatchMode and ControlPath=none, confirmed both keys and the same
SYSTEM/Administrators ACL, and removed only the one newly created backup at the
user's request. The agent did not modify the active authorization file or ACL.
This resolves the earlier Windows access blocker; no dotfiles were migrated.

For the optional Mac route, start the second SSH client on Mac using its own existing
identity. A ProxyJump alone does not substitute Mac's authentication key for the
lab key. Recheck the route before rollout, keep agent forwarding off, and never
copy a private key between hosts to make the route work.

Use the existing plain SSH aliases for cluster commands so configured interactive
RemoteCommand/TTY setup is not invoked. Re-resolve SSH config each session; do
not hardcode IPs/ports in new scripts. Do not substitute the secondary lab account
or unrelated SSH aliases for the six intended destinations.

## Ordered execution

1. Recheck access, role, HOME, source checkout and active revision for each target.
   Inspect user changes, tool availability, ownership and existing update workers.
   Check for shared physical machines, checkouts and OneDrive stores: separate
   logical roles do not prove writes are independent.
2. Complete isolated tests and the required exact-commit CI first. Build the
   Stage 6 deletion candidate in an isolated checkout, with ordinary/native source
   fully materialized and no includes of paths about to be removed.
3. Before a deployed checkout crosses the breaking revision, disable future old
   dotfiles AND payload hooks and wait for/address existing repo-owned workers
   and the exact Windows task. Setting an environment variable does not stop an
   already running worker or future unrelated login. Test the effective guard.
   Do not publish the deletion to auto-updated main first and hope SSH cleanup
   catches up. Coordinate candidate CI, host quiescence and final publication
   with the repository's existing landing rules.
4. Pick one recoverable canary. Stage 4 first proves real native takeover while
   old source paths still exist; Stage 6 proves the final native-only candidate.
   Keep the current access/recovery channel open. Save private snapshots of only
   the affected files, link text and relevant modes/ACLs outside the source tree.
5. Prepare required native tools and the selected secret backend using the
   explicit provisioning rules. Preserve existing parent modes/ACLs with
   `--exclude=dirs` on file apply/diff/update. Inspect the native directory
   inventory and ancestors; prepare only exact still-absent directories through
   reviewed native directory-only, nonrecursive apply, skipping an empty list.
   Never fall back to an all-directory apply. Review local umask separately;
   all five accepted Unix hosts selected native umask 077. Apply the reviewed files, then perform a
   second apply, shell/profile/application checks and actual thin updater checks
   after controlled maintenance removal. Restore maintenance on failure. Missing
   parents can stop apply after a source fast-forward or earlier file writes.
   Do not print secret diffs or start arbitrary authenticated application sessions.
6. Validate new access before dropping the old channel. On ordinary SSH targets,
   use a genuinely fresh connection with multiplexing disabled; a new command
   over the old master is insufficient. Where site/MFA rules require the user's
   authenticated master, record that limit and the specific user-assisted check
   needed; never force a new login. For local lab-ubuntu, keep local recovery
   access; the actual post-takeover WSL-to-lab fresh SSH check passed.
7. After the canary succeeds, roll out to the remaining reachable targets with
   one operation owner per host. Limited parallelism is fine only after confirming
   distinct writable state. A failure stops that host's retirement and any rollout
   that depends on the failed assumption; fix and revalidate before expanding.
8. Retire exact owned legacy links, tasks, helpers and sync environments only
   after their native replacements pass and no supported caller remains. Review
   each path, preserve local edits, and prefer recoverable movement until checks
   finish. Re-enable only the intended new hooks. Keep recovery snapshots until
   the successful migration record is complete; no blanket HOME cleanup.

The user expects this execution to happen in the implementing sessions. Writing
commands for the user is a fallback for a concrete access/privilege/site blocker,
not completion of otherwise executable work.

## Acceptance per target

Record the starting and resulting revision; destination ownership; backup state;
native tool version; selected secret access; ordinary and mutable-config apply;
second-apply convergence; platform shell/app smoke; native update behavior; fresh
access or its documented limitation; and exact legacy targets retired. Record
local edits and recovery outcomes without exposing their contents.

Only run checks appropriate to the host: Windows profile discovery and ACLs need
native evidence, and a headless connection cannot prove a GUI restarted properly.
Do not equate a rendered config or successful SSH echo with those checks.

Sherlock requires current `/etc/agents/AGENTS.md` and relevant topic files at each
session and after compaction. The initial preflight reused an existing master and
ran only permitted light reads, with no toolkit installation at that checkpoint.
The later separately approved local controller pins sherlock-kit v0.6.0; dotfiles
does not acquire that dependency. Use that project's pinned tool for its jobs and
transfers, respecting current site rules. Heavy checks,
compilation and environment creation require allocation; no detached login-node
updater/supervisor is permitted. Keep site-specific updater behavior compliant.
Read the applicable rules on Marlowe before installation or substantive changes.

Marlowe publishes no `/etc/agents` rules. Its site AppArmor profile `block-node`
denies `node` (and some IDE and agent binaries) on login nodes; never work
around it. The three Claude Code commands that run coding-agent-kit's Node
helpers there (the PreToolUse Git hook-bypass guard, Notification and
statusLine) therefore exit 127 on login nodes. Claude Code treats that as a
non-blocking hook error: the action proceeds, while permissions and the auto-mode
classifier still apply. The guard documents itself as no security boundary, so
the loss is user experience: a blank status line, no notifications and no usage
records for `claude-as --account-info`. Stage 5 accepted this without a
Marlowe-specific settings branch; non-Node helpers would be an upstream
coding-agent-kit change. Dotfiles still deploys Marlowe's Codex
configuration. The Codex CLI is deliberately not provisioned on its PATH, but
Codex app-servers do run there and read that configuration, so the Codex
write-back check applies on Marlowe too.

Sherlock's observed glibc 2.17 cannot run the generic v2.74 Linux artifact. The
official SHA256-verified static musl build passed an isolated version probe;
`77bb03e` selects it without changing the existing destination convention.
That correction is included in the accepted exact-green release. Actual cluster
installation and takeover outcomes are recorded separately in stage-4-evidence.md;
neither binary provisioning nor configuration apply requires an environment build.

Eight static Claude files are authorized for lab, Mac, WSL, Sherlock and Marlowe
plus independent R. Apple Passwords is selected and already syncs to another
usable device. Independent R was generated privately on Mac, and the user
reported both local retrieval checks PASS, then confirmed full retrieval on
another device. Custody and all five host identities are established. Eight
production inputs are encrypted for the exact six recipients, and each host
plus retrieved R passed all-eight recovery. Only ciphertext entered the published
`74985d08` source; actual deployment is accepted on all five Unix hosts and Windows
enrollment is false by design. Keep host private identities local and export only
public recipients.
Mutable Codex auth remains excluded; SSH stays ordinary. Bitwarden was canceled
and all five task-installed clients removed; Sherlock never installed one.
Do not reopen its canceled toolkit/allocation proposal. Launcher provisioning
and account acceptance remain separate host checks: Sherlock now has kit 0.7.0,
and Marlowe lacks native Codex on the inspected PATH.

## Stage 5 rollout as run (2026-11-04)

Stage 5 needed no takeover. Each Unix host reached `dddc718` through its own
login updater (Lab's checkout had already been fast-forwarded by the landing,
so its updater only applied the six targets), then took one reviewed re-init
that adds the owned `persistentState` key. One operation owner ran the
hosts one at a time. Results and per-host revisions are in
[status.md](status.md#stage-5-completion-record-2026-11-04).

Read the site rules before Sherlock work: `/etc/agents/AGENTS.md` and its topic
files, over the existing master (`sherlock-plain`), never by a new login. The
Stage 5 host probe read `AGENTS.md` and the policy, storage, software and slurm
topic files before any command. The Sherlock and Marlowe steps were light
foreground commands on a login node, with no job, detached process or
environment build. Marlowe publishes no site agent rules; its tmux install
ran only inside allocation jobs ([below](#marlowe-tmux-36a)).

Per Unix host:

1. Probe read-only: the binding marker, the source HEAD and cleanliness,
   full-argument status, the managed count, rendered equality of both AI
   configs, payload state, running Codex app-servers and tool versions. A
   Codex app-server matters whenever the update changes rendered Codex config,
   as `bcf5c0d` did on Sherlock, Marlowe and win.
2. Back up privately in `~/.local/state/dotfiles-stage5-rollout/u-<timestamp>/`
   (0700, umask 077): copies of `~/.codex/config.toml` and
   `~/.claude/settings.json`, checked with `cmp`, and a manifest of their mode,
   owner, group, link count, extra ACL entries and sha256, the eight secret
   files' inode, mtime, size, mode and owner, the maintenance marker and the
   binding marker.
3. Run the actual updater in a fresh interactive shell with stdin closed and
   no inherited session guard or disable switch, where `$SOURCE` is line 3 of
   `~/.config/dotfiles/native`. The script also set the now inert payload
   variable:

   ```sh
   env -u _DOTFILES_CHECKED -u DOTFILES_AUTO_UPDATE -u ENV DOTFILES_PAYLOAD_AUTO_UPDATE=0 \
       sh -i -c '. "$1/scripts/chezmoi-update.sh"' sh "$SOURCE" </dev/null
   ```

   A host already at the target with an empty status skips this step. On
   Sherlock (`sherlock-plain`) and Marlowe (`marlowe` with `RemoteCommand=none`
   and no TTY) the script ran from the login env's interactive login zsh, so
   PATH matched an ordinary login; that outer shell's own updater was off
   (`DOTFILES_AUTO_UPDATE=0`).
4. Verify: HEAD is the target, the checkout is clean with no local-only
   commits, and the managed count is unchanged. Full-argument
   `status --exclude=dirs` shows nothing but the harmless `config file template
   has changed` warning. Both AI configs equal `chezmoi cat` with unchanged
   metadata. A key diff of the Codex TOML allows changes only under owned
   policy paths and requires every unowned key to survive; a key diff of the
   Claude JSON lists its changes. Secrets, maintenance marker and binding marker
   are unchanged. Codex write-back check: no `MM` for `~/.codex/config.toml`
   after the update; an `MM` goes to the one-file reconcile in
   [takeover.md](takeover.md#reconcile-an-owned-ai-config-key), never to a
   routine force.
5. Re-init in that shell after its login update, with no other chezmoi
   running:
   - Precheck, read-only: the regular three-line marker names this canonical
     HOME; the provisioned chezmoi is v2.74.0 (`~/.local/bin/chezmoi`; on Mac
     `/opt/homebrew/bin/chezmoi`); the bound source is a clean checkout root
     whose `home/.chezmoi.toml.tmpl` is the reviewed blob `9e26214`; the config
     is a regular file without a `persistentState` key; the bound database is a
     nonempty regular file; `XDG_CONFIG_HOME` is unset or the default; and
     full-argument status is empty.
   - Record privately in `~/.local/state/dotfiles-stage5-reinit/` (0700): a
     copy of the config, its key names, and the ACLs of the config and the
     database.
   - Run the [takeover.md](takeover.md) init with the full explicit argument
     set: `--source`, `--working-tree`, `--destination`, `--config`, `--cache`,
     `--persistent-state`, `--mode=file --no-tty --error-on-conflict
     --force=false --no-pager --use-builtin-diff`.
   - Postcheck: `persistentState` is the only added key, nothing else changed
     and both ACLs are unchanged; a plain
     `execute-template '{{ .chezmoi.config.persistentState }}'` names the bound
     database; a stray `chezmoistate.boltdb`, if any, is moved into the record,
     never deleted; full-argument `status --exclude=dirs` is empty, and plain
     `status --exclude=dirs` is empty with empty stderr; and no stray database
     reappears. Rollback is an in-place copy of the recorded config.
6. Run the offline doctor from an interactive login shell. On Marlowe that is
   `ssh marlowe`, not `marlowe-plain` ([below](#marlowe-tmux-36a)).

Two portability lessons came from the first re-init attempts. Both were fixed
before the re-init ran on those hosts, and the failed attempts stopped before
init and changed no config, state or target:

- Copy the record without `cp -p`. Marlowe's filesystem refuses permission and
  ACL preservation (`Operation not supported`); a copy made under umask 077 is
  private anyway.
- Do not assume `$0` is a file. A script sent over SSH as
  `sh -c "$script" probe` sees `$0` as `probe`; copy the script into the record
  only when `$0` is a regular file.

The update step's backup (step 2) still used `cp -p` and printed the same
`Operation not supported` warning on Marlowe; its copies still matched by
`cmp`, with mode 0600.

The Codex write-back check found no `MM` on any host, although one Codex
app-server ran on each HPC host during the update.

### Marlowe tmux 3.6a

The 3.4 floor needed tmux in Marlowe's login env before landing. Both steps
were reviewed allocation jobs, never login-node work, and nothing touched the
site AppArmor profile. Solver dry-run job 554658 changed nothing. Install job
554712 (COMPLETED 0:0) added tmux 3.6a and libevent 2.1.12 from verified
archives with no removals. Package records went from 59 to 61 with the original
59 byte-identical. The 49 new files lost their upstream group write (0664 to
0644 and 0775 to 0755), the new-file-only rule of job 553043. At the user's
request, both private caches, about 931 MiB, were deleted afterwards. Evidence
on Marlowe: `~/.local/state/dotfiles-marlowe-tmux-dryrun-20261103-01/` and
`~/.local/state/dotfiles-marlowe-tmux-install-20261104-01/`.

Interactive login shells put the login env first and get 3.6a. Non-interactive
shells, such as `ssh marlowe-plain tmux ...` or
`ssh marlowe-plain 'cd ~/dotfiles && ./doctor.sh'`, still find `/usr/bin/tmux`
3.2a, which rejects the 3.4 options; that doctor then reports tmux as outdated
and exits 1. Start tmux and run the doctor from an interactive login shell
(`ssh marlowe`); see [shell.md](../shell.md#tmux).

### Windows rollout as run (2026-11-04)

win reached `57fbc45` (`dddc718` code plus the Stage 5 records) and took the
re-init on 2026-11-04; the results are in
[status.md](status.md#host-rollout-2026-11-04). Instead of typing the manual
steps below, the user explicitly approved in the session a one-off scheduled
task:

- Principal: the logged-on user, LogonType Interactive, RunLevel Limited; the
  run reported `elevated=False` at Medium Mandatory Level.
- The administrator SSH session only wrote the task script and registered,
  started (once, `Start-ScheduledTask`) and deleted the task. Every change to
  managed targets, chezmoi config and state and the `chezmoi.exe` ACL ran under
  the user's limited token.
- Limits: it needs the user logged on and the user's explicit approval of that
  one task, and the task is deleted after the run. It is not a standing channel:
  the administrator token never writes managed targets, chezmoi config or state,
  or ACLs.
- The task ran the manual steps in order: pass 1 with the checkout's
  `7e344f2` updater, as a first login would (fast-forward to `57fbc45`); pass 2
  with the new exact-exe updater (no `Native update skipped` warning);
  `reinit-win.ps1` with the same checks; `icacls /inheritance:d` (no
  CodexSandboxUsers entry was present); `doctor.ps1 -Quiet` (exit 0).
- Evidence on win: `~\.config\dotfiles-stage5-task\` (`run.ps1`, `run.log`) and
  `~\.config\chezmoi\stage5-reinit\`.

#### Manual Windows steps (fallback)

For a Windows host that cannot use such a task, the user runs these in an
ordinary, non-elevated pwsh 7.2 or later (the script declares
`#Requires -Version 7.2`; win has 7.6.9), because the re-init needs the user's
own token. Quit any Codex desktop app that connects to the host before step 1.

1. Open an ordinary interactive pwsh session and let its login update finish.
   On a host at `7e344f2` it runs the old updater, which fast-forwards to
   current main; on win three targets were expected to change:
   `Documents\PowerShell\profile.ps1`, `~/.codex/config.toml` and
   `~/.claude/settings.json`.
2. Open a second ordinary interactive session. Its login runs the new updater,
   which uses only `~/.local/bin/chezmoi.exe` after the owner and DACL checks.
   It must not print a `[dotfiles] Native update skipped` warning.
3. Check the staged script's hash, then run it from that ordinary session:

   ```powershell
   (Get-FileHash "$HOME\Downloads\reinit-win.ps1" -Algorithm SHA256).Hash
   # expected: CED552AB2A4F8099CC5F7478A6CD4AFB7BEC7AF2FD2B4B85C42509A2F550A212
   pwsh -NoProfile -File "$HOME\Downloads\reinit-win.ps1"
   ```

   It refuses an elevated token, verifies and holds `chezmoi.exe` as the
   updater does, requires the reviewed template blob (`9e26214c`, `dddc718`'s)
   and an empty full-argument status, and records the old config in
   `~/.config/chezmoi/stage5-reinit/`, not under `~/.local`, because of the
   inherited sandbox grant there. It then runs the full-argument init and the
   same postchecks as on Unix.
4. Optional: `icacls "$HOME\.local\bin\chezmoi.exe" /inheritance:d` turns the
   file's inherited ACEs into explicit ones, so a later propagation from
   `~/.local` cannot add the sandbox Modify grant that would make the updater
   refuse it. First confirm that plain `icacls` lists no CodexSandboxUsers
   entry, which would otherwise become permanent.
5. Run `.\doctor.ps1` from the checkout; native-config should be ok.

## Recording and incomplete targets

Keep one small nonsecret table in `status.md`, not a runtime fleet registry:

| Target role | Access rechecked | Starting revision | Backup | Native apply | Smoke/access | Legacy retired | Blocker |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Fill per host | Timestamp/method | Revision | Ready/not needed | Result | Result/limits | Exact scope/result | Concrete next action |

Attempt all six within the session's available access. Carry unreachable or
blocked targets forward explicitly, using current authorization and evidence;
do not call them migrated. Native-only source
retirement need not wait indefinitely for every offline host, but the stage cannot
claim fleet completion until all six actually pass. Record repository completion
and reachable-host execution separately. Keep controlled upgrade/recovery guidance
for later recovery of a host that auto-pulled past the cutoff.
