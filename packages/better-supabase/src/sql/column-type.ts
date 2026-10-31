import { sqlIdent } from "../core/template.ts";
import { SCHEMA, SERVICE_CALLER } from "./shared.ts";

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

function valueUnsupportedFunction(): string {
  return `${SCHEMA}
create or replace function better_supabase.value_unsupported(label text)
returns text
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  raise exception 'the app does not support the value %', label
    using errcode = '22023', hint = 'VALUE_UNSUPPORTED';
end;
$$;
revoke execute on function better_supabase.value_unsupported(text) from public;
grant execute on function better_supabase.value_unsupported(text) to anon, authenticated, service_role;`;
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

function columnDefaultFunction(): string {
  return `${SCHEMA}
create or replace function better_supabase.column_default(relation text, name text, target anyelement)
returns anyelement
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  result alias for $0;
  v_default text;
begin
  select pg_catalog.pg_get_expr(d.adbin, d.adrelid) into v_default
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  where a.attrelid = pg_catalog.to_regclass(column_default.relation) and a.attname = column_default.name and not a.attisdropped;
  if v_default is not null then
    execute 'select ' || v_default into result;
  end if;
  return result;
end;
$$;
revoke execute on function better_supabase.column_default(text, text, anyelement) from public, anon, authenticated, service_role;`;
}

/**
 * `better_supabase.import_run()`: the import run whose session this transaction
 * began, for the service role only. Any other caller gets null even when it
 * sets the transaction-local setting itself, so a user session can't turn
 * import mode on (ADR 0141).
 */
function importRunFunction(): string {
  return `${SCHEMA}
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and ${SERVICE_CALLER}
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;`;
}

const FUNCTIONS: readonly (readonly [string, () => string])[] = [
  ["as_column_type", columnTypeFunction],
  ["try_column_type", tryColumnTypeFunction],
  ["value_unsupported", valueUnsupportedFunction],
  ["column_default", columnDefaultFunction],
  ["import_run", importRunFunction],
];

/**
 * `sql` with `better_supabase.as_column_type`, `try_column_type` and
 * `import_run` defined ahead of it when it calls them and does not define them.
 * PL/pgSQL returns `value` through the type's input function, so a text value
 * becomes an enum label or any other type `target` has.
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
