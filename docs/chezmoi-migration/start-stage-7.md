# Fresh-session prompt: Stage 7

Paste the block below into a new Claude Code session started in `~/dotfiles`
to run Stage 7, the trace removal. Lab's checkout may lag origin/main, so copy
the block from origin/main:
`git -C ~/dotfiles fetch -q origin && git -C ~/dotfiles show origin/main:docs/chezmoi-migration/start-stage-7.md`.
The canonical plan is [stage-7-trace-removal.md](stage-7-trace-removal.md);
the prompt adds the session rules and host constraints. Stage 7 deletes this
file with the rest of `docs/chezmoi-migration/`.

```text
ultracode

Implement Stage 7 (trace removal) of the dotfiles chezmoi migration, following
docs/chezmoi-migration/stage-7-trace-removal.md, the canonical plan, to
completion. Stages 1-6 are accepted; do not reopen them. The user's goal, which
overrides every earlier retention decision and every AGENTS.md rule the plan
schedules for removal: remove every legacy, deprecated and transition mechanism
and every trace of it, in the tracked tree and on the six hosts, with no
safeguard for old options or layouts, so the result reads as if this design had
been the first one; then bring all six hosts to the final main. Git history and
tags are not rewritten.

First, before reading anything else: git -C $HOME/dotfiles fetch origin. If
branch stage7/plan has commits origin/main lacks, land them first through the
normal ci/** landing; once it is fully merged, remove .worktrees/stage7-plan and
the branch. Lab's canonical checkout $HOME/dotfiles advances only through its
login updater, so it may lag origin/main and lack the plan, this prompt and the
Stage 6 record: create the coordinator worktree
$HOME/dotfiles/.worktrees/stage7-coord at origin/main and read every file from
it (or with git show origin/main:<path>), never from the canonical checkout.
Never pull, merge, reset or switch a host checkout, Lab's included, and never
leave one dirty: it is the bound source, shared with Codex, and the login
updater refuses a dirty source. In particular, never create .claude/worktrees/
or leave .claude/settings.local.json in the canonical checkout: ask the user at
the start to answer permission prompts with a one-time yes until the landing
ignores that file, and if it appears anyway, move it to the plan's private copy
and tell the user. Landing pushes to origin only.

Read, in this order, before any edit or host operation: AGENTS.md; the plan;
docs/chezmoi-migration/status.md, above all the Stage 6 completion record
(approvals, host table, "Host traces left for Stage 7", "Findings not fixed in
Stage 6", "Unfinished gates", coordinator rulings); then takeover.md,
fleet-rollout.md, secrets-and-ssh.md and support-boundary.md, whose durable
content R6 folds into docs/; then docs/*.md, README.md and tests/COVERAGE.md.
File references in the plan were taken at 3cb223e: re-derive each with git
grep -n at your base. Make the private copy of Phase 0 step 5 early: the
landing deletes the records before Phase H2 needs them.

Authority. On 2026-11-07 the user approved this plan and asked that a fresh
session carry it out to completion: commits, publication, rollout and the
plan's host operations need no further authorization question (plan,
"Authority"). Ask the user only the plan's decision batch (S7-1, S7-2, S7-4,
S7-5, S7-8), once after Phase 0, each with its options and the recommendation
first, and at the end the exact S7-7 deletion list with the offline-identity
confirmation. The auto-mode classifier may require an explicit user
confirmation for the push to main; ask for it at the landing step. Expected
user actions, not questions: win logged on while its tasks run, mac awake, and
live existing control masters for Sherlock and Marlowe; tell the user once
after Phase 0 which phases need them, and if one is missing at a step, ask the
user to restore it and wait.

Orchestration. Use the Workflow tool for every substantive phase, with
independent agents and adversarial verification:
- Phase 0: a multi-modal sweep of the repository (by content, by path, by
  callers, by CI, e2e, tests, docs and skills) and of the six hosts (metadata
  only, one agent per host), then a completeness critic; collect the
  classification, the S7-4 rename map and the baselines.
- Phase R: one write-capable worker per commit group with frozen exclusive
  paths. The coordinator creates each worker's branch and worktree under
  $HOME/dotfiles/.worktrees/<task>/ from the current integration tip
  (git worktree add -b stage7/<task> ...) and names that path in the worker's
  prompt; do not use Workflow isolation 'worktree' for writers, since it
  branches from origin/main and writes under .claude/worktrees/ in the
  canonical checkout. Integrate sequentially in the coordinator worktree and
  keep recoverable patches until integrated. The coordinator owns AGENTS.md,
  README.md, the CLAUDE.md stub, docs/**, both mirrored skills,
  .pre-commit-config.yaml, .github/**, tests/run.*, tests/lib/**,
  tests/test-entrypoints.sh and the shared profiles, unless explicitly
  delegated. Never two writers in one checkout.
- Before the landing: the tree part of the zero-trace acceptance on the
  candidate, then an independent adversarial read-only review of the aggregate
  along several dimensions (over-deletion of needed behavior, missed traces,
  broken callers and links, host ordering, Windows and PowerShell 5.1, e2e
  extraction), a skeptic pass on every finding, and fixes for confirmed ones.
- After Phase H2: the host part of the zero-trace acceptance. Never commit the
  scanner.
Every commit is tests first (RED, then GREEN where behavior changes), atomic
and conventional, staged by explicit path, with no AI attribution.

Checks. Per commit: the focused suites, tests/run.sh --ci and pre-commit run
--all-files, from a fresh clone with no .venv-sync; before the landing also
pre-commit run --hook-stage manual gitleaks-history from a full clone.
tests/run.ps1 -CI runs only in CI (Lab has no pwsh). Linux CI keeps apt tmux
and DOTFILES_TEST_REQUIRE_TMUX=1. The Mac tmux 3.8 adversarial-menu failures are
a recorded baseline; never report them fixed. One landing (R1-R7): push the
exact candidate SHA to ci/<name> and e2e-ci/<name>, wait for every ci.yml job
(Linux, macOS, Windows) and every bootstrap-e2e job on that SHA, then
fast-forward origin main only (no force, no rewrite) once Phase H2 step 1 has
confirmed the maintenance marker on all six hosts; a host without a confirmed
marker blocks the landing. Delete both branches after the rollout.

Hosts. Lab is local (its self-SSH is rejected); use the existing SSH routes and
the plain aliases for clusters (sherlock-plain, marlowe-plain); re-resolve SSH
config each session. Follow the plan's Phase H1 and H2 exactly: H1 before the
landing; then maintenance on all six hosts, Lab first, one owner per host, the
full-argument chezmoi update --apply with --exclude=dirs
--recurse-submodules=false --force=false, the reviewed re-init when
home/.chezmoi.toml.tmpl changed, the binding deleted only after the new code is
applied, the plan's login-hook proof (never a shell that inherits
_DOTFILES_CHECKED), then acceptance with the Phase 0 probe methods. Every
interactive shell you start on a remote host for a probe sets
DOTFILES_AUTO_UPDATE=0. Plain read-only chezmoi commands are fine; plain
mutating commands are not. Never force, stash, rebase or reset a host checkout;
restore maintenance on failure. Handle every one-time switch by explicit
commands under maintenance, never by compatibility code. After the landing, an
unreachable or blocked host stays an explicit exception, never false success.
Pre-existing provisioning gaps in the Stage 6 record are not regressions and
are not yours to fix.

Windows. Commands that change the win home run as the ordinary user, through
one-off scheduled tasks with the logged-on user's limited token (Interactive,
RunLevel Limited, no trigger), which need the user logged on and are deleted
after each run. The user gave standing approval for such tasks on 2026-11-07:
do not ask per run; record each task script's SHA-256 and log. The SSH route
into win carries an administrator token: use it only for read-only metadata
and to write such a task's script and register, start and delete it; never to
write managed targets, the source checkout, chezmoi config or state, or ACLs.

Sherlock. Before every cluster operation, and again after any summary or
context compaction, read /etc/agents/AGENTS.md and the task's topic files
(storage.md, slurm.md, software.md, policy.md) through the user's existing
control master: check it with
$HOME/.local/share/chezmoi-sherlock-kit-provisioning/.venv/bin/shk doctor, run
with that directory as the working directory, then read with
ssh -oBatchMode=yes -oProxyCommand=false sherlock-plain cat <file>. Their
numbered site rules take precedence. That directory is the separately approved
local controller project pinning sherlock-kit v0.6.0 (its uv.lock resolves the
tag to sherlock-kit commit 09a37281; the controller is not a Git repository):
call its absolute .venv/bin/shk, never uv run, and read its shk rules
workstation first. It is already approved and is the explicit exception to the
global rules "ask before adding one" and "never another project's copy", so do
not ask again. Dotfiles pins no sherlock-kit and never adds one. Never log in or
authenticate for the user, never ssh ... sbatch. Build environments only inside
a Slurm allocation, never under $SCRATCH. Probe zsh there with zsh -n ~/.zshrc.

Marlowe. Interactive login shells use the micromamba login env
($HOME/micromamba, env login); non-interactive shells see the system tools.
Run the doctor inside the login env. The site AppArmor profile block-node
denies node on login nodes: accepted, never work around it. Any env change runs
in a Slurm job. Its filesystem keeps ACLs ('+'): never use cp -p there, and
never assume $0 is a file when a script travels over ssh. Probe zsh there with
zsh -n ~/.zshrc.

Secrets and evidence. Metadata only: never print, copy or diff secret values,
OAuth or app-written auth state, private identities or decrypted content, and
never read what evidence directories, the recovery store or /tmp artifacts
hold; compare AI configs privately and log only equal/not equal and key names.
The eight approved Claude age ciphertexts, each host's live age identity
(~/.config/chezmoi/age/, never deleted) and the user's offline identity
recovery copy stay. In Phase 0, chmod -R go-rwx the user's world-readable
migration artifacts in /tmp and $TMPDIR on every host. Evidence, snapshots,
moved checkouts, Lab's recovery store and those artifacts are deleted only in
Phase H2's last step, after every host passed acceptance and the plan's
moved-copy proof ran, and only the exact list the user confirms; on each host,
before its first such deletion, confirm by exit status only that chezmoi there
decrypts with its live identity. Delete only with literal paths in visible
top-level commands (Lab: rm -r -- <paths>; Unix remote: ssh <alias> rm -r --
<paths>, one command per confirmed batch, no bash -c, heredoc, variable, glob or
uploaded script; rmdir for directories that must be empty; win:
Remove-Item -LiteralPath inside a limited task). Expect a permission prompt per
batch and run them while the user is present.

Deliverables: the landing on main with its exact CI and e2e run IDs; all six
hosts at the final main with per-host before/after, removed traces and
acceptance results; the zero-trace scan summary with every kept hit and its
reason; the decisions; updated agent memory entries; no Stage 7 worktree,
branch, ci/** or e2e-ci/** branch left and no stale remote-tracking ref on any
host. The final tree has no docs/chezmoi-migration/, so the report to the user
and the commit messages are the record. Report unfinished gates and blocked
hosts explicitly.
```
