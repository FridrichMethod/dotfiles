#Requires -Version 7.0
# Shared helpers of tests/e2e/run.ps1: the console log, summary.tsv and the
# per-step logs, the log/timeline phases, child pwsh and git runs under a
# timeout, the registry PATH refresh and env.txt. Dot-source only: this file
# defines functions and the run state in the caller's scope and changes no
# preference of its own. The file formats are those of tests/e2e/lib/common.sh,
# so one reader serves the Unix and the Windows artifacts.

# Run state, mutated in place through its keys. run.ps1 fills the paths before
# the first step; the counters feed the last line and the exit code. Broken
# names the step after which the main flow cannot go on.
$script:E2E = @{
    Src = ''; Rev = ''; Out = ''; Clone = ''; Git = ''; PowerShell = ''
    StepN = 0; StepName = ''; StepPhase = ''; StepStart = 0
    StepLog = ''; StepOut = ''; StepErr = ''
    Passes = 0; Fails = 0; Skips = 0
    Broken = ''; Phase = ''
    SkippedBlocks = @()
    NoWriteTemp = ''; NoWriteHome = $null
}
# Seconds allowed to one HUMAN block line (the contract's 45 minutes), one
# setup-host apply run and one read-only run (doctor, -Check, a profile load).
$script:E2ETimeout = @{ Block = 2700; Apply = 3600; Check = 900 }
$script:E2EUtf8 = [Text.UTF8Encoding]::new($false)

function Write-E2ELog {
    # The harness's own console line.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Message)
    Write-Host "[e2e] $Message"
}

function Exit-E2EUsage {
    # A usage error or refusal: exit 2 (exit inside a function ends the script).
    param([Parameter(Mandatory)][string]$Message)
    Write-E2ELog $Message
    exit 2
}

function Get-E2ENow { return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

function Add-E2EText {
    # Append Text to Path as UTF-8 without a BOM, LF line endings as written.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    [IO.File]::AppendAllText($Path, $Text, $script:E2EUtf8)
}

function Get-E2ELines {
    # The lines of a text file, or none when it does not exist.
    param([Parameter(Mandatory)][string]$Path)
    if (-not [IO.File]::Exists($Path)) { return @() }
    return @([IO.File]::ReadAllText($Path) -split '\r?\n')
}

function Get-E2ELastLine {
    # A file's last non-empty line, or ''.
    param([Parameter(Mandatory)][string]$Path)
    $lines = @(Get-E2ELines $Path | Where-Object { $_.Trim() -ne '' })
    if ($lines.Count) { return $lines[-1] }
    return ''
}

function ConvertTo-E2EOneLine {
    # Text as one summary.tsv detail: tabs become spaces, line breaks " | ",
    # and more than Max (600) characters end in "...".
    param([AllowEmptyString()][AllowNull()][string]$Text, [int]$Max = 600)
    $flat = ([string]$Text).Replace("`t", ' ').TrimEnd("`r", "`n")
    $flat = ($flat -split '\r?\n') -join ' | '
    if ($flat.Length -gt $Max) { $flat = $flat.Substring(0, $Max) + '...' }
    return $flat
}

function Test-E2EElevated {
    # True when this token holds the Administrators role (SeCreateSymbolicLink).
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        return ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    finally { $identity.Dispose() }
}

# --- PATH and tools ----------------------------------------------------------

function Split-E2EPathList {
    # Non-empty, environment-expanded entries of a ;-separated PATH value.
    param([AllowEmptyString()][AllowNull()][string]$Value)
    foreach ($entry in ([string]$Value).Split(';')) {
        $expanded = [Environment]::ExpandEnvironmentVariables($entry.Trim())
        if ($expanded) { $expanded }
    }
}

function Update-E2EPath {
    # Rebuild this process's PATH as a new terminal reads it: the entries only
    # this process has first, then the Machine and User registry values, each
    # once (case-insensitively). Installers register directories in the
    # registry; a running process keeps the PATH it started with, so without
    # this the next child would not find what the last apply installed.
    $registry = @(Split-E2EPathList ([Environment]::GetEnvironmentVariable('Path', 'Machine'))) +
        @(Split-E2EPathList ([Environment]::GetEnvironmentVariable('Path', 'User')))
    $known = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $registry) { [void]$known.Add($entry.TrimEnd('\', '/')) }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $merged = [Collections.Generic.List[string]]::new()
    foreach ($entry in @(Split-E2EPathList $env:PATH)) {
        $key = $entry.TrimEnd('\', '/')
        if (-not $known.Contains($key) -and $seen.Add($key)) { $merged.Add($entry) }
    }
    foreach ($entry in $registry) {
        if ($seen.Add($entry.TrimEnd('\', '/'))) { $merged.Add($entry) }
    }
    $env:PATH = $merged -join ';'
}

function Find-E2ECommand {
    # The first PATH entry holding Name.exe, .cmd or .bat, or $null (no
    # Get-Command: about 0.45 s per missing name on Windows).
    param([Parameter(Mandatory)][string]$Name)
    foreach ($directory in @(Split-E2EPathList $env:PATH)) {
        foreach ($extension in @('.exe', '.cmd', '.bat')) {
            $candidate = [IO.Path]::Combine($directory.Trim('"'), $Name + $extension)
            if ([IO.File]::Exists($candidate)) { return $candidate }
        }
    }
    return $null
}

function Get-E2EToolVersion {
    # The first line Name prints for --version, or 'not found'. Probes only.
    param([Parameter(Mandatory)][string]$Name)
    $path = Find-E2ECommand $Name
    if (-not $path) { return 'not found' }
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $lines = @($null | & $path --version 2>&1 | ForEach-Object { "$_" } | Where-Object { $_.Trim() -ne '' })
    }
    catch { return "$path (no version: $($_.Exception.Message))" }
    if ($lines.Count) { return "$($lines[0].Trim()) at $path" }
    return "no output at $path"
}

function Get-E2EGitOutput {
    # git Arguments in this process, for the small queries outside a step:
    # Code and Text (stdout and stderr merged, trimmed).
    param([Parameter(Mandatory)][string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    $git = $E2E['Git']
    $lines = @($null | & $git @Arguments 2>&1 | ForEach-Object { "$_" })
    return [pscustomobject]@{ Code = [int]$LASTEXITCODE; Text = ($lines -join "`n").Trim() }
}

function Get-E2ELinkTarget {
    # A reparse point's target text: .NET's LinkTarget (pwsh 7.2+), else
    # PowerShell's Target property (a string, or string[] in older releases);
    # '' when the item is no link.
    param([Parameter(Mandatory)]$Item)
    foreach ($name in @('LinkTarget', 'Target')) {
        $property = $Item.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value) { return [string]@($property.Value)[0] }
    }
    return ''
}

function Get-E2ECloneDirty {
    # What git status --porcelain reports in the clone, or ''.
    $result = Get-E2EGitOutput @('-C', $E2E['Clone'], '--no-optional-locks', 'status', '--porcelain')
    if ($result.Code -ne 0) { return "git status exited $($result.Code): $($result.Text)" }
    return $result.Text
}

# --- timeline ----------------------------------------------------------------

function Start-E2EPhase {
    # Export E2E_PHASE and append "<epoch>\t<begin>\t<phase>" to log/timeline,
    # as inside.sh does. Windows has no wrappers reading the phase; the
    # timeline still dates every step for whoever reads the artifact.
    param([Parameter(Mandatory)][string]$Phase)
    $E2E['Phase'] = $Phase
    $env:E2E_PHASE = $Phase
    Add-E2EText (Join-Path $E2E['Out'] 'log/timeline') "$(Get-E2ENow)`tbegin`t$Phase`n"
}

function Stop-E2EPhase {
    Add-E2EText (Join-Path $E2E['Out'] 'log/timeline') "$(Get-E2ENow)`tend`t$($E2E['Phase'])`n"
    $E2E['Phase'] = ''
    $env:E2E_PHASE = '-'
}

# --- steps and the summary ---------------------------------------------------

function Add-E2ERecord {
    # One summary.tsv row ("<n>\t<step>\t<pass|fail|skip|note>\t<seconds>
    # \t<detail>") and its console line; the counters feed the exit code.
    param([Parameter(Mandatory)][string]$Step, [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][int]$Seconds, [AllowEmptyString()][string]$Detail)
    $line = ConvertTo-E2EOneLine $Detail
    Add-E2EText (Join-Path $E2E['Out'] 'summary.tsv') "$($E2E['StepN'])`t$Step`t$Status`t$Seconds`t$line`n"
    switch ($Status) {
        'pass' { $E2E['Passes'] = $E2E['Passes'] + 1 }
        'fail' { $E2E['Fails'] = $E2E['Fails'] + 1 }
        'skip' { $E2E['Skips'] = $E2E['Skips'] + 1 }
    }
    Write-E2ELog ('{0:d2} {1,-20} {2,-4} {3,5}s  {4}' -f [int]$E2E['StepN'], $Step, $Status, $Seconds, $line)
}

function Start-E2EStep {
    # Open step Name: its files steps/NN-Name.{log,out,err} and the phase.
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Phase)
    $E2E['StepN'] = $E2E['StepN'] + 1
    $E2E['StepName'] = $Name
    $E2E['StepPhase'] = $Phase
    $E2E['StepStart'] = Get-E2ENow
    $prefix = Join-Path $E2E['Out'] ('steps/{0:d2}-{1}' -f [int]$E2E['StepN'], $Name)
    $E2E['StepLog'] = "$prefix.log"
    $E2E['StepOut'] = "$prefix.out"
    $E2E['StepErr'] = "$prefix.err"
    [IO.File]::WriteAllText($E2E['StepLog'], '', $script:E2EUtf8)
    Start-E2EPhase $Phase
    Write-E2ELog ('{0:d2} {1}: begin' -f [int]$E2E['StepN'], $Name)
}

function Complete-E2EStep {
    # Close the phase, require a clean clone of a passing step, record the row.
    param([Parameter(Mandatory)][ValidateSet('pass', 'fail')][string]$Status,
        [AllowEmptyString()][string]$Detail)
    Stop-E2EPhase
    if ($Status -eq 'pass' -and $E2E['Clone'] -and [IO.Directory]::Exists($E2E['Clone'])) {
        $dirty = Get-E2ECloneDirty
        if ($dirty) {
            $Status = 'fail'
            $Detail = "$Detail; clone not clean: $(ConvertTo-E2EOneLine $dirty 200)"
            # The change itself goes into the step log, so whoever reads the
            # artifact sees what was written, not only which file.
            $diff = Get-E2EGitOutput @('-C', $E2E['Clone'], '--no-optional-locks', 'diff', '--no-color')
            Add-E2EText $E2E['StepLog'] ("--- git diff of the clone (exit $($diff.Code))`n$($diff.Text)`n--- end`n")
        }
    }
    $seconds = (Get-E2ENow) - $E2E['StepStart']
    Add-E2ERecord $E2E['StepName'] $Status $seconds $Detail
    if ($Status -eq 'fail' -and $E2E['StepName'] -eq $E2E['Broken']) {
        Write-E2ELog "the main flow stops after $($E2E['StepName'])"
    }
}

function Write-E2ENote {
    # A row without a step of its own: an observation.
    param([Parameter(Mandatory)][string]$Name, [AllowEmptyString()][string]$Detail)
    $E2E['StepN'] = $E2E['StepN'] + 1
    Add-E2ERecord $Name 'note' 0 $Detail
}

function Skip-E2EStep {
    # A step that did not run, or a block left to the person.
    param([Parameter(Mandatory)][string]$Name, [AllowEmptyString()][string]$Detail)
    $E2E['StepN'] = $E2E['StepN'] + 1
    Add-E2ERecord $Name 'skip' 0 $Detail
}

function Write-E2EFailure {
    # A failing verdict without a run of its own (a refused block, the apply
    # loop not converging, an unhandled error).
    param([Parameter(Mandatory)][string]$Name, [AllowEmptyString()][string]$Detail)
    $E2E['StepN'] = $E2E['StepN'] + 1
    Add-E2ERecord $Name 'fail' 0 $Detail
}

function Invoke-E2EOrSkip {
    # Run Action as step Name, unless an earlier step broke the flow.
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][scriptblock]$Action)
    if ($E2E['Broken']) { Skip-E2EStep $Name "after $($E2E['Broken']) failed" }
    else { & $Action }
}

# --- runs --------------------------------------------------------------------

function Invoke-E2EProcess {
    # Run FilePath with ArgumentList in WorkingDirectory: stdin closed, stdout
    # to OutFile and stderr to ErrFile, killed with its children after
    # TimeoutSeconds (exit code 124 then, as coreutils timeout), and both
    # streams copied into the step log. Environment sets names for the child
    # only; a $null value removes one. Returns the exit code.
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$OutFile,
        [Parameter(Mandatory)][string]$ErrFile,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [hashtable]$Environment = @{}
    )
    $start = [Diagnostics.ProcessStartInfo]::new($FilePath)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WorkingDirectory = $WorkingDirectory
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $ArgumentList) { $start.ArgumentList.Add($argument) }
    foreach ($name in $Environment.Keys) {
        if ($null -eq $Environment[$name]) { [void]$start.Environment.Remove($name) }
        else { $start.Environment[$name] = [string]$Environment[$name] }
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    [void]$process.Start()
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $code = 124
    if ($process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.WaitForExit()
        $code = $process.ExitCode
    }
    else {
        try { $process.Kill($true) } catch { }
        [void]$process.WaitForExit(30000)
    }
    # A grandchild that inherited the pipes keeps them open after the child
    # exits; the output is then not complete, and the log says so.
    $tasks = [Threading.Tasks.Task[]]@($stdout, $stderr)
    $pending = ''
    if (-not [Threading.Tasks.Task]::WaitAll($tasks, 30000)) { $pending = ' (a stream stayed open: a child process kept the pipe)' }
    $outText = if ($stdout.IsCompleted) { $stdout.Result } else { '' }
    $errText = if ($stderr.IsCompleted) { $stderr.Result } else { '' }
    $process.Dispose()
    [IO.File]::WriteAllText($OutFile, $outText, $script:E2EUtf8)
    [IO.File]::WriteAllText($ErrFile, $errText, $script:E2EUtf8)
    $shown = (@($FilePath) + @($ArgumentList)) -join ' '
    $phase = if ($E2E['Phase']) { $E2E['Phase'] } else { '-' }
    $header = "--- `$ $shown`n--- cwd $WorkingDirectory, phase $phase, exit $code$pending`n"
    $body = $outText.TrimEnd("`r", "`n") + "`n--- stderr`n" + $errText.TrimEnd("`r", "`n") + "`n--- end`n"
    Add-E2EText $E2E['StepLog'] ($header + $body)
    return $code
}

function Invoke-E2EPwsh {
    # Run one of the clone's scripts as a new PowerShell 7 window would:
    # pwsh -NoProfile -NonInteractive -File <script> <arguments>, in the
    # clone, under TimeoutSeconds. Returns the exit code.
    param([Parameter(Mandatory)][string]$Script, [string[]]$Arguments = @(),
        [Parameter(Mandatory)][int]$TimeoutSeconds, [hashtable]$Environment = @{})
    $list = @('-NoProfile', '-NonInteractive', '-File', (Join-Path $E2E['Clone'] $Script)) + @($Arguments)
    return Invoke-E2EProcess -FilePath $E2E['PowerShell'] -ArgumentList $list -WorkingDirectory $E2E['Clone'] `
        -OutFile $E2E['StepOut'] -ErrFile $E2E['StepErr'] -TimeoutSeconds $TimeoutSeconds -Environment $Environment
}

function Get-E2ETsvCounts {
    # "status=count ..." of a doctor -Tsv report.
    param([Parameter(Mandatory)][string]$Path)
    $counts = [ordered]@{}
    $rows = @(Get-E2ELines $Path | Select-Object -Skip 1 | Where-Object { $_.Contains("`t") })
    foreach ($row in $rows) {
        $status = $row.Split("`t")[0]
        if ($counts.Contains($status)) { $counts[$status] = $counts[$status] + 1 } else { $counts[$status] = 1 }
    }
    return (@($counts.Keys | ForEach-Object { "$_=$($counts[$_])" }) -join ' ') + ' '
}

function Get-E2EProblemLines {
    # The first five [error] or [warn] lines of a doctor or setup-host log.
    param([Parameter(Mandatory)][string]$Path)
    $lines = @(Get-E2ELines $Path | Where-Object { $_ -match '\[(error|warn)\]' } | Select-Object -First 5)
    return ConvertTo-E2EOneLine ($lines -join "`n") 400
}

# --- env.txt -----------------------------------------------------------------

function Get-E2EProperty {
    # Object's property Name as text, or '' when it has none.
    param([AllowNull()]$Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return '' }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return '' }
    return [string]$property.Value
}

function Write-E2EEnvironment {
    # What the run saw, for whoever reads the artifact.
    param([Parameter(Mandatory)][string]$Mode)
    $version = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $os = @(foreach ($name in @('ProductName', 'DisplayVersion', 'CurrentBuild', 'UBR')) { Get-E2EProperty $version $name }) -join ' '
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add("host=win flow=windows profile=windows mode=$Mode")
    $lines.Add("E2E_SRC=$($E2E['Src'])")
    $lines.Add("E2E_REV=$($E2E['Rev'])")
    $lines.Add("E2E_OUT=$($E2E['Out'])")
    $lines.Add("HOME=$HOME")
    $lines.Add("os: $os ($([Environment]::OSVersion.VersionString))")
    $lines.Add("pwsh: $($PSVersionTable.PSVersion) at $PSHOME")
    $lines.Add("user: $([Environment]::UserName) elevated=$(Test-E2EElevated)")
    $lines.Add("PATH=$env:PATH")
    foreach ($tool in @('git', 'winget', 'python', 'node', 'gh')) { $lines.Add("${tool}: $(Get-E2EToolVersion $tool)") }
    $lines.Add("timeout: check=$($E2ETimeout['Check']) apply=$($E2ETimeout['Apply']) block=$($E2ETimeout['Block'])")
    [IO.File]::WriteAllText((Join-Path $E2E['Out'] 'env.txt'), ($lines -join "`n") + "`n", $script:E2EUtf8)
}
