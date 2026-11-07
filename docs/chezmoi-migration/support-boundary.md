# Current-layout and tool-version support boundary

This is part of the chezmoi migration, not a separate implementation project.
It consolidates the remaining current-layout-only handoff from the completed
review/fix session. Integration baseline: `1a9d30b`. Re-read current source before
using the symbol/path inventory below; do not delete by old line numbers.

## Stage 4 candidate boundary

The corrected Stage 4 release reached local and remote main at
`bf9995809ca7564c0728f87bcbefe91c8a3cc5e0` after all three CI 41567805090 jobs
and all eight bootstrap e2e 41567805363 jobs passed. Lab's actual ordinary-file
canary then passed. The earlier `9c1a31f` bridge remains historical evidence;
the corrected release contains the directory-mode, secret-scope, compatibility
and tmux handoff changes. The bridge retains all legacy
physical source paths and supports explicit legacy
provisioning through `--legacy-stow` / `-LegacyStow`; native is the new setup
default. Native setup requires chezmoi 2.74.0, an explicit compatible role and
the [reviewed takeover procedure](takeover.md). The thin updater uses an actual
home/source binding, nonempty native state, clean source and native
`--less-interactive --no-tty --error-on-conflict` with fast-forward-only Git.
It does not use a sync parser environment. Bash 3.2 and both Windows shell
profile paths remain in scope; no new Bash/tmux/Claude client floor is declared.
Sherlock's glibc 2.17 needs the official static musl artifact selected by
`77bb03e`; its isolated verified probe passed. Actual per-host installation and
acceptance are recorded separately in status.md.

The corrected candidate explicitly passes `--exclude=dirs` on native file
apply/diff/update. Existing shared parents retain their modes/ACLs; only reviewed
still-absent exact directories may receive native directory-only, nonrecursive
apply. An empty missing list skips that command. Missing future parents require
operator preparation, not an automatic creator or plain-apply fallback. A failed
apply may follow Git or earlier file writes. Review local native umask and private
parent modes separately; all five accepted Unix hosts selected local 077 without
changing global policy.

The immutable supported Stow recovery bridge and first accepted ordinary-native
cutover revision are both `bf9995809ca7564c0728f87bcbefe91c8a3cc5e0`. This is a
deliberate compatibility release: legacy Stow recovery and native takeover are
both tested here. `1a9d30b` is the pre-migration input baseline, not the recovery
release. Later physical legacy retention does not extend the declared supported
Stow release automatically. No legacy source/runtime deletion occurs in Stage 4.
An isolated direct `1a9d30b` to `bf99958` ff-only fixture skipped ten intermediate
commits and retained all 95 physical source referents and 448 synthetic links;
the exact scope and reproducible evidence are in stage-4-evidence.md. It does
not promise a safe unsupported jump across the Stage 6 deletion cutoff.

Lab's 59, Mac's 56, WSL's 55 and both clusters' 54 targets are regular files;
native ownership/state remain. Maintenance was removed at ordinary acceptance;
Lab subsequently completed secret enrollment on exact-green `15068b9` and left
maintenance again. Actual updater checks
passed; lab/Mac/WSL passed fresh SSH and clusters used existing masters.
Application limits and other exceptions remain in status.md. Windows accepted
all 26 regular targets on `15068b9`, including ordinary-token updater/session
skip, fresh SSH and persisted bindings. Maintenance is off; its legacy restow
task stays disabled until Stage 6. Commit, publication and D11 rollout authority
are already granted; exact candidate gates and concrete host prerequisites still
apply. Before any Stage 6 breaking publication, execute the quiescence and
offline-home recovery procedure below: a declared cutoff alone cannot stop an
old updater from fetching a deletion commit.

## Stage 5 boundary

Stage 5 reached main as `dddc718` on 2026-11-04 after exact CI 41832666587 (all
three jobs) and bootstrap e2e 41832666818 (all seven hosts) passed on that
commit. It removes no package path, Stow entrypoint or parser runtime, and
`bf9995809ca7564c0728f87bcbefe91c8a3cc5e0` stays the supported Stow recovery
bridge. It changes the boundary as follows;
[stage-5-ecosystem.md](stage-5-ecosystem.md#stage-5-outcome) has the evidence.

- tmux: the floor is 3.4 (was 2.6). All seven version gates and the version
  parsing are gone, so older tmux is unsupported. On Marlowe only the login
  env's tmux 3.6a meets it; non-interactive shells there (`ssh marlowe-plain`)
  still find `/usr/bin/tmux` 3.2a.
- Payloads are explicit-only for every home, native or legacy (D7). No login,
  profile or schedule installs or refreshes a payload repo; a person runs
  `sync-payloads [ITEM...]` / `sync-skills`, or
  `sh scripts/payload-update.sh --now` (Windows:
  `scripts/payload-update.ps1 -Now`, unelevated). Until Stage 6
  a no-arg or sourced call and the retired `--auto`, `--worker`, `-Auto` and
  `-Worker` are silent no-ops, so rc files read before the pull keep working.
  Old `ITEM.stamp`, `ITEM.failed` and `payload.log` files are ignored and never
  removed automatically.
- `AWESOME_SKILLS_AUTO_UPDATE`: support ended early, in Stage 5, with the
  scheduler. The earlier promise to honor it through 2027-01-31 is withdrawn,
  and the variable is ignored. Name the items on the command instead
  (`sync-payloads kit pymol`); `DOTFILES_PAYLOAD_ITEMS` still sets the default
  items.
- `DOTFILES_PAYLOAD_AUTO_UPDATE`: nothing reads it any more. The `=0` exports
  in the provisioning shells and the tests that check them stay, inert, until
  Stage 6 removes them; they give it no new behavior.
- `DOTFILES_HOST` and the Stow receipt are legacy only. Native-owned homes take
  the role from the `[data]` `host` line of `~/.config/chezmoi/chezmoi.toml`,
  read as text; a malformed one exits 2 asking for `--host`.
- Windows login updates run only the private `~/.local/bin/chezmoi.exe`, after
  reparse, owner and DACL checks on a held handle, never a PATH match. A chezmoi
  found only elsewhere on PATH (winget, scoop) makes the updater skip each login
  with a warning; the doctor's `native-config` row and W1-chezmoi report it.
  The check narrows a directory-swap race; it does not close it.
- The native config template owns `persistentState`; existing homes take the
  key through a reviewed re-init. All six hosts are done (Windows on
  2026-11-04).
- Kept floors: Bash 3.2, PowerShell 7.0 entrypoints with the 5.1 profile,
  Python 3.11, git presence-only, both Claude plugin IDs and the root
  `CLAUDE.md` stub. A claimed PowerShell 7.1 need of W1-chezmoi was false and
  its gates were removed. Two pre-existing PowerShell 7.2 dependencies are
  recorded, not fixed: the PowerShell 7 profile sets `$PSStyle` without a
  guard, and the legacy HW-stow check `Test-SetupStowed` reads `LinkTarget`
  (.NET 6).
- The doctors' submodule check and retired-checkout advice are gone; leftover
  checkouts stay on disk for inspection by hand. The payload `stow-links`
  refusal and its advice stay unchanged until Stage 6 (a proposed Stage 5
  rewording of that advice for native-owned homes was dropped).

## Stage 6 boundary

Stage 6 (legacy retirement) is implemented on the coordinator integration
branch; landing, the final exact-SHA CI and e2e, and every host step (Phase C)
are pending, and their outcomes go to [status.md](status.md). The repository
side retires, in order: the legacy-stow setup and doctor mode, the receipt and
the environment host selector (B1, `4dc9f78`); the Stow installers, ignore
file, link-trust helper and old login updaters (B2, `c5bdca4`); the
configuration parser chain, its environment and wrappers (B3, `240338d`); the
payload transition shim, the payload `stow-links` field and every checkout
fallback (B4, `c97e2e1`); the PowerShell 7.2-only profile statements, now
behind feature guards (B6, `a82b69c`); the legacy package trees and include
bridges, with the source materialized under `home/` (B5, `5dae7da`); and the
auto-mode prose that named retired paths (D-10, `e243a2f`).

- No automatic legacy repair remains, and none is ported into chezmoi. A home
  outside native ownership (no `~/.config/dotfiles/native` binding) is
  unsupported: its login runs no updater and `sync-payloads` refuses it.
- `bf9995809ca7564c0728f87bcbefe91c8a3cc5e0` stays the immutable recovery and
  conversion source. Recover or convert an old-layout home only from it, by
  the [cutoff procedure](#one-time-operator-upgrade-and-cutoff-deliverable),
  never by updating it to current `main`.
- Both PowerShell 7.2 dependencies the Stage 5 boundary recorded are gone: B6
  guards `$PSStyle` and the PSReadLine 2.2 prediction options, and B1 deleted
  the HW-stow check with its `LinkTarget` read. The 7.0 entrypoint and 5.1
  profile floors are unchanged.
- Quiescence before main moves (maintenance on the five remote hosts, Lab
  first, D-16) and exact residue retirement belong to Phase C. The `.gitignore`
  residue lines stay until every host is verified clean (D-8).

### Historical Sherlock delivery residue (manual)

Earlier Sherlock toolkit delivery can leave these entries on an old home. The
installers that retired them automatically are gone, so inspect each one and
remove only an exact owned entry by hand, never automatically and never by a
bulk cleanup. Compare a link's resolved target (its directory plus `readlink`,
normalized), not its raw text. Preserve live or foreign links and regular
files; unlink a skill directory link itself and never recurse through it.

- Dangling home links whose resolved target is this checkout's historical
  `lab-ubuntu`, `wsl-ubuntu` or `sherlock` package path:
  `.claude/rules/sherlock-kit.md`, `.claude/skills/sherlock-kit`,
  `.agents/skills/sherlock-kit` and `.local/bin/shk`.
- The old `common/codex` `shk` and `codex-instructions-sync` launcher links.
- A regular (not linked) `~/.codex/AGENTS.override.md` whose first line is
  exactly the generated marker below. Codex reads an override instead of
  `~/.codex/AGENTS.md`; move any other override aside only after reading it.

  ```text
  <!-- Generated by dotfiles codex-instructions-sync. Edit common/codex/.codex/AGENTS.md or the host's sherlock-kit rules, then rerun stow-all.sh. -->
  ```

- Native Windows: the two exact dangling `common/codex` launcher links, and,
  by ownership inspection only, the older `~/.local/bin/shk.cmd` launcher, the
  `~/.local/share/sherlock-kit` installation and any old Windows rules, skills
  and overrides.
- The `common/sherlock-kit/sherlock-kit/` checkout and its repository
  `.git/modules/common/sherlock-kit/sherlock-kit`: inspect local branches and
  files first and keep the repository until local work is recovered
  ([leftover checkouts](../payloads.md#leftover-checkouts)).

## Resolved user direction

The user explicitly accepts ending automatic repair of historical layouts and
support for obsolete tool/client versions. Old installations may require a
one-time manual upgrade. This replaces the earlier plan's requirement to wait
for every old installation to attest migration before retiring compatibility.
The user subsequently authorized agents to execute the upgrade, tests and exact
retirement on the six current targets. "Manual" here means a controlled operator
procedure rather than automatic historical repair; the agent is the operator for
reachable hosts. See [fleet-rollout.md](fleet-rollout.md).

It does not authorize removing user data, old checkouts, Git module stores,
unintegrated commits or supported operating systems. Linux, macOS and native
Windows remain supported. Nor does it change D6: login automatic dotfiles updates
remain, implemented with a thin native chezmoi adapter.

Use a declared, tested support boundary and a short manual upgrade procedure.
Do not build a legacy detector, migration framework, fleet registry or permanent
dual-manager layer. A release cutoff is a support decision, not a technical block:
an old login hook can still pull a deletion commit and leave its symlinks broken.
Do not promise safe automatic upgrades for an installation outside the boundary.

## Two different layout transitions

1. **Historical layouts already superseded before this migration:** retired
   Sherlock launchers, old kit/PyMOL packages and submodules, generated overrides,
   old Git filter, one-login shim and historical environment-variable aliases.
   Do not port their automatic repair machinery into chezmoi.
2. **The currently supported Stow layout:** the files under `common/` and host
   directories at the integration baseline still back real installed symlinks.
   Keep them through the planned bridge stages. Their final removal follows the
   declared native cutover, not an assumption that nobody still uses them.

The second transition still needs an executable manual procedure and current-path
tests. It does not require an acknowledgement from every offline machine. Before
the declared cutoff, preserve whichever current layout the stage still advertises
as supported. Afterwards, unsupported installations must use the manual procedure.

## Allocation within the six stages

| Stage | Added responsibility | Avoid |
| --- | --- | --- |
| 1 | Inventory compatibility units and concrete tool-floor candidates; define support terms and evidence needed to select floors | Deleting runtime compatibility before native probes or treating "latest" as a version number |
| 2 | Map old-tool branches while converting ordinary configs; simplify only if the chosen floor and its provisioning/support notice ship together, otherwise defer removal to Stage 5 | A second standalone Stow refactor or silently changing legacy outputs before the selected floor is provisioned |
| 3 | Resolve supported Claude/Codex client contracts and native merge policy; decide the loss of `--migrate-portable` explicitly; defer unready client-floor changes to Stage 5 | Removing current owned/retired policy operations just because they mention old keys |
| 4 | Publish supported layout/version boundary, last supported Stow revision and manual bridge/clean-install steps; implement native login adapter | Requiring all-host attestation or claiming cutoff blocks old auto-pull |
| 5 | Simplify diagnostics, old environment adapters and provisioning/version branches in components that remain | Removing current platform protection or changing payload scheduling without its separate decision |
| 6 | Retire old Stow source/entrypoints and historical repair units with their callers/tests/docs; remove the sync parser chain | Porting legacy repair into chezmoi or deleting host-local residue as part of source cleanup |

Most historical Stow repair can disappear with Stow itself in Stage 6. Earlier
cohesive deletions are reasonable only if the stage already withdraws that support
and they reduce work rather than refactor code about to be deleted.

Stage 5 did its row: it simplified diagnostics (native host resolution, named
`native-config` verdicts, the submodule check removed), ended the skills opt-out
adapter, applied the tmux floor and, under its own user decision (D7), removed
payload scheduling for every home. See [Stage 5 boundary](#stage-5-boundary).

## Historical-removal inventory

| Unit | Current source/callers to inspect | Action and retained boundary |
| --- | --- | --- |
| Retired Sherlock/instructions links | `remove_retired_link` in `stow-all.sh`; `Remove-RetiredLink` in `stow-all.ps1` | Remove repair with the legacy installer; manual old-host instructions identify exact owned links. Done in Stage 6 B2 (`c5bdca4`); the identifiers are in [Historical Sherlock delivery residue](#historical-sherlock-delivery-residue-manual) |
| Retired kit/PyMOL package links | Unix retired-package/STOW_PATH loops; Windows `RetiredPackageLinks` / `Remove-RetiredPackageLink` | Remove transitions and fixtures; preserve upstream payload ownership and local edits. Done in Stage 6 B2 with the installers |
| Old Codex Git filter | `filter.codex-portable` cleanup in `stow-all.sh` | Remove source repair; manual checklist covers obsolete local Git config. Done in Stage 6 B2; obsolete local filter config is a Phase C residue item |
| Generated Codex override | Exact-marker `AGENTS.override.md` cleanup in `stow-all.sh` | Remove automatic cleanup; warn that an existing override can still shadow instructions; never delete an arbitrary user override. Done in Stage 6 B2; [config-sync.md](../config-sync.md#codex-override-precedence-and-retirement) keeps the warning |
| One-login shim | `scripts/awesome-skills-update.sh`, hook selectors and test entrypoint copies | Stage 5 made it a pure no-op; delete it with its old callers in Stage 6; do not recreate it for native deployment. Done in Stage 6 B4 (`c97e2e1`) |
| Payload legacy field | `stow-links` payload manifest row and retired-link consumers in payload scripts, `lib/bootstrap/checks.sh`, `doctor.ps1` | Remove historical repair advice; do not confuse it with current readiness checks sharing a similar name. Kept unchanged through Stage 5 (a proposed rewording of its advice for native-owned homes was dropped), so Stage 6 removes it. Done in Stage 6 B4: the field, its refusal and its advice are gone |
| Old skills opt-out | `AWESOME_SKILLS_AUTO_UPDATE` adapter and doctor advice | Done in Stage 5 with the payload scheduler: the hook adapter and its notice (`281e33f`) and the doctor's read and advice (`a8ca3ff`) deleted, and the previous through-2027-01-31 promise withdrawn early. Select items by command arguments (`sync-payloads kit pymol`); `DOTFILES_PAYLOAD_ITEMS` still sets the default items |
| Old checkout diagnostics | Retired path tables in `lib/bootstrap/checks.sh` and `doctor.ps1` | Done in Stage 5 (`d200d3f`): obsolete advice and the whole submodule check removed from both doctors; the no-submodule invariant is now a repository test (`tests/test_chezmoi_source_state.py`) |
| Retired checkout ignores | Specific `.gitignore` / `.stowrc` entries | Cheap `.gitignore` guards may remain for actual local residue; keep Stow exclusions while old package enumeration remains supported. Stage 6 B2 deleted the Stow ignore file; the `.gitignore` guards stay until Phase C verifies every host clean (D-8) |
| Old logger fallback | Fallback definition in `scripts/dotfiles-update.sh` | Delete with old updater when the native adapter replaces it; retain quiet/error-safe shell startup. Done in Stage 6 B2 with the old updaters |
| Portable baseline migration API | `--migrate-portable`, `retain_missing`, portable writeback and dedicated tests | Declare retirement in Stage 3 and remove with the backend in Stage 6; never turn normal apply into source cleanup. Done in Stage 6 B3 (`240338d`); native apply refuses the flag |

When deleting old repair fixtures, preserve fresh/current installation, repeat
application, conflict, current file safety and platform tests until their owning
component is replaced. Relevant suites include `tests/unix-installer.sh`,
`tests/stow-all.sh`, `tests/windows-installer*`, `tests/payload-update.*`,
`tests/update-hooks.*`, `tests/test_config_sync.py`, doctor/bootstrap suites and
their pre-commit selectors. Use symbols/callers, not blind ranges or a grep-based
"legacy" deletion pass.

## Tool-floor candidates and verification

Stage 1 adds a compact table to its inventory: tool, current floor, proposed floor,
public interface/feature evidence, actual tested versions, affected runtime and
CI invocations, provisioning changes, deletion set and implementation stage.
Select explicit minimums with demonstrated benefit. Do not add arbitrary upper
bounds or exact runtime pins merely to say "latest-only".

| Candidate | Investigation and conditions | Stage |
| --- | --- | --- |
| tmux version gates | Current config gates features at 3.0, 3.2, 3.3 and 3.4; 3.4 is a code-derived candidate floor for those branches, not a claim about the latest release. Verify public features, package availability and actual tests before deleting gates. Update `tools.tsv`, tmux config, tests and docs together. | 1 selected; 2 mapped; done in 5, landed together in `dddc718`: floor 3.4 in `tools.tsv` and `hpc-login-env.yml`, all seven gates and the version parsing removed with config and tests (`e6cfba2`), Linux CI's real tmux (`69f8652`, `33508e7`) and the docs; hosts run Lab/WSL 3.4, Mac 3.8, Sherlock 3.7 and Marlowe 3.6a (login envs); Linux CI fails without real tmux 3.4 |
| Old Claude plugin ID | Official direction is pre-2.1.285 `agents-md@builtin`, current `cc-plugin-agents-md@builtin`; newer clients accept either. Stage 3 retains both. Verify a coherent client floor and native ancestor loading before Stage 5 removes either entry. Removing portable data does not delete live-only state. | 3 preserves both; 5 kept both (no verified client decision) |
| Root `CLAUDE.md` stub | Keep the cheap import interoperability stub by default. Any later removal needs explicit convention change and verified ancestor loading from subdirectories; never conflate it with the substantive global Claude instructions. | Separate verified decision if justified |
| Codex CLAUDE fallback | This supports other repositories' instruction files, not demonstrably old Codex versions. Do not delete it as part of a client-floor sweep. | Preserve unless separately justified |
| Bash 3.2 branches | A higher floor is allowed if it materially simplifies surviving code. macOS must provision and actually invoke it; installing Homebrew Bash does not change `/bin/bash`, shebangs or CI commands. Keep offline/check and shell-state guarantees. BSD utilities are a platform concern. | 1 inventoried; 5 kept 3.2 (the Mac's `/bin/bash` is 3.2.57, the macOS CI job runs `/bin/bash`, and day-zero setup-host runs before Homebrew exists) |
| Python and Stow floors | Raise only for concrete remaining features or removable branches. Stow is being retired, so investing in a new Stow minimum may be wasted work. Python remains for tests/tmux stdlib code, not AI merge. | 1 inventoried; 5 kept Python 3.11 (Linux CI runs it) and Stow 2.3.1; Stow retires in 6 |
| PowerShell/Windows tools | Verify a concrete supported floor independently of platform support; preserve actual Windows requirements of surviving code. | 1 inventoried; 5 kept 7.0 entrypoints and the 5.1 profile, removed a false 7.1 claim and its gates (`72c8346`, `934041e`), and recorded the pre-existing 7.2 dependencies (`$PSStyle` in the PowerShell 7 profile, `LinkTarget` in the legacy `Test-SetupStowed`) without fixing them; 6 guarded `$PSStyle` and the PSReadLine 2.2 options (`a82b69c`) and deleted `Test-SetupStowed` with its `LinkTarget` read (B1) |

Do not delete current tmux missing-plugin, SSH/desktop clipboard, battery, private
metric cache, menu quoting, reload or host-scoped recovery behavior with version
gates. TPM's `@tpm_plugins` mechanism may serve present conditional-plugin needs;
the word "legacy" does not prove obsolescence. Stage 5 kept all of them when it
removed the gates. One accepted change: extrakto's OSC 52 choice now reads the
session environment like tmux-yank's, so a locally started server that an SSH
client attaches to and reloads uses OSC 52 instead of the tmux buffer; a server
started over SSH stays on OSC 52.

## Current behavior that is not historical-layout repair

- Codex retired-key removal remains live-policy enforcement: preserve it in the
  native transform unless a separate policy decision changes it.
- Mutable-file ownership, source protection and malformed-input failure remain;
  native parser/serialization/writer behavior replaces the old implementation
  according to the main plan, not according to the superseded standalone task.
- Missing kit helpers on native Windows still have their current silent-no-op
  contract because kit 0.7 does not install there. Removing old 0.6 prose does not
  remove the platform guard. Upstream kit aliases are outside this repo's scope.
- Current skill ownership probes and `sync-skills` need public-interface evidence
  before removal; older comments alone are insufficient. Stage 5 kept both;
  `sync-skills` now runs the validated native source.
- The Windows stamp-publication retry fix in `42b2e71`, integrated by `1a9d30b`,
  was current correctness, not obsolete-client support, while that publication
  code existed. The obligation ended with the code: D7, the separate decision to
  retire the entire scheduler, removed Windows stamp publication with it in
  Stage 5 (`281e33f`), and no payload state is written any more.
- The `DOTFILES_PAYLOAD_AUTO_UPDATE=0` exports of the provisioning shells were
  inert since Stage 5; Stage 6 B4 removed them. Do not give the variable new
  behavior.

The old standalone plan required retaining Stow, TOMLKit, custom receipts and
writer guarantees because it did not change the deployment engine. Those
implementation-retention clauses are superseded by this native migration plan.
Do not use them to block the explicit goal of removing the sync environment.

## One-time operator upgrade and cutoff deliverable

Stage 4 writes short commands/procedures tested in fixtures, using immutable
revisions rather than creating/moving tags merely for the handoff:

1. Name the last supported Stow revision and the first supported native layout
   and tool floors. State precisely what automatic legacy support is withdrawn.
2. Before an old installation fetches/applies the breaking revision, disable both
   dotfiles and payload auto-update hooks for its maintenance session, stop/wait
   for existing repo-owned workers and address its exact Windows scheduled task.
   Only a pre-Stage-5 revision still has a payload auto-update hook and workers;
   from `dddc718` on, payloads run only when a person starts them.
3. Offer a controlled bridge from the last supported revision, or a clean current
   clone plus manual preparation of old HOME destinations. A fresh clone does not
   remove old HOME links or `AGENTS.override.md`.
4. Inspect exact old links, generated vs manual overrides, local Git filter,
   old opt-outs and checkout/module residue. Preserve local commits and custom
   content. D11 authorizes exact host-side migration/retirement, not broad cleanup
   or automatic residue deletion. Keep one host owner and private recovery data.
5. Verify the native layout, tools, application reading and thin login updater
   before restoring automatic updates. Keep a recovery path that preserves new
   edits; never blindly restow over changed regular files.

If an old host skipped the maintenance procedure and auto-pulled a deletion
commit, describe recovery honestly. Do not call the support cutoff a guarantee
against broken old links. Do not require all such hosts to be online before the
current-layout-only code can ship. Sherlock operations still follow site rules
and require their own authorized access/allocation.
Implementing agents carry out this procedure on the user's reachable targets;
manual user action is reserved for specific access/privilege/site blockers.

## Provenance and supersession

The other review session confirmed that its fixes and tmux integration are
complete at `1a9d30b`, and only this compatibility-removal implementation remained.
Its `current-layout-only-assessment-20261102.md` and `next-session-prompt.txt` are
superseded by this document and the six stage plans. No external handoff directory,
archive, transcript or previous conversation is required to execute this plan.

Reported historical checks at that commit are available in the repository's CI:
[candidate CI](https://github.com/FridrichMethod/dotfiles/actions/runs/41404677286),
[bootstrap e2e](https://github.com/FridrichMethod/dotfiles/actions/runs/41404677227),
[main CI](https://github.com/FridrichMethod/dotfiles/actions/runs/41405768176).
These are provenance supplied by the completed task, not fresh validation of any
chezmoi stage. Do not restart the completed review fixes or its standalone prompt.
