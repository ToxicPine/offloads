---
name: offload
description: Use when the user wants to run a long or resource-heavy task on another computer so their local machine stays free, the work continues if they close their laptop or lose connection, and the result returns as a reviewable branch in their project. Use this skill also when no offload target exists yet and the user needs help setting one up.
argument-hint: <the work to hand off, plus any context the remote agent will need>
---

# Offload

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
technical jargon. Use technical terms only if the user requests more detail, demonstrates
familiarity, when providing exact command lines, or when relaying an error that includes them. The
same goes for setup probes: narrate what the probe means for the user, not what was probed.

When setup is needed, keep the user oriented around the visible phases:

- Create the remote computer.
- Add the required secrets before starting it.
- Save the local connection details.
- Connect the remote computer to GitHub so it can fetch and push branches.
- Send a tiny test job to confirm the remote computer can receive work and push results back,
  then run the requested work.

Do not describe a raw connection check as "the transport works" to the user. Say the remote computer
is reachable, then immediately explain the next visible requirement.

When no target is set up yet, say something like:

> I can help you set up a remote computer on Fly.io. It will require logging in with your Fly.io
> account, and Fly may charge for the remote computer while it exists.

When explaining access to web pages or dev servers, say that the remote computer gets a public web
address and Nestail auth protects the shareable links. Avoid implying that the user needs to
understand Fly internals or configure networking by hand.

## What An Offload Is

An offload is three moves: push, run, push back. `offloader` pushes the local `HEAD` to the base
branch and a fresh run branch `offloader/<run-id>` (the base branch gives the run branch its merge
base), reaches the target through a saved transport command, materializes the run branch as a
worktree there, and runs the command inside it. Everything to check follows from that shape:

- **Only committed state travels.** `HEAD` is what gets pushed. If uncommitted changes matter to
  the task, surface them and offer to commit first.
- **Nothing comes back on its own.** Results exist only as commits the remote command pushes to
  the run branch. A command that does not push has no result.
- **The environment is rebuilt, not copied.** The target does not inherit the local machine's
  setup; it builds the project environment fresh from `flake.nix`. Any tool, env var, or secret
  the flake does not provide will not exist there.
- **The remote sees the repo and the command text, nothing else.** No shell state, no files
  outside the repo, none of this conversation. For open-ended runs the task text must carry the
  context the run needs; `references/open-ended-runs.md` covers what belongs in it.

When in doubt about remote state, one comparison settles it: the worktree's `git rev-parse HEAD`
on the target (the open-ended wrapper logs it at run start) must equal the dispatched local `HEAD`.

## Tools

The system itself is two commands:

- **offloader** runs locally, inside the user's git project, and does the hand-off: push the
  project, start the remote work. Dispatch mechanics, the persistence pattern, and overrides are
  in the `offloader` skill.
- **offloader-configurator** checks and seeds the target's account state (GitHub, assistant auth)
  over the same transport. It is how a machine becomes ready, not part of any run.

Everything else is a choice of what to dispatch:

- A fixed command runs as given.
- An open-ended task ("make this feature work") dispatches a coding harness CLI (`claude`,
  `codex`) already on the target. Choose the harness in this order: the one the user asked for;
  the one this agent itself runs in, so the remote model is comparable, if it is configured on
  the target; otherwise whichever is configured. Compose and dispatch the run from
  `references/open-ended-runs.md`; if a run reports the harness missing or unauthenticated, or the
  user wants to steer it live, `references/assistants-on-the-machine.md` covers setup, auth, and
  remote control. When reporting back, name the harness only if it differs from the one dispatching
  the run.

If a supporting skill is missing, try `npx skills --help` and `npx skills add <repo> --list`;
`offloader` and `offloader-configurator` are in `ToxicPine/offloads`.

## Running the hand-off

The steps below are in execution order, and the path branches once, at the target:

1. Set up the command prefix.
2. Find the target. If none is saved, this is where the path forks: offer to set one up
   (`references/provision-remote-machine.md`, with the user's consent), then rejoin here with a
   saved transport.
3. Check the project rebuilds on the target.
4. Hand it off.
5. Report back.

**Use Nixie directly for local offload dependencies.** Resolve `<skill-dir>` as the directory
containing this `SKILL.md`. The Nixie-generated wrapper is `<skill-dir>/scripts/nix`. It behaves like
the `nix` command: when system Nix is installed it delegates to system Nix, and when Nix is missing
it downloads and runs Nixie's static Nix in the user's cache. It is not a custom package launcher.
Nixie, Nix, and `offloader` are internal names; keep them out of user-facing narration.

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

On the target, prefer Nix-run invocations when a command is not already installed:
`nix run github:ToxicPine/offloads#<package> -- ...`.

**Find the target.** `offloader` reaches the target through `OFFLOADER_TRANSPORT`: one saved
command with the transport contract. Adapters ship for plain SSH (`offloader-ssh <host>`),
Tailscale (`offloader-tailscale <host>`), and Fly
(`offloader-fly --app <app> --machine <machine-id>`), all runnable under `<offload-nix>`. Any
machine the user can reach this way is a valid target; Fly is only the default when this skill
provisions the machine for the user. Transport adapters and Fly Machines are internal vocabulary
too; to the user, all of this is the saved remote computer.

- Before deciding whether `OFFLOADER_TRANSPORT` is set, pull in the saved local transport file if it exists:
  ```bash
  if [ -z "${OFFLOADER_TRANSPORT:-}" ] && [ -r "$HOME/.offload-skill-transport" ]; then
    . "$HOME/.offload-skill-transport"
  fi
  ```
- If `OFFLOADER_TRANSPORT` is set, use it.
- If `OFFLOADER_TRANSPORT` is not set, fail fast. Do not use `fly`, `flyctl`,
  `offloader-fly`, or any provider-specific discovery command to search for a
  possible target. Tell the user there is no saved remote computer configured for this
  project, not that `OFFLOADER_TRANSPORT` is unset, and offer to help find an existing
  machine or set one up before offloading.
- Setting one up means renting a small server, from Fly.io by default, which costs money. If the
  user agrees, follow `references/provision-remote-machine.md`; provisioning needs Fly CLI auth
  first (`<offload-nix> fly auth whoami` to check, `<offload-nix> fly auth login` to log in). The
  provisioned machine keeps its files between restarts, rebuilds project dependencies fresh each
  run, and has the remote-side tools installed.
- If the saved target is a Fly app, confirm Nestail auth is set up. Nestail is the machine's web
  proxy: it exposes the target's `localhost:<port>` services as public URLs. `NESTAIL_AUTH_SECRET`
  is the signing key that enables its auth gate: when set, a route is reachable only through
  signed grant links generated on the machine; when unset, the routes are open to the internet.
  Check with
  `<offload-nix> fly secrets list -a <app>`; if the secret is missing, generate one with
  `<offload-nix> openssl rand -hex 32` and set it with
  `<offload-nix> fly secrets set -a <app> NESTAIL_AUTH_SECRET="$secret"`, telling the user this may
  restart the machine. Treat it as machine-level secret state: do not commit it, print it, or
  reuse a placeholder.
- If the target exists but `offloader` cannot reach the repo or push results back, use
  `offloader-configurator` to check and configure its GitHub access.

**Check the flake offload marker before doing anything with the flake.** Use `nix flake show` (or
`nix flake show --json`) to look for top-level `x-offload`. It records what is already known about
offloading this project, so you do not re-derive it every time. In user-facing narration, say
offloading is not set up for this project yet rather than mentioning the marker. Treat it as a
hint, not a guarantee:

- `"configured"` means an offload worked at some point. Try it; if it breaks because setup drifted,
  move it back to `"untested"` while you re-check the setup, then restore `"configured"` after a
  successful offload.
- `"untested"` means setup was attempted and nothing obvious blocks it, but no successful offload is
  known yet.
- `"none"` means there is a hard reason not to offload, or the user does not want offloading for this
  project. Optionally add `x-offload-none-reason` with a few dense words. If it is already `"none"`,
  stop and confirm with the user before continuing.

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
usually by adding or extending a `devShell` and `.envrc`. Only committed state travels, so a secret
committed to the repo would travel as plaintext; offer to encrypt it with `age` or `sops-nix`. A
secret outside the repo does not travel at all, so the devShell or the machine must provide it. Ask
before changing anything.

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
  assistant, such as Codex or Claude Code, set up and authenticated on the target beforehand; see
  `references/assistants-on-the-machine.md` (which also covers steering the run once it is live).

The work starts inside the project directory on the remote target, so the environment (`devShell`,
`.envrc`) loads on its own. Do not wrap the command in `cd` or `nix develop`.

**Report back.** Tell the user which branch receives the work, which target ran it, and how to check
progress later. For a detached open-ended run, also relay the launch line the dispatch printed
(pid and `<worktree>.log` path on the target). `offloader-target` is a target-side skill. It is useful when
the user talks to an agent on the remote target, for example over Telegram. If the user is local
only, use `OFFLOADER_TRANSPORT` to run a target-side command that asks the remote agent or configured
assistant to inspect the run and print the answer back locally. For an open-ended run, the user may
also be able to check in on and steer the assistant live from another device; see
`references/assistants-on-the-machine.md` for what each assistant needs.

**Authenticated Nestail links must be generated on the target.** The `nestail token ...`
command needs the target's `NESTAIL_AUTH_SECRET`, so do not run it locally unless the local computer
is the target. When reporting a dev-server URL, use the saved `OFFLOADER_TRANSPORT` to generate the
link remotely, or ask the Telegram conversational agent on the target to generate it. For example:

```bash
printf '%s\n' 'nestail token 3000 /dashboard' | bash -c "$OFFLOADER_TRANSPORT"
```

Do not construct a grant URL locally and do not ask the user to copy `NESTAIL_AUTH_SECRET` back to
their local shell. If the remote does not have `nestail` on `PATH`, run the target-side equivalent
that the machine provides, but keep the generation on the remote so the secret never leaves the
machine.

## Optional: Progress Pings

`vusperize` runs on the target beside the work and delivers live updates, for example to Telegram.
Offer it only for long jobs or when the user asks for updates: wrap the dispatched command with
`nix run github:ToxicPine/offloads#vusperize -- ...` on the target. If the user wants Telegram
pings and they are not set up yet, see `references/setup-telegram.md`.

## Follow-up questions

For how to view a dev server through the target's public URL, why an address won't load, or who
else can see it, read `references/frequently-asked-questions.md` before answering.
