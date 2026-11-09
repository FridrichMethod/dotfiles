#Requires -Version 7.0
# Hosted runner preparation only. The actual bootstrap and doctor stay unchanged.
function Test-E2EHostedRunner {
    return $IsWindows -and $env:GITHUB_ACTIONS -ceq 'true' -and $env:RUNNER_ENVIRONMENT -ceq 'github-hosted'
}

function Write-E2EAppInstallerState($State) {
    $path = Join-Path $E2E['Out'] 'appinstaller-state.json'
    [IO.File]::WriteAllText(($path + '.tmp'), (ConvertTo-Json -InputObject $State -Depth 8), $script:E2EUtf8)
    [IO.File]::Move(($path + '.tmp'), $path, $true)
}

function Test-E2EAppInstallerSame($Before, $After) {
    return $After.present -and $Before.package -ceq $After.package -and $Before.hash -ceq $After.hash -and
        $Before.policy_fingerprint -ceq $After.policy_fingerprint
}

function Invoke-E2EAppInstallerCommand([string]$Action) {
    $receipt = Join-Path $E2E['Out'] ("appinstaller-$($E2E['StepN'])-$Action.json")
    $worker = Join-Path $PSScriptRoot '../appinstaller-policy.ps1'
    $powershell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $arguments = @('-NoProfile', '-NonInteractive', '-File', $worker, '-Action', $Action,
        '-OutputPath', $receipt, '-StatePath', (Join-Path $E2E['Out'] 'appinstaller-state.json'))
    # Direct .NET launches otherwise inherit PS7 module paths that shadow the
    # legacy Utility module. Only this Windows PowerShell child loses the value.
    $code = Invoke-E2EProcess -FilePath $powershell -ArgumentList $arguments -WorkingDirectory $E2E['Out'] `
        -OutFile $E2E['StepOut'] -ErrFile $E2E['StepErr'] -TimeoutSeconds 45 -Environment @{ PSModulePath = $null }
    if ($code -ne 0) { throw "App Installer $Action exited $code; inspect its typed receipt." }
    return [IO.File]::ReadAllText($receipt) | ConvertFrom-Json
}

function Invoke-E2EAppInstallerPrepare([string]$Name) {
    if (-not (Test-E2EHostedRunner)) { Skip-E2EStep $Name 'App Installer preparation applies only to a disposable hosted Windows runner'; return }
    Start-E2EStep $Name "harness:$Name"
    try {
        $current = Invoke-E2EAppInstallerCommand Capture
        $path = Join-Path $E2E['Out'] 'appinstaller-state.json'
        if ([IO.File]::Exists($path)) {
            $owned = [IO.File]::ReadAllText($path) | ConvertFrom-Json
            if (-not $owned.attempted -or $owned.restored -or -not $current.active_pause -or
                -not (Test-E2EAppInstallerSame $owned.baseline $current)) { throw 'The previously owned package pause changed.' }
            Complete-E2EStep pass 'the original package, bytes and policy remain under this run''s pause'
            return
        }
        if (-not $current.present) { Complete-E2EStep pass 'OMP is absent; setup and doctor retain their normal verdicts'; return }
        if ($current.policy_source -cne 'Default' -or $current.active_pause -or $current.paused_until) { throw 'A system policy or pre-existing pause is not owned by this run.' }
        $preflight = Invoke-E2EAppInstallerCommand Preflight
        if (-not $preflight.ready) { throw 'The documented resume API is unavailable.' }
        $state = @{ family = 'ohmyposh.cli_96v55e8n804z4'; run_id = $env:GITHUB_RUN_ID;
            attempted = $true; restored = $false; baseline = $current }
        Write-E2EAppInstallerState $state
        $active = Invoke-E2EAppInstallerCommand Pause
        $minutes = ([DateTimeOffset]$active.paused_until - [DateTimeOffset]::UtcNow).TotalMinutes
        if (-not $active.active_pause -or $minutes -lt 115 -or $minutes -gt 125 -or
            -not (Test-E2EAppInstallerSame $current $active)) { throw 'The two-hour package pause or unchanged policy/bytes was not verified.' }
        Complete-E2EStep pass 'hosted adaptation: OMP App Installer updates paused for this run; package activation and all bootstrap checks remain real'
    }
    catch {
        $E2E['Broken'] = $Name
        Complete-E2EStep fail "App Installer preparation failed: $($_.Exception.Message)"
    }
}

function Invoke-E2EAppInstallerRestore {
    $path = Join-Path $E2E['Out'] 'appinstaller-state.json'
    if (-not [IO.File]::Exists($path)) { return }
    $state = [IO.File]::ReadAllText($path) | ConvertFrom-Json
    if (-not $state.attempted -or $state.restored) { return }
    Start-E2EStep appinstaller-restore 'harness:appinstaller-restore'
    try {
        if (-not (Test-E2EHostedRunner)) { throw 'Restoration requires the same disposable hosted Windows runner.' }
        $resumed = Invoke-E2EAppInstallerCommand Resume
        if ($resumed.active_pause -or -not (Test-E2EAppInstallerSame $state.baseline $resumed)) { throw 'Inactive pause, original policy and package bytes were not all verified.' }
        $state.restored = $true
        Write-E2EAppInstallerState $state
        Complete-E2EStep pass 'OMP updates resumed; original package, executable hash and other policy fields verified'
    }
    catch { Complete-E2EStep fail "App Installer restoration failed: $($_.Exception.Message)" }
}
