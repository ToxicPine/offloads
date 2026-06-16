import type { CliIo } from "../../lib/out.ts";
import { err, ok, type Result } from "../../lib/result.ts";
import {
  type OpencodeInput,
  opencodeInputToMutationShape,
  readOpencodeAuthJsonFile,
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
    type: "local-opencode-failed";
    detail: unknown;
  };

export default async function completeOpencodeInput(
  input: OpencodeInput,
  io: CliIo,
): Promise<Result<MutationPayload, MutationPlanningError>> {
  switch (input.type) {
    case "configure":
      return await completeConfigureInput(input, io);
  }
}

async function completeConfigureInput(
  input: Extract<OpencodeInput, { type: "configure" }>,
  io: CliIo,
): Promise<Result<MutationPayload, MutationPlanningError>> {
  if (input.authJsonFile) {
    return parseMutation(() => opencodeInputToMutationShape(input));
  }

  const authJson = await captureLocalOpencodeAuthJson(io);
  if (!authJson.ok) {
    return authJson;
  }

  return parseMutation(() => ({
    type: "configure",
    authJson: authJson.value,
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

async function captureLocalOpencodeAuthJson(
  io: CliIo,
): Promise<Result<MutationPayload["authJson"], MutationPlanningError>> {
  const scratchParent = await ensureScratchParent();
  if (!scratchParent.ok) {
    return scratchParent;
  }

  const scratch = await Deno.makeTempDir({
    dir: scratchParent.value,
    prefix: "opencode-",
  });
  const dataHome = `${scratch}/data`;
  const home = `${scratch}/home`;
  const authJson = `${dataHome}/opencode/auth.json`;

  await Deno.mkdir(dataHome);
  await Deno.mkdir(home);

  try {
    io.stdout.writeSync(
      encoder.encode("Starting isolated `opencode auth login`.\n"),
    );

    const login = await runOpencode(
      ["auth", "login"],
      dataHome,
      home,
      "inherit",
    );
    if (!login.ok) {
      return login;
    }

    try {
      return ok(readOpencodeAuthJsonFile(authJson));
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

async function ensureScratchParent(): Promise<
  Result<string, MutationPlanningError>
> {
  const home = Deno.env.get("HOME");
  if (!home) {
    return err({
      type: "local-opencode-failed",
      detail: "HOME is not set",
    });
  }

  const scratchParent = `${home}/.cache/offloader-configurator`;
  try {
    await Deno.mkdir(scratchParent, { recursive: true });
    return ok(scratchParent);
  } catch (error) {
    return err({
      type: "local-opencode-failed",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}

async function runOpencode(
  args: string[],
  dataHome: string,
  home: string,
  stdio: "inherit" | "piped",
): Promise<Result<undefined, MutationPlanningError>> {
  try {
    const command = new Deno.Command("opencode", {
      args,
      env: {
        XDG_DATA_HOME: dataHome,
        HOME: home,
      },
      stdin: stdio === "inherit" ? "inherit" : "null",
      stdout: stdio,
      stderr: stdio,
    });

    const code = stdio === "inherit"
      ? (await command.spawn().status).code
      : (await command.output()).code;

    if (code === 0) {
      return ok(undefined);
    }

    return err({
      type: "local-opencode-failed",
      detail: `opencode ${args.join(" ")} exited with code ${code}`,
    });
  } catch (error) {
    return err({
      type: "local-opencode-failed",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}
