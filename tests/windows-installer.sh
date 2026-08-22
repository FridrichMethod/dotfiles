#!/bin/bash

set -euo pipefail

# The Windows installer cannot be executed in CI - there is no pwsh, and the
# behaviour under test is an NTFS reparse-point property - so these are static
# assertions on the source plus an optional parse check when pwsh exists.

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

# GitHub's Ubuntu runners ship pwsh, so this parse check does run in CI. The
# path travels through the environment because -Command does not populate
# $args, which silently parsed a null path until CI caught it.
if command -v pwsh >/dev/null 2>&1; then
    INSTALLER_PATH="$INSTALLER" pwsh -NoProfile -NonInteractive -Command '
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
fi

echo "windows-installer=PASS"
