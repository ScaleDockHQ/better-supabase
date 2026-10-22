import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { blocks } from "@/lib/blocks";
import { bsb } from "@/lib/supabase/server";

export interface CurrentSession {
  readonly id: string;
  readonly method: string | null;
  readonly signedInAt: string | null;
  readonly aal: string | null;
}

const SessionClaims = v.object({
  session_id: v.string(),
  aal: v.optional(v.string()),
  amr: v.optional(
    v.array(v.object({ method: v.string(), timestamp: v.number() })),
  ),
});

type SignIn = NonNullable<v.InferOutput<typeof SessionClaims>["amr"]>[number];

function latestSignIn(amr: readonly SignIn[]): SignIn | null {
  let latest: SignIn | null = null;

  for (const entry of amr) {
    if (latest === null || entry.timestamp > latest.timestamp) {
      latest = entry;
    }
  }

  return latest;
}

const OtherSession = v.object({
  id: v.string(),
  lastActiveAt: v.string(),
  userAgent: v.nullable(v.string()),
  ip: v.nullable(v.string()),
  current: v.boolean(),
});

export type OtherSession = v.InferOutput<typeof OtherSession>;

/**
 * The caller's sessions on other devices, newest activity first
 * (`list_my_sessions`, which reads `auth.sessions` for the caller only).
 */
export async function getOtherSessions(): Promise<readonly OtherSession[]> {
  "use cache: private";
  const { auth, supabase } = await bsb.cached();

  if (auth.kind !== "user") {
    return [];
  }

  const rows = v.parse(
    v.array(OtherSession),
    await blocks(supabase).call("list_my_sessions", {}),
  );

  return rows.filter((row) => !row.current);
}

/** The session behind this request's token, or null for a caller without one. */
export async function getCurrentSession(): Promise<CurrentSession | null> {
  "use cache: private";
  const { auth } = await bsb.cached();

  if (auth.kind !== "user") {
    return null;
  }

  const parsed = v.safeParse(SessionClaims, auth.claims);

  if (!parsed.success) {
    return null;
  }

  const claims = parsed.output;
  const signIn = latestSignIn(claims.amr ?? []);

  return {
    aal: claims.aal ?? null,
    id: claims.session_id,
    method: signIn?.method ?? null,
    signedInAt:
      signIn === null
        ? null
        : Temporal.Instant.fromEpochMilliseconds(
            signIn.timestamp * 1000,
          ).toString(),
  };
}
