# /offload

[![License](https://img.shields.io/github/license/ToxicPine/offloads)](LICENSE.md)
[![Built with Nix](https://img.shields.io/badge/built%20with-Nix-5277C3?logo=nixos&logoColor=white)](https://nixos.org/)

https://github.com/user-attachments/assets/e23d4b5c-057a-4a3b-994e-ab8cc9e28e3b

## About

`/offload` is a sync engine between computers. It keeps a second machine
aligned with your own — the same project, the same development environment,
the same accounts and agent logins — so that either machine can pick up the
same task and carry it to completion.

That alignment is what makes hand-offs dependable. Ask your coding agent:

```text
/offload look through leads.csv, email the 500 best matches about our invoice
cleanup service between 9am and 5pm, track who replies and what they ask,
and stop Wednesday with a short review summary and recommended next steps
```

The agent pushes your project's current state to the other machine, the task
runs there inside a faithful rebuild of your environment, and everything it
produces comes back as an ordinary branch in your repository.

The other machine can be any computer you can reach over SSH or Tailscale, or
`/offload` can dispatch the job to a cloud instance on [Fly](https://fly.io).
Hosted products like Cursor Cloud Agents lend you their machine; `/offload`
turns a machine you already control into an interchangeable copy of your own.

Because the run lives on that machine, it survives your laptop sleeping or
disconnecting. While it works, it can send status updates, expose its
`localhost:<port>` dev servers through authenticated public URLs, and stay
steerable through the official Claude Code and Codex remote controls.

## Quick Start

`/offload` is an agent skill; no persistent local software is needed.

Install from GitHub:

```sh
curl -fsSL https://raw.githubusercontent.com/ToxicPine/offloads/master/install-offload | bash
```

Pass options after `bash -s --`, for example `--yes` to skip the prompt or
`--silent` for quiet installs.

## Documentation

This software is distributed with an agent skill, which serves as complete
documentation. I suggest that you install the skill, then ask an LLM about
its usage. Alternatively, you may read the skill text yourself, starting with
[this](./packages/offload/skills/offload/SKILL.md).

## What Stays In Sync

Three things must match before another computer can continue your work.
`/offload` keeps all three aligned.

**The project.** `offloader` pushes your repository's current state to a
dedicated run branch, and the remote machine checks it out into a fresh
worktree. Whatever the run produces is committed and pushed back on that same
branch, so results arrive the way a collaborator's work would: as a branch
you can review and merge.

**The environment.** Your repository's Nix flake defines its toolchain, and
the remote machine rebuilds that toolchain exactly — same dependencies, same
versions, same behavior. `/offload` ships a zero-install, rootless way to run
the Nix package manager, and the skill helps make your project runnable as a
flake if it isn't already.

**The credentials.** `offloader-configurator` checks and seeds the account
state the remote machine needs: GitHub access, git identity, and login state
for coding agents such as Claude Code and Codex. The remote machine can
fetch, push, and run the same assistants you run locally.

The default remote target is a container built for this arrangement: the
right tooling installed, runtime Nix builds, persistent state between runs,
and a way to expose dev servers on its own `localhost:<port>` through
authenticated public URLs. The skill includes instructions for deploying that
container on Fly.

### Optional: Hermes Agent Integration With Telegram

The machine includes [Hermes](https://hermes-agent.nousresearch.com/) by
default. You can optionally enable its Telegram integration for progress pings,
phone supervision, and quick interventions like asking the remote agent for a
dev-server link. `/offload` still works without it.

## Packages

`offload` is the main agent skill. It decides whether a remote computer is ready,
helps set one up when needed, and starts the offloaded run.

`offloader` sends a command from your current git project to the remote computer
and creates the run branch that receives the work.

`offloader-configurator` checks and seeds the remote computer with the account
state it needs, such as GitHub and assistant login.

`offloader-container` is the ready-to-run remote computer image used by the
default setup.

`offloader-transports` is the small set of ways to reach that computer, including
Fly.io, plain SSH, and Tailscale SSH.

`nestail` turns `localhost:<port>` on the remote computer into an openable URL,
and can generate protected share links for that port.

`vusperize` wraps long work so it can send live status updates while it runs.

`boondoggler` gives Codex a goal, lets it work from the remote branch, then
commits and pushes the result back.
