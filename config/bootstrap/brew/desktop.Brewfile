# Desktop tier on macOS (S2-brew-bundle). lab-ubuntu installs kitty and the
# font from installers.tsv; Windows uses winget.json.
# pinned 2026-10-09: cask tokens verified on formulae.brew.sh.
# Homebrew will not install kitty or wezterm while its @nightly cask is
# installed (conflicts_with), so S2-brew-bundle reads these lines and stops
# first with an uninstall block.
# conflicts: cask kitty kitty@nightly
# conflicts: cask wezterm wezterm@nightly
cask "kitty" if OS.mac?
cask "wezterm" if OS.mac?
cask "font-caskaydia-mono-nerd-font" if OS.mac?
