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
$names = @('LOCALAPPDATA', 'DOTFILES_TEST_PAYLOAD_HOME', 'PAYLOAD_EVENTS', 'FAKE_KIT_STATUS', 'FAKE_PYMOL_STATUS', 'FAKE_SKILLS_STATUS',
    'DOTFILES_PAYLOAD_AUTO_UPDATE', 'DOTFILES_PAYLOAD_ITEMS', '_DOTFILES_PAYLOAD_CHECKED', 'DOTFILES_PAYLOAD_TIMEOUT',
    'TEMP', 'TMP', 'TMPDIR', 'HOME')
$saved = @{}
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
$script:Passed = 0
$script:Case = 0

# Set a process variable, or remove it for $null: PowerShell passes $null to
# a .NET string parameter as '', so SetEnvironmentVariable would leave an
# empty variable, which the hook reads as a selection of no items.
function Set-TestVariable([string]$Name, $Value) {
    if ($null -eq $Value) { Remove-Item -LiteralPath "Env:$Name" -ErrorAction Ignore }
    else { [Environment]::SetEnvironmentVariable($Name, [string]$Value) }
}
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
    # file:///C:/... or file:///tmp/..., with a trailing slash. Built by hand:
    # a [Uri] cast reads a Unix path as a relative URI.
    $slashed = $remote.Replace('\', '/')
    $base = 'file://' + $(if ($slashed.StartsWith('/')) { '' } else { '/' }) + $slashed + '/'
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
Write-Output 'kit-update: fake output'
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
if ($env:FAKE_SKILLS_STATUS -and $env:FAKE_SKILLS_STATUS -ne '0') { exit ([int]$env:FAKE_SKILLS_STATUS) }
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
    # adds or ($null) removes variables. Off Windows HOME is the case's home
    # too (PowerShell's $HOME follows it there, not on Windows).
    function Invoke-Hook($Case, [string[]]$Arguments, [hashtable]$Environment = @{}, [string]$Hook = $hook) {
        $values = @{ LOCALAPPDATA = $Case.Data; DOTFILES_TEST_PAYLOAD_HOME = $Case.Home; PAYLOAD_EVENTS = $Case.Events
            TEMP = Join-Path $Case.Root 'tmp'; TMP = Join-Path $Case.Root 'tmp'; TMPDIR = Join-Path $Case.Root 'tmp'
            FAKE_KIT_STATUS = $null; FAKE_PYMOL_STATUS = $null; FAKE_SKILLS_STATUS = $null; DOTFILES_PAYLOAD_AUTO_UPDATE = $null
            DOTFILES_PAYLOAD_ITEMS = $null; _DOTFILES_PAYLOAD_CHECKED = $null; DOTFILES_PAYLOAD_TIMEOUT = $null }
        if (-not $IsWindows) { $values['HOME'] = $Case.Home }
        foreach ($key in $Environment.Keys) { $values[$key] = $Environment[$key] }
        foreach ($key in $values.Keys) { Set-TestVariable $key $values[$key] }
        $output = & $pwsh -NoProfile -NonInteractive -File $Hook @Arguments 2>&1 | ForEach-Object { "$_" }
        return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($output -join "`n") }
    }
    function Get-Events($Case) { @([IO.File]::ReadAllLines($Case.Events)) -join "`n" }
    function Clear-Events($Case) { [IO.File]::WriteAllText($Case.Events, '') }
    function Set-StampAge($Case, [string]$Name, [long]$Seconds) {
        [void][IO.Directory]::CreateDirectory($Case.State)
        [IO.File]::WriteAllText((Join-Path $Case.State "$Name.stamp"), "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $Seconds)`n")
    }
    # The background run is detached: wait for what it leaves.
    function Wait-Until([scriptblock]$Condition, [string]$Message) {
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        while (-not (& $Condition)) {
            if ([DateTime]::UtcNow -gt $deadline) { throw "timed out waiting for $Message" }
            Start-Sleep -Milliseconds 100
        }
    }
    function Get-Record($Case, [string]$Name) {
        $path = Join-Path $Case.State "$Name.failed"
        if ([IO.File]::Exists($path)) { [IO.File]::ReadAllText($path) } else { '' }
    }
    $installAll = "kit-install [-Channel 0.6]`npymol-install []`nskills-install []"

    Test-Case '-Now installs absent items in config order on the declared channel and stamps them' {
        $case = New-Case
        $run = Invoke-Hook $case @('-Now')
        Assert-True ($run.Code -eq 0) $run.Text
        Assert-True ((Get-Events $case) -ceq $installAll) "events: $(Get-Events $case); output: $($run.Text)"
        foreach ($name in 'kit', 'pymol', 'skills') {
            Assert-True (Test-Path -LiteralPath (Join-Path $case.State "$name.stamp")) "no $name stamp"
        }
        Assert-True ($run.Text.Contains('[dotfiles] [step] kit: installing (later updates run in the background)')) $run.Text
        Clear-Events $case
        $run = Invoke-Hook $case @('-Now', 'kit')
        Assert-True ($run.Code -eq 0 -and (Get-Events $case) -ceq 'kit-update [-Update True -Channel 0.6]') "update: $(Get-Events $case); output: $($run.Text)"
        Assert-True (-not @(Get-ChildItem -LiteralPath (Join-Path $case.Root 'tmp') -Filter 'dotfiles-payload-*').Count) 'a download was left behind'
    }
    Test-Case '-Now fails for a failed or unknown item and records the failure; exit 75 is neither' {
        $case = New-Case
        $run = Invoke-Hook $case @('-Now', 'pymol', 'kit') @{ FAKE_KIT_STATUS = '3' }
        Assert-True ($run.Code -eq 1) "exit $($run.Code): $($run.Text)"
        Assert-True ($run.Text.Contains('kit: install failed (exit 3); retry with: sync-payloads kit')) $run.Text
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $case.State 'kit.stamp')) -and (Test-Path -LiteralPath (Join-Path $case.State 'pymol.stamp'))) 'wrong stamps'
        Assert-True ((Get-Record $case kit) -match '^\d+ 3\n') "kit record: $(Get-Record $case kit)"
        $run = Invoke-Hook $case @('-Now', 'pymol') @{ FAKE_PYMOL_STATUS = '75' }
        Assert-True ($run.Code -eq 0 -and $run.Text.Contains('pymol: another run holds its lock')) "exit 75: $($run.Text)"
        Assert-True ((Get-Record $case pymol) -ceq '') 'exit 75 was recorded'
        $run = Invoke-Hook $case @('-Now', 'nope')
        Assert-True ($run.Code -eq 1 -and $run.Text.Contains("unknown item 'nope'")) $run.Text
    }
    Test-Case 'a failure is reported by every later session, worded by person-status, until a success' {
        $case = New-Case
        $run = Invoke-Hook $case @('-Now', 'skills') @{ FAKE_SKILLS_STATUS = '3' }
        Assert-True ($run.Code -eq 1) "exit $($run.Code): $($run.Text)"
        Assert-True ($run.Text.Contains('skills: stopped for a person (exit 3): do what its message says, then run sync-payloads skills')) $run.Text
        [void](Invoke-Hook $case @('-Now', 'kit') @{ FAKE_KIT_STATUS = '3' })
        Clear-Events $case
        $run = Invoke-Hook $case @('-Auto') @{ DOTFILES_PAYLOAD_ITEMS = 'skills kit' }
        $records = Join-Path $case.State 'skills.failed'
        Assert-True ($run.Text.Contains("skills: its last run stopped for a person (exit 3, see $records); run sync-payloads skills and do what it asks")) $run.Text
        Assert-True ($run.Text.Contains('kit: its last run failed (exit 3, see ')) $run.Text
        Assert-True ((Get-Events $case) -ceq '') "a fresh failure was retried: $(Get-Events $case)"
        $run = Invoke-Hook $case @('-Now', 'skills')
        Assert-True ($run.Code -eq 0 -and (Get-Record $case skills) -ceq '') "a success kept the record: $($run.Text)"
    }
    Test-Case 'a download that fails runs nothing and is recorded' {
        $case = New-Case
        $source = Join-Path $remote 'PyMOLScripts/main/install.ps1'
        Move-Item -LiteralPath $source -Destination "$source.hidden"
        try { $run = Invoke-Hook $case @('-Now', 'pymol') }
        finally { Move-Item -LiteralPath "$source.hidden" -Destination $source }
        Assert-True ($run.Code -eq 1 -and $run.Text.Contains('cannot run')) $run.Text
        Assert-True ((Get-Events $case) -ceq '') "events: $(Get-Events $case); output: $($run.Text)"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $case.State 'pymol.stamp')) -and (Get-Record $case pymol)) 'a failed download was stamped or not recorded'
    }
    Test-Case 'a stalled download ends within the timeout and the run tries no other; the next session backs off' {
        # A loopback port that accepts connections and never answers.
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        $listener.Start()
        try {
            $stalled = Join-Path $testRoot 'stalled'
            $port = $listener.LocalEndpoint.Port
            Write-Fixture (Join-Path $stalled 'config/payloads.tsv') ([IO.File]::ReadAllText((Join-Path $fixture 'config/payloads.tsv')).Replace($base, "http://127.0.0.1:$port/"))
            Write-Fixture (Join-Path $stalled 'scripts/payload-update.ps1') ([IO.File]::ReadAllText($hook))
            Write-Fixture (Join-Path $stalled 'lib/terminal.ps1') ([IO.File]::ReadAllText((Join-Path $fixture 'lib/terminal.ps1')))
            $case = New-Case
            $clock = [Diagnostics.Stopwatch]::StartNew()
            $run = Invoke-Hook $case @('-Now') @{ DOTFILES_PAYLOAD_TIMEOUT = '3' } (Join-Path $stalled 'scripts/payload-update.ps1')
            $clock.Stop()
            Assert-True ($clock.Elapsed.TotalSeconds -lt 9) "a stalled download held the run for $($clock.Elapsed.TotalSeconds)s"
            Assert-True ($run.Code -eq 1 -and $run.Text.Contains("cannot run http://127.0.0.1:$port/coding-agent-kit/main/install.ps1")) $run.Text
            Assert-True ($run.Text.Contains("cannot run http://127.0.0.1:$port/PyMOLScripts/main/install.ps1: skipped: a download already failed in this run")) $run.Text
            foreach ($name in 'kit', 'pymol', 'skills') { Assert-True (Get-Record $case $name) "no $name record" }
            $run = Invoke-Hook $case @('-Auto') @{ DOTFILES_PAYLOAD_TIMEOUT = '3' } (Join-Path $stalled 'scripts/payload-update.ps1')
            Assert-True (-not $run.Text.Contains('cannot run') -and $run.Text.Contains('kit: its last run failed (exit 1, see ')) "no back-off: $($run.Text)"
        }
        finally { $listener.Stop() }
    }
    Test-Case 'the profile call needs a console, runs once per session and obeys the opt-out' {
        $case = New-Case
        # Redirected here, as under every pwsh -Command: nothing runs, and the
        # session is not marked.
        $run = Invoke-Hook $case @()
        Assert-True ($run.Code -eq 0 -and (Get-Events $case) -ceq '') "redirected call ran: $(Get-Events $case)"
        $run = Invoke-Hook $case @('-Now') @{ DOTFILES_PAYLOAD_AUTO_UPDATE = '0' }
        Assert-True ($run.Code -eq 0 -and (Get-Events $case) -ceq $installAll) "-Now must ignore the opt-out: $(Get-Events $case); output: $($run.Text)"
    }
    if ($IsWindows) { Write-Output 'SKIP: a legacy kit link (PowerShell $HOME cannot be redirected on Windows)' }
    else {
        Test-Case 'a legacy link at a kit path waits for stow-all without running the installer' {
            $case = New-Case
            [void][IO.Directory]::CreateDirectory((Join-Path $case.Home '.local/bin'))
            # Dangling, as the pull leaves it; ln makes one on every Unix.
            & ln -s '../../dotfiles/common/coding-agent-kit/.local/bin/codex-as' (Join-Path $case.Home '.local/bin/codex-as')
            $run = Invoke-Hook $case @('-Now', 'kit', 'pymol')
            Assert-True ($run.Code -eq 1 -and $run.Text.Contains('kit: ~/.local/bin/codex-as is still a link the retired Stow package made, which its installer refuses; run stow-all.ps1')) $run.Text
            Assert-True ((Get-Events $case) -ceq 'pymol-install []' -and (Get-Record $case kit) -ceq '') "events: $(Get-Events $case)"
        }
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
            # A blank selection manages nothing (an environment variable
            # cannot be empty on Windows, so a space stands for it).
            $run = Invoke-Hook $case @('-Auto') @{ DOTFILES_PAYLOAD_ITEMS = ' ' }
            Assert-True ($run.Code -eq 0 -and (Get-Events $case) -ceq '') "a blank selection ran: $(Get-Events $case); output: $($run.Text)"
            $run = Invoke-Hook $case @('-Auto')
            Assert-True ($run.Code -eq 0 -and (Get-Events $case) -ceq $installAll) "events: $(Get-Events $case); output: $($run.Text)"
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $case.State 'payload.log'))) 'a first install started a background run'
            Clear-Events $case
            $run = Invoke-Hook $case @('-Auto')
            Assert-True ($run.Code -eq 0 -and (Get-Events $case) -ceq '') "a fresh install ran again: $(Get-Events $case); output: $($run.Text)"
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
            $log = Join-Path $case.State 'payload.log'
            Wait-Until { [IO.File]::Exists($log) -and [IO.File]::ReadAllText($log).Contains('kit: update done') } 'the background refresh'
            Assert-True ((Get-Events $case) -ceq 'kit-update [-Update True -Channel 0.6]') "events: $(Get-Events $case); output: $($run.Text)"
        }
        Test-Case 'a failure backs off for six hours, then retries in the background; a background failure keeps its output' {
            $case = New-Case
            $run = Invoke-Hook $case @('-Auto') @{ DOTFILES_PAYLOAD_ITEMS = 'kit'; FAKE_KIT_STATUS = '1' }
            Assert-True ($run.Code -eq 0 -and $run.Text.Contains('kit: install failed (exit 1)')) $run.Text
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $case.State 'kit.stamp')) -and (Get-Record $case kit)) 'a failed install was stamped or not recorded'
            Clear-Events $case
            $run = Invoke-Hook $case @('-Auto') @{ DOTFILES_PAYLOAD_ITEMS = 'kit' }
            Assert-True ((Get-Events $case) -ceq '' -and $run.Text.Contains('kit: its last run failed (exit 1, see ')) "no back-off: $(Get-Events $case) $($run.Text)"
            [IO.File]::WriteAllText((Join-Path $case.State 'kit.failed'), "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 21600) 1`n")
            [void](Invoke-Hook $case @('-Auto') @{ DOTFILES_PAYLOAD_ITEMS = 'kit' })
            Wait-Until { Test-Path -LiteralPath (Join-Path $case.State 'kit.stamp') } 'the background retry'
            Wait-Until { (Get-Record $case kit) -ceq '' } 'the cleared record'
            Assert-True ((Get-Events $case) -ceq 'kit-install [-Channel 0.6]') "retry: $(Get-Events $case)"
            Set-StampAge $case kit 86400
            [void](Invoke-Hook $case @('-Auto') @{ DOTFILES_PAYLOAD_ITEMS = 'kit'; FAKE_KIT_STATUS = '4' })
            Wait-Until { (Get-Record $case kit).Contains('kit-update: fake output') } 'the failure record with its output'
            Assert-True ((Get-Record $case kit) -match '^\d+ 4\n' -and (Get-Record $case kit).Contains('kit: update failed (exit 4)')) "record: $(Get-Record $case kit)"
        }
    }
    Write-Output "payload-update-ps=PASS ($script:Passed cases)"
}
finally {
    foreach ($name in $names) { Set-TestVariable $name $saved[$name] }
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
