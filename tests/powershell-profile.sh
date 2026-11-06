#!/bin/bash

set -euo pipefail

# Isolate inherited configuration while preserving explicit test inputs.
# shellcheck source=tests/lib/environment.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/environment.sh"

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Windows Terminal rewrites settings.json when it loads a file that is not in
# its own form: it adds a stub for each built-in profile missing from
# profiles.list (the e2e win row saw it on its first CI run). Keep both stubs
# hidden: Terminal treats a generated profile that state.json lists but
# settings.json omits as deleted, so a visible stub would bring them back on
# hosts that already dropped them. Also keep the strict JSON, ASCII and
# never-disabled PowerShell 7 source that AGENTS.md asks of this file. This
# needs only Python, so it runs where pwsh is missing too.
python3 -I -B - "$REPO_ROOT/win/terminal/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json" <<'PY'
import json
import sys

path = sys.argv[1]
raw = open(path, 'rb').read()
try:
    raw.decode('ascii')
except UnicodeDecodeError as error:
    sys.exit(f'ERROR: {path} is not ASCII: {error}')
settings = json.loads(raw)
builtin = {'{61c54bbd-c2c6-5271-96e7-009a87ff44bf}': 'Windows PowerShell',
           '{0caa0dad-35be-5f56-a8ff-afceeeaa6101}': 'Command Prompt'}
listed = {profile.get('guid'): profile for profile in settings['profiles']['list']}
missing = [name for guid, name in builtin.items() if guid not in listed]
if missing:
    sys.exit(f'ERROR: {path} lacks the built-in Windows Terminal profile stubs: {", ".join(missing)}')
shown = [name for guid, name in builtin.items() if listed[guid].get('hidden') is not True]
if shown:
    sys.exit(f'ERROR: {path} does not hide the built-in Windows Terminal profile stubs: {", ".join(shown)}')
if 'Windows.Terminal.PowershellCore' in settings.get('disabledProfileSources', []):
    sys.exit(f'ERROR: {path} disables Windows.Terminal.PowershellCore')
print('windows-terminal-settings=PASS')
PY

if ! command -v pwsh >/dev/null 2>&1; then
    printf 'SKIP: PowerShell parse gate and profile checks (pwsh unavailable).\n'
    exit 0
fi

# Parse the PowerShell entry points and libraries that no Unix suite runs in
# full, so a syntax error fails here before the native Windows job. One pwsh
# process reads the list from the environment, because -Command does not
# populate $args (which once let a null path escape this check). This is the
# pwsh 7 parser: Windows PowerShell 5.1 compatibility needs the Windows job.
ps_files=(
    doctor.ps1
    setup-host.ps1
    lib/chezmoi-guard.ps1
    lib/terminal.ps1
    scripts/chezmoi-update.ps1
    scripts/payload-update.ps1
    tests/run.ps1
    tests/terminal.ps1
)
PS_PARSE_ROOT="$REPO_ROOT" PS_PARSE_FILES="${ps_files[*]}" pwsh -NoProfile -NonInteractive -Command '
    $issues = [Collections.Generic.List[string]]::new()
    $names = @($env:PS_PARSE_FILES -split " " | Where-Object { $_ })
    if ($names.Count -eq 0) { $issues.Add("no PowerShell files named") }
    foreach ($name in $names) {
        $path = Join-Path $env:PS_PARSE_ROOT $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $issues.Add("${name}: missing"); continue }
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
        foreach ($issue in @($errors)) { $issues.Add("${name}:$($issue.Extent.StartLineNumber): $($issue.Message)") }
    }
    if ($issues.Count -gt 0) { $issues | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }; exit 1 }
    Write-Output "powershell-parse=PASS ($($names.Count) files)"
'

# Run the PowerShell profile and prompt theme contract.
exec pwsh -NoProfile -NonInteractive -File "$REPO_ROOT/tests/powershell-profile.ps1"
