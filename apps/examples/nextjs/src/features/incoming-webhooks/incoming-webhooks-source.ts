import "server-only";
import type {
  AdminListRaw,
  AdminListSource,
} from "@/features/admin-lists/admin-list-sql";

import type { IncomingWebhookRow } from "./incoming-webhooks-list";

interface IncomingWebhookRaw extends AdminListRaw {
  readonly name: string;
  readonly verify: string;
  readonly enabled: boolean;
  readonly receive_count: string;
  readonly last_received_at: string | null;
  readonly last_status: number | null;
  readonly created_at: string;
}

/**
 * The organization's incoming endpoints, read as the caller: the table grants
 * members every column but the secret, and RLS limits the rows.
 */
export const incomingWebhookSource: AdminListSource<
  IncomingWebhookRaw,
  IncomingWebhookRow
> = {
  from: "better_supabase.incoming_webhooks w",
  idColumn: "w.id",
  idType: "uuid",
  timeColumn: "w.created_at",
  scope: "w.tenant = $1",
  search: ["w.name"],
  facetSql: {
    state: "case when w.enabled then 'enabled' else 'disabled' end",
    verify: "w.verify",
  },
  select: `w.name, w.verify, w.enabled, w.receive_count::text as receive_count,
    w.last_received_at::text as last_received_at, w.last_status,
    w.created_at::text as created_at`,
  map: (raw) => ({
    id: raw.id,
    name: raw.name,
    verify: raw.verify,
    enabled: raw.enabled,
    receiveCount: Number(raw.receive_count),
    lastReceivedAt: raw.last_received_at,
    lastStatus: raw.last_status,
    createdAt: raw.created_at,
  }),
};
