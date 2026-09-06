#Requires -Version 7.0
# Portable behavioral tests use a scripted PSHost for real ShouldProcess
# decisions. Win32 trust errors are injected here; the native fixture tests
# the actual guarded subprocess and filesystem implementation separately.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;
namespace DotfilesTests {
    public sealed class DecisionHost : PSHost {
        public readonly DecisionUI Decisions = new DecisionUI();
        public override Guid InstanceId { get; } = Guid.NewGuid();
        public override string Name => "Dotfiles installer test";
        public override Version Version => new Version(1, 0);
        public override CultureInfo CurrentCulture => CultureInfo.InvariantCulture;
        public override CultureInfo CurrentUICulture => CultureInfo.InvariantCulture;
        public override PSHostUserInterface UI => Decisions;
        public override void SetShouldExit(int code) { }
        public override void EnterNestedPrompt() { throw new NotSupportedException(); }
        public override void ExitNestedPrompt() { throw new NotSupportedException(); }
        public override void NotifyBeginApplication() { }
        public override void NotifyEndApplication() { }
    }
    public sealed class DecisionUI : PSHostUserInterface {
        public string Decline = "";
        public readonly List<string> Prompts = new List<string>();
        public override PSHostRawUserInterface RawUI => null;
        public override int PromptForChoice(string caption, string message,
                Collection<ChoiceDescription> choices, int defaultChoice) {
            Prompts.Add(message);
            string answer = message.Contains(Decline) && Decline.Length > 0 ? "No" : "Yes";
            for (int i = 0; i < choices.Count; i++)
                if (choices[i].Label.Replace("&", "") == answer) return i;
            throw new InvalidOperationException("Expected a Yes/No confirmation.");
        }
        public override string ReadLine() { throw new NotSupportedException(); }
        public override SecureString ReadLineAsSecureString() { throw new NotSupportedException(); }
        public override Dictionary<string, PSObject> Prompt(string c, string m, Collection<FieldDescription> d) { throw new NotSupportedException(); }
        public override PSCredential PromptForCredential(string c, string m, string u, string t) { throw new NotSupportedException(); }
        public override PSCredential PromptForCredential(string c, string m, string u, string t, PSCredentialTypes a, PSCredentialUIOptions o) { throw new NotSupportedException(); }
        public override void Write(string value) { }
        public override void Write(ConsoleColor foreground, ConsoleColor background, string value) { }
        public override void WriteLine(string value) { }
        public override void WriteErrorLine(string value) { }
        public override void WriteDebugLine(string value) { }
        public override void WriteProgress(long source, ProgressRecord record) { }
        public override void WriteVerboseLine(string value) { }
        public override void WriteWarningLine(string value) { }
    }
}
'@

$repoRoot = Split-Path $PSScriptRoot -Parent
$installerPath = Join-Path $repoRoot 'stow-all.ps1'
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($installerPath, [ref]$null, [ref]$parseErrors)
if ($parseErrors) { throw ($parseErrors -join "`n") }
$definitions = ($ast.FindAll({ param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst]
        }, $false) | ForEach-Object { $_.Extent.Text }) -join "`n"
$installerText = [IO.File]::ReadAllText($installerPath)
$completion = $installerText.Substring($installerText.IndexOf('# Preserve PowerShell''s warning stream'))
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-stow-controls-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$script:Passed = 0
$script:FixtureNumber = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function New-ControlFixture {
    $script:FixtureNumber++
    $root = Join-Path $testRoot $script:FixtureNumber
    $package = Join-Path $root 'common/git'
    [void][IO.Directory]::CreateDirectory($package)
    $source = Join-Path $package '.fixture'
    [IO.File]::WriteAllText($source, 'source content')
    $target = Join-Path $root 'target'
    [void][IO.Directory]::CreateDirectory($target)
    $stateHelper = Join-Path $root 'scripts/dotfiles-auto-stow.ps1'
    [void][IO.Directory]::CreateDirectory((Split-Path $stateHelper -Parent))
    [IO.File]::WriteAllText($stateHelper, 'function Save-DotfilesStowState { param($Repo, $HostDir, $ExpectedHead) [IO.File]::WriteAllText((Join-Path $Repo "state-saved"), "saved") }')
    return [pscustomobject]@{ Root = $root; Package = $package; Source = $source; Target = $target
        Destination = Join-Path $target '.fixture'; State = Join-Path $root 'state-saved' }
}
function Invoke-Control {
    param($Fixture, [string]$Decline = '', [switch]$Preview, [switch]$Strict,
        [int]$LinkError = 0, [int]$SourceError = 0, [bool]$Elevated = $true, [string]$Preparation = '',
        [string]$Action = 'Invoke-StowPackage -PackageRoot (Join-Path $RepoRoot "common") -PackageName git -GlobalIgnores @()')
    $hostFixture = [DotfilesTests.DecisionHost]::new()
    $hostFixture.Decisions.Decline = $Decline
    $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($hostFixture)
    $runspace.Open()
    $pipeline = [PowerShell]::Create()
    $pipeline.Runspace = $runspace
    try {
        $setup = @'
param($Fixture, $Preview, $StrictMode, $LinkError, $SourceError, $Elevated)
$ErrorActionPreference = 'Stop'
$ConfirmPreference = 'Low'
$WhatIfPreference = $Preview
$Strict = $StrictMode
$RepoRoot = $Fixture.Root
$Target = $Fixture.Target
$HostDir = ''
$stowStartHead = 'fixture-head'
$recordAppliedState = $true
$script:Linked = 0
$script:Repaired = 0
$script:Unchanged = 0
$script:BackedUp = 0
$script:Warnings = [Collections.Generic.List[string]]::new()
$script:InstalledPaths = [Collections.Generic.List[string]]::new()
$script:LinkReadErrors = @{ $Fixture.Destination = $LinkError; $Fixture.Source = $SourceError }
$script:IsElevated = $Elevated
function Write-DotfilesLog { param($Level, $Message) }
function Get-DotfilesLinkReadErrors {
    param([string[]]$Paths)
    $result = @{}
    foreach ($path in $Paths) { $result[$path] = 0 }
    return $result
}
'@
        $code = $setup + "`n" + $definitions + "`n" + $Preparation + "`n" + $Action + "`n" + $completion + @'

[pscustomobject]@{ Warnings = @($script:Warnings); Repaired = $script:Repaired }
'@
        [void]$pipeline.AddScript($code).AddArgument($Fixture).AddArgument([bool]$Preview).
            AddArgument([bool]$Strict).AddArgument($LinkError).AddArgument($SourceError).AddArgument($Elevated)
        $failure = ''
        $values = @()
        try { $values = @($pipeline.Invoke()) } catch { $failure = $_.Exception.Message }
        return [pscustomobject]@{ Failed = $pipeline.HadErrors -or [bool]$failure; Errors = "$failure`n$($pipeline.Streams.Error -join "`n")"
            Values = $values; Prompts = @($hostFixture.Decisions.Prompts) }
    } finally {
        $pipeline.Dispose()
        $runspace.Dispose()
    }
}
function Test-Case([string]$Name, [scriptblock]$Action) {
    & $Action
    $script:Passed++
    Write-Output "PASS: $Name"
}
try {
    Test-Case 'declining a conflict preserves original bytes and suppresses replacement and state' {
        $fixture = New-ControlFixture
        [IO.File]::WriteAllText($fixture.Destination, 'irreplaceable original')
        $result = Invoke-Control $fixture -Decline 'Back up'
        Assert-True (-not $result.Failed) $result.Errors
        Assert-True ($result.Prompts.Count -eq 1) 'Backup and replacement must be one confirmation.'
        Assert-True ($result.Prompts[0].Contains('and link to')) 'Confirmation did not describe the complete operation.'
        Assert-True ([IO.File]::ReadAllText($fixture.Destination) -ceq 'irreplaceable original') 'Declined backup lost content.'
        Assert-True (-not (Get-Item -LiteralPath $fixture.Destination -Force).LinkType) 'Declined file became a link.'
        Assert-True (@(Get-ChildItem -LiteralPath $fixture.Target -Force -Filter '*.stow-backup-*').Count -eq 0) 'Declined backup was moved.'
        Assert-True (-not (Test-Path -LiteralPath $fixture.State)) 'Partial install advanced applied state.'
    }
    Test-Case 'Strict fails after a declined new link and does not acknowledge' {
        $fixture = New-ControlFixture
        $result = Invoke-Control $fixture -Decline 'Link to' -Strict
        Assert-True $result.Failed 'Strict accepted a declined link.'
        Assert-True ($result.Errors.Contains('automatic state was not advanced')) $result.Errors
        Assert-True (-not (Test-Path -LiteralPath $fixture.Destination)) 'Declined new link was created.'
        Assert-True (-not (Test-Path -LiteralPath $fixture.State)) 'Strict failure advanced state.'
    }
    Test-Case 'declining stale-link replacement and identical-file adoption preserves both originals' {
        foreach ($kind in @('stale', 'identical')) {
            $fixture = New-ControlFixture
            if ($kind -eq 'stale') {
                $oldTarget = Join-Path $fixture.Root 'old-target'
                [IO.File]::WriteAllText($oldTarget, 'old content')
                New-Item -ItemType SymbolicLink -Path $fixture.Destination -Value $oldTarget | Out-Null
                $decline = 'Replace stale'
            } else {
                [IO.File]::WriteAllText($fixture.Destination, 'source content')
                $decline = 'Adopt identical'
            }
            $result = Invoke-Control $fixture -Decline $decline
            Assert-True (-not $result.Failed) $result.Errors
            Assert-True ($result.Prompts.Count -eq 1) 'A declined removal fell through to a second prompt.'
            if ($kind -eq 'stale') {
                Assert-True (@((Get-Item -LiteralPath $fixture.Destination -Force).Target)[0] -eq $oldTarget) 'Stale link changed after decline.'
            } else {
                Assert-True (-not (Get-Item -LiteralPath $fixture.Destination -Force).LinkType) 'Identical file changed after decline.'
            }
            Assert-True (-not (Test-Path -LiteralPath $fixture.State)) 'Declined change advanced state.'
        }
    }
    Test-Case 'accepted backup and replacement use a single confirmation and retain backup bytes' {
        $fixture = New-ControlFixture
        [IO.File]::WriteAllText($fixture.Destination, 'backup me')
        $result = Invoke-Control $fixture
        Assert-True (-not $result.Failed) $result.Errors
        Assert-True ($result.Prompts.Count -eq 1) 'Internal filesystem commands prompted again.'
        Assert-True ((Get-Item -LiteralPath $fixture.Destination -Force).LinkType -eq 'SymbolicLink') 'Approved replacement did not link.'
        $backups = @(Get-ChildItem -LiteralPath $fixture.Target -Force -Filter '*.stow-backup-*')
        Assert-True ($backups.Count -eq 1 -and [IO.File]::ReadAllText($backups[0].FullName) -ceq 'backup me') 'Approved backup was not preserved.'
        Assert-True (Test-Path -LiteralPath $fixture.State) 'Complete install did not record state.'
    }
    Test-Case 'declined portable sync still performs preflight, skips apply and fails Strict' {
        $fixture = New-ControlFixture
        $bash = if ($IsWindows) {
            $gitDir = Split-Path (Get-Command git -CommandType Application | Select-Object -First 1).Source -Parent
            $found = $null
            while ($gitDir -and -not $found) {
                foreach ($relative in @('bin/bash.exe', 'usr/bin/bash.exe')) {
                    $candidate = Join-Path $gitDir $relative
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $found = $candidate; break }
                }
                $gitDir = Split-Path $gitDir -Parent
            }
            if (-not $found) { throw 'Git Bash is required for the portable sync confirmation test.' }
            $found
        } else { (Get-Command bash -CommandType Application | Select-Object -First 1).Source }
        $fakeGitBin = Join-Path $fixture.Root 'git/bin'
        [void][IO.Directory]::CreateDirectory($fakeGitBin)
        New-Item -ItemType SymbolicLink -Path (Join-Path $fakeGitBin 'bash.exe') -Value $bash | Out-Null
        $helper = Join-Path $fixture.Root 'sync-helper'
        [IO.File]::WriteAllText($helper, 'printf ''%s\n'' "$*" >> "$0.calls"' + "`n")
        $preparation = @'
function Get-Command {
    param($Name, $CommandType, $ErrorAction)
    [pscustomobject]@{ Source = Join-Path $Fixture.Root 'git/cmd/git.exe' }
}
'@
        $action = @'
$sync = @{ Helper = Join-Path $Fixture.Root 'sync-helper'; Portable = $Fixture.Source
    Live = Join-Path $Fixture.Target 'live.json'; Label = 'fixture' }
Invoke-PortableSync @sync -CheckOnly
Invoke-PortableSync @sync
'@
        $result = Invoke-Control $fixture -Decline 'Synchronize portable' -Strict -Preparation $preparation -Action $action
        Assert-True $result.Failed 'Strict accepted a declined portable sync.'
        Assert-True ($result.Errors.Contains('automatic state was not advanced')) $result.Errors
        $calls = @([IO.File]::ReadAllLines("$helper.calls"))
        Assert-True ($calls.Count -eq 1 -and $calls[0].Contains('--check')) 'Declined apply ran or preflight was skipped.'
        Assert-True (-not (Test-Path -LiteralPath $fixture.State)) 'Declined portable sync advanced state.'
    }
    Test-Case 'WhatIf remains successful under Strict and writes no files or state' {
        $fixture = New-ControlFixture
        $result = Invoke-Control $fixture -Preview -Strict
        Assert-True (-not $result.Failed) $result.Errors
        Assert-True ($result.Prompts.Count -eq 0) 'WhatIf asked an interactive question.'
        Assert-True (-not (Test-Path -LiteralPath $fixture.Destination)) 'WhatIf created a link.'
        Assert-True (-not (Test-Path -LiteralPath $fixture.State)) 'WhatIf advanced state.'
    }
    Test-Case 'guarded rejection repairs a matching locally-readable link; healthy rerun is unchanged' {
        $fixture = New-ControlFixture
        New-Item -ItemType SymbolicLink -Path $fixture.Destination -Value $fixture.Source | Out-Null
        Assert-True ([IO.File]::ReadAllText($fixture.Destination) -ceq 'source content') 'Fixture must open locally.'
        $result = Invoke-Control $fixture -LinkError 448
        Assert-True (-not $result.Failed) $result.Errors
        Assert-True ($result.Prompts.Count -eq 1 -and $result.Prompts[0].Contains('Repair untrusted symlink')) 'Guarded rejection did not trigger repair.'
        $again = Invoke-Control $fixture
        Assert-True (-not $again.Failed -and $again.Prompts.Count -eq 0) 'Trusted link was rewritten on rerun.'
    }
    Test-Case 'declined or unelevated trust repairs remain partial' {
        foreach ($elevated in @($true, $false)) {
            $fixture = New-ControlFixture
            New-Item -ItemType SymbolicLink -Path $fixture.Destination -Value $fixture.Source | Out-Null
            $result = Invoke-Control $fixture -LinkError 448 -Elevated $elevated -Decline 'Repair untrusted'
            Assert-True (-not $result.Failed) $result.Errors
            Assert-True (-not (Test-Path -LiteralPath $fixture.State)) 'Unrepaired trust advanced state.'
            Assert-True ([IO.File]::ReadAllText($fixture.Destination) -ceq 'source content') 'Unrepaired link lost its target.'
        }
    }
    Test-Case 'source trust repair preserves the relative target and then installs the destination' {
        $fixture = New-ControlFixture
        Remove-Item -LiteralPath $fixture.Source -Force
        $underlying = Join-Path $fixture.Package 'underlying'
        [IO.File]::WriteAllText($underlying, 'source content')
        New-Item -ItemType SymbolicLink -Path $fixture.Source -Value './underlying' | Out-Null
        $originalTarget = @((Get-Item -LiteralPath $fixture.Source -Force).Target)[0]
        Assert-True (-not [IO.Path]::IsPathRooted($originalTarget)) 'Fixture source target is not relative.'
        $result = Invoke-Control $fixture -SourceError 448
        Assert-True (-not $result.Failed) $result.Errors
        Assert-True (@((Get-Item -LiteralPath $fixture.Source -Force).Target)[0] -ceq $originalTarget) 'Source relative target was rewritten.'
        Assert-True ((Get-Item -LiteralPath $fixture.Destination -Force).LinkType -eq 'SymbolicLink') 'Source repair did not allow destination install.'
    }
    Test-Case 'other read failures are reported instead of being treated as trustworthy' {
        $fixture = New-ControlFixture
        New-Item -ItemType SymbolicLink -Path $fixture.Destination -Value $fixture.Source | Out-Null
        $result = Invoke-Control $fixture -LinkError 5 -Strict
        Assert-True $result.Failed 'Unreadable symlink was treated as healthy.'
        Assert-True ($result.Prompts.Count -eq 0) 'A permission failure was rewritten as a trust repair.'
        Assert-True (-not (Test-Path -LiteralPath $fixture.State)) 'Unreadable link advanced state.'
    }
    if (-not $IsWindows) {
        Test-Case 'unavailable native trust API fails closed in an isolated child process' {
            . (Join-Path $repoRoot 'lib/windows-link-trust.ps1')
            $failed = $false
            try { [void](Get-DotfilesLinkReadErrors -Paths @($installerPath)) } catch {
                $failed = $_.Exception.Message.Contains('Cannot verify symlink trust with RedirectionGuard')
            }
            Assert-True $failed 'Unavailable trust policy was silently treated as healthy.'
        }
    }
    Write-Output "windows-installer-controls=PASS ($script:Passed cases)"
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
