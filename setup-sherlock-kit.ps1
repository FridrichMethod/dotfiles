#Requires -Version 7.0
# Explicit frozen toolkit install; no login or automatic update invocation.
[CmdletBinding()]
param([string]$Python = 'python', [string]$Source, [string]$TargetHome = $HOME)
$ErrorActionPreference = 'Stop'
$SetupArguments = @('-I', '-B', (Join-Path $PSScriptRoot 'lib/sherlock_kit_integration.py'), '--install', '--target-home', $TargetHome)
if ($Source) { $SetupArguments += @('--source', $Source) }
& $Python @SetupArguments
if ($LASTEXITCODE -ne 0) { throw 'Pinned sherlock-kit installation failed; active revision was not advanced.' }
