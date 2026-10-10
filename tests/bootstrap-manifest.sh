#!/bin/bash

# Fixture tests for lib/bootstrap/{manifest,platform,version}.sh, then the
# stdlib validator for config/bootstrap (tests/test_bootstrap_manifest.py).
# Nothing here reads or writes the runner's real home.

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
TEST_PYTHON=${DOTFILES_SYNC_PYTHON:-$(command -v python3 || true)}
[ -n "$TEST_PYTHON" ] || {
    echo 'ERROR: python3 is required for the manifest validator.' >&2
    exit 1
}
REAL_GIT=$(command -v git)
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-bootstrap-manifest.XXXXXX")"
TEST_TMP="$(cd -- "$TEST_TMP" && pwd -P)"
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM

FIXTURE="$TEST_TMP/fixture"
FAKE_BIN="$TEST_TMP/bin"
TEST_HOME="$TEST_TMP/home"
EVENT_LOG="$TEST_TMP/events.log"
export EVENT_LOG
mkdir -p "$FIXTURE/lib/bootstrap" "$FIXTURE/config/bootstrap/brew" \
    "$FIXTURE/config/bootstrap/apt" "$FAKE_BIN" "$TEST_HOME"
cp "$REPO_ROOT"/lib/bootstrap/manifest.sh "$REPO_ROOT"/lib/bootstrap/platform.sh \
    "$REPO_ROOT"/lib/bootstrap/version.sh "$FIXTURE/lib/bootstrap/"
: >"$EVENT_LOG"

export HOME="$TEST_HOME"
export PATH="$FAKE_BIN:/usr/bin:/bin"
export LC_ALL=C
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset ZSH ZSH_CUSTOM NVM_DIR XDG_CONFIG_HOME XDG_DATA_HOME BAT_CONFIG_DIR \
    BOOTSTRAP_CONFIG BOOTSTRAP_UNAME_S BOOTSTRAP_UNAME_M BOOTSTRAP_OS_RELEASE \
    BOOTSTRAP_PROC_VERSION LMOD_DIR SLURM_JOB_ID WSL_DISTRO_NAME DOTFILES_HOST

# shellcheck source=lib/bootstrap/manifest.sh
. "$FIXTURE/lib/bootstrap/manifest.sh"
# shellcheck source=lib/bootstrap/platform.sh
. "$FIXTURE/lib/bootstrap/platform.sh"
# shellcheck source=lib/bootstrap/version.sh
. "$FIXTURE/lib/bootstrap/version.sh"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    [ "$1" = "$2" ] || fail "$3: expected [$2], got [$1]"
}

# assert_status EXPECTED LABEL COMMAND...: run COMMAND, compare its status.
assert_status() {
    local expected=$1 label=$2 status=0
    shift 2
    "$@" >/dev/null 2>&1 || status=$?
    [ "$status" = "$expected" ] || fail "$label: expected status $expected, got $status"
}

assert_events() {
    local expected="$TEST_TMP/expected-events.log"
    if [ "$#" -eq 0 ]; then
        : >"$expected"
    else
        printf '%s\n' "$@" >"$expected"
    fi
    if ! cmp -s "$expected" "$EVENT_LOG"; then
        diff -u "$expected" "$EVENT_LOG" >&2 || true
        fail 'unexpected tool invocations'
    fi
    : >"$EVENT_LOG"
}

tab=$(printf '\t')
row() {
    local IFS=$tab
    printf '%s\n' "$*"
}

# ---------------------------------------------------------------- platform
echo '==> platform detection'
assert_eq "$(bootstrap_known_hosts | tr '\n' ' ')" 'mac wsl-ubuntu lab-ubuntu sherlock marlowe win ' 'known hosts'
for pair in mac:macos wsl-ubuntu:debian lab-ubuntu:debian sherlock:hpc marlowe:hpc win:windows; do
    assert_eq "$(bootstrap_profile_for_host "${pair%%:*}")" "${pair#*:}" "profile of ${pair%%:*}"
done
assert_status 2 'unknown host profile' bootstrap_profile_for_host fedora
assert_status 2 'empty host profile' bootstrap_profile_for_host ''

assert_eq "$(BOOTSTRAP_UNAME_S=Darwin bootstrap_os)" Darwin 'uname -s override'
assert_eq "$(BOOTSTRAP_UNAME_M=arm64 bootstrap_arch)" aarch64 'arm64 arch'
assert_eq "$(BOOTSTRAP_UNAME_M=aarch64 bootstrap_arch)" aarch64 'aarch64 arch'
assert_eq "$(BOOTSTRAP_UNAME_M=x86_64 bootstrap_arch)" x86_64 'x86_64 arch'
assert_eq "$(BOOTSTRAP_UNAME_M=amd64 bootstrap_arch)" x86_64 'amd64 arch'
assert_status 1 'unsupported arch' env BOOTSTRAP_UNAME_M=ppc64le bash -c \
    '. "$1"; bootstrap_arch' _ "$FIXTURE/lib/bootstrap/platform.sh"

OS_RELEASE="$TEST_TMP/os-release"
detect() {
    # detect UNAME OS_RELEASE_TEXT [VAR=VALUE...]
    local uname=$1 text=$2
    shift 2
    printf '%s\n' "$text" >"$OS_RELEASE"
    env BOOTSTRAP_UNAME_S="$uname" BOOTSTRAP_OS_RELEASE="$OS_RELEASE" "$@" \
        bash -c 'set -eu; . "$1"; bootstrap_detect_platform' _ "$FIXTURE/lib/bootstrap/platform.sh"
}
assert_eq "$(detect Darwin '')" macos 'Darwin'
assert_eq "$(detect Linux 'ID=ubuntu')" debian 'Ubuntu'
assert_eq "$(detect Linux 'ID="debian"')" debian 'quoted Debian'
assert_eq "$(detect Linux "$(printf 'NAME="Linux Mint"\nID=linuxmint\nID_LIKE="ubuntu debian"')")" debian 'ID_LIKE ubuntu'
assert_eq "$(detect Linux "$(printf 'ID="rocky"\nID_LIKE="rhel centos fedora"')")" other 'Rocky without Lmod'
assert_eq "$(detect Linux "$(printf 'ID="rocky"\nID_LIKE="rhel centos fedora"')" LMOD_DIR=/share/lmod/lmod/libexec)" hpc 'Rocky with Lmod'
assert_eq "$(detect Linux 'ID=ubuntu' LMOD_DIR=/usr/share/lmod/lmod/libexec)" hpc 'Ubuntu cluster with Lmod'
assert_eq "$(detect Linux 'ID=ubuntu' LMOD_DIR=)" debian 'empty LMOD_DIR'
assert_eq "$(detect FreeBSD 'ID=freebsd')" other 'FreeBSD'
assert_eq "$(env BOOTSTRAP_UNAME_S=Linux BOOTSTRAP_OS_RELEASE="$TEST_TMP/missing" bash -c \
    '. "$1"; bootstrap_detect_platform' _ "$FIXTURE/lib/bootstrap/platform.sh")" other 'no os-release'
printf 'ID=$(touch %s)\n' "$TEST_TMP/injected" >"$OS_RELEASE"
assert_eq "$(BOOTSTRAP_UNAME_S=Linux BOOTSTRAP_OS_RELEASE="$OS_RELEASE" bootstrap_detect_platform)" other 'os-release is data'
[ ! -e "$TEST_TMP/injected" ] || fail 'os-release content was executed'

PROC_VERSION="$TEST_TMP/proc-version"
printf 'Linux version 6.6.87.2-microsoft-standard-WSL2\n' >"$PROC_VERSION"
assert_status 0 'WSL kernel' env BOOTSTRAP_PROC_VERSION="$PROC_VERSION" bash -c \
    '. "$1"; bootstrap_is_wsl' _ "$FIXTURE/lib/bootstrap/platform.sh"
printf 'Linux version 6.8.0-45-generic (buildd@lcy02-amd64-115)\n' >"$PROC_VERSION"
assert_status 1 'native kernel' env BOOTSTRAP_PROC_VERSION="$PROC_VERSION" bash -c \
    '. "$1"; bootstrap_is_wsl' _ "$FIXTURE/lib/bootstrap/platform.sh"
assert_status 0 'WSL_DISTRO_NAME' env WSL_DISTRO_NAME=Ubuntu BOOTSTRAP_PROC_VERSION="$PROC_VERSION" bash -c \
    '. "$1"; bootstrap_is_wsl' _ "$FIXTURE/lib/bootstrap/platform.sh"
assert_status 1 'no proc version' env BOOTSTRAP_PROC_VERSION="$TEST_TMP/missing" bash -c \
    '. "$1"; bootstrap_is_wsl' _ "$FIXTURE/lib/bootstrap/platform.sh"

assert_status 1 'login node' bootstrap_in_allocation
assert_status 0 'allocation' env SLURM_JOB_ID=4242 bash -c \
    '. "$1"; bootstrap_in_allocation' _ "$FIXTURE/lib/bootstrap/platform.sh"
assert_status 1 'empty SLURM_JOB_ID' env SLURM_JOB_ID= bash -c \
    '. "$1"; bootstrap_in_allocation' _ "$FIXTURE/lib/bootstrap/platform.sh"

cat >"$FAKE_BIN/ldd" <<'SH'
#!/bin/sh
printf 'ldd:%s\n' "$*" >>"$EVENT_LOG"
case ${LDD_FLAVOR:-glibc} in
    glibc) printf 'ldd (Ubuntu GLIBC 2.39-0ubuntu8.6) 2.39\nCopyright (C) 2024\n' ;;
    rhel) printf 'ldd (GNU libc) 2.34\n' ;;
    musl)
        printf 'musl libc (x86_64)\nVersion 1.2.4\n' >&2
        exit 1
        ;;
esac
SH
chmod +x "$FAKE_BIN/ldd"
assert_eq "$(BOOTSTRAP_UNAME_S=Linux bootstrap_glibc_version)" 2.39 'Ubuntu glibc'
assert_eq "$(BOOTSTRAP_UNAME_S=Linux LDD_FLAVOR=rhel bootstrap_glibc_version)" 2.34 'RHEL glibc'
assert_eq "$(BOOTSTRAP_UNAME_S=Linux LDD_FLAVOR=musl bootstrap_glibc_version)" '' 'musl'
assert_events 'ldd:--version' 'ldd:--version' 'ldd:--version'
assert_eq "$(BOOTSTRAP_UNAME_S=Darwin bootstrap_glibc_version)" '' 'macOS glibc'
assert_events

# A fresh Homebrew is off PATH until `brew shellenv` runs (stow brings that).
BREW_OFF="$TEST_TMP/prefix-a/bin/brew"
BREW_ON="$TEST_TMP/prefix-b/bin/brew"
mkdir -p "${BREW_OFF%/brew}" "${BREW_ON%/brew}"
: >"$BREW_OFF"
printf '#!/bin/sh\nexit 0\n' >"$BREW_ON"
chmod +x "$BREW_ON"
assert_eq "$(BOOTSTRAP_BREW_CANDIDATES="$BREW_OFF:$BREW_ON" bootstrap_brew_bin)" "$BREW_ON" 'first executable brew prefix'
assert_eq "$(brew() { :; } && BOOTSTRAP_BREW_CANDIDATES="$BREW_ON" bootstrap_brew_bin)" "$BREW_ON" 'a brew function is not a path'
assert_status 1 'no executable brew' env BOOTSTRAP_BREW_CANDIDATES="$BREW_OFF" bash -c \
    '. "$1"; bootstrap_brew_bin' _ "$FIXTURE/lib/bootstrap/platform.sh"
assert_status 1 'empty brew candidates' env BOOTSTRAP_BREW_CANDIDATES= bash -c \
    '. "$1"; bootstrap_brew_bin' _ "$FIXTURE/lib/bootstrap/platform.sh"
cp "$BREW_ON" "$FAKE_BIN/brew"
assert_eq "$(BOOTSTRAP_BREW_CANDIDATES="$BREW_OFF" bootstrap_brew_bin)" "$FAKE_BIN/brew" 'brew on PATH wins'
rm -f "$FAKE_BIN/brew"

# ----------------------------------------------------------------- versions
echo '==> version extraction and comparison'
version_case() {
    # version_case HAVE FLOOR ge|lt
    local status=0
    bootstrap_version_ge "$1" "$2" || status=$?
    case $3 in
        ge) [ "$status" = 0 ] || fail "$1 >= $2 expected, got status $status" ;;
        lt) [ "$status" = 1 ] || fail "$1 < $2 expected, got status $status" ;;
    esac
}
version_case 0.58.0 0.58 ge
version_case v3.14.1 3.13 ge
version_case 2.3.1 2.4 lt
version_case 10.5.0 8.3 ge
version_case 0.44.1 0.58.0 lt
version_case 0.58.0 0.58.0 ge
version_case 0.18.2 0.18.20 lt
version_case 0.18.20 0.18.2 ge
version_case 3.11 3.11.0 ge
version_case 3.10.12 3.11 lt
version_case 22.0 22.0 ge
version_case 24.13.0 22.0 ge
version_case 0.09 0.8 ge
version_case 1.08.0 1.8 ge
version_case 3 2.99.99 ge
assert_status 2 'empty have' bootstrap_version_ge '' 1.0
assert_status 2 'word have' bootstrap_version_ge abc 1.0
assert_status 2 'bad floor' bootstrap_version_ge 1.0 1.x
assert_status 2 'four parts' bootstrap_version_ge 1.2.3.4 1.0
assert_status 2 'trailing dot' bootstrap_version_ge 1.2. 1.0

assert_eq "$(bootstrap_extract_version "$(printf 'eza - A modern, maintained replacement for ls\nv0.23.5 [+git]\n')")" 0.23.5 'eza output'
assert_eq "$(bootstrap_extract_version 'jq-1.7')" 1.7 'jq output'
assert_eq "$(bootstrap_extract_version 'gh version 2.45.0 (2026-03-17 Ubuntu 2.45.0-1ubuntu0.3)')" 2.45.0 'gh output'
assert_eq "$(bootstrap_extract_version 'Python 3.14.8')" 3.14.8 'python output'
assert_eq "$(bootstrap_extract_version 'version 1.2.3.4')" 1.2.3 'three parts at most'
assert_eq "$(bootstrap_extract_version 'aria2 version 1.37.0')" 1.37.0 'aria2 output'
assert_eq "$(bootstrap_extract_version 'no version here 7')" '' 'no version'
assert_eq "$(bootstrap_extract_version '')" '' 'empty text'

cat >"$FAKE_BIN/fake-fzf" <<'SH'
#!/bin/sh
printf 'fake-fzf:%s\n' "$*" >>"$EVENT_LOG"
printf '0.44.1 (debian)\n'
SH
cat >"$FAKE_BIN/fake-stderr" <<'SH'
#!/bin/sh
printf 'fake-stderr:%s\n' "$*" >>"$EVENT_LOG"
printf 'tool v3.14.1\n' >&2
exit 3
SH
cat >"$FAKE_BIN/fake-chatty" <<'SH'
#!/bin/sh
printf 'fake-chatty:%s\n' "$*" >>"$EVENT_LOG"
printf 'line\nline\nline\nline\nline\nversion 9.9.9\n'
SH
cat >"$FAKE_BIN/fake-stdin" <<'SH'
#!/bin/sh
read -r line || line=eof
printf 'fake-stdin:%s\n' "$line" >>"$EVENT_LOG"
printf 'stdin 1.2\n'
SH
chmod +x "$FAKE_BIN"/fake-*
assert_eq "$(bootstrap_tool_version fake-fzf --version)" 0.44.1 'tool version'
assert_eq "$(bootstrap_tool_version fake-stderr -V)" 3.14.1 'stderr and failing status'
assert_eq "$(bootstrap_tool_version fake-chatty version)" '' 'only five lines are read'
assert_eq "$(bootstrap_tool_version fake-stdin --version)" 1.2 'stdin is /dev/null'
assert_eq "$(bootstrap_tool_version missing-tool --version)" '' 'missing tool'
assert_eq "$(bootstrap_tool_version fake-fzf -)" '' 'presence-only flag'
assert_events 'fake-fzf:--version' 'fake-stderr:-V' 'fake-chatty:version' 'fake-stdin:eof'

# ------------------------------------------------------------------ paths
echo '==> path tokens'
expand() {
    # expand TOKENIZED [VAR=VALUE...]
    local path=$1
    shift
    env "$@" bash -c 'set -eu; . "$1"; bootstrap_expand_path "$2"' _ \
        "$FIXTURE/lib/bootstrap/manifest.sh" "$path"
}
assert_eq "$(expand '$HOME/.oh-my-zsh/oh-my-zsh.sh')" "$TEST_HOME/.oh-my-zsh/oh-my-zsh.sh" 'HOME'
assert_eq "$(expand '$HOME')" "$TEST_HOME" 'bare HOME'
assert_eq "$(expand '$ZSH_CUSTOM/plugins/fzf-tab')" "$TEST_HOME/.oh-my-zsh/custom/plugins/fzf-tab" 'ZSH_CUSTOM default'
assert_eq "$(expand '$ZSH_CUSTOM/plugins/x' ZSH=/opt/omz)" /opt/omz/custom/plugins/x 'ZSH_CUSTOM from ZSH'
assert_eq "$(expand '$ZSH_CUSTOM/plugins/x' ZSH=/opt/omz ZSH_CUSTOM=/srv/custom)" /srv/custom/plugins/x 'ZSH_CUSTOM set'
assert_eq "$(expand '$NVM_DIR/nvm.sh')" "$TEST_HOME/.nvm/nvm.sh" 'NVM_DIR default'
assert_eq "$(expand '$NVM_DIR/nvm.sh' NVM_DIR=/srv/nvm)" /srv/nvm/nvm.sh 'NVM_DIR set'
assert_eq "$(expand '$XDG_CONFIG_HOME/bat')" "$TEST_HOME/.config/bat" 'XDG_CONFIG_HOME default'
assert_eq "$(expand '$XDG_CONFIG_HOME/bat' XDG_CONFIG_HOME=/srv/config)" /srv/config/bat 'XDG_CONFIG_HOME set'
assert_eq "$(expand '$XDG_DATA_HOME/fonts/CaskaydiaMonoNerdFont')" "$TEST_HOME/.local/share/fonts/CaskaydiaMonoNerdFont" 'XDG_DATA_HOME default'
assert_eq "$(expand '$XDG_DATA_HOME/fonts' XDG_DATA_HOME=/srv/data)" /srv/data/fonts 'XDG_DATA_HOME set'
assert_eq "$(expand '$BAT_CONFIG_DIR/themes/Catppuccin Mocha.tmTheme')" "$TEST_HOME/.config/bat/themes/Catppuccin Mocha.tmTheme" 'BAT_CONFIG_DIR default'
assert_eq "$(expand '$BAT_CONFIG_DIR/themes' XDG_CONFIG_HOME=/srv/config)" /srv/config/bat/themes 'BAT_CONFIG_DIR from XDG'
assert_eq "$(expand '$BAT_CONFIG_DIR/themes' BAT_CONFIG_DIR=/srv/bat)" /srv/bat/themes 'BAT_CONFIG_DIR set'
assert_eq "$(expand '/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe')" \
    '/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe' 'absolute path with spaces'
# shellcheck disable=SC2088 # these are literal manifest tokens, not paths
for rejected in '$FOO/x' '$HOMEDIR/x' '$HOME/$ZSH/x' '~/x' '$HOME/../x' '/a/../b' '$HOME/..' '${HOME}/x'; do
    assert_status 1 "reject $rejected" expand "$rejected"
done
assert_status 1 'empty HOME' expand '$HOME/x' HOME=

# ------------------------------------------------------- hosts and tiers
echo '==> host and tier selection'
assert_status 0 'all/win' bootstrap_host_matches all win
assert_status 0 'all/platform' bootstrap_host_matches all ''
assert_status 0 'unix/mac' bootstrap_host_matches unix mac
assert_status 0 'unix/platform' bootstrap_host_matches unix ''
assert_status 1 'unix/win' bootstrap_host_matches unix win
assert_status 0 'list/member' bootstrap_host_matches mac,wsl-ubuntu,lab-ubuntu lab-ubuntu
assert_status 0 'list/first' bootstrap_host_matches sherlock,marlowe sherlock
assert_status 1 'list/other' bootstrap_host_matches sherlock,marlowe mac
assert_status 1 'list/prefix' bootstrap_host_matches wsl-ubuntu wsl
assert_status 1 'list/platform' bootstrap_host_matches mac,win ''
assert_status 1 'list/glob' bootstrap_host_matches mac,win '*'
assert_status 0 'tier/all' bootstrap_tier_selected host all
assert_status 0 'tier/member' bootstrap_tier_selected ai core,cli,ai
assert_status 1 'tier/absent' bootstrap_tier_selected desktop core,cli,ai
assert_status 1 'tier/prefix' bootstrap_tier_selected co core,cli

# ---------------------------------------------------------- fixture rows
echo '==> manifest rows'
CONFIG="$FIXTURE/config/bootstrap"
{
    echo '# comment before the header'
    row id tier hosts probe version_flag floor absent doc
    row alpha core all alpha --version 1.0 'alpha breaks' P0-preflight
    echo '# comment between rows'
    row beta cli unix 'file:$HOME/beta file' - - 'beta, (with) punctuation' S3-clones
    echo
    row gamma host mac,sherlock gamma - - 'gamma breaks' X-host-tools
    row delta desktop win psmodule:Delta - - 'delta breaks' W1-psresources
} >"$CONFIG/tools.tsv"
{
    row id dest url ref hosts
    row alpha '$HOME/.alpha' https://github.com/o/alpha.git master unix
    row beta '$ZSH_CUSTOM/plugins/beta' https://github.com/o/beta.git 0123456789abcdef0123456789abcdef01234567 sherlock,marlowe
} >"$CONFIG/git-clones.tsv"
{
    row id kind url sha256 dest hosts arch tier human
    row alpha script https://e.test/v1.0/a.sh aaaa - all any core -
    row beta binary https://e.test/v1.0/b-x86_64 bbbb '$HOME/.local/bin/beta' sherlock x86_64 core -
    row beta binary https://e.test/v1.0/b-aarch64 cccc '$HOME/.local/bin/beta' sherlock aarch64 core -
    row gamma archive https://e.test/v1.0/g.tar.gz dddd '$HOME/g' unix any desktop -
    row gamma archive https://e.test/v1.0/g-arm.tar.gz eeee '$HOME/g' unix aarch64 desktop -
    row gamma-two file https://e.test/v1.0/g2 ffff '$HOME/g2' mac any core -
} >"$CONFIG/installers.tsv"

export BOOTSTRAP_CONFIG="$CONFIG"
bootstrap_init "$FIXTURE"
assert_eq "$BOOTSTRAP_ROOT" "$FIXTURE" 'BOOTSTRAP_ROOT'
assert_eq "$BOOTSTRAP_CONFIG" "$CONFIG" 'preset BOOTSTRAP_CONFIG is kept'
assert_eq "$(unset BOOTSTRAP_CONFIG && bootstrap_init /srv/repo && printf '%s' "$BOOTSTRAP_CONFIG")" \
    /srv/repo/config/bootstrap 'default BOOTSTRAP_CONFIG'

assert_eq "$(bootstrap_rows "$CONFIG/tools.tsv" | cut -f1 | tr '\n' ' ')" 'alpha beta gamma delta ' 'data rows'
assert_eq "$(bootstrap_rows "$CONFIG/tools.tsv" | sed -n 2p)" \
    "$(row beta cli unix 'file:$HOME/beta file' - - 'beta, (with) punctuation' S3-clones)" 'rows are unchanged'
assert_status 1 'missing manifest' bootstrap_rows "$CONFIG/missing.tsv"
assert_eq "$(bootstrap_field "$(row a b c)" 3)" c 'field 3'
assert_status 1 'field past the end' bootstrap_field "$(row a b c)" 4

assert_eq "$(bootstrap_tool_rows mac | cut -f1 | tr '\n' ' ')" 'alpha beta gamma ' 'tools for mac'
assert_eq "$(bootstrap_tool_rows sherlock | cut -f1 | tr '\n' ' ')" 'alpha beta gamma ' 'tools for sherlock'
assert_eq "$(bootstrap_tool_rows win | cut -f1 | tr '\n' ' ')" 'alpha delta ' 'tools for win'
assert_eq "$(bootstrap_tool_rows '' | cut -f1 | tr '\n' ' ')" 'alpha beta ' 'tools in platform mode'
assert_eq "$(bootstrap_clone_rows lab-ubuntu | cut -f1 | tr '\n' ' ')" 'alpha ' 'clones for lab-ubuntu'
assert_eq "$(bootstrap_clone_rows marlowe | cut -f1 | tr '\n' ' ')" 'alpha beta ' 'clones for marlowe'
assert_eq "$(bootstrap_clone_rows win)" '' 'no clones on win'

installer_url() {
    bootstrap_installer_row "$@" | cut -f3
}
assert_eq "$(installer_url alpha win x86_64)" https://e.test/v1.0/a.sh 'any arch'
assert_eq "$(installer_url beta sherlock x86_64)" https://e.test/v1.0/b-x86_64 'x86_64 row'
assert_eq "$(installer_url beta sherlock aarch64)" https://e.test/v1.0/b-aarch64 'aarch64 row'
assert_status 1 'host mismatch' bootstrap_installer_row beta marlowe x86_64
assert_status 1 'no arch row' bootstrap_installer_row beta sherlock riscv64
assert_eq "$(installer_url gamma mac aarch64)" https://e.test/v1.0/g-arm.tar.gz 'exact arch beats any'
assert_eq "$(installer_url gamma mac x86_64)" https://e.test/v1.0/g.tar.gz 'any as fallback'
assert_status 1 'unix row on win' bootstrap_installer_row gamma win x86_64
assert_eq "$(installer_url gamma-two mac x86_64)" https://e.test/v1.0/g2 'id with a shared prefix'
assert_status 1 'unknown id' bootstrap_installer_row gam mac any
assert_eq "$(bootstrap_installer_row gamma mac x86_64 | wc -l | tr -d ' ')" 1 'single row'

{
    echo '# shared'
    echo 'zsh'
    echo '  git  '
    echo
    echo '   # indented comment'
    echo 'git-lfs'
} >"$CONFIG/apt/common.txt"
printf '%s\n' '# lab' xclip wl-clipboard >"$CONFIG/apt/lab-ubuntu.txt"
assert_eq "$(bootstrap_apt_packages lab-ubuntu | tr '\n' ' ')" 'zsh git git-lfs xclip wl-clipboard ' 'apt for lab-ubuntu'
assert_eq "$(bootstrap_apt_packages wsl-ubuntu | tr '\n' ' ')" 'zsh git git-lfs ' 'apt without a host list'
assert_eq "$(bootstrap_apt_packages '' | tr '\n' ' ')" 'zsh git git-lfs ' 'apt in platform mode'
assert_eq "$(bootstrap_apt_packages ../lab-ubuntu | tr '\n' ' ')" 'zsh git git-lfs ' 'apt host is not a path'

for tier in core cli ai contributor; do
    printf 'brew "%s-tool"\n' "$tier" >"$CONFIG/brew/$tier.Brewfile"
done
assert_eq "$(bootstrap_brewfiles ai,core | tr '\n' ' ')" \
    "$CONFIG/brew/core.Brewfile $CONFIG/brew/ai.Brewfile " 'tier order, not selection order'
assert_eq "$(bootstrap_brewfiles all | sed 's#.*/##' | tr '\n' ' ')" \
    'core.Brewfile cli.Brewfile ai.Brewfile contributor.Brewfile ' 'missing desktop Brewfile is skipped'
assert_eq "$(bootstrap_brewfiles desktop,host)" '' 'no Brewfile for desktop or host here'

doc_case() {
    assert_eq "$(bootstrap_doc_ref "$1" "$2")" "$3" "doc ref $1 on $2"
}
doc_case S2-brew-bundle hpc S2-login-env
doc_case S4-nvm hpc S2-modules
doc_case S5-claude hpc S2-modules
doc_case S5-codex hpc S2-modules
doc_case S3-clones hpc S3-clones
doc_case H7-stow hpc H7-stow
for step in S2-brew-bundle S4-nvm S5-claude S5-codex; do
    doc_case "$step" windows W1-winget
done
doc_case S3-bat-theme windows W1-bat-theme
doc_case S6-nerd-font windows W1-font
doc_case S4-setup-sync windows W1-setup-sync
doc_case H7-stow windows HW-stow
doc_case H7-auth windows HW-auth
doc_case P0-preflight windows P0-preflight
for step in S2-brew-bundle S4-nvm S5-claude S3-bat-theme H7-stow; do
    doc_case "$step" debian "$step"
    doc_case "$step" macos "$step"
done

# Bash `local` is dynamically scoped: a TSV loop's `local IFS=$tab` reaches
# every library function it calls, so none of them may split by the caller's IFS.
echo '==> a caller IFS does not reach the libraries'
printf '%s\n' 'NAME="Linux Mint"' ID=linuxmint 'ID_LIKE="ubuntu debian"' >"$OS_RELEASE"
caller_ifs_case() {
    local IFS=$1 label=$2
    version_case 0.58.0 0.58 ge
    version_case 0.44.1 0.58.0 lt
    version_case 10.5.0 8.3 ge
    version_case v3.14.1 3.13 ge
    assert_eq "$(bootstrap_brewfiles core,cli | sed 's#.*/##' | tr '\n' ' ')" \
        'core.Brewfile cli.Brewfile ' "Brewfiles with a $label IFS"
    assert_eq "$(BOOTSTRAP_UNAME_S=Linux BOOTSTRAP_OS_RELEASE="$OS_RELEASE" bootstrap_detect_platform)" \
        debian "Linux Mint with a $label IFS"
    assert_eq "$(bootstrap_tool_rows mac | cut -f1 | tr '\n' ' ')" 'alpha beta gamma ' "tool rows with a $label IFS"
    assert_eq "$(bootstrap_installer_row beta sherlock aarch64 | cut -f3)" https://e.test/v1.0/b-aarch64 \
        "installer row with a $label IFS"
}
caller_ifs_case "$tab" tab
caller_ifs_case $'\n' newline
caller_ifs_case '' empty
printf '%s\n' 'ID=*' 'ID_LIKE="debian ?"' >"$OS_RELEASE"
touch "$TEST_TMP/debian"
assert_eq "$(cd "$TEST_TMP" && BOOTSTRAP_UNAME_S=Linux BOOTSTRAP_OS_RELEASE="$OS_RELEASE" bootstrap_detect_platform)" \
    debian 'os-release words are not globbed'
printf '%s\n' 'ID=*' >"$OS_RELEASE"
assert_eq "$(cd "$TEST_TMP" && BOOTSTRAP_UNAME_S=Linux BOOTSTRAP_OS_RELEASE="$OS_RELEASE" bootstrap_detect_platform)" \
    other 'a glob ID does not match a file named debian'

# --------------------------------------------------------- host resolution
echo '==> host resolution'
REPO="$TEST_TMP/repo"
"$REAL_GIT" -c init.defaultBranch=main init -q "$REPO"
"$REAL_GIT" -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
state_file() {
    local path
    path=$("$REAL_GIT" -C "$1" rev-parse --git-path dotfiles-sync-unix)
    case $path in
        /*) printf '%s\n' "$path" ;;
        *) printf '%s\n' "$1/$path" ;;
    esac
}
resolve() {
    # resolve ROOT [VAR=VALUE...]
    local root=$1
    shift
    env "$@" bash -c 'set -eu; . "$1"; bootstrap_resolve_host "$2"' _ \
        "$FIXTURE/lib/bootstrap/platform.sh" "$root"
}
STATE=$(state_file "$REPO")
assert_status 1 'no state file' resolve "$REPO"
printf '%s\n' "$TEST_HOME" "$(uname -s)" sherlock abc123 >"$STATE"
assert_eq "$(resolve "$REPO")" sherlock 'recorded host'
assert_eq "$(resolve "$REPO" DOTFILES_HOST=marlowe)" marlowe 'DOTFILES_HOST wins'
assert_status 1 'invalid DOTFILES_HOST' resolve "$REPO" DOTFILES_HOST=fedora
assert_status 1 'other HOME' resolve "$REPO" HOME="$TEST_TMP/elsewhere"
assert_status 1 'other kernel' resolve "$REPO" BOOTSTRAP_UNAME_S=Plan9
printf '%s\n' "$TEST_HOME" Plan9 mac '' >"$STATE"
assert_eq "$(resolve "$REPO" BOOTSTRAP_UNAME_S=Plan9)" mac 'kernel override matches'
printf '%s\n' "$TEST_HOME" "$(uname -s)" '' '' >"$STATE"
assert_status 1 'common-only stow' resolve "$REPO"
printf '%s\n' "$TEST_HOME" "$(uname -s)" ubuntu '' >"$STATE"
assert_status 1 'unknown recorded host' resolve "$REPO"
printf '%s\n%s\n%s' "$TEST_HOME" "$(uname -s)" lab-ubuntu >"$STATE"
assert_eq "$(resolve "$REPO")" lab-ubuntu 'no trailing newline'
printf '%s\n' "$TEST_HOME" >"$STATE"
assert_status 1 'truncated state' resolve "$REPO"
assert_status 1 'not a repository' resolve "$TEST_TMP/fixture" GIT_CEILING_DIRECTORIES="$TEST_TMP"

WORKTREE="$TEST_TMP/worktree"
"$REAL_GIT" -C "$REPO" worktree add -q --detach "$WORKTREE"
WORKTREE_STATE=$(state_file "$WORKTREE")
case $WORKTREE_STATE in
    "$REPO"/.git/worktrees/*) ;;
    *) fail "unexpected worktree state path: $WORKTREE_STATE" ;;
esac
printf '%s\n' "$TEST_HOME" "$(uname -s)" wsl-ubuntu '' >"$WORKTREE_STATE"
assert_eq "$(resolve "$WORKTREE")" wsl-ubuntu 'linked worktree state'

# ------------------------------------------------------- real manifests
echo '==> repository manifests'
unset BOOTSTRAP_CONFIG
bootstrap_init "$REPO_ROOT"
real_ids() {
    "$@" | cut -f1 | tr '\n' ' '
}
for file in tools.tsv:8 git-clones.tsv:5 installers.tsv:9; do
    bad=$(bootstrap_rows "$BOOTSTRAP_CONFIG/${file%%:*}" | awk -F '\t' -v n="${file#*:}" 'NF != n')
    [ -z "$bad" ] || fail "${file%%:*} rows without ${file#*:} fields: $bad"
done
case " $(real_ids bootstrap_tool_rows lab-ubuntu)" in
    *' fzf '*' gh-apt '*) ;;
    *) fail 'lab-ubuntu tools miss fzf or gh-apt' ;;
esac
case " $(real_ids bootstrap_tool_rows lab-ubuntu)" in
    *' pwsh '* | *' login-env '*) fail 'lab-ubuntu tools include another host' ;;
esac
case " $(real_ids bootstrap_tool_rows '')" in
    *' gh-apt '* | *' pwsh '* | *' micromamba '*) fail 'platform mode includes host-list rows' ;;
esac
assert_eq "$(bootstrap_clone_rows sherlock | wc -l | tr -d ' ')" 8 'eight clones on sherlock'
assert_eq "$(bootstrap_clone_rows win | wc -l | tr -d ' ')" 0 'no clones on win'
assert_eq "$(bootstrap_installer_row micromamba sherlock aarch64 | cut -f3 | sed 's#.*/##')" micromamba-linux-aarch64 'micromamba aarch64'
assert_eq "$(bootstrap_installer_row codex lab-ubuntu x86_64 | cut -f3 | sed 's#.*/##')" codex-package-x86_64-unknown-linux-musl.tar.gz 'codex x86_64'
assert_eq "$(bootstrap_installer_row claude wsl-ubuntu aarch64 | cut -f9)" inspect 'claude is inspect'
assert_status 1 'no micromamba on lab-ubuntu' bootstrap_installer_row micromamba lab-ubuntu x86_64
case " $(bootstrap_apt_packages lab-ubuntu | tr '\n' ' ')" in
    *' zsh '*' fontconfig xclip '*) ;;
    *) fail 'lab-ubuntu apt list is not common.txt then lab-ubuntu.txt' ;;
esac
assert_eq "$(bootstrap_brewfiles core,cli,ai | sed 's#.*/##' | tr '\n' ' ')" \
    'core.Brewfile cli.Brewfile ai.Brewfile ' 'default-tier Brewfiles'
assert_eq "$(bootstrap_expand_path "$(bootstrap_field "$(bootstrap_installer_row bat-theme mac any)" 5)")" \
    "$TEST_HOME/.config/bat/themes/Catppuccin Mocha.tmTheme" 'bat theme destination'
# The doctor writes nothing, and `brew --version` can rewrite Homebrew's
# .git/describe-cache, so a row that probes brew is presence-only.
bad=$(bootstrap_rows "$BOOTSTRAP_CONFIG/tools.tsv" | awk -F '\t' '$4 ~ /(^|,)brew(,|$)/ && $5 != "-"')
[ -z "$bad" ] || fail "tools.tsv runs brew for its version: $bad"
assert_events

# -------------------------------------------------- gh auth setup-git
echo '==> no bootstrap script or doc tells anyone to run gh auth setup-git'
# It runs git config --global, which writes through the stowed ~/.gitconfig
# into common/git/.gitconfig. It may only be named as a warning.
setup_git_offenders() {
    local file
    for file in "$@"; do
        grep -Hn -e 'setup-git' -- "$file" | grep -Eiv "never|do not run|don't run|skip" || true
    done
}
SETUP_GIT_FILES=(README.md AGENTS.md docs/bootstrap.md docs/dependencies.md doctor.sh setup-host.sh
    doctor.ps1 setup-host.ps1 lib/bootstrap.ps1 lib/bootstrap/*.sh
    .claude/skills/dotfiles-bootstrap/SKILL.md .agents/skills/dotfiles-bootstrap/SKILL.md)
offenders=$(cd "$REPO_ROOT" && setup_git_offenders "${SETUP_GIT_FILES[@]}")
[ -z "$offenders" ] || fail "gh auth setup-git outside a warning: $offenders"
printf '%s\n' '# never run gh auth setup-git' 'gh auth login && gh auth setup-git' >"$TEST_TMP/setup-git.md"
assert_eq "$(setup_git_offenders "$TEST_TMP/setup-git.md" | cut -d: -f2)" 2 'the setup-git check finds a command'

# ----------------------------------------------------------- validator
echo '==> manifest validator'
"$TEST_PYTHON" -I -B -m unittest discover -s "$TEST_DIR" -p test_bootstrap_manifest.py

echo 'bootstrap-manifest=PASS'
