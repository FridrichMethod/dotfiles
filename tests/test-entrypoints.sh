#!/bin/bash

set -euo pipefail

# Isolate inherited configuration while preserving explicit test inputs.
# shellcheck source=tests/lib/environment.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/environment.sh"

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

# Every standalone shell entrypoint uses the same test-only boundary.
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
for test_file in "$TEST_DIR"/*.sh; do
    grep -Fq '/lib/environment.sh"' "$test_file" || {
        printf 'ERROR: %s does not load test environment isolation.\n' "$test_file" >&2
        exit 1
    }
done
for suite in bootstrap-manifest.sh doctor.sh e2e-harness.sh payload-update.sh setup-host.sh unix-installer.sh; do
    grep -Fxq 'dotfiles_test_clear_git_environment' "$TEST_DIR/$suite" || {
        printf 'ERROR: tests/%s does not isolate fixture Git.\n' "$suite" >&2
        exit 1
    }
done
for suite in e2e-harness.ps1 windows-installer-controls.ps1; do
    grep -Fxq 'Clear-DotfilesTestGitEnvironment' "$TEST_DIR/$suite" || {
        printf 'ERROR: tests/%s does not isolate fixture Git.\n' "$suite" >&2
        exit 1
    }
done
grep -Fq "'lib/environment.ps1'" "$TEST_DIR/run.ps1" || {
    printf 'ERROR: tests/run.ps1 does not load test environment isolation.\n' >&2
    exit 1
}
# Exercise actual prefix and Git isolation with small subprocess fixtures,
# including a hook's relative index and absolute linked-worktree Git dir.
python3 -I -B -m unittest discover -s "$TEST_DIR" -p 'test_environment.py' -v

# Each hook named below runs its suite when a file the suite depends on
# changes: the engine suites on the engine and the real Codex config.toml,
# the payload hook suite on the hook, its config, the rc files that source it
# and the logger, and this test on itself, the entry points it reads and the
# hook configuration. Files are selected as pre-commit
# selects them: re.search of the hook's files, then of its exclude and the
# top-level one.
python3 -I -B - "$REPO_ROOT/.pre-commit-config.yaml" "$TEST_DIR/run.sh" <<'PY'
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
    match = re.match(r'\s+entry: (\S+)\s*$', line)
    if match and hook is not None:
        hook['entry'] = match.group(1)
        continue
    match = re.match(r'\s+(files|exclude): (.+?)\s*$', line)
    if match and hook is not None:
        hook[match.group(1)] = re.compile(match.group(2).strip('\'"'))
engine = ['lib/config_sync.py', 'lib/sync-runtime.sh']
need = {
    'structured-config-sync': engine + ['common/codex/.codex/config.toml'],
    'ai-config-sync': engine,
    'codex-config-sync': engine + ['common/codex/.codex/config.toml'],
    'payload-update': ['scripts/payload-update.sh', 'scripts/awesome-skills-update.sh', 'config/payloads.tsv',
                       'common/sh/.aliases', 'common/sh/.profile', 'common/zsh/.zshrc', 'lib/terminal.sh',
                       'tests/payload-update.sh', 'tests/test_payload_download.py'],
    'test-entrypoints': ['.pre-commit-config.yaml', 'tests/test-entrypoints.sh', 'tests/run.sh', 'tests/run.ps1',
                         'tests/windows-installer-controls.ps1', 'tests/lib/environment.sh',
                         'tests/lib/environment.ps1', 'tests/test_environment.py'],
    'e2e-harness': ['tests/e2e-harness.sh', 'tests/e2e/inside.sh', 'tests/e2e/lib/blocks.sh'],
    'e2e-harness-windows': ['tests/e2e-harness-windows.sh', 'tests/e2e-harness.ps1',
                            'tests/e2e/run.ps1', 'tests/e2e/lib/steps.ps1'],
}
missed = []
for name, paths in need.items():
    if len(hooks.get(name, [])) != 1:
        sys.exit(f'ERROR: .pre-commit-config.yaml must define the hook {name} exactly once.')
    files, exclude = hooks[name][0].get('files'), hooks[name][0].get('exclude')
    for path in paths:
        if (files and not files.search(path)) or any(e and e.search(path) for e in (exclude, top_exclude)):
            missed.append(f'{name} does not run on {path}')
runner = open(sys.argv[2], encoding='utf-8').read()
runner_suites = re.search(r'tests=\(\n(.*?)\n\)', runner, re.S).group(1).split() + ['unix-installer.sh']
entries = {hook.get('entry') for variants in hooks.values() for hook in variants}
for suite in runner_suites:
    if 'tests/' + suite not in entries:
        missed.append(f'Linux pre-commit behavior pass omits {suite}')
if missed:
    sys.exit('ERROR: ' + '; '.join(missed))
PY

printf 'test-entrypoints=PASS\n'
