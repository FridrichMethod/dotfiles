#Requires -Version 7.0
# Native test entrypoint. Every assigned suite is mandatory; no profile is loaded.
[CmdletBinding()]
param([switch]$CI, [switch]$CheckPrerequisites)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

. (Join-Path $PSScriptRoot 'lib/environment.ps1')

if ($CI -and -not $IsWindows) {
    throw 'The native Windows CI entrypoint requires Windows.'
}

foreach ($dependency in @('git', 'node', 'python')) {
    if (-not (Get-Command $dependency -CommandType Application -ErrorAction SilentlyContinue)) {
        throw "Required test dependency not found: $dependency"
    }
}
# The suites import stdlib tomllib; AGENTS.md sets the Python 3.11+ floor.
& python -I -B -c 'import sys; sys.exit(sys.version_info < (3, 11))'
if ($LASTEXITCODE -ne 0) { throw 'Required test dependency python is not Python 3.11 or newer.' }
$powerShell = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
if (-not (Test-Path -LiteralPath $powerShell -PathType Leaf)) {
    throw "Cannot locate the current PowerShell executable: $powerShell"
}
if (Test-Path Env:DOTFILES_TEST_CHEZMOI) {
    if (-not (Test-Path -LiteralPath $env:DOTFILES_TEST_CHEZMOI -PathType Leaf)) {
        throw 'Invalid DOTFILES_TEST_CHEZMOI executable path.'
    }
}
elseif (-not (Get-Command chezmoi -CommandType Application -ErrorAction SilentlyContinue)) {
    if ($CI -or $env:DOTFILES_TEST_REQUIRE_CHEZMOI -eq '1') {
        throw 'CI requires chezmoi for native fixture tests.'
    }
    Write-Output 'SKIP: native chezmoi fixtures (install the selected release or set DOTFILES_TEST_CHEZMOI).'
}
if ($CI) { $env:DOTFILES_TEST_REQUIRE_CHEZMOI = '1' }
if ($CheckPrerequisites) {
    Write-Output 'test-prerequisites=PASS'
    exit 0
}

Write-Output '==> chezmoi.ps1'
& $powerShell -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'chezmoi.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Native chezmoi fixture tests failed.' }

Write-Output '==> test_environment.py'
& python -I -B -m unittest discover -s $PSScriptRoot -p 'test_environment.py' -v
if ($LASTEXITCODE -ne 0) { throw 'Test environment isolation checks failed.' }

Write-Output '==> test_ai_integration.py'
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'test_ai_integration.py') -PathType Leaf)) {
    throw 'Required AI integration test suite is missing.'
}
& python -I -B -m unittest discover -s $PSScriptRoot -p 'test_ai_integration.py' -v
if ($LASTEXITCODE -ne 0) { throw 'AI integration tests failed.' }

Write-Output '==> test_ai_policy.py'
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'test_ai_policy.py') -PathType Leaf)) {
    throw 'Required AI policy test suite is missing.'
}
# Standard library only, so the plain interpreter runs it.
& python -I -B -m unittest discover -s $PSScriptRoot -p 'test_ai_policy.py' -v
if ($LASTEXITCODE -ne 0) { throw 'Portable AI policy tests failed.' }

Write-Output '==> test_bootstrap_manifest.py'
& python -I -B -m unittest discover -s $PSScriptRoot -p 'test_bootstrap_manifest.py' -v
if ($LASTEXITCODE -ne 0) { throw 'Bootstrap manifest validator tests failed.' }

Write-Output '==> claude-customizations.cjs'
& node --test (Join-Path $PSScriptRoot 'claude-customizations.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Claude customization tests failed.' }

Write-Output '==> terminal.ps1'
& $powerShell -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'terminal.ps1')
if ($LASTEXITCODE -ne 0) { throw 'PowerShell terminal-output tests failed.' }

Write-Output '==> test_payload_download.py'
& python -I -B (Join-Path $PSScriptRoot 'test_payload_download.py')
if ($LASTEXITCODE -ne 0) { throw 'Payload loopback download tests failed.' }

Write-Output '==> payload-update.ps1'
& $powerShell -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'payload-update.ps1')
if ($LASTEXITCODE -ne 0) { throw 'PowerShell payload hook tests failed.' }

Write-Output '==> powershell-profile.ps1'
& $powerShell -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'powershell-profile.ps1')
if ($LASTEXITCODE -ne 0) { throw 'PowerShell profile tests failed.' }

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

Write-Output 'test-suite=PASS'
