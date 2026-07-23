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
