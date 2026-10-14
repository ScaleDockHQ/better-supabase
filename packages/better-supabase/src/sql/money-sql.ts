import { ISO_4217_MINOR_UNITS } from "../blocks/commerce/iso4217.ts";
import { sqlString } from "../core/template.ts";

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
