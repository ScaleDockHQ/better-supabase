import "server-only";
import { activeOrganizationId } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

/** The flags the app checks; each is evaluated for the active organization. */
const FLAGS = ["beta-page"] as const;
export type FlagKey = (typeof FLAGS)[number];

/**
 * The flags that are on for the caller's organization, evaluated by
 * `flag_enabled` (the flags SQL module) with its rules and overrides.
 * Cached per session; switching organizations refreshes the session.
 */
export async function getEnabledFlags(): Promise<readonly FlagKey[]> {
  "use cache: private";
  const { session, supabase } = await bs.cached();
  const tenant = activeOrganizationId(session);
  if (!tenant) return [];
  const { call } = blocks(supabase);
  const enabled = await Promise.all(
    FLAGS.map(async (key) =>
      (await call("flag_enabled", { key, tenant })) === true ? key : null,
    ),
  );
  return enabled.filter((key): key is FlagKey => key !== null);
}
