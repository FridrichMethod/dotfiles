#Requires -Version 7.0
# HOME and TEMP snapshots of tests/e2e/run.ps1, for the steps that must write
# nothing (doctor.ps1, setup-host.ps1 -Check, the second -Yes). A snapshot
# holds every file under HOME with its size and modification time, read from
# the file's own record (Refresh(): NTFS fills a directory listing from the
# parent's index, which it updates lazily), every directory by name only (its
# time moves when a child changes, so it adds nothing), and every reparse
# point by its target, never followed (the profile holds junctions that loop,
# "Application Data" among them). Dot-source only, after common.ps1.
#
# Pruned, because something other than the step writes there: $HOME\work (the
# runner's checkouts), AppData\Local\Temp, AppData\Local\Microsoft\PowerShell
# (pwsh's own startup profile data, written by the child the harness starts),
# AppData\Local\Microsoft\Windows and AppData\Local\Packages (shell, store and
# app caches the OS keeps on its own), AppData\Local\ConnectedDevicesPlatform
# (a background service), the registry hives at the top of the profile
# (NTUSER.DAT and its logs flush on their own schedule), the clone's .git (as
# inside.sh prunes it) and the out dir. E2E_SNAPSHOT_PRUNE adds ;-separated
# paths, absolute or relative to HOME.
#
# Noted, not failed: AppData\LocalLow\Microsoft\CryptnetUrlCache, Windows'
# per-user cache of CRL and OCSP downloads. Every process of the runner
# account writes it, the Actions agent's own HTTPS traffic included, so a
# new entry during a step cannot be pinned on the step (setup-host.ps1
# -Check reads PATH, files, the registry and services, nothing networked).
# A difference there is kept in snapshots\<name>.diff as "noted ..." and does
# not fail the step; any other difference does.

$script:E2EPruneRelative = @(
    'work', 'AppData\Local\Temp', 'AppData\Local\Microsoft\PowerShell', 'AppData\Local\Microsoft\Windows',
    'AppData\Local\Packages', 'AppData\Local\ConnectedDevicesPlatform', 'dotfiles\.git'
)
$script:E2ENotedRelative = @('AppData\LocalLow\Microsoft\CryptnetUrlCache')

function Test-E2ENoted {
    # True for a snapshot difference ("added|removed|changed <path>...") under
    # a noted path.
    param([Parameter(Mandatory)][string]$Difference)
    $path = $Difference.Substring($Difference.IndexOf(' ') + 1)
    foreach ($entry in $script:E2ENotedRelative) {
        $prefix = [IO.Path]::GetFullPath((Join-Path $HOME $entry)).TrimEnd('\', '/')
        if ($path.StartsWith($prefix + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-E2EPruneList {
    # The pruned paths, full and without a trailing separator.
    $paths = [Collections.Generic.List[string]]::new()
    foreach ($entry in $script:E2EPruneRelative) { $paths.Add((Join-Path $HOME $entry)) }
    $paths.Add($E2E['Out'])
    foreach ($entry in ([string]$env:E2E_SNAPSHOT_PRUNE).Split(';')) {
        $trimmed = $entry.Trim()
        if (-not $trimmed) { continue }
        if ([IO.Path]::IsPathRooted($trimmed)) { $paths.Add($trimmed) } else { $paths.Add((Join-Path $HOME $trimmed)) }
    }
    return @($paths | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\', '/') })
}

function Test-E2EPruned {
    # True for a path under a pruned one, or a registry hive file of the profile.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root, [string[]]$Prune = @())
    $ignoreCase = [StringComparison]::OrdinalIgnoreCase
    foreach ($prefix in $Prune) {
        if ($Path.Equals($prefix, $ignoreCase) -or $Path.StartsWith($prefix + '\', $ignoreCase)) { return $true }
    }
    $parent = [string][IO.Path]::GetDirectoryName($Path)
    return $parent.TrimEnd('\', '/').Equals($Root.TrimEnd('\', '/'), $ignoreCase) -and
    [IO.Path]::GetFileName($Path).StartsWith('ntuser', $ignoreCase)
}

function Get-E2ESnapshot {
    # Root's tree as a dictionary: full path to "<size>|<LastWriteTimeUtc
    # ticks>" for a file, "dir" for a directory, "link|<target>" or
    # "dir-link|<target>" for a reparse point, "unreadable" where enumeration
    # or the file's record was refused.
    param([Parameter(Mandatory)][string]$Root, [string[]]$Prune = @())
    $snapshot = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($Root)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        $entries = @()
        try { $entries = @([IO.DirectoryInfo]::new($directory).EnumerateFileSystemInfos()) }
        catch {
            $snapshot[$directory] = 'unreadable'
            continue
        }
        foreach ($entry in $entries) {
            if (Test-E2EPruned -Path $entry.FullName -Root $Root -Prune $Prune) { continue }
            $isLink = ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
            if (($entry.Attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                if ($isLink) { $snapshot[$entry.FullName] = "dir-link|$(Get-E2ELinkTarget $entry)" }
                else {
                    $snapshot[$entry.FullName] = 'dir'
                    $pending.Push($entry.FullName)
                }
                continue
            }
            if ($isLink) {
                $snapshot[$entry.FullName] = "link|$(Get-E2ELinkTarget $entry)"
                continue
            }
            try {
                $entry.Refresh()
                $snapshot[$entry.FullName] = "$($entry.Length)|$($entry.LastWriteTimeUtc.Ticks)"
            }
            catch { $snapshot[$entry.FullName] = 'unreadable' }
        }
    }
    return $snapshot
}

function Compare-E2ESnapshot {
    # "added|removed|changed <path>" for every difference, sorted.
    param([Parameter(Mandatory)]$Before, [Parameter(Mandatory)]$After)
    $differences = [Collections.Generic.List[string]]::new()
    foreach ($path in $After.Keys) {
        if (-not $Before.ContainsKey($path)) { $differences.Add("added $path") }
        elseif ($Before[$path] -ne $After[$path]) { $differences.Add("changed $path ($($Before[$path]) -> $($After[$path]))") }
    }
    foreach ($path in $Before.Keys) {
        if (-not $After.ContainsKey($path)) { $differences.Add("removed $path") }
    }
    return @($differences | Sort-Object)
}

function Start-E2ENoWrite {
    # The before-image of a step that must write nothing: a fresh empty
    # directory under E2E_OUT\tmp\<name>, handed to the child as TEMP and TMP
    # (it must stay empty), and the pruned HOME snapshot.
    param([Parameter(Mandatory)][string]$Name)
    $temp = Join-Path $E2E['Out'] "tmp/$Name"
    if ([IO.Directory]::Exists($temp)) { Remove-Item -LiteralPath $temp -Recurse -Force }
    [void][IO.Directory]::CreateDirectory($temp)
    $E2E['NoWriteTemp'] = $temp
    $E2E['NoWriteHome'] = Get-E2ESnapshot -Root $HOME -Prune (Get-E2EPruneList)
}

function Get-E2ENoWriteEnvironment {
    # The child's TEMP and TMP for a no-write run.
    return @{ TEMP = $E2E['NoWriteTemp']; TMP = $E2E['NoWriteTemp'] }
}

function Stop-E2ENoWrite {
    # The violations, or '': TEMP entries left behind, HOME files added,
    # removed or changed outside the noted paths (every difference is kept in
    # snapshots\<name>.diff, the noted ones prefixed "noted ").
    param([Parameter(Mandatory)][string]$Name)
    $problems = [Collections.Generic.List[string]]::new()
    $left = @([IO.Directory]::EnumerateFileSystemEntries($E2E['NoWriteTemp']) | ForEach-Object { [IO.Path]::GetFileName($_) })
    if ($left.Count) { $problems.Add("TEMP not empty: $(ConvertTo-E2EOneLine ($left -join "`n") 200)") }
    $after = Get-E2ESnapshot -Root $HOME -Prune (Get-E2EPruneList)
    $differences = @(Compare-E2ESnapshot -Before $E2E['NoWriteHome'] -After $after)
    $real = @($differences | Where-Object { -not (Test-E2ENoted -Difference $_) })
    $report = @($differences | ForEach-Object { if (Test-E2ENoted -Difference $_) { "noted $_" } else { $_ } })
    [IO.File]::WriteAllText((Join-Path $E2E['Out'] "snapshots/$Name.diff"), (($report -join "`n") + "`n"), $script:E2EUtf8)
    if ($real.Count) {
        $problems.Add("HOME written ($($real.Count) difference(s)): $(ConvertTo-E2EOneLine ($real -join "`n") 300)")
    }
    $E2E['NoWriteHome'] = $null
    return ($problems -join '; ')
}
