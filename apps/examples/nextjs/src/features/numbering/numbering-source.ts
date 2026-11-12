import "server-only";
import type {
  AdminListRaw,
  AdminListSource,
} from "@/features/admin-lists/admin-list-sql";

import type { NumberingRow } from "./numbering-list";

interface NumberingRaw extends AdminListRaw {
  readonly entity: string;
  readonly period: string;
  readonly scope: string | null;
  readonly last_number: string;
  readonly updated_at: string;
}

/**
 * Numbering: the rows the page reads as the database owner after its permission
 * check.
 */
export const numberingSource: AdminListSource<NumberingRaw, NumberingRow> = {
  from: "better_supabase.number_sequences n",
  idColumn:
    "(n.entity || '/' || n.period || '/' || coalesce(n.legal_entity_id::text, ''))",
  idType: "text",
  timeColumn: "n.updated_at",
  scope: "n.tenant_id = $1",
  search: ["n.entity", "n.period"],
  facetSql: { entity: "n.entity" },
  select: `n.entity, n.period, n.scope, n.last_number::text as last_number, n.updated_at::text as updated_at`,
  map: (raw) => ({
    id: raw.id,
    entity: raw.entity,
    period: raw.period,
    scope: raw.scope,
    lastNumber: Number(raw.last_number),
    updatedAt: raw.updated_at,
  }),
};
