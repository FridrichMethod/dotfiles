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
   gives the command). On win run that update in a limited-token task. An
   ordinary noninteractive task does not run the profile's update hook; the
   separate console procedure below proves the hook itself
   ([PowerShell 7 console acceptance](#powershell-7-console-acceptance)). A
   change that needs a re-init, a directory preparation or the pre-pull
   updater out of the way follows that procedure as a whole.
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

A rollout reloads no running tmux server: a change to the tmux config reaches
one only through `tmux source-file ~/.tmux.conf`, while a new server loads it
itself ([tmux](shell.md#tmux)).

## Probe methods

Probes are read-only: chezmoi `status --exclude=dirs` (names only),
`diff --exclude=dirs,encrypted`, `managed`, `data` and `execute-template`, and
`cat` of the two AI config targets only, compared without printing them. A
differing encrypted target is reviewed privately, never in captured output
([secrets](secrets.md#output-and-failure)). Other probes: the offline doctor
(`./doctor.sh --host H --tsv`; on win `.\doctor.ps1 -Tsv`), `git status` and
`git rev-parse`, `codex-as --version` for the kit on Unix, and
`DOTFILES_AUTO_UPDATE=0 bash -ic true` and
`DOTFILES_AUTO_UPDATE=0 POWERLEVEL9K_INSTANT_PROMPT=off zsh -ic true` for
the shells, with stdout captured rather than attached to a terminal. Set
`POWERLEVEL9K_INSTANT_PROMPT=off` for doctor `--smoke` too. This combination
keeps Oh My Zsh's independent updater from running during probes; the legacy
`DISABLE_AUTO_UPDATE` variable alone is ineffective because the shared rc
explicitly selects `:omz:update` mode `auto`. Every interactive shell a probe starts on a remote host
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
- sherlock: through `sherlock-plain`, first use a login Bash (`bash -lc`)
  to initialize the site's Lmod environment, then the login env's interactive
  zsh, with those outer shells' own updaters off. A bare non-login SSH command
  can omit Lmod and falsely report the site-provided Node and AI tools missing.
- marlowe: inside the micromamba login env, from its interactive login zsh
  (`$HOME/micromamba/envs/login/bin/zsh -il`, reached through `marlowe-plain`
  or `ssh -o RemoteCommand=none marlowe`), with that outer shell's updater
  off; a bare `marlowe-plain` command sees the system tools.
- win: a one-off limited-token task ([win](#win)) checks that the PowerShell
  7 and Windows PowerShell 5.1 profiles parse and load. For a noninteractive
  updater check, dot-source the configured source's `lib/chezmoi-guard.ps1`
  and `scripts/chezmoi-update.ps1`, then call
  `Invoke-DotfilesChezmoiUpdate`, with `DOTFILES_AUTO_UPDATE` and
  `_DOTFILES_CHECKED` absent. Invoking the script with `&` alone does nothing
  when output is redirected. Prove the normal profile's hook in a separate
  ordinary-user console by
  [PowerShell 7 console acceptance](#powershell-7-console-acceptance).

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
  Capture its output on that run; never rerun a task driver merely to read
  the result, since that re-executes the task and replaces its log.
- Codex's sandbox can grant `CodexSandboxUsers` Modify on `~/.local`; inherited
  by `chezmoi.exe`, that grant makes the login updater refuse the binary. After
  confirming that plain `icacls` lists no such entry,
  `icacls "$HOME\.local\bin\chezmoi.exe" /inheritance:d` turns the inherited
  entries into explicit ones, so a later propagation cannot add it. For the
  same reason keep private records under `~/.config`, not `~/.local`.
- A task's noninteractive process does not run the profile's interactive
  setup or login hook. An Interactive-logon, Limited-token task can launch a
  separate real console under that same ordinary user, as below.

### PowerShell 7 console acceptance

Use a one-off task with the identity and lifetime above to launch a separate
`pwsh -NoLogo -NoExit` in a new console in the logged-on desktop session,
through `conhost.exe`: win's default terminal is Windows Terminal, and the
checks below read a classic console's screen buffer.
The child loads the normal profile. For a hook proof, remove
`DOTFILES_AUTO_UPDATE` and `_DOTFILES_CHECKED` from its inherited environment
and require maintenance to be absent; then verify the hook was attempted.
Keep these checks confined to the console created for this run:

1. Record the child's PID and session ID, and require `Elevated=false`,
   `InputRedirected=false` and `OutputRedirected=false`. Task settings alone
   do not establish these properties of the child.
2. Attach the controller only to that child's console. Never attach to an
   existing user console or capture the user's history. Use benign synthetic
   input with per-process `HistorySaveStyle=SaveNothing`: start each typed
   line with a space, which the profile keeps out of the history file, and
   let the first one set it. Seed a history suggestion only after the first
   `ReadLine` has initialized history, and record only list rows of the
   probe's own seed or of the plugin, since other rows can come from the
   user's history. A built-in completion such as `Get-Date -Form` tests
   CompletionPredictor without relying on an ad-hoc function reaching its
   separate runspace.
   Type that input one key at a time: keys written to the input buffer in
   one batch reach PSReadLine without a plugin suggestion appearing. In the
   list view, the first Escape closes the list and a second one reverts the
   line.
3. Inspect the created console's screen buffer for both history and plugin
   suggestions in `HistoryAndPlugin` / `ListView`. Check that the directory
   style equals `Bold+Blue` and a synthetic directory marker renders with
   foreground attribute 9. Record only these nonsecret results.
4. Require no `[dotfiles]` startup warning, an attempted profile update
   hook, empty full-argument `chezmoi status --exclude=dirs`, a clean Git
   checkout at the expected revision and no maintenance marker.
5. Exit the child, unregister every task the probe created, and confirm its
   processes are gone. Remove only its exact temporary files and empty
   directory under the ordinary token. Record the nonsecret conclusions here
   as current-state statements, then remove the completed probe's local logs,
   hashes and copied artifacts. Confirm no probe task, process or temporary
   directory remains.

The procedure passes on win with PowerShell 7.6.9, PSReadLine 2.4.5 and
oh-my-posh 32.0.0: every check above holds, and CompletionPredictor and
Microsoft.WinGet.CommandNotFound load through the normal idle hook. Rerun it
after a change to that profile or to the update hook it runs; until then the
change has fixture and CI evidence only. The procedure is evidence for
the existing home's console, not fresh-machine acceptance, which is the
separate [bootstrap gate](bootstrap.md#acceptance-checklist).

### Ordinary-token candidate checks

To test a candidate (the commit pushed to a `ci/**` branch before it lands,
[AGENTS.md](../AGENTS.md#workflows-and-checks)) under the ordinary token, use
a one-off task with the identity and lifetime above. Its script runs a
hash-recorded bundle of the candidate's public files from a separate
temporary directory and records the PowerShell version, the session ID and
`Elevated=false`; the host's source checkout stays clean and unchanged. The
check is run by hand, deploys nothing, does not replace the console
procedure above and is not fresh-machine acceptance. A run covers only the
files of the candidate it tested.

The check passes with PowerShell 7.6.9, Python 3.12 and oh-my-posh 32.0.0:
both updater culture tests of `tests/test_chezmoi_update_windows.py` run
without skips and pass, and the complete `tests/powershell-profile.ps1`
suite passes without skips, including the history cases under all three
cultures and the oh-my-posh prompt rendering. Rerun it after a change to
those tests or to the profile and updater they test.

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
  project, not a Git repository, whose `pyproject.toml` and `uv.lock` pin the
  sherlock-kit v0.6.0 release tag. Call its absolute `.venv/bin/shk`, never `uv run`, with
  that directory as the working directory, and read `shk rules workstation`
  before using it; `shk doctor` checks the existing master. Dotfiles pins no
  sherlock-kit and installs no `shk`, rules or skill.
- Sherlock's glibc 2.17 runs only the official static musl chezmoi, which
  S4-chezmoi selects.
- An interactive zsh on a login node starts no ssh-agent: only the
  lab-ubuntu and wsl-ubuntu plugin lists load it.
- The site's `~/.cache` symlink is intentional. The skills installer rejects
  symlink ancestors, so use its supported legacy cache-path option for manual skills
  updates inside an allocation:
  `SKILLS_CACHE_DIR="$SCRATCH/.cache/awesome-skills" sync-payloads skills`.
  This option selects the old snapshot cleanup path, not the active library
  clone. The installed payload and login environment stay in the home. The
  option is per invocation and is not persisted by the installer. Preserve
  the cache symlink and the installer's path guards.

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

## Provisioning state

The six existing homes are provisioned through setup-host, after its
`--check` plan, and through the canonical payload command (`sync-payloads`,
or `scripts/payload-update.* --now`); S3-clones clones only missing
repositories and leaves existing clones alone. On sherlock and marlowe,
packages missing from an existing login env are added as described below the
table. This is existing-host provisioning, separate from
[fresh-machine acceptance](bootstrap.md#acceptance-checklist).

The rows record each host's provisioning checks; they are not rerun at every
landing. A host's current state is what its probes report
([Probe methods](#probe-methods)), and step 4 of
[Rolling out a landed change](#rolling-out-a-landed-change) accepts a rollout
only when no doctor row is worse than before.

| Host | Default tiers (`core,cli,ai`) | Warnings and exceptions |
| --- | --- | --- |
| lab-ubuntu | Complete; setup-host has nothing to install; the offline doctor passes. | None. |
| wsl-ubuntu | Complete, with the tmux plugin clones from S3-clones; the doctor and `--smoke` pass and a repeated scoped `--check` has nothing left. | None. |
| mac | Complete, with zsh-completions and the tmux plugin clones from S3-clones and both Vim state directories from S3-dirs; the doctor, `--smoke` and the full setup check pass. | kitty (`desktop`), StyLua (`contributor`) and Schrodinger (`host`) warn; those tiers are not installed there. |
| sherlock | Complete. The existing login env includes git-lfs, git-delta, tealdeer and Chafa, with libxml2 and libxml2-16 held at 2.15.4 for ICU compatibility; zsh-completions, the tmux plugin clones, the bat theme and the Vim state directories come from S3-clones, S3-bat-theme and S3-dirs. The full setup check passes, and on a compute node the doctor with `--smoke` passes with three warnings. awesome-skills manages every skill directory under both clients' roots except Codex's own `.system`. | The three warnings are the optional `contributor` pre-commit, shfmt and StyLua; the login env lacks the yml's pre-commit and go-shfmt. |
| marlowe | Complete except `node` (`ai`), which the login env provides but `block-node` denies on login nodes ([Marlowe](#marlowe)). The existing login env includes git-lfs, git-delta, tealdeer, aria2 and uv; zsh-completions, the tmux plugin clones, the bat theme and the Vim state directories come from S3-clones, S3-bat-theme and S3-dirs. A repeated scoped setup installs nothing; the full check, the doctor and `--smoke` pass. | On a login node the doctor warns for `node` and five optional rows: the `contributor` pre-commit, shfmt, shellcheck and StyLua and the separate Miniconda (`host`); a compute node warns only for the five. The login env lacks the yml's pre-commit, go-shfmt and shellcheck. |
| win | Complete under the ordinary token: the offline doctor reports every row `ok`, the `payloads` row with `installed: pymol, skills`; setup `-Check` and a repeated setup `-Yes` exit 0, printing HUMAN blocks only. Codex and oh-my-posh are on the ordinary user's PATH. | None. |

On win the administrator SSH session's PATH lacks Codex, so a Codex `missing`
row from a doctor run there does not mean the ordinary user lacks it.

On sherlock and marlowe an existing login env makes setup-host report
S2-login-env done, which does not show that every package of
`config/bootstrap/hpc-login-env.yml` is present
([S2-login-env](bootstrap.md#s2-login-env-hpc-login-environment)). A missing
package is added to the existing env inside a Slurm allocation, never under
`$SCRATCH`, from a reviewed selective package plan instead of the whole-yml
`install`: the plan leaves every existing package's version and build
unchanged unless a reviewed dependency requires a change, as with sherlock's
libxml2 builds. S3-clones, S3-bat-theme, S3-dirs and the payload's own
installer supply the rest. Provisioning bypasses neither Marlowe's
`block-node` restriction nor the skills installer's ownership, capacity and
path guards.

awesome-skills' installer manages only the skill directories its ownership
manifests record and preserves any other, so a copy installed without a
record stays until a person removes it. Each host's payload ownership
manifests, library checkouts and lock files are part of the installation,
not diagnostics to clean up.

## Known limits

- win: OpenSSH's default shell there is PowerShell 7 with no
  DefaultShellCommandOption, so every SSH command loads the PowerShell 7
  CurrentUserAllHosts profile under the administrator token, non-interactively
  (no setup block, no update hook). Only a limited-token task proves the
  ordinary user's noninteractive profile load and updater; the normal hook
  and rendered predictions require its separate ordinary-user console
  ([PowerShell 7 console acceptance](#powershell-7-console-acceptance)).
- mac: the macOS CI job installs no tmux, so `tests/tmux.sh`'s real-tmux
  `TmuxConfiguration` cases skip there and its green result alone is not tmux
  evidence. Linux CI runs the suite with tmux 3.4. On the real mac host with
  tmux 3.8 all 16 tests pass without skips, including the six
  quoted-directory/action menu cases. A change to the tmux config or to
  `tests/test_tmux.py` is verified on macOS only by rerunning `tests/tmux.sh`
  on the mac host.
- Container and hosted-runner runs are not fresh-machine acceptance
  ([Acceptance checklist](bootstrap.md#acceptance-checklist)).
