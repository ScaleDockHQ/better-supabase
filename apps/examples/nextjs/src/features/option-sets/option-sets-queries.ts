import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type {
  RecordListPage,
  RecordListUrlQuery,
} from "@/components/record-list/record-list-types";

import { postgres, userClaims } from "@/features/developer/postgres";
import { pageEntityRows } from "@/lib/block-entity-page";
import { bsb } from "@/lib/supabase/server";
import { bsbShell } from "@/lib/supabase/server-shell";

import type { OptionItemRow, OptionSetRow } from "./option-sets-list";

import { OPTION_SETS_TAG } from "./option-sets-cache";
import { optionSetList, optionSetMap } from "./option-sets-list";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

/**
 * One page of the organization's option sets for a list query, searched,
 * filtered and sorted by the block's `setPage` and counted by `setFacets`.
 * Archived sets are hidden, as the block hides them by default.
 */
export function getOptionSetPage(
  db: Db,
  organizationId: string,
  query: RecordListUrlQuery,
): Promise<RecordListPage<OptionSetRow>> {
  return pageEntityRows({
    pager: {
      page: (options) => db.optionSets.setPage({ organizationId, ...options }),
      facets: (options) =>
        db.optionSets.setFacets({ organizationId, ...options }),
    },
    map: optionSetMap,
    query,
    pageSize: optionSetList.config.pageSize,
    rowsOf: (sets) =>
      sets.map((set): OptionSetRow => ({
        id: set.id,
        name: set.name,
        subjectType: set.subjectType,
        field: set.field,
        isDefault: set.isDefault,
        items: set.items.length,
      })),
  });
}

/**
 * The first page of the organization's option sets with the count per record
 * type and field. `bsb.cached()` reads with the user's token and RLS decides
 * the rows.
 */
export async function getOptionSets() {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(OPTION_SETS_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  return getOptionSetPage(db, tenant, optionSetList.defaults);
}

interface SetRecord {
  readonly id: string;
  readonly name: string;
  readonly subject_type: string;
  readonly field: string;
  readonly is_default: boolean;
  readonly archived: boolean;
}

interface ItemRecord {
  readonly id: string;
  readonly key: string;
  readonly label: string;
  readonly level: number;
  readonly color: string | null;
  readonly icon: string | null;
  readonly archived: boolean;
}

/** One option set with its items in rank order; `null` when RLS hides it. */
export async function getOptionSet(id: string) {
  "use cache: private";
  const { session } = await bsbShell.cached({ id });
  cacheTag(OPTION_SETS_TAG);
  const tenant = tenantOf(session);
  const connection = postgres();
  const claims = userClaims(session);

  if (!tenant || !connection || !claims) {
    return null;
  }

  const sql = connection.asUser(claims);

  const [sets, items] = await Promise.all([
    sql.queryRaw<SetRecord>(
      `select id, name, subject_type, field, is_default, archived_at is not null as archived
       from better_supabase.option_sets where id = $1 and tenant_id = $2`,
      [id, tenant],
    ),
    sql.queryRaw<ItemRecord>(
      `select id, key, label, level, color, icon, archived_at is not null as archived
       from better_supabase.option_set_items
       where option_set_id = $1 and tenant_id = $2
       order by rank collate "C", id`,
      [id, tenant],
    ),
  ]);

  const [set] = sets;

  if (!set) {
    return null;
  }

  return {
    id: set.id,
    name: set.name,
    subjectType: set.subject_type,
    field: set.field,
    isDefault: set.is_default,
    archived: set.archived,
    items: items.map((item): OptionItemRow => ({
      id: item.id,
      key: item.key,
      label: item.label,
      level: item.level,
      color: item.color,
      icon: item.icon,
      archived: item.archived,
    })),
  };
}
