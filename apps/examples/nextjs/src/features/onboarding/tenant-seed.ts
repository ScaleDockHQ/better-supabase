import { defineTenantSeed } from "better-supabase/testing";

import { betterSupabase } from "../../lib/supabase/index.ts";

/**
 * Demo rows every new organization starts with in development, and what
 * `better-supabase db seed --tenant <slug>` inserts into an existing one. Node
 * loads this file for the CLI, so its imports are relative with `.ts`.
 */
export const seed = defineTenantSeed(betterSupabase, (tenant) => ({
  customers: {
    demo: { organizationId: tenant.id, name: "Demo customer", status: "lead" },
  },
}));
