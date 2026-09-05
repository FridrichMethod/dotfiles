#Requires -Version 7.0
<#
.SYNOPSIS
    Update dotfiles once per interactive login and automatically apply changes.
.DESCRIPTION
    Shares the Unix hook's session marker, opt-outs, clean-tree requirement,
    fast-forward-only updates and retry of unapplied revisions. Windows stow
    runs elevated, directly or through the explicitly registered current-user
    task (.\dotfiles-auto-stow.ps1 -Register). No login-time UAC prompt.
.NOTES
    DOTFILES_DIR          repository path (default ~/dotfiles)
    DOTFILES_AUTO_UPDATE  0 disables the entire hook
    DOTFILES_AUTO_STOW    0 keeps pull enabled but skips automatic stow
    DOTFILES_HOST         override remembered host (win or empty on Windows)
#>
# Native failures must not abort the caller's profile on PowerShell 7.4+.
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false

if ([Console]::IsOutputRedirected) { return }
if ($env:_DOTFILES_CHECKED) { return }

try {
    if ($env:DOTFILES_AUTO_UPDATE -eq '0') { return }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return }
    $repo = if ($env:DOTFILES_DIR) { $env:DOTFILES_DIR } else { Join-Path $HOME 'dotfiles' }
    if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) { return }
    . (Join-Path $repo 'dotfiles-auto-stow.ps1')
    Invoke-DotfilesUpdate $repo
}
catch {
    Write-Host "[dotfiles] update check failed: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    $env:_DOTFILES_CHECKED = '1'
}
