# AI configuration sync runtime and contract

## Native configuration and Stage 4 handover

The isolated chezmoi candidate adds `home/dot_claude/modify_private_settings.json`
and `home/dot_codex/modify_private_config.toml`. They use the native
`chezmoi:modify-template` directive, have no `.tmpl` suffix, read canonical
portable values with literal includes from the existing `common/` files and
let chezmoi write private regular files. Native deployment invokes no Python,
external jq, TOMLKit, custom writer or sync environment. Legacy installation and
login behavior below remains available for unmarked legacy homes; never run
both writers on one destination. Stage 4 adds the reviewed
[takeover procedure](chezmoi-migration/takeover.md). Candidate CI and rollout
results are recorded separately in the migration status.

Claude retains recursive object merge with portable leaves winning and arrays
replaced wholesale, including empty arrays. Local model, additionalDirectories
and unknown live fields survive. Portable model is forbidden; allow/ask are
required string arrays and deny is a string array when present. Both plugin IDs
and every current portable permission value remain unchanged. No new client
version floor is selected. Removing a portable key does not delete a live-only key.

The JSON parser is builtin `jq "fromjson"` on raw text. Its native `json.Number`
values pass unchanged through object merge and serialization, retaining large
integers, long decimal fractions, signed zero and extreme exponents. Do not
substitute `fromJson`, which can coerce these values. Duplicate keys use the
native last-value-wins rule, unlike the legacy duplicate detector. Invalid
UTF-8 and unpaired surrogate escapes can become U+FFFD in the native parser;
the transform conservatively rejects U+FFFD in all parsed keys/strings before
writing. This also rejects otherwise valid intentional U+FFFD. Valid Unicode
and surrogate pairs remain supported. Empty/whitespace live JSON initializes
an object; malformed, trailing or non-object JSON fails.

Codex applies only the typed owned paths and removes only the retired paths
listed below. `home/.chezmoidata/codex-policy.json` contains paths/types only,
with a parity test against `CODEX_POLICY` and `CODEX_RETIRED`. The template reads
that manifest literally; local template data cannot expand ownership. Unknown
portable fields do not become policy. Every existing ancestor must be a table
before assignment. Quoted dotted keys, literal `"*"`, int64, unknown tables and
arrays of tables retain their native types without a JSON round trip.

TOML local date, local time and local datetime are explicitly unsupported by
this transform: v2.74.0 can shift their wall values, and Windows `TZ=UTC` is not
a fix. A recursive native type guard rejects these values anywhere in either
input, including arrays and retired/otherwise unowned fields, before changes
are emitted. The affected target remains byte-identical. Offset timestamps are
supported. Physical CRLF is normalized to LF before native parsing, matching
the tested multiline basic/literal-string consumer semantics; explicit `\r\n`
escapes retain CRLF values. Empty TOML is valid. Malformed TOML, missing required
policy or invalid types fail without replacing the affected target.

Changed native output is canonical JSON/TOML. After all validation and
transformation, each modify compares the result with an independently parsed
original using native typed equality: Claude after both JSON parses, the
permission and portable-model checks, the U+FFFD guard and the merge; Codex
after all TOML validation and ownership transformations. An equal result returns
the original input bytes, preserving application formatting (Claude Code's
insertion-ordered JSON, Codex comments and layout) and avoiding a conflict caused
only by reserialization. Empty or whitespace-only Claude input is never kept.
A different result uses native sorted-key JSON or TOML serialization; layout and
comments can then change. Object key order is ignored, but array order, value
types and JSON number spelling are not, so `1` and `"1"` or `1.0` still rewrite.
A Claude no-op also keeps duplicate live keys whose native last value already
matches. This is a conservative equality check, not a new parser or formatting
engine. Second apply converges. `private_` normally produces Unix 0600;
stricter/readonly existing modes and actual Windows ACLs need Stage 4
destination review. An administrative synthetic ACL is not that review.
Neither failures nor native conflict refusal promise a whole-home transaction.
Exit status matters even when stderr is empty; routine apply must retain
`--mode=file --less-interactive --no-tty --error-on-conflict --force=false`, closed stdin
and no blanket force.

File apply/update also passes `--exclude=dirs`; plain native apply can change
existing shared-directory permissions. The operator prepares only inspected
missing parents using native directory-only, nonrecursive apply. A later update
requiring another parent fails until that preparation is done; Git and earlier
files may already have changed. Review the local native umask and existing
private-parent modes separately, as described in the takeover procedure.

Fresh native state does not provide a first-apply ownership guard: ordinary
apply can replace a preexisting foreign symlink. Inspect exact owners and private
snapshots before any takeover apply. This also affects a new target first added
upstream after takeover; native less-interactive mode protects existing targets
without a recorded baseline. The updater refuses missing or empty persistent
state. The home-bound `.config/dotfiles/native` marker makes all four
legacy sync wrappers and the Python backend refuse an explicit LIVE destination,
including `--check` and `--migrate-portable`, before reads/writes. An unrelated
explicit destination does not inherit the invoking HOME's guard. Maintenance
also blocks legacy writers, future dotfiles updates and explicit payload runs.
Failed apply keeps ownership; removing a guard requires inspected recovery.

The native API has no `--migrate-portable` or source writeback. Before takeover,
review a historically polluted portable source privately, preserve its unknown
state in a separate private backup, and reconcile the intended live config and
owned portable values explicitly. Do not import an entire application directory
or use normal apply as source cleanup. During coexistence, edit canonical
`common/` policy values, inspect a nonsecret targeted native diff and apply.
For live-only edits, use the application's file/editor and review the resulting
native diff; do not `add` a mutable target over its modify template. Stage 6
moves canonical inputs once and retires the entire legacy parser/helper chain.

## Legacy compatibility path

Installation and login orchestration remain shell and PowerShell. The three
`*-sync` entrypoints delegate configuration/file operations to the
small `lib/config_sync.py` backend. It uses Python's standard-library JSON
implementation and `tomlkit` for syntax-aware TOML edits; no AWK/regular-expression
TOML parser or alternate jq merge implementation remains.

## Explicit provisioning

All AI helpers require Python 3.11 or newer. Codex TOML sync additionally needs
the exact pure-Python `tomlkit` version in `requirements-sync.txt`; setup verifies
its wheel hash. Claude JSON and Codex rules use only
Python's standard library.
To provision the complete installer runtime on each checkout/device, run one of:

```sh
./setup-sync.sh
# Or select a particular installed interpreter, including a path with spaces:
./setup-sync.sh --python /path/to/python3
```

```powershell
./setup-sync.ps1
# Or:
./setup-sync.ps1 -Python 'C:\path with spaces\python.exe'
```

Setup creates the ignored, checkout-local `.venv-sync/`, installs only the
pinned wheel, and validates the runtime. It does not require activation, root,
global pip installs, conda activation, or a new shell-startup PATH entry. It
refuses an unrelated directory or a linked virtual environment. It does not
install Python itself; select an already installed supported interpreter.

Profiles, installers, and automatic updates **never** install or download
AI-sync/parser dependencies. A missing runtime, or a changed required parser version after a
pull, fails with a request to rerun explicit setup. An offline host can provision
from a previously downloaded matching wheel using pip's normal offline options
(for example `PIP_NO_INDEX=1` and `PIP_FIND_LINKS=/path/to/wheels`).

The shell wrappers resolve their own Stow symlink chains to find the checkout
and its `lib/` directory. They use `.venv-sync/bin/python` on Unix or
`.venv-sync/Scripts/python.exe` under native Windows/Git Bash. An explicit
`DOTFILES_SYNC_PYTHON` **executable path** overrides this lookup, useful for CI
or a separately provisioned host-local environment. An invalid override fails;
it never falls back silently to another interpreter. Native Windows paths are
converted for Git Bash's executable lookup. Backend paths and arguments remain
quoted, and Python runs with `-I -B -X utf8` (no user-site/PYTHONPATH injection or
bytecode cache writes, and UTF-8 diagnostics for Windows paths).

Python itself does not need a venv. A separately provisioned interpreter selected
with `DOTFILES_SYNC_PYTHON` can run the helpers without one. JSON/rules do not
require `tomlkit` on that path, but TOML sync and the full `--runtime-check` still
require the exact pin. The default launcher continues to use `.venv-sync`; it
does not silently search system Python. See [dependency options](dependencies.md).

The clone must remain present for its stowed wrappers to work, just as for other
Stow-managed files. Re-provision rather than copying virtual environments to a
different OS, Python installation, or checkout location.

## Helper API

```text
codex-config-sync [--quiet] [--check | --migrate-portable] PORTABLE LIVE
claude-settings-sync [--quiet] [--check] PORTABLE LIVE
codex-rules-sync [--quiet] [--check] PORTABLE LIVE
```

All paths are explicit; helpers do not infer a user's real home. `--check`
validates the runtime, both selected inputs and the complete serialized merge
without creating target directories, temporary files, or changing any input.
It permits an absent live file and validates a legacy live symlink's contents
without replacing it. This is the installers' preflight interface. It is not a
promise that a later write will succeed: permissions or files can change after
preflight, and a filesystem can run out of space.

`--quiet` suppresses successful validation/sync messages, never errors. Installers
use it for both preflight and apply, and report their own stages and final summary.

Missing portable input, unreadable/nonregular input, dangling live symlinks,
malformed JSON/TOML, and invalid required portable fields fail closed. Empty live
JSON is treated as a fresh host; nonempty malformed JSON is rejected. Empty TOML
is a valid fresh document. Empty portable rules are rejected. Duplicate JSON
keys and non-JSON constants such as `NaN` are rejected rather than normalized.

Ordinary sync treats the portable source as read-only: bytes, permissions and
mtime are untouched. Passing the same regular file or two hardlinks as portable
and live is rejected. A live symlink to the portable source is supported for
migration to a mutable regular file.

## Merge ownership

Codex ownership, required types, and retired paths are centralized in
`CODEX_POLICY` and `CODEX_RETIRED` in `lib/config_sync.py`. The current owned
fields are:

| TOML path | Owned required keys |
| --- | --- |
| Top level | `model`, `model_reasoning_effort`, `plan_mode_reasoning_effort`, `personality`, `default_permissions`, `approval_policy`, `approvals_reviewer`, `project_doc_fallback_filenames` |
| `features` | `network_proxy`, `multi_agent`, `memories` |
| `permissions.workspace-net` | `description`, `extends` |
| `permissions.workspace-net.network` | `enabled`, `allow_local_binding` |
| `permissions.workspace-net.network.domains` | `"*"` |
| `memories` | `generate_memories`, `use_memories` |
| `tui` | `status_line` (ordered string array) |

The shared status line includes the cumulative session token total and the native
estimated thread cost item. Codex CLI 0.166.0 exposes cost only for Enterprise
workspaces and omits it when unavailable. `context-used` reports context window
occupancy, independently of cumulative tokens. Other `tui` settings, including
colors, theme and onboarding state, remain local. `/statusline` edits the live
layout. A legacy sync restores the shared array; on a native home a live edit of
any owned key stops the nonforce login update at `~/.codex/config.toml` until it
is reconciled as in [takeover.md](chezmoi-migration/takeover.md#reconcile-an-owned-ai-config-key).

Portable values replace these paths only. Other live keys, tables, comments,
multiline strings and arrays of tables are retained by TOMLKit's document model.
Formatting of edited values can change; the library may also normalize some
unusual out-of-order array-of-tables layouts. Semantic no-ops do not replace the
file. Retired `sandbox_mode`, the whole `sandbox_workspace_write` table, and
`features.js_repl` are removed. Unknown portable keys are not silently deployed
as shared policy.

Claude deep-merges objects with portable leaf values winning. Arrays, including
permissions and hooks, replace wholesale, even when empty. Live-only fields such
as `model` and `permissions.additionalDirectories` remain. `false`, `null`, and
numeric values remain distinct. Portable `permissions.allow` and `permissions.ask`
must be string arrays; `permissions.deny` must also be a string array when present.
Portable `model` is rejected to protect per-host model
selection. This refactor does not change the contents of the portable policies
or the separate Node-based Claude hooks.

Codex hooks are host runtime state and remain untouched by ordinary sync.
Explicit legacy migration preserves source-only hooks just like other unknown
fields. The helpers do not expose a separate hook-registration API.

Codex rules remain an opaque, authoritative byte copy: the backend does not
parse, reformat or edit rule syntax. Siblings such as `default.rules` are untouched.

## Codex override precedence and retirement

Codex reads one global instructions file, `~/.codex/AGENTS.override.md` when it
exists and `~/.codex/AGENTS.md` otherwise, with no include mechanism. Dotfiles
no longer generates overrides or ships a public instructions sync kind.

After successful POSIX Stow, the installer removes an override only when it is
a nonsymlink regular file whose first line exactly matches the retired generator's
marker. Foreign files, symlinks, directories and FIFOs remain with a warning to
inspect and move obsolete entries aside manually. A removal error prevents
applied-revision acknowledgment. Native Windows does not clean up overrides;
inspect legacy files manually. See [Sherlock migration](sherlock-kit.md).

## Legacy portable cleanup

Older Stow links may have allowed runtime state to accumulate in tracked Codex
input. Ordinary sync now materializes the live file without cleaning its source.
To explicitly clean that known legacy state:

```sh
common/codex/.local/bin/codex-config-sync --migrate-portable \
    common/codex/.codex/config.toml /path/to/live/config.toml
```

Migration first retains portable-only runtime state in the live document;
existing live runtime values win conflicts. It then applies owned portable
policy and removes retired paths. Only after the live snapshot is safely
materialized does it rewrite the portable baseline to owned keys. This also
preserves source-only runtime state when live is already a regular file or is
absent, not just when it remains a legacy symlink. The portable migration target
must itself be a regular file, not a symlink. Review the resulting tracked diff;
the command intentionally modifies the source and never runs automatically.

## File safety and test boundaries

Each changed file is serialized and validated before writes, staged in an
adjacent temporary file, flushed, and replaced with `os.replace`. There is no
preliminary unlink of an existing live symlink. Failed temporary creation,
writing or replacement leaves the prior file/link in place and cleans the
temporary file. New regular files and materialized legacy symlinks default to
`0600` for Codex config and `0644` for Claude settings and Codex rules on Unix.
Existing regular-file permissions are
intersected with those defaults, never broadened: for example, a private `0600`
Claude file stays private on both changed writes and no-ops. Explicit portable migration also preserves stricter source modes.
Windows uses native replacement behavior and inherited directory ACLs;
Unix permission bits are not an ACL policy there.

Unchanged regular files keep their inode and mtime; Unix mode drift may still be
corrected. The backend checks for observed content changes before replacement
and asks for retry instead of overwriting them. This is not an atomic
compare-and-swap and cannot eliminate a simultaneous application's final
read/replace race. Close the configuration editor during manual migrations.

Safety is per file, not a transaction across all AI files. Explicit migration
writes live first, then portable; failure of the second write leaves the original
portable source intact and can be retried. Installer state must only acknowledge
a completely successful install.

Tests use the standard library, disposable targets, and injected write failures:

```sh
.venv-sync/bin/python -I -B -m unittest discover -s tests -p test_config_sync.py -v
./tests/codex-config-sync.sh
./tests/ai-config-sync.sh
```

```powershell
& ./.venv-sync/Scripts/python.exe -I -B -m unittest discover -s tests -p test_config_sync.py -v
```

Native backend tests run on all three OSes; tests specific to POSIX permission
bits/FIFOs are explicitly marked. Windows symlink tests require the CI runner's
symlink privilege. These tests do not establish OpenSSH network-logon trust or
Task Scheduler behavior; those are separate installer/update integration checks.

## Permission policy rationale

The portable Claude arrays intentionally reserve ask for sudo and deny for the
irrecoverable extremes listed in AGENTS.md. In auto mode an ask rule prompts a
person even when a hook would allow the command, so broad ask rules would remove
commands from classifier review. Ordinary rm, recursive rm, git clean and npx
therefore remain classifier decisions, not portable allow/ask rules.

The classifier has built-in checks for critical paths, including root, its
direct children, HOME, the working directory and parents, directory-wide globs
and Windows drive roots. An allow rule or hook cannot approve these paths;
this also applies inside command/process substitutions. Claude inspects Git
status before work-discarding commands. Denials appear under /permissions,
Recently denied (retry with r); auto mode pauses after 3 consecutive or 20 total
blocks. Keep the literal $defaults entries when tuning autoMode prose so the
built-in allow/soft_deny lists remain included.

With classifyAllShell enabled, Bash allow rules are suspended in auto mode.
Protected-path writes are checked before allow rules even outside that mode.
Adding a shell allow pattern cannot fix a classifier false positive or grant
permission to loosen live .claude settings. A person applies those changes.

Broad allow patterns for network transfers, code loaders, package installers
and remote-mutating Git/GitHub operations were reviewed and knowingly accepted.
An automated review recommended narrower argument-anchored alternatives, such
as host-limited curl and in-tree requirements-only pip installs. That remains a
host threat-model decision, not authorization for unrelated policy changes.
No permission values change as part of this documentation consolidation.
