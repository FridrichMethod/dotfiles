#!/bin/bash

set -euo pipefail

# The two login updaters must keep one contract: same opt-out, same session
# marker, fast-forward only, and never an automatic re-stow. Only the POSIX one
# can be executed here, so the parity checks are static; the PowerShell one
# gets a parse check when pwsh is present (GitHub's Ubuntu runners ship it).

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SH_UPDATER="$REPO_ROOT/dotfiles-update.sh"
PS_UPDATER="$REPO_ROOT/dotfiles-update.ps1"
PS_PROFILE="$REPO_ROOT/win/powershell/Documents/PowerShell/profile.ps1"

for f in "$SH_UPDATER" "$PS_UPDATER" "$PS_PROFILE"; do
    if [ ! -r "$f" ]; then
        echo "ERROR: missing $f" >&2
        exit 1
    fi
done

# Shared contract, asserted on both implementations.
for token in _DOTFILES_CHECKED DOTFILES_AUTO_UPDATE DOTFILES_DIR --ff-only 'submodule update'; do
    for f in "$SH_UPDATER" "$PS_UPDATER"; do
        if ! grep -Fq -e "$token" "$f"; then
            echo "ERROR: $(basename "$f") lost the '$token' part of the contract" >&2
            exit 1
        fi
    done
done

# Every `pwsh -Command ...` loads the profile, so without the no-console guard
# the hook would fetch on every scripted invocation.
grep -Fq '[Console]::IsOutputRedirected' "$PS_UPDATER"

# The profile must actually reach the updater, and only at the end.
grep -Fq 'dotfiles-update.ps1' "$PS_PROFILE"

# Re-stowing stays manual, and the hint must say elevated: a login shell is not
# elevated, so an automatic or unelevated re-stow would create untrusted links.
if [ "$(grep -c 'stow-all\.ps1' "$PS_UPDATER")" -ne 1 ]; then
    echo "ERROR: dotfiles-update.ps1 should mention stow-all.ps1 exactly once" >&2
    exit 1
fi
if ! grep -Eq "Write-DotfilesNote '.*stow-all\.ps1 from an elevated PowerShell" "$PS_UPDATER"; then
    echo "ERROR: the re-stow hint must be a message and must say elevated" >&2
    exit 1
fi

# 'Stop' would turn a failed git fetch into a terminating error on 7.4+ and
# abort the profile, so the script must opt out and check exit codes instead.
grep -Fq 'PSNativeCommandUseErrorActionPreference = $false' "$PS_UPDATER"

if command -v pwsh >/dev/null 2>&1; then
    for f in "$PS_UPDATER" "$PS_PROFILE"; do
        PS_FILE="$f" pwsh -NoProfile -NonInteractive -Command '
            $path = $env:PS_FILE
            if (-not (Test-Path -LiteralPath $path)) {
                Write-Output "file not found at $path"
                exit 1
            }
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $path, [ref]$null, [ref]$errors)
            if ($errors) { $errors | ForEach-Object { $_.ToString() }; exit 1 }
        '
    done
fi

echo "update-hooks=PASS"
