---
name: dotfiles-bootstrap
description: Set up or diagnose a fresh machine for this dotfiles repository (hosts mac, wsl-ubuntu, lab-ubuntu, sherlock, marlowe, win). Use when asked to bootstrap, provision or check a host before or after stowing the dotfiles.
compatibility: Needs a clone of this dotfiles repository, Bash 3.2 or newer on macOS and Linux, and PowerShell 7 on Windows.
metadata:
  playbook: docs/bootstrap.md
---

# Dotfiles bootstrap

1. Read `docs/bootstrap.md` first. It is the playbook and the contract for
   every step, flag, exit code and HUMAN block below. If `./doctor.sh` or
   `./setup-host.sh` is missing from this checkout, stop and say so: the
   bootstrap scripts are not installed yet.
2. Diagnose without changing anything: `./doctor.sh --host <host>`
   (`.\doctor.ps1 -Host win` on Windows).
3. Preview the plan, which writes nothing: `./setup-host.sh --host <host> --check`.
4. Run `./setup-host.sh --host <host>` only after the person agrees. It stops
   before stow and prints HUMAN blocks instead of running them.
5. Never run `sudo` from a script, a `sh -c` wrapper or a chained command. A
   `sudo` HUMAN block runs only after the person approves it in chat, as one
   visible top-level command. Hand `auth`, `gui`, `alloc` and `chsh` blocks to
   the person.
6. Run `./stow-all.sh <host>` only as its own visible top-level command.
7. Finish with `./doctor.sh --host <host>`; exit status 0 is the completion gate.
