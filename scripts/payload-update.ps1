#Requires -Version 7.0
<#
.SYNOPSIS
    Keep the payload repos installed and current: the native Windows twin of
    scripts/payload-update.sh.
.DESCRIPTION
    The PowerShell 7 profile calls this script without arguments at its tail,
    after scripts/dotfiles-update.ps1, in an interactive console only. Once
    per session it installs each absent item of config/payloads.tsv
    (coding-agent-kit, PyMOLScripts, awesome-skills) in the foreground, through
    the repo's own install.ps1, so a person sees the first install, and starts
    one hidden, detached pwsh -NoProfile that refreshes the installed items
    whose refresh interval (their days row) has passed since their last
    success, so the profile never waits for a download. A failed run records
    nothing, so the next session tries again.

    It never runs automatically from an elevated session: an installer run
    there would leave its git clone owned by Administrators, which Git then
    refuses to update from an unelevated one.

        & scripts/payload-update.ps1 -Now [ITEM...]
        & scripts/payload-update.ps1 -Auto

    The first runs the given items (default: those of DOTFILES_PAYLOAD_ITEMS)
    in the foreground whatever their intervals, and exits 1 when one failed;
    the profile's sync-payloads and sync-skills functions call it. The second
    is the automatic run without its console, session and opt-out guards.
.NOTES
    DOTFILES_PAYLOAD_AUTO_UPDATE  0 disables the automatic runs (not -Now)
    DOTFILES_PAYLOAD_ITEMS        the items it manages (default: kit pymol
                                  skills; empty manages none)
    State, in %LOCALAPPDATA%\dotfiles\payload: one stamp per item (the time of
    its last success), worker.pid (the background run, which keeps a second
    one from starting while it lives, for a day at most) and payload.log (the output of the last
    background run). The repos' installers lock themselves and exit 75 while
    another run holds the lock; that is neither a success nor a failure here.
    An item whose installer exits with its person-status row has stopped for
    a person: ITEM.attention records it, every later automatic run warns
    about it, and the next success removes it.
#>
[CmdletBinding()]
param(
    # The automatic run without the session guards, as the profile's call
    # reaches it (scripts/payload-update.sh --auto).
    [switch]$Auto,
    [switch]$Now,
    [switch]$Worker,
    [Parameter(Position = 0, ValueFromRemainingArguments)][string[]]$Item
)

$Automatic = -not ($Now -or $Worker)
$Self = $PSCommandPath
$Repo = Split-Path -Parent $PSScriptRoot
if ($Automatic -and -not $Auto) {
    # The profile's call: a console, once per session, unless opted out.
    if ([Console]::IsOutputRedirected -or $env:_DOTFILES_PAYLOAD_CHECKED) { return }
    $env:_DOTFILES_PAYLOAD_CHECKED = '1'
    if ($env:DOTFILES_PAYLOAD_AUTO_UPDATE -eq '0') { return }
}

$PayloadFailed = & { try {
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    function Write-DotfilesLog {
        param([string]$Level, [string]$Message)
        Write-Host "[dotfiles] [$Level] $Message"
    }
    try {
        $terminalLibrary = Join-Path $Repo 'lib/terminal.ps1'
        if (Test-Path -LiteralPath $terminalLibrary -PathType Leaf) { . $terminalLibrary }
    } catch { } # Logging is cosmetic; keep the plain fallback available.

    $pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
    $stateRoot = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME '.local/state' }
    $state = Join-Path $stateRoot 'dotfiles/payload'
    $rows = @{}
    try {
        foreach ($line in [IO.File]::ReadAllLines((Join-Path $Repo 'config/payloads.tsv'))) {
            $parts = $line.Split("`t", 3)
            if ($line.StartsWith('#') -or $parts.Count -ne 3) { continue }
            $key = "$($parts[0])`t$($parts[1])"
            if (-not $rows.ContainsKey($key)) { $rows[$key] = $parts[2] }
        }
    }
    catch {
        Write-DotfilesLog error "payload-update: cannot read config/payloads.tsv: $($_.Exception.Message)"
        return $true
    }

    function Get-PayloadField([string]$Name, [string]$Field) { $rows["$Name`t$Field"] }

    function Invoke-DotfilesPayloadScript {
        # SOURCE [ARG...], for the windows-* rows: run SOURCE, a URL that is
        # downloaded into a temporary .ps1 first or an installed script, in a
        # child pwsh with ARG, and return its exit status. A simple function,
        # so -Channel and the like reach the script instead of binding here.
        $source = [string]$args[0]
        $rest = @($args | Select-Object -Skip 1 | ForEach-Object { [string]$_ })
        $temporary = $null
        try {
            $file = $source
            if ($source -match '^[A-Za-z][A-Za-z0-9+.-]*://') {
                $temporary = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-payload-' + [Guid]::NewGuid().ToString('N') + '.ps1')
                if ($source -like 'file:*') {
                    Copy-Item -LiteralPath ([Uri]$source).LocalPath -Destination $temporary -ErrorAction Stop
                }
                else {
                    $ProgressPreference = 'SilentlyContinue'
                    Invoke-WebRequest -Uri $source -OutFile $temporary -UseBasicParsing -ErrorAction Stop
                }
                if ((Get-Item -LiteralPath $temporary).Length -eq 0) { throw "$source downloaded empty" }
                $file = $temporary
            }
            elseif (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "$source is missing" }
            & $pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $file @rest 2>&1 |
                ForEach-Object { Write-Host "$_" }
            return $LASTEXITCODE
        }
        catch {
            Write-DotfilesLog error "cannot run $($source): $($_.Exception.Message)"
            return 1
        }
        finally {
            if ($temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction Ignore }
        }
    }

    function Test-PayloadInstalled([string]$Name) {
        $probe = Get-PayloadField $Name 'windows-probe'
        if (-not $probe) { return $false }
        try { return [bool](& ([scriptblock]::Create($probe))) } catch { return $false }
    }

    function Test-PayloadDue([string]$Name) {
        $days = 1
        if (-not [int]::TryParse([string](Get-PayloadField $Name 'days'), [ref]$days) -or $days -lt 0) { $days = 1 }
        try { $last = [long]([IO.File]::ReadAllText((Join-Path $state "$Name.stamp")).Trim()) }
        catch { return $true }
        return ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $last) -ge ($days * 86400)
    }

    # Install the item when absent, else update it, and stamp a success.
    function Invoke-PayloadItem([string]$Name) {
        $action = if (Test-PayloadInstalled $Name) { 'update' } else { 'install' }
        $command = Get-PayloadField $Name "windows-$action"
        if (-not $command) { $command = Get-PayloadField $Name 'windows-install' }
        if (-not $command) {
            Write-DotfilesLog error "$($Name): config/payloads.tsv has no windows-install row"
            return 1
        }
        if ($action -eq 'install') { Write-DotfilesLog step "$($Name): installing (later updates run in the background)" }
        else { Write-DotfilesLog step "$($Name): updating" }
        $Channel = Get-PayloadField 'kit' 'channel'
        $person = Get-PayloadField $Name 'person-status'
        # The command's last output is the exit status of the script it ran.
        $status = 1
        try {
            $result = @(& ([scriptblock]::Create($command)))
            if ($result.Count -and $result[-1] -is [int]) { $status = $result[-1] }
        }
        catch { Write-DotfilesLog error "$($Name): $($_.Exception.Message)" }
        if ($status -eq 0) {
            try {
                [void][IO.Directory]::CreateDirectory($state)
                $stamp = Join-Path $state "$Name.stamp"
                $temporary = "$stamp.$([Guid]::NewGuid().ToString('N')).tmp"
                [IO.File]::WriteAllText($temporary, "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())`n")
                [IO.File]::Move($temporary, $stamp, $true)
                [IO.File]::Delete((Join-Path $state "$Name.attention"))
                Write-DotfilesLog ok "$($Name): $action done"
            }
            catch {
                Write-DotfilesLog error "$($Name): cannot record the success in $($state): $($_.Exception.Message)"
                $status = 1
            }
        }
        elseif ($status -eq 75) { Write-DotfilesLog info "$($Name): another run holds its lock; the next session tries again" }
        elseif ($person -and "$status" -ceq $person) {
            Write-DotfilesLog error "$($Name): stopped for a person (exit $status): do what its message says, then run sync-payloads $Name"
            try {
                [void][IO.Directory]::CreateDirectory($state)
                [IO.File]::WriteAllText((Join-Path $state "$Name.attention"), "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) $status`n")
            }
            catch { Write-DotfilesLog error "$($Name): cannot record that in $($state): $($_.Exception.Message)" }
        }
        else { Write-DotfilesLog error "$($Name): $action failed (exit $status); retry with: sync-payloads $Name" }
        return $status
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
        $failed = [ref]$false
        $run = { foreach ($name in $names) { if ((Invoke-PayloadItem $name) -notin @(0, 75)) { $failed.Value = $true } } }
        if ($Worker) {
            [void][IO.Directory]::CreateDirectory($state)
            $log = Join-Path $state 'payload.log'
            & $run *> $log
        }
        else { & $run }
        return $failed.Value
    }

    $later = [Collections.Generic.List[string]]::new()
    foreach ($name in $names) {
        if ([IO.File]::Exists((Join-Path $state "$name.attention"))) {
            Write-DotfilesLog warn "$($name): its last run stopped for a person; run sync-payloads $name to see what it asks (background runs log to $(Join-Path $state 'payload.log'))"
        }
        if (-not (Test-PayloadInstalled $name)) {
            if ($elevated) {
                Write-DotfilesLog info "$($name) is not installed; an unelevated PowerShell installs it (or run sync-payloads $name there)."
                continue
            }
            [void](Invoke-PayloadItem $name)
        }
        elseif (-not $elevated -and (Test-PayloadDue $name)) { $later.Add($name) }
    }
    if (-not $later.Count) { return $false }
    try {
        [void][IO.Directory]::CreateDirectory($state)
        # worker.pid: the PID of the last background run and when it started.
        # A live one younger than a day blocks a new run; an older one is a
        # reused PID.
        $pidFile = Join-Path $state 'worker.pid'
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        if (Test-Path -LiteralPath $pidFile -PathType Leaf) {
            $fields = @([IO.File]::ReadAllText($pidFile).Trim() -split '\s+')
            $previous = 0
            $started = $now
            if ($fields.Count -gt 1) { [void][long]::TryParse($fields[1], [ref]$started) }
            if ([int]::TryParse($fields[0], [ref]$previous) -and ($now - $started) -lt 86400 -and
                (Get-Process -Id $previous -ErrorAction SilentlyContinue)) { return $false }
        }
        # One quoted argument string: Start-Process joins a list unquoted.
        $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass '
        if ($IsWindows) { $arguments += '-WindowStyle Hidden ' }
        $arguments += "-File `"$Self`" -Worker $($later -join ' ')"
        $start = @{ FilePath = $pwsh; ArgumentList = $arguments; PassThru = $true }
        if ($IsWindows) { $start.WindowStyle = 'Hidden' }
        $process = Start-Process @start
        [IO.File]::WriteAllText($pidFile, "$($process.Id) $now`n")
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
