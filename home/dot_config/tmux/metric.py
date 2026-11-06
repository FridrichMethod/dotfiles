"""Forward tmux-cpu metrics with its cache inside a private directory."""

import os
from pathlib import Path
import stat
import subprocess
import sys


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("cpu", "ram"):
        return
    home = Path.home()
    script = home / ".tmux/plugins/tmux-cpu/scripts" / f"{sys.argv[1]}_percentage.sh"
    if not script.is_file():
        return
    uid = os.geteuid()
    cache = home / ".cache/tmux-metrics"
    for directory, forbidden in (
        (cache.parent, 0o022),
        (cache, 0o077),
        (cache / f"tmux-{uid}-cpu", 0o077),
    ):
        directory.mkdir(mode=0o700, exist_ok=True)
        info = directory.lstat()
        if (not stat.S_ISDIR(info.st_mode) or info.st_uid != uid
                or info.st_mode & forbidden):
            return
    env = dict(os.environ, TMPDIR=str(cache))
    subprocess.run([str(script)], env=env, stderr=subprocess.DEVNULL, check=False)


try:
    main()
except OSError:
    pass
