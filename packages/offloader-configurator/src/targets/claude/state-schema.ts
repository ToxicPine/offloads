import { z } from "zod";

export const claudeStateSchema = z.object({
  authMethod: z.enum(["credentials", "token"]).optional(),
  claudeConfigDir: z.string().min(1),
  credentialsPresent: z.boolean(),
  oauthTokenConfigured: z.boolean(),
});

export type ClaudeState = z.infer<typeof claudeStateSchema>;
