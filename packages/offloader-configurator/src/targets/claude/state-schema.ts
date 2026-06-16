import { z } from "zod";

export const claudeStateSchema = z.object({
  authenticated: z.boolean(),
  credentialSource: z.enum(["credentials", "token", "none"]),
  claudeConfigDir: z.string().min(1),
});

export type ClaudeState = z.infer<typeof claudeStateSchema>;
