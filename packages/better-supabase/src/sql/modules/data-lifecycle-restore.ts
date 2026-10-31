import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";

import { SERVICE_CALLER, fail, raise, serviceGrant } from "../shared.ts";

/** The import entity restored rows go through (ADR 0141). */
const RESTORE_ENTITY = "data_lifecycle_row";

export const RESTORE_CONTRACT: readonly BlockSqlContractFunction[] = [
  { name: "data_restore_tables", args: [], returns: "jsonb" },
  {
    name: "restore_data_row",
    args: ["uuid", "jsonb", "text"],
    returns: "jsonb",
  },
];

/** What `imports` calls for a restored row: this module's write function. */
export function restoreTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  return [
    {
      entity: RESTORE_ENTITY,
      subjectType: RESTORE_ENTITY,
      write: own.fn("restore_data_row").replaceAll('"', ""),
    },
  ];
}

/**
 * `data_restore_tables` lists what a restore may write: the tables an
 * organization export reads, with the columns a row may carry, the primary key
 * without the tenant column, and the listed tables each one references. The
 * function `restore_data_row` writes one exported row into the importing
 * organization, through the import record map.
 */
export function restoreSql(ctx: BlockSqlContext): string {
  const fn = (name: string): string => ctx.fn(name);

  return `
-- The tables a restore may write, from the same list an export reads. Each
-- entry: name, tenantColumn, columns (writable and not omitted from exports),
-- keyColumns (the primary key without the tenant column) and references (the
-- listed tables its foreign keys point at).
create or replace function ${fn("data_restore_tables")}()
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
begin
  return (
  with listed as (
    select t.name, t.tbl, t.col, t.omit, to_regclass(t.tbl) as oid
    from ${fn("data_lifecycle_tables")}() t
    where t.subject = 'organization' and t.exported and to_regclass(t.tbl) is not null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'name', l.name,
    'tenantColumn', l.col,
    'columns', (
      select coalesce(jsonb_agg(a.attname order by a.attnum), '[]'::jsonb)
      from pg_catalog.pg_attribute a
      where a.attrelid = l.oid and a.attnum > 0 and not a.attisdropped
        and a.attgenerated = '' and a.attidentity <> 'a'
        and a.attname <> all (coalesce(l.omit, '{}'))
    ),
    'keyColumns', (
      select coalesce(jsonb_agg(a.attname order by k.ord), '[]'::jsonb)
      from pg_catalog.pg_constraint c
      cross join lateral unnest(c.conkey) with ordinality as k(attnum, ord)
      join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
      where c.conrelid = l.oid and c.contype = 'p' and a.attname <> l.col
    ),
    'references', (
      select coalesce(jsonb_agg(distinct o.name), '[]'::jsonb)
      from pg_catalog.pg_constraint c
      join listed o on o.oid = c.confrelid
      where c.conrelid = l.oid and c.contype = 'f' and c.confrelid <> c.conrelid
    )
  ) order by l.name), '[]'::jsonb)
  from listed l
  );
end
$$;
${serviceGrant(`${fn("data_restore_tables")}()`)}

-- The write function of the data_lifecycle_row import target: item.data is
-- { table, row }. The row goes into the importing organization (its tenant
-- column is replaced) and updates the row with the same primary key, unless
-- that row belongs to another organization.
create or replace function ${fn("restore_data_row")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_name text := item #>> '{data,table}';
  v_row jsonb := item #> '{data,row}';
  v_tenant text := item ->> 'tenant';
  v_table jsonb;
  v_tbl text;
  v_tenant_col text;
  v_columns text[];
  v_keys text[];
  v_given text[];
  v_cols text[];
  v_pk text[];
  v_sets text[];
  v_sql text;
  v_count bigint;
begin
  if not (${SERVICE_CALLER}) then
    ${fail("DATA_RESTORE_FORBIDDEN", "Only the service role restores data")}
  end if;
  if v_name is null or jsonb_typeof(v_row) is distinct from 'object' then
    ${fail("DATA_RESTORE_ROW_INVALID", "an item needs data.table and a data.row object", "22023")}
  end if;
  select x.value into v_table
  from jsonb_array_elements(${fn("data_restore_tables")}()) x
  where x.value ->> 'name' = v_name;
  if v_table is null then
    ${raise("The restore has no table %", "22023", "DATA_RESTORE_TABLE", "v_name")}
  end if;
  select t.tbl into v_tbl from ${fn("data_lifecycle_tables")}() t
  where t.subject = 'organization' and t.name = v_name and t.exported;
  v_tenant_col := v_table ->> 'tenantColumn';
  select coalesce(array_agg(c.value), '{}') into v_columns from jsonb_array_elements_text(v_table -> 'columns') c;
  select coalesce(array_agg(c.value), '{}') into v_keys from jsonb_array_elements_text(v_table -> 'keyColumns') c;
  select coalesce(array_agg(k.key), '{}') into v_given from jsonb_object_keys(v_row) k(key);
  if exists (select 1 from unnest(v_given) g where g <> all (v_columns)) then
    ${raise("The table % has no column %", "22023", "DATA_RESTORE_COLUMN", "v_name", "(select g from unnest(v_given) g where g <> all (v_columns) limit 1)")}
  end if;

  select array_agg(distinct c) into v_cols from unnest(v_given || array[v_tenant_col]) c;
  v_row := v_row || pg_catalog.jsonb_build_object(v_tenant_col, v_tenant);
  v_pk := v_keys || case when v_tenant_col = any (
    select a.attname from pg_catalog.pg_constraint c
    cross join lateral unnest(c.conkey) k(attnum)
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
    where c.conrelid = to_regclass(v_tbl) and c.contype = 'p'
  ) then array[v_tenant_col] else '{}'::text[] end;

  v_sql := pg_catalog.format(
    'insert into %s as t (%s) select %s from jsonb_populate_record(null::%s, $1) r',
    v_tbl,
    (select string_agg(pg_catalog.format('%I', c), ', ') from unnest(v_cols) c),
    (select string_agg(pg_catalog.format('r.%I', c), ', ') from unnest(v_cols) c),
    v_tbl
  );
  if cardinality(v_pk) > 0 then
    select array_agg(pg_catalog.format('%I = excluded.%I', c, c)) into v_sets
    from unnest(v_cols) c where c <> all (v_pk);
    v_sql := v_sql || pg_catalog.format(
      ' on conflict ' || '(%s) do update set %s where t.%I::text = excluded.%I::text',
      (select string_agg(pg_catalog.format('%I', c), ', ') from unnest(v_pk) c),
      coalesce(array_to_string(v_sets, ', '), pg_catalog.format('%I = excluded.%I', v_pk[1], v_pk[1])),
      v_tenant_col, v_tenant_col
    );
  end if;
  execute v_sql using v_row;
  get diagnostics v_count = row_count;
  if v_count = 0 then
    ${raise("The row of % belongs to another organization", "23505", "DATA_RESTORE_ROW_CONFLICT", "v_name")}
  end if;
  return pg_catalog.jsonb_build_object('subjectId', item ->> 'key', 'subjectType', '${RESTORE_ENTITY}');
end;
$$;
${serviceGrant(`${fn("restore_data_row")}(uuid, jsonb, text)`)}
`;
}
