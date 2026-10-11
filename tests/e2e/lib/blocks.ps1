#Requires -Version 7.0
# HUMAN block handling of tests/e2e/run.ps1: the parser that splits an apply
# run's output into blocks, the "HUMAN steps pending:" reader and the policy
# that says which block the harness may act on, keyed on (step id, kind) and
# failing closed. Dot-source only, after common.ps1. The policy follows
# docs/bootstrap.md "HUMAN blocks", "Running it with an agent" and "Native
# Windows": the harness stands in for the person who opens the elevated
# PowerShell for HW-stow (the runner is elevated) and leaves every other
# non-blocking Windows block to the person, since it can neither decide a
# security setting, grant a task standing elevation, start a service, install
# WSL nor sign in. HW-clone it performed and verified itself (the clone step,
# core.symlinks on), so that block pending means setup-host.ps1 did not
# accept the clone: a finding to fail on, never something to work around.

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
    # The ids of the "HUMAN steps pending: <ids>;" line setup-host.ps1 logs
    # once per run (on stdout: Write-Host), or ''.
    param([AllowEmptyCollection()][string[]]$Lines = @())
    foreach ($line in $Lines) {
        if ($line -cmatch 'HUMAN steps pending: ([^;]*);') { return $Matches[1] }
    }
    return ''
}

function Get-E2EFailureDetail {
    # What an exit 1 or 2 run said: its [error] lines, else the last line of
    # stderr, else of stdout.
    param([AllowEmptyCollection()][string[]]$Output = @(), [AllowEmptyCollection()][string[]]$Errors = @())
    $errors = @(@($Output) + @($Errors) | Where-Object { $_ -match '\[error\]' })
    if ($errors.Count) { return ConvertTo-E2EOneLine ($errors -join "`n") 400 }
    foreach ($lines in @($Errors, $Output)) {
        $kept = @($lines | Where-Object { "$_".Trim() -ne '' })
        if ($kept.Count) { return ConvertTo-E2EOneLine $kept[-1] 400 }
    }
    return 'no output'
}

function Get-E2EBlockPolicy {
    # The harness action for a block. run-stow: the HW-stow line, as the
    # person runs it from an elevated PowerShell 7. skip: a reminder for the
    # person about a non-blocking step (the execution policy, the automatic
    # stow task, the ssh-agent service, WSL, sign-in). fail: HW-clone, the
    # blocking step the clone step performed and verified itself, so pending
    # it means setup-host.ps1 did not accept the clone; and every (id, kind)
    # it does not know, a known id with another kind included.
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Kind)
    switch -CaseSensitive ("${Id}:$Kind") {
        'HW-stow:judgment' { return 'run-stow' }
        { $_ -cin @('HW-execution-policy:judgment', 'HW-auto-stow-task:judgment',
                'HW-ssh-agent:sudo', 'HW-wsl:judgment', 'HW-auth:auth') } { return 'skip' }
    }
    return 'fail'
}

function Get-E2EStowLine {
    # The one command line of an HW-stow block the harness runs: exactly
    # "& '<clone>\stow-all.ps1' win", naming the clone's own installer by its
    # full path (setup-host.ps1 prints it single-quoted, quotes doubled). Line
    # is '' with the reason in Error when the block holds anything else.
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][string]$Clone)
    $commands = @($Lines | Where-Object { $_ -ne '' -and -not $_.StartsWith('# ') })
    if ($commands.Count -ne 1) {
        return @{ Line = ''; Error = "the HW-stow block has $($commands.Count) command lines, not 1" }
    }
    $line = $commands[0]
    if ($line -cnotmatch "^& '((?:[^']|'')+)' win`$") {
        return @{ Line = ''; Error = "an HW-stow line the harness may not run: $line" }
    }
    $named = [IO.Path]::GetFullPath($Matches[1].Replace("''", "'"))
    $expected = [IO.Path]::GetFullPath((Join-Path $Clone 'stow-all.ps1'))
    if (-not $named.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
        return @{ Line = ''; Error = "the HW-stow line runs $named, not the clone's $expected" }
    }
    return @{ Line = $line; Error = '' }
}
