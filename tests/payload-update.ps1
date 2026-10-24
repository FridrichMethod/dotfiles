#Requires -Version 7.0
# scripts/payload-update.ps1 against fake installers served from file:// URIs:
# the real config/payloads.tsv with its raw.githubusercontent.com prefix
# pointed at a temporary directory. PowerShell's $HOME is the account's
# profile on Windows whatever HOME says, so the fixture copy of the config
# also reads the PyMOL rc files from DOTFILES_TEST_PAYLOAD_HOME, where the
# fakes write; every other path is under LOCALAPPDATA, which the cases set.
# Nothing here writes outside the temporary directory or reaches a network.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = Split-Path -Parent $PSScriptRoot
$pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-payload-ps-' + [Guid]::NewGuid().ToString('N'))
$names = @('LOCALAPPDATA', 'DOTFILES_TEST_PAYLOAD_HOME', 'PAYLOAD_EVENTS', 'FAKE_KIT_STATUS', 'FAKE_PYMOL_STATUS',
    'DOTFILES_PAYLOAD_AUTO_UPDATE', 'DOTFILES_PAYLOAD_ITEMS', '_DOTFILES_PAYLOAD_CHECKED', 'TEMP', 'TMP', 'TMPDIR')
$saved = @{}
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
$script:Passed = 0
$script:Case = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Write-Fixture([string]$Path, [string]$Text) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text)
}
function Test-Case([string]$Name, [scriptblock]$Action) {
    & $Action
    $script:Passed++
    Write-Output "PASS: $Name"
}

try {
    [void][IO.Directory]::CreateDirectory($testRoot)
    $remote = Join-Path $testRoot 'remote'
    $fixture = Join-Path $testRoot 'repo'
    $base = ([Uri](Join-Path $remote 'x')).AbsoluteUri
    $base = $base.Substring(0, $base.Length - 1)
    $config = [IO.File]::ReadAllText((Join-Path $repoRoot 'config/payloads.tsv'))
    Assert-True ($config.Contains('https://raw.githubusercontent.com/FridrichMethod/coding-agent-kit/main/install.ps1')) 'config/payloads.tsv no longer downloads the kit from raw.githubusercontent.com/FridrichMethod'
    $config = $config.Replace('https://raw.githubusercontent.com/FridrichMethod/', $base).Replace('Join-Path $HOME ', 'Join-Path $env:DOTFILES_TEST_PAYLOAD_HOME ')
    Assert-True (-not ($config -match 'https?://')) 'config/payloads.tsv names a URL outside raw.githubusercontent.com/FridrichMethod'
    Write-Fixture (Join-Path $fixture 'config/payloads.tsv') $config
    Write-Fixture (Join-Path $fixture 'scripts/payload-update.ps1') ([IO.File]::ReadAllText((Join-Path $repoRoot 'scripts/payload-update.ps1')))
    Write-Fixture (Join-Path $fixture 'lib/terminal.ps1') ([IO.File]::ReadAllText((Join-Path $repoRoot 'lib/terminal.ps1')))
    $hook = Join-Path $fixture 'scripts/payload-update.ps1'
    # The kit's bootstrap leaves a managed root whose install.ps1 is the
    # update command, its current file, and the three Claude helpers.
    Write-Fixture (Join-Path $remote 'coding-agent-kit/main/install.ps1') @'
param([string]$Channel, [switch]$Update)
Add-Content -LiteralPath $env:PAYLOAD_EVENTS -Value "kit-install [-Channel $Channel]"
if ($env:FAKE_KIT_STATUS -and $env:FAKE_KIT_STATUS -ne '0') { exit ([int]$env:FAKE_KIT_STATUS) }
$root = Join-Path $env:LOCALAPPDATA 'coding-agent-kit'
[void][IO.Directory]::CreateDirectory($root)
[IO.File]::WriteAllText((Join-Path $root 'current'), "v0.6.0`n")
[IO.File]::WriteAllText((Join-Path $root 'install.ps1'), @"
param([switch]`$Update, [string]`$Channel)
Add-Content -LiteralPath `$env:PAYLOAD_EVENTS -Value "kit-update [-Update `$Update -Channel `$Channel]"
if (`$env:FAKE_KIT_STATUS -and `$env:FAKE_KIT_STATUS -ne '0') { exit ([int]`$env:FAKE_KIT_STATUS) }
"@)
$helpers = Join-Path $env:DOTFILES_TEST_PAYLOAD_HOME '.claude/coding-agent-kit'
[void][IO.Directory]::CreateDirectory($helpers)
foreach ($name in 'statusline', 'notify', 'check-git-hooks') { [IO.File]::WriteAllText((Join-Path $helpers "$name.cjs"), '') }
'@
    Write-Fixture (Join-Path $remote 'PyMOLScripts/main/install.ps1') @'
Add-Content -LiteralPath $env:PAYLOAD_EVENTS -Value "pymol-install [$args]"
if ($env:FAKE_PYMOL_STATUS -and $env:FAKE_PYMOL_STATUS -ne '0') { exit ([int]$env:FAKE_PYMOL_STATUS) }
foreach ($name in '.pymolrc', '.pymolrc.py') { [IO.File]::WriteAllText((Join-Path $env:DOTFILES_TEST_PAYLOAD_HOME $name), '') }
'@
    Write-Fixture (Join-Path $remote 'awesome-skills/main/install.ps1') @'
Add-Content -LiteralPath $env:PAYLOAD_EVENTS -Value "skills-install [$args]"
[void][IO.Directory]::CreateDirectory((Join-Path $env:LOCALAPPDATA 'awesome-skills/library'))
'@
    $elevated = $IsWindows -and ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)

    # A fresh case: its own LOCALAPPDATA, test home and event log.
    function New-Case {
        $script:Case++
        $root = Join-Path $testRoot "case $script:Case"
        $case = [pscustomobject]@{ Root = $root; Data = Join-Path $root 'localappdata'; Home = Join-Path $root 'home'
            Events = Join-Path $root 'events.log'; State = Join-Path $root 'localappdata/dotfiles/payload' }
        foreach ($directory in @($case.Data, $case.Home, (Join-Path $root 'tmp'))) { [void][IO.Directory]::CreateDirectory($directory) }
        [IO.File]::WriteAllText($case.Events, '')
        return $case
    }
    # Run the hook in a child pwsh with the case's environment; Environment
    # adds or ($null) removes variables.
    function Invoke-Hook($Case, [string[]]$Arguments, [hashtable]$Environment = @{}) {
        $values = @{ LOCALAPPDATA = $Case.Data; DOTFILES_TEST_PAYLOAD_HOME = $Case.Home; PAYLOAD_EVENTS = $Case.Events
            TEMP = Join-Path $Case.Root 'tmp'; TMP = Join-Path $Case.Root 'tmp'; TMPDIR = Join-Path $Case.Root 'tmp'
            FAKE_KIT_STATUS = $null; FAKE_PYMOL_STATUS = $null; DOTFILES_PAYLOAD_AUTO_UPDATE = $null
            DOTFILES_PAYLOAD_ITEMS = $null; _DOTFILES_PAYLOAD_CHECKED = $null }
        foreach ($key in $Environment.Keys) { $values[$key] = $Environment[$key] }
        foreach ($key in $values.Keys) { [Environment]::SetEnvironmentVariable($key, $values[$key]) }
        $output = & $pwsh -NoProfile -NonInteractive -File $hook @Arguments 2>&1 | ForEach-Object { "$_" }
        return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($output -join "`n") }
    }
    function Get-Events($Case) { @([IO.File]::ReadAllLines($Case.Events)) -join "`n" }
    function Clear-Events($Case) { [IO.File]::WriteAllText($Case.Events, '') }
    function Set-StampAge($Case, [string]$Name, [long]$Seconds) {
        [void][IO.Directory]::CreateDirectory($Case.State)
        [IO.File]::WriteAllText((Join-Path $Case.State "$Name.stamp"), "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $Seconds)`n")
    }
    function Wait-Worker($Case) {
        $pidFile = Join-Path $Case.State 'worker.pid'
        Assert-True (Test-Path -LiteralPath $pidFile) 'no background run was started'
        $process = Get-Process -Id ([int](([IO.File]::ReadAllText($pidFile).Trim() -split '\s+')[0])) -ErrorAction SilentlyContinue
        if ($process) { Assert-True ($process.WaitForExit(20000)) 'the background run did not finish' }
    }
    $installAll = "kit-install [-Channel 0.6]`npymol-install []`nskills-install []"

    Test-Case '-Now installs absent items in config order on the declared channel and stamps them' {
        $case = New-Case
        $run = Invoke-Hook $case @('-Now')
        Assert-True ($run.Code -eq 0) $run.Text
        Assert-True ((Get-Events $case) -ceq $installAll) "events: $(Get-Events $case)"
        foreach ($name in 'kit', 'pymol', 'skills') {
            Assert-True (Test-Path -LiteralPath (Join-Path $case.State "$name.stamp")) "no $name stamp"
        }
        Assert-True ($run.Text.Contains('[dotfiles] [step] kit: installing (later updates run in the background)')) $run.Text
        Clear-Events $case
        $run = Invoke-Hook $case @('-Now', 'kit')
        Assert-True ($run.Code -eq 0 -and (Get-Events $case) -ceq 'kit-update [-Update True -Channel 0.6]') "update: $(Get-Events $case) $($run.Text)"
        Assert-True (-not @(Get-ChildItem -LiteralPath (Join-Path $case.Root 'tmp') -Filter 'dotfiles-payload-*').Count) 'a download was left behind'
    }
    Test-Case '-Now fails for a failed or unknown item, records nothing for it and calls exit 75 neither' {
        $case = New-Case
        $run = Invoke-Hook $case @('-Now', 'pymol', 'kit') @{ FAKE_KIT_STATUS = '3' }
        Assert-True ($run.Code -eq 1) "exit $($run.Code): $($run.Text)"
        Assert-True ($run.Text.Contains('kit: install failed (exit 3); retry with: sync-payloads kit')) $run.Text
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $case.State 'kit.stamp')) -and (Test-Path -LiteralPath (Join-Path $case.State 'pymol.stamp'))) 'wrong stamps'
        $run = Invoke-Hook $case @('-Now', 'pymol') @{ FAKE_PYMOL_STATUS = '75' }
        Assert-True ($run.Code -eq 0 -and $run.Text.Contains('pymol: another run holds its lock')) "exit 75: $($run.Text)"
        $run = Invoke-Hook $case @('-Now', 'nope')
        Assert-True ($run.Code -eq 1 -and $run.Text.Contains("unknown item 'nope'")) $run.Text
    }
    Test-Case 'a download that fails runs nothing' {
        $case = New-Case
        $source = Join-Path $remote 'PyMOLScripts/main/install.ps1'
        Move-Item -LiteralPath $source -Destination "$source.hidden"
        try { $run = Invoke-Hook $case @('-Now', 'pymol') }
        finally { Move-Item -LiteralPath "$source.hidden" -Destination $source }
        Assert-True ($run.Code -eq 1 -and $run.Text.Contains('cannot run')) $run.Text
        Assert-True ((Get-Events $case) -ceq '') "events: $(Get-Events $case)"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $case.State 'pymol.stamp'))) 'a failed download was stamped'
    }
    Test-Case 'the profile call needs a console, runs once per session and obeys the opt-out' {
        $case = New-Case
        # Redirected here, as under every pwsh -Command: nothing runs, and the
        # session is not marked.
        $run = Invoke-Hook $case @()
        Assert-True ($run.Code -eq 0 -and (Get-Events $case) -ceq '') "redirected call ran: $(Get-Events $case)"
        $run = Invoke-Hook $case @('-Now') @{ DOTFILES_PAYLOAD_AUTO_UPDATE = '0' }
        Assert-True ($run.Code -eq 0 -and (Get-Events $case) -ceq $installAll) '-Now must ignore the opt-out'
    }
    if ($elevated) {
        Test-Case 'an elevated automatic run installs nothing and says where to install' {
            $case = New-Case
            $run = Invoke-Hook $case @('-Auto')
            Assert-True ($run.Code -eq 0 -and (Get-Events $case) -ceq '') "elevated run installed: $(Get-Events $case)"
            Assert-True ($run.Text.Contains('kit is not installed; an unelevated PowerShell installs it')) $run.Text
        }
        Write-Output 'SKIP: unelevated automatic runs (this session is elevated)'
    }
    else {
        Test-Case 'an automatic run installs absent items in the foreground and starts no background run' {
            $case = New-Case
            $run = Invoke-Hook $case @('-Auto')
            Assert-True ($run.Code -eq 0 -and (Get-Events $case) -ceq $installAll) "events: $(Get-Events $case) $($run.Text)"
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $case.State 'worker.pid'))) 'a first install started a background run'
            Clear-Events $case
            $run = Invoke-Hook $case @('-Auto')
            Assert-True ($run.Code -eq 0 -and (Get-Events $case) -ceq '') "a fresh install ran again: $(Get-Events $case)"
            $run = Invoke-Hook $case @('-Auto') @{ DOTFILES_PAYLOAD_ITEMS = '' }
            Assert-True ((Get-Events $case) -ceq '') 'an empty selection ran an item'
        }
        Test-Case 'due items refresh in one detached background run that writes the log' {
            $case = New-Case
            [void](Invoke-Hook $case @('-Now'))
            Clear-Events $case
            Set-StampAge $case kit 86400
            Set-StampAge $case pymol 3600
            Set-StampAge $case skills (6 * 86400)
            $run = Invoke-Hook $case @('-Auto')
            Assert-True ($run.Code -eq 0 -and -not $run.Text.Contains('[dotfiles]')) "a background refresh printed: $($run.Text)"
            Wait-Worker $case
            Assert-True ((Get-Events $case) -ceq 'kit-update [-Update True -Channel 0.6]') "events: $(Get-Events $case)"
            $log = [IO.File]::ReadAllText((Join-Path $case.State 'payload.log'))
            Assert-True ($log.Contains('kit: update done')) "log: $log"
            # A live background run keeps a second one from starting.
            $sleeper = Start-Process -FilePath $pwsh -ArgumentList '-NoProfile', '-Command', 'Start-Sleep -Seconds 30' -PassThru
            try {
                [IO.File]::WriteAllText((Join-Path $case.State 'worker.pid'), "$($sleeper.Id)`n")
                Set-StampAge $case kit 86400
                Clear-Events $case
                [void](Invoke-Hook $case @('-Auto'))
                Start-Sleep -Seconds 2
                Assert-True ((Get-Events $case) -ceq '') "a second background run started: $(Get-Events $case)"
            }
            finally { Stop-Process -Id $sleeper.Id -Force -ErrorAction SilentlyContinue }
        }
        Test-Case 'a failed first install writes no stamp, so the next session retries it' {
            $case = New-Case
            $run = Invoke-Hook $case @('-Auto') @{ DOTFILES_PAYLOAD_ITEMS = 'kit'; FAKE_KIT_STATUS = '1' }
            Assert-True ($run.Code -eq 0 -and $run.Text.Contains('kit: install failed (exit 1)')) $run.Text
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $case.State 'kit.stamp'))) 'a failed install was stamped'
            Clear-Events $case
            [void](Invoke-Hook $case @('-Auto') @{ DOTFILES_PAYLOAD_ITEMS = 'kit' })
            Assert-True ((Get-Events $case) -ceq 'kit-install [-Channel 0.6]') "no retry: $(Get-Events $case)"
        }
    }
    Write-Output "payload-update-ps=PASS ($script:Passed cases)"
}
finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    Get-ChildItem -LiteralPath $testRoot -Recurse -Filter 'worker.pid' -ErrorAction SilentlyContinue | ForEach-Object {
        $id = 0
        if ([int]::TryParse(([IO.File]::ReadAllText($_.FullName).Trim() -split '\s+')[0], [ref]$id)) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    }
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
