import "server-only";
import type { AuditEventInput } from "better-supabase/blocks/audit";

import type { AppDb } from "@/lib/supabase";

/**
 * Records an app event in the audit SQL module after a change committed. A
 * failed write is logged, not returned: the change itself already happened.
 */
export async function recordAudit(
  db: AppDb,
  event: AuditEventInput,
): Promise<void> {
  const recorded = await db.audit.record({ source: "app", ...event });

  if (!recorded.ok) {
    console.error("audit event not recorded", event.eventType, recorded.error);
  }
}
