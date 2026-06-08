import { parseArgs } from "node:util";
import { z } from "zod";
import {
  codexAuthJsonSchema,
  type MutationPayload,
  mutationSchema,
} from "./mutation-schema.ts";

const configureFlagSchema = z.object({
  authJsonFile: z.string().min(1).optional(),
});
type ConfigureFlags = z.infer<typeof configureFlagSchema>;

export const configureInputSchema = configureFlagSchema.extend({
  type: z.literal("configure"),
});

export type ConfigureInput = z.infer<typeof configureInputSchema>;
export type CodexInput = ConfigureInput;

const checkArgvSchema = z
  .array(z.string())
  .length(0, "codex check does not accept arguments");

export function parseCodexCheckArgs(argv: string[]): undefined {
  checkArgvSchema.parse(argv);
  return undefined;
}

export function parseCodexInput(command: string, argv: string[]): CodexInput {
  switch (command) {
    case "configure":
      return configureInputSchema.parse({
        type: "configure",
        ...parseConfigureFlags(argv),
      });
    default:
      throw new Error(`unknown codex command: ${command}`);
  }
}

export function parseCodexMutationPayload(input: CodexInput): MutationPayload {
  return mutationSchema.parse(codexInputToMutationShape(input));
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

export function codexInputToMutationShape(input: CodexInput): unknown {
  switch (input.type) {
    case "configure":
      if (!input.authJsonFile) {
        throw new Error(
          "codex configure requires --auth-json-file for noninteractive configuration",
        );
      }

      return {
        type: "configure",
        authJson: readCodexAuthJsonFile(input.authJsonFile),
      };
  }
}

export function readCodexAuthJsonFile(
  path: string,
): z.infer<typeof codexAuthJsonSchema> {
  return codexAuthJsonSchema.parse(JSON.parse(Deno.readTextFileSync(path)));
}
