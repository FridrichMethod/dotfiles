#Requires -Version 7.0
# Unit test of the native Windows end-to-end driver, tests/e2e/run.ps1 and
# tests/e2e/lib/*.ps1: the PowerShell twin of tests/e2e-harness.sh. The
# libraries are dot-sourced into this process and run unchanged; what would
# reach the machine is replaced by stubs defined in a case's own scope, where
# the driver resolves them: each setup-host.ps1 run (realistic -Yes output
# with winget's blank progress lines and CRLF endings), the HW-stow line's
# child (it records the applied state in the clone's git dir only on a
# warning-free run, as stow-all.ps1 does), the ~\.gitconfig link check, the
# registry PATH rebuild and the HOME snapshots of the no-write steps. The
# clean-clone check and rev-parse run real git on a temp repository standing
# in for the clone; Invoke-E2EProcess, the run.ps1 refusals and
# setup-host.ps1 -PrintManual run as real child pwsh processes with their
# caches kept under the temp dir off Windows. Every tree lives under one temp
# directory, removed at the end, also on failure; nothing reads or writes the
# real home or profile, and no git runs on the real repository. Runs on Linux
# and macOS pwsh as well as Windows; the Windows-only checks are guarded and
# print a SKIP line elsewhere.
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
foreach ($name in @('common', 'snapshot', 'blocks', 'steps', 'flow-win')) { . (Join-Path $e2eLib "$name.ps1") }
$InitialRunState = $E2E.Clone()

# The driver's console lines, kept for assertions instead of printed.
$script:Console = [Collections.Generic.List[string]]::new()
function Write-E2ELog {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Message)
    $script:Console.Add($Message)
}

function Reset-RunState {
    # A fresh run state as run.ps1 fills it, with E2E_OUT and its
    # subdirectories under a new case directory, which it returns.
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
    New-File (Join-Path $Path 'common/git/.gitconfig') "[user]`n`tname = e2e`n"
    Invoke-Git $Path @('init', '-q')
    Invoke-Git $Path @('add', '--', 'common')
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

$Reminders = @('HW-auto-stow-task', 'HW-execution-policy', 'HW-ssh-agent', 'HW-wsl', 'HW-auth')
$ReminderSummary = 'HW-auto-stow-task(judgment) HW-execution-policy(judgment) HW-ssh-agent(sudo) HW-wsl(judgment) HW-auth(auth)'
$DoneLines = @(
    '[dotfiles] [ok] W1-winget: done: 24 winget tools on PATH'
    '[dotfiles] [ok] W1-psresources: done: 3 modules installed'
    '[dotfiles] [ok] W1-font: done: CaskaydiaMono Nerd Font installed'
    '[dotfiles] [info] W1-bat-theme: skip: no selected tier needs the bat theme'
    '[dotfiles] [ok] W1-setup-sync: done: .venv-sync passes the runtime check'
)
$StowWarning = 'WARNING: [dotfiles] [warn] PowerShell loads C:\Users\runneradmin\Documents\PowerShell\profile.ps1 but ' +
    'profiles were stowed under C:\Users\runneradmin\OneDrive\Documents\PowerShell (Documents may be redirected to OneDrive)'

function Get-WingetLines {
    # The applied steps of a first -Yes run: winget import's spinner frames
    # (carriage returns inside one line), a progress bar and the blank lines
    # its progress leaves, as a redirected winget writes them.
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
        '[dotfiles] [step] W1-setup-sync: run .\setup-sync.ps1 -Python C:\hostedtoolcache\windows\Python\3.12.10\x64\python.exe'
        ''
        '[dotfiles] [ok] W1-setup-sync: installed: .venv-sync passes the runtime check'
    )
}

function Get-BlockLines {
    # One HUMAN block as setup-host.ps1 prints it for a clone at Clone
    # (Get-SetupHumanBlock: paths single-quoted, quotes doubled).
    param([string]$Id, [string]$Clone)
    $repo = ConvertTo-Quoted $Clone
    $body = switch -CaseSensitive ($Id) {
        'HW-clone' {
            'gui', '# Turn on Developer Mode (Settings > System > For developers) so Git can create symlinks.',
            '# A fresh clone: git clone -c core.symlinks=true --recurse-submodules <repository URL>',
            "git -C $repo config core.symlinks true",
            "git -C $repo checkout -- common/pymol common/claude/.claude/dotfiles common/claude/.local common/claude/.oh-my-zsh common/codex/.local common/codex/.oh-my-zsh"
        }
        'HW-stow' {
            'judgment', '# From an elevated PowerShell 7 (Run as administrator); it writes ~\.claude, ~\.codex and ~\.ssh.',
            "& $(ConvertTo-Quoted (Join-Path $Clone 'stow-all.ps1')) win"
        }
        'HW-auto-stow-task' {
            'judgment', '# Optional, elevated PowerShell 7 (the MSI, see HW-clone): lets the login updater restow without a UAC prompt.',
            "& $(ConvertTo-Quoted (Join-Path (Join-Path $Clone 'scripts') 'dotfiles-auto-stow.ps1')) -Register"
        }
        'HW-execution-policy' {
            'judgment', '# Lets the stowed profiles and these scripts run. PowerShell 7 and Windows PowerShell 5.1 keep separate settings.',
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
            'auth', '# Sign in, then check with .\doctor.ps1 -Online. Skip gh auth setup-git: it would write the stowed ~\.gitconfig.',
            'ssh-keygen -t ed25519 -f $HOME\.ssh\id_ed25519', 'gh auth login --git-protocol ssh', 'claude auth login', 'codex login'
        }
        default { throw "No fixture block for $Id" }
    }
    return @("HUMAN-BEGIN $Id $($body[0])") + @($body | Select-Object -Skip 1) + @('HUMAN-END')
}

function Get-ApplyOutput {
    # The stdout of a setup-host.ps1 -Host win -Yes run for a clone at Clone:
    # the applied steps (winget's progress, or the -Done lines of a run with
    # nothing to apply), the HUMAN blocks of Blocks in order, then the
    # pending line naming Pending, or the closing line of an exit 0.
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
$script:Snapshots = [Collections.Generic.Queue[object]]::new()
$script:SnapshotCalls = [Collections.Generic.List[object]]::new()
$script:StowMode = 'clean'
$script:Stowed = @{ Done = $true; Detail = '' }

function New-DryRun {
    # A fresh run state with its own clone and empty stub queues; returns
    # the clone. StowMode says what the HW-stow line's child does.
    param([string]$StowMode = 'clean')
    $case = Reset-RunState
    $clone = Join-Path $case 'home/dotfiles'
    New-TempClone $clone
    $E2E['Clone'] = $clone
    $E2E['PowerShell'] = Join-Path $case 'bin/pwsh-never-started'
    $script:Runs.Clear()
    $script:PwshCalls.Clear()
    $script:ProcessCalls.Clear()
    $script:Snapshots.Clear()
    $script:SnapshotCalls.Clear()
    $script:StowMode = $StowMode
    $script:Stowed = @{ Done = $true; Detail = "~\.gitconfig -> $(Join-Path $clone 'common/git/.gitconfig')" }
    return $clone
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

function Write-StowState {
    # What Save-DotfilesStowState writes: <gitdir>\dotfiles-sync-windows\configuration.json.
    $state = Join-Path (Join-Path (Join-Path $E2E['Clone'] '.git') 'dotfiles-sync-windows') 'configuration.json'
    New-File $state ('{"home":"C:\\Users\\runneradmin","host":"win","appliedHead":"' + ('a' * 40) + '"}')
}

function Use-DryRun {
    # Run Action with the driver's machine-facing collaborators replaced in
    # this scope: no registry PATH rebuild; each setup-host.ps1 run takes
    # the next of $script:Runs; the HW-stow line's child plays stow-all.ps1
    # as $script:StowMode says; the ~\.gitconfig check answers
    # $script:Stowed; each HOME snapshot takes the next of $script:Snapshots.
    param([scriptblock]$Action)
    function Update-E2EPath { }
    function Test-E2EStowed { return @{ Done = $script:Stowed['Done']; Detail = $script:Stowed['Detail'] } }
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
                FilePath = $FilePath; Arguments = ($ArgumentList -join ' '); WorkingDirectory = $WorkingDirectory
                Timeout = $TimeoutSeconds; Line = [string]$Environment['E2E_BLOCK_LINE']
            })
        $out = [Collections.Generic.List[string]]::new()
        $err = [Collections.Generic.List[string]]::new()
        $out.Add('[dotfiles] [step] Stowing common packages, then win, into C:\Users\runneradmin')
        $code = 0
        switch ($script:StowMode) {
            'clean' { Write-StowState }
            'warn-stdout' { $out.Add($StowWarning) }
            'warn-stderr' { $err.Add($StowWarning) }
            'warn-with-state' { $out.Add($StowWarning); Write-StowState }
            'no-state' { }
            'exit-1' { $err.Add('Exception: Stow dry run found a conflict at C:\Users\runneradmin\.gitconfig'); $code = 1 }
            default { throw "unknown stow mode $($script:StowMode)" }
        }
        if ($code -eq 0) { $out.Add('[dotfiles] [ok] Stow complete; linked: 41   repaired: 0   unchanged/ignored: 7   backed up: 1') }
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

try {
    Test-Case 'ConvertFrom-E2EBlocks keeps notes and commands per block, winget''s blank lines included (bug 1)' {
        $case = Reset-RunState
        $clone = Join-Path $case 'home/dotfiles'
        # As Get-E2ELines reads a step's .out: CRLF split, a trailing ''.
        $text = ConvertTo-StepText (Get-ApplyOutput -Clone $clone -Blocks (@('HW-stow') + $Reminders) -Pending 'HW-stow')
        $output = @($text -split '\r?\n')
        Assert-True (@($output | Where-Object { $_ -eq '' }).Count -ge 4) 'the fixture output lost its blank lines'
        $directory = Join-Path $case 'out/steps/01-apply-1.blocks'
        $blocks = @(ConvertFrom-E2EBlocks -Output $output -Directory $directory)
        Assert-Equal (Get-E2EBlocksSummary $blocks) "HW-stow(judgment) $ReminderSummary" 'blocks in printed order'
        $stowLine = "& $(ConvertTo-Quoted (Join-Path $clone 'stow-all.ps1')) win"
        Assert-Lines $blocks[0].Lines @('# From an elevated PowerShell 7 (Run as administrator); it writes ~\.claude, ~\.codex and ~\.ssh.', $stowLine) 'HW-stow: its note, then its command'
        Assert-Equal $blocks[3].Lines.Count 4 'HW-ssh-agent keeps its two notes and two commands'
        foreach ($block in $blocks) {
            Assert-True (-not @($block.Lines | Where-Object { $_.StartsWith('[dotfiles]') -or $_.StartsWith('HUMAN-') -or $_ -eq '' }).Count) "$($block.Id) holds a line from outside it"
        }
        Assert-Equal (Read-Utf8 (Join-Path $directory 'index')) ("1`tHW-stow`tjudgment`n2`tHW-auto-stow-task`tjudgment`n3`tHW-execution-policy`tjudgment`n" +
            "4`tHW-ssh-agent`tsudo`n5`tHW-wsl`tjudgment`n6`tHW-auth`tauth`n") 'the index file'
        Assert-Equal (Read-Utf8 (Join-Path $directory '1.block')) ("# From an elevated PowerShell 7 (Run as administrator); it writes ~\.claude, ~\.codex and ~\.ssh.`n$stowLine`n") '1.block'
        Assert-Equal @(Get-ChildItem -LiteralPath $directory -Filter '*.block').Count 6 'one <n>.block per block'

        $blank = @(ConvertFrom-E2EBlocks -Output @('', 'HUMAN-BEGIN HW-wsl judgment', '', 'wsl --install -d Ubuntu', '   ', 'HUMAN-END', '') -Directory (Join-Path $case 'blank'))
        Assert-Equal (Get-E2EBlocksSummary $blank) 'HW-wsl(judgment)' 'blank lines around a block'
        Assert-Lines $blank[0].Lines @('', 'wsl --install -d Ubuntu', '   ') 'blank lines inside a block are kept'

        $partialDirectory = Join-Path $case 'partial'
        $partial = @(ConvertFrom-E2EBlocks -Directory $partialDirectory -Output @(
                'HUMAN-END', 'HUMAN-BEGIN HW-stow judgment', $stowLine, 'HUMAN-END',
                'HUMAN-BEGIN HW-wsl Judgment', 'wsl --install -d Ubuntu', 'HUMAN-END',
                'HUMAN-BEGIN HW-auth auth extra', 'codex login', 'HUMAN-END',
                'HUMAN-BEGIN HW-auth auth', 'gh auth login --git-protocol ssh'))
        Assert-Equal (Get-E2EBlocksSummary $partial) 'HW-stow(judgment)' 'a stray HUMAN-END, malformed HUMAN-BEGIN lines and an unclosed block make no block'
        Assert-Equal (Read-Utf8 (Join-Path $partialDirectory 'index')) "1`tHW-stow`tjudgment`n" 'the index lists closed blocks only'
        Assert-True (-not [IO.File]::Exists((Join-Path $partialDirectory '2.block'))) 'the unclosed block was saved'

        $none = @(ConvertFrom-E2EBlocks -Output @() -Directory (Join-Path $case 'none'))
        Assert-Equal $none.Count 0 'no output, no block'
        Assert-Equal (Read-Utf8 (Join-Path $case 'none/index')) "`n" 'an empty index'
    }

    Test-Case 'Get-E2EBlockPolicy: HW-stow runs, the five reminders skip, HW-clone and every other (id, kind) fail (bug 2)' {
        $rows = @(
            'HW-stow judgment run-stow'
            'HW-auto-stow-task judgment skip', 'HW-execution-policy judgment skip', 'HW-ssh-agent sudo skip'
            'HW-wsl judgment skip', 'HW-auth auth skip'
            'HW-clone gui fail'
            # A known id with another kind.
            'HW-stow sudo fail', 'HW-stow inspect fail', 'HW-stow gui fail', 'HW-clone judgment fail', 'HW-ssh-agent judgment fail'
            'HW-auth judgment fail', 'HW-wsl gui fail', 'HW-execution-policy sudo fail', 'HW-auto-stow-task auth fail'
            # Case matters.
            'hw-stow judgment fail', 'HW-stow Judgment fail', 'HW-AUTH auth fail'
            # Unknown ids and kinds.
            'H7-stow judgment fail', 'W1-winget judgment fail', 'HW-recovery judgment fail', 'HW-stow alloc fail', 'HW-wsl chsh fail'
        )
        foreach ($row in $rows) {
            $id, $kind, $action = $row.Split(' ')
            Assert-Equal (Get-E2EBlockPolicy -Id $id -Kind $kind) $action "the policy of ${id}:$kind"
        }
    }

    Test-Case 'Get-E2EStowLine accepts only the exact & ''<clone>\stow-all.ps1'' win line' {
        $clone = Join-Path $testRoot "stow line/o'brien home/dotfiles"
        $stow = Join-Path $clone 'stow-all.ps1'
        $line = "& $(ConvertTo-Quoted $stow) win"
        Assert-True $line.Contains("o''brien") 'the fixture line does not double its quote'
        $note = '# From an elevated PowerShell 7 (Run as administrator); it writes ~\.claude, ~\.codex and ~\.ssh.'
        $accepted = Get-E2EStowLine -Lines @($note, '', $line, '') -Clone $clone
        Assert-Equal $accepted['Line'] $line 'the printed line, a doubled quote and a space in the clone path'
        Assert-Equal $accepted['Error'] '' 'the printed line was refused'

        $parent = Split-Path -Parent $clone
        $other = Get-Path $parent 'elsewhere/stow-all.ps1'
        $full = Get-Path $clone 'stow-all.ps1'
        $refusals = @(
            @{ Lines = @($note); Error = 'the HW-stow block has 0 command lines, not 1' }
            @{ Lines = @($note, $line, $line); Error = 'the HW-stow block has 2 command lines, not 1' }
            @{ Lines = @($line, 'Set-ExecutionPolicy RemoteSigned -Scope CurrentUser'); Error = 'the HW-stow block has 2 command lines, not 1' }
            @{ Lines = @("& $(ConvertTo-Quoted $other) win"); Error = "the HW-stow line runs $other, not the clone's $full" }
            @{ Lines = @("& $(ConvertTo-Quoted (Join-Path $clone '../stow-all.ps1')) win")
                Error = "the HW-stow line runs $(Get-Path $parent 'stow-all.ps1'), not the clone's $full"
            }
            @{ Lines = @("& $(ConvertTo-Quoted (Join-Path $clone '../dotfiles-other/stow-all.ps1')) win")
                Error = "the HW-stow line runs $(Get-Path $parent 'dotfiles-other/stow-all.ps1'), not the clone's $full"
            }
            @{ Lines = @("& $(ConvertTo-Quoted (Join-Path $clone 'scripts/stow-all.ps1')) win")
                Error = "the HW-stow line runs $(Get-Path $clone 'scripts/stow-all.ps1'), not the clone's $full"
            }
        )
        foreach ($shape in @("$line -Strict", "& $(ConvertTo-Quoted $stow) wsl-ubuntu", "& $(ConvertTo-Quoted $stow)",
                "Remove-Item -Recurse -Force ~\.ssh; $line", "$line; Remove-Item -Recurse -Force ~\.ssh", "$line | Out-Null",
                ". $(ConvertTo-Quoted $stow) win", "& `"$stow`" win", "& '$stow' win", "  $line")) {
            $refusals += @{ Lines = @($shape); Error = "an HW-stow line the harness may not run: $shape" }
        }
        foreach ($refusal in $refusals) {
            $result = Get-E2EStowLine -Lines $refusal['Lines'] -Clone $clone
            Assert-Equal $result['Error'] $refusal['Error'] "refusal of $($refusal['Lines'] -join ' / ')"
            Assert-Equal $result['Line'] '' "a refused block still named a line: $($refusal['Lines'] -join ' / ')"
        }

        if ($IsWindows) {
            $runnerClone = 'C:\Users\runneradmin\dotfiles'
            $printed = "& 'C:\Users\runneradmin\dotfiles\stow-all.ps1' win"
            Assert-Equal (Get-E2EStowLine -Lines @($note, $printed) -Clone $runnerClone)['Line'] $printed 'the runner''s printed line'
            $cased = "& 'c:\users\RUNNERADMIN\dotfiles\STOW-ALL.ps1' win"
            Assert-Equal (Get-E2EStowLine -Lines @($cased) -Clone $runnerClone)['Line'] $cased 'NTFS paths compare without case'
            Assert-Equal (Get-E2EStowLine -Lines @("& 'C:\Users\runneradmin\dotfiles\..\stow-all.ps1' win") -Clone $runnerClone)['Error'] `
                "the HW-stow line runs C:\Users\runneradmin\stow-all.ps1, not the clone's C:\Users\runneradmin\dotfiles\stow-all.ps1" 'a drive-letter .. path'
        }
        else {
            Skip-Assertion 'drive-letter HW-stow lines (C:\Users\runneradmin\dotfiles) resolve only on Windows.'
        }
    }

    Test-Case 'setup-host.ps1 -PrintManual: each printed block meets its policy row, its HW-stow line is the one the harness runs' {
        $case = Reset-RunState
        Start-E2EStep print-manual check:print-manual
        $code = Invoke-Child -Arguments @('-NoProfile', '-NonInteractive', '-File', (Join-Path $sourceRoot 'setup-host.ps1'), '-Host', 'win', '-PrintManual') `
            -WorkingDirectory $case
        Assert-Equal $code 0 "setup-host.ps1 -PrintManual exit code: $([IO.File]::ReadAllText($E2E['StepErr']))"
        $blocks = @(ConvertFrom-E2EBlocks -Output @(Get-E2ELines $E2E['StepOut']) -Directory (Join-Path $case 'manual.blocks'))
        Assert-Equal (Get-E2EBlocksSummary $blocks) "HW-clone(gui) HW-stow(judgment) $ReminderSummary" 'the blocks setup-host.ps1 prints'
        Assert-Equal (@($blocks | ForEach-Object { Get-E2EBlockPolicy -Id $_.Id -Kind $_.Kind }) -join ' ') 'fail run-stow skip skip skip skip skip' 'their policies'
        $selected = Get-E2EStowLine -Lines @($blocks[1].Lines) -Clone $sourceRoot
        Assert-Equal $selected['Error'] '' 'the printed HW-stow line was refused'
        Assert-Equal $selected['Line'] "& $(ConvertTo-Quoted (Join-Path $sourceRoot 'stow-all.ps1')) win" 'the printed HW-stow line'
    }

    Test-Case 'Get-E2EPendingIds, Get-E2EFailureDetail, Get-E2EBlocksSummary and Get-E2EBlockText on setup-host output' {
        $pending = '[dotfiles] [warn] HUMAN steps pending: HW-clone HW-stow; run the HUMAN blocks above, then rerun .\setup-host.ps1'
        Assert-Equal (Get-E2EPendingIds (@(Get-WingetLines) + @($pending, ''))) 'HW-clone HW-stow' 'the pending ids'
        Assert-Equal (Get-E2EPendingIds (@(Get-WingetLines) + @('') + @($pending.Replace('HW-clone ', '')))) 'HW-stow' 'pending on the stderr half of the lines'
        Assert-Equal (Get-E2EPendingIds @(Get-WingetLines)) '' 'nothing pending'
        Assert-Equal (Get-E2EPendingIds @()) '' 'no lines'

        $winget = '[dotfiles] [error] W1-winget: winget exited 0x8A150046 (source agreements were not accepted) (docs/bootstrap.md W1-winget)'
        Assert-Equal (Get-E2EFailureDetail -Output (@(Get-WingetLines) + @($winget, '')) -Errors @('', '  ')) $winget 'the [error] line of stdout'
        Assert-Equal (Get-E2EFailureDetail -Output @($winget) -Errors @("[dotfiles] [error] second`twith a tab")) "$winget | [dotfiles] [error] second with a tab" '[error] lines of stdout, then stderr'
        Assert-Equal (Get-E2EFailureDetail -Output @(Get-WingetLines) -Errors @('Exception: first', 'Exception: last', '', '   ')) 'Exception: last' 'the last non-blank stderr line'
        Assert-Equal (Get-E2EFailureDetail -Output @('first', 'last', '') -Errors @('', ' ')) 'last' 'the last non-blank stdout line'
        Assert-Equal (Get-E2EFailureDetail -Output @('') -Errors @()) 'no output' 'nothing to report'
        Assert-Equal (Get-E2EFailureDetail -Output @('[error] ' + ('e' * 500))) ('[error] ' + ('e' * 392) + '...') 'a detail is cut at 400 characters'

        $blocks = @([pscustomobject]@{ Id = 'HW-stow'; Kind = 'judgment'; Lines = @('# note', "& 'x' win") }
            [pscustomobject]@{ Id = 'HW-auth'; Kind = 'auth'; Lines = @('gh auth login --git-protocol ssh') })
        Assert-Equal (Get-E2EBlocksSummary $blocks) 'HW-stow(judgment) HW-auth(auth)' 'id(kind) per block'
        Assert-Equal (Get-E2EBlocksSummary @()) '' 'no block'
        Assert-Equal (Get-E2EBlockText $blocks[0]) "# note | & 'x' win" 'a block as one detail line'
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
        $target = Join-Path $root 'dotfiles/common/git/.gitconfig'
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
            $relative = [IO.Path]::Combine('dotfiles', 'common', 'git', '.gitconfig')
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

    Test-Case 'Test-E2ENoted and Stop-E2ENoWrite: CryptnetUrlCache differences are noted, every other HOME difference fails (bug 4)' {
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
        Assert-True (-not (Test-E2ENoted "added $profileFile")) 'a HOME file'
        Assert-True (-not (Test-E2ENoted "changed $gitconfig (link|a -> 12|3)")) 'the stowed .gitconfig'

        [void](Reset-RunState)
        $script:Snapshots.Clear()
        $script:SnapshotCalls.Clear()
        $before = New-FakeSnapshot @{ $content = '1024|1'; $metadata = '620|1'; $gitconfig = 'link|x' }
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

            $script:Snapshots.Enqueue((New-FakeSnapshot @{ $content = '2048|2'; $metadata = '620|1'; "$noted\Content\NEW" = '512|2'; $gitconfig = 'link|x' }))
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
            $sorted = @(@("added $profileFile", "changed $gitconfig (link|x -> 1543|2)") + $cacheLines | Sort-Object)
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
        [IO.File]::WriteAllText((Join-Path $clone 'common/git/.gitconfig'), "[user]`n`tname = changed`n")
        Start-E2EStep login-shell check:login-shell
        Complete-E2EStep pass 'exit 0, silent'
        $dirtyLog = [IO.File]::ReadAllText($E2E['StepLog'])
        Start-E2EStep doctor-final check:doctor-final
        $E2E['Broken'] = 'doctor-final'
        Complete-E2EStep fail 'exit 1'
        $rows = @(Get-SummaryRows)
        Assert-Equal (Get-RowShape $rows) 'second-apply:pass login-shell:fail doctor-final:fail' 'the rows'
        Assert-Equal $rows[1].Detail 'exit 0, silent; clone not clean: M common/git/.gitconfig' 'the dirty clone in the detail'
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
                    @('[dotfiles] [error] .venv-sync is missing')) -join "`r`n"))
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

    Test-Case 'apply loop dry run: exit 3 with winget''s blank lines, HW-stow and the five reminders, then exit 0' {
        $clone = New-DryRun
        Add-Run 3 (Get-ApplyOutput -Clone $clone -Blocks (@('HW-stow') + $Reminders) -Pending 'HW-stow')
        Add-Run 0 (Get-ApplyOutput -Clone $clone -Blocks $Reminders -Done)
        Assert-True (Invoke-ApplyLoop) "the apply loop failed:`n$(Get-SummaryText)"
        $rows = @(Get-SummaryRows)
        Assert-Equal (Get-RowShape $rows) ('apply-1:pass HW-stow:pass HW-auto-stow-task:skip HW-execution-policy:skip ' +
            'HW-ssh-agent:skip HW-wsl:skip HW-auth:skip apply-2:pass') 'the rows'
        Assert-Equal $rows[0].Detail "exit 3; blocks: HW-stow(judgment) $ReminderSummary; pending: HW-stow" 'apply-1'
        $stowLine = "& $(ConvertTo-Quoted (Join-Path $clone 'stow-all.ps1')) win"
        Assert-Equal $rows[1].Detail ("1 line run as printed (run-stow); ~\.gitconfig -> $(Join-Path $clone 'common/git/.gitconfig'); " +
            'applied state recorded, 0 warnings') 'HW-stow'
        Assert-Equal $rows[4].Detail ('sudo block left to the person: # Elevated PowerShell (Run as administrator): | Set-Service -Name ssh-agent ' +
            '-StartupType Automatic | Start-Service -Name ssh-agent | # Then, as yourself, once HW-auth has created the key: ssh-add $HOME\.ssh\id_ed25519') 'a reminder'
        Assert-Equal $rows[7].Detail 'exit 0 after 2 run(s); 4 done, 1 skip' 'apply-2'
        Assert-Equal "$($E2E['Passes']) $($E2E['Fails']) $($E2E['Skips']) [$($E2E['Broken'])]" '3 0 5 []' 'counters and Broken'
        Assert-Equal (@($script:PwshCalls | ForEach-Object { "$($_.Script) $($_.Arguments) $($_.Timeout)" }) -join '; ') `
            'setup-host.ps1 -Host win -Yes 3600; setup-host.ps1 -Host win -Yes 3600' 'the setup-host.ps1 runs'
        Assert-Equal $script:ProcessCalls.Count 1 'HW-stow line runs'
        $call = $script:ProcessCalls[0]
        Assert-Equal $call.FilePath $E2E['PowerShell'] 'the stow child'
        Assert-Equal $call.Arguments '-NoProfile -NonInteractive -Command Invoke-Expression -Command $env:E2E_BLOCK_LINE' 'its arguments'
        Assert-Equal $call.Line $stowLine 'the line reaches it through E2E_BLOCK_LINE, as printed'
        Assert-Equal "$($call.WorkingDirectory) $($call.Timeout)" "$HOME 2700" 'it runs from HOME under the block timeout'
        $blocks = Join-Path $E2E['Out'] 'steps/01-apply-1.blocks'
        Assert-Equal (Read-Utf8 (Join-Path $blocks 'index')).Split("`n")[0] "1`tHW-stow`tjudgment" 'apply-1''s blocks were saved'
        Assert-True ([IO.File]::ReadAllText((Join-Path $E2E['Out'] 'steps/02-HW-stow.log')).StartsWith(
                "--- block`n# From an elevated PowerShell 7 (Run as administrator); it writes ~\.claude, ~\.codex and ~\.ssh.`n$stowLine`n")) 'the HW-stow log starts with its block'
        $phases = @(Get-E2ELines (Join-Path $E2E['Out'] 'log/timeline') | Where-Object { $_ } | ForEach-Object { $_.Split("`t", 2)[1].Replace("`t", ' ') })
        Assert-Equal ($phases -join ', ') ('begin setup:apply-1, end setup:apply-1, begin human:HW-stow, end human:HW-stow, ' +
            'begin setup:apply-2, end setup:apply-2') 'the timeline'
    }

    Test-Case 'Invoke-E2EBlocks records each reminder once across runs' {
        $clone = New-DryRun
        $blocks = @(ConvertFrom-E2EBlocks -Output (Get-ApplyOutput -Clone $clone -Blocks $Reminders) -Directory (Join-Path $E2E['Out'] 'reminders'))
        Assert-True (Invoke-E2EBlocks -Blocks $blocks) 'the first run of reminders'
        Assert-True (Invoke-E2EBlocks -Blocks $blocks) 'the second run of reminders'
        Assert-Equal (Get-RowShape @(Get-SummaryRows)) 'HW-auto-stow-task:skip HW-execution-policy:skip HW-ssh-agent:skip HW-wsl:skip HW-auth:skip' 'one skip row each'
        Assert-True (Invoke-E2EBlocks -Blocks @()) 'no blocks'
    }

    Test-Case 'apply loop dry run: HW-stow passes only with the applied state recorded and no WARNING line (bug 3)' {
        $missing = 'applied state missing at '
        $rule = ' (stow-all.ps1 records it only on a warning-free run)'
        foreach ($scenario in @(
                @{ Mode = 'warn-stdout'; Detail = "stow-all.ps1 exited 0 with 1 warning(s), $missing"; Warned = $true }
                @{ Mode = 'warn-stderr'; Detail = "stow-all.ps1 exited 0 with 1 warning(s), $missing"; Warned = $true }
                @{ Mode = 'warn-with-state'; Detail = "stow-all.ps1 exited 0 with 1 warning(s), applied state recorded$rule"; Warned = $true }
                @{ Mode = 'no-state'; Detail = "stow-all.ps1 exited 0 with 0 warning(s), $missing"; Warned = $false })) {
            $clone = New-DryRun -StowMode $scenario['Mode']
            Add-Run 3 (Get-ApplyOutput -Clone $clone -Blocks (@('HW-stow') + $Reminders) -Pending 'HW-stow')
            Add-Run 0 (Get-ApplyOutput -Clone $clone -Done)
            Assert-True (-not (Invoke-ApplyLoop)) "$($scenario['Mode']): the apply loop passed"
            $rows = @(Get-SummaryRows)
            Assert-Equal (Get-RowShape $rows) 'apply-1:pass HW-stow:fail' "$($scenario['Mode']): the rows"
            $detail = $rows[1].Detail
            Assert-True $detail.StartsWith($scenario['Detail']) "$($scenario['Mode']): $detail"
            if ($scenario['Detail'].EndsWith($missing)) {
                $state = [IO.Path]::Combine('dotfiles-sync-windows', 'configuration.json')
                Assert-True $detail.Contains("$state$rule") "$($scenario['Mode']): the state path: $detail"
            }
            Assert-Equal $detail.EndsWith(": $StowWarning") $scenario['Warned'] "$($scenario['Mode']): the warning quoted"
            Assert-Equal "$($E2E['Broken']) $($script:PwshCalls.Count) $($script:Runs.Count)" 'HW-stow 1 1' "$($scenario['Mode']): Broken, runs made and left"
        }

        $clone = New-DryRun -StowMode 'exit-1'
        Add-Run 3 (Get-ApplyOutput -Clone $clone -Blocks @('HW-stow') -Pending 'HW-stow')
        Assert-True (-not (Invoke-ApplyLoop)) 'a failing stow line passed'
        Assert-Equal @(Get-SummaryRows)[-1].Detail ("line 1 exited 1 (& $(ConvertTo-Quoted (Join-Path $clone 'stow-all.ps1')) win): " +
            'Exception: Stow dry run found a conflict at C:\Users\runneradmin\.gitconfig') 'the stow line''s exit code and stderr'

        $clone = New-DryRun
        $script:Stowed = @{ Done = $false; Detail = '~\.gitconfig is a regular file (1543 bytes), not a symlink' }
        Add-Run 3 (Get-ApplyOutput -Clone $clone -Blocks @('HW-stow') -Pending 'HW-stow')
        Assert-True (-not (Invoke-ApplyLoop)) 'a stow without the link passed'
        Assert-Equal @(Get-SummaryRows)[-1].Detail 'stow-all.ps1 exited 0, but ~\.gitconfig is a regular file (1543 bytes), not a symlink' 'HW-stow''s verify'

        $clone = New-DryRun
        Add-Run 3 (Get-ApplyOutput -Clone $clone -Blocks @('HW-stow') -Pending 'HW-stow')
        $result = @(Use-DryRun {
                function Get-E2EGitOutput {
                    param([string[]]$Arguments)
                    if ($Arguments -contains 'rev-parse') { return [pscustomobject]@{ Code = 128; Text = 'fatal: not a git repository: .git' } }
                    return [pscustomobject]@{ Code = 0; Text = '' }
                }
                Invoke-E2EApplyLoop
            })
        Assert-True (-not $result[0]) 'a stow whose git dir is unknown passed'
        Assert-Equal @(Get-SummaryRows)[-1].Detail 'git rev-parse --absolute-git-dir exited 128 in the clone: fatal: not a git repository: .git' 'the rev-parse failure'
        Assert-Equal $E2E['Broken'] 'HW-stow' 'Broken'
    }

    Test-Case 'apply loop dry run: a pending HW-clone fails the run before the stow, wherever it is printed (bug 2)' {
        foreach ($order in @(@('HW-clone', 'HW-stow'), @('HW-stow', 'HW-clone'))) {
            $clone = New-DryRun
            Add-Run 3 (Get-ApplyOutput -Clone $clone -Blocks (@($order) + $Reminders) -Pending 'HW-clone HW-stow')
            Add-Run 0 (Get-ApplyOutput -Clone $clone -Done)
            Assert-True (-not (Invoke-ApplyLoop)) "$($order -join ', '): the apply loop passed"
            $rows = @(Get-SummaryRows)
            Assert-Equal (Get-RowShape $rows) 'apply-1:pass HW-clone:fail' "$($order -join ', '): the rows"
            $kinds = @{ 'HW-clone' = 'gui'; 'HW-stow' = 'judgment' }
            Assert-Equal $rows[0].Detail "exit 3; blocks: $($order[0])($($kinds[$order[0]])) $($order[1])($($kinds[$order[1]])) $ReminderSummary; pending: HW-clone HW-stow" `
                "$($order -join ', '): apply-1"
            Assert-True $rows[1].Detail.StartsWith('gui block the harness must not run: # Turn on Developer Mode (Settings > System > For developers)') `
                "$($order -join ', '): $($rows[1].Detail)"
            Assert-Equal "$($E2E['Broken']) $($script:ProcessCalls.Count) $($script:PwshCalls.Count)" 'HW-clone 0 1' "$($order -join ', '): Broken, stow runs, setup-host runs"
        }
    }

    Test-Case 'apply loop dry run: an HW-stow block holding another line is refused before anything runs' {
        $clone = New-DryRun
        $other = Join-Path (Split-Path -Parent $clone) 'other/stow-all.ps1'
        Add-Run 3 (@(Get-WingetLines) + @('HUMAN-BEGIN HW-stow judgment', '# From an elevated PowerShell 7', "& $(ConvertTo-Quoted $other) win", 'HUMAN-END',
                '[dotfiles] [warn] HUMAN steps pending: HW-stow; run the HUMAN blocks above, then rerun .\setup-host.ps1'))
        Assert-True (-not (Invoke-ApplyLoop)) 'a foreign stow line passed'
        $rows = @(Get-SummaryRows)
        Assert-Equal (Get-RowShape $rows) 'apply-1:pass HW-stow:fail' 'the rows'
        Assert-Equal $rows[1].Detail ("judgment block refused: the HW-stow line runs $other, not the clone's $(Join-Path $clone 'stow-all.ps1'); " +
            "block: # From an elevated PowerShell 7 | & $(ConvertTo-Quoted $other) win") 'the refusal'
        Assert-Equal "$($E2E['Broken']) $($script:ProcessCalls.Count)" 'HW-stow 0' 'Broken and stow runs'
    }

    Test-Case 'apply loop dry run: no progress, exit 1, exit 2 and a timeout fail with what setup-host reported' {
        $clone = New-DryRun
        Add-Run 3 (Get-ApplyOutput -Clone $clone -Blocks $Reminders -Pending 'HW-stow')
        Assert-True (-not (Invoke-ApplyLoop)) 'exit 3 with reminders only passed'
        Assert-Equal (Get-SummaryText) "1`tapply-1`tfail`t$(@(Get-SummaryRows)[0].Seconds)`tno progress: exit 3 with no block the harness may run (pending: HW-stow; blocks: $ReminderSummary)`n" 'no progress, no skip rows'
        Assert-Equal "$($E2E['Broken']) $($script:ProcessCalls.Count)" 'apply-1 0' 'Broken and stow runs'

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

    Test-Case 'apply loop dry run: eight exit-3 runs without an exit 0 fail as apply-loop' {
        $clone = New-DryRun
        foreach ($n in 1..8) { Add-Run 3 (Get-ApplyOutput -Clone $clone -Blocks @('HW-stow') -Pending 'HW-stow') }
        Add-Run 0 (Get-ApplyOutput -Clone $clone -Done)
        Assert-True (-not (Invoke-ApplyLoop)) 'eight exit-3 runs passed'
        $rows = @(Get-SummaryRows)
        Assert-Equal $rows.Count 17 'eight apply rows, eight HW-stow rows and the verdict'
        Assert-Equal "$($rows[-1].Step) $($rows[-1].Status) $($rows[-1].Detail)" 'apply-loop fail eight apply runs without an exit 0' 'the verdict'
        Assert-Equal "$($E2E['Broken']) $($script:PwshCalls.Count) $($script:ProcessCalls.Count) $($script:Runs.Count)" 'apply-loop 8 8 1' 'Broken, runs, stows, runs left'
    }

    Test-Case 'no-write step dry runs: noted cache entries pass, a HOME write, a TEMP leftover or redone work fail' {
        $noted = [IO.Path]::Combine($HOME, 'AppData', 'LocalLow', 'Microsoft', 'CryptnetUrlCache')
        $gitconfig = [IO.Path]::Combine($HOME, '.gitconfig')
        $before = New-FakeSnapshot @{ $gitconfig = 'link|x' }
        $cacheOnly = New-FakeSnapshot @{ $gitconfig = 'link|x'; "$noted\Content\A1" = '1024|2' }
        $written = New-FakeSnapshot @{ $gitconfig = '1543|2'; "$noted\Content\A1" = '1024|2' }
        $plan = @('W1-winget todo winget import of 24 missing tools', 'W1-psresources todo Install-PSResource PSFzf -Scope CurrentUser',
            'W1-font todo oh-my-posh font install CascadiaMono, once W1-winget installs oh-my-posh', 'W1-bat-theme done present',
            'W1-setup-sync todo run .\setup-sync.ps1 once Python >= 3.11 is on PATH (W1-winget installs it)', 'HW-clone done already done',
            'HW-stow human judgment step for a person; blocking') + @($Reminders | ForEach-Object { "$_ human step for a person; not blocking" })

        $clone = New-DryRun
        Add-Run 3 $plan
        $script:Snapshots.Enqueue($before); $script:Snapshots.Enqueue($cacheOnly)
        Use-DryRun { Invoke-E2EStepCheckNoWrite }
        $call = $script:PwshCalls[0]
        $temp = Join-Path $E2E['Out'] 'tmp/check-nowrite'
        Assert-Equal "$($call.Script) $($call.Arguments) $($call.Timeout)" 'setup-host.ps1 -Host win -Check 900' 'the -Check run'
        Assert-Equal "$($call.Environment['TEMP'])|$($call.Environment['TMP'])" "$temp|$temp" 'its TEMP and TMP'
        Assert-Equal @(Get-SummaryRows)[0].Detail 'exit 3; 4 todo, 6 human; no writes' 'a noted cache entry passes -Check'
        Assert-Equal (Read-Utf8 (Join-Path $E2E['Out'] 'snapshots/check-nowrite.diff')) "noted added $noted\Content\A1`n" 'the noted diff'

        $clone = New-DryRun
        Add-Run 3 $plan
        $script:Snapshots.Enqueue($before); $script:Snapshots.Enqueue($written)
        Use-DryRun { Invoke-E2EStepCheckNoWrite }
        Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" "fail exit 3; HOME written (1 difference(s)): changed $gitconfig (link|x -> 1543|2)" 'a HOME write fails -Check'

        $clone = New-DryRun
        Add-Run 1 @('[dotfiles] [error] Invalid manifest: tools.tsv row 12 has 7 cells')
        $script:Snapshots.Enqueue($before); $script:Snapshots.Enqueue($before)
        Use-DryRun { Invoke-E2EStepCheckNoWrite }
        Assert-Equal "$(@(Get-SummaryRows)[0].Status) $(@(Get-SummaryRows)[0].Detail)" 'fail exit 1: [dotfiles] [error] Invalid manifest: tools.tsv row 12 has 7 cells' '-Check exit 1'

        $clone = New-DryRun
        Add-Run 0 (Get-ApplyOutput -Clone $clone -Blocks $Reminders -Done)
        $script:Snapshots.Enqueue($before); $script:Snapshots.Enqueue($cacheOnly)
        Use-DryRun { Invoke-E2EStepSecondApply }
        Assert-Equal "$($script:PwshCalls[0].Arguments) $($script:PwshCalls[0].Timeout)" '-Host win -Yes 3600' 'the second -Yes'
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

    Test-Case 'Invoke-E2EFlowWin runs the steps in order and, once one breaks the flow, skips what depends on it' {
        $script:FlowCalls = [Collections.Generic.List[string]]::new()
        $script:BreakAt = ''
        function Complete-FlowStub([string]$Name) {
            $script:FlowCalls.Add($Name)
            Start-E2EStep $Name "stub:$Name"
            if ($Name -ceq $script:BreakAt) { $E2E['Broken'] = $Name; Complete-E2EStep fail 'stub failure' }
            else { Complete-E2EStep pass 'stub' }
        }
        function Invoke-E2EStepClone { Complete-FlowStub clone }
        function Invoke-E2EStepWinget { Complete-FlowStub winget }
        function Invoke-E2EStepDoctorInitial { Complete-FlowStub doctor-initial }
        function Invoke-E2EStepCheckNoWrite { Complete-FlowStub check-nowrite }
        function Invoke-E2EApplyLoop { Complete-FlowStub apply-1; return ($script:BreakAt -cne 'apply-1') }
        function Invoke-E2EStepSecondApply { Complete-FlowStub second-apply }
        function Invoke-E2EStepLoginShell { Complete-FlowStub login-shell }
        function Invoke-E2EStepDoctorFinal { Complete-FlowStub doctor-final }
        $steps = @('clone', 'winget', 'doctor-initial', 'check-nowrite', 'apply-1', 'second-apply', 'login-shell', 'doctor-final')
        foreach ($breakAt in @('', 'clone', 'check-nowrite', 'apply-1')) {
            [void](Reset-RunState)
            $script:FlowCalls.Clear()
            $script:BreakAt = $breakAt
            Invoke-E2EFlowWin
            $ran = if ($breakAt) { [array]::IndexOf($steps, $breakAt) + 1 } else { $steps.Count }
            Assert-Equal ($script:FlowCalls -join ' ') ($steps[0..($ran - 1)] -join ' ') "break at '$breakAt': the steps run"
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
