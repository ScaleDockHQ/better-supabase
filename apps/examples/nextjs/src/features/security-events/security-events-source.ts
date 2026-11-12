import "server-only";
import type {
  AdminListRaw,
  AdminListSource,
} from "@/features/admin-lists/admin-list-sql";

import type { SecurityStreamRow } from "./security-events-list";

interface SecurityStreamRaw extends AdminListRaw {
  readonly receiver: string;
  readonly status: string;
  readonly delivery: string;
  readonly events_delivered: readonly string[];
  readonly verified_at: string | null;
  readonly created_at: string;
}

/**
 * Security events: the rows the page reads as the database owner after its
 * permission check.
 */
export const securityStreamSource: AdminListSource<
  SecurityStreamRaw,
  SecurityStreamRow
> = {
  from: "better_supabase.ssf_streams s",
  idColumn: "s.id",
  idType: "uuid",
  timeColumn: "s.created_at",
  scope: "(s.tenant is null or s.tenant = $1::text)",
  search: ["s.receiver", "s.description"],
  facetSql: {
    status: "s.status",
    delivery:
      "case when s.delivery_method = 'urn:ietf:rfc:8935' then 'push' else 'poll' end",
  },
  select: `s.receiver, s.status, case when s.delivery_method = 'urn:ietf:rfc:8935' then 'push' else 'poll' end as delivery,
    s.events_delivered, s.verified_at::text as verified_at, s.created_at::text as created_at`,
  map: (raw) => ({
    id: raw.id,
    receiver: raw.receiver,
    status: raw.status,
    delivery: raw.delivery === "push" ? "push" : "poll",
    events: raw.events_delivered,
    verifiedAt: raw.verified_at,
    createdAt: raw.created_at,
  }),
};
