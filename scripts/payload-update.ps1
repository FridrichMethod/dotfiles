#Requires -Version 7.0
<#
.SYNOPSIS
    Keep the payload repos installed and current: the native Windows twin of
    scripts/payload-update.sh (docs/payloads.md has the whole contract).
.DESCRIPTION
    The PowerShell 7 profile calls this script without arguments at its tail,
    after scripts/dotfiles-update.ps1, in an interactive console only. Once
    per session an absent item of config/payloads.tsv installs in the
    foreground through the repo's own install.ps1; a refresh whose days row
    has passed, and any retry six hours after a failure (ITEM.failed, which
    every later session and the doctor report), runs in one hidden, detached
    pwsh -NoProfile -Worker into payload.log. An elevated session never runs
    them automatically: its git clones would belong to Administrators.

        & scripts/payload-update.ps1 -Now [ITEM...]

    runs the items (default: DOTFILES_PAYLOAD_ITEMS) in the foreground
    whatever their state and exits 1 when one failed; the profile's
    sync-payloads and sync-skills functions call it. -Auto is the automatic
    run without the console, session and opt-out guards.
.NOTES
    DOTFILES_PAYLOAD_AUTO_UPDATE=0 disables the automatic runs (not -Now);
    DOTFILES_PAYLOAD_ITEMS lists the items (default: kit pymol skills);
    DOTFILES_PAYLOAD_TIMEOUT bounds each download in seconds (default 60).
    State, in %LOCALAPPDATA%\dotfiles\payload: ITEM.stamp (last success),
    ITEM.failed (time and exit status of the last failure, then the end of a
    background run's output) and payload.log. Exit 75, a repo's own lock, is
    neither a success nor a failure.
#>
[CmdletBinding()]
param(
    [switch]$Auto,
    [switch]$Now,
    [switch]$Worker,
    [Parameter(Position = 0, ValueFromRemainingArguments)][string[]]$Item
)

$Automatic = -not ($Now -or $Worker)
if ($Automatic -and -not $Auto) {
    # The profile's call: a console, once per session, unless opted out.
    if ([Console]::IsOutputRedirected -or $env:_DOTFILES_PAYLOAD_CHECKED) { return }
    $env:_DOTFILES_PAYLOAD_CHECKED = '1'
    if ($env:DOTFILES_PAYLOAD_AUTO_UPDATE -eq '0') { return }
}
$Repo = Split-Path -Parent $PSScriptRoot

$PayloadFailed = & { try {
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    function Write-DotfilesLog([string]$Level, [string]$Message) { Write-Host "[dotfiles] [$Level] $Message" }
    try { . (Join-Path $Repo 'lib/terminal.ps1') } catch { } # Logging is cosmetic.
    $pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
    $state = Join-Path $(if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME '.local/state' }) 'dotfiles/payload'
    $log = Join-Path $state 'payload.log'
    [void][IO.Directory]::CreateDirectory($state)
    $timeout = 60
    if (-not [int]::TryParse("$env:DOTFILES_PAYLOAD_TIMEOUT", [ref]$timeout) -or $timeout -lt 1) { $timeout = 60 }
    $rows = @{}
    foreach ($line in [IO.File]::ReadAllLines((Join-Path $Repo 'config/payloads.tsv'))) {
        $parts = $line.Split("`t", 3)
        if (-not $line.StartsWith('#') -and $parts.Count -eq 3 -and -not $rows.ContainsKey("$($parts[0])`t$($parts[1])")) {
            $rows["$($parts[0])`t$($parts[1])"] = $parts[2]
        }
    }
    function Get-PayloadField([string]$Name, [string]$Field) { $rows["$Name`t$Field"] }
    # The time and exit status a stamp or failure record starts with.
    function Get-PayloadRecord([string]$Path) {
        try { $fields = [IO.File]::ReadAllLines($Path)[0].Split(' '); return @([long]$fields[0], "$($fields[1])") }
        catch { return $null }
    }

    $script:PayloadOffline = $false
    function Invoke-DotfilesPayloadScript {
        # SOURCE [ARG...], for the windows-* rows: run SOURCE, a URL first
        # downloaded into a temporary .ps1 within the timeout or an installed
        # script, in a child pwsh with ARG, and return its exit status. After
        # one failed download a run tries no other. A simple function, so
        # -Channel and the like reach the script instead of binding here.
        $source = [string]$args[0]
        $rest = @($args | Select-Object -Skip 1 | ForEach-Object { [string]$_ })
        $temporary = $null
        try {
            $file = $source
            if ($source -match '^[A-Za-z][A-Za-z0-9+.-]*://') {
                if ($script:PayloadOffline) { throw 'skipped: a download already failed in this run' }
                $script:PayloadOffline = $true
                $temporary = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-payload-' + [Guid]::NewGuid().ToString('N') + '.ps1')
                if ($source -like 'file:*') { Copy-Item -LiteralPath ([Uri]$source).LocalPath -Destination $temporary -ErrorAction Stop }
                else {
                    $ProgressPreference = 'SilentlyContinue'
                    Invoke-WebRequest -Uri $source -OutFile $temporary -TimeoutSec $timeout -ErrorAction Stop
                }
                $script:PayloadOffline = $false
                if ((Get-Item -LiteralPath $temporary).Length -eq 0) { throw "$source downloaded empty" }
                $file = $temporary
            }
            elseif (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "$source is missing" }
            & $pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $file @rest 2>&1 | ForEach-Object { Write-Host "$_" }
            return $LASTEXITCODE
        }
        catch {
            Write-DotfilesLog error "cannot run $($source): $($_.Exception.Message)"
            return 1
        }
        finally { if ($temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction Ignore } }
    }

    function Test-PayloadInstalled([string]$Name) {
        try { return [bool](& ([scriptblock]::Create((Get-PayloadField $Name 'windows-probe')))) } catch { return $false }
    }

    # Install the item when absent, else update it; stamp a success, record a
    # failure, and leave the exit status in $script:PayloadStatus.
    function Invoke-PayloadItem([string]$Name) {
        $script:PayloadStatus = 1
        # A stow-links path (PACKAGE PATH...) still linked into the retired
        # common/PACKAGE: the repo's installer refuses it until stow-all runs.
        $words = @("$(Get-PayloadField $Name 'stow-links')".Split(' ', [StringSplitOptions]::RemoveEmptyEntries))
        foreach ($path in @($words | Select-Object -Skip 1)) {
            $link = Get-Item -LiteralPath (Join-Path $HOME $path) -Force -ErrorAction SilentlyContinue
            if ($link -and $link.LinkType -and "$(@($link.Target)[0])".Replace('\', '/') -like "*common/$($words[0])/*") {
                Write-DotfilesLog warn "$($Name): ~/$path is still a link the retired Stow package made, which its installer refuses; run stow-all.ps1 from an elevated PowerShell 7 first (the login updater's task does), then sync-payloads $Name"
                return
            }
        }
        $action = if (Test-PayloadInstalled $Name) { 'update' } else { 'install' }
        $command = Get-PayloadField $Name "windows-$action"
        if (-not $command) { $command = Get-PayloadField $Name 'windows-install' }
        $doing = if ($action -eq 'install') { 'installing (later updates run in the background)' } else { 'updating' }
        Write-DotfilesLog step "$($Name): $doing"
        $Channel = Get-PayloadField 'kit' 'channel'
        # The command's last output is the exit status of the script it ran.
        $status = 1
        try {
            $result = @(& ([scriptblock]::Create($command)))
            if ($result.Count -and $result[-1] -is [int]) { $status = $result[-1] }
        }
        catch { Write-DotfilesLog error "$($Name): $($_.Exception.Message)" }
        $clock = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $failure = Join-Path $state "$Name.failed"
        if ($status -eq 0) {
            $stamp = Join-Path $state "$Name.stamp"
            try {
                [IO.File]::WriteAllText("$stamp.tmp", "$clock`n")
                [IO.File]::Move("$stamp.tmp", $stamp, $true)
                [IO.File]::Delete($failure)
                Write-DotfilesLog ok "$($Name): $action done"
            }
            catch {
                Write-DotfilesLog error "$($Name): cannot record the success in $($state): $($_.Exception.Message)"
                $status = 1
            }
        }
        elseif ($status -eq 75) { Write-DotfilesLog info "$($Name): another run holds its lock; the next session tries again" }
        else {
            $person = Get-PayloadField $Name 'person-status'
            if ($person -and "$status" -ceq $person) {
                Write-DotfilesLog error "$($Name): stopped for a person (exit $status): do what its message says, then run sync-payloads $Name"
            }
            else { Write-DotfilesLog error "$($Name): $action failed (exit $status); retry with: sync-payloads $Name" }
            [IO.File]::WriteAllText($failure, "$clock $status`n")
        }
        $script:PayloadStatus = $status
    }

    $names = if ($Item) { @($Item) }
    elseif ($null -ne $env:DOTFILES_PAYLOAD_ITEMS) { @($env:DOTFILES_PAYLOAD_ITEMS -split '\s+' | Where-Object { $_ }) }
    else { @('kit', 'pymol', 'skills') }
    foreach ($name in $names) {
        if (-not $rows.ContainsKey("$name`tdays")) {
            Write-DotfilesLog error "payload-update: unknown item '$name'; config/payloads.tsv names kit, pymol and skills."
            return $true
        }
    }
    $elevated = $IsWindows -and ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $Automatic) {
        if ($Now -and $elevated) {
            Write-DotfilesLog warn 'payload-update: this session is elevated, so what the installers create (the kit and skills clones) will be owned by Administrators, which an unelevated update then cannot use; prefer an unelevated PowerShell.'
        }
        if ($Worker) { [IO.File]::WriteAllText($log, '') }
        $failed = $false
        foreach ($name in $names) {
            if ($Worker) {
                # Into the log, and the end of a failure into its record.
                $output = [string[]]@(Invoke-PayloadItem $name *>&1 | ForEach-Object { "$_" })
                [IO.File]::AppendAllLines($log, $output)
                $failure = Join-Path $state "$name.failed"
                if ($script:PayloadStatus -notin 0, 75 -and [IO.File]::Exists($failure)) {
                    [IO.File]::AppendAllLines($failure, [string[]]@($output | Select-Object -Last 20))
                }
            }
            else { Invoke-PayloadItem $name }
            if ($script:PayloadStatus -notin 0, 75) { $failed = $true }
        }
        return $failed
    }

    $clock = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $later = [Collections.Generic.List[string]]::new()
    foreach ($name in $names) {
        $failure = Get-PayloadRecord (Join-Path $state "$name.failed")
        $success = Get-PayloadRecord (Join-Path $state "$name.stamp")
        $days = 1
        if (-not [int]::TryParse("$(Get-PayloadField $name 'days')", [ref]$days) -or $days -lt 0) { $days = 1 }
        if ($failure) {
            $person = Get-PayloadField $name 'person-status'
            $what = 'failed'
            $hint = ''
            if ($person -and $failure[1] -ceq $person) { $what = 'stopped for a person'; $hint = ' and do what it asks' }
            Write-DotfilesLog warn "$($name): its last run $what (exit $($failure[1]), see $(Join-Path $state "$name.failed")); run sync-payloads $name$hint"
            if ($clock - $failure[0] -ge 21600) { $later.Add($name) }
        }
        elseif (-not (Test-PayloadInstalled $name)) {
            if ($elevated) { Write-DotfilesLog info "$($name) is not installed; an unelevated PowerShell installs it (or run sync-payloads $name there)." }
            else { Invoke-PayloadItem $name }
        }
        elseif (-not $success -or $clock - $success[0] -ge $days * 86400) { $later.Add($name) }
    }
    if ($elevated -or -not $later.Count) { return $false }
    try {
        # One quoted argument string: Start-Process joins a list unquoted.
        $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass ' + $(if ($IsWindows) { '-WindowStyle Hidden ' } else { '' }) +
            "-File `"$PSCommandPath`" -Worker $($later -join ' ')"
        $start = @{ FilePath = $pwsh; ArgumentList = $arguments }
        if ($IsWindows) { $start.WindowStyle = 'Hidden' }
        Start-Process @start
    }
    catch { Write-DotfilesLog warn "payload-update: cannot start the background refresh: $($_.Exception.Message)" }
    return $false
}
catch {
    # Never a stack trace in a person's console: one line, with where it broke.
    Write-Host "[dotfiles] [error] payload-update: $($_.Exception.Message) (scripts/payload-update.ps1 line $($_.InvocationInfo.ScriptLineNumber))"
    return $true
} }

if (-not $Automatic -and [bool](@($PayloadFailed)[-1])) { exit 1 }
