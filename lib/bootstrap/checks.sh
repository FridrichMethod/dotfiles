# shellcheck shell=bash
# Doctor checks for doctor.sh. Sourced only; defines functions and changes no
# shell options. Bash 3.2 compatible and `set -u` safe; every split sets its
# own IFS. Each check prints one line, STATUS<TAB>DETAIL, and returns 0;
# doctor.sh maps STATUS through the tier selection to a log level.
#   ok        present (and at or above its floor)
#   outdated  present below its floor
#   missing   absent, or a structural requirement is not met
#   warn      advisory: works, but differs from the documented setup
#   skip      not checkable here (a PowerShell module on unix, macOS locale)
#   human     a person must repair it (installer edits, stow before oh-my-zsh)
# Checks only read. git runs with --no-optional-locks, so it never refreshes
# the index. Fonts are found by file name, never through fc-list, which
# creates fontconfig caches under ~/.cache and in its prefix. venv-sync runs
# Python with -I -B, so it writes no bytecode. Tools whose version flag writes
# are presence-only rows in tools.tsv, so they never run: brew
# (.git/describe-cache), codex (~/.codex/tmp/arg0), nvim (its log) and
# pre-commit (__pycache__). Only bootstrap_check_auth (doctor.sh --online)
# may reach the network, and only bootstrap_check_smoke (doctor.sh --smoke)
# starts a shell, which may write shell caches. Test overrides:
# BOOTSTRAP_NVM_KEG_CANDIDATES, BOOTSTRAP_CLT_SHIMS and
# BOOTSTRAP_SYSTEM_FONT_DIRS (colon-separated paths).

# Structural checks run after the tools.tsv rows: id, tier, generic doc step
# (doctor.sh maps the step with bootstrap_doc_ref). These ids are reserved;
# tools.tsv never uses them.
# shellcheck disable=SC2034 # read by doctor.sh
BOOTSTRAP_STRUCTURAL_CHECKS='locale core H1-locale
venv-sync core S4-setup-sync
submodule core P0-preflight
stow-links core H7-stow
path-order core H7-stow
rc-pollution core X-rc-protection
omz-order core X-recovery
nvm-homebrew ai S4-nvm'

# Files under common/ that third-party installers append to through the stow
# symlinks in $HOME.
BOOTSTRAP_RC_FILES='common/zsh/.zshrc
common/zsh/.zshenv
common/zsh/.zprofile
common/sh/.profile
common/bash/.bashrc
common/bash/.bash_profile
common/bash/.bash_aliases'

# bootstrap_check_result STATUS DETAIL: print STATUS<TAB>DETAIL on one line
# (tabs, carriage returns and newlines in DETAIL become spaces).
bootstrap_check_result() {
    local detail=${2:-}
    detail=${detail//$'\t'/ }
    detail=${detail//$'\r'/ }
    detail=${detail//$'\n'/ }
    printf '%s\t%s\n' "$1" "$detail"
}

# bootstrap_in_colon_list ITEM LIST: 0 when the colon-separated LIST holds ITEM.
bootstrap_in_colon_list() {
    case ":$2:" in
        *":$1:"*) return 0 ;;
    esac
    return 1
}

# bootstrap_clt_shim PATH: 0 when PATH is one of macOS's developer-tool stubs
# (/usr/bin/git, /usr/bin/python3) and the Command Line Tools are absent, so
# running it would open the installer dialog instead of answering.
bootstrap_clt_shim() {
    local shims=${BOOTSTRAP_CLT_SHIMS-/usr/bin/git:/usr/bin/python3:/usr/bin/pip3}
    bootstrap_in_colon_list "$1" "$shims" || return 1
    [ "$(bootstrap_os)" = Darwin ] || return 1
    command -v xcode-select >/dev/null 2>&1 || return 1
    ! xcode-select -p >/dev/null 2>&1 </dev/null
}

# bootstrap_find_command SPEC: print the absolute path of the first command of
# the comma list SPEC found on PATH (functions and builtins never count). A
# CLT stub is skipped. Returns 1 when nothing is found, 2 when only stubs are.
bootstrap_find_command() {
    local rest=$1 name found status=1
    while [ -n "$rest" ]; do
        name=${rest%%,*}
        case $rest in
            *,*) rest=${rest#*,} ;;
            *) rest= ;;
        esac
        [ -n "$name" ] || continue
        found=$(type -P "$name" 2>/dev/null) || found=
        [ -n "$found" ] || continue
        if bootstrap_clt_shim "$found"; then
            status=2
            continue
        fi
        printf '%s\n' "$found"
        return 0
    done
    return "$status"
}

# bootstrap_doc_steps FILE: the step ids that FILE (docs/bootstrap.md) has a
# `### ID:` heading for, as one line " ID1 ID2 ... " (just " " when it has
# none). Returns 1, printing nothing, when FILE is not a readable file.
bootstrap_doc_steps() {
    [ -f "$1" ] && [ -r "$1" ] || return 1
    awk '
        /^### [A-Za-z0-9-]+:/ {
            id = $0
            sub(/^### /, "", id)
            sub(/:.*/, "", id)
            printf " %s", id
        }
        END { print " " }
    ' "$1"
}

# bootstrap_tool_row_valid ROW [STEPS]: 0 when a tools.tsv data row has
# exactly eight non-empty tab-separated cells and the vocabularies doctor.sh
# relies on, and, when STEPS (from bootstrap_doc_steps) is non-empty, a doc
# step that docs/bootstrap.md has a heading for. Prints the reason when not.
# tests/test_bootstrap_manifest.py is the full validator; this keeps the
# doctor fail-closed on a hand-edited manifest. The shape is judged with
# bootstrap_field, the splitter that selects rows by host, because `read`
# with a tab IFS merges runs of tabs and drops leading and trailing ones.
bootstrap_tool_row_valid() {
    local row=$1 steps=${2:-} shape=ok id tier hosts probe flag floor absent doc
    case $row in
        '' | "$BOOTSTRAP_TAB"* | *"$BOOTSTRAP_TAB" | *"$BOOTSTRAP_TAB$BOOTSTRAP_TAB"*)
            shape=bad
            ;;
    esac
    if [ "$shape" = bad ] || ! bootstrap_field "$row" 8 >/dev/null ||
        bootstrap_field "$row" 9 >/dev/null; then
        id=${row%%"$BOOTSTRAP_TAB"*}
        printf '%s\n' "row ${id:-?} does not have eight tab-separated columns (no empty cells, no leading or trailing tab)"
        return 1
    fi
    # Exactly seven single tabs separate eight non-empty cells, so this
    # read splits the row the same way bootstrap_field does.
    IFS=$BOOTSTRAP_TAB read -r id tier hosts probe flag floor absent doc <<EOF
$row
EOF
    case $id in
        [a-z0-9]*) ;;
        *)
            printf '%s\n' "row id '$id' is not [a-z0-9][a-z0-9-]*"
            return 1
            ;;
    esac
    case $id in
        *[!a-z0-9-]*)
            printf '%s\n' "row id '$id' is not [a-z0-9][a-z0-9-]*"
            return 1
            ;;
    esac
    case " $BOOTSTRAP_TIER_ORDER " in
        *" $tier "*) ;;
        *)
            printf '%s\n' "row $id has unknown tier '$tier'"
            return 1
            ;;
    esac
    case $hosts in
        all | unix) ;;
        '' | *[!a-z,-]* | ,* | *, | *,,*)
            printf '%s\n' "row $id has invalid hosts '$hosts'"
            return 1
            ;;
        *)
            if ! bootstrap_hosts_known "$hosts"; then
                printf '%s\n' "row $id names an unknown host in '$hosts'"
                return 1
            fi
            ;;
    esac
    case $probe in
        file:?* | dir:?*)
            if ! bootstrap_expand_path "${probe#*:}" >/dev/null; then
                printf '%s\n' "row $id probe path '${probe#*:}' cannot be expanded"
                return 1
            fi
            ;;
        env:*)
            case ${probe#env:} in
                '' | [0-9]* | *[!A-Za-z0-9_]*)
                    printf '%s\n' "row $id has an invalid env probe '$probe'"
                    return 1
                    ;;
            esac
            ;;
        font:?* | psmodule:?*) ;;
        *:* | '' | ,* | *, | *,,* | *[!A-Za-z0-9._+,-]*)
            printf '%s\n' "row $id has an unknown probe '$probe'"
            return 1
            ;;
    esac
    case $flag in
        --version | -V | -v | version | -) ;;
        *)
            printf '%s\n' "row $id has unknown version_flag '$flag'"
            return 1
            ;;
    esac
    if [ "$floor" != - ] && ! bootstrap_version_parts "$floor" >/dev/null; then
        printf '%s\n' "row $id has invalid floor '$floor'"
        return 1
    fi
    case $doc in
        *[!A-Za-z0-9-]*)
            printf '%s\n' "row $id has an invalid doc step '$doc'"
            return 1
            ;;
    esac
    case $steps in
        '' | *" $doc "*) ;;
        *)
            printf '%s\n' "row $id cites step '$doc', which has no '### $doc:' heading in docs/bootstrap.md"
            return 1
            ;;
    esac
    return 0
}

# bootstrap_hosts_known LIST: 0 when every name in the comma LIST is a host.
bootstrap_hosts_known() {
    local rest=$1 name
    while [ -n "$rest" ]; do
        name=${rest%%,*}
        case $rest in
            *,*) rest=${rest#*,} ;;
            *) rest= ;;
        esac
        bootstrap_profile_for_host "$name" >/dev/null || return 1
    done
    return 0
}

# bootstrap_check_version PATH FLAG FLOOR: ok/outdated/warn for a found tool.
bootstrap_check_version() {
    local target=$1 flag=$2 floor=$3 version rc
    if [ "$flag" = - ]; then
        bootstrap_check_result ok "found $target"
        return 0
    fi
    version=$(bootstrap_tool_version "$target" "$flag")
    if [ "$floor" = - ]; then
        if [ -n "$version" ]; then
            bootstrap_check_result ok "$version at $target"
        else
            bootstrap_check_result ok "version unknown at $target"
        fi
        return 0
    fi
    if [ -z "$version" ]; then
        bootstrap_check_result warn "version unknown, need >= $floor at $target"
        return 0
    fi
    if bootstrap_version_ge "$version" "$floor"; then
        rc=0
    else
        rc=$?
    fi
    case $rc in
        0) bootstrap_check_result ok "$version >= $floor at $target" ;;
        1) bootstrap_check_result outdated "$version < $floor at $target" ;;
        *) bootstrap_check_result warn "cannot compare $version with $floor at $target" ;;
    esac
}

# bootstrap_font_dirs: the font directories, one per line: the user's, then
# the system's and Homebrew's (BOOTSTRAP_SYSTEM_FONT_DIRS, a colon list,
# replaces those two in tests).
bootstrap_font_dirs() {
    local darwin=0 brew
    [ "$(bootstrap_os)" != Darwin ] || darwin=1
    if [ "$darwin" = 1 ]; then
        printf '%s\n' "$HOME/Library/Fonts"
    else
        printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/fonts" "$HOME/.fonts"
    fi
    if [ "${BOOTSTRAP_SYSTEM_FONT_DIRS+x}" = x ]; then
        printf '%s\n' "$BOOTSTRAP_SYSTEM_FONT_DIRS" | tr ':' '\n'
        return 0
    fi
    if [ "$darwin" = 1 ]; then
        printf '%s\n' /Library/Fonts
    else
        printf '%s\n' /usr/share/fonts /usr/local/share/fonts
    fi
    if brew=$(bootstrap_brew_bin); then
        printf '%s\n' "${brew%/bin/brew}/share/fonts"
    fi
}

# bootstrap_check_font FAMILY ABSENT: a font file whose name holds FAMILY
# without spaces, in any case (CaskaydiaMonoNerdFont-Regular.ttf), up to four
# levels below a font directory. A read-only scan on every platform: fc-list
# would create fontconfig caches in a fresh home.
bootstrap_check_font() {
    local family=$1 absent=$2 needle dir found
    needle=$(printf '%s' "$family" | tr -d ' ')
    while IFS= read -r dir; do
        if [ -z "$dir" ] || [ ! -d "$dir" ]; then
            continue
        fi
        found=$(
            find "$dir" -maxdepth 4 -iname "*$needle*" \( -type f -o -type l \) -print 2>/dev/null | sed -n 1p
            true
        )
        if [ -n "$found" ]; then
            bootstrap_check_result ok "font $family at $found"
            return 0
        fi
    done <<EOF
$(bootstrap_font_dirs)
EOF
    bootstrap_check_result missing "font $family: no font file named like $needle in the user, system or Homebrew font directories; $absent"
}

# bootstrap_check_tool PROBE VERSION_FLAG FLOOR ABSENT: one tools.tsv probe.
bootstrap_check_tool() {
    local probe=$1 flag=$2 floor=$3 absent=$4 target var rc
    case $probe in
        psmodule:*)
            bootstrap_check_result skip "PowerShell module ${probe#psmodule:}; doctor.ps1 checks it"
            ;;
        env:*)
            var=${probe#env:}
            if [ -n "${!var:-}" ]; then
                bootstrap_check_result ok "$var is set"
            else
                bootstrap_check_result missing "$var is not set; $absent"
            fi
            ;;
        font:*)
            bootstrap_check_font "${probe#font:}" "$absent"
            ;;
        file:* | dir:*)
            target=$(bootstrap_expand_path "${probe#*:}") || {
                bootstrap_check_result missing "cannot expand ${probe#*:}; $absent"
                return 0
            }
            case $probe in
                file:*) [ -f "$target" ] ;;
                *) [ -d "$target" ] ;;
            esac || {
                bootstrap_check_result missing "no $target; $absent"
                return 0
            }
            if [ "$flag" != - ] && [ -x "$target" ] && [ ! -d "$target" ]; then
                bootstrap_check_version "$target" "$flag" "$floor"
            else
                bootstrap_check_result ok "found $target"
            fi
            ;;
        *)
            if target=$(bootstrap_find_command "$probe"); then
                bootstrap_check_version "$target" "$flag" "$floor"
            else
                rc=$?
                if [ "$rc" = 2 ]; then
                    bootstrap_check_result missing "only the macOS stub for $probe, Command Line Tools are not installed; $absent"
                else
                    bootstrap_check_result missing "not found; $absent"
                fi
            fi
            ;;
    esac
    return 0
}

# bootstrap_check_locale PROFILE: en_US.UTF-8 is generated (skip on macOS).
bootstrap_check_locale() {
    local locale_bin list
    if [ "$1" = macos ]; then
        bootstrap_check_result skip "macOS ships en_US.UTF-8"
        return 0
    fi
    locale_bin=$(bootstrap_find_command locale) || {
        bootstrap_check_result warn "locale not found, cannot list generated locales"
        return 0
    }
    list=$("$locale_bin" -a </dev/null 2>/dev/null) || list=
    if grep -Eqi '^en_US\.utf-?8$' <<EOF
$list
EOF
    then
        bootstrap_check_result ok "en_US.UTF-8 is generated"
    else
        bootstrap_check_result missing "en_US.UTF-8 is not generated; LANG from ~/.profile falls back to C"
    fi
}

# bootstrap_sync_runtime_ok PYTHON ROOT: 0 when PYTHON passes
# ROOT/lib/config_sync.py --runtime-check (Python 3.11+ and the pinned
# tomlkit), as setup-sync.sh, setup-host's S4-setup-sync and doctor.ps1
# judge it. -I -B: isolated, and no bytecode is written.
bootstrap_sync_runtime_ok() {
    [ -n "$1" ] && [ -f "$1" ] && [ -x "$1" ] || return 1
    "$1" -I -B -X utf8 "$2/lib/config_sync.py" --runtime-check </dev/null >/dev/null 2>&1
}

# bootstrap_check_venv_sync ROOT: the AI-sync interpreter lib/sync-runtime.sh
# would use (DOTFILES_SYNC_PYTHON when set, else ROOT/.venv-sync) passes the
# runtime check; an interrupted setup-sync.sh leaves a venv that does not.
bootstrap_check_venv_sync() {
    local python
    if [ "${DOTFILES_SYNC_PYTHON+x}" = x ]; then
        python=$DOTFILES_SYNC_PYTHON
        if bootstrap_sync_runtime_ok "$python" "$1"; then
            bootstrap_check_result ok "DOTFILES_SYNC_PYTHON=$python passes the runtime check"
        else
            bootstrap_check_result missing "DOTFILES_SYNC_PYTHON='$python' fails lib/config_sync.py --runtime-check; the AI config sync helpers cannot run"
        fi
        return 0
    fi
    python=$1/.venv-sync/bin/python
    if bootstrap_sync_runtime_ok "$python" "$1"; then
        bootstrap_check_result ok "AI-sync runtime ready at $python"
    elif [ -f "$python" ] && [ -x "$python" ]; then
        bootstrap_check_result missing "$python fails lib/config_sync.py --runtime-check; rerun ./setup-sync.sh"
    else
        bootstrap_check_result missing "no executable $python; ./setup-sync.sh has not run, so ./stow-all.sh cannot sync the AI configs"
    fi
}

# bootstrap_check_submodule ROOT: the PyMOLScripts submodule is checked out.
bootstrap_check_submodule() {
    local rc=$1/common/pymol/PyMOLScripts/configs/.pymolrc
    if [ -f "$rc" ]; then
        bootstrap_check_result ok "found $rc"
    else
        bootstrap_check_result missing "no $rc; the stowed .pymolrc links dangle (git submodule update --init --recursive)"
    fi
}

# bootstrap_physical_path PATH: PATH with every symlink resolved (readlink
# without -f, which old BSD readlink lacks). Returns 1 on a loop or dead end.
bootstrap_physical_path() {
    local path=$1 target hops=0 dir
    while [ -L "$path" ]; do
        [ "$hops" -lt 40 ] || return 1
        target=$(readlink "$path") || return 1
        case $target in
            /*) path=$target ;;
            *) path=${path%/*}/$target ;;
        esac
        hops=$((hops + 1))
    done
    dir=${path%/*}
    [ -n "$dir" ] || dir=/
    dir=$(cd -P -- "$dir" 2>/dev/null && pwd -P) || return 1
    printf '%s/%s\n' "${dir%/}" "${path##*/}"
}

# bootstrap_check_stow_links ROOT: ~/.zshrc, ~/.profile and ~/.gitconfig are
# symlinks that resolve into ROOT/common/. A link into another checkout (a
# second clone or a worktree) is a warn; absent, dangling or regular files
# are missing.
bootstrap_check_stow_links() {
    local root broken='' elsewhere='' name link resolved
    root=$(cd -P -- "$1" 2>/dev/null && pwd -P) || root=$1
    for name in .zshrc .profile .gitconfig; do
        link=$HOME/$name
        if [ ! -L "$link" ]; then
            if [ -e "$link" ]; then
                broken="$broken, ~/$name is not a symlink"
            else
                broken="$broken, ~/$name is absent"
            fi
            continue
        fi
        if [ ! -e "$link" ]; then
            broken="$broken, ~/$name is a dangling symlink"
            continue
        fi
        resolved=$(bootstrap_physical_path "$link") || resolved=
        case $resolved in
            "$root"/common/*) ;;
            *) elsewhere="$elsewhere, ~/$name -> ${resolved:-unresolvable}" ;;
        esac
    done
    if [ -n "$broken" ]; then
        bootstrap_check_result missing "${broken#, }; stow with the line the H7-stow block of ./setup-host.sh prints"
    elif [ -n "$elsewhere" ]; then
        bootstrap_check_result warn "${elsewhere#, } (not $root/common)"
    else
        bootstrap_check_result ok "stow links ~/.zshrc, ~/.profile and ~/.gitconfig resolve into $root/common"
    fi
}

# The commands setup-host puts in ~/.local/bin (S5-claude, S5-codex,
# S2-micromamba, S6-kitty).
BOOTSTRAP_LOCAL_BIN_TOOLS='claude codex micromamba kitty kitten'

# bootstrap_check_path_order PATH_VALUE PROFILE: no command setup-host puts
# in ~/.local/bin is shadowed by another executable of the same name in a
# PATH entry before ~/.local/bin. The workstation overlays put Homebrew and
# conda ahead of it on purpose (they run after ~/.profile), as the sherlock
# and marlowe overlays do the login env, so only a real shadow, two installs
# of one tool, is reported; the login env is exempt on hpc. PATH_VALUE is the
# caller's PATH before doctor.sh prepended anything.
bootstrap_check_path_order() {
    local local_bin=${HOME%/}/.local/bin login=${HOME%/}/micromamba/envs/login/bin
    local rest=$1: entry earlier='' found=0 file name shadows='' count=0 IFS=' '
    while [ -n "$rest" ]; do
        entry=${rest%%:*}
        rest=${rest#*:}
        if [ "${entry%/}" = "$local_bin" ]; then
            found=1
            break
        fi
        if [ -n "$entry" ] && { [ "$2" != hpc ] || [ "${entry%/}" != "$login" ]; }; then
            earlier="$earlier$entry
"
        fi
    done
    if [ "$found" = 0 ]; then
        bootstrap_check_result warn "PATH lacks ~/.local/bin; the stowed ~/.profile prepends it"
        return 0
    fi
    for name in $BOOTSTRAP_LOCAL_BIN_TOOLS; do
        file=$local_bin/$name
        [ -f "$file" ] && [ -x "$file" ] || continue
        while IFS= read -r entry; do
            [ -n "$entry" ] || continue
            if [ -f "$entry/$name" ] && [ -x "$entry/$name" ] && ! [ "$entry/$name" -ef "$file" ]; then
                count=$((count + 1))
                [ "$count" -gt 3 ] || shadows="$shadows, $entry/$name"
                break
            fi
        done <<EOF
$earlier
EOF
    done
    if [ "$count" -gt 0 ]; then
        bootstrap_check_result warn "$count command(s) in ~/.local/bin are shadowed by an earlier PATH entry: ${shadows#, }; two installs of one tool, remove the one you do not use"
    else
        bootstrap_check_result ok "no command setup-host puts in ~/.local/bin is shadowed by an earlier PATH entry"
    fi
}

# bootstrap_check_rc_pollution ROOT: traces of installers that edit rc files:
# ~/.zshrc.pre-oh-my-zsh (upstream oh-my-zsh installer), a Codex installer,
# conda/mamba initialize or nvm loader block in a common/ rc file (they reach
# it through the stow symlink), and uncommitted changes under common/.
# shellcheck disable=SC2016 # the nvm marker is literal installer text
bootstrap_check_rc_pollution() {
    local root=$1 findings='' file dirty='' count first git_bin
    if [ -e "$HOME/.zshrc.pre-oh-my-zsh" ] || [ -L "$HOME/.zshrc.pre-oh-my-zsh" ]; then
        findings="$findings; ~/.zshrc.pre-oh-my-zsh exists (the upstream oh-my-zsh installer replaced ~/.zshrc)"
    fi
    while IFS= read -r file; do
        if [ -z "$file" ] || [ ! -f "$root/$file" ]; then
            continue
        fi
        if grep -Fq -e '>>> Codex installer >>>' "$root/$file" 2>/dev/null; then
            findings="$findings; $file has a Codex installer block"
        fi
        if grep -Fq -e '>>> conda initialize >>>' -e '>>> mamba initialize >>>' "$root/$file" 2>/dev/null; then
            findings="$findings; $file has a conda or mamba initialize block"
        fi
        if grep -Fq -e '# This loads nvm' -e '[ -s "$NVM_DIR/nvm.sh" ]' "$root/$file" 2>/dev/null; then
            findings="$findings; $file has an nvm installer loader"
        fi
    done <<EOF
$BOOTSTRAP_RC_FILES
EOF
    if git_bin=$(bootstrap_find_command git); then
        if dirty=$("$git_bin" --no-optional-locks -C "$root" status --porcelain -- common </dev/null 2>/dev/null); then
            if [ -n "$dirty" ]; then
                count=$(printf '%s\n' "$dirty" | grep -c .) || count=0
                first=$(printf '%s\n' "$dirty" | sed -n 1p)
                dirty="$count uncommitted change(s) under common/, first: ${first#???}"
            fi
        else
            dirty=
        fi
    fi
    if [ -n "$findings" ]; then
        [ -z "$dirty" ] || findings="$findings; $dirty"
        bootstrap_check_result human "${findings#; }"
    elif [ -n "$dirty" ]; then
        bootstrap_check_result warn "$dirty (an installer may have edited a stowed file)"
    else
        bootstrap_check_result ok "no installer blocks in the common rc files and common/ is clean"
    fi
}

# bootstrap_check_omz_order: ~/.oh-my-zsh exists without oh-my-zsh.sh, the
# state ./stow-all.sh leaves when it runs before the oh-my-zsh clone.
bootstrap_check_omz_order() {
    local omz=$HOME/.oh-my-zsh
    if [ -d "$omz" ] && [ ! -f "$omz/oh-my-zsh.sh" ]; then
        bootstrap_check_result human "oh-my-zsh.sh is missing from an existing ~/.oh-my-zsh (stow ran before the clone); follow the recovery recipe"
    elif [ -f "$omz/oh-my-zsh.sh" ]; then
        bootstrap_check_result ok "found ~/.oh-my-zsh/oh-my-zsh.sh"
    else
        bootstrap_check_result ok "no ~/.oh-my-zsh yet, so nothing was stowed into it"
    fi
}

# bootstrap_check_nvm_homebrew: a Homebrew nvm keg, which this repo does not
# support (only ~/.nvm or $XDG_CONFIG_HOME/nvm from the official installer).
bootstrap_check_nvm_homebrew() {
    local rest=${BOOTSTRAP_NVM_KEG_CANDIDATES-/opt/homebrew/opt/nvm:/usr/local/opt/nvm:/home/linuxbrew/.linuxbrew/opt/nvm}
    local keg
    while [ -n "$rest" ]; do
        keg=${rest%%:*}
        case $rest in
            *:*) rest=${rest#*:} ;;
            *) rest= ;;
        esac
        if [ -n "$keg" ] && { [ -e "$keg" ] || [ -L "$keg" ]; }; then
            bootstrap_check_result warn "Homebrew nvm at $keg is unsupported; use the official installer (brew uninstall nvm)"
            return 0
        fi
    done
    bootstrap_check_result ok "no Homebrew nvm keg"
}

# bootstrap_check_structural ID ROOT PROFILE PATH_VALUE: run one structural
# check by its reserved id.
bootstrap_check_structural() {
    case $1 in
        locale) bootstrap_check_locale "$3" ;;
        venv-sync) bootstrap_check_venv_sync "$2" ;;
        submodule) bootstrap_check_submodule "$2" ;;
        stow-links) bootstrap_check_stow_links "$2" ;;
        path-order) bootstrap_check_path_order "$4" "$3" ;;
        rc-pollution) bootstrap_check_rc_pollution "$2" ;;
        omz-order) bootstrap_check_omz_order ;;
        nvm-homebrew) bootstrap_check_nvm_homebrew ;;
        *) bootstrap_check_result warn "unknown structural check $1" ;;
    esac
}

# bootstrap_timeout_bin: print timeout or gtimeout (coreutils on macOS); 1 if
# neither exists.
bootstrap_timeout_bin() {
    bootstrap_find_command timeout,gtimeout
}

# bootstrap_check_auth gh|claude|codex: the CLI's own auth status command,
# bounded by a timeout when one is available. Never an error: a failure is
# warn. Its output (account names, tokens' scopes) is discarded.
bootstrap_check_auth() {
    local tool=$1 cmd timeout_bin rc
    cmd=$(bootstrap_find_command "$tool") || {
        bootstrap_check_result skip "$tool not found, auth not checked"
        return 0
    }
    timeout_bin=$(bootstrap_timeout_bin) || timeout_bin=
    set -- "$cmd"
    case $tool in
        gh | claude) set -- "$@" auth status ;;
        codex) set -- "$@" login status ;;
        *)
            bootstrap_check_result warn "no auth probe for $tool"
            return 0
            ;;
    esac
    if [ -n "$timeout_bin" ]; then
        set -- "$timeout_bin" 30 "$@"
    fi
    if "$@" </dev/null >/dev/null 2>&1; then
        bootstrap_check_result ok "$tool is authenticated"
    else
        rc=$?
        bootstrap_check_result warn "$tool is not authenticated or could not reach its service (exit $rc)"
    fi
}

# bootstrap_check_smoke PATH_VALUE: start an interactive zsh as a new terminal
# would (PATH_VALUE, update hooks off, stdin from /dev/null) and scan its
# stderr for missing plugins, commands and files.
bootstrap_check_smoke() {
    local path_value=${1:-$PATH} zsh_bin timeout_bin err rc esc findings count
    zsh_bin=$(bootstrap_find_command zsh) || {
        bootstrap_check_result missing "zsh not found, smoke test not run"
        return 0
    }
    timeout_bin=$(bootstrap_timeout_bin) || timeout_bin=
    set -- "$zsh_bin" -ic true
    if [ -n "$timeout_bin" ]; then
        set -- "$timeout_bin" 60 "$@"
    fi
    if err=$(PATH=$path_value DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0 "$@" </dev/null 2>&1 >/dev/null); then
        rc=0
    else
        rc=$?
    fi
    esc=$(printf '\033')
    err=$(printf '%s\n' "$err" | sed "s/${esc}\\[[0-9;?]*[A-Za-z]//g" | tr -d '\r')
    findings=$(printf '%s\n' "$err" | grep -Ei 'plugin .* not found|command not found|no such file' | sed -n 1,3p) || findings=
    if [ -n "$findings" ]; then
        count=$(printf '%s\n' "$err" | grep -Eci 'plugin .* not found|command not found|no such file') || count=0
        findings=$(printf '%s\n' "$findings" | tr '\n' ';')
        bootstrap_check_result missing "zsh -ic true printed $count finding(s): ${findings%;}"
    elif [ "$rc" = 124 ] && [ -n "$timeout_bin" ]; then
        bootstrap_check_result missing "zsh -ic true timed out after 60 s"
    elif [ "$rc" != 0 ]; then
        bootstrap_check_result missing "zsh -ic true exited $rc"
    else
        bootstrap_check_result ok "zsh -ic true started without errors"
    fi
}
