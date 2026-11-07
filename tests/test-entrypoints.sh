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
if (
    unset DOTFILES_TEST_CHEZMOI DOTFILES_TEST_REQUIRE_CHEZMOI
    PATH="$TEST_TMP/bin" /bin/bash "$TEST_DIR/run.sh" --ci --check-prerequisites
) \
    >"$TEST_TMP/ci.stdout" 2>"$TEST_TMP/ci.stderr"; then
    printf 'ERROR: CI accepted a missing chezmoi prerequisite.\n' >&2
    exit 1
fi
if grep -Fqi stow "$TEST_TMP/ci.stdout" "$TEST_TMP/ci.stderr"; then
    fail_run ci 'tests/run.sh --ci --check-prerequisites still requires or mentions GNU Stow.'
fi

grep -Fq 'CI requires chezmoi' "$TEST_TMP/ci.stderr" ||
    fail_run ci 'tests/run.sh --ci --check-prerequisites did not name missing chezmoi.'

if ! (
    unset DOTFILES_TEST_CHEZMOI DOTFILES_TEST_REQUIRE_CHEZMOI
    PATH="$TEST_TMP/bin" /bin/bash "$TEST_DIR/run.sh" --check-prerequisites
) \
    >"$TEST_TMP/local.stdout" 2>"$TEST_TMP/local.stderr"; then
    fail_run local 'tests/run.sh --check-prerequisites failed with only optional tools missing.'
fi
for skipped in 'optional Unix PowerShell checks' 'optional installed-Codex exec-policy checks' \
    'native chezmoi fixtures'; do
    grep -Fq "SKIP: $skipped" "$TEST_TMP/local.stdout" ||
        fail_run local "tests/run.sh --check-prerequisites did not skip the $skipped."
done
if grep -Fqi stow "$TEST_TMP/local.stdout" "$TEST_TMP/local.stderr"; then
    fail_run local 'tests/run.sh --check-prerequisites still mentions GNU Stow.'
fi
grep -Fxq 'test-prerequisites=PASS' "$TEST_TMP/local.stdout" ||
    fail_run local 'tests/run.sh --check-prerequisites did not print test-prerequisites=PASS.'

if DOTFILES_TEST_CHEZMOI="$TEST_TMP/missing-chezmoi" /bin/bash "$TEST_DIR/run.sh" --check-prerequisites \
    >"$TEST_TMP/chezmoi.stdout" 2>"$TEST_TMP/chezmoi.stderr"; then
    printf 'ERROR: tests accepted an invalid explicit chezmoi executable.\n' >&2
    exit 1
fi
grep -Fq 'invalid DOTFILES_TEST_CHEZMOI' "$TEST_TMP/chezmoi.stderr" ||
    fail_run chezmoi 'tests/run.sh did not reject the explicit invalid chezmoi path.'

# A python3 below the 3.11 floor is a named prerequisite failure, not an
# ImportError inside a suite.
mkdir "$TEST_TMP/old-python"
for dependency in bash sh git node dirname; do
    ln -s "$(command -v "$dependency")" "$TEST_TMP/old-python/$dependency"
done
printf '#!/bin/sh\nexit 1\n' >"$TEST_TMP/old-python/python3"
chmod +x "$TEST_TMP/old-python/python3"
if (
    unset DOTFILES_TEST_CHEZMOI DOTFILES_TEST_REQUIRE_CHEZMOI
    PATH="$TEST_TMP/old-python" /bin/bash "$TEST_DIR/run.sh" --check-prerequisites
) \
    >"$TEST_TMP/old-python.stdout" 2>"$TEST_TMP/old-python.stderr"; then
    printf 'ERROR: tests accepted a python3 below the 3.11 floor.\n' >&2
    exit 1
fi
grep -Fq 'python3 is not Python 3.11 or newer' "$TEST_TMP/old-python.stderr" ||
    fail_run old-python 'tests/run.sh --check-prerequisites did not name the Python 3.11 floor.'

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
for suite in bootstrap-manifest.sh doctor.sh e2e-harness.sh payload-update.sh setup-host.sh; do
    grep -Fxq 'dotfiles_test_clear_git_environment' "$TEST_DIR/$suite" || {
        printf 'ERROR: tests/%s does not isolate fixture Git.\n' "$suite" >&2
        exit 1
    }
done
grep -Fxq 'Clear-DotfilesTestGitEnvironment' "$TEST_DIR/e2e-harness.ps1" || {
    printf 'ERROR: tests/e2e-harness.ps1 does not isolate fixture Git.\n' >&2
    exit 1
}
grep -Fq "'lib/environment.ps1'" "$TEST_DIR/run.ps1" || {
    printf 'ERROR: tests/run.ps1 does not load test environment isolation.\n' >&2
    exit 1
}
# Exercise actual prefix and Git isolation with small subprocess fixtures,
# including a hook's relative index and absolute linked-worktree Git dir.
python3 -I -B -m unittest discover -s "$TEST_DIR" -p 'test_environment.py' -v

# Each hook named below runs its suite when a file the suite depends on
# changes: the payload hook suite on the hook, its config, the rc files that
# source it and the logger, and this test on itself, the entry points it
# reads and the hook configuration. Files are selected as pre-commit
# selects them: re.search of the hook's files, then of its exclude and the
# top-level one; a shell linter must also declare its types.
python3 -I -B - "$REPO_ROOT/.pre-commit-config.yaml" "$TEST_DIR/run.sh" "$TEST_DIR/fixtures/chezmoi/targets.tsv" <<'PY'
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
        continue
    match = re.match(r'\s+types: \[(.*)\]\s*$', line)
    if match and hook is not None:
        hook['types'] = [tag.strip() for tag in match.group(1).split(',') if tag.strip()]
need = {
    'ai-policy': ['tests/ai-policy.sh', 'tests/test_ai_policy.py', 'home/.policy/claude-settings.json',
                  'home/dot_claude/CLAUDE.md', 'home/dot_codex/AGENTS.md',
                  'home/dot_codex/rules/portable.rules', 'CLAUDE.md', 'AGENTS.md',
                  'tests/lib/environment.sh'],
    'payload-update': ['scripts/payload-update.sh', 'config/payloads.tsv', 'home/dot_aliases', 'home/dot_profile',
                       'home/dot_zshrc', 'lib/terminal.sh', 'lib/chezmoi-guard.sh', 'tests/payload-update.sh',
                       'tests/test_payload_download.py'],
    'test-entrypoints': ['.pre-commit-config.yaml', 'tests/test-entrypoints.sh', 'tests/run.sh', 'tests/run.ps1',
                         'tests/lib/environment.sh', 'tests/lib/environment.ps1', 'tests/test_environment.py',
                         'tests/fixtures/chezmoi/targets.tsv'],
    'repository-text': ['README.md', 'AGENTS.md', 'docs/bootstrap.md', '.gitignore',
                        'tests/test_repository_text.py', 'tests/repository-text.sh'],
    'chezmoi-native': ['tests/chezmoi_support.py', 'tests/test_chezmoi_foundation.py',
                       'lib/chezmoi-guard.sh', 'lib/chezmoi-guard.ps1',
                       'scripts/chezmoi-update.sh', 'scripts/chezmoi-update.ps1',
                       'scripts/payload-update.sh', '.gitignore',
                       'tests/chezmoi-takeover.sh', 'tests/chezmoi-takeover.ps1',
                       'home/.chezmoidata/codex-policy.json',
                       'home/.policy/claude-settings.json', 'home/.policy/codex-config.toml',
                       'home/dot_claude/modify_private_settings.json',
                       'home/dot_codex/modify_private_config.toml',
                       'tests/test_chezmoi_claude.py', 'tests/test_chezmoi_codex.py',
                       'tests/test_chezmoi_integration.py',
                       '.chezmoiroot', '.chezmoiversion', 'home/.chezmoiignore', '.gitattributes',
                       'home/dot_zshrc', 'home/dot_local/bin/executable_my-fzf-preview.sh',
                       'home/dot_config/aria2/aria2.conf', 'home/dot_wezterm.lua', 'home/dot_p10k.zsh',
                       'home/dot_config/sh/dot_profile.tmpl', 'home/.hosts/mac/.config/sh/.profile',
                       'tests/chezmoi_source_support.py', 'tests/test_chezmoi_source_state.py',
                       'tests/test_chezmoi_rendered.py', 'tests/fixtures/chezmoi/targets.tsv',
                       'home/dot_profile', 'home/dot_wslconfig',
                       'tests/test_chezmoi_native_config.py', 'tests/test_chezmoi_secrets.py',
                       'tests/fixtures/chezmoi/native-config/modify_private_settings.json',
                       'tests/fixtures/chezmoi/secrets/README.md', 'tests/chezmoi.sh',
                       'tests/chezmoi.ps1', 'tests/lib/environment.sh', 'tests/lib/environment.ps1',
                       '.github/scripts/install-test-chezmoi.py', 'lib/bootstrap/platform.sh',
                       'lib/bootstrap/checks.sh', 'lib/bootstrap/steps-human.sh',
                       'doctor.sh', 'setup-host.sh'],
    'e2e-harness': ['tests/e2e-harness.sh', 'tests/e2e/inside.sh', 'tests/e2e/lib/blocks.sh',
                    'tests/e2e/lib/steps.sh', 'docs/bootstrap.md', 'config/bootstrap/installers.tsv',
                    '.chezmoiversion', 'lib/bootstrap/steps-common.sh'],
    'shell-profile': ['home/dot_profile', 'home/dot_aliases', 'home/dot_zshrc', 'home/dot_oh-my-zsh/custom/nvm.zsh',
                      'home/dot_oh-my-zsh/custom/fzf-tab.zsh', 'lib/chezmoi-guard.sh'],
    'terminal-output': ['lib/terminal.sh', 'lib/terminal.ps1', 'tests/terminal.ps1', 'doctor.ps1', 'setup-host.ps1'],
    'powershell-profile': ['lib/chezmoi-guard.ps1', 'scripts/payload-update.ps1', 'tests/powershell-profile.sh',
                           'doctor.ps1', 'setup-host.ps1', 'lib/terminal.ps1', 'scripts/chezmoi-update.ps1',
                           'tests/run.ps1', 'tests/terminal.ps1',
                           'home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/'
                           'LocalState/settings.json', 'home/Documents/PowerShell/profile.ps1',
                           'home/Documents/WindowsPowerShell/profile.ps1',
                           'home/dot_config/oh-my-posh/prompt.omp.json', 'home/dot_zshrc'],
    'doctor': ['lib/terminal.sh', 'lib/chezmoi-guard.sh'],
    'setup-host': ['lib/terminal.sh', 'lib/chezmoi-guard.sh'],
    'bootstrap-windows': ['lib/bootstrap.ps1', 'lib/terminal.ps1', 'lib/chezmoi-guard.ps1'],
    'e2e-harness-windows': ['tests/e2e-harness-windows.sh', 'tests/e2e-harness.ps1',
                            'tests/e2e/run.ps1', 'tests/e2e/lib/steps.ps1', 'tests/e2e/lib/flow-win.ps1',
                            'docs/bootstrap.md', 'lib/chezmoi-guard.ps1', 'setup-host.ps1'],
    'tmux-config': ['home/dot_tmux.conf', 'home/dot_config/tmux/metric.py', 'home/dot_config/tmux/modern.conf'],
    'claude-customizations': ['home/.policy/claude-settings.json', 'tests/claude-customizations.cjs'],
    'ai-integration': ['.claude/settings.json', 'home/.policy/claude-settings.json', 'home/dot_zsh_aliases',
                       'home/dot_bash_aliases', 'home/dot_oh-my-zsh/custom/fzf-tab.zsh'],
    'host-overlays': ['home/.hosts/wsl-ubuntu/.config/bash/.bashrc', 'home/.hosts/lab-ubuntu/.config/zsh/.zshrc',
                      'home/.hosts/mac/.config/sh/.profile', 'home/dot_aliases'],
}
missed = []
for name, excluded, checked in (
    ('check-json', ['home/dot_claude/modify_private_settings.json',
                    'tests/fixtures/chezmoi/native-config/modify_private_settings.json'],
                   ['home/.policy/claude-settings.json', 'home/.chezmoidata/codex-policy.json',
                    'home/dot_claude/ordinary.json',
                    'home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json',
                    'home/dot_codex/pets/tom/pet.json', 'home/dot_config/oh-my-posh/prompt.omp.json']),
    ('check-toml', ['home/dot_codex/modify_private_config.toml',
                    'tests/fixtures/chezmoi/native-config/modify_private_config.toml'],
                   ['home/.policy/codex-config.toml', 'home/dot_codex/ordinary.toml']),
):
    exclude = hooks[name][0].get('exclude')
    for path in excluded:
        if not exclude or not exclude.search(path):
            missed.append(f'{name} attempts to parse native template {path}')
    for path in checked:
        if exclude and exclude.search(path):
            missed.append(f'{name} excludes ordinary policy/data {path}')
for name, paths in need.items():
    if len(hooks.get(name, [])) != 1:
        sys.exit(f'ERROR: .pre-commit-config.yaml must define the hook {name} exactly once.')
    files, exclude = hooks[name][0].get('files'), hooks[name][0].get('exclude')
    for path in paths:
        if (files and not files.search(path)) or any(e and e.search(path) for e in (exclude, top_exclude)):
            missed.append(f'{name} does not run on {path}')
# Shell sources the target table names stay linted under their native
# names; upstream and app-written bytes never reach a fixing hook.
TERMINAL = 'home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'
UPSTREAM = {'.p10k.zsh': 'home/dot_p10k.zsh', '.local/bin/my-fzf-preview.sh': 'home/dot_local/bin/executable_my-fzf-preview.sh'}
RENDERED_ONLY = set(UPSTREAM) | {'.local/bin/claude-limited', '.xprofile'}
def selects(variant, path):
    files, exclude = variant.get('files'), variant.get('exclude')
    return bool((files is None or files.search(path)) and not any(e and e.search(path) for e in (exclude, top_exclude)))
for name, paths in (('trailing-whitespace', [*UPSTREAM.values(), TERMINAL]), ('end-of-file-fixer', [*UPSTREAM.values(), TERMINAL]),
                    ('shellcheck', [UPSTREAM['.local/bin/my-fzf-preview.sh']]), ('shfmt', list(UPSTREAM.values()))):
    for path in paths:
        if any(selects(variant, path) for variant in hooks.get(name, [])):
            missed.append(f'{name} would rewrite or lint {path}')
# A variant without its own types inherits the upstream `types: [shell]`;
# identify gives dot_ names no shell tag, so it would silently skip
# home/dot_bashrc. Every variant sets `types: [file]` instead.
for name in ('shellcheck', 'shfmt'):
    for number, variant in enumerate(hooks.get(name, []), 1):
        if variant.get('types') != ['file']:
            missed.append(f'{name} variant {number} does not set types: [file]')
def lints(variant, path):
    return variant.get('types') == ['file'] and selects(variant, path)
ROLES = ('common-only', 'mac', 'wsl-ubuntu', 'lab-ubuntu', 'sherlock', 'marlowe', 'win')
rows = [line.split('\t') for line in open(sys.argv[3], encoding='ascii').read().splitlines() if line and not line.startswith('#')][1:]
for target, hosts, source, _mode, shell in rows:
    if shell == '-' or target in RENDERED_ONLY:
        continue
    roles = ROLES if hosts == 'all' else ROLES[:-1] if hosts == 'unix' else hosts.split(',')
    for path in sorted({source.replace('{host}', role) for role in roles}):
        for name in (('shfmt', 'shellcheck') if shell in ('sh', 'bash') else ('shfmt',)):
            if not any(lints(variant, path) for variant in hooks.get(name, [])):
                missed.append(f'{name} does not lint {path}')
runner = open(sys.argv[2], encoding='utf-8').read()
runner_suites = re.search(r'tests=\(\n(.*?)\n\)', runner, re.S).group(1).split()
entries = {hook.get('entry') for variants in hooks.values() for hook in variants}
for suite in runner_suites:
    if 'tests/' + suite not in entries:
        missed.append(f'Linux pre-commit behavior pass omits {suite}')
if missed:
    sys.exit('ERROR: ' + '; '.join(missed))
PY

printf 'test-entrypoints=PASS\n'
