#!/bin/bash

set -euo pipefail

# Unix contract checks supplement tests/windows-installer.ps1, which exercises
# actual links and helper processes in the native Windows CI job. A normal
# hosted job cannot establish SSH network-logon reparse-point trust.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$REPO_ROOT/stow-all.ps1"

# A symlink whose target already matches is indistinguishable from a healthy one
# until something opens it: an untrusted reparse point carries the same tag,
# flags and substitute name. Losing this probe silently reintroduces dotfiles
# that resolve locally and fail in every ssh session.
grep -Fq 'function Test-FileOpens' "$INSTALLER"
grep -Fq 'function Test-UntrustedLink' "$INSTALLER"
grep -Fq 'if (-not (Test-UntrustedLink -Link $destination' "$INSTALLER"

if ! grep -Fq 'Repair untrusted symlink' "$INSTALLER"; then
    echo "ERROR: installer must repair untrusted symlinks, not skip them" >&2
    exit 1
fi

# Only an elevated token creates a trusted link, so an unelevated run must warn
# instead of rewriting a link into an equally untrusted one.
grep -Fq '$script:IsElevated' "$INSTALLER"
if ! grep -Fq 'untrusted symlink left in place' "$INSTALLER"; then
    echo "ERROR: unelevated run must warn about untrusted symlinks it kept" >&2
    exit 1
fi
if ! grep -Fq 'created from a non-elevated session are' "$INSTALLER"; then
    echo "ERROR: unelevated run must warn about untrusted links it created" >&2
    exit 1
fi
grep -Fq 'repaired: $script:Repaired' "$INSTALLER"

# Isolated targets and validation-only helper calls are part of the installer
# contract. Native behavior tests exercise them; these guard Unix-only runs.
grep -Fq '[string]$TargetRoot' "$INSTALLER"
grep -Fq 'foreach ($sync in $syncPlan) { Invoke-PortableSync @sync -CheckOnly }' "$INSTALLER"
grep -Fq 'if ($recordAppliedState -and -not $WhatIfPreference' "$INSTALLER"
grep -Fq "Unsupported Windows host:" "$INSTALLER"

# The help text and README must not send anyone back to the unelevated path.
if grep -Fq 'symlinks can be created without an elevated prompt' "$INSTALLER"; then
    echo "ERROR: installer help still recommends the unelevated path" >&2
    exit 1
fi
if grep -Fq 'so symlinks need no elevation' "$REPO_ROOT/README.md"; then
    echo "ERROR: README still recommends the unelevated path" >&2
    exit 1
fi
grep -Fq 'untrusted mount point' "$REPO_ROOT/README.md"

# Both repository guides carry the rule; agents read one or the other.
for guide in CLAUDE.md AGENTS.md; do
    if ! grep -Fq 'untrusted mount point' "$REPO_ROOT/$guide"; then
        echo "ERROR: $guide is missing the untrusted-symlink rule" >&2
        exit 1
    fi
done

# Parse both the installer and native fixture when PowerShell is installed.
# The paths travel through the environment because -Command does not populate
# $args, which previously let a null path escape this check.
if command -v pwsh >/dev/null 2>&1; then
    for ps_file in "$INSTALLER" "$REPO_ROOT/tests/windows-installer.ps1"; do
        INSTALLER_PATH="$ps_file" pwsh -NoProfile -NonInteractive -Command '
        $path = $env:INSTALLER_PATH
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Output "installer not found at $path"
            exit 1
        }
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $path, [ref]$null, [ref]$errors)
        if ($errors) { $errors | ForEach-Object { $_.ToString() }; exit 1 }
    '
    done
else
    printf 'SKIP: Windows installer/native fixture parse checks (pwsh unavailable).\n'
fi

echo "windows-installer=PASS"
