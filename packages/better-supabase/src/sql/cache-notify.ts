import type { SchemaMeta, TableMeta } from "../schema/types.ts";

import { sqlIdent, sqlString } from "../core/template.ts";

/** Vault secret names `better_supabase.notify_cache()` reads. */
export const CACHE_NOTIFY_URL_SECRET = "bsb_cache_url";
export const CACHE_NOTIFY_BEARER_SECRET = "bsb_cache_bearer";

export interface CacheInvalidationSqlOptions {
  /** App keys of the tables to watch. Default: every table, not views. */
  readonly tables?: readonly string[];
  /**
   * A statement that changes more rows than this sends no ids, so the route
   * expires the whole table. Default: 1000.
   */
  readonly maxRows?: number;
}

const FUNCTION_NAME = "better_supabase.notify_cache";

/**
 * The shared trigger function. It reads the route URL and the bearer token from
 * Vault, sums up the rows a statement changed (table, primary keys, tenants)
 * and queues one `pg_net` request, which Postgres sends only after the
 * transaction commits. Without the URL secret it does nothing.
 */
function functionSql(): string {
  return `create schema if not exists better_supabase;

create or replace function ${FUNCTION_NAME}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $notify$
declare
  key_columns text[] := coalesce(string_to_array(nullif(tg_argv[0], ''), ','), '{}');
  tenant_column text := nullif(tg_argv[1], '');
  max_rows int := coalesce(nullif(tg_argv[2], '')::int, 1000);
  route_url text;
  route_bearer text;
  changed jsonb := '[]'::jsonb;
  ids jsonb := '[]'::jsonb;
  tenants jsonb := '[]'::jsonb;
begin
  select decrypted_secret into route_url
    from vault.decrypted_secrets where name = ${sqlString(CACHE_NOTIFY_URL_SECRET)};

  if route_url is null then
    return null;
  end if;

  select decrypted_secret into route_bearer
    from vault.decrypted_secrets where name = ${sqlString(CACHE_NOTIFY_BEARER_SECRET)};

  if tg_op in ('INSERT', 'UPDATE') then
    select coalesce(jsonb_agg(to_jsonb(new_rows)), '[]'::jsonb) into changed from new_rows;
  end if;

  if tg_op in ('UPDATE', 'DELETE') then
    changed := changed || (select coalesce(jsonb_agg(to_jsonb(old_rows)), '[]'::jsonb) from old_rows);
  end if;

  if jsonb_array_length(changed) = 0 then
    return null;
  end if;

  if tenant_column is not null then
    select coalesce(jsonb_agg(distinct r ->> tenant_column), '[]'::jsonb)
      into tenants from jsonb_array_elements(changed) r;
  end if;

  if cardinality(key_columns) > 0 and jsonb_array_length(changed) <= max_rows then
    select coalesce(jsonb_agg(distinct row_key), '[]'::jsonb) into ids
      from (
        select (
          select string_agg(r ->> k.name, ',' order by k.position)
            from unnest(key_columns) with ordinality as k(name, position)
        ) as row_key
          from jsonb_array_elements(changed) r
      ) keys
      where row_key is not null;
  end if;

  perform net.http_post(
    url := route_url,
    body := jsonb_build_object(
      'schema', tg_table_schema,
      'table', tg_table_name,
      'op', tg_op,
      'ids', ids,
      'tenants', tenants
    ),
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'authorization', 'Bearer ' || coalesce(route_bearer, '')
    )
  );

  return null;
end;
$notify$;

revoke all on function ${FUNCTION_NAME}() from public;`;
}

function dbColumn(table: TableMeta, app: string): string {
  return table.columns[app]?.db ?? app;
}

function triggersSql(table: TableMeta, maxRows: number): string {
  const target = `${sqlIdent(table.schema)}.${sqlIdent(table.name)}`;

  const args = [
    table.primaryKey.map((column) => dbColumn(table, column)).join(","),
    table.flags.tenant === undefined ? "" : dbColumn(table, table.flags.tenant),
    String(maxRows),
  ]
    .map(sqlString)
    .join(", ");

  const name = (event: string): string =>
    sqlIdent(`bsb_cache_${event}_${table.name}`.slice(0, 63));

  return `drop trigger if exists ${name("insert")} on ${target};
create trigger ${name("insert")} after insert on ${target}
  referencing new table as new_rows
  for each statement execute function ${FUNCTION_NAME}(${args});

drop trigger if exists ${name("update")} on ${target};
create trigger ${name("update")} after update on ${target}
  referencing old table as old_rows new table as new_rows
  for each statement execute function ${FUNCTION_NAME}(${args});

drop trigger if exists ${name("delete")} on ${target};
create trigger ${name("delete")} after delete on ${target}
  referencing old table as old_rows
  for each statement execute function ${FUNCTION_NAME}(${args});`;
}

/**
 * SQL for a migration that tells `cacheRoute` about every write to the chosen
 * tables, whoever makes it: SQL, `pg_cron` or another service. It creates
 * `better_supabase.notify_cache()` and, per table, statement-level triggers for
 * insert, update and delete. Store the route URL and the bearer token in Vault
 * under `bsb_cache_url` and `bsb_cache_bearer`; without the URL the triggers do
 * nothing. Needs the `pg_net` and `supabase_vault` extensions.
 */
export function cacheInvalidationSql(
  meta: SchemaMeta,
  options: CacheInvalidationSqlOptions = {},
): string {
  const wanted = options.tables;

  const tables = Object.values(meta.tables).filter(
    (table) =>
      table.kind === "table" &&
      (wanted === undefined || wanted.includes(table.key)),
  );

  const unknown = (wanted ?? []).filter((key) => !meta.tables[key]);

  if (unknown.length > 0) {
    throw new TypeError(
      `cacheInvalidationSql: unknown table ${unknown.join(", ")}`,
    );
  }

  return [
    functionSql(),
    ...tables.map((table) => triggersSql(table, options.maxRows ?? 1000)),
  ].join("\n\n");
}
