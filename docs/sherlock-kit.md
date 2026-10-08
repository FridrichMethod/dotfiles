# Pinned Sherlock integration

`sherlock-kit.pin.json` records an immutable toolkit Git revision, policy schema
and SHA-256 digest, and the exact compact instruction projection and its digest.
Both common global instruction files contain this projection in unique
`SHERLOCK-KIT:BEGIN` / `SHERLOCK-KIT:END` blocks. There is no host overlay targeting
either global instruction file. Unrelated tool-specific content stays intact.

Offline checks require only Python 3.11+, do not import the toolkit, and write
nothing:

```sh
python3 -I -B lib/sherlock_kit_integration.py --check
./tests/sherlock-kit.sh
```

The explicit installers share `lib/sherlock_kit_integration.py`:

```sh
./setup-sherlock-kit.sh
# A local repository containing the pinned commit can avoid a network clone:
./setup-sherlock-kit.sh --source /path/to/sherlock-kit
# Disposable test home:
./setup-sherlock-kit.sh --source /path/to/sherlock-kit --target-home /tmp/shk-home
# Persist a local state location independently of package revisions:
./setup-sherlock-kit.sh --state-root /absolute/path/to/private-state
```

```powershell
./setup-sherlock-kit.ps1 -Python python -Source /path/to/sherlock-kit -TargetHome C:/path/to/test-home -StateRoot C:/path/to/private-state
```

Setup archives the exact pin, builds a frozen package with embedded revision,
installs into `~/.local/share/sherlock-kit/revisions/REV`, verifies code and policy
identity, and only then replaces a private `active.json` pointer. Production is
never an editable checkout. One `.setup.lock` serializes explicit setup. An
interrupted lock or inactive failed environment is retained and reported; inspect
the named exact path before manually cleaning it. Setup never changes an active
pointer on failed verification. Existing restrictive regular-file modes are
preserved. Windows uses inherited directory ACLs; Unix mode bits are not Windows
ACL enforcement. Keep the private installation root in a user-owned directory.

`--state-root` (PowerShell `-StateRoot`) records an absolute state directory in
the private `active.json`. Setup validates the locator and never creates that
directory. Relative paths, parent traversal, control characters, invalid Windows
components, files and symlinked paths are rejected before changing the pointer.
Reinstalling or upgrading without this option preserves the saved locator;
passing it again explicitly replaces the locator. The launcher exports it as
`SHERLOCK_KIT_STATE_ROOT` only when that variable is unset, so an explicit
environment override takes precedence. With no saved locator or override,
the toolkit retains its default state location. Choose user-owned persistent
storage appropriate to the host; keep personal absolute paths out of dotfiles.

The Stow-owned `common/codex/.local/bin/shk` resolves the dotfiles checkout and
executes the active frozen interpreter. It supplies advertised pin and real
global instruction paths to doctor. Windows explicit setup additionally writes
a native `shk.cmd` wrapper, without a second Stow owner. The dotfiles checkout
must remain present, as for the existing sync launchers; the installed toolkit
also runs independently through `REV/bin/python -I -m sherlock_kit` (Windows:
`REV/Scripts/python.exe`). Updating instructions can temporarily advertise a
different release. The launcher diagnoses that gap while allowing package
diagnostics/recovery; typed toolkit admission owns mutation restrictions.

Only the integrator updates pin/projections from a reviewed committed toolkit:

```sh
python3 -I -B lib/sherlock_kit_integration.py --update-projection --source /path/to/sherlock-kit
# First insertion alone needs --insert. Later updates reject missing/duplicate markers.
```

Generation imports policy APIs from a temporary Git archive of source HEAD,
not uncommitted files. Review the resulting pin and both blocks together. Publish
the toolkit revision first, then publish the dotfiles pin; a locally generated
pin alone is not evidence that the revision is fetchable. Activate real client
configuration from the reviewed canonical checkout after isolated validation.
Client acceptance evidence belongs in the toolkit's
[validation record](https://github.com/FridrichMethod/sherlock-kit/blob/main/docs/validation/acceptance.md).

## Explicit first-party adapter delivery

The frozen package owns the adapter payloads under `sherlock_kit_data/adapters`.
Dotfiles does not vendor or independently regenerate the skill instructions.
Explicit delivery verifies the package revision/policy against the current pin,
preflights every target and refuses conflicting existing payloads:

```sh
./setup-sherlock-adapters.sh --runtime /path/to/frozen/bin/python --target-home /tmp/shk-home --check-adapters
./setup-sherlock-adapters.sh --runtime /path/to/frozen/bin/python --target-home /tmp/shk-home
```

Use `setup-sherlock-adapters.ps1 -Runtime /path/to/python.exe -TargetHome /path/to/test-home -Check`
for the corresponding PowerShell preflight. The three delivered files are:

- `.claude/plugins/sherlock-kit/.claude-plugin/plugin.json`
- `.claude/plugins/sherlock-kit/skills/sherlock-kit-operate/SKILL.md`
- `.codex/skills/sherlock-kit-operate/SKILL.md`

The Claude plugin contains no hooks. Copying it does not register a marketplace
or enable a plugin; isolated acceptance can load that directory with Claude's
`--plugin-dir`. Codex discovers the copied user skill in the selected test home.
Both skills delegate operations to the shared frozen `shk` command. Setup never
changes client settings, credentials or trust. An identical repeat leaves payload
bytes and mtimes unchanged; an upgrade with changed payloads requires explicit
review of the exact conflicting files. Native Windows execution remains a
separate acceptance check.

## Opt-in hook registration and trust

No Sherlock hook is registered by default. The existing structured merger accepts
`--hooks EVENTS.json` for both `claude-settings-sync` and `codex-config-sync`.
Selected events combine live, portable and opt-in registrations with exact
duplicates removed; host hooks, permissions and runtime keys are retained.
Codex's baseline contains no hooks, so an ordinary later sync preserves existing
opt-in hooks. Claude's other portable arrays retain ordinary authoritative
replacement; repeat its explicit scoped sync after portable hook updates.

Review the supplied `config/sherlock-kit/claude-hooks.json` and `codex-hooks.json`
before opting in. They register only `PreToolUse` command handlers invoking
`shk guard --client claude|codex`, with a five-second timeout. Codex's matcher is
`^Bash$`; its Windows override invokes the native `shk.cmd`. Apply read-only
preflight first, then the exact same inputs against an explicitly selected target:

```sh
common/codex/.local/bin/codex-config-sync --check --hooks config/sherlock-kit/codex-hooks.json common/codex/.codex/config.toml /tmp/shk-home/.codex/config.toml
common/codex/.local/bin/codex-config-sync --hooks config/sherlock-kit/codex-hooks.json common/codex/.codex/config.toml /tmp/shk-home/.codex/config.toml
common/claude/.local/bin/claude-settings-sync --check --hooks config/sherlock-kit/claude-hooks.json common/claude/.claude/settings.json /tmp/shk-home/.claude/settings.json
common/claude/.local/bin/claude-settings-sync --hooks config/sherlock-kit/claude-hooks.json common/claude/.claude/settings.json /tmp/shk-home/.claude/settings.json
```

Codex inline registrations use the raw `timeout` field; the sync validator rejects
the normalized API spellings `timeoutSec` and `timeout_sec`. Handler fields follow the
[official Codex hooks documentation](https://learn.chatgpt.com/docs/hooks);
Claude handlers follow the [Claude hooks reference](https://code.claude.com/docs/en/hooks).

For an offline Codex inspection with no model call:

```sh
python3 -I -B tests/inspect_codex_hooks.py --home /tmp/shk-home/.codex --cwd /tmp/test-project
```

The probe displays configuration errors/warnings, handler timeout, enabled state
and trust status. `enabled: true` alone does not establish execution: `untrusted`
hooks await user review in `/hooks`, and changed trusted hooks become `modified`
and are skipped until reviewed again. A disabled or absent hook is inactive.
Dotfiles does not write Codex's internal trust database or bypass review.
Keep a single inline owner rather than also registering the same handler in
`hooks.json`. Removing the opt-in input does not remove the live registration;
review and remove the exact handler when retiring it. Test a harmless blocking
canary and a benign command on each installed client before relying on a hook;
malformed output, missing handlers or timeouts can leave protection inactive.
Doctor does not infer trust or successful blocking from file presence. Definition
trust also does not attest executable contents; verify the frozen package identity.
See the toolkit [acceptance record](https://github.com/FridrichMethod/sherlock-kit/blob/main/docs/validation/acceptance.md)
for client-specific validation and limitations.

Native Windows setup, instructions, skills and guard support do not imply native
Windows controller support: admission and artifact promotion require POSIX
ownership, no-follow opens and `fcntl`. Native PowerShell behavior is validated
by dotfiles' Windows CI; local POSIX fixtures do not replace that gate.
