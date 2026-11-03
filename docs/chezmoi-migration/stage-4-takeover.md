# Stage 4: Compatibility release and takeover implementation plan

> **For agentic workers:** Use subagent-driven-development with separate worktrees
> under [README.md](README.md). Start with the complete Stage 3 artifact and
> [start-stage-4.md](start-stage-4.md); do not reconstruct it from bare HEAD.

**Goal:** Make native deployment usable for new installations and provide a safe,
explicit handover for existing homes without breaking old symlink source paths.

**Architecture:** Keep legacy files physically present, disable their writers for
each migrated home, and use native chezmoi for application. A thin login adapter
calls native update/apply. Use a bounded migration procedure and local backups,
not a new ongoing migration service or journal.

**Tech stack:** Chezmoi, existing Bash/PowerShell entrypoints only where needed for
compatibility, isolated native fixtures and operator documentation.

**Spec:** [Release invariant](README.md#release-invariant), completed Stage 3,
[status and decisions](status.md), [support boundary](support-boundary.md).
Operational contracts: [fleet rollout](fleet-rollout.md) and
[secrets and SSH](secrets-and-ssh.md).

## Global constraints and review focus

Stage 2 preserved fixed native Windows profile destinations. Before any takeover,
query `CurrentUserAllHosts` with `pwsh -NoProfile` and Windows PowerShell
`-NoProfile`, without reading/sourcing the files. Require both paths to match
the intended destination or explicitly model redirected Documents before writes.
The Stage 2 tested host matched defaults; that is not a fleet-wide assumption.
Private temporary Windows ACL evidence used an administrative SSH token and does
not establish an ordinary user's real destination ACL. Recheck destination ACLs.

The 67 ordinary source files still read legacy canonical paths. Preserve
that bridge through this stage; native host validation and empty/private/
executable/CRLF tests are existing acceptance inputs, not takeover authorization
by themselves. Stage 3 adds exactly two AI modifies, giving role totals
49/56/55/59/54/54/26. Local TOML date/time/datetime and JSON U+FFFD are deliberately
refused before affected-target writes. A real home containing them remains
blocked until its owner chooses a meaning-preserving change or native support
is verified; never force through the guard or claim the input was preserved by
a successful transformation. JSON duplicate keys remain native last-value-wins.
Review that boundary privately before first canonicalization.

The user has authorized real-host execution under D11 after fixture/CI checks.
Use existing access and exact targets; do not ask for blanket authorization again.
Concrete authentication, privilege, ownership and site blockers still apply.
Keep current Stow physical paths through this bridge stage; the eventual declared
cutoff may make unmigrated installations unsupported without waiting for all of
them. One writer owns each destination. No blanket force, broad source import,
directory adoption or deletion.

Review active old workers; Windows scheduled tasks outside the login profile;
foreign links/files; failed partial takeover; and application edits made after
backup. An environment opt-out does not stop a worker already running.

## Decisions to settle before activation

Stage 1 proved `add --follow` imports bytes but leaves an owned symlink in place.
Ordinary conflict-safe apply refuses replacement. A single verified fixture
target converted with explicit `apply --force TARGET`; do not generalize that
to an unreviewed link or whole-home force. Stage 4 must first verify ownership,
snapshot privately and limit replacement to the exact selected target. Routine
apply/update retains `--no-tty --error-on-conflict` and closed stdin; nonzero
status needs a clear adapter warning even if native stderr is empty. The Stage 3
native temporal refusal was verified on all three platforms. UTC process TZ is
not a correction on Windows; do not add it as an escape hatch.

- D6 is already resolved: preserve login automatic dotfiles updates with a thin
  adapter calling chezmoi. Scope its small interactive/session trigger and error
  handling; do not replace it with manual-only updates or ask the same question.
  Avoid rebuilding receipts, background services and retry protocols.
- Choose the smallest per-home handover guard that makes legacy entrypoints
  refuse to write a migrated target. Prefer a local native configuration signal
  or one migration-only marker; do not add a revision-acknowledgement database.
- Decide the supported Windows actual profile-path handling using native evidence.
- Keep Stage 5 payload scheduling choice separate from the dotfiles update choice.

## Ordered executable work packages

### 1. Freeze the per-home writer handover before parallel edits

Coordinator owns `home/.chezmoi.toml.tmpl`, `docs/config-sync.md`, this plan,
`support-boundary.md` and shared test fixture changes. Inspect current native
config discovery and all old callers before choosing one local ownership signal.
Use a small migration marker or an unambiguous native config signal, bound to the
actual destination home; no revision receipts or fleet database. Define its
exact path, absent/present semantics, source/destination binding and Windows
equivalent in the implementation ledger before worker dispatch. It must work
for direct legacy helpers with explicit LIVE arguments as well as installers.

Write a failing fixture that marks a home as native-owned, then invokes every
old writer against it: `stow-all.sh` / `.ps1`, `scripts/dotfiles-update.*`, the
Windows `scripts/dotfiles-auto-stow.ps1 -Apply`, and all four sync wrappers.
Expect refusal before any destination or portable-source write. An unmarked
legacy fixture must keep its supported behavior. A failed/partial native apply
must keep old writers disabled; removing a guard is an explicit recovery step.
Do not make an unrelated explicit test destination depend on the operator's HOME.

Freeze a separate maintenance procedure that disables future dotfiles AND payload
login hooks before entering takeover. The normal payload lifecycle remains a
Stage 5 decision. Maintenance must cover new logins, not only exported variables
in the current shell. Fixture-test the effective guard from a second process.

### 2. Implement Unix and Windows compatibility work in separate worktrees

| Worker | Exclusive files | Boundary tests |
| --- | --- | --- |
| Unix | `stow-all.sh`, `scripts/dotfiles-update.sh`, new `scripts/chezmoi-update.sh`, `common/sh/.profile`, `common/zsh/.zshrc`, `tests/chezmoi-takeover.sh`, `tests/test_chezmoi_takeover_unix.py` | Owned/foreign links, direct old-writer refusal, repeated/nested interactive shells, opt-out, missing binary, closed stdin and silent native failure |
| Windows | `stow-all.ps1`, `scripts/dotfiles-update.ps1`, `scripts/dotfiles-auto-stow.ps1`, new `scripts/chezmoi-update.ps1`, both `win/powershell/Documents/*/profile.ps1`, `tests/chezmoi-takeover.ps1`, `tests/test_chezmoi_takeover_windows.py` | Native profile metadata mismatch, regular-file apply unelevated, exact task guard, ordinary-token ACL boundary, ShouldProcess and partial handover |
| Coordinator | Canonical config template; `lib/config_sync.py` / four sync wrappers only as required by the frozen guard; manifests/provisioning/doctor/runners/hooks/docs and mirrored bootstrap skills | Same home-binding contract for explicit helper targets; prerequisite/CI selection and legacy/native modes |
| Recovery verifier | New `tests/test_chezmoi_takeover_recovery.py` only | Mid-apply failure, post-backup edits, foreign targets and recovery without blind restow |

If a shared guard helper is needed, coordinator assigns its exact Unix/Windows
files and interface once. Keep it limited to the temporary writer guard; Stage 6
removes it with the old writers. Native applies remain independent of the old
Python backend. Reviewers do not edit these workers' checkouts.

### 3. Pin the native update contract and prove it with local Git fixtures

The new adapters preserve D6: interactive once-per-session dotfiles updates,
`DOTFILES_AUTO_UPDATE=0`, no login installation, no UAC, no background supervisor,
and a warning that leaves shell startup usable on failure. Keep payload dispatch
separate. They call native update/apply with explicit source/config/destination
and `--no-tty --error-on-conflict`; do not fall back to a legacy writer.

The official native `update` default uses autostash/rebase. In the local native
configuration, use the supported `[update] command`/`args` override to call Git
fast-forward only. Candidate arguments to verify on the supported Git floor:
`-c rebase.autoStash=false -c merge.autoStash=false pull --ff-only --no-rebase
--no-autostash --no-recurse-submodules`. Set native recurseSubmodules false and
keep autoCommit/autoPush false. These are Stage 4 test inputs, not a claim of a
deployed configuration. A small clean-tree refusal before update is justified
to preserve source edits; no stash/reset/rebase or retry journal.

Use temporary repositories/remotes to prove clean fast-forward, dirty tracked
and untracked trees, divergent histories, hostile inherited pull/rebase options,
unavailable remote and destination conflict. Assert no stash, branch rewrite,
prompt or forced file replacement. Test native exit 1 with empty stderr and
clear adapter warning. Test missing/locked age access with synthetic ciphertext
and bounded noninteractive failure. Normal logs use a nonsecret target allowlist.

### 4. Turn fixture commands into the reviewed takeover procedure

The existing `SourceFixture` invocation establishes this command structure:

```sh
chezmoi --source "$source" --destination "$destination" --config "$config" \
  --cache "$cache" --persistent-state "$state" --no-tty --error-on-conflict --force=false \
  --no-pager --use-builtin-diff apply --exclude=dirs </dev/null
```

All six paths must be explicit and owned by the intended home. Role is written
to local `[data].host`; it is never inferred from DOTFILES_HOST or OS. In fixtures,
run targeted diff/apply against the two AI files before full apply, then repeat
apply and require an empty nonsecret diff. Preserve the 67 ordinary legacy
bridges, private/executable/empty/binary/CRLF behavior and shared unmanaged state.
Preserve existing directory permissions with the explicit exclusion above.
Before file apply, use the native managed-directory inventory to inspect and
create only still-absent exact parents with directory-only nonrecursive apply;
follow takeover.md. Future updates needing a new parent fail until this reviewed
preparation is complete. Review local umask and existing 0700 secret parents;
directory exclusion deliberately does not enforce or repair their modes.

For each existing link, snapshot link text, referent bytes and relevant modes/
ACLs privately outside source; prove the exact canonical legacy owner. Ordinary
apply is not an ownership check: fresh native state can replace a foreign link.
A tested targeted `apply --exclude=dirs --force=true "$target"` may convert
only that individually verified link after quiescence/backup; never add force
to a whole-home or recurring apply. `add --follow` is import-only and must not
replace a modify template. Foreign links, directories, unreadable targets,
unknown ownership or source edits stop that target's handover.

The recovery fixture must add an application edit after backup, simulate partial
takeover, then demonstrate preservation of both new edit and original snapshot.
Recovery compares them before restoring any exact link. Reverting Git plus blind
restow is forbidden. Keep one writer disabled while recovering the other.

### 5. Provision and publish only the tested compatibility release

Coordinator changes `config/bootstrap/`, `setup-host.*`, `doctor.*`, relevant
`lib/bootstrap*`, README, `stow-all.sh` usage/comments and mirrored bootstrap
skills together. New-home native setup obtains verified chezmoi explicitly and
creates no sync venv. Legacy setup remains clearly labeled during coexistence.
No setup/login hook enrolls secrets, runs privilege escalation or initializes
application auth. Preserve current tmux/Bash/PowerShell floors.

Run focused native takeover/recovery, Linux `tests/run.sh --ci`, Windows
`tests/run.ps1 -CI`, full pre-commit, independent review, then required exact
candidate-commit CI on all three systems and bootstrap e2e for setup changes.
The active Stage 4 prompt must authorize commits/publication before using the
repository landing procedure. Never claim an uncommitted local suite is hosted
CI. Name immutable last-Stow and first-native revisions only once real release
commits exist; do not invent hashes or move tags. Publish a bridge/clean-clone
operator procedure covering generated override, local filter and historical
opt-outs. No all-host waiting gate is reintroduced.

### 6. Execute quiescence, secrets and the six-host rollout

Recheck existing routes from `fleet-rollout.md`, shared machines/storage/OneDrive,
actual checkout/role, current Git changes and site rules. Choose lab-ubuntu as
the recoverable canary if its current state permits; otherwise record the exact
reason for another canary. Only after canary acceptance assign one owner to each
independent remaining host. Do not use real config or credentials as test fixtures.

Before fetching/crossing a breaking revision, verify maintenance prevents new
dotfiles/payload workers and wait for existing exact-owned processes. Inspect
the Unix Git-metadata `dotfiles-sync-unix.lock/pid` and process ancestry without
trusting a stale PID alone. Payload `--worker` has no consumer lock; identify
its exact command/source/owner and let it finish. On Windows derive the precise
`Dotfiles-Restow-<hash>` task with the existing `Get-DotfilesTaskName` algorithm;
inspect principal/actions/source path, disable only that task and wait for its
owned running action. No wildcard task disabling or unrelated process killing.

Before AI takeover, privately check unsupported input, stricter/read-only modes
and Windows destination ACLs under the actual user. Query both shells' real
CurrentUserAllHosts metadata with NoProfile; redirected Documents blocks the
fixed mapping until explicitly modeled and retested. Stage 2 administrative
capsule ACLs do not grant ordinary-user approval.

Before any real encrypted target exists, make the private allowlist explicit:
record consumer/writer, existing path, static vs refresh state, hosts, recipient
set, rotation/revocation and recovery owner. Recheck channel-0.7 public consumer
interfaces; Stage 1's installed-kit evidence was v0.6. Generate separate native
age identities outside Git through existing authorized access. First-key access
and a private recovery copy must not depend on the ciphertext being bootstrapped.
Enroll only selected static files with explicit per-file recipients; verify
recipient inclusion/exclusion privately. Do not expose values in commands/logs,
read tokens merely to classify them, deploy dummy credentials, copy SSH private
keys or add recurring create-if-missing OAuth seeds. Unresolved trust/bootstrap
choices block only their dependent enrollment; ordinary work can proceed.

For every actual host: private snapshots ready, old writers quiescent, explicit
role/config selected, guarded targeted AI preflight, exact-owned takeover, full
apply, second apply, shell/app checks, thin updater and fresh access test. Keep
the original SSH channel until success. Ordinary SSH uses a fresh connection
without multiplexing; site/MFA-only masters retain their explicit limit without
new authentication. Record results and blockers separately per host in status.md.
No recursive deletion/exact ownership of shared app, SSH or payload directories.

## Required implementation outcomes

Stage 4 is implemented and accepted on all six hosts; see [status.md](status.md)
and [stage-4-evidence.md](stage-4-evidence.md). This list preserves the
acceptance plan; do not restart Stage 4 from its unchecked items.

- [ ] Publish the supported current layout/tool floors, an immutable last
  supported Stow revision and a tested manual bridge/clean-install procedure.
  Use `support-boundary.md`'s checklist, including old generated overrides,
  Git filter, opt-out and leftover package links. A fresh clone alone does not
  repair old HOME targets. No new automated historical-repair framework.
- [ ] Existing old symlink paths remain valid after a clean fast-forward from an
  older revision, including a fixture that skips intermediate migration commits.
  This guarantee covers this pre-deletion bridge, not a future unsupported jump
  across the final cutoff. Test and document those distinct cases honestly.
- [ ] New-host provisioning selects the native path and does not create a sync
  venv. Tool installation remains explicit and follows artifact verification and
  no-rc rules. Legacy commands remain clearly labeled compatibility interfaces.
- [ ] Native update configuration prevents the default autostash/rebase behavior.
  Test it against divergent histories and inherited Git configuration. If strict
  clean-tree refusal is retained, justify one small check rather than a scheduler.
- [ ] The login adapter runs only in the intended interactive context, respects
  the existing update opt-out and invokes native chezmoi noninteractively. A small
  once-per-session guard is sufficient if needed; no applied-revision receipt.
  Prevent credential/TTY prompts and forced overwrites. Errors warn and leave
  shell startup usable; a later login can attempt native update again.
- [ ] Test repeated/nested shells, opt-out, absent chezmoi, dirty source, divergent
  Git history, edited live targets and native update failure. Do not install a
  missing binary during login. Keep native Windows ordinary-file updates
  unelevated; retain no UAC prompt or elevated task for the new path.
- [ ] Per-home takeover begins by preventing future old hooks, identifying and
  waiting for existing workers, and addressing the exact repo-owned Windows task.
  Do not kill unrelated processes or disable unrelated scheduled tasks.
- [ ] Snapshot only the targets being handed over, including original link text,
  content and relevant permissions. Keep backups private and outside source.
  Review real config locally; never log it into CI or commit it as a fixture.
- [ ] Prove ownership before replacing legacy links. Preserve foreign targets and
  surface concrete conflicts. Use native source/apply behavior; `add --follow`
  is only a targeted content-import tool, not a reason to import application state.
- [ ] Once native ownership starts, old Stow/sync entrypoints must not reclaim
  those targets, even on later login or an explicit old command. Test that path.
- [ ] Failed application remains visibly incomplete, has one documented owner,
  and can be retried without running both writers. Do not promise a transaction.
- [ ] Normal Windows regular-file deployment needs no symlink-creation elevation.
  Verify actual PowerShell, OpenSSH config reading and Terminal settings discovery
  in an authorized native environment; distinguish CI from real-host evidence.
- [ ] Preserve GUI/live edits through diff/add/merge. Document the changed editing
  workflow, including the temporary source bridge until Stage 6.
- [ ] Prepare the chosen secret backend and narrowly enroll real static secrets
  and private SSH snippets on authorized targets. Use ciphertext/vault references,
  private destinations and nonrevealing checks. Preserve active app auth and do
  not distribute private keys or unlock an account merely to avoid a blocker.
- [ ] Execute and verify a real canary takeover using fleet-rollout.md. Preserve
  the original access channel while testing new access, second apply, appropriate
  shell/app smoke and the thin updater. Record subsequent hosts actually migrated.

## Rollout and recovery

Execute real takeover under the user's recorded authorization after fixture checks
and the repository CI gates. Record actual operations and limits in `status.md`;
do not require an inventory/attestation from every offline installation. Explain
that an old updater can pull a breaking revision despite the support cutoff.
The operator must disable both old update hooks and address existing workers/tasks
BEFORE fetching/crossing it. Provide recovery for a host that skipped the procedure.

Recovery first preserves current regular files and application state, including
edits made since migration. Compare them to the pre-takeover snapshot before
restoring any prior link or writer. Switching Git revisions and restowing blindly
is not a rollback plan. Native source and backups must remain available until the
operator verifies application behavior.
The implementing agent is the operator for reachable hosts. Keep manual guidance
as recovery documentation and for concrete blockers, not as a substitute for the
authorized execution. Do not enable detached background update behavior on HPC
login nodes when site rules prohibit it.

Stage 4 code can be complete while some old installations remain unsupported or
not yet upgraded. Record those facts separately. Stage 6 requires native/cutoff
deliverables and CI, not universal host completion. Keep transitional source and
runtime dependencies until the stage that deliberately withdraws their support.

## Exit and next handoff

Run native migration/recovery fixtures, required full checks and platform CI;
bootstrap changes also require the repository's e2e evidence. Update active rules
and docs with the new default and the remaining compatibility window. Expand
Stage 5 into a concrete deletion/retention map with exact owners and tests. Never
mark all homes migrated based on CI or a successful developer-machine takeover.
