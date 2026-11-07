# Chezmoi migration handoff

Status: Stage 6 (legacy retirement) is implemented on the coordinator
integration branch; landing, the final exact-SHA CI and e2e and the host-side
Phase C are pending (see [status.md](status.md) and the
[Stage 6 plan](stage-6-retirement.md)). Stage 5 (ecosystem simplification) is
done. It landed at `dddc718` after exact CI 41832666587 and bootstrap e2e
41832666818; the five Unix hosts reached it through their login updater and
took the reviewed `persistentState` re-init, and Windows did the same on
2026-11-04 (at `57fbc45`) through a user-approved limited-token task.
Stage 4 native takeover is accepted on all six hosts, with all eight approved
static credentials enrolled on the five Unix hosts. Runtime `bf99958`, encrypted
source `74985d08` and formatting correction `15068b9` passed their exact hosted
CI/e2e gates before main landing and relevant host operations. Recovery custody
is established. Actual outcomes, historical partial operations and application
limits are recorded in [status.md](status.md). The Stage 6 session prompt is
[start-stage-6.md](start-stage-6.md). Initial research baseline: `738f619`;
consolidation baseline: `1a9d30b`. The completed review's old-layout/tool-support
plan is now integrated in [support-boundary.md](support-boundary.md); do not
execute its old standalone prompt. Takeover and recovery use
[takeover.md](takeover.md). The [Stage 5 prompt](start-stage-5.md) and the
original [Stage 1 prompt](start-stage-1.md) remain historical context.

## User intent and scope

The user wants to move substantially into the chezmoi ecosystem, reuse native
features, simplify existing behavior and reduce repository maintenance. Removing
TOMLKit, `.venv-sync`, `setup-sync.*` and their configuration-sync dependency chain
is an explicit end-state requirement. Preserving every legacy implementation
detail is not a requirement. Python remains legitimate for tests and unrelated
stdlib helpers such as the tmux metric script.

The user requested one fresh implementation session per stage, with multiple
subagents in separate worktrees. Near stages are detailed; each session must
improve the next stage before handing off. The user subsequently authorized agents
to perform actual migration, testing and exact legacy retirement on the six hosts
in Stages 4 and 6. Follow [fleet-rollout.md](fleet-rollout.md); do not defer
reachable-host execution to the user or ask for blanket permission again.
Stages 1-3 remain isolated. Authentication, privilege and site-specific boundaries
still apply, as do repository landing rules.

Isolation permits native platform fixtures in fresh private temporary directories
over existing authorized access. It forbids real HOME takeover, token inspection
and remote migration in these stages. Linux-only execution does not replace
required macOS/Windows evidence; lack of a published CI run is not a waiver.

This direction supersedes the feasibility review's conservative suggestion to
retain the Python merge backend indefinitely. The backend survives only while the
declared transition still supports the old path. The new path must not depend on
it. The user also accepts ending old-layout and obsolete-tool support with a
documented manual upgrade; waiting for every offline installation to attest
migration is no longer a prerequisite.

## Target architecture

- Chezmoi owns configuration source state, host selection, rendering, diff and
  application. Use its default regular-file mode and native file attributes.
- Native modify templates own the two mutable AI configurations. No external jq,
  Python merge process, TOMLKit, custom writer or third-party modify framework.
- Native encryption or password-manager integration manages explicitly selected
  secrets and private SSH snippets. App-written authentication state retains its
  owner; see [secrets-and-ssh.md](secrets-and-ssh.md).
- Package managers own packages. Upstream payload installers own their installed
  trees. Retain only narrowly justified site, privilege and download glue.
- Keep package installation separate from ordinary configuration apply. Do not
  hide sudo, authentication, HPC environment creation or installers in hooks.
- Preserve login automatic dotfiles updates through a thin adapter that invokes
  native chezmoi. This is the user's explicit choice. Keep interactive/session
  triggering and noninteractive failure handling small; do not recreate custom
  revision receipts, elevated stow workers or a retry/recovery protocol. Explicit
  manual update remains available. See D6 in [status.md](status.md).
- Preserve one source of portable policy and one writer per destination. Any
  transition duplication must have an owner, parity check and removal stage.

The intended final layout uses `.chezmoiroot` containing `home`:

```text
home/
  .chezmoi.toml.tmpl
  .chezmoiignore
  .chezmoidata/
  .chezmoitemplates/
  dot_gitconfig
  dot_gitconfig_local.tmpl
  dot_config/
  dot_claude/modify_private_settings.json
  dot_codex/modify_private_config.toml
config/       # only remaining provisioning/payload data
scripts/      # only remaining explicitly invoked integrations
tests/
docs/
```

Modify templates use the `chezmoi:modify-template` directive and have no `.tmpl`
suffix. Ordinary templates do use `.tmpl`. Initial sourceDir may remain
`~/dotfiles`; changing its location is unnecessary. Keep native Windows and WSL
checkouts and homes separate. Do not use a OneDrive-synced source checkout as a
shortcut around the repository's OneDrive Git rules.

## Contract decisions

These are implementation directions for the requested simplification. Stage 1
must verify native behavior and record exceptions, rather than claiming untested
equivalence. A failure of a retained requirement is not permission to weaken it.

| Area | Retain | Adopt or simplify |
| --- | --- | --- |
| Host selection | Explicit `common-only`, `mac`, `wsl-ubuntu`, `lab-ubuntu`, `sherlock`, `marlowe`, `win`; Windows package applicability | Local chezmoi data becomes the single host source after takeover; OS detection validates, not guesses, a role |
| Ordinary files | Correct content, executable/private attributes, visibility of local edits | Regular files, explicit edit/add/merge/apply workflow; no Stow write-through guarantee |
| AI ownership | Portable values, Claude authoritative arrays and local model, Codex owned/retired paths, unrelated live state | Native modify templates and native parsers; canonical serialization may remove TOML comments, ordering and original whitespace |
| Parser boundaries | Reject malformed input, invalid policy roots/types and destructive ancestor conflicts | Document native duplicate-key and numeric behavior; do not rebuild a compatibility parser to mimic Python |
| Convergence | Second apply has no remaining intended changes | No promise of the original first-apply bytes, inode, mtime, custom fsync or compare-and-swap behavior |
| Permissions | AI configs private; no plaintext credentials or private keys in source/logs; Windows usability | Declare private AI files, normally 0600 on Unix; review existing readonly/stricter targets at takeover instead of recreating arbitrary mode-intersection logic |
| Secrets and SSH | Existing auth ownership, trust, consumer paths and explicit recipient scope | Native ciphertext/vault references for allowlisted secrets; no periodic replay of refreshed OAuth state |
| Failure handling | Invalid target transform must fail without replacing that target; clear errors | No whole-home transaction, custom journal or rollback daemon |
| Checks | A reduced project's offline check remains offline; test homes isolated | Chezmoi preview is not advertised as globally write-free; native cache/state is allowed in explicitly isolated locations |
| Provisioning | Person-triggered installs, visible privileged steps, no authentication, HPC allocation boundaries | Native manifests and small adapters; retire redundant framework behavior |
| Payloads | Upstream ownership, platform/channel selection, honest errors, local edits | Explicit upstream delegation only (D7, resolved in Stage 5): `sync-payloads` runs the upstream installers in the foreground; no consumer-side scheduling |

Keep all existing Claude/Codex permission-policy VALUES unchanged. This migration
does not authorize weakening allow/ask/deny policy or replacing project guidance.
Do not import whole application directories, trust, sessions or caches. Selected
secrets may enter source only through the ciphertext/vault workflow, with no
plaintext credentials or decryption identities. Real enrollment belongs to Stage 4.
Do not use `exact_` or broad removal rules on shared `.ssh`, `.claude`, `.codex`,
`.oh-my-zsh`, `.tmux` or payload directories.

Stage 6 removed the Stow/TOMLKit rules from `AGENTS.md`; until then it
described them as active implementation rules. The coordinator updated only
rules needed by the stage being implemented, citing this migration direction
and preserving only the layout/version contract still supported by that stage. Apply the explicit support-cutoff decision; do not keep
old retention rules active indefinitely or copy them into the native architecture.
Do not leave future agents with contradictory active instructions. `CLAUDE.md`
remains an import stub. Mirrored first-party skills remain identical.

## Stage map

| Stage | Deliverable | Detail now | Deployment boundary |
| --- | --- | --- | --- |
| [1. Foundation](stage-1-foundation.md) | Versioned native probes, isolated tests, target/contract and support-floor inventory | Executable task plan | No live changes; legacy defaults stay intact |
| [2. Source state](stage-2-source-state.md) | Complete ordinary-file and host model with temporary legacy-source bridge | Implemented candidate and exact source checks | Candidate source, tested in temporary homes |
| [3. Native configuration](stage-3-native-config.md) | Native AI modifies; complete candidate needs no sync venv | Implemented with explicit safe input refusals | Isolated native fixtures; Stage 4 performs takeover |
| [4. Takeover](stage-4-takeover.md) | Declared cutoff, tested handover, real canary takeover, secret enrollment, thin login adapter | Ordered work packages with paths, guards, recovery and platform gates | Agent executes under the user's recorded six-host authorization |
| [5. Ecosystem simplification](stage-5-ecosystem.md) | Smaller provisioning/diagnostics/payload integration and verified old-tool branch removal | Done at `dddc718`; [completion record](status.md#stage-5-completion-record-2026-11-04) | D7 resolved as explicit-only payloads; all six hosts updated and re-initialized (win on 2026-11-04, at `57fbc45`) |
| [6. Retirement](stage-6-retirement.md) | Delete old source/runtime and execute tested host-side retirement | Implemented (A1-A4, B1-B7); landing and Phase C pending; [session prompt](start-stage-6.md) | Roll out to all reachable unblocked hosts; record exceptions without an all-host waiting gate |

Stages run in this order. Code completion and real-host operations are different
facts: record both. Old installations may become unsupported at the declared
cutoff; they need not all be online before Stage 6. Do not describe them as
migrated or safe to auto-update merely because current-layout tests pass.

## Release invariant

Current installed files point directly into the legacy `common/` and host paths.
Login can fast-forward `main` before any new installer runs. Renaming or deleting
those paths can break shell startup immediately. A compatibility commit does not
protect a machine that is offline and later skips straight to the final commit.

Keep current Stow paths through the bridge stages, then remove them under the
declared support boundary and tested manual upgrade/recovery procedure. The
user's latest-only decision replaces the earlier all-installations-attestation
gate. A cutoff does not stop old code from pulling a deletion commit: operators
must disable old hooks and address running workers/tasks BEFORE crossing it.
Document that unsupported installations cannot safely assume automatic upgrades.
Do not add a fleet service or require an inventory of every offline installation.
See [the cutoff procedure](support-boundary.md#one-time-operator-upgrade-and-cutoff-deliverable).
Executed in Stage 6 on the repository side; the host side follows the
Stage 6 record in [status.md](status.md).
The implementing agent executes that procedure on accessible hosts. Quiesce old
writers before publishing/crossing the breaking revision; a subsequent cleanup
cannot repair an auto-pull race retroactively. Follow the fleet rollout order.

## Session and parallel-worktree protocol

1. Read root `AGENTS.md`, this file, `status.md`, the current stage and its actual
   predecessor completion record. Inspect `git status`, relevant diffs, HEAD,
   branches and worktrees. Treat unfamiliar edits/commits as user-owned.
2. Base work on the current intended HEAD, including local commits such as the
   tmux changes in `738f619`, not blindly on `origin/main`.
3. These handoff files are committed on main, so a worktree created from current
   main contains them. Carry any later uncommitted required work explicitly.
   Stages 1-4 exist in the committed bridge plus follow-up changes; inspect
   status.md and the complete current diff instead of replaying a historical
   patch. Never stash, discard or indiscriminately copy unrelated changes.
   Commit only with active authorization.
4. Use one integration worktree owned by the coordinator and one separate branch
   and worktree per write-capable subagent. Never have two writers in one checkout.
   In a OneDrive checkout use independent local clones under the global rules.
5. Freeze task interfaces before parallel implementation. Assign exclusive file
   ownership. Coordinator owns shared CI, hook selection, test-entrypoint,
   `AGENTS.md`, documentation and integration edits unless explicitly delegated.
6. Workers return changed paths, focused test commands/results, assumptions and
   integration dependencies. Workers must not independently publish branches or
   edit the coordinator checkout. Integrate sequentially and review the aggregate
   diff with a separate read-only reviewer.
7. Commit only within the session's authorization. If commits are not authorized,
   return scoped patches for integration. Never use reset/stash/rebase to clear
   another worker's or the user's changes. Keep recoverable worktrees until their
   work has been integrated and verified.
8. Run focused behavior checks, then required aggregate checks. Repository landing
   rules govern any authorized publication: exact green commit on all three OSes,
   and bootstrap e2e when affected. Local Linux tests do not establish Windows or
   macOS behavior. Do not push incomplete migration behavior to auto-updated main.
9. Update `status.md` with evidence and refine the NEXT stage to executable tasks.
   Update farther-stage assumptions when discoveries affect them. Stop at the
   current stage boundary; a new session starts the next stage.

Use the available subagent-driven-development workflow, adapted to these explicit
parallel-worktree ownership rules. Do not run sequentially dependent tasks in
parallel merely to use more agents. Do not turn a planning skill's boilerplate
into repeated requests to approve work already authorized by the active prompt.

## Evidence and definition of done

No stage is complete solely because its files exist. Record the actual starting
and ending revision or patch state, native chezmoi version, focused and aggregate
checks, platform evidence, behavior changes, removed/retained mechanisms and
unresolved risks. Never label a planned check as passed. Private host details and
application configuration contents do not belong in the record.

The final system must deploy and update configuration without TOMLKit, a sync
venv, external jq or Python configuration transforms. Existing behavior tests for
shells, tmux, AI policy and platform applicability remain useful after adapting
them to rendered output. Delete tests for retired mechanisms with those mechanisms;
do not preserve dead infrastructure just to keep old tests unchanged.

Official references and source findings are in [sources.md](sources.md). Resolve
uncertainty against a selected tagged release and real isolated probes before
relying on moving documentation or model memory.
