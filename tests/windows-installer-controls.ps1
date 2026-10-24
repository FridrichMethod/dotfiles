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
# -C cannot neutralize an inherited GIT_DIR or GIT_INDEX_FILE, which a commit
# hook in a linked worktree exports, absolute: the fixture git init and add
# would reinitialize and stage into the caller's repository, and the
# installer's own git in each runspace would read its index. Remove every
# GIT_* entry for the whole run, as tests/windows-installer.ps1 does, and
# restore them at the end.
$environmentNames = @(@('GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM', 'GIT_TEMPLATE_DIR') +
    @(Get-ChildItem Env: | Where-Object Name -Like 'GIT_*' | Select-Object -ExpandProperty Name) |
    Sort-Object -Unique)
$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
    Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath "Env:$name") { throw "Environment override was not removed: $name" }
}
$env:GIT_CONFIG_GLOBAL = Join-Path $testRoot 'empty.gitconfig'
[IO.File]::WriteAllText($env:GIT_CONFIG_GLOBAL, '')
$env:GIT_CONFIG_NOSYSTEM = '1'
$env:GIT_TEMPLATE_DIR = Join-Path $testRoot 'empty-git-template'
[void][IO.Directory]::CreateDirectory($env:GIT_TEMPLATE_DIR)
$script:Passed = 0
$script:FixtureNumber = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Remove-ControlFixture([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    # Remove-Item -Force changes attributes through symlinks before unlinking.
    # Unlink first so targets such as macOS's read-only system Bash stay untouched.
    foreach ($link in Get-ChildItem -LiteralPath $Path -Recurse -Force | Where-Object LinkType -EQ SymbolicLink) {
        if ($link.PSIsContainer) { [IO.Directory]::Delete($link.FullName) }
        else { [IO.File]::Delete($link.FullName) }
    }
    Remove-Item -LiteralPath $Path -Recurse -Force
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
    Test-Case 'retired launcher links honor preview, decline and Strict without following targets' {
        foreach ($name in @('shk', 'codex-instructions-sync')) {
            foreach ($mode in @('apply', 'preview', 'decline', 'strict')) {
                $fixture = New-ControlFixture
                $relative = ".local/bin/$name"
                $link = Join-Path $fixture.Target $relative
                [void][IO.Directory]::CreateDirectory((Split-Path $link -Parent))
                $oldSource = Join-Path $fixture.Root "common/codex/$relative"
                New-Item -ItemType SymbolicLink -Path $link -Value $oldSource | Out-Null
                $decline = if ($mode -in @('decline', 'strict')) { 'Remove retired dotfiles symlink' } else { '' }
                $result = Invoke-Control $fixture -Preview:($mode -eq 'preview') -Strict:($mode -eq 'strict') -Decline $decline `
                    -Action "Remove-RetiredLink '$relative' 'common/codex/$relative'"
                Assert-True ($result.Failed -eq ($mode -eq 'strict')) "Wrong Strict result: $($result.Errors)"
                $remaining = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
                Assert-True ([bool]$remaining -eq ($mode -ne 'apply')) "Retirement changed the wrong entry in $mode mode."
                Assert-True ((Test-Path -LiteralPath $fixture.State) -eq ($mode -eq 'apply')) "Retirement acknowledged $mode."
                if ($mode -in @('decline', 'strict')) {
                    Assert-True (@($result.Prompts | Where-Object { $_ -like '*Remove retired dotfiles symlink*' }).Count -eq 1) 'Removal asked more than once.'
                }
            }
            foreach ($kind in @('live', 'foreign', 'file')) {
                $fixture = New-ControlFixture
                $relative = ".local/bin/$name"
                $link = Join-Path $fixture.Target $relative
                [void][IO.Directory]::CreateDirectory((Split-Path $link -Parent))
                $oldSource = Join-Path $fixture.Root "common/codex/$relative"
                if ($kind -eq 'file') { [IO.File]::WriteAllText($link, 'manual') }
                else {
                    if ($kind -eq 'live') {
                        [void][IO.Directory]::CreateDirectory((Split-Path $oldSource -Parent))
                        [IO.File]::WriteAllText($oldSource, 'live')
                    } else { $oldSource = Join-Path $fixture.Root "foreign/$name" }
                    New-Item -ItemType SymbolicLink -Path $link -Value $oldSource | Out-Null
                }
                $result = Invoke-Control $fixture -Action "Remove-RetiredLink '$relative' 'common/codex/$relative'"
                Assert-True (-not $result.Failed) $result.Errors
                Assert-True ([bool](Get-Item -LiteralPath $link -Force)) "Lost $kind entry."
                Assert-True ($result.Prompts.Count -eq 0) "Prompted for $kind entry."
            }
        }
    }
    Test-Case 'fixture cleanup preserves external read-only targets and removes dangling links' {
        $fixture = New-ControlFixture
        $cleanupRoot = Join-Path $fixture.Root 'cleanup'
        [void][IO.Directory]::CreateDirectory($cleanupRoot)
        $attributes = [IO.File]::GetAttributes($fixture.Source)
        try {
            [IO.File]::SetAttributes($fixture.Source, $attributes -bor [IO.FileAttributes]::ReadOnly)
            $readOnlyAttributes = [IO.File]::GetAttributes($fixture.Source)
            New-Item -ItemType SymbolicLink -Path (Join-Path $cleanupRoot 'read-only') -Value $fixture.Source | Out-Null
            New-Item -ItemType SymbolicLink -Path (Join-Path $cleanupRoot 'directory') -Value $fixture.Package | Out-Null
            New-Item -ItemType SymbolicLink -Path (Join-Path $cleanupRoot 'dangling') -Value (Join-Path $fixture.Root 'missing') | Out-Null
            Remove-ControlFixture $cleanupRoot
            Assert-True (-not (Test-Path -LiteralPath $cleanupRoot)) 'Fixture cleanup left files behind.'
            Assert-True ([IO.File]::ReadAllText($fixture.Source) -ceq 'source content') 'Cleanup changed external target bytes.'
            Assert-True ([IO.File]::GetAttributes($fixture.Source) -eq $readOnlyAttributes) 'Cleanup changed external target attributes.'
        } finally {
            [IO.File]::SetAttributes($fixture.Source, $attributes)
        }
    }
    Test-Case 'a path-anchored local ignore skips only the package-root entry, as GNU Stow does' {
        # Stow matches a pattern that contains a slash against "/PATH", so
        # ^/vendored/ hides the package's vendored/ tree (a submodule
        # checkout) but not .config/vendored/. The other patterns must keep
        # matching exactly as before.
        $fixture = New-ControlFixture
        [IO.File]::WriteAllText((Join-Path $fixture.Package '.stow-local-ignore'),
            "^/vendored`$`n^/vendored/`n(^|/)ignored[.]txt`$`n")
        $installed = @('.config/vendored/kept', '.claude/skills/vendored/SKILL.md', 'notvendored/kept')
        $ignored = @('vendored/bin/tool', 'vendored/.git', 'ignored.txt', 'sub/ignored.txt', 'coding-agent-kit/lib/x.py')
        foreach ($relative in @($installed + $ignored)) {
            $path = Join-Path $fixture.Package $relative
            [void][IO.Directory]::CreateDirectory((Split-Path $path -Parent))
            [IO.File]::WriteAllText($path, $relative)
        }
        $action = 'Invoke-StowPackage -PackageRoot (Join-Path $RepoRoot "common") -PackageName git -GlobalIgnores @(''^coding-agent-kit(/|$)'')'
        $result = Invoke-Control $fixture -Action $action
        Assert-True (-not $result.Failed) $result.Errors
        foreach ($relative in @('.fixture') + $installed) {
            Assert-True ((Get-Item -LiteralPath (Join-Path $fixture.Target $relative) -Force -ErrorAction SilentlyContinue).LinkType -eq 'SymbolicLink') "Not installed: $relative"
        }
        foreach ($relative in $ignored) {
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixture.Target $relative))) "Ignored path installed: $relative"
        }
    }
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
    Test-Case 'a package symlink is skipped with a warning, never repaired or linked' {
        # No package holds a symlink: Git checks one out untrusted, or as a
        # text file without core.symlinks, so the installer fails closed.
        foreach ($sourceError in @(0, 448)) {
            $fixture = New-ControlFixture
            Remove-Item -LiteralPath $fixture.Source -Force
            $underlying = Join-Path $fixture.Package 'underlying'
            [IO.File]::WriteAllText($underlying, 'source content')
            New-Item -ItemType SymbolicLink -Path $fixture.Source -Value './underlying' | Out-Null
            $result = Invoke-Control $fixture -SourceError $sourceError
            Assert-True (-not $result.Failed) $result.Errors
            $warnings = @($result.Values[-1].Warnings | ForEach-Object { [string]$_ })
            Assert-True (@($warnings -ceq 'package symlink skipped: git/.fixture (packages hold files only)').Count -eq 1) ($warnings -join '; ')
            Assert-True ($result.Prompts.Count -eq 0) 'A package symlink was repaired.'
            Assert-True ($result.Values[-1].Repaired -eq 0) 'A package symlink counted as repaired.'
            Assert-True (@((Get-Item -LiteralPath $fixture.Source -Force).Target)[0] -ceq './underlying') 'The package symlink changed.'
            Assert-True (-not (Get-Item -LiteralPath $fixture.Destination -Force -ErrorAction SilentlyContinue)) 'A package symlink was installed.'
            Assert-True (-not (Test-Path -LiteralPath $fixture.State)) 'A skipped package symlink advanced state.'
        }
    }
    Test-Case 'links made from the retired packages honor preview, decline and Strict, dangling or not' {
        # Invoke-StowPackage linked each file to its full path in common\PACKAGE;
        # exactly that text goes, whether or not the file is still there.
        $preparation = '$commonRoot = Join-Path $RepoRoot ''common'''
        $action = "Remove-RetiredPackageLink -Package coding-agent-kit -RelativePath '.local/bin/codex-as'`n" +
            "Remove-RetiredPackageLink -Package pymol -RelativePath '.pymolrc'"
        foreach ($mode in @('apply', 'preview', 'decline', 'strict')) {
            $fixture = New-ControlFixture
            $links = @()
            foreach ($entry in @(@('coding-agent-kit', '.local/bin/codex-as'), @('pymol', '.pymolrc'))) {
                $native = $entry[1].Replace('/', [IO.Path]::DirectorySeparatorChar)
                $link = Join-Path $fixture.Target $native
                [void][IO.Directory]::CreateDirectory((Split-Path $link -Parent))
                $text = Join-Path (Join-Path (Join-Path $fixture.Root 'common') $entry[0]) $native
                if ($entry[0] -eq 'pymol') {
                    # Still there: the pull may leave a package file behind.
                    [void][IO.Directory]::CreateDirectory((Split-Path $text -Parent))
                    [IO.File]::WriteAllText($text, 'pymolrc')
                }
                New-Item -ItemType SymbolicLink -Path $link -Value $text | Out-Null
                $links += $link
            }
            $decline = if ($mode -in @('decline', 'strict')) { 'Remove the link made from the retired' } else { '' }
            $result = Invoke-Control $fixture -Preview:($mode -eq 'preview') -Strict:($mode -eq 'strict') -Decline $decline `
                -Preparation $preparation -Action $action
            Assert-True ($result.Failed -eq ($mode -eq 'strict')) "Wrong Strict result in $($mode): $($result.Errors)"
            foreach ($link in $links) {
                $remaining = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
                Assert-True ([bool]$remaining -eq ($mode -ne 'apply')) "Retirement changed the wrong entry in $mode mode: $link"
            }
            Assert-True ((Test-Path -LiteralPath $fixture.State) -eq ($mode -eq 'apply')) "Retirement acknowledged $mode."
            if ($mode -in @('decline', 'strict')) {
                Assert-True (@($result.Prompts | Where-Object { $_ -like '*Remove the link made from the retired*' }).Count -eq 2) 'Each removal must ask once.'
            }
        }
    }
    Test-Case 'any other entry at a retired package path is kept without a prompt' {
        $preparation = '$commonRoot = Join-Path $RepoRoot ''common'''
        $action = "Remove-RetiredPackageLink -Package coding-agent-kit -RelativePath '.local/bin/codex-as'"
        foreach ($kind in @('relative', 'foreign', 'file', 'directory')) {
            $fixture = New-ControlFixture
            $native = '.local/bin/codex-as'.Replace('/', [IO.Path]::DirectorySeparatorChar)
            $link = Join-Path $fixture.Target $native
            [void][IO.Directory]::CreateDirectory((Split-Path $link -Parent))
            switch ($kind) {
                'relative' {
                    $text = ('..', '..', '..', 'common', 'coding-agent-kit', '.local', 'bin', 'codex-as') -join [IO.Path]::DirectorySeparatorChar
                    New-Item -ItemType SymbolicLink -Path $link -Value $text | Out-Null
                }
                'foreign' {
                    $text = Join-Path (Join-Path $fixture.Root 'other/common/coding-agent-kit') $native
                    New-Item -ItemType SymbolicLink -Path $link -Value $text | Out-Null
                }
                'file' { [IO.File]::WriteAllText($link, 'my own launcher') }
                'directory' { [void][IO.Directory]::CreateDirectory($link) }
            }
            $result = Invoke-Control $fixture -Preparation $preparation -Action $action
            Assert-True (-not $result.Failed) $result.Errors
            Assert-True ([bool](Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue)) "Lost the $kind entry."
            Assert-True ($result.Prompts.Count -eq 0) "Prompted for the $kind entry."
        }
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
} finally {
    foreach ($name in $environmentNames) {
        if ($null -eq $savedEnvironment[$name]) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name])
        }
    }
    Remove-ControlFixture $testRoot
}
Write-Output "windows-installer-controls=PASS ($script:Passed cases)"
