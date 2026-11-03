# Fresh-session prompt: Stage 5

```text
Implement only Stage 5 of the chezmoi migration when the current stage handoff
permits it. Do not restart completed Stages 1-3 or the Stage 4 bridge, treat
incomplete Stage 4 operational/candidate gates as passed, or perform Stage 6
source/runtime retirement. Read docs/chezmoi-migration/status.md first and distinguish
candidate code, actual native fixture results, hosted validation and real hosts.

Start by inspecting HEAD, branch, status, the full staged AND unstaged diff,
untracked task files and worktrees at /tmp/dotfiles-chezmoi-stage4-integration,
branch chezmoi-stage4-integration. Stages 1-4 runtime is committed through
bf9995809ca7564c0728f87bcbefe91c8a3cc5e0, including the Sherlock static artifact,
Terminal preference, directory-mode correction, five-host secret gate and exact
tmux handoff. Carry any subsequent pending tracked/untracked changes as well as
the committed source when creating another worktree. Do not replay a historical
whole-aggregate patch over this HEAD. The user's two original main tmux edits
were verified, staged deliberately and accepted by the matching fast-forward;
main was clean afterward. Validate parity and keep a recoverable patch. Never
reset/stash/discard or overwrite unrelated edits.

Runtime bf99958 passed all three jobs of CI 41567805090 and all eight jobs of
bootstrap e2e 41567805363 and reached local/remote main. It is both the supported
Stow recovery bridge and first accepted ordinary-native release. Encrypted
source 74985d08f6ec91391e8f6ba3b54e95d08ad91d44 subsequently passed all three
CI 41586461636 jobs and all eight bootstrap e2e 41586462369 jobs before reaching
main. Carry that complete source and later outcome records. Subsequent changes
need their applicable exact gates. The user explicitly authorized
commit, publication and rollout; do not ask again for blanket authority.
Outcome checkpoint cb7f11a039fbfc00428408e873730701d0aebf9b passed all three
CI 41613012922 jobs on ci/chezmoi-stage4-outcomes. Inspect actual integration
HEAD and later outcome commits before proceeding. Main remains at 74985d08 while
the retained WSL deployment plan requires that exact updater destination.
Lab's later model drift invalidates its old plan. Finish or explicitly replace
the WSL plan before advancing main; publication
authorization does not make a stale host binding valid.
Lab's 59 and WSL's 55 ordinary files are native regular targets; repeat convergence,
parent preservation, actual updater invocation, old-writer refusal and fresh
ordinary SSH passed. Native markers/state remain. Maintenance was removed at
ordinary acceptance. Mac later accepted secret deployment and left maintenance
again; Lab and WSL remain in maintenance after their approved normalizations.
Sherlock and Marlowe each accepted 54 ordinary files and actual updater checks,
with private state/binding retained and maintenance removed. Existing cluster
masters do not establish fresh MFA access. Sherlock's first post-apply verification
stopped for an unknown reason; all 54 writes and first full apply had succeeded.
A separately reviewed current-state backup and remaining single nonforced full
apply/diff passed without relaxing guards. Preserve that evidence and uncertainty.
Mac subsequently accepted 56 regular targets, two full convergent applies,
controlled updater activation, old-writer refusal and fresh nonmultiplexed SSH.
Its source was already clean bf99958 at ordinary takeover; that phase had no
operator source fast-forward. Fresh current and after-init backups matched.
The later secret-canary phase backed up 58 files before advancing bf99958 to
exact green 74985d08, then made a fresh postbridge backup and passed the private
64-target preview. Automatic approval review first refused execution; a new
direct-user approval resolved that gate. The unchanged reviewed controller then
deployed eight files with mode 0600 under a new 0700 parent, with all 56 ordinary files
unchanged, two nonforced applies, empty diff, offline consumer and actual updater
checks, followed by fresh nonmultiplexed SSH. Persisted post-apply bindings were
rechecked before acceptance. Mac is the accepted secret canary, with maintenance
off and enrollment true; no credential-server authentication was tested. The existing Homebrew
chezmoi, verified against its official bottle, was reused without installation;
root/staff .config mode 0770 and other
parents were preserved. Non-TTY agent startup is not GUI/p10k acceptance. The user
explicitly deferred Windows' ordinary-user execution/ACL gate;
do not retry automatic de-elevation or claim Windows acceptance. Preserve
specific auth/privilege/site/ownership boundaries and unfinished secret enrollment.
Lab retains a legacy-submodule warning; WSL retains that warning and 11 preexisting
missing tmux plugin checkouts. Shell/native acceptance is not full application
readiness or GUI validation. Do not silently expand this migration into cleanup
or install unrelated components merely to erase those recorded findings.

Read AGENTS.md and docs/chezmoi-migration/{README,status,inventory,sources,
stage-3-native-config,stage-4-takeover,takeover,stage-5-ecosystem,
stage-6-retirement,support-boundary,secrets-and-ssh,fleet-rollout}.md. Read
docs/{bootstrap,payloads,shell,config-sync,update-contract,testing}.md where their
callers change. Consult the final Stage 4 ledger/review/resolutions recorded in
status; /tmp/chezmoi-stage4-ledger.md and /tmp/chezmoi-stage4-review.md are local
supplemental evidence, not substitutes for the aggregate or completion record.

Use one coordinator integration checkout and separate branches/worktrees for
write-capable workers. Freeze exclusive paths before edits and integrate
sequentially. Independent read-only audits can run in parallel. The coordinator
owns shared profiles, manifests, doctor entrypoints, root docs/instructions,
mirrored skills, runners, hooks and CI unless explicitly delegated. Do not edit
the same checkout concurrently. Preserve recoverable patches and obtain
independent read-only review of the final aggregate.

Stage 4 candidate behavior: setup-host defaults to native provisioning, reuses
an existing minimum-satisfying chezmoi, and otherwise installs pinned
SHA256-verified v2.74.0 at ~/.local/bin. Unix uses
S4-chezmoi and H7-native; Windows W1-chezmoi and HW-native. setup-host never
initializes/applies configuration or creates the ownership marker. Its HUMAN
handoff points to takeover.md. Explicit --legacy-stow / -LegacyStow retains the
old setup-sync/Stow path. Native doctor omits Stow/parser requirements; legacy
mode still checks them. Do not reimplement this split or create a sync venv.
Sherlock's glibc 2.17 rejects the generic Linux artifact; 77bb03e selects the
verified official static musl build that passed an isolated native probe.
Do not infer a production installation from that probe or broaden path conventions.

The frozen native binding is ~/.config/dotfiles/native, a regular non-symlink
file with exactly three LF-terminated lines: dotfiles-chezmoi-v1, canonical HOME,
canonical repository root. Existing ~/.config/dotfiles/maintenance suppresses
future dotfiles/payload hooks and workers, including later logins. It does not
stop already running workers. Native config/cache/state are explicitly scoped
to ~/.config/chezmoi/chezmoi.toml, ~/.cache/chezmoi and
~/.local/state/chezmoi/chezmoi.boltdb. Preserve lib/chezmoi-guard.sh/.ps1 and
their direct-writer/explicit-destination guards while supported callers exist.
Never create another revision receipt, fleet registry or migration daemon.

Require Stage 4 safety-review closure before lifecycle simplification: routine
updates preserve existing regular files and foreign links newly introduced into
the managed set; missing/empty native state requires inspected recovery; repeat
init preserves encryption/backend and unknown local data; Windows finds the
provisioned binary without assuming .local/bin is on PATH and dispatches both
hooks from the validated source binding; malformed extra marker bytes are
rejected. Check actual regression results, not just patch presence. Keep
regular-file mode explicit in init and both adapters; stale local symlink mode
must not recreate source write-through. POSIX root-ancestor checks must not form
double-leading-slash UNC paths under Git Bash. Keep native
fast-forward-only updates, dirty/divergent refusal, no force/stash/rebase,
bounded noninteractive execution and generic nonsecret failure messages.

Preserve the directory correction: native file apply, diff and update explicitly
use --exclude=dirs; no effective config-key replacement was found in v2.74.
The operator inspects managed --include=dirs relative to canonical destination,
with ancestor ownership/type/reparse/mode/ACL checks, then runs native
apply --include=dirs --recursive=false only for exact still-absent directories.
An empty list skips preparation; zero target arguments would select all dirs.
Future missing parents require reviewed preparation, never an automatic creator
or all-directory fallback. Earlier files or source Git may already change before
failure. Existing private parents need separate permission review. Lab selected
local native umask 077 to preserve known 0600 files; do not impose a global umask
or silently chmod shared parents. The actual updater acceptance runs in a fresh
interactive session after controlled maintenance removal, with payloads off;
a maintenance/opt-out skip proves suppression only. Restore maintenance on failure.

D6, D9 and D11 are resolved. Preserve the thin automatic native dotfiles login
adapter, the declared current-layout support cutoff without an all-host waiting
gate, and authorized agent execution on reachable hosts. D7 remains unresolved:
whether upstream payload installs/updates become explicit-only. Present the
concrete choice before changing that lifecycle. D6 does not answer D7.

Follow stage-5-ecosystem.md's exact retained/deleted caller tables. First audit
provisioning step IDs, asset ownership and doctor advice. Keep package managers
and config/bootstrap's existing manifests authoritative; no duplicate package
inventory or general orchestration framework. Bounded externals need destination,
current owner/updater, local-edit handling, .git need, verification/ref policy
and refresh timing justified before implementation. Ordinary apply remains
configuration-only, with no hidden install, sudo, authentication or HPC build.
Keep no-rc flags, pinned-download gates, inspect-only vendor boundaries, shared
Homebrew protections and write-free offline doctor/setup-host --check.

If D7 selects explicit-only payloads, remove profile auto callers, scheduler-only
--auto/--worker/-Worker paths, session markers, days/retries and stamp/failure/log
readers together only after the supported caller contract changes. Otherwise
retain them. Shared legacy callers cannot be broken merely because native ones
were removed; defer their code to Stage 6 rather than create a second scheduler.
Keep explicit sync-payloads/sync-skills small, bound to the correct source, using
upstream installers and config/payloads.tsv platform/channel interfaces. Kit
channel 0.7 has no native Windows install. Preserve local edits, bounded private
download staging, no pipe-to-shell and honest busy/person-required/failure
results. Preserve Windows stamp-publication correctness while that code exists.

Sherlock's host profile now sets DOTFILES_PAYLOAD_AUTO_UPDATE=0 because current
site rules forbid detached login-node workers. This required site override does
not settle D7 globally. Preserve explicit sync-payloads under site/allocation
rules; only remove the variable if all automatic callers are removed and the
no-worker guarantee remains. Before cluster work, re-read current site/topic
rules through the existing authorized master. Never authenticate for the user,
use a foreign/global toolkit in place of project-pinned shk, or build an HPC
environment outside an allocation or under SCRATCH. Respect OneDrive independent
clone rules and one operation owner per home/checkout.

User-approved secret scope is eight static Claude files for lab, Mac, WSL,
Sherlock and Marlowe plus independent recovery recipient R. Each ciphertext must
include those six public recipients; R alone can recover all eight files. Host
private identities remain local and only public recipients are exported. The
default-off local enrollment gate still excludes win/common-only, including with
true opt-in, and rejects malformed flags. Do not ask again for this scope or infer
new targets. Mutable Codex auth remains excluded and requires host-local login.
Apple Passwords is selected and sync to a second usable device is confirmed,
and R was generated privately on Mac. The user reported RECIPIENT_MATCH=PASS and
RETRIEVED_R_ONLY_CHALLENGE=PASS from the local retrieval script, then explicitly
confirmed full retrieval from the saved item on another device. Custody is now
established. Do not repeat the exclusive-output generation/retrieval steps.
All five host identities were generated locally and eight production inputs were
encrypted for the exact six recipients. Each host and retrieved R passed
all-eight recovery; only ciphertext entered published source 74985d08.
Actual deployment remains a separate host gate. Mac's eight-file deployment is
accepted as recorded above; Marlowe's actual deployment and final persisted-binding
acceptance also passed. Lab, WSL and Sherlock enrollment flags
remain false. Lab and WSL each received a separate direct-user one-file force
exception for typed-equivalent Codex serialization. Both executed once, preserving
typed values and all other targets, followed by nonforced repeat and empty diff.
Do not repeat those normalizations or infer routine force authority. Both hosts
remain in maintenance. Lab's process-observation PermissionError preserved all
97 file/44 directory bindings; a narrow process-exit guard correction passed
six tests and independent review, then a new 67-target private review passed.
That preview is now historical: a later read-only guard found one changed
native-owned top-level model value in Lab's live Codex config. The file remains
4140 bytes/0600; all other protected bindings and 69 backup readbacks match.
The writer is unknown. Preserve that current model until its intended scope is
resolved, then prepare a fresh review. Never silently rebind the old plan or
repeat its one-time force exception. WSL's current read-only guard still passes;
its expired local control socket needs a retained channel through the existing
verified BatchMode route before execution. Neither follow-up audit wrote to HOME.
Keep both failed capsules. WSL's fresh continuation bound actual normalization
and accepted Mac evidence, backed up 57 files and passed its 63-target review.
Automatic approval review then refused both secret applies before execution,
recognizing the normalization approvals but not prior D11/scope authority for
deployment. Exact deployment confirmations were requested and remain pending;
do not retry or reroute without resolving that specific gate. Read the latest
outcome in stage-4-evidence.md.
All five task-installed Bitwarden clients were
removed; Sherlock never installed one and its Bitwarden tooling proposal is canceled.
Consult the private record and never log names/values here. SSH stays ordinary.
Sherlock kit 0.6 still needs reviewed channel-0.7 upgrade before secret deployment;
the official source review and separate local pinned sherlock-kit v0.6.0
controller proposal were prepared. The user approved the dependency, which was
installed separately and passed doctor, and explicitly authorized a new job.
No repeat approval or mandatory existing job ID is required. Current numbered
site Rule 10 still requires ten useful minutes per job; no qualifying bundle
or existing allocation is established. Do not submit a tiny/padded job or
repeat checks solely to fill time. Read stage-4-evidence.md
for the current decision and concrete proposal before acting.
Before runtime provisioning, Marlowe's inspected shell selected system Python
3.10.12 and its exact micromamba login prefix contained neither Python nor Node.
The allocation-only solver proposed 27 additions and zero removals, retaining
all 32 existing package records. Actual preparation job 552957 verified the
27 archives and inspected 7,355 destinations with zero collisions or package
scripts, while preserving the prefix. Native installation then ran once in job
553033 and succeeded with 59 records/original 32 preserved, but its postcheck
rejected 3,342 new files whose upstream archive modes retain real group write.
All 759 new directories are 0700. Subsequent job 553043 repaired exactly those
3,342 new file modes, preserving bytes, original records, parents and all other
bindings. Isolated Python 3.14.4, tomllib and Node 26.0.0 probes passed; runtime
acceptance is complete. Do not rerun installation or repair. Fresh consumer
inspection subsequently passed. A verified 56-file backup and exact clean
bf99958-to-74985d08 source fast-forward completed with all live config/ordinary/runtime
bindings preserved. A fresh 56-file backup and all 62 private target previews
then passed. Actual eight-file deployment passed two nonforced applies, empty
diff, offline consumer, updater and existing-master access. All 54 ordinary
files, runtime and existing parents remained unchanged; files are 0600 and the
new parent 0700. Final acceptance rechecked the persisted post-apply binding
without a new baseline; maintenance is off and enrollment true. Existing-master
access does not establish fresh MFA or credential-server authentication.
Do not repeat the completed backup, source bridge or apply. An initial automatic
approval denial of the bridge was resolved by a new direct-user approval for
the unchanged reviewed command.
Consult current Stage 4 evidence before proceeding. Native Codex
is separately absent from inspected PATH. Kit 0.7 presence is not proof of
usable accounts. Resolve required runtime provisioning under current site rules
before claiming consumer readiness; native Codex auth remains separate from
Claude scope. No production dummy
credentials, private keys in Git, recurring OAuth refresh replay, or permanent
create-if-missing auth seeds. Keep consumer paths, app-written auth, SSH trust
and the existing recovery channel. Secret enrollment is unfinished Stage 4
operational work, not an invitation to redesign secrets during Stage 5.

Keep all legacy physical package paths and literal native bridges through this
stage. Stage 6 owns canonical source consolidation, stow-all/.stowrc/link-trust
deletion, old updater/elevated task retirement, historical Stow repairs/shim,
stow-links payload metadata and the entire parser chain: setup-sync.*,
requirements-sync.txt, .venv-sync, lib/sync-runtime.sh, lib/config_sync.py,
the four legacy sync wrappers, DOTFILES_SYNC_PYTHON and their CI/runner/hooks.
Remove old checkout diagnostics and AWESOME_SKILLS_AUTO_UPDATE only as the
coherent scoped Stage 5 deletions in the map, with notice ending its old
2027-01-31 promise. Never delete user checkouts, modules, caches or payload trees.
Exact host-side runtime retirement happens only after its callers/replacement
checks are complete under D11 and Stage 6. Old updaters can still pull a deletion
commit; a support cutoff is not a technical barrier. Quiesce exact old workers
and owned Windows task before crossing the breaking revision.

Preserve seven explicit local [data].host roles, native source totals and all
portable policy values. The native AI modify templates use builtin jq/TOML,
no child jq/Python/TOMLKit; authoritative Claude arrays, local Claude model,
typed Codex ownership/retired-key enforcement and unknown live state survive.
Local TOML date/time/datetime and JSON U+FFFD are deliberately rejected before
affected-target writes; UTC is not a Windows fix. No whole-home transaction.
Read Stage 3/source evidence before touching transforms; ecosystem simplification
does not authorize policy changes. Preserve non-exact shared parents, binary/
empty/CRLF data and private/executable attributes.

Do not silently raise tool floors: tmux 3.4 is a candidate, not selected merely
by this prompt; existing floor is 2.6. Keep all five tmux files, plugin/clipboard/
battery/cache/menu/reload behavior. Retain both Claude plugin IDs and root
CLAUDE.md import stub until actual client evidence supports a coherent decision.
Bash 3.2, PowerShell 7 entrypoints/5.1 profile and Python 3.11 stdlib roles remain
unless a concrete tested benefit justifies changing them. A new macOS Bash must
actually be invoked, not merely installed. No new Stow floor is needed.

Tests first for changed behavior, then focused provisioning/payload/diagnostic
suites, actual native Linux/macOS/Windows tests, tests/run.sh --ci,
tests/run.ps1 -CI, full pre-commit and independent review. Reuse the existing
legacy DOTFILES_SYNC_PYTHON read-only where old suites require it. Preserve
tests/chezmoi.* and chezmoi-takeover.*, guard/provision/update-config/recovery
modules and current platform behavior. Bootstrap e2e uses explicit legacy flow,
then native provisioning plus isolated takeover/recovery with a required native
binary and tests/test_chezmoi_takeover_recovery.py. Do not label it real HOME
migration. Every new exact candidate still needs actual hosted CI/e2e runs;
commit/publication authorization is already granted.
Record native passes/skips separately; Mac tmux 3.8 has previously recorded
adversarial-menu failures, so do not report it green or fix it silently.

Update status, inventory, canonical docs, mirrored skills and ownership/removal
tables with actual outcomes. Measure code/test reductions; do not claim startup
speedups without measurement. Record every surviving helper's reason and every
remaining legacy caller. Expand Stage 6 into the exact final deletion and
native-only verification plan plus its fresh-session prompt. Stop after Stage 5;
report incomplete Stage 4/host/recovery gates explicitly rather than erasing them.
```
