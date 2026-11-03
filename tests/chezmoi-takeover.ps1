#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
. (Join-Path $PSScriptRoot 'lib/environment.ps1')

& python -I -B -m unittest discover -s $PSScriptRoot -p 'test_chezmoi_takeover_windows.py' -v
if ($LASTEXITCODE -ne 0) { throw 'Windows chezmoi takeover fixtures failed.' }
