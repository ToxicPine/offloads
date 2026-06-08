---
name: vusperize-status-updates
description: Use when wrapping a running workflow with `vusperize` so a Hermes-backed LLM agent can receive live status updates and decide when to surface them to the user.
---

# Vusperize Status Updates

Use `vusperize` when a command should be able to send live workflow status updates to a Hermes webhook route while it runs.

The wrapped command receives an exported Bash function named `tofiny`. Call it with a short label or type and the status update text:

```bash
tofiny started "Beginning the deploy"
tofiny progress "Finished the build; starting smoke tests"
tofiny blocked "Waiting for credentials"
tofiny done "Deploy completed"
```

The first argument is only a label or type. The remaining arguments are joined into the status update text.

Typical usage:

```bash
vusperize -- bash -lc '
  tofiny started "Starting deploy"
  npm run build
  tofiny progress "Build finished"
  npm run test
  tofiny done "Deploy checks finished"
'
```

`vusperize` creates a temporary Hermes webhook subscription before the command runs and removes it on exit.

## Delivery Options

Use `--deliver TARGET` to send rendered updates through a delivery target such as Telegram, Discord, or Slack. Use `--deliver-chat-id ID` when that target needs a chat or channel id.

Use `--deliver-only` only with a non-log delivery target when the rendered prompt should be delivered directly rather than processed by the agent.

## Missing Hermes

`vusperize` requires the `hermes` CLI to be on `PATH`. If Hermes is missing, it exits before running the wrapped command and prints a clear error.
