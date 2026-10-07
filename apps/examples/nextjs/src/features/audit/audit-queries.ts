import "server-only";
import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

export interface AuditRow {
  readonly id: string;
  /** ISO 8601. */
  readonly occurredAt: string;
  readonly eventType: string;
  readonly actor: string | null;
  readonly target: string | null;
  readonly outcome: string | null;
}

/** The organization's newest audit events (the audit SQL module checks `audit.read`). */
export async function getAuditEvents(
  organizationId: string,
): Promise<readonly AuditRow[]> {
  "use cache: private";
  const { supabase } = await bs.cached();
  const page = await blocks(supabase)
    .audit.list({ organizationId, limit: 50, order: "desc" })
    .orThrow();
  return page.entries.map((entry) => ({
    id: entry.id,
    occurredAt: entry.occurredAt.toString(),
    eventType:
      entry.eventType ?? `${entry.op ?? "change"} ${entry.table ?? ""}`.trim(),
    actor: entry.actorLabel ?? entry.actorId ?? null,
    target: entry.targetLabel ?? entry.record ?? null,
    outcome: entry.outcome ?? null,
  }));
}
