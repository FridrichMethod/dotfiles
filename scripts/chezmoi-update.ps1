#Requires -Version 7.0
# Native login update. Dot-sourcing defines the callable worker for fixtures.
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/chezmoi-guard.ps1')

function Invoke-DotfilesNativeProcess {
    param([string]$Program, [string[]]$Arguments, [object]$Binding)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Program
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $start.WorkingDirectory = $Binding.Source
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    # Ignore inherited repository/config overrides; retain normal user SSH trust.
    foreach ($key in @($start.Environment.Keys)) {
        if ($key -like 'GIT_*' -or $key -like 'CHEZMOI_*') { [void]$start.Environment.Remove($key) }
    }
    $start.Environment['HOME'] = $Binding.Destination
    $start.Environment['USERPROFILE'] = $Binding.Destination
    $start.Environment['GIT_TERMINAL_PROMPT'] = '0'
    $start.Environment['GIT_ASKPASS'] = ''
    $start.Environment['SSH_ASKPASS'] = ''
    $start.Environment['SSH_ASKPASS_REQUIRE'] = 'never'
    $start.Environment['GCM_INTERACTIVE'] = 'Never'
    $start.Environment['GIT_SSH_COMMAND'] = 'ssh -oBatchMode=yes -oConnectTimeout=10 -oConnectionAttempts=1'
    $gitOptions = @('credential.helper', '', 'credential.interactive', 'false', 'core.askpass', '',
        'http.lowSpeedLimit', '1000', 'http.lowSpeedTime', '15', 'core.hooksPath', 'NUL',
        'maintenance.auto', 'false', 'gc.auto', '0', 'core.fsmonitor', 'false')
    $start.Environment['GIT_CONFIG_COUNT'] = [string]($gitOptions.Count / 2)
    for ($i = 0; $i -lt $gitOptions.Count; $i += 2) {
        $start.Environment['GIT_CONFIG_KEY_' + ($i / 2)] = $gitOptions[$i]
        $start.Environment['GIT_CONFIG_VALUE_' + ($i / 2)] = $gitOptions[$i + 1]
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) {
            $process.Kill($true)
            throw 'Native update timed out.'
        }
        # Native stderr/diff can contain secrets. Only the caller sees stdout,
        # which it consumes as a scoped Boolean or a clean-tree status.
        [void]$stderr.GetAwaiter().GetResult()
        return [pscustomobject]@{ Code = $process.ExitCode; Output = $stdout.GetAwaiter().GetResult() }
    }
    finally { $process.Dispose() }
}

function Test-DotfilesNativeChezmoiPath {
    # True when .local and .local\bin are real directories and chezmoi.exe a
    # regular file. GetAttributes reports a link itself, never its target.
    param([Parameter(Mandatory)][string]$Path)
    $bin = Split-Path -Parent $Path
    foreach ($item in @((Split-Path -Parent $bin), $bin, $Path)) {
        $attributes = [IO.File]::GetAttributes($item)
        $isDirectory = [bool]($attributes -band [IO.FileAttributes]::Directory)
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -or $isDirectory -ne ($item -ne $Path)) { return $false }
    }
    return $true
}

function Test-DotfilesTrustedFileSecurity {
    # Owner is this user, SYSTEM or Administrators, and no allow entry gives
    # any other SID WRITE_DATA, APPEND, WRITE_EA, WRITE_ATTRIBUTES, DELETE,
    # WRITE_DAC, WRITE_OWNER, GENERIC_ALL or GENERIC_WRITE (0x500D0116).
    # OWNER RIGHTS (S-1-3-4) applies only to that already trusted owner.
    param([Parameter(Mandatory)][Security.AccessControl.FileSystemSecurity]$Security)
    $trusted = @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value, 'S-1-5-18', 'S-1-5-32-544')
    if ($trusted -notcontains $Security.GetOwner([Security.Principal.SecurityIdentifier]).Value) { return $false }
    $trusted += 'S-1-3-4'
    foreach ($rule in $Security.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -eq 'Allow' -and $trusted -notcontains $rule.IdentityReference.Value -and
            ([int]$rule.FileSystemRights -band 0x500D0116)) { return $false }
    }
    return $true
}

function Open-DotfilesNativeChezmoi {
    # The provisioned <destination>\.local\bin\chezmoi.exe, open for reading
    # with FileShare.Read (nobody may write, rename or delete it while held),
    # or $null when it is missing, a link, under a linked directory, or not
    # private. The path is checked again after opening, and owner and DACL
    # are read from the held handle. No PATH lookup ever happens.
    param([Parameter(Mandatory)][string]$Destination)
    $path = Join-Path $Destination '.local\bin\chezmoi.exe'
    $stream = $null
    try {
        if (-not (Test-DotfilesNativeChezmoiPath $path)) { return $null }
        $stream = [IO.FileStream]::new($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        if ((Test-DotfilesNativeChezmoiPath $path) -and
            (Test-DotfilesTrustedFileSecurity ([IO.FileSystemAclExtensions]::GetAccessControl($stream)))) {
            $held = $stream
            $stream = $null
            return $held
        }
        return $null
    }
    catch { return $null }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
}

function Invoke-DotfilesNativeUpdate {
    param([string]$HomePath = $HOME)
    if ($env:_DOTFILES_CHECKED -or $env:DOTFILES_AUTO_UPDATE -eq '0') { return }
    $chezmoi = $null
    try {
        if (Test-DotfilesMaintenance $HomePath) { return }
        $env:_DOTFILES_CHECKED = '1'
        $binding = Get-DotfilesNativeBinding $HomePath
        if (-not [IO.File]::Exists($binding.State) -or ([IO.FileInfo]$binding.State).Length -eq 0) {
            [Console]::Error.WriteLine('[dotfiles] Native state is missing or empty; inspected recovery is required before automatic update.')
            return
        }
        if ($binding.Source -match '(?i)OneDrive') {
            [Console]::Error.WriteLine('[dotfiles] Native update skipped: use the documented independent-clone procedure for OneDrive.')
            return
        }
        # Only the provisioned executable, verified and held open until both
        # chezmoi runs have exited (finally below); never a PATH match.
        $chezmoi = Open-DotfilesNativeChezmoi $binding.Destination
        if ($null -eq $chezmoi) {
            [Console]::Error.WriteLine('[dotfiles] Native update skipped: ~/.local/bin/chezmoi.exe is missing, a link or not private to you, SYSTEM and Administrators (docs/bootstrap.md W1-chezmoi).')
            return
        }
        $git = Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
        $root = Invoke-DotfilesNativeProcess $git.Source @('-C', $binding.Source, 'rev-parse', '--show-toplevel') $binding
        if ($root.Code -ne 0 -or -not $root.Output.Trim() -or
            -not (Resolve-DotfilesDirectory $root.Output.Trim()).Equals($binding.Source, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Git working tree differs from the native source binding.'
        }
        $clean = Invoke-DotfilesNativeProcess $git.Source @('-C', $binding.Source, 'status', '--porcelain=v1', '--untracked-files=all') $binding
        if ($clean.Code -ne 0 -or $clean.Output) { throw 'Source is not clean.' }
        $arguments = @('--source', $binding.Source, '--working-tree', $binding.Source, '--destination', $binding.Destination,
            '--config', $binding.Config, '--cache', $binding.Cache, '--persistent-state', $binding.State,
            '--mode=file', '--no-tty', '--less-interactive', '--error-on-conflict', '--no-pager', '--use-builtin-diff', '--use-builtin-age=true',
            '--use-builtin-git=false', '--force=false')
        $safeConfig = '{{ and (eq .chezmoi.config.update.command "git") ' +
            '(eq (toJson .chezmoi.config.update.args) (toJson (list "-c" "rebase.autoStash=false" "-c" "merge.autoStash=false" "pull" "--ff-only" "--no-rebase" "--no-autostash" "--no-recurse-submodules"))) ' +
            '(not .chezmoi.config.update.recurseSubmodules) .chezmoi.config.update.apply ' +
            '(not .chezmoi.config.git.autoadd) (not .chezmoi.config.git.autocommit) (not .chezmoi.config.git.autopush) }}'
        $config = Invoke-DotfilesNativeProcess $chezmoi.Name ($arguments + @('execute-template', $safeConfig)) $binding
        if ($config.Code -ne 0 -or $config.Output.Trim() -cne 'true') { throw 'Native update configuration is unsafe.' }
        $updated = Invoke-DotfilesNativeProcess $chezmoi.Name ($arguments + @('update', '--apply', '--exclude=dirs', '--recurse-submodules=false')) $binding
        if ($updated.Code -ne 0) { throw 'Native update failed.' }
    }
    catch {
        [Console]::Error.WriteLine('[dotfiles] Native update skipped or failed; review the source, configuration and destination privately.')
    }
    finally { if ($null -ne $chezmoi) { $chezmoi.Dispose() } }
}

if ($MyInvocation.InvocationName -ne '.' -and -not [Console]::IsOutputRedirected) {
    Invoke-DotfilesNativeUpdate
}
