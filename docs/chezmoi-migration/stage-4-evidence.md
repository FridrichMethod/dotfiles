# Stage 4 candidate and actual-host evidence

Date: 2026-11-02. This is a candidate record, not a claim that Stage 4 rollout or
secret enrollment is complete. Read [status.md](status.md) and
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
required hosted gates. No completed live takeover or credential enrollment is
claimed. Unrelated work remains preserved, including the separately handed-off
tmux fix and Windows Terminal preference.

The original main checkout's 13 untracked planning documents were verified
unchanged, moved intact to the private local
`$HOME/.local/state/dotfiles-stage4-preserved-planning-20261102/original-docs`,
and reverified against their retained manifest before fast-forward. They were
not reset, stashed or overwritten. The later two-file tmux handoff was imported
byte-for-byte from `/tmp/dotfiles-tmux-corners.patch`; its original main edits
remain preserved pending coordinated landing. No native apply may undo that fix.

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
environment prefixes. Their combined full pre-commit passed. They and the
subsequent changes below still need their own exact hosted gates before rollout.

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
consistency pass is validated separately. Hosted gates remain pending for the
new exact candidate.

## Actual fleet outcomes, separate from fixtures

| Host | Actual observation | Takeover outcome / blocker |
| --- | --- | --- |
| lab-ubuntu | Main reached green `9c1a31f`; original planning docs preserved; subsequent two-file tmux handoff retained. Verified native binary installed; persistent maintenance, 59-target private snapshots and explicit native init completed. Both actual AI dry runs and private policy/local-state comparisons passed | Canary prepared, not migrated: no managed target apply or native ownership marker. Paused before writes for the directory permission correction and refreshed snapshot of the newer tmux edit |
| mac | Last checkout preflight: clean main `1a9d30b`, non-OneDrive; 56 targets, 53 exact links and three regular files. Root-owned `.config` is writable/searchable by the user's group and must retain its permissions | Not migrated; await canary and corrected candidate gates; headless checks are not GUI checks |
| wsl-ubuntu | Last checkout preflight: clean main `1a9d30b`; 55 targets, 52 exact links and three regular files; no foreign links or linked parents | Not migrated; await canary and corrected candidate gates; preserve existing shared-parent modes |
| win | Last checkout preflight: main `7edf12fb5b61b6e6d96703bc67f4521e69501d0c`; 26 targets, 23 exact links and three regular files. Both NoProfile profile paths match. The appended Terminal profile is preserved with equivalent environment-variable prefixes | Not migrated; user deferred the required ordinary-user execution/ACL check. SSH is administrative; bounded automatic de-elevation did not complete the target audit. No task, marker, target or production ACL change |
| sherlock | Existing master; five current site/topic files reread; last checkout preflight clean main `6db67edf7b53e5436a2657219e63763393e6eb21`. Actual glibc 2.17 rejects the generic binary; verified official static musl v2.74 probe passed privately | Not migrated; no production native install/apply. Artifact correction needs its exact candidate gates. Kit 0.6 requires reviewed channel-0.7 upgrade before enrollment; master access does not prove fresh MFA access |
| marlowe | Existing master; current official operating policy checked; last checkout preflight clean main `2c177fcb6b6e1a3482ed71e1ef659a43973d9609`. Kit 0.7 launchers present; native Codex absent from inspected PATH | Not migrated; await canary and candidate gates. Native Codex installation/auth is separate from Claude credential enrollment |

Only the lab preparation above created native home config/state, maintenance
and exact private backups. No managed target apply or real encrypted enrollment
has occurred. D11 and explicit publication authority remain in force;
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
device. The personal item is `dotfiles age recovery`; actual private deposit and
independent retrieval remain pending. R alone recovers all eight files; host
private identities stay local and only public recipients are exported. A same-disk
`.secrets` directory is not independent recovery custody. No production identity
has been generated or credential file enrolled. Codex mutable auth remains
application-owned; each host needs its own login state.

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

## Remaining Stage 4 gates and Stage 5 handoff

The user authorized commit/publication and main landing. Bridge `9c1a31f` passed
all required hosted checks and reached main. Later actual-host corrections need
their own exact-green three-platform CI/bootstrap e2e before canary apply. Assign
immutable last-Stow/first-native revisions only when they exist. Complete custody
and secure first-identity handoff before enrollment. Then execute one recoverable
canary and other unblocked homes under D11, recording actual target/app/access
outcomes and exceptions.

[Stage 5](stage-5-ecosystem.md) and its [fresh-session prompt](start-stage-5.md)
contain the next caller map. They are a handoff only. No Stage 5 cleanup or
Stage 6 source/runtime retirement is included in this candidate.
