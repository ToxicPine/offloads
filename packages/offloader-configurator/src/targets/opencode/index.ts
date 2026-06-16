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
  type OpencodeInput,
  parseOpencodeCheckArgs,
  parseOpencodeInput,
  parseOpencodeMutationPayload,
} from "./arg-schema.ts";
import { type GuardResult, guardSchema } from "./guard-schema.ts";
import { type MutationPayload, mutationSchema } from "./mutation-schema.ts";
import { type OpencodeState, opencodeStateSchema } from "./state-schema.ts";

export { mutationSchema };
export { default as completeInput } from "./mutation.ts";
export type { OpencodeInput };

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
): Promise<Result<OpencodeState, CommandError>> {
  return await remoteJson(
    ctx.transport,
    await script("QUERY.sh"),
    opencodeStateSchema,
  );
}

export async function mutate(
  ctx: CommandContext,
  payload: MutationPayload,
): Promise<Result<OpencodeState, CommandError>> {
  return await remoteJson(
    ctx.transport,
    mutateWrapper(await script("MUTATE.sh"), payload),
    opencodeStateSchema,
  );
}

export function parseCheckInput(
  argv: string[],
): Result<undefined, CliBoundaryError> {
  try {
    return ok(parseOpencodeCheckArgs(argv));
  } catch (error) {
    return err(invalidCliArgsFrom(error));
  }
}

export function parseInput(
  command: string,
  argv: string[],
): Result<OpencodeInput, CliBoundaryError> {
  try {
    return ok(parseOpencodeInput(command, argv));
  } catch (error) {
    return err(invalidCliArgsFrom(error));
  }
}

export function parseCompleteMutationPayload(
  input: OpencodeInput,
): Result<MutationPayload, CliBoundaryError> {
  try {
    return ok(parseOpencodeMutationPayload(input));
  } catch (error) {
    return err(invalidCliArgsFrom(error));
  }
}
