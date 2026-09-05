#Requires -Version 7.0
# Real temporary Git fixtures; never installs live dotfiles or schedules tasks.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$sourceRoot = if ($env:DOTFILES_TEST_ROOT) { $env:DOTFILES_TEST_ROOT } else { Split-Path $PSScriptRoot -Parent }
$helperPath = Join-Path $sourceRoot 'dotfiles-auto-stow.ps1'
$hookPath = Join-Path $sourceRoot 'dotfiles-update.ps1'
$global:DotfilesTestGitExecutable = (Get-Command git -CommandType Application | Select-Object -First 1).Source
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-update-ps-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$environmentNames = @('DOTFILES_HOST', 'DOTFILES_AUTO_STOW', 'DOTFILES_AUTO_UPDATE', 'DOTFILES_DIR',
    '_DOTFILES_CHECKED', 'GIT_TERMINAL_PROMPT', 'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM',
    'DOTFILES_TEST_STOW_FAILURE', 'DOTFILES_TEST_STOW_NO_ACK')
$savedEnvironment = @{}
foreach ($name in $environmentNames) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name) }
$env:GIT_CONFIG_GLOBAL = Join-Path $testRoot 'gitconfig'
[IO.File]::WriteAllText($env:GIT_CONFIG_GLOBAL, '')
$env:GIT_CONFIG_NOSYSTEM = '1'
$global:DotfilesTestPassed = 0
$global:DotfilesTestFixtureNumber = 0

function Assert-True {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw $Message }
}
function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -cne $Actual) { throw "$Message (expected '$Expected', actual '$Actual')" }
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern)
    $failure = $null
    try { & $Action | Out-Null } catch { $failure = $_.Exception.Message }
    Assert-True ($null -ne $failure) "Expected failure matching '$Pattern'."
    Assert-True ($failure -match $Pattern) "Unexpected failure: $failure"
}
function Invoke-TestGit {
    & $global:DotfilesTestGitExecutable @args 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Fixture Git command failed: $args" }
}
function New-Fixture {
    $global:DotfilesTestFixtureNumber++
    $root = Join-Path $testRoot ("fixture $global:DotfilesTestFixtureNumber")
    [void][IO.Directory]::CreateDirectory($root)
    $remote = Join-Path $root 'remote.git'
    $seed = Join-Path $root 'seed'
    $repo = Join-Path $root 'checkout with spaces'
    Invoke-TestGit init --bare --quiet $remote
    Invoke-TestGit init --quiet --initial-branch=main $seed
    Invoke-TestGit -C $seed config user.name 'Dotfiles tests'
    Invoke-TestGit -C $seed config user.email 'dotfiles-tests@example.invalid'
    $installer = @'
param([AllowEmptyString()][string]$HostDir, [switch]$Strict)
if (-not $Strict) { throw 'Automatic installer must receive -Strict.' }
$directory = Get-DotfilesStateDirectory $PSScriptRoot
[IO.File]::AppendAllText((Join-Path $directory 'installs.log'), $HostDir + [Environment]::NewLine)
if ($env:DOTFILES_TEST_STOW_FAILURE -eq '1') { throw 'Injected installer failure.' }
if ($env:DOTFILES_TEST_STOW_NO_ACK -eq '1') { return }
Save-DotfilesStowState $PSScriptRoot $HostDir
'@
    [IO.File]::WriteAllText((Join-Path $seed 'stow-all.ps1'), $installer + [Environment]::NewLine)
    [IO.File]::WriteAllText((Join-Path $seed 'settings.txt'), 'initial' + [Environment]::NewLine)
    Invoke-TestGit -C $seed add stow-all.ps1 settings.txt
    Invoke-TestGit -C $seed commit --quiet -m initial
    Invoke-TestGit -C $seed remote add origin $remote
    Invoke-TestGit -C $seed push --quiet -u origin main
    Invoke-TestGit --git-dir=$remote symbolic-ref HEAD refs/heads/main
    Invoke-TestGit clone --quiet $remote $repo
    Invoke-TestGit -C $repo config user.name 'Dotfiles tests'
    Invoke-TestGit -C $repo config user.email 'dotfiles-tests@example.invalid'
    return [pscustomobject]@{ Root = $root; Remote = $remote; Seed = $seed; Repo = $repo }
}
function Add-RemoteCommit {
    param($Fixture)
    [IO.File]::AppendAllText((Join-Path $Fixture.Seed 'settings.txt'), 'updated' + [Environment]::NewLine)
    Invoke-TestGit -C $Fixture.Seed add settings.txt
    Invoke-TestGit -C $Fixture.Seed commit --quiet -m update
    Invoke-TestGit -C $Fixture.Seed push --quiet
}
function Get-InstallCount {
    param($Fixture)
    $log = Join-Path (Get-DotfilesStateDirectory $Fixture.Repo) 'installs.log'
    if (-not (Test-Path -LiteralPath $log)) { return 0 }
    return @([IO.File]::ReadAllLines($log)).Count
}
function Get-AppliedHead {
    param($Fixture)
    $state = Read-DotfilesState (Get-DotfilesStateDirectory $Fixture.Repo)
    if ($null -eq $state) { return '' }
    return $state.appliedHead
}
function Test-Case {
    param([string]$Name, [scriptblock]$Action)
    $global:DotfilesTestElevated = $true
    $global:DotfilesTestFailGitCommand = ''
    $global:DotfilesTestFailTaskStart = $false
    $global:DotfilesTestGitCalls = [Collections.Generic.List[string]]::new()
    $global:DotfilesTestTaskCalls = [Collections.Generic.List[string]]::new()
    foreach ($environmentName in @('DOTFILES_HOST', 'DOTFILES_AUTO_STOW', 'DOTFILES_AUTO_UPDATE',
            'DOTFILES_DIR', '_DOTFILES_CHECKED', 'DOTFILES_TEST_STOW_FAILURE', 'DOTFILES_TEST_STOW_NO_ACK')) {
        Remove-Item -LiteralPath "Env:$environmentName" -ErrorAction SilentlyContinue
    }
    & $Action
    $global:DotfilesTestPassed++
    Write-Host "PASS: $Name"
}

try {
    . $helperPath
    function git {
        $global:DotfilesTestGitCalls.Add(($args -join ' '))
        if ($args.Count -ge 3 -and ($args[2] -eq $global:DotfilesTestFailGitCommand -or
                ($global:DotfilesTestFailGitCommand -eq 'submodule-update' -and $args[2] -eq 'submodule' -and $args[3] -eq 'update'))) {
            $global:LASTEXITCODE = 17
            return
        }
        & $global:DotfilesTestGitExecutable @args
        $global:LASTEXITCODE = $LASTEXITCODE
    }
    function Test-DotfilesElevated { return $global:DotfilesTestElevated }
    function Start-ScheduledTask {
        [CmdletBinding()]
        param([string]$TaskName)
        $global:DotfilesTestTaskCalls.Add($TaskName)
        if ($global:DotfilesTestFailTaskStart) { throw 'Injected task startup failure.' }
    }

    Test-Case 'pull applies new revision once' {
        $fixture = New-Fixture
        Save-DotfilesStowState $fixture.Repo 'win'
        $previous = Get-AppliedHead $fixture
        Add-RemoteCommit $fixture
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-True ((Get-DotfilesHead $fixture.Repo) -ne $previous) 'HEAD did not fast-forward.'
        Assert-Equal (Get-DotfilesHead $fixture.Repo) (Get-AppliedHead $fixture) 'Success not acknowledged.'
        Assert-Equal 1 (Get-InstallCount $fixture) 'Installer must run once.'
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-Equal 1 (Get-InstallCount $fixture) 'Already applied HEAD reinstalled.'
        Assert-Equal 1 @($global:DotfilesTestGitCalls | Where-Object { $_ -match ' pull --ff-only --quiet$' }).Count 'Pull must be fast-forward only.'
    }
    Test-Case 'ordinary user queues a task; worker applies' {
        $fixture = New-Fixture
        $global:DotfilesTestElevated = $false
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-Equal 0 (Get-InstallCount $fixture) 'Unelevated installer ran.'
        Assert-Equal 1 $global:DotfilesTestTaskCalls.Count 'Expected one task request.'
        Assert-Equal (Get-DotfilesTaskName $fixture.Repo) $global:DotfilesTestTaskCalls[0] 'Wrong task requested.'
        $request = Read-DotfilesState (Get-DotfilesStateDirectory $fixture.Repo) 'request.json'
        Assert-Equal (Get-DotfilesHead $fixture.Repo) $request.head 'Wrong HEAD requested.'
        $global:DotfilesTestElevated = $true
        Invoke-DotfilesApply $fixture.Repo
        Assert-Equal 1 (Get-InstallCount $fixture) 'Worker did not apply.'
    }
    Test-Case 'failed installer retries without new commit' {
        $fixture = New-Fixture
        $env:DOTFILES_TEST_STOW_FAILURE = '1'
        Assert-Throws { Invoke-DotfilesUpdate $fixture.Repo } 'Injected installer failure'
        Assert-Equal '' (Get-AppliedHead $fixture) 'Failure acknowledged HEAD.'
        $env:DOTFILES_TEST_STOW_FAILURE = '0'
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-Equal 2 (Get-InstallCount $fixture) 'Pending installer not retried.'
        Assert-Equal (Get-DotfilesHead $fixture.Repo) (Get-AppliedHead $fixture) 'Retry not acknowledged.'
    }
    Test-Case 'offline retry restores prompt preference' {
        $fixture = New-Fixture
        $global:DotfilesTestFailGitCommand = 'fetch'
        $env:GIT_TERMINAL_PROMPT = 'original-value'
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-Equal 1 (Get-InstallCount $fixture) 'Offline pending HEAD skipped.'
        Assert-Equal 'original-value' $env:GIT_TERMINAL_PROMPT 'Git prompt preference leaked.'
    }
    Test-Case 'failed pull does not install and releases lock' {
        $fixture = New-Fixture
        Add-RemoteCommit $fixture
        $global:DotfilesTestFailGitCommand = 'pull'
        Assert-Throws { Invoke-DotfilesUpdate $fixture.Repo } 'Fast-forward pull failed'
        Assert-Equal '' (Get-AppliedHead $fixture) 'Failed pull acknowledged HEAD.'
        Assert-Equal 0 (Get-InstallCount $fixture) 'Failed pull ran installer.'
        $lock = Open-DotfilesLock (Get-DotfilesStateDirectory $fixture.Repo)
        Assert-True ($null -ne $lock) 'Failed pull leaked lock.'
        $lock.Dispose()
    }
    Test-Case 'submodule failure does not install or acknowledge' {
        $fixture = New-Fixture
        $global:DotfilesTestFailGitCommand = 'submodule-update'
        Assert-Throws { Invoke-DotfilesUpdate $fixture.Repo } 'Submodule update failed'
        Assert-Equal '' (Get-AppliedHead $fixture) 'Submodule failure acknowledged HEAD.'
        Assert-Equal 0 (Get-InstallCount $fixture) 'Submodule failure ran installer.'
    }
    Test-Case 'successful exit without installer acknowledgement stays pending' {
        $fixture = New-Fixture
        $env:DOTFILES_TEST_STOW_NO_ACK = '1'
        Assert-Throws { Invoke-DotfilesUpdate $fixture.Repo } 'did not acknowledge'
        Assert-Equal '' (Get-AppliedHead $fixture) 'Unacknowledged installer set state.'
    }
    Test-Case 'dirty tracked and untracked files skip fetch and restow' {
        $fixture = New-Fixture
        [IO.File]::AppendAllText((Join-Path $fixture.Repo 'settings.txt'), 'local edit')
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-Equal 0 (Get-InstallCount $fixture) 'Dirty checkout installed.'
        Assert-True (-not ($global:DotfilesTestGitCalls | Where-Object { $_ -match ' fetch ' })) 'Dirty checkout fetched.'
        Invoke-TestGit -C $fixture.Repo checkout -- settings.txt
        [IO.File]::WriteAllText((Join-Path $fixture.Repo 'untracked.txt'), 'local')
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-Equal 0 (Get-InstallCount $fixture) 'Untracked local file ignored.'
    }
    Test-Case 'dirty nested submodule is preserved despite ignored submodule status' {
        $fixture = New-Fixture
        $outer = New-Fixture
        $inner = New-Fixture
        Invoke-TestGit -C $outer.Seed -c protocol.file.allow=always submodule add --quiet $inner.Remote nested
        Invoke-TestGit -C $outer.Seed commit --quiet -am 'add nested submodule'
        Invoke-TestGit -C $outer.Seed push --quiet
        Invoke-TestGit -C $fixture.Repo -c protocol.file.allow=always submodule add --quiet $outer.Remote modules/outer
        Invoke-TestGit -C $fixture.Repo -c protocol.file.allow=always submodule update --init --recursive --quiet
        Invoke-TestGit -C $fixture.Repo commit --quiet -am 'add outer submodule'
        Invoke-TestGit -C $fixture.Repo config diff.ignoreSubmodules all
        [IO.File]::AppendAllText((Join-Path $fixture.Repo 'modules/outer/nested/settings.txt'), 'nested edit')
        Assert-True (-not (Test-DotfilesClean $fixture.Repo)) 'Normal check ignored nested edits.'
        Assert-True (-not (Test-DotfilesClean $fixture.Repo -AllowGitlinkChanges)) 'Retry check ignored nested edits.'
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-Equal 0 (Get-InstallCount $fixture) 'Dirty nested submodule installed.'
        Assert-True (-not ($global:DotfilesTestGitCalls | Where-Object { $_ -match ' fetch ' })) 'Nested edits did not skip fetch.'
        $nested = Join-Path $fixture.Repo 'modules/outer/nested'
        Invoke-TestGit -C $nested checkout -- settings.txt
        Invoke-TestGit -C $nested -c user.name=Tests -c user.email=tests@example.invalid commit --quiet --allow-empty -m 'user selected revision'
        $userHead = Get-DotfilesHead $nested
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-Equal $userHead (Get-DotfilesHead $nested) 'Clean user-selected submodule commit was reset.'
        Assert-Equal 0 (Get-InstallCount $fixture) 'Unrecorded gitlink change was installed.'
        $directory = Get-DotfilesStateDirectory $fixture.Repo
        Write-DotfilesState $directory 'submodules.json' @{ home = [Environment]::GetFolderPath('UserProfile'); head = 'stale-head' }
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-Equal $userHead (Get-DotfilesHead $nested) 'Stale pending marker allowed reset.'
        Set-DotfilesSubmodulePending $fixture.Repo $directory
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-True ((Get-DotfilesHead $nested) -ne $userHead) 'Matching retry marker did not synchronize nested gitlink.'
        Assert-Equal 1 (Get-InstallCount $fixture) 'Matching retry marker did not permit apply.'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $directory 'submodules.json'))) 'Successful sync left pending marker.'
    }
    Test-Case 'host changes apply unchanged HEAD including common-only' {
        $fixture = New-Fixture
        Save-DotfilesStowState $fixture.Repo 'win'
        $env:DOTFILES_HOST = ''
        Invoke-DotfilesUpdate $fixture.Repo
        $state = Read-DotfilesState (Get-DotfilesStateDirectory $fixture.Repo)
        Assert-Equal '' $state.host 'Explicit common-only not retained.'
        Assert-Equal 1 (Get-InstallCount $fixture) 'Host-only change did not restow.'
        Remove-Item Env:DOTFILES_HOST -ErrorAction SilentlyContinue
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-Equal 1 (Get-InstallCount $fixture) 'Remembered common-only lost.'
        $env:DOTFILES_HOST = 'win'
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-Equal 2 (Get-InstallCount $fixture) 'Switching back to win did not apply.'
    }
    Test-Case 'invalid Windows host fails before dispatch' {
        $fixture = New-Fixture
        $env:DOTFILES_HOST = 'wsl-ubuntu'
        Assert-Throws { Invoke-DotfilesUpdate $fixture.Repo } 'Windows DOTFILES_HOST'
        Assert-Equal 0 (Get-InstallCount $fixture) 'Unsupported host installed.'
    }
    Test-Case 'dirty manual install remembers host without acknowledging commit' {
        $fixture = New-Fixture
        [IO.File]::AppendAllText((Join-Path $fixture.Repo 'settings.txt'), 'local edit')
        Save-DotfilesStowState $fixture.Repo ''
        $state = Read-DotfilesState (Get-DotfilesStateDirectory $fixture.Repo)
        Assert-Equal '' $state.host 'Dirty manual common-only host lost.'
        Assert-Equal '' $state.appliedHead 'Dirty manual install acknowledged commit.'
    }
    Test-Case 'configuration and request are home-bound' {
        $fixture = New-Fixture
        $directory = Get-DotfilesStateDirectory $fixture.Repo
        Write-DotfilesState $directory 'configuration.json' @{ home = (Join-Path $testRoot 'another-home'); host = 'win'; appliedHead = '' }
        Assert-Throws { Request-DotfilesRestow $fixture.Repo $directory } 'another home'
        Write-DotfilesState $directory 'request.json' @{ home = (Join-Path $testRoot 'another-home'); host = 'win'; head = (Get-DotfilesHead $fixture.Repo) }
        Assert-Throws { Invoke-DotfilesApply $fixture.Repo } 'another home'
        Assert-Equal 0 (Get-InstallCount $fixture) 'Foreign-home request applied.'
    }
    Test-Case 'lock contention skips update until release' {
        $fixture = New-Fixture
        $directory = Get-DotfilesStateDirectory $fixture.Repo
        $lock = Open-DotfilesLock $directory
        Assert-True ($null -ne $lock) 'First lock acquisition failed.'
        try {
            Assert-True ($null -eq (Open-DotfilesLock $directory)) 'Concurrent lock granted.'
            Invoke-DotfilesUpdate $fixture.Repo
            Assert-Equal 0 (Get-InstallCount $fixture) 'Busy checkout installed.'
        }
        finally { $lock.Dispose() }
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-Equal 1 (Get-InstallCount $fixture) 'Released lock remained blocked.'
    }
    Test-Case 'failed task startup reports registration command and retries' {
        $fixture = New-Fixture
        $global:DotfilesTestElevated = $false
        $global:DotfilesTestFailTaskStart = $true
        Assert-Throws { Invoke-DotfilesUpdate $fixture.Repo } 'dotfiles-auto-stow.ps1 -Register.*elevated PowerShell'
        Assert-Equal '' (Get-AppliedHead $fixture) 'Failed dispatch acknowledged HEAD.'
        $global:DotfilesTestFailTaskStart = $false
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-Equal 2 $global:DotfilesTestTaskCalls.Count 'Failed dispatch not retried.'
    }
    Test-Case 'restow opt-out still pulls without advancing applied state' {
        $fixture = New-Fixture
        Save-DotfilesStowState $fixture.Repo 'win'
        $previous = Get-AppliedHead $fixture
        Add-RemoteCommit $fixture
        $env:DOTFILES_AUTO_STOW = '0'
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-True ((Get-DotfilesHead $fixture.Repo) -ne $previous) 'Restow opt-out disabled pull.'
        Assert-Equal $previous (Get-AppliedHead $fixture) 'Opt-out acknowledged update.'
        Assert-Equal 0 (Get-InstallCount $fixture) 'Restow opt-out ignored.'
        $env:DOTFILES_AUTO_STOW = '1'
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-Equal 1 (Get-InstallCount $fixture) 'Re-enabling did not apply pending HEAD.'
    }
    Test-Case 'worker refuses stale request and unelevated execution' {
        $fixture = New-Fixture
        $directory = Get-DotfilesStateDirectory $fixture.Repo
        [void](Request-DotfilesRestow $fixture.Repo $directory)
        Add-RemoteCommit $fixture
        Invoke-TestGit -C $fixture.Repo pull --ff-only --quiet
        Assert-Throws { Invoke-DotfilesApply $fixture.Repo } 'HEAD changed'
        Assert-Equal 0 (Get-InstallCount $fixture) 'Worker applied unrequested revision.'
        $global:DotfilesTestElevated = $false
        Assert-Throws { Invoke-DotfilesApply $fixture.Repo } 'requires an elevated task'
    }
    Test-Case 'task identity normalizes trailing separator and separates checkouts' {
        $fixture = New-Fixture
        Assert-Equal (Get-DotfilesTaskName $fixture.Repo) (Get-DotfilesTaskName ($fixture.Repo + [IO.Path]::DirectorySeparatorChar)) 'Trailing separator changed task identity.'
        Assert-True ((Get-DotfilesTaskName $fixture.Repo) -ne (Get-DotfilesTaskName $fixture.Seed)) 'Different checkout shared task identity.'
    }
    Test-Case 'save does not acknowledge a different expected revision' {
        $fixture = New-Fixture
        Save-DotfilesStowState $fixture.Repo 'win' 'different-head'
        Assert-Equal '' (Get-AppliedHead $fixture) 'Changed HEAD was acknowledged.'
    }
    Test-Case 'registration WhatIf never reaches Scheduled Tasks commands' {
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($helperPath, [ref]$null, [ref]$parseErrors)
        Assert-True (-not $parseErrors) 'Helper failed PowerShell parse.'
        $registration = @($ast.EndBlock.Statements | Where-Object { $_.Extent.Text.StartsWith('if ($Register)') })
        Assert-Equal 1 $registration.Count 'Could not isolate registration branch.'
        function New-ScheduledTaskAction { throw 'WhatIf attempted to create an action.' }
        function New-ScheduledTaskPrincipal { throw 'WhatIf attempted to create a principal.' }
        function New-ScheduledTaskSettingsSet { throw 'WhatIf attempted to create settings.' }
        function Register-ScheduledTask { throw 'WhatIf attempted to register a task.' }
        $preview = [scriptblock]::Create('[CmdletBinding(SupportsShouldProcess)]param([string]$RegistrationRoot) $PSScriptRoot = $RegistrationRoot; $Register = $true; $Apply = $false; ' + $registration[0].Extent.Text)
        & $preview -RegistrationRoot $sourceRoot -WhatIf
        Assert-True ($registration[0].Extent.Text -match '-LogonType Interactive -RunLevel Highest') 'Registration principal lost interactive highest-privilege contract.'
        Assert-True ($registration[0].Extent.Text -match '-MultipleInstances IgnoreNew') 'Task overlap guard missing.'
    }
    Test-Case 'interactive hook guards export marker and contain update failures' {
        $fixture = New-Fixture
        $stub = @'
function Invoke-DotfilesUpdate {
    param([string]$Repo)
    $global:DotfilesTestHookCalls++
    throw 'Injected hook failure.'
}
'@
        [IO.File]::WriteAllText((Join-Path $fixture.Repo 'dotfiles-auto-stow.ps1'), $stub)
        $hookSource = [IO.File]::ReadAllText($hookPath)
        $consoleGuard = 'if ([Console]::IsOutputRedirected) { return }'
        Assert-True ($hookSource.Contains($consoleGuard)) 'Console guard not found.'
        # Simulate a console only at its explicit guard, leaving hook logic intact.
        $interactiveHook = [scriptblock]::Create($hookSource.Replace($consoleGuard, ''))
        $global:DotfilesTestHookCalls = 0
        $env:DOTFILES_DIR = $fixture.Repo
        $env:DOTFILES_AUTO_UPDATE = '0'
        & $interactiveHook
        Assert-Equal '1' $env:_DOTFILES_CHECKED 'Disabled hook did not export marker.'
        Assert-Equal 0 $global:DotfilesTestHookCalls 'Disabled hook ran update.'
        $env:DOTFILES_AUTO_UPDATE = '1'
        & $interactiveHook
        Assert-Equal 0 $global:DotfilesTestHookCalls 'Existing marker did not suppress update.'
        Remove-Item Env:_DOTFILES_CHECKED
        & $interactiveHook
        Assert-Equal 1 $global:DotfilesTestHookCalls 'Interactive hook missed update.'
        Assert-Equal '1' $env:_DOTFILES_CHECKED 'Failed hook did not export marker.'
        & $interactiveHook
        Assert-Equal 1 $global:DotfilesTestHookCalls 'Failed hook retried in same session.'
    }
    Test-Case 'redirected hook is quiet and leaves marker unset' {
        Assert-True ([Console]::IsOutputRedirected) 'Run these tests with redirected stdout / -NonInteractive.'
        $fixture = New-Fixture
        $env:DOTFILES_DIR = $fixture.Repo
        . $hookPath
        Assert-True (-not (Test-Path Env:_DOTFILES_CHECKED)) 'Noninteractive hook consumed marker.'
        Assert-Equal 0 (Get-InstallCount $fixture) 'Noninteractive hook invoked installer.'
        Assert-True (-not ($global:DotfilesTestGitCalls | Where-Object { $_ -match ' fetch ' })) 'Noninteractive hook fetched.'
    }
    Write-Host "windows-update-hooks=PASS ($global:DotfilesTestPassed cases)"
}
finally {
    foreach ($name in $environmentNames) {
        if ($null -eq $savedEnvironment[$name]) { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name]) }
    }
    # Verify exact disposable target before recursive deletion.
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolved) -notlike 'dotfiles-update-ps-*') {
        throw "Refusing to remove unexpected test directory: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
