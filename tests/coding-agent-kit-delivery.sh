#!/bin/bash

# shellcheck disable=SC2088 # messages and help texts spell ~ literally
set -euo pipefail

# Hermetic: the provisioning exports (DOTFILES_AUTO_UPDATE=0 and the like,
# docs/bootstrap.md) and other dotfiles knobs never reach the code under
# test from the caller; each case sets what it needs.
unset DOTFILES_AUTO_UPDATE DOTFILES_AUTO_STOW DOTFILES_HOST DOTFILES_DIR _DOTFILES_CHECKED \
    DOTFILES_STOW_WITHOUT_OH_MY_ZSH DOTFILES_COLOR AWESOME_SKILLS_AUTO_UPDATE AWESOME_SKILLS_FORCE \
    AWESOME_SKILLS_BG AWESOME_SKILLS_INSTALLER_URL AWESOME_SKILLS_REFRESH_DAYS _AWESOME_SKILLS_CHECKED \
    CODING_AGENT_KIT_CONFIG CODING_AGENT_KIT_COLOR

# How the coding-agent-kit submodule delivers the Codex and Claude launchers,
# libraries, completions and Claude helpers (docs/coding-agent-kit.md). The
# structure checks always run, with git, bash and coreutils only: the
# .gitmodules entry, the .stowrc ignore line, the gitlink, every link's exact
# relative text from the link map, the doctor's sentinels, the sync launchers
# that stay in dotfiles as regular files, the Windows allowlist and the bump
# workflow. With the submodule initialized, check_real proves that every link
# resolves to the kit file the map names, tracked with its mode at the
# gitlink, and that the kit carries what dotfiles relies on; the docs path
# that --help prints must be a file of the kit. The real stow-all.sh then
# stows copies into temporary homes with the checkout full, emptied and
# restored. --real requires the submodule at the gitlink the index records and
# stops after those checks (the bump Action's guard). --ci turns every SKIP
# into a failure.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

require_all=0
real=0
for argument in "$@"; do
    case "$argument" in
        --ci) require_all=1 ;;
        --real) real=1 ;;
        --help)
            printf 'Usage: %s [--ci] [--real]\n' "$0"
            printf 'Without --real, copies of the checkout are stowed into temporary homes.\n'
            printf '%s\n' '--real checks the initialized submodule at the recorded gitlink; --ci fails instead of skipping.'
            exit 0
            ;;
        *)
            printf 'ERROR: unknown test option: %s\n' "$argument" >&2
            exit 2
            ;;
    esac
done

SUBMODULE=common/codex/coding-agent-kit
SUBMODULE_URL=https://github.com/FridrichMethod/coding-agent-kit.git
STOWRC_LINE='--ignore=^coding-agent-kit(/|$)'
WINDOWS_PACKAGES="\$CommonPackages = @('claude', 'codex', 'conda', 'git', 'pymol', 'ssh', 'wezterm')"
WARNING='[dotfiles] [warn] coding-agent-kit links dangle; codex-as, claude-as and the Claude helpers are unavailable until the submodule is checked out (git submodule update --init --recursive)'
# The link map: each of the 14 package files that are links into the
# submodule, and the kit file it points at. The package paths, and so the
# home paths Stow links, stay put whatever the kit's layout; a kit that moves
# a file changes only the text of its link here.
LINK_MAP='common/claude/.claude/dotfiles/check-git-hooks.cjs helpers/check-git-hooks.cjs
common/claude/.claude/dotfiles/notify.cjs helpers/notify.cjs
common/claude/.claude/dotfiles/statusline.cjs helpers/statusline.cjs
common/claude/.local/bin/claude-as bin/claude-as
common/claude/.local/lib/claude-as/launch.py lib/claude-as/launch.py
common/claude/.local/share/bash-completion/completions/claude-as completions/bash/claude-as
common/claude/.oh-my-zsh/custom/completions/_claude-as completions/zsh/_claude-as
common/codex/.local/bin/codex-as bin/codex-as
common/codex/.local/lib/codex-as/check.py lib/codex-as/check.py
common/codex/.local/lib/codex-as/handoff.py lib/codex-as/handoff.py
common/codex/.local/lib/codex-as/launch.py lib/codex-as/launch.py
common/codex/.local/lib/codex-as/layout.py lib/codex-as/layout.py
common/codex/.local/share/bash-completion/completions/codex-as completions/bash/codex-as
common/codex/.oh-my-zsh/custom/completions/_codex-as completions/zsh/_codex-as'
# The two kit executables among them.
EXECUTABLES='bin/claude-as bin/codex-as'
# The sync launchers stay in dotfiles as regular files.
LAUNCHERS='common/claude/.local/bin/claude-settings-sync common/codex/.local/bin/codex-config-sync
common/codex/.local/bin/codex-rules-sync common/codex/.local/bin/codex-instructions-sync'
# The kit test and fixture that dotfiles' real-data overlay runs with the real
# settings.json in place of the fixture (tests/ai-integration.sh, tests/run.ps1).
FIXTURES='tests/claude-customizations.cjs tests/fixtures/claude-settings.json'
# Patterns the kit's own .gitignore must hold. Superproject ignores do not
# apply inside a submodule, and what a host's file manager, editor, Python or
# a test virtual environment leaves in the checkout would otherwise make it
# dirty, which stops the login updater on that host.
KIT_GITIGNORE='.DS_Store
._*
Thumbs.db
Desktop.ini
*~
*.swp
__pycache__/
*.py[cod]
.venv*/'

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

skip() {
    if [[ "$require_all" == 1 ]]; then
        fail "CI requires $1"
    fi
    printf 'SKIP: %s\n' "$1"
}

# expect_grep TEXT FILE: FILE contains TEXT; expect_line: as a whole line.
expect_grep() {
    grep -Fq -- "$1" "$2" || fail "expected '$1' in $2"
}
expect_line() {
    grep -Fxq -- "$1" "$2" || fail "expected the line '$1' in $2"
}

# A pre-commit run exports the GIT_DIR and GIT_INDEX_FILE of the commit in
# progress; git in a temporary repository must not see them.
unset_git_env() {
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
        GIT_ALTERNATE_OBJECT_DIRECTORIES
}

# The submodule's own repository and index, never an inherited commit index.
checkout_git() {
    (
        unset_git_env
        git -C "$checkout" "$@"
    )
}

# A commit hook exports the superproject's GIT_INDEX_FILE (relative in the
# main worktree); check_real must still read the submodule's own index.
check_hook_index() {
    (
        cd -- "$REPO_ROOT"
        GIT_INDEX_FILE=$(git rev-parse --git-path index)
        export GIT_INDEX_FILE
        check_real "$REPO_ROOT" >/dev/null
    )
}

fixture_git() {
    (
        unset_git_env
        export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
        git -c user.name=fixture -c user.email=fixture@example.invalid "$@"
    )
}

# link_text PATH KIT_PATH: the text of the link at common/PACKAGE/REST to the
# kit file KIT_PATH. It climbs one level more than REST has directories, to
# common/, and enters the submodule there: ../codex/coding-agent-kit/KIT_PATH
# for a top-level REST.
link_text() {
    local rest=${1#common/*/} text=../
    while [[ "$rest" == */* ]]; do
        text=../$text
        rest=${rest#*/}
    done
    printf '%scodex/coding-agent-kit/%s\n' "$text" "$2"
}

# kit_paths: the kit side of the link map, one path per line.
kit_paths() {
    local path kit
    while read -r path kit; do
        printf '%s\n' "$kit"
    done <<<"$LINK_MAP"
}

# kit_entry REVISION PATH: "MODE TYPE" of PATH in the kit commit REVISION,
# empty when it does not track PATH.
kit_entry() {
    checkout_git ls-tree "$1" -- "$2" | awk '{ print $1, $2 }'
}

# launcher_help HOME LAUNCHER: LAUNCHER --help in HOME, without the caller's
# XDG_CONFIG_HOME, so no real coding-agent-kit configuration is in reach.
launcher_help() {
    env -u XDG_CONFIG_HOME HOME="$1" "$2" --help
}

check_gitmodules() {
    local expected actual
    expected=$(printf '%s\n' \
        "submodule.$SUBMODULE.path $SUBMODULE" \
        "submodule.$SUBMODULE.url $SUBMODULE_URL" \
        "submodule.$SUBMODULE.branch main")
    actual=$(git -C "$REPO_ROOT" config -f .gitmodules --get-regexp '^submodule\.common/codex/coding-agent-kit\.') ||
        fail ".gitmodules has no $SUBMODULE entry"
    [[ "$actual" == "$expected" ]] ||
        fail ".gitmodules entry for $SUBMODULE is not exactly path, url $SUBMODULE_URL and branch main: $actual"
}

# The checkout sits inside the codex package; this one line keeps Stow and
# stow-all.ps1 from linking it, without replacing Stow's built-in ignores.
check_stowrc() {
    expect_line "$STOWRC_LINE" "$REPO_ROOT/.stowrc"
}

# index_links: every tracked symlink under common/claude, common/codex and
# docs as "PATH -> TEXT".
index_links() {
    local mode sha path pattern='^(common/claude|common/codex|docs)/'
    git -C "$REPO_ROOT" ls-files -s | while read -r mode sha _ path; do
        [[ "$mode" == 120000 && "$path" =~ $pattern ]] || continue
        printf '%s -> %s\n' "$path" "$(git -C "$REPO_ROOT" cat-file blob "$sha")"
    done | LC_ALL=C sort
}

# index_mode PATH: the index mode of PATH, empty when it is not tracked.
index_mode() {
    git -C "$REPO_ROOT" ls-files -s -- "$1" | cut -d' ' -f1
}

# The index holds the gitlink, exactly the 14 links of the map with their
# computed texts, and the sync launchers as regular files; no package path
# besides the gitlink names coding-agent-kit, which .stowrc would hide.
check_index() {
    local actual expected path kit text rest
    [[ "$(index_mode "$SUBMODULE")" == 160000 ]] || fail "$SUBMODULE is not a gitlink (mode 160000)"
    actual=$(index_links)
    expected=$(while read -r path kit; do
        printf '%s -> %s\n' "$path" "$(link_text "$path" "$kit")"
    done <<<"$LINK_MAP" | LC_ALL=C sort)
    if [[ "$actual" != "$expected" ]]; then
        diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true
        fail 'the tracked links under common/claude, common/codex and docs differ from the link map'
    fi
    while read -r path kit; do
        text=$(link_text "$path" "$kit")
        [[ -L "$REPO_ROOT/$path" ]] || fail "$path is not a symlink in the checkout"
        [[ "$(readlink "$REPO_ROOT/$path")" == "$text" ]] ||
            fail "$path links to $(readlink "$REPO_ROOT/$path"), expected $text"
    done <<<"$LINK_MAP"
    for path in $LAUNCHERS; do
        [[ "$(index_mode "$path")" == 100755 ]] || fail "$path is not tracked as a 100755 regular file"
        [[ -f "$REPO_ROOT/$path" && ! -L "$REPO_ROOT/$path" ]] || fail "$path is not a regular file in the checkout"
    done
    # stow-all.sh takes any top-level directory as a host: HOST/PACKAGE/REST.
    while IFS= read -r path; do
        [[ "$path" != "$SUBMODULE" && "$path" != .* && "$path" == */*/* ]] || continue
        rest=${path#*/*/}
        case $rest in
            coding-agent-kit* | */coding-agent-kit)
                fail "$path: its package path $rest is hidden by the .stowrc ignore or names the submodule"
                ;;
        esac
    done < <(git -C "$REPO_ROOT" ls-files)
}

# The doctor judges a checked-out kit by sentinel files (lib/bootstrap/checks.sh);
# every one it names must be a kit file of the link map, so a kit layout change
# cannot leave the doctor checking paths the kit no longer has.
check_sentinels() {
    local line sentinel kit
    line=$(grep -m 1 "^$SUBMODULE " "$REPO_ROOT/lib/bootstrap/checks.sh") ||
        fail "lib/bootstrap/checks.sh names no sentinel files for $SUBMODULE"
    line=${line#"$SUBMODULE "}
    line=${line%"'"}
    [[ -n "$line" ]] || fail "lib/bootstrap/checks.sh names no sentinel files for $SUBMODULE"
    kit=$(kit_paths)
    for sentinel in $line; do
        grep -Fxq -- "$sentinel" <<<"$kit" ||
            fail "lib/bootstrap/checks.sh checks $SUBMODULE/$sentinel, which no package link points at"
    done
}

# check_help_paths: codex-as --help and claude-as --help, run through their
# package links with an empty temporary home, name a docs file of the kit as
# tracked at the recorded gitlink (the launchers print it below the kit root
# they resolve, or a URL when they cannot), and codex-as still names
# concurrent accounts.
check_help_paths() {
    local checkout=$REPO_ROOT/$SUBMODULE launcher output docs recorded physical home=$TEST_TMP/help-home
    recorded=$(git -C "$REPO_ROOT" ls-files -s -- "$SUBMODULE" | cut -d' ' -f2)
    physical=$(cd -P -- "$checkout" && pwd -P)
    mkdir -p "$home"
    for launcher in common/codex/.local/bin/codex-as common/claude/.local/bin/claude-as; do
        output=$(launcher_help "$home" "$REPO_ROOT/$launcher") || fail "$launcher --help failed"
        docs=$(sed -n 's/^Details and manual repair: //p' <<<"$output")
        [[ "$docs" == "$physical"/* && -f "$docs" ]] ||
            fail "$launcher --help names '$docs', not a file of the $SUBMODULE checkout"
        [[ "$(kit_entry "$recorded" "${docs#"$physical"/}")" == '100644 blob' ]] ||
            fail "$launcher --help names $docs, which coding-agent-kit $recorded does not track as 100644"
        case $launcher in
            */codex-as) grep -Fq 'Concurrent accounts' <<<"$output" || fail "$launcher --help no longer names concurrent accounts" ;;
        esac
    done
    [[ -z "$(ls -A "$home")" ]] || fail "--help wrote into its home: $(ls -A "$home")"
}

# Windows links each common package file by file and must not gain or lose a
# package through the submodule.
check_windows() {
    expect_line "$WINDOWS_PACKAGES" "$REPO_ROOT/stow-all.ps1"
}

# line_of TEXT FILE: the number of the first line of FILE holding TEXT, or
# empty.
line_of() {
    grep -m 1 -n -F -- "$1" "$2" | cut -d: -f1 || true
}

# A bump changes code that runs in every Codex and Claude session at the next
# login, so the Action runs only by hand, stages the bump, refuses it unless
# delivery and the target commit's own CI both hold, and pushes only a review
# branch, never main.
check_automation() {
    local workflow=$REPO_ROOT/.github/workflows/update-coding-agent-kit-submodule.yml triggers stage guard ci commit push
    [[ -f "$workflow" ]] || fail "missing ${workflow#"$REPO_ROOT"/}"
    triggers=$(sed -n '/^on:/,/^[^[:space:]#]/{/^  [^[:space:]#]/p;}' "$workflow")
    [[ "$triggers" == '  workflow_dispatch:' ]] ||
        fail "the coding-agent-kit bump must run on workflow_dispatch only: $triggers"
    ! grep -Eq '^[[:space:]]*schedule:' "$workflow" || fail 'the coding-agent-kit bump must not run on a schedule'
    expect_line "          git submodule update --remote --merge -- $SUBMODULE" "$workflow"
    stage=$(line_of "git add $SUBMODULE" "$workflow")
    guard=$(line_of 'bash tests/coding-agent-kit-delivery.sh --real' "$workflow")
    ci=$(line_of 'repos/FridrichMethod/coding-agent-kit/commits/$SHA/check-runs' "$workflow")
    commit=$(line_of 'git commit -m "chore(deps): update coding-agent-kit submodule to latest"' "$workflow")
    push=$(line_of 'git push origin "HEAD:refs/heads/$branch"' "$workflow")
    [[ -n "$stage" && -n "$guard" && "$stage" -lt "$guard" ]] ||
        fail 'the Action must stage its bump before --real checks the recorded gitlink'
    [[ -n "$ci" && "$guard" -lt "$ci" ]] ||
        fail 'the Action must require the check runs of the target commit after --real'
    [[ -n "$commit" && "$ci" -lt "$commit" ]] ||
        fail 'the Action must commit "chore(deps): update coding-agent-kit submodule to latest" after its guards'
    [[ -n "$push" && "$commit" -lt "$push" ]] || fail 'the Action must push HEAD:refs/heads/$branch after committing'
    expect_grep 'branch="bump/coding-agent-kit-' "$workflow"
    [[ "$(grep -c 'git push' "$workflow")" == 1 ]] || fail 'the Action may push only its review branch'
    ! grep -Eq 'git push.*main|refs/heads/main' "$workflow" || fail 'the Action must never push main'
}

# check_real ROOT: the submodule of ROOT is checked out at the gitlink the
# index records, every link resolves to a regular file at its kit path of the
# map, which that commit tracks with its mode, and the kit carries the
# overlay files, .gitattributes line and .gitignore patterns dotfiles relies
# on. An uninitialized submodule or an unstaged bump fails instead of passing;
# the bump Action stages its bump first.
check_real() {
    local root=$1 checkout=$1/$SUBMODULE physical path kit text revision recorded mode content pattern
    [[ -e "$checkout/.git" ]] ||
        fail "coding-agent-kit submodule not initialized at $SUBMODULE; run git submodule update --init --recursive"
    revision=$(checkout_git rev-parse HEAD)
    recorded=$(git -C "$root" ls-files -s -- "$SUBMODULE" | cut -d' ' -f2)
    [[ "$revision" == "$recorded" ]] ||
        fail "coding-agent-kit is checked out at $revision, which is not the recorded gitlink $recorded; stage the bump (git add $SUBMODULE) or check out the recorded commit (git submodule update)"
    physical=$(cd -P -- "$checkout" && pwd -P)
    while read -r path kit; do
        text=$(readlink "$root/$path")
        [[ "$(cd -P -- "$(dirname -- "$root/$path")/$(dirname -- "$text")" 2>/dev/null && pwd -P)/${text##*/}" == "$physical/$kit" ]] ||
            fail "$path -> $text does not point at $SUBMODULE/$kit"
        [[ -f "$physical/$kit" && ! -L "$physical/$kit" ]] ||
            fail "$path -> $text dangles with coding-agent-kit $revision"
        mode=100644
        case " $EXECUTABLES " in *" $kit "*) mode=100755 ;; esac
        [[ "$(kit_entry "$recorded" "$kit")" == "$mode blob" ]] ||
            fail "coding-agent-kit $revision does not track $kit as $mode"
        [[ "$mode" == 100644 || -x "$root/$path" ]] || fail "$path is not executable through its link"
    done <<<"$LINK_MAP"
    [[ -z "$(checkout_git ls-tree -r "$recorded" | awk '$1 == 120000')" ]] ||
        fail "coding-agent-kit $revision tracks a symlink"
    for path in $FIXTURES; do
        [[ "$(kit_entry "$recorded" "$path")" == '100644 blob' ]] ||
            fail "coding-agent-kit $revision lacks $path, which the real-data overlay uses"
    done
    content=$(checkout_git show "$recorded:.gitattributes") || fail "coding-agent-kit $revision has no .gitattributes"
    grep -Fxq -- '* text=auto eol=lf' <<<"$content" ||
        fail "coding-agent-kit $revision lacks the .gitattributes line '* text=auto eol=lf'"
    content=$(checkout_git show "$recorded:.gitignore") || fail "coding-agent-kit $revision has no .gitignore"
    while IFS= read -r pattern; do
        grep -Fxq -- "$pattern" <<<"$content" ||
            fail "coding-agent-kit $revision lacks the .gitignore pattern '$pattern'"
    done <<<"$KIT_GITIGNORE"
    printf 'coding-agent-kit-delivery: real submodule %s resolves every delivered link\n' "$revision"
}

TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-coding-agent-kit-delivery.XXXXXX")"
# macOS TMPDIR ends in '/', and /var may itself be a symlink.
TEST_TMP="$(cd -- "$TEST_TMP" && pwd -P)"
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM

check_gitmodules
check_stowrc
check_index
check_sentinels
check_windows
check_automation

if [[ "$real" == 1 || -e "$REPO_ROOT/$SUBMODULE/.git" ]]; then
    check_real "$REPO_ROOT"
    check_hook_index
    check_help_paths
else
    skip 'an initialized coding-agent-kit submodule for the link, help and stow checks (git submodule update --init --recursive)'
    echo 'coding-agent-kit-delivery=PASS'
    exit 0
fi
if [[ "$real" == 1 ]]; then
    echo 'coding-agent-kit-delivery=PASS'
    exit 0
fi

if ! command -v stow >/dev/null 2>&1; then
    skip 'real GNU Stow for the coding-agent-kit stow behavior (install stow to enable)'
    echo 'coding-agent-kit-delivery=PASS'
    exit 0
fi
SYNC_PYTHON="${DOTFILES_SYNC_PYTHON:-$REPO_ROOT/.venv-sync/bin/python}"
if [[ ! -x "$SYNC_PYTHON" ]]; then
    fail 'AI-sync runtime missing; run ./setup-sync.sh explicitly.'
fi

# make_home HOME: a temporary home holding a checkout subset at ~/dotfiles,
# as on the hosts, with the submodule as a plain tree. Its repository
# excludes that tree, so the status stays clean whether it is full or empty
# and only the dangling-link check can blank the applied HEAD.
make_home() {
    local home=$1
    local checkout=$home/dotfiles
    mkdir -p "$checkout/common" "$checkout/lib" "$home/.oh-my-zsh"
    # The packages carry completions and require the prerequisite OMZ clone.
    printf '%s\n' '# fixture oh-my-zsh entrypoint' >"$home/.oh-my-zsh/oh-my-zsh.sh"
    cp "$REPO_ROOT/stow-all.sh" "$checkout/"
    cp "$REPO_ROOT/lib/config_sync.py" "$REPO_ROOT/lib/sync-runtime.sh" "$REPO_ROOT/lib/terminal.sh" "$checkout/lib/"
    cp -RP "$REPO_ROOT/common/codex" "$REPO_ROOT/common/claude" "$checkout/common/"
    cp -RP "$REPO_ROOT/.stowrc" "$checkout/"
    rm -f "$checkout/$SUBMODULE/.git"
    fixture_git init -q "$checkout"
    printf '/%s/\n' "$SUBMODULE" >>"$checkout/.git/info/exclude"
    fixture_git -C "$checkout" add -A
    fixture_git -C "$checkout" commit -q -m fixture
}

# empty_submodule HOME / restore_submodule HOME: the checkout as after a
# plain clone or local merge, and as after git submodule update.
empty_submodule() {
    rm -rf "${1:?}/dotfiles/$SUBMODULE"
    mkdir "$1/dotfiles/$SUBMODULE"
}
restore_submodule() {
    rm -rf "${1:?}/dotfiles/$SUBMODULE"
    cp -RP "$REPO_ROOT/$SUBMODULE" "$1/dotfiles/$SUBMODULE"
    rm -f "$1/dotfiles/$SUBMODULE/.git"
}

# stow_home CASE HOME: the real stow-all.sh (common-only), hermetic and
# expected to succeed; its output is kept as CASE.stdout and CASE.stderr.
stow_home() {
    local name=$1 home=$2
    if ! (
        unset_git_env
        export HOME="$home" GIT_CEILING_DIRECTORIES="$TEST_TMP" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
            DOTFILES_SYNC_PYTHON="$SYNC_PYTHON" LC_ALL=C
        exec bash "$home/dotfiles/stow-all.sh"
    ) >"$TEST_TMP/$name.stdout" 2>"$TEST_TMP/$name.stderr"; then
        cat "$TEST_TMP/$name.stdout" "$TEST_TMP/$name.stderr" >&2
        fail "stow-all.sh failed in case $name"
    fi
    expect_grep '[dotfiles] [ok] Stow completed (common-only)' "$TEST_TMP/$name.stdout"
}

# home_link PATH: where Stow links the package file PATH in the home.
home_link() {
    printf '%s\n' "${1#common/*/}"
}

# assert_state HOME APPLIED: the recorded state names HOME and, on line 4,
# APPLIED (the checkout's HEAD, or empty for an incomplete install).
assert_state() {
    local state=$1/dotfiles/.git/dotfiles-sync-unix
    [[ "$(sed -n 1p "$state")" == "$1" && "$(wc -l <"$state" | tr -d ' ')" == 4 ]] ||
        fail "unexpected state for $1: $(cat "$state")"
    [[ "$(sed -n 4p "$state")" == "$2" ]] || fail "state line 4 is '$(sed -n 4p "$state")', expected '$2'"
}

# snapshot HOME: every path of the home outside ~/dotfiles, with link texts
# and file checksums.
snapshot() {
    local entry
    (cd -- "$1" && find . -path ./dotfiles -prune -o -print) | LC_ALL=C sort | while IFS= read -r entry; do
        if [[ -L "$1/$entry" ]]; then
            printf 'L %s -> %s\n' "$entry" "$(readlink "$1/$entry")"
        elif [[ -f "$1/$entry" ]]; then
            printf 'F %s %s\n' "$entry" "$(cksum <"$1/$entry")"
        else
            printf 'D %s\n' "$entry"
        fi
    done
}

# An initialized checkout: every delivered file reaches the home through the
# package path (one hop), and from there into the submodule; the checkout
# itself is never linked.
HOME_FULL=$TEST_TMP/full/home
make_home "$HOME_FULL"
stow_home full "$HOME_FULL"
[[ ! -s "$TEST_TMP/full.stderr" ]] || fail "the initialized stow warned: $(cat "$TEST_TMP/full.stderr")"
FULL_PHYSICAL=$(cd -P -- "$HOME_FULL/dotfiles" && pwd -P)
while read -r path _; do
    link=$HOME_FULL/$(home_link "$path")
    text=$(readlink "$link") || fail "~/$(home_link "$path") is not a link"
    [[ "$(cd -P -- "$(dirname -- "$link")/$(dirname -- "$text")" && pwd -P)/${text##*/}" == "$FULL_PHYSICAL/$path" ]] ||
        fail "~/$(home_link "$path") -> $text does not link the package path $path"
    [[ -f "$link" ]] || fail "~/$(home_link "$path") does not resolve"
done <<<"$LINK_MAP"
for name in coding-agent-kit .git; do
    [[ ! -e "$HOME_FULL/$name" && ! -L "$HOME_FULL/$name" ]] || fail "Stow linked the submodule checkout as ~/$name"
done
# Through both links, the launchers find the home's own kit copy and name its
# docs.
for path in .local/bin/codex-as .local/bin/claude-as; do
    docs=$(launcher_help "$HOME_FULL" "$HOME_FULL/$path" | sed -n 's/^Details and manual repair: //p')
    [[ "$docs" == "$FULL_PHYSICAL/$SUBMODULE/"* && -f "$docs" ]] ||
        fail "~/$path --help names '$docs', not a file of the kit copy in $FULL_PHYSICAL"
done
for path in .codex/config.toml .codex/rules/portable.rules .claude/settings.json; do
    [[ -f "$HOME_FULL/$path" && ! -L "$HOME_FULL/$path" ]] || fail "the initialized stow did not write ~/$path"
done
assert_state "$HOME_FULL" "$(fixture_git -C "$HOME_FULL/dotfiles" rev-parse HEAD)"
snapshot "$HOME_FULL" >"$TEST_TMP/full.snapshot"

# An empty checkout: one warning and no applied HEAD, while every AI sync
# still writes its live file and Stow still links all 14 package entries with
# the same text; they dangle until the submodule is checked out.
HOME_EMPTY=$TEST_TMP/empty/home
make_home "$HOME_EMPTY"
empty_submodule "$HOME_EMPTY"
stow_home empty "$HOME_EMPTY"
printf '%s\n' "$WARNING" >"$TEST_TMP/expected-empty.stderr"
if ! cmp -s "$TEST_TMP/expected-empty.stderr" "$TEST_TMP/empty.stderr"; then
    diff -u "$TEST_TMP/expected-empty.stderr" "$TEST_TMP/empty.stderr" >&2 || true
    fail 'an uninitialized submodule must give exactly the one warning'
fi
assert_state "$HOME_EMPTY" ''
for path in .codex/config.toml .codex/rules/portable.rules .claude/settings.json; do
    [[ -f "$HOME_EMPTY/$path" && ! -L "$HOME_EMPTY/$path" ]] || fail "an uninitialized submodule kept the sync from writing ~/$path"
    cmp -s "$HOME_FULL/$path" "$HOME_EMPTY/$path" || fail "~/$path differs from the initialized home"
done
while read -r path _; do
    link=$(home_link "$path")
    [[ -L "$HOME_EMPTY/$link" ]] || fail "~/$link was not stowed while the submodule is empty"
    [[ "$(readlink "$HOME_EMPTY/$link")" == "$(readlink "$HOME_FULL/$link")" ]] ||
        fail "~/$link -> $(readlink "$HOME_EMPTY/$link") differs from the initialized home"
done <<<"$LINK_MAP"
[[ ! -e "$HOME_EMPTY/coding-agent-kit" && ! -L "$HOME_EMPTY/coding-agent-kit" ]] ||
    fail 'Stow linked the empty submodule checkout'

# Once the submodule is checked out, a restow converges to the initialized
# home and records HEAD.
restore_submodule "$HOME_EMPTY"
stow_home restored "$HOME_EMPTY"
[[ ! -s "$TEST_TMP/restored.stderr" ]] || fail "the restored stow warned: $(cat "$TEST_TMP/restored.stderr")"
assert_state "$HOME_EMPTY" "$(fixture_git -C "$HOME_EMPTY/dotfiles" rev-parse HEAD)"
snapshot "$HOME_EMPTY" >"$TEST_TMP/restored.snapshot"
if ! cmp -s "$TEST_TMP/full.snapshot" "$TEST_TMP/restored.snapshot"; then
    diff -u "$TEST_TMP/full.snapshot" "$TEST_TMP/restored.snapshot" >&2 || true
    fail 'the restored home differs from the initialized one'
fi

echo 'coding-agent-kit-delivery=PASS'
