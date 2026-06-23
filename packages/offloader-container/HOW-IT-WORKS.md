# How the Container Build Works

## What I was trying to build

I set out to build a Docker container that behaves like a real multi-user
Linux box — different users, each with their own packages installed, their own
shell setup, and so on. The key requirement was this: I wanted to be able to
**change the configuration while the container is running**, without rebuilding
and redeploying the image. Add a package, bump a version, extend the
environment — all live, on a running container.

That one property unlocks a different way of building software. Instead of one
big shared backend that takes in HTTP requests, queues up work, and drains that
queue across a pool of workers, you give **each customer their own container**.
One environment per user. How information moves through the system becomes a
question of networking policy between these containers, not of routing inside a
monolithic backend. For a personal agent system — one AI agent per person —
this is exactly what you want: a single, private backend per customer that the
agent can reshape as it goes. The ability to mutate the environment at runtime
is the whole thing that makes this possible.

## Two things to notice up front

Before any details, two things will look strange, and both are deliberate:

1. **There is no Dockerfile.** Look around the project — you won't find one.
   That's because we don't write a Dockerfile; we use **Nix** to *derive* the
   Docker image directly.

2. **There are two copies of Nix in play, and they do different jobs.** One
   runs at *build time*, one runs at *runtime*. Keeping these straight is the
   single most important idea here, so it comes first.

Nix, for context, is a package manager with its own configuration language. A
Nix config is just a description: which packages should exist, how the shell is
set up, what the environment looks like. You write the description; Nix makes it
real.

## Build-time Nix vs. runtime Nix

**Build-time Nix** is what produces the Docker image. It does *not* try to
install the full environment into the image. It builds something almost empty:
just enough to bootstrap Nix itself inside the container — Nix, a shell, and a
handful of core tools. That's the image. A seed, not the finished plant.

**Runtime Nix** is the copy that lives *inside* the container and runs when the
container boots. This is the one that does the real work: it reads the Nix
configs and from them *derives* the actual multi-user environment — the users,
their packages, their shells. The rich, configurable system you actually use is
constructed at runtime, not baked into the image.

So the flow is: build-time Nix makes a tiny container that knows how to run
Nix → runtime Nix uses the configs to populate the system with everything else.

## The store: a data partition full of packages

Concretely, what runtime Nix populates is the **Nix store**. Think of it as a
data partition that holds all the installed packages. The Nix config — known
when the container is running — is what fills that partition. Once the store is
populated, the users, tools, and shells described by the config all exist and
work. That's the mechanism behind the whole thing: *config in, populated store
out, working environment.*

## Why first boot is still fast

There's a nice subtlety. Runtime Nix builds the environment from a config, and
the **default** environment comes from a default template. That means the base
config isn't really a runtime mystery — we already know, at *build time*, what
the default environment will contain.

So we cheat in our favor: at build time we **pre-cache every package the
default config needs** straight into the image. When a container boots with the
default setup, all those packages are already present — no big download or build
step before it's usable. You get fast boot for the common case, while still
keeping full runtime freedom to change the config and have Nix build whatever
new packages that requires (those, in turn, get cached too, so asking for them
again is fast).

## Where this is going

The reason this design matters: it's a foundation for an **LLM-driven
enterprise operating system**. Each user gets their own container that an agent
can progressively reshape — installing the exact tools a task needs, adjusting
the environment, all while it runs. You get deep per-user customizability and
the ability to update users one at a time, independently, without redeploying
anything. That combination — one private environment per customer, mutable at
runtime by the agent that lives in it — is what makes a per-customer agent OS
practical instead of a single shared backend everyone fights over.
