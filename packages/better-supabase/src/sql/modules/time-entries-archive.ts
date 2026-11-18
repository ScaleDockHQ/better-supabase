import type { BlockSqlContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { archiveRestoreFunctions } from "../archive-sql.ts";
import { conflict, SERVICE_CALLER, userGrant } from "../shared.ts";
import { byEmployee } from "./time-entries-owner.ts";
import { timerOptions } from "./time-entries-timers.ts";

/** What the archive functions borrow from the module's `build`. */
export interface EntryArchiveHelpers {
  readonly entryNotFound: string;
  readonly forbidden: (message: string) => string;
  /** Who may change the entry in `v_row` without a permission of its own. */
  readonly ownerOrManage: string;
  readonly running: (alias: string) => string;
  readonly overlap: (row: string) => string;
  readonly entryJson: (row: string) => string;
  readonly entryRecord: (
    type: string,
    row: string,
    withSeconds: boolean,
  ) => string;
}

/** `archive_time_entry`, `restore_time_entry` and `purge_time_entry`. */
export function archiveSql(
  ctx: BlockSqlContext,
  h: EntryArchiveHelpers,
): string {
  const entries = ctx.table("entries");
  const e = (column: string): string => ctx.col("entries", column);
  const fn = (name: string): string => ctx.fn(name);
  const purgeKey = ctx.config.permissions["purge"];

  const purgeGuard =
    purgeKey === undefined
      ? h.ownerOrManage
      : ctx.can("tenant", `v_row.${e("tenant")}`, sqlString(purgeKey));

  return `${
    ctx.has("entries", "archivedAt")
      ? archiveRestoreFunctions(ctx, {
          entity: "time_entry",
          arg: "entry_id",
          rowType: `${entries}%rowtype`,
          id: e("id"),
          archivedAt: e("archivedAt"),
          updatedAt: e("updatedAt"),
          table: entries,
          load: (
            name,
          ) => `select * into v_row from ${entries} x where x.${e("id")} = ${name}.entry_id for update;
  if not found then
    ${h.entryNotFound}
  end if;
  if not (${SERVICE_CALLER} or ${h.ownerOrManage}) then
    ${h.forbidden("not allowed to change this entry")}
  end if;`,
          beforeArchive: `
  if ${h.running("v_row")} then
    ${conflict("TIME_TIMER_RUNNING", "stop the running timer before archiving it")}
  end if;`,
          beforeRestore: `
  ${h.overlap("v_row")}`,
          json: h.entryJson("v_row"),
          record: (type) => h.entryRecord(type, "v_row", true),
          archiveNote:
            "Archives a finished entry: it leaves totals, reports, invoices and payroll. A locked week, a running timer and an invoiced entry refuse it.",
          restoreNote:
            "Brings an archived entry back. A locked week and an overlapping entry refuse it.",
        })
      : ""
  }
-- Removes an entry for good. Needs permissions.purge, which falls back to the
-- entry's owner (with track) and manage. A locked week and an invoiced entry
-- refuse it.
create or replace function ${fn("purge_time_entry")}(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${entries}%rowtype;
begin
  select * into v_row from ${entries} x where x.${e("id")} = purge_time_entry.entry_id for update;
  if not found then
    ${h.entryNotFound}
  end if;
  if not (${SERVICE_CALLER} or ${purgeGuard}) then
    ${h.forbidden("not allowed to purge this entry")}
  end if;
  delete from ${entries} x where x.${e("id")} = v_row.${e("id")};
  ${h.entryRecord("time_entry.purged", "v_row", false)}
  return ${h.entryJson("v_row")};
end;
$$;
${userGrant(`${fn("purge_time_entry")}(uuid)`)}`;
}

/** Version 4: the overlap constraint skips archived entries. */
export function upgradeArchive(ctx: BlockSqlContext): string {
  if (
    !ctx.owns("entries") ||
    !ctx.has("entries", "archivedAt") ||
    timerOptions(ctx).allowOverlap
  ) {
    return "";
  }

  const entries = ctx.table("entries");
  const e = (column: string): string => ctx.col("entries", column);
  const owner = byEmployee(ctx) ? e("employee") : e("user");
  const name = sqlIdent(`${ctx.tableName("entries").name}_no_overlap_excl`);

  return `drop function if exists ${ctx.fn("delete_time_entry")}(uuid);
alter table ${entries} add column if not exists ${e("archivedAt")} timestamptz;
alter table ${entries} drop constraint if exists ${name};
alter table ${entries} add constraint ${name} exclude using gist (
  ${e("tenant")} with =,
  ${owner} with =,
  tstzrange(${e("startedAt")}, coalesce(${e("endedAt")}, 'infinity'::timestamptz)) with &&
) where (${e("archivedAt")} is null);`;
}
