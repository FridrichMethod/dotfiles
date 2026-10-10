# Core tier: what the stowed shell config needs at login (S2-brew-bundle).
# pinned 2026-10-09: formula names verified on formulae.brew.sh; Homebrew
# installs its current bottle, and `brew bundle --no-upgrade` never upgrades.
# Never add openssh (the macOS ssh config uses Apple's UseKeychain) or nvm
# (Homebrew-installed nvm is unsupported; see installers.tsv).
brew "stow"
# python is Homebrew's alias for its default python@3.x, the only formula that
# links an unversioned python3; the others install python3.N alone, so a
# versioned pin loses python3 when the default moves (python resolved to
# python@3.15 on 2026-10-09, after python@3.14). Even with --no-upgrade, brew
# bundle installs the new default whenever the alias moves (the old keg stays
# beside it), so python is bundled on macOS only, where it is needed (the CLT
# python3 is 3.9). Debian and Ubuntu use apt's python3 and python3-venv
# (apt/common.txt, H1-apt-core; 24.04 ships 3.12), and a Linuxbrew python
# would relink python3 for every user of a shared prefix.
brew "python" if OS.mac?
brew "fzf"
brew "zoxide"
brew "eza"
# Homebrew will not install fd while the fdclone formula is installed
# (conflicts_with: both install `fd`), so S2-brew-bundle reads this line and
# stops first with an uninstall block.
# conflicts: fd fdclone
brew "fd"
brew "bat"
# Debian and Ubuntu get these from apt (apt/common.txt). A Linuxbrew tmux
# beside /usr/bin/tmux would split clients and servers by PATH.
brew "git-lfs" if OS.mac?
brew "tmux" if OS.mac?
