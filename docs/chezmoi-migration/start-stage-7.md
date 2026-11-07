# Fresh-session prompt: Stage 7

Paste the block below into a new session to run Stage 7, the trace removal.
It assumes the Stage 6 record is on main. The canonical plan is
[stage-7-trace-removal.md](stage-7-trace-removal.md); the prompt adds the
session rules and the host constraints. Stage 7 deletes this file with the rest
of `docs/chezmoi-migration/`.

```text
ultracode

Implement Stage 7 (trace removal) of the dotfiles chezmoi migration, following
docs/chezmoi-migration/stage-7-trace-removal.md, the canonical plan. Stages 1-6
are accepted; do not reopen them. The user's goal, which overrides any earlier
retention decision: remove every legacy, deprecated and transition mechanism
and every trace of it, in the tracked tree and on the six hosts, with no
safeguard for old options or layouts, so the result reads as if this design
had been the first one; then bring all six hosts to the final main. Git
history and tags are not rewritten.

Read first, in this order, before any edit or host operation: AGENTS.md; the
plan; docs/chezmoi-migration/status.md, above all the Stage 6 record (host
table, the exact host residue it left, open items); then takeover.md,
fleet-rollout.md, secrets-and-ssh.md and support-boundary.md, whose durable
content R6 folds into docs/ before R7 deletes them; then
docs/{bootstrap,payloads,config-sync,update-contract,testing,shell,dependencies}.md,
README.md and tests/COVERAGE.md. File references in the plan were taken at
55a7960: re-derive each with git grep -n at your base.

Start state. Begin at the canonical $HOME/dotfiles checkout on main. Inspect
HEAD, branch, status, the full diff, untracked and ignored files, branches and
the worktree list; treat anything you did not create as user-owned. That
checkout is Lab's bound source and is shared with Codex: never edit it, switch
its branch or leave it dirty, and never run deletion work there except the
Phase H1 removal of its own leftovers. If the branch stage7/plan is not on
main, merge it first through the normal landing. Work in a coordinator
worktree under $HOME/dotfiles/.worktrees/<task>/; every write-capable worker
gets its own branch and worktree there. Never two writers in one checkout.

Decisions. After Phase 0, ask the user S7-1..S7-8 in one batch, each with the
plan's options and its recommendation first. The user's goal answers
everything else; do not ask again for blanket commit, publication or rollout
authority (D11 and AGENTS.md "Workflows and checks"). Ask before anything those
rules forbid or that cannot be undone: the exact deletion lists of S7-6 and
S7-7. The auto-mode classifier may require an explicit user confirmation for a
main push; ask for it at the landing step.

Workflow, phased, with a todo list. Phase 0 is read-only and parallel where
independent: the repository scan and classification, the six-host trace
listing and the baselines. Then Phase H1 on all six hosts, Phase R (R1-R7) as
one aggregate, Phase H2. Every commit is tests first (RED, then GREEN where
behavior changes), atomic and conventional, staged by explicit path, with no AI
attribution. The coordinator owns AGENTS.md, README.md, the CLAUDE.md stub,
docs/**, both mirrored skills, .pre-commit-config.yaml, .github/**,
tests/run.*, tests/lib/**, tests/test-entrypoints.sh and the shared profiles,
unless explicitly delegated. Freeze each worker's exclusive paths before
edits, integrate sequentially and keep recoverable patches until integrated.
Before landing, run an independent adversarial read-only review of the
aggregate along several dimensions (over-deletion of needed behavior, missed
traces, broken callers and links, host ordering), verify each finding with a
skeptic pass, and fix confirmed findings. Then run the plan's zero-trace
acceptance; never commit its scanner.

Checks. Per commit: the focused suites, tests/run.sh --ci and pre-commit run
--all-files, from a fresh clone with no .venv-sync. tests/run.ps1 -CI runs
only in CI (Lab has no pwsh). Linux CI keeps apt tmux and
DOTFILES_TEST_REQUIRE_TMUX=1. The Mac tmux 3.8 adversarial-menu failures are a
recorded baseline; never report them fixed. Landing: push the exact candidate
SHA to ci/<name> and e2e-ci/<name>; wait for every ci.yml job (Linux, macOS,
Windows) and every bootstrap-e2e job on that exact SHA; then fast-forward main
only (no force, no rewrite) and delete both branches. R5 (the residue ignore
lines) lands only after Phase H1 is complete on all six hosts.

Hosts. Lab is local (its self-SSH is rejected); use the existing SSH routes
and the plain aliases for clusters (sherlock-plain, marlowe-plain); re-resolve
SSH config each session. Host updates are fast-forward only and nonforce: the
login updater, or explicit chezmoi commands with the updater's full argument
set plus --exclude=dirs --force=false. Plain read-only chezmoi commands are
fine; plain mutating commands are not. Never force, stash, rebase or reset a
host checkout. Quiesce with ~/.config/dotfiles/maintenance on the five remote
hosts before main moves, canary Lab, then go host by host with one owner per
host; restore maintenance on failure. Handle any one-time switch (binding,
state path, renames) by explicit commands under maintenance, never by
compatibility code. Run the plan's per-host acceptance and keep a per-host
record for the final report. An unreachable or blocked host stays an explicit
exception, never false success. Pre-existing provisioning gaps recorded in
Stage 6 are not regressions and are not yours to fix.

Windows. Commands that change the win home run as the ordinary user: typed by
the user, or a one-off scheduled task with the logged-on user's limited token
(Interactive, RunLevel Limited, no trigger) that the user explicitly approves
for that run, that needs the user logged on and that is deleted after it. The
SSH route into win carries an administrator token: use it only for read-only
metadata and, with that approval, to write such a task's script and register,
start and delete it; never to write managed targets, the source checkout,
chezmoi config or state, or ACLs.

Sherlock. Before every cluster operation, and again after any summary or
context compaction, read /etc/agents/AGENTS.md and the task's topic files
(storage.md, slurm.md, software.md, policy.md) through the user's existing
control master: check it with shk doctor (the separately approved local
controller project's pinned shk, as in the Stage 6 prompt), then read with
ssh -oBatchMode=yes -oProxyCommand=false sherlock-plain cat <file>. Their
numbered site rules take precedence. Never log in or authenticate for the
user. Never a global or development shk, never ssh ... sbatch. Build
environments only inside a Slurm allocation, never under $SCRATCH.

Marlowe. Interactive login shells use the micromamba login env
($HOME/micromamba, env login); non-interactive shells see the system tools.
The site AppArmor profile block-node denies node on login nodes: accepted,
never work around it. Any env change runs in a Slurm job. Its filesystem keeps
ACLs ('+'): never use cp -p there, and never assume $0 is a file when a script
travels over ssh.

Secrets and evidence. Metadata only: never print, copy or diff secret values,
OAuth or app-written auth state, private identities or decrypted content;
compare AI configs privately and log only equal/not equal and key names. The
eight approved Claude age ciphertexts, each host's live age identity and the
user's offline identity recovery copy stay. Migration evidence, snapshots and
Lab's recovery store are deleted only in Phase H2's last step, after every
host passed acceptance, and only the exact list the user confirms; before
deleting any Stage 4 age or enrollment directory, confirm by exit status that
chezmoi on that host decrypts with its live identity.

Deliverables: the Stage 7 commits landed on main with their exact CI and e2e
run IDs; all six hosts at the final main with per-host before/after, removed
traces and acceptance results; the zero-trace scan summary with every kept hit
and its reason; updated agent memory entries; no Stage 7 worktree or branch
left. The final tree has no docs/chezmoi-migration/, so the report to the user
and the commit messages are the record. Report unfinished gates and blocked
hosts explicitly.
```
