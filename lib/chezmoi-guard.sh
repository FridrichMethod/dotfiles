#!/bin/sh
# Home ownership guard: native binding and maintenance markers; sourcing writes nothing.

dotfiles_native_owned() {
    [ -e "${1%/}/.config/dotfiles/native" ] || [ -L "${1%/}/.config/dotfiles/native" ]
}

dotfiles_maintenance_active() {
    [ -e "${1%/}/.config/dotfiles/maintenance" ] || [ -L "${1%/}/.config/dotfiles/maintenance" ]
}

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
