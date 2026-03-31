#!/bin/zsh

# Upload local files/dirs -> remote ~/Downloads/
upload() {
    if (( $# < 2 )); then
        print -u2 "Usage: upload <file_or_dir> [more_files...] <remote_host>"
        return 2
    fi

    local remote_host="${@[-1]}"
    local -a files=("${@[1,-2]}")

    rsync -avhP "${files[@]}" "${remote_host}:Downloads/"
}
