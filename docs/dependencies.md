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
| Claude customization hooks | Node.js; independent of configuration-file merging |
| Optional skill downloads | Bash, curl, tar, rsync |
| Contributor checks | pre-commit, Node, Python/parser runtime; pinned lint tools; Stow integration; PowerShell required on Windows CI |

The configured applications (Zsh, Vim, terminals, Codex, Claude, etc.) are needed
to use their respective settings, not all to copy or symlink the repository.
There is no global Node/npm dependency for the AI merge backend. `jq`, `uv`,
`yq`, `jaq`, and `dasel` are not required by that backend either.

## Optional Windows interactive tools

The PowerShell 7 profile uses these tools only when they are already installed:
executables are probed on `PATH`, PSFzf by looking for a `PSFzf` directory in
each `PSModulePath` entry, and CompletionPredictor and
Microsoft.WinGet.CommandNotFound are imported on the first idle tick (a missing
module is silent; one that is installed but fails to import warns once).
Install them by hand; profiles, stow and automatic updates never install them.

| Tool | Install | Used for | When absent |
| --- | --- | --- | --- |
| oh-my-posh | `winget install --id JanDeDobbeleer.OhMyPosh -e` | prompt (`win/oh-my-posh` theme) | default `PS>` prompt |
| CaskaydiaMono Nerd Font | `oh-my-posh font install CascadiaMono` | Windows Terminal, WezTerm and Kitty glyphs | missing icons |
| CompletionPredictor | `Install-PSResource CompletionPredictor -Scope CurrentUser` | list-view predictions from completions | history-only predictions |
| fzf + PSFzf | `winget install --id junegunn.fzf -e`; `Install-PSResource PSFzf -Scope CurrentUser` | Ctrl+R, Ctrl+T, Alt+C | PSReadLine defaults |
| zoxide | `winget install --id ajeetdsouza.zoxide -e` | `z` / `zi` directory jumping | not defined |
| eza | `winget install --id eza-community.eza -e` | `ll` / `la` | `Get-ChildItem` |
| bat | `winget install --id sharkdp.bat -e` | `BAT_THEME` (Catppuccin Mocha) | not set |
| fd | `winget install --id sharkdp.fd -e` | standalone `fd`; the profile does not use it | none |

oh-my-posh 31 is an MSIX package. Upgrading from a 29.x installer requires
`winget uninstall` first. The MSIX package can also update itself through App
Installer; the theme's `$schema` pin moves with the installed release.

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

`config/bootstrap/tools.tsv` is the source of truth for what `doctor.sh`
checks; this table mirrors it for reading. Tiers `core`, `cli` and `ai` are
required by default; `desktop`, `contributor` and `host` are reported only.
`unix` means every host except `win`.

| Tool | Tier | Hosts | What breaks when absent |
| --- | --- | --- | --- |
| `git` | core | all | cannot clone, update or stow the dotfiles |
| `bash` | core | unix | doctor.sh, setup-host.sh and stow-all.sh cannot run |
| `zsh` | core | unix | no interactive shell for the stowed .zshrc |
| `git-lfs` | core | unix | the required lfs filter in .gitconfig fails on LFS repositories |
| `curl` | core | unix | setup-host downloads and the awesome-skills sync fail |
| `rsync` | core | unix | upload and the awesome-skills sync fail |
| `tar` | core | unix | archive installs and the targz aliases fail |
| `file` | core | unix | fzf previews cannot detect file types |
| `col` | core | unix | fzf-tab man page previews fail |
| `man` | core | unix | man, colored-man-pages and fzf-tab man previews fail |
| `tmux` | core | unix | fzf --tmux popups and tmux sessions are unavailable |
| `homebrew` | core | mac | Brewfile bundles cannot run |
| `linuxbrew` | core | wsl-ubuntu, lab-ubuntu | Brewfile bundles cannot run and the overlay brew shellenv line fails |
| `python3` | core | all | setup-sync and the AI config sync helpers cannot run |
| `stow` | core | unix | stow-all.sh refuses to run |
| `fzf` | core | all | Ctrl-R/T, Alt-C and fzf-tab fail |
| `zoxide` | core | all | z and zi are not defined |
| `eza` | core | all | ll, la and fzf directory previews fail |
| `fd` | core | all | fzf Ctrl-T and Alt-C list nothing |
| `bat` | core | all | fzf previews fall back to plain text |
| `oh-my-zsh` | core | unix | zsh aborts where .zshrc sources oh-my-zsh.sh |
| `powerlevel10k` | core | unix | oh-my-zsh cannot find the prompt theme |
| `fzf-tab` | core | unix | plugin fzf-tab not found, plain tab completion |
| `fast-syntax-highlighting` | core | unix | plugin fast-syntax-highlighting not found, no highlighting |
| `zsh-autosuggestions` | core | unix | plugin zsh-autosuggestions not found, no suggestions |
| `you-should-use` | core | unix | plugin you-should-use not found, no alias reminders |
| `conda-zsh-completion` | core | unix | plugin conda-zsh-completion not found, no conda completion |
| `zsh-completions` | core | unix | the extra completion functions on fpath are missing |
| `bat-theme` | core | all | BAT_THEME Catppuccin Mocha is unknown to bat |
| `micromamba` | core | sherlock, marlowe | the login env cannot be created or updated |
| `login-env` | core | sherlock, marlowe | ssh sherlock and ssh marlowe cannot exec the login zsh |
| `pwsh` | core | win | the PowerShell 7 profile and doctor.ps1 cannot run |
| `ripgrep` | cli | all | rg searches fail |
| `git-delta` | cli | all | fzf-tab git diff and show previews are empty |
| `tldr` | cli | all | fzf-tab command and tldr previews fall back to man |
| `chafa` | cli | unix | fzf image previews outside kitty show only file details |
| `jq` | cli | all | JSON filtering on the command line fails |
| `nvim` | cli | all | the vi alias fails |
| `aria2` | cli | all | aria2c downloads with the stowed aria2.conf fail |
| `uv` | cli | all | uv and the oh-my-zsh uv plugin are unavailable |
| `gh` | cli | all | gh auth git-credential and GitHub CLI workflows fail |
| `gh-apt` | cli | lab-ubuntu | the github.com credential helper in .gitconfig_local fails |
| `xclip` | cli | lab-ubuntu | fzf Ctrl-Y cannot copy to the X clipboard |
| `wl-clipboard` | cli | lab-ubuntu | no clipboard copy from Wayland sessions |
| `nvm` | ai | mac, wsl-ubuntu, lab-ubuntu | no default node on PATH and no nvm function |
| `node` | ai | all | Claude hooks and the status line fail |
| `claude` | ai | all | Claude Code is unavailable |
| `codex` | ai | all | Codex is unavailable |
| `bubblewrap` | ai | wsl-ubuntu, lab-ubuntu | the Codex Linux sandbox cannot start |
| `kitty` | desktop | mac, lab-ubuntu | the stowed kitty.conf has no terminal to configure |
| `wezterm` | desktop | mac, win | the stowed .wezterm.lua has no terminal to configure |
| `nerd-font` | desktop | mac, lab-ubuntu, win | prompt, eza and terminal icons render as boxes |
| `windows-terminal` | desktop | win | the stowed Windows Terminal settings are unused |
| `oh-my-posh` | desktop | win | the default PowerShell prompt replaces the tracked theme |
| `psfzf` | desktop | win | Ctrl+R, Ctrl+T and Alt+C keep PSReadLine defaults |
| `completionpredictor` | desktop | win | predictions come from history only |
| `commandnotfound` | desktop | win | no winget suggestions for unknown commands |
| `pre-commit` | contributor | all | pre-commit run --all-files cannot run |
| `shfmt` | contributor | unix | manual shfmt runs miss the zsh dialect |
| `shellcheck` | contributor | unix | manual shellcheck runs fail |
| `stylua` | contributor | unix | manual Lua formatting of .wezterm.lua fails |
| `miniconda` | host | mac, wsl-ubuntu, sherlock, marlowe | the overlay conda and mamba hooks fall back to a dead PATH entry |
| `miniconda-apps` | host | lab-ubuntu | the overlay conda and mamba hooks fall back to a dead PATH entry |
| `miniconda-win` | host | win | the lazy conda stub in profile.ps1 is not defined |
| `juliaup` | host | wsl-ubuntu | the juliaup PATH entry in the wsl profile is dead |
| `texlive-2024` | host | wsl-ubuntu | the TeX Live 2024 PATH, MANPATH and INFOPATH entries are dead |
| `texlive-2025` | host | lab-ubuntu | the TeX Live 2025 PATH, MANPATH and INFOPATH entries are dead |
| `gromacs` | host | wsl-ubuntu | gmx and its completion are not set up |
| `gromacs-apps` | host | lab-ubuntu | gmx and its completion are not set up |
| `cuda` | host | wsl-ubuntu, lab-ubuntu | nvcc and the CUDA PATH entry are absent |
| `matlab` | host | mac | MATLAB is not exported |
| `schrodinger` | host | mac | SCHRODINGER is not exported |
| `fcitx5` | host | lab-ubuntu | no input method, and the stowed fcitx5 profile is unused |
| `wslu` | host | wsl-ubuntu | BROWSER=wslview cannot open links |
| `notify-send` | host | wsl-ubuntu, lab-ubuntu | the alert alias fails |
| `kinit` | host | mac, wsl-ubuntu, lab-ubuntu | GSSAPI ssh to sherlock and marlowe cannot use Kerberos tickets |
| `gcm` | host | lab-ubuntu | the credential helper in .gitconfig_local fails |
| `gcm-windows` | host | wsl-ubuntu | the Windows credential helper in .gitconfig_local fails |
| `gpg` | host | lab-ubuntu | the GCM gpg credential store and the gpg-agent plugin fail |
| `pass` | host | lab-ubuntu | the GCM gpg credential store cannot save secrets |
| `tailscale` | host | mac, wsl-ubuntu, lab-ubuntu | the oh-my-zsh tailscale plugin does nothing |
| `lmod` | host | sherlock, marlowe | ml and module are undefined, so overlay module loads are skipped |
