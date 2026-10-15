import "server-only";
import { Temporal } from "temporal-polyfill";

import { blocks } from "@/lib/blocks";
import { workspaceSummary } from "@/lib/read-sets";
import { bs } from "@/lib/supabase/server";

/**
 * Four numbers, one GET: the read set runs as a single `stable` function.
 * `cacheTags` tags the entry with every table the set reads, so a new
 * customer or note revalidates it.
 */
export async function getWorkspaceSummary() {
  "use cache: private";
  const { db, session } = await bs.cached();
  bs.cacheTags(workspaceSummary);
  if (session.kind !== "user") return null;
  return db.$many(workspaceSummary, {}).orThrow();
}

export interface UsageMeter {
  readonly meter: string;
  readonly used: number;
  readonly limit: number | null;
  readonly unlimited: boolean;
  /** ISO 8601; Temporal values don't cross into Client Components. */
  readonly resetsAt: string;
}

/** This period's usage against the plan's quotas (the usage SQL module). */
export async function getUsage(
  organizationId: string,
): Promise<readonly UsageMeter[]> {
  "use cache: private";
  const { supabase } = await bs.cached();
  const overview = await blocks(supabase)
    .usage.overview(organizationId)
    .orThrow();
  return overview.map((status) => ({
    meter: status.meter,
    used: status.used,
    limit: status.limit ?? null,
    unlimited: status.unlimited,
    resetsAt: status.resetsAt.toString(),
  }));
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
 * them are leads or active (the metrics SQL module, read live with
 * `rollup: false`).
 */
export async function getCustomerCounts(
  organizationId: string,
): Promise<CustomerCounts> {
  "use cache: private";
  const { supabase } = await bs.cached();
  const until = Temporal.Now.instant();
  const range = {
    from: until.subtract({ milliseconds: 30 * DAY_MS }),
    until,
  };
  const { metrics } = blocks(supabase);
  const [total, lead, active] = await Promise.all([
    metrics
      .kpi("customers", range, { organizationId, compare: "previous" })
      .orThrow(),
    metrics
      .kpi("customers", range, { organizationId, filter: { status: "lead" } })
      .orThrow(),
    metrics
      .kpi("customers", range, {
        organizationId,
        filter: { status: "active" },
      })
      .orThrow(),
  ]);
  return {
    total: total.value ?? 0,
    previous: total.previous ?? 0,
    lead: lead.value ?? 0,
    active: active.value ?? 0,
  };
}
