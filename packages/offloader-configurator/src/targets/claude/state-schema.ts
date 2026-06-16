import { z } from "zod";

export const claudeStateSchema = z.object({
  authenticated: z.boolean(),
  authMethod: z.string().min(1).optional(),
  apiProvider: z.string().min(1).optional(),
  claudeConfigDir: z.string().min(1),
});

export type ClaudeState = z.infer<typeof claudeStateSchema>;
