# Dependencies and lighter packaging

Shell and PowerShell remain the orchestration languages. The structured merge
backend is deliberately small; no general application framework is involved.

## Current requirements

| Use | Requirements |
| --- | --- |
| Unix installation | Bash, Git, GNU Stow (and its Perl runtime), ordinary POSIX utilities |
| Native Windows installation | PowerShell 7+, Git for Windows / Git Bash, elevated symlink creation |
| All three AI sync helpers | Python 3.11+; no package installation during login or stow |
| Codex TOML merge | Exact `tomlkit` pin in `requirements-sync.txt` |
| Claude JSON / Codex rules alone | Python standard library only, via an explicitly selected interpreter |
| Default parser setup | Python's `venv` and pip support; downloads the pinned wheel unless pre-provisioned offline |
| Claude customization hooks | Node.js 22+ (18 and 20 are end of life); independent of configuration-file merging |
| Optional skill downloads | Bash, curl, tar, rsync |
| Contributor checks | pre-commit, Node, Python/parser runtime; pinned lint tools; Stow integration; PowerShell required on Windows CI |
| Day-zero bootstrap | `doctor.sh` and `setup-host.sh`: Bash 3.2+, git, curl and ordinary POSIX utilities; `doctor.ps1` and `setup-host.ps1`: PowerShell 7+ and winget. Everything they install is listed in `config/bootstrap/`, downloads sha256-pinned and clones on their upstream default branch (see [Day-zero tools](#day-zero-tools) and [bootstrap.md](bootstrap.md)); the manifest validator under `tests/` also needs Python 3 |

The configured applications (Zsh, Vim, terminals, Codex, Claude, etc.) are needed
to use their respective settings, not all to copy or symlink the repository.
There is no global Node/npm dependency for the AI merge backend. `jq`, `uv`,
`yq`, `jaq`, and `dasel` are not required by that backend either.

## Is a venv necessary?

No: [venv](https://docs.python.org/3/library/venv.html) provides package isolation;
it is not needed to execute Python. The current `setup-sync` scripts deliberately
use a checkout-local `.venv-sync` to avoid changing system/conda environments.
Nothing needs activating. A prepared Python executable can instead be selected
with `DOTFILES_SYNC_PYTHON`; its visible packages must satisfy the helper being
run. Copying a venv between devices is not supported: recreate it on each host.

## Alternatives investigated (2026-09-05)

| Option | Removes per-host venv setup? | Limitation for this repository |
| --- | --- | --- |
| Existing Python + stdlib | Yes | JSON and opaque rules work; [`tomllib`](https://docs.python.org/3/library/tomllib.html) reads TOML but cannot write it |
| [`jq`](https://jqlang.org/manual/) / PowerShell JSON commands | Yes for JSON | Do not solve comment-preserving TOML edits; splitting engines adds platform behavior to maintain |
| Standalone [`jaq`](https://github.com/01mf02/jaq) | Yes | TOML round-trip loses comments; its [manual](https://gedenkt.at/jaq/manual/#toml) excludes date-time values |
| [`dasel`](https://github.com/TomWright/dasel) | Yes | Multi-format executable worth evaluating, but lossless TOML and this repo's preservation contract are not verified |
| [`uv run`](https://docs.astral.sh/uv/guides/scripts/) | Hides management | Still provisions an environment/cache and adds uv; unsuitable for implicit login-time downloads |
| Bundle pinned tomlkit source, or a [zipapp](https://docs.python.org/3/library/zipapp.html) | Yes | Still requires Python; repository must own parser licensing, pin updates and packaging tests |

A local probe of official jaq 3.1.1 with `--from toml --to toml` dropped both
standalone and trailing comments after a one-key edit; an RFC 3339 date-time
value failed to parse. It is not a drop-in replacement for preserving arbitrary
live TOML state. These observations concern that tested release, not all tools.

The most promising smaller deployment is to bundle the pinned, pure-Python
[TOMLKit](https://tomlkit.readthedocs.io/en/latest/) parser, retaining its
[MIT license](https://github.com/python-poetry/tomlkit/blob/master/LICENSE).
The installed 0.15.1 package measured about 197 KiB of source excluding bytecode;
this host's complete `.venv-sync` occupied about 15 MiB. These are local size
measurements, not cross-platform guarantees. Bundling would remove pip/venv
provisioning per device while preserving one merge implementation, but would
not remove the Python interpreter dependency.

That packaging change is a separate decision and is **not implemented** here.
The current change only removes the unnecessary tomlkit requirement from
standalone JSON/rules operations. No AWK/regex TOML writer or hidden dependency
download has been introduced.

## Day-zero tools

[`config/bootstrap/tools.tsv`](../config/bootstrap/tools.tsv) is the source of
truth for what `doctor.sh` and `doctor.ps1` check; these tables mirror it for
reading and add where each platform gets the tool. Tiers `core`, `cli` and `ai`
are required by default; `desktop`, `contributor` and `host` are reported only
(`--tier all` makes them required). [bootstrap.md](bootstrap.md) has the step
for every row. `unix` means every host except `win`; the Ubuntu/WSL column
covers `wsl-ubuntu` and `lab-ubuntu` unless a cell names one.

How to read a cell:

- `brew X` / `cask X`: an entry in the tier's Brewfile in
  [`config/bootstrap/brew/`](../config/bootstrap/brew/) (`cask` is macOS only).
- `apt X`: a package in [`config/bootstrap/apt/`](../config/bootstrap/apt/),
  installed by the `H1-apt-core` sudo block.
- `login env X`: a dependency in
  [`hpc-login-env.yml`](../config/bootstrap/hpc-login-env.yml).
- `winget X`: a package in [`winget.json`](../config/bootstrap/winget.json).
- `clone`: a row of [`git-clones.tsv`](../config/bootstrap/git-clones.tsv): a
  shallow clone of the upstream default branch, which setup-host never
  updates.
- `pinned X`: a row of [`installers.tsv`](../config/bootstrap/installers.tsv)
  (URL plus sha256; `inspect` rows have no digest).
- `manual`: nothing in `config/bootstrap/` installs it there: the OS baseline,
  a module, a vendor installer or a person (`# manual:` declarations in
  `tools.tsv`). `-`: not checked on that platform.

Version floors (the `floor` column, compared with the first `X.Y[.Z]` the tool
prints) appear at the start of the When absent cell.

### Core tier

| Tool | Hosts | macOS | Ubuntu/WSL | Sherlock/Marlowe | Windows | When absent |
| --- | --- | --- | --- | --- | --- | --- |
| `git` | all | manual (Xcode CLT) | apt `git` | login env `git` | winget `Git.Git` | cannot clone, update or stow the dotfiles |
| `bash` | unix | manual (OS) | manual (OS) | manual (OS) | - | doctor.sh, setup-host.sh and stow-all.sh cannot run |
| `zsh` | unix | manual (OS) | apt `zsh` | login env `zsh` | - | no interactive shell for the stowed .zshrc |
| `git-lfs` | unix | brew `git-lfs` | apt `git-lfs` | login env `git-lfs` | - | the required lfs filter in .gitconfig fails on LFS repositories |
| `curl` | unix | manual (OS) | apt `curl` | login env `curl` | - | setup-host downloads and the awesome-skills sync fail |
| `rsync` | unix | manual (OS) | apt `rsync` | login env `rsync` | - | upload and the awesome-skills sync fail |
| `tar` | unix | manual (OS) | apt `tar` | manual (OS) | - | archive installs and the targz aliases fail |
| `file` | unix | manual (OS) | apt `file` | login env `file` | - | fzf previews cannot detect file types |
| `col` | unix | manual (OS) | apt `bsdextrautils` | manual (OS) | - | fzf-tab man page previews fail |
| `man` | unix | manual (OS) | apt `man-db` | manual (OS) | - | man, colored-man-pages and fzf-tab man previews fail |
| `tmux` | unix | brew `tmux` | apt `tmux` | login env `tmux` | - | fzf --tmux popups and tmux sessions are unavailable |
| `homebrew` | mac | pinned `homebrew` (sudo) | - | - | - | Brewfile bundles cannot run |
| `linuxbrew` | wsl-ubuntu, lab-ubuntu | - | pinned `homebrew` (sudo) | - | - | Brewfile bundles cannot run and the overlay brew shellenv line fails |
| `python3` | all | brew `python` | apt `python3`, brew `python` | login env `python` | winget `Python.Python.3.12` | >= 3.11. setup-sync and the AI config sync helpers cannot run |
| `stow` | unix | brew `stow` | brew `stow` | login env `stow` | - | >= 2.3.1. stow-all.sh refuses to run |
| `fzf` | all | brew `fzf` | brew `fzf` | login env `fzf` | winget `junegunn.fzf` | >= 0.58.0. Ctrl-R/T, Alt-C and fzf-tab fail |
| `zoxide` | all | brew `zoxide` | brew `zoxide` | login env `zoxide` | winget `ajeetdsouza.zoxide` | z and zi are not defined |
| `eza` | all | brew `eza` | brew `eza` | login env `eza` | winget `eza-community.eza` | >= 0.18.20. ll, la and fzf directory previews fail |
| `fd` | all | brew `fd` | brew `fd` | login env `fd-find` | winget `sharkdp.fd` | >= 8.3.0. fzf Ctrl-T and Alt-C list nothing |
| `bat` | all | brew `bat` | brew `bat` | login env `bat` | winget `sharkdp.bat` | fzf previews fall back to plain text |
| `oh-my-zsh` | unix | clone | clone | clone | - | zsh aborts where .zshrc sources oh-my-zsh.sh |
| `powerlevel10k` | unix | clone | clone | clone | - | oh-my-zsh cannot find the prompt theme |
| `fzf-tab` | unix | clone | clone | clone | - | plugin fzf-tab not found, plain tab completion |
| `fast-syntax-highlighting` | unix | clone | clone | clone | - | plugin fast-syntax-highlighting not found, no highlighting |
| `zsh-autosuggestions` | unix | clone | clone | clone | - | plugin zsh-autosuggestions not found, no suggestions |
| `you-should-use` | unix | clone | clone | clone | - | plugin you-should-use not found, no alias reminders |
| `conda-zsh-completion` | unix | clone | clone | clone | - | plugin conda-zsh-completion not found, no conda completion |
| `zsh-completions` | unix | clone | clone | clone | - | the extra completion functions on fpath are missing |
| `bat-theme` | all | pinned `bat-theme` | pinned `bat-theme` | pinned `bat-theme` | pinned `bat-theme` | BAT_THEME Catppuccin Mocha is unknown to bat |
| `micromamba` | sherlock, marlowe | - | - | pinned `micromamba` | - | the login env cannot be created or updated |
| `login-env` | sherlock, marlowe | - | - | `hpc-login-env.yml` (env `login`) | - | ssh sherlock and ssh marlowe cannot exec the login zsh |
| `pwsh` | win | - | - | - | winget `Microsoft.PowerShell` | >= 7.0. the PowerShell 7 profile and doctor.ps1 cannot run |

### CLI tier

| Tool | Hosts | macOS | Ubuntu/WSL | Sherlock/Marlowe | Windows | When absent |
| --- | --- | --- | --- | --- | --- | --- |
| `ripgrep` | all | brew `ripgrep` | brew `ripgrep` | login env `ripgrep` | winget `BurntSushi.ripgrep.MSVC` | rg searches fail |
| `git-delta` | all | brew `git-delta` | brew `git-delta` | login env `git-delta` | winget `dandavison.delta` | fzf-tab git diff and show previews are empty |
| `tldr` | all | brew `tldr` (the C client) | brew `tldr` (the C client) | login env `tealdeer` | winget `tldr-pages.tlrc` | fzf-tab command and tldr previews fall back to man |
| `chafa` | unix | brew `chafa` | brew `chafa` | login env `chafa` | - | fzf image previews outside kitty show only file details |
| `jq` | all | brew `jq` | brew `jq` | login env `jq` | winget `jqlang.jq` | JSON filtering on the command line fails |
| `nvim` | all | brew `neovim` | brew `neovim` | login env `nvim` | winget `Neovim.Neovim` | the vi alias fails |
| `aria2` | all | brew `aria2` | brew `aria2` | login env `aria2` | winget `aria2.aria2` | aria2c downloads with the stowed aria2.conf fail |
| `uv` | all | brew `uv` | brew `uv` | login env `uv` | winget `astral-sh.uv` | uv and the oh-my-zsh uv plugin are unavailable |
| `gh` | all | brew `gh` | brew `gh` (on lab-ubuntu also git's github.com credential helper, by full path) | login env `gh` | winget `GitHub.cli` | >= 2.50.0. gh auth git-credential and GitHub CLI workflows fail |
| `xclip` | lab-ubuntu | - | lab-ubuntu: apt `xclip` | - | - | fzf Ctrl-Y cannot copy to the X clipboard |
| `wl-clipboard` | lab-ubuntu | - | lab-ubuntu: apt `wl-clipboard` | - | - | no clipboard copy from Wayland sessions |

### AI tier

| Tool | Hosts | macOS | Ubuntu/WSL | Sherlock/Marlowe | Windows | When absent |
| --- | --- | --- | --- | --- | --- | --- |
| `nvm` | mac, wsl-ubuntu, lab-ubuntu | pinned `nvm` | pinned `nvm` | - | - | no default node on PATH and no nvm function |
| `node` | all | nvm `lts/*` | nvm `lts/*` | marlowe: login env `nodejs`; sherlock: Lmod `nodejs/24.13.0` | winget `OpenJS.NodeJS.LTS` | >= 22.0. Claude hooks and the status line fail |
| `claude` | mac, wsl-ubuntu, lab-ubuntu, win | cask `claude-code` | pinned `claude` (inspect) | not checked: optional site module (`ml spider claude-code`) | winget `Anthropic.ClaudeCode` | Claude Code is unavailable |
| `codex` | mac, wsl-ubuntu, lab-ubuntu, win | cask `codex` | pinned `codex` (codex-package) | not checked: optional site module (`ml spider codex`) | winget `OpenAI.Codex` | Codex is unavailable |

Opt-in, outside every tier: the pinned Sherlock toolkit (`shk`), which the
global agent instructions name for work on or connections to Sherlock. Neither
`./setup-host.sh` nor the doctor touches it; on a host where agents work with
Sherlock, run `./setup-sherlock-kit.sh` explicitly, then
`./stow-all.sh <host>`, which links the `shk` launcher. On Windows run
`./setup-sherlock-kit.ps1 -Python python`, which also writes the native
`~/.local/bin/shk.cmd`, then the normal `./stow-all.ps1 win`. See the README's
Pinned Sherlock toolkit section and [sherlock-kit.md](sherlock-kit.md).

### Desktop tier

| Tool | Hosts | macOS | Ubuntu/WSL | Sherlock/Marlowe | Windows | When absent |
| --- | --- | --- | --- | --- | --- | --- |
| `kitty` | mac, lab-ubuntu | cask `kitty` | lab-ubuntu: pinned `kitty` | - | - | the stowed kitty.conf has no terminal to configure |
| `wezterm` | mac, win | cask `wezterm` | - | - | winget `wez.wezterm` | the stowed .wezterm.lua has no terminal to configure |
| `nerd-font` | mac, lab-ubuntu, win | cask `font-caskaydia-mono-nerd-font` | lab-ubuntu: pinned `nerd-font` | - | `oh-my-posh font install CascadiaMono` | prompt, eza and terminal icons render as boxes |
| `windows-terminal` | win | - | - | - | winget `Microsoft.WindowsTerminal` | the stowed Windows Terminal settings are unused |
| `oh-my-posh` | win | - | - | - | winget `JanDeDobbeleer.OhMyPosh` | the default PowerShell prompt replaces the tracked theme |
| `psfzf` | win | - | - | - | `Install-PSResource PSFzf` | Ctrl+R, Ctrl+T and Alt+C keep PSReadLine defaults |
| `completionpredictor` | win | - | - | - | `Install-PSResource CompletionPredictor` | predictions come from history only |
| `commandnotfound` | win | - | - | - | `Install-PSResource Microsoft.WinGet.CommandNotFound` | no winget suggestions for unknown commands |

### Contributor tier

| Tool | Hosts | macOS | Ubuntu/WSL | Sherlock/Marlowe | Windows | When absent |
| --- | --- | --- | --- | --- | --- | --- |
| `pre-commit` | all | brew `pre-commit` | brew `pre-commit` | login env `pre-commit` | manual (`uv tool install pre-commit`) | pre-commit run --all-files cannot run |
| `shfmt` | unix | brew `shfmt` | brew `shfmt` | login env `go-shfmt` | - | >= 3.13.0. manual shfmt runs miss the zsh dialect |
| `shellcheck` | unix | brew `shellcheck` | brew `shellcheck` | login env `shellcheck` | - | manual shellcheck runs fail |
| `stylua` | unix | brew `stylua` | brew `stylua` | manual | - | manual Lua formatting of .wezterm.lua fails |

### Host tier

Reported, never installed (except micromamba and the `login` env on hpc, which
are in the core tier above). Each is installed by its vendor or site at the
path its row probes.

| Tool | Hosts | macOS | Ubuntu/WSL | Sherlock/Marlowe | Windows | When absent |
| --- | --- | --- | --- | --- | --- | --- |
| `miniconda` | mac, wsl-ubuntu, sherlock, marlowe | manual (`~/miniconda3`) | wsl-ubuntu: manual (`~/miniconda3`) | manual (`~/miniconda3`) | - | the overlay conda and mamba hooks fall back to a dead PATH entry |
| `miniconda-apps` | lab-ubuntu | - | lab-ubuntu: manual (shared `/apps/miniconda3`) | - | - | the overlay conda and mamba hooks fall back to a dead PATH entry |
| `miniconda-win` | win | - | - | - | manual (`~\miniconda3`) | the lazy conda stub in profile.ps1 is not defined |
| `juliaup` | wsl-ubuntu | - | wsl-ubuntu: manual (`~/.juliaup`) | - | - | the juliaup PATH entry in the wsl profile is dead |
| `texlive-2024` | wsl-ubuntu | - | wsl-ubuntu: manual (TeX Live 2024 in `/usr/local/texlive`) | - | - | the TeX Live 2024 PATH, MANPATH and INFOPATH entries are dead |
| `texlive-2025` | lab-ubuntu | - | lab-ubuntu: manual (TeX Live 2025 in `/usr/local/texlive`) | - | - | the TeX Live 2025 PATH, MANPATH and INFOPATH entries are dead |
| `gromacs` | wsl-ubuntu | - | wsl-ubuntu: manual (`/usr/local/gromacs`) | - | - | gmx and its completion are not set up |
| `gromacs-apps` | lab-ubuntu | - | lab-ubuntu: manual (shared `/apps/gromacs-2026.0`) | - | - | gmx and its completion are not set up |
| `cuda` | wsl-ubuntu, lab-ubuntu | - | manual (NVIDIA toolkit in `/usr/local/cuda`) | - | - | nvcc and the CUDA PATH entry are absent |
| `matlab` | mac | manual (MATLAB R2025b) | - | - | - | MATLAB is not exported |
| `schrodinger` | mac | manual (Schrodinger 2025-2) | - | - | - | SCHRODINGER is not exported |
| `fcitx5` | lab-ubuntu | - | lab-ubuntu: apt fcitx5 set, then `im-config -n fcitx5` | - | - | no input method, and the stowed fcitx5 profile is unused |
| `wslu` | wsl-ubuntu | - | wsl-ubuntu: apt `wslu` | - | - | BROWSER=wslview cannot open links |
| `notify-send` | wsl-ubuntu, lab-ubuntu | - | wsl-ubuntu: apt `libnotify-bin`; lab-ubuntu: desktop default | - | - | the alert alias fails |
| `kinit` | mac, wsl-ubuntu, lab-ubuntu | manual (OS) | manual (Kerberos client) | - | - | GSSAPI ssh to sherlock and marlowe cannot use Kerberos tickets |
| `gcm` | lab-ubuntu | - | lab-ubuntu: manual (Git Credential Manager) | - | - | the credential helper in .gitconfig_local fails |
| `gcm-windows` | wsl-ubuntu | - | wsl-ubuntu: manual (Git for Windows on the Windows side) | - | - | the Windows credential helper in .gitconfig_local fails |
| `gpg` | lab-ubuntu | - | lab-ubuntu: apt `gnupg` | - | - | the GCM gpg credential store and the gpg-agent plugin fail |
| `pass` | lab-ubuntu | - | lab-ubuntu: manual | - | - | the GCM gpg credential store cannot save secrets |
| `tailscale` | mac, wsl-ubuntu, lab-ubuntu | manual | manual | - | - | the oh-my-zsh tailscale plugin does nothing |
| `lmod` | sherlock, marlowe | - | - | manual (site Lmod) | - | ml and module are undefined, so overlay module loads are skipped |

### Windows interactive tools

The PowerShell 7 profile uses its tools only when they are already installed:
executables are probed on `PATH`, PSFzf by looking for a `PSFzf` directory in
each `PSModulePath` entry, and CompletionPredictor and
Microsoft.WinGet.CommandNotFound are imported on the first idle tick (a missing
module is silent; one that is installed but fails to import warns once).
`setup-host.ps1` installs them explicitly; profiles, stow and automatic updates
never install them. Where the Windows profile degrades differently from the
Unix rows above: without eza, `ll` and `la` fall back to `Get-ChildItem`;
without bat, `BAT_THEME` is not set; the profile does not use fd; without
oh-my-posh the prompt is the default `PS>`.

oh-my-posh 31 is an MSIX package. Upgrading from a 29.x installer requires
`winget uninstall` first. The MSIX package can also update itself through App
Installer; the theme's `$schema` pin moves with the installed release.

### Not managed here

Third-party plugins enabled in `common/claude/.claude/settings.json` can need
runtimes of their own that `config/bootstrap/` does not install or check: the
`telegram` plugin runs under bun, and the `*-lsp` plugins (TypeScript, Pyright,
rust-analyzer, clangd, Lua) need their language servers on PATH. Install those
per host if you use them; a missing one disables only that plugin.
