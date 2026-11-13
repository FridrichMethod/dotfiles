# Per-home chezmoi config lookup, maintenance and Windows binary-trust guard. Sourcing has no filesystem effects.
# Windows PowerShell 5.1 compatible. The PowerShell 7 profile, the login updater, scripts/commands/payloads-sync.ps1 (its rerun line), scripts/commands/doctor.ps1 and scripts/commands/setup.ps1 (through lib/bootstrap.ps1) load it.
function Test-DotfilesMarkerObject {
    param([Parameter(Mandatory)][string]$Path)
    try { [void][IO.File]::GetAttributes($Path); return $true }
    catch [IO.FileNotFoundException] { return $false }
    catch [IO.DirectoryNotFoundException] { return $false }
}

function Test-DotfilesMaintenance {
    param([Parameter(Mandatory)][string]$HomePath)
    return Test-DotfilesMarkerObject (Join-Path $HomePath '.config/dotfiles/maintenance')
}

function Test-DotfilesConfigExists {
    # HomePath's chezmoi config exists in any form, a dangling link included.
    param([Parameter(Mandatory)][string]$HomePath)
    return Test-DotfilesMarkerObject (Join-Path $HomePath '.config/chezmoi/chezmoi.toml')
}

function Resolve-DotfilesDirectory {
    param([Parameter(Mandatory)][string]$Path, [int]$Depth = 0)
    if ($Depth -gt 40) { throw 'Cannot resolve dotfiles directory ownership.' }
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    $current = $root
    foreach ($part in $full.Substring($root.Length).Split([char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries)) {
        $current = [IO.Path]::Combine($current, $part)
        if (-not (Test-DotfilesMarkerObject $current)) { continue }
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $target = @($item.Target) | Select-Object -First 1
            if (-not $target) { throw 'Cannot resolve dotfiles directory ownership.' }
            if ($target.StartsWith('\??\')) { $target = $target.Substring(4) }
            if (-not [IO.Path]::IsPathRooted($target)) {
                $target = Join-Path ([IO.Path]::GetDirectoryName($current)) $target
            }
            $current = Resolve-DotfilesDirectory -Path $target -Depth ($Depth + 1)
        }
    }
    return $current.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Get-DotfilesChezmoiPaths {
    # The source checkout and state paths HomePath's chezmoi config names, or a
    # throw. lib/chezmoi-guard.sh's dotfiles_chezmoi_source rules, plus two
    # that only this twin applies: strict UTF-8 for the whole file and a .git
    # in sourceDir. A regular file, not a link, whose lines before the first
    # table hold exactly one 'sourceDir = "VALUE"' and one 'destDir = "VALUE"'
    # line at column 0, LF line ends, and no quote, backslash or control
    # character in VALUE; any other spelling of either key, a workingTree key,
    # a line starting with a quote and a multi-line string before the first
    # table throw. Those spellings are matched ignoring case in every culture,
    # as the sh twin's spelled-out classes do (a current-culture match misses
    # SOURCEDIR under tr-TR, where I does not fold to i). On Windows a value
    # is 'C:/...' as chezmoi writes it, compared with backslashes and ignoring
    # case; elsewhere it starts with '/' and compares exactly. destDir is the
    # resolved home; sourceDir is a resolved directory holding .git and
    # .chezmoiroot. Reads text only and never runs chezmoi.
    param([Parameter(Mandatory)][string]$HomePath)
    $onWindows = ($PSVersionTable.PSEdition -ceq 'Desktop') -or ((Test-Path Variable:IsWindows) -and $IsWindows)
    $comparison = [StringComparison]::Ordinal
    $absolute = '\A/'
    if ($onWindows) {
        $comparison = [StringComparison]::OrdinalIgnoreCase
        $absolute = '\A[A-Za-z]:/'
    }
    $destination = Resolve-DotfilesDirectory $HomePath
    if (-not [IO.Directory]::Exists($destination)) { throw 'This home does not resolve to a directory.' }
    $config = Join-Path $destination '.config/chezmoi/chezmoi.toml'
    $attributes = [IO.File]::GetAttributes($config)
    if (($attributes -band [IO.FileAttributes]::ReparsePoint) -or ($attributes -band [IO.FileAttributes]::Directory)) {
        throw 'The chezmoi config must be a regular file.'
    }
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    $text = $utf8.GetString([IO.File]::ReadAllBytes($config))
    $layout = 'The chezmoi config needs exactly one top-level sourceDir and destDir line, each a double-quoted string without escapes.'
    $values = @{}
    foreach ($line in ($text -split "`n")) {
        $trimmed = $line.TrimStart([char[]]@(' ', "`t"))
        if ($trimmed.StartsWith('[', [StringComparison]::Ordinal)) { break }
        if ($trimmed.Contains('"""') -or $trimmed.Contains("'''") -or
            $trimmed.StartsWith('"', [StringComparison]::Ordinal) -or $trimmed.StartsWith("'", [StringComparison]::Ordinal)) {
            throw $layout
        }
        if ($line -cmatch '\A(sourceDir|destDir) = "([^"\\\x00-\x1F\x7F]+)"\z') {
            if ($values.ContainsKey($Matches[1])) { throw $layout }
            $values[$Matches[1]] = $Matches[2]
        }
        elseif ([regex]::IsMatch($trimmed, '\A(sourcedir|destdir|workingtree)[\s=]', [Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant')) { throw $layout }
    }
    if (-not $values.ContainsKey('sourceDir') -or -not $values.ContainsKey('destDir')) { throw $layout }
    $configuredSource = $values['sourceDir']
    $configuredDestination = $values['destDir']
    if ($configuredSource -cnotmatch $absolute -or $configuredDestination -cnotmatch $absolute) {
        throw 'sourceDir and destDir must be absolute.'
    }
    if ($onWindows) {
        $configuredSource = $configuredSource.Replace('/', '\')
        $configuredDestination = $configuredDestination.Replace('/', '\')
    }
    if (-not $configuredDestination.Equals($destination, $comparison)) { throw 'destDir must be this home.' }
    $source = Resolve-DotfilesDirectory $configuredSource
    if (-not $configuredSource.Equals($source, $comparison) -or
        -not [IO.Directory]::Exists($source) -or
        -not (Test-DotfilesMarkerObject (Join-Path $source '.git')) -or
        -not [IO.File]::Exists((Join-Path $source '.chezmoiroot'))) {
        throw 'sourceDir must be a canonical dotfiles checkout root.'
    }
    return [pscustomobject]@{
        Source = $source
        Destination = $destination
        Config = $config
        Cache = Join-Path $destination '.cache/chezmoi'
        State = Join-Path $destination '.local/state/chezmoi/chezmoi.boltdb'
    }
}

# The login updater's binary check (scripts/chezmoi-update.ps1), which
# scripts/commands/doctor.ps1 and scripts/commands/setup.ps1's W1-chezmoi apply too. Read-only and used on
# Windows only; like everything above, it parses under Windows PowerShell 5.1.
function Test-DotfilesChezmoiPath {
    # True when .local and .local\bin are real directories and chezmoi.exe a
    # regular file. GetAttributes reports a link itself, never its target.
    param([Parameter(Mandatory)][string]$Path)
    $bin = Split-Path -Parent $Path
    foreach ($item in @((Split-Path -Parent $bin), $bin, $Path)) {
        $attributes = [IO.File]::GetAttributes($item)
        $isDirectory = [bool]($attributes -band [IO.FileAttributes]::Directory)
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -or $isDirectory -ne ($item -ne $Path)) { return $false }
    }
    return $true
}

function Test-DotfilesTrustedFileSecurity {
    # Owner is this user, SYSTEM or Administrators, and no allow entry gives
    # any other SID WRITE_DATA, APPEND, WRITE_EA, WRITE_ATTRIBUTES, DELETE,
    # WRITE_DAC, WRITE_OWNER, GENERIC_ALL or GENERIC_WRITE (0x500D0116).
    # OWNER RIGHTS (S-1-3-4) applies only to that already trusted owner.
    # Read from the raw descriptor, not .NET's rule projection, which skips
    # every entry that is not a common ACE: a null DACL, or any DACL entry
    # but a plain or callback allow or deny entry (an object, compound or
    # unknown type), refuses. Deny entries only take rights away.
    param([Parameter(Mandatory)][Security.AccessControl.FileSystemSecurity]$Security)
    $descriptor = [Security.AccessControl.RawSecurityDescriptor]::new($Security.GetSecurityDescriptorBinaryForm(), 0)
    $trusted = @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value, 'S-1-5-18', 'S-1-5-32-544')
    if ($null -eq $descriptor.Owner -or $trusted -notcontains $descriptor.Owner.Value) { return $false }
    if ($null -eq $descriptor.DiscretionaryAcl) { return $false }
    $trusted += 'S-1-3-4'
    foreach ($ace in $descriptor.DiscretionaryAcl) {
        if ($ace -isnot [Security.AccessControl.CommonAce]) { return $false }
        if ($ace.AceQualifier -eq [Security.AccessControl.AceQualifier]::AccessDenied) { continue }
        if ($ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed) { return $false }
        if ($trusted -notcontains $ace.SecurityIdentifier.Value -and ($ace.AccessMask -band 0x500D0116)) { return $false }
    }
    return $true
}

function Open-DotfilesChezmoi {
    # The provisioned <destination>\.local\bin\chezmoi.exe, open for reading
    # with FileShare.Read (nobody may write, rename or delete it while held),
    # or $null when it is missing, a link, under a linked directory, or not
    # private. The path is checked again after opening, and owner and DACL
    # are read from the held handle. No PATH lookup ever happens.
    param([Parameter(Mandatory)][string]$Destination)
    $path = Join-Path $Destination '.local\bin\chezmoi.exe'
    $stream = $null
    try {
        if (-not (Test-DotfilesChezmoiPath $path)) { return $null }
        $stream = [IO.FileStream]::new($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        if ((Test-DotfilesChezmoiPath $path) -and
            (Test-DotfilesTrustedFileSecurity ([IO.FileSystemAclExtensions]::GetAccessControl($stream)))) {
            $held = $stream
            $stream = $null
            return $held
        }
        return $null
    }
    catch { return $null }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
}
