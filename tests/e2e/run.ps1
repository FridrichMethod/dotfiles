#Requires -Version 7.0
<#
.SYNOPSIS
    The native Windows driver of the opt-in end-to-end bootstrap suite.

.DESCRIPTION
    Plays the person who bootstraps a fresh Windows machine from
    docs/bootstrap.md "Native Windows", the way "Running it with an agent"
    says an agent drives it: clones the source checkout at E2E_REV into
    $HOME\dotfiles with core.symlinks on (HW-clone), checks winget answers
    (W1-winget needs it; a missing one is bootstrapped through
    Microsoft.WinGet.Client and recorded as a deviation), runs doctor.ps1
    -Host win -Tsv and setup-host.ps1 -Host win -Check and requires that
    neither wrote in HOME or TEMP, loops setup-host.ps1 -Host win -Yes (at
    most eight runs) running only the HW-stow block's line as an elevated
    PowerShell 7 would and leaving every other HW block to the person, then
    requires a second -Yes to exit 0 applying nothing, the stowed profile to
    load silently, doctor.ps1 -Host win to exit 0, and the clone to stay
    clean after every step. Between steps PATH is rebuilt from the registry,
    as a new terminal reads it. tests/e2e/inside.sh is the Unix twin.

    It refuses to run anywhere but a GitHub Actions runner (GITHUB_ACTIONS is
    true) or a session that sets E2E_NATIVE=1, and only when $HOME\dotfiles
    does not exist and the session is elevated (it never elevates itself),
    since it bootstraps the real home of the user it runs as. Never run it on
    a workstation.

    Environment: E2E_SRC (the source checkout; default GITHUB_WORKSPACE, else
    this checkout), E2E_REV (a 40-hex commit of it; default its HEAD),
    E2E_OUT (default <E2E_SRC>\tests\e2e\out\win-<UTC yyyymmddThhmmssZ>),
    E2E_ALLOW_DIRTY=1 (accept uncommitted changes in E2E_SRC) and
    E2E_SNAPSHOT_PRUNE (;-separated paths left out of the HOME snapshots).

    Output, the layout of inside.sh: summary.tsv ("<n>\t<step>\t<pass|fail|
    skip|note>\t<seconds>\t<detail>"), steps/NN-<step>.{log,out,err} plus
    NN-apply-N.blocks/ for the HUMAN blocks, env.txt, log/timeline,
    snapshots/<step>.diff and tmp/<step> (the TEMP of each no-write run).

    Exit codes: 0 every step passed (skip and note rows are fine); 1 a step
    failed; 2 usage error or refusal.

.EXAMPLE
    $env:E2E_NATIVE = '1'; .\tests\e2e\run.ps1   # elevated, on a disposable machine
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$E2EDir = $PSScriptRoot
. (Join-Path $E2EDir 'lib/common.ps1')
. (Join-Path $E2EDir 'lib/snapshot.ps1')
. (Join-Path $E2EDir 'lib/blocks.ps1')
. (Join-Path $E2EDir 'lib/steps.ps1')
. (Join-Path $E2EDir 'lib/flow-win.ps1')

# --- refusals (exit 2) -------------------------------------------------------

if ($args.Count -gt 0) {
    Exit-E2EUsage 'run.ps1 takes no arguments; it reads E2E_SRC, E2E_REV, E2E_OUT, E2E_ALLOW_DIRTY and E2E_SNAPSHOT_PRUNE'
}
if (-not $IsWindows) { Exit-E2EUsage 'run.ps1 drives native Windows; every other host runs through tests/e2e/run.sh' }
if ($env:GITHUB_ACTIONS -ne 'true' -and $env:E2E_NATIVE -ne '1') {
    Exit-E2EUsage ("run.ps1 bootstraps the real home of $([Environment]::UserName); it runs only on a GitHub Actions " +
        'runner (GITHUB_ACTIONS=true) or with E2E_NATIVE=1 on a disposable machine')
}
if (-not (Test-E2EElevated)) {
    Exit-E2EUsage 'run.ps1 needs an elevated session: it runs the HW-stow block, whose links any other token makes untrusted, and it never elevates itself'
}
$clone = Join-Path $HOME 'dotfiles'
if (Test-Path -LiteralPath $clone) { Exit-E2EUsage "$clone exists; the harness bootstraps only a home without a clone" }
$git = Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $git) { Exit-E2EUsage 'git is not on PATH; the Windows quick start installs it first (winget install --id Git.Git -e)' }
$E2E['Git'] = $git.Source
$E2E['PowerShell'] = Join-Path $PSHOME 'pwsh.exe'
if (-not (Test-Path -LiteralPath $E2E['PowerShell'] -PathType Leaf)) { Exit-E2EUsage "cannot locate pwsh.exe in $PSHOME" }

# The source checkout: read only, never modified; its HEAD is the default
# commit to test, as tests/e2e/run.sh takes it.
$src = if ($env:E2E_SRC) { $env:E2E_SRC }
    elseif ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE }
    else { Split-Path -Parent (Split-Path -Parent $E2EDir) }
if (-not (Test-Path -LiteralPath $src -PathType Container)) { Exit-E2EUsage "E2E_SRC is not a directory: $src" }
$src = [IO.Path]::GetFullPath($src).TrimEnd('\', '/')
$safe = "safe.directory=$src"
$checkout = Get-E2EGitOutput @('-C', $src, '-c', $safe, 'rev-parse', '--git-dir')
if ($checkout.Code -ne 0) { Exit-E2EUsage "E2E_SRC is not a git checkout: $src ($($checkout.Text))" }
$rev = if ($env:E2E_REV) { $env:E2E_REV } else { (Get-E2EGitOutput @('-C', $src, '-c', $safe, 'rev-parse', 'HEAD')).Text }
if ($rev -cnotmatch '^[0-9a-f]{40}$') { Exit-E2EUsage "E2E_REV is not a 40-hex commit: $rev" }
$known = Get-E2EGitOutput @('-C', $src, '-c', $safe, 'cat-file', '-e', ($rev + '^{commit}'))
if ($known.Code -ne 0) { Exit-E2EUsage "E2E_REV $rev is not a commit of ${src}: $($known.Text)" }
if ($env:E2E_ALLOW_DIRTY -ne '1') {
    $dirty = Get-E2EGitOutput @('-C', $src, '-c', $safe, '--no-optional-locks', 'status', '--porcelain')
    if ($dirty.Code -ne 0) { Exit-E2EUsage "git status fails in ${src}: $($dirty.Text)" }
    if ($dirty.Text) {
        Exit-E2EUsage "E2E_SRC has uncommitted changes (E2E_ALLOW_DIRTY=1 overrides): $(ConvertTo-E2EOneLine $dirty.Text 200)"
    }
}
$E2E['Src'] = $src
$E2E['Rev'] = $rev
$E2E['Clone'] = $clone

# --- the output directory ----------------------------------------------------

$stamp = [DateTime]::UtcNow.ToString("yyyyMMdd'T'HHmmss'Z'")
$out = if ($env:E2E_OUT) { $env:E2E_OUT } else { Join-Path $src "tests\e2e\out\win-$stamp" }
$out = [IO.Path]::GetFullPath($out).TrimEnd('\', '/')
foreach ($subdirectory in @('log', 'steps', 'snapshots', 'tmp')) {
    [void][IO.Directory]::CreateDirectory((Join-Path $out $subdirectory))
}
$E2E['Out'] = $out

# --- the run -----------------------------------------------------------------

$mode = if ($env:GITHUB_ACTIONS -eq 'true') { 'github-actions' } else { 'native' }
Write-E2EEnvironment $mode
Write-E2ELog "win: source $src at $rev; clone $clone; out $out"
try { Invoke-E2EFlowWin }
catch {
    # A harness bug, not a finding about the bootstrap: still a row and exit 1.
    if ($E2E['Phase']) { Stop-E2EPhase }
    Write-E2EFailure harness "unhandled error: $($_.Exception.Message) | $($_.ScriptStackTrace)"
}
Write-E2EEnvironment $mode
$status = if ($E2E['Fails'] -gt 0) { 1 } else { 0 }
Write-E2ELog "win: $($E2E['Passes']) passed, $($E2E['Fails']) failed, $($E2E['Skips']) skipped; $out\summary.tsv"
exit $status
