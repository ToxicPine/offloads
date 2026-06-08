import { parseArgs } from "node:util";
import { z } from "zod";
import { type MutationPayload, mutationSchema } from "./mutation-schema.ts";

const configureFlagSchema = z.object({
  token: z.string().min(1).optional(),
  gitUserName: z.string().min(1).optional(),
  gitUserEmail: z.email().optional(),
});
type ConfigureFlags = z.infer<typeof configureFlagSchema>;

export const configureInputSchema = configureFlagSchema.extend({
  type: z.literal("configure"),
});

export type ConfigureInput = z.infer<typeof configureInputSchema>;
export type GhInput = ConfigureInput;

const checkArgvSchema = z
  .array(z.string())
  .length(0, "gh check does not accept arguments");

export function parseGhCheckArgs(argv: string[]): undefined {
  checkArgvSchema.parse(argv);
  return undefined;
}

export function parseGhInput(command: string, argv: string[]): GhInput {
  switch (command) {
    case "configure":
      return configureInputSchema.parse({
        type: "configure",
        ...parseConfigureFlags(argv),
      });
    default:
      throw new Error(`unknown gh command: ${command}`);
  }
}

export function parseGhMutationPayload(input: GhInput): MutationPayload {
  return mutationSchema.parse(ghInputToMutationShape(input));
}

function parseConfigureFlags(argv: string[]): ConfigureFlags {
  const parsed = parseArgs({
    args: argv,
    allowPositionals: false,
    strict: true,
    options: {
      token: { type: "string" },
      "git-user-name": { type: "string" },
      "git-user-email": { type: "string" },
    },
  });

  return configureFlagSchema.parse({
    token: parsed.values.token,
    gitUserName: parsed.values["git-user-name"],
    gitUserEmail: parsed.values["git-user-email"],
  });
}

export function ghInputToMutationShape(input: GhInput): unknown {
  switch (input.type) {
    case "configure":
      return {
        type: "configure",
        githubToken: input.token,
        ...(input.gitUserName ? { gitUserName: input.gitUserName } : {}),
        ...(input.gitUserEmail ? { gitUserEmail: input.gitUserEmail } : {}),
      };
  }
}
