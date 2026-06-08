# offloader-configurator

`offloader-configurator` configures known remote targets through an offloader transport. The first target is
`gh`.

This tool is intentionally an interactive seeding mechanism, not a declarative remote configuration
system.

Some remote setup can be expressed declaratively, but auth state usually does not fit that model
cleanly. Tokens, credential helpers, account state, refresh behavior, and tool-owned auth files are
often ephemeral artifacts managed by the tool itself. For those cases, the reliable path is to let
the local side gather or create the needed auth/config material, send a narrow validated mutation
over the transport, and then ask the remote tool to apply it in the way it already understands.

```sh
offloader-configurator --transport "offloader-ssh box" gh check
offloader-configurator --transport "offloader-ssh box" gh configure
offloader-configurator --json --transport "offloader-ssh box" gh configure --token "$GITHUB_TOKEN"
offloader-configurator --transport "offloader-ssh box" codex check
offloader-configurator --transport "offloader-ssh box" codex configure
offloader-configurator --json --transport "offloader-ssh box" codex configure --auth-json-file ./auth.json
```

The `codex` target configures remote Codex CLI auth by applying the same `auth.json` artifact Codex
creates for a ChatGPT/device-code login. Interactive configuration runs `codex login --device-auth`
locally under an isolated scratch `CODEX_HOME`, reads only the scratch auth artifact, removes the
scratch home, and applies that artifact remotely. It does not use OpenAI enterprise access-token
handoff, and it does not read or mutate the host's ordinary `~/.codex` credentials.
