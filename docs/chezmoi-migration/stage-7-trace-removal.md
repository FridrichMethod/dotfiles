# Stage 7: Trace removal

Status: planned on 2026-11-06, corrected on 2026-11-07 after two read-only
reviews against the landed Stage 6 record (`3cb223e`); not started. The
fresh-session prompt is [start-stage-7.md](start-stage-7.md). This is the
last stage: its landing deletes `docs/chezmoi-migration/`, this plan included.

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

Git history and tags are not rewritten (the user confirmed this on
2026-11-07): every host updates main fast-forward only, and AGENTS.md forbids
rewriting main. The history is the record of the migration.

## Authority

On 2026-11-07 the user approved this plan and asked that a fresh session carry
it out to completion. That approval extends the D11 host authority and the
AGENTS.md "Workflows and checks" landing rules to Stage 7: commits, publication,
rollout and the host operations below need no further authorization question.
The same day the user gave standing approval for one-off limited-token win
tasks (status.md, Stage 6 completion record). Ask the user only the decision
batch (S7-1, S7-2, S7-4, S7-5, S7-8) after Phase 0, and the exact S7-7 deletion
list with the offline-identity confirmation at the end.

Expected user actions, not questions: win logged on while its limited-token
tasks run, mac awake, and live existing SSH control masters for Sherlock and
Marlowe. Tell the user once after Phase 0 which phases need them; if one is
missing at a step, ask the user to restore it and wait. Never log in or
authenticate for the user.

## The from-scratch test

For each candidate, ask whether a design written today for chezmoi on these six
hosts would contain it.

- No, it exists only because of Stow, the parser chain, the takeover, an
  earlier dotfiles or kit version, or a stage: delete it with its tests,
  fixtures, docs, callers and host files.
- Yes, but its name, comment or message explains it against the old design
  ("native" as opposed to legacy, "retired", "no longer", "after takeover",
  "since Stage N"): keep the behavior and rewrite the text or name.
- Yes, unchanged: keep.

Not traces, keep them:

- Behavior any design needs: refusing malformed live JSON/TOML, an invalid or
  OS-incompatible role and unsafe ancestors; private modes; `--exclude=dirs`
  on apply; the modify templates; encrypted secrets; payload delegation; tool
  floors; the maintenance marker as an operational pause switch. In the login
  updaters and `lib/chezmoi-guard.*`: the maintenance check, session-once and
  `DOTFILES_AUTO_UPDATE=0` opt-out, the clean-tree check, fast-forward-only
  update, the OneDrive skip, Git environment sanitization, the explicit
  `--persistent-state` and full argument set, refusal when the home has no
  valid config, and the Windows exact-exe trust check.
- The state database at `~/.local/state/chezmoi/chezmoi.boltdb`, owned by the
  config template's `persistentState` and passed explicitly by both updaters
  (S7-3).
- Every `.gitleaks.toml` rule and every allowlist matching value (regexes,
  paths, stopwords). CI's `gitleaks-history` scans every commit with the
  current config and history is not rewritten, so a value only older commits
  contain (the SHA256 `682a1258...22b5b`, `Bearer abcdefghijkl`) must stay.
  Reword its comments and `description` strings.
- The live age identity (`~/.config/chezmoi/age/`; never delete it) and the
  user's offline identity recovery copy, with their documentation.
- The Sherlock controller `~/.local/share/chezmoi-sherlock-kit-provisioning`
  while S7-8 (a) keeps it.
- Compatibility with a third-party tool version a host still runs, for example
  both `pluginConfigs` IDs while Marlowe's Claude Code (2.1.150) predates
  2.1.285. Recheck each against the hosts' actual versions in Phase 0; once no
  host needs one, it is a trace. Dotfiles' and the kit's own earlier versions
  never qualify.
- "Overlay" for the role-variant layer: a current term, not a Stow one.
- Unrelated senses of the scan's words: `native` for a platform (native
  Windows, natively) or a tool's own built-in behavior (AGENTS.md "native
  tools/behavior/features", tmux's native defaults, OSC 52 and copy bindings
  in `home/dot_tmux.conf`, the tpm and catppuccin rows of
  `config/bootstrap/tools.tsv`); "leftover", "no longer" or "receipt" about
  another tool or file (Homebrew kegs, editor and merge files, `.chezmoidata/`,
  TEMP, oh-my-zsh, an HTTP header); key bindings and `bound` meaning a limit
  (`DOTFILES_PAYLOAD_TIMEOUT`); Codex `allow_local_binding`;
  `window_background_opacity = 0.6` in `home/dot_wezterm.lua`; "alternative";
  shell `:-auto` defaults; PowerShell's `$PSNativeCommandUseErrorActionPreference`.
- Upstream or user text: `home/dot_config/kitty/kitty.conf`,
  `home/dot_p10k.zsh`, the battery list comment in `home/dot_tmux.conf`,
  `gitfast  # deprecated?` in `home/dot_zshrc`, the TabExpansion and API-key
  comments in `home/Documents/PowerShell/profile.ps1`; the user's SSH host
  group `legacy.conf` (`home/dot_ssh/config.d/legacy.conf.tmpl`, the role files
  `home/.hosts/*/.ssh/config.d/legacy.conf` and every reference to them); the
  protein "residue" lines and the OneDrive `--no-auto-maintenance` commands in
  `home/dot_claude/CLAUDE.md` and `home/dot_codex/AGENTS.md`; the tealdeer note
  in `config/bootstrap/brew/cli.Brewfile`.

## Stage 6 decisions this stage overrides

| Stage 6 decision | Stage 7 direction |
| --- | --- |
| D-5: dedicated refusal of `--auto`/`--worker`/`-Auto`/`-Worker`, and the sourced-call contract of `scripts/payload-update.sh` | Generic usage error only; delete the declared `-Auto`/`-Worker` switches, the `--auto \| --worker` branch, the return-when-sourced handling (only old rc files sourced the hook) and their tests |
| D-8: `.gitignore` residue lines, their pin test and the AGENTS.md rule | R5 deletes them; Stage 6 already moved everything they matched off every checkout |
| D-9: old payload `.stamp`/`.failed`/`payload.log` left on hosts | Delete them and their directories in Phase H1 |
| D-12: retired-name repository test with an allowlist | Delete the retired-name scan; keep the Markdown link check under a neutral name |
| D-17: takeover/recovery suites and `bf99958` conversion/recovery support | Delete the Stow-conversion cases, the `tests/chezmoi-takeover.{sh,ps1}` runners, the procedure and every pointer to `bf99958`; keep and rename the login-updater, Windows trust and missing-parent preparation suites (R1, R4) |
| D-4: golden list with 3 retired Codex paths | Keep the owned-path golden list; delete the `retired` list (S7-5) |
| D-1: `common-only` by-hand route | Keep the route; rename the role under S7-4 |

## Decisions

Keep the answers in the session record (the final report), not in the tree.

| ID | Decision | Options (recommendation first) |
| --- | --- | --- |
| S7-1 | Migration records | (a) fold the durable content into the docs listed under R6 and delete `docs/chezmoi-migration/` in R7; (b) keep a one-page history note. Recommended (a) |
| S7-2 | Home binding `~/.config/dotfiles/native` | (a) replace it with a fail-closed text read of the top-level `sourceDir` and `destDir` keys of `~/.config/chezmoi/chezmoi.toml` (details below); delete the binding format and its unbound/invalid states, and the file on each host in H2; (b) keep it, renamed under S7-4. Recommended (a) |
| S7-3 | Decided: keep `persistentState` | Keep the state where it is (Not traces). Reword only the takeover sentence in `scripts/chezmoi-update.sh` and comments. Delete the stray-database warning (`chezmoistate.boltdb`) and everything that only checks it: it detects state from before the config owned the path. Not asked |
| S7-4 | Names that contrast with the old design | (a) apply the frozen old-to-new map (Phase 0) to every identifier, step ID, hook ID, file name and doc anchor containing native, handover or takeover, and rename the role `common-only` to a name no `--platform` value uses (for example `generic`; the platforms are macos, debian, hpc, other, windows); (b) keep names, rewrite only text. Recommended (a) |
| S7-5 | Codex `retired` paths (`sandbox_mode`, `sandbox_workspace_write`, `features.js_repl`) | (a) delete the list in `home/.chezmoidata/codex-policy.json` and its loop in `home/dot_codex/modify_private_config.toml` after Phase 0 shows no host's live `config.toml` holds them; (b) keep. Recommended (a): the values came from dotfiles' own earlier portable config |
| S7-6 | Folded into S7-7 | Stage 6 moved the retired checkouts into evidence, so they are deleted with it after the proof below |
| S7-7 | Host-side migration evidence and artifacts | (a) after every host passes acceptance, present the exact per-host list (Known host traces) with the proof results and delete what the user confirms; (b) keep it. Recommended (a). Irreversible |
| S7-8 | Future host authority and the Sherlock controller | (a) one neutral AGENTS.md rule that agents may roll landed changes out to the six hosts by `docs/hosts.md`, and keep the controller, documented there with its pin (sherlock-kit v0.6.0, which its `uv.lock` resolves to sherlock-kit commit `09a37281`; the controller is a plain uv project, not a Git repository), its absolute `.venv/bin/shk` and `shk rules workstation`; (b) drop the rule, delete the controller after the last Sherlock operation, and document that Sherlock work asks for an shk route first. Recommended (a) |

### S7-2 (a) in detail

- One validator in POSIX sh (`lib/chezmoi-guard.sh`, renamed under S7-4) and
  one that parses under PowerShell 5.1 (`lib/chezmoi-guard.ps1`). The profiles
  and `home/dot_aliases` keep the two-step shape: a minimal pre-read of
  `sourceDir` to find the validator, then the validator. Doctor, setup-host,
  `sync-payloads` and both updaters reuse it; no second parser.
- Never run `chezmoi source-path` or any chezmoi command to locate the source:
  it returns `<checkout>/home`, PowerShell would run a PATH chezmoi before the
  trust check, and the doctor and `setup-host --check` run chezmoi only for the
  tools.tsv `--version` floor probe.
- Accept exactly one `sourceDir` and one `destDir` line before the first table
  header, each a double-quoted basic string without escapes (or exactly what
  Phase 0 shows chezmoi writes on win); refuse anything else. The config is a
  regular file, not a link; `sourceDir` is absolute, canonical and holds
  `.chezmoiroot` (and `.git` on Windows); `destDir` equals canonical HOME
  (ordinal on Unix, case-insensitive and slash-normalized on Windows).
- Replace the "native-owned" gate (the binding's existence) with "a regular
  config exists" in host auto-selection and every state: doctor, setup-host,
  `lib/bootstrap/{checks,platform,steps-human}.sh`, `lib/bootstrap.ps1`.
- Readers at `3cb223e` (re-derive with `git grep -n -E
  'config/dotfiles/native|dotfiles-chezmoi-v1|dotfiles_native_(owned|source)|NativeBinding|NativeOwned|BootstrapNative(State|Ready)|bootstrap_native_(home|state|ready)'`):
  `home/dot_profile`, `home/dot_aliases`, `home/Documents/PowerShell/profile.ps1`
  (login hook and `sync-payloads`), `lib/chezmoi-guard.*`,
  `scripts/chezmoi-update.*`, `doctor.*`, `setup-host.*` (setup-host.ps1: the
  HW-native done check through `Test-BootstrapNativeReady` and its "establish
  the home binding" HUMAN line), `lib/bootstrap.ps1`,
  `lib/bootstrap/{checks,platform,steps-human}.sh`, AGENTS.md, five docs and
  sixteen test files. After R3, `git grep -n -i -w -E
  'binding|bound|unbound|unmarked'` finds prose that describes the binding
  without naming it (README.md, `tests/e2e/run.ps1`, both skills,
  `tests/COVERAGE.md`); rewrite every hit about it.

## Entry gate

- `git fetch origin`; origin/main includes `3cb223e` (the Stage 6 record) and
  this plan's corrections; its exact-SHA CI is green.
- Every host is at `55a7960` or a descendant whose difference from origin/main
  touches only `docs/` (Stage 6's records are docs-only, and hosts update only
  at an interactive login). Record each host's HEAD.
- No maintenance marker, no `Dotfiles-*` scheduled task on win, no Stage 6
  worktree or `ci/**`/`e2e-ci/**` branch.
- Lab's canonical checkout may lag origin/main: read every file from the
  coordinator worktree at origin/main or with `git show origin/main:<path>`.
  A host checkout, Lab's included, advances only through `chezmoi update
  --apply` (the login updater or the explicit full-argument command); never run
  `git pull`, `merge` or `update-ref` on one. Landing pushes to origin only.
- Keep the canonical checkout clean. `.claude/settings.local.json` is not
  ignored there: ask the user to answer permission prompts with a one-time yes
  until R5 ignores it; if the file appears anyway, move it to the private copy
  (Phase 0 step 5) and tell the user. Never create `.claude/worktrees/` there:
  every worktree goes under `.worktrees/`.

## Phase 0: read-only inventory and baselines

1. Repository. Before anything else, union the scan of
   [Zero-trace acceptance](#zero-trace-acceptance) with the `RETIRED` regex of
   `tests/test_repository_text.py`, and copy that file's `Kept(...)` entries
   with `NEGATIVE` into the private inventory as negative assertions to delete
   or rewrite. Run the union with `git grep -I -i -P`, including file and
   directory names. Classify every hit by the from-scratch test as delete,
   rewrite or keep. Write a frozen old-to-new map for every identifier, step
   ID, hook ID, file name and doc anchor with native, handover or takeover
   (including `native_handover`, `Invoke-NativeHandover`, `native_cz`,
   `Invoke-NativeCz`, the e2e `native-*` step IDs and the `chezmoi-native`
   hook). Read status.md's Stage 6 "Host traces left for Stage 7", "Findings
   not fixed in Stage 6", "Unfinished gates" and "Coordinator rulings": traces
   there join the inventory, the rest go to `docs/hosts.md` known limits.
2. Hosts, metadata only. Start from status.md's per-host list, then sweep each
   host for anything it misses: `~/.local/state/dotfiles*`, win's
   `~\.config\dotfiles-*`, `%LOCALAPPDATA%\dotfiles` and
   `~\.config\chezmoi\stage5-reinit\`, empty directories in the checkout
   outside `.git` (`find -type d -empty`; git never lists them), `[submodule
   "..."]` sections in `.git/config`, every store under
   `retired/git-modules/` (wsl holds 8, 3 of them orphans), stale
   `origin/ci/*` and `origin/e2e-ci/*` refs, a kit 0.6 install on win
   (`%LOCALAPPDATA%\coding-agent-kit\`, `~\.claude\coding-agent-kit\`), and the
   user's migration artifacts in `/tmp` and `$TMPDIR` (Lab alone holds about
   1,050 `chezmoi*`, `dotfiles*` and `stage*` entries there, about 800
   world-readable, including snapshot tars). Read every live Codex
   `config.toml` for the S7-5 paths privately, logging key names only.
3. The one Phase 0 write: `chmod -R go-rwx` the user's own world-readable
   migration artifacts found in step 2 on every host. It is non-destructive;
   deletion waits for S7-7.
4. Baselines per host, recording the probe method to reuse unchanged later:
   HEAD; `chezmoi managed` count; each Unix host's kit version
   (`codex-as --version`); doctor rows as TSV (mac after `. /etc/profile;
   . ~/.profile`, Marlowe inside the micromamba login env, win inside a
   limited-token task); both AI configs equal to rendered (equal/not equal);
   `DOTFILES_AUTO_UPDATE=0 bash -ic true` everywhere and
   `DOTFILES_AUTO_UPDATE=0 zsh -ic true` on Lab, WSL and mac, `zsh -n ~/.zshrc`
   on Sherlock and Marlowe (Stage 6's method); PowerShell 7 and 5.1 profile
   parse and load on win. Every interactive shell Phase 0 starts on a remote
   host sets `DOTFILES_AUTO_UPDATE=0`: remote shells do not inherit
   `_DOTFILES_CHECKED`, so they would run the real login update.
5. Keep a private durable copy under `~/.local/state/dotfiles-stage7/` on Lab
   (mode 0700): this plan, the prompt, status.md, takeover.md,
   fleet-rollout.md, secrets-and-ssh.md, support-boundary.md, the inventory, the
   rename map and the baselines. R7 deletes the originals before Phase H2; the
   copy is deleted last.
6. Ask the decision batch.

### Known repository traces at `3cb223e`

A broad pattern hit 74 tracked files (603 lines) outside
`docs/chezmoi-migration/` at `55a7960`; many hits are allowed text, and
`native`/`handover` alone hit about 2,300 lines, mostly identifiers for S7-4's
map. Re-derive at your base.

- Tests to delete wholly or in part: the retired-name part of
  `tests/test_repository_text.py` and its hook (keep the link check, renamed);
  the Stow-conversion cases of `tests/test_chezmoi_takeover_recovery.py` and
  the runners `tests/chezmoi-takeover.sh` and `.ps1` (no runner or hook calls
  them); retired-flag and sourced-call cases in `tests/payload-update.sh` and
  `.ps1`; Stow and venv audits in `tests/e2e/` and `tests/e2e-harness.{sh,ps1}`
  (in e2e, "handover" names the current fresh-home flow, which S7-4 renames,
  not an audit); the previous-template upgrade case in
  `tests/test_chezmoi_update_config.py`; the stray-database checks (S7-3);
  binding-format cases (S7-2); the paste-safety loop in `tests/bootstrap.ps1`
  with no line left to check; the kit 0.6 clauses in
  `tests/test_ai_integration.py` and `tests/claude-customizations.cjs`; the
  negative assertions from step 1; their rows in `tests/COVERAGE.md` and
  `docs/testing.md`.
- Tests to keep and rename (R4): `tests/test_chezmoi_takeover_unix.py` and
  `tests/test_chezmoi_takeover_windows.py` are the suites for the login
  updaters and the Windows exact-exe trust check; the missing-parent
  preparation cases of the recovery suite stay. Keep new names inside the
  `test_chezmoi*.py` prefix that `tests/chezmoi.sh`, `tests/chezmoi.ps1` and
  the pre-commit regex discover, and update `tests/test-entrypoints.sh`.
- Compatibility code and deprecated-option handling: the payload flags and the
  sourced-call handling (D-5 row); the Codex `retired` list (S7-5); the binding
  (S7-2); the stray-database warning (S7-3); takeover and recovery pointers in
  `doctor.*`, `lib/bootstrap/checks.sh`, `lib/bootstrap/steps-human.sh` and
  `setup-host.ps1`; the retired-checkout comment in the PowerShell profile; the
  p10k instant-prompt branch in `lib/terminal.sh` that no login caller uses;
  doctor and payload advice for an unbound home; the kit 0.6 spelling in
  `home/dot_oh-my-zsh/custom/fzf-tab.zsh` (switch `--account-info` to `--info`
  once Phase 0 shows every Unix host on kit 0.7 or later).
- `home/.chezmoi.toml.tmpl`: four `native` strings (two comments, two error
  messages). Any byte change to this file makes every host warn "config file
  template has changed" until a re-init, so put every change to it in one
  commit and re-init in H2.
- Repository configuration: the `.gitignore` residue block (`/.venv-sync/`, the
  four retired checkout lines and their comments); `.gitleaks.toml` comments and
  `description` strings; the retired-name hook, selectors and excludes in
  `.pre-commit-config.yaml`.
- Docs: `README.md` (Stow homes, `bf99958`, takeover, leftover checkouts, the
  kit 0.6 helper sentence), `AGENTS.md` (D11, `bf99958`, the residue-line and
  retired-name-test rules, the retired Sherlock checkout and old Sherlock link
  rules, "existing 0.6 copies still run", "native" contrasts),
  `docs/bootstrap.md`, `docs/payloads.md` (Migration, Leftover checkouts, the
  0.6 sentences), `docs/config-sync.md`, `docs/update-contract.md`,
  `docs/testing.md`, `docs/shell.md`, `docs/dependencies.md`,
  `tests/COVERAGE.md`, both mirrored `dotfiles-bootstrap` skills, and
  `docs/chezmoi-migration/**` (S7-1).

### Known host traces

The authoritative per-host list is status.md "Host traces left for Stage 7"
(`3cb223e`), extended by the Phase 0 sweep. In summary:

- In each checkout: empty old-layout directories (Lab
  `lab-ubuntu/fcitx5/.config/fcitx5/conf`; mac `win/wezterm`, `fedora/bash`,
  `fedora/zsh`, `ubuntu/bash`, `ubuntu/zsh`) and the `[submodule "..."]`
  sections in `.git/config` (status.md counts keys, not sections: Lab 4 keys
  in 2 sections, WSL 8, mac 6, Sherlock 6, Marlowe 2, win 6). No checkout
  holds a retired checkout or `.venv-sync`.
- Payload state: `~/.local/state/dotfiles/` on the five Unix hosts (only
  `payload/` with old `*.stamp`, `skills.failed` and `payload.log`); win's
  `%LOCALAPPDATA%\dotfiles\` (only an empty `payload\`).
- win, if Phase 0 finds it: the kit 0.6 install
  `%LOCALAPPDATA%\coding-agent-kit\` and its helper copies in
  `~\.claude\coding-agent-kit\`.
- Stage 6 evidence: `~/.local/state/dotfiles-stage6/` on each Unix host, with
  `rollout-20261107/retired/` (the moved checkouts and `git-modules/` stores)
  and `residue/` (moved `.venv-sync`, receipts, wrapper links); win
  `~\.config\dotfiles-stage6-task\` (with `rollout\retired\` and
  `rollout\residue\`).
- Earlier evidence: every `~/.local/state/dotfiles-stage4-*`,
  `dotfiles-stage5-*`, `dotfiles-consolidation-*` and `dotfiles-cleanup`
  entry; Lab's `dotfiles-chezmoi-migration-recovery` (the pre-takeover
  recovery store); Marlowe's `dotfiles-marlowe-runtime-dryrun-*` and
  `dotfiles-marlowe-tmux-*`; win `~\.config\dotfiles-stage5-task\` and
  `~\.config\chezmoi\stage5-reinit\`.
- Migration artifacts in `/tmp` and `$TMPDIR` (Phase 0 step 2).
- After S7-2 (a) is live on a host: `~/.config/dotfiles/native`.
- Git metadata: stale `origin/ci/*` and `origin/e2e-ci/*` refs; the login
  updater's pull fetches every branch and never prunes.
- The controller only under S7-8 (b); Stage 7's own private copy, last.

Prove the moved copies and stores before S7-7 lists them; status.md's readings
are not proof. Enumerate every store under `retired/git-modules/` (each
directory with `HEAD` and `objects/`). Run every git call as `git
--no-optional-locks --git-dir=<store> --work-tree=<W>`, W being the copy under
`retired/common/...` or, for an orphan store, an empty scratch directory: the
moved gitfiles and the stores' relative `core.worktree` no longer resolve, and
any unexpected exit status counts as unproven. For each store,
`rev-parse -q --verify refs/stash` exits exactly 1 and `rev-list HEAD
--branches --not --remotes` exits 0 and prints nothing. For each copy, with a
private index T (an absolute path outside the store and the evidence, deleted
afterwards) passed as `GIT_INDEX_FILE` to every call, against a published
commit C: `read-tree C` exits 0, `update-index -q --refresh` (writes only T),
`diff-files --quiet` exits 0, and `ls-files --others` lists nothing but named
caches (`__pycache__`, `.DS_Store`); never use `status` for this. C is the
store's HEAD, except for mac's and Sherlock's `common/codex/coding-agent-kit`,
which shares the store and HEAD `9bba5a6` of
`common/coding-agent-kit/coding-agent-kit`: try `38333d6`, then `a10009e`, the
only gitlinks dotfiles recorded at that path, never `9bba5a6`. A failing store
or copy goes into the S7-7 question with its differing path names only.

On each host, before the first S7-7 deletion there (any evidence, snapshot,
temporary artifact or Lab's recovery store, whatever its name), confirm once,
by exit status only, that chezmoi on that host decrypts with its live identity,
and ask the user, with the S7-7 list, to confirm that the offline identity
recovery copy exists. Never read or print what those directories hold.

## Ordered work

### Phase H1: tidy the host checkouts and payload state

Before the landing, one owner per host (win: one limited-token task):

- `rmdir` the empty old-layout directories, deepest first.
- `git config --remove-section` each section that `git config --get-regexp
  '^submodule\.'` names, until that command prints nothing.
- Delete the exact payload files, then `rmdir ~/.local/state/dotfiles/payload`
  and `~/.local/state/dotfiles`; on win `Remove-Item -LiteralPath` (no
  `-Recurse`) the empty `%LOCALAPPDATA%\dotfiles\payload`, then
  `%LOCALAPPDATA%\dotfiles`.
- win, if Phase 0 found the kit 0.6 install: run `pwsh -NoProfile -File
  "$env:LOCALAPPDATA\coding-agent-kit\install.ps1" -Uninstall -Purge`; if
  `install.ps1` is missing, record a file listing and `Remove-Item -Recurse
  -LiteralPath` the two directories (native Windows missing helpers exit 0).
  A Unix host below kit 0.7: `sync-payloads kit`.
- Recheck that `git status --porcelain --ignored` in each checkout lists
  nothing the residue lines match.

These hold no private data and need no snapshot.

### Phase R: repository commits

Each commit: tests first (RED, then GREEN where behavior changes), focused
suites, `tests/run.sh --ci`, `pre-commit run --all-files`, a conventional
message without AI attribution, explicit `git add <paths>`. Suggested order:

- **R1 `test: drop the migration-only tests`**: the deletions listed above;
  keep the Markdown link check, renamed (for example
  `tests/test_markdown_links.py`).
- **R2 `refactor!: drop compatibility and retired-option handling`**: the
  compatibility items listed above, with every caller and doc in the same
  commit.
- **R3 `refactor!: locate the source through the chezmoi config`** (S7-2 (a)),
  with tests for the lookup and its refusals, and the doctor and setup-host
  states. No code that reads, migrates or warns about the old binding.
- **R4 `refactor: name things for the current design`**: the frozen map
  (S7-4), moving each renamed path with all its references (fixtures, hook
  IDs, `tests/test-entrypoints.sh`, the e2e block policy and verdicts, docs
  fences that e2e extracts). Put every `home/.chezmoi.toml.tmpl` change of the
  stage in one commit.
- **R5 `chore: drop the residue ignore lines`**: `.gitignore` (and add
  `.claude/settings.local.json`, which is machine-local), their pin test,
  `.pre-commit-config.yaml` selectors and excludes for deleted files, and the
  `.gitleaks.toml` comments and `description` strings, keeping every matching
  value; reword without any scan term, for example "A nonsecret SHA256 in older
  commits that the generic-api-key rule flags, so a full-history scan stays
  clean".
- **R6 `docs: describe the current design`**: rewrite README.md, AGENTS.md
  (under 28,000 bytes; S7-8), docs/*, tests/COVERAGE.md and both skills
  (identical bodies) without stage numbers, decision IDs, "takeover", "no
  longer" or native-versus-legacy wording. Fold durable content into neutral
  homes:
  - `docs/bootstrap.md`: a new home by hand, the renamed `common-only` route,
    directory-only preparation of missing parents.
  - `docs/updates.md` (replaces `docs/update-contract.md`): the login updater,
    editing and adding files, merge and apply, the maintenance marker, a
    maintenance-gated rollout of a breaking change, and a reviewed re-init
    after a config-template change.
  - `docs/secrets.md` (from secrets-and-ssh.md): recipients, enrolling a
    secret or a host, identity bootstrap and recovery custody.
  - `docs/ai-config.md` (renamed `docs/config-sync.md`): ownership, policy
    rationale, reconciling an owned key.
  - `docs/hosts.md`: per-host rules that stay true: win ordinary token and
    one-off limited-token tasks, the admin SSH limits; Sherlock site rules and
    the controller (S7-8); Marlowe login env, AppArmor `block-node`, ACLs;
    the probe methods of Phase 0 step 4; known host limits.
  - `docs/dependencies.md`: the tool floors from support-boundary.md.
- **R7 `docs: remove the migration records`**: delete
  `docs/chezmoi-migration/` and every remaining reference. It is part of the
  same landing, because the kept link check scans every tracked Markdown file
  and the records link to files R4 and R6 rename or delete.

Before landing: run the tree part of the zero-trace acceptance on the
candidate and fix every unclassified hit; run the adversarial review; run
`pre-commit run --hook-stage manual gitleaks-history` from a full clone. Then
land once: push the exact candidate SHA to `ci/<name>` and `e2e-ci/<name>`,
wait for every `ci.yml` and `bootstrap-e2e` job on that SHA, and fast-forward
origin/main only after H2 step 1 confirmed every marker; delete both branches
after H2 step 4. The landed SHA is "the final main".

### Phase H2: roll out and finish the hosts

1. Put `~/.config/dotfiles/maintenance` on all six hosts, Lab included (win:
   a limited-token task), and confirm each by exit status (Unix `test -e`, win
   `Test-Path` inside a task). The `ci/**` and `e2e-ci/**` pushes may go
   first; main moves only when all six are confirmed. A host that cannot get a
   marker blocks the landing (keep main and report it), because restoring its
   access later starts an interactive login that would run the old updater
   against the new main.
2. Fast-forward origin/main to the green candidate.
3. Per host, Lab first, one owner per host:
   1. Keep the binding: the first update runs the old updater, because the
      deployed hook sources the guard and updater from the checkout before it
      pulls.
   2. Under maintenance, from the checkout, run the full-argument `chezmoi
      update --apply` with the updater's explicit arguments plus
      `--exclude=dirs --recurse-submodules=false --force=false` (win: a
      limited-token task). On a partial apply, finish with the explicit
      full-argument apply; never restore an old function or guard file.
   3. Check that HEAD is the final main and full-argument `status
      --exclude=dirs` is empty.
   4. If `home/.chezmoi.toml.tmpl` changed, re-init: pre-check a clean
      checkout at the final main, a regular config and a non-empty state; keep
      a private copy of the config, its key names and modes or ACLs (no `cp
      -p` on Marlowe); run `chezmoi init` with `--source` and `--working-tree`
      set to the checkout and the full explicit argument set, plus
      `--mode=file --no-tty --error-on-conflict --force=false --no-pager
      --use-builtin-diff`; post-check that the key diff shows only expected
      changes and plain and full-argument `status --exclude=dirs` are empty
      with empty stderr; roll back by restoring the copy. On win, a
      limited-token task (the Stage 5 `reinit-win.ps1` pattern).
   5. Delete `~/.config/dotfiles/native` (S7-2 (a)).
   6. Lift maintenance and prove the deployed hook and the new updater without
      the user: on Unix `env -u _DOTFILES_CHECKED -u DOTFILES_AUTO_UPDATE -u ENV
      sh -i -c '. "$HOME/.profile"' </dev/null` from the host's Phase 0
      context (mac after `. /etc/profile`; Sherlock and Marlowe from the login
      env with that outer shell's updater off). Require exit 0, no
      `[dotfiles]` line on stderr (sh prints its own no-TTY job-control
      notice), HEAD at the final main and a clean status. On win, a
      login-equivalent limited-token task. Lab's Claude shells inherit
      `_DOTFILES_CHECKED=1`, so a plain shell there proves nothing.
   7. Per-host acceptance with the Phase 0 methods: HEAD is the final main;
      managed count equals the baseline plus the expected delta; no doctor row
      worse than the baseline (through the S7-4 map); both AI configs equal
      rendered; the shell probes pass; PowerShell 7 and 5.1 profiles parse and
      load; no maintenance marker; no `Dotfiles-*` task. On failure, restore
      maintenance and finish by explicit commands.
4. Delete the `ci/**` and `e2e-ci/**` branches, then `git fetch --prune
   origin` in each host checkout (it moves no local branch).
5. Run the moved-copy proof and the identity check, present the S7-7 list, and
   delete exactly what the user confirms, Stage 7's own copy last; then run the
   host part of the zero-trace acceptance.

Delete only with literal paths in visible top-level commands: on Lab `rm -r --
<exact path>...`; on a Unix remote `ssh <alias> rm -r -- <exact path>...`, one
command per confirmed batch, with no `bash -c`, heredoc, variable, glob or
uploaded script; `rmdir` for directories that must be empty; on win
`Remove-Item -LiteralPath` inside a limited-token task. Claude Code's built-in
rm check prompts per batch, so run S7-7 while the user is present.

## Zero-trace acceptance

Never commit the scanner or its pattern. The tree part runs on the landing
candidate (Phase R), the host part after H2.

- Tracked tree, contents and paths, `git grep -I -i -P` (skips the pinned
  binary files), unioned with the `RETIRED` regex (Phase 0 step 1):

  ```text
  stow|legacy|retire|deprecat|stage[ -]?[0-9]|venv-sync|tomlkit|setup-sync|
  config.sync|sync-runtime|bf99958|DOTFILES_HOST|DOTFILES_DIR|receipt|takeover|
  handover|migration|pre-chezmoi|auto-stow|restow|--auto\b|--worker\b|-Auto\b|
  -Worker\b|awesome-skills-update|leftover|residue|transition|formerly|
  no longer|old[- ]layout|dotfiles-sync-|\bD-?(1[0-7]|[1-9])\b|\bD11\b|native|
  dotfiles-update|ai-sync|sync[-_ ]?(runtime|python|venv)|
  venv[-_ ]?(sync|python|violation)|migrate-portable|codex-portable|
  requirements-sync|(claude-settings|codex-config|codex-rules|fcitx5-profile|
  codex-instructions)-sync|DOTFILES_PAYLOAD_(AUTO_UPDATE|CHECKED)|
  windows-link-trust|(unix|windows)-installer|installer-contract|update-hooks|
  sherlock-kit\.md|\b0\.6\b|account-info
  ```

  plus, under S7-2 (a), `\bunbound\b|unmarked|dotfiles-chezmoi-v1|binding|\bbound\b`,
  and the old package paths
  `(?<![\w.-])(?<!\.hosts/)(common|mac|sherlock|wsl-ubuntu|lab-ubuntu|marlowe|win)/[A-Za-z._]`
  and `(?<![\w.-])(common|win)\\(?=[\w.*$])`. Every remaining hit must be
  classified keep by the from-scratch test (Not traces) and listed in the final
  report; check each `native` hit against the S7-4 map. No Markdown link may
  point at a missing file or anchor.
- Each host: none of the known host traces exist, including empty
  directories, `[submodule]` sections, stale `origin/ci*` refs and `/tmp`
  artifacts; each checkout's `git status --porcelain --ignored` lists only
  expected paths.
- A fresh clone into an empty HOME converges (init, apply, second apply with no
  changes) on Linux; CI covers macOS and Windows; bootstrap e2e covers all
  seven flows.

## Risks

- The first update after R3 runs the old updater; if its pull succeeds and its
  apply does not, the old hook meets the new guard. Handle it under
  maintenance with explicit commands (H2 step 3), never with code.
- A config-template change without a re-init leaves every host warning on
  each manual chezmoi command.
- Deleting `.gitleaks.toml` matching values would fail every later CI run.
- Deletion is irreversible, and evidence, Lab's recovery store and temporary
  artifacts may hold identity material: prove, then ask.
- Over-deletion: the updater, trust and missing-parent suites, input
  refusals and safety checks are design, not traces.
- A dirty canonical checkout (`.claude/settings.local.json`, a stray
  `.claude/worktrees/`) makes Lab's updater refuse every login.
- `tests/run.*`, CI workflows, pre-commit selectors and e2e extraction that name
  renamed or deleted files.
- AGENTS.md stays under 28,000 bytes; both skills stay identical.
- Sherlock and Marlowe site rules and the win token limits apply throughout.

## Completion

- Report to the user: the landing with its exact CI and e2e run IDs, per-host
  before and after, removed host traces, the zero-trace scan summary with every
  kept hit and its reason, and the decisions. With the records deleted, this
  report and the commit messages are the record.
- Update the agent memory entries under
  `~/.claude/projects/-home-fridrichmethod-dotfiles/memory/` that describe
  retired mechanisms as current.
- Remove every Stage 7 worktree and branch, local and remote.
