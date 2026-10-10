---
name: dotfiles-bootstrap
description: Provision or check a machine for this dotfiles repository (hosts mac, wsl-ubuntu, lab-ubuntu, sherlock, marlowe, win, or another Linux without an overlay). Diagnoses with doctor.sh, installs pinned tools with setup-host.sh, hands sudo, login, GUI and allocation steps to the person, then stows. Use when asked to bootstrap, provision, set up or check a host, or when doctor.sh reports missing tools.
compatibility: Needs a clone of this dotfiles repository, Bash 3.2 or newer on macOS and Linux, and PowerShell 7 on Windows.
metadata:
  playbook: docs/bootstrap.md
---

# Dotfiles bootstrap

Use this to provision a fresh machine for this repository, finish a partial
setup, or fix what `./doctor.sh` reports. `docs/bootstrap.md` is the contract
for every step, flag, exit code and HUMAN block: read it before acting and
follow it over your defaults. If `./doctor.sh` or `./setup-host.sh` is missing
from this checkout, stop and say so.

1. Resolve the host: ask the person which overlay this is (`mac`, `wsl-ubuntu`,
   `lab-ubuntu`, `sherlock`, `marlowe`, `win`). Never guess an overlay from the
   OS. A machine without one is other Linux: `./doctor.sh --platform other` plus
   the manual steps of X-other-linux, because setup-host takes only `--host`.
2. Run every command with `DOTFILES_AUTO_UPDATE=0 AWESOME_SKILLS_AUTO_UPDATE=0`.
3. Diagnose: `./doctor.sh --host H --tsv`.
4. Plan: `./setup-host.sh --host H --check` writes nothing and makes no network
   calls; exit 0 means nothing is left to apply. Show the plan and wait for the
   person to agree.
5. Apply: `./setup-host.sh --host H --yes`.
6. Handle each HUMAN block by kind, as `docs/bootstrap.md` ("Running it with an
   agent") says. Lines starting with `# ` are notes, not commands; every other
   line is one self-contained command, run in order. `sudo`: only after the
   person approves it in chat, each command line as one visible top-level
   command, never through `sh -c`, a script or a chain (a printed
   `printf ... | sha256sum -c --status - && ...` digest gate is one command:
   run it as printed). `auth`, `gui`, `alloc`, `chsh`: hand them to the person
   and wait. `inspect`: show the script's digest, size and contents, then
   wait; run the block's digest-gated `bash <path>` line only after the person
   approves it in chat, as one visible top-level command, or leave it to them.
   `judgment`: the person decides.
7. Exit 3 means work remains: a blocking HUMAN block is pending, or steps are
   still to apply. Re-run step 5 after each block until H7-stow is the only one
   left.
8. Ask the person about H7-sync-skills (on by default once stowed). Then run
   the H7-stow block's one line exactly as printed (the `PATH=` prefix for this
   host, then the clone's `stow-all.sh H`), only as its own visible top-level
   command that the person approves; it writes under `~/.claude` and
   `~/.codex`. Re-run step 5; it should exit 0.
9. Finish with `./doctor.sh --host H --smoke`; exit 0 is the completion gate.
10. Report what was installed, which HUMAN blocks remain, and every failure with
    its `docs/bootstrap.md <step-id>` reference.

On native Windows use the twins (`.\doctor.ps1 -Host win -Tsv`,
`.\setup-host.ps1 -Host win -Check`, then `-Yes`); there `-Check` exits 0 even
with todo steps, so read its plan lines. `sudo` blocks and anything elevated
belong to the person. Never run `git lfs install`, `gh auth setup-git`,
`conda init` or `micromamba shell init`, never edit rc files, and never commit.
