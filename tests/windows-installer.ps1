#Requires -Version 7.0
# Native integration only: real Git Bash helpers and filesystem links, no mocks.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if (-not $IsWindows) { throw 'Native Windows installer tests require Windows; do not count a Unix skip as coverage.' }

$sourceRoot = Split-Path $PSScriptRoot -Parent
$powerShell = Join-Path $PSHOME 'pwsh.exe'
$gitExecutable = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
try {
    $elevated = ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
} finally { $identity.Dispose() }
if (-not $elevated) { throw 'Native installer integration needs an elevated process to create trusted symlinks.' }

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-native-stow-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$environmentNames = @(@('DOTFILES_SYNC_PYTHON', 'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM',
        'GIT_TERMINAL_PROMPT', 'GIT_TEMPLATE_DIR', 'BASH_ENV', 'ENV', 'DOTFILES_COLOR', 'NO_COLOR') +
    @(Get-ChildItem Env: | Where-Object Name -Like 'GIT_*' | Select-Object -ExpandProperty Name) |
    Sort-Object -Unique)
$savedEnvironment = @{}
foreach ($name in $environmentNames) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name) }
$script:Passed = 0
$script:FixtureNumber = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -cne $Actual) { throw "$Message (expected '$Expected', actual '$Actual')" }
}
function Write-FixtureFile {
    param([string]$Path, [string]$Text)
    [void][IO.Directory]::CreateDirectory((Split-Path $Path -Parent))
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function Invoke-FixtureGit {
    & $gitExecutable @args 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Fixture Git command failed: $args" }
}
function Get-TestGitBash {
    $directory = Split-Path -Parent $gitExecutable
    while ($directory) {
        $candidate = Join-Path $directory 'bin/bash.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        $directory = Split-Path -Parent $directory
    }
    throw 'Native installer fixtures require Git Bash beside the real Git executable.'
}
function New-Fixture {
    $script:FixtureNumber++
    $root = Join-Path $testRoot "fixture $script:FixtureNumber"
    $repo = Join-Path $root 'checkout with spaces'
    $target = Join-Path $root 'target home with spaces'
    [void][IO.Directory]::CreateDirectory($repo)
    foreach ($relative in @('stow-all.ps1', 'dotfiles-auto-stow.ps1', '.stowrc',
            'lib/config_sync.py', 'lib/sync-runtime.sh', 'lib/terminal.ps1',
            'common/claude/.local/bin/claude-settings-sync', 'common/claude/.claude/settings.json',
            'common/codex/.local/bin/codex-config-sync', 'common/codex/.local/bin/codex-rules-sync',
            'common/codex/.codex/config.toml', 'common/codex/.codex/rules/portable.rules')) {
        $destination = Join-Path $repo $relative
        [void][IO.Directory]::CreateDirectory((Split-Path $destination -Parent))
        Copy-Item -LiteralPath (Join-Path $sourceRoot $relative) -Destination $destination
    }
    foreach ($package in @('claude', 'codex', 'conda', 'git', 'pymol', 'ssh', 'wezterm')) {
        Write-FixtureFile (Join-Path $repo "common/$package/.fixture-$package") "$package`n"
    }
    Write-FixtureFile (Join-Path $repo 'common/git/.gitconfig') "[user]`n    name = common fixture`n"
    Write-FixtureFile (Join-Path $repo 'common/git/.stow-local-ignore') "(^|/)ignored[.]txt$`n"
    Write-FixtureFile (Join-Path $repo 'common/git/ignored.txt') 'local ignore sentinel'
    Write-FixtureFile (Join-Path $repo 'common/git/.DS_Store') 'global ignore sentinel'
    Write-FixtureFile (Join-Path $repo 'common/sh/.profile') 'POSIX package must not be installed'
    Write-FixtureFile (Join-Path $repo 'win/git/.gitconfig') "[user]`n    name = host fixture`n"
    Write-FixtureFile (Join-Path $repo 'win/terminal/AppData/Local/terminal/settings.json') '{"theme":"host"}'
    Invoke-FixtureGit init --quiet --initial-branch=main $repo
    Invoke-FixtureGit -C $repo config user.name 'Dotfiles tests'
    Invoke-FixtureGit -C $repo config user.email 'dotfiles-tests@example.invalid'
    Invoke-FixtureGit -C $repo config core.autocrlf false
    Invoke-FixtureGit -C $repo add stow-all.ps1 dotfiles-auto-stow.ps1 .stowrc lib common win
    Invoke-FixtureGit -C $repo commit --quiet -m fixture
    return [pscustomobject]@{ Root = $root; Repo = $repo; Target = $target }
}
function Invoke-Install {
    param($Fixture, [AllowEmptyString()][string]$HostDir = 'win', [switch]$Preview,
        [bool]$StrictMode = $true, [string]$TargetOverride = '')
    $target = if ($TargetOverride) { $TargetOverride } else { $Fixture.Target }
    $arguments = @('-NoProfile', '-NonInteractive', '-File', (Join-Path $Fixture.Repo 'stow-all.ps1'),
        '-HostDir', $HostDir, '-TargetRoot', $target)
    if ($StrictMode) { $arguments += '-Strict' }
    if ($Preview) { $arguments += '-WhatIf' }
    $output = & $powerShell @arguments 2>&1 | Out-String
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}
function Assert-Success {
    param($Result)
    Assert-Equal 0 $Result.ExitCode $Result.Output
}
function Assert-Failure {
    param($Result, [string]$Pattern)
    Assert-True ($Result.ExitCode -ne 0) "Expected installer failure: $($Result.Output)"
    Assert-True ($Result.Output -match $Pattern) "Missing '$Pattern' in failure: $($Result.Output)"
}
function Assert-Link {
    param([string]$Path, [string]$Target)
    $item = Get-Item -LiteralPath $Path -Force
    Assert-Equal 'SymbolicLink' $item.LinkType "Not a symlink: $Path"
    Assert-Equal $Target @($item.Target)[0] "Wrong link target: $Path"
    [void][IO.File]::ReadAllBytes($Path)
}
function Assert-NoState {
    param($Fixture)
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Fixture.Repo '.git/dotfiles-sync-windows'))) `
        'Custom-target, preview or failed installation wrote real-profile updater state.'
}
function Test-Case {
    param([string]$Name, [scriptblock]$Action)
    & $Action
    $script:Passed++
    Write-Output "PASS: $Name"
}

try {
    # -C cannot neutralize an inherited GIT_DIR/INDEX_FILE/CONFIG_COUNT or
    # object-store redirect. Keep all fixture Git activity inside this tree.
    # SetEnvironmentVariable(name, $null) can leave an empty entry, which Git
    # still interprets as an override. Remove the provider entry explicitly.
    foreach ($name in $environmentNames) {
        if ($name.StartsWith('GIT_', [StringComparison]::OrdinalIgnoreCase) -or $name -in @('BASH_ENV', 'ENV', 'DOTFILES_COLOR', 'NO_COLOR')) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            Assert-True (-not (Test-Path -LiteralPath "Env:$name")) "Environment override was not removed: $name"
        }
    }
    $env:GIT_CONFIG_GLOBAL = Join-Path $testRoot 'empty.gitconfig'
    [IO.File]::WriteAllText($env:GIT_CONFIG_GLOBAL, '')
    $env:GIT_CONFIG_NOSYSTEM = '1'
    $env:GIT_TERMINAL_PROMPT = '0'
    $env:GIT_TEMPLATE_DIR = Join-Path $testRoot 'empty-git-template'
    [void][IO.Directory]::CreateDirectory($env:GIT_TEMPLATE_DIR)
    if (-not $env:DOTFILES_SYNC_PYTHON) {
        $env:DOTFILES_SYNC_PYTHON = Join-Path $sourceRoot '.venv-sync/Scripts/python.exe'
    }
    if (-not (Test-Path -LiteralPath $env:DOTFILES_SYNC_PYTHON -PathType Leaf)) {
        throw 'Provision setup-sync.ps1 or DOTFILES_SYNC_PYTHON before native installer tests.'
    }
    & $env:DOTFILES_SYNC_PYTHON -I -B -c 'import tomlkit'
    if ($LASTEXITCODE -ne 0) { throw 'The configured sync interpreter lacks tomlkit.' }
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'lib/config_sync.py') -PathType Leaf)) {
        throw 'Shared configuration backend is missing; native integration cannot run.'
    }
    $gitBash = Get-TestGitBash

    Test-Case 'real links, host precedence, ignore rules, allowlist and materialized AI files' {
        $fixture = New-Fixture
        $portable = Join-Path $fixture.Repo 'common/codex/.codex/config.toml'
        $sourceHash = (Get-FileHash -LiteralPath $portable).Hash
        Assert-Success (Invoke-Install $fixture)
        Assert-Link (Join-Path $fixture.Target '.gitconfig') (Join-Path $fixture.Repo 'win/git/.gitconfig')
        Assert-Link (Join-Path $fixture.Target '.fixture-conda') (Join-Path $fixture.Repo 'common/conda/.fixture-conda')
        Assert-Link (Join-Path $fixture.Target 'AppData/Local/terminal/settings.json') `
            (Join-Path $fixture.Repo 'win/terminal/AppData/Local/terminal/settings.json')
        foreach ($relative in @('.profile', 'ignored.txt', '.DS_Store', '.stow-local-ignore')) {
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixture.Target $relative))) "Ignored path installed: $relative"
        }
        foreach ($relative in @('.codex/config.toml', '.codex/rules/portable.rules', '.claude/settings.json')) {
            $item = Get-Item -LiteralPath (Join-Path $fixture.Target $relative) -Force
            Assert-True (-not $item.LinkType) "AI live file is linked: $relative"
        }
        # Exercise Git Bash readlink and checkout discovery through the native
        # Windows symlink, not just the source wrapper invoked before stow.
        $installedWrapper = Join-Path $fixture.Target '.local/bin/codex-config-sync'
        Assert-Link $installedWrapper (Join-Path $fixture.Repo 'common/codex/.local/bin/codex-config-sync')
        $checkOutput = & $gitBash ($installedWrapper -replace '\\', '/') --check `
            ($portable -replace '\\', '/') ((Join-Path $fixture.Target '.codex/config.toml') -replace '\\', '/') 2>&1 | Out-String
        Assert-Equal 0 $LASTEXITCODE "Stowed wrapper failed to resolve the shared backend: $checkOutput"
        Assert-Equal $sourceHash (Get-FileHash -LiteralPath $portable).Hash 'Portable TOML source changed.'
        $changes = & $gitExecutable -C $fixture.Repo status --porcelain
        Assert-True (-not $changes) 'Installation modified the fixture checkout.'
        Assert-NoState $fixture
    }

    Test-Case 'uppercase WIN is normalized before selecting the overlay' {
        $fixture = New-Fixture
        $result = Invoke-Install $fixture -HostDir 'WIN'
        Assert-Success $result
        Assert-Link (Join-Path $fixture.Target '.gitconfig') (Join-Path $fixture.Repo 'win/git/.gitconfig')
        Assert-True ($result.Output.Contains('[dotfiles] [step] Stowing host packages (win):')) 'Host logging did not use canonical win.'
        Assert-True ($result.Output.Contains('[dotfiles] [ok] Stow complete;')) 'Installer success summary missing.'
        Assert-True (-not $result.Output.Contains([string][char]27)) 'Redirected installer emitted ANSI by default.'
        Assert-True ($result.Output -notmatch '(?m)^\s*(Validated|Synchronized)\b') 'Sync helper chatter escaped --quiet.'
        Assert-NoState $fixture
    }

    Test-Case 'common-only installs and repeated installs preserve unchanged live files' {
        $fixture = New-Fixture
        Assert-Success (Invoke-Install $fixture -HostDir '')
        Assert-Link (Join-Path $fixture.Target '.gitconfig') (Join-Path $fixture.Repo 'common/git/.gitconfig')
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixture.Target 'AppData'))) 'Common-only installed a host package.'
        $live = Join-Path $fixture.Target '.claude/settings.json'
        $sentinelTime = [DateTime]::SpecifyKind([DateTime]'2001-02-03T04:05:06', [DateTimeKind]::Utc)
        [IO.File]::SetLastWriteTimeUtc($live, $sentinelTime)
        Assert-Success (Invoke-Install $fixture -HostDir '')
        Assert-Equal $sentinelTime ([IO.File]::GetLastWriteTimeUtc($live)) 'No-op sync replaced live JSON.'
        Assert-NoState $fixture
    }

    Test-Case 'host AI source overrides the common baseline while retaining live-only state' {
        $fixture = New-Fixture
        Write-FixtureFile (Join-Path $fixture.Repo 'win/claude/.claude/settings.json') `
            '{"permissions":{"allow":[],"ask":[]},"theme":"host-override"}'
        Write-FixtureFile (Join-Path $fixture.Target '.claude/settings.json') '{"model":"local-choice"}'
        Assert-Success (Invoke-Install $fixture)
        $settings = Get-Content -LiteralPath (Join-Path $fixture.Target '.claude/settings.json') -Raw | ConvertFrom-Json
        Assert-Equal 'host-override' $settings.theme 'Host portable JSON was not selected.'
        Assert-Equal 'local-choice' $settings.model 'Host override removed live-only model.'
        Assert-NoState $fixture
    }

    Test-Case 'adoption, unique backups and stale-link repair use real filesystem objects' {
        $fixture = New-Fixture
        Write-FixtureFile (Join-Path $fixture.Target '.fixture-conda') "conda`r`n"
        Write-FixtureFile (Join-Path $fixture.Target '.fixture-ssh') 'keep this conflict'
        Write-FixtureFile (Join-Path $fixture.Target '.fixture-pymol/nested.txt') 'keep this directory conflict'
        $stale = Join-Path $fixture.Root 'old-wezterm'
        Write-FixtureFile $stale 'stale target remains'
        New-Item -ItemType SymbolicLink -Path (Join-Path $fixture.Target '.fixture-wezterm') -Value $stale | Out-Null
        Assert-Success (Invoke-Install $fixture)
        Assert-Link (Join-Path $fixture.Target '.fixture-conda') (Join-Path $fixture.Repo 'common/conda/.fixture-conda')
        Assert-Link (Join-Path $fixture.Target '.fixture-wezterm') (Join-Path $fixture.Repo 'common/wezterm/.fixture-wezterm')
        $backups = @(Get-ChildItem -LiteralPath $fixture.Target -Force -Filter '.fixture-ssh.stow-backup-*')
        Assert-Equal 1 $backups.Count 'Conflict must have one backup.'
        Assert-Equal 'keep this conflict' ([IO.File]::ReadAllText($backups[0].FullName)) 'Backup bytes changed.'
        $directoryBackups = @(Get-ChildItem -LiteralPath $fixture.Target -Force -Directory -Filter '.fixture-pymol.stow-backup-*')
        Assert-Equal 1 $directoryBackups.Count 'Directory conflict must have one backup.'
        Assert-Equal 'keep this directory conflict' ([IO.File]::ReadAllText((Join-Path $directoryBackups[0].FullName 'nested.txt'))) `
            'Directory backup contents changed.'
        Assert-Equal 0 @(Get-ChildItem -LiteralPath $fixture.Target -Force -Filter '.fixture-conda.stow-backup-*').Count `
            'Identical CRLF file was backed up instead of adopted.'
        Remove-Item -LiteralPath (Join-Path $fixture.Target '.fixture-ssh') -Force
        Write-FixtureFile (Join-Path $fixture.Target '.fixture-ssh') 'second conflict'
        Assert-Success (Invoke-Install $fixture)
        Assert-Equal 2 @(Get-ChildItem -LiteralPath $fixture.Target -Force -Filter '.fixture-ssh.stow-backup-*').Count `
            'A subsequent backup overwrote an earlier conflict.'
        Assert-Equal 'stale target remains' ([IO.File]::ReadAllText($stale)) 'Stale-link replacement modified its target.'
    }

    Test-Case 'case-only and invalid-UTF8 differences are backed up rather than adopted' {
        $fixture = New-Fixture
        Write-FixtureFile (Join-Path $fixture.Target '.fixture-ssh') "SSH`n"
        $binarySource = Join-Path $fixture.Repo 'common/conda/.fixture-conda'
        $binaryTarget = Join-Path $fixture.Target '.fixture-conda'
        [IO.File]::WriteAllBytes($binarySource, [byte[]]@(0xfe))
        [IO.File]::WriteAllBytes($binaryTarget, [byte[]]@(0xff))
        Assert-Success (Invoke-Install $fixture)
        $textBackups = @(Get-ChildItem -LiteralPath $fixture.Target -Force -Filter '.fixture-ssh.stow-backup-*')
        Assert-Equal 1 $textBackups.Count 'Case-only conflict was adopted without a backup.'
        Assert-Equal "SSH`n" ([IO.File]::ReadAllText($textBackups[0].FullName)) 'Case-only backup changed.'
        $binaryBackups = @(Get-ChildItem -LiteralPath $fixture.Target -Force -Filter '.fixture-conda.stow-backup-*')
        Assert-Equal 1 $binaryBackups.Count 'Binary conflict was adopted without a backup.'
        $bytes = [IO.File]::ReadAllBytes($binaryBackups[0].FullName)
        Assert-True ($bytes.Length -eq 1 -and $bytes[0] -eq 0xff) 'Binary backup bytes changed.'
        Assert-NoState $fixture
    }

    Test-Case 'legacy AI links are materialized without editing their portable targets' {
        $fixture = New-Fixture
        $portable = Join-Path $fixture.Repo 'common/claude/.claude/settings.json'
        $sourceHash = (Get-FileHash -LiteralPath $portable).Hash
        [void][IO.Directory]::CreateDirectory((Join-Path $fixture.Target '.claude'))
        $live = Join-Path $fixture.Target '.claude/settings.json'
        New-Item -ItemType SymbolicLink -Path $live -Value $portable | Out-Null
        Assert-Success (Invoke-Install $fixture)
        Assert-True (-not (Get-Item -LiteralPath $live -Force).LinkType) 'Legacy AI symlink remains.'
        Assert-Equal $sourceHash (Get-FileHash -LiteralPath $portable).Hash 'Legacy-link target was rewritten.'
    }

    Test-Case 'WhatIf creates no target, links, backend cache or applied-state metadata' {
        $fixture = New-Fixture
        Assert-Success (Invoke-Install $fixture -Preview)
        Assert-True (-not (Test-Path -LiteralPath $fixture.Target)) 'WhatIf created the absent target.'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixture.Repo 'lib/__pycache__'))) 'WhatIf wrote Python bytecode.'
        Assert-NoState $fixture
    }

    Test-Case 'WhatIf preserves existing conflicts and mutable settings' {
        $fixture = New-Fixture
        Write-FixtureFile (Join-Path $fixture.Target '.fixture-ssh') 'preview conflict'
        Write-FixtureFile (Join-Path $fixture.Target '.claude/settings.json') '{"model":"local-choice"}'
        Assert-Success (Invoke-Install $fixture -Preview)
        Assert-Equal 'preview conflict' ([IO.File]::ReadAllText((Join-Path $fixture.Target '.fixture-ssh'))) 'Preview changed conflict.'
        Assert-Equal '{"model":"local-choice"}' ([IO.File]::ReadAllText((Join-Path $fixture.Target '.claude/settings.json'))) `
            'Preview changed live JSON.'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixture.Target '.codex'))) 'Preview created Codex directory.'
        Assert-NoState $fixture
    }

    Test-Case 'invalid final Claude source blocks every earlier merge and link' {
        $fixture = New-Fixture
        Write-FixtureFile (Join-Path $fixture.Repo 'common/claude/.claude/settings.json') '{invalid'
        Write-FixtureFile (Join-Path $fixture.Target '.codex/config.toml') "runtime_only = 'keep'`n"
        $before = [IO.File]::ReadAllText((Join-Path $fixture.Target '.codex/config.toml'))
        Assert-Failure (Invoke-Install $fixture -StrictMode $false) 'Claude settings sync preflight failed'
        Assert-Equal $before ([IO.File]::ReadAllText((Join-Path $fixture.Target '.codex/config.toml'))) 'Earlier Codex merge ran before failed Claude validation.'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixture.Target '.fixture-conda'))) 'A package linked before preflight completed.'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixture.Target '.codex/rules'))) 'Earlier rules sync ran before failed Claude validation.'
        Assert-NoState $fixture
    }

    Test-Case 'missing late helper fails closed without creating a target' {
        $fixture = New-Fixture
        Remove-Item -LiteralPath (Join-Path $fixture.Repo 'common/claude/.local/bin/claude-settings-sync')
        Assert-Failure (Invoke-Install $fixture -StrictMode $false) 'Claude settings sync prerequisite missing'
        Assert-True (-not (Test-Path -LiteralPath $fixture.Target)) 'Missing helper caused a partial install.'
        Assert-NoState $fixture
    }

    Test-Case 'missing runtime fails closed without installing dependencies' {
        $fixture = New-Fixture
        $savedPython = $env:DOTFILES_SYNC_PYTHON
        try {
            $env:DOTFILES_SYNC_PYTHON = Join-Path $fixture.Root 'missing-python.exe'
            Assert-Failure (Invoke-Install $fixture) 'sync preflight failed'
        } finally { $env:DOTFILES_SYNC_PYTHON = $savedPython }
        Assert-True (-not (Test-Path -LiteralPath $fixture.Target)) 'Missing runtime caused a partial install.'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixture.Repo '.venv-sync'))) 'Installer provisioned dependencies implicitly.'
        Assert-NoState $fixture
    }

    Test-Case 'invalid host and missing win overlay are rejected before mutation' {
        $fixture = New-Fixture
        Assert-Failure (Invoke-Install $fixture -HostDir '../common') 'Unsupported Windows host'
        Move-Item -LiteralPath (Join-Path $fixture.Repo 'win') -Destination (Join-Path $fixture.Root 'saved-win')
        Assert-Failure (Invoke-Install $fixture) 'host dir not found'
        Assert-True (-not (Test-Path -LiteralPath $fixture.Target)) 'Invalid host caused a partial install.'
        Assert-NoState $fixture
    }

    Test-Case 'Strict missing-package warnings fail before mutation and do not acknowledge' {
        $fixture = New-Fixture
        Move-Item -LiteralPath (Join-Path $fixture.Repo 'common/pymol') -Destination (Join-Path $fixture.Root 'saved-pymol')
        Assert-Failure (Invoke-Install $fixture) 'Stow preflight failed.*common package not found'
        Assert-True (-not (Test-Path -LiteralPath $fixture.Target)) 'Strict preflight warning caused a partial install.'
        Assert-NoState $fixture
    }

    Test-Case 'invalid ignore expressions fail before portable sync or package writes' {
        $fixture = New-Fixture
        Write-FixtureFile (Join-Path $fixture.Repo 'win/git/.stow-local-ignore') '[invalid'
        Assert-Failure (Invoke-Install $fixture) 'Invalid pattern|Unterminated|Exception'
        Assert-True (-not (Test-Path -LiteralPath $fixture.Target)) 'Invalid ignore caused a partial install.'
        Assert-NoState $fixture
    }

    Test-Case 'root and relative targets are rejected' {
        $fixture = New-Fixture
        Assert-Failure (Invoke-Install $fixture -TargetOverride ([IO.Path]::GetPathRoot($fixture.Target))) 'must not be a drive or share root'
        Assert-Failure (Invoke-Install $fixture -TargetOverride 'relative-target') 'must be an absolute Windows directory path'
        Assert-True (-not (Test-Path -LiteralPath $fixture.Target)) 'Invalid target created directories.'
        Assert-NoState $fixture
    }
    Write-Output "windows-installer-native=PASS ($script:Passed cases)"
} finally {
    foreach ($name in $environmentNames) {
        if ($null -eq $savedEnvironment[$name]) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name])
        }
    }
    # Every fixture and backup belongs to this exact uniquely-created directory.
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
