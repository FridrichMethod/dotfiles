# PowerShell 7 profile (CurrentUserAllHosts), stowed from dotfiles.
# Portable (Join-Path $HOME ...) and install-free: optional tools and modules
# are used only when already present, and console-only setup sits behind one
# guard, because every `pwsh -Command ...` loads this file too.

# Agent terminals (Cursor, Gemini CLI) are real consoles, so the redirect test
# misses them. Mirror _is_agent_session in common/zsh/.zshrc and keep the
# prompt theme and key handlers out of their way.
$IsAgentSession = [bool]($env:CURSOR_AGENT -or $env:GEMINI_CLI)

# --- conda (lazy) -------------------------------------------------------------
# Do not run `conda init powershell`: it rewrites this file with an eager hook
# that spawns conda.exe on every start (~0.8-0.95 s) and an absolute path. The
# stub runs the same hook on first use, after which Conda.psm1's `conda` alias
# outranks it. The stub removes itself before running the hook: with
# auto_activate on, the hook ends in `conda activate base`, which would call
# the stub again, forever, if Conda.psm1 failed to load. Once the hook has
# returned without loading it (a failed hook, Ctrl+C) the stub comes back, so
# the next call retries instead of reaching a `conda` on PATH (conda.bat runs
# in a child cmd and cannot activate).
if (Test-Path -LiteralPath (Join-Path $HOME 'miniconda3\Scripts\conda.exe')) {
    function global:conda {
        $stub = $MyInvocation.MyCommand.ScriptBlock
        Remove-Item -LiteralPath Function:\conda
        try {
            $hook = & (Join-Path $HOME 'miniconda3\Scripts\conda.exe') shell.powershell hook | Out-String
            Invoke-Expression $hook
        }
        finally {
            if (-not (Test-Path Function:\Invoke-Conda)) { ${function:global:conda} = $stub }
        }
        if (-not (Test-Path Function:\Invoke-Conda)) {
            throw 'conda: shell.powershell hook did not load Conda.psm1'
        }
        Invoke-Conda @args
    }
    # Conda.psm1 completes only via the legacy TabExpansion function, which
    # PowerShell 7.4 stopped calling; this serves both the stub and the alias.
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

# --- Interactive console only -------------------------------------------------
# Redirected stdout breaks prediction, hangs CompletionPredictor, stalls
# Microsoft.WinGet.CommandNotFound for ~31 s and never draws a prompt, so all
# of that stays in here. A script run in a console (`pwsh -File x.ps1`, a .cmd
# wrapper's `pwsh -Command ...`) has real stdout but never reads a line. The
# console host imports PSReadLine before the profile only for a session that
# will (no -Command or -File without -NoExit, no -NonInteractive); VS Code's
# PowerShell extension does the same. The update check at the end uses the
# same test; as in zsh, agent terminals skip only the setup here.
$IsInteractive = -not [Console]::IsOutputRedirected -and (Get-Module PSReadLine)
if ($IsInteractive -and -not $IsAgentSession) {
    # The ANSI code page here is 936 (GBK), so pwsh mis-decoded captured UTF-8
    # output of native tools (git, rg, node, uv). The setter changes the code
    # page of the whole console (shared with any parent shell) and throws when
    # there is none, hence the guard and the try. Python (python, pip,
    # conda.exe) writes pipes in the ANSI code page, which this decoder would
    # turn into U+FFFD, so put it in UTF-8 mode. Unlike PYTHONIOENCODING, that
    # also makes a Python parent decode its Python children as UTF-8. A user
    # or parent setting wins, except PYTHONIOENCODING=utf-8, which this
    # profile used to export and which UTF-8 mode agrees with.
    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
        if (-not $env:PYTHONUTF8 -and (-not $env:PYTHONIOENCODING -or $env:PYTHONIOENCODING -eq 'utf-8')) {
            $env:PYTHONUTF8 = '1'
        }
    }
    catch { }

    # Get-Command takes ~0.45 s per missing name on this machine; probe PATH.
    $HasExe = {
        param([string]$Name)
        foreach ($dir in $env:PATH.Split([IO.Path]::PathSeparator)) {
            if ($dir -and [IO.File]::Exists([IO.Path]::Combine($dir, "$Name.exe"))) { return $true }
        }
        $false
    }

    # winget's documented completer, minus its per-call encoding reset.
    Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $word = $wordToComplete.Replace('"', '""')
        $line = $commandAst.ToString().Replace('"', '""')
        winget complete --word="$word" --commandline "$line" --position $cursorPosition | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }

    # --- PSReadLine -----------------------------------------------------------
    # The console host imports PSReadLine before profiles run, so it is not
    # imported again here.
    Set-PSReadLineOption -BellStyle None -HistorySearchCursorMovesToEnd `
        -PredictionSource HistoryAndPlugin -PredictionViewStyle ListView `
        -Colors @{ InlinePrediction = '#8d8d8d' }
    # Keep credentials out of ConsoleHost_history.txt (still recallable in this
    # session); a leading space mirrors zsh HIST_IGNORE_SPACE. A bearer token
    # needs a digit, an sk- key a vendor prefix (Anthropic, OpenAI project,
    # service-account, admin and legacy keys, OpenRouter), OpenAI's T3BlbkFJ
    # marker or one unbroken run, and PAT must be a whole name part, so prose
    # ("bearer authentication"), branch names (sk-refactor-dataloader-v2) and
    # *_PATH variables still reach the file.
    Set-PSReadLineOption -AddToHistoryHandler {
        param([string]$line)
        if ($line -match '^\s') { return [Microsoft.PowerShell.AddToHistoryOption]::MemoryOnly }
        $secret = '(?i)\bbearer\s+(?=[\w.~+/=-]*\d)[\w.~+/=-]{8,}' +
            '|\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_\w{20,})' +
            '|\bsk-(ant|proj|svcacct|admin|None|or-v1)-[\w-]{16,}|\bsk-[\w-]*T3BlbkFJ|\bsk-[A-Za-z0-9]{32,}' +
            '|\bhf_[A-Za-z0-9]{20,}' +
            '|\bAKIA[0-9A-Z]{16}\b|\bxox[abprs]-[\w-]{10,}' +
            '|-----BEGIN [A-Z ]*PRIVATE KEY-----' +
            '|\$env:\w*(token|secret|passw(or)?d|api_?key|(?<![a-z0-9])pat(?![a-z0-9]))\w*\s*=' +
            '|://[^/\s:@]+:[^/\s@]+@'
        if ($line -match $secret) { return [Microsoft.PowerShell.AddToHistoryOption]::MemoryOnly }
        [Microsoft.PowerShell.PSConsoleReadLine]::GetDefaultAddToHistoryOption($line)
    }
    # Tab cycles completions again. A suggestion is accepted with RightArrow at
    # the end of the line or by selecting it in the list view; Up/Down move
    # through that list while it is shown and search history by prefix
    # otherwise.
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

    # Both plugins register process-wide subsystems, so importing them on the
    # first idle tick works and keeps them off the startup path. Never installs.
    # A missing module stays quiet; one that is installed but fails to load
    # warns once per session, below the first prompt, which is then redrawn.
    $null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
        $failed = foreach ($module in 'CompletionPredictor', 'Microsoft.WinGet.CommandNotFound') {
            try { Import-Module $module -Global -ErrorAction Stop }
            catch {
                if ($_.FullyQualifiedErrorId -notlike 'Modules_ModuleNotFound,*') { "${module}: $($_.Exception.Message)" }
            }
        }
        if ($failed) {
            $Host.UI.WriteLine()
            $failed | ForEach-Object { $Host.UI.WriteWarningLine($_) }
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt($null, $Host.UI.RawUI.CursorPosition.Y)
        }
    }

    $PSStyle.FileInfo.Directory = $PSStyle.Bold + $PSStyle.Foreground.Blue

    # --- Optional CLI tools (docs/dependencies.md); each skipped when absent ---
    if (& $HasExe fzf) {
        if (-not $env:FZF_DEFAULT_OPTS) { $env:FZF_DEFAULT_OPTS = '--height=60% --layout=reverse --border --info=inline' }
        # Get-Module -ListAvailable takes ~30 ms; look in the module path instead.
        if ($env:PSModulePath.Split([IO.Path]::PathSeparator) |
                Where-Object { $_ -and [IO.Directory]::Exists([IO.Path]::Combine($_, 'PSFzf')) }) {
            # Calling an exported function autoloads PSFzf on the first keypress
            # instead of at startup. PSFzf never overrides a chord that is
            # already bound, so these bindings survive its import.
            Set-PSReadLineKeyHandler -Chord Ctrl+r -BriefDescription FzfHistory `
                -Description 'Search command history with fzf (PSFzf)' `
                -ScriptBlock { Invoke-FzfPsReadlineHandlerHistory }
            Set-PSReadLineKeyHandler -Chord Ctrl+t -BriefDescription FzfProvider `
                -Description 'Insert paths picked with fzf (PSFzf)' `
                -ScriptBlock { Invoke-FzfPsReadlineHandlerProvider }
            Set-PSReadLineKeyHandler -Chord Alt+c -BriefDescription FzfSetLocation `
                -Description 'Change to a directory picked with fzf (PSFzf)' `
                -ScriptBlock { Invoke-FzfPsReadlineHandlerSetLocation }
        }
    }
    # Same theme as common/zsh/.zshrc.
    if ((& $HasExe bat) -and -not $env:BAT_THEME) { $env:BAT_THEME = 'Catppuccin Mocha' }
    if (& $HasExe eza) {
        # eza does not glob on Windows and PowerShell passes wildcards to
        # native commands verbatim, so expand them here (ll *.pdb) as a POSIX
        # shell would: hidden items match, a pattern that matches nothing or
        # names an existing file ([draft].md) stays as typed, a rooted pattern
        # (~\Docu*, Temp:\*.log) yields full paths, and a match starting with
        # '-' gets a .\ prefix. Option values (-I '*.pyc') and everything after
        # a quoted '--' pass through; PowerShell drops a bare -- before this
        # sees it.
        function global:Expand-EzaArgs {
            # eza 0.23 options that consume the next word, including -F and
            # the --color/--icons kind whose value is optional. As in eza's
            # parser, that word is never another option (-F -I '*.pyc').
            $takesValue = '--ignore-glob', '--level', '--sort', '--time', '--width', '--time-style',
            '--color-scale-mode', '--classify', '--color', '--colour', '--icons', '--hyperlink',
            '--absolute', '--color-scale', '--colour-scale'
            $value = $literal = $false
            foreach ($a in $args) {
                if ($literal -or $a -isnot [string] -or ($value -and $a -notlike '-*')) { $value = $false; $a; continue }
                if ($a -like '-*') {
                    $literal = $a -eq '--'
                    $value = $a -cmatch '^-[^-ILstwF]*[ILstwF]$' -or $a -cin $takesValue
                    $a; continue
                }
                if (-not [WildcardPattern]::ContainsWildcardCharacters($a) -or (Test-Path -LiteralPath $a)) { $a; continue }
                try { $hits = @(Get-Item -Path $a -Force -ErrorAction Ignore | Where-Object { $_ -is [IO.FileSystemInfo] }) }
                catch { $hits = @() }
                if (-not $hits) { $a; continue }
                $rooted = $a -match '^~([\\/]|$)|^[^\\/:]+:' -or [IO.Path]::IsPathRooted($a)
                $here = (Get-Location -PSProvider FileSystem).ProviderPath
                foreach ($hit in $hits) {
                    $path = if ($rooted) { $hit.FullName } else { [IO.Path]::GetRelativePath($here, $hit.FullName) }
                    if ($path -like '-*') { Join-Path . $path } else { $path }
                }
            }
        }
        function global:ll { eza -l --group-directories-first --icons=auto @(Expand-EzaArgs @args) }
        function global:la { eza -la --group-directories-first --icons=auto @(Expand-EzaArgs @args) }
    }
    else {
        function global:ll { Get-ChildItem @args }
        function global:la { Get-ChildItem -Force @args }
    }

    # --- oh-my-posh prompt ----------------------------------------------------
    # Tracked theme (win/oh-my-posh), stowed to ~/.config/oh-my-posh. The
    # builtin name is only a fallback until stow links it, because it is
    # revalidated over the network. With shell_integration and
    # transient_prompt omp rebinds Enter and Ctrl+c, so this stays after every
    # other key handler.
    if (& $HasExe oh-my-posh) {
        $OmpConfig = Join-Path $HOME '.config/oh-my-posh/prompt.omp.json'
        if (-not (Test-Path -LiteralPath $OmpConfig -PathType Leaf)) { $OmpConfig = 'catppuccin' }
        oh-my-posh init pwsh --config $OmpConfig | Invoke-Expression
        Remove-Variable OmpConfig
        # The theme shows the conda env itself, so keep conda's '(env)' prefix
        # off this prompt, also for activations through conda-hook.ps1 (VS
        # Code, Anaconda Prompt) in this process. A user or parent value wins.
        if ((Get-Module oh-my-posh-core) -and $null -eq $env:CONDA_CHANGEPS1) { $env:CONDA_CHANGEPS1 = 'false' }
    }
    # zoxide wraps the prompt function, so it must run after oh-my-posh. Its
    # hook runs `zoxide add` after oh-my-posh restored $LASTEXITCODE, which
    # reset it to 0 after every cd, so the outer wrapper restores it again.
    # The value is a parameter default because any statement ahead of the
    # inner call would reset the $? that oh-my-posh reads, and the inner
    # prompt lives in a closure, not a global, so re-sourcing this profile
    # cannot make the wrapper call itself.
    if (& $HasExe zoxide) {
        Invoke-Expression (& { (zoxide init powershell | Out-String) })
        $function:global:prompt = & {
            $inner = $function:prompt
            {
                param($ExitCode = $global:LASTEXITCODE)
                & $inner
                $global:LASTEXITCODE = $ExitCode
            }.GetNewClosure()
        }
    }
    Remove-Variable HasExe
}
Remove-Variable IsAgentSession

# --- Dotfiles auto-update check ---------------------------------------
# Last, mirroring the tail of common/zsh/.zshrc, so the prompt and modules
# above are ready first. Like zsh, which returns before it for non-interactive
# shells, a script run in a console never fetches or stows. The session-once
# and no-console guards live in scripts/dotfiles-update.ps1 so both updaters
# keep one contract.
if ($IsInteractive) {
    $DotfilesDir = if ($env:DOTFILES_DIR) { $env:DOTFILES_DIR } else { Join-Path $HOME 'dotfiles' }
    $DotfilesUpdate = Join-Path $DotfilesDir 'scripts/dotfiles-update.ps1'
    if (Test-Path -LiteralPath $DotfilesUpdate) { & $DotfilesUpdate }
    Remove-Variable DotfilesDir, DotfilesUpdate
}
Remove-Variable IsInteractive
