import { err, ok, type Result } from "./result.ts";

export type CliMode = "json" | "interactive";

export type CliOptions = {
  json: boolean;
  transport?: string;
  target: string;
  command: string;
  targetArgs: string[];
};

export type ParseError = {
  type: "help" | "invalid-args";
  json: boolean;
  message?: string;
};

export const usage =
  `Usage: offloader-configurator [global-options] TARGET COMMAND [target-command-options]

Configure a known target on a remote machine through an offloader transport.

Global options:
  --transport COMMAND STRING      Transport that runs a bash script from stdin.
  --json                          Read/write local CLI data as JSON.
  -h, --help                      Show this help.

Environment:
  OFFLOADER_CONFIG_TRANSPORT        Transport command string fallback.

Targets:
  gh check
  gh configure [--token TOKEN] [--git-user-name NAME] [--git-user-email EMAIL]
  codex check
  codex configure [--auth-json-file PATH]
  opencode check
  opencode configure [--auth-json-file PATH]
  claude check
  claude configure [--credentials-file PATH]
  hermes check
  hermes configure [--provider ID] [--auth-json-file PATH]

Examples:
  offloader-configurator --transport "offloader-ssh box" gh check
  offloader-configurator --json --transport "offloader-ssh box" gh configure --token "$GITHUB_TOKEN"
  offloader-configurator --transport "offloader-ssh box" codex check
  offloader-configurator --transport "offloader-ssh box" opencode configure
  offloader-configurator --transport "offloader-ssh box" claude configure
  offloader-configurator --transport "offloader-ssh box" hermes configure
`;

export function parseCliArgs(argv: string[]): Result<CliOptions, ParseError> {
  let json = false;
  let transport: string | undefined;
  let target: string | undefined;
  let command: string | undefined;
  const targetArgs: string[] = [];

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];

    if (!target || !command) {
      if (arg === "--json") {
        json = true;
        continue;
      }

      if (arg === "-h" || arg === "--help") {
        return err({ type: "help", json });
      }

      if (arg === "--transport") {
        const value = argv[index + 1];
        if (!value) {
          return err({
            type: "invalid-args",
            json,
            message: "--transport requires a value",
          });
        }
        transport = value;
        index += 1;
        continue;
      }

      if (arg.startsWith("--transport=")) {
        transport = arg.slice("--transport=".length);
        if (!transport) {
          return err({
            type: "invalid-args",
            json,
            message: "--transport requires a value",
          });
        }
        continue;
      }

      if (!target) {
        target = arg;
      } else {
        command = arg;
      }
      continue;
    }

    targetArgs.push(arg);
  }

  if (!target || !command) {
    return err({
      type: "invalid-args",
      json,
      message: "TARGET and COMMAND are required",
    });
  }

  return ok({
    json,
    transport,
    target,
    command,
    targetArgs,
  });
}
