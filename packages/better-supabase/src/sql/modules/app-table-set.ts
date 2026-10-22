import type { AppTableConfig } from "../../config/types/app-tables.ts";
import type { ModuleIdType } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail, userGrant } from "../shared.ts";
import { APP_TABLE_SET } from "./bulk.ts";

/** An app table as `appTableSetSql` needs it. */
export interface SettableTable {
  readonly name: string;
  readonly config: AppTableConfig;
  /** The tenant column, when the table is scoped to the tenant. */
  readonly tenant: string | undefined;
}

/**
 * The columns `appTables.set` may write: the table's own columns, without
 * identities and without the columns signed-in users can't write (`access`).
 * The id, the scope column and the timestamps aren't own columns, so they are
 * never in the list.
 */
export function settableColumns(config: AppTableConfig): readonly string[] {
  return Object.entries(config.columns ?? {})
    .filter(
      ([, column]) =>
        column.identity !== true &&
        column.access === undefined &&
        column.encrypted !== true,
    )
    .map(([name]) => name);
}

/**
 * `public.app_table_set(tenant, subject_type, subject_id, args)`, the function
 * the bulk action `appTables.set` calls for each row. It runs as the caller, so
 * the table's policies and grants decide what changes, and casts `args.values`
 * to the column types through `jsonb_populate_record`. Empty without an app
 * table that is a subject.
 */
export function appTableSetSql(
  tables: readonly SettableTable[],
  idType: ModuleIdType,
): string {
  const arms = tables.flatMap((table) => {
    const subject = table.config.subject;
    const columns = settableColumns(table.config);

    if (subject === undefined || columns.length === 0) {
      return [];
    }

    const target = `public.${sqlIdent(table.name)}`;

    const set = columns
      .map(
        (column) =>
          `${sqlIdent(column)} = case when v_values ? ${sqlString(column)} then r.${sqlIdent(column)} else t.${sqlIdent(column)} end`,
      )
      .join(",\n          ");

    const tenant =
      table.tenant === undefined
        ? ""
        : `\n        and t.${sqlIdent(table.tenant)} = app_table_set.tenant`;

    return [
      `    when ${sqlString(subject.type)} then
      if exists (select 1 from jsonb_object_keys(v_values) k where not (k = any (${sqlString(`{${columns.join(",")}}`)}::text[]))) then
        ${fail("APP_TABLE_SET_COLUMN", `only these columns of ${table.name} can be set: ${columns.join(", ")}`, "22023")}
      end if;
      update ${target} t set
          ${set}
        from jsonb_populate_record(null::${target}, v_values) r
        where t.id = app_table_set.subject_id::${table.config.id === "bigint" ? "bigint" : "uuid"}${tenant};
      get diagnostics v_count = row_count;`,
    ];
  });

  if (arms.length === 0) {
    return "";
  }

  const fn = `public.${sqlIdent(APP_TABLE_SET)}`;

  return `-- Sets columns of one app table row for the bulk action appTables.set. It runs
-- as the caller, so the table's policies and grants decide what changes.
create or replace function ${fn}(tenant ${idType}, subject_type text, subject_id text, args jsonb)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_values jsonb := coalesce(app_table_set.args -> 'values', '{}'::jsonb);
  v_count integer := 0;
begin
  if jsonb_typeof(v_values) <> 'object' or v_values = '{}'::jsonb then
    ${fail("APP_TABLE_SET_EMPTY", "pass the columns to set as args.values", "22023")}
  end if;
  case app_table_set.subject_type
${arms.join("\n")}
    else
      ${fail("APP_TABLE_SET_SUBJECT", "not an app table subject type", "22023")}
  end case;
  if v_count = 0 then
    ${fail("APP_TABLE_SET_NOT_FOUND", "row not found or not writable", "P0002")}
  end if;
end;
$$;
${userGrant(`${fn}(${idType}, text, text, jsonb)`)}`;
}
