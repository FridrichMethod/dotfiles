#!/bin/zsh

# On macOS, oh-my-zsh's brew plugin runs `brew shellenv` when brew is not on
# PATH yet, which puts Homebrew's bin back ahead of the default node's bin
# that ~/.zshrc moved to the front. Move it ahead again only in that case:
# the plugins have filled the command hash table by now, and any PATH
# assignment empties it.
() {
    [[ -n ${NVM_BIN:-} && -n ${HOMEBREW_PREFIX:-} ]] || return 0
    local nvm=${path[(ie)$NVM_BIN]} brew=${path[(ie)$HOMEBREW_PREFIX/bin]}
    ((brew < nvm && nvm <= $#path)) || return 0
    path=("${(@)path[1,brew-1]}" "$NVM_BIN" "${(@)${(@)path[brew,-1]}:#$NVM_BIN}")
}

# nvm for interactive zsh, instead of the oh-my-zsh nvm plugin. ~/.profile
# has already put the default node's bin on PATH and exported NVM_DIR, so
# this only defines the nvm function and its completion: `--no-use` skips
# nvm's own `nvm use default` (~40 ms instead of ~0.5 s). node, npm and npm
# completion run the real binaries with no lazy wrapper, and there is no
# .nvmrc chpwd hook; run `nvm use` in a project that pins a version.
[[ -n ${NVM_DIR:-} && -r $NVM_DIR/nvm.sh ]] || return 0

(($+functions[nvm])) || source "$NVM_DIR/nvm.sh" --no-use

if [[ -r $NVM_DIR/bash_completion ]]; then
    autoload -Uz bashcompinit && bashcompinit
    # An empty ZSH_VERSION skips the compinit call in nvm's script.
    ZSH_VERSION= source "$NVM_DIR/bash_completion"
fi
