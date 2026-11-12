#Requires -Version 7.0
# Login update. Dot-sourcing defines the callable function for fixtures.
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/chezmoi-guard.ps1')
# Warnings go through lib/terminal.ps1 when it loads; plain lines otherwise.
try {
    $DotfilesTerminal = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/terminal.ps1'
    if (Test-Path -LiteralPath $DotfilesTerminal -PathType Leaf) { . $DotfilesTerminal }
}
catch { }
finally { Remove-Variable DotfilesTerminal -ErrorAction SilentlyContinue }

function Write-DotfilesUpdateWarning {
    param([string]$Message)
    if (Get-Command Write-DotfilesWarning -CommandType Function -ErrorAction SilentlyContinue) {
        Write-DotfilesWarning $Message
    }
    else { [Console]::Error.WriteLine("[dotfiles] [warn] $Message") }
}

function Invoke-DotfilesUpdateProcess {
    param([string]$Program, [string[]]$Arguments, [object]$Paths)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Program
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $start.WorkingDirectory = $Paths.Source
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    # Ignore inherited repository/config overrides; retain normal user SSH trust.
    # Protocol prefixes must fold ASCII I/i the same way in every culture.
    foreach ($key in @($start.Environment.Keys)) {
        if ($key.StartsWith('GIT_', [StringComparison]::OrdinalIgnoreCase) -or
            $key.StartsWith('CHEZMOI_', [StringComparison]::OrdinalIgnoreCase)) { [void]$start.Environment.Remove($key) }
    }
    $start.Environment['HOME'] = $Paths.Destination
    $start.Environment['USERPROFILE'] = $Paths.Destination
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
            throw 'Update timed out.'
        }
        # chezmoi and git stderr or diff output can contain secrets. Only the
        # caller sees stdout, which it consumes as a scoped Boolean or a
        # clean-tree status.
        [void]$stderr.GetAwaiter().GetResult()
        return [pscustomobject]@{ Code = $process.ExitCode; Output = $stdout.GetAwaiter().GetResult() }
    }
    finally { $process.Dispose() }
}

function Invoke-DotfilesChezmoiUpdate {
    param([string]$HomePath = $HOME)
    if ($env:_DOTFILES_CHECKED -or $env:DOTFILES_AUTO_UPDATE -eq '0') { return }
    $chezmoi = $null
    try {
        if (Test-DotfilesMaintenance $HomePath) { return }
        $env:_DOTFILES_CHECKED = '1'
        $paths = Get-DotfilesChezmoiPaths $HomePath
        if (-not [IO.File]::Exists($paths.State) -or ([IO.FileInfo]$paths.State).Length -eq 0) {
            Write-DotfilesUpdateWarning 'Update skipped: the chezmoi state is missing or empty; inspected recovery is required before automatic update.'
            return
        }
        if ($paths.Source.IndexOf('OneDrive', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Write-DotfilesUpdateWarning 'Update skipped: use the documented independent-clone procedure for OneDrive.'
            return
        }
        # Only the provisioned executable, verified and held open until both
        # chezmoi runs have exited (finally below); never a PATH match.
        $chezmoi = Open-DotfilesChezmoi $paths.Destination
        if ($null -eq $chezmoi) {
            Write-DotfilesUpdateWarning 'Update skipped: ~/.local/bin/chezmoi.exe is missing, a link or not private to you, SYSTEM and Administrators (docs/bootstrap.md W1-chezmoi).'
            return
        }
        $git = Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
        $root = Invoke-DotfilesUpdateProcess $git.Source @('-C', $paths.Source, 'rev-parse', '--show-toplevel') $paths
        if ($root.Code -ne 0 -or -not $root.Output.Trim() -or
            -not (Resolve-DotfilesDirectory $root.Output.Trim()).Equals($paths.Source, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Git working tree differs from the configured sourceDir.'
        }
        $clean = Invoke-DotfilesUpdateProcess $git.Source @('-C', $paths.Source, 'status', '--porcelain=v1', '--untracked-files=all') $paths
        if ($clean.Code -ne 0 -or $clean.Output) { throw 'Source is not clean.' }
        $arguments = @('--source', $paths.Source, '--working-tree', $paths.Source, '--destination', $paths.Destination,
            '--config', $paths.Config, '--cache', $paths.Cache, '--persistent-state', $paths.State,
            '--mode=file', '--no-tty', '--less-interactive', '--error-on-conflict', '--no-pager', '--use-builtin-diff', '--use-builtin-age=true',
            '--use-builtin-git=false', '--force=false')
        $safeConfig = '{{ and (eq .chezmoi.config.update.command "git") ' +
            '(eq (toJson .chezmoi.config.update.args) (toJson (list "-c" "rebase.autoStash=false" "-c" "merge.autoStash=false" "pull" "--ff-only" "--no-rebase" "--no-autostash" "--no-recurse-submodules"))) ' +
            '(not .chezmoi.config.update.recurseSubmodules) ' +
            '(not .chezmoi.config.git.autoadd) (not .chezmoi.config.git.autocommit) (not .chezmoi.config.git.autopush) }}'
        $config = Invoke-DotfilesUpdateProcess $chezmoi.Name ($arguments + @('execute-template', $safeConfig)) $paths
        if ($config.Code -ne 0 -or $config.Output.Trim() -cne 'true') { throw 'Update configuration is unsafe.' }
        $updated = Invoke-DotfilesUpdateProcess $chezmoi.Name ($arguments + @('update', '--apply', '--exclude=dirs', '--recurse-submodules=false')) $paths
        if ($updated.Code -ne 0) { throw 'Update failed.' }
    }
    catch {
        Write-DotfilesUpdateWarning 'Update skipped or failed; review the source, configuration and destination privately.'
    }
    finally { if ($null -ne $chezmoi) { $chezmoi.Dispose() } }
}

if ($MyInvocation.InvocationName -ne '.' -and -not [Console]::IsOutputRedirected) {
    Invoke-DotfilesChezmoiUpdate
}
