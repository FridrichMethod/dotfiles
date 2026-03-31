#!/bin/bash

# Upload local files/dirs -> remote ~/Downloads/
upload() {
    if (($# < 2)); then
        echo "Usage: upload <file_or_dir> [more_files...] <remote_host>" >&2
        return 2
    fi

    local remote_host="${*: -1}"
    local -a files
    files=("${@:1:$#-1}")

    rsync -avhP "${files[@]}" "${remote_host}:Downloads/"
}
