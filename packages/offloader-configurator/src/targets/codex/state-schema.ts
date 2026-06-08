import { z } from "zod";

export const codexStateSchema = z.object({
  authenticated: z.boolean(),
  codexHome: z.string().min(1),
  authJsonPresent: z.boolean(),
  loginStatus: z.string().min(1).optional(),
});

export type CodexState = z.infer<typeof codexStateSchema>;
