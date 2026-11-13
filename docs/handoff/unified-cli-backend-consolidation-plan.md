# Unified CLI Backend Consolidation Implementation Plan

> For agentic workers: use `subagent-driven-development` for task execution
> and independent review, with the separate-worktree ownership below. The
> user explicitly selects parallel Unix and PowerShell implementation. This
> document combines the binding design and its implementation plan.

**Goal:** Retire the old user entrypoints, preserve the public `dotfiles`
interface, and deliver independently implemented native command backends
through exact-candidate CI, main landing, six-host rollout and safe cleanup.

**Architecture:** Small POSIX sh and PowerShell frontends own public syntax,
help and dispatch. Executable command implementations live in
`scripts/commands/`; sourced shared modules remain in `lib/`. Installed
launchers continue selecting the checkout from validated home configuration.

**Tech stack:** Existing POSIX sh, Bash 3.2+, PowerShell 7.0+, chezmoi, Git
and repository test tools. No new CLI or bootstrap runtime dependency.

**Spec:** The binding design in this document, together with
[AGENTS.md](../../AGENTS.md), [bootstrap](../bootstrap.md),
[updates](../updates.md), [hosts](../hosts.md), [payloads](../payloads.md)
and [testing](../testing.md).

## Authority and baseline

This handoff authorizes no execution by its mere presence. The planning
session writes only this document, performs read-only exploration and checks
the document. It does not implement, commit, push, publish or deploy. The
execution prompt at the end becomes authorization only when the user gives
it to an executing agent after review.

Use the current repository as the execution baseline. Re-read instructions,
status, staged and unstaged diffs, untracked files, branch tips and worktrees
before work. Preserve other sessions' changes. Do not reset to a historical
reference or assume the source has stayed unchanged since this plan.

Background references supplied by the user are available with:

```sh
git show acd8f7387c84026e20653f0563ad16aa025a42d3:docs/handoff/unified-cli-refactor-plan.md
git show 74f30d234c5aa2ecef59d705fcdf6b63163bf07d
```

Those references explain the existing frontend and its compatibility layer;
their instructions to retain old entrypoints are superseded by this design.
Their delivery scope also differs: this plan includes actual six-host
rollout. Historical commits are evidence, never a replacement working tree.

## Binding design

### Goals and non-goals

The selected approach is option 3: retire the old user entrypoints and keep
separate command implementations. Delete the four root doctor/setup scripts
and the two old foreground payload script paths after migrating their
callers. There must be one implementation per command per native platform,
with no compatibility shim, hidden fallback or forwarding cycle.

Keep the current public CLI command set, argument grammar, streams, statuses,
interactive behavior and source-selection rules. Move human-facing examples
and emitted instructions to that CLI. Tests may invoke formal internal
backends to isolate behavior; that does not make those paths a public API.

Do not add commands, completion, a plugin registry, automatic discovery,
new runtime libraries, dependency upgrades, payload revisions or unrelated
cleanup. Do not consolidate unrelated modules or move business logic into
the frontends. Manual update/apply/diff and maintenance remain the existing
chezmoi procedures. Login hooks remain lifecycle hooks.

### Final layout and dependency direction

```text
dotfiles                              # public POSIX frontend
dotfiles.ps1                          # public PowerShell 7 frontend
scripts/
  commands/
    doctor.sh                         # executable Bash backend
    doctor.ps1                        # executable PowerShell backend
    setup.sh                          # executable Bash backend
    setup.ps1                         # executable PowerShell backend
    payloads-sync.sh                  # executable POSIX backend
    payloads-sync.ps1                 # executable PowerShell backend
  chezmoi-update.sh                   # stable sourced login hook
  chezmoi-update.ps1                  # stable login lifecycle implementation
lib/
  bootstrap/*.sh                     # shared sourced Bash modules
  bootstrap.ps1                      # shared dot-sourced functions
  chezmoi-guard.sh
  chezmoi-guard.ps1
  terminal.sh
  terminal.ps1
config/                              # existing inventories and pins
home/
  dot_local/bin/executable_dotfiles   # installed Unix launcher source
  dot_local/bin/dotfiles.ps1          # installed Windows launcher source
  ...                                # existing chezmoi targets
tests/
  run.sh
  run.ps1
  cli.sh
  cli.ps1
  test_cli_unix.py
  doctor.sh                          # retained test suite name
  setup-host.sh                      # retained test suite name
  payload-update.sh
  payload-update.ps1                 # retained test suite names
  ...                                # shared, fixture and E2E layers
```

The runtime graph is:

```text
person -> explicit checkout frontend -> formal command backend -> lib/config/native tools
person -> installed launcher -> validated sourceDir frontend -> same backend
sync-payloads / sync-skills -> installed launcher -> payloads sync -> same backend
interactive profile -> validated sourceDir login hook -> guard/terminal/chezmoi
dev test -> tests/run.*
dev check -> pre-commit in the selected checkout
```

Repository modules sourced/imported by command implementations stay in
`lib/`; preserve existing explicitly trusted vendor loading, such as the
validated nvm step, under its existing safety checks.
Backends never invoke the frontend or an old path to execute their own
operation. A printed recovery command can name the frontend without creating
a runtime dependency cycle. Frontends use a fixed dispatch table, not a scan
of `scripts/commands/`. Developer runners stay under `tests/`; their distinct
caller and dependency model does not justify another wrapper layer.

### Disposition of existing entrypoints

| Existing path or interface | Final disposition | Reason and required callers |
| --- | --- | --- |
| `dotfiles`, `dotfiles.ps1` | Keep; change backend table only as needed | Stable public parser/help/dispatch contract |
| Root `doctor.sh`, `doctor.ps1` | Move implementation to `scripts/commands/doctor.*`; delete old paths | Public callers use `dotfiles doctor`; isolated behavior tests can use the new backend |
| Root `setup-host.sh`, `setup-host.ps1` | Move implementation to `scripts/commands/setup.*`; delete old paths | Public callers use `dotfiles setup`; retain native internal parameters |
| `scripts/payload-update.sh`, `.ps1` | Move implementation to `scripts/commands/payloads-sync.*`; delete old paths | These are foreground person-run payload backends, not login hooks; migrate CI, advice, fixtures and direct tests |
| `scripts/chezmoi-update.sh`, `.ps1` | Keep paths and runtime behavior | Profiles load these lifecycle hooks; interactivity/session guards and failure behavior do not fit a manual subcommand |
| `home/dot_local/bin/executable_dotfiles`, `home/dot_local/bin/dotfiles.ps1` | Keep deployed paths and routing | Already delegate to the configured checkout frontend |
| `sync-payloads`, `sync-skills` in existing profiles | Keep public shortcuts | Already delegate to installed launchers; no old-backend fallback |
| `tests/run.*`, `tests/doctor.sh`, `tests/setup-host.sh`, `tests/payload-update.*` and other test launchers | Keep names and responsibilities | Test entrypoints are not retired production entrypoints |
| `lib/bootstrap/*`, `lib/bootstrap.ps1`, guards and terminal libraries | Keep module boundaries | Shared functions and scope semantics; update consumers and comments only where necessary |

No production file remains at any of the six retired paths. A symlink or
wrapper at one of them fails acceptance even if it prints a retirement
message. Direct old-path invocation is intentionally unsupported; its OS
missing-file failure need not be normalized across platforms.

### Public interface contract

| Public command | Unix execution | PowerShell execution |
| --- | --- | --- |
| `doctor [OPTIONS]` | `exec bash scripts/commands/doctor.sh` with original argv | `& scripts/commands/doctor.ps1` with mapped native parameters |
| `setup [OPTIONS]` | `exec bash scripts/commands/setup.sh` with original argv | `& scripts/commands/setup.ps1` with mapped native parameters |
| `payloads sync [ITEM...]` | `exec sh scripts/commands/payloads-sync.sh --now` plus items | `& scripts/commands/payloads-sync.ps1 -Now` plus `Item` |
| `dev test [OPTIONS]` | `exec bash tests/run.sh` | Current `$PSHOME` PowerShell child, `-NoProfile -File tests/run.ps1` |
| `dev check` | Change directory inside the frontend process, then exec pre-commit | Save/restore caller location with `finally`, invoke pre-commit |
| Help | Frontend built-in output | Frontend built-in output |

All paths in that table are resolved relative to the selected checkout,
never relative to the caller's cwd.

| Command | Both platforms | Unix only | PowerShell only |
| --- | --- | --- | --- |
| `doctor` | `--host`, `--tier`, `--tsv`, `--quiet`, `--online` | `--platform`, `--smoke`, `--list` | None |
| `setup` | `--host`, `--tier`, `--check`, `--yes`, `--print-manual` | `--only`, `--skip`, `--keep-going`, `--list` | `--what-if`, `--confirm` |
| `dev test` | `--ci`, `--check-prerequisites` | None | None |

Every command accepts `-h`/`--help`; `help` accepts the current valid command
paths. No arguments and bare `payloads`/`dev` show help, status 0. Preserve
current validation ordering: a help flag does not excuse an otherwise
invalid argument vector. Help uses stdout, errors stderr, and forwarding
adds no banner, especially for TSV.

Command names and public long options are exact lowercase. Values accept
`--name VALUE` and `--name=VALUE`; empty/missing values, unknown arguments,
boolean `--flag=true`, and platform-unsupported options fail with status 2
before a backend executes. Repeated scalar values use the last value;
booleans are idempotent; Unix step selections remain repeatable. PowerShell
rejects null, array and object arguments rather than stringifying them.
Quote comma lists in PowerShell examples, such as `--tier 'core,cli,ai'`.

Payload names, defaults and platform availability remain owned by
`config/payloads.tsv` and the backend. An unknown item returns 1; the
frontend must not duplicate the inventory. User-supplied `--now` is still
rejected. Retain `--now`/`-Now` as an internal foreground-execution sentinel,
added once by the frontend; absent sentinel returns 2 before maintenance or
downloads. Native backend parameter names remain an internal test contract,
not a second documented public command grammar.

The entrypoint platform chooses the native backend, not `--host`. Unix
doctor/setup retain configured `[data].host` resolution and existing
generic/unsupported-host refusals. Current Windows doctor/setup default to
`win` and accept only that host: do not impose Unix default-host inference
on them. Keep this distinction explicit when editing AGENTS and docs.

| Result | Required status behavior |
| --- | --- |
| Doctor | Preserve 0 success, 1 reported failure, 2 invalid/refused input |
| Setup | Preserve 0 complete, 1 failure, 2 invalid/refused input, 3 work pending; Windows initial ShouldContinue refusal is 2, while per-step ShouldProcess/Confirm refusal and WhatIf leave pending work at 3 |
| Payload child returns 75 | Informational lock contention; aggregate success if no other item fails |
| Another payload failure | Aggregate 1 and actionable public retry advice |
| Missing backend or required tool | One named diagnostic, status 1, no old-path fallback or partial execution |
| Unix interrupt | Preserve exec and existing backend handling; PTY fixture interruption remains 130 |
| Developer commands | Propagate runner/tool status; do not install tools or run a suite twice |

### Self-location, scope and output

Unix frontends retain their POSIX self-location and `exec` chain with quoted
`"$@"`. Bash backends resolve the checkout two parents above
`${BASH_SOURCE[0]}`; the POSIX payload backend resolves two parents above
`$0`. Preserve `CDPATH` suppression and each implementation's canonical-path
behavior. Test arbitrary cwd, linked worktrees, spaces, quotes and literal
shell metacharacters. Do not add Git discovery, `realpath`/`readlink -f`
requirements, environment-selected source roots or symlink-wrapper support.

Do not source executable backends, add a wrapper trap, capture output or
put setup behind a pipe. stdin/stdout/stderr and TTY identity must reach the
backend unchanged. Setup prompts remain on stderr with `read -r` on stdin;
noninteractive refusal, EOF, `--yes` and pending status 3 remain intact.
Shared Bash modules keep dynamic scope and caller variables; preserve the
ordinary `steps_run` invocation and its errexit restoration, rather than
placing it in a conditional context that disables errexit inside functions.

PowerShell keeps a raw `$args` parser without a new advanced `param` block
in the frontend. Compute backend roots with two parent operations on
`$PSScriptRoot`; use literal paths and hashtable splatting. Invoke backends
with `&` in script scope, not dot-sourcing, `Invoke-Expression`, a command
string or a new `pwsh` process. Do not capture/re-emit streams: retain stream
1 object identity, streams 2-6, redirection and caller preferences. Preserve
the deliberate `$global:LASTEXITCODE = 0` reset immediately before dispatch
and immediate result capture afterward, including a backend that leaves a
native failure without explicit `exit`. A terminating invocation error
becomes one diagnostic and status 1.

Only `dev test` keeps its separate PowerShell process to contain environment
sanitization. `dev check` restores location on success and failure. Do not
add `-NonInteractive`, `-Yes` or preference changes around ordinary setup;
native `ShouldProcess`, WhatIf and Confirm must still work. Windows
PowerShell 5.1 remains a profile/guard compatibility concern, not a new CLI
platform.

### Human instructions and retry source selection

Replace the misleading `bootstrap_payload_hook ROOT` contract with
`bootstrap_payload_source ROOT`, returning exactly one selected checkout
path on stdout, success status 0, or refusal status 1. It returns no command
string. Preserve the existing configured-home selection and refusal order;
with no config it returns the explicit checkout root. This is an internal
rename, not a new general source-discovery mechanism.

`bootstrap_check_payloads` and `step_H7_payloads_plan` consume that root and
append the public `dotfiles payloads sync` command. Remove suffix stripping
of `/scripts/payload-update.sh`. A configured different checkout stays the
selected source. Keep these distinct contracts:

| Consumer | Source and refusal behavior |
| --- | --- |
| `bootstrap_payload_source ROOT` | No config: return ROOT, including the existing early-return behavior under maintenance. Configured and valid: canonical ROOT or configured OTHER. Configured but maintenance/invalid/link/unreadable guard: return 1 |
| H7-payloads HUMAN block | Use the helper-selected source; helper refusal produces notes only |
| Doctor payload advice | Prefer the helper-selected source when usable; retain explicit ROOT advice when resolution refuses. Do not turn the existing warning into notes-only behavior |
| Executing payload backend retry | Always rerun that backend's own ROOT; use shortcut only when it reaches ROOT, otherwise print explicit ROOT frontend |

The actual payload backend independently enforces maintenance. Do not
broaden this task into changing the existing no-config advisory behavior.

Use a quoted explicit checkout frontend for copyable doctor/setup commands
and for payload retries when a shortcut cannot reach that checkout. Retain
`sync-payloads ITEM` advice only when the validated home source and available
installed launcher actually route there. No config, a different configured
source or a missing installed launcher must get the explicit checkout
command, never advice that silently selects another checkout. Retain item
arguments and current retry/failure classifications.

Unix uses existing quoting helpers (including `steps_quote`); PowerShell
uses its existing single-quoted literal escaping, including
`CodeGeneration::EscapeSingleQuotedStringContent` where applicable, and
prints `& '<checkout>/dotfiles.ps1' ...`. Do not introduce eval to execute
advice. All HUMAN lines remain either `# ` notes or self-contained commands;
digest gates, step IDs and the visible privilege boundaries remain intact.

### Alternatives and failure risks

| Decision | Rejected alternative | Tradeoff and risk control |
| --- | --- | --- |
| `scripts/commands/` with six native files | Giant frontend or unrelated module mergers | Clear executable/backend boundary; update self-location and all fixture copy lists |
| Delete old paths | Compatibility shims or fallback | Deliberate old-interface break; migrate every supported caller and prove absence |
| Keep login hooks at current paths | Move hooks into manual CLI | Avoid changing pre-pull lifecycle, session and failure semantics |
| Keep native parameter adapters | Shared parser/runtime framework | Some platform duplication remains; public contract tests enforce parity |
| Keep payload sentinel internally | Remove it during relocation | Avoid unnecessary behavioral change; public help and examples never expose it |
| Shared-file integration after platform branches | Both workers edit manifests/docs/runners | Extra integration stage prevents overlapping ownership and incomplete selector updates |
| No new deployed target | Redeploy renamed launchers | Existing launcher remains valid across old/new checkout revisions; exact target set stays fixed |

## Safety and behavior invariants

1. Explicit checkout commands work before home configuration exists. Root
   help requires no backend, Python, Node, installation or optional probe.
   Installed help still requires the validated home `sourceDir`; no cwd,
   `~/dotfiles`, environment or old-path fallback exists.
2. Keep the guard's restricted text config grammar, exact source/destination,
   symlink/junction and Windows ACL checks, safe update argument set,
   nonempty state requirement and dirty-source refusal. Do not change
   `home/.chezmoi.toml.tmpl` or introduce re-init requirements.
3. Maintenance in any existing recognized form blocks login updates and
   payload runs. Payloads remain foreground-only with private download
   staging, timeout, failure latch, stdin closure and cleanup. No extra
   scheduler, journal, lock protocol or daemon is introduced.
4. Doctor default and setup check remain offline and write-free. Preserve
   `GH_TELEMETRY=0`, `TLDR_AUTO_UPDATE_DISABLED=1`, presence-only probes,
   empty-home tests and stateful-fake no-write snapshots. Preserve online
   and smoke opt-ins, unsupported-input refusal and all platform floors.
5. Extend the no-heredoc, no-here-string and no-process-substitution scan to
   the relocated doctor/setup and the frontend path that reaches them;
   keep coverage of `lib/terminal.sh` and `lib/bootstrap/*.sh`. No Bash 3.2
   regression or newly required utility is acceptable.
6. Setup alone provisions third-party tools; payload backends only call
   their repos' documented installers. Preserve installer digests, channels,
   tool floors, clone branches, step IDs, HUMAN policy, no-rc flags,
   shared-prefix handling, conflict checks and protected nvm handling.
7. Do not run sudo, chsh, authentication, shell init or Git LFS init on the
   user's behalf as a consequence of this refactor. HPC environment changes
   need allocations and remain outside scope. No payload upgrade on the six
   live hosts is part of this delivery. Required existing CI/E2E fixture
   installations remain part of the acceptance workflows.
8. No target is added or removed. Preserve target modes and role selection;
   current counts are `50/57/56/59/55/55/27` in existing fixture role order.
   Re-derive if concurrent work changes the base; do not overwrite it. The
   tmux source comment may change to name the public setup command, but no
   tmux runtime behavior changes. No reload is needed for that comment.
9. Preserve AI ownership/policy parity, encrypted-target handling and pinned
   WebP/terminfo bytes. Never log config contents, credentials or private
   backups. Use exact reviewed targets and full chezmoi arguments,
   `--exclude=dirs`, no routine force apply and inspected private parents.
10. Keep test environment isolation and fixture Git override clearing;
    `DOTFILES_TEST_*` inputs survive. No tests use live credentials or
    daemons; network stays in explicit fixture-provisioning/E2E steps.
11. One active writer per checkout and file. No reset, stash, overwrite,
    force push or history rewrite to simplify integration. Completed
    tracked handoffs are removed before candidate tests, not after CI.

## Caller migration and file ownership

Ownership includes implementation, tests and documentation needed by each
task. The table is a minimum discovered inventory, not permission to ignore
a new caller on an advanced base. Search again before implementation. Add
any newly necessary file to one owner's ledger before editing it; another
owner must release it before reassignment. Newly discovered shared files
default to I until explicitly assigned. A row marked audit is not a request
to make an unnecessary edit. Within a table cell, filenames after a fully
qualified path share that path's directory unless another directory is
explicitly given; `steps.sh` following `lib/bootstrap/checks.sh`, for example,
means `lib/bootstrap/steps.sh`, not a new root file.

### Unix owner U: separate Unix worktree

| Files | Work |
| --- | --- |
| `dotfiles`; root `doctor.sh`, `setup-host.sh`; `scripts/payload-update.sh`; new `scripts/commands/doctor.sh`, `setup.sh`, `payloads-sync.sh` | Direct dispatch, moves/deletions, root calculation, public advice and internal sentinel |
| `lib/bootstrap/checks.sh`, `steps.sh`, `steps-human.sh`, `steps-files.sh`, `steps-packages.sh`, `steps-runtimes.sh`, `steps-archives.sh` | Source helper, HUMAN/retry instructions, doctor advice and relevant caller comments |
| `lib/bootstrap/manifest.sh`, `platform.sh`, `version.sh`, `fetch.sh`, `steps-common.sh`, `steps-guard.sh` | Audit comments and retained module semantics; edit only obsolete descriptions |
| `tests/test_cli_unix.py` | Nested backend fixtures, contract and retirement tests |
| `tests/doctor.sh`, `tests/setup-host.sh`, `tests/payload-update.sh` | Direct backend behavior fixtures and expected public advice |
| `tests/shell-profile.sh`, `tests/test_chezmoi_guard.py`, `tests/test_chezmoi_provision.py` | Fixture layout, real frontend/source routing and configured-host assertions |
| `tests/e2e-harness.sh`, `tests/e2e/lib/steps.sh`, `tests/e2e/lib/blocks.sh` | Public E2E calls, negative platform/root cases, nested planted-backend fixtures and HUMAN parsing |
| `lib/terminal.sh`, `lib/chezmoi-guard.sh`, `scripts/chezmoi-update.sh`, `tests/e2e/lib/flow-unix.sh` | Audit/regression ownership; no runtime changes expected |

### PowerShell owner P: separate PowerShell worktree

| Files | Work |
| --- | --- |
| `dotfiles.ps1`; root `doctor.ps1`, `setup-host.ps1`; `scripts/payload-update.ps1`; new `scripts/commands/doctor.ps1`, `setup.ps1`, `payloads-sync.ps1` | Native moves/deletions, self-location, direct dispatch, comments/help and advice |
| `lib/bootstrap.ps1`, `lib/chezmoi-guard.ps1` | Relevant advice and caller descriptions; retain shared function and scope behavior |
| `tests/cli.ps1`, `tests/bootstrap.ps1`, `tests/payload-update.ps1`, `tests/powershell-profile.ps1`, `tests/terminal.ps1` | Nested backend fixtures, statuses/streams/preferences, emitted command assertions and retirement tests |
| `tests/e2e-harness.ps1`, `tests/e2e/run.ps1`, `tests/e2e/lib/blocks.ps1`, `tests/e2e/lib/flow-win.ps1`, `tests/e2e/lib/snapshot.ps1`, `tests/e2e/lib/steps.ps1` | Windows fixture layouts, public commands, parser assertions and no-write snapshots; edit only path-dependent cases |
| `lib/terminal.ps1`, `scripts/chezmoi-update.ps1` | Audit/regression ownership; no runtime changes expected |

### Integration owner I: all shared files, after worker handoff

| Files | Work |
| --- | --- |
| `.pre-commit-config.yaml`, `tests/test-entrypoints.sh` | Hook selectors and their expectation maps; include every new backend in relevant CLI/bootstrap/doctor/setup/payload/chezmoi/E2E checks and correct shell dialect |
| `tests/bootstrap-manifest.sh`, `tests/test_bootstrap_manifest.py` | Git fixture copy lists, backend parse paths, `path()` dispatch for `scripts/commands/`, forbidden constructs/commands and mutation fixtures |
| `tests/test_payload_download.py` | Shared Unix/PowerShell backend command construction and download safety fixtures |
| `tests/run.sh`, `tests/run.ps1`, `tests/cli.sh`, `tests/bootstrap-windows.sh`, `tests/e2e-harness-windows.sh`, `tests/powershell-profile.sh`, `tests/terminal.sh` | Runners, optional native bridges, terminal PTY bridge and explicit PowerShell parse list; retain suite names and exactly-once execution. The payload bridge is in U-owned `tests/payload-update.sh` |
| `tests/fixtures/chezmoi/targets.tsv`, `tests/chezmoi_source_support.py`, `tests/test_chezmoi_rendered.py`, `tests/test_chezmoi_source_state.py`, `tests/chezmoi.sh`, `tests/chezmoi.ps1` | Audit exact targets/counts/modes and support fixture copies; no target changes expected |
| `tests/fixtures/bootstrap/artifacts/claude-install`, `tests/fixtures/bootstrap/artifacts/homebrew-install` | Caller comments in fake installers; preserve fixture behavior |
| `tests/fixtures/bootstrap/config/apt/common.txt`, `tests/fixtures/bootstrap/config/apt/lab-ubuntu.txt`, `tests/fixtures/bootstrap/config/brew/core.Brewfile`, `tests/fixtures/bootstrap/config/brew/cli.Brewfile`, `tests/fixtures/bootstrap/config/hpc-login-env.yml` | Audit only: references to retained `tests/setup-host.sh` are valid |
| `tests/test_ai_integration.py`, `tests/claude-customizations.cjs`, `tests/COVERAGE.md` | Current installation descriptions and test coverage map; no kit implementation changes |
| `.github/workflows/ci.yml`, `.github/workflows/bootstrap-e2e.yml` | Change Linux/macOS kit provisioning to public payload CLI; audit E2E full matrix and exact-candidate triggers without changing pins or gates |
| `tests/e2e/README.md`, `tests/e2e/inside.sh`, `tests/e2e/run.sh`, `tests/e2e/lib/common.sh`, `tests/e2e/lib/flow-other.sh`, `tests/lib/environment.sh`, `tests/lib/environment.ps1` | Audit E2E orchestration, generic flow and environment isolation; edit only if a demonstrated path migration requires it |
| `config/payloads.tsv`, `config/bootstrap/tools.tsv` | Header and human diagnostic text only; preserve functional inventory, digests, versions and channel |
| `home/dot_tmux.conf` | Comment names `dotfiles setup`; no behavioral edit |
| `home/dot_local/bin/executable_dotfiles`, `home/dot_local/bin/dotfiles.ps1`, `home/dot_aliases`, `home/dot_profile`, `home/dot_zshrc`, `home/Documents/PowerShell/profile.ps1`, `home/Documents/WindowsPowerShell/profile.ps1`, `home/.chezmoiignore` | Audit routing/target selection; no functional edits expected; only I may resolve a demonstrated integration need |
| `AGENTS.md`, `README.md`, `docs/bootstrap.md`, `docs/dependencies.md`, `docs/payloads.md`, `docs/shell.md`, `docs/testing.md`, `docs/updates.md`, `docs/hosts.md` | Canonical public instructions, internal layout, retirement, no-write rules, probes and rollout commands |
| `.agents/skills/dotfiles-bootstrap/SKILL.md`, `.claude/skills/dotfiles-bootstrap/SKILL.md` | Identical bodies; preserve Claude-only `disable-model-invocation: true` frontmatter and replace the compatibility promise with the public/frontend/backend boundary |
| `docs/handoff/unified-cli-backend-consolidation-plan.md`; task-owned ledger under `.worktrees/cli-backend-handoff/` | Preserve approved plan first, record execution evidence, then remove completed tracked plan before the final candidate |

Do not edit the root `CLAUDE.md` import stub. Existing test entrypoints,
fixture names, step IDs and historical Git content need not be renamed.
New regression cases belong in the existing owned suites; no new runner is
required by this plan.

### Required migration by caller category

- Frontends: replace all six production backend references with formal
  `scripts/commands/` paths; preserve direct exec/call behavior.
- HUMAN and retry output: include Unix `steps_rerun`, H1 installer notes,
  S2 allocation rerun, S3 recovery, S4 runtime/inspection notes, H7 payloads
  and doctor, Windows HW blocks, doctor foreign-source advice and payload
  retry strings. Public usage text must not recommend a deleted path.
- CI: both real kit installs in `ci.yml` become
  `HOME="$RUNNER_TEMP/kit-home" ./dotfiles payloads sync kit`. Keep the
  explicit temporary HOME and existing isolation; no installed launcher is
  required in that fresh home.
- E2E: positive flows already exercising the public CLI stay there. Migrate
  remaining generic-platform, WSL/lab mismatch, missing-Lmod and root-refusal
  calls in `tests/e2e/lib/steps.sh` to the public CLI without weakening
  expected refusal. Synthetic E2E repositories contain the real frontend
  plus nested backend stubs. Move malicious backend plants, resets, clone
  symlinks, captured sudo argv and failure assertions together.
- Tests: preserve backend-focused isolation while updating copied trees;
  public routing/source-selection tests must keep a real frontend. Do not
  make a fake root shim just to keep old fixtures passing. Shared download
  tests and manifest mutation tests cover both native paths.
- Lint/parse: update positive and negative hook-selection assertions, not
  just regexes. Include extensionless `dotfiles`, POSIX payload backend and
  Bash doctor/setup in their proper dialects. Update explicit PowerShell
  parse lists and bootstrap no-write syntax scans.
- Docs/skills: replace executable examples and obsolete compatibility
  promises, including hosts probes, setup/payload terminology and dependency
  diagnostics. Keep existing heading anchors/step IDs when links depend on
  them. Describe internal scripts as backends, not new supported entrypoints.
- Profiles/launchers: current real callers already use the frontend; update
  their test fixtures. Do not replace login-hook paths or make startup
  invoke a manual CLI command.

## Review focus and regression evidence

Each task gets a fresh read-only reviewer who did not implement it. Review
the entire owned diff, tests and evidence, not just the implementation file.
The reviewer can reject the task independently. Record findings, resolutions,
commands and missing native evidence in the ignored ledger. Review is not
permission for the reviewer to edit another checkout.

1. **Nested roots and hostile paths (U/P):** backend location two parents
   below checkout, a foreign cwd, spaces and apostrophes, linked worktree,
   configured source different from checkout and no config. Assert actual
   config/lib/inventory selection and argument boundaries.
2. **Missing formal backend (U/P):** plant a retired-path tripwire in a
   disposable fixture; assert a single status-1 failure and zero tripwire
   invocations. Real source tree contains none of the six retired paths.
3. **Interactive/status semantics (U/P):** Unix PTY stdin/stdout/stderr,
   same PID, literal input, Ctrl-C and no surviving child; setup refusal/EOF
   and status 3. PowerShell streams 1-6, object identity, stale and native
   LASTEXITCODE, WhatIf/Confirm, terminating failure and location restoration.
   Keep existing help home-write measurement inside the running child.
   P also owns a harmless ordinary-token native Windows console comparison
   of baseline and candidate Ctrl+C behavior; preserve observed cancellation
   and child cleanup rather than asserting Unix status 130 on Windows.
4. **Advice correctness (U/P/I):** capture HUMAN and retry text for no
   config, same/different configured source, maintenance, missing launcher,
   quoted paths, lock contention and download failure. Replay safe printed
   commands against fakes to prove source and argv; never run privileged
   HUMAN instructions as a test.
5. **Selection and fixture coverage (I):** stage new/deleted task paths
   deliberately before tracked-file scans. Prove new paths select all
   relevant hooks and forbidden constructs in relocated files are detected.
   Prove E2E negative fixtures still fail for their planted violation.

### Retirement acceptance

Add assertions to the existing CLI suites that the real repository lacks
all six retired production paths on disk and in the staged tracked-file
inventory, including symlinks/dangling links. Test
missing formal backend behavior with retired-path tripwires separately.
Do not require an artificial exact OS error code for invoking a nonexistent
file; assert no successful compatibility execution and no side effect.

Run the following inventory, then classify every hit by meaning:

```sh
rg -n --hidden -g '!.git/**' -g '!.worktrees/**' \
  '(doctor\.(sh|ps1)|setup-host\.(sh|ps1)|payload-update\.(sh|ps1)|bootstrap_payload_hook)' .
rg -n --hidden -g '!.git/**' -g '!.worktrees/**' \
  '(compatibility (entrypoints|interfaces|backends)|original doctor/setup|scripts/commands)' .
```

New formal `scripts/commands/doctor.*` paths and retained `tests/...` names
are valid hits. Explicit retirement prose and clearly labeled negative
fixtures may name deleted paths. Historical Git objects are not live
callers; never rewrite them. The active handoff contains migration examples
but is removed from the final candidate. A runtime invocation, copy list,
lint selector or positive example using a retired production path is a
failure. No broad allowlist of all `docs/` or `tests/` is acceptable.

Inspect dynamic path construction too (`Join-Path`, root suffix stripping,
fixture writes and helper return values): a zero literal grep count alone
does not prove retirement. Confirm `bootstrap_payload_hook` has no remaining
runtime consumer after its replacement.

## Execution workflow

Use distinct task-owned names on collision. The primary deployed checkout
stays on main; all implementation writes happen in project-local worktrees.

| Worktree | Branch | Writer |
| --- | --- | --- |
| `.worktrees/cli-backend-integration` | `task/cli-backend-integration` | I, coordinator and shared-file integrator |
| `.worktrees/cli-backend-unix` | `task/cli-backend-unix` | U only |
| `.worktrees/cli-backend-powershell` | `task/cli-backend-powershell` | P only |
| `.worktrees/cli-backend-handoff/` | Not a checkout | I's durable ignored ledger, evidence and recovery references |

Dependencies are `T0 -> (T1 || T2) -> T3 -> T4 -> T5 -> T6 -> T7`.
Read-only reviews may overlap independent work. I can prepare shared docs in
its own worktree during T1/T2, but must not edit worker-owned files. After
both workers stop, the integrator incorporates their branches or reviewed
snapshots and explicitly takes over any remaining platform fixes. If another implementer receives integration
ownership, I stops writing that checkout until it is returned.

The two platform moves can temporarily break shared checks owned by I.
Never bypass commit hooks or commit a tree whose required pre-commit checks
fail. A platform task can hand off a reviewed, durable uncommitted patch
instead of a commit: the worker stages only its complete owned changes and
stops writes; I records `git diff --cached --binary --full-index`, status,
base HEAD, exact paths and content hashes in a separate ledger file for that
worker. Include all new files in the staged snapshot and require no
unexplained unstaged/untracked changes. I alone writes the ledger; workers
return their review/test evidence through messages.

I applies such snapshots sequentially to integration only after
`git apply --check --index` succeeds, checks the resulting owned-file content
against the reviewed snapshot, and commits only after shared gates pass.
Ordinary merges remain preferred for independently green committed worker
branches. Preserve original worker trees and durable snapshots until the
integrated commit has verified their content. Branch ancestry alone is not
proof that an uncommitted patch was integrated.

### T0: Preserve the approved handoff and establish the baseline

**Owner:** I. **Files:** Handoff and ignored ledger only.
**Consumes:** User-approved prompt and current checkout state.
**Produces:** A durable approved-plan commit and a common worker base.

- [ ] Read instructions and status/diffs/untracked files in all involved
  checkouts; identify active writers. Reconcile scope against current main
  without changing unrelated work. Verify `.worktrees/` is ignored by this
  repository before creating it.
- [ ] Create the integration branch/worktree from the reviewed current
  base. Copy the exact approved handoff into it, stage only that file, run
  document checks and required pre-commit, and commit it. No implementation
  begins before this preservation commit.
- [ ] Verify the saved blob matches the original bytes, the commit is
  reachable from the integration branch, `git cat-file` can read it, and
  the integration worktree has the same file. Record branch/commit/blob in
  the durable ledger. Only then remove the exact task-owned untracked
  original from the primary checkout. If it changed, preserve both and
  resolve the difference; never delete an unexplained copy.
- [ ] Run `./tests/run.sh --ci --check-prerequisites`, record existing
  failures and tool availability. Do not install or alter a live home to
  hide a missing prerequisite. Optional native checks may be recorded as
  unavailable locally but remain required in native CI.
- [ ] Create U and P worktrees from the same approved-plan commit. Give
  each agent the binding design, exact worktree, owned file set and ledger
  reporting protocol: return evidence by message for I to record. Obtain an
  independent T0 preservation/scope review.

### T1: Unix backend migration and its callers

**Owner:** U. **Files:** All U rows above, no shared-file edits.
**Consumes:** T0 base and public contract.
**Produces:** Formal Unix backends, public dispatch, source helper and
Unix-specific fixtures/advice, with no old production paths.

- [ ] Extend `tests/test_cli_unix.py` with
  `test_retired_production_paths_absent`,
  `test_missing_backend_never_uses_retired_path` and
  `test_nested_backends_use_their_own_checkout`. Assert the U paths are
  absent, frontend uses nested fakes, and missing backend returns 1 without
  a tripwire event. Preserve the existing argv, help and PTY cases.
- [ ] Add/adjust advice cases in doctor/setup/payload suites for the source
  and quoting matrix above; fixture helper tests assert
  `bootstrap_payload_source ROOT` returns a path, never a shell command.
  Run focused cases and confirm failures identify the current old layout.
- [ ] Move the three implementations, update self-location and direct
  frontend dispatch, retain native parsers and sentinel. Update source
  helper consumers, HUMAN/retry text, comments and owned fixture copy trees.
- [ ] Migrate Unix E2E negative public invocations and planted backend
  fixtures together. Keep the real frontend in synthetic repositories and
  assert failure still comes from the planted unsafe behavior.
- [ ] Run the U focused commands below. Shared manifest, selector and
  download-builder checks may remain red until T3; in particular,
  `tests/payload-update.sh` also invokes shared download and optional
  PowerShell tests. Report the exact dependency failures without weakening
  them or claiming a full pass. Run full pre-commit; do not commit through
  a failure or skip a hook to make the worker branch committable.
- [ ] Request independent task review of the complete U diff. Fix owned
  correctness findings and rerun affected tests. If all required checks
  pass, commit only U files; otherwise use the staged binary snapshot
  protocol above. Hand I the reviewed diff/base, test evidence and exact
  shared dependencies. Stop writes before integration; expected dependency
  failures must be closed and re-reviewed in T3.

### T2: PowerShell backend migration and its callers

**Owner:** P. **Files:** All P rows above, no shared-file edits.
**Consumes:** T0 base and public contract.
**Produces:** Formal PowerShell backends, native dispatch, advice and
PowerShell-specific fixture migration, with no old production paths.

- [ ] Add retirement and nested-root cases to `tests/cli.ps1`: absent P
  production paths; a missing formal backend with old-path tripwire; exact
  native parameter bindings from public GNU options. Assert default host
  `win`, quoted item/tier values and unsupported Unix option refusal.
- [ ] Retain and extend the real-process status, streams, preferences,
  WhatIf/Confirm, environment and location cases described above. Test
  root help without config/tools and the existing in-child no-write probe.
  Explicitly distinguish initial ShouldContinue refusal (2) from per-step
  ShouldProcess refusal (3). Run to establish failures for the old layout.
- [ ] Prepare a harmless fake-backend cancellation probe in P-owned
  `tests/cli.ps1`, and compare baseline/candidate behavior in an ordinary
  Windows console using the documented limited-token procedure. No real
  installer runs. Record Ctrl+C propagation and child cleanup without
  imposing a guessed numeric Windows cancellation status. If unavailable
  locally, keep this specific evidence obligation pending for T6; CI and
  redirected-process tests do not establish real-console cancellation.
- [ ] Move the three backends, compute checkout roots two levels above,
  change only the dispatch paths and necessary native caller/advice logic.
  Preserve `&`, splatting, status reset/capture and backend scopes.
- [ ] Update P fixture copies, public command expectations, snapshots and
  E2E block parsing; keep native parameter tests focused on the internal
  files and public integration tests on `dotfiles.ps1`.
- [ ] Run P focused commands where PowerShell is available. Record local
  skips explicitly; a parser-only pass is not native Windows behavior
  evidence. Run required pre-commit and report shared dependencies as in T1.
- [ ] Obtain independent task review and resolve owned findings. Commit
  only P files if required checks pass; otherwise use the staged binary
  snapshot protocol, without bypassing hooks. Hand off reviewed base/diff,
  evidence and shared dependencies. Stop writes before integration; T3
  closes and re-reviews dependency failures.

### T3: Shared integration, selectors and fixture closure

**Owner:** I. **Files:** I implementation/test/config/workflow rows; U/P
files only after explicit ownership transfer.
**Consumes:** Independently reviewed T1 and T2 branches or durable staged
binary snapshots, with exact dependency-failure records.
**Produces:** One complete candidate tree with all runners and safety gates
following formal backends.

- [ ] Confirm workers/tests have stopped. Inspect full commit ranges and
  use ordinary ancestry-preserving merges for committed work; for staged
  snapshots use the checked sequential patch-transfer protocol above.
  Verify transferred content before shared edits, record any subsequent
  integration corrections, and preserve the original snapshots. Do not
  cherry-pick by default, squash, rebase or overwrite concurrent work.
- [ ] Update shared download tests and manifest fixture copy/path maps.
  In particular, `test_bootstrap_manifest.py` must route
  `scripts/commands/` mutations into the fixture; copying a moved file
  without updating `path()` leaves the test checking the wrong source.
- [ ] Update hook regexes plus `tests/test-entrypoints.sh` assertions.
  Update `SETUP_GIT_FILES`, heredoc offender lists and explicit PS parse
  lists. Add mutation/selection assertions that fail when a relocated
  backend escapes its former safety gate. Keep shell dialects correct.
- [ ] Migrate both CI kit installation calls to the public frontend. Audit
  full bootstrap E2E matrix/triggers and preserve the existing cache-off
  acceptance policy and Windows cleanup phase.
- [ ] Audit all runner/bridge registrations, shared chezmoi fixtures,
  launchers/profiles and config diagnostics. Preserve exact target set and
  counts; do not change launcher or profile behavior to accommodate an
  incomplete fixture. Keep retained test suite names.
- [ ] Stage exact task additions/deletions before checks that use
  `git ls-files`; inspect staged diff, then run shared focused tests and the
  retirement inventory. Restage only reviewed formatter edits.
- [ ] Run `./tests/run.sh --ci` and `pre-commit run --all-files`. Obtain an
  independent integration review of dependency direction, fixture validity,
  no-write enforcement, hook reachability, source binding and stream/status
  behavior. Commit the reviewed integration work.

### T4: Canonical instructions and rollout readiness

**Owner:** I. **Files:** All I documentation/skill rows and any coordinated
advice correction in transferred implementation files.
**Consumes:** Integrated runtime and tests.
**Produces:** Complete current-state documentation and a host acceptance
checklist with no retired positive examples.

- [ ] Update README layout/interface and AGENTS conventions: root scripts
  are frontends, command implementations are internal, `lib/` is shared,
  and login hooks retain their role. Move the syntax guard wording to new
  paths. Keep AGENTS below 28,000 bytes.
- [ ] Update every canonical doc row in the ownership table, especially
  `docs/hosts.md` doctor probes and `docs/updates.md` payload instructions.
  Remove compatibility promises. Explain explicit-checkout recovery and
  existing installed launchers without requiring new PATH changes.
- [ ] Update both project skill bodies identically. Retain safety/HUMAN
  instructions and step anchors; do not modify the root CLAUDE stub or
  global policy files.
- [ ] Check HUMAN/retry command examples against actual output and safe
  fake execution, including quoting and configured-other-source behavior.
  Audit all remaining old-path hits using the retirement rules.
- [ ] Read hosts/updates again and prepare each host's pre/post probe
  commands using the public CLI. This relocation alone needs no re-init,
  new directory preparation or hook replacement. If the actual diff creates
  such a need, stop and apply the documented breaking-rollout protocol
  before landing, including confirmed maintenance on every host.
- [ ] Run document, manifest, mirrored-skill and E2E harness checks, then
  required pre-commit. Obtain independent documentation/operability review
  covering every public example and host recovery path; commit scoped edits.

### T5: Whole-change review, frozen candidate and main landing

**Owner:** I, with a fresh read-only whole-change reviewer.
**Consumes:** T1-T4, resolved task reviews and current main.
**Produces:** The exact all-green candidate on local and remote main.

- [ ] Review the full diff against the real starting base. Reviewer checks
  all invariants, six-path retirement, file ownership closure, test strength,
  native evidence and the absence of new dependencies/features. Resolve
  correctness, security, compatibility and required-test failures; a retry
  limit does not turn them into accepted limitations.
- [ ] Preserve the approved plan commit in branch ancestry. Put lasting
  instructions in canonical docs, then delete this completed tracked
  handoff and any task-owned tracked scratch files from integration. Stage
  exact deletions. Keep the ignored active ledger until rollout acceptance.
- [ ] Run final focused checks, `./tests/run.sh --ci`,
  `pre-commit run --all-files` and `git diff --check`. Inspect the final
  staged and unstaged diff; account for every file and formatter change.
  Commit the complete clean candidate, including tracked cleanup.
- [ ] Freeze `C` as the full integration HEAD. Push exactly C to unique
  task-owned `ci/cli-backend-consolidation` and
  `e2e-ci/cli-backend-consolidation` branches with normal pushes. No force
  updates. Poll workflow results by branch and verify each run's full
  `headSha == C`, not only its name or latest green badge.
- [ ] Require every `ci.yml` Linux/macOS/Windows job and every full
  `bootstrap-e2e.yml` job to succeed for C: plan, lab-ubuntu, wsl-ubuntu,
  other, sherlock, marlowe, mac and win, with acceptance caches disabled.
  A cancelled/skipped required job is not success. Record URLs and native
  limitations in the ledger; never combine successes from different SHAs.
- [ ] Refresh origin main and inspect the primary checkout. Require both
  local and remote main to be ancestors of C and preserve unexplained local
  commits/changes. If main advanced beyond C's ancestry, merge that work
  into integration, review the combined diff and rerun local plus both
  candidate workflows for the new C. A concurrent push race follows the
  same process, without reset/rebase/force.
- [ ] With the primary checkout clean and not in use by another writer,
  fast-forward main to C, push normally, and verify local/remote main equal
  C. Verify main's resulting three-platform CI. Do not add a post-green
  cleanup or documentation commit to the delivered candidate.
- [ ] Obtain independent landing review of SHA identity, workflow job
  coverage, ancestry and cleanup inclusion. Main landing is not host rollout
  completion and creates no version tag or GitHub Release.

### T6: Actual rollout and acceptance on all six hosts

**Owner:** I coordinates; one explicit owner per host.
**Consumes:** Landed C with main CI, existing access and canonical procedures.
**Produces:** Actual verified acceptance on lab-ubuntu, wsl-ubuntu, mac,
sherlock, marlowe and win, or precise outstanding blockers.

- [ ] Re-read `docs/hosts.md` and `docs/updates.md`. Default to their Lab-first,
  serial host rollout; the user's allowance for parallel host work is an
  option, not a reason to weaken this ordering. If parallelism is used after
  Lab acceptance, assign disjoint hosts and record owners before writes.
  Never have two owners updating one host.
- [ ] Re-resolve aliases and use only existing SSH/control connections;
  never authenticate, answer MFA, copy keys or enable forwarding. For
  Sherlock, first use the configured provisioning project's pinned `shk`
  doctor/rules, then read `/etc/agents/AGENTS.md` and its four topic files
  through the existing master, including after compaction. Do not add a kit
  pin to dotfiles. Respect Marlowe login env and site restrictions.
- [ ] Before each update, record nonsecret HEAD/branch/status, managed
  count, maintenance, full-argument chezmoi status and offline public doctor
  rows. Use the explicit old checkout's `dotfiles` frontend, which already
  exists on the baseline. Preserve any preexisting drift privately, with
  correct mode/ACL, and classify it before proceeding. Never overwrite drift
  or call it a task-generated change without evidence.
- [ ] Run the canonical login update or full-argument manual update from
  hosts/updates, with `--exclude=dirs`, safe mode flags and no routine force.
  Pre-pull login hooks retain their paths and behavior, so they can update
  the source containing relocated backends. Old installed launchers still
  call the unchanged frontend path; that frontend and all new backends land
  in the same Git revision. Do not manually copy backend files or mix
  revisions on a host. Avoid starting CLI operations during a checkout
  update; introduce no new lock protocol.
- [ ] Do not refresh live payloads just for this task. The user's explicit
  no-payload-update scope overrides generic pre-deployment sync guidance;
  use read-only readiness checks. If a genuinely missing prerequisite
  prevents acceptance, report it and the smallest additional action needed.
  Existing CI/E2E installation gates are separate from live payload updates.
- [ ] On Windows, every home/Git/config write runs under the ordinary
  limited token. Administrator SSH is only for allowed metadata and one-off
  task management. Use the hash-checked Interactive-logon/RunLevel Limited
  task procedure with no recurring trigger; refuse elevation and require
  the user logged on. Do not persist PATH or rerun a task just to read logs.
- [ ] After update, require a clean main at C (or a deliberately reviewed
  newer landed descendant, recorded separately), empty full-argument
  `status --exclude=dirs`, expected managed count, equal AI target renders
  without printing contents, no worsened doctor row, no leftover maintenance
  marker and passing shell probes. Verify all six old production paths are
  absent and new backends present under that host's selected checkout.
  A newer descendant requires its own canonical landing evidence and
  reviewed acceptance expectations; never attribute C's workflow results
  to it or reset the host to conceal a concurrent main advance.
- [ ] From outside the checkout, exercise explicit and installed public
  help/doctor on each platform; assert the validated source is used. Use
  read-only setup `--check` only with host-correct environment, interpreting
  status 3 as pending work, not permission to install. Do not run payload
  sync merely to demonstrate dispatch. Use existing read-only evidence for
  payload readiness and CI/fakes for execution semantics.
- [ ] Prove login behavior with the exact per-host procedures and guards
  in hosts.md. Distinguish a noninteractive Windows updater call from the
  ordinary user's real profile hook; use its separate console acceptance
  procedure when claiming real hook acceptance. Close P's pending harmless
  native-console cancellation comparison if not already verified; use a
  separate hash-checked baseline fixture bundle, without resetting the live
  checkout. Native fixture/CI success and actual existing-home rollout are
  not fresh-machine acceptance.
- [ ] Have a read-only reviewer check each host's pre/post evidence and
  exceptions. A sleeping host, absent master, logged-off Windows user or
  unresolved drift is a real blocker; keep the host pending and do not claim
  all-six completion. Request only the missing access/action, not blanket
  permission to repeat already authorized work.

### T7: Recovery-aware cleanup and completion

**Owner:** I. **Consumes:** All six host acceptances and verified landing.
**Produces:** Clean task state, preserved necessary recovery data and a
precise delivery report.

- [ ] Confirm task agents, tests and host probe processes have stopped.
  Inspect each task worktree's status, staged/unstaged diffs and untracked
  files. Require its branch tip to be an ancestor of landed main. Preserve
  unexplained or unmerged work; never force cleanup. For snapshot-based
  handoff, additionally verify the reviewed patch was integrated, including
  recorded reviewed corrections, and is recoverable from landed Git history.
  Only then clear the exact task-owned duplicate staged/worktree changes
  with scoped canonical Git commands and recheck cleanliness. Never use a
  blanket reset or treat ancestry of the unchanged worker base as proof.
- [ ] Remove only verified task worktrees with `git worktree remove`, then
  their merged branches with `git branch -d`. The integration branch's plan
  commit remains reachable through main history. Do not delete the root
  `.worktrees/` directory or another task's checkout.
- [ ] Delete only this task's remote candidate branches after acceptance.
  Prune each host's remote refs using the canonical hosts procedure;
  Windows fetch/prune is an ordinary-token write. Verify no lingering probe
  task, child process or exact temporary artifact remains.
- [ ] Inspect the ignored ledger and temporary artifacts individually.
  Remove completed nonsecret reports, logs and bundles only after their
  checks are complete; retain private drift backups, ownership manifests,
  libraries, credentials and recovery state still needed. Nothing goes in
  `.git/`; `/tmp` is never the only copy of unfinished work.
- [ ] Run read-only final status/worktree/ancestry checks and obtain an
  independent cleanup review. Report main push, actual host acceptance,
  remaining exceptions and cleanup separately. No tag/version is selected
  and no GitHub Release is created without new explicit authorization.

## Verification commands and evidence boundaries

Run focused suites after their owned changes, then full checks after
integration and again only when a new candidate or unresolved concern
requires it. Execute from the appropriate worktree root. Existing optional
tool skips are reported, not converted into claims of native verification.

```sh
# Unix owner
./tests/cli.sh
./tests/doctor.sh
./tests/setup-host.sh
./tests/payload-update.sh
./tests/shell-profile.sh
./tests/chezmoi.sh
./tests/e2e-harness.sh

# Shared integration and documentation
./tests/bootstrap-manifest.sh
./tests/bootstrap-windows.sh
./tests/e2e-harness-windows.sh
./tests/powershell-profile.sh
./tests/terminal.sh
./tests/test-entrypoints.sh
./tests/markdown-links.sh
# bootstrap-manifest checks mirrored skill bodies, retaining tool frontmatter.

# Final local gate (not a substitute for either candidate workflow)
./tests/run.sh --ci --check-prerequisites
./tests/run.sh --ci
pre-commit run --all-files
git diff --check
```

```powershell
# PowerShell owner and native Windows evidence
pwsh -NoProfile -File tests/cli.ps1
pwsh -NoProfile -File tests/bootstrap.ps1
pwsh -NoProfile -File tests/payload-update.ps1
pwsh -NoProfile -File tests/powershell-profile.ps1
pwsh -NoProfile -File tests/terminal.ps1
pwsh -NoProfile -File tests/e2e-harness.ps1
pwsh -NoProfile -File tests/run.ps1 -CI
```

Bootstrap E2E is required for this change even if a workflow file needs no
edit. Push-triggered `e2e-ci/**` selects the complete seven-case matrix,
including `other`; six-host live rollout covers the six existing homes.
Record these as different evidence sets. Never run a real provisioning
suite in a live home as a shortcut for missing E2E evidence.

Tracked-file checks use `git ls-files`, so deliberately stage task-owned
renames/additions/deletions before the final implementation checks. Do not
use `git add .`. For this planning-only untracked handoff, run the ASCII
hook explicitly with `pre-commit run english-documentation --files
docs/handoff/unified-cli-backend-consolidation-plan.md` and call the existing
`tests/test_markdown_links.py` validator with tracked files plus this exact
new path; ordinary all-files checks alone cannot see it. Inspect final
status to ensure document validation did not leave implementation edits.

## Blockers, recovery and completion standard

A missing access path, required tool, approved design decision or native
test environment is a concrete blocker. State the failing command, observed
result, affected gate and smallest user action. Continue independent safe
work. Do not weaken a test, add an implicit fallback or create a substitute
green result. If automatic approval review rejects an operation, report
the action and stated reason separately; do not bypass the review mechanism.

Before landing, leave incomplete branches/worktrees and the approved plan
intact until failures are resolved. A failed rollout may have advanced Git
before chezmoi apply refused; inspect both states. Preserve private drift
and recovery copies, use maintenance where the documented recovery requires
it, and reconcile only exact reviewed targets. Do not roll main backward or
reset a host. If source correction is needed, make a scoped forward fix or
revert commit through the same local, candidate CI/E2E and main gates; a
repair commit is a new candidate, never an excuse to reuse C's evidence.
Any recovery outside these boundaries requires a specific user decision.

Completion requires all of the following:

- Public CLI behavior is stable; six retired paths are absent; every formal
  caller is migrated; no shim, fallback, duplicate implementation or cycle.
- Backend roots, native scopes, streams, TTY/signals, statuses, advice and
  safe source selection are tested on their relevant platforms.
- Safety invariants, target membership, pins and unrelated work are intact.
- Every task has independent review and the full integrated change has a
  separate review. Canonical docs/skills, fixtures, runners, parse/lint and
  hook-selection coverage agree with the implementation.
- The same final candidate, including tracked-artifact cleanup, passes
  local gates, all three-platform CI jobs and complete bootstrap E2E; main
  is fast-forwarded/pushed to it and main CI is verified.
- All six actual homes pass their pre/post acceptance with no unresolved
  task regression. A partial rollout is reported as partial.
- Task processes, worktrees, merged branches, remote candidate branches and
  completed artifacts are safely cleaned; necessary recovery data remains.
- The delivery report distinguishes source landing, host rollout and the
  intentionally unperformed tag/GitHub Release operations.

No unresolved product choice is required to execute this design. Actual
concurrent changes, unavailable access or unexplained host drift can create
new decisions; resolve only those concrete cases with the user.

## Prompt for the executing agent

> Implement `docs/handoff/unified-cli-backend-consolidation-plan.md` in full.
> I have reviewed and approved its binding design and implementation plan.
> This prompt activates execution authorization; the earlier planning
> session was authorized only to explore and write the handoff.
>
> Read AGENTS.md and current status/diffs/branches/worktrees first. Preserve
> other sessions' work and use the current repository, not a historical
> baseline. Before implementation, save this exact approved handoff in a
> scoped commit on the integration branch and verify a reliable Git copy
> before removing its original uncommitted copy.
>
> Use parallel Unix and PowerShell implementers in separate worktrees under
> this project's `.worktrees/`, one writer per checkout. Follow the complete
> file ownership table; one integrator owns shared files. Require independent
> task reviews and a fresh whole-change review. Retire all six specified old
> production entrypoints, call formal `scripts/commands/` backends directly,
> and preserve public CLI behavior and login-hook paths/semantics. Do not
> add features, new runtime dependencies, dependency upgrades, live payload
> updates or unrelated cleanup.
>
> I authorize the scoped commits, task-owned candidate branch pushes,
> ordinary ancestry-preserving integration, exact-green main fast-forward
> and normal push, actual rollout and acceptance on all six documented
> hosts, and safe task cleanup needed to complete this plan, without asking
> for permission at each routine step. Run focused tests,
> `tests/run.sh --ci` and `pre-commit run --all-files`. Remove completed
> tracked handoff/scratch files in the final candidate before testing. The
> exact same candidate SHA must pass every three-platform `ci/**` job and
> the full cache-off `e2e-ci/**` bootstrap matrix. Refresh main before landing;
> integrate concurrent changes and repeat reviews/gates for any new candidate.
> Verify main CI after push. Do not force push, rewrite history or discard
> someone else's work.
>
> Follow docs/hosts.md and docs/updates.md for actual six-host rollout,
> starting with Lab and assigning one owner per host. Use only existing SSH
> or control connections; do not authenticate or answer MFA for me. Read
> site rules and use the existing pinned Sherlock controller as required.
> Windows home writes must use the ordinary limited token. Preserve and
> assess existing drift before any reconciliation; keep exact targets,
> maintenance, ownership, secrets, no-write checks and installation pins safe.
> Do not claim complete rollout while a host remains blocked.
>
> After acceptance, verify processes, worktree status/diffs/untracked files
> and branch ancestry before removing task worktrees, merged branches,
> remote candidate branches and completed temporary artifacts. Preserve
> still-needed recovery data. Report concrete blockers and the smallest
> action I need to take when necessary, while continuing independent work.
>
> Main push and actual six-host rollout are included. Choosing a version,
> creating/moving/deleting a tag, or publishing a GitHub Release is not
> authorized. Ask only for a materially new decision, unavailable access,
> or action outside this scope; do not reinterpret routine scoped work as
> requiring repeated confirmation.
