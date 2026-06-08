WARNING: LLM SLOP TEXT (SLIGHTLY PRUNED).

# Technical Architecture

This repository is a system for moving agent work off the user's local machine
without changing what the work means.

The desired outcome is not just "run a command on a server." It is: take the
current project state, recreate the project's working environment somewhere
else, let a command or coding agent keep working after the user's laptop goes
away, expose any remote dev surfaces safely, provide useful progress signals,
and return the result as a reviewable git branch.

That goal creates several separate problems:

- How does the remote machine know what software environment the project needs?
- How does local state become remote state without losing reviewability?
- How does the system reach different kinds of remote machines?
- Where do durable credentials and assistant state live?
- How can a browser open `localhost` services running on the remote machine?
- How does long-running work report progress without forcing the user to watch
  logs?

The high-level design choice in this repo is to keep those concerns separate.
Nix flakes describe project environments. `offloader-container` provides a
mutable Nix-capable remote computer. `offloader` moves git work to that computer.
`offloader-transports` describe how to reach it. `offloader-configurator` seeds
tool-owned auth state. `nestail` exposes remote localhost services through one
public web surface. `vusperize` connects long-running shell workflows to Hermes
status delivery. `boondoggler` turns an open-ended prompt into a Codex goal run
that can commit and push its own result.

## First Principles

The core promise is semantic preservation. If a user says "run the tests" or
"finish this feature" from inside a project, the remote run should see the same
project and a compatible environment. Otherwise the offload system becomes a
second, subtly different development machine.

That is why flakes matter. A flake is the project-side contract for rebuilding
the environment elsewhere: dependencies, tool versions, and development shells
belong in versioned project configuration rather than in whatever happens to be
installed on the user's laptop. A project `.envrc` using `use flake` is the
ergonomic layer on top of that contract: it lets entering the repo load the
flake's development environment through direnv/nix-direnv-style workflows. The
offload skill treats this as a sanity requirement. Before offloading, it looks
for a `flake.nix`, checks the project's `devShell` and `.envrc` shape, and uses
an `x-offload` marker as a small project-local hint about whether offloading has
already been tried.

The other important principle is that not all state should be declarative.
Project tools and packages should be declarative. Human login state, GitHub
tokens, Codex auth artifacts, Telegram bot secrets, and assistant account files
are different: they are produced and refreshed by other tools, have security
properties, and should not be checked into a flake. This repo therefore has two
state planes:

- Declarative environment state, captured by flakes and Home Manager modules.
- Mutable operational state, stored on the remote machine's persistent disk or
  in provider secrets and seeded through narrow tooling.

That separation is the main reason the system has multiple small packages
instead of one large command.

## The Abstract Machine

From first principles, a useful offload target needs these capabilities:

1. A way to recreate project environments from the project's own declarations.
2. Persistent storage for homes, credentials, repo caches, Nix cache data, and
   assistant state.
3. A stable command execution boundary from the local machine to the target.
4. Git credentials that can fetch the user's repo and push result branches.
5. Optional assistant credentials for open-ended coding work.
6. A safe public access layer for dev servers running on the target.
7. A progress/status channel that is separate from the command's raw output.
8. A result path that lands in the user's normal review workflow.

The repo's concrete implementation maps directly onto those requirements.

## Repository Map

The top-level `flake.nix` exposes the packages and skill bundles:

- `offload`: the user-facing orchestration skill.
- `offloader`: local dispatch from a git repo to a remote worktree.
- `offloader-transports`: provider-specific ways to run a remote bash script.
- `offloader-configurator`: remote auth/config seeding for known tools.
- `offloader-container`: the default Fly.io remote machine image.
- `nestail`: a localhost-route proxy for web access to remote dev servers.
- `vusperize`: a status-update wrapper for long-running commands.
- `boondoggler`: a Codex goal launcher that can commit and push results.
- `ghwc` and `ghwrc`: supporting GitHub worktree/repo helpers.

The `offload` skill is the coordinator. It is intentionally not the runtime
implementation of everything. It decides whether a target is available, helps
provision one if needed, checks project readiness, invokes `offloader`, invokes
`offloader-configurator` when credentials are missing, and explains the result
to the user.

## Nix And The Remote Environment

There are two related but distinct Nix stories in this repo.

First, the local offload skill has to be usable even if the user's current
machine does not already have all helper dependencies installed. The skill ships
a Nixie-generated `scripts/nix` wrapper and a small `scripts/deps` flake. That
environment provides local setup tools such as `fly`, `git`, `jq`, `openssl`,
and the transport adapters. The wrapper behaves like `nix`: it delegates to
system Nix when available and can bootstrap Nixie's static Nix otherwise.

Second, the remote computer must itself be able to build Nix environments at
runtime. This is the more important architectural choice. A normal slim
container can only run what was baked into the image. That is too rigid for an
agent machine, because the project being offloaded may need packages that were
not known when the image was built. `offloader-container` solves this by making
the running container a Nix-capable, Home Manager-managed environment.

The container image includes only enough bootstrap closure to start reliably,
plus a precomputed `/nix-base` closure. On boot, the entrypoint seeds `/nix/store`
from `/nix-base/store` with `cp -aln`, loads the bundled Nix database
registration, starts `nix-daemon`, and then rebuilds each user's Home Manager
profile from the persisted user config. The Docker image declares `/nix` and
`/data` as volumes. `/nix` gives Nix a real store to mutate; `/data` holds the
state that should survive image rebuilds and restarts.

This simulates the useful parts of a multi-user Nix machine inside a container:
there are normal users, `nixbld` users, a Nix daemon socket, a shared store, and
per-user Home Manager profiles. It is not trying to be a full NixOS system. It
is a deliberately narrower substrate for agent work.

## Home Manager As The Editable System Layer

`offloader-container` uses Home Manager to make the remote machine adjustable
while it is running.

At image build time, `nix/default.nix` defines users and imports
`lib/hm.nix`. Home Manager activation packages can be prebuilt into the image,
but the live source of truth is persisted under `/data/homes/<user>/nixcfg`.
At boot, the entrypoint links that persisted config into both the user's home as
`~/.nixcfg` and the shared `/opt/app/hm-user/<user>` tree. That second link
matters because Home Manager modules refer to relative paths in `/opt/app`.

The user or agent can edit:

```text
~/.nixcfg/home.nix
```

and then run:

```text
refresh-system
```

`refresh-system` rebuilds the Home Manager activation package from that config
and activates it. The image also includes `reset-system`, `read-managed-hm`,
and `write-managed-hm` helpers. `managed.nix` is a provider-controlled module
that can be read or replaced without rewriting the whole user config.

The base Home Manager configuration installs the remote work tools: Codex,
Claude Code, Hermes, GitHub CLI, `nestail`, `boondoggler`, `vusperize`, and the
skills used by the remote agent. It also starts assistant remote-control
supervisors through Home Manager activation hooks. This is the mutable machine
layer: the target can acquire new tools and behavior without rebuilding the
Docker image, but those changes are still represented as Nix/Home Manager
configuration instead of ad hoc shell history.

## Container Runtime Shape

The current `offloader-container` runtime starts three important processes:

- Foreground entrypoint: `nestail` with `SCRAMJET_HOST=0.0.0.0` and
  `SCRAMJET_PORT=4096`.
- Spawnable background service: `hermes gateway`.
- Spawnable background service: `nix-gc-loop`.

The foreground entrypoint is the container's main process. If it exits, the
container exits. Hermes provides the agent gateway and messaging/status
integration. The GC loop runs daily and removes Nix store paths older than seven
days, while Home Manager activation copies new generations into `/data/nix-cache`
so repeated refreshes can reuse cached closures.

This is a deliberate split:

- The image is slim enough to deploy and roll.
- The Nix store is mutable at runtime.
- Agent identity, tool auth, repo caches, and Home Manager config live on
  `/data`.
- Default tools are present at boot, but missing project tools can still be
  built from flakes.

## Fly.io Deployment

Fly.io is the default provisioned target, not the core abstraction.

The Fly template in `packages/offloader-container/fly.toml` points at the
ready-made image, mounts a persistent volume at `/data`, exposes the HTTP service
on internal port `4096`, keeps at least one machine running, and sets webhook
environment defaults. The offload skill provisions this through the official
`fly` CLI from the local Nixie dependency shell.

The setup flow is intentionally phase-based:

1. Create a Fly app from the container template.
2. Set machine-level secrets before first deploy.
3. Deploy the machine and persistent volume.
4. Save a local transport command in `~/.offload-skill-transport`.
5. Configure GitHub and assistant auth on the remote.
6. Run a tiny end-to-end check.
7. Send the real work.

`NESTAIL_AUTH_SECRET` is mandatory for Fly targets. It is a machine-level secret
stored in Fly app secrets, not in any repo. Setting it enables Nestail's auth
gate for public dev-server routes. Authenticated Nestail links must be generated
on the target machine because the target owns the secret.

## Nestail: Public Access To Remote Localhost

A remote dev server usually binds to `localhost:3000` or similar. From the
user's laptop, `localhost:3000` points to the laptop, not to the Fly machine.
Nestail provides the bridge.

Nestail's public route contract is:

```text
/:port/:target-path
```

For example:

```text
https://<app>.fly.dev/3000/dashboard
```

means:

```text
http://localhost:3000/dashboard
```

It uses Scramjet and BareMux to render the target page in a browser frame while
preserving refresh, deep links, in-frame navigation, browser back/forward, and
websocket-style transport behavior. The route id is the port. There is no
general id-to-origin registry; `3000` maps to `http://localhost:3000`.

The transport layer is constrained. Transport requests must target localhost,
must match the selected route's origin, and must use allowed HTTP/WebSocket
protocols. This is important because Nestail is a public web surface on a remote
computer that may be running sensitive local services.

## Nestail Auth

Nestail auth is optional in the code but required by the offload skill for Fly
targets. It is enabled when `NESTAIL_AUTH_SECRET` is present.

The model has two signed token types:

- An authorization grant: a short-lived, one-time, route-bound token.
- A session token: a route-bound token stored in an HTTP-only cookie.

`nestail token <port> <path>` creates a URL with the grant in the fragment:

```text
/3000#<grant>/dashboard
```

The fragment is not sent to the server in the original HTTP request, so the
browser bootstrap page reads it, removes it from visible history, posts it to
`/__auth/consume`, receives an HTTP-only cookie, and then navigates to the normal
route:

```text
/3000/dashboard
```

Both the shell route and the Scramjet transport route check the cookie before
proxying anything to localhost. Session cookies are route-bound, so access to
`/3000` does not imply access to `/3001`. Grant consumption is currently tracked
in memory, which gives single-use behavior within a Nestail process. On process
restart, unexpired grants could be redeemed again; persistent grant storage would
be the extension point if restart-proof one-time grants become necessary.

Fly terminates TLS before forwarding to the container, so Nestail trusts proxy
TLS headers by default when deciding whether to mark cookies `Secure`. This is a
deployment-aware choice: it keeps browser cookie behavior correct on Fly without
requiring Nestail itself to terminate TLS.

## Offloader: Git Is The Transfer Protocol

`offloader` is the command that moves a local repo state to the target and runs
a command there.

It does not copy arbitrary directories over SSH. It uses git:

1. Detect the repo root and remote URL.
2. Push the current `HEAD` to the local branch when possible.
3. Push the current `HEAD` to a run branch named `offloader/<run-id>`.
4. Send a remote script through the configured transport.
5. On the target, create or update a bare repo cache.
6. Fetch branches into that bare repo.
7. Create or reset a worktree for the run branch.
8. Run the requested command from that worktree.

The default target layout is:

```text
~/.remote-work/repos/<repo-path>/.bare
~/.remote-work/repos/<repo-path>/offloader-<run-id>
```

This is a high-level design decision. Git gives the system a durable,
reviewable, branch-oriented result path. The offload run starts from an exact
commit state, and any result comes back as normal branch history. `offloader`
does not pull changes back by itself. For fixed commands, the command must
commit and push if it produces a result. For open-ended agent work, `boondoggler`
does that publication step.

## Transports: A Narrow Remote Execution Boundary

`offloader` is provider-neutral. It only requires a transport command with this
contract:

```text
read a bash script from stdin, run it on the remote machine, forward stdout,
stderr, and the exit status
```

`offloader-transports` provides three adapters:

- `offloader-ssh`: runs `ssh ... bash -s`.
- `offloader-tailscale`: runs `tailscale ssh ... bash -s`.
- `offloader-fly`: runs the script through `fly ssh console`.

The Fly adapter has to work around the shape of `fly ssh console`, so it writes
the stdin script to a remote temp file, runs it, prints a sentinel with the exit
status, and maps that back to the local process exit status.

This narrow transport contract is the reason Fly is replaceable. Fly supplies
the default durable remote computer, but `offloader` itself does not know about
Fly machines, volumes, or app names.

## Offloader Configurator: Auth State Is Seeded, Not Declared

`offloader-configurator` configures remote tools through the same transport
boundary. It is intentionally not a declarative remote configuration system.

The current targets are:

- `gh`: GitHub CLI auth, GitHub git credential setup, and global git identity.
- `codex`: Codex CLI auth via Codex's own `auth.json` artifact.

Each target has guard, query, and mutate scripts. The local CLI runs guards on
the remote to verify that required commands and writable config paths exist. It
queries state as JSON. For mutations, it gathers or accepts the needed local
material, wraps a validated payload, sends it over the transport, lets the
remote tool apply it in its native format, and validates the resulting JSON
state.

This is the correct boundary for auth. GitHub tokens, `gh` credential helper
state, and Codex login artifacts are not project dependencies. They are
operational credentials that belong to the remote user's persistent home on
`/data`. The container image can provide `gh`, `git`, `codex`, and `jq`, but it
must not bake in a user's credentials.

## Boondoggler: Open-Ended Agent Work

`offloader` can run any exact command, but open-ended requests need a process
that can hand a goal to a coding assistant and know when to publish the result.
That is `boondoggler`.

`boondoggler` reads a prompt from stdin, starts `codex app-server`, creates a
thread rooted at the current worktree, sets the prompt as the goal, and resumes
the thread with defaults suitable for unattended work. It watches Codex events
for goal and turn status. On completion, failure, or unexpected exit, it can
commit the current worktree state and push the current branch.

In the normal offload flow, `offloader` runs a remote shell command that pipes
the user's open-ended task into `boondoggler`. The result lands on the
`offloader/<run-id>` branch that was created for that run.

This keeps responsibilities distinct:

- `offloader` creates the remote worktree and starts the process.
- `boondoggler` owns the assistant goal lifecycle and result publication.
- Git remains the handoff and review boundary.

## Vusperize: Status Without Owning Execution

Long-running work has a different need from result publication: the user needs
to know when something important changes, without being spammed by raw logs.

`vusperize` wraps a command and creates a temporary Hermes webhook subscription.
The wrapped command receives an exported Bash function:

```text
tofiny <label> <status text>
```

When the command calls `tofiny`, `vusperize` sends a structured status event to
Hermes. Hermes can then decide, using the configured prompt and delivery target,
whether to surface that update to the user. Delivery can go to Telegram or
another Hermes-supported channel.

This is another high-level separation. `vusperize` does not decide what the
offloaded work is, does not create a worktree, does not publish results, and
does not replace `boondoggler`. It is a status plane that can wrap either exact
commands or open-ended workflows when useful.

## End-To-End Flow

A successful setup-and-run path looks like this:

1. The offload skill checks whether the current project can be rebuilt from a
   flake and whether an `x-offload` marker already says the project has been
   tested.
2. If no target is saved, the skill uses its Nixie dependency shell to run Fly
   setup commands, creates a Fly app from the `offloader-container` template,
   sets `HOSTNAME` and `NESTAIL_AUTH_SECRET`, deploys the image, and saves an
   `OFFLOADER_TRANSPORT` command locally.
3. The skill uses `offloader-configurator` through that transport to configure
   remote GitHub access. For open-ended work it also configures the assistant,
   such as Codex.
4. A small test run verifies that the remote can fetch the project and run a
   command from the worktree.
5. The real run starts through `offloader`.
6. `offloader` pushes `HEAD` to `offloader/<run-id>` and sends a remote script
   through the transport.
7. The remote target creates or refreshes its bare repo cache and run worktree.
8. The command runs inside the target worktree. Project commands can use the
   project's flake/devShell environment, and the remote machine can build missing
   Nix store paths at runtime.
9. If the command starts a dev server, Nestail exposes it through
   `https://<app>.fly.dev/<port>/`. With auth enabled, the shareable link is
   generated on the remote with `nestail token`.
10. If status updates are needed, `vusperize` wires the running workflow into
    Hermes delivery.
11. If the work is open-ended, `boondoggler` drives Codex and commits/pushes the
    result to the run branch.
12. The user reviews the branch in the normal git/GitHub workflow.

## Why The Pieces Interlock This Way

The system is built around a few deliberate tradeoffs.

The project environment follows the repo, not the machine. This puts pressure on
projects to have good flakes and dev shells, but it prevents the remote target
from becoming a magic snowflake whose installed packages quietly decide whether
work succeeds.

The machine environment is mutable, but through Home Manager. This accepts that
an agent machine must evolve at runtime, while still leaving a file-based system
configuration that can be read, reset, refreshed, cached, and reasoned about.

Git is the state transfer and result protocol. That means offloading requires a
usable git remote and remote credentials, but it also means results come back as
branches instead of opaque downloaded files.

The transport is tiny. Provider-specific concerns live at the edge, so Fly can
be the default without making Fly the architecture.

Auth state is configured imperatively. This avoids pretending that OAuth flows,
tool login artifacts, and credential helpers are good flake content. The remote
image supplies the tools; the configurator seeds each user's private state into
durable storage.

Nestail exposes exactly one public surface for localhost services. Public access
is useful for remote dev servers, but it must be route-bound and auth-gated on
Fly. Keeping the auth secret on the target and generating grants there prevents
the local setup flow from spreading machine secrets around.

Status is separate from execution. `vusperize` lets a workflow send meaningful
events into Hermes, while the command still runs normally and result publication
still happens through git.

Those choices make the system more complex than a single SSH wrapper, but they
serve the main purpose: remote work should be durable, inspectable, steerable,
and close to the semantics of the local project.

## Current Sharp Edges And Extension Points

The design still has explicit boundaries worth knowing:

- Projects without a usable flake/devShell are not good offload candidates until
  their environment is declared.
- `x-offload` is only a hint. It records known setup status; it does not prove a
  target still works.
- Nestail grant consumption is in-memory, so one-time grant state is not
  restart-proof.
- `offloader` has no built-in log or pidfile model. Status inspection uses
  worktree state, process state, and tool-specific signals.
- Fixed-command runs must publish their own results if they change files.
  `boondoggler` handles publication for open-ended Codex work.
- The visible container config establishes the Nix/Home Manager substrate and
  remote tools. Project-level `.envrc`/nix-direnv behavior remains a project
  contract that should be checked when deciding whether a repo is ready to
  offload.