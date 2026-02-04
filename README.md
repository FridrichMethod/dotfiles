# dotfiles

Personal dotfiles managed with GNU Stow. `common/` holds shared defaults and
host folders layer overrides.

## Structure

```bash
dotfiles/
├─ common/        # shared packages
├─ mac/           # macOS overrides
├─ wsl-ubuntu/    # WSL Ubuntu overrides
├─ lab-ubuntu/    # lab Ubuntu overrides
├─ marlowe/       # host overrides
├─ sherlock/      # host overrides
├─ win/           # Windows-side config (e.g. WSL)
└─ stow-all.sh    # optional helper
```

## Packages

- Zsh, Bash, POSIX sh, tcsh, xonsh
- Git + SSH
- Kitty + WezTerm
- Vim, Conda
- PyMOL scripts (submodule)
- Windows WSL config (`win/wsl/.wslconfig`)

## Usage

```bash
git clone <repo> ~/dotfiles
cd ~/dotfiles
./stow-all.sh <host-dir>
```

`.stowrc` sets `--target=~`, so stow links into your home directory.

## Pre-commit

Optional hooks for formatting/linting before commit:

```bash
pip install pre-commit  # or: brew install pre-commit
pre-commit install
pre-commit run --all-files
```

Hooks include `shellcheck` for `.sh`/`.bash*`, `shfmt` for `.sh`/`.bash*`/`.zsh*`,
`stylua` for `*.lua`, plus basic whitespace, EOF, merge-conflict, YAML, JSON,
and TOML checks.

## Extras

- Init PyMOL submodule: `git submodule update --init --recursive`
- Add a new package: create the folder, mirror `$HOME` paths, run `stow <package>`
