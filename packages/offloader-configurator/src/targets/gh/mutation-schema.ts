import { z } from "zod";

export const mutationSchema = z.object({
  type: z.literal("configure"),
  githubToken: z.string().min(1),
  gitUserName: z.string().min(1).optional(),
  gitUserEmail: z.string().email().optional(),
});

export type MutationPayload = z.infer<typeof mutationSchema>;
