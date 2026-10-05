import type { AuditedTable } from "../audit-registrations.ts";
import type { KitContext } from "../context.ts";
import type { KitTestFile } from "../kit.ts";

import { sqlString } from "../../core/template.ts";

const PROBE = "pg_temp.bs_audit_probe";
const PROBE_NAME =
  "(select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bs_audit_probe'";

const textArray = (names: readonly string[]): string =>
  `${sqlString(`{${names.map((name) => `"${name.replaceAll('"', '\\"')}"`).join(",")}}`)}::text[]`;

/** A quoted identifier for `schema.table` from its unquoted parts. */
const quotedTarget = (target: string): string => {
  const dot = target.indexOf(".");
  return [target.slice(0, dot), target.slice(dot + 1)]
    .map((part) => `"${part.replaceAll('"', '""')}"`)
    .join(".");
};

/**
 * A copy of the table's columns with their defaults, without constraints or
 * NOT NULL, so `default values` and type-shaped values always insert. The
 * copy carries the same registration as the table, so the trigger writes
 * the same entries the table's rows would.
 */
const probe = (
  table: AuditedTable,
): string => `create temp table bs_audit_probe (like ${quotedTarget(table.target)} including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = '${PROBE}'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table ${PROBE} alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('${PROBE}', ignore => ${textArray(table.ignore)}, redact => ${textArray(table.redact)});
  insert into ${PROBE} default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = '${PROBE}'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update ${PROBE} set %s', sets);
  end if;
  delete from ${PROBE};
end;
$$;`;

/**
 * The pgTAP file for one audited table: the trigger and registration match
 * the `audit()` call, and inserts, updates and deletes on a copy of the
 * table write entries without the ignored columns and with the redacted
 * values masked.
 */
function auditTableTest(
  ctx: KitContext,
  table: AuditedTable,
  restricted: boolean,
): string {
  const dot = table.target.indexOf(".");
  const schema = sqlString(table.target.slice(0, dot));
  const name = sqlString(table.target.slice(dot + 1));
  const regclass = `${sqlString(quotedTarget(table.target))}::regclass`;
  const log = ctx.table("log");
  const c = (logical: string) => ctx.col("log", logical);
  const checks: string[] = [
    `select extensions.has_trigger(${schema}, ${name}, 'bs_audit', ${sqlString(`${table.target} has the bs_audit trigger`)});`,
    `select extensions.trigger_is(${schema}, ${name}, 'bs_audit', 'better_supabase', 'audit_row_change', ${sqlString(`bs_audit on ${table.target} calls audit_row_change()`)});`,
    `select extensions.is((select a.ignore from better_supabase.audited_tables a where a.target = ${regclass}), ${textArray(table.ignore)}, ${sqlString(`${table.target} is registered with its ignored columns`)});`,
    `select extensions.is((select a.redact from better_supabase.audited_tables a where a.target = ${regclass}), ${textArray(table.redact)}, ${sqlString(`${table.target} is registered with its redacted columns`)});`,
  ];
  const behaviour = ctx.has("log", "table") && ctx.has("log", "op");
  if (!behaviour) {
    return `begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(${String(checks.length)});

${checks.join("\n")}

select * from extensions.finish();
rollback;`;
  }
  const joined = restricted && ctx.hasTable("restricted");
  const entries = `from ${log} l${
    joined
      ? ` left join ${ctx.table("restricted")} r on r.${ctx.col("restricted", "entry")} = l.${c("id")}`
      : ""
  } where l.${c("table")} = ${PROBE_NAME}`;
  const side = (logical: "old" | "new"): string | undefined => {
    if (joined) {
      return ctx.has("restricted", logical)
        ? `r.${ctx.col("restricted", logical)}`
        : undefined;
    }
    return ctx.has("log", logical) ? `l.${c(logical)}` : undefined;
  };
  const records = [side("old"), side("new")].filter(
    (value) => value !== undefined,
  );
  checks.push(
    `select extensions.results_eq($$select l.${c("op")}::text ${entries} order by l.${c("id")}$$, $$values ('insert'), ('update'), ('delete')$$, ${sqlString(`inserts, updates and deletes on ${table.target} write entries`)});`,
  );
  if (table.ignore.length > 0) {
    const tests = [
      ...(ctx.has("log", "changed")
        ? [`coalesce(l.${c("changed")} && ${textArray(table.ignore)}, false)`]
        : []),
      ...records.map(
        (record) => `coalesce(${record} ?| ${textArray(table.ignore)}, false)`,
      ),
    ];
    if (tests.length > 0) {
      checks.push(
        `select extensions.is((select count(*)::int ${entries} and (${tests.join(" or ")})), 0, ${sqlString(`entries for ${table.target} leave out ${table.ignore.join(", ")}`)});`,
      );
    }
  }
  const after = side("new");
  if (table.redact.length > 0 && after !== undefined) {
    checks.push(
      `select extensions.is((select count(*)::int ${entries} and l.${c("op")} <> 'delete' and exists (select 1 from unnest(${textArray(table.redact)}) k where ${after} ? k and ${after} ->> k is distinct from '[redacted]')), 0, ${sqlString(`entries for ${table.target} mask ${table.redact.join(", ")}`)});`,
    );
  }
  return `begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(${String(checks.length)});

${probe(table)}

${checks.join("\n")}

select * from extensions.finish();
rollback;`;
}

/** One pgTAP file per table in `audited`, named after the table. */
export function auditTests(
  ctx: KitContext,
  audited: readonly AuditedTable[],
  restricted: boolean,
): KitTestFile[] {
  return audited.map((table) => ({
    name: table.target.toLowerCase().replaceAll(/[^a-z0-9]+/g, "_"),
    sql: auditTableTest(ctx, table, restricted),
  }));
}
