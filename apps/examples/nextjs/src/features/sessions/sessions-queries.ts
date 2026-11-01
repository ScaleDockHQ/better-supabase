import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

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

export interface OtherSession {
  readonly id: string;
  readonly lastActiveAt: string;
  readonly userAgent: string | null;
  readonly ip: string | null;
  readonly current: boolean;
}

/**
 * The caller's sessions on other devices, newest activity first
 * (`sessions.listMine`, which reads `auth.sessions` for the caller only).
 */
export async function getOtherSessions(): Promise<readonly OtherSession[]> {
  "use cache: private";
  const { auth, db } = await bsb.cached();

  if (auth.kind !== "user") {
    return [];
  }

  const sessions = await db.$blocks.sessions.listMine().orThrow();

  return sessions
    .filter((session) => !session.current)
    .map((session) => ({
      id: session.id,
      lastActiveAt:
        (session.lastActiveAt ?? session.createdAt)?.toString() ?? "",
      userAgent: session.userAgent,
      ip: session.ip,
      current: session.current,
    }));
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
