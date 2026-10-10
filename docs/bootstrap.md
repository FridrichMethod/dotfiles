# Bootstrapping a host

This playbook takes a fresh machine to the state the dotfiles assume. The
pinned sources live in `config/bootstrap/`; `./doctor.sh` reports what is
missing and `./setup-host.sh` installs what it can without sudo. Each step
below has one heading that the doctor and installer cite as
`docs/bootstrap.md <step-id>`.

### P0-preflight: Preflight

TODO(T5)

### H1-xcode-clt: Xcode Command Line Tools

TODO(T5)

### H1-homebrew: Homebrew on macOS

TODO(T5)

### H1-apt-core: apt prerequisites

TODO(T5)

### H1-locale: en_US.UTF-8 locale

TODO(T5)

### H1-linuxbrew: Linuxbrew

TODO(T5)

### H1-gh-apt-repo: GitHub CLI apt repository

TODO(T5)

### H1-fcitx5: fcitx5 input method

TODO(T5)

### S2-brew-bundle: Brewfile bundles

TODO(T5)

### S2-micromamba: micromamba

TODO(T5)

### H2-alloc: Slurm allocation

TODO(T5)

### S2-login-env: HPC login environment

TODO(T5)

### S2-modules: HPC modules and manual AI CLIs

TODO(T5)

### S3-clones: oh-my-zsh, theme and plugin clones

TODO(T5)

### S3-bat-theme: bat theme

TODO(T5)

### S3-dirs: Vim state directories

TODO(T5)

### S4-nvm: nvm and Node.js

TODO(T5)

### S4-setup-sync: AI-sync runtime

TODO(T5)

### S5-claude: Claude Code

TODO(T5)

### S5-codex: Codex CLI

TODO(T5)

### S6-nerd-font: Nerd Font

TODO(T5)

### S6-kitty: kitty

TODO(T5)

### H7-stow: Stow the dotfiles

TODO(T5)

### H7-chsh: Login shell

TODO(T5)

### H7-auth: Authentication

TODO(T5)

### H7-sync-skills: Skill library sync

TODO(T5)

### H7-doctor: Final doctor run

TODO(T5)

### W1-winget: winget import

TODO(T5)

### W1-psresources: PowerShell modules

TODO(T5)

### W1-font: Nerd Font on Windows

TODO(T5)

### W1-bat-theme: bat theme on Windows

TODO(T5)

### W1-setup-sync: AI-sync runtime on Windows

TODO(T5)

### HW-clone: Clone with symlinks enabled

TODO(T5)

### HW-stow: Elevated stow

TODO(T5)

### HW-auto-stow-task: Automatic stow task

TODO(T5)

### HW-execution-policy: Execution policy

TODO(T5)

### HW-ssh-agent: ssh-agent service

TODO(T5)

### HW-wsl: WSL distribution

TODO(T5)

### HW-auth: Windows authentication

TODO(T5)

### X-host-tools: Host-specific tools

TODO(T5)

### X-contributor: Contributor tools

TODO(T5)

### X-other-linux: Other Linux distributions

TODO(T5)

### X-rc-protection: rc-file protection

TODO(T5)

### X-recovery: Recovery recipes

TODO(T5)
