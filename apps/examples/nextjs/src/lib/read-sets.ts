import { defineReadSet } from "better-supabase";

// `better-supabase gen` imports this file with Node, so relative imports keep
// their `.ts` extension.
import { betterSupabase } from "./supabase/index.ts";

/**
 * The dashboard's numbers as one round trip: `gen` compiles this into
 * `public.rs_workspace_summary(p jsonb)`, and `db.$many` calls it with a
 * single GET. RLS scopes every entry to the caller's organization.
 */
export const workspaceSummary = defineReadSet(
  betterSupabase,
  "workspace_summary",
  { params: { userId: "uuid" } },
  (s, p) => ({
    customers: s.customers.count(),
    active: s.customers.count({ where: { status: "active" } }),
    mine: s.customers.count({ where: { createdBy: p.userId } }),
    latestNote: s.notes.findFirst({
      select: ["body", "createdAt"],
      orderBy: { createdAt: "desc" },
    }),
  }),
);
