# Codex and Claude tooling (submodule)

[coding-agent-kit](https://github.com/FridrichMethod/coding-agent-kit) is a
standalone project: the `codex-as` and `claude-as` account launchers, their
Bash and zsh completions, and the Claude status line, notification and Git
hook check helpers, laid out as `bin/`, `lib/`, `completions/` and `helpers/`,
with an `install.sh` for hosts without dotfiles. This repository carries it as
the submodule `common/coding-agent-kit/coding-agent-kit`, pinned at a release
tag (`.gitmodules` names its `main` branch). The submodule keeps the name of
its first path, `common/codex/coding-agent-kit`, so its module directory is
`.git/modules/common/codex/coding-agent-kit` on every host. The settings
(both global instruction files, `settings.json`, `config.toml`,
`portable.rules`), the AI config sync engine `lib/config_sync.py` with its
runtime ([configuration sync](config-sync.md)) and the choice of which hosts
get a Codex override all stay here; the kit needs none of them.

The kit documents itself. With the submodule checked out:

- `common/coding-agent-kit/coding-agent-kit/README.md`: requirements, install
  and the helpers;
- `common/coding-agent-kit/coding-agent-kit/docs/account-launchers.md`: account
  layout, new accounts, completion and safety boundaries (`--help` names this
  file);
- `common/coding-agent-kit/coding-agent-kit/docs/configuration.md`: the
  optional configuration file;
- `common/coding-agent-kit/coding-agent-kit/docs/codex-as.md`: Codex source
  verification;
- `common/coding-agent-kit/coding-agent-kit/CHANGELOG.md`: what each release
  changed.

The same files are on [GitHub](https://github.com/FridrichMethod/coding-agent-kit),
where `main` may be ahead of the pinned release.

The checkout sits at the root of its own Stow package, `common/coding-agent-kit`,
laid out like `common/sherlock-kit`. The package's `.stow-local-ignore` holds
the path-anchored `^/coding-agent-kit$` and `^/coding-agent-kit/`: Stow matches
a pattern with a slash against `/PATH`, so only the package-root checkout is
ignored, and `stow-all.ps1` (which stows the package on Windows too) matches
the same way. A `.stow-local-ignore` replaces Stow's built-in ignore list, so
the package holds nothing but the checkout and its links. The submodule's own
`AGENTS.md` binds the helpers' behavior.

## Delivery

`common/coding-agent-kit` holds one relative symlink per delivered file, never
a directory link. Their `$HOME` paths are the ones these files had before the
kit existed; the link text follows the kit's layout. Each link climbs to the
package root and enters the submodule there, for example
`common/coding-agent-kit/.local/bin/codex-as -> ../../coding-agent-kit/bin/codex-as`.
Until the [move](#the-move-out-of-the-codex-package) the same links sat at the
same relative paths in `common/claude` and `common/codex`.
`tests/coding-agent-kit-delivery.sh` holds this map and checks every link
against it.

| Package path (link) | Kit path | `$HOME` path |
| --- | --- | --- |
| `common/coding-agent-kit/.claude/dotfiles/check-git-hooks.cjs` | `helpers/check-git-hooks.cjs` | `~/.claude/dotfiles/check-git-hooks.cjs` |
| `common/coding-agent-kit/.claude/dotfiles/notify.cjs` | `helpers/notify.cjs` | `~/.claude/dotfiles/notify.cjs` |
| `common/coding-agent-kit/.claude/dotfiles/statusline.cjs` | `helpers/statusline.cjs` | `~/.claude/dotfiles/statusline.cjs` |
| `common/coding-agent-kit/.local/bin/claude-as` | `bin/claude-as` | `~/.local/bin/claude-as` |
| `common/coding-agent-kit/.local/bin/codex-as` | `bin/codex-as` | `~/.local/bin/codex-as` |
| `common/coding-agent-kit/.local/lib/claude-as/launch.py` | `lib/claude-as/launch.py` | `~/.local/lib/claude-as/launch.py` |
| `common/coding-agent-kit/.local/lib/codex-as/check.py` | `lib/codex-as/check.py` | `~/.local/lib/codex-as/check.py` |
| `common/coding-agent-kit/.local/lib/codex-as/handoff.py` | `lib/codex-as/handoff.py` | `~/.local/lib/codex-as/handoff.py` |
| `common/coding-agent-kit/.local/lib/codex-as/launch.py` | `lib/codex-as/launch.py` | `~/.local/lib/codex-as/launch.py` |
| `common/coding-agent-kit/.local/lib/codex-as/layout.py` | `lib/codex-as/layout.py` | `~/.local/lib/codex-as/layout.py` |
| `common/coding-agent-kit/.local/share/bash-completion/completions/claude-as` | `completions/bash/claude-as` | `~/.local/share/bash-completion/completions/claude-as` |
| `common/coding-agent-kit/.local/share/bash-completion/completions/codex-as` | `completions/bash/codex-as` | `~/.local/share/bash-completion/completions/codex-as` |
| `common/coding-agent-kit/.oh-my-zsh/custom/completions/_claude-as` | `completions/zsh/_claude-as` | `~/.oh-my-zsh/custom/completions/_claude-as` |
| `common/coding-agent-kit/.oh-my-zsh/custom/completions/_codex-as` | `completions/zsh/_codex-as` | `~/.oh-my-zsh/custom/completions/_codex-as` |

The two launchers are executable in the kit; the links carry no mode of their
own. Each launcher follows its own links to the kit root, the directory above
`bin/`, and loads `lib/<tool>/` and `lib/coding-agent-kit/config.py` from
there, never from `~/.local/lib`. The five `~/.local/lib/{codex,claude}-as`
links stay so that the stowed `$HOME` tree is the same as before; two of
them, `~/.local/lib/codex-as/check.py` and `~/.local/lib/claude-as/launch.py`,
also keep working the completion functions that a shell loaded before an
update still calls. New shells complete through `codex-as --list-accounts`
and `claude-as --list-accounts`. `settings.json` runs the three helpers through
`~/.claude/dotfiles/`. `codex-as --help` and `claude-as --help` end with
`Details and manual repair:` and the physical path of the checkout's
`common/coding-agent-kit/coding-agent-kit/docs/account-launchers.md`, or the GitHub URL
when they cannot find their kit.

Never run the kit's `install.sh` on a dotfiles host. Stow already links the
launchers and completions, and `install.sh` refuses those links (it replaces
only links of its own) and changes nothing.

## Configuration

The launchers read an optional TOML file,
`${XDG_CONFIG_HOME:-~/.config}/coding-agent-kit/config.toml` (or the absolute
path in `CODING_AGENT_KIT_CONFIG`), for the `codex` and `claude` executables
and the `codex_home` and `secrets_dir` roots. Without one they run `codex` and
`claude` from PATH with `~/.codex` and `~/.secrets`, exactly as before the
file existed. Dotfiles ships and stows no such file, so a host keeps those
defaults unless someone writes one there; `codex-as --show-config` and
`claude-as --show-config` print the effective values and where they came
from. If a host ever needs other values, let one package of that host's
overlay own the whole file, never a common file plus a host copy (Stow cannot
merge them), and set `codex_home` and `secrets_dir` before the first
enrolment there, because account links are absolute. The rules are in
`common/coding-agent-kit/coding-agent-kit/docs/configuration.md`.

The launchers color their own messages by
`CODING_AGENT_KIT_COLOR=auto|always|never`; nonempty `NO_COLOR` and
`TERM=dumb` disable it. They no longer read `DOTFILES_COLOR`, which governs
only this repository's installers and update hooks.

## Updates

`update-coding-agent-kit-submodule.yml` runs daily at 05:17 UTC and on
dispatch from the Actions tab, one run at a time, always on `main`. A
dispatch runs the workflow file of the branch it names, and the gates are
reviewed only on `main`, so a run for any other branch skips the job. It reads
the release tag of the pinned commit and takes only the newest `vX.Y.Z` tag
of the same `vX.Y` line. Before it commits, it requires, in this order:

1. the release is a commit of coding-agent-kit's `main` that descends from
   the pin;
2. each of the kit's three CI jobs (`Linux behavior and lint`,
   `macOS system Bash behavior`, `Windows native PowerShell behavior`) has a
   GitHub Actions check run on the release, and every such run, of the pull
   request and of the push to `main` alike, completed with success: a red or
   unfinished run is not hidden by a green one of the same name;
3. with GNU Stow, zsh and `.venv-sync` installed on the runner and the
   release staged as the gitlink,
   `bash tests/coding-agent-kit-delivery.sh --real` passes: every link
   resolves into the release with its mode, and the release tracks no
   symlink, nested submodule or `.gitmodules` (the login updater's
   `--recursive` update would clone a nested URL on every host) and reads no
   `CODING_AGENT_KIT_*` name that the test entry points do not unset. Then
   `--ci` runs the real `stow-all.sh` into temporary homes with the checkout
   full, emptied and restored;
4. `tests/ai-integration.sh` passes on `.venv-sync`: `codex-as` through the
   alias files in Bash and zsh, the fzf-tab account preview, a real Stow of
   the completions, and the release's Claude helper suite on the real
   `settings.json` ([below](#real-settings-and-the-helper-tests)).

It then commits `chore(deps): update coding-agent-kit submodule to vX.Y.Z` as
github-actions[bot] and pushes `main`. A push made with `GITHUB_TOKEN` starts
no `ci.yml` run, so the four gates are all the checking a patch release gets
before every host pulls it at its next login. A failed gate fails the run and
bumps nothing, even when an older patch of the line would pass: tag a fixed
patch, or bump through a reviewed pull request as for a new minor release.
When the kit has a newer release line, the job summary says so, but the run
never takes it. On the next login the updater fast-forwards, runs
`git submodule update --init --recursive` and restows the remembered host.

Gates 3 and 4 run the release's code, so the checkout keeps no credential
and no step that runs that code gets the token: gate 2 reads the check runs
with it, `actions/checkout` and `actions/setup-node` take it through their
default `token` input, all before the release is staged, and the push gets it
last, as the header of that one `git push`. That keeps a release that
misbehaves from pushing to this repository. It is no boundary against a
malicious one, which can still reach the push step and the actions' post
steps through the job's files (`$GITHUB_PATH`, `$GITHUB_ENV`) and the
checkout's `.git`. Only a separate push job would stop that, and such a
release runs on every host at its next login anyway.

The schedule follows the PyMOLScripts (04:00 UTC) and sherlock-kit (04:30)
bumps and stays off the top of the hour, where GitHub delays scheduled runs
most, but nothing orders the three pushes. When another push lands on `main`
first, this run's push fails as non-fast-forward, nothing is bumped, and the
next run retries. The run never rebases and retries, which would push a
gitlink that gate 4 never ran against the new `main`'s `settings.json`.

`tests/coding-agent-kit-delivery.sh` pins the workflow: its gate lines in
order, and the whole file against the reviewed copy
`tests/fixtures/update-coding-agent-kit-submodule.yml`, both regular files.
Change both in the same commit.

Pin only commits on the kit's `main` that carry a `vX.Y.Z` tag. Every run
fails with an untagged-pin error until a release is pinned, and a gitlink off
`main` fails every host's submodule update at login.

### A new minor release

A new `vX.Y.0` (breaking while the kit is 0.x) goes through a reviewed pull
request. Make it in a separate clean clone of dotfiles (the auto-updated
`~/dotfiles` must stay on `main`, or its login updater stops pulling):

```sh
git pull --ff-only
git submodule update --init common/coding-agent-kit/coding-agent-kit
git -C common/coding-agent-kit/coding-agent-kit fetch --tags origin
git -C common/coding-agent-kit/coding-agent-kit checkout --detach vX.Y.0
git add common/coding-agent-kit/coding-agent-kit
./setup-sync.sh
bash tests/coding-agent-kit-delivery.sh --real
bash tests/coding-agent-kit-delivery.sh --ci
bash tests/ai-integration.sh
git switch -c bump/coding-agent-kit-vX.Y.0
git commit -m "chore(deps): update coding-agent-kit submodule to vX.Y.0"
```

When the release moves a delivered file, retarget its link, the map in
`tests/coding-agent-kit-delivery.sh`, the coding-agent-kit sentinels in
`lib/bootstrap/checks.sh` and their copy `CAK_SENTINELS` in `tests/doctor.sh`
in that same commit: a gitlink without its links leaves the launchers
dangling on every host. When it reads a new `CODING_AGENT_KIT_*` name, add
the name to the unset list of `tests/run.sh`, every other test entry point
and `tests/run.ps1` in that commit too. Push the branch and open a pull
request; it runs the full `ci.yml`, including the check that the pinned
commit is on the kit's `main`. After the merge the daily run follows the new
`vX.Y` line.

### Real settings and the helper tests

coding-agent-kit tests its Claude helpers on a frozen copy of this
repository's `settings.json`; `tests/fixtures/claude-settings.json` there is an
interface. `tests/ai-integration.sh` (and `tests/run.ps1` on Windows) exports
the pinned submodule tree to a temporary directory, copies the real
`settings.json` over that file and runs the helper tests on it, so they still
run on every change to the settings and, as gate 4, on every bump.

## Develop in a separate clone

Change the tooling in its own clone of coding-agent-kit, never in
`common/coding-agent-kit/coding-agent-kit`. An untracked file there makes the checkout
dirty: the login updater then skips every later pull, and `stow-all.sh`
records no applied revision.

## Uninitialized submodule

A fresh clone without `--recurse-submodules`, or a local merge, can leave the
submodule empty. Then:

- `./stow-all.sh` finds a tracked link under `common/coding-agent-kit` that
  does not resolve and warns once
  `coding-agent-kit links dangle; codex-as, claude-as and the Claude helpers are unavailable until the submodule is checked out (git submodule update --init --recursive)`.
  It still runs every Claude and Codex sync, still stows, and exits 0. It
  records no applied revision, so the login updater initializes the submodule
  and restows at the next login. On a fresh home the 14 links dangle until
  then.
- `stow-all.ps1` adds the same warning before any change, trusted links or
  not: whether a kit link dangles comes from its own target text, since
  RedirectionGuard rejects an untrusted link with 448 whether or not its target
  exists. With `-Strict` it stops there; without it, it syncs, stows with one
  `dangling source skipped` warning per link (an unelevated run warns
  `untrusted source symlink left in place` for each untrusted link instead)
  and saves no state.
- `./doctor.sh` reports the `submodule` row as missing, naming the kit's
  sentinel files it lacks (`bin/codex-as`, `bin/claude-as`, the two
  `launch.py` and the three helpers under
  `common/coding-agent-kit/coding-agent-kit/`),
  with the fix.

Run `git submodule update --init --recursive`, then `./stow-all.sh <host>`
(`.\stow-all.ps1 win` on Windows).

## Windows

The links are tracked symlinks, which Git for Windows creates only with
`core.symlinks=true` and Developer Mode (or `SeCreateSymbolicLinkPrivilege`).
Clone with `git clone -c core.symlinks=true --recurse-submodules`. A clone made
without symlinks has text files in place of the links: `stow-all.ps1` links
them into `$HOME` without a warning, `codex-as`, `claude-as` and the Claude
helpers break there, and only `doctor.ps1`'s `core-symlinks` row shows it. The
AI sync itself uses no link and keeps working. Repair it with:

```powershell
git -C $HOME\dotfiles config core.symlinks true
git -C $HOME\dotfiles checkout -- common/pymol common/coding-agent-kit
```

then run `.\stow-all.ps1 win` from an elevated PowerShell. The pathspec names
only the packages with tracked links, so settings you edited in place in
`.claude/` and `.codex/` stay.

A non-elevated pull creates the links as untrusted, which processes enforcing
RedirectionGuard reject. The elevated restow (the `Dotfiles-Restow-*` task or a
manual elevated `.\stow-all.ps1 win`) repairs them once, keeping their
relative text, and reports them under `repaired:`; a non-elevated run warns
`untrusted source symlink left in place` per link and fails `-Strict`. A
patch bump changes only the gitlink, but a change of link texts, such as the
move to the v0.2 layout or the move into the `coding-agent-kit` package,
rewrites all 14 links, so expect them under `repaired:` once. `stow-all.ps1`
walks the whole `coding-agent-kit` package, so its `unchanged/ignored:` count
includes every file of the submodule checkout.

## The move out of the codex package

Until 2026-10, the checkout sat at `common/codex/coding-agent-kit`, inside the
`codex` package, and `common/claude` and `common/codex` held the 14 links. One
commit moved it, with `git mv`, to its own package; the submodule kept its
name. A host takes the move in one login: the fast-forward deletes the old
links and the old gitlink, `git submodule update` checks the kit out at the
new path from the same module directory (with no download when that already
holds the pinned commit), and the restow
replaces each `$HOME` link with one into the new package, at the same path.

Git cannot remove a submodule checkout that holds files, so a host where the
kit was checked out keeps the old one at `common/codex/coding-agent-kit`
(`unable to rmdir`, which the login updater does not show). It is harmless:

- the `.gitignore` line `/common/codex/coding-agent-kit/` keeps it out of
  `git status`; without it, the updater would stop at `Checkout changed during
  update` and then at `Local changes` on every later login;
- the `.stowrc` line `--ignore=^coding-agent-kit(/|$)` keeps Stow from linking
  its tree into `$HOME`;
- `./doctor.sh` (and `doctor.ps1`) turn the `submodule` row into a warning that
  names the one command that removes it.

Check a host with
`git -C ~/dotfiles status --porcelain --ignored -- common/codex`: a line
`!! common/codex/coding-agent-kit/` is the leftover. Remove it with
`rm -rf ~/dotfiles/common/codex/coding-agent-kit`
(`Remove-Item -LiteralPath $HOME\dotfiles\common\codex\coding-agent-kit -Recurse -Force`
on Windows). Never delete `.git/modules/common/codex/coding-agent-kit`: it is
the repository of the current checkout. Until then, do not run git inside the
leftover or leave an editor open there: its `.git` file names that same module
directory, so a git command run there acts on the current checkout.

Once no host has the leftover, a later change drops the `.stowrc` line and
makes both installers refuse to run while the leftover exists; the
`.gitignore` line stays, so a host that takes the move late still converges.

## Rollback

Fix forward: never rewrite coding-agent-kit's `main` or move its tags.

- A bad patch release: revert its bump commit on `main` with a forward
  `git revert`, through a pull request, and disable
  `update-coding-agent-kit-submodule.yml` in the Actions tab until a fixed
  patch is tagged, because the next run would take the bad release again. At
  the next login every host checks the submodule out at the previous release
  and restows. The doctor's `submodule` row only checks that the kit's files
  exist, which a host still on the bad patch passes too, so confirm on each
  host that
  `git -C ~/dotfiles submodule status common/coding-agent-kit/coding-agent-kit`
  shows no leading `+` and ends with the previous release tag, and that line
  4 of `~/dotfiles/.git/dotfiles-sync-unix`, the applied revision, equals
  `git -C ~/dotfiles rev-parse HEAD` (on Windows, `appliedHead` in
  `$HOME\dotfiles\.git\dotfiles-sync-windows\configuration.json`).
- Back before the move out of the `codex` package: revert, newest first,
  `docs(coding-agent-kit): document the package and the move`,
  `feat(doctor): flag the leftover pre-move kit checkout` and
  `refactor(coding-agent-kit): give the kit its own Stow package`, in one
  `git revert <docs> <doctor> <refactor>`, and in the same pull request add
  the line `/common/coding-agent-kit/` to `.gitignore`. The pull cannot
  remove the checkout at the new path either (it holds files); without that
  line it shows as untracked and every host that had the kit checked out
  stops at `Checkout changed during update`, then at `Local changes`. With
  it, one login checks the kit out at `common/codex/coding-agent-kit` again
  and restows the `$HOME` links into `common/claude` and `common/codex`.
  Keep the line until no host has `common/coding-agent-kit/`. Land it only
  after every host has removed the pre-move leftover (the doctor's
  `submodule` row is `ok` and
  `git -C ~/dotfiles status --porcelain --ignored -- common/codex` prints
  nothing): the revert makes git take a leftover as the checkout again, and
  once the kit moved since the move (any later bump, or a host that took the
  move together with a kit bump) its old files show as modified and the host
  stops at `Checkout changed during update`. Repair such a host with
  `git -C ~/dotfiles submodule update --init --force -- common/codex/coding-agent-kit`;
  the next login converges.
- Back to v0.1.0: go back before the move first. Then revert any later bump
  commits, newest first, and revert, newest first, the three commits that
  moved to v0.2.0:
  `docs(coding-agent-kit): document the standalone kit and its bumps`,
  `ci(coding-agent-kit): bump patch releases daily behind four gates` and
  `refactor(coding-agent-kit): consume the kit's v0.2.0 layout`, in one
  `git revert <docs> <ci> <refactor>`. That returns exactly to the state
  before them: the sync engine stays here, the gitlink is v0.1.0 with the old
  link texts and the `docs/account-launchers.md` pointer, and the bump
  workflow is again the manual, dispatch-only one that proposes the kit's
  `main` on a review branch. The package paths and `$HOME` links are the same
  with both kits; the v0.1.0 launchers load `~/.local/lib/{codex,claude}-as`,
  read `DOTFILES_COLOR` and no configuration file.
- Back to regular files: go back to v0.1.0 first, whose kit paths are the
  package paths. Then a forward commit replaces the 14 links with the files at
  those paths in that kit commit and writes `docs/account-launchers.md` and
  `docs/codex-as.md` from it
  (`git -C common/codex/coding-agent-kit archive <sha> -- <paths> | tar -x`),
  so hosts get exactly the bytes they run. The submodule stays registered,
  checked out and ignored by Stow.
- Removing the submodule: while the package files are links, land the
  "Back to regular files" commit first and remove the submodule only in a
  later commit. Never remove it with a plain `git revert` or a per-host
  `git submodule deinit`, which leave an untracked checkout that freezes the
  login updater, or get it cloned again at the next pull. Use one forward
  commit that removes the gitlink and the `.gitmodules` entry, adds the
  gitlink's path at that point to `.gitignore` (after the steps above, which
  go back before the move, `/common/codex/coding-agent-kit/`), keeps what
  hides that path from Stow (there, the `.stowrc` line
  `--ignore=^coding-agent-kit(/|$)`; at `common/coding-agent-kit/coding-agent-kit`,
  the package's `.stow-local-ignore`), and drops the doctor sentinels, the CI
  submodule steps, the bump workflow and their test cases. Per-host cleanup is
  then optional:
  `rm -rf ~/dotfiles/common/codex/coding-agent-kit ~/dotfiles/common/coding-agent-kit ~/dotfiles/.git/modules/common/codex/coding-agent-kit`
  (the same three paths under `$HOME\dotfiles` on Windows); only then is the
  module directory unused. Drop the new `.gitignore` lines only in a later
  commit, after every host has done that cleanup.

## Verify

```sh
git submodule status common/coding-agent-kit/coding-agent-kit   # ends with the release tag, (vX.Y.Z)
readlink common/coding-agent-kit/.local/bin/codex-as            # ../../coding-agent-kit/bin/codex-as
ls -L ~/.local/bin/codex-as ~/.claude/dotfiles/statusline.cjs
git status --porcelain --ignored -- common/codex                # nothing: no pre-move leftover
codex-as --help | tail -n 1                          # Details and manual repair: .../common/coding-agent-kit/coding-agent-kit/docs/account-launchers.md
codex-as --show-config                               # config = ... (not found; defaults)
./doctor.sh --host <host>                            # submodule row ok
bash tests/coding-agent-kit-delivery.sh              # fixtures; --ci fails without stow, --real checks the submodule
```
