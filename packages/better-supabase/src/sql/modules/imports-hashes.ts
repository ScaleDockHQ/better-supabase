import type { BlockSqlContext } from "../context.ts";

import { serviceGrant } from "../shared.ts";

/**
 * `reapply_import_records` and `export_import_hashes` (ADR 0439), for the
 * service role: the record map's hashes out, and a way to make the next run
 * rewrite what an older version of the mapping code imported.
 */
export function hashFunctions(ctx: BlockSqlContext, runs: string): string {
  const records = ctx.table("records");
  const x = (column: string): string => ctx.col("records", column);
  const r = (column: string): string => ctx.col("runs", column);
  const fn = (name: string): string => ctx.fn(name);
  const id = ctx.idType;

  return `
-- Clears the content hash of the records of a source (and entity) that a run of
-- another mapper version last wrote, so the next import treats them as changed and
-- rewrites them through their target (a row a user changed since stays as it is, as
-- for any changed hash). Returns how many records it cleared.
create or replace function ${fn("reapply_import_records")}(tenant ${id}, source text, mapper_version text, entity text default null)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_count integer;
begin
  update ${records} x set ${x("contentHash")} = ''
  where x.${x("tenant")} = reapply_import_records.tenant and x.${x("source")} = reapply_import_records.source
    and (reapply_import_records.entity is null or x.${x("entity")} = reapply_import_records.entity)
    and x.${x("contentHash")} <> ''
    and (select r.${r("mapperVersion")} from ${runs} r where r.${r("id")} = x.${x("lastRun")}) is distinct from reapply_import_records.mapper_version;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceGrant(`${fn("reapply_import_records")}(${id}, text, text, text)`)}

-- The record map of a source as { entity, scope, key, role, hash, subjectType,
-- subjectId }, one object per record in key order, so a caller can compare what the
-- source sends with what was imported without reading the rows.
create or replace function ${fn("export_import_hashes")}(tenant ${id}, source text, entity text default null)
returns setof jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('entity', x.${x("entity")}, 'scope', x.${x("scope")}, 'key', x.${x("externalKey")}, 'role', x.${x("role")},
    'hash', x.${x("contentHash")}, 'subjectType', x.${x("subjectType")}, 'subjectId', x.${x("subjectId")})
  from ${records} x
  where x.${x("tenant")} = export_import_hashes.tenant and x.${x("source")} = export_import_hashes.source
    and (export_import_hashes.entity is null or x.${x("entity")} = export_import_hashes.entity)
  order by x.${x("entity")}, x.${x("scope")}, x.${x("externalKey")}, x.${x("role")}
$$;
${serviceGrant(`${fn("export_import_hashes")}(${id}, text, text)`)}
`;
}

/** The contract entries of the two functions. */
export const HASH_CONTRACT = [
  {
    name: "reapply_import_records",
    args: ["{id}", "text", "text", "text"],
    returns: "integer",
  },
  {
    name: "export_import_hashes",
    args: ["{id}", "text", "text"],
    returns: "setof jsonb",
  },
] as const;
