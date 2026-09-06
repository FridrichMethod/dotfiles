#!/bin/sh
# Shared POSIX terminal output. Sourcing is silent and changes no shell flags.
# NO_COLOR and TERM=dumb win over DOTFILES_COLOR=auto|always|never.

# Powerlevel10k's instant prompt swaps fd 1 and 2 for a capture file while the
# rest of ~/.zshrc runs, then replays that file verbatim to the terminal it
# saved in $__p9k_fd_1/$__p9k_fd_2. Login hooks therefore write to a regular
# file even though their output reaches a terminal, so auto keeps color for
# that replay only. A non-numeric or stale saved descriptor stays plain: `-t`
# reports an illegal number on stderr in dash, which sourcing must never emit.
dotfiles_captured_tty() (
    [ -n "${__p9k_instant_prompt_active:-}" ] || return 1
    case $1 in
        1) _dt_tty_fd=${__p9k_fd_1:-} ;;
        2) _dt_tty_fd=${__p9k_fd_2:-} ;;
        *) return 1 ;;
    esac
    case $_dt_tty_fd in
        '' | *[!0-9]*) return 1 ;;
    esac
    [ -t "$_dt_tty_fd" ]
)

dotfiles_color_enabled() {
    [ -z "${NO_COLOR:-}" ] || return 1
    [ "${TERM:-}" != dumb ] || return 1
    case "${DOTFILES_COLOR:-auto}" in
        always) return 0 ;;
        never) return 1 ;;
        *) [ -t "$1" ] || dotfiles_captured_tty "$1" ;;
    esac
}

dotfiles_log() (
    _dt_level=$1
    shift
    _dt_fd=1
    case $_dt_level in
        step) _dt_style='1;36' ;;
        ok) _dt_style=32 ;;
        warn)
            _dt_style=33
            _dt_fd=2
            ;;
        error)
            _dt_style=31
            _dt_fd=2
            ;;
        *)
            _dt_level=info
            _dt_style=
            ;;
    esac
    if [ -n "$_dt_style" ] && dotfiles_color_enabled "$_dt_fd"; then
        printf '\033[%sm[dotfiles] [%s]\033[0m %s\n' "$_dt_style" "$_dt_level" "$*" >&"$_dt_fd"
    else
        printf '[dotfiles] [%s] %s\n' "$_dt_level" "$*" >&"$_dt_fd"
    fi
)
