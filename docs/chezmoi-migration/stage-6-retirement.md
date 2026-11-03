# Stage 6: Legacy retirement implementation plan

> **For agentic workers:** Use subagent-driven-development with separate worktrees
> under [README.md](README.md). Expand this framework from Stage 5's removal map
> only after the retirement gate is satisfied.

**Goal:** Remove the old Stow deployment and configuration-sync dependency chain,
leaving a complete native chezmoi workflow with no supported sync venv setup.

**Architecture:** Canonical portable files and policy live in native source state.
Temporary source bridges, legacy callers and their implementation-specific tests
are retired together. No continuing dual-manager support or migration service.

**Tech stack:** Chezmoi and the small integrations retained by Stage 5; existing
stdlib/platform behavior tests.

**Spec:** [Release invariant](README.md#release-invariant),
[retirement evidence](status.md#retirement-gate),
[support boundary](support-boundary.md), completed Stage 5.
Also follow [fleet rollout](fleet-rollout.md) and
[secrets and SSH](secrets-and-ssh.md).

## Hard entry gate

Stage 2 introduced 65 literal text bridges and two raw asset copies (WebP and
compiled terminfo). Materialize text once, move canonical AI policy once, and
remove the duplicate legacy assets only after exact parity checks. Update the
inventory-derived tests with the new authority at the same time. Remove all
surviving legacy include paths, including the Stage 2 init guard's explicitly
working-tree-rooted internal path if source layout changes. Do not leave a
generator or two independently editable policy copies after retirement.

The native path and chosen tool floors pass required checks; the supported-layout
cutoff, last supported Stow revision and manual bridge/clean-install/recovery
procedure are documented and tested. Migrated targets have one owner and old
workers/tasks cannot reclaim them. Active instructions agree with this boundary.

The user's explicit current-layout-only decision replaces universal migration
attestation. Do not wait for all offline hosts. Older installations may become
unsupported; do not claim the cutoff stops their old updater pulling a deletion
commit. If the native/cutoff deliverables are incomplete, finish them before
removing current source paths; do not build a fleet registry or legacy detector.

## Global constraints and review focus

Preserve current native/live changes and user work. Do not automatically remove
unrelated environments, caches, downloaded plugins, payload repositories or old
checkouts. D11 permits exact retirement of the identified dotfiles sync environment
on each successfully migrated host after its callers are gone. Keep ignored paths
for leftovers; never recursively delete `.secrets` or credential stores.

Review skipped-release/offline hosts; hidden runtime callers; temporary policy
duplication; rendered shell/tmux regressions; and a clean install that accidentally
uses developer-only dependencies.

## Task groups

### Source consolidation

**Owner:** Source worker, exact subtrees allocated from the Stage 5 inventory.

- [ ] Materialize the native source's ordinary files from their canonical legacy
  content and remove temporary include/copy bridges. Preserve real templates only
  where machine differences require them.
- [ ] Move the canonical portable AI values into native source data/template
  locations. Keep one ownership definition and one policy value source.
- [ ] Verify output parity before deleting old physical package paths. Retain
  intended shell override composition and native Windows applicability.
- [ ] Update tests that read `common/` directly to use native source or rendered
  fixtures. Preserve new tmux configuration and its stdlib metric runtime.

### Runtime and caller retirement

**Owner:** Runtime worker; coordinator integrates shared entrypoints/manifests.

Audit and remove each item only once no supported caller needs it:

- [ ] `stow-all.sh`, `stow-all.ps1`, `.stowrc`, normal symlink-trust helpers and
  retired auto-stow/update implementation selected for removal in Stage 5.
  Preserve the thin native login update adapter required by D6.
- [ ] Retired Sherlock/kit/PyMOL link repair, `filter.codex-portable` cleanup,
  generated-override repair, `scripts/awesome-skills-update.sh` and remaining old
  layout consumers/fixtures listed in `support-boundary.md`. Delete them with
  their old owners instead of porting them into chezmoi. Keep a short manual
  override-shadowing warning and old-host upgrade instructions.
- [ ] `lib/config_sync.py`, `lib/sync-runtime.sh`, three AI sync wrappers and
  fcitx5 materialization helper.
- [ ] `setup-sync.sh`, `setup-sync.ps1`, `requirements-sync.txt`, sync-specific
  `.venv-sync` probes/setup, `DOTFILES_SYNC_PYTHON` support and old dependency rows.
- [ ] Bootstrap S4/W1 branches and edges in `lib/bootstrap/steps-runtimes.sh`,
  `steps.sh`, `steps-human.sh`, `checks.sh`, `manifest.sh`, `lib/bootstrap.ps1`,
  `setup-host.*` and `doctor.*`, as they exist after Stage 5.
- [ ] Unconditional parser runtime checks in `tests/run.*`, fixture environment
  support, legacy sync tests, pre-commit hooks and all CI parser-provision steps.
- [ ] Corresponding bootstrap fixtures/e2e steps, tool/document parity entries,
  obsolete docs and mirrored skill instructions.

Search active callers with `rg` across tracked sources, not ignored third-party
checkouts or real HOME. Historical migration documentation may mention retired
names; distinguish that from active runtime dependencies.

### Native-only verification

**Owner:** Independent verification worker; review deletion sets read-only.

- [ ] Use a fresh isolated checkout/home with no sync venv, no installed TOMLKit
  and no external jq. Complete documented native initialization/diff/apply and
  a second convergent apply for each supported platform/host combination.
- [ ] Exercise known local edits, malformed mutable config, private attributes,
  unrelated siblings and configured fast-forward update refusal cases.
- [ ] Run preserved shell, tmux, PowerShell, AI policy and payload behavior suites
  against the final layout. Python stdlib remains allowed for those purposes.
- [ ] Verify minimum-version failure is actionable and the documented source
  edit/add/merge workflow works without legacy paths.
- [ ] Verify checks and documentation no longer instruct a new user to create
  `.venv-sync`, run setup-sync or install Stow for native dotfile deployment.

## Coordinator completion

### Execute the six-host retirement

- [ ] Build and verify the final consolidated native-only source in an isolated
  checkout first. Apply no deletion commit to a live checkout while its old
  updater/workers can still run. Coordinate publication with the fleet order.
- [ ] Recheck all six targets using existing access. Read the latest follow-up
  in fleet-rollout.md: Windows direct access was repaired and verified; lab
  self-SSH rejection does not block local access. Do not assume the planning
  snapshot still holds or that a reused master proves fresh login. Follow
  cluster rules and record specific access/allocation blockers.
- [ ] Quiesce reachable hosts before crossing the cutoff. Execute one final-source
  canary, then the other reachable unblocked hosts, with one owner per target and
  private recovery snapshots. Preserve current access until new access is proven
  or its site-constrained validation limitation is explicitly recorded.
- [ ] On each migrated host, verify config/secret consumer paths, preserved auth,
  applicable shell/app smoke, second apply and thin updater behavior. Retire exact
  obsolete links, tasks, helpers and sync environments only after replacement
  checks pass; preserve custom content, local commits and unrelated checkouts.
- [ ] Record host-by-host execution and exceptions in status.md. Do not leave
  otherwise executable host cleanup as instructions for the user. Unreachable
  hosts can remain explicit exceptions to source retirement, never false success.

### Close implementation and deployment records

Update `AGENTS.md` as the single source of active repository rules, README,
canonical docs, mirrored skills, CI and hook selection. Remove obsolete rules
instead of leaving Stow requirements beside native instructions. Preserve the
CLAUDE import stub and global agent-policy alignment.

Run all required local and native-platform checks, with e2e for setup changes.
Follow the repository's authorized exact-green-commit landing process. Inspect
the aggregate diff and deletion inventory; preserve unrelated local commits.

Record actual code/test reductions and every remaining custom helper's purpose.
Mark repository completion only when no supported configuration deployment path requires
TOMLKit, a sync venv or setup-sync, and the documented current-layout/tool boundary
and manual recovery procedure are valid. Do not report unknown old hosts as
migrated. Record the six-host rollout result separately, including all actual
retirement and blockers. Archive completed stage instructions while retaining any
outstanding host recovery tasks so a later session does not repeat finished work
or overlook a blocked host. Unrelated host cleanup remains outside D11.
