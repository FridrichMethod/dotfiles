#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export TERMINAL_LIB="$REPO_ROOT/lib/terminal.sh"

# A real PTY is needed to distinguish redirected stdout from terminal stderr.
# No live dotfiles are installed and no non-standard Python package is used.
python3 - <<'PY'
import errno
import os
import selectors
import shutil
import subprocess
import sys
import time

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


def run(*, stdout_tty=False, stderr_tty=False, overrides=None, command=None, timeout=10):
    env = dict(os.environ)
    for key in ('DOTFILES_COLOR', 'NO_COLOR', 'TERM'):
        env.pop(key, None)
    env['TERM'] = 'xterm-256color'
    env.update(overrides or {})
    master = slave = None
    process = None
    if stdout_tty or stderr_tty:
        master, slave = os.openpty()
    try:
        process = subprocess.Popen(
            command or ['sh', '-eu', '-c', SCRIPT], env=env,
            stdout=slave if stdout_tty else subprocess.PIPE,
            stderr=slave if stderr_tty else subprocess.PIPE,
        )
        # Keep the parent's slave open until output is drained: macOS may
        # discard unread PTY bytes when the last slave closes. Multiplex all
        # three streams while the child runs so no pipe/PTY buffer can fill.
        chunks = {'terminal': [], 'stdout': [], 'stderr': []}
        deadline = time.monotonic() + timeout
        with selectors.DefaultSelector() as selector:
            for descriptor, name in ((master, 'terminal'),
                                     (process.stdout, 'stdout'),
                                     (process.stderr, 'stderr')):
                if descriptor is not None:
                    fd = descriptor if isinstance(descriptor, int) else descriptor.fileno()
                    os.set_blocking(fd, False)
                    selector.register(descriptor, selectors.EVENT_READ, name)
            while True:
                if time.monotonic() >= deadline:
                    raise subprocess.TimeoutExpired(process.args, timeout)
                child_exited = process.poll() is not None
                events = selector.select(timeout=0.1)
                for key, _ in events:
                    try:
                        chunk = os.read(key.fd, 4096)
                    except BlockingIOError:
                        continue
                    except OSError as error:
                        if key.data != 'terminal' or error.errno != errno.EIO:
                            raise
                        chunk = b''
                    if chunk:
                        chunks[key.data].append(chunk)
                    else:
                        selector.unregister(key.fileobj)
                if child_exited and not events:
                    break
        terminal, stdout, stderr = (b''.join(chunks[name])
                                    for name in ('terminal', 'stdout', 'stderr'))
        assert process.returncode == 0, (terminal, stdout, stderr)
        return (terminal if stdout_tty else stdout,
                terminal if stderr_tty else stderr)
    finally:
        if process is not None:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            for stream in (process.stdout, process.stderr):
                if stream is not None:
                    stream.close()
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
assert b'\x1b[1;36m[dotfiles] [step]' in stdout, (stdout, stderr)
assert b'\x1b[32m[dotfiles] [ok]' in stdout, (stdout, stderr)
assert ESC not in stderr, (stdout, stderr)

stdout, stderr = run(stderr_tty=True)
assert ESC not in stdout, (stdout, stderr)
assert b'\x1b[33m[dotfiles] [warn]' in stderr, (stdout, stderr)
assert b'\x1b[31m[dotfiles] [error]' in stderr, (stdout, stderr)

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

# Prove the harness drains PTY and pipe output concurrently, beyond their
# kernel buffer sizes, without dropping a short-lived child's trailing bytes.
stdout, stderr = run(stdout_tty=True, command=[
    sys.executable, '-c',
    "import sys; sys.stdout.buffer.write(b'x' * 131072); sys.stderr.buffer.write(b'y' * 131072)",
])
assert stdout == b'x' * 131072 and stderr == b'y' * 131072, (len(stdout), len(stderr))
print('terminal-output=PASS (TTY streams, overrides, plain logs, silent sourcing)')

# PowerShell's *> redirects streams without redirecting the process console.
# Exercise that distinction on an actual PTY, including OutputRendering=Ansi;
# the ordinary pipe-based PowerShell run cannot cover this branch by itself.
power_shell = shutil.which('pwsh')
if power_shell:
    suite = os.path.join(os.path.dirname(os.environ['TERMINAL_LIB']), '..', 'tests', 'terminal.ps1')
    stdout, stderr = run(stdout_tty=True, timeout=60, command=[
        power_shell, '-NoProfile', '-NonInteractive', '-File', suite,
    ])
    assert b'same-session-console-redirected=False' in stdout, (stdout, stderr)
    assert b'powershell-terminal=PASS' in stdout, (stdout, stderr)
    print('powershell-terminal-pty=PASS (real console with PowerShell stream redirection)')
else:
    print('SKIP: PowerShell real-PTY output tests (pwsh unavailable)')
PY
