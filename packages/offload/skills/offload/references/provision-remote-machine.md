# Set Up a Fly Machine for Offloaded Work

Use this only when no target machine exists: after selectively sourcing
`~/.offload-skill-transport`, `OFFLOADER_TRANSPORT` is unset and you cannot find an existing Fly
app/machine or user-managed server. This is one-time setup. It rents a small Fly.io Machine, deploys
the offload image, gives it persistent storage, and saves the transport command `offloader` needs.

This rents real compute and stores secrets. Confirm with the user before any step that costs money
or saves a token, password, or key.

## User-facing setup flow

Keep status updates plain and phase-based. Good wording:

- "I don't see a saved remote computer for this project yet."
- "Fly.io is logged in as `<account>`."
- "Before I create it, choose a name for your remote cloud computer. I can generate one like
  `offload-abc123def456`, or you can pick your own."
- "Which data center location should it run in? Somewhere close to you is fastest. I'd suggest
  `<nearby location>`, or I can list the alternatives."
- "The remote computer is created. I am adding the required secrets before starting it."
- "The remote computer is running. I am saving the connection details locally."
- "Next I need to connect the remote computer to GitHub so it can fetch and push branches for this
  project."
- "After that I will send the remote computer a tiny test job, to confirm it can receive work
  from this machine and push results back to your project, then run your original request."

Avoid user-facing phrases such as `OFFLOADER_TRANSPORT`, `x-offload`, "transport works", "Machine ID",
"flake marker", and "hand-off" unless the user asks for details, the exact command requires them, or
an error message contains them. It is fine to use those terms in internal commands and final
technical summaries.

Use the official Fly.io CLI, `fly`, for provisioning and management through the offload Nixie
dependency environment:

```bash
<skill-dir>/scripts/nix develop <skill-dir>/scripts/deps -c fly ...
```

For brevity, this document writes that prefix as `<offload-nix>`.

## 1. Make sure Fly is available

Check for the CLI and login:

```bash
<offload-nix> fly auth whoami
```

If that fails because Nixie or the dependency environment itself is broken, inspect
`<skill-dir>/scripts/nix` and `<skill-dir>/scripts/deps/flake.nix`. If Fly is not logged in, run
`<offload-nix> fly auth login`. If the user does not have an account, `<offload-nix> fly auth signup`
is also available.

## 2. Pick the app name and region

Offer the user two app-name choices before creating anything:

- Generate a pseudorandom name with a 12-character lowercase alphanumeric suffix, for example
  `offload-<suffix>`.
- Use a Fly app name of their own choice.

For the generated option, use the existing OpenSSL dependency:

```bash
suffix="$(<offload-nix> openssl rand -hex 6)"
app="offload-${suffix}"
```

Beyond this required name choice, ask only when the name affects billing, ownership, or sharing.

Pick a region close to where the user normally works. If unsure, run
`<offload-nix> fly platform regions` and use a nearby region. The template
currently defaults to `lhr`; override it during launch if another region is better.

## 3. Get the deployable template

Deploy from the offloader container package on the `master` branch of `ToxicPine/offloads`:

```bash
git clone --depth 1 --branch master https://github.com/ToxicPine/offloads.git <workdir>
cd <workdir>/packages/offloader-container
```

The template contains `fly.toml`, points at the ready-made offload image, mounts persistent storage
at `/data`, and exposes the agent/proxy service on Fly. Keep this checkout outside the user's project
unless they explicitly want to vendor the machine definition.

## 4. Create the Fly app without deploying

Run launch from the template checkout:

```bash
<offload-nix> fly launch --copy-config --no-deploy --name <app> --primary-region <region> --ha=false
```

Use `--org <org>` if the user needs a non-default Fly organization. `--copy-config` tells Fly to use
the existing `fly.toml`; `--no-deploy` lets you set secrets before the first Machine starts.

The `fly.toml` includes a `/data` volume mount. Fly creates the volume when the first deploy creates
the Machine. That persistent volume is what keeps GitHub credentials, assistant auth, repo caches,
and agent state across deploys and restarts.

## 5. Set machine-level secrets

Set secrets on the Fly app, not in any project repo:

```bash
<offload-nix> fly secrets set -a <app> HOSTNAME=<app>.fly.dev
```

Always generate and set a fresh Nestail auth secret before the first deploy:

```bash
secret="$(<offload-nix> openssl rand -hex 32)"
<offload-nix> fly secrets set -a <app> NESTAIL_AUTH_SECRET="$secret"
unset secret
```

`NESTAIL_AUTH_SECRET` enables Nestail's auth gate for public route URLs and transport requests. Do
not print it, commit it, paste it into docs, or reuse an example value.

The secret belongs to the remote machine. Authenticated Nestail route links must be generated on that
machine, not locally. After the machine is deployed and `OFFLOADER_TRANSPORT` is set, run `nestail
token <port> <path>` through the transport, or ask the Telegram conversational agent on the machine
to generate the link:

```bash
printf '%s\n' 'nestail token 3000 /dashboard' | bash -c "$OFFLOADER_TRANSPORT"
```

Never copy `NESTAIL_AUTH_SECRET` back to the local shell just to generate links.

Use `<offload-nix> fly secrets set -a <app> KEY=value` for any other
machine-level credentials. Fly injects these as runtime environment variables. `fly secrets set`
restarts existing Machines, so prefer setting initial secrets before the first deploy when possible.

Do not put project-specific secrets here unless the machine itself needs them. Project secrets belong
in the project devShell or an encrypted project file such as `age` or `sops`.

## 6. Deploy the machine

From the template checkout:

```bash
<offload-nix> fly deploy -a <app>
```

After deploy, check the app and find the Machine ID:

```bash
<offload-nix> fly status -a <app>
<offload-nix> fly machine list -a <app>
```

If Fly creates more than one Machine and this is meant to be a single persistent offload target,
choose one Machine and avoid spreading state across multiple volumes. Ask the user before destroying
extra Machines or volumes, because that can delete state.

## 7. Save the offloader transport

Save `OFFLOADER_TRANSPORT` in `~/.offload-skill-transport`. Use the full Nixie-backed Fly transport
so it works even when `offloader-fly` is not globally installed:

```bash
cat > "$HOME/.offload-skill-transport" <<'EOF'
export OFFLOADER_TRANSPORT='<skill-dir>/scripts/nix develop <skill-dir>/scripts/deps -c offloader-fly --app <app> --machine <machine-id>'
EOF
chmod 600 "$HOME/.offload-skill-transport"
```

Keep the app and Machine ID local to the user's setup rather than treating them as portable skill
defaults. Do not require the user's shell profile or project direnv to load the file globally; source
it only in commands that need to check or use the saved offload target.

Optionally verify the saved connection with a command that only uses POSIX shell builtins:

```bash
if [ -z "${OFFLOADER_TRANSPORT:-}" ] && [ -r "$HOME/.offload-skill-transport" ]; then
  . "$HOME/.offload-skill-transport"
fi
printf '%s\n' 'printf "%s\n" remote-ok; pwd' | bash -c "$OFFLOADER_TRANSPORT"
```

Do not use incidental tools such as `hostname` for this check; the target image may not include
them. Do not tell the user "the transport works". Say the remote computer is reachable, then move to
GitHub setup.

## 8. Configure GitHub and a coding assistant

`offloader` sends work by pushing a branch to the project's git remote. The machine then clones or
fetches that branch, does the work, and, on the open-ended path, pushes results back. The machine
needs GitHub credentials that can read and write the user's repos, plus a name and email for commits.
The provisioned machine also needs a coding assistant, such as Codex or Claude Code, authenticated
on the machine. Configure both before the first real hand-off.

Before running these commands, tell the user:

> The remote computer is running. Next I need to connect it to GitHub so it can fetch this project
> and push result branches back.

Use the `offloader-configurator` skill for this setup. It runs `offloader-configurator` over the same transport
`offloader` will use:

```bash
if [ -z "${OFFLOADER_TRANSPORT:-}" ] && [ -r "$HOME/.offload-skill-transport" ]; then
  . "$HOME/.offload-skill-transport"
fi
<skill-dir>/scripts/nix run github:ToxicPine/offloads#offloader-configurator -- --transport "$OFFLOADER_TRANSPORT" gh check
<skill-dir>/scripts/nix run github:ToxicPine/offloads#offloader-configurator -- --transport "$OFFLOADER_TRANSPORT" gh configure
```

Next, continue with `assistants-on-the-machine.md` and configure an assistant target that
`offloader-configurator` supports, such as `codex`. That reference also covers access from another
device. Follow the `offloader-configurator` skill for account prompts and credentials.

## 9. Try a tiny run before anything real

Do one trivial hand-off end to end before sending important work, e.g. from a test repo:

```bash
<skill-dir>/scripts/nix run github:ToxicPine/offloads#offloader -- -- bash -lc 'echo ok && git rev-parse HEAD'
```

Confirm the run branch shows up and the machine reached the repo. Once that is clean, go back to the
offload skill and send the real task.

Tell the user this is a final setup check before their requested command, not another setup choice.

## Maintenance commands

Use official Fly commands for routine checks:

- `<offload-nix> fly status -a <app>`: app state and Machines summary.
- `<offload-nix> fly logs -a <app>`: app logs.
- `<offload-nix> fly machine list -a <app>`: Machine IDs.
- `<offload-nix> fly ssh console -a <app> --machine <machine-id>`: interactive shell.
- `<offload-nix> fly ssh console -a <app> --machine <machine-id> -C '<command>'`: run one command.
- `<offload-nix> fly secrets list -a <app>` and `<offload-nix> fly secrets set -a <app> KEY=value`: secret names and updates.
- `<offload-nix> fly volumes list -a <app>`: persistent volumes.

Secrets rule: anything the machine itself needs, such as tokens or keys, goes in Fly app secrets
with `<offload-nix> fly secrets set -a <app> ...` and stays out of projects.
Anything the work needs, such as per-project settings, goes in the project's devShell or in an
encrypted project file.

When attaching to an existing Fly app, run `fly secrets list -a <app>` and confirm
`NESTAIL_AUTH_SECRET` is present. If it is missing, generate it with
`<offload-nix> openssl rand -hex 32` and set it with
`<offload-nix> fly secrets set -a <app> NESTAIL_AUTH_SECRET="$secret"` before
handing off work. Tell the user that adding or changing Fly secrets can restart the Machine.

For existing apps too, generate authenticated Nestail links on the remote target through
`OFFLOADER_TRANSPORT` or the Telegram agent. The local machine should not need to know the auth secret.
