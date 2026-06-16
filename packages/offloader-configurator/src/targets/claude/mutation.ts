import type { CliIo } from "../../lib/out.ts";
import { err, ok, type Result } from "../../lib/result.ts";
import {
  type ClaudeInput,
  claudeInputToMutationShape,
  readClaudeCredentialsFile,
} from "./arg-schema.ts";
import { type MutationPayload, mutationSchema } from "./mutation-schema.ts";

export type MutationPlanningError =
  | {
    type: "missing-input";
    detail: unknown;
  }
  | {
    type: "invalid-mutation";
    detail: unknown;
  }
  | {
    type: "local-claude-failed";
    detail: unknown;
  };

export default async function completeClaudeInput(
  input: ClaudeInput,
  io: CliIo,
): Promise<Result<MutationPayload, MutationPlanningError>> {
  switch (input.type) {
    case "configure":
      return await completeConfigureInput(input, io);
  }
}

async function completeConfigureInput(
  input: Extract<ClaudeInput, { type: "configure" }>,
  io: CliIo,
): Promise<Result<MutationPayload, MutationPlanningError>> {
  if (input.credentialsFile || input.oauthToken) {
    return parseMutation(() => claudeInputToMutationShape(input));
  }

  if (input.useToken) {
    const oauthToken = await captureLocalClaudeToken(io);
    if (!oauthToken.ok) {
      return oauthToken;
    }

    return parseMutation(() => ({
      type: "configure-token",
      oauthToken: oauthToken.value,
    }));
  }

  const credentials = await captureLocalClaudeCredentials(io);
  if (!credentials.ok) {
    return credentials;
  }

  return parseMutation(() => ({
    type: "configure-credentials",
    credentials: credentials.value,
  }));
}

function parseMutation(
  shape: () => unknown,
): Result<MutationPayload, MutationPlanningError> {
  try {
    const payload = mutationSchema.safeParse(shape());
    if (!payload.success) {
      return err({
        type: "invalid-mutation",
        detail: payload.error.issues,
      });
    }

    return ok(payload.data);
  } catch (error) {
    return err({
      type: "missing-input",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}

const encoder = new TextEncoder();

async function captureLocalClaudeCredentials(
  io: CliIo,
): Promise<
  Result<
    Extract<MutationPayload, { type: "configure-credentials" }>["credentials"],
    MutationPlanningError
  >
> {
  const scratchParent = await ensureScratchParent();
  if (!scratchParent.ok) {
    return scratchParent;
  }

  const scratch = await Deno.makeTempDir({
    dir: scratchParent.value,
    prefix: "claude-",
  });
  const claudeConfigDir = `${scratch}/claude`;
  const home = `${scratch}/home`;
  const credentialsJson = `${claudeConfigDir}/.credentials.json`;

  await Deno.mkdir(claudeConfigDir);
  await Deno.mkdir(home);

  try {
    io.stdout.writeSync(
      encoder.encode(
        "Starting isolated Claude login under a scratch CLAUDE_CONFIG_DIR. " +
          "Complete the login, then exit Claude (for example with /exit) to continue.\n",
      ),
    );

    const login = await runClaude([], claudeConfigDir, home);
    if (!login.ok) {
      return login;
    }

    try {
      return ok(readClaudeCredentialsFile(credentialsJson));
    } catch (error) {
      return err({
        type: "missing-input",
        detail: error instanceof Error ? error.message : String(error),
      });
    }
  } finally {
    await Deno.remove(scratch, { recursive: true });
  }
}

async function captureLocalClaudeToken(
  io: CliIo,
): Promise<Result<string, MutationPlanningError>> {
  io.stdout.writeSync(encoder.encode("Starting `claude setup-token`.\n"));

  try {
    const output = await new Deno.Command("claude", {
      args: ["setup-token"],
      stdin: "inherit",
      stdout: "piped",
      stderr: "inherit",
    }).output();

    if (output.code !== 0) {
      return err({
        type: "local-claude-failed",
        detail: `claude setup-token exited with code ${output.code}`,
      });
    }

    const token = lastNonEmptyLine(new TextDecoder().decode(output.stdout));
    if (!token) {
      return err({
        type: "missing-input",
        detail: "claude setup-token produced no token",
      });
    }

    return ok(token);
  } catch (error) {
    return err({
      type: "local-claude-failed",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}

function lastNonEmptyLine(text: string): string {
  const lines = text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
  return lines.length === 0 ? "" : lines[lines.length - 1];
}

async function ensureScratchParent(): Promise<
  Result<string, MutationPlanningError>
> {
  const home = Deno.env.get("HOME");
  if (!home) {
    return err({
      type: "local-claude-failed",
      detail: "HOME is not set",
    });
  }

  const scratchParent = `${home}/.cache/offloader-configurator`;
  try {
    await Deno.mkdir(scratchParent, { recursive: true });
    return ok(scratchParent);
  } catch (error) {
    return err({
      type: "local-claude-failed",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}

async function runClaude(
  args: string[],
  claudeConfigDir: string,
  home: string,
): Promise<Result<undefined, MutationPlanningError>> {
  try {
    const status = await new Deno.Command("claude", {
      args,
      env: {
        CLAUDE_CONFIG_DIR: claudeConfigDir,
        HOME: home,
      },
      stdin: "inherit",
      stdout: "inherit",
      stderr: "inherit",
    }).spawn().status;

    if (status.code === 0) {
      return ok(undefined);
    }

    return err({
      type: "local-claude-failed",
      detail: `claude ${args.join(" ")} exited with code ${status.code}`,
    });
  } catch (error) {
    return err({
      type: "local-claude-failed",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}
