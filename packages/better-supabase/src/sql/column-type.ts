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

/** `value` (text) cast to the type of `column` on the quoted `table`. */
export function asColumnType(
  table: string,
  column: string,
  value: string,
): string {
  return `better_supabase.as_column_type(${value}, (null::${table}).${sqlIdent(column)})`;
}

/**
 * `sql` with `better_supabase.as_column_type` defined ahead of it when it calls
 * the function and does not define it. PL/pgSQL returns `value` through the
 * type's input function, so a text value becomes an enum label or any other
 * type `target` has.
 */
export function withColumnTypeFunction(sql: string): string {
  if (
    !sql.includes("better_supabase.as_column_type(") ||
    sql.includes("function better_supabase.as_column_type(")
  ) {
    return sql;
  }

  return `${columnTypeFunction()}\n${sql}`;
}
