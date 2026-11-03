# Temporary per-home writer handover guard. Sourcing has no filesystem effects.
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

function Test-DotfilesLegacyWriteAllowed {
    param([Parameter(Mandatory)][string]$TargetPath)
    try {
        $lexical = [IO.Path]::GetFullPath($TargetPath)
        # Resolve parents, never the final target: it may be an owned Stow link.
        $parent = [IO.Path]::GetDirectoryName($lexical.TrimEnd('\', '/'))
        $resolved = if ($parent) { Resolve-DotfilesDirectory $parent } else { $lexical }
        foreach ($start in @($lexical, $resolved)) {
            for ($ancestor = $start; $ancestor; $ancestor = [IO.Path]::GetDirectoryName($ancestor)) {
                if ((Test-DotfilesNativeOwned $ancestor) -or (Test-DotfilesMaintenance $ancestor)) {
                    [Console]::Error.WriteLine('[dotfiles] Legacy writes are disabled for this destination (native ownership or maintenance).')
                    return $false
                }
            }
        }
        return $true
    }
    catch {
        [Console]::Error.WriteLine('[dotfiles] Legacy writes are disabled: destination ownership could not be checked.')
        return $false
    }
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
