import "server-only";
import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import { bsb } from "@/lib/supabase/server";

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/**
 * A failed read becomes `{ kind: "error" }` and is never cached, so Retry reads
 * again.
 */
async function settle<T>(load: () => Promise<T | null>): Promise<Loaded<T>> {
  try {
    const data = await load();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

/** A maintenance plan as the list shows it, serializable. */
export interface MaintenancePlanRow {
  readonly id: string;
  readonly title: string;
  readonly kind: "time" | "meter";
  readonly status: "active" | "paused";
  readonly due: boolean;
  readonly nextDueAt: string | null;
  readonly hasWorkOrder: boolean;
}

async function loadPlans(): Promise<readonly MaintenancePlanRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const plans = await db.maintenance.listPlans({ limit: 200 }).orThrow();

  return plans.map((row) => ({
    id: row.id,
    title: row.title,
    kind: row.kind,
    status: row.status,
    due: row.due,
    nextDueAt: row.nextDueAt?.toString() ?? null,
    hasWorkOrder: row.workOrderId !== undefined,
  }));
}

/** The organization's maintenance plans, the soonest due first. */
export function getMaintenancePlans(): Promise<
  Loaded<readonly MaintenancePlanRow[]>
> {
  return settle(loadPlans);
}
