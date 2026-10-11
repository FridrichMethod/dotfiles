#Requires -Version 7.0
# The flow of tests/e2e/run.ps1: the setup-host.ps1 -Yes loop with its HUMAN
# blocks, and the whole sequence: clone, winget, doctor-initial, the no-write
# -Check, the apply loop, the second apply, the profile load and the final
# doctor: docs/bootstrap.md "Native Windows", driven the way "Running it with
# an agent" says an agent drives it. Dot-source only, after steps.ps1.

# The child command for a block line: the line reaches it through the
# environment, so no quoting of the harness changes what runs, and
# Invoke-Expression runs it as the person's elevated PowerShell 7 would. A
# throw in stow-all.ps1 ends the child with exit 1.
$script:E2EInvokeCommand = 'Invoke-Expression -Command $env:E2E_BLOCK_LINE'

function Test-E2EStowed {
    # HW-stow's verify: ~\.gitconfig is a symlink to the clone's common copy.
    # Done, plus a Detail for the row.
    $link = Get-Item -LiteralPath (Join-Path $HOME '.gitconfig') -Force -ErrorAction SilentlyContinue
    if ($null -eq $link) { return @{ Done = $false; Detail = '~\.gitconfig is missing' } }
    if ([string]$link.LinkType -cne 'SymbolicLink') {
        return @{ Done = $false; Detail = "~\.gitconfig is a regular file ($($link.Length) bytes), not a symlink" }
    }
    $target = Get-E2ELinkTarget $link
    if (-not [IO.Path]::IsPathRooted($target)) { $target = Join-Path $HOME $target }
    $expected = [IO.Path]::GetFullPath((Join-Path $E2E['Clone'] 'common/git/.gitconfig'))
    $done = [IO.Path]::GetFullPath($target).Equals($expected, [StringComparison]::OrdinalIgnoreCase)
    $detail = if ($done) { "~\.gitconfig -> $target" } else { "~\.gitconfig -> $target, not the clone's $expected" }
    return @{ Done = $done; Detail = $detail }
}

function Invoke-E2EStowBlock {
    # Run the HW-stow block's one line as the person would from an elevated
    # PowerShell 7 (Invoke-Expression in a child pwsh -NoProfile
    # -NonInteractive, in HOME), then HW-stow's verify. A WARNING line of
    # stow-all.ps1 is a note, not a failure, as inside.sh judges stow-all.sh
    # by its exit code alone.
    param([Parameter(Mandatory)]$Block, [Parameter(Mandatory)][string]$Line)
    Start-E2EStep $Block.Id "human:$($Block.Id)"
    Add-E2EText $E2E['StepLog'] ("--- block`n" + ($Block.Lines -join "`n") + "`n")
    $code = Invoke-E2EProcess -FilePath $E2E['PowerShell'] -WorkingDirectory $HOME `
        -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', $script:E2EInvokeCommand) `
        -OutFile $E2E['StepOut'] -ErrFile $E2E['StepErr'] -TimeoutSeconds $E2ETimeout['Block'] `
        -Environment @{ E2E_BLOCK_LINE = $Line }
    if ($code -ne 0) {
        $E2E['Broken'] = $Block.Id
        Complete-E2EStep fail "line 1 exited $code ($(ConvertTo-E2EOneLine $Line 200)): $(Get-E2ELastLine $E2E['StepErr'])"
        return $false
    }
    $stowed = Test-E2EStowed
    if (-not $stowed['Done']) {
        $E2E['Broken'] = $Block.Id
        Complete-E2EStep fail "stow-all.ps1 exited 0, but $($stowed['Detail'])"
        return $false
    }
    $warnings = @(@(Get-E2ELines $E2E['StepOut']) + @(Get-E2ELines $E2E['StepErr']) | Where-Object { $_ -match '^WARNING: ' })
    Complete-E2EStep pass "1 line run as printed (run-stow); $($stowed['Detail']); $($warnings.Count) warning(s)"
    if ($warnings.Count) { Write-E2ENote "$($Block.Id)-warnings" ($warnings -join "`n") }
    return $true
}

function Invoke-E2EBlocks {
    # Act on an exit-3 run's blocks in printed order; $false once a block
    # fails or is refused (Broken is set).
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Blocks)
    foreach ($block in $Blocks) {
        $action = Get-E2EBlockPolicy -Id $block.Id -Kind $block.Kind
        $text = Get-E2EBlockText $block
        switch ($action) {
            'skip' {
                if ($E2E['SkippedBlocks'] -notcontains $block.Id) {
                    $E2E['SkippedBlocks'] = @($E2E['SkippedBlocks']) + @($block.Id)
                    Skip-E2EStep $block.Id "$($block.Kind) block left to the person: $text"
                }
            }
            'run-stow' {
                $selected = Get-E2EStowLine -Lines @($block.Lines) -Clone $E2E['Clone']
                if ($selected['Error']) {
                    $E2E['Broken'] = $block.Id
                    Write-E2EFailure $block.Id "$($block.Kind) block refused: $($selected['Error']); block: $text"
                    return $false
                }
                if (-not (Invoke-E2EStowBlock -Block $block -Line $selected['Line'])) { return $false }
            }
            default {
                $E2E['Broken'] = $block.Id
                Write-E2EFailure $block.Id "$($block.Kind) block the harness must not run: $text"
                return $false
            }
        }
    }
    return $true
}

function Invoke-E2EApplyLoop {
    # setup-host.ps1 -Host win -Yes until it exits 0, at most eight runs, each
    # with the PATH a new terminal would read. Exit 3 hands the printed blocks
    # to Invoke-E2EBlocks; a run whose blocks let nothing progress fails as
    # "no progress"; exit 1 or 2 fails with what setup-host reported.
    for ($n = 1; $n -le 8; $n++) {
        $name = "apply-$n"
        Update-E2EPath
        Start-E2EStep $name "setup:$name"
        $code = Invoke-E2EPwsh -Script setup-host.ps1 -Arguments @('-Host', 'win', '-Yes') -TimeoutSeconds $E2ETimeout['Apply']
        $output = @(Get-E2ELines $E2E['StepOut'])
        $errors = @(Get-E2ELines $E2E['StepErr'])
        switch ($code) {
            0 {
                $done = @($output | Where-Object { $_ -match '\] [A-Za-z0-9-]+: done: ' }).Count
                $skipped = @($output | Where-Object { $_ -match '\] [A-Za-z0-9-]+: skip: ' }).Count
                Complete-E2EStep pass "exit 0 after $n run(s); $done done, $skipped skip"
                return $true
            }
            3 {
                $blocks = @(ConvertFrom-E2EBlocks -Output $output -Directory ([IO.Path]::ChangeExtension($E2E['StepLog'], '.blocks')))
                $actions = @($blocks | ForEach-Object { Get-E2EBlockPolicy -Id $_.Id -Kind $_.Kind })
                $pending = Get-E2EPendingIds (@($output) + @($errors))
                $summary = Get-E2EBlocksSummary $blocks
                if ($actions -notcontains 'run-stow') {
                    $E2E['Broken'] = $name
                    Complete-E2EStep fail "no progress: exit 3 with no block the harness may run (pending: $pending; blocks: $summary)"
                    return $false
                }
                Complete-E2EStep pass "exit 3; blocks: $summary; pending: $pending"
                if (-not (Invoke-E2EBlocks -Blocks $blocks)) { return $false }
            }
            { $_ -in @(1, 2) } {
                $E2E['Broken'] = $name
                Complete-E2EStep fail "exit $code`: $(Get-E2EFailureDetail $output $errors)"
                return $false
            }
            default {
                $E2E['Broken'] = $name
                Complete-E2EStep fail "exit $code (124 is the $($E2ETimeout['Apply'])s timeout): $(Get-E2ELastLine $E2E['StepErr'])"
                return $false
            }
        }
    }
    $E2E['Broken'] = 'apply-loop'
    Write-E2EFailure apply-loop 'eight apply runs without an exit 0'
    return $false
}

function Invoke-E2EFlowWin {
    # The whole sequence for the win host.
    Invoke-E2EStepClone
    Invoke-E2EOrSkip winget { Invoke-E2EStepWinget }
    Invoke-E2EOrSkip doctor-initial { Invoke-E2EStepDoctorInitial }
    Invoke-E2EOrSkip check-nowrite { Invoke-E2EStepCheckNoWrite }
    if ($E2E['Broken']) { Skip-E2EStep apply-1 "after $($E2E['Broken']) failed" }
    else { [void](Invoke-E2EApplyLoop) }
    Invoke-E2EOrSkip second-apply { Invoke-E2EStepSecondApply }
    Invoke-E2EOrSkip login-shell { Invoke-E2EStepLoginShell }
    Invoke-E2EOrSkip doctor-final { Invoke-E2EStepDoctorFinal }
}
