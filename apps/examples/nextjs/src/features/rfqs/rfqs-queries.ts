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

/** A request as the list shows it, serializable. */
export interface RfqRow {
  readonly id: string;
  readonly number: string;
  readonly title: string;
  readonly currency: string;
  readonly status: "draft" | "open" | "closed" | "awarded" | "cancelled";
  readonly dueAt: string | null;
}

async function loadRfqs(): Promise<readonly RfqRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const rfqs = await db.rfqs.listRfqs({ limit: 100 }).orThrow();

  return rfqs.map((row) => ({
    id: row.id,
    number: row.number,
    title: row.title,
    currency: row.currency,
    status: row.status,
    dueAt: row.dueAt?.toString() ?? null,
  }));
}

/** The organization's requests for quotation, newest first. */
export function getRfqs(): Promise<Loaded<readonly RfqRow[]>> {
  return settle(loadRfqs);
}
