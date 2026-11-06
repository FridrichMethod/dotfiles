#Requires -Version 7.0
# Real child processes exercise emitted VT bytes and PowerShell redirection.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path $PSScriptRoot -Parent
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-terminal-ps-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporaryRoot)
$script:Passed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Invoke-LogChild {
    param([string]$Command, [hashtable]$Environment = @{}, [int]$ExpectedExit = 0)
    $start = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile', '-NonInteractive', '-Command', $Command)) {
        $start.ArgumentList.Add($argument)
    }
    foreach ($name in @('DOTFILES_COLOR', 'NO_COLOR', '_DOTFILES_CHECKED')) {
        [void]$start.Environment.Remove($name)
    }
    $start.Environment['TERM'] = 'xterm-256color'
    $start.Environment['DOTFILES_TEST_ROOT'] = $sourceRoot
    $start.Environment['DOTFILES_TEST_TEMP'] = $temporaryRoot
    foreach ($name in $Environment.Keys) { $start.Environment[$name] = $Environment[$name] }
    $child = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $child.StandardOutput.ReadToEndAsync()
        $stderr = $child.StandardError.ReadToEndAsync()
        if (-not $child.WaitForExit(30000)) {
            $child.Kill($true)
            throw 'Logging child timed out.'
        }
        $outputText = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        Assert-True ($child.ExitCode -eq $ExpectedExit) "Child exit $($child.ExitCode), expected ${ExpectedExit}: $outputText $errorText"
        Assert-True ($errorText -eq '') "Logging unexpectedly wrote PowerShell errors: $errorText"
        return $outputText
    }
    finally { $child.Dispose() }
}
function Test-Case {
    param([string]$Name, [scriptblock]$Action)
    & $Action
    $script:Passed++
    Write-Output "PASS: $Name"
}

$emit = @'
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$style = Get-Variable PSStyle -ValueOnly -ErrorAction SilentlyContinue
if ($style) { $style.OutputRendering = 'PlainText' }
. (Join-Path $env:DOTFILES_TEST_ROOT 'lib/terminal.ps1')
$LASTEXITCODE = 19
foreach ($level in @('step', 'ok', 'warn', 'error', 'info')) {
    $output = @(Write-DotfilesLog $level 'literal 100% %s %n {0}')
    if ($output.Count) { throw 'Logger polluted the success pipeline.' }
}
if ($LASTEXITCODE -ne 19) { throw 'Logger changed native exit status.' }
if ($ErrorActionPreference -ne 'Stop' -or -not $PSNativeCommandUseErrorActionPreference) { throw 'Logger changed preferences.' }
if ($style -and $style.OutputRendering -ne 'PlainText') { throw 'Logger changed PSStyle output rendering.' }
'@
try {
    Test-Case 'forced color emits exact VT badges and preserves preferences and percent text' {
        $outputText = Invoke-LogChild $emit @{ DOTFILES_COLOR = 'always' }
        foreach ($pair in @(@('step', '1;36'), @('ok', '32'), @('warn', '33'), @('error', '31'))) {
            $expected = "$([char]27)[$($pair[1])m[dotfiles] [$($pair[0])] literal 100% %s %n {0}$([char]27)[0m"
            Assert-True ($outputText.Contains($expected)) "Missing actual ANSI sequence for $($pair[0])."
        }
        Assert-True ($outputText.Contains('[dotfiles] [info] literal 100% %s %n {0}')) 'Plain info message missing.'
    }
    Test-Case 'auto piped output and explicit no-color controls remain plain' {
        foreach ($environment in @(@{}, @{ DOTFILES_COLOR = 'auto' }, @{ DOTFILES_COLOR = 'invalid' },
                @{ DOTFILES_COLOR = 'never' }, @{ DOTFILES_COLOR = 'always'; NO_COLOR = '1' },
                @{ DOTFILES_COLOR = 'always'; NO_COLOR = '0' }, @{ DOTFILES_COLOR = 'always'; TERM = 'dumb' })) {
            $outputText = Invoke-LogChild $emit $environment
            Assert-True (-not $outputText.Contains([string][char]27)) "Unexpected ANSI for $($environment | ConvertTo-Json -Compress)."
            foreach ($level in @('step', 'ok', 'warn', 'error', 'info')) {
                Assert-True ($outputText.Contains("[dotfiles] [$level] literal 100% %s %n {0}")) "Missing $level diagnostic."
            }
        }
    }
    Test-Case 'empty NO_COLOR does not disable an explicit color request' {
        $outputText = Invoke-LogChild $emit @{ DOTFILES_COLOR = 'always'; NO_COLOR = '' }
        Assert-True ($outputText.Contains("$([char]27)[1;36m")) 'Empty NO_COLOR disabled forced color.'
    }
    Test-Case 'worker-style all-stream redirection captures all badges as plain text' {
        $outputText = Invoke-LogChild @'
$ErrorActionPreference = 'Stop'
. (Join-Path $env:DOTFILES_TEST_ROOT 'lib/terminal.ps1')
$log = Join-Path $env:DOTFILES_TEST_TEMP 'worker.log'
& {
    foreach ($level in @('step', 'ok', 'warn', 'error', 'info')) { Write-DotfilesLog $level 'worker message' }
    Write-Output 'native-style output'
} *> $log
[Console]::Out.Write([IO.File]::ReadAllText($log))
'@
        Assert-True (-not $outputText.Contains([string][char]27)) 'Task log contains ANSI.'
        foreach ($level in @('step', 'ok', 'warn', 'error', 'info')) {
            Assert-True ($outputText.Contains("[dotfiles] [$level] worker message")) "Task log lost $level."
        }
        Assert-True ($outputText.Contains('native-style output')) 'Task log lost non-logger output.'
    }
    Test-Case 'failure diagnostics neither throw on Stop nor hide failure status' {
        $outputText = Invoke-LogChild @'
$ErrorActionPreference = 'Stop'
. (Join-Path $env:DOTFILES_TEST_ROOT 'lib/terminal.ps1')
try { throw 'expected failure 100%' }
catch { Write-DotfilesLog error $_.Exception.Message; exit 17 }
'@ @{ DOTFILES_COLOR = 'never' } -ExpectedExit 17
        Assert-True ($outputText.Contains('[dotfiles] [error] expected failure 100%')) 'Failure diagnostic disappeared.'
    }
    Test-Case 'same-session redirection stays plain even with Ansi rendering preference' {
        # Run this suite under a PTY too: unlike child-process pipes, *> leaves
        # Console.IsOutputRedirected false in an interactive console.
        $savedEnvironment = @{}
        foreach ($name in @('DOTFILES_COLOR', 'NO_COLOR', 'TERM')) {
            $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
        }
        $style = Get-Variable PSStyle -ValueOnly -ErrorAction SilentlyContinue
        $rendering = if ($style) { $style.OutputRendering } else { $null }
        try {
            $env:DOTFILES_COLOR = 'auto'
            $env:TERM = 'xterm-256color'
            Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue
            if ($style) { $style.OutputRendering = 'Ansi' }
            . (Join-Path $sourceRoot 'lib/terminal.ps1')
            $log = Join-Path $temporaryRoot 'same-session.log'
            & {
                foreach ($level in @('step', 'ok', 'warn', 'error', 'info')) { Write-DotfilesLog $level 'same-session log' }
            } *> $log
            $content = [IO.File]::ReadAllText($log)
            Assert-True (-not $content.Contains([string][char]27)) 'Auto color contaminated same-session redirection.'
            foreach ($level in @('step', 'ok', 'warn', 'error', 'info')) {
                Assert-True ($content.Contains("[dotfiles] [$level] same-session log")) "Same-session redirection lost $level."
            }
            Write-Output "same-session-console-redirected=$([Console]::IsOutputRedirected)"
        }
        finally {
            if ($style) { $style.OutputRendering = $rendering }
            foreach ($name in $savedEnvironment.Keys) {
                if ($null -eq $savedEnvironment[$name]) { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue }
                else { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name]) }
            }
        }
    }
    Test-Case 'missing or broken optional logging library leaves the entry points plain fallback' {
        # A partial checkout holds an entry point without lib/bootstrap.ps1, so
        # it stops with its one diagnostic before any check. The real library
        # is the positive control: only then is the badge colored.
        $fixture = Join-Path $temporaryRoot 'partial checkout'
        $libraryDirectory = Join-Path $fixture 'lib'
        [void][IO.Directory]::CreateDirectory($libraryDirectory)
        $logger = Join-Path $libraryDirectory 'terminal.ps1'
        foreach ($entry in @('doctor.ps1', 'setup-host.ps1')) {
            Copy-Item -LiteralPath (Join-Path $sourceRoot $entry) -Destination $fixture
            foreach ($state in @('missing', 'broken', 'present')) {
                switch ($state) {
                    'missing' { [IO.File]::Delete($logger) }
                    'broken' { [IO.File]::WriteAllText($logger, "throw 'broken optional logger'") }
                    'present' { Copy-Item -LiteralPath (Join-Path $sourceRoot 'lib/terminal.ps1') -Destination $logger -Force }
                }
                # Without the explicit exit, -Command would turn the script's exit 2 into 1.
                $outputText = Invoke-LogChild "& (Join-Path `$env:DOTFILES_TEST_TEMP 'partial checkout/$entry'); exit `$LASTEXITCODE" @{ DOTFILES_COLOR = 'always' } -ExpectedExit 2
                $plainText = $outputText.Replace("$([char]27)[31m", '').Replace("$([char]27)[0m", '').Trim()
                Assert-True ($plainText.StartsWith('[dotfiles] [error] Missing ') -and $plainText.EndsWith('bootstrap.ps1; this checkout is incomplete.')) "$entry lost its diagnostic with a $state logging library: $plainText"
                Assert-True ($outputText.Contains([string][char]27) -eq ($state -eq 'present')) "$entry colored its diagnostic wrongly with a $state logging library."
            }
        }
    }
    Write-Output "powershell-terminal=PASS ($script:Passed cases)"
}
finally {
    # Only this suite's explicitly created disposable directory is removed.
    if ([IO.Path]::GetFileName($temporaryRoot) -notlike 'dotfiles-terminal-ps-*') { throw 'Unexpected cleanup target.' }
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
}
