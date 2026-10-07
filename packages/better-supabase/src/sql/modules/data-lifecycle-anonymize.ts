import type { ModuleContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { SERVICE_CALLER, splitTable } from "../shared.ts";

interface AnonymizeRule {
  /** `schema.table`, unquoted, for the result keys. */
  readonly name: string;
  readonly table: string;
  readonly after: string;
  readonly from: string;
  readonly unless: string | undefined;
  readonly set: readonly (readonly [column: string, value: string])[];
  readonly markedBy: string;
}

const IDENT = /^[a-z_][a-z0-9_$]{0,62}$/;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** A `set` value: a literal, `null`, or `{ sql }` with `{row}` for the row. */
function valueSql(at: string, value: unknown): string {
  if (value === null) return "null";
  if (typeof value === "string") return sqlString(value);
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  if (typeof value === "boolean") return String(value);
  if (isRecord(value) && typeof value["sql"] === "string") {
    return `(${value["sql"].replaceAll("{row}", "r")})`;
  }
  throw new TypeError(
    `${at} must be a string, number, boolean, null or { sql: "<expression>" }`,
  );
}

function rulesOf(ctx: ModuleContext): readonly AnonymizeRule[] {
  const where = "sql.modules.data-lifecycle.options.anonymize";
  const value = ctx.option("anonymize");
  if (value === undefined) return [];
  if (!Array.isArray(value)) {
    throw new TypeError(
      `${where} must be a list of { table, after, from, set, markedBy, unless? }`,
    );
  }
  const ident = (at: string, name: unknown): string => {
    if (typeof name !== "string" || !IDENT.test(name)) {
      throw new TypeError(`${at} must be a lowercase column name`);
    }
    return name;
  };
  return value.map((rule: unknown, index): AnonymizeRule => {
    const at = `${where}[${String(index)}]`;
    if (
      !isRecord(rule) ||
      typeof rule["table"] !== "string" ||
      typeof rule["after"] !== "string" ||
      !isRecord(rule["set"])
    ) {
      throw new TypeError(
        `${at} must be { table: "schema.table", after: "<interval>", from: "<column>", set: { column: value }, markedBy: "<column>", unless?: "<condition on {row}>" }`,
      );
    }
    const unless = rule["unless"];
    if (
      unless !== undefined &&
      (typeof unless !== "string" || !unless.includes("{row}"))
    ) {
      throw new TypeError(`${at}.unless must be a condition on {row}`);
    }
    const set = Object.entries(rule["set"]).map(
      ([column, item]) =>
        [
          sqlIdent(ident(`${at}.set.${column}`, column)),
          valueSql(`${at}.set.${column}`, item),
        ] as const,
    );
    if (set.length === 0) {
      throw new TypeError(`${at}.set must name at least one column`);
    }
    const [schema, table] = splitTable(rule["table"]);
    return {
      name: `${schema}.${table}`,
      table: `${sqlIdent(schema)}.${sqlIdent(table)}`,
      after: rule["after"],
      from: sqlIdent(ident(`${at}.from`, rule["from"])),
      unless: unless?.replaceAll("{row}", "r"),
      set,
      markedBy: sqlIdent(ident(`${at}.markedBy`, rule["markedBy"])),
    };
  });
}

/**
 * `anonymize_due(max_rows)`: applies `options.anonymize` to the rows whose
 * `from` time is older than `after`, at most `max_rows` per rule, and marks
 * them in `markedBy` so each row is anonymized once.
 */
export function anonymizeSql(ctx: ModuleContext): string {
  const fn = ctx.fn("anonymize_due");
  const rules = rulesOf(ctx);
  const blocks = rules.map(
    (rule) => `
  with due as (
    select r.ctid from ${rule.table} r
    where r.${rule.markedBy} is null
      and r.${rule.from} is not null
      and r.${rule.from} <= now() - ${sqlString(rule.after)}::interval${
        rule.unless === undefined
          ? ""
          : `\n      and not coalesce((${rule.unless}), false)`
      }
    limit v_max
    for update skip locked
  ), done as (
    update ${rule.table} r
    set ${rule.set.map(([column, value]) => `${column} = ${value}`).join(", ")}, ${rule.markedBy} = now()
    from due
    where r.ctid = due.ctid
    returning 1
  )
  select count(*) into v_count from done;
  v_done := v_done || jsonb_build_object(${sqlString(rule.name)}, v_count);`,
  );
  return `
-- Anonymizes the rows sql.modules.data-lifecycle.options.anonymize names once
-- their time is up (service role): at most max_rows per rule, each row once,
-- marked with the time. Returns { table: rows }.
create or replace function ${fn}(max_rows integer default 1000)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare${
    rules.length === 0
      ? ""
      : `
  v_max integer := greatest(1, least(coalesce(max_rows, 1000), 10000));
  v_count bigint;`
  }
  v_done jsonb := '{}'::jsonb;
begin
  if not (${SERVICE_CALLER}) then
    raise exception 'Only the service role anonymizes rows' using errcode = '42501', hint = 'DATA_ANONYMIZE_FORBIDDEN';
  end if;${blocks.join("")}
  return v_done;
end;
$$;
revoke execute on function ${fn}(integer) from public, anon, authenticated;
grant execute on function ${fn}(integer) to service_role;
`;
}
