-- ==== alone: schema supabase/schemas/900_better_supabase_064_imports.sql
-- better-supabase module: imports
-- @bsb-block imports@2 managed
-- @bsb-hash sha256:9e00efde4a38abbb47d616d7bcf16af74d5967aa221e2bac660996df2624392a
-- Import runs and the external record map. import_upsert_batch writes items through the targets blocks and the app register, skips equal content, reports rows a user changed since the last import and marks missing keys on full runs. The dry run, parsing and mapping live in TypeScript.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."import_runs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "source" text not null,
  "status" text not null default 'pending',
  "mapping" jsonb not null default '{}'::jsonb,
  "counts" jsonb not null default '{}'::jsonb,
  "errors" jsonb not null default '[]'::jsonb,
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."import_runs" add column "dry_run" boolean not null default false;
alter table "better_supabase"."import_runs" add column "diff" jsonb not null default '[]'::jsonb;
alter table "better_supabase"."import_runs" add column "full" boolean not null default false;
alter table "better_supabase"."import_runs" add column "input_checksum" text;
alter table "better_supabase"."import_runs" add column "correlation_id" text;
alter table "better_supabase"."import_runs" add column "mapper_version" text;
alter table "better_supabase"."import_runs" add column "scope_aliases" jsonb not null default '[]'::jsonb;
alter table "better_supabase"."import_runs" add column "started_at" timestamptz;
alter table "better_supabase"."import_runs" add column "finished_at" timestamptz;
alter table "better_supabase"."import_runs" add column "plan" jsonb;
alter table "better_supabase"."import_runs" add column "outcome" text;
alter table "better_supabase"."import_runs" add column "lease_until" timestamptz;
alter table "better_supabase"."import_runs" add column "heartbeat_at" timestamptz;
alter table "better_supabase"."import_runs" add constraint "bsb_import_runs_status"
  check ("status" in ('pending', 'running', 'completed', 'failed', 'canceled'));
alter table "better_supabase"."import_runs" enable row level security;
revoke all on "better_supabase"."import_runs" from public, anon, authenticated;
grant select on "better_supabase"."import_runs" to authenticated;
grant all on "better_supabase"."import_runs" to service_role;
create index "import_runs_tenant_idx" on "better_supabase"."import_runs" ("tenant_id");
-- One pending or running run per organization and source.
create unique index "import_runs_active_idx" on "better_supabase"."import_runs" ("tenant_id", "source") where "status" in ('pending', 'running');

create table "better_supabase"."import_records" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "source" text not null,
  "scope" text not null default '',
  "entity" text not null,
  "external_key" text not null,
  "role" text not null default 'primary',
  "subject_type" text not null,
  "subject_id" text not null,
  "content_hash" text not null,
  "first_run_id" uuid not null,
  "last_run_id" uuid not null,
  "subject_imported_updated_at" timestamptz,
  "source_updated_at" timestamptz,
  "owned_hash" text,
  "went_missing_at" timestamptz,
  constraint "import_records_key" unique ("tenant_id", "source", "scope", "entity", "external_key", "role")
);
create index "import_records_subject_idx" on "better_supabase"."import_records" ("tenant_id", "subject_type", "subject_id");
alter table "better_supabase"."import_records" enable row level security;
revoke all on "better_supabase"."import_records" from public, anon, authenticated;
grant select on "better_supabase"."import_records" to authenticated;
grant all on "better_supabase"."import_records" to service_role;
create table "better_supabase".import_refs (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null,
  "key" text not null,
  "payload" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now(),
  constraint import_refs_key unique ("tenant_id", "kind", "key")
);

create table "better_supabase"."import_chunks" (
  "run_id" uuid not null references "better_supabase"."import_runs" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "entity" text not null,
  "chunk" integer not null,
  "items" jsonb not null,
  "status" text not null default 'pending',
  "result" jsonb,
  "claimed_at" timestamptz,
  "done_at" timestamptz,
  "created_at" timestamptz not null default now(),
  primary key ("run_id", "entity", "chunk")
);
alter table "better_supabase"."import_chunks" add constraint "bsb_import_chunks_status"
  check ("status" in ('pending', 'claimed', 'done'));
alter table "better_supabase"."import_chunks" enable row level security;
revoke all on "better_supabase"."import_chunks" from public, anon, authenticated;
grant all on "better_supabase"."import_chunks" to service_role;
create index "import_chunks_tenant_idx" on "better_supabase"."import_chunks" ("tenant_id");


create table "better_supabase".import_run_issues (
  "id" uuid primary key default gen_random_uuid(),
  "run_id" uuid not null,
  "tenant_id" uuid not null,
  "source" text not null,
  "entity" text not null,
  "key" text not null,
  "kind" text not null,
  "code" text not null,
  "message" text not null,
  "created_at" timestamptz not null default now(),
  "resolved_at" timestamptz,
  constraint bsb_import_run_issues_kind check ("kind" in ('conflict', 'error', 'warning'))
);
create index import_run_issues_open_idx
  on "better_supabase".import_run_issues ("tenant_id", "source", "entity", "key")
  where "resolved_at" is null;
create index import_run_issues_run_idx
  on "better_supabase".import_run_issues ("run_id", "entity");

create or replace function "better_supabase"."start_import_run"(tenant uuid, source text, options jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_options jsonb := coalesce(start_import_run.options, '{}'::jsonb);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', start_import_run.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if start_import_run.source is null or start_import_run.source = '' then
    raise exception 'an import run needs a source' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(coalesce(v_options -> 'scopeAliases', '[]'::jsonb)) <> 'array' then
    raise exception 'scopeAliases must be an array of { scope, of, entities }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    insert into "better_supabase"."import_runs" as r ("tenant_id", "source", "mapping", "dry_run", "full", "input_checksum", "correlation_id", "mapper_version", "scope_aliases", "plan", "lease_until", "created_by")
    values (
      start_import_run.tenant,
      start_import_run.source,
      coalesce(v_options -> 'mapping', '{}'::jsonb),
      coalesce((v_options ->> 'dryRun')::boolean, false),
      coalesce((v_options ->> 'full')::boolean, false),
      v_options ->> 'inputChecksum',
      v_options ->> 'correlationId',
      nullif(v_options ->> 'mapperVersion', ''),
      coalesce(v_options -> 'scopeAliases', '[]'::jsonb),
      v_options -> 'plan',
      now() + interval '30 seconds',
      auth.uid()
    )
    returning r."id" into v_id;
  exception when unique_violation then
    raise exception 'an import of this source is already pending or running' using errcode = '55P03', hint = 'IMPORT_RUN_ACTIVE';
  end;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."start_import_run"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."start_import_run"(uuid, text, jsonb) to authenticated, service_role;

-- The first release's entry point: a run without options.
create or replace function "better_supabase"."start_import"(tenant uuid, source text, mapping jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select "better_supabase"."start_import_run"(start_import.tenant, start_import.source, jsonb_build_object('mapping', coalesce(start_import.mapping, '{}'::jsonb)));
$$;
revoke execute on function "better_supabase"."start_import"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."start_import"(uuid, text, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_import_run"(id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = get_import_run.id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_run."tenant_id", 'imports.manage'), false)) then
    raise exception 'not allowed to read this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."tenant_id", 'source', v_run."source", 'status', v_run."status", 'outcome', v_run."outcome", 'plan', v_run."plan", 'mapping', v_run."mapping", 'counts', v_run."counts", 'errors', v_run."errors", 'dryRun', v_run."dry_run", 'full', v_run."full", 'inputChecksum', v_run."input_checksum", 'correlationId', v_run."correlation_id", 'mapperVersion', v_run."mapper_version", 'scopeAliases', v_run."scope_aliases", 'leaseUntil', v_run."lease_until", 'heartbeatAt', v_run."heartbeat_at", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'startedAt', v_run."started_at", 'finishedAt', v_run."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "better_supabase".import_run_issues i
    where i."run_id" = v_run."id"
  ));
end;
$$;
revoke execute on function "better_supabase"."get_import_run"(uuid) from public, anon;
grant execute on function "better_supabase"."get_import_run"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_import_runs"(tenant uuid, source text default null, status text default null, row_limit integer default 50)
returns setof jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_import_runs.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list imports' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  return query
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'source', r."source", 'status', r."status", 'outcome', r."outcome", 'plan', r."plan", 'mapping', r."mapping", 'counts', r."counts", 'errors', r."errors", 'dryRun', r."dry_run", 'full', r."full", 'inputChecksum', r."input_checksum", 'correlationId', r."correlation_id", 'mapperVersion', r."mapper_version", 'scopeAliases', r."scope_aliases", 'leaseUntil', r."lease_until", 'heartbeatAt', r."heartbeat_at", 'createdBy', r."created_by", 'createdAt', r."created_at", 'startedAt', r."started_at", 'finishedAt', r."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "better_supabase".import_run_issues i
    where i."run_id" = r."id"
  ))
    from "better_supabase"."import_runs" r
    where r."tenant_id" = list_import_runs.tenant
      and (list_import_runs.source is null or r."source" = list_import_runs.source)
      and (list_import_runs.status is null or r."status" = list_import_runs.status)
    order by r."created_at" desc, r."id" desc
    limit least(greatest(coalesce(list_import_runs.row_limit, 50), 1), 200);
end;
$$;
revoke execute on function "better_supabase"."list_import_runs"(uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_import_runs"(uuid, text, text, integer) to authenticated, service_role;

create or replace function "better_supabase"."cancel_import_run"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_run "better_supabase"."import_runs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_run from "better_supabase"."import_runs" r where r."id" = cancel_import_run.id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_run."tenant_id", 'imports.manage'), false)) then
    raise exception 'not allowed to cancel this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if v_run."status" not in ('pending', 'running') then
    raise exception 'this import already finished' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  update "better_supabase"."import_runs" r set "status" = 'canceled', "finished_at" = now()
  where r."id" = cancel_import_run.id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_import_run"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_import_run"(uuid) to authenticated, service_role;

-- The run moves from pending to running before the first batch, so a run
-- that dies mid-way is visible as running rather than pending.
create or replace function "better_supabase"."mark_import_running"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  update "better_supabase"."import_runs" set "status" = 'running', "started_at" = now()
  where "id" = mark_import_running.id and "status" = 'pending';
  if not found then
    raise exception 'no pending import with this id' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."mark_import_running"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_import_running"(uuid) to service_role;

-- Closes a run whose rows the caller wrote itself (`defineImport` without a
-- target); `finish_import_run` closes a run that used `import_upsert_batch`.
create or replace function "better_supabase"."finish_import"(id uuid, status text, count integer, error text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_source text;
begin
  update "better_supabase"."import_runs" set "status" = finish_import.status,
    "finished_at" = now(),
    "counts" = case when finish_import.status = 'completed' then jsonb_build_object("source", jsonb_build_object('inserted', finish_import.count, 'updated', 0, 'unchanged', 0, 'conflicted', 0, 'missing', 0)) else "counts" end,
    "errors" = case when finish_import.error is null then "errors" else "errors" || jsonb_build_array(jsonb_build_object('entity', "source", 'key', null, 'code', 'IMPORT_ITEM_INVALID', 'message', finish_import.error)) end
  where "id" = finish_import.id
  returning "tenant_id", "source" into v_tenant, v_source;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if finish_import.status = 'failed' then
    null;
  else
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."finish_import"(uuid, text, integer, text) from public, anon, authenticated;
grant execute on function "better_supabase"."finish_import"(uuid, text, integer, text) to service_role;

create or replace function "better_supabase"."import_note_issue"(run uuid, entity text, key text, kind text, code text, message text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_source text;
begin
  select r."tenant_id", r."source" into v_tenant, v_source
  from "better_supabase"."import_runs" r where r."id" = import_note_issue.run;
  if v_tenant is null or import_note_issue.key is null or import_note_issue.key = '' then
    return;
  end if;
  insert into "better_supabase".import_run_issues ("run_id", "tenant_id", "source", "entity", "key", "kind", "code", "message")
  values (import_note_issue.run, v_tenant, v_source, import_note_issue.entity, import_note_issue.key, import_note_issue.kind, import_note_issue.code, import_note_issue.message);
end;
$$;

create or replace function "better_supabase"."import_note_warnings"(run uuid, entity text, warnings jsonb)
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
    perform "better_supabase"."import_note_issue"(
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

create or replace function "better_supabase"."import_clear_issues"(run uuid, entity text, key text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_source text;
begin
  select r."tenant_id", r."source" into v_tenant, v_source
  from "better_supabase"."import_runs" r where r."id" = import_clear_issues.run;
  if v_tenant is null then
    return;
  end if;
  update "better_supabase".import_run_issues i set "resolved_at" = now()
  where i."tenant_id" = v_tenant and i."source" = v_source
    and i."entity" = import_clear_issues.entity and i."key" = import_clear_issues.key
    and i."resolved_at" is null;
end;
$$;

create or replace function "better_supabase"."list_import_issues"(run uuid, entity text default null, row_limit integer default 50, row_offset integer default 0)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_total integer;
  v_rows jsonb;
begin
  select r."tenant_id" into v_tenant from "better_supabase"."import_runs" r where r."id" = list_import_issues.run;
  if v_tenant is null then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list import issues' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  select count(*) into v_total from "better_supabase".import_run_issues i
  where i."run_id" = list_import_issues.run
    and (list_import_issues.entity is null or i."entity" = list_import_issues.entity);
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_rows from (
    select i."entity", i."key", i."kind", i."code", i."message", i."created_at", i."resolved_at"
    from "better_supabase".import_run_issues i
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
revoke execute on function "better_supabase"."list_import_issues"(uuid, text, integer, integer) from public, anon;
grant execute on function "better_supabase"."list_import_issues"(uuid, text, integer, integer) to authenticated, service_role;

-- Counts and the first changed fields of a dry run. The dry run itself writes
-- no subject rows; the diff is what the batch returned.
create or replace function "better_supabase"."list_import_diff"(run uuid, entity text default null, row_limit integer default 50, row_offset integer default 0)
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
  select r."counts", r."diff" into v_counts, v_diff from "better_supabase"."import_runs" r where r."id" = list_import_diff.run;
  if v_counts is null then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
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
revoke execute on function "better_supabase"."list_import_diff"(uuid, text, integer, integer) from public, anon;
grant execute on function "better_supabase"."list_import_diff"(uuid, text, integer, integer) to authenticated, service_role;

create or replace function "better_supabase"."resolve_import_conflict"(tenant uuid, source text, entity text, key text, action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resolved integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', resolve_import_conflict.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to resolve an import conflict' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if resolve_import_conflict.action = 'keep' then
    update "better_supabase"."import_records" x set "subject_imported_updated_at" = now()
    where x."tenant_id" = resolve_import_conflict.tenant
      and x."source" = resolve_import_conflict.source
      and x."entity" = resolve_import_conflict.entity
      and x."external_key" = resolve_import_conflict.key;
  elsif resolve_import_conflict.action = 'overwrite' then
    update "better_supabase"."import_records" x set "subject_imported_updated_at" = null, "owned_hash" = null
    where x."tenant_id" = resolve_import_conflict.tenant
      and x."source" = resolve_import_conflict.source
      and x."entity" = resolve_import_conflict.entity
      and x."external_key" = resolve_import_conflict.key;
  else
    raise exception 'action must be keep or overwrite' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  update "better_supabase".import_run_issues i set "resolved_at" = now()
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
revoke execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) to service_role;
revoke execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."import_integrity"(tenant uuid, source text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_checks jsonb := '[]'::jsonb;
  v_name text;
  v_severity text;
  v_count integer;
  v_ids jsonb;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', import_integrity.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to check this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  for v_name, v_severity, v_count, v_ids in
    select 'duplicate_keys', 'error', count(*)::integer, coalesce(jsonb_agg(sample), '[]'::jsonb) from (
      select min(d."id"::text) as sample from "better_supabase"."import_records" d
      where d."tenant_id" = import_integrity.tenant
        and (import_integrity.source is null or d."source" = import_integrity.source)
      group by d."entity", d."external_key"
      having count(distinct d."subject_id") > 1
    ) q
  loop
    v_checks := v_checks || jsonb_build_array(jsonb_build_object(
      'name', v_name, 'severity', v_severity, 'count', v_count, 'ids', coalesce(v_ids, '[]'::jsonb)));
  end loop;
  return jsonb_build_object('checks', v_checks);
end;
$$;
revoke execute on function "better_supabase"."import_integrity"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_integrity"(uuid, text) to service_role;
revoke execute on function "better_supabase"."import_integrity"(uuid, text) from public, anon;
grant execute on function "better_supabase"."import_integrity"(uuid, text) to authenticated, service_role;

create table "better_supabase".import_sources (
  "id" text primary key,
  "label_key" text not null,
  "description_key" text not null,
  "file_types" text[] not null default '{}',
  "entities" text[] not null default '{}',
  "docs_link" text
);

create or replace function "better_supabase"."register_import_source"(id text, label_key text, description_key text, file_types text[], entities text[], docs_link text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'not allowed to register an import source' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  insert into "better_supabase".import_sources ("id", "label_key", "description_key", "file_types", "entities", "docs_link")
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
revoke execute on function "better_supabase"."register_import_source"(text, text, text, text[], text[], text) from public, anon, authenticated;
grant execute on function "better_supabase"."register_import_source"(text, text, text, text[], text[], text) to service_role;

create or replace function "better_supabase"."list_import_sources"()
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
  from "better_supabase".import_sources s
$$;
revoke execute on function "better_supabase"."list_import_sources"() from public, anon;
grant execute on function "better_supabase"."list_import_sources"() to authenticated, service_role;

-- Every run of the tenant, whoever started it: the CLI, an API or the UI.
create or replace function "better_supabase"."list_import_source_runs"(tenant uuid, source text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r."id", 'source', r."source", 'status', r."status", 'createdAt', r."created_at"
  ) order by r."created_at" desc), '[]'::jsonb)
  from "better_supabase"."import_runs" r
  where r."tenant_id" = list_import_source_runs.tenant
    and (list_import_source_runs.source is null or r."source" = list_import_source_runs.source)
$$;
revoke execute on function "better_supabase"."list_import_source_runs"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_import_source_runs"(uuid, text) to authenticated, service_role;


-- Writes the items of one entity: an unknown key inserts, an equal hash is
-- unchanged and writes nothing, a changed hash updates unless the row changed
-- after the last import (conflicted). Returns the counts and the item errors.
create or replace function "better_supabase"."import_apply_batch"(run uuid, entity text, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := import_apply_batch.run;
  v_entity text := import_apply_batch.entity;
  v_items jsonb := import_apply_batch.items;
  v_run "better_supabase"."import_runs";
  v_item jsonb;
  v_call jsonb;
  v_key text;
  v_scope text;
  v_data jsonb;
  v_hash text;
  v_source_at timestamptz;
  v_diff jsonb := '[]'::jsonb;
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_owned text;
  v_natural text;
  v_ref_map jsonb := '{}'::jsonb;
  v_resolved jsonb := '{}'::jsonb;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_issue text;
  v_message text;
  v_hint text;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if v_entity <> all (array[]::text[]) then
    raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    raise exception 'items must be an array of { key, scope, data, refs }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  v_ref_map := '{}'::jsonb;

  for v_item in
    select e.value from jsonb_array_elements(v_items) e
    order by e.value #>> '{data,orderBy}', e.value #>> '{data,readAt}', e.value ->> 'key'
  loop
    v_issue := null;
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      perform "better_supabase"."import_note_issue"(v_run_id, v_entity, coalesce(v_key, ''), 'error', 'IMPORT_ITEM_INVALID', 'an item needs a key and a data object');
      continue;
    end if;

    

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;
      v_source_at := nullif(v_item ->> 'sourceUpdatedAt', '')::timestamptz;
      if v_found and v_source_at is not null and v_rec."source_updated_at" is not null and v_source_at <= v_rec."source_updated_at" then
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');
      end if;

      if v_done then
        null;
      elsif not v_found then
        v_natural := null;
        null;
        if v_natural is not null then
          v_found := true;
          v_rec."subject_id" := v_natural;
          v_rec."content_hash" := '';
        end if;
      end if;

      if v_done then
        null;
      elsif not v_found then
        -- A cloned administration reuses the subjects of the scope it aliases
        -- when the content is equal there.
        for v_other in
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = v_scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? v_entity)
        loop
          if exists (
            select 1 from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary' and x."content_hash" = v_hash
          ) then
            insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_imported_updated_at"
            from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key
            on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do nothing;
            v_unchanged := v_unchanged + 1;
            v_done := true;
            exit;
          end if;
        end loop;
      elsif v_rec."content_hash" = v_hash then
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."went_missing_at" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        v_owned := null;
        null;
        null;
        if v_owned is not null and v_rec."owned_hash" is not null and v_owned is distinct from v_rec."owned_hash" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_issue := 'conflict';
          v_done := true;
        elsif v_owned is not null and v_current is not null and v_rec."subject_imported_updated_at" is not null and v_current > v_rec."subject_imported_updated_at" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "subject_imported_updated_at" = v_current, "owned_hash" = v_owned
          where x."id" = v_rec."id";
        elsif v_owned is null and v_current is not null and v_rec."subject_imported_updated_at" is not null and v_current > v_rec."subject_imported_updated_at" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_issue := 'conflict';
          v_done := true;
        end if;
      end if;

      if v_issue = 'conflict' then
        perform "better_supabase"."import_note_issue"(v_run_id, v_entity, v_key, 'conflict', 'IMPORT_CONFLICT', 'the subject changed after the last import');
      else
        perform "better_supabase"."import_clear_issues"(v_run_id, v_entity, v_key);
      end if;

      if not v_done and v_run."dry_run" and jsonb_typeof(v_item -> 'previous') = 'object' and jsonb_array_length(v_diff) < 20 then
        v_diff := v_diff || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'fields', (
          select coalesce(jsonb_agg(jsonb_build_object('field', k, 'old', v_item -> 'previous' -> k, 'new', v_data -> k)), '[]'::jsonb)
          from jsonb_object_keys(v_data) k where (v_data -> k) is distinct from (v_item -> 'previous' -> k))));
      end if;
      if not v_done then
        v_subject_id := case when v_found then v_rec."subject_id" else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run."tenant_id", 'scope', v_scope);
        
        raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';

          v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
  if not exists (
    select 1 from jsonb_array_elements(v_subjects) s
    where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
  ) then
    raise exception 'the import target returned no primary subject' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
    if jsonb_typeof(v_subject -> 'warnings') = 'array' then
      v_warnings := v_warnings || (select coalesce(jsonb_agg(w.value || jsonb_build_object('entity', v_entity, 'key', v_key)), '[]'::jsonb) from jsonb_array_elements(v_subject -> 'warnings') w);
    end if;
    insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at", "source_updated_at", "went_missing_at")
    values (
      v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
      coalesce(v_subject ->> 'role', 'primary'),
      coalesce(v_subject ->> 'subjectType', v_subject_type),
      v_subject ->> 'subjectId',
      v_hash, v_run_id, v_run_id,
      coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
      v_source_at,
      null
    )
    on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
      "subject_type" = excluded."subject_type",
      "subject_id" = excluded."subject_id",
      "content_hash" = excluded."content_hash",
      "last_run_id" = excluded."last_run_id",
      "subject_imported_updated_at" = excluded."subject_imported_updated_at",
      "source_updated_at" = coalesce(excluded."source_updated_at", "better_supabase"."import_records"."source_updated_at"),
      "went_missing_at" = null;
  end loop;

  if v_found then
    v_updated := v_updated + 1;
  else
    v_inserted := v_inserted + 1;
  end if;
  
      end if;
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
      perform "better_supabase"."import_note_issue"(v_run_id, v_entity, coalesce(v_key, ''), 'error', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), v_message);
    end;
  end loop;

  

  perform "better_supabase"."import_note_warnings"(v_run_id, v_entity, v_warnings);

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors, 'diff', v_diff) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
end;
$$;
revoke execute on function "better_supabase"."import_apply_batch"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_apply_batch"(uuid, text, jsonb) to service_role;

-- Turns import mode on for the rest of the transaction (ADR 0141): the outbox
-- applies the imports.events policy, the audit log tags entries as
-- integration with the correlation id import:<run> (imports.audit decides rows
-- or one summary per entity) and ctx.importing() guards skip their side
-- effects. The setting is transaction-local and better_supabase.import_run()
-- only reports it to the service role, so no user session can turn it on.
create or replace function "better_supabase"."begin_import_session"(run uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_status text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role can begin an import session' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  select r."status"::text into v_status from "better_supabase"."import_runs" r where r."id" = begin_import_session.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_status <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  perform set_config('better_supabase.import_run', begin_import_session.run::text, true);
  perform set_config('better_supabase.correlation_id', 'import:' || begin_import_session.run::text, true);
  perform set_config('better_supabase.import_events', '{}', true);
  perform set_config('better_supabase.import_audit', 'rows', true);
  return begin_import_session.run;
end;
$$;
revoke execute on function "better_supabase"."begin_import_session"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."begin_import_session"(uuid) to service_role;

-- The single write path of an import (service role). It begins the import
-- session for its writes and restores the caller's settings afterwards. A dry
-- run writes inside a subtransaction it rolls back, then keeps the counts.
create or replace function "better_supabase"."import_upsert_batch"(run uuid, entity text, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := import_upsert_batch.run;
  v_entity text := import_upsert_batch.entity;
  v_run "better_supabase"."import_runs";
  v_result jsonb;
  v_name text;
  v_previous jsonb := '{}'::jsonb;
begin
  -- No row lock here: two batches of one run write at the same time, and the
  -- counts update at the end is the only statement that locks the run row.
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  if coalesce((v_run."plan" ->> 'unordered')::boolean, false) is distinct from true
    and jsonb_typeof(v_run."plan" -> 'waves') = 'array'
    and exists (
      select 1 from jsonb_array_elements(v_run."plan" -> 'waves') with ordinality as w(wave, n)
      where w.wave ? v_entity and exists (
        select 1 from jsonb_array_elements(v_run."plan" -> 'waves') with ordinality as earlier(wave, n)
        cross join lateral jsonb_array_elements_text(earlier.wave) dep(entity)
        join "better_supabase"."import_chunks" c on c."run_id" = v_run_id
          and c."entity" = dep.entity and c."status" <> 'done'
        where earlier.n < w.n)) then
    raise exception 'an earlier import wave still has open chunks' using errcode = '55000', hint = 'IMPORT_DEPENDENCY_OPEN';
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    v_previous := v_previous || jsonb_build_object(v_name, coalesce(current_setting(v_name, true), ''));
  end loop;
  perform "better_supabase"."begin_import_session"(v_run_id);

  if v_run."dry_run" then
    begin
      v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
      raise exception 'dry run' using errcode = 'BSDRY';
    exception when sqlstate 'BSDRY' then
      null;
    end;
  else
    v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    perform set_config(v_name, v_previous ->> v_name, true);
  end loop;

  update "better_supabase"."import_runs" r set
    "counts" = jsonb_set(r."counts", array[v_entity], jsonb_build_object(
      'inserted', coalesce(r."counts" -> v_entity ->> 'inserted', '0')::integer + coalesce((v_result ->> 'inserted')::integer, 0),
      'updated', coalesce(r."counts" -> v_entity ->> 'updated', '0')::integer + coalesce((v_result ->> 'updated')::integer, 0),
      'unchanged', coalesce(r."counts" -> v_entity ->> 'unchanged', '0')::integer + coalesce((v_result ->> 'unchanged')::integer, 0),
      'conflicted', coalesce(r."counts" -> v_entity ->> 'conflicted', '0')::integer + coalesce((v_result ->> 'conflicted')::integer, 0),
      'missing', coalesce((r."counts" -> v_entity ->> 'missing')::integer, 0)
    )),
    "errors" = r."errors" || coalesce(v_result -> 'errors', '[]'::jsonb),
    "diff" = (select coalesce(jsonb_agg(d.value), '[]'::jsonb) from (
      select value from jsonb_array_elements(r."diff" || coalesce(v_result -> 'diff', '[]'::jsonb)) value limit 100
    ) d)
  where r."id" = v_run_id;
  return v_result || jsonb_build_object('dryRun', v_run."dry_run");
end;
$$;
revoke execute on function "better_supabase"."import_upsert_batch"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_upsert_batch"(uuid, text, jsonb) to service_role;

-- Bulk external key to subject. keys is an array of text, or of { key, scope,
-- role }; a scope that aliases another resolves through it.
create or replace function "better_supabase"."import_resolve"(run uuid, entity text, keys jsonb)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = import_resolve.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if jsonb_typeof(import_resolve.keys) <> 'array' then
    raise exception 'keys must be an array' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('key', q.key, 'scope', q.scope, 'role', q.role, 'subjectType', m."subject_type", 'subjectId', m."subject_id") order by q.ord)
    from (
      select k.ord,
        case when jsonb_typeof(k.value) = 'string' then k.value #>> '{}' else k.value ->> 'key' end as key,
        case when jsonb_typeof(k.value) = 'string' then '' else coalesce(k.value ->> 'scope', '') end as scope,
        case when jsonb_typeof(k.value) = 'string' then 'primary' else coalesce(k.value ->> 'role', 'primary') end as role
      from jsonb_array_elements(import_resolve.keys) with ordinality k(value, ord)
    ) q
    join lateral (
      select x."subject_type", x."subject_id"
      from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source"
        and x."entity" = import_resolve.entity and x."external_key" = q.key and x."role" = q.role
        and (x."scope" = q.scope or x."scope" in (
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = q.scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? import_resolve.entity)
        ))
      order by (x."scope" = q.scope) desc
      limit 1
    ) m on true
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."import_resolve"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_resolve"(uuid, text, jsonb) to service_role;

-- Closes a run that wrote through import_upsert_batch. A full run marks the
-- records of its entities it didn't see, and never deletes them.
create or replace function "better_supabase"."finish_import_run"(run uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := finish_import_run.run;
  v_run "better_supabase"."import_runs";
  v_entity text;
  v_missing integer;
  v_total integer := 0;
  v_counts jsonb;
  v_outcome text := 'completed';
  v_expected integer;
  v_applied integer;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  v_counts := v_run."counts";

  if v_run."full" then
    for v_entity in select k.key from jsonb_object_keys(v_run."counts") k(key) loop
      select count(*)::integer into v_missing from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
        and x."role" = 'primary' and x."last_run_id" <> v_run_id
        and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      if not v_run."dry_run" then
        update "better_supabase"."import_records" x set "went_missing_at" = coalesce(x."went_missing_at", now())
        where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
          and x."last_run_id" <> v_run_id
          and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  if v_run."plan" is not null and jsonb_typeof(v_run."plan") = 'object' then
    for v_entity in select k.key from jsonb_object_keys(v_run."plan") k(key) loop
      v_expected := coalesce((v_run."plan" ->> v_entity)::integer, 0);
      v_applied := coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'unchanged')::integer, 0);
      if v_applied < v_expected then
        v_outcome := 'incomplete';
        v_counts := jsonb_set(coalesce(v_counts, '{}'::jsonb), array[v_entity, 'missing'], to_jsonb(v_expected - v_applied), true);
      end if;
    end loop;
  end if;
  if v_outcome = 'completed' and (jsonb_array_length(coalesce(v_run."errors", '[]'::jsonb)) > 0 or v_counts::text like '%"conflicted":%') then
    v_outcome := 'completed_with_issues';
  end if;

  update "better_supabase"."import_runs" r set "status" = 'completed', "outcome" = v_outcome, "finished_at" = now(), "counts" = v_counts
  where r."id" = v_run_id;

  if not v_run."dry_run" then
    for v_entity in select k.key from jsonb_object_keys(v_counts) k(key) loop
      v_total := v_total + coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0);
      null;
    end loop;
    null;
  end if;
  return v_counts;
end;
$$;
revoke execute on function "better_supabase"."finish_import_run"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."finish_import_run"(uuid) to service_role;

create or replace function "better_supabase"."heartbeat_import_run"(run uuid, seconds integer default 30)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_until timestamptz;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can heartbeat an import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  update "better_supabase"."import_runs" r set "heartbeat_at" = now(), "lease_until" = now() + make_interval(secs => greatest(heartbeat_import_run.seconds, 1))
  where r."id" = heartbeat_import_run.run and r."status" = 'running'
  returning r."lease_until" into v_until;
  if v_until is null then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  return v_until;
end;
$$;
revoke execute on function "better_supabase"."heartbeat_import_run"(uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."heartbeat_import_run"(uuid, integer) to service_role;

create or replace function "better_supabase"."import_ensure_ref"(tenant uuid, kind text, key text, defaults jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_created boolean := false;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can ensure an import ref' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if import_ensure_ref.kind is null or import_ensure_ref.key is null or import_ensure_ref.key = '' then
    raise exception 'a ref needs a kind and a key' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select r."id" into v_id from "better_supabase".import_refs r
  where r."tenant_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
  if v_id is null then
    insert into "better_supabase".import_refs ("tenant_id", "kind", "key", "payload")
    values (import_ensure_ref.tenant, import_ensure_ref.kind, import_ensure_ref.key, coalesce(import_ensure_ref.defaults, '{}'::jsonb))
    on conflict ("tenant_id", "kind", "key") do nothing
    returning "id" into v_id;
    v_created := v_id is not null;
    if v_id is null then
      select r."id" into v_id from "better_supabase".import_refs r
      where r."tenant_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
    end if;
  end if;
  return jsonb_build_object(
    'id', v_id,
    'created', v_created,
    'warnings', case when v_created then jsonb_build_array(jsonb_build_object('code', 'IMPORT_REF_CREATED', 'kind', import_ensure_ref.kind, 'key', import_ensure_ref.key)) else '[]'::jsonb end
  );
end;
$$;
revoke execute on function "better_supabase"."import_ensure_ref"(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_ensure_ref"(uuid, text, text, jsonb) to service_role;

create or replace function "better_supabase"."import_entities"()
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$ select array[]::text[] $$;
revoke execute on function "better_supabase"."import_entities"() from public, anon, authenticated;
grant execute on function "better_supabase"."import_entities"() to service_role;


create or replace function "better_supabase"."rebase_import_records"(tenant uuid, source text, entities text[] default null, keys text[] default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can rebase import records' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  update "better_supabase"."import_records" x
  set "subject_imported_updated_at" = coalesce((null), x."subject_imported_updated_at"),
      "owned_hash" = coalesce((null), x."owned_hash")
  where x."tenant_id" = rebase_import_records.tenant
    and x."source" = rebase_import_records.source
    and (rebase_import_records.entities is null or x."entity" = any (rebase_import_records.entities))
    and (rebase_import_records.keys is null or x."external_key" = any (rebase_import_records.keys));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."rebase_import_records"(uuid, text, text[], text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."rebase_import_records"(uuid, text, text[], text[]) to service_role;


-- Queues one job per chunk of an entity's items, so a worker writes a large
-- import in batches; the dedupe key makes a retry harmless.
create or replace function "better_supabase"."enqueue_import_chunks"(run uuid, entity text, chunks integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
  v_chunk integer;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = enqueue_import_chunks.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if enqueue_import_chunks.chunks is null or enqueue_import_chunks.chunks < 1 then
    raise exception 'chunks must be at least 1' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  for v_chunk in 0 .. enqueue_import_chunks.chunks - 1 loop
    perform "better_supabase"."enqueue_job"(queue => 'imports', payload => jsonb_build_object('run', v_run."id", 'entity', enqueue_import_chunks.entity, 'chunk', v_chunk), dedupe_key => v_run."id"::text || ':' || enqueue_import_chunks.entity || ':' || v_chunk::text, dedupe_running => false);
  end loop;
  return enqueue_import_chunks.chunks;
end;
$$;
revoke execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) to service_role;

-- Stores the items of one chunk of an entity, ready for a worker. Storing a chunk
-- again before it is done replaces its items; a done chunk is left as it is and
-- the answer is false.
create or replace function "better_supabase"."store_import_chunk"(run uuid, entity text, chunk integer, items jsonb)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = store_import_chunk.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if store_import_chunk.chunk is null or store_import_chunk.chunk < 0 or jsonb_typeof(store_import_chunk.items) is distinct from 'array' then
    raise exception 'a chunk has a number from 0 and an array of items' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  insert into "better_supabase"."import_chunks" ("run_id", "tenant_id", "entity", "chunk", "items")
  values (store_import_chunk.run, v_run."tenant_id", store_import_chunk.entity, store_import_chunk.chunk, store_import_chunk.items)
  on conflict ("run_id", "entity", "chunk") do update
    set "items" = excluded."items", "status" = 'pending', "claimed_at" = null
    where "better_supabase"."import_chunks"."status" <> 'done';
  return found;
end;
$$;
revoke execute on function "better_supabase"."store_import_chunk"(uuid, text, integer, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."store_import_chunk"(uuid, text, integer, jsonb) to service_role;

-- Takes a pending chunk, or one whose claim is older than lease seconds (a worker
-- that died), and returns { entity, chunk, items }. Null when the chunk is done,
-- missing or held by a live worker. Rows another worker holds are skipped, not waited for.
create or replace function "better_supabase"."claim_import_chunk"(run uuid, entity text, chunk integer, lease integer default 300)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_items jsonb;
begin
  with pick as (
    select x."run_id", x."entity", x."chunk"
    from "better_supabase"."import_chunks" x
    where x."run_id" = claim_import_chunk.run and x."entity" = claim_import_chunk.entity and x."chunk" = claim_import_chunk.chunk
      and (x."status" = 'pending' or (x."status" = 'claimed' and x."claimed_at" < now() - make_interval(secs => greatest(claim_import_chunk.lease, 1))))
    for update skip locked
  )
  update "better_supabase"."import_chunks" x set "status" = 'claimed', "claimed_at" = now()
  from pick
  where x."run_id" = pick."run_id" and x."entity" = pick."entity" and x."chunk" = pick."chunk"
  returning x."items" into v_items;
  if v_items is null then
    return null;
  end if;
  return jsonb_build_object('entity', claim_import_chunk.entity, 'chunk', claim_import_chunk.chunk, 'items', v_items);
end;
$$;
revoke execute on function "better_supabase"."claim_import_chunk"(uuid, text, integer, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."claim_import_chunk"(uuid, text, integer, integer) to service_role;

-- Marks a claimed chunk done and keeps what its batch answered.
create or replace function "better_supabase"."complete_import_chunk"(run uuid, entity text, chunk integer, result jsonb)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
begin
  update "better_supabase"."import_chunks" x set "status" = 'done', "done_at" = now(), "result" = complete_import_chunk.result
  where x."run_id" = complete_import_chunk.run and x."entity" = complete_import_chunk.entity
    and x."chunk" = complete_import_chunk.chunk and x."status" = 'claimed';
  return found;
end;
$$;
revoke execute on function "better_supabase"."complete_import_chunk"(uuid, text, integer, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_import_chunk"(uuid, text, integer, jsonb) to service_role;

-- One worker step: claim the chunk, write it with import_upsert_batch and mark it
-- done, in one transaction, so a failure leaves the chunk pending for the next try.
-- A chunk that is done answers what its batch answered; one that is missing or
-- held by another worker answers { skipped: true }.
create or replace function "better_supabase"."process_import_chunk"(run uuid, entity text, chunk integer)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_done jsonb;
  v_claim jsonb;
  v_result jsonb;
begin
  select x."result" into v_done from "better_supabase"."import_chunks" x
  where x."run_id" = process_import_chunk.run and x."entity" = process_import_chunk.entity
    and x."chunk" = process_import_chunk.chunk and x."status" = 'done';
  if found then
    return coalesce(v_done, '{}'::jsonb) || jsonb_build_object('done', true);
  end if;
  v_claim := "better_supabase"."claim_import_chunk"(process_import_chunk.run, process_import_chunk.entity, process_import_chunk.chunk);
  if v_claim is null then
    return jsonb_build_object('skipped', true);
  end if;
  v_result := "better_supabase"."import_upsert_batch"(process_import_chunk.run, process_import_chunk.entity, v_claim -> 'items');
  perform "better_supabase"."complete_import_chunk"(process_import_chunk.run, process_import_chunk.entity, process_import_chunk.chunk, v_result);
  return v_result;
end;
$$;
revoke execute on function "better_supabase"."process_import_chunk"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."process_import_chunk"(uuid, text, integer) to service_role;

-- How many chunks of a run are pending, claimed and done, so a caller knows when to
-- finish the run.
create or replace function "better_supabase"."import_chunk_progress"(run uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'pending', count(*) filter (where x."status" = 'pending'),
    'claimed', count(*) filter (where x."status" = 'claimed'),
    'done', count(*) filter (where x."status" = 'done')
  )
  from "better_supabase"."import_chunks" x
  where x."run_id" = import_chunk_progress.run
$$;
revoke execute on function "better_supabase"."import_chunk_progress"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."import_chunk_progress"(uuid) to service_role;

-- Clears the content hash of the records of a source (and entity) that a run of
-- another mapper version last wrote, so the next import treats them as changed and
-- rewrites them through their target (a row a user changed since stays as it is, as
-- for any changed hash). Returns how many records it cleared.
create or replace function "better_supabase"."reapply_import_records"(tenant uuid, source text, mapper_version text, entity text default null)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_count integer;
begin
  update "better_supabase"."import_records" x set "content_hash" = ''
  where x."tenant_id" = reapply_import_records.tenant and x."source" = reapply_import_records.source
    and (reapply_import_records.entity is null or x."entity" = reapply_import_records.entity)
    and x."content_hash" <> ''
    and (select r."mapper_version" from "better_supabase"."import_runs" r where r."id" = x."last_run_id") is distinct from reapply_import_records.mapper_version;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."reapply_import_records"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."reapply_import_records"(uuid, text, text, text) to service_role;

-- The record map of a source as { entity, scope, key, role, hash, subjectType,
-- subjectId }, one object per record in key order, so a caller can compare what the
-- source sends with what was imported without reading the rows.
create or replace function "better_supabase"."export_import_hashes"(tenant uuid, source text, entity text default null)
returns setof jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('entity', x."entity", 'scope', x."scope", 'key', x."external_key", 'role', x."role",
    'hash', x."content_hash", 'subjectType', x."subject_type", 'subjectId', x."subject_id")
  from "better_supabase"."import_records" x
  where x."tenant_id" = export_import_hashes.tenant and x."source" = export_import_hashes.source
    and (export_import_hashes.entity is null or x."entity" = export_import_hashes.entity)
  order by x."entity", x."scope", x."external_key", x."role"
$$;
revoke execute on function "better_supabase"."export_import_hashes"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."export_import_hashes"(uuid, text, text) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."import_runs" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."import_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."import_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."import_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."import_records" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."import_records" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."import_records" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."import_records" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_064_imports.sql
-- better-supabase module: imports
-- @bsb-block-data imports
-- @bsb-hash sha256:03c82178dd5c9af38535aa92f90002ada8c21fab4dadb8d91c33605f8bdcec29
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('imports', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_064_imports.sql
-- better-supabase module: imports
-- @bsb-block imports@2 managed
-- @bsb-hash sha256:0c62ba753a047ea528edb5180988677092ee24cde5453001231aaadd00149e4c
-- Import runs and the external record map. import_upsert_batch writes items through the targets blocks and the app register, skips equal content, reports rows a user changed since the last import and marks missing keys on full runs. The dry run, parsing and mapping live in TypeScript.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."import_runs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "source" text not null,
  "status" text not null default 'pending',
  "mapping" jsonb not null default '{}'::jsonb,
  "counts" jsonb not null default '{}'::jsonb,
  "errors" jsonb not null default '[]'::jsonb,
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."import_runs" add column "dry_run" boolean not null default false;
alter table "better_supabase"."import_runs" add column "diff" jsonb not null default '[]'::jsonb;
alter table "better_supabase"."import_runs" add column "full" boolean not null default false;
alter table "better_supabase"."import_runs" add column "input_checksum" text;
alter table "better_supabase"."import_runs" add column "correlation_id" text;
alter table "better_supabase"."import_runs" add column "mapper_version" text;
alter table "better_supabase"."import_runs" add column "scope_aliases" jsonb not null default '[]'::jsonb;
alter table "better_supabase"."import_runs" add column "started_at" timestamptz;
alter table "better_supabase"."import_runs" add column "finished_at" timestamptz;
alter table "better_supabase"."import_runs" add column "plan" jsonb;
alter table "better_supabase"."import_runs" add column "outcome" text;
alter table "better_supabase"."import_runs" add column "lease_until" timestamptz;
alter table "better_supabase"."import_runs" add column "heartbeat_at" timestamptz;
alter table "better_supabase"."import_runs" add constraint "bsb_import_runs_status"
  check ("status" in ('pending', 'running', 'completed', 'failed', 'canceled'));
alter table "better_supabase"."import_runs" enable row level security;
revoke all on "better_supabase"."import_runs" from public, anon, authenticated;
grant select on "better_supabase"."import_runs" to authenticated;
grant all on "better_supabase"."import_runs" to service_role;
create index "import_runs_tenant_idx" on "better_supabase"."import_runs" ("tenant_id");
-- One pending or running run per organization and source.
create unique index "import_runs_active_idx" on "better_supabase"."import_runs" ("tenant_id", "source") where "status" in ('pending', 'running');

create table "better_supabase"."import_records" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "source" text not null,
  "scope" text not null default '',
  "entity" text not null,
  "external_key" text not null,
  "role" text not null default 'primary',
  "subject_type" text not null,
  "subject_id" text not null,
  "content_hash" text not null,
  "first_run_id" uuid not null,
  "last_run_id" uuid not null,
  "subject_imported_updated_at" timestamptz,
  "source_updated_at" timestamptz,
  "owned_hash" text,
  "went_missing_at" timestamptz,
  constraint "import_records_key" unique ("tenant_id", "source", "scope", "entity", "external_key", "role")
);
create index "import_records_subject_idx" on "better_supabase"."import_records" ("tenant_id", "subject_type", "subject_id");
alter table "better_supabase"."import_records" enable row level security;
revoke all on "better_supabase"."import_records" from public, anon, authenticated;
grant select on "better_supabase"."import_records" to authenticated;
grant all on "better_supabase"."import_records" to service_role;
create table "better_supabase".import_refs (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null,
  "key" text not null,
  "payload" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now(),
  constraint import_refs_key unique ("tenant_id", "kind", "key")
);

create table "better_supabase"."import_chunks" (
  "run_id" uuid not null references "better_supabase"."import_runs" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "entity" text not null,
  "chunk" integer not null,
  "items" jsonb not null,
  "status" text not null default 'pending',
  "result" jsonb,
  "claimed_at" timestamptz,
  "done_at" timestamptz,
  "created_at" timestamptz not null default now(),
  primary key ("run_id", "entity", "chunk")
);
alter table "better_supabase"."import_chunks" add constraint "bsb_import_chunks_status"
  check ("status" in ('pending', 'claimed', 'done'));
alter table "better_supabase"."import_chunks" enable row level security;
revoke all on "better_supabase"."import_chunks" from public, anon, authenticated;
grant all on "better_supabase"."import_chunks" to service_role;
create index "import_chunks_tenant_idx" on "better_supabase"."import_chunks" ("tenant_id");


create table "better_supabase".import_run_issues (
  "id" uuid primary key default gen_random_uuid(),
  "run_id" uuid not null,
  "tenant_id" uuid not null,
  "source" text not null,
  "entity" text not null,
  "key" text not null,
  "kind" text not null,
  "code" text not null,
  "message" text not null,
  "created_at" timestamptz not null default now(),
  "resolved_at" timestamptz,
  constraint bsb_import_run_issues_kind check ("kind" in ('conflict', 'error', 'warning'))
);
create index import_run_issues_open_idx
  on "better_supabase".import_run_issues ("tenant_id", "source", "entity", "key")
  where "resolved_at" is null;
create index import_run_issues_run_idx
  on "better_supabase".import_run_issues ("run_id", "entity");

create or replace function "better_supabase"."start_import_run"(tenant uuid, source text, options jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_options jsonb := coalesce(start_import_run.options, '{}'::jsonb);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', start_import_run.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if start_import_run.source is null or start_import_run.source = '' then
    raise exception 'an import run needs a source' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(coalesce(v_options -> 'scopeAliases', '[]'::jsonb)) <> 'array' then
    raise exception 'scopeAliases must be an array of { scope, of, entities }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    insert into "better_supabase"."import_runs" as r ("tenant_id", "source", "mapping", "dry_run", "full", "input_checksum", "correlation_id", "mapper_version", "scope_aliases", "plan", "lease_until", "created_by")
    values (
      start_import_run.tenant,
      start_import_run.source,
      coalesce(v_options -> 'mapping', '{}'::jsonb),
      coalesce((v_options ->> 'dryRun')::boolean, false),
      coalesce((v_options ->> 'full')::boolean, false),
      v_options ->> 'inputChecksum',
      v_options ->> 'correlationId',
      nullif(v_options ->> 'mapperVersion', ''),
      coalesce(v_options -> 'scopeAliases', '[]'::jsonb),
      v_options -> 'plan',
      now() + interval '30 seconds',
      auth.uid()
    )
    returning r."id" into v_id;
  exception when unique_violation then
    raise exception 'an import of this source is already pending or running' using errcode = '55P03', hint = 'IMPORT_RUN_ACTIVE';
  end;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."start_import_run"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."start_import_run"(uuid, text, jsonb) to authenticated, service_role;

-- The first release's entry point: a run without options.
create or replace function "better_supabase"."start_import"(tenant uuid, source text, mapping jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select "better_supabase"."start_import_run"(start_import.tenant, start_import.source, jsonb_build_object('mapping', coalesce(start_import.mapping, '{}'::jsonb)));
$$;
revoke execute on function "better_supabase"."start_import"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."start_import"(uuid, text, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_import_run"(id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = get_import_run.id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_run."tenant_id", 'imports.manage'), false)) then
    raise exception 'not allowed to read this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."tenant_id", 'source', v_run."source", 'status', v_run."status", 'outcome', v_run."outcome", 'plan', v_run."plan", 'mapping', v_run."mapping", 'counts', v_run."counts", 'errors', v_run."errors", 'dryRun', v_run."dry_run", 'full', v_run."full", 'inputChecksum', v_run."input_checksum", 'correlationId', v_run."correlation_id", 'mapperVersion', v_run."mapper_version", 'scopeAliases', v_run."scope_aliases", 'leaseUntil', v_run."lease_until", 'heartbeatAt', v_run."heartbeat_at", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'startedAt', v_run."started_at", 'finishedAt', v_run."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "better_supabase".import_run_issues i
    where i."run_id" = v_run."id"
  ));
end;
$$;
revoke execute on function "better_supabase"."get_import_run"(uuid) from public, anon;
grant execute on function "better_supabase"."get_import_run"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_import_runs"(tenant uuid, source text default null, status text default null, row_limit integer default 50)
returns setof jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_import_runs.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list imports' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  return query
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'source', r."source", 'status', r."status", 'outcome', r."outcome", 'plan', r."plan", 'mapping', r."mapping", 'counts', r."counts", 'errors', r."errors", 'dryRun', r."dry_run", 'full', r."full", 'inputChecksum', r."input_checksum", 'correlationId', r."correlation_id", 'mapperVersion', r."mapper_version", 'scopeAliases', r."scope_aliases", 'leaseUntil', r."lease_until", 'heartbeatAt', r."heartbeat_at", 'createdBy', r."created_by", 'createdAt', r."created_at", 'startedAt', r."started_at", 'finishedAt', r."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "better_supabase".import_run_issues i
    where i."run_id" = r."id"
  ))
    from "better_supabase"."import_runs" r
    where r."tenant_id" = list_import_runs.tenant
      and (list_import_runs.source is null or r."source" = list_import_runs.source)
      and (list_import_runs.status is null or r."status" = list_import_runs.status)
    order by r."created_at" desc, r."id" desc
    limit least(greatest(coalesce(list_import_runs.row_limit, 50), 1), 200);
end;
$$;
revoke execute on function "better_supabase"."list_import_runs"(uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_import_runs"(uuid, text, text, integer) to authenticated, service_role;

create or replace function "better_supabase"."cancel_import_run"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_run "better_supabase"."import_runs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_run from "better_supabase"."import_runs" r where r."id" = cancel_import_run.id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_run."tenant_id", 'imports.manage'), false)) then
    raise exception 'not allowed to cancel this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if v_run."status" not in ('pending', 'running') then
    raise exception 'this import already finished' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  update "better_supabase"."import_runs" r set "status" = 'canceled', "finished_at" = now()
  where r."id" = cancel_import_run.id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_import_run"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_import_run"(uuid) to authenticated, service_role;

-- The run moves from pending to running before the first batch, so a run
-- that dies mid-way is visible as running rather than pending.
create or replace function "better_supabase"."mark_import_running"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  update "better_supabase"."import_runs" set "status" = 'running', "started_at" = now()
  where "id" = mark_import_running.id and "status" = 'pending';
  if not found then
    raise exception 'no pending import with this id' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."mark_import_running"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_import_running"(uuid) to service_role;

-- Closes a run whose rows the caller wrote itself (`defineImport` without a
-- target); `finish_import_run` closes a run that used `import_upsert_batch`.
create or replace function "better_supabase"."finish_import"(id uuid, status text, count integer, error text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_source text;
begin
  update "better_supabase"."import_runs" set "status" = finish_import.status,
    "finished_at" = now(),
    "counts" = case when finish_import.status = 'completed' then jsonb_build_object("source", jsonb_build_object('inserted', finish_import.count, 'updated', 0, 'unchanged', 0, 'conflicted', 0, 'missing', 0)) else "counts" end,
    "errors" = case when finish_import.error is null then "errors" else "errors" || jsonb_build_array(jsonb_build_object('entity', "source", 'key', null, 'code', 'IMPORT_ITEM_INVALID', 'message', finish_import.error)) end
  where "id" = finish_import.id
  returning "tenant_id", "source" into v_tenant, v_source;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if finish_import.status = 'failed' then
    perform "better_supabase".emit_event('import.failed', jsonb_build_object('organizationId', v_tenant, 'id', finish_import.id, 'error', finish_import.error), 'imports/' || finish_import.id::text, (v_tenant)::text, null, 'better-supabase/imports');
  else
    perform "better_supabase".emit_event('import.completed', jsonb_build_object('organizationId', v_tenant, 'id', finish_import.id, 'count', finish_import.count), 'imports/' || finish_import.id::text, (v_tenant)::text, null, 'better-supabase/imports');
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."finish_import"(uuid, text, integer, text) from public, anon, authenticated;
grant execute on function "better_supabase"."finish_import"(uuid, text, integer, text) to service_role;

create or replace function "better_supabase"."import_note_issue"(run uuid, entity text, key text, kind text, code text, message text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_source text;
begin
  select r."tenant_id", r."source" into v_tenant, v_source
  from "better_supabase"."import_runs" r where r."id" = import_note_issue.run;
  if v_tenant is null or import_note_issue.key is null or import_note_issue.key = '' then
    return;
  end if;
  insert into "better_supabase".import_run_issues ("run_id", "tenant_id", "source", "entity", "key", "kind", "code", "message")
  values (import_note_issue.run, v_tenant, v_source, import_note_issue.entity, import_note_issue.key, import_note_issue.kind, import_note_issue.code, import_note_issue.message);
end;
$$;

create or replace function "better_supabase"."import_note_warnings"(run uuid, entity text, warnings jsonb)
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
    perform "better_supabase"."import_note_issue"(
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

create or replace function "better_supabase"."import_clear_issues"(run uuid, entity text, key text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_source text;
begin
  select r."tenant_id", r."source" into v_tenant, v_source
  from "better_supabase"."import_runs" r where r."id" = import_clear_issues.run;
  if v_tenant is null then
    return;
  end if;
  update "better_supabase".import_run_issues i set "resolved_at" = now()
  where i."tenant_id" = v_tenant and i."source" = v_source
    and i."entity" = import_clear_issues.entity and i."key" = import_clear_issues.key
    and i."resolved_at" is null;
end;
$$;

create or replace function "better_supabase"."list_import_issues"(run uuid, entity text default null, row_limit integer default 50, row_offset integer default 0)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_total integer;
  v_rows jsonb;
begin
  select r."tenant_id" into v_tenant from "better_supabase"."import_runs" r where r."id" = list_import_issues.run;
  if v_tenant is null then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list import issues' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  select count(*) into v_total from "better_supabase".import_run_issues i
  where i."run_id" = list_import_issues.run
    and (list_import_issues.entity is null or i."entity" = list_import_issues.entity);
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_rows from (
    select i."entity", i."key", i."kind", i."code", i."message", i."created_at", i."resolved_at"
    from "better_supabase".import_run_issues i
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
revoke execute on function "better_supabase"."list_import_issues"(uuid, text, integer, integer) from public, anon;
grant execute on function "better_supabase"."list_import_issues"(uuid, text, integer, integer) to authenticated, service_role;

-- Counts and the first changed fields of a dry run. The dry run itself writes
-- no subject rows; the diff is what the batch returned.
create or replace function "better_supabase"."list_import_diff"(run uuid, entity text default null, row_limit integer default 50, row_offset integer default 0)
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
  select r."counts", r."diff" into v_counts, v_diff from "better_supabase"."import_runs" r where r."id" = list_import_diff.run;
  if v_counts is null then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
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
revoke execute on function "better_supabase"."list_import_diff"(uuid, text, integer, integer) from public, anon;
grant execute on function "better_supabase"."list_import_diff"(uuid, text, integer, integer) to authenticated, service_role;

create or replace function "better_supabase"."resolve_import_conflict"(tenant uuid, source text, entity text, key text, action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resolved integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', resolve_import_conflict.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to resolve an import conflict' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if resolve_import_conflict.action = 'keep' then
    update "better_supabase"."import_records" x set "subject_imported_updated_at" = now()
    where x."tenant_id" = resolve_import_conflict.tenant
      and x."source" = resolve_import_conflict.source
      and x."entity" = resolve_import_conflict.entity
      and x."external_key" = resolve_import_conflict.key;
  elsif resolve_import_conflict.action = 'overwrite' then
    update "better_supabase"."import_records" x set "subject_imported_updated_at" = null, "owned_hash" = null
    where x."tenant_id" = resolve_import_conflict.tenant
      and x."source" = resolve_import_conflict.source
      and x."entity" = resolve_import_conflict.entity
      and x."external_key" = resolve_import_conflict.key;
  else
    raise exception 'action must be keep or overwrite' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  update "better_supabase".import_run_issues i set "resolved_at" = now()
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
revoke execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) to service_role;
revoke execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."import_integrity"(tenant uuid, source text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_checks jsonb := '[]'::jsonb;
  v_name text;
  v_severity text;
  v_count integer;
  v_ids jsonb;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', import_integrity.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to check this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  for v_name, v_severity, v_count, v_ids in
    select 'duplicate_keys', 'error', count(*)::integer, coalesce(jsonb_agg(sample), '[]'::jsonb) from (
      select min(d."id"::text) as sample from "better_supabase"."import_records" d
      where d."tenant_id" = import_integrity.tenant
        and (import_integrity.source is null or d."source" = import_integrity.source)
      group by d."entity", d."external_key"
      having count(distinct d."subject_id") > 1
    ) q
    union all
    select 'unbalanced_ledger', 'error', count(*)::integer, coalesce(jsonb_agg(sample), '[]'::jsonb) from (
      select e."transaction_id"::text as sample from "better_supabase"."ledger_entries" e
      join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
      where y."tenant_id" = import_integrity.tenant
      group by e."transaction_id"
      having sum(e."amount") <> 0
    ) q
    union all
    select 'negative_invoice', 'warning', count(*)::integer, coalesce(jsonb_agg("id"::text), '[]'::jsonb) from "better_supabase"."invoices" where "tenant_id" = import_integrity.tenant and "total" < 0 and "kind"::text is distinct from 'credit_note'
    union all
    select 'issued_without_number', 'warning', count(*)::integer, coalesce(jsonb_agg("id"::text), '[]'::jsonb) from "better_supabase"."invoices" where "tenant_id" = import_integrity.tenant and "status"::text in ('issued', 'partially_paid', 'paid') and nullif("identifier"::text, '') is null
    union all
    select 'archived_without_date', 'warning', count(*)::integer, coalesce(jsonb_agg("id"::text), '[]'::jsonb) from "better_supabase"."companies" where "tenant_id" = import_integrity.tenant and "lifecycle"::text = 'archived' and "archived_at" is null
  loop
    v_checks := v_checks || jsonb_build_array(jsonb_build_object(
      'name', v_name, 'severity', v_severity, 'count', v_count, 'ids', coalesce(v_ids, '[]'::jsonb)));
  end loop;
  return jsonb_build_object('checks', v_checks);
end;
$$;
revoke execute on function "better_supabase"."import_integrity"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_integrity"(uuid, text) to service_role;
revoke execute on function "better_supabase"."import_integrity"(uuid, text) from public, anon;
grant execute on function "better_supabase"."import_integrity"(uuid, text) to authenticated, service_role;

create table "better_supabase".import_sources (
  "id" text primary key,
  "label_key" text not null,
  "description_key" text not null,
  "file_types" text[] not null default '{}',
  "entities" text[] not null default '{}',
  "docs_link" text
);

create or replace function "better_supabase"."register_import_source"(id text, label_key text, description_key text, file_types text[], entities text[], docs_link text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'not allowed to register an import source' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  insert into "better_supabase".import_sources ("id", "label_key", "description_key", "file_types", "entities", "docs_link")
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
revoke execute on function "better_supabase"."register_import_source"(text, text, text, text[], text[], text) from public, anon, authenticated;
grant execute on function "better_supabase"."register_import_source"(text, text, text, text[], text[], text) to service_role;

create or replace function "better_supabase"."list_import_sources"()
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
  from "better_supabase".import_sources s
$$;
revoke execute on function "better_supabase"."list_import_sources"() from public, anon;
grant execute on function "better_supabase"."list_import_sources"() to authenticated, service_role;

-- Every run of the tenant, whoever started it: the CLI, an API or the UI.
create or replace function "better_supabase"."list_import_source_runs"(tenant uuid, source text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r."id", 'source', r."source", 'status', r."status", 'createdAt', r."created_at"
  ) order by r."created_at" desc), '[]'::jsonb)
  from "better_supabase"."import_runs" r
  where r."tenant_id" = list_import_source_runs.tenant
    and (list_import_source_runs.source is null or r."source" = list_import_source_runs.source)
$$;
revoke execute on function "better_supabase"."list_import_source_runs"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_import_source_runs"(uuid, text) to authenticated, service_role;


-- Writes the items of one entity: an unknown key inserts, an equal hash is
-- unchanged and writes nothing, a changed hash updates unless the row changed
-- after the last import (conflicted). Returns the counts and the item errors.
create or replace function "better_supabase"."import_apply_batch"(run uuid, entity text, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := import_apply_batch.run;
  v_entity text := import_apply_batch.entity;
  v_items jsonb := import_apply_batch.items;
  v_run "better_supabase"."import_runs";
  v_item jsonb;
  v_call jsonb;
  v_key text;
  v_scope text;
  v_data jsonb;
  v_hash text;
  v_source_at timestamptz;
  v_diff jsonb := '[]'::jsonb;
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_owned text;
  v_natural text;
  v_ref_map jsonb := '{}'::jsonb;
  v_resolved jsonb := '{}'::jsonb;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_issue text;
  v_message text;
  v_hint text;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if v_entity <> all (array['organization_profile', 'attachment', 'data_lifecycle_row', 'field_value', 'supplier_item', 'product_identifier', 'discount_group', 'discount_rule', 'party_discount_group', 'product', 'product_category', 'stock_count', 'order', 'payment_term', 'document_delivery_preference', 'party', 'party_contact', 'contact_method', 'party_location', 'party_bank_account', 'quote', 'invoice', 'credit_note', 'open_item', 'invoice_allocation', 'meter_reading', 'due_check', 'asset', 'asset_identifier', 'accounting_account', 'accounting_journal', 'accounting_entry', 'accounting_opening_balance', 'tax_code', 'tax_rate', 'document_template', 'document_text_block']::text[]) then
    raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    raise exception 'items must be an array of { key, scope, data, refs }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  v_ref_map := coalesce((
    select jsonb_object_agg(wanted.field || chr(31) || wanted.key, found."subject_id")
    from (
      select ref.field, ref.entity, item.value -> 'refs' ->> ref.field as key
      from jsonb_array_elements(v_items) item(value)
      cross join (values ('tax', 'tax_code', 'product'), ('product', 'product', 'product_category'), ('category', 'category', 'product_category'), ('billTo', 'party', 'party'), ('company', 'party', 'party_contact'), ('person', 'party', 'party_contact'), ('party', 'party', 'contact_method'), ('party', 'party', 'party_location'), ('party', 'party', 'party_bank_account'), ('asset', 'asset', 'due_check'), ('asset', 'asset', 'asset_identifier')) as ref(field, entity, target)
      where ref.target = v_entity
    ) wanted
    join "better_supabase"."import_records" found
      on found."tenant_id" = v_run."tenant_id"
      and found."source" = v_run."source"
      and found."entity" = wanted.entity
      and found."external_key" = wanted.key
    where wanted.key is not null
  ), '{}'::jsonb);

  for v_item in
    select e.value from jsonb_array_elements(v_items) e
    order by e.value #>> '{data,orderBy}', e.value #>> '{data,readAt}', e.value ->> 'key'
  loop
    v_issue := null;
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      perform "better_supabase"."import_note_issue"(v_run_id, v_entity, coalesce(v_key, ''), 'error', 'IMPORT_ITEM_INVALID', 'an item needs a key and a data object');
      continue;
    end if;

    

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;
      v_source_at := nullif(v_item ->> 'sourceUpdatedAt', '')::timestamptz;
      if v_found and v_source_at is not null and v_rec."source_updated_at" is not null and v_source_at <= v_rec."source_updated_at" then
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');
      end if;

      if v_done then
        null;
      elsif not v_found then
        v_natural := null;
        case v_entity
        when 'party_bank_account' then
          v_natural := "better_supabase"."party_bank_account_id"(v_run."tenant_id", v_item);
          else null;
        end case;
        if v_natural is not null then
          v_found := true;
          v_rec."subject_id" := v_natural;
          v_rec."content_hash" := '';
        end if;
      end if;

      if v_done then
        null;
      elsif not v_found then
        -- A cloned administration reuses the subjects of the scope it aliases
        -- when the content is equal there.
        for v_other in
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = v_scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? v_entity)
        loop
          if exists (
            select 1 from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary' and x."content_hash" = v_hash
          ) then
            insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_imported_updated_at"
            from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key
            on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do nothing;
            v_unchanged := v_unchanged + 1;
            v_done := true;
            exit;
          end if;
        end loop;
      elsif v_rec."content_hash" = v_hash then
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."went_missing_at" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        v_owned := null;
        case v_entity
        when 'organization_profile' then
          v_current := "better_supabase"."organization_profile_updated_at"(v_rec."subject_id");
        when 'supplier_item' then
          v_current := "better_supabase"."supplier_item_updated_at"(v_rec."subject_id");
        when 'product_identifier' then
          v_current := "better_supabase"."product_identifier_updated_at"(v_rec."subject_id");
        when 'discount_group' then
          v_current := "better_supabase"."discount_group_updated_at"(v_rec."subject_id");
        when 'discount_rule' then
          v_current := "better_supabase"."discount_rule_updated_at"(v_rec."subject_id");
        when 'product' then
          v_current := "better_supabase"."product_updated_at"(v_rec."subject_id");
        when 'product_category' then
          v_current := "better_supabase"."product_category_updated_at"(v_rec."subject_id");
        when 'stock_count' then
          v_current := "better_supabase"."stock_count_updated_at"(v_rec."subject_id");
        when 'order' then
          v_current := "better_supabase"."order_updated_at"(v_rec."subject_id");
        when 'payment_term' then
          v_current := "better_supabase"."payment_term_updated_at"(v_rec."subject_id");
        when 'document_delivery_preference' then
          v_current := "better_supabase"."document_delivery_preference_updated_at"(v_rec."subject_id");
        when 'party' then
          v_current := "better_supabase"."party_updated_at"(v_rec."subject_id");
        when 'party_contact' then
          v_current := "better_supabase"."party_contact_updated_at"(v_rec."subject_id");
        when 'contact_method' then
          v_current := "better_supabase"."contact_method_updated_at"(v_rec."subject_id");
        when 'party_location' then
          v_current := "better_supabase"."party_location_updated_at"(v_rec."subject_id");
        when 'party_bank_account' then
          v_current := "better_supabase"."party_bank_account_updated_at"(v_rec."subject_id");
        when 'quote' then
          v_current := "better_supabase"."quote_updated_at"(v_rec."subject_id");
        when 'invoice' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'credit_note' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'open_item' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'invoice_allocation' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'due_check' then
          v_current := "better_supabase"."due_check_updated_at"(v_rec."subject_id");
        when 'asset' then
          v_current := "better_supabase"."asset_updated_at"(v_rec."subject_id");
        when 'asset_identifier' then
          v_current := "better_supabase"."asset_identifier_updated_at"(v_rec."subject_id");
        when 'tax_code' then
          v_current := "better_supabase"."tax_code_updated_at"(v_rec."subject_id");
        when 'document_template' then
          v_current := "better_supabase"."document_template_updated_at"(v_rec."subject_id");
        when 'document_text_block' then
          v_current := "better_supabase"."document_text_block_updated_at"(v_rec."subject_id");
          else null;
        end case;
        null;
        if v_owned is not null and v_rec."owned_hash" is not null and v_owned is distinct from v_rec."owned_hash" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_issue := 'conflict';
          v_done := true;
        elsif v_owned is not null and v_current is not null and v_rec."subject_imported_updated_at" is not null and v_current > v_rec."subject_imported_updated_at" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "subject_imported_updated_at" = v_current, "owned_hash" = v_owned
          where x."id" = v_rec."id";
        elsif v_owned is null and v_current is not null and v_rec."subject_imported_updated_at" is not null and v_current > v_rec."subject_imported_updated_at" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_issue := 'conflict';
          v_done := true;
        end if;
      end if;

      if v_issue = 'conflict' then
        perform "better_supabase"."import_note_issue"(v_run_id, v_entity, v_key, 'conflict', 'IMPORT_CONFLICT', 'the subject changed after the last import');
      else
        perform "better_supabase"."import_clear_issues"(v_run_id, v_entity, v_key);
      end if;

      if not v_done and v_run."dry_run" and jsonb_typeof(v_item -> 'previous') = 'object' and jsonb_array_length(v_diff) < 20 then
        v_diff := v_diff || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'fields', (
          select coalesce(jsonb_agg(jsonb_build_object('field', k, 'old', v_item -> 'previous' -> k, 'new', v_data -> k)), '[]'::jsonb)
          from jsonb_object_keys(v_data) k where (v_data -> k) is distinct from (v_item -> 'previous' -> k))));
      end if;
      if not v_done then
        v_subject_id := case when v_found then v_rec."subject_id" else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run."tenant_id", 'scope', v_scope);
        v_resolved := coalesce((
    select jsonb_object_agg(ref.field, v_ref_map ->> (ref.field || chr(31) || (v_item -> 'refs' ->> ref.field)))
    from (values ('tax', 'tax_code', 'product'), ('product', 'product', 'product_category'), ('category', 'category', 'product_category'), ('billTo', 'party', 'party'), ('company', 'party', 'party_contact'), ('person', 'party', 'party_contact'), ('party', 'party', 'contact_method'), ('party', 'party', 'party_location'), ('party', 'party', 'party_bank_account'), ('asset', 'asset', 'due_check'), ('asset', 'asset', 'asset_identifier')) as ref(field, entity, target)
    where ref.target = v_entity
      and v_item -> 'refs' ->> ref.field is not null
      and v_ref_map ? (ref.field || chr(31) || (v_item -> 'refs' ->> ref.field))
  ), '{}'::jsonb);
  v_warnings := v_warnings || coalesce((
    select jsonb_agg(jsonb_build_object(
      'entity', v_entity,
      'key', v_item -> 'refs' ->> ref.field,
      'code', 'IMPORT_REF_MISSING',
      'message', 'missing ref ' || ref.field
    ))
    from (values ('tax', 'tax_code', 'product'), ('product', 'product', 'product_category'), ('category', 'category', 'product_category'), ('billTo', 'party', 'party'), ('company', 'party', 'party_contact'), ('person', 'party', 'party_contact'), ('party', 'party', 'contact_method'), ('party', 'party', 'party_location'), ('party', 'party', 'party_bank_account'), ('asset', 'asset', 'due_check'), ('asset', 'asset', 'asset_identifier')) as ref(field, entity, target)
    where ref.target = v_entity
      and v_item -> 'refs' ->> ref.field is not null
      and not (v_ref_map ? (ref.field || chr(31) || (v_item -> 'refs' ->> ref.field)))
  ), '[]'::jsonb);
  v_call := v_call || jsonb_build_object('resolved', v_resolved);
        case v_entity
      when 'organization_profile' then
        v_subject_type := 'organization_profile';
        v_out := "better_supabase"."import_organization_profile"(v_run_id, v_call, v_subject_id);
      when 'attachment' then
        v_subject_type := 'attachment';
        v_out := "better_supabase"."import_attachment"(v_run_id, v_call, v_subject_id);
      when 'data_lifecycle_row' then
        v_subject_type := 'data_lifecycle_row';
        v_out := "better_supabase"."restore_data_row"(v_run_id, v_call, v_subject_id);
      when 'field_value' then
        v_subject_type := 'field_value';
        v_out := "better_supabase"."import_field_value"(v_run_id, v_call, v_subject_id);
      when 'supplier_item' then
        v_subject_type := 'supplier_item';
        v_out := "better_supabase"."import_supplier_item"(v_run_id, v_call, v_subject_id);
      when 'product_identifier' then
        v_subject_type := 'product_identifier';
        v_out := "better_supabase"."import_product_identifier"(v_run_id, v_call, v_subject_id);
      when 'discount_group' then
        v_subject_type := 'discount_group';
        v_out := "better_supabase"."import_discount_group"(v_run_id, v_call, v_subject_id);
      when 'discount_rule' then
        v_subject_type := 'discount_rule';
        v_out := "better_supabase"."import_discount_rule"(v_run_id, v_call, v_subject_id);
      when 'party_discount_group' then
        v_subject_type := 'party';
        v_out := "better_supabase"."import_party_discount_group"(v_run_id, v_call, v_subject_id);
      when 'product' then
        v_subject_type := 'product';
        v_out := "better_supabase"."import_product"(v_run_id, v_call, v_subject_id);
      when 'product_category' then
        v_subject_type := 'product_category';
        v_out := "better_supabase"."import_product_category"(v_run_id, v_call, v_subject_id);
      when 'stock_count' then
        v_subject_type := 'stock_count';
        v_out := "better_supabase"."import_stock_count"(v_run_id, v_call, v_subject_id);
      when 'order' then
        v_subject_type := 'order';
        v_out := "better_supabase"."import_order"(v_run_id, v_call, v_subject_id);
      when 'payment_term' then
        v_subject_type := 'payment_term';
        v_out := "better_supabase"."import_payment_term"(v_run_id, v_call, v_subject_id);
      when 'document_delivery_preference' then
        v_subject_type := 'document_delivery_preference';
        v_out := "better_supabase"."import_document_delivery_preference"(v_run_id, v_call, v_subject_id);
      when 'party' then
        v_subject_type := 'party';
        v_out := "better_supabase"."import_party"(v_run_id, v_call, v_subject_id);
      when 'party_contact' then
        v_subject_type := 'party_contact';
        v_out := "better_supabase"."import_party_contact"(v_run_id, v_call, v_subject_id);
      when 'contact_method' then
        v_subject_type := 'contact_method';
        v_out := "better_supabase"."import_contact_method"(v_run_id, v_call, v_subject_id);
      when 'party_location' then
        v_subject_type := 'party_location';
        v_out := "better_supabase"."import_party_location"(v_run_id, v_call, v_subject_id);
      when 'party_bank_account' then
        v_subject_type := 'party_bank_account';
        v_out := "better_supabase"."import_party_bank_account"(v_run_id, v_call, v_subject_id);
      when 'quote' then
        v_subject_type := 'quote';
        v_out := "better_supabase"."import_quote"(v_run_id, v_call, v_subject_id);
      when 'invoice' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_invoice"(v_run_id, v_call, v_subject_id);
      when 'credit_note' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_credit_note"(v_run_id, v_call, v_subject_id);
      when 'open_item' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_open_item"(v_run_id, v_call, v_subject_id);
      when 'invoice_allocation' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_allocation"(v_run_id, v_call, v_subject_id);
      when 'meter_reading' then
        v_subject_type := 'meter_reading';
        v_out := "better_supabase"."import_meter_reading"(v_run_id, v_call, v_subject_id);
      when 'due_check' then
        v_subject_type := 'due_check';
        v_out := "better_supabase"."import_due_check"(v_run_id, v_call, v_subject_id);
      when 'asset' then
        v_subject_type := 'asset';
        v_out := "better_supabase"."import_asset"(v_run_id, v_call, v_subject_id);
      when 'asset_identifier' then
        v_subject_type := 'asset_identifier';
        v_out := "better_supabase"."import_asset_identifier"(v_run_id, v_call, v_subject_id);
      when 'accounting_account' then
        v_subject_type := 'accounting_account';
        v_out := "better_supabase"."import_accounting_account"(v_run_id, v_call, v_subject_id);
      when 'accounting_journal' then
        v_subject_type := 'accounting_journal';
        v_out := "better_supabase"."import_accounting_journal"(v_run_id, v_call, v_subject_id);
      when 'accounting_entry' then
        v_subject_type := 'accounting_entry';
        v_out := "better_supabase"."import_accounting_entry"(v_run_id, v_call, v_subject_id);
      when 'accounting_opening_balance' then
        v_subject_type := 'accounting_opening_balance';
        v_out := "better_supabase"."import_accounting_opening_balance"(v_run_id, v_call, v_subject_id);
      when 'tax_code' then
        v_subject_type := 'tax_code';
        v_out := "better_supabase"."import_tax_code"(v_run_id, v_call, v_subject_id);
      when 'tax_rate' then
        v_subject_type := 'tax_rate';
        v_out := "better_supabase"."import_tax_rate"(v_run_id, v_call, v_subject_id);
      when 'document_template' then
        v_subject_type := 'document_template';
        v_out := "better_supabase"."import_document_template"(v_run_id, v_call, v_subject_id);
      when 'document_text_block' then
        v_subject_type := 'document_text_block';
        v_out := "better_supabase"."import_document_text_block"(v_run_id, v_call, v_subject_id);
      else
        raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
    end case;

          v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
  if not exists (
    select 1 from jsonb_array_elements(v_subjects) s
    where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
  ) then
    raise exception 'the import target returned no primary subject' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
    if jsonb_typeof(v_subject -> 'warnings') = 'array' then
      v_warnings := v_warnings || (select coalesce(jsonb_agg(w.value || jsonb_build_object('entity', v_entity, 'key', v_key)), '[]'::jsonb) from jsonb_array_elements(v_subject -> 'warnings') w);
    end if;
    insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at", "source_updated_at", "went_missing_at")
    values (
      v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
      coalesce(v_subject ->> 'role', 'primary'),
      coalesce(v_subject ->> 'subjectType', v_subject_type),
      v_subject ->> 'subjectId',
      v_hash, v_run_id, v_run_id,
      coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
      v_source_at,
      null
    )
    on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
      "subject_type" = excluded."subject_type",
      "subject_id" = excluded."subject_id",
      "content_hash" = excluded."content_hash",
      "last_run_id" = excluded."last_run_id",
      "subject_imported_updated_at" = excluded."subject_imported_updated_at",
      "source_updated_at" = coalesce(excluded."source_updated_at", "better_supabase"."import_records"."source_updated_at"),
      "went_missing_at" = null;
  end loop;

  if v_found then
    v_updated := v_updated + 1;
  else
    v_inserted := v_inserted + 1;
  end if;
  
      end if;
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
      perform "better_supabase"."import_note_issue"(v_run_id, v_entity, coalesce(v_key, ''), 'error', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), v_message);
    end;
  end loop;

  

  perform "better_supabase"."import_note_warnings"(v_run_id, v_entity, v_warnings);

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors, 'diff', v_diff) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
end;
$$;
revoke execute on function "better_supabase"."import_apply_batch"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_apply_batch"(uuid, text, jsonb) to service_role;

-- Turns import mode on for the rest of the transaction (ADR 0141): the outbox
-- applies the imports.events policy, the audit log tags entries as
-- integration with the correlation id import:<run> (imports.audit decides rows
-- or one summary per entity) and ctx.importing() guards skip their side
-- effects. The setting is transaction-local and better_supabase.import_run()
-- only reports it to the service role, so no user session can turn it on.
create or replace function "better_supabase"."begin_import_session"(run uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_status text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role can begin an import session' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  select r."status"::text into v_status from "better_supabase"."import_runs" r where r."id" = begin_import_session.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_status <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  perform set_config('better_supabase.import_run', begin_import_session.run::text, true);
  perform set_config('better_supabase.correlation_id', 'import:' || begin_import_session.run::text, true);
  perform set_config('better_supabase.import_events', '{}', true);
  perform set_config('better_supabase.import_audit', 'rows', true);
  return begin_import_session.run;
end;
$$;
revoke execute on function "better_supabase"."begin_import_session"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."begin_import_session"(uuid) to service_role;

-- The single write path of an import (service role). It begins the import
-- session for its writes and restores the caller's settings afterwards. A dry
-- run writes inside a subtransaction it rolls back, then keeps the counts.
create or replace function "better_supabase"."import_upsert_batch"(run uuid, entity text, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := import_upsert_batch.run;
  v_entity text := import_upsert_batch.entity;
  v_run "better_supabase"."import_runs";
  v_result jsonb;
  v_name text;
  v_previous jsonb := '{}'::jsonb;
begin
  -- No row lock here: two batches of one run write at the same time, and the
  -- counts update at the end is the only statement that locks the run row.
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  if coalesce((v_run."plan" ->> 'unordered')::boolean, false) is distinct from true
    and jsonb_typeof(v_run."plan" -> 'waves') = 'array'
    and exists (
      select 1 from jsonb_array_elements(v_run."plan" -> 'waves') with ordinality as w(wave, n)
      where w.wave ? v_entity and exists (
        select 1 from jsonb_array_elements(v_run."plan" -> 'waves') with ordinality as earlier(wave, n)
        cross join lateral jsonb_array_elements_text(earlier.wave) dep(entity)
        join "better_supabase"."import_chunks" c on c."run_id" = v_run_id
          and c."entity" = dep.entity and c."status" <> 'done'
        where earlier.n < w.n)) then
    raise exception 'an earlier import wave still has open chunks' using errcode = '55000', hint = 'IMPORT_DEPENDENCY_OPEN';
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    v_previous := v_previous || jsonb_build_object(v_name, coalesce(current_setting(v_name, true), ''));
  end loop;
  perform "better_supabase"."begin_import_session"(v_run_id);
  perform set_config('better_supabase.search_deferred', 'on', true);

  if v_run."dry_run" then
    begin
      v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
      raise exception 'dry run' using errcode = 'BSDRY';
    exception when sqlstate 'BSDRY' then
      null;
    end;
  else
    v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
    perform "better_supabase"."search_refresh_dirty"();
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    perform set_config(v_name, v_previous ->> v_name, true);
  end loop;

  update "better_supabase"."import_runs" r set
    "counts" = jsonb_set(r."counts", array[v_entity], jsonb_build_object(
      'inserted', coalesce(r."counts" -> v_entity ->> 'inserted', '0')::integer + coalesce((v_result ->> 'inserted')::integer, 0),
      'updated', coalesce(r."counts" -> v_entity ->> 'updated', '0')::integer + coalesce((v_result ->> 'updated')::integer, 0),
      'unchanged', coalesce(r."counts" -> v_entity ->> 'unchanged', '0')::integer + coalesce((v_result ->> 'unchanged')::integer, 0),
      'conflicted', coalesce(r."counts" -> v_entity ->> 'conflicted', '0')::integer + coalesce((v_result ->> 'conflicted')::integer, 0),
      'missing', coalesce((r."counts" -> v_entity ->> 'missing')::integer, 0)
    )),
    "errors" = r."errors" || coalesce(v_result -> 'errors', '[]'::jsonb),
    "diff" = (select coalesce(jsonb_agg(d.value), '[]'::jsonb) from (
      select value from jsonb_array_elements(r."diff" || coalesce(v_result -> 'diff', '[]'::jsonb)) value limit 100
    ) d)
  where r."id" = v_run_id;
  return v_result || jsonb_build_object('dryRun', v_run."dry_run");
end;
$$;
revoke execute on function "better_supabase"."import_upsert_batch"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_upsert_batch"(uuid, text, jsonb) to service_role;

-- Bulk external key to subject. keys is an array of text, or of { key, scope,
-- role }; a scope that aliases another resolves through it.
create or replace function "better_supabase"."import_resolve"(run uuid, entity text, keys jsonb)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = import_resolve.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if jsonb_typeof(import_resolve.keys) <> 'array' then
    raise exception 'keys must be an array' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('key', q.key, 'scope', q.scope, 'role', q.role, 'subjectType', m."subject_type", 'subjectId', m."subject_id") order by q.ord)
    from (
      select k.ord,
        case when jsonb_typeof(k.value) = 'string' then k.value #>> '{}' else k.value ->> 'key' end as key,
        case when jsonb_typeof(k.value) = 'string' then '' else coalesce(k.value ->> 'scope', '') end as scope,
        case when jsonb_typeof(k.value) = 'string' then 'primary' else coalesce(k.value ->> 'role', 'primary') end as role
      from jsonb_array_elements(import_resolve.keys) with ordinality k(value, ord)
    ) q
    join lateral (
      select x."subject_type", x."subject_id"
      from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source"
        and x."entity" = import_resolve.entity and x."external_key" = q.key and x."role" = q.role
        and (x."scope" = q.scope or x."scope" in (
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = q.scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? import_resolve.entity)
        ))
      order by (x."scope" = q.scope) desc
      limit 1
    ) m on true
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."import_resolve"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_resolve"(uuid, text, jsonb) to service_role;

-- Closes a run that wrote through import_upsert_batch. A full run marks the
-- records of its entities it didn't see, and never deletes them.
create or replace function "better_supabase"."finish_import_run"(run uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := finish_import_run.run;
  v_run "better_supabase"."import_runs";
  v_entity text;
  v_missing integer;
  v_total integer := 0;
  v_counts jsonb;
  v_outcome text := 'completed';
  v_expected integer;
  v_applied integer;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  v_counts := v_run."counts";

  if v_run."full" then
    for v_entity in select k.key from jsonb_object_keys(v_run."counts") k(key) loop
      select count(*)::integer into v_missing from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
        and x."role" = 'primary' and x."last_run_id" <> v_run_id
        and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      if not v_run."dry_run" then
        update "better_supabase"."import_records" x set "went_missing_at" = coalesce(x."went_missing_at", now())
        where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
          and x."last_run_id" <> v_run_id
          and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  if v_run."plan" is not null and jsonb_typeof(v_run."plan") = 'object' then
    for v_entity in select k.key from jsonb_object_keys(v_run."plan") k(key) loop
      v_expected := coalesce((v_run."plan" ->> v_entity)::integer, 0);
      v_applied := coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'unchanged')::integer, 0);
      if v_applied < v_expected then
        v_outcome := 'incomplete';
        v_counts := jsonb_set(coalesce(v_counts, '{}'::jsonb), array[v_entity, 'missing'], to_jsonb(v_expected - v_applied), true);
      end if;
    end loop;
  end if;
  if v_outcome = 'completed' and (jsonb_array_length(coalesce(v_run."errors", '[]'::jsonb)) > 0 or v_counts::text like '%"conflicted":%') then
    v_outcome := 'completed_with_issues';
  end if;

  update "better_supabase"."import_runs" r set "status" = 'completed', "outcome" = v_outcome, "finished_at" = now(), "counts" = v_counts
  where r."id" = v_run_id;

  if not v_run."dry_run" then
    for v_entity in select k.key from jsonb_object_keys(v_counts) k(key) loop
      v_total := v_total + coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0);
      perform "better_supabase".emit_event('import.entity_completed', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'entity', v_entity, 'counts', v_counts -> v_entity), 'imports/' || v_run_id::text, (v_run."tenant_id")::text, null, 'better-supabase/imports');
    end loop;
    perform "better_supabase".emit_event('import.completed', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'count', v_total), 'imports/' || v_run_id::text, (v_run."tenant_id")::text, null, 'better-supabase/imports');
  end if;
  return v_counts;
end;
$$;
revoke execute on function "better_supabase"."finish_import_run"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."finish_import_run"(uuid) to service_role;

create or replace function "better_supabase"."heartbeat_import_run"(run uuid, seconds integer default 30)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_until timestamptz;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can heartbeat an import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  update "better_supabase"."import_runs" r set "heartbeat_at" = now(), "lease_until" = now() + make_interval(secs => greatest(heartbeat_import_run.seconds, 1))
  where r."id" = heartbeat_import_run.run and r."status" = 'running'
  returning r."lease_until" into v_until;
  if v_until is null then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  return v_until;
end;
$$;
revoke execute on function "better_supabase"."heartbeat_import_run"(uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."heartbeat_import_run"(uuid, integer) to service_role;

create or replace function "better_supabase"."import_ensure_ref"(tenant uuid, kind text, key text, defaults jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_created boolean := false;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can ensure an import ref' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if import_ensure_ref.kind is null or import_ensure_ref.key is null or import_ensure_ref.key = '' then
    raise exception 'a ref needs a kind and a key' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select r."id" into v_id from "better_supabase".import_refs r
  where r."tenant_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
  if v_id is null then
    insert into "better_supabase".import_refs ("tenant_id", "kind", "key", "payload")
    values (import_ensure_ref.tenant, import_ensure_ref.kind, import_ensure_ref.key, coalesce(import_ensure_ref.defaults, '{}'::jsonb))
    on conflict ("tenant_id", "kind", "key") do nothing
    returning "id" into v_id;
    v_created := v_id is not null;
    if v_id is null then
      select r."id" into v_id from "better_supabase".import_refs r
      where r."tenant_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
    end if;
  end if;
  return jsonb_build_object(
    'id', v_id,
    'created', v_created,
    'warnings', case when v_created then jsonb_build_array(jsonb_build_object('code', 'IMPORT_REF_CREATED', 'kind', import_ensure_ref.kind, 'key', import_ensure_ref.key)) else '[]'::jsonb end
  );
end;
$$;
revoke execute on function "better_supabase"."import_ensure_ref"(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_ensure_ref"(uuid, text, text, jsonb) to service_role;

create or replace function "better_supabase"."import_entities"()
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$ select array['organization_profile', 'attachment', 'data_lifecycle_row', 'field_value', 'supplier_item', 'product_identifier', 'discount_group', 'discount_rule', 'party_discount_group', 'product', 'product_category', 'stock_count', 'order', 'payment_term', 'document_delivery_preference', 'party', 'party_contact', 'contact_method', 'party_location', 'party_bank_account', 'quote', 'invoice', 'credit_note', 'open_item', 'invoice_allocation', 'meter_reading', 'due_check', 'asset', 'asset_identifier', 'accounting_account', 'accounting_journal', 'accounting_entry', 'accounting_opening_balance', 'tax_code', 'tax_rate', 'document_template', 'document_text_block']::text[] $$;
revoke execute on function "better_supabase"."import_entities"() from public, anon, authenticated;
grant execute on function "better_supabase"."import_entities"() to service_role;


create or replace function "better_supabase"."rebase_import_records"(tenant uuid, source text, entities text[] default null, keys text[] default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can rebase import records' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  update "better_supabase"."import_records" x
  set "subject_imported_updated_at" = coalesce((case x."entity" when 'organization_profile' then "better_supabase"."organization_profile_updated_at"(x."subject_id") when 'supplier_item' then "better_supabase"."supplier_item_updated_at"(x."subject_id") when 'product_identifier' then "better_supabase"."product_identifier_updated_at"(x."subject_id") when 'discount_group' then "better_supabase"."discount_group_updated_at"(x."subject_id") when 'discount_rule' then "better_supabase"."discount_rule_updated_at"(x."subject_id") when 'product' then "better_supabase"."product_updated_at"(x."subject_id") when 'product_category' then "better_supabase"."product_category_updated_at"(x."subject_id") when 'stock_count' then "better_supabase"."stock_count_updated_at"(x."subject_id") when 'order' then "better_supabase"."order_updated_at"(x."subject_id") when 'payment_term' then "better_supabase"."payment_term_updated_at"(x."subject_id") when 'document_delivery_preference' then "better_supabase"."document_delivery_preference_updated_at"(x."subject_id") when 'party' then "better_supabase"."party_updated_at"(x."subject_id") when 'party_contact' then "better_supabase"."party_contact_updated_at"(x."subject_id") when 'contact_method' then "better_supabase"."contact_method_updated_at"(x."subject_id") when 'party_location' then "better_supabase"."party_location_updated_at"(x."subject_id") when 'party_bank_account' then "better_supabase"."party_bank_account_updated_at"(x."subject_id") when 'quote' then "better_supabase"."quote_updated_at"(x."subject_id") when 'invoice' then "better_supabase"."invoice_updated_at"(x."subject_id") when 'credit_note' then "better_supabase"."invoice_updated_at"(x."subject_id") when 'open_item' then "better_supabase"."invoice_updated_at"(x."subject_id") when 'invoice_allocation' then "better_supabase"."invoice_updated_at"(x."subject_id") when 'due_check' then "better_supabase"."due_check_updated_at"(x."subject_id") when 'asset' then "better_supabase"."asset_updated_at"(x."subject_id") when 'asset_identifier' then "better_supabase"."asset_identifier_updated_at"(x."subject_id") when 'tax_code' then "better_supabase"."tax_code_updated_at"(x."subject_id") when 'document_template' then "better_supabase"."document_template_updated_at"(x."subject_id") when 'document_text_block' then "better_supabase"."document_text_block_updated_at"(x."subject_id") else null end), x."subject_imported_updated_at"),
      "owned_hash" = coalesce((null), x."owned_hash")
  where x."tenant_id" = rebase_import_records.tenant
    and x."source" = rebase_import_records.source
    and (rebase_import_records.entities is null or x."entity" = any (rebase_import_records.entities))
    and (rebase_import_records.keys is null or x."external_key" = any (rebase_import_records.keys));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."rebase_import_records"(uuid, text, text[], text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."rebase_import_records"(uuid, text, text[], text[]) to service_role;


-- Queues one job per chunk of an entity's items, so a worker writes a large
-- import in batches; the dedupe key makes a retry harmless.
create or replace function "better_supabase"."enqueue_import_chunks"(run uuid, entity text, chunks integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
  v_chunk integer;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = enqueue_import_chunks.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if enqueue_import_chunks.chunks is null or enqueue_import_chunks.chunks < 1 then
    raise exception 'chunks must be at least 1' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  for v_chunk in 0 .. enqueue_import_chunks.chunks - 1 loop
    perform "better_supabase"."enqueue_job"(queue => 'imports', payload => jsonb_build_object('run', v_run."id", 'entity', enqueue_import_chunks.entity, 'chunk', v_chunk), dedupe_key => v_run."id"::text || ':' || enqueue_import_chunks.entity || ':' || v_chunk::text, dedupe_running => false);
  end loop;
  return enqueue_import_chunks.chunks;
end;
$$;
revoke execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) to service_role;

-- Stores the items of one chunk of an entity, ready for a worker. Storing a chunk
-- again before it is done replaces its items; a done chunk is left as it is and
-- the answer is false.
create or replace function "better_supabase"."store_import_chunk"(run uuid, entity text, chunk integer, items jsonb)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = store_import_chunk.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if store_import_chunk.chunk is null or store_import_chunk.chunk < 0 or jsonb_typeof(store_import_chunk.items) is distinct from 'array' then
    raise exception 'a chunk has a number from 0 and an array of items' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  insert into "better_supabase"."import_chunks" ("run_id", "tenant_id", "entity", "chunk", "items")
  values (store_import_chunk.run, v_run."tenant_id", store_import_chunk.entity, store_import_chunk.chunk, store_import_chunk.items)
  on conflict ("run_id", "entity", "chunk") do update
    set "items" = excluded."items", "status" = 'pending', "claimed_at" = null
    where "better_supabase"."import_chunks"."status" <> 'done';
  return found;
end;
$$;
revoke execute on function "better_supabase"."store_import_chunk"(uuid, text, integer, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."store_import_chunk"(uuid, text, integer, jsonb) to service_role;

-- Takes a pending chunk, or one whose claim is older than lease seconds (a worker
-- that died), and returns { entity, chunk, items }. Null when the chunk is done,
-- missing or held by a live worker. Rows another worker holds are skipped, not waited for.
create or replace function "better_supabase"."claim_import_chunk"(run uuid, entity text, chunk integer, lease integer default 300)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_items jsonb;
begin
  with pick as (
    select x."run_id", x."entity", x."chunk"
    from "better_supabase"."import_chunks" x
    where x."run_id" = claim_import_chunk.run and x."entity" = claim_import_chunk.entity and x."chunk" = claim_import_chunk.chunk
      and (x."status" = 'pending' or (x."status" = 'claimed' and x."claimed_at" < now() - make_interval(secs => greatest(claim_import_chunk.lease, 1))))
    for update skip locked
  )
  update "better_supabase"."import_chunks" x set "status" = 'claimed', "claimed_at" = now()
  from pick
  where x."run_id" = pick."run_id" and x."entity" = pick."entity" and x."chunk" = pick."chunk"
  returning x."items" into v_items;
  if v_items is null then
    return null;
  end if;
  return jsonb_build_object('entity', claim_import_chunk.entity, 'chunk', claim_import_chunk.chunk, 'items', v_items);
end;
$$;
revoke execute on function "better_supabase"."claim_import_chunk"(uuid, text, integer, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."claim_import_chunk"(uuid, text, integer, integer) to service_role;

-- Marks a claimed chunk done and keeps what its batch answered.
create or replace function "better_supabase"."complete_import_chunk"(run uuid, entity text, chunk integer, result jsonb)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
begin
  update "better_supabase"."import_chunks" x set "status" = 'done', "done_at" = now(), "result" = complete_import_chunk.result
  where x."run_id" = complete_import_chunk.run and x."entity" = complete_import_chunk.entity
    and x."chunk" = complete_import_chunk.chunk and x."status" = 'claimed';
  return found;
end;
$$;
revoke execute on function "better_supabase"."complete_import_chunk"(uuid, text, integer, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_import_chunk"(uuid, text, integer, jsonb) to service_role;

-- One worker step: claim the chunk, write it with import_upsert_batch and mark it
-- done, in one transaction, so a failure leaves the chunk pending for the next try.
-- A chunk that is done answers what its batch answered; one that is missing or
-- held by another worker answers { skipped: true }.
create or replace function "better_supabase"."process_import_chunk"(run uuid, entity text, chunk integer)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_done jsonb;
  v_claim jsonb;
  v_result jsonb;
begin
  select x."result" into v_done from "better_supabase"."import_chunks" x
  where x."run_id" = process_import_chunk.run and x."entity" = process_import_chunk.entity
    and x."chunk" = process_import_chunk.chunk and x."status" = 'done';
  if found then
    return coalesce(v_done, '{}'::jsonb) || jsonb_build_object('done', true);
  end if;
  v_claim := "better_supabase"."claim_import_chunk"(process_import_chunk.run, process_import_chunk.entity, process_import_chunk.chunk);
  if v_claim is null then
    return jsonb_build_object('skipped', true);
  end if;
  v_result := "better_supabase"."import_upsert_batch"(process_import_chunk.run, process_import_chunk.entity, v_claim -> 'items');
  perform "better_supabase"."complete_import_chunk"(process_import_chunk.run, process_import_chunk.entity, process_import_chunk.chunk, v_result);
  return v_result;
end;
$$;
revoke execute on function "better_supabase"."process_import_chunk"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."process_import_chunk"(uuid, text, integer) to service_role;

-- How many chunks of a run are pending, claimed and done, so a caller knows when to
-- finish the run.
create or replace function "better_supabase"."import_chunk_progress"(run uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'pending', count(*) filter (where x."status" = 'pending'),
    'claimed', count(*) filter (where x."status" = 'claimed'),
    'done', count(*) filter (where x."status" = 'done')
  )
  from "better_supabase"."import_chunks" x
  where x."run_id" = import_chunk_progress.run
$$;
revoke execute on function "better_supabase"."import_chunk_progress"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."import_chunk_progress"(uuid) to service_role;

-- Clears the content hash of the records of a source (and entity) that a run of
-- another mapper version last wrote, so the next import treats them as changed and
-- rewrites them through their target (a row a user changed since stays as it is, as
-- for any changed hash). Returns how many records it cleared.
create or replace function "better_supabase"."reapply_import_records"(tenant uuid, source text, mapper_version text, entity text default null)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_count integer;
begin
  update "better_supabase"."import_records" x set "content_hash" = ''
  where x."tenant_id" = reapply_import_records.tenant and x."source" = reapply_import_records.source
    and (reapply_import_records.entity is null or x."entity" = reapply_import_records.entity)
    and x."content_hash" <> ''
    and (select r."mapper_version" from "better_supabase"."import_runs" r where r."id" = x."last_run_id") is distinct from reapply_import_records.mapper_version;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."reapply_import_records"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."reapply_import_records"(uuid, text, text, text) to service_role;

-- The record map of a source as { entity, scope, key, role, hash, subjectType,
-- subjectId }, one object per record in key order, so a caller can compare what the
-- source sends with what was imported without reading the rows.
create or replace function "better_supabase"."export_import_hashes"(tenant uuid, source text, entity text default null)
returns setof jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('entity', x."entity", 'scope', x."scope", 'key', x."external_key", 'role', x."role",
    'hash', x."content_hash", 'subjectType', x."subject_type", 'subjectId', x."subject_id")
  from "better_supabase"."import_records" x
  where x."tenant_id" = export_import_hashes.tenant and x."source" = export_import_hashes.source
    and (export_import_hashes.entity is null or x."entity" = export_import_hashes.entity)
  order by x."entity", x."scope", x."external_key", x."role"
$$;
revoke execute on function "better_supabase"."export_import_hashes"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."export_import_hashes"(uuid, text, text) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."import_runs" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."import_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."import_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."import_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."import_records" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."import_records" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."import_records" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."import_records" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_064_imports.sql
-- better-supabase module: imports
-- @bsb-block-data imports
-- @bsb-hash sha256:03c82178dd5c9af38535aa92f90002ada8c21fab4dadb8d91c33605f8bdcec29
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('imports', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_064_imports.sql
-- better-supabase module: imports
-- @bsb-block imports@2 managed
-- @bsb-hash sha256:2b7dab2d9c4e9f96e48791f948c2887acb75e03b1b3d146ec51b88f92ede7d88
-- Import runs and the external record map. import_upsert_batch writes items through the targets blocks and the app register, skips equal content, reports rows a user changed since the last import and marks missing keys on full runs. The dry run, parsing and mapping live in TypeScript.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
create table "app_private"."import_runs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "source" text not null,
  "status" text not null default 'pending',
  "mapping" jsonb not null default '{}'::jsonb,
  "counts" jsonb not null default '{}'::jsonb,
  "errors" jsonb not null default '[]'::jsonb,
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
alter table "app_private"."import_runs" add column "dry_run" boolean not null default false;
alter table "app_private"."import_runs" add column "diff" jsonb not null default '[]'::jsonb;
alter table "app_private"."import_runs" add column "full" boolean not null default false;
alter table "app_private"."import_runs" add column "input_checksum" text;
alter table "app_private"."import_runs" add column "correlation_id" text;
alter table "app_private"."import_runs" add column "mapper_version" text;
alter table "app_private"."import_runs" add column "scope_aliases" jsonb not null default '[]'::jsonb;
alter table "app_private"."import_runs" add column "started_at" timestamptz;
alter table "app_private"."import_runs" add column "finished_at" timestamptz;
alter table "app_private"."import_runs" add column "plan" jsonb;
alter table "app_private"."import_runs" add column "outcome" text;
alter table "app_private"."import_runs" add column "lease_until" timestamptz;
alter table "app_private"."import_runs" add column "heartbeat_at" timestamptz;
alter table "app_private"."import_runs" add constraint "bsb_import_runs_status"
  check ("status" in ('pending', 'running', 'completed', 'failed', 'canceled'));
alter table "app_private"."import_runs" enable row level security;
revoke all on "app_private"."import_runs" from public, anon, authenticated;
grant select on "app_private"."import_runs" to authenticated;
grant all on "app_private"."import_runs" to service_role;
create index "import_runs_tenant_idx" on "app_private"."import_runs" ("tenant_id");
-- One pending or running run per organization and source.
create unique index "import_runs_active_idx" on "app_private"."import_runs" ("tenant_id", "source") where "status" in ('pending', 'running');

create table "app_private"."import_records" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "source" text not null,
  "scope" text not null default '',
  "entity" text not null,
  "external_key" text not null,
  "role" text not null default 'primary',
  "subject_type" text not null,
  "subject_id" text not null,
  "content_hash" text not null,
  "first_run_id" uuid not null,
  "last_run_id" uuid not null,
  "subject_imported_updated_at" timestamptz,
  "source_updated_at" timestamptz,
  "owned_hash" text,
  "went_missing_at" timestamptz,
  constraint "import_records_key" unique ("tenant_id", "source", "scope", "entity", "external_key", "role")
);
create index "import_records_subject_idx" on "app_private"."import_records" ("tenant_id", "subject_type", "subject_id");
alter table "app_private"."import_records" enable row level security;
revoke all on "app_private"."import_records" from public, anon, authenticated;
grant select on "app_private"."import_records" to authenticated;
grant all on "app_private"."import_records" to service_role;
create table "app_private".import_refs (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null,
  "key" text not null,
  "payload" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now(),
  constraint import_refs_key unique ("tenant_id", "kind", "key")
);

create table "app_private"."import_chunks" (
  "run_id" uuid not null references "app_private"."import_runs" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "entity" text not null,
  "chunk" integer not null,
  "items" jsonb not null,
  "status" text not null default 'pending',
  "result" jsonb,
  "claimed_at" timestamptz,
  "done_at" timestamptz,
  "created_at" timestamptz not null default now(),
  primary key ("run_id", "entity", "chunk")
);
alter table "app_private"."import_chunks" add constraint "bsb_import_chunks_status"
  check ("status" in ('pending', 'claimed', 'done'));
alter table "app_private"."import_chunks" enable row level security;
revoke all on "app_private"."import_chunks" from public, anon, authenticated;
grant all on "app_private"."import_chunks" to service_role;
create index "import_chunks_tenant_idx" on "app_private"."import_chunks" ("tenant_id");


create table "app_private".import_run_issues (
  "id" uuid primary key default gen_random_uuid(),
  "run_id" uuid not null,
  "tenant_id" uuid not null,
  "source" text not null,
  "entity" text not null,
  "key" text not null,
  "kind" text not null,
  "code" text not null,
  "message" text not null,
  "created_at" timestamptz not null default now(),
  "resolved_at" timestamptz,
  constraint bsb_import_run_issues_kind check ("kind" in ('conflict', 'error', 'warning'))
);
create index import_run_issues_open_idx
  on "app_private".import_run_issues ("tenant_id", "source", "entity", "key")
  where "resolved_at" is null;
create index import_run_issues_run_idx
  on "app_private".import_run_issues ("run_id", "entity");

create or replace function "app_private"."start_import_run"(tenant uuid, source text, options jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_options jsonb := coalesce(start_import_run.options, '{}'::jsonb);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', start_import_run.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if start_import_run.source is null or start_import_run.source = '' then
    raise exception 'an import run needs a source' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(coalesce(v_options -> 'scopeAliases', '[]'::jsonb)) <> 'array' then
    raise exception 'scopeAliases must be an array of { scope, of, entities }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    insert into "app_private"."import_runs" as r ("tenant_id", "source", "mapping", "dry_run", "full", "input_checksum", "correlation_id", "mapper_version", "scope_aliases", "plan", "lease_until", "created_by")
    values (
      start_import_run.tenant,
      start_import_run.source,
      coalesce(v_options -> 'mapping', '{}'::jsonb),
      coalesce((v_options ->> 'dryRun')::boolean, false),
      coalesce((v_options ->> 'full')::boolean, false),
      v_options ->> 'inputChecksum',
      v_options ->> 'correlationId',
      nullif(v_options ->> 'mapperVersion', ''),
      coalesce(v_options -> 'scopeAliases', '[]'::jsonb),
      v_options -> 'plan',
      now() + interval '30 seconds',
      auth.uid()
    )
    returning r."id" into v_id;
  exception when unique_violation then
    raise exception 'an import of this source is already pending or running' using errcode = '55P03', hint = 'IMPORT_RUN_ACTIVE';
  end;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "app_private"."start_import_run"(uuid, text, jsonb) from public, anon;
grant execute on function "app_private"."start_import_run"(uuid, text, jsonb) to authenticated, service_role;

-- The first release's entry point: a run without options.
create or replace function "app_private"."start_import"(tenant uuid, source text, mapping jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select "app_private"."start_import_run"(start_import.tenant, start_import.source, jsonb_build_object('mapping', coalesce(start_import.mapping, '{}'::jsonb)));
$$;
revoke execute on function "app_private"."start_import"(uuid, text, jsonb) from public, anon;
grant execute on function "app_private"."start_import"(uuid, text, jsonb) to authenticated, service_role;

create or replace function "app_private"."get_import_run"(id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_run "app_private"."import_runs";
begin
  select * into v_run from "app_private"."import_runs" r where r."id" = get_import_run.id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_run."tenant_id", 'imports.manage'), false)) then
    raise exception 'not allowed to read this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."tenant_id", 'source', v_run."source", 'status', v_run."status", 'outcome', v_run."outcome", 'plan', v_run."plan", 'mapping', v_run."mapping", 'counts', v_run."counts", 'errors', v_run."errors", 'dryRun', v_run."dry_run", 'full', v_run."full", 'inputChecksum', v_run."input_checksum", 'correlationId', v_run."correlation_id", 'mapperVersion', v_run."mapper_version", 'scopeAliases', v_run."scope_aliases", 'leaseUntil', v_run."lease_until", 'heartbeatAt', v_run."heartbeat_at", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'startedAt', v_run."started_at", 'finishedAt', v_run."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "app_private".import_run_issues i
    where i."run_id" = v_run."id"
  ));
end;
$$;
revoke execute on function "app_private"."get_import_run"(uuid) from public, anon;
grant execute on function "app_private"."get_import_run"(uuid) to authenticated, service_role;

create or replace function "app_private"."list_import_runs"(tenant uuid, source text default null, status text default null, row_limit integer default 50)
returns setof jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_import_runs.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list imports' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  return query
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'source', r."source", 'status', r."status", 'outcome', r."outcome", 'plan', r."plan", 'mapping', r."mapping", 'counts', r."counts", 'errors', r."errors", 'dryRun', r."dry_run", 'full', r."full", 'inputChecksum', r."input_checksum", 'correlationId', r."correlation_id", 'mapperVersion', r."mapper_version", 'scopeAliases', r."scope_aliases", 'leaseUntil', r."lease_until", 'heartbeatAt', r."heartbeat_at", 'createdBy', r."created_by", 'createdAt', r."created_at", 'startedAt', r."started_at", 'finishedAt', r."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "app_private".import_run_issues i
    where i."run_id" = r."id"
  ))
    from "app_private"."import_runs" r
    where r."tenant_id" = list_import_runs.tenant
      and (list_import_runs.source is null or r."source" = list_import_runs.source)
      and (list_import_runs.status is null or r."status" = list_import_runs.status)
    order by r."created_at" desc, r."id" desc
    limit least(greatest(coalesce(list_import_runs.row_limit, 50), 1), 200);
end;
$$;
revoke execute on function "app_private"."list_import_runs"(uuid, text, text, integer) from public, anon;
grant execute on function "app_private"."list_import_runs"(uuid, text, text, integer) to authenticated, service_role;

create or replace function "app_private"."cancel_import_run"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_run "app_private"."import_runs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_run from "app_private"."import_runs" r where r."id" = cancel_import_run.id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_run."tenant_id", 'imports.manage'), false)) then
    raise exception 'not allowed to cancel this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if v_run."status" not in ('pending', 'running') then
    raise exception 'this import already finished' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  update "app_private"."import_runs" r set "status" = 'canceled', "finished_at" = now()
  where r."id" = cancel_import_run.id;
  return true;
end;
$$;
revoke execute on function "app_private"."cancel_import_run"(uuid) from public, anon;
grant execute on function "app_private"."cancel_import_run"(uuid) to authenticated, service_role;

-- The run moves from pending to running before the first batch, so a run
-- that dies mid-way is visible as running rather than pending.
create or replace function "app_private"."mark_import_running"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  update "app_private"."import_runs" set "status" = 'running', "started_at" = now()
  where "id" = mark_import_running.id and "status" = 'pending';
  if not found then
    raise exception 'no pending import with this id' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  return true;
end;
$$;
revoke execute on function "app_private"."mark_import_running"(uuid) from public, anon, authenticated;
grant execute on function "app_private"."mark_import_running"(uuid) to service_role;

-- Closes a run whose rows the caller wrote itself (`defineImport` without a
-- target); `finish_import_run` closes a run that used `import_upsert_batch`.
create or replace function "app_private"."finish_import"(id uuid, status text, count integer, error text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_source text;
begin
  update "app_private"."import_runs" set "status" = finish_import.status,
    "finished_at" = now(),
    "counts" = case when finish_import.status = 'completed' then jsonb_build_object("source", jsonb_build_object('inserted', finish_import.count, 'updated', 0, 'unchanged', 0, 'conflicted', 0, 'missing', 0)) else "counts" end,
    "errors" = case when finish_import.error is null then "errors" else "errors" || jsonb_build_array(jsonb_build_object('entity', "source", 'key', null, 'code', 'IMPORT_ITEM_INVALID', 'message', finish_import.error)) end
  where "id" = finish_import.id
  returning "tenant_id", "source" into v_tenant, v_source;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if finish_import.status = 'failed' then
    null;
  else
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "app_private"."finish_import"(uuid, text, integer, text) from public, anon, authenticated;
grant execute on function "app_private"."finish_import"(uuid, text, integer, text) to service_role;

create or replace function "app_private"."import_note_issue"(run uuid, entity text, key text, kind text, code text, message text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_source text;
begin
  select r."tenant_id", r."source" into v_tenant, v_source
  from "app_private"."import_runs" r where r."id" = import_note_issue.run;
  if v_tenant is null or import_note_issue.key is null or import_note_issue.key = '' then
    return;
  end if;
  insert into "app_private".import_run_issues ("run_id", "tenant_id", "source", "entity", "key", "kind", "code", "message")
  values (import_note_issue.run, v_tenant, v_source, import_note_issue.entity, import_note_issue.key, import_note_issue.kind, import_note_issue.code, import_note_issue.message);
end;
$$;

create or replace function "app_private"."import_note_warnings"(run uuid, entity text, warnings jsonb)
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
    perform "app_private"."import_note_issue"(
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

create or replace function "app_private"."import_clear_issues"(run uuid, entity text, key text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_source text;
begin
  select r."tenant_id", r."source" into v_tenant, v_source
  from "app_private"."import_runs" r where r."id" = import_clear_issues.run;
  if v_tenant is null then
    return;
  end if;
  update "app_private".import_run_issues i set "resolved_at" = now()
  where i."tenant_id" = v_tenant and i."source" = v_source
    and i."entity" = import_clear_issues.entity and i."key" = import_clear_issues.key
    and i."resolved_at" is null;
end;
$$;

create or replace function "app_private"."list_import_issues"(run uuid, entity text default null, row_limit integer default 50, row_offset integer default 0)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_total integer;
  v_rows jsonb;
begin
  select r."tenant_id" into v_tenant from "app_private"."import_runs" r where r."id" = list_import_issues.run;
  if v_tenant is null then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list import issues' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  select count(*) into v_total from "app_private".import_run_issues i
  where i."run_id" = list_import_issues.run
    and (list_import_issues.entity is null or i."entity" = list_import_issues.entity);
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_rows from (
    select i."entity", i."key", i."kind", i."code", i."message", i."created_at", i."resolved_at"
    from "app_private".import_run_issues i
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
revoke execute on function "app_private"."list_import_issues"(uuid, text, integer, integer) from public, anon;
grant execute on function "app_private"."list_import_issues"(uuid, text, integer, integer) to authenticated, service_role;

-- Counts and the first changed fields of a dry run. The dry run itself writes
-- no subject rows; the diff is what the batch returned.
create or replace function "app_private"."list_import_diff"(run uuid, entity text default null, row_limit integer default 50, row_offset integer default 0)
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
  select r."counts", r."diff" into v_counts, v_diff from "app_private"."import_runs" r where r."id" = list_import_diff.run;
  if v_counts is null then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
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
revoke execute on function "app_private"."list_import_diff"(uuid, text, integer, integer) from public, anon;
grant execute on function "app_private"."list_import_diff"(uuid, text, integer, integer) to authenticated, service_role;

create or replace function "app_private"."resolve_import_conflict"(tenant uuid, source text, entity text, key text, action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resolved integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', resolve_import_conflict.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to resolve an import conflict' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if resolve_import_conflict.action = 'keep' then
    update "app_private"."import_records" x set "subject_imported_updated_at" = now()
    where x."tenant_id" = resolve_import_conflict.tenant
      and x."source" = resolve_import_conflict.source
      and x."entity" = resolve_import_conflict.entity
      and x."external_key" = resolve_import_conflict.key;
  elsif resolve_import_conflict.action = 'overwrite' then
    update "app_private"."import_records" x set "subject_imported_updated_at" = null, "owned_hash" = null
    where x."tenant_id" = resolve_import_conflict.tenant
      and x."source" = resolve_import_conflict.source
      and x."entity" = resolve_import_conflict.entity
      and x."external_key" = resolve_import_conflict.key;
  else
    raise exception 'action must be keep or overwrite' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  update "app_private".import_run_issues i set "resolved_at" = now()
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
revoke execute on function "app_private"."resolve_import_conflict"(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function "app_private"."resolve_import_conflict"(uuid, text, text, text, text) to service_role;
revoke execute on function "app_private"."resolve_import_conflict"(uuid, text, text, text, text) from public, anon;
grant execute on function "app_private"."resolve_import_conflict"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "app_private"."import_integrity"(tenant uuid, source text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_checks jsonb := '[]'::jsonb;
  v_name text;
  v_severity text;
  v_count integer;
  v_ids jsonb;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', import_integrity.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to check this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  for v_name, v_severity, v_count, v_ids in
    select 'duplicate_keys', 'error', count(*)::integer, coalesce(jsonb_agg(sample), '[]'::jsonb) from (
      select min(d."id"::text) as sample from "app_private"."import_records" d
      where d."tenant_id" = import_integrity.tenant
        and (import_integrity.source is null or d."source" = import_integrity.source)
      group by d."entity", d."external_key"
      having count(distinct d."subject_id") > 1
    ) q
  loop
    v_checks := v_checks || jsonb_build_array(jsonb_build_object(
      'name', v_name, 'severity', v_severity, 'count', v_count, 'ids', coalesce(v_ids, '[]'::jsonb)));
  end loop;
  return jsonb_build_object('checks', v_checks);
end;
$$;
revoke execute on function "app_private"."import_integrity"(uuid, text) from public, anon, authenticated;
grant execute on function "app_private"."import_integrity"(uuid, text) to service_role;
revoke execute on function "app_private"."import_integrity"(uuid, text) from public, anon;
grant execute on function "app_private"."import_integrity"(uuid, text) to authenticated, service_role;

create table "app_private".import_sources (
  "id" text primary key,
  "label_key" text not null,
  "description_key" text not null,
  "file_types" text[] not null default '{}',
  "entities" text[] not null default '{}',
  "docs_link" text
);

create or replace function "app_private"."register_import_source"(id text, label_key text, description_key text, file_types text[], entities text[], docs_link text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'not allowed to register an import source' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  insert into "app_private".import_sources ("id", "label_key", "description_key", "file_types", "entities", "docs_link")
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
revoke execute on function "app_private"."register_import_source"(text, text, text, text[], text[], text) from public, anon, authenticated;
grant execute on function "app_private"."register_import_source"(text, text, text, text[], text[], text) to service_role;

create or replace function "app_private"."list_import_sources"()
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
  from "app_private".import_sources s
$$;
revoke execute on function "app_private"."list_import_sources"() from public, anon;
grant execute on function "app_private"."list_import_sources"() to authenticated, service_role;

-- Every run of the tenant, whoever started it: the CLI, an API or the UI.
create or replace function "app_private"."list_import_source_runs"(tenant uuid, source text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r."id", 'source', r."source", 'status', r."status", 'createdAt', r."created_at"
  ) order by r."created_at" desc), '[]'::jsonb)
  from "app_private"."import_runs" r
  where r."tenant_id" = list_import_source_runs.tenant
    and (list_import_source_runs.source is null or r."source" = list_import_source_runs.source)
$$;
revoke execute on function "app_private"."list_import_source_runs"(uuid, text) from public, anon;
grant execute on function "app_private"."list_import_source_runs"(uuid, text) to authenticated, service_role;


-- Writes the items of one entity: an unknown key inserts, an equal hash is
-- unchanged and writes nothing, a changed hash updates unless the row changed
-- after the last import (conflicted). Returns the counts and the item errors.
create or replace function "app_private"."import_apply_batch"(run uuid, entity text, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := import_apply_batch.run;
  v_entity text := import_apply_batch.entity;
  v_items jsonb := import_apply_batch.items;
  v_run "app_private"."import_runs";
  v_item jsonb;
  v_call jsonb;
  v_key text;
  v_scope text;
  v_data jsonb;
  v_hash text;
  v_source_at timestamptz;
  v_diff jsonb := '[]'::jsonb;
  v_rec "app_private"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_owned text;
  v_natural text;
  v_ref_map jsonb := '{}'::jsonb;
  v_resolved jsonb := '{}'::jsonb;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_issue text;
  v_message text;
  v_hint text;
begin
  select * into v_run from "app_private"."import_runs" r where r."id" = v_run_id;
  if v_entity <> all (array[]::text[]) then
    raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    raise exception 'items must be an array of { key, scope, data, refs }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  v_ref_map := '{}'::jsonb;

  for v_item in
    select e.value from jsonb_array_elements(v_items) e
    order by e.value #>> '{data,orderBy}', e.value #>> '{data,readAt}', e.value ->> 'key'
  loop
    v_issue := null;
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      perform "app_private"."import_note_issue"(v_run_id, v_entity, coalesce(v_key, ''), 'error', 'IMPORT_ITEM_INVALID', 'an item needs a key and a data object');
      continue;
    end if;

    

    begin
      v_done := false;
      select * into v_rec from "app_private"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;
      v_source_at := nullif(v_item ->> 'sourceUpdatedAt', '')::timestamptz;
      if v_found and v_source_at is not null and v_rec."source_updated_at" is not null and v_source_at <= v_rec."source_updated_at" then
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');
      end if;

      if v_done then
        null;
      elsif not v_found then
        v_natural := null;
        null;
        if v_natural is not null then
          v_found := true;
          v_rec."subject_id" := v_natural;
          v_rec."content_hash" := '';
        end if;
      end if;

      if v_done then
        null;
      elsif not v_found then
        -- A cloned administration reuses the subjects of the scope it aliases
        -- when the content is equal there.
        for v_other in
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = v_scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? v_entity)
        loop
          if exists (
            select 1 from "app_private"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary' and x."content_hash" = v_hash
          ) then
            insert into "app_private"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_imported_updated_at"
            from "app_private"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key
            on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do nothing;
            v_unchanged := v_unchanged + 1;
            v_done := true;
            exit;
          end if;
        end loop;
      elsif v_rec."content_hash" = v_hash then
        update "app_private"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."went_missing_at" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        v_owned := null;
        null;
        null;
        if v_owned is not null and v_rec."owned_hash" is not null and v_owned is distinct from v_rec."owned_hash" then
          update "app_private"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_issue := 'conflict';
          v_done := true;
        elsif v_owned is not null and v_current is not null and v_rec."subject_imported_updated_at" is not null and v_current > v_rec."subject_imported_updated_at" then
          update "app_private"."import_records" x set "last_run_id" = v_run_id, "subject_imported_updated_at" = v_current, "owned_hash" = v_owned
          where x."id" = v_rec."id";
        elsif v_owned is null and v_current is not null and v_rec."subject_imported_updated_at" is not null and v_current > v_rec."subject_imported_updated_at" then
          update "app_private"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_issue := 'conflict';
          v_done := true;
        end if;
      end if;

      if v_issue = 'conflict' then
        perform "app_private"."import_note_issue"(v_run_id, v_entity, v_key, 'conflict', 'IMPORT_CONFLICT', 'the subject changed after the last import');
      else
        perform "app_private"."import_clear_issues"(v_run_id, v_entity, v_key);
      end if;

      if not v_done and v_run."dry_run" and jsonb_typeof(v_item -> 'previous') = 'object' and jsonb_array_length(v_diff) < 20 then
        v_diff := v_diff || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'fields', (
          select coalesce(jsonb_agg(jsonb_build_object('field', k, 'old', v_item -> 'previous' -> k, 'new', v_data -> k)), '[]'::jsonb)
          from jsonb_object_keys(v_data) k where (v_data -> k) is distinct from (v_item -> 'previous' -> k))));
      end if;
      if not v_done then
        v_subject_id := case when v_found then v_rec."subject_id" else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run."tenant_id", 'scope', v_scope);
        
        raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';

          v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
  if not exists (
    select 1 from jsonb_array_elements(v_subjects) s
    where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
  ) then
    raise exception 'the import target returned no primary subject' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
    if jsonb_typeof(v_subject -> 'warnings') = 'array' then
      v_warnings := v_warnings || (select coalesce(jsonb_agg(w.value || jsonb_build_object('entity', v_entity, 'key', v_key)), '[]'::jsonb) from jsonb_array_elements(v_subject -> 'warnings') w);
    end if;
    insert into "app_private"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at", "source_updated_at", "went_missing_at")
    values (
      v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
      coalesce(v_subject ->> 'role', 'primary'),
      coalesce(v_subject ->> 'subjectType', v_subject_type),
      v_subject ->> 'subjectId',
      v_hash, v_run_id, v_run_id,
      coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
      v_source_at,
      null
    )
    on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
      "subject_type" = excluded."subject_type",
      "subject_id" = excluded."subject_id",
      "content_hash" = excluded."content_hash",
      "last_run_id" = excluded."last_run_id",
      "subject_imported_updated_at" = excluded."subject_imported_updated_at",
      "source_updated_at" = coalesce(excluded."source_updated_at", "app_private"."import_records"."source_updated_at"),
      "went_missing_at" = null;
  end loop;

  if v_found then
    v_updated := v_updated + 1;
  else
    v_inserted := v_inserted + 1;
  end if;
  
      end if;
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
      perform "app_private"."import_note_issue"(v_run_id, v_entity, coalesce(v_key, ''), 'error', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), v_message);
    end;
  end loop;

  

  perform "app_private"."import_note_warnings"(v_run_id, v_entity, v_warnings);

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors, 'diff', v_diff) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
end;
$$;
revoke execute on function "app_private"."import_apply_batch"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "app_private"."import_apply_batch"(uuid, text, jsonb) to service_role;

-- Turns import mode on for the rest of the transaction (ADR 0141): the outbox
-- applies the imports.events policy, the audit log tags entries as
-- integration with the correlation id import:<run> (imports.audit decides rows
-- or one summary per entity) and ctx.importing() guards skip their side
-- effects. The setting is transaction-local and better_supabase.import_run()
-- only reports it to the service role, so no user session can turn it on.
create or replace function "app_private"."begin_import_session"(run uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_status text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role can begin an import session' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  select r."status"::text into v_status from "app_private"."import_runs" r where r."id" = begin_import_session.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_status <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  perform set_config('better_supabase.import_run', begin_import_session.run::text, true);
  perform set_config('better_supabase.correlation_id', 'import:' || begin_import_session.run::text, true);
  perform set_config('better_supabase.import_events', '{}', true);
  perform set_config('better_supabase.import_audit', 'rows', true);
  return begin_import_session.run;
end;
$$;
revoke execute on function "app_private"."begin_import_session"(uuid) from public, anon, authenticated;
grant execute on function "app_private"."begin_import_session"(uuid) to service_role;

-- The single write path of an import (service role). It begins the import
-- session for its writes and restores the caller's settings afterwards. A dry
-- run writes inside a subtransaction it rolls back, then keeps the counts.
create or replace function "app_private"."import_upsert_batch"(run uuid, entity text, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := import_upsert_batch.run;
  v_entity text := import_upsert_batch.entity;
  v_run "app_private"."import_runs";
  v_result jsonb;
  v_name text;
  v_previous jsonb := '{}'::jsonb;
begin
  -- No row lock here: two batches of one run write at the same time, and the
  -- counts update at the end is the only statement that locks the run row.
  select * into v_run from "app_private"."import_runs" r where r."id" = v_run_id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  if coalesce((v_run."plan" ->> 'unordered')::boolean, false) is distinct from true
    and jsonb_typeof(v_run."plan" -> 'waves') = 'array'
    and exists (
      select 1 from jsonb_array_elements(v_run."plan" -> 'waves') with ordinality as w(wave, n)
      where w.wave ? v_entity and exists (
        select 1 from jsonb_array_elements(v_run."plan" -> 'waves') with ordinality as earlier(wave, n)
        cross join lateral jsonb_array_elements_text(earlier.wave) dep(entity)
        join "app_private"."import_chunks" c on c."run_id" = v_run_id
          and c."entity" = dep.entity and c."status" <> 'done'
        where earlier.n < w.n)) then
    raise exception 'an earlier import wave still has open chunks' using errcode = '55000', hint = 'IMPORT_DEPENDENCY_OPEN';
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    v_previous := v_previous || jsonb_build_object(v_name, coalesce(current_setting(v_name, true), ''));
  end loop;
  perform "app_private"."begin_import_session"(v_run_id);

  if v_run."dry_run" then
    begin
      v_result := "app_private"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
      raise exception 'dry run' using errcode = 'BSDRY';
    exception when sqlstate 'BSDRY' then
      null;
    end;
  else
    v_result := "app_private"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    perform set_config(v_name, v_previous ->> v_name, true);
  end loop;

  update "app_private"."import_runs" r set
    "counts" = jsonb_set(r."counts", array[v_entity], jsonb_build_object(
      'inserted', coalesce(r."counts" -> v_entity ->> 'inserted', '0')::integer + coalesce((v_result ->> 'inserted')::integer, 0),
      'updated', coalesce(r."counts" -> v_entity ->> 'updated', '0')::integer + coalesce((v_result ->> 'updated')::integer, 0),
      'unchanged', coalesce(r."counts" -> v_entity ->> 'unchanged', '0')::integer + coalesce((v_result ->> 'unchanged')::integer, 0),
      'conflicted', coalesce(r."counts" -> v_entity ->> 'conflicted', '0')::integer + coalesce((v_result ->> 'conflicted')::integer, 0),
      'missing', coalesce((r."counts" -> v_entity ->> 'missing')::integer, 0)
    )),
    "errors" = r."errors" || coalesce(v_result -> 'errors', '[]'::jsonb),
    "diff" = (select coalesce(jsonb_agg(d.value), '[]'::jsonb) from (
      select value from jsonb_array_elements(r."diff" || coalesce(v_result -> 'diff', '[]'::jsonb)) value limit 100
    ) d)
  where r."id" = v_run_id;
  return v_result || jsonb_build_object('dryRun', v_run."dry_run");
end;
$$;
revoke execute on function "app_private"."import_upsert_batch"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "app_private"."import_upsert_batch"(uuid, text, jsonb) to service_role;

-- Bulk external key to subject. keys is an array of text, or of { key, scope,
-- role }; a scope that aliases another resolves through it.
create or replace function "app_private"."import_resolve"(run uuid, entity text, keys jsonb)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "app_private"."import_runs";
begin
  select * into v_run from "app_private"."import_runs" r where r."id" = import_resolve.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if jsonb_typeof(import_resolve.keys) <> 'array' then
    raise exception 'keys must be an array' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('key', q.key, 'scope', q.scope, 'role', q.role, 'subjectType', m."subject_type", 'subjectId', m."subject_id") order by q.ord)
    from (
      select k.ord,
        case when jsonb_typeof(k.value) = 'string' then k.value #>> '{}' else k.value ->> 'key' end as key,
        case when jsonb_typeof(k.value) = 'string' then '' else coalesce(k.value ->> 'scope', '') end as scope,
        case when jsonb_typeof(k.value) = 'string' then 'primary' else coalesce(k.value ->> 'role', 'primary') end as role
      from jsonb_array_elements(import_resolve.keys) with ordinality k(value, ord)
    ) q
    join lateral (
      select x."subject_type", x."subject_id"
      from "app_private"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source"
        and x."entity" = import_resolve.entity and x."external_key" = q.key and x."role" = q.role
        and (x."scope" = q.scope or x."scope" in (
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = q.scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? import_resolve.entity)
        ))
      order by (x."scope" = q.scope) desc
      limit 1
    ) m on true
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."import_resolve"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "app_private"."import_resolve"(uuid, text, jsonb) to service_role;

-- Closes a run that wrote through import_upsert_batch. A full run marks the
-- records of its entities it didn't see, and never deletes them.
create or replace function "app_private"."finish_import_run"(run uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := finish_import_run.run;
  v_run "app_private"."import_runs";
  v_entity text;
  v_missing integer;
  v_total integer := 0;
  v_counts jsonb;
  v_outcome text := 'completed';
  v_expected integer;
  v_applied integer;
begin
  select * into v_run from "app_private"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  v_counts := v_run."counts";

  if v_run."full" then
    for v_entity in select k.key from jsonb_object_keys(v_run."counts") k(key) loop
      select count(*)::integer into v_missing from "app_private"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
        and x."role" = 'primary' and x."last_run_id" <> v_run_id
        and x."scope" in (select y."scope" from "app_private"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      if not v_run."dry_run" then
        update "app_private"."import_records" x set "went_missing_at" = coalesce(x."went_missing_at", now())
        where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
          and x."last_run_id" <> v_run_id
          and x."scope" in (select y."scope" from "app_private"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  if v_run."plan" is not null and jsonb_typeof(v_run."plan") = 'object' then
    for v_entity in select k.key from jsonb_object_keys(v_run."plan") k(key) loop
      v_expected := coalesce((v_run."plan" ->> v_entity)::integer, 0);
      v_applied := coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'unchanged')::integer, 0);
      if v_applied < v_expected then
        v_outcome := 'incomplete';
        v_counts := jsonb_set(coalesce(v_counts, '{}'::jsonb), array[v_entity, 'missing'], to_jsonb(v_expected - v_applied), true);
      end if;
    end loop;
  end if;
  if v_outcome = 'completed' and (jsonb_array_length(coalesce(v_run."errors", '[]'::jsonb)) > 0 or v_counts::text like '%"conflicted":%') then
    v_outcome := 'completed_with_issues';
  end if;

  update "app_private"."import_runs" r set "status" = 'completed', "outcome" = v_outcome, "finished_at" = now(), "counts" = v_counts
  where r."id" = v_run_id;

  if not v_run."dry_run" then
    for v_entity in select k.key from jsonb_object_keys(v_counts) k(key) loop
      v_total := v_total + coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0);
      null;
    end loop;
    null;
  end if;
  return v_counts;
end;
$$;
revoke execute on function "app_private"."finish_import_run"(uuid) from public, anon, authenticated;
grant execute on function "app_private"."finish_import_run"(uuid) to service_role;

create or replace function "app_private"."heartbeat_import_run"(run uuid, seconds integer default 30)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_until timestamptz;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can heartbeat an import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  update "app_private"."import_runs" r set "heartbeat_at" = now(), "lease_until" = now() + make_interval(secs => greatest(heartbeat_import_run.seconds, 1))
  where r."id" = heartbeat_import_run.run and r."status" = 'running'
  returning r."lease_until" into v_until;
  if v_until is null then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  return v_until;
end;
$$;
revoke execute on function "app_private"."heartbeat_import_run"(uuid, integer) from public, anon, authenticated;
grant execute on function "app_private"."heartbeat_import_run"(uuid, integer) to service_role;

create or replace function "app_private"."import_ensure_ref"(tenant uuid, kind text, key text, defaults jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_created boolean := false;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can ensure an import ref' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if import_ensure_ref.kind is null or import_ensure_ref.key is null or import_ensure_ref.key = '' then
    raise exception 'a ref needs a kind and a key' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select r."id" into v_id from "app_private".import_refs r
  where r."tenant_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
  if v_id is null then
    insert into "app_private".import_refs ("tenant_id", "kind", "key", "payload")
    values (import_ensure_ref.tenant, import_ensure_ref.kind, import_ensure_ref.key, coalesce(import_ensure_ref.defaults, '{}'::jsonb))
    on conflict ("tenant_id", "kind", "key") do nothing
    returning "id" into v_id;
    v_created := v_id is not null;
    if v_id is null then
      select r."id" into v_id from "app_private".import_refs r
      where r."tenant_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
    end if;
  end if;
  return jsonb_build_object(
    'id', v_id,
    'created', v_created,
    'warnings', case when v_created then jsonb_build_array(jsonb_build_object('code', 'IMPORT_REF_CREATED', 'kind', import_ensure_ref.kind, 'key', import_ensure_ref.key)) else '[]'::jsonb end
  );
end;
$$;
revoke execute on function "app_private"."import_ensure_ref"(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function "app_private"."import_ensure_ref"(uuid, text, text, jsonb) to service_role;

create or replace function "app_private"."import_entities"()
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$ select array[]::text[] $$;
revoke execute on function "app_private"."import_entities"() from public, anon, authenticated;
grant execute on function "app_private"."import_entities"() to service_role;


create or replace function "app_private"."rebase_import_records"(tenant uuid, source text, entities text[] default null, keys text[] default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can rebase import records' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  update "app_private"."import_records" x
  set "subject_imported_updated_at" = coalesce((null), x."subject_imported_updated_at"),
      "owned_hash" = coalesce((null), x."owned_hash")
  where x."tenant_id" = rebase_import_records.tenant
    and x."source" = rebase_import_records.source
    and (rebase_import_records.entities is null or x."entity" = any (rebase_import_records.entities))
    and (rebase_import_records.keys is null or x."external_key" = any (rebase_import_records.keys));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "app_private"."rebase_import_records"(uuid, text, text[], text[]) from public, anon, authenticated;
grant execute on function "app_private"."rebase_import_records"(uuid, text, text[], text[]) to service_role;


-- Queues one job per chunk of an entity's items, so a worker writes a large
-- import in batches; the dedupe key makes a retry harmless.
create or replace function "app_private"."enqueue_import_chunks"(run uuid, entity text, chunks integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "app_private"."import_runs";
  v_chunk integer;
begin
  select * into v_run from "app_private"."import_runs" r where r."id" = enqueue_import_chunks.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if enqueue_import_chunks.chunks is null or enqueue_import_chunks.chunks < 1 then
    raise exception 'chunks must be at least 1' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  for v_chunk in 0 .. enqueue_import_chunks.chunks - 1 loop
    perform "better_supabase"."enqueue_job"(queue => 'imports', payload => jsonb_build_object('run', v_run."id", 'entity', enqueue_import_chunks.entity, 'chunk', v_chunk), dedupe_key => v_run."id"::text || ':' || enqueue_import_chunks.entity || ':' || v_chunk::text, dedupe_running => false);
  end loop;
  return enqueue_import_chunks.chunks;
end;
$$;
revoke execute on function "app_private"."enqueue_import_chunks"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "app_private"."enqueue_import_chunks"(uuid, text, integer) to service_role;

-- Stores the items of one chunk of an entity, ready for a worker. Storing a chunk
-- again before it is done replaces its items; a done chunk is left as it is and
-- the answer is false.
create or replace function "app_private"."store_import_chunk"(run uuid, entity text, chunk integer, items jsonb)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "app_private"."import_runs";
begin
  select * into v_run from "app_private"."import_runs" r where r."id" = store_import_chunk.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if store_import_chunk.chunk is null or store_import_chunk.chunk < 0 or jsonb_typeof(store_import_chunk.items) is distinct from 'array' then
    raise exception 'a chunk has a number from 0 and an array of items' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  insert into "app_private"."import_chunks" ("run_id", "tenant_id", "entity", "chunk", "items")
  values (store_import_chunk.run, v_run."tenant_id", store_import_chunk.entity, store_import_chunk.chunk, store_import_chunk.items)
  on conflict ("run_id", "entity", "chunk") do update
    set "items" = excluded."items", "status" = 'pending', "claimed_at" = null
    where "app_private"."import_chunks"."status" <> 'done';
  return found;
end;
$$;
revoke execute on function "app_private"."store_import_chunk"(uuid, text, integer, jsonb) from public, anon, authenticated;
grant execute on function "app_private"."store_import_chunk"(uuid, text, integer, jsonb) to service_role;

-- Takes a pending chunk, or one whose claim is older than lease seconds (a worker
-- that died), and returns { entity, chunk, items }. Null when the chunk is done,
-- missing or held by a live worker. Rows another worker holds are skipped, not waited for.
create or replace function "app_private"."claim_import_chunk"(run uuid, entity text, chunk integer, lease integer default 300)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_items jsonb;
begin
  with pick as (
    select x."run_id", x."entity", x."chunk"
    from "app_private"."import_chunks" x
    where x."run_id" = claim_import_chunk.run and x."entity" = claim_import_chunk.entity and x."chunk" = claim_import_chunk.chunk
      and (x."status" = 'pending' or (x."status" = 'claimed' and x."claimed_at" < now() - make_interval(secs => greatest(claim_import_chunk.lease, 1))))
    for update skip locked
  )
  update "app_private"."import_chunks" x set "status" = 'claimed', "claimed_at" = now()
  from pick
  where x."run_id" = pick."run_id" and x."entity" = pick."entity" and x."chunk" = pick."chunk"
  returning x."items" into v_items;
  if v_items is null then
    return null;
  end if;
  return jsonb_build_object('entity', claim_import_chunk.entity, 'chunk', claim_import_chunk.chunk, 'items', v_items);
end;
$$;
revoke execute on function "app_private"."claim_import_chunk"(uuid, text, integer, integer) from public, anon, authenticated;
grant execute on function "app_private"."claim_import_chunk"(uuid, text, integer, integer) to service_role;

-- Marks a claimed chunk done and keeps what its batch answered.
create or replace function "app_private"."complete_import_chunk"(run uuid, entity text, chunk integer, result jsonb)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
begin
  update "app_private"."import_chunks" x set "status" = 'done', "done_at" = now(), "result" = complete_import_chunk.result
  where x."run_id" = complete_import_chunk.run and x."entity" = complete_import_chunk.entity
    and x."chunk" = complete_import_chunk.chunk and x."status" = 'claimed';
  return found;
end;
$$;
revoke execute on function "app_private"."complete_import_chunk"(uuid, text, integer, jsonb) from public, anon, authenticated;
grant execute on function "app_private"."complete_import_chunk"(uuid, text, integer, jsonb) to service_role;

-- One worker step: claim the chunk, write it with import_upsert_batch and mark it
-- done, in one transaction, so a failure leaves the chunk pending for the next try.
-- A chunk that is done answers what its batch answered; one that is missing or
-- held by another worker answers { skipped: true }.
create or replace function "app_private"."process_import_chunk"(run uuid, entity text, chunk integer)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_done jsonb;
  v_claim jsonb;
  v_result jsonb;
begin
  select x."result" into v_done from "app_private"."import_chunks" x
  where x."run_id" = process_import_chunk.run and x."entity" = process_import_chunk.entity
    and x."chunk" = process_import_chunk.chunk and x."status" = 'done';
  if found then
    return coalesce(v_done, '{}'::jsonb) || jsonb_build_object('done', true);
  end if;
  v_claim := "app_private"."claim_import_chunk"(process_import_chunk.run, process_import_chunk.entity, process_import_chunk.chunk);
  if v_claim is null then
    return jsonb_build_object('skipped', true);
  end if;
  v_result := "app_private"."import_upsert_batch"(process_import_chunk.run, process_import_chunk.entity, v_claim -> 'items');
  perform "app_private"."complete_import_chunk"(process_import_chunk.run, process_import_chunk.entity, process_import_chunk.chunk, v_result);
  return v_result;
end;
$$;
revoke execute on function "app_private"."process_import_chunk"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "app_private"."process_import_chunk"(uuid, text, integer) to service_role;

-- How many chunks of a run are pending, claimed and done, so a caller knows when to
-- finish the run.
create or replace function "app_private"."import_chunk_progress"(run uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'pending', count(*) filter (where x."status" = 'pending'),
    'claimed', count(*) filter (where x."status" = 'claimed'),
    'done', count(*) filter (where x."status" = 'done')
  )
  from "app_private"."import_chunks" x
  where x."run_id" = import_chunk_progress.run
$$;
revoke execute on function "app_private"."import_chunk_progress"(uuid) from public, anon, authenticated;
grant execute on function "app_private"."import_chunk_progress"(uuid) to service_role;

-- Clears the content hash of the records of a source (and entity) that a run of
-- another mapper version last wrote, so the next import treats them as changed and
-- rewrites them through their target (a row a user changed since stays as it is, as
-- for any changed hash). Returns how many records it cleared.
create or replace function "app_private"."reapply_import_records"(tenant uuid, source text, mapper_version text, entity text default null)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_count integer;
begin
  update "app_private"."import_records" x set "content_hash" = ''
  where x."tenant_id" = reapply_import_records.tenant and x."source" = reapply_import_records.source
    and (reapply_import_records.entity is null or x."entity" = reapply_import_records.entity)
    and x."content_hash" <> ''
    and (select r."mapper_version" from "app_private"."import_runs" r where r."id" = x."last_run_id") is distinct from reapply_import_records.mapper_version;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "app_private"."reapply_import_records"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "app_private"."reapply_import_records"(uuid, text, text, text) to service_role;

-- The record map of a source as { entity, scope, key, role, hash, subjectType,
-- subjectId }, one object per record in key order, so a caller can compare what the
-- source sends with what was imported without reading the rows.
create or replace function "app_private"."export_import_hashes"(tenant uuid, source text, entity text default null)
returns setof jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('entity', x."entity", 'scope', x."scope", 'key', x."external_key", 'role', x."role",
    'hash', x."content_hash", 'subjectType', x."subject_type", 'subjectId', x."subject_id")
  from "app_private"."import_records" x
  where x."tenant_id" = export_import_hashes.tenant and x."source" = export_import_hashes.source
    and (export_import_hashes.entity is null or x."entity" = export_import_hashes.entity)
  order by x."entity", x."scope", x."external_key", x."role"
$$;
revoke execute on function "app_private"."export_import_hashes"(uuid, text, text) from public, anon, authenticated;
grant execute on function "app_private"."export_import_hashes"(uuid, text, text) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."import_runs" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "app_private"."import_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."import_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."import_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."import_records" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "app_private"."import_records" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."import_records" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."import_records" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_064_imports.sql
-- better-supabase module: imports
-- @bsb-block-data imports
-- @bsb-hash sha256:03c82178dd5c9af38535aa92f90002ada8c21fab4dadb8d91c33605f8bdcec29
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('imports', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_064_imports.sql
-- better-supabase module: imports
-- @bsb-block imports@2 managed
-- @bsb-hash sha256:416f836e82d3e315ec832150a700f499c7b571612a00b13496e887af6e1f8f05
-- Import runs and the external record map. import_upsert_batch writes items through the targets blocks and the app register, skips equal content, reports rows a user changed since the last import and marks missing keys on full runs. The dry run, parsing and mapping live in TypeScript.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."import_runs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "source" text not null,
  "status" text not null default 'pending',
  "mapping" jsonb not null default '{}'::jsonb,
  "counts" jsonb not null default '{}'::jsonb,
  "errors" jsonb not null default '[]'::jsonb,
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."import_runs" add column "dry_run" boolean not null default false;
alter table "better_supabase"."import_runs" add column "diff" jsonb not null default '[]'::jsonb;
alter table "better_supabase"."import_runs" add column "full" boolean not null default false;
alter table "better_supabase"."import_runs" add column "input_checksum" text;
alter table "better_supabase"."import_runs" add column "correlation_id" text;
alter table "better_supabase"."import_runs" add column "mapper_version" text;
alter table "better_supabase"."import_runs" add column "scope_aliases" jsonb not null default '[]'::jsonb;
alter table "better_supabase"."import_runs" add column "started_at" timestamptz;
alter table "better_supabase"."import_runs" add column "finished_at" timestamptz;
alter table "better_supabase"."import_runs" add column "plan" jsonb;
alter table "better_supabase"."import_runs" add column "outcome" text;
alter table "better_supabase"."import_runs" add column "lease_until" timestamptz;
alter table "better_supabase"."import_runs" add column "heartbeat_at" timestamptz;
alter table "better_supabase"."import_runs" add constraint "bsb_import_runs_status"
  check ("status" in ('pending', 'running', 'completed', 'failed', 'canceled'));
alter table "better_supabase"."import_runs" enable row level security;
revoke all on "better_supabase"."import_runs" from public, anon, authenticated;
grant select on "better_supabase"."import_runs" to authenticated;
grant all on "better_supabase"."import_runs" to service_role;
create index "import_runs_tenant_idx" on "better_supabase"."import_runs" ("tenant_id");
-- One pending or running run per organization and source.
create unique index "import_runs_active_idx" on "better_supabase"."import_runs" ("tenant_id", "source") where "status" in ('pending', 'running');

create table "better_supabase"."import_records" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "source" text not null,
  "scope" text not null default '',
  "entity" text not null,
  "external_key" text not null,
  "role" text not null default 'primary',
  "subject_type" text not null,
  "subject_id" text not null,
  "content_hash" text not null,
  "first_run_id" uuid not null,
  "last_run_id" uuid not null,
  "subject_imported_updated_at" timestamptz,
  "source_updated_at" timestamptz,
  "owned_hash" text,
  "went_missing_at" timestamptz,
  constraint "import_records_key" unique ("tenant_id", "source", "scope", "entity", "external_key", "role")
);
create index "import_records_subject_idx" on "better_supabase"."import_records" ("tenant_id", "subject_type", "subject_id");
alter table "better_supabase"."import_records" enable row level security;
revoke all on "better_supabase"."import_records" from public, anon, authenticated;
grant select on "better_supabase"."import_records" to authenticated;
grant all on "better_supabase"."import_records" to service_role;
create table "better_supabase".import_refs (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null,
  "key" text not null,
  "payload" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now(),
  constraint import_refs_key unique ("tenant_id", "kind", "key")
);

create table "better_supabase"."import_chunks" (
  "run_id" uuid not null references "better_supabase"."import_runs" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "entity" text not null,
  "chunk" integer not null,
  "items" jsonb not null,
  "status" text not null default 'pending',
  "result" jsonb,
  "claimed_at" timestamptz,
  "done_at" timestamptz,
  "created_at" timestamptz not null default now(),
  primary key ("run_id", "entity", "chunk")
);
alter table "better_supabase"."import_chunks" add constraint "bsb_import_chunks_status"
  check ("status" in ('pending', 'claimed', 'done'));
alter table "better_supabase"."import_chunks" enable row level security;
revoke all on "better_supabase"."import_chunks" from public, anon, authenticated;
grant all on "better_supabase"."import_chunks" to service_role;
create index "import_chunks_tenant_idx" on "better_supabase"."import_chunks" ("tenant_id");


create table "better_supabase".import_run_issues (
  "id" uuid primary key default gen_random_uuid(),
  "run_id" uuid not null,
  "tenant_id" uuid not null,
  "source" text not null,
  "entity" text not null,
  "key" text not null,
  "kind" text not null,
  "code" text not null,
  "message" text not null,
  "created_at" timestamptz not null default now(),
  "resolved_at" timestamptz,
  constraint bsb_import_run_issues_kind check ("kind" in ('conflict', 'error', 'warning'))
);
create index import_run_issues_open_idx
  on "better_supabase".import_run_issues ("tenant_id", "source", "entity", "key")
  where "resolved_at" is null;
create index import_run_issues_run_idx
  on "better_supabase".import_run_issues ("run_id", "entity");

create or replace function "better_supabase"."start_import_run"(tenant uuid, source text, options jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_options jsonb := coalesce(start_import_run.options, '{}'::jsonb);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', start_import_run.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if start_import_run.source is null or start_import_run.source = '' then
    raise exception 'an import run needs a source' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(coalesce(v_options -> 'scopeAliases', '[]'::jsonb)) <> 'array' then
    raise exception 'scopeAliases must be an array of { scope, of, entities }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    insert into "better_supabase"."import_runs" as r ("tenant_id", "source", "mapping", "dry_run", "full", "input_checksum", "correlation_id", "mapper_version", "scope_aliases", "plan", "lease_until", "created_by")
    values (
      start_import_run.tenant,
      start_import_run.source,
      coalesce(v_options -> 'mapping', '{}'::jsonb),
      coalesce((v_options ->> 'dryRun')::boolean, false),
      coalesce((v_options ->> 'full')::boolean, false),
      v_options ->> 'inputChecksum',
      v_options ->> 'correlationId',
      nullif(v_options ->> 'mapperVersion', ''),
      coalesce(v_options -> 'scopeAliases', '[]'::jsonb),
      v_options -> 'plan',
      now() + interval '30 seconds',
      auth.uid()
    )
    returning r."id" into v_id;
  exception when unique_violation then
    raise exception 'an import of this source is already pending or running' using errcode = '55P03', hint = 'IMPORT_RUN_ACTIVE';
  end;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."start_import_run"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."start_import_run"(uuid, text, jsonb) to authenticated, service_role;

-- The first release's entry point: a run without options.
create or replace function "better_supabase"."start_import"(tenant uuid, source text, mapping jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select "better_supabase"."start_import_run"(start_import.tenant, start_import.source, jsonb_build_object('mapping', coalesce(start_import.mapping, '{}'::jsonb)));
$$;
revoke execute on function "better_supabase"."start_import"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."start_import"(uuid, text, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_import_run"(id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = get_import_run.id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_run."tenant_id", 'imports.manage'), false)) then
    raise exception 'not allowed to read this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."tenant_id", 'source', v_run."source", 'status', v_run."status", 'outcome', v_run."outcome", 'plan', v_run."plan", 'mapping', v_run."mapping", 'counts', v_run."counts", 'errors', v_run."errors", 'dryRun', v_run."dry_run", 'full', v_run."full", 'inputChecksum', v_run."input_checksum", 'correlationId', v_run."correlation_id", 'mapperVersion', v_run."mapper_version", 'scopeAliases', v_run."scope_aliases", 'leaseUntil', v_run."lease_until", 'heartbeatAt', v_run."heartbeat_at", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'startedAt', v_run."started_at", 'finishedAt', v_run."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "better_supabase".import_run_issues i
    where i."run_id" = v_run."id"
  ));
end;
$$;
revoke execute on function "better_supabase"."get_import_run"(uuid) from public, anon;
grant execute on function "better_supabase"."get_import_run"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_import_runs"(tenant uuid, source text default null, status text default null, row_limit integer default 50)
returns setof jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_import_runs.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list imports' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  return query
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'source', r."source", 'status', r."status", 'outcome', r."outcome", 'plan', r."plan", 'mapping', r."mapping", 'counts', r."counts", 'errors', r."errors", 'dryRun', r."dry_run", 'full', r."full", 'inputChecksum', r."input_checksum", 'correlationId', r."correlation_id", 'mapperVersion', r."mapper_version", 'scopeAliases', r."scope_aliases", 'leaseUntil', r."lease_until", 'heartbeatAt', r."heartbeat_at", 'createdBy', r."created_by", 'createdAt', r."created_at", 'startedAt', r."started_at", 'finishedAt', r."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "better_supabase".import_run_issues i
    where i."run_id" = r."id"
  ))
    from "better_supabase"."import_runs" r
    where r."tenant_id" = list_import_runs.tenant
      and (list_import_runs.source is null or r."source" = list_import_runs.source)
      and (list_import_runs.status is null or r."status" = list_import_runs.status)
    order by r."created_at" desc, r."id" desc
    limit least(greatest(coalesce(list_import_runs.row_limit, 50), 1), 200);
end;
$$;
revoke execute on function "better_supabase"."list_import_runs"(uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_import_runs"(uuid, text, text, integer) to authenticated, service_role;

create or replace function "better_supabase"."cancel_import_run"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_run "better_supabase"."import_runs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_run from "better_supabase"."import_runs" r where r."id" = cancel_import_run.id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_run."tenant_id", 'imports.manage'), false)) then
    raise exception 'not allowed to cancel this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if v_run."status" not in ('pending', 'running') then
    raise exception 'this import already finished' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  update "better_supabase"."import_runs" r set "status" = 'canceled', "finished_at" = now()
  where r."id" = cancel_import_run.id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_import_run"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_import_run"(uuid) to authenticated, service_role;

-- The run moves from pending to running before the first batch, so a run
-- that dies mid-way is visible as running rather than pending.
create or replace function "better_supabase"."mark_import_running"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  update "better_supabase"."import_runs" set "status" = 'running', "started_at" = now()
  where "id" = mark_import_running.id and "status" = 'pending';
  if not found then
    raise exception 'no pending import with this id' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."mark_import_running"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_import_running"(uuid) to service_role;

-- Closes a run whose rows the caller wrote itself (`defineImport` without a
-- target); `finish_import_run` closes a run that used `import_upsert_batch`.
create or replace function "better_supabase"."finish_import"(id uuid, status text, count integer, error text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_source text;
begin
  update "better_supabase"."import_runs" set "status" = finish_import.status,
    "finished_at" = now(),
    "counts" = case when finish_import.status = 'completed' then jsonb_build_object("source", jsonb_build_object('inserted', finish_import.count, 'updated', 0, 'unchanged', 0, 'conflicted', 0, 'missing', 0)) else "counts" end,
    "errors" = case when finish_import.error is null then "errors" else "errors" || jsonb_build_array(jsonb_build_object('entity', "source", 'key', null, 'code', 'IMPORT_ITEM_INVALID', 'message', finish_import.error)) end
  where "id" = finish_import.id
  returning "tenant_id", "source" into v_tenant, v_source;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if finish_import.status = 'failed' then
    null;
  else
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."finish_import"(uuid, text, integer, text) from public, anon, authenticated;
grant execute on function "better_supabase"."finish_import"(uuid, text, integer, text) to service_role;

create or replace function "better_supabase"."import_note_issue"(run uuid, entity text, key text, kind text, code text, message text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_source text;
begin
  select r."tenant_id", r."source" into v_tenant, v_source
  from "better_supabase"."import_runs" r where r."id" = import_note_issue.run;
  if v_tenant is null or import_note_issue.key is null or import_note_issue.key = '' then
    return;
  end if;
  insert into "better_supabase".import_run_issues ("run_id", "tenant_id", "source", "entity", "key", "kind", "code", "message")
  values (import_note_issue.run, v_tenant, v_source, import_note_issue.entity, import_note_issue.key, import_note_issue.kind, import_note_issue.code, import_note_issue.message);
end;
$$;

create or replace function "better_supabase"."import_note_warnings"(run uuid, entity text, warnings jsonb)
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
    perform "better_supabase"."import_note_issue"(
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

create or replace function "better_supabase"."import_clear_issues"(run uuid, entity text, key text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_source text;
begin
  select r."tenant_id", r."source" into v_tenant, v_source
  from "better_supabase"."import_runs" r where r."id" = import_clear_issues.run;
  if v_tenant is null then
    return;
  end if;
  update "better_supabase".import_run_issues i set "resolved_at" = now()
  where i."tenant_id" = v_tenant and i."source" = v_source
    and i."entity" = import_clear_issues.entity and i."key" = import_clear_issues.key
    and i."resolved_at" is null;
end;
$$;

create or replace function "better_supabase"."list_import_issues"(run uuid, entity text default null, row_limit integer default 50, row_offset integer default 0)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_total integer;
  v_rows jsonb;
begin
  select r."tenant_id" into v_tenant from "better_supabase"."import_runs" r where r."id" = list_import_issues.run;
  if v_tenant is null then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list import issues' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  select count(*) into v_total from "better_supabase".import_run_issues i
  where i."run_id" = list_import_issues.run
    and (list_import_issues.entity is null or i."entity" = list_import_issues.entity);
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_rows from (
    select i."entity", i."key", i."kind", i."code", i."message", i."created_at", i."resolved_at"
    from "better_supabase".import_run_issues i
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
revoke execute on function "better_supabase"."list_import_issues"(uuid, text, integer, integer) from public, anon;
grant execute on function "better_supabase"."list_import_issues"(uuid, text, integer, integer) to authenticated, service_role;

-- Counts and the first changed fields of a dry run. The dry run itself writes
-- no subject rows; the diff is what the batch returned.
create or replace function "better_supabase"."list_import_diff"(run uuid, entity text default null, row_limit integer default 50, row_offset integer default 0)
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
  select r."counts", r."diff" into v_counts, v_diff from "better_supabase"."import_runs" r where r."id" = list_import_diff.run;
  if v_counts is null then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
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
revoke execute on function "better_supabase"."list_import_diff"(uuid, text, integer, integer) from public, anon;
grant execute on function "better_supabase"."list_import_diff"(uuid, text, integer, integer) to authenticated, service_role;

create or replace function "better_supabase"."resolve_import_conflict"(tenant uuid, source text, entity text, key text, action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resolved integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', resolve_import_conflict.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to resolve an import conflict' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if resolve_import_conflict.action = 'keep' then
    update "better_supabase"."import_records" x set "subject_imported_updated_at" = now()
    where x."tenant_id" = resolve_import_conflict.tenant
      and x."source" = resolve_import_conflict.source
      and x."entity" = resolve_import_conflict.entity
      and x."external_key" = resolve_import_conflict.key;
  elsif resolve_import_conflict.action = 'overwrite' then
    update "better_supabase"."import_records" x set "subject_imported_updated_at" = null, "owned_hash" = null
    where x."tenant_id" = resolve_import_conflict.tenant
      and x."source" = resolve_import_conflict.source
      and x."entity" = resolve_import_conflict.entity
      and x."external_key" = resolve_import_conflict.key;
  else
    raise exception 'action must be keep or overwrite' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  update "better_supabase".import_run_issues i set "resolved_at" = now()
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
revoke execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) to service_role;
revoke execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."import_integrity"(tenant uuid, source text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_checks jsonb := '[]'::jsonb;
  v_name text;
  v_severity text;
  v_count integer;
  v_ids jsonb;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', import_integrity.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to check this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  for v_name, v_severity, v_count, v_ids in
    select 'duplicate_keys', 'error', count(*)::integer, coalesce(jsonb_agg(sample), '[]'::jsonb) from (
      select min(d."id"::text) as sample from "better_supabase"."import_records" d
      where d."tenant_id" = import_integrity.tenant
        and (import_integrity.source is null or d."source" = import_integrity.source)
      group by d."entity", d."external_key"
      having count(distinct d."subject_id") > 1
    ) q
  loop
    v_checks := v_checks || jsonb_build_array(jsonb_build_object(
      'name', v_name, 'severity', v_severity, 'count', v_count, 'ids', coalesce(v_ids, '[]'::jsonb)));
  end loop;
  return jsonb_build_object('checks', v_checks);
end;
$$;
revoke execute on function "better_supabase"."import_integrity"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_integrity"(uuid, text) to service_role;
revoke execute on function "better_supabase"."import_integrity"(uuid, text) from public, anon;
grant execute on function "better_supabase"."import_integrity"(uuid, text) to authenticated, service_role;

create table "better_supabase".import_sources (
  "id" text primary key,
  "label_key" text not null,
  "description_key" text not null,
  "file_types" text[] not null default '{}',
  "entities" text[] not null default '{}',
  "docs_link" text
);

create or replace function "better_supabase"."register_import_source"(id text, label_key text, description_key text, file_types text[], entities text[], docs_link text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'not allowed to register an import source' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  insert into "better_supabase".import_sources ("id", "label_key", "description_key", "file_types", "entities", "docs_link")
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
revoke execute on function "better_supabase"."register_import_source"(text, text, text, text[], text[], text) from public, anon, authenticated;
grant execute on function "better_supabase"."register_import_source"(text, text, text, text[], text[], text) to service_role;

create or replace function "better_supabase"."list_import_sources"()
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
  from "better_supabase".import_sources s
$$;
revoke execute on function "better_supabase"."list_import_sources"() from public, anon;
grant execute on function "better_supabase"."list_import_sources"() to authenticated, service_role;

-- Every run of the tenant, whoever started it: the CLI, an API or the UI.
create or replace function "better_supabase"."list_import_source_runs"(tenant uuid, source text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r."id", 'source', r."source", 'status', r."status", 'createdAt', r."created_at"
  ) order by r."created_at" desc), '[]'::jsonb)
  from "better_supabase"."import_runs" r
  where r."tenant_id" = list_import_source_runs.tenant
    and (list_import_source_runs.source is null or r."source" = list_import_source_runs.source)
$$;
revoke execute on function "better_supabase"."list_import_source_runs"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_import_source_runs"(uuid, text) to authenticated, service_role;


-- Writes the items of one entity: an unknown key inserts, an equal hash is
-- unchanged and writes nothing, a changed hash updates unless the row changed
-- after the last import (conflicted). Returns the counts and the item errors.
create or replace function "better_supabase"."import_apply_batch"(run uuid, entity text, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := import_apply_batch.run;
  v_entity text := import_apply_batch.entity;
  v_items jsonb := import_apply_batch.items;
  v_run "better_supabase"."import_runs";
  v_item jsonb;
  v_call jsonb;
  v_key text;
  v_scope text;
  v_data jsonb;
  v_hash text;
  v_source_at timestamptz;
  v_diff jsonb := '[]'::jsonb;
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_owned text;
  v_natural text;
  v_ref_map jsonb := '{}'::jsonb;
  v_resolved jsonb := '{}'::jsonb;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_issue text;
  v_message text;
  v_hint text;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if v_entity <> all (array[]::text[]) then
    raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    raise exception 'items must be an array of { key, scope, data, refs }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  v_ref_map := '{}'::jsonb;

  for v_item in
    select e.value from jsonb_array_elements(v_items) e
    order by e.value #>> '{data,orderBy}', e.value #>> '{data,readAt}', e.value ->> 'key'
  loop
    v_issue := null;
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      perform "better_supabase"."import_note_issue"(v_run_id, v_entity, coalesce(v_key, ''), 'error', 'IMPORT_ITEM_INVALID', 'an item needs a key and a data object');
      continue;
    end if;

    

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;
      v_source_at := nullif(v_item ->> 'sourceUpdatedAt', '')::timestamptz;
      if v_found and v_source_at is not null and v_rec."source_updated_at" is not null and v_source_at <= v_rec."source_updated_at" then
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');
      end if;

      if v_done then
        null;
      elsif not v_found then
        v_natural := null;
        null;
        if v_natural is not null then
          v_found := true;
          v_rec."subject_id" := v_natural;
          v_rec."content_hash" := '';
        end if;
      end if;

      if v_done then
        null;
      elsif not v_found then
        -- A cloned administration reuses the subjects of the scope it aliases
        -- when the content is equal there.
        for v_other in
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = v_scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? v_entity)
        loop
          if exists (
            select 1 from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary' and x."content_hash" = v_hash
          ) then
            insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_imported_updated_at"
            from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key
            on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do nothing;
            v_unchanged := v_unchanged + 1;
            v_done := true;
            exit;
          end if;
        end loop;
      elsif v_rec."content_hash" = v_hash then
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."went_missing_at" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        v_owned := null;
        null;
        null;
        if v_owned is not null and v_rec."owned_hash" is not null and v_owned is distinct from v_rec."owned_hash" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_issue := 'conflict';
          v_done := true;
        elsif v_owned is not null and v_current is not null and v_rec."subject_imported_updated_at" is not null and v_current > v_rec."subject_imported_updated_at" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "subject_imported_updated_at" = v_current, "owned_hash" = v_owned
          where x."id" = v_rec."id";
        elsif v_owned is null and v_current is not null and v_rec."subject_imported_updated_at" is not null and v_current > v_rec."subject_imported_updated_at" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_issue := 'conflict';
          v_done := true;
        end if;
      end if;

      if v_issue = 'conflict' then
        perform "better_supabase"."import_note_issue"(v_run_id, v_entity, v_key, 'conflict', 'IMPORT_CONFLICT', 'the subject changed after the last import');
      else
        perform "better_supabase"."import_clear_issues"(v_run_id, v_entity, v_key);
      end if;

      if not v_done and v_run."dry_run" and jsonb_typeof(v_item -> 'previous') = 'object' and jsonb_array_length(v_diff) < 20 then
        v_diff := v_diff || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'fields', (
          select coalesce(jsonb_agg(jsonb_build_object('field', k, 'old', v_item -> 'previous' -> k, 'new', v_data -> k)), '[]'::jsonb)
          from jsonb_object_keys(v_data) k where (v_data -> k) is distinct from (v_item -> 'previous' -> k))));
      end if;
      if not v_done then
        v_subject_id := case when v_found then v_rec."subject_id" else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run."tenant_id", 'scope', v_scope);
        
        raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';

          v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
  if not exists (
    select 1 from jsonb_array_elements(v_subjects) s
    where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
  ) then
    raise exception 'the import target returned no primary subject' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
    if jsonb_typeof(v_subject -> 'warnings') = 'array' then
      v_warnings := v_warnings || (select coalesce(jsonb_agg(w.value || jsonb_build_object('entity', v_entity, 'key', v_key)), '[]'::jsonb) from jsonb_array_elements(v_subject -> 'warnings') w);
    end if;
    insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at", "source_updated_at", "went_missing_at")
    values (
      v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
      coalesce(v_subject ->> 'role', 'primary'),
      coalesce(v_subject ->> 'subjectType', v_subject_type),
      v_subject ->> 'subjectId',
      v_hash, v_run_id, v_run_id,
      coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
      v_source_at,
      null
    )
    on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
      "subject_type" = excluded."subject_type",
      "subject_id" = excluded."subject_id",
      "content_hash" = excluded."content_hash",
      "last_run_id" = excluded."last_run_id",
      "subject_imported_updated_at" = excluded."subject_imported_updated_at",
      "source_updated_at" = coalesce(excluded."source_updated_at", "better_supabase"."import_records"."source_updated_at"),
      "went_missing_at" = null;
  end loop;

  if v_found then
    v_updated := v_updated + 1;
  else
    v_inserted := v_inserted + 1;
  end if;
  
      end if;
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
      perform "better_supabase"."import_note_issue"(v_run_id, v_entity, coalesce(v_key, ''), 'error', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), v_message);
    end;
  end loop;

  

  perform "better_supabase"."import_note_warnings"(v_run_id, v_entity, v_warnings);

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors, 'diff', v_diff) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
end;
$$;
revoke execute on function "better_supabase"."import_apply_batch"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_apply_batch"(uuid, text, jsonb) to service_role;

-- Turns import mode on for the rest of the transaction (ADR 0141): the outbox
-- applies the imports.events policy, the audit log tags entries as
-- integration with the correlation id import:<run> (imports.audit decides rows
-- or one summary per entity) and ctx.importing() guards skip their side
-- effects. The setting is transaction-local and better_supabase.import_run()
-- only reports it to the service role, so no user session can turn it on.
create or replace function "better_supabase"."begin_import_session"(run uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_status text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role can begin an import session' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  select r."status"::text into v_status from "better_supabase"."import_runs" r where r."id" = begin_import_session.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_status <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  perform set_config('better_supabase.import_run', begin_import_session.run::text, true);
  perform set_config('better_supabase.correlation_id', 'import:' || begin_import_session.run::text, true);
  perform set_config('better_supabase.import_events', '{}', true);
  perform set_config('better_supabase.import_audit', 'rows', true);
  return begin_import_session.run;
end;
$$;
revoke execute on function "better_supabase"."begin_import_session"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."begin_import_session"(uuid) to service_role;

-- The single write path of an import (service role). It begins the import
-- session for its writes and restores the caller's settings afterwards. A dry
-- run writes inside a subtransaction it rolls back, then keeps the counts.
create or replace function "better_supabase"."import_upsert_batch"(run uuid, entity text, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := import_upsert_batch.run;
  v_entity text := import_upsert_batch.entity;
  v_run "better_supabase"."import_runs";
  v_result jsonb;
  v_name text;
  v_previous jsonb := '{}'::jsonb;
begin
  -- No row lock here: two batches of one run write at the same time, and the
  -- counts update at the end is the only statement that locks the run row.
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  if coalesce((v_run."plan" ->> 'unordered')::boolean, false) is distinct from true
    and jsonb_typeof(v_run."plan" -> 'waves') = 'array'
    and exists (
      select 1 from jsonb_array_elements(v_run."plan" -> 'waves') with ordinality as w(wave, n)
      where w.wave ? v_entity and exists (
        select 1 from jsonb_array_elements(v_run."plan" -> 'waves') with ordinality as earlier(wave, n)
        cross join lateral jsonb_array_elements_text(earlier.wave) dep(entity)
        join "better_supabase"."import_chunks" c on c."run_id" = v_run_id
          and c."entity" = dep.entity and c."status" <> 'done'
        where earlier.n < w.n)) then
    raise exception 'an earlier import wave still has open chunks' using errcode = '55000', hint = 'IMPORT_DEPENDENCY_OPEN';
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    v_previous := v_previous || jsonb_build_object(v_name, coalesce(current_setting(v_name, true), ''));
  end loop;
  perform "better_supabase"."begin_import_session"(v_run_id);

  if v_run."dry_run" then
    begin
      v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
      raise exception 'dry run' using errcode = 'BSDRY';
    exception when sqlstate 'BSDRY' then
      null;
    end;
  else
    v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    perform set_config(v_name, v_previous ->> v_name, true);
  end loop;

  update "better_supabase"."import_runs" r set
    "counts" = jsonb_set(r."counts", array[v_entity], jsonb_build_object(
      'inserted', coalesce(r."counts" -> v_entity ->> 'inserted', '0')::integer + coalesce((v_result ->> 'inserted')::integer, 0),
      'updated', coalesce(r."counts" -> v_entity ->> 'updated', '0')::integer + coalesce((v_result ->> 'updated')::integer, 0),
      'unchanged', coalesce(r."counts" -> v_entity ->> 'unchanged', '0')::integer + coalesce((v_result ->> 'unchanged')::integer, 0),
      'conflicted', coalesce(r."counts" -> v_entity ->> 'conflicted', '0')::integer + coalesce((v_result ->> 'conflicted')::integer, 0),
      'missing', coalesce((r."counts" -> v_entity ->> 'missing')::integer, 0)
    )),
    "errors" = r."errors" || coalesce(v_result -> 'errors', '[]'::jsonb),
    "diff" = (select coalesce(jsonb_agg(d.value), '[]'::jsonb) from (
      select value from jsonb_array_elements(r."diff" || coalesce(v_result -> 'diff', '[]'::jsonb)) value limit 100
    ) d)
  where r."id" = v_run_id;
  return v_result || jsonb_build_object('dryRun', v_run."dry_run");
end;
$$;
revoke execute on function "better_supabase"."import_upsert_batch"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_upsert_batch"(uuid, text, jsonb) to service_role;

-- Bulk external key to subject. keys is an array of text, or of { key, scope,
-- role }; a scope that aliases another resolves through it.
create or replace function "better_supabase"."import_resolve"(run uuid, entity text, keys jsonb)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = import_resolve.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if jsonb_typeof(import_resolve.keys) <> 'array' then
    raise exception 'keys must be an array' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('key', q.key, 'scope', q.scope, 'role', q.role, 'subjectType', m."subject_type", 'subjectId', m."subject_id") order by q.ord)
    from (
      select k.ord,
        case when jsonb_typeof(k.value) = 'string' then k.value #>> '{}' else k.value ->> 'key' end as key,
        case when jsonb_typeof(k.value) = 'string' then '' else coalesce(k.value ->> 'scope', '') end as scope,
        case when jsonb_typeof(k.value) = 'string' then 'primary' else coalesce(k.value ->> 'role', 'primary') end as role
      from jsonb_array_elements(import_resolve.keys) with ordinality k(value, ord)
    ) q
    join lateral (
      select x."subject_type", x."subject_id"
      from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source"
        and x."entity" = import_resolve.entity and x."external_key" = q.key and x."role" = q.role
        and (x."scope" = q.scope or x."scope" in (
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = q.scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? import_resolve.entity)
        ))
      order by (x."scope" = q.scope) desc
      limit 1
    ) m on true
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."import_resolve"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_resolve"(uuid, text, jsonb) to service_role;

-- Closes a run that wrote through import_upsert_batch. A full run marks the
-- records of its entities it didn't see, and never deletes them.
create or replace function "better_supabase"."finish_import_run"(run uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := finish_import_run.run;
  v_run "better_supabase"."import_runs";
  v_entity text;
  v_missing integer;
  v_total integer := 0;
  v_counts jsonb;
  v_outcome text := 'completed';
  v_expected integer;
  v_applied integer;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  v_counts := v_run."counts";

  if v_run."full" then
    for v_entity in select k.key from jsonb_object_keys(v_run."counts") k(key) loop
      select count(*)::integer into v_missing from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
        and x."role" = 'primary' and x."last_run_id" <> v_run_id
        and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      if not v_run."dry_run" then
        update "better_supabase"."import_records" x set "went_missing_at" = coalesce(x."went_missing_at", now())
        where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
          and x."last_run_id" <> v_run_id
          and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  if v_run."plan" is not null and jsonb_typeof(v_run."plan") = 'object' then
    for v_entity in select k.key from jsonb_object_keys(v_run."plan") k(key) loop
      v_expected := coalesce((v_run."plan" ->> v_entity)::integer, 0);
      v_applied := coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'unchanged')::integer, 0);
      if v_applied < v_expected then
        v_outcome := 'incomplete';
        v_counts := jsonb_set(coalesce(v_counts, '{}'::jsonb), array[v_entity, 'missing'], to_jsonb(v_expected - v_applied), true);
      end if;
    end loop;
  end if;
  if v_outcome = 'completed' and (jsonb_array_length(coalesce(v_run."errors", '[]'::jsonb)) > 0 or v_counts::text like '%"conflicted":%') then
    v_outcome := 'completed_with_issues';
  end if;

  update "better_supabase"."import_runs" r set "status" = 'completed', "outcome" = v_outcome, "finished_at" = now(), "counts" = v_counts
  where r."id" = v_run_id;

  if not v_run."dry_run" then
    for v_entity in select k.key from jsonb_object_keys(v_counts) k(key) loop
      v_total := v_total + coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0);
      null;
    end loop;
    null;
  end if;
  return v_counts;
end;
$$;
revoke execute on function "better_supabase"."finish_import_run"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."finish_import_run"(uuid) to service_role;

create or replace function "better_supabase"."heartbeat_import_run"(run uuid, seconds integer default 30)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_until timestamptz;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can heartbeat an import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  update "better_supabase"."import_runs" r set "heartbeat_at" = now(), "lease_until" = now() + make_interval(secs => greatest(heartbeat_import_run.seconds, 1))
  where r."id" = heartbeat_import_run.run and r."status" = 'running'
  returning r."lease_until" into v_until;
  if v_until is null then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  return v_until;
end;
$$;
revoke execute on function "better_supabase"."heartbeat_import_run"(uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."heartbeat_import_run"(uuid, integer) to service_role;

create or replace function "better_supabase"."import_ensure_ref"(tenant uuid, kind text, key text, defaults jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_created boolean := false;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can ensure an import ref' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if import_ensure_ref.kind is null or import_ensure_ref.key is null or import_ensure_ref.key = '' then
    raise exception 'a ref needs a kind and a key' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select r."id" into v_id from "better_supabase".import_refs r
  where r."tenant_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
  if v_id is null then
    insert into "better_supabase".import_refs ("tenant_id", "kind", "key", "payload")
    values (import_ensure_ref.tenant, import_ensure_ref.kind, import_ensure_ref.key, coalesce(import_ensure_ref.defaults, '{}'::jsonb))
    on conflict ("tenant_id", "kind", "key") do nothing
    returning "id" into v_id;
    v_created := v_id is not null;
    if v_id is null then
      select r."id" into v_id from "better_supabase".import_refs r
      where r."tenant_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
    end if;
  end if;
  return jsonb_build_object(
    'id', v_id,
    'created', v_created,
    'warnings', case when v_created then jsonb_build_array(jsonb_build_object('code', 'IMPORT_REF_CREATED', 'kind', import_ensure_ref.kind, 'key', import_ensure_ref.key)) else '[]'::jsonb end
  );
end;
$$;
revoke execute on function "better_supabase"."import_ensure_ref"(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_ensure_ref"(uuid, text, text, jsonb) to service_role;

create or replace function "better_supabase"."import_entities"()
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$ select array[]::text[] $$;
revoke execute on function "better_supabase"."import_entities"() from public, anon, authenticated;
grant execute on function "better_supabase"."import_entities"() to service_role;


create or replace function "better_supabase"."rebase_import_records"(tenant uuid, source text, entities text[] default null, keys text[] default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can rebase import records' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  update "better_supabase"."import_records" x
  set "subject_imported_updated_at" = coalesce((null), x."subject_imported_updated_at"),
      "owned_hash" = coalesce((null), x."owned_hash")
  where x."tenant_id" = rebase_import_records.tenant
    and x."source" = rebase_import_records.source
    and (rebase_import_records.entities is null or x."entity" = any (rebase_import_records.entities))
    and (rebase_import_records.keys is null or x."external_key" = any (rebase_import_records.keys));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."rebase_import_records"(uuid, text, text[], text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."rebase_import_records"(uuid, text, text[], text[]) to service_role;


-- Queues one job per chunk of an entity's items, so a worker writes a large
-- import in batches; the dedupe key makes a retry harmless.
create or replace function "better_supabase"."enqueue_import_chunks"(run uuid, entity text, chunks integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
  v_chunk integer;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = enqueue_import_chunks.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if enqueue_import_chunks.chunks is null or enqueue_import_chunks.chunks < 1 then
    raise exception 'chunks must be at least 1' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  for v_chunk in 0 .. enqueue_import_chunks.chunks - 1 loop
    perform "better_supabase"."enqueue_job"(queue => 'imports', payload => jsonb_build_object('run', v_run."id", 'entity', enqueue_import_chunks.entity, 'chunk', v_chunk), dedupe_key => v_run."id"::text || ':' || enqueue_import_chunks.entity || ':' || v_chunk::text, dedupe_running => false);
  end loop;
  return enqueue_import_chunks.chunks;
end;
$$;
revoke execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) to service_role;

-- Stores the items of one chunk of an entity, ready for a worker. Storing a chunk
-- again before it is done replaces its items; a done chunk is left as it is and
-- the answer is false.
create or replace function "better_supabase"."store_import_chunk"(run uuid, entity text, chunk integer, items jsonb)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = store_import_chunk.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if store_import_chunk.chunk is null or store_import_chunk.chunk < 0 or jsonb_typeof(store_import_chunk.items) is distinct from 'array' then
    raise exception 'a chunk has a number from 0 and an array of items' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  insert into "better_supabase"."import_chunks" ("run_id", "tenant_id", "entity", "chunk", "items")
  values (store_import_chunk.run, v_run."tenant_id", store_import_chunk.entity, store_import_chunk.chunk, store_import_chunk.items)
  on conflict ("run_id", "entity", "chunk") do update
    set "items" = excluded."items", "status" = 'pending', "claimed_at" = null
    where "better_supabase"."import_chunks"."status" <> 'done';
  return found;
end;
$$;
revoke execute on function "better_supabase"."store_import_chunk"(uuid, text, integer, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."store_import_chunk"(uuid, text, integer, jsonb) to service_role;

-- Takes a pending chunk, or one whose claim is older than lease seconds (a worker
-- that died), and returns { entity, chunk, items }. Null when the chunk is done,
-- missing or held by a live worker. Rows another worker holds are skipped, not waited for.
create or replace function "better_supabase"."claim_import_chunk"(run uuid, entity text, chunk integer, lease integer default 300)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_items jsonb;
begin
  with pick as (
    select x."run_id", x."entity", x."chunk"
    from "better_supabase"."import_chunks" x
    where x."run_id" = claim_import_chunk.run and x."entity" = claim_import_chunk.entity and x."chunk" = claim_import_chunk.chunk
      and (x."status" = 'pending' or (x."status" = 'claimed' and x."claimed_at" < now() - make_interval(secs => greatest(claim_import_chunk.lease, 1))))
    for update skip locked
  )
  update "better_supabase"."import_chunks" x set "status" = 'claimed', "claimed_at" = now()
  from pick
  where x."run_id" = pick."run_id" and x."entity" = pick."entity" and x."chunk" = pick."chunk"
  returning x."items" into v_items;
  if v_items is null then
    return null;
  end if;
  return jsonb_build_object('entity', claim_import_chunk.entity, 'chunk', claim_import_chunk.chunk, 'items', v_items);
end;
$$;
revoke execute on function "better_supabase"."claim_import_chunk"(uuid, text, integer, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."claim_import_chunk"(uuid, text, integer, integer) to service_role;

-- Marks a claimed chunk done and keeps what its batch answered.
create or replace function "better_supabase"."complete_import_chunk"(run uuid, entity text, chunk integer, result jsonb)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
begin
  update "better_supabase"."import_chunks" x set "status" = 'done', "done_at" = now(), "result" = complete_import_chunk.result
  where x."run_id" = complete_import_chunk.run and x."entity" = complete_import_chunk.entity
    and x."chunk" = complete_import_chunk.chunk and x."status" = 'claimed';
  return found;
end;
$$;
revoke execute on function "better_supabase"."complete_import_chunk"(uuid, text, integer, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_import_chunk"(uuid, text, integer, jsonb) to service_role;

-- One worker step: claim the chunk, write it with import_upsert_batch and mark it
-- done, in one transaction, so a failure leaves the chunk pending for the next try.
-- A chunk that is done answers what its batch answered; one that is missing or
-- held by another worker answers { skipped: true }.
create or replace function "better_supabase"."process_import_chunk"(run uuid, entity text, chunk integer)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_done jsonb;
  v_claim jsonb;
  v_result jsonb;
begin
  select x."result" into v_done from "better_supabase"."import_chunks" x
  where x."run_id" = process_import_chunk.run and x."entity" = process_import_chunk.entity
    and x."chunk" = process_import_chunk.chunk and x."status" = 'done';
  if found then
    return coalesce(v_done, '{}'::jsonb) || jsonb_build_object('done', true);
  end if;
  v_claim := "better_supabase"."claim_import_chunk"(process_import_chunk.run, process_import_chunk.entity, process_import_chunk.chunk);
  if v_claim is null then
    return jsonb_build_object('skipped', true);
  end if;
  v_result := "better_supabase"."import_upsert_batch"(process_import_chunk.run, process_import_chunk.entity, v_claim -> 'items');
  perform "better_supabase"."complete_import_chunk"(process_import_chunk.run, process_import_chunk.entity, process_import_chunk.chunk, v_result);
  return v_result;
end;
$$;
revoke execute on function "better_supabase"."process_import_chunk"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."process_import_chunk"(uuid, text, integer) to service_role;

-- How many chunks of a run are pending, claimed and done, so a caller knows when to
-- finish the run.
create or replace function "better_supabase"."import_chunk_progress"(run uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'pending', count(*) filter (where x."status" = 'pending'),
    'claimed', count(*) filter (where x."status" = 'claimed'),
    'done', count(*) filter (where x."status" = 'done')
  )
  from "better_supabase"."import_chunks" x
  where x."run_id" = import_chunk_progress.run
$$;
revoke execute on function "better_supabase"."import_chunk_progress"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."import_chunk_progress"(uuid) to service_role;

-- Clears the content hash of the records of a source (and entity) that a run of
-- another mapper version last wrote, so the next import treats them as changed and
-- rewrites them through their target (a row a user changed since stays as it is, as
-- for any changed hash). Returns how many records it cleared.
create or replace function "better_supabase"."reapply_import_records"(tenant uuid, source text, mapper_version text, entity text default null)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_count integer;
begin
  update "better_supabase"."import_records" x set "content_hash" = ''
  where x."tenant_id" = reapply_import_records.tenant and x."source" = reapply_import_records.source
    and (reapply_import_records.entity is null or x."entity" = reapply_import_records.entity)
    and x."content_hash" <> ''
    and (select r."mapper_version" from "better_supabase"."import_runs" r where r."id" = x."last_run_id") is distinct from reapply_import_records.mapper_version;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."reapply_import_records"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."reapply_import_records"(uuid, text, text, text) to service_role;

-- The record map of a source as { entity, scope, key, role, hash, subjectType,
-- subjectId }, one object per record in key order, so a caller can compare what the
-- source sends with what was imported without reading the rows.
create or replace function "better_supabase"."export_import_hashes"(tenant uuid, source text, entity text default null)
returns setof jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('entity', x."entity", 'scope', x."scope", 'key', x."external_key", 'role', x."role",
    'hash', x."content_hash", 'subjectType', x."subject_type", 'subjectId', x."subject_id")
  from "better_supabase"."import_records" x
  where x."tenant_id" = export_import_hashes.tenant and x."source" = export_import_hashes.source
    and (export_import_hashes.entity is null or x."entity" = export_import_hashes.entity)
  order by x."entity", x."scope", x."external_key", x."role"
$$;
revoke execute on function "better_supabase"."export_import_hashes"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."export_import_hashes"(uuid, text, text) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."import_runs" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."import_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."import_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."import_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."import_records" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."import_records" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."import_records" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."import_records" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.imports.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."start_import_run"(tenant uuid, source text, options jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."start_import_run"($1, $2, $3) $$;
revoke execute on function "api"."start_import_run"(uuid, text, jsonb) from public, anon;
grant execute on function "api"."start_import_run"(uuid, text, jsonb) to authenticated, service_role;

create or replace function "api"."start_import"(tenant uuid, source text, mapping jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."start_import"($1, $2, $3) $$;
revoke execute on function "api"."start_import"(uuid, text, jsonb) from public, anon;
grant execute on function "api"."start_import"(uuid, text, jsonb) to authenticated, service_role;

create or replace function "api"."get_import_run"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_import_run"($1) $$;
revoke execute on function "api"."get_import_run"(uuid) from public, anon;
grant execute on function "api"."get_import_run"(uuid) to authenticated, service_role;

create or replace function "api"."list_import_runs"(tenant uuid, source text default null, status text default null, row_limit integer default 50)
returns setof jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."list_import_runs"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_import_runs"(uuid, text, text, integer) from public, anon;
grant execute on function "api"."list_import_runs"(uuid, text, text, integer) to authenticated, service_role;

create or replace function "api"."cancel_import_run"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_import_run"($1) $$;
revoke execute on function "api"."cancel_import_run"(uuid) from public, anon;
grant execute on function "api"."cancel_import_run"(uuid) to authenticated, service_role;

create or replace function "api"."mark_import_running"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mark_import_running"($1) $$;
revoke execute on function "api"."mark_import_running"(uuid) from public, anon, authenticated;
grant execute on function "api"."mark_import_running"(uuid) to service_role;

create or replace function "api"."finish_import"(id uuid, status text, count integer, error text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."finish_import"($1, $2, $3, $4) $$;
revoke execute on function "api"."finish_import"(uuid, text, integer, text) from public, anon, authenticated;
grant execute on function "api"."finish_import"(uuid, text, integer, text) to service_role;

create or replace function "api"."list_import_issues"(run uuid, entity text default null, row_limit integer default 50, row_offset integer default 0)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_import_issues"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_import_issues"(uuid, text, integer, integer) from public, anon;
grant execute on function "api"."list_import_issues"(uuid, text, integer, integer) to authenticated, service_role;

create or replace function "api"."list_import_diff"(run uuid, entity text default null, row_limit integer default 50, row_offset integer default 0)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_import_diff"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_import_diff"(uuid, text, integer, integer) from public, anon;
grant execute on function "api"."list_import_diff"(uuid, text, integer, integer) to authenticated, service_role;

create or replace function "api"."resolve_import_conflict"(tenant uuid, source text, entity text, key text, action text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."resolve_import_conflict"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."resolve_import_conflict"(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function "api"."resolve_import_conflict"(uuid, text, text, text, text) to service_role;

create or replace function "api"."resolve_import_conflict"(tenant uuid, source text, entity text, key text, action text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."resolve_import_conflict"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."resolve_import_conflict"(uuid, text, text, text, text) from public, anon;
grant execute on function "api"."resolve_import_conflict"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "api"."import_integrity"(tenant uuid, source text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."import_integrity"($1, $2) $$;
revoke execute on function "api"."import_integrity"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."import_integrity"(uuid, text) to service_role;

create or replace function "api"."import_integrity"(tenant uuid, source text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."import_integrity"($1, $2) $$;
revoke execute on function "api"."import_integrity"(uuid, text) from public, anon;
grant execute on function "api"."import_integrity"(uuid, text) to authenticated, service_role;

create or replace function "api"."register_import_source"(id text, label_key text, description_key text, file_types text[], entities text[], docs_link text default null)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."register_import_source"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."register_import_source"(text, text, text, text[], text[], text) from public, anon, authenticated;
grant execute on function "api"."register_import_source"(text, text, text, text[], text[], text) to service_role;

create or replace function "api"."list_import_sources"()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_import_sources"() $$;
revoke execute on function "api"."list_import_sources"() from public, anon;
grant execute on function "api"."list_import_sources"() to authenticated, service_role;

create or replace function "api"."list_import_source_runs"(tenant uuid, source text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_import_source_runs"($1, $2) $$;
revoke execute on function "api"."list_import_source_runs"(uuid, text) from public, anon;
grant execute on function "api"."list_import_source_runs"(uuid, text) to authenticated, service_role;

create or replace function "api"."import_apply_batch"(run uuid, entity text, items jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_apply_batch"($1, $2, $3) $$;
revoke execute on function "api"."import_apply_batch"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "api"."import_apply_batch"(uuid, text, jsonb) to service_role;

create or replace function "api"."begin_import_session"(run uuid)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."begin_import_session"($1) $$;
revoke execute on function "api"."begin_import_session"(uuid) from public, anon, authenticated;
grant execute on function "api"."begin_import_session"(uuid) to service_role;

create or replace function "api"."import_upsert_batch"(run uuid, entity text, items jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_upsert_batch"($1, $2, $3) $$;
revoke execute on function "api"."import_upsert_batch"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "api"."import_upsert_batch"(uuid, text, jsonb) to service_role;

create or replace function "api"."import_resolve"(run uuid, entity text, keys jsonb)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."import_resolve"($1, $2, $3) $$;
revoke execute on function "api"."import_resolve"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "api"."import_resolve"(uuid, text, jsonb) to service_role;

create or replace function "api"."finish_import_run"(run uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."finish_import_run"($1) $$;
revoke execute on function "api"."finish_import_run"(uuid) from public, anon, authenticated;
grant execute on function "api"."finish_import_run"(uuid) to service_role;

create or replace function "api"."heartbeat_import_run"(run uuid, seconds integer default 30)
returns timestamptz
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."heartbeat_import_run"($1, $2) $$;
revoke execute on function "api"."heartbeat_import_run"(uuid, integer) from public, anon, authenticated;
grant execute on function "api"."heartbeat_import_run"(uuid, integer) to service_role;

create or replace function "api"."import_ensure_ref"(tenant uuid, kind text, key text, defaults jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_ensure_ref"($1, $2, $3, $4) $$;
revoke execute on function "api"."import_ensure_ref"(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function "api"."import_ensure_ref"(uuid, text, text, jsonb) to service_role;

create or replace function "api"."import_entities"()
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."import_entities"() $$;
revoke execute on function "api"."import_entities"() from public, anon, authenticated;
grant execute on function "api"."import_entities"() to service_role;

create or replace function "api"."rebase_import_records"(tenant uuid, source text, entities text[] default null, keys text[] default null)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rebase_import_records"($1, $2, $3, $4) $$;
revoke execute on function "api"."rebase_import_records"(uuid, text, text[], text[]) from public, anon, authenticated;
grant execute on function "api"."rebase_import_records"(uuid, text, text[], text[]) to service_role;

create or replace function "api"."enqueue_import_chunks"(run uuid, entity text, chunks integer)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."enqueue_import_chunks"($1, $2, $3) $$;
revoke execute on function "api"."enqueue_import_chunks"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "api"."enqueue_import_chunks"(uuid, text, integer) to service_role;

create or replace function "api"."store_import_chunk"(run uuid, entity text, chunk integer, items jsonb)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."store_import_chunk"($1, $2, $3, $4) $$;
revoke execute on function "api"."store_import_chunk"(uuid, text, integer, jsonb) from public, anon, authenticated;
grant execute on function "api"."store_import_chunk"(uuid, text, integer, jsonb) to service_role;

create or replace function "api"."claim_import_chunk"(run uuid, entity text, chunk integer, lease integer default 300)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."claim_import_chunk"($1, $2, $3, $4) $$;
revoke execute on function "api"."claim_import_chunk"(uuid, text, integer, integer) from public, anon, authenticated;
grant execute on function "api"."claim_import_chunk"(uuid, text, integer, integer) to service_role;

create or replace function "api"."complete_import_chunk"(run uuid, entity text, chunk integer, result jsonb)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."complete_import_chunk"($1, $2, $3, $4) $$;
revoke execute on function "api"."complete_import_chunk"(uuid, text, integer, jsonb) from public, anon, authenticated;
grant execute on function "api"."complete_import_chunk"(uuid, text, integer, jsonb) to service_role;

create or replace function "api"."process_import_chunk"(run uuid, entity text, chunk integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."process_import_chunk"($1, $2, $3) $$;
revoke execute on function "api"."process_import_chunk"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "api"."process_import_chunk"(uuid, text, integer) to service_role;

create or replace function "api"."import_chunk_progress"(run uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."import_chunk_progress"($1) $$;
revoke execute on function "api"."import_chunk_progress"(uuid) from public, anon, authenticated;
grant execute on function "api"."import_chunk_progress"(uuid) to service_role;

create or replace function "api"."reapply_import_records"(tenant uuid, source text, mapper_version text, entity text default null)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reapply_import_records"($1, $2, $3, $4) $$;
revoke execute on function "api"."reapply_import_records"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "api"."reapply_import_records"(uuid, text, text, text) to service_role;

create or replace function "api"."export_import_hashes"(tenant uuid, source text, entity text default null)
returns setof jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."export_import_hashes"($1, $2, $3) $$;
revoke execute on function "api"."export_import_hashes"(uuid, text, text) from public, anon, authenticated;
grant execute on function "api"."export_import_hashes"(uuid, text, text) to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_064_imports.sql
-- better-supabase module: imports
-- @bsb-block-data imports
-- @bsb-hash sha256:03c82178dd5c9af38535aa92f90002ada8c21fab4dadb8d91c33605f8bdcec29
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('imports', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_064_imports.sql
-- better-supabase module: imports
-- @bsb-block imports@2 managed
-- @bsb-hash sha256:8c196a0ab949914167ff3a655cfa8ca55ebca38c94640e8f43b7f5d25fc7e7ac
-- Import runs and the external record map. import_upsert_batch writes items through the targets blocks and the app register, skips equal content, reports rows a user changed since the last import and marks missing keys on full runs. The dry run, parsing and mapping live in TypeScript.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- better_supabase.import_runs is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."import_runs" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."import_runs" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."import_runs" add column if not exists "source" text;
alter table "better_supabase"."import_runs" add column if not exists "status" text not null default 'pending';
alter table "better_supabase"."import_runs" add column if not exists "mapping" jsonb not null default '{}'::jsonb;
alter table "better_supabase"."import_runs" add column if not exists "counts" jsonb not null default '{}'::jsonb;
alter table "better_supabase"."import_runs" add column if not exists "errors" jsonb not null default '[]'::jsonb;
alter table "better_supabase"."import_runs" add column if not exists "created_by" uuid;
alter table "better_supabase"."import_runs" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."import_runs" add column if not exists "dry_run" boolean not null default false;
alter table "better_supabase"."import_runs" add column if not exists "diff" jsonb not null default '[]'::jsonb;
alter table "better_supabase"."import_runs" add column if not exists "full" boolean not null default false;
alter table "better_supabase"."import_runs" add column if not exists "input_checksum" text;
alter table "better_supabase"."import_runs" add column if not exists "correlation_id" text;
alter table "better_supabase"."import_runs" add column if not exists "mapper_version" text;
alter table "better_supabase"."import_runs" add column if not exists "scope_aliases" jsonb not null default '[]'::jsonb;
alter table "better_supabase"."import_runs" add column if not exists "started_at" timestamptz;
alter table "better_supabase"."import_runs" add column if not exists "finished_at" timestamptz;
alter table "better_supabase"."import_runs" add column if not exists "plan" jsonb;
alter table "better_supabase"."import_runs" add column if not exists "outcome" text;
alter table "better_supabase"."import_runs" add column if not exists "lease_until" timestamptz;
alter table "better_supabase"."import_runs" add column if not exists "heartbeat_at" timestamptz;
alter table "better_supabase"."import_runs" enable row level security;
grant select on "better_supabase"."import_runs" to authenticated;
grant all on "better_supabase"."import_runs" to service_role;
create index if not exists "import_runs_tenant_idx" on "better_supabase"."import_runs" ("tenant_id");
-- One pending or running run per organization and source.
create unique index if not exists "import_runs_active_idx" on "better_supabase"."import_runs" ("tenant_id", "source") where "status" in ('pending', 'running');

-- better_supabase.import_records is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."import_records" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."import_records" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."import_records" add column if not exists "source" text;
alter table "better_supabase"."import_records" add column if not exists "scope" text not null default '';
alter table "better_supabase"."import_records" add column if not exists "entity" text;
alter table "better_supabase"."import_records" add column if not exists "external_key" text;
alter table "better_supabase"."import_records" add column if not exists "role" text not null default 'primary';
alter table "better_supabase"."import_records" add column if not exists "subject_type" text;
alter table "better_supabase"."import_records" add column if not exists "subject_id" text;
alter table "better_supabase"."import_records" add column if not exists "content_hash" text;
alter table "better_supabase"."import_records" add column if not exists "first_run_id" uuid;
alter table "better_supabase"."import_records" add column if not exists "last_run_id" uuid;
alter table "better_supabase"."import_records" add column if not exists "subject_imported_updated_at" timestamptz;
alter table "better_supabase"."import_records" add column if not exists "source_updated_at" timestamptz;
alter table "better_supabase"."import_records" add column if not exists "owned_hash" text;
alter table "better_supabase"."import_records" add column if not exists "went_missing_at" timestamptz;
create index if not exists "import_records_subject_idx" on "better_supabase"."import_records" ("tenant_id", "subject_type", "subject_id");
alter table "better_supabase"."import_records" add column if not exists "owned_hash" text;
alter table "better_supabase"."import_records" add column if not exists "source_updated_at" timestamptz;
alter table "better_supabase"."import_records" enable row level security;
grant select on "better_supabase"."import_records" to authenticated;
grant all on "better_supabase"."import_records" to service_role;
-- better_supabase.import_refs is the app's table: this block adds only the columns it needs.
alter table "better_supabase".import_refs add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase".import_refs add column if not exists "tenant_id" uuid;
alter table "better_supabase".import_refs add column if not exists "kind" text;
alter table "better_supabase".import_refs add column if not exists "key" text;
alter table "better_supabase".import_refs add column if not exists "payload" jsonb not null default '{}'::jsonb;
alter table "better_supabase".import_refs add column if not exists "created_at" timestamptz not null default now();

-- better_supabase.import_chunks is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."import_chunks" add column if not exists "run_id" uuid references "better_supabase"."import_runs" ("id") on delete cascade;
alter table "better_supabase"."import_chunks" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."import_chunks" add column if not exists "entity" text;
alter table "better_supabase"."import_chunks" add column if not exists "chunk" integer;
alter table "better_supabase"."import_chunks" add column if not exists "items" jsonb;
alter table "better_supabase"."import_chunks" add column if not exists "status" text not null default 'pending';
alter table "better_supabase"."import_chunks" add column if not exists "result" jsonb;
alter table "better_supabase"."import_chunks" add column if not exists "claimed_at" timestamptz;
alter table "better_supabase"."import_chunks" add column if not exists "done_at" timestamptz;
alter table "better_supabase"."import_chunks" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."import_chunks" enable row level security;
grant all on "better_supabase"."import_chunks" to service_role;
create index if not exists "import_chunks_tenant_idx" on "better_supabase"."import_chunks" ("tenant_id");


-- better_supabase.import_run_issues is the app's table: this block adds only the columns it needs.
alter table "better_supabase".import_run_issues add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase".import_run_issues add column if not exists "run_id" uuid;
alter table "better_supabase".import_run_issues add column if not exists "tenant_id" uuid;
alter table "better_supabase".import_run_issues add column if not exists "source" text;
alter table "better_supabase".import_run_issues add column if not exists "entity" text;
alter table "better_supabase".import_run_issues add column if not exists "key" text;
alter table "better_supabase".import_run_issues add column if not exists "kind" text;
alter table "better_supabase".import_run_issues add column if not exists "code" text;
alter table "better_supabase".import_run_issues add column if not exists "message" text;
alter table "better_supabase".import_run_issues add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase".import_run_issues add column if not exists "resolved_at" timestamptz;
create index if not exists import_run_issues_open_idx
  on "better_supabase".import_run_issues ("tenant_id", "source", "entity", "key")
  where "resolved_at" is null;
create index if not exists import_run_issues_run_idx
  on "better_supabase".import_run_issues ("run_id", "entity");

create or replace function "better_supabase"."start_import_run"(tenant uuid, source text, options jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_options jsonb := coalesce(start_import_run.options, '{}'::jsonb);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', start_import_run.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if start_import_run.source is null or start_import_run.source = '' then
    raise exception 'an import run needs a source' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(coalesce(v_options -> 'scopeAliases', '[]'::jsonb)) <> 'array' then
    raise exception 'scopeAliases must be an array of { scope, of, entities }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    insert into "better_supabase"."import_runs" as r ("tenant_id", "source", "mapping", "dry_run", "full", "input_checksum", "correlation_id", "mapper_version", "scope_aliases", "plan", "lease_until", "created_by")
    values (
      start_import_run.tenant,
      start_import_run.source,
      coalesce(v_options -> 'mapping', '{}'::jsonb),
      coalesce((v_options ->> 'dryRun')::boolean, false),
      coalesce((v_options ->> 'full')::boolean, false),
      v_options ->> 'inputChecksum',
      v_options ->> 'correlationId',
      nullif(v_options ->> 'mapperVersion', ''),
      coalesce(v_options -> 'scopeAliases', '[]'::jsonb),
      v_options -> 'plan',
      now() + interval '30 seconds',
      auth.uid()
    )
    returning r."id" into v_id;
  exception when unique_violation then
    raise exception 'an import of this source is already pending or running' using errcode = '55P03', hint = 'IMPORT_RUN_ACTIVE';
  end;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."start_import_run"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."start_import_run"(uuid, text, jsonb) to authenticated, service_role;

-- The first release's entry point: a run without options.
create or replace function "better_supabase"."start_import"(tenant uuid, source text, mapping jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select "better_supabase"."start_import_run"(start_import.tenant, start_import.source, jsonb_build_object('mapping', coalesce(start_import.mapping, '{}'::jsonb)));
$$;
revoke execute on function "better_supabase"."start_import"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."start_import"(uuid, text, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_import_run"(id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = get_import_run.id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_run."tenant_id", 'imports.manage'), false)) then
    raise exception 'not allowed to read this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."tenant_id", 'source', v_run."source", 'status', v_run."status", 'outcome', v_run."outcome", 'plan', v_run."plan", 'mapping', v_run."mapping", 'counts', v_run."counts", 'errors', v_run."errors", 'dryRun', v_run."dry_run", 'full', v_run."full", 'inputChecksum', v_run."input_checksum", 'correlationId', v_run."correlation_id", 'mapperVersion', v_run."mapper_version", 'scopeAliases', v_run."scope_aliases", 'leaseUntil', v_run."lease_until", 'heartbeatAt', v_run."heartbeat_at", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'startedAt', v_run."started_at", 'finishedAt', v_run."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "better_supabase".import_run_issues i
    where i."run_id" = v_run."id"
  ));
end;
$$;
revoke execute on function "better_supabase"."get_import_run"(uuid) from public, anon;
grant execute on function "better_supabase"."get_import_run"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_import_runs"(tenant uuid, source text default null, status text default null, row_limit integer default 50)
returns setof jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_import_runs.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list imports' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  return query
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'source', r."source", 'status', r."status", 'outcome', r."outcome", 'plan', r."plan", 'mapping', r."mapping", 'counts', r."counts", 'errors', r."errors", 'dryRun', r."dry_run", 'full', r."full", 'inputChecksum', r."input_checksum", 'correlationId', r."correlation_id", 'mapperVersion', r."mapper_version", 'scopeAliases', r."scope_aliases", 'leaseUntil', r."lease_until", 'heartbeatAt', r."heartbeat_at", 'createdBy', r."created_by", 'createdAt', r."created_at", 'startedAt', r."started_at", 'finishedAt', r."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "better_supabase".import_run_issues i
    where i."run_id" = r."id"
  ))
    from "better_supabase"."import_runs" r
    where r."tenant_id" = list_import_runs.tenant
      and (list_import_runs.source is null or r."source" = list_import_runs.source)
      and (list_import_runs.status is null or r."status" = list_import_runs.status)
    order by r."created_at" desc, r."id" desc
    limit least(greatest(coalesce(list_import_runs.row_limit, 50), 1), 200);
end;
$$;
revoke execute on function "better_supabase"."list_import_runs"(uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_import_runs"(uuid, text, text, integer) to authenticated, service_role;

create or replace function "better_supabase"."cancel_import_run"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_run "better_supabase"."import_runs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_run from "better_supabase"."import_runs" r where r."id" = cancel_import_run.id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_run."tenant_id", 'imports.manage'), false)) then
    raise exception 'not allowed to cancel this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if v_run."status" not in ('pending', 'running') then
    raise exception 'this import already finished' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  update "better_supabase"."import_runs" r set "status" = better_supabase.as_column_type('canceled', (null::"better_supabase"."import_runs")."status"), "finished_at" = now()
  where r."id" = cancel_import_run.id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_import_run"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_import_run"(uuid) to authenticated, service_role;

-- The run moves from pending to running before the first batch, so a run
-- that dies mid-way is visible as running rather than pending.
create or replace function "better_supabase"."mark_import_running"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  update "better_supabase"."import_runs" set "status" = 'running', "started_at" = now()
  where "id" = mark_import_running.id and "status" = 'pending';
  if not found then
    raise exception 'no pending import with this id' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."mark_import_running"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_import_running"(uuid) to service_role;

-- Closes a run whose rows the caller wrote itself (`defineImport` without a
-- target); `finish_import_run` closes a run that used `import_upsert_batch`.
create or replace function "better_supabase"."finish_import"(id uuid, status text, count integer, error text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_source text;
begin
  update "better_supabase"."import_runs" set "status" = better_supabase.as_column_type(finish_import.status, (null::"better_supabase"."import_runs")."status"),
    "finished_at" = now(),
    "counts" = case when finish_import.status = 'completed' then jsonb_build_object("source", jsonb_build_object('inserted', finish_import.count, 'updated', 0, 'unchanged', 0, 'conflicted', 0, 'missing', 0)) else "counts" end,
    "errors" = case when finish_import.error is null then "errors" else "errors" || jsonb_build_array(jsonb_build_object('entity', "source", 'key', null, 'code', 'IMPORT_ITEM_INVALID', 'message', finish_import.error)) end
  where "id" = finish_import.id
  returning "tenant_id", "source" into v_tenant, v_source;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if finish_import.status = 'failed' then
    null;
  else
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."finish_import"(uuid, text, integer, text) from public, anon, authenticated;
grant execute on function "better_supabase"."finish_import"(uuid, text, integer, text) to service_role;

create or replace function "better_supabase"."import_note_issue"(run uuid, entity text, key text, kind text, code text, message text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_source text;
begin
  select r."tenant_id", r."source" into v_tenant, v_source
  from "better_supabase"."import_runs" r where r."id" = import_note_issue.run;
  if v_tenant is null or import_note_issue.key is null or import_note_issue.key = '' then
    return;
  end if;
  insert into "better_supabase".import_run_issues ("run_id", "tenant_id", "source", "entity", "key", "kind", "code", "message")
  values (import_note_issue.run, v_tenant, v_source, import_note_issue.entity, import_note_issue.key, import_note_issue.kind, import_note_issue.code, import_note_issue.message);
end;
$$;

create or replace function "better_supabase"."import_note_warnings"(run uuid, entity text, warnings jsonb)
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
    perform "better_supabase"."import_note_issue"(
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

create or replace function "better_supabase"."import_clear_issues"(run uuid, entity text, key text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_source text;
begin
  select r."tenant_id", r."source" into v_tenant, v_source
  from "better_supabase"."import_runs" r where r."id" = import_clear_issues.run;
  if v_tenant is null then
    return;
  end if;
  update "better_supabase".import_run_issues i set "resolved_at" = now()
  where i."tenant_id" = v_tenant and i."source" = v_source
    and i."entity" = import_clear_issues.entity and i."key" = import_clear_issues.key
    and i."resolved_at" is null;
end;
$$;

create or replace function "better_supabase"."list_import_issues"(run uuid, entity text default null, row_limit integer default 50, row_offset integer default 0)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_total integer;
  v_rows jsonb;
begin
  select r."tenant_id" into v_tenant from "better_supabase"."import_runs" r where r."id" = list_import_issues.run;
  if v_tenant is null then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list import issues' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  select count(*) into v_total from "better_supabase".import_run_issues i
  where i."run_id" = list_import_issues.run
    and (list_import_issues.entity is null or i."entity" = list_import_issues.entity);
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_rows from (
    select i."entity", i."key", i."kind", i."code", i."message", i."created_at", i."resolved_at"
    from "better_supabase".import_run_issues i
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
revoke execute on function "better_supabase"."list_import_issues"(uuid, text, integer, integer) from public, anon;
grant execute on function "better_supabase"."list_import_issues"(uuid, text, integer, integer) to authenticated, service_role;

-- Counts and the first changed fields of a dry run. The dry run itself writes
-- no subject rows; the diff is what the batch returned.
create or replace function "better_supabase"."list_import_diff"(run uuid, entity text default null, row_limit integer default 50, row_offset integer default 0)
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
  select r."counts", r."diff" into v_counts, v_diff from "better_supabase"."import_runs" r where r."id" = list_import_diff.run;
  if v_counts is null then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
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
revoke execute on function "better_supabase"."list_import_diff"(uuid, text, integer, integer) from public, anon;
grant execute on function "better_supabase"."list_import_diff"(uuid, text, integer, integer) to authenticated, service_role;

create or replace function "better_supabase"."resolve_import_conflict"(tenant uuid, source text, entity text, key text, action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resolved integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', resolve_import_conflict.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to resolve an import conflict' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if resolve_import_conflict.action = 'keep' then
    update "better_supabase"."import_records" x set "subject_imported_updated_at" = now()
    where x."tenant_id" = resolve_import_conflict.tenant
      and x."source" = resolve_import_conflict.source
      and x."entity" = resolve_import_conflict.entity
      and x."external_key" = resolve_import_conflict.key;
  elsif resolve_import_conflict.action = 'overwrite' then
    update "better_supabase"."import_records" x set "subject_imported_updated_at" = null, "owned_hash" = null
    where x."tenant_id" = resolve_import_conflict.tenant
      and x."source" = resolve_import_conflict.source
      and x."entity" = resolve_import_conflict.entity
      and x."external_key" = resolve_import_conflict.key;
  else
    raise exception 'action must be keep or overwrite' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  update "better_supabase".import_run_issues i set "resolved_at" = now()
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
revoke execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) to service_role;
revoke execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."import_integrity"(tenant uuid, source text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_checks jsonb := '[]'::jsonb;
  v_name text;
  v_severity text;
  v_count integer;
  v_ids jsonb;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', import_integrity.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to check this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  for v_name, v_severity, v_count, v_ids in
    select 'duplicate_keys', 'error', count(*)::integer, coalesce(jsonb_agg(sample), '[]'::jsonb) from (
      select min(d."id"::text) as sample from "better_supabase"."import_records" d
      where d."tenant_id" = import_integrity.tenant
        and (import_integrity.source is null or d."source" = import_integrity.source)
      group by d."entity", d."external_key"
      having count(distinct d."subject_id") > 1
    ) q
  loop
    v_checks := v_checks || jsonb_build_array(jsonb_build_object(
      'name', v_name, 'severity', v_severity, 'count', v_count, 'ids', coalesce(v_ids, '[]'::jsonb)));
  end loop;
  return jsonb_build_object('checks', v_checks);
end;
$$;
revoke execute on function "better_supabase"."import_integrity"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_integrity"(uuid, text) to service_role;
revoke execute on function "better_supabase"."import_integrity"(uuid, text) from public, anon;
grant execute on function "better_supabase"."import_integrity"(uuid, text) to authenticated, service_role;

-- better_supabase.import_sources is the app's table: this block adds only the columns it needs.
alter table "better_supabase".import_sources add column if not exists "id" text;
alter table "better_supabase".import_sources add column if not exists "label_key" text;
alter table "better_supabase".import_sources add column if not exists "description_key" text;
alter table "better_supabase".import_sources add column if not exists "file_types" text[] not null default '{}';
alter table "better_supabase".import_sources add column if not exists "entities" text[] not null default '{}';
alter table "better_supabase".import_sources add column if not exists "docs_link" text;

create or replace function "better_supabase"."register_import_source"(id text, label_key text, description_key text, file_types text[], entities text[], docs_link text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'not allowed to register an import source' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  insert into "better_supabase".import_sources ("id", "label_key", "description_key", "file_types", "entities", "docs_link")
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
revoke execute on function "better_supabase"."register_import_source"(text, text, text, text[], text[], text) from public, anon, authenticated;
grant execute on function "better_supabase"."register_import_source"(text, text, text, text[], text[], text) to service_role;

create or replace function "better_supabase"."list_import_sources"()
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
  from "better_supabase".import_sources s
$$;
revoke execute on function "better_supabase"."list_import_sources"() from public, anon;
grant execute on function "better_supabase"."list_import_sources"() to authenticated, service_role;

-- Every run of the tenant, whoever started it: the CLI, an API or the UI.
create or replace function "better_supabase"."list_import_source_runs"(tenant uuid, source text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r."id", 'source', r."source", 'status', r."status", 'createdAt', r."created_at"
  ) order by r."created_at" desc), '[]'::jsonb)
  from "better_supabase"."import_runs" r
  where r."tenant_id" = list_import_source_runs.tenant
    and (list_import_source_runs.source is null or r."source" = list_import_source_runs.source)
$$;
revoke execute on function "better_supabase"."list_import_source_runs"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_import_source_runs"(uuid, text) to authenticated, service_role;


-- Writes the items of one entity: an unknown key inserts, an equal hash is
-- unchanged and writes nothing, a changed hash updates unless the row changed
-- after the last import (conflicted). Returns the counts and the item errors.
create or replace function "better_supabase"."import_apply_batch"(run uuid, entity text, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := import_apply_batch.run;
  v_entity text := import_apply_batch.entity;
  v_items jsonb := import_apply_batch.items;
  v_run "better_supabase"."import_runs";
  v_item jsonb;
  v_call jsonb;
  v_key text;
  v_scope text;
  v_data jsonb;
  v_hash text;
  v_source_at timestamptz;
  v_diff jsonb := '[]'::jsonb;
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_owned text;
  v_natural text;
  v_ref_map jsonb := '{}'::jsonb;
  v_resolved jsonb := '{}'::jsonb;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_issue text;
  v_message text;
  v_hint text;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if v_entity <> all (array[]::text[]) then
    raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    raise exception 'items must be an array of { key, scope, data, refs }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  v_ref_map := '{}'::jsonb;

  for v_item in
    select e.value from jsonb_array_elements(v_items) e
    order by e.value #>> '{data,orderBy}', e.value #>> '{data,readAt}', e.value ->> 'key'
  loop
    v_issue := null;
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      perform "better_supabase"."import_note_issue"(v_run_id, v_entity, coalesce(v_key, ''), 'error', 'IMPORT_ITEM_INVALID', 'an item needs a key and a data object');
      continue;
    end if;

    

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;
      v_source_at := nullif(v_item ->> 'sourceUpdatedAt', '')::timestamptz;
      if v_found and v_source_at is not null and v_rec."source_updated_at" is not null and v_source_at <= v_rec."source_updated_at" then
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');
      end if;

      if v_done then
        null;
      elsif not v_found then
        v_natural := null;
        null;
        if v_natural is not null then
          v_found := true;
          v_rec."subject_id" := v_natural;
          v_rec."content_hash" := '';
        end if;
      end if;

      if v_done then
        null;
      elsif not v_found then
        -- A cloned administration reuses the subjects of the scope it aliases
        -- when the content is equal there.
        for v_other in
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = v_scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? v_entity)
        loop
          if exists (
            select 1 from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary' and x."content_hash" = v_hash
          ) then
            insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_imported_updated_at"
            from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key
            on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do nothing;
            v_unchanged := v_unchanged + 1;
            v_done := true;
            exit;
          end if;
        end loop;
      elsif v_rec."content_hash" = v_hash then
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."went_missing_at" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        v_owned := null;
        null;
        null;
        if v_owned is not null and v_rec."owned_hash" is not null and v_owned is distinct from v_rec."owned_hash" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_issue := 'conflict';
          v_done := true;
        elsif v_owned is not null and v_current is not null and v_rec."subject_imported_updated_at" is not null and v_current > v_rec."subject_imported_updated_at" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "subject_imported_updated_at" = v_current, "owned_hash" = v_owned
          where x."id" = v_rec."id";
        elsif v_owned is null and v_current is not null and v_rec."subject_imported_updated_at" is not null and v_current > v_rec."subject_imported_updated_at" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_issue := 'conflict';
          v_done := true;
        end if;
      end if;

      if v_issue = 'conflict' then
        perform "better_supabase"."import_note_issue"(v_run_id, v_entity, v_key, 'conflict', 'IMPORT_CONFLICT', 'the subject changed after the last import');
      else
        perform "better_supabase"."import_clear_issues"(v_run_id, v_entity, v_key);
      end if;

      if not v_done and v_run."dry_run" and jsonb_typeof(v_item -> 'previous') = 'object' and jsonb_array_length(v_diff) < 20 then
        v_diff := v_diff || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'fields', (
          select coalesce(jsonb_agg(jsonb_build_object('field', k, 'old', v_item -> 'previous' -> k, 'new', v_data -> k)), '[]'::jsonb)
          from jsonb_object_keys(v_data) k where (v_data -> k) is distinct from (v_item -> 'previous' -> k))));
      end if;
      if not v_done then
        v_subject_id := case when v_found then v_rec."subject_id" else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run."tenant_id", 'scope', v_scope);
        
        raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';

          v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
  if not exists (
    select 1 from jsonb_array_elements(v_subjects) s
    where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
  ) then
    raise exception 'the import target returned no primary subject' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
    if jsonb_typeof(v_subject -> 'warnings') = 'array' then
      v_warnings := v_warnings || (select coalesce(jsonb_agg(w.value || jsonb_build_object('entity', v_entity, 'key', v_key)), '[]'::jsonb) from jsonb_array_elements(v_subject -> 'warnings') w);
    end if;
    insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at", "source_updated_at", "went_missing_at")
    values (
      v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
      coalesce(v_subject ->> 'role', 'primary'),
      coalesce(v_subject ->> 'subjectType', v_subject_type),
      v_subject ->> 'subjectId',
      v_hash, v_run_id, v_run_id,
      coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
      v_source_at,
      null
    )
    on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
      "subject_type" = excluded."subject_type",
      "subject_id" = excluded."subject_id",
      "content_hash" = excluded."content_hash",
      "last_run_id" = excluded."last_run_id",
      "subject_imported_updated_at" = excluded."subject_imported_updated_at",
      "source_updated_at" = coalesce(excluded."source_updated_at", "better_supabase"."import_records"."source_updated_at"),
      "went_missing_at" = null;
  end loop;

  if v_found then
    v_updated := v_updated + 1;
  else
    v_inserted := v_inserted + 1;
  end if;
  
      end if;
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
      perform "better_supabase"."import_note_issue"(v_run_id, v_entity, coalesce(v_key, ''), 'error', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), v_message);
    end;
  end loop;

  

  perform "better_supabase"."import_note_warnings"(v_run_id, v_entity, v_warnings);

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors, 'diff', v_diff) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
end;
$$;
revoke execute on function "better_supabase"."import_apply_batch"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_apply_batch"(uuid, text, jsonb) to service_role;

-- Turns import mode on for the rest of the transaction (ADR 0141): the outbox
-- applies the imports.events policy, the audit log tags entries as
-- integration with the correlation id import:<run> (imports.audit decides rows
-- or one summary per entity) and ctx.importing() guards skip their side
-- effects. The setting is transaction-local and better_supabase.import_run()
-- only reports it to the service role, so no user session can turn it on.
create or replace function "better_supabase"."begin_import_session"(run uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_status text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role can begin an import session' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  select r."status"::text into v_status from "better_supabase"."import_runs" r where r."id" = begin_import_session.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_status <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  perform set_config('better_supabase.import_run', begin_import_session.run::text, true);
  perform set_config('better_supabase.correlation_id', 'import:' || begin_import_session.run::text, true);
  perform set_config('better_supabase.import_events', '{}', true);
  perform set_config('better_supabase.import_audit', 'rows', true);
  return begin_import_session.run;
end;
$$;
revoke execute on function "better_supabase"."begin_import_session"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."begin_import_session"(uuid) to service_role;

-- The single write path of an import (service role). It begins the import
-- session for its writes and restores the caller's settings afterwards. A dry
-- run writes inside a subtransaction it rolls back, then keeps the counts.
create or replace function "better_supabase"."import_upsert_batch"(run uuid, entity text, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := import_upsert_batch.run;
  v_entity text := import_upsert_batch.entity;
  v_run "better_supabase"."import_runs";
  v_result jsonb;
  v_name text;
  v_previous jsonb := '{}'::jsonb;
begin
  -- No row lock here: two batches of one run write at the same time, and the
  -- counts update at the end is the only statement that locks the run row.
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  if coalesce((v_run."plan" ->> 'unordered')::boolean, false) is distinct from true
    and jsonb_typeof(v_run."plan" -> 'waves') = 'array'
    and exists (
      select 1 from jsonb_array_elements(v_run."plan" -> 'waves') with ordinality as w(wave, n)
      where w.wave ? v_entity and exists (
        select 1 from jsonb_array_elements(v_run."plan" -> 'waves') with ordinality as earlier(wave, n)
        cross join lateral jsonb_array_elements_text(earlier.wave) dep(entity)
        join "better_supabase"."import_chunks" c on c."run_id" = v_run_id
          and c."entity" = dep.entity and c."status" <> 'done'
        where earlier.n < w.n)) then
    raise exception 'an earlier import wave still has open chunks' using errcode = '55000', hint = 'IMPORT_DEPENDENCY_OPEN';
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    v_previous := v_previous || jsonb_build_object(v_name, coalesce(current_setting(v_name, true), ''));
  end loop;
  perform "better_supabase"."begin_import_session"(v_run_id);

  if v_run."dry_run" then
    begin
      v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
      raise exception 'dry run' using errcode = 'BSDRY';
    exception when sqlstate 'BSDRY' then
      null;
    end;
  else
    v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    perform set_config(v_name, v_previous ->> v_name, true);
  end loop;

  update "better_supabase"."import_runs" r set
    "counts" = jsonb_set(r."counts", array[v_entity], jsonb_build_object(
      'inserted', coalesce(r."counts" -> v_entity ->> 'inserted', '0')::integer + coalesce((v_result ->> 'inserted')::integer, 0),
      'updated', coalesce(r."counts" -> v_entity ->> 'updated', '0')::integer + coalesce((v_result ->> 'updated')::integer, 0),
      'unchanged', coalesce(r."counts" -> v_entity ->> 'unchanged', '0')::integer + coalesce((v_result ->> 'unchanged')::integer, 0),
      'conflicted', coalesce(r."counts" -> v_entity ->> 'conflicted', '0')::integer + coalesce((v_result ->> 'conflicted')::integer, 0),
      'missing', coalesce((r."counts" -> v_entity ->> 'missing')::integer, 0)
    )),
    "errors" = r."errors" || coalesce(v_result -> 'errors', '[]'::jsonb),
    "diff" = (select coalesce(jsonb_agg(d.value), '[]'::jsonb) from (
      select value from jsonb_array_elements(r."diff" || coalesce(v_result -> 'diff', '[]'::jsonb)) value limit 100
    ) d)
  where r."id" = v_run_id;
  return v_result || jsonb_build_object('dryRun', v_run."dry_run");
end;
$$;
revoke execute on function "better_supabase"."import_upsert_batch"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_upsert_batch"(uuid, text, jsonb) to service_role;

-- Bulk external key to subject. keys is an array of text, or of { key, scope,
-- role }; a scope that aliases another resolves through it.
create or replace function "better_supabase"."import_resolve"(run uuid, entity text, keys jsonb)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = import_resolve.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if jsonb_typeof(import_resolve.keys) <> 'array' then
    raise exception 'keys must be an array' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('key', q.key, 'scope', q.scope, 'role', q.role, 'subjectType', m."subject_type", 'subjectId', m."subject_id") order by q.ord)
    from (
      select k.ord,
        case when jsonb_typeof(k.value) = 'string' then k.value #>> '{}' else k.value ->> 'key' end as key,
        case when jsonb_typeof(k.value) = 'string' then '' else coalesce(k.value ->> 'scope', '') end as scope,
        case when jsonb_typeof(k.value) = 'string' then 'primary' else coalesce(k.value ->> 'role', 'primary') end as role
      from jsonb_array_elements(import_resolve.keys) with ordinality k(value, ord)
    ) q
    join lateral (
      select x."subject_type", x."subject_id"
      from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source"
        and x."entity" = import_resolve.entity and x."external_key" = q.key and x."role" = q.role
        and (x."scope" = q.scope or x."scope" in (
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = q.scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? import_resolve.entity)
        ))
      order by (x."scope" = q.scope) desc
      limit 1
    ) m on true
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."import_resolve"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_resolve"(uuid, text, jsonb) to service_role;

-- Closes a run that wrote through import_upsert_batch. A full run marks the
-- records of its entities it didn't see, and never deletes them.
create or replace function "better_supabase"."finish_import_run"(run uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := finish_import_run.run;
  v_run "better_supabase"."import_runs";
  v_entity text;
  v_missing integer;
  v_total integer := 0;
  v_counts jsonb;
  v_outcome text := 'completed';
  v_expected integer;
  v_applied integer;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  v_counts := v_run."counts";

  if v_run."full" then
    for v_entity in select k.key from jsonb_object_keys(v_run."counts") k(key) loop
      select count(*)::integer into v_missing from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
        and x."role" = 'primary' and x."last_run_id" <> v_run_id
        and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      if not v_run."dry_run" then
        update "better_supabase"."import_records" x set "went_missing_at" = coalesce(x."went_missing_at", now())
        where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
          and x."last_run_id" <> v_run_id
          and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  if v_run."plan" is not null and jsonb_typeof(v_run."plan") = 'object' then
    for v_entity in select k.key from jsonb_object_keys(v_run."plan") k(key) loop
      v_expected := coalesce((v_run."plan" ->> v_entity)::integer, 0);
      v_applied := coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'unchanged')::integer, 0);
      if v_applied < v_expected then
        v_outcome := 'incomplete';
        v_counts := jsonb_set(coalesce(v_counts, '{}'::jsonb), array[v_entity, 'missing'], to_jsonb(v_expected - v_applied), true);
      end if;
    end loop;
  end if;
  if v_outcome = 'completed' and (jsonb_array_length(coalesce(v_run."errors", '[]'::jsonb)) > 0 or v_counts::text like '%"conflicted":%') then
    v_outcome := 'completed_with_issues';
  end if;

  update "better_supabase"."import_runs" r set "status" = better_supabase.as_column_type('completed', (null::"better_supabase"."import_runs")."status"), "outcome" = v_outcome, "finished_at" = now(), "counts" = v_counts
  where r."id" = v_run_id;

  if not v_run."dry_run" then
    for v_entity in select k.key from jsonb_object_keys(v_counts) k(key) loop
      v_total := v_total + coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0);
      null;
    end loop;
    null;
  end if;
  return v_counts;
end;
$$;
revoke execute on function "better_supabase"."finish_import_run"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."finish_import_run"(uuid) to service_role;

create or replace function "better_supabase"."heartbeat_import_run"(run uuid, seconds integer default 30)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_until timestamptz;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can heartbeat an import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  update "better_supabase"."import_runs" r set "heartbeat_at" = now(), "lease_until" = now() + make_interval(secs => greatest(heartbeat_import_run.seconds, 1))
  where r."id" = heartbeat_import_run.run and r."status" = 'running'
  returning r."lease_until" into v_until;
  if v_until is null then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  return v_until;
end;
$$;
revoke execute on function "better_supabase"."heartbeat_import_run"(uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."heartbeat_import_run"(uuid, integer) to service_role;

create or replace function "better_supabase"."import_ensure_ref"(tenant uuid, kind text, key text, defaults jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_created boolean := false;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can ensure an import ref' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if import_ensure_ref.kind is null or import_ensure_ref.key is null or import_ensure_ref.key = '' then
    raise exception 'a ref needs a kind and a key' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select r."id" into v_id from "better_supabase".import_refs r
  where r."tenant_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
  if v_id is null then
    insert into "better_supabase".import_refs ("tenant_id", "kind", "key", "payload")
    values (import_ensure_ref.tenant, import_ensure_ref.kind, import_ensure_ref.key, coalesce(import_ensure_ref.defaults, '{}'::jsonb))
    on conflict ("tenant_id", "kind", "key") do nothing
    returning "id" into v_id;
    v_created := v_id is not null;
    if v_id is null then
      select r."id" into v_id from "better_supabase".import_refs r
      where r."tenant_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
    end if;
  end if;
  return jsonb_build_object(
    'id', v_id,
    'created', v_created,
    'warnings', case when v_created then jsonb_build_array(jsonb_build_object('code', 'IMPORT_REF_CREATED', 'kind', import_ensure_ref.kind, 'key', import_ensure_ref.key)) else '[]'::jsonb end
  );
end;
$$;
revoke execute on function "better_supabase"."import_ensure_ref"(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_ensure_ref"(uuid, text, text, jsonb) to service_role;

create or replace function "better_supabase"."import_entities"()
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$ select array[]::text[] $$;
revoke execute on function "better_supabase"."import_entities"() from public, anon, authenticated;
grant execute on function "better_supabase"."import_entities"() to service_role;


create or replace function "better_supabase"."rebase_import_records"(tenant uuid, source text, entities text[] default null, keys text[] default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can rebase import records' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  update "better_supabase"."import_records" x
  set "subject_imported_updated_at" = coalesce((null), x."subject_imported_updated_at"),
      "owned_hash" = coalesce((null), x."owned_hash")
  where x."tenant_id" = rebase_import_records.tenant
    and x."source" = rebase_import_records.source
    and (rebase_import_records.entities is null or x."entity" = any (rebase_import_records.entities))
    and (rebase_import_records.keys is null or x."external_key" = any (rebase_import_records.keys));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."rebase_import_records"(uuid, text, text[], text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."rebase_import_records"(uuid, text, text[], text[]) to service_role;


-- Queues one job per chunk of an entity's items, so a worker writes a large
-- import in batches; the dedupe key makes a retry harmless.
create or replace function "better_supabase"."enqueue_import_chunks"(run uuid, entity text, chunks integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
  v_chunk integer;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = enqueue_import_chunks.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if enqueue_import_chunks.chunks is null or enqueue_import_chunks.chunks < 1 then
    raise exception 'chunks must be at least 1' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  for v_chunk in 0 .. enqueue_import_chunks.chunks - 1 loop
    perform "better_supabase"."enqueue_job"(queue => 'imports', payload => jsonb_build_object('run', v_run."id", 'entity', enqueue_import_chunks.entity, 'chunk', v_chunk), dedupe_key => v_run."id"::text || ':' || enqueue_import_chunks.entity || ':' || v_chunk::text, dedupe_running => false);
  end loop;
  return enqueue_import_chunks.chunks;
end;
$$;
revoke execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) to service_role;

-- Stores the items of one chunk of an entity, ready for a worker. Storing a chunk
-- again before it is done replaces its items; a done chunk is left as it is and
-- the answer is false.
create or replace function "better_supabase"."store_import_chunk"(run uuid, entity text, chunk integer, items jsonb)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = store_import_chunk.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if store_import_chunk.chunk is null or store_import_chunk.chunk < 0 or jsonb_typeof(store_import_chunk.items) is distinct from 'array' then
    raise exception 'a chunk has a number from 0 and an array of items' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  insert into "better_supabase"."import_chunks" ("run_id", "tenant_id", "entity", "chunk", "items")
  values (store_import_chunk.run, v_run."tenant_id", store_import_chunk.entity, store_import_chunk.chunk, store_import_chunk.items)
  on conflict ("run_id", "entity", "chunk") do update
    set "items" = excluded."items", "status" = 'pending', "claimed_at" = null
    where "better_supabase"."import_chunks"."status" <> 'done';
  return found;
end;
$$;
revoke execute on function "better_supabase"."store_import_chunk"(uuid, text, integer, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."store_import_chunk"(uuid, text, integer, jsonb) to service_role;

-- Takes a pending chunk, or one whose claim is older than lease seconds (a worker
-- that died), and returns { entity, chunk, items }. Null when the chunk is done,
-- missing or held by a live worker. Rows another worker holds are skipped, not waited for.
create or replace function "better_supabase"."claim_import_chunk"(run uuid, entity text, chunk integer, lease integer default 300)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_items jsonb;
begin
  with pick as (
    select x."run_id", x."entity", x."chunk"
    from "better_supabase"."import_chunks" x
    where x."run_id" = claim_import_chunk.run and x."entity" = claim_import_chunk.entity and x."chunk" = claim_import_chunk.chunk
      and (x."status" = 'pending' or (x."status" = 'claimed' and x."claimed_at" < now() - make_interval(secs => greatest(claim_import_chunk.lease, 1))))
    for update skip locked
  )
  update "better_supabase"."import_chunks" x set "status" = 'claimed', "claimed_at" = now()
  from pick
  where x."run_id" = pick."run_id" and x."entity" = pick."entity" and x."chunk" = pick."chunk"
  returning x."items" into v_items;
  if v_items is null then
    return null;
  end if;
  return jsonb_build_object('entity', claim_import_chunk.entity, 'chunk', claim_import_chunk.chunk, 'items', v_items);
end;
$$;
revoke execute on function "better_supabase"."claim_import_chunk"(uuid, text, integer, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."claim_import_chunk"(uuid, text, integer, integer) to service_role;

-- Marks a claimed chunk done and keeps what its batch answered.
create or replace function "better_supabase"."complete_import_chunk"(run uuid, entity text, chunk integer, result jsonb)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
begin
  update "better_supabase"."import_chunks" x set "status" = 'done', "done_at" = now(), "result" = complete_import_chunk.result
  where x."run_id" = complete_import_chunk.run and x."entity" = complete_import_chunk.entity
    and x."chunk" = complete_import_chunk.chunk and x."status" = 'claimed';
  return found;
end;
$$;
revoke execute on function "better_supabase"."complete_import_chunk"(uuid, text, integer, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_import_chunk"(uuid, text, integer, jsonb) to service_role;

-- One worker step: claim the chunk, write it with import_upsert_batch and mark it
-- done, in one transaction, so a failure leaves the chunk pending for the next try.
-- A chunk that is done answers what its batch answered; one that is missing or
-- held by another worker answers { skipped: true }.
create or replace function "better_supabase"."process_import_chunk"(run uuid, entity text, chunk integer)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_done jsonb;
  v_claim jsonb;
  v_result jsonb;
begin
  select x."result" into v_done from "better_supabase"."import_chunks" x
  where x."run_id" = process_import_chunk.run and x."entity" = process_import_chunk.entity
    and x."chunk" = process_import_chunk.chunk and x."status" = 'done';
  if found then
    return coalesce(v_done, '{}'::jsonb) || jsonb_build_object('done', true);
  end if;
  v_claim := "better_supabase"."claim_import_chunk"(process_import_chunk.run, process_import_chunk.entity, process_import_chunk.chunk);
  if v_claim is null then
    return jsonb_build_object('skipped', true);
  end if;
  v_result := "better_supabase"."import_upsert_batch"(process_import_chunk.run, process_import_chunk.entity, v_claim -> 'items');
  perform "better_supabase"."complete_import_chunk"(process_import_chunk.run, process_import_chunk.entity, process_import_chunk.chunk, v_result);
  return v_result;
end;
$$;
revoke execute on function "better_supabase"."process_import_chunk"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."process_import_chunk"(uuid, text, integer) to service_role;

-- How many chunks of a run are pending, claimed and done, so a caller knows when to
-- finish the run.
create or replace function "better_supabase"."import_chunk_progress"(run uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'pending', count(*) filter (where x."status" = 'pending'),
    'claimed', count(*) filter (where x."status" = 'claimed'),
    'done', count(*) filter (where x."status" = 'done')
  )
  from "better_supabase"."import_chunks" x
  where x."run_id" = import_chunk_progress.run
$$;
revoke execute on function "better_supabase"."import_chunk_progress"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."import_chunk_progress"(uuid) to service_role;

-- Clears the content hash of the records of a source (and entity) that a run of
-- another mapper version last wrote, so the next import treats them as changed and
-- rewrites them through their target (a row a user changed since stays as it is, as
-- for any changed hash). Returns how many records it cleared.
create or replace function "better_supabase"."reapply_import_records"(tenant uuid, source text, mapper_version text, entity text default null)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_count integer;
begin
  update "better_supabase"."import_records" x set "content_hash" = ''
  where x."tenant_id" = reapply_import_records.tenant and x."source" = reapply_import_records.source
    and (reapply_import_records.entity is null or x."entity" = reapply_import_records.entity)
    and x."content_hash" <> ''
    and (select r."mapper_version" from "better_supabase"."import_runs" r where r."id" = x."last_run_id") is distinct from reapply_import_records.mapper_version;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."reapply_import_records"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."reapply_import_records"(uuid, text, text, text) to service_role;

-- The record map of a source as { entity, scope, key, role, hash, subjectType,
-- subjectId }, one object per record in key order, so a caller can compare what the
-- source sends with what was imported without reading the rows.
create or replace function "better_supabase"."export_import_hashes"(tenant uuid, source text, entity text default null)
returns setof jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('entity', x."entity", 'scope', x."scope", 'key', x."external_key", 'role', x."role",
    'hash', x."content_hash", 'subjectType', x."subject_type", 'subjectId', x."subject_id")
  from "better_supabase"."import_records" x
  where x."tenant_id" = export_import_hashes.tenant and x."source" = export_import_hashes.source
    and (export_import_hashes.entity is null or x."entity" = export_import_hashes.entity)
  order by x."entity", x."scope", x."external_key", x."role"
$$;
revoke execute on function "better_supabase"."export_import_hashes"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."export_import_hashes"(uuid, text, text) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."import_runs" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."import_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."import_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."import_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."import_records" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."import_records" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."import_records" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."import_records" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_064_imports.sql
-- better-supabase module: imports
-- @bsb-block-data imports
-- @bsb-hash sha256:03c82178dd5c9af38535aa92f90002ada8c21fab4dadb8d91c33605f8bdcec29
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('imports', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_064_imports.sql
-- better-supabase module: imports
-- @bsb-block imports@2 managed
-- @bsb-hash sha256:8ea4fe88db8763aba41d26c79502fe031ae5ae6b10f43e0b646c2126c19ea8c5
-- Import runs and the external record map. import_upsert_batch writes items through the targets blocks and the app register, skips equal content, reports rows a user changed since the last import and marks missing keys on full runs. The dry run, parsing and mapping live in TypeScript.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."import_runs" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "source" text not null,
  "status" text not null default 'pending',
  "mapping" jsonb not null default '{}'::jsonb,
  "counts" jsonb not null default '{}'::jsonb,
  "errors" jsonb not null default '[]'::jsonb,
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."import_runs" add column "dry_run" boolean not null default false;
alter table "better_supabase"."import_runs" add column "diff" jsonb not null default '[]'::jsonb;
alter table "better_supabase"."import_runs" add column "full" boolean not null default false;
alter table "better_supabase"."import_runs" add column "input_checksum" text;
alter table "better_supabase"."import_runs" add column "correlation_id" text;
alter table "better_supabase"."import_runs" add column "mapper_version" text;
alter table "better_supabase"."import_runs" add column "scope_aliases" jsonb not null default '[]'::jsonb;
alter table "better_supabase"."import_runs" add column "started_at" timestamptz;
alter table "better_supabase"."import_runs" add column "finished_at" timestamptz;
alter table "better_supabase"."import_runs" add column "plan" jsonb;
alter table "better_supabase"."import_runs" add column "outcome" text;
alter table "better_supabase"."import_runs" add column "lease_until" timestamptz;
alter table "better_supabase"."import_runs" add column "heartbeat_at" timestamptz;
alter table "better_supabase"."import_runs" add constraint "bsb_import_runs_status"
  check ("status" in ('pending', 'running', 'completed', 'failed', 'canceled'));
alter table "better_supabase"."import_runs" enable row level security;
revoke all on "better_supabase"."import_runs" from public, anon, authenticated;
grant select on "better_supabase"."import_runs" to authenticated;
grant all on "better_supabase"."import_runs" to service_role;
create index "import_runs_tenant_idx" on "better_supabase"."import_runs" ("org_id");
-- One pending or running run per organization and source.
create unique index "import_runs_active_idx" on "better_supabase"."import_runs" ("org_id", "source") where "status" in ('pending', 'running');

create table "better_supabase"."import_records" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "source" text not null,
  "scope" text not null default '',
  "entity" text not null,
  "external_key" text not null,
  "role" text not null default 'primary',
  "subject_type" text not null,
  "subject_id" text not null,
  "content_hash" text not null,
  "first_run_id" uuid not null,
  "last_run_id" uuid not null,
  "subject_imported_updated_at" timestamptz,
  "source_updated_at" timestamptz,
  "owned_hash" text,
  "went_missing_at" timestamptz,
  constraint "import_records_key" unique ("org_id", "source", "scope", "entity", "external_key", "role")
);
create index "import_records_subject_idx" on "better_supabase"."import_records" ("org_id", "subject_type", "subject_id");
alter table "better_supabase"."import_records" enable row level security;
revoke all on "better_supabase"."import_records" from public, anon, authenticated;
grant select on "better_supabase"."import_records" to authenticated;
grant all on "better_supabase"."import_records" to service_role;
create table "better_supabase".import_refs (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "kind" text not null,
  "key" text not null,
  "payload" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now(),
  constraint import_refs_key unique ("org_id", "kind", "key")
);

create table "better_supabase"."import_chunks" (
  "run_id" uuid not null references "better_supabase"."import_runs" ("id") on delete cascade,
  "org_id" uuid not null,
  "entity" text not null,
  "chunk" integer not null,
  "items" jsonb not null,
  "status" text not null default 'pending',
  "result" jsonb,
  "claimed_at" timestamptz,
  "done_at" timestamptz,
  "created_at" timestamptz not null default now(),
  primary key ("run_id", "entity", "chunk")
);
alter table "better_supabase"."import_chunks" add constraint "bsb_import_chunks_status"
  check ("status" in ('pending', 'claimed', 'done'));
alter table "better_supabase"."import_chunks" enable row level security;
revoke all on "better_supabase"."import_chunks" from public, anon, authenticated;
grant all on "better_supabase"."import_chunks" to service_role;
create index "import_chunks_tenant_idx" on "better_supabase"."import_chunks" ("org_id");


create table "better_supabase".import_run_issues (
  "id" uuid primary key default gen_random_uuid(),
  "run_id" uuid not null,
  "org_id" uuid not null,
  "source" text not null,
  "entity" text not null,
  "key" text not null,
  "kind" text not null,
  "code" text not null,
  "message" text not null,
  "created_at" timestamptz not null default now(),
  "resolved_at" timestamptz,
  constraint bsb_import_run_issues_kind check ("kind" in ('conflict', 'error', 'warning'))
);
create index import_run_issues_open_idx
  on "better_supabase".import_run_issues ("org_id", "source", "entity", "key")
  where "resolved_at" is null;
create index import_run_issues_run_idx
  on "better_supabase".import_run_issues ("run_id", "entity");

create or replace function "better_supabase"."start_import_run"(tenant uuid, source text, options jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_options jsonb := coalesce(start_import_run.options, '{}'::jsonb);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', start_import_run.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if start_import_run.source is null or start_import_run.source = '' then
    raise exception 'an import run needs a source' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(coalesce(v_options -> 'scopeAliases', '[]'::jsonb)) <> 'array' then
    raise exception 'scopeAliases must be an array of { scope, of, entities }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    insert into "better_supabase"."import_runs" as r ("org_id", "source", "mapping", "dry_run", "full", "input_checksum", "correlation_id", "mapper_version", "scope_aliases", "plan", "lease_until", "created_by")
    values (
      start_import_run.tenant,
      start_import_run.source,
      coalesce(v_options -> 'mapping', '{}'::jsonb),
      coalesce((v_options ->> 'dryRun')::boolean, false),
      coalesce((v_options ->> 'full')::boolean, false),
      v_options ->> 'inputChecksum',
      v_options ->> 'correlationId',
      nullif(v_options ->> 'mapperVersion', ''),
      coalesce(v_options -> 'scopeAliases', '[]'::jsonb),
      v_options -> 'plan',
      now() + interval '30 seconds',
      auth.uid()
    )
    returning r."id" into v_id;
  exception when unique_violation then
    raise exception 'an import of this source is already pending or running' using errcode = '55P03', hint = 'IMPORT_RUN_ACTIVE';
  end;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."start_import_run"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."start_import_run"(uuid, text, jsonb) to authenticated, service_role;

-- The first release's entry point: a run without options.
create or replace function "better_supabase"."start_import"(tenant uuid, source text, mapping jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select "better_supabase"."start_import_run"(start_import.tenant, start_import.source, jsonb_build_object('mapping', coalesce(start_import.mapping, '{}'::jsonb)));
$$;
revoke execute on function "better_supabase"."start_import"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."start_import"(uuid, text, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_import_run"(id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = get_import_run.id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_run."org_id", 'imports.manage'), false)) then
    raise exception 'not allowed to read this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."org_id", 'source', v_run."source", 'status', v_run."status", 'outcome', v_run."outcome", 'plan', v_run."plan", 'mapping', v_run."mapping", 'counts', v_run."counts", 'errors', v_run."errors", 'dryRun', v_run."dry_run", 'full', v_run."full", 'inputChecksum', v_run."input_checksum", 'correlationId', v_run."correlation_id", 'mapperVersion', v_run."mapper_version", 'scopeAliases', v_run."scope_aliases", 'leaseUntil', v_run."lease_until", 'heartbeatAt', v_run."heartbeat_at", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'startedAt', v_run."started_at", 'finishedAt', v_run."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "better_supabase".import_run_issues i
    where i."run_id" = v_run."id"
  ));
end;
$$;
revoke execute on function "better_supabase"."get_import_run"(uuid) from public, anon;
grant execute on function "better_supabase"."get_import_run"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_import_runs"(tenant uuid, source text default null, status text default null, row_limit integer default 50)
returns setof jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_import_runs.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list imports' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  return query
    select jsonb_build_object('id', r."id", 'organizationId', r."org_id", 'source', r."source", 'status', r."status", 'outcome', r."outcome", 'plan', r."plan", 'mapping', r."mapping", 'counts', r."counts", 'errors', r."errors", 'dryRun', r."dry_run", 'full', r."full", 'inputChecksum', r."input_checksum", 'correlationId', r."correlation_id", 'mapperVersion', r."mapper_version", 'scopeAliases', r."scope_aliases", 'leaseUntil', r."lease_until", 'heartbeatAt', r."heartbeat_at", 'createdBy', r."created_by", 'createdAt', r."created_at", 'startedAt', r."started_at", 'finishedAt', r."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "better_supabase".import_run_issues i
    where i."run_id" = r."id"
  ))
    from "better_supabase"."import_runs" r
    where r."org_id" = list_import_runs.tenant
      and (list_import_runs.source is null or r."source" = list_import_runs.source)
      and (list_import_runs.status is null or r."status" = list_import_runs.status)
    order by r."created_at" desc, r."id" desc
    limit least(greatest(coalesce(list_import_runs.row_limit, 50), 1), 200);
end;
$$;
revoke execute on function "better_supabase"."list_import_runs"(uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_import_runs"(uuid, text, text, integer) to authenticated, service_role;

create or replace function "better_supabase"."cancel_import_run"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_run "better_supabase"."import_runs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_run from "better_supabase"."import_runs" r where r."id" = cancel_import_run.id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_run."org_id", 'imports.manage'), false)) then
    raise exception 'not allowed to cancel this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if v_run."status" not in ('pending', 'running') then
    raise exception 'this import already finished' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  update "better_supabase"."import_runs" r set "status" = 'canceled', "finished_at" = now()
  where r."id" = cancel_import_run.id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_import_run"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_import_run"(uuid) to authenticated, service_role;

-- The run moves from pending to running before the first batch, so a run
-- that dies mid-way is visible as running rather than pending.
create or replace function "better_supabase"."mark_import_running"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  update "better_supabase"."import_runs" set "status" = 'running', "started_at" = now()
  where "id" = mark_import_running.id and "status" = 'pending';
  if not found then
    raise exception 'no pending import with this id' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."mark_import_running"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_import_running"(uuid) to service_role;

-- Closes a run whose rows the caller wrote itself (`defineImport` without a
-- target); `finish_import_run` closes a run that used `import_upsert_batch`.
create or replace function "better_supabase"."finish_import"(id uuid, status text, count integer, error text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_source text;
begin
  update "better_supabase"."import_runs" set "status" = finish_import.status,
    "finished_at" = now(),
    "counts" = case when finish_import.status = 'completed' then jsonb_build_object("source", jsonb_build_object('inserted', finish_import.count, 'updated', 0, 'unchanged', 0, 'conflicted', 0, 'missing', 0)) else "counts" end,
    "errors" = case when finish_import.error is null then "errors" else "errors" || jsonb_build_array(jsonb_build_object('entity', "source", 'key', null, 'code', 'IMPORT_ITEM_INVALID', 'message', finish_import.error)) end
  where "id" = finish_import.id
  returning "org_id", "source" into v_tenant, v_source;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if finish_import.status = 'failed' then
    null;
  else
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."finish_import"(uuid, text, integer, text) from public, anon, authenticated;
grant execute on function "better_supabase"."finish_import"(uuid, text, integer, text) to service_role;

create or replace function "better_supabase"."import_note_issue"(run uuid, entity text, key text, kind text, code text, message text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_source text;
begin
  select r."org_id", r."source" into v_tenant, v_source
  from "better_supabase"."import_runs" r where r."id" = import_note_issue.run;
  if v_tenant is null or import_note_issue.key is null or import_note_issue.key = '' then
    return;
  end if;
  insert into "better_supabase".import_run_issues ("run_id", "org_id", "source", "entity", "key", "kind", "code", "message")
  values (import_note_issue.run, v_tenant, v_source, import_note_issue.entity, import_note_issue.key, import_note_issue.kind, import_note_issue.code, import_note_issue.message);
end;
$$;

create or replace function "better_supabase"."import_note_warnings"(run uuid, entity text, warnings jsonb)
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
    perform "better_supabase"."import_note_issue"(
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

create or replace function "better_supabase"."import_clear_issues"(run uuid, entity text, key text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_source text;
begin
  select r."org_id", r."source" into v_tenant, v_source
  from "better_supabase"."import_runs" r where r."id" = import_clear_issues.run;
  if v_tenant is null then
    return;
  end if;
  update "better_supabase".import_run_issues i set "resolved_at" = now()
  where i."org_id" = v_tenant and i."source" = v_source
    and i."entity" = import_clear_issues.entity and i."key" = import_clear_issues.key
    and i."resolved_at" is null;
end;
$$;

create or replace function "better_supabase"."list_import_issues"(run uuid, entity text default null, row_limit integer default 50, row_offset integer default 0)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_total integer;
  v_rows jsonb;
begin
  select r."org_id" into v_tenant from "better_supabase"."import_runs" r where r."id" = list_import_issues.run;
  if v_tenant is null then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list import issues' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  select count(*) into v_total from "better_supabase".import_run_issues i
  where i."run_id" = list_import_issues.run
    and (list_import_issues.entity is null or i."entity" = list_import_issues.entity);
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_rows from (
    select i."entity", i."key", i."kind", i."code", i."message", i."created_at", i."resolved_at"
    from "better_supabase".import_run_issues i
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
revoke execute on function "better_supabase"."list_import_issues"(uuid, text, integer, integer) from public, anon;
grant execute on function "better_supabase"."list_import_issues"(uuid, text, integer, integer) to authenticated, service_role;

-- Counts and the first changed fields of a dry run. The dry run itself writes
-- no subject rows; the diff is what the batch returned.
create or replace function "better_supabase"."list_import_diff"(run uuid, entity text default null, row_limit integer default 50, row_offset integer default 0)
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
  select r."counts", r."diff" into v_counts, v_diff from "better_supabase"."import_runs" r where r."id" = list_import_diff.run;
  if v_counts is null then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
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
revoke execute on function "better_supabase"."list_import_diff"(uuid, text, integer, integer) from public, anon;
grant execute on function "better_supabase"."list_import_diff"(uuid, text, integer, integer) to authenticated, service_role;

create or replace function "better_supabase"."resolve_import_conflict"(tenant uuid, source text, entity text, key text, action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resolved integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', resolve_import_conflict.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to resolve an import conflict' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if resolve_import_conflict.action = 'keep' then
    update "better_supabase"."import_records" x set "subject_imported_updated_at" = now()
    where x."org_id" = resolve_import_conflict.tenant
      and x."source" = resolve_import_conflict.source
      and x."entity" = resolve_import_conflict.entity
      and x."external_key" = resolve_import_conflict.key;
  elsif resolve_import_conflict.action = 'overwrite' then
    update "better_supabase"."import_records" x set "subject_imported_updated_at" = null, "owned_hash" = null
    where x."org_id" = resolve_import_conflict.tenant
      and x."source" = resolve_import_conflict.source
      and x."entity" = resolve_import_conflict.entity
      and x."external_key" = resolve_import_conflict.key;
  else
    raise exception 'action must be keep or overwrite' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  update "better_supabase".import_run_issues i set "resolved_at" = now()
  where i."org_id" = resolve_import_conflict.tenant
    and i."source" = resolve_import_conflict.source
    and i."entity" = resolve_import_conflict.entity
    and i."key" = resolve_import_conflict.key
    and i."kind" = 'conflict'
    and i."resolved_at" is null;
  get diagnostics v_resolved = row_count;
  return jsonb_build_object('action', resolve_import_conflict.action, 'resolved', v_resolved);
end;
$$;
revoke execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) to service_role;
revoke execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."resolve_import_conflict"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."import_integrity"(tenant uuid, source text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_checks jsonb := '[]'::jsonb;
  v_name text;
  v_severity text;
  v_count integer;
  v_ids jsonb;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', import_integrity.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to check this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  for v_name, v_severity, v_count, v_ids in
    select 'duplicate_keys', 'error', count(*)::integer, coalesce(jsonb_agg(sample), '[]'::jsonb) from (
      select min(d."id"::text) as sample from "better_supabase"."import_records" d
      where d."org_id" = import_integrity.tenant
        and (import_integrity.source is null or d."source" = import_integrity.source)
      group by d."entity", d."external_key"
      having count(distinct d."subject_id") > 1
    ) q
  loop
    v_checks := v_checks || jsonb_build_array(jsonb_build_object(
      'name', v_name, 'severity', v_severity, 'count', v_count, 'ids', coalesce(v_ids, '[]'::jsonb)));
  end loop;
  return jsonb_build_object('checks', v_checks);
end;
$$;
revoke execute on function "better_supabase"."import_integrity"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_integrity"(uuid, text) to service_role;
revoke execute on function "better_supabase"."import_integrity"(uuid, text) from public, anon;
grant execute on function "better_supabase"."import_integrity"(uuid, text) to authenticated, service_role;

create table "better_supabase".import_sources (
  "id" text primary key,
  "label_key" text not null,
  "description_key" text not null,
  "file_types" text[] not null default '{}',
  "entities" text[] not null default '{}',
  "docs_link" text
);

create or replace function "better_supabase"."register_import_source"(id text, label_key text, description_key text, file_types text[], entities text[], docs_link text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'not allowed to register an import source' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  insert into "better_supabase".import_sources ("id", "label_key", "description_key", "file_types", "entities", "docs_link")
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
revoke execute on function "better_supabase"."register_import_source"(text, text, text, text[], text[], text) from public, anon, authenticated;
grant execute on function "better_supabase"."register_import_source"(text, text, text, text[], text[], text) to service_role;

create or replace function "better_supabase"."list_import_sources"()
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
  from "better_supabase".import_sources s
$$;
revoke execute on function "better_supabase"."list_import_sources"() from public, anon;
grant execute on function "better_supabase"."list_import_sources"() to authenticated, service_role;

-- Every run of the tenant, whoever started it: the CLI, an API or the UI.
create or replace function "better_supabase"."list_import_source_runs"(tenant uuid, source text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r."id", 'source', r."source", 'status', r."status", 'createdAt', r."created_at"
  ) order by r."created_at" desc), '[]'::jsonb)
  from "better_supabase"."import_runs" r
  where r."org_id" = list_import_source_runs.tenant
    and (list_import_source_runs.source is null or r."source" = list_import_source_runs.source)
$$;
revoke execute on function "better_supabase"."list_import_source_runs"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_import_source_runs"(uuid, text) to authenticated, service_role;


-- Writes the items of one entity: an unknown key inserts, an equal hash is
-- unchanged and writes nothing, a changed hash updates unless the row changed
-- after the last import (conflicted). Returns the counts and the item errors.
create or replace function "better_supabase"."import_apply_batch"(run uuid, entity text, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := import_apply_batch.run;
  v_entity text := import_apply_batch.entity;
  v_items jsonb := import_apply_batch.items;
  v_run "better_supabase"."import_runs";
  v_item jsonb;
  v_call jsonb;
  v_key text;
  v_scope text;
  v_data jsonb;
  v_hash text;
  v_source_at timestamptz;
  v_diff jsonb := '[]'::jsonb;
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_owned text;
  v_natural text;
  v_ref_map jsonb := '{}'::jsonb;
  v_resolved jsonb := '{}'::jsonb;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_issue text;
  v_message text;
  v_hint text;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if v_entity <> all (array[]::text[]) then
    raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    raise exception 'items must be an array of { key, scope, data, refs }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  v_ref_map := '{}'::jsonb;

  for v_item in
    select e.value from jsonb_array_elements(v_items) e
    order by e.value #>> '{data,orderBy}', e.value #>> '{data,readAt}', e.value ->> 'key'
  loop
    v_issue := null;
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      perform "better_supabase"."import_note_issue"(v_run_id, v_entity, coalesce(v_key, ''), 'error', 'IMPORT_ITEM_INVALID', 'an item needs a key and a data object');
      continue;
    end if;

    

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."org_id" = v_run."org_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;
      v_source_at := nullif(v_item ->> 'sourceUpdatedAt', '')::timestamptz;
      if v_found and v_source_at is not null and v_rec."source_updated_at" is not null and v_source_at <= v_rec."source_updated_at" then
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');
      end if;

      if v_done then
        null;
      elsif not v_found then
        v_natural := null;
        null;
        if v_natural is not null then
          v_found := true;
          v_rec."subject_id" := v_natural;
          v_rec."content_hash" := '';
        end if;
      end if;

      if v_done then
        null;
      elsif not v_found then
        -- A cloned administration reuses the subjects of the scope it aliases
        -- when the content is equal there.
        for v_other in
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = v_scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? v_entity)
        loop
          if exists (
            select 1 from "better_supabase"."import_records" x
            where x."org_id" = v_run."org_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary' and x."content_hash" = v_hash
          ) then
            insert into "better_supabase"."import_records" ("org_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at")
            select x."org_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_imported_updated_at"
            from "better_supabase"."import_records" x
            where x."org_id" = v_run."org_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key
            on conflict ("org_id", "source", "scope", "entity", "external_key", "role") do nothing;
            v_unchanged := v_unchanged + 1;
            v_done := true;
            exit;
          end if;
        end loop;
      elsif v_rec."content_hash" = v_hash then
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
        where x."org_id" = v_rec."org_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."went_missing_at" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        v_owned := null;
        null;
        null;
        if v_owned is not null and v_rec."owned_hash" is not null and v_owned is distinct from v_rec."owned_hash" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_issue := 'conflict';
          v_done := true;
        elsif v_owned is not null and v_current is not null and v_rec."subject_imported_updated_at" is not null and v_current > v_rec."subject_imported_updated_at" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "subject_imported_updated_at" = v_current, "owned_hash" = v_owned
          where x."id" = v_rec."id";
        elsif v_owned is null and v_current is not null and v_rec."subject_imported_updated_at" is not null and v_current > v_rec."subject_imported_updated_at" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_issue := 'conflict';
          v_done := true;
        end if;
      end if;

      if v_issue = 'conflict' then
        perform "better_supabase"."import_note_issue"(v_run_id, v_entity, v_key, 'conflict', 'IMPORT_CONFLICT', 'the subject changed after the last import');
      else
        perform "better_supabase"."import_clear_issues"(v_run_id, v_entity, v_key);
      end if;

      if not v_done and v_run."dry_run" and jsonb_typeof(v_item -> 'previous') = 'object' and jsonb_array_length(v_diff) < 20 then
        v_diff := v_diff || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'fields', (
          select coalesce(jsonb_agg(jsonb_build_object('field', k, 'old', v_item -> 'previous' -> k, 'new', v_data -> k)), '[]'::jsonb)
          from jsonb_object_keys(v_data) k where (v_data -> k) is distinct from (v_item -> 'previous' -> k))));
      end if;
      if not v_done then
        v_subject_id := case when v_found then v_rec."subject_id" else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run."org_id", 'scope', v_scope);
        
        raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';

          v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
  if not exists (
    select 1 from jsonb_array_elements(v_subjects) s
    where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
  ) then
    raise exception 'the import target returned no primary subject' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
    if jsonb_typeof(v_subject -> 'warnings') = 'array' then
      v_warnings := v_warnings || (select coalesce(jsonb_agg(w.value || jsonb_build_object('entity', v_entity, 'key', v_key)), '[]'::jsonb) from jsonb_array_elements(v_subject -> 'warnings') w);
    end if;
    insert into "better_supabase"."import_records" ("org_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at", "source_updated_at", "went_missing_at")
    values (
      v_run."org_id", v_run."source", v_scope, v_entity, v_key,
      coalesce(v_subject ->> 'role', 'primary'),
      coalesce(v_subject ->> 'subjectType', v_subject_type),
      v_subject ->> 'subjectId',
      v_hash, v_run_id, v_run_id,
      coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
      v_source_at,
      null
    )
    on conflict ("org_id", "source", "scope", "entity", "external_key", "role") do update set
      "subject_type" = excluded."subject_type",
      "subject_id" = excluded."subject_id",
      "content_hash" = excluded."content_hash",
      "last_run_id" = excluded."last_run_id",
      "subject_imported_updated_at" = excluded."subject_imported_updated_at",
      "source_updated_at" = coalesce(excluded."source_updated_at", "better_supabase"."import_records"."source_updated_at"),
      "went_missing_at" = null;
  end loop;

  if v_found then
    v_updated := v_updated + 1;
  else
    v_inserted := v_inserted + 1;
  end if;
  
      end if;
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
      perform "better_supabase"."import_note_issue"(v_run_id, v_entity, coalesce(v_key, ''), 'error', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), v_message);
    end;
  end loop;

  

  perform "better_supabase"."import_note_warnings"(v_run_id, v_entity, v_warnings);

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors, 'diff', v_diff) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
end;
$$;
revoke execute on function "better_supabase"."import_apply_batch"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_apply_batch"(uuid, text, jsonb) to service_role;

-- Turns import mode on for the rest of the transaction (ADR 0141): the outbox
-- applies the imports.events policy, the audit log tags entries as
-- integration with the correlation id import:<run> (imports.audit decides rows
-- or one summary per entity) and ctx.importing() guards skip their side
-- effects. The setting is transaction-local and better_supabase.import_run()
-- only reports it to the service role, so no user session can turn it on.
create or replace function "better_supabase"."begin_import_session"(run uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_status text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role can begin an import session' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  select r."status"::text into v_status from "better_supabase"."import_runs" r where r."id" = begin_import_session.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_status <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  perform set_config('better_supabase.import_run', begin_import_session.run::text, true);
  perform set_config('better_supabase.correlation_id', 'import:' || begin_import_session.run::text, true);
  perform set_config('better_supabase.import_events', '{}', true);
  perform set_config('better_supabase.import_audit', 'rows', true);
  return begin_import_session.run;
end;
$$;
revoke execute on function "better_supabase"."begin_import_session"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."begin_import_session"(uuid) to service_role;

-- The single write path of an import (service role). It begins the import
-- session for its writes and restores the caller's settings afterwards. A dry
-- run writes inside a subtransaction it rolls back, then keeps the counts.
create or replace function "better_supabase"."import_upsert_batch"(run uuid, entity text, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := import_upsert_batch.run;
  v_entity text := import_upsert_batch.entity;
  v_run "better_supabase"."import_runs";
  v_result jsonb;
  v_name text;
  v_previous jsonb := '{}'::jsonb;
begin
  -- No row lock here: two batches of one run write at the same time, and the
  -- counts update at the end is the only statement that locks the run row.
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  if coalesce((v_run."plan" ->> 'unordered')::boolean, false) is distinct from true
    and jsonb_typeof(v_run."plan" -> 'waves') = 'array'
    and exists (
      select 1 from jsonb_array_elements(v_run."plan" -> 'waves') with ordinality as w(wave, n)
      where w.wave ? v_entity and exists (
        select 1 from jsonb_array_elements(v_run."plan" -> 'waves') with ordinality as earlier(wave, n)
        cross join lateral jsonb_array_elements_text(earlier.wave) dep(entity)
        join "better_supabase"."import_chunks" c on c."run_id" = v_run_id
          and c."entity" = dep.entity and c."status" <> 'done'
        where earlier.n < w.n)) then
    raise exception 'an earlier import wave still has open chunks' using errcode = '55000', hint = 'IMPORT_DEPENDENCY_OPEN';
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    v_previous := v_previous || jsonb_build_object(v_name, coalesce(current_setting(v_name, true), ''));
  end loop;
  perform "better_supabase"."begin_import_session"(v_run_id);

  if v_run."dry_run" then
    begin
      v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
      raise exception 'dry run' using errcode = 'BSDRY';
    exception when sqlstate 'BSDRY' then
      null;
    end;
  else
    v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    perform set_config(v_name, v_previous ->> v_name, true);
  end loop;

  update "better_supabase"."import_runs" r set
    "counts" = jsonb_set(r."counts", array[v_entity], jsonb_build_object(
      'inserted', coalesce(r."counts" -> v_entity ->> 'inserted', '0')::integer + coalesce((v_result ->> 'inserted')::integer, 0),
      'updated', coalesce(r."counts" -> v_entity ->> 'updated', '0')::integer + coalesce((v_result ->> 'updated')::integer, 0),
      'unchanged', coalesce(r."counts" -> v_entity ->> 'unchanged', '0')::integer + coalesce((v_result ->> 'unchanged')::integer, 0),
      'conflicted', coalesce(r."counts" -> v_entity ->> 'conflicted', '0')::integer + coalesce((v_result ->> 'conflicted')::integer, 0),
      'missing', coalesce((r."counts" -> v_entity ->> 'missing')::integer, 0)
    )),
    "errors" = r."errors" || coalesce(v_result -> 'errors', '[]'::jsonb),
    "diff" = (select coalesce(jsonb_agg(d.value), '[]'::jsonb) from (
      select value from jsonb_array_elements(r."diff" || coalesce(v_result -> 'diff', '[]'::jsonb)) value limit 100
    ) d)
  where r."id" = v_run_id;
  return v_result || jsonb_build_object('dryRun', v_run."dry_run");
end;
$$;
revoke execute on function "better_supabase"."import_upsert_batch"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_upsert_batch"(uuid, text, jsonb) to service_role;

-- Bulk external key to subject. keys is an array of text, or of { key, scope,
-- role }; a scope that aliases another resolves through it.
create or replace function "better_supabase"."import_resolve"(run uuid, entity text, keys jsonb)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = import_resolve.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if jsonb_typeof(import_resolve.keys) <> 'array' then
    raise exception 'keys must be an array' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('key', q.key, 'scope', q.scope, 'role', q.role, 'subjectType', m."subject_type", 'subjectId', m."subject_id") order by q.ord)
    from (
      select k.ord,
        case when jsonb_typeof(k.value) = 'string' then k.value #>> '{}' else k.value ->> 'key' end as key,
        case when jsonb_typeof(k.value) = 'string' then '' else coalesce(k.value ->> 'scope', '') end as scope,
        case when jsonb_typeof(k.value) = 'string' then 'primary' else coalesce(k.value ->> 'role', 'primary') end as role
      from jsonb_array_elements(import_resolve.keys) with ordinality k(value, ord)
    ) q
    join lateral (
      select x."subject_type", x."subject_id"
      from "better_supabase"."import_records" x
      where x."org_id" = v_run."org_id" and x."source" = v_run."source"
        and x."entity" = import_resolve.entity and x."external_key" = q.key and x."role" = q.role
        and (x."scope" = q.scope or x."scope" in (
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = q.scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? import_resolve.entity)
        ))
      order by (x."scope" = q.scope) desc
      limit 1
    ) m on true
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."import_resolve"(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_resolve"(uuid, text, jsonb) to service_role;

-- Closes a run that wrote through import_upsert_batch. A full run marks the
-- records of its entities it didn't see, and never deletes them.
create or replace function "better_supabase"."finish_import_run"(run uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := finish_import_run.run;
  v_run "better_supabase"."import_runs";
  v_entity text;
  v_missing integer;
  v_total integer := 0;
  v_counts jsonb;
  v_outcome text := 'completed';
  v_expected integer;
  v_applied integer;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  v_counts := v_run."counts";

  if v_run."full" then
    for v_entity in select k.key from jsonb_object_keys(v_run."counts") k(key) loop
      select count(*)::integer into v_missing from "better_supabase"."import_records" x
      where x."org_id" = v_run."org_id" and x."source" = v_run."source" and x."entity" = v_entity
        and x."role" = 'primary' and x."last_run_id" <> v_run_id
        and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."org_id" = v_run."org_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      if not v_run."dry_run" then
        update "better_supabase"."import_records" x set "went_missing_at" = coalesce(x."went_missing_at", now())
        where x."org_id" = v_run."org_id" and x."source" = v_run."source" and x."entity" = v_entity
          and x."last_run_id" <> v_run_id
          and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."org_id" = v_run."org_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  if v_run."plan" is not null and jsonb_typeof(v_run."plan") = 'object' then
    for v_entity in select k.key from jsonb_object_keys(v_run."plan") k(key) loop
      v_expected := coalesce((v_run."plan" ->> v_entity)::integer, 0);
      v_applied := coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'unchanged')::integer, 0);
      if v_applied < v_expected then
        v_outcome := 'incomplete';
        v_counts := jsonb_set(coalesce(v_counts, '{}'::jsonb), array[v_entity, 'missing'], to_jsonb(v_expected - v_applied), true);
      end if;
    end loop;
  end if;
  if v_outcome = 'completed' and (jsonb_array_length(coalesce(v_run."errors", '[]'::jsonb)) > 0 or v_counts::text like '%"conflicted":%') then
    v_outcome := 'completed_with_issues';
  end if;

  update "better_supabase"."import_runs" r set "status" = 'completed', "outcome" = v_outcome, "finished_at" = now(), "counts" = v_counts
  where r."id" = v_run_id;

  if not v_run."dry_run" then
    for v_entity in select k.key from jsonb_object_keys(v_counts) k(key) loop
      v_total := v_total + coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0);
      null;
    end loop;
    null;
  end if;
  return v_counts;
end;
$$;
revoke execute on function "better_supabase"."finish_import_run"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."finish_import_run"(uuid) to service_role;

create or replace function "better_supabase"."heartbeat_import_run"(run uuid, seconds integer default 30)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_until timestamptz;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can heartbeat an import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  update "better_supabase"."import_runs" r set "heartbeat_at" = now(), "lease_until" = now() + make_interval(secs => greatest(heartbeat_import_run.seconds, 1))
  where r."id" = heartbeat_import_run.run and r."status" = 'running'
  returning r."lease_until" into v_until;
  if v_until is null then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  return v_until;
end;
$$;
revoke execute on function "better_supabase"."heartbeat_import_run"(uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."heartbeat_import_run"(uuid, integer) to service_role;

create or replace function "better_supabase"."import_ensure_ref"(tenant uuid, kind text, key text, defaults jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_created boolean := false;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can ensure an import ref' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if import_ensure_ref.kind is null or import_ensure_ref.key is null or import_ensure_ref.key = '' then
    raise exception 'a ref needs a kind and a key' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select r."id" into v_id from "better_supabase".import_refs r
  where r."org_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
  if v_id is null then
    insert into "better_supabase".import_refs ("org_id", "kind", "key", "payload")
    values (import_ensure_ref.tenant, import_ensure_ref.kind, import_ensure_ref.key, coalesce(import_ensure_ref.defaults, '{}'::jsonb))
    on conflict ("org_id", "kind", "key") do nothing
    returning "id" into v_id;
    v_created := v_id is not null;
    if v_id is null then
      select r."id" into v_id from "better_supabase".import_refs r
      where r."org_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
    end if;
  end if;
  return jsonb_build_object(
    'id', v_id,
    'created', v_created,
    'warnings', case when v_created then jsonb_build_array(jsonb_build_object('code', 'IMPORT_REF_CREATED', 'kind', import_ensure_ref.kind, 'key', import_ensure_ref.key)) else '[]'::jsonb end
  );
end;
$$;
revoke execute on function "better_supabase"."import_ensure_ref"(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."import_ensure_ref"(uuid, text, text, jsonb) to service_role;

create or replace function "better_supabase"."import_entities"()
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$ select array[]::text[] $$;
revoke execute on function "better_supabase"."import_entities"() from public, anon, authenticated;
grant execute on function "better_supabase"."import_entities"() to service_role;


create or replace function "better_supabase"."rebase_import_records"(tenant uuid, source text, entities text[] default null, keys text[] default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can rebase import records' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  update "better_supabase"."import_records" x
  set "subject_imported_updated_at" = coalesce((null), x."subject_imported_updated_at"),
      "owned_hash" = coalesce((null), x."owned_hash")
  where x."org_id" = rebase_import_records.tenant
    and x."source" = rebase_import_records.source
    and (rebase_import_records.entities is null or x."entity" = any (rebase_import_records.entities))
    and (rebase_import_records.keys is null or x."external_key" = any (rebase_import_records.keys));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."rebase_import_records"(uuid, text, text[], text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."rebase_import_records"(uuid, text, text[], text[]) to service_role;


-- Queues one job per chunk of an entity's items, so a worker writes a large
-- import in batches; the dedupe key makes a retry harmless.
create or replace function "better_supabase"."enqueue_import_chunks"(run uuid, entity text, chunks integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
  v_chunk integer;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = enqueue_import_chunks.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if enqueue_import_chunks.chunks is null or enqueue_import_chunks.chunks < 1 then
    raise exception 'chunks must be at least 1' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  for v_chunk in 0 .. enqueue_import_chunks.chunks - 1 loop
    perform "better_supabase"."enqueue_job"(queue => 'imports', payload => jsonb_build_object('run', v_run."id", 'entity', enqueue_import_chunks.entity, 'chunk', v_chunk), dedupe_key => v_run."id"::text || ':' || enqueue_import_chunks.entity || ':' || v_chunk::text, dedupe_running => false);
  end loop;
  return enqueue_import_chunks.chunks;
end;
$$;
revoke execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) to service_role;

-- Stores the items of one chunk of an entity, ready for a worker. Storing a chunk
-- again before it is done replaces its items; a done chunk is left as it is and
-- the answer is false.
create or replace function "better_supabase"."store_import_chunk"(run uuid, entity text, chunk integer, items jsonb)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = store_import_chunk.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if store_import_chunk.chunk is null or store_import_chunk.chunk < 0 or jsonb_typeof(store_import_chunk.items) is distinct from 'array' then
    raise exception 'a chunk has a number from 0 and an array of items' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  insert into "better_supabase"."import_chunks" ("run_id", "org_id", "entity", "chunk", "items")
  values (store_import_chunk.run, v_run."org_id", store_import_chunk.entity, store_import_chunk.chunk, store_import_chunk.items)
  on conflict ("run_id", "entity", "chunk") do update
    set "items" = excluded."items", "status" = 'pending', "claimed_at" = null
    where "better_supabase"."import_chunks"."status" <> 'done';
  return found;
end;
$$;
revoke execute on function "better_supabase"."store_import_chunk"(uuid, text, integer, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."store_import_chunk"(uuid, text, integer, jsonb) to service_role;

-- Takes a pending chunk, or one whose claim is older than lease seconds (a worker
-- that died), and returns { entity, chunk, items }. Null when the chunk is done,
-- missing or held by a live worker. Rows another worker holds are skipped, not waited for.
create or replace function "better_supabase"."claim_import_chunk"(run uuid, entity text, chunk integer, lease integer default 300)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_items jsonb;
begin
  with pick as (
    select x."run_id", x."entity", x."chunk"
    from "better_supabase"."import_chunks" x
    where x."run_id" = claim_import_chunk.run and x."entity" = claim_import_chunk.entity and x."chunk" = claim_import_chunk.chunk
      and (x."status" = 'pending' or (x."status" = 'claimed' and x."claimed_at" < now() - make_interval(secs => greatest(claim_import_chunk.lease, 1))))
    for update skip locked
  )
  update "better_supabase"."import_chunks" x set "status" = 'claimed', "claimed_at" = now()
  from pick
  where x."run_id" = pick."run_id" and x."entity" = pick."entity" and x."chunk" = pick."chunk"
  returning x."items" into v_items;
  if v_items is null then
    return null;
  end if;
  return jsonb_build_object('entity', claim_import_chunk.entity, 'chunk', claim_import_chunk.chunk, 'items', v_items);
end;
$$;
revoke execute on function "better_supabase"."claim_import_chunk"(uuid, text, integer, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."claim_import_chunk"(uuid, text, integer, integer) to service_role;

-- Marks a claimed chunk done and keeps what its batch answered.
create or replace function "better_supabase"."complete_import_chunk"(run uuid, entity text, chunk integer, result jsonb)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
begin
  update "better_supabase"."import_chunks" x set "status" = 'done', "done_at" = now(), "result" = complete_import_chunk.result
  where x."run_id" = complete_import_chunk.run and x."entity" = complete_import_chunk.entity
    and x."chunk" = complete_import_chunk.chunk and x."status" = 'claimed';
  return found;
end;
$$;
revoke execute on function "better_supabase"."complete_import_chunk"(uuid, text, integer, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_import_chunk"(uuid, text, integer, jsonb) to service_role;

-- One worker step: claim the chunk, write it with import_upsert_batch and mark it
-- done, in one transaction, so a failure leaves the chunk pending for the next try.
-- A chunk that is done answers what its batch answered; one that is missing or
-- held by another worker answers { skipped: true }.
create or replace function "better_supabase"."process_import_chunk"(run uuid, entity text, chunk integer)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_done jsonb;
  v_claim jsonb;
  v_result jsonb;
begin
  select x."result" into v_done from "better_supabase"."import_chunks" x
  where x."run_id" = process_import_chunk.run and x."entity" = process_import_chunk.entity
    and x."chunk" = process_import_chunk.chunk and x."status" = 'done';
  if found then
    return coalesce(v_done, '{}'::jsonb) || jsonb_build_object('done', true);
  end if;
  v_claim := "better_supabase"."claim_import_chunk"(process_import_chunk.run, process_import_chunk.entity, process_import_chunk.chunk);
  if v_claim is null then
    return jsonb_build_object('skipped', true);
  end if;
  v_result := "better_supabase"."import_upsert_batch"(process_import_chunk.run, process_import_chunk.entity, v_claim -> 'items');
  perform "better_supabase"."complete_import_chunk"(process_import_chunk.run, process_import_chunk.entity, process_import_chunk.chunk, v_result);
  return v_result;
end;
$$;
revoke execute on function "better_supabase"."process_import_chunk"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."process_import_chunk"(uuid, text, integer) to service_role;

-- How many chunks of a run are pending, claimed and done, so a caller knows when to
-- finish the run.
create or replace function "better_supabase"."import_chunk_progress"(run uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'pending', count(*) filter (where x."status" = 'pending'),
    'claimed', count(*) filter (where x."status" = 'claimed'),
    'done', count(*) filter (where x."status" = 'done')
  )
  from "better_supabase"."import_chunks" x
  where x."run_id" = import_chunk_progress.run
$$;
revoke execute on function "better_supabase"."import_chunk_progress"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."import_chunk_progress"(uuid) to service_role;

-- Clears the content hash of the records of a source (and entity) that a run of
-- another mapper version last wrote, so the next import treats them as changed and
-- rewrites them through their target (a row a user changed since stays as it is, as
-- for any changed hash). Returns how many records it cleared.
create or replace function "better_supabase"."reapply_import_records"(tenant uuid, source text, mapper_version text, entity text default null)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_count integer;
begin
  update "better_supabase"."import_records" x set "content_hash" = ''
  where x."org_id" = reapply_import_records.tenant and x."source" = reapply_import_records.source
    and (reapply_import_records.entity is null or x."entity" = reapply_import_records.entity)
    and x."content_hash" <> ''
    and (select r."mapper_version" from "better_supabase"."import_runs" r where r."id" = x."last_run_id") is distinct from reapply_import_records.mapper_version;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."reapply_import_records"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."reapply_import_records"(uuid, text, text, text) to service_role;

-- The record map of a source as { entity, scope, key, role, hash, subjectType,
-- subjectId }, one object per record in key order, so a caller can compare what the
-- source sends with what was imported without reading the rows.
create or replace function "better_supabase"."export_import_hashes"(tenant uuid, source text, entity text default null)
returns setof jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('entity', x."entity", 'scope', x."scope", 'key', x."external_key", 'role', x."role",
    'hash', x."content_hash", 'subjectType', x."subject_type", 'subjectId', x."subject_id")
  from "better_supabase"."import_records" x
  where x."org_id" = export_import_hashes.tenant and x."source" = export_import_hashes.source
    and (export_import_hashes.entity is null or x."entity" = export_import_hashes.entity)
  order by x."entity", x."scope", x."external_key", x."role"
$$;
revoke execute on function "better_supabase"."export_import_hashes"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."export_import_hashes"(uuid, text, text) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."import_runs" as restrictive
  for select to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."import_runs" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."import_runs" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."import_runs" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."import_records" as restrictive
  for select to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."import_records" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."import_records" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."import_records" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_064_imports.sql
-- better-supabase module: imports
-- @bsb-block-data imports
-- @bsb-hash sha256:03c82178dd5c9af38535aa92f90002ada8c21fab4dadb8d91c33605f8bdcec29
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('imports', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
