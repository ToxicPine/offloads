import { z } from "zod";

// Modelled on `hermes auth status <provider>`: Hermes is multi-provider, so the
// active provider only exists once Hermes reports one logged in, and lives solely
// in the authenticated branch. A logged-in provider implies the store exists, so
// authJsonPresent is pinned true there.
export const hermesStateSchema = z.discriminatedUnion("authenticated", [
  z.object({
    authenticated: z.literal(true),
    hermesHome: z.string().min(1),
    authJsonPresent: z.literal(true),
    activeProvider: z.string().min(1),
  }),
  z.object({
    authenticated: z.literal(false),
    hermesHome: z.string().min(1),
    authJsonPresent: z.boolean(),
  }),
]);

export type HermesState = z.infer<typeof hermesStateSchema>;
