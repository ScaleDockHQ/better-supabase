import { defineReadSet } from "better-supabase";

// `better-supabase gen` imports this file with Node, so relative imports keep
// their `.ts` extension.
import { reads } from "./supabase/blocks.generated.ts";
import { betterSupabase } from "./supabase/index.ts";

/**
 * The dashboard's numbers as one round trip: `gen` compiles this into
 * `public.rs_workspace_summary(p jsonb)`, and `db.$many` calls it with a single
 * GET. RLS scopes every entry to the caller's organization, and `mine` reads
 * `auth.uid()` in the function, so nobody counts another member's customers.
 */
export const workspaceSummary = defineReadSet(
  betterSupabase,
  "workspace_summary",
  {},
  (s, _p, auth) => ({
    customers: s.customers.count(),
    active: s.customers.count({ where: { status: "active" } }),
    mine: s.customers.count({ where: { createdBy: auth.uid } }),
    latestNote: s.notes.list({
      select: ["body", "createdAt"],
      orderBy: { createdAt: "desc" },
      limit: 1,
    }),
  }),
);

/**
 * A pipeline board and its headline count in one round trip. `s.blocks` calls
 * the `deals` block's own `deal_board` function, so the page doesn't await the
 * board and the count one after the other.
 */
export const pipelineOverview = defineReadSet(
  betterSupabase,
  "pipeline_overview",
  { params: { pipelineId: "uuid" }, blocks: reads },
  (s, p) => ({
    customers: s.customers.count(),
    board: s.blocks.deals.board({ pipelineId: p.pipelineId }),
  }),
);

/**
 * One bank account's reconciliation page and the stock watch list in one round
 * trip: `s.blocks.banking.reconciliationBoard` and
 * `s.blocks.inventory.overview` are the blocks' own read functions, so the page
 * doesn't await them one after the other.
 */
export const financeOverview = defineReadSet(
  betterSupabase,
  "finance_overview",
  { params: { accountId: "uuid", organizationId: "uuid" }, blocks: reads },
  (s, p) => ({
    reconciliation: s.blocks.banking.reconciliationBoard({
      accountId: p.accountId,
      limit: 100,
    }),
    stock: s.blocks.inventory.overview({ organizationId: p.organizationId }),
  }),
);
