#Requires -Version 5.1
# Native WinRT projection is built into Windows PowerShell 5.1. This worker
# changes only one hosted runner package's pause, never system policy.
[CmdletBinding()]
param([ValidateSet('Capture', 'Preflight', 'Pause', 'Resume')][string]$Action,
    [Parameter(Mandatory)][string]$OutputPath, [Parameter(Mandatory)][string]$StatePath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or -not $env:GITHUB_RUN_ID) { throw 'A disposable hosted runner is required.' }
$family = 'ohmyposh.cli_96v55e8n804z4'
function Get-Fingerprint([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-', '') }
    finally { $sha.Dispose() }
}
function Get-Snapshot {
    $packages = @(Get-AppxPackage -Name ohmyposh.cli)
    if ($packages.Count -eq 0) { return [ordered]@{ present = $false } }
    if ($packages.Count -ne 1 -or $packages[0].PackageFamilyName -cne $family -or
        $packages[0].IsDevelopmentMode -or [string]$packages[0].Status -cne 'Ok') { throw 'Unexpected OMP package registration.' }
    $hash = (Get-FileHash -LiteralPath (Join-Path $packages[0].InstallLocation 'oh-my-posh.exe') -Algorithm SHA256).Hash
    $items = @(Get-AppxPackageAutoUpdateSettings -PackageFamilyName $family)
    if ($items.Count -ne 1) { throw 'Expected one effective App Installer setting.' }
    $settings = $items[0]
    $policy = [ordered]@{}
    foreach ($key in @('CheckForUpdatesOnLaunch', 'ShowPromptOnLaunchWhenUpdateIsAvailable', 'UpdateBlocksActivation',
            'AutomaticBackgroundTaskUpdatesEnabled', 'ForceUpdateFromAnyVersion', 'IsAutoRepairEnabled',
            'HoursBetweenUpdateChecks', 'PolicySource', 'Version')) { $policy[$key] = [string]$settings.$key }
    foreach ($key in @('AppInstallerUri', 'UpdateUris', 'RepairUris', 'OptionalPackageUris', 'DependencyPackageUris')) {
        $policy[$key] = Get-Fingerprint ((@($settings.$key | ForEach-Object { [string]$_ })) -join "`n")
    }
    $paused = $null
    if ($null -ne $settings.PausedUntil -and [string]$settings.PausedUntil) { $paused = [DateTimeOffset]$settings.PausedUntil }
    return [ordered]@{ present = $true; package = $packages[0].PackageFullName; hash = $hash; policy = $policy;
        policy_fingerprint = Get-Fingerprint ($policy | ConvertTo-Json -Compress); policy_source = [string]$settings.PolicySource;
        paused_until = $(if ($null -ne $paused) { $paused.ToUniversalTime().ToString('o') } else { '' });
        active_pause = $null -ne $paused -and $paused -gt [DateTimeOffset]::UtcNow }
}
try {
    if ($Action -in @('Preflight', 'Resume')) {
        $manager = [Windows.Management.Deployment.AppInstallerManager,Windows.Management.Deployment,ContentType=WindowsRuntime]::GetDefault()
        if ($null -eq $manager -or $null -eq $manager.PSObject.Methods['PauseAutoUpdatesUntil']) { throw 'The documented resume API is unavailable.' }
    }
    if ($Action -in @('Pause', 'Resume')) {
        $state = [IO.File]::ReadAllText($StatePath) | ConvertFrom-Json
        if (-not $state.attempted -or $state.restored -or $state.family -cne $family -or $state.run_id -cne $env:GITHUB_RUN_ID) { throw 'This run does not own the package pause.' }
    }
    if ($Action -eq 'Preflight') { $result = @{ ready = $true } }
    else {
        if ($Action -eq 'Pause') {
            $before = Get-Snapshot
            if (-not $before.present -or $before.policy_source -cne 'Default' -or $before.active_pause -or $before.paused_until -or
                $before.package -cne $state.baseline.package -or $before.hash -cne $state.baseline.hash -or
                $before.policy_fingerprint -cne $state.baseline.policy_fingerprint) { throw 'The original unpaused package or policy changed.' }
            Set-AppxPackageAutoUpdateSettings -PackageFamilyName $family -PauseUpdates -HoursToPause 2
        }
        if ($Action -eq 'Resume') { $manager.PauseAutoUpdatesUntil($family, [DateTimeOffset]::Now) }
        $result = Get-Snapshot
    }
    [IO.File]::WriteAllText($OutputPath, (ConvertTo-Json -InputObject $result -Depth 6), [Text.UTF8Encoding]::new($false))
}
catch {
    $command = ''
    if ($null -ne $_.InvocationInfo.MyCommand) { $command = $_.InvocationInfo.MyCommand.Name }
    [IO.File]::WriteAllText($OutputPath, (@{ error_type = $_.Exception.GetType().FullName; hresult = $_.Exception.HResult;
                error_command = $command; error_line = $_.InvocationInfo.ScriptLineNumber } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    exit 1
}
