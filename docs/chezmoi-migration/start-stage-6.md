# Fresh-session prompt: Stage 6

> Archived: this stage is complete ([status.md](status.md)); do not start a session from this prompt.

> Completed. Stage 6 landed at `55a7960` on 2026-11-07 after exact CI
> 42349446858 and bootstrap e2e 42349446830, and all six hosts reached it
> through their own login updater. Its decisions, review, host results and the
> host traces it leaves are in
> [status.md](status.md#stage-6-completion-record-2026-11-07). The next
> session starts from [start-stage-7.md](start-stage-7.md). The prompt below
> is the original handoff, kept as history; do not run it again.

Paste the block below into a new session to run Stage 6, the legacy retirement.
It assumes the Stage 5 records are on main. The canonical plan is
[stage-6-retirement.md](stage-6-retirement.md); the prompt adds the session
rules and the host constraints.

```text
ultracode

Implement only Stage 6 (legacy retirement) of the dotfiles chezmoi migration,
following docs/chezmoi-migration/stage-6-retirement.md, the canonical plan.
Stages 1-5 are accepted. Do not rerun any completed bridge, takeover, init,
secret enrollment, Stage 5 persistentState re-init, Marlowe runtime or tmux
install or kit upgrade, and do not reopen Stage 5 work. Stage 5 landed on main
as b9f9d61..dddc718: exact-SHA ci.yml run 41832666587 (all three jobs) and
bootstrap-e2e run 41832666818 (all seven hosts) passed.

Read first, in this order, before any edit or host operation: AGENTS.md;
docs/chezmoi-migration/status.md, above all the Stage 5 record (host table,
findings, open items) and the retirement gate; stage-6-retirement.md (gates
R1-R8 and F1-F12, host residue, the ordered commits A1-A4, B1-B7 and Phase C,
what must be kept, the native-only verification plan, measured sizes, risks and
D-1..D-17); the ownership tables in inventory.md ("Per-tracked-package-file
mapping", "Source-path callers and test disposition", "Compatibility deletion
map") and stage-5-ecosystem.md ("Exact caller disposition from Stage 4"); then
support-boundary.md, takeover.md, fleet-rollout.md, secrets-and-ssh.md and the
migration README.md. Read docs/{bootstrap,payloads,config-sync,update-contract,
testing,shell,dependencies}.md and tests/COVERAGE.md where their callers change.
The plan's file:line references were verified at dddc718 only: re-derive each
with git grep -n at your base and follow symbols and callers.

Start state. Begin at the canonical $HOME/dotfiles checkout on main. Inspect
HEAD, branch, status, the full staged and unstaged diff, untracked files,
branches and the worktree list; treat anything you did not create as user-owned.
That checkout is Lab's bound native source and is shared with Codex: never edit
it, switch its branch, add files to it or leave it dirty (the native login
updater refuses a dirty source at every login), and never run deletion work
there. Confirm the Stage 5 records commits are on main (R2). Create the
coordinator worktree under $HOME/dotfiles/.worktrees/<task>/ (for example
stage6-coord) from current main; every write-capable worker gets its own branch
and worktree under .worktrees/<task>/. These do not dirty the checkout:
.worktrees/ is ignored (.gitignore:25) and the updater's status check does not
list ignored paths. Never two writers in one checkout.

Windows. Gate R3 passed on 2026-11-04 (status.md, Stage 5 host rollout): win
reached 57fbc45 (dddc718 code plus the Stage 5 records) through its own updater,
took the persistentState re-init and its doctor exited 0. Only the read-only
Phase 0 recheck remains (F1-F12; its F7 managed count was not measured). For the
whole stage, commands that change the win home run as the ordinary user: typed
by the user, or a one-off scheduled task with the logged-on user's limited token
(Interactive, RunLevel Limited) that the user explicitly approves for that run,
that needs the user logged on and that is deleted after it (fleet-rollout.md,
Windows rollout as run). The SSH route into win carries an administrator token:
use it only for read-only metadata and, with that approval, to write such a
task's script and register, start and delete it; never to write managed targets,
the source checkout, chezmoi config or state, or ACLs. The one possible
exception, deregistering the disabled Dotfiles-Restow-<16 hex> task, follows the
plan's procedure and needs the user's approval of that exact command.

Decisions. Before any commit that depends on them, ask the user D-1..D-17 in
one batch, each with the plan's options and its recommendation first, and record
the answers in status.md. Do not ask again for blanket commit, publication or
rollout authority: D11 and AGENTS.md "Workflows and checks" grant it within
their limits. Ask before anything those rules forbid or that cannot be undone.
The auto-mode classifier may require an explicit user confirmation for a main
push; if it does, ask for it at the landing step.

Workflow, phased, with a todo list. Phase 0 is read-only and parallel where
independent: re-derive the plan's callers at your base, run fleet gates F1-F12
on all six hosts and list the host residue. Then Phase A (A1-A4) and Phase B
(B1-B5, optional B6, B7) in the plan's order. Every commit is tests first
(capture RED, then GREEN), atomic and conventional (test:, feat(e2e):,
refactor!:, fix:, docs:), staged by explicit path, with no AI attribution. The
coordinator owns the shared files: AGENTS.md, README.md, the CLAUDE.md stub,
docs/**, both mirrored skills, .pre-commit-config.yaml, .github/**, tests/run.*,
tests/lib/**, tests/test-entrypoints.sh, the status and inventory records and
the shared profiles, unless explicitly delegated. Freeze each worker's exclusive
paths before edits, integrate sequentially and keep recoverable patches until
integrated. Finish with an independent adversarial read-only review of the final
aggregate along several dimensions, verify each finding with a skeptic pass, and
fix confirmed findings in reviewed fix branches.

Checks. Per commit: the focused suites, tests/run.sh --ci and pre-commit run
--all-files. Until B3, tests/run.sh requires the parser runtime: reuse
DOTFILES_SYNC_PYTHON=$HOME/dotfiles/.venv-sync/bin/python read-only; never run
setup-sync, create a venv or install TOMLKit. From B3 on, run every suite with
DOTFILES_SYNC_PYTHON unset and no .venv-sync, from a fresh clone. tests/run.ps1
-CI runs only in CI (Lab has no pwsh). Linux CI keeps apt tmux and
DOTFILES_TEST_REQUIRE_TMUX=1. The Mac tmux 3.8 adversarial-menu failures are a
recorded baseline; never report them fixed. Landing: push the exact candidate
SHA to a ci/<name> branch and, because Phases A and B change bootstrap and e2e,
to an e2e-ci/<name> branch; wait for every ci.yml job (Linux, macOS, Windows)
and every bootstrap-e2e job on that exact SHA; then fast-forward main only (no
force, no rewrite) and delete the ci/** and e2e-ci/** branches. Land Phase A
before Phase B.

Hosts (Phase C), only after the final aggregate landed green and R3 passed. Lab
is local (its self-SSH is rejected); use the existing SSH routes and the plain
aliases for clusters (sherlock-plain, marlowe-plain); re-resolve SSH config each
session. Deregister the Windows task first, while its script still exists.
Quiesce with ~/.config/dotfiles/maintenance on the five remote hosts and canary
Lab (D-16), then go host by host with one owner per host. Host updates are
fast-forward only and nonforce: the login updater, or explicit native commands
with the updater's full argument set plus --exclude=dirs --force=false. Plain
read-only chezmoi commands are fine on all six hosts, whose config owns
persistentState since the Stage 5 re-init; plain mutating commands never are.
Never force, stash, rebase or reset a host checkout; restore maintenance on
failure. Run the plan's per-host acceptance, then retire only exact residue
items, each with a private snapshot first, and record every host separately in
status.md (revision before and after, checks, removed residue, blockers). An
unreachable or blocked host stays an explicit exception, never false success.
The recorded pre-existing provisioning gaps are not regressions and are not
yours to fix.

Sherlock. Before every cluster operation, and again after any summary or context
compaction, read /etc/agents/AGENTS.md and the task's topic files (storage.md,
slurm.md, software.md, policy.md) through the user's existing control master:
check it with shk doctor (the controller's pinned shk, below), then read with
ssh -oBatchMode=yes -oProxyCommand=false sherlock-plain cat <file>. Their
numbered site rules take precedence. Never log in or authenticate for the user.
Use the shk of the separately approved local controller project that pins
sherlock-kit v0.6.0 (fleet-rollout.md, Sherlock paragraph; stage-4-evidence.md):
it is already approved, so do not ask again. Dotfiles itself pins none and does
not add one. Never a global or development copy, never ssh ... sbatch. Build
environments only inside a Slurm allocation, never under $SCRATCH; light
foreground git or chezmoi work on a login node only as the current rules allow.

Marlowe. Interactive login shells use the micromamba login env
($HOME/micromamba, env login, with tmux 3.6a and Python); non-interactive
shells (ssh marlowe-plain) see /usr/bin/tmux 3.2a and the system tools. The site
AppArmor profile block-node denies node on login nodes (the env's node does not
run), so Claude's Node hooks fail open: accepted, and the Codex config stays
deployed (no Codex CLI is on PATH there, but remotely started Codex
app-servers read it). Never work
around the profile. Any env change runs in a Slurm job. Its filesystem keeps
ACLs ('+'): never use cp -p there, and never assume $0 is a file when a script
travels over ssh.

Secrets and evidence. Metadata only: never print, copy or diff secret values,
OAuth or app-written auth state, private identities or decrypted content;
compare AI configs privately and log only equal/not equal and key names. The
eight approved Claude age ciphertexts stay; win enrollment stays false. Keep all
recovery backups and historical manifests: Lab's private recovery store at
~/.local/state/dotfiles-chezmoi-migration-recovery/ (moved there from
$HOME/dotfiles/.git/ at the end of Stage 5; read its README and manifests
before any recovery; never apply its old whole patches to newer main), the
Stage 4 private host backups, the Stage 5 evidence under
~/.local/state/dotfiles-stage5-rollout/ and ~/.local/state/dotfiles-stage5-reinit/
on each Unix host (win: ~\.config\dotfiles-stage5-task\ and
~\.config\chezmoi\stage5-reinit\), and Marlowe's
~/.local/state/dotfiles-marlowe-tmux-*/. Stage 6 never deletes or rewrites
them.

Out of scope: the findings the plan lists under "Not in Stage 6" (tmux plugin
clones, login-env packages, Codex skills pruning, Sherlock skills, the Windows
Codex sandbox ACL grants, tool floors beyond D-15, upstream payload
repositories, the permission policy beyond D-10). Report them; do not fix them.

Deliverables: the Stage 6 commits landed on main with their exact CI and e2e run
IDs; native-only verification evidence (fresh local clone, three OSes, e2e);
per-host rollout and residue retirement results; the status.md Stage 6 record
(stage completion template) with measured code, test and doc deltas by category
from git diff --numstat, each surviving custom helper's purpose and any
remaining legacy reader; the updated stage table, retirement gate, the plan's
checkboxes, support-boundary.md, inventory.md, AGENTS.md (below 28,000 bytes),
README, canonical docs and both skills; archived start-stage-*.md with
outstanding host tasks kept visible. Stop when Stage 6 is recorded. Report
unfinished gates and blocked hosts explicitly, and start nothing beyond Stage 6.
```
