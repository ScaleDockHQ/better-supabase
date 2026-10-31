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

/** A usage right as the list shows it, serializable. */
export interface UsageRightRow {
  readonly id: string;
  readonly licensee: string;
  readonly territory: string | null;
  readonly channel: string | null;
  readonly status: "upcoming" | "active" | "expired" | "revoked";
  readonly expiresOn: string | null;
}

async function loadRights(): Promise<readonly UsageRightRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const rights = await db.dam.listRights({ limit: 200 }).orThrow();

  return rights.map((row) => ({
    id: row.id,
    licensee: row.licensee,
    territory: row.territory ?? null,
    channel: row.channel ?? null,
    status: row.status,
    expiresOn: row.expiresOn?.toString() ?? null,
  }));
}

/** The organization's usage rights, the soonest to expire first. */
export function getUsageRights(): Promise<Loaded<readonly UsageRightRow[]>> {
  return settle(loadRights);
}
