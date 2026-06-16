import { z } from "zod";

export const opencodeAuthJsonSchema = z.record(z.string(), z.unknown());

export const mutationSchema = z.object({
  type: z.literal("configure"),
  authJson: opencodeAuthJsonSchema,
});

export type MutationPayload = z.infer<typeof mutationSchema>;
