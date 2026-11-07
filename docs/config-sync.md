# Native AI configuration contract

## Native configuration

The native source has `home/dot_claude/modify_private_settings.json` and
`home/dot_codex/modify_private_config.toml`. They use the native
`chezmoi:modify-template` directive, have no `.tmpl` suffix, read the portable
policy raw with a source-relative `include` of `home/.policy/claude-settings.json`
and `home/.policy/codex-config.toml` (a dot-directory chezmoi never deploys), and
let chezmoi write private regular files. Native deployment invokes no Python,
external jq, TOML library, custom writer or virtual environment. Converting an
existing home follows the reviewed
[takeover procedure](chezmoi-migration/takeover.md); host results are recorded
in the [migration status](chezmoi-migration/status.md).

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
native last-value-wins rule. Invalid UTF-8 and unpaired surrogate escapes can
become U+FFFD in the native parser; the transform conservatively rejects U+FFFD
in all parsed keys/strings before writing. This also rejects otherwise valid
intentional U+FFFD. Valid Unicode and surrogate pairs remain supported.
Empty/whitespace live JSON initializes an object; malformed, trailing or
non-object JSON fails.

Codex applies only the typed owned paths and removes only the retired paths
listed below. `home/.chezmoidata/codex-policy.json` contains paths/types only;
`tests/test_chezmoi_codex.py` pins it to a frozen list (19 owned paths with
types, 3 retired) and requires the portable TOML's leaves to be exactly the
owned paths with those types. The template reads
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
stricter/readonly existing modes and actual Windows ACLs need the takeover
procedure's destination review. An administrative synthetic ACL is not that review.
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
state. Maintenance blocks future dotfiles updates and explicit payload runs.
Failed apply keeps ownership; removing a guard requires inspected recovery.

The native API has no source writeback. Before takeover, review a historically
polluted portable source privately, preserve its unknown state in a separate
private backup, and reconcile the intended live config and owned portable values
explicitly. Do not import an entire application directory or use normal apply as
source cleanup. To change portable policy, edit `home/.policy/`, inspect a
nonsecret targeted native diff and apply. For live-only edits, use the
application's file/editor and review the resulting native diff; do not `add` a
mutable target over its modify template.

## Merge ownership

Codex ownership, required types and retired paths live in
`home/.chezmoidata/codex-policy.json`, which the native modify reads literally
(paths and types only, no values). The current owned fields are:

| TOML path | Owned required keys |
| --- | --- |
| Top level | `model`, `model_reasoning_effort`, `plan_mode_reasoning_effort`, `personality`, `default_permissions`, `approval_policy`, `approvals_reviewer`, `project_doc_fallback_filenames` |
| `features` | `network_proxy`, `multi_agent`, `memories` |
| `permissions.workspace-net` | `description`, `extends` |
| `permissions.workspace-net.network` | `enabled`, `allow_local_binding` |
| `permissions.workspace-net.network.domains` | `"*"` |
| `memories` | `generate_memories`, `use_memories` |
| `tui` | `status_line` (ordered string array) |

The shared status line includes the cumulative session token total and the
native estimated thread cost item. Codex CLI 0.166.0 exposes cost only for
Enterprise workspaces and omits it when unavailable. `context-used` reports
context window occupancy, independently of cumulative tokens. Other `tui`
settings, including colors, theme and onboarding state, remain local.
`/statusline` edits the live layout. A live edit of any owned key stops the
nonforce login update at `~/.codex/config.toml` until it is reconciled as in
[takeover.md](chezmoi-migration/takeover.md#reconcile-an-owned-ai-config-key).

Portable values replace these paths only; other live keys and tables are
retained, with the native serialization described above. Retired `sandbox_mode`,
the whole `sandbox_workspace_write` table and `features.js_repl` are removed.
Unknown portable keys are not silently deployed as shared policy.

Codex hooks are host runtime state; the native modify leaves them in place like
any other unowned field.

Codex rules deploy as an opaque, authoritative ordinary file: the plain source
`home/dot_codex/rules/portable.rules`; siblings such as `default.rules` are untouched.

## Codex override precedence and retirement

Codex reads one global instructions file, `~/.codex/AGENTS.override.md` when it
exists and `~/.codex/AGENTS.md` otherwise, with no include mechanism. Dotfiles
no longer generates overrides or ships a public instructions sync kind.

A host may still carry a regular `~/.codex/AGENTS.override.md` written by the
retired generator, which makes Codex ignore `~/.codex/AGENTS.md`. Nothing
removes it automatically: inspect it and move it aside by hand.

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
