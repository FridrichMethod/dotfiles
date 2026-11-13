#Requires -Version 7.0
# PowerShell profile and oh-my-posh theme contract. Runs with -NoProfile and
# never loads the live profile: static checks walk the AST, unit checks run
# single pieces lifted from it, and the load checks dot-source the tracked
# files in child processes with a fake HOME and the update hook disabled.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = Split-Path -Parent $PSScriptRoot
$profile7 = Join-Path $repoRoot 'home/Documents/PowerShell/profile.ps1'
$profile51 = Join-Path $repoRoot 'home/Documents/WindowsPowerShell/profile.ps1'
$theme = Join-Path $repoRoot 'home/dot_config/oh-my-posh/prompt.omp.json'
$zshrc = Join-Path $repoRoot 'home/dot_zshrc'
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
# fill up, and kills it after the timeout. Output is decoded in the console
# code page that PowerShell children write in, or in -Encoding (oh-my-posh
# writes UTF-8, and the console code page would merge its glyphs with the next
# ASCII letter).
function Invoke-Child {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [hashtable]$Environment = @{},
        [int]$TimeoutSeconds = 60,
        [System.Text.Encoding]$Encoding
    )
    $psi = [Diagnostics.ProcessStartInfo]::new($FilePath)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($Encoding) { $psi.StandardOutputEncoding = $psi.StandardErrorEncoding = $Encoding }
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
Assert-True ($tail.Contains('scripts/chezmoi-update.ps1')) 'the update hook runs the configured source''s scripts/chezmoi-update.ps1'
Assert-True (($tail -replace '\$env:DOTFILES_AUTO_UPDATE\b', '') -notmatch '(?i)\$env:') 'the update hook reads no environment variable but the DOTFILES_AUTO_UPDATE opt-out'
Assert-True ($tail -notmatch 'Import-Module|oh-my-posh|Set-PSReadLine|zoxide') 'nothing interactive runs after the update hook'

function Get-Assignments($Ast, [string]$Left) {
    @($Ast.FindAll({
                param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left.Extent.Text -eq $Left
            }.GetNewClosure(), $true))
}
function Get-IfStatements($Ast, [string]$Condition) {
    @($Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] }, $true) |
            Where-Object { ($_.Clauses[0].Item1.Extent.Text -replace '\s+', ' ').Trim() -eq $Condition })
}

# The interactive test is computed once: stdout and stdin are a console and
# the host loaded PSReadLine, which it skips for -Command/-File scripts and
# -NonInteractive but not for commands piped to stdin. Setup runs only in the
# then-branch of exactly one if on that flag and no agent terminal, and the
# update check only under the flag. Comparing whole conditions catches an
# inverted or dropped term, and the branch checks catch code moved into an
# else or elseif.
$interactiveText = '-not [Console]::IsOutputRedirected -and -not [Console]::IsInputRedirected -and (Get-Module PSReadLine)'
$interactiveFlag = Get-Assignments $parsed7.Ast '$IsInteractive'
Assert-True ($interactiveFlag.Count -eq 1 -and ($interactiveFlag[0].Right.Extent.Text -replace '\s+', ' ').Trim() -eq $interactiveText) "`$IsInteractive is assigned once: $interactiveText"
$guardText = '$IsInteractive -and -not $IsAgentSession'
$guards = Get-IfStatements $parsed7.Ast $guardText
Assert-True ($guards.Count -eq 1 -and $interactiveFlag.Count -eq 1 -and $guards[0].Extent.StartOffset -gt $interactiveFlag[0].Extent.EndOffset) "exactly one interactive guard, after the flag: if ($guardText)"
$guardBody = if ($guards.Count -eq 1) { $guards[0].Clauses[0].Item2 }
$updateCall = @(Get-Commands $parsed7.Ast | Where-Object {
        $_.InvocationOperator -eq 'Ampersand' -and $_.CommandElements[0].Extent.Text -eq '$DotfilesUpdate'
    })
$updateGate = Get-IfStatements $parsed7.Ast '$IsInteractive'
$afterGate = if ($updateGate.Count -eq 1) {
    @($parsed7.Ast.EndBlock.Statements | Where-Object { $_.Extent.StartOffset -gt $updateGate[0].Extent.StartOffset })
}
Assert-True ($updateCall.Count -eq 1 -and $updateGate.Count -eq 1 -and [object]::ReferenceEquals($updateGate[0].Parent, $parsed7.Ast.EndBlock) -and
    (Test-InsideNode $updateCall[0] $updateGate[0].Clauses[0].Item2) -and
    -not ($afterGate | Where-Object { $_ -isnot [System.Management.Automation.Language.PipelineAst] -or $_.Extent.Text -notmatch '^Remove-Variable\b' })) 'the update check runs last, only in the then-branch of if ($IsInteractive)'
# No payload hook runs at login: the payload repos install only when a person
# runs the manual triggers, which are interactive setup.
Assert-True (-not $tail.Contains('payload-update')) 'the tail runs no payload hook'
foreach ($name in 'sync-payloads', 'sync-skills') {
    $definition = @($parsed7.Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $n.Name -eq "global:$name" }.GetNewClosure(), $true))
    Assert-True ($definition.Count -eq 1 -and $guardBody -and (Test-InsideNode $definition[0] $guardBody)) "$name is defined once, in the interactive guard"
}
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
# It is assigned once, before the guard reads it, as [bool] of nothing but
# $env: variables, -or and parentheses (a constant or another cast would make
# every session an agent one).
$zshAgents = @()
if (Test-Path -LiteralPath $zshrc) {
    $zshMatch = [regex]::Match((Get-Content -LiteralPath $zshrc -Raw), '(?m)^_is_agent_session\(\)\s*\{\s*\[\[(?<body>[^\]]*)\]\]\s*\}')
    if ($zshMatch.Success) {
        $terms = @($zshMatch.Groups['body'].Value -split '\|\|')
        $names = @($terms | ForEach-Object { if ($_ -match '^\s*-n\s+"\$\{?(\w+)\}?"\s*$') { $Matches[1].ToUpperInvariant() } })
        if ($names.Count -eq $terms.Count) { $zshAgents = $names }
    }
}
Assert-True ($zshAgents.Count -gt 0) "home/dot_zshrc defines _is_agent_session as [[ -n `"`$A`" || ... ]] ($($zshAgents -join ', '))"
$psAgents = @()
$agentFlags = Get-Assignments $parsed7.Ast '$IsAgentSession'
Assert-True ($agentFlags.Count -eq 1 -and $guards.Count -eq 1 -and $agentFlags[0].Extent.EndOffset -lt $guards[0].Extent.StartOffset) "`$IsAgentSession is assigned exactly once, before the guard ($($agentFlags.Count) assignments)"
if ($agentFlags.Count -eq 1) {
    $agentValue = $agentFlags[0].Right
    if ($agentValue -is [System.Management.Automation.Language.PipelineAst] -and $agentValue.PipelineElements.Count -eq 1) { $agentValue = $agentValue.PipelineElements[0] }
    if ($agentValue -is [System.Management.Automation.Language.CommandExpressionAst]) { $agentValue = $agentValue.Expression }
    if ($agentValue -is [System.Management.Automation.Language.ConvertExpressionAst] -and
        $agentValue.Type.TypeName.GetReflectionType() -eq [bool]) {
        $nodes = @($agentValue.Child.FindAll({ $true }, $true))
        $foreign = @($nodes | Where-Object {
                -not ($_ -is [System.Management.Automation.Language.ParenExpressionAst] -or
                    $_ -is [System.Management.Automation.Language.PipelineAst] -or
                    $_ -is [System.Management.Automation.Language.CommandExpressionAst] -or
                    ($_ -is [System.Management.Automation.Language.BinaryExpressionAst] -and $_.Operator -eq 'Or') -or
                    ($_ -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.VariablePath.DriveName -eq 'env'))
            })
        if (-not $foreign) {
            $psAgents = @($nodes | Where-Object { $_ -is [System.Management.Automation.Language.VariableExpressionAst] } |
                    ForEach-Object { ($_.VariablePath.UserPath -replace '^env:', '').ToUpperInvariant() })
        }
    }
}
$sameAgents = $psAgents.Count -eq $zshAgents.Count -and
    (@($zshAgents | Sort-Object -Unique) -join ',') -eq (@($psAgents | Sort-Object -Unique) -join ',')
Assert-True ($zshAgents.Count -gt 0 -and $sameAgents) "`$IsAgentSession is [bool](`$env:$($zshAgents -join ' -or $env:')), like _is_agent_session (profile: $($psAgents -join ', '))"

# Python writes pipes in the ANSI code page unless it runs in UTF-8 mode;
# PYTHONIOENCODING would fix only its own stdout and break Python->Python
# pipes, so the profile never sets it.
$pythonUtf8 = @(Get-Assignments $parsed7.Ast '$env:PYTHONUTF8')
$pythonIo = @(Get-Assignments $parsed7.Ast '$env:PYTHONIOENCODING') + @(Get-Assignments $parsed51.Ast '$env:PYTHONIOENCODING')
Assert-True ($pythonUtf8.Count -eq 1 -and $pythonUtf8[0].Right.Extent.Text -eq "'1'" -and $guardBody -and (Test-InsideNode $pythonUtf8[0] $guardBody) -and
    $pythonIo.Count -eq 0) "interactive setup sets PYTHONUTF8=1 and nothing sets PYTHONIOENCODING ($($pythonUtf8.Count) and $($pythonIo.Count) assignments)"
if ($pythonUtf8.Count -eq 1) {
    # Only an if made of expressions is replayed here, never the guard.
    $utf8Rule = $pythonUtf8[0].Parent.Parent
    if ($utf8Rule -isnot [System.Management.Automation.Language.IfStatementAst] -or (Get-Commands $utf8Rule)) { $utf8Rule = $null }
    $savedPython = @{ PYTHONUTF8 = $env:PYTHONUTF8; PYTHONIOENCODING = $env:PYTHONIOENCODING }
    try {
        # Inherited value -> expected PYTHONUTF8: an explicit setting of
        # either variable wins.
        foreach ($case in @(@($null, $null, '1'), @('utf-8', $null, $null), @('cp936', $null, $null), @($null, '0', '0'))) {
            $env:PYTHONIOENCODING, $env:PYTHONUTF8 = $case[0], $case[1]
            if ($utf8Rule) { Invoke-Expression $utf8Rule.Extent.Text }
            Assert-True ($utf8Rule -and $env:PYTHONUTF8 -eq $case[2] -and $env:PYTHONIOENCODING -eq $case[0]) "PYTHONIOENCODING=[$($case[0])] PYTHONUTF8=[$($case[1])] -> PYTHONUTF8=[$($case[2])] (got [$env:PYTHONUTF8])"
        }
    }
    finally { $env:PYTHONIOENCODING, $env:PYTHONUTF8 = $savedPython.PYTHONIOENCODING, $savedPython.PYTHONUTF8 }
}

$importsPSReadLine = @(Get-Commands $parsed7.Ast | Where-Object {
        $_.GetCommandName() -eq 'Import-Module' -and $_.Extent.Text -match '\bPSReadLine\b'
    })
Assert-True ($importsPSReadLine.Count -eq 0) 'PSReadLine is not imported again'
$getCommand = @(Get-Commands $parsed7.Ast | Where-Object { $_.GetCommandName() -in 'Get-Command', 'gcm' })
Assert-True ($getCommand.Count -eq 0) 'optional tools are probed on PATH, not with Get-Command'
$listAvailable = @(Get-Commands $parsed7.Ast | Where-Object { $_.GetCommandName() -eq 'Get-Module' -and $_.Extent.Text -match '-ListAvailable' })
Assert-True ($listAvailable.Count -eq 0) 'optional modules are probed on PSModulePath, not with Get-Module -ListAvailable'

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

# The theme shows the conda env, so conda's own prefix is turned off, but only
# where oh-my-posh drew the prompt and only when nobody chose a value: one
# assignment, after `oh-my-posh init` in the oh-my-posh branch, inside an if
# whose condition requires $null -eq $env:CONDA_CHANGEPS1.
$changePs1 = Get-Assignments $parsed7.Ast '$env:CONDA_CHANGEPS1'
$ompBranch = Get-IfStatements $parsed7.Ast '& $HasExe oh-my-posh'
$changePs1Rule = if ($changePs1.Count -eq 1) { $changePs1[0].Parent.Parent }
$unsetTest = @()
if ($changePs1Rule -is [System.Management.Automation.Language.IfStatementAst]) {
    # The terms joined by -and at the top of the condition.
    $pending = [System.Collections.Generic.Queue[object]]::new()
    $pending.Enqueue($changePs1Rule.Clauses[0].Item1)
    $andTerms = while ($pending.Count) {
        $node = $pending.Dequeue()
        if ($node -is [System.Management.Automation.Language.PipelineAst] -and $node.PipelineElements.Count -eq 1) { $pending.Enqueue($node.PipelineElements[0]) }
        elseif ($node -is [System.Management.Automation.Language.CommandExpressionAst]) { $pending.Enqueue($node.Expression) }
        elseif ($node -is [System.Management.Automation.Language.BinaryExpressionAst] -and $node.Operator -eq 'And') { $pending.Enqueue($node.Left); $pending.Enqueue($node.Right) }
        else { $node }
    }
    $unsetTest = @($andTerms | Where-Object {
            $_ -is [System.Management.Automation.Language.BinaryExpressionAst] -and $_.Operator -eq 'Ieq' -and
            $_.Left.Extent.Text -eq '$null' -and $_.Right.Extent.Text -eq '$env:CONDA_CHANGEPS1'
        })
}
Assert-True ($changePs1.Count -eq 1 -and $changePs1[0].Right.Extent.Text -eq "'false'" -and $ompBranch.Count -eq 1 -and $ompInit.Count -eq 1 -and
    (Test-InsideNode $changePs1[0] $ompBranch[0].Clauses[0].Item2) -and $changePs1[0].Extent.StartOffset -gt $ompInit[0].Extent.EndOffset -and
    $unsetTest.Count -eq 1 -and [object]::ReferenceEquals($changePs1[0].Parent, $changePs1Rule.Clauses[0].Item2)) "CONDA_CHANGEPS1=false is set once, after oh-my-posh init and only when unset ($($changePs1.Count) assignments)"

Write-Output '--- prompt wrapper'
# zoxide's hook runs a native command after oh-my-posh restored
# $LASTEXITCODE. Replay that with stand-ins: the oh-my-posh one reads $? first
# and restores $LASTEXITCODE, the zoxide one wraps it and then clobbers it.
# The one wrapper is a statement of the guard itself, not of the zoxide
# branch, so it also runs without zoxide. After the inner prompt it writes
# the terminal mode resets of ~/.zshrc (without kitty's keyboard pop) to the
# console, captured here through [Console]::SetOut, and only where the host
# supports VT output: the replay stands in for that test with $true and
# $false.
$wrappers = @($parsed7.Ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left.Extent.Text -eq '$function:global:prompt'
        }, $true))
$wrapper = if ($wrappers.Count -eq 1) { $wrappers[0] }
Assert-True ($null -ne $wrapper -and $zoxide.Count -eq 1 -and $wrapper.Extent.StartOffset -gt $zoxide[0].Extent.StartOffset -and
    $guardBody -and [object]::ReferenceEquals($wrapper.Parent, $guardBody)) "one prompt wrapper, a statement of the interactive guard, follows zoxide init ($($wrappers.Count) wrappers)"
$vtGate = '$Host.UI.SupportsVirtualTerminal'
$zshReset = [regex]::Match([IO.File]::ReadAllText($zshrc), "print -rn -- \`$'((?:\\e\[\?[0-9]+[hl])+)'")
$expectedReset = $zshReset.Groups[1].Value.Replace('\e', [string][char]27)
Assert-True ($zshReset.Success -and $null -ne $wrapper -and
    [regex]::Matches($wrapper.Extent.Text, [regex]::Escape($vtGate)).Count -eq 1) "the wrapper tests $vtGate once and ~/.zshrc lists its mode resets"
if ($wrapper -and $zshReset.Success) {
    $console = [Console]::Out
    foreach ($vt in '$true', '$false') {
        function global:prompt { $global:OmpSawStatus = $?; $code = $global:LASTEXITCODE; 'PS> '; $global:LASTEXITCODE = $code }
        $global:__zoxide_prompt_old = $function:prompt
        function global:prompt {
            if ($null -ne $__zoxide_prompt_old) { & $__zoxide_prompt_old }
            $global:LASTEXITCODE = 0
        }
        Invoke-Expression ($wrapper.Extent.Text.Replace($vtGate, $vt))
        $written = [IO.StringWriter]::new()
        [Console]::SetOut($written)
        try {
            $global:LASTEXITCODE = 3
            Write-Error 'a failed command' -ErrorAction SilentlyContinue
            $rendered = prompt
        }
        finally { [Console]::SetOut($console) }
        Assert-True ($global:LASTEXITCODE -eq 3 -and $global:OmpSawStatus -eq $false -and $rendered -eq 'PS> ') "the prompt keeps `$LASTEXITCODE and the `$? oh-my-posh reads, VT $vt (LASTEXITCODE=$global:LASTEXITCODE, `$?=$global:OmpSawStatus)"
        $wantReset = if ($vt -eq '$true') { $expectedReset } else { '' }
        $shown = $written.ToString().Replace([string][char]27, '\e')
        Assert-True ($written.ToString() -ceq $wantReset) "the prompt writes the mode resets of ~/.zshrc only with VT, VT $vt (wrote [$shown])"
    }
    # Re-sourcing the profile wraps the wrapper; the inner prompt must come
    # from a closure, or the second wrapper calls itself until the stack ends.
    Invoke-Expression $wrapper.Extent.Text
    $global:LASTEXITCODE = 5
    [Console]::SetOut([IO.StringWriter]::new())
    try { $rendered = try { prompt } catch { "threw: $($_.Exception.Message)" } }
    finally { [Console]::SetOut($console) }
    Assert-True ($global:LASTEXITCODE -eq 5 -and $rendered -eq 'PS> ') "a second wrap neither recurses nor loses `$LASTEXITCODE (LASTEXITCODE=$global:LASTEXITCODE, prompt=$rendered)"
    Remove-Item -LiteralPath Function:\prompt
    Remove-Variable -Name __zoxide_prompt_old, OmpSawStatus -Scope Global
}

Write-Output '--- eza argument expansion'
$expandAst = Get-FunctionAst $parsed7.Ast 'Expand-EzaArgs'
Assert-True ($null -ne $expandAst) 'Expand-EzaArgs is defined'
if ($expandAst) {
    Invoke-Expression $expandAst.Extent.Text
    $globDir = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-eza-test-" + [guid]::NewGuid().ToString('N'))
    try {
        $null = New-Item -ItemType Directory -Path (Join-Path $globDir 'sub')
        foreach ($name in 'a.pyc', 'b.pyc', 'd.md', '[draft].md', '-rf.txt', 'secret.txt', 'sub/x.md', '~$lock.docx') {
            [IO.File]::WriteAllText((Join-Path $globDir $name), '')
        }
        if ($IsWindows) { [IO.File]::SetAttributes((Join-Path $globDir 'secret.txt'), 'Hidden') }
        Push-Location -LiteralPath $globDir
        $null = New-PSDrive -Name DotfilesEzaTest -PSProvider FileSystem -Root $globDir -Scope Global
        $cases = [ordered]@{
            'option values pass through'             = @('-I', '*.pyc', '--sort', 'size'), @('-I', '*.pyc', '--sort', 'size')
            'a short cluster takes the next word'    = @('-lI', '*.pyc'), @('-lI', '*.pyc')
            'an optional value is never an option'   = @('-F', '-I', '*.pyc', '--color', '--ignore-glob', '*.pyc'), @('-F', '-I', '*.pyc', '--color', '--ignore-glob', '*.pyc')
            'an optional value takes a plain word'   = @('-F', 'never', '*.md'), @('-F', 'never', 'd.md', '[draft].md')
            'an existing literal name stays'         = @(, '[draft].md'), @(, '[draft].md')
            'matches include hidden, -names guarded' = @(, '*.txt'), @((Join-Path . '-rf.txt'), 'secret.txt')
            'a relative directory stays relative'    = @(, 'sub/*.md'), @(, (Join-Path sub x.md))
            'a rooted pattern yields full paths'     = @(, (Join-Path $globDir '*.pyc')), @((Join-Path $globDir a.pyc), (Join-Path $globDir b.pyc))
            'a drive-qualified pattern is rooted'    = @(, "DotfilesEzaTest:$([IO.Path]::DirectorySeparatorChar)*.pyc"), @((Join-Path $globDir a.pyc), (Join-Path $globDir b.pyc))
            'a leading ~ is home only before a slash' = @(, '~$*'), @(, '~$lock.docx')
            'no match stays as typed'                = @(, '*.zzz'), @(, '*.zzz')
            'a quoted -- ends expansion'             = @('--', '*.md'), @('--', '*.md')
        }
        foreach ($case in $cases.GetEnumerator()) {
            $words = $case.Value[0]
            $got = @(Expand-EzaArgs @words)
            $same = (@($got | Sort-Object) -join '|') -ceq (@($case.Value[1] | Sort-Object) -join '|')
            Assert-True $same "Expand-EzaArgs: $($case.Key) ($($case.Value[0] -join ' ') -> $($got -join ' '))"
        }
    }
    finally {
        Pop-Location
        Remove-PSDrive -Name DotfilesEzaTest -Scope Global -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $globDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath Function:\Expand-EzaArgs -ErrorAction SilentlyContinue
    }
}

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

Write-Output '--- PowerShell 7.0 floor'
# The profile's floor is 7.0 (the tools.tsv pwsh row), but $PSStyle came with
# PowerShell 7.2 and the prediction options with PSReadLine 2.1 and 2.2, while
# pwsh 7.0 to 7.2 ship PSReadLine 2.0 or 2.1. Every use sits in the
# then-branch of one interactive if that detects its feature first. The
# $PSStyle statement is replayed in a runspace whose initial state lacks
# $PSStyle, as 7.0 and 7.1 do, plainly and in strict mode, and, where this
# pwsh has $PSStyle, in an ordinary one; the bare assignment replayed without
# $PSStyle must fail, or the stand-in would prove nothing. Where pwsh is
# missing, the .sh entry point still scans the profile for the same guards.
$styleGuardText = 'Get-Variable -Name PSStyle -ValueOnly -ErrorAction Ignore'
$readLineGuardText = '(Get-Module PSReadLine).Version -ge [version]''2.2.0'' -and $PSVersionTable.PSVersion -ge [System.Management.Automation.SemanticVersion]''7.2.0'''
# The USES outside the then-branch of every if in IFS, and their line numbers.
function Get-Unguarded([object[]]$Uses, [object[]]$Ifs) {
    @($Uses | Where-Object { $use = $_; -not ($Ifs | Where-Object { Test-InsideNode $use $_.Clauses[0].Item2 }) })
}
function Format-Unguarded([object[]]$Nodes) {
    if ($Nodes) { '; unguarded on line ' + (@($Nodes | ForEach-Object { $_.Extent.StartLineNumber } | Sort-Object -Unique) -join ', ') }
}
# IFS is one if with one clause and no else, inside the interactive guard.
function Test-FloorGuard([object[]]$Ifs) {
    ($Ifs.Count -eq 1 -and $Ifs[0].Clauses.Count -eq 1 -and $null -eq $Ifs[0].ElseClause -and
        $null -ne $guardBody -and (Test-InsideNode $Ifs[0] $guardBody))
}
$findStyle = {
    param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] -and
    $n.VariablePath.UserPath -match '^((global|local|script|private|variable):)?PSStyle$'
}
$styleUses = @($parsed7.Ast.FindAll($findStyle, $true))
$styleGuards = @(Get-IfStatements $parsed7.Ast $styleGuardText)
$unguardedStyle = @(Get-Unguarded $styleUses $styleGuards)
Assert-True ($styleUses.Count -gt 0 -and (Test-FloorGuard $styleGuards) -and $unguardedStyle.Count -eq 0) "every `$PSStyle use ($($styleUses.Count)) is in the then-branch of one interactive if ($styleGuardText)$(Format-Unguarded $unguardedStyle)"
Assert-True (@($parsed51.Ast.FindAll($findStyle, $true)).Count -eq 0) 'the 5.1 profile does not use $PSStyle'
# The prediction parameters and the prediction color keys of every
# Set-PSReadLineOption call.
$readLineGuards = @(Get-IfStatements $parsed7.Ast $readLineGuardText)
$predictionArgs = @(Get-Commands $parsed7.Ast | Where-Object { $_.GetCommandName() -eq 'Set-PSReadLineOption' } | ForEach-Object {
        $command = $_
        $command.CommandElements | Where-Object {
            $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -match '^Prediction'
        }
        $command.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true) |
            ForEach-Object { $_.KeyValuePairs } | ForEach-Object { $_.Item1 } |
            Where-Object { $_.Extent.Text -match '^[''"]?(Inline|List)Prediction' }
    })
$unguardedArgs = @(Get-Unguarded $predictionArgs $readLineGuards)
Assert-True ($predictionArgs.Count -gt 0 -and (Test-FloorGuard $readLineGuards) -and $unguardedArgs.Count -eq 0) "every PSReadLine 2.2 prediction option ($($predictionArgs.Count)) is in the then-branch of one interactive if ($readLineGuardText)$(Format-Unguarded $unguardedArgs)"

# Runs TEXT in a fresh runspace, without the PSStyle variable under
# -NoPSStyle, and returns its output and every error it wrote or threw.
function Invoke-FloorRunspace([string]$Text, [switch]$NoPSStyle) {
    $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    if ($NoPSStyle) { $state.Variables.Remove('PSStyle', $null) }
    $shell = [System.Management.Automation.PowerShell]::Create($state)
    try {
        $out = $errors = @()
        try { $out = @($shell.AddScript($Text).Invoke()) }
        catch { $errors += $_.Exception.Message }
        $errors += @($shell.Streams.Error | ForEach-Object { $_.ToString() })
        [pscustomobject]@{ Out = $out -join '|'; Errors = $errors -join '; ' }
    }
    finally { $shell.Dispose() }
}
$styleAssign = @(Get-Assignments $parsed7.Ast '$PSStyle.FileInfo.Directory')
$styleRule = if ($styleAssign.Count -eq 1) {
    if ($styleGuards.Count -eq 1 -and (Test-InsideNode $styleAssign[0] $styleGuards[0])) { $styleGuards[0] } else { $styleAssign[0] }
}
# Only the lookup may run as a command here, never the interactive guard.
if ($styleRule -and @(Get-Commands $styleRule | Where-Object { $_.GetCommandName() -ne 'Get-Variable' }).Count) { $styleRule = $null }
Assert-True ($null -ne $styleRule) "the directory color is set once, by a replayable statement ($($styleAssign.Count) assignments)"
if ($styleRule) {
    $probe = Invoke-FloorRunspace '[bool](Get-Variable -Name PSStyle -ErrorAction Ignore)' -NoPSStyle
    Assert-True ($probe.Out -ceq 'False' -and -not $probe.Errors) "a runspace without the PSStyle variable stands in for PowerShell 7.0 and 7.1 (out=$($probe.Out) errors=$($probe.Errors))"
    $bare = Invoke-FloorRunspace $styleAssign[0].Extent.Text -NoPSStyle
    Assert-True ([bool]$bare.Errors) 'the bare assignment fails in that runspace'
    foreach ($strict in $false, $true) {
        $prefix = if ($strict) { "Set-StrictMode -Version Latest`n" } else { '' }
        $run = Invoke-FloorRunspace ($prefix + $styleRule.Extent.Text) -NoPSStyle
        Assert-True (-not $run.Errors) "without `$PSStyle$(if ($strict) { ', in strict mode,' }) the directory color statement runs cleanly ($($run.Errors))"
    }
    if (Get-Variable -Name PSStyle -ValueOnly -ErrorAction Ignore) {
        # Runspaces share one PSStyle instance: start from a value the
        # statement does not set, and restore the original afterwards.
        $savedDirectory = $PSStyle.FileInfo.Directory
        try {
            $PSStyle.FileInfo.Directory = $PSStyle.Reset
            $run = Invoke-FloorRunspace ($styleRule.Extent.Text + "`n" + '$PSStyle.FileInfo.Directory -ceq $PSStyle.Bold + $PSStyle.Foreground.Blue')
        }
        finally { $PSStyle.FileInfo.Directory = $savedDirectory }
        Assert-True ($run.Out -ceq 'True' -and -not $run.Errors) "with `$PSStyle the statement colors directories bold blue (out=$($run.Out) errors=$($run.Errors))"
    }
    else { Write-Output 'SKIP: $PSStyle replay (this PowerShell predates 7.2)' }
}

# The profile's PSReadLine statements, replayed against stand-ins: a real
# prediction source refuses redirected output, and $PSVersionTable cannot be
# replaced, so the replay reads the engine version from $FakeEngine.
# PSReadLine 2.1 added -PredictionSource (None, History) and the
# InlinePrediction color; 2.2 added the plugin sources, -PredictionViewStyle
# and the ListPrediction colors, and a plugin source needs PowerShell 7.2.
$readLineStatements = @(if ($guardBody) {
        $guardBody.Statements | Where-Object { @(Get-Commands $_ | Where-Object { $_.GetCommandName() -eq 'Set-PSReadLineOption' }).Count }
    })
$readLineReplay = (@($readLineStatements | ForEach-Object { $_.Extent.Text }) -join "`n").Replace('$PSVersionTable.PSVersion', '$FakeEngine')
# Only the stand-ins may run as commands here.
$readLineForeign = @($readLineStatements | ForEach-Object { Get-Commands $_ } | Where-Object { $_.GetCommandName() -notin 'Set-PSReadLineOption', 'Get-Module' })
if ($readLineForeign) { $readLineReplay = '' }
Assert-True ($readLineStatements.Count -gt 0 -and -not $readLineForeign -and $readLineReplay.Contains('$FakeEngine')) "the PSReadLine options are set by $($readLineStatements.Count) replayable statements that test the engine version"
$readLineStandIn = @'
function Get-Module { [pscustomobject]@{ Name = 'PSReadLine'; Version = $FakeReadLine } }
function Set-PSReadLineOption {
    [CmdletBinding()]
    param($BellStyle, [switch]$HistorySearchCursorMovesToEnd, [hashtable]$Colors, $AddToHistoryHandler, $PredictionSource, $PredictionViewStyle)
    $since = @{ PredictionSource = '2.1.0'; InlinePrediction = '2.1.0'; PredictionViewStyle = '2.2.0'; ListPrediction = '2.2.0'; Plugin = '2.2.0' }
    $used = @($PSBoundParameters.Keys) + @(if ($Colors) { $Colors.Keys -replace '^ListPrediction.*', 'ListPrediction' })
    if ("$PredictionSource" -like '*Plugin') { $used += 'Plugin' }
    foreach ($name in $used) {
        if ($since.ContainsKey($name) -and $FakeReadLine -lt [System.Version]$since[$name]) { throw "PSReadLine $FakeReadLine has no $name" }
    }
    if ($used -contains 'Plugin' -and $FakeEngine -lt [System.Management.Automation.SemanticVersion]'7.2.0') {
        throw "a plugin prediction source needs PowerShell 7.2, not $FakeEngine"
    }
    foreach ($name in $PSBoundParameters.Keys) { $Bound.Add($name) }
}
'@
# PSReadLine, PowerShell, whether the predictions apply: the stock pairs of
# 7.0, 7.1 and 7.2, PSReadLine 2.2 installed on 7.1, and the supported pairs.
foreach ($floorCase in @(
        @('2.0.0', '7.0.0', $false), @('2.1.0', '7.1.0', $false), @('2.1.0', '7.2.0', $false),
        @('2.2.0', '7.1.0', $false), @('2.2.0', '7.2.0', $true), @('2.3.6', '7.4.6', $true))) {
    $prelude = "`$FakeReadLine = [System.Version]'$($floorCase[0])'`n`$FakeEngine = [System.Management.Automation.SemanticVersion]'$($floorCase[1])'`n" +
        "`$Bound = [System.Collections.Generic.List[string]]::new()`n"
    $run = if ($readLineReplay) { Invoke-FloorRunspace ($prelude + $readLineStandIn + "`n" + $readLineReplay + "`n" + '"bound=" + ($Bound -join ",")') }
    $names = if ($run) { @(($run.Out -replace '^bound=', '') -split ',') } else { @() }
    $predicts = $names -contains 'PredictionViewStyle'
    Assert-True ($run -and -not $run.Errors -and $run.Out -like 'bound=*' -and $names -contains 'BellStyle' -and $predicts -eq $floorCase[2]) "PSReadLine $($floorCase[0]) on PowerShell $($floorCase[1]) takes the profile's options$(if ($floorCase[2]) { ' with' } else { ' without' }) predictions (out=$($run.Out) errors=$($run.Errors))"
}
Remove-Item -LiteralPath Function:\Invoke-FloorRunspace, Function:\Get-Unguarded, Function:\Format-Unguarded, Function:\Test-FloorGuard

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
try { conda --version } catch { }
"after-failed-hook=$((Get-Command conda).CommandType)"
'@
        $result = Invoke-Child $windowsPowerShell @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', $child51) -Environment @{
            PSModulePath = $null; DOTFILES_TEST_PROFILE = $profile51; DOTFILES_TEST_HOME = $fakeHome51
        }
        $expected = "parse-errors=0`nconda=Function`nsubcommand=info`nenv=demo`nafter-failed-hook=Function"
        Assert-True (-not $result.TimedOut -and $result.ExitCode -eq 0 -and ($result.Out -replace "`r", '') -eq $expected -and -not $result.Err) "the 5.1 profile parses, completes conda and keeps the stub after a failed hook under Windows PowerShell (exit=$($result.ExitCode) out=$($result.Out -replace '\s+', ' ') err=$($result.Err))"
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
    # Token-shaped strings are assembled at run time so no scanner flags them.
    $memoryOnly = @(
            'curl -H "Authorization: Bearer abc123def456ghi" https://example.org',
            ('echo ghp_' + ('a' * 24)),
            ('gh auth login --with-token github_pat_' + ('A1b' * 8)),
            ('$env:ANTHROPIC_API_KEY = "sk-ant-' + 'api03-' + ('x' * 48) + '"'),
            ('echo sk-proj-' + ('Ab1' * 16)),
            ('echo sk-' + ('aB3' * 12)),
            ('setx OPENAI_API_KEY sk-svcacct-' + ('aB3_' * 12)),
            ("[Environment]::SetEnvironmentVariable('OPENAI_API_KEY', 'sk-admin-" + ('aB3-' * 12) + "', 'User')"),
            ('setx OPENAI_API_KEY sk-None-' + ('aB3' * 16)),
            ('python run.py --api-key sk-or-v1-' + ('0123456789abcdef' * 4)),
            ('codex login --api-key sk-' + ('aB3' * 4) + 'T3Blbk' + 'FJ' + ('aB3' * 4)),
            ('echo sk-next-' + ('aB3' * 25) + 'T3Blbk' + 'FJ' + ('aB3' * 25)),
            ('huggingface-cli login --token hf_' + ('aB' * 12)),
            ('aws configure set aws_access_key_id AKIA' + ('ABCD2345' * 2)),
            ('curl -d token=xoxb-' + ('12345-' * 3) + 'abc https://slack.com/api'),
            ('echo "-----BEGIN ' + 'OPENSSH PRIVATE KEY-----"'),
            'git clone https://user:pass@example.org/repo.git',
            '$env:GITHUB_TOKEN = "abc"',
            '$env:HF_TOKEN = "abc"',
            '$env:AWS_SECRET_ACCESS_KEY = "abc"',
            '$env:GH_PAT = "abc"',
            ' echo kept in memory only',
            # ASCII I/i differs under Turkish and Azerbaijani cultures.
            ('echo GITHUB_PAT_' + ('A1b' * 8)),
            ('echo akia' + ('abcd2345' * 2)),
            ('echo "-----begin rsa ' + 'private key-----"'),
            '$ENV:BUILD_API_KEY = "fixture"',
            ('echo SK-admin-' + ('aB3-' * 12)))
    $memoryAndFile = @(
            'git push',
            '$env:CUDA_PATH = "C:\cuda\v12.4"',
            '$env:LD_LIBRARY_PATH = "/opt/lib"',
            '$env:CMAKE_PREFIX_PATH = "C:\deps"',
            '$env:PKG_CONFIG_PATH = "C:\deps\lib\pkgconfig"',
            '$env:PATH = "C:\tools;" + $env:PATH',
            'git commit -m "Add bearer authentication"',
            'git checkout sk-refactor-dataloader-v2',
            # Too short for an admin key; a key's None prefix is capitalized.
            'git checkout -b sk-admin-tools',
            'git checkout -b sk-admin-dashboard-cleanup-v2',
            'git switch sk-none-fix-for-flaky-tests',
            '$env:API_KEYBOARD = "fixture"',
            '$env:MYAPI_KEY = "fixture"',
            ('echo mygithub_pat_' + ('A1b' * 8)),
            ('echo xakia' + ('abcd2345' * 2)),
            ('echo github_pat_' + ('a' * 19)))
    # Vendor subpatterns are intentionally case-sensitive; use hyphenated
    # bodies so the independent unbroken-key rule cannot hide a regression.
    foreach ($vendor in 'ant', 'proj', 'svcacct', 'admin', 'None', 'or-v1') {
        $memoryOnly += 'echo sk-' + $vendor + '-' + ('aB3-' * 12)
    }
    foreach ($vendor in 'ANT', 'PROJ', 'SVCACCT', 'admIn', 'none', 'OR-V1') {
        $memoryAndFile += 'echo sk-' + $vendor + '-' + ('aB3-' * 12)
    }
    # -match caches compiled regexes without including culture in its key.
    # A fresh child per culture ensures the first match uses that culture.
    $historyHome = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-history-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $historyHome)
    $lines = @($memoryOnly) + @($memoryAndFile)
    $linesJson = ConvertTo-Json -InputObject $lines -Compress
    try {
        foreach ($cultureName in 'en-US', 'tr-TR', 'az-Latn-AZ') {
            $probe = '$ErrorActionPreference = ''Stop''' + "`n" +
                '$culture = [Globalization.CultureInfo]::GetCultureInfo(''' + $cultureName + ''')' + "`n" +
                '[Threading.Thread]::CurrentThread.CurrentCulture = $culture' + "`n" +
                '[Threading.Thread]::CurrentThread.CurrentUICulture = $culture' + "`n" +
                'Import-Module PSReadLine -ErrorAction Stop' + "`n" +
                '$handler = [scriptblock]::Create(''' + $handler.ToString().Replace("'", "''") + ''')' + "`n" +
                '$lines = ConvertFrom-Json -InputObject ''' + $linesJson.Replace("'", "''") + "'`n" +
                '[Threading.Thread]::CurrentThread.CurrentCulture.Name' + "`n" +
                'foreach ($line in $lines) { [string](& $handler $line) }'
            $result = Invoke-Child -FilePath $powerShell -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand',
                [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probe))) -Environment @{
                HOME = $historyHome; USERPROFILE = $historyHome
                XDG_CONFIG_HOME = $historyHome; XDG_DATA_HOME = $historyHome; XDG_CACHE_HOME = $historyHome
            }
            Assert-True (-not $result.TimedOut -and $result.ExitCode -eq 0 -and -not $result.Err) "history ($cultureName) isolated child succeeds: $($result.Err)"
            $verdicts = @($result.Out -split '\r?\n')
            Assert-True ($verdicts.Count -eq $lines.Count + 1 -and $verdicts[0] -ceq $cultureName) "history child sets $cultureName and returns every verdict"
            for ($index = 0; $index -lt $lines.Count; $index++) {
                $expected = if ($index -lt $memoryOnly.Count) { 'MemoryOnly' } else { 'MemoryAndFile' }
                Assert-True ($verdicts[$index + 1] -ceq $expected) "history ($cultureName) $expected`: $($lines[$index])"
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $historyHome -Recurse -Force -ErrorAction SilentlyContinue
    }
    # The handler runs on Enter. With an unbounded gap before the T3BlbkFJ
    # marker, one run of many sk- starts backtracked quadratically: this line
    # took about 4 s, the bounded gap tens of milliseconds.
    $runLine = 'echo ' + ('sk-' * 20000)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $runResult = & $handler $runLine
    $sw.Stop()
    Assert-True ($runResult -eq [Microsoft.PowerShell.AddToHistoryOption]::MemoryAndFile -and $sw.ElapsedMilliseconds -lt 500) "history filter takes $($sw.ElapsedMilliseconds) ms (< 500) for a $($runLine.Length)-character run of sk-"
}
else {
    Write-Output 'SKIP: PSReadLine unavailable'
}

Write-Output '--- payload commands follow the home chezmoi config'
# sync-payloads and sync-skills, lifted into a child with a fake HOME, run the
# hook of the source a valid ~/.config/chezmoi/chezmoi.toml names (never the
# checkout at ~\dotfiles or its guard) and pass its exit status through; a
# home without a config and a config the guard refuses run no hook;
# maintenance surfaces the configured hook's own refusal.
$syncRoot = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-payload-commands-test-" + [guid]::NewGuid().ToString('N'))
try {
    $syncHome = Join-Path $syncRoot 'home'
    $configured = Join-Path $syncRoot 'configured source'
    $other = Join-Path $syncHome 'dotfiles'
    $syncTrace = Join-Path $syncRoot 'trace'
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $syncHome '.config/dotfiles'), (Join-Path $syncHome '.config/chezmoi'), (Join-Path $syncHome '.local/bin'),
        (Join-Path $configured 'scripts'), (Join-Path $configured 'lib'), (Join-Path $configured '.git'), (Join-Path $other 'scripts'), (Join-Path $other 'lib')
    [IO.File]::WriteAllText((Join-Path $configured '.chezmoiroot'), "home`n")
    Copy-Item -LiteralPath (Join-Path $repoRoot 'lib/chezmoi-guard.ps1') -Destination (Join-Path $configured 'lib/chezmoi-guard.ps1')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'dotfiles.ps1') -Destination (Join-Path $configured 'dotfiles.ps1')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'home/dot_local/bin/dotfiles.ps1') -Destination (Join-Path $syncHome '.local/bin/dotfiles.ps1')
    foreach ($checkout in @{ Path = $configured; Name = 'configured' }, @{ Path = $other; Name = 'other' }) {
        [IO.File]::WriteAllText((Join-Path $checkout.Path 'scripts/payload-update.ps1'),
            "param([switch]`$Now, [string[]]`$Item)`nif (-not `$Now) { throw 'Missing Now.' }`nAdd-Content -LiteralPath `$env:DOTFILES_TEST_TRACE -Value ('$($checkout.Name) -Now ' + (`$Item -join ' '))`nexit 4`n")
    }
    [IO.File]::WriteAllText((Join-Path $other 'lib/chezmoi-guard.ps1'), "Add-Content -LiteralPath `$env:DOTFILES_TEST_TRACE -Value 'other-guard'`n")
    # The form chezmoi init writes: on Windows forward slashes and an
    # upper-case drive; elsewhere the canonical path (/var is /private/var on
    # macOS), as the guard compares them.
    $forms = & {
        . (Join-Path $repoRoot 'lib/chezmoi-guard.ps1')
        foreach ($path in $args) {
            $resolved = Resolve-DotfilesDirectory $path
            if ($IsWindows) { $resolved = $resolved.Replace('\', '/'); $resolved = $resolved.Substring(0, 1).ToUpperInvariant() + $resolved.Substring(1) }
            $resolved
        }
    } $syncHome $configured $syncRoot
    $syncConfig = Join-Path $syncHome '.config/chezmoi/chezmoi.toml'
    $sourceLine = "sourceDir = `"$($forms[1])`""
    $valid = "destDir = `"$($forms[0])`"`n$sourceLine`n`n[data]`n  host = 'win'`n"
    $syncChild = @'
Set-Variable -Name HOME -Value $env:DOTFILES_TEST_HOME -Force -Scope Global
$ast = [Management.Automation.Language.Parser]::ParseFile($env:DOTFILES_TEST_PROFILE, [ref]$null, [ref]$null)
foreach ($name in 'sync-payloads', 'sync-skills') {
    Invoke-Expression $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $n.Name -eq "global:$name" }.GetNewClosure(), $true).Extent.Text
}
$global:LASTEXITCODE = 7; sync-payloads pymol; $first = $LASTEXITCODE
$global:LASTEXITCODE = 7; sync-skills ignored; "exit=$first,$LASTEXITCODE"
'@
    # Invoke-SyncCase PREPARE: a fresh trace and config, PREPARE, one child run.
    function Invoke-SyncCase([scriptblock]$Prepare) {
        # A linked config goes as a link (dangling ones too), never its target.
        try { if ([IO.File]::GetAttributes($syncConfig) -band [IO.FileAttributes]::ReparsePoint) { [IO.File]::Delete($syncConfig) } } catch { }
        Remove-Item -LiteralPath $syncTrace, $syncConfig -Recurse -Force -ErrorAction Ignore
        & $Prepare
        $run = Invoke-Child $powerShell @('-NoProfile', '-NonInteractive', '-Command', $syncChild) -Environment @{
            DOTFILES_TEST_HOME = $syncHome; DOTFILES_TEST_PROFILE = $profile7; DOTFILES_TEST_TRACE = $syncTrace
        }
        $events = if (Test-Path -LiteralPath $syncTrace) { @(Get-Content -LiteralPath $syncTrace) -join '|' } else { '' }
        [pscustomobject]@{ Out = $run.Out; Err = $run.Err; Events = $events; Text = "out=$($run.Out) err=$($run.Err) events=$events" }
    }
    $refused = 'dotfiles: ~/.config/chezmoi/chezmoi.toml must name this home and an available dotfiles checkout; run & CHECKOUT\dotfiles.ps1 explicitly to recover.'
    $case = Invoke-SyncCase { [IO.File]::WriteAllText($syncConfig, $valid) }
    Assert-True ($case.Events -ceq 'configured -Now pymol|configured -Now skills' -and $case.Out -ceq 'exit=4,4' -and -not $case.Err) "a valid config runs its source's hook, not ~\dotfiles's ($($case.Text))"
    $case = Invoke-SyncCase { }
    Assert-True ($case.Events -ceq '' -and $case.Out -ceq 'exit=1,1' -and $case.Err.Contains($refused)) "a home without a config refuses and runs no hook, not even ~\dotfiles's ($($case.Text))"
    $invalid = [ordered]@{
        'two sourceDir lines' = { [IO.File]::WriteAllText($syncConfig, $valid.Replace($sourceLine, "$sourceLine`n$sourceLine")) }
        'a literal string'    = { [IO.File]::WriteAllText($syncConfig, $valid.Replace($sourceLine, $sourceLine.Replace('"', "'"))) }
        'CRLF'                = { [IO.File]::WriteAllText($syncConfig, $valid.Replace("`n", "`r`n")) }
        'relative source'     = { [IO.File]::WriteAllText($syncConfig, $valid.Replace($sourceLine, 'sourceDir = "dotfiles"')) }
        'other home'          = { [IO.File]::WriteAllText($syncConfig, $valid.Replace("destDir = `"$($forms[0])`"", "destDir = `"$($forms[2])`"")) }
        'a workingTree key'   = { [IO.File]::WriteAllText($syncConfig, $valid.Replace($sourceLine, "$sourceLine`n$($sourceLine.Replace('sourceDir', 'workingTree'))")) }
        'directory'           = { $null = New-Item -ItemType Directory -Path $syncConfig }
    }
    # A config that is a link, dangling or to a valid config, refuses too and
    # never falls back to ~\dotfiles. A symbolic link on Windows needs
    # elevation or Developer Mode (hosted runners are elevated).
    $validCopy = Join-Path $syncRoot 'valid config'
    [IO.File]::WriteAllText($validCopy, $valid)
    $linkProbe = Join-Path $syncRoot 'link probe'
    try { $null = New-Item -ItemType SymbolicLink -Path $linkProbe -Target $validCopy -ErrorAction Stop; [IO.File]::Delete($linkProbe) }
    catch { $linkProbe = $null }
    if ($linkProbe) {
        $gone = Join-Path $syncRoot 'removed config'
        $invalid['dangling link'] = {
            [IO.File]::WriteAllText($gone, $valid)
            $null = New-Item -ItemType SymbolicLink -Path $syncConfig -Target $gone
            [IO.File]::Delete($gone)
        }
        $invalid['link to a valid config'] = { $null = New-Item -ItemType SymbolicLink -Path $syncConfig -Target $validCopy }
    }
    else { Write-Output 'SKIP: linked sync-payloads configs (cannot create a symbolic link here)' }
    foreach ($entry in $invalid.GetEnumerator()) {
        $case = Invoke-SyncCase $entry.Value
        Assert-True ($case.Events -ceq '' -and $case.Out -ceq 'exit=1,1' -and $case.Err.Contains($refused)) "an invalid config ($($entry.Key)) refuses without running a hook ($($case.Text))"
    }
    # A valid config whose source has no guard refuses as well.
    $sourceGuard = Join-Path $configured 'lib/chezmoi-guard.ps1'
    Move-Item -LiteralPath $sourceGuard -Destination "$sourceGuard.hidden"
    try { $case = Invoke-SyncCase { [IO.File]::WriteAllText($syncConfig, $valid) } }
    finally { Move-Item -LiteralPath "$sourceGuard.hidden" -Destination $sourceGuard }
    Assert-True ($case.Events -ceq '' -and $case.Out -ceq 'exit=1,1' -and $case.Err.Contains($refused)) "a configured source without its guard refuses without running a hook ($($case.Text))"
    # A configured source without the hook fails with one line and exit 1, not
    # a leftover 0.
    $hookPath = Join-Path $configured 'scripts/payload-update.ps1'
    Move-Item -LiteralPath $hookPath -Destination "$hookPath.hidden"
    try { $case = Invoke-SyncCase { [IO.File]::WriteAllText($syncConfig, $valid) } }
    finally { Move-Item -LiteralPath "$hookPath.hidden" -Destination $hookPath }
    Assert-True ($case.Events -ceq '' -and $case.Out -ceq 'exit=1,1' -and $case.Err.Contains('payload-update.ps1') -and
        -not $case.Err.Contains('CommandNotFound')) "a configured source without the hook fails with exit 1 ($($case.Text))"
    $launcherPath = Join-Path $syncHome '.local/bin/dotfiles.ps1'
    Move-Item -LiteralPath $launcherPath -Destination "$launcherPath.hidden"
    try { $case = Invoke-SyncCase { [IO.File]::WriteAllText($syncConfig, $valid) } }
    finally { Move-Item -LiteralPath "$launcherPath.hidden" -Destination $launcherPath }
    Assert-True ($case.Events -ceq '' -and $case.Out -ceq 'exit=1,1' -and $case.Err.Contains('missing ~/.local/bin/dotfiles.ps1')) "missing launcher refuses without the old backend fallback ($($case.Text))"
    # A hook that ends without exit leaves no stale exit status behind.
    [IO.File]::WriteAllText((Join-Path $configured 'scripts/payload-update.ps1'), "Add-Content -LiteralPath `$env:DOTFILES_TEST_TRACE -Value 'quiet'`n")
    $case = Invoke-SyncCase { [IO.File]::WriteAllText($syncConfig, $valid) }
    Assert-True ($case.Events -ceq 'quiet|quiet' -and $case.Out -ceq 'exit=0,0') "a hook without exit reports 0, not the caller's last status ($($case.Text))"
    # The real hook's maintenance refusal.
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/payload-update.ps1') -Destination (Join-Path $configured 'scripts/payload-update.ps1') -Force
    $case = Invoke-SyncCase { [IO.File]::WriteAllText($syncConfig, $valid); [IO.File]::WriteAllText((Join-Path $syncHome '.config/dotfiles/maintenance'), '') }
    Assert-True ($case.Events -ceq '' -and $case.Out.EndsWith('exit=1,1') -and ($case.Out + $case.Err).Contains('payload update refused during maintenance')) "maintenance surfaces the configured hook's refusal ($($case.Text))"
    Remove-Item -LiteralPath (Join-Path $syncHome '.config/dotfiles/maintenance') -Force
}
finally {
    Remove-Item -LiteralPath $syncRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath Function:\Invoke-SyncCase -ErrorAction SilentlyContinue
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
    # The fake conda.exe cannot run, so the hook fails; the stub must come back.
    try { conda --version } catch { }
    if ((Get-Command conda).CommandType -ne 'Function') { throw 'a failed conda hook left no stub behind' }
}
'PASS'
'@
    $result = Invoke-Child $powerShell @('-NoProfile', '-NonInteractive', '-Command', $child) -Environment @{
        DOTFILES_AUTO_UPDATE = '0'
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
    # An inherited POSH_SESSION_ID makes oh-my-posh render that session's
    # cached config instead of --config, and an OMP_CACHE_DIR that does not
    # exist falls back to the user's own cache. Each call therefore gets no
    # POSH_* session and a cache directory that exists and is deleted after.
    $ompDir = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-omp-test-" + [guid]::NewGuid().ToString('N'))
    $ompEnv = @{ OMP_CACHE_DIR = Join-Path $ompDir 'cache' }
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    Get-ChildItem Env: | Where-Object Name -like 'POSH_*' | ForEach-Object { $ompEnv[$_.Name] = $null }
    # A broken theme still exits 0 and prints a prompt; the error text that
    # replaces the failed part is what gives it away.
    $renderError = 'CONFIG PARSE ERROR|CONFIG ERROR|invalid template text|unable to create text based on template'
    $render = {
        param([string]$Config, [string]$Kind)
        Invoke-Child $omp.Source @('print', $Kind, '--config', $Config, '--shell', 'pwsh', '--plain') -Environment $ompEnv -Encoding $utf8
    }
    try {
        $null = New-Item -ItemType Directory -Path $ompEnv.OMP_CACHE_DIR
        foreach ($kind in 'primary', 'transient', 'secondary') {
            $result = & $render $theme $kind
            Assert-True (-not $result.TimedOut -and $result.ExitCode -eq 0 -and $result.Out -and $result.Out -notmatch $renderError -and -not $result.Err) "oh-my-posh renders the $kind prompt without errors"
        }
        # The render check itself must notice a broken segment template.
        $broken = Get-Content -LiteralPath $theme -Raw | ConvertFrom-Json -AsHashtable
        $broken.blocks[0].segments[0].template = '{{ .NoSuchField }}'
        $brokenTheme = Join-Path $ompDir 'broken.omp.json'
        [IO.File]::WriteAllText($brokenTheme, ($broken | ConvertTo-Json -Depth 64))
        Assert-True ((& $render $brokenTheme 'primary').Out -match $renderError) 'the render check catches a broken template'
        $init = Invoke-Child $omp.Source @('init', 'pwsh', '--config', $theme, '--print') -Environment $ompEnv -Encoding $utf8
        Assert-True ($init.Out -match '_ompFTCSMarks = \$true' -and $init.Out -match '_ompTransientPrompt = \$true') 'oh-my-posh enables prompt marks and the transient prompt'
    }
    finally {
        Remove-Item -LiteralPath $ompDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
else {
    Write-Output 'SKIP: oh-my-posh not installed'
}

if ($failures.Count) {
    throw "PowerShell profile tests failed: $($failures.Count)"
}
Write-Output 'powershell-profile=PASS'
