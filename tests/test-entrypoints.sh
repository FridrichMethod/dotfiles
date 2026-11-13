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
    'chezmoi fixtures'; do
    grep -Fq "SKIP: $skipped" "$TEST_TMP/local.stdout" ||
        fail_run local "tests/run.sh --check-prerequisites did not skip the $skipped."
done
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
# source it, the logger and both lib/chezmoi-guard twins, and this test on
# itself, the entry points it reads and the hook configuration. Files are
# selected as pre-commit selects them: re.search of the hook's files, then
# of its exclude and the top-level one; a shell linter must also declare its
# types.
python3 -I -B - "$REPO_ROOT/.pre-commit-config.yaml" "$TEST_DIR/run.sh" "$TEST_DIR/fixtures/chezmoi/targets.tsv" \
    "$REPO_ROOT/.github/workflows/ci.yml" "$TEST_DIR/run.ps1" "$TEST_DIR/cli.sh" "$TEST_DIR/powershell-profile.sh" <<'PY'
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
        continue
    match = re.match(r'\s+args: \[(.*)\]\s*$', line)
    if match and hook is not None:
        hook['args'] = [arg.strip().strip('\'"') for arg in match.group(1).split(',')]
need = {
    'cli': ['dotfiles', 'dotfiles.ps1', 'home/dot_local/bin/executable_dotfiles',
            'home/dot_local/bin/dotfiles.ps1', 'home/dot_aliases',
            'home/Documents/PowerShell/profile.ps1', 'tests/cli.sh', 'tests/cli.ps1',
            'tests/test_cli_unix.py', 'lib/chezmoi-guard.sh', 'lib/chezmoi-guard.ps1',
            'scripts/commands/doctor.sh', 'scripts/commands/doctor.ps1', 'scripts/commands/setup.sh', 'scripts/commands/setup.ps1',
            'scripts/commands/payloads-sync.sh', 'scripts/commands/payloads-sync.ps1',
            'tests/run.sh', 'tests/run.ps1', 'tests/lib/environment.sh', 'tests/lib/environment.ps1'],
    'ai-policy': ['tests/ai-policy.sh', 'tests/test_ai_policy.py', 'home/.policy/claude-settings.json',
                  'home/dot_claude/CLAUDE.md', 'home/dot_codex/AGENTS.md',
                  'home/dot_codex/rules/portable.rules', 'CLAUDE.md', 'AGENTS.md',
                  'tests/lib/environment.sh'],
    'payload-update': ['scripts/commands/payloads-sync.sh', 'config/payloads.tsv', 'home/dot_aliases', 'home/dot_profile',
                       'home/dot_zshrc', 'lib/terminal.sh', 'lib/chezmoi-guard.sh', 'lib/chezmoi-guard.ps1',
                       'tests/payload-update.sh', 'tests/test_payload_download.py'],
    'test-entrypoints': ['.pre-commit-config.yaml', 'tests/test-entrypoints.sh', 'tests/run.sh', 'tests/run.ps1',
                         'tests/lib/environment.sh', 'tests/lib/environment.ps1', 'tests/test_environment.py',
                         'tests/fixtures/chezmoi/targets.tsv', '.github/workflows/ci.yml'],
    'markdown-links': ['README.md', 'AGENTS.md', 'docs/bootstrap.md',
                       'tests/test_markdown_links.py', 'tests/markdown-links.sh'],
    'chezmoi': ['tests/chezmoi_support.py', 'tests/test_chezmoi_foundation.py',
                'lib/chezmoi-guard.sh', 'lib/chezmoi-guard.ps1',
                'scripts/chezmoi-update.sh', 'scripts/chezmoi-update.ps1',
                'scripts/commands/payloads-sync.sh', '.gitignore',
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
                'tests/test_chezmoi_modify.py', 'tests/test_chezmoi_secrets.py',
                'tests/fixtures/chezmoi/modify/modify_private_settings.json',
                'tests/fixtures/chezmoi/secrets/README.md', 'tests/chezmoi.sh',
                'tests/chezmoi.ps1', 'tests/lib/environment.sh', 'tests/lib/environment.ps1',
                '.github/scripts/install-test-chezmoi.py', 'lib/bootstrap/platform.sh',
                'lib/bootstrap/checks.sh', 'lib/bootstrap/steps-human.sh',
                'scripts/commands/doctor.sh', 'scripts/commands/setup.sh'],
    'e2e-harness': ['tests/e2e-harness.sh', 'tests/e2e/inside.sh', 'tests/e2e/lib/blocks.sh',
                    'tests/e2e/lib/steps.sh', 'docs/bootstrap.md', 'config/bootstrap/installers.tsv',
                    '.chezmoiversion', 'lib/bootstrap/steps-common.sh', 'lib/chezmoi-guard.sh'],
    'shell-profile': ['home/dot_profile', 'home/dot_aliases', 'home/dot_zshrc', 'home/dot_oh-my-zsh/custom/nvm.zsh',
                      'home/dot_oh-my-zsh/custom/fzf-tab.zsh', 'lib/chezmoi-guard.sh'],
    'terminal-output': ['lib/terminal.sh', 'lib/terminal.ps1', 'tests/terminal.ps1', 'scripts/commands/doctor.ps1', 'scripts/commands/setup.ps1'],
    'powershell-profile': ['lib/chezmoi-guard.ps1', 'scripts/commands/payloads-sync.ps1', 'tests/powershell-profile.sh',
                           'scripts/commands/doctor.ps1', 'scripts/commands/setup.ps1', 'lib/terminal.ps1', 'scripts/chezmoi-update.ps1',
                           'tests/run.ps1', 'tests/terminal.ps1', 'dotfiles.ps1',
                           'home/dot_local/bin/dotfiles.ps1', 'tests/cli.ps1',
                           'home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/'
                           'LocalState/settings.json', 'home/Documents/PowerShell/profile.ps1',
                           'home/Documents/WindowsPowerShell/profile.ps1',
                           'home/dot_config/oh-my-posh/prompt.omp.json', 'home/dot_zshrc'],
    'doctor': ['scripts/commands/doctor.sh', 'lib/terminal.sh', 'lib/chezmoi-guard.sh'],
    'setup-host': ['scripts/commands/setup.sh', 'lib/terminal.sh', 'lib/chezmoi-guard.sh'],
    'bootstrap-windows': ['scripts/commands/doctor.ps1', 'scripts/commands/setup.ps1',
                          'lib/bootstrap.ps1', 'lib/terminal.ps1', 'lib/chezmoi-guard.ps1'],
    'bootstrap-manifest': ['dotfiles', 'scripts/commands/doctor.sh', 'scripts/commands/setup.sh',
                           'scripts/commands/doctor.ps1', 'scripts/commands/setup.ps1'],
    'e2e-harness-windows': ['tests/e2e-harness-windows.sh', 'tests/e2e-harness.ps1',
                            'tests/e2e/run.ps1', 'tests/e2e/lib/steps.ps1', 'tests/e2e/lib/flow-win.ps1',
                            'docs/bootstrap.md', 'lib/chezmoi-guard.ps1', 'scripts/commands/setup.ps1'],
    'tmux-config': ['home/dot_tmux.conf', 'home/dot_config/tmux/metric.py', 'home/dot_config/tmux/modern.conf'],
    'claude-customizations': ['home/.policy/claude-settings.json', 'tests/claude-customizations.cjs'],
    'ai-integration': ['.claude/settings.json', 'home/.policy/claude-settings.json', 'home/dot_zsh_aliases',
                       'home/dot_bash_aliases', 'home/dot_oh-my-zsh/custom/fzf-tab.zsh'],
    'host-overlays': ['home/.hosts/wsl-ubuntu/.config/bash/.bashrc', 'home/.hosts/lab-ubuntu/.config/zsh/.zshrc',
                      'home/.hosts/mac/.config/sh/.profile', 'home/dot_aliases'],
}
need['payload-update'].append('scripts/commands/payloads-sync.ps1')
need['chezmoi'].append('scripts/commands/payloads-sync.ps1')
need['shell-profile'].extend(['dotfiles', 'scripts/commands/payloads-sync.sh'])
for hook_id, suffix, frontend in (('e2e-harness', 'sh', 'dotfiles'),
                                  ('e2e-harness-windows', 'ps1', 'dotfiles.ps1')):
    need[hook_id].extend([frontend, *(f'scripts/commands/{command}.{suffix}'
                                    for command in ('doctor', 'setup', 'payloads-sync'))])
missed = []
for name, excluded, checked in (
    ('check-json', ['home/dot_claude/modify_private_settings.json',
                    'tests/fixtures/chezmoi/modify/modify_private_settings.json'],
                   ['home/.policy/claude-settings.json', 'home/.chezmoidata/codex-policy.json',
                    'home/dot_claude/ordinary.json',
                    'home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json',
                    'home/dot_codex/pets/tom/pet.json', 'home/dot_config/oh-my-posh/prompt.omp.json']),
    ('check-toml', ['home/dot_codex/modify_private_config.toml',
                    'tests/fixtures/chezmoi/modify/modify_private_config.toml'],
                   ['home/.policy/codex-config.toml', 'home/dot_codex/ordinary.toml']),
):
    exclude = hooks[name][0].get('exclude')
    for path in excluded:
        if not exclude or not exclude.search(path):
            missed.append(f'{name} attempts to parse modify template {path}')
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
# Shell sources the target table names stay linted under their source
# names; upstream and app-written bytes never reach a fixing hook.
TERMINAL = 'home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'
UPSTREAM = {'.p10k.zsh': 'home/dot_p10k.zsh', '.local/bin/my-fzf-preview.sh': 'home/dot_local/bin/executable_my-fzf-preview.sh'}
RENDERED_ONLY = set(UPSTREAM) | {'.xprofile'}
def selects(variant, path):
    files, exclude = variant.get('files'), variant.get('exclude')
    return bool((files is None or files.search(path)) and not any(e and e.search(path) for e in (exclude, top_exclude)))
# Retired production paths must not remain in behavior-hook dispatch maps.
# Retained tests/doctor.sh and tests/setup-host.sh are distinct valid suites.
retired = [f'{command}.{suffix}' for command in ('doctor', 'setup-host')
           for suffix in ('sh', 'ps1')]
retired += [f'scripts/payload-update.{suffix}' for suffix in ('sh', 'ps1')]
for name in ('cli', 'chezmoi', 'terminal-output', 'payload-update', 'powershell-profile',
             'bootstrap-manifest', 'doctor', 'setup-host', 'bootstrap-windows',
             'e2e-harness', 'e2e-harness-windows'):
    for path in retired:
        if any(selects(variant, path) for variant in hooks[name]):
            missed.append(f'{name} still selects retired production path {path}')
for path, dialect in (('dotfiles', 'posix'), ('scripts/commands/payloads-sync.sh', 'posix'),
                      ('scripts/commands/doctor.sh', 'bash'), ('scripts/commands/setup.sh', 'bash')):
    selected = [variant for variant in hooks['shfmt'] if selects(variant, path)]
    if len(selected) != 1 or selected[0].get('args', [])[-2:] != ['-ln', dialect]:
        missed.append(f'{path} must select exactly one shfmt {dialect} variant')
    if not any(selects(variant, path) for variant in hooks['shellcheck']):
        missed.append(f'shellcheck does not lint {path}')
for name, paths in (('trailing-whitespace', [*UPSTREAM.values(), TERMINAL]), ('end-of-file-fixer', [*UPSTREAM.values(), TERMINAL]),
                    ('shellcheck', [UPSTREAM['.local/bin/my-fzf-preview.sh']]), ('shfmt', list(UPSTREAM.values()))):
    for path in paths:
        if any(selects(variant, path) for variant in hooks.get(name, [])):
            missed.append(f'{name} would rewrite or lint {path}')
# A variant without its own types inherits the upstream `types: [shell]`;
# identify gives dot_ names no shell tag, so it would silently skip
# home/dot_bashrc. Every variant sets `types: [file]` instead.
for name in ('shellcheck', 'shfmt'):
    if not any(selects(variant, 'dotfiles') for variant in hooks.get(name, [])):
        missed.append(f'{name} does not lint the root Unix dispatcher')
    for number, variant in enumerate(hooks.get(name, []), 1):
        if variant.get('types') != ['file']:
            missed.append(f'{name} variant {number} does not set types: [file]')
def lints(variant, path):
    return variant.get('types') == ['file'] and selects(variant, path)
ROLES = ('generic', 'mac', 'wsl-ubuntu', 'lab-ubuntu', 'sherlock', 'marlowe', 'win')
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
if len(runner_suites) != len(set(runner_suites)) or runner_suites.count('cli.sh') != 1:
    missed.append('tests/run.sh must select each suite once, including cli.sh')
# The CLI hook owns the optional Unix PowerShell run. The profile hook parses
# the files without running the CLI suite a second time in a full check.
cli_runner = open(sys.argv[6], encoding='utf-8').read()
windows_runner = open(sys.argv[5], encoding='utf-8').read()
profile_runner = open(sys.argv[7], encoding='utf-8').read()
if len(re.findall(r'^python3 .*test_cli_unix[.]py', cli_runner, re.M)) != 1:
    missed.append('cli.sh must run the Unix CLI suite exactly once')
if len(re.findall(r'^    pwsh .*cli[.]ps1', cli_runner, re.M)) != 1:
    missed.append('cli.sh must run the optional PowerShell CLI suite exactly once')
if len(re.findall(r'^& \$powerShell .*PSScriptRoot \'cli[.]ps1\'', windows_runner, re.M)) != 1:
    missed.append('run.ps1 must run the native PowerShell CLI suite exactly once')
if re.search(r'^.*(?:-File|&).*tests/cli[.]ps1', profile_runner, re.M):
    missed.append('powershell-profile.sh must not duplicate the CLI behavior suite')
entries = {hook.get('entry') for variants in hooks.values() for hook in variants}
for suite in runner_suites:
    if 'tests/' + suite not in entries:
        missed.append(f'Linux pre-commit behavior pass omits {suite}')
# The Linux job alone has a real tmux, from apt, and requires it, so its
# cases fail instead of skipping.
# Comments are dropped and backslash continuations joined before matching.
workflow = re.sub(r'\\\n\s*', ' ', re.sub(r'(?m)^\s*#.*\n|\s+#.*$', '', open(sys.argv[4], encoding='utf-8').read()))
linux = re.search(r'\n  linux:\n(.*?)\n  [a-z]+:\n', workflow, re.S)
linux = linux.group(1) if linux else ''
if 'DOTFILES_TEST_REQUIRE_TMUX: "1"' not in linux:
    missed.append('ci.yml: the Linux job does not set DOTFILES_TEST_REQUIRE_TMUX: "1"')
if not re.search(r'\bapt(?:-get)?\b[^\n]*\binstall\b[^\n]*\btmux\b', linux):
    missed.append('ci.yml: the Linux job does not apt-get install tmux')
if missed:
    sys.exit('ERROR: ' + '; '.join(missed))
PY

printf 'test-entrypoints=PASS\n'
