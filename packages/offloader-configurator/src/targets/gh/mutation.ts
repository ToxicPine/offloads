import type { CliIo } from "../../lib/out.ts";
import { err, ok, type Result } from "../../lib/result.ts";
import { type GhInput, ghInputToMutationShape } from "./arg-schema.ts";
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
      type: "local-gh-failed";
      detail: unknown;
    };

export default async function completeGhInput(
  input: GhInput,
  io: CliIo,
): Promise<Result<MutationPayload, MutationPlanningError>> {
  switch (input.type) {
    case "configure":
      return await completeConfigureInput(input, io);
  }
}

async function completeConfigureInput(
  input: Extract<GhInput, { type: "configure" }>,
  io: CliIo,
): Promise<Result<MutationPayload, MutationPlanningError>> {
  const token = input.token ? ok(input.token) : await getLocalGhToken(io);
  if (!token.ok) {
    return token;
  }

  const payload = mutationSchema.safeParse(
    ghInputToMutationShape({ ...input, token: token.value }),
  );
  if (!payload.success) {
    return err({
      type: "invalid-mutation",
      detail: payload.error.issues,
    });
  }

  return ok(payload.data);
}

const encoder = new TextEncoder();

async function getLocalGhToken(
  io: CliIo,
): Promise<Result<string, MutationPlanningError>> {
  const existing = await readLocalGhToken();
  if (existing.ok) {
    return existing;
  }

  io.stdout.writeSync(
    encoder.encode("No local GitHub token found. Starting `gh auth login`.\n"),
  );

  const login = await runInteractiveGhLogin();
  if (!login.ok) {
    return login;
  }

  return await readLocalGhToken();
}

async function readLocalGhToken(): Promise<
  Result<string, MutationPlanningError>
> {
  try {
    const output = await new Deno.Command("gh", {
      args: ["auth", "token", "--hostname", "github.com"],
      stdout: "piped",
      stderr: "piped",
    }).output();

    const token = new TextDecoder().decode(output.stdout).trim();
    if (output.code === 0 && token) {
      return ok(token);
    }

    return err({
      type: "missing-input",
      detail:
        new TextDecoder().decode(output.stderr).trim() ||
        "local gh token is unavailable",
    });
  } catch (error) {
    return err({
      type: "local-gh-failed",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}

async function runInteractiveGhLogin(): Promise<
  Result<undefined, MutationPlanningError>
> {
  try {
    const status = await new Deno.Command("gh", {
      args: ["auth", "login", "--hostname", "github.com", "--web"],
      stdin: "inherit",
      stdout: "inherit",
      stderr: "inherit",
    }).spawn().status;

    if (status.code === 0) {
      return ok(undefined);
    }

    return err({
      type: "local-gh-failed",
      detail: `gh auth login exited with code ${status.code}`,
    });
  } catch (error) {
    return err({
      type: "local-gh-failed",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}
