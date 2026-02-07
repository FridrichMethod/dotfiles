#!/bin/zsh

# Download files/dirs from remote -> local ~/Downloads/
download() {
    if (( $# == 0 )); then
        print -u2 "usage: download <file_or_dir> [more_files_or_dirs...]"
        return 2
    fi

    if ! command -v kitten >/dev/null 2>&1; then
        print -u2 "download: 'kitten' not found. Tip: login using 'kitten ssh user@host' (recommended) or install kitty/kitten on this remote."
        return 127
    fi

    # If a public key is set, use it to bypass permissions.
    local -a transfer_opts
    transfer_opts=(--transmit-deltas --compress=auto)
    if [[ -n "${KITTY_PUBLIC_KEY:-}" ]]; then
        transfer_opts+=(--permissions-bypass yes)
    fi

    # NOTE:
    # - Destination 'Downloads/' is interpreted on the RECEIVING side (your local machine).
    # - Do NOT use ~/Downloads here; it will be expanded on the remote and may map to /home/... on local.
    kitten transfer \
        "${transfer_opts[@]}" \
        "$@" \
        Downloads/
}
