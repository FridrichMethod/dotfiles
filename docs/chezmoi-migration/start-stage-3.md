# Fresh-session prompt: Stage 3

> Archived: this stage is complete ([status.md](status.md)); do not start a session from this prompt.

```text
Implement only Stage 3 of the chezmoi migration. Do not redo Stage 2 or continue
automatically into Stage 4; no real HOME takeover or secret enrollment here.

First inspect HEAD, status, full diff and worktrees at
/tmp/dotfiles-chezmoi-stage2-integration, branch chezmoi-stage2-integration.
The result is uncommitted on baseline 1a9d30b and includes the full Stage 1
result. Its complete backup is /tmp/chezmoi-stage2.patch; status.md is the evidence
record. Preserve subsequent user work. A new worktree from bare HEAD loses both
stages: explicitly carry their entire required result. Do not stash, reset,
discard or overwrite unrelated files. No commit/publication without active
authorization and repository landing checks.

Read AGENTS.md and docs/chezmoi-migration/{README,status,inventory,sources,
stage-3-native-config,stage-4-takeover,support-boundary,secrets-and-ssh,
fleet-rollout}.md. Use one coordinator integration worktree and separate
branch/worktree per writable worker. Freeze the portable input and typed
ownership interfaces first; parallelize Claude and Codex only after dependent
native-preservation decisions. Integrate sequentially, then obtain independent
read-only review. Retain exact file ownership and recoverable patches.

Stage 2 creates .chezmoiroot=home and .chezmoiversion=2.74.0, 67 ordinary native
source files, explicit local [data].host and one validation guard. Valid roles
are common-only/mac/wsl-ubuntu/lab-ubuntu/sherlock/marlowe/win. Missing/empty/type/
unknown/incompatible roles fail; DOTFILES_HOST and OS detection never select one.
Init loads home/.chezmoitemplates/validate-host using includeTemplate because
named templates are unavailable there. Ordinary legacy contents use literal
include rooted at .chezmoi.workingTree, never template evaluation. Legacy source
remains canonical through Stage 6; WebP/terminfo are the only raw copies and
have parity tests. Keep all current installers/login defaults/legacy paths.

Use tests/chezmoi_source_support.py SourceFixture(host) and expected_entries(host)
plus the existing isolated native harness. Native child PATH is empty and all
source/destination/config/cache/state/HOME paths are temporary. Inventory has
95 package rows. Ordinary target sets are 47/54/53/57/52/52/24; adding exactly
the two AI targets yields 49/56/55/59/54/54/26. Four legacy helper definitions
stay absent. Rules and lab fcitx5 profile remain ordinary; shared parents are
non-exact and preserve unmanaged state. Retain zero-byte configs, all five tmux
files, binary/CRLF bytes and native umask/private/executable behavior.

Implement home/dot_claude/modify_private_settings.json and
home/dot_codex/modify_private_config.toml (chezmoi:modify-template directive,
no .tmpl suffix). Read canonical portable values via literal include from
common/claude/.claude/settings.json and common/codex/.codex/config.toml. No
duplicate independently editable policy. If needed, codex-policy.json under
home/.chezmoidata holds only typed owned/retired paths and gets a parity test
against current lib/config_sync.py constants. Preserve all policy VALUES,
authoritative Claude arrays, local model, exact Codex ownership and unknown live
state. No external jq/Python/TOMLKit/custom parser/writer in the native path.

Begin with the unresolved TOML local-temporal safety issue: v2.74.0 can shift
date/time/datetime wall values. Unix TZ=UTC is not a Windows fix; actual Windows
UTC/LA/Tokyo probes all shifted local time/datetime on the tested host. Obtain
a verified native correction or fail safely before writing affected input,
documenting any unsupported valid input. Never silently lose unknown values or
call a characterization test preservation. Also test CRLF multiline basic and
literal strings, quoted dotted keys, literal '*', int64, offset timestamps,
ancestor type collisions and native JSON numeric/duplicate limits. Malformed
or invalid input preserves the affected target; no whole-home transaction is
promised. Native conflict may return 1 with empty stderr.

Retain both Claude plugin IDs pending a coherent supported-client decision;
official rename direction differs from old prose. Do not raise tmux/Bash/PS
floors in unrelated mapping. --migrate-portable is absent from the native API;
legacy backend remains for old callers until Stage 6. Final removal of TOMLKit,
.venv-sync, setup-sync and merger remains mandatory, but is not this stage.

Builtin age is selected; separate host identities and per-file recipients are
synthetically verified. Any Stage 3 static-secret representation is optional
and synthetic until private allowlists/trust groups/bootstrap access are settled
for Stage 4. No production dummy credentials, token reads, key enrollment or
recurring replay of app-written OAuth refresh state. Keep SSH recovery/trust and
consumer paths. Never exact/remove shared app, SSH or payload directories.

Run real native Linux/macOS/Windows isolated fixtures. Existing authorized SSH
routes may use private temporary directories; transfer only reviewed source and
synthetic fixtures. Reverify official runtime provenance and transferred hashes.
Reuse existing legacy DOTFILES_SYNC_PYTHON read-only for old suites; do not create
a parser environment. Stage 2 explicitly authorized read-only Windows existing
test-runtime reuse without app/profile/token reads. Windows profile metadata for
both shells matched fixed Documents targets; redirected Documents requires a
Stage 4 preflight/mapping decision, never guess from synthetic HOME. Synthetic
administrative ACL evidence does not prove a real ordinary-user destination ACL.

Stage 2 also records a pre-existing native Mac tmux 3.8 adversarial-directory
menu limitation: 12/13 legacy test methods pass, three menu subtests fail, while
the native source suite passes. Do not call that legacy check green or silently
rewrite tmux configuration during the AI-transform stage. Store-Python and tmux
test-only isolation corrections are already integrated; preserve their evidence.

Run focused native transform/negative tests, complete candidate apply without
merge subprocesses, tests/run.sh --ci, native tests/run.ps1 -CI, full pre-commit
and independent review. Add narrow parser exclusions only for native modify
templates; parse/lint rendered output and keep portable/ownership data checked.
Report actual native passes and skips separately from supplemental OS rendering
and from unpublished hosted CI. Update status/inventory/sources, refine Stage 4
to concrete executable takeover/quiescence/secret/recovery tasks and provide its
next-session prompt. Preserve D6 thin login updates and the existing six-host
Stage 4/6 agent execution authorization, with explicit support cutoff and no
all-host waiting gate. Stop at Stage 3.
```
