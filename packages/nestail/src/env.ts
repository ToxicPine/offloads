import { z } from "@zod/zod";

const RawEnvSchema = z.object({
  SCRAMJET_HOST: z.string().default("localhost"),
  SCRAMJET_PORT: z.preprocess(
    (value) => value === undefined ? undefined : Number(value),
    z.number().int().min(1).max(65535).default(4096),
  ),
  NESTAIL_AUTH_SECRET: z.string().optional().transform((value) => {
    const trimmed = value?.trim();
    return trimmed ? trimmed : null;
  }),
  NESTAIL_TRUST_PROXY_HEADERS: z.string().optional().transform((value) =>
    value !== "0"
  ),
}).transform((env) => ({
  scramjetHost: env.SCRAMJET_HOST,
  scramjetPort: env.SCRAMJET_PORT,
  authSecret: env.NESTAIL_AUTH_SECRET,
  trustProxyHeaders: env.NESTAIL_TRUST_PROXY_HEADERS,
}));

export type NestailEnv = z.output<typeof RawEnvSchema>;

export class EnvValidationError extends Error {
  constructor(readonly issues: string[]) {
    super(
      `Invalid environment:\n${
        issues.map((issue) => `  - ${issue}`).join("\n")
      }`,
    );
    this.name = "EnvValidationError";
  }
}

export function readEnv(): NestailEnv {
  return parseEnv(Deno.env.toObject());
}

export function parseEnv(
  source: Record<string, string | undefined>,
): NestailEnv {
  const parsed = RawEnvSchema.safeParse(source);
  if (!parsed.success) {
    throw new EnvValidationError(parsed.error.issues.map(formatIssue));
  }

  return parsed.data;
}

function formatIssue(
  issue: { path: readonly PropertyKey[]; message: string },
): string {
  const name = issue.path.join(".") || "env";
  return `${name}: ${issue.message}`;
}
