#!/bin/bash

# The wsl-ubuntu and lab-ubuntu overlays guard their Linuxbrew `brew
# shellenv` line, so a shell started before Linuxbrew exists stays quiet.
# Each zsh and bash rc file is sourced from a temporary copy under `env -i`,
# with a temporary HOME and PATH=/usr/bin:/bin, after /home/linuxbrew/.linuxbrew
# is replaced by (a) a missing prefix, (b) a prefix whose brew is not
# executable and (c) a prefix whose brew prints an export line. The overlays'
# absolute conda and mamba prefixes become missing paths too, so only the
# guard is under test. zsh files run with zsh -f (a SKIP line without zsh),
# bash files with bash --norc --noprofile.

set -euo pipefail

# Hermetic: the provisioning exports (DOTFILES_AUTO_UPDATE=0 and the like,
# docs/bootstrap.md) and other dotfiles knobs never reach the code under
# test from the caller; each case sets what it needs.
unset DOTFILES_AUTO_UPDATE DOTFILES_AUTO_STOW DOTFILES_HOST DOTFILES_DIR _DOTFILES_CHECKED \
    DOTFILES_STOW_WITHOUT_OH_MY_ZSH DOTFILES_COLOR AWESOME_SKILLS_AUTO_UPDATE AWESOME_SKILLS_FORCE \
    AWESOME_SKILLS_BG AWESOME_SKILLS_INSTALLER_URL AWESOME_SKILLS_REFRESH_DAYS _AWESOME_SKILLS_CHECKED

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-host-overlays.XXXXXX")"
TEST_TMP="$(cd -- "$TEST_TMP" && pwd -P)"
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

TEST_HOME="$TEST_TMP/home"
EVENT_LOG="$TEST_TMP/events.log"
MISSING_CONDA="$TEST_TMP/missing-conda"
mkdir -p "$TEST_HOME" "$TEST_TMP/copies"

# brew_prefix MODE: the Linuxbrew stand-in of MODE; only the fake one runs.
brew_prefix() {
    printf '%s\n' "$TEST_TMP/$1-brew"
}
PREFIX_NOEXEC=$(brew_prefix noexec)
PREFIX_FAKE=$(brew_prefix fake)
mkdir -p "$PREFIX_NOEXEC/bin" "$PREFIX_FAKE/bin"
cat >"$PREFIX_FAKE/bin/brew" <<'SH'
#!/bin/sh
printf 'brew %s\n' "$*" >>"$EVENT_LOG"
if [ "${1:-}" = shellenv ]; then
    printf '%s\n' 'export FAKE_BREW_SHELLENV=applied'
fi
SH
cp "$PREFIX_FAKE/bin/brew" "$PREFIX_NOEXEC/bin/brew"
chmod 755 "$PREFIX_FAKE/bin/brew"
chmod 644 "$PREFIX_NOEXEC/bin/brew"

# sed_escape TEXT: TEXT as a literal sed replacement with # as delimiter.
sed_escape() {
    printf '%s' "$1" | sed 's/[#&\\]/\\&/g'
}

# make_copy FILE MODE: a copy of FILE whose Linuxbrew prefix is MODE's and
# whose conda and mamba prefixes are missing; prints its path.
make_copy() {
    local file=$1 mode=$2 prefix copy
    prefix=$(brew_prefix "$mode")
    copy="$TEST_TMP/copies/${file//\//_}.$mode"
    sed -e "s#/home/linuxbrew/\\.linuxbrew#$(sed_escape "$prefix")#g" \
        -e "s#/[A-Za-z0-9._/-]*miniconda3#$(sed_escape "$MISSING_CONDA")#g" \
        "$REPO_ROOT/$file" >"$copy"
    ! grep -Eq '/home/linuxbrew|miniconda3' "$copy" || fail "$file: a prefix survived in the $mode copy"
    grep -Fq "$prefix/bin/brew" "$copy" || fail "$file: no Linuxbrew line to guard"
    printf '%s\n' "$copy"
}

# check_overlay SHELL FILE: source FILE's copy in every mode with SHELL.
check_overlay() {
    local shell=$1 file=$2 mode copy out err expected
    for mode in missing noexec fake; do
        copy=$(make_copy "$file" "$mode")
        out="$TEST_TMP/$mode.out"
        err="$TEST_TMP/$mode.err"
        : >"$EVENT_LOG"
        if [ "$shell" = zsh ]; then
            # _is_agent_session comes from ~/.zshrc, which sources the overlay.
            # shellcheck disable=SC2016 # expanded by the child zsh
            env -i HOME="$TEST_HOME" PATH=/usr/bin:/bin EVENT_LOG="$EVENT_LOG" "$ZSH_BIN" -f -c \
                '_is_agent_session() { return 1; }; source "$1"; print -r -- "FAKE_BREW_SHELLENV=${FAKE_BREW_SHELLENV-unset}"' \
                zsh "$copy" >"$out" 2>"$err" || fail "$file ($mode): zsh exited $?"
        else
            # shellcheck disable=SC2016 # expanded by the child bash
            env -i HOME="$TEST_HOME" PATH=/usr/bin:/bin EVENT_LOG="$EVENT_LOG" "$BASH_BIN" --norc --noprofile -c \
                'source "$1"; printf "FAKE_BREW_SHELLENV=%s\n" "${FAKE_BREW_SHELLENV-unset}"' \
                bash "$copy" >"$out" 2>"$err" || fail "$file ($mode): bash exited $?"
        fi
        if [ -s "$err" ]; then
            cat "$err" >&2
            fail "$file ($mode): sourcing wrote to stderr"
        fi
        expected='unset'
        [ "$mode" != fake ] || expected='applied'
        [ "$(tail -n 1 "$out")" = "FAKE_BREW_SHELLENV=$expected" ] ||
            fail "$file ($mode): brew shellenv $(tail -n 1 "$out"), expected $expected"
        if [ "$mode" = fake ]; then
            grep -Fxq 'brew shellenv' "$EVENT_LOG" || fail "$file ($mode): brew shellenv did not run"
        elif [ -s "$EVENT_LOG" ]; then
            fail "$file ($mode): brew ran: $(cat "$EVENT_LOG")"
        fi
    done
    printf 'ok: %s\n' "$file"
}

BASH_BIN=$(command -v bash)
for file in wsl-ubuntu/bash/.config/bash/.bashrc lab-ubuntu/bash/.config/bash/.bashrc; do
    check_overlay bash "$file"
done

if ZSH_BIN=$(command -v zsh); then
    for file in wsl-ubuntu/zsh/.config/zsh/.zshrc lab-ubuntu/zsh/.config/zsh/.zshrc; do
        check_overlay zsh "$file"
    done
else
    printf 'SKIP: zsh overlay guards (zsh unavailable).\n'
fi

echo "host-overlays=PASS"
