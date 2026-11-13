#Requires -Version 7.0
# Parse GNU-style arguments before invoking the native Windows command backends.
# No param block: PowerShell named-parameter binding must not consume $args.
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false

function Stop-DotfilesCli([string]$Message, [int]$Status = 2) {
    [Console]::Error.WriteLine('dotfiles: ' + ($Message -replace '[\r\n]+', ' '))
    exit $Status
}

function Write-DotfilesCliHelp([string]$Command = '') {
    switch -CaseSensitive ($Command) {
        '' {
            Write-Output @'
Usage: dotfiles COMMAND [OPTIONS]

Commands:
  doctor          Check this Windows host (offline and read-only by default).
  setup           Install host tools; --check shows work without changes.
  payloads sync   Install or update payload repositories.
  dev test        Run the test suite in a fresh PowerShell process.
  dev check       Run pre-commit run --all-files in this checkout.
  help [COMMAND]  Show help without running a backend.

Use dotfiles help COMMAND for command options. Requires PowerShell 7.0+.
'@
        }
        'doctor' {
            Write-Output @'
Usage: dotfiles doctor [OPTIONS]
  --host VALUE    Host name (Windows backend default: win).
  --tier VALUE    all or a quoted comma list, e.g. 'core,cli,ai'.
  --tsv           Emit tab-separated results.
  --quiet         Omit successful and skipped checks.
  --online        Include authentication probes.
  --help, -h      Show this help.

Value options also accept --name=VALUE. Checks are offline and read-only
unless --online is selected. Unix-only options are unavailable here.
'@
        }
        'setup' {
            Write-Output @'
Usage: dotfiles setup [OPTIONS]
  --host VALUE    Host name (Windows backend default: win).
  --tier VALUE    all or a quoted comma list, e.g. 'core,cli,ai'.
  --check         Show pending work, offline and without changes.
  --yes           Accept the backend's supported installation prompts.
  --print-manual  Print person-run instructions.
  --what-if       Forward PowerShell -WhatIf.
  --confirm       Forward PowerShell -Confirm.
  --help, -h      Show this help.

Value options also accept --name=VALUE. Exit 3 means work remains.
'@
        }
        'payloads' { Write-Output 'Usage: dotfiles payloads sync [ITEM...]' }
        'payloads sync' {
            Write-Output @'
Usage: dotfiles payloads sync [ITEM...]
Install or update the selected payload repositories in the foreground.
With no items, the backend selects the Windows defaults. Maintenance blocks
execution. Item validation, retries and locking belong to the backend.
  --help, -h      Show this help.
'@
        }
        'dev' {
            Write-Output @'
Usage: dotfiles dev test [OPTIONS]
       dotfiles dev check
'@
        }
        'dev test' {
            Write-Output @'
Usage: dotfiles dev test [OPTIONS]
  --ci                    Require native Windows CI prerequisites.
  --check-prerequisites   Check dependencies without running suites.
  --help, -h              Show this help.

Run tests/run.ps1 in a fresh current PowerShell with -NoProfile -File.
Missing dependencies are reported without installing them.
'@
        }
        'dev check' {
            Write-Output @'
Usage: dotfiles dev check
Run pre-commit run --all-files from this checkout. Existing hooks include
behavior tests and may format files. Missing dependencies are not installed.
  --help, -h      Show this help.
'@
        }
    }
}

$tokens = @($args)
foreach ($token in $tokens) {
    if ($token -isnot [string]) { Stop-DotfilesCli 'arguments must be strings; quote comma lists and do not pass arrays or objects.' }
}
if ($tokens.Count -eq 0) { Write-DotfilesCliHelp; exit 0 }
if ($tokens.Count -eq 1 -and $tokens[0] -cin @('--help', '-h')) { Write-DotfilesCliHelp; exit 0 }

$helpRequested = $tokens[0] -ceq 'help'
$offset = if ($helpRequested) { 1 } else { 0 }
if ($offset -eq $tokens.Count) { Write-DotfilesCliHelp; exit 0 }
$command = $tokens[$offset]
$offset++
switch -CaseSensitive ($command) {
    'doctor' { }
    'setup' { }
    { $_ -cin @('payloads', 'dev') } {
        if ($offset -eq $tokens.Count) { Write-DotfilesCliHelp $command; exit 0 }
        if ($tokens.Count -eq $offset + 1 -and $tokens[$offset] -cin @('--help', '-h') -and -not $helpRequested) {
            Write-DotfilesCliHelp $command
            exit 0
        }
        $subcommand = $tokens[$offset]
        if (($command -ceq 'payloads' -and $subcommand -cne 'sync') -or
            ($command -ceq 'dev' -and $subcommand -cnotin @('test', 'check'))) {
            Stop-DotfilesCli "unknown command '$command $subcommand'."
        }
        $command += " $subcommand"
        $offset++
    }
    default { Stop-DotfilesCli "unknown command '$command'." }
}
if ($helpRequested) {
    if ($offset -ne $tokens.Count) { Stop-DotfilesCli "unknown help path after '$command'." }
    Write-DotfilesCliHelp $command
    exit 0
}

$valueOptions = @{}
$switchOptions = @{}
switch -CaseSensitive ($command) {
    'doctor' {
        $valueOptions = @{ '--host' = 'HostName'; '--tier' = 'Tier' }
        $switchOptions = @{ '--tsv' = 'Tsv'; '--quiet' = 'Quiet'; '--online' = 'Online' }
    }
    'setup' {
        $valueOptions = @{ '--host' = 'HostName'; '--tier' = 'Tier' }
        $switchOptions = @{ '--check' = 'Check'; '--yes' = 'Yes'; '--print-manual' = 'PrintManual'; '--what-if' = 'WhatIf'; '--confirm' = 'Confirm' }
    }
    'dev test' { $switchOptions = @{ '--ci' = 'CI'; '--check-prerequisites' = 'CheckPrerequisites' } }
}
$parameters = @{}
$items = [Collections.Generic.List[string]]::new()
while ($offset -lt $tokens.Count) {
    $token = $tokens[$offset]
    $offset++
    if ($token -cin @('--help', '-h')) { $helpRequested = $true; continue }
    $name = $token
    $equals = $token.IndexOf('=')
    if ($equals -ge 0) { $name = $token.Substring(0, $equals) }
    if ($name -cin $valueOptions.Keys) {
        if ($equals -ge 0) { $value = $token.Substring($equals + 1) }
        else {
            if ($offset -eq $tokens.Count -or $tokens[$offset].StartsWith('-')) { Stop-DotfilesCli "missing value for '$name'." }
            $value = $tokens[$offset]
            $offset++
        }
        if ($value.Length -eq 0) { Stop-DotfilesCli "empty value for '$name'." }
        $parameters[$valueOptions[$name]] = $value
    }
    elseif ($token -cin $switchOptions.Keys) { $parameters[$switchOptions[$token]] = $true }
    elseif ($command -ceq 'payloads sync' -and $token.Length -gt 0 -and -not $token.StartsWith('-')) { $items.Add($token) }
    else { Stop-DotfilesCli "unknown option or argument '$token' for '$command'." }
}
if ($helpRequested) { Write-DotfilesCliHelp $command; exit 0 }

$backend = ''
$childArguments = @()
switch -CaseSensitive ($command) {
    'doctor' { $backend = Join-Path $PSScriptRoot 'scripts/commands/doctor.ps1' }
    'setup' { $backend = Join-Path $PSScriptRoot 'scripts/commands/setup.ps1' }
    'payloads sync' {
        $backend = Join-Path $PSScriptRoot 'scripts/commands/payloads-sync.ps1'
        $parameters = @{ Now = $true }
        if ($items.Count -gt 0) { $parameters.Item = $items.ToArray() }
    }
    'dev test' {
        $runner = Join-Path $PSScriptRoot 'tests/run.ps1'
        if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) { Stop-DotfilesCli "missing backend '$runner'." 1 }
        $backend = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
        $childArguments = @('-NoProfile', '-File', $runner)
        if ($parameters.ContainsKey('CI')) { $childArguments += '-CI' }
        if ($parameters.ContainsKey('CheckPrerequisites')) { $childArguments += '-CheckPrerequisites' }
    }
    'dev check' {
        try {
            $preCommit = Get-Command 'pre-commit' -CommandType Application, ExternalScript -ErrorAction Stop | Select-Object -First 1
            $backend = $preCommit.Source
        }
        catch { Stop-DotfilesCli 'required executable pre-commit was not found.' 1 }
        $childArguments = @('run', '--all-files')
    }
}
if (-not (Test-Path -LiteralPath $backend -PathType Leaf)) { Stop-DotfilesCli "missing backend or executable '$backend'." 1 }

$savedLocation = Get-Location
try {
    if ($command -ceq 'dev check') { Set-Location -LiteralPath $PSScriptRoot -ErrorAction Stop }
    # Native commands and script exit update the global automatic variable.
    # A script-local variable here would hide native failures in a backend.
    $global:LASTEXITCODE = 0
    if ($command -cin @('dev test', 'dev check')) { & $backend @childArguments }
    else { & $backend @parameters }
    $status = $global:LASTEXITCODE
}
catch {
    [Console]::Error.WriteLine('dotfiles: invocation failed: ' + ($_.Exception.Message -replace '[\r\n]+', ' '))
    $status = 1
}
finally {
    if ($command -ceq 'dev check') { Set-Location -LiteralPath $savedLocation.ProviderPath -ErrorAction Stop }
}
exit $status
