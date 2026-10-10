# Fixture cli Brewfile. On bundle, the fake brew in tests/setup-host.sh links
# opt/<formula> for each brew "x" line; bundle check looks for those links.
# The conflicts line is the real cli.Brewfile's: a Cellar/tldr or
# Cellar/tealdeer keg stops S2-brew-bundle while tlrc is not installed.
# conflicts: tlrc tldr tealdeer
brew "jq"
brew "tlrc"
