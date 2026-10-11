# Sherlock toolkit (submodule)

[sherlock-kit](https://github.com/FridrichMethod/sherlock-kit) gives agents one
interface for moving data, submitting and tracking Slurm jobs and reading
compute resources between a workstation and Sherlock. This repository carries
it as the submodule `common/sherlock-kit/sherlock-kit`, wired like
`common/pymol/PyMOLScripts`: `.gitmodules` follows its `main` branch, the
package's path-anchored `.stow-local-ignore` (`^/sherlock-kit$`) keeps the
checkout itself out of `$HOME`, and only relative symlinks point into it.
Nothing is copied or spliced except the one generated Codex file below.

## Delivery

Only `lab-ubuntu`, `wsl-ubuntu` and `sherlock` have a `<host>/sherlock-kit`
package; `mac`, `marlowe` and `win` get nothing. `common/sherlock-kit` holds
only the submodule and its ignore file.

| Target | Links to (in the submodule) | Hosts |
| --- | --- | --- |
| `~/.claude/rules/sherlock-kit.md` | `src/sherlock_kit/data/rules/workstation.md` | lab-ubuntu, wsl-ubuntu |
| `~/.claude/rules/sherlock-kit.md` | `src/sherlock_kit/data/rules/cluster.md` | sherlock |
| `~/.claude/skills/sherlock-kit`, `~/.agents/skills/sherlock-kit` | `src/sherlock_kit/data/skills/sherlock-kit` (directory links) | all three |
| `~/.local/bin/shk` | `bin/shk` | all three |

- **Claude Code** loads `~/.claude/rules/**/*.md` as user memory, so the rules
  arrive through the stowed link; `CLAUDE.md` neither imports nor splices
  them. It is the one first-party file in `~/.claude/rules/`, and it follows
  the submodule without a restow.
- **Codex** reads one global file and has no include, so `./stow-all.sh <host>`
  runs `codex-instructions-sync`, which writes `~/.codex/AGENTS.override.md`:
  a marker line, `common/codex/.codex/AGENTS.md`, then the host's rules. It
  replaces only a file it generated; on a host without rules it removes its
  own file and leaves any other in place. It is POSIX-only (no Windows host
  has rules) and not a Stow target, so `.stowrc` has no entry for it.
- **Skills** are personal skills in both clients. The Claude link sits in
  `~/.claude/skills/`, which awesome-skills also writes into: its installer's
  default `rsync -a` only adds and updates, so the link survives (an
  `install.sh --delete` run removes it until the next stow), and AGENTS.md
  exempts it from awesome-skills' ownership. The Codex link uses
  `~/.agents/skills/`, outside awesome-skills' `~/.codex/skills/`.
- **`shk`**: `bin/shk` is stdlib-only and needs Python 3.11+ as `python3`. An
  activated project env that pip-installed sherlock-kit puts its own `shk`
  first on PATH and wins. On Sherlock the profile exports `SHK_EXECUTOR=local`.

## Updates

`update-sherlock-kit-submodule.yml` runs daily at 04:30 UTC (30 minutes after
the PyMOLScripts bump). It moves the gitlink to sherlock-kit `main`, refuses a
bump that leaves a stowed link dangling, and commits
`chore(deps): update sherlock-kit submodule to latest`. On the next login the
updater fast-forwards, runs `git submodule update --init --recursive` and
restows the remembered host, which regenerates the Codex override.

A manual bump from a clean checkout:

```sh
git pull --ff-only
git submodule update --remote --merge common/sherlock-kit/sherlock-kit
bash tests/sherlock-kit-delivery.sh --real
git add common/sherlock-kit/sherlock-kit
git commit -m "chore(deps): update sherlock-kit submodule to latest"
git push
./stow-all.sh <host>
```

Push right away: once the daily bump lands on `origin/main`, an unpushed
local bump has diverged from it, and the login updater's `git pull --ff-only`
fails on every login, so the host gets no update until you reconcile the two
(`git pull --rebase`, then push). Stow after the
commit, because `stow-all.sh` records a revision as applied only from a clean
tree.

## Projects

Pin the toolkit in the project's own environment, for example
`pip install "sherlock-kit @ git+https://github.com/FridrichMethod/sherlock-kit@v0.4.0"`.
`shk install-skill --project DIR` copies the skill into `DIR/.claude/skills/`
and `DIR/.agents/skills/` for machines without these dotfiles; on a dotfiles
host the personal skill shadows that copy in Claude, and `--rules` is skipped
while `~/.claude/rules/sherlock-kit.md` exists.

## Verify

```sh
readlink -f ~/.claude/rules/sherlock-kit.md     # .../workstation.md, or cluster.md on Sherlock
ls -L ~/.claude/skills/sherlock-kit/SKILL.md ~/.agents/skills/sherlock-kit/SKILL.md
head -n 1 ~/.codex/AGENTS.override.md           # the codex-instructions-sync marker
wc -c <~/.codex/AGENTS.override.md              # well under 32 KiB
shk --version
./doctor.sh --host <host>                       # submodule and codex-override rows ok
bash tests/sherlock-kit-delivery.sh             # fixtures; --ci fails without stow, --real checks the submodule
```

## Troubleshooting

- `sherlock-kit submodule not initialized; Codex instructions left unchanged (git submodule update --init --recursive)`:
  a fresh clone or a local merge left the submodule empty, so the links
  dangle. `./stow-all.sh` skips only the Codex step and records no applied
  revision, so the login updater retries. Run
  `git submodule update --init --recursive`, then `./stow-all.sh <host>`.
- The doctor's `codex-override` row: `outdated` means the override is stale
  (rerun `./stow-all.sh <host>`); `human` means `~/.codex/AGENTS.override.md`
  is a symlink or a file the helper did not write, which Codex reads instead
  of `AGENTS.md` and the rules (move it aside, then restow). It warns above
  28 KiB, because Codex truncates global instructions at 32 KiB.
- Retired 0.3 launchers: on POSIX, `./stow-all.sh` removes the old dangling
  `~/.local/bin/shk` itself. Windows hosts that ran the old `stow-all.ps1`
  keep a dangling `~\.local\bin\shk`, and hosts that also ran the retired 0.3
  Windows setup script keep `~\.local\bin\shk.cmd` and
  `~\.local\share\sherlock-kit`; remove them by hand.
