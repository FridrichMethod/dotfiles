#Requires -Version 7.0
<#
.SYNOPSIS
    Windows automatic restow support; register once from elevated PowerShell.
.DESCRIPTION
    .\dotfiles-auto-stow.ps1 -Register installs an on-demand task for the
    current user with highest privileges. Login hooks request work; -Apply
    runs it under the same checkout lock used by fetch/pull. Dot-sourcing
    without switches only defines functions (also used by the installer).
    The task executes this checkout's scripts with administrator privileges.
    Registration is explicit; the login hook never prompts for elevation.
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Register, [switch]$Apply)

function Get-DotfilesStateDirectory {
    param([Parameter(Mandatory)][string]$Repo)
    $gitDir = git -C $Repo rev-parse --absolute-git-dir 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Cannot locate Git metadata in $Repo" }
    $state = Join-Path ([string]$gitDir) 'dotfiles-sync-windows'
    [void][IO.Directory]::CreateDirectory($state)
    return $state
}

function Get-DotfilesTaskName {
    param([Parameter(Mandatory)][string]$Repo)
    $key = [IO.Path]::GetFullPath($Repo).TrimEnd([char[]]@('\', '/')).ToLowerInvariant() + '|' +
        [Environment]::GetFolderPath('UserProfile').ToLowerInvariant()
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($key))).Replace('-', '') }
    finally { $sha.Dispose() }
    return 'Dotfiles-Restow-' + $hash.Substring(0, 16)
}

function Test-DotfilesElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Read-DotfilesState {
    param([string]$Directory, [string]$Name = 'configuration.json')
    $path = Join-Path $Directory $Name
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $state = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($state.home -ne [Environment]::GetFolderPath('UserProfile')) {
        throw 'Automatic stow state belongs to another home; use a separate checkout.'
    }
    return $state
}

function Write-DotfilesState {
    param([string]$Directory, [string]$Name, [object]$Value)
    $path = Join-Path $Directory $Name
    $temporary = $path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json) + [Environment]::NewLine)
        [IO.File]::Move($temporary, $path, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
}

function Open-DotfilesLock {
    param([string]$Directory, [int]$WaitSeconds = 0)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        try {
            # The OS releases this lock on crashes, including elevated workers.
            return [IO.File]::Open((Join-Path $Directory 'update.lock'),
                [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        }
        catch [IO.IOException] {
            if ($timer.Elapsed.TotalSeconds -ge $WaitSeconds) { return $null }
            Start-Sleep -Milliseconds 200
        }
    } while ($true)
}

function Get-DotfilesHead {
    param([string]$Repo)
    $head = git -C $Repo rev-parse --verify HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve dotfiles HEAD.' }
    return [string]$head
}

function Test-DotfilesClean {
    param([string]$Repo, [switch]$AllowGitlinkChanges)
    $arguments = @('-C', $Repo, 'status', '--porcelain', '--untracked-files=normal')
    $arguments += if ($AllowGitlinkChanges) { '--ignore-submodules=all' } else { '--ignore-submodules=none' }
    $changes = git @arguments 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot check dotfiles working tree.' }
    if ($changes) { return $false }
    if ($AllowGitlinkChanges) {
        # A failed submodule download may leave a stale gitlink. Preserve real
        # submodule edits, but allow retrying the checkout of the recorded SHA.
        git -C $Repo submodule foreach --quiet --recursive 'status=$(git status --porcelain --untracked-files=normal --ignore-submodules=all) && test -z "$status"' 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
    }
    return $true
}


function Test-DotfilesUpdateClean {
    param([string]$Repo, [string]$Directory)
    $pending = Read-DotfilesState $Directory 'submodules.json'
    $allowGitlinks = $null -ne $pending -and $pending.head -eq (Get-DotfilesHead $Repo)
    return Test-DotfilesClean $Repo -AllowGitlinkChanges:$allowGitlinks
}

function Set-DotfilesSubmodulePending {
    param([string]$Repo, [string]$Directory)
    Write-DotfilesState $Directory 'submodules.json' @{
        home = [Environment]::GetFolderPath('UserProfile')
        head = Get-DotfilesHead $Repo
    }
}

function Invoke-DotfilesSubmoduleSync {
    param([string]$Repo, [string]$Directory)
    if (-not (Test-DotfilesUpdateClean $Repo $Directory)) { throw 'Local changes present; submodule update skipped.' }
    Set-DotfilesSubmodulePending $Repo $Directory
    git -C $Repo submodule update --init --recursive --quiet 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Submodule update failed; restow remains pending.' }
    if (-not (Test-DotfilesClean $Repo)) { throw 'Working tree changed during update; stow skipped.' }
    Remove-Item -LiteralPath (Join-Path $Directory 'submodules.json') -ErrorAction Stop
}

function Save-DotfilesStowState {
    param([string]$Repo, [AllowEmptyString()][string]$HostDir, [string]$ExpectedHead)
    $directory = Get-DotfilesStateDirectory $Repo
    # Remember the host for dirty manual installs without acknowledging HEAD.
    $head = Get-DotfilesHead $Repo
    if (-not (Test-DotfilesClean $Repo) -or ($ExpectedHead -and $ExpectedHead -ne $head)) { $head = '' }
    Write-DotfilesState $directory 'configuration.json' @{
        home = [Environment]::GetFolderPath('UserProfile')
        host = $HostDir
        appliedHead = $head
    }
}

function Request-DotfilesRestow {
    param([string]$Repo, [string]$Directory)
    if ($env:DOTFILES_AUTO_STOW -eq '0') { return $false }
    $state = Read-DotfilesState $Directory
    $hostDir = if (Test-Path Env:DOTFILES_HOST) { $env:DOTFILES_HOST }
        elseif ($null -ne $state) { $state.host } else { 'win' }
    if ($hostDir -notin @('', 'win')) { throw 'Windows DOTFILES_HOST must be win or empty (common only).' }
    $head = Get-DotfilesHead $Repo
    if ($null -ne $state -and $state.appliedHead -eq $head -and $state.host -eq $hostDir) {
        return $false
    }
    Write-DotfilesState $Directory 'request.json' @{
        home = [Environment]::GetFolderPath('UserProfile')
        host = $hostDir
        head = $head
    }
    return $true
}

function Invoke-DotfilesApply {
    param([string]$Repo)
    if (-not (Test-DotfilesElevated)) { throw 'Automatic Windows stow requires an elevated task.' }
    $directory = Get-DotfilesStateDirectory $Repo
    $lock = Open-DotfilesLock $directory -WaitSeconds 30
    if ($null -eq $lock) { throw 'Dotfiles update is busy; restow remains pending.' }
    $savedPrompt = $env:GIT_TERMINAL_PROMPT
    $env:GIT_TERMINAL_PROMPT = '0'
    try {
        $request = Read-DotfilesState $directory 'request.json'
        if ($null -eq $request) { return }
        if ($request.host -notin @('', 'win')) { throw 'Invalid Windows host in restow request.' }
        if ($request.head -ne (Get-DotfilesHead $Repo)) { throw 'HEAD changed; a new login will request the current revision.' }
        if (-not (Test-DotfilesUpdateClean $Repo $directory)) { throw 'Working tree has local changes; restow remains pending.' }
        $state = Read-DotfilesState $directory
        if ($null -ne $state -and $state.appliedHead -eq $request.head -and $state.host -eq $request.host) { return }
        Invoke-DotfilesSubmoduleSync $Repo $directory
        # Child scope isolates installer preference variables and helper names.
        & (Join-Path $Repo 'stow-all.ps1') -HostDir $request.host -Strict
        $state = Read-DotfilesState $directory
        if ($null -eq $state -or $state.appliedHead -ne $request.head -or $state.host -ne $request.host) {
            throw 'Installer did not acknowledge this revision; restow remains pending.'
        }
        Write-Host '[dotfiles] Automatically stowed. Restart the shell/apps to load updated settings.'
    }
    finally {
        $lock.Dispose()
        if ($null -eq $savedPrompt) { Remove-Item Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue }
        else { $env:GIT_TERMINAL_PROMPT = $savedPrompt }
    }
}

function Invoke-DotfilesUpdate {
    param([string]$Repo)
    $directory = Get-DotfilesStateDirectory $Repo
    $lock = Open-DotfilesLock $directory
    if ($null -eq $lock) { return }
    $dispatch = $false
    $pulled = $false
    $savedPrompt = $env:GIT_TERMINAL_PROMPT
    $env:GIT_TERMINAL_PROMPT = '0'
    try {
        if (-not (Test-DotfilesUpdateClean $Repo $directory)) {
            Write-Host '[dotfiles] Local changes present; automatic pull/stow skipped.'
            return
        }
        git -C $Repo fetch --quiet 2>$null
        if ($LASTEXITCODE -eq 0) {
            $behind = git -C $Repo rev-list --count 'HEAD..@{upstream}' 2>$null
            if ($LASTEXITCODE -eq 0 -and ($behind -as [int]) -gt 0) {
                Write-Host "[dotfiles] $behind new commit(s) available - pulling..."
                git -C $Repo pull --ff-only --quiet 2>$null
                if ($LASTEXITCODE -ne 0) { throw "Fast-forward pull failed. Resolve manually in $Repo." }
                Set-DotfilesSubmodulePending $Repo $directory
                $pulled = $true
                Write-Host '[dotfiles] Pulled successfully.'
            }
        }
        # Also retries failed stows after a previous pull or while offline.
        $dispatch = Request-DotfilesRestow $Repo $directory
        $pending = Read-DotfilesState $directory 'submodules.json'
        $retrySubmodules = $null -ne $pending -and $pending.head -eq (Get-DotfilesHead $Repo)
        if ($dispatch -or $pulled -or $retrySubmodules) {
            Invoke-DotfilesSubmoduleSync $Repo $directory
        }
    }
    finally {
        $lock.Dispose()
        if ($null -eq $savedPrompt) { Remove-Item Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue }
        else { $env:GIT_TERMINAL_PROMPT = $savedPrompt }
    }
    if ($dispatch) {
        if (Test-DotfilesElevated) { Invoke-DotfilesApply $Repo }
        else {
            $taskName = Get-DotfilesTaskName $Repo
            try {
                Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
                Write-Host "[dotfiles] Restow queued. Log: $(Join-Path $directory 'restow.log')"
            }
            catch {
                throw "Cannot start $taskName. Run .\dotfiles-auto-stow.ps1 -Register once from elevated PowerShell in $Repo. $($_.Exception.Message)"
            }
        }
    }
}

if ($Register -and $Apply) { throw 'Choose either -Register or -Apply.' }
if ($Register) {
    if (-not (Test-DotfilesElevated)) { throw 'Register from elevated PowerShell 7+.' }
    $repo = $PSScriptRoot
    $taskName = Get-DotfilesTaskName $repo
    if ($PSCmdlet.ShouldProcess($taskName, 'Register current-user task that runs checkout scripts with highest privileges')) {
        $action = New-ScheduledTaskAction -Execute (Join-Path $PSHOME 'pwsh.exe') `
            -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -File "{0}" -Apply' -f $PSCommandPath) `
            -WorkingDirectory $repo
        $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) `
            -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal `
            -Settings $settings -Description "Apply this user's dotfiles after update: $repo" -Force -ErrorAction Stop | Out-Null
        Write-Host "Registered $taskName. New interactive shells can now request automatic stow."
    }
}
elseif ($Apply) {
    $ErrorActionPreference = 'Stop'
    $PSNativeCommandUseErrorActionPreference = $false
    $directory = Get-DotfilesStateDirectory $PSScriptRoot
    $log = Join-Path $directory 'restow.log'
    try {
        # One bounded last-run log; requests remain pending on any error.
        & { Invoke-DotfilesApply $PSScriptRoot } *> $log
    }
    catch {
        Add-Content -LiteralPath $log -Value $_.ToString()
        exit 1
    }
}
