# /offload

[![License](https://img.shields.io/github/license/ToxicPine/offloads)](LICENSE.md)
[![Built with Nix](https://img.shields.io/badge/built%20with-Nix-5277C3?logo=nixos&logoColor=white)](https://nixos.org/)

https://github.com/user-attachments/assets/e23d4b5c-057a-4a3b-994e-ab8cc9e28e3b

## About

From within Claude Code or Codex, the `/offload` command sets up a remote dev
computer that matches the machine you work on, copying over your software
versions and `.env` files, and hands your prompt off to it. That's why the
prompt runs with everything it needs already in place, and keeps going on its
own even after you close your laptop.

You may, for example:

```text
/offload look through leads.csv, email the 500 best matches about our invoice
cleanup service between 9am and 5pm, track who replies and what they ask,
and stop Wednesday with a short review summary and recommended next steps
```

The agent sends your current project state to another machine, runs the task
there, and saves any changes on a new branch. You can use any machine you can
access, or `/offload` can easily dispatch the job to a cloud instance on
[Fly](https://fly.io), similar to Cursor Cloud Agents.

The run can continue even if your laptop sleeps or disconnects. It can send
status updates, expose remote `localhost:<port>` dev servers through
authenticated public URLs, and use the official Claude Code or Codex remote
controls to check in or steer it.

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
its usage, etc. Alternatively, you may read the skill text yourself, starting
with [this](./packages/offload/skills/offload/SKILL.md).

## How It Works (Technical)

`/offload` ships with a zero-install, rootless way to run the Nix package
manager, and the skill helps manage the work of making your project runnable as
a Nix flake. That lets the repo define the project environment the remote
machine needs in order to work with it correctly.

The next part is the remote target: a container designed for work, with the
right tooling installed, runtime Nix builds, persistent state, and a way to
expose dev servers running on its own `localhost:<port>` through authenticated
public URLs. The skill includes instructions for deploying that container on Fly.

The rest is integration polish, like checking and seeding GitHub credentials,
git identity, repo state, and coding-agent login state for tools like Codex and
Claude Code. The goal is simple: run the same project somewhere else and return
the result as a normal branch.

### Does It Sync Claude Code / Codex Conversation History?

No. The offload carries your project state and a written task, not your chat
history. To sync the sessions themselves, use [Entire](https://entire.io). It
saves Claude Code and Codex transcripts to a branch in your repo, with secrets
redacted, and restores them wherever the repo is checked out. This lets the
remote agent resume with full context from your previous conversations, which
can improve the quality of the offloaded work.

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
