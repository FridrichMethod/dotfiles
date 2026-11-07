# Stage 7: Trace removal

Status: planned on 2026-11-06 at `55a7960`, not started. It starts after the
Stage 6 record is on main. The fresh-session prompt is
[start-stage-7.md](start-stage-7.md). This is the last stage: its final
repository commit deletes `docs/chezmoi-migration/`, this plan included.

## Goal

The user's end-state requirement of 2026-11-06. It supersedes every earlier
retention decision it conflicts with:

- Remove every legacy, deprecated and transition mechanism and every trace of
  it: residue `.gitignore` lines, environments, tests, fixtures, docs,
  comments, names and host-side files.
- Keep no safeguard for old options or old layouts. An option that only an
  earlier version had gets the same generic usage error as any unknown option:
  no branch, switch, warning or message that names it.
- The result reads as if this design had been the first one. Nothing in the
  tracked tree or on the six hosts mentions or handles the Stow layout, the AI
  parser chain, the takeover, the migration stages or their decisions.
- All six hosts end on the final main, verified.

Git history and tags are not rewritten: every host updates main fast-forward
only, and AGENTS.md forbids rewriting main. The history is the record of the
migration, so nothing in the tree needs to repeat it.

## The from-scratch test

For each candidate, ask whether a design written today for chezmoi on these six
hosts would contain it.

- No, it exists only because of Stow, the parser chain, the takeover or a
  stage: delete it with its tests, fixtures, docs, callers and host files.
- Yes, but its name, comment or message explains it against the old design
  ("native" as opposed to legacy, "retired", "no longer", "after takeover",
  "since Stage N"): keep the behavior and rewrite the text or name.
- Yes, unchanged: keep.

Not traces, keep them:

- Behavior any design needs: refusing malformed live JSON/TOML, an invalid or
  OS-incompatible role, unsafe ancestors; private modes; the fast-forward-only
  login updater with its clean-tree check; `--exclude=dirs` on apply; the
  modify templates; encrypted secrets; payload delegation; tool floors; the
  maintenance marker as an operational pause switch.
- The live age identity (`~/.config/chezmoi/age/identity.txt`) and the user's
  offline identity recovery copy, with their documentation.
- Compatibility with a third-party tool version a host still runs, for example
  both `pluginConfigs` IDs while Marlowe's Claude Code (2.1.150) predates
  2.1.285. Recheck each against the hosts' actual versions in Phase 0; once no
  host needs one, it is a trace. Dotfiles' own earlier versions never qualify.
- Upstream or user text that uses these words for unrelated reasons:
  `home/dot_config/kitty/kitty.conf`, `home/dot_p10k.zsh`, the battery list
  comment in `home/dot_tmux.conf`, `gitfast  # deprecated?` in
  `home/dot_zshrc`, the TabExpansion and API-key comments in
  `home/Documents/PowerShell/profile.ps1`, the user's SSH host group
  `home/dot_ssh/config.d/legacy.conf.tmpl`, the protein "residue" lines and the
  sherlock-kit project guidance in `home/dot_claude/CLAUDE.md` and
  `home/dot_codex/AGENTS.md`, the tealdeer note in
  `config/bootstrap/brew/cli.Brewfile`.

## Stage 6 decisions this stage overrides

| Stage 6 decision | Stage 7 direction |
| --- | --- |
| D-5: dedicated refusal of `--auto`/`--worker`/`-Auto`/`-Worker` | Generic usage error only; delete the declared `-Auto`/`-Worker` switches, the `--auto \| --worker` branch and their tests |
| D-8: keep the `.gitignore` residue lines until hosts are clean | Phase H1 cleans the hosts, then R5 deletes the lines and their comments |
| D-9: old payload `.stamp`/`.failed`/`payload.log` left on hosts | Delete them in Phase H1 |
| D-12: retired-name repository test with an allowlist | Delete the retired-name scan; keep the Markdown link check under a neutral name |
| D-17: synthetic-link takeover/recovery suites, `bf99958` conversion/recovery support | Delete the suites, the procedure and every pointer to `bf99958` |
| D-4: golden list with 3 retired Codex paths | Keep the owned-path golden list; delete the `retired` list (S7-5) |
| D-1: `common-only` by-hand route | Keep the route; rename the role only under S7-4 |

## Decisions

The user's goal answers most questions. Ask only these, in one batch with the
recommendation first, before the commits or host operations that need them, and
keep the answers in the session record (the final report), not in the tree.

| ID | Decision | Options (recommendation first) |
| --- | --- | --- |
| S7-1 | Migration records | (a) fold the durable content into the docs listed under R6 and delete `docs/chezmoi-migration/` in the last repository commit; (b) keep a one-page history note. Recommended (a) |
| S7-2 | Home binding `~/.config/dotfiles/native` and its guard | (a) locate the source from chezmoi's own config (`chezmoi source-path`, or the `sourceDir` that `home/.chezmoi.toml.tmpl` writes) in the updaters, profiles, doctor and `sync-payloads`; delete the binding format, its unbound/invalid states, the guard code that serves only it and the file on each host once the replacement is live there; (b) keep it. Recommended (a) if Phase 0 confirms its purposes were blocking the old writers and recording the handover |
| S7-3 | Non-default `persistentState` and the separate-state warning (`lib/bootstrap/checks.sh` `chezmoistate.boltdb`) | (a) return to chezmoi's default state path if Phase 0 shows the location exists only for the takeover's explicit argument set; move each host's state once by hand under maintenance; (b) keep it. Recommend from the Phase 0 evidence; (b) when unclear |
| S7-4 | Names that contrast with the old design | (a) rename them: step IDs `H7-native`/`HW-native`, the doctor row `native-config`, `tests/test_chezmoi_native_config.py`, "native" in prose where it means "not Stow", and the role `common-only` to `other` (matching `--platform other` and the e2e `other` host); (b) keep names, rewrite only text. Recommended (a). A rename that touches host state is a one-time host operation, never compatibility code |
| S7-5 | Codex `retired` paths (`sandbox_mode`, `sandbox_workspace_write`, `features.js_repl`) in `home/.chezmoidata/codex-policy.json` | (a) delete the list and its loop in `home/dot_codex/modify_private_config.toml` after Phase 0 shows no host's live `config.toml` holds them; (b) keep. Recommended (a) |
| S7-6 | Retired submodule checkouts and empty old-layout directories in each host checkout | (a) delete each after proving it has no local-only work (clean status, no stash, every local commit reachable from its upstream); (b) keep. Recommended (a) |
| S7-7 | Host-side migration evidence, including Lab's recovery store | (a) after every host passes final acceptance, present the exact per-host list and delete what the user confirms, Stage 7's own snapshots last; (b) keep it outside the repository. Recommended (a). Irreversible: confirm the exact list |
| S7-8 | Standing host-operation authority (status.md D11) once status.md is gone | (a) one neutral AGENTS.md rule: agents may roll landed changes out to the six hosts by `docs/hosts.md`; (b) drop it, future host work asks first. Recommended (a) |

Commit, publication and rollout authority for this stage is the existing D11
and AGENTS.md "Workflows and checks". Ask before anything they forbid or that
cannot be undone (S7-6, S7-7).

## Entry gate

- The Stage 6 record is on main and main's exact-SHA CI is green.
- All six hosts are at that main, no maintenance marker is in place, and no
  Stage 6 worktree, branch or `ci/**`/`e2e-ci/**` branch remains.
- This plan is on main (merge `stage7/plan` first if Stage 6 did not).

## Phase 0: read-only inventory and baselines

1. Repository. Run the scan of
   [Zero-trace acceptance](#zero-trace-acceptance) at the base with `git grep`,
   including file and directory names. Classify every hit by the from-scratch
   test as delete, rewrite or keep, and freeze the classification in the
   session scratchpad. Never commit the scanner or its list.
2. Hosts, metadata only. List every host trace below that exists, with sizes
   and, for checkouts, status, stash and unpushed commits. Read every live
   Codex `config.toml` for the S7-5 paths privately, logging key names only.
3. Baselines per host: HEAD, `chezmoi managed` count, doctor rows (TSV),
   both AI configs equal to rendered (equal/not equal), interactive shell
   start, PowerShell 7 and 5.1 profile parse and load on win.
4. Ask S7-1..S7-8.

### Known repository traces at `55a7960`

A broad pattern hit 74 tracked files (603 lines) outside
`docs/chezmoi-migration/`; some hits are allowed text. Re-derive at your base.

- Migration-only tests: `tests/test_chezmoi_takeover_recovery.py`,
  `tests/test_chezmoi_takeover_unix.py`, `tests/test_chezmoi_takeover_windows.py`,
  `tests/chezmoi-takeover.sh`, `tests/chezmoi-takeover.ps1`; the retired-name
  part of `tests/test_repository_text.py` and its hook; retired-flag cases in
  `tests/payload-update.sh` and `.ps1`; Stow and login-stow audits in
  `tests/e2e/lib/assert.sh`, `tests/e2e-harness.sh` and `.ps1`; legacy and
  takeover cases in `tests/test_chezmoi_guard.py`, `tests/setup-host.sh`,
  `tests/doctor.sh`, `tests/bootstrap.ps1`, `tests/test_chezmoi_provision.py`,
  `tests/test_chezmoi_source_state.py`, `tests/test_ai_policy.py`,
  `tests/test_chezmoi_codex.py`, `tests/test-entrypoints.sh`,
  `tests/e2e/lib/steps.sh` and `.ps1`; their rows in `tests/COVERAGE.md` and
  `docs/testing.md`. Keep each surviving behavior's own test.
- Compatibility code and deprecated-option handling:
  `scripts/payload-update.sh` (`--auto | --worker`),
  `scripts/payload-update.ps1` (`-Auto`/`-Worker` declared only to be
  refused); the Codex `retired` list (S7-5); the binding and its readers
  (S7-2): `lib/chezmoi-guard.sh` and `.ps1`, `scripts/chezmoi-update.sh` and
  `.ps1`, the profile hooks in `home/dot_profile` and
  `home/Documents/PowerShell/profile.ps1` ("never execute a retired checkout's
  guard or updater"), `doctor.sh`, `doctor.ps1` and `lib/bootstrap/checks.sh`
  states and messages that point at `docs/chezmoi-migration/takeover.md`;
  takeover blocks in `lib/bootstrap/steps-human.sh` and `setup-host.ps1`.
- Repository configuration: the `.gitignore` residue block (`/.venv-sync/`, the
  four retired checkout lines and their comments); the Stage 4 receipt digest
  in `.gitleaks.toml`; the retired-name hook and selectors in
  `.pre-commit-config.yaml`; history comments in `home/.chezmoiignore`.
- Docs: `README.md` (Stow homes, `bf99958`, takeover, leftover checkouts),
  `AGENTS.md` (D11, `bf99958`, the residue-line and retired-name-test rules,
  the retired Sherlock checkout and old Sherlock link rules, "existing 0.6
  copies still run" for the kit on Windows unless win still has one,
  "native" contrasts),
  `docs/bootstrap.md`, `docs/payloads.md` (Migration, Leftover checkouts),
  `docs/config-sync.md` (named after the retired sync helpers),
  `docs/update-contract.md`, `docs/testing.md`, `docs/shell.md`,
  `docs/dependencies.md`, `tests/COVERAGE.md`, both mirrored
  `dotfiles-bootstrap` skills, and `docs/chezmoi-migration/**` (S7-1).

### Known host traces

From the Stage 6 Phase 0 and Phase C records and a Lab listing on 2026-11-06.
The Stage 6 record lists the exact paths per host; re-derive on each host.

- In each checkout: retired submodule checkouts under `common/`
  (`common/coding-agent-kit/coding-agent-kit/`, `common/pymol/PyMOLScripts/`,
  `common/codex/coding-agent-kit/`, `common/sherlock-kit/sherlock-kit/`; one
  to four per host) and empty old-layout directories that git left behind
  (Lab: `lab-ubuntu/fcitx5/.config/fcitx5/conf`).
- `~/.local/state/dotfiles/payload/` stamps, `.failed` files and
  `payload.log` (Lab, WSL, Sherlock, Marlowe).
- Migration evidence and snapshots: Lab's
  `~/.local/state/dotfiles-chezmoi-migration-recovery/` (the private
  pre-takeover recovery store) and about two dozen
  `~/.local/state/dotfiles-stage4-*`, `dotfiles-stage5-*`, `dotfiles-stage6*`,
  `dotfiles-consolidation-*` and `dotfiles-cleanup` entries; every Unix host's
  Stage 5 and Stage 6 evidence; Marlowe's `~/.local/state/dotfiles-marlowe-tmux-*/`;
  the Stage 4 private host backups named in status.md; on win
  `~\.config\dotfiles-stage5-task\`, `~\.config\dotfiles-stage6-task\` (which
  holds the moved `.venv-sync`, `.git\dotfiles-sync-windows\` and dangling
  `~\.local\bin` links) and `~\.config\chezmoi\stage5-reinit\`.
- Under S7-2 or S7-3: `~/.config/dotfiles/native` and the old state file, after
  the replacement is live on that host.
- Git metadata: remote-tracking refs of deleted `ci/**` and `e2e-ci/**`
  branches and any custom file Phase 0 finds under `.git/`.

Before deleting any `dotfiles-stage4-*age*` or secret-enrollment directory,
confirm (exit status only) that chezmoi on that host decrypts with its live
identity and that the user confirms the offline identity recovery copy exists.

## Ordered work

### Phase H1: clean the host checkouts before the ignore lines go

The login updater refuses a checkout whose `git status` is not clean, and the
residue `.gitignore` lines are what hide the leftovers. On all six hosts,
before main drops them: delete the retired checkouts and empty old-layout
directories (S7-6), any remaining `.venv-sync` and the payload stamp/log files.
Then `git status --porcelain --ignored` in each checkout must list only
expected ignored paths (`.worktrees/` on Lab, tool caches). One owner per
host, a private snapshot first for anything not reproducible from an upstream.

### Phase R: repository commits

Each commit: tests first (RED, then GREEN where behavior changes), focused
suites, `tests/run.sh --ci`, `pre-commit run --all-files`, a conventional
message without AI attribution, explicit `git add <paths>`. Suggested order:

- **R1 `test: drop the migration-only suites`**: the tests listed above; keep
  the Markdown link check, renamed (for example `tests/test_markdown_links.py`).
- **R2 `refactor!: drop compatibility and retired-option handling`**: payload
  flags (generic usage error), the S7-5 list, takeover pointers and messages,
  retired-checkout comments; every caller and doc in the same commit.
- **R3 `refactor!: locate the source through chezmoi`** (S7-2, and S7-3 if
  chosen), with tests for the new lookup and for refusal when chezmoi has no
  config. No code that reads, migrates or warns about the old binding or path.
- **R4 `refactor: name things for the current design`** (S7-4).
- **R5 `chore: drop the residue ignore lines and allowlists`**: `.gitignore`,
  `.gitleaks.toml`, `.pre-commit-config.yaml` selectors and excludes for
  deleted files. Lands only after Phase H1 is complete on all six hosts.
- **R6 `docs: describe the current design`**: rewrite README.md, AGENTS.md
  (under 28,000 bytes; S7-8), docs/*, tests/COVERAGE.md and both skills
  (identical bodies) without stage numbers, decision IDs, "takeover", "no
  longer" or native-versus-legacy wording. Fold durable migration content
  into neutral homes:
  - `docs/bootstrap.md`: a new home by hand (takeover.md "Fresh home"), the
    `common-only`/`other` route, directory-only preparation of missing parents.
  - `docs/updates.md` (replaces `docs/update-contract.md`): the login updater,
    editing and adding files, merge and apply, the maintenance marker and a
    maintenance-gated rollout of a breaking change (from fleet-rollout.md).
  - `docs/secrets.md` (from secrets-and-ssh.md): recipients, enrolling a
    secret or a host, identity bootstrap and recovery custody.
  - `docs/ai-config.md` (renamed `docs/config-sync.md`): ownership, policy
    rationale, reconciling an owned key.
  - `docs/hosts.md`: per-host operating rules that stay true: win ordinary
    token and one-off limited-token tasks, the admin SSH limits; Sherlock site
    rules and `shk`; Marlowe login env, AppArmor `block-node`, ACLs; known
    host limits from the Stage 6 "Not in Stage 6" list.
  - `docs/dependencies.md`: the tool floors from support-boundary.md.
- **R7 `docs: remove the migration records`**: delete
  `docs/chezmoi-migration/` and every link to it. Keep a private copy of this
  plan in the session scratchpad for Phase H2.

Land once: push the exact candidate SHA to `ci/<name>` and `e2e-ci/<name>`,
wait for every `ci.yml` and `bootstrap-e2e` job on that SHA, fast-forward main
only, delete both branches. Because R3 changes the updater and the profiles,
quiesce the hosts first (Phase H2 step 1).

### Phase H2: roll out and finish the hosts

1. Before main moves, put `~/.config/dotfiles/maintenance` on the five remote
   hosts (win: an approved one-off limited-token task).
2. Land Phase R.
3. Lab first, then host by host: update fast-forward only through the login
   updater or explicit chezmoi commands with the updater's arguments plus
   `--exclude=dirs --force=false`, accept, and lift maintenance on that host.
   Restore maintenance on failure. Do not add compatibility code for this
   one-time switch: if an old deployed hook cannot hand over to the new
   updater, do that host's step by explicit commands under maintenance.
4. On each host once the new lookup is live: delete the binding file and the
   old state file (S7-2, S7-3).
5. Per-host acceptance: HEAD is the final main; managed count equals the
   baseline plus the expected delta; no doctor row worse than the baseline;
   both AI configs equal rendered; interactive zsh and bash start without
   warnings; PowerShell 7 and 5.1 profiles parse and load on win; no
   maintenance marker; no `Dotfiles-*` scheduled task on win.
6. After all six pass: present the S7-7 list, delete exactly what the user
   confirms, Stage 7's own snapshots last, and run the host part of the
   zero-trace acceptance.

## Zero-trace acceptance

Run once at the end; never commit the scanner or its pattern.

- Tracked tree, contents and paths, case-insensitive:

  ```text
  stow|legacy|retire|deprecat|stage[ -]?[0-9]|venv-sync|tomlkit|setup-sync|
  config.sync|sync-runtime|bf99958|DOTFILES_HOST|DOTFILES_DIR|receipt|takeover|
  handover|migration|pre-chezmoi|auto-stow|restow|--auto\b|--worker\b|-Auto\b|
  -Worker\b|awesome-skills-update|leftover|residue|transition|formerly|
  no longer|old[- ]layout|dotfiles-sync-|\bD-?(1[0-7]|[1-9])\b|\bD11\b|native
  ```

  plus legacy package paths
  `(^|[^A-Za-z_/.-])(common|mac|sherlock|wsl-ubuntu|lab-ubuntu|marlowe|win)/[A-Za-z._]`.
  Only the allowed text above may remain; review each `native` hit by hand
  and keep it only where it means a platform (native Windows). No Markdown
  link may point at a deleted file.
- Each host: none of the known host traces exist; each checkout's
  `git status --porcelain --ignored` lists only expected paths.
- A fresh clone into an empty HOME converges (init, apply, second apply with no
  changes) on Linux; CI covers macOS and Windows; bootstrap e2e covers all
  seven flows.

## Risks

- Order: R5 before Phase H1 completes makes every unclean host refuse its
  login updates.
- The old deployed hook meets the new updater once per host: handle it under
  maintenance, not with code.
- Deletion is irreversible: retired checkouts may hold local work, and Stage 4
  directories may hold identity material. Prove, then ask.
- Over-deletion: input refusals and safety checks a fresh design needs are not
  traces.
- `tests/run.*`, CI workflows and pre-commit selectors that name deleted files.
- AGENTS.md stays under 28,000 bytes; both skills stay identical.
- Sherlock and Marlowe site rules and the win token limits apply throughout.

## Completion

- Report to the user: commits with exact CI and e2e run IDs, per-host before
  and after, removed host traces, the zero-trace scan summary, and anything kept
  with its reason. With the records deleted, this report and the commit
  messages are the record.
- Update the agent memory entries under
  `~/.claude/projects/-home-fridrichmethod-dotfiles/memory/` that describe
  retired mechanisms as current.
- Remove every Stage 7 worktree and branch, local and remote.
