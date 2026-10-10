# AI tier on macOS (S2-brew-bundle). Debian hosts install these from
# installers.tsv instead; Node.js comes from nvm on every workstation.
# pinned 2026-10-09: cask tokens verified on formulae.brew.sh.
# Homebrew will not install the claude-code cask while claude-code@latest is
# installed (conflicts_with), so S2-brew-bundle reads this line and stops
# first with an uninstall block.
# conflicts: cask claude-code claude-code@latest
cask "claude-code" if OS.mac?
cask "codex" if OS.mac?
