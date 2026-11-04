#Requires -Version 7.0
<#
.SYNOPSIS
    Read-only day-zero check for the win host - the Windows twin of doctor.sh.

.DESCRIPTION
    Probes every config/bootstrap/tools.tsv row whose hosts match win, plus
    the structural checks native-config (with -LegacyStow, venv-sync) and
    payloads, prints one line per check and then a summary:

      [dotfiles] [<level>] <tier> <id>: <detail> (docs/bootstrap.md <step>)

    Statuses are ok, outdated, missing, warn, skip and human, with the same
    meaning as in doctor.sh: missing, outdated and human are errors, and
    outside the selected tiers they are reported as warn. Executables are
    found by probing PATH entries for .exe, .cmd, .bat and .ps1 files (a
    Microsoft Store alias that prints no version does not count);
    PowerShell modules by a directory in a PSModulePath entry; the Nerd Font
    by a file name in the system or per-user Windows font directory.
    Only -LegacyStow checks venv-sync; native mode checks chezmoi and the
    home-bound native configuration signal, named by cause: a binding to
    another checkout and a stray ~/.config/chezmoi/chezmoistate.boltdb only
    warn, and on Windows a bound home whose ~/.local/bin/chezmoi.exe the
    login updater refuses is human. Legacy venv-sync passes when the
    interpreter the AI config sync helpers use (DOTFILES_SYNC_PYTHON when
    set, else .venv-sync) passes lib/config_sync.py --runtime-check.

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

.PARAMETER LegacyStow
    Check the supported Stow/parser compatibility path instead of native chezmoi.

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
    [switch]$Online,
    [switch]$LegacyStow
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
$ReservedIds = @('locale', 'venv-sync', 'stow-links', 'path-order', 'rc-pollution', 'omz-order',
    'nvm-homebrew', 'payloads', 'gh-auth', 'claude-auth', 'codex-auth', 'zsh-smoke', 'native-config')

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

function Get-DoctorSyncRuntimeResult {
    # The interpreter lib/sync-runtime.sh would run for stow-all.ps1's
    # helpers must pass lib/config_sync.py --runtime-check (read-only).
    $step = Get-BootstrapDocRef -Step S4-setup-sync -ProfileName windows
    $runtime = Get-BootstrapSyncPython $RepoRoot
    $ready = Test-BootstrapSyncRuntime -Python $runtime.Path -RepoRoot $RepoRoot
    if ($runtime.Source -ceq 'DOTFILES_SYNC_PYTHON') {
        if ($ready) { return New-DoctorResult ok venv-sync core "DOTFILES_SYNC_PYTHON=$($runtime.Path) passes the runtime check" $step }
        return New-DoctorResult missing venv-sync core "DOTFILES_SYNC_PYTHON='$($runtime.Path)' fails lib/config_sync.py --runtime-check; the AI config sync helpers cannot run" $step
    }
    if ($ready) { return New-DoctorResult ok venv-sync core "AI-sync runtime ready at $($runtime.Path)" $step }
    if (-not [IO.File]::Exists($runtime.Path)) {
        return New-DoctorResult missing venv-sync core "no $($runtime.Path); setup-sync.ps1 has not run, so stow-all.ps1 cannot sync AI configs" $step
    }
    return New-DoctorResult missing venv-sync core "$($runtime.Path) fails lib/config_sync.py --runtime-check; rerun setup-sync.ps1" $step
}

function Get-DoctorNativeConfigResult {
    # doctor.sh's bootstrap_check_native_config: the native binding, named by
    # cause. A binding to another checkout and a stray state database that a
    # chezmoi command without the updater's arguments wrote only warn; the
    # doctor never removes that file. On Windows a bound home also needs the
    # one chezmoi.exe the login updater runs (read-only check, before the
    # stray database); Unix updaters use the PATH chezmoi.
    $native = Get-BootstrapNativeState -RepoRoot $RepoRoot
    $takeover = 'follow docs/chezmoi-migration/takeover.md'
    switch -CaseSensitive ($native.State) {
        'ok' {
            if ($IsWindows -and -not (Test-BootstrapNativeChezmoi -RepoRoot $RepoRoot -HomePath $HOME)) {
                return New-DoctorResult human native-config core ("native binding and local config present, but the login updater refuses ~/.local/bin/chezmoi.exe " +
                    '(missing, a link, under a linked directory, or not private to you, SYSTEM and Administrators) and never uses a PATH chezmoi, ' +
                    'so native updates do not run; let setup-host.ps1 W1-chezmoi install a private copy') W1-chezmoi
            }
            $stray = Join-Path $HOME '.config/chezmoi/chezmoistate.boltdb'
            if (Get-Item -LiteralPath $stray -Force -ErrorAction SilentlyContinue) {
                return New-DoctorResult warn native-config core ("native binding and local config present, but ~/.config/chezmoi/chezmoistate.boltdb exists: " +
                    "a chezmoi command without the updater's full explicit argument set wrote this separate state database; " +
                    'run every manual native command with that argument set (docs/chezmoi-migration/takeover.md); the doctor leaves the file in place') HW-native
            }
            return New-DoctorResult ok native-config core 'native binding and local config present; review configuration with scoped native diff' HW-native
        }
        'elsewhere' {
            return New-DoctorResult warn native-config core "this home is bound to $($native.Source), not to this checkout $($native.Checkout); run $(Join-Path $native.Source 'doctor.ps1') for its native state" HW-native
        }
        'maintenance' { return New-DoctorResult human native-config core "maintenance is active (~/.config/dotfiles/maintenance): native updates and payload installs stay off until the reviewed procedure removes it; $takeover" HW-native }
        'unbound' { return New-DoctorResult human native-config core "no native binding (~/.config/dotfiles/native): this home's native handover is not done; $takeover" HW-native }
        'invalid' { return New-DoctorResult human native-config core "the native binding ~/.config/dotfiles/native is not valid for this home; inspect it, never overwrite it blindly, and $takeover" HW-native }
        'config' { return New-DoctorResult human native-config core "the local config ~/.config/chezmoi/chezmoi.toml is absent or not a regular file; $takeover" HW-native }
    }
    return New-DoctorResult human native-config core "$(Join-Path $RepoRoot 'lib/chezmoi-guard.ps1') is unreadable, so the native binding cannot be checked; use a complete checkout" HW-native
}

function Get-DoctorStructuralResults {
    if ($LegacyStow) { Get-DoctorSyncRuntimeResult }
    else { Get-DoctorNativeConfigResult }
    Get-DoctorPayloadResult
}

function Get-DoctorPayloadResult {
    # Each item of DOTFILES_PAYLOAD_ITEMS (default: those with a
    # windows-install row of config/payloads.tsv, pymol skills) that installs
    # here passes its windows-probe row; an item that waits for stow-all (a
    # stow-links path still linked into the retired package) is named with
    # what to run. Only a person installs the payload repos (sync-payloads),
    # so every shortfall names that and only warns. An item without a
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
        $words = @("$($rows["$item`tstow-links"])".Split(' ', [StringSplitOptions]::RemoveEmptyEntries))
        foreach ($path in @($words | Select-Object -Skip 1)) {
            $link = Get-Item -LiteralPath (Join-Path $HOME $path) -Force -ErrorAction SilentlyContinue
            if ($link -and $link.LinkType -and "$(@($link.Target)[0])".Replace('\', '/') -like "*common/$($words[0])/*") {
                $issues += "$item waits for stow-all: ~/$path is still a link the retired $($words[0]) Stow package made, which its installer refuses: run stow-all.ps1 from an elevated PowerShell 7, then sync-payloads $item"
                break
            }
        }
        $probe = $rows["$item`twindows-probe"]
        $installed = $false
        if ($probe) { try { $installed = [bool](& ([scriptblock]::Create($probe))) } catch { } }
        if (-not $probe) { $short += "$item (no windows-probe row)" }
        elseif (-not $installed) { $short += $item }
        else { $found += $item }
    }
    if ($short.Count) {
        $issues += "not installed: $($short -join ', '): run sync-payloads ITEM"
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
            if ($LegacyStow -and $row.id -ceq 'chezmoi') { continue }
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
