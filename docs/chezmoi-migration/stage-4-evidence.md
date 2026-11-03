# Stage 4 candidate and actual-host evidence

Dates: 2026-11-02 through 2026-11-03 local. This separates accepted runtime and
actual-host evidence from unfinished rollout and secret enrollment. Read [status.md](status.md) and
[takeover.md](takeover.md) together. Stages 5/6 have not started.

## Preserved input and reviewable result

Input coordinator: `/tmp/dotfiles-chezmoi-stage3-integration`, branch
`chezmoi-stage3-integration`, HEAD `1a9d30b837b4425c8c5964bf1e0704290178d41f`.
Independent audit compared all 126 changed paths and full binary diff with
`/tmp/chezmoi-stage3.patch`: exactly 2,950,933 bytes, SHA256
`97ef649e2f7db1be4cf5ebbe04ceea917c288f6aeafd2e5ef873a814855352fe`.
There were no additional changes or untracked files at carry time. The original
coordinator was not edited. Its complete Stages 1-3 result was applied to
`/tmp/dotfiles-chezmoi-stage4-integration`, branch `chezmoi-stage4-integration`,
at the same HEAD. The complete aggregate was subsequently committed as
`e77e745`, with follow-up commits below. Review the whole result against
`1a9d30b`, including any later working-tree diff; a HEAD-only diff no longer
contains the original carried stages.

Separate Unix, Windows and provisioning worktrees returned recoverable patches,
integrated sequentially. The user explicitly authorized commits, publication
and exact-green main landing. The bridge reached main at `9c1a31f` after all
required hosted gates. The corrected release `bf99958` subsequently passed its
own hosted gates and lab ordinary takeover below. Encrypted source `74985d08`
then passed its exact hosted gates and reached main; target deployment remains
separate. Unrelated work remains preserved, including the separately handed-off
tmux fix and Windows Terminal preference.

The original main checkout's 13 untracked planning documents were verified
unchanged, moved intact to the private local
`$HOME/.local/state/dotfiles-stage4-preserved-planning-20261102/original-docs`,
and reverified against their retained manifest before fast-forward. They were
not reset, stashed or overwritten. The later two-file tmux handoff was imported
byte-for-byte from `/tmp/dotfiles-tmux-corners.patch`. Its two original main edits
were deliberately staged and accepted by the matching fast-forward, with a
fresh private target backup before lab native apply. Both source and live native
theme retain the fix; no tmux reload or restart was needed.

## Implemented contract

- A fixed private three-line home/source marker blocks old installers,
  updater/task writers and all four sync wrappers, including explicit LIVE paths.
  A separate persistent maintenance marker blocks new dotfiles/payload workers.
  Existing workers still require exact quiescence; markers are not cancellation.
- Native login updates preserve D6: once per interactive session, explicit paths,
  clean-tree refusal, fast-forward only, no stash/rebase, no login installation,
  no elevated Windows restow or UAC. `--less-interactive` adds native first-target
  conflict protection; absent/empty state refuses automatic recovery.
- Source binding selects both dotfiles and payload dispatch. Native config init
  preserves age/backend/local data through native TOML while owning safe update
  settings; unsupported local temporal values refuse config replacement.
  Init and both adapters pin regular-file mode over stale local symlink mode.
- Default setup/doctor use the native path. Explicit legacy mode retains existing
  behavior. Verified official chezmoi archives need no new parser environment.
  Legacy suites reuse an existing environment read-only.
- Takeover remains an inspected procedure with private per-target backups,
  exact owned-link conversion and recovery preserving later app edits.
  No journal, migration daemon, broad force or shared-directory ownership added.
- All 95 physical legacy package files and native policy values remain.
  Sherlock's host profile disables detached payload login workers under the site
  rules. General payload lifecycle D7 remains a Stage 5 choice.

## Fixture and review evidence

Native executables are SHA256-verified official chezmoi 2.74.0 builds retained
from earlier stages. Tests use synthetic credentials, temporary homes and local
Git remotes; they do not authenticate real applications.

Independent read-only review found five issues: new-target conflict replacement,
init loss of local config, Windows backend discovery, Windows binding dispatch,
and an unterminated fourth marker line. Regressions reproduced them before fixes.
An actual macOS run also exposed a Bash 3.2 parser failure in a command
substitution; the POSIX profile now avoids that construct. Final aggregate
results below supersede the retained earlier failed fixture attempts.

Independent fix review resolved all five findings, with 34 focused methods and
repeated original conflict/init reproducers passing. No new actionable finding
was identified. Reports: `/tmp/chezmoi-stage4-review.md` and
`/tmp/chezmoi-stage4-review-resolution.md`.

Later native Windows execution found root-ancestor paths were concatenated as
`//.config`, which Git Bash interprets as UNC and could falsely report a marker.
The guard now joins root correctly. A separate native probe found stale local
`mode="symlink"` could restore source write-through; init and both adapters now
pin file mode. Both regressions failed before fixes. Independent review passed
32 focused tests after these fixes and found no new issue.

Final-runtime Linux `tests/run.sh --ci` passed; log
`/tmp/chezmoi-stage4-linux-final2.log`. Its native aggregate ran 138 methods,
29 Windows skips, overall PASS. Native Mac `tests/chezmoi.sh` ran 138 methods,
29 Windows method skips and one optional StyLua subtest skip, overall PASS.
Its takeover runner passed 24 methods with 29 Windows skips; system Bash 3.2/sh
syntax passed. All 383 transferred source hashes/modes were unchanged. Report:
`/tmp/chezmoi-stage4-macos-report.md`. Supplemental all-role rendering is distinct
from actual native Mac execution. Full Mac legacy runner was not run because its
previously recorded standard prerequisites are absent.

Final-runtime Windows native suite ran 138 methods, 39 platform skips, overall PASS,
including all 29 Windows adapter methods. Update hooks 29 cases, profile suite,
bootstrap 33 cases, e2e harness 28 cases, payload 11 cases, installer controls
15 cases and real NTFS legacy installer 21 cases passed. The complete Windows
`tests/run.ps1 -CI` passed with `test-suite=PASS`; all 383 source hashes and
synthetic index modes passed afterward. Evidence is under
`/tmp/chezmoi-stage4-windows-aggregate-r5/`, with the final report at
`/tmp/chezmoi-stage4-windows-report.md`. Full Linux pre-commit on the final
runtime passed (`/tmp/chezmoi-stage4-precommit-final2.log`); the documentation
handoff also passed (`/tmp/chezmoi-stage4-precommit-handoff.log`).
The first Windows 135-method
aggregate exposed two test-only portable
path assertions (slash spelling and extended link prefix), now corrected with
Path identity and the original link text. Required guard dependencies were also
added to legacy fixture copies, without weakening their logger or failure
assertions. Provisioning 9 native methods and 13
manifest checks passed. Offline e2e harness passed; it does not install packages
or replace hosted bootstrap e2e. Pre-existing macOS tmux
3.8 adversarial-menu failures remain separate and unchanged. Administrative
Windows fixture tokens do not establish ordinary-user ACL acceptance.

One repeated full Windows snapshot transfer was rejected by automatic review
for insufficient explicit transfer-authorization context. The approved narrower
operation reused resident verified source and transferred only reviewed changed
nonsecret files plus integrity/isolated-runner metadata. No rejection was
bypassed, and no transfer blocker remains. All fixture source/runtime bytes
were verified independently of subsequent documentation-only record updates.

### Published bridge and subsequent corrections

| Commit | Hosted CI | Hosted bootstrap e2e | Outcome |
| --- | --- | --- | --- |
| `e77e745` | 41553620773: Linux/Windows passed; Mac fixture path failed | 41553620937: Mac/cluster/Windows fixture failures | Not landed |
| `dc2df42` | 41556058800: all three passed | 41556059382: Windows fixture working-directory issue; other roles passed | Not landed |
| `9c1a31f4efa0b23a67e9a20640a2f236eae64325` | [41558979663](https://github.com/FridrichMethod/dotfiles/actions/runs/41558979663): all three passed | [41558979671](https://github.com/FridrichMethod/dotfiles/actions/runs/41558979671): select plus all seven roles passed | Exact commit fast-forwarded to main |

The Windows correction pins the PowerShell 5 child working directory to its
fixture. The earlier generated-path provenance was not fully reproduced; the
final hosted run establishes containment for that exact candidate. Later local
commits `77bb03e` and `c4412a5` select the compatible official Sherlock static
artifact and preserve the user's additional Terminal profile with portable
environment prefixes. Their combined full pre-commit passed. At that checkpoint,
they and the subsequent changes below still needed their exact hosted gates.

Before lab target writes, actual v2.74 isolated probes showed plain apply changes
existing shared directory modes: a 0700 parent can become 0755 or 0775 depending
on umask. The effective correction is explicit `--exclude=dirs` on both native
update adapters and every operator file apply/diff. A config-key alternative
was ineffective. File-only apply does not create missing parents: the operator
inspects native managed directories, rejects links/reparse points, and prepares
only still-absent exact parents with nonrecursive directory-only apply. An empty
missing list must skip that command. Existing directory modes remain unchanged;
future missing parents require another reviewed preparation, and failed apply
is not transactional. Local native umask 077 avoids widening the inspected lab
regular targets. Existing private parents require explicit ownership/mode checks.

The regressions reproduced the unsafe mode change before the fix. Corrected
Unix adapter suite: 22 methods passed, including ambient umask 002/022 and
missing-parent refusal. Actual isolated Windows adapter suite: 31 methods
passed, with unchanged parent SDDL and missing-parent refusal; this does not
satisfy the deferred real-user ACL gate. Operator recovery suite: six methods
passed, including private missing-parent preparation, repeated convergence,
unmanaged sibling/local model retention and dangling-link refusal. Worker full
pre-commit runs passed; aggregate checks and independent review are recorded
separately when completed. Reports are `/tmp/chezmoi-directory-permissions-review.md`,
`/tmp/chezmoi-stage4-windows-directory-parity-report.md` and
`/tmp/chezmoi-operator-permissions-report.md`.

The corrected aggregate Linux `tests/run.sh --ci` passed with `test-suite=PASS`
(`/tmp/chezmoi-stage4-directory-aggregate-tests.log`). Independent cross-review
confirmed the runtime flags, five-host opt-in scope, operator patch and exact
tmux handoff. It found two documentation gaps, now corrected: pin force false
despite preserved local config, and remove the obsolete implication that fresh
native apply refuses foreign links. Full aggregate pre-commit passed
(`/tmp/chezmoi-stage4-directory-aggregate-precommit.log`); a final documentation
consistency pass is validated separately. Hosted gates were pending at that
checkpoint; the accepted exact release is recorded below.

Candidate `1c109d2` was published to CI 41566499702 and bootstrap e2e
41566499764. Its Mac CI rejected the new operator test's Linux role during
native init, correctly enforcing the actual Darwin host guard. The fixture now
selects the actual platform role for both operator cases, local config and exact
target-set expectation; no OS guard or permission assertion was weakened.
All six focused Linux methods pass. A bounded actual-Mac fixture connection
timed out before transfer or execution, so no actual-host Mac rerun is claimed.
The corrected candidate then passed fresh hosted gates before landing or apply.

The corrected exact release `bf9995809ca7564c0728f87bcbefe91c8a3cc5e0` passed
all three jobs of [CI 41567805090](https://github.com/FridrichMethod/dotfiles/actions/runs/41567805090)
and all eight jobs of [bootstrap e2e 41567805363](https://github.com/FridrichMethod/dotfiles/actions/runs/41567805363).
This includes the actual Mac operator fixture regression and required native
Windows full suite. Local `tests/run.sh --ci` and full pre-commit passed before
publication (`/tmp/chezmoi-stage4-native-role-tests.log` and
`/tmp/chezmoi-stage4-native-role-precommit.log`); the native Linux aggregate ran
149 methods with 31 Windows method skips. Commit hooks passed. Local and remote
main then fast-forwarded to this exact release, without force or history rewrite.
The later documentation-only handoff also passed `tests/run.sh --ci` against the
unchanged runtime (`/tmp/chezmoi-stage4-final-handoff-tests.log`): native 149
methods with 31 Windows method skips, final `test-suite=PASS`. Optional local
PowerShell/installed-kit checks and the real-checkout refusal under `/tmp` retain
their explicit skips; exact-release hosted platform evidence remains separate.

### Accepted lab ordinary canary

Before apply, the local native umask was set to 077 with prior config privately
preserved; all other parsed values were unchanged and native init passed. Exact
worker quiescence was rechecked, all 19 managed directories and ancestors were
real existing directories, and a new 59-target private snapshot captured the
integrated tmux fix. The older snapshot remains retained. All 59 private native
cat/dry-run outputs passed; both AI outputs matched their independently approved
policy/local-state results.

The private native ownership marker preceded all managed writes. Exactly 55
owned links were converted individually, with four reviewed regular files using
force false. Two full file-only applies converged and private diff was empty.
All 59 destinations are regular files (57 at 0600, two executables at 0700),
existing parent identity/mode/ownership remained unchanged, and source stayed
clean at the accepted revision. Shell syntax and actual zsh smoke passed. A
genuinely fresh nonmultiplexed WSL-to-lab SSH connection passed after conversion.

Controlled activation removed maintenance and started a fresh interactive Bash
through the installed profile with dotfiles updates enabled, the session sentinel
unset and payload updates disabled. Private Git trace proves one actual ff-only
pull; explicitly sourcing the adapter again skipped the second attempt. There
were no native warnings, and all target bytes/modes and parent metadata remained
unchanged. The old Stow installer then refused under native ownership with
maintenance absent. Native ownership/state remain, and normal native updates are
active. Doctor's native-config check passed; its only remaining warning concerns
preexisting retired submodule checkouts, deliberately retained for Stage 6. The
doctor is therefore not claimed to be warning-free. No GUI reload or application
authentication is inferred from these shell/access checks.

Private evidence lives under `$HOME/.local/state/dotfiles-stage4-bf99958-refreshed59`
and `$HOME/.local/state/dotfiles-stage4-bf99958-file-apply`, including exact
snapshots, command outputs, parent metadata and `activation-result.json`. These
are one-off operator evidence, not a runtime receipt database or updater input.

### Direct old-link bridge fixture

A separate reproducible local fixture cloned the source without shared objects,
started at immutable `1a9d30b`, and performed one clean ff-only merge directly
to `bf99958`, skipping ten intermediate commits. All 95 baseline physical package
referents remained regular files. Their synthetic links kept exact identity/text
and read the final Git blobs, including all five tmux files and the handed-off
theme change. The final clone was clean and all original referent bytes remain
in the private fixture backup.

The seven-role inventory additionally supplied 353 synthetic mapped links, making
448 checked links in total. Those artificial mappings include AI targets that
the real legacy installer materializes as regular files; they are not real-host
symlink counts. Git HOME/config/hooks were isolated, transport was local-only,
and no real HOME, native apply or network was used. This proves retained paths
for the compatibility bridge, not a future unsupported Stage 6 deletion jump or
native Windows ACL behavior. Report and reproducible script are under
`/tmp/chezmoi-stage4-skipped-bridge-fixture`; script SHA256 is
`22e561a82a58cc418f810e9d049f38cdcb55cbeb6762814575a55d05b45ccddb`.

### Accepted Mac ordinary takeover

When connectivity returned, the source was already clean main at `bf99958`.
This operator did no fetch or fast-forward and cannot establish how the earlier
checkout advanced. Fresh current and after-init 56-target backups matched exactly;
neither is represented as a pre-fast-forward backup. The skipped-bridge fixture
above is separate compatibility evidence.

Canonical S4-only check found the existing Homebrew chezmoi 2.74.0 sufficient.
The Cellar binary SHA256
`59d662943464e6af839ac674bac0d04bac564369463de32cab1521763d4ecfd2`
matched the independently verified official arm64_tahoe bottle. No installation
or Homebrew mutation occurred. The reviewed operator bound the launcher symlink,
canonical binary and ancestors. Six isolated actual Mac recovery fixtures passed
against this binary; five synthetic binary-binding predicates also passed.

Private native init selected host mac, umask 077 and enrollment false. Independent
semantic review approved both AI outputs, preserving local model, exact portable
arrays, typed ownership and unknown live state. All 56 previews/dry runs were
reviewed before writes. Native ownership preceded individual conversion of 53
owned links; the three regular targets and subsequent full applies used force
false. Every file operation excluded directories. Two full applies converged
with empty private diff: 56 regular targets, 55 mode 0600 and one executable 0700.
Existing parent identity, ownership, modes, ACLs and flags remained unchanged,
including root/staff-owned `.config` mode 0770.

Controlled activation proved maintenance suppression, one actual ff-only pull,
same-session second-call skip, old-writer refusal and empty file-only diff.
There were no native updater warnings or target/parent changes. Maintenance is
removed and native binding/private state remain. Fresh SSH with BatchMode,
ControlPath=none and ControlMaster=no passed and independently rechecked all
56 hashes/modes, parents, source and native state before releasing the old channel.

Shell evidence is syntax and bounded non-TTY agent zsh startup, not GUI/p10k
acceptance. The installed OMZ non-TTY/instant-prompt-off guard was checked first.
The smoke exited zero with stty/tput/ZLE terminal diagnostics; redirected Bash
reported expected job-control diagnostics. Final native diff stderr was empty.
No token, identity or R capsule was touched during ordinary takeover.

Private snapshots, approval and execution evidence remain under Mac's local
state directory. Local report:
`/tmp/chezmoi-stage4-mac-brew-review/final-report.md`, SHA256
`9bf187e70e8ffe64a3a2b6305021f8aa42158043ac4ee7fbde22d19a60ec3ac0`.
Its manifest binds the exact reviewed operator, activation and safe receipts.

### Accepted WSL ordinary takeover

Fresh preflight found clean main `9c1a31f`, 52 exact legacy-owned links and three
regular targets. Maintenance and exact worker quiescence preceded the source
fast-forward to `bf99958`. Separate private 55-target snapshots retained both
prebridge and postbridge states. The only referent byte change was the reviewed
tmux corner fix; regular app files and all parent metadata were unchanged.

Canonical `S4-chezmoi` provisioning installed the verified v2.74 binary. Private
native config/init set host `wsl-ubuntu`, local umask 077 and secrets false; safe
native Git/update settings passed. Both actual AI outputs were independently
checked for typed ownership, exact Claude permission arrays, local model and
unknown live-state preservation. WSL-specific output approvals were bound to
the fresh source/config/backup; no lab approval was reused.

Native ownership preceded conversion. All 52 links were converted individually;
regular/full applies used force false and every file operation excluded dirs.
Two full applies converged with empty private diff. All 55 targets are regular
files: 54 at 0600 and the preview executable at 0700. Existing parents retained
their metadata, including 0775 shared config children and the 0777 pet directory.
Native state is populated/private and source remained clean at the release.

Controlled activation proved one actual ff-only pull and same-session skip by
private Git trace, with no warnings or target/parent changes. Fresh nonmultiplexed
SSH, actual Bash/Zsh startup and SSH config parsing passed. Legacy Stow refused
while maintenance was absent. Native binding/state remain, maintenance is removed
and the intended automatic update policy is active.

Actual login-context doctor recorded 63 ok, zero outdated, 11 missing and one
warning, exit 1. The 11 missing tmux plugin checkouts and retired-submodule warning
predate takeover; raw-SSH Node/PATH findings disappear in the actual login
context. No unrelated plugins were installed and no interactive tmux or GUI
acceptance is claimed. This is ordinary configuration and shell/access acceptance,
not complete application readiness. Evidence: `/tmp/chezmoi-stage4-wsl-report.md`
and `/tmp/chezmoi-stage4-wsl-execution-bf999580/evidence-manifest.json`; original
private snapshots, AI outputs and activation traces remain on WSL outside source.

### Accepted cluster ordinary takeovers

Current site/topic rules were read through the existing authorized masters.
Sherlock started at clean `6db67ed` with 47 owned links, three regular files and
four absent targets; Marlowe started at clean `2c177fc` with 42 owned links, one
regular file and 11 absences. Exact prebridge backups preceded source changes;
maintenance preceded the final fast-forward to `bf99958`. Separate postbridge
snapshots and actual native AI policy/typed-local-state reviews passed. All
existing parents and their access/ACL metadata were preserved; native binding
preceded preparation of only exact reviewed absent directories.
Sherlock created one managed parent, `.config/tmux`; Marlowe created four,
`.codex/pets`, `.codex/pets/tom`, `.codex/rules` and `.config/tmux`. Each was
previously absent and created at 0700.

Canonical S4 provisioning installed verified v2.74 binaries: the official static
musl artifact on Sherlock's glibc 2.17, and the compatible Linux artifact on
Marlowe. Both local configs use umask 077 and secrets false. Each final ordinary
set has 54 regular files, 53 at 0600 and one executable at 0700. File-only
nonforced full applies converged, private diff was empty and source stayed clean.
The exact owned-link conversions alone used force.

Sherlock's existing scratch-backed `.cache` symlink received a separately
reviewed cache-only exception in the one-off operator artifact. Its link identity,
text, referent, ancestors and ACLs remain bound across phases; only the absent
private chezmoi cache child was created. Wrong/replaced links and a link replaced
by a real directory were synthetically refused before native commands. Managed
parents, source, config, state and keys retain their strict boundaries; no durable
state was moved to scratch and no cache link or parent permission was changed.

Sherlock's original file phase completed all 54 individual writes and the first
full file-only apply with exit zero, then stopped during subsequent verification.
Its generic dispatcher discarded the exception detail, so the historical cause
remains unknown. Maintenance and native ownership stayed active. A read-only
audit and exact verifier replay found all 54 approved bytes/modes, parents,
cache metadata and clean source unchanged. A new private current-state backup
preceded the separately reviewed continuation, which performed only the remaining
single nonforced full file apply, all target checks and empty diff. Original
guards were unchanged; changed-current-file fixtures refused before writing.
The continuation passed and preserved original backups. Its SHA256 is
`27d27bf9c760f2ea4f17fe313d37ee9ba0426a83a2849893dbc2ca3d8a25f3d6`.
This is a verified bounded continuation, not a reproduced or diagnosed original
failure and not a claim of transactional recovery.

On each cluster, actual shell syntax, maintenance suppression with updates
enabled, controlled interactive native updater activation and old-writer refusal
passed. Private Git trace proves exactly one ff-only pull and same-session skip.
Maintenance is removed and native state/binding remain. Existing authenticated
masters were retained; no new login/MFA or GUI/account session was attempted.
That access limit remains explicit and does not become a synthetic fresh-login
pass. No host identity, token file or production ciphertext was accessed.

Marlowe's offline doctor in the explicit login-bin/system PATH recorded 36 ok,
19 missing, one outdated and eight warnings, exit 1; native-config and chezmoi
passed. Some Lmod/miniconda warnings depend on that non-login probe context.
Separate normal Bash-login probes confirmed Python 3.10.12 and no Node/npm; the
available python3 module yielded 3.9.21; the other module queries did not establish
an available node/nodejs module.
Kit 0.7 and the native Claude path exist, but launchers require Python 3.11+ and
Claude Node helpers need their runtime. Native Codex is absent from inspected
PATH. These consumer prerequisites remain open; no package/environment was built
or account invoked to hide them. Ordinary configuration acceptance is distinct
from complete bootstrap/application readiness.
Sherlock's offline doctor recorded 40 ok, 18 missing and six warnings, exit 1;
its chezmoi/native-config checks passed. Node was absent from that probe PATH.
Remaining tool/plugin/theme prerequisites were not installed as part of takeover.
Final report: `/tmp/chezmoi-cluster-takeover-report.md`, SHA256
`557dbd0f222d686f8d65ebc9dfee7df72104c5f26c3aaec5596b9c94d2687bd9`.
Private source snapshots and command outputs remain under each host's
`$HOME/.local/state/dotfiles-stage4-bf999-{prebridge,fresh,run}`; the third Sherlock
snapshot uses the separate `dotfiles-stage4-bf999-postapply-review` directory.
Only metadata receipts were transferred to the coordinator.

## Actual fleet outcomes, separate from fixtures

| Host | Actual observation | Takeover outcome / blocker |
| --- | --- | --- |
| lab-ubuntu | All 59 ordinary targets and updater/access accepted. User-approved normalization passed once. After the reviewed process-exit guard correction, fresh 69-file backup and all 67 target previews passed | Secret apply rejected by automatic approval review before execution; specific deployment confirmation pending. Maintenance on, enrollment false. Failed capsules retained; no second normalization. Retired-submodule warning belongs to Stage 6 |
| mac | Ordinary takeover accepted 56 targets. Secret-canary preparation backed up 58 files before and after the exact `74985d08` fast-forward. After new direct-user approval, actual eight-file deployment and fresh SSH passed | Secret canary accepted: two nonforced applies, empty diff, offline consumer and actual updater passed; 56 ordinary files and shared `.config` 0770 preserved. Maintenance off, enrollment true. No GUI/p10k or credential-server authentication claim |
| wsl-ubuntu | Ordinary takeover accepted 55 files and updater/fresh SSH. User-approved normalization passed once; fresh continuation bound actual Mac acceptance, retained maintenance, backed up 57 files and passed all 63 target previews | Secret apply rejected by automatic approval review before execution; specific deployment confirmation pending. Maintenance on, enrollment false, secret parent absent. Existing 11 tmux prerequisites and retired-submodule warning remain |
| win | Last checkout preflight: main `7edf12fb5b61b6e6d96703bc67f4521e69501d0c`; 26 targets, 23 exact links and three regular files. Both NoProfile profile paths match. The appended Terminal profile is preserved with equivalent environment-variable prefixes | Not migrated; user deferred the required ordinary-user execution/ACL check. SSH is administrative; bounded automatic de-elevation did not complete the target audit. No task, marker, target or production ACL change |
| sherlock | Clean `6db67ed` reached exact green `bf99958`; verified static musl installed, private pre/post/current backups, all 54 regular files, empty diff and actual updater passed | Ordinary takeover accepted; parents/cache preserved, maintenance removed and native binding/state retained. Historical postcheck cause unknown; reviewed continuation passed. Identity and eight-file crypto checks passed; kit 0.6 upgrade/site allocation gate deployment; master is not fresh MFA proof |
| marlowe | Runtime installation/repair and consumer checks passed. Verified 56-file backups before and after exact BF-to-749 source fast-forward preceded all 62 target previews. Actual eight-file deployment, nonforced repeat, empty diff, offline consumer, updater and existing-master access passed; 54 ordinary files and runtime/parents unchanged | Secret deployment accepted after rechecking persisted post-apply bindings. Maintenance off, enrollment true; eight files 0600 in a new 0700 parent. Earlier bridge approval denial resolved by new direct-user approval. No fresh MFA or credential-server authentication claim; native Codex is separate |

Lab, Mac, WSL, Sherlock and Marlowe ordinary native takeovers are accepted as described
above, with application and access limits retained. Other hosts are recorded
independently. Subsequent private cryptographic enrollment and accepted Mac
secret deployment are recorded below. D11 and explicit publication authority remain in force;
they do not replace exact-candidate CI or concrete host prerequisites.
Do not relabel an offline/site/token blocker as a successful migration.

## Secret choices and custody

Private proposal: `/tmp/chezmoi-stage4-private/secret-proposal.md`, directory 0700,
files 0600. Exact candidates, consumers and ownership evidence stay there.
Current channel-0.7 public consumer code was checked against upstream without
reading credential values. The user approved eight static-for-consumer files,
lab/mac/WSL/Sherlock/Marlowe recipients plus independent recovery, and account-label exposure in
encrypted filenames. Five Codex mutable auth files remain excluded. The user
chose to keep seven SSH snippets in their ordinary mappings.

The user selected Apple Passwords and confirmed synchronization to another usable
device. The personal item is `dotfiles age recovery`; the user subsequently
confirmed full retrieval on another device. R alone must recover all eight files; host
private identities stay local and only public recipients are exported. A same-disk
`.secrets` directory is not independent recovery custody. Independent R was
generated in a private Mac handoff directory using the unchanged verified
v2.74 binary and already-green bridge age evidence. Native generation, public
recipient conversion and public R-only challenge encryption passed without
exporting or printing R. The user subsequently reported
`RECIPIENT_MATCH=PASS` and `RETRIEVED_R_ONLY_CHALLENGE=PASS` from the local check
using only the returned identity. The script's reminder correctly states that
it cannot establish independent second-device retrieval. The coordinator asked
only for that remaining explicit confirmation, which the user supplied. Recovery
custody is now established. Do not rerun
generation or the exclusive-file retrieval step merely to repeat completed
checks. This isolated custody step wrote no managed target, host identity or
production ciphertext and read none of the eight token files. A later extra
metadata-only SSH check timed out; that does not invalidate the completed
generation result or establish custody. Codex mutable auth remains
application-owned; each host needs its own login state.

### Actual host identities and private ciphertext preparation

All five Unix hosts generated a separate native age identity locally, with a
0700 identity directory and 0600 single-link identity. Only public recipients
left their hosts. Existing native configuration and the false enrollment flag
were preserved. Mac retained its existing root-owned shared parent permissions.
Marlowe's NFS ACL projection required a narrowly reviewed metadata validator:
owner-only access, zero group/other permissions, no named/default ACL entries,
and exact before/after ACL preservation. No chmod or setfacl was used to alter
existing parent access. The ordinary takeover receipts remain separate evidence.

The Lab producer entered persistent maintenance, rechecked the reviewed v0.7
consumer contract and privately backed up the exact eight owned 0600 inputs.
The existing Claude process was retained: inspected public code and descriptor
metadata established that it only reads these static inputs; no process argv,
environment, unrelated auth bytes or user process was exposed or terminated.
Stable file descriptors and before/after cohort checks guarded native encryption.
The five excluded Codex records were checked only for unchanged metadata.

Native `add --encrypt --recursive=false` in an isolated private source produced
exactly eight `encrypted_private_` leaves, each for the five approved host public
recipients plus independent R. No `create_`, `exact_`, template or runtime script
was introduced. The private producer capsule contains plaintext backups and must
never be copied wholesale. Only the eight ciphertexts and private verification
manifest were staged for recipient checks. No private identity or plaintext is
part of the candidate source or CI inputs.

Lab, Mac and WSL each decrypted all eight using only their own identity and
matched the producer's private equality checks. Mac separately verified all
eight using only the retrieved R identity; the original recovery identity was
not opened. Both clusters subsequently passed all eight with their own local
identities: 48 private equalities across six recipients. A disposable outsider
was rejected by all eight. These checks establish cryptographic access and
byte equality, not issuer validity, expiration, successful account login or
application/API acceptance. At that checkpoint Mac and WSL had no `.secrets` directory;
all five host enrollment flags remained false at that cryptographic checkpoint.
Both clusters also retained absent
`.secrets` directories and unchanged ordinary/config/state targets. Lab
maintenance remained active.

Cluster verification used existing authenticated masters and only lightweight
native crypto checks. Sherlock transfers used the separately pinned controller's
`shk push --anywhere`; Marlowe used the existing SSH master with rsync. Exact
13-file staging inventories, hashes and private modes were checked before helper
import. Sherlock's old system Git could not run the guard flags, so the final
operator bound the existing login-environment Git 2.55.0, without installation
or PATH changes. Its existing group-write mode was accepted only behind real
owned 0700 HOME with no ACL and a single-link binary; broader HOME permissions,
named ACLs or a second hardlink refuse before Git runs. Marlowe used system Git
2.34.1. These narrow operator checks do not change runtime floors or package modes.

After a fresh guarded two-pass check confirmed the authoritative Lab inputs
unchanged, the coordinator copied only the exact eight verified ciphertexts into
`home/private_dot_secrets`. No private manifest, plaintext or identity entered
the worktree. A targeted Git `-text` attribute preserves their verified bytes;
the source guard accepts only eight private encrypted Claude leaves with six
native recipient stanzas. Stanza structure is not the access proof: the actual
six independent recipient operations above provide that proof. Existing secret
scanners remain enabled with no new exclusion.

Private evidence is retained in
`/tmp/chezmoi-stage4-secret-enrollment/phase-A-report.md`,
`/tmp/chezmoi-stage4-lab-secret-operator/run-result.json` and
`/tmp/chezmoi-stage4-secret-enrollment/phase-C-verified-report.md` and
`/tmp/chezmoi-stage4-secret-enrollment/all-six-production-verification.json`.
The actual producer manifest is kept outside Git. Synthetic operator tests,
host metadata receipts and these real decryptions are distinct evidence.
### Published encrypted source

Commit `74985d08f6ec91391e8f6ba3b54e95d08ad91d44` contains only the eight
approved ciphertexts, their byte-preserving attribute, source guard and evidence
updates. A private scan of all 391 working-tree files and all 391 indexed files
found none of the eight plaintext inputs or private-key material. No scanner
exclusion was added. Keyless fixtures retain all ordinary seven-role totals with
enrollment disabled. Local native validation ran 150 methods with 31 Windows
method skips on Linux; the complete local runner, full pre-commit and independent
review passed.

All three jobs of
[CI 41586461636](https://github.com/FridrichMethod/dotfiles/actions/runs/41586461636)
and all eight jobs of
[bootstrap e2e 41586462369](https://github.com/FridrichMethod/dotfiles/actions/runs/41586462369)
passed for that exact commit before local and remote main fast-forwarded to it.
Lab's fresh 69-file prepublication backup and final metadata guard passed before
the fast-forward; maintenance remained on. This publication is separate from
host opt-in, target deployment and account authentication. The immutable supported
Stow recovery bridge and first accepted ordinary-native release remain `bf99958`.

The first deployment attempt selected Lab as canary; cluster consumer/site gates
remain. Later ordinary-source metadata checks found Mac
still clean at `bf99958` and WSL already clean at `74985d08`. WSL's Codex target
had changed timestamps only, with the same inode, size, mode and ACL; that
metadata-only check did not establish content equality or attribute the writer.
A subsequent actual native read-only preview compared all ordinary bytes using
the existing false config, `/dev/null` state and an absent cache path. Mac's
56 files all matched. WSL matched 54 of 55; only its Codex config differed,
1,547 versus 1,556 rendered bytes, with recursively identical TOML keys, types
and values. Both hosts retained all target/config/state/parent metadata, absent
secret parents and false enrollment; the cache path remained absent. No config
bodies left either host. WSL therefore required its own specifically reviewed
regular-file serialization decision; the Lab proposal did not authorize WSL force.
A WSL-specific operator bound that actual 55-file metadata inspection, exact
source, false enrollment and absent secret parent. It prepared fresh target/state
backups, one targeted normalization, a nonforced repeat and empty diff while
preserving the other 54 targets. Three focused isolated tests and independent
review passed. Its separate exception initially awaited approval; the later
approved execution is recorded below.
Because Lab's regular-file exception then awaited a decision and Mac passed all 56
ordinary-byte comparisons, the coordinator selected Mac as the alternate secret
canary allowed by stage-4-takeover.md. This is an execution-order decision, not
an accepted deployment. The prepared Mac gate must bind its explicit selection,
exact green source and six-recipient evidence without inventing a Lab acceptance
receipt. Expansion still requires an actual accepted canary and fresh access.

Mac subsequently completed the actual prebridge phase: maintenance and worker
suppression passed, 58 files were privately backed up, and clean source advanced
from `bf99958` to exact green `74985d08` with an ordinary fast-forward. All 56
ordinary files, native config/state, parent permissions and existing verified
Brew launcher binding were preserved. A fresh 58-file postbridge backup and
native review then passed the exact 64-target set, all 56 ordinary byte matches,
all eight approved secret equality checks and typed config preservation. With
the secret parent still absent, no successful file dry run is claimed.

Automatic approval review rejected the final Mac apply twice before process
creation. Its stated reason was that the earlier direct-user rollout authority
appeared only as coordinator-relayed context to that reviewer. The second
submission provided the existing scope, custody and exact-green evidence; it was
also refused. The coordinator requested a specific direct approval for this
already-prepared Mac operation, without reopening recipient scope or blanket
D11 authority. No third attempt or alternate execution route was used. At this
checkpoint Mac maintenance remained on, enrollment false and `.secrets` absent;
the old SSH channel and both backups remained available. No managed deployment
or fresh-access acceptance is claimed.

Before the second policy submission, independent inspection found a separate
controller-only transport-failure gap. The corrected wrapper attempts the same
pinned maintenance-restoration path after SSH timeout, unsuccessful exit or
unreadable receipts and reports restoration only when confirmed. Ten isolated
failure cases passed. Native deployment code, force=false and actual plan
bindings were unchanged; these tests are not host execution evidence.

### Accepted Mac secret canary

The user subsequently approved the exact prepared Mac deployment directly.
A fresh metadata-only check confirmed clean `74985d08`, all retained bindings,
maintenance on, false enrollment, absent secret parent and the held SSH channel.
The same reviewed controller then passed automatic approval review and executed;
no alternate route or unreviewed retry was used to evade the earlier denials.

Actual native deployment enabled the local enrollment flag, created only the
0700 secret parent and eight 0600 files, preserved all 56 ordinary files and
existing parent permissions, passed two nonforced applies and an empty full diff,
and verified offline consumer readability. The real updater performed one
fast-forward-only pull and skipped its second same-session invocation. Fresh
nonmultiplexed SSH passed. The coordinator then checked the actual apply/fresh
receipts and revalidated persisted post-apply bindings before writing acceptance.
Mac is the accepted secret canary; maintenance is off and enrollment is true.
These checks do not test the remote credential issuer or an authenticated API.
The old access channel and both private backups remain available.

### Lab secret preview and one-file serialization gate

The first post-publication private preview stopped after 12 native commands:
the strict ordinary-file comparison found that `$HOME/.codex/config.toml` was
4,131 bytes while native rendering produced 4,140 bytes. Recursive TOML
comparison established identical keys, types, values, arrays and nesting. The
trimmed-line multiset was identical; indentation, one blank line and assignment
order differed. The historical writer is unknown. No live config, target or
native state changed during this refused preview. Lab maintenance stayed on,
and the failed private review capsule and fresh 69-file backup were retained.

A private copy using the actual original/canonical bytes reproduced native
nonforce conflict refusal with exit 1. A separate isolated proof used exactly
one targeted force operation, preserved all typed values and mode 0600, and
passed an unchanged nonforce repeat and empty diff. It accessed no production
HOME. A small one-file operator was then prepared with fresh durable target/state
backups, unchanged guards for the other 66 managed files and five excluded auth
siblings, one-force-only enforcement, and no retry or rollback. Three isolated
native/guard tests and independent review passed. Those are preparation results,
not a live normalization or deployment outcome.

The original Stage 4 specification permits force only for individually reviewed
backed-up link conversions. This target is a regular file, so the coordinator
requested a separate explicit exception for this exact serialization change.
Normal update and secret deployment remain nonforced; the strict ordinary-byte
canary guard remains intact. Any accepted normalization must precede a fresh
canary plan in a new capsule, never a blind retry of the failed preview.

The user later approved the exact Lab and WSL one-file exceptions separately.
Both executed once and passed fresh target/state backups, recursive typed-value
preservation, a nonforced repeat and empty targeted diff. Lab preserved its other
66 files and five excluded auth siblings; WSL preserved the other 54 ordinary
files and left its secret parent absent. Neither operation enabled secrets, and
both retained maintenance. No repeat normalization is authorized by that result.

Lab's newly inspected 67-target preview then stopped at process observation:
PermissionError while enumerating one candidate process's `/proc/PID/fd`.
All 69 private backups and the disabled config candidate completed; no enabled
native candidate command, target cat, dry run or apply ran. All 97 protected file
and 44 directory bindings still matched. That PID was absent at the subsequent
bounded check, which does not establish the historical reason for EACCES.
The failed capsule is retained while the process-exit case is diagnosed; live
inaccessible candidate processes must still fail closed.

A separate narrow guard variant now rechecks metadata after PermissionError
and skips only confirmed vanished, zombie or out-of-scope processes. Live
same-user and uninspectable candidates still refuse. Six focused synthetic
methods and independent review passed. Original operators and both failed
capsules remain immutable. A fresh plan differed only in the reviewed helper
binding, with all other files and 44 directories unchanged. The new actual Lab
review passed 69 fresh backups, all 67 native target equalities and an empty
eight-target dry run. No further normalization was performed.

WSL separately retained its original normalization maintenance marker, bound
the actual accepted Mac receipt and took a fresh 57-file current-green backup;
source was already `74985d08`, so no fast-forward is claimed. Its actual private
review passed the exact 63 targets, all 55 ordinary equalities and eight approved
secret equalities, preserving live config/state and the absent secret parent.
Four focused continuation tests and independent review passed. Its controller
retains the accepted Mac transport-failure restoration behavior.

Automatic approval review then rejected both concrete Lab and WSL secret-apply
commands before process creation. It recognized the recent single-file
normalization approvals but did not recognize earlier D11/scope authority as
covering these deployments. Exact additional deployment confirmations were
requested separately. Neither command was retried or rerouted; both hosts keep
maintenance on and enrollment false while those confirmations are pending.

### Canceled password-manager provisioning and cluster consumers

The user first requested Bitwarden installations, then canceled them and requested
removal after selecting Apple Passwords. These actual outcomes are separate from
fixtures, custody and takeover:

| Host | Bitwarden outcome |
| --- | --- |
| mac | Task-installed Desktop removed; app and cask receipt absent. Homebrew unexpectedly auto-removed preexisting llvm@22 22.1.8; that exact version was restored from a verified official bottle, with a successful clang probe and no other formula-version changes. Prior keg hashes were unavailable, so byte-identical restoration is not claimed |
| lab-ubuntu | Exact verified task-installed CLI removed; destination absent |
| wsl-ubuntu | Exact verified task-installed CLI removed; destination absent |
| marlowe | CLI first moved into the existing micromamba login environment as requested, then both task binary and exact task backup removed; all 32 Conda package records unchanged |
| sherlock | Never installed after its staged ABI failure. Bitwarden Node/toolkit/allocation proposal canceled; no pending authorization for it |
| win | Exact task-installed user-scope Desktop removed. Installer data-deletion behavior was checked first; expected app-data directory was absent before and after, and no user data was purged |

No client was signed in or unlocked and no vault data was read. Current removal
evidence is `/tmp/bitwarden-lab-uninstall-report.md`,
`/tmp/bitwarden-uninstall-unix-report.md` and
`/tmp/bitwarden-win-uninstall-report.md`. Historical installation reports remain
retained separately. Apple Passwords custody needs no Bitwarden client.

Sherlock's existing coding-agent-kit 0.6 needs a separate reviewed upgrade to
channel 0.7 before enabling/applying its selected secret targets. Official v0.7.0 consumer/installer source was
reviewed without reading tokens. The installer builds no environment, but it
does not check exported-release local edits, prunes older releases and has no
transactional rollback after activation; exact release/link preservation must
precede the canonical foreground `sync-payloads kit` operation. The committed
Sherlock overlay requires an appropriate allocation. The user approved the
separate local pinned sherlock-kit v0.6.0 dependency, which was installed in its
own controller project; commit 09a37281 and local/remote doctor passed. The new
project's status is empty, not proof that the user has no unrelated jobs. A later
supported broader query through the same approved pinned executable found one
running current-user allocation belonging to another project. Before any reuse,
the exact-ID query showed that it had independently ended. Spare resources and
membership were never established, and no helper entered, modified or signaled
that workload. No investigation of the unrelated job's failure was performed.
The user also
explicitly authorized submitting a new job; an existing job ID is
optional and no further submission approval is pending. Current numbered site
Rule 10 requires at least ten minutes of useful work per job. No qualifying
bundle or suitable existing allocation is established, so no job, remote
environment build or kit upgrade occurred. No sleep/redundant checks may fill
that gap. This is distinct from the canceled Bitwarden proposal.
Review and concrete proposal: `/tmp/chezmoi-sherlock-kit-upgrade-review.md` and
`/tmp/chezmoi-sherlock-kit-provisioning-proposal.md`. No tiny or padded job may
be submitted merely to bypass the site's useful-work batching rule.
Actual controller and rule evidence:
`/tmp/chezmoi-sherlock-kit-provisioning-result.md`. Marlowe's separate bounded
existing-login repair proposal is `/tmp/chezmoi-marlowe-runtime-repair-plan.md`;
it required preserving the 32 package records and an allocation plus a reviewed
solver plan, not environment recreation. No package transaction had been applied
at that initial proposal checkpoint.
The subsequent direct-prefix check confirmed Python and Node packages/binaries
absent from that exact login prefix, with all 32 records unchanged. The initial
missing-Slurm result came from a sanitized subprocess that dropped the site's
observed module paths; restoring only those paths resolved it. Actual Slurm
queries and `sbatch --test-only` accepted a CPU-only request under the observed
default basic-project account. A reviewed bounded allocation-only solver plan
uses one CPU, 2 GiB and a ten-minute cap, exact existing-package pins, an isolated
cache and explicit public conda-forge configuration. That preparation alone did
not establish a successful solve or package installation.
The first actual allocation stopped before the solver because a binary identity
check compared client-local NFS device numbers across nodes. A separate
diagnostic established that this was the sole differing field: all 32 package
records, the other eight stat fields and exact binary bytes matched. The corrected
binding preserves full stat checks within each node and exact bytes across nodes.
The subsequent solver completed successfully in 15 seconds: 27 additions,
zero removals and no replacement of an existing package name, selecting Python
3.14.4 and Node.js 26.0.0 under the declared lower bounds. All existing records,
history, runtime paths and parent metadata remained unchanged. No installation
had occurred at that checkpoint. Native micromamba integrity flags alone do not
refuse preexisting destination files, so a separately reviewed preparation job
downloaded and SHA256-verified the exact 27 archives, then used native extraction
in private staging. Job 552957 completed 0:0 in 27 seconds with one CPU, 2 GiB
and no GPU. All 55 native commands succeeded with empty stderr. Its inventory
covered 7,355 package and generated destinations: zero existing collisions,
zero package link/unlink scripts and zero native trash/message/lock objects.
All original 32 package records, history, watched runtime paths and parent
identities/ACLs remained unchanged. This was extraction and inspection only;
installation had not yet occurred at that preparation checkpoint. The exact installation
proposal is retained in `/tmp/chezmoi-marlowe-runtime-install-proposal.md`.

The subsequent exact native installation ran once in allocation job 553033.
It used only the 27 verified local archives, an independent private cache,
`--always-copy`, `--no-pyc`, no solver and no package scripts. Native installation
returned zero with empty stderr, creating 59 package records while preserving
the original 32. The old history bytes were retained with an append. The job
then failed its regular-file permission postcheck before Python/Node probes;
that failure is not authority to repeat the successful installation.

Read-only diagnosis found 3,342 new regular files with real group-write access:
3,132 at 0664 and 210 at 0775. Seventeen upstream archives carry those same
permissions; native copying preserved them despite umask 077. The existing
prefix is 0755 and HOME 0750, so group traversal exists; this is not the earlier
owner-only NFS mask projection. All 759 new directories are 0700, all 163
intrinsic links match, and all 406 suppressed pyc paths are absent. Original
records, existing parents and outside source/config/trust/secret metadata remain
unchanged, apart from the already-proven client-local device-number difference.
No native trash/message/lock object remained. An exact new-file-only repair was
prepared to remove write bits from those 3,342 bound files while retaining
their bytes and executable bits, without directory or old-file chmod, reinstall
or manual rollback.

The first repair staging check stopped before directory creation or job submission
because the literal filesystem root `/` has different inodes on login and compute
nodes. Read-only diagnosis confirmed that all NFS ancestor inodes, modes, owners
and ACLs matched; only their already-proven client-local device numbers differed.
A narrow correction accepts only the exact root-owned 0755, empty-ACL shape for
the initial cross-node `/` check, then binds full node-local identity. NFS inode
and full per-file checks remain unchanged. Eleven isolated tests and independent
review passed before the corrected staging was released.

Actual repair job 553043 completed 0:0 in 26 seconds: 3,132 files changed from
0664 to 0644 and 210 from 0775 to 0755. No directory changed. All 7,355 target
states/content hashes, 59 records, original 32 records, post-install history,
163 links, 406 absent pyc paths and parent/outside bindings passed. Private progress
records preserve every original and resulting file identity. The isolated absolute
login-prefix probes passed Python 3.14.4, tomllib and Node 26.0.0 with empty stderr.
No installer, account or credential call ran in this repair. The actual receipt
and reviewed script hashes were independently checked before runtime acceptance.
Fresh consumer inspection and secret deployment remained separate gates at that
runtime checkpoint; existing master access does not establish fresh cluster MFA.

### Marlowe secret continuation

Fresh read-only inspection verified the accepted login-prefix runtime, native
Claude executable, kit 0.7 public files and links, absent default kit override,
clean `bf99958` source, 54 unchanged ordinary targets and eight absent secrets.
The adapter retains the full historical binding and adds runtime observations.
An independent review caught a saved-versus-current environment gap; exact kit
and XDG selection equality now precedes runtime inspection. Eleven isolated
methods passed, including native 62-target deployment, NFS/private-parent checks
and refusal/restoration cases. This is distinct from actual host deployment.

The actual host inspection then matched every historical binding. Maintenance
was established and proved to suppress both update paths. All 56 ordinary/config/
state backups were privately read back and verified; no plaintext backups left
the host. A separately reviewed source bridge pins that backup, exact parents,
clean main, canonical public origin and exact green `74985d08`. Synthetic Git
tests exposed URL-specific HTTP settings that survive generic overrides; six
exact scoped resets corrected the three settings for both accepted origin forms.
All four real-Git regression methods and independent review passed. Credential
helper behavior was verified with a synthetic positive control, without reading
actual credentials. The operator claims only those verified transport settings.

Automatic approval review initially refused the bridge before process creation,
stating that it saw only assistant-relayed authority for the remote Git mutation.
The coordinator checked the original user-adopted D11 scope and exact CI gates.
Before any resubmission, the user provided a new direct approval. The identical
frozen command then passed review and executed once: clean main advanced from
`bf99958` to `74985d08`; all 54 ordinary files, native config/state, runtime,
parents and 56 backups remained bound. Maintenance stayed on and all eight secret
targets remained absent at that source-only checkpoint.

The actual private review then backed up and read back 56 files and verified all
62 native target renders: 54 ordinary files plus the eight approved credentials.
The one-shot transport controller passed five isolated failure-path methods and
independent review. The coordinator executed it once after explicit sole-host
handoff. Actual deployment passed: the new parent is 0700, all eight single-link
files are 0600, both nonforced applies converged and the full file diff was empty.
The offline consumer read all eight, and the real updater performed one successful
fast-forward-only pull followed by a skipped second call. All 54 ordinary files,
runtime, identities and existing parents remained bound. Only the reviewed local
config, native state and secrets changed. Maintenance is off and enrollment true.

The retained authenticated SSH master passed the post-apply access check with
both private stderr logs empty. The separate acceptance controller passed three
isolated transport tests and independent review. Actual acceptance then rechecked
the persisted post-apply binding without recapturing a baseline or repeating
apply. Its native receipt binds apply receipt
`79517fc565013f4cf849e76284e9e594a9c0aca8be4bd899395da1c08e0fc8c3`;
the accepted receipt digest is
`4f7f693622e0b112e1de15c45b102007d698a2aae8b61242e77b636fd897b023`.
This is existing-master access only: fresh MFA and credential-server
authentication were not tested. Native Codex remains a separate absent prerequisite.

## Remaining Stage 4 gates and Stage 5 handoff

The user authorized commit/publication and main landing. Corrected `bf99958`
passed exact hosted CI/e2e and ordinary acceptance on all five Unix hosts.
It is the immutable
supported Stow recovery bridge and first accepted ordinary-native release;
see support-boundary.md. Custody and all five host identities are established;
all six recipient checks passed. Encrypted source `74985d08` passed its exact
hosted gates and is published. Mac is the accepted secret canary with actual
fresh-access evidence; Marlowe subsequently accepted deployment under existing
authenticated access. Lab and WSL have each completed their separately approved
single-file normalization; continue their fresh guarded plans without repeating
force or reusing failed capsules. Continue independent
unblocked work under D11, recording actual
target/app/access outcomes and exceptions without treating fixtures as rollout.

[Stage 5](stage-5-ecosystem.md) and its [fresh-session prompt](start-stage-5.md)
contain the next caller map. They are a handoff only. No Stage 5 cleanup or
Stage 6 source/runtime retirement is included in this candidate.
