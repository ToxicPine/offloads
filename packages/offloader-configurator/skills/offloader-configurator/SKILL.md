---
name: offloader-configurator
description: Use this to check or configure auth and config state on a remote device via a Offloader transport -- this is `offloader-configurator`.
---

# Offloader Config Workflow

Use `offloader-configurator` when the user wants to check or seed known remote tool config or auth state
through a Offloader-style transport. It configures interactive tool state on the remote; it is not a
declarative machine configuration system.

The transport uses the same contract as Offloader: one local command reads a bash script from stdin,
runs it on the remote under bash, and forwards stdout, stderr, and exit status. Pass it with
`--transport` or set `OFFLOADER_CONFIG_TRANSPORT`.

```bash
export OFFLOADER_CONFIG_TRANSPORT='offloader-ssh box'
offloader-configurator gh check
offloader-configurator gh configure
```

Each target owns its own checks, mutation options, and reporting fields. The current targets are
`gh` and `codex`.

## GitHub Target

The `gh` target checks or configures GitHub CLI auth, GitHub git credential setup, and global git
identity on the remote.

Use `gh check` when the user asks whether the remote is ready:

```bash
offloader-configurator --transport "offloader-ssh box" gh check
```

The remote must have `gh`, `git`, and `jq` on `PATH`. Its GitHub CLI config directory and global git
config must be writable or creatable.

Use `gh configure` to seed auth and optional identity:

```bash
offloader-configurator --transport "offloader-ssh box" gh configure \
  --git-user-name "User Name" \
  --git-user-email "user@example.com"
```

In interactive mode, if no token is passed, the local command tries
`gh auth token --hostname github.com`. If no local token is available, it starts
`gh auth login --hostname github.com --web` locally and then reads the token. The token is sent over
the transport to run `gh auth login --with-token` on the remote, followed by `gh auth setup-git`.

For noninteractive or scripted use, pass JSON mode and provide all mutation data explicitly. For
`gh configure`, this means passing the token:

```bash
offloader-configurator --json --transport "offloader-ssh box" gh configure --token "$GITHUB_TOKEN"
```

Never print or paste token values in the final response. Report only whether configuration
succeeded, the transport/remote used, the authenticated account when shown, and the resulting git
identity or credential helper fields.

## Codex Target

The `codex` target checks or configures Codex CLI auth on the remote by applying Codex's own
`auth.json` device-login artifact.

Use `codex check` when the user asks whether remote Codex is logged in:

```bash
offloader-configurator --transport "offloader-ssh box" codex check
```

The remote must have `codex` and `jq` on `PATH`, and its `CODEX_HOME` or default `~/.codex` must be
writable or creatable.

Use `codex configure` to seed remote Codex auth without logging in on the remote:

```bash
offloader-configurator --transport "offloader-ssh box" codex configure
```

In interactive mode, the local command runs `codex login --device-auth` under an isolated scratch
`CODEX_HOME`, reads only the scratch `auth.json`, removes the scratch home, and sends that artifact
over the transport. This must not read, overwrite, refresh, or log out the user's ordinary host
`~/.codex` credentials.

For noninteractive or scripted use, pass JSON mode and provide the complete auth artifact
explicitly:

```bash
offloader-configurator --json --transport "offloader-ssh box" codex configure --auth-json-file ./auth.json
```

Do not use `codex login --with-access-token`, OpenAI enterprise access tokens, or access-token
handoff for this target. Never print or paste Codex auth artifact contents in the final response.
Report only whether configuration succeeded and the resulting `authenticated`, `codexHome`,
`authJsonPresent`, and `loginStatus` fields.

## Useful Options

- `--transport COMMAND STRING` selects the remote transport for one invocation.
- `OFFLOADER_CONFIG_TRANSPORT` provides the default transport command.
- `--json` makes CLI output machine-readable and disables interactive completion of missing mutation
  data.
- `gh configure --token TOKEN` supplies the GitHub token directly.
- `gh configure --git-user-name NAME` sets remote global `git config user.name`.
- `gh configure --git-user-email EMAIL` sets remote global `git config user.email`.
- `codex configure --auth-json-file PATH` supplies a Codex `auth.json` artifact for noninteractive
  configuration.

## What To Report

After `gh check`, report whether the remote is ready and name any missing requirement.

After `gh configure`, report:

- The target and command, e.g. `gh configure`.
- The transport target, e.g. `offloader-ssh box`.
- Whether `gh` is authenticated.
- The GitHub account, host, git user name/email, and credential helper if present.

If the transport fails, say which transport command was used and include the error detail from
`offloader-configurator`.

After `codex check` or `codex configure`, report:

- The target and command, e.g. `codex configure`.
- The transport target, e.g. `offloader-ssh box`.
- Whether Codex is authenticated.
- The Codex home path, whether `auth.json` is present, and the login status text when shown.

Never include `auth.json` contents.
