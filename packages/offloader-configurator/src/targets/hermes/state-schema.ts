import { z } from "zod";

// Modelled on `hermes auth status <provider>`. Hermes is multi-provider, so the
// active provider only exists once Hermes reports one logged in: it lives solely
// in the authenticated branch and is unrepresentable when authenticated is
// false. A logged-in provider implies the auth.json store exists, so
// authJsonPresent is pinned true on that branch.
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
