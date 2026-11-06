#Requires -Version 7.0
# The steps of tests/e2e/run.ps1 besides the apply loop (flow-win.ps1): the
# clone, the winget probe, the read-only doctor and -Check runs, the native
# handover through docs/bootstrap.md "Fresh Windows home by hand" and its
# convergence check, the second apply, the profile load, the payload repos,
# the final doctor, the isolated native fixtures and the task and
# sync-runtime audits. Each opens its step, runs and closes it with a
# verdict; a step the rest depends on sets Broken when it fails, and the flow
# then skips what cannot run. Dot-source only, after common.ps1,
# snapshot.ps1 and blocks.ps1.

$script:E2EUpstream = 'https://github.com/FridrichMethod/dotfiles.git'
# Lines of a setup-host.ps1 -Yes run that show a step was applied: the
# "[step] <id>: ..." line before an apply and the installed, present or
# skipped result after it (inside.sh reads "<id> done applied:" plan lines).
$script:E2EAppliedRe = '\[step\] [A-Za-z0-9-]+: |: (installed|present|skipped): '

function Get-E2EScheduledTaskNames {
    # Read task identities only (TaskPath + TaskName, sorted, one per line).
    return (@(Get-ScheduledTask -ErrorAction Stop | ForEach-Object { $_.TaskPath + $_.TaskName } | Sort-Object) -join "`n")
}

function Test-E2ERegularFile {
    # True when Path is a regular file: present, no directory, no link or
    # other reparse point (its own attributes, never its target's).
    param([Parameter(Mandatory)][string]$Path)
    try { $attributes = [IO.File]::GetAttributes($Path) }
    catch { return $false }
    return (($attributes -band ([IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint)) -eq 0)
}

function Get-E2EFileSha256 {
    # The SHA-256 of a file, as Get-FileHash reports it.
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Invoke-E2EStepNativeHandover {
    # HW-native done the way a person does it on a fresh home: the clone's
    # docs/bootstrap.md "Fresh Windows home by hand" functions, checked by
    # Get-E2EHandoverScript and written with the one call
    # Invoke-NativeHandover -Role win to handover\run.ps1 under the out dir,
    # run by a child pwsh -NoProfile -NonInteractive from the clone. The step
    # log starts with the HW-native block it stands in for. It passes when the
    # child exits 0 and the end state is the documented one: the clone's
    # lib/chezmoi-guard.ps1 accepts the home binding as naming the clone, the
    # local config is a regular file selecting win, no maintenance and no
    # stray state database beside the config, a non-empty bound state
    # database, and a same-hash private copy of each of .gitconfig and the
    # two profile.ps1 files that existed before. The runner token is elevated
    # (it has no ordinary one), which the procedure warns about and a note
    # records; the ordinary-token login-updater check stays in per-host
    # acceptance.
    Start-E2EStep native-handover human:HW-native
    if ($null -ne $E2E['HandoverBlock']) {
        Add-E2EText $E2E['StepLog'] ("--- block`n" + (@($E2E['HandoverBlock'].Lines) -join "`n") + "`n")
    }
    $userHome = $E2E['Home']
    $handover = Get-E2EHandoverScript -Document (Join-Path $E2E['Clone'] 'docs/bootstrap.md')
    if ($handover['Error']) {
        $E2E['Broken'] = 'native-handover'
        Complete-E2EStep fail "docs/bootstrap.md: $($handover['Error'])"
        return
    }
    $directory = Join-Path $E2E['Out'] 'handover'
    [void][IO.Directory]::CreateDirectory($directory)
    $runner = Join-Path $directory 'run.ps1'
    [IO.File]::WriteAllText($runner, $handover['Text'] + "`nInvoke-NativeHandover -Role win`n", $script:E2EUtf8)
    $before = [ordered]@{}
    foreach ($relative in @('.gitconfig', 'Documents/PowerShell/profile.ps1', 'Documents/WindowsPowerShell/profile.ps1')) {
        $path = Join-Path $userHome $relative
        if (Test-E2ERegularFile $path) { $before[$relative] = Get-E2EFileSha256 $path }
    }
    $code = Invoke-E2EProcess -FilePath $E2E['PowerShell'] -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $runner) `
        -WorkingDirectory $E2E['Clone'] -OutFile $E2E['StepOut'] -ErrFile $E2E['StepErr'] -TimeoutSeconds $E2ETimeout['Apply']
    if ($code -ne 0) {
        $E2E['Broken'] = 'native-handover'
        Complete-E2EStep fail "Invoke-NativeHandover -Role win exit ${code}: $(Get-E2ELastLine $E2E['StepErr'])"
        return
    }
    $problems = [Collections.Generic.List[string]]::new()
    $source = ''
    try {
        . (Join-Path $E2E['Clone'] 'lib/chezmoi-guard.ps1')
        $binding = Get-DotfilesNativeBinding -HomePath $userHome
        $expected = Resolve-DotfilesDirectory $E2E['Clone']
        $source = [string]$binding.Source
        if (-not $source.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
            $problems.Add("the home binding names $source, not the clone $expected")
        }
    }
    catch { $problems.Add("lib/chezmoi-guard.ps1 refuses the home binding: $($_.Exception.Message)") }
    $config = Join-Path $userHome '.config/chezmoi/chezmoi.toml'
    if (-not (Test-E2ERegularFile $config)) { $problems.Add('~\.config\chezmoi\chezmoi.toml is missing, a link or not a regular file') }
    elseif ([IO.File]::ReadAllText($config) -cnotmatch '(?m)^\s*host\s*=\s*[''"]win[''"]') {
        $problems.Add('~\.config\chezmoi\chezmoi.toml does not select host win')
    }
    if (Test-E2EEntry (Join-Path $userHome '.config/dotfiles/maintenance')) { $problems.Add('~\.config\dotfiles\maintenance exists') }
    if (Test-E2EEntry (Join-Path $userHome '.config/chezmoi/chezmoistate.boltdb')) {
        $problems.Add('~\.config\chezmoi\chezmoistate.boltdb exists (a chezmoi run without the explicit argument set)')
    }
    $state = Join-Path $userHome '.local/state/chezmoi/chezmoi.boltdb'
    if (-not (Test-E2ERegularFile $state) -or [IO.FileInfo]::new($state).Length -eq 0) {
        $problems.Add('~\.local\state\chezmoi\chezmoi.boltdb is missing or empty')
    }
    $kept = 0
    foreach ($relative in $before.Keys) {
        $copy = Join-Path (Join-Path $userHome '.local/state/dotfiles-fresh-backup') $relative
        if ((Test-E2ERegularFile $copy) -and (Get-E2EFileSha256 $copy) -ceq $before[$relative]) { $kept++ }
        else { $problems.Add("no same-hash copy of ~\$($relative.Replace('/', '\')) in ~\.local\state\dotfiles-fresh-backup") }
    }
    if ($problems.Count) {
        $E2E['Broken'] = 'native-handover'
        Complete-E2EStep fail "Invoke-NativeHandover -Role win exit 0, but $($problems -join '; ')"
        return
    }
    Complete-E2EStep pass "Invoke-NativeHandover -Role win exit 0; $kept earlier file(s) kept byte for byte; bound to $source"
    if (Test-E2EElevated) {
        Write-E2ENote handover-token 'elevated: the hosted runner has no ordinary token; the ordinary-token login-updater check stays in per-host acceptance'
    }
}

function Invoke-E2EStepCheckDone {
    # After the handover, setup-host.ps1 -Host win -Check has nothing left:
    # exit 0, no todo line, no step that blocks completion, and no write in
    # TEMP or HOME.
    Update-E2EPath
    Start-E2EStep check-done check:check-done
    Start-E2ENoWrite check-done
    $code = Invoke-E2EPwsh -Script setup-host.ps1 -Arguments @('-Host', 'win', '-Check') `
        -TimeoutSeconds $E2ETimeout['Check'] -Environment (Get-E2ENoWriteEnvironment)
    $problems = Stop-E2ENoWrite check-done
    $output = @(Get-E2ELines $E2E['StepOut'])
    $left = @($output | Where-Object { $_ -cmatch '^[A-Za-z0-9-]+ todo ' -or $_ -cmatch '^[A-Za-z0-9-]+ human .*; blocks completion$' })
    if ($code -ne 0) {
        Complete-E2EStep fail "exit $code, expected 0 after the handover: $(Get-E2EFailureDetail $output @(Get-E2ELines $E2E['StepErr']))"
    }
    elseif ($left.Count) { Complete-E2EStep fail "exit 0 with steps left: $(ConvertTo-E2EOneLine ($left -join "`n") 300)" }
    elseif ($problems) { Complete-E2EStep fail $problems }
    else { Complete-E2EStep pass 'exit 0; nothing left to apply; no writes' }
}

function Invoke-E2EStepNativeConverged {
    # With the Fresh Windows home by hand functions of the clone, a child pwsh
    # (handover\converged.ps1 under the out dir) runs Invoke-NativeCz
    # @('diff', '--exclude=dirs') and exits 4 with the diff when it is not
    # empty, else prints "--- managed" and the Invoke-NativeCz @('managed',
    # '--include=files,symlinks') list. The step passes when the diff is
    # empty (after the payload repos ran, so an installer that edits a
    # managed target shows here), every listed target is a regular file of
    # the home, and the stray state database is still absent.
    Start-E2EStep native-converged check:native-converged
    $handover = Get-E2EHandoverScript -Document (Join-Path $E2E['Clone'] 'docs/bootstrap.md')
    if ($handover['Error']) {
        Complete-E2EStep fail "docs/bootstrap.md: $($handover['Error'])"
        return
    }
    $directory = Join-Path $E2E['Out'] 'handover'
    [void][IO.Directory]::CreateDirectory($directory)
    $runner = Join-Path $directory 'converged.ps1'
    $check = @(
        '$diff = [string](Invoke-NativeCz @(''diff'', ''--exclude=dirs''))'
        'if ($diff.Trim()) { [Console]::Out.Write($diff); exit 4 }'
        '[Console]::Out.WriteLine(''--- managed'')'
        '[Console]::Out.Write([string](Invoke-NativeCz @(''managed'', ''--include=files,symlinks'')))'
        'exit 0'
    ) -join "`n"
    [IO.File]::WriteAllText($runner, $handover['Text'] + "`n" + $check + "`n", $script:E2EUtf8)
    $code = Invoke-E2EProcess -FilePath $E2E['PowerShell'] -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $runner) `
        -WorkingDirectory $E2E['Clone'] -OutFile $E2E['StepOut'] -ErrFile $E2E['StepErr'] -TimeoutSeconds $E2ETimeout['Check']
    $output = @(Get-E2ELines $E2E['StepOut'])
    if ($code -eq 4) {
        $headers = @($output | Where-Object { $_ -cmatch '^diff ' } | Select-Object -First 5)
        if (-not $headers.Count) { $headers = @($output | Where-Object { $_.Trim() } | Select-Object -First 3) }
        Complete-E2EStep fail "Invoke-NativeCz diff --exclude=dirs is not empty: $(ConvertTo-E2EOneLine ($headers -join "`n") 400)"
        return
    }
    if ($code -ne 0) {
        Complete-E2EStep fail "the convergence check exited ${code}: $(Get-E2ELastLine $E2E['StepErr'])"
        return
    }
    $marker = [Array]::IndexOf([object[]]$output, '--- managed')
    $managed = @(if ($marker -ge 0) { $output | Select-Object -Skip ($marker + 1) | Where-Object { $_.Trim() } })
    $bad = @($managed | Where-Object { -not (Test-E2ERegularFile (Join-Path $E2E['Home'] $_)) })
    if (-not $managed.Count) { Complete-E2EStep fail 'Invoke-NativeCz managed --include=files,symlinks listed no target' }
    elseif ($bad.Count) { Complete-E2EStep fail "managed targets that are not regular files: $(ConvertTo-E2EOneLine ($bad -join ' ') 300)" }
    elseif (Test-E2EEntry (Join-Path $E2E['Home'] '.config/chezmoi/chezmoistate.boltdb')) {
        Complete-E2EStep fail 'empty diff, but ~\.config\chezmoi\chezmoistate.boltdb exists'
    }
    else { Complete-E2EStep pass "empty diff; $($managed.Count) managed file(s), all regular" }
}

function Invoke-E2EStepNativeFixtures {
    # tests/chezmoi.ps1 with the provisioned ~\.local\bin\chezmoi.exe
    # required. The native suite owns temp homes and explicit native state
    # paths and never touches this home.
    Start-E2EStep native-fixtures check:native-fixtures
    if (-not [IO.File]::Exists((Join-Path $E2E['Clone'] 'tests/test_chezmoi_takeover_recovery.py'))) {
        $E2E['Broken'] = 'native-fixtures'
        Complete-E2EStep fail 'native takeover/recovery fixture is missing from this checkout'
        return
    }
    $code = Invoke-E2EPwsh -Script tests/chezmoi.ps1 -TimeoutSeconds $E2ETimeout['Apply'] -Environment @{
        DOTFILES_TEST_CHEZMOI = (Join-Path $E2E['Home'] '.local/bin/chezmoi.exe')
        DOTFILES_TEST_REQUIRE_CHEZMOI = '1'
    }
    if ($code -ne 0) {
        $E2E['Broken'] = 'native-fixtures'
        Complete-E2EStep fail "isolated native suite exit ${code}: $(Get-E2ELastLine $E2E['StepErr'])"
    }
    else { Complete-E2EStep pass 'isolated native source/config/takeover/recovery fixtures passed' }
}

function Invoke-E2EAuditTasks {
    # audit-scheduled-tasks: at the end no scheduled task of the dotfiles
    # exists (an identity whose name starts with Dotfiles-, the retired
    # restow task's), and the task identities did not change after the apply
    # loop (the handover and every step after it register nothing). The
    # tasks the loop itself added (installers winget ran) are listed in a
    # note.
    Start-E2EStep audit-scheduled-tasks check:audit-scheduled-tasks
    $now = @(([string](Get-E2EScheduledTaskNames)) -split "`n" | Where-Object { $_ })
    $before = @(([string]$E2E['TasksBefore']) -split "`n" | Where-Object { $_ })
    $afterLoop = @(([string]$E2E['TasksAfterLoop']) -split "`n" | Where-Object { $_ })
    $dotfiles = @($now | Where-Object { $_ -match '\\Dotfiles-[^\\]*$' })
    $problems = [Collections.Generic.List[string]]::new()
    if ($dotfiles.Count) { $problems.Add("a dotfiles task exists: $($dotfiles -join ', ')") }
    if ($afterLoop.Count -and (($afterLoop -join "`n") -cne ($now -join "`n"))) {
        $added = @($now | Where-Object { $afterLoop -notcontains $_ })
        $removed = @($afterLoop | Where-Object { $now -notcontains $_ })
        $problems.Add("task identities changed after the apply loop (added: $($added -join ', '); removed: $($removed -join ', '))")
    }
    if ($problems.Count) { Complete-E2EStep fail ($problems -join '; ') }
    else { Complete-E2EStep pass "no dotfiles task; $($now.Count) task identities, unchanged after the apply loop" }
    $loopAdded = @($afterLoop | Where-Object { $before -notcontains $_ })
    if ($loopAdded.Count) { Write-E2ENote scheduled-tasks "the apply loop added $($loopAdded.Count) task(s): $($loopAdded -join ', ')" }
}

function Invoke-E2EAuditSyncVenv {
    # audit-sync-venv: the clone never held the AI-sync runtime directory
    # after any step (Complete-E2EStep records the first that left it).
    Start-E2EStep audit-sync-venv check:audit-sync-venv
    if ($E2E['VenvViolations']) { Complete-E2EStep fail "the clone held $script:E2ESyncVenv after $($E2E['VenvViolations'])" }
    else { Complete-E2EStep pass "$script:E2ESyncVenv never appeared in the clone" }
}

function Invoke-E2EStepClone {
    # The clone a person makes (HW-clone): from the read-only source checkout
    # at E2E_REV, its origin pointed at GitHub as a real clone has it.
    # Everything after it runs with the login and payload hooks off, as
    # docs/bootstrap.md asks of every provisioning shell.
    Start-E2EStep clone setup:clone
    $clone = $E2E['Clone']
    $runs = @(
        @{ Label = 'clone'; Arguments = @('clone', $E2E['Src'], $clone) }
        @{ Label = 'checkout'; Arguments = @('-C', $clone, '-c', 'advice.detachedHead=false', 'checkout', '--detach', $E2E['Rev']) }
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
    $env:DOTFILES_PAYLOAD_AUTO_UPDATE = '0'
    $env:GIT_TERMINAL_PROMPT = '0'
    # HW-clone's verify: a clone of E2E_REV whose tree tracks no symlink.
    $short = (Get-E2EGitOutput @('-C', $clone, 'rev-parse', '--short', 'HEAD')).Text
    $links = @((Get-E2EGitOutput @('-C', $clone, 'ls-files', '-s')).Text -split "`n" | Where-Object { $_ -like '120000 *' })
    if (-not $short -or $links.Count) {
        $E2E['Broken'] = 'clone'
        Complete-E2EStep fail "the clone at $clone has HEAD '$short' and tracks $($links.Count) symlink(s)"
        return
    }
    Complete-E2EStep pass "$short at $clone; no tracked symlink"
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
    # doctor.ps1 -Host win -Tsv on the fresh home exits 1 (the tools and the
    # native binding are missing) and writes nothing, in TEMP or HOME.
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
    # deployed profile (no -NoProfile), non-interactive with its output
    # redirected as an agent terminal or a script host starts it, exits 0 and
    # prints nothing, and the profile it loads is the regular file the native
    # handover wrote. The profile gates its interactive setup and the update
    # hook on an interactive console, so silence is the contract
    # (tests/powershell-profile.ps1 covers the interactive paths).
    Update-E2EPath
    Start-E2EStep login-shell check:login-shell
    $code = Invoke-E2EProcess -FilePath $E2E['PowerShell'] -ArgumentList @('-NonInteractive', '-Command', 'exit 0') `
        -WorkingDirectory $HOME -OutFile $E2E['StepOut'] -ErrFile $E2E['StepErr'] -TimeoutSeconds $E2ETimeout['Check']
    $printed = @(@(Get-E2ELines $E2E['StepOut']) + @(Get-E2ELines $E2E['StepErr']) | Where-Object { $_.Trim() -ne '' })
    $profilePath = [string]$PROFILE.CurrentUserAllHosts
    if ($code -ne 0) { Complete-E2EStep fail "exit $code loading ${profilePath}: $(Get-E2ELastLine $E2E['StepErr'])" }
    elseif ($printed.Count) { Complete-E2EStep fail "the profile load printed: $(ConvertTo-E2EOneLine ($printed -join "`n") 300)" }
    elseif (-not (Test-E2ERegularFile $profilePath)) {
        Complete-E2EStep fail "$profilePath is missing, a link or not a regular file, not the regular file the native handover wrote"
    }
    else { Complete-E2EStep pass "exit 0, silent; $profilePath is the regular file the native handover wrote" }
}

function Invoke-E2EStepPayloads {
    # The Windows run line of docs/bootstrap.md H7-payloads,
    # scripts\payload-update.ps1 -Now, with the PATH a new terminal reads:
    # every payload repo of config/payloads.tsv with a windows-install row
    # (PyMOLScripts and awesome-skills; coding-agent-kit installs nothing on
    # native Windows) installs from the network through its own install.ps1,
    # under the block limit, since the installs run in a row. It passes when
    # that exits 0 and the payloads row of doctor.ps1 -Host win -Tsv is then
    # ok and names what it found installed.
    Update-E2EPath
    Start-E2EStep payloads setup:payloads
    $code = Invoke-E2EPwsh -Script 'scripts/payload-update.ps1' -Arguments @('-Now') -TimeoutSeconds $E2ETimeout['Block']
    if ($code -ne 0) {
        # The hook logs one [error] line per failed item, on stdout here, and goes on.
        $detail = @(@(Get-E2ELines $E2E['StepErr']) + @(Get-E2ELines $E2E['StepOut']) |
                Where-Object { $_.Contains('[error]') }) | Select-Object -First 1
        if (-not $detail) { $detail = Get-E2ELastLine $E2E['StepErr'] }
        Complete-E2EStep fail "exit $code (124 is the $($E2ETimeout['Block'])s timeout): $detail"
        return
    }
    [void](Invoke-E2EPwsh -Script doctor.ps1 -Arguments @('-Host', 'win', '-Tsv') -TimeoutSeconds $E2ETimeout['Check'])
    $row = $null
    foreach ($line in @(Get-E2ELines $E2E['StepOut'])) {
        $cells = $line.Split("`t")
        if ($cells.Count -ge 4 -and $cells[1] -ceq 'payloads') { $row = $cells; break }
    }
    if ($null -eq $row) { Complete-E2EStep fail "exit 0, but the doctor's payloads row is missing" }
    elseif ($row[0] -ceq 'ok' -and $row[3].StartsWith('installed: ', [StringComparison]::Ordinal)) {
        Complete-E2EStep pass "exit 0; doctor payloads ok: $($row[3])"
    }
    else { Complete-E2EStep fail "exit 0, but the doctor's payloads row is $($row[0]): $($row[3])" }
}

function Invoke-E2EStepDoctorFinal {
    # doctor.ps1 -Host win, with the PATH a new terminal reads, exits 0.
    Update-E2EPath
    Start-E2EStep doctor-final check:doctor-final
    $code = Invoke-E2EPwsh -Script doctor.ps1 -Arguments @('-Host', 'win') -TimeoutSeconds $E2ETimeout['Check']
    if ($code -eq 0) { Complete-E2EStep pass 'exit 0 with the registry PATH' }
    else { Complete-E2EStep fail "exit ${code}: $(Get-E2EProblemLines $E2E['StepOut'])" }
}
