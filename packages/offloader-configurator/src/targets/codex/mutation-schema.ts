import { z } from "zod";

export const codexAuthJsonSchema = z.record(z.string(), z.unknown());

export const mutationSchema = z.object({
  type: z.literal("configure"),
  authJson: codexAuthJsonSchema,
});

export type MutationPayload = z.infer<typeof mutationSchema>;
