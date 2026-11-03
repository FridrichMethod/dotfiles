# Native secrets and SSH management

Stage 4 private proposal and user choices are summarized without account names
in [stage-4-evidence.md](stage-4-evidence.md#secret-choices-and-custody). Eight
static-for-consumer files are approved for lab, Mac, WSL, Sherlock and Marlowe
plus independent recovery; five mutable Codex auth files remain excluded.
SSH snippets retain ordinary mappings by explicit choice. Apple Passwords is
selected for recovery custody. Independent R was generated in a private Mac
handoff directory. The user reported local recipient matching and retrieved-R-only
challenge PASS, then explicitly confirmed retrieving the full saved identity
on another device. Recovery custody and all five local host identities are
established. Eight production inputs were encrypted privately to the exact six
recipients. Each host and retrieved R passed all-eight equality checks, and a
disposable outsider failed all eight. Only the eight ciphertexts enter the
candidate source; publication and actual target deployment remain pending. A local
`.secrets` directory on the same disk cannot establish independent recovery.

## Scope added by the user

The user asked to include the account files under `~/.secrets` and SSH connection
information in the chezmoi design. Earlier plans excluded credentials entirely;
this document adds a narrow encrypted/vault-backed path, not plaintext secrets
in Git or indiscriminate synchronization of application state.

Planning inspection read only file names/types and permissions: the local
`~/.secrets` directory is 0700 and its twelve regular files are 0600. Token values
were not read, printed, copied or classified from their contents. Account labels
and private endpoint details are omitted here. File names do not establish whether
a token is static or whether a launcher/application refreshes it.

## Ownership decisions

| Material | Intended treatment |
| --- | --- |
| Allowlisted static API/gateway/account secrets | Native encrypted files, or native integration with an existing password manager; preserve consumer paths |
| Application-written auth/refresh state, including such files under `.secrets` | Application/launcher remains the writer; no recurring apply of a stale snapshot |
| SSH connection snippets | Native files/templates; encrypt private endpoint snippets where confidentiality is wanted |
| SSH private keys | Outside the default distribution scope; supporting encryption does not authorize copying every key to every host |
| Codex/Claude credential stores and OS keychains | Preserve active auth and backend ownership; do not export/import the whole store |
| SSH known_hosts, sockets, agent state and caches | Host-local state; preserve trust and existing access |

Stage 1 must inspect documented consumer interfaces, not guess from JSON suffixes.
For each selected secret record type, owner/writer, destination, target hosts,
rotation method and source authority in a private local inventory. Keep only
generic categories and test evidence in public docs. Do not modify upstream
coding-agent-kit to create a second token synchronization/refresh implementation.

## Native backend and key bootstrap

Prefer testing builtin age first: it matches the goal of no extra parser/runtime
environment. Its builtin implementation supports native age identities and
recipients, but not passphrases, symmetric mode or SSH-key identities. Do not
assume the existing SSH key is also the decryption key. An existing password
manager is an alternative if its CLI/session availability suits all target hosts.
These are native integrations, not a custom encryption helper.

Before activating real secrets, select the backend and decide which hosts can
decrypt which content, where identities live, and how a new host gets its first
identity without depending on the ciphertext it needs to decrypt. Prefer separate
host identities with explicitly scoped recipients where practical; verify the
selected release's ability to represent those scopes without a new framework.
If the simple source design grants every recipient access to all encrypted files,
document that fact and resolve the trust choice before distribution. Host ignore
patterns and templates control deployment, not cryptographic access.

Keep decryption identities outside Git, generated source and normal backups/logs.
Public recipients may be recorded where appropriate; private keys may not. Use
existing authorized secure transfer/local provisioning, never command-line secret
arguments or a credential paste into chat. Missing access is a specific bootstrap
blocker, not permission to invent credentials or bypass login/MFA.

`encrypted_` protects source contents; `private_` sets destination permissions.
Applications still normally consume plaintext files, with private parent/file
permissions and actual Windows ACL checks. Encryption does not hide source file
names. Do not put values into `.chezmoidata`, portable AI preferences, test output
or plaintext tracked templates. Use only ciphertext or appropriate vault references.

### Explicit local enrollment gate

The local native config must set `[data].enrollStaticSecrets = true` before
`.secrets` enters the target set. The approved roles are `mac`, `wsl-ubuntu`,
`lab-ubuntu`, `sherlock` and `marlowe`. An absent or false flag ignores the entire
directory on every role; `win` and `common-only` ignore it even with a true flag.
A present non-boolean value fails before
destination writes. This gate never removes existing local secrets and is not
a cryptographic access boundary: each ciphertext still needs the explicitly
approved host and independent recovery recipients.

Every selected ciphertext includes the five host public recipients and recovery
recipient R. R alone can recover all eight static files; host private identities
remain local and only public recipients are exported. Cluster deployment also
requires current site rules and verified channel-0.7 launcher consumers. Tool
provisioning and actual account acceptance are separate from enrollment scope.

Keep the flag absent until identity/bootstrap, recovery custody and exact-file
ownership checks are complete. Native init preserves this local data and age
configuration. Enroll only the eight privately approved static files as
`encrypted_private_` leaves under `home/private_dot_secrets`, never an `exact_`
directory or `create_` auth seed. SSH remains on its ordinary source paths.

Ordinary source fixtures copy the entire candidate, including opaque ciphertext,
with enrollment disabled. Their exact ordinary inventory remains unchanged and
CI needs no production identities. Separate native tests use only disposable
identities and synthetic ciphertext to exercise opt-in, host selection, private
permissions and missing-identity failure. Real recipient/decryption equality and
consumer acceptance remain private rollout checks; do not print secret diffs or
decrypted bytes to establish them.

## Mutable auth is a separate lifecycle

Codex can refresh cached login tokens during use; Claude owns its credential file
or platform keychain. A repeated declarative apply of old credentials can undo
that state. Preserve it during both configuration migration and host retirement.

One-time seeding is not inherently unsupported: Codex documents copying a local
auth cache to a headless machine. If a selected account profile needs initial
seeding, evaluate native `create_` with encrypted/private attributes in synthetic
tests and make the seed an explicit bootstrap-only choice. Test an existing
refreshed target, missing target, expired seed and logout/removal. A permanently
active create-if-missing target can recreate credentials after logout, so do not
make it the default login-update path. Do not commit active OAuth caches by
default or build a refresh-token replication service.

## Logging, unattended apply and access recovery

Ordinary diff/output is not a secret-redaction boundary. Use a nonsecret target
allowlist for logs and CI. Excluding encrypted targets from diff helps only for
those targets; password-manager templates can also emit secrets. Review necessary
real-secret differences privately, never through captured chat/CI output.

Test unavailable identity, locked backend and malformed ciphertext with synthetic
data. The unattended adapter must fail without prompting, replacing the affected
secret with empty content, or blocking shell startup indefinitely. Do not promise
whole-home atomicity. Backend availability checks must not add a daemon, background
key agent or repeated login service on HPC systems.

SSH snippet changes must preserve Include, host selection, jump/master options
and host-key trust. Keep an existing recovery channel until the appropriate new
connection test succeeds; follow [fleet-rollout.md](fleet-rollout.md). Changing
today's source to encrypted snippets does not remove plaintext host information
from old Git history. History rewriting is outside this migration's scope.

## Stage allocation and acceptance

| Stage | Work and evidence |
| --- | --- |
| 1 | Classify metadata/consumers; select/test backend and host trust model; add synthetic encryption, permissions, noninteractive-failure, no-secret-output and optional seed probes |
| 2 | Map SSH root/snippets and optional encrypted private snippets; preserve trust/access semantics and host applicability |
| 3 | Retain builtin-age synthetic coverage and ciphertext/vault-only rules; no static-secret target selected while allowlists/trust/bootstrap remain unresolved; preserve mutable auth and consumer paths |
| 4 | On authorized rollout targets, provision the selected decryption access and enroll/deploy selected real secrets without exposing values; verify consumers and SSH access |
| 5 | Test locked/missing backend through the thin login adapter; retire only redundant secret copy/export glue, if any actually exists |
| 6 | Verify secrets and app auth on each migrated host before exact legacy cleanup; never recursively delete `.secrets`, `.ssh` or application credential stores |

Stages 1-3 use synthetic values, not copied production credentials. The planning
session did not encrypt, enroll or distribute any real credential. Stage 1 now
selects builtin age from actual synthetic evidence below; actual static-file
allowlists, host trust grouping and secure initial identity access remain to be
established privately before real Stage 4 enrollment.

Stage 3 deliberately adds no production encrypted target or dummy credential.
Exact whole-source target tests prove that only the two AI configs are added;
SSH trust, `.secrets`, app auth and payload siblings remain unmanaged. Existing
builtin-age recipient/missing-identity/malformed-ciphertext and seed-lifecycle
tests continue to run. Real allowlists, recipient groups, initial key access
and consumer classification are concrete Stage 4 enrollment prerequisites,
not facts established by these synthetic checks.

## Stage 1 backend and bootstrap decision

Use builtin age with separate native host identities outside Git. The Stage 1
suite proves root `age-keygen --output IDENTITY`, `age-keygen --convert IDENTITY`,
`encrypt` and `decrypt` with `--use-builtin-age=true`, an empty tool PATH, private
parent/file deployment and unchanged ciphertext source. Missing identity,
malformed ciphertext and an unavailable external backend preserve the affected
existing secret. No real vault or locked password-manager session was exercised.

Per-file encryption is feasible without a custom abstraction: explicit
`--age-recipient A` overrides a configured default B, and B cannot decrypt that
file. A multi-recipient A+B file is readable by either identity. Enrollment must
choose its recipient set explicitly and verify it privately; host ignores and
templates control deployment only. A default recipient change does not rotate
already encrypted files. Do not assume every host is allowed every secret.

First-identity bootstrap must be independent of this encrypted source: generate
locally or provision through an existing authorized secure channel, protect its
file/ACL and maintain a private recovery copy with a documented owner. Do not
reuse SSH keys as native age identities, distribute private keys in the repo,
paste them into chat, or invent an unattended unlock service. Concrete host
trust groups and recovery custody remain Stage 4 enrollment choices, subject to
the user's existing authorization and actual access boundaries.

The synthetic `create_` test preserves refreshed contents. Deletion under the
remembered guarded state conflicts; deleting that disposable state and applying
again recreates the seed. Persistent create-if-missing is therefore unsuitable
as recurring auth deployment. Optional initial seeding must be explicit and
removed from recurring source after bootstrap. Static-for-consumer candidates
and application-written refresh stores are classified separately in
[inventory.md](inventory.md). The approved eight-file classification now has a
public channel-0.7 consumer review. Sherlock's installed kit v0.6 still requires
the reviewed upgrade and actual interface check before enabling/applying secrets
on that host. Approved host identity generation, encrypted source preparation
and private decryption checks can proceed independently. The approved recipient
grant gives that host cryptographic access even while deployment is disabled;
public source review alone does not upgrade its consumer.

Synthetic output checks use a public-target allowlist for diff and inspect
successful apply output/source for the disposable canary. This does not promise
redaction of ordinary diff, arbitrary errors or password-manager templates.
Unix 0700/0600 evidence is not a Windows ACL test. See [sources.md](sources.md)
and [status.md](status.md) for commands and actual platform scope.

## Official references checked during planning

- [Encryption](https://www.chezmoi.io/user-guide/encryption/) and
  [source attributes](https://www.chezmoi.io/reference/source-state-attributes/):
  source encryption, private targets and create-if-missing semantics.
- [age](https://www.chezmoi.io/user-guide/encryption/age/): builtin limitations
  and identity/recipient configuration.
- [Password managers](https://www.chezmoi.io/user-guide/password-managers/) and
  [1Password](https://www.chezmoi.io/user-guide/password-managers/1password/):
  native integrations and interactive-session constraints.
- [Diff](https://www.chezmoi.io/reference/commands/diff/): output and exclusions.
- [Codex authentication](https://learn.chatgpt.com/docs/auth): mutable login
  caching, credential stores and documented headless initial transfer.
- [Claude authentication](https://code.claude.com/docs/en/authentication):
  platform credential stores and application-managed login state.
