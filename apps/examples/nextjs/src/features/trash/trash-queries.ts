import "server-only";
import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import { bsb } from "@/lib/supabase/server";

export interface TrashEntry {
  readonly id: string;
  readonly subjectType: string;
  readonly title: string | null;
  readonly count: number;
  /** ISO 8601, so the cached value stays serializable. */
  readonly trashedAt: string;
  readonly purgeAfter: string | null;
}

export type TrashView =
  | { readonly kind: "ok"; readonly items: readonly TrashEntry[] }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/** The trash, newest first. A failed read throws, so Retry reads again. */
async function loadTrash(): Promise<readonly TrashEntry[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const items = await db.trash
    .list({ organizationId: tenant, pageSize: 100 })
    .orThrow();

  return items.map((item) => ({
    id: item.id,
    subjectType: item.subjectType,
    title: item.title ?? null,
    count: item.count,
    trashedAt: item.trashedAt.toString(),
    purgeAfter: item.purgeAfter?.toString() ?? null,
  }));
}

export async function getTrash(): Promise<TrashView> {
  try {
    const items = await loadTrash();

    return items === null ? { kind: "no-organization" } : { kind: "ok", items };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}
