import { z } from "zod";

export const claudeCredentialsSchema = z.record(z.string(), z.unknown());

export const mutationSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("configure-credentials"),
    credentials: claudeCredentialsSchema,
  }),
  z.object({
    type: z.literal("configure-token"),
    oauthToken: z.string().min(1),
  }),
]);

export type MutationPayload = z.infer<typeof mutationSchema>;
