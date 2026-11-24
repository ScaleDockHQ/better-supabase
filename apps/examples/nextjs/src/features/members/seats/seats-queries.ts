import "server-only";
import { tenantOf } from "better-supabase/next";

import { bsb } from "@/lib/supabase/server";

/**
 * The seats the plan leaves given `used` members: `undefined` when the plan
 * sets no limit, `null` without an organization.
 */
export async function loadSeatsLeft(
  used: number,
): Promise<number | undefined | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  return db.entitlements.seatsLeft({ organizationId, used }).orThrow();
}
