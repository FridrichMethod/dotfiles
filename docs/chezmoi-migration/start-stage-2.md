# Fresh-session prompt: Stage 2

> Archived: this stage is complete ([status.md](status.md)); do not start a session from this prompt.

```text
Implement only Stage 2 of the chezmoi migration; do not restart Stage 1 or
continue automatically into Stage 3.

First locate the completed Stage 1 work. Its integration branch/worktree is
chezmoi-stage1-integration at /tmp/dotfiles-chezmoi-stage1-integration, based on
1a9d30b, with uncommitted changes. The original checkout retains the original
untracked handoff package. Inspect actual HEAD, git status/diff, branches and
worktrees; preserve later user work. Do not start from bare HEAD and lose the
Stage 1 tests/docs. If moving work, explicitly carry its complete scoped patch
(status.md records its location), not only the old handoff. Do not stash,
discard, reset or overwrite unrelated changes. Commits/publishing require the
active session authorization and repository landing rules.

Read AGENTS.md and docs/chezmoi-migration/{README,status,inventory,sources,
stage-2-source-state,stage-3-native-config,support-boundary,secrets-and-ssh,
fleet-rollout}.md. Use one coordinator integration worktree and one separate
branch/worktree per writable subagent; freeze host/bridge interfaces first,
assign exact disjoint target subtrees, integrate sequentially and obtain an
independent read-only review.

Stage 1 selected and SHA256-verified chezmoi v2.74.0. Its 23 native probes run
with temporary source/destination/config/cache/state/HOME, empty child tool
PATH and synthetic secrets. Binary at /tmp/dotfiles-chezmoi-stage1-runtime/chezmoi
may still exist; reverify version/provenance rather than assume it does. Use
DOTFILES_TEST_CHEZMOI or resolve an existing verified binary. No network inside
behavioral tests or new parser environment. The old suites may reuse an existing
DOTFILES_SYNC_PYTHON; do not call setup-sync merely to create a fresh environment.

Implement the executable Stage 2 packages, beginning with linked-worktree/space
path literal include proof, .chezmoiroot=home, .chezmoiversion=2.74.0 and explicit
[data].host. Missing/empty host must fail rather than mean common-only. Preserve
native Windows's six common-package allowlist and actual profile discovery.
Inventory has 95 tracked package rows. Native Stage 2 ordinary file totals are
47/54/53/57/52/52/24 for common-only/mac/wsl-ubuntu/lab-ubuntu/sherlock/marlowe/win.
Compare exact target sets and bytes, not only counts. Omit the two AI mutable
targets for Stage 3 and the four legacy helper definitions as applicable;
portable.rules and lab fcitx5 profile remain ordinary native targets. Preserve
all five tmux files, binary assets, CRLF exceptions and empty_ configurations.

Use temporary literal include bridges rooted at .chezmoi.workingTree for text;
legacy content remains canonical until Stage 6. Raw asset copies need byte-parity
checks and an owner/removal stage. Do not duplicate independently editable policy,
port symlink-climbing legacy sync wrappers, or render shell text as Go templates.
Keep all runtime installer/login defaults and legacy source paths intact.

Known native condition: local TOML date/time/datetime can shift outside UTC.
Stage 1 characterizes UTC/LA/Tokyo; native Windows observations confirm TZ=UTC
does not prevent local temporal shifts on the tested host. It is
a Stage 3 safe-preservation blocker, not approval of value loss; do not add a
custom parser. JSON duplicate/numeric and native path signatures are in sources.
add --follow imports bytes but leaves symlinks; controlled takeover is Stage 4,
never routine force. Conflicts may exit 1 with empty stderr.

Builtin age is selected. Separate native host identities and explicit per-file
recipient override are synthetically proved; real allowlists, host trust groups
and secure first-key/recovery access remain private enrollment choices. Preserve
app-written refresh state. No actual token/SSH key reading or enrollment in this
stage; no dummy credentials in production source. Preserve both Claude plugin
IDs pending supported-client evidence; official ID rename differs from old prose.
Do not raise tmux/Bash/PowerShell floors while merely mapping source.

Keep the final direction: native deployment/transforms eventually remove TOMLKit,
.venv-sync, setup-sync and custom merger; thin chezmoi login updates remain.
Old layouts/tools end at an explicit cutoff without all-host attestation. The
user has already authorized agent execution of migration/tests/exact retirement
on six hosts in Stages 4/6; retain that authority and do not defer reachable-host
operations to the user. Stage 2 remains fully isolated with no real HOME takeover;
native platform fixtures may use private remote temporary directories through
existing authorized access, without live app/secret operations.

Run focused native/source-state and preserved behavior tests, tests/run.sh --ci
(Windows tests/run.ps1 -CI), full pre-commit and independent review. Report actual
native Linux/macOS/Windows execution and skips separately; Stage 1 ran actual
isolated fixtures on all three and both native entrypoints, but did not publish
CI or perform real app takeover. Windows skipped the Unix-specific TZ assertion,
with supplemental native temporal/ACL observations. Update status.md,
inventory and sources, refine Stage 3 into exact tasks using implemented paths,
adjust later dependencies and supply the Stage 3 prompt. Stop at Stage 2.
```
