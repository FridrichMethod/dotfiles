# Behavioral test coverage

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
| `lib/config_sync.py` and sync runtime/wrappers | `test_config_sync.py`, `config-sync.sh`, `ai-config-sync.sh`, `unix-installer.sh` | Portable policy ownership; authoritative Claude arrays including deny validation; unknown live Codex fields/hooks; explicit migration; malformed/special inputs; no-write preflight; symlink replacement, atomic-failure preservation, permissions and runtime selection. |
| `common/sh/.profile`, `common/zsh/.zshrc`, `common/zsh/.oh-my-zsh/custom/nvm.zsh`, `fzf-tab.zsh` | `shell-profile.sh` | MANPATH defaults, repeated sourcing, nvm alias chains and discovery, incomplete installs/cycles, inherited NVM_BIN, nested PATH/FPATH ordering with brew/conda, guarded --no-use loading and safe colored tldr previews. |
| `lib/terminal.sh`, `lib/terminal.ps1` | `terminal.sh`, `terminal.ps1` | TTY/redirected output, explicit color controls, NO_COLOR/TERM=dumb, quiet sourcing, p10k capture replay, PowerShell streams and caller preferences. |
| `setup-sync.sh` / `setup-sync.ps1` | `test_config_sync.py`, CI setup steps | Pinned explicit provisioning, chosen interpreter, version floor, unsafe environment reuse refusal, no hidden runtime install and no mutation of linked environments. |
| `common/claude/.local/bin/claude-settings-sync` | `ai-config-sync.sh` | Portable-wins object merge and authoritative arrays, local-only fields/model preserved, malformed policy rejection, no-op and legacy links. |
| The `settings.json` commands that run the kit's Claude helpers from `~/.claude/coding-agent-kit/` | `test_ai_integration.py` (through `ai-integration.sh`), `claude-customizations.cjs` | Required helper names and events; exact configured commands in isolated spaced homes; platform-specific missing-helper behavior and present-helper exit status; installed-kit behavior optional. Upstream helper internals remain upstream tests. |
| `common/codex/.local/bin/codex-config-sync` | `codex-config-sync.sh`, `unix-installer.sh` | Portable allowlist, quoted/multiline TOML, unknown live tables and arrays, retired sandbox settings, no-op/fresh/legacy files and real --check/apply. |
| `common/codex/.local/bin/codex-rules-sync` | `ai-config-sync.sh` | Opaque authoritative rules, empty-source failure, sibling and permission preservation, prompt-only policy and cross-client global-instruction alignment. |
| `lab-ubuntu/fcitx5/.local/bin/fcitx5-profile-sync` | `fcitx5-profile-sync.sh` | Authoritative materialization, no-op inode, safe staging/replacement, permissions and directory/special-file rejection. |
| `common/tmux/`, tmux clone/probe rows | `tmux.sh`, `test_tmux.py` | matching Unix-only installation/probes; real tmux with a temporary HOME and private socket: native Mocha/copy settings without TPM, no network/bootstrap on load, layout-only recovery options and a concrete hostname directory, fake TPM loaded from the bootstrap path, idempotent conditional registration and desktop/SSH clipboard selection, native menu without autobuild, reloads and loader quoting with spaces in HOME, menu cwd quote/injection regression, private metric cache and symlink/permission refusal; skips real tmux when absent; real upstream popup/restore behavior and historical binaries require an isolated manual smoke check |
| `.stowrc` ignores, `.gitignore` | `test_stow_ignores.py`, `stow-ignores.sh`, `windows-installer.ps1` | Git/Stow 2.3/Stow 2.4/PowerShell ignore equivalence, whole components and near misses, tracked-file coverage, native fixture links and safe fixture Git isolation. |
| `stow-all.sh` | `stow-all.sh`, `unix-installer.sh` | Host refusal and common-before-host order, all-input preflight, oh-my-zsh prerequisite, dry-run conflicts before sync, exact flags, SSH modes, safe retirement and revision acknowledgement; filesystem failures remain retryable. |
| The retirement of both submodules: `.gitignore` and `.stowrc` lines for the leftover checkouts, no `.gitmodules`, no tracked symlink, the scripts/awesome-skills-update.sh shim | `unix-installer.sh`, `update-hooks.sh`, `update-hooks.ps1`, `ai-config-sync.sh`, `stow-ignores.sh` | Real local-remote update from legacy layouts, ignored leftover checkouts, exact retired links, one-login payload handoff, shim convergence and no automatic submodule commands or repository deletion. |
| `scripts/dotfiles-update.sh` | `update-hooks.sh`, `unix-installer.sh` | Clean fast-forward, dirty/diverged protection, session markers/opt-outs, explicit host selection, home/platform/host/revision-bound acknowledgement, retry without a new pull, process contention and real Git/Stow integration. |
| `scripts/payload-update.sh`, `scripts/payload-update.ps1`, `config/payloads.tsv`, the rc tails, the aliases and the profile functions | `payload-update.sh`, `payload-update.ps1`, `unix-installer.sh`, `powershell-profile.ps1`, `setup-host.sh`, `test-entrypoints.sh` | Platform/item selection, foreground install/background refresh, private staging and execution directory, success/failure/person-status/exit-75 state, six-hour backoff, bounded downloads, legacy-link refusal and manual triggers. See the payload contract and focused fixtures for backend-specific cases. |
| `stow-all.ps1`, `lib/windows-link-trust.ps1` | `windows-installer.sh`, `windows-installer.ps1`, `windows-installer-controls.ps1` | Native target/allowlist, no-folding links, safe adoption/backups, exact legacy cleanup, RedirectionGuard subprocess, elevated repair, strict/incomplete state, preview and one confirmation for a complete file operation. |
| `scripts/dotfiles-update.ps1`, `scripts/dotfiles-auto-stow.ps1` and the profile's update-hook tail | `update-hooks.ps1`, `update-hooks.sh` | Fast-forward/host/receipt parity, dirty protection, shared lock, explicit elevated worker, safe task dispatch and failed/no-ack retries. Mock dispatch is not Task Scheduler execution evidence. |
| `win/powershell/**/profile.ps1`, `win/oh-my-posh/**` | `powershell-profile.ps1`, `powershell-profile.sh` | Interactive/agent guards, quiet script loads, lazy conda recursion safety/completion, UTF-8 behavior, optional tools, key/prompt order, LASTEXITCODE, history filtering and tagged theme render checks. |
| `lib/bootstrap/manifest.sh`, `platform.sh`, `version.sh` and `config/bootstrap/` | `bootstrap-manifest.sh`, `test_bootstrap_manifest.py` | Manifest schema, host/tier/probe coverage, SHA256/default-branch contracts, no machine-home paths, docs step/tool-ID parity, mirrored skill bodies and AGENTS byte budget. |
| `doctor.sh`, `lib/bootstrap/checks.sh` | `doctor.sh` | Offline/write-free probes including stateful gh/tldr fakes and real tools in an empty home; version/TSV/status contracts, explicit sync runtime, platform/host/common-only selection, structural checks and opt-in auth/smoke. |
| `setup-host.sh`, `lib/bootstrap/fetch.sh`, `lib/bootstrap/steps*.sh` | `setup-host.sh` | Ordering/idempotence, zero-write checks, provider-aware bundles and declared conflicts, no privileged hidden operations, digest gates, immutable existing clones, trusted nvm bootstrap, explicit sync interpreter and receipt-plus-link stow readiness; partial/wrong-home/host/revision installs remain pending. |
| `doctor.ps1`, `setup-host.ps1`, `lib/bootstrap.ps1` | `bootstrap.ps1`, `bootstrap-windows.sh` | Native PowerShell parser/runtime/provider parity, explicit runtime failures, no-write check modes, receipt-bound readiness and Windows HUMAN blocks. Require native Windows execution before claiming that platform validated. |
| Portable mac/Ubuntu/Sherlock/Marlowe profiles, rc files and common aliases | `host-overlays.sh`, `test_portable_shell.py` | Isolated Bash/zsh: portable HOME paths and failed-hook alias quoting, native vi fallback, Juliaup idempotence, macOS Homebrew/nvm order, Ubuntu shared/home/custom-PATH brew discovery, and durable Marlowe Cargo. No live site policy or real installer execution. |
| `tests/e2e/inside.sh`, `tests/e2e/lib/*.sh` (`blocks.sh` policy, `assert.sh` snapshots and audits), `tests/e2e/hosts/*.env` | `e2e-harness.sh` | HUMAN-block parser/policy, digest and stow-line restrictions, snapshots/audits, timeout propagation, sandbox refusals and dry-run apply flows. Real Docker bootstrap remains opt-in. |
| `tests/e2e/run.ps1`, `tests/e2e/lib/*.ps1` | `e2e-harness.ps1`, `e2e-harness-windows.sh`, `tests/run.ps1` parse gate | PowerShell HUMAN-block policy, exact stow invocation, no-write snapshots, process limits, apply-loop state and refusal cases; real winget/runner-home setup remains opt-in. |
| `.stowrc`, `common/(claude\|codex)/**`, `fzf-tab.zsh`, `.zsh_aliases`, `.bash_aliases`, and the real `settings.json` against an installed coding-agent-kit | `ai-integration.sh`, `test_ai_integration.py`, `tests/run.ps1` | Public account-preview and alias wiring against credential-free installed kit paths, optional real fzf-tab PTY behavior, configured Claude commands and native Windows wiring-only behavior. No credential/session data is copied. |
| `tests/run.sh`, `tests/run.ps1`, the suites' fixture Git, `.pre-commit-config.yaml` and CI | `test-entrypoints.sh`, three native CI jobs | Visible prerequisite failure and optional skips, tests/lib/environment prefix isolation with explicit fixture/runtime exceptions, real linked-worktree parent HEAD/index/core.bare preservation, hook file selection and one complete intended behavior pass per platform. Installed-kit variables/helpers outside the public dotfiles contract are not owned here. |
| Sherlock migration in `stow-all.sh` and `stow-all.ps1` | `stow-all.sh`, `unix-installer.sh`, `windows-installer-controls.ps1`, `windows-installer.ps1` | Exact dangling historical links, foreign/manual entries and loops preserved, generated regular override retired only after Stow, special files never read, repeated convergence, Windows preview/decline and ignored checkout retention. |

Windows updater mocks do not establish real Task Scheduler execution. Native
NTFS fixtures use a local runner token, not OpenSSH network-logon trust. Desktop
notification delivery requires an interactive terminal; container/hosted-runner
success does not establish fresh-machine or real-cluster acceptance.

Interactive presentation helpers and network-transfer aliases remain outside
this automation matrix. Add a focused test when promoting one to a supported
automation contract. No line-coverage percentage substitutes for these checks.
