# Research references and evidence boundaries

## Stage 4 additions

The candidate/evidence boundary and actual six-host outcomes are recorded in
[stage-4-evidence.md](stage-4-evidence.md). Current native probes established a
critical refinement: `--error-on-conflict` alone can replace an existing target
that has no recorded native baseline, including a target first added upstream
after takeover. The combination `--less-interactive --no-tty
--error-on-conflict --force=false` rejects these conflicts while permitting
absent new targets and known safe updates. The
[official global flags](https://www.chezmoi.io/reference/command-line-flags/global/)
describe the native mechanism; isolated v2.74.0 regressions establish this
candidate's actual boundary. No custom state parser or second journal was added.

Later v2.74 probes established that plain apply also changes existing directory
modes. The corrected operator/update commands pin `--exclude=dirs`; missing
parents require inspected native directory-only preparation. Ignore-directory
patterns and config-key alternatives did not preserve the required behavior in
these probes. The actual regression evidence and nontransactional boundary are
in [Stage 4 evidence](stage-4-evidence.md#published-bridge-and-subsequent-corrections).

Native config init now reads existing TOML and preserves unrelated local
settings, including age and data, with native
[setValueAtPath](https://www.chezmoi.io/reference/templates/functions/setValueAtPath/)
and [deleteValueAtPath](https://www.chezmoi.io/reference/templates/functions/deleteValueAtPath/).
The latter takes a string path; only fixed simple owned config keys use it.
Local temporal values are refused before config write because the Stage 3
native temporal limitation also applies to this parser/writer round trip.

For the recovery-custody request, the official
[Bitwarden downloads](https://bitwarden.com/download/) and
[CLI documentation](https://bitwarden.com/help/cli/) establish platform clients
and published CLI checksums. Installing a client is not proof of account setup,
vault custody or age recovery. The private proposal retains actual selections.
The user subsequently selected Apple Passwords and canceled Bitwarden; all
task-installed clients were removed. Actual recovery deposit/retrieval remains
pending, separately from the confirmed second-device sync choice.

Planning references read on 2026-11-01; native evidence added on 2026-11-02.
Prefer these official sources over third-party migration examples. Live
documentation may describe a newer release than the selected test binary.
The planning work ran no binary; Stage 1 now tests the selected release below.

## Upstream references

| Topic | Official source | Consequence for this plan |
| --- | --- | --- |
| State model | [Concepts](https://www.chezmoi.io/reference/concepts/) | Source, local data and destination contribute to desired state |
| Source root | [Custom source directory](https://www.chezmoi.io/user-guide/advanced/customize-your-source-directory/) | `.chezmoiroot` separates `home/` from repo tooling |
| Host differences | [Machine differences](https://www.chezmoi.io/user-guide/manage-machine-to-machine-differences/) | Use data, small templates and full-file fragments |
| Ignore rules | [.chezmoiignore](https://www.chezmoi.io/reference/special-files/chezmoiignore/) | Patterns match destination paths; do not copy Stow regexes |
| Attributes | [Source attributes](https://www.chezmoi.io/reference/source-state-attributes/) | Native private/executable files; avoid exact ownership of shared directories |
| Mutable files | [Modify targets](https://www.chezmoi.io/reference/target-types/#modify-file) and [file guide](https://www.chezmoi.io/user-guide/manage-different-types-of-file/) | Native modify templates read `.chezmoi.stdin`; no `.tmpl` suffix |
| JSON transform | [Built-in jq](https://www.chezmoi.io/reference/templates/functions/jq/) | Go implementation, no external jq executable; returns a list of results |
| Recursive merge | [jq multiplication](https://jqlang.org/manual/#multiplication-division-modulo) | Object recursion and right-side replacement; test gojq on the chosen release |
| TOML transforms | [fromToml](https://www.chezmoi.io/reference/templates/functions/fromToml/), [toToml](https://www.chezmoi.io/reference/templates/functions/toToml/) | Native parse/serialize rather than comment-preserving edits |
| Path operations | [setValueAtPath](https://www.chezmoi.io/reference/templates/functions/setValueAtPath/), [deleteValueAtPath](https://www.chezmoi.io/reference/templates/functions/deleteValueAtPath/) | Validate ancestor types; use tested argument forms |
| Command isolation | [Global flags](https://www.chezmoi.io/reference/command-line-flags/global/) | Explicit source, destination, config, cache, state and conflict behavior |
| Local configuration | [Variables](https://www.chezmoi.io/reference/configuration-file/variables/) | Keep paths/state local; distinguish working tree from source root |
| Apply | [apply](https://www.chezmoi.io/reference/commands/apply/) | Local edits need conflict handling; never use blanket force |
| Update | [update](https://www.chezmoi.io/reference/commands/update/) | Default autostash/rebase must be replaced by configured fast-forward behavior |
| Ordering | [Application order](https://www.chezmoi.io/reference/application-order/) | Target calculation precedes before scripts; no scripts writing the same managed targets |
| Hooks | [Hooks](https://www.chezmoi.io/reference/configuration-file/hooks/) | Hooks run even during dry-run; keep mutating/network hooks out of normal config flow |
| Scripts | [Script guide](https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/) | Content-based execution records are not installation probes or schedulers |
| Externals | [External sources](https://www.chezmoi.io/reference/special-files/chezmoiexternal-format/) | Downloads/checksums/cache and Git updates, not payload installer lifecycle |
| Packages | [Declarative packages](https://www.chezmoi.io/user-guide/advanced/install-packages-declaratively/) | Still invokes native package managers; avoid migrating a framework into templates |
| Windows | [Windows](https://www.chezmoi.io/user-guide/machines/windows/) | Symlink permissions remain special; prefer regular files |
| Migration | [Migrating symlinks](https://www.chezmoi.io/migrating-from-another-dotfile-manager/) | `add --follow` captures contents; do not import a whole real application directory |
| Daily editing | [Daily operations](https://www.chezmoi.io/user-guide/daily-operations/) | Teach explicit edit/apply and add/merge workflows |
| Version floor | [.chezmoiversion](https://www.chezmoi.io/reference/special-files/chezmoiversion/) | Record the tested minimum, not an invented compatibility claim |

## Tagged implementation findings

The official release selected for Stage 1 is
[v2.74.0](https://github.com/twpayne/chezmoi/releases/tag/v2.74.0), published on
2026-11-01. Its verified Linux binary reports commit
`fcc38cf6fdb3a79ae4afae9ef6ad241890db6cde`, build time
`2026-11-01T13:53:24Z`. This is the tested native floor; older releases were not
tested. CI-only provisioning lives in `.github/scripts/install-test-chezmoi.py`.
Production installation is unchanged in Stage 1.

The artifact and [checksum manifest](https://github.com/twpayne/chezmoi/releases/download/v2.74.0/chezmoi_2.74.0_checksums.txt)
were downloaded separately over HTTPS from the official release. SHA256 was
checked before execution. The CI provisioner embeds the reviewed digests below;
it downloads outside tests and extracts only the executable. This verifies
integrity against the selected upstream manifest, not an independently verified
signature. No signature/attestation verification is claimed.

| CI artifact | SHA256 | Actual execution this session |
| --- | --- | --- |
| `chezmoi_2.74.0_linux_amd64.tar.gz` | `1b98a567f726f41540414aea4caf912699d53e248b29ccf8369cf553657b2374` | Linux x86_64; manual checksum and CI provisioner both verified |
| `chezmoi_2.74.0_darwin_amd64.tar.gz` | `3d30cb05efae2f4a68519d6d0e8856765f2b21a0686e66498ee6d2de7707e5e6` | Not run |
| `chezmoi_2.74.0_darwin_arm64.tar.gz` | `9d89672a597a9333ab47ea5173fcececb85c04864205686a7aa5699c3d8bd98c` | Tar not run; same-release raw arm64 artifact tested below |
| `chezmoi_2.74.0_windows_amd64.zip` | `13dee2831d371c6ce2ac30fc9ae1aad4f70c68e7d44700f6129fe4b244ee7a95` | Verified/executed in a private native Windows fixture |

The release supplies other platform artifacts; this small provisioner selects
only the CI architectures above. The native Mac follow-up used the official raw
`chezmoi-darwin-arm64` artifact from release v2.74.0, SHA256
`9d4d7aeecb40b2616af766f88cf6ea45ed2b1fc0a9793df7b075b63847ae47f8`,
verified locally and after transfer against the same official manifest. Actual
Linux/Mac/Windows fixtures ran at that checkpoint; hosted CI had not yet run.
The later bridge's exact hosted runs are recorded in Stage 4 evidence. Intel Mac
execution is not established by arm64 results.

## Observed Stage 1 deployment contract

`tests/test_chezmoi_foundation.py` exercises real explicit `--source`,
`--destination`, `--config`, `--cache`, `--persistent-state`, `--no-tty` and
`--error-on-conflict`. Children have closed stdin by default and an empty tool
PATH; only the selected absolute binary executes. A minimal OS/locale environment
and temporary HOME/USERPROFILE/XDG/APPDATA/temp paths exclude inherited user
configuration, credential, Git-index and agent overrides.

| Probe | Observed v2.74.0 behavior | Consequence |
| --- | --- | --- |
| Plain/private apply, second apply/diff | Regular files, convergent output; Unix private file 0600 | Native file mode is viable; Windows ACL evidence remains separate |
| Destination and source both edited | `apply --error-on-conflict --no-tty` exits 1, preserves live edit, emits no diagnostic in this case | Thin adapter must report a nonzero status even when native stderr is empty |
| Dry run without hooks | Destination/source unchanged, fixture-local state permitted | No global write-free or hook-side-effect promise |
| Owned symlink import | `add --follow TARGET` copies bytes into source and leaves the link | Import is not takeover |
| Owned symlink replacement | Ordinary apply refuses; narrowly targeted `apply --force TARGET` converts the verified fixture link to a regular file, original source unchanged | Stage 4 must prove ownership and snapshot first; never force routine or broad apply |

These are per-target observations. They do not establish all-home atomicity or
permission/ACL behavior on a platform that was not executed.

## Observed Stage 2 source-state contract

The same official v2.74.0 binaries were reverified before use. Linux's retained
release tar SHA256 matched the pinned digest and its member bytes matched the
executable. Mac's retained raw binary and Windows's retained extracted binary
were rehashed against Stage 1 evidence before temporary execution. No parser
environment or package was created. All native source/destination/config/cache/
state/HOME paths remained isolated; old-suite runtime reuse is separate.

| Probe | Native observation | Consequence |
| --- | --- | --- |
| Root + linked Git worktree with spaces | `.chezmoiroot=home` and `include (joinPath .chezmoi.workingTree ...)` resolve canonical bytes outside home/; quotes, CRLF and literal `{{ ... }}` survive | Use literal includes for every text payload, not `includeTemplate` |
| Init guard | Init cannot resolve named templates from `.chezmoitemplates`; explicit `includeTemplate` of the internal guard works | One guard validates init and target calculation; it never evaluates legacy payloads |
| Local host data | Missing/empty/non-string/unknown and actual-OS-incompatible host fails; `DOTFILES_HOST` does not fill missing data | Local `[data].host` is explicit; common-only is a selected Unix role |
| Minimum version | Raising fixture `.chezmoiversion` above the running version refuses before destination writes | Root minimum is effective with the selected home/ source root |
| Exact ordinary targets | Seven role sets are 47/54/53/57/52/52/24 files; all bytes equal current canonical legacy files | Two AI mutable targets remain omitted for Stage 3; four legacy helpers stay absent |
| Opaque assets/newlines | WebP and terminfo raw bytes match; text pet JSON and Windows CRLF/mixed-newline files survive literal include | Exactly two temporary raw copies, both removed as duplication in Stage 6 |
| Empty/private/executable files | Native empty_ preserves zero-byte rc files; fcitx5 private profile is 0600 on Unix; executable_ respects umask (0700 under 077) | Assert effective owner execution/private scope, not group/other bits forbidden by umask |
| Unmanaged state and repeat apply | Synthetic SSH trust/key siblings, app auth/AI gap files, default.rules and payload siblings survive; source unchanged; second apply/diff clean | Shared parents remain non-exact; no routine force or hidden writer |
| Windows profile discovery | Both actual native CurrentUserAllHosts paths match default Documents mapping; queried metadata only | A redirected Documents path still blocks takeover until explicit mapping/preflight |

The final focused suite has 33 tests: the 23 Stage 1 probes, nine source-state
tests and one rendered-output lint test. Native Linux and macOS execute their
compatible role sets; Windows executes win. A separately named test overrides
OS template data to cover every role on each runner, without claiming native
platform or ACL evidence from that supplemental rendering. Rendered shell,
Python, JSON and Lua checks retain explicit optional tool skips. Full commands,
native versions/results, manifest evidence and review are in `status.md`.

Extra native legacy Mac testing is not wholly green: tmux 3.8 has three
adversarial-cwd menu subtest failures (12/13 methods pass) with unchanged tracked
configuration, including a separate reproduction with a verified initial cwd.
Stage 2 retains that explicit limit without changing runtime behavior or floors.
The passing 33-test native source suite establishes exact deployment bytes and
attributes, not a fix for that pre-existing application behavior.

The official [include interface](https://www.chezmoi.io/reference/templates/functions/include/),
[source-root file](https://www.chezmoi.io/reference/special-files/chezmoiroot/),
[minimum-version file](https://www.chezmoi.io/reference/special-files/chezmoiversion/)
and [template variables](https://www.chezmoi.io/reference/templates/variables/)
were consulted again. Executable fixtures establish the selected-release
behavior above; live reference pages alone are not a compatibility guarantee.

## Observed native transforms and secret backend

| Probe | Actual native result | Adopted boundary / next stage |
| --- | --- | --- |
| JSON modify template | Directive `chezmoi:modify-template`, `.chezmoi.stdin`, no `.tmpl`; native `jq` returns a result list | Require one result and serialize `first`; production policy validation remains S3 |
| JSON recursive merge | `.live * .portable` retains live model/unknown nested fields; portable empty arrays/false/null survive | Native merge viable without external jq/Python |
| Missing/empty JSON | Initializes an object; malformed/trailing/non-object input fails and preserves affected target | Never turn an invalid parse into an empty successful modify |
| JSON duplicate/numeric limits | Duplicate keys last-value-wins; 9007199254740993 remains an integer; 1e400 becomes the string `"1e400"` | Document native limits; no arbitrary-precision/legacy duplicate detector promise |
| Typed TOML round trip | Unknown tables, quoted dotted project key, arrays of tables, multiline strings, int64 and explicit-offset timestamp survive; normalization converges | Canonical layout/comments replace legacy formatting preservation |
| Literal TOML paths | `setValueAtPath (list "features" "*") false $live` and literal dotted key work | Use list assignment for literal components |
| Path deletion | `deleteValueAtPath "retired.setting" $live` works; list input fails with expected-string error | Tagged implementation wins over moving docs |
| Ancestor conflict | Native setter can discard a scalar ancestor; template map validation fails first and preserves live bytes | S3 must validate owned ancestors before assignment |
| TOML local values | UTC round trip works on Unix; LA shifts local time/datetime by eight hours; Tokyo can shift a local date to the previous day | Unresolved S3 preservation condition, not an accepted value-loss contract |
| TOML CRLF multiline basic string | Raw CRLF is retained by native parse/serialize, while stdlib normalizes it; native `replace "\r\n" "\n"` before parse selects LF and preserves explicit escapes | Candidate S3 normalization policy; not universal literal-string or consumer-parser evidence |
| Builtin age | Root `age-keygen`, `encrypt`, `decrypt`, encrypted/private apply work with empty PATH | Selected backend is builtin age with native identities; no external age/key daemon |
| Secret failure | Missing identity, malformed ciphertext or explicitly unavailable external backend fail without replacing affected existing secret | Closed stdin, no TTY and finite timeout; no live vault lock/unlock test claimed |
| Per-file recipients | Explicit `encrypt --age-recipient A` replaces configured default B; B cannot decrypt A-only ciphertext; A+B ciphertext is readable by both | Separate host identities and explicit per-file recipient scopes are feasible |
| Optional encrypted create seed | Existing refreshed file survives; remembered deletion conflicts, but state loss plus apply recreates seed | No persistent auth seed in recurring source; only separately tested bootstrap enrollment |

All checks use disposable values and an empty child PATH, with no `.venv-sync`.
The parent unittest process uses Python stdlib; the new merge/encryption path
does not. Synthetic decryption output is captured only for assertions, never
reported. Source contains no plaintext canary. Reporting checks explicitly diff
only the public target; ordinary diff is not a secret-redaction boundary.

The local TOML issue follows the tagged
[chezmoi dependency](https://github.com/twpayne/chezmoi/blob/v2.74.0/go.mod)
on BurntSushi/toml v1.6.0. Its
[encoder](https://github.com/BurntSushi/toml/blob/v1.6.0/encode.go)
converts special local date/time locations with `v.In(time.UTC)`. The tested
minimal input is `clock = 12:34:56`, `local = 2026-11-01T12:34:56`,
`day = 2026-11-01`. UTC process TZ mitigates the observed Unix case. Actual
Windows probes with TZ=UTC/LA/Tokyo all retained a +8-hour local time/datetime
shift on the tested host, so UTC environment configuration is insufficient there.
A native cross-platform correction remains unresolved. Stage 3 must resolve
this or reject affected content safely before writing it. The passing
characterization test proves the limitation, not preservation.

The [TOML string specification](https://toml.io/en/v1.0.0#string) allows parser
choices for multiline newline normalization. The new basic-string CRLF probe
therefore documents a difference, not a standards violation. It uses exact
`write_bytes` input and separately proves native LF normalization without
altering explicitly escaped CRLF. No production transform changed; multiline
literal strings and actual application-parser expectations still need S3 tests.

## Native platform follow-up evidence

The final same-source suite has 23 probes. Native macOS 27.2 arm64 with existing
Python 3.15.2 and system Bash 3.2.57 passed all 23, including the shell entrypoint.
Native Windows 11 10.0.26300 AMD64 with Python 3.12.10 and PowerShell 7.6.9
passed 22 and skipped the Unix-only TZ assertion, including the PowerShell
entrypoint. Separate Windows temporal probes above fill that platform-specific
observation. Linux passes all 23, including under restrictive umask 077.
Reports and actual hash/skip/ACL limits are in [status.md](status.md).

Native Mac testing showed that `add --follow` can encode `private_` from the
original mode. Query `source-path TARGET` rather than assuming a source filename.
Windows testing showed current-directory executable lookup and implicit text
newline expansion can invalidate fixture assumptions. Both are now explicit
test inputs; native deployment semantics were not changed to satisfy the tests.
All remote writes were private temporary synthetic fixtures. These runs are not
published CI, full native legacy suites, real application checks or migration.

JSON conversion limits follow
[`replaceJSONNumbersWithNumericValues`](https://github.com/twpayne/chezmoi/blob/v2.74.0/internal/chezmoi/format.go),
not an assumed float64-only parser. The builtin age commands proved here are
root `encrypt`/`decrypt` using `[age]` identity/recipients. `age encrypt` is a
different wrapper and is not the tested recipient-encryption command.

The [inventory](inventory.md) records the current tracked targets and tool
floors. It also records a primary-source discrepancy in existing Claude ID
prose: the current [official memory docs](https://code.claude.com/docs/en/memory#agentsmd)
identify `agents-md@builtin` as the pre-2.1.285 ID and
`cc-plugin-agents-md@builtin` as canonical now. Preserve both values in Stage 1;
actual supported-client behavior remains a Stage 3/5 verification task.

The tagged [template implementation](https://github.com/twpayne/chezmoi/blob/v2.74.0/internal/cmd/templatefuncs.go)
and [format implementation](https://github.com/twpayne/chezmoi/blob/v2.74.0/internal/chezmoi/format.go)
show the following relevant boundaries:

- TOML is parsed to a value map and serialized again. Original comments and
  formatting are not retained; this is an intentional new contract.
- `setValueAtPath` can replace non-map ancestors. Add small policy validation
  before assigning owned paths so unrelated data cannot disappear silently.
- In this tag, `deleteValueAtPathTemplateFunc` takes a string even though the
  current reference describes string or list. Existing retired paths can use
  unambiguous dotted strings. Verify the selected binary instead of copying an
  untested list-path deletion example.
- JSON parsing rejects malformed syntax/trailing data but does not implement the
  legacy Python duplicate-key detector. Record native numeric limits too; do not
  claim arbitrary-precision parity or build another parser to achieve it.

## Stage 3 native preservation decisions

The official v2.74.0 checksum manifest was fetched again before execution.
Retained Linux/Windows archives matched the manifest, and their executable
members matched the selected binaries. Mac's raw executable matched its official
digest before native execution. Every transferred source/probe snapshot has a
separate hash manifest; no real HOME or application state enters the capsules.
These checks establish official-manifest integrity, not signature verification.

The initial safety probe ran on actual Linux, macOS and Windows before Claude
and Codex work was parallelized. Each platform passed 18 local-temporal
reject-and-preserve cases and three offset/int64/string/convergence cases under
UTC, Los Angeles and Tokyo settings. The raw Windows reproduction still shifted
local time/datetime by eight hours under all three settings. Therefore the native
candidate rejects all TOML local dates/times/datetimes before serialization;
the passing guard tests prove safe refusal, not corrected wall-value support.

The tagged [timezone markers](https://github.com/BurntSushi/toml/blob/v1.6.0/internal/tz.go)
and [parser](https://github.com/BurntSushi/toml/blob/v1.6.0/parse.go) expose local
values as `time.Time` with `date-local`, `time-local` or `datetime-local`
locations. A small recursive native template checks parsed maps/arrays and those
locations in both input documents. Offset timestamps pass unchanged. No lexer,
external parser, JSON conversion or custom TOML writer is added. The production
tests cover nested arrays/inline tables/AoT, literal dotted and star keys and
values in unowned or retired branches as well as simple top-level cases.

For JSON, Stage 3 avoids Stage 1's observed `fromJson` number conversion entirely.
The selected release pins gojq v0.12.20; its
[fromjson implementation](https://github.com/itchyny/gojq/blob/v0.12.20/func.go)
uses `json.Decoder.UseNumber` and rejects trailing tokens. Chezmoi's
[jq template function](https://github.com/twpayne/chezmoi/blob/v2.74.0/internal/cmd/templatefuncs.go)
returns those native results without `replaceJSONNumbersWithNumericValues`.
Raw strings parsed through builtin `jq "fromjson"`, object multiplication and
`toPrettyJson` retain numeric tokens, including int64-exceeding integers,
overflow/underflow exponents, long fractions and negative zero. The 33-case
numeric/merge/malformed/type probe passed on all three actual platforms.
No arithmetic on those retained numbers is used. Permission element checks use
`typeIs "string"`; `json.Number` has string kind and must not pass that check.

Native JSON duplicate keys remain last-value-wins. Go JSON can replace invalid
UTF-8 or unpaired surrogates with U+FFFD. The candidate rejects parsed U+FFFD in
keys/strings in either input before merging, deliberately also refusing valid
intentional U+FFFD. The affected bytes survive; valid surrogate pairs and literal
backslash-u text remain supported. This is a safe documented input limit, not a
duplicate detector or custom Unicode parser.

Physical CRLF is normalized to LF before native TOML parsing. Exact-byte tests
cover both multiline basic and literal strings, multiline continuations, and
explicit escaped CRLF. This selects the tested consumer newline semantics;
canonical serialization is intentional, and comments/layout are not retained.
The final complete native suite ran 64 test methods on each actual platform:
Linux had no skips; Mac skipped one optional StyLua subtest; Windows skipped the
historical Unix-only raw-TZ characterization and optional StyLua subtest. New
production temporal refusal tests ran on Windows. Linux and native Windows full
runners passed. Exact logs/versions/limits are in [status.md](status.md); these
are isolated fixtures, not real application or fleet takeover evidence.

Current [Claude memory documentation](https://code.claude.com/docs/en/memory#agentsmd)
was rechecked: pre-2.1.285 uses `agents-md@builtin`; newer clients accept both
and use `cc-plugin-agents-md@builtin` as the current name. Stage 3 preserves both
policy entries and corrects explanatory prose. No client, tmux, Bash or PowerShell
floor changes here. The [native update reference](https://www.chezmoi.io/reference/commands/update/)
also confirms the default autostash/rebase and supported update command/arguments
override; Stage 4 must verify its fast-forward-only configuration in Git fixtures
before activating D6. No updater behavior changed in Stage 3.

## Local evidence map

Paths are relative to the repository root. Re-read current files after each stage;
line numbers and paths will change.

- `lib/config_sync.py`, `docs/config-sync.md`, `tests/test_config_sync.py`:
  ownership, merge semantics and legacy writer guarantees.
- `stow-all.sh`, `stow-all.ps1`, `.stowrc`, `lib/windows-link-trust.ps1`:
  deployment, conflict checks and symlink trust.
- `scripts/dotfiles-update.*`, `scripts/dotfiles-auto-stow.ps1`,
  `docs/update-contract.md`: live auto-pull, state and Windows worker.
- `scripts/payload-update.*`, `config/payloads.tsv`, `docs/payloads.md`:
  upstream ownership and consumer-side scheduling.
- `setup-host.*`, `doctor.*`, `lib/bootstrap/`, `lib/bootstrap.ps1`,
  `config/bootstrap/`: provisioning and prerequisite checks.
- `tests/run.*`, `tests/lib/environment.*`, `.pre-commit-config.yaml`,
  `.github/workflows/`, `tests/e2e/`: isolation, dependency gates and platform proof.
- `common/tmux/`, `tests/test_tmux.py`: include changes from `738f619`; removal
  of the sync venv must not remove unrelated Python helpers or tmux behavior.

The original feasibility count of 91 package files predates that tmux commit.
Counts in future handoffs must be recomputed, and code-size reductions must be
measured after implementation rather than estimated as a percentage here.

## Consolidated compatibility handoff

The originating review session confirmed its completed baseline at `1a9d30b` and
the user's explicit current-layout/modern-tool support decision. Its outstanding
`current-layout-only-assessment-20261102.md` and standalone next-session prompt
have been absorbed into [support-boundary.md](support-boundary.md) and the stages.
Historical review archives are not required to execute this plan. They are not
additional sources of active rules or evidence that chezmoi implementation passed.

The former all-host-attestation retirement requirement is superseded by the
declared support cutoff/manual upgrade contract. The old handoff's requirement to
keep the Python/Stow implementation intact applied to its narrower cleanup task;
the native migration's explicit architecture and parser retirement now govern.

## Fleet and secret scope added after review

The user subsequently authorized direct agent execution on the six hosts, with
tests during final legacy retirement. [Fleet rollout](fleet-rollout.md) records
the 2026-11-02 connection-only preflight and the required rollout order. No host
was migrated and no secret value was read in that preflight.

[Secrets and SSH](secrets-and-ssh.md) adds official references for native encrypted
files, builtin age, password-manager integration and mutable application auth.
This extends the original credential exclusion only for explicitly selected
ciphertext/vault-backed material. It does not authorize plaintext credentials in
Git or repeated overwriting of current OAuth refresh state.
