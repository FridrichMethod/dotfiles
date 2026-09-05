# Dotfiles sync hardening execution plan

Status: planned. Baseline: `c8567f1`.

## Objective and boundaries

Keep shell and PowerShell as the installation/update orchestration layers.
Replace hand-written TOML parsing with a small Python configuration backend
using the standard-library JSON implementation and pinned `tomlkit`. Keep the
existing Stow package layout, common-before-host ordering, permission policies,
and Claude Node hooks unchanged.

Python becomes an explicit AI-sync runtime dependency. Provision it and the
isolated parser environment during an explicit setup step, never during login
or automatic update. Do not track virtual environments or downloaded packages.
Normal synchronization must not modify portable source files. Legacy baseline
cleanup requires an explicit migration operation.

All tests use disposable repositories and home/target directories. Never run
an installer against the operator's real home. Network-logon symlink trust and
real Windows Task Scheduler execution remain separately documented environment
checks; ordinary hosted-runner tests must not claim to prove those properties.

## Work graph

```text
P: plan and baseline
  +--> A: three-platform CI and explicit test prerequisites --------+
  +--> B: structured configuration backend and safe file updates ---+--> D: installer preflight,
  +--> C: updater acknowledgement and concurrency tests -----------+    native integration,
                                                                       docs and lint
                                                                       |
                                                                       v
                                                                  R: independent review
                                                                     + complete validation
                                                                       |
                                                                       v
                                                                  M: merge to main
                                                                     + remove task worktrees
                                                                     + push and watch CI
```

Each implementation node has its own branch and worktree. The coordinator is
the only writer to the integration worktree and merges completed node commits
in dependency order. Review agents are read-only. No simultaneous writers may
share a checkout. Only branches/worktrees created for this task are removed.

## Nodes, ownership, and acceptance

| Node | Owned scope | Acceptance |
| --- | --- | --- |
| P | This plan and baseline validation | Clean initial tree, current remote main, recorded plan commit before implementation |
| A | `.github/workflows/ci.yml`, test entrypoints/prerequisite reporting, initial CI documentation | Explicit Ubuntu/macOS/Windows jobs; native PowerShell suite mandatory on Windows; required CI dependencies cannot silently skip; macOS uses system Bash/BSD utilities |
| B | AI sync wrappers, new parser/runtime files, sync-specific tests and dependency/setup documentation | Real TOML parsing and validation; JSON merge has one engine; unknown live state retained; arrays remain authoritative; invalid input leaves live untouched; portable inputs unchanged; idempotence and legacy-link migration tested |
| C | `dotfiles-update.sh`, updater tests, updater-specific documentation | Unix verifies applied HEAD/host after installer success; missing acknowledgement retries; isolated real-process concurrency and realistic Git scenarios exercised |
| D | `stow-all.*`, installer integration tests, lint wiring, consolidated README/COVERAGE | All selected config inputs/dependencies preflight before mutation; injectable disposable Windows target; real native link/adopt/backup/ignore/no-op/WhatIf/Strict tests; shared core tests on all OSes; extensionless shell helpers linted |
| R | Read-only independent code review; coordinator owns fixes | Focused tests and full pre-commit pass; no unresolved correctness/security findings; review source diff and test isolation |
| M | Integration/main Git refs and task-only cleanup | Main contains all reviewed commits; worktrees clean before removal; task branches merged before deletion; push without force; watch exact pushed HEAD until all CI jobs finish |

Documentation changes from independent branches stay in distinct scoped files
until D consolidates README and COVERAGE. Tests may report optional local skips,
but CI jobs must explicitly require the suites assigned to that platform.

## Configuration and filesystem regression contract

- TOML: multiline arrays/strings, comments, quoted and dotted keys, inline
  tables, arrays of tables, unknown runtime tables, malformed/duplicate input,
  required portable fields, and retired keys.
- JSON: portable-wins recursive object merge, live-only keys, authoritative
  permission/hook arrays, empty arrays, false/null, Unicode, and invalid roots.
- Files: adjacent temporary output, validate before replacement, no preliminary
  removal of the live link, cleanup on failure, no-op without replacing an
  unchanged regular file, Unix modes, and native Windows replacement behavior.
- Installation: common/host order, shared ignore rules and Windows allowlist,
  spaced paths, materialized AI files, conflicts/backups, strict failures, no
  false applied-state acknowledgement, and no writes during dry-run.
- Update: fast-forward only, clean-tree/submodule protection, home-bound state,
  host selection, failed-stow retry, acknowledgement, and independent-process
  lock contention. Document the manual/automatic installer locking boundary.

## Validation and release procedure

1. Run focused tests in each node, followed by `pre-commit run --all-files`
   before committing. Report unavailable native checks honestly.
2. Merge node commits into the integration branch, never overwrite user work.
3. Run `./tests/run.sh`, native PowerShell tests when available, parser tests,
   full pre-commit, and `git diff --check`. Independently review the final diff.
4. Recheck main/remote for concurrent changes; integrate safely without force.
5. Fast-forward main when possible, remove only clean task worktrees and fully
   merged task branches, then push main.
6. Watch the workflow run for the exact pushed SHA. Fix CI regressions through
   a fresh isolated branch/worktree and repeat validation/push/watch as needed.

## Execution record

- P: inspected baseline and remote; only the original main worktree existed.
- A/B/C/D/R/M: pending.
