# Coding assistants on the machine

Open-ended hand-offs run a coding assistant's own CLI on the target machine (see
`open-ended-runs.md`). That assistant may be **Codex** or **Claude Code**, depending on machine and
user setup. Configure the coding assistant on the target once before using this path. If it is not
configured, open-ended runs fail before they start.

A fixed-command hand-off (`<skill-dir>/scripts/nix run github:ToxicPine/offloads#offloader -- -- <cmd>`) does not need
assistant setup.

## Configure the assistant

Use the `offloader-configurator` skill for assistant setup. It runs `offloader-configurator` over the same
transport `offloader` uses (`OFFLOADER_TRANSPORT`) and owns target-specific setup.

Use the assistant target that `offloader-configurator` supports, such as `codex`. Follow the
`offloader-configurator` skill for any account prompts, device-code flows, API keys, or token
handling. Do not duplicate those details in the offload skill.

Setup is saved on the machine's persistent disk, so it should be one-time work for each assistant.

After assistant setup, open-ended hand-offs will work: compose the harness invocation and publish
wrapper from `open-ended-runs.md` and dispatch it through `offloader`.

## Checking in and steering a run from your phone

The coding assistants can be driven from another device while an open-ended run keeps going on the
machine: the user connects from their phone or laptop, watches the run, sends a nudge, or points it
somewhere new without SSHing back in. This is the "check in and steer" path — the work stays on the
machine; the user inspects or guides it from elsewhere.

The feature exists across the assistants, but how the user reaches it differs, and for Claude Code
and Codex it only appears once that assistant's CLI is authenticated on the target (the setup
above) — an unauthenticated assistant has no signed-in session to show, so remote control never
surfaces. Beyond that, enable it through the assistant's own app or CLI rather than expecting a
fixed offload command here.

- **Codex** needs an explicit pairing step. Once Codex is authenticated on the target, run
  `codex remote-control pair` there so the run becomes controllable from the user's devices; recent
  Codex versions do not expose remote control until this pairing happens.
- **Claude Code** needs no pairing. Once Claude Code is authenticated on the target with the user's
  account, the run shows up for remote control wherever the user is signed in to that same account —
  matching accounts is the only requirement.
- **OpenCode** is reached through its built-in HTTP server: the user opens a link to where that
  server runs. It is password authed and only starts when an `OPENCODE_SERVER_PASSWORD` secret is
  set on the target (it uses that to enforce basic auth, so it never comes up unauthenticated). When
  a user wants OpenCode steering, ask them to choose a password, set it as a secret/env variable
  wherever the assistant is deployed, and offer to help persist it to their own password store (e.g.
  macOS Keychain) so it survives and isn't lost.

If the user wants passive updates rather than hands-on steering, use Telegram pings instead; see
`references/setup-telegram.md`.
