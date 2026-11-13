#Requires -Version 7.0
# HUMAN block handling of tests/e2e/run.ps1: the parser that splits an apply
# run's output into blocks, the "HUMAN steps pending:" reader, the policy
# that says which block the harness may act on, keyed on (step id, kind) and
# failing closed, the apply loop's verdict on one run, and the extraction of
# the docs/bootstrap.md "Fresh Windows home by hand" functions. Dot-source
# only, after common.ps1. The policy follows docs/bootstrap.md "HUMAN blocks",
# "Running it with an agent" and "Native Windows": the harness stands in for
# the person who does the HW-deploy step with the agent (its block holds
# notes only; the home-deploy step runs the documented procedure) and
# leaves every non-blocking Windows block to the person, since it can neither
# decide a security setting, start a service, install WSL nor sign in.
# HW-clone it performed and verified itself (the clone step), so that block
# pending means dotfiles.ps1 setup did not accept the clone: a finding to fail
# on, never something to work around.

function ConvertFrom-E2EBlocks {
    # The HUMAN blocks of an apply run's output lines, in order, as objects
    # with Id, Kind and Lines (those between HUMAN-BEGIN and HUMAN-END), each
    # also saved to Directory\<n>.block with an index file, the layout of
    # inside.sh. Output keeps blank lines (winget's progress leaves them),
    # which a mandatory string parameter refuses without AllowEmptyString.
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Output,
        [Parameter(Mandatory)][string]$Directory)
    [void][IO.Directory]::CreateDirectory($Directory)
    $blocks = [Collections.Generic.List[object]]::new()
    $current = $null
    foreach ($line in $Output) {
        if ($line -cmatch '^HUMAN-BEGIN ([A-Za-z0-9-]+) ([a-z]+)$') {
            $current = [pscustomobject]@{ Id = $Matches[1]; Kind = $Matches[2]; Lines = [Collections.Generic.List[string]]::new() }
            continue
        }
        if ($line -ceq 'HUMAN-END') {
            if ($null -ne $current) { $blocks.Add($current) }
            $current = $null
            continue
        }
        if ($null -ne $current) { $current.Lines.Add($line) }
    }
    $index = [Collections.Generic.List[string]]::new()
    for ($n = 1; $n -le $blocks.Count; $n++) {
        $block = $blocks[$n - 1]
        $index.Add("$n`t$($block.Id)`t$($block.Kind)")
        [IO.File]::WriteAllText((Join-Path $Directory "$n.block"), (($block.Lines -join "`n") + "`n"), $script:E2EUtf8)
    }
    [IO.File]::WriteAllText((Join-Path $Directory 'index'), (($index -join "`n") + "`n"), $script:E2EUtf8)
    return @($blocks)
}

function Get-E2EBlockText {
    # A block's lines for a detail.
    param([Parameter(Mandatory)]$Block)
    return ConvertTo-E2EOneLine ($Block.Lines -join "`n") 400
}

function Get-E2EBlocksSummary {
    # "id(kind) ..." for a detail line.
    param([AllowEmptyCollection()][object[]]$Blocks = @())
    return (@($Blocks | ForEach-Object { "$($_.Id)($($_.Kind))" }) -join ' ')
}

function Get-E2EPendingIds {
    # The ids of the "HUMAN steps pending: <ids>;" line dotfiles.ps1 setup logs
    # once per run (on stdout: Write-Host), or ''.
    param([AllowEmptyCollection()][string[]]$Lines = @())
    foreach ($line in $Lines) {
        if ($line -cmatch 'HUMAN steps pending: ([^;]*);') { return $Matches[1] }
    }
    return ''
}

function Get-E2EFailureDetail {
    # What an exit 1 or 2 run said: its [error] lines, else the last line of
    # stderr, else of stdout. (Variable names ignore case: a local $errors
    # would be the $Errors parameter.)
    param([AllowEmptyCollection()][string[]]$Output = @(), [AllowEmptyCollection()][string[]]$Errors = @())
    $flagged = @(@($Output) + @($Errors) | Where-Object { $_ -match '\[error\]' })
    if ($flagged.Count) { return ConvertTo-E2EOneLine ($flagged -join "`n") 400 }
    foreach ($lines in @($Errors, $Output)) {
        $kept = @($lines | Where-Object { "$_".Trim() -ne '' })
        if ($kept.Count) { return ConvertTo-E2EOneLine $kept[-1] 400 }
    }
    return 'no output'
}

function Get-E2EBlockPolicy {
    # The harness action for a block. deploy: HW-deploy, whose lines are
    # notes and are never run; once it alone is pending and a run applied
    # nothing, the loop ends and the home-deploy step runs Fresh Windows
    # home by hand. skip: a reminder for the person about a non-blocking step
    # (the execution policy, the ssh-agent service, WSL, sign-in). fail:
    # HW-clone, the blocking step the clone step performed and verified
    # itself, so pending it means dotfiles.ps1 setup did not accept the clone;
    # and every (id, kind) it does not know, a known id with another kind
    # included.
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Kind)
    switch -CaseSensitive ("${Id}:$Kind") {
        'HW-deploy:judgment' { return 'deploy' }
        { $_ -cin @('HW-execution-policy:judgment', 'HW-ssh-agent:sudo', 'HW-wsl:judgment', 'HW-auth:auth') } { return 'skip' }
    }
    return 'fail'
}

function Get-E2ELoopNext {
    # The apply loop's verdict on one dotfiles.ps1 setup --yes run, the table of
    # e2e_loop_next in blocks.sh with HW-deploy as the deploy step: blocks (exit
    # 3 with a block to act on), rerun (exit 3, nothing to act on, a step
    # applied), done (exit 3, nothing to act on, nothing applied, HW-deploy
    # alone pending), stuck (any other exit 3), early (exit 0, which a fresh
    # home cannot reach before its first apply), error (exit 1 or 2) or timeout.
    param([Parameter(Mandatory)][int]$Code, [AllowEmptyString()][string]$Pending = '',
        [Parameter(Mandatory)][bool]$Actionable, [Parameter(Mandatory)][bool]$Applied)
    if ($Code -eq 3) {
        if ($Actionable) { return 'blocks' }
        if ($Applied) { return 'rerun' }
        if ($Pending -ceq 'HW-deploy') { return 'done' }
        return 'stuck'
    }
    if ($Code -eq 0) { return 'early' }
    if ($Code -eq 1 -or $Code -eq 2) { return 'error' }
    return 'timeout'
}

function Get-E2EDeployScript {
    # The Fresh Windows home by hand functions of Document (the clone's
    # docs/bootstrap.md): the first ```powershell fence after a heading line
    # "#... Fresh Windows home by hand", taken from the clone instead of
    # copied here, so the test runs what the playbook prints. It must parse,
    # with no param, begin, process or clean block, and its top-level
    # statements must be exactly the definitions of Invoke-HomeCz and
    # Invoke-HomeDeploy, once each, since the deploy step runs it before
    # its one call. Returns @{ Text; Error }: the fence text, or '' and the
    # reason.
    param([Parameter(Mandatory)][string]$Document)
    $heading = 'Fresh Windows home by hand'
    $names = @('Invoke-HomeCz', 'Invoke-HomeDeploy')
    $seen = $false
    $inside = $false
    $fence = [Collections.Generic.List[string]]::new()
    foreach ($line in @([IO.File]::ReadAllText($Document) -split '\r?\n')) {
        if ($inside) {
            if ($line.StartsWith('```', [StringComparison]::Ordinal)) { break }
            $fence.Add($line)
            continue
        }
        if (-not $seen) {
            if ($line -cmatch '^#+ (.*)$' -and $Matches[1].StartsWith($heading, [StringComparison]::Ordinal)) { $seen = $true }
            continue
        }
        if ($line.StartsWith('```powershell', [StringComparison]::Ordinal)) { $inside = $true }
    }
    if ($fence.Count -eq 0) { return @{ Text = ''; Error = "no fenced powershell block after `"$heading`"" } }
    $text = ($fence -join "`n") + "`n"
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        return @{ Text = ''; Error = "the fenced powershell block does not parse: $(@($parseErrors)[0].Message)" }
    }
    $outside = "a statement outside the $($names -join ' and ') definitions in the fenced powershell block"
    $clean = $ast.PSObject.Properties['CleanBlock']
    foreach ($block in @($ast.ParamBlock, $ast.DynamicParamBlock, $ast.BeginBlock, $ast.ProcessBlock,
            $(if ($null -ne $clean) { $clean.Value } else { $null }))) {
        if ($null -ne $block) { return @{ Text = ''; Error = "${outside}: $(ConvertTo-E2EOneLine $block.Extent.Text 200)" } }
    }
    $statements = @(if ($null -ne $ast.EndBlock) { $ast.EndBlock.Statements })
    $defined = [Collections.Generic.List[string]]::new()
    foreach ($statement in $statements) {
        $isDefinition = $statement -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $names -ccontains $statement.Name -and -not $defined.Contains($statement.Name)
        if (-not $isDefinition) { return @{ Text = ''; Error = "${outside}: $(ConvertTo-E2EOneLine $statement.Extent.Text 200)" } }
        $defined.Add($statement.Name)
    }
    foreach ($name in $names) {
        if (-not $defined.Contains($name)) { return @{ Text = ''; Error = "the fenced powershell block lacks the $name definition" } }
    }
    return @{ Text = $text; Error = '' }
}
