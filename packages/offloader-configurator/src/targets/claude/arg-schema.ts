import { parseArgs } from "node:util";
import { z } from "zod";
import {
  claudeCredentialsSchema,
  type MutationPayload,
  mutationSchema,
} from "./mutation-schema.ts";

const configureFlagSchema = z.object({
  credentialsFile: z.string().min(1).optional(),
  oauthToken: z.string().min(1).optional(),
  useToken: z.boolean().optional(),
});
type ConfigureFlags = z.infer<typeof configureFlagSchema>;

export const configureInputSchema = configureFlagSchema
  .extend({
    type: z.literal("configure"),
  })
  .refine(
    (input) => !(input.credentialsFile && (input.oauthToken || input.useToken)),
    {
      message:
        "claude configure cannot combine --credentials-file with --oauth-token or --use-token",
    },
  );

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
      "oauth-token": { type: "string" },
      "use-token": { type: "boolean" },
    },
  });

  return configureFlagSchema.parse({
    credentialsFile: parsed.values["credentials-file"],
    oauthToken: parsed.values["oauth-token"],
    useToken: parsed.values["use-token"],
  });
}

export function claudeInputToMutationShape(input: ClaudeInput): unknown {
  switch (input.type) {
    case "configure":
      if (input.credentialsFile) {
        return {
          type: "configure-credentials",
          credentials: readClaudeCredentialsFile(input.credentialsFile),
        };
      }

      if (input.oauthToken) {
        return {
          type: "configure-token",
          oauthToken: input.oauthToken,
        };
      }

      throw new Error(
        "claude configure requires --credentials-file or --oauth-token for noninteractive configuration",
      );
  }
}

export function readClaudeCredentialsFile(
  path: string,
): z.infer<typeof claudeCredentialsSchema> {
  return claudeCredentialsSchema.parse(JSON.parse(Deno.readTextFileSync(path)));
}
