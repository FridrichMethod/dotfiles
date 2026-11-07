#!/bin/sh
# Home guard: the source checkout this home's chezmoi config names, and the
# maintenance marker. Sourcing defines functions only and writes nothing.

# dotfiles_config_exists HOME: HOME/.config/chezmoi/chezmoi.toml exists in any
# form, a dangling link included.
dotfiles_config_exists() {
    [ -e "${1%/}/.config/chezmoi/chezmoi.toml" ] || [ -L "${1%/}/.config/chezmoi/chezmoi.toml" ]
}

dotfiles_maintenance_active() {
    [ -e "${1%/}/.config/dotfiles/maintenance" ] || [ -L "${1%/}/.config/dotfiles/maintenance" ]
}

# dotfiles_chezmoi_source HOME: print the source checkout that
# HOME/.config/chezmoi/chezmoi.toml names, or return 1 without output. Only the
# form chezmoi init writes passes: a regular file, not a link, whose lines
# before the first table hold exactly one 'sourceDir = "VALUE"' and one
# 'destDir = "VALUE"' line at column 0, LF line ends, and no quote, backslash
# or control character in VALUE. Any other spelling of either key, a
# workingTree key, a line starting with a quote and a multi-line string
# before the first table refuse. destDir is the canonical HOME; sourceDir is
# an absolute canonical directory holding .chezmoiroot. Reads text only and
# never runs chezmoi.
dotfiles_chezmoi_source() (
    _dg_home=$(CDPATH='' cd -P -- "$1" 2>/dev/null && pwd -P) || return 1
    _dg_config=${_dg_home%/}/.config/chezmoi/chezmoi.toml
    [ -f "$_dg_config" ] && [ ! -L "$_dg_config" ] || return 1
    _dg_source='' _dg_destination='' _dg_sources=0 _dg_destinations=0
    while IFS= read -r _dg_line || [ -n "$_dg_line" ]; do
        _dg_text=${_dg_line#"${_dg_line%%[![:blank:]]*}"}
        case $_dg_text in
            '['*) break ;;
            *'"""'* | *"'''"* | \"* | \'*) return 1 ;;
        esac
        case $_dg_line in
            'sourceDir = "'*'"')
                _dg_sources=$((_dg_sources + 1))
                _dg_source=${_dg_line#'sourceDir = "'}
                _dg_source=${_dg_source%'"'}
                ;;
            'destDir = "'*'"')
                _dg_destinations=$((_dg_destinations + 1))
                _dg_destination=${_dg_line#'destDir = "'}
                _dg_destination=${_dg_destination%'"'}
                ;;
            *)
                case $_dg_text in
                    [Ss][Oo][Uu][Rr][Cc][Ee][Dd][Ii][Rr][=[:blank:]]* | \
                        [Dd][Ee][Ss][Tt][Dd][Ii][Rr][=[:blank:]]* | \
                        [Ww][Oo][Rr][Kk][Ii][Nn][Gg][Tt][Rr][Ee][Ee][=[:blank:]]*)
                        return 1
                        ;;
                esac
                ;;
        esac
    done <"$_dg_config"
    [ "$_dg_sources" = 1 ] && [ "$_dg_destinations" = 1 ] || return 1
    case $_dg_source$_dg_destination in
        *\"* | *\\* | *[[:cntrl:]]*) return 1 ;;
    esac
    [ "$_dg_destination" = "$_dg_home" ] || return 1
    case $_dg_source in
        /*) ;;
        *) return 1 ;;
    esac
    _dg_canonical=$(CDPATH='' cd -P -- "$_dg_source" 2>/dev/null && pwd -P) || return 1
    [ "$_dg_source" = "$_dg_canonical" ] && [ -f "$_dg_source/.chezmoiroot" ] || return 1
    printf '%s\n' "$_dg_source"
)
