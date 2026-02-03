#!/bin/bash

# tar alias
alias targz='tar -czvf'
alias untargz='tar -xzvf'

# nvim alias
alias vi='nvim'

# ssh for terminal
alias ssh='TERM=xterm-256color ssh'

# Load host-specific alias additions (if any)
if [[ -r "$HOME/.config/bash/.bash_aliases" ]]; then
    source "$HOME/.config/bash/.bash_aliases"
fi
