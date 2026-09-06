#Requires -Version 7.0
# Dot-source only: no preference, terminal-theme or environment changes.
# Use the Information stream so PowerShell *> redirection and task logs keep
# working. DOTFILES_COLOR=always explicitly permits redirected ANSI; NO_COLOR
# (nonempty) and TERM=dumb still win. Invalid modes mean auto.
function Write-DotfilesLog {
    param(
        [ValidateSet('step', 'ok', 'warn', 'error', 'info')][string]$Level,
        [AllowEmptyString()][string]$Message
    )
    $line = "[dotfiles] [$Level] $Message"
    $redirected = [Console]::IsOutputRedirected
    $color = $false
    if (-not $env:NO_COLOR -and $env:TERM -ne 'dumb' -and $env:DOTFILES_COLOR -ne 'never') {
        $color = $env:DOTFILES_COLOR -eq 'always' -or
            (-not $redirected -and $Host.UI.SupportsVirtualTerminal)
    }
    $forced = $color -and $env:DOTFILES_COLOR -eq 'always'
    if ($color -and -not $forced) {
        # Native foreground metadata is not part of MessageData: even a
        # same-console *> log stays plain when OutputRendering=Ansi. Native
        # Write-Host has no bold attribute; explicit always uses bold cyan.
        $foreground = switch ($Level) {
            step { 'Cyan' }
            ok { 'Green' }
            warn { 'Yellow' }
            error { 'Red' }
        }
        if ($foreground) { Write-Host $line -ForegroundColor $foreground }
        else { Write-Host $line }
        return
    }
    if ($forced) {
        $code = switch ($Level) {
            step { '1;36' }
            ok { '32' }
            warn { '33' }
            error { '31' }
        }
        if ($code) { $line = "$([char]27)[$($code)m$line$([char]27)[0m" }
    }
    # PS 7.2+ strips ANSI when OutputRendering=PlainText, including on some CI
    # hosts. A forced-color request applies only to this message, never the
    # caller's subsequent output. Auto retains normal PS redirection behavior.
    $style = Get-Variable -Name PSStyle -ValueOnly -ErrorAction SilentlyContinue
    if ($forced -and $style) {
        $rendering = $style.OutputRendering
        try {
            $style.OutputRendering = 'Ansi'
            Write-Host $line
        }
        finally { $style.OutputRendering = $rendering }
    }
    else { Write-Host $line }
}
