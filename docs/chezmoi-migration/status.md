# Migration state and next-session record

## Stages 1-4 consolidation checkpoint (2026-11-03)

This section is the current state. The Stage 4 closure below and the
[acceptance table](stage-4-evidence.md#actual-fleet-outcomes-separate-from-fixtures)
record how and at which revision each host was accepted. Stages 5/6 have not
started. The closure `a5d9ad7` passed exact CI 41719265671 on Linux, macOS and
native Windows, plus main-push CI 41721427618. The latest applicable bootstrap
e2e is 41702352195 on `493f395`; later closure commits changed only docs and
`.gitleaks.toml`. The consolidation commit that adds this section lands only
after its own exact CI.

Each host was probed, then advanced through its normal native updater where
needed. Fast-forward only, nonforce, `--exclude=dirs`; no takeover, identity
bootstrap or enrollment step was repeated. "Checkout" means the bound source;
"ordinary config" means native `status --exclude=dirs` and rendered-equality
checks with live-only configuration preserved.

| Host | Checkout | Binding | Ordinary config | Enrollment / consumer | Updater / maintenance | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| lab-ubuntu | `a5d9ad7`, clean; the canonical main checkout, advanced by the coordinator's fast-forwards | Marker, state and safe update contract valid; chezmoi 2.74.0 | Status empty, 67 managed (8 encrypted); both guides and both AI configs equal rendered output | True; eight 0600 files in a 0700 `.secrets`; five excluded auth siblings untouched; `claude-as` on PATH | Maintenance absent; no payload failure record | Ignored retired-submodule leftovers lie outside the native root; four legacy wrapper links in `~/.local/bin` retire in Stage 6 |
| mac | `493f395` -> `a5d9ad7` by the actual updater; login updates had already advanced it from `74985d0` | Valid | Status empty, 64 managed; before/after target and parent manifest identical | True; eight files unchanged | Maintenance absent; no payload failure record | A preexisting merged, clean linked worktree outside the repository was left alone |
| wsl-ubuntu | Already `a5d9ad7` through four unattended login updates | Valid | Status empty, 63 managed; the guide and Codex template deltas were applied by those updates | True | Maintenance absent; no payload failure record | 0 of 11 tmux plugin checkouts; core tmux loads without errors because plugin loading is guarded, so only plugin features are missing |
| win | `15068b9` -> `a5d9ad7` by `scripts/chezmoi-update.ps1` under a one-off ordinary Medium-token task, removed afterwards | Valid; administrator SSH was used only for read-only metadata | Status empty, 26 regular targets; only the two guides changed, in place, with owner and protected DACL unchanged; the other 24 targets and 18 parents unchanged | False by design | Maintenance absent; legacy restow task still Disabled for Stage 6; no payload state yet | Codex desktop sandbox accounts hold preexisting Modify grants on several profile directories; dotfiles did not create them |
| sherlock | `15068b9` -> `a5d9ad7` by the actual updater in the login shell | Valid; static musl chezmoi 2.74.0 | Status empty, 62 managed; only the two guides changed; stat/hash/ACL of the other 60 targets and parents unchanged | True; `claude-as --list` resolves eight files offline; Claude, Codex and Lmod Node run | Maintenance absent; the site profile keeps payload auto-update off; awesome-skills refuses the scratch-backed `~/.cache` link | Existing master only, no fresh MFA; the earlier post-repeat metadata failure did not recur |
| marlowe | `15068b9` -> `a5d9ad7` by the actual updater; login updates had advanced it from `74985d08` | Valid | Status empty, 62 managed; only the two guides changed | True; `claude-as --list` resolves eight files; Claude runs | Maintenance absent; awesome-skills stops on the legacy Codex skills root | A site AppArmor profile denies `node` on login nodes, so Claude's Node hooks fail open there; Codex is absent and unused |

On all six hosts the checkout is updated and the live managed files are applied.
Program checks are availability checks only. No application login, credential
server or GUI authentication was tested. Cluster access reused existing masters.
Private before/after evidence stays on each host under
`~/.local/state/dotfiles-consolidation-20261103/` and in the coordinator's
unpushed `.git/chezmoi-migration-recovery/20261103-consolidation-a5d9ad7/`.
A separate session then landed `130d240`, a shared Codex status line that changes
`~/.codex/config.toml` on every host. The consolidation commits change no
rendered output for these converged files. Login updaters fast-forward to both.
The same day, after `7e344f2` landed, all six hosts reached it with an empty
status: Lab, WSL, Sherlock and Marlowe through the actual updater, Mac and
Windows through ordinary logins. Only `~/.codex/config.toml` gained the status
line; `~/.claude/settings.json` stayed byte-identical.

The same separate session then landed `bcf5c0d`, which shortens that status line
and enables Claude colors; `4abad00` corrected these docs. A later read-only
check found Lab, WSL and Mac at `4abad00` and Sherlock, Marlowe and Windows
still at `7e344f2`, all six with an empty status and both AI configs equal to
rendered output. The last three apply `bcf5c0d` at their next interactive login.

On WSL the first `bcf5c0d` update raced Codex. As observed, a Codex app-server
writes its in-memory copy of `~/.codex/config.toml` back shortly after it starts.
One that the Mac Codex desktop app started on WSL at 16:41:11 read the old file
one second before the login updater wrote the new status line, and wrote the old
one back at 16:41:18. Status then showed `MM` for that file, so every later
nonforce login update would stop there. The reconcile
was a reviewed one-file operation, not a routine force: stop the idle WSL
app-servers, confirm privately that `tui.status_line` was the only differing key,
back up the file, apply only that target with the updater's full argument set,
`--exclude=dirs` and `--force`, then restart the app-servers that had started
before the reconcile. Status became empty, the file equal to its target, mode
0600 and owner unchanged. Later app-server starts rewrote identical bytes. On
Windows, the `7e344f2` update added the line while the Codex desktop app had
been running for days, and nothing reverted it.

### Review outcome

The pass reviewed `1a9d30b..a5d9ad7` for AI transforms, writer guards and the
login binding, permissions, credential consumers and documentation, with an
independent verifier for each material finding. Guards, binding, mode pinning
and secret paths/modes held. Fixed in the consolidation commit:

- The Claude settings modifier always reserialized with sorted keys. Claude
  Code writes in insertion order (plugin install, marketplace add, first
  `/model`), so the next nonforce login update would stop at
  `~/.claude/settings.json` and leave later targets stale. It now mirrors the
  Codex fix: after all validation, keep the original input when the merged result
  is typed-equal. Reproduced with Claude Code 2.1.317 in a temporary home; no
  host had hit it, since every status was empty.
- Stale current-state statements, the README package procedure, legacy labels
  on the AGENTS updater rules, takeover notes on the native state database and
  transport bounds, a static-token rotation runbook, and Stage 5 notes for
  Marlowe and Windows.
- Evidence these docs cite under `/tmp` (68 entries) was copied with modes and a
  verified sha256 manifest to that private consolidation directory.

Accepted limits, unchanged now:

- Native commands without the updater's explicit argument set use a separate
  `~/.config/chezmoi/chezmoistate.boltdb`; always pass the full set
  ([takeover.md](takeover.md#updates-and-edits-after-takeover)).
- An HTTPS connect to a silently dropped route is bounded only by OS/curl defaults.
- Replacing an enrolled token in place stalls that host's updater until the new
  ciphertext lands; follow the runbook in [secrets-and-ssh.md](secrets-and-ssh.md).
- At the user's request, the 80 plaintext token copies in Lab's private Stage 4
  backups and rehearsal destination were deleted after hash verification; their
  manifests and receipts remain. No other host held copies.
- Windows Codex sandbox grants are app-created; dotfiles manages no directory ACLs.
- Retired submodule leftovers and legacy wrapper links stay until Stage 6.
- A change to a Codex key that dotfiles owns can race a Codex app-server that
  starts around the login update, as on WSL above. Quitting every Codex client
  that can start one on that host, remote desktop apps included, before that
  first login should avoid it; otherwise reconcile the one file as described
  there.

Stage 5 inputs, none blocking this checkpoint:

- D7 payload lifecycle, including Sherlock's `~/.cache` refusal, Marlowe's
  Codex skills root limit and Windows' first foreground skills install.
- Marlowe login nodes: accept and document, give Marlowe Claude settings without
  Node hooks, or port the helpers off Node; descope Codex there or use a non-Node
  binary. Never bypass the site profile.
- Make the config template set `persistentState` (requires reviewed re-init), or
  keep the full-argument rule.
- Windows: review the inherited sandbox Modify grant on `~/.local/bin` or verify
  the executable before running it, then prefer the exact provisioned
  `chezmoi.exe` over the first PATH match; name the parent ACL model of any new
  target under an existing parent.
- Widen the gitleaks secrets-directory rule to the encoded `private_dot_secrets/`
  source path; the source-guard unit test already blocks plaintext there.
- Decide whether `tui.status_line` stays an owned Codex key, enforced on every
  update, or becomes a default seeded only when absent, so that Codex's own
  rewrites cannot stop the login updater.
- Last step of Stage 5, after its final docs land: move Lab's private
  `$HOME/dotfiles/.git/chezmoi-migration-recovery/` to
  `~/.local/state/dotfiles-chezmoi-migration-recovery/`, keeping modes and
  subdirectory names. Verify every manifest by readback before removing the
  original, and update every doc path that cites it.

### Stages 1-4 component map

- Native source root: `.chezmoiroot`, `home/.chezmoi.toml.tmpl`,
  `home/.chezmoiignore`, `home/.chezmoitemplates/validate-host`; explicit
  `[data].host`, owned fast-forward update config, role ignores and the secret
  gate. Tests: `test_chezmoi_source_state.py`, `test_chezmoi_update_config.py`,
  `test_chezmoi_rendered.py`.
- Ordinary bridge: `home/**.tmpl` literal includes of the 95 legacy package
  paths, which stay canonical until Stage 6; see [inventory.md](inventory.md).
- AI transforms: `home/dot_claude/modify_private_settings.json`,
  `home/dot_codex/modify_private_config.toml`, `home/.chezmoidata/codex-policy.json`.
  Tests: `test_chezmoi_claude.py`, `test_chezmoi_codex.py`,
  `test_chezmoi_native_config.py`.
- Static secrets: eight `home/private_dot_secrets/encrypted_private_claude-*.age`,
  builtin age, five host recipients plus R. Test: `test_chezmoi_secrets.py`.
- Ownership and maintenance: `lib/chezmoi-guard.sh`/`.ps1` and the refusals in
  every legacy writer and payload hook. Tests: `test_chezmoi_guard.py` and the
  takeover tests.
- D6 login adapters: `scripts/chezmoi-update.sh`/`.ps1`, dispatched from the
  shared profiles and the PowerShell profile.
- Provisioning and doctor: native-default `setup-host.*`, `lib/bootstrap*`,
  `doctor.*` and `config/bootstrap/*` with the pinned v2.74.0 (static musl on
  Sherlock); `--legacy-stow` / `-LegacyStow` keep the old path.
- Takeover and recovery: [takeover.md](takeover.md) with
  `test_chezmoi_takeover_{unix,windows,recovery}.py`.
- Retained for Stage 6: legacy packages, `stow-all.*`, `.stowrc`, `setup-sync.*`,
  `.venv-sync`, `lib/sync-runtime.sh`, `lib/config_sync.py`, the four sync
  wrappers, the old updaters and the disabled Windows restow task.

## Stage 4 closure

The user explicitly approved the remaining deployments, commit/publication and
main integration, selected shared Codex `gpt-6-astra` / `xhigh`, resumed Windows,
and requested the lightweight Sherlock kit update on its login node. No blanket
approval, recovery-custody choice or mandatory job ID remains outstanding.

All five Unix hosts have accepted all eight secret targets, nonforce
convergence, offline consumer and actual updater checks. Their enrollment flags
are true and maintenance is off. WSL's final acceptance binds actual fresh SSH;
Marlowe uses the existing authenticated master and does not claim fresh MFA.

Sherlock's official kit 0.7.0 update passed: 50 new release files, all 53 previous
files retained, nine owned links and parent security metadata preserved. It used
the existing login environment and required no environment build or job. Fresh
site rules permit this bounded source-file deployment; the earlier allocation
block was an overly strict interpretation. Sherlock also accepted all eight
secret files on `15068b9`: empty 62-target diff, offline consumer, actual updater
and existing-master access passed. Final acceptance rechecked persisted bindings;
maintenance is off. An earlier post-repeat metadata guard failure remains of
unknown cause; the reviewed remaining-only continuation did not replay deployment.

Windows completed native takeover on `15068b9`: all 26 targets are regular
files, with seven protected ACL replacements, 16 native owned-link conversions
and three existing regular-file applications. Two nonforce repeats, empty diff,
both PowerShell profile smokes, actual ordinary-token updater and same-session
skip, fresh nonmultiplexed SSH and persisted-binding acceptance passed. All 61
parents stayed unchanged; maintenance is off and secret enrollment remains false.
Five exact idle operator tasks were removed. The legacy restow task remains
disabled for Stage 6 retirement. Earlier bounded operator failures and reviewed
continuations remain recorded separately; no GUI or account-authentication claim
is made. All six hosts have actual Stage 4 acceptance.

Lab's approved Astra/xhigh correction passed. The subsequent formatting-only
rewrite is handled by the accepted native modifier fix: after all existing
validation and transformations, preserve original input when native typed equality
says no change is needed. Actual policy changes retain canonical serialization
and ordinary conflict protection. Lab's fresh 67-target review and eight-file
enrollment passed on `15068b9`, preserving all 59 ordinary files and five excluded
auth siblings. Two nonforce applies, empty full diff, offline consumer, automatic
updater and fresh nonmultiplexed WSL-to-Lab SSH passed. Persisted post-apply
bindings were rechecked before acceptance; maintenance is off and enrollment true.

Local and remote main reached runtime correction
`15068b9936dc1bf36416d59154746e8f643d5bd5` after all three jobs of CI
41684120644 and all eight bootstrap e2e 41684121107 jobs passed. Full local
`tests/run.sh --ci`, frozen full pre-commit and independent review also passed.
Integration includes all earlier outcome commits through `12262e6`. Current
per-host evidence and limits are in [stage-4-evidence.md](stage-4-evidence.md).
Stages 5/6 have not started.

Worktree-policy commit `493f39545a63f69c32648b97936736286fa43dcd` passed all three
jobs of CI 41702351649 and all eight bootstrap e2e 41702352195 jobs. The two
relative-path fixtures now isolate themselves in their existing temporary homes;
runtime behavior is unchanged. The full Linux suite and pre-commit passed.
Local and remote main then fast-forwarded to that exact policy commit. Lab's two
global instruction files were refreshed with targeted nonforce apply and repeat;
their diff is empty and file modes/parent security metadata were preserved.
The closure commits `2a612f5` and `a5d9ad7` then passed exact CI 41719265671 on
all three platforms, and local and remote main fast-forwarded to `a5d9ad7`.

Committed Stages 1-4 are stored in the main checkout's persistent Git object
store and published on origin/main; the `/tmp` worktrees are not their only
copy. At the user's preservation checkpoint, all 28 migration worktrees were
saved under `$HOME/dotfiles/.git/chezmoi-migration-recovery/20261103-checkpoint-15068b9-02`:
full staged/unstaged binary patches, 562 nonignored untracked files with original
modes, original Stage 3/tmux patches and handoff records. The 653-file core
manifest passed readback verification. Separate private Lab, Windows, Sherlock
and review exports preserve safe operator evidence without credential values or
identities. These local Git-metadata backups are not committed or pushed. After
fresh verification and release by active agents, 26 completed worktrees and 25
merged task branches were removed. After the closure reached verified main, the
coordinator and its branch were removed too: 27 task worktrees, 26 merged local
branches and seven task-owned remote CI/e2e branches in total, leaving only main.
The final private record is `FINAL-HANDOFF.md` in that checkpoint. Retain the
checkpoints. Future work starts from main. Never replay an old aggregate patch
over newer main.

## Publication and historical operational checkpoints

The following checkpoints retain what was known then. The current continuation
above supersedes their pending approvals, Windows deferral and allocation claim.

- Planning baseline: `738f619` on 2026-11-01. It includes local tmux changes after
  the initial feasibility assessment at `2c177fc`.
- Original consolidation baseline: `1a9d30b`. The other review session finished
  its fixes and integrated tmux before the plan merge; retain that history.
- Initial published Stage 4 bridge: local and remote `main` reached exact commit
  `9c1a31f4efa0b23a67e9a20640a2f236eae64325` after all three jobs of
  [CI 41558979663](https://github.com/FridrichMethod/dotfiles/actions/runs/41558979663)
  and all eight jobs of
  [bootstrap e2e 41558979671](https://github.com/FridrichMethod/dotfiles/actions/runs/41558979671)
  passed. No force or history rewrite was used.
- Accepted ordinary-native release:
  `bf9995809ca7564c0728f87bcbefe91c8a3cc5e0`, after all three jobs of
  [CI 41567805090](https://github.com/FridrichMethod/dotfiles/actions/runs/41567805090)
  and all eight jobs of
  [bootstrap e2e 41567805363](https://github.com/FridrichMethod/dotfiles/actions/runs/41567805363)
  passed. Local and remote main fast-forwarded to that exact commit. It includes
  the Sherlock static artifact, portable Terminal preference, five-host secret
  gate, directory-mode correction and the user's exact tmux handoff. The two
  matching main edits were deliberately staged before the fast-forward; no user
  work was discarded. Inspect subsequent working-tree changes before carrying.
- Published encrypted-source release:
  `74985d08f6ec91391e8f6ba3b54e95d08ad91d44`, after all three jobs of
  [CI 41586461636](https://github.com/FridrichMethod/dotfiles/actions/runs/41586461636)
  and all eight jobs of
  [bootstrap e2e 41586462369](https://github.com/FridrichMethod/dotfiles/actions/runs/41586462369)
  passed. Local and remote main fast-forwarded to that exact commit. Only the
  eight approved ciphertexts entered source; target deployment is a separate gate.
- Outcome checkpoint `cb7f11a039fbfc00428408e873730701d0aebf9b` passed all three
  jobs of [CI 41613012922](https://github.com/FridrichMethod/dotfiles/actions/runs/41613012922)
  on `ci/chezmoi-stage4-outcomes`. Later outcome records are prepared on the same
  integration branch and require their own exact CI. Main remains `74985d08`
  while the retained WSL deployment plan binds that revision. Lab's later model
  drift invalidates its old plan and requires a fresh review. Complete the WSL
  plan or explicitly replace it with a fresh reviewed plan before advancing
  main; do not run a stale plan after its updater would pull a newer revision.
- Implemented migration candidates: Stage 1 isolated foundation, Stage 2 ordinary
  source, Stage 3 native AI configuration and Stage 4 compatibility/takeover.
  The corrected runtime passed hosted validation and the lab ordinary-file
  canary. Secret custody and per-host rollout remain separate outcomes; see
  [Stage 4 evidence](stage-4-evidence.md).
- Lab ordinary takeover is accepted: 59 regular targets, repeat convergence,
  unchanged parent modes, shell and fresh SSH checks, actual automatic native
  update and old-writer refusal passed. Native ownership/state remain; maintenance
  was removed at ordinary acceptance and later reenabled for secret enrollment.
  WSL's 55 ordinary files and updater/access checks also passed;
  its preexisting tmux prerequisites remain missing. Sherlock and Marlowe each
  accepted 54 ordinary files and actual updater checks, with maintenance removed;
  access used existing authenticated masters, not fresh MFA. Mac subsequently
  accepted 56 ordinary files, controlled updater activation and fresh
  nonmultiplexed SSH. The user explicitly deferred Windows' ordinary-user gate.
- Initial connection-only preflight: four SSH successes, local lab-ubuntu access, and
  SSH auth rejection on win/lab-ubuntu; see [fleet rollout](fleet-rollout.md).
- Earlier connectivity-only follow-up: Mac's own SSH client reached win and
  lab-ubuntu, establishing an observed route for all six at that checkpoint.
  The user then added the lab public key on
  Windows; fresh direct lab-to-win SSH was independently verified. Both public
  keys and the existing ACL remain intact. Only the one new authorization-file
  backup was removed at the user's request. That connection check performed no
  dotfiles migration; later actual takeover is recorded separately above.
- All five host identities were generated privately on their own hosts. The
  eight approved static inputs were encrypted in an isolated private Lab capsule
  for exactly those five recipients plus R. Lab, Mac, WSL and retrieved R have
  each decrypted all eight with private equality checks, and both clusters then
  passed the same checks: 48 equalities across six recipients. A disposable
  outsider failed all eight. Only the verified ciphertexts entered `74985d08`;
  source publication passed its exact gates. Mac subsequently accepted all eight
  deployed secret targets, offline consumer checks, updater and fresh SSH.
  Marlowe subsequently accepted all eight with 62-target convergence, retained
  authenticated access and an unchanged persisted post-apply binding.
  Lab, WSL and Sherlock enrollment flags remain false at this checkpoint.
  See [secrets and SSH](secrets-and-ssh.md).
- Eight static Claude files are approved for lab, Mac, WSL, Sherlock and Marlowe
  plus recovery recipient R. Mutable Codex auth stays excluded and SSH stays
  ordinary. Apple Passwords is selected and already syncs to another usable
  device; R was generated privately on Mac. The user reported local recipient
  matching and retrieved-R-only challenge PASS, then explicitly confirmed full
  retrieval of the saved item on another device. Custody and host bootstrap are
  established. Mac secret-canary acceptance restored its automatic updates.
  Lab and WSL are temporarily in maintenance after their separately approved
  one-file Codex normalizations; ordinary acceptance above remains valid.
  Marlowe's eight-file deployment restored automatic updates after private
  backups, 62-target review and an exact source fast-forward.
  All five task-installed
  Bitwarden clients were removed; Sherlock never had one installed.
- Native chezmoi executables tested: official v2.74.0 Linux amd64, Darwin arm64
  and Windows amd64, SHA256 verified. Stage 3's final candidate has 64 native
  test methods; exact passes/skips and full-run evidence appear below. Remote work
  used private temporary fixtures at those checkpoints; their evidence is
  distinct from the later takeovers and real cryptographic enrollment above.
  No production credentials were used in those isolated fixtures.
- Active work at that checkpoint: finish [Stage 4](stage-4-takeover.md) and its
  recorded gates. Stage 4 has since closed; see the consolidation checkpoint above.
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

## Historical planning validation

The following records describe the original planning checkpoints, not the
current publication or host state.

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
At that checkpoint the package was uncommitted. The later bridge publication
supersedes that state; original untracked planning files were preserved privately
before the main fast-forward.

## Stage summary

| Stage | Code/check status | Real-host status | Completion evidence |
| --- | --- | --- | --- |
| 1 | Implemented; Linux/macOS/Windows probes and independent review | No real HOME takeover or fleet migration | 23 probes; Windows one Unix-TZ skip; inventory and CI integration |
| 2 | Ordinary source and explicit host implemented; final validation record below | Isolated fixtures only; no takeover | Exact seven-role sets/bytes/modes and native platform checks |
| 3 | Native Claude/Codex candidate implemented; validation record below | Isolated fixtures only; no takeover/enrollment | Exact policy/ownership, safe input refusal and complete native source |
| 4 | Runtime `bf99958`, encrypted source `74985d08` and formatting correction `15068b9` passed exact CI/e2e and reached main; worktree policy `493f395` passed its exact CI/e2e; closure `a5d9ad7` passed exact CI 41719265671 | All six native takeovers accepted; all five Unix eight-file secret enrollments accepted; Windows enrollment stays false | [Evidence](stage-4-evidence.md), [operator procedure](takeover.md) |
| 5 | Not started | Depends on integration scope | None |
| 6 | Not started | Native-only deletion candidate and actual retirement not implemented | None |

## Decisions and open choices

Use the canonical `$HOME/dotfiles` main checkout and this committed record for the
next stage. Accepted runtime `bf99958`, encrypted source `74985d08` and native
formatting correction `15068b9` already reached local and remote main. Preserve
subsequent commits and inspect staged, unstaged and untracked changes before
creating a fresh `.worktrees/` task checkout. The former Stage 4 coordinator
was removed after verified integration; no future stage depends on its path.
Do not replay the old whole-aggregate `/tmp/chezmoi-stage4-candidate.patch` over
newer main. Original Stage 3 inputs and earlier patches are historical recovery
evidence in the durable checkpoint. The original main tmux edits were preserved
in the coordinated landing. The user explicitly authorized commits, publication
and rollout; no blanket authorization question remains. Recovery custody is
established; exact candidate CI/e2e and concrete host gates still apply.
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
| D13 | Builtin age, separate native host identities, explicit per-file recipient scopes | Eight static Claude files approved for five Unix hosts plus R; all five identities generated locally. Apple Passwords custody confirmed on another device and retrieved R decrypts all eight. Published in `74985d08` and accepted on all five Unix hosts; Windows enrollment stays false |

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

## Stage 4 ordinary acceptance and remaining host gates

Corrected runtime `bf99958` passed its exact CI/e2e runs linked above and reached
main before lab canary and WSL execution. It includes the reviewed Sherlock
artifact, Terminal preference, five-host static-secret scope, tmux handoff and
directory permission correction. Earlier fixture counts retain their original
snapshot scope. Final local native validation ran 149 methods with 31 Windows
method skips; hosted native Windows and Mac passed at the exact release.

During lab preparation, isolated probes found that plain native apply changes
existing parent modes, including 0700 private directories and a 0770 shared
`.config`. The finding stopped the first attempt before target writes and was
fixed before actual takeover. The accepted contract pins `--exclude=dirs` on
file apply, diff and routine update. Inspect the native `managed --include=dirs`
inventory relative to the canonical destination, including ancestor ownership,
links/reparse points, modes and ACLs. Only exact still-absent reviewed directories
may be created using native `apply --include=dirs --recursive=false` with those
targets; skip the command for an empty list. Preserve all existing parents.
Future missing parents require the same preparation. Git or earlier files may
already have changed before a later failure; there is no transaction or fallback
to all-directory apply. See [takeover.md](takeover.md) for the complete procedure.
All five accepted Unix hosts use reviewed local native `umask = 0o077` to avoid
widening known 0600 files; this is a local choice, not a global shell-umask policy.

### Historical operational checkpoint before the direct continuation

This table and the following custody/allocation notes preserve an earlier
checkpoint. The current continuation at the top and the current fleet table in
[Stage 4 evidence](stage-4-evidence.md#actual-fleet-outcomes-separate-from-fixtures)
supersede these old pending approvals, deferral and allocation claims.

| Host | State at this checkpoint | Gate at this checkpoint |
| --- | --- | --- |
| lab-ubuntu | 59 ordinary targets accepted. User-approved one-file normalization passed once. The subsequent 69-file backup and 67-target preview passed, but a later read-only guard found one changed native-owned `model` value in live Codex config; all other bindings and backups remain exact | Old secret plan is stale and unexecuted. Preserve the current model until its intended scope is resolved, then prepare a fresh review; no silent rebind or repeated force. Deployment confirmation also remains pending after automatic review refused execution. Maintenance on, enrollment false; excluded auth siblings untouched |
| mac | Secret canary accepted on exact `74985d08`: eight files 0600 in a new 0700 parent, 56 ordinary files unchanged, two nonforced applies, empty diff, offline consumer checks, one updater pull and fresh nonmultiplexed SSH passed | Persisted post-apply bindings rechecked before acceptance; maintenance off, enrollment true. Shared `.config` 0770 preserved. Earlier automatic-review denials were resolved by a new direct-user approval; no GUI/p10k or credential-server acceptance claim |
| wsl-ubuntu | 55 ordinary targets accepted. User-approved normalization passed once. Fresh continuation bound actual Mac acceptance and normalized state, retained maintenance, backed up 57 files and passed all 63 native target equalities | Automatic approval review rejected secret apply before execution, recognizing only the recent normalization approval. Specific deployment confirmation pending; maintenance on, enrollment false, secret parent absent. Existing 11 tmux prerequisites and retired-submodule warning remain |
| win | 26-target metadata preflight; 23 exact links and three regular files. Terminal preference retained | User explicitly deferred ordinary-user execution/ACL check; no target/task/production ACL change or takeover |
| sherlock | Verified official static musl installed; clean `bf99958`, 54 reviewed regular targets, preserved parents/cache layout, repeat convergence and actual updater/old-writer refusal passed. Maintenance removed; private state/binding retained | Historical postcheck interruption has unknown cause; reviewed bounded continuation passed with current-state backup. Existing master is not fresh MFA proof. Kit 0.6 upgrade/allocation gates secret deployment; identity and eight-file crypto checks passed |
| marlowe | Runtime installation/repair and consumer checks passed. Verified 56-file backups before and after the exact BF-to-749 source fast-forward preceded all 62 target previews. Eight-file deployment passed twice nonforce, empty diff, offline consumer, actual updater and existing-master access; 54 ordinary files and runtime/parents unchanged | Secret deployment accepted after rechecking persisted post-apply bindings. Maintenance off, enrollment true; eight files 0600 in a new 0700 parent. Earlier bridge approval denial resolved by new direct-user approval. No fresh MFA or credential-server authentication claim; native Codex remains a separate absent prerequisite |

Apple Passwords custody is chosen and second-device sync is confirmed. The
private handoff generated independent R on Mac. The user reported
`RECIPIENT_MATCH=PASS` and `RETRIEVED_R_ONLY_CHALLENGE=PASS`, then explicitly
confirmed full retrieval from another device. This closes the independent
custody gate without exporting the key. R alone must recover all eight approved static files, each
encrypted for the five host public recipients plus R; host private identities
never leave their hosts. Mutable Codex auth remains local, and SSH snippets remain
ordinary. All five host identities and eight private production ciphertexts now
exist; retrieved R alone passed actual eight-file recovery. Encrypted source
`74985d08` is published; actual deployment remains a separate gate. Bitwarden was canceled:
all five task-installed clients were removed, Sherlock never installed one, and
no Bitwarden installation remains planned. A separate, concrete proposal for a
local pinned sherlock-kit v0.6.0 controller received the required dependency
approval, was installed separately and passed doctor. New-job submission is
also explicitly authorized; no additional approval or mandatory job ID is
pending. Current numbered site Rule 10 still requires at least ten useful
minutes per job, and no compliant bundle/allocation has been established for
the short coding-agent-kit upgrade. See stage-4-evidence.md.
The Mac uninstall's unintended LLVM
removal was disclosed and exact version 22.1.8 restored; do not claim identical
prior keg bytes. Detailed receipts stay in [Stage 4 evidence](stage-4-evidence.md).

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
