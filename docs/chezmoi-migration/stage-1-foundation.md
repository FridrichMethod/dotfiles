# Stage 1: Native contract and fixture foundation implementation plan

Stage 1 implementation/evidence is recorded in [status.md](status.md).
This document preserves the acceptance plan; do not restart it from its original
unchecked task list. Local TOML temporal behavior remains an explicit Stage 3
condition. Native Linux/macOS/Windows fixtures and both platform entrypoints
have now run; the Windows Unix-TZ skip has a supplemental native observation.

> **For agentic workers:** Use the available subagent-driven-development workflow
> with separate write worktrees, following the protocol in [README.md](README.md).
> Complete only this stage and refine Stage 2 before handing off.

**Goal:** Establish tested native behavior, a complete migration inventory and
explicit layout/tool-support choices without changing any default installer,
login hook or real HOME.

**Architecture:** Small black-box tests invoke one selected real chezmoi binary
with fully isolated source, destination, config, cache and state. Test-only native
templates prove the simplified merge contract. The existing Stow path continues
to work unchanged.

**Tech stack:** Chezmoi, Python 3.11+ stdlib unittest, existing Bash/PowerShell
test entrypoints, Git and the existing three-platform CI.

**Spec:** [Migration direction](README.md), [current state](status.md),
[official evidence](sources.md), [support boundary](support-boundary.md).
Also read [secrets and SSH](secrets-and-ssh.md) and the already recorded
[six-host access baseline](fleet-rollout.md).

## Global constraints

- No live apply, recursive HOME import, application startup, credentials or real
  daemon access. No network/download inside behavioral tests.
- No new Python package, parser, virtual environment or template framework.
  Existing legacy tests may still require their already provisioned sync runtime.
- Native JSON/TOML formatting changes are allowed; lost live values and modified
  security-policy values are not. Read the contract table in the spec.
- The selected chezmoi binary is mandatory in CI. Missing local prerequisites
  produce an explicit skip/failure according to the existing test convention.
- Root `AGENTS.md`, CI, pre-commit and runner integration have one coordinator
  owner. Do not use this stage to rewrite unrelated bootstrap or shell behavior.
- Native platform validation may use fresh private temporary directories through
  existing authorized access. This does not authorize real HOME takeover, token
  inspection or remote migration. The inventory worker's no-host-contact rule
  applies to inventory work; it is not a reason to skip native platform probes.

## Review focus

1. Inherited real chezmoi config, environment, Git index overrides or default
   cache/state must not redirect a fixture outside its temporary root.
2. An empty, malformed or failed modify result must not accidentally delete or
   replace a target that should have been preserved.
3. False, null, empty arrays, literal dotted keys and TOML-specific values must
   not change type or disappear in a generic merge.
4. The inventory must include current tracked files, especially new tmux files;
   stale counts and role-only rollout lists are insufficient.
5. A missing binary or Linux-only result must not be reported as complete native
   Windows/macOS evidence.

## Read first

Read `tests/run.sh`, `tests/run.ps1`, `tests/lib/environment.*`,
`.pre-commit-config.yaml`, `.github/workflows/ci.yml`, `lib/config_sync.py`,
`tests/test_config_sync.py`, `.stowrc`, the package selection in `stow-all.ps1`,
and current `common/tmux/`. Use the evidence map for deeper references.

Inspect status and local commits before creating worktrees. Handoff files may
not yet be committed; carry them intentionally as described in the spec.

## Task 1: Select and document a real native test runtime

**Owner:** Coordinator, with a read-only upstream researcher if useful.

**Files:** Update `sources.md` and `status.md`; integration changes to existing
CI and prerequisite checks happen in Task 5. Do not add a second global tool
inventory or install chezmoi during shell startup.

**Interface:** `DOTFILES_TEST_CHEZMOI` is an optional explicit executable path.
Otherwise the fixture resolves `chezmoi` on PATH. Resolve it before restricting
the child PATH. An invalid explicit path fails instead of falling back.

- [ ] Record the starting revision and pre-existing changes.
- [ ] Verify an official stable release; v2.74.0 is the research candidate, not
  a previously tested floor. Use a versioned, verified artifact or an existing
  supported binary. Keep downloads/provisioning outside test execution.
- [ ] Record the exact version, supported platform artifacts, checksum/provenance
  mechanism and CLI features used. Use repository install conventions; do not
  introduce pipe-to-shell installation.
- [ ] Verify actual support for `--source`, `--destination`, `--config`, `--cache`,
  `--persistent-state`, `--no-tty` and `--error-on-conflict`. Native invocation
  behavior, not only documentation, determines the eventual minimum version.
- [ ] Freeze the fixture interface below before worker implementation. No
  production `.chezmoiversion` is needed until Stage 2 creates production source.

## Task 2: Add the small isolated fixture and deployment probes

**Owner:** Fixture worker in its own worktree.

**Create:** `tests/chezmoi_support.py`, `tests/test_chezmoi_foundation.py`, minimal
artificial source files under `tests/fixtures/chezmoi/foundation/`.

**Interface:** A small `ChezmoiFixture` context manager exposes `source`,
`destination`, `config`, `cache`, `state` paths and
`run(*args: str, input: str | None = None) -> subprocess.CompletedProcess[str]`.
It uses the binary selected by Task 1. Keep this a subprocess/temporary-directory
helper, not an abstraction over chezmoi's state model. Set finite child timeouts.

Every child uses explicit temporary paths for all five locations, a temporary
HOME/USERPROFILE and relevant XDG/temp directories, and noninteractive test
settings. Reuse the existing environment isolation entrypoints; drop inherited
CHEZMOI-related overrides and fixture Git overrides before mutations. Keep test
input overrides deliberate. Include paths with spaces.

- [ ] Add `test_regular_file_and_second_apply_converge`: a plain source becomes
  a regular file; a second apply/diff has no remaining intended changes.
- [ ] Add `test_explicit_paths_ignore_inherited_user_state`: poison inherited
  chezmoi paths with fixture-owned sentinel locations; none may be read as config
  or changed. Assert all generated cache/state stays inside the fixture.
- [ ] Add `test_destination_drift_is_not_forced`: after native apply, edit the
  destination and alter its source; a noninteractive conflict must not silently
  replace the destination. Verify the selected native flags and failure result.
- [ ] Add `test_private_file_and_source_immutability`: verify Unix private mode
  and unchanged source bytes; report Windows ACL behavior separately.
- [ ] Add `test_dry_run_preserves_destination`: compare destination snapshots,
  while allowing native cache/state only inside the fixture. Use no hooks.
- [ ] Add `test_owned_symlink_can_become_regular_file`: on supported native
  fixtures, establish the documented content-import/takeover behavior without
  modifying the original source. Foreign-link decisions belong to Stage 4.
- [ ] Run the tests before implementing fixture behavior to expose missing
  integration; then implement the minimal helper and rerun. An unavailable binary
  is a prerequisite failure/explicit skip, not the intended red-test evidence.

## Task 3: Prove native JSON and TOML transforms

**Owner:** Native-semantics worker after Task 2's interface is available.

**Create:** `tests/test_chezmoi_native_config.py` and artificial modify templates
under `tests/fixtures/chezmoi/native-config/`.

**Consumes:** `ChezmoiFixture`. **Produces:** executable evidence for Stage 3 and
a short result table in `sources.md`, integrated by the coordinator.

Use actual `modify_` templates with `chezmoi:modify-template`, no `.tmpl` suffix,
and `.chezmoi.stdin`. Use native functions, not calls to the legacy merge backend.

- [ ] Add a JSON test with live data
  `{"model":"local","permissions":{"allow":["old"],"additionalDirectories":["local"]},"x":1}`
  and portable data
  `{"permissions":{"allow":[],"ask":[]},"x":false,"y":null}`.
  Assert preserved model/additionalDirectories, empty authoritative arrays,
  boolean false and null. Test the builtin `jq` result-list handling.
- [ ] Add malformed/empty/missing JSON cases and reject non-object Claude roots.
  A parse error must fail without replacing that target. Characterize duplicate
  keys and numeric limits as native behavior, not legacy compatibility failures.
- [ ] Add TOML cases preserving unknown tables, a quoted dotted project key,
  arrays of tables, multiline strings, integer values and a native timestamp.
  Parse assertions with stdlib `tomllib` where appropriate. Do not route the
  whole TOML document through JSON/gojq.
- [ ] Verify literal `"*"` path assignment and actual delete-path argument forms
  on the selected release. Verify a non-table ancestor can be rejected before
  assignment rather than silently discarded.
- [ ] Verify first-apply normalization and second-apply convergence. Do not test
  original comment/whitespace/inode preservation as requirements.
- [ ] Run native transforms with a deliberately restricted child PATH containing
  neither Python nor external jq, and with no `.venv-sync`. The Python unittest
  parent remains allowed; it must not be a merge runtime dependency.
- [ ] Record any discrepancy between tagged source, docs and observed behavior.
  If native features cannot preserve a retained requirement, document the minimal
  unresolved case and refine Stage 3; do not add a compatibility parser.

## Task 4: Inventory targets and classify contracts

Before inventory integration, extend Task 3's native probes with a small
`tests/test_chezmoi_secrets.py` and synthetic files under
`tests/fixtures/chezmoi/secrets/`, owned by the native-semantics worker:

- [ ] Prove builtin-age encrypt/decrypt/apply with disposable identities and no
  external age executable. Test private files/directories, unchanged source,
  second apply and no plaintext canary in source or captured reporting paths.
- [ ] Test missing identity, malformed ciphertext and unavailable/locked backend
  without prompts or replacement of the affected existing secret. Record actual
  native behavior; do not promise whole-home atomicity.
- [ ] If initial auth seeding is proposed, test native create-if-missing against
  existing refreshed data and logout/deletion; avoid persistent credential reseed.
- [ ] Select a backend and feasible recipient/key-bootstrap design using the
  narrow consumer inventory below. No real secret enrollment in this stage.

Keep these tests small and synthetic; do not build a vault abstraction or use
live credentials/password-manager sessions in CI.

**Owner:** Inventory worker; can run alongside Task 2.

**Create:** `docs/chezmoi-migration/inventory.md` and, if needed by tests, one
test-only mapping fixture under `tests/fixtures/chezmoi/`. No runtime manifest or
new general deployment generator.

**Interface:** For each tracked package file, record legacy source, destination,
applicable hosts, category, native representation, current owner and removal stage.
Categories: ordinary configuration, executable helper, mutable config, external
asset, payload-owned path, or migration-only compatibility file.

- [ ] Derive from current tracked paths, not a recursive scan of real HOME or
  ignored checkouts. Include binary terminfo/pet assets and new tmux files.
- [ ] Account for `.stowrc` exceptions and the native Windows common allowlist.
  Include common-only and all six explicit host roles.
- [ ] List source-path assumptions in wrappers/profiles and tests that directly
  read legacy paths. Distinguish behavior tests to port from mechanism tests to
  retire. Preserve tmux and shell behavior coverage.
- [ ] Classify legacy guarantees as retained, deliberately native, temporary
  compatibility or deferred product choice using the spec's contract table.
- [ ] Incorporate the historical-removal units in `support-boundary.md`; map
  callers/tests/docs to the owning stage. Plan most Stow repair deletion with
  Stow retirement, rather than a separate refactor of the old installer.
- [ ] Add a tool-support table to `inventory.md`: current/proposed minimum,
  concrete removable branch or required feature, official interface evidence,
  actual tested version, provisioning/CI invocation changes and owning stage.
  Include tmux gates, old Claude plugin ID, Bash 3.2, Python/Stow and PowerShell.
  Keep small current interoperability features unless obsolescence is proven.
- [ ] Record the declared current-layout-only direction and the manual old-host
  upgrade deliverables. Select floors only after evidence; do not claim the
  candidate tmux 3.4 floor is the latest release or raise all floors arbitrarily.
- [ ] Specify Stage 2's temporary single-source bridge and its parity check; do
  not plan two independently editable copies of portable policy.
- [ ] Record real-host checks separately from CI. Do not contact remote hosts,
  invent a fleet list, or restore the superseded all-host-attestation gate.
- [ ] Carry the six observed targets/access limits from fleet-rollout.md into the
  handoff. Later stages must recheck and execute the authorized host rollout.
- [ ] Classify selected secret consumers by static vs application-written state,
  destination, rotation and host scope, using metadata/documented interfaces only.
  Do not infer type from filenames or copy account labels/values into public docs.
  Separate SSH connection snippets, private keys and known_hosts/runtime state.

## Task 5: Integrate, validate and prepare Stage 2

**Owner:** Coordinator, then a separate read-only reviewer.

**Create:** `tests/chezmoi.sh`, `tests/chezmoi.ps1` as thin existing-style test
entrypoints. **Modify:** `tests/run.sh`, `tests/run.ps1`,
`.pre-commit-config.yaml`, `.github/workflows/ci.yml`, `docs/testing.md`,
`tests/COVERAGE.md`, and stage handoff records. Update `AGENTS.md` only as needed
to permit the test-only native migration path while keeping legacy behavior.

- [ ] Integrate workers sequentially. Test entrypoints reuse repository
  environment cleanup and execute the stdlib tests. They do not provision tools.
- [ ] Provision the selected real binary explicitly in all three CI jobs and
  make its absence fail CI. Keep Linux's single all-files pre-commit behavior
  pass and native macOS/Windows runners; avoid a duplicate full-suite pass.
- [ ] Keep old parser provisioning for legacy suites during this stage. Record
  that this is transition-only; never claim the repo already needs no venv.
- [ ] Scope `check-json` / `check-toml` exclusions to the new artificial modify
  template paths: their required `.json` / `.toml` suffix does not make their
  Go-template source valid JSON/TOML. Validate rendered output in native tests;
  keep parser hooks on real baselines and all other data files. Do not disable
  the hooks globally. Check this when introducing the first fixture, not only
  when production templates arrive in Stage 3.
- [ ] Run focused checks:
  `python3 -I -B -m unittest discover -s tests -p 'test_chezmoi*.py' -v`,
  through the isolated entrypoints where environment cleanup is required.
  Expected: all available native fixture cases pass; skips are explicit.
- [ ] Run `tests/run.sh --ci` and `pre-commit run --all-files` as required by the
  repository; native Windows uses `tests/run.ps1 -CI`. Record unavailable native
  evidence instead of claiming it. If publishing is authorized, satisfy the
  existing exact-commit CI gates.
- [ ] Review isolation, type preservation, no forced drift overwrite and no
  live/default behavior changes. Measure added infrastructure and remove generic
  abstractions that are not needed by these few probes.
- [ ] Keep `AGENTS.md` below its 28,000-byte limit; use a short transition rule
  and links rather than copying this planning package into project instructions.
- [ ] Update `status.md` with actual results. Expand Stage 2 into concrete tasks
  using the inventory; update Stage 3 with verified function forms and tests.
  Include the secret backend decision, remaining bootstrap/access questions and
  synthetic evidence; keep D11's later fleet execution authorization intact.
  Carry unresolved product decisions forward without blocking unrelated work.

## Exit and rollback

Exit requires real native behavior evidence, a complete tracked-target inventory,
honest platform results and a refined Stage 2. No real installation has changed.
Rollback is limited to this stage's branch/files and disposable fixtures; preserve
user commits and any pre-existing environment. Do not start Stage 2 automatically.
