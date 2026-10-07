import "server-only";
import type { AuditEventInput } from "better-supabase/blocks/audit";
import type { RpcClient } from "better-supabase/blocks/organizations";

import { blocks } from "@/lib/blocks";

/**
 * Records an app event in the audit SQL module after a change committed.
 * A failed write is logged, not returned: the change itself already happened.
 */
export async function recordAudit(
  supabase: RpcClient,
  event: AuditEventInput,
): Promise<void> {
  const recorded = await blocks(supabase).audit.record({
    source: "app",
    ...event,
  });
  if (!recorded.ok) {
    console.error("audit event not recorded", event.eventType, recorded.error);
  }
}
