import { z } from "zod";

export const guardSchema = z.discriminatedUnion("ok", [
  z.object({
    ok: z.literal(true),
    value: z.object({}).optional(),
  }),
  z.object({
    ok: z.literal(false),
    error: z.object({
      type: z.string(),
      detail: z.unknown(),
    }),
  }),
]);

export type GuardResult = z.infer<typeof guardSchema>;
