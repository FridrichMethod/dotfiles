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
- Keep routine, scoped cleanup autonomous. Simple file deletion, empty-directory removal, and moves inside the active workspace may proceed when the exact targets are known; prefer `apply_patch` for tracked files and recoverable trash operations when practical.
- Route recursive or forced deletion, destructive Git operations, disk/device mutation, and privilege escalation through their direct canonical commands so exec-policy can send them to automatic review. Never bypass a `prompt` decision through a shell, interpreter, script, alias, alternate executable path, or equivalent indirect operation.
- Before an exceptionally destructive action, resolve and report every target, explain impact and recoverability, and obtain explicit user authorization. This includes recursive deletion aimed at a filesystem, home, workspace, or repository root; mount points, device paths, broad or ambiguous globs; disk overwrite, formatting, wiping, or partitioning; and operations likely to destroy irreplaceable or untracked data. Bounded cleanup of verified build, cache, test, or temporary outputs may rely on automatic review without a separate user prompt.

## Multiple agents and Git

- Assume Claude Code and Codex may be active on the same project at the same time.
- Do not let two write-capable agents edit the same checkout concurrently. Prefer a separate Git worktree and branch for each agent or task.
- Before editing, inspect repository status and relevant diffs. Treat existing modifications as user-owned unless clearly produced by the current task.
- Never discard, reset, stash, amend, rebase, or overwrite user work unless explicitly requested.
- When commits are requested, keep them atomic and reviewable, stage files deliberately, and do not use `git add .` blindly.
- When creating commits or pull requests, do not add `Co-Authored-By` trailers, "Generated with" lines, or any other AI or agent attribution.

## Engineering workflow

- Read the repository's own instruction files first; more specific project instructions override these global preferences.
- Reuse the project's existing environment, package manager, style, abstractions, and test commands.
- Prefer the smallest coherent change that solves the problem. Add or update tests when behavior changes.
- Validate in proportion to risk: run focused checks first, then broader tests when justified. Report what was run and any checks that could not be completed.
- For reviews, prioritize correctness, security, scientific validity, regressions, numerical issues, concurrency, and missing tests over cosmetic style comments.
- For long-running or parallelizable work, delegate bounded independent subtasks, keep write ownership disjoint, and consolidate evidence in the main task.

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
