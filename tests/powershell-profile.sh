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
python3 -I -B - "$REPO_ROOT/home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json" <<'PY'
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

# The PowerShell 7.0 floor, scanned here too because most hosts have no pwsh.
# $PSStyle came with PowerShell 7.2 and the prediction options with PSReadLine
# 2.1 and 2.2, while pwsh 7.0 to 7.2 ship PSReadLine 2.0 or 2.1. In the
# PowerShell 7 profile they may appear in code only in the body of the one
# pinned if that detects each feature, inside the interactive guard, with no
# else; the 5.1 profile uses neither. Comment lines are skipped. The pwsh
# suite checks the same rule on the AST and replays the guarded statements.
STYLE_GUARD='if (Get-Variable -Name PSStyle -ValueOnly -ErrorAction Ignore) {'
READLINE_GUARD="if ((Get-Module PSReadLine).Version -ge [version]'2.2.0' -and \$PSVersionTable.PSVersion -ge [System.Management.Automation.SemanticVersion]'7.2.0') {"

# scan_floor PATH MODE: MODE 7 requires both guards, MODE 51 neither feature.
scan_floor() {
    awk -v name="$1" -v mode="$2" -v style_guard="$STYLE_GUARD" -v readline_guard="$READLINE_GUARD" '
        function fail(message) { printf "FAIL: %s%s: %s\n", name, (ending ? "" : ":" FNR), message; bad++ }
        {
            line = $0
            sub(/\r$/, "", line)
            text = line
            sub(/^[ \t]+/, "", text)
            indent = substr(line, 1, length(line) - length(text))
            if (open != "" && substr(line, 1, length(open_indent) + 1) == open_indent "}") {
                if (line != open_indent "}") fail("the " open " guard must close on a line of its own: " text)
                open = ""
                closed = 1
                next
            }
            if (closed) {
                if (text == "" || text ~ /^#/) next
                if (text ~ /^else/) fail("a feature guard has an else branch: " text)
                closed = 0
            }
            if (text == "if ($IsInteractive -and -not $IsAgentSession) {") interactive = 1
            else if (interactive && line == "}") interactive = 0
            if (text ~ /^#/) next
            if (mode == "7" && open == "" && (text == style_guard || text == readline_guard)) {
                open = (text == style_guard) ? "PSStyle" : "PSReadLine"
                open_indent = indent
                guards[open]++
                if (!interactive) fail("the " open " guard is outside the interactive guard")
                next
            }
            lower = tolower(text)
            if (index(lower, "psstyle")) {
                if (open == "PSStyle") uses["PSStyle"]++
                else fail("$PSStyle (PowerShell 7.2) outside its guard: " text)
            }
            if (lower ~ /prediction(source|view)|(inline|list)prediction/) {
                if (open == "PSReadLine") uses["PSReadLine"]++
                else fail("a PSReadLine 2.1/2.2 prediction option outside its guard: " text)
            }
        }
        END {
            ending = 1
            if (open != "") fail("the " open " guard never closes")
            if (mode == "7") {
                seen["PSStyle"] = style_guard
                seen["PSReadLine"] = readline_guard
                for (feature in seen) {
                    if (guards[feature] != 1) fail(sprintf("%d %s guards, expected exactly one: %s", guards[feature], feature, seen[feature]))
                    if (uses[feature] < 1) fail("no " feature " use behind its guard")
                }
            }
            if (bad) exit 1
            if (mode == "7") printf "ok: %s uses $PSStyle and the PSReadLine 2.2 prediction options only behind their guards (%d and %d lines)\n", name, uses["PSStyle"], uses["PSReadLine"]
            else printf "ok: %s uses neither $PSStyle nor prediction options\n", name
        }
    ' "$REPO_ROOT/$1"
}

floor_status=0
scan_floor home/Documents/PowerShell/profile.ps1 7 || floor_status=1
scan_floor home/Documents/WindowsPowerShell/profile.ps1 51 || floor_status=1
if [ "$floor_status" -ne 0 ]; then
    printf 'PowerShell 7.0 floor scan failed.\n' >&2
    exit 1
fi

if ! command -v pwsh >/dev/null 2>&1; then
    printf 'SKIP: PowerShell parse gate and profile checks (pwsh unavailable).\n'
    exit 0
fi

# Parse the PowerShell entry points and libraries that no Unix suite runs in
# full, so a syntax error fails here before the native Windows job. One pwsh
# process reads the list from the environment, because -Command does not
# populate $args. This is the pwsh 7 parser: Windows PowerShell 5.1
# compatibility needs the Windows job.
ps_files=(
    dotfiles.ps1
    home/dot_local/bin/dotfiles.ps1
    tests/cli.ps1
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
