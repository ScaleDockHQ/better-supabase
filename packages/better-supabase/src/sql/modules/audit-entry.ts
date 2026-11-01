import type { BlockSqlContext, BlockSqlIdType } from "../context.ts";

import { registryColumn } from "./audit-register.ts";

/** A text expression as the id type, or null when it doesn't parse as one. */
export function castId(value: string, idType: BlockSqlIdType): string {
  switch (idType) {
    case "uuid": {
      return `case when ${value} ~* '^[0-9a-f-]{36}$' then (${value})::uuid end`;
    }

    case "bigint": {
      return `case when ${value} ~ '^-?[0-9]{1,18}$' then (${value})::bigint end`;
    }

    case "integer": {
      return `case when ${value} ~ '^-?[0-9]{1,9}$' then (${value})::integer end`;
    }

    case "text": {
      return value;
    }

    default: {
      const unknown: never = idType;

      return unknown;
    }
  }
}

/**
 * Reads the row's audit settings: the trigger argument, or the legacy
 * `audited_tables` row.
 */
export function entrySql(ctx: BlockSqlContext): string {
  const a = (logical: string, missing: string): string =>
    registryColumn(ctx, "a", logical, missing);

  return `  if tg_nargs > 0 then
    settings := tg_argv[0]::jsonb;
    select array(select jsonb_array_elements_text(coalesce(settings -> 'ignore', '[]'))) as ignore,
      coalesce(
        nullif(array(select jsonb_array_elements_text(coalesce(settings -> 'key_columns', '[]'))), '{}'),
        (select array_agg(c.attname::text order by k.ord)
         from pg_catalog.pg_index i
         cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
         join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
         where i.indrelid = tg_relid and i.indisprimary),
        '{id}'
      ) as key_columns,
      array(select jsonb_array_elements_text(coalesce(settings -> 'redact', '[]'))) as redact,
      settings ->> 'category' as category, settings ->> 'event_prefix' as event_prefix,
      settings ->> 'target_type' as target_type, settings ->> 'tenant_column' as tenant_column,
      settings ->> 'label_column' as label_column,
      settings -> 'tenant_path' as tenant_path, settings ->> 'tenant_function' as tenant_function
    into entry;
  else
    select coalesce(${a("ignore", "null")}, '{}') as ignore, coalesce(${a("keyColumns", "null")}, '{id}') as key_columns,
      coalesce(${a("redact", "null")}, '{}') as redact, ${a("category", "null::text")} as category,
      ${a("eventPrefix", "null::text")} as event_prefix, ${a("targetType", "null::text")} as target_type,
      ${a("tenantColumn", "null::text")} as tenant_column, ${a("labelColumn", "null::text")} as label_column,
      null::jsonb as tenant_path, null::text as tenant_function
    into entry
    from (select 1) one
    left join ${ctx.table("registry")} a on a.${ctx.col("registry", "target")} = tg_relid::regclass;
  end if;
${recordedSkipSql()}`;
}

/**
 * Resolves the tenant of a row without a tenant column, through its
 * `tenant_path` and `tenant_function`.
 */
export function tenantFallbackSql(idType: BlockSqlIdType): string {
  const cast = castId("path_value", idType);

  return `  -- A child row without a tenant column: follow the foreign-key path
  -- registered through tenant_path, then the tenant function.
  if row_tenant is null and entry.tenant_path is not null then
    path_value := row_data ->> (entry.tenant_path ->> 'column');
    for path_step in select * from jsonb_array_elements(entry.tenant_path -> 'steps') loop
      exit when path_value is null;
      execute format('select %I::text from %s where %I::text = $1 limit 1',
        path_step ->> 'read', path_step ->> 'table', path_step ->> 'ref')
        into path_value using path_value;
    end loop;
    row_tenant := ${cast};
  end if;
  if row_tenant is null and entry.tenant_function is not null then
    execute format('select %s($1)::text', (entry.tenant_function::regprocedure)::oid::regproc) into path_value using row_data;
    row_tenant := ${cast};
  end if;`;
}

/**
 * In the row trigger: skips a row `audit_event` already recorded
 * (`bsb.recorded`).
 */
export function recordedSkipSql(): string {
  return `  if position(E'\\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\\n' in coalesce(current_setting('bsb.recorded', true), '') || E'\\n') > 0 then
    return null;
  end if;`;
}

/** In `audit_event`: marks the record so the row trigger skips it. */
export function recordedMarkSql(): string {
  return `  if audit_event.target_type is not null and audit_event.record_id is not null then
    perform pg_catalog.set_config('bsb.recorded', coalesce(pg_catalog.current_setting('bsb.recorded', true), '') || E'\\n' || audit_event.target_type || ':' || audit_event.record_id, true);
  end if;`;
}
