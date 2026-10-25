import { tenantOf } from "better-supabase/next";
import "server-only";

import { bsb } from "@/lib/supabase/server";

/** The flags the app checks; each is evaluated for the active organization. */
const FLAGS = ["beta-page"] as const;

export type FlagKey = (typeof FLAGS)[number];

/**
 * The flags that are on for the caller's organization, evaluated by
 * `flag_enabled` (the flags SQL module) with its rules and overrides. Cached
 * per session; switching organizations refreshes the session.
 */
export async function getEnabledFlags(): Promise<readonly FlagKey[]> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return [];
  }

  const enabled = await Promise.all(
    FLAGS.map(async (key) =>
      (await db.$api("flag_enabled", { key, tenant }).orThrow()) === true
        ? key
        : null,
    ),
  );

  return enabled.filter((key): key is FlagKey => key !== null);
}
