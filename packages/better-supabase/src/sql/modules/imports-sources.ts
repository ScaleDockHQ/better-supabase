import type { BlockSqlContext } from "../context.ts";

import { fail, lockTable, serviceGrant, userGrant } from "../shared.ts";

/** The registry an integration catalog reads, and the runs any client started. */
export function importSourcesSql(ctx: BlockSqlContext): string {
  const fn = (name: string): string => ctx.fn(name);
  const runs = ctx.table("runs");
  const r = (column: string): string => ctx.col("runs", column);

  return `
create table if not exists ${ctx.schema}.import_sources (
  "id" text primary key,
  "label_key" text not null,
  "description_key" text not null,
  "file_types" text[] not null default '{}',
  "entities" text[] not null default '{}',
  "docs_link" text
);
${lockTable(`${ctx.schema}.import_sources`)}

create or replace function ${fn("register_import_source")}(id text, label_key text, description_key text, file_types text[], entities text[], docs_link text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    ${fail("IMPORT_FORBIDDEN", "not allowed to register an import source", "42501")}
  end if;
  insert into ${ctx.schema}.import_sources ("id", "label_key", "description_key", "file_types", "entities", "docs_link")
  values (register_import_source.id, register_import_source.label_key, register_import_source.description_key,
    coalesce(register_import_source.file_types, '{}'), coalesce(register_import_source.entities, '{}'), register_import_source.docs_link)
  on conflict ("id") do update set
    "label_key" = excluded."label_key",
    "description_key" = excluded."description_key",
    "file_types" = excluded."file_types",
    "entities" = excluded."entities",
    "docs_link" = excluded."docs_link";
end;
$$;
${serviceGrant(`${fn("register_import_source")}(text, text, text, text[], text[], text)`)}

create or replace function ${fn("list_import_sources")}()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s."id", 'labelKey', s."label_key", 'descriptionKey', s."description_key",
    'fileTypes', s."file_types", 'entities', s."entities", 'docsLink', s."docs_link"
  ) order by s."id"), '[]'::jsonb)
  from ${ctx.schema}.import_sources s
$$;
${userGrant(`${fn("list_import_sources")}()`)}

-- Every run of the tenant, whoever started it: the CLI, an API or the UI.
create or replace function ${fn("list_import_source_runs")}(tenant ${ctx.idType}, source text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.${r("id")}, 'source', r.${r("source")}, 'status', r.${r("status")}, 'createdAt', r.${r("createdAt")}
  ) order by r.${r("createdAt")} desc), '[]'::jsonb)
  from ${runs} r
  where r.${r("tenant")} = list_import_source_runs.tenant
    and (list_import_source_runs.source is null or r.${r("source")} = list_import_source_runs.source)
$$;
${userGrant(`${fn("list_import_source_runs")}(${ctx.idType}, text)`)}
`;
}
