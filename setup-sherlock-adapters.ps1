#Requires -Version 7.0
# Explicit first-party payload delivery. Hooks are registered/trusted separately.
[CmdletBinding()]
param([string]$Python = 'python', [Parameter(Mandatory)][string]$Runtime,
    [string]$TargetHome = $HOME, [switch]$Check)
$ErrorActionPreference = 'Stop'
$SetupArguments = @('-I', '-B', (Join-Path $PSScriptRoot 'lib/sherlock_kit_integration.py'), '--install-adapters', '--runtime', $Runtime, '--target-home', $TargetHome)
if ($Check) { $SetupArguments += '--check-adapters' }
& $Python @SetupArguments
if ($LASTEXITCODE -ne 0) { throw 'First-party Sherlock adapter delivery failed; review the diagnostic.' }
