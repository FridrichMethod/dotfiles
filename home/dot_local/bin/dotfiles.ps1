#Requires -Version 7.0
# Raw arguments pass unchanged to the configured checkout's dispatcher.
$callerErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$forwardArguments = $args
try {
    $config = Get-Item -LiteralPath (Join-Path $HOME '.config/chezmoi/chezmoi.toml') -Force -ErrorAction Stop
    if ($config -isnot [IO.FileInfo] -or ($config.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The chezmoi config must be a regular file.'
    }
    $text = [Text.UTF8Encoding]::new($false, $true).GetString([IO.File]::ReadAllBytes($config.FullName))
    $source = $null
    foreach ($line in ($text -split "`n")) {
        if ($line.TrimStart([char[]]@(' ', "`t")).StartsWith('[', [StringComparison]::Ordinal)) { break }
        if ($line -cmatch '\AsourceDir = "([^"\r\n]+)"\z') { $source = $Matches[1]; break }
    }
    if (-not $source -or -not [IO.Path]::IsPathFullyQualified($source)) { throw 'No absolute sourceDir.' }
    $guard = Join-Path $source 'lib/chezmoi-guard.ps1'
    if (-not (Test-Path -LiteralPath $guard -PathType Leaf)) { throw 'Missing source guard.' }
    . $guard
    $source = (Get-DotfilesChezmoiPaths -HomePath $HOME).Source
    $dispatcher = Join-Path $source 'dotfiles.ps1'
    if (-not (Test-Path -LiteralPath $dispatcher -PathType Leaf)) { throw 'Missing dispatcher.' }
}
catch {
    [Console]::Error.WriteLine('dotfiles: ~/.config/chezmoi/chezmoi.toml must name this home and an available dotfiles checkout; run & CHECKOUT\dotfiles.ps1 explicitly to recover.')
    exit 1
}
$ErrorActionPreference = $callerErrorActionPreference
try {
    $global:LASTEXITCODE = 0
    & $dispatcher @forwardArguments
    $status = $global:LASTEXITCODE
}
catch {
    [Console]::Error.WriteLine('dotfiles: invocation failed; run & CHECKOUT\dotfiles.ps1 explicitly to recover.')
    exit 1
}
exit $status
