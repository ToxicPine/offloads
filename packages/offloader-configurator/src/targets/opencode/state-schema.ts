import { z } from "zod";

export const opencodeStateSchema = z.object({
  authenticated: z.boolean(),
  dataDir: z.string().min(1),
  authJsonPresent: z.boolean(),
  providers: z.string().min(1).optional(),
});

export type OpencodeState = z.infer<typeof opencodeStateSchema>;
