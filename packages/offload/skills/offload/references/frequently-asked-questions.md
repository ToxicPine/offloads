# Offloader FAQ

Short answers to common follow-up questions. Keep replies plain: explain the idea, avoid jargon.

## "How do I see the dev server (or web page) of something I offloaded?"

The work is running on another computer, so its dev server is running there, not on the user's local
machine. `localhost:3000` points at the user's own machine, where nothing is running.

The Fly target has a small web proxy that lets the user reach services running on it. Put the port
number at the start of the path, after the Fly app address. A dev server on port `3000` becomes:

```text
https://<app>.fly.dev/3000/
```

Anything after the port, such as paths, query strings, or `#` anchors, goes after it:

```text
dev server at localhost:3000/         ->  https://<app>.fly.dev/3000/
dev server at localhost:5173/app      ->  https://<app>.fly.dev/5173/app
dev server at localhost:8000/a?x=1    ->  https://<app>.fly.dev/8000/a?x=1
```

`<app>.fly.dev` is the Fly app hostname, the same one this skill reported back. Refresh, links,
back/forward, and live connections (websockets) work through it, so it behaves like the real dev
server.

If Nestail auth is enabled, do not hand-build a grant URL locally. Generate the secure link on the
target machine, where `NESTAIL_AUTH_SECRET` is available:

```bash
printf '%s\n' 'nestail token 3000 /' | bash -c "$OFFLOADER_TRANSPORT"
```

The Telegram conversational agent on the target can do the same thing. If the exact port is unclear,
the target-side agent can work it out; its `nestail-service-urls` skill turns a port into the right
link, and `offloader-target` can tell which port the run is listening on.

## "I opened the address and nothing loads."

Check these common causes first:

- **The work has to actually be running a server.** The proxy only shows something if a dev server
  is up and listening on that port on the target machine. If the task finished, or never started a
  server, there is nothing to show. Check whether it is still running; `offloader-target` can look.
- **Wrong app hostname.** For the Fly setup, use `https://<app>.fly.dev/...` unless the user has
  configured a custom domain.
- **Right port, in the path.** Double-check the port number, and that it is in the path (`/3000/`),
  not attached to the address like `:3000`.
- **The server has to listen on the machine itself.** Most dev servers do by default. If one was
  told to bind to a specific outside address, it may not be reachable through the proxy. Have it
  listen on localhost or `0.0.0.0` on the machine.

## "Where do I find the machine's address?"

It is usually `https://<app>.fly.dev`. This skill reported the Fly app name when it sent the work
off. If it is lost, use `<offload-nix> fly status -a <app>` when the app name is known, or
`<offload-nix> fly apps list` to find likely apps.

## "Can anyone else see my dev server?"

With the straightforward Fly setup, assume the `https://<app>.fly.dev/...` URL is reachable on the
public internet. Nestail auth should be enabled with `NESTAIL_AUTH_SECRET`, and shareable grant links
should be generated on the target machine with `nestail token ...`, either through
`OFFLOADER_TRANSPORT` or the Telegram agent. Do not share unauthenticated dev-server links that expose
secrets, admin views, or private data.

## "Can I point this at my own server instead of Fly?"

Yes. `offloader` reaches the machine through a transport command set in `OFFLOADER_TRANSPORT`. Fly is
the default for this skill, but user-managed SSH and Tailscale targets are valid too:
`<offload-nix> offloader-tailscale <host>`,
`<offload-nix> offloader-ssh <host>`, or
`<skill-dir>/scripts/nix develop <skill-dir>/scripts/deps -c offloader-fly --app ... --machine ...`.
Any box reachable over SSH or Tailscale SSH can be the target. Set the transport to point at it.

A hand-rolled box needs the pieces the provisioned image normally supplies:

- A writable home directory that survives restarts.
- Repo storage. By default `offloader` keeps repos under `~/.remote-work`, with `.bare` beside
  branch-named worktree directories.
- Git credentials that can read and write the user's repos, configured through `offloader-configurator`.
- For open-ended work, the chosen coding assistant's CLI (`claude` or `codex`) installed and
  configured through `offloader-configurator`.
- For Telegram progress pings, `vusperize` installed plus the setup in `setup-telegram.md`.
- For web URLs like `https://<app>.fly.dev/<port>/`, a proxy equivalent to the provisioned
  setup.

Fixed-command hand-offs (`<skill-dir>/scripts/nix run github:ToxicPine/offloads#offloader -- -- <command>`) only need
persistent home storage and GitHub access.

## "How do I check on the work itself — progress, logs, whether it's done?"

That is separate from viewing a web page. Another skill handles it: `offloader-target` covers the
state of a handed-off run on the machine, including an open-ended coding-assistant run's progress
and completion.

That is a target-side skill. If the user is already talking to an agent on the machine, for
example through Telegram, that agent should use them directly. If you only have the local machine,
use the saved `OFFLOADER_TRANSPORT` to ask the target-side agent or configured assistant to answer
from the target and print the result locally. Finished code still comes back as the branch this skill
reported.
