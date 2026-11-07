# Fresh-session prompt: Stage 4

> Archived: this stage is complete ([status.md](status.md)); do not start a session from this prompt.

```text
Implement only Stage 4 of the chezmoi migration. Do not redo Stage 3 or proceed
automatically into Stages 5/6. Keep legacy physical source paths through this
compatibility stage. Read status.md before any operation; distinguish completed
candidate code, actual platform fixtures, unpublished CI and real-host rollout.

First inspect HEAD, branch, status, full diff and worktrees at
/tmp/dotfiles-chezmoi-stage3-integration, branch chezmoi-stage3-integration.
The uncommitted result is on baseline 1a9d30b and includes the entire Stage 1/2
result. Complete backup: /tmp/chezmoi-stage3.patch. Preserve subsequent user work.
A fresh worktree from HEAD loses all three stages: explicitly carry the complete
required result. Do not stash/reset/discard or overwrite unrelated work. No
commit/publication without active authorization and the repository landing gates;
prepare a concrete reviewed candidate before requesting any missing authorization.

Read AGENTS.md and docs/chezmoi-migration/{README,status,inventory,sources,
stage-3-native-config,stage-4-takeover,stage-5-ecosystem,stage-6-retirement,
support-boundary,secrets-and-ssh,fleet-rollout}.md. Use one coordinator integration
worktree and a separate branch/worktree for every writable worker. Freeze the
home-binding/writer-guard and native update interfaces before parallel Unix and
Windows changes. Integrate sequentially, retain recoverable patches, and obtain
independent read-only review.

Stage 3 has .chezmoiroot=home, minimum 2.74.0, 67 ordinary sources, exactly two
private AI modify templates (no .tmpl suffix), and value-free typed Codex
ownership metadata. Both AI policies and ordinary text still read canonical
legacy files literally from .chezmoi.workingTree; never evaluate them as Go
templates or create independently editable duplicate policy. WebP/terminfo are
the only raw bridge copies and have parity checks. Keep all five tmux files,
binary/CRLF bytes, zero-byte configs and native private/executable/umask behavior.
Inventory is 95 rows; complete target totals are 49/56/55/59/54/54/26 for
common-only/mac/wsl-ubuntu/lab-ubuntu/sherlock/marlowe/win. Four legacy helper
definitions remain absent from native targets; portable.rules and lab fcitx5
profile remain ordinary. Shared app/SSH/payload parents are non-exact.

Local [data].host is mandatory. Missing/empty/type/unknown/incompatible roles
fail; DOTFILES_HOST and OS detection never select one. Init uses includeTemplate
only to load the shared validate-host guard. Reuse SourceFixture(host),
expected_entries(host) and the existing isolated native harness. Children have
empty PATH; all source/destination/config/cache/state/HOME paths are temporary.

Preserve all portable VALUES, authoritative Claude arrays, local Claude model,
exact Codex ownership/retired keys and unknown live state. Claude uses builtin
jq fromjson on raw input, retaining json.Number tokens through merge/output;
fromJson is lossy for some numbers. Permission elements use typeIs string,
not kindIs. Duplicate JSON keys are native last-value-wins. Parsed U+FFFD is
refused, including intentional U+FFFD, to avoid silent invalid UTF-8/surrogate
repair. Codex uses native TOML only, list setters and validated table ancestors.
Its literal-read metadata has parity with current legacy constants; local data
cannot expand ownership. No external jq/Python/TOMLKit/custom parser or writer.

TOML local date/time/datetime is explicitly unsupported and fails before writing
the affected target, anywhere in either input. Actual Windows UTC/LA/Tokyo raw
probes all shift local time/datetime; TZ=UTC is not a fix. Never bypass or weaken
the guard for a real home. Offset timestamps/int64/quoted dotted and literal-star
keys survive. Physical CRLF normalizes to LF with basic/literal multiline and
continuation tests; explicit escaped CRLF survives. Canonical comments/layout
change intentionally. Malformed/invalid input preserves the affected target;
no whole-home transaction. Native conflict may return 1 with empty stderr.

Keep both Claude plugin IDs; official pre-2.1.285 is agents-md@builtin, current
is cc-plugin-agents-md@builtin and newer clients accept either. No client-floor
change was established. Do not raise tmux/Bash/PowerShell floors in takeover.
--migrate-portable is absent from native API; legacy backend/API remains until
Stage 6. Final removal of TOMLKit/.venv-sync/setup-sync/merger is mandatory,
but deleting legacy paths/runtime is not Stage 4.

Follow Stage 4's ordered work packages: prove per-home old-writer refusal,
effective maintenance across new logins, exact worker/task quiescence, native
fast-forward update with no stash/rebase, targeted owned-link takeover and
recovery preserving edits since backup. Preserve D6 thin automatic login updates;
do not replace them with manual-only updates, receipts or background services.
Keep payload scheduling's separate Stage 5 decision open. Native Windows regular
file update must be unelevated with no login UAC or elevated restow task.

Before takeover, query actual CurrentUserAllHosts metadata for both Windows shells
using NoProfile. Fixed Documents targets were verified on one host only;
redirected Documents requires explicit mapping/preflight before writes. Inspect
actual destination ACLs under the real user; protected administrative fixture
ACLs do not prove ordinary-user safety. Snapshot exact targets privately, prove
legacy link ownership and use force only for an individually reviewed backed-up
link conversion. Never force routine apply, import whole app directories, use
exact/remove on shared parents, or restore old links over newer app edits.

Builtin age with separate host identities and per-file recipients is selected
and synthetically verified. Stage 3 selected no production static-secret target.
Before real enrollment resolve private allowlists, current channel-0.7 consumer
writer classification, trust groups, secure first-identity access and recovery
custody. Do not infer static credentials from filenames or read tokens to classify
them. No production dummy credentials, private keys in Git, recurring OAuth
refresh replay or permanent create-if-missing auth seeds. Preserve consumer paths,
SSH trust and recovery access. Normal logs/diffs use nonsecret target allowlists.

D11 six-host Stage 4/6 execution authority persists: implement, test and migrate
reachable hosts using existing authorized access after required candidate/CI
checks. Do not ask again for blanket rollout permission or leave executable
work as a manual TODO. Specific auth/MFA/privilege/site/ownership blockers remain.
Start with one recoverable canary, keep the old channel until new access passes,
then expand with one operation owner per independent home/checkout. Re-read
current Sherlock site/topic rules through the user's existing master and use
project-pinned shk where required; never authenticate for the user or build an
HPC environment outside allocation. Respect OneDrive independent-clone rules.

Publish concrete supported layout/tool floors and immutable last-Stow/first-native
revisions only when real release commits exist. Quiesce old dotfiles AND payload
hooks/workers and the exact Windows task before crossing/publishing a breaking
revision. A support cutoff cannot stop an old updater pulling a deletion commit.
Keep the tested bridge/clean-clone/recovery procedure, explicit offline-host
exceptions and no all-host waiting gate. Record repository completion separately
from actual per-host success; do not call blocked hosts migrated.

Run native Linux/macOS/Windows takeover/recovery fixtures, tests/run.sh --ci,
native tests/run.ps1 -CI, full pre-commit, independent review and required exact
green candidate CI/e2e before authorized landing/rollout. Reuse existing legacy
DOTFILES_SYNC_PYTHON read-only for old suites; no new parser environment. Prior
authorization covers Windows existing test-runtime reuse without app/profile/
token reads. Preserve Stage 2 Store-Python and tmux isolation corrections.
Mac tmux3.8 still has the pre-existing three adversarial-menu subtest failures
(12/13 methods); native source tests pass. Do not call legacy tmux green or fix
it silently during takeover. Report actual native passes/skips separately from
supplemental rendering, hosted CI and real GUI/application checks.

Update status/inventory/sources and exact per-host evidence. Refine Stage 5 into
a concrete retained/deleted caller map, with a fresh-session prompt. Stop at
Stage 4; keep source/runtime retirement and remaining host cleanup for Stage 6.
```
