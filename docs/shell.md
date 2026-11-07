# Shell startup and host behavior

## Unix startup

The shared profile owns HOME/bin and HOME/.local/bin, locale, MANPATH (including
man's default search path), nvm discovery and host login configuration. Bash
loads it from .bashrc; zsh sources it immediately after its uniqueness setup.
Host aliases and profile files live under ~/.config/sh/. Preserve shared site
prefixes such as /apps/miniconda3; per-user conda and Juliaup paths use HOME.
The vi alias selects nvim only when available, leaving native vi usable otherwise.
An interactive login updates only a home bound by ~/.config/dotfiles/native
([update contract](update-contract.md)); an unmarked home runs nothing.

nvm discovery honors an explicit NVM_DIR, then ~/.nvm, then
${XDG_CONFIG_HOME:-~/.config}/nvm. The profile reads default-alias chains with the read builtin without
sourcing nvm.sh, supporting installed exact/partial versions and node/stable;
relative lts/-N aliases stay unresolved. It avoids incomplete installations and
alias cycles. The zsh custom file loads nvm.sh --no-use and completion. There
are no lazy node/npm wrappers or automatic .nvmrc switching.

zsh makes PATH unique only during setup so later conda activation/deactivation
can restore entries. It puts nvm ahead of brew/conda before oh-my-zsh loads and
preserves the order inherited from a parent using NVM_BIN. fpath and INFOPATH
remain unique. The custom nvm file repairs a later Homebrew-plugin move only
when that plugin changed the order. Keep the main zshrc PATH setup before plugin loading; the custom nvm file
may repair the brew plugin ordering afterwards. Do not add a post-plugin
command-hash rebuild. Plugin options must be set before their
plugins load; ssh-agent settings are pre-sourced for this reason.

The mac profile initializes an existing /opt/homebrew or /usr/local brew for
fresh Bash sessions, retaining nvm priority and repeated-source stability.
Ubuntu rc files use selected brew on PATH, then the shared Linuxbrew prefix,
then ~/.linuxbrew. They run native shellenv only for an available executable.
Marlowe preserves explicit CARGO_HOME or Cargo's durable HOME default; it does
not relocate Cargo config, credentials and installed binaries into scratch.
Sherlock's remaining cache placement requires current site-rule review before
changes. No configuration change migrates or deletes existing Cargo contents.

## PowerShell profile and prompt

The PowerShell profile installs nothing. Interactive setup requires console
stdin/stdout, loaded PSReadLine and a non-agent session. Script invocations,
redirected output and piped input skip setup and console code-page changes.
Agent detection matches zsh. The interactive tail, which agent terminals keep,
runs only the update hook; no payload hook runs there. Interactive setup defines
`sync-payloads` and `sync-skills`, which install or update the payload repos
only when a person runs them; native Windows has no kit installation. See
[payloads](payloads.md).

Tab cycles completions; Up/Down search history by prefix. RightArrow at the
end of the line accepts a prediction; with PSReadLine 2.2 or later, F2
switches between the inline and list prediction views. The profile asks for history and plugin predictions in the list view only with
PSReadLine 2.2 on PowerShell 7.2 or later; older versions, down to the 7.0
floor, keep PSReadLine's own prediction defaults. With fzf/PSFzf present,
Ctrl+R searches history, Ctrl+T inserts paths and Alt+C changes directory.
Lazy conda setup avoids importing conda until first use.

Interactive encoding uses UTF-8 for native output and Python, respecting
explicit PYTHONUTF8/PYTHONIOENCODING choices. Legacy GBK files still need an
explicit encoding; localized Windows commands may emit a different code page.
CompletionPredictor and WinGet CommandNotFound load on the first idle tick:
missing modules stay silent, failed imports warn once.
Directories list bold blue where `$PSStyle.FileInfo` colors listings
(mainstream from PowerShell 7.3); before 7.2, which added `$PSStyle`, the
profile skips the setting.

oh-my-posh initializes after PSReadLine key handlers because it owns Enter and
Ctrl+C; zoxide follows because it wraps the prompt. A final wrapper preserves
LASTEXITCODE, which zoxide's directory tracking can reset. The tracked theme
lives in home/dot_config/oh-my-posh, uses a release-tagged schema and ASCII
glyph escapes, and supports shell integration/transient prompts. Re-render it
after upgrades.
Windows Terminal settings deploy as a native regular file. A Terminal UI save
rewrites the live file, which shows up as destination drift (`chezmoi diff`);
the next login update stops at it like any changed target until the edit is
committed to the source or reconciled ([update contract](update-contract.md)).
A Terminal restart loads changes.

## Lab input settings

fcitx5 rewrites its profile, so the native source deploys the authoritative
baseline as a private regular file rather than a link; fcitx5's own `conf/`
state stays unmanaged. Like a Terminal UI save above, an fcitx5 rewrite is
destination drift at which the next login update stops until it is reconciled.
On lab-ubuntu, GNOME owns the X keymap. The deployed .xprofile sets CapsLock as
Hyper_L for the fcitx5 language trigger and frees Super+Space for cycling input
methods. It uses /usr/bin/gsettings because the Linuxbrew command lacks GNOME's
dconf backend. Settings apply at X login, not by appending to a shell rc.

## tmux

The shared config requires tmux 3.4+ and keeps its `Ctrl-b` prefix, mouse support, 100000 lines
of scrollback and numbering from 1. [TPM](https://github.com/tmux-plugins/tpm)
loads [resurrect](https://github.com/tmux-plugins/tmux-resurrect),
[tmux-fzf](https://github.com/sainnhe/tmux-fzf) and
[continuum](https://github.com/tmux-plugins/tmux-continuum). Catppuccin Mocha,
extrakto, yank, FloaX, which-key, CPU/RAM and battery plugins add appearance
and interaction where the host supports them. No full config framework or
Oh My Tmux is needed.

On Marlowe only the login env's tmux (3.6a) meets the floor. A non-interactive
shell there, such as `ssh marlowe-plain tmux ...`, finds `/usr/bin/tmux` 3.2a,
which rejects the 3.4 options, and a 3.2a server sharing the default socket
with a 3.6a client can fail to talk to it. Start tmux from an interactive login
shell. For the same reason a non-interactive doctor there, such as
`ssh marlowe-plain 'cd ~/dotfiles && ./doctor.sh'`, reports tmux 3.2a as
`outdated` and exits 1: run the doctor from an interactive login shell
(`ssh marlowe`), where it finds 3.6a.

Without any plugin, the native settings use Catppuccin's Mocha colors:
transparent status background, mauve active pane borders, centered windows,
Nerd Font status capsules and PREFIX/COPY/ZOOM indicators. Catppuccin adds
rounded window tabs; both match WezTerm and Kitty. Window caps use
explicit foreground colors and the default background, avoiding upstream's
invalid `fg=none` styles with a transparent status line. Reloading the config
updates both current and inactive window caps without restarting sessions.
The status line shows the session, directory and host; CPU/RAM appear when available, and
battery appears only on a supported battery-powered host. Metrics describe
the host running tmux, not a particular process or scheduler allocation.
CPU/RAM jobs forward to tmux-cpu with a private 0700 cache under
`~/.cache/tmux-metrics/`; only those subprocesses receive the cache TMPDIR.
Unsafe, foreign or symlinked cache paths hide the optional metrics without
changing the shell's TMPDIR or following shared temporary-file symlinks.

Install the missing clones with `./setup-host.sh --host <host> --check --only S3-clones`,
then `./setup-host.sh --host <host> --yes --only S3-clones`, with
`DOTFILES_AUTO_UPDATE=0` exported. After the dotfiles are applied, reload a running
server with `tmux source-file ~/.tmux.conf`; new servers load it
automatically. Plugins live in `~/.tmux/plugins/`, outside this checkout.
Startup, reload and login hooks never install or update them. Without
TPM, native tmux settings still work. See
[S3-clones](bootstrap.md#s3-clones-oh-my-zsh-theme-and-plugin-clones) for
Other Linux installation and existing-clone behavior.
Use the deployed `~/.tmux.conf` as the sole tmux config: TPM prefers
`${XDG_CONFIG_HOME:-~/.config}/tmux/tmux.conf` when that file exists and would
read its plugin declarations instead.

Press `Ctrl-b`, release it, then use:

| Key | Action |
| --- | --- |
| `Ctrl-s` | Save the layout now |
| `Ctrl-r` | Restore the last saved layout |
| `F` | Search/manage sessions, windows and panes with fzf |
| `Tab` | Extract output text with fzf; Enter copies and Tab inserts |
| `Space` | Open the custom which-key menu |
| `Alt-f` | Toggle the persistent floating scratch shell |
| `Alt-Shift-f` | Open the floating shell's resize/fullscreen/embed menu |
| `y` / `Y` | Copy the command line / working directory with desktop yank |
| `I` | Install plugins added to the config |
| `U` | Explicitly update plugins through TPM |
| `Alt-u` | Remove plugins no longer declared in the config |

The prefix remains Ctrl-b. `p` still selects the previous window, `F` still
opens fzf, and `?` still displays the native key reference. Copy mode uses
vi movement and `y` to copy. Desktop yank requires an available clipboard
backend; SSH sessions use native OSC 52 through the connected terminal.
The terminal must allow clipboard writes. Extrakto uses that transport for SSH
copies. Like the tmux-yank gate, its gate looks for `SSH_CONNECTION`,
`SSH_CLIENT` or `SSH_TTY` in the environment of the session that loads or
reloads the config, so an SSH client's reload turns OSC 52 on. Of the three, a
local attach removes only `SSH_CONNECTION` from the session; a server started
from an SSH login keeps the other two globally and stays on OSC 52. Extrakto
uses the existing Python/fzf tools, clears inherited fzf options, and captures
at most 2000 recent lines per window pane.

The Space menu groups Sessions, Windows, Panes and Tools, with layout
save/restore, resize, fzf, extraction, floating shell and plugin/config
actions. The deployed `~/.config/tmux/which-key.conf` is a manual native tmux
configuration: upstream autobuild is disabled, so reload needs no Python
menu generation, pip package or virtual environment. Upstream may copy its
default config into ignored files in its own checkout on first load; the
deployed menu is then applied. To customize the menu, edit
`home/dot_config/tmux/which-key.conf` in the checkout; a native home receives it
through the login update once it is committed, since that update refuses a dirty
checkout.

The config uses tmux 3.4 popup, menu and style features without version
checks; `config/bootstrap/tools.tsv` holds the floor, and older tmux is
unsupported. TPM statically scans ordinary `@plugin` declarations regardless of
conditionals; the supported legacy `@tpm_plugins` option registers extrakto and
CPU/RAM, the probed battery and desktop-yank plugins, then which-key,
Catppuccin and FloaX, and is rebuilt on each reload.

Continuum saves every 15 minutes while an attached client's status line
refreshes. It restores sessions, windows, panes, layouts and working
directories on server startup. Reloading an established server does not
restore; upstream treats loads within its first 10 seconds as startup.
Programs are **not restarted**, and pane contents/scrollback are
not saved: this does not resume training processes, SSH connections, agent
sessions or Slurm allocations. Boot-time tmux startup is disabled; continuum
disables its existing user `tmux.service` on systemd hosts or removes its
`~/Library/LaunchAgents/Tmux.Start.plist` on macOS.

Snapshots live in `~/.local/share/tmux/resurrect/<hostname>/`, keeping nodes
with a shared home separate. On a single host, continuum gives the first
tmux server precedence; later `-L`/`-S` servers do not independently autosave
or auto-restore. Manual saves on that host still share its snapshot directory.
Keep continuum last in the plugin list and do not overwrite its `status-right`
hook; automatic saves require the status line to stay enabled.

FloaX keeps its own scratch session while hidden and preserves that shell's
directory rather than changing it on every toggle. The config corrects the
current upstream bindings to use the shipped `scripts/floax.sh` and
`scripts/menu.sh`, without modifying the plugin checkout. The scratch session
is included in layout snapshots; its running programs follow the same
layout-only restore policy as other sessions.

tmux-fzf opens in a popup. It reuses the existing fzf dependency and limits its
menu to tmux sessions/windows/panes.
On shared nodes, use native tmux commands for creating or renaming objects:
upstream's new/rename dialogs use fixed `/tmp` pipe names that can collide.
CopyQ is not required or installed; if already available on PATH, upstream
tmux-fzf starts it on plugin load even with this reduced menu. Upstream
plugins do not reliably support installation paths containing spaces.
