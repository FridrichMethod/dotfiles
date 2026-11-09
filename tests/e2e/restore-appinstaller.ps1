#Requires -Version 7.0
# Independent workflow cleanup after a terminated E2E driver. The durable
# receipt makes this harmless after the driver's own verified restoration.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $env:E2E_OUT) { throw 'E2E_OUT must identify this run''s output directory.' }
$output = [IO.Path]::GetFullPath($env:E2E_OUT)
if (-not [IO.File]::Exists((Join-Path $output 'appinstaller-state.json'))) { exit 0 }
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/appinstaller.ps1')
$E2E['Out'] = $output
Invoke-E2EAppInstallerRestore
if ($E2E['Fails'] -gt 0) { exit 1 }
