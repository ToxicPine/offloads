import { z } from "zod";

export const ghStateSchema = z.object({
  authenticated: z.boolean(),
  account: z.string().min(1).optional(),
  host: z.string().min(1).optional(),
  gitUserName: z.string().min(1).optional(),
  gitUserEmail: z.string().min(1).optional(),
  credentialHelper: z.string().min(1).optional(),
});

export type GhState = z.infer<typeof ghStateSchema>;
