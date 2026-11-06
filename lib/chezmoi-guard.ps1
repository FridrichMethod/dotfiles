# Per-home native binding, maintenance and Windows binary-trust guard. Sourcing has no filesystem effects.
# PowerShell 5.1 compatible: both installed profile variants load this library.
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

function Test-DotfilesNativeOwned {
    param([Parameter(Mandatory)][string]$HomePath)
    return Test-DotfilesMarkerObject (Join-Path $HomePath '.config/dotfiles/native')
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

function Get-DotfilesNativeBinding {
    param([Parameter(Mandatory)][string]$HomePath)
    $destination = Resolve-DotfilesDirectory $HomePath
    if (-not [IO.Directory]::Exists($destination)) { throw 'Invalid native destination binding.' }
    $marker = Join-Path $destination '.config/dotfiles/native'
    $attributes = [IO.File]::GetAttributes($marker)
    if (($attributes -band [IO.FileAttributes]::ReparsePoint) -or ($attributes -band [IO.FileAttributes]::Directory)) {
        throw 'Native ownership marker must be a regular file.'
    }
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    $content = $utf8.GetString([IO.File]::ReadAllBytes($marker))
    if ($content -cnotmatch '\Adotfiles-chezmoi-v1\n([^\r\n]+)\n([^\r\n]+)\n\z') {
        throw 'Invalid native ownership binding.'
    }
    $boundHome = $Matches[1]
    $boundSource = $Matches[2]
    if (-not [IO.Path]::IsPathRooted($boundHome) -or -not [IO.Path]::IsPathRooted($boundSource)) {
        throw 'Native ownership paths must be absolute.'
    }
    $source = Resolve-DotfilesDirectory $boundSource
    if (-not $boundHome.Equals($destination, [StringComparison]::OrdinalIgnoreCase) -or
        -not $boundSource.Equals($source, [StringComparison]::OrdinalIgnoreCase) -or
        -not [IO.Directory]::Exists($source) -or
        -not (Test-DotfilesMarkerObject (Join-Path $source '.git')) -or
        -not [IO.File]::Exists((Join-Path $source '.chezmoiroot'))) {
        throw 'Native ownership binding must name this destination and a repository root.'
    }
    return [pscustomobject]@{
        Source = $source
        Destination = $destination
        Config = Join-Path $destination '.config/chezmoi/chezmoi.toml'
        Cache = Join-Path $destination '.cache/chezmoi'
        State = Join-Path $destination '.local/state/chezmoi/chezmoi.boltdb'
    }
}

# The native login updater's binary check (scripts/chezmoi-update.ps1), which
# doctor.ps1 and setup-host.ps1's W1-chezmoi apply too. Read-only and used on
# Windows only; like everything above, it parses under Windows PowerShell 5.1.
function Test-DotfilesNativeChezmoiPath {
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

function Open-DotfilesNativeChezmoi {
    # The provisioned <destination>\.local\bin\chezmoi.exe, open for reading
    # with FileShare.Read (nobody may write, rename or delete it while held),
    # or $null when it is missing, a link, under a linked directory, or not
    # private. The path is checked again after opening, and owner and DACL
    # are read from the held handle. No PATH lookup ever happens.
    param([Parameter(Mandatory)][string]$Destination)
    $path = Join-Path $Destination '.local\bin\chezmoi.exe'
    $stream = $null
    try {
        if (-not (Test-DotfilesNativeChezmoiPath $path)) { return $null }
        $stream = [IO.FileStream]::new($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        if ((Test-DotfilesNativeChezmoiPath $path) -and
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
