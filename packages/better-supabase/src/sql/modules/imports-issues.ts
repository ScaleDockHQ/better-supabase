import type { BlockSqlContext } from "../context.ts";

import { fail, serviceGrant, userGrant } from "../shared.ts";

const ISSUES = (schema: string): string => `${schema}.import_run_issues`;

/** The issues table, created with the other import tables. */
export function importIssuesTable(ctx: BlockSqlContext): string {
  const table = ISSUES(ctx.schema);

  return `
create table if not exists ${table} (
  "id" uuid primary key default gen_random_uuid(),
  "run_id" uuid not null,
  "tenant_id" ${ctx.idType} not null,
  "source" text not null,
  "entity" text not null,
  "key" text not null,
  "kind" text not null,
  "code" text not null,
  "message" text not null,
  "created_at" timestamptz not null default now(),
  "resolved_at" timestamptz,
  constraint import_run_issues_kind check ("kind" in ('conflict', 'error', 'warning'))
);
create index if not exists import_run_issues_open_idx
  on ${table} ("tenant_id", "source", "entity", "key")
  where "resolved_at" is null;
create index if not exists import_run_issues_run_idx
  on ${table} ("run_id", "entity");
`;
}

/** Records one issue and clears open issues for a key the run applied. */
export function importIssueHelpers(
  ctx: BlockSqlContext,
  manage: string,
): string {
  const fn = (name: string): string => ctx.fn(name);
  const table = ISSUES(ctx.schema);
  const runs = ctx.table("runs");
  const records = ctx.table("records");
  const r = (column: string): string => ctx.col("runs", column);
  const x = (column: string): string => ctx.col("records", column);

  return `
create or replace function ${fn("import_note_issue")}(run uuid, entity text, key text, kind text, code text, message text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_source text;
begin
  select r.${r("tenant")}, r.${r("source")} into v_tenant, v_source
  from ${runs} r where r.${r("id")} = import_note_issue.run;
  if v_tenant is null or import_note_issue.key is null or import_note_issue.key = '' then
    return;
  end if;
  insert into ${table} ("run_id", "tenant_id", "source", "entity", "key", "kind", "code", "message")
  values (import_note_issue.run, v_tenant, v_source, import_note_issue.entity, import_note_issue.key, import_note_issue.kind, import_note_issue.code, import_note_issue.message);
end;
$$;

create or replace function ${fn("import_note_warnings")}(run uuid, entity text, warnings jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_warning jsonb;
begin
  if jsonb_typeof(import_note_warnings.warnings) is distinct from 'array' then
    return;
  end if;
  for v_warning in select value from jsonb_array_elements(import_note_warnings.warnings) loop
    perform ${fn("import_note_issue")}(
      import_note_warnings.run,
      import_note_warnings.entity,
      coalesce(v_warning ->> 'key', ''),
      'warning',
      coalesce(v_warning ->> 'code', 'IMPORT_WARNING'),
      coalesce(v_warning ->> 'message', '')
    );
  end loop;
end;
$$;

create or replace function ${fn("import_clear_issues")}(run uuid, entity text, key text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_source text;
begin
  select r.${r("tenant")}, r.${r("source")} into v_tenant, v_source
  from ${runs} r where r.${r("id")} = import_clear_issues.run;
  if v_tenant is null then
    return;
  end if;
  update ${table} i set "resolved_at" = now()
  where i."tenant_id" = v_tenant and i."source" = v_source
    and i."entity" = import_clear_issues.entity and i."key" = import_clear_issues.key
    and i."resolved_at" is null;
end;
$$;

create or replace function ${fn("list_import_issues")}(run uuid, entity text default null, row_limit integer default 50, row_offset integer default 0)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_total integer;
  v_rows jsonb;
begin
  select r.${r("tenant")} into v_tenant from ${runs} r where r.${r("id")} = list_import_issues.run;
  if v_tenant is null then
    ${fail("IMPORT_NOT_FOUND", "import not found", "P0002")}
  end if;
  if not (auth.role() = 'service_role' or ${ctx.scope.can("v_tenant", manage)}) then
    ${fail("IMPORT_FORBIDDEN", "not allowed to list import issues")}
  end if;
  select count(*) into v_total from ${table} i
  where i."run_id" = list_import_issues.run
    and (list_import_issues.entity is null or i."entity" = list_import_issues.entity);
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_rows from (
    select i."entity", i."key", i."kind", i."code", i."message", i."created_at", i."resolved_at"
    from ${table} i
    where i."run_id" = list_import_issues.run
      and (list_import_issues.entity is null or i."entity" = list_import_issues.entity)
    order by i."created_at", i."id"
    limit least(greatest(coalesce(list_import_issues.row_limit, 50), 1), 200)
    offset greatest(coalesce(list_import_issues.row_offset, 0), 0)
  ) t;
  return jsonb_build_object(
    'rows', v_rows,
    'total', least(v_total, 10000),
    'capped', v_total > 10000
  );
end;
$$;
${userGrant(`${fn("list_import_issues")}(uuid, text, integer, integer)`)}

-- Counts and the first changed fields of a dry run. The dry run itself writes
-- no subject rows; the diff is what the batch returned.
create or replace function ${fn("list_import_diff")}(run uuid, entity text default null, row_limit integer default 50, row_offset integer default 0)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_counts jsonb;
  v_diff jsonb;
  v_rows jsonb;
begin
  select r.${r("counts")}, r.${r("diff")} into v_counts, v_diff from ${runs} r where r.${r("id")} = list_import_diff.run;
  if v_counts is null then
    ${fail("IMPORT_NOT_FOUND", "import not found", "P0002")}
  end if;
  select coalesce(jsonb_agg(d.value), '[]'::jsonb) into v_rows from (
    select value from jsonb_array_elements(coalesce(v_diff, '[]'::jsonb)) value
    where list_import_diff.entity is null or value ->> 'entity' = list_import_diff.entity
    offset greatest(coalesce(list_import_diff.row_offset, 0), 0)
    limit least(greatest(coalesce(list_import_diff.row_limit, 50), 1), 200)
  ) d;
  return jsonb_build_object(
    'counts', case when list_import_diff.entity is null then v_counts else coalesce(v_counts -> list_import_diff.entity, '{}'::jsonb) end,
    'rows', v_rows
  );
end;
$$;
${userGrant(`${fn("list_import_diff")}(uuid, text, integer, integer)`)}

create or replace function ${fn("resolve_import_conflict")}(tenant ${ctx.idType}, source text, entity text, key text, action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resolved integer;
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("resolve_import_conflict.tenant", manage)}) then
    ${fail("IMPORT_FORBIDDEN", "not allowed to resolve an import conflict")}
  end if;
  if resolve_import_conflict.action = 'keep' then
    update ${records} x set ${x("subjectUpdatedAt")} = now()
    where x.${x("tenant")} = resolve_import_conflict.tenant
      and x.${x("source")} = resolve_import_conflict.source
      and x.${x("entity")} = resolve_import_conflict.entity
      and x.${x("externalKey")} = resolve_import_conflict.key;
  elsif resolve_import_conflict.action = 'overwrite' then
    update ${records} x set ${x("subjectUpdatedAt")} = null, ${x("ownedHash")} = null
    where x.${x("tenant")} = resolve_import_conflict.tenant
      and x.${x("source")} = resolve_import_conflict.source
      and x.${x("entity")} = resolve_import_conflict.entity
      and x.${x("externalKey")} = resolve_import_conflict.key;
  else
    ${fail("IMPORT_ITEM_INVALID", "action must be keep or overwrite", "22023")}
  end if;
  update ${table} i set "resolved_at" = now()
  where i."tenant_id" = resolve_import_conflict.tenant
    and i."source" = resolve_import_conflict.source
    and i."entity" = resolve_import_conflict.entity
    and i."key" = resolve_import_conflict.key
    and i."kind" = 'conflict'
    and i."resolved_at" is null;
  get diagnostics v_resolved = row_count;
  return jsonb_build_object('action', resolve_import_conflict.action, 'resolved', v_resolved);
end;
$$;
${serviceGrant(`${fn("resolve_import_conflict")}(${ctx.idType}, text, text, text, text)`)}
${userGrant(`${fn("resolve_import_conflict")}(${ctx.idType}, text, text, text, text)`)}
`;
}

/** Open issue counts for one run, for the list payload. */
export function importIssueCounts(ctx: BlockSqlContext, runId: string): string {
  const table = ISSUES(ctx.schema);

  return `(
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from ${table} i
    where i."run_id" = ${runId}
  )`;
}
