import {
  type CliBoundaryError,
  invalidCliArgsFrom,
} from "../../lib/cli-error.ts";
import {
  mutateWrapper,
  remoteJson,
  type RemoteJsonError,
} from "../../lib/remote.ts";
import { err, ok, type Result } from "../../lib/result.ts";
import {
  type GhInput,
  parseGhCheckArgs,
  parseGhInput,
  parseGhMutationPayload,
} from "./arg-schema.ts";
import { type GuardResult, guardSchema } from "./guard-schema.ts";
import { type MutationPayload, mutationSchema } from "./mutation-schema.ts";
import { type GhState, ghStateSchema } from "./state-schema.ts";

export { mutationSchema };
export { default as completeInput } from "./mutation.ts";
export type { GhInput };

export type CommandContext = {
  transport: string;
};

export type CommandError = RemoteJsonError;

const textDecoder = new TextDecoder();

async function script(
  name: "GUARD.sh" | "QUERY.sh" | "MUTATE.sh",
): Promise<string> {
  return textDecoder.decode(
    await Deno.readFile(new URL(`./${name}`, import.meta.url)),
  );
}

export async function guard(
  ctx: CommandContext,
): Promise<Result<GuardResult, CommandError>> {
  return await remoteJson(ctx.transport, await script("GUARD.sh"), guardSchema);
}

export async function query(
  ctx: CommandContext,
): Promise<Result<GhState, CommandError>> {
  return await remoteJson(
    ctx.transport,
    await script("QUERY.sh"),
    ghStateSchema,
  );
}

export async function mutate(
  ctx: CommandContext,
  payload: MutationPayload,
): Promise<Result<GhState, CommandError>> {
  return await remoteJson(
    ctx.transport,
    mutateWrapper(await script("MUTATE.sh"), payload),
    ghStateSchema,
  );
}

export function parseCheckInput(
  argv: string[],
): Result<undefined, CliBoundaryError> {
  try {
    return ok(parseGhCheckArgs(argv));
  } catch (error) {
    return err(invalidCliArgsFrom(error));
  }
}

export function parseInput(
  command: string,
  argv: string[],
): Result<GhInput, CliBoundaryError> {
  try {
    return ok(parseGhInput(command, argv));
  } catch (error) {
    return err(invalidCliArgsFrom(error));
  }
}

export function parseCompleteMutationPayload(
  input: GhInput,
): Result<MutationPayload, CliBoundaryError> {
  try {
    return ok(parseGhMutationPayload(input));
  } catch (error) {
    return err(invalidCliArgsFrom(error));
  }
}
