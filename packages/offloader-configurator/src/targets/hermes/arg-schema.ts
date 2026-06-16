import { parseArgs } from "node:util";
import { z } from "zod";
import { hermesAuthJsonSchema, type MutationPayload, mutationSchema } from "./mutation-schema.ts";

// Hermes is multi-provider, so interactive capture needs to know which
// provider to log in. `nous` is Hermes's first-party provider and its historic
// login default. The flag only steers the local `hermes auth add` flow; the
// resulting auth.json artifact is what crosses the transport.
const defaultProvider = "nous";

const configureFlagSchema = z.object({
  provider: z.string().min(1).default(defaultProvider),
  authJsonFile: z.string().min(1).optional(),
});
type ConfigureFlags = z.infer<typeof configureFlagSchema>;

export const configureInputSchema = configureFlagSchema.extend({
  type: z.literal("configure"),
});

export type ConfigureInput = z.infer<typeof configureInputSchema>;
export type HermesInput = ConfigureInput;

const checkArgvSchema = z
  .array(z.string())
  .length(0, "hermes check does not accept arguments");

export function parseHermesCheckArgs(argv: string[]): undefined {
  checkArgvSchema.parse(argv);
  return undefined;
}

export function parseHermesInput(command: string, argv: string[]): HermesInput {
  switch (command) {
    case "configure":
      return configureInputSchema.parse({
        type: "configure",
        ...parseConfigureFlags(argv),
      });
    default:
      throw new Error(`unknown hermes command: ${command}`);
  }
}

export function parseHermesMutationPayload(input: HermesInput): MutationPayload {
  return mutationSchema.parse(hermesInputToMutationShape(input));
}

function parseConfigureFlags(argv: string[]): ConfigureFlags {
  const parsed = parseArgs({
    args: argv,
    allowPositionals: false,
    strict: true,
    options: {
      "provider": { type: "string" },
      "auth-json-file": { type: "string" },
    },
  });

  return configureFlagSchema.parse({
    provider: parsed.values["provider"],
    authJsonFile: parsed.values["auth-json-file"],
  });
}

export function hermesInputToMutationShape(input: HermesInput): unknown {
  switch (input.type) {
    case "configure":
      if (!input.authJsonFile) {
        throw new Error(
          "hermes configure requires --auth-json-file for noninteractive configuration",
        );
      }

      return {
        type: "configure",
        authJson: readHermesAuthJsonFile(input.authJsonFile),
      };
  }
}

export function readHermesAuthJsonFile(
  path: string,
): z.infer<typeof hermesAuthJsonSchema> {
  return hermesAuthJsonSchema.parse(JSON.parse(Deno.readTextFileSync(path)));
}
