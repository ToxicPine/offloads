# Coding assistants on the machine

Open-ended hand-offs use `boondoggler` to run a coding assistant on the target machine. That
assistant may be **Codex** or **Claude Code**, depending on machine and user setup. Configure the
coding assistant on the target once before using this path. If it is not configured, open-ended runs
fail before they start.

A fixed-command hand-off (`<skill-dir>/scripts/nix run github:ToxicPine/offloads#offloader -- -- <cmd>`) does not need
assistant setup.

## Configure the assistant

Use the `offloader-configurator` skill for assistant setup. It runs `offloader-configurator` over the same
transport `offloader` uses (`OFFLOADER_TRANSPORT`) and owns target-specific setup.

Use the assistant target that `offloader-configurator` supports, such as `codex`. Follow the
`offloader-configurator` skill for any account prompts, device-code flows, API keys, or token
handling. Do not duplicate those details in the offload skill.

Setup is saved on the machine's persistent disk, so it should be one-time work for each assistant.

After assistant setup, open-ended hand-offs will work:

```bash
<skill-dir>/scripts/nix run github:ToxicPine/offloads#offloader -- -- bash -lc 'printf "%s" "<task>" | nix run github:ToxicPine/offloads#boondoggler'
```

## Checking in and steering a run from your phone

Some assistants have remote-control or session-following features. After assistant setup, the user
may be able to connect from another device, watch the run, send a nudge, or point it somewhere new
without SSHing back into the machine. This is the "check in and steer" path: open-ended work keeps
running on the machine, while the user can inspect or guide it from elsewhere.

These features are assistant-specific. Enable them through that assistant's app, settings, or CLI
docs rather than expecting a fixed offload command here. The offload-side requirement is the setup
above.

**OpenCode** offers this via its built-in HTTP server, but it needs one extra step: it is password
authed and only starts when an `OPENCODE_SERVER_PASSWORD` secret is set on the target (it uses that
to enforce basic auth, so it never comes up unauthenticated). When a user wants OpenCode steering,
ask them to choose a password, set it as a secret/env variable wherever the assistant is deployed,
and offer to help persist it to their own password store (e.g. macOS Keychain) so it survives and
isn't lost.

If the user wants passive updates rather than hands-on steering, use Telegram pings instead; see
`references/setup-telegram.md`.
