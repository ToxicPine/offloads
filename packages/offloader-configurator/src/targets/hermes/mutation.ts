import type { CliIo } from "../../lib/out.ts";
import { err, ok, type Result } from "../../lib/result.ts";
import {
  type HermesInput,
  hermesInputToMutationShape,
  readHermesAuthJsonFile,
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
    type: "local-hermes-failed";
    detail: unknown;
  };

export default async function completeHermesInput(
  input: HermesInput,
  io: CliIo,
): Promise<Result<MutationPayload, MutationPlanningError>> {
  switch (input.type) {
    case "configure":
      return await completeConfigureInput(input, io);
  }
}

async function completeConfigureInput(
  input: Extract<HermesInput, { type: "configure" }>,
  io: CliIo,
): Promise<Result<MutationPayload, MutationPlanningError>> {
  if (input.authJsonFile) {
    return parseMutation(() => hermesInputToMutationShape(input));
  }

  const authJson = await captureLocalHermesAuthJson(input.provider, io);
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

async function captureLocalHermesAuthJson(
  provider: string,
  io: CliIo,
): Promise<Result<MutationPayload["authJson"], MutationPlanningError>> {
  const scratchParent = await ensureScratchParent();
  if (!scratchParent.ok) {
    return scratchParent;
  }

  const scratch = await Deno.makeTempDir({
    dir: scratchParent.value,
    prefix: "hermes-",
  });
  const hermesHome = `${scratch}/hermes`;
  const home = `${scratch}/home`;
  const authJson = `${hermesHome}/auth.json`;

  await Deno.mkdir(hermesHome);
  await Deno.mkdir(home);

  try {
    io.stdout.writeSync(
      encoder.encode(
        `Starting isolated \`hermes auth add ${provider} --type oauth\`.\n`,
      ),
    );

    const login = await runHermes(
      ["auth", "add", provider, "--type", "oauth"],
      hermesHome,
      home,
    );
    if (!login.ok) {
      return login;
    }

    try {
      return ok(readHermesAuthJsonFile(authJson));
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
      type: "local-hermes-failed",
      detail: "HOME is not set",
    });
  }

  const scratchParent = `${home}/.cache/offloader-configurator`;
  try {
    await Deno.mkdir(scratchParent, { recursive: true });
    return ok(scratchParent);
  } catch (error) {
    return err({
      type: "local-hermes-failed",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}

async function runHermes(
  args: string[],
  hermesHome: string,
  home: string,
): Promise<Result<undefined, MutationPlanningError>> {
  try {
    const status = await new Deno.Command("hermes", {
      args,
      env: {
        HERMES_HOME: hermesHome,
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
      type: "local-hermes-failed",
      detail: `hermes ${args.join(" ")} exited with code ${status.code}`,
    });
  } catch (error) {
    return err({
      type: "local-hermes-failed",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}
