#Requires -Version 7.0
# Day-zero helpers for doctor.ps1 and setup-host.ps1, the thin Windows twins of
# doctor.sh and setup-host.sh. Dot-source only: this file defines functions and
# changes no preference, location, variable or environment of its caller.
# It reads the same config/bootstrap manifests as lib/bootstrap/*.sh with the
# same rules. tests/test_bootstrap_manifest.py validates them; these readers
# still fail closed with IO.InvalidDataException on a malformed row, which the
# entry points report as exit 2.
# Commands are found by probing PATH entries, never with Get-Command, which
# takes about 0.45 s per missing name on Windows (see the PowerShell profile).

function Get-BootstrapTierNames {
    # The tier vocabulary, in the order Brewfiles and reports use.
    return @('core', 'cli', 'ai', 'desktop', 'contributor', 'host')
}

function Test-BootstrapTierSelection {
    # True when Selection is "all" or a comma list of known tiers.
    param([AllowEmptyString()][string]$Selection)
    if ($Selection -ceq 'all') { return $true }
    if (-not $Selection) { return $false }
    foreach ($tier in $Selection.Split(',')) {
        if ($tier -cnotin (Get-BootstrapTierNames)) { return $false }
    }
    return $true
}

function Test-BootstrapTierSelected {
    # bootstrap_tier_selected: Selection is "all" or a comma list.
    param([Parameter(Mandatory)][string]$Tier, [Parameter(Mandatory)][string]$Selection)
    if ($Selection -ceq 'all') { return $true }
    return $Selection.Split(',') -ccontains $Tier
}

function Get-BootstrapManifestRows {
    # TSV rows as objects whose properties are the header's column names.
    # Lines starting with # (anywhere, including the trailing alias/manual
    # declarations) and blank lines are skipped; the first other line is the
    # header. Every row must have the header's width and no empty cell.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [string[]]$Header)
    if (-not [IO.File]::Exists($Path)) {
        throw [IO.InvalidDataException]::new("Manifest not found: $Path")
    }
    $columns = $null
    $number = 0
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $number++
        if ($line.StartsWith('#') -or $line.Trim().Length -eq 0) { continue }
        $cells = $line.Split("`t")
        if ($null -eq $columns) {
            if ($Header -and (($cells -join "`t") -cne ($Header -join "`t"))) {
                throw [IO.InvalidDataException]::new("${Path}:${number}: header is not '$($Header -join ' ')'")
            }
            $columns = $cells
            continue
        }
        if ($cells.Count -ne $columns.Count) {
            throw [IO.InvalidDataException]::new(
                "${Path}:${number}: expected $($columns.Count) tab-separated fields, found $($cells.Count)")
        }
        $row = [ordered]@{}
        for ($index = 0; $index -lt $cells.Count; $index++) {
            if ($cells[$index].Length -eq 0) {
                throw [IO.InvalidDataException]::new("${Path}:${number}: empty $($columns[$index]) cell; use -")
            }
            $row[$columns[$index]] = $cells[$index]
        }
        [pscustomobject]$row
    }
    if ($null -eq $columns) { throw [IO.InvalidDataException]::new("${Path}: no header row") }
}

function Get-BootstrapBatConfigDirectory {
    # bat honours BAT_CONFIG_DIR first; its Windows default is %APPDATA%\bat.
    if ($env:BAT_CONFIG_DIR) { return $env:BAT_CONFIG_DIR }
    if ($env:APPDATA) { return Join-Path $env:APPDATA 'bat' }
    if (-not $IsWindows -and $HOME) {
        $configHome = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME '.config' }
        return Join-Path $configHome 'bat'
    }
    return ''
}

function Expand-BootstrapPath {
    # bootstrap_expand_path: expand one leading token ($HOME $ZSH_CUSTOM
    # $NVM_DIR $XDG_CONFIG_HOME $XDG_DATA_HOME $BAT_CONFIG_DIR), alone or
    # followed by "/". Any other "$", a leading "~" or a ".." segment is
    # invalid manifest data; an unresolvable base (no APPDATA) is too.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not $HOME) { throw [IO.InvalidDataException]::new("HOME is empty; cannot expand '$Path'") }
    $token = ''
    $rest = $Path
    if ($Path -cmatch '^\$([A-Za-z_][A-Za-z0-9_]*)(?=/|$)') {
        $token = $Matches[1]
        $rest = $Path.Substring($token.Length + 1)
    }
    $zshRoot = if ($env:ZSH) { $env:ZSH } else { Join-Path $HOME '.oh-my-zsh' }
    $base = switch -CaseSensitive ($token) {
        '' { '' }
        'HOME' { $HOME }
        'ZSH_CUSTOM' { if ($env:ZSH_CUSTOM) { $env:ZSH_CUSTOM } else { Join-Path $zshRoot 'custom' } }
        'NVM_DIR' { if ($env:NVM_DIR) { $env:NVM_DIR } else { Join-Path $HOME '.nvm' } }
        'XDG_CONFIG_HOME' { if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME '.config' } }
        'XDG_DATA_HOME' { if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path $HOME '.local/share' } }
        'BAT_CONFIG_DIR' { Get-BootstrapBatConfigDirectory }
        default { throw [IO.InvalidDataException]::new("Unsupported path token `$$token in '$Path'") }
    }
    if ($rest.Contains('$') -or $rest.StartsWith('~') -or $rest -match '(^|[\\/])\.\.([\\/]|$)') {
        throw [IO.InvalidDataException]::new("Unsupported manifest path '$Path'")
    }
    if ($token -and -not $base) {
        throw [IO.InvalidDataException]::new("Cannot resolve `$$token for '$Path'")
    }
    $expanded = [string]$base + $rest
    if ($IsWindows) { $expanded = $expanded.Replace('/', '\') }
    return $expanded
}

function Test-BootstrapHostMatch {
    # bootstrap_host_matches: "all"; "unix" for every host but win; or a
    # comma list naming HostName. An empty HostName matches only all/unix.
    param([Parameter(Mandatory)][string]$Hosts, [AllowEmptyString()][string]$HostName = '')
    if ($Hosts -ceq 'all') { return $true }
    if ($Hosts -ceq 'unix') { return $HostName -cne 'win' }
    if (-not $HostName) { return $false }
    return $Hosts.Split(',') -ccontains $HostName
}

function Find-BootstrapCommand {
    # The first PATH entry holding Name.exe, .cmd, .bat or .ps1 (in that
    # order within an entry), or $null. With -All, every such file in PATH
    # order, one per entry. Off Windows an extensionless file also counts,
    # so Unix pwsh runs of the twins and their tests work.
    param([Parameter(Mandatory)][string]$Name, [switch]$All)
    $extensions = @('.exe', '.cmd', '.bat', '.ps1')
    if (-not $IsWindows) { $extensions += '' }
    $found = [Collections.Generic.List[string]]::new()
    foreach ($entry in ([string]$env:PATH).Split([IO.Path]::PathSeparator)) {
        $directory = $entry.Trim().Trim('"')
        if (-not $directory) { continue }
        foreach ($extension in $extensions) {
            $candidate = [IO.Path]::Combine($directory, $Name + $extension)
            if (-not [IO.File]::Exists($candidate)) { continue }
            if (-not $All) { return $candidate }
            if (-not ($found -contains $candidate)) { $found.Add($candidate) }
            break
        }
    }
    if ($All) { return $found.ToArray() }
    return $null
}

function Test-BootstrapStoreAlias {
    # True for a file directly in %LOCALAPPDATA%\Microsoft\WindowsApps, where
    # the Microsoft Store keeps its app execution aliases. Without the Store
    # app, python.exe and python3.exe there print only an install hint.
    param([Parameter(Mandatory)][string]$Path)
    if (-not $env:LOCALAPPDATA) { return $false }
    $aliases = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Microsoft/WindowsApps')).TrimEnd('\', '/')
    $directory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
    return [string]$directory.TrimEnd('\', '/') -eq $aliases
}

function ConvertFrom-BootstrapVersionText {
    # bootstrap_extract_version: the first X.Y or X.Y.Z in Text, or ''.
    param([AllowEmptyString()][AllowNull()][string]$Text)
    $match = [regex]::Match([string]$Text, '[0-9]+\.[0-9]+(\.[0-9]+)?')
    if ($match.Success) { return $match.Value }
    return ''
}

function Use-BootstrapToolEnvironment {
    # Run Action with GH_TELEMETRY=0 and GH_NO_UPDATE_NOTIFIER=1, which
    # doctor.sh and setup-host.sh export: recent gh releases write a telemetry
    # device id on any command, --version included, and the notifier checks
    # GitHub for a release. The process environment outlives this script in
    # an interactive session, so the caller's values are restored.
    param([Parameter(Mandatory)][scriptblock]$Action)
    $saved = @{}
    foreach ($name in @('GH_TELEMETRY', 'GH_NO_UPDATE_NOTIFIER')) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name)
    }
    try {
        $env:GH_TELEMETRY = '0'
        $env:GH_NO_UPDATE_NOTIFIER = '1'
        & $Action
    }
    finally {
        foreach ($name in $saved.Keys) {
            # PowerShell passes $null to a string parameter as '', which sets
            # an empty variable off Windows instead of removing it.
            if ($null -eq $saved[$name]) { Remove-Item -LiteralPath "Env:$name" -ErrorAction Ignore }
            else { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
        }
    }
}

function Get-BootstrapToolVersion {
    # bootstrap_tool_version: run Path with Flag (stdin closed, stderr merged),
    # keep the first five lines and extract a version; '' for Flag "-", a tool
    # that prints none, or one that fails to start.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Flag)
    if ($Flag -ceq '-') { return '' }
    # Function-local preferences: a caller's Stop must not turn a tool's
    # stderr or exit status into an exception here.
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $lines = @(Use-BootstrapToolEnvironment {
                $null | & $Path $Flag 2>&1 | Select-Object -First 5 | ForEach-Object { "$_" }
            })
    }
    catch { return '' }
    return ConvertFrom-BootstrapVersionText ($lines -join "`n")
}

function Get-BootstrapVersionParts {
    # bootstrap_version_parts: three integers, or $null unless Version is 1-3
    # dot-separated digit groups (one leading v allowed).
    param([AllowEmptyString()][AllowNull()][string]$Version)
    $text = [string]$Version
    if ($text.StartsWith('v')) { $text = $text.Substring(1) }
    if ($text -cnotmatch '^[0-9]+(\.[0-9]+){0,2}$') { return $null }
    $parts = [Collections.Generic.List[decimal]]::new()
    foreach ($group in $text.Split('.')) { $parts.Add([decimal]::Parse($group, [Globalization.CultureInfo]::InvariantCulture)) }
    while ($parts.Count -lt 3) { $parts.Add(0) }
    return , $parts.ToArray()
}

function Compare-BootstrapVersion {
    # bootstrap_version_ge: 0 when Have >= Floor, 1 when lower, 2 when either
    # side is not a version.
    param([AllowEmptyString()][AllowNull()][string]$Have, [AllowEmptyString()][AllowNull()][string]$Floor)
    $haveParts = Get-BootstrapVersionParts $Have
    $floorParts = Get-BootstrapVersionParts $Floor
    if ($null -eq $haveParts -or $null -eq $floorParts) { return 2 }
    for ($index = 0; $index -lt 3; $index++) {
        if ($haveParts[$index] -gt $floorParts[$index]) { return 0 }
        if ($haveParts[$index] -lt $floorParts[$index]) { return 1 }
    }
    return 0
}

function Get-BootstrapDocRef {
    # bootstrap_doc_ref: the docs/bootstrap.md step a profile's reader follows.
    param([Parameter(Mandatory)][string]$Step, [string]$ProfileName = 'windows')
    switch -CaseSensitive ("${ProfileName}:$Step") {
        { $_ -cin @('hpc:S2-brew-bundle', 'hpc:H1-apt-core') } { return 'S2-login-env' }
        'hpc:H1-locale' { return 'P0-preflight' }
        { $_ -cin @('hpc:S4-nvm', 'hpc:S5-claude', 'hpc:S5-codex') } { return 'S2-modules' }
        'macos:H1-apt-core' { return 'S2-brew-bundle' }
        { $_ -cin @('other:H1-apt-core', 'other:H1-locale', 'other:H1-homebrew', 'other:H1-linuxbrew',
                'other:S2-brew-bundle', 'other:S4-nvm', 'other:S5-claude', 'other:S5-codex') } { return 'X-other-linux' }
        'windows:P0-preflight' { return 'HW-clone' }
        { $_ -cin @('windows:S2-brew-bundle', 'windows:S4-nvm', 'windows:S5-claude', 'windows:S5-codex') } {
            return 'W1-winget'
        }
        'windows:S3-bat-theme' { return 'W1-bat-theme' }
        'windows:S6-nerd-font' { return 'W1-font' }
        'windows:S4-setup-sync' { return 'W1-setup-sync' }
        'windows:H7-stow' { return 'HW-stow' }
        'windows:H7-auth' { return 'HW-auth' }
    }
    return $Step
}

function Get-BootstrapProbe {
    # Split a tools.tsv probe into Kind (command, file, dir, font, env,
    # psmodule) and Value. Anything else is invalid manifest data.
    param([Parameter(Mandatory)][string]$Probe)
    if ($Probe -cmatch '^(file|dir|font|env|psmodule):(.+)$') {
        return [pscustomobject]@{ Kind = $Matches[1]; Value = $Matches[2] }
    }
    if ($Probe -cmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*(,[A-Za-z0-9][A-Za-z0-9._+-]*)*$') {
        return [pscustomobject]@{ Kind = 'command'; Value = $Probe }
    }
    throw [IO.InvalidDataException]::new("Unsupported probe '$Probe'")
}

function Find-BootstrapFontFile {
    # A font file whose name contains Family without spaces, in the system or
    # per-user Windows font directory (oh-my-posh installs per user unless
    # elevated), or $null.
    param([Parameter(Mandatory)][string]$Family)
    $needle = $Family.Replace(' ', '')
    $directories = @()
    if ($env:WINDIR) { $directories += Join-Path $env:WINDIR 'Fonts' }
    if ($env:LOCALAPPDATA) { $directories += Join-Path $env:LOCALAPPDATA 'Microsoft/Windows/Fonts' }
    foreach ($directory in $directories) {
        if (-not [IO.Directory]::Exists($directory)) { continue }
        foreach ($file in [IO.Directory]::EnumerateFiles($directory)) {
            if ([IO.Path]::GetFileName($file).IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return $file
            }
        }
    }
    return $null
}

function Find-BootstrapModuleDirectory {
    # The first PSModulePath entry holding a directory named Name, or $null
    # (the profile's PSFzf check; Get-Module -ListAvailable is far slower).
    param([Parameter(Mandatory)][string]$Name)
    foreach ($entry in ([string]$env:PSModulePath).Split([IO.Path]::PathSeparator)) {
        if (-not $entry) { continue }
        $candidate = [IO.Path]::Combine($entry, $Name)
        if ([IO.Directory]::Exists($candidate)) { return $candidate }
    }
    return $null
}

function Test-BootstrapTool {
    # Probe one tools.tsv row: Found, Path and (with a VersionFlag) Version.
    # For comma alternatives the first found wins, except that a candidate
    # printing no version yields to a later one that does. A Microsoft Store
    # alias that prints no version is an install hint, not the tool: the
    # search goes on along PATH, and a row with only such stubs is missing.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Probe, [string]$VersionFlag = '-')
    $parsed = Get-BootstrapProbe $Probe
    $path = $null
    $fallback = $null
    $version = ''
    switch -CaseSensitive ($parsed.Kind) {
        'file' {
            # An executable file (doctor.sh's file: probes) may name a version flag.
            $candidate = Expand-BootstrapPath $parsed.Value
            if ([IO.File]::Exists($candidate)) {
                $path = $candidate
                if ($VersionFlag -cne '-') { $version = Get-BootstrapToolVersion -Path $candidate -Flag $VersionFlag }
            }
        }
        'dir' {
            $candidate = Expand-BootstrapPath $parsed.Value
            if ([IO.Directory]::Exists($candidate)) { $path = $candidate }
        }
        'font' { $path = Find-BootstrapFontFile $parsed.Value }
        'env' {
            if ([Environment]::GetEnvironmentVariable($parsed.Value)) { $path = "env:$($parsed.Value)" }
        }
        'psmodule' { $path = Find-BootstrapModuleDirectory $parsed.Value }
        'command' {
            foreach ($name in $parsed.Value.Split(',')) {
                $candidates = @(Find-BootstrapCommand $name -All)
                if (-not $candidates.Count) { continue }
                if ($VersionFlag -ceq '-') { $path = $candidates[0]; break }
                foreach ($candidate in $candidates) {
                    $version = Get-BootstrapToolVersion -Path $candidate -Flag $VersionFlag
                    if ($version) { $path = $candidate; break }
                    if (Test-BootstrapStoreAlias $candidate) { continue }
                    if (-not $fallback) { $fallback = $candidate }
                    break
                }
                if ($version) { break }
            }
            if (-not $path) { $path = $fallback }
        }
    }
    return [pscustomobject]@{ Found = [bool]$path; Path = [string]$path; Version = $version }
}

function Select-BootstrapCommand {
    # The first PATH candidate, over the comma alternatives of a command
    # Probe in order, whose VersionFlag output carries a version >= Floor:
    # Path and Version, or empty ones. Rejected lists every candidate passed
    # over, with its version or "no version" (a Store alias stub).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Probe, [Parameter(Mandatory)][string]$VersionFlag,
        [Parameter(Mandatory)][string]$Floor)
    $parsed = Get-BootstrapProbe $Probe
    if ($parsed.Kind -cne 'command') { throw [IO.InvalidDataException]::new("Not a command probe: '$Probe'") }
    $rejected = [Collections.Generic.List[string]]::new()
    foreach ($name in $parsed.Value.Split(',')) {
        foreach ($candidate in @(Find-BootstrapCommand $name -All)) {
            $version = Get-BootstrapToolVersion -Path $candidate -Flag $VersionFlag
            if ($version -and (Compare-BootstrapVersion $version $Floor) -eq 0) {
                return [pscustomobject]@{ Path = $candidate; Version = $version; Rejected = $rejected.ToArray() }
            }
            $shown = if ($version) { $version } else { 'no version' }
            $rejected.Add("$candidate ($shown)")
        }
    }
    return [pscustomobject]@{ Path = ''; Version = ''; Rejected = $rejected.ToArray() }
}

function New-BootstrapResult {
    # Action outcome: Status is installed, present, skipped or failed.
    param([Parameter(Mandatory)][ValidateSet('installed', 'present', 'skipped', 'failed')][string]$Status,
        [AllowEmptyString()][string]$Message = '', $ExitCode = $null)
    return [pscustomobject]@{
        Status = $Status; Success = $Status -cne 'failed'; Message = $Message; ExitCode = $ExitCode
    }
}

function Get-BootstrapWingetOutcome {
    # Classify a winget exit code. Already installed and no applicable update
    # are success; agreements not accepted, no package found and every other
    # non-zero code fail, reported as the HRESULT in hex.
    param([Parameter(Mandatory)][int]$ExitCode)
    $hex = '0x{0:X8}' -f $ExitCode
    $known = @{
        [int]0x8A150061 = @('present', 'package already installed')
        [int]0x8A15002B = @('present', 'no applicable update found')
        [int]0x8A150046 = @('failed', 'source agreements were not accepted')
        [int]0x8A150041 = @('failed', 'package agreements were not accepted')
        [int]0x8A150014 = @('failed', 'no package found')
    }
    if ($ExitCode -eq 0) { return New-BootstrapResult installed "winget exited $hex" $ExitCode }
    if ($known.ContainsKey($ExitCode)) {
        $status, $label = $known[$ExitCode]
        return New-BootstrapResult $status "winget exited $hex ($label)" $ExitCode
    }
    return New-BootstrapResult failed "winget exited $hex" $ExitCode
}

function Invoke-BootstrapWingetCommand {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $PSNativeCommandUseErrorActionPreference = $false
    $winget = Find-BootstrapCommand 'winget'
    if (-not $winget) {
        return New-BootstrapResult failed 'winget is not on PATH; install or update App Installer from the Microsoft Store'
    }
    # Host output keeps winget's own lines visible without returning them.
    & $winget @Arguments | Out-Host
    return Get-BootstrapWingetOutcome ([int]$LASTEXITCODE)
}

function Invoke-BootstrapWinget {
    # Install one package by exact winget id without upgrading an existing one.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    return Invoke-BootstrapWingetCommand @('install', '--id', $Id, '-e', '--source', 'winget',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity', '--no-upgrade')
}

function Invoke-BootstrapWingetImport {
    # Import config/bootstrap/winget.json; installed packages are left alone.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    return Invoke-BootstrapWingetCommand @('import', '-i', $Path, '--no-upgrade', '--ignore-unavailable',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
}

function Invoke-BootstrapPSResource {
    # Install a module for the current user only when PSResourceGet has none.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    try {
        $installed = @(Get-InstalledPSResource -Name $Name -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
    }
    catch [Management.Automation.CommandNotFoundException] {
        return New-BootstrapResult failed 'PSResourceGet is unavailable; use PowerShell 7.4 or newer'
    }
    if ($installed.Count) { return New-BootstrapResult present "$Name is already installed" }
    try {
        Install-PSResource -Name $Name -Scope CurrentUser -TrustRepository -AcceptLicense -ErrorAction Stop
    }
    catch { return New-BootstrapResult failed "Install-PSResource $Name failed: $($_.Exception.Message)" }
    return New-BootstrapResult installed "$Name installed for the current user"
}

function Install-BootstrapFont {
    # Install the Nerd Font through oh-my-posh, and only when oh-my-posh is on
    # PATH: no other installer is attempted.
    [CmdletBinding()]
    param([string]$Family = 'CaskaydiaMono Nerd Font', [string]$Font = 'CascadiaMono')
    $PSNativeCommandUseErrorActionPreference = $false
    if (Find-BootstrapFontFile $Family) { return New-BootstrapResult present "$Family is installed" }
    $ohMyPosh = Find-BootstrapCommand 'oh-my-posh'
    if (-not $ohMyPosh) { return New-BootstrapResult skipped 'oh-my-posh is not on PATH (W1-winget installs it)' }
    & $ohMyPosh font install $Font | Out-Host
    $code = [int]$LASTEXITCODE
    if ($code -ne 0) { return New-BootstrapResult failed "oh-my-posh font install $Font exited $code" $code }
    return New-BootstrapResult installed "oh-my-posh installed $Font" 0
}

function Install-BootstrapFile {
    # Download an https URL to a fresh scratch directory, check its SHA256
    # against the pin and only then move it to Destination (never replaced).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][string]$Sha256,
        [Parameter(Mandatory)][string]$Destination)
    if ($Uri -cnotmatch '^https://') { throw [IO.InvalidDataException]::new("Refusing a non-https download: $Uri") }
    if ($Sha256 -cnotmatch '^[0-9a-f]{64}$') { throw [IO.InvalidDataException]::new("Invalid sha256 pin for $Uri") }
    $ProgressPreference = 'SilentlyContinue'
    $scratch = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-bootstrap-' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($scratch)
    try {
        $part = Join-Path $scratch 'download.part'
        Invoke-WebRequest -Uri $Uri -OutFile $part -MaximumRetryCount 3 -RetryIntervalSec 2 -ErrorAction Stop
        $actual = (Get-FileHash -LiteralPath $part -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        if ($actual -cne $Sha256) {
            return New-BootstrapResult failed "sha256 mismatch for ${Uri}: expected $Sha256, got $actual"
        }
        if ([IO.File]::Exists($Destination)) { return New-BootstrapResult failed "$Destination already exists" }
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Destination))
        [IO.File]::Move($part, $Destination)
        return New-BootstrapResult installed "verified sha256 $Sha256"
    }
    catch { return New-BootstrapResult failed "download of $Uri failed: $($_.Exception.Message)" }
    finally { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

function Get-BootstrapVenvPython {
    # The interpreter setup-sync creates in RepoRoot/.venv-sync: bin/python
    # when it exists, else Scripts\python.exe, the order lib/sync-runtime.sh
    # uses.
    param([Parameter(Mandatory)][string]$RepoRoot)
    $unix = Join-Path $RepoRoot '.venv-sync/bin/python'
    if ([IO.File]::Exists($unix)) { return $unix }
    return Join-Path $RepoRoot '.venv-sync/Scripts/python.exe'
}

function Get-BootstrapSyncPython {
    # The interpreter the AI config sync helpers run (lib/sync-runtime.sh):
    # DOTFILES_SYNC_PYTHON whenever it is set, else the .venv-sync one.
    param([Parameter(Mandatory)][string]$RepoRoot)
    $override = [Environment]::GetEnvironmentVariable('DOTFILES_SYNC_PYTHON')
    if ($null -ne $override) { return [pscustomobject]@{ Path = $override; Source = 'DOTFILES_SYNC_PYTHON' } }
    return [pscustomobject]@{ Path = (Get-BootstrapVenvPython $RepoRoot); Source = '.venv-sync' }
}

function Test-BootstrapSyncRuntime {
    # True when Python passes lib/config_sync.py --runtime-check (Python
    # 3.11+ and the pinned tomlkit), the check setup-sync itself ends with.
    # Read-only: -B writes no bytecode, and its output is discarded.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Python, [Parameter(Mandatory)][string]$RepoRoot)
    if (-not $Python -or -not [IO.File]::Exists($Python)) { return $false }
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    try { $null | & $Python -I -B -X utf8 (Join-Path $RepoRoot 'lib/config_sync.py') --runtime-check *> $null }
    catch { return $false }
    return $LASTEXITCODE -eq 0
}

function Split-BootstrapPathList {
    # Non-empty, environment-expanded entries of a ;-separated PATH value.
    param([AllowEmptyString()][AllowNull()][string]$Value)
    foreach ($entry in ([string]$Value).Split(';')) {
        $expanded = [Environment]::ExpandEnvironmentVariables($entry.Trim())
        if ($expanded) { $expanded }
    }
}

function Merge-BootstrapPath {
    # A Windows PATH value: the entries only this process has (an activated
    # venv, a caller's own prepend) first and in their order, then Machine
    # and User entries in the order a new terminal reads them. A process
    # PATH keeps the order it had at launch, so an installer's User-scope
    # PrependPath entry (winget's Python) would otherwise land after the
    # WindowsApps Store aliases already in it. Entries are deduplicated
    # case-insensitively, ignoring a trailing separator.
    param([AllowEmptyString()][AllowNull()][string]$Process, [AllowEmptyString()][AllowNull()][string]$Machine,
        [AllowEmptyString()][AllowNull()][string]$User)
    $registry = @(Split-BootstrapPathList $Machine) + @(Split-BootstrapPathList $User)
    $known = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $registry) { [void]$known.Add($entry.TrimEnd('\', '/')) }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $merged = [Collections.Generic.List[string]]::new()
    foreach ($entry in @(Split-BootstrapPathList $Process)) {
        $key = $entry.TrimEnd('\', '/')
        if (-not $known.Contains($key) -and $seen.Add($key)) { $merged.Add($entry) }
    }
    foreach ($entry in $registry) {
        if ($seen.Add($entry.TrimEnd('\', '/'))) { $merged.Add($entry) }
    }
    return $merged -join ';'
}

function Update-BootstrapSessionPath {
    # Windows only: rebuild this process's PATH with Merge-BootstrapPath, so
    # entries installers just registered resolve as in a new terminal.
    if (-not $IsWindows) { return }
    $env:PATH = Merge-BootstrapPath -Process $env:PATH -Machine ([Environment]::GetEnvironmentVariable('Path', 'Machine')) `
        -User ([Environment]::GetEnvironmentVariable('Path', 'User'))
}

function Write-BootstrapHumanBlock {
    # Emit one HUMAN block on the success stream (stdout), the grammar the
    # Unix installer prints: HUMAN-BEGIN <step-id> <kind>, lines, HUMAN-END.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Step, [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string[]]$Line)
    if ($Step -cnotmatch '^[A-Za-z0-9-]+$') { throw "Invalid HUMAN step id '$Step'" }
    if ($Kind -cnotin @('sudo', 'auth', 'gui', 'alloc', 'chsh', 'inspect', 'judgment')) {
        throw "Invalid HUMAN kind '$Kind'"
    }
    foreach ($text in $Line) {
        if ($text -match '[\r\n]' -or $text.StartsWith('HUMAN-')) { throw "Invalid HUMAN line in ${Step}: '$text'" }
    }
    "HUMAN-BEGIN $Step $Kind"
    $Line
    'HUMAN-END'
}
