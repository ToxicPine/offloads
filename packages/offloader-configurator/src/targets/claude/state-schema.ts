import { z } from "zod";

// Modelled on `claude auth status --json`: authMethod/apiProvider only exist
// when Claude reports a session, so they live solely in the authenticated
// branch and are unrepresentable when authenticated is false.
export const claudeStateSchema = z.discriminatedUnion("authenticated", [
  z.object({
    authenticated: z.literal(true),
    authMethod: z.string().min(1).optional(),
    apiProvider: z.string().min(1).optional(),
    claudeConfigDir: z.string().min(1),
  }),
  z.object({
    authenticated: z.literal(false),
    claudeConfigDir: z.string().min(1),
  }),
]);

export type ClaudeState = z.infer<typeof claudeStateSchema>;
