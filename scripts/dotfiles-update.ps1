#Requires -Version 7.0
<#
.SYNOPSIS
    Update dotfiles once per interactive login and automatically apply changes.
.DESCRIPTION
    Shares the Unix hook's session marker, opt-outs, clean-tree requirement,
    fast-forward-only updates and retry of unapplied revisions. Windows stow
    runs elevated, directly or through the explicitly registered current-user
    task (.\scripts\dotfiles-auto-stow.ps1 -Register). No login-time UAC prompt.
.NOTES
    DOTFILES_DIR          repository path (default ~/dotfiles)
    DOTFILES_AUTO_UPDATE  0 disables the entire hook
    DOTFILES_AUTO_STOW    0 keeps pull enabled but skips automatic stow
    DOTFILES_HOST         override remembered host (win or empty on Windows)
#>
if ([Console]::IsOutputRedirected) { return }
if ($env:_DOTFILES_CHECKED) { return }

# Keep native failures session-safe without changing a dot-sourcing caller's
# preferences or leaving the worker's functions in the user's profile scope.
& {
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    function Write-DotfilesLog {
        param([string]$Level, [string]$Message)
        Write-Host "[dotfiles] [$Level] $Message"
    }
    try {
        if ($env:DOTFILES_AUTO_UPDATE -eq '0') { return }
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return }
        $repo = if ($env:DOTFILES_DIR) { $env:DOTFILES_DIR } else { Join-Path $HOME 'dotfiles' }
        if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) { return }
        . (Join-Path $repo 'scripts/dotfiles-auto-stow.ps1')
        Invoke-DotfilesUpdate $repo
    }
    catch {
        Write-DotfilesLog error "Update check failed: $($_.Exception.Message)"
    }
    finally {
        $env:_DOTFILES_CHECKED = '1'
    }
}
