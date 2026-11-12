# Unified Dotfiles CLI Implementation Plan

> **For agentic workers:** Use the `subagent-driven-development` skill for
> task implementation and independent review. The user explicitly selects
> parallel implementation in separate worktrees; this overrides the skill's
> default of serial implementers in one checkout. Follow the ownership and
> dependency boundaries below. Steps use checkboxes for tracking.

**Goal:** Deliver a cross-platform `dotfiles` CLI, integrate every completed
task into an exact CI-approved `main`, and remove completed implementation
artifacts and worktrees.

**Architecture:** Small POSIX sh and PowerShell dispatchers forward to the
existing doctor, setup, payload and contributor backends. Deployed launchers
resolve the checkout from the home's validated chezmoi configuration. Existing
entrypoints remain compatible, and all public CLI options use the same long
option spelling across platforms.

**Tech Stack:** POSIX sh, Bash 3.2+, PowerShell 7.0+, existing chezmoi and Git;
Python 3.11+ stdlib for tests, existing pre-commit and three-platform CI.

**Spec:** [Binding design](#binding-design) in this document is the complete
implementation contract. Read it together with [AGENTS.md](../../AGENTS.md),
[bootstrap](../bootstrap.md), [updates](../updates.md),
[payloads](../payloads.md) and [testing](../testing.md).

## Global Constraints

- Runtime dispatch adds no Python, Node, pip package, environment, compiler,
  service or daemon dependency. Unix bootstrap retains Bash 3.2 compatibility;
  Windows CLI requires PowerShell 7.0, not Windows PowerShell 5.1.
- Shared public syntax is `dotfiles COMMAND --long-option VALUE`; Windows
  adapts it explicitly to the existing PowerShell parameters.
- Root checkout entrypoints work before chezmoi configuration exists.
  Installed launchers use only the validated home config's `sourceDir`.
- Doctor stays offline and write-free by default. Setup `--check` stays
  offline and write-free. Help runs no backend probes or installers.
- Preserve backend output streams, interactivity and exit codes, including
  setup's `3` for work remaining and payload handling of upstream exit `75`.
- Maintenance still blocks payload execution. Login updater behavior,
  ownership checks, encrypted secrets, installer pins and payload ownership
  remain governed by their existing contracts.
- No automatic first apply, force apply, authentication, elevation, PATH
  persistence, shell initialization or live-host installation is introduced.
- Each write-capable agent has one separate worktree. Each file has one
  active owner. Preserve unrelated changes and all unfinished work.
- Documentation and skills use English and printable ASCII. Canonical docs
  describe the current product, without task history or run identifiers.

## Review Focus

1. A fresh home has no config or Python: root help and explicit-host bootstrap
   must remain usable. Tasks 1 and 2 test restricted PATH and empty HOME.
2. The current directory names another checkout, or the configured checkout
   is a worktree with spaces: installed commands must use only the validated
   source. Task 3 tests both successful routing and refusal paths.
3. Windows argument binding, stale `$LASTEXITCODE`, output redirection and
   interactive setup can change behavior through a wrapper. Task 2 tests
   actual PowerShell processes and fake backends, not source text alone.
4. A newly deployed executable can escape lint selection or reach the wrong
   role. Task 3 tests exact targets, modes, counts and hook selection.
5. A test invoking `dev test` or `dev check` can recurse into its own runner.
   Tasks 1 and 2 use fixture runners; Task 3 checks each CI suite is selected
   once rather than composing duplicate full-suite invocations.

## Binding Design

### Scope and command contract

| Public command | Unix backend | Windows backend |
| --- | --- | --- |
| `doctor [OPTIONS]` | `bash doctor.sh` | `doctor.ps1` |
| `setup [OPTIONS]` | `bash setup-host.sh` | `setup-host.ps1` |
| `payloads sync [ITEM...]` | `sh scripts/payload-update.sh --now` | `scripts/payload-update.ps1 -Now` |
| `dev test [OPTIONS]` | `bash tests/run.sh` | `tests/run.ps1` in a fresh PowerShell process |
| `dev check` | `pre-commit run --all-files` | `pre-commit run --all-files` |
| `help [COMMAND...]`, `--help`, `-h` | Built-in CLI help | Built-in CLI help |

`dev check` runs from the selected checkout and can apply the existing
pre-commit formatters. It already includes behavior checks; it must not also
invoke `dev test`. Neither developer command installs missing dependencies.
Payload defaults, selection, retry messages, timeout and lock handling remain
in the payload backend and `config/payloads.tsv`.

No arguments prints top-level help and exits `0`. Bare `payloads` and `dev`
print their group help and exit `0`; they perform no operation. Support
`help doctor`, `help setup`, `help payloads sync`, `help dev test`,
`help dev check`, and the corresponding command followed by `--help` or `-h`.
Unknown command paths or options exit `2` with one concise diagnostic.
CLI errors use stderr; help uses stdout. Normal forwarding adds no banners.

| Command | Options on both platforms | Unix-only options | Windows-only options |
| --- | --- | --- | --- |
| `doctor` | `--host`, `--tier`, `--tsv`, `--quiet`, `--online` | `--platform`, `--smoke`, `--list` | None |
| `setup` | `--host`, `--tier`, `--check`, `--yes`, `--print-manual` | `--only`, `--skip`, `--keep-going`, `--list` | `--what-if`, `--confirm` |
| `dev test` | `--ci`, `--check-prerequisites` | None | None |

Help options apply to every row. `dev check` accepts only help, with no
arbitrary pre-commit passthrough. `payloads sync` accepts help and item names;
an unknown option exits `2`, while an unknown item retains the backend's
exit `1`. Do not hard-code a second payload inventory in the dispatcher.

Value options accept `--name VALUE` and `--name=VALUE`; empty or missing
values exit `2`. Scalar repetitions use the last value, boolean repetitions
are idempotent, and Unix `--only`/`--skip` retain repeatability. Boolean
`--flag=true` syntax is unsupported. Platform-unsupported options fail before
any backend runs. Preserve existing semantic validation, such as host versus
platform exclusivity, in the backend where possible. Commands and long
options use exact lowercase spellings; old PowerShell entrypoints retain
their native case-insensitive parameters.

Routing follows the entrypoint platform, not `--host`: selecting `win` in
the Unix CLI does not start WSL interop or remote execution. Existing host
defaults and unsupported-host refusals remain intact, including the Windows
backend's `win` default. Quote comma lists in PowerShell examples:
`dotfiles doctor --tier 'core,cli,ai'`. Raw array/object arguments to the
PowerShell dispatcher are rejected with exit `2`, rather than silently
stringified or expanded into a different argument vector.

### Entrypoints and source selection

Create these regular files:

| Source file | Responsibility |
| --- | --- |
| `dotfiles` | Executable POSIX sh dispatcher, rooted at its own checkout |
| `dotfiles.ps1` | PowerShell dispatcher, rooted at `$PSScriptRoot` |
| `home/dot_local/bin/executable_dotfiles` | Unix installed launcher for `~/.local/bin/dotfiles` |
| `home/dot_local/bin/dotfiles.ps1` | Windows installed launcher for `~/.local/bin/dotfiles.ps1` |

Root help must work without a configured home or optional tools. Installed
launchers resolve the configured source before forwarding any request,
including help. A missing/invalid config or missing dispatcher returns `1`
with a diagnostic naming the explicit checkout entrypoint as the recovery
path; installed launchers do not carry a duplicate help implementation.

Reuse the source-selection pattern in `home/dot_aliases` and the PowerShell
profile: locate the candidate guard from the first permitted top-level
`sourceDir` line, then let `lib/chezmoi-guard.*` validate the whole config.
Do not replace its restricted text contract with a generic TOML parser or
`chezmoi source-path`. No cwd, environment or `~/dotfiles` fallback exists.
Do not edit `home/.chezmoi.toml.tmpl` for this feature; doing so requires
per-host re-init that the CLI does not need.

Unix uses `exec` and quoted argument arrays through `"$@"`; it must not
source executable backends into the caller. PowerShell parses raw `$args`
without advanced named-parameter binding consuming GNU-style options. Map
recognized values to a parameter hashtable (`HostName`, `Tier`, `Check`,
`PrintManual`, `WhatIf`, `Confirm`, etc.) and call the existing scripts with
`&` and splatting. Do not use `eval`, `Invoke-Expression`, command-string
construction, wildcard command discovery or dynamic script paths.

PowerShell clears stale status immediately before invocation and saves and
propagates the observed backend status immediately afterward. A backend that
leaves status untouched succeeds after that reset; a native command inside
the backend can change status even without an explicit script `exit`, and
that resulting status is propagated. Terminating
invocation failures become one diagnostic and exit `1`. Do not capture and
re-emit success/Information/error streams. Do not force setup into
`-NonInteractive` or automatically add `--yes`. `dev test` uses the current
PowerShell executable under `$PSHOME` with `-NoProfile -File`, mapping its
two flags, so test environment sanitization cannot alter the caller's
environment. PowerShell `dev check` restores the caller's location in a
`finally` block, including on failure; wrapper preference changes stay in
script scope. Missing executables or backend files fail once with their
names and exit `1`, without a traceback or partial operation.

Keep both original doctor/setup scripts and the payload hooks callable with
their existing interfaces. Make `sync-payloads` and `sync-skills` delegate to
the installed launcher by explicit home path. Preserve their config refusal,
maintenance and exit semantics, and do not add an old-backend fallback when
the launcher is absent. Keep these aliases/functions in their existing
profile locations; do not broaden interactive startup behavior.
Keep each shortcut's existing argument behavior: Unix `sync-skills` appends
caller arguments after `skills`, while the Windows shortcut keeps its
existing fixed `skills` invocation.

### Deployment and Windows command discovery

Add exactly one target per role: the executable Unix launcher on every Unix
role, and the regular `.ps1` launcher on `win`. Replace Windows' broad
`.local` ignore with exact exclusions for the Unix launcher and existing
`my-fzf-preview.sh`; exclude the `.ps1` launcher on non-Windows roles.
Keep the target table authoritative and verify no other target changes.

The Unix profile already places `~/.local/bin` on PATH. Windows does not.
Document an explicit, unelevated, one-time User PATH procedure in the
Windows deployment instructions: preserve all existing user entries,
deduplicate the added home-local bin path case-insensitively, never copy the
combined process/Machine PATH into User PATH, and explain the fresh-process
requirement. Do not execute this procedure from setup, the launcher or a
profile. Keep the existing execution-policy HUMAN procedure. No new HUMAN
step ID, `.cmd` shim, Windows PowerShell 5.1 or cmd.exe support is required.

Before that manual PATH setup, support explicit invocation:
`& "$HOME/.local/bin/dotfiles.ps1" doctor --host win`. Afterward, bare
`dotfiles` must work in a fresh PowerShell 7 process, including `-NoProfile`.
Tests may supply a controlled process PATH; they must not change the real
machine's User PATH. Review Windows destination-parent ACLs and missing
parents using the existing deployment procedure; retain `--exclude=dirs`.

### Scope boundary and completion authority

This release covers the commands above. Manual `update`, `diff`, `apply`,
maintenance management, shell completion, plugin discovery and backend
relocation are separate work. In particular, `scripts/chezmoi-update.*`
remains a login hook: it skips noninteractive/session-repeated execution
and does not expose a suitable manual failure contract.

The user's requested execution includes implementation, scoped commits,
candidate CI pushes, fast-forward landing on `main`, and cleanup of this
task's artifacts and merged branches. Apply repository gates without asking
again at each routine step. Preserve unrelated work. Release ready here
means tested source on local and remote `main`; it does not mean a new tag,
GitHub Release or live-host rollout. Those are separate operations.

## Parallel Workflow and Ownership

Use the primary project's `.worktrees/` directory, already ignored by Git.
Recheck that ignore before creating worktrees. Suggested task-owned names
are below; inspect existing names and choose a unique suffix on collision.

| Worktree | Branch | Writer and ownership |
| --- | --- | --- |
| `.worktrees/dotfiles-cli-integration` | `task/dotfiles-cli-integration` | Coordinator; handoff, integration, then Tasks 3-5 |
| `.worktrees/dotfiles-cli-unix` | `task/dotfiles-cli-unix` | Unix agent; Task 1 files only |
| `.worktrees/dotfiles-cli-windows` | `task/dotfiles-cli-windows` | Windows agent; Task 2 files only |

Dependency order is `Task 0 -> (Task 1 || Task 2) -> Task 3 -> Task 4 -> Task 5`.
Run independent reads and reviews concurrently as slots permit. During the
parallel implementation wave, the coordinator may draft documentation in
its own worktree but must not edit either worker's files. A reviewer is
read-only. Once workers stop and their branches are merged, the coordinator
may transfer their file ownership to the next implementer explicitly.

One writer owns shared integration files: `.pre-commit-config.yaml`,
`tests/test-entrypoints.sh`, `tests/run.*`, deployment fixtures, profile
changes, docs and mirrored skills. Do not ask both platform agents to patch
these files independently. When delegating Task 3 or 4, the coordinator
stops writing the integration checkout until that implementer releases it.

Checks that enumerate `git ls-files` require task-owned additions and
deletions to be staged first. Stage exact paths, inspect the staged diff,
then run those checks and full pre-commit; restage reviewed formatter edits
before committing. Do not use `git add .` or include another agent's work.

Store active reports, decisions and test evidence under the primary
project's ignored `.worktrees/dotfiles-cli-handoff/` directory, outside the
individual worktrees. Never use `.git/`, and do not keep the only recovery
copy in `/tmp`. Record actual branch tips and test run identifiers there,
not in canonical docs. Each report names owned files, commits, commands,
results, skipped checks and remaining findings.

## Task 0: Preserve the Handoff and Establish the Baseline

**Owner:** Coordinator. **Files:** This plan and an ignored execution ledger.
**Produces:** A durable plan commit on the integration branch and a common
base for the two independent implementation branches.

- [ ] Read project instructions, inspect status/diffs/untracked files and
  worktrees, and identify any active agents. Confirm this plan's v1 scope.
- [ ] If this handoff is untracked, create the integration worktree from
  the clean base, copy the exact plan into it, and deliberately stage only
  that file. Run focused documentation checks and full pre-commit, then
  commit the plan. Verify byte identity and durable
  Git storage before removing the task-owned untracked copy in the primary
  checkout. Do not commit the plan directly to deployed `main`.
- [ ] Check required test tools with `./tests/run.sh --ci --check-prerequisites`.
  Record preexisting failures separately; do not install into live homes
  merely to make a test pass. Read `docs/testing.md` for opt-in fixtures.
- [ ] Create the Unix and Windows worktrees from the same integration base.
  Give each agent the global constraints, binding design, its task, exact
  worktree path and report path. No worker writes the primary checkout.

## Task 1: Unix Dispatcher and Focused Behavior Tests

**Files:** Create `dotfiles`, `tests/cli.sh`, `tests/test_cli_unix.py`.
**Consumes:** Existing Unix backends and the public command contract.
**Produces:** Executable `./dotfiles` and `./tests/cli.sh`; no deployed target
or shared CI registration is added in this task.

- [ ] Write failing unittest cases using isolated fixture checkouts and
  fake backends: `test_help_without_home_config_or_python`,
  `test_command_and_option_refusals`, `test_setup_argv_and_exit_3`,
  `test_payload_sync_adds_now_once`, `test_doctor_tsv_has_no_banner`,
  `test_dev_commands_use_selected_checkout`, and
  `test_missing_backend_or_tool_fails_once`. Assert exact argv boundaries,
  stdout/stderr and exit status, including paths with spaces and literal
  shell metacharacters. Use fake pre-commit/test runners to prevent recursion.
- [ ] Add a real-shell interruption/TTY check with a harmless fixture child:
  stdin and terminal status reach setup, and interruption reaches the child
  without leaving it running. No live installer participates.
- [ ] Make `tests/cli.sh` load `tests/lib/environment.sh` and run only the
  new Python suite with `python3 -I -B`. Fixture Git must sanitize inherited
  repository/index overrides before mutation.
- [ ] Run `./tests/cli.sh`; confirm failures identify the absent dispatcher.
- [ ] Implement the small fixed dispatch table and CLI-owned help. Preserve
  original doctor/setup argument values and let those backends keep semantic
  validation. Make `dev check` change directory only inside its process.
- [ ] Run `./tests/cli.sh`, `shellcheck --severity=warning dotfiles tests/cli.sh`,
  and `shfmt -d -i 4 -ci -ln posix dotfiles`. Confirm all pass; use Bash style
  for the test launcher. Run required pre-commit before committing.
- [ ] Commit only owned files and request independent task review. Report
  tests, skips and concerns; retain branch/worktree until integration.

## Task 2: PowerShell Dispatcher and Focused Behavior Tests

**Files:** Create `dotfiles.ps1`, `tests/cli.ps1`.
**Consumes:** Existing PowerShell backends and the same public contract.
**Produces:** `dotfiles.ps1` and a standalone `tests/cli.ps1` behavior suite.

- [ ] Write failing cases in temporary homes/checkouts. Cover raw long
  options, `--name=value`, quoted comma lists, scalar repetitions, array
  rejection, unsupported Unix options, help with no config/Python, and
  missing tools. Fake scripts record their bound parameters as structured
  data; do not test correctness by grepping the dispatcher source.
- [ ] Test backend exits `0`, `1`, `2`, `3`, a status-untouched backend after
  a stale failure, a backend that leaves a native failure status without
  script `exit`, success/Information/error streams, redirected TSV, and a
  harmless interactive setup child. Verify `--what-if`/`--confirm` mapping
  and that no implicit `-NonInteractive` or `-Yes` is added.
- [ ] Load `tests/lib/environment.ps1` in the test entrypoint. Exercise
  `dev test` in a child process and assert its environment cleanup does not
  reach the parent. Assert `dev check` restores the parent's location after
  success, nonzero exit and invocation failure. Stub dev runners and
  pre-commit to prevent recursion.
- [ ] Run `pwsh -NoProfile -File tests/cli.ps1`; confirm failures identify
  the missing dispatcher. If PowerShell is unavailable locally, keep this
  limitation explicit and require native Windows evidence before acceptance.
- [ ] Implement raw-argument parsing, explicit parameter mappings and
  status/stream propagation as specified. Use `$PSScriptRoot`, literal paths
  and splatting; leave legacy backends and Windows PowerShell 5.1 untouched.
- [ ] Run the focused suite and existing `tests/terminal.ps1` when pwsh is
  available. Run required pre-commit before committing owned files.
- [ ] Request independent task review; record any missing native evidence
  without claiming cross-platform verification from parser checks alone.

## Task 3: Integration, Deployment and Compatibility

**Owner:** One integration implementer after Tasks 1 and 2 pass review.
**Files:** Create both deployed launchers from the design table. Modify
`home/.chezmoiignore`, `home/dot_aliases`,
`home/Documents/PowerShell/profile.ps1`, `tests/fixtures/chezmoi/targets.tsv`,
`tests/chezmoi_source_support.py`, `tests/test_chezmoi_rendered.py`,
`tests/test_chezmoi_guard.py`, `tests/test_cli_unix.py`, `tests/cli.ps1`,
`tests/shell-profile.sh`,
`tests/powershell-profile.ps1`, `tests/powershell-profile.sh`,
`tests/test-entrypoints.sh`, `tests/run.sh`, `tests/run.ps1`,
`.pre-commit-config.yaml` and `tests/COVERAGE.md`.
**Produces:** Installed commands, compatible shortcuts, and mandatory
platform-appropriate CLI tests through existing check entrypoints.

- [ ] Stop worker writes, review their complete branch ranges, and merge
  both branches into integration. Use ordinary merges to preserve ancestry;
  do not cherry-pick by default or rewrite another agent's commits.
- [ ] Extend focused tests before deployment code: a configured source
  different from cwd and `~/dotfiles`; a linked worktree with spaces;
  missing, duplicate-key, symlinked or malformed config; missing guard or
  dispatcher; foreign destination; maintenance; missing launcher in legacy
  aliases; and status propagation through `sync-skills`.
- [ ] Add Windows discovery cases for explicit `.ps1` invocation with no
  profile/PATH entry and bare `dotfiles` with controlled process PATH.
  Verify the fixture uses no real User PATH or live profile.
- [ ] Implement both launchers and replace only the existing manual payload
  wrapper bodies. Keep login tails, interactivity guards and conda stubs
  unchanged. Extend fixtures to include the dispatcher/launcher where old
  wrapper tests previously installed only a fake payload hook. In particular,
  update `test_sync_commands_use_only_the_validated_home_source` in
  `tests/test_chezmoi_guard.py`, including diagnostics, while retaining its
  sh/dash/Bash/zsh, invalid-config, maintenance and exit-code coverage.
- [ ] Add target rows: `.local/bin/dotfiles`, hosts `unix`, mode `executable`,
  shell `sh`; `.local/bin/dotfiles.ps1`, host `win`, mode `regular`, shell `-`.
  With only these two files, each role gains one target: expected counts
  become `50/57/56/59/55/55/27` in existing role order. Increment rendered
  shell counts only for Unix roles. Re-derive from the current base if it
  has advanced; never overwrite unrelated newly added targets.
- [ ] Register the Unix CLI suite and Windows CLI suite in their native
  runners, the optional Unix PowerShell path and PowerShell parse gate.
  Add one scoped pre-commit CLI hook, selecting both dispatchers, launchers,
  their tests and consumed guards/backends. Update selection tests and
  shellcheck/POSIX shfmt patterns to include extensionless files. Avoid
  running the same CLI suite twice within one full check invocation.
- [ ] Run both focused CLI suites plus `tests/shell-profile.sh`,
  `tests/powershell-profile.sh`, `tests/test-entrypoints.sh` and
  `tests/chezmoi.sh`; require native Windows behavior through its runner.
  Confirm existing target bytes, AI policies, login behavior and bootstrap
  refusals remain unchanged. Run full pre-commit before committing.
- [ ] Obtain independent integration review covering source selection,
  platform targets, quoting, exit statuses and CI reachability.

## Task 4: Public Documentation and Bootstrap E2E

**Owner:** One implementer with integration ownership after Task 3.
**Files:** Modify `README.md`, `AGENTS.md`, `docs/bootstrap.md`,
`docs/dependencies.md`, `docs/payloads.md`, `docs/shell.md`, `docs/testing.md`,
`.agents/skills/dotfiles-bootstrap/SKILL.md`, its identical `.claude/skills/`
counterpart, `tests/e2e/lib/steps.sh`, `tests/e2e/lib/flow-unix.sh`,
`tests/e2e/lib/steps.ps1`, `tests/e2e/lib/flow-win.ps1`, and the corresponding
`tests/e2e-harness.*` fixture assertions. Modify related coverage/parse
selection files only when the changed test inputs require it.
**Produces:** Discoverable CLI instructions and fresh-bootstrap evidence
that exercises the new public path.

- [ ] Update primary examples to the unified CLI; document old entrypoints
  as supported compatibility interfaces. Include the option availability
  table, setup exit `3`, payload semantics, dev-check write behavior and
  recovery through explicit checkout paths. Keep backend-specific reference
  sections accurate rather than mechanically renaming every script mention.
- [ ] Document Unix and Windows discovery, including the manual User PATH
  procedure and native PowerShell quoting from the design. Include explicit
  path examples for use before configuration/deployment. Update the Windows
  target count and other derived counts in canonical documentation.
- [ ] Keep `AGENTS.md` under its size cap, change no `CLAUDE.md` stub, and
  keep the two project skill bodies identical. No new HUMAN step IDs are
  needed; existing deployment blocks point to the updated instructions.
- [ ] Write failing e2e-harness expectations for unified CLI invocation.
  Switch positive root doctor/setup bootstrap calls to `./dotfiles ...`
  and `dotfiles.ps1` with long options. After deployment, exercise the
  installed launcher from a directory outside the checkout. On Windows use
  explicit launcher path and a controlled process PATH for bare-name proof.
  Preserve at least the existing legacy backend negative/compatibility tests.
- [ ] Preserve e2e timeouts, no-write snapshots, HUMAN execution policy,
  standard-user requirements and assertion strength. Do not add extra real
  installs solely to test forwarding; exercise the existing installation
  steps through the new frontend. `other` retains its generic-host flow.
- [ ] Run `tests/bootstrap-manifest.sh`, `tests/e2e-harness.sh`,
  `tests/e2e-harness-windows.sh`, `tests/markdown-links.sh` and full pre-commit.
  Review and commit only the coherent documentation/e2e change.

## Task 5: Acceptance, Exact-Candidate Landing and Cleanup

**Owner:** Coordinator, with an independent whole-change reviewer.
**Consumes:** Reviewed integrated implementation, focused test reports and
canonical docs. **Produces:** Clean local/remote `main` at the approved
candidate, with merged task worktrees and artifacts removed.

- [ ] Review the complete diff against the task's starting base. Confirm
  all review findings are resolved or explicitly judged nonblocking with
  reasons. A known correctness, security, compatibility or required-test
  failure blocks release-ready status; a retry limit does not waive it.
- [ ] Preserve the accepted plan in Git history. Move every lasting
  instruction into canonical docs, then remove this completed handoff and
  any other task-owned tracked scratch artifacts from the integration tree.
  Stage these exact deletions before the tracked-file checks below.
  Retain the ignored active ledger and evidence until landing is verified.
  Make this tracked cleanup part of the candidate, not a post-CI commit.
- [ ] Run `./tests/run.sh --ci` and `pre-commit run --all-files` on the final
  integration tree. Inspect their results and `git diff --check`, stage
  deliberately and confirm clean status. Recheck after any formatter edits.
  Preserve existing native macOS/Windows and optional-fixture distinctions.
- [ ] Freeze candidate `C` from integration HEAD. Push that exact commit to
  task-owned `ci/dotfiles-cli` and `e2e-ci/dotfiles-cli` branches, using unique
  names if existing branches belong to others. No force push. This feature
  changes bootstrap-facing entrypoints, so both workflows are required.
- [ ] Verify `ci.yml` and `bootstrap-e2e.yml` both complete for `headSha == C`
  and every required job succeeds. The e2e push selects all supported cases
  without acceptance caches. Record URLs and platform limitations in the
  ignored ledger. A green run for another SHA is insufficient. Any code,
  test or tracked-cleanup change creates a new candidate and restarts gates.
- [ ] Refresh remote main and require it to be an ancestor of `C`. If it
  advanced incompatibly, merge it into integration, resolve and review the
  combined result, rerun local checks and both workflows for the new
  candidate. Preserve unexplained local main commits or changes.
- [ ] With the primary checkout clean, fast-forward local `main` to `C`
  using `git merge --ff-only`, push main normally, and verify local and
  remote main resolve to `C`. Handle a concurrent remote advance through
  integration and new gates. Do not squash, amend, rebase, force push or
  create a cleanup commit after the approved candidate. Verify the resulting
  main CI run as well before the final release-ready report.
- [ ] For each worker and integration worktree, confirm its agent and tests
  have stopped, inspect status/diffs/untracked files, and require the branch
  tip to be an ancestor of landed main. Preserve any unexplained files.
  Use `git worktree remove` without force, then `git branch -d` for merged
  task branches. Never recursively delete `.worktrees/` or unrelated state.
- [ ] Remove only this task's remote candidate branches after landing is
  verified. Review the ignored handoff/evidence directory's exact contents,
  preserve any still-needed recovery data, and remove completed artifacts
  through canonical cleanup commands. Keep no report bundle in `.git/`.
- [ ] Report the CLI commands delivered, local checks, exact candidate and
  workflow evidence, remaining limitations, `git status --short`, and
  `git worktree list`. Distinguish release readiness from live-host rollout.

## Release-Ready Checklist

- [ ] All commands and common long options work on their supported platforms.
- [ ] Root bootstrap needs no new runtime; installed routing is config-bound.
- [ ] Legacy commands remain compatible; login behavior is unchanged.
- [ ] Unix/Windows target sets, permissions, PATH guidance and help agree.
- [ ] Focused tests and full local checks pass; native platform evidence exists.
- [ ] Both required candidate workflows pass for the exact landed commit.
- [ ] Canonical docs and mirrored skills describe the delivered interface.
- [ ] Main is clean and synchronized; no unmerged task branch or active task
  worktree remains, and completed handoff/scratch artifacts are removed.

## Prompt for the Executing Session

> Implement `docs/handoff/unified-cli-refactor-plan.md` through its
> release-ready checklist. Read AGENTS.md first. Use parallel Unix and
> PowerShell implementers in separate project-local worktrees, then integrate
> under one writer with independent reviews. Preserve the handoff durably
> before cleaning its initial copy. Complete implementation, canonical docs,
> local tests, exact-candidate three-platform CI and bootstrap E2E, then
> fast-forward and push main. Remove completed tracked artifacts before the
> final candidate; remove merged worktrees, branches and ignored scratch
> only after verified landing. Preserve unrelated work and report concrete
> blockers and missing platform evidence instead of claiming release ready.
