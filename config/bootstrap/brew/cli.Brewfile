# CLI tier: tools the aliases, previews and workflows use (S2-brew-bundle).
# pinned 2026-10-27: formula names verified on formulae.brew.sh.
# tlrc is the official Rust tldr client and installs `tldr`; Homebrew removed
# the tldr formula, the C client (tldr-c-client), on 2026-10-25, but keeps a
# keg of it on a host that installed it. Homebrew will not install tlrc while
# tealdeer is installed (conflicts_with: both install `tldr`), and a leftover
# C client keg holds the same `tldr`, so S2-brew-bundle reads this line and
# stops first with an uninstall block. A keg whose linked `tldr` the doctor
# accepts satisfies the entry instead, so nothing conflicts.
# conflicts: tlrc tldr tealdeer
brew "ripgrep"
brew "git-delta"
brew "tlrc"
brew "chafa"
brew "jq"
brew "neovim"
brew "aria2"
brew "uv"
brew "gh"
