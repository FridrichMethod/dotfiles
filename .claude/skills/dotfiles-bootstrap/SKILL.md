---
name: dotfiles-bootstrap
description: Provision or check a machine for this dotfiles repository (hosts mac, wsl-ubuntu, lab-ubuntu, sherlock, marlowe, win, or another Linux without an overlay). Diagnoses with dotfiles doctor, installs pinned tools with dotfiles setup, hands sudo, login, GUI and allocation steps to the person, then deploys the configuration with chezmoi. Use when asked to bootstrap, provision, set up or check a host, or when dotfiles doctor reports missing tools.
compatibility: Needs a clone of this dotfiles repository, Bash 3.2 or newer on macOS and Linux, and PowerShell 7 on Windows.
metadata:
  playbook: docs/bootstrap.md
disable-model-invocation: true
---

# Dotfiles bootstrap

Use this to provision a fresh machine for this repository, finish a partial
setup, or fix what `./dotfiles doctor` reports. `docs/bootstrap.md` is the contract
for every step, flag, exit code and HUMAN block: read it before acting and
follow it over your defaults. Tool/package inventories and versions live in
`config/bootstrap/`; do not copy or invent a second inventory. If the checkout
dispatcher `./dotfiles` or its doctor/setup backends are missing, stop and say so.

1. Resolve the host: ask the person which overlay this is (`mac`, `wsl-ubuntu`,
   `lab-ubuntu`, `sherlock`, `marlowe`, `win`). Never guess an overlay from the
   OS. A machine without one is other Linux: `./dotfiles doctor --platform other` plus
   the manual steps of X-other-linux, because setup-host takes only `--host`.
2. Run every command with `DOTFILES_AUTO_UPDATE=0`.
3. Diagnose: `./dotfiles doctor --host H --tsv`.
4. Plan: `./dotfiles setup --host H --check` writes nothing and makes no network
   calls; exit 3 means work remains and exit 0 means nothing is left to apply.
   Show the plan and wait for the person to agree.
5. Apply: `./dotfiles setup --host H --yes`.
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
   still to apply. Re-run step 5 after each block until H7-deploy is the only one
   left.
8. Run the H7-payloads line only if the person wants the payload repos now;
   no login installs them. Follow the H7-deploy block, Fresh home by hand in
   `docs/bootstrap.md`: explicit local host data, explicit chezmoi paths, private
   backups and the local config init writes, which names this home and the
   checkout. Do not improvise `init --apply` or force a whole home.
   setup-host only provisions tools and never initializes configuration or
   applies it.
9. Finish with `./dotfiles doctor --host H --smoke`; exit 0 is the completion gate.
10. Report what was installed, which HUMAN blocks remain, and every failure with
    its `docs/bootstrap.md <step-id>` reference.

On native Windows use the CLI (`.\dotfiles.ps1 doctor --host win --tsv`,
`.\dotfiles.ps1 setup --host win --check`, then `--yes`), with the same exit codes;
the first apply is the HW-deploy block and the finish is
`.\dotfiles.ps1 doctor --host win`.
`sudo` blocks and anything elevated belong to the person.
Never run `git lfs install`, `gh auth setup-git`, `conda init` or
`micromamba shell init`, never edit rc files, and never commit.

Provisioning installs the verified chezmoi release. Doctor checks the tool and that the local
chezmoi config names this home and this checkout; a config naming another
checkout only warns. On Unix, with a local config the default host is its
`[data].host`; nothing else selects one. Windows doctor/setup default to `win`
and accept only that host. The doctor
remains offline and write-free; chezmoi diff and apply are a separate operation.

Root checkout entrypoints work before home configuration exists. Installed
`dotfiles` launchers require the validated home's configured sourceDir, including
help; recover with an explicit checkout path when configuration is unavailable.
On Windows, use `& "$HOME/.local/bin/dotfiles.ps1" doctor --host win` before
the manual User PATH procedure in `docs/bootstrap.md`; never persist PATH from
an agent, launcher or profile. Quote comma lists, such as `--tier 'core,cli,ai'`.
The public frontends call internal native backends in `scripts/commands/`
directly. Shared functions stay in `lib/`; login hooks retain their
`scripts/chezmoi-update.*` paths. Retired production doctor/setup and
payload-update paths are absent, with no compatibility shims or fallbacks.
