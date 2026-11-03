# Agent-executed rollout on the six target hosts

Current Stage 4 actual observations and blockers are in
[stage-4-evidence.md](stage-4-evidence.md#actual-fleet-outcomes-separate-from-fixtures).
Lab's 59, Mac's 56, WSL's 55 and each cluster's 54 ordinary targets completed native
takeover, repeat convergence and controlled automatic-update activation. Lab,
Mac and WSL passed fresh ordinary SSH; clusters used existing authenticated masters and
do not claim new MFA access.
Their native ownership/state remain. Maintenance was removed at ordinary
acceptance. Mac subsequently accepted its eight-file secret deployment and left
maintenance again; Lab and WSL currently remain in maintenance after their
approved one-file Codex normalizations. Existing WSL
tmux plugin prerequisites and retired-checkout diagnostics are recorded separately
from ordinary-file acceptance. Cluster consumer prerequisites remain separate
from accepted ordinary targets. The user explicitly deferred Windows' ordinary-user execution/ACL
gate. Native fixtures and SSH connectivity are distinct from takeover. The operator procedure is
[takeover.md](takeover.md). Commit/publication/rollout authority is explicit;
the corrected release `bf99958` passed all three CI 41567805090 jobs and all eight
bootstrap e2e 41567805363 jobs before main landing and actual ordinary takeover.
It is the supported Stow recovery bridge and first accepted ordinary-native
release; source/runtime retirement has not started.
Encrypted source `74985d08` subsequently passed exact CI 41586461636 and bootstrap
e2e 41586462369 before reaching main. This does not itself enable host enrollment.

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
`74985d08` source; actual deployment remains a separate host gate. Keep host private
identities local and export only public recipients.
Mutable Codex auth remains excluded; SSH stays ordinary. Bitwarden was canceled
and all five task-installed clients removed; Sherlock never installed one.
Do not reopen its canceled toolkit/allocation proposal. Launcher provisioning
and account acceptance remain separate host checks: Sherlock still has kit 0.6,
and Marlowe lacks native Codex on the inspected PATH.

## Recording and incomplete targets

Keep one small nonsecret table in `status.md`, not a runtime fleet registry:

| Target role | Access rechecked | Starting revision | Backup | Native apply | Smoke/access | Legacy retired | Blocker |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Fill per host | Timestamp/method | Revision | Ready/not needed | Result | Result/limits | Exact scope/result | Concrete next action |

Attempt all six within the session's available access. Carry unreachable or
blocked targets forward explicitly, respecting the user's Windows deferral;
do not call them migrated. Native-only source
retirement need not wait indefinitely for every offline host, but the stage cannot
claim fleet completion until all six actually pass. Record repository completion
and reachable-host execution separately. Keep controlled upgrade/recovery guidance
for later recovery of a host that auto-pulled past the cutoff.
