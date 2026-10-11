#Requires -Version 7.0
# The steps of tests/e2e/run.ps1 besides the apply loop (flow-win.ps1): the
# clone, the winget probe, the read-only doctor and -Check runs, the second
# apply, the profile load and the final doctor. Each opens its step, runs and
# closes it with a verdict; a step the rest depends on sets Broken when it
# fails, and the flow then skips what cannot run. Dot-source only, after
# common.ps1, snapshot.ps1 and blocks.ps1.

$script:E2EUpstream = 'https://github.com/FridrichMethod/dotfiles.git'
# Lines of a setup-host.ps1 -Yes run that show a step was applied: the
# "[step] <id>: ..." line before an apply and the installed, present or
# skipped result after it (inside.sh reads "<id> done applied:" plan lines).
$script:E2EAppliedRe = '\[step\] [A-Za-z0-9-]+: |: (installed|present|skipped): '

function Invoke-E2EStepClone {
    # The clone a person makes (HW-clone): from the read-only source checkout
    # at E2E_REV, with core.symlinks on and the submodules, its origin pointed
    # at GitHub as a real clone has it. Everything after it runs with the
    # login hooks off, as docs/bootstrap.md asks of every provisioning shell.
    Start-E2EStep clone setup:clone
    $clone = $E2E['Clone']
    $runs = @(
        @{ Label = 'clone'; Arguments = @('clone', '-c', 'core.symlinks=true', '--recurse-submodules', $E2E['Src'], $clone) }
        @{ Label = 'checkout'; Arguments = @('-C', $clone, '-c', 'advice.detachedHead=false', 'checkout', '--detach', $E2E['Rev']) }
        @{ Label = 'submodule update'; Arguments = @('-C', $clone, 'submodule', 'update', '--init', '--recursive') }
        @{ Label = 'remote set-url'; Arguments = @('-C', $clone, 'remote', 'set-url', 'origin', $script:E2EUpstream) }
    )
    foreach ($run in $runs) {
        $code = Invoke-E2EProcess -FilePath $E2E['Git'] -ArgumentList $run['Arguments'] -WorkingDirectory $HOME `
            -OutFile $E2E['StepOut'] -ErrFile $E2E['StepErr'] -TimeoutSeconds $E2ETimeout['Check']
        if ($code -ne 0) {
            $E2E['Broken'] = 'clone'
            Complete-E2EStep fail "git $($run['Label']) exited ${code}: $(Get-E2ELastLine $E2E['StepErr'])"
            return
        }
    }
    $env:DOTFILES_AUTO_UPDATE = '0'
    $env:AWESOME_SKILLS_AUTO_UPDATE = '0'
    $env:GIT_TERMINAL_PROMPT = '0'
    # HW-clone's verify: core.symlinks is true and the tracked links are links.
    $symlinks = (Get-E2EGitOutput @('-C', $clone, 'config', '--get', 'core.symlinks')).Text
    $pymolrc = Get-Item -LiteralPath (Join-Path $clone 'common/pymol/.pymolrc') -Force -ErrorAction SilentlyContinue
    $linkType = if ($null -ne $pymolrc) { [string]$pymolrc.LinkType } else { 'missing' }
    $short = (Get-E2EGitOutput @('-C', $clone, 'rev-parse', '--short', 'HEAD')).Text
    if ($symlinks -cne 'true' -or $linkType -cne 'SymbolicLink') {
        $E2E['Broken'] = 'clone'
        Complete-E2EStep fail "core.symlinks is '$symlinks' and common/pymol/.pymolrc is '$linkType' in the clone"
        return
    }
    Complete-E2EStep pass "$short at $clone; core.symlinks true, .pymolrc is a SymbolicLink"
}

function Get-E2EWingetVersion {
    # winget's version from winget --version, or '' when it is absent or does
    # not answer (an App Installer that is present but not registered).
    $path = Find-E2ECommand winget
    if (-not $path) { return '' }
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    try { $text = @($null | & $path --version 2>&1 | ForEach-Object { "$_" }) -join ' ' }
    catch { return '' }
    if ($LASTEXITCODE -eq 0 -and $text -match 'v?([0-9]+(\.[0-9]+)+)') { return $Matches[1] }
    return ''
}

function Repair-E2EWinget {
    # The fallback when the image has no working winget: the
    # Microsoft.WinGet.Client module for the current user (Install-PSResource,
    # or Install-Module where PSResourceGet is missing), then its
    # Repair-WinGetPackageManager -AllUsers, which installs or re-registers
    # App Installer (the runner is elevated). Module output goes to the step
    # log. Returns what ran; throws when a cmdlet fails.
    $log = $E2E['StepLog']
    $ran = [Collections.Generic.List[string]]::new()
    if (-not @(Get-Module -ListAvailable -Name Microsoft.WinGet.Client).Count) {
        if (Get-Command -Name Install-PSResource -ErrorAction SilentlyContinue) {
            Install-PSResource -Name Microsoft.WinGet.Client -Scope CurrentUser -TrustRepository -AcceptLicense -ErrorAction Stop *>> $log
            $ran.Add('Install-PSResource Microsoft.WinGet.Client -Scope CurrentUser')
        }
        else {
            Install-Module -Name Microsoft.WinGet.Client -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop *>> $log
            $ran.Add('Install-Module Microsoft.WinGet.Client -Scope CurrentUser')
        }
    }
    Import-Module -Name Microsoft.WinGet.Client -ErrorAction Stop
    Repair-WinGetPackageManager -AllUsers -ErrorAction Stop *>> $log
    $ran.Add('Repair-WinGetPackageManager -AllUsers')
    return ($ran -join ', ')
}

function Invoke-E2EStepWinget {
    # winget must answer (W1-winget imports with it). When the image lacks it,
    # Repair-E2EWinget stands in for the Microsoft Store, and that deviation
    # from the quick start is recorded as a note.
    Start-E2EStep winget setup:winget
    Update-E2EPath
    $version = Get-E2EWingetVersion
    $deviation = ''
    if (-not $version) {
        $ran = ''
        try { $ran = Repair-E2EWinget }
        catch {
            $E2E['Broken'] = 'winget'
            Complete-E2EStep fail "winget is absent and its repair failed: $($_.Exception.Message)"
            return
        }
        Update-E2EPath
        $version = Get-E2EWingetVersion
        if (-not $version) {
            $E2E['Broken'] = 'winget'
            Complete-E2EStep fail "winget is still absent or not answering after $ran"
            return
        }
        $deviation = "deviation: winget was not on the image; bootstrapped with $ran"
    }
    Complete-E2EStep pass "winget $version at $(Find-E2ECommand winget)"
    if ($deviation) { Write-E2ENote winget-bootstrap $deviation }
}

function Invoke-E2EStepDoctorInitial {
    # doctor.ps1 -Host win -Tsv on the fresh home exits 1 (the AI-sync runtime
    # and the tools are missing) and writes nothing, in TEMP or HOME.
    Start-E2EStep doctor-initial check:doctor-initial
    Start-E2ENoWrite doctor-initial
    $code = Invoke-E2EPwsh -Script doctor.ps1 -Arguments @('-Host', 'win', '-Tsv') `
        -TimeoutSeconds $E2ETimeout['Check'] -Environment (Get-E2ENoWriteEnvironment)
    $problems = Stop-E2ENoWrite doctor-initial
    $suffix = if ($problems) { "; $problems" } else { '' }
    if ($code -ne 1) { Complete-E2EStep fail "exit $code, expected 1 on a fresh home$suffix" }
    elseif ($problems) { Complete-E2EStep fail $problems }
    else { Complete-E2EStep pass "exit 1; $(Get-E2ETsvCounts $E2E['StepOut'])no writes" }
}

function Invoke-E2EStepCheckNoWrite {
    # setup-host.ps1 -Host win -Check plans (exit 3 while work remains, 0 when
    # nothing is left) and writes nothing.
    Start-E2EStep check-nowrite check:check-nowrite
    Start-E2ENoWrite check-nowrite
    $code = Invoke-E2EPwsh -Script setup-host.ps1 -Arguments @('-Host', 'win', '-Check') `
        -TimeoutSeconds $E2ETimeout['Check'] -Environment (Get-E2ENoWriteEnvironment)
    $problems = Stop-E2ENoWrite check-nowrite
    $output = @(Get-E2ELines $E2E['StepOut'])
    $suffix = if ($problems) { "; $problems" } else { '' }
    if ($code -notin @(0, 3)) {
        Complete-E2EStep fail "exit ${code}: $(Get-E2EFailureDetail $output @(Get-E2ELines $E2E['StepErr']))$suffix"
    }
    elseif ($problems) { Complete-E2EStep fail "exit $code$suffix" }
    else {
        $todo = @($output | Where-Object { $_ -cmatch '^[A-Za-z0-9-]+ todo ' }).Count
        $human = @($output | Where-Object { $_ -cmatch '^[A-Za-z0-9-]+ human ' }).Count
        Complete-E2EStep pass "exit $code; $todo todo, $human human; no writes"
    }
}

function Invoke-E2EStepSecondApply {
    # One more setup-host.ps1 -Host win -Yes exits 0, applies nothing (a
    # [step] or installed/present/skipped line would be a step that redid its
    # work) and writes nothing in HOME.
    Update-E2EPath
    Start-E2EStep second-apply setup:second-apply
    Start-E2ENoWrite second-apply
    $code = Invoke-E2EPwsh -Script setup-host.ps1 -Arguments @('-Host', 'win', '-Yes') `
        -TimeoutSeconds $E2ETimeout['Apply'] -Environment (Get-E2ENoWriteEnvironment)
    $problems = Stop-E2ENoWrite second-apply
    $output = @(Get-E2ELines $E2E['StepOut'])
    $applied = @($output | Where-Object { $_ -match $script:E2EAppliedRe })
    if ($code -ne 0) {
        Complete-E2EStep fail "exit $code, expected 0: $(Get-E2EFailureDetail $output @(Get-E2ELines $E2E['StepErr']))"
    }
    elseif ($applied.Count) { Complete-E2EStep fail "a second apply redid work: $(ConvertTo-E2EOneLine ($applied -join "`n") 300)" }
    elseif ($problems) { Complete-E2EStep fail $problems }
    else { Complete-E2EStep pass 'exit 0, nothing applied, HOME untouched' }
}

function Invoke-E2EStepLoginShell {
    # The Windows stand-in for the login-shell check: a pwsh that loads the
    # stowed profile (no -NoProfile), non-interactive with its output
    # redirected as an agent terminal or a script host starts it, exits 0 and
    # prints nothing. The profile gates its interactive setup and the update
    # hook on an interactive console, so silence is the contract
    # (tests/powershell-profile.ps1 covers the interactive paths).
    Update-E2EPath
    Start-E2EStep login-shell check:login-shell
    $code = Invoke-E2EProcess -FilePath $E2E['PowerShell'] -ArgumentList @('-NonInteractive', '-Command', 'exit 0') `
        -WorkingDirectory $HOME -OutFile $E2E['StepOut'] -ErrFile $E2E['StepErr'] -TimeoutSeconds $E2ETimeout['Check']
    $printed = @(@(Get-E2ELines $E2E['StepOut']) + @(Get-E2ELines $E2E['StepErr']) | Where-Object { $_.Trim() -ne '' })
    $profilePath = [string]$PROFILE.CurrentUserAllHosts
    $item = Get-Item -LiteralPath $profilePath -Force -ErrorAction SilentlyContinue
    $linkType = if ($null -ne $item) { [string]$item.LinkType } else { 'missing' }
    if ($code -ne 0) { Complete-E2EStep fail "exit $code loading ${profilePath}: $(Get-E2ELastLine $E2E['StepErr'])" }
    elseif ($printed.Count) { Complete-E2EStep fail "the profile load printed: $(ConvertTo-E2EOneLine ($printed -join "`n") 300)" }
    elseif ($linkType -cne 'SymbolicLink') { Complete-E2EStep fail "$profilePath is '$linkType', not a symlink the stow made" }
    else { Complete-E2EStep pass "exit 0, silent; $profilePath is a SymbolicLink" }
}

function Invoke-E2EStepDoctorFinal {
    # doctor.ps1 -Host win, with the PATH a new terminal reads, exits 0.
    Update-E2EPath
    Start-E2EStep doctor-final check:doctor-final
    $code = Invoke-E2EPwsh -Script doctor.ps1 -Arguments @('-Host', 'win') -TimeoutSeconds $E2ETimeout['Check']
    if ($code -eq 0) { Complete-E2EStep pass 'exit 0 with the registry PATH' }
    else { Complete-E2EStep fail "exit ${code}: $(Get-E2EProblemLines $E2E['StepOut'])" }
}
