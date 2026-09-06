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
    point: Windows refuses to traverse one for a file open whose token is a
    network logon - which is what OpenSSH public-key auth produces - so every
    stowed dotfile fails inside an ssh session with "the path cannot be
    traversed because it contains an untrusted mount point" while resolving
    fine locally. An elevated run creates trusted links and repairs untrusted
    ones it finds.

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

# Only a token holding SeCreateSymbolicLinkPrivilege creates trusted symlinks,
# so both the repair path and the closing warning need to know how we run.
$script:Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$script:IsElevated = ([Security.Principal.WindowsPrincipal]$script:Identity).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

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

    if ($CheckOnly -or $PSCmdlet.ShouldProcess($Live, "Synchronize portable $Label")) {
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

function Test-FileOpens {
    <#
    .SYNOPSIS
        True when a file can actually be opened for reading.
    .DESCRIPTION
        ReadWrite sharing keeps a file another process holds open - a profile
        being sourced, a config being watched - from reading as a failure.
    #>
    param([Parameter(Mandatory)][string]$Path)

    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $stream.Dispose()
        return $true
    }
    catch {
        return $false
    }
}

function Test-UntrustedLink {
    <#
    .SYNOPSIS
        True when a symlink resolves on paper but cannot be traversed.
    .DESCRIPTION
        Get-Item, Test-Path and fsutil all report an untrusted reparse point as
        a healthy link: tag, flags and substitute name are byte-identical to a
        trusted one. Only an open that traverses the link fails, so opening it
        is the sole reliable probe. A target that will not open either means a
        lock or a missing file rather than link trust, and rewriting the link
        would not help, so that case is not reported as untrusted.
    #>
    param(
        [Parameter(Mandatory)][string]$Link,
        [Parameter(Mandatory)][string]$Target
    )

    if (Test-FileOpens -Path $Link) { return $false }
    return (Test-FileOpens -Path $Target)
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
                    if (-not (Test-UntrustedLink -Link $destination `
                                -Target $item.FullName)) {
                        Write-Verbose "ok        $relativeUnix"
                        $script:Unchanged++
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
                    if ($PSCmdlet.ShouldProcess(
                            $destination, 'Repair untrusted symlink')) {
                        New-Item -ItemType SymbolicLink -Path $destination `
                            -Value $item.FullName -Force | Out-Null
                        Write-Verbose "repair    $relativeUnix"
                        $script:Repaired++
                    }
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
                $backup = '{0}.stow-backup-{1}-{2}' -f $destination,
                    (Get-Date -Format 'yyyyMMddHHmmss'), [Guid]::NewGuid().ToString('N')
                if ($PSCmdlet.ShouldProcess($destination, "Back up to $backup")) {
                    Move-Item -LiteralPath $destination -Destination $backup
                    Write-DotfilesLog info "Backed up $relativeUnix -> $(Split-Path -Leaf $backup)"
                    $script:BackedUp++
                }
            }
        }

        if ($PSCmdlet.ShouldProcess($destination, "Link to $($item.FullName)")) {
            New-Item -ItemType SymbolicLink -Path $destination `
                -Value $item.FullName -Force | Out-Null
            Write-Verbose "link      $relativeUnix"
            $script:Linked++
        }
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
    }
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
