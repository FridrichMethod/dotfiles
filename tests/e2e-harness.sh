#!/bin/bash

# Unit test of the opt-in end-to-end bootstrap harness, tests/e2e/inside.sh
# and tests/e2e/lib/*.sh, without Docker or network. Part one sources the
# libraries and checks the HUMAN block parser (notes against commands, %q
# paths with spaces), the "HUMAN steps pending:" reader, every row of the
# (step id, kind) policy including the fail rows, the digest-gate regex, the
# E2E_ALLOC_ENV expansion and the audit parsers against fixture logs. Part
# two runs inside.sh itself with E2E_SANDBOX_HOME against a fixture clone
# whose setup-host.sh, doctor.sh and stow-all.sh are stubs printing
# realistic plan lines, blocks and exit codes (first apply exit 3 with an
# apt sudo block, then an inspect block, then H7-stow, then exit 0), with
# stub sudo, chsh, stow and apt-get wrappers that write the wrappers.log
# format, and once more at a fixture commit whose doctor.sh calls sudo
# outside a human phase, which must fail the wrappers audit. Every write
# lands under this test's temp dir; the sandbox home has a space in its
# name. Runs under the Bash that runs the test, so Bash 3.2 too.

set -euo pipefail

# Hermetic: the provisioning exports (DOTFILES_AUTO_UPDATE=0 and the like,
# docs/bootstrap.md) and other dotfiles knobs never reach the code under
# test from the caller; each case sets what it needs.
unset DOTFILES_AUTO_UPDATE DOTFILES_AUTO_STOW DOTFILES_HOST DOTFILES_DIR _DOTFILES_CHECKED \
    DOTFILES_STOW_WITHOUT_OH_MY_ZSH DOTFILES_COLOR AWESOME_SKILLS_AUTO_UPDATE AWESOME_SKILLS_FORCE \
    AWESOME_SKILLS_BG AWESOME_SKILLS_INSTALLER_URL AWESOME_SKILLS_REFRESH_DAYS _AWESOME_SKILLS_CHECKED

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
E2E_DIR="$REPO_ROOT/tests/e2e"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-e2e-harness.XXXXXX")"
TEST_TMP="$(cd -- "$TEST_TMP" && pwd -P)"
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM
STARTED=$(date +%s)
TAB=$(printf '\t')

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

# expect_eq NAME GOT WANT: an exact string comparison.
expect_eq() {
    [ "$2" = "$3" ] || fail "$1: got [$2], expected [$3]"
}

# expect_text NAME FILE TEXT / expect_no_text: fixed-string file checks.
expect_text() {
    grep -F -- "$3" "$2" >/dev/null || {
        printf -- '--- %s\n' "$2" >&2
        cat "$2" >&2 || true
        fail "$1: $2 lacks [$3]"
    }
}

expect_no_text() {
    if grep -F -- "$3" "$2" >/dev/null; then
        printf -- '--- %s\n' "$2" >&2
        cat "$2" >&2 || true
        fail "$1: $2 holds [$3]"
    fi
}

# --- part one: the libraries ---------------------------------------------

UNIT="$TEST_TMP/unit"
mkdir -p "$UNIT/log"
# shellcheck disable=SC2034 # the run state the sourced libraries read
E2E_OUT=$UNIT E2E_RUN_USER=tester E2E_SETUP_HOST=lab-ubuntu
# shellcheck source=tests/e2e/lib/common.sh
. "$E2E_DIR/lib/common.sh"
# shellcheck source=tests/e2e/lib/blocks.sh
. "$E2E_DIR/lib/blocks.sh"
# shellcheck source=tests/e2e/lib/assert.sh
. "$E2E_DIR/lib/assert.sh"

# The stdout of an apply run that exits 3: plan lines, then three blocks,
# one with %q-quoted paths (a home with a space) in its mv and stow lines.
cat >"$UNIT/apply.out" <<'OUT'
P0-preflight done host lab-ubuntu, profile debian, Linux x86_64
H1-apt-core human missing apt packages: zsh stow
S5-claude human blocked by H1-apt-core: Claude Code is not installed
H7-stow human blocked by S3-clones: /home/u/My Files/.zshrc is not a stow link yet
HUMAN-BEGIN H1-apt-core sudo
# docs/bootstrap.md H1-apt-core
sudo apt-get update
sudo apt-get install -y --no-install-recommends zsh stow
HUMAN-END
HUMAN-BEGIN H7-auth auth
# docs/bootstrap.md H7-auth
ssh-keygen -t ed25519
gh auth login --git-protocol ssh
HUMAN-END
HUMAN-BEGIN H7-stow judgment
# docs/bootstrap.md H7-stow
# Stow never replaces these files and stow --adopt would overwrite the tracked copies, so move each aside;
mv -n /home/u/My\ Files/.bashrc /home/u/My\ Files/.bashrc.pre-dotfiles
mv -n /home/u/My\ Files/.profile /home/u/My\ Files/.profile.pre-dotfiles
# writes ~/.claude, ~/.codex and ~/.ssh; an agent runs it only as one visible top-level command
PATH="/home/linuxbrew/.linuxbrew/bin:$PATH" /home/u/My\ Files/dotfiles/stow-all.sh lab-ubuntu
HUMAN-END
OUT
cat >"$UNIT/apply.err" <<'ERR'
[dotfiles] [warn] uncommitted changes in /home/u/dotfiles: none
[dotfiles] [warn] HUMAN steps pending: H1-apt-core S5-claude H7-stow; run the HUMAN blocks above, then rerun ./setup-host.sh --host lab-ubuntu
ERR

e2e_blocks_parse "$UNIT/apply.out" "$UNIT/blocks"
expect_eq 'block count' "$(e2e_blocks_count "$UNIT/blocks")" 3
expect_eq 'block index' "$(cat "$UNIT/blocks/index")" "1${TAB}H1-apt-core${TAB}sudo
2${TAB}H7-auth${TAB}auth
3${TAB}H7-stow${TAB}judgment"
expect_eq 'block row' "$(e2e_block_row "$UNIT/blocks" 3)" 'H7-stow judgment'
expect_eq 'block summary' "$(e2e_blocks_summary "$UNIT/blocks")" 'H1-apt-core(sudo) H7-auth(auth) H7-stow(judgment)'
expect_eq 'block 1 lines' "$(grep -c . "$UNIT/blocks/1.block")" 3
grep -Fx -- 'mv -n /home/u/My\ Files/.bashrc /home/u/My\ Files/.bashrc.pre-dotfiles' "$UNIT/blocks/3.block" >/dev/null ||
    fail 'the %q-quoted mv line did not reach the block file byte for byte'
expect_no_text 'plan lines outside blocks' "$UNIT/blocks/1.block" 'P0-preflight'
expect_eq 'pending ids' "$(e2e_pending_ids "$UNIT/apply.err")" 'H1-apt-core S5-claude H7-stow'
: >"$UNIT/empty"
expect_eq 'pending ids without the line' "$(e2e_pending_ids "$UNIT/empty")" ''

# The policy table, every row, and fail for anything else.
while read -r id kind want; do
    expect_eq "policy $id $kind" "$(e2e_block_policy "$id" "$kind")" "$want"
done <<'ROWS'
H1-apt-core sudo run-all
H1-locale sudo run-all
H1-linuxbrew sudo run-all
H1-homebrew sudo run-all
S5-claude inspect run-gate
H7-stow judgment run-stow
H2-alloc alloc alloc
S2-modules judgment skip
H7-sync-skills judgment skip
H7-doctor judgment skip
H7-auth auth skip
H1-fcitx5 gui skip
H7-chsh chsh skip
H1-xcode-clt gui fail
S2-brew-bundle sudo fail
S2-brew-bundle judgment fail
S4-nvm judgment fail
X-recovery judgment fail
H1-apt-core judgment fail
H7-stow sudo fail
S5-claude sudo fail
H9-unknown sudo fail
ROWS

# run-all takes every command line and no note.
expect_eq 'run-all lines' "$(e2e_block_lines run-all lab-ubuntu "$UNIT/blocks/1.block")" 'sudo apt-get update
sudo apt-get install -y --no-install-recommends zsh stow'
# run-stow takes the mv lines and the one stow line for the host, as printed.
expect_eq 'run-stow lines' "$(e2e_block_lines run-stow lab-ubuntu "$UNIT/blocks/3.block")" 'mv -n /home/u/My\ Files/.bashrc /home/u/My\ Files/.bashrc.pre-dotfiles
mv -n /home/u/My\ Files/.profile /home/u/My\ Files/.profile.pre-dotfiles
PATH="/home/linuxbrew/.linuxbrew/bin:$PATH" /home/u/My\ Files/dotfiles/stow-all.sh lab-ubuntu'
if e2e_block_lines run-stow wsl-ubuntu "$UNIT/blocks/3.block" >/dev/null; then
    fail 'run-stow accepted a stow line for another host'
fi
expect_eq 'run-stow other host error' "$E2E_BLOCK_ERROR" 'an H7-stow line the harness may not run: PATH="/home/linuxbrew/.linuxbrew/bin:$PATH" /home/u/My\ Files/dotfiles/stow-all.sh lab-ubuntu'
{
    cat "$UNIT/blocks/3.block"
    printf '%s\n' 'rm -rf ~/.oh-my-zsh'
} >"$UNIT/stow-planted.block"
if e2e_block_lines run-stow lab-ubuntu "$UNIT/stow-planted.block" >/dev/null; then
    fail 'run-stow accepted a planted extra line'
fi
expect_eq 'run-stow planted error' "$E2E_BLOCK_ERROR" 'an H7-stow line the harness may not run: rm -rf ~/.oh-my-zsh'
{
    cat "$UNIT/blocks/3.block"
    sed -n '/stow-all/p' "$UNIT/blocks/3.block"
} >"$UNIT/stow-twice.block"
if e2e_block_lines run-stow lab-ubuntu "$UNIT/stow-twice.block" >/dev/null; then
    fail 'run-stow accepted two stow lines'
fi
expect_eq 'run-stow twice error' "$E2E_BLOCK_ERROR" 'the H7-stow block has 2 stow-all.sh lab-ubuntu lines, not 1'
grep -v stow-all "$UNIT/blocks/3.block" >"$UNIT/stow-none.block"
if e2e_block_lines run-stow lab-ubuntu "$UNIT/stow-none.block" >/dev/null; then
    fail 'run-stow accepted a block without the stow line'
fi
if e2e_block_lines skip lab-ubuntu "$UNIT/blocks/2.block" >/dev/null; then
    fail 'e2e_block_lines ran lines for a skip action'
fi

# The digest gate: exactly one line of the printed shape, both verifiers;
# a gate without --status, the Homebrew form (/bin/bash) or a bare run
# line never counts.
SHA=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
GATE="printf '%s  %s\\n' $SHA /home/u/.cache/dotfiles-bootstrap/claude/install.sh | sha256sum -c --status - && bash /home/u/.cache/dotfiles-bootstrap/claude/install.sh"
cat >"$UNIT/inspect.block" <<BLOCK
# docs/bootstrap.md S5-claude
# downloaded https://claude.ai/install.sh (unpinned vendor script) to /home/u/.cache/dotfiles-bootstrap/claude/install.sh
# sha256 $SHA, 1234 bytes; delete the file for a fresh copy
# read it first; the line below runs it only while its sha256 is still the one above
$GATE
# ./doctor.sh then checks the installed claude against tools.tsv
BLOCK
expect_eq 'run-gate line' "$(e2e_block_lines run-gate lab-ubuntu "$UNIT/inspect.block")" "$GATE"
sed 's/sha256sum -c --status -/shasum -a 256 -c --status -/' "$UNIT/inspect.block" >"$UNIT/inspect-mac.block"
expect_eq 'run-gate shasum' "$(e2e_block_lines run-gate mac "$UNIT/inspect-mac.block" | grep -c 'shasum -a 256 -c --status -')" 1
for variant in 's/ --status//' 's/&& bash /\&\& NONINTERACTIVE=1 \/bin\/bash /' '/^printf/d'; do
    sed "$variant" "$UNIT/inspect.block" >"$UNIT/inspect-bad.block"
    if e2e_block_lines run-gate lab-ubuntu "$UNIT/inspect-bad.block" >/dev/null; then
        fail "run-gate accepted an inspect block after sed [$variant]"
    fi
    expect_eq "run-gate error after [$variant]" "$E2E_BLOCK_ERROR" 'the inspect block has 0 digest-gated run lines, not 1'
done
{
    cat "$UNIT/inspect.block"
    printf '%s\n' "$GATE"
} >"$UNIT/inspect-twice.block"
if e2e_block_lines run-gate lab-ubuntu "$UNIT/inspect-twice.block" >/dev/null; then
    fail 'run-gate accepted two gated lines'
fi
printf '%s\n' '# docs/bootstrap.md S5-claude' 'bash /home/u/.cache/dotfiles-bootstrap/claude/install.sh' >"$UNIT/inspect-bare.block"
if e2e_block_lines run-gate lab-ubuntu "$UNIT/inspect-bare.block" >/dev/null; then
    fail 'run-gate accepted a bare run line'
fi

# E2E_ALLOC_ENV: expanded with SCRATCH and the running user, refused while
# a name is unexpanded or a word is not KEY=value.
unset SCRATCH
expect_eq 'alloc exports' "$(SCRATCH=/scratch/users/tester e2e_alloc_exports 'SLURM_JOB_ID=424242 CONDA_PKGS_DIRS=$SCRATCH/.cache/conda/pkgs/$USER')" \
    'SLURM_JOB_ID=424242 CONDA_PKGS_DIRS=/scratch/users/tester/.cache/conda/pkgs/tester'
if e2e_alloc_exports 'SLURM_JOB_ID=424242 CONDA_PKGS_DIRS=$SCRATCH/.cache/conda/pkgs' >/dev/null; then
    fail 'alloc exports accepted an unset SCRATCH'
fi
expect_eq 'alloc unset error' "${E2E_BLOCK_ERROR%%:*}" 'E2E_ALLOC_ENV still holds an unexpanded name (is SCRATCH set?)'
if e2e_alloc_exports 'SLURM_JOB_ID=1 bogus' >/dev/null; then
    fail 'alloc exports accepted a word without ='
fi
if e2e_alloc_exports '' >/dev/null; then
    fail 'alloc exports accepted an empty E2E_ALLOC_ENV'
fi

# What a failed run said.
printf '%s\n' 'P0-preflight done ok' 'S3-clones failed git exited 128' >"$UNIT/failed.out"
printf '%s\n' '[dotfiles] [error] S3-clones failed: git exited 128' '[dotfiles] [error] failed steps: S3-clones' >"$UNIT/failed.err"
expect_eq 'failure detail' "$(e2e_failure_detail "$UNIT/failed.out" "$UNIT/failed.err")" 'S3-clones failed git exited 128
[dotfiles] [error] failed steps: S3-clones'
printf '%s\n' '[dotfiles] [error] unknown host: nope' >"$UNIT/usage.err"
expect_eq 'failure detail fallback' "$(e2e_failure_detail "$UNIT/empty" "$UNIT/usage.err")" '[dotfiles] [error] unknown host: nope'

# The wrappers.log audit: human and negative phases pass, as does the
# doctor's bare `stow --version` probe in a check phase; any other check
# phase or no phase fails; on a host without sudo any sudo line fails.
printf '%s\t%s\t%s\t%s\t%s\t%s\n' 1700000000 human:H1-apt-core sudo 42 'bash -c sudo apt-get update' 'apt-get update' \
    1700000010 negative:root-refused sudo 43 'bash' '-n ./setup-host.sh --host lab-ubuntu --check' \
    1700000015 check:doctor-initial stow 47 'doctor.sh' '--version' \
    1700000020 human:H7-stow stow 44 'stow-all.sh' '-n --restow -d common zsh' >"$UNIT/wrappers.log"
bad=$(e2e_audit_wrappers "$UNIT/wrappers.log") || fail "wrappers audit failed a clean log: $bad"
if bad=$(e2e_audit_no_sudo "$UNIT/wrappers.log"); then
    fail 'no-sudo audit passed a log with sudo lines'
fi
expect_eq 'no-sudo audit lines' "$(printf '%s\n' "$bad" | grep -c .)" 2
cp "$UNIT/wrappers.log" "$UNIT/wrappers-bad.log"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' 1700000030 check:doctor-initial sudo 45 'doctor.sh' '-n true' \
    1700000040 - chsh 46 'installer' '-s /usr/bin/zsh' >>"$UNIT/wrappers-bad.log"
if bad=$(e2e_audit_wrappers "$UNIT/wrappers-bad.log"); then
    fail 'wrappers audit passed a sudo outside the human phases'
fi
expect_eq 'wrappers audit violations' "$(printf '%s\n' "$bad" | grep -c .)" 2
case $bad in
    *check:doctor-initial*"$E2E_NL"*"${TAB}-${TAB}chsh"*) ;;
    *) fail "wrappers audit named the wrong lines: $bad" ;;
esac

# The sudo.log audit needs GNU date -d (Linux); the timestamps are sudo's
# with Defaults log_year, and only the entry outside a window is reported.
if date -d @0 +%s >/dev/null 2>&1; then
    printf '%s\t%s\t%s\n' 1700000000 begin setup:clone 1700000005 end setup:clone \
        1700000010 begin human:H1-apt-core 1700000100 end human:H1-apt-core \
        1700000200 begin negative:root-refused 1700000210 end negative:root-refused >"$UNIT/timeline"
    {
        printf '%s : tester : TTY=unknown ; PWD=/home/tester ; USER=root ; COMMAND=/usr/bin/apt-get update\n' \
            "$(date -d @1700000010 '+%b %e %T %Y')"
        printf '%s : tester : TTY=unknown ; PWD=/home/tester ; USER=root ; COMMAND=/usr/bin/apt-get install -y\n' \
            "$(date -d @1700000100 '+%b %e %T %Y')"
        printf '    zsh stow\n'
        printf '%s : tester : TTY=unknown ; PWD=/home/tester/dotfiles ; USER=root ; COMMAND=./setup-host.sh\n' \
            "$(date -d @1700000205 '+%b %e %T %Y')"
    } >"$UNIT/sudo.log"
    bad=$(e2e_audit_sudo_log "$UNIT/timeline" "$UNIT/sudo.log") || fail "sudo.log audit failed entries inside the windows: $bad"
    printf '%s : tester : TTY=unknown ; PWD=/home/tester ; USER=root ; COMMAND=/usr/bin/true\n' \
        "$(date -d @1700000150 '+%b %e %T %Y')" >>"$UNIT/sudo.log"
    if bad=$(e2e_audit_sudo_log "$UNIT/timeline" "$UNIT/sudo.log"); then
        fail 'sudo.log audit passed an entry between the windows'
    fi
    expect_eq 'sudo.log audit violations' "$(printf '%s\n' "$bad" | grep -c .)" 1
    case $bad in
        'outside every human/negative window: '*'COMMAND=/usr/bin/true') ;;
        *) fail "sudo.log audit named the wrong entry: $bad" ;;
    esac
else
    printf 'SKIP: sudo.log timestamp audit (no GNU date -d; the audit itself skips here too).\n'
    rc=0
    e2e_audit_sudo_log /dev/null /dev/null >/dev/null || rc=$?
    expect_eq 'sudo.log audit without date -d' "$rc" 2
fi
printf 'ok: block parser, policy, gate, alloc and audit parsers\n'

# --- part two: the sandboxed dry run -------------------------------------

# The fixture source checkout: stubs for the three entry points inside.sh
# drives, and the tracked ~/.zshrc the stow stub links. Two commits: the
# second plants a sudo in doctor.sh outside any human phase.
SRC="$TEST_TMP/src"
TEST_BIN="$TEST_TMP/bin"
mkdir -p "$SRC/common/zsh" "$TEST_BIN"
cat >"$TEST_TMP/gitconfig" <<EOF
[user]
	name = Fixture
	email = fixture@example.invalid
[init]
	defaultBranch = main
[advice]
	detachedHead = false
EOF
export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
printf '# tracked zshrc\n' >"$SRC/common/zsh/.zshrc"

# The setup-host.sh stub keeps the real one's shape: the root and WSL
# refusals (exit 2), plan lines, the HUMAN blocks of docs/bootstrap.md with
# the real frames, the pending line on stderr and exit 3 while a blocking
# step is pending. Its state is what the blocks leave behind: the apt
# marker the apt-get stub writes, ~/.local/bin/claude from the gated
# installer, the ~/.zshrc link from stow-all.sh. --check writes nothing.
cat >"$SRC/setup-host.sh" <<'SH'
#!/bin/bash
# e2e-harness fixture: a setup-host.sh stand-in (see tests/e2e-harness.sh).
set -u
host='' mode=check
while [ $# -gt 0 ]; do
    case $1 in
        --host) host=$2; shift ;;
        --check) mode=check ;;
        --yes) mode=apply ;;
        *) printf '[dotfiles] [error] unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done
if [ "$(id -u)" = 0 ] || [ "${E2E_STUB_ROOT:-}" = 1 ]; then
    printf '%s\n' '[dotfiles] [error] run ./setup-host.sh as your user, not root (no sudo); the sudo steps are printed as HUMAN blocks' >&2
    exit 2
fi
if [ -z "$host" ]; then
    printf '%s\n' '[dotfiles] [error] ./stow-all.sh recorded a common-only install for this home (no host overlay); setup-host needs one: pass --host HOST' >&2
    exit 2
fi
case $host in
    lab-ubuntu) ;;
    wsl-ubuntu)
        printf '%s\n' '[dotfiles] [error] host wsl-ubuntu runs under WSL, but this is not WSL (no WSL_DISTRO_NAME, no Microsoft kernel); a native Ubuntu workstation is --host lab-ubuntu' >&2
        exit 2
        ;;
    *) printf '[dotfiles] [error] unknown host: %s\n' "$host" >&2; exit 2 ;;
esac
root=$(cd "$(dirname "$0")" && pwd -P)
scratch=$HOME/.cache/dotfiles-bootstrap
installer=$scratch/claude/install.sh
if command -v sha256sum >/dev/null 2>&1; then
    verify='sha256sum -c --status -'
    digest() { sha256sum <"$1" | cut -d ' ' -f 1; }
else
    verify='shasum -a 256 -c --status -'
    digest() { shasum -a 256 <"$1" | cut -d ' ' -f 1; }
fi
apt_done=0 claude_done=0 stowed=0 omz=0
[ ! -f "$scratch/apt-core.done" ] || apt_done=1
[ ! -x "$HOME/.local/bin/claude" ] || claude_done=1
[ ! -L "$HOME/.zshrc" ] || stowed=1
[ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ] || omz=1
held=''
printf 'P0-preflight done host %s, profile debian, checkout %s\n' "$host" "$root"
if [ "$apt_done" = 1 ]; then
    printf '%s\n' 'H1-apt-core done 2 apt packages installed'
else
    printf '%s\n' 'H1-apt-core human missing apt packages: zsh stow'
    held=H1-apt-core
fi
if [ "$apt_done" = 0 ]; then
    printf '%s\n' 'S3-clones todo blocked by H1-apt-core: oh-my-zsh is not cloned'
elif [ "$omz" = 1 ]; then
    printf 'S3-clones done oh-my-zsh at %s/.oh-my-zsh\n' "$HOME"
elif [ "$mode" = apply ]; then
    mkdir -p "$HOME/.oh-my-zsh" && : >"$HOME/.oh-my-zsh/oh-my-zsh.sh"
    printf '%s\n' 'S3-clones done applied: clone oh-my-zsh'
    omz=1
else
    printf '%s\n' 'S3-clones todo clone oh-my-zsh'
fi
if [ "$claude_done" = 1 ]; then
    printf 'S5-claude done claude at %s/.local/bin/claude\n' "$HOME"
elif [ "$apt_done" = 0 ]; then
    printf '%s\n' 'S5-claude human blocked by H1-apt-core: Claude Code is not installed'
    held="$held${held:+ }S5-claude"
else
    if [ "$mode" = apply ] && [ ! -f "$installer" ]; then
        mkdir -p "$scratch/claude"
        printf '%s\n' '#!/bin/sh' 'mkdir -p "$HOME/.local/bin" || exit 1' \
            'printf "#!/bin/sh\nexit 0\n" >"$HOME/.local/bin/claude" && chmod 755 "$HOME/.local/bin/claude"' >"$installer"
    fi
    printf '%s\n' 'S5-claude human Claude Code is not installed; its vendor installer is read by a person first'
    held="$held${held:+ }S5-claude"
fi
if [ "$stowed" = 1 ]; then
    printf 'H7-stow done %s/.zshrc links into %s/common\n' "$HOME" "$root"
elif [ "$omz" = 0 ] || [ "$claude_done" = 0 ]; then
    printf '%s\n' 'H7-stow human blocked by S5-claude: not a stow link yet'
    held="$held${held:+ }H7-stow"
else
    printf 'H7-stow human %s/.zshrc is not a stow link yet; 2 home file(s) to move aside first: .bashrc .profile\n' "$HOME"
    held="$held${held:+ }H7-stow"
fi
printf '%s\n' 'H7-auth human sign in to GitHub, Claude Code and Codex (not checked offline)' \
    'H7-doctor human the completion gate is ./doctor.sh --host lab-ubuntu'
if [ "$apt_done" = 0 ]; then
    printf '%s\n' 'HUMAN-BEGIN H1-apt-core sudo' '# docs/bootstrap.md H1-apt-core' 'sudo apt-get update' \
        'sudo apt-get install -y --no-install-recommends zsh stow' 'HUMAN-END'
elif [ "$claude_done" = 0 ]; then
    printf '%s\n' 'HUMAN-BEGIN S5-claude inspect' '# docs/bootstrap.md S5-claude'
    if [ -f "$installer" ]; then
        printf '# downloaded https://claude.ai/install.sh (unpinned vendor script) to %q\n' "$installer"
        printf '# sha256 %s, %s bytes; delete the file for a fresh copy\n' "$(digest "$installer")" "$(wc -c <"$installer" | tr -d ' ')"
        printf '%s\n' '# read it first; the line below runs it only while its sha256 is still the one above'
        printf "printf '%%s  %%s\\\\n' %s %q | %s && bash %q\\n" "$(digest "$installer")" "$installer" "$verify" "$installer"
    else
        printf '# ./setup-host.sh --host %s (without --check) downloads https://claude.ai/install.sh (unpinned)\n' "$host"
    fi
    printf '%s\n' '# ./doctor.sh then checks the installed claude against tools.tsv' 'HUMAN-END'
elif [ "$stowed" = 0 ]; then
    printf '%s\n' 'HUMAN-BEGIN H7-stow judgment' '# docs/bootstrap.md H7-stow' \
        '# Stow never replaces these files and stow --adopt would overwrite the tracked copies, so move each aside;'
    for rel in .bashrc .profile; do
        [ -f "$HOME/$rel" ] && [ ! -L "$HOME/$rel" ] || continue
        printf 'mv -n %q %q\n' "$HOME/$rel" "$HOME/$rel.pre-dotfiles"
    done
    printf '%s\n' '# writes ~/.claude, ~/.codex and ~/.ssh; an agent runs it only as one visible top-level command'
    # The real block names the Homebrew prefix; a machine running this test
    # may have a real stow there, which the prefix would find before the
    # stub, so the fixture names a prefix that exists nowhere.
    printf 'PATH="$HOME/.e2e-stub-prefix/bin:$PATH" %q %s\n' "$root/stow-all.sh" "$host"
    printf '%s\n' 'HUMAN-END'
fi
printf '%s\n' 'HUMAN-BEGIN H7-auth auth' '# docs/bootstrap.md H7-auth' 'ssh-keygen -t ed25519' \
    'gh auth login --git-protocol ssh' 'HUMAN-END' 'HUMAN-BEGIN H7-doctor judgment' '# docs/bootstrap.md H7-doctor'
printf '%q --host %s\n' "$root/doctor.sh" "$host"
printf '%s\n' 'HUMAN-END'
if [ -n "$held" ]; then
    printf '[dotfiles] [warn] HUMAN steps pending: %s; run the HUMAN blocks above, then rerun ./setup-host.sh --host %s\n' "$held" "$host" >&2
    exit 3
fi
printf '[dotfiles] [ok] setup-host: nothing blocking remains for %s\n' "$host" >&2
exit 0
SH

# doctor.sh: exit 1 until the stow and the gated installer happened, 0
# after; --tsv prints the five-column report; --smoke exits like a run.
cat >"$SRC/doctor.sh" <<'SH'
#!/bin/bash
# e2e-harness fixture: a doctor.sh stand-in (see tests/e2e-harness.sh).
set -u
tsv=0
for argument in "$@"; do
    case $argument in
        --tsv) tsv=1 ;;
        --host | --platform | --smoke | lab-ubuntu | other) ;;
        *) printf '[dotfiles] [error] unknown argument: %s\n' "$argument" >&2; exit 2 ;;
    esac
done
# PLANT
claude=missing stow=missing rc=1
[ ! -x "$HOME/.local/bin/claude" ] || claude=ok
[ ! -L "$HOME/.zshrc" ] || stow=ok
[ "$claude" != ok ] || [ "$stow" != ok ] || rc=0
if [ "$tsv" = 1 ]; then
    printf 'status\tid\ttier\tdetail\tfix\n'
    printf 'ok\tgit\tcore\t2.43.0\t-\n'
    printf '%s\tclaude\tai\t%s\tdocs/bootstrap.md S5-claude\n' "$claude" "$HOME/.local/bin/claude"
    printf '%s\tstow-links\tcore\t%s/.zshrc\tdocs/bootstrap.md H7-stow\n' "$stow" "$HOME"
else
    printf '[dotfiles] [ok] core git: 2.43.0\n'
    [ "$claude" = ok ] || printf '[dotfiles] [error] ai claude: missing (docs/bootstrap.md S5-claude)\n'
    [ "$stow" = ok ] || printf '[dotfiles] [error] core stow-links: %s/.zshrc is not a stow link (docs/bootstrap.md H7-stow)\n' "$HOME"
    printf '[dotfiles] [info] summary: ok=1 missing=%s\n' "$((2 - (claude = ok) - (stow = ok)))" 2>/dev/null || true
fi
exit "$rc"
SH
sed -i.bak '/summary/d' "$SRC/doctor.sh" && rm -f "$SRC/doctor.sh.bak"

# stow-all.sh: refuses a regular ~/.bashrc or ~/.profile like Stow would,
# calls stow (the wrapper logs it), links ~/.zshrc into the clone and
# records the host in the state file the harness watches.
cat >"$SRC/stow-all.sh" <<'SH'
#!/bin/bash
# e2e-harness fixture: a stow-all.sh stand-in (see tests/e2e-harness.sh).
set -u
root=$(cd "$(dirname "$0")" && pwd -P)
host=${1:-}
for rel in .bashrc .profile; do
    if [ -f "$HOME/$rel" ] && [ ! -L "$HOME/$rel" ]; then
        printf '[dotfiles] [error] Stow would conflict with %s; move it aside first\n' "$HOME/$rel" >&2
        exit 1
    fi
done
command -v stow >/dev/null 2>&1 || { printf '[dotfiles] [error] required GNU Stow is missing\n' >&2; exit 1; }
stow -n --restow --no-folding -d "$root/common" zsh || exit 1
ln -sfn "$root/common/zsh/.zshrc" "$HOME/.zshrc" || exit 1
state=$(cd "$root" && git rev-parse --git-path dotfiles-sync-unix) || exit 1
case $state in
    /*) ;;
    *) state=$root/$state ;;
esac
printf 'HOST=%s\n' "$host" >"$state" || exit 1
printf '[dotfiles] [ok] stowed common%s\n' "${host:+ and $host}"
exit 0
SH
chmod +x "$SRC/setup-host.sh" "$SRC/doctor.sh" "$SRC/stow-all.sh"
git -C "$SRC" init -q
git -C "$SRC" add -A
git -C "$SRC" commit -q -m 'stubs'
REV_CLEAN=$(git -C "$SRC" rev-parse HEAD)
# The planted commit: doctor.sh runs sudo on its own, in whatever phase it
# is called, but only through this test's stub (never a real sudo).
sed "s|^# PLANT\$|[ \"\$(command -v sudo)\" != '$TEST_BIN/sudo' ] \|\| sudo -n true|" "$SRC/doctor.sh" >"$SRC/doctor.sh.new"
mv "$SRC/doctor.sh.new" "$SRC/doctor.sh"
chmod +x "$SRC/doctor.sh"
grep -F 'sudo -n true' "$SRC/doctor.sh" >/dev/null || fail 'the planted sudo did not land in doctor.sh'
git -C "$SRC" commit -q -a -m 'plant a sudo in doctor.sh'
REV_PLANTED=$(git -C "$SRC" rev-parse HEAD)

# The stub wrappers, in B's wrappers.log format: sudo logs and then runs
# the command itself (there is no root here), marking it for the
# setup-host stub's root refusal; chsh and stow log and succeed; apt-get
# leaves the marker H1-apt-core waits for; zsh stands in for the login
# shell and runs -c commands through bash.
write_stub() {
    cat >"$TEST_BIN/$1"
    chmod +x "$TEST_BIN/$1"
}
for tool in sudo chsh stow; do
    write_stub "$tool" <<SH
#!/bin/bash
# e2e-harness stub wrapper for $tool (see tests/e2e-harness.sh).
tool=$tool
dir=\${E2E_OUT:-/e2e/out}/log
{ mkdir -p "\$dir" && printf '%s\t%s\t%s\t%s\t%s\t%s\n' "\$(date +%s)" "\${E2E_PHASE:--}" "\$tool" "\$PPID" "stub parent" "\$*" >>"\$dir/wrappers.log"; } 2>/dev/null || true
[ "\$tool" = sudo ] || exit 0
while [ \$# -gt 0 ]; do
    case \$1 in
        -n | -v | -k | -E | -H) shift ;;
        -u) shift 2 ;;
        *) break ;;
    esac
done
[ \$# -gt 0 ] || exit 0
E2E_STUB_ROOT=1 exec "\$@"
SH
done
write_stub apt-get <<'SH'
#!/bin/bash
# e2e-harness stub apt-get: install leaves the marker the setup-host stub checks.
[ "${1:-}" != install ] || { mkdir -p "$HOME/.cache/dotfiles-bootstrap" && : >"$HOME/.cache/dotfiles-bootstrap/apt-core.done"; }
exit 0
SH
write_stub zsh <<'SH'
#!/bin/bash
# e2e-harness stub zsh: -il -c COMMAND runs COMMAND through bash, silently.
cmd=''
while [ $# -gt 0 ]; do
    case $1 in
        -c) cmd=${2-}; shift ;;
        --version) printf 'zsh 5.9 (stub)\n'; exit 0 ;;
    esac
    shift
done
[ -n "$cmd" ] || exit 0
exec bash -c "$cmd"
SH

# run_inside NAME REV HOME ENV...: inside.sh against the fixture at REV in
# the sandbox HOME (a path with a space), with the stub bin first on PATH
# and the login zsh pointed at the stub. Sets RUN_RC.
run_inside() {
    local name=$1 rev=$2 home=$3
    shift 3
    mkdir -p "$home"
    printf '# /etc/skel\n' >"$home/.bashrc"
    printf '# /etc/skel\n' >"$home/.profile"
    RUN_RC=0
    env "$@" E2E_SANDBOX_HOME="$home" E2E_HOST=lab-ubuntu E2E_REV="$rev" E2E_SRC="$SRC" E2E_OUT="$TEST_TMP/out-$name" \
        E2E_LOGIN_ZSH="$TEST_BIN/zsh" PATH="$TEST_BIN:$PATH" \
        "$E2E_DIR/inside.sh" >"$TEST_TMP/$name.out" 2>"$TEST_TMP/$name.err" || RUN_RC=$?
}

# summary_rows NAME STEP: the summary.tsv rows of STEP as "status<TAB>detail".
summary_rows() {
    awk -F '\t' -v step="$2" '$2 == step { print $3 "\t" $5 }' "$TEST_TMP/out-$1/summary.tsv"
}

# expect_step NAME STEP STATUS [TEXT]: exactly one row of STEP, with STATUS
# and TEXT in its detail.
expect_step() {
    local rows
    rows=$(summary_rows "$1" "$2")
    [ "$(printf '%s\n' "$rows" | grep -c .)" = 1 ] || {
        cat "$TEST_TMP/out-$1/summary.tsv" >&2
        fail "$1: $2 has rows [$rows], expected exactly one"
    }
    case $rows in
        "$3${TAB}"*"${4:-}"*) ;;
        *)
            cat "$TEST_TMP/out-$1/summary.tsv" "$TEST_TMP/$1.err" >&2
            fail "$1: $2 row is [$rows], expected status $3 with [${4:-}]"
            ;;
    esac
}

# The clean run: every step passes, the reminders are skipped once, the
# apply loop converges in four runs and the audits see only human and
# negative phases.
CLEAN_HOME="$TEST_TMP/home dir"
run_inside clean "$REV_CLEAN" "$CLEAN_HOME"
if [ "$RUN_RC" != 0 ]; then
    cat "$TEST_TMP/clean.err" "$TEST_TMP/out-clean/summary.tsv" >&2 || true
    fail "clean: inside.sh exited $RUN_RC, expected 0"
fi
CLEAN_OUT="$TEST_TMP/out-clean"
if grep -E "^[0-9]+${TAB}[^${TAB}]+${TAB}fail${TAB}" "$CLEAN_OUT/summary.tsv" >/dev/null; then
    cat "$CLEAN_OUT/summary.tsv" >&2
    fail 'clean: summary.tsv has a fail row'
fi
expect_step clean clone pass "at $CLEAN_HOME/dotfiles"
expect_step clean doctor-initial pass 'exit 1; '
expect_step clean doctor-initial pass 'no writes'
expect_step clean check-nowrite pass 'exit 3; '
expect_step clean check-nowrite pass '1 todo, 5 human; no writes'
expect_step clean apply-1 pass 'blocks: H1-apt-core(sudo) H7-auth(auth) H7-doctor(judgment); pending: H1-apt-core S5-claude H7-stow'
expect_step clean H1-apt-core pass '2 line(s) run as printed (run-all)'
expect_step clean H7-auth skip 'auth block left to the person'
expect_step clean H7-doctor skip 'judgment block left to the person'
expect_step clean apply-2 pass 'blocks: S5-claude(inspect) H7-auth(auth) H7-doctor(judgment); pending: S5-claude H7-stow'
expect_step clean S5-claude pass '1 line(s) run as printed (run-gate)'
expect_step clean apply-3 pass 'blocks: H7-stow(judgment) H7-auth(auth) H7-doctor(judgment); pending: H7-stow'
expect_step clean H7-stow pass '3 line(s) run as printed (run-stow)'
expect_step clean apply-4 pass 'exit 0 after 4 run(s)'
expect_step clean second-apply pass 'exit 0, nothing applied, HOME untouched'
expect_step clean login-shell pass 'exit 0; silent'
expect_step clean doctor-final pass 'exit 0 from the login shell'
expect_step clean doctor-smoke pass 'exit 0 from the login shell'
expect_step clean negative-wsl-refused pass 'exit 2: '
expect_step clean negative-root-refused pass 'not root'
expect_step clean audit-wrappers pass '4 wrapper call(s), all in human or negative phases'
expect_step clean audit-sudo-log skip 'no log/sudo.log'
expect_step clean audit-stow-state pass 'during human:H7-stow only'
expect_step clean audit-login-shell pass 'login shell still '
expect_step clean audit-rc-files pass 'human phases only'
expect_step clean rc-files note 'changed during human:H7-stow: .bashrc .profile .zshrc'
[ "$(summary_rows clean apply-5)" = '' ] || fail 'clean: a fifth apply run happened'
# The wrappers.log holds the two apt sudos, the stow and the root-refused
# sudo, nothing else; the timeline frames each phase.
expect_eq 'clean wrappers.log' "$(cut -f 2,3 "$CLEAN_OUT/log/wrappers.log" | tr '\t' ' ')" 'human:H1-apt-core sudo
human:H1-apt-core sudo
human:H7-stow stow
negative:root-refused sudo'
expect_text 'clean wrappers.log argv' "$CLEAN_OUT/log/wrappers.log" "${TAB}-n ./setup-host.sh --host lab-ubuntu --check"
for phase in human:H1-apt-core human:S5-claude human:H7-stow negative:wsl-refused negative:root-refused check:doctor-initial setup:apply-1; do
    expect_eq "clean timeline $phase" "$(awk -F '\t' -v p="$phase" '$3 == p { print $2 }' "$CLEAN_OUT/log/timeline" | tr '\n' ' ')" 'begin end '
done
awk -F '\t' '$3 ~ /^(human|negative):/ { if ($2 == "begin") b = $1; else if ($1 - b < 0) exit 1 }' "$CLEAN_OUT/log/timeline" ||
    fail 'clean: a timeline window ends before it begins'
# The outputs the contract names, and what the run left in the home.
expect_text 'clean env.txt' "$CLEAN_OUT/env.txt" 'host=lab-ubuntu flow=unix profile=debian mode=sandbox'
[ -f "$CLEAN_OUT/steps/01-clone.log" ] || fail 'clean: no steps/01-clone.log'
[ -f "$CLEAN_OUT/steps/04-apply-1.blocks/1.block" ] || fail 'clean: the apply-1 blocks were not kept'
[ -f "$CLEAN_OUT/snapshots/doctor-initial.newer" ] || fail 'clean: no doctor-initial snapshot'
[ ! -s "$CLEAN_OUT/snapshots/doctor-initial.newer" ] || fail "clean: doctor-initial wrote in HOME: $(cat "$CLEAN_OUT/snapshots/doctor-initial.newer")"
[ -f "$CLEAN_HOME/.bashrc.pre-dotfiles" ] && [ ! -e "$CLEAN_HOME/.bashrc" ] || fail 'clean: the mv -n lines did not move ~/.bashrc aside'
[ -L "$CLEAN_HOME/.zshrc" ] || fail 'clean: ~/.zshrc is not the stow link'
[ -x "$CLEAN_HOME/.local/bin/claude" ] || fail 'clean: the gated installer did not run'
[ -f "$CLEAN_HOME/.cache/dotfiles-bootstrap/apt-core.done" ] || fail 'clean: the apt block did not run through the sudo stub'
[ -z "$(git -C "$SRC" status --porcelain)" ] || fail 'clean: the source checkout changed'
[ -z "$(git -C "$CLEAN_HOME/dotfiles" status --porcelain --untracked-files=all)" ] || fail 'clean: the clone is not clean'
expect_eq 'clean clone rev' "$(git -C "$CLEAN_HOME/dotfiles" rev-parse HEAD)" "$REV_CLEAN"
expect_text 'clean log' "$TEST_TMP/clean.err" 'pass, 0 fail,'
printf 'ok: sandboxed dry run (clean fixture)\n'

# The planted run, without negatives: doctor-initial itself passes, but the
# sudo it made under check:doctor-initial fails the wrappers audit and the
# run exits 1.
run_inside planted "$REV_PLANTED" "$TEST_TMP/home planted" E2E_NEGATIVE=
expect_eq 'planted exit' "$RUN_RC" 1
expect_step planted doctor-initial pass 'exit 1; '
expect_step planted H7-stow pass '3 line(s) run as printed (run-stow)'
expect_step planted audit-wrappers fail 'wrapper calls outside human/negative phases: '
expect_step planted audit-wrappers fail ' check:doctor-initial sudo '
expect_step planted audit-stow-state pass 'during human:H7-stow only'
[ "$(summary_rows planted negative-wsl-refused)" = '' ] || fail 'planted: a negative ran although E2E_NEGATIVE was empty'
expect_eq 'planted fail count' "$(awk -F '\t' '$3 == "fail"' "$TEST_TMP/out-planted/summary.tsv" | grep -c .)" 1
expect_eq 'planted clone rev' "$(git -C "$TEST_TMP/home planted/dotfiles" rev-parse HEAD)" "$REV_PLANTED"
printf 'ok: sandboxed dry run (planted sudo fails the wrappers audit)\n'

# --- refusals (exit 2) -----------------------------------------------------

# refused NAME ENV...: inside.sh with ENV (which overrides the defaults
# before it) must exit 2 before any step; the stub bin stays first on PATH,
# so a misfire could still reach no real sudo.
refused() {
    local name=$1 rc=0
    shift
    env E2E_HOST=lab-ubuntu E2E_REV="$REV_CLEAN" E2E_SRC="$SRC" E2E_OUT="$TEST_TMP/out-$name" \
        E2E_LOGIN_ZSH="$TEST_BIN/zsh" PATH="$TEST_BIN:$PATH" "$@" \
        "$E2E_DIR/inside.sh" >"$TEST_TMP/$name.out" 2>"$TEST_TMP/$name.err" || rc=$?
    [ "$rc" = 2 ] || fail "$name: inside.sh exited $rc, expected 2: $(cat "$TEST_TMP/$name.err")"
    [ ! -f "$TEST_TMP/out-$name/summary.tsv" ] || [ ! -s "$TEST_TMP/out-$name/summary.tsv" ] ||
        fail "$name: inside.sh ran steps before refusing"
}
refused sandbox-is-home E2E_SANDBOX_HOME="$HOME"
expect_text 'sandbox-is-home' "$TEST_TMP/sandbox-is-home.err" 'must lie under the temp dir'
refused sandbox-relative E2E_SANDBOX_HOME=relative/home
expect_text 'sandbox-relative' "$TEST_TMP/sandbox-relative.err" 'must be absolute'
refused win-host E2E_SANDBOX_HOME="$TEST_TMP/home win" E2E_HOST=win
expect_text 'win-host' "$TEST_TMP/win-host.err" 'driven by tests/e2e/run.ps1'
refused bad-rev E2E_SANDBOX_HOME="$TEST_TMP/home rev" E2E_REV=abc123
expect_text 'bad-rev' "$TEST_TMP/bad-rev.err" 'not a 40-hex commit'
refused home-taken E2E_SANDBOX_HOME="$CLEAN_HOME"
expect_text 'home-taken' "$TEST_TMP/home-taken.err" 'exists already'
if [ ! -f /.dockerenv ] && [ "$(uname -s)" != Darwin ]; then
    # Without a seam, a workstation run is refused before it can touch HOME.
    refused no-seam E2E_NATIVE=1
    expect_text 'no-seam' "$TEST_TMP/no-seam.err" 'refusing to run outside a container'
fi
printf 'ok: refusals exit 2 before any step\n'

printf 'e2e-harness: %ss\n' "$(($(date +%s) - STARTED))"
echo "e2e-harness=PASS"
