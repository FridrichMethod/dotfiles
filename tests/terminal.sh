#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export TERMINAL_LIB="$REPO_ROOT/lib/terminal.sh"

# A real PTY is needed to distinguish redirected stdout from terminal stderr.
# No live dotfiles are installed and no non-standard Python package is used.
python3 - <<'PY'
import errno
import os
import subprocess

SCRIPT = r'''
before_flags=$-
before_umask=$(umask)
. "$TERMINAL_LIB"
[ "$-" = "$before_flags" ]
[ "$(umask)" = "$before_umask" ]
dotfiles_log step 'Preparing 100% of selected files'
dotfiles_log ok 'Configuration applied'
dotfiles_log info 'Details remain plain'
dotfiles_log warn 'Local edits retained'
dotfiles_log error 'Configuration invalid'
'''
ESC = b'\x1b['


def run(*, stdout_tty=False, stderr_tty=False, overrides=None):
    env = dict(os.environ)
    for key in ('DOTFILES_COLOR', 'NO_COLOR', 'TERM'):
        env.pop(key, None)
    env['TERM'] = 'xterm-256color'
    env.update(overrides or {})
    master = slave = None
    if stdout_tty or stderr_tty:
        master, slave = os.openpty()
    try:
        process = subprocess.Popen(
            ['sh', '-eu', '-c', SCRIPT], env=env,
            stdout=slave if stdout_tty else subprocess.PIPE,
            stderr=slave if stderr_tty else subprocess.PIPE,
        )
        if slave is not None:
            os.close(slave)
            slave = None
        try:
            stdout, stderr = process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate()
            raise
        assert process.returncode == 0, (stdout, stderr)
        terminal = b''
        if master is not None:
            while True:
                try:
                    chunk = os.read(master, 4096)
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
                if not chunk:
                    break
                terminal += chunk
        return (terminal if stdout_tty else stdout,
                terminal if stderr_tty else stderr)
    finally:
        for descriptor in (master, slave):
            if descriptor is not None:
                os.close(descriptor)


stdout, stderr = run()
assert ESC not in stdout + stderr
assert b'[dotfiles] [step] Preparing 100% of selected files' in stdout
assert b'[dotfiles] [ok] Configuration applied' in stdout
assert b'[dotfiles] [info] Details remain plain' in stdout
assert b'[dotfiles] [warn] Local edits retained' in stderr
assert b'[dotfiles] [error] Configuration invalid' in stderr
assert b'[warn]' not in stdout and b'[error]' not in stdout

stdout, stderr = run(stdout_tty=True)
assert b'\x1b[1;36m[dotfiles] [step]' in stdout
assert b'\x1b[32m[dotfiles] [ok]' in stdout
assert ESC not in stderr

stdout, stderr = run(stderr_tty=True)
assert ESC not in stdout
assert b'\x1b[33m[dotfiles] [warn]' in stderr
assert b'\x1b[31m[dotfiles] [error]' in stderr

stdout, stderr = run(overrides={'DOTFILES_COLOR': 'always'})
assert ESC in stdout and ESC in stderr
assert b'\x1b[0m' in stdout and b'\x1b[0m' in stderr

for settings in (
    {'DOTFILES_COLOR': 'never'},
    {'DOTFILES_COLOR': 'always', 'NO_COLOR': '1'},
    {'DOTFILES_COLOR': 'always', 'NO_COLOR': '0'},
    {'DOTFILES_COLOR': 'always', 'TERM': 'dumb'},
):
    stdout, stderr = run(stdout_tty=True, stderr_tty=True, overrides=settings)
    assert ESC not in stdout + stderr, settings

stdout, stderr = run(overrides={'DOTFILES_COLOR': 'always', 'NO_COLOR': ''})
assert ESC in stdout and ESC in stderr
for mode in ('', 'invalid'):
    stdout, stderr = run(overrides={'DOTFILES_COLOR': mode})
    assert ESC not in stdout + stderr
    stdout, stderr = run(stdout_tty=True, overrides={'DOTFILES_COLOR': mode})
    assert ESC in stdout and ESC not in stderr

result = subprocess.run(['sh', '-eu', '-c', '. "$TERMINAL_LIB"'],
                        capture_output=True, check=True)
assert result.stdout == result.stderr == b''
print('terminal-output=PASS (TTY streams, overrides, plain logs, silent sourcing)')
PY
