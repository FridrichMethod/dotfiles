# Dependencies

Shell and PowerShell remain the entrypoint languages. Native configuration
deployment uses chezmoi 2.74.0 or newer.

## Current requirements

| Use | Requirements |
| --- | --- |
| Native Unix installation | chezmoi 2.74.0+, Git, shell and ordinary POSIX utilities; no sync venv |
| Native Windows installation | chezmoi 2.74.0+, PowerShell 7+, Git; ordinary file updates are unelevated |
| Claude customization hooks | Node.js 22+ (18 and 20 are end of life); independent of configuration-file merging |
| Payload repos ([payloads.md](payloads.md)) | `scripts/payload-update.*`, which `sync-payloads` runs: POSIX `sh` and curl, or wget plus an existing timeout/gtimeout on Unix, PowerShell 7 on Windows; then what each repository's installer needs, which its README lists (Git for the kit's managed install, on Unix only since the kit installs nothing on native Windows, and for awesome-skills) |
| Contributor checks | pre-commit, Node, Python 3.11+; pinned lint tools; PowerShell required on Windows CI; Docker for the opt-in end-to-end bootstrap suite (`tests/e2e/run.sh`, see [testing.md](testing.md#end-to-end-bootstrap-opt-in)) |
| Day-zero bootstrap | `doctor.sh` and `setup-host.sh`: Bash 3.2+, git, curl and ordinary POSIX utilities; `doctor.ps1` and `setup-host.ps1`: PowerShell 7+ and winget. Everything they install is listed in `config/bootstrap/`, downloads sha256-pinned and clones on their upstream default branch (see [Day-zero tools](#day-zero-tools) and [bootstrap.md](bootstrap.md)); the manifest validator under `tests/` also needs Python 3 |

The configured applications (Zsh, Vim, terminals, Codex, Claude, etc.) are needed
to use their respective settings, not all to deploy the repository. The native
Claude and Codex merges run inside chezmoi: no Node/npm, `jq`, `uv`, `yq`, `jaq`
or `dasel` is required for them.

## Day-zero tools

[`config/bootstrap/tools.tsv`](../config/bootstrap/tools.tsv) is the source of
truth for what `doctor.sh` and `doctor.ps1` check; the compact tables below describe the
impact of missing tools without duplicating provider inventories. Tiers `core`, `cli` and `ai`
are required by default; `desktop`, `contributor` and `host` are reported only
(`--tier all` makes them required). [bootstrap.md](bootstrap.md) has the step
for every row. `unix` means every host except `win`.

For platform/provider/package mappings and version floors, read the manifests
instead of a second copied inventory:

- [tools.tsv](../config/bootstrap/tools.tsv): host applicability, tiers, probes,
  floors, absence messages and step IDs; `# alias:` and `# manual:` declarations.
- [Brewfiles](../config/bootstrap/brew/) and [apt lists](../config/bootstrap/apt/).
- [HPC environment](../config/bootstrap/hpc-login-env.yml) and
  [Windows packages](../config/bootstrap/winget.json).
- [Installers](../config/bootstrap/installers.tsv) and
  [clone branches](../config/bootstrap/git-clones.tsv).

S2-brew-bundle skips a package when the doctor's probe already finds its tool,
including an apt/conda/OS copy. The tables below retain tool IDs and the impact
of missing them; manifest parity tests require every ID to remain documented.

### Core tier

| Tool | Hosts | When absent |
| --- | --- | --- |
| `git` | all | cannot clone or update the dotfiles |
| `chezmoi` | all | native configuration deployment needs 2.74.0+; setup steps S4-chezmoi / W1-chezmoi provision it explicitly |
| `bash` | unix | doctor.sh and setup-host.sh cannot run |
| `zsh` | unix | no interactive shell for the dotfiles .zshrc |
| `git-lfs` | unix | the required lfs filter in .gitconfig fails on LFS repositories |
| `curl` | unix | setup-host downloads fail, and the payload hook needs wget instead |
| `rsync` | unix | upload fails |
| `tar` | unix | archive installs and the targz aliases fail |
| `file` | unix | fzf previews cannot detect file types |
| `col` | unix | fzf-tab man page previews fail |
| `man` | unix | man, colored-man-pages and fzf-tab man previews fail |
| `tmux` | unix | tmux 3.4+ hostname-scoped recovery configuration and sessions are unavailable |
| `homebrew` | mac | Brewfile bundles cannot run |
| `linuxbrew` | wsl-ubuntu, lab-ubuntu | Brewfile bundles cannot run and the overlay brew shellenv line fails |
| `python3` | all | Python helpers cannot run |
| `fzf` | all | Ctrl-R/T, Alt-C and fzf-tab fail |
| `zoxide` | all | z and zi are not defined |
| `eza` | all | ll, la and fzf directory previews fail |
| `fd` | all | fzf Ctrl-T and Alt-C list nothing |
| `bat` | all | fzf previews fall back to plain text |
| `oh-my-zsh` | unix | zsh aborts where .zshrc sources oh-my-zsh.sh |
| `powerlevel10k` | unix | oh-my-zsh cannot find the prompt theme |
| `fzf-tab` | unix | plugin fzf-tab not found, plain tab completion |
| `fast-syntax-highlighting` | unix | plugin fast-syntax-highlighting not found, no highlighting |
| `zsh-autosuggestions` | unix | plugin zsh-autosuggestions not found, no suggestions |
| `you-should-use` | unix | plugin you-should-use not found, no alias reminders |
| `conda-zsh-completion` | unix | plugin conda-zsh-completion not found, no conda completion |
| `zsh-completions` | unix | the extra completion functions on fpath are missing |
| `tpm` | unix | tmux plugins are not loaded (native tmux still works) |
| `tmux-resurrect` | unix | tmux layouts cannot be saved or restored |
| `tmux-fzf` | unix | prefix F has no tmux search menu |
| `catppuccin-tmux` | unix | modern tmux windows use the native Mocha fallback theme |
| `extrakto` | unix | prefix Tab cannot extract paths and text from pane output |
| `tmux-yank` | unix | desktop copy mode lacks clipboard helpers |
| `tmux-floax` | unix | modern tmux has no persistent floating scratch terminal |
| `tmux-which-key` | unix | upstream which-key menu defaults are unavailable |
| `tmux-cpu` | unix | tmux status cannot display CPU and RAM percentages |
| `tmux-battery` | unix | tmux status cannot display battery charge on a laptop |
| `tmux-continuum` | unix | tmux layouts are not saved or restored automatically |
| `bat-theme` | all | BAT_THEME Catppuccin Mocha is unknown to bat |
| `micromamba` | sherlock, marlowe | the login env cannot be created or updated |
| `login-env` | sherlock, marlowe | ssh sherlock and ssh marlowe cannot exec the login zsh |
| `pwsh` | win | the PowerShell 7 profile and doctor.ps1 cannot run |

### CLI tier

| Tool | Hosts | When absent |
| --- | --- | --- |
| `ripgrep` | all | rg searches fail |
| `git-delta` | all | fzf-tab git diff and show previews are empty |
| `tldr` | all | fzf-tab command and tldr previews fall back to man |
| `chafa` | unix | fzf image previews outside kitty show only file details |
| `jq` | all | JSON filtering on the command line fails |
| `nvim` | all | the vi alias fails |
| `aria2` | all | aria2c downloads with the dotfiles aria2.conf fail |
| `uv` | all | uv and the oh-my-zsh uv plugin are unavailable |
| `gh` | all | gh auth git-credential and GitHub CLI workflows fail |
| `gh-linuxbrew` | lab-ubuntu | GitHub/Gist credential helpers call this exact executable, including GUI Git |
| `xclip` | lab-ubuntu | fzf Ctrl-Y cannot copy to the X clipboard |
| `wl-clipboard` | lab-ubuntu | no clipboard copy from Wayland sessions |
| `make` | win | make targets in project Makefiles cannot run |

### AI tier

| Tool | Hosts | When absent |
| --- | --- | --- |
| `nvm` | mac, wsl-ubuntu, lab-ubuntu | no default node on PATH and no nvm function |
| `node` | all | Claude hooks and the status line fail |
| `claude` | mac, wsl-ubuntu, lab-ubuntu, win | Claude Code is unavailable |
| `codex` | mac, wsl-ubuntu, lab-ubuntu, win | Codex is unavailable |

The Sherlock toolkit is installed and pinned by consumer projects from its
[standalone repository](https://github.com/FridrichMethod/sherlock-kit).
Dotfiles does not install `shk`, toolkit rules or skills. See
[sherlock-kit.md](sherlock-kit.md) for migration of older hosts.

### Desktop tier

| Tool | Hosts | When absent |
| --- | --- | --- |
| `kitty` | mac, lab-ubuntu | the dotfiles kitty.conf has no terminal to configure |
| `wezterm` | mac, win | the dotfiles .wezterm.lua has no terminal to configure |
| `nerd-font` | mac, lab-ubuntu, win | prompt, eza and terminal icons render as boxes |
| `windows-terminal` | win | the dotfiles Windows Terminal settings are unused |
| `oh-my-posh` | win | the default PowerShell prompt replaces the tracked theme |
| `psfzf` | win | Ctrl+R, Ctrl+T and Alt+C keep PSReadLine defaults |
| `completionpredictor` | win | predictions come from history only |
| `commandnotfound` | win | no winget suggestions for unknown commands |

### Contributor tier

| Tool | Hosts | When absent |
| --- | --- | --- |
| `pre-commit` | all | pre-commit run --all-files cannot run |
| `shfmt` | unix | manual shfmt runs miss the zsh dialect |
| `shellcheck` | unix | manual shellcheck runs fail |
| `stylua` | unix | manual Lua formatting of .wezterm.lua fails |

### Host tier

Reported, never installed (except micromamba and the `login` env on hpc, which
are in the core tier above). Each is installed by its vendor or site at the
path its row probes.

| Tool | Hosts | When absent |
| --- | --- | --- |
| `miniconda` | mac, wsl-ubuntu, sherlock, marlowe | the overlay conda and mamba hooks fall back to a dead PATH entry |
| `miniconda-apps` | lab-ubuntu | the overlay conda and mamba hooks fall back to a dead PATH entry |
| `miniconda-win` | win | the lazy conda stub in profile.ps1 is not defined |
| `juliaup` | wsl-ubuntu | the juliaup PATH entry in the wsl profile is dead |
| `texlive-2024` | wsl-ubuntu | the TeX Live 2024 PATH, MANPATH and INFOPATH entries are dead |
| `texlive-2025` | lab-ubuntu | the TeX Live 2025 PATH, MANPATH and INFOPATH entries are dead |
| `gromacs` | wsl-ubuntu | gmx and its completion are not set up |
| `gromacs-apps` | lab-ubuntu | gmx and its completion are not set up |
| `cuda` | wsl-ubuntu, lab-ubuntu | nvcc and the CUDA PATH entry are absent |
| `matlab` | mac | MATLAB is not exported |
| `schrodinger` | mac | SCHRODINGER is not exported |
| `fcitx5` | lab-ubuntu | no input method, and the dotfiles fcitx5 profile is unused |
| `wslu` | wsl-ubuntu | BROWSER=wslview cannot open links |
| `notify-send` | wsl-ubuntu, lab-ubuntu | the alert alias fails |
| `kinit` | mac, wsl-ubuntu, lab-ubuntu | GSSAPI ssh to sherlock and marlowe cannot use Kerberos tickets |
| `gcm` | lab-ubuntu | the credential helper in .gitconfig_local fails |
| `gcm-windows` | wsl-ubuntu | the Windows credential helper in .gitconfig_local fails |
| `gpg` | lab-ubuntu | the GCM gpg credential store and the gpg-agent plugin fail |
| `pass` | lab-ubuntu | the GCM gpg credential store cannot save secrets |
| `tailscale` | mac, wsl-ubuntu, lab-ubuntu | the oh-my-zsh tailscale plugin does nothing |
| `lmod` | sherlock, marlowe | ml and module are undefined, so overlay module loads are skipped |

### Windows interactive tools

The PowerShell 7 profile uses its tools only when they are already installed:
executables are probed on `PATH`, PSFzf by looking for a `PSFzf` directory in
each `PSModulePath` entry, and CompletionPredictor and
Microsoft.WinGet.CommandNotFound are imported on the first idle tick (a missing
module is silent; one that is installed but fails to import warns once).
`setup-host.ps1` installs them explicitly; profiles, automatic updates
and the payload hook never install them. Where the Windows profile degrades differently from the
Unix rows above: without eza, `ll` and `la` fall back to `Get-ChildItem`;
without bat, `BAT_THEME` is not set; the profile does not use fd; without
oh-my-posh the prompt is the default `PS>`.

oh-my-posh 31 is an MSIX package. Upgrading from a 29.x installer requires
`winget uninstall` first. The MSIX package can also update itself through App
Installer; the theme's `$schema` pin moves with the installed release.

### Not managed here

Third-party plugins enabled in `home/.policy/claude-settings.json` can need
runtimes of their own that `config/bootstrap/` does not install or check: the
`telegram` plugin runs under bun, and the `*-lsp` plugins (TypeScript, Pyright,
rust-analyzer, clangd, Lua) need their language servers on PATH. Install those
per host if you use them; a missing one disables only that plugin.
