import "server-only";
import { cacheTag } from "next/cache";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

import { SUPPORT_TAG } from "./support-cache";

const SessionJson = v.object({
  id: v.string(),
  target_user_id: v.string(),
  reason: v.nullable(v.string()),
  read_only: v.boolean(),
  started_at: v.string(),
  expires_at: v.string(),
  ended_at: v.nullable(v.string()),
});

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
  cacheTag(SUPPORT_TAG);

  // The api schema is untyped here, so the reply is typed at the call.
  const response: {
    readonly data: unknown;
    readonly error: { readonly message: string } | null;
  } = await db.$client
    .schema("api")
    .rpc("list_support_sessions", { max_rows: 50 });

  if (response.error) {
    throw new Error(response.error.message);
  }

  return v
    .parse(v.array(SessionJson), response.data)
    .map((row) => ({
      id: row.id,
      targetUserId: row.target_user_id,
      reason: row.reason,
      readOnly: row.read_only,
      startedAt: row.started_at,
      expiresAt: row.expires_at,
      endedAt: row.ended_at,
    }));
}
