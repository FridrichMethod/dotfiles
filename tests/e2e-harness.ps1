#Requires -Version 7.0
# Unit test of the native Windows end-to-end driver, tests/e2e/run.ps1 and
# tests/e2e/lib/*.ps1: the PowerShell twin of tests/e2e-harness.sh. The
# libraries are dot-sourced into this process and run unchanged; what would
# reach the machine is replaced by stubs defined in a case's own scope, where
# the driver resolves them: each setup-host.ps1 run (realistic -Yes output
# with winget's blank progress lines and CRLF endings), each child pwsh the
# home-deploy and home-converged steps start (the stub writes the
# config, state database and private copies Fresh Windows home by hand
# leaves, or the diff and managed list of the convergence check), the
# elevation probe, the scheduled task list, the registry PATH rebuild and the
# HOME snapshots of the no-write steps. The clean-clone check and rev-parse
# run real git on a temp repository standing in for the clone; the clone's
# lib/chezmoi-guard.ps1 judges the config's sourceDir and destDir for real; Invoke-E2EProcess, the
# run.ps1 refusals and setup-host.ps1 -PrintManual run as real child pwsh
# processes with their caches kept under the temp dir off Windows; the
# docs/bootstrap.md fence of Fresh Windows home by hand is parsed and
# checked, never run (bootstrap-e2e runs it on the windows-2025 runner).
# Every tree lives under one temp directory, removed at the end, also on
# failure; nothing reads or writes the real home or profile, and no git runs
# on the real repository. Runs on Linux and macOS pwsh as well as Windows;
# the Windows-only checks are guarded and print a SKIP line elsewhere.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$sourceRoot = Split-Path $PSScriptRoot -Parent
$powerShell = (Get-Process -Id $PID).Path
$gitCommand = Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $gitCommand) { throw 'git is required: the clean-clone check runs it on a temp repository.' }
$git = $gitCommand.Source
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-e2e-ps-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$script:Passed = 0
$script:CaseNumber = 0
$Utf8 = [Text.UTF8Encoding]::new($false)

# Git sees only the temp repositories: no system or global configuration
# (Git for Windows' autocrlf among them) and no repository above the temp dir.
# -C cannot neutralize an inherited GIT_DIR or GIT_INDEX_FILE, which a commit
# hook in a linked worktree exports, absolute: New-TempClone would then
# reinitialize and commit into the caller's repository. Remove every GIT_*
# entry first.
. (Join-Path $PSScriptRoot 'lib/environment.ps1')
Clear-DotfilesTestGitEnvironment
$env:GIT_CONFIG_NOSYSTEM = '1'
$env:GIT_CONFIG_GLOBAL = Join-Path $testRoot 'gitconfig'
$env:GIT_CEILING_DIRECTORIES = $testRoot
[IO.File]::WriteAllText($env:GIT_CONFIG_GLOBAL, '')

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ([string]$Actual -cne [string]$Expected) { throw "$Message`n  expected: [$Expected]`n  actual:   [$Actual]" }
}
function Assert-Lines([object[]]$Actual, [object[]]$Expected, [string]$Message) {
    Assert-Equal (@($Actual) -join "`n") (@($Expected) -join "`n") $Message
}
function Test-Case {
    param([string]$Name, [scriptblock]$Action)
    & $Action
    $script:Passed++
    Write-Output "PASS: $Name"
}
function Skip-Assertion([string]$Reason) { Write-Output "SKIP: $Reason" }
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
function Read-Utf8 {
    # A file the harness wrote: UTF-8 without a BOM, LF line endings.
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) "$Path starts with a BOM"
    $text = $Utf8.GetString($bytes)
    Assert-True (-not $text.Contains("`r")) "$Path holds a carriage return"
    return $text
}
function New-File {
    # Write Text to Path (parents created), dated Time when given.
    param([string]$Path, [string]$Text, [Nullable[DateTime]]$Time = $null)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, $Utf8)
    if ($null -ne $Time) { [IO.File]::SetLastWriteTimeUtc($Path, [DateTime]$Time) }
}
function ConvertTo-Quoted([string]$Text) { return "'" + $Text.Replace("'", "''") + "'" }
# Child under Base with the platform's separators, as an enumerated path or
# GetFullPath spells it.
function Get-Path([string]$Base, [string]$Child) { return [IO.Path]::GetFullPath((Join-Path $Base $Child)) }

$e2eLib = Join-Path $PSScriptRoot 'e2e/lib'
foreach ($name in @('common', 'snapshot', 'blocks', 'steps', 'appinstaller', 'flow-win')) { . (Join-Path $e2eLib "$name.ps1") }
$InitialRunState = $E2E.Clone()

# The driver's console lines, kept for assertions instead of printed.
$script:Console = [Collections.Generic.List[string]]::new()
function Write-E2ELog {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Message)
    $script:Console.Add($Message)
}

function Reset-RunState {
    # A fresh run state as run.ps1 fills it, with E2E_OUT and its
    # subdirectories under a new case directory, which it returns; Home is
    # the case's home.
    $script:CaseNumber++
    $case = Join-Path $testRoot ('case-{0:d2}' -f $script:CaseNumber)
    $out = Join-Path $case 'out'
    foreach ($subdirectory in @('log', 'steps', 'snapshots', 'tmp')) {
        [void][IO.Directory]::CreateDirectory((Join-Path $out $subdirectory))
    }
    $script:E2E = $InitialRunState.Clone()
    $E2E['Src'] = Join-Path $case 'source-not-read'
    $E2E['Rev'] = '0' * 40
    $E2E['Out'] = $out
    $E2E['Home'] = Join-Path $case 'home'
    $E2E['Git'] = $git
    $E2E['PowerShell'] = $powerShell
    $script:Console.Clear()
    return $case
}

function Invoke-Git([string]$Repository, [string[]]$Arguments) {
    $output = @(& $git -C $Repository @Arguments 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed in ${Repository}: $($output -join ' ')" }
}
function New-TempClone {
    # A committed repository standing in for $HOME\dotfiles.
    param([string]$Path)
    New-File (Join-Path $Path 'home/dot_gitconfig') "[user]`n`tname = e2e`n"
    Invoke-Git $Path @('init', '-q')
    Invoke-Git $Path @('add', '--', 'home')
    Invoke-Git $Path @('-c', 'user.name=e2e', '-c', 'user.email=e2e@example.invalid', 'commit', '-q', '-m', 'fixture')
}

function Get-SummaryRows {
    # summary.tsv as rows, each required to hold exactly five fields.
    $path = Join-Path $E2E['Out'] 'summary.tsv'
    if (-not [IO.File]::Exists($path)) { return @() }
    return @((Read-Utf8 $path).TrimEnd("`n").Split("`n") | ForEach-Object {
            $cells = $_.Split("`t")
            Assert-True ($cells.Count -eq 5) "summary.tsv row without five fields: $_"
            [pscustomobject]@{ N = $cells[0]; Step = $cells[1]; Status = $cells[2]; Seconds = $cells[3]; Detail = $cells[4] }
        })
}
function Get-RowShape([object[]]$Rows) { return (@($Rows | ForEach-Object { "$($_.Step):$($_.Status)" }) -join ' ') }
function Get-SummaryText {
    $path = Join-Path $E2E['Out'] 'summary.tsv'
    if ([IO.File]::Exists($path)) { return [IO.File]::ReadAllText($path) }
    return '(no summary.tsv)'
}

# --- setup-host.ps1 -Yes output -------------------------------------------

$Reminders = @('HW-execution-policy', 'HW-ssh-agent', 'HW-wsl', 'HW-auth')
$ReminderSummary = 'HW-execution-policy(judgment) HW-ssh-agent(sudo) HW-wsl(judgment) HW-auth(auth)'
$DoneLines = @(
    '[dotfiles] [ok] W1-winget: done: 24 winget tools on PATH'
    '[dotfiles] [ok] W1-psresources: done: 3 modules installed'
    '[dotfiles] [ok] W1-font: done: CaskaydiaMono Nerd Font installed'
    '[dotfiles] [info] W1-bat-theme: skip: no selected tier needs the bat theme'
    '[dotfiles] [ok] W1-chezmoi: done: chezmoi 2.74.0 at C:\Users\runneradmin\.local\bin\chezmoi.exe'
)

function Get-WingetLines {
    # The applied steps of a first -Yes run: winget import's spinner frames
    # (carriage returns inside one line), a progress bar and the blank lines
    # its progress leaves, as a redirected winget writes them, then the
    # chezmoi binary.
    $bar = [string]::new([char]0x2588, 30)
    return @(
        '[dotfiles] [step] W1-winget: winget import config\bootstrap\winget.json (24 tools missing)'
        "   - `r   \ `r   | `r   / `r"
        ''
        'Found Git [Git.Git] Version 2.51.0.2'
        'This application is licensed to you by its owner.'
        'Microsoft is not responsible for, nor does it grant any licenses to, third-party packages.'
        'Downloading https://github.com/git-for-windows/git/releases/download/v2.51.0.windows.2/Git-2.51.0.2-64-bit.exe'
        "  $bar  62.9 MB / 62.9 MB"
        'Successfully verified installer hash'
        'Starting package install...'
        'Successfully installed'
        ''
        '   '
        ''
        '[dotfiles] [ok] W1-winget: installed: winget import finished'
        "[dotfiles] [warn] W1-winget: not on this session's PATH yet: oh-my-posh; open a new shell, then run .\doctor.ps1"
        '[dotfiles] [step] W1-psresources: Install-PSResource PSFzf, CompletionPredictor -Scope CurrentUser'
        '[dotfiles] [ok] W1-psresources: installed: modules installed for the current user'
        '[dotfiles] [info] W1-font: skip: oh-my-posh is not on PATH, so the font is not installed'
        '[dotfiles] [step] W1-chezmoi: install the verified chezmoi 2.74.0 archive into C:\Users\runneradmin\.local\bin'
        ''
        '[dotfiles] [ok] W1-chezmoi: installed: chezmoi 2.74.0 at C:\Users\runneradmin\.local\bin\chezmoi.exe'
    )
}

function Get-BlockLines {
    # One HUMAN block as setup-host.ps1 prints it natively for a clone at
    # Clone (Get-SetupHumanBlock); no block names the clone's path.
    param([string]$Id, [string]$Clone)
    $body = switch -CaseSensitive ($Id) {
        'HW-clone' {
            'judgment', '# This checkout has no .git, so the login updater cannot pull it. Move it aside, clone onto NTFS (not into WSL), then rerun setup-host.ps1 from the clone.',
            '# Git and PowerShell 7 as the MSI in Program Files\PowerShell\7:',
            'winget install --id Git.Git -e --source winget',
            'winget install --id Microsoft.PowerShell -e --source winget --installer-type wix',
            'git clone https://github.com/FridrichMethod/dotfiles.git $HOME\dotfiles'
        }
        'HW-deploy' {
            'judgment', '# Follow Fresh Windows home by hand in docs/bootstrap.md from this checkout.',
            '# Select local [data].host = win explicitly; setup-host never initializes or applies configuration.',
            '# As the ordinary user, review with icacls the ACLs of the existing destination parents, such as ~\Documents and ~\AppData\Local\Packages; Invoke-HomeDeploy checks both actual CurrentUserAllHosts paths itself.',
            '# Snapshot exact targets and initialize with all paths explicit.',
            '# Updates write regular files and need no elevation or scheduled task.'
        }
        'HW-execution-policy' {
            'judgment', '# Lets the PowerShell profiles and these scripts run. PowerShell 7 and Windows PowerShell 5.1 keep separate settings.',
            'Set-ExecutionPolicy RemoteSigned -Scope CurrentUser',
            'powershell.exe -NoProfile -Command Set-ExecutionPolicy RemoteSigned -Scope CurrentUser'
        }
        'HW-ssh-agent' {
            'sudo', '# Elevated PowerShell (Run as administrator):', 'Set-Service -Name ssh-agent -StartupType Automatic',
            'Start-Service -Name ssh-agent', '# Then, as yourself, once HW-auth has created the key: ssh-add $HOME\.ssh\id_ed25519'
        }
        'HW-wsl' {
            'judgment', '# Optional, elevated PowerShell. Windows Terminal and WezTerm profiles need the distro named exactly Ubuntu.',
            '# ~\mount.vbs mounts one specific physical disk; do not schedule it on another machine.', 'wsl --install -d Ubuntu'
        }
        'HW-auth' {
            'auth', '# Sign in, then check with .\doctor.ps1 -Online. Skip gh auth setup-git: it would rewrite ~\.gitconfig, which the dotfiles manage.',
            'ssh-keygen -t ed25519 -f $HOME\.ssh\id_ed25519', 'gh auth login --git-protocol ssh', 'claude auth login', 'codex login'
        }
        default { throw "No fixture block for $Id" }
    }
    return @("HUMAN-BEGIN $Id $($body[0])") + @($body | Select-Object -Skip 1) + @('HUMAN-END')
}

function Get-ApplyOutput {
    # The stdout of a setup-host.ps1 -Host win -Yes run for a clone at Clone:
    # the applied steps (winget's progress and the chezmoi binary, or the
    # -Done lines of a run with nothing to apply), the HUMAN blocks of Blocks
    # in order, then the pending line naming Pending, or the closing line of
    # an exit 0.
    param([string]$Clone, [string[]]$Blocks = @(), [string]$Pending = '', [switch]$Done)
    $lines = [Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]$(if ($Done) { $DoneLines } else { Get-WingetLines }))
    foreach ($id in $Blocks) { $lines.AddRange([string[]](Get-BlockLines $id $Clone)) }
    if ($Pending) { $lines.Add("[dotfiles] [warn] HUMAN steps pending: $Pending; run the HUMAN blocks above, then rerun .\setup-host.ps1") }
    elseif ($Done) { $lines.Add('[dotfiles] [ok] setup-host: nothing blocking remains for win') }
    return , $lines.ToArray()
}

function ConvertTo-StepText {
    # Lines as a Windows child writes them to a redirected stream: CRLF after each.
    param([AllowEmptyCollection()][string[]]$Lines = @())
    if (-not $Lines.Count) { return '' }
    return ($Lines -join "`r`n") + "`r`n"
}

# --- dry-run stubs ---------------------------------------------------------

$script:Runs = [Collections.Generic.Queue[hashtable]]::new()
$script:PwshCalls = [Collections.Generic.List[object]]::new()
$script:ProcessCalls = [Collections.Generic.List[object]]::new()
$script:ProcessModes = [Collections.Generic.Queue[string]]::new()
$script:Snapshots = [Collections.Generic.Queue[object]]::new()
$script:SnapshotCalls = [Collections.Generic.List[object]]::new()
$script:TaskNames = ''
$script:Elevated = $false
$script:Managed = @()

function New-DryRun {
    # A fresh run state with its own clone (Home is its parent) and empty
    # stub queues; returns the clone.
    $case = Reset-RunState
    $clone = Join-Path $case 'home/dotfiles'
    New-TempClone $clone
    $E2E['Clone'] = $clone
    $E2E['PowerShell'] = Join-Path $case 'bin/pwsh-never-started'
    $script:Runs.Clear()
    $script:PwshCalls.Clear()
    $script:ProcessCalls.Clear()
    $script:ProcessModes.Clear()
    $script:Snapshots.Clear()
    $script:SnapshotCalls.Clear()
    $script:TaskNames = 'existing-task'
    $script:Elevated = $false
    $script:Managed = @()
    return $clone
}

function New-DeployClone {
    # New-DryRun's clone, also holding (committed, so it stays clean) what
    # the steps read from it: this checkout's docs/bootstrap.md and
    # lib/chezmoi-guard.ps1, and a .chezmoiroot. Returns the clone.
    $clone = New-DryRun
    New-File (Join-Path $clone 'docs/bootstrap.md') ([IO.File]::ReadAllText((Join-Path $sourceRoot 'docs/bootstrap.md')))
    New-File (Join-Path $clone 'lib/chezmoi-guard.ps1') ([IO.File]::ReadAllText((Join-Path $sourceRoot 'lib/chezmoi-guard.ps1')))
    New-File (Join-Path $clone '.chezmoiroot') "home`n"
    Invoke-Git $clone @('add', '--', 'docs', 'lib', '.chezmoiroot')
    Invoke-Git $clone @('-c', 'user.name=e2e', '-c', 'user.email=e2e@example.invalid', 'commit', '-q', '-m', 'fixture')
    return $clone
}

function Write-DeployState {
    # What Invoke-HomeDeploy -Role win leaves in Home, with the config's
    # top-level destDir and sourceDir in the form chezmoi init writes (on
    # Windows forward slashes and an upper-case drive) from the paths the
    # clone's own lib/chezmoi-guard.ps1 resolves, as Variant says: clean,
    # bad-config (destDir names another directory), maintenance, no-copy (no
    # private copy of the files it replaced) or no-state (an empty state
    # database).
    param([string]$Variant)
    $userHome = $E2E['Home']
    . (Join-Path $E2E['Clone'] 'lib/chezmoi-guard.ps1')
    $destination = Resolve-DotfilesDirectory $userHome
    $source = Resolve-DotfilesDirectory $E2E['Clone']
    $keep = Join-Path $userHome '.local/state/dotfiles-fresh-backup'
    [void][IO.Directory]::CreateDirectory($keep)
    foreach ($relative in @('.gitconfig', 'Documents/PowerShell/profile.ps1')) {
        $path = Join-Path $userHome $relative
        if ([IO.File]::Exists($path) -and $Variant -cne 'no-copy') {
            $copy = Join-Path $keep $relative
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $copy))
            [IO.File]::Copy($path, $copy)
        }
    }
    $configHome = if ($Variant -ceq 'bad-config') { Join-Path $destination 'elsewhere' } else { $destination }
    $form = {
        param([string]$Path)
        if (-not $IsWindows) { return $Path }
        $Path = $Path.Replace('\', '/')
        return $Path.Substring(0, 1).ToUpperInvariant() + $Path.Substring(1)
    }
    New-File (Join-Path $userHome '.config/chezmoi/chezmoi.toml') ("destDir = `"$(& $form $configHome)`"`nsourceDir = `"$(& $form $source)`"`n" +
        "`n[data]`n  host = `"win`"`n")
    New-File (Join-Path $userHome '.local/state/chezmoi/chezmoi.boltdb') $(if ($Variant -ceq 'no-state') { '' } else { 'db' })
    New-File (Join-Path $userHome '.gitconfig') "[user]`n`tname = deployed`n"
    New-File (Join-Path $userHome 'Documents/PowerShell/profile.ps1') "# deployed profile`n"
    if ($Variant -ceq 'maintenance') { New-File (Join-Path $userHome '.config/dotfiles/maintenance') '' }
}

function Add-Run {
    # Queue one setup-host.ps1 run: exit code, stdout and stderr lines, and
    # an Action run before it returns (a file left in TEMP, say).
    param([int]$Code, [string[]]$Out = @(), [string[]]$Err = @(), [scriptblock]$Action = $null)
    $script:Runs.Enqueue(@{ Code = $Code; Out = (ConvertTo-StepText $Out); Err = (ConvertTo-StepText $Err); Action = $Action })
}

function New-FakeSnapshot([hashtable]$Entries) {
    $snapshot = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $Entries.Keys) { $snapshot[$key] = $Entries[$key] }
    return $snapshot
}

function Use-DryRun {
    # Run Action with the driver's machine-facing collaborators replaced in
    # this scope: no registry PATH rebuild; the elevation probe answers
    # $script:Elevated and the task list $script:TaskNames; each
    # setup-host.ps1 run takes the next of $script:Runs; each child process
    # plays the next mode of $script:ProcessModes (a deploy variant, or the
    # convergence check's converged, diff or exit-1 with $script:Managed as
    # the managed list); each HOME snapshot takes the next of
    # $script:Snapshots.
    param([scriptblock]$Action)
    function Update-E2EPath { }
    function Test-E2EElevated { return $script:Elevated }
    function Get-E2EScheduledTaskNames { return $script:TaskNames }
    function Get-E2ESnapshot {
        param([string]$Root, [string[]]$Prune = @())
        $script:SnapshotCalls.Add([pscustomobject]@{ Root = $Root; Prune = @($Prune) })
        if (-not $script:Snapshots.Count) { throw "an unexpected HOME snapshot of $Root" }
        return $script:Snapshots.Dequeue()
    }
    function Invoke-E2EPwsh {
        param([string]$Script, [string[]]$Arguments = @(), [int]$TimeoutSeconds, [hashtable]$Environment = @{})
        $script:PwshCalls.Add([pscustomobject]@{
                Script = $Script; Arguments = ($Arguments -join ' '); Timeout = $TimeoutSeconds; Environment = $Environment
            })
        if (-not $script:Runs.Count) { throw "an unexpected run of $Script $($Arguments -join ' ')" }
        $run = $script:Runs.Dequeue()
        if ($null -ne $run['Action']) { & $run['Action'] }
        [IO.File]::WriteAllText($E2E['StepOut'], $run['Out'], $Utf8)
        [IO.File]::WriteAllText($E2E['StepErr'], $run['Err'], $Utf8)
        Add-E2EText $E2E['StepLog'] "--- stub $Script $($Arguments -join ' '): exit $($run['Code'])`n"
        return $run['Code']
    }
    function Invoke-E2EProcess {
        param([string]$FilePath, [string[]]$ArgumentList = @(), [string]$WorkingDirectory, [string]$OutFile,
            [string]$ErrFile, [int]$TimeoutSeconds, [hashtable]$Environment = @{})
        $script:ProcessCalls.Add([pscustomobject]@{
                FilePath = $FilePath; Arguments = ($ArgumentList -join ' '); WorkingDirectory = $WorkingDirectory; Timeout = $TimeoutSeconds; Environment = $Environment
            })
        if (-not $script:ProcessModes.Count) { throw "an unexpected child process $FilePath $($ArgumentList -join ' ')" }
        $mode = $script:ProcessModes.Dequeue()
        $out = [Collections.Generic.List[string]]::new()
        $err = [Collections.Generic.List[string]]::new()
        $code = 0
        switch -CaseSensitive ($mode) {
            'backend' {
                if (-not $script:Runs.Count) { throw 'an unexpected installed CLI backend run' }
                $run = $script:Runs.Dequeue()
                if ($null -ne $run['Action']) { & $run['Action'] }
                [IO.File]::WriteAllText($OutFile, $run['Out'], $Utf8)
                [IO.File]::WriteAllText($ErrFile, $run['Err'], $Utf8)
                return $run['Code']
            }
            { $_ -cin @('clean', 'bad-config', 'maintenance', 'no-copy', 'no-state') } {
                Write-DeployState $mode
                $out.Add('Invoke-HomeDeploy: win deployed; copies of the files it replaced are in ~\.local\state\dotfiles-fresh-backup')
            }
            'refused' {
                $err.Add('Invoke-HomeDeploy: ~\.gitconfig is a link or not the expected kind of entry; inspect it and move it aside first')
                $code = 1
            }
            'converged' { $out.Add('--- managed'); $out.AddRange([string[]]$script:Managed) }
            'diff' { $out.Add('diff --git a/.gitconfig b/.gitconfig'); $out.Add('-[user]'); $code = 4 }
            'exit-1' { $err.Add('Invoke-HomeCz: chezmoi diff --exclude=dirs exited 1'); $code = 1 }
            default { throw "unknown process mode $mode" }
        }
        [IO.File]::WriteAllText($OutFile, (ConvertTo-StepText $out.ToArray()), $Utf8)
        [IO.File]::WriteAllText($ErrFile, (ConvertTo-StepText $err.ToArray()), $Utf8)
        return $code
    }
    & $Action
}

function Invoke-ApplyLoop {
    # Invoke-E2EApplyLoop under the stubs; it must return exactly one bool.
    $result = @(Use-DryRun { Invoke-E2EApplyLoop })
    Assert-True ($result.Count -eq 1 -and $result[0] -is [bool]) "the apply loop returned $($result.Count) objects: $($result -join ', ')"
    return $result[0]
}

function Get-ChildEnvironment {
    # What a child pwsh gets: no telemetry, update check or color, never the
    # variables that let run.ps1 bootstrap a home, and off Windows (where
    # pwsh keeps its caches under HOME and the XDG paths) a temp home.
    $environment = @{
        POWERSHELL_TELEMETRY_OPTOUT = '1'; POWERSHELL_UPDATECHECK = 'Off'; NO_COLOR = '1'
        GITHUB_ACTIONS = $null; E2E_NATIVE = $null
    }
    if (-not $IsWindows) {
        foreach ($name in @('HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME')) {
            $environment[$name] = Join-Path (Join-Path $testRoot 'pwsh-state') $name.ToLowerInvariant()
            [void][IO.Directory]::CreateDirectory($environment[$name])
        }
    }
    return $environment
}

function Invoke-Child {
    # A child pwsh through Invoke-E2EProcess, in the current step's files.
    param([string[]]$Arguments, [string]$WorkingDirectory, [int]$TimeoutSeconds = 120, [hashtable]$Environment = @{})
    $values = Get-ChildEnvironment
    foreach ($name in $Environment.Keys) { $values[$name] = $Environment[$name] }
    return Invoke-E2EProcess -FilePath $powerShell -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory `
        -OutFile $E2E['StepOut'] -ErrFile $E2E['StepErr'] -TimeoutSeconds $TimeoutSeconds -Environment $values
}

function New-PlantedDocument {
    # This checkout's docs/bootstrap.md with Text inserted just before the
    # closing fence of the Fresh Windows home by hand block (or, with
    # -AtStart, just after its opening line), or with that heading renamed
    # (-MoveHeading); returns the copy's path under Directory.
    param([string]$Directory, [string]$Text = '', [switch]$AtStart, [switch]$MoveHeading)
    $document = [IO.File]::ReadAllText((Join-Path $sourceRoot 'docs/bootstrap.md'))
    $heading = '#### Fresh Windows home by hand'
    $at = $document.IndexOf($heading, [StringComparison]::Ordinal)
    Assert-True ($at -ge 0) 'docs/bootstrap.md lacks the Fresh Windows home by hand heading'
    if ($MoveHeading) { $document = $document.Replace($heading, '#### Fresh Windows home, by hand') }
    else {
        $open = $document.IndexOf("``````powershell`n", $at, [StringComparison]::Ordinal)
        $close = $document.IndexOf("`n``````", $open + 1, [StringComparison]::Ordinal)
        Assert-True ($open -ge 0 -and $close -gt $open) 'docs/bootstrap.md lacks the Fresh Windows home by hand fence'
        $insertAt = if ($AtStart) { $open + "``````powershell`n".Length } else { $close + 1 }
        $document = $document.Insert($insertAt, "$Text`n")
    }
    $path = Join-Path $Directory 'bootstrap-planted.md'
    New-File $path $document
    return $path
}

try {
    Test-Case 'ConvertFrom-E2EBlocks keeps notes and commands per block, winget''s blank lines included (bug 1)' {
        $case = Reset-RunState
        $clone = Join-Path $case 'home/dotfiles'
        # As Get-E2ELines reads a step's .out: CRLF split, a trailing ''.
        $text = ConvertTo-StepText (Get-ApplyOutput -Clone $clone -Blocks (@('HW-deploy') + $Reminders) -Pending 'HW-deploy')
        $output = @($text -split '\r?\n')
        Assert-True (@($output | Where-Object { $_ -eq '' }).Count -ge 4) 'the fixture output lost its blank lines'
        $directory = Join-Path $case 'out/steps/01-apply-1.blocks'
        $blocks = @(ConvertFrom-E2EBlocks -Output $output -Directory $directory)
        Assert-Equal (Get-E2EBlocksSummary $blocks) "HW-deploy(judgment) $ReminderSummary" 'blocks in printed order'
        $notes = @(Get-BlockLines 'HW-deploy' $clone | Select-Object -Skip 1 | Select-Object -SkipLast 1)
        Assert-Lines $blocks[0].Lines $notes 'HW-deploy: its notes'
        Assert-Equal $blocks[2].Lines.Count 4 'HW-ssh-agent keeps its two notes and two commands'
        foreach ($block in $blocks) {
            Assert-True (-not @($block.Lines | Where-Object { $_.StartsWith('[dotfiles]') -or $_.StartsWith('HUMAN-') -or $_ -eq '' }).Count) "$($block.Id) holds a line from outside it"
        }
        Assert-Equal (Read-Utf8 (Join-Path $directory 'index')) ("1`tHW-deploy`tjudgment`n2`tHW-execution-policy`tjudgment`n" +
            "3`tHW-ssh-agent`tsudo`n4`tHW-wsl`tjudgment`n5`tHW-auth`tauth`n") 'the index file'
        Assert-Equal (Read-Utf8 (Join-Path $directory '1.block')) (($notes -join "`n") + "`n") '1.block'
        Assert-Equal @(Get-ChildItem -LiteralPath $directory -Filter '*.block').Count 5 'one <n>.block per block'

        $blank = @(ConvertFrom-E2EBlocks -Output @('', 'HUMAN-BEGIN HW-wsl judgment', '', 'wsl --install -d Ubuntu', '   ', 'HUMAN-END', '') -Directory (Join-Path $case 'blank'))
        Assert-Equal (Get-E2EBlocksSummary $blank) 'HW-wsl(judgment)' 'blank lines around a block'
        Assert-Lines $blank[0].Lines @('', 'wsl --install -d Ubuntu', '   ') 'blank lines inside a block are kept'

        $partialDirectory = Join-Path $case 'partial'
        $partial = @(ConvertFrom-E2EBlocks -Directory $partialDirectory -Output @(
                'HUMAN-END', 'HUMAN-BEGIN HW-deploy judgment', '# Follow Fresh Windows home by hand in docs/bootstrap.md from this checkout.', 'HUMAN-END',
                'HUMAN-BEGIN HW-wsl Judgment', 'wsl --install -d Ubuntu', 'HUMAN-END',
                'HUMAN-BEGIN HW-auth auth extra', 'codex login', 'HUMAN-END',
                'HUMAN-BEGIN HW-auth auth', 'gh auth login --git-protocol ssh'))
        Assert-Equal (Get-E2EBlocksSummary $partial) 'HW-deploy(judgment)' 'a stray HUMAN-END, malformed HUMAN-BEGIN lines and an unclosed block make no block'
        Assert-Equal (Read-Utf8 (Join-Path $partialDirectory 'index')) "1`tHW-deploy`tjudgment`n" 'the index lists closed blocks only'
        Assert-True (-not [IO.File]::Exists((Join-Path $partialDirectory '2.block'))) 'the unclosed block was saved'

        $none = @(ConvertFrom-E2EBlocks -Output @() -Directory (Join-Path $case 'none'))
        Assert-Equal $none.Count 0 'no output, no block'
        Assert-Equal (Read-Utf8 (Join-Path $case 'none/index')) "`n" 'an empty index'
    }

    Test-Case 'Get-E2EBlockPolicy: HW-deploy is the deploy step, the four reminders skip, HW-clone and every other (id, kind) fail (bug 2)' {
        $rows = @(
            'HW-deploy judgment deploy'
            'HW-execution-policy judgment skip', 'HW-ssh-agent sudo skip', 'HW-wsl judgment skip', 'HW-auth auth skip'
            'HW-clone gui fail', 'HW-clone judgment fail'
            # A known id with another kind.
            'HW-deploy sudo fail', 'HW-deploy inspect fail', 'HW-deploy gui fail', 'HW-ssh-agent judgment fail'
            'HW-auth judgment fail', 'HW-wsl gui fail', 'HW-execution-policy sudo fail', 'HW-auth sudo fail'
            # Case matters.
            'hw-deploy judgment fail', 'HW-deploy Judgment fail', 'HW-AUTH auth fail'
            # Unknown ids and kinds.
            'H7-deploy judgment fail', 'W1-winget judgment fail', 'HW-recovery judgment fail', 'HW-deploy alloc fail', 'HW-wsl chsh fail'
        )
        foreach ($row in $rows) {
            $id, $kind, $action = $row.Split(' ')
            Assert-Equal (Get-E2EBlockPolicy -Id $id -Kind $kind) $action "the policy of ${id}:$kind"
        }
    }

    Test-Case 'Get-E2ELoopNext: the verdict table of inside.sh, with HW-deploy as the deploy step' {
        $rows = @(
            '3|HW-deploy|0|0|done', '3|HW-deploy|0|1|rerun', '3|HW-deploy|1|0|blocks', '3|HW-deploy|1|1|blocks'
            '3|HW-clone HW-deploy|1|0|blocks', '3|HW-clone HW-deploy|0|0|stuck', '3|HW-clone HW-deploy|0|1|rerun'
            '3|H7-deploy|0|0|stuck', '3||0|0|stuck', '0||0|0|early', '0|HW-deploy|0|1|early'
            '1|x|0|0|error', '2|x|0|0|error', '124|x|0|0|timeout', '137|x|0|0|timeout'
        )
        foreach ($row in $rows) {
            $cells = $row.Split('|')
            $verdict = Get-E2ELoopNext -Code ([int]$cells[0]) -Pending $cells[1] -Actionable ($cells[2] -ceq '1') -Applied ($cells[3] -ceq '1')
            Assert-Equal $verdict $cells[4] "the verdict of [$row]"
        }
    }

    Test-Case 'Get-E2EDeployScript takes exactly the two Fresh Windows home by hand functions from docs/bootstrap.md and refuses anything else' {
        $case = Reset-RunState
        $deploy = Get-E2EDeployScript -Document (Join-Path $sourceRoot 'docs/bootstrap.md')
        Assert-Equal $deploy['Error'] '' 'the real fence was refused'
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput($deploy['Text'], [ref]$tokens, [ref]$parseErrors)
        Assert-Equal @($parseErrors).Count 0 'the fence parses'
        Assert-Lines @($ast.EndBlock.Statements | ForEach-Object { "$($_.GetType().Name) $($_.Name)" }) @(
            'FunctionDefinitionAst Invoke-HomeCz', 'FunctionDefinitionAst Invoke-HomeDeploy') 'two definitions and nothing else'
        Assert-True ($deploy['Text'].EndsWith("}`n")) 'the text ends with the last definition'
        $outside = 'a statement outside the Invoke-HomeCz and Invoke-HomeDeploy definitions in the fenced powershell block: '
        foreach ($refusal in @(
                @{ Text = 'Invoke-HomeDeploy -Role win'; AtStart = $false; Error = "${outside}Invoke-HomeDeploy -Role win" }
                @{ Text = 'function Invoke-Third { }'; AtStart = $false; Error = "${outside}function Invoke-Third { }" }
                @{ Text = 'function Invoke-HomeCz { }'; AtStart = $false; Error = "${outside}function Invoke-HomeCz { }" }
                @{ Text = '$env:CHEZMOI_SOURCE_DIR = ''C:\evil'''; AtStart = $false; Error = "$outside`$env:CHEZMOI_SOURCE_DIR = 'C:\evil'" }
                @{ Text = 'param()'; AtStart = $true; Error = "${outside}param()" })) {
            $directory = Join-Path $case ('planted-' + [Guid]::NewGuid().ToString('N'))
            $document = New-PlantedDocument -Directory $directory -Text $refusal['Text'] -AtStart:$refusal['AtStart']
            $planted = Get-E2EDeployScript -Document $document
            Assert-Equal $planted['Error'] $refusal['Error'] "the planted [$($refusal['Text'])]"
            Assert-Equal $planted['Text'] '' "a refused fence still returned text for [$($refusal['Text'])]"
        }
        $broken = Get-E2EDeployScript -Document (New-PlantedDocument -Directory (Join-Path $case 'broken') -Text 'function Broken {')
        Assert-True $broken['Error'].StartsWith('the fenced powershell block does not parse: ') "a parse error: $($broken['Error'])"
        $moved = Get-E2EDeployScript -Document (New-PlantedDocument -Directory (Join-Path $case 'moved') -MoveHeading)
        Assert-Equal $moved['Error'] 'no fenced powershell block after "Fresh Windows home by hand"' 'a moved heading'
    }

    Test-Case 'setup-host.ps1 -PrintManual: the blocks meet their policy rows, and HW-deploy holds notes only' {
        $case = Reset-RunState
        Start-E2EStep print-manual check:print-manual
        $code = Invoke-Child -Arguments @('-NoProfile', '-NonInteractive', '-File', (Join-Path $sourceRoot 'setup-host.ps1'), '-Host', 'win', '-PrintManual') `
            -WorkingDirectory $case
        Assert-Equal $code 0 "setup-host.ps1 -PrintManual exit code: $([IO.File]::ReadAllText($E2E['StepErr']))"
        $blocks = @(ConvertFrom-E2EBlocks -Output @(Get-E2ELines $E2E['StepOut']) -Directory (Join-Path $case 'manual.blocks'))
        Assert-Equal (Get-E2EBlocksSummary $blocks) "HW-clone(judgment) HW-deploy(judgment) $ReminderSummary" 'the blocks setup-host.ps1 prints'
        Assert-Equal (@($blocks | ForEach-Object { Get-E2EBlockPolicy -Id $_.Id -Kind $_.Kind }) -join ' ') 'fail deploy skip skip skip skip' 'their policies'
        Assert-Equal @($blocks[1].Lines | Where-Object { $_ -and -not $_.StartsWith('# ') }).Count 0 'HW-deploy holds a command line'
    }

    Test-Case 'Get-E2EPendingIds, Get-E2EFailureDetail, Get-E2EBlocksSummary and Get-E2EBlockText on setup-host output' {
        $pending = '[dotfiles] [warn] HUMAN steps pending: HW-clone HW-deploy; run the HUMAN blocks above, then rerun .\setup-host.ps1'
        Assert-Equal (Get-E2EPendingIds (@(Get-WingetLines) + @($pending, ''))) 'HW-clone HW-deploy' 'the pending ids'
        Assert-Equal (Get-E2EPendingIds (@(Get-WingetLines) + @('') + @($pending.Replace('HW-clone ', '')))) 'HW-deploy' 'pending on the stderr half of the lines'
        Assert-Equal (Get-E2EPendingIds @(Get-WingetLines)) '' 'nothing pending'
        Assert-Equal (Get-E2EPendingIds @()) '' 'no lines'

        $winget = '[dotfiles] [error] W1-winget: winget exited 0x8A150046 (source agreements were not accepted) (docs/bootstrap.md W1-winget)'
        Assert-Equal (Get-E2EFailureDetail -Output (@(Get-WingetLines) + @($winget, '')) -Errors @('', '  ')) $winget 'the [error] line of stdout'
        Assert-Equal (Get-E2EFailureDetail -Output @($winget) -Errors @("[dotfiles] [error] second`twith a tab")) "$winget | [dotfiles] [error] second with a tab" '[error] lines of stdout, then stderr'
        Assert-Equal (Get-E2EFailureDetail -Output @(Get-WingetLines) -Errors @('Exception: first', 'Exception: last', '', '   ')) 'Exception: last' 'the last non-blank stderr line'
        Assert-Equal (Get-E2EFailureDetail -Output @('first', 'last', '') -Errors @('', ' ')) 'last' 'the last non-blank stdout line'
        Assert-Equal (Get-E2EFailureDetail -Output @('') -Errors @()) 'no output' 'nothing to report'
        Assert-Equal (Get-E2EFailureDetail -Output @('[error] ' + ('e' * 500))) ('[error] ' + ('e' * 392) + '...') 'a detail is cut at 400 characters'

        $blocks = @([pscustomobject]@{ Id = 'HW-deploy'; Kind = 'judgment'; Lines = @('# note', '# another') }
            [pscustomobject]@{ Id = 'HW-auth'; Kind = 'auth'; Lines = @('gh auth login --git-protocol ssh') })
        Assert-Equal (Get-E2EBlocksSummary $blocks) 'HW-deploy(judgment) HW-auth(auth)' 'id(kind) per block'
        Assert-Equal (Get-E2EBlocksSummary @()) '' 'no block'
        Assert-Equal (Get-E2EBlockText $blocks[0]) '# note | # another' 'a block as one detail line'
    }

    Test-Case 'Get-E2ESnapshot and Compare-E2ESnapshot: added, removed, changed; a pruned subtree and the top-level ntuser hives ignored' {
        $case = Reset-RunState
        $root = Join-Path $case 'home'
        $epoch = [DateTime]::new(2026, 1, 2, 3, 4, 5, [DateTimeKind]::Utc)
        $ticks = $epoch.Ticks
        $a = Get-Path $root 'a.txt'
        $b = Get-Path $root 'sub/b.txt'
        $deepHive = Get-Path $root 'sub/NTUSER.DAT'
        New-File $a 'one' $epoch
        New-File $b 'two' $epoch
        New-File $deepHive 'user' $epoch
        New-File (Join-Path $root 'work/_temp/runner.txt') 'checkout' $epoch
        New-File (Join-Path $root 'NTUSER.DAT') 'hive' $epoch
        New-File (Join-Path $root 'ntuser.dat.LOG1') 'hive log' $epoch
        [void][IO.Directory]::CreateDirectory((Join-Path $root 'empty'))
        $prune = @((Join-Path $root 'work'))
        $before = Get-E2ESnapshot -Root $root -Prune $prune
        $keys = [string[]]@($before.Keys | ForEach-Object { $_.Substring($root.Length + 1).Replace('\', '/') })
        [Array]::Sort($keys, [StringComparer]::Ordinal)
        Assert-Lines $keys @('a.txt', 'empty', 'sub', 'sub/NTUSER.DAT', 'sub/b.txt') 'the entries: no pruned subtree, no top-level hive'
        Assert-Equal $before[$a] "3|$ticks" 'a file: size and modification time'
        Assert-Equal $before[(Get-Path $root 'sub')] 'dir' 'a directory: by name only'

        New-File $a 'one more' $epoch.AddSeconds(1)
        Remove-Item -LiteralPath $b
        $c = Get-Path $root 'c.txt'
        New-File $c 'new' $epoch
        New-File (Join-Path $root 'work/_temp/new.txt') 'pruned' $epoch
        New-File (Join-Path $root 'ntuser.dat.LOG2') 'hive log' $epoch
        [IO.File]::SetLastWriteTimeUtc($deepHive, $epoch.AddSeconds(2))
        [IO.Directory]::SetLastWriteTimeUtc((Join-Path $root 'empty'), $epoch.AddDays(1))
        $after = Get-E2ESnapshot -Root $root -Prune $prune
        Assert-Lines @(Compare-E2ESnapshot -Before $before -After $after) @(
            "added $c"
            "changed $a (3|$ticks -> 8|$($epoch.AddSeconds(1).Ticks))"
            "changed $deepHive (4|$ticks -> 4|$($epoch.AddSeconds(2).Ticks))"
            "removed $b"
        ) 'the differences, sorted; a same-size rewrite counts, a directory time does not'
        Assert-Equal @(Compare-E2ESnapshot -Before $after -After (Get-E2ESnapshot -Root $root -Prune $prune)).Count 0 'an unchanged tree'
    }

    Test-Case 'Get-E2ESnapshot records links by their target and never follows them' {
        $case = Reset-RunState
        $root = Join-Path $case 'home'
        $target = Join-Path $root 'dotfiles/home/dot_gitconfig'
        New-File $target '[user]'
        $fileLink = Join-Path $root '.gitconfig'
        $loop = Join-Path $root 'Application Data'
        try {
            [void][IO.File]::CreateSymbolicLink($fileLink, $target)
            [void][IO.Directory]::CreateSymbolicLink($loop, $root)
        }
        catch {
            Skip-Assertion "symbolic links cannot be created here ($($_.Exception.Message)); links not checked."
            return
        }
        try {
            $snapshot = Get-E2ESnapshot -Root $root
            Assert-Equal $snapshot[$fileLink] "link|$target" 'a file link: its target'
            Assert-Equal $snapshot[$loop] "dir-link|$root" 'a directory link: its target'
            $inside = @($snapshot.Keys | Where-Object { $_.StartsWith($loop + [IO.Path]::DirectorySeparatorChar) })
            Assert-Equal $inside.Count 0 'the looping directory link was followed'
            [IO.File]::Delete($fileLink)
            $relative = [IO.Path]::Combine('dotfiles', 'home', 'dot_gitconfig')
            [void][IO.File]::CreateSymbolicLink($fileLink, $relative)
            Assert-Lines @(Compare-E2ESnapshot -Before $snapshot -After (Get-E2ESnapshot -Root $root)) @(
                "changed $fileLink (link|$target -> link|$relative)") 'a retargeted link'
        }
        finally { [IO.Directory]::Delete($loop) }
    }

    Test-Case 'Get-E2ESnapshot marks a directory it cannot enumerate unreadable' {
        if ($IsWindows) { Skip-Assertion 'an unreadable directory is made with POSIX modes; not checked on Windows.'; return }
        $case = Reset-RunState
        $root = Join-Path $case 'home'
        $locked = Join-Path $root 'locked'
        New-File (Join-Path $locked 'secret') 'x'
        [IO.File]::SetUnixFileMode($locked, [IO.UnixFileMode]::None)
        try {
            $readable = $true
            try { [void]@([IO.Directory]::EnumerateFileSystemEntries($locked)) } catch { $readable = $false }
            if ($readable) { Skip-Assertion 'this user reads a mode-000 directory (root); unreadable entries not checked.'; return }
            $snapshot = Get-E2ESnapshot -Root $root
            Assert-Equal $snapshot[$locked] 'unreadable' 'the locked directory'
            Assert-Equal @($snapshot.Keys | Where-Object { $_.StartsWith($locked + '/') }).Count 0 'an entry below the locked directory'
        }
        finally { [IO.File]::SetUnixFileMode($locked, [IO.UnixFileMode]'UserRead, UserWrite, UserExecute') }
    }

    Test-Case 'Test-E2EPruned and Get-E2EPruneList: pruned prefixes, top-level ntuser hives, E2E_SNAPSHOT_PRUNE' {
        # The prefix rule compares strings, so Windows paths work everywhere.
        $userHome = 'C:\Users\runneradmin'
        $prune = @("$userHome\work", "$userHome\AppData\Local\Temp")
        foreach ($row in @(
                @("$userHome\work", $true), @("$userHome\work\_temp\x.txt", $true), @('c:\USERS\runneradmin\WORK\x', $true),
                @("$userHome\AppData\Local\Temp\pwsh.tmp", $true), @("$userHome\workshop", $false),
                @("$userHome\AppData\Local\TempState\x", $false), @("$userHome\Documents\x", $false))) {
            Assert-Equal (Test-E2EPruned -Path $row[0] -Root $userHome -Prune $prune) $row[1] "pruned: $($row[0])"
        }
        $root = Join-Path $testRoot 'hive-home'
        Assert-True (Test-E2EPruned -Path (Join-Path $root 'NTUSER.DAT') -Root $root) 'NTUSER.DAT at the top'
        Assert-True (Test-E2EPruned -Path (Join-Path $root 'ntuser.dat.LOG1') -Root $root) 'a hive log at the top'
        Assert-True (Test-E2EPruned -Path (Join-Path $root 'ntuser.ini') -Root ($root + [IO.Path]::DirectorySeparatorChar)) 'a root with a trailing separator'
        Assert-True (-not (Test-E2EPruned -Path (Join-Path $root 'AppData/NTUSER.DAT') -Root $root)) 'a hive name below the top'
        Assert-True (-not (Test-E2EPruned -Path (Join-Path $root 'user.dat') -Root $root)) 'another top-level file'
        if ($IsWindows) {
            Assert-True (Test-E2EPruned -Path "$userHome\NTUSER.DAT" -Root $userHome) 'the runner''s hive'
            Assert-True (-not (Test-E2EPruned -Path "$userHome\AppData\Local\Microsoft\Windows\UsrClass.dat" -Root $userHome)) 'a deeper hive'
        }
        else {
            Skip-Assertion 'drive-letter hive paths (C:\Users\runneradmin\NTUSER.DAT) split only on Windows.'
        }

        [void](Reset-RunState)
        $defaults = @('work', 'AppData\Local\Temp', 'AppData\Local\Microsoft\PowerShell', 'AppData\Local\Microsoft\Windows',
            'AppData\Local\Packages', 'AppData\Local\ConnectedDevicesPlatform', 'dotfiles\.git') |
            ForEach-Object { [IO.Path]::GetFullPath((Join-Path $HOME $_)) }
        $extra = Join-Path $testRoot 'extra-prune'
        Use-Environment @{ E2E_SNAPSHOT_PRUNE = $null } {
            Assert-Lines @(Get-E2EPruneList) (@($defaults) + @($E2E['Out'])) 'the default prune list and the out dir'
        }
        Use-Environment @{ E2E_SNAPSHOT_PRUNE = " AppData\Roaming\Code ; ;$extra$([IO.Path]::DirectorySeparatorChar)" } {
            Assert-Lines @(Get-E2EPruneList) (@($defaults) + @($E2E['Out'], [IO.Path]::GetFullPath((Join-Path $HOME 'AppData\Roaming\Code')), $extra)) `
                'E2E_SNAPSHOT_PRUNE: trimmed, relative to HOME or absolute, empty entries dropped'
        }
    }

    Test-Case 'Test-E2ENoted and Stop-E2ENoWrite: CryptnetUrlCache and TokenBroker cache differences are noted, every other HOME difference fails (bug 4)' {
        # The driver compares Windows paths ('\' below the noted root); off
        # Windows $HOME's own separator is '/', so the entries below the
        # root are spelled the Windows way on every platform.
        $noted = [IO.Path]::Combine($HOME, 'AppData', 'LocalLow', 'Microsoft', 'CryptnetUrlCache')
        $content = "$noted\Content\77EC63BDA74BD0D0E0426DC8F8008506"
        $metadata = "$noted\MetaData\77EC63BDA74BD0D0E0426DC8F8008506"
        $gitconfig = [IO.Path]::Combine($HOME, '.gitconfig')
        $profileFile = [IO.Path]::Combine($HOME, 'Documents', 'PowerShell', 'profile.ps1')
        Assert-True (Test-E2ENoted "added $content") 'an added cache entry'
        Assert-True (Test-E2ENoted "changed $metadata (620|1 -> 620|2)") 'a changed cache entry'
        Assert-True (Test-E2ENoted "removed $content") 'a removed cache entry'
        Assert-True (Test-E2ENoted "added $($content.ToUpperInvariant())") 'a cache entry in another case'
        Assert-True (-not (Test-E2ENoted "added ${noted}Old\Content\x")) 'a sibling sharing the prefix'
        $broker = [IO.Path]::Combine($HOME, 'AppData', 'Local', 'Microsoft', 'TokenBroker', 'Cache')
        Assert-True (Test-E2ENoted "changed $broker\01c5cb21ab1d4fd56e65159d6c36cd5db1f647e1.tbres (2750|1 -> 2750|2)") 'a token broker cache entry'
        Assert-True (-not (Test-E2ENoted "added ${broker}Old\x")) 'a sibling of the token broker cache sharing its prefix'
        Assert-True (-not (Test-E2ENoted "added $([IO.Path]::Combine($HOME, 'AppData', 'Local', 'Microsoft', 'TokenBroker', 'Accounts'))\x")) 'the token broker outside its cache'
        Assert-True (-not (Test-E2ENoted "added $profileFile")) 'a HOME file'
        Assert-True (-not (Test-E2ENoted "changed $gitconfig (11|1 -> 12|3)")) 'the deployed .gitconfig'

        [void](Reset-RunState)
        $script:Snapshots.Clear()
        $script:SnapshotCalls.Clear()
        $before = New-FakeSnapshot @{ $content = '1024|1'; $metadata = '620|1'; $gitconfig = '1024|1' }
        Use-DryRun {
            $script:Snapshots.Enqueue($before)
            Start-E2ENoWrite check-nowrite
            $temp = Join-Path $E2E['Out'] 'tmp/check-nowrite'
            Assert-Equal $E2E['NoWriteTemp'] $temp 'the no-write TEMP'
            Assert-Equal @([IO.Directory]::EnumerateFileSystemEntries($temp)).Count 0 'a fresh TEMP'
            $environment = Get-E2ENoWriteEnvironment
            Assert-Equal "$($environment['TEMP'])|$($environment['TMP'])" "$temp|$temp" 'TEMP and TMP of the child'
            Assert-Equal $script:SnapshotCalls[0].Root $HOME 'the snapshot root'
            Assert-True ($script:SnapshotCalls[0].Prune -contains $E2E['Out']) 'the out dir is not pruned'

            $script:Snapshots.Enqueue((New-FakeSnapshot @{ $content = '2048|2'; $metadata = '620|1'; "$noted\Content\NEW" = '512|2'; $gitconfig = '1024|1' }))
            Assert-Equal (Stop-E2ENoWrite check-nowrite) '' 'CryptnetUrlCache differences alone fail the step'
            Assert-Equal (Read-Utf8 (Join-Path $E2E['Out'] 'snapshots/check-nowrite.diff')) (
                "noted added $noted\Content\NEW`nnoted changed $content (1024|1 -> 2048|2)`n") 'the diff keeps the noted differences'
            Assert-True ($null -eq $E2E['NoWriteHome']) 'the before-image was kept'

            $script:Snapshots.Enqueue($before)
            Start-E2ENoWrite second-apply
            [IO.File]::WriteAllText((Join-Path $E2E['NoWriteTemp'] 'pwsh-1234.tmp'), 'x')
            $script:Snapshots.Enqueue((New-FakeSnapshot @{ $content = '2048|2'; $gitconfig = '1543|2'; $profileFile = '900|2' }))
            # Sorted as Compare-E2ESnapshot sorts (the culture decides where
            # .gitconfig falls against AppData); the two cache lines are noted.
            $cacheLines = @("changed $content (1024|1 -> 2048|2)", "removed $metadata")
            $sorted = @(@("added $profileFile", "changed $gitconfig (1024|1 -> 1543|2)") + $cacheLines | Sort-Object)
            $real = @($sorted | Where-Object { $cacheLines -cnotcontains $_ })
            Assert-Equal (Stop-E2ENoWrite second-apply) (
                "TEMP not empty: pwsh-1234.tmp; HOME written (2 difference(s)): $(ConvertTo-E2EOneLine ($real -join "`n") 300)") 'the real differences and TEMP'
            Assert-Equal (Read-Utf8 (Join-Path $E2E['Out'] 'snapshots/second-apply.diff')) (
                (@($sorted | ForEach-Object { if ($cacheLines -ccontains $_) { "noted $_" } else { $_ } }) -join "`n") + "`n") 'noted and real in one diff'
        }
    }

    Test-Case 'summary.tsv: tab-separated rows in UTF-8 without BOM, LF endings, the counters, step files, the timeline' {
        [void](Reset-RunState)
        Write-E2ENote winget-bootstrap "deviation: winget was not on the image;`tbootstrapped`nwith Repair-WinGetPackageManager"
        Skip-E2EStep HW-wsl ''
        Write-E2EFailure HW-clone ('x' * 700)
        Start-E2EStep doctor-final check:doctor-final
        $prefix = Join-Path $E2E['Out'] 'steps/04-doctor-final'
        Assert-Equal "$($E2E['StepLog'])|$($E2E['StepOut'])|$($E2E['StepErr'])" "$prefix.log|$prefix.out|$prefix.err" 'the step files'
        Assert-Equal (Read-Utf8 "$prefix.log") '' 'a fresh step log'
        Assert-Equal $env:E2E_PHASE 'check:doctor-final' 'E2E_PHASE during the step'
        Complete-E2EStep pass 'exit 0 with the registry PATH'
        Assert-Equal $env:E2E_PHASE '-' 'E2E_PHASE after the step'

        $text = Read-Utf8 (Join-Path $E2E['Out'] 'summary.tsv')
        Assert-True $text.EndsWith("`n") 'summary.tsv does not end in a newline'
        $rows = @(Get-SummaryRows)
        Assert-Equal (Get-RowShape $rows) 'winget-bootstrap:note HW-wsl:skip HW-clone:fail doctor-final:pass' 'the rows'
        Assert-Equal ($rows | ForEach-Object { $_.N }) '1 2 3 4' 'the row numbers'
        Assert-Equal $text.Split("`n")[0] "1`twinget-bootstrap`tnote`t0`tdeviation: winget was not on the image; bootstrapped | with Repair-WinGetPackageManager" 'tabs and line breaks flattened'
        Assert-Equal $text.Split("`n")[1] "2`tHW-wsl`tskip`t0`t" 'an empty detail'
        Assert-Equal $rows[2].Detail (('x' * 600) + '...') 'a detail is cut at 600 characters'
        Assert-True ($rows[3].Seconds -cmatch '^[0-9]+$' -and $rows[3].Detail -ceq 'exit 0 with the registry PATH') "the step row: $($text.Split("`n")[3])"
        Assert-Equal "$($E2E['Passes']) $($E2E['Fails']) $($E2E['Skips'])" '1 1 1' 'pass, fail and skip counters (a note counts as none)'
        Assert-True ($script:Console[-1] -cmatch '^04 doctor-final +pass +[0-9]+s  exit 0 with the registry PATH$') "the console line: $($script:Console[-1])"
        $timeline = @(Get-E2ELines (Join-Path $E2E['Out'] 'log/timeline') | Where-Object { $_ })
        Assert-Equal (@($timeline | ForEach-Object { $cells = $_.Split("`t"); Assert-True ($cells[0] -cmatch '^[0-9]+$') "timeline epoch: $_"; "$($cells[1]) $($cells[2])" }) -join ', ') `
            'begin check:doctor-final, end check:doctor-final' 'the timeline'
    }

    Test-Case 'Complete-E2EStep fails a passing step that left the clone dirty, quoting the diff, and stops on a broken step' {
        $case = Reset-RunState
        $clone = Join-Path $case 'home/dotfiles'
        New-TempClone $clone
        $E2E['Clone'] = $clone
        Start-E2EStep second-apply setup:second-apply
        Complete-E2EStep pass 'exit 0, nothing applied, HOME untouched'
        [IO.File]::WriteAllText((Join-Path $clone 'home/dot_gitconfig'), "[user]`n`tname = changed`n")
        Start-E2EStep login-shell check:login-shell
        Complete-E2EStep pass 'exit 0, silent'
        $dirtyLog = [IO.File]::ReadAllText($E2E['StepLog'])
        Start-E2EStep doctor-final check:doctor-final
        $E2E['Broken'] = 'doctor-final'
        Complete-E2EStep fail 'exit 1'
        $rows = @(Get-SummaryRows)
        Assert-Equal (Get-RowShape $rows) 'second-apply:pass login-shell:fail doctor-final:fail' 'the rows'
        Assert-Equal $rows[1].Detail 'exit 0, silent; clone not clean: M home/dot_gitconfig' 'the dirty clone in the detail'
        Assert-True ($dirtyLog.Contains('--- git diff of the clone (exit 0)') -and $dirtyLog.Contains("+`tname = changed") -and $dirtyLog.Contains("--- end`n")) "the step log lacks the diff: $dirtyLog"
        Assert-Equal $rows[2].Detail 'exit 1' 'a failing step is not checked again'
        Assert-True (-not [IO.File]::ReadAllText($E2E['StepLog']).Contains('git diff')) 'a failing step quoted the diff'
        Assert-Equal $script:Console[-1] 'the main flow stops after doctor-final' 'the stop line'
        $E2E['Clone'] = Join-Path $case 'not-cloned'
        Start-E2EStep missing-clone check:missing-clone
        Complete-E2EStep pass 'exit 0'
        Assert-Equal @(Get-SummaryRows)[-1].Status 'pass' 'a clone that does not exist yet is not checked'
    }

    Test-Case 'Get-E2ETsvCounts and Get-E2EProblemLines read doctor output' {
        $case = Reset-RunState
        $tsv = Join-Path $case 'doctor.tsv'
        [IO.File]::WriteAllText($tsv, "status`tid`ttier`tdetail`tfix`r`nok`tgit`tcore`t2.51.0`t-`r`nmissing`tfzf`tcli`tnot found`tW1-winget`r`n" +
            "missing`tbat`tcli`tnot found`tW1-winget`r`nwarn`tnode`tai`t20.0.0 < 22`tW1-winget`r`n`r`n")
        Assert-Equal (Get-E2ETsvCounts $tsv) 'ok=1 missing=2 warn=1 ' 'status counts of a -Tsv report'
        $log = Join-Path $case 'doctor.out'
        [IO.File]::WriteAllText($log, ((@('[dotfiles] [ok] git 2.51.0') + @(1..6 | ForEach-Object { "[dotfiles] [warn] tool $_ below its floor" }) +
                    @('[dotfiles] [error] chezmoi-config: there is no ~/.config/chezmoi/chezmoi.toml')) -join "`r`n"))
        Assert-Equal (Get-E2EProblemLines $log) (@(1..5 | ForEach-Object { "[dotfiles] [warn] tool $_ below its floor" }) -join ' | ') 'the first five problem lines'
    }

    Test-Case 'Invoke-E2EProcess: closed stdin, the child''s own environment, both streams logged, 124 after the timeout' {
        $case = Reset-RunState
        $work = Join-Path $case 'work dir'
        [void][IO.Directory]::CreateDirectory($work)
        Start-E2EStep probe check:probe
        $command = '$in = [Console]::In.ReadToEnd(); "stdin=[$in]"; "set=[$env:E2E_TEST_SET]"; "removed=[$env:E2E_TEST_REMOVED]"; ' +
            '"cwd=[$((Get-Location).Path)]"; [Console]::Error.WriteLine(''to stderr''); exit 7'
        $code = Use-Environment @{ E2E_TEST_REMOVED = 'parent value' } {
            Invoke-Child -Arguments @('-NoProfile', '-NonInteractive', '-Command', $command) -WorkingDirectory $work `
                -Environment @{ E2E_TEST_SET = 'child value'; E2E_TEST_REMOVED = $null }
        }
        Assert-Equal $code 7 "the child's exit code: $([IO.File]::ReadAllText($E2E['StepErr']))"
        $lines = @(Get-E2ELines $E2E['StepOut'] | Where-Object { $_ })
        Assert-Lines $lines[0..2] @('stdin=[]', 'set=[child value]', 'removed=[]') 'stdin closed, a variable set and one removed for the child'
        Assert-True ($lines[3] -like '*work dir]') "the child's working directory: $($lines[3])"
        Assert-Equal (Get-E2ELastLine $E2E['StepErr']) 'to stderr' 'stderr'
        $log = [IO.File]::ReadAllText($E2E['StepLog'])
        $header = "--- `$ $powerShell -NoProfile -NonInteractive -Command $command`n--- cwd $work, phase check:probe, exit 7`nstdin=[]"
        Assert-True $log.StartsWith($header) "the step log header: $log"
        Assert-True $log.EndsWith("`n--- stderr`nto stderr`n--- end`n") "the step log tail: $log"

        $clock = [Diagnostics.Stopwatch]::StartNew()
        $code = Invoke-Child -Arguments @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 60') -WorkingDirectory $work -TimeoutSeconds 2
        Assert-Equal $code 124 'a child past its timeout'
        Assert-True ($clock.Elapsed.TotalSeconds -lt 50) "the timed-out child was not killed ($($clock.Elapsed.TotalSeconds)s)"
        Assert-True ([IO.File]::ReadAllText($E2E['StepLog']).Contains(', exit 124')) 'the step log lacks exit 124'
    }

    Test-Case 'run.ps1 refuses arguments, and any host but Windows, with exit 2 before anything else' {
        $case = Reset-RunState
        Start-E2EStep run-ps1 check:run-ps1
        $run = Join-Path $PSScriptRoot 'e2e/run.ps1'
        $code = Invoke-Child -Arguments @('-NoProfile', '-NonInteractive', '-File', $run, 'extra') -WorkingDirectory $case
        Assert-Equal $code 2 'run.ps1 with an argument'
        Assert-Equal (Get-E2ELastLine $E2E['StepOut']) ('[e2e] run.ps1 takes no arguments; it reads E2E_SRC, E2E_REV, E2E_OUT, ' +
            'E2E_ALLOW_DIRTY and E2E_SNAPSHOT_PRUNE') 'the argument refusal'
        if (-not $IsWindows) {
            $code = Invoke-Child -Arguments @('-NoProfile', '-NonInteractive', '-File', $run) -WorkingDirectory $case
            Assert-Equal $code 2 'run.ps1 off Windows'
            Assert-Equal (Get-E2ELastLine $E2E['StepOut']) '[e2e] run.ps1 drives native Windows; every other host runs through tests/e2e/run.sh' 'the host refusal'
        }
        else {
            Skip-Assertion 'run.ps1 without arguments is not started on Windows, where only its GITHUB_ACTIONS/E2E_NATIVE gate would stand before the real home.'
        }
        Assert-Equal @(Get-ChildItem -LiteralPath $case -Force | Where-Object { $_.Name -ne 'out' }).Count 0 'run.ps1 wrote beside its working directory'
    }

    Test-Case 'apply loop dry run: a run that applies the winget steps and chezmoi, then a run with only HW-deploy left ends the loop' {
        $clone = New-DryRun
        Add-Run 3 (Get-ApplyOutput -Clone $clone -Blocks (@('HW-deploy') + $Reminders) -Pending 'HW-deploy')
        Add-Run 3 (Get-ApplyOutput -Clone $clone -Blocks (@('HW-deploy') + $Reminders) -Pending 'HW-deploy' -Done)
        Assert-True (Invoke-ApplyLoop) "the apply loop failed:`n$(Get-SummaryText)"
        $rows = @(Get-SummaryRows)
        Assert-Equal (Get-RowShape $rows) 'apply-1:pass apply-2:pass HW-execution-policy:skip HW-ssh-agent:skip HW-wsl:skip HW-auth:skip' 'the rows'
        Assert-Equal $rows[0].Detail 'exit 3; applied 3 step(s); pending: HW-deploy' 'apply-1 reruns'
        Assert-Equal $rows[1].Detail "exit 3 after 2 run(s); only HW-deploy pending; blocks: HW-deploy(judgment) $ReminderSummary" 'apply-2 ends the loop'
        Assert-Equal $rows[3].Detail ('sudo block left to the person: # Elevated PowerShell (Run as administrator): | Set-Service -Name ssh-agent ' +
            '-StartupType Automatic | Start-Service -Name ssh-agent | # Then, as yourself, once HW-auth has created the key: ssh-add $HOME\.ssh\id_ed25519') 'a reminder'
        Assert-Equal "$($E2E['Passes']) $($E2E['Fails']) $($E2E['Skips']) [$($E2E['Broken'])]" '2 0 4 []' 'counters and Broken'
        Assert-Equal (@($script:PwshCalls | ForEach-Object { "$($_.Script) $($_.Arguments) $($_.Timeout)" }) -join '; ') `
            'dotfiles.ps1 setup --host win --yes 3600; dotfiles.ps1 setup --host win --yes 3600' 'the setup-host.ps1 runs, without a mode flag'
        Assert-Equal $script:ProcessCalls.Count 0 'no block line runs'
        Assert-Equal "$($E2E['DeployBlock'].Id) $($E2E['DeployBlock'].Kind)" 'HW-deploy judgment' 'the deploy block is kept'
        Assert-Lines @($E2E['DeployBlock'].Lines) @(Get-BlockLines 'HW-deploy' $clone | Select-Object -Skip 1 | Select-Object -SkipLast 1) 'its notes'
        $blocks = Join-Path $E2E['Out'] 'steps/02-apply-2.blocks'
        Assert-Equal (Read-Utf8 (Join-Path $blocks 'index')).Split("`n")[0] "1`tHW-deploy`tjudgment" 'apply-2''s blocks were saved'
        $phases = @(Get-E2ELines (Join-Path $E2E['Out'] 'log/timeline') | Where-Object { $_ } | ForEach-Object { $_.Split("`t", 2)[1].Replace("`t", ' ') })
        Assert-Equal ($phases -join ', ') 'begin setup:apply-1, end setup:apply-1, begin setup:apply-2, end setup:apply-2' 'the timeline'
    }

    Test-Case 'Invoke-E2EBlocks records each reminder once across runs and leaves the deploy block alone' {
        $clone = New-DryRun
        $blocks = @(ConvertFrom-E2EBlocks -Output (Get-ApplyOutput -Clone $clone -Blocks (@('HW-deploy') + $Reminders)) -Directory (Join-Path $E2E['Out'] 'reminders'))
        Assert-True (Invoke-E2EBlocks -Blocks $blocks) 'the first run of reminders'
        Assert-True (Invoke-E2EBlocks -Blocks $blocks) 'the second run of reminders'
        Assert-Equal (Get-RowShape @(Get-SummaryRows)) 'HW-execution-policy:skip HW-ssh-agent:skip HW-wsl:skip HW-auth:skip' 'one skip row each'
        Assert-True (Invoke-E2EBlocks -Blocks @()) 'no blocks'
        Assert-Equal "$($E2E['Broken']) $($script:ProcessCalls.Count)" ' 0' 'nothing broke and nothing ran'
    }

    Test-Case 'apply loop dry run: exit 0 before the first apply fails, since a fresh home cannot have HW-deploy done' {
        $clone = New-DryRun
        Add-Run 0 (Get-ApplyOutput -Clone $clone -Blocks $Reminders -Done)
        Add-Run 3 (Get-ApplyOutput -Clone $clone -Blocks (@('HW-deploy') + $Reminders) -Pending 'HW-deploy' -Done)
        Assert-True (-not (Invoke-ApplyLoop)) 'an exit 0 passed'
        Assert-Equal (Get-RowShape @(Get-SummaryRows)) 'apply-1:fail' 'the rows'
        Assert-Equal @(Get-SummaryRows)[0].Detail 'exit 0 before the first apply: HW-deploy was already done on a fresh home' 'the verdict'
        Assert-Equal "$($E2E['Broken']) $($script:Runs.Count)" 'apply-1 1' 'Broken and runs left'
    }

    Test-Case 'apply loop dry run: a pending HW-clone fails the run before anything else, wherever it is printed (bug 2)' {
        foreach ($order in @(@('HW-clone', 'HW-deploy'), @('HW-deploy', 'HW-clone'))) {
            $clone = New-DryRun
            Add-Run 3 (Get-ApplyOutput -Clone $clone -Blocks (@($order) + $Reminders) -Pending 'HW-clone HW-deploy')
            Add-Run 3 (Get-ApplyOutput -Clone $clone -Blocks (@('HW-deploy') + $Reminders) -Pending 'HW-deploy' -Done)
            Assert-True (-not (Invoke-ApplyLoop)) "$($order -join ', '): the apply loop passed"
            $rows = @(Get-SummaryRows)
            Assert-Equal (Get-RowShape $rows) 'apply-1:pass HW-clone:fail' "$($order -join ', '): the rows"
            Assert-Equal $rows[0].Detail "exit 3; blocks: $($order[0])(judgment) $($order[1])(judgment) $ReminderSummary; pending: HW-clone HW-deploy" `
                "$($order -join ', '): apply-1"
            Assert-True $rows[1].Detail.StartsWith('judgment block the harness must not run: # This checkout has no .git') `
                "$($order -join ', '): $($rows[1].Detail)"
            Assert-Equal "$($E2E['Broken']) $($script:ProcessCalls.Count) $($script:PwshCalls.Count)" 'HW-clone 0 1' "$($order -join ', '): Broken, child processes, setup-host runs"
        }
    }

    Test-Case 'apply loop dry run: no progress, a missing HW-deploy block, exit 1, exit 2 and a timeout fail with what setup-host reported' {
        $clone = New-DryRun
        Add-Run 3 (Get-ApplyOutput -Clone $clone -Blocks (@('HW-deploy') + $Reminders) -Pending 'HW-clone HW-deploy' -Done)
        Assert-True (-not (Invoke-ApplyLoop)) 'exit 3 with nothing to do and nothing applied passed'
        Assert-Equal (Get-SummaryText) ("1`tapply-1`tfail`t$(@(Get-SummaryRows)[0].Seconds)`tno progress: exit 3 with no block the harness may run " +
            "and nothing applied (pending: HW-clone HW-deploy; blocks: HW-deploy(judgment) $ReminderSummary)`n") 'no progress, no skip rows'
        Assert-Equal "$($E2E['Broken']) $($script:ProcessCalls.Count)" 'apply-1 0' 'Broken and child processes'

        $clone = New-DryRun
        Add-Run 3 (Get-ApplyOutput -Clone $clone -Blocks $Reminders -Pending 'HW-deploy' -Done)
        Assert-True (-not (Invoke-ApplyLoop)) 'only HW-deploy pending without its block passed'
        Assert-Equal @(Get-SummaryRows)[0].Detail "exit 3 with only HW-deploy pending, but no HW-deploy block (blocks: $ReminderSummary)" 'the missing block'
        Assert-Equal $E2E['Broken'] 'apply-1' 'Broken'

        $winget = '[dotfiles] [error] W1-winget: winget exited 0x8A150046 (source agreements were not accepted) (docs/bootstrap.md W1-winget)'
        $manifest = "[dotfiles] [error] Unknown -Tier 'bogus'; use all or a comma list of core, cli, ai, desktop, host."
        foreach ($failure in @(
                @{ Code = 1; Out = @(@(Get-WingetLines) + @($winget)); Err = @(''); Detail = "exit 1: $winget" }
                @{ Code = 2; Out = @($manifest); Err = @(); Detail = "exit 2: $manifest" }
                @{ Code = 1; Out = @(Get-WingetLines); Err = @('Exception: Cannot index into a null array.', '   '); Detail = 'exit 1: Exception: Cannot index into a null array.' }
                @{ Code = 124; Out = @(Get-WingetLines); Err = @('winget: still downloading', ''); Detail = 'exit 124 (124 is the 3600s timeout): winget: still downloading' })) {
            $clone = New-DryRun
            Add-Run $failure['Code'] $failure['Out'] $failure['Err']
            Add-Run 0 (Get-ApplyOutput -Clone $clone -Done)
            Assert-True (-not (Invoke-ApplyLoop)) "exit $($failure['Code']) passed"
            Assert-Equal (Get-RowShape @(Get-SummaryRows)) 'apply-1:fail' "exit $($failure['Code']): the rows"
            Assert-Equal @(Get-SummaryRows)[0].Detail $failure['Detail'] "exit $($failure['Code']): the detail"
            Assert-Equal "$($E2E['Broken']) $($script:Runs.Count)" 'apply-1 1' "exit $($failure['Code']): Broken and runs left"
        }
    }

    Test-Case 'apply loop dry run: eight runs that keep applying without reaching the first apply fail as apply-loop' {
        $clone = New-DryRun
        foreach ($n in 1..8) { Add-Run 3 (Get-ApplyOutput -Clone $clone -Blocks (@('HW-deploy') + $Reminders) -Pending 'HW-deploy') }
        Add-Run 3 (Get-ApplyOutput -Clone $clone -Blocks (@('HW-deploy') + $Reminders) -Pending 'HW-deploy' -Done)
        Assert-True (-not (Invoke-ApplyLoop)) 'eight applying runs passed'
        $rows = @(Get-SummaryRows)
        Assert-Equal $rows.Count 9 'eight apply rows and the verdict'
        Assert-Equal "$($rows[-1].Step) $($rows[-1].Status) $($rows[-1].Detail)" 'apply-loop fail eight apply runs without reaching the first apply' 'the verdict'
        Assert-Equal "$($E2E['Broken']) $($script:PwshCalls.Count) $($script:ProcessCalls.Count) $($script:Runs.Count)" 'apply-loop 8 0 1' 'Broken, runs, child processes, runs left'
    }

    Test-Case 'no-write step dry runs: noted cache entries pass, a HOME write, a TEMP leftover or redone work fail' {
        $noted = [IO.Path]::Combine($HOME, 'AppData', 'LocalLow', 'Microsoft', 'CryptnetUrlCache')
        $gitconfig = [IO.Path]::Combine($HOME, '.gitconfig')
        $before = New-FakeSnapshot @{ $gitconfig = '1543|1' }
        $cacheOnly = New-FakeSnapshot @{ $gitconfig = '1543|1'; "$noted\Content\A1" = '1024|2' }
        $written = New-FakeSnapshot @{ $gitconfig = '1600|2'; "$noted\Content\A1" = '1024|2' }
        $plan = @('W1-winget todo winget import of 24 missing tools', 'W1-psresources todo Install-PSResource PSFzf -Scope CurrentUser',
            'W1-font todo oh-my-posh font install CascadiaMono, once W1-winget installs oh-my-posh', 'W1-bat-theme done present',
            'W1-chezmoi todo install the verified chezmoi 2.74.0 archive', 'HW-clone done already done',
            'HW-deploy human judgment step for a person; blocks completion') + @($Reminders | ForEach-Object { "$_ human step for a person; does not block" })

        $clone = New-DryRun
        Add-Run 3 $plan
        $script:Snapshots.Enqueue($before); $script:Snapshots.Enqueue($cacheOnly)
        Use-DryRun { Invoke-E2EStepCheckNoWrite }
        $call = $script:PwshCalls[0]
        $temp = Join-Path $E2E['Out'] 'tmp/check-nowrite'
        Assert-Equal "$($call.Script) $($call.Arguments) $($call.Timeout)" 'dotfiles.ps1 setup --host win --check 900' 'the -Check run'
        Assert-Equal "$($call.Environment['TEMP'])|$($call.Environment['TMP'])" "$temp|$temp" 'its TEMP and TMP'
        Assert-Equal @(Get-SummaryRows)[0].Detail 'exit 3; 4 todo, 5 human; no writes' 'a noted cache entry passes -Check'
        Assert-Equal (Read-Utf8 (Join-Path $E2E['Out'] 'snapshots/check-nowrite.diff')) "noted added $noted\Content\A1`n" 'the noted diff'

        # Windows' token broker refreshes a cache entry on its own, as it did
        # during -Check on a GitHub windows runner.
        $ticket = [IO.Path]::Combine($HOME, 'AppData', 'Local', 'Microsoft', 'TokenBroker', 'Cache') + '\01c5cb21ab1d4fd56e65159d6c36cd5db1f647e1.tbres'
        $clone = New-DryRun
        Add-Run 3 $plan
        $script:Snapshots.Enqueue((New-FakeSnapshot @{ $gitconfig = '1543|1'; $ticket = '2750|1' }))
        $script:Snapshots.Enqueue((New-FakeSnapshot @{ $gitconfig = '1543|1'; $ticket = '2750|2' }))
        Use-DryRun { Invoke-E2EStepCheckNoWrite }
        Assert-Equal @(Get-SummaryRows)[0].Detail 'exit 3; 4 todo, 5 human; no writes' 'a refreshed token broker cache entry passes -Check'
        Assert-Equal (Read-Utf8 (Join-Path $E2E['Out'] 'snapshots/check-nowrite.diff')) "noted changed $ticket (2750|1 -> 2750|2)`n" 'the noted token broker diff'

        $clone = New-DryRun
        Add-Run 3 $plan
        $script:Snapshots.Enqueue($before); $script:Snapshots.Enqueue($written)
        Use-DryRun { Invoke-E2EStepCheckNoWrite }
        Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" "fail exit 3; HOME written (1 difference(s)): changed $gitconfig (1543|1 -> 1600|2)" 'a HOME write fails -Check'

        $clone = New-DryRun
        Add-Run 1 @('[dotfiles] [error] Invalid manifest: tools.tsv row 12 has 7 cells')
        $script:Snapshots.Enqueue($before); $script:Snapshots.Enqueue($before)
        Use-DryRun { Invoke-E2EStepCheckNoWrite }
        Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" 'fail exit 1: [dotfiles] [error] Invalid manifest: tools.tsv row 12 has 7 cells' '-Check exit 1'

        $clone = New-DryRun
        Add-Run 0 (Get-ApplyOutput -Clone $clone -Blocks $Reminders -Done)
        $script:Snapshots.Enqueue($before); $script:Snapshots.Enqueue($cacheOnly)
        Use-DryRun { Invoke-E2EStepSecondApply }
        Assert-Equal "$($script:PwshCalls[0].Arguments) $($script:PwshCalls[0].Timeout)" 'setup --host win --yes 3600' 'the second -Yes'
        Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" 'pass exit 0, nothing applied, HOME untouched' 'a second apply with a noted cache entry'

        $clone = New-DryRun
        $redone = @('[dotfiles] [step] W1-font: oh-my-posh font install CascadiaMono', '[dotfiles] [ok] W1-font: installed: CaskaydiaMono Nerd Font')
        Add-Run 0 (@($DoneLines) + $redone) -Action { [IO.File]::WriteAllText((Join-Path $E2E['NoWriteTemp'] 'CascadiaMono.zip'), 'x') }
        $script:Snapshots.Enqueue($before); $script:Snapshots.Enqueue($before)
        Use-DryRun { Invoke-E2EStepSecondApply }
        Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" "fail a second apply redid work: $($redone -join ' | ')" 'redone work'

        $clone = New-DryRun
        Add-Run 0 (Get-ApplyOutput -Clone $clone -Done) -Action { [IO.File]::WriteAllText((Join-Path $E2E['NoWriteTemp'] 'CascadiaMono.zip'), 'x') }
        $script:Snapshots.Enqueue($before); $script:Snapshots.Enqueue($before)
        Use-DryRun { Invoke-E2EStepSecondApply }
        Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" 'fail TEMP not empty: CascadiaMono.zip' 'a TEMP leftover'
    }

    Test-Case 'check-done dry runs: after the first apply -Check exits 0 with nothing left and writes nothing' {
        $before = New-FakeSnapshot @{ ([IO.Path]::Combine($HOME, '.gitconfig')) = '338|1' }
        $done = @('W1-winget done 24 winget tools on PATH', 'W1-chezmoi done chezmoi 2.74.0', 'HW-clone done already done', 'HW-deploy done already done') +
            @($Reminders | ForEach-Object { "$_ human step for a person; does not block" })
        [void](New-DryRun)
        Add-Run 0 $done
        $script:Snapshots.Enqueue($before); $script:Snapshots.Enqueue($before)
        Use-DryRun { Invoke-E2EStepCheckDone }
        Assert-Equal "$($script:PwshCalls[0].Script) $($script:PwshCalls[0].Arguments) $($script:PwshCalls[0].Timeout)" 'dotfiles.ps1 setup --host win --check 900' 'the -Check run'
        Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" 'pass exit 0; nothing left to apply; no writes' 'nothing left'

        [void](New-DryRun)
        Add-Run 3 (@($done | Where-Object { $_ -notlike 'HW-deploy *' }) + @('HW-deploy human judgment step for a person; blocks completion',
                '[dotfiles] [warn] HUMAN steps pending: HW-deploy; run the HUMAN blocks above, then rerun .\setup-host.ps1'))
        $script:Snapshots.Enqueue($before); $script:Snapshots.Enqueue($before)
        Use-DryRun { Invoke-E2EStepCheckDone }
        Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" `
            'fail exit 3, expected 0 after the first apply: [dotfiles] [warn] HUMAN steps pending: HW-deploy; run the HUMAN blocks above, then rerun .\setup-host.ps1' 'exit 3'

        [void](New-DryRun)
        Add-Run 0 (@($done) + @('W1-font todo oh-my-posh font install CascadiaMono'))
        $script:Snapshots.Enqueue($before); $script:Snapshots.Enqueue($before)
        Use-DryRun { Invoke-E2EStepCheckDone }
        Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" 'fail exit 0 with steps left: W1-font todo oh-my-posh font install CascadiaMono' 'a todo line'

        [void](New-DryRun)
        Add-Run 0 $done
        $script:Snapshots.Enqueue($before); $script:Snapshots.Enqueue((New-FakeSnapshot @{ ([IO.Path]::Combine($HOME, '.gitconfig')) = '400|2' }))
        Use-DryRun { Invoke-E2EStepCheckDone }
        Assert-Equal @(Get-SummaryRows)[0].Status 'fail' 'a HOME write'
    }

    Test-Case 'doctor-final discovers the installed CLI without a profile outside the checkout' {
        [void](New-DryRun)
        Add-Run 0 @()
        $script:ProcessModes.Enqueue('backend')
        Use-DryRun { Invoke-E2EStepDoctorFinal }
        $call = $script:ProcessCalls[0]
        Assert-Equal $call.Arguments '-NoProfile -NonInteractive -Command $LASTEXITCODE = 1; dotfiles doctor --host win; exit $LASTEXITCODE' 'bare-name discovery in a fresh PowerShell'
        Assert-Equal "$($call.WorkingDirectory) $($call.Timeout)" "$($E2E['Home']) 900" 'doctor outside the checkout under its check limit'
        Assert-True ($call.Environment['PATH'].StartsWith((Join-Path $E2E['Home'] '.local/bin') + [IO.Path]::PathSeparator, [StringComparison]::OrdinalIgnoreCase)) 'controlled child PATH contains the installed launcher first'
        Assert-Equal @(Get-SummaryRows)[0].Status 'pass' 'the installed doctor succeeded'
    }

    Test-Case 'doctor-final rejects missing and invalid launchers in real child processes' {
        function Update-E2EPath { }
        foreach ($launcherState in @('missing', 'invalid')) {
            $case = Reset-RunState
            $bin = Join-Path $E2E['Home'] '.local/bin'
            [void][IO.Directory]::CreateDirectory($bin)
            if ($launcherState -ceq 'invalid') { New-File (Join-Path $bin 'dotfiles.ps1') "param(`n" }
            $environment = Get-ChildEnvironment
            $environment['PATH'] = Join-Path $case 'empty-path'
            [void][IO.Directory]::CreateDirectory($environment['PATH'])
            Use-Environment $environment { Invoke-E2EStepDoctorFinal }
            $row = @(Get-SummaryRows)[0]
            Assert-Equal $row.Status 'fail' "$launcherState launcher must not pass without execution"
            Assert-True ($row.Detail -match '^exit [1-9][0-9]*:') "$launcherState launcher needs a nonzero child status: $($row.Detail)"
            Assert-True ([IO.File]::ReadAllText($E2E['StepErr']).Length -gt 0) "$launcherState invocation error must remain on stderr"
        }
    }

    Test-Case 'doctor-final preserves launcher exit codes and streams in real child processes' {
        function Update-E2EPath { }
        foreach ($status in @(0, 37)) {
            $case = Reset-RunState
            $bin = Join-Path $E2E['Home'] '.local/bin'
            New-File (Join-Path $bin 'dotfiles.ps1') ("[Console]::Out.WriteLine('fixture doctor output')`n" +
                "[Console]::Error.WriteLine('fixture doctor diagnostic')`nexit $status`n")
            $environment = Get-ChildEnvironment
            $environment['PATH'] = Join-Path $case 'empty-path'
            [void][IO.Directory]::CreateDirectory($environment['PATH'])
            Use-Environment $environment { Invoke-E2EStepDoctorFinal }
            $row = @(Get-SummaryRows)[0]
            $expected = if ($status -eq 0) { 'pass' } else { 'fail' }
            Assert-Equal $row.Status $expected "launcher exit $status decides the step"
            Assert-True ([IO.File]::ReadAllText($E2E['StepLog']).Contains(", exit $status`n")) "launcher exit $status must reach the process log"
            Assert-Lines @(Get-E2ELines $E2E['StepOut'] | Where-Object { $_ }) @('fixture doctor output') 'stdout survives discovery'
            Assert-Lines @(Get-E2ELines $E2E['StepErr'] | Where-Object { $_ }) @('fixture doctor diagnostic') 'stderr survives discovery'
        }
    }

    Test-Case 'Invoke-E2EStepPayloads: doctor failures retain their exit code even after an installed payloads row' {
        $header = "status`tid`ttier`tdetail`tfix"
        foreach ($doctorCode in @(124, 1, 2)) {
            foreach ($payloadLine in @("ok`tpayloads`tai`tinstalled: pymol, skills`t-", '')) {
                [void](New-DryRun)
                Add-Run 0 @('[dotfiles] [ok] skills: install done')
                $output = @($header)
                if ($payloadLine) { $output += $payloadLine }
                Add-Run $doctorCode $output @('earlier doctor message', 'fixture doctor failure')
                $script:ProcessModes.Enqueue('backend')
                Use-DryRun { Invoke-E2EStepPayloads }
                $rows = @(Get-SummaryRows)
                Assert-Equal (Get-RowShape $rows) 'payloads:fail' "doctor exit $doctorCode with row [$payloadLine] must fail"
                Assert-Equal $rows[0].Detail "doctor exit $doctorCode (124 is the 900s timeout): fixture doctor failure" 'the doctor exit code and error survive'
                Assert-Equal "$($script:PwshCalls[0].Script) $($script:PwshCalls[0].Timeout)" 'dotfiles.ps1 900' 'the doctor timeout stays unchanged'
            }
        }
    }

    Test-Case 'Invoke-E2EStepPayloads: payload-update.ps1 -Now, then a successful doctor and its payloads row decide' {
        $header = "status`tid`ttier`tdetail`tfix"
        [void](New-DryRun)
        Add-Run 0 @('[dotfiles] [ok] pymol: install done', '[dotfiles] [ok] skills: install done')
        Add-Run 0 @($header, "ok`tgit`tcore`t2.51.0`t-", "ok`tpayloads`tai`tinstalled: pymol, skills`t-")
        $script:ProcessModes.Enqueue('backend')
        Use-DryRun { Invoke-E2EStepPayloads }
        Assert-Equal (@($script:PwshCalls | ForEach-Object { "$($_.Script) $($_.Arguments) $($_.Timeout)" }) -join '; ') `
            'dotfiles.ps1 doctor --host win --tsv 900' 'the root CLI doctor follows installed payload sync'
        $call = $script:ProcessCalls[0]
        Assert-Equal $call.Arguments "-NoProfile -NonInteractive -File $(Join-Path $E2E['Home'] '.local/bin/dotfiles.ps1') payloads sync" 'explicit installed launcher in a fresh process'
        Assert-Equal "$($call.WorkingDirectory) $($call.Timeout)" "$($E2E['Home']) 2700" 'installed payload sync outside the checkout, with its original timeout'
        Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" `
            'pass exit 0; doctor payloads ok: installed: pymol, skills' 'every payload installed'

        [void](New-DryRun)
        Add-Run 0 @()
        Add-Run 0 @($header, "warn`tpayloads`tai`tnot installed: skills`tdocs/bootstrap.md H7-payloads")
        $script:ProcessModes.Enqueue('backend')
        Use-DryRun { Invoke-E2EStepPayloads }
        Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" `
            "fail exit 0, but the doctor's payloads row is warn: not installed: skills" 'a payload still missing'

        [void](New-DryRun)
        Add-Run 0 @()
        Add-Run 0 @($header, "ok`tgit`tcore`t2.51.0`t-")
        $script:ProcessModes.Enqueue('backend')
        Use-DryRun { Invoke-E2EStepPayloads }
        Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" `
            "fail exit 0, but the doctor's payloads row is missing" 'a successful doctor without its payloads row'

        # An ok row that names nothing installed (no item selected) passes nothing.
        [void](New-DryRun)
        Add-Run 0 @()
        Add-Run 0 @($header, "ok`tpayloads`tai`tDOTFILES_PAYLOAD_ITEMS selects no payload`t-")
        $script:ProcessModes.Enqueue('backend')
        Use-DryRun { Invoke-E2EStepPayloads }
        Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" `
            "fail exit 0, but the doctor's payloads row is ok: DOTFILES_PAYLOAD_ITEMS selects no payload" 'an empty selection'

        [void](New-DryRun)
        Add-Run 1 @('[dotfiles] [step] skills: installing', '[dotfiles] [error] skills: install failed (exit 1)', 'the next item') @()
        $script:ProcessModes.Enqueue('backend')
        Use-DryRun { Invoke-E2EStepPayloads }
        Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" `
            'fail exit 1 (124 is the 2700s timeout): [dotfiles] [error] skills: install failed (exit 1)' 'the error line from stdout'

        [void](New-DryRun)
        Add-Run 1 @() @('[dotfiles] [error] payload-update: skills failed (exit 1)')
        $script:ProcessModes.Enqueue('backend')
        Use-DryRun { Invoke-E2EStepPayloads }
        Assert-Equal $script:PwshCalls.Count 0 'no doctor run after a failed payload sync'
        Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" `
            'fail exit 1 (124 is the 2700s timeout): [dotfiles] [error] payload-update: skills failed (exit 1)' 'a failed -Now'
    }

    Test-Case 'home-deploy runs the documented Fresh Windows home by hand functions and requires the end state they promise' {
        $clone = New-DeployClone
        New-File (Join-Path $E2E['Home'] '.gitconfig') "[user]`n`tname = runner`n"
        $E2E['DeployBlock'] = [pscustomobject]@{ Id = 'HW-deploy'; Kind = 'judgment'; Lines = @('# Follow Fresh Windows home by hand in docs/bootstrap.md from this checkout.') }
        $script:ProcessModes.Enqueue('clean')
        $script:Elevated = $true
        Use-DryRun { Invoke-E2EStepHomeDeploy }
        . (Join-Path $clone 'lib/chezmoi-guard.ps1')
        $source = Resolve-DotfilesDirectory $clone
        $rows = @(Get-SummaryRows)
        Assert-Equal (Get-RowShape $rows) 'home-deploy:pass deploy-token:note' "the rows:`n$(Get-SummaryText)"
        Assert-Equal $rows[0].Detail "Invoke-HomeDeploy -Role win exit 0; 1 earlier file(s) kept byte for byte; the config names $source" 'the verdict'
        Assert-Equal $rows[1].Detail 'elevated: this harness uses the default runner account; the ordinary-token login-updater check stays in per-host acceptance' 'the token note'
        $runner = Join-Path (Join-Path $E2E['Out'] 'deploy') 'run.ps1'
        $call = $script:ProcessCalls[0]
        Assert-Equal "$($call.FilePath) $($call.Arguments)" "$($E2E['PowerShell']) -NoProfile -NonInteractive -File $runner" 'the child'
        Assert-Equal "$($call.WorkingDirectory) $($call.Timeout)" "$clone 3600" 'from the clone under the apply limit'
        $deploy = Get-E2EDeployScript -Document (Join-Path $sourceRoot 'docs/bootstrap.md')
        Assert-Equal (Read-Utf8 $runner) ($deploy['Text'] + "`nInvoke-HomeDeploy -Role win`n") 'the runner: the fence and its one call'
        Assert-True ([IO.File]::ReadAllText($E2E['StepLog']).StartsWith("--- block`n# Follow Fresh Windows home by hand in docs/bootstrap.md from this checkout.`n")) 'the step log starts with the HW-deploy block'
        Assert-Equal "$($E2E['Broken']) $($E2E['Phase'])" ' ' 'Broken and the phase after the step'
        $timeline = @(Get-E2ELines (Join-Path $E2E['Out'] 'log/timeline') | Where-Object { $_ } | ForEach-Object { $_.Split("`t", 2)[1].Replace("`t", ' ') })
        Assert-Equal ($timeline -join ', ') 'begin human:HW-deploy, end human:HW-deploy' 'the phase'

        [void](New-DeployClone)
        $script:ProcessModes.Enqueue('clean')
        Use-DryRun { Invoke-E2EStepHomeDeploy }
        Assert-Equal (Get-RowShape @(Get-SummaryRows)) 'home-deploy:pass' 'no note on an ordinary token'
        Assert-True (@(Get-SummaryRows)[0].Detail.Contains('exit 0; 0 earlier file(s) kept byte for byte')) 'nothing to keep in an empty home'

        foreach ($failure in @(
                @{ Mode = 'bad-config'; Text = 'lib/chezmoi-guard.ps1 refuses the config: destDir must be this home.' }
                @{ Mode = 'maintenance'; Text = '~\.config\dotfiles\maintenance exists' }
                @{ Mode = 'no-copy'; Text = 'no same-hash copy of ~\.gitconfig in ~\.local\state\dotfiles-fresh-backup' }
                @{ Mode = 'no-state'; Text = '~\.local\state\chezmoi\chezmoi.boltdb is missing or empty' }
                @{ Mode = 'refused'; Text = 'Invoke-HomeDeploy -Role win exit 1: Invoke-HomeDeploy: ~\.gitconfig is a link or not the expected kind of entry' })) {
            [void](New-DeployClone)
            New-File (Join-Path $E2E['Home'] '.gitconfig') "[user]`n`tname = runner`n"
            $script:ProcessModes.Enqueue($failure['Mode'])
            Use-DryRun { Invoke-E2EStepHomeDeploy }
            $row = @(Get-SummaryRows)[0]
            Assert-Equal "$($row.Step) $($row.Status)" 'home-deploy fail' "$($failure['Mode']): the row"
            Assert-True $row.Detail.Contains($failure['Text']) "$($failure['Mode']): $($row.Detail)"
            Assert-Equal $E2E['Broken'] 'home-deploy' "$($failure['Mode']): Broken"
        }

        # A fence that holds anything but the two definitions never runs.
        $clone = New-DeployClone
        $planted = New-PlantedDocument -Directory (Join-Path $E2E['Out'] 'plant') -Text 'Invoke-HomeDeploy -Role win'
        New-File (Join-Path $clone 'docs/bootstrap.md') ([IO.File]::ReadAllText($planted))
        Invoke-Git $clone @('-c', 'user.name=e2e', '-c', 'user.email=e2e@example.invalid', 'commit', '-q', '-a', '-m', 'planted')
        Use-DryRun { Invoke-E2EStepHomeDeploy }
        Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" ('fail docs/bootstrap.md: a statement outside the Invoke-HomeCz and ' +
            'Invoke-HomeDeploy definitions in the fenced powershell block: Invoke-HomeDeploy -Role win') 'a planted call'
        Assert-Equal "$($E2E['Broken']) $($script:ProcessCalls.Count)" 'home-deploy 0' 'Broken and nothing ran'
    }

    Test-Case 'home-converged: an empty Invoke-HomeCz diff and regular managed files pass; a diff, another entry or a failure fail' {
        $clone = New-DeployClone
        New-File (Join-Path $E2E['Home'] '.gitconfig') "[user]`n"
        New-File (Join-Path $E2E['Home'] 'Documents/PowerShell/profile.ps1') "# deployed profile`n"
        $script:Managed = @('.gitconfig', 'Documents/PowerShell/profile.ps1')
        $script:ProcessModes.Enqueue('converged')
        Use-DryRun { Invoke-E2EStepHomeConverged }
        Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" 'pass empty diff; 2 managed file(s), all regular' 'converged'
        $runner = Join-Path (Join-Path $E2E['Out'] 'deploy') 'converged.ps1'
        Assert-Equal "$($script:ProcessCalls[0].Arguments) $($script:ProcessCalls[0].WorkingDirectory) $($script:ProcessCalls[0].Timeout)" `
            "-NoProfile -NonInteractive -File $runner $clone 900" 'the child'
        $text = Read-Utf8 $runner
        $deploy = Get-E2EDeployScript -Document (Join-Path $sourceRoot 'docs/bootstrap.md')
        Assert-True $text.StartsWith($deploy['Text']) 'the check runs after the documented functions'
        Assert-True ($text.Contains("Invoke-HomeCz @('diff', '--exclude=dirs')") -and $text.Contains("Invoke-HomeCz @('managed', '--include=files,symlinks')")) "the check: $text"
        $tokens = $null
        $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors)
        Assert-Equal @($parseErrors).Count 0 'the check script parses'

        foreach ($failure in @(
                @{ Mode = 'diff'; Managed = @('.gitconfig'); Text = 'fail Invoke-HomeCz diff --exclude=dirs is not empty: diff --git a/.gitconfig b/.gitconfig' }
                @{ Mode = 'converged'; Managed = @('.gitconfig', 'Documents/PowerShell'); Text = 'fail managed targets that are not regular files: Documents/PowerShell' }
                @{ Mode = 'converged'; Managed = @(); Text = 'fail Invoke-HomeCz managed --include=files,symlinks listed no target' }
                @{ Mode = 'exit-1'; Managed = @(); Text = 'fail the convergence check exited 1: Invoke-HomeCz: chezmoi diff --exclude=dirs exited 1' })) {
            [void](New-DeployClone)
            New-File (Join-Path $E2E['Home'] '.gitconfig') "[user]`n"
            New-File (Join-Path $E2E['Home'] 'Documents/PowerShell/profile.ps1') "# deployed profile`n"
            $script:Managed = $failure['Managed']
            $script:ProcessModes.Enqueue($failure['Mode'])
            Use-DryRun { Invoke-E2EStepHomeConverged }
            Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" $failure['Text'] "$($failure['Mode']) with [$($failure['Managed'] -join ', ')]"
        }
    }

    Test-Case 'audit-scheduled-tasks: no change after the apply loop; the tasks the loop added are noted' {
        $installed = "\Microsoft\Windows\Defrag`n\WinGet\Installer"
        foreach ($case in @(
                @{ Before = '\Microsoft\Windows\Defrag'; AfterLoop = $installed; Now = $installed; Shape = 'audit-scheduled-tasks:pass scheduled-tasks:note'
                    Detail = '2 task identities, unchanged after the apply loop' }
                @{ Before = $installed; AfterLoop = $installed; Now = $installed; Shape = 'audit-scheduled-tasks:pass'; Detail = '2 task identities, unchanged after the apply loop' }
                @{ Before = $installed; AfterLoop = $installed; Now = "$installed`n\Later\Task"; Shape = 'audit-scheduled-tasks:fail'
                    Detail = 'task identities changed after the apply loop (added: \Later\Task; removed: )' })) {
            [void](New-DryRun)
            $E2E['TasksBefore'] = $case['Before']
            $E2E['TasksAfterLoop'] = $case['AfterLoop']
            $script:TaskNames = $case['Now']
            Use-DryRun { Invoke-E2EAuditTasks }
            $rows = @(Get-SummaryRows)
            Assert-Equal (Get-RowShape $rows) $case['Shape'] "the rows for [$($case['Now'])]"
            Assert-Equal $rows[0].Detail $case['Detail'] "the verdict for [$($case['Now'])]"
        }
        Assert-Equal @(Get-SummaryRows)[0].Status 'fail' 'the last case'
        [void](New-DryRun)
        $E2E['TasksBefore'] = '\A'
        $E2E['TasksAfterLoop'] = "\A`n\B"
        $script:TaskNames = "\A`n\B"
        Use-DryRun { Invoke-E2EAuditTasks }
        Assert-Equal @(Get-SummaryRows)[1].Detail 'the apply loop added 1 task(s): \B' 'the note'
    }

    Test-Case 'chezmoi fixtures require the provisioned binary and propagate failure' {
        foreach ($code in @(0, 1)) {
            [void](New-DryRun)
            Add-Run $code
            Use-DryRun { Invoke-E2EStepChezmoiFixtures }
            $call = $script:PwshCalls[0]
            Assert-Equal $call.Script tests/chezmoi.ps1 'chezmoi aggregate entrypoint'
            Assert-Equal $call.Environment['DOTFILES_TEST_CHEZMOI'] (Join-Path $E2E['Home'] '.local/bin/chezmoi.exe') 'chezmoi binary selection'
            Assert-Equal $call.Environment['DOTFILES_TEST_REQUIRE_CHEZMOI'] 1 'chezmoi prerequisite cannot skip'
            $want = if ($code) { 'fail' } else { 'pass' }
            Assert-Equal (@(Get-SummaryRows)[0].Status) $want 'chezmoi fixture status'
            if (-not $code) { Assert-Equal @(Get-SummaryRows)[0].Detail 'isolated chezmoi fixtures passed' 'the pass text' }
        }
    }

    Test-Case 'hosted App Installer preparation leaves non-hosted sessions and absent packages alone' {
        [void](Reset-RunState)
        function Test-E2EHostedRunner { return $false }
        function Invoke-E2EAppInstallerCommand { throw 'A non-hosted session must not reach Appx.' }
        Invoke-E2EAppInstallerPrepare 'appinstaller-initial'
        Assert-Equal @(Get-SummaryRows)[0].Status skip 'native sessions retain their update settings'
        [void](Reset-RunState)
        function Test-E2EHostedRunner { return $true }
        function Invoke-E2EAppInstallerCommand([string]$Action) {
            Assert-Equal $Action Capture 'absence needs only one read'
            return [pscustomobject]@{ present = $false }
        }
        Invoke-E2EAppInstallerPrepare 'appinstaller-initial'
        Assert-Equal $E2E['Fails'] 0 'an absent package remains the doctor or setup responsibility'
        Assert-True (-not [IO.File]::Exists((Join-Path $E2E['Out'] 'appinstaller-state.json'))) 'absence owns no pause'
    }

    Test-Case 'hosted App Installer preparation owns one pause, persists before mutation and restores idempotently' {
        [void](Reset-RunState)
        function Test-E2EHostedRunner { return $true }
        $script:Policy = @{ present = $true; package = 'synthetic-package'; hash = 'a' * 64;
            policy_fingerprint = 'b' * 64; policy_source = 'Default'; paused_until = ''; active_pause = $false }
        $script:PolicyCalls = [Collections.Generic.List[string]]::new()
        function Invoke-E2EAppInstallerCommand([string]$Action) {
            $script:PolicyCalls.Add($Action)
            if ($Action -ceq 'Preflight') { return [pscustomobject]@{ ready = $true } }
            if ($Action -ceq 'Pause') {
                $saved = [IO.File]::ReadAllText((Join-Path $E2E['Out'] 'appinstaller-state.json')) | ConvertFrom-Json
                Assert-True $saved.attempted 'attempt ownership must precede even a partially failing setter'
                Assert-Equal $saved.baseline.hash ('a' * 64) 'baseline bytes are already durable'
                $script:Policy.active_pause = $true
                $script:Policy.paused_until = [DateTimeOffset]::UtcNow.AddHours(2).ToString('o')
            }
            if ($Action -ceq 'Resume') { $script:Policy.active_pause = $false; $script:Policy.paused_until = '' }
            return [pscustomobject]$script:Policy.Clone()
        }
        Invoke-E2EAppInstallerPrepare 'appinstaller-initial'
        Invoke-E2EAppInstallerPrepare 'appinstaller-installed'
        Assert-Equal $E2E['Fails'] 0 'the owned pause is reused without replacing its baseline'
        Invoke-E2EAppInstallerRestore
        Invoke-E2EAppInstallerRestore
        Assert-Equal @($script:PolicyCalls | Where-Object { $_ -ceq 'Pause' }).Count 1 'one pause setter'
        Assert-Equal @($script:PolicyCalls | Where-Object { $_ -ceq 'Resume' }).Count 1 'one resume setter'
        $saved = [IO.File]::ReadAllText((Join-Path $E2E['Out'] 'appinstaller-state.json')) | ConvertFrom-Json
        Assert-True $saved.restored 'restoration is verified and durable'
    }

    Test-Case 'hosted App Installer refuses foreign policy and existing pauses before mutation' {
        function Test-E2EHostedRunner { return $true }
        foreach ($mode in @('system-policy', 'existing-pause')) {
            [void](Reset-RunState)
            $script:PolicyMode = $mode
            function Invoke-E2EAppInstallerCommand([string]$Action) {
                Assert-Equal $Action Capture 'foreign settings must never reach a setter'
                return [pscustomobject]@{ present = $true; package = 'synthetic-package'; hash = 'a' * 64;
                    policy_fingerprint = 'b' * 64; policy_source = $(if ($script:PolicyMode -ceq 'system-policy') { 'System' } else { 'Default' });
                    paused_until = $(if ($script:PolicyMode -ceq 'existing-pause') { '2099-01-01T00:00:00Z' } else { '' });
                    active_pause = $script:PolicyMode -ceq 'existing-pause' }
            }
            Invoke-E2EAppInstallerPrepare 'appinstaller-initial'
            Assert-Equal $E2E['Fails'] 1 'foreign settings fail preparation'
            Assert-True (-not [IO.File]::Exists((Join-Path $E2E['Out'] 'appinstaller-state.json'))) 'no owned mutation was recorded'
        }
    }

    Test-Case 'hosted App Installer cleanup preserves setter and doctor failures and rejects restoration drift' {
        function Test-E2EHostedRunner { return $true }
        foreach ($mode in @('partial-setter', 'doctor-124', 'restore-drift')) {
            [void](Reset-RunState)
            $script:PolicyMode = $mode
            $script:Policy = @{ present = $true; package = 'synthetic-package'; hash = 'a' * 64;
                policy_fingerprint = 'b' * 64; policy_source = 'Default'; paused_until = ''; active_pause = $false }
            $script:Resumed = $false
            function Invoke-E2EAppInstallerCommand([string]$Action) {
                if ($Action -ceq 'Preflight') { return [pscustomobject]@{ ready = $true } }
                if ($Action -ceq 'Pause') {
                    $script:Policy.active_pause = $true
                    $script:Policy.paused_until = [DateTimeOffset]::UtcNow.AddHours(2).ToString('o')
                    if ($script:PolicyMode -ceq 'partial-setter') { throw 'Synthetic partial setter failure.' }
                }
                if ($Action -ceq 'Resume') {
                    $script:Resumed = $true
                    $script:Policy.active_pause = $false
                    $script:Policy.paused_until = ''
                    if ($script:PolicyMode -ceq 'restore-drift') { $script:Policy.hash = 'c' * 64 }
                }
                return [pscustomobject]$script:Policy.Clone()
            }
            Invoke-E2EAppInstallerPrepare 'appinstaller-initial'
            if ($mode -ceq 'doctor-124') { Write-E2EFailure doctor-final 'exit 124: original doctor timeout' }
            Invoke-E2EAppInstallerRestore
            Assert-True $script:Resumed 'cleanup runs after success or a partially applied pause'
            Assert-Equal $E2E['Fails'] 1 'cleanup cannot erase a setter/doctor failure, and drift itself fails'
            $saved = [IO.File]::ReadAllText((Join-Path $E2E['Out'] 'appinstaller-state.json')) | ConvertFrom-Json
            Assert-Equal $saved.restored ($mode -cne 'restore-drift') 'only verified restoration is marked complete'
            if ($mode -ceq 'doctor-124') { Assert-True ((Get-SummaryText).Contains('exit 124')) 'doctor timeout remains visible' }
        }
    }

    Test-Case 'the actual driver finally restores App Installer after an escaped exception' {
        $tokens = $null; $errors = $null
        $tree = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'e2e/run.ps1'), [ref]$tokens, [ref]$errors)
        Assert-Equal $errors.Count 0 'driver parses before extracting its cleanup boundary'
        $guard = $tree.Find({ param($node)
                $node -is [Management.Automation.Language.TryStatementAst] -and
                $node.Body.Extent.Text.Contains('Invoke-E2EFlowWin') }, $false)
        Assert-True ($null -ne $guard -and $null -ne $guard.Finally) 'the actual driver flow owns a finally block'
        $script:RestoredAfterEscape = $false
        function Invoke-E2EAppInstallerRestore { $script:RestoredAfterEscape = $true }
        $probe = [scriptblock]::Create("try { throw 'synthetic escaped flow failure' } finally " + $guard.Finally.Extent.Text)
        $caught = $false
        try { & $probe } catch { $caught = $true }
        Assert-True $caught 'the original exception remains a failure'
        Assert-True $script:RestoredAfterEscape 'the real finally block invokes restoration'
    }

    Test-Case 'Invoke-E2EFlowWin runs the steps in order and, once one breaks the flow, skips what depends on it; the audit always runs' {
        $script:FlowCalls = [Collections.Generic.List[string]]::new()
        $script:BreakAt = ''
        function Complete-FlowStub([string]$Name) {
            $script:FlowCalls.Add($Name)
            Start-E2EStep $Name "stub:$Name"
            if ($Name -ceq $script:BreakAt) { $E2E['Broken'] = $Name; Complete-E2EStep fail 'stub failure' }
            else { Complete-E2EStep pass 'stub' }
        }
        function Get-E2EScheduledTaskNames { $script:FlowCalls.Add('tasks'); return '' }
        function Invoke-E2EStepClone { Complete-FlowStub clone }
        function Invoke-E2EStepWinget { Complete-FlowStub winget }
        function Invoke-E2EAppInstallerPrepare([string]$Name) { Complete-FlowStub $Name }
        function Invoke-E2EStepDoctorInitial { Complete-FlowStub doctor-initial }
        function Invoke-E2EStepCheckNoWrite { Complete-FlowStub check-nowrite }
        function Invoke-E2EApplyLoop { Complete-FlowStub apply-1; return ($script:BreakAt -cne 'apply-1') }
        function Invoke-E2EStepHomeDeploy { Complete-FlowStub home-deploy }
        function Invoke-E2EStepSecondApply { Complete-FlowStub second-apply }
        function Invoke-E2EStepCheckDone { Complete-FlowStub check-done }
        function Invoke-E2EStepLoginShell { Complete-FlowStub login-shell }
        function Invoke-E2EStepPayloads { Complete-FlowStub payloads }
        function Invoke-E2EStepHomeConverged { Complete-FlowStub home-converged }
        function Invoke-E2EStepDoctorFinal { Complete-FlowStub doctor-final }
        function Invoke-E2EStepChezmoiFixtures { Complete-FlowStub chezmoi-fixtures }
        function Invoke-E2EAuditTasks { $script:FlowCalls.Add('audit-scheduled-tasks') }
        $steps = @('clone', 'winget', 'appinstaller-initial', 'doctor-initial', 'check-nowrite', 'apply-1', 'appinstaller-installed', 'home-deploy', 'second-apply', 'check-done',
            'login-shell', 'payloads', 'home-converged', 'doctor-final', 'chezmoi-fixtures')
        $audits = @('audit-scheduled-tasks')
        Assert-Equal ($steps.Count + $audits.Count) 16 'sixteen steps including both hosted preparation checkpoints'
        foreach ($breakAt in @('', 'clone', 'appinstaller-initial', 'check-nowrite', 'apply-1', 'appinstaller-installed', 'home-deploy', 'check-done', 'home-converged')) {
            [void](Reset-RunState)
            $script:FlowCalls.Clear()
            $script:BreakAt = $breakAt
            Invoke-E2EFlowWin
            $ran = if ($breakAt) { [array]::IndexOf($steps, $breakAt) + 1 } else { $steps.Count }
            $called = [Collections.Generic.List[string]]::new()
            foreach ($step in $steps[0..($ran - 1)]) {
                if ($step -ceq 'apply-1') { $called.Add('tasks') }
                $called.Add($step)
                if ($step -ceq 'apply-1') { $called.Add('tasks') }
            }
            $called.AddRange([string[]]$audits)
            Assert-Equal ($script:FlowCalls -join ' ') ($called -join ' ') "break at '$breakAt': the steps run"
            $expected = for ($i = 0; $i -lt $steps.Count; $i++) {
                $status = if ($i -ge $ran) { 'skip' } elseif ($i -eq $ran - 1 -and $breakAt) { 'fail' } else { 'pass' }
                "$($steps[$i]):$status"
            }
            $rows = @(Get-SummaryRows)
            Assert-Equal (Get-RowShape $rows) ($expected -join ' ') "break at '$breakAt': the rows"
            foreach ($row in @($rows | Where-Object { $_.Status -eq 'skip' })) {
                Assert-Equal $row.Detail "after $breakAt failed" "break at '$breakAt': the skip of $($row.Step)"
            }
        }
    }

    Write-Output "e2e-harness-ps=PASS ($script:Passed cases)"
}
finally {
    if ([IO.Path]::GetFileName($testRoot) -notlike 'dotfiles-e2e-ps-*') { throw 'Unexpected cleanup target.' }
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
