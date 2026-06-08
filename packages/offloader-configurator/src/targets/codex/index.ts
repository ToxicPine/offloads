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
  type CodexInput,
  parseCodexCheckArgs,
  parseCodexInput,
  parseCodexMutationPayload,
} from "./arg-schema.ts";
import { type GuardResult, guardSchema } from "./guard-schema.ts";
import { type MutationPayload, mutationSchema } from "./mutation-schema.ts";
import { type CodexState, codexStateSchema } from "./state-schema.ts";

export { mutationSchema };
export { default as completeInput } from "./mutation.ts";
export type { CodexInput };

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
): Promise<Result<CodexState, CommandError>> {
  return await remoteJson(
    ctx.transport,
    await script("QUERY.sh"),
    codexStateSchema,
  );
}

export async function mutate(
  ctx: CommandContext,
  payload: MutationPayload,
): Promise<Result<CodexState, CommandError>> {
  return await remoteJson(
    ctx.transport,
    mutateWrapper(await script("MUTATE.sh"), payload),
    codexStateSchema,
  );
}

export function parseCheckInput(
  argv: string[],
): Result<undefined, CliBoundaryError> {
  try {
    return ok(parseCodexCheckArgs(argv));
  } catch (error) {
    return err(invalidCliArgsFrom(error));
  }
}

export function parseInput(
  command: string,
  argv: string[],
): Result<CodexInput, CliBoundaryError> {
  try {
    return ok(parseCodexInput(command, argv));
  } catch (error) {
    return err(invalidCliArgsFrom(error));
  }
}

export function parseCompleteMutationPayload(
  input: CodexInput,
): Result<MutationPayload, CliBoundaryError> {
  try {
    return ok(parseCodexMutationPayload(input));
  } catch (error) {
    return err(invalidCliArgsFrom(error));
  }
}
