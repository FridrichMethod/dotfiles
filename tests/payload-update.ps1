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
$names = @('LOCALAPPDATA', 'DOTFILES_TEST_PAYLOAD_HOME', 'PAYLOAD_EVENTS', 'FAKE_PYMOL_STATUS', 'FAKE_SKILLS_STATUS',
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
    Assert-True ($config.Contains('https://raw.githubusercontent.com/FridrichMethod/PyMOLScripts/main/install.ps1')) 'config/payloads.tsv no longer downloads PyMOLScripts from raw.githubusercontent.com/FridrichMethod'
    # coding-agent-kit installs nothing on native Windows (0.7 and later).
    Assert-True (-not ($config -match "(?m)^kit`twindows-")) 'config/payloads.tsv has a windows row for the kit, which does not install on native Windows'
    $config = $config.Replace('https://raw.githubusercontent.com/FridrichMethod/', $base).Replace('Join-Path $HOME ', 'Join-Path $env:DOTFILES_TEST_PAYLOAD_HOME ')
    Assert-True (-not ($config -match 'https?://')) 'config/payloads.tsv names a URL outside raw.githubusercontent.com/FridrichMethod'
    # Rows only this fixture has, so the generic fields keep their coverage
    # now that no Windows item of the real file uses them: an update command
    # that runs an installed script (skills), and a stow-links row (pymol;
    # the kit's on Unix) at a path no real home has, since PowerShell's $HOME
    # on Windows is the account's profile.
    $config = $config.TrimEnd() + "`n" +
        "skills`twindows-update`tInvoke-DotfilesPayloadScript (Join-Path `$env:LOCALAPPDATA 'awesome-skills/update.ps1') -Update`n" +
        "pymol`tstow-links`tpymol .dotfiles-test-legacy-pymolrc`n"
    Write-Fixture (Join-Path $fixture 'config/payloads.tsv') $config
    Write-Fixture (Join-Path $fixture 'scripts/payload-update.ps1') ([IO.File]::ReadAllText((Join-Path $repoRoot 'scripts/payload-update.ps1')))
    Write-Fixture (Join-Path $fixture 'lib/terminal.ps1') ([IO.File]::ReadAllText((Join-Path $repoRoot 'lib/terminal.ps1')))
    $hook = Join-Path $fixture 'scripts/payload-update.ps1'
    # PyMOLScripts' and awesome-skills' installers read a configs/ or scripts/
    # directory beside themselves as a checkout's, so their fakes record the
    # directory they run from and its entries. The skills fake also leaves
    # the installed update script of the fixture's windows-update row.
    Write-Fixture (Join-Path $remote 'PyMOLScripts/main/install.ps1') @'
Add-Content -LiteralPath $env:PAYLOAD_EVENTS -Value "pymol-install [$args]"
$here = Split-Path -Parent $PSCommandPath
$mode = if ($IsWindows) { '-' } else { "$(& ls -ld $here)".Substring(0, 10) }
[IO.File]::WriteAllLines("$env:PAYLOAD_EVENTS.pymol-dir", [string[]]@($here, $mode, ((Get-ChildItem -LiteralPath $here -Force -Name) -join ' ')))
if ($env:FAKE_PYMOL_STATUS -and $env:FAKE_PYMOL_STATUS -ne '0') { exit ([int]$env:FAKE_PYMOL_STATUS) }
foreach ($name in '.pymolrc', '.pymolrc.py') { [IO.File]::WriteAllText((Join-Path $env:DOTFILES_TEST_PAYLOAD_HOME $name), '') }
'@
    Write-Fixture (Join-Path $remote 'awesome-skills/main/install.ps1') @'
Add-Content -LiteralPath $env:PAYLOAD_EVENTS -Value "skills-install [$args]"
$here = Split-Path -Parent $PSCommandPath
$mode = if ($IsWindows) { '-' } else { "$(& ls -ld $here)".Substring(0, 10) }
[IO.File]::WriteAllLines("$env:PAYLOAD_EVENTS.skills-dir", [string[]]@($here, $mode, ((Get-ChildItem -LiteralPath $here -Force -Name) -join ' ')))
if ($env:FAKE_SKILLS_STATUS -and $env:FAKE_SKILLS_STATUS -ne '0') { exit ([int]$env:FAKE_SKILLS_STATUS) }
$root = Join-Path $env:LOCALAPPDATA 'awesome-skills'
[void][IO.Directory]::CreateDirectory((Join-Path $root 'library'))
[IO.File]::WriteAllText((Join-Path $root 'update.ps1'), @"
param([switch]`$Update)
Add-Content -LiteralPath `$env:PAYLOAD_EVENTS -Value "skills-update [-Update `$Update]"
Write-Output 'skills-update: fake output'
if (`$env:FAKE_SKILLS_STATUS -and `$env:FAKE_SKILLS_STATUS -ne '0') { exit ([int]`$env:FAKE_SKILLS_STATUS) }
"@)
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
            FAKE_PYMOL_STATUS = $null; FAKE_SKILLS_STATUS = $null; DOTFILES_PAYLOAD_AUTO_UPDATE = $null
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
    # The default items are those with a windows-install row, in config order.
    $installAll = "pymol-install []`nskills-install []"

    Test-Case '-Now installs the items with a windows-install row in config order and stamps them; an installed one runs its update row' {
        $case = New-Case
        $run = Invoke-Hook $case @('-Now')
        Assert-True ($run.Code -eq 0) $run.Text
        Assert-True ((Get-Events $case) -ceq $installAll) "events: $(Get-Events $case); output: $($run.Text)"
        foreach ($name in 'pymol', 'skills') {
            Assert-True (Test-Path -LiteralPath (Join-Path $case.State "$name.stamp")) "no $name stamp"
        }
        Assert-True ($run.Text.Contains('[dotfiles] [step] pymol: installing (later updates run in the background)')) $run.Text
        Assert-True (-not $run.Text.Contains('kit')) "the default items named the kit: $($run.Text)"
        Clear-Events $case
        $run = Invoke-Hook $case @('-Now', 'skills', 'pymol')
        Assert-True ($run.Code -eq 0 -and (Get-Events $case) -ceq "skills-update [-Update True]`npymol-install []") "update: $(Get-Events $case); output: $($run.Text)"
        Assert-True (-not @(Get-ChildItem -LiteralPath (Join-Path $case.Root 'tmp') -Filter 'dotfiles-payload-*').Count) 'a download was left behind'
    }
    Test-Case 'the kit is not available on native Windows: a run that names it says so, runs nothing for it and records nothing' {
        $case = New-Case
        $run = Invoke-Hook $case @('-Now', 'kit')
        Assert-True ($run.Code -eq 0 -and $run.Text.Contains('[dotfiles] [info] kit: not available on native Windows')) "exit $($run.Code): $($run.Text)"
        Assert-True ((Get-Events $case) -ceq '' -and (Get-Record $case kit) -ceq '' -and -not (Test-Path -LiteralPath (Join-Path $case.State 'kit.stamp'))) "events: $(Get-Events $case)"
        $run = Invoke-Hook $case @('-Now', 'kit', 'pymol')
        Assert-True ($run.Code -eq 0 -and (Get-Events $case) -ceq 'pymol-install []') "events: $(Get-Events $case); output: $($run.Text)"
        # The automatic run leaves it out without a word, also with a v0.6
        # failure record still in the state directory.
        [IO.File]::WriteAllText((Join-Path $case.State 'kit.failed'), "1700000000 1`n")
        Clear-Events $case
        $run = Invoke-Hook $case @('-Auto') @{ DOTFILES_PAYLOAD_ITEMS = 'kit skills' }
        Assert-True ($run.Code -eq 0 -and -not $run.Text.Contains('kit')) "the automatic run named the kit: $($run.Text)"
        Assert-True ($elevated -or (Get-Events $case) -ceq 'skills-install []') "events: $(Get-Events $case); output: $($run.Text)"
        $run = Invoke-Hook $case @('-Auto')
        Assert-True ($run.Code -eq 0 -and -not $run.Text.Contains('kit')) "the automatic run named the kit: $($run.Text)"
    }
    Test-Case '-Now fails for a failed or unknown item and records the failure; exit 75 is neither' {
        $case = New-Case
        $run = Invoke-Hook $case @('-Now', 'pymol', 'skills') @{ FAKE_SKILLS_STATUS = '4' }
        Assert-True ($run.Code -eq 1) "exit $($run.Code): $($run.Text)"
        Assert-True ($run.Text.Contains('skills: install failed (exit 4); retry with: sync-payloads skills')) $run.Text
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $case.State 'skills.stamp')) -and (Test-Path -LiteralPath (Join-Path $case.State 'pymol.stamp'))) 'wrong stamps'
        Assert-True ((Get-Record $case skills) -match '^\d+ 4\n') "skills record: $(Get-Record $case skills)"
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
        # Another exit of an item with that row is an ordinary failure.
        [void](Invoke-Hook $case @('-Now', 'pymol') @{ FAKE_PYMOL_STATUS = '4' })
        Clear-Events $case
        $run = Invoke-Hook $case @('-Auto') @{ DOTFILES_PAYLOAD_ITEMS = 'skills pymol' }
        $records = Join-Path $case.State 'skills.failed'
        Assert-True ($run.Text.Contains("skills: its last run stopped for a person (exit 3, see $records); run sync-payloads skills and do what it asks")) $run.Text
        Assert-True ($run.Text.Contains('pymol: its last run failed (exit 4, see ')) $run.Text
        Assert-True ((Get-Events $case) -ceq '') "a fresh failure was retried: $(Get-Events $case)"
        # PyMOLScripts' 3: a locally edited rc file it leaves alone.
        $run = Invoke-Hook $case @('-Now', 'pymol') @{ FAKE_PYMOL_STATUS = '3' }
        Assert-True ($run.Code -eq 1 -and $run.Text.Contains('pymol: stopped for a person (exit 3): do what its message says, then run sync-payloads pymol')) $run.Text
        $run = Invoke-Hook $case @('-Auto') @{ DOTFILES_PAYLOAD_ITEMS = 'pymol' }
        Assert-True ($run.Text.Contains('pymol: its last run stopped for a person (exit 3, see ')) $run.Text
        $run = Invoke-Hook $case @('-Now', 'skills')
        Assert-True ($run.Code -eq 0 -and (Get-Record $case skills) -ceq '') "a success kept the record: $($run.Text)"
    }
    Test-Case 'a download runs alone in a fresh private directory, removed afterwards' {
        # What another user planted in a shared temporary directory is never
        # beside the installer.
        $case = New-Case
        $temporary = Join-Path $case.Root 'tmp'
        Write-Fixture (Join-Path $temporary 'configs/.pymolrc.py') 'planted'
        Write-Fixture (Join-Path $temporary 'scripts/install_skills.py') 'planted'
        $run = Invoke-Hook $case @('-Now', 'pymol', 'skills')
        Assert-True ($run.Code -eq 0) $run.Text
        foreach ($name in 'pymol', 'skills') {
            $record = @([IO.File]::ReadAllLines("$($case.Events).$name-dir"))
            # A fresh directory beside the planted ones, whatever spelling of
            # the temporary path (a Windows short name) the run saw.
            Assert-True ((Split-Path -Leaf $record[0]) -like 'dotfiles-payload-*' -and
                (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $record[0]) 'configs/.pymolrc.py'))) "$name ran from $($record[0])"
            Assert-True ($IsWindows -or $record[1] -ceq 'drwx------') "$name ran from a directory with mode $($record[1])"
            Assert-True ($record[2] -ceq 'install.ps1') "$name's directory held more than its script: $($record[2])"
            Assert-True (-not (Test-Path -LiteralPath $record[0])) "$name's staging directory was left behind"
        }
        $run = Invoke-Hook $case @('-Now', 'pymol') @{ FAKE_PYMOL_STATUS = '1' }
        $here = @([IO.File]::ReadAllLines("$($case.Events).pymol-dir"))[0]
        Assert-True ($run.Code -eq 1 -and -not (Test-Path -LiteralPath $here)) 'a failed installer left its staging directory behind'
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
    Test-Case 'a missing installed script runs nothing and is recorded' {
        $case = New-Case
        [void](Invoke-Hook $case @('-Now', 'skills'))
        Remove-Item -LiteralPath (Join-Path $case.Data 'awesome-skills/update.ps1')
        Clear-Events $case
        $run = Invoke-Hook $case @('-Now', 'skills')
        Assert-True ($run.Code -eq 1 -and $run.Text.Contains('update.ps1 is missing')) $run.Text
        Assert-True ((Get-Events $case) -ceq '' -and (Get-Record $case skills) -match '^\d+ 1\n') "events: $(Get-Events $case); record: $(Get-Record $case skills)"
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
            Assert-True ($run.Code -eq 1 -and $run.Text.Contains("cannot run http://127.0.0.1:$port/PyMOLScripts/main/install.ps1")) $run.Text
            Assert-True ($run.Text.Contains("cannot run http://127.0.0.1:$port/awesome-skills/main/install.ps1: skipped: a download already failed in this run")) $run.Text
            foreach ($name in 'pymol', 'skills') { Assert-True ([bool](Get-Record $case $name)) "no $name record" }
            $run = Invoke-Hook $case @('-Auto') @{ DOTFILES_PAYLOAD_TIMEOUT = '3' } (Join-Path $stalled 'scripts/payload-update.ps1')
            Assert-True (-not $run.Text.Contains('cannot run') -and $run.Text.Contains('pymol: its last run failed (exit 1, see ')) "no back-off: $($run.Text)"
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
    if ($IsWindows) { Write-Output 'SKIP: a legacy Stow link (PowerShell $HOME cannot be redirected on Windows)' }
    else {
        Test-Case 'a stow-links path still linked into its retired package waits for stow-all without running the installer' {
            $case = New-Case
            # Dangling, as the pull leaves it; ln makes one on every Unix.
            & ln -s '../dotfiles/common/pymol/.pymolrc' (Join-Path $case.Home '.dotfiles-test-legacy-pymolrc')
            $run = Invoke-Hook $case @('-Now', 'pymol', 'skills')
            Assert-True ($run.Code -eq 1 -and $run.Text.Contains('pymol: ~/.dotfiles-test-legacy-pymolrc is still a link the retired Stow package made, which its installer refuses; run stow-all.ps1')) $run.Text
            Assert-True ((Get-Events $case) -ceq 'skills-install []' -and (Get-Record $case pymol) -ceq '') "events: $(Get-Events $case)"
        }
    }
    if ($elevated) {
        Test-Case 'an elevated automatic run installs nothing and says where to install' {
            $case = New-Case
            $run = Invoke-Hook $case @('-Auto')
            Assert-True ($run.Code -eq 0 -and (Get-Events $case) -ceq '') "elevated run installed: $(Get-Events $case)"
            Assert-True ($run.Text.Contains('pymol is not installed; an unelevated PowerShell installs it')) $run.Text
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
        Test-Case 'due items refresh in one detached background run that writes the log, each by its own interval' {
            $case = New-Case
            [void](Invoke-Hook $case @('-Now'))
            Clear-Events $case
            Set-StampAge $case pymol 86400
            Set-StampAge $case skills (6 * 86400)
            $run = Invoke-Hook $case @('-Auto')
            Assert-True ($run.Code -eq 0 -and -not $run.Text.Contains('[dotfiles]')) "a background refresh printed: $($run.Text)"
            $log = Join-Path $case.State 'payload.log'
            Wait-Until { [IO.File]::Exists($log) -and [IO.File]::ReadAllText($log).Contains('pymol: update done') } 'the background refresh'
            Assert-True ((Get-Events $case) -ceq 'pymol-install []') "events: $(Get-Events $case); output: $($run.Text)"
            Clear-Events $case
            Set-StampAge $case skills (7 * 86400)
            [void](Invoke-Hook $case @('-Auto'))
            Wait-Until { [IO.File]::Exists($log) -and [IO.File]::ReadAllText($log).Contains('skills: update done') } 'the second background refresh'
            Assert-True ((Get-Events $case) -ceq 'skills-update [-Update True]') "events: $(Get-Events $case)"
        }
        Test-Case 'a failure backs off for six hours, then retries in the background; a background failure keeps its output' {
            $case = New-Case
            $run = Invoke-Hook $case @('-Auto') @{ DOTFILES_PAYLOAD_ITEMS = 'skills'; FAKE_SKILLS_STATUS = '1' }
            Assert-True ($run.Code -eq 0 -and $run.Text.Contains('skills: install failed (exit 1)')) $run.Text
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $case.State 'skills.stamp')) -and (Get-Record $case skills)) 'a failed install was stamped or not recorded'
            Clear-Events $case
            $run = Invoke-Hook $case @('-Auto') @{ DOTFILES_PAYLOAD_ITEMS = 'skills' }
            Assert-True ((Get-Events $case) -ceq '' -and $run.Text.Contains('skills: its last run failed (exit 1, see ')) "no back-off: $(Get-Events $case) $($run.Text)"
            [IO.File]::WriteAllText((Join-Path $case.State 'skills.failed'), "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 21600) 1`n")
            [void](Invoke-Hook $case @('-Auto') @{ DOTFILES_PAYLOAD_ITEMS = 'skills' })
            Wait-Until { Test-Path -LiteralPath (Join-Path $case.State 'skills.stamp') } 'the background retry'
            Wait-Until { (Get-Record $case skills) -ceq '' } 'the cleared record'
            Assert-True ((Get-Events $case) -ceq 'skills-install []') "retry: $(Get-Events $case)"
            Set-StampAge $case skills (7 * 86400)
            [void](Invoke-Hook $case @('-Auto') @{ DOTFILES_PAYLOAD_ITEMS = 'skills'; FAKE_SKILLS_STATUS = '4' })
            Wait-Until { (Get-Record $case skills).Contains('skills-update: fake output') } 'the failure record with its output'
            Assert-True ((Get-Record $case skills) -match '^\d+ 4\n' -and (Get-Record $case skills).Contains('skills: update failed (exit 4)')) "record: $(Get-Record $case skills)"
        }
    }
    Write-Output "payload-update-ps=PASS ($script:Passed cases)"
}
finally {
    foreach ($name in $names) { Set-TestVariable $name $saved[$name] }
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
