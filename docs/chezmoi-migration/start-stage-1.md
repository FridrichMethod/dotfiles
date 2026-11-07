# Fresh-session prompt: Stage 1

> Archived: this stage is complete ([status.md](status.md)); do not start a session from this prompt.

Paste the following into a new session opened in the dotfiles repository. This
replaces both earlier startup prompts; the compatibility-removal work is part of
the staged migration. Later stages must write their own next-session prompt in
`status.md` using their actual results.

```text
Implement only Stage 1 of the chezmoi migration. Use multiple subagents with one
separate Git worktree and branch per write-capable agent, plus a coordinator
integration worktree. Use the available subagent-driven-development workflow,
adapted to the repository's explicit worktree and ownership rules.

Read these files first:
- AGENTS.md
- docs/chezmoi-migration/README.md
- docs/chezmoi-migration/status.md
- docs/chezmoi-migration/support-boundary.md
- docs/chezmoi-migration/fleet-rollout.md
- docs/chezmoi-migration/secrets-and-ssh.md
- docs/chezmoi-migration/sources.md
- docs/chezmoi-migration/stage-1-foundation.md
Read Stages 2 and 3 before finalizing Stage 1's interfaces and next handoff.

Inspect HEAD, git status, relevant diffs, local commits and existing worktrees.
The planning consolidation baseline was 1a9d30b, not a required checkout target.
Preserve later work and verify the actual intended base. The handoff package may
still be uncommitted: worktrees created from HEAD will omit it. Read it first,
then carry only this package intentionally into the integration worktree; do not
stash/discard user changes or assume another agent will provide missing docs.

The user wants native chezmoi deployment and configuration transforms, eventually
removing TOMLKit, .venv-sync, setup-sync.* and the custom sync backend. Login
automatic dotfiles updates must remain as a thin chezmoi adapter in Stage 4.
The user also accepts ending old-layout and obsolete-tool support at an explicit
cutoff with a manual upgrade procedure; do not reinstate an all-host-attestation
gate. No real-home upgrade or historical cleanup belongs in Stage 1.
The user has authorized agent-executed real migration, testing and exact legacy
retirement on the six hosts during Stages 4 and 6. Preserve that authorization
and do not defer reachable-host work to the user. Stage 1 also includes native
secrets/backend/SSH design and synthetic probes; do not read or enroll real tokens.

Select and verify a real chezmoi release, freeze the isolated fixture interface,
then delegate independent foundation probes, native JSON/TOML policy probes and
the current target/support-floor inventory. Keep dependent work sequential and
file ownership exclusive. The coordinator owns shared test/CI integration,
AGENTS.md and handoff edits. Use only temporary homes and synthetic config; do
not read credentials, apply to the real HOME, alter default installers/login
behavior, install a new Python environment or implement later-stage deletion.

Use current source and official versioned documentation to verify assumptions.
Record observed behavior, deliberate native-semantic changes and unresolved
requirements. Keep current permission-policy values and live-state ownership.
Do not recreate the legacy parser/writer framework to pass obsolete tests.
Do not restart the completed review fixes or the superseded external handoff.

Integrate sequentially, obtain an independent read-only review, and run focused
checks plus required aggregate checks (including pre-commit run --all-files).
Report actual native Linux/macOS/Windows evidence and any skips separately.
Follow active session authorization and repository rules for commits/publication;
this Stage 1 session does not deploy to real homes. Later Stage 4/6 sessions use
the recorded fleet authorization, subject to concrete auth/privilege/site limits.

Before finishing, update status.md with actual paths/revisions, checks, decisions
and remaining limits. Expand Stage 2 into executable tasks and update Stage 3
with verified native semantics. Refine farther stages when findings affect them.
Provide the next-session prompt, then stop at the Stage 1 boundary.
```
