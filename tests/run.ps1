#Requires -Version 7.0
# Native test entrypoint. Every assigned suite is mandatory; no profile is loaded.
[CmdletBinding()]
param([switch]$CI, [switch]$CheckPrerequisites)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ($CI -and -not $IsWindows) {
    throw 'The native Windows CI entrypoint requires Windows.'
}

foreach ($dependency in @('git', 'node')) {
    if (-not (Get-Command $dependency -CommandType Application -ErrorAction SilentlyContinue)) {
        throw "Required test dependency not found: $dependency"
    }
}
$powerShell = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
if (-not (Test-Path -LiteralPath $powerShell -PathType Leaf)) {
    throw "Cannot locate the current PowerShell executable: $powerShell"
}
$repoRoot = Split-Path -Parent $PSScriptRoot
$syncPython = if ($env:DOTFILES_SYNC_PYTHON) { $env:DOTFILES_SYNC_PYTHON }
    elseif ($IsWindows) { Join-Path $repoRoot '.venv-sync/Scripts/python.exe' }
    else { Join-Path $repoRoot '.venv-sync/bin/python' }
if (-not (Test-Path -LiteralPath $syncPython -PathType Leaf)) {
    throw 'AI-sync runtime missing; run setup-sync.ps1 explicitly.'
}
$env:DOTFILES_SYNC_PYTHON = $syncPython
& $syncPython -I -B (Join-Path $repoRoot 'lib/config_sync.py') --runtime-check
if ($LASTEXITCODE -ne 0) { throw 'Configuration runtime check failed.' }
if ($CheckPrerequisites) {
    Write-Output 'test-prerequisites=PASS'
    exit 0
}

Write-Output '==> test_config_sync.py'
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'test_config_sync.py') -PathType Leaf)) {
    throw 'Required configuration backend test suite is missing.'
}
& $syncPython -I -B -m unittest discover -s $PSScriptRoot -p 'test_config_sync.py' -v
if ($LASTEXITCODE -ne 0) { throw 'Configuration backend tests failed.' }

Write-Output '==> claude-customizations.cjs'
& node --test (Join-Path $PSScriptRoot 'claude-customizations.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Claude customization tests failed.' }

Write-Output '==> terminal.ps1'
& $powerShell -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'terminal.ps1')
if ($LASTEXITCODE -ne 0) { throw 'PowerShell terminal-output tests failed.' }

Write-Output '==> update-hooks.ps1'
# Use a child process so fixtures cannot leak mock functions or global state.
& $powerShell -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'update-hooks.ps1')
if ($LASTEXITCODE -ne 0) { throw 'PowerShell update-hook tests failed.' }

Write-Output '==> windows-installer-controls.ps1'
& $powerShell -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'windows-installer-controls.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Windows installer confirmation and failure-control tests failed.' }

if ($IsWindows) {
    Write-Output '==> windows-installer.ps1'
    & $powerShell -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'windows-installer.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Native Windows installer tests failed.' }
}
else {
    Write-Output 'SKIP: native NTFS installer integration requires Windows (mandatory in Windows CI).'
}

Write-Output 'test-suite=PASS'
