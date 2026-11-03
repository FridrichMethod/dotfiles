# Migration state and next-session record

## Current state

- Planning baseline: `738f619` on 2026-11-01. It includes local tmux changes after
  the initial feasibility assessment at `2c177fc`.
- Current consolidation baseline: local `main` and `origin/main` at `1a9d30b`.
  The other review session finished its fixes and integrated tmux before this
  plan merge; do not restart that completed review work.
- Implemented migration candidates: Stage 1 isolated foundation, Stage 2 ordinary
  source, Stage 3 native AI configuration and Stage 4 compatibility/takeover.
  Stage 4 local validation passed; publication, secret custody and rollout remain
  separate gates; see [Stage 4 evidence](stage-4-evidence.md).
- Real homes migrated by this planning work: none.
- Initial connection-only preflight: four SSH successes, local lab-ubuntu access, and
  SSH auth rejection on win/lab-ubuntu; see [fleet rollout](fleet-rollout.md).
- Follow-up: Mac's own SSH client also reaches win and lab-ubuntu. All six now
  have an observed operation route. The user then added the lab public key on
  Windows; fresh direct lab-to-win SSH was independently verified. Both public
  keys and the existing ACL remain intact. Only the one new authorization-file
  backup was removed at the user's request. No dotfiles migration was performed.
- Real secret values inspected/enrolled by this planning work: none; only local
  names/types/modes were checked. See [secrets and SSH](secrets-and-ssh.md).
- Native chezmoi executables tested: official v2.74.0 Linux amd64, Darwin arm64
  and Windows amd64, SHA256 verified. Stage 3's final candidate has 64 native
  test methods; exact passes/skips and full-run evidence appear below. Remote work
  used private temporary fixtures only; no real HOME apply, token inspection,
  secret enrollment or remote migration occurred.
- Active work: finish [Stage 4](stage-4-takeover.md) and its recorded gates.
  The [Stage 5 prompt](start-stage-5.md) is a handoff, not authorization to start it.
- The new [inventory](inventory.md) derives 95 tracked package paths at
  `1a9d30b`, including all five tmux files and assets. The old 91 count is stale.
- During the earlier documentation validation, another session advanced `origin/main` to
  `1a9d30b` while this checkout stayed at `738f619`. The observed additional
  commits include payload stamp retry and Windows legacy-directory documentation
  fixes (`42b2e71`, `e617ff1`). No fetch/pull/merge was performed for this handoff.
  That session subsequently brought this checkout to `1a9d30b`. Reconcile the
  actual intended base again before creating implementation worktrees; include
  `scripts/payload-update.ps1`, `tests/test_payload_download.py` and
  `docs/payloads.md` in the inventory of current behavior.

Initial planning-package validation at `738f619`: `pre-commit run --all-files`
passed, explicit `pre-commit run --files` checks covered the new untracked
handoff files, and ASCII/local-link validation passed. Two read-only reviewers
checked native semantics and rollout/worktree sequencing. This is documentation
validation, not evidence that a migration stage or native platform rollout passed.
Consolidation validation at `1a9d30b`: full pre-commit passed again; explicit
new-file pre-commit checks passed; all 11 Markdown files passed ASCII validation
and all 41 local links/anchors resolved. A separate read-only reviewer found no
material inconsistency in the merged cutoff, stage allocation or recovery plan.
The 2026-11-02 fleet/secrets extension also passed full pre-commit, explicit
new-file checks, and validation of 13 ASCII Markdown files with 59 local
links/anchors. Separate read-only reviewers checked actual rollout sequencing and
secret ownership. Connection results are recorded separately from these checks;
no native migration, encryption enrollment or application-auth test has run.
The package is left uncommitted; read/carry these files before creating worktrees.

| Stage | Code/check status | Real-host status | Completion evidence |
| --- | --- | --- | --- |
| 1 | Implemented; Linux/macOS/Windows probes and independent review | No real HOME takeover or fleet migration | 23 probes; Windows one Unix-TZ skip; inventory and CI integration |
| 2 | Ordinary source and explicit host implemented; final validation record below | Isolated fixtures only; no takeover | Exact seven-role sets/bytes/modes and native platform checks |
| 3 | Native Claude/Codex candidate implemented; validation record below | Isolated fixtures only; no takeover/enrollment | Exact policy/ownership, safe input refusal and complete native source |
| 4 | Compatibility candidate implemented; Linux full/pre-commit, Mac native, Windows full and independent review passed | No native takeover; publication/custody and actual host blockers remain | [Evidence](stage-4-evidence.md), [operator procedure](takeover.md) |
| 5 | Not started | Depends on integration scope | None |
| 6 | Not started | Support-cutoff deliverables not implemented | None |

## Decisions and open choices

Stage 4 complete reviewable aggregate: `/tmp/dotfiles-chezmoi-stage4-integration`
on `chezmoi-stage4-integration`, uncommitted on `1a9d30b`. Recovery backup is
`/tmp/chezmoi-stage4-candidate.patch` (entire Stages 1-4); the smaller
`/tmp/chezmoi-stage4-review.patch` contains Stage 4 relative to the staged carried
input. Recompare with current status/diff before use and preserve subsequent work.
The original Stage 3 coordinator still matches its audited backup. Real native
takeover/enrollment and hosted CI/e2e remain unperformed. Bitwarden installation
outcomes and recovery-custody status are separate in [the evidence](stage-4-evidence.md).
The [Stage 5 prompt](start-stage-5.md) is prepared, but Stage 5 has not started.

| ID | Decision | State / owner |
| --- | --- | --- |
| D1 | Native regular-file deployment and native modify templates; no permanent Python merge backend | Stage 3 implemented; local TOML temporals deliberately refused before affected-target writes |
| D2 | Remove TOMLKit, `.venv-sync` and `setup-sync.*` from the final supported path | Explicit user requirement; Stage 3 removes new-path dependency, Stage 6 retires legacy callers |
| D3 | Canonical TOML/JSON formatting and upstream parser/writer behavior replace legacy formatting, inode and writer guarantees | Plan direction necessary for native reuse; characterize in Stage 1 and document in Stage 3 |
| D4 | Preserve ownership, local state, policy values, malformed-input failure and explicit host selection | Required across stages |
| D5 | Private native AI configs; readonly/stricter existing targets reviewed during takeover | Verify attributes/modes on selected release; Windows ACL evidence separate |
| D6 | Keep login automatic dotfiles updates through only a thin adapter calling chezmoi | Explicit user choice during planning: preserve login updates; do not ask again |
| D7 | Prefer explicit payload delegation and remove consumer scheduling | Proposed Stage 5 simplification; distinguish from D6, which concerns dotfiles updates |
| D8 | Select chezmoi v2.74.0 as tested native floor | Official Linux/Mac/Windows binaries verified/exercised; CI pins artifacts; Stage 2 declares candidate-source minimum |
| D9 | Stop automatic historical-layout repair and obsolete-tool support; require manual upgrades outside the declared boundary instead of waiting for all hosts | Explicit user direction confirmed with the originating review session; incorporated in support-boundary.md |
| D10 | Select concrete tested minimum versions before removing old-tool branches; preserve supported OSes and current safety semantics | Stage 1 inventory, coherent component changes through Stage 5 |
| D11 | Agents execute migration, tests and precise legacy retirement on the six hosts in Stages 4/6; do not defer reachable-host work to a later manual user task | Explicit user authorization; persists across sessions; concrete auth/privilege/site blockers remain |
| D12 | Include allowlisted secrets and private SSH information through native encryption/vault integration; preserve app-written auth state | User-requested scope; Stage 1 classifies consumers and tests; Stage 4 enrolls real values |
| D13 | Builtin age, separate native host identities, explicit per-file recipient scopes | Synthetic backend/scope proved; actual allowlists/trust groups and secure identity/recovery access remain private Stage 4 enrollment choices |

D6 is resolved: the user selected keeping login automatic updates with a thin
chezmoi adapter. Stage 4 must implement that direction, with noninteractive
conflict/error handling and fast-forward Git behavior. Do not replace it with
manual-only updates or ask for the same preference again. D7 is a different
decision about upstream payload installation/update scheduling; resolve it with
a concrete proposal in Stage 5 without blocking Stage 1-4 work. D9 does not change
D6 or settle D7. The old standalone compatibility-removal prompt is superseded;
its remaining work is assigned within these stages.

D11 supersedes earlier blanket wording that all real-host work needs a new
authorization. Execute the authorized rollout after the relevant stage checks;
ask only about concrete blockers outside its scope. D12 supersedes excluding all
secret-management design, while plaintext credentials and private keys remain
forbidden in source/logs. OAuth refresh state is not a static portable baseline.

## Stage completion template

Append one completed record per stage. Keep the table above consistent with it.

```text
Stage:
Date:
Starting revision and pre-existing changes:
Resulting revision(s), or uncommitted paths/patch location:
Integration branch/worktree and worker branches retained:
Chezmoi version, artifact source and verification evidence:
Implemented behavior:
Deliberately changed legacy behavior:
Remaining legacy readers/writers and why they remain:
Focused checks: command, result, skips:
Aggregate checks: command, result, skips:
Native Linux/macOS/Windows evidence (do not infer from mocked tests):
CI publication/landing state, if authorized:
Real-home operations performed under D11, per-host results and blockers:
Secret backend/recipient decision and synthetic tests (never secret values):
Known limits/blockers:
Next-stage document updated and concrete starting task:
Farther-stage assumptions changed:
Suggested prompt for the next session:
```

## Initial Stage 1 implementation record (2026-11-02)

This initial Linux-only record predates the native platform validation below.
Its code and local checks passed; calling three-platform acceptance complete was
premature. The follow-up supersedes its platform/remote-execution limits. Native
Mac/Windows tests are required and were not waived by the user.

Starting revision: `1a9d30b837b4425c8c5964bf1e0704290178d41f` on `main`.
Only pre-existing changes were the untracked `docs/chezmoi-migration/` package.
It was copied intentionally into the coordinator worktree; the original
checkout/package was not overwritten, stashed or discarded. No pre-existing
worktrees existed. No commit, push, PR, deployment or remote-host command was
performed in this initial implementation pass.

The result is an uncommitted scoped patch on branch `chezmoi-stage1-integration`
at `/tmp/dotfiles-chezmoi-stage1-integration`, still based on the starting revision.
New files have intent-to-add entries solely so all-files hooks inspect them.
The complete recoverable patch is `/tmp/chezmoi-stage1.patch` (generated after
final checks, including carried handoff files); the retained integration
worktree is the authoritative artifact. Do not recreate it from bare HEAD.
Worker branches/worktrees retained for audit are `chezmoi-stage1-foundation`,
`chezmoi-stage1-native`, `chezmoi-stage1-inventory` under matching
`/tmp/dotfiles-chezmoi-stage1-*` directories. Each worker edited exclusive paths;
the coordinator copied only frozen owned files sequentially. Independent review
was read-only against the aggregate integration tree.

Implemented files and behavior:

- `tests/chezmoi_support.py`, `test_chezmoi_foundation.py` and two tiny fixtures:
  native regular/private file apply, second-apply convergence, explicit isolated
  paths, poisoned inherited state, default closed stdin, dry run, drift refusal,
  and the distinction between content import and exact owned-link takeover.
- `tests/test_chezmoi_native_config.py` and artificial native modify templates:
  JSON object validation and right-biased recursive merge with authoritative
  empty arrays/false/null; typed TOML paths, parse/ancestor failures, convergence,
  numeric/duplicate boundaries and UTC/LA/Tokyo temporal characterization.
- `tests/test_chezmoi_secrets.py`: disposable builtin-age identities, encrypt/
  decrypt/private apply, source/report canaries, missing identity/bad ciphertext/
  unavailable backend preservation, per-file recipient scope and optional seed
  refresh/deletion/state-loss behavior. No real credential values were read.
- `tests/chezmoi.sh` and `.ps1`, both runners, prerequisite/hook selection tests,
  a scoped native pre-commit hook and exact artificial-template parser exclusions.
  All three existing CI jobs explicitly provision the pinned, verified test
  artifact through `.github/scripts/install-test-chezmoi.py`. Downloads occur
  outside behavioral tests; Linux keeps its single pre-commit behavior pass.
- `inventory.md`: all 95 tracked package files, exact seven-role applicability,
  six executable modes, four materialization exceptions, binary/empty assets,
  all five tmux files, source consumers/tests, compatibility units, tool floors,
  secret-writer classification and later six-host obligations.
- `README.md`, `AGENTS.md`, testing/coverage docs and migration handoff were
  updated. The active guide remains below 28,000 bytes. Stage 2 now has concrete
  work packages, target totals, bridge/host interfaces and verification tasks.

Selected runtime: chezmoi v2.74.0, commit
`fcc38cf6fdb3a79ae4afae9ef6ad241890db6cde`, build `2026-11-01T13:53:24Z`.
The official Linux amd64 artifact SHA256 and reviewed macOS/Windows CI artifact
digests are in [sources.md](sources.md). Manual verification and the actual CI
provisioner both verified the Linux digest before execution. No signature or
attestation verification is claimed. Older chezmoi releases were not tested.

Validation commands use the already provisioned legacy interpreter via
`DOTFILES_SYNC_PYTHON=<original-checkout>/.venv-sync/bin/python` and the
verified test binary via
`DOTFILES_TEST_CHEZMOI=/tmp/dotfiles-chezmoi-stage1-runtime/chezmoi` as appropriate:

| Check | Actual result / limits |
| --- | --- |
| `tests/chezmoi.sh` (stdlib `python3 -I -B -m unittest discover -s tests -p 'test_chezmoi*.py' -v`) | 22 tests PASS, no Linux skips; final integration run 1.196s |
| Same 22-test suite with `TZ=Asia/Tokyo` | PASS, no skips, 1.210s after independent review correction |
| Native worker's 12 transform/secret tests with default, LA and Tokyo parent TZ | PASS in each environment; temporal defect is explicitly characterized |
| Fixture test-first evidence | Missing helper produced intended import failure; inherited-stdin regression failed before DEVNULL fix, then passed |
| Inventory's embedded exact-index checker | PASS: 95 rows, seven host sets, four exceptions, six executable modes, five tmux files |
| `tests/test-entrypoints.sh` | PASS; two optional pwsh subtests skip because pwsh is absent |
| `tests/run.sh --ci` | PASS (`test-suite=PASS`), including actual Stow integration; log `/tmp/chezmoi-stage1-full-suite.log` |
| `pre-commit run --all-files` | PASS, all hooks; first pass applied shfmt, then clean rerun passed; log `/tmp/chezmoi-stage1-pre-commit.log` |
| CI provisioner run with temporary RUNNER_TEMP/GITHUB_ENV | PASS: official Linux artifact downloaded, SHA256 verified, binary extracted only into /tmp |
| ASCII/local-link validation and `git diff --check` | PASS: 15 ASCII Markdown files, 72 local links/anchors; AGENTS.md 26,468 bytes; no whitespace errors |
| Worker inventory pre-commit attempt | Failed only on missing legacy sync runtime in its fresh worktree; coordinator's aggregate run reuses the existing runtime without creating an environment |

Actual platform evidence is local Linux x86_64 with Python 3.15.2, Bash 5.2.21,
zsh 5.9, Stow 2.4.1 and tmux 3.4. Inventory-worker tmux tests passed 13/13 and
shell-profile passed; the full coordinator suite exercises them again.
At the end of this initial pass, no native macOS/Windows execution had occurred
and no new CI run was published.
CI wiring and reviewed artifact hashes are not native platform evidence.
Windows inherited ACLs, actual profile/app discovery and Go TZ behavior remain
unverified. Local full-suite skips include absent pwsh, installed-kit cases
without `DOTFILES_TEST_KIT_HOME`, real fzf-tab without `FZF_TAB_TEST_DIR`, and the
e2e harness's real-checkout refusal under /tmp. Real bootstrap e2e/network and
credential/daemon tests were not run. Native 22-test Linux probes had no skips.

Independent review found an environment-dependent positive TOML date test:
Tokyo moved a local date backward. The fix removes local temporals from the
general positive fixture and extends explicit Unix characterization to Tokyo.
It also suppresses a synthetic plaintext value in a possible failed encryption
assertion. Scoped review confirmed meaningful backend failures, isolated state,
non-forced drift behavior, narrow hooks and CI-only provisioning. Final aggregate
review passed spec compliance and code quality with no remaining important
findings. Its only pending condition was final checks, now passed. A local
review record is retained at `/tmp/chezmoi-stage1-review.md`.

Decisions and unresolved conditions:

- Native deployment/transforms are viable without child Python/external jq or
  TOMLKit. Stage 1 changes no production/default installer, login writer or
  permission-policy value. Legacy Stow, TOMLKit, `.venv-sync`, `setup-sync.*` and
  custom backend remain for their existing callers/tests until staged retirement.
- TOML local date/time/datetime preservation is an unresolved Stage 3 condition:
  v2.74.0/BurntSushi v1.6.0 can shift wall values outside UTC. UTC mitigates the
  tested Unix case; it is not a cross-platform fix. Stage 3 must obtain a verified
  native correction or fail safely before writing affected input. No custom
  parser or silent data-loss acceptance was added.
- Native duplicate/numeric and canonical formatting behavior replace legacy
  details as explicitly recorded in sources. Non-object/invalid inputs and
  ancestor collisions still fail without replacing the affected target. Conflict
  exit 1 may have no diagnostic; the future thin login adapter must handle it.
- `add --follow` imports, but does not take over a symlink. Stage 4 must snapshot
  and prove ownership before any exact-target replacement. Routine apply/update
  must not use force. No whole-home transaction is promised.
- Builtin age is selected; separate native host identities and explicit per-file
  recipients are feasible. Actual secret allowlists, host trust groups, first-key
  delivery/recovery custody and Windows ACL evidence remain private Stage 4
  enrollment conditions. App-written auth is excluded from recurring targets;
  `create_` can resurrect a seed after native state loss and is not a logout-safe
  recurring source. No real host identity or secret was enrolled/distributed.
- Existing tmux/Bash/Python/Stow/PowerShell floors are retained; tmux 3.4 and a
  Claude-client floor remain candidates pending coherent provisioning/native
  evidence. Official Claude docs reverse the old plugin-ID rename prose;
  preserve both current values until the supported-client decision. Installed
  kit v0.6 consumer evidence requires channel-0.7 recheck before secret enrollment.
- D6 thin login automatic updates, D9 declared cutoff without all-host waiting,
  and D11 authorized six-host execution in Stages 4/6 remain unchanged. This
  initial pass contacted no host and retired no old layout or live environment.

Next concrete task: run Stage 2's linked-worktree literal-include/host-selection
contract tests, then map ordinary source from the 95-row inventory. The full
self-contained next-session prompt is [start-stage-2.md](start-stage-2.md).
Stage 3 now includes exact native syntax and the temporal preservation condition;
Stage 4 includes import/takeover and silent-conflict consequences; secrets plans
include the verified backend/scoping and bootstrap/refresh boundaries.
Stop here: Stage 2 production source has not been created.

## Stage 1 native platform validation (2026-11-02)

The user's follow-up prompted completion of required native platform evidence.
Isolated remote tests are permitted; they are not real HOME takeover or remote
migration. One worker per host used existing SSH access, a fresh private task
directory, synthetic fixtures, minimal parent environment and explicit temporary
source/destination/config/cache/state/HOME. No live settings, auth, login hooks,
payloads, tasks, checkout or user ACLs changed. No package or environment was
installed; only verified temporary binaries and existing Python were used.

| Platform | Actual environment | Final same-source native entrypoint | Evidence |
| --- | --- | --- | --- |
| Linux x86_64 | Python 3.15.2, chezmoi v2.74.0 | 23 PASS; also PASS under umask 077 | Coordinator and independent reviewer |
| macOS arm64 | macOS 27.2 build 26B123, Bash 3.2.57, Python 3.15.2, chezmoi v2.74.0 | `/bin/bash tests/chezmoi.sh`: 23 PASS, no skips, exit 0, 1.660s, umask 077 | `/tmp/chezmoi-stage1-macos-report.md` |
| Native Windows AMD64 | Windows 11 10.0.26300, PowerShell 7.6.9, Python 3.12.10, chezmoi v2.74.0 | `pwsh -NoProfile -NonInteractive -File tests/chezmoi.ps1`: 23 ran, 22 PASS, one Unix-TZ skip, exit 0, 3.524s | `/tmp/chezmoi-stage1-windows-report.md`, `/tmp/chezmoi-stage1-windows-wrapper-output.txt` |

Mac initially timed out twice; after the user restored reachability, the same
alias worked. No alternate endpoint, key copying or authentication prompt was
used. Its system Python was 3.9.6, so the worker explicitly selected existing
Homebrew Python 3.15.2. The official raw Darwin-arm64 binary SHA256 is
`9d4d7aeecb40b2616af766f88cf6ea45ed2b1fc0a9793df7b075b63847ae47f8`;
local and transferred bytes matched the official manifest. Windows verified its
official zip and transferred binary. Both platforms' final test/fixture hashes
matched integration; the final foundation module hash was
`d9634949404a6b6061b8a9b3942dc30c2ba8c13d24b960929d733c3d06790a67`.

The initial Windows run had 18 passes, three failures and one skip. Two failures
came from current-directory executable lookup; missing-binary tests now enter
their empty temporary directory. The TOML positive input now explicitly writes
LF, avoiding accidental Windows text-mode CRLF expansion. A new 23rd exact-byte
probe records native CRLF multiline parsing and an optional native LF
normalization, preserving explicitly escaped CRLF. TOML permits parser newline
choices; this is not a claimed specification violation. Production policy and
multiline literal-string coverage remain Stage 3 work.

Mac's first 23-probe run passed 22 and errored once: umask 077 made the owned
source private, so native import created `private_dot_owned-config`. The test
now queries native `source-path`, checks source containment and retains content/
type/takeover assertions. Linux reproduced the old error and passed after the
fix; Mac retained umask 077 and passed. Windows then reran identical final files.

The Windows Unix-TZ skip is supplemented by a separate exact-byte native probe:
`TZ=UTC`, `America/Los_Angeles` and `Asia/Tokyo` all caused the same +8-hour local
time/local datetime shift on this host; the local date and offset datetime
survived. UTC process TZ is therefore confirmed insufficient here, strengthening
the Stage 3 temporal-preservation blocker rather than resolving it.

Only synthetic Windows ACLs were inspected. The final validation root had
protected ACLs limited to OWNER RIGHTS, SYSTEM and Administrators; private target
children inherited those roles. This administrative SSH token does not prove
ordinary-user destination ACL safety. The first transfer root had broader
inherited account ACEs and was not the private validation root. No real secret
was present or enrolled; actual destinations still need Stage 3/4 ACL review.

Follow-up `tests/run.sh --ci` and `pre-commit run --all-files` both PASS; logs are
`/tmp/chezmoi-stage1-followup-full-suite.log` and
`/tmp/chezmoi-stage1-followup-pre-commit.log`. Independent spec/quality review
passed after checking both native reports, all transferred test/fixture hashes,
the final umask fix and temporal/ACL limits. Its sole documentation correction
was the raw Mac asset filename, now correctly `chezmoi-darwin-arm64` in sources.
ASCII/local-link validation passed for 15 documents and 73 local links/anchors;
`git diff --check` passed. The final documentation snapshot receives the required
all-files check as well.
No hosted CI, native full legacy suite, GUI/app smoke or real migration was run
on these hosts. This establishes native fixture/entrypoint behavior, not fleet
takeover or general application/ACL acceptance. Stage 2 has not started.

## Stage 2 ordinary source implementation (2026-11-02)

Starting revision: `1a9d30b837b4425c8c5964bf1e0704290178d41f`. The session first
inspected the Stage 1 integration HEAD/status/diff and all five worktrees. Its
38-file uncommitted result was saved as `/tmp/chezmoi-stage2-input.patch` and
explicitly applied to the new Stage 2 integration worktree; every carried file
was byte-compared. The original Stage 1 worktrees and backup remain untouched.
No task commit, push, hosted CI run, live migration or secret read was performed.

The authoritative result is branch `chezmoi-stage2-integration` at
`/tmp/dotfiles-chezmoi-stage2-integration`, still uncommitted on the same HEAD.
The complete recoverable patch, including Stage 1 and this handoff, is
`/tmp/chezmoi-stage2.patch`. New files have intent-to-add entries for all-files
checks. Workers retain independent `chezmoi-stage2-unix`, `chezmoi-stage2-windows`
and `chezmoi-stage2-verification` branches/worktrees under matching `/tmp/`
paths. Only the coordinator writes integration; exact owned paths were copied
sequentially. The frozen interface, target sets and execution ledger are retained
in `/tmp/chezmoi-stage2-{interface.md,expected-targets.json,ledger.md}`.

Implemented behavior:

- `.chezmoiroot=home`, `.chezmoiversion=2.74.0`, mandatory local `[data].host`
  and one internal validation guard. Init explicitly loads that guard; target
  calculation calls it before writes. No environment/OS role inference.
- 67 ordinary source files: 65 literal text bridges and raw WebP/terminfo assets.
  Legacy content remains canonical through Stage 6. All seven exact file sets
  and bytes match inventory: 47/54/53/57/52/52/24. Pet JSON is a text bridge.
- Zero-byte rc files, both ordinary executables, all five tmux files, Windows
  CRLF/mixed newlines, opaque portable.rules and private lab fcitx5 profile.
  Non-exact shared directories preserve synthetic auth, trust and payload state.
- Windows's six common packages and actual metadata-only discovery of both
  native PowerShell CurrentUserAllHosts paths. Both matched fixed Documents
  targets; redirected Documents remains a Stage 4 preflight/mapping obligation.
- Independent inventory/index, exact native target/byte/mode/convergence tests,
  linked-worktree/space-path literal-include proof, host/init/version failures,
  rendered shell/Python/JSON/Lua lint, and encoded-source hook coverage.
- `tests/test_stow_ignores.py` excludes candidate `home/` from legacy package
  layers. Legacy production source, installers, profiles, payload/update hooks,
  permission-policy values and parser runtime behavior are unchanged.

The two AI mutable configs are absent from candidate source and left untouched
as synthetic unmanaged files during apply. The four legacy sync definitions
remain available only to the old path. There are no native scripts, removals,
symlinks, credentials, new merge processes or deployment-time package installs.
GUI edits are native destination drift; no Stow write-through guarantee is
claimed for candidate regular files.

The Linux official artifact digest and extracted executable bytes were rechecked
against Stage 1's selected v2.74.0 release. Mac and Windows binaries were rehashed
before execution. Source/tests were transferred as a 360-file tracked snapshot
with exact SHA256 and Git mode manifests, then scoped test-only corrections were
applied and verified. Later documentation edits do not change the tested native
source. Exact reports and manifest paths are retained under `/tmp/chezmoi-stage2-*`.

| Validation | Actual result / evidence |
| --- | --- |
| Native Linux focused suite | 33 tests PASS; native five compatible roles and separately labeled supplemental seven-role OS-data rendering |
| Source-state tests under umask 077 | Nine PASS; executable assertions respect native umask, private profile remains 0600 |
| Native macOS focused suite | System `/bin/bash tests/chezmoi.sh`, 33 ran, one optional StyLua subtest skip; native common-only/mac roles PASS |
| Native Windows focused suite | `pwsh -NoProfile -NonInteractive -File tests/chezmoi.ps1`, 33 ran, two skips: Unix TZ assertion and optional StyLua; native win PASS |
| Linux complete legacy/native runner | `tests/run.sh --ci` PASS (`test-suite=PASS`); `/tmp/chezmoi-stage2-full-suite.log` |
| Native Windows complete runner | `tests/run.ps1 -CI` PASS, exit 0 and `test-suite=PASS`; `/tmp/chezmoi-stage2-windows-final-full-output.txt` |
| Full pre-commit after fixture corrections | `pre-commit run --all-files` PASS; `/tmp/chezmoi-stage2-complete-pre-commit.log`; final handoff receives the same check again |
| Independent read-only review | Implementation and scoped final evidence review PASS, no actionable findings; `/tmp/chezmoi-stage2-review.md`; nine source tests, rendered lint and corrected tmux 13 independently PASS on Linux |

Native Mac: macOS 27.2 arm64, system Bash 3.2.57, existing Python 3.15.2.
Native Windows: Windows 11 10.0.26300 AMD64, PowerShell 7.6.9, Python 3.12.10.
Each used a fresh private capsule, synthetic HOME/XDG/temp, explicit native paths,
closed stdin and empty native child PATH. Windows capsule ACL inheritance was
protected and limited to OWNER RIGHTS, SYSTEM and Administrators. This is
administrative test-token evidence, not ordinary-user destination ACL approval.

Windows full legacy tests reuse the already provisioned exact tomlkit 0.15.1
interpreter read-only, under the user's explicit permission after automatic
review initially rejected its metadata probe. No parser environment was created.
Existing tests may create disposable no-pip stdlib-only venv fixtures; these have
no parser package and are not a new deployment runtime. Native Mac full legacy
CI prerequisites are absent (standard-path Node and exact parser runtime); no
package/environment was installed or real Mac runtime directory inspected.
Mac native fixtures plus focused shell/overlay/tmux checks are separate evidence.

Mac shell-profile and eight host-overlay cases passed. The extra legacy tmux
suite on native tmux 3.8 passed 12 of 13 methods, with three adversarial-directory
menu subtest failures. Two fixture defects were corrected in tracked tests only:
the isolated PATH now exposes the resolved tmux executable, and the deliberately
unsafe cache gets explicit 0755 despite umask 077. Linux passes all 13 under
both masks. Mac's remaining quoted-directory failure predates Stage 2: unchanged
baseline bytes fail before menu setup through native `new-window -c`. A separate
temporary shell-origin reproduction establishes the correct initial cwd, then
the same three unchanged production menu actions still fall back to fixture
HOME. No assertion was weakened and no production tmux behavior/floor changed.
This is a recorded native legacy limitation, not a green Mac tmux claim or a
source-byte migration regression. Reproduction/report:
`/tmp/chezmoi-stage2-macos-tmux-stronger-reproducer.py` and
`/tmp/chezmoi-stage2-macos-report.md`. Resolve that behavior in separate scope.

Windows Store Python also exposed two old test-fixture assumptions under the
required synthetic HOME: its base executable resolves below fake USERPROFILE,
so a no-pip venv may have no executable. `tests/test_config_sync.py` and
`tests/bootstrap.ps1` now use an existing PATH Python for that disposable stdlib
fixture when needed and require the resulting interpreter. They install no
packages, create no parser environment, and do not weaken or bypass runtime
requirements. Both corrected native focused checks passed before the final full
Windows rerun. A long capsule path also exceeded Windows MAX_PATH; validation
was moved to a shorter private temporary root, with ACLs and hashes rechecked.

The final native Windows runner passed all assigned suites: native chezmoi 33
(two skips above), environment 2, config 66 (seven POSIX skips), AI 8 (six
no-kit skips), manifest 13, Stow inventory 6 (one absent GNU Stow skip), Node,
terminal, update, payload, profiles, installer controls 15, bootstrap 31,
e2e parsing/25 harness cases and native Windows installer. Bootstrap retains
four explicit existing-machine font/PATH limitations. These skips are not
failures or claims of real application/privileged bootstrap execution.
Additional skips are explicit in the full log: seven of 16 payload-download
cases, PowerShell's non-redirectable HOME legacy-link case, the unelevated-run
case under this administrative token, absent oh-my-posh, POSIX-only unreadable
directory behavior, and the e2e no-argument launch that could otherwise reach
real HOME. These checks were not represented by synthetic passes.
Final result JSON: `/tmp/chezmoi-stage2-windows-final-full-result.json`;
report: `/tmp/chezmoi-stage2-windows-report.md`.

Local full-suite optional skips retain their meaning: absent Unix pwsh, optional
installed-kit/fzf-tab checks without explicit inputs, and the e2e real-checkout
refusal check under `/tmp`. No network/bootstrap e2e, real GUI/app smoke, hosted
CI acceptance, real auth enrollment or fleet takeover is claimed.

Stage 3 is refined into exact guard/baseline/ownership interfaces, disjoint native
Claude/Codex templates, whole-source counts and cross-platform preservation
tasks. Its first blocker remains TOML local-temporal safety; Windows TZ=UTC is
not a correction. Stage 4 now explicitly carries profile redirection/ACL
preflight; Stage 6 carries the 65 bridges/two raw-copy retirement obligations.
D6 thin login updates, D9 support cutoff and D11 six-host Stage 4/6 execution
authority remain unchanged. The self-contained next prompt is
[start-stage-3.md](start-stage-3.md). Stop at Stage 2.

## Stage 3 native configuration implementation (2026-11-02)

Starting revision: `1a9d30b837b4425c8c5964bf1e0704290178d41f`. The Stage 2
integration HEAD/status/full diff/worktrees were inspected first. Its complete
118-file diff matched `/tmp/chezmoi-stage2.patch` byte-for-byte (2,856,417 bytes,
SHA256 `32e04411e48ec958ccd13fa2220419c720032028834b1b216f250bbf167a3193`).
The full result was applied to the new integration worktree, and every carried
file's bytes and mode were checked. No subsequent Stage 2 changes were present
at inspection. Original worktrees and patches remain untouched.

Authoritative artifact: branch `chezmoi-stage3-integration` at
`/tmp/dotfiles-chezmoi-stage3-integration`, uncommitted on the same baseline.
Complete recoverable final patch: `/tmp/chezmoi-stage3.patch`. The input backup
is `/tmp/chezmoi-stage3-input.patch`. New files have intent-to-add entries for
all-files hooks. No task commit, push, PR, publication or hosted CI run occurred.
Retained writable worker branches/worktrees are `chezmoi-stage3-claude`,
`chezmoi-stage3-codex` and `chezmoi-stage3-verification`, under matching
`/tmp/dotfiles-chezmoi-stage3-*` paths. Only the coordinator writes integration;
owned patches were checked and applied sequentially. Runtime validation and
review workers made no repository edits. Frozen interfaces, portable hashes and
execution ledger are `/tmp/chezmoi-stage3-{interface.md,portable-sha256.json,ledger.md}`.

The first dependency was native temporal safety. The selected guard checks parsed
`time.Time` location markers recursively and refuses local date/time/datetime
anywhere in either TOML input. Actual Linux, macOS and Windows each passed 18
reject-and-preserve and three supported-offset/convergence probes. Windows raw
UTC/LA/Tokyo tests still shifted local time/datetime by eight hours. This is safe
refusal of valid unsupported input, not corrected temporal serialization.
Only after that evidence and the ownership interface were frozen did the two
transform workers run in parallel.

Implemented behavior:

- Native private Claude settings and Codex config modifies, with no `.tmpl`
  suffix and literal reads of canonical legacy policy. No portable VALUES changed.
- Claude raw builtin `jq "fromjson"` retains numeric tokens through recursive
  merge/output, including huge integers, extreme exponents, fractions and signed
  zero. Authoritative arrays, false/null and local model remain correct. Both
  plugin IDs remain; explanatory rename prose is corrected, with no client floor.
- Parsed JSON U+FFFD is refused in keys/strings to prevent invalid UTF-8/surrogate
  repair. Intentional U+FFFD is also unsupported. Native duplicates use last value.
- Codex's 18 typed owned paths and three retired paths exactly match the current
  legacy constants. Value-free JSON metadata is parity-tested and read literally
  so local template data cannot expand ownership. Unknown portable keys do not
  become policy; live ancestor collisions fail before mutation.
- TOML uses native parse/set/delete/serialize only. Unknown tables/AoT, quoted
  dotted and literal-star keys, int64 and offset timestamps survive. Physical
  CRLF normalizes to LF, with exact multiline basic/literal/continuation tests;
  explicit escaped CRLF remains a value. Comments/layout canonicalize intentionally.
- Complete native target sets are 49/56/55/59/54/54/26, exactly two more per role
  than Stage 2. The 67 ordinary targets retain byte/mode/empty/binary parity;
  four helper definitions stay absent. Synthetic auth, SSH trust, `.secrets`,
  default.rules and payload siblings survive under non-exact shared parents.
- Narrow exact-path parser exclusions for the two production and two artificial
  modify templates. Portable inputs and ownership data retain normal JSON/TOML
  hooks; rendered output is parsed/linted. Legacy-constant edits trigger native
  metadata parity tests.
- No selected production static-secret target, dummy credential, identity or
  refresh-state replay. Existing builtin-age recipient/failure/seed-lifecycle
  probes remain. Real allowlists/trust/bootstrap and consumer review belong to
  Stage 4; no real settings/token reads or enrollment occurred.

Native modifies invoke no external jq, Python, TOMLKit, custom parser/writer or
sync environment. Existing installers, login defaults, legacy paths and helpers
remain unchanged for old callers until takeover/Stage 6. `--migrate-portable` is
absent from the native API; normal apply never writes source. Legacy runtime
reuse for existing tests does not contradict native deployment independence.
No new parser environment was created; existing no-pip stdlib test environments
remain disposable legacy fixtures.

Validation results are recorded below. The platform snapshot
contains 367 reviewed source/synthetic files, with a SHA256/Git-mode manifest at
`/tmp/chezmoi-stage3-runtime-manifest.json`. Archive SHA256 values:
`31440b652929d9b837533fd5b8f7356dc26c6266ae946eca9ff0a52c8566b1f6`
(tar) and `27460a0e16520e8f360a1879533a55c8ac94ace32b4d99e5373e2420cd21fdac`
(zip). Every remote file is verified before/after tests. Later documentation
edits are separate from the frozen native runtime and are checked locally.
The official manifest was fetched anew; retained archives/executable members and
transferred binaries match. This is SHA256 integrity, not signature verification.

| Validation | Actual result / evidence |
| --- | --- |
| Test-first focused worker checks | Claude 11 PASS after absent-target failures; Codex 14 PASS after absent-target/metadata failures; independent integration 6 PASS after 10 absent-feature subtest failures |
| Native Linux complete candidate | 64 tests PASS, no native-suite skips; included in the full runner (19.815s) |
| Native macOS focused entrypoint | 64 ran, exit 0, 34.543s; one optional StyLua rendered-lint subtest skipped; `/tmp/chezmoi-stage3-macos-report.md` |
| Native Windows focused entrypoint | 64 ran, exit 0, 94.766s; historical Unix-only raw-TZ characterization and optional StyLua subtest skipped; new temporal safety tests ran; `/tmp/chezmoi-stage3-windows-report.md` |
| Linux complete legacy/native runner | `tests/run.sh --ci` PASS, `test-suite=PASS`; `/tmp/chezmoi-stage3-full-suite.log` |
| Native Windows complete runner | `tests/run.ps1 -CI` PASS, `test-suite=PASS`; native 64 reran in 93.741s with the same two skips; `/tmp/chezmoi-stage3-windows-5pq4_jzt/stage3-full-result.json` |
| Full all-files pre-commit | PASS, every hook; `/tmp/chezmoi-stage3-pre-commit.log`; final handoff check uses the same command and `/tmp/chezmoi-stage3-final-pre-commit.log` |
| Independent transform and aggregate review | Spec compliance and code quality PASS, no actionable findings; `/tmp/chezmoi-stage3-transform-review.md` and `/tmp/chezmoi-stage3-aggregate-review.md` |
| Source/provenance parity | Frozen portable/backend hashes unchanged; original Stage 2 patch unchanged; native remote 367-file SHA256/Git-mode manifests unchanged |

Native environments: Linux x86_64 Python 3.15.2/Bash 5.2.21/tmux 3.4;
macOS 27.2 arm64 system Bash 3.2.57/Python 3.15.2;
Windows 11 AMD64 PowerShell 7.6.9/Python 3.12.10. Native role coverage is five
Linux roles, common-only/mac on Mac and win on Windows. Seven-role OS-data
rendering is reported separately and never counted as another native OS.

All remote applies use private synthetic capsules, minimal parent environments,
closed stdin and empty native child PATH. Windows's capsule ACL is protected for
OWNER RIGHTS, SYSTEM and Administrators under the administrative test token.
Existing legacy Python/tomlkit 0.15.1 is reused read-only under the prior explicit
Windows authorization; no app/profile/token files were read. Both native runners
verify all 367 transferred source hashes and Git index modes after completion.
Mac evidence is under `/tmp/chezmoi-stage3-macos-evidence/`; Windows evidence is
under `/tmp/chezmoi-stage3-windows-5pq4_jzt/`. Both private remote capsules remain
recoverable; no recursive cleanup was performed.

Local full-run skips include absent Unix pwsh, optional installed-kit inputs,
platform-specific payload-download cases and the e2e real-checkout refusal under
/tmp. Windows full-run skips include POSIX-only checks, absent installed kit/GNU
Stow/oh-my-posh/StyLua, administrative-token unelevated checks, nonredirectable
PowerShell HOME, guarded existing-machine font/PATH checks and the real-HOME e2e
startup guard. Exact cases remain in the full logs. Native Mac full legacy
prerequisites remain unavailable; no runtime/package was installed to satisfy them.


Native checks are isolated fixtures, not actual application startup, GUI reload,
ordinary-user Windows destination ACL approval or fleet takeover. Windows profile
redirection and real ACLs remain Stage 4 preflight tasks. The pre-existing native
Mac tmux 3.8 limit remains 12/13 methods with three adversarial-menu subtest
failures; it was not rerun or silently changed in this AI-transform stage.
The Stage 2 Store-Python/tmux test-only isolation fixes remain intact.
No hosted CI/e2e installation or real auth/secret enrollment is claimed.

Safe limitations are explicit: local TOML temporals and JSON U+FFFD fail before
affected-target writes; native duplicate JSON keys use last value; canonical
formatting loses TOML comments/layout. There is no whole-home transaction,
arbitrary old mode guarantee, live-app concurrency protection or secret-redaction
promise. These require Stage 4 private preflight/quiescence/backup and conflict
handling, not disabling a guard. Native conflict can fail with empty stderr.

Stage 4 now names concrete file owners and tests for home-bound writer guards,
maintenance across new logins, exact process/task quiescence, no-stash fast-forward
native updates, targeted owned-link conversion, post-backup-edit recovery,
provisioning/CI gates, secret allowlists/recipients/bootstrap and canary/six-host
execution. D6 thin login updates, D9 support cutoff without an all-host waiting
gate, and D11 six-host execution authority remain unchanged. The next prompt is
[start-stage-4.md](start-stage-4.md). Stop at Stage 3; no real HOME was taken over.

## Retirement gate

Stage 6 requires the tested native path, explicit supported layout/tool floors,
a recorded last supported Stow revision, and the fixture-verified manual upgrade
and recovery procedure from [support-boundary.md](support-boundary.md). Current
support must not silently change without those deliverables and the required CI.

D9 replaces the former requirement for an attestation from every installed home.
Do not block retirement solely because an offline host is unaccounted for. Record
such hosts as outside the declared support boundary, not migrated. The cutoff
cannot technically prevent their old login hooks pulling a deletion commit;
instructions must explain disabling those hooks/workers before upgrading and
recovering if an unsupported installation skipped the procedure.

D11 separately authorizes the bounded host operations in fleet-rollout.md.
Record actual execution on each host and all exceptions; a manual document alone
does not satisfy reachable-host rollout. Preserve unrelated data and private
inventories. Source may contain only the explicitly selected ciphertext/vault
references from D12, never plaintext credentials. Do not claim completion while
supported code or tests require the sync parser environment, or claim all six
hosts migrated when one remains blocked.
