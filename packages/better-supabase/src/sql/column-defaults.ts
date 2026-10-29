import { sqlString } from "../core/template.ts";
import { NOTHING } from "./shared.ts";

const QUOTED_IDENT = /^"(.*)"$/s;

const bareName = (ident: string): string =>
  QUOTED_IDENT.exec(ident)?.[1]?.replaceAll('""', '"') ?? ident;

/**
 * PL/pgSQL that stores in `into` (a `jsonb` variable) the defaults of the
 * columns of `table` whose value is null, as `[column, value]` pairs of a
 * quoted identifier and SQL. An insert then writes `withColumnDefault(...)`
 * instead of an explicit null, so an app column such as `title text not null
 * default ''` keeps its default. Only the defaults of null values run.
 */
export function columnDefaults(
  table: string,
  columns: readonly (readonly [string, string])[],
  into: string,
): string {
  if (columns.length === 0) {
    return NOTHING;
  }

  const wanted = columns
    .map(
      ([column, value]) =>
        `case when ${value} is null then ${sqlString(bareName(column))} end`,
    )
    .join(", ");

  return `execute coalesce((select 'select jsonb_build_object(' || string_agg(pg_catalog.quote_literal(a.attname) || ', ' || pg_catalog.pg_get_expr(d.adbin, d.adrelid), ', ') || ')'
    from pg_catalog.pg_attrdef d join pg_catalog.pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
    where d.adrelid = ${sqlString(table)}::regclass and a.attname = any (array[${wanted}]::text[])), 'select ''{}''::jsonb') into ${into};`;
}

/**
 * `value`, or the default `columnDefaults` stored in `defaults` when it is
 * null.
 */
export const withColumnDefault = (
  table: string,
  column: string,
  value: string,
  defaults: string,
): string =>
  `coalesce(${value}, (jsonb_populate_record(null::${table}, ${defaults})).${column})`;

/**
 * An `exception when unique_violation then` body: `then` (a `raise`) when the
 * violated index of `table` covers `column` (a quoted identifier), in its
 * columns or its expressions, and the original error otherwise, so an app's own
 * unique index keeps its constraint name.
 */
export function uniqueViolationOn(
  table: string,
  column: string,
  then: string,
): string {
  const name = sqlString(bareName(column));

  return `declare
      v_constraint text;
    begin
      get stacked diagnostics v_constraint = constraint_name;
      if exists (
        select 1 from pg_catalog.pg_index i
        join pg_catalog.pg_class c on c.oid = i.indexrelid
        where i.indrelid = ${sqlString(table)}::regclass and c.relname = v_constraint
          and (exists (select 1 from pg_catalog.pg_attribute a where a.attrelid = i.indrelid and a.attnum = any (i.indkey) and a.attname = ${name})
            or coalesce(pg_catalog.pg_get_expr(i.indexprs, i.indrelid), '') ~ ('\\m' || ${name} || '\\M'))
      ) then
        ${then}
      end if;
      raise;
    end;`;
}
