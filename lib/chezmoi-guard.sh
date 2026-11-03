#!/bin/sh
# Temporary Stage 4 home ownership guard; no writes or dependency on sync Python.

dotfiles_native_owned() {
    [ -e "${1%/}/.config/dotfiles/native" ] || [ -L "${1%/}/.config/dotfiles/native" ]
}

dotfiles_maintenance_active() {
    [ -e "${1%/}/.config/dotfiles/maintenance" ] || [ -L "${1%/}/.config/dotfiles/maintenance" ]
}

dotfiles_legacy_write_allowed() (
    _dg_target=$1
    if command -v cygpath >/dev/null 2>&1; then
        _dg_target=$(cygpath -u "$_dg_target") || return 1
    fi
    case $_dg_target in
        /*) ;;
        *) _dg_target=$PWD/$_dg_target ;;
    esac
    # Do not follow the final file link: it can still point into the checkout.
    if [ -d "$_dg_target" ]; then
        _dg_start=$_dg_target
    else
        _dg_start=$(dirname -- "$_dg_target") || return 1
    fi
    _dg_path=$_dg_start
    while :; do
        if dotfiles_native_owned "$_dg_path" || dotfiles_maintenance_active "$_dg_path"; then
            printf '%s\n' 'dotfiles: legacy write refused: destination is native-owned or in maintenance.' >&2
            return 1
        fi
        [ "$_dg_path" != / ] || break
        _dg_path=$(dirname -- "$_dg_path") || return 1
    done
    # Parent directories may themselves be links, including an app directory.
    _dg_path=$_dg_start
    while [ ! -d "$_dg_path" ]; do
        [ "$_dg_path" != / ] || return 1
        _dg_path=$(dirname -- "$_dg_path") || return 1
    done
    _dg_path=$(CDPATH='' cd -P -- "$_dg_path" && pwd -P) || return 1
    while :; do
        if dotfiles_native_owned "$_dg_path" || dotfiles_maintenance_active "$_dg_path"; then
            printf '%s\n' 'dotfiles: legacy write refused: destination is native-owned or in maintenance.' >&2
            return 1
        fi
        [ "$_dg_path" != / ] || break
        _dg_path=$(dirname -- "$_dg_path") || return 1
    done
)

dotfiles_native_source() (
    _dg_home=$(CDPATH='' cd -P -- "$1" && pwd -P) || return 1
    _dg_marker=${_dg_home%/}/.config/dotfiles/native
    [ -f "$_dg_marker" ] && [ ! -L "$_dg_marker" ] || return 1
    {
        IFS= read -r _dg_version && IFS= read -r _dg_destination &&
            IFS= read -r _dg_source && ! IFS= read -r _dg_extra && [ -z "$_dg_extra" ]
    } <"$_dg_marker" || return 1
    [ "$_dg_version" = dotfiles-chezmoi-v1 ] && [ "$_dg_destination" = "$_dg_home" ] || return 1
    case $_dg_source in
        /*) ;;
        *) return 1 ;;
    esac
    _dg_canonical=$(CDPATH='' cd -P -- "$_dg_source" && pwd -P) || return 1
    [ "$_dg_source" = "$_dg_canonical" ] && [ -f "$_dg_source/.chezmoiroot" ] || return 1
    printf '%s\n' "$_dg_source"
)
