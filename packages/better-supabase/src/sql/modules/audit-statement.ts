import type { BlockSqlContext } from "../context.ts";

import { entryLoadSql, recordedPredicate } from "./audit-entry.ts";

/**
 * The trigger reads the JWT and the request headers once per call, not once per
 * column that uses them.
 */
export function once(sql: string): string {
  return sql
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
 * entry of the statement in one insert, instead of one insert per row.
 */
export function statementFunction(
  ctx: BlockSqlContext,
  parts: {
    /** SQL for the tenant of `row_data`. */
    tenantValue: string;
    /** The log's column list and the values for one paired row. */
    insert: { columns: string; values: string };
    grant: string;
  },
): string {
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
    ), final as (
      select k.op, k.row_data, k.changed_columns, k.row_tenant,
        k.old_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.old_row ? r), '{}') as old_row,
        k.new_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.new_row ? r), '{}') as new_row
      from kept k
    )
    insert into ${ctx.table("log")} (${parts.insert.columns})
    select ${once(parts.insert.values)}
    from final;`;

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
begin
  if current_setting('better_supabase.import_audit', true) = 'summary' and better_supabase.import_run() is not null then
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
