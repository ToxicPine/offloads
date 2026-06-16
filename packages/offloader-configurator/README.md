# offloader-configurator

`offloader-configurator` configures known remote targets through an offloader transport. The first
target is `gh`.

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
offloader-configurator --transport "offloader-ssh box" opencode check
offloader-configurator --transport "offloader-ssh box" opencode configure
offloader-configurator --json --transport "offloader-ssh box" opencode configure --auth-json-file ./auth.json
offloader-configurator --transport "offloader-ssh box" claude check
offloader-configurator --transport "offloader-ssh box" claude configure
offloader-configurator --json --transport "offloader-ssh box" claude configure --credentials-file ./.credentials.json
```

The `codex` target configures remote Codex CLI auth by applying the same `auth.json` artifact Codex
creates for a ChatGPT/device-code login. Interactive configuration runs `codex login --device-auth`
locally under an isolated scratch `CODEX_HOME`, reads only the scratch auth artifact, removes the
scratch home, and applies that artifact remotely. It does not use OpenAI enterprise access-token
handoff, and it does not read or mutate the host's ordinary `~/.codex` credentials.

The `opencode` target follows the same artifact pattern for OpenCode. Interactive configuration runs
`opencode auth login` locally under an isolated scratch `XDG_DATA_HOME`, reads only the scratch
`opencode/auth.json`, removes the scratch home, and writes that artifact to the remote
`$XDG_DATA_HOME/opencode/auth.json`. It does not read or mutate the host's ordinary
`~/.local/share/opencode` credentials.

The `claude` target follows the same artifact pattern for Claude Code, applying the same
`.credentials.json` artifact a subscription login writes. Interactive configuration runs
`claude auth login` locally under an isolated scratch `CLAUDE_CONFIG_DIR`, reads only the scratch
`.credentials.json`, removes the scratch home, and writes that artifact to the remote
`$CLAUDE_CONFIG_DIR/.credentials.json`. It does not read or mutate the host's ordinary `~/.claude`
credentials. `claude check` and the post-configure state report Claude's own
`claude auth status
--json` fields (`authenticated`, and `authMethod`/`apiProvider` when present).
