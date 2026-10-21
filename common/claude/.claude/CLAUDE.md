# Global Working Preferences

## Background

- The user is a PhD student at Stanford Bioengineering and Computer Science.
- Their main interests are protein engineering, enzyme design, diffusion models, inverse folding models, machine learning, and pure mathematics.
- Assume strong technical fluency. Use domain terminology precisely and explain introductory material only when it is needed for the task.

## Communication

- Match the language of the user's request. When the user writes in Chinese, respond in Chinese while keeping standard English technical terms where they improve precision.
- Lead with the result, recommendation, or diagnosis. Keep routine explanations compact, but make assumptions, uncertainty, and important tradeoffs explicit.
- Prefer concrete evidence, exact file paths, commands, equations, tensor shapes, residue identifiers, and test results over generic advice.
- Distinguish confirmed facts, inferences, hypotheses, and open questions.

## Autonomy and scope

- Work autonomously on clearly scoped, reversible local tasks: inspect the relevant context, implement the change, and validate it without unnecessary confirmation.
- Ask only when a missing choice would materially change the result or when additional authorization is required.
- Preserve unrelated user changes and existing repository conventions. Do not broaden the task into unrelated cleanup or dependency upgrades.
- Do not commit, push, open or merge a pull request, deploy, publish, or modify shared or remote state unless the request authorizes that action.
- Before destructive or difficult-to-reverse actions, explain the exact target and obtain explicit approval.

## Multiple agents and Git

- Assume Claude Code and Codex may be active on the same project at the same time.
- Do not let two write-capable agents edit the same checkout concurrently. Prefer a separate Git worktree and branch for each agent or task.
- Before editing, inspect repository status and relevant diffs. Treat existing modifications as user-owned unless clearly produced by the current task.
- Never discard, reset, stash, amend, rebase, or overwrite user work unless explicitly requested.
- When commits are requested, keep them atomic and reviewable, stage files deliberately, and do not use `git add .` blindly.
- When creating commits or pull requests, do not add `Co-Authored-By` trailers, "Generated with" lines, or any other AI or agent attribution.

## Git in a OneDrive-synced checkout

These rules apply whenever `git rev-parse --show-toplevel` contains `OneDrive`, and they override the worktree preference above. A repository's own `AGENTS.md` adds only what is specific to it, such as how to set up a clone.

- OneDrive syncs `.git` between machines one file at a time and in no order, while one git command writes refs, the index and many objects together. The other machine can receive a ref without the objects it names, and objects can be lost outright. A plain `git fetch` cannot refill a hole, because it tells the remote which commits are already present, and a missing subtree stays silent until an incoming commit touches it, so a pull that succeeds proves nothing.
- In such a checkout, edit files and run read-only git commands (`git status`, `git diff`, `git log`, `git fsck`); every other git write is one of the steps in this section. Never run `git pull`, `git commit`, `git worktree add`, a rebase, `git gc`, or any merge other than the `--ff-only` steps below. A worktree is no escape: it shares the OneDrive object store, and its metadata records an absolute path that does not exist on the other machine. Make changes in an independent clone on local disk, which is an ordinary repository.
- Never create, sync or rebuild a project environment that lives inside such a checkout, such as the `.venv` that `uv sync` and `uv run` maintain or a `node_modules`; run commands that need one in the clone. Environments sync like everything else, and `uv run` on the other OS deletes a `.venv` it did not build ("Removed virtual environment at: .venv") and creates its own, which then replaces the first machine's copy.
- Set `core.fileMode=false`, `maintenance.auto=false` and `gc.auto=0` in the repository's `.git/config`, and set them again whenever `.git` is replaced. Automatic maintenance repacks: it writes a new pack and deletes the old ones, the change OneDrive is most likely to deliver half-done. The config is shared by both machines, so a machine-specific path in it (a textconv driver, say) is wrong on the other one; never copy one into a clone.
- The sync also flips executable bits, rewrites line endings and touches mtimes. A path you did not change that shows zero insertions and deletions, a `mode change` in `git diff --summary`, or nothing in `git diff --ignore-all-space --stat` is sync churn: never revert it, and trust `git diff --quiet` over `git status`, whose stat cache goes stale.
- On macOS, a git command that hangs instead of erroring is reading a dataless placeholder, and it can survive `SIGKILL`; never conclude from a failed read that a file is missing or the repository is broken. Finder's "Always Keep on This Device" does not fix it. Before running git in such a checkout on macOS, list placeholders without reading them:

  ```bash
  python3 - .git <<'EOF'
  import os, sys
  for d, _, fs in os.walk(sys.argv[1]):
      for f in fs:
          st = os.lstat(p := os.path.join(d, f))
          if st.st_size > 0 and st.st_blocks == 0:
              print(p)
  EOF
  ```

  If it prints anything, run no git command there and tell the user. The repair, once the user confirms that no local branch holds unpushed commits, is to swap in the `.git` of a fresh `git clone --no-checkout`, run `git reset`, and reapply the settings above.

### Sync with the remote instead of `git pull`

With a clean working tree (`git status --porcelain` prints nothing; `main` stands for the default branch throughout):

```bash
git fetch --refetch --no-auto-maintenance --no-write-commit-graph origin
git fsck --connectivity-only        # only "dangling ..." lines are acceptable
git -c maintenance.auto=false merge --ff-only origin/main
```

- `--refetch` downloads every object as a fresh clone would, which refills any hole. Each run adds one full pack; leave the duplicates. If `git count-objects -vH` reports more than about 100 MB in packs, ask the user before refetching.
- An `fsck` error that names only the commit-graph (`failed to parse commit <sha> ... for commit-graph`) is a stale cache: delete `.git/objects/info/commit-graph` and `.git/objects/info/commit-graphs/`, then run `fsck` again. If it still reports `missing` or `broken link`, stop and report it.
- If `--ff-only` is refused, the local branch has commits the remote lacks: integrate them in a clone, never here.

### Change it: clone out, merge back, clean up

```bash
ONEDRIVE="$(git rev-parse --show-toplevel)"   # in the OneDrive checkout, after syncing it
CLONE=/tmp/<repo>-<slug>                      # local disk; Git Bash maps /tmp to %TEMP%

# 1. Clone the remote, then take any local commits it does not have yet.
git clone "$(git remote get-url origin)" "$CLONE"
git -C "$CLONE" pull --ff-only "$ONEDRIVE" main

# 2. Set the clone up as the repository's AGENTS.md says, then work there as in any
#    repository: branch, edit, run the checks, commit, and land the work on main.

# 3. Bring main back as a fast-forward, as one pack rather than loose objects.
cd "$ONEDRIVE"
git -c fetch.unpackLimit=1 fetch --no-auto-maintenance "$CLONE" main
git -c maintenance.auto=false merge --ff-only FETCH_HEAD
git fsck --connectivity-only

# 4. Delete the clone only when everything in it has reached this checkout.
test -z "$(git -C "$CLONE" log --oneline --branches --not main)" &&
  git merge-base --is-ancestor "$(git -C "$CLONE" rev-parse main)" main &&
  rm -rf "$CLONE"
```

- A project environment that lives outside the checkout, such as a conda env with an editable install, still imports the OneDrive copy when used from the clone; the repository's `AGENTS.md` says how to point it at the clone.
- If step 3 refuses the fast-forward, `main` moved here while you worked: run `git -C "$CLONE" pull --no-rebase "$ONEDRIVE" main`, rerun the checks in the clone, and repeat step 3.
- Push only when asked, from the clone and before step 4 (`git -C "$CLONE" push origin main`); otherwise say that this checkout is now ahead of the remote.
- To carry over edits already made here, stage them (`git add <paths>`), save `git diff --cached` to a patch outside the checkout, `git -C "$CLONE" apply` it, and keep them staged through step 3: the fast-forward refuses unstaged local edits and untracked files even when they match, but accepts staged ones.

## Engineering workflow

- Read the repository's own instruction files first; more specific project instructions override these global preferences.
- Reuse the project's existing environment, package manager, style, abstractions, and test commands.
- Prefer the smallest coherent change that solves the problem. Add or update tests when behavior changes.
- Validate in proportion to risk: run focused checks first, then broader tests when justified. Report what was run and any checks that could not be completed.
- For reviews, prioritize correctness, security, scientific validity, regressions, numerical issues, concurrency, and missing tests over cosmetic style comments.
- For long-running or parallelizable work, delegate bounded independent subtasks, keep write ownership disjoint, and consolidate evidence in the main task.
- In the user's own repositories, `AGENTS.md` is the single source of project instructions and `CLAUDE.md` is a stub that imports it; add or change project rules in `AGENTS.md`, never in the stub.

## Scientific and mathematical work

- Prefer primary literature, official documentation, and authoritative databases. Verify current, niche, medical, legal, financial, or otherwise high-stakes claims before relying on them.
- Make analyses reproducible: record data provenance, preprocessing, units, seeds, software versions, configurations, assumptions, and evaluation definitions when relevant.
- For protein and enzyme work, preserve exact sequences and distinguish chain IDs, residue numbering schemes, wild type versus mutation, construct boundaries, assay conditions, and computational predictions versus experimental evidence.
- For machine learning, track tensor shapes, dtypes, devices, train/eval mode, masking, data splits, leakage risk, baselines, ablations, uncertainty, and evaluation metrics.
- For mathematical arguments, state assumptions and quantifiers, check edge cases, and separate intuition from proof.

## Completion standard

- Inspect the final diff or artifact before reporting completion.
- State the outcome, key changes, validation performed, and remaining risks or limitations.
- When blocked, identify the concrete blocker and the smallest user action needed to continue.

## Stanford Sherlock

- Before Sherlock work, and again after a summary or context compaction, read `/etc/agents/AGENTS.md` and the task's topic files (`storage.md`, `slurm.md`, `software.md`, `policy.md` beside it). Their numbered site rules take precedence. On Sherlock, read them locally. From a workstation, check the user's existing control master with the project's `shk doctor`; once usable, read with `ssh -oBatchMode=yes -oProxyCommand=false sherlock-plain cat /etc/agents/AGENTS.md`, then read the topic files through the same master. Never log in or authenticate for the user.
- Use the current project's own pinned sherlock-kit (`shk`) for jobs, status and transfers. If it has none, ask before adding `sherlock-kit @ git+https://github.com/FridrichMethod/sherlock-kit@<latest release tag>` to its environment. Preserve existing project pins; never use a global, another project's or a development copy, or fall back to `ssh ... sbatch`.
- Read that install's `shk rules workstation` (on Sherlock: `shk rules cluster`). `shk install-skill --project DIR --rules workstation|cluster` copies the skill and requested Claude rules; Codex gets a hint to append the rules output to the project's `AGENTS.md` and must read the rules directly if they are not loaded.
- Inside Sherlock jobs, invoke the project's pinned install on Sherlock by absolute path from an environment in `$GROUP_HOME`, or use the skill's `sha256sum` one-liner for manifests. Build environments only inside a Slurm allocation.
