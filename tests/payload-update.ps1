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
. (Join-Path $PSScriptRoot 'lib/environment.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot
$pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-payload-ps-' + [Guid]::NewGuid().ToString('N'))
$names = @('LOCALAPPDATA', 'DOTFILES_TEST_PAYLOAD_HOME', 'PAYLOAD_EVENTS', 'FAKE_PYMOL_STATUS', 'FAKE_SKILLS_STATUS',
    'DOTFILES_PAYLOAD_ITEMS', 'DOTFILES_PAYLOAD_TIMEOUT', 'TEMP', 'TMP', 'TMPDIR', 'HOME')
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
    # coding-agent-kit installs nothing on native Windows.
    Assert-True (-not ($config -match "(?m)^kit`twindows-")) 'config/payloads.tsv has a windows row for the kit, which does not install on native Windows'
    $config = $config.Replace('https://raw.githubusercontent.com/FridrichMethod/', $base).Replace('Join-Path $HOME ', 'Join-Path $env:DOTFILES_TEST_PAYLOAD_HOME ')
    Assert-True (-not ($config -match 'https?://')) 'config/payloads.tsv names a URL outside raw.githubusercontent.com/FridrichMethod'
    # A row only this fixture has, so the generic field keeps its coverage
    # now that no Windows item of the real file uses it: an update command
    # that runs an installed script (skills).
    $config = $config.TrimEnd() + "`n" +
        "skills`twindows-update`tInvoke-DotfilesPayloadScript (Join-Path `$env:LOCALAPPDATA 'awesome-skills/update.ps1') -Update`n"
    Write-Fixture (Join-Path $fixture 'config/payloads.tsv') $config
    Write-Fixture (Join-Path $fixture 'scripts/payload-update.ps1') ([IO.File]::ReadAllText((Join-Path $repoRoot 'scripts/payload-update.ps1')))
    Write-Fixture (Join-Path $fixture 'lib/terminal.ps1') ([IO.File]::ReadAllText((Join-Path $repoRoot 'lib/terminal.ps1')))
    $hook = Join-Path $fixture 'scripts/payload-update.ps1'
    # PyMOLScripts' and awesome-skills' installers read a configs/ or scripts/
    # directory beside themselves as a checkout's, so their fakes record the
    # directory they run from, who may enter it (its mode; on Windows its
    # access list) and its entries. Every fake also records the
    # working directory it runs in, as PowerShell and the process see it, and
    # where /proc shows it (Linux) its parent's, the hook's
    # (EVENTS.NAME-cwd). The skills fake also leaves the installed update
    # script of the fixture's windows-update row.
    Write-Fixture (Join-Path $remote 'PyMOLScripts/main/install.ps1') @'
Add-Content -LiteralPath $env:PAYLOAD_EVENTS -Value "pymol-install [$args]"
$here = Split-Path -Parent $PSCommandPath
$mode = if (-not $IsWindows) { "$(& ls -ld $here)".Substring(0, 10) }
else {
    $acl = [IO.FileSystemAclExtensions]::GetAccessControl([IO.DirectoryInfo]::new($here), 'Access')
    "protected=$($acl.AreAccessRulesProtected) " + (@($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) |
        ForEach-Object { "$($_.IdentityReference.Value):$($_.FileSystemRights):$($_.AccessControlType):inherited=$($_.IsInherited)" }) -join ' ')
}
[IO.File]::WriteAllLines("$env:PAYLOAD_EVENTS.pymol-dir", [string[]]@($here, $mode, ((Get-ChildItem -LiteralPath $here -Force -Name) -join ' ')))
$parent = if (Test-Path -LiteralPath /proc/self/cwd) { [IO.FileInfo]::new("/proc/$((Get-Process -Id $PID).Parent.Id)/cwd").LinkTarget } else { '-' }
[IO.File]::WriteAllLines("$env:PAYLOAD_EVENTS.pymol-cwd", [string[]]@((Get-Location).ProviderPath, [Environment]::CurrentDirectory, $parent))
if ($env:FAKE_PYMOL_STATUS -and $env:FAKE_PYMOL_STATUS -ne '0') { exit ([int]$env:FAKE_PYMOL_STATUS) }
foreach ($name in '.pymolrc', '.pymolrc.py') { [IO.File]::WriteAllText((Join-Path $env:DOTFILES_TEST_PAYLOAD_HOME $name), '') }
'@
    Write-Fixture (Join-Path $remote 'awesome-skills/main/install.ps1') @'
Add-Content -LiteralPath $env:PAYLOAD_EVENTS -Value "skills-install [$args]"
$here = Split-Path -Parent $PSCommandPath
$mode = if (-not $IsWindows) { "$(& ls -ld $here)".Substring(0, 10) }
else {
    $acl = [IO.FileSystemAclExtensions]::GetAccessControl([IO.DirectoryInfo]::new($here), 'Access')
    "protected=$($acl.AreAccessRulesProtected) " + (@($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) |
        ForEach-Object { "$($_.IdentityReference.Value):$($_.FileSystemRights):$($_.AccessControlType):inherited=$($_.IsInherited)" }) -join ' ')
}
[IO.File]::WriteAllLines("$env:PAYLOAD_EVENTS.skills-dir", [string[]]@($here, $mode, ((Get-ChildItem -LiteralPath $here -Force -Name) -join ' ')))
$parent = if (Test-Path -LiteralPath /proc/self/cwd) { [IO.FileInfo]::new("/proc/$((Get-Process -Id $PID).Parent.Id)/cwd").LinkTarget } else { '-' }
[IO.File]::WriteAllLines("$env:PAYLOAD_EVENTS.skills-cwd", [string[]]@((Get-Location).ProviderPath, [Environment]::CurrentDirectory, $parent))
if ($env:FAKE_SKILLS_STATUS -and $env:FAKE_SKILLS_STATUS -ne '0') { exit ([int]$env:FAKE_SKILLS_STATUS) }
$root = Join-Path $env:LOCALAPPDATA 'awesome-skills'
[void][IO.Directory]::CreateDirectory((Join-Path $root 'library'))
[IO.File]::WriteAllText((Join-Path $root 'update.ps1'), @"
param([switch]`$Update)
Add-Content -LiteralPath `$env:PAYLOAD_EVENTS -Value "skills-update [-Update `$Update]"
`$parent = if (Test-Path -LiteralPath /proc/self/cwd) { [IO.FileInfo]::new("/proc/`$((Get-Process -Id `$PID).Parent.Id)/cwd").LinkTarget } else { '-' }
[IO.File]::WriteAllLines("`$env:PAYLOAD_EVENTS.skills-update-cwd", [string[]]@((Get-Location).ProviderPath, [Environment]::CurrentDirectory, `$parent))
Write-Output 'skills-update: fake output'
if (`$env:FAKE_SKILLS_STATUS -and `$env:FAKE_SKILLS_STATUS -ne '0') { exit ([int]`$env:FAKE_SKILLS_STATUS) }
"@)
'@
    # The working directory a child started in $PSHOME sees, in the spelling
    # PowerShell and the process report (a symlink resolved, say).
    Push-Location -LiteralPath $PSHOME
    try { $pshomeCwd = @(& $pwsh -NoProfile -NonInteractive -Command '(Get-Location).ProviderPath; [Environment]::CurrentDirectory') }
    finally { Pop-Location }
    Assert-True ($pshomeCwd.Count -eq 2) "cannot read the working directory of a pwsh started in $($PSHOME): $pshomeCwd"
    # Assert that the fake NAME, a download or an installed script, ran in
    # $PSHOME.
    function Assert-RanInPSHome($Case, [string]$Name) {
        $cwd = @([IO.File]::ReadAllLines("$($Case.Events).$Name-cwd"))
        Assert-True ($cwd[0] -eq $pshomeCwd[0] -and $cwd[1] -eq $pshomeCwd[1]) "$Name ran in $($cwd[0]) ($($cwd[1])), not in $PSHOME"
        return $cwd
    }
    # A fresh case: its own LOCALAPPDATA, test home and event log.
    function New-Case {
        $script:Case++
        $root = Join-Path $testRoot "case $script:Case"
        $case = [pscustomobject]@{ Root = $root; Data = Join-Path $root 'localappdata'; Home = Join-Path $root 'home'
            Events = Join-Path $root 'events.log' }
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
            FAKE_PYMOL_STATUS = $null; FAKE_SKILLS_STATUS = $null; DOTFILES_PAYLOAD_ITEMS = $null; DOTFILES_PAYLOAD_TIMEOUT = $null }
        if (-not $IsWindows) { $values['HOME'] = $Case.Home }
        foreach ($key in $Environment.Keys) { $values[$key] = $Environment[$key] }
        foreach ($key in $values.Keys) { Set-TestVariable $key $values[$key] }
        # A merged stderr record must not end the suite under the file's Stop
        # (PowerShell 7.0 and 7.1 apply it to native stderr).
        $ErrorActionPreference = 'Continue'
        $output = & $pwsh -NoProfile -NonInteractive -File $Hook @Arguments 2>&1 | ForEach-Object { "$_" }
        return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($output -join "`n") }
    }
    function Get-Events($Case) { @([IO.File]::ReadAllLines($Case.Events)) -join "`n" }
    function Clear-Events($Case) { [IO.File]::WriteAllText($Case.Events, '') }
    # No run keeps payload state of its own.
    function Assert-NoState($Case, [string]$What) {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $Case.Data 'dotfiles'))) "$What kept payload state"
    }
    # The default items are those with a windows-install row, in config order.
    $installAll = "pymol-install []`nskills-install []"

    Test-Case '-Now installs the items with a windows-install row in config order; an installed one runs its update row' {
        $case = New-Case
        $run = Invoke-Hook $case @('-Now')
        Assert-True ($run.Code -eq 0) $run.Text
        Assert-True ((Get-Events $case) -ceq $installAll) "events: $(Get-Events $case); output: $($run.Text)"
        Assert-True ($run.Text.Contains('[dotfiles] [step] pymol: installing')) $run.Text
        Assert-True (-not $run.Text.Contains('kit')) "the default items named the kit: $($run.Text)"
        Clear-Events $case
        $run = Invoke-Hook $case @('-Now', 'skills', 'pymol')
        Assert-True ($run.Code -eq 0 -and (Get-Events $case) -ceq "skills-update [-Update True]`npymol-install []") "update: $(Get-Events $case); output: $($run.Text)"
        Assert-True (-not @(Get-ChildItem -LiteralPath (Join-Path $case.Root 'tmp') -Filter 'dotfiles-payload-*').Count) 'a download was left behind'
        Assert-NoState $case 'a -Now run'
    }
    Test-Case 'the kit is not available on native Windows: a run that names it says so and runs nothing for it' {
        $case = New-Case
        $run = Invoke-Hook $case @('-Now', 'kit')
        Assert-True ($run.Code -eq 0 -and $run.Text.Contains('[dotfiles] [info] kit: not available on native Windows')) "exit $($run.Code): $($run.Text)"
        Assert-True ((Get-Events $case) -ceq '') "events: $(Get-Events $case)"
        $run = Invoke-Hook $case @('-Now', 'kit', 'pymol')
        Assert-True ($run.Code -eq 0 -and (Get-Events $case) -ceq 'pymol-install []') "events: $(Get-Events $case); output: $($run.Text)"
    }
    Test-Case '-Now fails for a failed or unknown item and says how to retry; exit 75 is no failure; nothing is recorded' {
        $case = New-Case
        $run = Invoke-Hook $case @('-Now', 'pymol', 'skills') @{ FAKE_SKILLS_STATUS = '4' }
        Assert-True ($run.Code -eq 1) "exit $($run.Code): $($run.Text)"
        Assert-True ($run.Text.Contains('skills: install failed (exit 4); retry with: sync-payloads skills')) $run.Text
        $run = Invoke-Hook $case @('-Now', 'pymol') @{ FAKE_PYMOL_STATUS = '75' }
        Assert-True ($run.Code -eq 0 -and $run.Text.Contains('pymol: another run holds its lock; run sync-payloads pymol again once it has finished')) "exit 75: $($run.Text)"
        $run = Invoke-Hook $case @('-Now', 'nope')
        Assert-True ($run.Code -eq 1 -and $run.Text.Contains("unknown item 'nope'")) $run.Text
        Assert-NoState $case 'a failed run'
    }
    Test-Case 'an exit with the item''s person-status row waits for a person; another exit is an ordinary failure' {
        $case = New-Case
        $run = Invoke-Hook $case @('-Now', 'skills') @{ FAKE_SKILLS_STATUS = '3' }
        Assert-True ($run.Code -eq 1 -and $run.Text.Contains('skills: stopped for a person (exit 3): do what its message says, then run sync-payloads skills')) $run.Text
        $run = Invoke-Hook $case @('-Now', 'pymol') @{ FAKE_PYMOL_STATUS = '4' }
        Assert-True ($run.Code -eq 1 -and $run.Text.Contains('pymol: install failed (exit 4); retry with: sync-payloads pymol')) $run.Text
        # PyMOLScripts' 3: a locally edited rc file it leaves alone.
        $run = Invoke-Hook $case @('-Now', 'pymol') @{ FAKE_PYMOL_STATUS = '3' }
        Assert-True ($run.Code -eq 1 -and $run.Text.Contains('pymol: stopped for a person (exit 3): do what its message says, then run sync-payloads pymol')) $run.Text
    }
    Test-Case 'a download runs alone in a fresh private directory, removed afterwards' {
        # What another user planted in a shared temporary directory is never
        # beside the installer, and no other user can add anything there
        # while it downloads: mode 0700, and on Windows (where %TEMP% may be
        # a shared C:\Temp) an access list that grants only this account and
        # inherits nothing from the temporary directory.
        $private = if ($IsWindows) { "protected=True $([Security.Principal.WindowsIdentity]::GetCurrent().User.Value):FullControl:Allow:inherited=False" } else { 'drwx------' }
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
            Assert-True ($record[1] -ceq $private) "$name ran from a directory that is not private: $($record[1]), not $private"
            Assert-True ($record[2] -ceq 'install.ps1') "$name's directory held more than its script: $($record[2])"
            Assert-True (-not (Test-Path -LiteralPath $record[0])) "$name's staging directory was left behind"
        }
        $run = Invoke-Hook $case @('-Now', 'pymol') @{ FAKE_PYMOL_STATUS = '1' }
        $here = @([IO.File]::ReadAllLines("$($case.Events).pymol-dir"))[0]
        Assert-True ($run.Code -eq 1 -and -not (Test-Path -LiteralPath $here)) 'a failed installer left its staging directory behind'
        # A private directory that cannot be made (the temporary directory
        # lies below a file) runs nothing and fails.
        Clear-Events $case
        $blocked = Join-Path $case.Events 'tmp'
        $run = Invoke-Hook $case @('-Now', 'pymol') @{ TEMP = $blocked; TMP = $blocked; TMPDIR = $blocked }
        Assert-True ($run.Code -eq 1 -and $run.Text.Contains('cannot run')) "exit $($run.Code): $($run.Text)"
        Assert-True ((Get-Events $case) -ceq '') "events: $(Get-Events $case)"
    }
    Test-Case 'every installer, a download or an installed script, runs in $PSHOME, never in the caller''s working directory' {
        # The caller's directory may be an untrusted checkout (a VS Code
        # terminal starts in its workspace, holding a git.cmd here), and
        # awesome-skills' installer finds git with Python's shutil.which,
        # which on Windows searches the working directory first. A download's
        # own directory lies in the temporary directory, which may be shared
        # (git looks for a repository from its working directory upwards,
        # though on Windows it reaches C:\.git from $PSHOME too).
        $case = New-Case
        $caller = Join-Path $case.Root 'caller'
        Write-Fixture (Join-Path $caller 'git.cmd') '@echo planted'
        Push-Location -LiteralPath $caller
        try {
            $run = Invoke-Hook $case @('-Now', 'pymol', 'skills')
            Assert-True ($run.Code -eq 0) $run.Text
            foreach ($name in 'pymol', 'skills') { [void](Assert-RanInPSHome $case $name) }
            # skills is installed now, so its update row runs the installed script.
            $run = Invoke-Hook $case @('-Now', 'skills')
            Assert-True ($run.Code -eq 0 -and (Get-Events $case).EndsWith('skills-update [-Update True]')) "events: $(Get-Events $case); output: $($run.Text)"
            [void](Assert-RanInPSHome $case skills-update)
        }
        finally { Pop-Location }
    }
    Test-Case 'a download that fails runs nothing and fails' {
        $case = New-Case
        $source = Join-Path $remote 'PyMOLScripts/main/install.ps1'
        Move-Item -LiteralPath $source -Destination "$source.hidden"
        try { $run = Invoke-Hook $case @('-Now', 'pymol') }
        finally { Move-Item -LiteralPath "$source.hidden" -Destination $source }
        Assert-True ($run.Code -eq 1 -and $run.Text.Contains('cannot run')) $run.Text
        Assert-True ((Get-Events $case) -ceq '') "events: $(Get-Events $case); output: $($run.Text)"
    }
    Test-Case 'a missing installed script runs nothing and fails' {
        $case = New-Case
        [void](Invoke-Hook $case @('-Now', 'skills'))
        Remove-Item -LiteralPath (Join-Path $case.Data 'awesome-skills/update.ps1')
        Clear-Events $case
        $run = Invoke-Hook $case @('-Now', 'skills')
        Assert-True ($run.Code -eq 1 -and $run.Text.Contains('update.ps1 is missing')) $run.Text
        Assert-True ((Get-Events $case) -ceq '') "events: $(Get-Events $case)"
    }
    Test-Case 'a stalled download ends within the timeout and the run tries no other' {
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
        }
        finally { $listener.Stop() }
    }
    Test-Case 'a call without -Now, a bare item or an unknown argument included, prints one usage line and exits 2' {
        $case = New-Case
        $usage = 'dotfiles: usage: scripts/payload-update.ps1 -Now [ITEM...]'
        function Assert-UsageError([string[]]$Arguments, [string]$What) {
            $run = Invoke-Hook $case $Arguments
            Assert-True ($run.Code -eq 2 -and $run.Text -ceq $usage -and (Get-Events $case) -ceq '') "$($What): exit $($run.Code), events $(Get-Events $case), output: $($run.Text)"
        }
        Assert-UsageError @() 'no arguments'
        Assert-UsageError @('pymol') 'a bare item'
        Assert-UsageError @('-Bogus') 'an unknown argument'
        # Under maintenance too; a -Now run is refused there. Off Windows only:
        # PowerShell's $HOME on Windows is the account's profile.
        if (-not $IsWindows) {
            $maintenance = Join-Path $case.Home '.config/dotfiles/maintenance'
            Write-Fixture $maintenance ''
            try {
                Assert-UsageError @() 'no arguments under maintenance'
                $run = Invoke-Hook $case @('-Now', 'pymol')
                Assert-True ($run.Code -eq 1 -and $run.Text.Contains('payload update refused during maintenance') -and (Get-Events $case) -ceq '') "-Now under maintenance: exit $($run.Code): $($run.Text)"
            }
            finally { [IO.File]::Delete($maintenance) }
        }
        Assert-NoState $case 'a usage error'
    }
    Write-Output "payload-update-ps=PASS ($script:Passed cases)"
}
finally {
    foreach ($name in $names) { Set-TestVariable $name $saved[$name] }
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
