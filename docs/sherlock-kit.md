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
```

```powershell
./setup-sherlock-kit.ps1 -Python python -Source /path/to/sherlock-kit -TargetHome /path/to/test-home
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
pin alone is not evidence that the revision is fetchable. Never run an isolated
worktree's installer against the real home. Real Claude/Codex instruction loading
and precedence tests are a separate acceptance gate; unit tests do not prove
actual client delivery.

## Opt-in hook preparation

No Sherlock hook is registered by default. The existing structured merger accepts
`claude-settings-sync --hooks EVENTS.json [--check] PORTABLE LIVE`. This explicit
input contains only Claude hook event arrays. Selected events combine existing
live, portable and opt-in registrations, remove exact duplicates, and preserve
host-only events and runtime/permission keys. Other portable arrays retain their
existing authoritative replacement semantics. Supported opt-in handlers are
validated command objects from the [Claude hooks reference](https://code.claude.com/docs/en/hooks).
Apply `--check` first. A later ordinary sync still follows ordinary baseline
ownership; persistent opt-in installer wiring, removal/upgrades, actual guard
registration/trust and negative smoke tests are Phase 5 work. Codex `--hooks`
is rejected until its installed schema and trust have been verified.
