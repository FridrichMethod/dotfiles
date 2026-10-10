#!/bin/bash

# Fixture tests for setup-host.sh and lib/bootstrap/{fetch,steps*}.sh. Every
# package manager, download and clone remote is a local stub; sudo, chsh,
# stow, apt-get, git lfs and the fixture's ./stow-all.sh are tripwires; each
# case runs under `env -i` with its own fixture home, never the real one.
# The [y/N] prompt cases run on a pseudo terminal from python3's pty module
# and are skipped, with a note on stderr, where that is unavailable.

set -euo pipefail

# Hermetic: the provisioning exports (DOTFILES_AUTO_UPDATE=0 and the like,
# docs/bootstrap.md) and other dotfiles knobs never reach the code under
# test from the caller; each case sets what it needs.
unset DOTFILES_AUTO_UPDATE DOTFILES_AUTO_STOW DOTFILES_HOST DOTFILES_DIR _DOTFILES_CHECKED \
    DOTFILES_STOW_WITHOUT_OH_MY_ZSH DOTFILES_COLOR AWESOME_SKILLS_AUTO_UPDATE AWESOME_SKILLS_FORCE \
    AWESOME_SKILLS_BG AWESOME_SKILLS_INSTALLER_URL AWESOME_SKILLS_REFRESH_DAYS _AWESOME_SKILLS_CHECKED

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures/bootstrap"
REAL_GIT=$(command -v git)
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-setup-host.XXXXXX")"
TEST_TMP="$(cd -- "$TEST_TMP" && pwd -P)"
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM

FIXTURE="$TEST_TMP/repo"
FAKE_BIN="$TEST_TMP/bin"
REMOTES="$TEST_TMP/remotes"
ARTIFACTS="$TEST_TMP/artifacts"
EVENT_LOG="$TEST_TMP/events.log"
CURL_ARGS_LOG="$TEST_TMP/curl-args.log"
URL_MAP="$TEST_TMP/url-map.tsv"
URL_MAP_BAD="$TEST_TMP/url-map-bad.tsv"
GITCONFIG="$TEST_TMP/gitconfig"
OS_DEBIAN="$TEST_TMP/os-release-ubuntu"
OS_ROCKY="$TEST_TMP/os-release-rocky"
PROC_NATIVE="$TEST_TMP/proc-version-native"
PROC_WSL="$TEST_TMP/proc-version-wsl"
DPKG_ALL="$TEST_TMP/dpkg-all"
DPKG_PARTIAL="$TEST_TMP/dpkg-partial"
MARKER="$TEST_TMP/marker"
TAB=$(printf '\t')
mkdir -p "$FAKE_BIN" "$REMOTES" "$ARTIFACTS" "$TEST_TMP/homes" "$TEST_TMP/work"
: >"$EVENT_LOG"
: >"$CURL_ARGS_LOG"

# Test setup uses the real git with a private config; setup-host's git goes
# through the logging wrapper below, with https://github.com/ rewritten to
# local bare repositories.
cat >"$GITCONFIG" <<EOF
[user]
	name = Fixture
	email = fixture@example.invalid
[init]
	defaultBranch = master
[advice]
	detachedHead = false
[url "file://$REMOTES/"]
	insteadOf = https://github.com/
EOF
export GIT_CONFIG_GLOBAL="$GITCONFIG" GIT_CONFIG_NOSYSTEM=1

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

show() {
    local file
    for file in "$TEST_TMP/$1.out" "$TEST_TMP/$1.err" "$EVENT_LOG"; do
        printf -- '--- %s\n' "$file" >&2
        cat "$file" >&2 || true
    done
}

# expect_rc NAME CODE: the last run_case exited CODE.
expect_rc() {
    if [ "$CASE_RC" != "$2" ]; then
        show "$1"
        fail "$1: exit $CASE_RC, expected $2"
    fi
}

# expect_text NAME STREAM TEXT / expect_no_text: fixed-string checks.
expect_text() {
    if ! grep -Fq -- "$3" "$TEST_TMP/$1.$2"; then
        show "$1"
        fail "$1: $2 lacks [$3]"
    fi
}

expect_no_text() {
    if grep -Fq -- "$3" "$TEST_TMP/$1.$2"; then
        show "$1"
        fail "$1: $2 unexpectedly has [$3]"
    fi
}

# expect_line NAME TEXT: stdout has TEXT as a whole line.
expect_line() {
    if ! grep -Fxq -- "$2" "$TEST_TMP/$1.out"; then
        show "$1"
        fail "$1: stdout lacks the line [$2]"
    fi
}

expect_event() {
    grep -Fq -- "$1" "$EVENT_LOG" || {
        cat "$EVENT_LOG" >&2
        fail "missing event [$1]"
    }
}

expect_no_event() {
    if grep -Fq -- "$1" "$EVENT_LOG"; then
        cat "$EVENT_LOG" >&2
        fail "unexpected event [$1]"
    fi
}

expect_no_events() {
    if [ -s "$EVENT_LOG" ]; then
        cat "$EVENT_LOG" >&2
        fail "$1: expected no install, network or tripwire events"
    fi
}

# expect_no_installs NAME: apply mode may run `brew bundle check`, nothing else.
expect_no_installs() {
    if grep -v '^brew-check:' "$EVENT_LOG" | grep -q .; then
        cat "$EVENT_LOG" >&2
        fail "$1: expected no install, network or tripwire events"
    fi
}

# expect_order TEXT...: the first event matching each TEXT appears in order.
expect_order() {
    local previous=0 line text
    for text in "$@"; do
        line=$(grep -nF -- "$text" "$EVENT_LOG" | sed -n '1s/:.*//p')
        [ -n "$line" ] || {
            cat "$EVENT_LOG" >&2
            fail "missing ordered event [$text]"
        }
        [ "$line" -gt "$previous" ] || {
            cat "$EVENT_LOG" >&2
            fail "event [$text] (line $line) is out of phase order"
        }
        previous=$line
    done
}

# new_home NAME: a fresh fixture home and Homebrew prefix; sets CASE_HOME
# and CASE_BREW.
new_home() {
    CASE_HOME="$TEST_TMP/homes/$1"
    CASE_BREW="$TEST_TMP/brew/$1"
    rm -rf "$CASE_HOME" "$CASE_BREW"
    mkdir -p "$CASE_HOME" "$CASE_BREW/bin"
    cp "$TEST_TMP/brew-stub" "$CASE_BREW/bin/brew"
}

# snapshot: every path under the fixture home, Homebrew prefix and checkout.
snapshot() {
    find "$CASE_HOME" "$CASE_BREW" "$FIXTURE" -print | LC_ALL=C sort
}

# case_command [VAR=VALUE...] -- ARGS...: set CASE_CMD to the fixture
# setup-host.sh under a clean environment (debian lab-ubuntu defaults, not
# WSL); a VAR=VALUE overrides a default of the same name. setup-host runs
# under the Bash running this file ($BASH), so `bash-3.2 tests/setup-host.sh`
# tests it under Bash 3.2 too.
case_command() {
    local extra=()
    while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
        extra+=("$1")
        shift
    done
    shift
    CASE_CMD=(env -i
        HOME="$CASE_HOME"
        PATH="$FAKE_BIN:/usr/bin:/bin"
        LC_ALL=C
        DOTFILES_COLOR=never
        TMPDIR="$TEST_TMP"
        EVENT_LOG="$EVENT_LOG"
        CURL_ARGS_LOG="$CURL_ARGS_LOG"
        URL_MAP="$URL_MAP"
        REAL_GIT="$REAL_GIT"
        GIT_CONFIG_GLOBAL="$GITCONFIG"
        GIT_CONFIG_NOSYSTEM=1
        BOOTSTRAP_UNAME_S=Linux
        BOOTSTRAP_UNAME_M=x86_64
        BOOTSTRAP_OS_RELEASE="$OS_DEBIAN"
        BOOTSTRAP_PROC_VERSION="$PROC_NATIVE"
        BOOTSTRAP_BREW_CANDIDATES="$CASE_BREW/bin/brew"
        FAKE_DPKG_INSTALLED="$DPKG_ALL"
        ${extra[@]+"${extra[@]}"}
        "$BASH" "$FIXTURE/setup-host.sh" "$@")
}

# run_case NAME [VAR=VALUE...] -- ARGS...: run case_command with stdin closed.
run_case() {
    local name=$1
    shift
    case_command "$@"
    : >"$EVENT_LOG"
    set +e
    "${CASE_CMD[@]}" </dev/null >"$TEST_TMP/$name.out" 2>"$TEST_TMP/$name.err"
    CASE_RC=$?
    set -e
}

# run_tty_case NAME ANSWER [VAR=VALUE...] -- ARGS...: run case_command on a
# pseudo terminal that answers ANSWER to every [y/N] prompt. stdout and
# stderr share the terminal, so both land in NAME.out.
run_tty_case() {
    local name=$1 answer=$2
    shift 2
    case_command "$@"
    : >"$EVENT_LOG"
    : >"$TEST_TMP/$name.err"
    set +e
    python3 -I "$TEST_TMP/pty-run.py" "$TEST_TMP/$name.out" "$answer" "${CASE_CMD[@]}" </dev/null
    CASE_RC=$?
    set -e
}

# --- stubs -------------------------------------------------------------------

cat >"$FAKE_BIN/git" <<'SH'
#!/bin/sh
# Logs network and write subcommands, then runs the real git.
sub='' skip=0
for arg do
    if [ "$skip" = 1 ]; then
        skip=0
        continue
    fi
    case $arg in
        -C | -c) skip=1 ;;
        -*) ;;
        *)
            sub=$arg
            break
            ;;
    esac
done
case $sub in
    lfs)
        printf 'TRIPWIRE git %s\n' "$*" >>"$EVENT_LOG"
        exit 99
        ;;
    clone | fetch | init | checkout | pull | push | remote | submodule | reset | clean | commit)
        printf 'git:%s\n' "$*" >>"$EVENT_LOG"
        ;;
esac
exec "$REAL_GIT" "$@"
SH

cat >"$FAKE_BIN/curl" <<'SH'
#!/bin/sh
# Serves fixture artifacts by URL from $URL_MAP.
out='' url='' prev=''
for arg do
    [ "$prev" != -o ] || out=$arg
    case $arg in
        https://* | http://*) url=$arg ;;
    esac
    prev=$arg
done
printf 'curl:%s\n' "$url" >>"$EVENT_LOG"
printf '%s\n' "$*" >>"$CURL_ARGS_LOG"
src=$(awk -F '\t' -v u="$url" '$1 == u { print $2; exit }' "$URL_MAP")
if [ -z "$src" ] || [ ! -f "$src" ] || [ -z "$out" ]; then
    echo "curl: (22) no fixture for $url" >&2
    exit 22
fi
cp "$src" "$out"
SH

cat >"$FAKE_BIN/wget" <<'SH'
#!/bin/sh
out='' url='' prev=''
for arg do
    [ "$prev" != -O ] || out=$arg
    case $arg in
        https://* | http://*) url=$arg ;;
    esac
    prev=$arg
done
printf 'wget:%s\n' "$url" >>"$EVENT_LOG"
src=$(awk -F '\t' -v u="$url" '$1 == u { print $2; exit }' "$URL_MAP")
[ -n "$src" ] && [ -f "$src" ] && [ -n "$out" ] || exit 8
cp "$src" "$out"
SH

cat >"$FAKE_BIN/dpkg-query" <<'SH'
#!/bin/sh
# Reports the packages listed in $FAKE_DPKG_INSTALLED as installed.
rc=0
for arg do
    case $arg in
        -*) continue ;;
    esac
    if grep -qx -- "$arg" "${FAKE_DPKG_INSTALLED:-/dev/null}" 2>/dev/null; then
        printf '%s ii \n' "$arg"
    else
        printf 'dpkg-query: no packages found matching %s\n' "$arg" >&2
        rc=1
    fi
done
exit "$rc"
SH

cat >"$TEST_TMP/brew-stub" <<'SH'
#!/bin/sh
# Fake Homebrew: bundle links opt/<formula> for each `brew "x"` of the file,
# bundle check looks for those links (as the offline --check estimate does).
prefix=$(cd "$(dirname "$0")/.." && pwd) file='' prev=''
for arg do
    [ "$prev" != --file ] || file=$arg
    prev=$arg
done
name=${file##*/}
formulas=$(sed -nE 's/^[[:space:]]*brew[[:space:]]+"([^"]+)".*/\1/p' "$file" 2>/dev/null)
case "${1:-} ${2:-}" in
    'bundle check')
        printf 'brew-check:%s\n' "$name" >>"$EVENT_LOG"
        for formula in $formulas; do
            [ -e "$prefix/opt/$formula" ] || exit 1
        done
        ;;
    'bundle --no-upgrade')
        printf 'brew:bundle %s\n' "$name" >>"$EVENT_LOG"
        printf 'brew-env:%s\n' "DOTFILES_AUTO_UPDATE=${DOTFILES_AUTO_UPDATE-} AWESOME_SKILLS_AUTO_UPDATE=${AWESOME_SKILLS_AUTO_UPDATE-} GIT_TERMINAL_PROMPT=${GIT_TERMINAL_PROMPT-} NONINTERACTIVE=${NONINTERACTIVE-} HOMEBREW_NO_AUTO_UPDATE=${HOMEBREW_NO_AUTO_UPDATE-} HOMEBREW_NO_ENV_HINTS=${HOMEBREW_NO_ENV_HINTS-} HOMEBREW_NO_INSTALL_CLEANUP=${HOMEBREW_NO_INSTALL_CLEANUP-}" >>"$EVENT_LOG"
        [ "${BREW_FAIL:-0}" != 1 ] || exit 1
        if [ -n "${BREW_POLLUTE:-}" ]; then
            printf '%s\n' '# appended by a brew installer' >>"$BREW_POLLUTE"
        fi
        for formula in $formulas; do
            mkdir -p "$prefix/Cellar/$formula/1.0" "$prefix/opt" &&
                ln -sfn "../Cellar/$formula/1.0" "$prefix/opt/$formula" || exit 1
        done
        ;;
    '--version '*) echo 'Homebrew 4.6.0' ;;
    *)
        printf 'TRIPWIRE brew %s\n' "$*" >>"$EVENT_LOG"
        exit 99
        ;;
esac
SH

cat >"$FAKE_BIN/bat" <<'SH'
#!/bin/sh
case "$*" in
    'cache --build')
        printf 'bat:cache --build\n' >>"$EVENT_LOG"
        mkdir -p "$HOME/.fake-bat" && : >"$HOME/.fake-bat/cache"
        ;;
    --list-themes*)
        echo 'Monokai Extended'
        if [ -f "$HOME/.fake-bat/cache" ]; then echo 'Catppuccin Mocha'; fi
        ;;
    --version) echo 'bat 0.25.0' ;;
esac
exit 0
SH

cat >"$FAKE_BIN/fc-cache" <<'SH'
#!/bin/sh
printf 'fc-cache:%s\n' "$*" >>"$EVENT_LOG"
SH

cat >"$FAKE_BIN/uname" <<'SH'
#!/bin/sh
case ${1:-} in
    -m) echo "${BOOTSTRAP_UNAME_M:-x86_64}" ;;
    *) echo "${BOOTSTRAP_UNAME_S:-Linux}" ;;
esac
SH

cat >"$FAKE_BIN/getent" <<'SH'
#!/bin/sh
printf '%s:x:1000:1000::%s:/bin/bash\n' "${2:-user}" "$HOME"
SH

cat >"$FAKE_BIN/locale" <<'SH'
#!/bin/sh
printf '%s\n' C C.utf8 en_US.utf8 POSIX
SH

cat >"$FAKE_BIN/xcode-select" <<'SH'
#!/bin/sh
[ "${FAKE_XCODE:-0}" = 1 ] || exit 2
echo /Library/Developer/CommandLineTools
SH

for tripwire in sudo chsh stow apt-get apt conda; do
    cat >"$FAKE_BIN/$tripwire" <<SH
#!/bin/sh
printf 'TRIPWIRE $tripwire %s\n' "\$*" >>"\$EVENT_LOG"
exit 99
SH
done
chmod 755 "$FAKE_BIN"/* "$TEST_TMP/brew-stub"

# A PATH dir whose id reports root, for the refusal case.
ROOT_BIN="$TEST_TMP/bin-root"
mkdir -p "$ROOT_BIN"
cat >"$ROOT_BIN/id" <<'SH'
#!/bin/sh
case "$*" in
    -u) echo 0 ;;
    -un) echo root ;;
    *) echo 'uid=0(root) gid=0(root) groups=0(root)' ;;
esac
SH
chmod 755 "$ROOT_BIN/id"

# Runs a command on a pseudo terminal, answers every [y/N] prompt, saves the
# output and exits with the command's status (97 when the helper breaks).
cat >"$TEST_TMP/pty-run.py" <<'PY'
import os
import pty
import select
import sys
import time


def main():
    out_path, answer, argv = sys.argv[1], sys.argv[2].encode() + b"\n", sys.argv[3:]
    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.execvp(argv[0], argv)
        finally:
            os._exit(127)
    output, answered, deadline = b"", 0, time.monotonic() + 120
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], 1.0)
        if not ready:
            continue
        try:
            data = os.read(fd, 65536)
        except OSError:  # Linux: EIO once the child has exited
            break
        if not data:
            break
        output += data
        while output.count(b"[y/N] ") > answered:
            os.write(fd, answer)
            answered += 1
    else:
        os.kill(pid, 9)
    _, status = os.waitpid(pid, 0)
    with open(out_path, "wb") as handle:
        handle.write(output.replace(b"\r\n", b"\n"))
    return os.WEXITSTATUS(status) if os.WIFEXITED(status) else 98


try:
    sys.exit(main())
except Exception as error:  # report the helper's own failure distinctly
    print(f"pty-run: {error!r}", file=sys.stderr)
    sys.exit(97)
PY
HAVE_PTY=0
if command -v python3 >/dev/null 2>&1 && python3 -I -c 'import pty, select' >/dev/null 2>&1; then
    HAVE_PTY=1
fi

# --- clone remotes -----------------------------------------------------------

# make_remote OWNER/REPO FILE...: a bare repository with one commit; prints
# the commit.
make_remote() {
    local name=$1 work="$TEST_TMP/work/$1" file
    shift
    mkdir -p "$work"
    "$REAL_GIT" init -q "$work"
    for file in "$@"; do
        mkdir -p "$(dirname "$work/$file")"
        printf '# %s\n' "$file" >"$work/$file"
    done
    "$REAL_GIT" -C "$work" add -A
    "$REAL_GIT" -C "$work" commit -q -m initial
    "$REAL_GIT" clone -q --bare "$work" "$REMOTES/$name.git"
    "$REAL_GIT" -C "$REMOTES/$name.git" config uploadpack.allowAnySHA1InWant true
    "$REAL_GIT" -C "$work" rev-parse HEAD
}

make_remote ohmyzsh/ohmyzsh oh-my-zsh.sh custom/example.zsh \
    custom/plugins/example/example.plugin.zsh custom/themes/example.zsh-theme >/dev/null
P10K_PIN=$(make_remote romkatv/powerlevel10k powerlevel10k.zsh-theme)
FZF_TAB_PIN=$(make_remote Aloxaf/fzf-tab fzf-tab.plugin.zsh)
# nvm: the pinned commit, then a later one, as when a release tag moves.
NVM_PIN=$(make_remote nvm-sh/nvm README.md)
printf '# moved\n' >>"$TEST_TMP/work/nvm-sh/nvm/README.md"
"$REAL_GIT" -C "$TEST_TMP/work/nvm-sh/nvm" commit -q -am moved
"$REAL_GIT" -C "$TEST_TMP/work/nvm-sh/nvm" push -q "$REMOTES/nvm-sh/nvm.git" master

# --- artifacts and manifests -------------------------------------------------

# sha FILE: its sha256 (sha256sum, or shasum on macOS).
if command -v sha256sum >/dev/null 2>&1; then
    SHA_TOOL=sha256sum
else
    SHA_TOOL=shasum
fi
sha() {
    if [ "$SHA_TOOL" = sha256sum ]; then
        sha256sum <"$1" | sed 's/ .*//'
    else
        shasum -a 256 <"$1" | sed 's/ .*//'
    fi
}

printf '<plist><!-- fixture Catppuccin Mocha --></plist>\n' >"$ARTIFACTS/theme"
printf '#!/bin/sh\necho bad micromamba\n' >"$ARTIFACTS/micromamba-bad"

mkdir -p "$TEST_TMP/build/codex/bin" "$TEST_TMP/build/codex/codex-path" "$TEST_TMP/build/codex/codex-resources"
# Checks must not run codex (it writes ~/.codex/tmp); only apply's verify may.
printf '#!/bin/sh\nprintf "codex-run:%%s\\n" "$*" >>"$EVENT_LOG"\necho "codex-cli 0.161.0"\n' \
    >"$TEST_TMP/build/codex/bin/codex"
printf '#!/bin/sh\nexit 0\n' >"$TEST_TMP/build/codex/bin/codex-code-mode-host"
printf '#!/bin/sh\nexit 0\n' >"$TEST_TMP/build/codex/codex-path/rg"
printf '#!/bin/sh\nexit 0\n' >"$TEST_TMP/build/codex/codex-resources/bwrap"
chmod 755 "$TEST_TMP/build/codex/bin/codex" "$TEST_TMP/build/codex/bin/codex-code-mode-host" \
    "$TEST_TMP/build/codex/codex-path/rg" "$TEST_TMP/build/codex/codex-resources/bwrap"
cat >"$TEST_TMP/build/codex/codex-package.json" <<'EOF'
{
  "layoutVersion": 1,
  "version": "0.161.0",
  "target": "x86_64-unknown-linux-musl",
  "variant": "codex",
  "entrypoint": "bin/codex"
}
EOF
tar -C "$TEST_TMP/build/codex" -czf "$ARTIFACTS/codex.tar.gz" .

mkdir -p "$TEST_TMP/build/font"
for face in CaskaydiaMonoNerdFont-Regular CaskaydiaMonoNerdFontMono-Regular; do
    printf 'fixture font\n' >"$TEST_TMP/build/font/$face.ttf"
done
printf 'license\n' >"$TEST_TMP/build/font/LICENSE"
printf 'readme\n' >"$TEST_TMP/build/font/README.md"
tar -C "$TEST_TMP/build/font" -cJf "$ARTIFACTS/font.tar.xz" .

mkdir -p "$TEST_TMP/build/kitty/bin" "$TEST_TMP/build/kitty/lib" "$TEST_TMP/build/kitty/share"
printf '#!/bin/sh\necho "kitty 0.49.2"\n' >"$TEST_TMP/build/kitty/bin/kitty"
printf '#!/bin/sh\nexit 0\n' >"$TEST_TMP/build/kitty/bin/kitten"
chmod 755 "$TEST_TMP/build/kitty/bin/kitty" "$TEST_TMP/build/kitty/bin/kitten"
printf 'lib\n' >"$TEST_TMP/build/kitty/lib/kitty.so"
tar -C "$TEST_TMP/build/kitty" -cJf "$ARTIFACTS/kitty.txz" .

URL_HOMEBREW=https://raw.githubusercontent.com/Homebrew/install/0123456789abcdef0123456789abcdef01234567/install.sh
URL_NVM=https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_PIN/install.sh
URL_MICROMAMBA=https://github.com/mamba-org/micromamba-releases/releases/download/2.9.0-0/micromamba-linux-64
URL_CODEX=https://github.com/openai/codex/releases/download/rust-v0.161.0/codex-package-x86_64-unknown-linux-musl.tar.gz
URL_CLAUDE=https://claude.ai/install.sh
URL_FONT=https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/CascadiaMono.tar.xz
URL_KITTY=https://github.com/kovidgoyal/kitty/releases/download/v0.49.2/kitty-0.49.2-x86_64.txz
URL_THEME='https://raw.githubusercontent.com/catppuccin/bat/0123456789abcdef0123456789abcdef01234567/themes/Catppuccin%20Mocha.tmTheme'

{
    printf '%s\t%s\n' "$URL_HOMEBREW" "$FIXTURES/artifacts/homebrew-install"
    printf '%s\t%s\n' "$URL_NVM" "$FIXTURES/artifacts/nvm-install"
    printf '%s\t%s\n' "$URL_MICROMAMBA" "$FIXTURES/artifacts/micromamba"
    printf '%s\t%s\n' "$URL_CODEX" "$ARTIFACTS/codex.tar.gz"
    printf '%s\t%s\n' "$URL_CLAUDE" "$FIXTURES/artifacts/claude-install"
    printf '%s\t%s\n' "$URL_FONT" "$ARTIFACTS/font.tar.xz"
    printf '%s\t%s\n' "$URL_KITTY" "$ARTIFACTS/kitty.txz"
    printf '%s\t%s\n' "$URL_THEME" "$ARTIFACTS/theme"
} >"$URL_MAP"
awk -F '\t' -v OFS='\t' -v url="$URL_MICROMAMBA" -v bad="$ARTIFACTS/micromamba-bad" \
    '$1 == url { $2 = bad } { print }' "$URL_MAP" >"$URL_MAP_BAD"

SHA_HOMEBREW=$(sha "$FIXTURES/artifacts/homebrew-install")
SHA_MICROMAMBA=$(sha "$FIXTURES/artifacts/micromamba")
SHA_MICROMAMBA_BAD=$(sha "$ARTIFACTS/micromamba-bad")
SHA_CLAUDE=$(sha "$FIXTURES/artifacts/claude-install")

mkdir -p "$FIXTURE/lib/bootstrap" "$FIXTURE/config/bootstrap" "$FIXTURE/common/zsh"
cp "$REPO_ROOT/setup-host.sh" "$FIXTURE/setup-host.sh"
cp "$REPO_ROOT/lib/terminal.sh" "$FIXTURE/lib/terminal.sh"
cp "$REPO_ROOT"/lib/bootstrap/*.sh "$FIXTURE/lib/bootstrap/"
cp -R "$FIXTURES/config/." "$FIXTURE/config/bootstrap/"
# The real tools.tsv.
cp "$REPO_ROOT/config/bootstrap/tools.tsv" "$FIXTURE/config/bootstrap/tools.tsv"
write_clones() {
    {
        printf 'id\tdest\turl\tref\thosts\n'
        # shellcheck disable=SC2016 # literal manifest tokens
        printf '%s\t%s\t%s\t%s\t%s\n' \
            oh-my-zsh '$HOME/.oh-my-zsh' https://github.com/ohmyzsh/ohmyzsh.git master unix \
            powerlevel10k '$ZSH_CUSTOM/themes/powerlevel10k' https://github.com/romkatv/powerlevel10k.git "$P10K_PIN" unix \
            fzf-tab '$ZSH_CUSTOM/plugins/fzf-tab' https://github.com/Aloxaf/fzf-tab.git "$FZF_TAB_PIN" unix
    } >"$FIXTURE/config/bootstrap/git-clones.tsv"
}
write_clones
{
    printf 'id\tkind\turl\tsha256\tdest\thosts\tarch\ttier\thuman\n'
    # shellcheck disable=SC2016 # literal manifest tokens
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        homebrew script "$URL_HOMEBREW" "$SHA_HOMEBREW" - mac,wsl-ubuntu,lab-ubuntu any core sudo \
        nvm script "$URL_NVM" "$(sha "$FIXTURES/artifacts/nvm-install")" - mac,wsl-ubuntu,lab-ubuntu any ai - \
        micromamba binary "$URL_MICROMAMBA" "$SHA_MICROMAMBA" '$HOME/.local/bin/micromamba' sherlock,marlowe x86_64 core - \
        codex archive "$URL_CODEX" "$(sha "$ARTIFACTS/codex.tar.gz")" '$HOME/.codex/packages/standalone' wsl-ubuntu,lab-ubuntu x86_64 ai - \
        claude script "$URL_CLAUDE" - - wsl-ubuntu,lab-ubuntu any ai inspect \
        nerd-font archive "$URL_FONT" "$(sha "$ARTIFACTS/font.tar.xz")" '$XDG_DATA_HOME/fonts/CaskaydiaMonoNerdFont' lab-ubuntu any desktop - \
        kitty archive "$URL_KITTY" "$(sha "$ARTIFACTS/kitty.txz")" '$HOME/.local/kitty.app' lab-ubuntu x86_64 desktop - \
        bat-theme file "$URL_THEME" "$(sha "$ARTIFACTS/theme")" '$BAT_CONFIG_DIR/themes/Catppuccin Mocha.tmTheme' all any core -
} >"$FIXTURE/config/bootstrap/installers.tsv"

printf '%s\n' '# fixture zshrc' >"$FIXTURE/common/zsh/.zshrc"
mkdir -p "$FIXTURE/common/bash" "$FIXTURE/common/claude/.claude"
printf '%s\n' '# fixture bashrc' >"$FIXTURE/common/bash/.bashrc"
printf '%s\n' '{}' >"$FIXTURE/common/claude/.claude/settings.json"
cp "$REPO_ROOT/.stowrc" "$FIXTURE/.stowrc"
mkdir -p "$FIXTURE/scripts"
cp "$REPO_ROOT/scripts/awesome-skills-update.sh" "$FIXTURE/scripts/awesome-skills-update.sh"
printf '%s\n' '/.venv-sync/' >"$FIXTURE/.gitignore"
cat >"$FIXTURE/stow-all.sh" <<'SH'
#!/bin/sh
printf 'TRIPWIRE stow-all.sh %s\n' "$*" >>"$EVENT_LOG"
exit 99
SH
cat >"$FIXTURE/setup-sync.sh" <<'SH'
#!/bin/sh
root=$(cd "$(dirname "$0")" && pwd)
printf 'setup-sync:%s\n' "$*" >>"$EVENT_LOG"
mkdir -p "$root/.venv-sync/bin"
: >"$root/.venv-sync/pyvenv.cfg"
printf '#!/bin/sh\nexit 0\n' >"$root/.venv-sync/bin/python"
chmod 755 "$root/.venv-sync/bin/python"
SH
chmod 755 "$FIXTURE/setup-host.sh" "$FIXTURE/stow-all.sh" "$FIXTURE/setup-sync.sh"
"$REAL_GIT" -C "$FIXTURE" init -q
"$REAL_GIT" -C "$FIXTURE" add -A
"$REAL_GIT" -C "$FIXTURE" commit -q -m fixture

printf 'ID=ubuntu\nID_LIKE=debian\nVERSION_ID="24.04"\n' >"$OS_DEBIAN"
printf 'ID="rocky"\nID_LIKE="rhel centos fedora"\n' >"$OS_ROCKY"
printf 'Linux version 6.8.0-45-generic (buildd@lcy02-amd64-075) #45-Ubuntu SMP\n' >"$PROC_NATIVE"
printf 'Linux version 5.15.167.4-microsoft-standard-WSL2 (root@runner) #1 SMP\n' >"$PROC_WSL"
printf '%s\n' zsh git curl xclip >"$DPKG_ALL"
printf '%s\n' curl xclip >"$DPKG_PARTIAL"
HOMEBREW_SCRATCH_REL=.cache/dotfiles-bootstrap/homebrew/install.sh
CLAUDE_SCRATCH_REL=.cache/dotfiles-bootstrap/claude/install.sh

# --- refusals ----------------------------------------------------------------

new_home refusals
run_case win -- --host win
expect_rc win 2
expect_text win err 'setup-host.ps1'
expect_no_events win

run_case no-host -- --check
expect_rc no-host 2
expect_text no-host err 'no host: pass --host'

run_case unknown-host -- --host fedora --check
expect_rc unknown-host 2
expect_text unknown-host err 'unknown host: fedora'

run_case unknown-step -- --host lab-ubuntu --check --only S9-nothing
expect_rc unknown-step 2
expect_text unknown-step err "unknown step for lab-ubuntu: 'S9-nothing'"

run_case bad-tier -- --host lab-ubuntu --check --tier core,gui
expect_rc bad-tier 2

run_case mode-clash -- --host lab-ubuntu --check --list
expect_rc mode-clash 2

run_case no-tty -- --host lab-ubuntu
expect_rc no-tty 2
expect_text no-tty err 'refusing to apply without a terminal'
expect_no_events no-tty

run_case wrong-platform -- --host mac --check
expect_rc wrong-platform 2
expect_text wrong-platform err 'is macOS, but this kernel is Linux'

run_case wrong-distro BOOTSTRAP_OS_RELEASE="$OS_ROCKY" -- --host lab-ubuntu --check
expect_rc wrong-distro 2

# DOTFILES_HOST stands in for --host.
run_case env-host DOTFILES_HOST=win -- --check
expect_rc env-host 2
expect_text env-host err 'setup-host.ps1'

# A set but empty DOTFILES_HOST means common only, as the login updater reads
# it, and setup-host has no --platform: it asks for --host instead of using
# the host ./stow-all.sh recorded.
printf '%s\n' "$CASE_HOME" Linux lab-ubuntu recorded-head >"$FIXTURE/.git/dotfiles-sync-unix"
run_case env-host-recorded -- --check --only S3-dirs
expect_rc env-host-recorded 3
expect_text env-host-recorded out 'P0-preflight done host lab-ubuntu'
run_case env-host-empty DOTFILES_HOST= -- --check --only S3-dirs
expect_rc env-host-empty 2
expect_text env-host-empty err 'DOTFILES_HOST is set but empty, which means common only (no host overlay)'
expect_text env-host-empty err 'pass --host HOST'
expect_no_text env-host-empty out 'P0-preflight'
expect_no_events env-host-empty
run_case env-host-empty-explicit DOTFILES_HOST= -- --host lab-ubuntu --check --only S3-dirs
expect_rc env-host-empty-explicit 3
expect_text env-host-empty-explicit out 'P0-preflight done host lab-ubuntu'
# So is a common-only install that ./stow-all.sh recorded (an empty host
# line): exit 2 asking for --host, not the generic "no host"; DOTFILES_HOST
# and --host still win.
printf '%s\n' "$CASE_HOME" Linux '' recorded-head >"$FIXTURE/.git/dotfiles-sync-unix"
run_case state-common-only -- --check --only S3-dirs
expect_rc state-common-only 2
expect_text state-common-only err './stow-all.sh recorded a common-only install for this home (no host overlay)'
expect_text state-common-only err 'pass --host HOST'
expect_no_text state-common-only err 'no host: pass --host'
expect_no_text state-common-only out 'P0-preflight'
expect_no_events state-common-only
run_case state-common-only-list -- --list
expect_rc state-common-only-list 2
expect_text state-common-only-list err 'recorded a common-only install'
run_case state-common-only-env DOTFILES_HOST=lab-ubuntu -- --check --only S3-dirs
expect_rc state-common-only-env 3
expect_text state-common-only-env out 'P0-preflight done host lab-ubuntu'
run_case state-common-only-host -- --host lab-ubuntu --check --only S3-dirs
expect_rc state-common-only-host 3
expect_text state-common-only-host out 'P0-preflight done host lab-ubuntu'
rm -f "$FIXTURE/.git/dotfiles-sync-unix"

# Never as root: it would install into /root or leave root-owned files.
run_case root PATH="$ROOT_BIN:$FAKE_BIN:/usr/bin:/bin" -- --host lab-ubuntu --check
expect_rc root 2
expect_text root err 'run ./setup-host.sh as your user, not root'
expect_no_text root out 'P0-preflight'
expect_no_events root

# A cluster host needs Lmod; wsl-ubuntu needs WSL, lab-ubuntu needs its absence.
run_case hpc-no-lmod BOOTSTRAP_OS_RELEASE="$OS_ROCKY" -- --host sherlock --check
expect_rc hpc-no-lmod 2
expect_text hpc-no-lmod err 'host sherlock is a cluster with Lmod, but LMOD_DIR is unset here (detected other)'
run_case marlowe-no-lmod -- --host marlowe --yes
expect_rc marlowe-no-lmod 2
expect_text marlowe-no-lmod err 'LMOD_DIR is unset here (detected debian)'
expect_no_events marlowe-no-lmod
run_case wsl-native -- --host wsl-ubuntu --yes
expect_rc wsl-native 2
expect_text wsl-native err 'host wsl-ubuntu runs under WSL, but this is not WSL'
expect_no_events wsl-native
run_case lab-in-wsl BOOTSTRAP_PROC_VERSION="$PROC_WSL" -- --host lab-ubuntu --check
expect_rc lab-in-wsl 2
expect_text lab-in-wsl err 'host lab-ubuntu is a native workstation, but this is WSL; use --host wsl-ubuntu'
run_case wsl-kernel BOOTSTRAP_PROC_VERSION="$PROC_WSL" -- --host wsl-ubuntu --check
expect_rc wsl-kernel 3
expect_no_text wsl-kernel err 'refusing'
run_case wsl-distro WSL_DISTRO_NAME=Ubuntu -- --host wsl-ubuntu --check
expect_rc wsl-distro 3
expect_no_text wsl-distro err 'refusing'

# --- debian --check: zsh and git missing ------------------------------------

new_home debian-missing
snapshot >"$TEST_TMP/before"
touch "$MARKER"
run_case check-missing FAKE_DPKG_INSTALLED="$DPKG_PARTIAL" \
    BOOTSTRAP_BREW_CANDIDATES="$TEST_TMP/no-brew/brew" -- --host lab-ubuntu --check
expect_rc check-missing 3
expect_line check-missing 'HUMAN-BEGIN H1-apt-core sudo'
expect_line check-missing 'sudo apt-get update'
expect_line check-missing 'sudo apt-get install -y --no-install-recommends zsh git'
expect_line check-missing 'H1-apt-core human missing apt packages: zsh git'
expect_text check-missing out 'H1-linuxbrew human blocked by H1-apt-core'
expect_text check-missing out 'S3-clones todo blocked by H1-apt-core'
expect_text check-missing out 'H7-stow human waiting: oh-my-zsh must be cloned before ./stow-all.sh'
expect_no_text check-missing out 'HUMAN-BEGIN H1-linuxbrew'
expect_no_text check-missing out 'HUMAN-BEGIN H7-stow'
# chsh -s /usr/bin/zsh fails before the apt block installed zsh.
expect_text check-missing out 'H7-chsh human blocked by H1-apt-core'
expect_no_text check-missing out 'HUMAN-BEGIN H7-chsh'
expect_line check-missing 'HUMAN-BEGIN H7-auth auth'
expect_text check-missing err 'HUMAN steps pending: H1-apt-core H1-linuxbrew'
expect_text check-missing err 'steps to apply: S2-brew-bundle S3-clones'
expect_text check-missing err 'after the HUMAN blocks, rerun ./setup-host.sh --host lab-ubuntu without --check'
expect_no_events check-missing
snapshot >"$TEST_TMP/after"
cmp -s "$TEST_TMP/before" "$TEST_TMP/after" || {
    diff -u "$TEST_TMP/before" "$TEST_TMP/after" >&2 || true
    fail '--check created or removed files'
}
[ -z "$(find "$CASE_HOME" "$CASE_BREW" "$FIXTURE" -newer "$MARKER" -print)" ] || fail '--check modified files'

# --- debian --check: apt done, Homebrew present, nothing else ----------------

new_home debian
snapshot >"$TEST_TMP/before"
touch "$MARKER"
run_case check-fresh -- --host lab-ubuntu --check --tier all
expect_rc check-fresh 3
expect_text check-fresh out 'P0-preflight done host lab-ubuntu, profile debian, Linux x86_64'
expect_text check-fresh out 'H1-apt-core done 4 apt packages installed'
expect_text check-fresh out "H1-linuxbrew done brew at $CASE_BREW/bin/brew"
expect_text check-fresh out "S2-brew-bundle todo Brewfiles to bundle: core cli (offline estimate from $CASE_BREW/opt"
expect_text check-fresh out 'S3-clones todo to clone or re-pin: oh-my-zsh (clone) powerlevel10k (clone) fzf-tab (clone)'
expect_text check-fresh out 'S3-dirs todo'
expect_text check-fresh out 'S4-nvm todo'
expect_text check-fresh out 'S5-codex todo codex is not installed; pinned 0.161.0'
expect_text check-fresh out 'S6-kitty todo'
expect_text check-fresh out 'S5-claude human'
expect_line check-fresh 'HUMAN-BEGIN S5-claude inspect'
expect_text check-fresh out "downloads $URL_CLAUDE (unpinned)"
expect_text check-fresh out 'that runs it only while that sha256 holds'
expect_no_text check-fresh out "&& bash $CASE_HOME/$CLAUDE_SCRATCH_REL"
expect_text check-fresh out 'H1-locale done'
expect_line check-fresh 'HUMAN-BEGIN H1-fcitx5 gui'
expect_line check-fresh 'HUMAN-BEGIN H7-chsh chsh'
expect_line check-fresh 'HUMAN-BEGIN H7-sync-skills judgment'
expect_text check-fresh out 'unpinned curl of awesome-skills main'
expect_text check-fresh out '# on by default once stowed: every new interactive shell runs it unless AWESOME_SKILLS_AUTO_UPDATE=0'
SKILLS_LINE="AWESOME_SKILLS_AUTO_UPDATE=1 AWESOME_SKILLS_FORCE=1 AWESOME_SKILLS_BG=0 sh $FIXTURE/scripts/awesome-skills-update.sh"
expect_line check-fresh "$SKILLS_LINE"
expect_line check-fresh 'HUMAN-BEGIN H7-doctor judgment'
expect_no_events check-fresh
snapshot >"$TEST_TMP/after"
cmp -s "$TEST_TMP/before" "$TEST_TMP/after" || {
    diff -u "$TEST_TMP/before" "$TEST_TMP/after" >&2 || true
    fail '--check created or removed files'
}
[ -z "$(find "$CASE_HOME" "$CASE_BREW" "$FIXTURE" -newer "$MARKER" -print)" ] || fail '--check modified files'

# The skill-sync line runs the sync even in a provisioning shell, which
# exports AWESOME_SKILLS_AUTO_UPDATE=0 (curl is the stub; it logs the URL).
: >"$EVENT_LOG"
env -i HOME="$TEST_TMP/skills-home" PATH="$FAKE_BIN:/usr/bin:/bin" EVENT_LOG="$EVENT_LOG" \
    CURL_ARGS_LOG="$CURL_ARGS_LOG" URL_MAP="$URL_MAP" AWESOME_SKILLS_AUTO_UPDATE=0 \
    sh -c "$SKILLS_LINE" >/dev/null 2>&1 || true
expect_event 'curl:https://raw.githubusercontent.com/FridrichMethod/awesome-skills/main/install.sh'

# --- debian apply: every step, in phase order --------------------------------

run_case apply -- --host lab-ubuntu --yes --tier all
expect_rc apply 3
expect_order 'brew:bundle core.Brewfile' 'brew:bundle cli.Brewfile' \
    'git:clone -q --depth=1 --branch master' "git:-C $CASE_HOME/.oh-my-zsh/custom/themes/" \
    "curl:$URL_THEME" 'bat:cache --build' \
    "curl:$URL_NVM" 'nvm-install:PROFILE=/dev/null' 'nvm:install --lts' 'nvm:alias default lts/*' \
    'setup-sync:' "curl:$URL_CLAUDE" "curl:$URL_CODEX" "curl:$URL_FONT" 'fc-cache:-f' "curl:$URL_KITTY"
expect_event 'brew-env:DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0 GIT_TERMINAL_PROMPT=0 NONINTERACTIVE=1 HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1'
expect_event "nvm-install:PROFILE=/dev/null NVM_DIR=$CASE_HOME/.nvm NVM_INSTALL_VERSION=$NVM_PIN"
expect_no_event TRIPWIRE
expect_text apply out 'S3-clones done applied:'
expect_text apply out 'S5-codex done applied:'
expect_event 'codex-run:--version'
expect_line apply 'HUMAN-BEGIN S5-claude inspect'
expect_line apply "# sha256 $SHA_CLAUDE, $(wc -c <"$FIXTURES/artifacts/claude-install" | tr -d ' ') bytes; delete the file for a fresh copy"
expect_line apply "printf '%s  %s\\n' $SHA_CLAUDE $CASE_HOME/$CLAUDE_SCRATCH_REL | sha256sum -c --status - && bash $CASE_HOME/$CLAUDE_SCRATCH_REL"
expect_line apply 'HUMAN-BEGIN H7-stow judgment'
# One self-contained line: stow is on PATH only after the first stow.
expect_line apply "PATH=\"$CASE_BREW/bin:\$PATH\" $FIXTURE/stow-all.sh lab-ubuntu"
expect_text apply err 'HUMAN steps pending: S5-claude H7-stow'

[ "$(sha "$CASE_HOME/$CLAUDE_SCRATCH_REL")" = "$SHA_CLAUDE" ] || fail 'claude installer not staged'
[ -f "$CASE_HOME/.oh-my-zsh/oh-my-zsh.sh" ] || fail 'oh-my-zsh not cloned'
[ "$("$REAL_GIT" -C "$CASE_HOME/.oh-my-zsh" config oh-my-zsh.branch)" = master ] || fail 'oh-my-zsh clone config'
[ "$("$REAL_GIT" -C "$CASE_HOME/.oh-my-zsh/custom/themes/powerlevel10k" rev-parse HEAD)" = "$P10K_PIN" ] ||
    fail 'powerlevel10k not at its pin'
[ "$("$REAL_GIT" -C "$CASE_HOME/.oh-my-zsh/custom/plugins/fzf-tab" rev-parse HEAD)" = "$FZF_TAB_PIN" ] ||
    fail 'fzf-tab not at its pin'
cmp -s "$ARTIFACTS/theme" "$CASE_HOME/.config/bat/themes/Catppuccin Mocha.tmTheme" || fail 'bat theme'
[ -d "$CASE_HOME/.vim/undo" ] && [ -d "$CASE_HOME/.vim/tmp" ] || fail 'vim dirs'
[ -x "$CASE_HOME/.nvm/versions/node/v24.11.1/bin/node" ] && [ -f "$CASE_HOME/.nvm/alias/default" ] || fail 'nvm node'
[ "$("$REAL_GIT" -C "$CASE_HOME/.nvm" rev-parse HEAD)" = "$NVM_PIN" ] || fail 'nvm not at its pinned commit'
[ -f "$FIXTURE/.venv-sync/pyvenv.cfg" ] || fail 'setup-sync did not run'
CODEX_RELEASE="$CASE_HOME/.codex/packages/standalone/releases/0.161.0-x86_64-unknown-linux-musl"
[ "$(readlink "$CODEX_RELEASE/codex")" = bin/codex ] || fail 'codex release link'
[ "$(readlink "$CASE_HOME/.codex/packages/standalone/current")" = "$CODEX_RELEASE" ] || fail 'codex current link'
[ "$(readlink "$CASE_HOME/.local/bin/codex")" = "$CASE_HOME/.codex/packages/standalone/current/bin/codex" ] ||
    fail 'codex ~/.local/bin link'
[ -z "$(find "$CASE_HOME/.codex/packages/standalone" -maxdepth 1 -name '.extract.*')" ] || fail 'codex temp dir left'
[ -f "$CASE_HOME/.local/share/fonts/CaskaydiaMonoNerdFont/CaskaydiaMonoNerdFont-Regular.ttf" ] || fail 'font'
[ "$(readlink "$CASE_HOME/.local/bin/kitty")" = "$CASE_HOME/.local/kitty.app/bin/kitty" ] || fail 'kitty link'
[ "$(readlink "$CASE_HOME/.local/bin/kitten")" = "$CASE_HOME/.local/kitty.app/bin/kitten" ] || fail 'kitten link'
[ -z "$("$REAL_GIT" -C "$FIXTURE" status --porcelain)" ] || fail 'apply dirtied the checkout'

# The inspect download is kept: a later apply never replaces the copy a
# person read, and its run line runs that copy only while it has the digest
# the block shows.
CLAUDE_SCRATCH="$CASE_HOME/$CLAUDE_SCRATCH_REL"
GATE_LOG="$TEST_TMP/gate.log"
printf '%s\n' '# reviewed version A' 'printf "reviewed-run\n" >>"$GATE_LOG"' >"$CLAUDE_SCRATCH"
SHA_REVIEWED=$(sha "$CLAUDE_SCRATCH")
run_case claude-keep -- --host lab-ubuntu --yes --only S5-claude
expect_rc claude-keep 3
expect_no_event "curl:$URL_CLAUDE"
[ "$(sha "$CLAUDE_SCRATCH")" = "$SHA_REVIEWED" ] || fail 'a later apply replaced the reviewed claude installer'
expect_text claude-keep out "# sha256 $SHA_REVIEWED, "
GATE_LINE="printf '%s  %s\\n' $SHA_REVIEWED $CLAUDE_SCRATCH | sha256sum -c --status - && bash $CLAUDE_SCRATCH"
expect_line claude-keep "$GATE_LINE"
run_case claude-keep-check -- --host lab-ubuntu --check --only S5-claude
expect_line claude-keep-check "$GATE_LINE"
expect_no_events claude-keep-check
if command -v sha256sum >/dev/null 2>&1; then
    : >"$GATE_LOG"
    GATE_LOG="$GATE_LOG" bash -c "$GATE_LINE" || fail 'the claude gate rejects the reviewed copy'
    grep -qx reviewed-run "$GATE_LOG" || fail 'the claude gate did not run the reviewed copy'
    printf '%s\n' 'printf "tampered-run\n" >>"$GATE_LOG"' >>"$CLAUDE_SCRATCH"
    : >"$GATE_LOG"
    if GATE_LOG="$GATE_LOG" bash -c "$GATE_LINE" 2>/dev/null; then
        fail 'the claude gate ran a changed installer'
    fi
    [ ! -s "$GATE_LOG" ] || fail 'the claude gate ran a changed installer'
fi
cp "$FIXTURES/artifacts/claude-install" "$CLAUDE_SCRATCH"

# A second apply installs nothing; once ~/.zshrc is stowed nothing blocks.
printf '#!/bin/sh\necho "2.0.0 (Claude Code)"\n' >"$CASE_HOME/.local/bin/claude"
chmod 755 "$CASE_HOME/.local/bin/claude"
run_case reapply -- --host lab-ubuntu --yes --tier all
expect_rc reapply 3
expect_no_installs reapply
expect_event 'brew-check:core.Brewfile'
expect_text reapply out 'S5-claude done claude at'
expect_text reapply out 'S2-brew-bundle done Brewfiles satisfied: core cli'
expect_line reapply 'HUMAN-BEGIN H7-stow judgment'
ln -s "$FIXTURE/common/zsh/.zshrc" "$CASE_HOME/.zshrc"
run_case stowed -- --host lab-ubuntu --yes --tier all
expect_rc stowed 0
expect_no_installs stowed
expect_text stowed out "H7-stow done $CASE_HOME/.zshrc links into $FIXTURE/common"
expect_no_text stowed out 'HUMAN-BEGIN H7-stow'
expect_line stowed 'HUMAN-BEGIN H7-auth auth'
expect_text stowed out 'nothing blocking remains for lab-ubuntu'
run_case check-done -- --host lab-ubuntu --check --tier all
expect_rc check-done 0
expect_no_events check-done
expect_text check-done out "S2-brew-bundle done Brewfiles satisfied: core cli (offline estimate"

# Exit 0 means done: an auto step still to apply makes a --check exit 3.
rm -rf "$CASE_HOME/.vim"
run_case check-todo -- --host lab-ubuntu --check --tier all
expect_rc check-todo 3
expect_text check-todo out 'S3-dirs todo'
expect_text check-todo err 'steps to apply: S3-dirs; rerun ./setup-host.sh --host lab-ubuntu --tier all without --check'
expect_no_text check-todo out 'nothing blocking remains'
expect_no_text check-todo err 'HUMAN steps pending'
expect_no_events check-todo
mkdir -p "$CASE_HOME/.vim/undo" "$CASE_HOME/.vim/tmp"

# --- clones: re-pin a clean drifted clone, refuse a dirty one ----------------

FZF_TAB_WORK="$TEST_TMP/work/Aloxaf/fzf-tab"
printf '# v2\n' >>"$FZF_TAB_WORK/fzf-tab.plugin.zsh"
"$REAL_GIT" -C "$FZF_TAB_WORK" commit -q -am v2
"$REAL_GIT" -C "$FZF_TAB_WORK" push -q "$REMOTES/Aloxaf/fzf-tab.git" master
FZF_TAB_PIN=$("$REAL_GIT" -C "$FZF_TAB_WORK" rev-parse HEAD)
write_clones
"$REAL_GIT" -C "$FIXTURE" commit -q -am 're-pin fzf-tab'
P10K_DIR="$CASE_HOME/.oh-my-zsh/custom/themes/powerlevel10k"
printf '# local edit\n' >>"$P10K_DIR/powerlevel10k.zsh-theme"
run_case repin -- --host lab-ubuntu --yes --only S3-clones
expect_rc repin 1
expect_event "git:-C $CASE_HOME/.oh-my-zsh/custom/plugins/fzf-tab fetch -q --depth=1 origin $FZF_TAB_PIN"
[ "$("$REAL_GIT" -C "$CASE_HOME/.oh-my-zsh/custom/plugins/fzf-tab" rev-parse HEAD)" = "$FZF_TAB_PIN" ] ||
    fail 'fzf-tab was not re-pinned'
[ "$("$REAL_GIT" -C "$P10K_DIR" rev-parse HEAD)" = "$P10K_PIN" ] || fail 'dirty powerlevel10k moved'
expect_text repin err "$P10K_DIR has local changes"
expect_text repin out 'S3-clones failed'
expect_no_event "git:-C $P10K_DIR"
"$REAL_GIT" -C "$P10K_DIR" checkout -q -- powerlevel10k.zsh-theme

# A --check never hands out ./stow-all.sh while an auto prerequisite is todo.
new_home cloned-only
run_case cloned-only -- --host lab-ubuntu --yes --only S3-clones
expect_rc cloned-only 0
run_case check-cloned -- --host lab-ubuntu --check
expect_rc check-cloned 3
expect_text check-cloned out 'S3-clones done 3 clones at their pins'
expect_text check-cloned out 'H7-stow human blocked by S2-brew-bundle'
expect_no_text check-cloned out 'HUMAN-BEGIN H7-stow'
expect_no_events check-cloned

# --- H7-stow: home files Stow would refuse are moved aside first -------------

new_home stow-conflicts
mkdir -p "$CASE_HOME/.oh-my-zsh" "$CASE_HOME/.claude"
: >"$CASE_HOME/.oh-my-zsh/oh-my-zsh.sh"
printf '# from /etc/skel\n' >"$CASE_HOME/.bashrc"
ln -s "$TEST_TMP/elsewhere/.zshrc" "$CASE_HOME/.zshrc"
# A regular file by design: .stowrc ignores the tracked settings.json.
printf '{}\n' >"$CASE_HOME/.claude/settings.json"
run_case stow-conflicts -- --host lab-ubuntu --check --only H7-stow
expect_rc stow-conflicts 3
expect_text stow-conflicts out 'H7-stow human '
expect_text stow-conflicts out '2 home file(s) to move aside first: .bashrc .zshrc'
expect_text stow-conflicts out 'stow --adopt would overwrite the tracked copies'
expect_line stow-conflicts "mv -n $CASE_HOME/.bashrc $CASE_HOME/.bashrc.pre-dotfiles"
expect_line stow-conflicts "mv -n $CASE_HOME/.zshrc $CASE_HOME/.zshrc.pre-dotfiles"
expect_no_text stow-conflicts out 'settings.json.pre-dotfiles'
expect_no_events stow-conflicts
# A link into this checkout is Stow's own: nothing to move.
rm "$CASE_HOME/.bashrc"
ln -s "$FIXTURE/common/bash/.bashrc" "$CASE_HOME/.bashrc"
run_case stow-own-link -- --host lab-ubuntu --check --only H7-stow
expect_text stow-own-link out '1 home file(s) to move aside first: .zshrc'
expect_no_text stow-own-link out "mv -n $CASE_HOME/.bashrc"

# --- S2-brew-bundle: a conflicting formula stops it before brew runs ---------

# The fixture cli.Brewfile declares "# conflicts: tlrc tldr tealdeer", as the
# real one does: Homebrew will not install tlrc next to a tldr keg, and
# brew bundle then fails with no more than that.
new_home brew-conflict
mkdir -p "$CASE_BREW/Cellar/tldr/1.6.1"
run_case brew-conflict-check -- --host lab-ubuntu --check --only S2-brew-bundle
expect_rc brew-conflict-check 3
expect_text brew-conflict-check out 'S2-brew-bundle human the installed tldr formula conflicts with tlrc (cli.Brewfile); brew bundle would fail'
expect_line brew-conflict-check 'HUMAN-BEGIN S2-brew-bundle judgment'
expect_line brew-conflict-check '# docs/bootstrap.md S2-brew-bundle'
expect_line brew-conflict-check "$CASE_BREW/bin/brew uninstall --formula tldr"
expect_no_text brew-conflict-check out 'uninstall --formula tealdeer'
expect_text brew-conflict-check err 'HUMAN steps pending: S2-brew-bundle'
expect_no_events brew-conflict-check
# Apply stops too, before brew bundle check or brew bundle.
run_case brew-conflict-apply -- --host lab-ubuntu --yes --only S2-brew-bundle
expect_rc brew-conflict-apply 3
expect_line brew-conflict-apply "$CASE_BREW/bin/brew uninstall --formula tldr"
expect_no_events brew-conflict-apply
[ ! -e "$CASE_BREW/opt" ] || fail 'S2-brew-bundle ran brew bundle next to a conflicting formula'
# A keg in $HOMEBREW_CELLAR counts as well.
mkdir -p "$TEST_TMP/cellar-elsewhere/tealdeer/1.7.0"
run_case brew-conflict-cellar HOMEBREW_CELLAR="$TEST_TMP/cellar-elsewhere" -- \
    --host lab-ubuntu --check --only S2-brew-bundle
expect_rc brew-conflict-cellar 3
expect_line brew-conflict-cellar "$CASE_BREW/bin/brew uninstall --formula tldr"
expect_line brew-conflict-cellar "$CASE_BREW/bin/brew uninstall --formula tealdeer"
# Without the keg the bundle runs; once tlrc is installed a tldr keg is no
# conflict any more (brew bundle has nothing left to install).
rm -rf "$CASE_BREW/Cellar/tldr"
run_case brew-conflict-gone -- --host lab-ubuntu --yes --only S2-brew-bundle
expect_rc brew-conflict-gone 0
expect_event 'brew:bundle cli.Brewfile'
[ -e "$CASE_BREW/opt/tlrc" ] || fail 'tlrc was not bundled once the conflicting keg was gone'
mkdir -p "$CASE_BREW/Cellar/tldr/1.6.1"
run_case brew-conflict-installed -- --host lab-ubuntu --check --only S2-brew-bundle
expect_rc brew-conflict-installed 0
expect_text brew-conflict-installed out 'S2-brew-bundle done Brewfiles satisfied: core cli'
expect_no_text brew-conflict-installed out 'HUMAN-BEGIN S2-brew-bundle'

# --- S2-brew-bundle: a conflicting cask, judged only where it installs -------

# A desktop Brewfile like the real one, for these cases only: a macOS-only
# cask whose "# conflicts: cask TOKEN OTHER" line names its @nightly twin.
# On mac a Caskroom/kitty@nightly directory stops the step before brew runs;
# on Linux brew bundle skips the cask, so the pair never applies.
DESKTOP_BREWFILE="$FIXTURE/config/bootstrap/brew/desktop.Brewfile"
printf '%s\n' '# conflicts: cask kitty kitty@nightly' 'cask "kitty" if OS.mac?' >"$DESKTOP_BREWFILE"
CASK_MAC=(BOOTSTRAP_UNAME_S=Darwin BOOTSTRAP_UNAME_M=aarch64 FAKE_XCODE=1)
new_home cask-conflict
mkdir -p "$CASE_BREW/Caskroom/kitty@nightly/0.44.0"
run_case cask-conflict-check "${CASK_MAC[@]}" -- --host mac --check --tier desktop --only S2-brew-bundle
expect_rc cask-conflict-check 3
expect_text cask-conflict-check out 'S2-brew-bundle human the installed kitty@nightly cask conflicts with kitty (desktop.Brewfile); brew bundle would fail'
expect_line cask-conflict-check 'HUMAN-BEGIN S2-brew-bundle judgment'
expect_line cask-conflict-check '# Homebrew does not install kitty (desktop.Brewfile) while the kitty@nightly cask is installed (conflicts_with), so brew bundle would fail'
expect_line cask-conflict-check "$CASE_BREW/bin/brew uninstall --cask kitty@nightly"
expect_no_text cask-conflict-check out 'uninstall --formula'
expect_no_events cask-conflict-check
run_case cask-conflict-apply "${CASK_MAC[@]}" -- --host mac --yes --tier desktop --only S2-brew-bundle
expect_rc cask-conflict-apply 3
expect_line cask-conflict-apply "$CASE_BREW/bin/brew uninstall --cask kitty@nightly"
expect_no_events cask-conflict-apply
run_case cask-conflict-manual "${CASK_MAC[@]}" -- --host mac --print-manual --tier desktop
expect_rc cask-conflict-manual 0
expect_line cask-conflict-manual "$CASE_BREW/bin/brew uninstall --cask kitty@nightly"
# The pair is not judged on Linux, in --check or --print-manual.
run_case cask-conflict-linux -- --host lab-ubuntu --check --tier desktop --only S2-brew-bundle
expect_rc cask-conflict-linux 0
expect_text cask-conflict-linux out 'S2-brew-bundle done Brewfiles satisfied: desktop'
expect_no_text cask-conflict-linux out 'kitty@nightly'
run_case cask-conflict-linux-manual -- --host lab-ubuntu --print-manual --tier desktop
expect_rc cask-conflict-linux-manual 0
expect_no_text cask-conflict-linux-manual out 'kitty@nightly'
# Once kitty itself is installed, its @nightly twin is no conflict.
mkdir -p "$CASE_BREW/Caskroom/kitty/0.44.0"
run_case cask-conflict-installed "${CASK_MAC[@]}" -- --host mac --check --tier desktop --only S2-brew-bundle
expect_rc cask-conflict-installed 0
expect_text cask-conflict-installed out 'S2-brew-bundle done Brewfiles satisfied: desktop'
expect_no_text cask-conflict-installed out 'HUMAN-BEGIN S2-brew-bundle'
rm -f "$DESKTOP_BREWFILE"

# --- nvm: only the pinned, unmodified checkout is ever sourced --------------

new_home nvm-moved
run_case nvm-moved FAKE_NVM_REF=master -- --host lab-ubuntu --yes --only S4-nvm
expect_rc nvm-moved 1
expect_text nvm-moved err "not the pinned nvm commit $NVM_PIN"
expect_event "curl:$URL_NVM"
expect_no_event 'nvm:'
[ ! -e "$CASE_HOME/.nvm" ] || fail 'an nvm checkout off its pin was left in place'

# nvm_checkout HOME REF: HOME/.nvm as the fixture installer lays it out at REF
# (empty: the pinned commit), with an nvm.sh that records being sourced.
nvm_checkout() {
    mkdir -p "$1/.nvm"
    EVENT_LOG="$TEST_TMP/nvm-setup.log" NVM_DIR="$1/.nvm" NVM_INSTALL_VERSION="$NVM_PIN" FAKE_NVM_REF="$2" \
        sh "$FIXTURES/artifacts/nvm-install" >/dev/null
    printf '%s\n' 'printf "nvm-sourced\n" >>"$EVENT_LOG"' | cat - "$1/.nvm/nvm.sh" >"$1/.nvm/nvm.sh.new"
    mv "$1/.nvm/nvm.sh.new" "$1/.nvm/nvm.sh"
}

# The pinned checkout without node: sourced, and node installed.
new_home nvm-pinned
nvm_checkout "$CASE_HOME" ''
run_case nvm-pinned -- --host lab-ubuntu --yes --only S4-nvm
expect_rc nvm-pinned 0
expect_no_event "curl:$URL_NVM"
expect_order 'nvm-sourced' 'nvm:install --lts' 'nvm:alias default lts/*'
[ -f "$CASE_HOME/.nvm/alias/default" ] || fail 'the pinned nvm checkout got no default alias'

# A checkout off the pin with no default node: a judgment block, never sourced.
new_home nvm-foreign
nvm_checkout "$CASE_HOME" master
NVM_MOVED=$("$REAL_GIT" -C "$CASE_HOME/.nvm" rev-parse HEAD)
[ "$NVM_MOVED" != "$NVM_PIN" ] || fail 'the moved nvm fixture is at the pin'
run_case nvm-foreign-check -- --host lab-ubuntu --check --only S4-nvm
expect_rc nvm-foreign-check 3
expect_text nvm-foreign-check out "S4-nvm human nvm has no node >= 22.0; $CASE_HOME/.nvm is at $NVM_MOVED, not the pinned nvm commit $NVM_PIN, so its nvm.sh is not sourced"
expect_line nvm-foreign-check 'HUMAN-BEGIN S4-nvm judgment'
expect_line nvm-foreign-check "git -C $CASE_HOME/.nvm fetch --depth=1 https://github.com/nvm-sh/nvm.git $NVM_PIN"
expect_line nvm-foreign-check "git -C $CASE_HOME/.nvm -c advice.detachedHead=false checkout --detach $NVM_PIN"
expect_text nvm-foreign-check err 'HUMAN steps pending: S4-nvm'
expect_no_events nvm-foreign-check
run_case nvm-foreign -- --host lab-ubuntu --yes --only S4-nvm
expect_rc nvm-foreign 3
expect_line nvm-foreign 'HUMAN-BEGIN S4-nvm judgment'
expect_no_event 'nvm-sourced'
expect_no_event 'nvm:'
expect_no_event "curl:$URL_NVM"
[ ! -e "$CASE_HOME/.nvm/alias/default" ] || fail 'an nvm checkout off its pin got a default alias'
# The block's command lines, each run on its own, bring it to the pin; the
# next apply sources it.
sed -n '/^HUMAN-BEGIN S4-nvm /,/^HUMAN-END$/p' "$TEST_TMP/nvm-foreign.out" |
    grep -v -e '^HUMAN-' -e '^#' >"$TEST_TMP/nvm-block.lines"
[ "$(grep -c . "$TEST_TMP/nvm-block.lines")" = 2 ] || fail "nvm block: $(cat "$TEST_TMP/nvm-block.lines")"
while IFS= read -r line; do
    bash -c "$line" >/dev/null 2>&1 </dev/null || fail "the nvm block line failed: $line"
done <"$TEST_TMP/nvm-block.lines"
[ "$("$REAL_GIT" -C "$CASE_HOME/.nvm" rev-parse HEAD)" = "$NVM_PIN" ] || fail 'the nvm block did not reach the pin'
run_case nvm-foreign-fixed -- --host lab-ubuntu --yes --only S4-nvm
expect_rc nvm-foreign-fixed 0
expect_order 'nvm-sourced' 'nvm:install --lts'

# With node at the floor and a default alias, any checkout is done, unsourced.
new_home nvm-done
nvm_checkout "$CASE_HOME" master
mkdir -p "$CASE_HOME/.nvm/versions/node/v24.11.1/bin" "$CASE_HOME/.nvm/alias"
printf '#!/bin/sh\necho v24.11.1\n' >"$CASE_HOME/.nvm/versions/node/v24.11.1/bin/node"
chmod 755 "$CASE_HOME/.nvm/versions/node/v24.11.1/bin/node"
printf 'lts/*\n' >"$CASE_HOME/.nvm/alias/default"
run_case nvm-done -- --host lab-ubuntu --yes --only S4-nvm
expect_rc nvm-done 0
expect_text nvm-done out "S4-nvm done nvm in $CASE_HOME/.nvm with node 24.11.1 and a default alias"
expect_no_event 'nvm-sourced'
expect_no_event 'nvm:'

# An nvm.sh outside a git checkout cannot be checked: moved aside, not sourced.
new_home nvm-plain
mkdir -p "$CASE_HOME/.nvm"
printf '%s\n' 'printf "nvm-sourced\n" >>"$EVENT_LOG"' >"$CASE_HOME/.nvm/nvm.sh"
run_case nvm-plain -- --host lab-ubuntu --yes --only S4-nvm
expect_rc nvm-plain 3
expect_text nvm-plain out "$CASE_HOME/.nvm is not a git checkout, so its nvm.sh cannot be checked against the pinned commit and is not sourced"
expect_line nvm-plain "mv -n $CASE_HOME/.nvm $CASE_HOME/.nvm.pre-dotfiles"
expect_no_event 'nvm-sourced'

# The pinned commit with a changed tracked file is not the pinned nvm.sh.
new_home nvm-dirty
nvm_checkout "$CASE_HOME" ''
printf '# a local edit\n' >>"$CASE_HOME/.nvm/README.md"
run_case nvm-dirty -- --host lab-ubuntu --yes --only S4-nvm
expect_rc nvm-dirty 3
expect_text nvm-dirty out "$CASE_HOME/.nvm has local changes at the pinned commit, so its nvm.sh is not sourced"
expect_line nvm-dirty "git -C $CASE_HOME/.nvm checkout -- ."
expect_no_event 'nvm-sourced'

# --- oh-my-zsh recovery: stow ran before the clone ---------------------------

new_home recovery
mkdir -p "$CASE_HOME/.oh-my-zsh/custom"
printf '# stowed\n' >"$CASE_HOME/.oh-my-zsh/custom/fzf.zsh"
run_case recovery -- --host lab-ubuntu --yes --only S3-clones
expect_rc recovery 3
expect_line recovery 'HUMAN-BEGIN X-recovery judgment'
expect_line recovery "git -C $CASE_HOME/.oh-my-zsh checkout -b master origin/master"
expect_text recovery out 'S3-clones human'
expect_no_events recovery
[ ! -e "$CASE_HOME/.oh-my-zsh/custom/themes" ] || fail 'recovery case cloned plugins'

# --- rc-pollution guard ------------------------------------------------------

new_home pollution
run_case pollution BREW_POLLUTE="$FIXTURE/common/zsh/.zshrc" -- --host lab-ubuntu --yes --only S2-brew-bundle
expect_rc pollution 1
expect_text pollution err 'S2-brew-bundle failed: changed files in'
expect_text pollution err 'common/zsh/.zshrc'
"$REAL_GIT" -C "$FIXTURE" checkout -q -- common/zsh/.zshrc

# The guard compares content: a file that was already modified keeps its
# status line, and a file added inside an untracked dir would hide behind
# `?? dir/` in the default status.
printf '# a local edit\n' >>"$FIXTURE/common/zsh/.zshrc"
new_home pollution-dirty
run_case pollution-dirty BREW_POLLUTE="$FIXTURE/common/zsh/.zshrc" -- --host lab-ubuntu --yes --only S2-brew-bundle
expect_rc pollution-dirty 1
expect_text pollution-dirty err "uncommitted changes in $FIXTURE: common/zsh/.zshrc;"
expect_text pollution-dirty err "S2-brew-bundle failed: changed files in $FIXTURE: common/zsh/.zshrc"
"$REAL_GIT" -C "$FIXTURE" checkout -q -- common/zsh/.zshrc

mkdir -p "$FIXTURE/common/extra"
printf '# untracked\n' >"$FIXTURE/common/extra/a.zsh"
new_home pollution-new
run_case pollution-new BREW_POLLUTE="$FIXTURE/common/extra/b.zsh" -- --host lab-ubuntu --yes --only S2-brew-bundle
expect_rc pollution-new 1
expect_text pollution-new err "S2-brew-bundle failed: changed files in $FIXTURE: common/extra/b.zsh"
new_home pollution-untracked
run_case pollution-untracked BREW_POLLUTE="$FIXTURE/common/extra/a.zsh" -- --host lab-ubuntu --yes --only S2-brew-bundle
expect_rc pollution-untracked 1
expect_text pollution-untracked err "S2-brew-bundle failed: changed files in $FIXTURE: common/extra/a.zsh"
rm -rf "$FIXTURE/common/extra"
[ -z "$("$REAL_GIT" -C "$FIXTURE" status --porcelain)" ] || fail 'the pollution cases left the fixture checkout dirty'

# --- --only, --skip and --keep-going -----------------------------------------

new_home only
run_case only -- --host lab-ubuntu --yes --only S3-dirs
expect_rc only 0
expect_no_events only
[ -d "$CASE_HOME/.vim/undo" ] || fail '--only S3-dirs did not run it'
expect_text only out 'S3-clones skip not selected by --only'
expect_text only out 'H7-stow skip not selected by --only'

new_home skip
run_case skip -- --host lab-ubuntu --yes --only S3-dirs --skip S3-dirs
expect_rc skip 0
expect_text skip out 'S3-dirs skip skipped by --skip'
[ ! -e "$CASE_HOME/.vim" ] || fail '--skip S3-dirs ran it'

# A prerequisite left undone by --skip or a declined prompt holds H7-stow:
# ./stow-all.sh is never handed out before stow and .venv-sync exist.
new_home skipped
mkdir -p "$CASE_HOME/.oh-my-zsh"
: >"$CASE_HOME/.oh-my-zsh/oh-my-zsh.sh"
run_case skipped -- --host lab-ubuntu --yes --only S2-brew-bundle --only H7-stow --skip S2-brew-bundle
expect_rc skipped 3
expect_text skipped out 'S2-brew-bundle skip skipped by --skip'
expect_text skipped out 'H7-stow human blocked by S2-brew-bundle (skipped)'
expect_no_text skipped out 'HUMAN-BEGIN H7-stow'
expect_no_events skipped

if [ "$HAVE_PTY" = 1 ]; then
    run_tty_case declined n -- --host lab-ubuntu --only S2-brew-bundle --only H7-stow
    expect_rc declined 3
    expect_text declined out 'Apply S2-brew-bundle? [y/N]'
    expect_text declined out 'S2-brew-bundle skip declined: brew bundle'
    expect_text declined out 'H7-stow human blocked by S2-brew-bundle (declined)'
    expect_no_text declined out 'HUMAN-BEGIN H7-stow'
    expect_text declined out 'steps not applied: S2-brew-bundle; after the HUMAN blocks, rerun ./setup-host.sh --host lab-ubuntu'
    expect_no_text declined out 'nothing blocking remains'
    expect_no_installs declined
    [ ! -e "$CASE_BREW/opt" ] || fail 'a declined S2-brew-bundle ran brew bundle'

    new_home declined-dirs
    run_tty_case declined-dirs n -- --host lab-ubuntu --only S3-dirs
    expect_rc declined-dirs 3
    expect_text declined-dirs out 'S3-dirs skip declined: mkdir -p ~/.vim/undo ~/.vim/tmp'
    expect_no_text declined-dirs out 'nothing blocking remains'
    [ ! -e "$CASE_HOME/.vim" ] || fail 'a declined S3-dirs ran'

    run_tty_case accepted-dirs y -- --host lab-ubuntu --only S3-dirs
    expect_rc accepted-dirs 0
    expect_text accepted-dirs out 'S3-dirs done applied:'
    [ -d "$CASE_HOME/.vim/undo" ] || fail 'an accepted S3-dirs did not run'
else
    printf '%s\n' 'setup-host: SKIP the prompt cases (python3 with pty is not available)' >&2
fi

new_home stop
run_case stop BREW_FAIL=1 -- --host lab-ubuntu --yes --only S2-brew-bundle --only S3-dirs
expect_rc stop 1
expect_text stop err 'stopped after S2-brew-bundle failed'
[ ! -e "$CASE_HOME/.vim" ] || fail 'a later step ran after a failure without --keep-going'

new_home keep-going
run_case keep-going BREW_FAIL=1 -- --host lab-ubuntu --yes --keep-going --only S2-brew-bundle --only S3-dirs
expect_rc keep-going 1
[ -d "$CASE_HOME/.vim/undo" ] || fail '--keep-going did not continue'
expect_text keep-going err 'failed steps: S2-brew-bundle'

# --- hpc: the login env only inside an allocation ----------------------------

new_home sherlock
HPC_ENV=(LMOD_DIR=/opt/lmod BOOTSTRAP_OS_RELEASE="$OS_ROCKY")
rm -rf "$FIXTURE/.venv-sync"
run_case hpc-login "${HPC_ENV[@]}" -- --host sherlock --yes
expect_rc hpc-login 3
expect_event "curl:$URL_MICROMAMBA"
expect_no_event 'micromamba:create'
expect_no_event 'setup-sync:'
expect_line hpc-login 'HUMAN-BEGIN H2-alloc alloc'
expect_line hpc-login 'sh_dev -t 1:00:00'
expect_text hpc-login out 'S2-login-env todo blocked by H2-alloc'
expect_text hpc-login out 'S4-setup-sync todo blocked by S2-login-env'
expect_line hpc-login 'HUMAN-BEGIN S2-modules judgment'
# No site module provides claude or codex here, so H7-auth does not name them.
expect_line hpc-login 'HUMAN-BEGIN H7-auth auth'
expect_line hpc-login 'kinit'
expect_no_text hpc-login out 'codex login'
expect_no_text hpc-login out '# Claude Code signs in'
[ -x "$CASE_HOME/.local/bin/micromamba" ] || fail 'micromamba not installed'
[ "$(sha "$CASE_HOME/.local/bin/micromamba")" = "$SHA_MICROMAMBA" ] || fail 'micromamba digest'

run_case hpc-alloc "${HPC_ENV[@]}" SLURM_JOB_ID=1 -- --host sherlock --yes
expect_rc hpc-alloc 3
expect_event "micromamba:create -y -r $CASE_HOME/micromamba -n login -f $FIXTURE/config/bootstrap/hpc-login-env.yml"
expect_event "setup-sync:--python $CASE_HOME/micromamba/envs/login/bin/python3"
expect_line hpc-alloc 'HUMAN-BEGIN H7-stow judgment'
expect_line hpc-alloc "PATH=\"\$HOME/micromamba/envs/login/bin:\$PATH\" $FIXTURE/stow-all.sh sherlock"
expect_no_text hpc-alloc out 'HUMAN-BEGIN H2-alloc'
expect_no_event TRIPWIRE

new_home sherlock-scratch
run_case hpc-scratch "${HPC_ENV[@]}" SLURM_JOB_ID=1 SCRATCH="$TEST_TMP/homes" -- \
    --host sherlock --yes --only S2-micromamba --only S2-login-env
expect_rc hpc-scratch 1
expect_text hpc-scratch err 'refusing to build the login env under $SCRATCH'
expect_no_event 'micromamba:create'

# --- digest mismatch ---------------------------------------------------------

new_home mismatch
run_case mismatch "${HPC_ENV[@]}" URL_MAP="$URL_MAP_BAD" -- --host sherlock --yes --only S2-micromamba
expect_rc mismatch 1
expect_text mismatch err "expected $SHA_MICROMAMBA, actual $SHA_MICROMAMBA_BAD"
[ ! -e "$CASE_HOME/.local/bin/micromamba" ] || fail 'mismatched micromamba was installed'
[ ! -e "$CASE_HOME/.local/bin/micromamba.part" ] || fail 'mismatched download left a .part file'

# --- macOS: Homebrew is a HUMAN sudo block with a verified installer ---------

MAC_ENV=(BOOTSTRAP_UNAME_S=Darwin BOOTSTRAP_UNAME_M=aarch64 FAKE_XCODE=1
    BOOTSTRAP_BREW_CANDIDATES="$TEST_TMP/no-brew/brew")
new_home mac
snapshot >"$TEST_TMP/before"
run_case mac-check "${MAC_ENV[@]}" -- --host mac --check
expect_rc mac-check 3
expect_line mac-check 'HUMAN-BEGIN H1-homebrew sudo'
expect_text mac-check out "downloads $URL_HOMEBREW"
expect_text mac-check out "verifies sha256 $SHA_HOMEBREW first"
MAC_GATE="printf '%s  %s\\n' $SHA_HOMEBREW $CASE_HOME/$HOMEBREW_SCRATCH_REL | shasum -a 256 -c --status - && NONINTERACTIVE=1 /bin/bash $CASE_HOME/$HOMEBREW_SCRATCH_REL"
expect_line mac-check "$MAC_GATE"
expect_no_text mac-check out 'stop unless'
expect_text mac-check out 'S2-brew-bundle todo blocked by H1-homebrew'
expect_no_events mac-check
snapshot >"$TEST_TMP/after"
cmp -s "$TEST_TMP/before" "$TEST_TMP/after" || fail 'mac --check wrote files'

run_case mac-brew "${MAC_ENV[@]}" -- --host mac --yes --only H1-homebrew
expect_rc mac-brew 3
expect_event "curl:$URL_HOMEBREW"
expect_no_event TRIPWIRE
expect_line mac-brew "# sha256 $SHA_HOMEBREW verified"
[ "$(sha "$CASE_HOME/$HOMEBREW_SCRATCH_REL")" = "$SHA_HOMEBREW" ] || fail 'homebrew installer not staged'
# sudo -v, then one line that runs the installer only while its digest holds
# (a FAILED check must not fall through to the run), then sudo -k.
grep -n -e '| shasum -a 256 -c --status - && ' -e '^sudo -[vk]$' -e '/bin/bash ' \
    "$TEST_TMP/mac-brew.out" | cut -d: -f2- >"$TEST_TMP/mac-brew.order"
printf '%s\n' 'sudo -v' "$MAC_GATE" 'sudo -k' | cmp -s - "$TEST_TMP/mac-brew.order" ||
    fail "Homebrew block: sudo -v, the digest-gated run, then sudo -k: $(cat "$TEST_TMP/mac-brew.order")"
# gate_runs NAME LINE: run a gated block line; the fixture installer it
# guards records a TRIPWIRE event and exits 99 when it runs.
gate_runs() {
    : >"$EVENT_LOG"
    set +e
    EVENT_LOG="$EVENT_LOG" bash -c "$2" >/dev/null 2>&1
    GATE_RC=$?
    set -e
    if [ "$GATE_RC" != 99 ] || ! grep -q 'TRIPWIRE homebrew-install' "$EVENT_LOG"; then
        fail "$1: the digest gate did not run the staged installer (exit $GATE_RC)"
    fi
}
gate_refuses() {
    : >"$EVENT_LOG"
    if EVENT_LOG="$EVENT_LOG" bash -c "$2" >/dev/null 2>&1 || [ -s "$EVENT_LOG" ]; then
        fail "$1: the digest gate ran a tampered installer"
    fi
}
gate_runs mac-gate "$MAC_GATE"
printf '# tampered\n' >>"$CASE_HOME/$HOMEBREW_SCRATCH_REL"
gate_refuses mac-gate-tampered "$MAC_GATE"
rm -f "$CASE_HOME/$HOMEBREW_SCRATCH_REL"

run_case mac-clt "${MAC_ENV[@]}" FAKE_XCODE=0 -- --host mac --check
expect_rc mac-clt 3
expect_line mac-clt 'HUMAN-BEGIN H1-xcode-clt gui'
expect_text mac-clt out 'H1-homebrew human blocked by H1-xcode-clt'
expect_no_text mac-clt out 'HUMAN-BEGIN H1-homebrew'

new_home linuxbrew
run_case linuxbrew BOOTSTRAP_BREW_CANDIDATES="$TEST_TMP/no-brew/brew" -- --host lab-ubuntu --yes --only H1-linuxbrew
expect_rc linuxbrew 3
expect_event "curl:$URL_HOMEBREW"
expect_no_event TRIPWIRE
expect_line linuxbrew 'HUMAN-BEGIN H1-linuxbrew sudo'
expect_line linuxbrew "# sha256 $SHA_HOMEBREW verified"
LINUX_GATE="printf '%s  %s\\n' $SHA_HOMEBREW $CASE_HOME/$HOMEBREW_SCRATCH_REL | sha256sum -c --status - && NONINTERACTIVE=1 /bin/bash $CASE_HOME/$HOMEBREW_SCRATCH_REL"
expect_line linuxbrew "$LINUX_GATE"
expect_line linuxbrew 'sudo -k'
if command -v sha256sum >/dev/null 2>&1; then
    gate_runs linuxbrew-gate "$LINUX_GATE"
    printf '# tampered\n' >>"$CASE_HOME/$HOMEBREW_SCRATCH_REL"
    gate_refuses linuxbrew-gate-tampered "$LINUX_GATE"
fi

# --- --list and --print-manual -----------------------------------------------

new_home manual
run_case list -- --host lab-ubuntu --list
expect_rc list 0
expect_line list "id${TAB}kind${TAB}tier${TAB}blocking"
expect_line list "H1-apt-core${TAB}sudo${TAB}-${TAB}yes"
expect_line list "S6-kitty${TAB}auto${TAB}desktop${TAB}-"
expect_no_text list out 'S2-micromamba'

snapshot >"$TEST_TMP/before"
run_case manual -- --host lab-ubuntu --print-manual
expect_rc manual 0
expect_line manual 'sudo apt-get install -y --no-install-recommends zsh git curl xclip'
expect_line manual 'HUMAN-BEGIN H1-linuxbrew sudo'
expect_line manual "printf '%s  %s\\n' $SHA_HOMEBREW $CASE_HOME/$HOMEBREW_SCRATCH_REL | sha256sum -c --status - && NONINTERACTIVE=1 /bin/bash $CASE_HOME/$HOMEBREW_SCRATCH_REL"
expect_line manual 'HUMAN-BEGIN X-recovery judgment'
expect_line manual 'HUMAN-BEGIN S2-brew-bundle judgment'
expect_line manual 'HUMAN-BEGIN S4-nvm judgment'
expect_line manual "$CASE_BREW/bin/brew uninstall --formula tldr"
expect_line manual "$CASE_BREW/bin/brew uninstall --formula tealdeer"
expect_line manual 'HUMAN-BEGIN H7-stow judgment'
expect_line manual "PATH=\"$CASE_BREW/bin:\$PATH\" $FIXTURE/stow-all.sh lab-ubuntu"
expect_line manual 'HUMAN-BEGIN H7-doctor judgment'
[ "$(grep -c '^HUMAN-BEGIN ' "$TEST_TMP/manual.out")" = "$(grep -c '^HUMAN-END$' "$TEST_TMP/manual.out")" ] ||
    fail 'unbalanced HUMAN blocks'
expect_no_events manual
snapshot >"$TEST_TMP/after"
cmp -s "$TEST_TMP/before" "$TEST_TMP/after" || fail '--print-manual wrote files'

# --- PATH before the first stow ----------------------------------------------

# path_case PROFILE: this process's PATH after steps_extend_path, starting
# from /usr/bin:/bin, with Homebrew, ~/.local/bin and the login env present.
path_case() {
    env -i HOME="$CASE_HOME" PATH=/usr/bin:/bin BOOTSTRAP_BREW_CANDIDATES="$CASE_BREW/bin/brew" \
        STEPS_PROFILE="$1" /bin/bash -c \
        'for lib in manifest platform steps steps-common; do . "$0/$lib.sh"; done
        steps_extend_path
        printf "%s\n" "$PATH"' "$FIXTURE/lib/bootstrap"
}
new_home path
mkdir -p "$CASE_BREW/sbin" "$CASE_HOME/.local/bin" "$CASE_HOME/micromamba/envs/login/bin"
# The stowed shells' order: ~/.local/bin before Homebrew; on hpc the login
# env before both.
PATH_DEBIAN=$(path_case debian)
[ "$PATH_DEBIAN" = "$CASE_HOME/.local/bin:$CASE_BREW/bin:$CASE_BREW/sbin:/usr/bin:/bin" ] ||
    fail "debian PATH before stow: $PATH_DEBIAN"
PATH_HPC=$(path_case hpc)
[ "$PATH_HPC" = "$CASE_HOME/micromamba/envs/login/bin:$CASE_HOME/.local/bin:$CASE_BREW/bin:$CASE_BREW/sbin:/usr/bin:/bin" ] ||
    fail "hpc PATH before stow: $PATH_HPC"

# The H7-stow prefix without a Homebrew yet: each profile's default prefix,
# and a found brew outside the plain path characters stays quoted.
stow_line() {
    awk -v tail=" $FIXTURE/stow-all.sh $2" 'substr($0, length($0) - length(tail) + 1) == tail' "$TEST_TMP/$1.out"
}
run_case stow-arm "${MAC_ENV[@]}" -- --host mac --print-manual
[ "$(stow_line stow-arm mac)" = "PATH=\"/opt/homebrew/bin:\$PATH\" $FIXTURE/stow-all.sh mac" ] ||
    fail "Apple Silicon stow line: $(stow_line stow-arm mac)"
run_case stow-intel "${MAC_ENV[@]}" BOOTSTRAP_UNAME_M=x86_64 -- --host mac --print-manual
[ "$(stow_line stow-intel mac)" = "PATH=\"/usr/local/bin:\$PATH\" $FIXTURE/stow-all.sh mac" ] ||
    fail "Intel macOS stow line: $(stow_line stow-intel mac)"
run_case stow-linux BOOTSTRAP_BREW_CANDIDATES="$TEST_TMP/no-brew/brew" -- --host wsl-ubuntu --print-manual
[ "$(stow_line stow-linux wsl-ubuntu)" = "PATH=\"/home/linuxbrew/.linuxbrew/bin:\$PATH\" $FIXTURE/stow-all.sh wsl-ubuntu" ] ||
    fail "Linuxbrew stow line: $(stow_line stow-linux wsl-ubuntu)"
mkdir -p "$TEST_TMP/odd brew/bin"
cp "$TEST_TMP/brew-stub" "$TEST_TMP/odd brew/bin/brew"
run_case stow-odd BOOTSTRAP_BREW_CANDIDATES="$TEST_TMP/odd brew/bin/brew" -- --host lab-ubuntu --print-manual
[ "$(stow_line stow-odd lab-ubuntu)" = "PATH=$(printf '%q' "$TEST_TMP/odd brew/bin"):\"\$PATH\" $FIXTURE/stow-all.sh lab-ubuntu" ] ||
    fail "quoted stow prefix: $(stow_line stow-odd lab-ubuntu)"

# --- HUMAN block lines stand alone -------------------------------------------

# block_violations FILE: print every HUMAN block line of FILE that is neither
# a '# ' note nor a self-contained command. A command may not change shell
# state (cd, export, ...), may not use a $NAME that another line of the
# block assigns, and never runs gh auth setup-git. An agent runs each line
# as its own command, with no shell state kept in between.
block_violations() {
    awk '
        function finish(i, j, k, count, names, pattern) {
            for (j = 1; j <= n; j++) {
                if (!(j in assigned)) continue
                count = split(assigned[j], names, " ")
                for (k = 1; k <= count; k++) {
                    pattern = "[$][{]?" names[k] "([^A-Za-z0-9_]|$)"
                    for (i = 1; i <= n; i++)
                        if (i != j && lines[i] !~ /^#/ && lines[i] ~ pattern)
                            print id ": uses $" names[k] " from another line: " lines[i]
                }
            }
        }
        /^HUMAN-BEGIN / { inside = 1; id = $2; n = 0; split("", lines); split("", assigned); next }
        /^HUMAN-END$/ { finish(); inside = 0; next }
        !inside { next }
        {
            lines[++n] = $0
            if ($0 ~ /^#/) {
                if ($0 !~ /^# /) print id ": a note needs \"# \": " $0
                next
            }
            if ($0 ~ /^[[:space:]]*$/) print id ": empty line"
            if ($0 ~ /^(cd|pushd|popd|export|unset|set|source|alias|read|declare|typeset|local)([[:space:]]|$)/ || $0 ~ /^[.][[:space:]]/)
                print id ": changes shell state: " $0
            if ($0 ~ /setup-git/) print id ": runs gh auth setup-git: " $0
            rest = $0
            while (match(rest, /^[A-Za-z_][A-Za-z0-9_]*=/)) {
                assigned[n] = assigned[n] " " substr(rest, 1, RLENGTH - 1)
                rest = substr(rest, RLENGTH + 1)
                sub(/^[^[:space:]]*[[:space:]]*/, "", rest)
            }
        }
        END { if (inside) print id ": no HUMAN-END" }
    ' "$1"
}

# The scan finds the carried state it is meant to catch.
cat >"$TEST_TMP/carried.out" <<'EOF'
HUMAN-BEGIN H1-example sudo
#no space
download=$(mktemp)
curl -o "$download" https://example.invalid/key
cd /tmp
gh auth setup-git
NONINTERACTIVE=1 /bin/bash /tmp/install.sh
HUMAN-END
EOF
VIOLATIONS=$(block_violations "$TEST_TMP/carried.out")
for text in 'a note needs' 'uses $download from another line' 'changes shell state: cd /tmp' 'runs gh auth setup-git'; do
    case $VIOLATIONS in
        *"$text"*) ;;
        *) fail "the block scan misses [$text]: $VIOLATIONS" ;;
    esac
done
[ "$(printf '%s\n' "$VIOLATIONS" | grep -c .)" = 4 ] || fail "the block scan flags a self-contained line: $VIOLATIONS"

# Every block of every host, as --print-manual lists them and as the
# apply and check runs above printed them.
run_case manual-mac "${MAC_ENV[@]}" -- --host mac --print-manual
for host in wsl-ubuntu sherlock marlowe; do
    run_case "manual-$host" -- --host "$host" --print-manual
done
for name in manual manual-mac manual-wsl-ubuntu manual-sherlock manual-marlowe \
    check-missing check-fresh apply recovery hpc-login hpc-alloc mac-check mac-brew linuxbrew stow-conflicts \
    brew-conflict-check brew-conflict-cellar nvm-foreign-check nvm-plain nvm-dirty; do
    grep -q '^HUMAN-BEGIN ' "$TEST_TMP/$name.out" || fail "$name printed no HUMAN block to scan"
    VIOLATIONS=$(block_violations "$TEST_TMP/$name.out")
    [ -z "$VIOLATIONS" ] || fail "$name: HUMAN block lines that do not stand alone: $VIOLATIONS"
done

# --- no temporary files ------------------------------------------------------

# --check, --list and --print-manual create no file in TMPDIR, not even one
# they remove again: TMPDIR is an empty directory with an old mtime, which
# any file created or unlinked there would update. That catches mktemp and
# the here-document files of Bash 4 and later; Bash 3.2 puts its own in
# P_tmpdir whatever TMPDIR says, so bootstrap-manifest.sh scans these
# scripts for here-documents as well.
NO_TMP="$TEST_TMP/no-tmp"
NO_TMP_REF="$TEST_TMP/no-tmp.ref"
mkdir "$NO_TMP"
# no_tmp_case NAME RC [VAR=VALUE...] -- ARGS...: run_case, its exit code, an
# untouched TMPDIR.
no_tmp_case() {
    local name=$1 rc=$2
    shift 2
    touch -t 200001010000 "$NO_TMP" "$NO_TMP_REF"
    run_case "$name" TMPDIR="$NO_TMP" "$@"
    expect_rc "$name" "$rc"
    [ -z "$(ls -A "$NO_TMP")" ] || fail "$name left files in TMPDIR: $(ls -A "$NO_TMP")"
    [ -z "$(find "$NO_TMP" -maxdepth 0 -newer "$NO_TMP_REF" -print)" ] ||
        fail "$name created and removed a file in TMPDIR"
}
new_home no-tmp
no_tmp_case no-tmp-check 3 -- --host lab-ubuntu --check --tier all
expect_text no-tmp-check out 'S3-clones todo'
no_tmp_case no-tmp-check-missing 3 FAKE_DPKG_INSTALLED="$DPKG_PARTIAL" -- --host lab-ubuntu --check
expect_line no-tmp-check-missing 'HUMAN-BEGIN H1-apt-core sudo'
no_tmp_case no-tmp-list 0 -- --host lab-ubuntu --list
no_tmp_case no-tmp-manual 0 -- --host lab-ubuntu --print-manual
no_tmp_case no-tmp-mac 3 "${MAC_ENV[@]}" -- --host mac --check
no_tmp_case no-tmp-hpc 3 "${HPC_ENV[@]}" -- --host sherlock --check
no_tmp_case no-tmp-help 0 -- --help
no_tmp_case no-tmp-usage 2 -- --host lab-ubuntu --check --tier core,gui

# --- bootstrap_fetch ---------------------------------------------------------

# fetch_case NAME BIN_DIR ARGS...: run bootstrap_fetch with PATH=BIN_DIR.
fetch_case() {
    local name=$1 bin=$2
    shift 2
    : >"$EVENT_LOG"
    set +e
    env -i HOME="$TEST_TMP" PATH="$bin" LC_ALL=C EVENT_LOG="$EVENT_LOG" URL_MAP="$URL_MAP" \
        CURL_ARGS_LOG="$CURL_ARGS_LOG" /bin/bash -c \
        '. "$1"; shift; bootstrap_fetch "$@"' fetch "$FIXTURE/lib/bootstrap/fetch.sh" "$@" \
        >"$TEST_TMP/$name.out" 2>"$TEST_TMP/$name.err"
    CASE_RC=$?
    set -e
}

# link_tools DIR TOOL...: a PATH dir holding only these tools.
link_tools() {
    local dir=$1 tool
    shift
    mkdir -p "$dir"
    for tool in "$@"; do
        if [ -x "$FAKE_BIN/$tool" ]; then
            ln -s "$FAKE_BIN/$tool" "$dir/$tool"
        else
            ln -s "$(command -v "$tool")" "$dir/$tool"
        fi
    done
}

FETCH_DIR="$TEST_TMP/fetch"
CURL_ONLY="$TEST_TMP/bin-curl"
WGET_ONLY="$TEST_TMP/bin-wget"
# The curl run checks the shasum fallback; the wget run uses either tool.
link_tools "$CURL_ONLY" curl shasum awk cp mkdir rm mv dirname
link_tools "$WGET_ONLY" wget "$SHA_TOOL" awk cp mkdir rm mv dirname

: >"$CURL_ARGS_LOG"
fetch_case fetch-ok "$CURL_ONLY" "$URL_MICROMAMBA" "$FETCH_DIR/ok/micromamba" "$SHA_MICROMAMBA"
expect_rc fetch-ok 0
cmp -s "$FIXTURES/artifacts/micromamba" "$FETCH_DIR/ok/micromamba" || fail 'fetch with shasum'
[ ! -e "$FETCH_DIR/ok/micromamba.part" ] || fail 'fetch left a .part file'
grep -Fq -- "-fsSL --proto =https --tlsv1.2 --retry 3 -o $FETCH_DIR/ok/micromamba.part $URL_MICROMAMBA" \
    "$CURL_ARGS_LOG" || fail "curl flags: $(cat "$CURL_ARGS_LOG")"

fetch_case fetch-wget "$WGET_ONLY" "$URL_MICROMAMBA" "$FETCH_DIR/wget/micromamba" "$SHA_MICROMAMBA"
expect_rc fetch-wget 0
expect_event "wget:$URL_MICROMAMBA"
cmp -s "$FIXTURES/artifacts/micromamba" "$FETCH_DIR/wget/micromamba" || fail 'fetch with wget'

mkdir -p "$FETCH_DIR/keep"
printf 'previous\n' >"$FETCH_DIR/keep/micromamba"
fetch_case fetch-bad "$CURL_ONLY" "$URL_MICROMAMBA" "$FETCH_DIR/keep/micromamba" "$SHA_MICROMAMBA_BAD"
expect_rc fetch-bad 1
expect_text fetch-bad err "expected $SHA_MICROMAMBA_BAD, actual $SHA_MICROMAMBA"
[ ! -e "$FETCH_DIR/keep/micromamba.part" ] || fail 'mismatch left a .part file'
[ "$(cat "$FETCH_DIR/keep/micromamba")" = previous ] || fail 'mismatch replaced DEST'

fetch_case fetch-unpinned "$CURL_ONLY" "$URL_CLAUDE" "$FETCH_DIR/claude" -
expect_rc fetch-unpinned 2
expect_text fetch-unpinned err 'without --inspect'
expect_no_events fetch-unpinned

fetch_case fetch-inspect "$CURL_ONLY" --inspect "$URL_CLAUDE" "$FETCH_DIR/claude" -
expect_rc fetch-inspect 0
cmp -s "$FIXTURES/artifacts/claude-install" "$FETCH_DIR/claude" || fail 'fetch --inspect'

# wget follows a redirect to http, and nothing pins an inspect download, so
# --inspect needs curl; it writes nothing without it.
fetch_case fetch-inspect-wget "$WGET_ONLY" --inspect "$URL_CLAUDE" "$FETCH_DIR/inspect-wget/claude" -
expect_rc fetch-inspect-wget 1
expect_text fetch-inspect-wget err 'an unpinned download needs curl'
expect_no_events fetch-inspect-wget
[ ! -e "$FETCH_DIR/inspect-wget" ] || fail 'fetch --inspect without curl wrote files'

fetch_case fetch-http "$CURL_ONLY" http://example.invalid/x "$FETCH_DIR/http" "$SHA_MICROMAMBA"
expect_rc fetch-http 2
expect_no_events fetch-http

echo "setup-host=PASS"
