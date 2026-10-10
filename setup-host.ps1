#Requires -Version 7.0
<#
.SYNOPSIS
    Day-zero installer for the win host - the thin Windows twin of setup-host.sh.

.DESCRIPTION
    Runs five steps in order, each checked first and applied only when it is
    todo, then prints the person-only steps as HUMAN blocks:

      W1-winget       winget import config/bootstrap/winget.json --no-upgrade
      W1-psresources  Install-PSResource PSFzf, CompletionPredictor and
                      Microsoft.WinGet.CommandNotFound -Scope CurrentUser
      W1-font         oh-my-posh font install CascadiaMono (needs oh-my-posh)
      W1-bat-theme    the pinned Catppuccin Mocha theme, sha256-checked, into
                      %APPDATA%\bat\themes, then bat cache --build
      W1-setup-sync   .\setup-sync.ps1 -Python <the first python3 or python on
                      PATH that reports 3.11 or newer; a Microsoft Store
                      alias does not count> (the only write inside this
                      checkout); done when .venv-sync passes
                      lib/config_sync.py --runtime-check

    A step runs when a selected tier needs it: tools.tsv rows whose Windows
    docs step is W1-winget, W1-psresources, W1-font or W1-bat-theme decide
    their step's tiers; W1-setup-sync is core.

    HUMAN blocks follow the shared grammar (HUMAN-BEGIN <step-id> <kind>,
    command lines, HUMAN-END) for HW-clone, HW-stow, HW-auto-stow-task,
    HW-execution-policy, HW-ssh-agent, HW-wsl and HW-auth. This script never
    elevates itself, never runs stow-all.ps1 and never edits a profile or rc
    file; elevated steps are left to a person.

    Exit codes: 0 done (non-blocking HUMAN blocks may still be printed);
    1 a step failed; 2 usage error, invalid manifest, or refusal (a
    non-interactive run without -Yes, or a declined prompt); 3 work remains:
    a blocking HUMAN step is pending (HW-clone or HW-stow), or, under
    -Check, a step is still to apply. As in setup-host.sh, the other HUMAN
    steps (HW-auto-stow-task, HW-execution-policy, HW-ssh-agent, HW-wsl,
    HW-auth) are printed while pending but leave the exit code alone;
    .\doctor.ps1 -Online then shows whether sign-in is done.

.PARAMETER HostName
    Alias -Host. Only win is accepted; use ./setup-host.sh on Unix.

.PARAMETER Tier
    all, or a comma list of core, cli, ai, desktop, contributor, host.
    Defaults to core,cli,ai.

.PARAMETER Check
    Print one plan line per step, "<step-id> <done|todo|human|skip> <detail>",
    and change nothing: no writes and no network. Exits 3 while a step is
    todo or a blocking HUMAN step is pending, as setup-host.sh --check does.

.PARAMETER Yes
    Apply without asking. Required when the session is not interactive.

.PARAMETER PrintManual
    Print every HUMAN block and exit 0 without checking or applying anything.

.EXAMPLE
    .\setup-host.ps1 -Check

.EXAMPLE
    .\setup-host.ps1 -Tier all -Yes
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [Alias('Host')]
    [string]$HostName = 'win',
    [string]$Tier = 'core,cli,ai',
    [switch]$Check,
    [switch]$Yes,
    [switch]$PrintManual
)

Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false

$RepoRoot = $PSScriptRoot
function Write-DotfilesLog {
    param([string]$Level, [string]$Message)
    Write-Host "[dotfiles] [$Level] $Message"
}
try {
    $terminalLibrary = Join-Path $RepoRoot 'lib/terminal.ps1'
    if (Test-Path -LiteralPath $terminalLibrary -PathType Leaf) { . $terminalLibrary }
} catch { } # Plain diagnostics remain usable in a partial checkout.

$AutomatedSteps = @('W1-winget', 'W1-psresources', 'W1-font', 'W1-bat-theme', 'W1-setup-sync')
$HumanSteps = @('HW-clone', 'HW-stow', 'HW-auto-stow-task', 'HW-execution-policy', 'HW-ssh-agent', 'HW-wsl', 'HW-auth')
# A pending blocking step makes the run exit 3 (setup-host.sh's "blocking").
$BlockingHumanSteps = @('HW-clone', 'HW-stow')

function New-SetupState {
    param([string]$Id, [ValidateSet('done', 'todo', 'human', 'skip')][string]$Status, [string]$Detail)
    return [pscustomobject]@{ Id = $Id; Status = $Status; Detail = ($Detail -replace '[\t\r\n]+', ' ') }
}

function Get-SetupStepRows {
    # Selected-tier tools.tsv rows for the win host whose Windows docs step is Step.
    param([Parameter(Mandatory)][string]$Step)
    return @($script:ToolRows | Where-Object {
            (Get-BootstrapDocRef -Step $_.doc -ProfileName windows) -ceq $Step -and
            (Test-BootstrapTierSelected $_.tier $Tier)
        })
}

function Get-SetupMissingNames {
    # Rows with a floor are probed with their version flag, so a Microsoft
    # Store alias stub (python.exe in WindowsApps) does not pass for Python.
    param([object[]]$Rows)
    return @($Rows | Where-Object {
            $flag = if ($_.floor -cne '-') { $_.version_flag } else { '-' }
            -not (Test-BootstrapTool -Probe $_.probe -VersionFlag $flag).Found
        } | ForEach-Object { $_.id })
}

function Get-SetupBatThemeRow {
    $rows = @($script:InstallerRows | Where-Object {
            $_.id -ceq 'bat-theme' -and $_.arch -ceq 'any' -and (Test-BootstrapHostMatch $_.hosts win)
        })
    if ($rows.Count -ne 1 -or $rows[0].kind -cne 'file') {
        throw [IO.InvalidDataException]::new('installers.tsv needs exactly one any-arch file row for bat-theme on win')
    }
    if ($rows[0].url -cnotmatch '^https://' -or $rows[0].sha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw [IO.InvalidDataException]::new('installers.tsv bat-theme needs an https url and a 64-digit lowercase hex sha256')
    }
    return $rows[0]
}

function Assert-SetupWingetManifest {
    # winget import reads the file itself; check only that it is the export
    # shape with at least one package, so a broken file is exit 2, not 1.
    param([Parameter(Mandatory)][string]$Path)
    try {
        $manifest = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
        $count = @($manifest.Sources[0].Packages | Where-Object { $_.PackageIdentifier }).Count
    }
    catch { throw [IO.InvalidDataException]::new("${Path}: $($_.Exception.Message)") }
    if (-not $count) { throw [IO.InvalidDataException]::new("${Path}: no PackageIdentifier entries") }
}

function Get-SetupSyncPythonSpec {
    # What W1-setup-sync hands to setup-sync.ps1 -Python: the tools.tsv
    # python3 row's probe, version flag and floor (Select-BootstrapCommand).
    $row = @($script:ToolRows | Where-Object { $_.id -ceq 'python3' -and $_.floor -cne '-' }) | Select-Object -First 1
    if ($row) { return @{ Probe = $row.probe; VersionFlag = $row.version_flag; Floor = $row.floor } }
    return @{ Probe = 'python3,python'; VersionFlag = '--version'; Floor = '3.11' }
}

function Test-SetupVenvReady {
    # Ready means runnable with the pinned dependency, not merely present: a
    # failed first setup-sync.ps1 leaves a venv without tomlkit.
    return Test-BootstrapSyncRuntime -Python (Get-BootstrapVenvPython $RepoRoot) -RepoRoot $RepoRoot
}

function Get-SetupStepState {
    # Read-only and offline: PATH, file, module-directory and font probes.
    param([Parameter(Mandatory)][string]$Id, [Collections.IDictionary]$Earlier = @{})
    switch -CaseSensitive ($Id) {
        'W1-winget' {
            $rows = @(Get-SetupStepRows W1-winget)
            if (-not $rows.Count) { return New-SetupState $Id skip 'no selected tier installs from winget' }
            $missing = @(Get-SetupMissingNames $rows)
            if (-not $missing.Count) { return New-SetupState $Id done "$($rows.Count) winget tools on PATH" }
            $detail = "missing: $($missing -join ', ')"
            if (-not (Find-BootstrapCommand 'winget')) { $detail += '; winget is not on PATH (install App Installer)' }
            return New-SetupState $Id todo $detail
        }
        'W1-psresources' {
            $rows = @(Get-SetupStepRows W1-psresources | Where-Object { (Get-BootstrapProbe $_.probe).Kind -ceq 'psmodule' })
            if (-not $rows.Count) { return New-SetupState $Id skip 'no selected tier needs PowerShell modules' }
            $missing = @($rows | Where-Object { -not (Test-BootstrapTool -Probe $_.probe).Found } |
                    ForEach-Object { (Get-BootstrapProbe $_.probe).Value })
            if (-not $missing.Count) { return New-SetupState $Id done "$($rows.Count) modules installed" }
            return New-SetupState $Id todo "Install-PSResource $($missing -join ', ') -Scope CurrentUser"
        }
        'W1-font' {
            $rows = @(Get-SetupStepRows W1-font)
            if (-not $rows.Count) { return New-SetupState $Id skip 'no selected tier needs the Nerd Font' }
            if (-not @(Get-SetupMissingNames $rows).Count) { return New-SetupState $Id done 'CaskaydiaMono Nerd Font installed' }
            if (Find-BootstrapCommand 'oh-my-posh') { return New-SetupState $Id todo 'oh-my-posh font install CascadiaMono' }
            if ($Earlier.Contains('W1-winget') -and $Earlier['W1-winget'].Status -ceq 'todo') {
                return New-SetupState $Id todo 'oh-my-posh font install CascadiaMono, once W1-winget installs oh-my-posh'
            }
            return New-SetupState $Id skip 'oh-my-posh is not on PATH, so the font is not installed'
        }
        'W1-bat-theme' {
            $rows = @(Get-SetupStepRows W1-bat-theme)
            if (-not $rows.Count) { return New-SetupState $Id skip 'no selected tier needs the bat theme' }
            $destination = Expand-BootstrapPath (Get-SetupBatThemeRow).dest
            if ([IO.File]::Exists($destination)) { return New-SetupState $Id done "present at $destination" }
            return New-SetupState $Id todo "fetch the pinned theme into $destination"
        }
        'W1-setup-sync' {
            if (-not (Test-BootstrapTierSelected core $Tier)) { return New-SetupState $Id skip 'tier core not selected' }
            if (Test-SetupVenvReady) { return New-SetupState $Id done '.venv-sync passes the runtime check' }
            $spec = Get-SetupSyncPythonSpec
            $python = Select-BootstrapCommand @spec
            if ($python.Path) { return New-SetupState $Id todo "run .\setup-sync.ps1 -Python $($python.Path)" }
            return New-SetupState $Id todo "run .\setup-sync.ps1 once Python >= $($spec.Floor) is on PATH (W1-winget installs it)"
        }
    }
    throw "Unknown step $Id"
}

function Test-SetupStowed {
    # HW-stow is done when ~/.gitconfig links to this checkout's common copy.
    $link = Get-Item -LiteralPath (Join-Path $HOME '.gitconfig') -Force -ErrorAction SilentlyContinue
    $property = if ($link) { $link.PSObject.Properties['LinkTarget'] } else { $null }
    if ($null -eq $property -or -not $property.Value) { return $false }
    $target = [string]$property.Value
    if (-not [IO.Path]::IsPathRooted($target)) { $target = Join-Path (Split-Path -Parent $link.FullName) $target }
    $expected = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'common/git/.gitconfig'))
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    return [IO.Path]::GetFullPath($target).Equals($expected, $comparison)
}

function Get-SetupFirstPolicy {
    # The first execution policy in precedence order that is set, or ''.
    param([AllowNull()][object[]]$Values)
    foreach ($value in $Values) { if ("$value" -and "$value" -cne 'Undefined') { return "$value" } }
    return ''
}

function Test-SetupExecutionPolicy {
    # Both shells' own scopes must allow local scripts. PowerShell 7: Group
    # Policy, then CurrentUser; LocalMachine is no evidence, because pwsh's
    # $PSHOME\powershell.config.json already sets it to RemoteSigned on
    # Windows. Windows PowerShell 5.1 (it loads the stowed WindowsPowerShell
    # profile) keeps its own settings in the registry, Restricted by default.
    $allowed = @('RemoteSigned', 'Unrestricted', 'Bypass')
    $list = @(Get-ExecutionPolicy -List -ErrorAction SilentlyContinue)
    $pwsh = foreach ($scope in @('MachinePolicy', 'UserPolicy', 'CurrentUser')) {
        $list | Where-Object { "$($_.Scope)" -ceq $scope } | Select-Object -First 1 | ForEach-Object { "$($_.ExecutionPolicy)" }
    }
    $desktop = foreach ($key in @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell',
            'HKCU:\SOFTWARE\Policies\Microsoft\Windows\PowerShell',
            'HKCU:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell')) {
        Get-ItemProperty -LiteralPath $key -Name ExecutionPolicy -ErrorAction SilentlyContinue |
            ForEach-Object { "$($_.ExecutionPolicy)" }
    }
    return (Get-SetupFirstPolicy $pwsh) -cin $allowed -and (Get-SetupFirstPolicy $desktop) -cin $allowed
}

function Test-SetupHumanDone {
    # Offline, read-only evidence that a person already did the step. Checks
    # that need Windows APIs report not done elsewhere.
    param([Parameter(Mandatory)][string]$Id)
    switch -CaseSensitive ($Id) {
        'HW-clone' {
            $git = Find-BootstrapCommand 'git'
            if (-not $git) { return $false }
            $value = @(& $git --no-optional-locks -C $RepoRoot config --get core.symlinks 2>$null) -join ''
            return $value -ceq 'true'
        }
        'HW-stow' { return Test-SetupStowed }
        'HW-auto-stow-task' {
            $autoStow = Join-Path $RepoRoot 'scripts/dotfiles-auto-stow.ps1'
            if (-not $IsWindows -or -not (Test-Path -LiteralPath $autoStow -PathType Leaf)) { return $false }
            # Without switches the script only defines functions, here in
            # this function's scope; its task name is keyed to this checkout.
            . $autoStow
            return [bool](Get-ScheduledTask -TaskName (Get-DotfilesTaskName $RepoRoot) -ErrorAction SilentlyContinue)
        }
        'HW-execution-policy' {
            if (-not $IsWindows) { return $false }
            return Test-SetupExecutionPolicy
        }
        'HW-ssh-agent' {
            if (-not $IsWindows) { return $false }
            $service = Get-Service -Name ssh-agent -ErrorAction SilentlyContinue
            return $null -ne $service -and "$($service.StartType)" -ceq 'Automatic'
        }
        'HW-wsl' {
            if (-not $IsWindows) { return $false }
            $lxss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
            $names = @(Get-ChildItem -LiteralPath $lxss -ErrorAction SilentlyContinue |
                    ForEach-Object { $_.GetValue('DistributionName') })
            return $names -ccontains 'Ubuntu'
        }
    }
    return $false
}

function ConvertTo-SetupQuoted {
    # A single-quoted PowerShell literal, so a pasted path never expands $
    # or backticks (CodeGeneration also doubles the typographic quotes).
    param([Parameter(Mandatory)][string]$Text)
    return "'" + [Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Text) + "'"
}

function Get-SetupHumanBlock {
    # Kind and lines for one HUMAN step. Each line is a '# ' note or a
    # self-contained command: no Set-Location or variable carries over.
    param([Parameter(Mandatory)][string]$Id)
    $repo = ConvertTo-SetupQuoted $RepoRoot
    switch -CaseSensitive ($Id) {
        'HW-clone' {
            return @{ Kind = 'gui'; Lines = @(
                    '# Turn on Developer Mode (Settings > System > For developers) so Git can create symlinks.'
                    '# A fresh clone: git clone -c core.symlinks=true --recurse-submodules <repository URL>'
                    "git -C $repo config core.symlinks true"
                    "git -C $repo checkout -- common/pymol"
                ) }
        }
        'HW-stow' {
            return @{ Kind = 'judgment'; Lines = @(
                    '# From an elevated PowerShell 7 (Run as administrator); it writes ~\.claude, ~\.codex and ~\.ssh.'
                    "& $(ConvertTo-SetupQuoted (Join-Path $RepoRoot 'stow-all.ps1')) win"
                ) }
        }
        'HW-auto-stow-task' {
            return @{ Kind = 'judgment'; Lines = @(
                    '# Optional, elevated PowerShell 7: lets the login updater restow without a UAC prompt.'
                    "& $(ConvertTo-SetupQuoted (Join-Path (Join-Path $RepoRoot 'scripts') 'dotfiles-auto-stow.ps1')) -Register"
                ) }
        }
        'HW-execution-policy' {
            return @{ Kind = 'judgment'; Lines = @(
                    '# Lets the stowed profiles and these scripts run. PowerShell 7 and Windows PowerShell 5.1 keep separate settings.'
                    'Set-ExecutionPolicy RemoteSigned -Scope CurrentUser'
                    'powershell.exe -NoProfile -Command Set-ExecutionPolicy RemoteSigned -Scope CurrentUser'
                ) }
        }
        'HW-ssh-agent' {
            return @{ Kind = 'sudo'; Lines = @(
                    '# Elevated PowerShell (Run as administrator):'
                    'Set-Service -Name ssh-agent -StartupType Automatic'
                    'Start-Service -Name ssh-agent'
                    '# Then, as yourself, once HW-auth has created the key: ssh-add $HOME\.ssh\id_ed25519'
                ) }
        }
        'HW-wsl' {
            return @{ Kind = 'judgment'; Lines = @(
                    '# Optional, elevated PowerShell. Windows Terminal and WezTerm profiles need the distro named exactly Ubuntu.'
                    '# .\stow-all.ps1 win links win\wsl into your home. ~\.wslconfig sizes WSL memory and processors for one machine: review it, then wsl --shutdown.'
                    '# ~\wsl.conf applies only when copied to /etc/wsl.conf inside the distro; the tracked one runs /usr/local/bin/mount-data.sh, which this repository does not ship, and hardcodes a default user.'
                    '# ~\mount.vbs mounts one specific physical disk; do not schedule it on another machine.'
                    'wsl --install -d Ubuntu'
                ) }
        }
        'HW-auth' {
            return @{ Kind = 'auth'; Lines = @(
                    '# Sign in, then check with .\doctor.ps1 -Online. Skip gh auth setup-git: it would write the stowed ~\.gitconfig.'
                    'ssh-keygen -t ed25519 -f $HOME\.ssh\id_ed25519'
                    'gh auth login --git-protocol ssh'
                    'claude auth login'
                    'codex login'
                ) }
        }
    }
    throw "Unknown HUMAN step $Id"
}

function Write-SetupHumanBlock {
    param([Parameter(Mandatory)][string]$Id)
    $block = Get-SetupHumanBlock $Id
    Write-BootstrapHumanBlock -Step $Id -Kind $block.Kind -Line $block.Lines
}

function Test-SetupInteractive {
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { return $false }
    foreach ($argument in [Environment]::GetCommandLineArgs()) {
        if ($argument -match '^[-/]noni') { return $false }
    }
    return [Environment]::UserInteractive
}

function Invoke-SetupStep {
    # Apply one todo step; returns a lib/bootstrap.ps1 result object.
    param([Parameter(Mandatory)][string]$Id)
    switch -CaseSensitive ($Id) {
        'W1-winget' {
            $manifest = Join-Path $RepoRoot 'config/bootstrap/winget.json'
            $result = Invoke-BootstrapWingetImport -Path $manifest
            if (-not $result.Success) { return $result }
            Update-BootstrapSessionPath
            $missing = @(Get-SetupMissingNames @(Get-SetupStepRows W1-winget))
            if ($missing.Count) {
                Write-DotfilesLog warn "W1-winget: not on this session's PATH yet: $($missing -join ', '); open a new shell, then run .\doctor.ps1"
            }
            return $result
        }
        'W1-psresources' {
            $rows = @(Get-SetupStepRows W1-psresources | Where-Object { (Get-BootstrapProbe $_.probe).Kind -ceq 'psmodule' })
            foreach ($row in $rows) {
                if ((Test-BootstrapTool -Probe $row.probe).Found) { continue }
                $result = Invoke-BootstrapPSResource -Name (Get-BootstrapProbe $row.probe).Value
                Write-DotfilesLog info "W1-psresources: $($result.Message)"
                if (-not $result.Success) { return $result }
            }
            return New-BootstrapResult installed 'modules installed for the current user'
        }
        'W1-font' { return Install-BootstrapFont }
        'W1-bat-theme' {
            $row = Get-SetupBatThemeRow
            $destination = Expand-BootstrapPath $row.dest
            $result = Install-BootstrapFile -Uri $row.url -Sha256 $row.sha256 -Destination $destination
            if (-not $result.Success) { return $result }
            $bat = Find-BootstrapCommand 'bat'
            if (-not $bat) {
                Write-DotfilesLog warn 'W1-bat-theme: bat is not on PATH yet; run bat cache --build once it is.'
                return $result
            }
            & $bat cache --build | Out-Host
            if ($LASTEXITCODE -ne 0) { return New-BootstrapResult failed "bat cache --build exited $LASTEXITCODE" $LASTEXITCODE }
            return $result
        }
        'W1-setup-sync' {
            # setup-sync.ps1 defaults to "python", which can resolve to the
            # Store alias even after winget installed a real one; pass a
            # probed interpreter instead.
            $spec = Get-SetupSyncPythonSpec
            $python = Select-BootstrapCommand @spec
            if (-not $python.Path) {
                $seen = if ($python.Rejected.Count) { " (passed over: $($python.Rejected -join ', '))" } else { '' }
                return New-BootstrapResult failed ("no Python >= $($spec.Floor) on PATH$seen; a Microsoft Store alias does not count. " +
                    'Open a new terminal so the W1-winget PATH applies, or run .\setup-sync.ps1 -Python <path> (py -0p lists interpreters)')
            }
            try { & (Join-Path $RepoRoot 'setup-sync.ps1') -Python $python.Path | Out-Host }
            catch { return New-BootstrapResult failed "setup-sync.ps1 -Python $($python.Path) failed: $($_.Exception.Message)" }
            if (-not (Test-SetupVenvReady)) {
                return New-BootstrapResult failed "setup-sync.ps1 finished, but $(Get-BootstrapVenvPython $RepoRoot) fails lib/config_sync.py --runtime-check"
            }
            return New-BootstrapResult installed "AI-sync runtime ready, from Python $($python.Version) at $($python.Path)"
        }
    }
    throw "Unknown step $Id"
}

function Get-SetupPlan {
    $states = [ordered]@{}
    foreach ($id in $AutomatedSteps) { $states[$id] = Get-SetupStepState -Id $id -Earlier $states }
    foreach ($id in $HumanSteps) {
        $done = Test-SetupHumanDone $id
        $blocking = if ($id -cin $BlockingHumanSteps) { 'blocks completion' } else { 'does not block' }
        $states[$id] = if ($done) { New-SetupState $id done 'already done' }
        else { New-SetupState $id human "$((Get-SetupHumanBlock $id).Kind) step for a person; $blocking" }
    }
    return $states
}

function Invoke-SetupApply {
    # Apply todo steps in order and stop at the first failure.
    foreach ($id in $AutomatedSteps) {
        $state = Get-SetupStepState -Id $id
        if ($state.Status -cne 'todo') {
            $level = if ($state.Status -ceq 'done') { 'ok' } else { 'info' }
            Write-DotfilesLog $level "${id}: $($state.Status): $($state.Detail)"
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($id, $state.Detail)) { continue }
        Write-DotfilesLog step "${id}: $($state.Detail)"
        $result = Invoke-SetupStep -Id $id
        if (-not $result.Success) {
            Write-DotfilesLog error "${id}: $($result.Message) (docs/bootstrap.md $id)"
            return $false
        }
        $level = if ($result.Status -ceq 'skipped') { 'warn' } else { 'ok' }
        Write-DotfilesLog $level "${id}: $($result.Status): $($result.Message)"
    }
    return $true
}

function Invoke-BootstrapSetup {
    # Emits plan lines and HUMAN blocks on the success stream; the exit
    # status goes to $script:SetupStatus.
    $ErrorActionPreference = 'Stop'
    $script:SetupStatus = 2
    if ($HostName.ToLowerInvariant() -cne 'win') {
        Write-DotfilesLog error "setup-host.ps1 provisions only the win host, not '$HostName'; use ./setup-host.sh --host <host> on Unix."
        return
    }
    if (-not (Test-BootstrapTierSelection $Tier)) {
        Write-DotfilesLog error "Unknown -Tier '$Tier'; use all or a comma list of $((Get-BootstrapTierNames) -join ', ')."
        return
    }
    if ($PrintManual) {
        foreach ($id in $HumanSteps) { Write-SetupHumanBlock $id }
        $script:SetupStatus = 0
        return
    }
    try {
        $config = Join-Path $RepoRoot 'config/bootstrap'
        $script:ToolRows = @(Get-BootstrapManifestRows -Path (Join-Path $config 'tools.tsv') -Header @(
                    'id', 'tier', 'hosts', 'probe', 'version_flag', 'floor', 'absent', 'doc') |
                Where-Object { Test-BootstrapHostMatch $_.hosts win })
        $script:InstallerRows = @(Get-BootstrapManifestRows -Path (Join-Path $config 'installers.tsv') -Header @(
                    'id', 'kind', 'url', 'sha256', 'dest', 'hosts', 'arch', 'tier', 'human'))
        Assert-SetupWingetManifest (Join-Path $config 'winget.json')
        [void](Get-SetupBatThemeRow)
    }
    catch [IO.InvalidDataException] {
        Write-DotfilesLog error "Invalid manifest: $($_.Exception.Message)"
        return
    }
    # Refuse before probing anything, so a refused run has no side effects.
    if (-not $Check -and -not $Yes -and -not (Test-SetupInteractive)) {
        Write-DotfilesLog error 'Refusing to install from a non-interactive session without -Yes; preview with -Check.'
        return
    }
    try { $plan = Get-SetupPlan }
    catch [IO.InvalidDataException] {
        Write-DotfilesLog error "Invalid manifest: $($_.Exception.Message)"
        return
    }

    if ($Check) {
        # As setup-host.sh --check: 0 only when nothing is left to apply.
        foreach ($state in $plan.Values) { "$($state.Id) $($state.Status) $($state.Detail)" }
        $held = @($plan.Values | Where-Object { $_.Status -ceq 'human' -and $_.Id -cin $BlockingHumanSteps }).Count
        $todo = @($plan.Values | Where-Object { $_.Status -ceq 'todo' }).Count
        $script:SetupStatus = if ($held -or $todo) { 3 } else { 0 }
        return
    }

    if (-not $Yes) {
        foreach ($state in $plan.Values) { "$($state.Id) $($state.Status) $($state.Detail)" }
        if (-not $PSCmdlet.ShouldContinue('Apply the todo steps listed above?', 'setup-host.ps1')) {
            Write-DotfilesLog warn 'Declined; nothing was changed.'
            return
        }
    }

    # Provisioning children must not start update hooks or prompt for Git
    # credentials. Process environment outlives this script in an
    # interactive session, so every change is restored at the end.
    $saved = @{}
    foreach ($name in @('DOTFILES_AUTO_UPDATE', 'AWESOME_SKILLS_AUTO_UPDATE', 'GIT_TERMINAL_PROMPT', 'PATH')) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name)
    }
    try {
        $env:DOTFILES_AUTO_UPDATE = '0'
        $env:AWESOME_SKILLS_AUTO_UPDATE = '0'
        $env:GIT_TERMINAL_PROMPT = '0'
        $applied = @(Invoke-SetupApply)
        if ($applied.Count -ne 1 -or $applied[0] -isnot [bool]) {
            Write-DotfilesLog error "Internal error: a step leaked $($applied.Count) output objects into the apply result."
            $script:SetupStatus = 1
            return
        }
        if (-not $applied[0]) {
            $script:SetupStatus = 1
            return
        }
    }
    finally {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }

    $pending = @($HumanSteps | Where-Object { -not (Test-SetupHumanDone $_) })
    foreach ($id in $pending) { Write-SetupHumanBlock $id }
    $held = @($pending | Where-Object { $_ -cin $BlockingHumanSteps })
    if ($held.Count) {
        Write-DotfilesLog warn "HUMAN steps pending: $($held -join ' '); run the HUMAN blocks above, then rerun .\setup-host.ps1"
        $script:SetupStatus = 3
        return
    }
    Write-DotfilesLog ok 'setup-host: nothing blocking remains for win'
    $script:SetupStatus = 0
}

$libraryPath = Join-Path $RepoRoot 'lib/bootstrap.ps1'
if (-not (Test-Path -LiteralPath $libraryPath -PathType Leaf)) {
    Write-DotfilesLog error "Missing $libraryPath; this checkout is incomplete."
    exit 2
}
. $libraryPath
$script:ToolRows = @()
$script:InstallerRows = @()
$script:SetupStatus = 1
try { Invoke-BootstrapSetup }
catch {
    Write-DotfilesLog error "setup-host.ps1 failed: $($_.Exception.Message)"
    $script:SetupStatus = 1
}
exit $script:SetupStatus
