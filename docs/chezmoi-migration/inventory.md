# Tracked-target inventory and retirement ownership

Stage 1 baseline: `1a9d30b837b4425c8c5964bf1e0704290178d41f`.
This is a source-derived migration inventory, not a live HOME scan or deployment
record. No real secrets, account labels, SSH endpoints or remote hosts were read
for this inventory. Stage numbers refer to the [migration plan](README.md).

Stage 4 keeps all 95 physical package paths, 67 ordinary native source entries and
two AI modifies. Role target totals remain 49/56/55/59/54/54/26. Login profile
bridges now dispatch the native updater by the home binding; no legacy sync
helper enters native targets. Ownership/maintenance files and native runtime
state are local metadata, not new managed targets. Eight separately approved
encrypted source leaves now live under `home/private_dot_secrets`; they are not
additional legacy package rows. With local enrollment enabled, complete role
totals are 49/64/63/67/62/62/26 in the same order. Without it, the ordinary totals
above remain unchanged. Mac's production flag is enabled after actual acceptance
of all 64 targets. Marlowe's flag is also enabled after actual 62-target
convergence and final persisted-binding acceptance. WSL's flag is enabled after
63-target convergence and fresh-access acceptance. Lab's flag is enabled after
67-target convergence and fresh WSL-to-Lab access acceptance on `15068b9`.
Sherlock's flag is enabled after actual 62-target convergence and final
persisted-binding acceptance on `15068b9`. All five Unix flags are enabled. The
encrypted source passed exact CI/e2e and reached main at `74985d08`; all five
approved host deployments are now accepted. Native Windows separately accepted
all 26 ordinary targets on `15068b9`, with enrollment false.
The exact-green `bf99958` release has actual ordinary acceptance for lab's 59,
Mac's 56, WSL's 55 and each cluster's 54 targets; this does not change source counts. Per-host backups,
parent preservation, application limits and historical blockers are recorded in
[Stage 4 evidence](stage-4-evidence.md#actual-fleet-outcomes-separate-from-fixtures).

Stage 5 (main `dddc718`, 2026-11-04) changes no package path, native source
entry, category or role total. It modified only canonical inputs
(`common/sh/.aliases`, `common/sh/.profile`, `common/zsh/.zshrc`, the three tmux
`.conf` files, `sherlock/sh/.config/sh/.profile`, the PowerShell 7 profile) and
`home/.chezmoi.toml.tmpl`, which now owns `persistentState`; the state database
stays local metadata, not a managed target. The ownership, caller, contract,
deletion and tool tables below record the Stage 5 results; the per-file mapping
is unchanged. Five Unix hosts converged on `dddc718` and Windows on `57fbc45`
(the same code plus the Stage 5 records), all six re-initialized
([Stage 5 outcome](stage-5-ecosystem.md#stage-5-outcome)).

## Derivation, applicability and notation

`git ls-files common mac sherlock wsl-ubuntu lab-ubuntu marlowe win` yields
**95 tracked package files**: common 52, mac 7, wsl-ubuntu 6, lab-ubuntu 11,
sherlock 5, marlowe 5, win 9. All are Git regular files; six have mode 100755.
The table below has one row per path, including zero-byte tcsh/xonsh files,
the pet metadata/WebP, compiled terminfo and all five current tmux files.
No ignored payload checkout or untracked HOME content contributes a row.

Host sets: **U** = common-only, mac, wsl-ubuntu, lab-ubuntu, sherlock, marlowe;
**A** = U plus win. The common-only role is Unix with no overlay, not an empty
or uninitialized role. An explicit role selects common plus that role's overlay.
Windows selects only common packages `claude`, `codex`, `conda`, `git`, `ssh`,
`wezterm`, as `home/.chezmoiignore` selects for `win` (the former
`$CommonPackages` of the retired `stow-all.ps1`), plus `win/`.
Thus 20 common paths apply to Windows; Unix common has 52. Presence in a package
does not assert that its application is installed on every applicable host.

All destinations are relative to HOME, including `mount.vbs` and `wsl.conf`:
the latter is not automatically installed into WSL's `/etc/wsl.conf`.
Windows Documents paths describe the tracked default; Stage 2 must verify the
actual `$PROFILE` path or model redirected Documents in local data.

Category codes: **O** ordinary configuration; **E** executable/helper code
(some is sourced or invoked with Python and deliberately not executable);
**M** mutable configuration; **X** external asset, here an already tracked opaque
asset, not a new network download; **P** payload-owned path; **C** migration-only
compatibility file. No tracked package file is P: payload-owned trees appear in
the separate ownership-boundary table. Category is not a permission declaration.

Native representation cells name planned paths under the `home/` source root.
**B** is a thin `.tmpl` bridge using literal `include` of the corresponding
legacy source, rooted at `.chezmoi.workingTree`; role variants select exactly
one legacy file for their common destination. **R** is a raw byte-preserving
asset copy with mandatory parity checking during the bridge. **N** is a native
modify template, reading the legacy policy as canonical data during coexistence.
**-** means intentionally absent from native managed targets. `private_` and
`executable_` are native attributes; shared parent directories are never `exact_`.
Stage 2 implements ordinary paths and verifies exact target sets and bytes with
`tests/test_chezmoi_source_state.py`. Literal include is documented by the
[native include interface](https://www.chezmoi.io/reference/templates/functions/include/).
Stage 3 adds exactly the two N modify paths with canonical legacy policy inputs;
their output is checked semantically because native serialization is intentional.
Typed Codex owned/retired metadata contains no policy values and has a parity
test against the legacy constants. The eight separate static-secret source leaves
use `encrypted_private_` and preserve native age ciphertext bytes through a
targeted `-text` attribute. Their six real recipient checks stay private; keyless
CI checks opaque source structure and ordinary role exclusion without identities.

Owner **D** is dotfiles content with the application as reader; **D/app** means
dotfiles baseline plus application-written live state; **D/legacy** means only
the old installer/helper owns the deployment mechanism. Every S6 cell removes
the legacy source after native materialization; it never authorizes deleting
the corresponding live user file. Parenthetical S2/S3 is the replacement stage.

## Per-tracked-package-file mapping

| Legacy source | Destination | Hosts | Category | Native representation under home/ | Current owner | Legacy removal |
| --- | --- | --- | --- | --- | --- | --- |
| `common/aria2/.config/aria2/aria2.conf` | `~/.config/aria2/aria2.conf` | U | O | B: dot_config/aria2/aria2.conf.tmpl | D | S6 (S2) |
| `common/bash/.bash_aliases` | `~/.bash_aliases` | U | O | B: dot_bash_aliases.tmpl | D | S6 (S2) |
| `common/bash/.bash_profile` | `~/.bash_profile` | U | O | B: dot_bash_profile.tmpl | D | S6 (S2) |
| `common/bash/.bashrc` | `~/.bashrc` | U | O | B: dot_bashrc.tmpl | D | S6 (S2) |
| `common/bash/.config/bash/download.sh` | `~/.config/bash/download.sh` | U | E | B: dot_config/bash/download.sh.tmpl | D | S6 (S2) |
| `common/bash/.config/bash/upload.sh` | `~/.config/bash/upload.sh` | U | E | B: dot_config/bash/upload.sh.tmpl | D | S6 (S2) |
| `common/claude/.claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | A | O | B: dot_claude/CLAUDE.md.tmpl | D | S6 (S2) |
| `common/claude/.claude/settings.json` | `~/.claude/settings.json` | A | M | N: dot_claude/modify_private_settings.json | D/app | S6 (S3) |
| `common/claude/.local/bin/claude-settings-sync` | `~/.local/bin/claude-settings-sync` | A | C | -; retire helper | D/legacy | S6 (S2/S3 native replacement) |
| `common/codex/.codex/AGENTS.md` | `~/.codex/AGENTS.md` | A | O | B: dot_codex/AGENTS.md.tmpl | D | S6 (S2) |
| `common/codex/.codex/config.toml` | `~/.codex/config.toml` | A | M | N: dot_codex/modify_private_config.toml | D/app | S6 (S3) |
| `common/codex/.codex/pets/tom/pet.json` | `~/.codex/pets/tom/pet.json` | A | X | B: dot_codex/pets/tom/pet.json.tmpl | D | S6 (S2) |
| `common/codex/.codex/pets/tom/spritesheet.webp` | `~/.codex/pets/tom/spritesheet.webp` | A | X | R: dot_codex/pets/tom/spritesheet.webp | D | S6 (S2) |
| `common/codex/.codex/rules/portable.rules` | `~/.codex/rules/portable.rules` | A | O | B: dot_codex/rules/portable.rules.tmpl | D | S6 (S2) |
| `common/codex/.local/bin/codex-config-sync` | `~/.local/bin/codex-config-sync` | A | C | -; retire helper | D/legacy | S6 (S2/S3 native replacement) |
| `common/codex/.local/bin/codex-rules-sync` | `~/.local/bin/codex-rules-sync` | A | C | -; retire helper | D/legacy | S6 (S2/S3 native replacement) |
| `common/conda/.condarc` | `~/.condarc` | A | O | B: dot_condarc.tmpl | D | S6 (S2) |
| `common/git/.gitconfig` | `~/.gitconfig` | A | O | B: dot_gitconfig.tmpl | D | S6 (S2) |
| `common/kitty/.config/kitty/current-theme.conf` | `~/.config/kitty/current-theme.conf` | U | O | B: dot_config/kitty/current-theme.conf.tmpl | D/app | S6 (S2) |
| `common/kitty/.config/kitty/kitty.conf` | `~/.config/kitty/kitty.conf` | U | O | B: dot_config/kitty/kitty.conf.tmpl | D/app | S6 (S2) |
| `common/sh/.aliases` | `~/.aliases` | U | O | B: dot_aliases.tmpl | D | S6 (S2) |
| `common/sh/.profile` | `~/.profile` | U | O | B: dot_profile.tmpl | D | S6 (S2) |
| `common/ssh/.ssh/config` | `~/.ssh/config` | A | O | B: dot_ssh/config.tmpl | D | S6 (S2) |
| `common/ssh/.ssh/config.d/all.conf` | `~/.ssh/config.d/all.conf` | A | O | B: dot_ssh/config.d/all.conf.tmpl | D | S6 (S2) |
| `common/ssh/.ssh/config.d/github.conf` | `~/.ssh/config.d/github.conf` | A | O | B: dot_ssh/config.d/github.conf.tmpl | D | S6 (S2) |
| `common/ssh/.ssh/config.d/lambda.conf` | `~/.ssh/config.d/lambda.conf` | A | O | B: dot_ssh/config.d/lambda.conf.tmpl | D | S6 (S2) |
| `common/ssh/.ssh/config.d/local.conf` | `~/.ssh/config.d/local.conf` | A | O | B: dot_ssh/config.d/local.conf.tmpl | D | S6 (S2) |
| `common/ssh/.ssh/config.d/pku.conf` | `~/.ssh/config.d/pku.conf` | A | O | B: dot_ssh/config.d/pku.conf.tmpl | D | S6 (S2) |
| `common/ssh/.ssh/config.d/stanford.conf` | `~/.ssh/config.d/stanford.conf` | A | O | B: dot_ssh/config.d/stanford.conf.tmpl | D | S6 (S2) |
| `common/tcsh/.tcshrc` | `~/.tcshrc` | U | O | B: empty_dot_tcshrc.tmpl | D | S6 (S2) |
| `common/tmux/.config/tmux/floax.conf` | `~/.config/tmux/floax.conf` | U | O | B: dot_config/tmux/floax.conf.tmpl | D | S6 (S2) |
| `common/tmux/.config/tmux/metric.py` | `~/.config/tmux/metric.py` | U | E | B: dot_config/tmux/metric.py.tmpl | D | S6 (S2) |
| `common/tmux/.config/tmux/modern.conf` | `~/.config/tmux/modern.conf` | U | O | B: dot_config/tmux/modern.conf.tmpl | D | S6 (S2) |
| `common/tmux/.config/tmux/which-key.conf` | `~/.config/tmux/which-key.conf` | U | O | B: dot_config/tmux/which-key.conf.tmpl | D | S6 (S2) |
| `common/tmux/.tmux.conf` | `~/.tmux.conf` | U | O | B: dot_tmux.conf.tmpl | D | S6 (S2) |
| `common/vim/.vimrc` | `~/.vimrc` | U | O | B: dot_vimrc.tmpl | D | S6 (S2) |
| `common/wezterm/.wezterm.lua` | `~/.wezterm.lua` | A | O | B: dot_wezterm.lua.tmpl | D/app | S6 (S2) |
| `common/xonsh/.xonshrc` | `~/.xonshrc` | U | O | B: empty_dot_xonshrc.tmpl | D | S6 (S2) |
| `common/zsh/.local/bin/my-fzf-preview.sh` | `~/.local/bin/my-fzf-preview.sh` | U | E | B: dot_local/bin/executable_my-fzf-preview.sh.tmpl | D | S6 (S2) |
| `common/zsh/.oh-my-zsh/custom/conda-zsh-completion.zsh` | `~/.oh-my-zsh/custom/conda-zsh-completion.zsh` | U | O | B: dot_oh-my-zsh/custom/conda-zsh-completion.zsh.tmpl | D | S6 (S2) |
| `common/zsh/.oh-my-zsh/custom/download.zsh` | `~/.oh-my-zsh/custom/download.zsh` | U | E | B: dot_oh-my-zsh/custom/download.zsh.tmpl | D | S6 (S2) |
| `common/zsh/.oh-my-zsh/custom/fzf-tab.zsh` | `~/.oh-my-zsh/custom/fzf-tab.zsh` | U | O | B: dot_oh-my-zsh/custom/fzf-tab.zsh.tmpl | D | S6 (S2) |
| `common/zsh/.oh-my-zsh/custom/fzf.zsh` | `~/.oh-my-zsh/custom/fzf.zsh` | U | O | B: dot_oh-my-zsh/custom/fzf.zsh.tmpl | D | S6 (S2) |
| `common/zsh/.oh-my-zsh/custom/nvm.zsh` | `~/.oh-my-zsh/custom/nvm.zsh` | U | O | B: dot_oh-my-zsh/custom/nvm.zsh.tmpl | D | S6 (S2) |
| `common/zsh/.oh-my-zsh/custom/ssh-agent.zsh` | `~/.oh-my-zsh/custom/ssh-agent.zsh` | U | O | B: dot_oh-my-zsh/custom/ssh-agent.zsh.tmpl | D | S6 (S2) |
| `common/zsh/.oh-my-zsh/custom/upload.zsh` | `~/.oh-my-zsh/custom/upload.zsh` | U | E | B: dot_oh-my-zsh/custom/upload.zsh.tmpl | D | S6 (S2) |
| `common/zsh/.oh-my-zsh/custom/zsh-autosuggestions.zsh` | `~/.oh-my-zsh/custom/zsh-autosuggestions.zsh` | U | O | B: dot_oh-my-zsh/custom/zsh-autosuggestions.zsh.tmpl | D | S6 (S2) |
| `common/zsh/.p10k.zsh` | `~/.p10k.zsh` | U | O | B: dot_p10k.zsh.tmpl | D | S6 (S2) |
| `common/zsh/.zprofile` | `~/.zprofile` | U | O | B: dot_zprofile.tmpl | D | S6 (S2) |
| `common/zsh/.zsh_aliases` | `~/.zsh_aliases` | U | O | B: dot_zsh_aliases.tmpl | D | S6 (S2) |
| `common/zsh/.zshenv` | `~/.zshenv` | U | O | B: dot_zshenv.tmpl | D | S6 (S2) |
| `common/zsh/.zshrc` | `~/.zshrc` | U | O | B: dot_zshrc.tmpl | D | S6 (S2) |
| `lab-ubuntu/bash/.config/bash/.bashrc` | `~/.config/bash/.bashrc` | lab-ubuntu | O | B: dot_config/bash/dot_bashrc.tmpl | D | S6 (S2) |
| `lab-ubuntu/claude/.local/bin/claude-limited` | `~/.local/bin/claude-limited` | lab-ubuntu | E | B: dot_local/bin/executable_claude-limited.tmpl | D | S6 (S2) |
| `lab-ubuntu/fcitx5/.config/fcitx5/config` | `~/.config/fcitx5/config` | lab-ubuntu | O | B: dot_config/fcitx5/config.tmpl | D | S6 (S2) |
| `lab-ubuntu/fcitx5/.config/fcitx5/profile` | `~/.config/fcitx5/profile` | lab-ubuntu | M | B: dot_config/fcitx5/private_profile.tmpl | D/app | S6 (S2) |
| `lab-ubuntu/fcitx5/.local/bin/fcitx5-profile-sync` | `~/.local/bin/fcitx5-profile-sync` | lab-ubuntu | C | -; retire helper | D/legacy | S6 (S2/S3 native replacement) |
| `lab-ubuntu/fcitx5/.xprofile` | `~/.xprofile` | lab-ubuntu | O | B: dot_xprofile.tmpl | D | S6 (S2) |
| `lab-ubuntu/git/.gitconfig_local` | `~/.gitconfig_local` | lab-ubuntu | O | B: dot_gitconfig_local.tmpl | D | S6 (S2) |
| `lab-ubuntu/sh/.config/sh/.aliases` | `~/.config/sh/.aliases` | lab-ubuntu | O | B: dot_config/sh/dot_aliases.tmpl | D | S6 (S2) |
| `lab-ubuntu/sh/.config/sh/.profile` | `~/.config/sh/.profile` | lab-ubuntu | O | B: dot_config/sh/dot_profile.tmpl | D | S6 (S2) |
| `lab-ubuntu/ssh/.ssh/config.d/legacy.conf` | `~/.ssh/config.d/legacy.conf` | lab-ubuntu | O | B: dot_ssh/config.d/legacy.conf.tmpl | D | S6 (S2) |
| `lab-ubuntu/zsh/.config/zsh/.zshrc` | `~/.config/zsh/.zshrc` | lab-ubuntu | O | B: dot_config/zsh/dot_zshrc.tmpl | D | S6 (S2) |
| `mac/bash/.config/bash/.bashrc` | `~/.config/bash/.bashrc` | mac | O | B: dot_config/bash/dot_bashrc.tmpl | D | S6 (S2) |
| `mac/git/.gitignore_global` | `~/.gitignore_global` | mac | O | B: dot_gitignore_global.tmpl | D | S6 (S2) |
| `mac/sh/.config/sh/.aliases` | `~/.config/sh/.aliases` | mac | O | B: dot_config/sh/dot_aliases.tmpl | D | S6 (S2) |
| `mac/sh/.config/sh/.profile` | `~/.config/sh/.profile` | mac | O | B: dot_config/sh/dot_profile.tmpl | D | S6 (S2) |
| `mac/ssh/.ssh/config.d/legacy.conf` | `~/.ssh/config.d/legacy.conf` | mac | O | B: dot_ssh/config.d/legacy.conf.tmpl | D | S6 (S2) |
| `mac/ssh/.ssh/config.d/mac.conf` | `~/.ssh/config.d/mac.conf` | mac | O | B: dot_ssh/config.d/mac.conf.tmpl | D | S6 (S2) |
| `mac/zsh/.config/zsh/.zshrc` | `~/.config/zsh/.zshrc` | mac | O | B: dot_config/zsh/dot_zshrc.tmpl | D | S6 (S2) |
| `marlowe/bash/.config/bash/.bashrc` | `~/.config/bash/.bashrc` | marlowe | O | B: dot_config/bash/dot_bashrc.tmpl | D | S6 (S2) |
| `marlowe/git/.gitconfig_local` | `~/.gitconfig_local` | marlowe | O | B: dot_gitconfig_local.tmpl | D | S6 (S2) |
| `marlowe/sh/.config/sh/.aliases` | `~/.config/sh/.aliases` | marlowe | O | B: dot_config/sh/dot_aliases.tmpl | D | S6 (S2) |
| `marlowe/sh/.config/sh/.profile` | `~/.config/sh/.profile` | marlowe | O | B: dot_config/sh/dot_profile.tmpl | D | S6 (S2) |
| `marlowe/zsh/.config/zsh/.zshrc` | `~/.config/zsh/.zshrc` | marlowe | O | B: dot_config/zsh/dot_zshrc.tmpl | D | S6 (S2) |
| `sherlock/bash/.config/bash/.bashrc` | `~/.config/bash/.bashrc` | sherlock | O | B: dot_config/bash/dot_bashrc.tmpl | D | S6 (S2) |
| `sherlock/sh/.config/sh/.aliases` | `~/.config/sh/.aliases` | sherlock | O | B: dot_config/sh/dot_aliases.tmpl | D | S6 (S2) |
| `sherlock/sh/.config/sh/.profile` | `~/.config/sh/.profile` | sherlock | O | B: dot_config/sh/dot_profile.tmpl | D | S6 (S2) |
| `sherlock/terminfo/.terminfo/t/tmux-256color` | `~/.terminfo/t/tmux-256color` | sherlock | X | R: dot_terminfo/t/tmux-256color | D | S6 (S2) |
| `sherlock/zsh/.config/zsh/.zshrc` | `~/.config/zsh/.zshrc` | sherlock | O | B: dot_config/zsh/dot_zshrc.tmpl | D | S6 (S2) |
| `win/git/.gitconfig_local` | `~/.gitconfig_local` | win | O | B: dot_gitconfig_local.tmpl | D | S6 (S2) |
| `win/oh-my-posh/.config/oh-my-posh/prompt.omp.json` | `~/.config/oh-my-posh/prompt.omp.json` | win | O | B: dot_config/oh-my-posh/prompt.omp.json.tmpl | D/app | S6 (S2) |
| `win/powershell/Documents/PowerShell/profile.ps1` | `~/Documents/PowerShell/profile.ps1` | win | O | B: Documents/PowerShell/profile.ps1.tmpl | D | S6 (S2) |
| `win/powershell/Documents/WindowsPowerShell/profile.ps1` | `~/Documents/WindowsPowerShell/profile.ps1` | win | O | B: Documents/WindowsPowerShell/profile.ps1.tmpl | D | S6 (S2) |
| `win/ssh/.ssh/config.d/legacy.conf` | `~/.ssh/config.d/legacy.conf` | win | O | B: dot_ssh/config.d/legacy.conf.tmpl | D | S6 (S2) |
| `win/terminal/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json` | `~/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json` | win | O | B: AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json.tmpl | D/app | S6 (S2) |
| `win/wsl/.wslconfig` | `~/.wslconfig` | win | O | B: dot_wslconfig.tmpl | D | S6 (S2) |
| `win/wsl/mount.vbs` | `~/mount.vbs` | win | E | B: mount.vbs.tmpl | D | S6 (S2) |
| `win/wsl/wsl.conf` | `~/wsl.conf` | win | O | B: wsl.conf.tmpl | D | S6 (S2) |
| `wsl-ubuntu/bash/.config/bash/.bashrc` | `~/.config/bash/.bashrc` | wsl-ubuntu | O | B: dot_config/bash/dot_bashrc.tmpl | D | S6 (S2) |
| `wsl-ubuntu/git/.gitconfig_local` | `~/.gitconfig_local` | wsl-ubuntu | O | B: dot_gitconfig_local.tmpl | D | S6 (S2) |
| `wsl-ubuntu/sh/.config/sh/.aliases` | `~/.config/sh/.aliases` | wsl-ubuntu | O | B: dot_config/sh/dot_aliases.tmpl | D | S6 (S2) |
| `wsl-ubuntu/sh/.config/sh/.profile` | `~/.config/sh/.profile` | wsl-ubuntu | O | B: dot_config/sh/dot_profile.tmpl | D | S6 (S2) |
| `wsl-ubuntu/ssh/.ssh/config.d/legacy.conf` | `~/.ssh/config.d/legacy.conf` | wsl-ubuntu | O | B: dot_ssh/config.d/legacy.conf.tmpl | D | S6 (S2) |
| `wsl-ubuntu/zsh/.config/zsh/.zshrc` | `~/.config/zsh/.zshrc` | wsl-ubuntu | O | B: dot_config/zsh/dot_zshrc.tmpl | D | S6 (S2) |

## Exceptions, coverage totals and ownership boundaries

The four former `.stowrc` materialization exceptions (Stow retired in Stage 6)
are explicitly included above:
`.claude/settings.json`, `.codex/config.toml`, `.codex/rules/portable.rules`,
and lab-ubuntu's `.config/fcitx5/profile`. The first two become native modifies;
rules become an opaque ordinary file and fcitx5 becomes an authoritative private
ordinary file despite being rewritten by fcitx5. No runtime-only fcitx5 `conf/`
state is imported. The three AI sync executables and fcitx5 sync executable
remain available only to the legacy path, never copied as native helpers.

The other former `.stowrc` ignores covered OS/editor/cache artifacts and the
retired `coding-agent-kit`, `PyMOLScripts`, `sherlock-kit` checkouts; none of
the 95 tracked paths matched them. There is no tracked `.stow-local-ignore` in
these packages. Stage 6 removed `.stowrc` with Stow; `.gitignore` keeps the
leftover-checkout lines until Phase C. The native model deploys only
inventoried targets; it must not import ignored checkouts.

| Role | Current package paths | Legacy-only helpers excluded | Stage 2 ordinary/assets targets | Stage 3 complete native targets |
| --- | ---: | ---: | ---: | ---: |
| common-only | 52 | 3 | 47 | 49 |
| mac | 59 | 3 | 54 | 56 |
| wsl-ubuntu | 58 | 3 | 53 | 55 |
| lab-ubuntu | 63 | 4 | 57 | 59 |
| sherlock | 57 | 3 | 52 | 54 |
| marlowe | 57 | 3 | 52 | 54 |
| win | 29 | 3 | 24 | 26 |

These are unique file destinations, excluding directories, native special files
and unapproved secret enrollment. Stage 3 fills Stage 2's two AI gaps on every
role; the four legacy helper definitions stay absent. An omitted legacy helper
is not a coverage defect.
Native rendered target lists must match these sets, not just their counts.

| Non-package material | Destination/owner | Native treatment and boundary | Stage |
| --- | --- | --- | --- |
| `config/payloads.tsv` kit entry | Upstream kit installation; launchers/completions and `.claude/coding-agent-kit/` | P; delegate to the upstream installer, preserve Unix-only availability and native Windows silent missing-helper guards | S5 done: explicit-only (D7), installed or updated only by `sync-payloads` or `--now`, channel `0.7` and Unix-only rows unchanged; S6 removes the `stow-links` refusal (old link repair) |
| Same manifest, PyMOL entry | Upstream PyMOLScripts installer and its installed targets | P; no vendored tree, no direct native ownership of its files | S5 done: explicit-only (D7); S6 retires only the shared transition no-ops |
| Same manifest, skills entry | Upstream awesome-skills installed skills under its documented roots | P; keep explicit `sync-skills` and ownership checks until interface evidence supports removal | S5 done: explicit-only (D7), `sync-skills` and the probes kept, `AWESOME_SKILLS_AUTO_UPDATE` removed; S6 deletes the no-op shim |
| Bootstrap clone manifests | `.oh-my-zsh/`, plugin/theme trees and `.tmux/plugins/` | Installer-owned external assets; chezmoi manages only inventoried custom files within shared parents, never an exact directory or blanket cleanup | S2 mapping; S5 kept them in S3-clones with their upstream updaters, no externals (`test_source_declares_no_externals`) |
| Root `AGENTS.md`, `CLAUDE.md`, mirrored first-party skills | Repository instructions, not HOME targets | Preserve the import stub and mirrored skills; narrowly update active stage instructions | Each owning stage |
| `.venv-sync`, `requirements-sync.txt`, `setup-sync.*`, `lib/config_sync.py`, `lib/sync-runtime.sh` | Legacy sync backend/runtime | Temporary compatibility only; keep for legacy callers through S6, absent from native runtime | S3 dependency-negative proof; S6 delete chain |
| `.ssh` keys, known_hosts, control sockets and agent state | User/SSH runtime | Unmanaged, never inferred from tracked connection snippets or distributed by default | S2 boundaries; S4/S6 private verification |
| Auth stores, sessions, history, project trust, plugin caches | Application/OS keychain | Unmanaged, preserve contents and active ownership | S3/S4/S6 |

The Windows WSL helper contains a physical-drive mount command. Managing its
bytes does not authorize executing it or changing its device target. Keep its
CRLF exception and the `.wslconfig` CRLF exception from `.gitattributes`; test
rendered bytes on Windows. Files named SSH `legacy.conf` are current tracked
connection snippets, not automatically historical-removal candidates.

## Temporary single-source bridge and parity checks

Until S6, the 95 legacy files remain canonical. S2 creates small include templates
for text, with no second editable copy of policy or shell configuration. A
working-tree-root path is required because `.chezmoiroot` selects `home/` and
relative native includes otherwise resolve from the source directory. Prove it
in a linked worktree whose path contains spaces. Use literal `include`, never
`includeTemplate` or `template`, so shell/config text containing template-looking
delimiters stays opaque. Role selection is explicit local chezmoi data; OS
validation rejects an incompatible role and never guesses a cluster overlay.

Only the WebP and compiled terminfo assets are copied temporarily. JSON pet
metadata uses a literal text bridge. Windows CRLF/mixed-newline files also use
literal includes and retain exact bytes. The legacy file is canonical; S2 compares
every copied asset against `git show BASELINE:path`/current canonical bytes and
fails on divergence. Stage 6 removes these two duplicate legacy assets after
materialization; no generator service or runtime inventory is needed.
Empty `.tcshrc` and `.xonshrc` need the native `empty_` attribute (or an equally
tested native representation) if plain empty rendering would omit/delete them.
The B row is a content mapping, not permission to drop these files.

S2 coverage checks compare this table's exact host destination sets with native
`managed` output, compare every ordinary rendered byte to its canonical source,
and inspect executable/private modes. The two AI targets are the only planned
content gaps. In S3, native modify templates read the same legacy JSON/TOML
baselines. Any temporary native ownership metadata mirroring `CODEX_POLICY` and
`CODEX_RETIRED` gets an explicit parity assertion against the legacy definitions;
portable policy values are never independently duplicated. S6 materializes
final ordinary source, moves canonical policy once, then asserts no surviving
include, wrapper, test, documentation instruction or hook reads a removed path.

## Source-path callers and test disposition

This map is derived from tracked-source searches, not a scan of installed state.
S2/S3 adapt behavior tests to rendered temporary destinations while retaining
legacy coverage during coexistence; S6 deletes mechanism-only cases together
with their implementation. Files with both kinds of cases must be split by
behavior, not deleted wholesale.

| Current callers/source assumptions | Relevant tests/selectors | Disposition and owner |
| --- | --- | --- |
| `common/{claude,codex}/.local/bin/*-sync` resolve symlinks and climb four parents into `lib/sync-runtime.sh`; that runtime invokes `lib/config_sync.py` | `tests/test_config_sync.py`, `tests/config-sync.sh`, `tests/ai-config-sync.sh`, `tests/codex-config-sync.sh`; structured/AI/Codex hooks | S3 port owned-field, arrays, malformed-input, permissions and local-state behavior to native modifies; S6 retire symlink-climb, custom writer/CAS/formatting and runtime-selection cases |
| `stow-all.sh`, `stow-all.ps1` enumerate package roots and invoke merge/materialization sources directly | `tests/stow-all.sh`, `tests/unix-installer.sh`, `tests/windows-installer.{sh,ps1}`, `tests/windows-installer-controls.ps1`, `tests/test_stow_ignores.py` | S2 preserve applicability/bytes in native fixtures; S4 port takeover/conflict/foreign-file/mode/ACL safety; S6 retire package enumeration, Stow parser, adoption and historical-repair mechanics |
| `lab-ubuntu/fcitx5/.local/bin/fcitx5-profile-sync`, both installers' fcitx5 source handling | `tests/fcitx5-profile-sync.sh`, Stow hook | S2 port authoritative private profile and unmanaged sibling behavior; S6 retire the helper's staging mechanics |
| `common/sh/.profile` sources `~/.config/sh/.profile`; `.aliases` sources the matching host aliases; Bash/zsh source shared and host paths | `tests/shell-profile.sh`, `tests/host-overlays.sh`, `tests/test_portable_shell.py` | S2 port source inputs to rendered HOME; retain PATH/nvm ordering, quiet startup, shell-state, completions and host overrides; S5 change only justified surviving branches |
| `common/zsh/.zshrc` sources custom oh-my-zsh files and update/payload scripts; `my-fzf-preview.sh` remains executable | `tests/test_ai_integration.py`, `tests/ai-integration.sh`, shell tests | S2 retain fzf/account preview non-disclosure, aliases and native Windows helper guards; S4 switch updater caller; S5 removed the payload dispatch (D7 explicit-only, `281e33f`), so only the update dispatch remains |
| `common/tmux/.tmux.conf` sources all three `.conf` fragments and calls `metric.py` with `python3 -I -B`; which-key reloads `~/.tmux.conf` | `tests/test_tmux.py`, `tests/tmux.sh`; tmux hook | S2 use rendered files and preserve all five paths, plugin fallback, clipboard/battery gates, private metric cache, menu quoting, reload and hostname recovery; S5 removed all seven version gates and the version parsing at the 3.4 floor (`e6cfba2`), keeping all of the rest; extrakto's OSC 52 choice now reads the session environment like tmux-yank's; Linux CI fails, not skips, without real tmux 3.4 |
| `tests/claude-customizations.cjs` parses shared settings; `test_ai_integration.py` reads legacy policy and shell files | Claude/AI integration hooks | S3 verify resulting native policy values and helper commands; retain legacy-source checks until S6 canonical policy move |
| `win/powershell/Documents/*/profile.ps1` discovers kit/theme/conda and resolves update/payload scripts through `DOTFILES_DIR` or `~/dotfiles` | `tests/powershell-profile.{sh,ps1}`, Windows installer suites | S2 retain 5.1/7 profile syntax, interaction/agent detection, lazy conda, completion and LASTEXITCODE behavior; S4 verify real `$PROFILE` and switch updater; S5 removed the payload tail call, and `sync-payloads` runs the validated native source (`DOTFILES_DIR` only on unmarked homes); S6 remove old deployment assumptions |
| `scripts/dotfiles-update.{sh,ps1}`, `scripts/dotfiles-auto-stow.ps1`, common profile/zsh and PowerShell interactive tails | `tests/update-hooks.{sh,ps1}`, `tests/e2e-harness.{sh,ps1}` | S4 port session triggering, dirty-source visibility and bounded noninteractive failure to thin native update; S6 retire Stow acknowledgement/revision receipts, elevated worker and old logger fallback |
| `scripts/payload-update.{sh,ps1}`, `config/payloads.tsv`, `lib/bootstrap/checks.sh`, `doctor.ps1` inspect retired `common/PACKAGE/` link text | `tests/payload-update.{sh,ps1}`, `tests/test_payload_download.py`, doctor/bootstrap tests | S5 made payloads explicit-only (D7) and deleted the scheduler, its records and the Windows stamp publication (`281e33f`), ending that correctness obligation with the code; S6 remove `stow-links` historical advice and detection while preserving supported upstream delegation, platform selection and local edits |
| `lib/bootstrap/checks.sh` rc source tables/dirty checks and Stow symlink diagnostics; `steps-guard.sh`, `steps-human.sh`, `steps-runtimes.sh` use current source layout | `tests/doctor.sh`, `tests/bootstrap.ps1`, `tests/setup-host.sh`, `tests/bootstrap-manifest.sh`, `tests/test_bootstrap_manifest.py` | S5 resolved the native host from `[data].host`, named the `native-config` cause, deleted the submodule check and fixed native H2-alloc; it kept the rc source tables and `steps-guard.sh` as tripwires; S6 delete obsolete source tables/venv checks and keep offline/no-write/error guarantees |
| `tests/e2e/lib/flow-other.sh`, `flow-win.ps1`, e2e harnesses copy/enumerate `common/`/`win/`; site fixtures encode overlay paths | E2e runner and harness tests | S4 port real takeover/recovery flow; S6 retire fake Stow/link expectations and retain supported platform/site behavior |
| `tests/run.{sh,ps1}`, `tests/test-entrypoints.sh`, `.pre-commit-config.yaml`, CI and `tests/COVERAGE.md` encode paths and sync runtime prerequisites | Hook-selection/environment/worktree tests | Each stage updates its added/changed selector; S2 lint rendered shell/Lua where source has Go syntax; S6 remove legacy-only prerequisites without losing behavior hooks |
| `README.md`, `docs/{config-sync,shell,bootstrap,payloads,update-contract,windows-installer,testing}.md`, root `AGENTS.md`, mirrored bootstrap skills | Documentation/ASCII/skill-parity hooks | Update with each changed contract; S4 publish upgrade procedure; S6 remove instructions that invoke deleted source, Stow or setup-sync |

Re-derive source-path callers at each removal with `rg -n` over the tracked
scripts, libraries, tests, hook definitions and docs. A search hit is a review
candidate, not an automatic deletion instruction.

## Contract classification

| Classification | Guarantees / implementation | Owning stages |
| --- | --- | --- |
| Retained | Seven explicit roles, Windows allowlist, one writer per destination, unmanaged siblings and local edits visible, executable/private attributes, second-apply convergence, unchanged security-policy values | S2/S3 fixtures; S4 takeover; S6 verification |
| Retained | Claude authoritative arrays and local model; Codex exact owned/retired paths and live-only state; malformed/type/ancestor conflicts fail without replacing the affected target | S3 native transforms; S6 legacy backend deletion |
| Retained | Offline reduced doctor, isolated test homes, person-triggered installs, visible privileged steps, site/allocation rules, payload upstream ownership, native Windows/macOS/Linux support; since S5 payload repos install or update only when a person runs `sync-payloads` or `--now` | S1 onward, S5 simplification |
| Retained | Current shell and tmux behavior, root import stub, Codex fallback to other projects' CLAUDE instructions, native Windows silent missing-kit guards | S2 mapping, S5 only with separately proved benefit; S5 dropped tmux below 3.4 by user decision and extrakto's OSC 52 choice now reads the session environment (tmux rows below) |
| Retained | Native login updater binary: Unix as in S4; Windows runs only the private `~/.local/bin/chezmoi.exe` after reparse, owner and DACL checks on a held handle, never a PATH match (narrowed, not closed: a double junction swap remains possible); W1-chezmoi writes it with a protected DACL, and the doctor and W1-chezmoi flag an exe the updater refuses | S4 adapter; S5 binary trust (`6e2f6df`, `9836f27`, `90d10ac`) |
| Deliberately native | Regular-file deployment and native edit/add/merge/apply; GUI saves become destination drift; no Stow write-through promise | S2 model; S4 recovery guidance |
| Deliberately native | Native JSON/TOML duplicate-key/numeric semantics and serialization; comments/order/whitespace can change; no old first-apply bytes/inode/mtime/fsync/CAS guarantees | S1 observed evidence; S3 implementation |
| Deliberately native | Native file writing/cache/state, no whole-HOME transaction or global write-free-preview claim; private AI files rather than arbitrary mode intersections. Since S5 the config template owns `persistentState` = `<destDir>/.local/state/chezmoi/chezmoi.boltdb`, so plain native commands share the updater's state (updater flags still win); `cacheDir` stays local | S1/S3 probes; S4 takeover review; S5 `69a743b` and six-host re-init (all six done) |
| Temporary compatibility | Current Stow source paths, source bridge, legacy wrappers/runtime and preflight, `DOTFILES_HOST`/remembered old role and old updater until takeover. Since S5 `DOTFILES_HOST` and the receipt are legacy only: native-owned homes take the role from `[data].host` | S2/S3 coexistence; S4 switch; S5 native host resolution (`4b46737`); S6 removal |
| Temporary compatibility | Historical repair, baseline migration API/writeback, old shim (a pure no-op since S5), payload transition no-ops and `stow-links` refusal, inert `DOTFILES_PAYLOAD_AUTO_UPDATE=0` provisioning exports | S3 declare native API retirement; S5 deleted the old checkout diagnostics and the opt-out adapter; S6 deletes the rest (below) |
| Deferred product choice | Exact Claude floor/old-ID removal (both IDs kept through S5) | Later verified client decision; no arbitrary floor increase |
| Decided in S5 | tmux floor 3.4 with all seven version gates removed; consumer-side payload scheduler removed (D7 explicit-only for every home); Bash 3.2, PowerShell 7.0 entrypoints with the 5.1 profile and Python 3.11 kept | S5 (`e6cfba2`, `281e33f`, `a8ca3ff`) |
| Deferred enrollment choice | Actual static-secret allowlist, recipient/access scope and private first-identity bootstrap; optional one-time auth seed | S1 synthetic evidence and interface classification; S3 representation; S4 real enrollment |

## Compatibility deletion map

The accepted end state is **current-layout-only** support. Historical automatic
repair is not ported into chezmoi. Most old Stow repair disappears with Stow in
S6, rather than becoming a separate refactor in S2. No all-host-attestation gate
is restored; unsupported offline installations still need controlled recovery.

| Unit / symbols | Callers, tests and documentation to change together | Stage / preserved boundary |
| --- | --- | --- |
| `remove_retired_link` / `Remove-RetiredLink`, retired Sherlock/instructions links | Both installers; Stow/Unix/Windows installer repair fixtures; bootstrap/Sherlock guidance | S6 delete; S4 manual exact-owned-link procedure, preserve foreign links/checkouts/modules |
| Retired kit/PyMOL `STOW_PATH` loops and `RetiredPackageLinks` / `Remove-RetiredPackageLink` | Both installers; retired-package fixture portions; `docs/payloads.md` | S6; keep upstream ownership and local edits |
| `filter.codex-portable` cleanup | `stow-all.sh`, installer fixtures, config-sync docs | S6; S4 manual local Git-filter inspection |
| Exact-marker `AGENTS.override.md` cleanup | `stow-all.sh`, generated-marker installer cases, instructions docs | S6; S4 identify generated vs manual override; never delete arbitrary content |
| `scripts/awesome-skills-update.sh` one-login shim | Hook selectors, test entrypoint copies, payload/update fixtures and docs | S5 made it a pure no-op (`:`, `281e33f`) for rc files read before an old pull; S6 deletes it with its last caller; no native shim |
| Payload consumer scheduler: `--auto` / `--worker` / `-Auto` / `-Worker`, session markers, `days` rows, `ITEM.stamp` / `ITEM.failed` / `payload.log`, age/retry, detached spawn, Windows stamp publication, Sherlock `DOTFILES_PAYLOAD_AUTO_UPDATE=0` override | Payload twins, profiles, `config/payloads.tsv`, `lib/bootstrap/checks.sh`, `doctor.ps1`, payload/doctor/guard/profile tests | Deleted in S5 under D7 (`c4b4349`, `281e33f`, `a8ca3ff`): `scripts/payload-update.sh` 343 to 244 lines, `.ps1` 333 to 235. Until S6 a no-arg or sourced call and the retired flags are silent no-ops, and the provisioning exports of `DOTFILES_PAYLOAD_AUTO_UPDATE=0` are inert; old host record files are ignored, never removed |
| Payload manifest `stow-links` field and retired-link consumers | `config/payloads.tsv`, payload twins, `lib/bootstrap/checks.sh`, `doctor.ps1`, payload/doctor/bootstrap tests | Kept unchanged through S5 (a proposed rewording of its advice for native-owned homes was dropped); S6 remove historical field/readers together; keep actual current readiness/ownership probes |
| `AWESOME_SKILLS_AUTO_UPDATE` adapter | Payload scripts, doctor advice, payload/doctor tests, payload docs | Deleted in S5 with the scheduler: the hook half in `281e33f`, the doctor half in `a8ca3ff`; the through-2027-01-31 promise is withdrawn early. Name items on the command (`sync-payloads kit pymol`); `DOTFILES_PAYLOAD_ITEMS` still sets the default items; `tests/doctor.sh` pins that the variable is ignored |
| `BOOTSTRAP_RETIRED_CHECKOUTS` and Windows counterpart | `lib/bootstrap/checks.sh`, `doctor.ps1`, doctor/bootstrap fixtures | Deleted in S5 under D9 with the whole submodule check and the `submodule` reserved id (`d200d3f`); the no-submodule invariant is `test_repository_tracks_no_submodules` (`3b54132`). Leftover checkouts stay for inspection by hand; no automatic checkout/module deletion |
| Retired checkout ignore entries | `.gitignore`, `.stowrc`, `tests/test_stow_ignores.py` | S6 Stow ignores retire with enumeration; cheap `.gitignore` residue guards may remain |
| Old updater fallback logger, receipts/locks/retries/elevated task | `scripts/dotfiles-update.*`, `scripts/dotfiles-auto-stow.ps1`, profile callers, update/e2e tests, update-contract docs | S4 native adapter replaces behavior; S6 old code retires; preserve quiet startup and exact worker/task quiescence |
| `--migrate-portable`, `retain_missing`, source writeback | `lib/config_sync.py`, sync wrappers, dedicated config-sync tests/docs | S3 declare absent from native API; S6 delete backend/API; Codex retired-key removal remains current enforcement |
| Parser chain and installers' AI checks | `setup-sync.*`, requirements, sync runtime, wrappers, bootstrap/doctor/runners/CI/hooks/docs | S3 prove native path lacks dependency; S6 remove only after last supported legacy caller |

S4's operator deliverable names immutable last-Stow and first-native revisions
(not assigned prematurely here), supported floors, withdrawn automatic repair,
and bridge vs clean-clone procedure. Disable both old dotfiles and payload hooks,
quiesce existing owned workers and the exact Windows scheduled task before the
breaking revision; environment variables alone do not stop existing workers.
Inspect exact links, generated override, filter and old opt-outs; preserve local
commits/custom content. A fresh clone does not repair HOME. Reapply twice, check
shells/apps/SSH/new update behavior, then restore intended hooks. Recovery keeps
new edits; never blindly restow over changed regular files. Document honestly
that an unsupported old hook can pull past the cutoff and break links.

## Tool support and evidence

No floor is raised by this documentation change. Stage 5 later raised only tmux
(2.6 to 3.4, `e6cfba2`); the rows below add the Stage 5 result after the Stage 1
text. `config/bootstrap/tools.tsv` remains authoritative for existing
provisioning. Version output is distinguished
from behavior tests; no native macOS/Windows or remote-host test was run by this
inventory worker. The coordinator's selected native fixture binary is v2.74.0;
the actual native test matrix belongs in [sources.md](sources.md)/[status.md](status.md).

| Tool / current floor | Stage 1 decision / concrete feature or removal | Official evidence | Actually observed or exercised here | Provisioning / invocation and owner |
| --- | --- | --- | --- | --- |
| chezmoi / absent in legacy | Select v2.74.0 fixture baseline; S2 minimum follows successful probes, no untested older claim. Native flags, modify templates, typed TOML operations and builtin age replace custom runtime | [v2.74.0 release](https://github.com/twpayne/chezmoi/releases/tag/v2.74.0), [source attributes](https://www.chezmoi.io/reference/source-state-attributes/), [minimum-version file](https://www.chezmoi.io/reference/special-files/chezmoiversion/) | Not on this worker's PATH; coordinator provisions and records actual native evidence separately | S1 checksum-verified CI artifact on all three platforms; `DOTFILES_TEST_CHEZMOI` explicit path or PATH. S2 `.chezmoiversion`; S4/S5 person-triggered host provisioning. S5: the Windows login updater runs only the provisioned `~/.local/bin/chezmoi.exe`, which W1-chezmoi writes with a protected DACL |
| tmux / 3.4 since S5 (2.6 before) | Stage 1 retained 2.6 and named 3.4 as the candidate for removing the 3.0 menu, 3.2 modern/OSC52, 3.3 FloaX and 3.4 style gates; no claim it is latest. S5 applied it by user decision (`e6cfba2`): `tools.tsv` and `hpc-login-env.yml` together, all seven gates and the version parsing removed; conditional TPM registration (battery, yank) and current fallbacks kept | [Tagged 3.4 CHANGES](https://raw.githubusercontent.com/tmux/tmux/3.4/CHANGES) documents display-menu (3.0), popups (3.2), popup style/title flags (3.3), menu styles (3.4) | Stage 1: tmux 3.4; `bash tests/tmux.sh`: 13 tests pass. S5 hosts: Lab and WSL 3.4, Mac 3.8, Sherlock 3.7 (login env), Marlowe 3.6a (login env; `/usr/bin/tmux` 3.2a still answers non-interactive shells). Linux CI installs apt tmux 3.4 with `DOTFILES_TEST_REQUIRE_TMUX=1`, so a missing or older tmux fails | S2 map unchanged files; S5 floor change shipped with `tools.tsv`, `hpc-login-env.yml`, config, tests and docs; Marlowe's login env gained tmux 3.6a through person-approved Slurm jobs before landing. Older tmux is unsupported |
| Claude Code / presence-only | Keep both plugin IDs and root import stub. Candidate >=2.1.285 needs actual supported-client/ancestor tests; deleting a portable key does not delete live-only state. S5 kept both IDs and the stub: no client floor was verified | [Official memory docs](https://code.claude.com/docs/en/memory#agentsmd): >=2.1.277 native AGENTS feature, >=2.1.281 broader sessions; 2.1.285 ID compatibility | No application startup/version/auth probe; no client floor proved. S5 observed Marlowe's client stuck at 2.1.150 (a recorded finding, not a floor) | S3 resolve merge/client policy; S5 update tools/provisioning and tests if benefit shown (none shipped); keep Windows missing-kit guards |
| Bash / 3.2 compatibility, manifest presence-only | Retain 3.2; associative arrays/mapfile could simplify code, but no surviving benefit demonstrated. Keep no-heredoc/check guarantees. S5 kept 3.2: macOS `/bin/bash` is 3.2.57 and day-zero setup-host runs before Homebrew exists | [GNU Bash redirections](https://www.gnu.org/software/bash/manual/html_node/Redirections.html) and local native help; upstream page retrieval timed out, so no new compatibility inference | Bash 5.2.21, zsh 5.9; `bash tests/shell-profile.sh`: PASS. No Bash 3.2 run here; the macOS CI job runs `/bin/bash` | S5 only if justified: provision macOS and change actual shebang/CI invocations; Homebrew installation alone does not replace `/bin/bash` (not justified in S5) |
| Python / 3.11 | Retain 3.11 for stdlib tests and tmux metrics; remove merge-runtime need, not Python itself. S5 kept 3.11 | [Python 3.11 tomllib](https://docs.python.org/3.11/library/tomllib.html) establishes the stdlib parser and TOML value mapping | Python 3.15.2; inventory generation/check and tmux stdlib suite exercised. Linux CI runs Python 3.11 | S1 tests use existing Python; S3 native transforms must work without child Python; S6 remove venv/runtime prerequisites, update floor rationale |
| Stow / 2.3.1 Unix | Retain existing floor through bridge, then retire dependency. No benefit in bumping an outgoing tool | [GNU Stow invocation manual](https://www.gnu.org/software/stow/manual/html_node/Invoking-Stow.html); retrieval timed out; local 2.4.1 `--help` confirms current interface, not 2.3.1 parity | Stow 2.4.1 version/help only in this worker; historical 2.3/2.4 tests remain legacy evidence | S6 remove manifest/package/CI prerequisite and installer suites with all callers; do not change Stow version semantics in S1 |
| PowerShell / 7.0 entrypoints, 5.1 profile | Retain both current distinctions; replacing Stow removes link-trust repair, not Windows support or profile semantics. S5 kept 7.0: a claimed 7.1 need of W1-chezmoi was false (.NET Core 3.1 already has both `FileSystemAclExtensions.Create` overloads) and its gates were removed (`72c8346`, `934041e`). Pre-existing 7.2 dependencies, not fixed: the profile sets `$PSStyle` unguarded and the legacy `Test-SetupStowed` reads `LinkTarget` (.NET 6) | [Microsoft about_Requires](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_requires?view=powershell-7.5), [profiles](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles) | pwsh unavailable; native Windows profile discovery/ACL/version tests deferred, never inferred from Linux rendering. S5 Windows CI (windows-2025) runs its hosted pwsh, not 7.0; the win host has pwsh 7.6.9 | S2/S4 use native Windows CI and host checks; S5 higher floor only for a demonstrated surviving feature (none shipped) |
| External jq / presence-only CLI | Keep ordinary CLI tool; native AI merge must not invoke it | [chezmoi builtin jq function](https://www.chezmoi.io/reference/templates/functions/jq/) | Native merge probes owned by coordinator/native worker, not run here | S3 restricted child PATH proves merge independence; S5 package choice remains separate |
| tomlkit / existing pinned requirements | No new floor; temporary legacy-only parser dependency | Existing `requirements-sync.txt` and [native fromToml](https://www.chezmoi.io/reference/templates/functions/fromToml/) define transition roles | No new package/environment provisioned | Keep legacy provisioning until S6; native deploy never imports it |

Evidence correction for later stages: current repository prose reverses the
Claude plugin-ID rename. The official memory page checked 2026-11-02 says
**before 2.1.285: `agents-md@builtin`; current: `cc-plugin-agents-md@builtin`**,
and >=2.1.285 accepts either. Preserve both entries now; fix future support prose
from the primary source before selecting a deletion. This does not justify
removing native ancestor loading, the cheap CLAUDE import stub or Codex's
fallback for other repositories' CLAUDE instructions.

## Secret consumer classification without secret reads

This is a public interface inventory, not the private per-account enrollment
inventory. Planning metadata reports twelve regular 0600 files in a 0700
`.secrets` directory; this worker did not re-enumerate or read it. File extensions
do not prove credential type. Installed kit source was read without invoking
its launchers: the local public install resolves to **v0.6.0**, while the
repository manifest selects channel 0.7. Recheck the actual 0.7 public consumer
interface before S4 enrollment; do not modify upstream refresh/copy behavior.

| Consumer / material | Default documented destination | Writer/type and rotation | Host scope and native treatment | Source authority |
| --- | --- | --- | --- | --- |
| `codex-as` account auth | `.secrets/codex-<account>.json`; account view's `auth.json` links to it | Mutable application auth. Codex refresh can replace/write auth; kit imports the refreshed result and restores the link. Native logout revokes/removes auth, so old snapshots must not be replayed | Kit exists on Unix roles only; actual account-to-host selection unverified. No recurring native target; optional seed only after explicit bootstrap lifecycle test | Installed v0.6.0 `lib/codex-as/{layout,launch}.py`, `Layout.repair`, `post_run`; documented app auth |
| `claude-as` explicit token account | `.secrets/claude-<account>` | Launcher enrolls through native setup-token, saves once, reads existing token and passes it via `CLAUDE_CODE_OAUTH_TOKEN`; this launcher implements no token refresh. Token expiry/revocation needs explicit issuer/launcher reenrollment; for an enrolled file follow the [rotation runbook](secrets-and-ssh.md#rotating-an-enrolled-static-token) | Potential static-for-consumer encrypted file, subject to selected 0.7 contract and per-host allowlist. Keep consumer path; no inference that every Claude auth file is static | Installed v0.6.0 `lib/claude-as/launch.py`, `enroll`, `save`, `main` |
| API/gateway/account secret consumed as a fixed file or environment value | Selected existing `.secrets` path, retained privately | Static only after its public consumer interface confirms no writeback; owner rotates through issuer and updates ciphertext/vault | Actual selection/hosts unresolved. Encrypt only explicit allowlist; do not derive a whole directory import from metadata | Consumer source/documentation required; not proved by a filename |
| Native Codex/Claude login store and OS keychain | Application/OS-selected auth locations | App-managed refresh/login/logout | Excluded on every role by default; preserve active state | [Codex auth](https://learn.chatgpt.com/docs/auth), [Claude authentication](https://code.claude.com/docs/en/authentication); see secrets-and-ssh.md |
| Account labels/usage metadata | Kit's state-directory `accounts/`, not secret directory | Launcher-owned changing metadata, not credential source | Unmanaged; do not include account names, labels or usage in public docs/logs | Installed v0.6.0 `lib/coding-agent-kit/{config,accounts}.py` |
| SSH connection snippets | `.ssh/config` and `config.d/*.conf` from the tracked rows | Declarative config; operator changes connection metadata | Existing role sets above retained. Optional encrypted private snippets require explicit endpoint/trust decision; Includes, jump/master settings and access stay intact | Tracked path structure and SSH conventions; no endpoint contents reproduced |
| SSH private keys / known_hosts / runtime | Host's existing `.ssh` state | User/SSH/agent own keys and host trust | Keys outside default distribution; known_hosts, sockets and caches unmanaged; no `exact_` or blanket remove | secrets-and-ssh.md and fleet-rollout.md |

Builtin age is the selected Stage 1 backend, with synthetic encrypt/decrypt,
private-mode, missing-identity and malformed-ciphertext tests integrated in
`tests/test_chezmoi_secrets.py`. The [official age interface](https://www.chezmoi.io/user-guide/encryption/age/)
supports native recipients/identities; its builtin backend has no SSH-key,
passphrase or symmetric support. No external age/daemon is required for that
backend. Do not mistake an SSH login identity for an age identity.

Proposed bootstrap boundary: generate a separate host age identity outside Git,
provision it locally or through an already authorized secure channel, and record
only public recipients. A shared recipient list grants each recipient access to
all ciphertext encrypted to that list; host templates/ignores do not restrict
decryption. Selected-release tests now prove explicit per-file recipient
override and multi-recipient access. Actual host trust grouping and initial
identity/recovery custody remain private enrollment choices. Do not
activate real secret distribution until that trust choice and recovery access
are explicit. An existing vault is an alternative only with a usable native
CLI/session on each selected host; none is assumed present here.

The private enrollment inventory must map selected records to opaque identifiers,
consumer/writer, path, host set, recipient group, rotation/revocation and source
authority without placing values into chat/source/logs. S3 uses synthetic values;
S4 establishes actual enrollment. A permanent encrypted `create_` seed can restore
a logged-out credential and is therefore not a default login-update target.
Neither native diff nor captured errors are a redaction boundary: use nonsecret
target allowlists for normal logs and CI and no production canaries in tests.

## Fleet handoff and honest validation scope

Carry the **six observed roles** from [fleet-rollout.md](fleet-rollout.md), checked
by the prior planning session on 2026-11-02 UTC. These are historical connection
results, not new inventory-worker host checks or migration evidence.

| Role | Recorded access baseline | Later-stage obligation / limit |
| --- | --- | --- |
| mac | Noninteractive SSH command succeeded | S4 recheck role/HOME/revision and native tools, apply/smoke and verify a fresh connection |
| wsl-ubuntu | Noninteractive SSH command succeeded | Distinct from native Windows HOME/checkout; prove independent writable state before parallel rollout |
| lab-ubuntu | Local context and Mac-to-lab SSH worked; self-SSH rejected | Operate locally or via verified Mac route; preserve local recovery, record self-SSH limit |
| sherlock | Existing user ControlMaster accepted commands and site-rule reads | Reuse authorized channel, reread current site/topic rules; no forced login/MFA or heavy work/environment creation outside allocation |
| marlowe | Existing user ControlMaster accepted a command | Recheck access and current site rules before installation; reused master does not prove new authentication |
| win | Fresh direct lab SSH succeeded after user key setup; Mac route available | Initial blocker resolved in planning; recheck direct route and native profile/ACL behavior. No key copying/agent forwarding |

Stages 4 and 6 are authorized to execute reachable-host migration and exact
retirement, with one owner per host and private recovery data. Do not leave
executable work as a user TODO or restore the superseded all-host waiting gate.
Specific authentication, privilege and site blockers still require the smallest
concrete user action; an offline host is not migrated by repository completion.
Recheck source checkout, shared storage/OneDrive, existing workers, selected
secret access and recovery channel before any write. Keep the old SSH session
until new access passes; a command over its master is not a fresh access test.

Per-host status belongs in `status.md`: starting/resulting revision, backup,
owner, tool version, secret access, ordinary/mutable apply, second apply,
shell/application smoke, new updater, fresh access or site limit, exact retired
targets and blocker. Native macOS/Windows test evidence and actual fleet evidence
remain separate from Linux fixture results. This inventory changes neither
default deployment nor real HOME.

## Reproducible inventory check

Run this from the repository root; it compares exact table sources, destinations,
host-set codes, executable modes, materialization exceptions and role totals to
the tracked index. No HOME or secret path is opened. A future package change
must update both the rows and counts rather than silently accepting a stale list.

```sh
python3 -I -B - <<'PY'
from pathlib import Path
import collections
import re
import subprocess

trees = ['common', 'mac', 'sherlock', 'wsl-ubuntu', 'lab-ubuntu', 'marlowe', 'win']
tracked = subprocess.check_output(['git', 'ls-files', *trees], text=True).splitlines()
text = Path('docs/chezmoi-migration/inventory.md').read_text(encoding='ascii')
rows = re.findall(r'^\| `((?:common|mac|sherlock|wsl-ubuntu|lab-ubuntu|marlowe|win)/[^`]+)` \| `~/([^`]+)` \| ([^|]+) \| ([OEMXPC]) \| ([^|]+) \| ([^|]+) \| ([^|]+) \|$', text, re.M)
assert len(rows) == len(tracked) == 95
assert collections.Counter(row[0] for row in rows) == collections.Counter(tracked)
windows = {'claude', 'codex', 'conda', 'git', 'ssh', 'wezterm'}
roles = ['common-only', 'mac', 'wsl-ubuntu', 'lab-ubuntu', 'sherlock', 'marlowe', 'win']
targets = {role: set() for role in roles}
native = {role: set() for role in roles}
for source, dest, hosts, category, representation, owner, removal in rows:
    role, package, relative = source.split('/', 2)
    assert dest == relative
    expected = ('A' if package in windows else 'U') if role == 'common' else role
    assert hosts.strip() == expected
    selected = roles if hosts.strip() == 'A' else roles[:-1] if hosts.strip() == 'U' else [role]
    for host in selected:
        assert dest not in targets[host]
        targets[host].add(dest)
        if category != 'C':
            native[host].add(dest)
assert [len(targets[h]) for h in roles] == [52, 59, 58, 63, 57, 57, 29]
assert [len(native[h]) for h in roles] == [49, 56, 55, 59, 54, 54, 26]
exceptions = {'common/claude/.claude/settings.json', 'common/codex/.codex/config.toml', 'common/codex/.codex/rules/portable.rules', 'lab-ubuntu/fcitx5/.config/fcitx5/profile'}
assert exceptions <= set(tracked)
modes = subprocess.check_output(['git', 'ls-files', '--stage', *trees], text=True).splitlines()
assert sum(line.startswith('100755 ') for line in modes) == 6
assert not any(p.endswith('/.stow-local-ignore') for p in tracked)
assert len([p for p in tracked if p.startswith('common/tmux/')]) == 5
print('inventory=PASS: 95 exact rows; seven host sets; four exceptions; six executable modes; five tmux files')
PY
```
