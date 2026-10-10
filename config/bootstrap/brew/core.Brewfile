# Core tier: what the stowed shell config needs at login (S2-brew-bundle).
# pinned 2026-10-09: formula names verified on formulae.brew.sh; Homebrew
# installs its current bottle, and `brew bundle --no-upgrade` never upgrades.
# Never add openssh (the macOS ssh config uses Apple's UseKeychain) or nvm
# (Homebrew-installed nvm is unsupported; see installers.tsv).
brew "stow"
brew "python@3.14"
brew "fzf"
brew "zoxide"
brew "eza"
brew "fd"
brew "bat"
# Debian and Ubuntu get these from apt (apt/common.txt). A Linuxbrew tmux
# beside /usr/bin/tmux would split clients and servers by PATH.
brew "git-lfs" if OS.mac?
brew "tmux" if OS.mac?
