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

/** A care alert as the list shows it, serializable. */
export interface CareAlertRow {
  readonly id: string;
  readonly subject: string;
  readonly kind:
    | "dose_range"
    | "duplicate_therapy"
    | "interaction"
    | "allergy"
    | "other";
  readonly severity: "info" | "warning" | "critical";
  readonly status: "open" | "acknowledged" | "overridden" | "resolved";
  readonly message: string;
  readonly source: string;
}

async function loadAlerts(): Promise<readonly CareAlertRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const alerts = await db.clinicalDecisionSupport
    .alerts({ limit: 100 })
    .orThrow();

  return alerts.map((alert) => ({
    id: alert.id,
    subject: `${alert.subject.type} ${alert.subject.id.slice(0, 8)}`,
    kind: alert.kind,
    severity: alert.severity,
    status: alert.status,
    message: alert.message,
    source: alert.source,
  }));
}

/** The organization's open and decided care alerts, serious ones first. */
export function getCareAlerts(): Promise<Loaded<readonly CareAlertRow[]>> {
  return settle(loadAlerts);
}
