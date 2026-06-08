# /offload

`/offload` lets coding agents continue long-running tasks on another machine.

You may, for example:

```text
/offload audit the payment flow, reproduce the intermittent checkout failure,
add regression tests, and keep iterating until the full suite passes locally
```

Or, maybe:

```text
/offload look through leads.csv, email the 500 best matches about our invoice
cleanup service between 9am and 5pm, track who replies and what they ask,
and stop Wednesday with a short review summary and recommended next steps
```

The agent sends your current project state to another machine, runs the task
there, and keeps every change on a new branch from this exact state.

The run can continue even if your laptop sleeps or disconnects. It can send
status updates, expose dev-server links, and use the agent remote controls you
already have to check in or steer it.

## Install

From this repo:

```sh
./install-offload
```

Use `--yes` to skip the prompt, or `--silent` for quiet installs.

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
