# Stage 6: Legacy retirement implementation plan

> **For agentic workers:** Start a fresh session with
> [start-stage-6.md](start-stage-6.md). Use subagent-driven-development with
> separate worktrees under `.worktrees/<task>/` and the protocol in
> [README.md](README.md). This is the canonical plan. It was verified read-only
> against `dddc718`; re-derive every `file:line` with `git grep -n` at the actual
> Stage 6 base and follow symbols and callers, never blind line ranges.

**Goal:** Remove the old Stow deployment and configuration-sync dependency chain,
leaving a complete native chezmoi workflow with no supported sync venv setup.

**Architecture:** Canonical portable files and policy live in native source state.
Temporary source bridges, legacy callers and their implementation-specific tests
are retired together. No continuing dual-manager support or migration service.

**Tech stack:** Chezmoi and the small integrations retained by Stage 5; existing
stdlib/platform behavior tests.

**Spec:** [Release invariant](README.md#release-invariant),
[retirement evidence](status.md#retirement-gate),
[support boundary](support-boundary.md), completed Stage 5 (its record in
[status.md](status.md)). Also follow [fleet rollout](fleet-rollout.md) and
[secrets and SSH](secrets-and-ssh.md).

**State:** Not started. Stage 5 landed on main as `b9f9d61..dddc718`; the
Windows host's Stage 5 login update and re-init are still pending (gate R3).

Notation: every `file:line` is at `dddc718`. **Confirmed** = seen in code at the
cited line; **Inference** = reasoned from code, not executed; **Uncertain** =
needs a probe or a decision. D-n are the open decisions below; A, B and C are
the phases of the ordered commit list.

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

### Repository gates

| # | Gate | State at `dddc718` |
| --- | --- | --- |
| R1 | Stage 5 integrated with exact-SHA gates | Done. Main `dddc718` (85 commits, 69 files, +3765/-2043 from `b9f9d61`, no force). Exact-SHA `ci.yml` run 41832666587 passed all three jobs (Linux behavior and lint, macOS system Bash, Windows native PowerShell); `bootstrap-e2e` run 41832666818 passed all seven hosts (five containers, mac and win runners). Local `tests/run.sh --ci` PASS; `pre-commit run --all-files` passed 39 hooks; `tests/run.ps1 -CI` runs only in CI |
| R2 | Stage 5 records on main | The status.md Stage 5 record and the migration records (inventory, stage-5-ecosystem, support-boundary, fleet-rollout, this plan, the Stage 6 prompt) land in the Stage 5 records commits. Confirm they are on main before Stage 6 edits the same files |
| R3 | Windows converged on Stage 5 | **Pending, user-run** (steps below). No Stage 6 breaking revision may reach win before it passes |
| R4 | Fresh-home native install procedure, documented and executable by an agent | **Open**; deliverable of A4. `step_H7_native_plan` (`lib/bootstrap/steps-human.sh:574-582`) and bootstrap.md H7-native/HW-native still defer to takeover.md, which converts existing Stow homes |
| R5 | Stow recovery bridge and cutoff documented | Present: `bf9995809ca7564c0728f87bcbefe91c8a3cc5e0` is the last supported Stow release and the first accepted native release (support-boundary.md, "Stage 4 candidate boundary"). B7 restates it in README |
| R6 | Isolation | Work only in `.worktrees/<task>/` worktrees or independent clones. Lab's `$HOME/dotfiles` main checkout is the bound native source of Lab's home and is shared with Codex: never edit, switch branches or leave it dirty (the native updater refuses a dirty source, `scripts/chezmoi-update.sh:57`). Worktrees under its `.worktrees/` do not dirty it: the path is ignored (`.gitignore:25`) and that status check does not list ignored paths |
| R7 | Landing authority | AGENTS.md "Workflows and checks": exact candidate on `ci/**` (and `e2e-ci/**`), every job green, then fast-forward `main`. The auto-mode classifier has required an explicit user confirmation for `main` pushes in earlier sessions; plan for it at the landing step |
| R8 | Decisions | D-1..D-17 answered by the user before the commits that depend on them |

Windows Stage 5 steps (R3). The user runs them from an ordinary, non-elevated
PowerShell 7; the administrator SSH channel never writes managed targets:

1. Two ordinary pwsh logins: the login updater moves the bound source from
   `7e344f2` to `dddc718` (or later main). Expected changed targets: 3
   (`profile.ps1`, Codex config, Claude settings).
2. Check that the staged `reinit-win.ps1` in Downloads has sha256
   `CED552AB2A4F8099CC5F7478A6CD4AFB7BEC7AF2FD2B4B85C42509A2F550A212`
   (`Get-FileHash`). After that session's login updater has finished and with no
   other chezmoi running, run `pwsh -NoProfile -File <path>\reinit-win.ps1`. It
   prints only hashes, owners, key names, booleans and nonsecret paths. It needs
   pwsh 7.2 or later (`#Requires -Version 7.2`; win has 7.6.9) and stops unless
   the source's `HEAD:home/.chezmoi.toml.tmpl` is blob `9e26214c` (`dddc718`'s),
   so R3 must run before any commit that changes that template reaches main.
3. Optional: `icacls <HOME>\.local\bin\chezmoi.exe /inheritance:d`, which keeps
   the file's current entries but stops later inheritance from `~/.local` (a
   propagated Codex sandbox Modify grant would make the updater refuse it).
   First run `icacls <HOME>\.local\bin\chezmoi.exe` and confirm that no entry
   names `CodexSandboxUsers`: `/inheritance:d` copies the inherited entries as
   explicit ones, so a grant already present would become permanent.
4. `.\doctor.ps1` (native): `native-config` ok.

The agent then records, read-only: revision, config sha256 before and after,
managed count, empty native status, and whether a Codex process was running.

### Fleet gates

Read-only, on each of the six targets, before Phase B reaches any host.
Sherlock: reread `/etc/agents/AGENTS.md` and its topic files through the user's
existing master first. Mutating native commands use the updater's full explicit
argument set (`scripts/chezmoi-update.sh:62-67`) plus `--exclude=dirs
--force=false`. After the Stage 5 re-init the config owns `persistentState`, so
plain read-only commands (`status`, `diff`, `managed`, `data`,
`execute-template`) no longer fork state; never run a plain mutating command.
That holds only on the five re-initialized Unix hosts: on win, until R3's
re-init passes (F11), even read-only commands need the full explicit argument
set, because a plain one reads and creates the default
`~/.config/chezmoi/chezmoistate.boltdb` instead of the bound state.

| # | Check | Expected |
| --- | --- | --- |
| F1 | `~/.config/dotfiles/native` | Regular file, exactly three LF lines: `dotfiles-chezmoi-v1`, canonical HOME, canonical source (`dotfiles_native_source`, `lib/chezmoi-guard.sh:53-69`) |
| F2 | `~/.config/dotfiles/maintenance` | Absent, except deliberately during a Phase C canary |
| F3 | Bound chezmoi version | 2.74.0 or later (the `.chezmoiversion` floor); record the actual version. Unix updaters run the chezmoi on PATH and Mac reuses its Homebrew chezmoi, which can move. Sherlock: static musl build; Windows: the private `~/.local/bin/chezmoi.exe` that `Test-BootstrapNativeChezmoi` accepts |
| F4 | `git -C <source> status --porcelain --untracked-files=all` | Empty |
| F5 | Source HEAD | The last green main |
| F6 | Native `status --exclude=dirs` | Empty |
| F7 | Native `managed --exclude=dirs` count | Lab 67, Mac 64, WSL 63, Sherlock 62, Marlowe 62 (Stage 5 after-state); Win 26 (Stage 4; recheck after R3) |
| F8 | `~/.claude/settings.json`, `~/.codex/config.toml` vs rendered output | Equal (private comparison; record only equal/not equal and key names) |
| F9 | `./doctor.sh` / `.\doctor.ps1` (native) | `native-config` ok; every other row as in the Stage 5 after-state. Lab exited 0 with 79 ok; the other hosts carry recorded pre-existing provisioning gaps, which are not Stage 6 blockers and must not be reported as regressions |
| F10 | `~/.config/chezmoi/chezmoistate.boltdb` | Absent (none on the five Unix hosts after Stage 5) |
| F11 | `persistentState` key in the bound config | Present (five Unix re-inits done; win pending, R3) |
| F12 | No unmarked home in use | The six targets are the whole supported fleet. Another clone found later is outside the boundary and is recorded, not repaired |

### Host residue

Inspection is read-only first. Remove only exact, identified, dotfiles-owned
residue under D11, after the host passes the post-Stage-6 acceptance, with a
private snapshot. Never recursively delete `.secrets`, credential stores, payload
repos, unmerged work or a checkout or module store with local commits.

| Residue | Where | Disposition |
| --- | --- | --- |
| `.venv-sync/` | `<source>/.venv-sync` (ignored, `.gitignore:55`); Win `.venv-sync\Scripts` | D11 permits exact retirement after its callers are gone. Lab's copy serves the legacy suites until B3. Keep the `.gitignore` line (D-8) |
| Legacy wrapper links | `~/.local/bin/{claude-settings-sync,codex-config-sync,codex-rules-sync}`; Lab `fcitx5-profile-sync` | They dangle once B3 deletes their targets. Remove only links whose `readlink` is exactly `<source>/common/{claude,codex}/.local/bin/<name>` or `<source>/lab-ubuntu/fcitx5/.local/bin/fcitx5-profile-sync` |
| Payload scheduler files | `${XDG_STATE_HOME:-~/.local/state}/dotfiles/payload/{ITEM.stamp,ITEM.failed,payload.log}`; Win `%LOCALAPPDATA%\dotfiles\payload\` | Ignored since Stage 5 (still present on hosts). List, then D-9 |
| Legacy receipts and locks | `<source>/.git/dotfiles-sync-unix` and its `.lock`; Win `<source>\.git\dotfiles-sync-windows\` | Invisible to `git status`. Inspect, then remove exact files only (D-9) |
| Retired submodule checkouts | `common/codex/coding-agent-kit/`, `common/coding-agent-kit/coding-agent-kit/`, `common/pymol/PyMOLScripts/`, `common/sherlock-kit/sherlock-kit/`, `.git/modules/*` | Never automatic. B5 removes tracked `common/`, git leaves these ignored directories, and `.gitignore:81-86` must stay or the updater's `--untracked-files=all` check refuses every login. Inspect `status` and `log --branches --not --remotes` before any person-approved removal |
| Historical kit links | `~/.local/bin/claude-as`, `codex-as` and completions into `common/coding-agent-kit/` (`config/payloads.tsv:42`) | The kit installer refuses them itself; after B4 dotfiles no longer pre-checks. Remove exact links only |
| Generated Codex override | `~/.codex/AGENTS.override.md` whose first line is the retired generator marker | Remove only exact-marker files; user overrides stay |
| Local Git filter | `filter.codex-portable` in `<source>/.git/config` | Remove that section only |
| `*.pre-dotfiles` files | HOME paths moved aside by old H7-stow `mv -n` | User data: leave |
| Windows restow task | `Dotfiles-Restow-<16 hex>`, disabled | Deregister before B2 reaches win (below) |
| Recovery evidence | Lab's private recovery store at `~/.local/state/dotfiles-chezmoi-migration-recovery/` (incl. the Stage 5 session archive `20261104-stage5-dddc718/`); Stage 4 private host backups; Stage 5 evidence under `~/.local/state/dotfiles-stage5-rollout/` and `~/.local/state/dotfiles-stage5-reinit/`; Marlowe `~/.local/state/dotfiles-marlowe-tmux-*` | Not residue: keep, with every historical manifest |

### Windows restow task

Confirmed (`scripts/dotfiles-auto-stow.ps1:57-65`): the name is
`'Dotfiles-Restow-' + first 16 hex of SHA256(UTF8(lower(GetFullPath(repo).TrimEnd('\','/')) + '|' + lower(UserProfile)))`.
Its action runs `<repo>\scripts\dotfiles-auto-stow.ps1 -Apply` with RunLevel
Highest (`:315-324`). Once B2 deletes that script, the disabled task would point
at a missing file inside a user-writable checkout.

Before B2 reaches win, while the script still exists: dot-source it without
switches in the bound checkout, take `Get-DotfilesTaskName -Repo <source>`, and
read the task's actions and principal. Require principal = the ordinary user,
RunLevel Highest, State Disabled, program = the MSI `pwsh.exe`, arguments naming
exactly `<source>\scripts\dotfiles-auto-stow.ps1 -Apply`; refuse on any mismatch.
Then `Unregister-ScheduledTask -TaskName <name> -Confirm:$false`. **Uncertain**:
whether the ordinary token may delete a task registered elevated. If not, give the
user the exact command for their own elevated pwsh; use the administrator SSH
channel only with the user's approval of that one command. Record name and result.

### Deliverables before the first deletion commit

1. The native fresh-home install procedure (R4), committed with A4.
2. Old-Stow-home recovery pinned to `bf99958` (support-boundary.md, takeover.md;
   README in B7).
3. Ported policy and repository invariants (A1), so no invariant lives only in a
   suite that B2/B3 delete.
4. Native e2e flows (A4) green on every bootstrap-e2e job.

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

Each item names the commits of the ordered list below that do it.

### Source consolidation

**Owner:** Source worker, exact subtrees allocated from the Stage 5 inventory.

- [ ] Materialize the native source's ordinary files from their canonical legacy
  content and remove temporary include/copy bridges. Preserve real templates only
  where machine differences require them. (B5)
- [ ] Move the canonical portable AI values into native source data/template
  locations. Keep one ownership definition and one policy value source. (A1, B5)
- [ ] Verify output parity before deleting old physical package paths. Retain
  intended shell override composition and native Windows applicability. (B5)
- [ ] Update tests that read `common/` directly to use native source or rendered
  fixtures. Preserve new tmux configuration and its stdlib metric runtime. (B5)

### Runtime and caller retirement

**Owner:** Runtime worker; coordinator integrates shared entrypoints/manifests.

Audit and remove each item only once no supported caller needs it:

- [ ] `stow-all.sh`, `stow-all.ps1`, `.stowrc`, normal symlink-trust helpers and
  retired auto-stow/update implementation selected for removal in Stage 5.
  Preserve the thin native login update adapter required by D6. (B2)
- [ ] Retired Sherlock/kit/PyMOL link repair, `filter.codex-portable` cleanup,
  generated-override repair, `scripts/awesome-skills-update.sh` and remaining old
  layout consumers/fixtures listed in `support-boundary.md`. Delete them with
  their old owners instead of porting them into chezmoi. Keep a short manual
  override-shadowing warning and old-host upgrade instructions. (B2 for the
  installer repairs, which live only in `stow-all.*`; B4 for the shim)
- [ ] `lib/config_sync.py`, `lib/sync-runtime.sh`, three AI sync wrappers and
  fcitx5 materialization helper. (B3)
- [ ] `setup-sync.sh`, `setup-sync.ps1`, `requirements-sync.txt`, sync-specific
  `.venv-sync` probes/setup, `DOTFILES_SYNC_PYTHON` support and old dependency rows.
  (B1, B3)
- [ ] Bootstrap S4/W1 branches and edges in `lib/bootstrap/steps-runtimes.sh`,
  `steps.sh`, `steps-human.sh`, `checks.sh`, `manifest.sh`, `lib/bootstrap.ps1`,
  `setup-host.*` and `doctor.*`, as they exist after Stage 5. (B1)
- [ ] Unconditional parser runtime checks in `tests/run.*`, fixture environment
  support, legacy sync tests, pre-commit hooks and all CI parser-provision steps.
  (A2, B3)
- [ ] Corresponding bootstrap fixtures/e2e steps, tool/document parity entries,
  obsolete docs and mirrored skill instructions. (A3, A4, B1-B4, B7)

Search active callers with `rg` across tracked sources, not ignored third-party
checkouts or real HOME. Historical migration documentation may mention retired
names; distinguish that from active runtime dependencies.

### Native-only verification

**Owner:** Independent verification worker; review deletion sets read-only.
The concrete plan is [Native-only verification plan](#native-only-verification-plan).

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

## Ordered commits

### Ordering constraints

Confirmed couplings:

- `scripts/dotfiles-update.sh:142` runs `stow-all.sh`;
  `scripts/dotfiles-auto-stow.ps1:233` runs `stow-all.ps1`; `stow-all.ps1:624`
  dot-sources `dotfiles-auto-stow.ps1`. Updaters and installers go together (B2).
- `stow-all.sh:133-166` and `stow-all.ps1:510-514` call the four wrappers; each
  wrapper sources `lib/sync-runtime.sh`, whose `:8-13` call
  `dotfiles_legacy_write_allowed` before running `lib/config_sync.py`. So B2
  (Stow) precedes B3 (parser), and the Unix legacy guard leaves with its last
  callers in B3.
- `S4-setup-sync` runs `setup-sync.sh` (`lib/bootstrap/steps-runtimes.sh:253-279`)
  and is selected only in legacy mode (`lib/bootstrap/steps.sh:85-86`): B1
  precedes deleting `setup-sync.*` in B3.
- Every e2e flow runs the legacy mode (`tests/e2e/lib/flow-unix.sh:21,170,216`;
  `steps.sh:44,71,102,196,206,232-240`; `steps.ps1:197,211,234,288,305`;
  `flow-win.ps1:135`): A4 precedes B1.
- `tests/test_chezmoi_codex.py:13-17` imports `CODEX_POLICY` and
  `CODEX_RETIRED` from `lib/config_sync.py`; policy invariants live only in
  `tests/ai-config-sync.sh` and repository invariants in
  `tests/windows-installer.sh`: A1 precedes B2/B3.
- B5 moves files the legacy installers enumerate: after B2/B3, so no commit has a
  half-working Stow path.

Each commit: tests first (RED, then GREEN where behavior changes), `pre-commit
run --all-files`, `tests/run.sh --ci`, a conventional message without AI
attribution, explicit `git add <paths>`. Until B3, `tests/run.sh` itself still
requires the parser runtime (`tests/run.sh:41-48`): reuse
`DOTFILES_SYNC_PYTHON=$HOME/dotfiles/.venv-sync/bin/python` read-only, never run
setup-sync or create a venv. From B3 on, run everything with it unset.

### Phase A: preparation (behavior-preserving; may land before the cutoff)

**A1 `test: keep AI policy and repository invariants in native suites`**

- New stdlib `unittest` file (D-12) porting, against the portable sources and a
  native-rendered fixture instead of a legacy live merge:
  `tests/ai-config-sync.sh:37-127` (exact portable `permissions.allow`, `ask`/`deny`
  shape, `defaultMode`, `autoMode.classifyAllShell` true at `:87`, both plugin IDs
  `agents-md@builtin` and `cc-plugin-agents-md@builtin` at `:106`, unsafe allow
  fragments absent, no portable `model`); `:301-310` (portable Codex rules with no
  `allow` or `forbidden` decision, no machine paths); `:311-320` (global
  `CLAUDE.md` and `AGENTS.md` differ only in the destructive-action bullets);
  `:322-343` (one identical, version-free "Stanford Sherlock" section);
  `:345-388` (no host-specific path in the portable Codex rules, routine
  commands absent, the required auto-review guardrails present; not `:390-392`,
  which grep `stow-all.sh`, `stow-all.ps1` and `.stowrc` and so would fail at
  B2); `:431-470` (installed-Codex exec-policy check, optional skip).
- Port from `tests/windows-installer.sh`: `:80-104` (Windows Terminal
  `settings.json`: strict JSON, ASCII, the Windows PowerShell and Command Prompt
  built-in profile stubs listed and hidden `:93-101`,
  `Windows.Terminal.PowershellCore` never disabled), `:111-114` (`CLAUDE.md`
  first line `@AGENTS.md`), `:116-140`
  (PowerShell parse gate for `doctor.ps1`, `setup-host.ps1`,
  `scripts/payload-update.ps1`, `scripts/chezmoi-update.ps1`, `lib/terminal.ps1`,
  `lib/chezmoi-guard.ps1`, `tests/terminal.ps1`, `tests/run.ps1`; drop files B2/B3
  delete).
- `tests/test_chezmoi_codex.py:13-17,43-52`: stop importing `lib/config_sync.py`;
  `home/.chezmoidata/codex-policy.json` becomes the single authority (D-4).
- Wire it: `tests/run.sh:87-111`, `tests/run.ps1`, a pre-commit hook selecting the
  portable policy files, `AGENTS.md`, `CLAUDE.md`, the Terminal settings and the
  test; the `need` map in `tests/test-entrypoints.sh:143-186`.
- RED evidence: mutate a copy (add an `allow` decision, drop one plugin ID,
  diverge the two guides) and see the new test fail.

**A2 `test: run non-parser suites without the AI-sync runtime`**

- `tests/run.ps1:56,70,74,95`: run `test_environment.py`, `test_ai_integration.py`,
  `test_bootstrap_manifest.py` and `test_payload_download.py` with plain `python`
  (keep `$syncPython` for `test_config_sync.py` `:59-64` and
  `test_stow_ignores.py` `:77-79` until B2/B3).
- `tests/doctor.sh:25-31` and `tests/ai-integration.sh:14-30`: drop the hard
  `.venv-sync` requirement (`tests/doctor.sh:25-26` says a stdlib Python
  suffices; `tests/test_ai_integration.py` imports neither `tomlkit` nor
  `lib/config_sync.py`); `tests/bootstrap-manifest.sh:19`: plain `python3`.
- Gate: these suites pass with `DOTFILES_SYNC_PYTHON` unset and no `.venv-sync`.

**A3 `test: make native the default mode of the bootstrap suites`**

- `tests/doctor.sh:311-313` (`DOCTOR_MODE=--legacy-stow`) and `:1291`;
  `tests/setup-host.sh:171-173` (`CASE_FLAGS=(--legacy-stow)`), `:236-243`
  (`run_native_case`) and `:2550-2552`; `tests/bootstrap.ps1:323`
  (`LegacyStow = $true` default).
- Mark every remaining legacy-only case so B1 deletes by marker. Native coverage
  that must exist afterwards: offline write-free doctor and `setup-host --check`,
  gh/tldr telemetry off, empty-home real-tool run, host from `[data].host`,
  `--host`/`--platform` precedence, step lists (STEPS_REGISTRY parity), HUMAN
  blocks, native `H2-alloc`, payload advice through the bound source's hook
  (`bootstrap_payload_hook`, `lib/bootstrap/checks.sh:525-537`).

**A4 `feat(e2e): drive the native install end to end`** (needs an `e2e-ci/**` run)

- Document the fresh-home native procedure (R4) in bootstrap.md H7-native and
  HW-native, cross-linked from takeover.md: seed `~/.config/chezmoi/chezmoi.toml`
  with only `[data] host = "<role>"`, reviewed umask; `init` with the explicit
  argument set (takeover.md "Initialize and establish one writer"); write the
  three-line marker privately; list `managed --include=dirs`, prepare only exact
  absent directories with reviewed `apply --include=dirs --recursive=false`
  (skip an empty list); `apply --exclude=dirs --force=false`; repeat; require an
  empty `diff --exclude=dirs`. Windows: unelevated argument array, closed stdin,
  `~\.local\bin\chezmoi.exe`.
- `tests/e2e/lib/flow-unix.sh`: replace the legacy check/apply loop/second apply
  (`e2e_step_check_nowrite` `:16-33`, `e2e_apply_loop` `:162-206`,
  `e2e_step_second_apply` `:211-228`) with native runs ending with only H7-native
  pending, a `native-handover` step that runs the documented commands in the
  sandbox HOME, a second nonforce apply, empty diff, `setup-host --check` exit 0,
  login shell, payloads through `sh scripts/payload-update.sh --now`, final doctor
  and `--smoke` without `--legacy-stow`, and the negatives
  (`tests/e2e/lib/steps.sh:218-252`) without the flag. `native-provision` and
  `native-check` (`steps.sh:113-139`, `flow-unix.sh:248-249`) become the main flow.
- `tests/e2e/lib/flow-win.ps1` (`Test-E2EStowed` `:16-30`, `Invoke-E2EStowBlock`
  `:32-79`, `:135`), `steps.ps1` (`:197,211,234`, the profile-symlink check
  `:249-264`, `:288,305`), `blocks.ps1` and `tests/e2e/run.ps1` (help `:13-24`,
  the HW-stow elevation requirement `:75-77`): same for HW-native. **Uncertain**:
  whether the hosted runner can drop to an ordinary token; if not, record the
  Windows e2e as elevated and keep the ordinary-token updater check in per-host
  acceptance.
- `tests/e2e/lib/flow-other.sh` (`e2e_step_setup_sync` `:114-116`,
  `e2e_skel_conflicts` `:123-138`, `e2e_step_stow_other` `:142-167`): D-1.
- Remove Stow expectations: `tests/e2e/lib/assert.sh` `e2e_stow_state` `:72-85`;
  `blocks.sh` `e2e_stow_line` `:84-104` and the `run-stow` policy in
  `e2e_block_policy`/`e2e_block_lines` `:164-232`; `steps.sh` `:44,67-77,102`,
  the common-only negative `:191-214`, the audit comment `:259` and
  `audit-stow-state` `:290-296`.
- Stow wrapper (D-11): `tests/e2e/wrappers/stow` (69 lines), Dockerfiles
  (`ubuntu.Dockerfile:46-48`, `ubuntu-lmod.Dockerfile:47-49`,
  `rocky-lmod.Dockerfile:40-42`, `fedora.Dockerfile:35-36`),
  `bootstrap-e2e.yml:136-146`, `tests/e2e/hosts/other.env:28`, `inside.sh:7,13,
  131-134,192`, `tests/e2e/README.md:59-60,94`. Keep the sudo/chsh wrappers and
  audits.
- `tests/e2e-harness.sh` / `.ps1`: rewrite the fixtures to the native flow.

### Phase B: deletion (each commit green; land in this order)

**B1 `refactor!: drop the legacy-stow mode from setup-host and the doctor`**

Unix code:

- `setup-host.sh`: header `:10-18`, usage `:45-53`, `BOOTSTRAP_LEGACY_STOW`
  `:133`, flag `:185-187`, host resolution `:226-249` (keep `--host` > native
  `[data].host` > exit 2; drop the `DOTFILES_HOST` and receipt branches
  `:240-245`).
- `doctor.sh`: header `:9-21`, help `:76-94`, `:143`, `:172-174`, host resolution
  `:208-251` (drop `:222-228` and `:242-247`; an unmarked home without
  `--host`/`--platform` keeps the "no host given" exit 2), mode filters
  `:302-303`.
- `lib/bootstrap/steps.sh`: rows `:48` (S4-setup-sync) and `:54` (H7-stow), mode
  filter `:85-86`, edges `:160-161,169-170`, rerun flag `:394`.
- `lib/bootstrap/steps-common.sh`: `steps_mode_flag` `:13-17` and its six
  callers (`steps-human.sh:23,56,203,276`, `steps-files.sh:137`,
  `steps-runtimes.sh:156`);
  P0-preflight legacy `why` `:395-399`; the `DOTFILES_DIR` warning `:386-388`
  (D-6).
- `lib/bootstrap/steps-runtimes.sh`: header `:3`, S4-setup-sync `:212-279`.
- `lib/bootstrap/steps-human.sh`: H2-alloc legacy branch `:173-183`; H7-stow
  `:284-414` (`steps_stowed`, `steps_stow_conflicts`, check, path prefix, plan);
  H7-doctor flag `:557`.
- `lib/bootstrap/checks.sh`: header `:18-19`, structural rows `:32-33` and the
  `path-order` doc ref `:35` (H7-native), `bootstrap_mode_structural_checks`
  `:42-55`, `bootstrap_sync_runtime_ok` `:483-490`, `bootstrap_check_venv_sync`
  `:492-514`, `bootstrap_physical_path` `:605-622` (only caller is stow-links),
  `bootstrap_check_stow_links` `:624-658`, dispatch `:800-801`.
- `lib/bootstrap/manifest.sh`: `bootstrap_mode_tool_rows` `:214-225` (only
  caller `doctor.sh:302`; setup-host filters through the step-registry mode
  filter `steps.sh:85-86` instead), Windows id map `:336-337`.
- `lib/bootstrap/platform.sh`: `bootstrap_host_env_empty` `:164-168`,
  `bootstrap_state_file` `:232-246`; reduce `bootstrap_recorded_common_only`
  `:248-267` and `bootstrap_resolve_host` `:269-304` to their native branches.

Windows code:

- `setup-host.ps1`: help `:7-9,24,32,47-48,57-59`, `-LegacyStow` doc and param
  (`:78`, `:99`), step lists `:115-122` (collapse to the native lists),
  `Get-SetupSyncPythonSpec` `:251-257`, `Test-SetupVenvReady` `:259-263`,
  W1-setup-sync check `:329-340` and apply `:599-620`, `Test-SetupStowed`
  `:345-371` (it reads `LinkTarget`, a .NET 6 API, so it is also one of the two
  PowerShell 7.2 dependencies), HW-stow/HW-auto-stow-task checks `:409-419` and
  blocks `:479-490`, mode branches `:454-458,507-508,557,687,751-752`.
- `doctor.ps1`: help `:8,20-26`, `-LegacyStow` doc and param (`:54`, `:75`),
  `$ReservedIds` `:106` (drop venv-sync, stow-links), `Get-DoctorSyncRuntimeResult`
  `:150-165`, `:203`, `:324`.
- `lib/bootstrap.ps1`: `Get-BootstrapVenvPython` `:580-588`,
  `Get-BootstrapSyncPython` `:590-597`, `Test-BootstrapSyncRuntime` `:599-610`;
  id map `:289-290` in `Get-BootstrapDocRef`.

Manifests: `config/bootstrap/tools.tsv` `stow` row `:48` and wording
`:19-20,24-26,35,46`; `config/bootstrap/brew/core.Brewfile:1,6`;
`config/bootstrap/hpc-login-env.yml:10,23`.

Tests (delete the cases A3 marked; no whole files yet): `tests/setup-host.sh`,
`tests/doctor.sh` (add "unmarked home, `DOTFILES_HOST` set, no `--host`: exit 2"),
`tests/bootstrap.ps1`, `tests/bootstrap-manifest.sh:431,437-438,448,451,565`,
`tests/test_bootstrap_manifest.py:39` (RESERVED_IDS),
`tests/test_chezmoi_provision.py:50-55,87-91`.

Docs in the same commit (step-heading, tool-ID and mirrored-skill parity hooks
require it): bootstrap.md S4-setup-sync `:1483-1520`, H7-stow `:1654-1718`,
W1-setup-sync `:1946-1965`, HW-stow `:1979-1998`, HW-auto-stow-task `:1999-2018`
deleted; "Native and legacy provisioning" `:34-51` and "Legacy quick start"
`:146-350` rewritten as a native quick start; contract tables `:351-517`
(`--legacy-stow`, `DOTFILES_HOST` rows); X-other-linux `:2097-2131` (D-1);
Phase 7 title `:1652`. Both mirrored `dotfiles-bootstrap` skills;
docs/dependencies.md legacy rows; AGENTS.md "Verification" and "Bootstrap and
doctor" bullets on `--legacy-stow`, `.venv-sync`, the receipt and `DOTFILES_HOST`.

**B2 `refactor!: retire the Stow deployment path and the legacy updaters`**

Delete: `stow-all.sh` (420), `stow-all.ps1` (629), `.stowrc` (45),
`lib/windows-link-trust.ps1` (101), `scripts/dotfiles-update.sh` (174),
`scripts/dotfiles-update.ps1` (44), `scripts/dotfiles-auto-stow.ps1` (340). The
historical repairs (retired links, `filter.codex-portable`, generated override)
live only in the two installers and go with them.

Edit:

- `common/sh/.profile` `_dotfiles_login_updates` `:118-155`: drop the unmarked
  fallback `:123-124`; an unmarked home runs no update (D-6). Keep
  maintenance-first, marker validation through the guard, the invalid-binding
  warning and the `chezmoi-update.sh` dispatch.
- `win/powershell/Documents/PowerShell/profile.ps1` tail `:318-366`: drop the
  `DOTFILES_DIR` branch `:348-350` and the `dotfiles-update.ps1` choice `:361`;
  comments `:322-323`; "stowed" wording `:1,281-282` and
  `WindowsPowerShell/profile.ps1:1` (changes rendered bytes; every host
  login-updates once).
- Comments in deployed files that name source paths: `profile.ps1:7,191,281,319`,
  `common/sh/.profile:23`, `sherlock/sh/.config/sh/.profile:83`. Rewrite them to
  target names (`~/.zshrc`) here, where rendered bytes change anyway; B5's
  rendered-parity gate allows no byte change.
- `lib/chezmoi-guard.ps1`: delete `Test-DotfilesLegacyWriteAllowed` `:43-64`.
- Delete tests: `tests/stow-all.sh` (810), `stow-ignores.sh` (20),
  `test_stow_ignores.py` (248), `unix-installer.sh` (516), `update-hooks.sh` (462),
  `update-hooks.ps1` (674), `windows-installer.sh` (144, after A1),
  `windows-installer.ps1` (528), `windows-installer-controls.ps1` (502).
- Edit tests: `tests/terminal.ps1:155-224` (logger cases load
  `dotfiles-auto-stow.ps1`, `stow-all.ps1` and `dotfiles-update.ps1`; re-point the
  logger contract at surviving consumers so `lib/terminal.ps1` keeps one);
  `tests/powershell-profile.ps1:128`; `tests/test_chezmoi_guard.py:43-82` (the
  unmarked home now runs no hook); `tests/test_chezmoi_takeover_unix.py:106-127,
  373`; `tests/test_chezmoi_takeover_windows.py:153-204,393-472` (legacy writer
  and stale-hook expectations only); `tests/test-entrypoints.sh:29-38` (CI
  requires stow), `:50` (Stow skip), `:91,97` (fixture Git isolation lists naming
  deleted suites), `:151,156-157,180,212`.
- Runners: `tests/run.sh:24,65-72,98-100,103,118-121`;
  `tests/run.ps1:77-79,89-92,106-108,140-147`.
- CI: `ci.yml:46` drops `stow` from apt (keep `tmux` and
  `DOTFILES_TEST_REQUIRE_TMUX=1` at `:18-21`); delete the brew stow step `:89-90`.
- Pre-commit: delete hooks `stow-installer` (`:150-156`), `stow-ignores`
  (`:157-162`), `unix-installer-integration` (`:163-169`), `windows-installer`
  (`:182-187`), `update-hooks` (`:194-199`); edit selectors naming
  `stow-all|dotfiles-update|dotfiles-auto-stow|.stowrc`: shfmt `:55,58`,
  chezmoi-native `:92`, terminal-output `:98`, ai-integration `:148`.
- `.gitignore:1-3`: the comment names `.stowrc` and `tests/test_stow_ignores.py`;
  rewrite it. Keep `:55` and `:74-86` (D-8).
- `docs/chezmoi-migration/inventory.md`: its reproducible check reads `.stowrc`
  (materialization exceptions); retarget or retire that assertion here.
- Docs: delete `docs/windows-installer.md` (81) and `docs/installer-contract.md`
  (38); `docs/update-contract.md` (123, D-7); README "Quick Start" legacy lines
  `:35-48`, "On Windows" `:69-73`, "Hosts and packages" `:101-105`, "Auto-update
  Hooks" `:125-134`; AGENTS.md "Stow and update scripts" `:140-154` (keep the
  `lib/terminal` bullet `:142`), the Stow bullets of "Windows" `:155-169`,
  including `:161` ("is a plain Stow symlink"), obsolete for native homes
  (natively a regular file since Stage 4) and true only of legacy Windows Stow.

Replacement coverage: native login dispatch stays in `tests/shell-profile.sh`,
`tests/powershell-profile.ps1`, `tests/test_chezmoi_guard.py` and the takeover
suites; the native updater in `test_chezmoi_takeover_{unix,windows,recovery}.py`
and `test_chezmoi_update_config.py`. Add "unmarked home: login runs no updater and
prints nothing" for sh, dash, bash, zsh and PowerShell if absent.

**B3 `refactor!: retire the AI-sync parser chain`**

Delete: `setup-sync.sh` (32), `setup-sync.ps1` (24), `requirements-sync.txt` (3),
`lib/sync-runtime.sh` (32), `lib/config_sync.py` (350),
`common/claude/.local/bin/claude-settings-sync` (33),
`common/codex/.local/bin/codex-config-sync` (33),
`common/codex/.local/bin/codex-rules-sync` (31),
`lab-ubuntu/fcitx5/.local/bin/fcitx5-profile-sync` (73).

Edit:

- `lib/chezmoi-guard.sh`: delete `dotfiles_legacy_write_allowed` `:12-51` and
  the "Temporary Stage 4" header `:2`.
- `tests/lib/environment.sh:7`, `tests/lib/environment.ps1:4`,
  `tests/test_environment.py:23`: `DOTFILES_SYNC_PYTHON` becomes an ordinary
  cleared `DOTFILES_` variable.
- Runners: `tests/run.sh:41-48,93-94,96-97` (keep `:95` `ai-integration.sh`,
  which A2 frees from the parser; the macOS job is the only one that runs its
  real fzf-tab preview case, `ci.yml:91-97`); `tests/run.ps1:25-33,59-64`.
- Delete tests: `tests/config-sync.sh` (20), `test_config_sync.py` (798),
  `codex-config-sync.sh` (414), `ai-config-sync.sh` (472, after A1),
  `fcitx5-profile-sync.sh` (128).
- Edit tests: `tests/test_chezmoi_guard.py:179-248` (legacy writer refusal)
  delete; `tests/test_chezmoi_integration.py:57-85` keeps the "native transforms
  never shell out" intent, with a poison on any interpreter on PATH replacing the
  `DOTFILES_SYNC_PYTHON` poison (`:64`) and the deleted wrapper paths
  (`:65-67`); `tests/test_chezmoi_source_state.py:97-113` and
  `tests/chezmoi_source_support.py:74,100-116` (category C and the 95 count);
  `tests/test-entrypoints.sh:142-146` and, as an edit, `:157-159` (drop only
  `lib/sync-runtime.sh` and `lib/config_sync.py`; the takeover suites on `:158`
  and `codex-policy.json` on `:159` stay).
- `config/bootstrap/apt/common.txt:19-20` (`python3-venv`, `python3-pip`), which
  docs/dependencies.md:18 ties to parser setup: drop them unless the caller
  re-derivation finds another consumer (for example pre-commit on a
  contributor host); record the outcome.
- `docs/chezmoi-migration/inventory.md`: remove the four C rows (`:97,103,104,
  145`); 95 -> 91 tracked rows; per-role package paths 52/59/58/63/57/57/29 ->
  49/56/55/59/54/54/26 (now equal to the native totals); six executable modes ->
  two; update the reproducible check in the same commit (the parity tests
  otherwise fail on missing paths).
- CI: the three "Provision pinned configuration parser explicitly" steps
  (`ci.yml:47-48,98-99,123-124`).
- Pre-commit: delete hooks `structured-config-sync` (`:111-121`),
  `ai-config-sync` (`:122-128`), `codex-config-sync` (`:136-142`),
  `fcitx5-profile-sync` (`:170-175`); selectors: shellcheck `:46` and shfmt
  `:58` (`/\.local/bin/[^/]+-sync$`), shfmt `:55,58` (`setup-sync`,
  `sync-runtime`), chezmoi-native `:92` and doctor `:211`
  (`config_sync`, `sync-runtime`).
- Docs: docs/config-sync.md `:102-315` (legacy path, provisioning, helper API,
  legacy cleanup, file safety; rewrite "Merge ownership" `:192-240` to point at
  `home/.chezmoidata/codex-policy.json`; keep a short manual note on generated
  `AGENTS.override.md` from `:241-253`), keeping `:1-101` (native) and `:316-343`
  (permission policy rationale, linked from AGENTS.md); docs/dependencies.md "Is
  a venv necessary?" and parser rows; README `:151-163,229`; AGENTS.md `:26`
  ("sole exception ... tomlkit"), `:35` (setup-sync), "AI assistant
  configuration" `:106-134` legacy bullets; tests/COVERAGE.md.
- `common/claude/.claude/settings.json:168-169`: autoMode prose names "GNU Stow
  link target" and `.venv-sync` (D-10; a separate reviewed commit that a human
  applies; rendered Claude settings change on every host).

**B4 `refactor!: end the Stage 5 payload transition`**

- `scripts/payload-update.sh`: transition comment `:14-18`; maintenance and
  no-`--now` branches `:20-28` (D-5: a call without `--now` becomes an error;
  when sourced, `return 2` with one stderr line, no leaked options or variables,
  never `exit` the caller's shell); delete `stowed()` `:183-198` and its use
  `:204-207`.
- `scripts/payload-update.ps1`: help `:18-19`; params `-Auto` `:28`, `-Worker`
  `:30` (binding errors once removed); `:44-45` no-op -> error; stow-links block
  `:164-173`.
- `config/payloads.tsv`: `stow-links` doc `:23-26` and row `:42`.
- `lib/bootstrap/checks.sh` `bootstrap_check_payloads` `:539-603`: drop the
  `links` parsing and advice (`:542-543,546,557,561,564-572`); the dispatch `:807`
  no longer passes HOST. Keep `bootstrap_payload_hook` `:525-537` (Stage 5's
  bound-source advice).
- `doctor.ps1` `Get-DoctorPayloadResult` `:208-261`: drop `:211-212,240-247`.
- Delete `scripts/awesome-skills-update.sh` (6) and its references:
  `.pre-commit-config.yaml:55,58,181`; `tests/test-entrypoints.sh:147`;
  `tests/payload-update.sh:47,181-227` (shim and transition cases become error
  cases; keep "sourcing leaks nothing").
- Inert `DOTFILES_PAYLOAD_AUTO_UPDATE` export: `setup-host.sh:339`,
  `setup-host.ps1:725,730`, `lib/bootstrap/checks.sh:872`, `tests/doctor.sh:106-107,
  783`, `tests/setup-host.sh:381,1007`, `tests/test_chezmoi_provision.py:30`,
  `tests/e2e/lib/assert.sh:188`, `steps.sh:32`, `steps.ps1:112`, `AGENTS.md:92`,
  both skills (`:22`/`:23`), docs (bootstrap 12 lines, payloads 2, testing 2,
  shell 1).
- Tests: `tests/payload-update.sh:311-320` (stow-links refusal),
  `tests/payload-update.ps1:61-67,300-317`, the stow-link advice cases in
  `tests/doctor.sh` near `:888` and in `tests/bootstrap.ps1`, `tests/e2e-harness.sh`.
- Docs: docs/payloads.md transition and migration sections; AGENTS.md `:138`
  ("Until Stage 6 other calls are quiet no-ops", the stow-links clause) and
  `:153` (shim, `.stowrc` lines).
- `DOTFILES_DIR` fallback of `sync-payloads` (`common/sh/.aliases:25-46`, `:26`;
  `profile.ps1:243-278`, `:261`): D-6.

**B5 `refactor: materialize the native source and remove the Stage 2 bridges`**

- 65 one-line bridges (Confirmed: `git grep -l 'include (joinPath
  .chezmoi.workingTree' -- 'home/*.tmpl'`): 59 literal includes are replaced by the
  canonical legacy file moved with `git mv` to the native name without `.tmpl`,
  keeping attributes (`executable_`, `empty_`, `private_`). Confirmed:
  `common/kitty/.config/kitty/kitty.conf` (22 lines) and
  `win/oh-my-posh/.config/oh-my-posh/prompt.omp.json` (18 lines) contain `{{`;
  they must stay plain, non-template files.
- 6 host-variant bridges (`include (joinPath .chezmoi.workingTree .host ...)`,
  28 inputs: bash rc x5, `sh/.aliases` x5, `sh/.profile` x5, `zsh/.zshrc` x5,
  `.gitconfig_local` x4, `ssh legacy.conf` x4) keep a role-keyed literal include
  from a new layout (D-2).
- 2 AI policy inputs (`common/claude/.claude/settings.json`,
  `common/codex/.codex/config.toml`) move once (D-3); retarget
  `home/dot_claude/modify_private_settings.json:28` and
  `home/dot_codex/modify_private_config.toml:11`. Rendered Codex and Claude
  output must stay byte-identical (see Risks: Codex write-back race).
- 2 raw duplicates deleted: `common/codex/.codex/pets/tom/spritesheet.webp`
  (1,934,566 bytes) and `sherlock/terminfo/.terminfo/t/tmux-256color` (3,426
  bytes); Confirmed byte-identical to `home/dot_codex/pets/tom/spritesheet.webp`
  (sha256 `78179015...`) and `home/dot_terminfo/t/tmux-256color` (`55808427...`).
- `.gitattributes:10-11`: move `-text` from `win/wsl/.wslconfig` (`i/crlf`) and
  `win/wsl/mount.vbs` (`i/mixed`) to their new paths in the same commit; verify
  with `git ls-files --eol` before and after.
- `.pre-commit-config.yaml`: top-level exclude `:2`, whitespace/EOF excludes
  `:13,15`, and every surviving hook `files:` naming `common/` or a host
  directory (after B2/B3: `:92,104,110,134,148,181,193,230`);
  `tests/test-entrypoints.sh` need-map and check-json/toml paths.
- Surviving tests that read legacy package paths (`git grep -c -E
  '(^|[^A-Za-z_/.-])(common|mac|sherlock|wsl-ubuntu|lab-ubuntu|marlowe|win)/[A-Za-z._]'`
  at `dddc718`): `test_chezmoi_guard.py` 8, `setup-host.sh` 8,
  `test-entrypoints.sh` 7, `test_chezmoi_source_state.py` 7, `doctor.sh` 6,
  `test_tmux.py` 5, `powershell-profile.ps1` 5, `e2e-harness.ps1` 5,
  `test_portable_shell.py` 4, `shell-profile.sh` 4,
  `test_chezmoi_takeover_unix.py` 3, `test_chezmoi_integration.py` 3,
  `test_ai_integration.py` 3, `bootstrap.ps1` 3, `test_chezmoi_codex.py` 2,
  `host-overlays.sh` 2, `bootstrap-manifest.sh` 2,
  `test_chezmoi_takeover_windows.py` 1, `test_chezmoi_claude.py` 1,
  `payload-update.sh` 1. The same command also hits `tests/e2e/lib/flow-win.ps1`
  1 (`Test-E2EStowed`, which A4 removes) and `tests/e2e/docker/site/marlowe.sh`
  1 (a comment, listed below), plus suites B2/B3 delete. Path joins built from
  parts and tree names alone are not counted: grep for the tree names as well
  (for example `chezmoi_source_support.py` `TREES`/`ROW`, below).
- `docs/chezmoi-migration/inventory.md` and `tests/chezmoi_source_support.py`
  (`TREES` `:17`, `ROW` `:21` and its parser `:42-43`): D-13. Role totals
  49/56/55/59/54/54/26 must not change.
- `lib/bootstrap/checks.sh` `BOOTSTRAP_RC_FILES` `:127-135` and
  `bootstrap_check_rc_pollution` `:717-758` scan `common/` sources: D-14.
  Comments: `lib/bootstrap/manifest.sh:130`, `steps-runtimes.sh:27`,
  `steps-guard.sh:6`, `checks.sh:516`, `config/bootstrap/git-clones.tsv:8`,
  `config/bootstrap/tools.tsv:22`, `config/bootstrap/apt/lab-ubuntu.txt:2`,
  `tests/e2e/docker/site/marlowe.sh:6` (comments in deployed files belong to B2).
- `home/.chezmoiignore:9` comment; `home/.chezmoi.toml.tmpl:1` keeps its
  working-tree `includeTemplate` of `validate-host` (not a legacy path; change it
  only if the source root moves).
- AGENTS.md "Scope and layout" `:6-14`, shell/Git/SSH convention paths, "AI
  assistant configuration" package list, the oh-my-posh path, the `.gitattributes`
  note; README layout section.
- Gate: rendered parity. For each role and enrollment on/off, `managed`, every
  target's rendered bytes and modes are identical between the parent and this
  commit (a one-off script over both revisions plus `test_chezmoi_source_state.py`
  and `test_chezmoi_rendered.py`). Windows CI covers the CRLF files.

**B6 `fix: close the remaining binary and floor findings`** (optional; D-15)

Stage 5 already did the Windows part of the draft item: W1-chezmoi readiness
(`setup-host.ps1:323`) and the doctor's `native-config` row (`doctor.ps1:178`)
apply the updater's exact-exe trust check through `Test-BootstrapNativeChezmoi`
(`lib/bootstrap.ps1:716`), with the helpers in `lib/chezmoi-guard.ps1:105-164`.
The earlier "W1-chezmoi needs PowerShell 7.1" claim was false and its gates are
gone; the pwsh floor stays 7.0. What remains: the profile sets `$PSStyle`
(PowerShell 7.2+) unguarded (`profile.ps1:169`), and Unix
`step_S4_chezmoi_check` (`lib/bootstrap/steps-archives.sh:245-265`) and
`scripts/chezmoi-update.sh:39` (`command -v chezmoi`) accept a PATH chezmoi by
design. `Test-SetupStowed`'s `LinkTarget` use leaves with B1.

**B7 `docs: close Stage 6`**

- README, AGENTS.md (drop every "until Stage 6" clause and the Stow/legacy rules;
  it is 27,982 of 28,000 bytes now), docs/testing.md, tests/COVERAGE.md,
  docs/shell.md, docs/payloads.md, docs/sherlock-kit.md (D-7),
  docs/dependencies.md.
- Migration records: status.md Stage 6 record (stage completion template), stage
  table, retirement gate; this plan's checkboxes; support-boundary.md "executed";
  inventory.md header; archive `start-stage-*.md` while keeping outstanding host
  recovery tasks visible.
- Optional repository test that retired names appear only under
  `docs/chezmoi-migration/**` and the kept `.gitignore` residue lines (D-12).

### Phase C: fleet rollout and residue retirement

1. Build and verify the final aggregate in an isolated clone (R6); run the local
   verification below; push the exact SHA to `ci/**` and `e2e-ci/**`; wait for
   all three `ci.yml` jobs and every `bootstrap-e2e` job.
2. Windows task: deregister it (above) while the old script still exists on win.
3. Quiesce and canary (D-16): create `~/.config/dotfiles/maintenance` on the five
   remote hosts, fast-forward `main` (R7), update Lab first and verify, then
   remove maintenance host by host with verification; restore it on failure.
   Updates are fast-forward only and nonforce, through the login updater or the
   full explicit argument set with `--exclude=dirs --force=false`.
4. Per host: the acceptance below, then exact residue retirement (private
   snapshot first), then the status.md record (revision before/after, checks,
   removed residue, blockers).
5. Delete the `ci/**` and `e2e-ci/**` branches; remove the Stage 6 worktrees
   after integration (global rules).

## What must be kept

| Keep | Why |
| --- | --- |
| `home/` native source, `.chezmoiroot`, `.chezmoiversion` (2.74.0), `home/.chezmoi.toml.tmpl` (`persistentState`, ff-only update contract, case-insensitive key dedupe), `home/.chezmoiignore`, `home/.chezmoitemplates/validate-host`, `home/.chezmoidata/codex-policy.json`, the two modify templates, encrypted `home/private_dot_secrets/*.age` | The native engine (D1, D3, D12, D13) |
| `lib/chezmoi-guard.sh` (`dotfiles_native_owned`, `dotfiles_maintenance_active`, `dotfiles_native_source`) and `lib/chezmoi-guard.ps1` (marker, maintenance, binding, `Test-DotfilesNativeChezmoiPath`, `Test-DotfilesTrustedFileSecurity`, `Open-DotfilesNativeChezmoi`) | Binding, maintenance and Windows binary trust used by profiles, updaters, doctor and setup-host |
| `scripts/chezmoi-update.sh` / `.ps1` | D6 thin login updater: bounded, ff-only, clean source, `--exclude=dirs --force=false --less-interactive --no-tty --error-on-conflict`; Windows runs only the private `~/.local/bin/chezmoi.exe` on a held handle (residual junction-swap window narrowed, not closed) |
| Native profile dispatch: `_dotfiles_login_updates` (native branch), `common/zsh/.zshrc:258-259`, the PowerShell tail (native branch) | D6 |
| Explicit payloads: `--now`/`-Now`, `sync-payloads`/`sync-skills` bound to the validated source, maintenance refusal, bounded private staging, no pipe-to-shell, busy 75 / person / failure results, platform and channel selection, `config/payloads.tsv` minus `stow-links`, `bootstrap_payload_hook` | D7 explicit-only; CI installs the kit with `sh scripts/payload-update.sh --now kit` (`ci.yml:34,80`) |
| Native doctor/setup-host: S4-chezmoi/W1-chezmoi, H7-native/HW-native, `native-config` (stray-DB warn, Windows binary check), `bootstrap_native_host`, offline and write-free guarantees, telemetry suppression, bat theme, nvm, fonts, Brew conflict handling, native `H2-alloc` | Stage 5 results |
| `lib/bootstrap/steps-guard.sh`; rc-pollution check (D-14) | Stage 5 kept both as cheap tripwires; after Stage 6 the checkout-unchanged invariant has no `.venv-sync` exception |
| `.gitignore:55` and `:74-86` | Residue guards (D-8) |
| `.gitattributes` CRLF rules (retargeted in B5) and `*.age -text` | Byte parity |
| `.gitleaks.toml` covering the native `[attribute_]dot_secrets` encoding (only the eight approved Claude age ciphertexts allowlisted) | Secret scanning |
| No-externals and no-submodule tests (`tests/test_chezmoi_source_state.py:57-73`) | Stage 5 invariants |
| tmux floor 3.4 (`tools.tsv:34`, `hpc-login-env.yml:24`), Linux CI apt `tmux` and `DOTFILES_TEST_REQUIRE_TMUX=1` | A missing or old tmux fails CI instead of skipping |
| Native suites (`tests/chezmoi.*`, `chezmoi-takeover.*`, every `test_chezmoi_*.py`, `chezmoi_support.py`, `chezmoi_source_support.py`) and behavior suites (shell, tmux, PowerShell, terminal, AI integration, payload, doctor, setup-host, bootstrap, e2e) | Coverage, retargeted, not deleted |
| Historical stage docs in `docs/chezmoi-migration/` | Record; may mention retired names |
| Recovery evidence (Host residue table) and `bf99958` as the Stow recovery bridge | Recovery |
| docs/config-sync.md `:316-343` permission policy rationale; root `CLAUDE.md` stub; both Claude plugin IDs | Linked from AGENTS.md; unrelated client contract (A1 tests it) |

## Native-only verification plan

### Local, in a fresh clone

1. Fresh `git clone` of the candidate; no `.venv-sync`; `env -u
   DOTFILES_SYNC_PYTHON`. No tracked file outside `docs/chezmoi-migration/` may
   name a retired mechanism; this returns only reviewed hits: `.gitignore:55`;
   kept native negative assertions unless their commits drop them
   (`tests/test_chezmoi_source_state.py:113`,
   `tests/test_chezmoi_native_config.py:21`,
   `tests/test_chezmoi_integration.py:62`, the `DOTFILES_SYNC_PYTHON` poison in
   `tests/test_chezmoi_provision.py:31`); the D-12 retired-name test and the A4
   e2e `.venv-sync` audit; D-10 prose if kept; `DOTFILES_DIR` only where D-6
   keeps it:

   ```sh
   git grep -n -E 'tomlkit|config_sync|sync-runtime|DOTFILES_SYNC_PYTHON|DOTFILES_DIR|setup-sync|venv-sync|stow-all|dotfiles-update|dotfiles-auto-stow|awesome-skills-update|stow-links|legacy-stow|LegacyStow|BOOTSTRAP_LEGACY_STOW|DOTFILES_AUTO_STOW|DOTFILES_PAYLOAD_AUTO_UPDATE|dotfiles-sync-(unix|windows)|windows-link-trust|requirements-sync' -- ':!docs/chezmoi-migration'
   ```

2. `git grep -n 'joinPath .chezmoi.workingTree' -- home` returns only the D-2/D-3
   includes and `validate-host`; none names `common/` or a host directory.
3. `/bin/bash tests/run.sh --ci` (chezmoi through
   `.github/scripts/install-test-chezmoi.py` or `DOTFILES_TEST_CHEZMOI`), with no
   "AI-sync runtime" or "stow" prerequisite.
4. `pre-commit run --all-files`; `pre-commit run --hook-stage manual
   gitleaks-history`.
5. `tests/test-entrypoints.sh`: every runner suite has a hook and every need-map
   path selects its hook.
6. Mutation spot checks: A1 policy mutations fail; deleting a materialized file
   fails `test_chezmoi_source_state`; changing one byte in the WSL config fails
   rendered parity.

### CI on three OSes

`ci.yml` on `ci/**`: Linux (full pre-commit with behavior hooks; apt `tmux`
without `stow`; `DOTFILES_TEST_REQUIRE_TMUX=1`; no parser step), macOS
(`/bin/bash` 3.2 `tests/run.sh --ci`; no brew stow), Windows (`tests/run.ps1 -CI`
without the sync interpreter). Record the run and job IDs. Mac tmux 3.8
adversarial-menu failures are a recorded baseline and the macOS job installs no
tmux; do not report them as fixed.

### End to end on native flows

`e2e-ci/**`, every bootstrap-e2e job. Per Linux container host (lab-ubuntu,
wsl-ubuntu, sherlock, marlowe; other per D-1), mac and win: initial doctor
(native, no writes), `setup-host --check` (no writes), apply loop to only
H7-native/HW-native pending, documented native handover in the sandbox HOME,
second nonforce apply, empty diff, `setup-host --check` exit 0, clean login
shell, payload install through `--now`, final doctor and `--smoke`, negatives,
audits (sudo/chsh only where allowed; nothing installs Stow; `.venv-sync` never
created; checkout unchanged). Windows registers no scheduled task (keep the
task-identity snapshot).

### Per-host acceptance after the update lands

For each host separately (Sherlock and Marlowe through existing masters, site
rules first):

1. F1-F12 again on the post-Stage-6 revision; managed counts unchanged from F7;
   native `status` and `diff --exclude=dirs` empty.
2. Both AI configs equal rendered output (private; equal/not equal and key names).
3. Doctor with no `venv-sync` or `stow-links` rows at all; `native-config` ok;
   other rows unchanged from the Stage 5 after-state.
4. A fresh interactive login runs the native updater once, with no stderr
   warning (win: an ordinary pwsh run by the user); maintenance absent afterwards.
5. Shell smoke: `zsh -ic true`, `bash -ic true`; on win PowerShell 7 and 5.1
   profile load.
6. Win: `Get-ScheduledTask -TaskName 'Dotfiles-Restow-*'` returns nothing.
7. Exact residue retirement, then 1-3 again.

## Measured sizes at `dddc718`

Method: `wc -l`; category totals with `git ls-files -z -- PATHS | xargs -0 grep
-IlZ '' | xargs -0 wc -l` (text files only). Partial-edit figures are measured
ranges, not predicted diffs; report the actual Stage 6 delta with `git diff
--numstat <base>..HEAD` by category, and moves with `git diff -M --stat`, never
as deletions.

| Area | Lines | Files |
| --- | ---: | ---: |
| All tracked text (391 tracked files) | 64,218 | 385 |
| `tests/**` | 29,621 | 116 |
| of which `tests/e2e/**` | 4,489 | 35 |
| Docs (`docs/**`, root `*.md`, `.claude/**`, `.agents/**`) | 12,202 | 36 |
| of which `docs/chezmoi-migration/**` (kept) | 6,741 | 20 |
| Root entrypoints (doctor, setup-host, setup-sync, stow-all; both shells) | 3,067 | 8 |
| `lib/**` | 6,646 | 21 |
| `scripts/**` | 1,238 | 8 |
| Legacy package trees (`common/` and six host directories), text | 9,424 | 91 (+2 binary, +2 empty = 95 tracked) |
| `home/` | 622 | 79 text (81 tracked) |

Whole-file code deletions, 2,370 lines in 17 files: Stow deployment 1,195
(`stow-all.sh` 420, `stow-all.ps1` 629, `.stowrc` 45, `lib/windows-link-trust.ps1`
101); parser chain 441 (`setup-sync.sh` 32, `setup-sync.ps1` 24,
`requirements-sync.txt` 3, `lib/sync-runtime.sh` 32, `lib/config_sync.py` 350);
wrappers 170 (33, 33, 31, 73); legacy updaters and shim 564
(`dotfiles-update.sh` 174, `.ps1` 44, `dotfiles-auto-stow.ps1` 340,
`awesome-skills-update.sh` 6).

Partial code removals (measured ranges, roughly 800 lines in total):
`steps-human.sh` H7-stow 131 and H2-alloc branch 11; `steps-runtimes.sh`
S4-setup-sync 68; `checks.sh` venv-sync 32, physical-path and stow-links 54,
payload stow-links about 12, structural/mode/dispatch about 20; `platform.sh`
about 55; `steps.sh`, `steps-common.sh`, `manifest.sh` about 35; guards 40 (sh)
and 22 (ps1); `lib/bootstrap.ps1` 33; `setup-host.ps1` about 120; `doctor.ps1`
about 40; `doctor.sh` about 35 and `setup-host.sh` about 25; payload twins about
45; profiles and aliases 10-20 (D-6); manifests `tools.tsv` 1 row plus wording,
`core.Brewfile` 1, `hpc-login-env.yml` 2, `payloads.tsv` 5.

Source consolidation: 65 bridge files (65 lines) go; 6 role-keyed includes
survive (D-2), so about 59 lines net; 2 binary duplicates (1,934,566 + 3,426
bytes); the other 89 package files (about 9,250 text lines) are renames.

Tests: whole-file legacy suites 5,333 lines in 14 files (`stow-all.sh` 810,
`stow-ignores.sh` 20, `test_stow_ignores.py` 248, `config-sync.sh` 20,
`test_config_sync.py` 798, `codex-config-sync.sh` 414, `fcitx5-profile-sync.sh` 128,
`update-hooks.sh` 462, `update-hooks.ps1` 674, `unix-installer.sh` 516,
`windows-installer.sh` 144, `windows-installer.ps1` 528,
`windows-installer-controls.ps1` 502, `e2e/wrappers/stow` 69), plus
`ai-config-sync.sh` 472 after A1 (the port adds back an uncertain 150-250).
Mixed suites, lines matching `legacy|stow|setup-sync|venv-sync|DOTFILES_HOST|
receipt|dotfiles-sync-` (case-insensitive) over file size: `setup-host.sh`
187/2,637, `e2e-harness.ps1` 167/1,226, `e2e-harness.sh` 157/1,227,
`bootstrap.ps1` 130/1,870, `doctor.sh` 72/1,537, `test_chezmoi_provision.py`
23/311, `bootstrap-manifest.sh` 14/756, `test_chezmoi_takeover_windows.py`
13/762, `test_chezmoi_guard.py` 4/252; e2e libraries `flow-win.ps1` 28,
`steps.sh` 27, `blocks.sh` 25, `assert.sh` 19, `flow-other.sh` 17,
`blocks.ps1` 12, `steps.ps1` 11. Report their numstat afterwards.

Docs: whole-file candidates 281 (`windows-installer.md` 81,
`installer-contract.md` 38, `update-contract.md` 123 and `sherlock-kit.md` 39 per
D-7); config-sync.md legacy sections 214; bootstrap.md legacy step sections 163
(S4-setup-sync 38, H7-stow 65, W1-setup-sync 20, HW-stow 20, HW-auto-stow-task
20) and the "Legacy quick start" 205 (rewritten, not only deleted);
dependencies.md "Is a venv necessary?" 17. Lines matching the pattern above plus
`DOTFILES_PAYLOAD_AUTO_UPDATE`: bootstrap.md 236, testing.md 78, AGENTS.md 39,
payloads.md 37, config-sync.md 30, README 26, dependencies.md 20, COVERAGE 19,
update-contract.md 18, shell.md 9, each skill 8, sherlock-kit.md 5.

Context, Stage 5 audit categories (`b9f9d61` -> `dddc718`): root entrypoints
3,006 -> 3,067; `lib/` 6,370 -> 6,646; `scripts/` 1,437 -> 1,238; shell,
PowerShell and Python outside tests 11,435 -> 11,603; tests 28,490 -> 29,621;
docs 11,807 -> 12,202; all tracked text 62,496 -> 64,218.

## Risks

1. **Unmarked homes break on pull (accepted under D9).** A Stow home whose old
   updater pulls B2/B5 loses its link targets. The six targets are native;
   recovery for others is from `bf99958` (support-boundary.md).
2. **Untracked-residue stall.** Removing `.gitignore` residue lines while hosts
   keep `.venv-sync` or retired checkouts makes the updater's
   `--untracked-files=all` check refuse every login (`scripts/chezmoi-update.sh:57`).
   Keep the lines (D-8).
3. **Windows not converged.** Crossing the breaking revision on win before R3
   leaves its Stage 5 re-init and updater acceptance unproven under new code.
4. **Dangling privileged task** on win if B2 lands before deregistration.
5. **Rendered drift from consolidation.** Lost `-text` on the WSL files, an
   accidental `.tmpl` on `kitty.conf` or `prompt.omp.json`, or lost attributes
   change deployed bytes or modes. Mitigation: B5's parity gate,
   `git ls-files --eol`, Windows CI.
6. **Codex write-back race.** A Codex app-server that starts just before an
   update writes its in-memory `~/.codex/config.toml` back and stops the
   nonforce update at MM. Any commit that changes rendered Codex config can meet
   it; B5's policy move must render identical bytes. If it does not, ask the user
   to quit Codex clients first and use takeover.md "Reconcile an owned AI-config
   key", never a routine force.
7. **Coverage loss** if a legacy suite goes before its invariants are ported:
   policy (`ai-config-sync.sh`), Terminal JSON and the `CLAUDE.md` stub
   (`windows-installer.sh`), the logger contract (`terminal.ps1` cases loading
   legacy scripts), Codex ownership (`test_chezmoi_codex.py`). A1/B2 handle them;
   review with tests/COVERAGE.md.
8. **Policy prose change propagates** (D-10): rendered Claude settings change on
   every host.
9. **Big-bang landing.** Land the A commits first; keep B commits atomic and in
   order; one `ci/**` run per checkpoint.
10. **Pre-existing doctor gaps mistaken for regressions** (missing tmux plugin
    clones, login-env packages): compare with the Stage 5 after-state.
11. **e2e common-only gap**: the `other` flow deploys with by-hand setup-sync and
    a host-less `stow-all.sh`; after Stage 6 it needs D-1.
12. **Windows token limits**: the task deregistration may need the user's
    elevated pwsh. The Windows chezmoi.exe DACL is inherited; a propagated Codex
    sandbox grant from `~/.local` would make the updater refuse it (the doctor now
    shows it); recheck before the canary.
13. **Lab shared checkout**: Lab receives Stage 6 only through its updater or an
    explicit native update after `main` moves.
14. **Host tooling**: no `cp -p` on Marlowe's filesystem (it cannot preserve
    permissions and ACLs); a script sent over ssh must not assume `$0` is a file.
    Marlowe non-interactive shells (`ssh marlowe-plain`) find `/usr/bin/tmux`
    3.2a, below the floor; only the login env has 3.6a.

## Open decisions

Ask the user these, with the recommendations, before the commits that need them.

| ID | Decision | Options (recommendation first) |
| --- | --- | --- |
| D-1 | Common-only ("other" Linux) after Stage 6 | (a) Document a by-hand native route (fetch the pinned chezmoi with `fetch_pinned`, init with `[data].host = "common-only"`) and keep the e2e `other` host on it; (b) `--host common-only` in setup-host; (c) drop common-only support and the e2e `other` host. Recommended (a): smallest, no new setup-host mode |
| D-2 | Layout for the 6 host-variant targets (28 files) | (a) `hosts/<host>/<target-path>` at the repository root with 6 role-keyed literal-include `.tmpl` files (the tested working-tree mechanism); (b) a dot-directory inside `home/` with relative `include` (needs a v2.74.0 probe; Uncertain); (c) keep the host directories as include inputs only. Recommended (a) |
| D-3 | Canonical portable AI policy location | (a) a non-target directory read by the modify templates through the same literal include (e.g. `policy/claude-settings.json`, `policy/codex-config.toml`); (b) `home/.chezmoidata/` (merges into template data; Inference); (c) `home/.chezmoitemplates/` (parsed as templates). Recommended (a); `check-json`/`check-toml` and A1 retarget |
| D-4 | Oracle for `codex-policy.json` once `CODEX_POLICY` goes | (a) frozen golden list in the test (19 owned paths with types, 3 retired) plus structural checks against the portable TOML; (b) structural checks only. Recommended (a) |
| D-5 | Payload calls without `--now`/`-Now` | (a) error with one usage line, exit/return 2, no state, no option leak when sourced; (b) keep silent no-ops. Recommended (a) |
| D-6 | `DOTFILES_DIR` | (a) remove it as a knob everywhere (profile fallbacks, `sync-payloads` fallbacks, P0-preflight warning, README knob, docs/payloads.md, docs/testing.md, `tests/e2e/lib/flow-other.sh` and the suites that set it); `sync-payloads` then needs a valid binding and an unmarked home runs `sh <checkout>/scripts/payload-update.sh --now`, as H7-payloads prints; (b) keep it for `sync-payloads` only. Recommended (a). Either way, the paste-in helpers in bootstrap.md (`fetch_pinned`, `clone_listed`, the nvm block) read `${DOTFILES_DIR:-$HOME/dotfiles}` only to find the checkout, and D-1(a) relies on `fetch_pinned`: keep that as documented shell input or rename it to a local variable |
| D-7 | docs/update-contract.md and docs/sherlock-kit.md | (a) rewrite update-contract.md as the durable native updater contract (from takeover.md "Updates and edits after takeover") and delete sherlock-kit.md if support-boundary.md's manual checklist covers its links; (b) delete both. Recommended (a) |
| D-8 | `.gitignore` residue lines | (a) keep permanently as cheap guards; (b) remove after every host's residue is gone. Recommended (a) |
| D-9 | Old payload files and `.git` receipts on hosts | (a) remove exact files in Phase C under D11 after listing them; (b) leave them. Recommended (a) for `.venv-sync` and receipts, (b) for payload files unless the user wants them gone |
| D-10 | `settings.json:168-169` autoMode prose naming Stow links and `.venv-sync` | (a) update it in a separate reviewed commit that a human applies; (b) leave it. Recommended (a) |
| D-11 | e2e `stow` wrapper | (a) drop it from images, the mac job and audits; (b) keep it as a tripwire. Recommended (a); the audits already flag unexpected commands |
| D-12 | New test names | `tests/test_ai_policy.py` for policy; PowerShell parse gate and Terminal JSON into `tests/powershell-profile.sh`; optional retired-name repository test. Recommended as listed |
| D-13 | Inventory authority after consolidation | (a) re-key the inventory table to native paths and keep it as test input; (b) move expected target sets into a small data file under `tests/fixtures/` and leave inventory.md historical. Recommended (b) |
| D-14 | rc-pollution check | (a) scan live HOME rc files for installer blocks (read-only) and drop the checkout half; (b) retarget to `home/` unchanged; (c) drop it. Recommended (a) |
| D-15 | Remaining binary and floor findings (B6) | (a) keep Unix's PATH chezmoi (S4-chezmoi reuses a floor-satisfying chezmoi by design) and guard `$PSStyle` so the pwsh 7.0 floor holds; (b) also pin Unix to `~/.local/bin/chezmoi`; (c) raise the pwsh floor to 7.2 instead of guarding. Recommended (a), as a small separate `fix:` commit |
| D-16 | Rollout gating | (a) maintenance-gated canary on Lab, then host by host; (b) normal login propagation with post-checks. Recommended (a): B2 changes both profiles' bytes and B5 rewrites the layout the updater reads. (b) conflicts with support-boundary.md (quiescence before any Stage 6 breaking publication) and fleet-rollout.md "Ordered execution" step 3 ("Do not publish the deletion to auto-updated main first"); choosing it would first need those documents changed |
| D-17 | Takeover-from-Stow coverage | Conversion stays supported only from `bf99958`. (a) keep the takeover/recovery suites with synthetic links (`test_chezmoi_takeover_recovery.py:142`) and drop only cases that run `stow-all` or `dotfiles-update`; (b) delete link-conversion cases too. Recommended (a) |

## Not in Stage 6

Recorded findings for the user, not retirement work:

- Pre-existing provisioning gaps: tmux plugin clones on WSL, Mac, Sherlock and
  Marlowe; login-env packages on Sherlock and Marlowe; Marlowe's login env
  diverges from `hpc-login-env.yml`; Marlowe Claude Code at 2.1.150; Mac kitty,
  stylua and schrodinger.
- Payload host leftovers: Sherlock skills not installed (its `~/.cache ->
  /scratch` symlink refusal is upstream); Codex skills counts above 1,990 on Mac,
  WSL and Marlowe need a person to prune.
- Windows: Codex sandbox Modify grants on `~/.local`, `Documents\PowerShell`,
  AppData, Startup and `%TEMP%` (user decision); the narrowed, not closed,
  junction-swap window.
- Marlowe: the site AppArmor profile `block-node` denies node on login nodes, so
  Claude's Node hooks fail open (accepted); Codex config stays deployed, inert.
- Tool floors beyond D-15; upstream payload repositories; the permission policy
  beyond D-10; a portable transport watchdog (accepted limit).

## Coordinator completion

### Execute the six-host retirement

- [ ] Build and verify the final consolidated native-only source in an isolated
  checkout first. Apply no deletion commit to a live checkout while its old
  updater/workers can still run. Coordinate publication with the fleet order.
- [ ] Recheck all six targets using existing access. Read the latest follow-up
  in fleet-rollout.md: Windows direct access was repaired and verified; lab
  self-SSH rejection does not block local access. Do not assume the planning
  snapshot still holds or that a reused master proves fresh login. Follow
  cluster rules and record specific access/allocation blockers. Win must first
  pass its pending Stage 5 steps (R3).
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
