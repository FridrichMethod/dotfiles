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

    Run this from an elevated PowerShell. Developer Mode (Settings >
    System > For developers) also lets it create symlinks without elevation,
    but a symlink created by a non-elevated process is an untrusted reparse
    point. Processes enforcing RedirectionGuard, including protected OpenSSH
    sessions, refuse to traverse it with "the path cannot be traversed because
    it contains an untrusted mount point" even when a local console can read
    the same link. A separate read-only process enables RedirectionGuard to
    check links even from a local console. An elevated run repairs rejected
    source and destination links, preserving source links' relative targets.
    Unsupported or failed trust checks stop the installation before syncing.
    Declining any change leaves the installation partial; Strict reports a
    failure and the login updater never records that revision as applied.

.PARAMETER Strict
    Fail if any package, link or portable sync was skipped or warned.
    Successful installations remember the host and applied revision for
    the login updater. Register the Windows worker once with:
      .\scripts\dotfiles-auto-stow.ps1 -Register

.PARAMETER HostDir
    Host overlay to stow after common/. Defaults to 'win'. Pass '' to stow
    only the shared baseline.

.PARAMETER TargetRoot
    Explicit target directory for a disposable installation or test. Defaults
    to the real Windows user profile. A different target never records login
    updater state. Run setup-sync.ps1 once before installing; every selected
    AI configuration is checked before any helper or package is applied.

.EXAMPLE
    .\stow-all.ps1 win

.EXAMPLE
    .\stow-all.ps1 win -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [AllowEmptyString()]
    [string]$HostDir = 'win',
    # Automatic workers treat skipped syncs or links as failures.
    [switch]$Strict,
    [string]$TargetRoot = [Environment]::GetFolderPath('UserProfile')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
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

trap {
    Write-DotfilesLog error $_.Exception.Message
    throw
}

$HostDir = $HostDir.ToLowerInvariant()
if (-not $IsWindows) { throw 'Use stow-all.sh on Unix; stow-all.ps1 requires native Windows.' }
if ($HostDir -cnotin @('', 'win')) { throw "Unsupported Windows host: '$HostDir'; use 'win' or ''." }
if ([string]::IsNullOrWhiteSpace($TargetRoot) -or -not [IO.Path]::IsPathFullyQualified($TargetRoot)) {
    throw 'TargetRoot must be an absolute Windows directory path.'
}
$Target = [IO.Path]::GetFullPath($TargetRoot)
if ($Target.TrimEnd('\', '/') -eq [IO.Path]::GetPathRoot($Target).TrimEnd('\', '/')) {
    throw 'TargetRoot must not be a drive or share root.'
}
$Target = $Target.TrimEnd('\', '/')
$profileTarget = [IO.Path]::GetFullPath([Environment]::GetFolderPath('UserProfile')).TrimEnd('\', '/')
$recordAppliedState = $Target.Equals($profileTarget, [StringComparison]::OrdinalIgnoreCase)
if (Test-Path -LiteralPath $Target -PathType Leaf) { throw "TargetRoot is not a directory: $Target" }
$commonRoot = Join-Path $RepoRoot 'common'
if (-not (Test-Path -LiteralPath $commonRoot -PathType Container)) {
    throw "missing common dir: $commonRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.stowrc') -PathType Leaf)) {
    throw 'Missing .stowrc; refusing to install without materialized-file exclusions.'
}
$hostRoot = $null
$hostPackages = @()
if ($HostDir) {
    $hostRoot = Join-Path $RepoRoot $HostDir
    if (-not (Test-Path -LiteralPath $hostRoot -PathType Container)) {
        throw "host dir not found: $hostRoot"
    }
    $hostPackages = @(Get-ChildItem -LiteralPath $hostRoot -Directory |
            Select-Object -ExpandProperty Name)
}
$stowStartHead = git -C $RepoRoot rev-parse --verify HEAD 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve starting dotfiles HEAD.' }

# common/ is stowed on every host, but on Windows we take an explicit
# allowlist instead of every package: Git Bash sources ~/.bashrc and
# ~/.bash_profile, so linking the Linux shell packages in would break it.
# Terminal/editor packages are listed only where the tool runs natively.
$CommonPackages = @('claude', 'codex', 'conda', 'git', 'pymol', 'ssh', 'wezterm')

$script:Linked = 0
$script:Repaired = 0
$script:Unchanged = 0
$script:BackedUp = 0
$script:Warnings = [System.Collections.Generic.List[string]]::new()
$script:LinkReadErrors = @{}
$script:InstalledPaths = [Collections.Generic.List[string]]::new()
. (Join-Path $RepoRoot 'lib/windows-link-trust.ps1')

# Only a token holding SeCreateSymbolicLinkPrivilege creates trusted symlinks,
# so both the repair path and the closing warning need to know how we run.
$script:Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$script:IsElevated = ([Security.Principal.WindowsPrincipal]$script:Identity).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

function Test-StowShouldProcess {
    # A declined operation makes this installation partial. WhatIf is a
    # successful preview, so it does not contribute warnings or fail Strict.
    param([string]$Path, [string]$Action)
    if ($PSCmdlet.ShouldProcess($Path, $Action)) { return $true }
    if (-not $WhatIfPreference) {
        $script:Warnings.Add("operation declined: $Action ($Path)")
    }
    return $false
}

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
        The Claude/Codex baselines are merge or materialization sources
        excluded from Stow, so simply stowing those packages would silently
        drop them. The helpers are POSIX sh and run under Git Bash.
        system32\bash.exe is WSL and would operate on the WSL home, so it is
        never used. CheckOnly runs the helper's read-only validation before
        any selected file is applied. Apply failures stop installation and
        never acknowledge the current revision.
    #>
    param(
        [Parameter(Mandatory)][string]$Helper,
        [Parameter(Mandatory)][string]$Portable,
        [Parameter(Mandatory)][string]$Live,
        [Parameter(Mandatory)][string]$Label,
        [switch]$CheckOnly
    )

    if (-not (Test-Path -LiteralPath $Helper -PathType Leaf) -or
        -not (Test-Path -LiteralPath $Portable -PathType Leaf)) {
        throw "$Label sync prerequisite missing: helper or portable source."
    }

    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $bash = $null
    if ($git) {
        # Git may be exposed from cmd/, bin/, or mingw64/bin/. Only inspect
        # its own installation; never accidentally choose system32/WSL bash.
        $gitDirectory = Split-Path -Parent $git.Source
        for ($depth = 0; $depth -lt 3 -and $gitDirectory -and -not $bash; $depth++) {
            foreach ($relative in @('bin\bash.exe', 'usr\bin\bash.exe')) {
                $candidate = Join-Path $gitDirectory $relative
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { $bash = $candidate; break }
            }
            $gitDirectory = Split-Path -Parent $gitDirectory
        }
    }
    if (-not $bash) {
        throw "$Label sync prerequisite missing: Git Bash from the Git for Windows installation."
    }

    if ($CheckOnly -or (Test-StowShouldProcess $Live "Synchronize portable $Label")) {
        $syncArguments = @(($Helper -replace '\\', '/'), '--quiet')
        if ($CheckOnly) { $syncArguments += '--check' }
        $syncArguments += @(($Portable -replace '\\', '/'), ($Live -replace '\\', '/'))
        & $bash @syncArguments
        if ($LASTEXITCODE -ne 0) {
            $phase = if ($CheckOnly) { 'preflight' } else { 'apply' }
            throw "$Label sync $phase failed (exit $LASTEXITCODE); installation was not acknowledged."
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
        # Only normalize CRLF in valid UTF-8. Replacement decoding can turn
        # different binary bytes into the same text and destroy a conflict.
        $utf8 = [Text.UTF8Encoding]::new($false, $true)
        $textA = $utf8.GetString([System.IO.File]::ReadAllBytes($PathA)).Replace("`r`n", "`n")
        $textB = $utf8.GetString([System.IO.File]::ReadAllBytes($PathB)).Replace("`r`n", "`n")
    }
    catch {
        return $false
    }
    return [string]::Equals($textA, $textB, [StringComparison]::Ordinal)
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
        $relative = $item.FullName.Substring($packagePath.Length).TrimStart('\', '/')
        $relativeUnix = $relative -replace '\\', '/'

        # Stow never installs its own control file.
        if ($relativeUnix -eq '.stow-local-ignore') { continue }

        if (Test-StowIgnored -RelativePath $relativeUnix -Patterns $patterns) {
            Write-Verbose "ignore    $PackageName/$relativeUnix"
            $script:Unchanged++
            continue
        }

        # A source can itself be a symlink (for example .pymolrc into a
        # submodule). Check it before its destination so repairing the outer
        # link cannot hide an untrusted source in the chain.
        $sourceRepaired = $false
        if ($item.LinkType -eq 'SymbolicLink') {
            $sourceError = $script:LinkReadErrors[$item.FullName]
            if ($sourceError -in @(2, 3)) {
                $script:Warnings.Add(
                    "dangling source skipped: $PackageName/$relativeUnix " +
                    '(run: git submodule update --init --recursive)')
                continue
            }
            if ($sourceError -eq 448) {
                if (-not $script:IsElevated) {
                    $script:Warnings.Add("untrusted source symlink left in place: $PackageName/$relativeUnix (re-run elevated)")
                    continue
                }
                if (-not (Test-StowShouldProcess $item.FullName 'Repair untrusted source symlink')) { continue }
                # Use the raw target, never a resolved absolute path: Git
                # tracks relative symlink text, including submodule links.
                New-Item -ItemType SymbolicLink -Path $item.FullName `
                    -Value @($item.Target)[0] -Force -Confirm:$false | Out-Null
                $sourceError = (Get-DotfilesLinkReadErrors -Paths @($item.FullName))[$item.FullName]
                $script:LinkReadErrors[$item.FullName] = $sourceError
                $script:Repaired++
                $sourceRepaired = $true
            }
            if ($sourceError -ne 0) {
                $script:Warnings.Add("source unreadable under RedirectionGuard, skipped: $PackageName/$relativeUnix (Win32 $sourceError)")
                continue
            }
        }

        $destination = Join-Path $Target $relative
        $destinationDir = Split-Path -Parent $destination

        $backup = $null
        $removeExisting = $false
        $action = "Link to $($item.FullName)"
        $existing = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
        if ($existing) {
            if ($existing.LinkType -eq 'SymbolicLink') {
                if (@($existing.Target)[0] -eq $item.FullName) {
                    $linkError = if ($sourceRepaired) {
                        (Get-DotfilesLinkReadErrors -Paths @($destination))[$destination]
                    } else { $script:LinkReadErrors[$destination] }
                    if ($linkError -eq 0) {
                        Write-Verbose "ok        $relativeUnix"
                        $script:Unchanged++
                        continue
                    }
                    if ($linkError -ne 448) {
                        $script:Warnings.Add("symlink unreadable under RedirectionGuard, skipped: $relativeUnix (Win32 $linkError)")
                        continue
                    }
                    # Recreating it is the only repair, and only an elevated
                    # token makes the replacement any more trusted than the
                    # link already there.
                    if (-not $script:IsElevated) {
                        $script:Warnings.Add(
                            "untrusted symlink left in place: $relativeUnix " +
                            '(re-run from an elevated PowerShell to repair it)')
                        $script:Unchanged++
                        continue
                    }
                    if (Test-StowShouldProcess $destination 'Repair untrusted symlink') {
                        New-Item -ItemType SymbolicLink -Path $destination `
                            -Value $item.FullName -Force -Confirm:$false | Out-Null
                        $repairedError = (Get-DotfilesLinkReadErrors -Paths @($destination))[$destination]
                        if ($repairedError -ne 0) {
                            throw "Repaired symlink is still unreadable under RedirectionGuard: $destination (Win32 $repairedError)"
                        }
                        Write-Verbose "repair    $relativeUnix"
                        $script:Repaired++
                    }
                    continue
                }
                $action = "Replace stale symlink with link to $($item.FullName)"
                $removeExisting = $true
            }
            elseif (Test-ContentEquivalent -PathA $destination -PathB $item.FullName) {
                $action = "Adopt identical file as link to $($item.FullName)"
                $removeExisting = $true
            }
            else {
                $backup = '{0}.stow-backup-{1}-{2}' -f $destination,
                    (Get-Date -Format 'yyyyMMddHHmmss'), [Guid]::NewGuid().ToString('N')
                $action = "Back up to $backup and link to $($item.FullName)"
            }
        }

        # Backup/removal and replacement are one consent decision. In
        # particular, declining a backup must never fall through to a forced
        # link creation that can overwrite the original without a backup.
        if (-not (Test-StowShouldProcess $destination $action)) { continue }
        if (-not (Test-Path -LiteralPath $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir -Force -Confirm:$false | Out-Null
        }
        if ($backup) {
            Move-Item -LiteralPath $destination -Destination $backup -Confirm:$false
            Write-DotfilesLog info "Backed up $relativeUnix -> $(Split-Path -Leaf $backup)"
            $script:BackedUp++
        } elseif ($removeExisting) {
            Remove-Item -LiteralPath $destination -Force -Confirm:$false
        }
        # Do not overwrite a file that appeared after the initial check.
        New-Item -ItemType SymbolicLink -Path $destination `
            -Value $item.FullName -Confirm:$false | Out-Null
        Write-Verbose "link      $relativeUnix"
        $script:Linked++
        $script:InstalledPaths.Add($destination)
    }
}

Write-DotfilesLog step "Checking portable settings and packages for $Target"
Write-Verbose "Stowing from $RepoRoot"

$globalIgnores = Get-StowIgnorePattern -Path (Join-Path $RepoRoot '.stowrc')

# Portable/live sync first, mirroring stow-all.sh: a host layer may override
# the portable merge source wholesale.
$codexPortable = Join-Path $commonRoot 'codex\.codex\config.toml'
$codexRulesPortable = Join-Path $commonRoot 'codex\.codex\rules\portable.rules'
# The common Claude package also links its local hooks/status line; Node.js 18+
# must be on PATH when Claude runs those helpers.
$claudePortable = Join-Path $commonRoot 'claude\.claude\settings.json'
if ($HostDir) {
    $codexHost = Join-Path $RepoRoot "$HostDir\codex\.codex\config.toml"
    if (Test-Path -LiteralPath $codexHost) { $codexPortable = $codexHost }
    $codexRulesHost = Join-Path $RepoRoot `
        "$HostDir\codex\.codex\rules\portable.rules"
    if (Test-Path -LiteralPath $codexRulesHost) {
        $codexRulesPortable = $codexRulesHost
    }
    $claudeHost = Join-Path $RepoRoot "$HostDir\claude\.claude\settings.json"
    if (Test-Path -LiteralPath $claudeHost) { $claudePortable = $claudeHost }
}
$syncPlan = @(
    @{ Label = 'Codex settings'; Helper = Join-Path $commonRoot 'codex\.local\bin\codex-config-sync'
        Portable = $codexPortable; Live = Join-Path $Target '.codex\config.toml' },
    @{ Label = 'Codex rules'; Helper = Join-Path $commonRoot 'codex\.local\bin\codex-rules-sync'
        Portable = $codexRulesPortable; Live = Join-Path $Target '.codex\rules\portable.rules' },
    @{ Label = 'Claude settings'; Helper = Join-Path $commonRoot 'claude\.local\bin\claude-settings-sync'
        Portable = $claudePortable; Live = Join-Path $Target '.claude\settings.json' }
)

# Validate every selected merge and every ignore expression before mutation.
# --check must also leave a missing target directory absent during -WhatIf.
foreach ($sync in $syncPlan) { Invoke-PortableSync @sync -CheckOnly }
$probePaths = [Collections.Generic.List[string]]::new()
foreach ($rootAndPackages in @(
        @{ Root = $commonRoot; Packages = $CommonPackages },
        @{ Root = $hostRoot; Packages = $hostPackages })) {
    foreach ($package in $rootAndPackages.Packages) {
        $packagePath = Join-Path $rootAndPackages.Root $package
        if (-not (Test-Path -LiteralPath $packagePath -PathType Container)) {
            $script:Warnings.Add("common package not found, skipped: $package")
            continue
        }
        $patterns = @($globalIgnores) + @(Get-StowIgnorePattern `
                -Path (Join-Path $packagePath '.stow-local-ignore') -Prefix '')
        foreach ($pattern in $patterns) { [void][regex]::new($pattern) }
        foreach ($item in Get-ChildItem -LiteralPath $packagePath -Recurse -Force -File) {
            $relative = $item.FullName.Substring($packagePath.Length).TrimStart('\', '/')
            if ($relative -eq '.stow-local-ignore' -or
                (Test-StowIgnored -RelativePath ($relative -replace '\\', '/') -Patterns $patterns)) { continue }
            if ($item.LinkType -eq 'SymbolicLink') { $probePaths.Add($item.FullName) }
            $destination = Join-Path $Target $relative
            $existing = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
            if ($existing -and $existing.LinkType -eq 'SymbolicLink' -and
                @($existing.Target)[0] -eq $item.FullName) { $probePaths.Add($destination) }
        }
    }
}
# Even an initial install checks policy availability before any apply. The
# source script is an ordinary readable file and also validates the checkout's
# parent path. A failed/unsupported probe must never count as trusted.
$probePaths.Add($PSCommandPath)
$script:LinkReadErrors = Get-DotfilesLinkReadErrors -Paths $probePaths.ToArray()
if ($script:LinkReadErrors[$PSCommandPath] -ne 0) {
    throw 'The installer checkout is not readable under RedirectionGuard; repair its parent path first.'
}
if ($Strict -and $script:Warnings.Count -gt 0) {
    throw "Stow preflight failed: $($script:Warnings -join '; ')"
}
if (-not $WhatIfPreference) { Write-DotfilesLog step 'Synchronizing portable Codex and Claude settings' }
foreach ($sync in $syncPlan) { Invoke-PortableSync @sync }

Write-DotfilesLog step "Stowing common packages: $($CommonPackages -join ' ')"
foreach ($package in $CommonPackages) {
    if (-not (Test-Path -LiteralPath (Join-Path $commonRoot $package))) {
        continue
    }
    Invoke-StowPackage -PackageRoot $commonRoot -PackageName $package `
        -GlobalIgnores $globalIgnores
}

if ($HostDir) {
    Write-DotfilesLog step "Stowing host packages ($HostDir): $($hostPackages -join ' ')"
    foreach ($package in $hostPackages) {
        Invoke-StowPackage -PackageRoot $hostRoot -PackageName $package `
            -GlobalIgnores $globalIgnores
    }
}

# Validate final destinations in one guarded process, including newly created
# links and host overrides. A trusted file link inside an untrusted directory
# still fails traversal; such an install must not advance applied state.
if (-not $WhatIfPreference -and $script:InstalledPaths.Count -gt 0) {
    $installedErrors = Get-DotfilesLinkReadErrors -Paths $script:InstalledPaths.ToArray()
    foreach ($path in $installedErrors.Keys) {
        if ($installedErrors[$path] -ne 0) {
            $script:Warnings.Add("installed symlink unreadable under RedirectionGuard: $path (Win32 $($installedErrors[$path]))")
        }
    }
}

# A OneDrive-redirected Documents folder would strip the profile links of any
# effect, so check the path PowerShell actually loads.
$profileRoot = Join-Path $Target 'Documents\PowerShell'
if ($recordAppliedState -and (Test-Path -LiteralPath $profileRoot) -and
    -not $PROFILE.CurrentUserAllHosts.StartsWith($profileRoot, [StringComparison]::OrdinalIgnoreCase)) {
    $script:Warnings.Add(
        "PowerShell loads $($PROFILE.CurrentUserAllHosts) but profiles were stowed " +
        "under $profileRoot (Documents may be redirected to OneDrive)")
}

# Every link inherits the trust of the token that created it, so a non-elevated
# run quietly produces links that work locally and nowhere else.
if (-not $script:IsElevated -and $script:Linked -gt 0) {
    $script:Warnings.Add(
        "$script:Linked symlink(s) created from a non-elevated session are " +
        'untrusted reparse points: an ssh session cannot traverse them. ' +
        'Re-run from an elevated PowerShell to replace them with trusted links')
}

# Preserve PowerShell's warning stream and -WarningAction behavior. The native
# warning renderer owns its appearance; status logging uses terminal.ps1.
foreach ($warning in $script:Warnings) { Write-Warning "[dotfiles] [warn] $warning" }

# Never acknowledge a partial or preview installation as an applied revision.
if ($Strict -and $script:Warnings.Count -gt 0) {
    throw 'Stow completed with warnings; automatic state was not advanced.'
}
if ($recordAppliedState -and -not $WhatIfPreference -and $script:Warnings.Count -eq 0) {
    . (Join-Path $RepoRoot 'scripts/dotfiles-auto-stow.ps1')
    Save-DotfilesStowState -Repo $RepoRoot -HostDir $HostDir -ExpectedHead $stowStartHead
}
$resultLevel = if ($WhatIfPreference -or $script:Warnings.Count) { 'info' } else { 'ok' }
$resultLabel = if ($WhatIfPreference) { 'Preview complete (no changes)' } else { 'Stow complete' }
Write-DotfilesLog $resultLevel "$resultLabel; linked: $script:Linked   repaired: $script:Repaired   unchanged/ignored: $script:Unchanged   backed up: $script:BackedUp"
