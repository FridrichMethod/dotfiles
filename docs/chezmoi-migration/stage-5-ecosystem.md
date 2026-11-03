# Stage 5: Ecosystem simplification implementation plan

> **For agentic workers:** Use subagent-driven-development with separate worktrees
> under [README.md](README.md). Start from the complete Stage 4 integration
> artifact and [start-stage-5.md](start-stage-5.md), never a bare baseline HEAD.

**Goal:** Reduce remaining lifecycle code by adopting native chezmoi/package-manager
behavior and explicit upstream interfaces, without replacing it with another
general orchestration framework.

**Architecture:** Ordinary apply remains configuration-only. Native package data
and narrowly selected externals handle appropriate resources. Remaining commands
are explicit, small and justified by site or upstream requirements.

**Tech stack:** Chezmoi, native package managers, existing upstream installers,
small shell/PowerShell glue only where required, stdlib tests.

**Spec:** [Target architecture](README.md#target-architecture), resolved decisions
in [status.md](status.md), [support boundary](support-boundary.md).
Preserve [fleet execution](fleet-rollout.md) and
[native secret ownership](secrets-and-ssh.md) through this simplification.

## Entry state and gates

This is a handoff, not Stage 5 implementation. Start at `$HOME/dotfiles` on main,
inspect current status and read the committed closure record in [status.md](status.md)
and exact per-host results in [stage-4-evidence.md](stage-4-evidence.md). Preserve
subsequent changes and their applicable exact CI gates before creating a fresh
task worktree under `.worktrees/`. Do not depend on the former Stage 4 coordinator
remaining on disk after its integrated result is validated.

The accepted ordinary-native bridge is `bf99958`; encrypted source `74985d08`
also passed exact three-platform CI and bootstrap e2e before reaching main.
All five Unix ordinary takeovers and subsequent secret enrollments passed. They
accepted eight-file deployment, nonforce convergence, offline consumer and actual
updater checks. Sherlock's kit 0.7.0 source update is accepted using its existing
login runtime; its eight-file enrollment then passed empty diff, consumer,
updater, existing-master access and final persisted-binding checks on `15068b9`.
Its earlier post-repeat metadata guard cause remains unknown; the reviewed
continuation completed only remaining checks without replaying deployment.
Windows completed all 26 regular targets on `15068b9`, two nonforce repeats,
empty diff, both shell smokes, ordinary-token updater/session skip, fresh SSH and
persisted-binding acceptance. Maintenance is off; enrollment remains false and
the old restow task stays disabled for Stage 6. All six Stage 4 host gates passed;
historical partial operations remain separately documented.
Lab's shared Astra/xhigh correction passed, then a formatting-only rewrite
exposed a native modifier conflict. The scoped typed-no-op preservation correction
`15068b9` passed exact CI 41684120644 (all three) and bootstrap e2e 41684121107
(all eight), then reached main. Lab's fresh 67-target review, two nonforce applies,
empty diff, actual updater and fresh WSL-to-Lab SSH passed; all 59 ordinary files
and five excluded auth siblings remained bound. No blanket
deployment approval, recovery choice or mandatory Sherlock job ID remains open.
Do not repeat historical force exceptions or treat a prepared candidate as a
completed host migration. Existing-master access never proves fresh MFA, and
offline consumer checks do not prove credential-server authentication.

Stage 4 adds native-default provisioning, explicit legacy compatibility flags,
per-home native/maintenance guards, thin native login update adapters and isolated
takeover/recovery fixtures. It does not remove the legacy physical packages or
parser chain. The bootstrap e2e path retains an explicitly labeled legacy install,
then tests native provisioning and isolated takeover/recovery; this is not a
migration of that sandbox HOME.

Before lifecycle simplification, require closure and regression evidence for
Stage 4 review findings: existing regular files or foreign links at newly managed
targets must not be overwritten by unattended updates; missing/empty native state
requires inspected recovery; repeat init preserves existing backend/local data;
Windows discovers the provisioned binary and dispatches from the validated bound
source; Unix rejects appended unterminated marker data. Read the final resolution
record rather than assuming a finding is fixed because a patch exists. Preserve
these checks when reducing code; they protect current native behavior.

The required native-platform fixtures, independent review, local checks and exact
candidate hosted CI/e2e passed for the accepted runtime. `bf99958` is the immutable
supported Stow recovery bridge and first accepted ordinary-native release, as
defined in support-boundary.md. Any later runtime or enrolled-source candidate
must pass its applicable gates before activation.
Preparing Stage 5 in isolation does not waive those gates or extend the current
Stage 4 scope. Commit/publication/landing authority for Stage 4 is explicit.
D11 authorizes the six-host operations
after applicable gates, but does not turn preflight into migration. Concrete
access, privilege, site and ownership blockers remain; do not restore a gate
requiring every offline host to attest migration.

D6 (thin automatic dotfiles updates), D9 (declared current-layout cutoff) and D11
(agent-executed six-host migration/retirement) are resolved. D7 (payload scheduling)
is unresolved. The user has approved the private eight-file static-secret scope
for lab, Mac, WSL, Sherlock and Marlowe plus recovery recipient R. Apple Passwords
is selected; local retrieval checks were reported PASS and independent full
retrieval on another device was confirmed. All five host identities now exist
locally, and eight production inputs are encrypted for the exact six recipients. All five host
identities and retrieved R each decrypt all eight; only ciphertext entered source
commit `74985d08`, which passed exact CI 41586461636 and bootstrap e2e 41586462369
before reaching main. Deployment remains a separate host gate. Do not reopen
the approved scope or custody choices. Keep private
names/values out of this document.
SSH configuration remains ordinary configuration; no new private SSH target is
implied. Preserve app-written auth, existing trust and recovery access.

## Exact caller disposition from Stage 4

Paths below are current source paths, not a permission to remove live files.
Reconfirm callers in the final integration diff before editing. "Stage 6" means
retain the file and its supported behavior now; removing a native caller does
not prove that a shared legacy caller disappeared.

| Current caller and implementation | Stage 5 disposition | Required evidence / later owner |
| --- | --- | --- |
| `common/sh/.profile` `_dotfiles_login_updates`, called from `common/zsh/.zshrc`; `win/powershell/Documents/PowerShell/profile.ps1` interactive tail | Retain maintenance-first native/legacy dispatch and validated source binding. Keep `scripts/chezmoi-update.sh` and `.ps1` for native homes under D6. No manual-only dotfiles replacement. | `tests/shell-profile.sh`, `tests/powershell-profile.ps1`, `tests/test_chezmoi_takeover_unix.py` and `test_chezmoi_takeover_windows.py`; non-default source and malformed-marker tests must survive. |
| `scripts/chezmoi-update.sh`, `.ps1`; `home/.chezmoi.toml.tmpl` | Retain bounded noninteractive native update, clean-source and safe-config checks, fast-forward-only behavior, reviewed target-baseline protection and generic nonsecret warnings. Preserve init's local data/backend handling. | `tests/test_chezmoi_takeover_recovery.py`, `test_chezmoi_update_config.py`; no force/stash/rebase, no newly introduced receipts/locks/retry service. Stage 4 already bypasses the old machinery. |
| `lib/chezmoi-guard.sh`, `.ps1`; `lib/config_sync.py` direct backend guard; all four legacy sync wrappers | Retain native binding and persistent maintenance semantics, including explicit LIVE destinations and parent symlink checks. Keep legacy write refusal after partial apply. | `tests/test_chezmoi_guard.py` and takeover suites. Stage 6 removes legacy-only guard users with their writers; native binding/maintenance protection still has callers. |
| `setup-host.sh`, `.ps1`, `lib/bootstrap/steps.sh`, `steps-archives.sh`, `steps-human.sh`, `lib/bootstrap.ps1` | Retain native `S4-chezmoi` / `W1-chezmoi` verified binary installation and `H7-native` / `HW-native` reviewed handoff. Keep `--legacy-stow` / `-LegacyStow` and their `S4-setup-sync` / `W1-setup-sync`, `H7-stow` / `HW-stow` / `HW-auto-stow-task` branches through Stage 6. | setup never applies config or creates the native marker. `tests/test_chezmoi_provision.py`, bootstrap/setup suites and explicit legacy e2e callers remain. |
| `doctor.sh`, `.ps1`, `lib/bootstrap/checks.sh`, `lib/bootstrap.ps1`, `config/bootstrap/tools.tsv` | Native mode already omits Stow/parser checks; do not reimplement that split. Simplify native diagnostics to actual prerequisites/site checks. Keep legacy `venv-sync` / `stow-links` probes in explicit compatibility mode. | Offline/write-free checks and telemetry suppression remain. Remove a shared check only after tracing both mode consumers. |
| `BOOTSTRAP_RETIRED_CHECKOUTS` / `bootstrap_check_submodule` in `lib/bootstrap/checks.sh`; retired-checkout loop in `doctor.ps1` | Stage 5 deletion candidate: remove historical checkout/module cleanup advice under D9, retaining any useful current no-submodule invariant. | Update doctor/bootstrap tests and support notice together. Never delete those local checkouts or module stores as part of diagnosis. |
| `lib/bootstrap/steps-guard.sh`, `steps-common.sh`, `steps-runtimes.sh`, rc-pollution checks in `checks.sh` | Narrow only proven obsolete new-path source-write-through assumptions; keep shared protection needed by legacy symlink homes. Retain no-rc installer flags and offline/check guarantees. | Full removal of Stow-specific source tables/guards is Stage 6 if the old installer still calls them. No snapshot daemon or new generic guard framework. |
| Profile auto calls to `scripts/payload-update.sh` / `.ps1`; `common/sh/.aliases` `sync-payloads` / `sync-skills`; PowerShell functions of the same names | Conditional on D7: remove automatic profile calls if explicit-only delegation is selected; retain small explicit entrypoints with correct native bound-source resolution and upstream-owned installs. | Do not infer this choice from D6 or the Sherlock override. Preserve platform/item selection and meaningful failure/busy/person-required results. |
| `scripts/payload-update.sh` `--auto` / `--worker`, `_DOTFILES_PAYLOAD_CHECKED`, `record`, background spawn; PowerShell `-Worker`, record handling and detached process | Conditional on D7 and supported callers: delete scheduler-only foreground/background split, session markers, age/retry logic, stamp/failure publication and log machinery as a unit when no advertised automatic caller needs them. | `tests/payload-update.sh`, `.ps1`, `tests/test_payload_download.py`; preserve Windows stamp-publication correctness while that code remains. Do not keep its tests after deleting the entire scheduler or create a second scheduler for native homes. |
| `config/payloads.tsv` `days`; `ITEM.stamp`, `ITEM.failed`, `payload.log` readers in payload twins, `bootstrap_check_payloads` and Windows doctor | Delete scheduler data and doctor schedule/failure-record advice with the D7 scheduler removal, not beforehand. Keep URLs, install/update commands, channel `0.7`, platform probes and person-status where the explicit interface still needs them. | Shared old callers that remain supported defer deletion to Stage 6. Do not remove host-local record files automatically. Missing schedules cannot be an error after their contract ends. |
| `AWESOME_SKILLS_AUTO_UPDATE` adapter in Unix payload hook and doctor | Stage 5 coherent deletion candidate under D9: explicitly withdraw the former through-2027-01-31 promise and update selection guidance/tests. | While retained, use `DOTFILES_PAYLOAD_ITEMS`; under explicit-only D7, document command arguments instead. Preserve upstream skills ownership probes and `sync-skills` unless separately justified. |
| `sherlock/sh/.config/sh/.profile` `DOTFILES_PAYLOAD_AUTO_UPDATE=0` | Retain the site override while any automatic scheduler exists. Explicit `sync-payloads` remains available subject to site/allocation rules. | `tests/shell-profile.sh`; no detached login-node worker. If D7 removes all automatic calls, remove only the redundant variable with a documented equivalent no-worker guarantee. |
| `scripts/dotfiles-update.sh`, `.ps1`, `scripts/dotfiles-auto-stow.ps1`, legacy profile fallback | Stage 6 deletion, not Stage 5 refactoring: still serve unmarked supported homes/registered tasks. Their locks, revision receipts, retry logic and elevation handling are already absent from the native path. | `tests/update-hooks.sh`, `.ps1`, `tests/windows-installer*`; quiesce and deregister only the exact owned task under the reviewed operator procedure. |
| `stow-all.sh`, `.ps1`, `.stowrc`, `lib/windows-link-trust.ps1`; retired-link/filter/generated-override repair | Stage 6 deletion with old deployment. Keep current compatibility and refusal checks until its support ends; do not port repair to native apply. | Includes `filter.codex-portable`, exact generated `AGENTS.override.md`, retired Sherlock/kit/PyMOL link repair. Foreign files/links and user overrides remain untouched. |
| `scripts/awesome-skills-update.sh`; `config/payloads.tsv` `stow-links`; readers in both payload hooks and doctors | Stage 6 deletion with the last supported historical caller; earlier removal only with an explicit cohesive withdrawal and proof of no supported dependency. | Do not confuse historical payload links with current Stow readiness or native destination-baseline safety. Cheap ignored-residue entries may remain. |
| `setup-sync.sh`, `.ps1`, `requirements-sync.txt`, `lib/sync-runtime.sh`, `lib/config_sync.py`, `.venv-sync`, `DOTFILES_SYNC_PYTHON` | Stage 6 mandatory retirement after the last supported legacy caller. Stage 5 creates no new parser environment and removes no still-required runtime. | Four exact wrappers: `common/claude/.local/bin/claude-settings-sync`, `common/codex/.local/bin/codex-config-sync`, `common/codex/.local/bin/codex-rules-sync`, `lab-ubuntu/fcitx5/.local/bin/fcitx5-profile-sync`. Retire their runner/CI/hooks/tests together. |
| `home/` literal includes into `common/`, host packages and portable AI policies; two raw asset copies | Retain through Stage 5. Edit the canonical legacy input when a justified ecosystem change changes rendered config; keep parity. | Stage 6 materializes once and removes old physical paths. No independently editable policy copies or hidden source generator. |

## Provisioning step decisions

Keep installation person-triggered and separate from ordinary apply. Reuse
`config/bootstrap/brew/*.Brewfile`, `apt/*.txt`, `winget.json`,
`hpc-login-env.yml`, `tools.tsv`, `installers.tsv` and `git-clones.tsv` as their
existing authorities. Do not add a second package inventory in chezmoi data.

| Current step family | Retain / simplify in Stage 5 |
| --- | --- |
| `P0-preflight`; `H1-xcode-clt`, `H1-homebrew`, `H1-apt-core`, `H1-locale`, `H1-linuxbrew`, `H1-fcitx5`; Windows HUMAN service/auth/GUI steps | Retain justified platform/privilege/person boundaries. Reduce presentation or duplicated probes only with unchanged supported outcomes; no sudo/chsh/auth hidden in apply. |
| `S2-brew-bundle`, `S2-micromamba`, `H2-alloc`, `S2-login-env`, `S2-modules`; `W1-winget`, `W1-psresources` | Keep package-manager delegation, existing-tool probes, Brew conflict/shared-prefix handling and allocation gates. Shared Stow package entries remain while the compatibility path needs them; final dependency removal is Stage 6. |
| `S3-clones`, `S3-bat-theme`, `S3-dirs`; `W1-bat-theme`, `W1-font`, `S6-nerd-font`, `S6-kitty` | Classify each asset before any native external proposal. Bat theme is the bounded first candidate; preserve verification, destination ownership and refresh timing. Leave dirty Git/plugin trees with their current owner unless takeover is explicitly designed and tested. |
| `S4-nvm`, `S5-claude`, `S5-codex` | Retain verified/inspect distinctions, no-rc installation and native package alternatives already selected. Native configuration apply must not invoke installers. |
| `S4-chezmoi`, `W1-chezmoi`; `H7-native`, `HW-native` | Retain explicit SHA256-verified v2.74.0 provisioning and manual init/takeover boundary. Do not replace this with curl-pipe-shell or hidden network work in preview/apply. |
| `H7-chsh`, `H7-auth`, `H7-payloads`, `H7-doctor`; Windows equivalents | Retain necessary person actions; update payload wording only after D7 and diagnostic wording with the reduced doctor. The native handoff never advertises legacy stow as the default. |

Tool-floor changes are conditional deliverables, not presumed upgrades: current
tmux 2.6, Bash 3.2 compatibility and PowerShell 7 entrypoints/5.1 profile support
remain until a coherent tested alternative ships. tmux 3.4 is the code-derived
candidate; preserve all five tmux files and current feature fallbacks. Retain both
Claude plugin IDs and the root `CLAUDE.md` import stub until actual client evidence
supports a deliberate policy change. Python 3.11 remains for stdlib tests/metrics.
Installing newer Bash without changing the actual macOS/CI invocation is not a
floor change. Do not raise Stow's outgoing floor merely to simplify its tests.

## Global constraints and review focus

Preserve the declared current-layout support contract while simplifying the new
path. Older layouts/tools may explicitly become unsupported under the documented
cutoff. Do not change upstream payload repositories or security policy incidentally.
No automatic removal of users' checkouts, environments or local plugin edits.
Remove new-path calls and probes freely within scope, but keep any shared legacy
entrypoint, worker, guard, payload lifecycle or dependency still used by a supported
old home or registered task until their declared support ends (normally Stage 6),
unless absence of callers is proved. Do not restore an all-host-attestation gate.

Review changed ownership of existing clones; network/cache behavior during preview;
HPC allocation and shared-prefix constraints; payload busy/person-required errors;
and retained tests that accidentally keep a retired mechanism alive.

## Task groups

### Provisioning and assets

**Owner:** Provisioning worker. Inspect `setup-host.*`, `lib/bootstrap/`,
`lib/bootstrap.ps1`, `config/bootstrap/` and bootstrap/e2e suites.

- [ ] Classify each active step as native package-manager operation, downloaded
  asset, explicit site/person action, or obsolete machinery. For every retained
  helper, state why a native command or manifest is insufficient.
- [ ] Reuse Brewfiles, apt lists, winget and conda data where they already serve
  the need. Do not copy all manifests into a second chezmoi inventory.
- [ ] Select and verify any still-proposed tool floors before deleting branches.
  Implement confirmed decisions with tmux/Claude config, provisioning,
  minimum probes, tests and docs in one coherent change. A newer Bash must be
  actually invoked on macOS/CI; installing it alone does not replace `/bin/bash`.
  Preserve platforms, current feature fallbacks and cheap interoperability stubs.
- [ ] Propose bounded externals for suitable assets first, such as a verified
  theme file. For each external record destination, current owner/updater, local
  edit handling, whether `.git` is needed, ref/checksum policy and update timing.
- [ ] Treat switching plugin clones to chezmoi-owned Git/archive externals as an
  ownership change. Existing dirty clones need explicit handling. Preserve
  upstream update mechanisms when they are still the chosen owner.
- [ ] Avoid `exact` for shared directories and downloaded installers in normal
  apply hooks. Keep privileged and HPC actions visible and person-triggered.
- [ ] Remove source-write-through guard branches only when the exact caller map
  proves them obsolete; shared legacy protection remains until Stage 6. Retain
  no-rc installer arguments. Do not replace the guard with a snapshot daemon.

### Payload delegation

**Owner:** Payload worker. Inspect `scripts/payload-update.*`, `config/payloads.tsv`,
profile callers and payload tests.

- [ ] Settle D7 with a concrete proposal before changing default lifecycle. The
  preferred endpoint is explicit invocation of upstream installers, not an
  imitation scheduler built from `run_once_` or `run_onchange_`.
- [ ] Preserve platform/channel selection and upstream ownership. Native Windows
  still does not install coding-agent-kit unless its actual upstream support and
  this repository's policy are deliberately changed in separate scope.
- [ ] If manual-only is selected, retire automatic callers and scheduler contracts
  together, then remove foreground/background splitting, session markers, update
  timestamps, persistent failure records and timed retry logic. Shared behavior
  still advertised to supported legacy homes stays until Stage 6.
  Retain honest propagation of busy/failure/person-required outcomes.
- [ ] Where download glue remains, keep bounded downloads, private staging and
  no pipe-to-shell. Do not convert an installed payload tree into a chezmoi archive.
- [ ] Update doctor and profiles so retired state files or missing schedules are
  no longer treated as errors. Do not delete old host data automatically.
- [ ] Follow the exact map: historical payload `stow-links` metadata/repair advice
  normally retires in Stage 6; old checkout diagnostics and
  `AWESOME_SKILLS_AUTO_UPDATE` can end coherently in Stage 5. Document the early
  end of the latter's old 2027-01-31 promise and the
  current selection alternative. Do not confuse current stow readiness or Windows
  stamp-publication correctness with those historical adapters.

### Diagnostics and update cleanup

**Owner:** Diagnostics worker, with coordinator ownership of shared entrypoints.

- [ ] Reduce doctor to project prerequisites and justified site checks. Native
  `chezmoi doctor` diagnoses chezmoi, not all configured applications; document
  the boundary rather than wrapping both into another generic audit framework.
- [ ] Remove new-path Stow/venv/receipt probes and redundant mode/link checks.
  Keep a reduced offline check's explicit guarantee; do not advertise all native
  chezmoi commands as globally write-free.
- [ ] Preserve resolved D6: the thin native login update adapter remains. Retire
  custom locks, applied-revision acknowledgement, complex retry machinery and
  elevated Windows stow worker/task support from the NEW path. Keep shared legacy
  files until remaining callers are gone under the rule above. Task deregistration
  is exact and authorized; it is not implied by editing a profile.
- [ ] Use configured native fast-forward update behavior. Do not hide Git errors
  or automatically discard/rebase/stash user changes to make updates succeed.
- [ ] Test missing/locked secret backend through the login adapter. Keep it
  noninteractive and bounded, with existing secret targets preserved on failure.
  Retire only proven redundant secret copy/export glue; do not add a key daemon
  or OAuth refresh replication. Preserve site-compliant HPC execution.

## Coordinator integration and acceptance

Workers propose exact deletion sets before editing overlapping code. The
coordinator owns root instructions, README, docs, mirrored skills, shared manifests,
hook selectors, test runners and CI integration unless reassigned explicitly.

Begin with independent caller audits, then freeze a path ownership table. A
payload worker may prepare the D7 choice and bounded-download interface while a
provisioning worker audits steps/assets and a diagnostics worker identifies
obsolete advice. Only the coordinator edits shared profiles/manifests/doctor
entrypoints until their decisions are integrated; independent audits do not
authorize concurrent writes to one checkout.

For each removed mechanism, remove or rewrite its tests according to retained
behavior. Keep shell/tmux/AI policy and platform behavior coverage. Measure actual
implementation/test reductions and list remaining custom helpers with a short
reason. A pile of templates containing the old framework is not a successful
simplification.

Run focused native/package/payload/diagnostic fixtures, required full checks and
bootstrap e2e where behavior changed. Tests remain offline apart from explicit
provisioning and opt-in e2e. Do not claim improvements in startup time without
measurements.

Retain `tests/chezmoi.sh` / `.ps1`, `tests/chezmoi-takeover.sh` / `.ps1`, the guard,
provisioning, update-config and takeover/recovery modules, and native shell/profile
checks. Preserve explicit legacy bootstrap/e2e coverage while legacy mode is
supported; record its results separately from native provisioning plus isolated
fixtures. Run `tests/run.sh --ci`, actual native `tests/run.ps1 -CI`, full
pre-commit and independent review on the final aggregate. Existing Mac tmux 3.8
adversarial-menu failures are a recorded baseline, not permission to report that
suite green or silently broaden ecosystem work to an unrelated fix. Record
actual platform passes/skips and any still-open Stage 4 gates.

## Exit and next handoff

The new path has small, explainable lifecycle glue and the documented native
workflows. Record code still required by the declared transition contract. Expand
Stage 6 into an exact caller-removal plan and verify its native-support cutoff,
manual-upgrade and validation deliverables. Missing those deliverables blocks
retirement; an unaccounted-for offline host alone does not. Report removed
capabilities and tested minimum versions explicitly, not as invisible cleanup.
