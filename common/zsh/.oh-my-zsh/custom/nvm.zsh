#!/bin/zsh

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

# oh-my-zsh sources this file after its plugins, so Homebrew's shellenv and
# conda's hook have prepended bins that can hold another node or
# tree-sitter. Move nvm's bin back to the front, where `nvm use` puts it,
# and export what `nvm use` would.
() {
    local bin=${path[(r)${(b)NVM_DIR}/versions/node/*/bin]}
    [[ -n $bin ]] || return 0
    path=("$bin" "${(@)path:#$bin}")
    export NVM_BIN=$bin NVM_INC=${bin%/bin}/include/node
}
