#Requires -Version 7.0
# Behavior tests for lib/bootstrap.ps1, doctor.ps1 and setup-host.ps1.
# Library functions run in this process against fixture PATH, module, font and
# APPDATA directories. The entry points run as child pwsh -NoProfile
# -NonInteractive processes on a fixture checkout, with .ps1 shims for winget,
# git, oh-my-posh, bat and every probed tool on a fixture-only PATH, and global
# wrapper functions standing in for Invoke-WebRequest and PSResourceGet.
# Nothing touches the runner's real home, profile, modules or network. Runs on
# Linux and macOS pwsh as well as Windows; Windows-only probes are guarded.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$sourceRoot = Split-Path $PSScriptRoot -Parent
$powerShell = (Get-Process -Id $PID).Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-bootstrap-ps-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$script:Passed = 0
$script:FixtureNumber = 0
$AutomatedSteps = @('W1-winget', 'W1-psresources', 'W1-font', 'W1-bat-theme', 'W1-setup-sync')
$HumanSteps = @('HW-clone', 'HW-stow', 'HW-auto-stow-task', 'HW-execution-policy', 'HW-ssh-agent', 'HW-wsl', 'HW-auth')
$InstallEvent = '^(winget |Install-PSResource |oh-my-posh font |Invoke-WebRequest |bat cache |setup-sync\.ps1)'
$VenvPython = if ($IsWindows) { '.venv-sync/Scripts/python.exe' } else { '.venv-sync/bin/python' }
$FontFile = 'Microsoft/Windows/Fonts/CaskaydiaMonoNerdFont-Regular.ttf'
$ThemeFile = 'bat/themes/Catppuccin Mocha.tmTheme'

# Version text each tool shim prints for its version flag (blank: no flag).
$ToolText = [ordered]@{
    git = 'git version 2.47.1.windows.1'; python = 'Python 3.12.7'; fzf = '0.60.0 (d4c1a6d)'
    zoxide = 'zoxide 0.9.6'; eza = "eza - A modern, maintained replacement for ls`nv0.20.10 [+git]"
    fd = 'fd 10.2.0'; bat = 'bat 0.24.0 (fc954637)'; pwsh = 'PowerShell 7.4.6'; rg = 'ripgrep 14.1.1'
    delta = 'delta 0.18.2'; tldr = 'tlrc v1.9.3'; jq = 'jq-1.7.1'; nvim = 'NVIM v0.10.2'
    aria2c = 'aria2 version 1.37.0'; uv = 'uv 0.5.4'; gh = 'gh version 2.63.0 (2024-11-27)'
    node = 'v22.11.0'; claude = '2.0.14 (Claude Code)'; codex = 'codex-cli 0.161.0'; wezterm = ''; wt = ''
    'oh-my-posh' = '24.11.4'; 'pre-commit' = 'pre-commit 4.0.1'
}

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ([string]$Actual -cne [string]$Expected) { throw "$Message`n  expected: [$Expected]`n  actual:   [$Actual]" }
}
function Assert-Throws {
    # Action must throw; with -InvalidData, an IO.InvalidDataException.
    param([scriptblock]$Action, [string]$Message, [switch]$InvalidData)
    try { & $Action } catch {
        if (-not $InvalidData -or $_.Exception -is [IO.InvalidDataException]) { return }
        throw "${Message}: $($_.Exception.GetType().Name) $($_.Exception.Message)"
    }
    throw $Message
}
function Test-Case {
    param([string]$Name, [scriptblock]$Action)
    & $Action
    $script:Passed++
    Write-Output "PASS: $Name"
}
function Use-Environment {
    # Set process variables for one action and restore them afterwards.
    param([hashtable]$Values, [scriptblock]$Action)
    $saved = @{}
    foreach ($name in $Values.Keys) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, $Values[$name])
    }
    try { & $Action }
    finally { foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) } }
}

function New-Shim {
    # A .ps1 tool stand-in: logs "<name> <args>" to the event log, then runs Body.
    param([string]$Directory, [string]$Name, [string]$Body)
    [void][IO.Directory]::CreateDirectory($Directory)
    $prefix = "Add-Content -LiteralPath `$env:BOOTSTRAP_TEST_EVENTS -Value ((@('$Name') + @(`$args | ForEach-Object { `"`$_`" })) -join ' ')"
    [IO.File]::WriteAllText((Join-Path $Directory "$Name.ps1"), "$prefix`n$Body`n")
}
function New-ToolShim {
    # Prints Text for a version flag; auth/login status exits FAKE_AUTH_EXIT.
    # git answers core.symlinks from FAKE_GIT_SYMLINKS; oh-my-posh "font
    # install" drops a font file into the per-user Windows font directory.
    param([string]$Directory, [string]$Name, [string]$Text = $ToolText[$Name])
    $special = @{
        'git' = 'if ($args -contains ''core.symlinks'') { if ($env:FAKE_GIT_SYMLINKS) { $env:FAKE_GIT_SYMLINKS; exit 0 }; exit 1 }'
        'oh-my-posh' = 'if ("$args" -like ''font install *'') { $f = Join-Path $env:LOCALAPPDATA ''Microsoft/Windows/Fonts''; ' +
            '[void][IO.Directory]::CreateDirectory($f); [IO.File]::WriteAllText((Join-Path $f ''CaskaydiaMonoNerdFont-Regular.ttf''), ''f''); exit 0 }'
    }[$Name]
    $common = @'
$first = if ($args.Count) { "$($args[0])" } else { '' }
if ($first -in @('--version', '-V', '-v', 'version')) { Write-Output __TEXT__; exit 0 }
if ($first -in @('auth', 'login')) { exit ([int]"0$env:FAKE_AUTH_EXIT") }
exit 0
'@
    $quoted = "'" + $Text.Replace("'", "''") + "'"
    New-Shim $Directory $Name ([string]$special + "`n" + $common.Replace('__TEXT__', $quoted))
}
function New-WingetShim {
    param([string]$Directory)
    New-Shim $Directory 'winget' @'
$code = if ($env:FAKE_WINGET_EXIT) { [int]$env:FAKE_WINGET_EXIT } else { 0 }
if ($args.Count -and $args[0] -eq 'import' -and $code -eq 0 -and $env:FAKE_WINGET_PACKAGES) {
    foreach ($file in [IO.Directory]::GetFiles($env:FAKE_WINGET_PACKAGES)) {
        [IO.File]::Copy($file, (Join-Path $PSScriptRoot ([IO.Path]::GetFileName($file))), $true)
    }
}
if ($env:FAKE_WINGET_ECHO) { 'winget fixture output' }
exit $code
'@
}

function New-Fixture {
    # A disposable checkout plus home, APPDATA, LOCALAPPDATA, WINDIR, module,
    # PATH and package directories. Only winget and git are on PATH.
    $script:FixtureNumber++
    $root = Join-Path $testRoot $script:FixtureNumber
    $fixture = [pscustomobject]@{
        Root = $root; Repo = Join-Path $root 'repo'; Home = Join-Path $root 'home'
        AppData = Join-Path $root 'appdata'; LocalAppData = Join-Path $root 'localappdata'
        WinDir = Join-Path $root 'windir'; Modules = Join-Path $root 'modules'; Bin = Join-Path $root 'bin'
        Packages = Join-Path $root 'packages'; State = Join-Path $root 'state'; Temp = Join-Path $root 'temp'
        PwshState = Join-Path $root 'pwsh-state'; Events = Join-Path $root 'state/events.log'
        Download = Join-Path $root 'state/theme.download'
    }
    foreach ($directory in @($fixture.Repo, $fixture.Home, $fixture.AppData, $fixture.LocalAppData,
            (Join-Path $fixture.WinDir 'Fonts'), $fixture.Modules, $fixture.Bin, $fixture.Packages,
            $fixture.State, $fixture.Temp, $fixture.PwshState)) {
        [void][IO.Directory]::CreateDirectory($directory)
    }
    foreach ($file in @('doctor.ps1', 'setup-host.ps1', 'lib/bootstrap.ps1', 'lib/terminal.ps1', '.gitmodules',
            'config/bootstrap/tools.tsv', 'config/bootstrap/installers.tsv', 'config/bootstrap/winget.json')) {
        $target = Join-Path $fixture.Repo $file
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
        [IO.File]::Copy((Join-Path $sourceRoot $file), $target)
    }
    [IO.File]::WriteAllText((Join-Path $fixture.Repo 'setup-sync.ps1'), @'
Add-Content -LiteralPath $env:BOOTSTRAP_TEST_EVENTS -Value 'setup-sync.ps1'
$python = if ($IsWindows) { '.venv-sync/Scripts/python.exe' } else { '.venv-sync/bin/python' }
$path = Join-Path $PSScriptRoot $python
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
[IO.File]::WriteAllText($path, '')
Write-Host 'fixture AI-sync runtime ready'
'@)
    # The real pin cannot match fixture bytes; repin only bat-theme's digest.
    [IO.File]::WriteAllText($fixture.Download, 'fixture Catppuccin Mocha theme')
    $digest = (Get-FileHash -LiteralPath $fixture.Download -Algorithm SHA256).Hash.ToLowerInvariant()
    $installers = Join-Path $fixture.Repo 'config/bootstrap/installers.tsv'
    $lines = foreach ($line in [IO.File]::ReadAllLines($installers)) {
        if (-not $line.StartsWith("bat-theme`t")) { $line; continue }
        $cells = $line.Split("`t"); $cells[3] = $digest; $cells -join "`t"
    }
    [IO.File]::WriteAllLines($installers, [string[]]$lines)
    [IO.File]::WriteAllText($fixture.Events, '')
    New-WingetShim $fixture.Bin
    New-ToolShim $fixture.Bin 'git'
    return $fixture
}

function Set-FixtureHealthy {
    # Everything the win rows probe, plus the structural checks, is present.
    param($Fixture, [string[]]$Except = @())
    foreach ($name in $ToolText.Keys) {
        if ($name -notin $Except) { New-ToolShim $Fixture.Bin $name }
    }
    foreach ($module in @('PSFzf', 'CompletionPredictor', 'Microsoft.WinGet.CommandNotFound')) {
        [void][IO.Directory]::CreateDirectory((Join-Path $Fixture.Modules $module))
    }
    $files = @{
        (Join-Path $Fixture.LocalAppData $FontFile) = 'font'
        (Join-Path $Fixture.AppData $ThemeFile) = 'theme'
        (Join-Path $Fixture.Repo $VenvPython) = ''
        (Join-Path $Fixture.Repo 'common/pymol/PyMOLScripts/.git') = 'gitdir: ../../../.git/modules/PyMOLScripts'
        (Join-Path $Fixture.Home 'miniconda3/Scripts/conda.exe') = ''
    }
    foreach ($path in $files.Keys) {
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
        [IO.File]::WriteAllText($path, $files[$path])
    }
}

function Invoke-Fixture {
    # Run doctor.ps1 or setup-host.ps1 from the fixture checkout in a child.
    param($Fixture, [string]$Script, [hashtable]$Parameters = @{}, [hashtable]$Environment = @{})
    $wrapper = @'
$ErrorActionPreference = 'Continue'
Set-Variable -Name HOME -Value $env:FIXTURE_HOME -Scope Global -Force
$env:PSModulePath = $env:FIXTURE_MODULES + [IO.Path]::PathSeparator + (Join-Path $PSHOME 'Modules')
function global:Invoke-WebRequest {
    [CmdletBinding()]
    param([string]$Uri, [string]$OutFile, [int]$MaximumRetryCount, [int]$RetryIntervalSec)
    Add-Content -LiteralPath $env:BOOTSTRAP_TEST_EVENTS -Value "Invoke-WebRequest $Uri"
    [IO.File]::Copy($env:FAKE_DOWNLOAD, $OutFile)
}
function global:Get-InstalledPSResource {
    [CmdletBinding()]
    param([string]$Name)
    Add-Content -LiteralPath $env:BOOTSTRAP_TEST_EVENTS -Value "Get-InstalledPSResource $Name"
    if ((([string]$env:FAKE_PSRESOURCE_INSTALLED).Split(',') -contains $Name) -or
        [IO.Directory]::Exists((Join-Path $env:FIXTURE_MODULES $Name))) { [pscustomobject]@{ Name = $Name } }
}
function global:Install-PSResource {
    [CmdletBinding()]
    param([string]$Name, [string]$Scope, [switch]$TrustRepository, [switch]$AcceptLicense)
    $flags = @(if ($TrustRepository) { '-TrustRepository' }) + @(if ($AcceptLicense) { '-AcceptLicense' })
    Add-Content -LiteralPath $env:BOOTSTRAP_TEST_EVENTS -Value (@("Install-PSResource -Name $Name -Scope $Scope") + $flags -join ' ')
    [void][IO.Directory]::CreateDirectory((Join-Path $env:FIXTURE_MODULES $Name))
}
$parameters = $env:FIXTURE_PARAMETERS | ConvertFrom-Json -AsHashtable
& $env:FIXTURE_SCRIPT @parameters
exit $LASTEXITCODE
'@
    $start = [Diagnostics.ProcessStartInfo]::new($powerShell)
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', $wrapper)) {
        $start.ArgumentList.Add($argument)
    }
    foreach ($name in @('DOTFILES_COLOR', 'BAT_CONFIG_DIR', 'ZSH', 'ZSH_CUSTOM', 'NVM_DIR', 'DOTFILES_HOST',
            'DOTFILES_AUTO_UPDATE', 'FAKE_WINGET_EXIT', 'FAKE_AUTH_EXIT', 'FAKE_PSRESOURCE_INSTALLED')) {
        [void]$start.Environment.Remove($name)
    }
    $values = @{
        PATH = $Fixture.Bin; HOME = $Fixture.Home; APPDATA = $Fixture.AppData; LOCALAPPDATA = $Fixture.LocalAppData
        TMPDIR = $Fixture.Temp; TEMP = $Fixture.Temp; TMP = $Fixture.Temp
        NO_COLOR = '1'; POWERSHELL_TELEMETRY_OPTOUT = '1'; POWERSHELL_UPDATECHECK = 'Off'
        BOOTSTRAP_TEST_EVENTS = $Fixture.Events; FIXTURE_HOME = $Fixture.Home; FIXTURE_MODULES = $Fixture.Modules
        FIXTURE_SCRIPT = Join-Path $Fixture.Repo $Script; FIXTURE_PARAMETERS = ($Parameters | ConvertTo-Json -Compress)
        FAKE_GIT_SYMLINKS = 'true'; FAKE_WINGET_PACKAGES = $Fixture.Packages; FAKE_DOWNLOAD = $Fixture.Download
        FAKE_WINGET_ECHO = '1'
    }
    if (-not $IsWindows) {
        # Keep pwsh's own caches out of the snapshotted fixture home; Unix
        # has no WINDIR, so the fixture provides the system font directory.
        $values['WINDIR'] = $Fixture.WinDir
        $values['XDG_CONFIG_HOME'] = Join-Path $Fixture.PwshState 'config'
        $values['XDG_CACHE_HOME'] = Join-Path $Fixture.PwshState 'cache'
        $values['XDG_DATA_HOME'] = Join-Path $Fixture.PwshState 'data'
    }
    foreach ($name in $Environment.Keys) { $values[$name] = $Environment[$name] }
    foreach ($name in $values.Keys) { $start.Environment[$name] = $values[$name] }
    $child = [Diagnostics.Process]::Start($start)
    try {
        $child.StandardInput.Close()
        $stdout = $child.StandardOutput.ReadToEndAsync()
        $stderr = $child.StandardError.ReadToEndAsync()
        if (-not $child.WaitForExit(120000)) {
            $child.Kill($true)
            throw "$Script timed out."
        }
        $outputText = $stdout.GetAwaiter().GetResult()
        return [pscustomobject]@{
            ExitCode = $child.ExitCode; Stdout = $outputText; Stderr = $stderr.GetAwaiter().GetResult()
            Lines = @($outputText.Split("`n") | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -ne '' })
        }
    }
    finally { $child.Dispose() }
}
function Assert-Exit {
    param($Run, [int]$Expected, [string]$Label)
    Assert-True ($Run.ExitCode -eq $Expected) "$Label exited $($Run.ExitCode), expected ${Expected}:`n$($Run.Stdout)`n$($Run.Stderr)"
    Assert-True ($Run.Stderr -eq '') "$Label wrote to stderr: $($Run.Stderr)"
}
function Get-FixtureEvents($Fixture) { return @([IO.File]::ReadAllLines($Fixture.Events)) }
function Get-InstallEvents($Fixture) { return @(Get-FixtureEvents $Fixture | Where-Object { $_ -cmatch $InstallEvent }) }
function Get-ImportEvent($Fixture) {
    return "winget import -i $(Join-Path $Fixture.Repo 'config/bootstrap/winget.json') --no-upgrade --ignore-unavailable " +
        '--accept-package-agreements --accept-source-agreements --disable-interactivity'
}
function Get-Snapshot {
    # Every file and directory with its size and modification time.
    param([string[]]$Paths)
    $entries = foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        Get-ChildItem -LiteralPath $path -Recurse -Force | ForEach-Object {
            $length = if ($_.PSIsContainer) { 'dir' } else { $_.Length }
            "$($_.FullName)|$length|$($_.LastWriteTimeUtc.Ticks)"
        }
    }
    return (@($entries) | Sort-Object) -join "`n"
}
function Get-FixtureRoots {
    param($Fixture)
    # Temp is left out: the .NET runtime keeps its own files there.
    return @($Fixture.Repo, $Fixture.Home, $Fixture.AppData, $Fixture.LocalAppData, $Fixture.WinDir,
        $Fixture.Modules, $Fixture.Bin, $Fixture.Packages)
}
function Get-HumanBlocks {
    # Parse and validate the HUMAN grammar: BEGIN <id> <kind>, lines, END.
    param([string[]]$Lines)
    $blocks = [Collections.Generic.List[object]]::new()
    $current = $null
    foreach ($line in $Lines) {
        if ($line.StartsWith('HUMAN-BEGIN')) {
            Assert-True ($null -eq $current) "Nested HUMAN-BEGIN: $line"
            Assert-True ($line -cmatch '^HUMAN-BEGIN ([A-Za-z0-9-]+) (sudo|auth|gui|alloc|chsh|inspect|judgment)$') "Malformed: $line"
            $current = [pscustomobject]@{ Id = $Matches[1]; Kind = $Matches[2]; Lines = [Collections.Generic.List[string]]::new() }
        }
        elseif ($line -ceq 'HUMAN-END') {
            Assert-True ($null -ne $current) 'HUMAN-END without HUMAN-BEGIN.'
            Assert-True ($current.Lines.Count -gt 0) "Empty HUMAN block $($current.Id)."
            $blocks.Add($current)
            $current = $null
        }
        elseif ($null -ne $current) {
            Assert-True (-not $line.StartsWith('HUMAN-')) "Malformed HUMAN line: $line"
            $current.Lines.Add($line)
        }
    }
    Assert-True ($null -eq $current) 'Unterminated HUMAN block.'
    return , $blocks.ToArray()
}
function Get-WinToolIds {
    # Independent of lib/bootstrap.ps1: data rows whose hosts are all or name win.
    $rows = @([IO.File]::ReadAllLines((Join-Path $sourceRoot 'config/bootstrap/tools.tsv')) |
            Where-Object { $_ -and -not $_.StartsWith('#') } | Select-Object -Skip 1)
    return @($rows | ForEach-Object { $cells = $_.Split("`t"); if ($cells[2] -ceq 'all' -or $cells[2].Split(',') -ccontains 'win') { $cells[0] } })
}

. (Join-Path $sourceRoot 'lib/bootstrap.ps1')
$script:MockInstalled = @()
$script:MockEvents = [Collections.Generic.List[string]]::new()
$script:DownloadSource = ''
function Get-InstalledPSResource {
    [CmdletBinding()] param([string]$Name)
    $script:MockEvents.Add("Get-InstalledPSResource $Name")
    if ($script:MockInstalled -contains $Name) { [pscustomobject]@{ Name = $Name } }
}
function Install-PSResource {
    [CmdletBinding()] param([string]$Name, [string]$Scope, [switch]$TrustRepository, [switch]$AcceptLicense)
    $script:MockEvents.Add("Install-PSResource -Name $Name -Scope $Scope -TrustRepository:$TrustRepository -AcceptLicense:$AcceptLicense")
    if ($Name -eq 'Broken') { throw 'gallery unreachable' }
}
function Invoke-WebRequest {
    [CmdletBinding()] param([string]$Uri, [string]$OutFile, [int]$MaximumRetryCount, [int]$RetryIntervalSec)
    $script:MockEvents.Add("Invoke-WebRequest $Uri")
    [IO.File]::WriteAllText($OutFile, $script:DownloadSource)
}

try {
    Test-Case 'entry points and library parse, never elevate and keep preferences scoped' {
        foreach ($name in @('doctor.ps1', 'setup-host.ps1', 'lib/bootstrap.ps1', 'tests/bootstrap.ps1')) {
            $errors = $null
            $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $sourceRoot $name), [ref]$null, [ref]$errors)
            Assert-True (-not $errors) "$name has parse errors: $($errors -join '; ')"
            if ($name -like 'tests/*') { continue }
            Assert-True ([IO.File]::ReadAllText((Join-Path $sourceRoot $name)) -notmatch '(?i)runas') "$name mentions RunAs."
            $commands = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true) |
                    ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
            foreach ($forbidden in @('Get-Command', 'Start-Process', 'sudo', 'Set-ExecutionPolicy', 'Register-ScheduledTask')) {
                Assert-True ($commands -notcontains $forbidden) "$name runs $forbidden."
            }
            Assert-True (-not @($commands | Where-Object { $_ -match 'stow-all' }).Count) "$name runs stow-all."
            $assignments = $ast.FindAll({ param($node)
                    $node -is [Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and
                    $node.Left.VariablePath.UserPath -eq 'ErrorActionPreference' }, $true)
            foreach ($assignment in $assignments) {
                $parent = $assignment.Parent
                while ($parent -and $parent -isnot [Management.Automation.Language.FunctionDefinitionAst]) { $parent = $parent.Parent }
                Assert-True ($null -ne $parent) "$name sets ErrorActionPreference outside a function."
            }
            if ($name -eq 'lib/bootstrap.ps1') {
                Assert-True ($null -eq $ast.ParamBlock) 'The library declares parameters.'
                foreach ($statement in $ast.EndBlock.Statements) {
                    Assert-True ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) "The library runs top-level code: $statement"
                }
            }
        }
    }

    Test-Case 'manifest rows are header driven and skip comments anywhere' {
        $rows = @(Get-BootstrapManifestRows -Path (Join-Path $sourceRoot 'config/bootstrap/tools.tsv') -Header @(
                    'id', 'tier', 'hosts', 'probe', 'version_flag', 'floor', 'absent', 'doc'))
        $dataLines = @([IO.File]::ReadAllLines((Join-Path $sourceRoot 'config/bootstrap/tools.tsv')) |
                Where-Object { $_.Trim() -and -not $_.StartsWith('#') })
        Assert-Equal $rows.Count ($dataLines.Count - 1) 'tools.tsv row count'
        Assert-True (@($rows | Where-Object { $_.id.StartsWith('#') }).Count -eq 0) 'A comment became a row.'
        Assert-Equal (@($rows[0].PSObject.Properties.Name) -join ',') 'id,tier,hosts,probe,version_flag,floor,absent,doc' 'tools.tsv columns'
        $sample = Join-Path $testRoot 'sample.tsv'
        [IO.File]::WriteAllText($sample, "# lead`r`na`tb`r`n`r`n1`tx y`r`n# middle`r`n2`t-`r`n# alias: trailing declaration`r`n")
        $parsed = @(Get-BootstrapManifestRows -Path $sample -Header @('a', 'b'))
        Assert-Equal (($parsed | ForEach-Object { "$($_.a)=$($_.b)" }) -join ';') '1=x y;2=-' 'CRLF rows'
        foreach ($bad in @("a`tb`n1`n", "a`tb`n1`t2`t3`n", "a`tb`n1`t`n", "a`tc`n1`t2`n", "# only comments`n")) {
            [IO.File]::WriteAllText($sample, $bad)
            Assert-Throws { Get-BootstrapManifestRows -Path $sample -Header @('a', 'b') } "Accepted $($bad.Replace("`n", '\n'))" -InvalidData
        }
    }

    Test-Case 'paths expand the contract tokens and reject anything else' {
        $separator = if ($IsWindows) { '\' } else { '/' }
        Use-Environment @{ APPDATA = (Join-Path $testRoot 'appdata'); BAT_CONFIG_DIR = $null; NVM_DIR = $null; ZSH = $null; ZSH_CUSTOM = $null } {
            Assert-Equal (Expand-BootstrapPath '$HOME/miniconda3/Scripts/conda.exe') (($HOME + '/miniconda3/Scripts/conda.exe').Replace('/', $separator)) '$HOME'
            Assert-Equal (Expand-BootstrapPath '$BAT_CONFIG_DIR/themes/Catppuccin Mocha.tmTheme') (
                (Join-Path (Join-Path $testRoot 'appdata') 'bat') + '/themes/Catppuccin Mocha.tmTheme').Replace('/', $separator) '$BAT_CONFIG_DIR'
            Assert-Equal (Expand-BootstrapPath '$NVM_DIR/nvm.sh') ((Join-Path $HOME '.nvm') + '/nvm.sh').Replace('/', $separator) '$NVM_DIR'
            Assert-Equal (Expand-BootstrapPath '$ZSH_CUSTOM') (Join-Path (Join-Path $HOME '.oh-my-zsh') 'custom').Replace('/', $separator) '$ZSH_CUSTOM'
        }
        Use-Environment @{ BAT_CONFIG_DIR = (Join-Path $testRoot 'batcfg') } {
            Assert-Equal (Expand-BootstrapPath '$BAT_CONFIG_DIR') (Join-Path $testRoot 'batcfg') 'BAT_CONFIG_DIR override'
        }
        foreach ($bad in @('~/x', '$HOME/../x', '$FOO/x', '$HOME/$PATH', '$HOMEX/y', '/a/../b')) {
            Assert-Throws { Expand-BootstrapPath $bad } "Expanded $bad." -InvalidData
        }
    }

    Test-Case 'host matching, tiers, doc refs and versions mirror the Bash library' {
        Assert-True (Test-BootstrapHostMatch all win) 'all'
        Assert-True (-not (Test-BootstrapHostMatch unix win)) 'unix excludes win'
        Assert-True (Test-BootstrapHostMatch unix '') 'unix in platform mode'
        Assert-True (Test-BootstrapHostMatch 'mac,win' win) 'list'
        Assert-True (-not (Test-BootstrapHostMatch 'mac,lab-ubuntu' win)) 'list without win'
        Assert-True (-not (Test-BootstrapHostMatch 'win' '')) 'list in platform mode'
        Assert-True (Test-BootstrapTierSelection 'core,desktop') 'tier list'
        Assert-True (-not (Test-BootstrapTierSelection 'core,bogus')) 'unknown tier'
        Assert-True (-not (Test-BootstrapTierSelection '')) 'empty tiers'
        Assert-True (Test-BootstrapTierSelected host all) 'all tiers'
        Assert-True (-not (Test-BootstrapTierSelected desktop 'core,cli,ai')) 'default tiers'
        $refs = [ordered]@{ 'S2-brew-bundle' = 'W1-winget'; 'S4-nvm' = 'W1-winget'; 'S5-claude' = 'W1-winget'
            'S5-codex' = 'W1-winget'; 'S3-bat-theme' = 'W1-bat-theme'; 'S6-nerd-font' = 'W1-font'
            'S4-setup-sync' = 'W1-setup-sync'; 'H7-stow' = 'HW-stow'; 'H7-auth' = 'HW-auth'; 'X-contributor' = 'X-contributor'
        }
        foreach ($step in $refs.Keys) { Assert-Equal (Get-BootstrapDocRef $step) $refs[$step] "windows $step" }
        Assert-Equal (Get-BootstrapDocRef S2-brew-bundle hpc) 'S2-login-env' 'hpc brew'
        Assert-Equal (Get-BootstrapDocRef S5-claude hpc) 'S2-modules' 'hpc claude'
        Assert-Equal (Get-BootstrapDocRef S4-nvm debian) 'S4-nvm' 'debian nvm'
        foreach ($case in @(@('0.58.0', '0.58', 0), @('v3.14.1', '3.13', 0), @('2.3.1', '2.4', 1), @('10.5.0', '8.3', 0),
                @('0.44.1', '0.58.0', 1), @('7.0', '7.0', 0), @('x', '1.0', 2), @('1.2.3.4', '1.0', 2), @('', '1.0', 2))) {
            Assert-Equal (Compare-BootstrapVersion $case[0] $case[1]) $case[2] "compare $($case[0]) $($case[1])"
        }
        Assert-Equal (ConvertFrom-BootstrapVersionText "eza - ls`nv0.20.10 [+git]") '0.20.10' 'version text'
        Assert-Equal (ConvertFrom-BootstrapVersionText 'jq-1.7.1 build 2.3') '1.7.1' 'first version'
        Assert-Equal (ConvertFrom-BootstrapVersionText 'no version') '' 'no version'
    }

    Test-Case 'tool probes cover every kind without Get-Command' {
        $root = Join-Path $testRoot 'probes'
        $bin, $modules, $windir, $local = @('bin', 'modules', 'windir', 'local') | ForEach-Object { Join-Path $root $_ }
        foreach ($directory in @((Join-Path $modules 'PSFzf'), (Join-Path $windir 'Fonts'), (Join-Path $local 'Microsoft/Windows/Fonts'))) {
            [void][IO.Directory]::CreateDirectory($directory)
        }
        New-ToolShim $bin 'fzf' '0.60.0 (d4c1a6d)'
        New-ToolShim $bin 'python3' 'Python was not found; run without arguments to install from the Microsoft Store'
        New-ToolShim $bin 'python' 'Python 3.12.7'
        [IO.File]::WriteAllText((Join-Path $bin 'broken.ps1'), "throw 'cannot start'")
        [IO.File]::WriteAllText((Join-Path $bin 'both.exe'), '')
        [IO.File]::WriteAllText((Join-Path $bin 'both.ps1'), '')
        [IO.File]::WriteAllText((Join-Path $bin 'batch.cmd'), '')
        Use-Environment @{ PATH = $bin; PSModulePath = $modules; WINDIR = $windir; LOCALAPPDATA = $local
            BOOTSTRAP_TEST_EVENTS = (Join-Path $root 'events.log'); BOOTSTRAP_TEST_FLAG = 'set' } {
            Assert-Equal (Find-BootstrapCommand both) (Join-Path $bin 'both.exe') '.exe before .ps1'
            Assert-Equal (Find-BootstrapCommand batch) (Join-Path $bin 'batch.cmd') '.cmd'
            Assert-True ($null -eq (Find-BootstrapCommand missing)) 'missing command'
            $fzf = Test-BootstrapTool -Probe fzf -VersionFlag '--version'
            Assert-True ($fzf.Found -and $fzf.Version -eq '0.60.0') "fzf: $($fzf.Version)"
            Assert-Equal (Test-BootstrapTool -Probe fzf).Version '' 'presence-only probe ran the tool'
            $python = Test-BootstrapTool -Probe 'python3,python' -VersionFlag '--version'
            Assert-True ($python.Path -eq (Join-Path $bin 'python.ps1') -and $python.Version -eq '3.12.7') "Store stub won: $($python.Path)"
            $first = Test-BootstrapTool -Probe 'python3,python'
            Assert-Equal $first.Path (Join-Path $bin 'python3.ps1') 'presence-only alternatives: first found wins'
            Assert-Equal (Get-BootstrapToolVersion -Path (Join-Path $bin 'broken.ps1') -Flag '--version') '' 'failing tool'
            Assert-Equal (Get-BootstrapToolVersion -Path (Join-Path $bin 'fzf.ps1') -Flag '-') '' 'flag -'
            Assert-True (Test-BootstrapTool -Probe 'psmodule:PSFzf').Found 'psmodule present'
            Assert-True (-not (Test-BootstrapTool -Probe 'psmodule:CompletionPredictor').Found) 'psmodule absent'
            Assert-True (Test-BootstrapTool -Probe 'env:BOOTSTRAP_TEST_FLAG').Found 'env set'
            Assert-True (-not (Test-BootstrapTool -Probe 'env:BOOTSTRAP_TEST_UNSET').Found) 'env unset'
            Assert-True (-not (Test-BootstrapTool -Probe 'font:CaskaydiaMono Nerd Font').Found) 'font absent'
            [IO.File]::WriteAllText((Join-Path $windir 'Fonts/CaskaydiaMonoNerdFont-Regular.ttf'), '')
            Assert-True (Test-BootstrapTool -Probe 'font:CaskaydiaMono Nerd Font').Found 'system font'
            Remove-Item -LiteralPath (Join-Path $windir 'Fonts/CaskaydiaMonoNerdFont-Regular.ttf')
            [IO.File]::WriteAllText((Join-Path $local 'Microsoft/Windows/Fonts/caskaydiamononerdfontmono-bold.ttf'), '')
            Assert-True (Test-BootstrapTool -Probe 'font:CaskaydiaMono Nerd Font').Found 'per-user font, any case'
            Assert-True (Test-BootstrapTool -Probe "file:$($bin.Replace('\', '/'))/fzf.ps1").Found 'file'
            Assert-True (Test-BootstrapTool -Probe "dir:$($modules.Replace('\', '/'))").Found 'dir'
            foreach ($bad in @('url:x', 'a b', 'C:\tools\x.exe', 'file:~/x')) {
                Assert-Throws { Test-BootstrapTool -Probe $bad } "Accepted probe $bad." -InvalidData
            }
        }
    }

    Test-Case 'winget exit codes map to success and fail-closed classes with exact arguments' {
        $root = Join-Path $testRoot 'winget'
        $bin, $events = (Join-Path $root 'bin'), (Join-Path $root 'events.log')
        New-WingetShim $bin
        $cases = @(
            @(0, 'installed', '0x00000000'), @(0x8A150061, 'present', '0x8A150061'), @(0x8A15002B, 'present', '0x8A15002B'),
            @(0x8A150046, 'failed', '0x8A150046'), @(0x8A150041, 'failed', '0x8A150041'),
            @(0x8A150014, 'failed', '0x8A150014'), @(1, 'failed', '0x00000001'), @(0x8A150049, 'failed', '0x8A150049'))
        foreach ($case in $cases) {
            [IO.File]::WriteAllText($events, '')
            Use-Environment @{ PATH = $bin; BOOTSTRAP_TEST_EVENTS = $events; FAKE_WINGET_EXIT = [string]$case[0]; FAKE_WINGET_PACKAGES = $null } {
                $results = @(Invoke-BootstrapWinget -Id junegunn.fzf)
                Assert-Equal $results.Count 1 'winget output leaked into the result'
                $result = $results[0]
                Assert-Equal $result.Status $case[1] "winget $($case[2])"
                Assert-Equal $result.Success ($case[1] -ne 'failed') "winget $($case[2]) success"
                Assert-True $result.Message.Contains($case[2]) "Message lacks hex: $($result.Message)"
                Assert-Equal ([IO.File]::ReadAllText($events).Trim()) 'winget install --id junegunn.fzf -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity --no-upgrade' 'install arguments'
            }
        }
        [IO.File]::WriteAllText($events, '')
        Use-Environment @{ PATH = $bin; BOOTSTRAP_TEST_EVENTS = $events; FAKE_WINGET_EXIT = '0'; FAKE_WINGET_PACKAGES = $null } {
            Assert-True (Invoke-BootstrapWingetImport -Path 'C:/x/winget.json').Success 'import'
            Assert-Equal ([IO.File]::ReadAllText($events).Trim()) 'winget import -i C:/x/winget.json --no-upgrade --ignore-unavailable --accept-package-agreements --accept-source-agreements --disable-interactivity' 'import arguments'
        }
        Use-Environment @{ PATH = (Join-Path $root 'empty') } {
            $result = Invoke-BootstrapWinget -Id junegunn.fzf
            Assert-True (-not $result.Success -and $result.Message.Contains('winget is not on PATH')) 'missing winget'
        }
    }

    Test-Case 'PSResource installs only what PSResourceGet lacks' {
        $script:MockInstalled = @('PSFzf')
        $script:MockEvents.Clear()
        Assert-Equal (Invoke-BootstrapPSResource -Name PSFzf).Status 'present' 'installed module'
        Assert-Equal ($script:MockEvents -join ';') 'Get-InstalledPSResource PSFzf' 'present module was reinstalled'
        $script:MockEvents.Clear()
        Assert-Equal (Invoke-BootstrapPSResource -Name CompletionPredictor).Status 'installed' 'missing module'
        Assert-Equal ($script:MockEvents -join ';') 'Get-InstalledPSResource CompletionPredictor;Install-PSResource -Name CompletionPredictor -Scope CurrentUser -TrustRepository:True -AcceptLicense:True' 'install call'
        $result = Invoke-BootstrapPSResource -Name Broken
        Assert-True (-not $result.Success -and $result.Message.Contains('gallery unreachable')) 'install failure'
    }

    Test-Case 'font install is gated on oh-my-posh and an absent font' {
        $root = Join-Path $testRoot 'font'
        $bin, $local, $events = (Join-Path $root 'bin'), (Join-Path $root 'local'), (Join-Path $root 'events.log')
        [void][IO.Directory]::CreateDirectory($bin)
        [IO.File]::WriteAllText($events, '')
        Use-Environment @{ PATH = $bin; WINDIR = (Join-Path $root 'windir'); LOCALAPPDATA = $local; BOOTSTRAP_TEST_EVENTS = $events } {
            $result = Install-BootstrapFont
            Assert-True ($result.Status -eq 'skipped' -and $result.Success) "No oh-my-posh: $($result.Status)"
            Assert-Equal ([IO.File]::ReadAllText($events)) '' 'font step ran without oh-my-posh'
            New-ToolShim $bin 'oh-my-posh'
            Assert-Equal (Install-BootstrapFont).Status 'installed' 'oh-my-posh present'
            Assert-Equal ([IO.File]::ReadAllText($events).Trim()) 'oh-my-posh font install CascadiaMono' 'font command'
            Assert-Equal (Install-BootstrapFont).Status 'present' 'second font run'
            Assert-Equal @([IO.File]::ReadAllLines($events)).Count 1 'font reinstalled'
        }
    }

    Test-Case 'pinned downloads move into place only with a matching digest' {
        $root = Join-Path $testRoot 'download'
        $destination = Join-Path $root 'bat/themes/Catppuccin Mocha.tmTheme'
        $script:DownloadSource = 'theme bytes'
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $digest = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes('theme bytes'))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
        $temporary = Join-Path $root 'tmp'
        [void][IO.Directory]::CreateDirectory($temporary)
        Use-Environment @{ TMPDIR = $temporary; TEMP = $temporary; TMP = $temporary } {
            $bad = Install-BootstrapFile -Uri 'https://example.invalid/t' -Sha256 ('0' * 64) -Destination $destination
            Assert-True (-not $bad.Success -and $bad.Message.Contains('sha256 mismatch')) "Mismatch: $($bad.Message)"
            Assert-True (-not (Test-Path -LiteralPath $destination)) 'Mismatched download was installed.'
            $good = Install-BootstrapFile -Uri 'https://example.invalid/t' -Sha256 $digest -Destination $destination
            Assert-True $good.Success "Matching digest failed: $($good.Message)"
            Assert-Equal ([IO.File]::ReadAllText($destination)) 'theme bytes' 'installed bytes'
            $again = Install-BootstrapFile -Uri 'https://example.invalid/t' -Sha256 $digest -Destination $destination
            Assert-True (-not $again.Success) 'An existing destination was replaced.'
            Assert-Equal @([IO.Directory]::GetFileSystemEntries($temporary)).Count 0 'scratch directories left behind'
        }
        foreach ($case in @(@('http://example.invalid/t', $digest), @('https://example.invalid/t', 'ABC'))) {
            Assert-Throws { Install-BootstrapFile -Uri $case[0] -Sha256 $case[1] -Destination $destination } "Accepted $($case -join ' ')." -InvalidData
        }
    }

    Test-Case 'HUMAN blocks follow the shared grammar' {
        $lines = @(Write-BootstrapHumanBlock -Step HW-auth -Kind auth -Line @('gh auth login', 'codex login'))
        Assert-Equal ($lines -join '|') 'HUMAN-BEGIN HW-auth auth|gh auth login|codex login|HUMAN-END' 'block'
        Assert-Equal (Get-HumanBlocks $lines)[0].Id 'HW-auth' 'parsed block'
        foreach ($bad in @(@('HW-auth', 'admin', 'x'), @('HW auth', 'auth', 'x'), @('HW-auth', 'Auth', 'x'),
                @('HW-auth', 'auth', "a`nb"), @('HW-auth', 'auth', 'HUMAN-END'))) {
            Assert-Throws { Write-BootstrapHumanBlock -Step $bad[0] -Kind $bad[1] -Line $bad[2] } "Accepted HUMAN block $($bad -join ' ')."
        }
    }

    # On Windows the children see the real system font directory, and apply
    # runs append this machine's PATH after winget: font and oh-my-posh
    # expectations hold only when neither is installed on the machine.
    $machineTools = $false
    if ($IsWindows) {
        $machinePath = @('Machine', 'User' | ForEach-Object { [Environment]::GetEnvironmentVariable('Path', $_) }) -join ';'
        $machineTools = Use-Environment @{ PATH = $machinePath; LOCALAPPDATA = $null } {
            [bool]((Find-BootstrapCommand 'oh-my-posh') -or (Find-BootstrapFontFile 'CaskaydiaMono Nerd Font'))
        }
    }

    Test-Case 'doctor reports a healthy host with five TSV columns and writes nothing offline' {
        $fixture = New-Fixture
        Set-FixtureHealthy $fixture
        $before = Get-Snapshot (Get-FixtureRoots $fixture)
        $run = Invoke-Fixture $fixture doctor.ps1 @{ Tier = 'all'; Tsv = $true }
        Assert-Exit $run 0 'healthy doctor'
        Assert-Equal $run.Lines[0] "status`tid`ttier`tdetail`tfix" 'TSV header'
        $ids = foreach ($line in @($run.Lines | Select-Object -Skip 1)) {
            $cells = $line.Split("`t")
            Assert-Equal $cells.Count 5 "TSV columns in '$line'"
            Assert-Equal $cells[0] 'ok' "status in '$line'"
            Assert-Equal $cells[4] '-' "fix in '$line'"
            $cells[1]
        }
        Assert-Equal (@($ids) -join ',') ((@(Get-WinToolIds) + @('venv-sync', 'submodule', 'core-symlinks')) -join ',') 'doctor ids'
        Assert-Equal (Get-Snapshot (Get-FixtureRoots $fixture)) $before 'doctor wrote files'
        $events = Get-FixtureEvents $fixture
        Assert-True ($events -contains 'fzf --version' -and $events -contains 'oh-my-posh version') 'version probes did not run'
        Assert-True (-not @($events | Where-Object { $_ -match '(auth|login) status|Invoke-WebRequest|^winget|PSResource' }).Count) "Offline doctor used the network: $($events -join '; ')"
        $quiet = Invoke-Fixture $fixture doctor.ps1 @{ Quiet = $true }; Assert-Exit $quiet 0 'quiet doctor'
        Assert-Equal $quiet.Stdout '' 'quiet doctor printed ok lines'
        $plain = Invoke-Fixture $fixture doctor.ps1 @{}; Assert-Exit $plain 0 'plain doctor'
        Assert-True ($plain.Lines -contains '[dotfiles] [ok] core fzf: 0.60.0') 'ok line format'
        Assert-True ($plain.Lines[-1].StartsWith('[dotfiles] [ok] doctor win: ')) 'summary line'
    }

    Test-Case 'doctor fails selected tiers, warns for the rest and maps fixes to Windows steps' {
        $fixture = New-Fixture
        Set-FixtureHealthy $fixture -Except @('wezterm')
        New-ToolShim $fixture.Bin 'fzf' '0.44.1'
        $run = Invoke-Fixture $fixture doctor.ps1 @{}
        Assert-Exit $run 1 'outdated fzf'
        Assert-True ($run.Lines -contains '[dotfiles] [error] core fzf: 0.44.1 < 0.58.0 (docs/bootstrap.md W1-winget)') "fzf line: $($run.Stdout)"
        Assert-True (@($run.Lines | Where-Object { $_ -like '`[dotfiles`] `[warn`] desktop wezterm: missing: *(tier desktop not selected) (docs/bootstrap.md W1-winget)' }).Count -eq 1) 'wezterm warn line'
        Assert-True (-not $run.Stdout.Contains([string][char]27)) 'NO_COLOR output contains ANSI.'
        New-ToolShim $fixture.Bin 'fzf'
        Assert-Exit (Invoke-Fixture $fixture doctor.ps1 @{}) 0 'desktop gap under default tiers'
        $all = Invoke-Fixture $fixture doctor.ps1 @{ Tier = 'all'; Tsv = $true }
        Assert-Exit $all 1 'desktop gap under -Tier all'
        Assert-True (@($all.Lines | Where-Object { $_ -cmatch "^missing`twezterm`tdesktop`tmissing: .+`tdocs/bootstrap.md W1-winget$" }).Count -eq 1) 'wezterm TSV row'
        foreach ($case in @(@('false', 'false'), @('', 'unset'))) {
            $run = Invoke-Fixture $fixture doctor.ps1 @{ Tsv = $true } @{ FAKE_GIT_SYMLINKS = $case[0] }
            Assert-Exit $run 1 "core.symlinks $($case[1])"
            Assert-True ($run.Lines -contains "missing`tcore-symlinks`tcore`tcore.symlinks is $($case[1]) in this clone; tracked symlinks are plain files`tdocs/bootstrap.md HW-clone") "core-symlinks row: $($run.Stdout)"
        }
        Remove-Item -LiteralPath (Join-Path $fixture.Repo $VenvPython) -Force
        Remove-Item -LiteralPath (Join-Path $fixture.Repo 'common/pymol/PyMOLScripts/.git') -Force
        $run = Invoke-Fixture $fixture doctor.ps1 @{ Tsv = $true }
        Assert-Exit $run 1 'structural failures'
        Assert-True (@($run.Lines | Where-Object { $_ -cmatch "^missing`tvenv-sync`tcore`t.+`tdocs/bootstrap.md W1-setup-sync$" }).Count -eq 1) 'venv-sync row'
        Assert-True (@($run.Lines | Where-Object { $_ -cmatch "^missing`tsubmodule`tcore`tnot initialized: common/pymol/PyMOLScripts.+`tdocs/bootstrap.md P0-preflight$" }).Count -eq 1) 'submodule row'
    }

    Test-Case 'doctor runs auth probes only with -Online and never fails on them' {
        $fixture = New-Fixture
        Set-FixtureHealthy $fixture
        $run = Invoke-Fixture $fixture doctor.ps1 @{ Online = $true; Tsv = $true }; Assert-Exit $run 0 'online doctor'
        foreach ($expected in @('gh auth status', 'claude auth status', 'codex login status')) { Assert-True ((Get-FixtureEvents $fixture) -contains $expected) "No $expected" }
        Assert-True ($run.Lines -contains "ok`tgh-auth`tcli`tgh auth status succeeded`t-") 'gh-auth row'
        $run = Invoke-Fixture $fixture doctor.ps1 @{ Online = $true; Tsv = $true } @{ FAKE_AUTH_EXIT = '1' }
        Assert-Exit $run 0 'signed-out doctor'
        Assert-True (@($run.Lines | Where-Object { $_ -cmatch "^human`t(gh|claude|codex)-auth`t" }).Count -eq 3) 'human auth rows'
    }

    Test-Case 'doctor rejects other hosts, unknown tiers and malformed manifests with exit 2' {
        $fixture = New-Fixture
        Assert-Exit (Invoke-Fixture $fixture doctor.ps1 @{ HostName = 'mac' }) 2 'mac host'
        Assert-Exit (Invoke-Fixture $fixture doctor.ps1 @{ Tier = 'core,bogus' }) 2 'bogus tier'
        Assert-Equal @(Get-FixtureEvents $fixture).Count 0 'usage errors probed tools'
        Add-Content -LiteralPath (Join-Path $fixture.Repo 'config/bootstrap/tools.tsv') -Value "broken`tcore`twin"
        Assert-Exit (Invoke-Fixture $fixture doctor.ps1 @{}) 2 'short row'
        $tools = Join-Path $fixture.Repo 'config/bootstrap/tools.tsv'
        [IO.File]::WriteAllLines($tools, [string[]]@([IO.File]::ReadAllLines($tools) | Select-Object -SkipLast 1))
        Add-Content -LiteralPath $tools -Value "bad`tcore`twin`turl:x`t-`t-`tbroken`tW1-winget"
        Assert-Exit (Invoke-Fixture $fixture doctor.ps1 @{}) 2 'unknown probe kind'
    }

    Test-Case 'setup-host -Check plans every step and writes nothing' {
        $fixture = New-Fixture
        $before = Get-Snapshot (Get-FixtureRoots $fixture)
        $run = Invoke-Fixture $fixture setup-host.ps1 @{ Check = $true; Tier = 'all' }
        Assert-Exit $run 3 'check with work pending'
        Assert-Equal (@($run.Lines | ForEach-Object { $_.Split(' ')[0] }) -join ',') (($AutomatedSteps + $HumanSteps) -join ',') 'plan step order'
        foreach ($line in $run.Lines) { Assert-True ($line -cmatch '^(W1|HW)-[a-z-]+ (done|todo|human|skip) \S') "Malformed plan line: $line" }
        $status = @{}; foreach ($line in $run.Lines) { $parts = $line.Split(' '); $status[$parts[0]] = $parts[1] }
        foreach ($id in $AutomatedSteps) { if ($id -ne 'W1-font' -or -not $machineTools) { Assert-Equal $status[$id] 'todo' "$id status" } }
        if (-not $machineTools) {
            Assert-True ($run.Lines -contains 'W1-font todo oh-my-posh font install CascadiaMono, once W1-winget installs oh-my-posh') 'font waits for winget'
        }
        foreach ($pair in @(@('HW-clone', 'done'), @('HW-stow', 'human'), @('HW-auth', 'human'))) { Assert-Equal $status[$pair[0]] $pair[1] $pair[0] }
        Assert-Equal (Get-Snapshot (Get-FixtureRoots $fixture)) $before '-Check wrote files'
        Assert-Equal @(Get-InstallEvents $fixture).Count 0 '-Check installed something'
        Assert-True (-not @(Get-FixtureEvents $fixture | Where-Object { $_ -match 'PSResource|Invoke-WebRequest' }).Count) '-Check queried the network or PSResourceGet'
        # A ~/.gitconfig symlink into this checkout marks HW-stow done.
        $gitconfig = Join-Path $fixture.Repo 'common/git/.gitconfig'
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $gitconfig)); [IO.File]::WriteAllText($gitconfig, '')
        try { [void](New-Item -ItemType SymbolicLink -Path (Join-Path $fixture.Home '.gitconfig') -Target $gitconfig) } catch { } # no symlink right
        $default = Invoke-Fixture $fixture setup-host.ps1 @{ Check = $true }; Assert-Exit $default 3 'default-tier check'
        Assert-True ($default.Lines -contains 'W1-psresources skip no selected tier needs PowerShell modules') 'desktop modules under default tiers'
        Assert-True ($default.Lines -contains 'W1-font skip no selected tier needs the Nerd Font') 'font under default tiers'
        if (Test-Path -LiteralPath (Join-Path $fixture.Home '.gitconfig')) { Assert-True ($default.Lines -contains 'HW-stow done already done') 'stowed .gitconfig' }
    }

    Test-Case 'setup-host refuses a non-interactive run without -Yes and bad usage' {
        $fixture = New-Fixture
        $before = Get-Snapshot (Get-FixtureRoots $fixture)
        $run = Invoke-Fixture $fixture setup-host.ps1 @{}
        Assert-Exit $run 2 'no -Yes'
        Assert-True ($run.Stdout.Contains('without -Yes')) 'refusal message'
        Assert-Exit (Invoke-Fixture $fixture setup-host.ps1 @{ HostName = 'lab-ubuntu'; Yes = $true }) 2 'unix host'
        Assert-Exit (Invoke-Fixture $fixture setup-host.ps1 @{ Tier = 'nope'; Yes = $true }) 2 'bad tier'
        Assert-Equal @(Get-FixtureEvents $fixture).Count 0 'refused runs probed or installed'
        Assert-Equal (Get-Snapshot (Get-FixtureRoots $fixture)) $before 'refused runs wrote files'
        [IO.File]::WriteAllText((Join-Path $fixture.Repo 'config/bootstrap/winget.json'), '{"Sources": []}')
        Assert-Exit (Invoke-Fixture $fixture setup-host.ps1 @{ Check = $true }) 2 'empty winget.json'
    }

    Test-Case 'setup-host -PrintManual prints every HUMAN block and nothing else' {
        $fixture = New-Fixture
        $run = Invoke-Fixture $fixture setup-host.ps1 @{ PrintManual = $true }
        Assert-Exit $run 0 'print manual'
        $blocks = Get-HumanBlocks $run.Lines
        Assert-Equal (($blocks | ForEach-Object Id) -join ',') ($HumanSteps -join ',') 'HUMAN ids'
        Assert-Equal (($blocks | ForEach-Object Kind) -join ',') 'gui,judgment,judgment,judgment,sudo,judgment,auth' 'HUMAN kinds'
        Assert-Equal @($run.Lines | Where-Object { $_ -notmatch '^HUMAN-' }).Count (@($blocks | ForEach-Object { $_.Lines.Count }) | Measure-Object -Sum).Sum 'text outside blocks'
        $text = $run.Stdout
        foreach ($expected in @('.\stow-all.ps1 win', '.\scripts\dotfiles-auto-stow.ps1 -Register',
                'Set-ExecutionPolicy RemoteSigned -Scope CurrentUser', 'wsl --install -d Ubuntu', 'named exactly Ubuntu',
                'Developer Mode', 'core.symlinks true', 'Set-Service -Name ssh-agent -StartupType Automatic', 'gh auth login --git-protocol ssh')) {
            Assert-True ($text.Contains($expected)) "HUMAN blocks lack '$expected'"
        }
        Assert-Equal @(Get-FixtureEvents $fixture).Count 0 'print manual probed tools'
    }

    Test-Case 'setup-host applies every todo step once, in order, then prints HUMAN blocks' {
        if ($machineTools) { Write-Output 'SKIP: oh-my-posh or the Nerd Font is installed on this machine.'; return }
        $fixture = New-Fixture
        foreach ($name in $ToolText.Keys) { if ($name -ne 'git') { New-ToolShim $fixture.Packages $name } }
        [void][IO.Directory]::CreateDirectory((Join-Path $fixture.Modules 'PSFzf'))
        $repoBefore = @((Get-Snapshot @($fixture.Repo)).Split("`n"))
        $environment = @{ FAKE_PSRESOURCE_INSTALLED = 'CompletionPredictor' }
        $run = Invoke-Fixture $fixture setup-host.ps1 @{ Yes = $true; Tier = 'all' } $environment
        Assert-Exit $run 3 'full apply'
        $url = @([IO.File]::ReadAllLines((Join-Path $fixture.Repo 'config/bootstrap/installers.tsv')) |
                Where-Object { $_.StartsWith("bat-theme`t") })[0].Split("`t")[2]
        $expected = @((Get-ImportEvent $fixture), 'Install-PSResource -Name Microsoft.WinGet.CommandNotFound -Scope CurrentUser -TrustRepository -AcceptLicense',
            'oh-my-posh font install CascadiaMono', "Invoke-WebRequest $url", 'bat cache --build', 'setup-sync.ps1')
        Assert-Equal ((Get-InstallEvents $fixture) -join "`n") ($expected -join "`n") 'apply events'
        $queries = @(Get-FixtureEvents $fixture | Where-Object { $_ -like 'Get-InstalledPSResource *' })
        Assert-Equal ($queries -join ',') 'Get-InstalledPSResource CompletionPredictor,Get-InstalledPSResource Microsoft.WinGet.CommandNotFound' 'PSResourceGet queries'
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $fixture.AppData $ThemeFile))) 'fixture Catppuccin Mocha theme' 'theme bytes'
        $repoAdded = @((Get-Snapshot @($fixture.Repo)).Split("`n") | Where-Object { $_ -notin $repoBefore })
        $outside = @($repoAdded | Where-Object { -not $_.StartsWith((Join-Path $fixture.Repo '.venv-sync')) })
        Assert-Equal ($outside -join "`n") '' 'apply wrote inside the checkout outside .venv-sync'
        Assert-True $repoAdded.Count '.venv-sync was not created'
        $blocks = Get-HumanBlocks $run.Lines
        $ids = @($blocks | ForEach-Object Id)
        Assert-True ($ids -contains 'HW-stow' -and $ids -contains 'HW-auth') "HUMAN blocks: $($ids -join ',')"
        Assert-True ($ids -notcontains 'HW-clone') 'HW-clone printed although core.symlinks is true'
        Assert-Equal @(Get-ChildItem -LiteralPath $fixture.Temp -Filter 'dotfiles-bootstrap-*').Count 0 'scratch left behind'
        $count = @(Get-FixtureEvents $fixture).Count
        Assert-Exit (Invoke-Fixture $fixture setup-host.ps1 @{ Yes = $true; Tier = 'all' } $environment) 3 'second apply'
        $new = @(Get-FixtureEvents $fixture | Select-Object -Skip $count | Where-Object { $_ -cmatch $InstallEvent })
        Assert-Equal ($new -join '; ') '' 'second apply installed again'
        $check = Invoke-Fixture $fixture setup-host.ps1 @{ Check = $true; Tier = 'all' }
        foreach ($id in @('W1-winget', 'W1-font', 'W1-bat-theme', 'W1-setup-sync')) { Assert-True (@($check.Lines -like "$id done *").Count -eq 1) "$id not done after apply" }
    }

    Test-Case 'setup-host -WhatIf previews without installing' {
        $fixture = New-Fixture
        foreach ($name in $ToolText.Keys) { if ($name -ne 'git') { New-ToolShim $fixture.Packages $name } }
        $before = Get-Snapshot (Get-FixtureRoots $fixture)
        Assert-Exit (Invoke-Fixture $fixture setup-host.ps1 @{ Yes = $true; Tier = 'all'; WhatIf = $true }) 3 'what-if'
        Assert-Equal @(Get-InstallEvents $fixture).Count 0 'what-if installed'
        Assert-Equal (Get-Snapshot (Get-FixtureRoots $fixture)) $before 'what-if wrote files'
    }

    Test-Case 'setup-host skips the font without oh-my-posh and stops at a failed step' {
        if ($machineTools) { Write-Output 'SKIP: oh-my-posh or the Nerd Font is installed on this machine.'; return }
        $fixture = New-Fixture
        Set-FixtureHealthy $fixture -Except @('oh-my-posh')
        Remove-Item -LiteralPath (Join-Path $fixture.LocalAppData $FontFile) -Force
        $run = Invoke-Fixture $fixture setup-host.ps1 @{ Yes = $true; Tier = 'desktop' }
        Assert-Exit $run 3 'desktop apply without oh-my-posh'
        Assert-True (@(Get-FixtureEvents $fixture) -contains (Get-ImportEvent $fixture)) 'winget import did not run'
        Assert-True (-not @(Get-FixtureEvents $fixture | Where-Object { $_ -like 'oh-my-posh*' }).Count) 'font installed without oh-my-posh'
        Assert-True ($run.Lines -contains '[dotfiles] [info] W1-font: skip: oh-my-posh is not on PATH, so the font is not installed') "font skip line: $($run.Stdout)"

        $fixture = New-Fixture
        Set-FixtureHealthy $fixture
        Remove-Item -LiteralPath (Join-Path $fixture.AppData $ThemeFile) -Force
        Remove-Item -LiteralPath (Join-Path $fixture.Repo $VenvPython) -Force
        [IO.File]::WriteAllText($fixture.Download, 'tampered theme')
        $run = Invoke-Fixture $fixture setup-host.ps1 @{ Yes = $true }
        Assert-Exit $run 1 'digest mismatch'
        Assert-True ($run.Stdout.Contains('sha256 mismatch')) "mismatch message: $($run.Stdout)"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixture.AppData $ThemeFile))) 'tampered theme installed'
        Assert-True ((Get-FixtureEvents $fixture) -notcontains 'setup-sync.ps1') 'a later step ran after a failure'
        Assert-Equal (Get-HumanBlocks $run.Lines).Count 0 'HUMAN blocks after a failure'
        Assert-Equal @(Get-ChildItem -LiteralPath $fixture.Temp -Filter 'dotfiles-bootstrap-*').Count 0 'scratch left behind'

        $fixture = New-Fixture
        $run = Invoke-Fixture $fixture setup-host.ps1 @{ Yes = $true } @{ FAKE_WINGET_EXIT = [string][int]0x8A150046 }
        Assert-Exit $run 1 'winget failure'
        Assert-True ($run.Stdout.Contains('winget exited 0x8A150046 (source agreements were not accepted)')) "winget message: $($run.Stdout)"
        Assert-Equal (@(Get-InstallEvents $fixture) -join '; ') (@(Get-InstallEvents $fixture | Select-Object -First 1) -join '; ') 'steps ran after the winget failure'
    }

    Write-Output "bootstrap-ps=PASS ($script:Passed cases)"
}
finally {
    if ([IO.Path]::GetFileName($testRoot) -notlike 'dotfiles-bootstrap-ps-*') { throw 'Unexpected cleanup target.' }
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
