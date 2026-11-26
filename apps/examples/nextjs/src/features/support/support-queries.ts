import "server-only";
import { cacheTag } from "next/cache";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

export interface SupportSessionRow {
  readonly id: string;
  readonly targetUserId: string;
  readonly reason: string | null;
  readonly readOnly: boolean;
  readonly startedAt: string;
  readonly expiresAt: string;
  readonly endedAt: string | null;
}

/**
 * The support sessions platform staff opened, newest first. The function
 * returns rows only to a caller holding the platform permission, so everyone
 * else reads an empty list.
 */
export async function getSupportSessions(): Promise<
  readonly SupportSessionRow[]
> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(tags.supportSessions());

  const { items: sessions } = await db.impersonation
    .sessionPage({ limit: 50 })
    .orThrow();

  return sessions.map((row) => ({
    id: row.id,
    targetUserId: row.targetUserId,
    reason: row.reason,
    readOnly: row.readOnly,
    startedAt: row.startedAt.toString(),
    expiresAt: row.expiresAt.toString(),
    endedAt: row.endedAt?.toString() ?? null,
  }));
}
