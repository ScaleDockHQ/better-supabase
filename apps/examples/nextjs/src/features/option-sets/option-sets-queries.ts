import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { loadAdminList } from "@/features/admin-lists/admin-list-load";
import { postgres, userClaims } from "@/features/developer/postgres";
import { bsbShell } from "@/lib/supabase/server-shell";

import type { OptionItemRow } from "./option-sets-list";

import { OPTION_SETS_TAG } from "./option-sets-cache";
import { optionSetList } from "./option-sets-list";
import { optionSetSource } from "./option-sets-source";

/**
 * The first page of the organization's option sets with the count per state.
 * `bsbShell.cached()` reads with the user's token and RLS decides the rows.
 */
export async function getOptionSets() {
  "use cache: private";
  const { session } = await bsbShell.cached();
  cacheTag(OPTION_SETS_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  return loadAdminList({
    session,
    tenant,
    list: optionSetList,
    source: optionSetSource,
    access: "user",
    query: optionSetList.defaults,
  });
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
