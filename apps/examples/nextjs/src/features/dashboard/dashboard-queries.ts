import "server-only";
import { Temporal } from "temporal-polyfill";

import { workspaceSummary } from "@/lib/read-sets";
import { bsb } from "@/lib/supabase/server";

/**
 * Four numbers, one GET: the read set runs as a single `stable` function.
 * `bsb.tags` tags the entry with every table the set reads, so a new customer
 * or note revalidates it.
 */
export async function getWorkspaceSummary() {
  "use cache: private";
  const { db, session } = await bsb.cached();
  bsb.tags(workspaceSummary);

  if (session.kind !== "user") {
    return null;
  }

  return db.$many(workspaceSummary, {}).orThrow();
}

export interface CustomerCounts {
  readonly total: number;
  readonly previous: number;
  readonly lead: number;
  readonly active: number;
}

const DAY_MS = 86_400_000;

/**
 * New customers over the last 30 days against the 30 before, and how many of
 * them are leads or active (the metrics SQL module, read live with `rollup:
 * false`).
 */
export async function getCustomerCounts(
  organizationId: string,
): Promise<CustomerCounts> {
  "use cache: private";
  const { db } = await bsb.cached();
  const until = Temporal.Now.instant();

  const range = { from: until.subtract({ milliseconds: 30 * DAY_MS }), until };

  const { metrics } = db;

  const [total, lead, active] = await Promise.all([
    metrics
      .kpi("customers", range, { organizationId, compare: "previous" })
      .orThrow(),
    metrics
      .kpi("customers", range, { organizationId, filter: { status: "lead" } })
      .orThrow(),
    metrics
      .kpi("customers", range, { organizationId, filter: { status: "active" } })
      .orThrow(),
  ]);

  return {
    total: total.value ?? 0,
    previous: total.previous ?? 0,
    lead: lead.value ?? 0,
    active: active.value ?? 0,
  };
}
