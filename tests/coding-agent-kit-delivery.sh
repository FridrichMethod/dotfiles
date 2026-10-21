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
# .gitmodules entry, the coding-agent-kit package's local ignore file, the
# .stowrc and .gitignore lines that keep a pre-move checkout harmless, the
# gitlink, every link's exact relative text from the link map, the doctor's
# sentinels, the sync launchers that stay in dotfiles as regular files, the
# Windows allowlist and the bump workflow. With the submodule initialized, check_real proves that every link
# resolves to the kit file the map names, tracked with its mode at the
# gitlink, and that the kit carries what dotfiles relies on and reads no knob
# the test entry points leave set; the docs path that --help prints must be a
# file of the kit. Fixture superprojects then show check_real refusing a kit
# commit with a nested submodule, a .gitmodules or an unlisted knob, and the
# real stow-all.sh stows copies into temporary homes with the checkout full,
# emptied and restored, and a home stowed from the pre-move layout converges
# to the same home. --real requires the submodule at the gitlink the index
# records and stops after the real checks (the bump Action's gate 3, before
# --ci). --ci turns every SKIP into a failure. Sourced, as by
# tests/test-entrypoints.sh, it only defines its checks.

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

# The submodule keeps the name of its first path, so every host reuses its
# module directory .git/modules/common/codex/coding-agent-kit; only its path
# moved, into a package of its own.
SUBMODULE_NAME=common/codex/coding-agent-kit
SUBMODULE=common/coding-agent-kit/coding-agent-kit
PACKAGE=common/coding-agent-kit
SUBMODULE_URL=https://github.com/FridrichMethod/coding-agent-kit.git
# The pre-move checkout that a fast-forward leaves behind on a host where the
# submodule was checked out; .gitignore keeps it out of git status and the
# .stowrc line keeps Stow from linking it.
LEFTOVER=common/codex/coding-agent-kit
STOWRC_LINE='--ignore=^coding-agent-kit(/|$)'
GITIGNORE_LINE=/$LEFTOVER/
# Path-anchored, as in common/sherlock-kit: Stow matches a pattern with a
# slash against "/PATH", so only the package-root checkout is ignored.
LOCAL_IGNORE='^/coding-agent-kit$
^/coding-agent-kit/'
WINDOWS_PACKAGES="\$CommonPackages = @('claude', 'codex', 'coding-agent-kit', 'conda', 'git', 'pymol', 'ssh', 'wezterm')"
WARNING='[dotfiles] [warn] coding-agent-kit links dangle; codex-as, claude-as and the Claude helpers are unavailable until the submodule is checked out (git submodule update --init --recursive)'
# The link map: each of the 14 package files that are links into the
# submodule, and the kit file it points at. The home paths Stow links stay
# put whatever the kit's layout; a kit that moves a file changes only the
# text of its link here.
LINK_MAP='common/coding-agent-kit/.claude/dotfiles/check-git-hooks.cjs helpers/check-git-hooks.cjs
common/coding-agent-kit/.claude/dotfiles/notify.cjs helpers/notify.cjs
common/coding-agent-kit/.claude/dotfiles/statusline.cjs helpers/statusline.cjs
common/coding-agent-kit/.local/bin/claude-as bin/claude-as
common/coding-agent-kit/.local/bin/codex-as bin/codex-as
common/coding-agent-kit/.local/lib/claude-as/launch.py lib/claude-as/launch.py
common/coding-agent-kit/.local/lib/codex-as/check.py lib/codex-as/check.py
common/coding-agent-kit/.local/lib/codex-as/handoff.py lib/codex-as/handoff.py
common/coding-agent-kit/.local/lib/codex-as/launch.py lib/codex-as/launch.py
common/coding-agent-kit/.local/lib/codex-as/layout.py lib/codex-as/layout.py
common/coding-agent-kit/.local/share/bash-completion/completions/claude-as completions/bash/claude-as
common/coding-agent-kit/.local/share/bash-completion/completions/codex-as completions/bash/codex-as
common/coding-agent-kit/.oh-my-zsh/custom/completions/_claude-as completions/zsh/_claude-as
common/coding-agent-kit/.oh-my-zsh/custom/completions/_codex-as completions/zsh/_codex-as'
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

# in_fixture_env CMD...: CMD against a temporary repository, without the
# caller's git environment or the operator's git config.
in_fixture_env() {
    (
        unset_git_env
        export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
        "$@"
    )
}

fixture_git() {
    in_fixture_env git -c user.name=fixture -c user.email=fixture@example.invalid "$@"
}

# link_text PATH KIT_PATH: the text of the link at common/coding-agent-kit/REST
# to the kit file KIT_PATH. It climbs as many levels as REST has directories,
# to the package root, and enters the submodule there:
# ../../coding-agent-kit/bin/codex-as for .local/bin/codex-as.
link_text() {
    local rest=${1#common/*/} text=''
    while [[ "$rest" == */* ]]; do
        text=../$text
        rest=${rest#*/}
    done
    printf '%scoding-agent-kit/%s\n' "$text" "$2"
}

# legacy_package KIT_PATH: the package that linked KIT_PATH before the kit got
# its own package: claude for the Claude launcher and helpers, else codex.
legacy_package() {
    case $1 in
        helpers/* | *claude-as*) printf 'claude\n' ;;
        *) printf 'codex\n' ;;
    esac
}

# legacy_link PATH KIT_PATH: "LEGACY_PATH TEXT", the pre-move link for the map
# entry PATH: the same path in common/claude or common/codex, climbing one
# level more, to common/, and entering the checkout at
# common/codex/coding-agent-kit (../../../codex/coding-agent-kit/bin/codex-as).
legacy_link() {
    local text
    text=$(link_text "$1" "$2")
    printf 'common/%s/%s ../%scodex/coding-agent-kit/%s\n' \
        "$(legacy_package "$2")" "${1#common/*/}" "${text%coding-agent-kit/*}" "$2"
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
        "submodule.$SUBMODULE_NAME.path $SUBMODULE" \
        "submodule.$SUBMODULE_NAME.url $SUBMODULE_URL" \
        "submodule.$SUBMODULE_NAME.branch main")
    actual=$(git -C "$REPO_ROOT" config -f .gitmodules --get-regexp '^submodule\.common/codex/coding-agent-kit\.') ||
        fail ".gitmodules has no $SUBMODULE_NAME entry"
    [[ "$actual" == "$expected" ]] ||
        fail ".gitmodules entry $SUBMODULE_NAME is not exactly path $SUBMODULE, url $SUBMODULE_URL and branch main: $actual"
}

# The checkout sits at the root of its own package, whose local ignore file
# keeps Stow and stow-all.ps1 from linking it (a package-local file replaces
# Stow's built-in ignores only for that package). The pre-move checkout that
# a fast-forward leaves on a host must stay out of git status, or the login
# updater stops at "Checkout changed during update" and then at every later
# login, and out of Stow, or it links its whole tree into the home.
check_ignores() {
    local actual
    actual=$(grep -v -e '^#' -e '^$' "$REPO_ROOT/$PACKAGE/.stow-local-ignore") ||
        fail "$PACKAGE/.stow-local-ignore names no pattern"
    [[ "$actual" == "$LOCAL_IGNORE" ]] ||
        fail "$PACKAGE/.stow-local-ignore must hold exactly the path-anchored ^/coding-agent-kit\$ and ^/coding-agent-kit/: $actual"
    [[ "$(index_mode "$PACKAGE/.stow-local-ignore")" == 100644 ]] ||
        fail "$PACKAGE/.stow-local-ignore is not tracked as a 100644 regular file"
    expect_line "$STOWRC_LINE" "$REPO_ROOT/.stowrc"
    expect_line "$GITIGNORE_LINE" "$REPO_ROOT/.gitignore"
}

# index_links: every tracked symlink under common/coding-agent-kit,
# common/claude, common/codex and docs as "PATH -> TEXT".
index_links() {
    local mode sha path pattern='^(common/coding-agent-kit|common/claude|common/codex|docs)/'
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
# computed texts, and the sync launchers as regular files; nothing at the
# pre-move path; no package path besides the gitlink names coding-agent-kit,
# which .stowrc would hide.
check_index() {
    local actual expected path kit text rest
    [[ "$(index_mode "$SUBMODULE")" == 160000 ]] || fail "$SUBMODULE is not a gitlink (mode 160000)"
    actual=$(index_links)
    expected=$(while read -r path kit; do
        printf '%s -> %s\n' "$path" "$(link_text "$path" "$kit")"
    done <<<"$LINK_MAP" | LC_ALL=C sort)
    if [[ "$actual" != "$expected" ]]; then
        diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true
        fail 'the tracked links under common/coding-agent-kit, common/claude, common/codex and docs differ from the link map'
    fi
    [[ -z "$(git -C "$REPO_ROOT" ls-files -- "$LEFTOVER")" ]] || fail "the index still tracks $LEFTOVER"
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
    for launcher in $PACKAGE/.local/bin/codex-as $PACKAGE/.local/bin/claude-as; do
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

# line_of TEXT FILE: the number of the first line of FILE that is exactly
# TEXT, or empty.
line_of() {
    grep -m 1 -n -F -x -- "$1" "$2" | cut -d: -f1 || true
}

# A bump changes code that runs in every Codex and Claude session at the next
# login, and the Action's own push to main starts no ci.yml run. So it runs
# daily and by hand, one run at a time, on main; a dispatch runs the workflow
# file of the ref it names, so the job runs only for main, and the
# concurrency group is keyed on the ref, so such a skipped run cannot
# displace a pending main run. It reads the release tag of the pin and takes
# only the newest release with the same MAJOR.MINOR, then refuses it unless
# the release is on the kit's main ahead of the pin, every GitHub Actions run
# of the kit's three CI jobs on it passed, delivery holds at the staged
# gitlink and in stowed temporary homes, and the real-settings suite passes
# with GNU Stow and zsh installed. Only then does it commit and make its one
# push, to main. Of the job's own git commands only that push gets the
# token; actions/checkout used it for its fetch and did not persist it, so
# the release's code finds none, and setup-node takes it through its default
# input, both before the release is staged. The here-document lists lines
# that must appear exactly and in this order, so deleting or reordering any
# gate fails.
# Last, the whole file must equal its reviewed copy in tests/fixtures, both
# regular files tracked as 100644 (a link would compare a file with itself),
# so any other edit (an env mapping, a step output, a shell or an inserted
# line) fails until that copy changes in the same commit.
check_automation() {
    local workflow=$REPO_ROOT/.github/workflows/update-coding-agent-kit-submodule.yml triggers cron sibling line number
    local reviewed=$REPO_ROOT/tests/fixtures/update-coding-agent-kit-submodule.yml previous=0 steps guarded tokens file
    [[ -f "$workflow" ]] || fail "missing ${workflow#"$REPO_ROOT"/}"
    triggers=$(sed -n '/^on:/,/^[^[:space:]#]/{/^  [^[:space:]#]/p;}' "$workflow")
    [[ "$triggers" == $'  schedule:\n  workflow_dispatch:' ]] ||
        fail "the coding-agent-kit bump must run on schedule and workflow_dispatch only: $triggers"
    cron='    - cron: "17 5 * * *"'
    expect_line "$cron" "$workflow"
    for sibling in update-pymolscripts-submodule.yml update-sherlock-kit-submodule.yml; do
        ! grep -Fxq -- "$cron" "$REPO_ROOT/.github/workflows/$sibling" ||
            fail "the coding-agent-kit bump must not start with $sibling and race its push to main"
    done
    for line in 'concurrency:' '  group: update-coding-agent-kit-submodule-${{ github.ref }}' \
        '  cancel-in-progress: false' \
        "    if: github.ref == 'refs/heads/main'" '        shell: bash' '          ref: main' \
        '          persist-credentials: false'; do
        expect_line "$line" "$workflow"
    done
    # The workflow itself names the token only for gate 2's read and the
    # push, and sets no action's token input (both take it by default).
    tokens=$(grep -c -F 'secrets.GITHUB_TOKEN' "$workflow" || true)
    [[ "$tokens" == 2 ]] && grep -Fxq -- '          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}' "$workflow" &&
        grep -Fxq -- '          TOKEN: ${{ secrets.GITHUB_TOKEN }}' "$workflow" &&
        ! grep -Eq 'github\.token|^ +token:' "$workflow" ||
        fail 'the coding-agent-kit bump must pass the token only to gate 2 and the push step'
    while IFS= read -r line; do
        number=$(line_of "$line" "$workflow")
        [[ -n "$number" && "$number" -gt "$previous" ]] ||
            fail "the coding-agent-kit bump lacks this exact line after line $previous: $line"
        previous=$number
    done <<'EOF'
          git submodule update --init -- common/coding-agent-kit/coding-agent-kit
          pinned_sha=$(git rev-parse HEAD:common/coding-agent-kit/coding-agent-kit)
          git -C common/coding-agent-kit/coding-agent-kit fetch --quiet --tags origin +refs/heads/main:refs/remotes/origin/main
            { grep -Ex 'v[0-9]+\.[0-9]+\.[0-9]+' || true; } | sort -V
          pinned=$(git -C common/coding-agent-kit/coding-agent-kit tag --points-at "$pinned_sha" | releases | tail -n 1)
          if [ -z "$pinned" ]; then
            echo "::error::coding-agent-kit is pinned at $pinned_sha, which carries no vMAJOR.MINOR.PATCH release tag; bumps go through a reviewed pull request"
            exit 1
          candidate=$(git -C common/coding-agent-kit/coding-agent-kit tag --list "${pinned%.*}.*" | releases | tail -n 1)
          newest=$(git -C common/coding-agent-kit/coding-agent-kit tag --list | releases | tail -n 1)
          if [ "${newest%.*}" != "${pinned%.*}" ]; then
          if [ "$candidate" = "$pinned" ]; then
            echo "changed=0" >>"$GITHUB_OUTPUT"
            exit 0
            echo "changed=1"
          git -C common/coding-agent-kit/coding-agent-kit merge-base --is-ancestor "$SHA" refs/remotes/origin/main ||
            { echo "::error::coding-agent-kit $TAG ($SHA) is not on its main"; exit 1; }
          git -C common/coding-agent-kit/coding-agent-kit merge-base --is-ancestor "$PINNED_SHA" "$SHA" ||
            { echo "::error::coding-agent-kit $TAG ($SHA) does not descend from the pinned $PINNED_SHA"; exit 1; }
          missing=$(gh api "repos/FridrichMethod/coding-agent-kit/commits/$SHA/check-runs?per_page=100" \
            --jq '["Linux behavior and lint", "macOS system Bash behavior", "Windows native PowerShell behavior"] - ([.check_runs[] | select(.app.slug == "github-actions") | .name] - [.check_runs[] | select(.app.slug == "github-actions" and (.status != "completed" or .conclusion != "success")) | .name]) | join(", ")')
          [ -z "$missing" ] ||
            { echo "::error::coding-agent-kit CI is not green on $TAG ($SHA): $missing"; exit 1; }
      - uses: actions/setup-node@v6
          node-version: "24"
          git -C common/coding-agent-kit/coding-agent-kit checkout --quiet --detach "$SHA"
          git add common/coding-agent-kit/coding-agent-kit
          sudo apt-get install --yes --no-install-recommends stow zsh
          ./setup-sync.sh
          bash tests/coding-agent-kit-delivery.sh --real
          bash tests/coding-agent-kit-delivery.sh --ci
        run: bash tests/ai-integration.sh
          [ "$(git diff --cached --name-only)" = common/coding-agent-kit/coding-agent-kit ] ||
          git commit -m "chore(deps): update coding-agent-kit submodule to $TAG"
          git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic $(printf 'x-access-token:%s' "$TOKEN" | base64 -w0)" push origin HEAD:main
EOF
    # Every step after the checkout and the pick runs exactly when the pick
    # found a newer release, and none may fail without failing the run; the
    # only other condition is the job's, on main.
    steps=$(grep -c '^      - ' "$workflow" || true)
    guarded=$(grep -c -F -x "        if: steps.pick.outputs.changed == '1'" "$workflow" || true)
    [[ "$guarded" == $((steps - 2)) && "$(grep -c -E '^[[:space:]]*if:' "$workflow")" == $((guarded + 1)) ]] ||
        fail "every step after the pick must run if and only if steps.pick.outputs.changed == '1'"
    ! grep -q 'continue-on-error' "$workflow" || fail 'no step of the coding-agent-kit bump may continue on error'
    [[ "$(grep -c -E '^[[:space:]]*git .*[[:space:]]push[[:space:]]' "$workflow")" == 1 ]] ||
        fail 'the Action must push once, to main'
    ! grep -Eq 'bump/|branch=|/compare/' "$workflow" || fail 'the Action must leave no review branch'
    # A main that moved fails the push; a rebase would skip gate 4 on it.
    ! grep -Eq '^[[:space:]]*git .*[[:space:]](rebase|pull)([[:space:]]|$)' "$workflow" ||
        fail 'the Action must never rebase onto or pull a main that moved'
    expect_grep 'Pushes made with GITHUB_TOKEN do not trigger ci.yml' "$workflow"
    [[ -f "$reviewed" ]] || fail "missing ${reviewed#"$REPO_ROOT"/}"
    for file in "$workflow" "$reviewed"; do
        [[ ! -L "$file" && "$(index_mode "${file#"$REPO_ROOT"/}")" == 100644 ]] ||
            fail "${file#"$REPO_ROOT"/} must be a regular file tracked as 100644"
    done
    if ! cmp -s "$reviewed" "$workflow"; then
        diff -u "$reviewed" "$workflow" >&2 || true
        fail "${workflow#"$REPO_ROOT"/} differs from its reviewed copy ${reviewed#"$REPO_ROOT"/}; change both in the same commit"
    fi
}

# check_kit_knobs ROOT: every CODING_AGENT_KIT_* (or _CODING_AGENT_KIT_*) name
# in the kit's code at the gitlink ROOT's index records, outside the kit's own
# tests/, docs/, .github/ and Markdown, is on the unset list of
# ROOT/tests/run.sh, which every test entry point carries
# (tests/test-entrypoints.sh), so a caller's kit knob never reaches a suite.
# A name embedded in a longer identifier does not count. check_real runs it,
# so the bump Action's gate 3 refuses a release that reads a new knob, and
# tests/test-entrypoints.sh calls it for the checked-out submodule.
check_kit_knobs() {
    local root=$1 checkout=$1/$SUBMODULE recorded knobs names knob
    recorded=$(git -C "$root" ls-files -s -- "$SUBMODULE" | cut -d' ' -f2)
    checkout_git cat-file -e "$recorded^{commit}" 2>/dev/null ||
        fail "the $SUBMODULE checkout lacks the recorded gitlink $recorded; run git submodule update"
    knobs=$(sed -n '/^unset DOTFILES_AUTO_UPDATE /,/[^\\]$/p' "$root/tests/run.sh" | tr -d '\\' | tr -s ' ' '\n')
    [[ -n "$knobs" ]] || fail 'tests/run.sh has no unset statement for the dotfiles knobs'
    names=$(checkout_git -c grep.lineNumber=false -c grep.column=false \
        grep -I -h -o --no-color -E '(^|[^A-Za-z0-9_])_?CODING_AGENT_KIT_[A-Z_]+' "$recorded" \
        -- ':!tests' ':!docs' ':!.github' ':!*.md') ||
        fail "git grep found no CODING_AGENT_KIT_* name in coding-agent-kit $recorded"
    for knob in $(sed -E 's/^[^A-Z_]//' <<<"$names" | LC_ALL=C sort -u); do
        grep -Fxq -- "$knob" <<<"$knobs" ||
            fail "coding-agent-kit $recorded reads $knob, which tests/run.sh and the other test entry points do not unset; bump it through a reviewed pull request that adds it to every entry point"
    done
}

# check_real ROOT: the submodule of ROOT is checked out at the gitlink the
# index records, its code reads no knob the entry points leave set, every
# link resolves to a regular file at its kit path of the map, which that
# commit tracks with its mode, the kit tracks no symlink, nested submodule
# or .gitmodules, and it carries the overlay files, .gitattributes line and
# .gitignore patterns dotfiles relies on. An uninitialized submodule or an
# unstaged bump fails instead of passing; the bump Action stages its bump
# first.
check_real() {
    local root=$1 checkout=$1/$SUBMODULE physical path kit text revision recorded mode content pattern entries
    [[ -e "$checkout/.git" ]] ||
        fail "coding-agent-kit submodule not initialized at $SUBMODULE; run git submodule update --init --recursive"
    revision=$(checkout_git rev-parse HEAD)
    recorded=$(git -C "$root" ls-files -s -- "$SUBMODULE" | cut -d' ' -f2)
    [[ "$revision" == "$recorded" ]] ||
        fail "coding-agent-kit is checked out at $revision, which is not the recorded gitlink $recorded; stage the bump (git add $SUBMODULE) or check out the recorded commit (git submodule update)"
    check_kit_knobs "$root"
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
    # A nested submodule would have every host's login updater, which runs
    # git submodule update --init --recursive, clone its URL, and fail and
    # skip the restow at each login where it cannot.
    entries=$(checkout_git ls-tree -r "$recorded" |
        awk -F '\t' '$1 ~ /^(120000|160000) / { printf "%s%s", sep, $2; sep = ", " }')
    [[ -z "$entries" ]] || fail "coding-agent-kit $revision tracks a symlink or a nested submodule: $entries"
    ! checkout_git cat-file -e "$recorded:.gitmodules" 2>/dev/null ||
        fail "coding-agent-kit $revision has a .gitmodules"
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

# real_fixture ROOT: a superproject like a host checkout after git submodule
# update --init: the 14 links, tests/run.sh and a clone of the kit, checked
# out at the gitlink commit that its index records.
real_fixture() {
    local root=$1 path kit_git_dir
    fixture_git init -q "$root"
    mkdir -p "$root/tests"
    cp "$REPO_ROOT/tests/run.sh" "$root/tests/"
    while read -r path _; do
        mkdir -p "$root/${path%/*}"
        cp -RP "$REPO_ROOT/$path" "$root/$path"
    done <<<"$LINK_MAP"
    kit_git_dir=$(cd -- "$REPO_ROOT/$SUBMODULE" && unset_git_env && git rev-parse --absolute-git-dir)
    fixture_git clone -q --shared --no-checkout "$kit_git_dir" "$root/$SUBMODULE"
    record_kit "$root" "$(git -C "$REPO_ROOT" ls-files -s -- "$SUBMODULE" | cut -d' ' -f2)"
}

# record_kit ROOT COMMIT: the fixture kit checked out at COMMIT, which the
# index of ROOT then records.
record_kit() {
    fixture_git -C "$1/$SUBMODULE" checkout -q --detach "$2"
    fixture_git -C "$1" update-index --add --cacheinfo "160000,$2,$SUBMODULE"
}

# commit_kit ROOT MESSAGE: commits what is staged in the fixture kit and
# records the new commit.
commit_kit() {
    fixture_git -C "$1/$SUBMODULE" commit -q -m "$2"
    record_kit "$1" "$(fixture_git -C "$1/$SUBMODULE" rev-parse HEAD)"
}

# expect_real_failure CASE ROOT TEXT: check_real refuses ROOT, saying TEXT.
expect_real_failure() {
    if in_fixture_env check_real "$2" >"$TEST_TMP/real-$1.out" 2>&1; then
        cat "$TEST_TMP/real-$1.out" >&2
        fail "check_real accepted the $1 fixture"
    fi
    expect_grep "$3" "$TEST_TMP/real-$1.out"
}

# Sourced, as tests/test-entrypoints.sh does for check_kit_knobs, the test
# only defines its checks.
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-coding-agent-kit-delivery.XXXXXX")"
# macOS TMPDIR ends in '/', and /var may itself be a symlink.
TEST_TMP="$(cd -- "$TEST_TMP" && pwd -P)"
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM

check_gitmodules
check_ignores
check_index
check_sentinels
check_windows
check_automation
# check_automation on a copy of the bump workflows whose reviewed copy is a
# link to the workflow, which cmp would compare with itself: refused.
AUTOMATION_ROOT=$TEST_TMP/automation
mkdir -p "$AUTOMATION_ROOT/.github/workflows" "$AUTOMATION_ROOT/tests/fixtures"
cp "$REPO_ROOT/.github/workflows/"update-*-submodule.yml "$AUTOMATION_ROOT/.github/workflows/"
ln -s ../../.github/workflows/update-coding-agent-kit-submodule.yml \
    "$AUTOMATION_ROOT/tests/fixtures/update-coding-agent-kit-submodule.yml"
fixture_git init -q "$AUTOMATION_ROOT"
fixture_git -C "$AUTOMATION_ROOT" add -A
if (REPO_ROOT=$AUTOMATION_ROOT && in_fixture_env check_automation) >"$TEST_TMP/automation-link.out" 2>&1; then
    cat "$TEST_TMP/automation-link.out" >&2
    fail 'check_automation accepted a reviewed copy that links to the workflow'
fi
expect_grep 'tests/fixtures/update-coding-agent-kit-submodule.yml must be a regular file tracked as 100644' \
    "$TEST_TMP/automation-link.out"

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

# check_real on fixture superprojects: the recorded kit commit passes, and
# each change below, committed on it and recorded, fails.
REAL_ROOT=$TEST_TMP/real/dotfiles
REAL_KIT=$REAL_ROOT/$SUBMODULE
real_fixture "$REAL_ROOT"
REAL_COMMIT=$(fixture_git -C "$REAL_KIT" rev-parse HEAD)
in_fixture_env check_real "$REAL_ROOT" >"$TEST_TMP/real-pass.out"
expect_grep 'resolves every delivered link' "$TEST_TMP/real-pass.out"
# A nested submodule: its gitlink, and its .gitmodules entry on its own.
fixture_git -C "$REAL_KIT" update-index --add --cacheinfo "160000,$REAL_COMMIT,vendor/nested"
commit_kit "$REAL_ROOT" 'fixture: vendor a nested submodule'
expect_real_failure nested-gitlink "$REAL_ROOT" 'tracks a symlink or a nested submodule: vendor/nested'
# A tracked symlink: the checkout must work where links are unsupported.
record_kit "$REAL_ROOT" "$REAL_COMMIT"
ln -s codex-as "$REAL_KIT/bin/alias"
fixture_git -C "$REAL_KIT" add bin/alias
commit_kit "$REAL_ROOT" 'fixture: track a symlink'
expect_real_failure symlink "$REAL_ROOT" 'tracks a symlink or a nested submodule: bin/alias'
record_kit "$REAL_ROOT" "$REAL_COMMIT"
printf '[submodule "vendor/nested"]\n\tpath = vendor/nested\n\turl = https://example.invalid/nested.git\n' \
    >"$REAL_KIT/.gitmodules"
fixture_git -C "$REAL_KIT" add .gitmodules
commit_kit "$REAL_ROOT" 'fixture: add a .gitmodules'
expect_real_failure gitmodules "$REAL_ROOT" 'has a .gitmodules'
# A knob that the test entry points do not unset, with or without the
# leading underscore of an internal name.
for knob in CODING_AGENT_KIT_DEBUG _CODING_AGENT_KIT_TRACE; do
    record_kit "$REAL_ROOT" "$REAL_COMMIT"
    printf ': "${%s:-}"\n' "$knob" >>"$REAL_KIT/bin/codex-as"
    fixture_git -C "$REAL_KIT" add bin/codex-as
    commit_kit "$REAL_ROOT" "fixture: read $knob"
    expect_real_failure "knob$knob" "$REAL_ROOT" "reads $knob, which tests/run.sh and the other test entry points do not unset"
done

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
    cp -RP "$REPO_ROOT/common/codex" "$REPO_ROOT/common/claude" "$REPO_ROOT/$PACKAGE" "$checkout/common/"
    cp -RP "$REPO_ROOT/.stowrc" "$REPO_ROOT/.gitignore" "$checkout/"
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

# legacy_layout CHECKOUT: the pre-move layout in CHECKOUT, committed: the 14
# links at the same paths in common/claude and common/codex, climbing to
# common/ and entering the checkout at common/codex/coding-agent-kit, and no
# coding-agent-kit package.
legacy_layout() {
    local checkout=$1 path kit legacy text
    mv "$checkout/$SUBMODULE" "$checkout/$LEFTOVER"
    printf '/%s/\n' "$LEFTOVER" >>"$checkout/.git/info/exclude"
    while read -r path kit; do
        read -r legacy text <<<"$(legacy_link "$path" "$kit")"
        mkdir -p "$checkout/${legacy%/*}"
        ln -s "$text" "$checkout/$legacy"
    done <<<"$LINK_MAP"
    rm -rf "${checkout:?}/$PACKAGE"
    fixture_git -C "$checkout" add -A
    fixture_git -C "$checkout" commit -q -m 'fixture: pre-move layout'
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

# The package's local ignore file alone keeps the checkout out of the home:
# real Stow with no .stowrc (run where none is in reach, as after the cleanup
# that drops the line) links exactly the 14 package links, and the anchored
# pattern still lets a package-local .config/coding-agent-kit/ through.
ALONE=$TEST_TMP/alone
mkdir -p "$ALONE/home" "$ALONE/target" "$ALONE/stow"
cp -RP "$HOME_FULL/dotfiles/$PACKAGE" "$ALONE/stow/"
mkdir -p "$ALONE/stow/coding-agent-kit/.config/coding-agent-kit"
printf 'kept\n' >"$ALONE/stow/coding-agent-kit/.config/coding-agent-kit/kept"
(cd "$ALONE" && HOME=$ALONE/home stow --no-folding -d "$ALONE/stow" -t "$ALONE/target" coding-agent-kit) ||
    fail 'Stow without .stowrc refused the coding-agent-kit package'
[[ -f "$ALONE/target/.config/coding-agent-kit/kept" ]] || fail 'the local ignore hid .config/coding-agent-kit/'
[[ ! -e "$ALONE/target/coding-agent-kit" && ! -L "$ALONE/target/coding-agent-kit" ]] ||
    fail 'the local ignore alone let Stow link the checkout'
alone_links=$(cd "$ALONE/target" && find . -type l | sed 's|^\./||' | LC_ALL=C sort)
expected_links=$(
    while read -r path _; do home_link "$path"; done <<<"$LINK_MAP"
    printf '%s\n' .config/coding-agent-kit/kept
)
[[ "$alone_links" == "$(LC_ALL=C sort <<<"$expected_links")" ]] ||
    fail "Stow without .stowrc linked: $alone_links"

# A home stowed from the pre-move layout, as on every host before the kit got
# its own package. A fast-forward deletes the old links and leaves the old
# checkout behind (git cannot remove a submodule checkout that holds files);
# the submodule update fills the new path. One restow then converges to
# exactly the home of a fresh install: Stow replaces each home link whose
# package file is gone with the new package's link at the same path, the
# leftover is linked nowhere, and nothing warns.
HOME_MOVED=$TEST_TMP/moved/home
make_home "$HOME_MOVED"
MOVED_CHECKOUT=$HOME_MOVED/dotfiles
MOVED_HEAD=$(fixture_git -C "$MOVED_CHECKOUT" rev-parse HEAD)
legacy_layout "$MOVED_CHECKOUT"
stow_home legacy "$HOME_MOVED"
[[ ! -s "$TEST_TMP/legacy.stderr" ]] || fail "the pre-move stow warned: $(cat "$TEST_TMP/legacy.stderr")"
while read -r path kit; do
    link=$(home_link "$path")
    [[ "$(readlink "$HOME_MOVED/$link")" == */dotfiles/common/$(legacy_package "$kit")/$link && -f "$HOME_MOVED/$link" ]] ||
        fail "the pre-move stow did not link ~/$link to common/$(legacy_package "$kit")/$link"
done <<<"$LINK_MAP"
fixture_git -C "$MOVED_CHECKOUT" checkout -q --detach "$MOVED_HEAD"
restore_submodule "$HOME_MOVED"
[[ -f "$MOVED_CHECKOUT/$LEFTOVER/bin/codex-as" ]] || fail 'the fixture lost its pre-move checkout'
stow_home moved "$HOME_MOVED"
[[ ! -s "$TEST_TMP/moved.stderr" ]] || fail "the stow after the move warned: $(cat "$TEST_TMP/moved.stderr")"
assert_state "$HOME_MOVED" "$MOVED_HEAD"
snapshot "$HOME_MOVED" >"$TEST_TMP/moved.snapshot"
if ! cmp -s "$TEST_TMP/full.snapshot" "$TEST_TMP/moved.snapshot"; then
    diff -u "$TEST_TMP/full.snapshot" "$TEST_TMP/moved.snapshot" >&2 || true
    fail 'the home stowed across the move differs from a fresh install'
fi

echo 'coding-agent-kit-delivery=PASS'
