import "server-only";
import type {
  AdminListRaw,
  AdminListSource,
} from "@/features/admin-lists/admin-list-sql";

import type { DomainRow } from "./domains-list";

interface DomainRaw extends AdminListRaw {
  readonly hostname: string;
  readonly kind: string;
  readonly verified: boolean;
  readonly is_primary: boolean;
  readonly created_at: string;
  readonly token: string;
}

/**
 * The hostnames of one organization. `better_supabase.hostnames` is not on the
 * Data API, so the page reads it as the database owner after checking
 * `domains.read`; `scope` keeps it to the caller's organization.
 */
export const domainSource: AdminListSource<DomainRaw, DomainRow> = {
  from: "better_supabase.hostnames h",
  idColumn: "h.id",
  idType: "uuid",
  timeColumn: "h.created_at",
  scope: "h.tenant_id = $1",
  search: ["h.hostname"],
  facetSql: {
    state: "case when h.verified_at is null then 'pending' else 'verified' end",
    kind: "h.kind",
  },
  select: `h.hostname, h.kind, h.verified_at is not null as verified,
    h.is_primary, h.created_at::text as created_at, h.verification_token as token`,
  map: (raw) => ({
    id: raw.id,
    hostname: raw.hostname,
    kind: raw.kind === "subdomain" ? "subdomain" : "custom",
    verified: raw.verified,
    primary: raw.is_primary,
    createdAt: raw.created_at,
    record: raw.verified
      ? null
      : {
          name: `_better-supabase.${raw.hostname}`,
          value: `better-supabase-hostname-verification=${raw.token}`,
        },
  }),
};
