#Requires -Version 7.0
<#
.SYNOPSIS
    Read-only day-zero check for the win host - the Windows twin of doctor.sh.

.DESCRIPTION
    Probes every config/bootstrap/tools.tsv row whose hosts match win, plus
    three structural checks (venv-sync, submodule, core-symlinks), and prints
    one line per check:

      [dotfiles] [<level>] <tier> <id>: <detail> (docs/bootstrap.md <step>)

    Statuses are ok, outdated, missing, warn, skip and human. A missing or
    outdated row outside the selected tiers is reported as warn. Executables
    are found by probing PATH entries for .exe, .cmd, .bat and .ps1 files;
    PowerShell modules by a directory in a PSModulePath entry; the Nerd Font
    by a file name in the system or per-user Windows font directory.

    The doctor writes nothing and makes no network call: no winget list, no
    module repository query. -Online adds the auth probes gh auth status,
    claude auth status and codex login status, reported as human when signed
    out.

    Exit codes: 0 every selected-tier check is ok (warn, skip and human do
    not fail); 1 a selected-tier row is missing or outdated, or a structural
    check failed; 2 usage error, unknown host or invalid manifest.

.PARAMETER HostName
    Alias -Host. Only win is accepted; use ./doctor.sh --host <host> on Unix.

.PARAMETER Tier
    all, or a comma list of core, cli, ai, desktop, contributor, host.
    Defaults to core,cli,ai.

.PARAMETER Tsv
    Print a header and exactly five tab-separated columns per check:
    status, id, tier, detail, fix (docs/bootstrap.md <step>, or -).

.PARAMETER Quiet
    Print only checks that are not ok, and the summary only on failure.

.PARAMETER Online
    Also run the network auth probes.

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
    $fix = if ($Status -ceq 'ok' -or -not $Step) { '-' } else { "docs/bootstrap.md $Step" }
    return [pscustomobject]@{
        Status = $Status; Id = $Id; Tier = $Tier; Fix = $fix
        Detail = ($Detail -replace '[\t\r\n]+', ' ')
    }
}

function Limit-DoctorResult {
    # Missing or outdated rows outside the selected tiers only warn.
    param([Parameter(Mandatory)]$Result, [string]$Selection)
    if ($Result.Status -cin @('missing', 'outdated') -and -not (Test-BootstrapTierSelected $Result.Tier $Selection)) {
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
    [void](Get-BootstrapProbe $Row.probe)
}

function Get-DoctorToolResult {
    param([Parameter(Mandatory)]$Row, [string]$Selection)
    $step = Get-BootstrapDocRef -Step $Row.doc -ProfileName windows
    $probe = Test-BootstrapTool -Probe $Row.probe -VersionFlag $Row.version_flag
    if (-not $probe.Found) {
        $result = New-DoctorResult missing $Row.id $Row.tier "missing: $($Row.absent)" $step
    }
    elseif ($Row.floor -cne '-') {
        $result = switch (Compare-BootstrapVersion $probe.Version $Row.floor) {
            0 { New-DoctorResult ok $Row.id $Row.tier $probe.Version $step }
            1 { New-DoctorResult outdated $Row.id $Row.tier "$($probe.Version) < $($Row.floor)" $step }
            default {
                New-DoctorResult warn $Row.id $Row.tier "version unknown at $($probe.Path) (needs >= $($Row.floor))" $step
            }
        }
    }
    else {
        $detail = if ($probe.Version) { $probe.Version } else { 'present' }
        $result = New-DoctorResult ok $Row.id $Row.tier $detail $step
    }
    return Limit-DoctorResult $result $Selection
}

function Get-DoctorStructuralResults {
    $python = if ($IsWindows) { '.venv-sync/Scripts/python.exe' } else { '.venv-sync/bin/python' }
    $setupSync = Get-BootstrapDocRef -Step S4-setup-sync -ProfileName windows
    if ([IO.File]::Exists((Join-Path $RepoRoot $python))) {
        New-DoctorResult ok venv-sync core 'present' $setupSync
    }
    else {
        New-DoctorResult missing venv-sync core 'missing: setup-sync.ps1 has not run, so stow-all.ps1 cannot sync AI configs' $setupSync
    }

    $paths = @()
    $modules = Join-Path $RepoRoot '.gitmodules'
    if ([IO.File]::Exists($modules)) {
        $paths = @([IO.File]::ReadAllLines($modules) | ForEach-Object {
                if ($_ -match '^\s*path\s*=\s*(.+?)\s*$') { $Matches[1] }
            })
    }
    $absent = @($paths | Where-Object { -not (Test-Path -LiteralPath (Join-Path (Join-Path $RepoRoot $_) '.git')) })
    if ($absent.Count) {
        New-DoctorResult missing submodule core "not initialized: $($absent -join ', '); run git submodule update --init --recursive" P0-preflight
    }
    else { New-DoctorResult ok submodule core "$($paths.Count) initialized" P0-preflight }

    $git = Find-BootstrapCommand 'git'
    if (-not $git) {
        New-DoctorResult skip core-symlinks core 'git is not on PATH' HW-clone
    }
    else {
        $value = @(& $git --no-optional-locks -C $RepoRoot config --get core.symlinks 2>$null) -join ''
        if ($value -ceq 'true') { New-DoctorResult ok core-symlinks core 'core.symlinks is true' HW-clone }
        else {
            $shown = if ($value) { $value } else { 'unset' }
            New-DoctorResult missing core-symlinks core "core.symlinks is $shown in this clone; tracked symlinks are plain files" HW-clone
        }
    }
}

function Get-DoctorOnlineResults {
    $probes = @(
        @{ Id = 'gh-auth'; Tier = 'cli'; Tool = 'gh'; Arguments = @('auth', 'status') }
        @{ Id = 'claude-auth'; Tier = 'ai'; Tool = 'claude'; Arguments = @('auth', 'status') }
        @{ Id = 'codex-auth'; Tier = 'ai'; Tool = 'codex'; Arguments = @('login', 'status') }
    )
    foreach ($probe in $probes) {
        $path = Find-BootstrapCommand $probe.Tool
        if (-not $path) {
            New-DoctorResult skip $probe.Id $probe.Tier "$($probe.Tool) is not on PATH" HW-auth
            continue
        }
        $arguments = $probe.Arguments
        $null | & $path @arguments *> $null
        if ($LASTEXITCODE -eq 0) {
            New-DoctorResult ok $probe.Id $probe.Tier "$($probe.Tool) $($arguments -join ' ') succeeded" HW-auth
        }
        else {
            New-DoctorResult human $probe.Id $probe.Tier "$($probe.Tool) $($arguments -join ' ') exited $LASTEXITCODE; sign in" HW-auth
        }
    }
}

function Write-DoctorResult {
    param([Parameter(Mandatory)]$Result)
    $level = switch -CaseSensitive ($Result.Status) {
        ok { 'ok' }
        { $_ -cin @('missing', 'outdated') } { 'error' }
        skip { 'info' }
        default { 'warn' }
    }
    if ($Quiet -and $level -cin @('ok', 'info')) { return }
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
        foreach ($row in $rows) { Assert-DoctorToolRow $row }
        if (-not $Tsv -and -not $Quiet) { Write-DotfilesLog step "doctor win (tiers $Tier)" }
        foreach ($row in $rows) { $results.Add((Get-DoctorToolResult $row $Tier)) }
    }
    catch [IO.InvalidDataException] {
        Write-DotfilesLog error "Invalid manifest: $($_.Exception.Message)"
        return
    }
    foreach ($result in @(Get-DoctorStructuralResults)) { $results.Add((Limit-DoctorResult $result $Tier)) }
    if ($Online) { foreach ($result in @(Get-DoctorOnlineResults)) { $results.Add($result) } }

    $failed = @($results | Where-Object { $_.Status -cin @('missing', 'outdated') }).Count
    if ($Tsv) {
        "status`tid`ttier`tdetail`tfix"
        foreach ($result in $results) {
            @($result.Status, $result.Id, $result.Tier, $result.Detail, $result.Fix) -join "`t"
        }
    }
    else {
        foreach ($result in $results) { Write-DoctorResult $result }
        $counts = foreach ($status in @('ok', 'outdated', 'missing', 'warn', 'skip', 'human')) {
            "$(@($results | Where-Object { $_.Status -ceq $status }).Count) $status"
        }
        if ($failed) { Write-DotfilesLog error "doctor win: $($counts -join ', ')" }
        elseif (-not $Quiet) { Write-DotfilesLog ok "doctor win: $($counts -join ', ')" }
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
