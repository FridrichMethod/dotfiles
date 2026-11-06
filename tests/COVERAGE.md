# Behavioral test coverage

The Stage 1-3 `tests/chezmoi.sh` / `.ps1` suite runs real v2.74.0 in disposable
homes: regular/private deployment, explicit-path isolation, drift refusal,
preview, owned-link takeover, native JSON/TOML modifies and synthetic builtin-age
success/failure. `test_chezmoi*.py` parses rendered output without a merge runtime
on child PATH. Native macOS/Windows execution and Windows ACLs need their own
evidence; the CI workflow provisions the binary in all three jobs. See the
[migration record](../docs/chezmoi-migration/status.md) for actual results.

Stage 2 `test_chezmoi_source_state.py` checks the 95-row inventory against the
Git index, all seven exact ordinary-file sets, byte parity, native attributes,
unmanaged siblings, unchanged source and repeat apply. It separately labels
supplemental OS-data rendering. Linked-worktree/space paths, explicit host/init,
the minimum version, binary and empty files, and CRLF are covered.
`test_chezmoi_rendered.py` parses/lints applied output; canonical legacy lint and
behavior suites remain active while the temporary include bridge exists.

Stage 3 adds `test_chezmoi_claude.py`, `test_chezmoi_codex.py` and independent
`test_chezmoi_integration.py`: exact portable ownership, authoritative arrays,
local/unknown state, JSON numeric tokens and Unicode refusal, typed metadata
against a frozen list and the portable TOML, recursive local-temporal refusal,
offset timestamps, literal paths, CRLF multiline strings, malformed input and
destructive ancestor conflicts.
Complete candidate sets add exactly two private AI targets per role. Rendered
TOML/JSON is parsed, literal canonical inputs stay read-only, and the native
path runs with empty child PATH and no sync environment. Parser exclusions name
only the exact modify templates; portable/data files retain their parser hooks.

Stage 5 adds `test_chezmoi_update_config.py` cases for the owned
`persistentState` (derived from the destination in slash form, case variants
folded, duplicates refused, a previous-template config gaining only that key,
a plain command sharing the bound database while the updater's flag wins);
`test_chezmoi_source_state.py` guards against chezmoi externals, `.gitmodules`
and gitlinks; `test_chezmoi_provision.py` reads a native home's role as the
doctor and setup-host do, against chezmoi init's real rendering; and
Windows-only `test_chezmoi_takeover_windows.py` cases pin the login updater to
a private `~/.local/bin/chezmoi.exe` (no PATH fallback; a missing exe, a
foreign owner or writer, a link or a junctioned parent refused with one
warning; the check lives in the guard, which Windows PowerShell 5.1 loads, and
its unit case also refuses a null DACL and object, compound and custom ACEs in
in-memory descriptors) and record that NTFS refuses renaming its parents while
the updater's handle is open.

`./tests/run.sh` is the Unix entry point; `./tests/run.ps1` is the PowerShell
entry point. CI requires `--ci` on Unix and `-CI` on native Windows. Provision
the pinned parser with `setup-sync.sh` / `setup-sync.ps1` first. The pre-commit
hooks run the same focused Unix tests when their production sources change.

The launcher, configuration and Claude helper suites live in
coding-agent-kit and run there on the kit's own fixtures. This repository
keeps the AI-sync engine suites and its own public content/wiring checks;
the cases that run the kit reach it through an installed kit
(`DOTFILES_TEST_KIT_HOME`, which the "Install the real coding-agent-kit" step
of CI's Unix jobs sets; the kit installs nothing on native Windows) and skip
without one.

Shell line-coverage is not used as a hard gate: these programs mix sourced
POSIX shell, Bash, Python, Node, child processes, and PowerShell, for
which one percentage would omit meaningful branches. Coverage is tracked as a
source-to-test behavior matrix instead.

The matrix lists coverage boundaries, not a duplicate inventory of every
assertion. [Testing documentation](../docs/testing.md) explains execution and
platform limits; the named focused suites contain the executable regressions.

| Production target | Test | Covered behavior |
| --- | --- | --- |
| `lib/config_sync.py` and sync runtime/wrappers | `test_config_sync.py`, `config-sync.sh`, `ai-config-sync.sh` | Portable policy ownership; authoritative Claude arrays including deny validation; unknown live Codex fields/hooks; explicit migration; malformed/special inputs; no-write preflight; symlink replacement, atomic-failure preservation, permissions and runtime selection. |
| `common/sh/.profile`, `common/zsh/.zshrc`, `common/zsh/.oh-my-zsh/custom/nvm.zsh`, `fzf-tab.zsh`, the `sync-payloads`/`sync-skills` aliases | `shell-profile.sh`, `test_chezmoi_guard.py` | MANPATH defaults, repeated sourcing, nvm alias chains and discovery, incomplete installs/cycles, inherited NVM_BIN, nested PATH/FPATH ordering with brew/conda, guarded --no-use loading and safe colored tldr previews; sync commands that run a valid native binding's hook, or an unmarked home's `DOTFILES_DIR` one, under sh/dash/bash/zsh and refuse invalid bindings and maintenance, and logins that start no payload run; an interactive login of an unmarked home (sh/dash/bash/zsh) that runs no updater, even with a checkout at ~/dotfiles, and prints nothing; a bound home's update dispatch. |
| The profile login tails (`common/sh/.profile`, `~/.zshrc`, PowerShell 7 tail) | `test_chezmoi_guard.py`, `shell-profile.sh`, `test_chezmoi_takeover_unix.py`, `test_chezmoi_takeover_windows.py`, `powershell-profile.ps1` | Maintenance first, marker validation, the bound source's updater only, no unmarked-home fallback, quiet unmarked logins, a failing updater that leaves the shell usable with caller preferences intact. |
| `lib/terminal.sh`, `lib/terminal.ps1` | `terminal.sh`, `terminal.ps1` | TTY/redirected output, explicit color controls, NO_COLOR/TERM=dumb, quiet sourcing, p10k capture replay, PowerShell streams and caller preferences; the plain fallback of doctor.ps1/setup-host.ps1 with a missing or broken library. |
| `setup-sync.sh` / `setup-sync.ps1` | `test_config_sync.py`, CI setup steps | Pinned explicit provisioning, chosen interpreter, version floor, unsafe environment reuse refusal, no hidden runtime install and no mutation of linked environments. |
| `common/claude/.local/bin/claude-settings-sync` | `ai-config-sync.sh` | Portable-wins object merge and authoritative arrays, local-only fields/model preserved, malformed policy rejection, no-op and legacy links. |
| The `settings.json` commands that run the kit's Claude helpers from `~/.claude/coding-agent-kit/` | `test_ai_integration.py` (through `ai-integration.sh`), `claude-customizations.cjs` | Required helper names and events; exact configured commands in isolated spaced homes; platform-specific missing-helper behavior and present-helper exit status; installed-kit behavior optional. Upstream helper internals remain upstream tests. |
| `common/codex/.local/bin/codex-config-sync` | `codex-config-sync.sh` | Portable allowlist, quoted/multiline TOML, unknown live tables and arrays, retired sandbox settings, no-op/fresh/legacy files and real --check/apply. |
| `common/codex/.local/bin/codex-rules-sync` | `ai-config-sync.sh` | Opaque authoritative rules, empty-source failure, sibling and permission preservation, prompt-only policy and cross-client global-instruction alignment. |
| `common/claude/.claude/settings.json`, `common/codex/.codex/rules/portable.rules`, the global `CLAUDE.md` and `AGENTS.md`, the root `CLAUDE.md` stub | `test_ai_policy.py` (through `ai-policy.sh` and `tests/run.ps1`), `test_chezmoi_claude.py`, `test_chezmoi_source_state.py` | Exact Claude allow set and the AGENTS.md ask/deny tiers, `defaultMode` auto, `classifyAllShell` and literal `$defaults`, `effortLevel`, cleared plugin hooks, empty attribution, both agents-md plugin IDs and no portable `model`, each with a mutation case; a stale host file rendered natively to that policy; prompt-only Codex rules without host paths or routine commands and with every guardrail; guides that differ only in the destructive-action bullets and share one version-free Sherlock section; the `@AGENTS.md` stub; no role managing the kit launchers or helpers; optional installed-Codex exec-policy decisions. |
| `lab-ubuntu/fcitx5/.local/bin/fcitx5-profile-sync` | `fcitx5-profile-sync.sh` | Authoritative materialization, no-op inode, safe staging/replacement, permissions and directory/special-file rejection. |
| `common/tmux/`, tmux clone/probe rows | `tmux.sh`, `test_tmux.py` | matching Unix-only installation/probes; the `tools.tsv` floor 3.4 and no `#{version}` or `tmux -V` gate; real tmux with a temporary HOME and private socket: native Mocha/copy settings without TPM, no network/bootstrap on load, layout-only recovery options and a concrete hostname directory, fake TPM loaded from the bootstrap path, unconditional which-key/Catppuccin/FloaX registration and popup/menu styles, FloaX keys only with its script, idempotent conditional registration and desktop/SSH clipboard selection from the session environment (extrakto's OSC 52 on for a session-only SSH client, off after a session removal of a server-global `SSH_CONNECTION`), native menu without autobuild, reloads and loader quoting with spaces in HOME, menu cwd quote/injection regression, private metric cache and symlink/permission refusal; skips real tmux when absent or below 3.4 (unsupported) and fails instead under `DOTFILES_TEST_REQUIRE_TMUX=1`, which Linux CI sets with apt's 3.4; real upstream popup/restore behavior requires an isolated manual smoke check |
| The retirement of both submodules: the `.gitignore` lines for the leftover checkouts and `/.venv-sync/`, no `.gitmodules` or gitlink, the no-op scripts/awesome-skills-update.sh shim | `test_chezmoi_source_state.py`, `payload-update.sh` | Residue guard lines kept until Phase C, no submodule or gitlink, and a shim that does nothing. |
| `scripts/payload-update.sh`, `scripts/payload-update.ps1`, `config/payloads.tsv`, the rc tails, the aliases and the profile functions | `payload-update.sh`, `payload-update.ps1`, `test_payload_download.py`, `test_chezmoi_guard.py`, `shell-profile.sh`, `powershell-profile.ps1`, `setup-host.sh`, `test-entrypoints.sh` | Explicit foreground runs only: silent transition no-ops (sourced, no mode, the retired auto/worker modes, the shim) that change no shell option or trap, no login caller, `--now` returning only after its installers; platform/item selection and update rows; failure, exit-75 and person-status wording with no state kept; bounded downloads and the failed-download latch, private staging and execution directory, legacy-link refusal, and sync commands bound to the validated native source. See the payload contract and focused fixtures for backend-specific cases. |
| `win/powershell/**/profile.ps1`, `win/oh-my-posh/**`, `win/terminal/**/settings.json`, the parse-gated PowerShell entry points and libraries | `powershell-profile.ps1`, `powershell-profile.sh` | Interactive/agent guards, quiet script loads, no payload hook at login, sync commands bound to the native source with their exit status passed through (linked markers, a source without its guard and a missing hook refused with exit 1), lazy conda recursion safety/completion, UTF-8 behavior, optional tools, key/prompt order, LASTEXITCODE, history filtering and tagged theme render checks; Windows Terminal settings as strict ASCII JSON with hidden built-in stubs and PowerShell 7 never disabled (no pwsh needed); with pwsh, one parse of `doctor.ps1`, `setup-host.ps1`, `lib/chezmoi-guard.ps1`, `lib/terminal.ps1`, `scripts/chezmoi-update.ps1`, `scripts/payload-update.ps1`, `tests/run.ps1` and `tests/terminal.ps1`. |
| `lib/bootstrap/manifest.sh`, `platform.sh`, `version.sh`, `config/bootstrap/` and the setup-host step lists | `bootstrap-manifest.sh`, `test_bootstrap_manifest.py` | Manifest schema, host/tier/probe coverage, SHA256/default-branch contracts, no machine-home paths, docs step/tool-ID parity, `STEPS_REGISTRY` and both `setup-host.ps1` modes naming only contract step ids, mirrored skill bodies and AGENTS byte budget. |
| `doctor.sh`, `lib/bootstrap/checks.sh`, the native host reader in `lib/bootstrap/platform.sh` | `doctor.sh`, `test_chezmoi_provision.py` | Offline/write-free probes including stateful gh/tldr fakes and real tools in an empty home; every fixture case in the native default on a home bound to the fixture checkout: version/TSV/status contracts, platform/host/common-only selection, a native home's role from `[data].host` (`DOTFILES_HOST` ignored; unclear configs and unmarked homes without `--host` exit 2), the retired `--legacy-stow` refused, `native-config` causes (another checkout's binding and a kept stray state database warn), payload advice that names a native home's bound source, never this checkout, no submodule row, structural checks and opt-in auth/smoke. |
| `setup-host.sh`, `lib/bootstrap/fetch.sh`, `lib/bootstrap/steps*.sh` | `setup-host.sh`, `test_chezmoi_provision.py` | Native mode for every case: each host's exact step order, the retired `--legacy-stow` refused and `DOTFILES_HOST` ignored, ordering/idempotence of a full apply that installs a pinned chezmoi and ends at H7-native (done, exit 0, once the home is bound), zero-write `--check`, `--list` and `--print-manual` on debian, mac and hpc, provider-aware bundles and declared conflicts, no privileged hidden operations, digest gates, immutable existing clones, trusted nvm bootstrap, HUMAN text without Stow, `--host` over `[data].host`, H2-alloc satisfied by an existing login env and a native hpc apply, an H7-payloads line that runs the bound source's hook. S6-nerd-font accepts a system font. |
| `doctor.ps1`, `setup-host.ps1`, `lib/bootstrap.ps1` | `bootstrap.ps1`, `bootstrap-windows.sh` | Native mode for every case: PowerShell parser/provider parity, no `-LegacyStow` parameter, the healthy, failing and -Online doctor on a bound home, no-write check modes, the native plan order, paste-safe HUMAN blocks, a full apply that ends at HW-native (done, exit 0, once bound); the native doctor and HW-native (gh telemetry off, `native-config` causes, junction or symlink checkouts), native HUMAN text without Stow, W1-chezmoi hashing and extracting through one handle into an exe with a protected DACL (asserted on Windows only), refusing a linked `.local`, and, on Windows, `native-config` `human` and W1-chezmoi todo for a `~/.local/bin/chezmoi.exe` the login updater refuses. Require native Windows execution before claiming that platform validated. |
| Portable mac/Ubuntu/Sherlock/Marlowe profiles, rc files and common aliases | `host-overlays.sh`, `test_portable_shell.py` | Isolated Bash/zsh: portable HOME paths and failed-hook alias quoting, native vi fallback, Juliaup idempotence, macOS Homebrew/nvm order, Ubuntu shared/home/custom-PATH brew discovery, and durable Marlowe Cargo. No live site policy or real installer execution. |
| `tests/e2e/inside.sh`, `tests/e2e/lib/*.sh` (`blocks.sh` policy, `assert.sh` snapshots and audits), `tests/e2e/hosts/*.env` | `e2e-harness.sh` | HUMAN-block parser/policy (H7-native handover end state, loop verdicts), digest-gate restrictions, the by-hand helpers and Fresh home by hand functions extracted from docs/bootstrap.md and run against a stub chezmoi (argument set, order, refusals, kept copies, binding bytes), snapshots/audits (wrappers, sudo.log, clone links, a stow on the login PATH, `.venv-sync`), timeout propagation, sandbox refusals and dry-run native flows. Real Docker bootstrap remains opt-in. |
| `tests/e2e/run.ps1`, `tests/e2e/lib/*.ps1` | `e2e-harness.ps1`, `e2e-harness-windows.sh`, `tests/run.ps1` parse gate | PowerShell HUMAN-block policy (HW-native handover end state, loop verdicts), the extracted Fresh Windows home by hand functions (parse and shape only; executed in bootstrap-e2e), no-write snapshots, process limits, apply-loop state, handover/check-done/converged verdicts, task-identity and `.venv-sync` audits and refusal cases; real winget/runner-home setup remains opt-in. |
| `common/(claude\|codex)/**`, `fzf-tab.zsh`, `.zsh_aliases`, `.bash_aliases`, and the real `settings.json` against an installed coding-agent-kit | `ai-integration.sh`, `test_ai_integration.py`, `tests/run.ps1` | Public account-preview and alias wiring against credential-free installed kit paths, optional real fzf-tab PTY behavior, configured Claude commands and native Windows wiring-only behavior. No credential/session data is copied. |
| `tests/run.sh`, `tests/run.ps1`, the suites' fixture Git, `.pre-commit-config.yaml` and CI | `test-entrypoints.sh`, three native CI jobs | Visible prerequisite failure and optional skips, tests/lib/environment prefix isolation with explicit fixture/runtime exceptions, real linked-worktree parent HEAD/index/core.bare preservation, hook file selection with each hook's required inputs and one complete intended behavior pass per platform. Installed-kit variables/helpers outside the public dotfiles contract are not owned here. |

Native NTFS fixtures use a local runner token, not OpenSSH network-logon
trust. The held-handle rename fixture shows the rename refusal; that narrows,
but does not close, the window in which a writer of `~/.local` could swap its
`chezmoi.exe`. Desktop notification delivery requires an interactive
terminal; container/hosted-runner success does not establish fresh-machine
or real-cluster acceptance.

Interactive presentation helpers and network-transfer aliases remain outside
this automation matrix. Add a focused test when promoting one to a supported
automation contract. No line-coverage percentage substitutes for these checks.
