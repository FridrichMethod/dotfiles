#!/bin/bash

set -euo pipefail

# Hermetic: the provisioning exports (DOTFILES_AUTO_UPDATE=0 and the like,
# docs/bootstrap.md) and other dotfiles knobs never reach the code under
# test from the caller; each case sets what it needs.
unset DOTFILES_AUTO_UPDATE DOTFILES_AUTO_STOW DOTFILES_HOST DOTFILES_DIR _DOTFILES_CHECKED \
    DOTFILES_STOW_WITHOUT_OH_MY_ZSH DOTFILES_COLOR AWESOME_SKILLS_AUTO_UPDATE AWESOME_SKILLS_FORCE \
    AWESOME_SKILLS_BG AWESOME_SKILLS_INSTALLER_URL AWESOME_SKILLS_REFRESH_DAYS _AWESOME_SKILLS_CHECKED \
    CODING_AGENT_KIT_CONFIG CODING_AGENT_KIT_COLOR

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-test-entrypoints.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT
# A pre-commit hook runs this test on its own, without tests/run.sh to name a
# missing prerequisite first, so no failure may stop it silently: a bare
# assertion names its line, and a check of a captured run prints that run.
trap 'printf "ERROR: tests/test-entrypoints.sh failed at line %s.\n" "$LINENO" >&2' ERR
# fail_run NAME MESSAGE: print the run captured in $TEST_TMP/NAME.stdout and
# NAME.stderr, which the EXIT trap deletes, then MESSAGE, and stop.
fail_run() {
    cat -- "$TEST_TMP/$1.stdout" "$TEST_TMP/$1.stderr" >&2
    printf 'ERROR: %s\n' "$2" >&2
    exit 1
}
mkdir "$TEST_TMP/bin"

# Deliberately omit optional tools without relying on the host's installed set.
for dependency in bash sh git python3 node dirname; do
    ln -s "$(command -v "$dependency")" "$TEST_TMP/bin/$dependency"
done
if PATH="$TEST_TMP/bin" /bin/bash "$TEST_DIR/run.sh" --ci --check-prerequisites \
    >"$TEST_TMP/ci.stdout" 2>"$TEST_TMP/ci.stderr"; then
    printf 'ERROR: CI accepted a missing Stow integration prerequisite.\n' >&2
    exit 1
fi
grep -Fq 'CI requires stow' "$TEST_TMP/ci.stderr" ||
    fail_run ci 'tests/run.sh --ci --check-prerequisites did not name the missing stow.'

if ! PATH="$TEST_TMP/bin" /bin/bash "$TEST_DIR/run.sh" --check-prerequisites \
    >"$TEST_TMP/local.stdout" 2>"$TEST_TMP/local.stderr"; then
    fail_run local 'tests/run.sh --check-prerequisites failed with only optional tools missing.'
fi
for skipped in 'real GNU Stow integration' 'optional Unix PowerShell checks' \
    'optional installed-Codex exec-policy checks'; do
    grep -Fq "SKIP: $skipped" "$TEST_TMP/local.stdout" ||
        fail_run local "tests/run.sh --check-prerequisites did not skip the $skipped."
done
grep -Fxq 'test-prerequisites=PASS' "$TEST_TMP/local.stdout" ||
    fail_run local 'tests/run.sh --check-prerequisites did not print test-prerequisites=PASS.'

rm "$TEST_TMP/bin/node"
if PATH="$TEST_TMP/bin" /bin/bash "$TEST_DIR/run.sh" --check-prerequisites \
    >"$TEST_TMP/missing.stdout" 2>"$TEST_TMP/missing.stderr"; then
    printf 'ERROR: local tests accepted a missing required Node dependency.\n' >&2
    exit 1
fi
grep -Fq 'required test dependency not found: node' "$TEST_TMP/missing.stderr" ||
    fail_run missing 'tests/run.sh --check-prerequisites did not name the missing node.'

if /bin/bash "$TEST_DIR/run.sh" --unknown-option \
    >"$TEST_TMP/option.stdout" 2>"$TEST_TMP/option.stderr"; then
    printf 'ERROR: test entrypoint accepted an unknown option.\n' >&2
    exit 1
else
    [[ "$?" == 2 ]]
fi

# Every entry point drops the same dotfiles knobs, tests/run.ps1 too, and the
# list names every DOTFILES_* and AWESOME_SKILLS_* variable the code can read
# (but DOTFILES_SYNC_PYTHON, which tests/run.sh provisions), so a shell that
# exports DOTFILES_AUTO_UPDATE=0 while provisioning cannot fail a suite. It
# also names every CODING_AGENT_KIT_* variable that the coding-agent-kit
# launchers the suites run can read (check_kit_knobs of
# tests/coding-agent-kit-delivery.sh).
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
# knob_list FILE: the names of FILE's "unset DOTFILES_AUTO_UPDATE ..." statement.
knob_list() {
    sed -n '/^unset DOTFILES_AUTO_UPDATE /,/[^\\]$/p' "$1" | tr -d '\\' | tr -s ' ' '\n' |
        grep -v -e '^unset$' -e '^$' | LC_ALL=C sort
}
KNOBS=$(knob_list "$TEST_DIR/run.sh")
[[ -n "$KNOBS" ]] || {
    printf 'ERROR: tests/run.sh has no unset statement for the dotfiles knobs.\n' >&2
    exit 1
}
for test_file in "$TEST_DIR"/*.sh; do
    if [[ "$(knob_list "$test_file")" != "$KNOBS" ]]; then
        printf 'ERROR: %s does not unset the dotfiles knobs that tests/run.sh does.\n' "${test_file#"$REPO_ROOT"/}" >&2
        exit 1
    fi
done
PS_KNOBS=$(awk '/foreach \(\$knob in @\(/ { on = 1 } on { print } on && /\)\) \{/ { exit }' "$TEST_DIR/run.ps1" |
    grep -oE "'[A-Z_]+'" | tr -d "'" | LC_ALL=C sort)
if [[ "$PS_KNOBS" != "$KNOBS" ]]; then
    printf 'ERROR: tests/run.ps1 does not remove the dotfiles knobs that tests/run.sh unsets.\n' >&2
    exit 1
fi
# The names come from every tracked file outside tests/, docs/, .github/ and
# Markdown, whatever reads them: $NAME and ${NAME in shell, $env:NAME,
# Env:NAME and GetEnvironmentVariable('NAME') in PowerShell, os.environ in
# Python. A name embedded in a longer identifier does not count.
if ! KNOB_NAMES=$(git -C "$REPO_ROOT" -c grep.lineNumber=false -c grep.column=false \
    grep -I -h -o --no-color -E '(^|[^A-Za-z0-9_])_?(DOTFILES|AWESOME_SKILLS)_[A-Z_]+' \
    -- ':!tests' ':!docs' ':!.github' ':!*.md'); then
    printf 'ERROR: git grep found no DOTFILES_* or AWESOME_SKILLS_* name in %s.\n' "$REPO_ROOT" >&2
    exit 1
fi
READ_KNOBS=$(printf '%s\n' "$KNOB_NAMES" | sed -E 's/^[^A-Z_]//' | LC_ALL=C sort -u)
for knob in $READ_KNOBS; do
    case $knob in
        DOTFILES_SYNC_PYTHON | DOTFILES_TEST_*) continue ;;
    esac
    if ! grep -Fxq -- "$knob" <<<"$KNOBS"; then
        printf 'ERROR: tracked code reads %s, which the test entry points do not unset.\n' "$knob" >&2
        exit 1
    fi
done
# The same for the kit's knobs, from its code at the recorded gitlink outside
# its own tests and docs, when the submodule is checked out. The delivery
# test owns that check, so the bump Action's gate 3 runs it on every release.
if [[ -e "$REPO_ROOT/common/codex/coding-agent-kit/.git" ]]; then
    (
        set --
        # shellcheck source=tests/coding-agent-kit-delivery.sh
        source "$TEST_DIR/coding-agent-kit-delivery.sh"
        check_kit_knobs "$REPO_ROOT"
    )
fi
# Commit hooks export a relative index path. The manifest suite creates a
# linked worktree whose .git is a file, so fixture Git must clear this path.
if ! env GIT_INDEX_FILE=.git/index /bin/bash "$TEST_DIR/bootstrap-manifest.sh" \
    >"$TEST_TMP/git-hook.stdout" 2>"$TEST_TMP/git-hook.stderr"; then
    cat "$TEST_TMP/git-hook.stdout" "$TEST_TMP/git-hook.stderr" >&2
    printf 'ERROR: bootstrap manifest fixtures inherited the commit index.\n' >&2
    exit 1
fi
grep -Fxq 'bootstrap-manifest=PASS' "$TEST_TMP/git-hook.stdout" ||
    fail_run git-hook 'tests/bootstrap-manifest.sh did not print bootstrap-manifest=PASS.'
# A commit hook in a linked worktree exports an absolute GIT_DIR and
# GIT_INDEX_FILE, which -C does not override: fixture Git would reinitialize,
# stage and commit into that repository. Each suite that runs fixture Git in
# its own body drops them before its first git command: the Bash suites with
# this unset, the PowerShell ones by removing every GIT_* entry.
for suite in bootstrap-manifest.sh doctor.sh e2e-harness.sh setup-host.sh unix-installer.sh; do
    if ! grep -Eq '^unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE ' "$TEST_DIR/$suite"; then
        printf 'ERROR: tests/%s does not unset GIT_DIR and GIT_INDEX_FILE for its fixture Git.\n' "$suite" >&2
        exit 1
    fi
done
for suite in e2e-harness.ps1 windows-installer-controls.ps1; do
    if ! grep -Fq "Where-Object Name -Like 'GIT_*'" "$TEST_DIR/$suite" ||
        ! grep -Fq 'Remove-Item -LiteralPath "Env:$name"' "$TEST_DIR/$suite"; then
        printf 'ERROR: tests/%s does not remove every GIT_* variable for its fixture Git.\n' "$suite" >&2
        exit 1
    fi
done
# hook_git ARGS: git on the throwaway repository below, without the caller's
# git environment or configuration.
hook_git() {
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
        -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_PREFIX GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        git -c user.name=fixture -c user.email=fixture@example.invalid -c init.defaultBranch=main "$@"
}
# The installer controls, run as from such a hook of a throwaway repository's
# linked worktree, leave that repository as it was.
if command -v pwsh >/dev/null 2>&1; then
    HOOK_REPO=$TEST_TMP/hook-repo
    HOOK_WORKTREE=$TEST_TMP/hook-worktree
    hook_git init -q "$HOOK_REPO"
    printf 'fixture\n' >"$HOOK_REPO/tracked"
    hook_git -C "$HOOK_REPO" add tracked
    hook_git -C "$HOOK_REPO" commit -q -m fixture
    hook_git -C "$HOOK_REPO" worktree add -q --detach "$HOOK_WORKTREE"
    HOOK_GIT_DIR=$(hook_git -C "$HOOK_WORKTREE" rev-parse --absolute-git-dir)
    HOOK_HEAD=$(hook_git -C "$HOOK_WORKTREE" rev-parse HEAD)
    if ! (cd -- "$HOOK_WORKTREE" && env GIT_DIR="$HOOK_GIT_DIR" GIT_INDEX_FILE="$HOOK_GIT_DIR/index" \
        pwsh -NoProfile -NonInteractive -File "$TEST_DIR/windows-installer-controls.ps1") \
        >"$TEST_TMP/hook-controls.stdout" 2>"$TEST_TMP/hook-controls.stderr"; then
        cat "$TEST_TMP/hook-controls.stdout" "$TEST_TMP/hook-controls.stderr" >&2
        printf 'ERROR: tests/windows-installer-controls.ps1 fails under a commit hook GIT_DIR.\n' >&2
        exit 1
    fi
    grep -Fq 'windows-installer-controls=PASS' "$TEST_TMP/hook-controls.stdout" ||
        fail_run hook-controls 'tests/windows-installer-controls.ps1 did not print windows-installer-controls=PASS.'
    if [[ "$(hook_git -C "$HOOK_REPO" config --get core.bare)" != false ]] ||
        ! hook_git -C "$HOOK_WORKTREE" diff --cached --quiet ||
        [[ "$(hook_git -C "$HOOK_WORKTREE" rev-parse HEAD)" != "$HOOK_HEAD" ]]; then
        printf 'ERROR: tests/windows-installer-controls.ps1 wrote into the repository of a commit hook GIT_DIR.\n' >&2
        exit 1
    fi
else
    printf 'SKIP: installer controls under a commit hook GIT_DIR (pwsh unavailable).\n'
fi

# Each hook named below runs its suite when a file the suite depends on
# changes: the engine suites on the engine and the real Codex config.toml,
# the delivery test on the knob list of tests/run.sh and on the bump
# workflow and its reviewed copy, and this test on itself, the entry points
# it reads and the hook configuration. Files are selected as pre-commit
# selects them: re.search of the hook's files, then of its exclude and the
# top-level one.
python3 -I - "$REPO_ROOT/.pre-commit-config.yaml" <<'PY'
import re
import sys

top_exclude = None
hooks = {}
hook = None
for line in open(sys.argv[1], encoding='utf-8'):
    match = re.match(r'exclude: (.+?)\s*$', line)
    if match:
        top_exclude = re.compile(match.group(1).strip('\'"'))
        continue
    match = re.match(r'\s+- id: (\S+)\s*$', line)
    if match:
        hook = {}
        hooks.setdefault(match.group(1), []).append(hook)
        continue
    match = re.match(r'\s+(files|exclude): (.+?)\s*$', line)
    if match and hook is not None:
        hook[match.group(1)] = re.compile(match.group(2).strip('\'"'))
engine = ['lib/config_sync.py', 'lib/sync-runtime.sh']
need = {
    'structured-config-sync': engine + ['common/codex/.codex/config.toml'],
    'ai-config-sync': engine,
    'codex-config-sync': engine + ['common/codex/.codex/config.toml'],
    'coding-agent-kit-delivery': ['tests/run.sh', '.github/workflows/update-coding-agent-kit-submodule.yml',
                                  'tests/fixtures/update-coding-agent-kit-submodule.yml'],
    'test-entrypoints': ['.pre-commit-config.yaml', 'tests/test-entrypoints.sh', 'tests/run.sh', 'tests/run.ps1',
                         'tests/windows-installer-controls.ps1'],
}
missed = []
for name, paths in need.items():
    if len(hooks.get(name, [])) != 1:
        sys.exit(f'ERROR: .pre-commit-config.yaml must define the hook {name} exactly once.')
    files, exclude = hooks[name][0].get('files'), hooks[name][0].get('exclude')
    for path in paths:
        if (files and not files.search(path)) or any(e and e.search(path) for e in (exclude, top_exclude)):
            missed.append(f'{name} does not run on {path}')
if missed:
    sys.exit('ERROR: ' + '; '.join(missed))
PY

# The provisioning exports in the caller's shell change nothing.
if ! env DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0 DOTFILES_HOST= _DOTFILES_CHECKED=1 \
    AWESOME_SKILLS_FORCE=1 AWESOME_SKILLS_BG=1 _AWESOME_SKILLS_CHECKED=1 \
    /bin/bash "$TEST_DIR/awesome-skills-update.sh" >"$TEST_TMP/hermetic.stdout" 2>"$TEST_TMP/hermetic.stderr"; then
    cat "$TEST_TMP/hermetic.stdout" "$TEST_TMP/hermetic.stderr" >&2
    printf 'ERROR: tests/awesome-skills-update.sh fails under the provisioning exports.\n' >&2
    exit 1
fi
grep -Fxq 'awesome-skills-update=PASS' "$TEST_TMP/hermetic.stdout" ||
    fail_run hermetic 'tests/awesome-skills-update.sh did not print awesome-skills-update=PASS.'

printf 'test-entrypoints=PASS\n'
