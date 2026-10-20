# Codex and Claude tooling (submodule)

[coding-agent-kit](https://github.com/FridrichMethod/coding-agent-kit) holds
the `codex-as` and `claude-as` launchers and the Claude status line,
notification and Git hook check helpers. This repository carries it as the
submodule `common/codex/coding-agent-kit`, and `.gitmodules` follows its
`main` branch. The settings themselves (both global instruction files,
`settings.json`, `config.toml`, `portable.rules`) stay here, with the AI config
sync engine and its runtime ([configuration sync](config-sync.md)), and so
does the choice of which hosts get a Codex override.

The checkout sits inside the `codex` package. The `.stowrc` line
`--ignore=^coding-agent-kit(/|$)` keeps it out of `$HOME`; a
`.stow-local-ignore` in `common/codex` would replace Stow's built-in ignore
list for the whole package. `stow-all.ps1` reads the same line. The
submodule's own `AGENTS.md` binds the helpers' behavior.

## Delivery

`common/claude` and `common/codex` hold one relative symlink per delivered
file, never a directory link. Each link at `common/P/R` points at the same
path inside the submodule, `common/codex/coding-agent-kit/common/P/R`, so the
stowed `$HOME` links keep their old text and resolve through one more hop.

| Package path (link) | `$HOME` path |
| --- | --- |
| `common/claude/.claude/dotfiles/check-git-hooks.cjs` | `~/.claude/dotfiles/check-git-hooks.cjs` |
| `common/claude/.claude/dotfiles/notify.cjs` | `~/.claude/dotfiles/notify.cjs` |
| `common/claude/.claude/dotfiles/statusline.cjs` | `~/.claude/dotfiles/statusline.cjs` |
| `common/claude/.local/bin/claude-as` | `~/.local/bin/claude-as` |
| `common/claude/.local/lib/claude-as/launch.py` | `~/.local/lib/claude-as/launch.py` |
| `common/claude/.local/share/bash-completion/completions/claude-as` | `~/.local/share/bash-completion/completions/claude-as` |
| `common/claude/.oh-my-zsh/custom/completions/_claude-as` | `~/.oh-my-zsh/custom/completions/_claude-as` |
| `common/codex/.local/bin/codex-as` | `~/.local/bin/codex-as` |
| `common/codex/.local/lib/codex-as/check.py` | `~/.local/lib/codex-as/check.py` |
| `common/codex/.local/lib/codex-as/handoff.py` | `~/.local/lib/codex-as/handoff.py` |
| `common/codex/.local/lib/codex-as/launch.py` | `~/.local/lib/codex-as/launch.py` |
| `common/codex/.local/lib/codex-as/layout.py` | `~/.local/lib/codex-as/layout.py` |
| `common/codex/.local/share/bash-completion/completions/codex-as` | `~/.local/share/bash-completion/completions/codex-as` |
| `common/codex/.oh-my-zsh/custom/completions/_codex-as` | `~/.oh-my-zsh/custom/completions/_codex-as` |

The two launchers are executable in the submodule; the links carry no mode of
their own. `settings.json` runs the three `.cjs` helpers through
`~/.claude/dotfiles/`, and `docs/account-launchers.md` stays here as a pointer
because `codex-as --help` and `claude-as --help` name it.

## Updates

A bump is manual, because the launchers and the Claude Git hook check run in
every Codex and Claude session from the next login. Dispatch
`update-coding-agent-kit-submodule.yml` from the Actions tab. It moves the
gitlink to coding-agent-kit `main`, runs
`bash tests/coding-agent-kit-delivery.sh --real`, requires the linux, macos
and windows jobs of coding-agent-kit to have passed on that commit, and
pushes the branch `bump/coding-agent-kit-<first 12 hex of the sha>`, never
`main`. Open a pull request from the compare link in the job summary; it runs
the full `ci.yml`, including the check that the pinned commit is on
coding-agent-kit's `main`. Merge it when it is green. If a branch of that name
already exists, the push is rejected: delete the old branch and dispatch
again. On the next login the updater fast-forwards, runs
`git submodule update --init --recursive` and restows the remembered host.

A bump by hand, in a separate clean clone of dotfiles (the auto-updated
`~/dotfiles` must stay on `main`, or its login updater stops pulling):

```sh
git pull --ff-only
git submodule update --init --remote --merge common/codex/coding-agent-kit
git add common/codex/coding-agent-kit
bash tests/coding-agent-kit-delivery.sh --real
git switch -c bump/coding-agent-kit-manual
git commit -m "chore(deps): update coding-agent-kit submodule to latest"
```

Push the branch and open a pull request, as above. Never record a gitlink at a
commit that is not on coding-agent-kit's `main`: a host that cannot fetch it
fails its submodule update at every login.

### Real settings and the helper tests

coding-agent-kit tests its Claude helpers on a frozen copy of this
repository's `settings.json`; `tests/fixtures/claude-settings.json` there is an
interface. `tests/ai-integration.sh` (and `tests/run.ps1` on Windows) exports
the pinned submodule tree to a temporary directory, copies the real
`settings.json` over that file and runs the helper tests on it, so they still
run on every change to the settings.

## Develop in a separate clone

Change the tooling in its own clone of coding-agent-kit, never in
`common/codex/coding-agent-kit`. An untracked file there makes the checkout
dirty: the login updater then skips every later pull, and `stow-all.sh`
records no applied revision.

## Uninitialized submodule

A fresh clone without `--recurse-submodules`, or a local merge, can leave the
submodule empty. Then:

- `./stow-all.sh` finds a tracked link under `common/claude` or `common/codex`
  that does not resolve and warns once
  `coding-agent-kit links dangle; codex-as, claude-as and the Claude helpers are unavailable until the submodule is checked out (git submodule update --init --recursive)`.
  It still runs every Claude and Codex sync, still stows, and exits 0. It
  records no applied revision, so the login updater initializes the submodule
  and restows at the next login. On a fresh home the 14 links dangle until
  then.
- `stow-all.ps1` adds the same warning before any change. With `-Strict` it
  stops there; without it, it syncs, stows with one `dangling source skipped`
  warning per link and saves no state.
- `./doctor.sh` reports the `submodule` row as missing with the fix.

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
git -C $HOME\dotfiles checkout -- common/pymol common/claude/.claude/dotfiles common/claude/.local common/claude/.oh-my-zsh common/codex/.local common/codex/.oh-my-zsh
```

then run `.\stow-all.ps1 win` from an elevated PowerShell. The pathspec stops
short of `.claude/` and `.codex/`, whose settings you may have edited in place.

A non-elevated pull creates the links as untrusted, which processes enforcing
RedirectionGuard reject. The elevated restow (the `Dotfiles-Restow-*` task or a
manual elevated `.\stow-all.ps1 win`) repairs them once, keeping their
relative text, and reports them under `repaired:`; a non-elevated run warns
`untrusted source symlink left in place` per link and fails `-Strict`.
`stow-all.ps1` walks the whole `codex` package, so its `unchanged/ignored:`
count includes every file of the submodule checkout.

## Rollback

- A bad bump: revert only the gitlink commit with a forward `git revert` on a
  branch, through a pull request. At the next login every host checks the
  submodule out at the previous commit and restows; confirm with
  `./doctor.sh --host <host>` (`.\doctor.ps1` on Windows). Never rewrite
  coding-agent-kit's `main` or move its tags; fix forward there and bump again.
- Back to regular files: a forward commit reverts the switch to the links and
  writes the 14 delivered files, `docs/account-launchers.md` and
  `docs/codex-as.md` back from the submodule commit that `main` records
  (`git -C common/codex/coding-agent-kit archive <sha> -- <paths> | tar -x`),
  so hosts get exactly the bytes they run. The submodule stays registered,
  checked out and ignored by Stow.
- Removing the submodule: while the package files are links, land the
  "Back to regular files" commit first and remove the submodule only in a
  later commit. Never remove it with a plain `git revert` or a per-host
  `git submodule deinit`, which leave an untracked checkout that freezes the
  login updater, or get it cloned again at the next pull. Use one forward
  commit that removes the gitlink and the `.gitmodules` entry, adds
  `/common/codex/coding-agent-kit/` to `.gitignore`, keeps the `.stowrc` line,
  and drops the doctor sentinel, the CI submodule steps and their test cases.
  Per-host cleanup is then optional:
  `rm -rf ~/dotfiles/common/codex/coding-agent-kit ~/dotfiles/.git/modules/common/codex/coding-agent-kit`
  (the same two paths under `$HOME\dotfiles` on Windows). Drop the
  `.gitignore` and `.stowrc` lines only in a later commit, after every host
  has done that cleanup.

## Verify

```sh
git submodule status common/codex/coding-agent-kit
readlink common/codex/.local/bin/codex-as     # ../../../codex/coding-agent-kit/common/codex/.local/bin/codex-as
ls -L ~/.local/bin/codex-as ~/.claude/dotfiles/statusline.cjs
./doctor.sh --host <host>                     # submodule row ok
bash tests/coding-agent-kit-delivery.sh       # fixtures; --ci fails without stow, --real checks the submodule
```
