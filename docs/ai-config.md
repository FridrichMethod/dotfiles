# AI configuration

## Modify templates

The source has `home/dot_claude/modify_private_settings.json` and
`home/dot_codex/modify_private_config.toml`. They use chezmoi's
`chezmoi:modify-template` directive, have no `.tmpl` suffix, read the portable
policy raw with a source-relative `include` of `home/.policy/claude-settings.json`
and `home/.policy/codex-config.toml` (a dot-directory chezmoi never deploys), and
let chezmoi write private regular files. They run inside chezmoi with its
builtin JSON and TOML functions, so deployment needs no other tool.

Claude merges objects recursively, portable leaves winning and arrays
replaced wholesale, including empty arrays. Local model, additionalDirectories
and unknown live fields survive. Portable model is forbidden; allow/ask are
required string arrays and deny is a string array when present. Removing a
portable key does not delete a live-only key.

The JSON parser is builtin `jq "fromjson"` on raw text. Its `json.Number`
values pass unchanged through object merge and serialization, retaining large
integers, long decimal fractions, signed zero and extreme exponents. Do not
substitute `fromJson`, which can coerce these values. Duplicate keys use the
parser's last-value-wins rule. Invalid UTF-8 and unpaired surrogate escapes can
become U+FFFD in that parser; the transform conservatively rejects U+FFFD
in all parsed keys/strings before writing. This also rejects otherwise valid
intentional U+FFFD. Valid Unicode and surrogate pairs remain supported.
Empty/whitespace live JSON initializes an object; malformed, trailing or
non-object JSON fails.

Codex applies only the typed owned paths listed below.
`home/.chezmoidata/codex-policy.json` contains paths/types only;
`tests/test_chezmoi_codex.py` pins it to a frozen list (19 owned paths with
types) and requires the portable TOML's leaves to be exactly the owned paths
with those types. The template reads
that manifest literally; local template data cannot expand ownership. Unknown
portable fields do not become policy. Every existing ancestor must be a table
before assignment. Quoted dotted keys, literal `"*"`, int64, unknown tables and
arrays of tables retain their TOML types without a JSON round trip.

TOML local date, local time and local datetime are explicitly unsupported by
this transform: v2.74.0 can shift their wall values, and Windows `TZ=UTC` is not
a fix. A recursive type guard rejects these values anywhere in either
input, including arrays and unowned fields, before changes
are emitted. The affected target remains byte-identical. Offset timestamps are
supported. Physical CRLF is normalized to LF before parsing, matching
the tested multiline basic/literal-string consumer semantics; explicit `\r\n`
escapes retain CRLF values. Empty TOML is valid. Malformed TOML, missing required
policy or invalid types fail without replacing the affected target.

Changed output is canonical JSON/TOML. After all validation and
transformation, each modify compares the result with an independently parsed
original using typed equality: Claude after both JSON parses, the
permission and portable-model checks, the U+FFFD guard and the merge; Codex
after all TOML validation and ownership transformations. An equal result returns
the original input bytes, preserving application formatting (Claude Code's
insertion-ordered JSON, Codex comments and layout) and avoiding a conflict caused
only by reserialization. Empty or whitespace-only Claude input is never kept.
A different result uses chezmoi's sorted-key JSON or TOML serialization; layout and
comments can then change. Object key order is ignored, but array order, value
types and JSON number spelling are not, so `1` and `"1"` or `1.0` still rewrite.
A Claude no-op also keeps duplicate live keys whose last value already
matches. This is a conservative equality check, not a new parser or formatting
engine. Second apply converges. `private_` normally produces Unix 0600;
stricter or read-only existing modes and actual Windows ACLs need a private
review of their own before the first apply. An administrative synthetic ACL is
not that review. Neither failures nor conflict refusal promise a whole-home
transaction.
Exit status matters even when stderr is empty; routine apply must retain
`--mode=file --less-interactive --no-tty --error-on-conflict --force=false`, closed stdin
and no blanket force.

File apply/update also passes `--exclude=dirs`; plain apply can change
existing shared-directory permissions. The operator prepares only inspected
missing parents using the directory-only, nonrecursive apply of
[Preparing missing parents](bootstrap.md#preparing-missing-parents). A later
update requiring another parent fails until that preparation is done; Git and
earlier files may already have changed. Review the local umask (Fresh home by
hand seeds `umask = 0o077`) and existing private-parent modes separately.

A fresh state database provides no first-apply ownership guard: ordinary
apply can replace a preexisting foreign symlink. Inspect exact owners and keep
private snapshots before a first apply ([Fresh home by hand](bootstrap.md#fresh-home-by-hand)
stops on a link at any managed path and copies each regular file it
replaces). A target first added upstream later is protected by
less-interactive mode, which refuses an existing target without a recorded
baseline. The updater refuses missing or empty persistent state. Maintenance
blocks dotfiles updates and explicit payload runs. Failed apply keeps
ownership; removing a guard requires inspected recovery
([Lost state](updates.md#lost-state)).

Apply, update and the modify templates write nothing back to the source.
Do not import an entire application directory or use normal apply as source
cleanup. To change portable policy, edit `home/.policy/`, inspect a
nonsecret targeted chezmoi diff and apply. For live-only edits, use the
application's file/editor and review the resulting diff; do not `add` a
mutable target over its modify template.

## Merge ownership

Codex ownership and required types live in
`home/.chezmoidata/codex-policy.json`, which the Codex modify template reads literally
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

The shared status line includes the cumulative session token total and
Codex's built-in estimated thread cost item. Codex CLI 0.166.0 exposes cost only for
Enterprise workspaces and omits it when unavailable. `context-used` reports
context window occupancy, independently of cumulative tokens. Other `tui`
settings, including colors, theme and onboarding state, remain local.
`/statusline` edits the live layout. A live edit of any owned key stops the
nonforce login update at `~/.codex/config.toml` until it is
[reconciled](#reconciling-an-owned-key).

Portable values replace these paths only; other live keys and tables are
retained, with the serialization described above. Unknown portable keys
are not silently deployed as shared policy.

Codex hooks are host runtime state; the modify template leaves them in place
like any other unowned field.

Codex rules deploy as an opaque, authoritative ordinary file: the plain source
`home/dot_codex/rules/portable.rules`; siblings such as `default.rules` are untouched.

## Reconciling an owned key

Dotfiles owns the portable Claude leaves of `home/.policy/claude-settings.json`
and the Codex paths listed above; `tui.status_line` is owned too. When a live
owned value differs from the last applied one, the nonforce login update stops
at that file and later targets stay stale. Causes: a local UI choice (Codex
`/statusline`, a persisted model or effort), or a Codex app-server that
started just before the update and wrote its in-memory copy of
`~/.codex/config.toml` back. That race does not depend on the key: any commit
that changes rendered Codex config can meet it, on every host where Codex
app-servers run, Marlowe included.

Reconcile one file, never with a routine force:

1. Stop or let idle the Codex app-servers on that host, including those started
   by a remote desktop client on another machine.
2. Privately compare the live file with `chezmoi cat` of the target under the
   full argument set (`home_cz cat TARGET` from the clone); record only the
   differing key names.
3. Back up the file privately with its mode and owner.
4. If a differing value is a deliberate local choice, change the tracked
   portable value through a reviewed commit, or accept the portable value.
5. Apply only that target with the full argument set, `--exclude=dirs` and
   `--force` (`home_cz apply --exclude=dirs --force TARGET`).
6. Verify an empty status, a file equal to its target, and unchanged mode and
   owner; then restart the app-servers stopped in step 1.

Before rolling out a commit that changes rendered `~/.codex/config.toml`, ask
the user to quit Codex desktop apps that connect to the target hosts, and check
each host's status for that file after its first login update.

## Codex override precedence

Codex reads one global instructions file, `~/.codex/AGENTS.override.md` when it
exists and `~/.codex/AGENTS.md` otherwise, with no include mechanism. Dotfiles
deploys only `~/.codex/AGENTS.md`.

## No third-party instructions under ~/.claude

The global `CLAUDE.md` is the only reviewed cross-host instruction source for
Claude. No host should hold `~/.claude/AGENTS.md` or third-party Markdown
under `~/.claude/rules/`: Claude Code loads `~/.claude/rules/**/*.md` into
sessions (a file with `paths:` frontmatter when a matching file is touched),
and with `claude-md-and-agents-md` it also loads `~/.claude/AGENTS.md` next to
the global `CLAUDE.md`. An installer that copies a plugin's rules, agents and
commands into `~/.claude` itself, as everything-claude-code's own installer
does, therefore injects unreviewed instructions that conflict with the global
guide (automatic commit and push, an 80% coverage floor, agents started
without being asked) and shadows slash commands such as `/code-review`. Use
such a plugin through the plugin system, which loads no plugin-bundled rules;
adopt a rule worth keeping into the global `CLAUDE.md` and Codex `AGENTS.md`
after review, as the parallel-execution bullet was.

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
