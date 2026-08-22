#Requires -Version 7.0
<#
.SYNOPSIS
    Checks for upstream dotfiles changes on login - the PowerShell
    counterpart to dotfiles-update.sh.

.DESCRIPTION
    Same contract as the POSIX hook: fetch, fast-forward when behind, then
    stop. Re-stowing is never automatic. On Windows that is not merely a
    preference: only an elevated run creates trusted symlinks, and a login
    shell is not elevated, so an automatic re-stow would quietly produce
    links that no ssh session can traverse.

    Two guards keep it from firing where it should not.

    $env:_DOTFILES_CHECKED is a process environment variable, so every child
    shell and nested pwsh inherits it and skips instantly, while a fresh
    login starts with a clean environment and checks again.

    Redirected stdout means there is no console, which is true of every
    `pwsh -Command ...` invocation - scripts, ssh one-liners, editor
    tooling - and stands in for the POSIX interactive-shell test. Without it
    a network fetch would run on every scripted call.

.NOTES
    Configurable before invocation:
      $env:DOTFILES_DIR          repo path (default: ~/dotfiles)
      $env:DOTFILES_AUTO_UPDATE  set to 0 to disable
#>

# Deliberately not 'Stop': PowerShell 7.4+ turns a failing native command
# into a terminating error under 'Stop', which would abort the whole profile
# just because git could not reach the remote. Exit codes are checked instead.
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false

if ([Console]::IsOutputRedirected) { return }
if ($env:_DOTFILES_CHECKED) { return }

function Write-DotfilesNote {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Color = 'Yellow'
    )
    Write-Host '[dotfiles] ' -ForegroundColor $Color -NoNewline
    Write-Host $Message
}

try {
    if ($env:DOTFILES_AUTO_UPDATE -eq '0') { return }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return }

    $repo = if ($env:DOTFILES_DIR) { $env:DOTFILES_DIR } else { Join-Path $HOME 'dotfiles' }
    if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) { return }

    # A credential prompt here would hang the login before the prompt appears.
    $savedPrompt = $env:GIT_TERMINAL_PROMPT
    $env:GIT_TERMINAL_PROMPT = '0'
    try {
        git -C $repo fetch --quiet 2>$null
        if ($LASTEXITCODE -ne 0) { return }

        # Quoted: @{ starts a hashtable literal in PowerShell.
        $behind = git -C $repo rev-list --count 'HEAD..@{upstream}' 2>$null
        if ($LASTEXITCODE -ne 0) { return }
        $count = $behind -as [int]
        if (-not $count -or $count -le 0) { return }

        Write-DotfilesNote "$count new commit(s) available - pulling..."
        git -C $repo pull --ff-only --quiet 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-DotfilesNote "Fast-forward pull failed. Resolve manually in $repo." -Color Red
            return
        }
        git -C $repo submodule update --init --recursive --quiet 2>$null
        Write-DotfilesNote 'Pulled successfully.' -Color Green
        Write-DotfilesNote 'Run stow-all.ps1 from an elevated PowerShell to re-stow, then restart the shell.'
    }
    finally {
        if ($null -eq $savedPrompt) {
            Remove-Item Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue
        }
        else {
            $env:GIT_TERMINAL_PROMPT = $savedPrompt
        }
    }
}
catch {
    # Never break a login over this, but never swallow it silently either.
    Write-DotfilesNote "update check failed: $($_.Exception.Message)" -Color Red
}
finally {
    # Set even when the check bailed out, so a broken repo or missing remote
    # does not re-run the whole probe in every subshell of this session.
    $env:_DOTFILES_CHECKED = '1'
}
