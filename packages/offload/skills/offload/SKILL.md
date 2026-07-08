---
name: offload
description: Use when the user wants to run a long or resource-heavy task on another computer so their local machine stays free, the work continues if they close their laptop or lose connection, and the result returns as a reviewable branch in their project. Use this skill also when no offload target exists yet and the user needs help setting one up.
argument-hint: <the work to hand off, plus any context the remote agent will need>
---

# Offloader

Help the user offload work to another computer, or set up and configure the target computer. A
correct offload preserves the local project's behavior: it rebuilds the same environment from the
project's Nix flake, runs the requested work there, and returns the result as a branch in the user's
project.

You do NOT do the requested work yourself when this skill is invoked. You must start it on the
remote target.

> $ARGUMENTS

Infer what you can from the project and request. Ask only when the choice matters: spending money,
using an online account, choosing between valid targets, or changing project configuration.

## How To Speak To The User

Keep the narration and explanation clear and direct. When describing setup, focus on what the user
needs to do and what will happen, without introducing internal names, implementation details, or
technical jargon such as Fly Machines, Nix, `offloader`, Nixie, or transport adapters. Use those terms
only if the user requests more detail, demonstrates familiarity, when providing exact command lines,
or when relaying an error that includes them.

Do not expose setup probes in user-facing narration. For example, do not say "`OFFLOADER_TRANSPORT` is
unset" or "the flake has no `x-offload` marker" unless the user asks for implementation details.
Say that no saved remote computer is configured for this project yet.

When setup is needed, keep the user oriented around the visible phases:

- Create the remote computer.
- Add the required secrets before starting it.
- Save the local connection details.
- Connect the remote computer to GitHub so it can fetch and push branches.
- Run a tiny end-to-end check, then run the requested work.

Do not describe a raw connection check as "the transport works" to the user. Say the remote computer
is reachable, then immediately explain the next visible requirement.

When no target is set up yet, say something like:

> I can help you set up a remote computer on Fly.io. It will require logging in with your Fly.io
> account, and Fly may charge for the remote computer while it exists.

When explaining access to web pages or dev servers, say that the remote computer gets a public web
address and Nestail auth protects the shareable links. Avoid implying that the user needs to
understand Fly internals or configure networking by hand.

## Supporting Skills

Use supporting skills for specialized work: `offloader` for the hand-off and `offloader-configurator` for remote
GitHub and assistant setup. Provision and manage the target with the official Fly.io CLI (`fly`).
If a skill is missing, try `npx skills --help` and `npx skills add <repo> --list`; `offloader` and
`offloader-configurator` are in `ToxicPine/offloads`.

## Tools

Two custom commands are involved, plus the coding harness CLIs already on the target. Run
`offloader` locally for the actual hand-off; it starts the remote work.

- **offloader** runs locally, inside the user's git project. It pushes the project's current state to
  the remote target as branch `offloader/<run-id>`, then starts the remote work. It does not pull
  results back by itself, so every dispatched command must push its own changes.
- **Coding harness CLIs** (`claude`, `codex`) run on the remote target, inside the copied project,
  for open-ended tasks such as "make this feature work" rather than one exact command. Compose the
  harness invocation and its publish wrapper from `references/open-ended-runs.md`. Configure the
  assistant through `offloader-configurator`; see `references/assistants-on-the-machine.md`.
- **vusperize** runs on the remote target and wraps the work so it can send live progress pings,
  for example to Telegram. Use it for long jobs or when the user asks for progress updates. If the
  user wants Telegram pings and they are not set up yet, see `references/setup-telegram.md`.

`offloader` reaches the target through a transport (see "Find the target") and starts the requested
command there. The Fly target keeps its files between restarts, rebuilds project dependencies
fresh each run, and has the remote-side tools installed. If no target exists, set one up with
`references/provision-remote-machine.md`. Otherwise assume one exists.

## What An Offload Is

An offload is three moves: push, run, push back. `offloader` pushes the local `HEAD` to the base
branch and a fresh run branch `offloader/<run-id>`, reaches the target through the transport,
materializes the run branch as a worktree there, and runs the command inside it. Everything to
check follows from that shape:

- **Only committed state travels.** `HEAD` is what gets pushed. If uncommitted changes matter to
  the task, surface them and offer to commit first.
- **Nothing comes back on its own.** Results exist only as commits the remote command pushes to
  the run branch. A command that does not push has no result.
- **The environment is rebuilt, not copied.** The target re-derives it from `flake.nix`. Anything
  the flake cannot provide (tools, env vars, secrets) will not exist there.
- **The remote sees the repo and the command text, nothing else.** No shell state, no files
  outside the repo, none of this conversation. For open-ended runs the task text must carry the
  context the run needs; `references/open-ended-runs.md` covers what belongs in it.

When in doubt about remote state, one comparison settles it: the worktree's `git rev-parse HEAD`
on the target (the open-ended wrapper logs it at run start) must equal the dispatched local `HEAD`.

## Running the hand-off

**Use Nixie directly for local offload dependencies.** Resolve `<skill-dir>` as the directory
containing this `SKILL.md`. The Nixie-generated wrapper is `<skill-dir>/scripts/nix`. It behaves like
the `nix` command: when system Nix is installed it delegates to system Nix, and when Nix is missing
it downloads and runs Nixie's static Nix in the user's cache. It is not a custom package launcher.

The offload dependency environment is a small flake at `<skill-dir>/scripts/deps`. Use this command
shape for local setup tools:

```bash
<skill-dir>/scripts/nix develop <skill-dir>/scripts/deps -c <command> ...
```

For brevity, the rest of this skill writes that prefix as `<offload-nix>`. It provides local
dependencies such as `fly`, `openssl`, `git`, `jq`, and the original `offloader-transports` package
(`offloader-fly`, `offloader-ssh`, `offloader-tailscale`, etc). Run offloads commands such as
`offloader` and `offloader-configurator` through `<skill-dir>/scripts/nix run` or
`<skill-dir>/scripts/nix shell` against `github:ToxicPine/offloads`.

Examples:

```bash
<offload-nix> fly auth whoami
<offload-nix> fly status -a <app>
<skill-dir>/scripts/nix run github:ToxicPine/offloads#offloader -- -- <command>
```

Offloading still works cleanly only when the target can rebuild the project environment from
`flake.nix`. That keeps dependencies and behavior consistent after the work moves. On the target,
prefer Nix-run invocations when commands are not already installed:
`nix run github:ToxicPine/offloads#vusperize -- ...`.

**Fly CLI auth must be ready before provisioning a new target.** Use
`<offload-nix> fly auth whoami` to check,
`<offload-nix> fly auth login` to log in, and
`<offload-nix> fly --help` or the Fly docs when a command option needs
confirmation.

**Fly targets must have Nestail auth enabled.** Before using a Fly target, ensure its app has
`NESTAIL_AUTH_SECRET` set. Check with `<offload-nix> fly secrets list -a <app>`.
If it is missing, generate a fresh secret with
`<offload-nix> openssl rand -hex 32` and set it with
`<offload-nix> fly secrets set -a <app> NESTAIL_AUTH_SECRET="$secret"`. Treat this
as machine-level secret state; do not commit it, print it, or reuse a placeholder.

**Authenticated Nestail links must be generated on the target.** The `nestail token ...`
command needs the target's `NESTAIL_AUTH_SECRET`, so do not run it locally unless the local computer
is the target. Use the saved `OFFLOADER_TRANSPORT` to run it remotely, or ask the Telegram
conversational agent on the target to generate the link. For example:

```bash
printf '%s\n' 'nestail token 3000 /dashboard' | bash -c "$OFFLOADER_TRANSPORT"
```

If the remote does not have `nestail` on `PATH`, run the target-side equivalent that the machine
provides, but keep the generation on the remote so the secret never leaves the machine.

**Check the flake offload marker before doing anything with the flake.** Use `nix flake show` (or
`nix flake show --json`) to look for top-level `x-offload`. Treat it as a hint, not a guarantee:

- `"configured"` means an offload worked at some point. Try it; if it breaks because setup drifted,
  move it back to `"untested"` while you re-check the setup, then restore `"configured"` after a
  successful offload.
- `"untested"` means setup was attempted and nothing obvious blocks it, but no successful offload is
  known yet.
- `"none"` means there is a hard reason not to offload, or the user does not want offloading for this
  project. Optionally add `x-offload-none-reason` with a few dense words.

When you become confident the flake will work for offloading, set `x-offload = "untested";`. After a
successful offload, set `x-offload = "configured";`. If you find a real blocker, or the user
declines offloading, set `x-offload = "none";`.

Keep it in `outputs` beside the existing outputs:

```nix
outputs = { self, nixpkgs, ... }: {
  x-offload = "configured";
  # existing outputs...
};
```

**Check that the project rebuilds on the target.** Review `flake.nix` and any `.envrc`: will the
rebuilt project have the dependencies and settings this task needs? This is a sanity check, not an
audit. If setup is incomplete or there is no `flake.nix`, tell the user and offer to fix it first,
usually by adding or extending a `devShell` and `.envrc`. `offloader` copies the whole project, so any
secret the devShell cannot provide must not travel as plaintext. Offer to encrypt it with `age` or
`sops-nix`. Ask before changing anything.

**Find the target.** `offloader` reaches it through `OFFLOADER_TRANSPORT`, usually Fly:
`<skill-dir>/scripts/nix develop <skill-dir>/scripts/deps -c offloader-fly --app <app> --machine <machine-id>`.
Plain SSH and Tailscale transports are still valid for user-managed boxes, but Fly is the default
when this skill provisions the machine.

- Before deciding whether `OFFLOADER_TRANSPORT` is set, pull in the saved local transport  file if it exists:
  ```bash
  if [ -z "${OFFLOADER_TRANSPORT:-}" ] && [ -r "$HOME/.offload-skill-transport" ]; then
    . "$HOME/.offload-skill-transport"
  fi
  ```
- If `OFFLOADER_TRANSPORT` is set, use it.
- If `OFFLOADER_TRANSPORT` is not set, fail fast. Do not use `fly`, `flyctl`,
  `offloader-fly`, or any provider-specific discovery command to search for a
  possible target. Tell the user there is no saved remote computer configured, and
  offer to help find an existing machine or set one up before offloading.
- For an existing Fly app, check `<offload-nix> fly secrets list -a <app>` and set a generated
  `NESTAIL_AUTH_SECRET` if missing. Tell the user this may restart the Fly Machine.
- If no target exists, tell the user setup means renting a small server from Fly.io, which costs
  money. If they agree, follow `references/provision-remote-machine.md`.
- If the target exists but `offloader` cannot reach the repo or push results back, use
  `offloader-configurator` to check and configure its GitHub access.

**Hand it off.** Whatever is dispatched runs in the foreground of the transport session and dies
with it if the connection drops. Detach anything that should outlive the connection — that is most
offloads, fixed command or open-ended alike — using the `setsid` pattern in the `offloader` skill's
Persistence section; dispatch plainly only for short commands watched live. The open-ended
composition below already includes the detach.

- One exact command: `<skill-dir>/scripts/nix run github:ToxicPine/offloads#offloader -- -- <command>`. This runs on the
  remote branch. To return changes, the command must commit and push them itself.
- Open-ended task: compose the publish-wrapped harness command into a `remote_script` variable
  exactly as `references/open-ended-runs.md` shows, then dispatch it the same way:
  `<skill-dir>/scripts/nix run github:ToxicPine/offloads#offloader -- -- bash -lc "${remote_script}"`.
  The wrapper pushes the result back on the run branch when the run ends. This requires an
  assistant, such as Codex or Claude Code, configured through `offloader-configurator`
  (`references/assistants-on-the-machine.md`).

The work starts inside the project directory on the remote target, so the environment (`devShell`,
`.envrc`) loads on its own. Do not wrap the command in `cd` or `nix develop`. For long jobs or
progress pings, wrap the command with `vusperize`, which runs alongside it on the remote target.

**Report back.** Tell the user which branch receives the work, which target ran it, and how to check
progress later. For a detached open-ended run, also relay the launch line the dispatch printed
(pid and `<worktree>.log` path on the target). `offloader-target` is a target-side skill. It is useful when
the user talks to an agent on the remote target, for example over Telegram. If the user is local
only, use `OFFLOADER_TRANSPORT` to run a target-side command that asks the remote agent or configured
assistant to inspect the run and print the answer back locally.

When reporting a dev-server URL for a Fly target with Nestail auth enabled, generate the shareable
URL on the remote target with `nestail token <port> <path>` through `OFFLOADER_TRANSPORT`, or have the
Telegram agent on the target do it. Do not construct a grant URL locally and do not ask the user to
copy `NESTAIL_AUTH_SECRET` back to their local shell.

## Follow-up questions

For how to view a dev server through the public Fly URL, why an address won't load, or who else can
see it, read `references/frequently-asked-questions.md` before answering.
