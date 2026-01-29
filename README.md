# dotfiles

Personal dotfiles managed with GNU Stow. `common/` holds shared defaults and
OS folders layer overrides.

## Structure

```bash
dotfiles/
├─ common/        # shared packages
├─ mac/           # macOS overrides
├─ wsl-ubuntu/    # WSL Ubuntu overrides
├─ lab-ubuntu/    # lab Ubuntu overrides
└─ stow-all.sh    # optional helper
```

## Packages

- Zsh (`.zshenv`, `.zprofile`, `.zshrc`, aliases, custom plugins)
- Git + SSH
- Kitty, Vim, Conda
- PyMOL scripts (submodule)

## Usage

```
git clone <repo> ~/dotfiles
cd ~/dotfiles
stow common
stow mac   # or wsl-ubuntu / lab-ubuntu
```

`.stowrc` sets `--target=~`, so stow links into your home directory.

## Extras

- Init PyMOL submodule: `git submodule update --init --recursive`
- Add a new package: create the folder, mirror `$HOME` paths, run `stow <package>`
