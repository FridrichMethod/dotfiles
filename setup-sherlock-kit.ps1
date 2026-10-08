#Requires -Version 7.0
# Explicit frozen toolkit install; no login or automatic update invocation.
# -StateRoot records an absolute local locator without creating its directory.
[CmdletBinding()]
param([string]$Python = 'python', [string]$Source, [string]$TargetHome = $HOME, [string]$StateRoot)
$ErrorActionPreference = 'Stop'
$SetupArguments = @('-I', '-B', (Join-Path $PSScriptRoot 'lib/sherlock_kit_integration.py'), '--install', '--target-home', $TargetHome)
if ($Source) { $SetupArguments += @('--source', $Source) }
if ($PSBoundParameters.ContainsKey('StateRoot')) { $SetupArguments += @('--state-root', $StateRoot) }
& $Python @SetupArguments
if ($LASTEXITCODE -ne 0) { throw 'Pinned sherlock-kit installation failed; active revision was not advanced.' }
