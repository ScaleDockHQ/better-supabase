import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";

/** The `rls-guard` block's manifest (ADR 0029). */
export const rlsGuardBlock: Block<"rls-guard"> = defineBlock({
  name: "rls-guard",
  sql: ["rls-guard"],
  category: "database",
  entities: { rls_guard: { mutability: "read-only" } },
  description:
    "An event trigger that enables row level security on every table created outside the Supabase-managed schemas, so a new table is never readable through the Data API before it has policies. Install it as postgres: supautils lets that role create event triggers.",
});
