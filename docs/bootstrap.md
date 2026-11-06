# Bootstrapping a host

## What this is

`./doctor.sh` and `./setup-host.sh` (on native Windows, `.\doctor.ps1` and
`.\setup-host.ps1`) are the explicit, fail-closed entry points that take a
fresh machine to the state the dotfiles assume. The doctor is read-only
and offline: for every tool it reports `ok`, `missing` or `outdated` and names
the step below that fixes it. The installer runs pinned, checksummed steps that
need no root, and prints everything that needs a person (sudo, a browser login,
a GUI dialog, a Slurm allocation, a login-shell change, a judgment call) as a
HUMAN block instead of running it. Profiles and the login update never
install a tool; only these entry points do, and only when you run them. (This
repository's three first-party payload repos install and update, through their
own installers, only when a person runs the payload command; no login,
profile or schedule does; see [H7-payloads](#h7-payloads-payload-repos).)

[`config/bootstrap/`](../config/bootstrap/) is the single source for
everything they install: [`tools.tsv`](../config/bootstrap/tools.tsv) (what the
doctor checks: tier, hosts, probe, version floor, and the step that fixes each
row), the tiered Brewfiles in [`brew/`](../config/bootstrap/brew/), the apt
lists in [`apt/`](../config/bootstrap/apt/),
[`hpc-login-env.yml`](../config/bootstrap/hpc-login-env.yml),
[`winget.json`](../config/bootstrap/winget.json),
[`git-clones.tsv`](../config/bootstrap/git-clones.tsv) (default branches,
tracked and never pinned) and
[`installers.tsv`](../config/bootstrap/installers.tsv) (URL plus sha256). This
playbook links those files instead of repeating their pins and branches.
`tests/bootstrap-manifest.sh` validates them, checks that this file has exactly
one `### <step-id>:` heading per step, and checks that
[dependencies.md](dependencies.md#day-zero-tools) lists every tool.

## Native provisioning

New installations use native chezmoi. Both setup-host entrypoints install its
pinned, SHA256-verified release explicitly and create no virtual environment.
They do not initialize or apply configuration. The blocking
H7-native / HW-native step points to the reviewed
[takeover procedure](chezmoi-migration/takeover.md), including explicit local
host selection, quiescence, private snapshots and the per-home writer binding.
A fresh home, with no earlier install, takes the shorter
[Fresh home by hand](#fresh-home-by-hand) procedure instead
([Fresh Windows home by hand](#fresh-windows-home-by-hand) on Windows).
Native doctor checks chezmoi and that binding; it never invokes transforms.
An active maintenance marker means handover is still incomplete.

### S4-chezmoi: Native chezmoi binary

Install the release archive selected by host and architecture from
`config/bootstrap/installers.tsv` into `~/.local/bin/chezmoi`, extracting only
the executable after SHA256 verification. An existing executable meeting the
`tools.tsv` floor is retained. Unsupported architectures fail visibly. A symlink
or directory at the managed binary destination requires operator judgment.
No shell rc, native config, marker, auth state or sync environment is created.
The official release checksum manifest is the integrity source; this does not
claim independent signature verification. `--check` only reads and probes.
Sherlock x86_64 selects the official static musl archive: its glibc 2.17 cannot
load the generic v2.74.0 Linux binary, which requires glibc 2.34. A private
staged version probe on Sherlock verified the static binary without installing
a runtime, creating an environment or changing the destination convention.

By hand on a Linux without an overlay (X-other-linux; glibc 2.34 or later), for
an absent or regular `~/.local/bin/chezmoi`: `fetch_pinned`
([Downloads and clones by hand](#downloads-and-clones-by-hand)) takes the first
`installers.tsv` row for the architecture, the generic Linux archive, so macOS
and the clusters run `./setup-host.sh` instead:

```sh
f=$(fetch_pinned chezmoi "$(uname -m)") && mkdir -p "$HOME/.local/bin" && tar -xzOf "$f" chezmoi >"$HOME/.local/bin/chezmoi.new" && chmod 755 "$HOME/.local/bin/chezmoi.new" && mv -f "$HOME/.local/bin/chezmoi.new" "$HOME/.local/bin/chezmoi"
```

### H7-native: Reviewed native configuration handover

Follow [takeover.md](chezmoi-migration/takeover.md). Provisioning does not own this
operation and prints no blanket apply command. A valid native binding matching
this checkout and regular local config, with maintenance absent, satisfies the
bootstrap handoff check; it does not substitute for the procedure's native diff,
second apply or application checks. Run from another checkout (a worktree or a
second clone), setup-host keeps H7-native pending.

The doctor's `native-config` row names the cause. `ok`: the handoff state above.
`warn`, which does not fail the run: the home is bound to another checkout,
whose doctor it names, or, with the binding otherwise `ok`,
`~/.config/chezmoi/chezmoistate.boltdb` exists, a separate state database that
a chezmoi command without the updater's full explicit argument set wrote (run
every manual native command with that set, as takeover.md says; the doctor
never removes the file, and setup-host still counts H7-native done). `human`: active maintenance, a missing or invalid
binding, a local config that is absent or not a regular file (a link or a
directory), or no readable `lib/chezmoi-guard.sh` in this checkout; on Windows
also a `~/.local/bin/chezmoi.exe` the login updater refuses
([HW-native](#hw-native-windows-native-handover)).

#### Fresh home by hand

A fresh home has no Stow links, no `~/.config/dotfiles/native`, no maintenance
marker and no `~/.config/chezmoi/chezmoi.toml`. Nothing else writes it, so it
needs neither the quiescence nor the maintenance marker of
[takeover.md](chezmoi-migration/takeover.md), and it runs that procedure's
commands with the same explicit arguments. Anything else, or a function below
that stops, goes back to takeover.md. Paste both functions into the shell you
are working in, then run `native_handover ROLE` from the clone, where ROLE is
the `--host` value, or `common-only` on a Linux without an overlay
([X-other-linux](#x-other-linux-other-linux-distributions)):

```sh
# native_cz ARGS...: this home's native chezmoi, run from the clone with every
# native path explicit (takeover.md) and stdin closed; ~/.local/bin/chezmoi
# (S4-chezmoi) comes first, then a chezmoi on PATH.
native_cz() {
    _nc_src=$(pwd -P) && _nc_home=$(cd -P -- "$HOME" && pwd -P) || return 1
    [ -f "$_nc_src/.chezmoiroot" ] || { printf '%s\n' 'native_cz: run it from the dotfiles clone' >&2; return 1; }
    _nc_bin=$_nc_home/.local/bin/chezmoi
    [ -x "$_nc_bin" ] || _nc_bin=$(command -v chezmoi) ||
        { printf '%s\n' 'native_cz: no chezmoi; run S4-chezmoi first' >&2; return 1; }
    "$_nc_bin" --source "$_nc_src" --working-tree "$_nc_src" --destination "$_nc_home" \
        --config "$_nc_home/.config/chezmoi/chezmoi.toml" --cache "$_nc_home/.cache/chezmoi" \
        --persistent-state "$_nc_home/.local/state/chezmoi/chezmoi.boltdb" \
        --mode=file --no-tty --error-on-conflict --force=false --no-pager --use-builtin-diff "$@" </dev/null
}

# native_handover ROLE: the first native deployment of a fresh home, run from
# the clone; ROLE is this machine's --host, or common-only (X-other-linux).
native_handover() {
    _nh_role=${1:-}
    case $_nh_role in
        common-only | mac | wsl-ubuntu | lab-ubuntu | sherlock | marlowe) ;;
        *)
            printf '%s\n' 'native_handover: name the role: common-only, mac, wsl-ubuntu, lab-ubuntu, sherlock or marlowe' >&2
            return 1
            ;;
    esac
    _nh_src=$(pwd -P) && _nh_home=$(cd -P -- "$HOME" && pwd -P) || return 1
    [ -f "$_nh_src/.chezmoiroot" ] || { printf '%s\n' 'native_handover: run it from the dotfiles clone' >&2; return 1; }
    _nh_keep=$_nh_home/.local/state/dotfiles-fresh-backup
    for _nh_rel in .config/dotfiles/native .config/dotfiles/maintenance .config/chezmoi/chezmoi.toml \
        .local/state/chezmoi/chezmoi.boltdb .local/state/dotfiles-fresh-backup; do
        if [ -e "$_nh_home/$_nh_rel" ] || [ -L "$_nh_home/$_nh_rel" ]; then
            printf 'native_handover: ~/%s exists, so this is no fresh home; follow docs/chezmoi-migration/takeover.md\n' "$_nh_rel" >&2
            return 1
        fi
    done
    # The local config: the role, and a private umask for what apply writes.
    (umask 077 && mkdir -p "$_nh_home/.config/chezmoi" "$_nh_keep" &&
        printf 'umask = 0o077\n\n[data]\nhost = "%s"\n' "$_nh_role" >"$_nh_home/.config/chezmoi/chezmoi.toml") || return 1
    native_cz init || return 1
    native_cz managed --include=dirs >"$_nh_keep/dirs" || return 1
    native_cz managed --include=files,symlinks >"$_nh_keep/files" || return 1
    # Only a real directory may stand where a directory goes, and only a
    # regular file where a file goes; that file is copied first, since with no
    # native state the first apply replaces it without asking.
    while IFS= read -r _nh_rel; do
        if [ -L "$_nh_home/$_nh_rel" ] || { [ -e "$_nh_home/$_nh_rel" ] && [ ! -d "$_nh_home/$_nh_rel" ]; }; then
            printf 'native_handover: ~/%s is not a directory; follow docs/chezmoi-migration/takeover.md\n' "$_nh_rel" >&2
            return 1
        fi
    done <"$_nh_keep/dirs"
    while IFS= read -r _nh_rel; do
        if [ -L "$_nh_home/$_nh_rel" ] || { [ -e "$_nh_home/$_nh_rel" ] && [ ! -f "$_nh_home/$_nh_rel" ]; }; then
            printf 'native_handover: ~/%s is a link or not a regular file; follow docs/chezmoi-migration/takeover.md\n' "$_nh_rel" >&2
            return 1
        fi
        [ ! -f "$_nh_home/$_nh_rel" ] ||
            (umask 077 && mkdir -p "$(dirname -- "$_nh_keep/$_nh_rel")" && cp "$_nh_home/$_nh_rel" "$_nh_keep/$_nh_rel") ||
            return 1
    done <"$_nh_keep/files"
    # The home binding, before the first change to a target.
    (umask 077 && mkdir -p "$_nh_home/.config/dotfiles" &&
        printf '%s\n' dotfiles-chezmoi-v1 "$_nh_home" "$_nh_src" >"$_nh_home/.config/dotfiles/native" &&
        chmod 600 "$_nh_home/.config/dotfiles/native") || return 1
    # Exactly the absent directories, one at a time, parents first.
    while IFS= read -r _nh_rel; do
        [ -e "$_nh_home/$_nh_rel" ] || native_cz apply --include=dirs --recursive=false "$_nh_home/$_nh_rel" || return 1
    done <"$_nh_keep/dirs"
    native_cz apply --exclude=dirs && native_cz apply --exclude=dirs || return 1
    _nh_diff=$(native_cz diff --exclude=dirs) || return 1
    if [ -n "$_nh_diff" ]; then
        printf '%s\n' 'native_handover: targets still differ after two applies; review native_cz diff --exclude=dirs privately' >&2
        return 1
    fi
    printf 'native_handover: %s deployed; copies of the files it replaced are in ~/.local/state/dotfiles-fresh-backup\n' "$_nh_role"
}
```

`native_handover` seeds the local config with only the role plus
`umask = 0o077`, the umask the five Unix hosts selected (files 0600,
executables 0700). It stops on a link, or an entry of the wrong kind, at any
managed path. It copies each regular file it is about to replace into
`~/.local/state/dotfiles-fresh-backup/` (0700), such as the `/etc/skel`
`.bashrc`, `.profile` or `.bash_profile`, because the first apply with no
native state replaces such a file without asking. It writes the three-line
0600 binding before the first target change, creates only the absent managed
directories, one at a time, parents first, applies twice and requires an empty
`native_cz diff --exclude=dirs`. It never forces and never creates
maintenance. The managed paths come from this repository's own source, so the
lists are read one path per line (takeover.md's `--nul-path-separator` guards
names a pasted shell function cannot split portably). Afterwards
`./setup-host.sh --host H` exits 0, the next interactive login runs the native
updater, and `./doctor.sh --host H --smoke` is the gate. Delete the backup
directory once nothing in it is needed. Run any later manual native command as
`native_cz ARGS...` from the clone: without the explicit arguments chezmoi
writes the stray `chezmoistate.boltdb` the doctor warns about.

### W1-chezmoi: Windows native chezmoi binary

The Windows equivalent of S4-chezmoi verifies the pinned ZIP and extracts only
`chezmoi.exe` to `~/.local/bin`. It hashes and extracts through one read-only
handle and writes the file with an explicit protected DACL (FullControl for
you, SYSTEM and Administrators, nothing inherited) before renaming it into
place, replacing a regular file. A link at `chezmoi.exe`, `.local\bin` or
`.local` stops it before downloading, for inspection. Dotfiles never
changes the ACL of `~/.local` or `~/.local/bin`. Bootstrap and doctor search
this directory explicitly, before PATH; use the full executable path when
invoking chezmoi manually. No permanent PATH or profile edit, elevation or
scheduled task is performed.

The native login updater runs only this exact file, never a PATH match. It
opens it with `FileShare.Read`, holds it until its chezmoi runs have exited,
and requires a regular file with no link or junction at it, `.local` or
`.local\bin` (checked before and after the open), an owner that is you, SYSTEM
or Administrators, a DACL that is present and holds only plain allow or deny
entries (no object or compound entry, which .NET's access rules would skip),
and no allow entry that gives any other account a write, delete, permission or
owner change right (OWNER RIGHTS counts only for such an owner); owner and DACL
are read from the held handle's raw descriptor. Otherwise, also when the file
is missing, it prints one warning naming this section and skips the update.
This narrows the gap between check and start but does not close it:
on a `windows-2025` hosted runner (elevated), NTFS refused to rename `.local`
or `.local\bin` while the handle was held, and the fixture's rename of
`.local\bin` succeeded after release. This protects only once the real file
is held at its real path. A writer of `~/.local` that wins two sub-millisecond
races (swapping `.local\bin` for a junction before the open, then a prepared
directory back before the re-check) can still get a different `chezmoi.exe`
started; the check does not make the path tamper-proof.

W1-chezmoi is done only when a chezmoi at or above the floor works and the
updater would run `~/.local/bin/chezmoi.exe`, by the same read-only check. A
chezmoi only elsewhere on PATH (winget, scoop), which the updater never runs,
or a copy that is linked or not private leaves it todo, and on a bound home
`doctor.ps1`'s `native-config` row reports `human` naming this section. If the
updater warns, inspect `~/.local/bin/chezmoi.exe`; remove a link there, and
make a linked `.local` or `.local\bin` a real directory; then rerun
`setup-host.ps1` so W1-chezmoi installs a private copy over a regular file.
Another chezmoi on PATH may stay: neither the updater nor the manual commands
of [takeover.md](chezmoi-migration/takeover.md) use it.

### HW-native: Windows native handover

Follow [takeover.md](chezmoi-migration/takeover.md), including actual
CurrentUserAllHosts discovery in both shells and ordinary-user destination ACL
checks. Native regular-file updates need no elevation or scheduled task.
`doctor.ps1`'s `native-config` row gives the verdicts of
[H7-native](#h7-native-reviewed-native-configuration-handover), with
`lib/chezmoi-guard.ps1` as the guard; a junction or symlink path to the bound
checkout counts as that checkout. One verdict is Windows only: with the
binding otherwise `ok`, the row is `human`, citing
[W1-chezmoi](#w1-chezmoi-windows-native-chezmoi-binary), when the login updater
would refuse `~/.local/bin/chezmoi.exe`. That check only opens the file for
reading and comes before the stray state database warning.

#### Fresh Windows home by hand

The Windows twin of [Fresh home by hand](#fresh-home-by-hand), for the same
fresh home. Run it in an ordinary, unelevated PowerShell 7 in the clone, after
W1-chezmoi: paste both functions, then `Invoke-NativeHandover -Role win`. It
requires both PowerShell editions to load `~\Documents\PowerShell\profile.ps1`
and `~\Documents\WindowsPowerShell\profile.ps1`; a Documents folder
redirected to OneDrive is a takeover.md case. `~\.local\bin\chezmoi.exe`
must be a regular file with no link at it, `.local` or `.local\bin`, the file
the login updater runs. It warns when elevated. The local config holds only
`[data]` `host = "win"`. Each chezmoi run gets the full argument array, with
stdin closed; the copies, the binding, the directory order, the double apply
and the empty diff are as on Unix.

```powershell
function Invoke-NativeCz {
    # This home's native chezmoi, ~\.local\bin\chezmoi.exe by its full path,
    # run from the clone: every native path explicit (takeover.md), the
    # arguments as an array, stdin closed. Returns its output; throws when it
    # exits nonzero.
    param([Parameter(Mandatory)][string[]]$Arguments)
    $ErrorActionPreference = 'Stop'
    $clone = $PWD.ProviderPath
    if (-not [IO.File]::Exists((Join-Path $clone '.chezmoiroot'))) { throw 'Invoke-NativeCz: run it from the dotfiles clone' }
    . (Join-Path $clone 'lib\chezmoi-guard.ps1')
    $source = Resolve-DotfilesDirectory $clone
    $destination = Resolve-DotfilesDirectory $HOME
    $start = [Diagnostics.ProcessStartInfo]::new((Join-Path $destination '.local\bin\chezmoi.exe'))
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.WorkingDirectory = $source
    $fixed = @('--source', $source, '--working-tree', $source, '--destination', $destination,
        '--config', (Join-Path $destination '.config\chezmoi\chezmoi.toml'),
        '--cache', (Join-Path $destination '.cache\chezmoi'),
        '--persistent-state', (Join-Path $destination '.local\state\chezmoi\chezmoi.boltdb'),
        '--mode=file', '--no-tty', '--error-on-conflict', '--force=false', '--no-pager', '--use-builtin-diff')
    foreach ($argument in @($fixed) + @($Arguments)) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $process.StandardInput.Close()
        $output = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "Invoke-NativeCz: chezmoi $($Arguments -join ' ') exited $($process.ExitCode)" }
        return $output
    }
    finally { $process.Dispose() }
}

function Invoke-NativeHandover {
    # The first native deployment of a fresh Windows home, run from the clone
    # in an ordinary (unelevated) PowerShell 7 after W1-chezmoi.
    param([Parameter(Mandatory)][ValidateSet('win')][string]$Role)
    $ErrorActionPreference = 'Stop'
    $clone = $PWD.ProviderPath
    if (-not [IO.File]::Exists((Join-Path $clone '.chezmoiroot'))) { throw 'Invoke-NativeHandover: run it from the dotfiles clone' }
    . (Join-Path $clone 'lib\chezmoi-guard.ps1')
    $source = Resolve-DotfilesDirectory $clone
    $destination = Resolve-DotfilesDirectory $HOME
    $keep = Join-Path $destination '.local\state\dotfiles-fresh-backup'
    foreach ($relative in @('.config\dotfiles\native', '.config\dotfiles\maintenance', '.config\chezmoi\chezmoi.toml',
            '.local\state\chezmoi\chezmoi.boltdb', '.local\state\dotfiles-fresh-backup')) {
        if (Test-DotfilesMarkerObject (Join-Path $destination $relative)) {
            throw "Invoke-NativeHandover: ~\$relative exists, so this is no fresh home; follow docs/chezmoi-migration/takeover.md"
        }
    }
    if (-not (Test-DotfilesNativeChezmoiPath (Join-Path $destination '.local\bin\chezmoi.exe'))) {
        throw 'Invoke-NativeHandover: ~\.local\bin\chezmoi.exe is missing or linked; follow W1-chezmoi'
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        if (([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Warning 'Invoke-NativeHandover: this PowerShell is elevated; the handover needs no elevation'
        }
    }
    finally { $identity.Dispose() }
    # Both PowerShell editions must load the profiles this home deploys; a
    # Documents folder redirected elsewhere (OneDrive) is a takeover.md case.
    $profiles = @{ 'Documents\PowerShell\profile.ps1' = [string]$PROFILE.CurrentUserAllHosts }
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if ([IO.File]::Exists($windowsPowerShell)) {
        $profiles['Documents\WindowsPowerShell\profile.ps1'] = [string](@($null | & $windowsPowerShell -NoProfile -NonInteractive -Command '$PROFILE.CurrentUserAllHosts') -join '')
    }
    foreach ($relative in $profiles.Keys) {
        if (-not [IO.Path]::GetFullPath($profiles[$relative]).Equals((Join-Path $destination $relative), [StringComparison]::OrdinalIgnoreCase)) {
            throw "Invoke-NativeHandover: PowerShell loads $($profiles[$relative]), not ~\$relative; follow docs/chezmoi-migration/takeover.md"
        }
    }
    $utf8 = [Text.UTF8Encoding]::new($false)
    [void][IO.Directory]::CreateDirectory((Join-Path $destination '.config\chezmoi'))
    [void][IO.Directory]::CreateDirectory($keep)
    [IO.File]::WriteAllText((Join-Path $destination '.config\chezmoi\chezmoi.toml'), "[data]`nhost = `"$Role`"`n", $utf8)
    [void](Invoke-NativeCz @('init'))
    $directories = @((Invoke-NativeCz @('managed', '--include=dirs')) -split '\r?\n' | Where-Object { $_ } | ForEach-Object { $_.Replace('/', '\') })
    $files = @((Invoke-NativeCz @('managed', '--include=files,symlinks')) -split '\r?\n' | Where-Object { $_ } | ForEach-Object { $_.Replace('/', '\') })
    # Only a real directory may stand where a directory goes, and only a
    # regular file where a file goes; that file is copied first, since with no
    # native state the first apply replaces it without asking.
    foreach ($relative in @($directories) + @($files)) {
        $path = Join-Path $destination $relative
        if (-not (Test-DotfilesMarkerObject $path)) { continue }
        $attributes = [IO.File]::GetAttributes($path)
        $isDirectory = ($attributes -band [IO.FileAttributes]::Directory) -ne 0
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -or ($isDirectory -ne ($directories -contains $relative))) {
            throw "Invoke-NativeHandover: ~\$relative is a link or not the expected kind of entry; follow docs/chezmoi-migration/takeover.md"
        }
        if (-not $isDirectory) {
            $copy = Join-Path $keep $relative
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $copy))
            [IO.File]::Copy($path, $copy)
        }
    }
    # The home binding, before the first change to a target.
    [void][IO.Directory]::CreateDirectory((Join-Path $destination '.config\dotfiles'))
    [IO.File]::WriteAllText((Join-Path $destination '.config\dotfiles\native'), "dotfiles-chezmoi-v1`n$destination`n$source`n", $utf8)
    # Exactly the absent directories, one at a time, parents first.
    foreach ($relative in $directories) {
        $path = Join-Path $destination $relative
        if (-not (Test-DotfilesMarkerObject $path)) { [void](Invoke-NativeCz @('apply', '--include=dirs', '--recursive=false', $path)) }
    }
    [void](Invoke-NativeCz @('apply', '--exclude=dirs'))
    [void](Invoke-NativeCz @('apply', '--exclude=dirs'))
    if ((Invoke-NativeCz @('diff', '--exclude=dirs')).Trim()) {
        throw 'Invoke-NativeHandover: targets still differ after two applies; review Invoke-NativeCz @(''diff'', ''--exclude=dirs'') privately'
    }
    Write-Output "Invoke-NativeHandover: $Role deployed; copies of the files it replaced are in ~\.local\state\dotfiles-fresh-backup"
}
```

## Quick start

Every platform runs the same sequence: get git (and, if you want an agent to
drive the rest, one agent CLI), clone to `~/dotfiles`, diagnose,
preview, apply, handle the HUMAN blocks, hand the home over to native chezmoi,
start a login shell, and finish with the smoke test. Pick the host overlay
yourself (`mac`, `wsl-ubuntu`, `lab-ubuntu`, `sherlock`, `marlowe`, `win`);
nothing guesses it.

> **Ordering note: oh-my-zsh must exist before the handover.** The dotfiles
> put files under `~/.oh-my-zsh/custom/`, and once that directory exists,
> oh-my-zsh can no longer be cloned into `~/.oh-my-zsh`, so zsh aborts where
> `.zshrc` sources `oh-my-zsh.sh`. `./setup-host.sh` clones it in
> [S3-clones](#s3-clones-oh-my-zsh-theme-and-plugin-clones), before
> [H7-native](#h7-native-reviewed-native-configuration-handover). If the
> handover ran first, use the first recipe in
> [X-recovery](#x-recovery-recovery-recipes).

Keep the login update hook quiet while provisioning, in every shell you use for
it: `export DOTFILES_AUTO_UPDATE=0 DOTFILES_PAYLOAD_AUTO_UPDATE=0` (the second
is inert: nothing reads it any more). Otherwise the first interactive shell
after the handover pulls the checkout in the middle of the bootstrap. No shell
installs the payload repos: they install only when you run the
[H7-payloads](#h7-payloads-payload-repos) line, whenever you choose.

`./setup-host.sh` exits 3 while work remains: a blocking HUMAN step is pending,
or automatic steps are still to apply.
[H7-native](#h7-native-reviewed-native-configuration-handover) (HW-native on
Windows) blocks, so re-run it after each block until H7-native is the only one
still blocking, run the fresh-home procedure of H7-native
([Fresh home by hand](#fresh-home-by-hand)), and run it once more; then it
exits 0 and reprints only the non-blocking blocks (login shell, sign-in, the
payload repos, the final doctor run). `--check` exits 3 whenever a step is
still to do, so a `--check` that exits 0 has nothing left to apply.

### macOS

```sh
xcode-select --install          # H1-xcode-clt: git comes with the Command Line Tools (GUI dialog)
git clone https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles
export DOTFILES_AUTO_UPDATE=0 DOTFILES_PAYLOAD_AUTO_UPDATE=0
./doctor.sh --host mac
./setup-host.sh --host mac --check
./setup-host.sh --host mac      # exit 3: run the printed H1-homebrew sudo block yourself
./setup-host.sh --host mac      # again after each block, until only H7-native still blocks
# H7-native: the fresh-home procedure in H7-native
./setup-host.sh --host mac      # exits 0 now
# H7-payloads (optional, any time): sh scripts/payload-update.sh --now
exec zsh -l
./doctor.sh --host mac --smoke
```

An agent CLI before Homebrew exists: download Claude Code's installer, read it,
then run it (`f=$(mktemp) && curl -fsSL --proto '=https' -o "$f" https://claude.ai/install.sh && less "$f"`,
then `bash "$f"`). Otherwise skip it; the `ai` tier installs the
`claude-code` and `codex` casks.

### Ubuntu and WSL

For `wsl-ubuntu`, first create the distribution from Windows with the literal
name `Ubuntu` ([HW-wsl](#hw-wsl-wsl-distribution), which also covers the
`/etc/wsl.conf` judgment) and work inside it, in its own clone. For
`lab-ubuntu`, start from a desktop session.

```sh
sudo apt-get update
sudo apt-get install -y git curl
git clone https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles
export DOTFILES_AUTO_UPDATE=0 DOTFILES_PAYLOAD_AUTO_UPDATE=0
./doctor.sh --host wsl-ubuntu                 # or lab-ubuntu
./setup-host.sh --host wsl-ubuntu --check
./setup-host.sh --host wsl-ubuntu             # exit 3: sudo blocks H1-apt-core, H1-linuxbrew (and H1-locale)
./setup-host.sh --host wsl-ubuntu             # again after each block (later the S5-claude inspect block),
                                              # until only H7-native still blocks
# H7-native: the fresh-home procedure in H7-native
./setup-host.sh --host wsl-ubuntu             # exits 0 now
chsh -s "$(command -v zsh)"                   # H7-chsh, asks for your password
# H7-payloads (optional, any time): sh scripts/payload-update.sh --now
exec zsh -l
./doctor.sh --host wsl-ubuntu --smoke
```

`lab-ubuntu` adds one gui step (H1-fcitx5: `im-config -n fcitx5` as you, then
a relogin); add `--tier all` to get kitty and the Nerd Font. An agent CLI
first, if wanted: the Claude Code installer as on macOS. Where
`/home/linuxbrew/.linuxbrew` belongs to a shared lab account, S2-brew-bundle
prints a `sudo` block that runs `brew bundle` as that account; never `chown`
the prefix ([S2-brew-bundle](#s2-brew-bundle-brewfile-bundles)).

### Sherlock and Marlowe

No sudo, no Homebrew, no `chsh`. Log in without the RemoteCommand
(`ssh sherlock-plain` / `ssh marlowe-plain` from a configured workstation, or
`ssh <SUNetID>@login.sherlock.stanford.edu`); `ssh sherlock` execs the login-env
zsh and fails until [S2-login-env](#s2-login-env-hpc-login-environment) exists.

```sh
cat /etc/os-release; ldd --version | head -n 1     # P0-preflight: record OS and glibc
git clone https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles
export DOTFILES_AUTO_UPDATE=0 DOTFILES_PAYLOAD_AUTO_UPDATE=0
./doctor.sh --host sherlock                        # or marlowe
./setup-host.sh --host sherlock --check
./setup-host.sh --host sherlock                    # light steps on the login node; exit 3 at H2-alloc
sh_dev -t 1:00:00                                  # H2-alloc; Marlowe: an interactive Slurm job
cd ~/dotfiles && export DOTFILES_AUTO_UPDATE=0 DOTFILES_PAYLOAD_AUTO_UPDATE=0
export CONDA_PKGS_DIRS="$SCRATCH/.cache/conda/pkgs"  # Marlowe: "$SCRATCH/.cache/conda/pkgs/$USER"
./setup-host.sh --host sherlock                    # builds the login env inside the job; exit 3 at H7-native
exit                                               # back to the login node
# H7-native: the fresh-home procedure in H7-native
./setup-host.sh --host sherlock                    # exits 0 now
# H7-payloads (optional, any time): sh scripts/payload-update.sh --now
exec "$HOME/micromamba/envs/login/bin/zsh" -l
./doctor.sh --host sherlock --smoke
```

The `CONDA_PKGS_DIRS` line puts micromamba's package cache where the overlay
the handover deploys will put it, under `$SCRATCH`, instead of
`~/micromamba/pkgs` in your home quota; the env itself stays in your home. From
then on `ssh sherlock` from a workstation lands in that zsh. Agent CLIs come
from modules ([S2-modules](#s2-modules-hpc-modules-and-manual-ai-clis)), never
from a long-running agent on a login node.

### Native Windows

Clone onto NTFS, not into WSL. In Windows PowerShell or Terminal:

```powershell
winget install --id Git.Git -e
winget install --id Microsoft.PowerShell -e --source winget --installer-type wix   # the MSI (HW-clone)
# open a new PowerShell 7 (pwsh) window, then:
git clone https://github.com/FridrichMethod/dotfiles.git $HOME\dotfiles
cd $HOME\dotfiles
$env:DOTFILES_AUTO_UPDATE = '0'; $env:DOTFILES_PAYLOAD_AUTO_UPDATE = '0'
.\doctor.ps1 -Host win
.\setup-host.ps1 -Host win -Check
.\setup-host.ps1 -Host win      # exit 3 until HW-native is done
# HW-native: the fresh-home procedure in HW-native, unelevated
# open a new terminal, then from $HOME\dotfiles:
.\setup-host.ps1 -Host win      # exits 0 now; prints the non-blocking HW blocks
# H7-payloads (optional, any time, unelevated): .\scripts\payload-update.ps1 -Now
.\doctor.ps1 -Host win
```

The remaining Windows steps are HUMAN: execution policy, the ssh-agent
service, WSL and authentication (`HW-*` below; `.\setup-host.ps1 -PrintManual`
prints them all). An agent CLI first, if wanted:
`winget install --id Anthropic.ClaudeCode -e`.

### Other Linux

There is no Fedora, Arch or generic Ubuntu overlay, and `./setup-host.sh` takes
only `--host`. Select native `common-only`, install packages yourself, and do
the platform-neutral setup steps by hand
([X-other-linux](#x-other-linux-other-linux-distributions)). Paste `clone_listed`
and `fetch_pinned` from [Downloads and clones by hand](#downloads-and-clones-by-hand),
and `native_cz` and `native_handover` from [Fresh home by hand](#fresh-home-by-hand),
into your shell first.

```sh
# with your package manager: git zsh curl rsync tar file man ssh, tmux >= 3.4, python3 >= 3.11,
# and fzf, zoxide, eza, fd and bat at the floors in config/bootstrap/tools.tsv
git clone https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles
export DOTFILES_AUTO_UPDATE=0 DOTFILES_PAYLOAD_AUTO_UPDATE=0
./doctor.sh --platform other
for id in $(awk -F '\t' '/^#/ { next } !h { h = 1; next } { print $1 }' config/bootstrap/git-clones.tsv); do
    clone_listed "$id" || break                                    # S3-clones, oh-my-zsh first
done
f=$(fetch_pinned bat-theme) && d="$(bat --config-dir)/themes" && mkdir -p "$d" &&
    cp "$f" "$d/Catppuccin Mocha.tmTheme" && bat cache --build    # S3-bat-theme
mkdir -p ~/.vim/undo ~/.vim/tmp                                    # S3-dirs
f=$(fetch_pinned chezmoi "$(uname -m)") && mkdir -p "$HOME/.local/bin" && tar -xzOf "$f" chezmoi >"$HOME/.local/bin/chezmoi.new" && chmod 755 "$HOME/.local/bin/chezmoi.new" && mv -f "$HOME/.local/bin/chezmoi.new" "$HOME/.local/bin/chezmoi"
native_handover common-only    # H7-native, Fresh home by hand
# H7-payloads (optional, any time): sh scripts/payload-update.sh --now
exec zsh -l
./doctor.sh --platform other --smoke
```

## Contract

### doctor.sh

```text
./doctor.sh [--host H | --platform P] [--tier LIST] [--tsv] [--quiet] [--online] [--smoke]
./doctor.sh [--host H | --platform P] --list
./doctor.sh --help
```

`--list` resolves the host like every other mode, and `--host` or `--platform`
always wins. On a native-owned home (one with `~/.config/dotfiles/native`, in
any form) the host is the one quoted `host` line of the `[data]` table in
`~/.config/chezmoi/chezmoi.toml`, read as text, without chezmoi or git. A
missing, repeated, unknown or otherwise spelled role, or a linked or absent
config, exits 2 asking for `--host`. Any other home needs `--host` or
`--platform` and exits 2 otherwise (for example in a fresh clone or a linked
worktree); `DOTFILES_HOST` selects nothing. `common-only` as that
`[data].host` means the doctor checks the platform it detects (`macos`,
`debian`, `hpc` or `other`) without an overlay, exactly as `--platform` would,
and warns that it did.

| Flag | Meaning |
| --- | --- |
| `--host H` | `mac`, `wsl-ubuntu`, `lab-ubuntu`, `sherlock` or `marlowe` (`win` is refused; use `doctor.ps1`). Without it: on a native-owned home its `[data].host` (`common-only` there: the detected platform without an overlay); elsewhere none, exit 2. Never guessed |
| `--platform P` | `macos`, `debian`, `hpc` or `other`: no overlay, only rows whose hosts are `all` or `unix` |
| `--tier LIST` | Comma list of `core`, `cli`, `ai`, `desktop`, `contributor`, `host`, or `all`. Default `core,cli,ai`; rows in unselected tiers report `warn` and never fail the run |
| `--tsv` | Header `status id tier detail fix`, then 5 tab-separated columns per row; `fix` is `docs/bootstrap.md <step-id>` or `-` |
| `--quiet` | Only rows that are neither `ok` nor `skip`, then the summary |
| `--online` | Adds the only network probes: `gh auth status`, `claude auth status`, `codex login status`. A signed-out tool is `warn` and an absent one `skip`, so an exit 0 does not prove you are signed in. The probes may write the tools' own state in your home (claude rewrites `~/.claude.json` and keeps backups of it; some codex releases create `~/.codex/tmp`); the doctor itself still writes nothing |
| `--smoke` | Runs `DOTFILES_AUTO_UPDATE=0 DOTFILES_PAYLOAD_AUTO_UPDATE=0 zsh -ic true` and fails when its stdout or stderr has a line starting `[oh-my-zsh]` (oh-my-zsh echoes `plugin 'x' not found`, `theme 'x' not found` and `zoxide not found` on stdout), or matching `plugin .* not found`, `plugin: .* not found`, `plugin: Cannot find`, `command not found`, `no such file` or `Permission denied` (all case-insensitive); `stty:` noise passes. It may write zsh's own caches |
| `--list` | The rows and checks that apply, without probing |

Each line reads `[dotfiles] [<level>] <tier> <id>: <detail> (docs/bootstrap.md <step-id>)`,
for example `[dotfiles] [error] core fzf: 0.44.1 < 0.58.0 (docs/bootstrap.md S2-brew-bundle)`;
`ok` and `skip` rows end at the detail. Without `--tsv`, a summary line with
the count of each status closes the report.
Statuses are `ok`, `outdated`, `missing`, `warn`, `skip` and `human`. Besides the
`tools.tsv` rows the doctor runs structural checks: `locale`, `native-config`,
`path-order`, `rc-pollution`, `omz-order`, `nvm-homebrew` and `payloads`.
`native-config` names the state of this home's native binding by cause
([H7-native](#h7-native-reviewed-native-configuration-handover)). `payloads`
warns, never fails, while an item of
`DOTFILES_PAYLOAD_ITEMS` fails its probe in `config/payloads.tsv` or an
installed kit lacks a Claude helper, and names `sync-payloads ITEM`
([H7-payloads](#h7-payloads-payload-repos)).
The step it cites is the one that installs the tool on that
profile: `tools.tsv` names the Ubuntu or macOS step, and on `hpc` the apt and
Brewfile rows point at S2-login-env, the `node` row at S2-modules and the
locale check at P0-preflight (`claude` and `codex` are not checked there); on `macos` the apt rows (git-lfs, tmux and
the macOS baseline tools) point at S2-brew-bundle; under `--platform other`
every apt, Homebrew, Brewfile, nvm, Claude, Codex and locale reference points
at X-other-linux; on `windows` they point at the `W1-*` and `HW-*` steps (git
at HW-clone).

| Exit | Meaning |
| --- | --- |
| 0 | No selected-tier row is `missing`, `outdated` or `human`; `warn` and `skip` never fail the run |
| 1 | A selected-tier row, from `tools.tsv` or a structural check, is `missing`, `outdated` or `human` |
| 2 | Usage error, invalid manifest (a malformed `tools.tsv` row, or a doc step without its `###` heading here), unknown host, or `--host win` |

### setup-host.sh

```text
./setup-host.sh [--host H] [--tier LIST] [--check] [--yes]
                [--only STEP]... [--skip STEP]... [--keep-going]
./setup-host.sh [--host H] --list | --print-manual
./setup-host.sh --help
```

| Flag | Meaning |
| --- | --- |
| `--host H` | `mac`, `wsl-ubuntu`, `lab-ubuntu`, `sherlock` or `marlowe`, with the same default as the doctor (a native-owned home's `[data].host`); `win` is refused (use `setup-host.ps1`). There is no `--platform`: another Linux does the setup steps by hand ([X-other-linux](#x-other-linux-other-linux-distributions)), and `common-only` as that `[data].host` exits 2 asking for `--host` |
| `--tier LIST` | As for the doctor; default `core,cli,ai` |
| `--check` | One plan line per step, `<step-id> <state> <detail>` with state `done`, `todo`, `human`, `skip` or `failed` (a step held back by a prerequisite shows as `todo` or `human`, its detail starting with `blocked by <step-id>` or `waiting:`), then the pending HUMAN blocks; no writes, no network. Exits 3 while any step is `todo` |
| `--yes` | Apply without asking. Without it, a run in a terminal asks before each automatic step, and a run whose stdin is not a terminal (agents, CI) exits 2 |
| `--only STEP`, `--skip STEP` | Run only, or skip, that step id from this file; both repeat |
| `--keep-going` | Continue past a failed step instead of stopping there; the run still exits 1 |
| `--list` | The steps for this host as TSV: `id`, `kind` (`auto` or a HUMAN kind), `tier`, `blocking` |
| `--print-manual` | Every HUMAN block for this host, pending or not, then exit 0; that includes the judgment blocks an automatic step prints only in one situation, each with a note saying when: X-recovery (`~/.oh-my-zsh` without `oh-my-zsh.sh`), S2-brew-bundle (a conflicting formula or cask is installed) and S4-nvm (an `nvm.sh` that is not the pinned checkout). S2-brew-bundle's `sudo` block for a Homebrew prefix you cannot write names the prefix's owner, so it is printed only while that holds, for every Brewfile of the selected tiers |

Every step runs check, plan, apply, verify; a satisfied step is skipped, so a
second run changes nothing. During apply it exports `DOTFILES_AUTO_UPDATE=0
DOTFILES_PAYLOAD_AUTO_UPDATE=0 GIT_TERMINAL_PROMPT=0 NONINTERACTIVE=1
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1`
(and `HOMEBREW_BUNDLE_NO_LOCK=1`, so an older `brew bundle` writes no
`Brewfile.lock.json` into the checkout), and in every mode
`GH_TELEMETRY=0 GH_NO_UPDATE_NOTIFIER=1 TLDR_AUTO_UPDATE_DISABLED=1`:
S2-brew-bundle runs gh and tldr only as the doctor does, for their version,
and the export keeps that gh, and any a tool it starts may run, from writing
its device id, and a tldr C client from refreshing its page cache over the
network ([Guarantees](#guarantees)).
Before probing anything, both scripts prepend to their own PATH, when they
exist, the bin directory of the Homebrew they find (`/opt/homebrew`,
`/usr/local`, `/home/linuxbrew/.linuxbrew` or `~/.linuxbrew`), then
`~/.local/bin` (micromamba, codex, claude, kitty), then on hpc
`~/micromamba/envs/login/bin`, so the login env comes first on hpc, as in the
dotfiles' shells, and elsewhere what setup-host linked into `~/.local/bin` wins.
(The dotfiles' workstation shells run `brew shellenv` and the conda hook after
`~/.profile`, so there Homebrew and conda come before `~/.local/bin`.) A run
before the dotfiles are applied thus sees what earlier steps installed;
neither script writes this to an rc file. The doctor's `path-order` check
judges the PATH you started it with: it warns when a command setup-host puts in `~/.local/bin`
(`claude`, `codex`, `micromamba`, `kitty`, `kitten`) is shadowed by another
executable of the same name earlier on PATH (two installs of one tool), the
login env on hpc excepted, or when `~/.local/bin` is missing.
Downloads use `curl -fsSL --proto '=https' --tlsv1.2 --retry 3` into a `.part`
file that must match the pinned sha256 before it is used; a mismatch deletes
it and fails the step. Without curl, pinned downloads fall back to `wget`,
whose digest check still holds; the unpinned `inspect` download needs curl,
because wget follows a redirect to plain http.

| Exit | Meaning |
| --- | --- |
| 0 | Done: every selected step is done or does not apply; non-blocking HUMAN blocks may still be printed |
| 1 | A step failed |
| 2 | Usage error or refusal: unknown host (or none: no `--host`, or a native config without one known `[data].host`), `win`, run as root (or through sudo), a machine that is not that host (wrong kernel or distribution, a cluster host without `LMOD_DIR`, `wsl-ubuntu` outside WSL, `lab-ubuntu` inside WSL), no terminal without `--yes`, invalid manifest. `--list` and `--print-manual` skip the machine check |
| 3 | Work remains: a blocking HUMAN step is pending, or automatic steps are still to apply (under `--check`, after a declined prompt, or while they wait on a HUMAN step); handle the printed blocks and run it again |

`--list` shows which HUMAN steps block. A pending blocking step (Xcode CLT,
Homebrew, apt packages, Linuxbrew, the Slurm allocation, the Claude Code
installer, the native handover) holds back the
steps that need it and makes the run exit 3,
and so does an automatic step that needs a person's decision first: it shows
as `human` and prints a judgment block (the oh-my-zsh recovery of S3-clones, a
conflicting Homebrew formula or cask in S2-brew-bundle, an `nvm.sh` S4-nvm will not
source). S2-brew-bundle on a Homebrew prefix you cannot write (a shared
Linuxbrew) likewise shows as `human`, not `todo`, and prints a blocking `sudo`
block for the prefix's owner instead of running brew. A prerequisite you `--skip` or decline at the prompt holds back its HUMAN
dependents too (`H7-native human blocked by S2-brew-bundle (skipped)`); one that
`--tier` or `--only` leaves out does not. Non-blocking blocks (locale, fcitx5,
site modules, `chsh`, sign-in, the payload repos, the final doctor run) are printed
but leave the exit code alone. Since H7-native blocks, every run before the
handover exits 3.

Printed lines that run setup-host or the doctor again (in the H1-xcode-clt,
H1-homebrew, H1-linuxbrew, H2-alloc, S4-nvm, S5-claude, X-recovery and
H7-doctor blocks; on Windows in the HW-clone and HW-auth blocks and
W1-winget's PATH warning) do not repeat a non-default `--tier`; the closing
rerun warning of `setup-host.sh` does.

The Windows twins take the same ideas as PowerShell parameters:
`.\doctor.ps1 [-Host win] [-Tier LIST] [-Tsv] [-Quiet] [-Online]` and
`.\setup-host.ps1 [-Host win] [-Tier LIST] [-Check] [-Yes] [-PrintManual] [-WhatIf]`
(`-Host` defaults to `win`). Both need PowerShell 7
and never elevate themselves. `.\doctor.ps1` exits 0 when no selected-tier check is `missing`,
`outdated` or `human`, 1 when one is, and 2 for a usage error, another host or
an invalid manifest; its structural checks are `native-config` and
`payloads`, and `-Online` reports a signed-out
tool as `warn`, as on Unix (its auth probes, too, may write the tools' own
state). `.\setup-host.ps1` exits 3 while HW-clone or HW-native is pending;
the other HW blocks are printed but leave the exit code alone. Its `-Check` prints only
plan lines (`<step-id> <done|todo|human|skip> <detail>`, a HUMAN step's detail
ending in `blocks completion` or `does not block`) and, like the Unix
`--check`, exits 3 while a step is todo, so a `-Check` that exits 0 has
nothing left to apply. A declined prompt, like a non-interactive run without
`-Yes`, exits 2 and changes nothing.

### HUMAN blocks

The installer prints, and never runs, these blocks on stdout:

```text
HUMAN-BEGIN H1-apt-core sudo
# docs/bootstrap.md H1-apt-core
sudo apt-get update
sudo apt-get install -y --no-install-recommends zsh git git-lfs ...
HUMAN-END
```

The first line names the step and the kind. Every other line up to
`HUMAN-END` is either a note or a command:

- A line that starts with `# ` is a note, shown to the person and never run
  (Unix blocks open with a `# docs/bootstrap.md <step-id>` note).
- Every other line is one self-contained command. It needs no shell variable,
  working directory or other shell state from another line, so each line can
  run as its own top-level command; scripts in the checkout are named by their
  full path. Run them in order, top to bottom: a later line can need a file or
  a cached credential that an earlier one left (the Homebrew block runs
  `sudo -v`, then the installer, then `sudo -k`).
- A line of the form
  `printf '%s  %s\n' <sha256> <path> | sha256sum -c --status - && <command>`
  (`shasum -a 256 -c --status -` on macOS) is a digest gate: `<command>` runs
  only while the file still has that sha256, so the file that was verified or
  read is the file that runs. Run it as printed, as one command.
- A line of the form
  `(cd /tmp && sudo -u <owner> -H env HOMEBREW_NO_AUTO_UPDATE=1 ... <brew> <arguments>)`
  runs brew as the owner of a Homebrew prefix you cannot write
  ([S2-brew-bundle](#s2-brew-bundle-brewfile-bundles)). The parentheses keep
  the `cd` in a subshell, so your shell stays where it was. Run it as printed,
  as one command, too. These two forms are the only lines that chain commands.

| Kind | Who runs it | Meaning |
| --- | --- | --- |
| `sudo` | On macOS and Linux, the person, or an agent after the person approves the block in chat. On Windows always the person: the block needs an elevated shell, and agents never elevate | Needs root or another account: system packages, the system locale, `/home/linuxbrew`, a shared Homebrew prefix its owner installs into; on Windows, services |
| `auth` | The person | Browser or device-code login, passwords, keys, Kerberos tickets |
| `gui` | The person | A dialog, a Settings toggle or a relogin (Xcode CLT, the fcitx5 session) |
| `alloc` | The person | A Slurm allocation; heavy work on hpc runs only inside one |
| `chsh` | The person | Changes the login shell and asks for the password |
| `inspect` | The person reads, then runs | A vendor script that cannot be pinned by digest: read it before it runs |
| `judgment` | The person decides | A choice with tradeoffs: the native handover, the payload repos, site modules, the final doctor run, execution policy, WSL, a checkout that is not a git clone |

Any block whose note says it needs an elevated PowerShell (WSL, the ssh-agent
service) is the person's to run, whatever its kind.

### Guarantees

- `./doctor.sh` without `--online` or `--smoke`, and `./setup-host.sh --check`,
  write nothing anywhere and make no network calls. `--online` adds the three
  auth probes, which go online and may write the tools' own state
  (`~/.claude.json`; `~/.codex/tmp` for some codex releases); `--smoke` may
  write zsh's caches.
  The doctor never runs a tool whose version flag writes (the `brew`, `codex`,
  `nvim` and `pre-commit` rows are presence-only; S2-brew-bundle probes a
  Brewfile's tools with the same function), finds fonts by file name
  instead of through `fc-list` (which creates fontconfig caches). Both Unix
  scripts export `GH_TELEMETRY=0 GH_NO_UPDATE_NOTIFIER=1` (the Windows twins set
  them around each probe and restore yours): recent gh releases otherwise write
  `~/.local/state/gh/device-id` on any command, even `gh --version` (and may
  send telemetry for other commands). They also export
  `TLDR_AUTO_UPDATE_DISABLED=1`: the tldr C client (the `tldr` formula
  Homebrew removed in 2026-10, still on hosts that installed it) checks its
  page cache before it handles `--version`, and once `~/.tldrc/date` is two
  weeks old it otherwise downloads the tldr-pages archive into `~/.tldrc`
  first (tlrc, which the cli Brewfile and winget install, and tealdeer ignore
  the variable and never update on `--version`). Not even a temporary file:
  the Unix scripts use no here-documents or here-strings, which macOS's Bash
  3.2 backs with files in the system temporary directory.
  `tests/doctor.sh` runs the real doctor with the real manifest on the machine
  running the tests (`--platform debian` and `other`, an empty `HOME`), and
  checks that it changed nothing.
- The installer never invokes `sudo`, `chsh`, `conda init`, `micromamba shell
  init` or `git lfs install`, never initializes or applies native
  configuration, and never edits an rc file. It writes nothing inside the
  checkout.
- No `curl | sh`: every script is downloaded to a scratch directory first, and
  only `inspect` rows (today just Claude Code's installer) have no digest. A
  HUMAN block runs a downloaded script only behind a digest gate: the pinned
  sha256, or for an `inspect` download the digest of the copy the person read,
  which later runs keep instead of downloading it again.
- The pins cover what setup-host downloads itself: every `installers.tsv`
  row but the `inspect` one is sha256-pinned. The theme and plugin clones of
  `git-clones.tsv` are not pinned: each tracks its upstream default branch,
  like oh-my-zsh's own auto-update, and setup-host clones only a missing one
  and never modifies an existing clone
  ([S3-clones](#s3-clones-oh-my-zsh-theme-and-plugin-clones)). Unpinned plugin
  code runs in shell or tmux startup, the same trust model as oh-my-zsh's auto-update.
  What a package manager installs follows that manager's own current version
  and trust:
  Homebrew (`brew bundle`), apt, conda-forge (the login env, within the yml's
  floors), winget (`winget.json` names packages, not versions), PSGallery
  (W1-psresources runs `Install-PSResource -TrustRepository -AcceptLicense`
  for the current PSFzf, CompletionPredictor and
  Microsoft.WinGet.CommandNotFound, skipping PSGallery's untrusted-repository
  prompt) and oh-my-posh's font installer (W1-font fetches the current Nerd
  Fonts release, while S6-nerd-font on Linux uses a pinned archive).
- Everything a person must do ends up in a HUMAN block; exit 3 means work
  remains: a blocking block is pending, or automatic steps are still to apply.

### Downloads and clones by hand

The automatic steps below also list a manual equivalent. Those that download or
clone use these two helpers, which read the URL and digest from
`installers.tsv`, or the URL and branch from `git-clones.tsv`, instead of
copying them here. Paste them into the shell you are working in:

```sh
# fetch_pinned ID [ARCH]: download one installers.tsv row into a fresh temporary
# directory, check its sha256 and print the file's path. ARCH: $(uname -m).
fetch_pinned() {
    _row=$(awk -F '\t' -v id="$1" -v arch="${2:-any}" \
        '$1 == id && ($7 == arch || $7 == "any") { print; exit }' \
        "${DOTFILES_DIR:-$HOME/dotfiles}/config/bootstrap/installers.tsv")
    [ -n "$_row" ] || { echo "fetch_pinned: no row for $1 ${2:-any}" >&2; return 1; }
    _url=$(printf '%s\n' "$_row" | cut -f 3)
    _sum=$(printf '%s\n' "$_row" | cut -f 4)
    _dir=$(mktemp -d) || return 1
    _out=$_dir/$(basename "$_url")
    curl -fsSL --proto '=https' --tlsv1.2 --retry 3 -o "$_out" "$_url" || return 1
    if command -v sha256sum >/dev/null 2>&1; then _have=$(sha256sum "$_out"); else _have=$(shasum -a 256 "$_out"); fi
    _have=${_have%% *}
    if [ "$_sum" = - ]; then
        echo "fetch_pinned: $1 is unpinned (sha256 $_have, $(wc -c <"$_out") bytes); read it first" >&2
    elif [ "$_have" != "$_sum" ]; then
        rm -f "$_out"
        echo "fetch_pinned: $1 sha256 $_have, expected $_sum" >&2
        return 1
    fi
    printf '%s\n' "$_out"
}

# clone_listed ID: make one git-clones.tsv row's clone the way S3-clones does:
# a shallow clone of the row's branch, and an existing clone left as it is.
clone_listed() {
    _row=$(awk -F '\t' -v id="$1" '$1 == id { print; exit }' \
        "${DOTFILES_DIR:-$HOME/dotfiles}/config/bootstrap/git-clones.tsv")
    [ -n "$_row" ] || { echo "clone_listed: no row for $1" >&2; return 1; }
    _dest=$(printf '%s\n' "$_row" | cut -f 2)
    _url=$(printf '%s\n' "$_row" | cut -f 3)
    _ref=$(printf '%s\n' "$_row" | cut -f 4)
    case $_dest in
        '$HOME/'*) _dest=$HOME/${_dest#'$HOME/'} ;;
        '$ZSH_CUSTOM/'*) _dest=${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/${_dest#'$ZSH_CUSTOM/'} ;;
        *) echo "clone_listed: unsupported dest $_dest" >&2; return 1 ;;
    esac
    if [ -e "$_dest/.git" ]; then
        echo "clone_listed: $_dest is already a clone; left as it is" >&2
        return 0
    fi
    if [ "$1" = oh-my-zsh ]; then
        git clone --depth=1 --branch "$_ref" -c core.eol=lf -c core.autocrlf=false \
            -c fsck.zeroPaddedFilemode=ignore -c fetch.fsck.zeroPaddedFilemode=ignore \
            -c receive.fsck.zeroPaddedFilemode=ignore -c oh-my-zsh.remote=origin \
            -c oh-my-zsh.branch="$_ref" "$_url" "$_dest"
    else
        git clone --depth=1 --branch "$_ref" "$_url" "$_dest"
    fi
}
```

Per-architecture rows (`micromamba`, `codex`, `kitty`, `chezmoi`) need `"$(uname -m)"`
as the second argument of `fetch_pinned` (`x86_64` or `aarch64`).

## Running it with an agent

The project skill is `/dotfiles-bootstrap` in Claude Code
(`.claude/skills/dotfiles-bootstrap/`, invoked only on request) and
`$dotfiles-bootstrap` in Codex (`.agents/skills/dotfiles-bootstrap/`). Both are
short and send the agent here. The rules they follow:

- **Host.** The agent asks which overlay this machine is; it never infers one
  from the OS. A machine without an overlay is "other Linux": the doctor takes
  `--platform other`, and the setup steps are the manual ones in
  [X-other-linux](#x-other-linux-other-linux-distributions).
- **Quiet hooks.** Every command runs with
  `DOTFILES_AUTO_UPDATE=0 DOTFILES_PAYLOAD_AUTO_UPDATE=0` (the second is
  inert). Nothing installs the payload repos unless someone runs the
  [H7-payloads](#h7-payloads-payload-repos) line, so the agent asks the person
  whether to run it.
- **Plan first.** `./doctor.sh --host H --tsv` and
  `./setup-host.sh --host H --check`, shown to the person, before any apply.
  The apply is `./setup-host.sh --host H --yes`, because an agent's shell has
  no terminal. It writes outside the clone (`~/.oh-my-zsh`, `~/.local`, `~/.nvm`)
  and needs the network, so a sandboxed agent asks to run it with broader
  permissions; approving that one command is expected.
- **Block lines.** Lines starting with `# ` are notes to show the person, not
  commands to run. Every other line is one self-contained command (no variable
  or directory carries over from another line), so the agent runs them in order,
  each as its own command.
- **`sudo` blocks** run only after the person approves the block in chat. Each
  command line is then run as one visible top-level shell command, exactly as
  printed: never wrapped in `sh -c`, never inside a script, never chained to
  another command. The exceptions are the two forms a block prints as a single
  line, a digest gate (`printf ... | sha256sum -c --status - && <command>`) and
  S2-brew-bundle's shared-prefix line (`(cd /tmp && sudo -u <owner> ...)`): run
  each as printed, as one command. If sudo would ask for a password and the agent's
  shell has no terminal, the person runs the block in their own terminal
  instead. On native Windows a `sudo` block needs an elevated shell, so it is
  always the person's.
- **`auth`, `gui`, `alloc` and `chsh` blocks** are handed to the person, who
  says when they are done. **`inspect`** blocks: the agent shows the script's
  digest, size and contents, then waits. It runs the block's digest-gated
  `bash <path>` line only after the person approves it in chat, as one visible
  top-level command, or leaves it to the person. **`judgment`** blocks: the
  agent explains the choice and lets the person make it.
- **Handover.** Natively, the agent follows the H7-native block and
  [takeover.md](chezmoi-migration/takeover.md) with the person; it never
  improvises `chezmoi init --apply` or forces a whole home. On a fresh home
  (no earlier install) that is [Fresh home by hand](#fresh-home-by-hand)
  ([Fresh Windows home by hand](#fresh-windows-home-by-hand) on win), with the
  person.
- **Exit 3** means work remains: a blocking HUMAN step is pending, or automatic
  steps are still to apply, and H7-native blocks. The agent re-runs setup-host
  after each block until that step is the only one left, then does the
  handover, then runs setup-host once more, which exits 0. A `--check` that
  exits 0 has nothing left to do.
- **Never** `git lfs install`, `gh auth setup-git`, `conda init`,
  `micromamba shell init`, the upstream oh-my-zsh installer, rc-file edits,
  commits or pushes. After each installer, `git -C ~/dotfiles status --porcelain`
  stays empty ([X-rc-protection](#x-rc-protection-rc-file-protection)).
- **Done** means `./doctor.sh --host H --smoke` exits 0. The agent reports what
  it installed, which HUMAN blocks remain and any failure with its
  `docs/bootstrap.md <step-id>` reference.

### Prompt for an agent started outside the clone

Paste this into Claude Code or Codex when the session does not start inside
`~/dotfiles` (the project skills only load inside the clone):

```text
Bootstrap this machine with my dotfiles, https://github.com/FridrichMethod/dotfiles.
1. If ~/dotfiles does not exist, clone it with
   git clone https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
   (native Windows: follow HW-clone in docs/bootstrap.md first). Work only inside ~/dotfiles.
2. Read ~/dotfiles/docs/bootstrap.md completely. It is the contract; follow it over your defaults.
3. Ask me which host this is: mac, wsl-ubuntu, lab-ubuntu, sherlock, marlowe, win,
   or another Linux (then follow X-other-linux). Never guess. On win, use the
   PowerShell twins in every step below: .\doctor.ps1 -Host win -Tsv,
   .\setup-host.ps1 -Host win -Check, then -Yes; the handover is the HW-native
   block, and the finish is .\doctor.ps1 -Host win.
4. Run every command with DOTFILES_AUTO_UPDATE=0 DOTFILES_PAYLOAD_AUTO_UPDATE=0.
5. Run ./doctor.sh --host H --tsv and ./setup-host.sh --host H --check and show me the plan.
6. After I agree, run ./setup-host.sh --host H --yes. For each HUMAN block
   (lines starting with "# " are notes for me; every other line is one
   self-contained command, run in order):
   sudo: show it and wait for my approval, then run each command line as its own
   visible top-level command (never sh -c, never a script, never chained, except
   that a printed "printf ... | sha256sum -c --status - && ..." digest gate runs
   as printed, as one command);
   auth, gui, alloc, chsh: hand them to me and wait;
   inspect: show me the script's digest, size and contents and wait; run its
   digest-gated line only after I approve it, or leave it to me;
   judgment: explain the choice and let me decide.
7. Exit 3 means work remains (a blocking HUMAN step, or steps still to apply).
   Re-run setup-host after each block until H7-native (HW-native on win) is the
   only one left. Ask me about H7-payloads. Then go through the H7-native block
   and docs/chezmoi-migration/takeover.md with me (on a fresh home: the "Fresh
   home by hand" procedure under H7-native in docs/bootstrap.md); never improvise
   chezmoi init --apply or force a whole home. Re-run setup-host; it should
   exit 0.
8. Finish with ./doctor.sh --host H --smoke, then report what changed, what is
   still pending, and every failure with its docs/bootstrap.md step id.
Never run git lfs install, gh auth setup-git, conda init or micromamba shell init,
never edit rc files, and never commit or push.
```

## Phase 0: preflight

Each step below lists a read-only **Check**, the **Install** (exact commands,
or automatic via setup-host.sh), a **Verify**, and whether a **Human** is needed
and why.

### P0-preflight: Preflight

Applies to every host. Record what the machine is before installing anything:
OS release, architecture, glibc (conda-forge packages and vendor binaries each
have a minimum), the overlay the person chose, and a complete checkout.

- **Check:** `uname -sm; cat /etc/os-release 2>/dev/null || sw_vers; ldd --version 2>/dev/null | head -n 1; git -C ~/dotfiles status --porcelain`
- **Install:** `git clone https://github.com/FridrichMethod/dotfiles.git ~/dotfiles`
  (any path; native login updates follow the home binding that handover
  writes). The checkout has no submodules; the payload repos install only when
  you run them, through their own installers ([H7-payloads](#h7-payloads-payload-repos)).
- **Verify:** the status is empty. setup-host's P0-preflight line records the
  OS, architecture, glibc and detected platform, and warns about uncommitted
  changes in the checkout: the native login update does not run from a
  checkout with uncommitted changes
  ([X-rc-protection](#x-rc-protection-rc-file-protection)). On an older clone
  `git -C ~/dotfiles status --porcelain --ignored -- common` lists the retired
  submodule checkouts a pull left behind (`common/codex/coding-agent-kit`,
  `common/coding-agent-kit/coding-agent-kit`, `common/pymol/PyMOLScripts`,
  `common/sherlock-kit/sherlock-kit`): they are harmless, nothing reports or
  removes them, and once one holds no work of yours you can delete it by hand
  ([leftover checkouts](payloads.md#leftover-checkouts)).
- **Human:** yes (judgment: the person names the host overlay; setup-host
  prints no block for this step)

On `sherlock` and `marlowe` the doctor's `locale` check points here: the
cluster provides its locales, so a missing `en_US.UTF-8` is the site's to fix
(there is no `sudo locale-gen`); record it with the OS release.

## Phase 1: host prerequisites

These need root or a GUI, so the installer only prints them.

### H1-xcode-clt: Xcode Command Line Tools

Applies to `mac`. Provides `git`, `make` and the compilers Homebrew needs;
`git`, `bash`, `zsh`, `curl`, `rsync`, `tar`, `file`, `col` and `man` are
macOS baseline (manual rows in `tools.tsv`).

- **Check:** `xcode-select -p`
- **Install:** `xcode-select --install`
- **Verify:** `xcode-select -p && git --version`
- **Human:** yes (gui: macOS opens an install dialog)

### H1-homebrew: Homebrew on macOS

Applies to `mac`. Uses the commit-pinned `homebrew` row in
[`installers.tsv`](../config/bootstrap/installers.tsv). A fresh Homebrew stays
off PATH until the dotfiles zsh loads oh-my-zsh's `brew` plugin, so `doctor.sh`
and `setup-host.sh` prepend the directory of the brew they find to their own
PATH. In a shell before the handover where you run brew by hand, use
`eval "$(/opt/homebrew/bin/brew shellenv)"` (Intel: `/usr/local/bin/brew`) in
that shell only.

- **Check:** `test -x /opt/homebrew/bin/brew || test -x /usr/local/bin/brew`
  (running `brew --version` can rewrite Homebrew's `.git/describe-cache`, so the
  checks only look for the file)
- **Install:** `setup-host.sh` downloads and checks the script, then prints a
  sudo block with its path. Run its three command lines in order, in one
  terminal: `sudo -v` (non-interactive mode only works with sudo credentials
  already cached); then the digest gate
  `printf '%s  %s\n' <sha256> <path> | shasum -a 256 -c --status - && NONINTERACTIVE=1 /bin/bash <path>`,
  which runs the installer only while it still has the pinned sha256; then
  `sudo -k`. By hand: `f=$(fetch_pinned homebrew)`, then `sudo -v`, then
  `NONINTERACTIVE=1 /bin/bash "$f"` and `sudo -k` in the same terminal.
- **Verify:** `/opt/homebrew/bin/brew --version` (or `/usr/local/bin/brew`)
- **Human:** yes (sudo: the installer creates the Homebrew prefix and needs an
  administrator account)

Never paste the installer's "Next steps" `brew shellenv` lines into an rc file,
never `brew install openssh` (`mac/ssh` uses Apple's `UseKeychain`, which
Homebrew's OpenSSH rejects), and never `brew install nvm` (see
[S4-nvm](#s4-nvm-nvm-and-nodejs)).

### H1-apt-core: apt prerequisites

Applies to `wsl-ubuntu` and `lab-ubuntu`: the packages in
[`apt/common.txt`](../config/bootstrap/apt/common.txt) plus the host's
[`apt/wsl-ubuntu.txt`](../config/bootstrap/apt/wsl-ubuntu.txt) (wslu for
`wslview`, libnotify-bin for `notify-send`) or
[`apt/lab-ubuntu.txt`](../config/bootstrap/apt/lab-ubuntu.txt) (xclip,
wl-clipboard and the fcitx5 set). apt keeps the system pieces (zsh, git,
git-lfs, tmux, man, locales, build tools, and `openssh-client` for the
`ssh`, `ssh-agent` and `ssh-keygen` that the dotfiles `~/.ssh` config, the
overlays' ssh-agent plugin and [H7-auth](#h7-auth-authentication) need; a
minimal Ubuntu has none of them) and Python: `python3` and
`python3-venv` meet the 3.11 floor of setup-sync (Ubuntu 24.04 ships 3.12), so
no Linuxbrew python is bundled ([S2-brew-bundle](#s2-brew-bundle-brewfile-bundles)).
The interactive tools come from
Linuxbrew because Ubuntu 24.04's apt is below the floors (fzf 0.44.1,
gh 2.45) and renames bat and fd to `batcat` and `fdfind`. Ubuntu's apt gh is
too old and is not used, even where it is installed: the Linuxbrew gh of the
`cli` Brewfile comes first on PATH in the dotfiles shells, and it is what git's
github.com credential helper calls on lab-ubuntu, by its full path
`/home/linuxbrew/.linuxbrew/bin/gh` in `lab-ubuntu/git/.gitconfig_local`
(git started from a GUI or another non-login context may not have Linuxbrew
on PATH). gh needs no sudo on any host.

- **Check:** `grep -hv '^#' config/bootstrap/apt/common.txt config/bootstrap/apt/wsl-ubuntu.txt | xargs dpkg -s >/dev/null && echo ok`
  (use `lab-ubuntu.txt` on lab-ubuntu)
- **Install:** the printed sudo block, which is
  `sudo apt-get update` and then
  `sudo apt-get install -y --no-install-recommends` followed by every package of
  both lists.
- **Verify:** the check prints `ok`; doctor rows `zsh`, `git-lfs`, `tmux`, `col`,
  `man` and `python3` are `ok`.
- **Human:** yes (sudo: installs system packages)

On `wsl-ubuntu`, Windows PATH entries are appended inside the distribution, so
also confirm that `command -v claude codex node` resolves under your Linux home
or `/home/linuxbrew`, not to a Windows-side shim under `/mnt/c`.

### H1-locale: en_US.UTF-8 locale

Applies to `wsl-ubuntu` and `lab-ubuntu`. `common/sh/.profile` exports
`LANG=en_US.UTF-8`; without the generated locale every shell warns.

- **Check:** `locale -a | grep -qix 'en_US.utf8' && echo ok`
- **Install:** `sudo locale-gen en_US.UTF-8` (printed sudo block)
- **Verify:** the check prints `ok`; the doctor's `locale` check is `ok`.
- **Human:** yes (sudo: writes the system locale archive)

### H1-linuxbrew: Linuxbrew

Applies to `wsl-ubuntu` and `lab-ubuntu`, after H1-apt-core (it needs
build-essential, curl, git, procps and file). Same pinned `homebrew` row as
macOS; on Linux it installs into `/home/linuxbrew/.linuxbrew`. The overlay rc
files guard their `brew shellenv` line, so shells stay quiet before it exists.

- **Check:** `test -x /home/linuxbrew/.linuxbrew/bin/brew && echo ok`
- **Install:** the printed sudo block, the same three lines as on macOS with
  `sha256sum -c --status -` in the digest gate. By hand:
  `f=$(fetch_pinned homebrew)`, `sudo -v`, then `NONINTERACTIVE=1 /bin/bash "$f"`
  and `sudo -k` in the same terminal.
- **Verify:** `/home/linuxbrew/.linuxbrew/bin/brew --version`; doctor row
  `linuxbrew` is `ok`.
- **Human:** yes (sudo: creates `/home/linuxbrew` and gives it to you)

Never append the installer's "Next steps" lines to `~/.bashrc` or `~/.zshrc`;
the overlay already has them.

**A Linuxbrew owned by another account.** On a lab machine,
`/home/linuxbrew/.linuxbrew` may already exist and belong to a shared lab
account whose group you are not in (`ls -ld /home/linuxbrew/.linuxbrew`
names it). H1-linuxbrew is then `done`, since `brew` runs, but brew refuses to
install there as you ("The following directories are not writable by your
user"). S2-brew-bundle notices this before it runs brew and prints a `sudo`
block that installs the missing Brewfile entries as that account
([S2-brew-bundle](#s2-brew-bundle-brewfile-bundles)). Never follow brew's own
advice to `sudo chown -R` the prefix: that takes it away from the account that
maintains it and from everyone else who uses it.

### H1-fcitx5: fcitx5 input method

Applies to `lab-ubuntu`. The fcitx5 packages arrive with H1-apt-core; the
native handover (H7-native) deploys `~/.config/fcitx5/profile` (pinyin and
mozc) as a regular file.

- **Check:** `command -v fcitx5 && grep -s fcitx5 ~/.xinputrc`
- **Install:** `im-config -n fcitx5` (as you, no sudo), then the handover,
  then log out and back in.
- **Verify:** after the relogin, `pgrep -x fcitx5` finds the daemon and
  `fcitx5-remote` prints 1 or 2.
- **Human:** yes (gui: run as you, no sudo; the input method starts only after
  you log out and back in)

## Phase 2: package managers and environments

### S2-brew-bundle: Brewfile bundles

Applies to `mac`, `wsl-ubuntu` and `lab-ubuntu`. On macOS the doctor's rows
that Ubuntu gets from apt point here too: python3, git-lfs and tmux come from
the core Brewfile, and the rest (zsh, curl, rsync, tar, file, col, man) are
macOS baseline. One Brewfile per tier in
[`brew/`](../config/bootstrap/brew/): `core` (fzf, zoxide, eza, fd, bat;
on macOS also python, git-lfs and tmux), `cli` (ripgrep, git-delta, tlrc,
chafa, jq, neovim, aria2, uv, gh), `ai` and `desktop` (macOS casks only:
claude-code and codex; kitty, wezterm and the CaskaydiaMono Nerd Font) and
`contributor`. `--no-upgrade` never upgrades what is already installed, so an
old formula shows up as `outdated` in the doctor; upgrade it deliberately with
`brew upgrade <name>`. Never `brew bundle cleanup`.

- **Check:** every entry that applies here is satisfied: Homebrew has it, or
  the doctor already finds its tool, wherever it came from (Tools that apt,
  conda or the OS already provide, below). By hand,
  `HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --no-upgrade --file=config/bootstrap/brew/<tier>.Brewfile`
  for each selected tier answers for Homebrew alone. Keep the variable:
  `brew bundle` otherwise may run `brew update` first, which uses the network
  and writes the Homebrew prefix. Before the handover, put brew on PATH first, as
  H1-homebrew says.
- **Install:** automatic via setup-host.sh, for each selected tier with a
  missing entry: `brew bundle --no-upgrade` on the Brewfile, less the entries
  whose tools the doctor already finds, with
  `HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_BUNDLE_NO_LOCK=1`.
- **Verify:** `./doctor.sh --host H` shows the Brewfile rows (`fzf`,
  `eza`, `fd`, `gh`, ..., and on macOS `python3`) `ok` with their floors.
- **Human:** no, unless a conflicting formula or cask is installed (judgment,
  below) or you cannot write the Homebrew prefix (sudo, below)

**Tools that apt, conda or the OS already provide.** The step's goal is a
green doctor, not a Homebrew copy of every tool. Each `brew` and `cask` entry
that brew bundle installs on this platform (`if OS.mac?` and `if OS.linux?`
honoured as brew bundle honours them; every cask is macOS-only) maps to the
`tools.tsv` row of this host whose id is the entry's name (a tap's formula by
its last segment), or else to one that a `# alias: TOOL-ID NAME` line names
(`neovim` is `nvim`, `python` is `python3`, the `claude-code` cask is
`claude`, the `font-caskaydia-mono-nerd-font` cask is `nerd-font`). The entry
uses a host-only alias before a general row: on lab-ubuntu, `gh` maps to
`gh-linuxbrew`, which checks `/home/linuxbrew/.linuxbrew/bin/gh`, the exact
executable its GitHub/Gist credential helpers invoke, even from GUI Git.
That required file must be executable and meet the floor. The general `gh`
row continues to check PATH on every platform. An entry is satisfied when
the doctor's own probe for that row (`bootstrap_check_tool`,
`lib/bootstrap/checks.sh`) reports `ok`: the tool is found and, when the row
has a floor, at or above it, whoever installed it; for the font, a
CaskaydiaMono Nerd Font file in a font directory. One below its floor, of
unknown version against a floor (`warn` in the doctor), or not found at all
is not. An entry without a row would keep the plain rule, Homebrew's
`opt/<name>` link or `Caskroom/<token>` directory, but every entry has one
today, and `tests/bootstrap-manifest.sh` fails a Brewfile entry without one.
Homebrew's own copy satisfies an entry too, even an old one that
`--no-upgrade` leaves alone.
On lab-ubuntu, apt's `/usr/bin/jq`, `/usr/bin/aria2c` and `/usr/bin/shellcheck`
thus complete `cli` and `contributor` (their rows have no floor), and no
duplicate lands in a shared Linuxbrew, where it would shadow apt's copy in
every account's PATH. To have Homebrew's copy instead, remove the other one.

The step is `done` once every entry that applies is satisfied; otherwise its
plan line names only the missing entries, per Brewfile:
`S2-brew-bundle todo Brewfile entries to bundle: cli: git-delta; contributor: shfmt stylua (offline estimate from PREFIX/opt and the doctor's probes; apply runs brew bundle check)`.
Apply runs brew only for a Brewfile with an entry left: `brew bundle check`
and then `brew bundle --no-upgrade` on the Brewfile itself when none of its
entries is provided another way, as without this filter, and otherwise on
its lines less the provided entries, every `tap` line kept (a bare name may
come from any tap), fed through a pipe as `--file=-`. That keeps brew
bundle's own judgment of what Homebrew has, its taps and `--no-upgrade`, and
the conflict guard below still runs first. `brew bundle` reopens
`/dev/stdin` by path, which works on a pipe for the user who made it; the
owner of a shared prefix gets names on the command line instead (below). A
Brewfile with no entry left, because every one is provided or none applies
on this platform (`ai` and `desktop` hold only macOS casks), runs no brew at
all, not even `brew bundle check`, whose API refresh would go online. The
probes run each mapped row's version flag, as the doctor does (never one of a
presence-only row such as `nvim`, `codex` or `pre-commit`), with
`GH_TELEMETRY=0` and `TLDR_AUTO_UPDATE_DISABLED=1` exported, so `--check`
stays read-only and offline.

**Conflicting formulae and casks.** Homebrew refuses to install a formula or
cask next to one it `conflicts_with`, and `brew bundle` then fails with no more
than "brew bundle failed". A Brewfile names the conflicts the bootstrap knows
of, taken from each entry's `conflicts_with` on formulae.brew.sh when it was
pinned, in `# conflicts: FORMULA OTHER...` lines and, for casks,
`# conflicts: cask TOKEN OTHER...` lines (validated by
`tests/bootstrap-manifest.sh`). Today they are `core`'s `fd fdclone` (both
install `fd`), `cli`'s `tlrc tldr tealdeer` (all three install `tldr`: tlrc
`conflicts_with` tealdeer, and `tldr` is the C client, whose formula Homebrew
removed in 2026-10 but whose keg stays on a host that installed it), and the
macOS casks `claude-code` (`ai`, against `claude-code@latest`), `kitty` and
`wezterm` (`desktop`, each against its `@nightly` cask). Before it runs brew at
all, in `--check` and apply alike, S2-brew-bundle looks for each OTHER that is
installed while the Brewfile's own entry is not: a formula keg (`Cellar/OTHER`
under the Homebrew prefix it found, or under `$HOMEBREW_CELLAR`) while FORMULA
has neither a keg nor an `opt/` link, or a cask's `Caskroom/OTHER` while
`Caskroom/TOKEN` is absent. A pair whose Brewfile entry brew bundle skips on
this platform (the casks are `if OS.mac?`) is never judged, and neither is
one whose entry is satisfied another way (above), even by OTHER itself: a
linked C client or tealdeer puts a `tldr` in the prefix's `bin` that the
doctor accepts, so brew bundle never gets the `tlrc` entry, nothing
conflicts, and OTHER stays. A host that installed the C client before
Homebrew removed it is such a host: it bundles no tlrc and keeps its `tldr`.
What remains is OTHER installed while the doctor does not accept the entry's
tool, as with an unlinked keg. When it finds one,
the step is `human` and blocking (exit 3), and setup-host prints a judgment
block whose command line uninstalls it (`--formula` or `--cask`) with the brew
it found, by full path:

```text
HUMAN-BEGIN S2-brew-bundle judgment
# docs/bootstrap.md S2-brew-bundle
# Homebrew does not install tlrc (cli.Brewfile) while the tealdeer formula is installed (conflicts_with), so brew bundle would fail
# uninstall each conflicting formula or cask below; the next ./setup-host.sh run then bundles the Brewfile one
/home/linuxbrew/.linuxbrew/bin/brew uninstall --formula tealdeer
HUMAN-END
```

On a prefix you cannot write (a shared Homebrew prefix, below), the line runs
brew as the prefix's owner and the last note reads "uninstall each
conflicting formula or cask below as the owner; the next ./setup-host.sh run
then prints the owner's lines that install the Brewfile one", since that run
stops again at the owner's `sudo` block rather than bundling.

A leftover keg of the C client prints the same block with `tldr` in place of
`tealdeer` (its formula declared `conflicts_with` tlrc until Homebrew removed
it); Homebrew still uninstalls, and links, a keg whose formula it removed.
The `tldr` command comes back from the `tlrc` formula on the next run (a cask
such as `wezterm@nightly` likewise gives way to `wezterm`).
tlrc's `--color` takes a value; the C client (tldr-c-client), the `tldr`
formula Homebrew removed in 2026-10 and still on hosts that installed it,
takes a bare `-C`. The fzf-tab previews try `tldr --color always` (tlrc,
tealdeer) and then `tldr -C`, so they color with every client, and run both
with `TLDR_AUTO_UPDATE_DISABLED=1`, so the C client answers from its local
cache and never fetches a missing page or a stale archive while you
tab-complete. The conflict holds back the whole step, every selected
Brewfile, so keeping the other package instead means making its tool the one
the doctor finds (`brew link tealdeer`, or `brew link tldr` for the C client,
as the prefix's owner on a shared one), which satisfies the entry, or leaving
its tier out (for tlrc, `--tier core,ai`). The C client gets no fixes or
rebuilds from Homebrew any more, so uninstalling its keg is the better fix.
`--print-manual` prints the block for every declared pair that applies on
this platform. A conflict Homebrew adds later is not judged until a Brewfile
line names it ([Known limitations](#known-limitations)). See also
[X-recovery](#x-recovery-recovery-recipes).

**Python on macOS only.** The core Brewfile's `brew "python" if OS.mac?`
names Homebrew's `python` alias for its default `python@3.x`, the only formula
that links an unversioned `python3`. `--no-upgrade` never upgrades an
installed formula, but it resolves the alias each time: when Homebrew's
default moves (it became `python@3.15` on 2026-10-09, after `python@3.14`),
the next bundle installs the new `python@3.x` alongside the old one, which
stays installed until you remove it. On Debian and Ubuntu, apt's `python3`
and `python3-venv` from H1-apt-core already meet the 3.11 floor, and a
Linuxbrew python would add a whole new formula at every such move and, on a
shared prefix, relink `python3` for every account, so it is bundled on macOS
only, where it is needed (the Command Line Tools' `python3` is 3.9). The
manifest validator rejects a `python` or `python@3.x` Brewfile entry without
`if OS.mac?`.

**A shared Homebrew prefix.** brew refuses to install into a prefix whose
directories its user cannot write ("The following directories are not
writable by your user", then a `sudo chown -R` suggestion), as on a lab
machine whose `/home/linuxbrew/.linuxbrew` belongs to a shared lab account
(H1-linuxbrew). So before it runs brew at all, in `--check` and apply alike,
S2-brew-bundle takes the prefix from the brew it found (the parent of its
`bin`) and tests with `[ -w ]` whether you can write the prefix's `Cellar`,
its `bin` and Homebrew's repository (what `brew --repository` prints:
`PREFIX/Homebrew` on Linux and for `/usr/local`, while `/opt/homebrew` is its
own); a directory that does not exist yet counts as its parent, where brew
would create it. When one is not writable, it runs no brew command, not even
`brew bundle check`. The Brewfiles that the offline estimate (`opt/` links
and the doctor's probes, above) finds incomplete are pending: then the step
is `human`, not `todo`, and blocking (exit 3), and setup-host prints a `sudo`
block with one line per pending Brewfile (one for its formulae, one for its
casks) that installs, by name, its missing entries, as the account owning the
first unwritable directory (`stat`, else `ls -ld`):

```text
HUMAN-BEGIN S2-brew-bundle sudo
# docs/bootstrap.md S2-brew-bundle
# the Homebrew prefix /home/linuxbrew/.linuxbrew is shared and owned by lab; you cannot write /home/linuxbrew/.linuxbrew/Cellar, /home/linuxbrew/.linuxbrew/bin, /home/linuxbrew/.linuxbrew/Homebrew
# the lines below run brew as lab and change the prefix for everyone on this machine
# never chown a shared prefix: it belongs to lab and serves every account here
# each line installs by name the missing entries of one Brewfile, from /tmp: brew never opens the Brewfile or your home, which lab may not be able to read
# an entry is missing when the prefix lacks it and the doctor does not find its tool installed another way (apt, conda, the OS): no second copy in the shared prefix
# HOMEBREW_NO_INSTALL_UPGRADE=1 leaves an installed formula or cask alone, as brew bundle --no-upgrade does
(cd /tmp && sudo -u lab -H env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_INSTALL_UPGRADE=1 /home/linuxbrew/.linuxbrew/bin/brew install --formula gh tlrc)
HUMAN-END
```

Each line is self-contained. `sudo` resets the environment, so `env` passes
the Homebrew variables after it, and `-H` gives brew the owner's home for its
cache. The owner's brew never reads a file of yours: setup-host reads the
Brewfile as you and puts the names on the command line. Another account often
cannot read a Brewfile in your checkout, either because your home is closed
to it (mode `0750`) or because the file itself is (a clone made under
`umask 077` has `0600` Brewfiles), and handing the file over on stdin does not
help: `brew bundle --file=-` reopens `/dev/stdin` by path, and Linux then
checks the file's own mode against the owner. brew also refuses a working
directory its user cannot read, so the line starts in `/tmp`, inside
parentheses so the `cd` stays in a subshell. The names are the offline
estimate's missing entries, with the OS guards applied and a tap's formula as
`user/tap/name`, which `brew install` taps by itself (a `tap` line alone gets
no line); an entry whose tool the doctor finds installed another way is left
out, and a Brewfile with nothing missing gets no line. brew bundle installs
its missing entries with this same
`brew install`, and `HOMEBREW_NO_INSTALL_UPGRADE=1` leaves an entry that turns
out to be installed alone, as `--no-upgrade` does. Whatever the lines install
lands in the shared prefix for every account on the machine, which is the
point of a shared install; Homebrew links it there for everyone. Never
`chown` a shared prefix, even though brew's own error suggests it: that takes
it from the account that maintains it and from everyone using it. When every
Brewfile is already satisfied, the step is `done` without the owner. A
conflicting formula or cask there is uninstalled the same way: the judgment
block above then prints its `brew uninstall` as such a line, with the same
notes. `--print-manual` prints the block while you cannot write the prefix,
with every entry of each selected Brewfile that applies on this platform,
less those the prefix lacks whose tools the doctor finds installed another
way (so a pasted block puts no Homebrew `jq` in front of apt's on every
account's PATH), and nothing otherwise, since it names the owner.

### S2-micromamba: micromamba

Applies to `sherlock` and `marlowe`. The `micromamba` rows in
[`installers.tsv`](../config/bootstrap/installers.tsv) are a bare static
executable per architecture. One small download, fine on a login node.

- **Check:** `~/.local/bin/micromamba --version`
- **Install:** automatic via setup-host.sh (sha256-checked, mode 755). By hand:
  `f=$(fetch_pinned micromamba "$(uname -m)") && mkdir -p ~/.local/bin && install -m 0755 "$f" ~/.local/bin/micromamba`
- **Verify:** `~/.local/bin/micromamba --version` prints the release named in
  `installers.tsv`.
- **Human:** no

Never run `micromamba shell init` or the micro.mamba.pm script: the overlay rc
files already carry the hook block.

### H2-alloc: Slurm allocation

Applies to `sherlock` and `marlowe`. Build the login env on a compute node.
setup-host refuses S2-login-env while `SLURM_JOB_ID` is unset and its env needs
building. An existing login env satisfies this step.

- **Check:** `echo "${SLURM_JOB_ID:-none}"`
- **Install:** Sherlock: `sh_dev -t 1:00:00`. Marlowe: an interactive job with
  an explicit walltime, for example `srun -t 1:00:00 --pty bash -l` (check the
  partition and account Marlowe requires). Then, inside the job, export the two
  `*_AUTO_UPDATE=0` variables and `CONDA_PKGS_DIRS`
  ([S2-login-env](#s2-login-env-hpc-login-environment)) and re-run setup-host;
  the block prints it with the clone's full path, so it runs from any
  directory.
- **Verify:** `echo "$SLURM_JOB_ID"` is non-empty and `hostname` is a compute node.
- **Human:** yes (alloc: queueing and resources are the person's call)

### S2-login-env: HPC login environment

Applies to `sherlock` and `marlowe`, inside an allocation. The conda-forge spec
[`hpc-login-env.yml`](../config/bootstrap/hpc-login-env.yml) holds the shell and
CLI package names and constraints; [tools.tsv](../config/bootstrap/tools.tsv)
owns the doctor's version floors. Name traps are commented in the yml.
Every workstation's `ssh sherlock` / `ssh marlowe` RemoteCommand
execs `$HOME/micromamba/envs/login/bin/zsh`.

- **Check:** `~/micromamba/envs/login/bin/zsh --version && ~/micromamba/envs/login/bin/python3 --version`
- **Install:** automatic via setup-host.sh:
  `micromamba create -y -r "$HOME/micromamba" -n login -f config/bootstrap/hpc-login-env.yml`.
  After editing the yml, the same with `install` instead of `create`.
  `CONDA_PKGS_DIRS` is inherited. Once the handover deployed it, the overlay
  `.profile` points it at a cache under `$SCRATCH`, but the first build runs
  before the handover, so
  export the overlay's value in the job first; otherwise the cache lands in
  `~/micromamba/pkgs`, inside your home quota (`sh_quota` on Sherlock) and with
  heavy `$HOME` I/O. Sherlock:
  `export CONDA_PKGS_DIRS="$SCRATCH/.cache/conda/pkgs"`; Marlowe:
  `export CONDA_PKGS_DIRS="$SCRATCH/.cache/conda/pkgs/$USER"`. Check
  `echo "$SCRATCH"` first: before the handover only the site sets it, and the
  Marlowe overlay exports its own value.
- **Verify:** `./doctor.sh --host sherlock` shows `login-env` and the tool rows `ok`.
- **Human:** no (after H2-alloc)

Never create the env under `$SCRATCH`: scratch is purged (90 days on Sherlock)
and would take the login shell with it. A package cache there is fine.

### S2-modules: HPC modules and manual AI CLIs

Applies to `sherlock` and `marlowe`, and is where the doctor points for
`node` on hpc. There is no installer for this step: the cluster provides Lmod.
Sherlock's overlay zsh rc pins the modules it loads; Marlowe's only
initialises Lmod and loads none. Claude Code and Codex come only from optional
site modules here, so `tools.tsv` does not check them on hpc and the
completion gate does not depend on them; setup-host prints this block while
they are not on PATH, and H7-auth names them only once they are.

- **Check:** `echo "$LMOD_DIR"; ml spider claude-code codex pi-coding-agent; node --version`
- **Install:** none; `ml <module>` in your own session, or the overlay line for
  pinned modules.
- **Verify:** on Sherlock, in a dotfiles zsh, `ml list` shows the pinned
  modules; on both, `node --version` meets the `node` floor in `tools.tsv`.
- **Human:** yes (judgment: module availability and versions differ per cluster
  and change over time)

**Node.js.** On `marlowe`, `node` comes from the login env
([S2-login-env](#s2-login-env-hpc-login-environment): conda-forge `nodejs`,
`>=22.0` in the yml; the newest build on 2026-10-09 was 26.x). On `sherlock`,
it comes from Lmod `ml nodejs/24.13.0`, which `sherlock/zsh/.config/zsh/.zshrc`
loads after putting the login env on PATH, so the module wins. There is no nvm
on hpc.

**Lmod pins.** The `ml ...` line in `sherlock/zsh/.config/zsh/.zshrc` names
exact module versions (`ml spider <name>` lists what exists); a bump is a
reviewed change. Marlowe's overlay loads no modules.

**Agent CLIs** are manual rows. Look for site modules with
`ml spider claude-code codex pi-coding-agent` and verify on the host what is
actually there. If you
install Claude Code yourself into an NFS home instead, set `DISABLE_UPDATES=1`
in the environment it starts from, so sessions on several nodes do not race its
updater over the shared home. Do not leave agents running unattended on login
nodes.

**Sherlock toolkit.** Consumer projects install and pin `shk` from its
[standalone repository](https://github.com/FridrichMethod/sherlock-kit).
Neither setup-host nor the handover installs its launcher, rules or skill.
[sherlock-kit.md](sherlock-kit.md) covers retirement of earlier delivery.

**OS and glibc.** Record `cat /etc/os-release` and `ldd --version` on each
cluster; vendor binaries and conda-forge builds each need a minimum glibc.

## Phase 3: shell framework

### S3-clones: oh-my-zsh, theme and plugin clones

Applies to every Unix host, **before** the dotfiles are applied (the native
handover). Rows in
[`git-clones.tsv`](../config/bootstrap/git-clones.tsv) own repository names,
destinations and branches. Clone oh-my-zsh first; ZSH_CUSTOM defaults to
~/.oh-my-zsh/custom for the theme and zsh plugins; tmux plugins live under
~/.tmux/plugins/. Nothing here is pinned:
each row's `ref` is the repository's default branch (`master` or `main`),
and every clone tracks it, the way oh-my-zsh's own
auto-update (`zstyle ':omz:update' mode auto` in `common/zsh/.zshrc`) keeps
`~/.oh-my-zsh` on `master`. Downloads stay sha256-pinned in
[`installers.tsv`](../config/bootstrap/installers.tsv), the Catppuccin bat
theme file of S3-bat-theme included. The trade-off: unpinned theme and plugin
code runs in shell or tmux startup, the same trust model as oh-my-zsh's auto-update.

- **Check:** `test -f ~/.oh-my-zsh/oh-my-zsh.sh && git -C ~/.oh-my-zsh/custom/plugins/fzf-tab log -1 --oneline --decorate`
- **Install:** automatic via setup-host.sh, only for a clone that is missing.
  oh-my-zsh is cloned the way its own installer does:
  `git clone --depth=1 --branch master -c core.eol=lf -c core.autocrlf=false -c fsck.zeroPaddedFilemode=ignore -c fetch.fsck.zeroPaddedFilemode=ignore -c receive.fsck.zeroPaddedFilemode=ignore -c oh-my-zsh.remote=origin -c oh-my-zsh.branch=master https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh`.
  Every other row: `git clone --depth=1 --branch REF URL DEST`. By hand:
  `clone_listed ID` per row, oh-my-zsh first (the Other Linux quick start
  loops over all of them).
- **Verify:** doctor rows `oh-my-zsh`, `powerlevel10k`, the six zsh plugins,
  `tpm`, `tmux-resurrect`, `tmux-fzf`, `tmux-continuum`, `catppuccin-tmux`,
  `extrakto`, `tmux-yank`, `tmux-floax`, `tmux-which-key`, `tmux-cpu` and
  `tmux-battery` are `ok`. The clones are provisioned on all Unix hosts;
  the tmux config needs tmux 3.4 or newer (the `tools.tsv` floor).
- **Human:** no

setup-host never modifies an existing clone: a destination that is a git
checkout is left as it is, whatever its branch, commit or local changes; no
fetch, pull, checkout or status check runs there, and the step reports it
`done` with its branch and commit (`fzf-tab master@24105b1`) for information.
A destination that exists but is not a git checkout fails the step; move it
aside and re-run ([X-recovery](#x-recovery-recovery-recipes)). Never run the
upstream oh-my-zsh installer: it replaces `~/.zshrc` and can change your login
shell.

Updating is yours to do. oh-my-zsh updates itself, or with `omz update`, which
updates only oh-my-zsh itself. For the theme and zsh plugins, fast-forward each
clone to its upstream branch:

```sh
for d in "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"/plugins/* "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"/themes/powerlevel10k; do git -C "$d" pull --ff-only; done
```

A clone with local changes in the way or a diverged history makes its
`pull --ff-only` stop and say so, and the loop goes on with the next one.
`plugins/example`, which oh-my-zsh ships, lies inside the oh-my-zsh checkout,
so the loop fast-forwards oh-my-zsh as well.

For tmux, run `./setup-host.sh --host H --check --only S3-clones`, then
`./setup-host.sh --host H --yes --only S3-clones` to install missing plugins.
Keep `DOTFILES_AUTO_UPDATE=0 DOTFILES_PAYLOAD_AUTO_UPDATE=0` exported while
provisioning. Once `.tmux.conf` is in place, reload a running server with
`tmux source-file ~/.tmux.conf`; otherwise the next tmux start loads it.
There is no tmux startup download or automatic plugin update. Use TPM's
`prefix + U` for an explicit update and `prefix + I` after declaring another
plugin. Other Linux uses `clone_listed ID` as above. Native Windows installs
none of these clones. See [tmux usage](shell.md#tmux) for save/restore
keys, the recovery policy and shared-host limits.

### S3-bat-theme: bat theme

Applies to every Unix host (Windows: W1-bat-theme). `BAT_THEME` is
`Catppuccin Mocha`, which bat does not ship; the commit-pinned `bat-theme` row
in [`installers.tsv`](../config/bootstrap/installers.tsv) provides it. Needs bat
first (S2-brew-bundle or S2-login-env).

- **Check:** `bat --list-themes | grep -x 'Catppuccin Mocha'`
- **Install:** automatic via setup-host.sh: the file goes to
  `$BAT_CONFIG_DIR/themes/Catppuccin Mocha.tmTheme` (default
  `~/.config/bat/themes`), then `bat cache --build`. By hand:
  `f=$(fetch_pinned bat-theme) && d="$(bat --config-dir)/themes" && mkdir -p "$d" && cp "$f" "$d/Catppuccin Mocha.tmTheme" && bat cache --build`
- **Verify:** the check prints `Catppuccin Mocha`; doctor row `bat-theme` is `ok`.
- **Human:** no

### S3-dirs: Vim state directories

Applies to every Unix host. `common/vim/.vimrc` keeps undo files in
`~/.vim/undo` and swap and backup files in `~/.vim/tmp`.

- **Check:** `test -d ~/.vim/undo && test -d ~/.vim/tmp && echo ok`
- **Install:** automatic via setup-host.sh: `mkdir -p ~/.vim/undo ~/.vim/tmp`
- **Verify:** the check prints `ok`.
- **Human:** no

Editor note: the `vi` alias runs `nvim`, which the `cli` tier installs, but the
repository ships no `~/.config/nvim`; Neovim does not read `.vimrc`, so it starts
with its defaults.

## Phase 4: runtimes

### S4-nvm: nvm and Node.js

Applies to `mac`, `wsl-ubuntu` and `lab-ubuntu` (hpc: S2-modules; Windows:
winget's `OpenJS.NodeJS.LTS`). Node.js is required by the Claude Code hooks and
status line; its floor in `tools.tsv` is 22 (18 and 20 are end of life).
`common/sh/.profile` resolves nvm's `default` alias without sourcing `nvm.sh`,
so the alias must exist. Setup and doctor use the same discovery order:
a nonempty `NVM_DIR`, then an existing `~/.nvm`, then an existing
`${XDG_CONFIG_HOME:-$HOME/.config}/nvm`. With no installation, setup targets
`~/.nvm`; it does not create a second copy beside an existing XDG install.

- **Check:** `./setup-host.sh --host <host> --check --only S4-nvm` (offline; does not source `nvm.sh`).
- **Install:** automatic via setup-host.sh with the commit-pinned `nvm` row:
  `NVM_INSTALL_VERSION=<commit> PROFILE=/dev/null bash install.sh`, where
  `<commit>` is the commit in the row's URL. The installer would otherwise
  clone its release tag, which can move; with the commit it fetches exactly
  that commit, and `PROFILE=/dev/null` keeps it out of every rc file.
  setup-host sources `nvm.sh` (to run `nvm install --lts` and
  `nvm alias default 'lts/*'`) only when `$NVM_DIR` is a git checkout at that
  commit with no change to a tracked file; it removes a checkout it just made
  that is not. By hand, as one block that sources nothing unless that holds
  (paste `fetch_pinned` from [Downloads and clones by hand](#downloads-and-clones-by-hand)
  first):

  ```sh
  if [ -z "${NVM_DIR:-}" ]; then
      NVM_DIR=$HOME/.nvm
      if [ ! -d "$NVM_DIR" ] && [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/nvm" ]; then
          NVM_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/nvm
      fi
      export NVM_DIR
  fi
  (
      set -eu
      d=$NVM_DIR
      c=$(awk -F '\t' '$1 == "nvm" { split($3, p, "/"); print p[6]; exit }' \
          "${DOTFILES_DIR:-$HOME/dotfiles}/config/bootstrap/installers.tsv")
      case $c in
          '' | *[!0-9a-f]*) echo "installers.tsv names no nvm commit: [$c]" >&2 && exit 1 ;;
      esac
      test "${#c}" -eq 40 || exit 1
      if [ ! -s "$d/nvm.sh" ]; then
          f=$(fetch_pinned nvm) || exit 1
          mkdir -p "$d" || exit 1
          NVM_DIR=$d NVM_INSTALL_VERSION=$c PROFILE=/dev/null bash "$f" || exit 1
      fi
      head=$(git -C "$d" rev-parse HEAD) || exit 1
      changed=$(git -C "$d" status --porcelain --untracked-files=no) || exit 1
      if [ "$head" != "$c" ] || [ -n "$changed" ]; then
          echo "$d is at $head (or has local changes), not the pinned nvm commit $c; not sourced" >&2
          exit 1
      fi
  ) && . "$NVM_DIR/nvm.sh" && nvm install --lts && nvm alias default 'lts/*'
  ```

- **Verify:** in a new shell, `command -v node` is under the selected nvm directory's `versions/` and
  `node --version` meets the floor.
- **Human:** no, unless an existing nvm is not the pinned checkout (judgment,
  below)

**An nvm that is already there.** S4-nvm is `done` whenever `$NVM_DIR`'s
`default` alias selects an installed node at the floor, whatever installed
nvm: those are files, and nothing needs `nvm.sh`. It follows chained, exact,
partial, `node`/`stable` and named LTS aliases as `common/sh/.profile` does;
an empty, cyclic or unresolved alias, or a default below the floor, stays
pending even when a newer node is installed. When the default needs repair,
setup-host has to source `nvm.sh`, and then an `nvm.sh` that is not the pinned,
unmodified checkout (an older install, a checkout at another commit, a
directory that is not a git checkout, local edits) makes the step `human` and
blocking, with a judgment block instead of a source: `git -C ~/.nvm fetch` and
`git -C ~/.nvm checkout --detach` to the pinned commit (its `versions/` and
`alias/` stay), `git -C ~/.nvm status --short` and `checkout -- .` for local
edits, or `mv -n ~/.nvm ~/.nvm.pre-dotfiles` for a directory that is not a git
checkout, after which the next run installs the pinned nvm there. Each block
names the alternative of moving the directory aside in a note.
`--print-manual` prints the commit case.

Never install nvm with Homebrew; the doctor's `nvm-homebrew` check warns about
it and [X-recovery](#x-recovery-recovery-recipes) moves you off it. Install Node
before the first interactive `claude`.

## Phase 5: AI CLIs

Authenticate GitHub ([H7-auth](#h7-auth-authentication)) and install Node before
the first interactive `claude`: plugin marketplaces are cloned with your git
credentials and never prompt.

### S5-claude: Claude Code

Applies to `wsl-ubuntu` and `lab-ubuntu` through the `claude` row of
[`installers.tsv`](../config/bootstrap/installers.tsv); macOS uses the
`claude-code` cask (`ai` tier of S2-brew-bundle), hpc S2-modules, Windows
`Anthropic.ClaudeCode` (W1-winget). Anthropic's native installer cannot be
pinned by version or digest, so it is an `inspect` step.

- **Check:** `claude --version`
- **Install:** setup-host.sh downloads `https://claude.ai/install.sh` once to a
  scratch directory (later runs keep that copy; delete it for a fresh one) and
  prints a `HUMAN-BEGIN S5-claude inspect` block with its sha256, size and
  path. Read it: it should fetch Claude Code from Anthropic into your home
  directory and must not call sudo or edit rc files. Then run the block's
  digest gate,
  `printf '%s  %s\n' <sha256> <path> | sha256sum -c --status - && bash <path>`,
  which runs the copy only while it still has the digest the block showed. By
  hand: `f=$(fetch_pinned claude)`, `less "$f"`, `bash "$f"`.
- **Verify:** `claude --version` prints a version and `command -v claude` is
  `~/.local/bin/claude`; `git -C ~/dotfiles status --porcelain` is empty.
- **Human:** yes (inspect: an unpinned vendor script is read before it runs)

### S5-codex: Codex CLI

Applies to `wsl-ubuntu` and `lab-ubuntu` through the per-architecture `codex`
rows of [`installers.tsv`](../config/bootstrap/installers.tsv) (the upstream
`codex-package` musl tarball); macOS uses the `codex` cask, hpc S2-modules,
Windows `OpenAI.Codex`. The tarball is laid out the way OpenAI's installer does
it: extracted to `~/.codex/packages/standalone/releases/<version>-<target>/`
with a relative `codex -> bin/codex` link inside,
`~/.codex/packages/standalone/current` linked to that release, and
`~/.local/bin/codex` linked to `current/bin/codex`. The package bundles its own
`bwrap` (`codex-resources/bwrap`), `rg` and `codex-code-mode-host`, so no apt
`bubblewrap` is needed. OpenAI's `install.sh` is never run.

- **Check:** `codex --version; readlink ~/.local/bin/codex`
- **Install:** automatic via setup-host.sh. By hand (version and target come
  from the package's own `codex-package.json`), as one block: the subshell
  stops at the first failing command (`set -eu`) and refuses an empty or
  path-like version or target, so a failed download, unpack or JSON read never
  repoints `current` at `releases/` itself or removes a working install:

  ```sh
  (
      set -eu
      f=$(fetch_pinned codex "$(uname -m)")
      dest=$HOME/.codex/packages/standalone
      mkdir -p "$dest/releases" "$HOME/.local/bin"
      tmp=$(mktemp -d "$dest/.extract.XXXXXX")
      trap 'rm -rf "$tmp"' EXIT    # gone once moved into releases/
      tar -C "$tmp" -xzf "$f"
      ver=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$tmp/codex-package.json")
      tgt=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["target"])' "$tmp/codex-package.json")
      for name in "$ver" "$tgt"; do
          case $name in
              '' | .* | *[!A-Za-z0-9._-]*)
                  echo "codex-package.json: unusable version or target [$ver] [$tgt]" >&2
                  exit 1
                  ;;
          esac
      done
      test -x "$tmp/bin/codex"
      rel=$dest/releases/$ver-$tgt
      if [ ! -d "$rel" ]; then    # else this release is already unpacked
          ln -s bin/codex "$tmp/codex"
          mv "$tmp" "$rel"
      fi
      ln -sfn "$rel" "$dest/current"
      ln -sfn "$dest/current/bin/codex" "$HOME/.local/bin/codex"
  )
  ```

- **Verify:** `codex --version` reports the release named in `installers.tsv`.
- **Human:** no

On Ubuntu 24.04, AppArmor may restrict the unprivileged user namespaces that
bwrap needs. If Codex reports a sandbox failure, that is a judgment step: read
OpenAI's Linux sandbox documentation and decide on the AppArmor change yourself.

## Phase 6: desktop

Not in the default tiers; select `--tier all` (or add `desktop`).

### S6-nerd-font: Nerd Font

Applies to `lab-ubuntu` through the `nerd-font` row of
[`installers.tsv`](../config/bootstrap/installers.tsv) (a flat archive of
CaskaydiaMono Nerd Font `.ttf` files); macOS uses the
`font-caskaydia-mono-nerd-font` cask, Windows W1-font. On `wsl-ubuntu` the font
belongs to the Windows terminal, not the distribution.

- **Check:** `find ~/.local/share/fonts ~/.fonts /usr/share/fonts /usr/local/share/fonts -maxdepth 4 -iname '*CaskaydiaMonoNerdFont*' 2>/dev/null | head -n 1`
  (macOS: `ls ~/Library/Fonts /Library/Fonts | grep -i CaskaydiaMono`); the
  doctor's `nerd-font` row looks for the same file names, also under
  Homebrew's `share/fonts`.
- **Install:** automatic via setup-host.sh: extract into
  `$XDG_DATA_HOME/fonts/CaskaydiaMonoNerdFont` (default
  `~/.local/share/fonts/...`), then `fc-cache -f`. Like the doctor's row, the
  step counts a file named like `CaskaydiaMonoNerdFont` in the user, system or
  Homebrew font directories as installed
  (`font CaskaydiaMonoNerdFont at PATH`), so it never adds a second user copy.
  By hand:
  `f=$(fetch_pinned nerd-font) && d=~/.local/share/fonts/CaskaydiaMonoNerdFont && mkdir -p "$d" && tar -C "$d" -xJf "$f" && fc-cache -f`
- **Verify:** the check prints a font file and `fc-list | grep -i 'CaskaydiaMono Nerd Font'`
  lists the family; prompt and `eza` icons render in kitty and WezTerm.
- **Human:** no

### S6-kitty: kitty

Applies to `lab-ubuntu` through the per-architecture `kitty` rows of
[`installers.tsv`](../config/bootstrap/installers.tsv); macOS uses the `kitty`
cask. The `.txz` has `bin/`, `lib/` and `share/` at its top level.

- **Check:** `kitty --version; readlink ~/.local/bin/kitty`
- **Install:** automatic via setup-host.sh. By hand:
  `f=$(fetch_pinned kitty "$(uname -m)") && mkdir -p ~/.local/kitty.app ~/.local/bin && tar -C ~/.local/kitty.app -xJof "$f" && ln -sf ~/.local/kitty.app/bin/kitty ~/.local/kitty.app/bin/kitten ~/.local/bin/`
- **Verify:** `kitty --version` and `kitten --version` both run.
- **Human:** no (a desktop launcher is optional: copy
  `~/.local/kitty.app/share/applications/kitty.desktop` into
  `~/.local/share/applications/` and fix its paths, as kitty's install docs describe)

`kitten` on remotes: the `download` zsh function and kitty image previews call
`kitten` on the host you ssh into. No manifest installs it on hpc; if you want
them there, unpack the same tarball into your home on that host by hand.

## Phase 7: login shell and authentication

### H7-chsh: Login shell

Applies to `mac`, `wsl-ubuntu` and `lab-ubuntu`. macOS has used `/bin/zsh` by
default since Catalina. On hpc there is no `chsh`: zsh is reached through the
workstation's `ssh sherlock` / `ssh marlowe` RemoteCommand, which execs
`~/micromamba/envs/login/bin/zsh -il` (the native Windows ssh config still uses
an older RemoteCommand; the Windows terminal profiles ssh from inside WSL).

- **Check:** macOS `dscl . -read ~ UserShell`; Linux `getent passwd "$USER" | cut -d: -f7`
- **Install:** `chsh -s "$(command -v zsh)"` (the shell must be listed in
  `/etc/shells`; on Ubuntu it is `/usr/bin/zsh`)
- **Verify:** in a new login, `echo "$SHELL"` ends in `/zsh`.
- **Human:** yes (chsh: it asks for your password)

### H7-auth: Authentication

Applies to every Unix host (Windows: HW-auth). Do this before the first
interactive `claude` or `codex`.

- **Check:** `ssh -T git@github.com; gh auth status; claude auth status; codex login status`
  (or `./doctor.sh --host H --online`)
- **Install:**
  - SSH key: `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519` (the dotfiles' ssh config
    uses exactly that file, with `IdentitiesOnly yes`).
  - GitHub: `gh auth login --git-protocol ssh` (browser or device code; it offers
    to upload the public key). Do not run `gh auth setup-git`: it rewrites
    `~/.gitconfig`, which the dotfiles manage (a local change at which the next
    login update stops). Hosts that need gh as a
    credential helper already name it by full path in their
    `.gitconfig_local`: lab-ubuntu the Linuxbrew gh, marlowe the login env's.
  - Claude Code: run `claude` once in a terminal, or `claude auth login`.
  - Codex: `codex login` (`codex login --device-auth` on a headless host).
  - Kerberos for Sherlock and Marlowe: `kinit <SUNetID>@stanford.edu` on the
    workstation (krb5 is a host tool, X-host-tools); the ssh config delegates the
    ticket. The block setup-host prints on sherlock and marlowe also lists
    `kinit`, for a session on the cluster that has no delegated ticket. The
    `kstanford` alias (`common/sh/.aliases`) requests a 25 h ticket renewable
    for 7 days and, when kstart's `krenew` is installed, starts one background
    `krenew -K 60` that renews it until then; after that, run it again.
  - lab-ubuntu: Git Credential Manager with `credentialStore = gpg` needs a gpg
    key and `pass init <gpg-key-id>`. wsl-ubuntu uses the Windows-side Git
    Credential Manager from Git for Windows.
- **Verify:** `./doctor.sh --host H --online` shows the three auth probes `ok`.
  A signed-out tool shows `warn` and does not fail the run, so read the rows
  rather than the exit code.
- **Human:** yes (auth: browser or device-code logins, passwords and key
  passphrases)

### H7-payloads: Payload repos

Applies to every host. coding-agent-kit (the account launchers and the Claude
helpers that `settings.json` runs; Unix only, nothing on native Windows),
PyMOLScripts (`~/.pymolrc`, `~/.pymolrc.py`) and awesome-skills
(`~/.claude/skills`, `~/.codex/skills`, `~/.agents/skills/awesome-skills`)
install and update only when a person runs `scripts/payload-update.sh --now`
(`scripts/payload-update.ps1 -Now`): in the foreground, it installs each
absent item and updates each installed one through the repository's own
installer, named in [`config/payloads.tsv`](../config/payloads.tsv). No login,
profile or schedule installs or refreshes them, on any home, and the script
keeps no state of its own: files older automatic runs left (`ITEM.stamp`,
`ITEM.failed`, `payload.log`) are ignored and never removed. Each run
downloads its repository's unpinned `main` install script; the kit's installs
the newest patch release of the channel the file declares.
[payloads.md](payloads.md) is the contract.

setup-host prints this as a non-blocking judgment block until the doctor's
`payloads` row is `ok`; `setup-host.ps1` prints no block, and `doctor.ps1`'s
`payloads` row points here. `DOTFILES_PAYLOAD_ITEMS` (for example `kit pymol`)
selects the items a run without arguments installs and the doctor checks.

- **Check:** the doctor's `payloads` row (`./doctor.sh --host H`,
  `.\doctor.ps1 -Host win`): each selected item passes its probe, and on
  Unix an installed kit has its three helpers in `~/.claude/coding-agent-kit/`
  (`doctor.ps1` checks only PyMOLScripts and awesome-skills). A shortfall only
  warns and names `sync-payloads ITEM` and, on Unix, the `--now` line of the
  hook to run: on a native-owned home the hook of the source its binding
  names, never the checkout the doctor runs from, and none while the binding
  does not resolve.
- **Install:** the line the setup-host block prints, which works before the
  dotfiles are applied too: `sh ~/dotfiles/scripts/payload-update.sh --now [ITEM...]`
  (Windows, from an ordinary unelevated PowerShell 7:
  `& $HOME\dotfiles\scripts\payload-update.ps1 -Now [ITEM...]`); run it again to
  update. On a native-owned home the block names the script of the source the
  binding names (and says so), never the checkout setup-host runs from, and
  only a note while the binding does not resolve. In an interactive shell
  with the dotfiles applied, `sync-payloads [ITEM...]` does the same and
  `sync-skills` runs only the skills; on a native-owned home they run the
  bound checkout's script and refuse an invalid binding. An installer's exit
  75 (its own lock is busy) is no failure; any other failure makes the run exit 1
  and names what to run next. Active maintenance refuses a run. It needs `sh`
  and curl, or wget with an existing timeout/gtimeout (Windows: PowerShell 7),
  plus what each installer needs, which its README lists (Git for the kit and
  the skills).
- **Verify:** the `payloads` row is `ok`.
- **Human:** yes (judgment: whether and when to run unpinned scripts from
  branch heads)

### H7-doctor: Final doctor run

Applies to every host. This is the completion gate.

- **Check:** `./doctor.sh --host H --smoke` (Windows: `.\doctor.ps1 -Host win`)
- **Install:** none; follow the step each failing row names, then run it again.
- **Verify:** exit 0. Add `--online` for the auth probes and `--tier all` to see
  the desktop, contributor and host rows.
- **Human:** yes (judgment: setup-host prints it as a non-blocking reminder; the
  person or the agent runs it and decides whether the remaining warnings matter)

## Native Windows

The Windows steps, in the order you run them. Agents never elevate; every
elevated command is the person's.

### HW-clone: Clone the repository

The checkout tracks no symlink, so Git for Windows needs neither
`core.symlinks` nor Developer Mode; the native handover writes regular files.
The login updater pulls the checkout, so it must be a git clone, not an
extracted archive.

- **Check:** `Test-Path $HOME\dotfiles\.git; git -C $HOME\dotfiles status --porcelain`
- **Install:** `winget install --id Git.Git -e`,
  `winget install --id Microsoft.PowerShell -e --source winget --installer-type wix`,
  and in a new `pwsh` window
  `git clone https://github.com/FridrichMethod/dotfiles.git $HOME\dotfiles`.
  `--installer-type wix` selects the MSI, in `Program Files\PowerShell\7`.
  Since PowerShell 7.6.0 winget installs the MSIX package by default, whose
  `$PSHOME` under `Program Files\WindowsApps` is named for its version and
  replaced by each update. PowerShell 7.7
  ships only the MSIX package; 7.6 is the LTS release. Once 7.7 is the newest
  release, add `--version` with the newest 7.6 one
  (`winget show --id Microsoft.PowerShell -e --versions` lists them).
  Clone onto NTFS, never into a WSL distribution. An older clone made with
  `core.symlinks` and `--recurse-submodules` needs nothing: its leftover
  submodule checkouts are harmless
  ([leftover checkouts](payloads.md#leftover-checkouts)).
- **Verify:** `Test-Path` prints `True` and the status is empty.
- **Human:** yes (judgment: the person installs Git and PowerShell 7 and
  clones before `setup-host.ps1` can run from the clone; it blocks on this
  step only in a checkout that is not a git clone)

### W1-winget: winget import

Installs the package inventory in
[`winget.json`](../config/bootstrap/winget.json). Platform aliases and doctor
probes are defined in [tools.tsv](../config/bootstrap/tools.tsv), not in a
second documentation list.

- **Check:** `winget list --id Git.Git -e` (or `.\doctor.ps1 -Host win`)
- **Install:** automatic via setup-host.ps1:
  `winget import --import-file config\bootstrap\winget.json --no-upgrade --ignore-unavailable --accept-package-agreements --accept-source-agreements --disable-interactivity`,
  less the packages whose tools the doctor already finds (below).
  Already-installed packages count as success; other failures fail the step.
  Open a new terminal afterwards so the new PATH entries apply.
- **Verify:** `.\doctor.ps1 -Host win` shows the winget rows `ok`.
- **Human:** no (setup-host.ps1 runs it; a machine-wide installer may still
  raise a UAC prompt for the person to accept)

**Tools that another installer already provides.** As in S2-brew-bundle, the
goal is a green doctor, not a winget copy of every tool: winget sees only the
installs it made, so `--no-upgrade` alone would add a second Claude Code or
Codex next to the one from its own installer. Each package maps to the win
`tools.tsv` row that a `# alias: TOOL-ID PackageIdentifier` line names (a
win-only row first). setup-host.ps1 leaves the package out of the import when
the doctor's own verdict on that row (`Get-BootstrapToolStatus` in
`lib/bootstrap.ps1`) is `ok`: the tool is on PATH, whoever installed it, and
at or above the row's floor. A row with a version flag must print a version,
so a Microsoft Store alias stub does not count for it; a presence-only row
(`codex`, `nvim`, `wezterm`, `wt`) takes the first PATH match. The rest goes
to winget as a copy of `winget.json` in a scratch directory that is removed
afterwards; when nothing is left out, winget reads `winget.json` itself.

The verdict is the one the doctor gives in the same session. The step is
`todo` only while a tool is missing; a tool below its floor stays `outdated`
in the doctor and keeps its package in the import only when another tool
starts the step (`--no-upgrade` never upgrades a winget install). Probes see
this process's PATH: a tool installed by hand after the terminal opened is
not seen, and one from an activated venv or conda environment counts, so run
setup-host.ps1 from a new terminal with no environment activated. The running
PowerShell 7 always counts for `Microsoft.PowerShell`, which HW-clone installs
before the clone.

### W1-psresources: PowerShell modules

PSFzf, CompletionPredictor and Microsoft.WinGet.CommandNotFound, which the
PowerShell 7 profile uses only when present.

- **Check:** `Get-InstalledPSResource PSFzf, CompletionPredictor, Microsoft.WinGet.CommandNotFound`
- **Install:** automatic via setup-host.ps1, only for the missing ones, one at
  a time with `Install-PSResource -Name <module> -Scope CurrentUser -TrustRepository -AcceptLicense`:
  the current PSGallery version, not a pin (see [Guarantees](#guarantees)).
  By hand:
  `Install-PSResource -Name PSFzf, CompletionPredictor, Microsoft.WinGet.CommandNotFound -Scope CurrentUser`
  (PSGallery is untrusted by default, so a manual run asks to confirm).
- **Verify:** the check lists all three.
- **Human:** no

### W1-font: Nerd Font on Windows

Runs only when oh-my-posh is installed (W1-winget).

- **Check:** `Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Fonts", "$env:WINDIR\Fonts" -Filter 'CaskaydiaMono*' -ErrorAction Ignore`
- **Install:** automatic via setup-host.ps1: `oh-my-posh font install CascadiaMono`,
  which fetches the current Nerd Fonts release, unpinned (see
  [Guarantees](#guarantees)).
- **Verify:** the check lists the font files; restart Windows Terminal and WezTerm.
- **Human:** no

### W1-bat-theme: bat theme on Windows

The same commit-pinned `bat-theme` row as S3-bat-theme, in bat's Windows
config directory.

- **Check:** `.\setup-host.ps1 -Host win -Check` verifies the theme's sha256 pin
  and, when bat is installed, its registration in `bat --list-themes --color=never`.
- **Install:** automatic via setup-host.ps1: download with the sha256 check to
  `$env:APPDATA\bat\themes\Catppuccin Mocha.tmTheme`, then `bat cache --build`.
  A rerun reuses the matching file and repairs a missing cache, including after
  a failed build or when bat was installed later. A file whose bytes differ from
  the pin is preserved and fails apply: move it aside, then rerun setup-host.ps1.
- **Verify:** `bat --list-themes | Select-String -SimpleMatch 'Catppuccin Mocha'`
- **Human:** no

### HW-execution-policy: Execution policy

The tracked profiles and scripts are local files, which `RemoteSigned` allows.

- **Check:** `Get-ExecutionPolicy -List`
- **Install:** the block's two lines, one per PowerShell, since PowerShell 7
  and Windows PowerShell 5.1 keep the setting separately:
  `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` (in PowerShell 7) and
  `powershell.exe -NoProfile -Command Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`
  (for 5.1). Skip the second if you never use 5.1.
- **Verify:** `Get-ExecutionPolicy -Scope CurrentUser` prints `RemoteSigned`.
- **Human:** yes (judgment: a security setting)

### HW-ssh-agent: ssh-agent service

The OpenSSH agent ships disabled.

- **Check:** `Get-Service ssh-agent | Select-Object Status, StartType`
- **Install:** elevated: `Set-Service -Name ssh-agent -StartupType Automatic`,
  then `Start-Service ssh-agent`; then, as yourself, `ssh-add $HOME\.ssh\id_ed25519`.
- **Verify:** `ssh-add -l` lists the key.
- **Human:** yes (sudo: changing a service needs an elevated shell)

### HW-wsl: WSL distribution

The WezTerm and Windows Terminal configs open the distribution by the literal
name `Ubuntu` (`WSL:Ubuntu`, `wsl.exe -d Ubuntu`). Inside it, follow the Ubuntu
and WSL quick start with host `wsl-ubuntu`.

- **Check:** `wsl --list --verbose`
- **Install:** elevated: `wsl --install -d Ubuntu`, then reboot if asked.
- **Verify:** `wsl -d Ubuntu -- uname -a`
- **Human:** yes (judgment: optional; it needs an elevated shell and maybe a
  reboot, and the tracked `wsl.conf` needs review, below)

The judgment part: the native handover (HW-native) deploys `win/wsl/`'s
`.wslconfig`, `wsl.conf` and `mount.vbs` into your Windows home. `.wslconfig`
sizes memory and processors for one machine; review it. `wsl.conf` takes
effect only as `/etc/wsl.conf` inside the distribution, and the tracked one runs
`/usr/local/bin/mount-data.sh`, which this repository does not ship, and
hardcodes a `[user] default=` name. Copy only what fits this machine into
`/etc/wsl.conf` by hand (with sudo), then `wsl --shutdown`. `mount.vbs` mounts
one specific physical disk; do not schedule it on another machine.

### HW-auth: Windows authentication

- **Check:** `ssh -T git@github.com; gh auth status; claude auth status; codex login status`
  (or `.\doctor.ps1 -Host win -Online`)
- **Install:** `ssh-keygen -t ed25519 -f $HOME\.ssh\id_ed25519`;
  `gh auth login --git-protocol ssh`; Git Credential Manager comes with Git for
  Windows and `win/git/.gitconfig_local` selects it; `claude` once, or
  `claude auth login`; `codex login`. For Sherlock and Marlowe, the terminal
  profiles ssh from inside WSL, so `kinit` there. Skip `gh auth setup-git`:
  it would rewrite `~\.gitconfig`, which the dotfiles manage.
- **Verify:** `.\doctor.ps1 -Host win -Online` shows the auth probes `ok`.
- **Human:** yes (auth: browser logins and key passphrases)

## Optional and other platforms

### X-host-tools: Host-specific tools

The `host` tier of `tools.tsv` is reported, never installed: the per-overlay
miniconda prefixes, juliaup, TeX Live, GROMACS, CUDA, MATLAB, Schrodinger,
fcitx5 (H1-fcitx5), wslu and notify-send (H1-apt-core), Kerberos `kinit`, Git
Credential Manager, gpg and pass, Tailscale, and Lmod. A missing one costs only
what the doctor's `absent` text names. The one exception, micromamba with the
`login` env on hpc, is installed by S2-micromamba and S2-login-env. The
overlays' `conda initialize` blocks hardcode one machine's prefix; re-aiming
them is a separate change.

- **Check:** `./doctor.sh --host H --tier host`
- **Install:** each from its vendor or site, at the path the row probes.
- **Verify:** the doctor row turns `ok`.
- **Human:** yes (judgment: licensed or site-specific software)

### X-contributor: Contributor tools

For working on this repository: pre-commit, shfmt (3.13 or newer for the zsh
dialect), shellcheck and stylua. `pre-commit` provisions its own pinned hook
environments; the local binaries are for manual runs.

- **Check:** `./doctor.sh --host H --tier contributor`
- **Install:** mac and Ubuntu: `./setup-host.sh --host H --tier contributor`
  (the [contributor Brewfile](../config/bootstrap/brew/contributor.Brewfile));
  hpc: pre-commit, go-shfmt and shellcheck are in the login env, stylua is
  manual; Windows: `uv tool install pre-commit`.
- **Verify:** `pre-commit run --all-files`
- **Human:** no

### X-other-linux: Other Linux distributions

There are only six overlays; `fedora/` and `ubuntu/` do not exist. On any other
Linux, deploy the `common-only` role (`common/` without an overlay) and install
the packages yourself. An Ubuntu or Debian machine that is neither WSL nor the
lab desktop can use `--platform debian` for the doctor's rows.
`./setup-host.sh` needs a host overlay, so its four platform-neutral steps are
done by hand; the sequence at the end of this section runs them in order (the
Other Linux quick start repeats it).

- **Check:** `./doctor.sh --platform other` (its apt, Homebrew, Brewfile, nvm
  and locale references all point here)
- **Install:** with the distribution's package manager, the equivalents of
  [`apt/common.txt`](../config/bootstrap/apt/common.txt) and the Brewfile tools,
  meeting every floor in
  [`tools.tsv`](../config/bootstrap/tools.tsv) (distro fzf, eza, gh and tmux
  are often older; for tmux see
  [Known limitations](#known-limitations)), and the `en_US.UTF-8` locale (`locale-gen`
  or `localedef`, as the distribution does it); or install Homebrew on Linux
  yourself and run
  `HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_BUNDLE_NO_LOCK=1 brew bundle --file=config/bootstrap/brew/<tier>.Brewfile --no-upgrade`.
  Then, with `clone_listed` and `fetch_pinned` from
  [Downloads and clones by hand](#downloads-and-clones-by-hand): `clone_listed ID` for
  every `git-clones.tsv` row, oh-my-zsh first (S3-clones); the by-hand recipe of
  S3-bat-theme; `mkdir -p ~/.vim/undo ~/.vim/tmp` (S3-dirs); the by-hand line
  of [S4-chezmoi](#s4-chezmoi-native-chezmoi-binary). Finally, from the clone,
  `native_handover common-only` ([Fresh home by hand](#fresh-home-by-hand)).
- **Install, `ai` tier:** the default tiers also check `node` (at the floor in
  `tools.tsv`, for the Claude Code hooks and status line): the by-hand recipe
  of [S4-nvm](#s4-nvm-nvm-and-nodejs), or the distribution's Node.js if it
  meets the floor. Claude Code and Codex are optional here and not checked; to
  add them, `f=$(fetch_pinned claude)`, read it, then `bash "$f"`
  ([S5-claude](#s5-claude-claude-code)), and the by-hand recipe of
  [S5-codex](#s5-codex-codex-cli).
- **Verify:** `./doctor.sh --platform other --smoke` exits 0.
- **Human:** yes (sudo: distribution packages)

The native route as one sequence, with `clone_listed` and `fetch_pinned`
([Downloads and clones by hand](#downloads-and-clones-by-hand)) and `native_cz`
and `native_handover` ([Fresh home by hand](#fresh-home-by-hand)) pasted first:

```sh
# with your package manager: git zsh curl rsync tar file man ssh, tmux >= 3.4, python3 >= 3.11,
# and fzf, zoxide, eza, fd and bat at the floors in config/bootstrap/tools.tsv
git clone https://github.com/FridrichMethod/dotfiles.git ~/dotfiles
cd ~/dotfiles
export DOTFILES_AUTO_UPDATE=0 DOTFILES_PAYLOAD_AUTO_UPDATE=0
./doctor.sh --platform other
for id in $(awk -F '\t' '/^#/ { next } !h { h = 1; next } { print $1 }' config/bootstrap/git-clones.tsv); do
    clone_listed "$id" || break                                    # S3-clones, oh-my-zsh first
done
f=$(fetch_pinned bat-theme) && d="$(bat --config-dir)/themes" && mkdir -p "$d" &&
    cp "$f" "$d/Catppuccin Mocha.tmTheme" && bat cache --build    # S3-bat-theme
mkdir -p ~/.vim/undo ~/.vim/tmp                                    # S3-dirs
f=$(fetch_pinned chezmoi "$(uname -m)") && mkdir -p "$HOME/.local/bin" && tar -xzOf "$f" chezmoi >"$HOME/.local/bin/chezmoi.new" && chmod 755 "$HOME/.local/bin/chezmoi.new" && mv -f "$HOME/.local/bin/chezmoi.new" "$HOME/.local/bin/chezmoi"
native_handover common-only    # H7-native, Fresh home by hand
# H7-payloads (optional, any time): sh scripts/payload-update.sh --now
exec zsh -l
./doctor.sh --platform other --smoke
```

## Appendix: rc-file protection

### X-rc-protection: rc-file protection

On a native home `~/.zshrc`, `~/.bashrc`, `~/.profile` and `~/.gitconfig` are
regular files that chezmoi manages: anything a third-party installer appends
is a local change at which the next login update stops, so later targets stay
stale until you review it with a private targeted native diff
([takeover.md](chezmoi-migration/takeover.md#updates-and-edits-after-takeover)).
The doctor's `rc-pollution` check reads the checkout
(it cannot see a native file's append): it reports `human` for
`~/.zshrc.pre-oh-my-zsh`, and for a `# >>> Codex installer >>>` block, any
conda or mamba initialize block or an nvm loader in a `common/` rc file, and
`warn` for other uncommitted changes under `common/`. Keep every installer away
from rc files:

- nvm: `PROFILE=/dev/null`.
- uv's standalone installer: `UV_NO_MODIFY_PATH=1` (the bootstrap installs uv
  with Homebrew, conda-forge or winget instead).
- micromamba's install script: `INIT_YES=no` (the bootstrap uses the bare
  binary), and never `micromamba shell init`.
- OpenAI's Codex installer: `CODEX_NON_INTERACTIVE=1`, and only once
  `~/.local/bin` is already on PATH; otherwise it appends a PATH block (the
  bootstrap never runs it).
- Homebrew: `NONINTERACTIVE=1`, and never paste its `brew shellenv` "Next steps"
  lines.
- Never `git lfs install` (the `lfs` filter is already in `common/git/.gitconfig`
  and the command rewrites `~/.gitconfig`, which the dotfiles manage), never
  `gh auth setup-git` (same file), never `conda init`, never the upstream
  oh-my-zsh installer.

PATH belongs in `common/sh/.profile`, which already puts `~/.local/bin` first;
AGENTS.md's shell conventions say to discard installer PATH blocks and keep
only their intent there.

setup-host enforces this for its own steps: it records the checkout's state
before each step and fails the step when anything changed, comparing file
content, so an edit to a file that was already modified still fails. Start from
a clean checkout; P0-preflight warns when it is not, also because the native
login update does not run from a checkout with uncommitted changes.

- **Check:** `git -C ~/dotfiles status --porcelain` (must print nothing)
- **Install:** if it lists a file, read `git -C ~/dotfiles diff <file>`. When the
  diff is only an installer's block, discard it with
  `git -C ~/dotfiles restore <file>`; when your own edits are in the same file,
  delete just the block by hand.
- **Verify:** the check prints nothing and the doctor's `rc-pollution` check is `ok`.
- **Human:** yes (judgment: confirm the diff is only the installer's block before
  discarding it)

## Appendix: recovery

### X-recovery: Recovery recipes

- **Check:** `./doctor.sh --host H` (the `omz-order`, `rc-pollution` and
  `nvm-homebrew` checks point here)
- **Install:** the matching recipe below.
- **Verify:** the doctor check that pointed here is `ok`.
- **Human:** yes (judgment: each recipe moves or replaces files)

**oh-my-zsh after the dotfiles.** `~/.oh-my-zsh/custom/` exists (a native
directory preparation made it) but `~/.oh-my-zsh/oh-my-zsh.sh` does
not, so S3-clones refuses and the doctor's `omz-order` check says "the dotfiles
were applied before the clone". Turn the directory into the checkout in place,
keeping the dotfiles' custom files:

```sh
git -C ~/.oh-my-zsh init
git -C ~/.oh-my-zsh remote add origin https://github.com/ohmyzsh/ohmyzsh.git
git -C ~/.oh-my-zsh fetch --depth=1 origin master
git -C ~/.oh-my-zsh checkout -b master origin/master
git -C ~/.oh-my-zsh config oh-my-zsh.remote origin
git -C ~/.oh-my-zsh config oh-my-zsh.branch master
```

Then re-run `./setup-host.sh --host H` for the theme and plugin clones. When S3-clones refuses, setup-host prints this
recipe with your paths as an X-recovery block, with the clone settings of
[S3-clones](#s3-clones-oh-my-zsh-theme-and-plugin-clones) set before the fetch
and that rerun line.

**Clone destination that is not a git checkout.** S3-clones fails with
"DEST exists and is not a git checkout": a plugin or theme directory that was
copied by hand, or left by another plugin manager. Look at it, move it aside
(`mv DEST DEST.pre-dotfiles`), then `./setup-host.sh --host H --only S3-clones`
clones it afresh. An existing clone, dirty or not, is never touched; to
update one, see [S3-clones](#s3-clones-oh-my-zsh-theme-and-plugin-clones). A
dirty `~/dotfiles` checkout after an installer is
[X-rc-protection](#x-rc-protection-rc-file-protection).

**Conflicting Homebrew formula or cask.** S2-brew-bundle is `human` with "the
installed tldr formula conflicts with tlrc (cli.Brewfile)" (a keg of the C
client, whose formula Homebrew removed in 2026-10; or, on macOS, for example
"the installed wezterm@nightly cask conflicts with wezterm
(desktop.Brewfile)"), or `brew bundle` failed with "Cannot install tlrc
because conflicting formulae are installed" or a cask conflict. Check with
`ls "$(brew --prefix)/Cellar" "$(brew --prefix)/Caskroom"`, then uninstall the
other package by the path setup-host printed, for example
`/home/linuxbrew/.linuxbrew/bin/brew uninstall --formula tldr` (tealdeer the
same way) or `/opt/homebrew/bin/brew uninstall --cask wezterm@nightly`, and run
`./setup-host.sh --host H --only S2-brew-bundle`; the Brewfile's package then
takes its place. To keep the other package instead, link it
(`brew link tldr`): a `tldr` the doctor finds satisfies the entry, so the
pair is no longer judged. If brew refuses because another formula depends on
it, keep it and leave its tier out instead
([S2-brew-bundle](#s2-brew-bundle-brewfile-bundles)). A failure that names a
conflict no Brewfile declares is the same fix by hand; add its
`# conflicts:` line to the Brewfile as well. On a Linuxbrew prefix owned by
another account (a shared lab install), only that account can uninstall or
install: setup-host prints the uninstall as a `(cd /tmp && sudo -u <owner> ...)`
line, and a conflict found by hand is uninstalled the same way; never `chown`
the prefix.

**Digest mismatch.** setup-host deletes the `.part` file and fails the step with
the expected and actual sha256. Never edit the digest just to make it pass.
Retry once (a proxy or captive portal can serve an HTML page). If the artifact
really changed upstream, or you want a newer release, review the new artifact
(release notes; for a script, its diff against the pinned commit), download it,
compute its digest (`sha256sum FILE`, macOS `shasum -a 256 FILE`), update its
`url` and `sha256` and the `# pinned` date in
[`installers.tsv`](../config/bootstrap/installers.tsv), run
`bash tests/bootstrap-manifest.sh`, commit, and re-run setup-host.

**Homebrew-installed nvm.** `brew list nvm` succeeds and the doctor's
`nvm-homebrew` check warns. Run `brew uninstall nvm` and delete the
`$(brew --prefix nvm)/nvm.sh` lines Homebrew's caveat told you to add (they
are a local change at which the next login update stops; see
X-rc-protection). Keep `~/.nvm`, whose
`versions/` stay usable, then run `./setup-host.sh --host mac --only S4-nvm`;
the pinned installer turns `~/.nvm` into its own checkout.

**`~/.zshrc.pre-oh-my-zsh`.** The upstream oh-my-zsh installer ran: it moved
your `~/.zshrc` (a regular file) to `~/.zshrc.pre-oh-my-zsh`, wrote its template `~/.zshrc`, and may have
changed your login shell. Check with `ls -l ~/.zshrc ~/.zshrc.pre-oh-my-zsh`
and move the template aside (`mv ~/.zshrc ~/.zshrc.omz-template`). On a native
home, move `~/.zshrc.pre-oh-my-zsh` back to `~/.zshrc` (a nonforce apply
refuses an absent target it wrote, as it refuses an edited one), review it with
a private targeted native diff, and apply only that target with the full
argument set, `--exclude=dirs` and `--force=false`
([takeover.md](chezmoi-migration/takeover.md#updates-and-edits-after-takeover)).
Then, if needed, [H7-chsh](#h7-chsh-login-shell).

## Known limitations

Accepted gaps, each low in impact; none of them weakens a step's
fail-closed behavior beyond what is stated.

- **rc-pollution guard granularity.** The guard
  ([X-rc-protection](#x-rc-protection-rc-file-protection)) fingerprints each
  top-level `git status --porcelain` entry of the checkout: a file's content,
  a link's target. A nested repository that git does not track is one
  `?? dir/` entry, so an installer that edits a file inside a nested
  untracked repository after it is already dirty goes unnoticed. Nothing the
  bootstrap runs writes there.
- **Execution policy set only through `EnableScripts`.**
  [HW-execution-policy](#hw-execution-policy-execution-policy) reads the
  `ExecutionPolicy` values (the policy keys, then CurrentUser and Windows
  PowerShell 5.1's key). A "Turn on Script Execution: Disabled" policy stored
  only as `EnableScripts=0` is not detected, so its non-blocking judgment
  block may not be printed; `Get-ExecutionPolicy -List` still shows it.
- **lab-ubuntu zsh overlay outside an interactive shell.** Sourcing
  `lab-ubuntu/zsh/.config/zsh/.zshrc` in a non-interactive `zsh` with Linuxbrew
  and the `/apps/miniconda3` mamba hook present prints
  `compinit: initialization aborted` and `command not found: compdef`. This
  predates the bootstrap; interactive shells are fine, and
  `tests/host-overlays.sh` keeps real conda and mamba setup out of the
  Linuxbrew guard checks. Isolated fakes also cover portable tool discovery,
  HOME paths and fallback commands.
- **A conflicting formula is judged by its keg.** S2-brew-bundle stops when
  `Cellar/<formula>` of a declared conflict exists, linked or not (a cask, when
  its `Caskroom/<token>` exists), unless the doctor finds the Brewfile entry's
  tool. Homebrew itself refuses only a linked formula, so an unlinked keg
  stops the step although `brew bundle` would succeed; uninstalling or
  linking it is still the fix.
- **Only declared conflicts are judged.** The `# conflicts:` lines record the
  `conflicts_with` data that formulae.brew.sh listed for each Brewfile entry
  when its Brewfile was pinned (the `# pinned` date at its top), plus `cli`'s
  `tldr`, the C client that Homebrew removed in 2026-10 and so no longer
  lists, whose leftover keg installs the same `tldr` as tlrc. A conflict
  Homebrew adds later fails `brew bundle` with "brew bundle failed for <file>"
  until a Brewfile line names it ([X-recovery](#x-recovery-recovery-recipes)).
- **A Homebrew prefix owned by another account.** H1-linuxbrew is `done` once
  `brew` runs, whoever owns `/home/linuxbrew/.linuxbrew`. S2-brew-bundle tests
  only `[ -w ]` on the prefix's `Cellar`, `bin` and repository, so a prefix
  that other directories (an ACL, a read-only `opt` or `var`) keep you out of
  still runs `brew bundle` as you, and it fails inside brew. With a prefix you
  cannot write it decides what is pending from the offline estimate (`opt/`
  links and the doctor's probes) alone, never `brew bundle check`. The owner
  it names is that of the first unwritable directory; when you own it
  yourself (a mode you changed), the block's `sudo -u` line names you and
  cannot help: restore the mode instead.
- **Ubuntu 22.04 needs a newer Python by hand.** Its apt `python3` is 3.10,
  below the `tools.tsv` 3.11 floor, and no Linux Brewfile bundles a python, so
  the doctor's `python3` row stays `outdated` until you install a newer one
  yourself; it still points at H1-apt-core, which cannot raise the version.
- **Some distributions' tmux is below the 3.4 floor.** apt installs tmux
  3.2a on Ubuntu 22.04 and 3.3a on Debian 12, and RHEL 9's packages carry
  3.2a, so the doctor's `tmux` row is `outdated` and points at H1-apt-core
  (or X-other-linux), which cannot raise it, and that tmux rejects the
  shared config's 3.4-only options when it loads. Provide tmux 3.4 or newer yourself: a newer
  distribution release (Ubuntu 24.04 ships 3.4), conda-forge's `tmux` in a
  user env, as the HPC login env does, or Homebrew's (`brew install tmux`;
  the Linux Brewfiles leave it out). Keep the newer one first on PATH in every
  shell that starts or attaches tmux: a server and a client of different
  versions sharing the default socket can fail to talk (the
  [Marlowe note](shell.md#tmux)).
- **Windows Terminal re-serializes its settings.** Terminal saves
  `settings.json` in place whenever the file it loads is not in its own form,
  which shows up as destination drift (`chezmoi diff`). Terminal releases can
  reorder its arrays, so inspect and retain the native serialization in the
  source if starting Terminal changes the deployed file. The Windows PowerShell and Command Prompt stubs
  stay `"hidden": true`: Terminal treats a generated profile that its
  `state.json` lists but `settings.json` omits as deleted, so a visible stub
  brings both profiles back on a host that had already dropped them.

## Known follow-ups

Deferred on purpose; each is a separate change.

- **StyLua hook without Rust.** `.pre-commit-config.yaml` uses the StyLua
  hook id `stylua`, which builds StyLua with cargo, so a contributor needs
  Rust; switch to the `stylua-github` id, which downloads the release binary.
- **Windows ssh RemoteCommand.** `win/ssh/.ssh/config.d/legacy.conf` still
  runs `/bin/bash -ilc 'exec zsh -l'` for sherlock and marlowe; align it with
  the login-env form the other overlays use
  (`exec "$HOME/micromamba/envs/login/bin/zsh" -il`).
- **`win/wsl` is not a `$HOME`-shaped package.** Native apply deploys
  `wsl.conf` and `mount.vbs` into `%USERPROFILE%`, where neither does
  anything: `wsl.conf` only works as `/etc/wsl.conf` inside the distribution,
  and its `mount-data.sh` is not shipped
  ([HW-wsl](#hw-wsl-wsl-distribution)). Split it into what belongs in the
  Windows home (`.wslconfig`) and a documented by-hand copy.
- **Doctor quota note on hpc.** The doctor does not mention the home quota
  (`sh_quota` on Sherlock) that a login env and package cache count against;
  [S2-login-env](#s2-login-env-hpc-login-environment) documents it instead.
- **Cross-OS runs.** The macOS (Bash 3.2, BSD tools) and native Windows jobs
  of `ci.yml` run the fixture suites, so the PowerShell twins run natively
  only against shims. The opt-in end-to-end suite
  ([docs/testing.md](testing.md#end-to-end-bootstrap-opt-in)) has run the
  bootstrap for real in Linux containers and on GitHub's `macos-15` and
  `windows-2025` runners (the [acceptance checklist](#acceptance-checklist)
  below). Those runners are not fresh machines, and no real-machine row
  exists yet: a fresh macOS VM, a fresh WSL distribution, Sherlock, Marlowe
  and Windows 11 remain.

## Acceptance checklist

Fresh-machine acceptance is still pending for the platforms below. Container
and hosted-runner tests approximate portions of setup; they do not prove site
policy, real credentials, fresh Windows 11 or untouched macOS behavior.
Each run starts from a fresh machine, follows the quick start for its
platform, and passes when all of these hold:

- `./doctor.sh --host H` (Windows `.\doctor.ps1 -Host win`) exits 0 for the
  default tiers, and `--smoke` exits 0 on Unix.
- `./setup-host.sh --host H --check` wrote nothing: a
  `find "$HOME" -newer <marker>` taken around it is empty.
- A second `./setup-host.sh --host H` installs nothing and exits 0.
- `git -C ~/dotfiles status --porcelain` is empty after every step.
- No step ran sudo, `chsh` or an rc edit outside a HUMAN block.
- The H7-payloads run line (`sh ~/dotfiles/scripts/payload-update.sh --now`,
  Windows `scripts\payload-update.ps1 -Now`) exits 0, and the doctor's
  `payloads` row is then `ok`.

| Run | Date | Result | Notes |
| --- | --- | --- | --- |
| Fresh macOS VM (Apple Silicon), host `mac` | | not yet run | |
| Fresh WSL `Ubuntu` (24.04), host `wsl-ubuntu` | | not yet run | |
| Sherlock inside `sh_dev`, host `sherlock` | | not yet run | |
| Marlowe inside an interactive Slurm job, host `marlowe` | | not yet run | |
| Native Windows 11, host `win` | | not yet run | |

Keep new acceptance records with their reproducible run artifacts: revision,
platform, tool versions, options, failures and limitations. Historical runner
and container receipts are available in Git history, not maintained as current
operational guarantees here. The [opt-in suite](testing.md#end-to-end-bootstrap-opt-in)
implements the HUMAN-block policy and checks idempotence, no-write modes and
quiet startup. Native site/desktop acceptance remains a separate check.
