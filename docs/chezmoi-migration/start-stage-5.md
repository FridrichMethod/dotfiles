# Fresh-session prompt: Stage 5

```text
Implement only Stage 5 of the chezmoi migration when the current stage handoff
permits it. Do not restart completed Stages 1-3 or the Stage 4 bridge, treat
incomplete Stage 4 operational/candidate gates as passed, or perform Stage 6
source/runtime retirement. Read docs/chezmoi-migration/status.md first and distinguish
candidate code, actual native fixture results, hosted validation and real hosts.

Start at the canonical $HOME/dotfiles checkout on main. Inspect HEAD, branch,
status, the full staged AND unstaged diff, untracked task files and worktree list.
Read the committed Stage 4 closure record before creating a fresh Stage 5 task
worktree under $HOME/dotfiles/.worktrees/. The former Stage 4 coordinator worktree
and branch were removed after closure; start from main (a5d9ad7 or later).
Carry the complete committed result and any subsequent pending work, not the
original planning baseline or a historical whole-aggregate patch. Stages 1-4
include the Sherlock static artifact, Terminal preference, directory-mode
correction, five-host secret gate, exact tmux handoff, encrypted source and native
typed-no-op formatting correction. The user's original main tmux edits were
verified, staged deliberately and accepted by the matching fast-forward. Validate
parity and preserve a recoverable patch before moving pending work. Never
reset/stash/discard or overwrite unrelated edits.

Committed Stages 1-4 also live in the persistent main Git object store and remote;
they do not depend on /tmp surviving. The user-requested private checkpoint at
$HOME/dotfiles/.git/chezmoi-migration-recovery/20261103-checkpoint-15068b9-02
preserves all 28 migration worktree patches/untracked files, original modes and
handoff records, plus safe operator/review exports. Its readback hashes passed.
It is a historical local checkpoint, not current host status or a remote backup
of private evidence. Read its README/manifests before recovery, never blindly
apply its old whole patches to newer main. Inspect later commits/diffs first.

Runtime bf99958 passed all three jobs of CI 41567805090 and all eight jobs of
bootstrap e2e 41567805363 and reached local/remote main. It is both the supported
Stow recovery bridge and first accepted ordinary-native release. Encrypted
source 74985d08f6ec91391e8f6ba3b54e95d08ad91d44 subsequently passed all three
CI 41586461636 jobs and all eight bootstrap e2e 41586462369 jobs before reaching
main. Carry that complete source and later outcome records. Subsequent changes
need their applicable exact gates. The user explicitly authorized
commit, publication and rollout; do not ask again for blanket authority.
Read status.md's Stages 1-4 consolidation checkpoint section (current host table
and open items) and the Stage 4 acceptance table in stage-4-evidence.md before
any action. Earlier outcome checkpoints through 12262e6 passed all three CI jobs.
The native formatting correction
15068b9936dc1bf36416d59154746e8f643d5bd5 passed all three CI 41684120644 jobs and
all eight bootstrap e2e 41684121107 jobs, then reached local/remote main. No Stage 5
execution is authorized by preparing this handoff.
All five Unix ordinary takeovers and secret enrollments are accepted. They have
accepted eight-file deployment, nonforce convergence, offline consumer and updater
checks. Mac/WSL use fresh SSH evidence; cluster masters are not fresh MFA proof.
Sherlock's source-only kit 0.7.0 upgrade passed using its existing login runtime,
with original files and links preserved. Current numbered site rules permit this
light foreground work; environment builds and heavy installs still need a job.
Windows completed native takeover on 15068b9: 26 regular targets, 61 unchanged
parents, two nonforce repeats, empty diff, both shell smokes, ordinary
Medium/non-elevated updater and same-session skip, fresh nonmultiplexed SSH and
persisted acceptance. Maintenance is off; secretEnrollment=false; five exact
operator tasks were removed. The old restow task remains disabled for Stage 6.
Do not replay completed bridge, init, conversion or deployment steps. Historical private-operator stops and their
reviewed remaining-only continuations remain in stage-4-evidence.md.
Lab's requested shared Astra/xhigh preference is applied. A later formatting-only
rewrite exposed an always-reserialize conflict. The published native typed-no-op
preservation fix passed a fresh Lab continuation: 67-target review, two nonforce
applies, empty diff, updater and fresh WSL-to-Lab SSH, with all 59 ordinary files
unchanged. Maintenance is off and enrollment true; no further force was needed.
Current integration and actual host outcomes
must be checked again rather than treating this preparation as completion.
Lab retains a legacy-submodule warning; WSL also retains 11 preexisting missing
tmux plugin checkouts. Do not expand this migration into unrelated cleanup.

Read AGENTS.md and docs/chezmoi-migration/{README,status,inventory,sources,
stage-3-native-config,stage-4-takeover,takeover,stage-5-ecosystem,
stage-6-retirement,support-boundary,secrets-and-ssh,fleet-rollout}.md. Read
docs/{bootstrap,payloads,shell,config-sync,update-contract,testing}.md where their
callers change. Consult the final Stage 4 ledger/review/resolutions recorded in
status. The former /tmp/chezmoi-stage4-ledger.md and /tmp/chezmoi-stage4-review.md
are preserved, with the rest of the cited /tmp evidence, on lab-ubuntu only, in the
private unpushed
$HOME/dotfiles/.git/chezmoi-migration-recovery/20261103-consolidation-a5d9ad7/tmp-evidence/
(manifest ../tmp-evidence-manifest.sha256). Read them there; they are local
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
Windows updater hardening candidate: a Codex desktop sandbox group holds an
inherited Modify grant on ~/.local (including ~/.local/bin) on the win host.
chezmoi.exe itself carried no such grant when checked, but files created there
inherit it. Review or restrict that grant first, or verify the executable's
owner/ACL/hash before running it. Secondary: scripts/chezmoi-update.ps1 takes the
first chezmoi Application on PATH, so a planted chezmoi.com could shadow the
provisioned ~/.local/bin/chezmoi.exe; prefer that exact path. Dotfiles did not
create those grants.
Also carried into Stage 5: native commands without the updater's full explicit
argument set use a separate ~/.config/chezmoi/chezmoistate.boltdb (set
persistentState in the config template with a reviewed re-init, or keep the
full-argument rule; see takeover.md), and a portable transport watchdog is only a
design question. The Claude settings modifier now matches the Codex typed no-op
preservation, so Claude Code's own insertion-order rewrites no longer stop nonforce
login updates. Codex is different: as observed, an app-server writes its in-memory
copy of ~/.codex/config.toml back shortly after starting. On WSL one that the Mac
Codex app started a second before the bcf5c0d login update wrote the old owned
tui.status_line back and left status MM until a reviewed one-file reconcile (see
status.md). Decide whether tui.status_line stays owned or becomes a seed-only
default; never clear such a stop with a routine force.

Preserve the directory correction: native file apply, diff and update explicitly
use --exclude=dirs; no effective config-key replacement was found in v2.74.
The operator inspects managed --include=dirs relative to canonical destination,
with ancestor ownership/type/reparse/mode/ACL checks, then runs native
apply --include=dirs --recursive=false only for exact still-absent directories.
An empty list skips preparation; zero target arguments would select all dirs.
Future missing parents require reviewed preparation, never an automatic creator
or all-directory fallback. Earlier files or source Git may already change before
failure. Existing private parents need separate permission review. On Windows, a
new win-applicable target under an EXISTING parent inherits that parent's ACL:
name the parent's ACL model for each new win target and reuse the reviewed
protected-materialization step when the parent is broader than the intended file
ACL. Lab selected local native umask 077 to preserve known 0600 files; do not
impose a global umask or silently chmod shared parents. The actual updater
acceptance runs in a fresh
interactive session after controlled maintenance removal, with payloads off;
a maintenance/opt-out skip proves suppression only. Restore maintenance on failure.

D6, D9 and D11 are resolved. Preserve the thin automatic native dotfiles login
adapter, the declared current-layout support cutoff without an all-host waiting
gate, and authorized agent execution on reachable hosts. D7 remains unresolved:
whether upstream payload installs/updates become explicit-only. Present the
concrete choice before changing that lifecycle. D6 does not answer D7.
Observed awesome-skills inputs for D7: Sherlock's installer refuses the
site-mandated scratch-backed ~/.cache symlink; Marlowe's run stops for a person
on the legacy ~/.codex/skills root above the 1990-folder limit; native Windows has
no payload state yet, so its first ordinary interactive pwsh login will install
skills in the foreground.

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
Actual deployment is accepted on all five Unix hosts; Windows enrollment is false
by design.
Sherlock's earlier post-repeat metadata guard cause remains unknown; a separately
reviewed remaining-only continuation passed empty diff, offline consumer, updater,
existing-master access and persisted-binding acceptance without replaying
deployment. Maintenance is off and enrollment true. All specific
deployment approvals are now resolved. Lab and WSL's historical one-file
normalizations ran once; preserve those receipts and never reuse failed capsules.
Lab's later explicit Astra/xhigh correction also passed, followed by a new
formatting-only rewrite. The current source fix preserves validated typed no-ops
for both Codex and Claude and retains all unsupported-input and genuine-conflict
protections. Exact CI/e2e
and actual Lab acceptance passed; see the current Stage 4 evidence.
All five task-installed Bitwarden clients were removed; Sherlock never installed
one and its Bitwarden tooling proposal is canceled. SSH stays ordinary.
Sherlock's separately approved local pinned controller remains outside dotfiles.
The official kit 0.7.0 source-only upgrade passed on the login node, preserving its
previous release, links and existing runtime. No allocation/job ID is required
for that completed light deployment; current site rules still govern later work.
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
the unchanged reviewed command. The job 553043 in-allocation probes above do not
cover Marlowe login nodes: a site AppArmor profile (block-node) denies node there,
so the Claude settings Node hooks (PreToolUse Bash guard, Notification,
statusLine) fail open. Codex is absent and unused on Marlowe. Both are Stage 5
product choices: accept and document, host-specific Claude settings without Node
hooks, or helpers ported off Node; descope Codex on Marlowe or use a non-node
binary. Never work around the site profile.
Consult current Stage 4 evidence before proceeding. Native Codex
is separately absent from inspected PATH. Kit 0.7 presence is not proof of
usable accounts. Resolve required runtime provisioning under current site rules
before claiming consumer readiness; native Codex auth remains separate from
Claude scope. No production dummy
credentials, private keys in Git, recurring OAuth refresh replay, or permanent
create-if-missing auth seeds. Keep consumer paths, app-written auth, SSH trust
and the existing recovery channel. Approved secret enrollment is accepted on
all five Unix hosts. Windows native takeover is separately accepted, with no
secret enrollment. This is not an invitation to redesign secrets during Stage 5.

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
native-only verification plan plus its fresh-session prompt. As the last step,
after the final Stage 5 docs land, move Lab's private
$HOME/dotfiles/.git/chezmoi-migration-recovery/ to
~/.local/state/dotfiles-chezmoi-migration-recovery/, keeping modes and
subdirectory names: copy, verify every manifest by readback, then remove the
original. Update every doc path that cites it, including the Stage 6 prompt.
The user chose this move; it is not a deletion of evidence. Stop after Stage 5;
report incomplete Stage 4/host/recovery gates explicitly rather than erasing them.
```
