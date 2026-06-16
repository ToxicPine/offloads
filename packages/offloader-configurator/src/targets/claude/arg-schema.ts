import { parseArgs } from "node:util";
import { z } from "zod";
import {
  claudeCredentialsSchema,
  type MutationPayload,
  mutationSchema,
} from "./mutation-schema.ts";

const configureFlagSchema = z.object({
  credentialsFile: z.string().min(1).optional(),
});
type ConfigureFlags = z.infer<typeof configureFlagSchema>;

export const configureInputSchema = configureFlagSchema.extend({
  type: z.literal("configure"),
});

export type ConfigureInput = z.infer<typeof configureInputSchema>;
export type ClaudeInput = ConfigureInput;

const checkArgvSchema = z
  .array(z.string())
  .length(0, "claude check does not accept arguments");

export function parseClaudeCheckArgs(argv: string[]): undefined {
  checkArgvSchema.parse(argv);
  return undefined;
}

export function parseClaudeInput(command: string, argv: string[]): ClaudeInput {
  switch (command) {
    case "configure":
      return configureInputSchema.parse({
        type: "configure",
        ...parseConfigureFlags(argv),
      });
    default:
      throw new Error(`unknown claude command: ${command}`);
  }
}

export function parseClaudeMutationPayload(input: ClaudeInput): MutationPayload {
  return mutationSchema.parse(claudeInputToMutationShape(input));
}

function parseConfigureFlags(argv: string[]): ConfigureFlags {
  const parsed = parseArgs({
    args: argv,
    allowPositionals: false,
    strict: true,
    options: {
      "credentials-file": { type: "string" },
    },
  });

  return configureFlagSchema.parse({
    credentialsFile: parsed.values["credentials-file"],
  });
}

export function claudeInputToMutationShape(input: ClaudeInput): unknown {
  switch (input.type) {
    case "configure":
      if (!input.credentialsFile) {
        throw new Error(
          "claude configure requires --credentials-file for noninteractive configuration",
        );
      }

      return {
        type: "configure",
        credentials: readClaudeCredentialsFile(input.credentialsFile),
      };
  }
}

export function readClaudeCredentialsFile(
  path: string,
): z.infer<typeof claudeCredentialsSchema> {
  return claudeCredentialsSchema.parse(JSON.parse(Deno.readTextFileSync(path)));
}
