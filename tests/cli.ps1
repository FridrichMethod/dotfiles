#Requires -Version 7.0
# Dispatcher behavior against disposable checkout backends, never real installers.
[CmdletBinding()]
param(
    [switch]$ConsoleCancellationProbe,
    [string]$BaselineRoot,
    [string]$ConsoleEvidenceDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
. (Join-Path $PSScriptRoot 'lib/environment.ps1')

$sourceRoot = Split-Path -Parent $PSScriptRoot
$dispatcher = Join-Path $sourceRoot 'dotfiles.ps1'
if (-not (Test-Path -LiteralPath $dispatcher -PathType Leaf)) { throw "Missing dispatcher: $dispatcher" }
$powerShell = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-cli-ps-' + [Guid]::NewGuid().ToString('N'))
$fixture = Join-Path $temporaryRoot "checkout O'Neil [literal] with spaces"
$emptyHome = Join-Path $temporaryRoot 'empty home'
$runtimeState = Join-Path $temporaryRoot 'powershell state'
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
# Explicit native acceptance mode. Each conhost creates a NEW classic console;
# the coordinator may attach/send Ctrl+C only to its recorded backend PID.
# Leave the bundle and markers for comparison and scoped cleanup by its owner.
if ($ConsoleCancellationProbe) {
    if (-not $IsWindows -or -not [Environment]::UserInteractive) {
        throw 'Cancellation acceptance needs an ordinary native Windows interactive session.'
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Cancellation acceptance refuses an elevated token.'
    }
    $consoleHost = Join-Path $env:SystemRoot 'System32/conhost.exe'
    if (-not [IO.File]::Exists($consoleHost)) { throw 'Cancellation acceptance requires conhost.exe.' }
    if (-not $BaselineRoot -or -not $ConsoleEvidenceDirectory -or
        -not [IO.File]::Exists((Join-Path $BaselineRoot 'dotfiles.ps1'))) {
        throw 'Pass a separately hash-checked baseline bundle and a new evidence directory.'
    }
    if (Test-Path -LiteralPath $ConsoleEvidenceDirectory) { throw 'Evidence directory must not already exist.' }
    [void][IO.Directory]::CreateDirectory($ConsoleEvidenceDirectory)
    $ConsoleEvidenceDirectory = (Get-Item -LiteralPath $ConsoleEvidenceDirectory).FullName
    $records = @()
    $probeProcesses = [Collections.Generic.List[Diagnostics.Process]]::new()
    try {
        foreach ($variant in @('baseline', 'candidate')) {
            $root = Join-Path $ConsoleEvidenceDirectory $variant
            $original = Join-Path $(if ($variant -ceq 'baseline') { $BaselineRoot } else { $sourceRoot }) 'dotfiles.ps1'
            Write-Fixture (Join-Path $root 'dotfiles.ps1') ([IO.File]::ReadAllText($original))
            Write-Fixture (Join-Path $root 'sleeper.ps1') @'
# Harmless native child, interrupted with its backend in the probe console.
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'child-ready.txt'), [string]$PID)
Start-Sleep -Seconds 300
'@
            $stub = @'
[CmdletBinding(SupportsShouldProcess)]
param([string]$HostName = 'win', [string]$Tier = 'core,cli,ai', [switch]$Check, [switch]$Yes, [switch]$PrintManual)
$root = $env:DOTFILES_TEST_CONSOLE_ROOT
$child = $null
try {
    $start = [Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'))
    $start.UseShellExecute = $false
    foreach ($argument in @('-NoProfile', '-File', (Join-Path $root 'sleeper.ps1'))) { $start.ArgumentList.Add($argument) }
    $child = [Diagnostics.Process]::Start($start)
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while (-not [IO.File]::Exists((Join-Path $root 'child-ready.txt')) -and -not $child.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 100
    }
    if (-not [IO.File]::Exists((Join-Path $root 'child-ready.txt'))) { throw 'Harmless child did not become ready.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $ready = @{
        BackendPid = $PID; SessionId = (Get-Process -Id $PID).SessionId; ChildPid = $child.Id
        Elevated = ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        InputRedirected = [Console]::IsInputRedirected; OutputRedirected = [Console]::IsOutputRedirected
    }
    # Publish the complete observation before the coordinator reads it.
    [IO.File]::WriteAllText((Join-Path $root 'ready.tmp'), ($ready | ConvertTo-Json))
    [IO.File]::Move((Join-Path $root 'ready.tmp'), (Join-Path $root 'ready.json'))
    # No input capture and no wrapper handler: Ctrl+C retains native propagation.
    $child.WaitForExit()
}
finally {
    $survived = $false
    if ($child) {
        $survived = -not $child.HasExited
        if ($survived) { $child.Kill($true); $child.WaitForExit() }
        $child.Dispose()
    }
    [IO.File]::WriteAllText((Join-Path $root 'backend-finally.json'), (@{ ChildSurvivedCancellation = $survived; CleanupComplete = $true } | ConvertTo-Json))
}
'@
            $backend = if ($variant -ceq 'baseline') { 'setup-host.ps1' } else { 'scripts/commands/setup.ps1' }
            Write-Fixture (Join-Path $root $backend) $stub
            $driver = Join-Path $root 'console.ps1'
            Write-Fixture $driver @'
$env:DOTFILES_TEST_CONSOLE_ROOT = $PSScriptRoot
try {
    & (Join-Path $PSScriptRoot 'dotfiles.ps1') setup
}
finally {
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'console-finally.json'), (@{ Pid = $PID; LastExitCode = $global:LASTEXITCODE } | ConvertTo-Json))
}
'@
            # Explicit conhost bypasses the default Windows Terminal host.
            # Quote both paths in its single command line and create a new console.
            $process = Start-Process -FilePath $consoleHost -ArgumentList ('"' + $powerShell + '" -NoProfile -File "' + $driver + '"') -PassThru
            $probeProcesses.Add($process)
            $deadline = [DateTime]::UtcNow.AddSeconds(20)
            while (-not [IO.File]::Exists((Join-Path $root 'ready.json')) -and -not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
                Start-Sleep -Milliseconds 100
            }
            if (-not [IO.File]::Exists((Join-Path $root 'ready.json'))) {
                throw "Probe did not become ready: $variant"
            }
            $ready = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $root 'ready.json')))
            Assert-True (-not $ready.Elevated -and -not $ready.InputRedirected -and -not $ready.OutputRedirected) "Probe backend needs an ordinary token and unredirected stdin/stdout: $variant"
            Assert-True ($ready.BackendPid -gt 0 -and $ready.BackendPid -ne $process.Id) "Probe did not record a separate backend PowerShell PID: $variant"
            $records += [pscustomobject]@{
                Variant = $variant; ConsoleHostPid = $process.Id; ConsoleHostSessionId = $process.SessionId
                BackendPid = $ready.BackendPid; SessionId = $ready.SessionId; ChildPid = $ready.ChildPid
                Elevated = $ready.Elevated; InputRedirected = $ready.InputRedirected; OutputRedirected = $ready.OutputRedirected
                FrontendSha256 = (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
                Ready = Join-Path $root 'ready.json'; BackendFinally = Join-Path $root 'backend-finally.json'
                ConsoleFinally = Join-Path $root 'console-finally.json'
            }
        }
        $records | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $ConsoleEvidenceDirectory 'probes.json')
        $records
    }
    catch {
        foreach ($probeProcess in $probeProcesses) {
            if (-not $probeProcess.HasExited) { $probeProcess.Kill($true); $probeProcess.WaitForExit() }
        }
        throw
    }
    finally { foreach ($probeProcess in $probeProcesses) { $probeProcess.Dispose() } }
    return
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
    foreach ($name in @('HOME', 'USERPROFILE')) {
        $start.Environment[$name] = $emptyHome
    }
    # PowerShell writes startup caches before the driver runs. Keep runtime
    # state separate so the empty-home assertion measures only CLI effects.
    foreach ($name in @('LOCALAPPDATA', 'APPDATA', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME')) {
        $start.Environment[$name] = $runtimeState
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
function Assert-HelpHomeUnchanged([string]$SnapshotPath, [string]$Context) {
    $snapshot = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($SnapshotPath))
    $before = @{}
    $after = @{}
    foreach ($entry in $snapshot.Before) { $before[$entry.Path] = $entry.State }
    foreach ($entry in $snapshot.After) { $after[$entry.Path] = $entry.State }
    $changes = @(
        foreach ($path in @(@($before.Keys) + @($after.Keys) | Sort-Object -Unique)) {
            if (-not $before.ContainsKey($path)) { "added: $path" }
            elseif (-not $after.ContainsKey($path)) { "removed: $path" }
            elseif ($before[$path] -cne $after[$path]) { "changed: $path" }
        }
    )
    Assert-True ($changes.Count -eq 0) "$Context wrote to HOME: $($changes -join '; ')."
    return $snapshot
}

$recordBackend = @'
$bound = @{}
foreach ($name in $PSBoundParameters.Keys) {
    $value = $PSBoundParameters[$name]
    $bound[$name] = if ($value -is [Management.Automation.SwitchParameter]) { [bool]$value } else { $value }
}
# Advanced scripts can inherit the caller's $args when all parameters bind.
# InvocationInfo records this backend's actual unbound arguments.
$eventJson = @{ Root = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)); HostName = $(if (Get-Variable HostName -ErrorAction Ignore) { $HostName } else { '' }); Kind = [IO.Path]::GetFileName($PSCommandPath); Bound = $bound; Extra = @($MyInvocation.UnboundArguments);
   Pid = $PID; Location = (Get-Location).ProviderPath } |
    ConvertTo-Json -Depth 8 -Compress
# Recording is test instrumentation, independent of forwarded WhatIf/Confirm.
[IO.File]::AppendAllText($env:DOTFILES_TEST_CLI_EVENTS, $eventJson + [Environment]::NewLine)
switch ($env:DOTFILES_TEST_CLI_BEHAVIOR) {
    'streams' {
        Write-Output $global:DotfilesCliSuccessObject
        Write-Information 'backend-information' -InformationAction Continue
        Write-Warning 'backend-warning'
        Write-Verbose 'backend-verbose' -Verbose
        Write-Debug 'backend-debug' -Debug
        Write-Error 'backend-error' -ErrorAction Continue
    }
    'tsv' { Write-Output "status`tid`ttier`tdetail`tfix"; Write-Output "ok`tfixture`tcore`ttext`t-" }
    'continue' { if (-not $PSCmdlet.ShouldContinue('Fixture only; no installation.', 'initial consent')) { exit 2 }; exit 0 }
    'process' { if (-not $PSCmdlet.ShouldProcess('fixture only', 'no installation')) { exit 3 }; exit 0 }
    'read' { $answer = Read-Host 'fixture-question'; Write-Output "answer:$answer" }
    'nonterminating' { Write-Error 'backend-default-error'; Write-Output 'continued' }
    'throw' { throw 'fixture invocation failed' }
    'native' {
        & $env:DOTFILES_TEST_CLI_PWSH -NoProfile -File (Join-Path $PSScriptRoot '../../native-exit.ps1')
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
    foreach ($directory in @($fixture, $emptyHome, $runtimeState, $emptyBin)) { [void][IO.Directory]::CreateDirectory($directory) }
    Copy-Item -LiteralPath $dispatcher -Destination (Join-Path $fixture 'dotfiles.ps1')
    Write-Fixture (Join-Path $fixture 'scripts/commands/doctor.ps1') ($doctorParameters + "`n" + $recordBackend)
    Write-Fixture (Join-Path $fixture 'scripts/commands/setup.ps1') ($setupParameters + "`n" + $recordBackend)
    Write-Fixture (Join-Path $fixture 'scripts/commands/payloads-sync.ps1') ($payloadParameters + "`n" + $recordBackend)
    Write-Fixture (Join-Path $fixture 'native-exit.ps1') 'exit 23'

    Test-Case 'retired PowerShell production paths are absent on disk and in the index' {
        $retired = @('doctor.ps1', 'setup-host.ps1', 'scripts/payload-update.ps1')
        foreach ($relative in $retired) {
            # Get-Item sees dangling links as well as ordinary files.
            Assert-True ($null -eq (Get-Item -LiteralPath (Join-Path $sourceRoot $relative) -Force -ErrorAction SilentlyContinue)) "Retired path remains: $relative"
        }
        $tracked = @(& git -C $sourceRoot ls-files -- @retired)
        Assert-True ($LASTEXITCODE -eq 0 -and $tracked.Count -eq 0) "Retired paths remain tracked: $tracked"
    }
    Test-Case 'nested backends use their own checkout and default native host from a foreign cwd' {
        foreach ($command in @('doctor', 'setup', 'payloads sync')) {
            [IO.File]::Delete($events)
            $result = Invoke-CliChild @'
# Observe the child before dispatch: macOS can canonicalize a /var temporary
# directory to /private/var when starting the process.
Write-Output (Get-Location).ProviderPath
$arguments = $env:DOTFILES_TEST_CLI_COMMAND.Split(' ')
& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') @arguments
exit $LASTEXITCODE
'@ @{ DOTFILES_TEST_CLI_COMMAND = $command }
            $calls = @(Get-Events)
            Assert-True ($calls.Count -eq 1) "Expected one nested backend call for ${command}: $($calls.Count)"
            Assert-True ($calls[0].Root -ceq $fixture) "Nested backend selected wrong root for ${command}: expected <$fixture>, got <$($calls[0].Root)>"
            $before = $result.Out.TrimEnd()
            Assert-True ($before -and $calls[0].Location -ceq $before) "Nested backend changed cwd for ${command}: before <$before>, backend <$($calls[0].Location)>"
            if ($command -cne 'payloads sync') { Assert-True ($calls[0].HostName -ceq 'win') "Native default host changed: $command" }
        }
    }
    Test-Case 'missing formal backend never invokes a retired-path tripwire' {
        $missing = Join-Path $temporaryRoot 'tripwire checkout'
        Write-Fixture (Join-Path $missing 'dotfiles.ps1') ([IO.File]::ReadAllText($dispatcher))
        foreach ($entry in @(@('doctor', 'doctor.ps1', 'doctor.ps1'), @('setup', 'setup-host.ps1', 'setup.ps1'),
                @('payloads sync', 'scripts/payload-update.ps1', 'payloads-sync.ps1'))) {
            Write-Fixture (Join-Path $missing $entry[1]) "[IO.File]::AppendAllText(`$env:DOTFILES_TEST_CLI_EVENTS, 'tripwire'); exit 0"
            $result = Invoke-CliChild @'
$arguments = $env:DOTFILES_TEST_CLI_COMMAND.Split(' ')
& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') @arguments
exit $LASTEXITCODE
'@ @{ DOTFILES_TEST_CLI_ROOT = $missing; DOTFILES_TEST_CLI_COMMAND = $entry[0] } -ExpectedExit 1
            Assert-OneDiagnostic $result ('scripts' + [IO.Path]::DirectorySeparatorChar + 'commands' + [IO.Path]::DirectorySeparatorChar + $entry[2])
        }
    }
    Test-Case 'help needs no configured home, Python, backend or PATH tools' {
        $helpOnly = Join-Path $temporaryRoot 'help only'
        [void][IO.Directory]::CreateDirectory($helpOnly)
        Copy-Item -LiteralPath $dispatcher -Destination (Join-Path $helpOnly 'dotfiles.ps1')
        $code = @'
$arguments = @($env:DOTFILES_TEST_CLI_ARGUMENTS | ConvertFrom-Json)
$entrypoint = Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1'
# Prime the fixture's commands before measuring the actual CLI invocation.
$null = Write-Output ''
function Get-HelpHomeSnapshot {
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        foreach ($path in @([IO.Directory]::EnumerateFileSystemEntries($HOME, '*', [IO.SearchOption]::AllDirectories) | Sort-Object)) {
            $isDirectory = [IO.Directory]::Exists($path)
            $item = if ($isDirectory) { [IO.DirectoryInfo]::new($path) } else { [IO.FileInfo]::new($path) }
            $digest = if ($isDirectory) { '' } else { [Convert]::ToBase64String($hash.ComputeHash([IO.File]::ReadAllBytes($path))) }
            [pscustomobject]@{
                Path = [IO.Path]::GetRelativePath($HOME, $path)
                State = "$isDirectory|$($item.Attributes)|$($item.LastWriteTimeUtc.Ticks)|$digest"
            }
        }
    }
    finally { $hash.Dispose() }
}
# PowerShell can initialize home paths before this driver starts, including
# Windows paths that do not follow redirected APPDATA. Compare in one process.
$null = @(Get-HelpHomeSnapshot)
$before = @(Get-HelpHomeSnapshot)
if ([IO.File]::Exists((Join-Path $HOME '.config/chezmoi/chezmoi.toml'))) { throw 'Help fixture unexpectedly has a configured home.' }
if ($env:DOTFILES_TEST_CLI_CONTROL -ceq 'startup-only') { $status = 0 }
else {
    & $entrypoint @arguments
    $status = $LASTEXITCODE
}
$after = @(Get-HelpHomeSnapshot)
[IO.File]::WriteAllText($env:DOTFILES_TEST_CLI_SNAPSHOT, (@{ Before = $before; After = $after } | ConvertTo-Json -Depth 5))
exit $status
'@
        $snapshotPath = Join-Path $temporaryRoot 'help-home.json'
        $result = Invoke-CliChild $code @{
            DOTFILES_TEST_CLI_ROOT = $helpOnly; DOTFILES_TEST_CLI_ARGUMENTS = '[]'
            DOTFILES_TEST_CLI_CONTROL = 'startup-only'; DOTFILES_TEST_CLI_SNAPSHOT = $snapshotPath
        }
        Assert-True ($result.Out -ceq '' -and $result.Error -ceq '') 'Startup-only control emitted unexpected output.'
        $startup = Assert-HelpHomeUnchanged $snapshotPath 'Startup-only control'
        Write-Output "help-startup-home=$(@($startup.Before | ForEach-Object Path) -join ', ')"
        foreach ($arguments in @(@(), @('--help'), @('-h'), @('help'), @('payloads'), @('dev'),
                @('help', 'doctor'), @('help', 'setup'), @('help', 'payloads', 'sync'),
                @('help', 'dev', 'test'), @('help', 'dev', 'check'), @('doctor', '--help'),
                @('setup', '-h'), @('payloads', 'sync', '--help'), @('dev', 'test', '-h'), @('dev', 'check', '--help'))) {
            $result = Invoke-CliChild $code @{
                DOTFILES_TEST_CLI_ROOT = $helpOnly; DOTFILES_TEST_CLI_ARGUMENTS = (ConvertTo-Json -InputObject $arguments -Compress)
                DOTFILES_TEST_CLI_CONTROL = ''; DOTFILES_TEST_CLI_SNAPSHOT = $snapshotPath
            }
            Assert-True ($result.Error -ceq '' -and $result.Out.Contains('dotfiles')) "Help failed for [$arguments]: $($result.Error)"
            [void](Assert-HelpHomeUnchanged $snapshotPath "Help [$arguments]")
        }
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
        Assert-True ($calls.Count -eq 1 -and $calls[0].Kind -ceq 'payloads-sync.ps1') 'Payload backend was not called once.'
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
$global:DotfilesCliSuccessObject = [pscustomobject]@{ Value = 'success-object' }
$logs = @{}
foreach ($number in 2..6) { $logs[$number] = Join-Path $env:DOTFILES_TEST_CLI_HOME "stream-$number.log" }
$success = @(& (Join-Path $env:DOTFILES_TEST_CLI_ROOT 'dotfiles.ps1') doctor 2> $logs[2] 3> $logs[3] 4> $logs[4] 5> $logs[5] 6> $logs[6])
$status = $LASTEXITCODE
if ($success.Count -ne 1 -or -not [object]::ReferenceEquals($success[0], $global:DotfilesCliSuccessObject)) { throw 'Success object was converted or mixed with another stream.' }
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
        Assert-True ($null -eq $bound.PSObject.Properties['Yes']) 'Dispatcher added Yes to setup.'
    }
    Test-Case 'initial ShouldContinue refusal is 2 while per-step Confirm refusal and WhatIf are 3' {
        [void](Invoke-CliChild -FileArguments @('setup') -Environment @{ DOTFILES_TEST_CLI_BEHAVIOR = 'continue' } -InputText "n`n" -ExpectedExit 2)
        [void](Invoke-CliChild -FileArguments @('setup', '--confirm') -Environment @{ DOTFILES_TEST_CLI_BEHAVIOR = 'process' } -InputText "n`n" -ExpectedExit 3)
        [void](Invoke-CliChild -FileArguments @('setup', '--what-if') -Environment @{ DOTFILES_TEST_CLI_BEHAVIOR = 'process' } -ExpectedExit 3)
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
    # Installed entrypoints require a validated fixture config even for help.
    # Only the child's process PATH changes; the real User PATH is never read or written.
    $launcher = Join-Path $emptyHome '.local/bin/dotfiles.ps1'
    Write-Fixture $launcher ([IO.File]::ReadAllText((Join-Path $sourceRoot 'home/dot_local/bin/dotfiles.ps1')))
    Write-Fixture (Join-Path $fixture 'lib/chezmoi-guard.ps1') ([IO.File]::ReadAllText((Join-Path $sourceRoot 'lib/chezmoi-guard.ps1')))
    Write-Fixture (Join-Path $fixture '.chezmoiroot') "home`n"
    # The guard accepts a linked worktree's .git file as well as a clone's directory.
    Write-Fixture (Join-Path $fixture '.git') "gitdir: unused-fixture`n"
    $config = Join-Path $emptyHome '.config/chezmoi/chezmoi.toml'
    $forms = & {
        . (Join-Path $sourceRoot 'lib/chezmoi-guard.ps1')
        foreach ($path in @($emptyHome, $fixture, $temporaryRoot)) {
            (Resolve-DotfilesDirectory $path).Replace('\', '/')
        }
    }
    $valid = 'destDir = "' + $forms[0] + '"' + "`n" + 'sourceDir = "' + $forms[1] + '"' + "`n"
    Write-Fixture $config $valid
    Write-Fixture (Join-Path $emptyHome 'dotfiles/dotfiles.ps1') "throw 'Wrong checkout selected.'"
    Test-Case 'installed help forwards to the selected checkout without running a backend' {
        $result = Invoke-CliChild "& (Join-Path `$HOME '.local/bin/dotfiles.ps1') --help; exit `$LASTEXITCODE"
        Assert-True ($result.Error -ceq '' -and $result.Out.Contains('Usage: dotfiles') -and @(Get-Events).Count -eq 0) 'Installed help failed or ran a backend.'
    }
    Test-Case 'installed explicit invocation selects configured worktree without PATH or profile' {
        [void](Invoke-CliChild @'
& (Join-Path $HOME '.local/bin/dotfiles.ps1') doctor --tier 'core, cli;literal'
exit $LASTEXITCODE
'@ @{ DOTFILES_TEST_CLI_STATUS = '3' } -ExpectedExit 3)
        $calls = @(Get-Events)
        Assert-True ($calls.Count -eq 1 -and $calls[0].Bound.Tier -ceq 'core, cli;literal') 'Installed launcher lost arguments or chose another checkout.'
    }
    Test-Case 'installed bare dotfiles is discovered through controlled process PATH with NoProfile' {
        [void](Invoke-CliChild 'dotfiles doctor --host win; exit $LASTEXITCODE' @{ PATH = (Split-Path -Parent $launcher) })
        Assert-True (@(Get-Events).Count -eq 1) 'Bare dotfiles did not invoke the configured dispatcher once.'
    }
    Test-Case 'installed invocation preserves the caller error preference for backend side streams' {
        $result = Invoke-CliChild @'
$ErrorActionPreference = 'Continue'
& (Join-Path $HOME '.local/bin/dotfiles.ps1') doctor
exit $LASTEXITCODE
'@ @{ DOTFILES_TEST_CLI_BEHAVIOR = 'nonterminating' }
        Assert-True ($result.Out.Trim() -ceq 'continued' -and $result.Error.Contains('backend-default-error') -and
            -not $result.Error.Contains('invocation failed')) 'Launcher changed a nonterminating backend error into termination.'
    }
    Test-Case 'installed help refuses absent duplicate malformed and foreign configs' {
        foreach ($text in @($null, ($valid + $valid), $valid.Replace('sourceDir = ', 'sourceDir='),
                $valid.Replace($forms[0], $forms[2]), $valid.Replace("`n", "`r`n"))) {
            [IO.File]::Delete($config)
            if ($null -ne $text) { Write-Fixture $config $text }
            $result = Invoke-CliChild "& (Join-Path `$HOME '.local/bin/dotfiles.ps1') --help; exit `$LASTEXITCODE" -ExpectedExit 1
            Assert-OneDiagnostic $result 'CHECKOUT'
        }
        Write-Fixture $config $valid
    }
    Test-Case 'installed help refuses missing guard or dispatcher' {
        foreach ($path in @((Join-Path $fixture 'lib/chezmoi-guard.ps1'), (Join-Path $fixture 'dotfiles.ps1'))) {
            Move-Item -LiteralPath $path -Destination "$path.hidden"
            try {
                $result = Invoke-CliChild "& (Join-Path `$HOME '.local/bin/dotfiles.ps1') --help; exit `$LASTEXITCODE" -ExpectedExit 1
                Assert-OneDiagnostic $result 'CHECKOUT'
            }
            finally { Move-Item -LiteralPath "$path.hidden" -Destination $path }
        }
    }
    Write-Output "powershell-cli=PASS ($script:Passed cases)"
}
finally {
    if ([IO.Path]::GetFileName($temporaryRoot) -notlike 'dotfiles-cli-ps-*') { throw 'Unexpected cleanup target.' }
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
}
