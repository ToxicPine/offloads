import { z } from "zod";

export const hermesAuthJsonSchema = z.record(z.string(), z.unknown());

export const mutationSchema = z.object({
  type: z.literal("configure"),
  authJson: hermesAuthJsonSchema,
});

export type MutationPayload = z.infer<typeof mutationSchema>;
