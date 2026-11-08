#Requires -Version 7.0
<#
.SYNOPSIS
    Read-only day-zero check for the win host - the Windows twin of doctor.sh.

.DESCRIPTION
    Probes every config/bootstrap/tools.tsv row whose hosts match win, plus
    the structural checks chezmoi-config and payloads, prints one line per
    check and then a summary:

      [dotfiles] [<level>] <tier> <id>: <detail> (docs/bootstrap.md <step>)

    Statuses are ok, outdated, missing, warn, skip and human, with the same
    meaning as in doctor.sh: missing, outdated and human are errors, and
    outside the selected tiers they are reported as warn. Executables are
    found by probing PATH entries for .exe, .cmd, .bat and .ps1 files (a
    Microsoft Store alias that prints no version does not count);
    PowerShell modules by a directory in a PSModulePath entry; the Nerd Font
    by a file name in the system or per-user Windows font directory.
    chezmoi-config checks this home's chezmoi config, named by cause: a
    config naming another checkout only warns, and on Windows a configured
    home whose ~/.local/bin/chezmoi.exe the login updater refuses is human.

    The doctor writes nothing and makes no network call: no winget list, no
    module repository query. -Online adds the auth probes gh auth status,
    claude auth status and codex login status; as in doctor.sh, a tool that
    is signed out warns and one that is absent is skipped, and the probed
    tools may write their own state (claude rewrites ~/.claude.json).

    Exit codes: 0 no selected-tier check is missing, outdated or human (warn
    and skip do not fail); 1 a selected-tier check, tools.tsv row or
    structural, is missing, outdated or human; 2 usage error, unknown host
    or invalid manifest.

.PARAMETER HostName
    Alias -Host. Only win is accepted; use ./doctor.sh --host <host> on Unix.

.PARAMETER Tier
    all, or a comma list of core, cli, ai, desktop, contributor, host.
    Defaults to core,cli,ai.

.PARAMETER Tsv
    Print a header and exactly five tab-separated columns per check:
    status, id, tier, detail, fix (docs/bootstrap.md <step>, or -).

.PARAMETER Quiet
    Print only checks that are neither ok nor skip, then the summary; with
    -Tsv, only those rows after the header.

.PARAMETER Online
    Also run the network auth probes, which may write the tools' own state.

.EXAMPLE
    .\doctor.ps1

.EXAMPLE
    .\doctor.ps1 -Tier all -Tsv
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [Alias('Host')]
    [string]$HostName = 'win',
    [string]$Tier = 'core,cli,ai',
    [switch]$Tsv,
    [switch]$Quiet,
    [switch]$Online
)

Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false

$RepoRoot = $PSScriptRoot
function Write-DotfilesLog {
    param([string]$Level, [string]$Message)
    Write-Host "[dotfiles] [$Level] $Message"
}
try {
    $terminalLibrary = Join-Path $RepoRoot 'lib/terminal.ps1'
    if (Test-Path -LiteralPath $terminalLibrary -PathType Leaf) { . $terminalLibrary }
} catch { } # Plain diagnostics remain usable in a partial checkout.

$ToolHeader = @('id', 'tier', 'hosts', 'probe', 'version_flag', 'floor', 'absent', 'doc')

function New-DoctorResult {
    param([string]$Status, [string]$Id, [string]$Tier, [string]$Detail, [string]$Step)
    $fix = if ($Status -cin @('ok', 'skip') -or -not $Step) { '-' } else { "docs/bootstrap.md $Step" }
    return [pscustomobject]@{
        Status = $Status; Id = $Id; Tier = $Tier; Fix = $fix
        Detail = ($Detail -replace '[\t\r\n]+', ' ')
    }
}

$FailingStatuses = @('missing', 'outdated', 'human')
# Ids the doctors report besides tools.tsv rows (doctor.sh's structural
# checks, the -Online and --smoke rows); tools.tsv never uses them
# (tests/test_bootstrap_manifest.py RESERVED_IDS).
$ReservedIds = @('locale', 'path-order', 'rc-pollution', 'omz-order', 'nvm-homebrew', 'payloads',
    'gh-auth', 'claude-auth', 'codex-auth', 'zsh-smoke', 'chezmoi-config')

function Limit-DoctorResult {
    # Missing, outdated and human rows outside the selected tiers only warn.
    param([Parameter(Mandatory)]$Result, [string]$Selection)
    if ($Result.Status -cin $FailingStatuses -and -not (Test-BootstrapTierSelected $Result.Tier $Selection)) {
        $Result.Detail = "$($Result.Detail) (tier $($Result.Tier) not selected)"
        $Result.Status = 'warn'
    }
    return $Result
}

function Assert-DoctorToolRow {
    param([Parameter(Mandatory)]$Row)
    $valid = $Row.id -cmatch '^[a-z0-9][a-z0-9-]*$' -and $Row.tier -cin (Get-BootstrapTierNames) -and
        $Row.version_flag -cin @('--version', '-V', '-v', 'version', '-') -and
        ($Row.floor -ceq '-' -or $Row.floor -cmatch '^[0-9]+\.[0-9]+(\.[0-9]+)?$') -and
        $Row.doc -cmatch '^[A-Za-z0-9-]+$'
    if (-not $valid) { throw [IO.InvalidDataException]::new("Invalid tools.tsv row '$($Row.id)'") }
    if ($Row.id -cin $ReservedIds) { throw [IO.InvalidDataException]::new("tools.tsv id '$($Row.id)' is reserved for a doctor check") }
    [void](Get-BootstrapProbe $Row.probe)
}

function Get-DoctorToolResult {
    param([Parameter(Mandatory)]$Row, [string]$Selection)
    $step = Get-BootstrapDocRef -Step $Row.doc -ProfileName windows
    # The same verdict W1-winget's filter in setup-host.ps1 relies on.
    $state = Get-BootstrapToolStatus $Row
    $probe = $state.Probe
    $result = switch -CaseSensitive ($state.Status) {
        'missing' { New-DoctorResult missing $Row.id $Row.tier "missing: $($Row.absent)" $step }
        'outdated' { New-DoctorResult outdated $Row.id $Row.tier "$($probe.Version) < $($Row.floor)" $step }
        'unknown' {
            New-DoctorResult warn $Row.id $Row.tier "version unknown at $($probe.Path) (needs >= $($Row.floor))" $step
        }
        default {
            $detail = if ($probe.Version) { $probe.Version } else { 'present' }
            New-DoctorResult ok $Row.id $Row.tier $detail $step
        }
    }
    return Limit-DoctorResult $result $Selection
}

function Get-DoctorChezmoiConfigResult {
    # doctor.sh's bootstrap_check_chezmoi_config: this home's chezmoi config,
    # named by cause. A config naming another checkout only warns. On Windows
    # a configured home also needs the one chezmoi.exe the login updater runs
    # (a read-only check); Unix updaters use the PATH chezmoi.
    $homeState = Get-BootstrapChezmoiState -RepoRoot $RepoRoot
    $config = Join-Path $HOME '.config/chezmoi/chezmoi.toml'
    switch -CaseSensitive ($homeState.State) {
        'ok' {
            if ($IsWindows -and -not (Test-BootstrapTrustedChezmoi -RepoRoot $RepoRoot -HomePath $HOME)) {
                return New-DoctorResult human chezmoi-config core ('~/.config/chezmoi/chezmoi.toml names this home and this checkout, but the login updater refuses ~/.local/bin/chezmoi.exe ' +
                    '(missing, a link, under a linked directory, or not private to you, SYSTEM and Administrators) and never uses a PATH chezmoi, ' +
                    'so login updates do not run; let setup-host.ps1 W1-chezmoi install a private copy') W1-chezmoi
            }
            return New-DoctorResult ok chezmoi-config core '~/.config/chezmoi/chezmoi.toml names this home and this checkout; review configuration with a scoped diff' HW-deploy
        }
        'elsewhere' {
            return New-DoctorResult warn chezmoi-config core "~/.config/chezmoi/chezmoi.toml names the checkout $($homeState.Source), not this checkout $($homeState.Checkout); run $(Join-Path $homeState.Source 'doctor.ps1') for its state" HW-deploy
        }
        'maintenance' { return New-DoctorResult human chezmoi-config core 'maintenance is active (~/.config/dotfiles/maintenance): login updates and payload installs stay off until a person removes it; see docs/updates.md' HW-deploy }
        'config' {
            if (-not $homeState.Exists) {
                return New-DoctorResult human chezmoi-config core 'there is no ~/.config/chezmoi/chezmoi.toml; a new home gets one from Fresh Windows home by hand in docs/bootstrap.md' HW-deploy
            }
            $item = Get-Item -LiteralPath $config -Force -ErrorAction SilentlyContinue
            if (-not $item -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                return New-DoctorResult human chezmoi-config core '~/.config/chezmoi/chezmoi.toml is a link; inspect it and never overwrite it blindly' HW-deploy
            }
            return New-DoctorResult human chezmoi-config core '~/.config/chezmoi/chezmoi.toml is not a regular file; inspect it and never overwrite it blindly' HW-deploy
        }
        'invalid' { return New-DoctorResult human chezmoi-config core '~/.config/chezmoi/chezmoi.toml does not name this home and a dotfiles checkout in exactly one top-level sourceDir and destDir line as chezmoi init writes them; inspect it and never overwrite it blindly' HW-deploy }
    }
    return New-DoctorResult human chezmoi-config core "$(Join-Path $RepoRoot 'lib/chezmoi-guard.ps1') is unreadable, so the chezmoi config cannot be checked; use a complete checkout" HW-deploy
}

function Get-DoctorStructuralResults {
    Get-DoctorChezmoiConfigResult
    Get-DoctorPayloadResult
}

function Get-DoctorPayloadResult {
    # Each item of DOTFILES_PAYLOAD_ITEMS (default: those with a
    # windows-install row of config/payloads.tsv, pymol skills) that installs
    # here passes its windows-probe row. Only a person installs the payload
    # repos, so every shortfall names what to run and only warns:
    # sync-payloads where the chezmoi config resolves, else this checkout's
    # quoted -Now line (sync-payloads refuses a home without a valid config,
    # and so does every hook under maintenance). An item without a
    # windows-install row (the kit, which installs nothing on native Windows)
    # is not checked, as the hook does not run it.
    $step = Get-BootstrapDocRef -Step H7-payloads -ProfileName windows
    $config = Join-Path $RepoRoot 'config/payloads.tsv'
    if (-not [IO.File]::Exists($config)) { return New-DoctorResult warn payloads ai "no readable $config" $step }
    $rows = @{}
    $known = @{}
    $available = [Collections.Generic.List[string]]::new()
    foreach ($line in [IO.File]::ReadAllLines($config)) {
        $parts = $line.Split("`t", 3)
        if (-not $line.StartsWith('#') -and $parts.Count -eq 3 -and -not $rows.ContainsKey("$($parts[0])`t$($parts[1])")) {
            $known[$parts[0]] = $true
            $rows["$($parts[0])`t$($parts[1])"] = $parts[2]
            if ($parts[1] -ceq 'windows-install') { $available.Add($parts[0]) }
        }
    }
    # A name config/payloads.tsv does not know stays, to be named below.
    $items = if ($null -ne $env:DOTFILES_PAYLOAD_ITEMS) {
        @($env:DOTFILES_PAYLOAD_ITEMS -split '\s+' | Where-Object { $_ -and ($_ -in $available -or -not $known.ContainsKey($_)) })
    }
    else { @($available) }
    $short = @()
    $found = @()
    $issues = @()
    foreach ($item in $items) {
        $probe = $rows["$item`twindows-probe"]
        $installed = $false
        if ($probe) { try { $installed = [bool](& ([scriptblock]::Create($probe))) } catch { } }
        if (-not $probe) { $short += "$item (no windows-probe row)" }
        elseif (-not $installed) { $short += $item }
        else { $found += $item }
    }
    if ($short.Count) {
        $advice = "& '" + (Join-Path (Join-Path $RepoRoot 'scripts') 'payload-update.ps1').Replace("'", "''") + "' -Now ITEM"
        if ((Get-BootstrapChezmoiState -RepoRoot $RepoRoot).State -cin @('ok', 'elsewhere')) { $advice = 'sync-payloads ITEM' }
        $issues += "not installed: $($short -join ', '): run $advice"
    }
    if ($issues.Count) { return New-DoctorResult warn payloads ai ($issues -join '; ') $step }
    if ($found.Count) { return New-DoctorResult ok payloads ai "installed: $($found -join ', ')" $step }
    return New-DoctorResult ok payloads ai 'DOTFILES_PAYLOAD_ITEMS selects no payload' $step
}

function Get-DoctorOnlineResults {
    $probes = @(
        @{ Id = 'gh-auth'; Tier = 'cli'; Tool = 'gh'; Arguments = @('auth', 'status') }
        @{ Id = 'claude-auth'; Tier = 'ai'; Tool = 'claude'; Arguments = @('auth', 'status') }
        @{ Id = 'codex-auth'; Tier = 'ai'; Tool = 'codex'; Arguments = @('login', 'status') }
    )
    foreach ($probe in $probes) {
        # doctor.sh's bootstrap_check_auth: absent is skip, signed out is warn.
        $path = Find-BootstrapCommand $probe.Tool
        if (-not $path) {
            New-DoctorResult skip $probe.Id $probe.Tier "$($probe.Tool) not found, auth not checked" HW-auth
            continue
        }
        $arguments = $probe.Arguments
        Use-BootstrapToolEnvironment { $null | & $path @arguments *> $null }
        if ($LASTEXITCODE -eq 0) {
            New-DoctorResult ok $probe.Id $probe.Tier "$($probe.Tool) is authenticated" HW-auth
        }
        else {
            New-DoctorResult warn $probe.Id $probe.Tier "$($probe.Tool) is not authenticated or could not reach its service ($($probe.Tool) $($arguments -join ' ') exited $LASTEXITCODE)" HW-auth
        }
    }
}

function Write-DoctorResult {
    param([Parameter(Mandatory)]$Result)
    $level = switch -CaseSensitive ($Result.Status) {
        ok { 'ok' }
        { $_ -cin $FailingStatuses } { 'error' }
        skip { 'info' }
        default { 'warn' }
    }
    $suffix = if ($Result.Fix -cne '-') { " ($($Result.Fix))" } else { '' }
    Write-DotfilesLog $level "$($Result.Tier) $($Result.Id): $($Result.Detail)$suffix"
}

function Invoke-BootstrapDoctor {
    # Emits TSV lines on the success stream; the exit status goes to
    # $script:DoctorStatus so no output line can be mistaken for it.
    $ErrorActionPreference = 'Stop'
    $script:DoctorStatus = 2
    $canonicalHost = $HostName.ToLowerInvariant()
    if ($canonicalHost -cne 'win') {
        Write-DotfilesLog error "doctor.ps1 checks only the win host, not '$HostName'; use ./doctor.sh --host <host> on Unix."
        return
    }
    if (-not (Test-BootstrapTierSelection $Tier)) {
        Write-DotfilesLog error "Unknown -Tier '$Tier'; use all or a comma list of $((Get-BootstrapTierNames) -join ', ')."
        return
    }
    $results = [Collections.Generic.List[object]]::new()
    try {
        $rows = @(Get-BootstrapManifestRows -Path (Join-Path $RepoRoot 'config/bootstrap/tools.tsv') -Header $ToolHeader |
                Where-Object { Test-BootstrapHostMatch $_.hosts $canonicalHost })
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($row in $rows) {
            Assert-DoctorToolRow $row
            if (-not $seen.Add($row.id)) { throw [IO.InvalidDataException]::new("tools.tsv repeats id '$($row.id)'") }
        }
        if (-not $Tsv -and -not $Quiet) { Write-DotfilesLog step "Checking host win (windows); required tiers: $Tier" }
        foreach ($row in $rows) {
            $results.Add((Get-DoctorToolResult $row $Tier))
        }
    }
    catch [IO.InvalidDataException] {
        Write-DotfilesLog error "Invalid manifest: $($_.Exception.Message)"
        return
    }
    $checks = @(Get-DoctorStructuralResults)
    if ($Online) { $checks += @(Get-DoctorOnlineResults) }
    foreach ($result in $checks) { $results.Add((Limit-DoctorResult $result $Tier)) }

    $failed = @($results | Where-Object { $_.Status -cin $FailingStatuses }).Count
    # As in doctor.sh, -Quiet hides ok and skip rows in both formats.
    $shown = @($results | Where-Object { -not $Quiet -or $_.Status -cnotin @('ok', 'skip') })
    if ($Tsv) {
        "status`tid`ttier`tdetail`tfix"
        foreach ($result in $shown) {
            @($result.Status, $result.Id, $result.Tier, $result.Detail, $result.Fix) -join "`t"
        }
    }
    else {
        foreach ($result in $shown) { Write-DoctorResult $result }
        $counts = foreach ($status in @('ok', 'outdated', 'missing', 'warn', 'skip', 'human')) {
            "$(@($results | Where-Object { $_.Status -ceq $status }).Count) $status"
        }
        Write-DotfilesLog info "summary: $($counts -join ', ') (win, required tiers: $Tier)"
    }
    $script:DoctorStatus = if ($failed) { 1 } else { 0 }
}

$libraryPath = Join-Path $RepoRoot 'lib/bootstrap.ps1'
if (-not (Test-Path -LiteralPath $libraryPath -PathType Leaf)) {
    Write-DotfilesLog error "Missing $libraryPath; this checkout is incomplete."
    exit 2
}
. $libraryPath
$script:DoctorStatus = 1
try { Invoke-BootstrapDoctor }
catch {
    Write-DotfilesLog error "doctor.ps1 failed: $($_.Exception.Message)"
    $script:DoctorStatus = 1
}
exit $script:DoctorStatus
