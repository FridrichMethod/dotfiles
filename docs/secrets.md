# Secrets

The source carries a small set of static account secrets, encrypted with
chezmoi's builtin age, and deploys them only to homes that opt in. Everything
else that is secret stays with the application or host that writes it. This
page holds metadata only: no identity, no recipient's private data and no
secret value belongs in it or anywhere in the repository.

## What is managed

| Material | Treatment |
| --- | --- |
| Static account files under `~/.secrets` that a consumer only reads (the coding-agent-kit's `claude-as` tokens) | `home/private_dot_secrets/encrypted_private_<name>.age`: builtin-age ciphertext, deployed as a private regular file on an enrolled home |
| Application-written auth and refresh state, also when it sits under `~/.secrets` (Codex logins, Claude credential files and keychains) | The application stays the writer; never a managed target, a `create_` seed or a snapshot |
| SSH connection snippets (`~/.ssh/config.d/*.conf`) | Ordinary source files |
| SSH private keys | Outside the repository; encryption support does not authorize copying a key to other hosts |
| `known_hosts`, sockets, agent state and caches | Host-local state |

`encrypted_` protects the source contents; `private_` sets the destination
mode (0600 in a 0700 `~/.secrets`). Encryption does not hide file names. No
value goes into `.chezmoidata`, the portable AI policy, test output or a
plaintext template. `.gitleaks.toml` refuses any file under a `.secrets`
directory or its source encoding except
`home/private_dot_secrets/encrypted_private_claude-<name>.age`, `<name>` of
lowercase letters and digits.

## Enrollment gate

The local config must set `[data].enrollStaticSecrets = true` before
`.secrets` enters a home's target set (`home/.chezmoiignore`). Only the roles
`mac`, `wsl-ubuntu`, `lab-ubuntu`, `sherlock` and `marlowe` can enroll; an
absent or false flag ignores the whole directory on every role, and `win` and
`generic` ignore it even with a true flag. A value that is not a boolean
fails before any destination write. The gate never removes an existing local
secret, and it is not a cryptographic boundary: host ignores and templates
control deployment, while the recipients of each ciphertext control who can
decrypt it.

## Recipients and identities

Every ciphertext is encrypted to the public recipient of each enrolled host
plus one recovery recipient, R, and to nobody else; R alone can recover every
file. `tests/test_chezmoi_secrets.py` pins the set: exactly the enrolled
ciphertexts, each with one X25519 stanza per recipient (six today: five hosts
and R).

Each enrolled host has its own age identity, generated on that host and kept
outside Git:

- `~/.config/chezmoi/age/` (0700) holds `identity.txt`, the host's private
  identity (0600), and `recipient.txt`, its public recipient.
- The local config sets `encryption = "age"` and `[age].identity` to that
  file; the config template keeps both through every re-init.
- The live identity is never deleted, moved or copied to another host, and
  never printed, pasted into chat or passed as a command-line argument.

Recovery custody: the user keeps an offline copy of R's identity outside
every host and the repository, retrievable on another device. A `~/.secrets`
directory on the same disk is no recovery copy. Missing access to an identity
is a bootstrap blocker for that host, not a reason to invent or bypass
credentials.

## Enrolling a host

1. On the new host, generate its identity locally into
   `~/.config/chezmoi/age/` under umask 077
   (`chezmoi age-keygen --output "$HOME/.config/chezmoi/age/identity.txt"`,
   then `chezmoi age-keygen --convert` of that file into `recipient.txt`,
   both with `--use-builtin-age=true`); never reuse an SSH key
   as an age identity and never fetch an identity through the encrypted source.
2. Add `encryption = "age"` and `[age].identity` to its local config.
3. Re-encrypt every enrolled file to the extended recipient set (as in
   [Enrolling or rotating a secret](#enrolling-or-rotating-a-secret)), check
   that each identity and R decrypt every file to the same bytes, and land the
   new ciphertexts.
4. Set `[data].enrollStaticSecrets = true` only after its identity, R's
   custody and the exact target files (owner, type, mode of `~/.secrets`)
   have been checked; a role outside the gate's list is a reviewed change of
   `home/.chezmoiignore` and its tests first.

A new recipient gives its host cryptographic access to every file encrypted to
it from then on, even while deployment is off; changing the recipient set does
not re-encrypt files already in Git history.

## Enrolling or rotating a secret

`claude-as` enrolls a token only when `~/.secrets/claude-NAME` is absent and
never overwrites one. Do not delete or move a managed
`~/.secrets/claude-NAME` to re-enroll in place: the next nonforce login update
then stops at it (changed since last write) and later targets stay stale until
the new ciphertext lands. Instead:

1. Obtain the new token under an unmanaged temporary name, such as
   `claude-as TEMPNAME`; `.secrets` is not an exact directory, so apply leaves
   that sibling alone.
2. Privately run `chezmoi encrypt --use-builtin-age=true` with the full
   explicit argument set ([Manual commands](updates.md#manual-commands)) and
   `--age-recipient-file PRIVATE_FILE`, a private file listing exactly the
   current public recipients, one per line. In v2.74 a repeated
   `--age-recipient` keeps only the last value, and `chezmoi add --encrypt`
   uses the host's configured recipients; never use `add` without `--encrypt`
   or `re-add` for a secret.
3. Privately verify that each host identity and R decrypt the result to the
   same bytes, without printing them.
4. Add or replace `home/private_dot_secrets/encrypted_private_claude-NAME.age`
   (an `encrypted_private_` leaf, never an `exact_` directory or a `create_`
   seed; a new file also updates the count `tests/test_chezmoi_secrets.py`
   pins) and land it through CI. Each enrolled host's login update deploys it;
   then remove the temporary token file and any `TEMPNAME` kit metadata, and
   revoke the superseded token at its issuer. Git history keeps the old
   ciphertext, so revocation, not deletion, ends it.

## Output and failure

Ordinary diff output is not a redaction boundary: review real secret
differences privately, never in captured chat or CI output, and keep logs to
a nonsecret target allowlist. A missing identity, a malformed ciphertext or an
unavailable backend fails the apply without prompting and leaves the existing
secret in place; nothing adds a daemon, key agent or unlock service. SSH
snippet changes keep `Include`, host selection, jump and master options and
host-key trust, and keep an existing working connection until a fresh one
passes.

Tests use only disposable identities and synthetic ciphertext
(`tests/test_chezmoi_secrets.py`): opt-in, host selection, private
permissions, missing-identity and malformed-input failure, per-file recipient
scope and the `create_` seed lifecycle, which shows why a create-if-missing
target is unsuitable for recurring auth.
