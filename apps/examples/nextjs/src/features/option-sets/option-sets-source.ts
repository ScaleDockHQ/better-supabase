import "server-only";
import type {
  AdminListRaw,
  AdminListSource,
} from "@/features/admin-lists/admin-list-sql";

import type { OptionSetRow } from "./option-sets-list";

interface OptionSetRaw extends AdminListRaw {
  readonly name: string;
  readonly subject_type: string;
  readonly field: string;
  readonly is_default: boolean;
  readonly archived: boolean;
  readonly items: string;
  readonly created_at: string;
}

/**
 * The organization's option sets with their active item count. RLS lets members
 * with `option_sets.read` see them, so the page reads as the caller.
 */
export const optionSetSource: AdminListSource<OptionSetRaw, OptionSetRow> = {
  from: "better_supabase.option_sets s",
  idColumn: "s.id",
  idType: "uuid",
  timeColumn: "s.created_at",
  scope: "s.tenant_id = $1",
  search: ["s.name", "s.field", "s.subject_type"],
  facetSql: {
    state: "case when s.archived_at is null then 'active' else 'archived' end",
  },
  select: `s.name, s.subject_type, s.field, s.is_default,
    s.archived_at is not null as archived, s.created_at::text as created_at,
    (select count(*) from better_supabase.option_set_items i
      where i.option_set_id = s.id and i.archived_at is null)::text as items`,
  map: (raw) => ({
    id: raw.id,
    name: raw.name,
    subjectType: raw.subject_type,
    field: raw.field,
    isDefault: raw.is_default,
    archived: raw.archived,
    items: Number(raw.items),
    createdAt: raw.created_at,
  }),
};
