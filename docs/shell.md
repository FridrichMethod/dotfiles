# Shell startup and host behavior

## Unix startup

The shared profile owns HOME/bin and HOME/.local/bin, locale, MANPATH (including
man's default search path), nvm discovery and host login configuration. Bash
loads it from .bashrc; zsh sources it immediately after its uniqueness setup.
Host aliases and profile files live under ~/.config/sh/. Preserve shared site
prefixes such as /apps/miniconda3; per-user conda and Juliaup paths use HOME.
The vi alias selects nvim only when available, leaving native vi usable otherwise.

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
Agent detection matches zsh. Interactive tails run the update hook before the
payload hook; native Windows has no kit installation. See [payloads](payloads.md).

Tab cycles completions; Up/Down search history by prefix. RightArrow at the
end of the line accepts a prediction, and F2 switches prediction views. With
fzf/PSFzf present, Ctrl+R searches history, Ctrl+T inserts paths and Alt+C
changes directory. Lazy conda setup avoids importing conda until first use.

Interactive encoding uses UTF-8 for native output and Python, respecting
explicit PYTHONUTF8/PYTHONIOENCODING choices. Legacy GBK files still need an
explicit encoding; localized Windows commands may emit a different code page.
CompletionPredictor and WinGet CommandNotFound load on the first idle tick:
missing modules stay silent, failed imports warn once.

oh-my-posh initializes after PSReadLine key handlers because it owns Enter and
Ctrl+C; zoxide follows because it wraps the prompt. A final wrapper preserves
LASTEXITCODE, which zoxide's directory tracking can reset. The tracked theme
lives under win/oh-my-posh, uses a release-tagged schema and ASCII glyph escapes,
and supports shell integration/transient prompts. Re-render it after upgrades.
Windows Terminal settings remain a Stow symlink; UI saves follow it, but a
Terminal restart is required for changes to load. See [Windows installation](windows-installer.md).

## Lab input settings

fcitx5 rewrites its profile, so Stow materializes the authoritative baseline as
an ordinary file; a later stow reasserts it. Invalid directory/special-file
targets fail, and existing links survive until replacements are staged.
On lab-ubuntu, GNOME owns the X keymap. The stowed .xprofile sets CapsLock as
Hyper_L for the fcitx5 language trigger and frees Super+Space for cycling input
methods. It uses /usr/bin/gsettings because the Linuxbrew command lacks GNOME's
dconf backend. Settings apply at X login, not by appending to a shell rc.

## tmux

The shared config requires tmux 2.6+ and keeps its `Ctrl-b` prefix, mouse support, 100000 lines
of scrollback and numbering from 1. [TPM](https://github.com/tmux-plugins/tpm)
loads [resurrect](https://github.com/tmux-plugins/tmux-resurrect),
[tmux-fzf](https://github.com/sainnhe/tmux-fzf) and
[continuum](https://github.com/tmux-plugins/tmux-continuum); no full config
framework or Oh My Tmux is needed.

Install the missing clones with `./setup-host.sh --host <host> --check --only S3-clones`,
then `./setup-host.sh --host <host> --yes --only S3-clones`, with
`DOTFILES_AUTO_UPDATE=0 DOTFILES_PAYLOAD_AUTO_UPDATE=0` exported. After stow,
reload a running server with `tmux source-file ~/.tmux.conf`; new servers
load it automatically. Plugins live in `~/.tmux/plugins/`, outside this
checkout. Startup, reload, Stow and login hooks never install or update
them. Without TPM, native tmux settings still work. See
[S3-clones](bootstrap.md#s3-clones-oh-my-zsh-theme-and-plugin-clones) for
Other Linux installation and existing-clone behavior.
Use the stowed `~/.tmux.conf` as the sole tmux config: TPM prefers
`${XDG_CONFIG_HOME:-~/.config}/tmux/tmux.conf` when that file exists and would
read its plugin declarations instead.

Press `Ctrl-b`, release it, then use:

| Key | Action |
| --- | --- |
| `Ctrl-s` | Save the layout now |
| `Ctrl-r` | Restore the last saved layout |
| `F` | Search/manage sessions, windows and panes with fzf |
| `I` | Install plugins added to the config |
| `U` | Explicitly update plugins through TPM |
| `Alt-u` | Remove plugins no longer declared in the config |

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

tmux-fzf uses a popup on tmux 3.2+ and a split otherwise. It reuses the
existing fzf dependency and limits its menu to tmux sessions/windows/panes.
On shared nodes, use native tmux commands for creating or renaming objects:
upstream's new/rename dialogs use fixed `/tmp` pipe names that can collide.
CopyQ is not required or installed; if already available on PATH, upstream
tmux-fzf starts it on plugin load even with this reduced menu. Upstream
plugins do not reliably support installation paths containing spaces.
