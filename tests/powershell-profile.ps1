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
$powerShell = (Get-Process -Id $PID).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) { Write-Output "ok: $Message" }
    else {
        Write-Output "FAIL: $Message"
        $failures.Add($Message)
    }
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

# True when $Node sits inside the interactive guard: an `if` whose condition
# tests both redirected stdout and the agent-session flag.
function Test-InsideConsoleGuard($Node) {
    for ($p = $Node.Parent; $p; $p = $p.Parent) {
        if ($p -is [System.Management.Automation.Language.IfStatementAst]) {
            $condition = $p.Clauses[0].Item1.Extent.Text
            if ($condition -match 'IsOutputRedirected' -and $condition -match 'IsAgentSession') { return $true }
        }
    }
    $false
}

function Test-InsideFunction($Node, [string]$Name) {
    for ($p = $Node.Parent; $p; $p = $p.Parent) {
        if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            ($p.Name -replace '^global:', '') -eq $Name) { return $true }
    }
    $false
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

$guarded = @(Get-Commands $parsed7.Ast | Where-Object {
        $name = $_.GetCommandName()
        $name -in 'Set-PSReadLineOption', 'Set-PSReadLineKeyHandler', 'Register-EngineEvent', 'oh-my-posh', 'zoxide' -or
        ($name -eq 'Import-Module' -and $_.Extent.Text -match 'CompletionPredictor|Microsoft\.WinGet\.CommandNotFound|PSFzf')
    })
Assert-True ($guarded.Count -ge 8) "found the interactive commands ($($guarded.Count))"
$outside = @($guarded | Where-Object { -not (Test-InsideConsoleGuard $_) })
Assert-True ($outside.Count -eq 0) "interactive setup stays inside the console and agent guard$(if ($outside) { ': ' + (($outside | ForEach-Object { $_.Extent.Text.Split("`n")[0] }) -join ' | ') })"
$agentFlag = $parsed7.Ast.FindAll({
        param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left.Extent.Text -eq '$IsAgentSession'
    }, $true) | Select-Object -First 1
Assert-True ($null -ne $agentFlag -and $agentFlag.Right.Extent.Text -match 'CURSOR_AGENT' -and
    $agentFlag.Right.Extent.Text -match 'GEMINI_CLI') 'agent sessions mirror _is_agent_session (CURSOR_AGENT, GEMINI_CLI)'
$importsPSReadLine = @(Get-Commands $parsed7.Ast | Where-Object {
        $_.GetCommandName() -eq 'Import-Module' -and $_.Extent.Text -match '\bPSReadLine\b'
    })
Assert-True ($importsPSReadLine.Count -eq 0) 'PSReadLine is not imported again'

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
    $hooks = @(Get-Commands $parsed.Ast | Where-Object { $_.Extent.Text -match 'shell\.powershell' })
    Assert-True ($hooks.Count -ge 1 -and -not ($hooks | Where-Object { -not (Test-InsideFunction $_ 'conda') })) "$($parsed.Ast.Extent.File) runs the conda hook only from the conda stub"
}

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
    # Windows PowerShell cannot load modules from the pwsh 7 module path it
    # would inherit, so start it with that variable removed.
    $psi = [Diagnostics.ProcessStartInfo]::new($windowsPowerShell)
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $null = $psi.Environment.Remove('PSModulePath')
    $script = "`$t = `$e = `$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$profile51', [ref]`$t, [ref]`$e); `$e.Count"
    foreach ($a in '-NoProfile', '-NonInteractive', '-Command', $script) { $psi.ArgumentList.Add($a) }
    $process = [Diagnostics.Process]::Start($psi)
    $out = $process.StandardOutput.ReadToEnd().Trim()
    $process.WaitForExit()
    Assert-True ($process.ExitCode -eq 0 -and $out -eq '0') "the 5.1 profile parses under Windows PowerShell (errors: $out)"
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
Set-Variable -Name HOME -Value '__HOME__' -Force -Scope Global
$promptBefore = (Get-Command prompt).ScriptBlock.ToString()
$before = @((Get-Variable).Name)
$sw = [Diagnostics.Stopwatch]::StartNew()
. '__PROFILE__'
$sw.Stop()
$leaked = @((Get-Variable).Name | Where-Object { $_ -notin $before -and $_ -notin 'before', 'sw', 'promptBefore' })
if ($sw.Elapsed.TotalSeconds -ge 5) { throw "profile load took $($sw.Elapsed.TotalSeconds) s" }
if ($leaked) { throw "profile leaked globals: $($leaked -join ', ')" }
if ((Get-Command prompt).ScriptBlock.ToString() -ne $promptBefore) { throw 'redirected load changed the prompt' }
if ($env:CONDA_CHANGEPS1 -ne 'false') { throw "CONDA_CHANGEPS1 is '$env:CONDA_CHANGEPS1'" }
if ($IsWindows) {
    if ((Get-Command conda).CommandType -ne 'Function') { throw 'conda is not the lazy stub' }
    $completion = (TabExpansion2 'conda activate de' 17).CompletionMatches.CompletionText
    if ('demo' -notin $completion) { throw "conda completion offered: $($completion -join ', ')" }
}
'PASS'
'@
    $child = $child.Replace('__HOME__', $fakeHome.Replace("'", "''")).Replace('__PROFILE__', $profile7.Replace("'", "''"))
    $psi = [Diagnostics.ProcessStartInfo]::new($powerShell)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Environment['DOTFILES_AUTO_UPDATE'] = '0'
    $psi.Environment['DOTFILES_DIR'] = Join-Path $fakeHome 'no-dotfiles'
    $null = $psi.Environment.Remove('CONDA_CHANGEPS1')
    foreach ($a in '-NoProfile', '-NonInteractive', '-Command', $child) { $psi.ArgumentList.Add($a) }
    $process = [Diagnostics.Process]::Start($psi)
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(60000)) {
        $process.Kill($true)
        Assert-True $false 'redirected profile load finished within 60 s'
    }
    else {
        $out = $stdout.GetAwaiter().GetResult().Trim()
        $err = $stderr.GetAwaiter().GetResult().Trim()
        Assert-True ($process.ExitCode -eq 0 -and $out -eq 'PASS' -and -not $err) "redirected load is fast, silent and leaves the prompt alone (exit=$($process.ExitCode) out=$out err=$err)"
    }
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
