import "server-only";
import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import { bsb } from "@/lib/supabase/server";

/** A record the member is asked to read, serializable. */
export interface PendingRow {
  readonly type: string;
  readonly id: string;
  readonly title: string | null;
  readonly versionId: string;
  readonly dueOn: string | null;
  readonly overdue: boolean;
}

export type Pending =
  | { readonly kind: "ok"; readonly rows: readonly PendingRow[] }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

async function loadPending(): Promise<readonly PendingRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const mine = await db.acknowledgements.mine(tenant).orThrow();

  return mine.map((item) => ({
    type: item.record.type,
    id: item.record.id,
    title: item.title ?? null,
    versionId: item.versionId,
    dueOn: item.dueOn?.toString() ?? null,
    overdue: item.overdue,
  }));
}

/**
 * The records the signed-in member still has to acknowledge, soonest due first.
 * A failed read becomes `{ kind: "error" }` and is never cached, so Retry reads
 * again.
 */
export async function getPending(): Promise<Pending> {
  try {
    const rows = await loadPending();

    return rows === null ? { kind: "no-organization" } : { kind: "ok", rows };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}
