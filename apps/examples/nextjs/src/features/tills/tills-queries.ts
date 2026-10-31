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

/** A till session as the list shows it, serializable. */
export interface TillSessionRow {
  readonly id: string;
  readonly till: string;
  readonly status: "open" | "closed";
  /** Expected cash in minor units, as text. */
  readonly expected: string;
  readonly currency: string;
  readonly openedAt: string;
}

async function loadSessions(): Promise<readonly TillSessionRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const [tills, sessions] = await Promise.all([
    db.tills.listTills({ includeArchived: true }).orThrow(),
    db.tills.listSessions({ limit: 100 }).orThrow(),
  ]);

  const names = new Map(tills.map((till) => [till.id, till.name]));

  return sessions.map((row) => ({
    id: row.id,
    till: names.get(row.tillId) ?? "",
    status: row.status,
    expected: row.expected.amount.toString(),
    currency: row.expected.currency,
    openedAt: row.openedAt.toString(),
  }));
}

/** The organization's till sessions, newest first. */
export function getTillSessions(): Promise<Loaded<readonly TillSessionRow[]>> {
  return settle(loadSessions);
}
