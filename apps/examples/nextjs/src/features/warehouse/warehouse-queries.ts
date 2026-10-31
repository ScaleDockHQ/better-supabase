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

/** A pick list as the grid shows it, serializable. */
export interface PickListRow {
  readonly id: string;
  readonly documentType: string;
  readonly documentId: string;
  readonly status: "open" | "picked" | "cancelled";
  /** How many lines are picked, of how many. */
  readonly picked: number;
  readonly lines: number;
}

async function loadPickLists(): Promise<readonly PickListRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const rows = await db.warehouse.listPickLists({ limit: 200 }).orThrow();

  return rows.map((row) => ({
    id: row.id,
    documentType: row.documentType,
    documentId: row.documentId,
    status: row.status,
    picked: row.lines.filter((line) => line.status === "picked").length,
    lines: row.lines.length,
  }));
}

/** The pick lists the caller reads, newest first. */
export function getPickLists(): Promise<Loaded<readonly PickListRow[]>> {
  return settle(loadPickLists);
}
