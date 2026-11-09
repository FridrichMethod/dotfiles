# Behavioral test coverage

The `tests/chezmoi.sh` / `.ps1` suite runs real v2.74.0 in disposable
homes: regular/private deployment, explicit-path isolation, drift refusal,
preview, the JSON/TOML modify templates and synthetic builtin-age success/failure.
`test_chezmoi*.py` parses rendered output without a merge runtime on child PATH.
Native macOS/Windows execution and Windows ACLs need their own evidence; the CI
workflow provisions the binary in all three jobs. Real-host results are not
fixture results; [hosts](../docs/hosts.md) has how hosts are checked.

`test_chezmoi_source_state.py` checks all seven exact ordinary-file sets against
`tests/fixtures/chezmoi/targets.tsv`, byte parity, chezmoi source attributes, unmanaged
siblings, unchanged source and repeat apply. It separately labels supplemental
OS-data rendering. Linked-worktree/space paths, explicit host/init, the minimum
version, binary and empty files, and CRLF are covered.
`test_chezmoi_rendered.py` parses/lints applied output, with the shell dialect
taken from the table.

`test_chezmoi_claude.py`, `test_chezmoi_codex.py` and the independent
`test_chezmoi_integration.py` cover exact portable ownership, authoritative
arrays, local/unknown state, JSON numeric tokens and Unicode refusal, typed
metadata against a frozen list and the portable TOML, recursive local-temporal
refusal, offset timestamps, literal paths, CRLF multiline strings, malformed
input and destructive ancestor conflicts. Complete candidate sets add exactly
two private AI targets per role. Rendered TOML/JSON is parsed, literal canonical
inputs stay read-only, and the apply runs with a child PATH of failing
interpreter poisons (Python, jq, Node, shells). Parser exclusions name only
the exact modify templates; portable/data files retain their parser hooks.

`test_chezmoi_update_config.py` covers the owned `persistentState` (derived from
the destination in slash form, case variants folded, duplicates refused, a
plain command sharing the configured state database while the updater's flag
wins);
`test_chezmoi_source_state.py` guards against chezmoi externals, `.gitmodules`
and gitlinks; `test_chezmoi_modify.py` runs fixture JSON and TOML modify
templates against fixture live files, `test_chezmoi_foundation.py` covers
regular/private deployment, explicit-path isolation and drift refusal, and
`test_chezmoi_secrets.py` the enrolled ciphertexts and builtin age; `test_chezmoi_provision.py` reads a configured home's role as
the doctor and setup-host do, and requires that `lib/chezmoi-guard.sh` accepts
chezmoi init's real rendering; and
Windows-only `test_chezmoi_update_windows.py` cases pin the login updater to a
private `~/.local/bin/chezmoi.exe` (no PATH fallback; a missing exe, a foreign
owner or writer, a link or a junctioned parent refused with one warning; the
check lives in the guard, which Windows PowerShell 5.1 and PowerShell 7 load,
whose `Get-DotfilesChezmoiPaths` accepts the real chezmoi init output there and
refuses every other config form, and its unit case
also refuses a null DACL and object, compound and custom ACEs in in-memory
descriptors) and record that NTFS refuses renaming its parents while the
updater's handle is open.

Portable PowerShell 7 cases in that same file also test all 256 ASCII
OneDrive spellings, substring boundaries and a real child's inherited
`GIT_`/`CHEZMOI_` prefix cleanup under `en-US`, `tr-TR` and `az-Latn-AZ`.
`powershell-profile.ps1` repeats synthetic secret, case-sensitive vendor and
benign-boundary history decisions in a fresh process per culture, avoiding
PowerShell's culture-blind `-match` cache. These are separate from Windows
ACL and interactive-console acceptance.

`./tests/run.sh` is the Unix entry point; `./tests/run.ps1` is the PowerShell
entry point. CI requires `--ci` on Unix and `-CI` on native Windows. The
pre-commit hooks run the same focused Unix tests when their production sources
change.

The launcher, configuration and Claude helper suites live in
coding-agent-kit and run there on the kit's own fixtures. This repository
keeps its own public content/wiring checks;
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
| `home/dot_profile`, `home/dot_zshrc`, `home/dot_oh-my-zsh/custom/nvm.zsh`, `fzf-tab.zsh`, the `sync-payloads`/`sync-skills` aliases | `shell-profile.sh`, `test_chezmoi_guard.py` | MANPATH defaults, repeated sourcing, nvm alias chains and discovery, incomplete installs/cycles, inherited NVM_BIN, nested PATH/FPATH ordering with brew/conda, guarded --no-use loading and safe colored tldr previews; the config validator `dotfiles_chezmoi_source` (the init layout accepted, every other form refused silently); sync commands that run the hook of the checkout a valid chezmoi config names under sh/dash/bash/zsh and refuse a home without a config, invalid configs and maintenance, and logins that start no payload run; an interactive login (sh/dash/bash/zsh) that runs no updater and prints nothing without a config, even with a checkout at ~/dotfiles, warns once for an invalid config and runs only the configured checkout's updater. |
| The profile login tails (`home/dot_profile`, `~/.zshrc`, PowerShell 7 tail) | `test_chezmoi_guard.py`, `shell-profile.sh`, `test_chezmoi_update_unix.py`, `test_chezmoi_update_windows.py`, `powershell-profile.ps1` | Maintenance first, config validation (a refused config warns once), the configured checkout's updater only, no fallback without a config, quiet logins without a config, a failing updater that leaves the shell usable with caller preferences intact. |
| `lib/terminal.sh`, `lib/terminal.ps1` | `terminal.sh`, `terminal.ps1` | TTY/redirected output, explicit color controls, NO_COLOR/TERM=dumb, quiet sourcing, PowerShell streams and caller preferences; the plain fallback of doctor.ps1/setup-host.ps1 with a missing or broken library. |
| The `settings.json` commands that run the kit's Claude helpers from `~/.claude/coding-agent-kit/` | `test_ai_integration.py` (through `ai-integration.sh`), `claude-customizations.cjs` | Required helper names and events; exact configured commands in isolated spaced homes; platform-specific missing-helper behavior and present-helper exit status; installed-kit behavior optional. Upstream helper internals remain upstream tests. |
| `home/.policy/claude-settings.json`, `home/dot_codex/rules/portable.rules`, the global `CLAUDE.md` and `AGENTS.md`, the root `CLAUDE.md` stub | `test_ai_policy.py` (through `ai-policy.sh` and `tests/run.ps1`), `test_chezmoi_claude.py`, `test_chezmoi_source_state.py` | Exact Claude allow set and the AGENTS.md ask/deny tiers, `defaultMode` auto, `classifyAllShell` and literal `$defaults`, `effortLevel`, cleared plugin hooks, empty attribution, both agents-md plugin IDs and no portable `model`, each with a mutation case; a stale host file rendered by the modify template to that policy; prompt-only Codex rules without host paths or routine commands and with every guardrail; guides that differ only in the destructive-action bullets and share one version-free Sherlock section; the `@AGENTS.md` stub; no role managing the kit launchers or helpers; optional installed-Codex exec-policy decisions; autoMode allow and soft_deny keep one leading literal `$defaults`, printable-ASCII prose, and every soft_deny protection (source state under `home/` and `.chezmoiroot`, `~/.claude`, `~/.codex`, `~/.ssh`, `~/.config`, `~/.local/state/chezmoi`, conda/mamba/Python environments, untracked work), with in-process mutation checks. |
| `home/dot_tmux.conf`, `home/dot_config/tmux/`, tmux clone/probe rows | `tmux.sh`, `test_tmux.py` | matching Unix-only installation/probes; a file map that names every tmux source; the `tools.tsv` floor 3.4 and no `#{version}` or `tmux -V` gate; real tmux with a temporary HOME and private socket: native Mocha/copy settings without TPM, no network/bootstrap on load, layout-only recovery options and a concrete hostname directory, fake TPM loaded from the bootstrap path, unconditional which-key/Catppuccin/FloaX registration and popup/menu styles, FloaX keys only with its script, idempotent conditional registration and desktop/SSH clipboard selection from the session environment (extrakto's OSC 52 on for a session-only SSH client, off after a session removal of a server-global `SSH_CONNECTION`), the hand-written which-key menu without autobuild, reloads and loader quoting with spaces in HOME, menu cwd quote/injection regression, private metric cache and symlink/permission refusal; skips real tmux when absent or below 3.4 (unsupported) and fails instead under `DOTFILES_TEST_REQUIRE_TMUX=1`, which Linux CI sets with apt's 3.4; real upstream popup/restore behavior requires an isolated manual smoke check |
| `.gitignore` | `test_chezmoi_source_state.py` | The checkout's own `.gitignore` hides Claude Code's machine-local `.claude/settings.local.json` at the root (a personal exclude does not count), and `.claude/settings.json` stays tracked. |
| `home/` chezmoi source, `home/.hosts/`, `home/.policy/`, `tests/fixtures/chezmoi/targets.tsv` | `test_chezmoi_source_state.py`, `test_chezmoi_rendered.py`, `test-entrypoints.sh` | Exact per-role targets, bytes, modes and convergence; regular files only (no tracked symlink or gitlink, the executable bit exactly on `executable_` sources); git-ignored leftovers under `home/` never deploy (`.chezmoiignore` mirrors `.gitignore`); only the six role templates remain and none reads the working tree; sourceDir-relative raw includes and never-deployed dot-directories (linked worktree with spaces); CRLF -text and empty files; rendered shell lint by table dialect; shellcheck/shfmt select every shell source, each variant with `types: [file]`, and never touch upstream or app bytes. |
| `scripts/payload-update.sh`, `scripts/payload-update.ps1`, `config/payloads.tsv`, the rc tails, the aliases and the profile functions | `payload-update.sh`, `payload-update.ps1`, `test_payload_download.py`, `test_chezmoi_guard.py`, `shell-profile.sh`, `powershell-profile.ps1`, `setup-host.sh`, `test-entrypoints.sh` | Explicit foreground runs only: every call without `--now`/`-Now` (no mode, a bare item or an unknown argument) a usage error with exit 2, no login caller, `--now` returning only after its installers; platform/item selection and update rows; failure, exit-75 and person-status wording with no state kept; bounded downloads and the failed-download latch, loopback HTTP readiness before the download deadline with a delayed-server regression, private staging and execution directory, only documented fields in config/payloads.tsv, retry lines that name `sync-payloads` only where it runs that hook and the hook's quoted line elsewhere, and sync commands that need the validated chezmoi config. See the payload contract and focused fixtures for backend-specific cases. |
| `home/Documents/*/profile.ps1`, `home/dot_config/oh-my-posh/**`, `home/AppData/**/settings.json`, the parse-gated PowerShell entry points and libraries | `powershell-profile.ps1`, `powershell-profile.sh` | Interactive/agent guards, quiet script loads, no payload hook at login, sync commands that follow the configured checkout with their exit status passed through (invalid and linked configs, a checkout without its guard and a missing hook refused with exit 1), lazy conda recursion safety/completion, UTF-8 behavior, optional tools, key/prompt order, LASTEXITCODE, history filtering, the 7.0 floor's `$PSStyle` and PSReadLine 2.2 guards (a static scan, the AST, a replay in a runspace without `$PSStyle` and replays against older PSReadLine stand-ins) and tagged theme render checks; Windows Terminal settings as strict ASCII JSON with hidden built-in stubs and PowerShell 7 never disabled (no pwsh needed); with pwsh, one parse of `doctor.ps1`, `setup-host.ps1`, `lib/chezmoi-guard.ps1`, `lib/terminal.ps1`, `scripts/chezmoi-update.ps1`, `scripts/payload-update.ps1`, `tests/run.ps1` and `tests/terminal.ps1`. |
| `lib/bootstrap/manifest.sh`, `platform.sh`, `version.sh`, `config/bootstrap/` and the setup-host step lists | `bootstrap-manifest.sh`, `test_bootstrap_manifest.py` | Manifest schema, host/tier/probe coverage, SHA256/default-branch contracts, no machine-home paths, docs step/tool-ID parity, `STEPS_REGISTRY` and the `setup-host.ps1` step lists naming only contract step ids, mirrored skill bodies and AGENTS byte budget. |
| `doctor.sh`, `lib/bootstrap/checks.sh`, the config host reader (`bootstrap_config_host`) in `lib/bootstrap/platform.sh` | `doctor.sh`, `test_chezmoi_provision.py` | Offline/write-free probes including stateful gh/tldr fakes and real tools in an empty home; fixture cases on a home whose chezmoi config names the fixture checkout: version/TSV/status contracts, platform/host/generic selection, a configured home's role from `[data].host` alone (unclear configs and homes without a config exit 2 without `--host`), `chezmoi-config` causes (absent, link, directory, each invalid form, no guard; a config naming another checkout warns), payload advice that names the shell-quoted hook of the checkout the config names, never this checkout, and this checkout's `--now` line wherever `sync-payloads` refuses, structural checks (rc-pollution reads only the home rc files) and opt-in auth/smoke. |
| `setup-host.sh`, `lib/bootstrap/fetch.sh`, `lib/bootstrap/steps*.sh` | `setup-host.sh`, `test_chezmoi_provision.py` | Each host's exact step order, an unknown argument refused, ordering/idempotence of a full apply that installs a pinned chezmoi and ends at H7-deploy (done, exit 0, once the home's config names this checkout), zero-write `--check`, `--list` and `--print-manual` on debian, mac and hpc, provider-aware bundles and declared conflicts, no privileged hidden operations, digest gates, immutable existing clones, trusted nvm bootstrap, `--host` over `[data].host`, H2-alloc satisfied by an existing login env and an hpc apply, an H7-payloads line that runs the hook of the checkout the config names (the block of a home without a config names no `sync-payloads`). S6-nerd-font accepts a system font. |
| `doctor.ps1`, `setup-host.ps1`, `lib/bootstrap.ps1` | `bootstrap.ps1`, `bootstrap-windows.sh` | PowerShell parser/provider parity, the exact entry-point parameters, the healthy, failing and -Online doctor on a configured home, no-write check modes, the plan order, self-contained HUMAN blocks that name no checkout path, a full apply that ends at HW-deploy (done, exit 0, once configured); the doctor and HW-deploy (gh telemetry off, `chezmoi-config` causes, the quoted `-Now` payload advice wherever `sync-payloads` refuses, junction or symlink checkouts), W1-chezmoi hashing and extracting through one handle into an exe with a protected DACL (asserted on Windows only), refusing a linked `.local`, and, on Windows, `chezmoi-config` `human` and W1-chezmoi todo for a `~/.local/bin/chezmoi.exe` the login updater refuses. Require native Windows execution before claiming that platform validated. |
| Portable macOS, Ubuntu, Sherlock and Marlowe profiles and rc files in `home/.hosts/*/`, and the shared aliases | `host-overlays.sh`, `test_portable_shell.py` | Isolated Bash/zsh: portable HOME paths and failed-hook alias quoting, native vi fallback, Juliaup idempotence, macOS Homebrew/nvm order, Ubuntu shared/home/custom-PATH brew discovery, and durable Marlowe Cargo. No live site policy or real installer execution. |
| `tests/e2e/inside.sh`, `tests/e2e/lib/*.sh` (`blocks.sh` policy, `assert.sh` snapshots and audits), `tests/e2e/hosts/*.env` | `e2e-harness.sh` | HUMAN-block parser/policy (H7-deploy end state, loop verdicts), digest-gate restrictions, the by-hand helpers and Fresh home by hand functions extracted from docs/bootstrap.md and run against a stub chezmoi whose init writes the top-level keys the config template sets (argument set, order, refusals, kept copies, the config the clone's guard accepts, a config naming another home refused before any apply), snapshots/audits (wrappers, sudo.log, clone links), timeout propagation, sandbox refusals and the sandboxed dry run. Real Docker bootstrap remains opt-in. |
| `tests/e2e/run.ps1`, `tests/e2e/lib/*.ps1`, App Installer policy/restore workers | `e2e-harness.ps1`, `e2e-harness-windows.sh`, `tests/run.ps1` parse gate | PowerShell HUMAN-block policy, no-write snapshots, process limits, apply-loop and deployment verdicts, task-identity audit and refusals; hosted App Installer preparation before initial doctor and after setup, absent-package no-op, foreign policy/pause refusal, durable ownership before partial setter failure, retained doctor exit 124, idempotent cleanup, restoration hash drift and actual driver finally execution. The policy worker also parses under native Windows PowerShell 5.1. Real winget/runner-home setup remains opt-in; hosted update scheduling is adapted, not validated. |
| `home/.policy/**`, `home/dot_claude/**`, `home/dot_codex/**`, `.claude/settings.json` `claudeMdExcludes`, `fzf-tab.zsh`, `.zsh_aliases`, `.bash_aliases`, and the real `settings.json` against an installed coding-agent-kit | `ai-integration.sh`, `test_ai_integration.py`, `tests/run.ps1` | Public account-preview and alias wiring against credential-free installed kit paths, optional real fzf-tab PTY behavior, configured Claude commands and native Windows wiring-only behavior. No credential/session data is copied. |
| Every tracked Markdown link | `test_markdown_links.py` (through `markdown-links.sh`) | Relative links in every tracked Markdown file resolve to tracked files and #anchors to GitHub heading slugs. |
| `tests/run.sh`, `tests/run.ps1`, the suites' fixture Git, `.pre-commit-config.yaml` and CI | `test-entrypoints.sh`, three native CI jobs | Visible prerequisite failure and optional skips, tests/lib/environment prefix isolation with explicit DOTFILES_TEST_* fixture exceptions, a named Python 3.11 floor failure, real linked-worktree parent HEAD/index/core.bare preservation, hook file selection with each hook's required inputs and one complete intended behavior pass per platform. Installed-kit variables/helpers outside the public dotfiles contract are not owned here. |

Native NTFS fixtures use a local runner token, not OpenSSH network-logon
trust. The held-handle rename fixture shows the rename refusal; that narrows,
but does not close, the window in which a writer of `~/.local` could swap its
`chezmoi.exe`. Desktop notification delivery requires an interactive
terminal; container/hosted-runner success does not establish fresh-machine
or real-cluster acceptance.

Interactive presentation helpers and network-transfer aliases remain outside
this automation matrix. Add a focused test when promoting one to a supported
automation contract. No line-coverage percentage substitutes for these checks.

Real-host evidence is separate: the ordinary-user PowerShell 7 console,
predictions, color and update-hook acceptance on 2026-11-08 is recorded in
[hosts](../docs/hosts.md#powershell-7-console-acceptance). On 2026-11-09 all
16 tmux tests passed on Linux tmux 3.4 and actual macOS tmux 3.8, including
six quoted-directory/action cases. Those tests verify the fixture's physical
starting directory and preserve quotes, backticks and literal tmux formats
without command injection. Neither result establishes genuine fresh-machine
acceptance. The user waived the five genuine fresh-machine runs for the
2026-11-09 follow-up; they remain not run in the
[acceptance checklist](../docs/bootstrap.md#acceptance-checklist). This scope
decision changes no automated coverage claim.
