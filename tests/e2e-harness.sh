#!/bin/bash

# Unit test of the opt-in end-to-end bootstrap harness, tests/e2e/inside.sh
# and tests/e2e/lib/*.sh, without Docker or network. Part one sources the
# libraries and checks the HUMAN block parser (notes against commands, %q
# paths with spaces), the "HUMAN steps pending:" reader, every row of the
# (step id, kind) policy including the H7-deploy block and the fail rows,
# the apply loop's verdict table, the exact shape of the digest gate
# (against what lib/bootstrap's own printer emits, and against chained or
# foreign lines), the E2E_ALLOC_ENV expansion, the audit parsers against
# fixture logs, the clone-link audit, and the functions extracted from
# docs/bootstrap.md: the by-hand helpers (and the installers.tsv row
# fetch_pinned picks for chezmoi) and the two "Fresh home by hand"
# functions, run under bash, sh and zsh against a stub chezmoi that accepts
# only the full explicit argument set. Part two runs inside.sh itself with
# E2E_SANDBOX_HOME against a fixture clone whose scripts/commands/setup.sh, scripts/commands/doctor.sh
# and chezmoi are stubs printing realistic plan lines, blocks and exit codes
# (an apt sudo block, then an inspect block, then a run that applies the
# chezmoi binary, then only H7-deploy left), with stub sudo, chsh and apt-get
# wrappers that write the wrappers.log format; the run deploys the home
# through the documented functions and must converge. Two more runs at
# planted fixture commits (a sudo in scripts/commands/doctor.sh, a link into the clone) must
# each fail exactly one audit. Every write lands under this test's temp dir;
# the sandbox home has a space in its name. Runs under the Bash that runs
# the test, so Bash 3.2 too.

set -euo pipefail

# Isolate inherited configuration while preserving explicit test inputs.
# shellcheck source=tests/lib/environment.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/environment.sh"

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
E2E_DIR="$REPO_ROOT/tests/e2e"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-e2e-harness.XXXXXX")"
TEST_TMP="$(cd -- "$TEST_TMP" && pwd -P)"
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM
STARTED=$(date +%s)
TAB=$(printf '\t')
# A commit hook in a linked worktree exports an absolute GIT_DIR and
# GIT_INDEX_FILE, which -C does not override: the fixture source's git init
# and commits would reinitialize and commit into the caller's repository.
dotfiles_test_clear_git_environment

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

# write_chezmoi_stub PATH: the chezmoi stand-in of both parts. It accepts
# only the full explicit argument set docs/bootstrap.md home_cz passes, in
# that order, against the clone at ~/dotfiles (exit 2 otherwise), logs the
# rest of each call to E2E_STUB_LOG when that is set, and plays a five-file
# source (plus the executable CLI when its source exists): an init that writes the top-level keys home/.chezmoi.toml.tmpl
# sets (destDir, mode, persistentState and sourceDir, sorted, before the seed
# config's own lines, as toToml writes them; E2E_STUB_INIT=foreign names
# another home), the two managed lists, a directory-only apply of one absent
# directory under the home, a file apply that writes each target (refused
# until the config names this home and the clone) and the state database,
# and a diff that names each target whose bytes differ (E2E_STUB_DIFF=1 adds
# one).
write_chezmoi_stub() {
    cat >"$1" <<'SH'
#!/bin/sh
# e2e-harness fixture: a chezmoi stand-in (see tests/e2e-harness.sh).
if [ "$*" = --version ]; then
    printf 'chezmoi version v2.74.0, commit fixture\n'
    exit 0
fi
src=$(cd "$HOME/dotfiles" 2>/dev/null && pwd -P) && home=$(cd "$HOME" && pwd -P) || {
    printf 'stub chezmoi: no clone at ~/dotfiles\n' >&2
    exit 2
}
[ "$1|$2|$3|$4|$5|$6" = "--source|$src|--working-tree|$src|--destination|$home" ] || {
    printf 'stub chezmoi: bad source or destination: %s\n' "$*" >&2
    exit 2
}
shift 6
[ "$1|$2|$3|$4|$5|$6|$7" = "--config|$home/.config/chezmoi/chezmoi.toml|--cache|$home/.cache/chezmoi|--persistent-state|$home/.local/state/chezmoi/chezmoi.boltdb|--mode=file" ] || {
    printf 'stub chezmoi: bad state paths: %s\n' "$*" >&2
    exit 2
}
shift 7
[ "$1 $2 $3 $4 $5" = "--no-tty --error-on-conflict --force=false --no-pager --use-builtin-diff" ] || {
    printf 'stub chezmoi: bad flags: %s\n' "$*" >&2
    exit 2
}
shift 5
[ -z "${E2E_STUB_LOG:-}" ] || printf '%s\n' "$*" >>"$E2E_STUB_LOG"
files='.bashrc .profile .zshrc .config/sh/.profile .ssh/config'
[ ! -f "$src/home/dot_local/bin/executable_dotfiles" ] || files="$files .local/bin/dotfiles"
case $* in
    init)
        config=$home/.config/chezmoi/chezmoi.toml
        [ -f "$config" ] && [ ! -L "$config" ] || {
            printf 'stub chezmoi: init without a regular local config\n' >&2
            exit 1
        }
        dest=$home
        [ "${E2E_STUB_INIT:-}" != foreign ] || dest=/elsewhere
        {
            printf 'destDir = "%s"\nmode = "file"\npersistentState = "%s/.local/state/chezmoi/chezmoi.boltdb"\nsourceDir = "%s"\n' \
                "$dest" "$dest" "$src"
            cat "$config"
        } >"$config.new" && mv -f "$config.new" "$config" || exit 1
        ;;
    'managed --include=dirs') printf '%s\n' .config .config/sh .ssh ;;
    'managed --include=files,symlinks') printf '%s\n' $files ;;
    'apply --include=dirs --recursive=false '*)
        [ "$#" = 4 ] || exit 2
        case $4 in
            "$home"/?*) ;;
            *)
                printf 'stub chezmoi: %s is not under the home\n' "$4" >&2
                exit 2
                ;;
        esac
        if [ -e "$4" ] || [ -L "$4" ]; then
            printf 'stub chezmoi: %s exists already\n' "$4" >&2
            exit 1
        fi
        mkdir -m 700 "$4" || exit 1
        ;;
    'apply --exclude=dirs')
        grep -qxF "destDir = \"$home\"" "$home/.config/chezmoi/chezmoi.toml" 2>/dev/null &&
            grep -qxF "sourceDir = \"$src\"" "$home/.config/chezmoi/chezmoi.toml" || {
            printf 'stub chezmoi: a target change before the config names this home and the clone\n' >&2
            exit 1
        }
        for f in $files; do
            case $f in
                */*) parent=$home/${f%/*} ;;
                *) parent=$home ;;
            esac
            [ -d "$parent" ] || {
                printf 'stub chezmoi: no directory for %s\n' "$f" >&2
                exit 1
            }
            if [ "$f" = .local/bin/dotfiles ]; then
                cp "$src/home/dot_local/bin/executable_dotfiles" "$home/$f" && chmod 755 "$home/$f" || exit 1
            else
                printf '# deployed %s\n' "$f" >"$home/$f" || exit 1
            fi
        done
        # PLANT-LINK
        mkdir -p "$home/.local/state/chezmoi" && printf 'db\n' >"$home/.local/state/chezmoi/chezmoi.boltdb" || exit 1
        ;;
    'diff --exclude=dirs')
        for f in $files; do
            if [ "$f" = .local/bin/dotfiles ]; then
                cmp "$src/home/dot_local/bin/executable_dotfiles" "$home/$f" >/dev/null 2>&1 && [ -x "$home/$f" ] ||
                    printf 'diff --git a/%s b/%s\n' "$f" "$f"
                continue
            fi
            [ "$(cat "$home/$f" 2>/dev/null)" = "# deployed $f" ] || printf 'diff --git a/%s b/%s\n' "$f" "$f"
        done
        [ "${E2E_STUB_DIFF:-}" != 1 ] || printf 'diff --git a/.bashrc b/.bashrc\n'
        ;;
    *)
        printf 'stub chezmoi: unexpected: %s\n' "$*" >&2
        exit 2
        ;;
esac
SH
    chmod 755 "$1"
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
# shellcheck source=tests/e2e/lib/steps.sh
. "$E2E_DIR/lib/steps.sh"
# shellcheck source=tests/e2e/lib/flow-other.sh
. "$E2E_DIR/lib/flow-other.sh"

# Fixture discovery is one rule for both flows: ~/.local/bin/chezmoi,
# else a chezmoi on PATH, else a blocking failure; a failing aggregate fails
# too.
mkdir -p "$UNIT/no-chezmoi-home" "$UNIT/fakebin"
printf '#!/bin/sh\nprintf "chezmoi version v2.74.0\\n"\n' >"$UNIT/fakebin/chezmoi"
chmod 755 "$UNIT/fakebin/chezmoi"
for flow in unix other; do
    fixtures_none=$(
        # shellcheck disable=SC2123 # deliberately hide every installed chezmoi
        HOME=$UNIT/no-chezmoi-home E2E_FLOW=$flow E2E_CLONE=$UNIT/missing-chezmoi-suite PATH=/no-chezmoi-tools
        e2e_step_begin() { :; }
        e2e_step_end() { printf '%s:%s\n' "$1" "$2"; }
        e2e_step_chezmoi_fixtures
        printf '%s\n' "$E2E_BROKEN"
    )
    expect_eq "chezmoi fixtures without a binary ($flow)" "$fixtures_none" 'fail:no provisioned chezmoi (~/.local/bin/chezmoi or PATH)
chezmoi-fixtures'
done
fixtures_failure=$(
    HOME=$UNIT/no-chezmoi-home E2E_FLOW=other E2E_CLONE=$UNIT/chezmoi-suite PATH="$UNIT/fakebin:$PATH"
    E2E_STEP_OUT=$UNIT/fixtures.out E2E_STEP_ERR=$UNIT/fixtures.err E2E_TIMEOUT_APPLY=1
    E2E_SYS_PATH=$PATH
    e2e_step_begin() { :; }
    e2e_step_end() { printf '%s\n' "$1"; }
    e2e_run() { return 1; }
    e2e_step_chezmoi_fixtures
    printf '%s\n' "$E2E_BROKEN"
)
expect_eq 'chezmoi suite failure is blocking' "$fixtures_failure" 'fail
chezmoi-fixtures'

# Fixture discovery needs the prepared login runtime: the base image may have
# no Python or an older Python without tomllib. Run the real suite entrypoint
# with a deliberately unusable base Python and a working login-only Python,
# and the binary at ~/.local/bin/chezmoi of a home with a space.
FIXTURES_HOME="$UNIT/fixtures home"
mkdir -p "$FIXTURES_HOME/runtime/bin" "$FIXTURES_HOME/base/bin" "$FIXTURES_HOME/fixture source/tests/lib" "$FIXTURES_HOME/.local/bin"
ln -s "$(command -v python3)" "$FIXTURES_HOME/runtime/bin/python3"
cp "$REPO_ROOT/tests/chezmoi.sh" "$FIXTURES_HOME/fixture source/tests/chezmoi.sh"
cp "$REPO_ROOT/tests/lib/environment.sh" "$FIXTURES_HOME/fixture source/tests/lib/environment.sh"
cat >"$FIXTURES_HOME/base/bin/python3" <<'SH'
#!/bin/sh
printf 'base image Python cannot run chezmoi fixtures\n' >&2
exit 79
SH
cat >"$FIXTURES_HOME/runtime/bin/zsh" <<'SH'
#!/bin/bash
set -eu
[ "$1" = -il ] && [ "$2" = -c ]
export PATH="$HOME/runtime/bin:$PATH"
exec /bin/bash --noprofile --norc -c "$3"
SH
cat >"$FIXTURES_HOME/.local/bin/chezmoi" <<'SH'
#!/bin/sh
[ "$1" = --version ] || exit 2
printf 'explicit chezmoi fixture binary\n'
SH
chmod +x "$FIXTURES_HOME/base/bin/python3" "$FIXTURES_HOME/runtime/bin/zsh" "$FIXTURES_HOME/.local/bin/chezmoi"
cat >"$FIXTURES_HOME/fixture source/tests/test_chezmoi_prepared_runtime.py" <<'PY'
from contextlib import chdir
import os
from pathlib import Path
import subprocess
import tomllib
import unittest


class PreparedRuntimeTests(unittest.TestCase):
    def test_login_runtime_preserves_explicit_binary_and_working_directory(self):
        home = Path(os.environ["HOME"])
        binary = os.environ["DOTFILES_TEST_CHEZMOI"]
        self.assertEqual(binary, str(home / ".local/bin/chezmoi"))
        self.assertEqual(os.environ["DOTFILES_TEST_REQUIRE_CHEZMOI"], "1")
        self.assertEqual(Path.cwd(), home / "fixture source")
        with chdir(home):
            self.assertEqual(tomllib.loads("prepared = true"), {"prepared": True})
        result = subprocess.run([binary, "--version"], capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout, "explicit chezmoi fixture binary\n")
        self.assertFalse(Path("force-failure").exists(), "deliberate chezmoi fixture failure")
PY
for fixtures_outcome in pass fail; do
    [ "$fixtures_outcome" != fail ] || : >"$FIXTURES_HOME/fixture source/force-failure"
    # shellcheck disable=SC2034 # run state consumed by the sourced e2e helpers
    fixtures_result=$(
        HOME=$FIXTURES_HOME E2E_FLOW=other E2E_CLONE="$FIXTURES_HOME/fixture source"
        PATH="$FIXTURES_HOME/base/bin:$PATH" E2E_SYS_PATH=$PATH
        E2E_LOGIN_ZSH="$FIXTURES_HOME/runtime/bin/zsh"
        E2E_STEP_OUT=$UNIT/fixtures-login.out E2E_STEP_ERR=$UNIT/fixtures-login.err
        E2E_STEP_LOG=$UNIT/fixtures-login.log E2E_TIMEOUT_APPLY=30 E2E_BROKEN=''
        e2e_step_begin() { :; }
        e2e_step_end() { printf '%s\n' "$1"; }
        e2e_step_chezmoi_fixtures
        printf '%s\n' "$E2E_BROKEN"
    )
    if [ "$fixtures_outcome" = pass ]; then
        [ "$fixtures_result" = pass ] || cat "$UNIT/fixtures-login.err" >&2
        expect_eq 'chezmoi fixtures use the prepared login Python and the home binary' "$fixtures_result" pass
    else
        expect_eq 'login chezmoi fixture failure remains blocking' "$fixtures_result" 'fail
chezmoi-fixtures'
        expect_text 'chezmoi fixture failure reaches phase stderr' "$UNIT/fixtures-login.err" 'deliberate chezmoi fixture failure'
    fi
done

# The stdout of an apply run that exits 3: plan lines, then four blocks: an
# apt sudo block, a sign-in reminder, an inspect gate whose %q path has a
# space, and the H7-deploy block, which holds notes only.
SHA=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
cat >"$UNIT/apply.out" <<'OUT'
P0-preflight done host lab-ubuntu, profile debian, Linux x86_64
H1-apt-core human missing apt packages: zsh
S5-claude human blocked by H1-apt-core: Claude Code is not installed
H7-deploy human follow Fresh home by hand in docs/bootstrap.md to initialize and deploy this home
HUMAN-BEGIN H1-apt-core sudo
# docs/bootstrap.md H1-apt-core
sudo apt-get update
sudo apt-get install -y --no-install-recommends zsh
HUMAN-END
HUMAN-BEGIN H7-auth auth
# docs/bootstrap.md H7-auth
ssh-keygen -t ed25519
gh auth login --git-protocol ssh
HUMAN-END
HUMAN-BEGIN S5-claude inspect
# docs/bootstrap.md S5-claude
# read it first; the line below runs it only while its sha256 is still the one above
printf '%s  %s\n' 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef /home/u/My\ Files/.cache/dotfiles-bootstrap/claude/install.sh | sha256sum -c --status - && bash /home/u/My\ Files/.cache/dotfiles-bootstrap/claude/install.sh
HUMAN-END
HUMAN-BEGIN H7-deploy judgment
# docs/bootstrap.md H7-deploy
# Follow Fresh home by hand in docs/bootstrap.md from this checkout.
# Select local [data].host = lab-ubuntu explicitly; setup-host never initializes or applies configuration.
HUMAN-END
OUT
cat >"$UNIT/apply.err" <<'ERR'
[dotfiles] [warn] uncommitted changes in /home/u/dotfiles: none
[dotfiles] [warn] HUMAN steps pending: H1-apt-core S5-claude H7-deploy; run the HUMAN blocks above, then rerun ./dotfiles setup --host lab-ubuntu
ERR
GATE_SPACE="printf '%s  %s\\n' $SHA /home/u/My\\ Files/.cache/dotfiles-bootstrap/claude/install.sh | sha256sum -c --status - && bash /home/u/My\\ Files/.cache/dotfiles-bootstrap/claude/install.sh"

e2e_blocks_parse "$UNIT/apply.out" "$UNIT/blocks"
expect_eq 'block count' "$(e2e_blocks_count "$UNIT/blocks")" 4
expect_eq 'block index' "$(cat "$UNIT/blocks/index")" "1${TAB}H1-apt-core${TAB}sudo
2${TAB}H7-auth${TAB}auth
3${TAB}S5-claude${TAB}inspect
4${TAB}H7-deploy${TAB}judgment"
expect_eq 'block row' "$(e2e_block_row "$UNIT/blocks" 4)" 'H7-deploy judgment'
expect_eq 'block summary' "$(e2e_blocks_summary "$UNIT/blocks")" 'H1-apt-core(sudo) H7-auth(auth) S5-claude(inspect) H7-deploy(judgment)'
expect_eq 'block 1 lines' "$(grep -c . "$UNIT/blocks/1.block")" 3
grep -Fx -- "$GATE_SPACE" "$UNIT/blocks/3.block" >/dev/null ||
    fail 'the %q-quoted gate line did not reach the block file byte for byte'
expect_eq 'run-gate takes the printed gate' "$(e2e_block_lines run-gate lab-ubuntu "$UNIT/blocks/3.block")" "$GATE_SPACE"
expect_no_text 'plan lines outside blocks' "$UNIT/blocks/1.block" 'P0-preflight'
expect_eq 'H7-deploy block holds notes only' "$(grep -cv '^# ' "$UNIT/blocks/4.block" || true)" 0
expect_eq 'pending ids' "$(e2e_pending_ids "$UNIT/apply.err")" 'H1-apt-core S5-claude H7-deploy'
: >"$UNIT/empty"
expect_eq 'pending ids without the line' "$(e2e_pending_ids "$UNIT/empty")" ''
expect_eq 'the H7-deploy block is found' "$(e2e_blocks_find "$UNIT/blocks" H7-deploy)" 4
expect_eq 'the first block is found' "$(e2e_blocks_find "$UNIT/blocks" H1-apt-core)" 1
if e2e_blocks_find "$UNIT/blocks" H9-unknown >/dev/null; then
    fail 'e2e_blocks_find found a block that was not printed'
fi

# The policy table, every row, and fail for anything else. The H7-deploy
# block is never run line by line.
while read -r id kind want; do
    expect_eq "policy $id $kind" "$(e2e_block_policy "$id" "$kind")" "$want"
done <<'ROWS'
H1-apt-core sudo run-all
H1-locale sudo run-all
H1-linuxbrew sudo run-all
H1-homebrew sudo run-all
S5-claude inspect run-gate
H7-deploy judgment deploy
H2-alloc alloc alloc
S2-modules judgment skip
H7-payloads judgment skip
H7-doctor judgment skip
H7-auth auth skip
H1-fcitx5 gui skip
H7-chsh chsh skip
H7-deploy sudo fail
H7-deploy inspect fail
H1-xcode-clt gui fail
S2-brew-bundle sudo fail
S2-brew-bundle judgment fail
S4-nvm judgment fail
X-recovery judgment fail
H1-apt-core judgment fail
S5-claude sudo fail
H9-unknown sudo fail
ROWS

# run-all takes every command line and no note; no other action than run-all
# and run-gate selects a line, the deploy and an unknown action included.
expect_eq 'run-all lines' "$(e2e_block_lines run-all lab-ubuntu "$UNIT/blocks/1.block")" 'sudo apt-get update
sudo apt-get install -y --no-install-recommends zsh'
for action in skip deploy run-unknown; do
    if e2e_block_lines "$action" lab-ubuntu "$UNIT/blocks/2.block" >/dev/null; then
        fail "e2e_block_lines ran lines for the $action action"
    fi
    expect_eq "$action action error" "$E2E_BLOCK_ERROR" "no lines run for action $action"
done
expect_eq 'deploy action error printed' "$(e2e_block_lines deploy lab-ubuntu "$UNIT/blocks/4.block")" 'no lines run for action deploy'

# The apply loop's verdict, a pure function of the run's exit code, its
# pending ids, whether a block was actionable and whether a step applied.
while IFS='|' read -r rc pending actionable applied want; do
    expect_eq "loop verdict [$rc|$pending|$actionable|$applied]" "$(e2e_loop_next "$rc" "$pending" "$actionable" "$applied")" "$want"
done <<'ROWS'
3|H7-deploy|0|0|done
3|H7-deploy|0|1|rerun
3|H7-deploy|1|0|blocks
3|H7-deploy|1|1|blocks
3|H1-apt-core H7-deploy|1|0|blocks
3|H1-apt-core H7-deploy|0|0|stuck
3|S5-claude H7-deploy|0|0|stuck
3|S5-claude H7-deploy|0|1|rerun
3|H7-deploy H7-auth|0|0|stuck
3||0|0|stuck
0|-|0|0|early
0|H7-deploy|0|1|early
1|x|0|0|error
2|x|0|0|error
124|x|0|0|timeout
137|x|0|0|timeout
ROWS

# The real gate printer (lib/bootstrap/steps-common.sh steps_digest_gate,
# in its block frame) in each profile, against a home with a space: every
# gate it prints is one the policy accepts, with the verifier of that
# profile.
mkdir -p "$UNIT/real/My Files"
real_block() {
    (
        # shellcheck disable=SC2034 # the STEPS_* fields and BOOTSTRAP_NL are read by the sourced step file
        STEPS_PROFILE=$1 STEPS_HOST=$2 STEPS_ROOT="$3/dotfiles" STEPS_MODE=apply STEPS_ARCH=x86_64
        # shellcheck disable=SC2034
        BOOTSTRAP_NL=$E2E_NL
        HOME=$3
        # shellcheck source=lib/bootstrap/steps-common.sh
        . "$REPO_ROOT/lib/bootstrap/steps-common.sh"
        bootstrap_doc_ref() { printf '%s\n' "$1"; }
        steps_block_begin S5-claude inspect
        steps_digest_gate "$4" "$HOME/.cache/dotfiles-bootstrap/claude/install.sh" \
            "bash $(steps_quote "$HOME/.cache/dotfiles-bootstrap/claude/install.sh")"
        steps_block_end
    )
}
while IFS='|' read -r profile host; do
    real_block "$profile" "$host" "$UNIT/real/My Files" "$SHA" >"$UNIT/real/$profile.out"
    e2e_blocks_parse "$UNIT/real/$profile.out" "$UNIT/real/$profile.blocks"
    expect_eq "real $profile blocks" "$(e2e_blocks_summary "$UNIT/real/$profile.blocks")" 'S5-claude(inspect)'
    got=$(e2e_block_lines run-gate "$host" "$UNIT/real/$profile.blocks/1.block") ||
        fail "run-gate refused the real $profile gate: $got; $(cat "$UNIT/real/$profile.blocks/1.block")"
    case $got in
        "printf '%s  %s\\n' $SHA $(printf '%q' "$UNIT/real/My Files/.cache/dotfiles-bootstrap/claude/install.sh") | "*) ;;
        *) fail "real $profile gate is [$got]" ;;
    esac
done <<'ROWS'
debian|lab-ubuntu
macos|mac
hpc|sherlock
ROWS
expect_eq 'real macos verifier' "$(grep -c 'shasum -a 256 -c --status -' "$UNIT/real/macos.blocks/1.block")" 1
expect_eq 'real debian verifier' "$(grep -c 'sha256sum -c --status -' "$UNIT/real/debian.blocks/1.block")" 1

# The digest gate: exactly one line of the printed shape, both verifiers,
# and nothing but notes besides it. A gate without --status, the Homebrew
# form (/bin/bash), a run of another path than the digested one, a chained
# tail, an extra pipe stage or a bare run line is a line the harness may
# not run; a block without the gate lacks its one line.
GATE="printf '%s  %s\\n' $SHA /home/u/.cache/dotfiles-bootstrap/claude/install.sh | sha256sum -c --status - && bash /home/u/.cache/dotfiles-bootstrap/claude/install.sh"
cat >"$UNIT/inspect.block" <<BLOCK
# docs/bootstrap.md S5-claude
# downloaded https://claude.ai/install.sh (unpinned vendor script) to /home/u/.cache/dotfiles-bootstrap/claude/install.sh
# sha256 $SHA, 1234 bytes; delete the file for a fresh copy
# read it first; the line below runs it only while its sha256 is still the one above
$GATE
# ./dotfiles doctor then checks the installed claude against tools.tsv
BLOCK
expect_eq 'run-gate line' "$(e2e_block_lines run-gate lab-ubuntu "$UNIT/inspect.block")" "$GATE"
sed 's/sha256sum -c --status -/shasum -a 256 -c --status -/' "$UNIT/inspect.block" >"$UNIT/inspect-mac.block"
expect_eq 'run-gate shasum' "$(e2e_block_lines run-gate mac "$UNIT/inspect-mac.block" | grep -c 'shasum -a 256 -c --status -')" 1
printf '%s\n' "$GATE_SPACE" >"$UNIT/inspect-space.block"
expect_eq 'run-gate %q path with a space' "$(e2e_block_lines run-gate lab-ubuntu "$UNIT/inspect-space.block")" "$GATE_SPACE"
for variant in 's/ --status//' 's/&& bash /\&\& NONINTERACTIVE=1 \/bin\/bash /' \
    '/^printf/s|&& bash .*$|\&\& bash /tmp/other.sh|' \
    '/^printf/s/$/; rm -rf ~/' \
    '/^printf/s/ | sha256sum/ | evil; true | sha256sum/' \
    '/^printf/s/$/ \&\& .\/dotfiles doctor/' \
    '/^printf/s/$/ /' \
    '/^printf/s/install.sh |/install.sh;x |/' \
    "/^printf/s/$SHA/${SHA}0/" \
    '/^printf/s| /home/u/| home/u/|g'; do
    sed "$variant" "$UNIT/inspect.block" >"$UNIT/inspect-bad.block"
    grep -Fx -- "$GATE" "$UNIT/inspect-bad.block" >/dev/null && fail "sed [$variant] left the gate line as it was"
    if e2e_block_lines run-gate lab-ubuntu "$UNIT/inspect-bad.block" >/dev/null; then
        fail "run-gate accepted an inspect block after sed [$variant]"
    fi
    expect_eq "run-gate error after [$variant]" "$E2E_BLOCK_ERROR" "an inspect line the harness may not run: $(sed -n '/^printf/p' "$UNIT/inspect-bad.block")"
done
sed '/^printf/d' "$UNIT/inspect.block" >"$UNIT/inspect-bad.block"
if e2e_block_lines run-gate lab-ubuntu "$UNIT/inspect-bad.block" >/dev/null; then
    fail 'run-gate accepted an inspect block without the gate'
fi
expect_eq 'run-gate error without the gate' "$E2E_BLOCK_ERROR" 'the inspect block has 0 digest-gated run lines, not 1'
{
    cat "$UNIT/inspect.block"
    printf '%s\n' "$GATE"
} >"$UNIT/inspect-twice.block"
if e2e_block_lines run-gate lab-ubuntu "$UNIT/inspect-twice.block" >/dev/null; then
    fail 'run-gate accepted two gated lines'
fi
expect_eq 'run-gate twice error' "$E2E_BLOCK_ERROR" 'the inspect block has 2 digest-gated run lines, not 1'
printf '%s\n' '# docs/bootstrap.md S5-claude' 'bash /home/u/.cache/dotfiles-bootstrap/claude/install.sh' >"$UNIT/inspect-bare.block"
if e2e_block_lines run-gate lab-ubuntu "$UNIT/inspect-bare.block" >/dev/null; then
    fail 'run-gate accepted a bare run line'
fi
expect_eq 'run-gate bare error' "$E2E_BLOCK_ERROR" 'an inspect line the harness may not run: bash /home/u/.cache/dotfiles-bootstrap/claude/install.sh'
{
    cat "$UNIT/inspect.block"
    printf '%s\n' 'bash /home/u/.cache/dotfiles-bootstrap/claude/install.sh'
} >"$UNIT/inspect-gate-bare.block"
if e2e_block_lines run-gate lab-ubuntu "$UNIT/inspect-gate-bare.block" >/dev/null; then
    fail 'run-gate accepted an un-gated run line beside the gate'
fi
expect_eq 'run-gate gate+bare error' "$E2E_BLOCK_ERROR" 'an inspect line the harness may not run: bash /home/u/.cache/dotfiles-bootstrap/claude/install.sh'
expect_eq 'run-gate gate+bare error printed' "$(e2e_block_lines run-gate lab-ubuntu "$UNIT/inspect-gate-bare.block")" 'an inspect line the harness may not run: bash /home/u/.cache/dotfiles-bootstrap/claude/install.sh'

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
# A caller capturing the output sees the reason too (the variable is lost in
# its subshell).
expect_eq 'alloc error printed' "$(e2e_alloc_exports 'SLURM_JOB_ID=1 bogus')" 'E2E_ALLOC_ENV word is not KEY=value: bogus'
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

# The wrappers.log audit: human and negative phases pass; any other phase
# or no phase fails, whatever the tool and its arguments; on a host
# without sudo any sudo line fails.
printf '%s\t%s\t%s\t%s\t%s\t%s\n' 1700000000 human:H1-apt-core sudo 42 'bash -c sudo apt-get update' 'apt-get update' \
    1700000010 negative:root-refused sudo 43 'bash' '-n ./dotfiles setup --host lab-ubuntu --check' \
    1700000015 human:H1-locale sudo 47 'bash -c sudo locale-gen en_US.UTF-8' 'locale-gen en_US.UTF-8' \
    1700000020 human:H7-chsh chsh 44 'bash -c chsh -s /usr/bin/zsh' '-s /usr/bin/zsh' >"$UNIT/wrappers.log"
bad=$(e2e_audit_wrappers "$UNIT/wrappers.log") || fail "wrappers audit failed a clean log: $bad"
if bad=$(e2e_audit_no_sudo "$UNIT/wrappers.log"); then
    fail 'no-sudo audit passed a log with sudo lines'
fi
expect_eq 'no-sudo audit lines' "$(printf '%s\n' "$bad" | grep -c .)" 3
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

# The login shell's stderr filter drops only what a missing terminal causes
# (the stty line, fzf's zle option restore) and keeps everything else.
printf '%s\n' "stty: 'standard input': Inappropriate ioctl for device" \
    "(eval):1: can't change option: zle" \
    "(eval):1: can't change option: zle" >"$UNIT/login-noise.err"
expect_eq 'login noise filter drops the terminal-only lines' "$(e2e_login_noise "$UNIT/login-noise.err")" ''
printf '%s\n' "stty: stdin isn't a terminal" \
    "(eval):1: can't change option: zle" \
    "[oh-my-zsh] plugin 'fzf-tab' not found" \
    "(eval):7: can't change option: monitor" \
    'zsh: command not found: eza' >"$UNIT/login-real.err"
expect_eq 'login noise filter keeps real complaints' "$(e2e_login_noise "$UNIT/login-real.err")" \
    "[oh-my-zsh] plugin 'fzf-tab' not found
(eval):7: can't change option: monitor
zsh: command not found: eza"
# The stdout filter drops terminal control (Fedora's /etc/zlogout `clear`)
# and keeps text, even text wrapped in colour.
printf '\033[H\033[2J\033[3J\r' >"$UNIT/login-clear.out"
expect_eq 'login text filter drops a clear' "$(e2e_login_text "$UNIT/login-clear.out")" ''
printf '\033[H\033[2J\033[1;31mgitstatus failed\033[0m\n' >"$UNIT/login-text.out"
expect_eq 'login text filter keeps text' "$(e2e_login_text "$UNIT/login-text.out")" 'gitstatus failed'

# The real wrappers with two copies on PATH, as on the macOS runner
# (/usr/local/bin and $E2E_OUT/bin): the first logs the call once and runs
# the real tool, skipping the other copy, and with no real tool both give up
# with 127 instead of exec'ing each other. PATH holds only the copies, the
# fake real tool and the few utilities the wrapper uses, so a chsh or sudo
# of the test machine is never reached.
WRAP="$UNIT/wrap"
mkdir -p "$WRAP/a" "$WRAP/b" "$WRAP/real" "$WRAP/util" "$WRAP/out"
for tool in chsh sudo; do
    cp "$REPO_ROOT/tests/e2e/wrappers/$tool" "$WRAP/a/$tool"
    cp "$REPO_ROOT/tests/e2e/wrappers/$tool" "$WRAP/b/$tool"
    chmod 755 "$WRAP/a/$tool" "$WRAP/b/$tool"
done
for util in grep tr date mkdir ps dirname cat; do
    found=$(command -v "$util") || fail "the wrapper test needs $util"
    ln -s "$found" "$WRAP/util/$util"
done
printf '#!/bin/sh\necho "real chsh $*"\n' >"$WRAP/real/chsh"
chmod 755 "$WRAP/real/chsh"
# timeout is named by its full path: the PATH prefix below also governs the
# lookup of the command it precedes.
WRAP_LIMIT=$(command -v timeout 2>/dev/null) || WRAP_LIMIT=
wrap_run() {
    local status=0
    if [ -n "$WRAP_LIMIT" ]; then
        E2E_OUT="$WRAP/out" E2E_PHASE=check:unit PATH="$1" "$WRAP_LIMIT" 20 "$WRAP/a/$2" --version >"$WRAP/run.out" 2>&1 || status=$?
    else
        E2E_OUT="$WRAP/out" E2E_PHASE=check:unit PATH="$1" "$WRAP/a/$2" --version >"$WRAP/run.out" 2>&1 || status=$?
    fi
    printf '%s\n' "$status"
}
expect_eq 'two wrapper copies reach the real tool' "$(wrap_run "$WRAP/a:$WRAP/b:$WRAP/real:$WRAP/util" chsh)" 0
expect_eq 'the real tool ran once' "$(cat "$WRAP/run.out")" 'real chsh --version'
expect_eq 'one log line for one call' "$(grep -c . "$WRAP/out/log/wrappers.log")" 1
expect_eq 'two wrapper copies and no real tool give up' "$(wrap_run "$WRAP/a:$WRAP/b:$WRAP/util" sudo)" 127
expect_eq 'the give-up message' "$(cat "$WRAP/run.out")" 'e2e wrapper: real sudo not found'

# tests/e2e/timeout.pl, the per-command limit on a machine without timeout
# or gtimeout (the macos-15 runner): GNU timeout's exit codes, the command's
# own status passed through, and the whole process group gone after a
# timeout, so a hung grandchild does not outlive its step.
if command -v perl >/dev/null 2>&1; then
    TPL="$E2E_DIR/timeout.pl"
    tpl_run() { # LIMIT COMMAND...: the exit code
        local status=0
        "$TPL" "$@" >/dev/null 2>&1 || status=$?
        printf '%s\n' "$status"
    }
    start=$(date +%s)
    expect_eq 'timeout.pl times out with 124' "$(tpl_run 1 sleep 30)" 124
    elapsed=$(($(date +%s) - start))
    [ "$elapsed" -le 8 ] || fail "timeout.pl took ${elapsed}s for a 1s limit"
    expect_eq 'timeout.pl passes a status through' "$(tpl_run 10 sh -c 'exit 3')" 3
    expect_eq 'timeout.pl passes success through' "$(tpl_run 10 true)" 0
    expect_eq 'timeout.pl reports a signal as 128+N' "$(tpl_run 10 sh -c 'kill -TERM $$')" 143
    expect_eq 'timeout.pl cannot run a missing command' "$(tpl_run 10 "$UNIT/no-such-command")" 127
    expect_eq 'timeout.pl refuses a bad limit' "$(tpl_run x true)" 125
    # A grandchild in the command's process group dies with it.
    tpl_run 1 sh -c "sleep 30 & echo \$! >'$UNIT/grandchild.pid'; wait" >/dev/null
    grandchild=$(cat "$UNIT/grandchild.pid")
    sleep 1
    if kill -0 "$grandchild" 2>/dev/null; then
        kill "$grandchild" 2>/dev/null || true
        fail 'timeout.pl left a grandchild running after the limit'
    fi
    # e2e_find_timeout picks it only when neither timeout nor gtimeout exists.
    mkdir -p "$UNIT/noto"
    ln -s "$(command -v perl)" "$UNIT/noto/perl"
    expect_eq 'e2e_find_timeout falls back to timeout.pl' \
        "$(PATH="$UNIT/noto" e2e_find_timeout && printf '%s\n' "$E2E_TIMEOUT_BIN")" "$TPL"
    if command -v timeout >/dev/null 2>&1; then
        expect_eq 'e2e_find_timeout prefers timeout' "$(e2e_find_timeout && printf '%s\n' "$E2E_TIMEOUT_BIN")" timeout
    fi
else
    printf 'SKIP: tests/e2e/timeout.pl (perl unavailable).\n'
fi

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
        printf '    zsh git\n'
        printf '%s : tester : TTY=unknown ; PWD=/home/tester/dotfiles ; USER=root ; COMMAND=./dotfiles setup\n' \
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

# The by-hand helpers of the other flow: the real fence defines both
# helpers and nothing else; a top-level line planted after the definitions,
# or indented between them, is refused by name, since the file is sourced
# at the start of every by-hand step; so is a fence without the heading.
e2e_extract_helpers "$REPO_ROOT/docs/bootstrap.md" "$UNIT/helpers.sh" || fail 'extract_helpers refused docs/bootstrap.md'
expect_eq 'helpers define both' "$(grep -cE '^(fetch_pinned|clone_listed)\(\) \{$' "$UNIT/helpers.sh")" 2
expect_eq 'helpers hold nothing else in column 0' "$(grep -cvE '^(#|[ \t]|\}$|fetch_pinned\(\) \{$|clone_listed\(\) \{$|$)' "$UNIT/helpers.sh")" 0
# LINE reaches awk through the environment: macOS awk (the One True AWK)
# refuses a newline in a -v assignment, and the third case plants three lines.
plant_fence() { # DOC HEADING OUT LINE: LINE just before the closing ``` of the fence after HEADING
    E2E_PLANT=$4 E2E_PLANT_HEADING=$2 awk '
        index($0, "# " ENVIRON["E2E_PLANT_HEADING"]) && /^#+ / { s = 1 }
        s && !i && /^```sh/ { i = 1 }
        i && !p && /^```$/ { print ENVIRON["E2E_PLANT"]; p = 1 }
        { print }
    ' "$1" >"$3"
}
plant_fence "$REPO_ROOT/docs/bootstrap.md" 'Downloads and clones by hand' "$UNIT/bootstrap-planted.md" 'fetch_pinned claude'
if e2e_extract_helpers "$UNIT/bootstrap-planted.md" "$UNIT/helpers-planted.sh" >"$UNIT/helpers-planted.out"; then
    fail 'extract_helpers accepted a top-level line after the definitions'
fi
expect_eq 'planted line named' "$(cat "$UNIT/helpers-planted.out")" 'a line outside the fetch_pinned and clone_listed definitions in the fenced sh block: fetch_pinned claude'
plant_fence "$REPO_ROOT/docs/bootstrap.md" 'Downloads and clones by hand' "$UNIT/bootstrap-planted.md" '    export CURL_CA_BUNDLE=/tmp/evil.pem'
if e2e_extract_helpers "$UNIT/bootstrap-planted.md" "$UNIT/helpers-planted.sh" >"$UNIT/helpers-planted.out"; then
    fail 'extract_helpers accepted an indented top-level line'
fi
expect_eq 'indented planted line named' "$(cat "$UNIT/helpers-planted.out")" 'a line outside the fetch_pinned and clone_listed definitions in the fenced sh block:     export CURL_CA_BUNDLE=/tmp/evil.pem'
plant_fence "$REPO_ROOT/docs/bootstrap.md" 'Downloads and clones by hand' "$UNIT/bootstrap-planted.md" 'helper_three() {
    :
}'
if e2e_extract_helpers "$UNIT/bootstrap-planted.md" "$UNIT/helpers-planted.sh" >"$UNIT/helpers-planted.out"; then
    fail 'extract_helpers accepted a third definition'
fi
expect_eq 'third definition named' "$(cat "$UNIT/helpers-planted.out")" 'a line outside the fetch_pinned and clone_listed definitions in the fenced sh block: helper_three() {'
sed 's/^### Downloads and clones by hand/### Something else/' "$REPO_ROOT/docs/bootstrap.md" >"$UNIT/bootstrap-moved.md"
if e2e_extract_helpers "$UNIT/bootstrap-moved.md" "$UNIT/helpers-moved.sh" >"$UNIT/helpers-moved.out"; then
    fail 'extract_helpers found a fence without the heading'
fi
expect_eq 'moved heading named' "$(cat "$UNIT/helpers-moved.out")" 'no fenced sh block after "Downloads and clones by hand"'

# The by-hand chezmoi route: the extracted fetch_pinned, under a curl that
# records its URL and fails, asks for the generic Linux archive of the
# pinned release for each architecture, so a reordered installers.tsv (a
# musl or macOS row first) fails here; and the S4-chezmoi line the other
# flow runs is the documented one.
FP_HOME="$UNIT/fp home"
mkdir -p "$FP_HOME/dotfiles/config/bootstrap" "$UNIT/fp-bin" "$UNIT/fp-tmp"
cp "$REPO_ROOT/config/bootstrap/installers.tsv" "$FP_HOME/dotfiles/config/bootstrap/installers.tsv"
printf '#!/bin/sh\nfor a do u=$a; done\nprintf "%%s\\n" "$u" >>"$E2E_FP_LOG"\nexit 1\n' >"$UNIT/fp-bin/curl"
chmod 755 "$UNIT/fp-bin/curl"
CZ_VERSION=$(cat "$REPO_ROOT/.chezmoiversion")
for row in 'x86_64 amd64' 'aarch64 arm64'; do
    : >"$UNIT/fp.log"
    fp_rc=0
    env -i HOME="$FP_HOME" PATH="$UNIT/fp-bin:/usr/bin:/bin" TMPDIR="$UNIT/fp-tmp" E2E_FP_LOG="$UNIT/fp.log" \
        "$BASH" -c ". $(e2e_quote "$UNIT/helpers.sh") && fetch_pinned chezmoi ${row%% *}" >/dev/null 2>&1 || fp_rc=$?
    expect_eq "fetch_pinned chezmoi ${row%% *} fails with the curl stub" "$fp_rc" 1
    case $(cat "$UNIT/fp.log") in
        */chezmoi_"${CZ_VERSION}"_linux_"${row#* }".tar.gz) ;;
        *) fail "fetch_pinned chezmoi ${row%% *} requested [$(cat "$UNIT/fp.log")], not the generic linux_${row#* } archive" ;;
    esac
done
grep -F -- "$E2E_CHEZMOI_LINE" "$REPO_ROOT/docs/bootstrap.md" >/dev/null ||
    fail 'docs/bootstrap.md lacks the by-hand S4-chezmoi line the other flow runs (E2E_CHEZMOI_LINE)'
printf 'ok: block parser, policy, verdicts, gate, alloc, audit parsers and by-hand helpers\n'

# "Fresh home by hand": the real fence defines exactly home_cz and
# home_deploy; a planted top-level line and a moved heading are refused
# by name, as the by-hand helpers are.
e2e_extract_fence "$REPO_ROOT/docs/bootstrap.md" 'Fresh home by hand' "$UNIT/fresh.sh" home_cz home_deploy ||
    fail 'e2e_extract_fence refused the Fresh home by hand fence'
expect_eq 'fresh home defines both' "$(grep -cE '^(home_cz|home_deploy)\(\) \{$' "$UNIT/fresh.sh")" 2
expect_eq 'fresh home holds nothing else in column 0' "$(grep -cvE '^(#|[ \t]|\}$|home_cz\(\) \{$|home_deploy\(\) \{$|$)' "$UNIT/fresh.sh" || true)" 0
plant_fence "$REPO_ROOT/docs/bootstrap.md" 'Fresh home by hand' "$UNIT/fresh-planted.md" 'home_deploy lab-ubuntu'
if e2e_extract_fence "$UNIT/fresh-planted.md" 'Fresh home by hand' "$UNIT/fresh-planted.sh" home_cz home_deploy >"$UNIT/fresh-planted.out"; then
    fail 'e2e_extract_fence accepted a top-level call in the fresh home fence'
fi
expect_eq 'fresh home planted line named' "$(cat "$UNIT/fresh-planted.out")" 'a line outside the home_cz and home_deploy definitions in the fenced sh block: home_deploy lab-ubuntu'
sed 's/^#### Fresh home by hand/#### Fresh home, by hand/' "$REPO_ROOT/docs/bootstrap.md" >"$UNIT/fresh-moved.md"
if e2e_extract_fence "$UNIT/fresh-moved.md" 'Fresh home by hand' "$UNIT/fresh-moved.sh" home_cz home_deploy >"$UNIT/fresh-moved.out"; then
    fail 'e2e_extract_fence found the fresh home fence without its heading'
fi
expect_eq 'fresh home moved heading named' "$(cat "$UNIT/fresh-moved.out")" 'no fenced sh block after "Fresh home by hand"'
if e2e_extract_fence "$REPO_ROOT/docs/bootstrap.md" 'Fresh home by hand' "$UNIT/fresh-third.sh" home_cz home_deploy missing_third >"$UNIT/fresh-third.out"; then
    fail 'e2e_extract_fence accepted a fence without a requested definition'
fi
expect_eq 'fresh home missing definition named' "$(cat "$UNIT/fresh-third.out")" 'the fenced sh block lacks a "home_cz() {" or a "home_deploy() {" or a "missing_third() {" line'
printf 'ok: Fresh home by hand extraction\n'

# The two functions, run as a person pastes them, against the stub chezmoi
# in a fresh home whose name has a space (an /etc/skel .bashrc, a clone with
# .chezmoiroot at ~/dotfiles), under bash, sh and zsh.
CZBIN="$UNIT/czbin"
mkdir -p "$CZBIN" "$UNIT/shells"
write_chezmoi_stub "$CZBIN/chezmoi"
fresh_home() { # NAME: a fresh home in FRESH_HOME, its stub log in FRESH_LOG
    FRESH_HOME="$UNIT/fresh/$1/home dir"
    FRESH_LOG="$UNIT/fresh/$1/stub.log"
    mkdir -p "$FRESH_HOME/dotfiles/lib"
    printf 'home\n' >"$FRESH_HOME/dotfiles/.chezmoiroot"
    cp "$REPO_ROOT/lib/chezmoi-guard.sh" "$FRESH_HOME/dotfiles/lib/"
    printf '# /etc/skel\n' >"$FRESH_HOME/.bashrc"
    : >"$FRESH_LOG"
}
# fresh_run SHELL CODE [NAME=value...]: CODE after the extracted functions,
# in SHELL, from FRESH_CWD (default the clone), in an environment of HOME,
# the stub's PATH and NAME=value only; FRESH_RC is its exit code.
fresh_run() {
    local shell=$1 code=$2
    shift 2
    FRESH_RC=0
    (cd "${FRESH_CWD:-$FRESH_HOME/dotfiles}" &&
        exec env -i HOME="$FRESH_HOME" PATH="$CZBIN:/usr/bin:/bin" LC_ALL=C E2E_STUB_LOG="$FRESH_LOG" "$@" \
            "$shell" -c ". $(e2e_quote "$UNIT/fresh.sh") && $code") >"$FRESH_HOME.out" 2>"$FRESH_HOME.err" || FRESH_RC=$?
}
expect_refusal() { # NAME TEXT: FRESH_RC 1, TEXT on stderr, no apply
    expect_eq "$1: exit" "$FRESH_RC" 1
    expect_text "$1: stderr" "$FRESH_HOME.err" "$2"
    expect_no_text "$1: no apply" "$FRESH_LOG" apply
}
for shell in bash sh zsh; do
    case $shell in
        bash) exe=$BASH ;;
        sh) exe=/bin/sh ;;
        zsh)
            if ! zsh_path=$(command -v zsh); then
                printf 'SKIP: Fresh home by hand under zsh (zsh unavailable).\n'
                continue
            fi
            # -f: no startup file of the test machine's zsh.
            printf '#!/bin/sh\nexec %s -f "$@"\n' "$zsh_path" >"$UNIT/shells/zsh"
            chmod 755 "$UNIT/shells/zsh"
            exe=$UNIT/shells/zsh
            ;;
    esac
    fresh_home "proto-$shell"
    fresh_run "$exe" 'home_deploy lab-ubuntu'
    [ "$FRESH_RC" = 0 ] || {
        cat "$FRESH_HOME.err" >&2
        fail "home_deploy under $shell exited $FRESH_RC"
    }
    phys_home=$(cd -P "$FRESH_HOME" && pwd -P)
    expect_eq "fresh $shell call order" "$(cat "$FRESH_LOG")" "init
managed --include=dirs
managed --include=files,symlinks
apply --include=dirs --recursive=false $phys_home/.config/sh
apply --include=dirs --recursive=false $phys_home/.ssh
apply --exclude=dirs
apply --exclude=dirs
diff --exclude=dirs"
    # The seed config with the top-level lines the stub init wrote, which
    # the clone's guard accepts as naming this home and the clone.
    printf 'destDir = "%s"\nmode = "file"\npersistentState = "%s/.local/state/chezmoi/chezmoi.boltdb"\nsourceDir = "%s"\numask = 0o077\n\n[data]\nhost = "lab-ubuntu"\n' \
        "$phys_home" "$phys_home" "$phys_home/dotfiles" >"$UNIT/fresh/want-config"
    cmp -s "$UNIT/fresh/want-config" "$FRESH_HOME/.config/chezmoi/chezmoi.toml" || fail "fresh $shell config: $(cat "$FRESH_HOME/.config/chezmoi/chezmoi.toml")"
    expect_eq "fresh $shell config source" "$(. "$REPO_ROOT/lib/chezmoi-guard.sh" && dotfiles_chezmoi_source "$FRESH_HOME")" "$phys_home/dotfiles"
    [ ! -e "$FRESH_HOME/.config/dotfiles" ] || fail "fresh $shell created ~/.config/dotfiles"
    expect_eq "fresh $shell backup mode" "$(ls -ld "$FRESH_HOME/.local/state/dotfiles-fresh-backup" | cut -c1-10)" 'drwx------'
    printf '# /etc/skel\n' >"$UNIT/fresh/want-bashrc"
    cmp -s "$UNIT/fresh/want-bashrc" "$FRESH_HOME/.local/state/dotfiles-fresh-backup/.bashrc" || fail "fresh $shell kept no copy of the skel .bashrc"
    [ ! -e "$FRESH_HOME/.local/state/dotfiles-fresh-backup/.profile" ] || fail "fresh $shell copied a .profile that did not exist"
    [ ! -e "$FRESH_HOME/.config/dotfiles/maintenance" ] || fail "fresh $shell created maintenance"
    [ -s "$FRESH_HOME/.local/state/chezmoi/chezmoi.boltdb" ] || fail "fresh $shell has no state database"
    expect_eq "fresh $shell targets" "$(cat "$FRESH_HOME/.bashrc")" '# deployed .bashrc'
    expect_text "fresh $shell result" "$FRESH_HOME.out" 'home_deploy: lab-ubuntu deployed; copies of the files it replaced are in ~/.local/state/dotfiles-fresh-backup'
done

# Each refusal exits 1 before a target is written, and before the seed
# config exists when there was none: maintenance, a local config, a state
# database or the backup directory; a role it does not know (win has its own
# procedure); a shell outside the clone.
for rel in .config/dotfiles/maintenance .config/chezmoi/chezmoi.toml \
    .local/state/chezmoi/chezmoi.boltdb .local/state/dotfiles-fresh-backup; do
    fresh_home "exists$(printf '%s' "$rel" | tr '/.' '--')"
    mkdir -p "$(dirname "$FRESH_HOME/$rel")"
    : >"$FRESH_HOME/$rel"
    fresh_run "$BASH" 'home_deploy lab-ubuntu'
    expect_refusal "fresh refusal for ~/$rel" "home_deploy: ~/$rel exists, so this is no fresh home; inspect it and move it aside first"
    [ "$rel" = .config/chezmoi/chezmoi.toml ] || [ ! -e "$FRESH_HOME/.config/chezmoi/chezmoi.toml" ] ||
        fail "fresh refusal for ~/$rel created the seed config"
    expect_eq "fresh refusal for ~/$rel ran no chezmoi" "$(cat "$FRESH_LOG")" ''
done
for role in win nope ''; do
    fresh_home "role-${role:-empty}"
    fresh_run "$BASH" "home_deploy $(e2e_quote "$role")"
    expect_refusal "fresh role [$role]" 'home_deploy: name the role: generic, mac, wsl-ubuntu, lab-ubuntu, sherlock or marlowe'
    [ ! -e "$FRESH_HOME/.config/chezmoi/chezmoi.toml" ] || fail "fresh role [$role] created the seed config"
done
fresh_home outside
FRESH_CWD=$FRESH_HOME fresh_run "$BASH" 'home_deploy lab-ubuntu'
expect_refusal 'fresh outside the clone' 'home_deploy: run it from the dotfiles clone'
[ ! -e "$FRESH_HOME/.config/chezmoi/chezmoi.toml" ] || fail 'fresh outside the clone created the seed config'
FRESH_CWD=$FRESH_HOME fresh_run "$BASH" 'home_cz managed --include=dirs'
expect_refusal 'home_cz outside the clone' 'home_cz: run it from the dotfiles clone'
# A config init wrote that does not name this home and the clone stops it
# before any apply.
fresh_home foreign-config
fresh_run "$BASH" 'home_deploy lab-ubuntu' E2E_STUB_INIT=foreign
expect_refusal 'fresh config naming another home' 'home_deploy: ~/.config/chezmoi/chezmoi.toml does not name this home and this clone; inspect it privately'
# A link, or an entry of the wrong kind, at a managed path stops it before
# any apply.
fresh_home link
ln -s .bashrc "$FRESH_HOME/.profile"
fresh_run "$BASH" 'home_deploy lab-ubuntu'
expect_refusal 'fresh link at ~/.profile' 'home_deploy: ~/.profile is a link or not a regular file; inspect it and move it aside first'
fresh_home ssh-file
: >"$FRESH_HOME/.ssh"
fresh_run "$BASH" 'home_deploy lab-ubuntu'
expect_refusal 'fresh file at ~/.ssh' 'home_deploy: ~/.ssh is not a directory; inspect it and move it aside first'
fresh_home dir-at-file
mkdir -p "$FRESH_HOME/.zshrc"
fresh_run "$BASH" 'home_deploy lab-ubuntu'
expect_refusal 'fresh directory at ~/.zshrc' 'home_deploy: ~/.zshrc is a link or not a regular file'
# Targets that still differ after the two applies stop it.
fresh_home differ
fresh_run "$BASH" 'home_deploy lab-ubuntu' E2E_STUB_DIFF=1
expect_eq 'fresh diff exit' "$FRESH_RC" 1
expect_text 'fresh diff stderr' "$FRESH_HOME.err" 'home_deploy: targets still differ after two applies; review home_cz diff --exclude=dirs privately'
# Without ~/.local/bin/chezmoi and with none on PATH, home_cz names the
# step that installs it.
if [ -x /usr/bin/chezmoi ] || [ -x /bin/chezmoi ]; then
    printf 'SKIP: home_cz without a chezmoi (this machine has one in /usr/bin or /bin).\n'
else
    fresh_home no-binary
    fresh_run "$BASH" 'home_cz managed --include=dirs' PATH=/usr/bin:/bin
    expect_refusal 'home_cz without a chezmoi' 'home_cz: no chezmoi; run S4-chezmoi first'
fi
printf 'ok: Fresh home by hand under the stub chezmoi\n'

# e2e_deploy_problems: the end state the home-deploy step requires,
# against a home that has it, then against one mutation at a time.
HP="$UNIT/hp"
mkdir -p "$HP/good/dotfiles/lib" "$HP/good/.config/dotfiles" "$HP/good/.config/chezmoi" \
    "$HP/good/.local/state/chezmoi" "$HP/good/.local/state/dotfiles-fresh-backup"
printf 'home\n' >"$HP/good/dotfiles/.chezmoiroot"
cp "$REPO_ROOT/lib/chezmoi-guard.sh" "$HP/good/dotfiles/lib/"
printf 'umask = 63\n\n[data]\n  host = "lab-ubuntu"\n' >"$HP/good/.config/chezmoi/chezmoi.toml"
printf 'db\n' >"$HP/good/.local/state/chezmoi/chezmoi.boltdb"
printf '# deployed .zshrc\n' >"$HP/good/.zshrc"
printf '# /etc/skel\n' >"$HP/good/.local/state/dotfiles-fresh-backup/.bashrc"
HP_BEFORE=".bashrc=$(e2e_sha256 "$HP/good/.local/state/dotfiles-fresh-backup/.bashrc")"
# dp_case NAME MUTATION: the problems e2e_deploy_problems reports for a
# copy of the good home after MUTATION (shell code run in that copy), then
# the kept count, as "<problems>|<kept>".
dp_case() {
    rm -rf "${HP:?}/$1"
    cp -Rp "$HP/good" "$HP/$1"
    (cd "$HP/$1" && eval "$2")
    (
        # shellcheck disable=SC2034 # read by the sourced lib/assert.sh
        HOME=$HP/$1 E2E_CLONE=$HP/$1/dotfiles E2E_RC_BEFORE=$HP_BEFORE
        e2e_deploy_problems lab-ubuntu || true
        printf '%s|%s\n' "$E2E_DEPLOY_DETAIL" "$E2E_DEPLOY_KEPT"
    )
}
# name_copy [DEST [SOURCE]]: the copy's config names DEST (default the copy)
# and SOURCE (default the copy's clone) in the lines chezmoi init writes.
name_copy() {
    local phys
    phys=$(pwd -P)
    { printf 'destDir = "%s"\nsourceDir = "%s"\n' "${1:-$phys}" "${2:-$phys/dotfiles}" && cat .config/chezmoi/chezmoi.toml; } >.config/chezmoi/top.toml &&
        mv .config/chezmoi/top.toml .config/chezmoi/chezmoi.toml
}
expect_eq 'deploy end state' "$(dp_case own 'name_copy')" '|1'
while IFS='|' read -r name mutation want; do
    got=$(dp_case "$name" "$mutation")
    case $got in
        *"$want"*) ;;
        *) fail "deploy problem $name: [$got] lacks [$want]" ;;
    esac
done <<'ROWS'
elsewhere|name_copy /elsewhere|~/.config/chezmoi/chezmoi.toml does not name this home and the clone
othersource|mkdir -p other && printf 'home\n' >other/.chezmoiroot && name_copy "" "$(pwd -P)/other"|~/.config/chezmoi/chezmoi.toml does not name this home and the clone
twice|name_copy && name_copy|~/.config/chezmoi/chezmoi.toml does not name this home and the clone
nosource|name_copy && grep -v '^sourceDir = ' .config/chezmoi/chezmoi.toml >c && mv c .config/chezmoi/chezmoi.toml|~/.config/chezmoi/chezmoi.toml does not name this home and the clone
role|name_copy && sed 's/host = "lab-ubuntu"/host = "mac"/' .config/chezmoi/chezmoi.toml >c && mv c .config/chezmoi/chezmoi.toml|~/.config/chezmoi/chezmoi.toml does not select host lab-ubuntu
configlink|name_copy && mv .config/chezmoi/chezmoi.toml .config/chezmoi/real.toml && ln -s real.toml .config/chezmoi/chezmoi.toml|~/.config/chezmoi/chezmoi.toml is missing, a link or not a regular file
maintenance|name_copy && : >.config/dotfiles/maintenance|~/.config/dotfiles/maintenance exists
nostate|name_copy && : >.local/state/chezmoi/chezmoi.boltdb|~/.local/state/chezmoi/chezmoi.boltdb is missing or empty
zshrc|name_copy && rm .zshrc && ln -s .config .zshrc|~/.zshrc is missing, a link or not a regular file
nocopy|name_copy && rm .local/state/dotfiles-fresh-backup/.bashrc|no byte-identical copy of ~/.bashrc in ~/.local/state/dotfiles-fresh-backup
changed|name_copy && printf 'edited\n' >.local/state/dotfiles-fresh-backup/.bashrc|no byte-identical copy of ~/.bashrc in ~/.local/state/dotfiles-fresh-backup
ROWS

# The clone-link audit: a relative and an absolute link into the clone, a
# link to a directory of it and a dangling one into it are reported; a link
# elsewhere, a link to a sibling whose name starts like the clone's, and a
# link inside the clone itself are not.
CL="$UNIT/cl home"
mkdir -p "$CL/dotfiles/home" "$CL/dotfiles-old" "$CL/.config"
: >"$CL/dotfiles/home/x"
: >"$CL/dotfiles-old/x"
ln -s ../dotfiles/home/x "$CL/.config/rel"
ln -s dotfiles/home/x "$CL/top"
ln -s "$CL/dotfiles/home/x" "$CL/abs"
ln -s dotfiles/home "$CL/dirlink"
ln -s dotfiles/missing "$CL/dangling"
ln -s /etc "$CL/other"
ln -s dotfiles-old/x "$CL/near"
ln -s home/x "$CL/dotfiles/inner"
cl_out=$(HOME=$CL E2E_CLONE=$CL/dotfiles E2E_SRC=$UNIT/no-src E2E_SNAPSHOT_PRUNE='' e2e_audit_clone_links) &&
    fail 'the clone-link audit passed a home with links into the clone'
expect_eq 'clone links found' "$(printf '%s\n' "$cl_out" | LC_ALL=C sort)" "$CL/.config/rel
$CL/abs
$CL/dangling
$CL/dirlink
$CL/top"
rm "$CL/.config/rel" "$CL/top" "$CL/abs" "$CL/dirlink" "$CL/dangling"
cl_out=$(HOME=$CL E2E_CLONE=$CL/dotfiles E2E_SRC=$UNIT/no-src E2E_SNAPSHOT_PRUNE='' e2e_audit_clone_links) ||
    fail "the clone-link audit failed a home without links into the clone: $cl_out"
expect_eq 'no clone links' "$cl_out" ''
printf 'ok: deploy end state and clone links\n'

# --- part two: the sandboxed dry run -------------------------------------

# The fixture source checkout: stubs for the entry points inside.sh drives,
# the chezmoi stub S4-chezmoi installs, the clone's own docs/bootstrap.md
# (home-deploy extracts the Fresh home by hand functions from it) and a
# .chezmoiroot. Three commits: the clean one, then two plants, each built on
# the clean files: a sudo in scripts/commands/doctor.sh outside any human phase, and a
# chezmoi whose first file apply also links a home path into the clone.
SRC="$TEST_TMP/src"
TEST_BIN="$TEST_TMP/bin"
mkdir -p "$SRC/docs" "$SRC/fixture" "$SRC/lib" "$SRC/scripts/commands" "$SRC/tests" "$SRC/home/dot_local/bin" "$TEST_BIN"
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
cp "$REPO_ROOT/dotfiles" "$SRC/dotfiles"
cp "$REPO_ROOT/home/dot_local/bin/executable_dotfiles" "$SRC/home/dot_local/bin/executable_dotfiles"
cp "$REPO_ROOT/docs/bootstrap.md" "$SRC/docs/bootstrap.md"
cp "$REPO_ROOT/lib/chezmoi-guard.sh" "$SRC/lib/chezmoi-guard.sh"
printf 'home\n' >"$SRC/.chezmoiroot"
write_chezmoi_stub "$SRC/fixture/chezmoi"

# The scripts/commands/setup.sh stub keeps the real one's shape: no mode flag
# (an unknown argument is exit 2), the root and WSL
# refusals (exit 2), plan lines, the HUMAN blocks with the real frames, the
# pending line on stderr and exit 3 while a blocking step is pending. Its
# state is what the blocks and the first apply leave behind: the apt marker the
# apt-get stub writes, ~/.local/bin/claude from the gated installer, the
# chezmoi it installs from the clone once claude is done (so one run applies
# that and leaves only H7-deploy), and the local config the fresh-home step
# leaves (the clone's guard accepts it as naming this home and the clone).
# --check writes nothing.
cat >"$SRC/scripts/commands/setup.sh" <<'SH'
#!/bin/bash
# e2e-harness fixture: a scripts/commands/setup.sh stand-in (see tests/e2e-harness.sh).
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
    printf '%s\n' '[dotfiles] [error] run ./dotfiles setup as your user, not root (no sudo); the sudo steps are printed as HUMAN blocks' >&2
    exit 2
fi
if [ -z "$host" ]; then
    printf '%s\n' "[dotfiles] [error] this home's ~/.config/chezmoi/chezmoi.toml selects [data].host generic (no host overlay); setup-host needs one: pass --host HOST" >&2
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
root=$(cd "$(dirname "$0")/../.." && pwd -P)
scratch=$HOME/.cache/dotfiles-bootstrap
installer=$scratch/claude/install.sh
if command -v sha256sum >/dev/null 2>&1; then
    verify='sha256sum -c --status -'
    digest() { sha256sum <"$1" | cut -d ' ' -f 1; }
else
    verify='shasum -a 256 -c --status -'
    digest() { shasum -a 256 <"$1" | cut -d ' ' -f 1; }
fi
apt_done=0 claude_done=0 omz=0 cz=0 deployed=0
[ ! -f "$scratch/apt-core.done" ] || apt_done=1
[ ! -x "$HOME/.local/bin/claude" ] || claude_done=1
[ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ] || omz=1
[ ! -x "$HOME/.local/bin/chezmoi" ] || cz=1
if [ ! -e "$HOME/.config/dotfiles/maintenance" ] &&
    [ "$(. "$root/lib/chezmoi-guard.sh" && dotfiles_chezmoi_source "$HOME")" = "$root" ]; then
    deployed=1
fi
held=''
printf 'P0-preflight done host %s, profile debian, checkout %s\n' "$host" "$root"
if [ "$apt_done" = 1 ]; then
    printf '%s\n' 'H1-apt-core done 1 apt package installed'
else
    printf '%s\n' 'H1-apt-core human missing apt packages: zsh'
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
if [ "$cz" = 1 ]; then
    printf 'S4-chezmoi done chezmoi 2.74.0 at %s/.local/bin/chezmoi\n' "$HOME"
elif [ "$apt_done" = 0 ]; then
    printf '%s\n' 'S4-chezmoi todo blocked by H1-apt-core: chezmoi is not installed'
elif [ "$claude_done" = 0 ]; then
    printf '%s\n' 'S4-chezmoi todo waiting for S5-claude (this stub): chezmoi is not installed'
elif [ "$mode" = apply ]; then
    mkdir -p "$HOME/.local/bin" && cp "$root/fixture/chezmoi" "$HOME/.local/bin/chezmoi" &&
        chmod 755 "$HOME/.local/bin/chezmoi" || exit 1
    printf '%s\n' 'S4-chezmoi done applied: install chezmoi 2.74.0'
else
    printf '%s\n' 'S4-chezmoi todo install chezmoi 2.74.0'
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
if [ "$deployed" = 1 ]; then
    printf '%s\n' 'H7-deploy done ~/.config/chezmoi/chezmoi.toml names this home and this checkout; configuration review remains an operator step'
else
    printf '%s\n' 'H7-deploy human follow Fresh home by hand in docs/bootstrap.md to initialize and deploy this home'
    held="$held${held:+ }H7-deploy"
fi
printf '%s\n' 'H7-auth human sign in to GitHub, Claude Code and Codex (not checked offline)' \
    'H7-doctor human the completion gate is ./dotfiles doctor --host lab-ubuntu'
if [ "$apt_done" = 0 ]; then
    printf '%s\n' 'HUMAN-BEGIN H1-apt-core sudo' '# docs/bootstrap.md H1-apt-core' 'sudo apt-get update' \
        'sudo apt-get install -y --no-install-recommends zsh' 'HUMAN-END'
elif [ "$claude_done" = 0 ]; then
    printf '%s\n' 'HUMAN-BEGIN S5-claude inspect' '# docs/bootstrap.md S5-claude'
    if [ -f "$installer" ]; then
        printf '# downloaded https://claude.ai/install.sh (unpinned vendor script) to %q\n' "$installer"
        printf '# sha256 %s, %s bytes; delete the file for a fresh copy\n' "$(digest "$installer")" "$(wc -c <"$installer" | tr -d ' ')"
        printf '%s\n' '# read it first; the line below runs it only while its sha256 is still the one above'
        printf "printf '%%s  %%s\\\\n' %s %q | %s && bash %q\\n" "$(digest "$installer")" "$installer" "$verify" "$installer"
    else
        printf '# ./dotfiles setup --host %s (without --check) downloads https://claude.ai/install.sh (unpinned)\n' "$host"
    fi
    printf '%s\n' '# ./dotfiles doctor then checks the installed claude against tools.tsv' 'HUMAN-END'
fi
if [ "$deployed" = 0 ]; then
    printf '%s\n' 'HUMAN-BEGIN H7-deploy judgment' '# docs/bootstrap.md H7-deploy' \
        '# Follow Fresh home by hand in docs/bootstrap.md from this checkout.' \
        "# Select local [data].host = $host explicitly; setup-host never initializes or applies configuration." 'HUMAN-END'
fi
printf '%s\n' 'HUMAN-BEGIN H7-auth auth' '# docs/bootstrap.md H7-auth' 'ssh-keygen -t ed25519' \
    'gh auth login --git-protocol ssh' 'HUMAN-END' 'HUMAN-BEGIN H7-doctor judgment' '# docs/bootstrap.md H7-doctor'
printf '%q doctor --host %s\n' "$root/dotfiles" "$host"
printf '%s\n' 'HUMAN-END'
if [ -n "$held" ]; then
    printf '[dotfiles] [warn] HUMAN steps pending: %s; run the HUMAN blocks above, then rerun ./dotfiles setup --host %s\n' "$held" "$host" >&2
    exit 3
fi
printf '[dotfiles] [ok] setup-host: nothing blocking remains for %s\n' "$host" >&2
exit 0
SH

# scripts/commands/doctor.sh: exit 1 until the gated installer ran and the home's chezmoi
# config names this checkout, 0 after; --tsv prints the five-column report, with a
# chezmoi-config row and a payloads row that is ok once the
# payloads-sync.sh stub ran; --smoke exits like a run. Any other argument
# is exit 2.
cat >"$SRC/scripts/commands/doctor.sh" <<'SH'
#!/bin/bash
# e2e-harness fixture: a scripts/commands/doctor.sh stand-in (see tests/e2e-harness.sh).
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
root=$(cd "$(dirname "$0")/../.." && pwd -P)
claude=missing deployed=human rc=1
[ ! -x "$HOME/.local/bin/claude" ] || claude=ok
if [ "$(. "$root/lib/chezmoi-guard.sh" && dotfiles_chezmoi_source "$HOME")" = "$root" ]; then
    deployed=ok
fi
[ "$claude" != ok ] || [ "$deployed" != ok ] || rc=0
if [ "$tsv" = 1 ]; then
    printf 'status\tid\ttier\tdetail\tfix\n'
    printf 'ok\tgit\tcore\t2.43.0\t-\n'
    printf '%s\tclaude\tai\t%s\tdocs/bootstrap.md S5-claude\n' "$claude" "$HOME/.local/bin/claude"
    printf '%s\tchezmoi-config\tcore\tconfig of %s\tdocs/bootstrap.md H7-deploy\n' "$deployed" "$HOME"
    if [ -f "$HOME/.local/share/e2e-payloads" ]; then
        printf 'ok\tpayloads\tai\tinstalled: kit, pymol, skills\t-\n'
    else
        printf 'warn\tpayloads\tai\tnot installed: kit, pymol, skills\tdocs/bootstrap.md H7-payloads\n'
    fi
else
    printf '[dotfiles] [ok] core git: 2.43.0\n'
    [ "$claude" = ok ] || printf '[dotfiles] [error] ai claude: missing (docs/bootstrap.md S5-claude)\n'
    [ "$deployed" = ok ] || printf '[dotfiles] [error] core chezmoi-config: no config of %s naming this checkout (docs/bootstrap.md H7-deploy)\n' "$HOME"
fi
exit "$rc"
SH

# scripts/commands/payloads-sync.sh: --now leaves the file the doctor stub's
# payloads row looks for, as the real installers leave their installs.
cat >"$SRC/scripts/commands/payloads-sync.sh" <<'SH'
#!/bin/sh
# e2e-harness fixture: a scripts/commands/payloads-sync.sh stand-in (see tests/e2e-harness.sh).
[ "$*" = --now ] || { printf '[dotfiles] [error] payload-update: unknown arguments: %s\n' "$*" >&2; exit 2; }
mkdir -p "$HOME/.local/share" && : >"$HOME/.local/share/e2e-payloads" || exit 1
printf '%s\n' 'payload-update: installed kit, pymol, skills'
SH
cat >"$SRC/tests/chezmoi.sh" <<'SH'
#!/bin/bash
set -eu
[ "$DOTFILES_TEST_REQUIRE_CHEZMOI" = 1 ]
[ "$DOTFILES_TEST_CHEZMOI" = "$HOME/.local/bin/chezmoi" ]
"$DOTFILES_TEST_CHEZMOI" --version
printf 'isolated chezmoi fixture entrypoint stand-in\n'
SH
chmod +x "$SRC/scripts/commands/setup.sh" "$SRC/scripts/commands/doctor.sh" "$SRC/scripts/commands/payloads-sync.sh"
git -C "$SRC" init -q
git -C "$SRC" add -A
git -C "$SRC" commit -q -m 'stubs'
REV_CLEAN=$(git -C "$SRC" rev-parse HEAD)
# plant FILE MARKER LINE MESSAGE: every stub as it is at REV_CLEAN, then the
# line of FILE that is exactly MARKER replaced by LINE, committed with
# MESSAGE; prints the new commit.
plant() {
    git -C "$SRC" checkout -q "$REV_CLEAN" -- scripts/commands/doctor.sh scripts/commands/setup.sh fixture/chezmoi
    E2E_PLANT_MARKER=$2 E2E_PLANT_LINE=$3 awk '
        $0 == ENVIRON["E2E_PLANT_MARKER"] { print ENVIRON["E2E_PLANT_LINE"]; found = 1; next }
        { print }
        END { if (!found) exit 1 }
    ' "$SRC/$1" >"$SRC/$1.new" || fail "the plant marker [$2] is not in $1"
    mv "$SRC/$1.new" "$SRC/$1"
    chmod +x "$SRC/$1"
    git -C "$SRC" commit -q -a -m "$4"
    git -C "$SRC" rev-parse HEAD
}
# The planted sudo runs on its own, in whatever phase scripts/commands/doctor.sh is called,
# but only through this test's stub (never a real sudo).
REV_PLANTED=$(plant scripts/commands/doctor.sh '# PLANT' "[ \"\$(command -v sudo)\" != '$TEST_BIN/sudo' ] || sudo -n true" 'plant a sudo in doctor.sh')
# shellcheck disable=SC2016 # the planted line expands in the stub, not here
REV_LINK=$(plant fixture/chezmoi '        # PLANT-LINK' '        [ -L "$home/.clone-link" ] || ln -s "$src/scripts/commands/setup.sh" "$home/.clone-link" || exit 1' 'plant a link into the clone')
if grep -F 'sudo -n true' "$SRC/scripts/commands/doctor.sh" >/dev/null; then
    fail 'the later plants did not restore the clean doctor.sh'
fi
[ -z "$(git -C "$SRC" status --porcelain)" ] || fail 'the fixture source is not clean after the plants'

# The stub wrappers, in the wrappers.log format of tests/e2e/wrappers: sudo
# logs and then runs the command itself (there is no root here), marking it
# for the setup-host stub's root refusal; chsh logs and succeeds; apt-get
# leaves the marker H1-apt-core waits for; zsh stands in for the login shell
# and runs -c commands through bash; chezmoi is the fixture's, so no chezmoi
# of the test machine is on PATH.
write_stub() {
    cat >"$TEST_BIN/$1"
    chmod +x "$TEST_BIN/$1"
}
for tool in sudo chsh; do
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
write_chezmoi_stub "$TEST_BIN/chezmoi"

# run_inside NAME REV HOME ENV...: inside.sh against the fixture at REV in
# the sandbox HOME (a path with a space) holding the /etc/skel .bashrc and
# .profile, with the stub bin first on PATH and the login zsh pointed at the
# stub. Sets RUN_RC.
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

# expect_one_fail NAME STEP TEXT: the run exited 1 and its only fail row is
# STEP, holding TEXT.
expect_one_fail() {
    expect_eq "$1 exit" "$RUN_RC" 1
    expect_step "$1" "$2" fail "$3"
    expect_eq "$1 fail count" "$(awk -F '\t' '$3 == "fail"' "$TEST_TMP/out-$1/summary.tsv" | grep -c .)" 1
}

# The clean run: every step passes, the reminders are skipped once, the
# apply loop ends in four runs with only H7-deploy left, the documented
# first apply converges, and the audits see only human and negative phases.
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
# Every step of the dry run went through the limit e2e_find_timeout picks on
# this PATH: coreutils timeout on Linux, tests/e2e/timeout.pl on the macOS
# runner (basenames: inside.sh resolves its own directory physically).
expected_timeout=$(PATH="$TEST_BIN:$PATH" e2e_find_timeout && printf '%s\n' "${E2E_TIMEOUT_BIN:-none}")
expect_eq 'clean env.txt names the timeout' "$(sed -n 's/^timeout=//p' "$CLEAN_OUT/env.txt" | sed 's|.*/||')" \
    "${expected_timeout##*/}"
CLEAN_PHYS=$(cd -P "$CLEAN_HOME" && pwd -P)
expect_text 'initial doctor uses the root CLI' "$CLEAN_OUT/steps/02-doctor-initial.log" './dotfiles doctor --host lab-ubuntu --tsv'
expect_text 'setup plan uses the root CLI' "$CLEAN_OUT/steps/03-check-nowrite.log" './dotfiles setup --host lab-ubuntu --check'
payload_log=$(printf '%s\n' "$CLEAN_OUT"/steps/*-payloads.log)
expect_text 'payloads use the installed CLI' "$payload_log" '.local/bin/dotfiles'
expect_text 'payloads select sync' "$payload_log" 'payloads\ sync'
expect_text 'payloads run outside the checkout' "$payload_log" "--- cwd $CLEAN_PHYS, phase setup:payloads"
[ -x "$CLEAN_HOME/.local/bin/dotfiles" ] && [ ! -L "$CLEAN_HOME/.local/bin/dotfiles" ] ||
    fail 'clean: the installed CLI is not an executable regular file'
cmp "$REPO_ROOT/home/dot_local/bin/executable_dotfiles" "$CLEAN_HOME/.local/bin/dotfiles" ||
    fail 'clean: the installed CLI differs from its source'
expect_step clean clone pass "at $CLEAN_HOME/dotfiles"
expect_step clean doctor-initial pass 'exit 1; '
expect_step clean doctor-initial pass 'no writes'
expect_step clean check-nowrite pass 'exit 3; 2 todo, 5 human; no writes'
expect_step clean apply-1 pass 'exit 3; blocks: H1-apt-core(sudo) H7-deploy(judgment) H7-auth(auth) H7-doctor(judgment); pending: H1-apt-core S5-claude H7-deploy'
expect_step clean H1-apt-core pass '2 line(s) run as printed (run-all)'
expect_step clean H7-auth skip 'auth block left to the person'
expect_step clean H7-doctor skip 'judgment block left to the person'
expect_step clean apply-2 pass 'exit 3; blocks: S5-claude(inspect) H7-deploy(judgment) H7-auth(auth) H7-doctor(judgment); pending: S5-claude H7-deploy'
expect_step clean S5-claude pass '1 line(s) run as printed (run-gate)'
expect_step clean apply-3 pass 'exit 3; applied 1 step(s); pending: H7-deploy'
expect_step clean apply-4 pass 'exit 3 after 4 run(s); only H7-deploy pending; blocks: H7-deploy(judgment) H7-auth(auth) H7-doctor(judgment)'
expect_step clean home-deploy pass "home_deploy lab-ubuntu exit 0; 2 earlier file(s) kept byte for byte; the config names $CLEAN_PHYS/dotfiles"
expect_step clean second-apply pass 'exit 0, nothing applied, HOME untouched'
expect_step clean check-done pass 'exit 0; nothing left to apply; no writes'
expect_step clean login-shell pass 'exit 0; silent'
expect_step clean payloads pass 'exit 0; doctor payloads ok: installed: kit, pymol, skills'
expect_step clean home-converged pass 'empty diff; 6 managed file(s), all regular'
expect_step clean doctor-final pass 'exit 0 from the login shell'
expect_step clean doctor-smoke pass 'exit 0 from the login shell'
expect_step clean negative-wsl-refused pass 'exit 2: '
expect_step clean negative-root-refused pass 'not root'
expect_step clean chezmoi-fixtures pass 'isolated chezmoi fixtures passed'
expect_step clean audit-wrappers pass '3 wrapper call(s), all in human or negative phases'
expect_step clean audit-sudo-log skip 'no log/sudo.log'
expect_step clean audit-clone-links pass 'no link under HOME leads into the clone'
expect_step clean audit-login-shell pass 'login shell still '
expect_step clean audit-rc-files pass 'human phases only'
expect_step clean rc-files note 'changed during human:H7-deploy: .bashrc .profile .zshrc'
[ "$(summary_rows clean apply-5)" = '' ] || fail 'clean: a fifth apply run happened'
# The steps run in the documented order.
expect_eq 'clean step order' "$(awk -F '\t' '$3 != "note" && $3 != "skip" { printf "%s ", $2 }' "$CLEAN_OUT/summary.tsv")" \
    'clone doctor-initial check-nowrite apply-1 H1-apt-core apply-2 S5-claude apply-3 apply-4 home-deploy second-apply check-done login-shell payloads home-converged doctor-final doctor-smoke negative-wsl-refused negative-root-refused chezmoi-fixtures audit-wrappers audit-clone-links audit-login-shell audit-rc-files '
# The wrappers.log holds the two apt sudos and the root-refused sudo,
# nothing else; the timeline frames each phase.
expect_eq 'clean wrappers.log' "$(cut -f 2,3 "$CLEAN_OUT/log/wrappers.log" | tr '\t' ' ')" 'human:H1-apt-core sudo
human:H1-apt-core sudo
negative:root-refused sudo'
expect_text 'clean wrappers.log argv' "$CLEAN_OUT/log/wrappers.log" "${TAB}-n ./dotfiles setup --host lab-ubuntu --check"
for phase in human:H1-apt-core human:S5-claude human:H7-deploy negative:wsl-refused negative:root-refused check:doctor-initial setup:apply-1 check:check-done check:home-converged; do
    expect_eq "clean timeline $phase" "$(awk -F '\t' -v p="$phase" '$3 == p { print $2 }' "$CLEAN_OUT/log/timeline" | tr '\n' ' ')" 'begin end '
done
awk -F '\t' '$3 ~ /^(human|negative):/ { if ($2 == "begin") b = $1; else if ($1 - b < 0) exit 1 }' "$CLEAN_OUT/log/timeline" ||
    fail 'clean: a timeline window ends before it begins'
# The home-deploy step's log starts with the H7-deploy block it stands in for.
expect_eq 'clean home-deploy log' "$(sed -n 1,2p "$CLEAN_OUT"/steps/*-home-deploy.log)" '--- block
# docs/bootstrap.md H7-deploy'
# The outputs the contract names, and what the run left in the home.
expect_text 'clean env.txt' "$CLEAN_OUT/env.txt" 'host=lab-ubuntu flow=unix profile=debian mode=sandbox'
[ -f "$CLEAN_OUT/steps/01-clone.log" ] || fail 'clean: no steps/01-clone.log'
[ -f "$CLEAN_OUT/steps/04-apply-1.blocks/1.block" ] || fail 'clean: the apply-1 blocks were not kept'
[ -f "$CLEAN_OUT/snapshots/doctor-initial.newer" ] || fail 'clean: no doctor-initial snapshot'
[ ! -s "$CLEAN_OUT/snapshots/doctor-initial.newer" ] || fail "clean: doctor-initial wrote in HOME: $(cat "$CLEAN_OUT/snapshots/doctor-initial.newer")"
[ -f "$CLEAN_OUT/snapshots/check-done.newer" ] && [ ! -s "$CLEAN_OUT/snapshots/check-done.newer" ] ||
    fail 'clean: check-done has no empty no-write snapshot'
expect_eq 'clean: the config names the clone' \
    "$(. "$REPO_ROOT/lib/chezmoi-guard.sh" && dotfiles_chezmoi_source "$CLEAN_HOME")" "$CLEAN_PHYS/dotfiles"
[ ! -e "$CLEAN_HOME/.config/dotfiles" ] || fail 'clean: the fresh-home step created ~/.config/dotfiles'
[ -f "$CLEAN_HOME/.zshrc" ] && [ ! -L "$CLEAN_HOME/.zshrc" ] || fail 'clean: ~/.zshrc is not a regular file'
for rel in .bashrc .profile; do
    expect_eq "clean kept $rel" "$(cat "$CLEAN_HOME/.local/state/dotfiles-fresh-backup/$rel")" '# /etc/skel'
done
[ ! -e "$CLEAN_HOME/.config/dotfiles/maintenance" ] || fail 'clean: the first apply left maintenance'
[ -x "$CLEAN_HOME/.local/bin/claude" ] || fail 'clean: the gated installer did not run'
[ -x "$CLEAN_HOME/.local/bin/chezmoi" ] || fail 'clean: chezmoi was not provisioned'
[ -f "$CLEAN_HOME/.cache/dotfiles-bootstrap/apt-core.done" ] || fail 'clean: the apt block did not run through the sudo stub'
[ -z "$(git -C "$SRC" status --porcelain)" ] || fail 'clean: the source checkout changed'
[ -z "$(git -C "$CLEAN_HOME/dotfiles" status --porcelain --untracked-files=all)" ] || fail 'clean: the clone is not clean'
expect_eq 'clean clone rev' "$(git -C "$CLEAN_HOME/dotfiles" rev-parse HEAD)" "$REV_CLEAN"
expect_text 'clean log' "$TEST_TMP/clean.err" 'pass, 0 fail,'
printf 'ok: sandboxed dry run (clean fixture)\n'

# The planted runs, without negatives: each passes every step but one
# audit. The sudo scripts/commands/doctor.sh made under check:doctor-initial fails the
# wrappers audit; the link the first file apply made fails the clone-link
# audit.
run_inside planted "$REV_PLANTED" "$TEST_TMP/home planted" E2E_NEGATIVE=
expect_one_fail planted audit-wrappers ' check:doctor-initial sudo '
expect_step planted doctor-initial pass 'exit 1; '
expect_step planted home-deploy pass 'home_deploy lab-ubuntu exit 0'
[ "$(summary_rows planted negative-wsl-refused)" = '' ] || fail 'planted: a negative ran although E2E_NEGATIVE was empty'
expect_eq 'planted clone rev' "$(git -C "$TEST_TMP/home planted/dotfiles" rev-parse HEAD)" "$REV_PLANTED"
printf 'ok: sandboxed dry run (planted sudo fails the wrappers audit)\n'

run_inside link "$REV_LINK" "$TEST_TMP/home link" E2E_NEGATIVE=
expect_one_fail link audit-clone-links "$TEST_TMP/home link/.clone-link"
expect_step link home-converged pass 'empty diff; 6 managed file(s), all regular'
[ -L "$TEST_TMP/home link/.clone-link" ] || fail 'link: the planted link is missing'
printf 'ok: sandboxed dry run (a link into the clone fails its audit)\n'

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
# The sandbox seam relocates HOME only, so it drives nothing but a fixture
# under the temp dir with stub tools: this repository as E2E_SRC is refused
# (unless the checkout itself sits under the temp dir), and so is a PATH
# whose sudo, chsh or chezmoi is the machine's own (a real chezmoi would
# deploy into the sandbox home for real).
TMP_ROOT=$(cd -- "${TMPDIR:-/tmp}" && pwd -P)
case $REPO_ROOT in
    "$TMP_ROOT"/*) printf 'SKIP: the real-checkout refusal (this checkout lies under %s).\n' "$TMP_ROOT" ;;
    *)
        refused src-outside-tmp E2E_SANDBOX_HOME="$TEST_TMP/home src" E2E_SRC="$REPO_ROOT" \
            E2E_REV="$(git -C "$REPO_ROOT" rev-parse HEAD)" E2E_ALLOW_DIRTY=1
        expect_text 'src-outside-tmp' "$TEST_TMP/src-outside-tmp.err" 'drives only a fixture checkout under the temp dir'
        expect_text 'src-outside-tmp names the checkout' "$TEST_TMP/src-outside-tmp.err" "E2E_SRC is $REPO_ROOT"
        ;;
esac
REAL_TOOL=''
for tool in sudo chsh chezmoi; do
    found=$(command -v "$tool" 2>/dev/null) || continue
    case $(cd -- "$(dirname -- "$found")" && pwd -P) in
        "$TMP_ROOT"/*) ;;
        *)
            REAL_TOOL=$tool
            break
            ;;
    esac
done
if [ -n "$REAL_TOOL" ]; then
    refused real-tool E2E_SANDBOX_HOME="$TEST_TMP/home tool" PATH="$PATH"
    expect_text 'real-tool' "$TEST_TMP/real-tool.err" "runs only with stub tools under the temp dir $TMP_ROOT; $REAL_TOOL on PATH is "
else
    printf 'SKIP: the real-tool refusal (no sudo, chsh or chezmoi outside %s on PATH).\n' "$TMP_ROOT"
fi
# A chezmoi of the machine behind stub sudo and chsh is refused by name.
REAL_CHEZMOI=$(command -v chezmoi 2>/dev/null) || REAL_CHEZMOI=''
REAL_CHEZMOI_DIR=''
[ -z "$REAL_CHEZMOI" ] || REAL_CHEZMOI_DIR=$(cd -- "$(dirname -- "$REAL_CHEZMOI")" && pwd -P)
case $REAL_CHEZMOI_DIR in
    '' | "$TMP_ROOT"/*) printf 'SKIP: the real-chezmoi refusal (no chezmoi outside %s on PATH).\n' "$TMP_ROOT" ;;
    *)
        mkdir -p "$TEST_TMP/stubs-only"
        cp "$TEST_BIN/sudo" "$TEST_BIN/chsh" "$TEST_TMP/stubs-only/"
        refused real-chezmoi E2E_SANDBOX_HOME="$TEST_TMP/home chezmoi" \
            PATH="$TEST_TMP/stubs-only:$REAL_CHEZMOI_DIR:/usr/bin:/bin"
        expect_text 'real-chezmoi' "$TEST_TMP/real-chezmoi.err" "; chezmoi on PATH is $REAL_CHEZMOI_DIR/chezmoi"
        ;;
esac
if [ ! -f /.dockerenv ] && [ ! -f /run/.containerenv ] && [ "$(uname -s)" != Darwin ]; then
    # Without a seam, a workstation run is refused before it can touch HOME.
    refused no-seam E2E_NATIVE=1
    expect_text 'no-seam' "$TEST_TMP/no-seam.err" 'refusing to run outside a container'
fi
printf 'ok: refusals exit 2 before any step\n'

printf 'e2e-harness: %ss\n' "$(($(date +%s) - STARTED))"
echo "e2e-harness=PASS"
