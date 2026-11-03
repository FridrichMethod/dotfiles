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
at the same HEAD. The inherited patch is staged; Stage 4 is unstaged, with new
files included through intent-to-add. `git diff` reviews Stage 4;
`git diff HEAD` reviews the entire candidate.

Separate Unix, Windows and provisioning worktrees returned recoverable patches,
integrated sequentially. No commit, push, PR, hosted CI run, release cutoff,
live takeover or credential enrollment has occurred. Unrelated work remains
preserved in the original checkout and on Windows.

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

## Actual fleet outcomes, separate from fixtures

| Host | Actual observation | Takeover outcome / blocker |
| --- | --- | --- |
| lab-ubuntu | Local main `1a9d30b`; untracked migration docs retained; existing parser environment reused only for tests | Not migrated; exact published candidate/CI gates pending |
| mac | Fresh BatchMode route; clean main `1a9d30b`; non-OneDrive checkout; native fixtures in private temporary capsule | Not migrated; publication gates pending; headless fixtures are not GUI checks |
| wsl-ubuntu | Fresh BatchMode route; clean main `1a9d30b` | Not migrated; publication gates pending |
| win | Fresh direct SSH; main `7edf12fb5b61b6e6d96703bc67f4521e69501d0c`; modified tracked Terminal settings preserved; both NoProfile CurrentUserAllHosts paths match fixed mappings | Not migrated; publication gates, user-owned Terminal drift and ordinary-user token/ACL validation pending; SSH token is administrative |
| sherlock | Existing master on login node, no allocation; all five current site/topic rules read; clean main `6db67edf7b53e5436a2657219e63763393e6eb21` | Not migrated; publication/site gates pending; master access does not prove fresh MFA access; no native dotfiles provisioning or build/job attempted |
| marlowe | Existing master on login node, no allocation; standard site-guide path absent, current official operating policy checked; clean main `2c177fcb6b6e1a3482ed71e1ef659a43973d9609` | Not migrated; publication/site gates pending; no native dotfiles provisioning attempted |

No real-home maintenance marker, task change, backup, age identity or takeover
was created. D11 permits the eventual canary and subsequent reachable-host work;
it does not substitute for exact-candidate publication authorization or CI.
Do not relabel an offline/site/token blocker as a successful migration.

## Secret choices and custody

Private proposal: `/tmp/chezmoi-stage4-private/secret-proposal.md`, directory 0700,
files 0600. Exact candidates, consumers and ownership evidence stay there.
Current channel-0.7 public consumer code was checked against upstream without
reading credential values. The user approved eight static-for-consumer files,
lab/mac/WSL recipients plus independent recovery, and account-label exposure in
encrypted filenames. Five Codex mutable auth files remain excluded. The user
chose to keep seven SSH snippets in their ordinary mappings.

The user has no existing independent recovery store and requested a cross-platform
password manager with host installation assistance. Bitwarden is the proposed
custody tool. Account setup, secure-item creation and private recovery handoff
remain pending. A same-disk `.secrets` directory can hold a host identity but is
not independent recovery custody. No real key was generated or secret enrolled.
Password-manager installation outcomes are separate from native takeover and
do not satisfy the account/custody gate by themselves.

The user separately requested password-manager installation on all six hosts.
These are actual installation results, not fixture or takeover results:

| Host | Bitwarden outcome |
| --- | --- |
| mac | Desktop 2026.10.3 installed in user Applications; Homebrew receipt, DMG SHA256 and strict code-signature verification passed |
| lab-ubuntu | CLI 2026.10.1 installed at `~/.local/bin/bw`; official archive and executable hashes passed; isolated version probe passed |
| wsl-ubuntu | CLI 2026.10.1 installed at the separate WSL `~/.local/bin/bw`; both hashes and isolated version probe passed |
| marlowe | CLI 2026.10.1 installed at `~/.local/bin/bw`; verified prebuilt binary, isolated staged version probe before install, mode 755 and final hash passed |
| sherlock | Not installed: verified standalone binary failed staged loading on missing GLIBC/C++ runtime symbols; destination remains absent. Site module `devel nodejs/24.13.0` provides Node 24.13.0/npm 11.6.2, satisfying the npm package engines. Dependency installation and application execution are unverified; the allocation-based alternative needs a separately approved project-pinned toolkit. No system-library change, unsupported downgrade or environment build attempted |
| win | Desktop 2026.10.3 installed with pinned user-scope x64 winget command after tests; installer hash verified, expected user-path product/file versions match and Authenticode is Valid for Bitwarden Inc. |

No client was signed in or unlocked; no existing vault data was read. Version
probes used private temporary appdata. Cluster module prerequisites and actual
site rules were checked: the bounded prebuilt copy needed no allocation, but
Sherlock's standalone runtime compatibility check failed. A separate npm route
can use its existing compatible site module, but no installation or build was
run on the login node. Reports are
`/tmp/bitwarden-install-plan.md`, `/tmp/bitwarden-cluster-preflight.md`,
`/tmp/bitwarden-cluster-install-report.md` and
`/tmp/bitwarden-sherlock-runtime-followup.md`; Windows records are
`/tmp/bitwarden-win-install.log` and `/tmp/bitwarden-win-verification.json`.

## Remaining Stage 4 gates and Stage 5 handoff

Local/native validation and independent fix review are complete. The complete
candidate still needs commit/publication authorization. Follow the
exact-green three-platform CI and bootstrap e2e gates before landing. Assign
immutable last-Stow/first-native revisions only when they exist. Complete custody
and secure first-identity handoff before enrollment. Then execute one recoverable
canary and other unblocked homes under D11, recording actual target/app/access
outcomes and exceptions.

[Stage 5](stage-5-ecosystem.md) and its [fresh-session prompt](start-stage-5.md)
contain the next caller map. They are a handoff only. No Stage 5 cleanup or
Stage 6 source/runtime retirement is included in this candidate.
