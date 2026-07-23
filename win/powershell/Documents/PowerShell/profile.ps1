#region conda initialize
# !! Contents within this block are managed by 'conda init' !!
# Path kept $HOME-relative so the file stays portable; re-running
# `conda init` will rewrite it with an absolute path.
$CondaExe = Join-Path $HOME 'miniconda3\Scripts\conda.exe'
If (Test-Path $CondaExe) {
    (& $CondaExe "shell.powershell" "hook") | Out-String |
        Where-Object { $_ } | Invoke-Expression
}
#endregion

# --- WinGet "command-not-found" hook ---------------------------------
if (Get-Module -ListAvailable Microsoft.WinGet.CommandNotFound) {
    Import-Module Microsoft.WinGet.CommandNotFound
}

# --- PSReadLine core --------------------------------------------------
Import-Module PSReadLine

# --- PSReadLine tuning ------------------------------------------------
Set-PSReadLineOption -Colors @{ InLinePrediction = '#8d8d8d' }

# Choose ONE Tab mode - comment the other
Set-PSReadLineKeyHandler -Key Tab -Function AcceptSuggestion   # drop-down accepts
# Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete     # bash-like cycling

# --- Prediction: interactive consoles only ----------------------------
# Everything below needs a real console, and redirected stdout - which is
# every `pwsh -Command ...` invocation - breaks it in three separate ways:
# PSReadLine reports "the predictive suggestion feature cannot be enabled"
# directly to the host so -ErrorAction cannot silence it; importing
# CompletionPredictor hangs the session outright; and Install-Module would
# block on the PSGallery trust prompt with no one to answer it. None of
# this can work when redirected, so skipping it loses nothing.
if (-not [Console]::IsOutputRedirected) {
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin    # history + plugins
    Set-PSReadLineOption -PredictionViewStyle ListView         # VS Code-style panel

    if (-not (Get-Module CompletionPredictor -ListAvailable)) {
        Install-Module CompletionPredictor -Scope CurrentUser -Force
    }
    Import-Module CompletionPredictor
}

# --- Oh-My-Posh prompt (requires PSReadLine already loaded) -----------
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config 'catppuccin' | Invoke-Expression
}
