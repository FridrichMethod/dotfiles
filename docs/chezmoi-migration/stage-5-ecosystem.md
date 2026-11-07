# Stage 5: Ecosystem simplification implementation plan

> **For agentic workers:** Use subagent-driven-development with separate worktrees
> under [README.md](README.md). Start from current main, which is the integration
> artifact, and [start-stage-5.md](start-stage-5.md), never a bare baseline HEAD.
>
> **Status:** landed on main `dddc718` on 2026-11-04. The Windows host finished
> its update and re-init the same day; see [Stage 5 outcome](#stage-5-outcome).
> The plan below is kept as written; each table and checklist records its result.

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

## Stage 5 outcome

Stage 5 ran 2026-11-03..04 and landed by fast-forward: main moved from `b9f9d61`
to `dddc71831944acdf80813532f5935867093dd59b` (85 commits, 69 files,
+3765/-2043), locally and on origin, with no force push. Exact-SHA gates on
`dddc718`: `ci.yml` run 41832666587 passed all three jobs (Linux behavior and
lint, macOS system Bash, Windows native PowerShell, which runs
`tests/run.ps1 -CI`); bootstrap e2e run 41832666818 passed on all seven hosts
(lab-ubuntu, wsl-ubuntu, sherlock, marlowe and other in containers; mac and win
on runners). Locally `tests/run.sh --ci` reported test-suite=PASS and
`pre-commit run --all-files` passed all 39 hooks; `tests/run.ps1 -CI` runs only
in CI (Lab has no pwsh). An earlier e2e run 41805691258 on `69f8652` failed only
on sherlock and marlowe: a new test found zsh on the test PATH but ran it under
`PATH=os.defpath`. `a29a749` runs each shell by its absolute path, and the
review-fix round fixed the same class in `tests/shell-profile.sh`.

Six worker packages were reviewed independently and merged `--no-ff` in order:
PROV (`8353a07`), DIAG (`c8a8d1d`), PAYLOAD (`d9c0009`), WINUPD (`3f24a8d`),
NATIVECFG (`718470d`) and TMUX (`f4a862a`). Coordinator follow-ups, five
documentation branches, an adversarial review (seven dimensions, findings
verified by skeptics: no critical or high, one confirmed medium about Windows
updater-binary readiness) and two review-fix merges (Windows `c326812`, Unix
`57c6390`) followed, each CI-green before merge. The user chose every
recommended option: D7 explicit-only payloads for every home; `tui.status_line`
stays an owned Codex key, with the one-file reconcile runbook in
[takeover.md](takeover.md#reconcile-an-owned-ai-config-key); Marlowe accepts its
failing Node hooks (the site's block-node AppArmor profile) and keeps the inert
Codex config; Windows runs only the exact provisioned `chezmoi.exe` after an
owner/DACL check, with no `~/.local` ACL edits and no hash pin; the native config
template owns `persistentState`, followed by a reviewed re-init on each of the
six hosts (all done); the tmux floor is 3.4, with a Marlowe tmux install
and cache cleanup.

Measured with `git diff --numstat b9f9d61..dddc718`: code 29 files +788/-602
(net +186); tests 22 files +1923/-792 (net +1131); docs 14 files +1031/-636
(net +395); CI/config 4 files +23/-13 (net +10). Against the Stage 5 audit
baseline: root entrypoints 3006 to 3067 lines, `lib/` 6370 to 6646, `scripts/`
1437 to 1238, all `*.sh`/`*.ps1`/`*.py` outside tests 11435 to 11603, `tests/`
28490 to 29621, docs 11807 to 12202, all tracked text 62496 to 64218. The payload
package alone was implementation +184/-377 (net -193) and tests +500/-653 (net
-153). The code growth sits in `lib/`: Windows binary trust
(`lib/chezmoi-guard.ps1` +64), `lib/bootstrap.ps1` +113/-16 (per-commit
numstat: binary trust `9836f27` and `90d10ac` +80/-11, native-config verdicts
`3b89dbf` +39/-11, and a PowerShell 7.1 gate added and reverted in `d55b78b`
and `72c8346` that nets to zero) and native host resolution
(`lib/bootstrap/platform.sh` +82/-6). No startup time was measured; no speedup
is claimed.

Host rollout (2026-11-04). Evidence stays on each host under
`~/.local/state/dotfiles-stage5-rollout/u-<ts>/` and
`~/.local/state/dotfiles-stage5-reinit/`; [status.md](status.md) holds the
per-host record.

| Host | Revision | Targets changed (managed) | `persistentState` re-init | Doctor afterwards |
| --- | --- | --- | --- | --- |
| lab-ubuntu | `b9f9d61` to `dddc718` | 6 (67) | done | 79 ok, 0 warn, exit 0; host from `[data].host` |
| wsl-ubuntu | `4abad00` to `dddc718` | 6 (63) | done | login shell: only the 11 tmux plugin clones missing (pre-existing) |
| mac | `4abad00` to `dddc718` | 6 (64) | done | 11 tmux plugin clones missing; kitty, stylua, schrodinger warnings (pre-existing) |
| sherlock | `7e344f2` to `dddc718` | 9 (62) | done | pre-existing login-env and clone gaps; payloads warn "not installed: skills" (D7 advice) |
| marlowe | `7e344f2` to `dddc718` | 8 (62) | done; ACL `+` kept | interactive: tmux ok (3.6a); node version unknown (AppArmor, accepted); login-env gaps |
| win | `7e344f2` to `57fbc45` | not captured (expected 3; managed count not measured) | done (limited-token task) | 32 ok, 1 warn (payloads "not installed: skills"), exit 0 |

The six targets on every Unix host are `.aliases`, `.profile`, `.zshrc`,
`.tmux.conf`, tmux `modern.conf` and `which-key.conf`. Sherlock also took
`~/.config/sh/.profile`, and both clusters took the Codex config and Claude
settings: their only deltas were the owned `tui.status_line` and
`statusLine.command` from `bcf5c0d`. On all five Unix hosts the updater returned
0; status was empty after re-init (full and plain); the AI configs equal the
rendered output; mode, uid, gid, link and ACL metadata and each host's eight
secrets (inode, mtime, size, mode, uid) were unchanged; maintenance was absent, the
marker unchanged and no stray `chezmoistate.boltdb` existed. No Codex write-back
(MM) was seen; one Codex app-server ran on each HPC host. Marlowe's login env
gained tmux 3.6a and libevent 2.1.12 through Slurm jobs (dry run 554658, install
554712 COMPLETED 0:0; 59 to 61 package records with the original 59
byte-identical; 49 new-file modes repaired; about 931 MiB of caches removed;
evidence `~/.local/state/dotfiles-marlowe-tmux-{dryrun-20261103-01,install-20261104-01}/`).
`/usr/bin/tmux` stays 3.2a there for non-interactive shells such as
`ssh marlowe-plain`. Two rollout-tool defects were fixed before the hosts they
affected ran (re-init must not use `cp -p` on Marlowe's filesystem, which does
not support that permission/ACL preservation, and must not assume `$0` is a file
when sent over SSH); the failed attempts stopped before init and changed nothing.

**Windows finished on 2026-11-04**, through a one-off scheduled task the user
approved instead of typing the steps: the logged-on user's limited token
(Interactive, RunLevel Limited, not elevated) made every change, and the
administrator SSH session only wrote the task script and registered, started and
deleted the task. The old `7e344f2` updater moved win to `57fbc45` (`dddc718`
code plus the Stage 5 records), then the new exact-exe updater ran with no
warning; `reinit-win.ps1` added only `persistentState`, with empty full and
plain status and no stray database; `icacls /inheritance:d` left explicit
entries only on `chezmoi.exe`; the doctor exited 0. The per-file list of changed
targets and the managed count were not measured. Record in
[status.md](status.md#host-rollout-2026-11-04); method, limits and the manual
fallback steps in
[fleet-rollout.md](fleet-rollout.md#windows-rollout-as-run-2026-11-04).

Findings recorded, not fixed in Stage 5: pre-existing person-run provisioning
gaps (tmux plugin clones missing on wsl, mac, sherlock and marlowe; login-env
packages such as git-lfs, git-delta, tldr, chafa, aria2 and uv missing on the
clusters; Marlowe's login env diverges from `hpc-login-env.yml`; Marlowe's
Claude Code stuck at 2.1.150; Mac kitty, stylua and schrodinger). Payload host
leftovers: Sherlock has no skills install (its `~/.cache` to `/scratch` symlink
refusal is unchanged); the Codex skills roots on mac, wsl and marlowe exceed
1990 entries and need a person to prune; old `ITEM.stamp`, `ITEM.failed` and
`payload.log` files remain and are ignored. Windows: `chezmoi.exe` was
re-extracted at 2026-11-03T19:27:56Z (attribution unknown) and its DACL was
inherited, so a propagation from `~/.local` (the Codex sandbox Modify grant)
would have made the updater refuse it, which the doctor shows (the rollout's
`icacls /inheritance:d` left explicit entries only); the
CodexSandboxUsers Modify grants on `~/.local`, `Documents\PowerShell`,
`AppData`, the Startup folder and `%TEMP%` remain a user decision; the
pre-existing PowerShell 7.2 dependencies are in
[support-boundary.md](support-boundary.md#stage-5-boundary).

Lab's private recovery store moved at the end of Stage 5 from
`$HOME/dotfiles/.git/chezmoi-migration-recovery/` to
`~/.local/state/dotfiles-chezmoi-migration-recovery/`, verified by full
readback ([status.md](status.md#unfinished-gates-and-stage-6-readiness)).

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
was unresolved at entry; Stage 5 resolved it as explicit-only. The user has approved the private eight-file static-secret scope
for lab, Mac, WSL, Sherlock and Marlowe plus recovery recipient R. Apple Passwords
is selected; local retrieval checks were reported PASS and independent full
retrieval on another device was confirmed. All five host identities now exist
locally, and eight production inputs are encrypted for the exact six recipients. All five host
identities and retrieved R each decrypt all eight; only ciphertext entered source
commit `74985d08`, which passed exact CI 41586461636 and bootstrap e2e 41586462369
before reaching main. Deployment is accepted on all five Unix hosts; Windows
enrollment is false by design. Do not reopen
the approved scope or custody choices. Keep private
names/values out of this document.
SSH configuration remains ordinary configuration; no new private SSH target is
implied. Preserve app-written auth, existing trust and recovery access.

## Exact caller disposition from Stage 4

Paths below are current source paths, not a permission to remove live files.
Reconfirm callers in the final integration diff before editing. "Stage 6" means
retain the file and its supported behavior now; removing a native caller does
not prove that a shared legacy caller disappeared. The last column records the
landed result at `dddc718`.

| Current caller and implementation | Stage 5 disposition | Required evidence / later owner | Stage 5 result (`dddc718`) |
| --- | --- | --- | --- |
| `common/sh/.profile` `_dotfiles_login_updates`, called from `common/zsh/.zshrc`; `win/powershell/Documents/PowerShell/profile.ps1` interactive tail | Retain maintenance-first native/legacy dispatch and validated source binding. Keep `scripts/chezmoi-update.sh` and `.ps1` for native homes under D6. No manual-only dotfiles replacement. | `tests/shell-profile.sh`, `tests/powershell-profile.ps1`, `tests/test_chezmoi_takeover_unix.py` and `test_chezmoi_takeover_windows.py`; non-default source and malformed-marker tests must survive. | Done, retained. Only the payload call left both profiles (`281e33f`); the update dispatch, maintenance-first order and binding are unchanged. Tests: `test_chezmoi_guard.py` `test_logins_start_no_payload_run_and_keep_the_update_dispatch`, `test_chezmoi_takeover_unix.py` `test_profiles_select_native_source_binding_and_maintenance_survives_new_logins`, and the listed suites. |
| `scripts/chezmoi-update.sh`, `.ps1`; `home/.chezmoi.toml.tmpl` | Retain bounded noninteractive native update, clean-source and safe-config checks, fast-forward-only behavior, reviewed target-baseline protection and generic nonsecret warnings. Preserve init's local data/backend handling. | `tests/test_chezmoi_takeover_recovery.py`, `test_chezmoi_update_config.py`; no force/stash/rebase, no newly introduced receipts/locks/retry service. Stage 4 already bypasses the old machinery. | Done, retained and tightened. The template owns `persistentState` = `<destDir>/.local/state/chezmoi/chezmoi.boltdb` in its case-insensitive dedupe list (`69a743b`); both updaters still pass every explicit flag (flags win), and `scripts/chezmoi-update.sh` is unchanged. The Windows updater runs only `<destination>\.local\bin\chezmoi.exe` after reparse, owner and DACL checks on a held `FileShare.Read` handle, with no PATH fallback (`6e2f6df`, `02ffadb`, `7cae647`). Tests: `test_chezmoi_update_config.py` `test_state_aliases_collapse_to_the_owned_key`, `test_template_derives_state_from_unix_and_windows_destinations`, `test_plain_native_command_shares_the_bound_state_database`; the updater-binary cases in `test_chezmoi_takeover_windows.py`, including `test_held_binary_handle_blocks_renaming_its_parent_directories` (windows-2025, elevated: NTFS refused renaming `.local\bin` and `.local` while the handle was held and allowed it after release). The double junction-swap window is narrowed, not closed. |
| `lib/chezmoi-guard.sh`, `.ps1`; `lib/config_sync.py` direct backend guard; all four legacy sync wrappers | Retain native binding and persistent maintenance semantics, including explicit LIVE destinations and parent symlink checks. Keep legacy write refusal after partial apply. | `tests/test_chezmoi_guard.py` and takeover suites. Stage 6 removes legacy-only guard users with their writers; native binding/maintenance protection still has callers. | Retained. `lib/chezmoi-guard.ps1` gained the updater-binary trust helpers (`Test-DotfilesNativeChezmoiPath`, `Test-DotfilesTrustedFileSecurity`, `Open-DotfilesNativeChezmoi`); the raw DACL check refuses a null DACL and any allow or deny entry that is not a common ACE. `lib/chezmoi-guard.sh`, `lib/config_sync.py` and the wrappers are unchanged; the Stage 6 part stays. |
| `setup-host.sh`, `.ps1`, `lib/bootstrap/steps.sh`, `steps-archives.sh`, `steps-human.sh`, `lib/bootstrap.ps1` | Retain native `S4-chezmoi` / `W1-chezmoi` verified binary installation and `H7-native` / `HW-native` reviewed handoff. Keep `--legacy-stow` / `-LegacyStow` and their `S4-setup-sync` / `W1-setup-sync`, `H7-stow` / `HW-stow` / `HW-auto-stow-task` branches through Stage 6. | setup never applies config or creates the native marker. `tests/test_chezmoi_provision.py`, bootstrap/setup suites and explicit legacy e2e callers remain. | Done, retained with fixes (see the provisioning table): native H2-alloc (`745658c`), mode flag on every rerun note (`ca34d14`, `1f464b0`), W1-chezmoi single-handle private install (`9836f27`) and updater-aware readiness (`90d10ac`). `test_bootstrap_manifest.py` `test_step_lists` checks `STEPS_REGISTRY` and both `setup-host.ps1` lists against the contract ids (`f615ff4`). Legacy branches stay for Stage 6. |
| `doctor.sh`, `.ps1`, `lib/bootstrap/checks.sh`, `lib/bootstrap.ps1`, `config/bootstrap/tools.tsv` | Native mode already omits Stow/parser checks; do not reimplement that split. Simplify native diagnostics to actual prerequisites/site checks. Keep legacy `venv-sync` / `stow-links` probes in explicit compatibility mode. | Offline/write-free checks and telemetry suppression remain. Remove a shared check only after tracing both mode consumers. | Done. Native-owned homes take the host from the `[data]` `host` line of `~/.config/chezmoi/chezmoi.toml`, read as text (malformed: exit 2 asking for `--host`); `DOTFILES_HOST` and the Stow receipt are legacy only (`4b46737`). `native-config` is ok, warn (bound to another checkout, or a stray `~/.config/chezmoi/chezmoistate.boltdb`, never removed) or human (`3b89dbf`); on Windows also human when the updater would refuse the exe (`90d10ac`). Legacy probes stay mode-gated. Tests: `tests/doctor.sh`, `tests/bootstrap.ps1`, `test_chezmoi_provision.py` (`test_native_role_selects_host_without_receipt_or_environment` and neighbors). |
| `BOOTSTRAP_RETIRED_CHECKOUTS` / `bootstrap_check_submodule` in `lib/bootstrap/checks.sh`; retired-checkout loop in `doctor.ps1` | Stage 5 deletion candidate: remove historical checkout/module cleanup advice under D9, retaining any useful current no-submodule invariant. | Update doctor/bootstrap tests and support notice together. Never delete those local checkouts or module stores as part of diagnosis. | Deleted (`d200d3f`): the whole check, both retired-checkout tables and `submodule` in every reserved-id list. The invariant is `test_chezmoi_source_state.py` `test_repository_tracks_no_submodules` (`3b54132`; now `test_repository_tracks_only_regular_files`: no `.gitmodules`, no 160000 gitlink). Leftover checkouts stay on disk for inspection by hand ([payloads.md](../payloads.md#leftover-checkouts)). |
| `lib/bootstrap/steps-guard.sh`, `steps-common.sh`, `steps-runtimes.sh`, rc-pollution checks in `checks.sh` | Narrow only proven obsolete new-path source-write-through assumptions; keep shared protection needed by legacy symlink homes. Retain no-rc installer flags and offline/check guarantees. | Full removal of Stow-specific source tables/guards is Stage 6 if the old installer still calls them. No snapshot daemon or new generic guard framework. | Retained unchanged as cheap tripwires: on a native home they still catch an installer that writes into the checkout. `steps-common.sh` and `steps-runtimes.sh` changed only printed text (the mode flag, and a native reason in P0-preflight's dirty-checkout warning). No-rc flags unchanged. |
| Profile auto calls to `scripts/payload-update.sh` / `.ps1`; `common/sh/.aliases` `sync-payloads` / `sync-skills`; PowerShell functions of the same names | Conditional on D7: remove automatic profile calls if explicit-only delegation is selected; retain small explicit entrypoints with correct native bound-source resolution and upstream-owned installs. | Do not infer this choice from D6 or the Sherlock override. Preserve platform/item selection and meaningful failure/busy/person-required results. | Done under D7, explicit-only for every home: no profile calls the hook (`281e33f`). `sync-payloads` / `sync-skills` run the validated native source (`DOTFILES_DIR` only on unmarked homes) and refuse an invalid binding (`047ed39`). Item selection kept; exit 75 is busy, no failure; person-required 3 and other failures exit 1 with a retry line. Tests: `test_chezmoi_guard.py` `test_sync_payload_commands_run_only_the_validated_native_source`, `tests/shell-profile.sh`, `tests/powershell-profile.ps1`. |
| `scripts/payload-update.sh` `--auto` / `--worker`, `_DOTFILES_PAYLOAD_CHECKED`, `record`, background spawn; PowerShell `-Worker`, record handling and detached process | Conditional on D7 and supported callers: delete scheduler-only foreground/background split, session markers, age/retry logic, stamp/failure publication and log machinery as a unit when no advertised automatic caller needs them. | `tests/payload-update.sh`, `.ps1`, `tests/test_payload_download.py`; preserve Windows stamp-publication correctness while that code remains. Do not keep its tests after deleting the entire scheduler or create a second scheduler for native homes. | Deleted as one unit (`281e33f`), Windows stamp publication and its tests included. Until Stage 6 a no-arg or sourced call and `--auto` / `--worker` / `-Auto` / `-Worker` are silent no-ops that leak no shell option. `scripts/payload-update.sh` 343 to 244 lines, `.ps1` 333 to 235. Tests: `tests/payload-update.sh` (transition no-ops in bash, zsh and sh), `.ps1`, `test_payload_download.py`. |
| `config/payloads.tsv` `days`; `ITEM.stamp`, `ITEM.failed`, `payload.log` readers in payload twins, `bootstrap_check_payloads` and Windows doctor | Delete scheduler data and doctor schedule/failure-record advice with the D7 scheduler removal, not beforehand. Keep URLs, install/update commands, channel `0.7`, platform probes and person-status where the explicit interface still needs them. | Shared old callers that remain supported defer deletion to Stage 6. Do not remove host-local record files automatically. Missing schedules cannot be an error after their contract ends. | Deleted: the known-item check moved off `days` first (`c4b4349`), then `days` rows and every record reader and writer (`281e33f`, `a8ca3ff`). The doctor advises `sync-payloads ITEM`, naming the bound source's hook on native homes (`09fb823`). URLs, commands, channel `0.7`, probes and person-status stay. Host record files are ignored and never removed. |
| `AWESOME_SKILLS_AUTO_UPDATE` adapter in Unix payload hook and doctor | Stage 5 coherent deletion candidate under D9: explicitly withdraw the former through-2027-01-31 promise and update selection guidance/tests. | While retained, use `DOTFILES_PAYLOAD_ITEMS`; under explicit-only D7, document command arguments instead. Preserve upstream skills ownership probes and `sync-skills` unless separately justified. | Deleted with the scheduler: the hook half in `281e33f`, the doctor half in `a8ca3ff`; the through-2027-01-31 promise is withdrawn early. Name items on the command (`sync-payloads kit pymol`); `DOTFILES_PAYLOAD_ITEMS` still sets the default items. `tests/doctor.sh` case `payloads-awesome-ignored` pins that the variable is ignored. `sync-skills` and the skills probes stay. |
| `sherlock/sh/.config/sh/.profile` `DOTFILES_PAYLOAD_AUTO_UPDATE=0` | Retain the site override while any automatic scheduler exists. Explicit `sync-payloads` remains available subject to site/allocation rules. | `tests/shell-profile.sh`; no detached login-node worker. If D7 removes all automatic calls, remove only the redundant variable with a documented equivalent no-worker guarantee. | Removed (`281e33f`); only a comment remains. Correction to the evidence column: the no-worker guarantee is pinned by `tests/payload-update.sh` (`--now` never detaches) and `test_chezmoi_guard.py` `test_logins_start_no_payload_run_and_keep_the_update_dispatch` (Sherlock overlay on and off), not by `tests/shell-profile.sh`. |
| `scripts/dotfiles-update.sh`, `.ps1`, `scripts/dotfiles-auto-stow.ps1`, legacy profile fallback | Stage 6 deletion, not Stage 5 refactoring: still serve unmarked supported homes/registered tasks. Their locks, revision receipts, retry logic and elevation handling are already absent from the native path. | `tests/update-hooks.sh`, `.ps1`, `tests/windows-installer*`; quiesce and deregister only the exact owned task under the reviewed operator procedure. | Stage 6; unchanged. The Windows restow task stays disabled. |
| `stow-all.sh`, `.ps1`, `.stowrc`, `lib/windows-link-trust.ps1`; retired-link/filter/generated-override repair | Stage 6 deletion with old deployment. Keep current compatibility and refusal checks until its support ends; do not port repair to native apply. | Includes `filter.codex-portable`, exact generated `AGENTS.override.md`, retired Sherlock/kit/PyMOL link repair. Foreign files/links and user overrides remain untouched. | Stage 6; unchanged. |
| `scripts/awesome-skills-update.sh`; `config/payloads.tsv` `stow-links`; readers in both payload hooks and doctors | Stage 6 deletion with the last supported historical caller; earlier removal only with an explicit cohesive withdrawal and proof of no supported dependency. | Do not confuse historical payload links with current Stow readiness or native destination-baseline safety. Cheap ignored-residue entries may remain. | Stage 6. The shim is now a pure no-op (`:`) until then (`281e33f`). The `stow-links` refusal and its advice in both hooks and doctors stay unchanged (a proposed Stage 5 rewording of that advice for native-owned homes was dropped). |
| `setup-sync.sh`, `.ps1`, `requirements-sync.txt`, `lib/sync-runtime.sh`, `lib/config_sync.py`, `.venv-sync`, `DOTFILES_SYNC_PYTHON` | Stage 6 mandatory retirement after the last supported legacy caller. Stage 5 creates no new parser environment and removes no still-required runtime. | Four exact wrappers: `common/claude/.local/bin/claude-settings-sync`, `common/codex/.local/bin/codex-config-sync`, `common/codex/.local/bin/codex-rules-sync`, `lab-ubuntu/fcitx5/.local/bin/fcitx5-profile-sync`. Retire their runner/CI/hooks/tests together. | Stage 6; unchanged. Stage 5 created no environment; legacy suites reused the existing `.venv-sync` read-only through `DOTFILES_SYNC_PYTHON`. |
| `home/` literal includes into `common/`, host packages and portable AI policies; two raw asset copies | Retain through Stage 5. Edit the canonical legacy input when a justified ecosystem change changes rendered config; keep parity. | Stage 6 materializes once and removes old physical paths. No independently editable policy copies or hidden source generator. | Retained. Stage 5 edited only canonical inputs (`common/sh/.aliases`, `.profile`, `common/zsh/.zshrc`, three tmux files, the Sherlock profile, the PowerShell 7 profile) and `home/.chezmoi.toml.tmpl`; no bridge, package path or role total changed ([inventory.md](inventory.md)). |

## Provisioning step decisions

Keep installation person-triggered and separate from ordinary apply. Reuse
`config/bootstrap/brew/*.Brewfile`, `apt/*.txt`, `winget.json`,
`hpc-login-env.yml`, `tools.tsv`, `installers.tsv` and `git-clones.tsv` as their
existing authorities. Do not add a second package inventory in chezmoi data.

| Current step family | Retain / simplify in Stage 5 | Stage 5 result (`dddc718`) |
| --- | --- | --- |
| `P0-preflight`; `H1-xcode-clt`, `H1-homebrew`, `H1-apt-core`, `H1-locale`, `H1-linuxbrew`, `H1-fcitx5`; Windows HUMAN service/auth/GUI steps | Retain justified platform/privilege/person boundaries. Reduce presentation or duplicated probes only with unchanged supported outcomes; no sudo/chsh/auth hidden in apply. | Retained; no probe removed. Native HUMAN text names no Stow (H7-auth, X-recovery, the HW blocks); only P0-preflight and HW-wsl branch on the mode (`ca34d14`). |
| `S2-brew-bundle`, `S2-micromamba`, `H2-alloc`, `S2-login-env`, `S2-modules`; `W1-winget`, `W1-psresources` | Keep package-manager delegation, existing-tool probes, Brew conflict/shared-prefix handling and allocation gates. Shared Stow package entries remain while the compatibility path needs them; final dependency removal is Stage 6. | Retained. Native H2-alloc is satisfied by an existing login env, so only S2-login-env needs an allocation (`745658c`); W1-winget's rerun note keeps `-LegacyStow` (`1f464b0`). The Stow-only manifest entries stay for Stage 6. |
| `S3-clones`, `S3-bat-theme`, `S3-dirs`; `W1-bat-theme`, `W1-font`, `S6-nerd-font`, `S6-kitty` | Classify each asset before any native external proposal. Bat theme is the bounded first candidate; preserve verification, destination ownership and refresh timing. Leave dirty Git/plugin trees with their current owner unless takeover is explicitly designed and tested. | Classified; no chezmoi external is suitable, so every asset step stays in setup-host. Clones need `.git` for their upstream updaters, the archives need post-install commands, and a bat-theme external would conflict with existing theme modes under the private native umask, download unattended (no timeout) during the login update and still need `bat cache --build`. `test_chezmoi_source_state.py` `test_source_declares_no_externals` (`fc8ea85`) guards the source. S6-nerd-font counts a font in user, system or Homebrew dirs, the doctor's rule (`24a7905`). Bat theme behavior is unchanged: Unix replaces a theme that differs from the pin, Windows stops on it (recorded difference). |
| `S4-nvm`, `S5-claude`, `S5-codex` | Retain verified/inspect distinctions, no-rc installation and native package alternatives already selected. Native configuration apply must not invoke installers. | Retained; S4-nvm's rerun note keeps the mode flag (`1f464b0`). |
| `S4-chezmoi`, `W1-chezmoi`; `H7-native`, `HW-native` | Retain explicit SHA256-verified v2.74.0 provisioning and manual init/takeover boundary. Do not replace this with curl-pipe-shell or hidden network work in preview/apply. | Retained. W1-chezmoi hashes and extracts through one handle and writes `chezmoi.exe` with an explicit protected DACL (user, SYSTEM, Administrators) instead of one inherited from `%TEMP%` (`9836f27`); it is todo while the login updater would refuse `~/.local/bin/chezmoi.exe`, including when chezmoi is found only on PATH (`90d10ac`). A claimed PowerShell 7.1 requirement was false and was removed (`72c8346`, `934041e`). |
| `H7-chsh`, `H7-auth`, `H7-payloads`, `H7-doctor`; Windows equivalents | Retain necessary person actions; update payload wording only after D7 and diagnostic wording with the reduced doctor. The native handoff never advertises legacy stow as the default. | Done. H7-payloads says only a person installs payloads and prints the hook's `--now` line, the bound source's hook on native homes (`a8ca3ff`, `09fb823`); H7-auth names no Stow; H7-doctor keeps the mode flag. `setup-host.ps1` still prints no payload block. |

Tool-floor changes are conditional deliverables, not presumed upgrades: at entry,
tmux 2.6, Bash 3.2 compatibility and PowerShell 7 entrypoints/5.1 profile support
remained until a coherent tested alternative shipped. tmux 3.4 was the code-derived
candidate; preserve all five tmux files and current feature fallbacks. Retain both
Claude plugin IDs and the root `CLAUDE.md` import stub until actual client evidence
supports a deliberate policy change. Python 3.11 remains for stdlib tests/metrics.
Installing newer Bash without changing the actual macOS/CI invocation is not a
floor change. Do not raise Stow's outgoing floor merely to simplify its tests.

Stage 5 result: the tmux floor is 3.4 (`e6cfba2`), changed in `tools.tsv` and
`hpc-login-env.yml` together; all seven version gates and the version parsing
are gone, all five tmux files and the plugin, clipboard, battery, metric-cache,
menu, reload and hostname-recovery behavior remain. Extrakto's OSC 52 choice now
reads the session environment like tmux-yank's; tmux refreshes only
`SSH_CONNECTION` of the gate's variables, so a server started over SSH stays on
OSC 52, and a locally started server that an SSH client attaches to and reloads
now uses OSC 52 instead of the tmux buffer. Linux CI installs apt tmux 3.4 and sets
`DOTFILES_TEST_REQUIRE_TMUX=1`, so a missing or older tmux fails its cases
(`69f8652`, `33508e7`). Bash 3.2, PowerShell 7.0 entrypoints with the 5.1 profile,
Python 3.11, git presence-only, both Claude plugin IDs and the `CLAUDE.md` stub
are unchanged.

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

- [x] Classify each active step as native package-manager operation, downloaded
  asset, explicit site/person action, or obsolete machinery. For every retained
  helper, state why a native command or manifest is insufficient.
  Done: every Unix registry step and Windows step was classified; the
  provisioning table above records each family's reason and result. Only the
  legacy-only Stow/sync steps are obsolete, and they stay for Stage 6.
- [x] Reuse Brewfiles, apt lists, winget and conda data where they already serve
  the need. Do not copy all manifests into a second chezmoi inventory.
  Done: no second inventory; of the provisioning manifests only `tools.tsv` and
  `hpc-login-env.yml` changed, for the tmux floor.
- [x] Select and verify any still-proposed tool floors before deleting branches.
  Implement confirmed decisions with tmux/Claude config, provisioning,
  minimum probes, tests and docs in one coherent change. A newer Bash must be
  actually invoked on macOS/CI; installing it alone does not replace `/bin/bash`.
  Preserve platforms, current feature fallbacks and cheap interoperability stubs.
  Done: tmux 3.4 by user decision, landed together in `dddc718` (config,
  provisioning and tests `e6cfba2`; Linux CI `69f8652`, `33508e7`; docs), with
  Marlowe's login env given tmux 3.6a before landing; hosts run Lab/WSL 3.4,
  Mac 3.8, Sherlock 3.7 and Marlowe 3.6a. Bash 3.2 (the Mac's `/bin/bash` is
  3.2.57, and the macOS CI job runs `/bin/bash`), PowerShell 7.0 with the 5.1
  profile, Python 3.11 and both Claude plugin IDs are kept.
- [x] Propose bounded externals for suitable assets first, such as a verified
  theme file. For each external record destination, current owner/updater, local
  edit handling, whether `.git` is needed, ref/checksum policy and update timing.
  Done: evaluated, none adopted (reasons in the provisioning table); a guard
  test now fails on any `.chezmoiexternal*` in the source.
- [x] Treat switching plugin clones to chezmoi-owned Git/archive externals as an
  ownership change. Existing dirty clones need explicit handling. Preserve
  upstream update mechanisms when they are still the chosen owner.
  Done: no ownership change; S3-clones keeps upstream owners and never touches
  an existing clone.
- [x] Avoid `exact` for shared directories and downloaded installers in normal
  apply hooks. Keep privileged and HPC actions visible and person-triggered.
  Done: no `exact_`, apply script or external was added.
- [x] Remove source-write-through guard branches only when the exact caller map
  proves them obsolete; shared legacy protection remains until Stage 6. Retain
  no-rc installer arguments. Do not replace the guard with a snapshot daemon.
  Done: none removed; `steps-guard.sh` and the rc-pollution check stay as cheap
  tripwires, and the no-rc flags are unchanged.

### Payload delegation

**Owner:** Payload worker. Inspect `scripts/payload-update.*`, `config/payloads.tsv`,
profile callers and payload tests.

- [x] Settle D7 with a concrete proposal before changing default lifecycle. The
  preferred endpoint is explicit invocation of upstream installers, not an
  imitation scheduler built from `run_once_` or `run_onchange_`.
  Done: the user chose explicit-only for every home (native and legacy); no
  `run_once_` or `run_onchange_` script exists.
- [x] Preserve platform/channel selection and upstream ownership. Native Windows
  still does not install coding-agent-kit unless its actual upstream support and
  this repository's policy are deliberately changed in separate scope.
  Done: channel `0.7`, the probes and the install/update rows are unchanged; the
  kit still has no `windows-install` row.
- [x] If manual-only is selected, retire automatic callers and scheduler contracts
  together, then remove foreground/background splitting, session markers, update
  timestamps, persistent failure records and timed retry logic. Shared behavior
  still advertised to supported legacy homes stays until Stage 6.
  Retain honest propagation of busy/failure/person-required outcomes.
  Done as one unit in the payload merge (`d9c0009`): the hooks in `281e33f`,
  the doctors' record readers in `a8ca3ff`, legacy homes included (D7 covers
  them); the transition no-ops stay until Stage 6. The payload package measured
  implementation net -193 and tests net -153 lines; exit 75, person-required 3
  and failure results remain.
- [x] Where download glue remains, keep bounded downloads, private staging and
  no pipe-to-shell. Do not convert an installed payload tree into a chezmoi archive.
  Done: `DOTFILES_PAYLOAD_TIMEOUT` bounds each download, each is staged alone in a
  fresh private directory and never piped into a shell, and one failed download
  ends the run's downloads (`test_payload_download.py`, `tests/payload-update.sh`).
- [x] Update doctor and profiles so retired state files or missing schedules are
  no longer treated as errors. Do not delete old host data automatically.
  Done: nothing reads the records any more; the doctor advises
  `sync-payloads ITEM`; old record files stay on hosts, ignored.
- [x] Follow the exact map: historical payload `stow-links` metadata/repair advice
  normally retires in Stage 6; old checkout diagnostics and
  `AWESOME_SKILLS_AUTO_UPDATE` can end coherently in Stage 5. Document the early
  end of the latter's old 2027-01-31 promise and the
  current selection alternative. Do not confuse current stow readiness or Windows
  stamp-publication correctness with those historical adapters.
  Done: `stow-links` stays for Stage 6; the checkout diagnostics (`d200d3f`) and
  the adapter (`281e33f`, `a8ca3ff`) ended in Stage 5, with the promise withdrawn in
  [support-boundary.md](support-boundary.md#stage-5-boundary). The Windows
  stamp-publication obligation ended with its code.

### Diagnostics and update cleanup

**Owner:** Diagnostics worker, with coordinator ownership of shared entrypoints.

- [x] Reduce doctor to project prerequisites and justified site checks. Native
  `chezmoi doctor` diagnoses chezmoi, not all configured applications; document
  the boundary rather than wrapping both into another generic audit framework.
  Done: the submodule check and the payload schedule/record advice are gone, and
  `native-config` names its cause; no audit framework was added. The rc-pollution
  check stays as a tripwire.
- [x] Remove new-path Stow/venv/receipt probes and redundant mode/link checks.
  Keep a reduced offline check's explicit guarantee; do not advertise all native
  chezmoi commands as globally write-free.
  Done: native mode already skipped the Stow/venv probes; native-owned homes no
  longer read the receipt or `DOTFILES_HOST` (`4b46737`). The `[data].host` read
  is a text read without chezmoi or git, so the offline write-free guarantee holds.
- [x] Preserve resolved D6: the thin native login update adapter remains. Retire
  custom locks, applied-revision acknowledgement, complex retry machinery and
  elevated Windows stow worker/task support from the NEW path. Keep shared legacy
  files until remaining callers are gone under the rule above. Task deregistration
  is exact and authorized; it is not implied by editing a profile.
  Done: the adapter remains, and the Windows one runs only the private
  `~/.local/bin/chezmoi.exe`; legacy updaters are untouched and the disabled
  restow task stays for Stage 6.
- [x] Use configured native fast-forward update behavior. Do not hide Git errors
  or automatically discard/rebase/stash user changes to make updates succeed.
  Done: the owned update contract and the updaters' safe-config check are
  unchanged.
- [x] Test missing/locked secret backend through the login adapter. Keep it
  noninteractive and bounded, with existing secret targets preserved on failure.
  Retire only proven redundant secret copy/export glue; do not add a key daemon
  or OAuth refresh replication. Preserve site-compliant HPC execution.
  Done before Stage 5 and kept: `test_chezmoi_takeover_unix.py`
  `test_missing_backend_and_nonsecret_failure_are_bounded` and
  `test_missing_age_identity_and_malformed_ciphertext_preserve_secret_without_output`,
  `test_chezmoi_takeover_windows.py`
  `test_missing_backend_and_conflict_are_nonsecret_warnings`. Stage 5 removed no
  secret glue; gitleaks now also covers the encoded native secrets source path,
  allowing only the eight approved age ciphertexts (`4f71bd2`).

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

Stage 5 result: the path freeze and integration order held, and workers listed
their doc edits for the coordinator instead of editing shared files. Remaining
custom lifecycle glue, each with its reason:

- `scripts/chezmoi-update.sh` / `.ps1`: the D6 adapter (bound source, clean
  tree, safe-config check, bounded noninteractive native update); Windows adds
  the exact-exe trust check because a sandbox-writable `~/.local` could
  otherwise substitute the binary.
- `lib/chezmoi-guard.sh` / `.ps1`: binding and maintenance for native and legacy
  writers, plus the Windows binary trust helpers.
- `scripts/payload-update.sh` / `.ps1`: the explicit foreground runner for the
  three upstream installers (bound source, bounded private download, maintenance
  refusal); its transition no-ops and `stow-links` refusal end in Stage 6.
- `home/.chezmoi.toml.tmpl`: owns the update contract, `persistentState` and
  `[data].host` while preserving local settings.
- `doctor.*`, `setup-host.*`, `lib/bootstrap*`: offline prerequisite checks and
  person-triggered installs, with the legacy mode until Stage 6.
- `lib/bootstrap/steps-guard.sh` and the rc-pollution check: cheap tripwires.

Checks on the final aggregate: `tests/run.sh --ci` PASS and all 39 pre-commit
hooks locally; native `tests/run.ps1 -CI` in the Windows job of CI run
41832666587; the review's one confirmed medium was fixed before landing. macOS
CI runs no real tmux, and this record has no Stage 5 rerun of the Mac tmux 3.8
baseline. No Stage 4 host gate is open, and the Stage 5 Windows rollout finished
on 2026-11-04 ([outcome](#stage-5-outcome)).

## Exit and next handoff

The new path has small, explainable lifecycle glue and the documented native
workflows. Record code still required by the declared transition contract. Expand
Stage 6 into an exact caller-removal plan and verify its native-support cutoff,
manual-upgrade and validation deliverables. Missing those deliverables blocks
retirement; an unaccounted-for offline host alone does not. Report removed
capabilities and tested minimum versions explicitly, not as invisible cleanup.

Stage 5 exit record. Code kept only for the transition contract: the Stage 6
rows of the caller table, the payload transition no-ops, the no-op
`scripts/awesome-skills-update.sh`, the payload `stow-links` refusal and the
inert `DOTFILES_PAYLOAD_AUTO_UPDATE=0` provisioning exports. Removed
capabilities: automatic payload installs and refreshes at login on every home;
`AWESOME_SKILLS_AUTO_UPDATE`; the `DOTFILES_PAYLOAD_AUTO_UPDATE` knob and
Sherlock's override; payload stamps, failure records, log and timed retry; the
doctor's submodule and retired-checkout advice; `DOTFILES_HOST` and the Stow
receipt on native-owned homes; any PATH `chezmoi` for the Windows login
updater; tmux below 3.4. Tested minimums: tmux 3.4 (Linux CI's apt tmux; Lab
and WSL hosts also have 3.4), Bash 3.2 (macOS CI `/bin/bash`), Python 3.11
(Linux CI). PowerShell 7.0 stays the declared floor, but CI runs the hosted
runner's pwsh, not 7.0.
Stage 6 is next: [stage-6-retirement.md](stage-6-retirement.md) carries its
gates, including the Windows host converged on the landed revision, no unmarked
home, a fresh-home native install procedure for e2e, and its open decisions
D-1..D-17.
