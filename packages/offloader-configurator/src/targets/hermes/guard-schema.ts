import { z } from "zod";

export const guardSchema = z.union([
  z.object({
    ok: z.literal(true),
  }),
  z.object({
    ok: z.literal(false),
    error: z.object({
      type: z.string().min(1),
      detail: z.array(
        z.object({
          name: z.string().min(1),
          detail: z.string().min(1),
        }),
      ),
    }),
  }),
]);

export type GuardResult = z.infer<typeof guardSchema>;
