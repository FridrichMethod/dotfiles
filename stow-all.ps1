#Requires -Version 7.0
<#
.SYNOPSIS
    Windows installer for this dotfiles repo - the counterpart to stow-all.sh.

.DESCRIPTION
    GNU Stow does not run natively on Windows, so this script reproduces the
    subset of Stow semantics this repo depends on:

      --target=~        every package mirrors a path under $HOME
      --no-folding      individual files are linked; directories stay real
      --restow          re-running is idempotent and repairs drifted links

    Ignore patterns are read from .stowrc and from per-package
    .stow-local-ignore files, so POSIX and Windows share one source of truth.

    Requires Developer Mode (Settings > System > For developers) so that
    symlinks can be created without an elevated prompt.

.PARAMETER HostDir
    Host overlay to stow after common/. Defaults to 'win'. Pass '' to stow
    only the shared baseline.

.EXAMPLE
    .\stow-all.ps1 win

.EXAMPLE
    .\stow-all.ps1 win -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [string]$HostDir = 'win'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot
$Target = [Environment]::GetFolderPath('UserProfile')

# common/ is stowed on every host, but on Windows we take an explicit
# allowlist instead of every package: Git Bash sources ~/.bashrc and
# ~/.bash_profile, so linking the Linux shell packages in would break it.
# Terminal/editor packages are listed only where the tool runs natively.
$CommonPackages = @('claude', 'codex', 'conda', 'git', 'pymol', 'ssh', 'wezterm')

$script:Linked = 0
$script:Unchanged = 0
$script:BackedUp = 0
$script:Warnings = [System.Collections.Generic.List[string]]::new()

function Get-StowIgnorePattern {
    <#
    .SYNOPSIS
        Reads ignore regexes from .stowrc (--ignore= lines) or from a bare
        .stow-local-ignore (one pattern per line).
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Prefix = '--ignore='
    )

    if (-not (Test-Path -LiteralPath $Path)) { return @() }

    $patterns = foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        if ($Prefix -and -not $trimmed.StartsWith($Prefix)) { continue }
        $value = if ($Prefix) { $trimmed.Substring($Prefix.Length) } else { $trimmed }
        $value.Trim().Trim("'", '"')
    }

    return @($patterns)
}

function Test-StowIgnored {
    <#
    .SYNOPSIS
        Matches a package-relative path against ignore regexes.
    .DESCRIPTION
        GNU Stow matches patterns containing a slash against the relative
        path and all others against the basename. Testing both is a superset
        that is correct for every pattern this repo currently ships.
    #>
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [string[]]$Patterns
    )

    if (-not $Patterns) { return $false }
    $leaf = Split-Path -Leaf $RelativePath
    foreach ($pattern in $Patterns) {
        if ($RelativePath -match $pattern -or $leaf -match $pattern) { return $true }
    }
    return $false
}

function Invoke-PortableSync {
    <#
    .SYNOPSIS
        Runs a portable/live sync helper, mirroring the same step in
        stow-all.sh.
    .DESCRIPTION
        The claude/codex baselines are merge sources excluded from Stow by
        .stowrc, so simply stowing those packages would silently drop them.
        The helpers are POSIX sh; they run under Git Bash (claude needs jq or
        python3 on PATH, codex only awk). system32\bash.exe is WSL and would
        operate on the WSL home, so it is never used. Fail closed: any missing
        prerequisite or nonzero exit leaves the live file untouched.
    #>
    param(
        [Parameter(Mandatory)][string]$Helper,
        [Parameter(Mandatory)][string]$Portable,
        [Parameter(Mandatory)][string]$Live,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Helper) -or
        -not (Test-Path -LiteralPath $Portable)) {
        return
    }

    $git = Get-Command git -ErrorAction SilentlyContinue
    $bash = $null
    if ($git) {
        $gitRoot = Split-Path -Parent (Split-Path -Parent $git.Source)
        $candidate = Join-Path $gitRoot 'bin\bash.exe'
        if (Test-Path -LiteralPath $candidate) { $bash = $candidate }
    }
    if (-not $bash) {
        $script:Warnings.Add(
            "$Label sync skipped: Git Bash not found; portable settings " +
            "were not merged into $Live")
        return
    }

    if ($PSCmdlet.ShouldProcess($Live, "Merge portable $Label settings")) {
        & $bash ($Helper -replace '\\', '/') ($Portable -replace '\\', '/') `
            ($Live -replace '\\', '/')
        if ($LASTEXITCODE -ne 0) {
            $script:Warnings.Add(
                "$Label sync failed (exit $LASTEXITCODE); live file left " +
                "untouched: $Live")
        }
    }
}

function Test-ContentEquivalent {
    <#
    .SYNOPSIS
        True when two files carry the same content, ignoring line endings.
    .DESCRIPTION
        Adopting a file that already matches the repo is not a destructive
        change, so there is nothing worth backing up. Git for Windows checks
        out LF-tracked files as CRLF unless .gitattributes says otherwise,
        which is why an exact byte match is not enough on its own.
    #>
    param(
        [Parameter(Mandatory)][string]$PathA,
        [Parameter(Mandatory)][string]$PathB
    )

    # A destination occupied by a directory can never be equivalent to a
    # package file; without this guard Get-FileHash would throw and abort
    # the whole run instead of letting the caller back the directory up.
    if ((Test-Path -LiteralPath $PathA -PathType Container) -or
        (Test-Path -LiteralPath $PathB -PathType Container)) {
        return $false
    }

    if ((Get-FileHash -LiteralPath $PathA -Algorithm SHA256).Hash -eq
        (Get-FileHash -LiteralPath $PathB -Algorithm SHA256).Hash) {
        return $true
    }

    try {
        $textA = [System.IO.File]::ReadAllText($PathA) -replace "`r`n", "`n"
        $textB = [System.IO.File]::ReadAllText($PathB) -replace "`r`n", "`n"
    }
    catch {
        return $false
    }
    return $textA -eq $textB
}

function Invoke-StowPackage {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$PackageName,
        [string[]]$GlobalIgnores
    )

    $packagePath = Join-Path $PackageRoot $PackageName
    $localIgnores = Get-StowIgnorePattern `
        -Path (Join-Path $packagePath '.stow-local-ignore') -Prefix ''
    $patterns = @($GlobalIgnores) + @($localIgnores)

    foreach ($item in Get-ChildItem -LiteralPath $packagePath -Recurse -Force -File) {
        $relative = $item.FullName.Substring($packagePath.Length).TrimStart('\')
        $relativeUnix = $relative -replace '\\', '/'

        # Stow never installs its own control file.
        if ($relativeUnix -eq '.stow-local-ignore') { continue }

        if (Test-StowIgnored -RelativePath $relativeUnix -Patterns $patterns) {
            Write-Verbose "ignore    $PackageName/$relativeUnix"
            $script:Unchanged++
            continue
        }

        # A tracked file may itself be a symlink into a submodule
        # (common/pymol/.pymolrc). Linking an uninitialised one would only
        # propagate a dead target.
        if ($item.LinkType -eq 'SymbolicLink' -and
            -not (Test-Path -LiteralPath $item.FullName)) {
            $script:Warnings.Add(
                "dangling source skipped: $PackageName/$relativeUnix " +
                '(run: git submodule update --init --recursive)')
            continue
        }

        $destination = Join-Path $Target $relative
        $destinationDir = Split-Path -Parent $destination

        if (-not (Test-Path -LiteralPath $destinationDir)) {
            if ($PSCmdlet.ShouldProcess($destinationDir, 'Create directory')) {
                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
            }
        }

        $existing = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
        if ($existing) {
            if ($existing.LinkType -eq 'SymbolicLink') {
                if (@($existing.Target)[0] -eq $item.FullName) {
                    Write-Verbose "ok        $relativeUnix"
                    $script:Unchanged++
                    continue
                }
                if ($PSCmdlet.ShouldProcess($destination, 'Replace stale symlink')) {
                    Remove-Item -LiteralPath $destination -Force -Confirm:$false
                }
            }
            elseif (Test-ContentEquivalent -PathA $destination -PathB $item.FullName) {
                if ($PSCmdlet.ShouldProcess($destination, 'Adopt identical file')) {
                    Remove-Item -LiteralPath $destination -Force -Confirm:$false
                }
            }
            else {
                $backup = '{0}.stow-backup-{1}' -f $destination, (Get-Date -Format 'yyyyMMddHHmmss')
                if ($PSCmdlet.ShouldProcess($destination, "Back up to $backup")) {
                    Move-Item -LiteralPath $destination -Destination $backup -Force
                    Write-Host "  backup  $relativeUnix -> $(Split-Path -Leaf $backup)"
                    $script:BackedUp++
                }
            }
        }

        if ($PSCmdlet.ShouldProcess($destination, "Link to $($item.FullName)")) {
            New-Item -ItemType SymbolicLink -Path $destination `
                -Value $item.FullName -Force | Out-Null
            Write-Host "  link    $relativeUnix"
            $script:Linked++
        }
    }
}

Write-Host "Stowing from $RepoRoot"
Write-Host "Target: $Target"

$commonRoot = Join-Path $RepoRoot 'common'
if (-not (Test-Path -LiteralPath $commonRoot)) {
    throw "missing common dir: $commonRoot"
}

$globalIgnores = Get-StowIgnorePattern -Path (Join-Path $RepoRoot '.stowrc')

# Portable/live sync first, mirroring stow-all.sh: a host layer may override
# the portable merge source wholesale.
$codexPortable = Join-Path $commonRoot 'codex\.codex\config.toml'
$claudePortable = Join-Path $commonRoot 'claude\.claude\settings.json'
if ($HostDir) {
    $codexHost = Join-Path $RepoRoot "$HostDir\codex\.codex\config.toml"
    if (Test-Path -LiteralPath $codexHost) { $codexPortable = $codexHost }
    $claudeHost = Join-Path $RepoRoot "$HostDir\claude\.claude\settings.json"
    if (Test-Path -LiteralPath $claudeHost) { $claudePortable = $claudeHost }
}
Invoke-PortableSync -Label 'Codex' `
    -Helper (Join-Path $commonRoot 'codex\.local\bin\codex-config-sync') `
    -Portable $codexPortable `
    -Live (Join-Path $Target '.codex\config.toml')
Invoke-PortableSync -Label 'Claude' `
    -Helper (Join-Path $commonRoot 'claude\.local\bin\claude-settings-sync') `
    -Portable $claudePortable `
    -Live (Join-Path $Target '.claude\settings.json')

Write-Host "`nStowing common packages:"
Write-Host ($CommonPackages -join ' ')
foreach ($package in $CommonPackages) {
    if (-not (Test-Path -LiteralPath (Join-Path $commonRoot $package))) {
        $script:Warnings.Add("common package not found, skipped: $package")
        continue
    }
    Invoke-StowPackage -PackageRoot $commonRoot -PackageName $package `
        -GlobalIgnores $globalIgnores
}

if ($HostDir) {
    $hostRoot = Join-Path $RepoRoot $HostDir
    if (-not (Test-Path -LiteralPath $hostRoot)) {
        throw "host dir not found: $hostRoot"
    }
    $hostPackages = @(Get-ChildItem -LiteralPath $hostRoot -Directory |
            Select-Object -ExpandProperty Name)
    Write-Host "`nStowing host-specific packages ($HostDir):"
    Write-Host ($hostPackages -join ' ')
    foreach ($package in $hostPackages) {
        Invoke-StowPackage -PackageRoot $hostRoot -PackageName $package `
            -GlobalIgnores $globalIgnores
    }
}

# A OneDrive-redirected Documents folder would strip the profile links of any
# effect, so check the path PowerShell actually loads.
$profileRoot = Join-Path $Target 'Documents\PowerShell'
if ((Test-Path -LiteralPath $profileRoot) -and
    -not $PROFILE.CurrentUserAllHosts.StartsWith($profileRoot, [StringComparison]::OrdinalIgnoreCase)) {
    $script:Warnings.Add(
        "PowerShell loads $($PROFILE.CurrentUserAllHosts) but profiles were stowed " +
        "under $profileRoot (Documents may be redirected to OneDrive)")
}

Write-Host "`nlinked: $script:Linked   unchanged/ignored: $script:Unchanged   backed up: $script:BackedUp"
foreach ($warning in $script:Warnings) { Write-Warning $warning }
