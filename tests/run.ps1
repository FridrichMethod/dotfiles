#Requires -Version 7.0
# Native test entrypoint. Every assigned suite is mandatory; no profile is loaded.
[CmdletBinding()]
param([switch]$CI, [switch]$CheckPrerequisites)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

# Hermetic: the provisioning exports (DOTFILES_AUTO_UPDATE=0 and the like,
# docs/bootstrap.md) and other dotfiles knobs never reach the suites from the
# caller; each case sets what it needs. The same list as tests/*.sh.
foreach ($knob in @('DOTFILES_AUTO_UPDATE', 'DOTFILES_AUTO_STOW', 'DOTFILES_HOST', 'DOTFILES_DIR',
        '_DOTFILES_CHECKED', 'DOTFILES_STOW_WITHOUT_OH_MY_ZSH', 'DOTFILES_COLOR',
        'AWESOME_SKILLS_AUTO_UPDATE', 'AWESOME_SKILLS_FORCE', 'AWESOME_SKILLS_BG',
        'AWESOME_SKILLS_INSTALLER_URL', 'AWESOME_SKILLS_REFRESH_DAYS', '_AWESOME_SKILLS_CHECKED',
        'CODING_AGENT_KIT_CONFIG', 'CODING_AGENT_KIT_COLOR')) {
    Remove-Item -LiteralPath "Env:$knob" -ErrorAction Ignore
}

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

Write-Output '==> test_ai_integration.py'
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'test_ai_integration.py') -PathType Leaf)) {
    throw 'Required AI integration test suite is missing.'
}
& $syncPython -I -B -m unittest discover -s $PSScriptRoot -p 'test_ai_integration.py' -v
if ($LASTEXITCODE -ne 0) { throw 'AI integration tests failed.' }

# Real-data overlay, as in tests/ai-integration.sh: the Claude helper suite of
# the pinned coding-agent-kit tree runs again with the real settings.json in
# place of its frozen fixture. Windows uses the bsdtar in System32 by full
# path, so Git for Windows' GNU tar, which reads C: in an archive path as a
# remote host, is never picked up from PATH.
Write-Output '==> real-data overlay of coding-agent-kit'
$kit = Join-Path ([IO.Path]::GetTempPath()) "dotfiles-kit-$PID"
$tar = "$kit.tar"
[void][IO.Directory]::CreateDirectory($kit)
try {
    & git -C (Join-Path $repoRoot 'common/coding-agent-kit/coding-agent-kit') archive --format=tar -o $tar HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Could not export the coding-agent-kit tree.' }
    $tarExe = if ($IsWindows) { Join-Path $env:SystemRoot 'System32\tar.exe' } else { 'tar' }
    & $tarExe -xf $tar -C $kit
    if ($LASTEXITCODE -ne 0) { throw 'Could not unpack the coding-agent-kit tree.' }
    Copy-Item -LiteralPath (Join-Path $repoRoot 'common/claude/.claude/settings.json') (Join-Path $kit 'tests/fixtures/claude-settings.json')
    & node --test (Join-Path $kit 'tests/claude-customizations.cjs')
    if ($LASTEXITCODE -ne 0) { throw 'Claude customization tests failed on the real data.' }
}
finally {
    Remove-Item -LiteralPath $kit, $tar -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output '==> test_bootstrap_manifest.py'
& $syncPython -I -B -m unittest discover -s $PSScriptRoot -p 'test_bootstrap_manifest.py' -v
if ($LASTEXITCODE -ne 0) { throw 'Bootstrap manifest validator tests failed.' }

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

Write-Output '==> powershell-profile.ps1'
& $powerShell -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'powershell-profile.ps1')
if ($LASTEXITCODE -ne 0) { throw 'PowerShell profile tests failed.' }

Write-Output '==> windows-installer-controls.ps1'
& $powerShell -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'windows-installer-controls.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Windows installer confirmation and failure-control tests failed.' }

Write-Output '==> bootstrap.ps1'
& $powerShell -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'bootstrap.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Windows bootstrap doctor and installer tests failed.' }

Write-Output '==> e2e/run.ps1 parse gate'
# The native Windows end-to-end driver runs only in the opt-in bootstrap-e2e
# workflow (90 minutes, against the runner's real home), so a syntax error in
# it would otherwise surface there first. Parsing every file here, with the
# parser each other PowerShell suite uses, is the fast signal; e2e-harness.ps1
# below then drives its behaviour against stubs.
$e2eRun = Join-Path $PSScriptRoot 'e2e/run.ps1'
if (-not (Test-Path -LiteralPath $e2eRun -PathType Leaf)) { throw "Windows e2e driver is missing: $e2eRun" }
$e2eLibs = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'e2e/lib') -Filter '*.ps1' -File |
        Sort-Object -Property Name | ForEach-Object { $_.FullName })
if ($e2eLibs.Count -eq 0) { throw 'No tests/e2e/lib/*.ps1 found to parse.' }
$e2eParseIssues = [Collections.Generic.List[string]]::new()
foreach ($e2eFile in (@($e2eRun) + $e2eLibs)) {
    $e2eErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($e2eFile, [ref]$null, [ref]$e2eErrors)
    foreach ($issue in @($e2eErrors)) {
        $e2eParseIssues.Add("$($e2eFile):$($issue.Extent.StartLineNumber):$($issue.Message)")
    }
    Write-Output "parsed $e2eFile"
}
if ($e2eParseIssues.Count -gt 0) { throw "Windows e2e driver parse errors:`n$($e2eParseIssues -join "`n")" }

Write-Output '==> e2e-harness.ps1'
& $powerShell -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'e2e-harness.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Windows e2e driver unit tests failed.' }

if ($IsWindows) {
    Write-Output '==> windows-installer.ps1'
    & $powerShell -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'windows-installer.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Native Windows installer tests failed.' }
}
else {
    Write-Output 'SKIP: native NTFS installer integration requires Windows (mandatory in Windows CI).'
}

Write-Output 'test-suite=PASS'
