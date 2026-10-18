import { ISO_4217_MINOR_UNITS } from "../commerce/iso4217.ts";
import { sqlString } from "../core/template.ts";

/**
 * `jsonb_build_object` of the `int8` columns of row `alias` as text, keyed
 * like `to_jsonb(alias)` so it merges over it. A JSON number loses precision
 * past 2^53, so every `int8` a block function returns is text (ADR 0037).
 * `columns` are the quoted identifiers `ctx.col` returns.
 */
export const int8Text = (alias: string, columns: readonly string[]): string =>
  `jsonb_build_object(${columns
    .map(
      (column) =>
        `${sqlString(column.replaceAll('"', ""))}, ${alias}.${column}::text`,
    )
    .join(", ")})`;

/**
 * `create function <name>(code text) returns integer`: the minor units of an
 * ISO 4217 currency code from the list pinned in `SPEC_PINS.iso4217`, or
 * `null` for a code the list doesn't carry. Money columns store `bigint`
 * minor units next to a `char(3)` code, and functions refuse a code this
 * returns `null` for.
 */
export function currencyMinorUnitsFunction(name: string): string {
  const rows = Object.entries(ISO_4217_MINOR_UNITS)
    .map(([code, units]) => `(${sqlString(code)}, ${String(units)})`)
    .join(", ");

  return `create or replace function ${name}(code text)
returns integer
language sql
immutable
parallel safe
set search_path = ''
as $$
  select c.units from (values ${rows}) as c (code, units) where c.code = $1
$$;
grant execute on function ${name}(text) to anon, authenticated, service_role;`;
}
