#Requires -Version 7.0
# Real temporary Git fixtures; never installs live dotfiles or schedules tasks.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$sourceRoot = if ($env:DOTFILES_TEST_ROOT) { $env:DOTFILES_TEST_ROOT } else { Split-Path $PSScriptRoot -Parent }
$helperPath = Join-Path $sourceRoot 'scripts/dotfiles-auto-stow.ps1'
$hookPath = Join-Path $sourceRoot 'scripts/dotfiles-update.ps1'
$global:DotfilesTestGitExecutable = (Get-Command git -CommandType Application | Select-Object -First 1).Source
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-update-ps-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$environmentNames = @(@('DOTFILES_HOST', 'DOTFILES_AUTO_STOW', 'DOTFILES_AUTO_UPDATE', 'DOTFILES_DIR',
        '_DOTFILES_CHECKED', 'GIT_TERMINAL_PROMPT', 'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM',
        'GIT_TEMPLATE_DIR', 'DOTFILES_TEST_STOW_FAILURE', 'DOTFILES_TEST_STOW_NO_ACK') +
    @(Get-ChildItem Env: | Where-Object Name -Like 'GIT_*' | Select-Object -ExpandProperty Name) |
    Sort-Object -Unique)
$savedEnvironment = @{}
foreach ($name in $environmentNames) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name) }
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
    $global:DotfilesTestTaskProgram = $global:DotfilesTestGitExecutable
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
    # -C cannot override inherited repository/index/object-store redirects or
    # injected config. Fixtures must never reach the caller's checkout/hooks.
    foreach ($name in $environmentNames) {
        if ($name.StartsWith('GIT_', [StringComparison]::OrdinalIgnoreCase)) {
            # Setting a .NET environment variable to $null can leave an empty
            # GIT_DIR on current runtimes; remove the provider entry instead.
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath "Env:$name") { throw "Cannot isolate inherited Git variable: $name" }
        }
    }
    $env:GIT_CONFIG_GLOBAL = Join-Path $testRoot 'gitconfig'
    [IO.File]::WriteAllText($env:GIT_CONFIG_GLOBAL, '')
    $env:GIT_CONFIG_NOSYSTEM = '1'
    $env:GIT_TERMINAL_PROMPT = '0'
    $env:GIT_TEMPLATE_DIR = Join-Path $testRoot 'empty-git-template'
    [void][IO.Directory]::CreateDirectory($env:GIT_TEMPLATE_DIR)

    . $helperPath
    function git {
        $global:DotfilesTestGitCalls.Add(($args -join ' '))
        if ($args.Count -ge 3 -and $args[2] -eq $global:DotfilesTestFailGitCommand) {
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
    # The registered task starts DotfilesTestTaskProgram (an existing file by
    # default); $null stands for no registered task.
    function Get-ScheduledTask {
        [CmdletBinding()]
        param([string]$TaskName)
        if ($null -eq $global:DotfilesTestTaskProgram) { return }
        [pscustomobject]@{ TaskName = $TaskName; Actions = @([pscustomobject]@{ Execute = $global:DotfilesTestTaskProgram }) }
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
    Test-Case 'a submodule marker left by an older updater is ignored' {
        $fixture = New-Fixture
        $directory = Get-DotfilesStateDirectory $fixture.Repo
        Write-DotfilesState $directory 'submodules.json' @{ home = [Environment]::GetFolderPath('UserProfile'); head = (Get-DotfilesHead $fixture.Repo) }
        Add-RemoteCommit $fixture
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-Equal (Get-DotfilesHead $fixture.Repo) (Get-AppliedHead $fixture) 'Update not acknowledged.'
        Assert-Equal 1 (Get-InstallCount $fixture) 'Installer must run once.'
        Assert-True (-not ($global:DotfilesTestGitCalls | Where-Object { $_ -match ' submodule ' })) 'The updater ran a submodule command.'
    }
    Test-Case 'pull that removes a checked-out submodule leaves its checkout ignored' {
        # The payload repos' change: one fast-forward deletes a gitlink whose
        # checkout holds files, which the pull cannot remove. A .gitignore line
        # keeps it out of the status, so the restow runs and is acknowledged
        # in that update; without the line the update stops before the stow.
        foreach ($guarded in @($true, $false)) {
            $fixture = New-Fixture
            $kit = New-Fixture
            [void][IO.Directory]::CreateDirectory((Join-Path $kit.Seed 'bin'))
            [IO.File]::WriteAllText((Join-Path $kit.Seed 'bin/tool'), 'tool content' + [Environment]::NewLine)
            Invoke-TestGit -C $kit.Seed add bin/tool
            Invoke-TestGit -C $kit.Seed commit --quiet -m 'add tool'
            Invoke-TestGit -C $kit.Seed push --quiet
            Invoke-TestGit -C $fixture.Seed -c protocol.file.allow=always submodule add --quiet $kit.Remote old/kit
            Invoke-TestGit -C $fixture.Seed commit --quiet -m 'add the submodule'
            Invoke-TestGit -C $fixture.Seed push --quiet
            Invoke-TestGit -C $fixture.Repo pull --ff-only --quiet
            Invoke-TestGit -C $fixture.Repo -c protocol.file.allow=always submodule update --init --quiet
            Assert-True (Test-Path -LiteralPath (Join-Path $fixture.Repo 'old/kit/bin/tool') -PathType Leaf) 'Checkout missing.'
            Save-DotfilesStowState $fixture.Repo 'win'
            $previous = Get-AppliedHead $fixture
            Assert-Equal (Get-DotfilesHead $fixture.Repo) $previous 'Baseline was not acknowledged.'
            Invoke-TestGit -C $fixture.Seed rm --quiet old/kit
            if ($guarded) {
                [IO.File]::WriteAllText((Join-Path $fixture.Seed '.gitignore'), '/old/kit/' + [Environment]::NewLine)
                Invoke-TestGit -C $fixture.Seed add .gitignore
            }
            Invoke-TestGit -C $fixture.Seed commit --quiet -m 'remove the submodule'
            Invoke-TestGit -C $fixture.Seed push --quiet
            if ($guarded) { Invoke-DotfilesUpdate $fixture.Repo }
            else { Assert-Throws { Invoke-DotfilesUpdate $fixture.Repo } 'Working tree changed during update' }
            $head = Get-DotfilesHead $fixture.Repo
            Assert-True ($head -ne $previous) 'HEAD did not fast-forward.'
            Assert-True (Test-Path -LiteralPath (Join-Path $fixture.Repo 'old/kit/bin/tool') -PathType Leaf) 'The update removed the checkout.'
            Assert-True (-not ($global:DotfilesTestGitCalls | Where-Object { $_ -match ' submodule ' })) 'The updater ran a submodule command.'
            if (-not $guarded) {
                Assert-Equal 0 (Get-InstallCount $fixture) 'Installer ran despite the untracked checkout.'
                Assert-Equal $previous (Get-AppliedHead $fixture) 'Applied state advanced despite the untracked checkout.'
                Invoke-DotfilesUpdate $fixture.Repo
                Assert-Equal 0 (Get-InstallCount $fixture) 'Installer ran despite the local changes.'
                continue
            }
            Assert-Equal 1 (Get-InstallCount $fixture) 'Installer must run once.'
            Assert-Equal $head (Get-AppliedHead $fixture) 'Success not acknowledged.'
            $status = & $global:DotfilesTestGitExecutable -C $fixture.Repo status --porcelain --untracked-files=normal
            Assert-Equal 0 $LASTEXITCODE 'Cannot read the checkout status.'
            Assert-Equal '' (@($status) -join "`n") 'Checkout is not clean after the update.'
            Invoke-DotfilesUpdate $fixture.Repo
            Assert-Equal 1 (Get-InstallCount $fixture) 'The next update restowed again.'
        }
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
    Test-Case 'WIN override and legacy host state dispatch canonical win' {
        $fixture = New-Fixture
        $directory = Get-DotfilesStateDirectory $fixture.Repo
        Save-DotfilesStowState $fixture.Repo 'WIN'
        $saved = Get-Content -LiteralPath (Join-Path $directory 'configuration.json') -Raw | ConvertFrom-Json
        Assert-Equal 'win' $saved.host 'Manual save did not canonicalize WIN.'
        # Existing metadata may contain mixed-case hosts accepted by older hooks.
        Write-DotfilesState $directory 'configuration.json' @{ home = [Environment]::GetFolderPath('UserProfile'); host = 'WiN'; appliedHead = '' }
        Assert-Equal 'win' (Read-DotfilesState $directory).host 'Legacy configuration host not canonicalized on read.'
        $env:DOTFILES_HOST = 'WIN'
        $global:DotfilesTestElevated = $false
        Invoke-DotfilesUpdate $fixture.Repo
        $request = Get-Content -LiteralPath (Join-Path $directory 'request.json') -Raw | ConvertFrom-Json
        Assert-Equal 'win' $request.host 'Override dispatched uppercase host.'
        $request.host = 'WIN'
        Write-DotfilesState $directory 'request.json' $request
        $global:DotfilesTestElevated = $true
        Invoke-DotfilesApply $fixture.Repo
        $saved = Get-Content -LiteralPath (Join-Path $directory 'configuration.json') -Raw | ConvertFrom-Json
        Assert-Equal 'win' $saved.host 'Worker did not canonicalize legacy request.'
        Assert-Equal 'win' ([IO.File]::ReadAllText((Join-Path $directory 'installs.log')).Trim()) 'Installer received noncanonical host.'
        Remove-Item Env:DOTFILES_HOST
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-Equal 1 (Get-InstallCount $fixture) 'Canonical host caused redundant restow.'
    }
    Test-Case 'invalid Windows host fails before dispatch' {
        $fixture = New-Fixture
        $env:DOTFILES_HOST = 'wsl-ubuntu'
        Assert-Throws { Invoke-DotfilesUpdate $fixture.Repo } 'Windows DOTFILES_HOST'
        Assert-Equal 0 (Get-InstallCount $fixture) 'Unsupported host installed.'
        Assert-Throws { Save-DotfilesStowState $fixture.Repo 'arbitraryhost' } 'Windows DOTFILES_HOST'
        $directory = Get-DotfilesStateDirectory $fixture.Repo
        Write-DotfilesState $directory 'request.json' @{ home = [Environment]::GetFolderPath('UserProfile'); host = 'arbitraryhost'; head = (Get-DotfilesHead $fixture.Repo) }
        Assert-Throws { Invoke-DotfilesApply $fixture.Repo } 'Windows DOTFILES_HOST'
        Assert-Equal 0 (Get-InstallCount $fixture) 'Invalid legacy request installed.'
    }
    Test-Case 'missing null and non-string persisted hosts fail closed before dispatch or apply' {
        $fixture = New-Fixture
        $directory = Get-DotfilesStateDirectory $fixture.Repo
        foreach ($name in @('configuration.json', 'request.json')) {
            foreach ($hostCase in @(@{ Label = 'missing' }, @{ Label = 'null'; Value = $null },
                    @{ Label = 'empty array'; Value = @() }, @{ Label = 'array'; Value = @('win') },
                    @{ Label = 'number'; Value = 0 }, @{ Label = 'boolean'; Value = $false },
                    @{ Label = 'object'; Value = @{} })) {
                Save-DotfilesStowState $fixture.Repo 'win'
                $value = @{ home = [Environment]::GetFolderPath('UserProfile'); head = (Get-DotfilesHead $fixture.Repo); appliedHead = '' }
                if ($hostCase.ContainsKey('Value')) { $value.host = $hostCase.Value }
                Write-DotfilesState $directory $name $value
                if ($name -eq 'configuration.json') {
                    Assert-Throws { Request-DotfilesRestow $fixture.Repo $directory } 'host must be a string'
                }
                else { Assert-Throws { Invoke-DotfilesApply $fixture.Repo } 'host must be a string' }
                Assert-Equal 0 (Get-InstallCount $fixture) "$name accepted $($hostCase.Label) host."
            }
        }
        Assert-Equal 0 $global:DotfilesTestTaskCalls.Count 'Malformed host dispatched a scheduled task.'
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
        Assert-Throws { Invoke-DotfilesUpdate $fixture.Repo } 'scripts.dotfiles-auto-stow.ps1 -Register.*elevated PowerShell'
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
        # The pwsh running this suite may be any package; the next case covers
        # the real check. This one proves what the branch passes and uses.
        function Get-DotfilesTaskShell {
            param([string]$PowerShellHome, [string]$Version)
            $global:DotfilesTestShellQuery = @($PowerShellHome, $Version)
            return 'X:\stable\pwsh.exe'
        }
        $preview = [scriptblock]::Create('[CmdletBinding(SupportsShouldProcess)]param([string]$RegistrationRoot) $DotfilesRepoRoot = $RegistrationRoot; $Register = $true; $Apply = $false; ' + $registration[0].Extent.Text)
        & $preview -RegistrationRoot $sourceRoot -WhatIf
        Assert-True ($registration[0].Extent.Text -match '-LogonType Interactive -RunLevel Highest') 'Registration principal lost interactive highest-privilege contract.'
        Assert-True ($registration[0].Extent.Text -match '-MultipleInstances IgnoreNew') 'Task overlap guard missing.'
        $running = $PSVersionTable.PSVersion
        Assert-Equal $PSHOME $global:DotfilesTestShellQuery[0] 'Registration did not check its own $PSHOME.'
        Assert-Equal ('{0}.{1}.{2}' -f $running.Major, $running.Minor, $running.Patch) $global:DotfilesTestShellQuery[1] 'Registration did not check its own version.'
        function New-ScheduledTaskAction {
            param([string]$Execute, [string]$Argument, [string]$WorkingDirectory)
            $global:DotfilesTestTaskExecute = $Execute
            throw 'Recorded action.'
        }
        Assert-Throws { & $preview -RegistrationRoot $sourceRoot } '^Recorded action\.$'
        Assert-Equal 'X:\stable\pwsh.exe' $global:DotfilesTestTaskExecute 'Task does not start the checked pwsh.'
        # A refused pwsh stops registration before the elevation check and
        # ShouldProcess, so an ordinary shell and -WhatIf report it too, and
        # before any Scheduled Tasks command.
        function Get-DotfilesTaskShell { throw 'Injected refusal.' }
        Assert-Throws { & $preview -RegistrationRoot $sourceRoot -WhatIf } '^Injected refusal\.$'
        Assert-Throws { & $preview -RegistrationRoot $sourceRoot } '^Injected refusal\.$'
        $global:DotfilesTestElevated = $false
        Assert-Throws { & $preview -RegistrationRoot $sourceRoot } '^Injected refusal\.$'
    }
    Test-Case 'task shell refuses a pwsh whose folder is named for its version' {
        # Windows paths as strings: off Windows no C: drive exists, and the
        # helper must not need one.
        $separator = [IO.Path]::DirectorySeparatorChar
        $msi = 'C:\Program Files\PowerShell\7'
        Assert-Equal "$msi${separator}pwsh.exe" (Get-DotfilesTaskShell $msi '7.6.7') 'MSI pwsh not used by path.'
        $msix = 'C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.7.0_x64__8wekyb3d8bbwe'
        Assert-Throws { Get-DotfilesTaskShell $msix '7.6.7' } 'named for its version.*Remove-AppxPackage.*--installer-type wix'
        Assert-Throws { Get-DotfilesTaskShell $msix.ToLowerInvariant().Replace('\', '/') '7.6.7' } 'named for its version'
        # Another volume, and a WindowsApps segment alone.
        Assert-Throws { Get-DotfilesTaskShell 'D:\WindowsApps\Microsoft.PowerShell_7.6.7.0_x64__8wekyb3d8bbwe\' '9.9.9' } 'named for its version'
        Assert-Throws { Get-DotfilesTaskShell 'D:\tools\.store\powershell\7.6.7\powershell\7.6.7\tools\net9.0\any\win' '7.6.7' } 'named for its version'
        Assert-Throws { Get-DotfilesTaskShell 'D:\tools\PowerShell-7.6.6' '7.6.6' } 'named for its version'
        $sibling = 'C:\Program Files\WindowsAppsTools\PowerShell'
        Assert-Equal "$sibling${separator}pwsh.exe" (Get-DotfilesTaskShell $sibling '7.6.7') 'A sibling of WindowsApps was refused.'
        # A zip replaced in place keeps its path, whatever the folder says.
        $zip = 'D:\tools\PowerShell-7.6.6'
        Assert-Equal "$zip${separator}pwsh.exe" (Get-DotfilesTaskShell $zip '7.6.7') 'A folder named for another version was refused.'
    }
    Test-Case 'dispatch refuses a task whose program is gone and retries' {
        $fixture = New-Fixture
        $global:DotfilesTestElevated = $false
        $global:DotfilesTestTaskProgram = Join-Path (Join-Path $testRoot 'removed pwsh') 'pwsh.exe'
        Assert-Throws { Invoke-DotfilesUpdate $fixture.Repo } 'removed pwsh.*no longer exists.*-Register again'
        Assert-Equal 0 $global:DotfilesTestTaskCalls.Count 'Task with a missing program was started.'
        Assert-Equal '' (Get-AppliedHead $fixture) 'Refused dispatch acknowledged HEAD.'
        $global:DotfilesTestTaskProgram = ''
        Assert-Throws { Invoke-DotfilesUpdate $fixture.Repo } 'names no program to start.*-Register again'
        Assert-Equal 0 $global:DotfilesTestTaskCalls.Count 'Task naming no program was started.'
        # Re-registered; quotes around the program are accepted.
        $global:DotfilesTestTaskProgram = '"' + $global:DotfilesTestGitExecutable + '"'
        Invoke-DotfilesUpdate $fixture.Repo
        Assert-Equal 1 $global:DotfilesTestTaskCalls.Count 'Dispatch not retried after re-registration.'
    }
    Test-Case 'dispatch warns about a task in a WindowsApps folder but starts it' {
        $fixture = New-Fixture
        $global:DotfilesTestElevated = $false
        $package = Join-Path (Join-Path $testRoot 'WindowsApps') 'Microsoft.PowerShell_7.6.7.0_x64__8wekyb3d8bbwe'
        [void][IO.Directory]::CreateDirectory($package)
        $global:DotfilesTestTaskProgram = Join-Path $package 'pwsh.exe'
        [IO.File]::WriteAllText($global:DotfilesTestTaskProgram, '')
        $warnings = @(Invoke-DotfilesUpdate $fixture.Repo *>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match 'next pwsh update removes' })
        Assert-Equal 1 $warnings.Count 'Versioned task program not warned about.'
        Assert-True ($warnings[0] -match '\[warn\].*-Register again') "Warning lacks the fix: $($warnings[0])"
        Assert-Equal 1 $global:DotfilesTestTaskCalls.Count 'Still-working task was not started.'
    }
    Test-Case 'task status separates missing, empty, gone, versioned and working programs' {
        $global:DotfilesTestTaskProgram = $null
        Assert-Equal 'Missing' (Get-DotfilesTaskStatus 'any').State 'No task.'
        $global:DotfilesTestTaskProgram = ''
        Assert-Equal 'NoProgram' (Get-DotfilesTaskStatus 'any').State 'Empty Execute.'
        $global:DotfilesTestTaskProgram = Join-Path (Join-Path $testRoot 'removed pwsh') 'pwsh.exe'
        Assert-Equal 'Gone' (Get-DotfilesTaskStatus 'any').State 'Removed program.'
        # Task Scheduler resolves a bare name on PATH; it cannot be tested here.
        $global:DotfilesTestTaskProgram = 'pwsh.exe'
        Assert-Equal 'Ok' (Get-DotfilesTaskStatus 'any').State 'Bare program name.'
        $global:DotfilesTestTaskProgram = '"' + $global:DotfilesTestGitExecutable + '"'
        $status = Get-DotfilesTaskStatus 'any'
        Assert-Equal 'Ok' $status.State 'Quoted existing program.'
        Assert-Equal $global:DotfilesTestGitExecutable $status.Program 'Quotes kept in the program.'
        $package = Join-Path (Join-Path (Join-Path $testRoot 'status') 'WindowsApps') 'Microsoft.PowerShell_7.6.7.0_x64__8wekyb3d8bbwe'
        [void][IO.Directory]::CreateDirectory($package)
        $global:DotfilesTestTaskProgram = Join-Path $package 'pwsh.exe'
        [IO.File]::WriteAllText($global:DotfilesTestTaskProgram, '')
        Assert-Equal 'Versioned' (Get-DotfilesTaskStatus 'any').State 'Program in a WindowsApps folder.'
        # setup-host counts only a working task as done; it runs only on
        # Windows against the real Task Scheduler, so pin its one call here.
        $setupHost = [IO.File]::ReadAllText((Join-Path $sourceRoot 'setup-host.ps1'))
        Assert-True ($setupHost.Contains("return (Get-DotfilesTaskStatus (Get-DotfilesTaskName `$RepoRoot)).State -ceq 'Ok'")) 'setup-host HW-auto-stow-task check does not require a working task.'
    }
    Test-Case 'worker branch retains all-stream log capture without changing caller preferences' {
        $fixture = New-Fixture
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($helperPath, [ref]$null, [ref]$parseErrors)
        Assert-True (-not $parseErrors) 'Helper failed PowerShell parse.'
        $dispatch = @($ast.EndBlock.Statements | Where-Object { $_.Extent.Text.StartsWith('if ($Register)') })
        Assert-Equal 1 $dispatch.Count 'Could not isolate worker dispatch.'
        function Invoke-DotfilesApply {
            param([string]$Repo)
            Write-DotfilesLog step 'Worker stage'
            Write-DotfilesLog ok 'Worker success'
            Write-Output 'Installer output'
        }
        # A real file preserves $PSScriptRoot inside the worker's child scope;
        # ScriptBlock.Create resets that automatic variable to an empty value.
        # The helper derives the checkout from its own location, which only the
        # whole file does; the extracted branch gets it injected instead, with
        # the fixture repo standing in for the checkout root.
        $worker = Join-Path $fixture.Repo 'worker-test.ps1'
        [IO.File]::WriteAllText($worker, '[CmdletBinding(SupportsShouldProcess)]param([switch]$Register, [switch]$Apply) $DotfilesRepoRoot = $PSScriptRoot; ' + $dispatch[0].Extent.Text)
        $PSNativeCommandUseErrorActionPreference = $true
        $savedErrorAction = $ErrorActionPreference
        . $worker -Apply
        Assert-Equal $savedErrorAction $ErrorActionPreference 'Worker changed caller error preference.'
        Assert-True $PSNativeCommandUseErrorActionPreference 'Worker changed caller native preference.'
        $content = [IO.File]::ReadAllText((Join-Path (Get-DotfilesStateDirectory $fixture.Repo) 'restow.log'))
        Assert-True ($content.Contains('[dotfiles] [step] Worker stage')) 'Worker log lost stage output.'
        Assert-True ($content.Contains('[dotfiles] [ok] Worker success')) 'Worker log lost success output.'
        Assert-True ($content.Contains('Installer output')) 'Worker log lost ordinary output.'
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
        $stubDirectory = Join-Path $fixture.Repo 'scripts'
        [void][IO.Directory]::CreateDirectory($stubDirectory)
        [IO.File]::WriteAllText((Join-Path $stubDirectory 'dotfiles-auto-stow.ps1'), $stub)
        $hookSource = [IO.File]::ReadAllText($hookPath)
        $consoleGuard = 'if ([Console]::IsOutputRedirected) { return }'
        Assert-True ($hookSource.Contains($consoleGuard)) 'Console guard not found.'
        # Simulate a console only at its explicit guard, leaving hook logic intact.
        $interactiveHook = [scriptblock]::Create($hookSource.Replace($consoleGuard, ''))
        $global:DotfilesTestHookCalls = 0
        $env:DOTFILES_DIR = $fixture.Repo
        $env:DOTFILES_AUTO_UPDATE = '0'
        $PSNativeCommandUseErrorActionPreference = $true
        $savedErrorAction = $ErrorActionPreference
        $savedNativePreference = $PSNativeCommandUseErrorActionPreference
        . $interactiveHook
        Assert-Equal $savedErrorAction $ErrorActionPreference 'Disabled hook changed caller error preference.'
        Assert-Equal $savedNativePreference $PSNativeCommandUseErrorActionPreference 'Disabled hook changed native preference.'
        Assert-Equal '1' $env:_DOTFILES_CHECKED 'Disabled hook did not export marker.'
        Assert-Equal 0 $global:DotfilesTestHookCalls 'Disabled hook ran update.'
        $env:DOTFILES_AUTO_UPDATE = '1'
        . $interactiveHook
        Assert-Equal 0 $global:DotfilesTestHookCalls 'Existing marker did not suppress update.'
        Remove-Item Env:_DOTFILES_CHECKED
        . $interactiveHook
        Assert-Equal 1 $global:DotfilesTestHookCalls 'Interactive hook missed update.'
        Assert-Equal '1' $env:_DOTFILES_CHECKED 'Failed hook did not export marker.'
        Assert-Equal $savedErrorAction $ErrorActionPreference 'Failed hook changed caller error preference.'
        Assert-Equal $savedNativePreference $PSNativeCommandUseErrorActionPreference 'Failed hook changed native preference.'
        & $interactiveHook
        Assert-Equal 1 $global:DotfilesTestHookCalls 'Failed hook retried in same session.'
    }
    Test-Case 'redirected hook is quiet and leaves marker unset' {
        $fixture = New-Fixture
        # Linux pre-commit uses a PTY. -NonInteractive does not redirect stdout,
        # so create a real redirected child instead of assuming the test runner
        # has no console. This exercises the actual guard on every platform.
        $start = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        foreach ($argument in @('-NoProfile', '-NonInteractive', '-Command')) {
            $start.ArgumentList.Add($argument)
        }
        $start.ArgumentList.Add(@'
$ErrorActionPreference = 'Stop'
& $env:DOTFILES_TEST_HOOK
if (Test-Path Env:_DOTFILES_CHECKED) { throw 'Noninteractive hook consumed marker.' }
Write-Output 'redirected-hook=PASS'
'@)
        $start.Environment['DOTFILES_DIR'] = $fixture.Repo
        $start.Environment['DOTFILES_TEST_HOOK'] = $hookPath
        [void]$start.Environment.Remove('_DOTFILES_CHECKED')
        $child = [Diagnostics.Process]::Start($start)
        try {
            $stdout = $child.StandardOutput.ReadToEndAsync()
            $stderr = $child.StandardError.ReadToEndAsync()
            if (-not $child.WaitForExit(30000)) {
                $child.Kill($true)
                throw 'Redirected hook did not return within 30 seconds.'
            }
            $outputText = $stdout.GetAwaiter().GetResult()
            $errorText = $stderr.GetAwaiter().GetResult()
            Assert-Equal 0 $child.ExitCode "Redirected child failed: $errorText"
            Assert-Equal 'redirected-hook=PASS' $outputText.Trim() 'Redirected hook was not quiet.'
            Assert-Equal '' $errorText 'Redirected hook wrote stderr.'
        }
        finally { $child.Dispose() }
        Assert-Equal 0 (Get-InstallCount $fixture) 'Noninteractive hook invoked installer.'
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
