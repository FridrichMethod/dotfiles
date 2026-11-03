# Stage 3: Native mutable configuration implementation plan

> **For agentic workers:** Use subagent-driven-development with separate worktrees
> under [README.md](README.md). Incorporate Stage 1-2 evidence before starting and
> refine Stage 4 at completion.

**Goal:** Complete the new deployment path using native JSON/TOML transforms,
with no Python, external jq, TOMLKit or sync virtual environment in that path.

**Architecture:** Two native modify templates read live contents and portable
policy, validate ownership boundaries, and emit complete desired contents.
Chezmoi owns writing. Legacy Stow/backend remains available only for homes that
have not yet switched and for corresponding compatibility checks.

**Tech stack:** Chezmoi builtin gojq and TOML/template functions; stdlib tests.

**Spec:** [Contract decisions](README.md#contract-decisions), Stage 1's probes,
Stage 2's portable-source bridge, [support boundary](support-boundary.md) and
[status](status.md).
Retain the selected synthetic secret backend from
[secrets-and-ssh.md](secrets-and-ssh.md). No production static-secret target is
selected in Stage 3; private allowlists/trust/bootstrap belong to Stage 4.

Implementation record: the native candidate now contains both modifies and typed
ownership metadata. [status.md](status.md) records actual checks and limitations;
the next session is [Stage 4](start-stage-4.md). The work packages below retain
the execution contract, with the native parser decisions updated from evidence.

## Global constraints and review focus

Preserve portable security-policy values and live-only state. Claude and Codex use
canonical formatting when policy transformation changes typed data; a validated
typed no-op preserves the original bytes. Do not introduce a second parser,
custom atomic writer, template framework, generic configuration merger or
per-application subprocess.

Review malformed/empty input; authoritative arrays/false/null; Codex quoted keys
and TOML types; shared-file ownership; and accidental dependence on a developer's
Python, jq, old wrapper or venv. Do not mutate managed files in before/after hooks.

## Parallel ownership

- Claude worker: `home/dot_claude/modify_private_settings.json`, its assigned
  native validation fragment and Claude tests.
- Codex worker: `home/dot_codex/modify_private_config.toml`, its assigned ownership
  data/validation fragment and Codex tests.
- Independent verifier: integration/negative cases against both outputs; read-only
  review of portable policy and existing source. Do not edit worker templates.
- Coordinator: common data locations, shared fixture/CI/runners, ordinary rules
  integration, active instructions and documentation.

Freeze portable baseline and ownership-data interfaces first. During coexistence,
existing baselines remain canonical through the Stage 2 bridge. Native ownership
metadata may temporarily mirror `CODEX_POLICY`; one parity check prevents drift
until Stage 6 removes the legacy definition. Do not duplicate policy values.

## Stage 2 implementation inputs and execution order

Start from the complete Stage 2 integration worktree recorded in `status.md`,
including its uncommitted predecessor results. Never recreate only bare HEAD.
The candidate now has `.chezmoiroot=home`, `.chezmoiversion=2.74.0`, and exactly
67 ordinary source files and five source-selection/validation files.
`home/.chezmoiignore` calls
`home/.chezmoitemplates/validate-host`. The init template explicitly loads that
same internal guard with `includeTemplate`; named templates are unavailable in
the init context. Ordinary legacy payloads always use literal `include`.

Local `[data].host` is mandatory, with exactly seven values. Missing, empty,
wrong-type, unknown and incompatible roles fail before destination writes.
Neither `DOTFILES_HOST` nor OS detection chooses a role. The source/data/bridge
contract and exact ordinary sets are exercised by `tests/chezmoi_source_support.py`
and `tests/test_chezmoi_source_state.py`. Reuse `SourceFixture(host)` and
`expected_entries(host)` rather than creating another deployment harness.

Execute these packages in order, then parallelize the two independent transforms:

1. Preserve Stage 2's passing ordinary-source checks and begin with the local
   TOML temporal reproduction on all three actual platforms. Select a verified
   native correction or a conservative native fail-before-write strategy. A
   timezone environment variable is not a Windows fix. Record any rejected
   legitimate input as an explicit safe limitation; never label it preserved.
2. Freeze the two input paths below and the ownership manifest interface. Read
   current `CODEX_POLICY`/`CODEX_RETIRED` in `lib/config_sync.py`. If native typed
   ownership data is needed, use `home/.chezmoidata/codex-policy.json`, containing
   only owned/retired paths and types, with one stdlib parity check against those
   exact legacy constants. Do not duplicate portable values or invent a generic
   merge framework. Keep the metadata JSON under ordinary parser hooks.
3. Claude worker owns `home/dot_claude/modify_private_settings.json`, optional
   `home/.chezmoitemplates/claude-policy`, and `tests/test_chezmoi_claude.py`.
   Codex worker owns `home/dot_codex/modify_private_config.toml`, optional
   `home/.chezmoitemplates/codex-policy`, the frozen ownership manifest, and
   `tests/test_chezmoi_codex.py`. Both use the existing fixture and builtin native
   functions; no `.tmpl` suffix on modify targets. Each worker has its own
   branch/worktree carrying the entire required Stage 2 state.
4. Integrate sequentially. Coordinator updates whole-source expectations from
   `47/54/53/57/52/52/24` to `49/56/55/59/54/54/26`, removing only the explicit
   two-AI omission. Keep legacy sync executables absent, fcitx5/rules ordinary,
   shared directories non-exact, and unmanaged auth/default.rules untouched.
   A separate verifier adds destructive-input and dependency-negative cases.
5. Keep static-secret work separate from these two shared files. Real allowlists,
   trust groups and identities remain private Stage 4 enrollment choices. Stage 3
   may establish optional ciphertext/vault selection and synthetic tests only;
   an unselected secret produces no managed target, never a dummy credential.
6. Run `tests/chezmoi.sh` / native `tests/chezmoi.ps1`, focused transform tests,
   Linux full `tests/run.sh --ci`, Windows full `tests/run.ps1 -CI`, full
   pre-commit, and independent read-only aggregate review. Reuse existing legacy
   interpreters for old suites; create no new merge runtime. Record actual
   Linux/macOS/Windows results and optional lint/platform skips separately.

The canonical portable input expressions are:

```gotemplate
{{- $portableJSON := include (joinPath .chezmoi.workingTree "common/claude/.claude/settings.json") -}}
{{- $portableTOML := include (joinPath .chezmoi.workingTree "common/codex/.codex/config.toml") -}}
```

Parse these as native data inside their respective modify templates. They are
not independently editable native policy copies. Stage 6 moves canonical input
once and removes all remaining legacy includes with parity checks.

Windows ordinary profiles still target `Documents/PowerShell/profile.ps1` and
`Documents/WindowsPowerShell/profile.ps1`. Stage 2 queried both real native
`CurrentUserAllHosts` paths without reading profiles and confirmed that mapping
on the tested host. Redirected Documents remains a concrete takeover blocker
until Stage 4 explicitly maps it or rejects it before mutation. Do not infer
profile discovery from overridden HOME or Linux OS-data rendering.

## Task 1: Implement native Claude merge

### Verified native inputs and supported safety limits

Use the executable artificial templates in
`tests/fixtures/chezmoi/native-config/` as syntax evidence, not as the full
production policy. `jq` is builtin and returns a list: wrap live/portable in an
object, use `.live * .portable`, require one result, then `first | toPrettyJson`
unless the result is a validated typed no-op of nonempty live input.
Read `.chezmoi.stdin`, initialize only missing/empty content, validate object
roots, and preserve false/null/empty arrays. Never use truthy fallback operators
for owned values. Keep all real portable policy values unchanged.

For TOML, native list paths assign literal dotted and `"*"` keys;
`deleteValueAtPath` takes a dotted string on v2.74.0 and rejects a list. Validate
ancestors before assignment. Ordinary integers, offset timestamps, tables,
arrays of tables and multiline strings have native evidence in the Stage 1
suite. Do not pass the complete document through JSON/gojq.

Stage 3 selects safe refusal for local TOML date/time/datetime, recursively
checking parsed `time.Time` location markers in both inputs before assignment.
All three actual native platforms passed the refusal/byte-preservation probes.
This is an explicit unsupported-valid-input limit, not a serialization correction.
Windows UTC/LA/Tokyo settings still shifted raw wall times; never bypass the guard
with TZ. Offset timestamps remain supported without a JSON round trip.

Native conflict refusal can have empty stderr. Template failure must still
preserve the affected target, and adapter error handling must honor exit status.
The production JSON parser uses builtin `jq "fromjson"` on raw live/portable
strings, preserving `json.Number` through merge/serialization. Never substitute
`fromJson`, whose conversions lose some numeric values. Permission elements use
`typeIs "string"`, since json.Number has string kind. Native duplicates remain
last-value-wins. A parsed U+FFFD guard rejects invalid UTF-8/surrogate replacement
and intentionally valid U+FFFD before writing; valid Unicode pairs remain supported.
After every check and the merge, Claude returns the original nonempty live bytes,
including CRLF and key order, only when the merged object is native `deepEqual`
to an independently reparsed live document. Claude Code writes insertion-ordered
JSON after plugin, marketplace or model changes, so sorted serialization alone
would otherwise conflict. `json.Number` compares by token and types stay distinct.

Native `replace "\r\n" "\n"` before `fromToml` selects LF physical newlines for
parsing while retaining explicit escaped CRLF. Codex returns the original bytes,
including physical CRLF, only when the fully validated transformed document is
native `deepEqual` to an independently parsed original. This avoids conflicts
when an application changes formatting without changing policy values. Both
inputs, temporal restrictions, required types and ancestors are still validated
before that comparison, and retired keys are still removed. Integers and floats
remain distinct; native NaN equality is false, so NaN documents conservatively
continue through canonical serialization. Exact-byte production tests cover multiline
basic/literal strings, continuations and portable-owned strings. Do not let
Windows `write_text` choose synthetic input bytes implicitly, or claim these
stdlib/native comparisons are real application startup tests.

- [x] Use a modify template with `chezmoi:modify-template` and no `.tmpl` suffix.
  Missing/empty live content initializes an object; nonempty malformed content
  and non-object roots fail rather than becoming an empty successful result.
- [x] Parse with native JSON functions. Validate portable permissions arrays and
  reject a portable `model`, preserving current per-host model selection.
- [x] Use the tested builtin jq recursive object merge with live first and
  portable second. Arrays replace wholesale, including empty arrays. Do not use
  `//` or template `default` to distinguish missing leaves from false/null/empty.
- [x] Test live-only model, additionalDirectories and unknown nested fields;
  portable-owned hooks/arrays must still replace according to the policy.
- [x] Verify invalid policy, false/zero distinction, nested arrays and null.
  Adopt documented native duplicate-key/numeric limits without a new parser.
- [x] Resolve the supported Claude client contract from Stage 1. Remove the old
  plugin ID only with a verified floor and coherent tests/docs; otherwise schedule
  that change for Stage 5. Explain that removing a portable key does not purge a
  live-only old key. Keep current Windows helper guards and permission values.

## Task 2: Implement native Codex owned-field transformation

- [x] Use `fromToml`, typed ownership validation, native path operations and
  `toToml`. Never round-trip the entire document through JSON/gojq.
- [x] Preserve current owned-path behavior: only required owned keys are applied;
  unknown portable keys do not silently acquire ownership. Remove exactly the
  current retired paths. Re-read the current policy instead of freezing a stale
  count if legitimate changes landed after planning.
- [x] Validate ancestor types before assignment so an unexpected scalar/table
  collision does not destroy unrelated live content.
- [x] Test live projects with quoted dotted keys, literal `"*"`, unknown tables,
  arrays of tables, multiline strings, integers and native TOML timestamps.
- [x] Verify typed required fields and malformed live/portable documents fail
  without replacing the affected target. Use tested delete-path syntax.
- [x] Document canonical formatting/comment loss on actual typed policy changes
  and the native edit workflow. Preserve exact input bytes on a validated native
  typed no-op, including comments and absence of a final newline. Existing-state
  fixtures require nonforce apply, empty diff and unchanged target metadata after
  application reformatting. No external parser, filter or helper is involved.
- [x] Explicitly retire `--migrate-portable` from the new native API and describe
  manual recovery of a historically polluted portable source before adoption.
  Do not port source writeback into normal apply. Keep retired-key removal as
  current live-policy enforcement; remove the old API with the backend in Stage 6.

## Task 3: Complete whole-source and dependency-negative checks

Stage 3 selects no production static-secret target while private allowlists,
trust groups and bootstrap access remain unsettled. Keep the existing builtin-age
synthetic recipient/failure/seed tests and prove the complete candidate adds only
the two AI targets, preserving synthetic `.secrets` siblings. No dummy credential
or recurring auth seed is installed. Stage 4 enrolls selected real static files
through the native encrypted/private path after those choices are explicit.

Update active instructions narrowly to permit the reviewed ciphertext/vault path
while continuing to forbid plaintext credentials, private keys and active auth
caches in tracked source. Keep app-owned refresh state and optional bootstrap
seeding separate from recurring apply; no token-sync or refresh implementation.

**Files:** Stage 1-2 tests plus specific native Claude/Codex tests; update
`docs/config-sync.md` to distinguish native and legacy compatibility paths.

- [x] Assert portable values remain unchanged and live-only values survive.
  Assert unrelated files such as `default.rules`, app-written auth caches and
  runtime data are neither overwritten nor removed. Allowlisted static secrets
  have their own native ownership tests and must not leak into these transforms.
- [x] Assert source bytes are unchanged, private file attributes are effective,
  and second apply converges after initial canonicalization.
- [x] Verify template/parse failure cannot produce an empty target that chezmoi
  interprets as removal. Do not claim an all-home transaction.
- [x] Run a complete candidate source apply in a fixture lacking `.venv-sync`
  and with Python/external jq unavailable to chezmoi children. The test harness
  may use stdlib Python; the deployment path must not invoke it for merging.
- [x] Exercise native Linux/macOS/Windows. Validate native Windows JSON/TOML
  readability and inherited ACL behavior without claiming Unix mode parity.
- [x] Audit test entrypoints/CI: legacy suites may still need TOMLKit, but the
  native suite has a separate dependency-negative proof. Report both facts.
- [x] Extend Stage 1's narrowly scoped parser-hook exclusions to these native
  modify templates, whose `.json` / `.toml` source contains Go template syntax.
  Require rendered-output parse tests and keep ordinary portable/data files
  under `check-json` / `check-toml`; do not exempt whole tool directories.
- [x] Run required checks and a separate aggregate review. Update active rules
  only to support the completed native path alongside legacy compatibility.

## Exit and next-stage refinement

Exit requires a complete candidate source and a tested deployment path with no
sync venv dependency. It does NOT mean the legacy runtime can already be deleted.
Do not apply both paths to the same real target or activate login changes here.

Update the inventory and `status.md`. Expand Stage 4 into concrete compatibility
release, worker quiescence, per-home takeover, conflict, backup and recovery tasks.
Record the simplest native commands that passed fixtures. Identify all remaining
legacy callers so Stage 6 can remove them together. No real HOME was changed.
Refine Stage 4's real canary, secret enrollment/key bootstrap and per-host evidence
under D11; do not revert to leaving reachable-host execution to the user.
