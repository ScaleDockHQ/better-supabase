import type { BlockSqlContext } from "../context.ts";

import { entryLoadSql, recordedPredicate } from "./audit-entry.ts";
import { INTEGRATION_TEST } from "./audit-subjects.ts";
import { tenantLabel } from "./audit-values.ts";

/**
 * The trigger reads the JWT and the request headers once per call, not once per
 * column that uses them.
 */
export function once(sql: string): string {
  return sql
    .replaceAll(INTEGRATION_TEST, "v_integration")
    .replaceAll("auth.jwt()", "v_jwt")
    .replaceAll(
      /better_supabase\.request_header\(('[^']*')\)/g,
      "(v_headers ->> $1)",
    );
}

const KEY = (row: string): string =>
  `(select string_agg(to_jsonb(${row}) ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord))`;

/**
 * `audit_statement_change()`: the trigger function of a table audited with
 * `statement => true`. It reads the transition tables once and writes every
 * entry of the statement in one insert, and the restricted details in one more
 * when the app keeps them in their own table, instead of one insert per row.
 */
export function statementFunction(
  ctx: BlockSqlContext,
  parts: {
    /** SQL for the tenant of `row_data`. */
    tenantValue: string;
    /** The log's column list and the values for one paired row. */
    insert: { columns: string; values: string };
    /**
     * Where the restricted details go, when the app keeps them apart. `values`
     * read `f` (the entry's source row) and `lg` (the log row just written).
     */
    restricted?:
      | { table: string; columns: string; values: string; logId: string }
      | undefined;
    grant: string;
  },
): string {
  // One lookup per distinct tenant of the statement, not one per row.
  const label = tenantLabel(ctx, "row_tenant");
  const labels = label !== "null" && parts.insert.values.includes(label);

  const values = labels
    ? parts.insert.values.replaceAll(label, "l.label")
    : parts.insert.values;

  const restricted = parts.restricted;

  // The restricted rows are matched to their entries by position: the entries
  // are inserted in `rn` order, and RETURNING emits them in insertion order.
  // The log's id can be a uuid, so it can't carry the order.
  const changedValues = `(select jsonb_object_agg(k, jsonb_build_object(
          'old', case when length((r.old_row -> k)::text) > 1000 then to_jsonb(left((r.old_row -> k)::text, 1000)) else r.old_row -> k end,
          'new', case when length((r.new_row -> k)::text) > 1000 then to_jsonb(left((r.new_row -> k)::text, 1000)) else r.new_row -> k end
        )) from unnest(coalesce(r.changed_columns, array(select jsonb_object_keys(coalesce(r.new_row, r.old_row))))) k)`;

  const finalCte = restricted
    ? `redacted as (
      select k.op, k.row_data, k.changed_columns, k.row_tenant,
        k.old_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.old_row ? r), '{}') as old_row,
        k.new_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.new_row ? r), '{}') as new_row
      from kept k
    ), final as (
      select r.*, row_number() over () as rn, ${changedValues} as changed_values
      from redacted r
    )`
    : `final as (
      select k.op, k.row_data, k.changed_columns, k.row_tenant,
        k.old_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.old_row ? r), '{}') as old_row,
        k.new_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.new_row ? r), '{}') as new_row
      from kept k
    )`;

  const labelsCte = labels
    ? `, labels as (
      select t.row_tenant as tenant_key, ${tenantLabel(ctx, "t.row_tenant")} as label
      from (select distinct row_tenant from kept) t
    )`
    : "";

  const entries = `select ${once(values)}
    from final${labels ? "\n    left join labels l on l.tenant_key is not distinct from final.row_tenant" : ""}`;

  const write = (source: string): string => `with src as (
      ${source}
    ), paired as (
      select case when s.old_row is null then 'insert' when s.new_row is null then 'delete' else 'update' end as op,
        coalesce(s.new_row, s.old_row) as row_data,
        s.old_row - entry.ignore as old_row, s.new_row - entry.ignore as new_row
      from src s
    ), changed as (
      select p.*, case when p.op = 'update' then (
          select array_agg(e.key order by e.key) from jsonb_each(p.new_row) e
          where e.value is distinct from p.old_row -> e.key
        ) end as changed_columns
      from paired p
    ), kept as (
      select c.*, ${parts.tenantValue} as row_tenant
      from changed c
      where (c.op <> 'update' or c.changed_columns is not null)
        and not (${recordedPredicate()})
    ), ${finalCte}${labelsCte}${
      restricted
        ? `, logged as (
      insert into ${ctx.table("log")} (${parts.insert.columns})
      ${entries}
      order by final.rn
      returning ${restricted.logId} as entry_id
    )
    insert into ${restricted.table} (${restricted.columns})
    select ${once(restricted.values)}
    from (select x.entry_id, row_number() over () as rn from logged x) lg
    join final f on f.rn = lg.rn;`
        : `
    insert into ${ctx.table("log")} (${parts.insert.columns})
    ${entries};`
    }`;

  const sides = {
    insert:
      "select null::jsonb as old_row, to_jsonb(n) as new_row from new_rows n",
    delete:
      "select to_jsonb(o) as old_row, null::jsonb as new_row from old_rows o",
    update: `select o.j as old_row, n.j as new_row
      from (select to_jsonb(r) as j, ${KEY("r")} as k from old_rows r) o
      full join (select to_jsonb(r) as j, ${KEY("r")} as k from new_rows r) n on o.k = n.k`,
  } as const;

  return `-- Statement-level audit (audit(..., statement => true)): the transition tables
-- hold every row the statement changed, so the whole statement is audited with
-- one insert. An update that changes a key column is audited as a delete and an
-- insert.
create or replace function better_supabase.audit_statement_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry record;
  settings jsonb;
  v_jwt jsonb := auth.jwt();
  v_headers jsonb := better_supabase.request_headers();
${restricted ? "  v_ip inet := better_supabase.request_ip();\n" : ""}  v_integration boolean := better_supabase.import_run() is not null;
begin
  if v_integration and current_setting('better_supabase.import_audit', true) = 'summary' then
    return null;
  end if;
${entryLoadSql(ctx)}
  if tg_op = 'INSERT' then
    ${write(sides.insert)}
  elsif tg_op = 'DELETE' then
    ${write(sides.delete)}
  else
    ${write(sides.update)}
  end if;
  return null;
end;
$$;
${parts.grant}`;
}
