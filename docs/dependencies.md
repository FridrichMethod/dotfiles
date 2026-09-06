# Dependencies and lighter packaging

Shell and PowerShell remain the orchestration languages. The structured merge
backend is deliberately small; no general application framework is involved.

## Current requirements

| Use | Requirements |
| --- | --- |
| Unix installation | Bash, Git, GNU Stow (and its Perl runtime), ordinary POSIX utilities |
| Native Windows installation | PowerShell 7+, Git for Windows / Git Bash, elevated symlink creation |
| All three AI sync helpers | Python 3.11+; no package installation during login or stow |
| Codex TOML merge | Exact `tomlkit` pin in `requirements-sync.txt` |
| Claude JSON / Codex rules alone | Python standard library only, via an explicitly selected interpreter |
| Default parser setup | Python's `venv` and pip support; downloads the pinned wheel unless pre-provisioned offline |
| Claude customization hooks | Node.js; independent of configuration-file merging |
| Optional skill downloads | Bash, curl, tar, rsync |
| Contributor checks | pre-commit, Node, Python/parser runtime; pinned lint tools; Stow integration; PowerShell required on Windows CI |

The configured applications (Zsh, Vim, terminals, Codex, Claude, etc.) are needed
to use their respective settings, not all to copy or symlink the repository.
There is no global Node/npm dependency for the AI merge backend. `jq`, `uv`,
`yq`, `jaq`, and `dasel` are not required by that backend either.

## Is a venv necessary?

No: [venv](https://docs.python.org/3/library/venv.html) provides package isolation;
it is not needed to execute Python. The current `setup-sync` scripts deliberately
use a checkout-local `.venv-sync` to avoid changing system/conda environments.
Nothing needs activating. A prepared Python executable can instead be selected
with `DOTFILES_SYNC_PYTHON`; its visible packages must satisfy the helper being
run. Copying a venv between devices is not supported: recreate it on each host.

## Alternatives investigated (2026-09-05)

| Option | Removes per-host venv setup? | Limitation for this repository |
| --- | --- | --- |
| Existing Python + stdlib | Yes | JSON and opaque rules work; [`tomllib`](https://docs.python.org/3/library/tomllib.html) reads TOML but cannot write it |
| [`jq`](https://jqlang.org/manual/) / PowerShell JSON commands | Yes for JSON | Do not solve comment-preserving TOML edits; splitting engines adds platform behavior to maintain |
| Standalone [`jaq`](https://github.com/01mf02/jaq) | Yes | TOML round-trip loses comments; its [manual](https://gedenkt.at/jaq/manual/#toml) excludes date-time values |
| [`dasel`](https://github.com/TomWright/dasel) | Yes | Multi-format executable worth evaluating, but lossless TOML and this repo's preservation contract are not verified |
| [`uv run`](https://docs.astral.sh/uv/guides/scripts/) | Hides management | Still provisions an environment/cache and adds uv; unsuitable for implicit login-time downloads |
| Bundle pinned tomlkit source, or a [zipapp](https://docs.python.org/3/library/zipapp.html) | Yes | Still requires Python; repository must own parser licensing, pin updates and packaging tests |

A local probe of official jaq 3.1.1 with `--from toml --to toml` dropped both
standalone and trailing comments after a one-key edit; an RFC 3339 date-time
value failed to parse. It is not a drop-in replacement for preserving arbitrary
live TOML state. These observations concern that tested release, not all tools.

The most promising smaller deployment is to bundle the pinned, pure-Python
[TOMLKit](https://tomlkit.readthedocs.io/en/latest/) parser, retaining its
[MIT license](https://github.com/python-poetry/tomlkit/blob/master/LICENSE).
The installed 0.15.1 package measured about 197 KiB of source excluding bytecode;
this host's complete `.venv-sync` occupied about 15 MiB. These are local size
measurements, not cross-platform guarantees. Bundling would remove pip/venv
provisioning per device while preserving one merge implementation, but would
not remove the Python interpreter dependency.

That packaging change is a separate decision and is **not implemented** here.
The current change only removes the unnecessary tomlkit requirement from
standalone JSON/rules operations. No AWK/regex TOML writer or hidden dependency
download has been introduced.
