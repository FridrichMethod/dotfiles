#Requires -Version 7.0
# PowerShell profile and oh-my-posh theme contract. Runs with -NoProfile and
# never loads the live profile: static checks walk the AST, and the load checks
# dot-source the tracked files in child processes with a fake HOME and the
# update hook disabled.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = Split-Path -Parent $PSScriptRoot
$profile7 = Join-Path $repoRoot 'win/powershell/Documents/PowerShell/profile.ps1'
$profile51 = Join-Path $repoRoot 'win/powershell/Documents/WindowsPowerShell/profile.ps1'
$theme = Join-Path $repoRoot 'win/oh-my-posh/.config/oh-my-posh/prompt.omp.json'
$zshrc = Join-Path $repoRoot 'common/zsh/.zshrc'
$powerShell = (Get-Process -Id $PID).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) { Write-Output "ok: $Message" }
    else {
        Write-Output "FAIL: $Message"
        $failures.Add($Message)
    }
}

# Runs a child without a window or stdin, with environment edits ($null
# removes a variable), drains both streams concurrently so neither pipe can
# fill up, and kills it after the timeout.
function Invoke-Child {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [hashtable]$Environment = @{},
        [int]$TimeoutSeconds = 60
    )
    $psi = [Diagnostics.ProcessStartInfo]::new($FilePath)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($name in $Environment.Keys) {
        if ($null -eq $Environment[$name]) { $null = $psi.Environment.Remove($name) }
        else { $psi.Environment[$name] = $Environment[$name] }
    }
    foreach ($a in $ArgumentList) { $psi.ArgumentList.Add($a) }
    $process = [Diagnostics.Process]::Start($psi)
    try {
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) { $process.Kill($true) }
        $process.WaitForExit()
        [pscustomobject]@{
            TimedOut = $timedOut
            ExitCode = $process.ExitCode
            Out = $stdout.GetAwaiter().GetResult().Trim()
            Err = $stderr.GetAwaiter().GetResult().Trim()
        }
    }
    finally { $process.Dispose() }
}

function Get-ProfileAst([string]$Path) {
    $tokens = $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count) {
        throw "$Path does not parse: $(($errors | ForEach-Object Message) -join '; ')"
    }
    [pscustomobject]@{ Ast = $ast; Tokens = $tokens }
}

function Get-Commands($Ast) {
    $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
}

function Test-InsideNode($Node, $Ancestor) {
    for ($p = $Node.Parent; $p; $p = $p.Parent) {
        if ([object]::ReferenceEquals($p, $Ancestor)) { return $true }
    }
    $false
}

function Get-FunctionAst($Ast, [string]$Name) {
    $Ast.Find({
            param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            ($n.Name -replace '^global:', '') -eq $Name
        }, $true)
}

$parsed7 = Get-ProfileAst $profile7
$parsed51 = Get-ProfileAst $profile51
$text7 = Get-Content -LiteralPath $profile7 -Raw
Assert-True $true 'both profiles parse'

Write-Output '--- install-free and portable'
foreach ($parsed in $parsed7, $parsed51) {
    $commands = Get-Commands $parsed.Ast
    $installs = @($commands | Where-Object {
            $_.GetCommandName() -in 'Install-Module', 'Install-PSResource', 'Install-Script', 'Update-Module', 'Update-PSResource' -or
            ($_.GetCommandName() -eq 'winget' -and $_.CommandElements.Count -gt 1 -and
            $_.CommandElements[1].Extent.Text -in 'install', 'upgrade')
        })
    Assert-True ($installs.Count -eq 0) "$($parsed.Ast.Extent.File | Split-Path -Leaf) ($(Split-Path -Leaf (Split-Path -Parent $parsed.Ast.Extent.File))) installs nothing"
}
foreach ($file in $profile7, $profile51, $theme) {
    $content = Get-Content -LiteralPath $file -Raw
    Assert-True ($content -notmatch '(?i)\b[a-z]:[\\/]+users[\\/]') "$file holds no absolute user path"
}
foreach ($file in $profile51, $theme) {
    $bytes = [IO.File]::ReadAllBytes($file)
    Assert-True (-not ($bytes | Where-Object { $_ -gt 0x7F })) "$file is ASCII only"
}

Write-Output '--- PowerShell 7 profile structure'
$tailMarker = '# --- Dotfiles auto-update check'
$tailAt = $text7.IndexOf($tailMarker)
Assert-True ($tailAt -gt 0) 'the update hook block is present'
$tail = $text7.Substring([Math]::Max($tailAt, 0))
Assert-True ($tail.Contains('scripts/dotfiles-update.ps1')) 'the update hook runs scripts/dotfiles-update.ps1'
Assert-True ($tail -notmatch 'Import-Module|oh-my-posh|Set-PSReadLine|zoxide') 'nothing interactive runs after the update hook'

# Interactive setup runs only in the then-branch of exactly this if: stdout is
# a console, no agent terminal, and the host loaded PSReadLine, which it skips
# for -Command/-File scripts and -NonInteractive. Comparing the whole condition
# catches an inverted or dropped term, and the branch check catches setup moved
# into an else or elseif.
$guardText = '-not [Console]::IsOutputRedirected -and -not $IsAgentSession -and (Get-Module PSReadLine)'
$guards = @($parsed7.Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] }, $true) |
        Where-Object { ($_.Clauses[0].Item1.Extent.Text -replace '\s+', ' ').Trim() -eq $guardText })
Assert-True ($guards.Count -eq 1) "exactly one interactive guard: if ($guardText)"
$guardBody = if ($guards.Count -eq 1) { $guards[0].Clauses[0].Item2 }
$guarded = @(Get-Commands $parsed7.Ast | Where-Object {
        $name = $_.GetCommandName()
        $name -in 'Set-PSReadLineOption', 'Set-PSReadLineKeyHandler', 'Register-EngineEvent', 'oh-my-posh', 'zoxide' -or
        ($name -eq 'Import-Module' -and $_.Extent.Text -match 'CompletionPredictor|Microsoft\.WinGet\.CommandNotFound|PSFzf')
    })
Assert-True ($guarded.Count -ge 8) "found the interactive commands ($($guarded.Count))"
$outside = @($guarded | Where-Object { -not ($guardBody -and (Test-InsideNode $_ $guardBody)) })
Assert-True ($outside.Count -eq 0) "interactive setup runs only in the guard's then-branch$(if ($outside) { ': ' + (($outside | ForEach-Object { $_.Extent.Text.Split("`n")[0] }) -join ' | ') })"

# $IsAgentSession tests exactly the variables zsh's _is_agent_session tests,
# joined with -or, so an agent terminal skips the same setup in both shells.
$zshAgents = @()
if (Test-Path -LiteralPath $zshrc) {
    $zshMatch = [regex]::Match((Get-Content -LiteralPath $zshrc -Raw), '(?m)^_is_agent_session\(\)\s*\{\s*\[\[(?<body>[^\]]*)\]\]\s*\}')
    if ($zshMatch.Success) {
        $terms = @($zshMatch.Groups['body'].Value -split '\|\|')
        $names = @($terms | ForEach-Object { if ($_ -match '^\s*-n\s+"\$\{?(\w+)\}?"\s*$') { $Matches[1].ToUpperInvariant() } })
        if ($names.Count -eq $terms.Count) { $zshAgents = $names }
    }
}
Assert-True ($zshAgents.Count -gt 0) "common/zsh/.zshrc defines _is_agent_session as [[ -n `"`$A`" || ... ]] ($($zshAgents -join ', '))"
$psAgents = @()
$agentFlag = $parsed7.Ast.Find({
        param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left.Extent.Text -eq '$IsAgentSession'
    }, $true)
if ($agentFlag) {
    $find = { param($Type) @($agentFlag.Right.FindAll({ param($n) $n -is $Type }.GetNewClosure(), $true)) }
    $variables = & $find ([System.Management.Automation.Language.VariableExpressionAst])
    $operators = @(& $find ([System.Management.Automation.Language.BinaryExpressionAst]) | ForEach-Object Operator)
    $negations = & $find ([System.Management.Automation.Language.UnaryExpressionAst])
    if (-not ($variables | Where-Object { $_.VariablePath.DriveName -ne 'env' }) -and
        -not ($operators | Where-Object { $_ -ne 'Or' }) -and -not $negations) {
        $psAgents = @($variables | ForEach-Object { ($_.VariablePath.UserPath -replace '^env:', '').ToUpperInvariant() })
    }
}
$sameAgents = (@($zshAgents | Sort-Object -Unique) -join ',') -eq (@($psAgents | Sort-Object -Unique) -join ',')
Assert-True ($zshAgents.Count -gt 0 -and $sameAgents) "`$IsAgentSession is `$env:$($zshAgents -join ' -or $env:'), like _is_agent_session (profile: $($psAgents -join ', '))"

$importsPSReadLine = @(Get-Commands $parsed7.Ast | Where-Object {
        $_.GetCommandName() -eq 'Import-Module' -and $_.Extent.Text -match '\bPSReadLine\b'
    })
Assert-True ($importsPSReadLine.Count -eq 0) 'PSReadLine is not imported again'
$getCommand = @(Get-Commands $parsed7.Ast | Where-Object { $_.GetCommandName() -in 'Get-Command', 'gcm' })
Assert-True ($getCommand.Count -eq 0) 'optional tools are probed on PATH, not with Get-Command'

$tabBinding = @(Get-Commands $parsed7.Ast | Where-Object {
        $_.GetCommandName() -eq 'Set-PSReadLineKeyHandler' -and $_.Extent.Text -match '-Key\s+Tab\b'
    })
Assert-True ($tabBinding.Count -eq 1 -and $tabBinding[0].Extent.Text -match 'MenuComplete') 'Tab is bound to MenuComplete'

$ompInit = @(Get-Commands $parsed7.Ast | Where-Object { $_.GetCommandName() -eq 'oh-my-posh' })
$keyHandlers = @(Get-Commands $parsed7.Ast | Where-Object { $_.GetCommandName() -eq 'Set-PSReadLineKeyHandler' })
Assert-True ($ompInit.Count -eq 1 -and -not ($keyHandlers | Where-Object { $_.Extent.StartOffset -gt $ompInit[0].Extent.StartOffset })) 'oh-my-posh initializes after every other key handler'
$zoxide = @(Get-Commands $parsed7.Ast | Where-Object { $_.GetCommandName() -eq 'zoxide' })
Assert-True ($zoxide.Count -eq 1 -and $ompInit.Count -eq 1 -and $zoxide[0].Extent.StartOffset -gt $ompInit[0].Extent.StartOffset) 'zoxide wraps the oh-my-posh prompt, so it initializes after it'
Assert-True ($text7.Contains(".config/oh-my-posh/prompt.omp.json")) 'the profile loads the tracked theme path'

Write-Output '--- conda stays lazy'
foreach ($parsed in $parsed7, $parsed51) {
    $file = $parsed.Ast.Extent.File
    $hooks = @(Get-Commands $parsed.Ast | Where-Object { $_.Extent.Text -match 'shell\.powershell' })
    $stub = Get-FunctionAst $parsed.Ast 'conda'
    Assert-True ($hooks.Count -ge 1 -and -not ($hooks | Where-Object { -not ($stub -and (Test-InsideNode $_ $stub)) })) "$file runs the conda hook only from the conda stub"
    # With auto_activate the hook itself calls conda; the stub must be gone by
    # then, or a failed Conda.psm1 import recurses until the call stack overflows.
    $removal = if ($stub) { @(Get-Commands $stub.Body | Where-Object { $_.GetCommandName() -eq 'Remove-Item' -and $_.Extent.Text -match 'Function:\\conda' }) }
    $evaluation = if ($stub) { @(Get-Commands $stub.Body | Where-Object { $_.GetCommandName() -eq 'Invoke-Expression' }) }
    Assert-True ($removal.Count -eq 1 -and $evaluation.Count -eq 1 -and $removal[0].Extent.StartOffset -lt $evaluation[0].Extent.StartOffset) "$file drops the conda stub before running the hook"
}
$condaSetup = {
    param($parsed)
    $completer = @(Get-Commands $parsed.Ast | Where-Object {
            $_.GetCommandName() -eq 'Register-ArgumentCompleter' -and $_.Extent.Text -match '-CommandName\s+conda\b'
        })
    ((Get-FunctionAst $parsed.Ast 'conda').Extent.Text, ($completer | ForEach-Object { $_.Extent.Text })) -join "`n"
}
Assert-True ((& $condaSetup $parsed7) -ceq (& $condaSetup $parsed51) -and (& $condaSetup $parsed7) -match 'Register-ArgumentCompleter') 'both profiles define the same conda stub and completer'

Write-Output '--- Windows PowerShell 5.1 compatibility'
$modern = @($parsed51.Ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.TernaryExpressionAst] -or
            $n -is [System.Management.Automation.Language.PipelineChainAst] -or
            ($n -is [System.Management.Automation.Language.BinaryExpressionAst] -and $n.Operator -eq 'QuestionQuestion') -or
            ($n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Operator -eq 'QuestionQuestionEquals')
        }, $true))
Assert-True ($modern.Count -eq 0) 'the 5.1 profile avoids PowerShell 7-only syntax'
$windowsPowerShell = if ($IsWindows) { Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
if ($windowsPowerShell -and (Test-Path -LiteralPath $windowsPowerShell)) {
    $fakeHome51 = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-profile51-test-" + [guid]::NewGuid().ToString('N'))
    try {
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $fakeHome51 'miniconda3/Scripts'), (Join-Path $fakeHome51 'miniconda3/envs/demo')
        $null = New-Item -ItemType File -Force -Path (Join-Path $fakeHome51 'miniconda3/Scripts/conda.exe')
        # Paths travel in the environment, so no quoting can break the command.
        # Windows PowerShell cannot load modules from the pwsh 7 module path it
        # would inherit, so that variable is removed.
        $child51 = @'
$t = $e = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($env:DOTFILES_TEST_PROFILE, [ref]$t, [ref]$e)
"parse-errors=$($e.Count)"
Set-Variable -Name HOME -Value $env:DOTFILES_TEST_HOME -Force -Scope Global
. $env:DOTFILES_TEST_PROFILE
"conda=$((Get-Command conda).CommandType)"
"subcommand=$(@((TabExpansion2 'conda inf --json' 9).CompletionMatches | ForEach-Object CompletionText) -join ',')"
"env=$(@((TabExpansion2 'conda activate de' 17).CompletionMatches | ForEach-Object CompletionText) -join ',')"
'@
        $result = Invoke-Child $windowsPowerShell @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', $child51) -Environment @{
            PSModulePath = $null; DOTFILES_TEST_PROFILE = $profile51; DOTFILES_TEST_HOME = $fakeHome51
        }
        $expected = "parse-errors=0`nconda=Function`nsubcommand=info`nenv=demo"
        Assert-True (-not $result.TimedOut -and $result.ExitCode -eq 0 -and ($result.Out -replace "`r", '') -eq $expected -and -not $result.Err) "the 5.1 profile parses and completes conda under Windows PowerShell (exit=$($result.ExitCode) out=$($result.Out -replace '\s+', ' ') err=$($result.Err))"
    }
    finally {
        Remove-Item -LiteralPath $fakeHome51 -Recurse -Force -ErrorAction SilentlyContinue
    }
}
else {
    Write-Output 'SKIP: Windows PowerShell 5.1 parse (not on Windows)'
}

Write-Output '--- history filter'
Import-Module PSReadLine -ErrorAction SilentlyContinue
if (Get-Module PSReadLine) {
    $handlerAst = (Get-Commands $parsed7.Ast | Where-Object {
            $_.GetCommandName() -eq 'Set-PSReadLineOption' -and $_.Extent.Text -match '-AddToHistoryHandler'
        } | Select-Object -First 1).FindAll({
            param($n) $n -is [System.Management.Automation.Language.ScriptBlockExpressionAst]
        }, $true) | Select-Object -First 1
    $handler = $handlerAst.ScriptBlock.GetScriptBlock()
    $memoryOnly = [Microsoft.PowerShell.AddToHistoryOption]::MemoryOnly
    foreach ($line in @(
            'curl -H "Authorization: Bearer abcdefghijkl" https://example.org',
            ('echo ghp_' + ('a' * 24)),
            '$env:ANTHROPIC_API_KEY = "sk-ant-xxxxxxxxxxxxxxxxxx"',
            'git clone https://user:pass@example.org/repo.git',
            ' echo kept in memory only')) {
        Assert-True ((& $handler $line) -eq $memoryOnly) "history keeps out of the file: $line"
    }
    Assert-True ((& $handler 'git push') -eq [Microsoft.PowerShell.AddToHistoryOption]::MemoryAndFile) 'ordinary commands still reach the history file'
}
else {
    Write-Output 'SKIP: PSReadLine unavailable'
}

Write-Output '--- bounded, silent redirected load'
$fakeHome = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-profile-test-" + [guid]::NewGuid().ToString('N'))
try {
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $fakeHome 'miniconda3/Scripts'), (Join-Path $fakeHome 'miniconda3/envs/demo')
    $null = New-Item -ItemType File -Force -Path (Join-Path $fakeHome 'miniconda3/Scripts/conda.exe')
    $child = @'
$ErrorActionPreference = 'Stop'
Set-Variable -Name HOME -Value $env:DOTFILES_TEST_HOME -Force -Scope Global
$promptBefore = (Get-Command prompt).ScriptBlock.ToString()
$before = @((Get-Variable).Name)
$sw = [Diagnostics.Stopwatch]::StartNew()
. $env:DOTFILES_TEST_PROFILE
$sw.Stop()
$leaked = @((Get-Variable).Name | Where-Object { $_ -notin $before -and $_ -notin 'before', 'sw', 'promptBefore' })
if ($sw.Elapsed.TotalSeconds -ge 5) { throw "profile load took $($sw.Elapsed.TotalSeconds) s" }
if ($leaked) { throw "profile leaked globals: $($leaked -join ', ')" }
if ((Get-Command prompt).ScriptBlock.ToString() -ne $promptBefore) { throw 'redirected load changed the prompt' }
foreach ($name in 'CONDA_CHANGEPS1', 'PYTHONUTF8', 'PYTHONIOENCODING') {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ($null -ne $value) { throw "redirected load set $name=$value" }
}
if ($IsWindows) {
    if ((Get-Command conda).CommandType -ne 'Function') { throw 'conda is not the lazy stub' }
    $completion = (TabExpansion2 'conda activate de' 17).CompletionMatches.CompletionText
    if ('demo' -notin $completion) { throw "conda completion offered: $($completion -join ', ')" }
    $completion = (TabExpansion2 'conda inf --json' 9).CompletionMatches.CompletionText
    if ('info' -notin $completion) { throw "mid-line conda completion offered: $($completion -join ', ')" }
}
'PASS'
'@
    $result = Invoke-Child $powerShell @('-NoProfile', '-NonInteractive', '-Command', $child) -Environment @{
        DOTFILES_AUTO_UPDATE = '0'
        DOTFILES_DIR = Join-Path $fakeHome 'no-dotfiles'
        DOTFILES_TEST_HOME = $fakeHome
        DOTFILES_TEST_PROFILE = $profile7
        CONDA_CHANGEPS1 = $null
        PYTHONUTF8 = $null
        PYTHONIOENCODING = $null
    }
    Assert-True (-not $result.TimedOut -and $result.ExitCode -eq 0 -and $result.Out -eq 'PASS' -and -not $result.Err) "redirected load is fast, silent and leaves the prompt and environment alone (timedout=$($result.TimedOut) exit=$($result.ExitCode) out=$($result.Out) err=$($result.Err))"
}
finally {
    Remove-Item -LiteralPath $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output '--- oh-my-posh theme'
$config = Get-Content -LiteralPath $theme -Raw | ConvertFrom-Json
Assert-True ($config.'$schema' -match '/v\d+\.\d+\.\d+/themes/schema\.json$') 'the theme pins its schema to a release'
Assert-True ($config.shell_integration -eq $true) 'the theme emits shell-integration marks'
Assert-True ($null -ne $config.transient_prompt) 'the theme defines a transient prompt'
Assert-True ($config.upgrade.auto -eq $false -and $config.upgrade.notice -eq $false) 'the theme never upgrades or nags'
$omp = Get-Command oh-my-posh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($omp) {
    $cache = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-omp-cache-" + [guid]::NewGuid().ToString('N'))
    $savedCache = $env:OMP_CACHE_DIR
    try {
        $env:OMP_CACHE_DIR = $cache
        $rendered = & $omp.Source print primary --config $theme --shell pwsh 2>&1 | Out-String
        Assert-True ($LASTEXITCODE -eq 0 -and $rendered.Trim()) 'oh-my-posh renders the theme'
        $init = & $omp.Source init pwsh --config $theme --print 2>&1 | Out-String
        Assert-True ($init -match '_ompFTCSMarks = \$true' -and $init -match '_ompTransientPrompt = \$true') 'oh-my-posh enables prompt marks and the transient prompt'
    }
    finally {
        $env:OMP_CACHE_DIR = $savedCache
        Remove-Item -LiteralPath $cache -Recurse -Force -ErrorAction SilentlyContinue
    }
}
else {
    Write-Output 'SKIP: oh-my-posh not installed'
}

if ($failures.Count) {
    throw "PowerShell profile tests failed: $($failures.Count)"
}
Write-Output 'powershell-profile=PASS'
