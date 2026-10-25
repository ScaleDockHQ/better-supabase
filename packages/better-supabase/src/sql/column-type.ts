import { sqlIdent } from "../core/template.ts";
import { SCHEMA } from "./shared.ts";

function columnTypeFunction(): string {
  return `${SCHEMA}
create or replace function better_supabase.as_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return value;
end;
$$;
revoke execute on function better_supabase.as_column_type(text, anyelement) from public;
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;`;
}

function tryColumnTypeFunction(): string {
  return `${SCHEMA}
create or replace function better_supabase.try_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  result alias for $0;
begin
  result := value;
  return result;
exception when data_exception or check_violation then
  return null;
end;
$$;
revoke execute on function better_supabase.try_column_type(text, anyelement) from public;
grant execute on function better_supabase.try_column_type(text, anyelement) to anon, authenticated, service_role;`;
}

/** `value` (text) cast to the type of `column` on the quoted `table`. */
export function asColumnType(
  table: string,
  column: string,
  value: string,
): string {
  return `better_supabase.as_column_type(${value}, (null::${table}).${sqlIdent(column)})`;
}

export function tryColumnType(
  table: string,
  column: string,
  value: string,
): string {
  return `better_supabase.try_column_type(${value}, (null::${table}).${sqlIdent(column)})`;
}

const FUNCTIONS: readonly (readonly [string, () => string])[] = [
  ["as_column_type", columnTypeFunction],
  ["try_column_type", tryColumnTypeFunction],
];

/**
 * `sql` with `better_supabase.as_column_type` and `try_column_type` defined
 * ahead of it when it calls them and does not define them. PL/pgSQL returns
 * `value` through the type's input function, so a text value becomes an enum
 * label or any other type `target` has.
 */
export function withColumnTypeFunction(sql: string): string {
  const missing = FUNCTIONS.filter(
    ([name]) =>
      sql.includes(`better_supabase.${name}(`) &&
      !sql.includes(`function better_supabase.${name}(`),
  );

  return missing.length === 0
    ? sql
    : `${missing.map(([, define]) => define()).join("\n")}\n${sql}`;
}
