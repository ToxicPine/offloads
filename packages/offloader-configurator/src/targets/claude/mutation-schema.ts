import { z } from "zod";

export const claudeCredentialsSchema = z.record(z.string(), z.unknown());

export const mutationSchema = z.object({
  type: z.literal("configure"),
  credentials: claudeCredentialsSchema,
});

export type MutationPayload = z.infer<typeof mutationSchema>;
