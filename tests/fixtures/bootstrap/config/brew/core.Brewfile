# Fixture core Brewfile. On bundle, the fake brew in tests/setup-host.sh links
# opt/<formula> for each brew "x" line that applies on the case's OS (Darwin
# or not); bundle check looks for those links. python is macOS-only, as in the
# real core.Brewfile.
brew "fzf"
brew "python" if OS.mac?
