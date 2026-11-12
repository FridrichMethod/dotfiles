#Requires -Version 7.0
# Dispatcher behavior against disposable checkout backends, never real installers.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
. (Join-Path $PSScriptRoot 'lib/environment.ps1')

$sourceRoot = Split-Path -Parent $PSScriptRoot
$dispatcher = Join-Path $sourceRoot 'dotfiles.ps1'
if (-not (Test-Path -LiteralPath $dispatcher -PathType Leaf)) { throw "Missing dispatcher: $dispatcher" }
$powerShell = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-cli-ps-' + [Guid]::NewGuid().ToString('N'))
$fixture = Join-Path $temporaryRoot 'checkout with spaces'
$emptyHome = Join-Path $temporaryRoot 'empty home'
$emptyBin = Join-Path $temporaryRoot 'empty bin'
$events = Join-Path $temporaryRoot 'events.jsonl'
$script:Passed = 0
$script:ChildNumber = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Write-Fixture([string]$Path, [string]$Text) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text)
}
function Test-Case([string]$Name, [scriptblock]$Action) {
    [IO.File]::Delete($events)
    & $Action
    $script:Passed++
    Write-Output "PASS: $Name"
}
function Get-Events {
    if (Test-Path -LiteralPath $events) {
        foreach ($line in [IO.File]::ReadAllLines($events)) { ConvertFrom-Json -InputObject $line }
    }
}
function Invoke-CliChild {
    param([string]$Code, [hashtable]$Environment = @{}, [int]$ExpectedExit = 0, [string]$InputText = '', [string[]]$FileArguments)
    $script:ChildNumber++
    $driver = Join-Path $temporaryRoot "driver-$script:ChildNumber.ps1"
    # Set the PowerShell variable too: HOME in the environment alone does not
    # select a Windows PowerShell home. Every backend and artifact is a fixture.
    Write-Fixture $driver (@'
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-Variable HOME -Value $env:DOTFILES_TEST_CLI_HOME -Scope Global -Force
'@ + "`n" + $Code)
    $start = [Diagnostics.ProcessStartInfo]::new($powerShell)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.RedirectStandardInput = $true
    $start.WorkingDirectory = $emptyHome
    $entry = if ($PSBoundParameters.ContainsKey('FileArguments')) { Join-Path $fixture 'dotfiles.ps1' } else { $driver }
    foreach ($argument in @('-NoProfile', '-File', $entry)) { $start.ArgumentList.Add($argument) }
    if ($PSBoundParameters.ContainsKey('FileArguments')) {
        foreach ($argument in $FileArguments) { $start.ArgumentList.Add($argument) }
    }
    $start.Environment['DOTFILES_TEST_CLI_ROOT'] = $fixture
    $start.Environment['DOTFILES_TEST_CLI_SOURCE'] = $sourceRoot
    $start.Environment['DOTFILES_TEST_CLI_HOME'] = $emptyHome
    $start.Environment['DOTFILES_TEST_CLI_EVENTS'] = $events
    $start.Environment['DOTFILES_TEST_CLI_PWSH'] = $powerShell
    $start.Environment['PATH'] = $emptyBin
    $start.Environment['PSModulePath'] = (Join-Path $PSHOME 'Modules')
    $start.Environment['POWERSHELL_TELEMETRY_OPTOUT'] = '1'
    $start.Environment['POWERSHELL_UPDATECHECK'] = 'Off'
    foreach ($name in @('DOTFILES_TEST_CLI_STATUS', 'DOTFILES_TEST_CLI_BEHAVIOR')) { [void]$start.Environment.Remove($name) }
    foreach ($name in @('HOME', 'USERPROFILE', 'LOCALAPPDATA', 'APPDATA', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME')) {
        $start.Environment[$name] = $emptyHome
    }
    foreach ($name in $Environment.Keys) { $start.Environment[$name] = $Environment[$name] }
    $child = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $child.StandardOutput.ReadToEndAsync()
        $stderr = $child.StandardError.ReadToEndAsync()
        $child.StandardInput.Write($InputText)
        $child.StandardInput.Close()
        if (-not $child.WaitForExit(30000)) {
            $child.Kill($true)
            throw 'CLI child timed out.'
        }
        $outputText = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        Assert-True ($child.ExitCode -eq $ExpectedExit) "Child exit $($child.ExitCode), expected ${ExpectedExit}: $outputText $errorText"
        return [pscustomobject]@{ Out = $outputText; Error = $errorText }
    }
    finally { $child.Dispose() }
}
function Assert-OneDiagnostic($Result, [string]$Name) {
    Assert-True ($Result.Out -ceq '') "Refusal polluted stdout: $($Result.Out)"
    $lines = @($Result.Error.TrimEnd() -split '\r?\n')
    Assert-True ($lines.Count -eq 1 -and $lines[0].Contains($Name)) "Expected one diagnostic naming ${Name}: $($Result.Error)"
    Assert-True (@(Get-Events).Count -eq 0) 'A rejected invocation ran a backend.'
}

$recordBackend = @'
$bound = @{}
foreach ($name in $PSBoundParameters.Keys) {
    $value = $PSBoundParameters[$name]
    $bound[$name] = if ($value -is [Management.Automation.SwitchParameter]) { [bool]$value } else { $value }
}
@{ Kind = [IO.Path]::GetFileName($PSCommandPath); Bound = $bound; Extra = @($args);
   Pid = $PID; Location = (Get-Location).ProviderPath } |
    ConvertTo-Json -Depth 8 -Compress | Add-Content -LiteralPath $env:DOTFILES_TEST_CLI_EVENTS
switch ($env:DOTFILES_TEST_CLI_BEHAVIOR) {
    'streams' {
        Write-Output ([pscustomobject]@{ Value = 'success-object' })
        Write-Information 'backend-information' -InformationAction Continue
        Write-Warning 'backend-warning'
        Write-Verbose 'backend-verbose' -Verbose
        Write-Debug 'backend-debug' -Debug
        Write-Error 'backend-error' -ErrorAction Continue
    }
    'tsv' { Write-Output "status`tid`ttier`tdetail`tfix"; Write-Output "ok`tfixture`tcore`ttext`t-" }
    'read' { $answer = Read-Host 'fixture-question'; Write-Output "answer:$answer" }
    'throw' { throw 'fixture invocation failed' }
    'native' {
        & $env:DOTFILES_TEST_CLI_PWSH -NoProfile -File (Join-Path $PSScriptRoot 'native-exit.ps1')
        return
    }
}
if ($env:DOTFILES_TEST_CLI_STATUS) { exit ([int]$env:DOTFILES_TEST_CLI_STATUS) }
'@
$doctorParameters = @'
[CmdletBinding()]
param([string]$HostName = 'win', [string]$Tier = 'core,cli,ai', [switch]$Tsv, [switch]$Quiet, [switch]$Online)
'@
$setupParameters = @'
[CmdletBinding(SupportsShouldProcess)]
param([string]$HostName = 'win', [string]$Tier = 'core,cli,ai', [switch]$Check, [switch]$Yes, [switch]$PrintManual)
'@
$payloadParameters = @'
[CmdletBinding()]
param([switch]$Now, [Parameter(Position = 0, ValueFromRemainingArguments)][string[]]$Item)
'@

try {
    foreach ($directory in @($fixture, $emptyHome, $emptyBin)) { [void][IO.Directory]::CreateDirectory($directory) }
    Copy-Item -LiteralPath $dispatcher -Destination (Join-Path $fixture 'dotfiles.ps1')
    Write-Fixture (Join-Path $fixture 'doctor.ps1') ($doctorParameters + "`n" + $recordBackend)
    Write-Fixture (Join-Path $fixture 'setup-host.ps1') ($setupParameters + "`n" + $recordBackend)
    Write-Fixture (Join-Path $fixture 'scripts/payload-update.ps1') ($payloadParameters + "`n" + $recordBackend)
    Write-Fixture (Join-Path $fixture 'native-exit.ps1') 'exit 23'

    Test-Case 'help needs no configured home, Python, backend or PATH tools' {
        $helpOnly = Join-Path $temporaryRoot 'help only'
        [void][IO.Directory]::CreateDirectory($helpOnly)
        Copy-Item -LiteralPath $dispatcher -Destination (Join-Path $helpOnly 'dotfiles.ps1')
        $code = @'
$arguments = @($env:DOTFILES_TEST_CLI_ARGUMENTS | ConvertFrom-Json)
& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') @arguments
exit $LASTEXITCODE
'@
        foreach ($arguments in @(@(), @('--help'), @('-h'), @('help'), @('payloads'), @('dev'),
                @('help', 'doctor'), @('help', 'setup'), @('help', 'payloads', 'sync'),
                @('help', 'dev', 'test'), @('help', 'dev', 'check'), @('doctor', '--help'),
                @('setup', '-h'), @('payloads', 'sync', '--help'), @('dev', 'test', '-h'), @('dev', 'check', '--help'))) {
            $result = Invoke-CliChild $code @{ DOTFILES_TEST_CLI_ROOT = $helpOnly; DOTFILES_TEST_CLI_ARGUMENTS = (ConvertTo-Json -InputObject $arguments -Compress) }
            Assert-True ($result.Error -ceq '' -and $result.Out.Contains('dotfiles')) "Help failed for [$arguments]: $($result.Error)"
        }
        Assert-True (@(Get-ChildItem -LiteralPath $emptyHome -Force).Count -eq 0) 'Help wrote to the empty home.'
    }
    Test-Case 'doctor maps raw long options, last scalar value, and idempotent booleans' {
        $result = Invoke-CliChild @'
& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') doctor --host ignored --host=win --tier ignored --tier 'core,cli,ai' --quiet --quiet --online --tsv
exit $LASTEXITCODE
'@
        Assert-True ($result.Out -ceq '' -and $result.Error -ceq '') 'Normal forwarding added output.'
        $calls = @(Get-Events)
        Assert-True ($calls.Count -eq 1 -and $calls[0].Kind -ceq 'doctor.ps1') 'Wrong backend or invocation count.'
        $bound = $calls[0].Bound
        Assert-True ($bound.HostName -ceq 'win' -and $bound.Tier -ceq 'core,cli,ai') 'Value options lost their boundaries or last value.'
        Assert-True ($bound.Quiet -and $bound.Online -and $bound.Tsv -and $calls[0].Extra.Count -eq 0) 'Boolean mapping or forwarding failed.'
    }
    Test-Case 'direct File invocation preserves GNU arguments and process exit status' {
        $result = Invoke-CliChild -FileArguments @('doctor', '--host=win', '--tier', 'core,cli,ai', '--tsv') -Environment @{ DOTFILES_TEST_CLI_STATUS = '3' } -ExpectedExit 3
        $calls = @(Get-Events)
        Assert-True ($calls.Count -eq 1 -and $calls[0].Kind -ceq 'doctor.ps1') 'Direct File invocation chose the wrong backend.'
        Assert-True ($calls[0].Bound.HostName -ceq 'win' -and $calls[0].Bound.Tier -ceq 'core,cli,ai' -and $calls[0].Bound.Tsv) 'File invocation consumed or changed GNU arguments.'
        Assert-True ($result.Out -ceq '' -and $result.Error -ceq '') 'File invocation added output.'
    }
    Test-Case 'literal option values survive spaces and PowerShell metacharacters' {
        [void](Invoke-CliChild @'
& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') doctor --tier 'core, cli;$(throw "evaluated") [x]'
exit $LASTEXITCODE
'@)
        Assert-True (@(Get-Events)[0].Bound.Tier -ceq 'core, cli;$(throw "evaluated") [x]') 'A literal value was expanded or split.'
    }
    Test-Case 'setup maps check, yes, print-manual, what-if and confirm explicitly' {
        [void](Invoke-CliChild @'
& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') setup --host=win --tier=core --check --yes --print-manual --what-if --confirm
exit $LASTEXITCODE
'@)
        $bound = @(Get-Events)[0].Bound
        foreach ($name in @('Check', 'Yes', 'PrintManual', 'WhatIf', 'Confirm')) {
            Assert-True ($bound.$name) "Setup did not map $name."
        }
        Assert-True ($bound.HostName -ceq 'win' -and $bound.Tier -ceq 'core') 'Setup scalar mapping failed.'
    }
    Test-Case 'usage errors reject unknown paths, unsupported options and malformed values before dispatch' {
        $cases = @(
            @('Doctor'), @('doctor', '--Host', 'win'), @('setup', '--CHECK'), @('update'),
            @('payloads', 'unknown'), @('dev', 'unknown'), @('help', 'dev', 'unknown'),
            @('help', 'doctor', 'extra'), @('doctor', '--platform', 'win'), @('doctor', '--smoke'),
            @('doctor', '--list'), @('setup', '--only', 'step'), @('setup', '--skip', 'step'),
            @('setup', '--keep-going'), @('setup', '--list'), @('doctor', '--host'),
            @('doctor', '--tier='), @('doctor', '--tier', ''), @('doctor', '--host', '--quiet'),
            @('doctor', '--quiet=true'), @('setup', '--check=false'), @('setup', '--confirm=true'),
            @('payloads', 'sync', '--now'), @('payloads', 'sync', '--unknown'),
            @('dev', 'test', '--unknown'), @('dev', 'check', '--ci'), @('dev', 'check', 'extra'),
            @('doctor', "--unknown`noption")
        )
        foreach ($arguments in $cases) {
            $result = Invoke-CliChild @'
$arguments = @($env:DOTFILES_TEST_CLI_ARGUMENTS | ConvertFrom-Json)
& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') @arguments
exit $LASTEXITCODE
'@ @{ DOTFILES_TEST_CLI_ARGUMENTS = (ConvertTo-Json -InputObject $arguments -Compress) } -ExpectedExit 2
            Assert-OneDiagnostic $result 'dotfiles'
        }
    }
    Test-Case 'raw arrays, comma expressions, objects and null arguments are usage errors' {
        foreach ($call in @(
                'doctor --tier core,cli', "doctor --tier @('core', 'cli')", "doctor --tier @{ value = 'core' }",
                "doctor --tier ([pscustomobject]@{ value = 'core' })", 'doctor --tier $null',
                "payloads sync @('skills', 'pymol')")) {
            $result = Invoke-CliChild ("& (Join-Path `$env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') $call`nexit `$LASTEXITCODE") -ExpectedExit 2
            Assert-OneDiagnostic $result 'dotfiles'
        }
    }
    Test-Case 'payload names remain backend-owned and Now is supplied exactly once' {
        [void](Invoke-CliChild @'
& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') payloads sync 'future item' skills
exit $LASTEXITCODE
'@ @{ DOTFILES_TEST_CLI_STATUS = '1' } -ExpectedExit 1)
        $calls = @(Get-Events)
        Assert-True ($calls.Count -eq 1 -and $calls[0].Kind -ceq 'payload-update.ps1') 'Payload backend was not called once.'
        Assert-True ($calls[0].Bound.Now -and $calls[0].Extra.Count -eq 0) 'Payload Now mapping failed.'
        Assert-True (($calls[0].Bound.Item -join '|') -ceq 'future item|skills') 'Dispatcher filtered or split item names.'
    }
    Test-Case 'payload defaults are selected by the backend without an explicit item list' {
        [void](Invoke-CliChild -FileArguments @('payloads', 'sync'))
        $calls = @(Get-Events)
        Assert-True ($calls.Count -eq 1 -and $calls[0].Bound.Now) 'Default payload sync did not call its backend once.'
        Assert-True ($calls[0].Bound.PSObject.Properties.Name -cnotcontains 'Item') 'Dispatcher overrode the backend payload defaults.'
    }
    Test-Case 'explicit backend exits 0, 1, 2 and 3 are preserved' {
        foreach ($status in 0, 1, 2, 3) {
            [void](Invoke-CliChild @'
& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') setup --check
exit $LASTEXITCODE
'@ @{ DOTFILES_TEST_CLI_STATUS = [string]$status } -ExpectedExit $status)
        }
    }
    Test-Case 'same-session stale failure resets and native failure without script exit propagates' {
        foreach ($mode in @('untouched', 'native')) {
            $expected = if ($mode -ceq 'native') { 23 } else { 0 }
            $result = Invoke-CliChild @'
$global:LASTEXITCODE = 19
& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') doctor
$observed = $LASTEXITCODE
Write-Output "observed=$observed"
exit $observed
'@ @{ DOTFILES_TEST_CLI_BEHAVIOR = $mode } -ExpectedExit $expected
            Assert-True ($result.Out.Trim() -ceq "observed=$expected") "Status was stale or lost: $($result.Out)"
        }
    }
    Test-Case 'success objects and all five side streams retain their stream identity' {
        $result = Invoke-CliChild @'
$logs = @{}
foreach ($number in 2..6) { $logs[$number] = Join-Path $env:DOTFILES_TEST_CLI_HOME "stream-$number.log" }
$success = @(& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') doctor 2> $logs[2] 3> $logs[3] 4> $logs[4] 5> $logs[5] 6> $logs[6])
$status = $LASTEXITCODE
if ($success.Count -ne 1 -or $success[0].Value -cne 'success-object') { throw 'Success object was converted or mixed with another stream.' }
foreach ($pair in @(@(2, 'error'), @(3, 'warning'), @(4, 'verbose'), @(5, 'debug'), @(6, 'information'))) {
    $text = [IO.File]::ReadAllText($logs[$pair[0]])
    if (-not $text.Contains("backend-$($pair[1])")) { throw "Lost stream $($pair[0]): $text" }
    foreach ($other in @('error', 'warning', 'verbose', 'debug', 'information')) {
        if ($other -cne $pair[1] -and $text.Contains("backend-$other")) { throw 'Stream identity changed.' }
    }
}
exit $status
'@ @{ DOTFILES_TEST_CLI_BEHAVIOR = 'streams' }
        Assert-True ($result.Out -ceq '' -and $result.Error -ceq '') 'Side streams escaped redirection.'
    }
    Test-Case 'redirected doctor TSV contains only backend TSV' {
        $result = Invoke-CliChild @'
$tsv = Join-Path $env:DOTFILES_TEST_CLI_HOME 'doctor.tsv'
& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') doctor --tsv > $tsv
$status = $LASTEXITCODE
[Console]::Out.Write([IO.File]::ReadAllText($tsv))
exit $status
'@ @{ DOTFILES_TEST_CLI_BEHAVIOR = 'tsv' }
        Assert-True ($result.Out.Replace("`r`n", "`n") -ceq "status`tid`ttier`tdetail`tfix`nok`tfixture`tcore`ttext`t-`n") 'TSV was reformatted or contaminated.'
        Assert-True ($result.Error -ceq '') 'TSV forwarding wrote a diagnostic.'
    }
    Test-Case 'setup inherits stdin and does not add Yes or NonInteractive' {
        $result = Invoke-CliChild @'
& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') setup
exit $LASTEXITCODE
'@ @{ DOTFILES_TEST_CLI_BEHAVIOR = 'read' } -InputText "fixture answer`n"
        $bound = @(Get-Events)[0].Bound
        Assert-True ($result.Out.Contains('answer:fixture answer') -and $result.Error -ceq '') 'Setup could not read inherited input.'
        Assert-True ($bound.PSObject.Properties.Name -cnotcontains 'Yes') 'Dispatcher added Yes to setup.'
    }
    Test-Case 'missing backend and terminating backend failure each produce one diagnostic' {
        $missing = Join-Path $temporaryRoot 'missing backend'
        [void][IO.Directory]::CreateDirectory($missing)
        Copy-Item -LiteralPath $dispatcher -Destination (Join-Path $missing 'dotfiles.ps1')
        $result = Invoke-CliChild @'
& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') doctor
exit $LASTEXITCODE
'@ @{ DOTFILES_TEST_CLI_ROOT = $missing } -ExpectedExit 1
        Assert-OneDiagnostic $result 'doctor.ps1'
        $result = Invoke-CliChild @'
& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') doctor
exit $LASTEXITCODE
'@ @{ DOTFILES_TEST_CLI_BEHAVIOR = 'throw' } -ExpectedExit 1
        Assert-True ($result.Out -ceq '' -and @($result.Error.TrimEnd() -split '\r?\n').Count -eq 1 -and $result.Error.Contains('fixture invocation failed')) 'Terminating failure was hidden or emitted a traceback.'
    }
    Test-Case 'dev test starts the current PowerShell and keeps sanitization out of its caller' {
        Write-Fixture (Join-Path $fixture 'tests/lib/environment.ps1') ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'lib/environment.ps1')))
        Write-Fixture (Join-Path $fixture 'tests/run.ps1') @'
[CmdletBinding()]
param([switch]$CI, [switch]$CheckPrerequisites)
. (Join-Path $PSScriptRoot 'lib/environment.ps1')
@{ CI = [bool]$CI; CheckPrerequisites = [bool]$CheckPrerequisites; Pid = $PID;
   Process = (Get-Process -Id $PID).Path; Arguments = [Environment]::GetCommandLineArgs();
   Leaked = (Test-Path Env:DOTFILES_CLI_PARENT); Preserved = $env:DOTFILES_TEST_CLI_EVENTS } |
    ConvertTo-Json -Depth 8 -Compress | Add-Content -LiteralPath $env:DOTFILES_TEST_CLI_EVENTS
exit 3
'@
        $result = Invoke-CliChild @'
$env:DOTFILES_CLI_PARENT = 'keep'
$parentPid = $PID
& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') dev test --ci --check-prerequisites --ci
$status = $LASTEXITCODE
if ($env:DOTFILES_CLI_PARENT -cne 'keep') { throw 'dev test sanitized its caller.' }
Write-Output "parent=$parentPid"
exit $status
'@ -ExpectedExit 3
        $calls = @(Get-Events)
        Assert-True ($calls.Count -eq 1 -and $calls[0].CI -and $calls[0].CheckPrerequisites) 'Developer flags were not mapped once.'
        Assert-True (-not $calls[0].Leaked -and $calls[0].Preserved -ceq $events) 'Test runner isolation failed.'
        Assert-True ($result.Out.Trim() -cne "parent=$($calls[0].Pid)" -and $calls[0].Process -eq $powerShell) 'dev test did not use a fresh current PowerShell.'
        Assert-True ($calls[0].Arguments -contains '-NoProfile' -and $calls[0].Arguments -contains '-File') 'Developer child used the wrong PowerShell interface.'
        Assert-True ($result.Error -ceq '') 'dev test emitted an unexpected diagnostic.'
    }
    Test-Case 'dev check names missing pre-commit once and restores the caller location' {
        $result = Invoke-CliChild @'
$before = (Get-Location).ProviderPath
& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') dev check
$status = $LASTEXITCODE
if ((Get-Location).ProviderPath -cne $before) { throw 'dev check changed caller location.' }
exit $status
'@ -ExpectedExit 1
        Assert-OneDiagnostic $result 'pre-commit'
    }
    Test-Case 'dev check invokes only pre-commit in the checkout and restores location on every outcome' {
        Write-Fixture (Join-Path $emptyBin 'pre-commit.ps1') @'
@{ Arguments = @($args); Location = (Get-Location).ProviderPath } |
    ConvertTo-Json -Depth 8 -Compress | Add-Content -LiteralPath $env:DOTFILES_TEST_CLI_EVENTS
if ($env:DOTFILES_TEST_CLI_BEHAVIOR -ceq 'throw') { throw 'pre-commit fixture failure' }
exit ([int]$env:DOTFILES_TEST_CLI_STATUS)
'@
        foreach ($mode in @('success', 'failure', 'throw')) {
            [IO.File]::Delete($events)
            $status = if ($mode -ceq 'success') { 0 } elseif ($mode -ceq 'throw') { 1 } else { 3 }
            $result = Invoke-CliChild @'
$before = (Get-Location).ProviderPath
$beforePreference = $ErrorActionPreference
$beforeNativePreference = $PSNativeCommandUseErrorActionPreference
& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') dev check
$status = $LASTEXITCODE
if ((Get-Location).ProviderPath -cne $before) { throw 'dev check changed caller location.' }
if ($ErrorActionPreference -cne $beforePreference -or $PSNativeCommandUseErrorActionPreference -ne $beforeNativePreference) { throw 'Dispatcher leaked preferences.' }
exit $status
'@ @{ DOTFILES_TEST_CLI_BEHAVIOR = $mode; DOTFILES_TEST_CLI_STATUS = [string]$status } -ExpectedExit $status
            $calls = @(Get-Events)
            Assert-True ($calls.Count -eq 1 -and ($calls[0].Arguments -join '|') -ceq 'run|--all-files') 'dev check ran the wrong command or recursed into tests.'
            Assert-True ($calls[0].Location -ceq $fixture) 'dev check ran outside its checkout.'
            if ($mode -ceq 'throw') {
                Assert-True ($result.Out -ceq '' -and @($result.Error.TrimEnd() -split '\r?\n').Count -eq 1 -and $result.Error.Contains('pre-commit fixture failure')) 'dev check invocation failure diagnostic was not concise.'
            }
            else { Assert-True ($result.Out -ceq '' -and $result.Error -ceq '') 'dev check added output.' }
        }
    }
    Write-Output "powershell-cli=PASS ($script:Passed cases)"
}
finally {
    if ([IO.Path]::GetFileName($temporaryRoot) -notlike 'dotfiles-cli-ps-*') { throw 'Unexpected cleanup target.' }
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
}
