import type { ModuleIdType } from "../context.ts";

/** A text expression as the id type, or null when it doesn't parse as one. */
export function castId(value: string, idType: ModuleIdType): string {
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

/** Reads the row's audit settings: the trigger argument, or the legacy `audited_tables` row. */
export function entrySql(): string {
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
    select coalesce(a.ignore, '{}') as ignore, coalesce(a.key_columns, '{id}') as key_columns,
      coalesce(a.redact, '{}') as redact, a.category, a.event_prefix, a.target_type, a.tenant_column,
      a.label_column, null::jsonb as tenant_path, null::text as tenant_function
    into entry
    from (select 1) one
    left join better_supabase.audited_tables a on a.target = tg_relid::regclass;
  end if;`;
}

/** Resolves the tenant of a row without a tenant column, through its `tenant_path` and `tenant_function`. */
export function tenantFallbackSql(idType: ModuleIdType): string {
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
