"""Small real-chezmoi fixture shared by isolated native behavior tests."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class ChezmoiFixture:
    """Keep native source, destination and all user state in one temporary root."""

    def __init__(self):
        explicit = os.environ.get("DOTFILES_TEST_CHEZMOI")
        if explicit is not None:
            binary = Path(explicit).resolve() if explicit else None
            if binary is None or not binary.is_file() or not os.access(binary, os.X_OK):
                raise RuntimeError("chezmoi prerequisite: DOTFILES_TEST_CHEZMOI must name an executable file")
        else:
            selected = shutil.which("chezmoi")
            if selected is None:
                message = "chezmoi prerequisite: select DOTFILES_TEST_CHEZMOI or install chezmoi on PATH"
                if os.environ.get("DOTFILES_TEST_REQUIRE_CHEZMOI") == "1":
                    raise RuntimeError(message)
                raise unittest.SkipTest(message)
            binary = Path(selected).resolve()
        self.binary = binary

    def __enter__(self):
        self._temporary = tempfile.TemporaryDirectory(prefix="dotfiles chezmoi ")
        self.root = Path(self._temporary.name).resolve()
        self.source = self.root / "source state"
        self.destination = self.root / "destination home"
        self.config = self.root / "configuration/chezmoi.toml"
        self.cache = self.root / "cache"
        self.state = self.root / "state/chezmoi.boltdb"
        directories = {
            "HOME": self.root / "home",
            "USERPROFILE": self.root / "home",
            "XDG_CONFIG_HOME": self.root / "xdg/config",
            "XDG_CACHE_HOME": self.root / "xdg/cache",
            "XDG_DATA_HOME": self.root / "xdg/data",
            "XDG_STATE_HOME": self.root / "xdg/state",
            "XDG_RUNTIME_DIR": self.root / "xdg/runtime",
            "APPDATA": self.root / "appdata/roaming",
            "LOCALAPPDATA": self.root / "appdata/local",
            "TMPDIR": self.root / "temporary files",
            "TMP": self.root / "temporary files",
            "TEMP": self.root / "temporary files",
            "PATH": self.root / "empty-bin",
        }
        for directory in (*directories.values(), self.source, self.destination, self.cache,
                          self.config.parent, self.state.parent):
            directory.mkdir(parents=True, exist_ok=True)
        self.config.write_text("", encoding="utf-8")
        # Keep only OS/locale essentials: no inherited credentials, agent,
        # proxy, Git or chezmoi overrides. Consumers may add deliberate inputs.
        essentials = {"SYSTEMROOT", "WINDIR", "COMSPEC", "PATHEXT", "SYSTEMDRIVE",
                      "LANG", "LANGUAGE", "TZ"}
        self.env = {key: value for key, value in os.environ.items()
                    if key.upper() in essentials or key.upper().startswith("LC_")}
        self.env.update({key: str(value) for key, value in directories.items()})
        self.env.update(TERM="dumb", NO_COLOR="1", GH_TELEMETRY="0", TLDR_AUTO_UPDATE_DISABLED="1")
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self._temporary.cleanup()

    def run(self, *args: str, input: str | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(self.binary), "--source", str(self.source),
             "--destination", str(self.destination), "--config", str(self.config),
             "--cache", str(self.cache), "--persistent-state", str(self.state),
             "--no-tty", "--error-on-conflict", "--no-pager", "--use-builtin-diff", *args],
            input=input, text=True, encoding="utf-8", capture_output=True,
            cwd=self.root, env=self.env, timeout=30, check=False,
            **({"stdin": subprocess.DEVNULL} if input is None else {}),
        )
