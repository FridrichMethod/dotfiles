# Stage 2: Ordinary source state implementation plan

> **For agentic workers:** Use subagent-driven-development with separate worktrees
> and the coordination rules in [README.md](README.md). Refine this plan from
> Stage 1 evidence before implementation; complete only this stage.

**Goal:** Represent every ordinary managed target and host selection in native
chezmoi source state while keeping legacy source paths usable.

**Architecture:** `.chezmoiroot` selects `home/`. Local data selects one explicit
host role. Ordinary files use native attributes and small templates. A temporary
bridge keeps legacy portable content authoritative until retirement, avoiding
two independently edited source copies.

**Tech stack:** Native chezmoi files/templates, existing shell configuration,
Stage 1 stdlib integration tests.

**Spec:** [Migration direction](README.md), [status](status.md), Stage 1's inventory
and selected-release evidence, and [support boundary](support-boundary.md).
Read [secrets and SSH](secrets-and-ssh.md) for encrypted snippet ownership.

## Implemented Stage 2 contract

The candidate contains 67 ordinary source files and five control files across
the seven explicit roles. The exact row map is in `inventory.md`; role file sets
remain `47/54/53/57/52/52/24`. No runtime installer or login default changed.
Text payloads are literal includes of the current legacy sources. Only WebP and
compiled terminfo are raw copies, with canonical legacy ownership and parity
tests until Stage 6. Pet JSON metadata is also an include bridge.

The local config must contain `[data].host`. The shared guard at
`home/.chezmoitemplates/validate-host` rejects missing/empty/non-string/unknown or
OS-incompatible choices. `home/.chezmoiignore` evaluates it before targets;
`home/.chezmoi.toml.tmpl` explicitly evaluates the internal guard with
`includeTemplate` because init does not load named templates. This does not
evaluate any legacy content as a template. No host is inferred from the OS or
`DOTFILES_HOST`. Noninteractive initialization requires an existing explicit
local data value; no interactive selector or automatic takeover is introduced.

`tests/chezmoi_source_support.py` independently derives expectations from the
95-row inventory and checks the Git index. `test_chezmoi_source_state.py` checks
real managed file sets, bytes, empty files, executable/private attributes,
unmanaged siblings, no source mutation and clean second apply/diff. It labels
OS-data overrides as supplemental. `test_chezmoi_rendered.py` parses/lints actual
deployed bytes, with optional tool skips visible. The original behavior and lint
suites still check canonical legacy inputs during coexistence.

Windows retains the six common packages and the seven Windows-worker files;
shared Git/SSH variants supply the other two host rows. Both actual native
PowerShell `CurrentUserAllHosts` paths were queried without reading profiles and
matched the tracked Documents targets. A redirected profile location blocks
Stage 4 takeover until explicitly mapped or rejected before mutation. Synthetic
HOME overrides and supplemental Linux rendering cannot establish this fact.

Regular deployment means GUI edits are destination drift: review native diff,
then consciously edit/add/merge through the source workflow. Until Stage 6, edit
the legacy canonical text behind each bridge; adding a full replacement into
`home/` would create a second policy source. No automatic write-through to legacy
source is promised. Do not run this incomplete candidate against real HOME.

Validation and native platform evidence are recorded in `status.md`; the next
session starts with [start-stage-3.md](start-stage-3.md).

## Global constraints and review focus

No live apply, installer-default switch, legacy path move or deletion. Keep all
policy values and application behavior. Candidate source is incomplete until
Stage 3; do not advertise normal `init --apply` as a supported live workflow yet.

Review particularly: Windows applicability; empty-vs-unselected host meaning;
hidden/binary/executable files; source-root vs working-tree path resolution;
shared directories containing unmanaged state. A host switch is not automatic
permission to remove the previous host's live files.

## File ownership and parallel tasks

| Owner | Exclusive files | Dependencies |
| --- | --- | --- |
| Coordinator | `.chezmoiroot`, `.chezmoiversion`, `home/.chezmoi.toml.tmpl`, `home/.chezmoiignore`, common data schema, shared runners/docs/CI | Stage 1 evidence and inventory |
| Unix source worker | Assigned Unix/shared target subtrees and host fragments | Frozen host/data and bridge interface |
| Windows source worker | Assigned Windows paths and PowerShell/profile fragments | Same interface; native Windows fixture |
| Verification worker | Dedicated source-state test module and inventory checks | Frozen target contract; no edits to other workers' targets |

With only three worker slots, let the coordinator integrate common/shared files
and use workers for Unix, Windows and verification. Keep ownership disjoint even
across worktrees to reduce integration conflicts.

## Task 1: Freeze host data and the temporary source bridge

### Stage 1 handoff: execute these packages in order

Start from the completed Stage 1 integration worktree/patch in `status.md`, not
bare `1a9d30b`: the tests and original handoff can still be uncommitted. Recheck
HEAD/status/worktrees and carry the complete scoped patch intentionally. Read
`inventory.md` as the exact 95-row source map; regenerate it if tracked targets
changed. Stage 1 selected v2.74.0; older chezmoi releases have no test evidence.
Native macOS/Windows checks remain mandatory evidence before live takeover.

1. Coordinator first creates `tests/test_chezmoi_source_state.py`'s small bridge
   contract cases, then `.chezmoiroot` (`home`) and `.chezmoiversion` (`2.74.0`).
   Before bulk files, prove a literal include from `.chezmoi.workingTree` in a
   disposable linked Git worktree with spaces. Use `ChezmoiFixture` and sanitized
   fixture Git; no real repository import or HOME apply. Prove source-root vs
   working-tree resolution, literal `{{` bytes and unchanged original content.
2. Freeze local `[data].host` with exactly `common-only`, `mac`, `wsl-ubuntu`,
   `lab-ubuntu`, `sherlock`, `marlowe`, `win`. Missing/empty is uninitialized and
   fails noninteractive apply; it never aliases common-only. Validate `mac` with
   Darwin, `win` with Windows, Linux roles with Linux; common-only is Unix.
   Interactive initial selection may prompt once; tests always supply local
   data. OS detection validates the choice rather than selecting an overlay.
3. Publish an explicit destination list per role from inventory rows before
   parallel writes. Omit only the two AI mutable targets for Stage 3 and four
   legacy sync helpers (three AI helpers plus fcitx5-profile-sync). Keep
   `portable.rules` and the lab fcitx5 profile as ordinary native targets.
   Deduplicate host variants by destination; do not sum all inventory rows as
   if every role deployed every file. Count directories separately from files.
4. Assign disjoint writes after these interfaces pass: Unix worker owns
   `home/dot_bash*`, `dot_aliases.tmpl`, `dot_profile.tmpl`, `dot_zsh*`,
   `dot_zprofile.tmpl`, `dot_p10k.zsh.tmpl`, `empty_dot_tcshrc.tmpl`,
   `empty_dot_xonshrc.tmpl`, `dot_tmux.conf.tmpl`, `dot_vimrc.tmpl`,
   `dot_xprofile.tmpl`, `dot_terminfo`, `dot_oh-my-zsh`,
   `dot_local/bin/executable_my-fzf-preview.sh.tmpl`, and `dot_config` subtrees
   `aria2`, `bash`, `sh`, `zsh`, `kitty`, `tmux`, `fcitx5`.
   Windows worker owns `home/Documents`, `home/AppData`, `dot_wslconfig`,
   `mount.vbs`, `wsl.conf`, and `dot_config/oh-my-posh`. Coordinator owns shared
   Git/SSH/Conda/WezTerm/Claude/Codex/pet targets (including
   `dot_local/bin/executable_claude-limited.tmpl`), ignore/config/data files,
   platform selection and all shared integration. Verification worker owns
   `tests/test_chezmoi_source_state.py` after the initial contract is frozen.
   Confirm exact encoded paths from the inventory before dispatch; fragments
   belong to the same owner as their destination. No two writers share a tree.
5. Use literal include bridges for text, preserving legacy source as canonical.
   Binary WebP/terminfo use explicit raw copies with byte-parity tests (one
   declared temporary duplication); zero-byte configs must remain managed empty
   files. Preserve executable/private attributes separately from content. Test
   quote/delimiter bytes; never render legacy shell files as Go templates.
6. Verification compares native `managed` file targets and rendered bytes with
   inventory for common-only and six roles. On each actual OS run compatible
   host roles and reject incompatible choices. Cross-role rendering fixtures
   supplement actual native OS jobs; they must not be reported as native OS
   execution. Preserve unmanaged siblings, private modes where supported,
   source bytes and second-apply convergence.
7. Before closing the stage, run `tests/chezmoi.sh`, source-state tests, relevant
   shell/tmux/AI/PowerShell behavior suites, `tests/run.sh --ci` and full
   pre-commit. Extend the existing native hook selector to source templates and
   add rendered lint checks for encoded/template files. Keep CI's verified
   runtime and legacy parser provisioning; obtain an independent read-only
   aggregate review, then refine Stage 3 with actual bridge/data paths.

Do not raise tmux/Bash/Claude floors or remove their gates during this mapping:
Stage 1 did not establish cross-platform evidence for those changes. Keep both
Claude plugin IDs until the documented ID-direction discrepancy is resolved.
No encrypted production credential or dummy account file belongs in Stage 2.
Map SSH ownership now; optional private enrollment remains Stage 4.

**Create:** Root `.chezmoiroot`, `.chezmoiversion`, `home/.chezmoi.toml.tmpl`,
`home/.chezmoiignore` and minimal shared host data. **Update:** Stage 1 inventory.

- [x] Set `.chezmoiroot` to `home`; set the minimum only from Stage 1 evidence.
- [x] Define a local `host` value using the seven explicit names in the spec.
  An explicitly chosen common-only value must differ from an uninitialized
  choice. Reject unsupported values and incompatible OS/role combinations.
- [x] Preserve native Windows's package applicability; do not deploy Unix rc
  files there. Keep WSL and native Windows homes separate.
- [x] Select one temporary bridge: thin native include templates reading the
  existing tracked baselines are preferred. Use literal `include`, not
  `includeTemplate`/`template`, for legacy content that may itself contain template
  delimiters. A candidate is an include path rooted in `.chezmoi.workingTree`;
  prove this with `.chezmoiroot=home`, a linked worktree and a path containing
  spaces. Avoid tracked machine-home literals or a source-generation service.
- [x] If a file cannot reasonably use that bridge, allow a temporary copy only
  with an explicit canonical owner and a test that detects divergence. List it
  for Stage 6 removal. Do not silently maintain two policy sources.
- [x] Keep helper resolution explicit; copied legacy symlink-resolving wrappers
  are not valid native runtime helpers. Leave old sync wrappers on the legacy
  path, excluded from the new managed targets.

## Task 2: Map ordinary files and host fragments

**Create:** `home/` ordinary target paths, host fragments under
`home/.chezmoitemplates/`, and `tests/test_chezmoi_source_state.py`.

- [x] Convert the Stage 1 inventory, including new tmux configuration and binary
  assets. Most shell contents should remain byte-equivalent after rendering.
- [x] Map old-tool gates to the new canonical configuration and Stage 1's chosen
  floors. Remove them here only if the component's minimum version, provisioning,
  support notice, tests and docs change coherently in this stage. Otherwise assign
  the actual deletion to Stage 5; do not launch a second parallel rewrite of the
  same tmux/Claude source or silently break the still-supported Stow path.
- [x] Preserve `.gitconfig_local`, SSH snippet and shell override composition.
  Use a full-file fragment when variants differ substantially; do not rewrite
  every shell file into a large conditional template.
- [x] Map SSH Include/host/jump/master semantics explicitly. Use synthetic tests
  for private encrypted snippets and ensure the ordinary source does not import
  private keys, known_hosts or sockets. Actual private enrollment is Stage 4;
  existing tracked endpoints do not become historically secret by encrypting a
  later revision. Preserve a workable access/recovery path for takeover.
- [x] Model executable/private files with native attributes. Verify actual
  output contents and modes, not merely source filenames.
- [x] Manage `portable.rules` as an opaque file and fcitx5 profile as a private
  ordinary file on its applicable host. Preserve unrelated siblings.
- [x] Leave the two AI mutable targets for Stage 3 and document that explicit
  gap. Do not replace them with complete portable-file copies even temporarily.
- [x] Keep ordinary editable GUI configs plain where practical. Document that
  GUI saves become live drift to review/add/merge, not source write-through.
- [x] Retain the actual Windows `$PROFILE` location check or model its location
  as local data. Do not assume Documents is never redirected or that Linux
  rendering validates Windows application discovery.

## Task 3: Verify native target coverage and preserve behavior

**Tests:** Stage 1 fixture, `tests/test_chezmoi_source_state.py`, current shell,
tmux, AI-policy and PowerShell behavior suites as applicable.

- [x] For common-only and all six hosts, compare the expected inventory with
  native managed targets: no missing ordinary target, no extra runtime/secret
  target, and exactly the documented Stage 3 omissions.
- [x] Compare rendered ordinary content to legacy baselines, excluding only
  explicitly recorded intentional path/workflow changes.
- [x] Run real native fixtures on Linux, macOS and Windows. A mocked host-data
  render supplements but does not replace platform evidence.
- [x] Verify no source mutation, second-apply convergence, unmanaged sibling
  preservation and permissions. Test the source bridge from a linked worktree.
- [x] Adapt behavior tests to accept rendered fixtures where needed. Keep legacy
  suites operating while old installations are supported; do not delete tmux or
  shell behavior tests just because their source paths will eventually change.
- [x] Audit pre-commit file selectors for encoded names such as `dot_zshrc` and
  `executable_...`, and for `.tmpl` inputs. Keep direct lint on plain native
  source and validate rendered shell/Lua/config output where source is a template;
  do not feed Go templates to shell parsers or silently lose coverage on renames.
- [x] Run required aggregate checks and obtain an independent read-only review.

## Exit, rollback and next-stage refinement

Exit requires complete ordinary-file coverage and native host selection with
documented AI gaps. Existing source paths, installers and auto-update defaults
remain intact. Candidate source has not taken over a real HOME.

Update `status.md`, bridge ownership and inventory. Expand Stage 3 with exact
canonical portable-data paths, selected-release syntax and focused test commands.
Record any Windows profile/ACL questions for Stage 4. Rollback affects only the
candidate source and its tests; no live rollback is required.
