# Windows PowerShell 5.1 profile, stowed from dotfiles. Keep it 5.1 syntax
# and ASCII only: 5.1 reads a BOM-less file in the ANSI code page.

#region conda initialize (lazy)
# Do not run `conda init powershell`: it rewrites this block eagerly (~0.8 s
# per start) with an absolute path. The stub runs the same hook on first use;
# Conda.psm1's `conda` alias then outranks it. The stub removes itself before
# running the hook: with auto_activate on, the hook ends in `conda activate
# base`, which would call the stub again, forever, if Conda.psm1 failed to
# load. 5.1 has no oh-my-posh, so conda's own (env) prefix is the only env
# indicator here, except when this shell inherits CONDA_CHANGEPS1=false from a
# PowerShell 7 parent.
if (Test-Path -LiteralPath (Join-Path $HOME 'miniconda3\Scripts\conda.exe')) {
    function global:conda {
        Remove-Item -LiteralPath Function:\conda
        $hook = & (Join-Path $HOME 'miniconda3\Scripts\conda.exe') shell.powershell hook | Out-String
        Invoke-Expression $hook
        if (-not (Test-Path Function:\Invoke-Conda)) {
            throw 'conda: shell.powershell hook did not load Conda.psm1'
        }
        Invoke-Conda @args
    }
    # Same completer as the PowerShell 7 profile, so the stub completes before
    # Conda.psm1 (whose TabExpansion spawns conda.exe per Tab) is loaded.
    # Commands are conda 26.5's `conda commands`; only the words before the
    # cursor count, so completing mid-line works.
    Register-ArgumentCompleter -Native -CommandName conda -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $words = @($commandAst.CommandElements | Where-Object { $_.Extent.EndOffset -lt $cursorPosition } |
                ForEach-Object { $_.Extent.Text })
        $candidates = if ($words.Count -eq 1) {
            'activate', 'check', 'clean', 'commands', 'compare', 'config', 'content-trust', 'create',
            'deactivate', 'doctor', 'env', 'export', 'index', 'info', 'init', 'install', 'list',
            'menuinst', 'notices', 'package', 'pypi', 'remove', 'rename', 'repoquery', 'run',
            'search', 'self', 'token', 'tos', 'uninstall', 'update', 'upgrade'
        }
        elseif (($words.Count -eq 2 -and $words[1] -eq 'activate') -or $words[-1] -in '-n', '--name') {
            @('base') + @(Get-ChildItem -LiteralPath (Join-Path $HOME 'miniconda3\envs') -Directory -ErrorAction Ignore |
                    ForEach-Object Name)
        }
        $candidates | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}
#endregion
