# Fixture cli Brewfile. On bundle, the fake brew in tests/setup-host.sh links
# opt/<formula> for each brew "x" line; bundle check looks for those links.
# The conflicts line is the real cli.Brewfile's: a Cellar/tlrc or
# Cellar/tealdeer keg stops S2-brew-bundle while tldr is not installed.
# conflicts: tldr tlrc tealdeer
brew "jq"
brew "tldr"
