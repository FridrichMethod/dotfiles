# Fresh-session prompt: Stage 5

```text
Implement only Stage 5 of the chezmoi migration. Do not restart completed
Stages 1-4, treat incomplete Stage 4 gates as passed, or perform Stage 6 source/
runtime retirement. Read docs/chezmoi-migration/status.md first and distinguish
candidate code, actual native fixture results, hosted validation and real hosts.

Start by inspecting HEAD, branch, status, the full staged AND unstaged diff,
untracked task files and worktrees at /tmp/dotfiles-chezmoi-stage4-integration,
branch chezmoi-stage4-integration. Its baseline is 1a9d30b. This is an uncommitted
aggregate carrying all Stages 1-4, not a committed branch tip. A worktree made
from bare HEAD loses the entire implementation. Preserve subsequent user work;
read the final status record for the complete backup patch and verify it against
the current aggregate before use. Carry all required tracked and untracked
candidate files to the new integration worktree, validate parity, and retain a
recoverable patch. Never reset/stash/discard or overwrite unrelated edits.

At handoff no candidate commit, hosted CI/bootstrap-e2e publication or real-home
migration has occurred. Do not invent release hashes or infer commit/push/landing
authority from D11 or this prompt. Prepare concrete reviewed changes first and
follow active authorization and exact-green-candidate repository gates. The
historical CI runs at 1a9d30b prove none of this candidate. D11 still authorizes
six-host operations after applicable checks, without another blanket rollout
question; specific auth/privilege/site/ownership blockers remain.

Read AGENTS.md and docs/chezmoi-migration/{README,status,inventory,sources,
stage-3-native-config,stage-4-takeover,takeover,stage-5-ecosystem,
stage-6-retirement,support-boundary,secrets-and-ssh,fleet-rollout}.md. Read
docs/{bootstrap,payloads,shell,config-sync,update-contract,testing}.md where their
callers change. Consult the final Stage 4 ledger/review/resolutions recorded in
status; /tmp/chezmoi-stage4-ledger.md and /tmp/chezmoi-stage4-review.md are local
supplemental evidence, not substitutes for the aggregate or completion record.

Use one coordinator integration checkout and separate branches/worktrees for
write-capable workers. Freeze exclusive paths before edits and integrate
sequentially. Independent read-only audits can run in parallel. The coordinator
owns shared profiles, manifests, doctor entrypoints, root docs/instructions,
mirrored skills, runners, hooks and CI unless explicitly delegated. Do not edit
the same checkout concurrently. Preserve recoverable patches and obtain
independent read-only review of the final aggregate.

Stage 4 candidate behavior: setup-host defaults to native provisioning and
installs pinned SHA256-verified chezmoi v2.74.0 at ~/.local/bin. Unix uses
S4-chezmoi and H7-native; Windows W1-chezmoi and HW-native. setup-host never
initializes/applies configuration or creates the ownership marker. Its HUMAN
handoff points to takeover.md. Explicit --legacy-stow / -LegacyStow retains the
old setup-sync/Stow path. Native doctor omits Stow/parser requirements; legacy
mode still checks them. Do not reimplement this split or create a sync venv.

The frozen native binding is ~/.config/dotfiles/native, a regular non-symlink
file with exactly three LF-terminated lines: dotfiles-chezmoi-v1, canonical HOME,
canonical repository root. Existing ~/.config/dotfiles/maintenance suppresses
future dotfiles/payload hooks and workers, including later logins. It does not
stop already running workers. Native config/cache/state are explicitly scoped
to ~/.config/chezmoi/chezmoi.toml, ~/.cache/chezmoi and
~/.local/state/chezmoi/chezmoi.boltdb. Preserve lib/chezmoi-guard.sh/.ps1 and
their direct-writer/explicit-destination guards while supported callers exist.
Never create another revision receipt, fleet registry or migration daemon.

Require Stage 4 safety-review closure before lifecycle simplification: routine
updates preserve existing regular files and foreign links newly introduced into
the managed set; missing/empty native state requires inspected recovery; repeat
init preserves encryption/backend and unknown local data; Windows finds the
provisioned binary without assuming .local/bin is on PATH and dispatches both
hooks from the validated source binding; malformed extra marker bytes are
rejected. Check actual regression results, not just patch presence. Keep
regular-file mode explicit in init and both adapters; stale local symlink mode
must not recreate source write-through. POSIX root-ancestor checks must not form
double-leading-slash UNC paths under Git Bash. Keep native
fast-forward-only updates, dirty/divergent refusal, no force/stash/rebase,
bounded noninteractive execution and generic nonsecret failure messages.

D6, D9 and D11 are resolved. Preserve the thin automatic native dotfiles login
adapter, the declared current-layout support cutoff without an all-host waiting
gate, and authorized agent execution on reachable hosts. D7 remains unresolved:
whether upstream payload installs/updates become explicit-only. Present the
concrete choice before changing that lifecycle. D6 does not answer D7.

Follow stage-5-ecosystem.md's exact retained/deleted caller tables. First audit
provisioning step IDs, asset ownership and doctor advice. Keep package managers
and config/bootstrap's existing manifests authoritative; no duplicate package
inventory or general orchestration framework. Bounded externals need destination,
current owner/updater, local-edit handling, .git need, verification/ref policy
and refresh timing justified before implementation. Ordinary apply remains
configuration-only, with no hidden install, sudo, authentication or HPC build.
Keep no-rc flags, pinned-download gates, inspect-only vendor boundaries, shared
Homebrew protections and write-free offline doctor/setup-host --check.

If D7 selects explicit-only payloads, remove profile auto callers, scheduler-only
--auto/--worker/-Worker paths, session markers, days/retries and stamp/failure/log
readers together only after the supported caller contract changes. Otherwise
retain them. Shared legacy callers cannot be broken merely because native ones
were removed; defer their code to Stage 6 rather than create a second scheduler.
Keep explicit sync-payloads/sync-skills small, bound to the correct source, using
upstream installers and config/payloads.tsv platform/channel interfaces. Kit
channel 0.7 has no native Windows install. Preserve local edits, bounded private
download staging, no pipe-to-shell and honest busy/person-required/failure
results. Preserve Windows stamp-publication correctness while that code exists.

Sherlock's host profile now sets DOTFILES_PAYLOAD_AUTO_UPDATE=0 because current
site rules forbid detached login-node workers. This required site override does
not settle D7 globally. Preserve explicit sync-payloads under site/allocation
rules; only remove the variable if all automatic callers are removed and the
no-worker guarantee remains. Before cluster work, re-read current site/topic
rules through the existing authorized master. Never authenticate for the user,
use a foreign/global toolkit in place of project-pinned shk, or build an HPC
environment outside an allocation or under SCRATCH. Respect OneDrive independent
clone rules and one operation owner per home/checkout.

User-approved secret scope is eight private static files, the three approved
host recipients and recovery recipient. Do not ask again for that scope or infer
new targets. Production enrollment remains pending secure recovery-identity
custody/bootstrap; consult its private record, preserve authorization and never
log names/values here. SSH stays ordinary configuration. No production dummy
credentials, private keys in Git, recurring OAuth refresh replay, or permanent
create-if-missing auth seeds. Keep consumer paths, app-written auth, SSH trust
and the existing recovery channel. Secret enrollment is unfinished Stage 4
operational work, not an invitation to redesign secrets during Stage 5.

Keep all legacy physical package paths and literal native bridges through this
stage. Stage 6 owns canonical source consolidation, stow-all/.stowrc/link-trust
deletion, old updater/elevated task retirement, historical Stow repairs/shim,
stow-links payload metadata and the entire parser chain: setup-sync.*,
requirements-sync.txt, .venv-sync, lib/sync-runtime.sh, lib/config_sync.py,
the four legacy sync wrappers, DOTFILES_SYNC_PYTHON and their CI/runner/hooks.
Remove old checkout diagnostics and AWESOME_SKILLS_AUTO_UPDATE only as the
coherent scoped Stage 5 deletions in the map, with notice ending its old
2027-01-31 promise. Never delete user checkouts, modules, caches or payload trees.
Exact host-side runtime retirement happens only after its callers/replacement
checks are complete under D11 and Stage 6. Old updaters can still pull a deletion
commit; a support cutoff is not a technical barrier. Quiesce exact old workers
and owned Windows task before crossing the breaking revision.

Preserve seven explicit local [data].host roles, native source totals and all
portable policy values. The native AI modify templates use builtin jq/TOML,
no child jq/Python/TOMLKit; authoritative Claude arrays, local Claude model,
typed Codex ownership/retired-key enforcement and unknown live state survive.
Local TOML date/time/datetime and JSON U+FFFD are deliberately rejected before
affected-target writes; UTC is not a Windows fix. No whole-home transaction.
Read Stage 3/source evidence before touching transforms; ecosystem simplification
does not authorize policy changes. Preserve non-exact shared parents, binary/
empty/CRLF data and private/executable attributes.

Do not silently raise tool floors: tmux 3.4 is a candidate, not selected merely
by this prompt; existing floor is 2.6. Keep all five tmux files, plugin/clipboard/
battery/cache/menu/reload behavior. Retain both Claude plugin IDs and root
CLAUDE.md import stub until actual client evidence supports a coherent decision.
Bash 3.2, PowerShell 7 entrypoints/5.1 profile and Python 3.11 stdlib roles remain
unless a concrete tested benefit justifies changing them. A new macOS Bash must
actually be invoked, not merely installed. No new Stow floor is needed.

Tests first for changed behavior, then focused provisioning/payload/diagnostic
suites, actual native Linux/macOS/Windows tests, tests/run.sh --ci,
tests/run.ps1 -CI, full pre-commit and independent review. Reuse the existing
legacy DOTFILES_SYNC_PYTHON read-only where old suites require it. Preserve
tests/chezmoi.* and chezmoi-takeover.*, guard/provision/update-config/recovery
modules and current platform behavior. Bootstrap e2e uses explicit legacy flow,
then native provisioning plus isolated takeover/recovery with a required native
binary and tests/test_chezmoi_takeover_recovery.py. Do not label it real HOME
migration. Hosted exact-candidate CI/e2e still needs actual runs/authorization.
Record native passes/skips separately; Mac tmux 3.8 has previously recorded
adversarial-menu failures, so do not report it green or fix it silently.

Update status, inventory, canonical docs, mirrored skills and ownership/removal
tables with actual outcomes. Measure code/test reductions; do not claim startup
speedups without measurement. Record every surviving helper's reason and every
remaining legacy caller. Expand Stage 6 into the exact final deletion and
native-only verification plan plus its fresh-session prompt. Stop after Stage 5;
report incomplete Stage 4/host/recovery gates explicitly rather than erasing them.
```
