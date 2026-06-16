import { parseArgs } from "node:util";
import { z } from "zod";
import { type MutationPayload, mutationSchema, opencodeAuthJsonSchema } from "./mutation-schema.ts";

const configureFlagSchema = z.object({
  authJsonFile: z.string().min(1).optional(),
});
type ConfigureFlags = z.infer<typeof configureFlagSchema>;

export const configureInputSchema = configureFlagSchema.extend({
  type: z.literal("configure"),
});

export type ConfigureInput = z.infer<typeof configureInputSchema>;
export type OpencodeInput = ConfigureInput;

const checkArgvSchema = z
  .array(z.string())
  .length(0, "opencode check does not accept arguments");

export function parseOpencodeCheckArgs(argv: string[]): undefined {
  checkArgvSchema.parse(argv);
  return undefined;
}

export function parseOpencodeInput(
  command: string,
  argv: string[],
): OpencodeInput {
  switch (command) {
    case "configure":
      return configureInputSchema.parse({
        type: "configure",
        ...parseConfigureFlags(argv),
      });
    default:
      throw new Error(`unknown opencode command: ${command}`);
  }
}

export function parseOpencodeMutationPayload(
  input: OpencodeInput,
): MutationPayload {
  return mutationSchema.parse(opencodeInputToMutationShape(input));
}

function parseConfigureFlags(argv: string[]): ConfigureFlags {
  const parsed = parseArgs({
    args: argv,
    allowPositionals: false,
    strict: true,
    options: {
      "auth-json-file": { type: "string" },
    },
  });

  return configureFlagSchema.parse({
    authJsonFile: parsed.values["auth-json-file"],
  });
}

export function opencodeInputToMutationShape(input: OpencodeInput): unknown {
  switch (input.type) {
    case "configure":
      if (!input.authJsonFile) {
        throw new Error(
          "opencode configure requires --auth-json-file for noninteractive configuration",
        );
      }

      return {
        type: "configure",
        authJson: readOpencodeAuthJsonFile(input.authJsonFile),
      };
  }
}

export function readOpencodeAuthJsonFile(
  path: string,
): z.infer<typeof opencodeAuthJsonSchema> {
  return opencodeAuthJsonSchema.parse(JSON.parse(Deno.readTextFileSync(path)));
}
