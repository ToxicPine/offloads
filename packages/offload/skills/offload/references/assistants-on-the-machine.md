# Coding assistants on the machine

This file covers one-time assistant setup, authentication, and access from another device;
`open-ended-runs.md` covers individual runs.

A fixed-command hand-off does not need assistant setup.

## Assistant authentication on the machine

During first-time machine setup, use the `offloader-configurator` skill to authenticate the chosen
assistant. After that, let the launch attempt be the check: if it reports a setup or authentication
failure, use the same skill to repair it, then retry. Follow that skill for account prompts and
credentials; setup persists on the machine.

## Checking in and steering a run from another device

Remote steering is assistant-specific and is not enabled by the normal noninteractive run wrapper.

### Codex: authenticate, start, then pair

Codex remote control requires Codex authentication on the target. Start it and generate a pairing
code:

```bash
codex remote-control start
codex remote-control pair
```

The user completes pairing on the controlling Codex/ChatGPT device. Pairing is additional to account
login, and an ordinary app-server run is not automatically remotely steerable.

### Claude Code: authenticate the same account; no pairing step

Claude Code Remote Control requires a Claude.ai subscription login on the target; API-key auth and
`claude setup-token` do not qualify. Start it from the trusted project directory:

```bash
claude remote-control
```

It appears on `claude.ai/code` and in the Claude mobile app for the same account and organization;
there is no separate pairing step. Team or Enterprise policy can disable it. An ordinary
`claude -p` run is not a Remote Control session.

### OpenCode: connect to its server

OpenCode uses its own server through the already-protected proxy, so no server password is needed.

If the user wants passive updates rather than hands-on steering, use Telegram pings instead; see
`references/setup-telegram.md`.
