#!/bin/bash

set -euo pipefail

# Hermetic: the provisioning exports (DOTFILES_AUTO_UPDATE=0 and the like,
# docs/bootstrap.md) and other dotfiles knobs never reach the code under
# test from the caller; each case sets what it needs.
unset DOTFILES_AUTO_UPDATE DOTFILES_AUTO_STOW DOTFILES_HOST DOTFILES_DIR _DOTFILES_CHECKED \
    DOTFILES_STOW_WITHOUT_OH_MY_ZSH DOTFILES_COLOR AWESOME_SKILLS_AUTO_UPDATE AWESOME_SKILLS_FORCE \
    AWESOME_SKILLS_BG AWESOME_SKILLS_INSTALLER_URL AWESOME_SKILLS_REFRESH_DAYS _AWESOME_SKILLS_CHECKED

# Unix contract checks supplement tests/windows-installer.ps1, which exercises
# actual links and helper processes in the native Windows CI job. A normal
# hosted job cannot establish SSH network-logon reparse-point trust.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$REPO_ROOT/stow-all.ps1"

# A local open cannot detect RedirectionGuard rejection in an SSH process.
# The shared helper must enable enforcement only in a disposable child, and
# the installer must consume its native errors for sources and destinations.
grep -Fq 'Get-DotfilesLinkReadErrors -Paths $probePaths.ToArray()' "$INSTALLER"
grep -Fq '$linkError -ne 448' "$INSTALLER"
grep -Fq '$sourceError -eq 448' "$INSTALLER"
grep -Fq -- '-Value @($item.Target)[0] -Force -Confirm:$false' "$INSTALLER"
grep -Fq 'SetProcessMitigationPolicy(16, ref flags' "$REPO_ROOT/lib/windows-link-trust.ps1"
grep -Fq '$start.RedirectStandardInput = $true' "$REPO_ROOT/lib/windows-link-trust.ps1"

if ! grep -Fq 'Repair untrusted symlink' "$INSTALLER"; then
    echo "ERROR: installer must repair untrusted symlinks, not skip them" >&2
    exit 1
fi

# Only an elevated token creates a trusted link, so an unelevated run must warn
# instead of rewriting a link into an equally untrusted one.
grep -Fq '$script:IsElevated' "$INSTALLER"
if ! grep -Fq 'untrusted symlink left in place' "$INSTALLER"; then
    echo "ERROR: unelevated run must warn about untrusted symlinks it kept" >&2
    exit 1
fi
if ! grep -Fq 'created from a non-elevated session are' "$INSTALLER"; then
    echo "ERROR: unelevated run must warn about untrusted links it created" >&2
    exit 1
fi
grep -Fq 'repaired: $script:Repaired' "$INSTALLER"

# Isolated targets and validation-only helper calls are part of the installer
# contract. Native behavior tests exercise them; these guard Unix-only runs.
grep -Fq '[string]$TargetRoot' "$INSTALLER"
grep -Fq 'foreach ($sync in $syncPlan) { Invoke-PortableSync @sync -CheckOnly }' "$INSTALLER"
grep -Fq 'if ($recordAppliedState -and -not $WhatIfPreference' "$INSTALLER"
grep -Fq "Unsupported Windows host:" "$INSTALLER"

# The help text and README must not send anyone back to the unelevated path.
if grep -Fq 'symlinks can be created without an elevated prompt' "$INSTALLER"; then
    echo "ERROR: installer help still recommends the unelevated path" >&2
    exit 1
fi
if grep -Fq 'so symlinks need no elevation' "$REPO_ROOT/README.md"; then
    echo "ERROR: README still recommends the unelevated path" >&2
    exit 1
fi
grep -Fq 'untrusted mount point' "$REPO_ROOT/README.md"

# Windows Terminal rewrites the stowed settings.json through its link when it
# loads a file that is not in its own form: it adds a stub for each built-in
# profile missing from profiles.list (the e2e win row saw it on its first
# CI run). Keep both stubs, and the strict JSON, ASCII and never-disabled
# PowerShell 7 source that AGENTS.md asks of this file.
python3 - "$REPO_ROOT/win/terminal/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json" <<'PY'
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
listed = {profile.get('guid') for profile in settings['profiles']['list']}
missing = [name for guid, name in builtin.items() if guid not in listed]
if missing:
    sys.exit(f'ERROR: {path} lacks the built-in Windows Terminal profile stubs: {", ".join(missing)}')
if 'Windows.Terminal.PowershellCore' in settings.get('disabledProfileSources', []):
    sys.exit(f'ERROR: {path} disables Windows.Terminal.PowershellCore')
PY

# AGENTS.md is the single repository guide; CLAUDE.md only imports it.
if ! grep -Fq 'untrusted mount point' "$REPO_ROOT/AGENTS.md"; then
    echo "ERROR: AGENTS.md is missing the untrusted-symlink rule" >&2
    exit 1
fi
if [[ "$(head -n1 "$REPO_ROOT/CLAUDE.md")" != '@AGENTS.md' ]]; then
    echo "ERROR: CLAUDE.md must start with @AGENTS.md so Claude Code imports the shared guide" >&2
    exit 1
fi

# Parse both the installer and native fixture when PowerShell is installed.
# The paths travel through the environment because -Command does not populate
# $args, which previously let a null path escape this check.
if command -v pwsh >/dev/null 2>&1; then
    for ps_file in "$INSTALLER" "$REPO_ROOT/tests/windows-installer.ps1" \
        "$REPO_ROOT/setup-sync.ps1" "$REPO_ROOT/tests/run.ps1" \
        "$REPO_ROOT/lib/terminal.ps1" "$REPO_ROOT/tests/terminal.ps1" \
        "$REPO_ROOT/lib/windows-link-trust.ps1" "$REPO_ROOT/tests/windows-installer-controls.ps1"; do
        INSTALLER_PATH="$ps_file" pwsh -NoProfile -NonInteractive -Command '
        $path = $env:INSTALLER_PATH
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Output "installer not found at $path"
            exit 1
        }
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $path, [ref]$null, [ref]$errors)
        if ($errors) { $errors | ForEach-Object { $_.ToString() }; exit 1 }
    '
    done
    pwsh -NoProfile -NonInteractive -File "$REPO_ROOT/tests/terminal.ps1"
    pwsh -NoProfile -NonInteractive -File "$REPO_ROOT/tests/windows-installer-controls.ps1"
else
    printf 'SKIP: Windows installer/native fixture parse checks (pwsh unavailable).\n'
fi

echo "windows-installer=PASS"
