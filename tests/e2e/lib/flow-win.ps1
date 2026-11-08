#Requires -Version 7.0
# The flow of tests/e2e/run.ps1: the setup-host.ps1 -Host win -Yes loop with
# its HUMAN blocks up to the HW-deploy step, and the whole sequence:
# clone, winget, doctor-initial, the no-write -Check, the apply loop, the
# first apply through docs/bootstrap.md "Fresh Windows home by hand", the second
# apply, the no-write -Check that finds nothing left, the profile load, the
# payload repos, the convergence check, the final doctor, the isolated
# chezmoi fixtures and the task audit: the native Windows bootstrap, driven the
# way "Running it with an agent" says an agent drives it. Dot-source only,
# after steps.ps1.

function Invoke-E2EBlocks {
    # Act on an exit-3 run's blocks in printed order; $false once a block is
    # refused (Broken is set). A block the harness must not act on refuses
    # the whole run first, wherever it was printed. The HW-deploy block is the
    # home-deploy step's, after the loop; each reminder is recorded once
    # as a skip, across runs.
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Blocks)
    foreach ($block in $Blocks) {
        if ((Get-E2EBlockPolicy -Id $block.Id -Kind $block.Kind) -ceq 'fail') {
            $E2E['Broken'] = $block.Id
            Write-E2EFailure $block.Id "$($block.Kind) block the harness must not run: $(Get-E2EBlockText $block)"
            return $false
        }
    }
    foreach ($block in $Blocks) {
        $action = Get-E2EBlockPolicy -Id $block.Id -Kind $block.Kind
        if ($action -ceq 'deploy') { continue }
        if ($action -ceq 'skip') {
            if ($E2E['SkippedBlocks'] -notcontains $block.Id) {
                $E2E['SkippedBlocks'] = @($E2E['SkippedBlocks']) + @($block.Id)
                Skip-E2EStep $block.Id "$($block.Kind) block left to the person: $(Get-E2EBlockText $block)"
            }
            continue
        }
        $E2E['Broken'] = $block.Id
        Write-E2EFailure $block.Id "$($block.Kind) block the harness must not run: $(Get-E2EBlockText $block)"
        return $false
    }
    return $true
}

function Invoke-E2EApplyLoop {
    # setup-host.ps1 -Host win -Yes until only the HW-deploy block is
    # left, at most eight runs, each with the PATH a new terminal would read;
    # Get-E2ELoopNext decides on each run, as e2e_loop_next does in
    # inside.sh. blocks: a block the harness must act on (no Windows block
    # line runs, so a refused one), handed to Invoke-E2EBlocks. rerun:
    # nothing to act on, but a step applied (a line of E2EAppliedRe). done:
    # nothing to act on, nothing applied, HW-deploy alone pending and its
    # block printed; the reminders are recorded and DeployBlock keeps that
    # block for the home-deploy step. stuck: any other exit 3 fails as
    # "no progress". early: exit 0 fails, since a fresh home cannot have
    # HW-deploy done. Exit 1 or 2 fails with what setup-host reported;
    # anything else is the timeout. Returns one bool.
    for ($n = 1; $n -le 8; $n++) {
        $name = "apply-$n"
        Update-E2EPath
        Start-E2EStep $name "setup:$name"
        $code = Invoke-E2EPwsh -Script setup-host.ps1 -Arguments @('-Host', 'win', '-Yes') -TimeoutSeconds $E2ETimeout['Apply']
        $output = @(Get-E2ELines $E2E['StepOut'])
        $stderr = @(Get-E2ELines $E2E['StepErr'])
        $applied = @($output | Where-Object { $_ -match $script:E2EAppliedRe })
        $stepped = @($output | Where-Object { $_ -match '\[step\] [A-Za-z0-9-]+: ' })
        $blocks = @()
        $actions = @()
        if ($code -eq 3) {
            $blocks = @(ConvertFrom-E2EBlocks -Output $output -Directory ([IO.Path]::ChangeExtension($E2E['StepLog'], '.blocks')))
            $actions = @($blocks | ForEach-Object { Get-E2EBlockPolicy -Id $_.Id -Kind $_.Kind })
        }
        $pending = Get-E2EPendingIds (@($output) + @($stderr))
        $summary = Get-E2EBlocksSummary $blocks
        $verdict = Get-E2ELoopNext -Code $code -Pending $pending -Actionable ($actions -contains 'fail') -Applied ($applied.Count -gt 0)
        if ($verdict -ceq 'blocks') {
            Complete-E2EStep pass "exit 3; blocks: $summary; pending: $pending"
            if (-not (Invoke-E2EBlocks -Blocks $blocks)) { return $false }
            continue
        }
        if ($verdict -ceq 'rerun') {
            Complete-E2EStep pass "exit 3; applied $($stepped.Count) step(s); pending: $pending"
            continue
        }
        $deploy = @($blocks | Where-Object { $_.Id -ceq 'HW-deploy' }) | Select-Object -First 1
        if ($verdict -ceq 'done' -and $null -ne $deploy) {
            $E2E['DeployBlock'] = $deploy
            Complete-E2EStep pass "exit 3 after $n run(s); only HW-deploy pending; blocks: $summary"
            return (Invoke-E2EBlocks -Blocks $blocks)
        }
        $E2E['Broken'] = $name
        if ($verdict -ceq 'done') {
            Complete-E2EStep fail "exit 3 with only HW-deploy pending, but no HW-deploy block (blocks: $summary)"
        }
        elseif ($verdict -ceq 'stuck') {
            Complete-E2EStep fail "no progress: exit 3 with no block the harness may run and nothing applied (pending: $pending; blocks: $summary)"
        }
        elseif ($verdict -ceq 'early') {
            Complete-E2EStep fail 'exit 0 before the first apply: HW-deploy was already done on a fresh home'
        }
        elseif ($verdict -ceq 'error') {
            Complete-E2EStep fail "exit ${code}: $(Get-E2EFailureDetail $output $stderr)"
        }
        else {
            Complete-E2EStep fail "exit $code (124 is the $($E2ETimeout['Apply'])s timeout): $(Get-E2ELastLine $E2E['StepErr'])"
        }
        return $false
    }
    $E2E['Broken'] = 'apply-loop'
    Write-E2EFailure apply-loop 'eight apply runs without reaching the first apply'
    return $false
}

function Invoke-E2EFlowWin {
    # The whole sequence for the win host. The scheduled task identities are
    # read just before and just after the apply loop; the audit runs whatever
    # broke the flow before it.
    Invoke-E2EStepClone
    Invoke-E2EOrSkip winget { Invoke-E2EStepWinget }
    Invoke-E2EOrSkip doctor-initial { Invoke-E2EStepDoctorInitial }
    Invoke-E2EOrSkip check-nowrite { Invoke-E2EStepCheckNoWrite }
    if ($E2E['Broken']) { Skip-E2EStep apply-1 "after $($E2E['Broken']) failed" }
    else {
        $E2E['TasksBefore'] = Get-E2EScheduledTaskNames
        [void](Invoke-E2EApplyLoop)
        $E2E['TasksAfterLoop'] = Get-E2EScheduledTaskNames
    }
    Invoke-E2EOrSkip home-deploy { Invoke-E2EStepHomeDeploy }
    Invoke-E2EOrSkip second-apply { Invoke-E2EStepSecondApply }
    Invoke-E2EOrSkip check-done { Invoke-E2EStepCheckDone }
    Invoke-E2EOrSkip login-shell { Invoke-E2EStepLoginShell }
    Invoke-E2EOrSkip payloads { Invoke-E2EStepPayloads }
    Invoke-E2EOrSkip home-converged { Invoke-E2EStepHomeConverged }
    Invoke-E2EOrSkip doctor-final { Invoke-E2EStepDoctorFinal }
    Invoke-E2EOrSkip chezmoi-fixtures { Invoke-E2EStepChezmoiFixtures }
    Invoke-E2EAuditTasks
}
