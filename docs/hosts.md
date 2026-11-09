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
- The user-approved deletion of five exact administrator-owned TEMP
  directories on 2026-11-08 was a one-time exception for those paths. It
  grants no general administrator cleanup or privilege-escalation authority.

### PowerShell 7 console acceptance

Use a one-off task with the identity and lifetime above to launch a separate
`pwsh -NoLogo -NoExit` in a new console in the logged-on desktop session.
The child loads the normal profile. For a hook proof, remove
`DOTFILES_AUTO_UPDATE` and `_DOTFILES_CHECKED` from its inherited environment
and require maintenance to be absent; then verify the hook was attempted.
Keep these checks confined to the console created for this run:

1. Record the child's PID and session ID, and require `Elevated=false`,
   `InputRedirected=false` and `OutputRedirected=false`. Task settings alone
   do not establish these properties of the child.
2. Attach the controller only to that child's console. Never attach to an
   existing user console or capture the user's history. Use benign synthetic
   input with per-process `HistorySaveStyle=SaveNothing`; seed a history
   suggestion only after the first `ReadLine` has initialized history. A
   built-in completion such as `Get-Date -Format` tests CompletionPredictor
   without relying on an ad-hoc function reaching its separate runspace.
3. Inspect the created console's screen buffer for both history and plugin
   suggestions in `HistoryAndPlugin` / `ListView`. Check that the directory
   style equals `Bold+Blue` and a synthetic directory marker renders with
   foreground attribute 9. Record only these nonsecret results.
4. Require no `[dotfiles]` startup warning, an attempted profile update
   hook, empty full-argument `chezmoi status --exclude=dirs`, a clean Git
   checkout at the expected revision and no maintenance marker.
5. Exit the child, unregister every task the probe created, and confirm its
   processes are gone. Remove only its exact temporary files and empty
   directory under the ordinary token, retaining nonsecret results and script
   hashes. Confirm no probe task, process or temporary directory remains.

This passed on 2026-11-08 at `360a269`: PowerShell 7.6.9, PSReadLine 2.4.5,
`HistoryAndPlugin` / `ListView`, a rendered seeded history suggestion and a
rendered Completion plugin `Get-Date -Format` suggestion. The directory
style matched `Bold+Blue` and its marker had foreground attribute 9.
CompletionPredictor and Microsoft.WinGet.CommandNotFound loaded through the
normal idle hook. The profile update hook was attempted without a
`[dotfiles]` startup warning; chezmoi status and Git were clean and maintenance
was absent. The child exited and all probe tasks, processes and temporary
files were removed. Nonsecret `result.json`, `cleanup.json` and script hashes
are retained on lab-ubuntu under
`~/.local/state/dotfiles-validation/20261108-ps7/`. This establishes the
existing home's console behavior; fresh-machine acceptance remains the
separate [bootstrap gate](bootstrap.md#acceptance-checklist).

### Ordinary-token candidate checks

On 2026-11-09, a user-approved one-off Limited-token task tested a
hash-recorded bundle of 13 public files from candidate `c19a83f`. The task
recorded PowerShell 7.6.9, SessionId 1 and `Elevated=false`. Both updater
culture tests executed without skips and passed; the complete
`tests/powershell-profile.ps1` suite passed, including history cases under all
three cultures and oh-my-posh prompt rendering. The existing home's offline
doctor and setup `-Check` both exited 0. Codex was present on the ordinary
user's PATH, resolving the earlier administrator-SSH absence as a PATH
difference; oh-my-posh 31.9.1 also passed there.

The host source remained clean at `360a269` before and after these checks;
the candidate files were tested in a separate temporary directory. This
did not deploy the candidate, rerun the separate interactive-console proof
or close a fresh-machine acceptance gate. Nonsecret results, logs and the
bundle manifest are retained on lab-ubuntu in the checkout's
`.git/followup-20261109/approved-native2-*` evidence files.

The skills payload was genuinely absent; its own dry-run required an initial
library clone. The approved ordinary-token
`scripts/payload-update.ps1 -Now skills` run then exited 0. Its installer
copied 2,346 skills per client, removed none, and selected one visible skill
with 2,345 hidden. Two subsequent setup `-Yes` runs, setup `-Check` and the
offline doctor all exited 0; all 33 doctor rows were `ok`, including
`payloads` with `installed: pymol, skills`. HUMAN blocks were printed only.
Source remained clean at `360a269`, chezmoi status was empty, managed counts
were 26 files and 43 total entries, both AI configs matched their rendered
targets, and maintenance was absent. The install evidence is retained beside
the candidate checks as `approved-skills-install-*`.
The five created tasks were unregistered, and ordinary-token cleanup removed
their temporary files and directories; no validation process remained. A
nonsecret cleanup receipt is retained at
`~/.config/dotfiles-validation/20261109-approved-cleanup.json`.

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

## Provisioning follow-up

The 2026-11-09 inventory used the existing homes, not fresh-machine fixtures.
New acceptance environments and allocations were unavailable at that inventory.
The user later waived genuine fresh-machine acceptance for this follow-up;
the [five cases](bootstrap.md#acceptance-checklist) remain not run and are not
follow-up blockers. Existing-host provisioning and its allocation requirements
remain separate. Tool provisioning used the existing setup-host entry point after
its scoped `--check`; payload installation used its canonical update command.
Existing clones and package versions were left alone. No
running user tmux server was reloaded.

| Host | Changes and result | Remaining classification |
| --- | --- | --- |
| lab-ubuntu | No installation needed; offline doctor passes. | None in the selected tiers. |
| wsl-ubuntu | S3-clones installed the 11 missing tmux plugins; doctor and smoke pass, and the scoped second plan is done. | None in the selected tiers. |
| mac | S3-clones installed zsh-completions and the 11 tmux plugins; S3-dirs created the two missing Vim state directories. Doctor, smoke and the full setup check pass. | Optional kitty, StyLua and Schrodinger warnings remain; these unselected tiers were not installed. |
| sherlock | Read-only inventory; no environment changes without an allocation. | Required: git-lfs, git-delta, tealdeer (tldr), chafa, zsh-completions, 11 tmux plugins and the bat theme. The skills payload is missing. Contributor pre-commit, shfmt and StyLua remain optional. |
| marlowe | Read-only inventory; no environment changes without an allocation. | Required: git-lfs, git-delta, tealdeer (tldr), aria2, uv, zsh-completions, 11 tmux plugins and the bat theme. Node on the login node is policy-blocked, not an installation target. Contributor tools and the separate Miniconda installation remain optional. |
| win | The approved ordinary-token task passed both culture tests and the full PowerShell profile suite. The canonical skills payload install passed, followed by two setup `-Yes` runs, `-Check` and all 33 doctor rows; see [candidate checks](#ordinary-token-candidate-checks). Codex and oh-my-posh 31.9.1 are present; the earlier administrator-SSH Codex absence was a PATH difference. | None in the selected tiers; the payloads row reports `installed: pymol, skills`. Source and deployed dotfiles remain at `360a269`; fresh-machine acceptance remains separate. |

For the two clusters, S3-dirs also reports missing Vim state directories.
An existing login env makes setup-host report S2-login-env done; that alone
does not prove every tool in its specification is present. Resume in an
authorized allocation, check modules first on Sherlock, review a selective
package plan that preserves existing packages, and use the documented
S3-clones, S3-bat-theme, S3-dirs and payload commands for the other missing
items. Keep environments off SCRATCH, obey Marlowe's `block-node` restriction,
and do not run a global package upgrade to clear the doctor.

## Known limits

- win: OpenSSH's default shell there is PowerShell 7 with no
  DefaultShellCommandOption, so every SSH command loads the PowerShell 7
  CurrentUserAllHosts profile under the administrator token, non-interactively
  (no setup block, no update hook). Only a limited-token task proves the
  ordinary user's noninteractive profile load and updater; the normal hook
  and rendered predictions require its separate ordinary-user console
  ([PowerShell 7 console acceptance](#powershell-7-console-acceptance)).
- mac: the quoted-directory failure was reproduced and fixed on real macOS
  with tmux 3.8 on 2026-11-09. All 16 tmux tests pass there and with Linux
  tmux 3.4, including six hostile-directory/action subtests. The macOS CI
  job installs no tmux; its green result alone is still not tmux evidence.
- sherlock, marlowe: the required provisioning items above remain blocked
  on an allocation. Compare rollout doctor rows with those recorded baselines;
  an unchanged failure is not a completed provisioning gate.
- Container and hosted-runner runs are not fresh-machine acceptance
  ([Acceptance checklist](bootstrap.md#acceptance-checklist)).
