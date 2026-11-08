# Hosts

Six homes run these dotfiles, each from its own clone at `~/dotfiles` and
with its own role in `[data].host`:

| Host | Machine | Access from lab-ubuntu |
| --- | --- | --- |
| `lab-ubuntu` | the Ubuntu lab desktop | local |
| `wsl-ubuntu` | WSL `Ubuntu` on the Windows machine, with a clone separate from `win`'s | ordinary SSH |
| `mac` | macOS | ordinary SSH |
| `sherlock` | Stanford Sherlock, a login node | the user's existing SSH control master |
| `marlowe` | Marlowe, a login node | the user's existing SSH control master |
| `win` | native Windows | SSH as an administrator, for the limited uses below |

[AGENTS.md](../AGENTS.md#workflows-and-checks) lets agents roll a landed
change out to these hosts by this page. Use only existing access: never log
in, authenticate or answer MFA for the user, never copy a private key between
hosts, and keep agent forwarding off. Re-resolve SSH aliases each session; do
not hardcode addresses. A host that is asleep, logged off or without its
master is a concrete blocker to report, not a reason to work around it.
The authority covers the procedures on this page and in
[Login updates](updates.md) and their checks only: no privilege
escalation, no reset or discard of local Git work, no removal of payload
checkouts or other unrelated cleanup, and only these six destinations, never
another account or alias.

## Rolling out a landed change

Every host takes `main` at its next interactive login, through its login
updater ([Login updates](updates.md)). To roll a change out without waiting,
or one that needs more than the update:

1. One owner per host; run hosts one at a time, Lab first.
2. Probe the host as below and record its HEAD, managed count and doctor rows
   first, so a later row can be compared with this one instead of with zero.
3. Let the login update run (start the host's interactive shell with
   `DOTFILES_AUTO_UPDATE` unset; on lab-ubuntu also `_DOTFILES_CHECKED`, as
   in the hook proof below), or run from the checkout the update the login
   updater runs, with its mode flags (step 3 of
   [Rolling out a breaking change](updates.md#rolling-out-a-breaking-change)
   gives the command). On win always run that update, in a limited-token
   task: a task opens no interactive session, so the profile's update hook
   does not run there. A change that needs a re-init, a directory preparation
   or the pre-pull updater out of the way follows that procedure as a whole.
4. Accept the host: HEAD is `main`, full-argument `status --exclude=dirs` is
   empty, the managed count is the expected one, both AI configs equal
   `chezmoi cat` of their targets (record only equal or not equal), no doctor
   row is worse than before, the shell probes pass and no maintenance marker
   is left.
5. Once every host is accepted and the landing's `ci/**` and `e2e-ci/**`
   branches are deleted ([AGENTS.md](../AGENTS.md#workflows-and-checks)),
   prune each host's checkout as step 5 of
   [Rolling out a breaking change](updates.md#rolling-out-a-breaking-change)
   says: `git -C ~/dotfiles fetch --prune origin` on Unix. The login
   updater's pull never prunes, so a host that fetched while those branches
   existed keeps their `origin/ci/*` and `origin/e2e-ci/*` refs otherwise.
   The fetch moves no local branch. On win run
   `git -C (Join-Path $HOME dotfiles) fetch --prune origin` in a limited-token
   task: it writes Git metadata, and the administrator session is for
   read-only metadata ([win](#win)).

Before a change to rendered `~/.codex/config.toml`, ask the user to quit the
Codex desktop apps that connect to the hosts
([Reconciling an owned key](ai-config.md#reconciling-an-owned-key)).

## Probe methods

Probes are read-only: chezmoi `status --exclude=dirs` (names only),
`diff --exclude=dirs,encrypted`, `managed`, `data` and `execute-template`, and
`cat` of the two AI config targets only, compared without printing them. A
differing encrypted target is reviewed privately, never in captured output
([secrets](secrets.md#output-and-failure)). Other probes: the offline doctor
(`./doctor.sh --host H --tsv`; on win `.\doctor.ps1 -Tsv`), `git status` and
`git rev-parse`, `codex-as --version` for the kit on Unix, and
`DOTFILES_AUTO_UPDATE=0 bash -ic true` and `DOTFILES_AUTO_UPDATE=0 zsh -ic
true` for the shells. Every interactive shell a probe starts on a remote host
sets `DOTFILES_AUTO_UPDATE=0`: a remote shell does not inherit
`_DOTFILES_CHECKED`, so it would otherwise run the real login update.
Conversely, shells an agent starts on lab-ubuntu inherit
`_DOTFILES_CHECKED=1`, so a plain shell there proves nothing about the hook.

To prove the login hook itself, start a login-equivalent shell with the
session guard and the opt-out removed and stdin closed:

```sh
env -u _DOTFILES_CHECKED -u DOTFILES_AUTO_UPDATE -u ENV sh -i -c '. "$HOME/.profile"' </dev/null
```

It passes with exit 0, no `[dotfiles]` line on stderr (sh prints its own
no-terminal job-control notice), HEAD at `main` and a clean status. Per host:

- lab-ubuntu, wsl-ubuntu: as above.
- mac: a non-login SSH command first runs `. /etc/profile; . ~/.profile`, so
  PATH matches a login shell (`path_helper`).
- sherlock: through `sherlock-plain`, from the login env's interactive zsh,
  with that outer shell's own updater off.
- marlowe: inside the micromamba login env, from its interactive login zsh
  (`$HOME/micromamba/envs/login/bin/zsh -il`, reached through `marlowe-plain`
  or `ssh -o RemoteCommand=none marlowe`), with that outer shell's updater
  off; a bare `marlowe-plain` command sees the system tools.
- win: a one-off limited-token task ([win](#win)) checks that the PowerShell
  7 and Windows PowerShell 5.1 profiles parse and load, then runs what the
  profile's update hook runs: the source's `lib/chezmoi-guard.ps1` and its
  `scripts/chezmoi-update.ps1`. The hook itself runs only in an interactive
  console, which a task does not have, so the user checks it in a session of
  their own.

## win

- Everything that writes the home runs under the user's ordinary, limited
  token: managed targets, the chezmoi config and state, and the ACL of
  `~/.local/bin/chezmoi.exe`. The administrator SSH session writes none of
  them and changes no ACL.
- The administrator session is for read-only metadata, and for writing,
  registering, starting and deleting a one-off scheduled task.
- A one-off task runs as the logged-on user with LogonType Interactive and
  RunLevel Limited, has no trigger, is started once with
  `Start-ScheduledTask` and is unregistered after the run. Its script is a
  hash-checked copy, refuses an elevated token and logs only nonsecret lines.
  It needs the user logged on. Never register an elevated or recurring task.
- Codex's sandbox can grant `CodexSandboxUsers` Modify on `~/.local`; inherited
  by `chezmoi.exe`, that grant makes the login updater refuse the binary. After
  confirming that plain `icacls` lists no such entry,
  `icacls "$HOME\.local\bin\chezmoi.exe" /inheritance:d` turns the inherited
  entries into explicit ones, so a later propagation cannot add it. For the
  same reason keep private records under `~/.config`, not `~/.local`.
- A task cannot open an interactive console: checks that need one are the
  user's ([Known limits](#known-limits)).

## Sherlock

- Before any Sherlock work, and again after a summary or compaction, read
  `/etc/agents/AGENTS.md` and its topic files (`policy.md`, `storage.md`,
  `software.md`, `slurm.md`) through the existing control master
  (`ssh -oBatchMode=yes -oProxyCommand=false sherlock-plain cat
  /etc/agents/AGENTS.md`). Their numbered site rules take precedence.
- On a login node run only light foreground commands: no job, detached
  process, supervisor or environment build there. HPC environments are built
  only inside a Slurm allocation, never under `$SCRATCH`.
- The controller for jobs, status and transfers is
  `~/.local/share/chezmoi-sherlock-kit-provisioning` on lab-ubuntu: a plain uv
  project, not a Git repository, that pins sherlock-kit v0.6.0, which its
  `uv.lock` resolves to sherlock-kit commit `09a37281`. Call its absolute
  `.venv/bin/shk`, never `uv run`, with that directory as the working
  directory, and read `shk rules workstation` before using it; `shk doctor`
  checks the existing master. Dotfiles pins no sherlock-kit and installs no
  `shk`, rules or skill.
- Sherlock's glibc 2.17 runs only the official static musl chezmoi, which
  S4-chezmoi selects.
- An interactive zsh on a login node starts no ssh-agent: only the
  lab-ubuntu and wsl-ubuntu plugin lists load it.

## Marlowe

- Marlowe publishes no `/etc/agents` rules; read its site documentation
  before an installation or a substantive change.
- Interactive login shells put the micromamba login env (`$HOME/micromamba`,
  env `login`) first. Non-interactive shells, such as `ssh marlowe-plain
  CMD`, see the system tools: `/usr/bin/tmux` there is below the 3.4 floor,
  so start tmux and run the doctor from an interactive login shell.
- The site AppArmor profile `block-node` denies `node` (and some IDE and agent
  binaries) on login nodes; never work around it. The three Claude Code
  commands that run the kit's Node helpers (the Git hook check, Notification
  and statusLine) exit 127 there, which Claude Code treats as a non-blocking
  hook error: no status line, notifications or usage records. That is
  accepted, with no Marlowe-specific settings. The Codex CLI is not on PATH,
  but Codex app-servers run there and read the deployed Codex config.
- The filesystem keeps extended ACLs (`+` in `ls -l`) and refuses to preserve
  permissions or ACLs on copy: never `cp -p`; a copy made under umask 077 is
  private.
- Never assume `$0` is a file over SSH: a script sent as
  `sh -c "$script" probe` sees `$0` as `probe`.
- Changes to the login env run in a Slurm job, never on a login node.

## Known limits

- win: whether an interactive PowerShell 7 session shows history and plugin
  predictions in the list view and directories in bold blue is checked by the
  user in a session of their own; a scheduled task cannot open one.
- win: OpenSSH's default shell there is PowerShell 7 with no
  DefaultShellCommandOption, so every SSH command loads the PowerShell 7
  CurrentUserAllHosts profile under the administrator token, non-interactively
  (no setup block, no update hook). Only a limited-token task proves the
  ordinary user's profile load and updater; the update hook runs only in the
  user's own interactive session.
- mac: under tmux 3.8, three quoted-directory subtests of
  `test_menu_actions_preserve_quoted_directory_without_executing_its_text` in
  `tests/test_tmux.py` fail, while the other test methods pass; this is the
  recorded baseline, not a pass. The macOS CI job installs no tmux; Linux
  CI runs the tmux tests with tmux 3.4.
- sherlock, marlowe: the doctor reports rows the login env does not provide
  and missing tmux plugin clones; wsl-ubuntu and mac report missing tmux
  plugin clones too. They are no regression of a rollout: compare with the
  host's previous doctor run.
- Container and hosted-runner runs are not fresh-machine acceptance
  ([Acceptance checklist](bootstrap.md#acceptance-checklist)).
