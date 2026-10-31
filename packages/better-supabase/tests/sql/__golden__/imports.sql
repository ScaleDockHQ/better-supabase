-- ==== alone: schema supabase/schemas/900_better_supabase_064_imports.sql
-- better-supabase module: imports
-- @bsb-block imports@2 managed
-- @bsb-hash sha256:f75ffecb9211052857f3b0ceb8c92e2b07906719cb5754f3feaea1272bca446a
-- Import runs and the external record map. import_upsert_batch writes items through the targets blocks and the app register, skips equal content, reports rows a user changed since the last import and marks missing keys on full runs. The dry run, parsing and mapping live in TypeScript.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_runs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_records";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."import_runs" (
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
alter table "better_supabase"."import_runs" add column if not exists "dry_run" boolean not null default false;
alter table "better_supabase"."import_runs" add column if not exists "full" boolean not null default false;
alter table "better_supabase"."import_runs" add column if not exists "input_checksum" text;
alter table "better_supabase"."import_runs" add column if not exists "correlation_id" text;
alter table "better_supabase"."import_runs" add column if not exists "scope_aliases" jsonb not null default '[]'::jsonb;
alter table "better_supabase"."import_runs" add column if not exists "started_at" timestamptz;
alter table "better_supabase"."import_runs" add column if not exists "finished_at" timestamptz;
alter table "better_supabase"."import_runs" drop constraint if exists "import_runs_status_check";
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."import_runs"'::regclass and c.conname = 'bsb_import_runs_status'
  ), 'pg_constraint'), '') <> 'better-supabase check 664f0f9f' then
    alter table "better_supabase"."import_runs" drop constraint if exists "bsb_import_runs_status";
    alter table "better_supabase"."import_runs" add constraint "bsb_import_runs_status" check ("status" in ('pending', 'running', 'completed', 'failed', 'canceled'));
    comment on constraint "bsb_import_runs_status" on "better_supabase"."import_runs" is 'better-supabase check 664f0f9f';
  end if;
end;
$$;
alter table "better_supabase"."import_runs" enable row level security;
revoke all on "better_supabase"."import_runs" from public, anon, authenticated;
grant select on "better_supabase"."import_runs" to authenticated;
grant all on "better_supabase"."import_runs" to service_role;
create index if not exists "import_runs_tenant_idx" on "better_supabase"."import_runs" ("tenant_id");
-- One pending or running run per organization and source.
create unique index if not exists "import_runs_active_idx" on "better_supabase"."import_runs" ("tenant_id", "source") where "status" in ('pending', 'running');

create table if not exists "better_supabase"."import_records" (
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
  "subject_updated_at_at_import" timestamptz,
  "missing_since" timestamptz,
  constraint "import_records_key" unique ("tenant_id", "source", "scope", "entity", "external_key", "role")
);
create index if not exists "import_records_subject_idx" on "better_supabase"."import_records" ("tenant_id", "subject_type", "subject_id");
alter table "better_supabase"."import_records" enable row level security;
revoke all on "better_supabase"."import_records" from public, anon, authenticated;
grant select on "better_supabase"."import_records" to authenticated;
grant all on "better_supabase"."import_records" to service_role;

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
    insert into "better_supabase"."import_runs" as r ("tenant_id", "source", "mapping", "dry_run", "full", "input_checksum", "correlation_id", "scope_aliases", "created_by")
    values (
      start_import_run.tenant,
      start_import_run.source,
      coalesce(v_options -> 'mapping', '{}'::jsonb),
      coalesce((v_options ->> 'dryRun')::boolean, false),
      coalesce((v_options ->> 'full')::boolean, false),
      v_options ->> 'inputChecksum',
      v_options ->> 'correlationId',
      coalesce(v_options -> 'scopeAliases', '[]'::jsonb),
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
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."tenant_id", 'source', v_run."source", 'status', v_run."status", 'mapping', v_run."mapping", 'counts', v_run."counts", 'errors', v_run."errors", 'dryRun', v_run."dry_run", 'full', v_run."full", 'inputChecksum', v_run."input_checksum", 'correlationId', v_run."correlation_id", 'scopeAliases', v_run."scope_aliases", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'startedAt', v_run."started_at", 'finishedAt', v_run."finished_at");
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
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'source', r."source", 'status', r."status", 'mapping', r."mapping", 'counts', r."counts", 'errors', r."errors", 'dryRun', r."dry_run", 'full', r."full", 'inputChecksum', r."input_checksum", 'correlationId', r."correlation_id", 'scopeAliases', r."scope_aliases", 'createdBy', r."created_by", 'createdAt', r."created_at", 'startedAt', r."started_at", 'finishedAt', r."finished_at")
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
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
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

  for v_item in select e.value from jsonb_array_elements(v_items) e loop
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      continue;
    end if;

    -- jsonb text is key-ordered, so equal content hashes equally.
    v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;

      if not v_found then
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
            insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_updated_at_at_import"
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
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."missing_since" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        null;
        if v_current is not null and v_rec."subject_updated_at_at_import" is not null and v_current > v_rec."subject_updated_at_at_import" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_done := true;
        end if;
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
          insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import", "missing_since")
          values (
            v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
            coalesce(v_subject ->> 'role', 'primary'),
            coalesce(v_subject ->> 'subjectType', v_subject_type),
            v_subject ->> 'subjectId',
            v_hash, v_run_id, v_run_id,
            coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
            null
          )
          on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
            "subject_type" = excluded."subject_type",
            "subject_id" = excluded."subject_id",
            "content_hash" = excluded."content_hash",
            "last_run_id" = excluded."last_run_id",
            "subject_updated_at_at_import" = excluded."subject_updated_at_at_import",
            "missing_since" = null;
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
    end;
  end loop;

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
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
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit'] loop
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

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit'] loop
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
    "errors" = r."errors" || coalesce(v_result -> 'errors', '[]'::jsonb)
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
        update "better_supabase"."import_records" x set "missing_since" = coalesce(x."missing_since", now())
        where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
          and x."last_run_id" <> v_run_id
          and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  update "better_supabase"."import_runs" r set "status" = 'completed', "finished_at" = now(), "counts" = v_counts
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
    perform "better_supabase"."enqueue_job"(queue => '''imports''', payload => jsonb_build_object('run', v_run."id", 'entity', enqueue_import_chunks.entity, 'chunk', v_chunk), dedupe_key => v_run."id"::text || ':' || enqueue_import_chunks.entity || ':' || v_chunk::text, dedupe_running => false);
  end loop;
  return enqueue_import_chunks.chunks;
end;
$$;
revoke execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."import_runs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_runs";
create policy bsb_tenant_scope_select on "better_supabase"."import_runs" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_runs";
create policy bsb_tenant_scope_insert on "better_supabase"."import_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_runs";
create policy bsb_tenant_scope_update on "better_supabase"."import_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_runs";
create policy bsb_tenant_scope_delete on "better_supabase"."import_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."import_records";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_records";
create policy bsb_tenant_scope_select on "better_supabase"."import_records" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_records";
create policy bsb_tenant_scope_insert on "better_supabase"."import_records" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_records";
create policy bsb_tenant_scope_update on "better_supabase"."import_records" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_records";
create policy bsb_tenant_scope_delete on "better_supabase"."import_records" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

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
-- @bsb-hash sha256:49e8892d8ac1c09d13cb9d117cd3b21db6203909bb758429a43c1372579acd27
-- Import runs and the external record map. import_upsert_batch writes items through the targets blocks and the app register, skips equal content, reports rows a user changed since the last import and marks missing keys on full runs. The dry run, parsing and mapping live in TypeScript.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_runs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_records";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."import_runs" (
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
alter table "better_supabase"."import_runs" add column if not exists "dry_run" boolean not null default false;
alter table "better_supabase"."import_runs" add column if not exists "full" boolean not null default false;
alter table "better_supabase"."import_runs" add column if not exists "input_checksum" text;
alter table "better_supabase"."import_runs" add column if not exists "correlation_id" text;
alter table "better_supabase"."import_runs" add column if not exists "scope_aliases" jsonb not null default '[]'::jsonb;
alter table "better_supabase"."import_runs" add column if not exists "started_at" timestamptz;
alter table "better_supabase"."import_runs" add column if not exists "finished_at" timestamptz;
alter table "better_supabase"."import_runs" drop constraint if exists "import_runs_status_check";
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."import_runs"'::regclass and c.conname = 'bsb_import_runs_status'
  ), 'pg_constraint'), '') <> 'better-supabase check 664f0f9f' then
    alter table "better_supabase"."import_runs" drop constraint if exists "bsb_import_runs_status";
    alter table "better_supabase"."import_runs" add constraint "bsb_import_runs_status" check ("status" in ('pending', 'running', 'completed', 'failed', 'canceled'));
    comment on constraint "bsb_import_runs_status" on "better_supabase"."import_runs" is 'better-supabase check 664f0f9f';
  end if;
end;
$$;
alter table "better_supabase"."import_runs" enable row level security;
revoke all on "better_supabase"."import_runs" from public, anon, authenticated;
grant select on "better_supabase"."import_runs" to authenticated;
grant all on "better_supabase"."import_runs" to service_role;
create index if not exists "import_runs_tenant_idx" on "better_supabase"."import_runs" ("tenant_id");
-- One pending or running run per organization and source.
create unique index if not exists "import_runs_active_idx" on "better_supabase"."import_runs" ("tenant_id", "source") where "status" in ('pending', 'running');

create table if not exists "better_supabase"."import_records" (
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
  "subject_updated_at_at_import" timestamptz,
  "missing_since" timestamptz,
  constraint "import_records_key" unique ("tenant_id", "source", "scope", "entity", "external_key", "role")
);
create index if not exists "import_records_subject_idx" on "better_supabase"."import_records" ("tenant_id", "subject_type", "subject_id");
alter table "better_supabase"."import_records" enable row level security;
revoke all on "better_supabase"."import_records" from public, anon, authenticated;
grant select on "better_supabase"."import_records" to authenticated;
grant all on "better_supabase"."import_records" to service_role;

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
    insert into "better_supabase"."import_runs" as r ("tenant_id", "source", "mapping", "dry_run", "full", "input_checksum", "correlation_id", "scope_aliases", "created_by")
    values (
      start_import_run.tenant,
      start_import_run.source,
      coalesce(v_options -> 'mapping', '{}'::jsonb),
      coalesce((v_options ->> 'dryRun')::boolean, false),
      coalesce((v_options ->> 'full')::boolean, false),
      v_options ->> 'inputChecksum',
      v_options ->> 'correlationId',
      coalesce(v_options -> 'scopeAliases', '[]'::jsonb),
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
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."tenant_id", 'source', v_run."source", 'status', v_run."status", 'mapping', v_run."mapping", 'counts', v_run."counts", 'errors', v_run."errors", 'dryRun', v_run."dry_run", 'full', v_run."full", 'inputChecksum', v_run."input_checksum", 'correlationId', v_run."correlation_id", 'scopeAliases', v_run."scope_aliases", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'startedAt', v_run."started_at", 'finishedAt', v_run."finished_at");
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
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'source', r."source", 'status', r."status", 'mapping', r."mapping", 'counts', r."counts", 'errors', r."errors", 'dryRun', r."dry_run", 'full', r."full", 'inputChecksum', r."input_checksum", 'correlationId', r."correlation_id", 'scopeAliases', r."scope_aliases", 'createdBy', r."created_by", 'createdAt', r."created_at", 'startedAt', r."started_at", 'finishedAt', r."finished_at")
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
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_message text;
  v_hint text;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if v_entity <> all (array['attachment', 'data_lifecycle_row', 'field_value', 'supplier_item', 'product_identifier', 'order', 'payment_term', 'document_delivery_preference', 'quote', 'invoice', 'credit_note', 'accounting_account', 'accounting_journal', 'accounting_entry', 'accounting_opening_balance', 'tax_code', 'tax_rate']::text[]) then
    raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    raise exception 'items must be an array of { key, scope, data, refs }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_item in select e.value from jsonb_array_elements(v_items) e loop
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      continue;
    end if;

    -- jsonb text is key-ordered, so equal content hashes equally.
    v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;

      if not v_found then
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
            insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_updated_at_at_import"
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
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."missing_since" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        case v_entity
        when 'supplier_item' then
          v_current := "better_supabase"."supplier_item_updated_at"(v_rec."subject_id");
        when 'product_identifier' then
          v_current := "better_supabase"."product_identifier_updated_at"(v_rec."subject_id");
        when 'order' then
          v_current := "better_supabase"."order_updated_at"(v_rec."subject_id");
        when 'payment_term' then
          v_current := "better_supabase"."payment_term_updated_at"(v_rec."subject_id");
        when 'document_delivery_preference' then
          v_current := "better_supabase"."document_delivery_preference_updated_at"(v_rec."subject_id");
        when 'quote' then
          v_current := "better_supabase"."quote_updated_at"(v_rec."subject_id");
        when 'invoice' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'credit_note' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'tax_code' then
          v_current := "better_supabase"."tax_code_updated_at"(v_rec."subject_id");
          else null;
        end case;
        if v_current is not null and v_rec."subject_updated_at_at_import" is not null and v_current > v_rec."subject_updated_at_at_import" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_done := true;
        end if;
      end if;

      if not v_done then
        v_subject_id := case when v_found then v_rec."subject_id" else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run."tenant_id", 'scope', v_scope);
        case v_entity
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
      when 'order' then
        v_subject_type := 'order';
        v_out := "better_supabase"."import_order"(v_run_id, v_call, v_subject_id);
      when 'payment_term' then
        v_subject_type := 'payment_term';
        v_out := "better_supabase"."import_payment_term"(v_run_id, v_call, v_subject_id);
      when 'document_delivery_preference' then
        v_subject_type := 'document_delivery_preference';
        v_out := "better_supabase"."import_document_delivery_preference"(v_run_id, v_call, v_subject_id);
      when 'quote' then
        v_subject_type := 'quote';
        v_out := "better_supabase"."import_quote"(v_run_id, v_call, v_subject_id);
      when 'invoice' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_invoice"(v_run_id, v_call, v_subject_id);
      when 'credit_note' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_credit_note"(v_run_id, v_call, v_subject_id);
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
          insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import", "missing_since")
          values (
            v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
            coalesce(v_subject ->> 'role', 'primary'),
            coalesce(v_subject ->> 'subjectType', v_subject_type),
            v_subject ->> 'subjectId',
            v_hash, v_run_id, v_run_id,
            coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
            null
          )
          on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
            "subject_type" = excluded."subject_type",
            "subject_id" = excluded."subject_id",
            "content_hash" = excluded."content_hash",
            "last_run_id" = excluded."last_run_id",
            "subject_updated_at_at_import" = excluded."subject_updated_at_at_import",
            "missing_since" = null;
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
    end;
  end loop;

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
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
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit'] loop
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

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit'] loop
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
    "errors" = r."errors" || coalesce(v_result -> 'errors', '[]'::jsonb)
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
        update "better_supabase"."import_records" x set "missing_since" = coalesce(x."missing_since", now())
        where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
          and x."last_run_id" <> v_run_id
          and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  update "better_supabase"."import_runs" r set "status" = 'completed', "finished_at" = now(), "counts" = v_counts
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
    perform "better_supabase"."enqueue_job"(queue => '''imports''', payload => jsonb_build_object('run', v_run."id", 'entity', enqueue_import_chunks.entity, 'chunk', v_chunk), dedupe_key => v_run."id"::text || ':' || enqueue_import_chunks.entity || ':' || v_chunk::text, dedupe_running => false);
  end loop;
  return enqueue_import_chunks.chunks;
end;
$$;
revoke execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."import_runs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_runs";
create policy bsb_tenant_scope_select on "better_supabase"."import_runs" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_runs";
create policy bsb_tenant_scope_insert on "better_supabase"."import_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_runs";
create policy bsb_tenant_scope_update on "better_supabase"."import_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_runs";
create policy bsb_tenant_scope_delete on "better_supabase"."import_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."import_records";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_records";
create policy bsb_tenant_scope_select on "better_supabase"."import_records" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_records";
create policy bsb_tenant_scope_insert on "better_supabase"."import_records" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_records";
create policy bsb_tenant_scope_update on "better_supabase"."import_records" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_records";
create policy bsb_tenant_scope_delete on "better_supabase"."import_records" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

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
-- @bsb-hash sha256:b1d8e260cff9f04512a3deae9348d117e7081856788eae48ff96a34e6a132513
-- Import runs and the external record map. import_upsert_batch writes items through the targets blocks and the app register, skips equal content, reports rows a user changed since the last import and marks missing keys on full runs. The dry run, parsing and mapping live in TypeScript.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."import_runs";
    drop policy if exists bsb_tenant_scope_select on "app_private"."import_runs";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."import_runs";
    drop policy if exists bsb_tenant_scope_update on "app_private"."import_runs";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."import_runs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."import_records";
    drop policy if exists bsb_tenant_scope_select on "app_private"."import_records";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."import_records";
    drop policy if exists bsb_tenant_scope_update on "app_private"."import_records";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."import_records";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
create table if not exists "app_private"."import_runs" (
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
alter table "app_private"."import_runs" add column if not exists "dry_run" boolean not null default false;
alter table "app_private"."import_runs" add column if not exists "full" boolean not null default false;
alter table "app_private"."import_runs" add column if not exists "input_checksum" text;
alter table "app_private"."import_runs" add column if not exists "correlation_id" text;
alter table "app_private"."import_runs" add column if not exists "scope_aliases" jsonb not null default '[]'::jsonb;
alter table "app_private"."import_runs" add column if not exists "started_at" timestamptz;
alter table "app_private"."import_runs" add column if not exists "finished_at" timestamptz;
alter table "app_private"."import_runs" drop constraint if exists "import_runs_status_check";
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"app_private"."import_runs"'::regclass and c.conname = 'bsb_import_runs_status'
  ), 'pg_constraint'), '') <> 'better-supabase check 664f0f9f' then
    alter table "app_private"."import_runs" drop constraint if exists "bsb_import_runs_status";
    alter table "app_private"."import_runs" add constraint "bsb_import_runs_status" check ("status" in ('pending', 'running', 'completed', 'failed', 'canceled'));
    comment on constraint "bsb_import_runs_status" on "app_private"."import_runs" is 'better-supabase check 664f0f9f';
  end if;
end;
$$;
alter table "app_private"."import_runs" enable row level security;
revoke all on "app_private"."import_runs" from public, anon, authenticated;
grant select on "app_private"."import_runs" to authenticated;
grant all on "app_private"."import_runs" to service_role;
create index if not exists "import_runs_tenant_idx" on "app_private"."import_runs" ("tenant_id");
-- One pending or running run per organization and source.
create unique index if not exists "import_runs_active_idx" on "app_private"."import_runs" ("tenant_id", "source") where "status" in ('pending', 'running');

create table if not exists "app_private"."import_records" (
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
  "subject_updated_at_at_import" timestamptz,
  "missing_since" timestamptz,
  constraint "import_records_key" unique ("tenant_id", "source", "scope", "entity", "external_key", "role")
);
create index if not exists "import_records_subject_idx" on "app_private"."import_records" ("tenant_id", "subject_type", "subject_id");
alter table "app_private"."import_records" enable row level security;
revoke all on "app_private"."import_records" from public, anon, authenticated;
grant select on "app_private"."import_records" to authenticated;
grant all on "app_private"."import_records" to service_role;

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
    insert into "app_private"."import_runs" as r ("tenant_id", "source", "mapping", "dry_run", "full", "input_checksum", "correlation_id", "scope_aliases", "created_by")
    values (
      start_import_run.tenant,
      start_import_run.source,
      coalesce(v_options -> 'mapping', '{}'::jsonb),
      coalesce((v_options ->> 'dryRun')::boolean, false),
      coalesce((v_options ->> 'full')::boolean, false),
      v_options ->> 'inputChecksum',
      v_options ->> 'correlationId',
      coalesce(v_options -> 'scopeAliases', '[]'::jsonb),
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
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."tenant_id", 'source', v_run."source", 'status', v_run."status", 'mapping', v_run."mapping", 'counts', v_run."counts", 'errors', v_run."errors", 'dryRun', v_run."dry_run", 'full', v_run."full", 'inputChecksum', v_run."input_checksum", 'correlationId', v_run."correlation_id", 'scopeAliases', v_run."scope_aliases", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'startedAt', v_run."started_at", 'finishedAt', v_run."finished_at");
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
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'source', r."source", 'status', r."status", 'mapping', r."mapping", 'counts', r."counts", 'errors', r."errors", 'dryRun', r."dry_run", 'full', r."full", 'inputChecksum', r."input_checksum", 'correlationId', r."correlation_id", 'scopeAliases', r."scope_aliases", 'createdBy', r."created_by", 'createdAt', r."created_at", 'startedAt', r."started_at", 'finishedAt', r."finished_at")
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
  v_rec "app_private"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
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

  for v_item in select e.value from jsonb_array_elements(v_items) e loop
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      continue;
    end if;

    -- jsonb text is key-ordered, so equal content hashes equally.
    v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');

    begin
      v_done := false;
      select * into v_rec from "app_private"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;

      if not v_found then
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
            insert into "app_private"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_updated_at_at_import"
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
        update "app_private"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."missing_since" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        null;
        if v_current is not null and v_rec."subject_updated_at_at_import" is not null and v_current > v_rec."subject_updated_at_at_import" then
          update "app_private"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_done := true;
        end if;
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
          insert into "app_private"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import", "missing_since")
          values (
            v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
            coalesce(v_subject ->> 'role', 'primary'),
            coalesce(v_subject ->> 'subjectType', v_subject_type),
            v_subject ->> 'subjectId',
            v_hash, v_run_id, v_run_id,
            coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
            null
          )
          on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
            "subject_type" = excluded."subject_type",
            "subject_id" = excluded."subject_id",
            "content_hash" = excluded."content_hash",
            "last_run_id" = excluded."last_run_id",
            "subject_updated_at_at_import" = excluded."subject_updated_at_at_import",
            "missing_since" = null;
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
    end;
  end loop;

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
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
  select * into v_run from "app_private"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit'] loop
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

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit'] loop
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
    "errors" = r."errors" || coalesce(v_result -> 'errors', '[]'::jsonb)
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
        update "app_private"."import_records" x set "missing_since" = coalesce(x."missing_since", now())
        where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
          and x."last_run_id" <> v_run_id
          and x."scope" in (select y."scope" from "app_private"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  update "app_private"."import_runs" r set "status" = 'completed', "finished_at" = now(), "counts" = v_counts
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
    perform "better_supabase"."enqueue_job"(queue => '''imports''', payload => jsonb_build_object('run', v_run."id", 'entity', enqueue_import_chunks.entity, 'chunk', v_chunk), dedupe_key => v_run."id"::text || ':' || enqueue_import_chunks.entity || ':' || v_chunk::text, dedupe_running => false);
  end loop;
  return enqueue_import_chunks.chunks;
end;
$$;
revoke execute on function "app_private"."enqueue_import_chunks"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "app_private"."enqueue_import_chunks"(uuid, text, integer) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "app_private"."import_runs";
drop policy if exists bsb_tenant_scope_select on "app_private"."import_runs";
create policy bsb_tenant_scope_select on "app_private"."import_runs" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "app_private"."import_runs";
create policy bsb_tenant_scope_insert on "app_private"."import_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."import_runs";
create policy bsb_tenant_scope_update on "app_private"."import_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."import_runs";
create policy bsb_tenant_scope_delete on "app_private"."import_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."import_records";
drop policy if exists bsb_tenant_scope_select on "app_private"."import_records";
create policy bsb_tenant_scope_select on "app_private"."import_records" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "app_private"."import_records";
create policy bsb_tenant_scope_insert on "app_private"."import_records" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."import_records";
create policy bsb_tenant_scope_update on "app_private"."import_records" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."import_records";
create policy bsb_tenant_scope_delete on "app_private"."import_records" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

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
-- @bsb-hash sha256:ba70b62c6b77f639e64fe82029cb18b1bdd6b4e1d4845080f88dbe02702c0095
-- Import runs and the external record map. import_upsert_batch writes items through the targets blocks and the app register, skips equal content, reports rows a user changed since the last import and marks missing keys on full runs. The dry run, parsing and mapping live in TypeScript.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_runs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_records";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."import_runs" (
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
alter table "better_supabase"."import_runs" add column if not exists "dry_run" boolean not null default false;
alter table "better_supabase"."import_runs" add column if not exists "full" boolean not null default false;
alter table "better_supabase"."import_runs" add column if not exists "input_checksum" text;
alter table "better_supabase"."import_runs" add column if not exists "correlation_id" text;
alter table "better_supabase"."import_runs" add column if not exists "scope_aliases" jsonb not null default '[]'::jsonb;
alter table "better_supabase"."import_runs" add column if not exists "started_at" timestamptz;
alter table "better_supabase"."import_runs" add column if not exists "finished_at" timestamptz;
alter table "better_supabase"."import_runs" drop constraint if exists "import_runs_status_check";
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."import_runs"'::regclass and c.conname = 'bsb_import_runs_status'
  ), 'pg_constraint'), '') <> 'better-supabase check 664f0f9f' then
    alter table "better_supabase"."import_runs" drop constraint if exists "bsb_import_runs_status";
    alter table "better_supabase"."import_runs" add constraint "bsb_import_runs_status" check ("status" in ('pending', 'running', 'completed', 'failed', 'canceled'));
    comment on constraint "bsb_import_runs_status" on "better_supabase"."import_runs" is 'better-supabase check 664f0f9f';
  end if;
end;
$$;
alter table "better_supabase"."import_runs" enable row level security;
revoke all on "better_supabase"."import_runs" from public, anon, authenticated;
grant select on "better_supabase"."import_runs" to authenticated;
grant all on "better_supabase"."import_runs" to service_role;
create index if not exists "import_runs_tenant_idx" on "better_supabase"."import_runs" ("tenant_id");
-- One pending or running run per organization and source.
create unique index if not exists "import_runs_active_idx" on "better_supabase"."import_runs" ("tenant_id", "source") where "status" in ('pending', 'running');

create table if not exists "better_supabase"."import_records" (
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
  "subject_updated_at_at_import" timestamptz,
  "missing_since" timestamptz,
  constraint "import_records_key" unique ("tenant_id", "source", "scope", "entity", "external_key", "role")
);
create index if not exists "import_records_subject_idx" on "better_supabase"."import_records" ("tenant_id", "subject_type", "subject_id");
alter table "better_supabase"."import_records" enable row level security;
revoke all on "better_supabase"."import_records" from public, anon, authenticated;
grant select on "better_supabase"."import_records" to authenticated;
grant all on "better_supabase"."import_records" to service_role;

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
    insert into "better_supabase"."import_runs" as r ("tenant_id", "source", "mapping", "dry_run", "full", "input_checksum", "correlation_id", "scope_aliases", "created_by")
    values (
      start_import_run.tenant,
      start_import_run.source,
      coalesce(v_options -> 'mapping', '{}'::jsonb),
      coalesce((v_options ->> 'dryRun')::boolean, false),
      coalesce((v_options ->> 'full')::boolean, false),
      v_options ->> 'inputChecksum',
      v_options ->> 'correlationId',
      coalesce(v_options -> 'scopeAliases', '[]'::jsonb),
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
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."tenant_id", 'source', v_run."source", 'status', v_run."status", 'mapping', v_run."mapping", 'counts', v_run."counts", 'errors', v_run."errors", 'dryRun', v_run."dry_run", 'full', v_run."full", 'inputChecksum', v_run."input_checksum", 'correlationId', v_run."correlation_id", 'scopeAliases', v_run."scope_aliases", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'startedAt', v_run."started_at", 'finishedAt', v_run."finished_at");
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
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'source', r."source", 'status', r."status", 'mapping', r."mapping", 'counts', r."counts", 'errors', r."errors", 'dryRun', r."dry_run", 'full', r."full", 'inputChecksum', r."input_checksum", 'correlationId', r."correlation_id", 'scopeAliases', r."scope_aliases", 'createdBy', r."created_by", 'createdAt', r."created_at", 'startedAt', r."started_at", 'finishedAt', r."finished_at")
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
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
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

  for v_item in select e.value from jsonb_array_elements(v_items) e loop
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      continue;
    end if;

    -- jsonb text is key-ordered, so equal content hashes equally.
    v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;

      if not v_found then
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
            insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_updated_at_at_import"
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
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."missing_since" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        null;
        if v_current is not null and v_rec."subject_updated_at_at_import" is not null and v_current > v_rec."subject_updated_at_at_import" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_done := true;
        end if;
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
          insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import", "missing_since")
          values (
            v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
            coalesce(v_subject ->> 'role', 'primary'),
            coalesce(v_subject ->> 'subjectType', v_subject_type),
            v_subject ->> 'subjectId',
            v_hash, v_run_id, v_run_id,
            coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
            null
          )
          on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
            "subject_type" = excluded."subject_type",
            "subject_id" = excluded."subject_id",
            "content_hash" = excluded."content_hash",
            "last_run_id" = excluded."last_run_id",
            "subject_updated_at_at_import" = excluded."subject_updated_at_at_import",
            "missing_since" = null;
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
    end;
  end loop;

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
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
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit'] loop
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

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit'] loop
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
    "errors" = r."errors" || coalesce(v_result -> 'errors', '[]'::jsonb)
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
        update "better_supabase"."import_records" x set "missing_since" = coalesce(x."missing_since", now())
        where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
          and x."last_run_id" <> v_run_id
          and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  update "better_supabase"."import_runs" r set "status" = 'completed', "finished_at" = now(), "counts" = v_counts
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
    perform "better_supabase"."enqueue_job"(queue => '''imports''', payload => jsonb_build_object('run', v_run."id", 'entity', enqueue_import_chunks.entity, 'chunk', v_chunk), dedupe_key => v_run."id"::text || ':' || enqueue_import_chunks.entity || ':' || v_chunk::text, dedupe_running => false);
  end loop;
  return enqueue_import_chunks.chunks;
end;
$$;
revoke execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."import_runs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_runs";
create policy bsb_tenant_scope_select on "better_supabase"."import_runs" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_runs";
create policy bsb_tenant_scope_insert on "better_supabase"."import_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_runs";
create policy bsb_tenant_scope_update on "better_supabase"."import_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_runs";
create policy bsb_tenant_scope_delete on "better_supabase"."import_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."import_records";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_records";
create policy bsb_tenant_scope_select on "better_supabase"."import_records" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_records";
create policy bsb_tenant_scope_insert on "better_supabase"."import_records" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_records";
create policy bsb_tenant_scope_update on "better_supabase"."import_records" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_records";
create policy bsb_tenant_scope_delete on "better_supabase"."import_records" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.imports.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."import_run"()
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_run"() $$;
revoke execute on function "api"."import_run"() from public;
grant execute on function "api"."import_run"() to anon, authenticated, service_role;

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

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
security invoker
set search_path = ''
as $$ select "better_supabase"."get_import_run"($1) $$;
revoke execute on function "api"."get_import_run"(uuid) from public, anon;
grant execute on function "api"."get_import_run"(uuid) to authenticated, service_role;

create or replace function "api"."list_import_runs"(tenant uuid, source text default null, status text default null, row_limit integer default 50)
returns setof jsonb
language sql
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

create or replace function "api"."enqueue_import_chunks"(run uuid, entity text, chunks integer)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."enqueue_import_chunks"($1, $2, $3) $$;
revoke execute on function "api"."enqueue_import_chunks"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "api"."enqueue_import_chunks"(uuid, text, integer) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

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
-- @bsb-hash sha256:a87dca5794518cb0f50d9fcf111581d25f4b0d105ec709f291294da15cb4ec26
-- Import runs and the external record map. import_upsert_batch writes items through the targets blocks and the app register, skips equal content, reports rows a user changed since the last import and marks missing keys on full runs. The dry run, parsing and mapping live in TypeScript.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
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
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_runs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_records";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
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
alter table "better_supabase"."import_runs" add column if not exists "full" boolean not null default false;
alter table "better_supabase"."import_runs" add column if not exists "input_checksum" text;
alter table "better_supabase"."import_runs" add column if not exists "correlation_id" text;
alter table "better_supabase"."import_runs" add column if not exists "scope_aliases" jsonb not null default '[]'::jsonb;
alter table "better_supabase"."import_runs" add column if not exists "started_at" timestamptz;
alter table "better_supabase"."import_runs" add column if not exists "finished_at" timestamptz;
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
alter table "better_supabase"."import_records" add column if not exists "subject_updated_at_at_import" timestamptz;
alter table "better_supabase"."import_records" add column if not exists "missing_since" timestamptz;
create index if not exists "import_records_subject_idx" on "better_supabase"."import_records" ("tenant_id", "subject_type", "subject_id");
alter table "better_supabase"."import_records" enable row level security;
grant select on "better_supabase"."import_records" to authenticated;
grant all on "better_supabase"."import_records" to service_role;

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
    insert into "better_supabase"."import_runs" as r ("tenant_id", "source", "mapping", "dry_run", "full", "input_checksum", "correlation_id", "scope_aliases", "created_by")
    values (
      start_import_run.tenant,
      start_import_run.source,
      coalesce(v_options -> 'mapping', '{}'::jsonb),
      coalesce((v_options ->> 'dryRun')::boolean, false),
      coalesce((v_options ->> 'full')::boolean, false),
      v_options ->> 'inputChecksum',
      v_options ->> 'correlationId',
      coalesce(v_options -> 'scopeAliases', '[]'::jsonb),
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
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."tenant_id", 'source', v_run."source", 'status', v_run."status", 'mapping', v_run."mapping", 'counts', v_run."counts", 'errors', v_run."errors", 'dryRun', v_run."dry_run", 'full', v_run."full", 'inputChecksum', v_run."input_checksum", 'correlationId', v_run."correlation_id", 'scopeAliases', v_run."scope_aliases", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'startedAt', v_run."started_at", 'finishedAt', v_run."finished_at");
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
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'source', r."source", 'status', r."status", 'mapping', r."mapping", 'counts', r."counts", 'errors', r."errors", 'dryRun', r."dry_run", 'full', r."full", 'inputChecksum', r."input_checksum", 'correlationId', r."correlation_id", 'scopeAliases', r."scope_aliases", 'createdBy', r."created_by", 'createdAt', r."created_at", 'startedAt', r."started_at", 'finishedAt', r."finished_at")
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
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
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

  for v_item in select e.value from jsonb_array_elements(v_items) e loop
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      continue;
    end if;

    -- jsonb text is key-ordered, so equal content hashes equally.
    v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;

      if not v_found then
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
            insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_updated_at_at_import"
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
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."missing_since" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        null;
        if v_current is not null and v_rec."subject_updated_at_at_import" is not null and v_current > v_rec."subject_updated_at_at_import" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_done := true;
        end if;
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
          insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import", "missing_since")
          values (
            v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
            coalesce(v_subject ->> 'role', 'primary'),
            coalesce(v_subject ->> 'subjectType', v_subject_type),
            v_subject ->> 'subjectId',
            v_hash, v_run_id, v_run_id,
            coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
            null
          )
          on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
            "subject_type" = excluded."subject_type",
            "subject_id" = excluded."subject_id",
            "content_hash" = excluded."content_hash",
            "last_run_id" = excluded."last_run_id",
            "subject_updated_at_at_import" = excluded."subject_updated_at_at_import",
            "missing_since" = null;
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
    end;
  end loop;

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
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
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit'] loop
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

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit'] loop
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
    "errors" = r."errors" || coalesce(v_result -> 'errors', '[]'::jsonb)
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
        update "better_supabase"."import_records" x set "missing_since" = coalesce(x."missing_since", now())
        where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
          and x."last_run_id" <> v_run_id
          and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  update "better_supabase"."import_runs" r set "status" = better_supabase.as_column_type('completed', (null::"better_supabase"."import_runs")."status"), "finished_at" = now(), "counts" = v_counts
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
    perform "better_supabase"."enqueue_job"(queue => '''imports''', payload => jsonb_build_object('run', v_run."id", 'entity', enqueue_import_chunks.entity, 'chunk', v_chunk), dedupe_key => v_run."id"::text || ':' || enqueue_import_chunks.entity || ':' || v_chunk::text, dedupe_running => false);
  end loop;
  return enqueue_import_chunks.chunks;
end;
$$;
revoke execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."import_runs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_runs";
create policy bsb_tenant_scope_select on "better_supabase"."import_runs" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_runs";
create policy bsb_tenant_scope_insert on "better_supabase"."import_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_runs";
create policy bsb_tenant_scope_update on "better_supabase"."import_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_runs";
create policy bsb_tenant_scope_delete on "better_supabase"."import_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."import_records";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_records";
create policy bsb_tenant_scope_select on "better_supabase"."import_records" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_records";
create policy bsb_tenant_scope_insert on "better_supabase"."import_records" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_records";
create policy bsb_tenant_scope_update on "better_supabase"."import_records" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_records";
create policy bsb_tenant_scope_delete on "better_supabase"."import_records" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

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
-- @bsb-hash sha256:26c502a16a979e8bbea9184b75e186716b673eba14f3771686b24cb5d95e5b17
-- Import runs and the external record map. import_upsert_batch writes items through the targets blocks and the app register, skips equal content, reports rows a user changed since the last import and marks missing keys on full runs. The dry run, parsing and mapping live in TypeScript.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_runs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_runs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_records";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_records";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."import_runs" (
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
alter table "better_supabase"."import_runs" add column if not exists "dry_run" boolean not null default false;
alter table "better_supabase"."import_runs" add column if not exists "full" boolean not null default false;
alter table "better_supabase"."import_runs" add column if not exists "input_checksum" text;
alter table "better_supabase"."import_runs" add column if not exists "correlation_id" text;
alter table "better_supabase"."import_runs" add column if not exists "scope_aliases" jsonb not null default '[]'::jsonb;
alter table "better_supabase"."import_runs" add column if not exists "started_at" timestamptz;
alter table "better_supabase"."import_runs" add column if not exists "finished_at" timestamptz;
alter table "better_supabase"."import_runs" drop constraint if exists "import_runs_status_check";
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."import_runs"'::regclass and c.conname = 'bsb_import_runs_status'
  ), 'pg_constraint'), '') <> 'better-supabase check 664f0f9f' then
    alter table "better_supabase"."import_runs" drop constraint if exists "bsb_import_runs_status";
    alter table "better_supabase"."import_runs" add constraint "bsb_import_runs_status" check ("status" in ('pending', 'running', 'completed', 'failed', 'canceled'));
    comment on constraint "bsb_import_runs_status" on "better_supabase"."import_runs" is 'better-supabase check 664f0f9f';
  end if;
end;
$$;
alter table "better_supabase"."import_runs" enable row level security;
revoke all on "better_supabase"."import_runs" from public, anon, authenticated;
grant select on "better_supabase"."import_runs" to authenticated;
grant all on "better_supabase"."import_runs" to service_role;
create index if not exists "import_runs_tenant_idx" on "better_supabase"."import_runs" ("org_id");
-- One pending or running run per organization and source.
create unique index if not exists "import_runs_active_idx" on "better_supabase"."import_runs" ("org_id", "source") where "status" in ('pending', 'running');

create table if not exists "better_supabase"."import_records" (
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
  "subject_updated_at_at_import" timestamptz,
  "missing_since" timestamptz,
  constraint "import_records_key" unique ("org_id", "source", "scope", "entity", "external_key", "role")
);
create index if not exists "import_records_subject_idx" on "better_supabase"."import_records" ("org_id", "subject_type", "subject_id");
alter table "better_supabase"."import_records" enable row level security;
revoke all on "better_supabase"."import_records" from public, anon, authenticated;
grant select on "better_supabase"."import_records" to authenticated;
grant all on "better_supabase"."import_records" to service_role;

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
    insert into "better_supabase"."import_runs" as r ("org_id", "source", "mapping", "dry_run", "full", "input_checksum", "correlation_id", "scope_aliases", "created_by")
    values (
      start_import_run.tenant,
      start_import_run.source,
      coalesce(v_options -> 'mapping', '{}'::jsonb),
      coalesce((v_options ->> 'dryRun')::boolean, false),
      coalesce((v_options ->> 'full')::boolean, false),
      v_options ->> 'inputChecksum',
      v_options ->> 'correlationId',
      coalesce(v_options -> 'scopeAliases', '[]'::jsonb),
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
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."org_id", 'source', v_run."source", 'status', v_run."status", 'mapping', v_run."mapping", 'counts', v_run."counts", 'errors', v_run."errors", 'dryRun', v_run."dry_run", 'full', v_run."full", 'inputChecksum', v_run."input_checksum", 'correlationId', v_run."correlation_id", 'scopeAliases', v_run."scope_aliases", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'startedAt', v_run."started_at", 'finishedAt', v_run."finished_at");
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
    select jsonb_build_object('id', r."id", 'organizationId', r."org_id", 'source', r."source", 'status', r."status", 'mapping', r."mapping", 'counts', r."counts", 'errors', r."errors", 'dryRun', r."dry_run", 'full', r."full", 'inputChecksum', r."input_checksum", 'correlationId', r."correlation_id", 'scopeAliases', r."scope_aliases", 'createdBy', r."created_by", 'createdAt', r."created_at", 'startedAt', r."started_at", 'finishedAt', r."finished_at")
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
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
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

  for v_item in select e.value from jsonb_array_elements(v_items) e loop
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      continue;
    end if;

    -- jsonb text is key-ordered, so equal content hashes equally.
    v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."org_id" = v_run."org_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;

      if not v_found then
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
            insert into "better_supabase"."import_records" ("org_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import")
            select x."org_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_updated_at_at_import"
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
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
        where x."org_id" = v_rec."org_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."missing_since" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        null;
        if v_current is not null and v_rec."subject_updated_at_at_import" is not null and v_current > v_rec."subject_updated_at_at_import" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_done := true;
        end if;
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
          insert into "better_supabase"."import_records" ("org_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import", "missing_since")
          values (
            v_run."org_id", v_run."source", v_scope, v_entity, v_key,
            coalesce(v_subject ->> 'role', 'primary'),
            coalesce(v_subject ->> 'subjectType', v_subject_type),
            v_subject ->> 'subjectId',
            v_hash, v_run_id, v_run_id,
            coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
            null
          )
          on conflict ("org_id", "source", "scope", "entity", "external_key", "role") do update set
            "subject_type" = excluded."subject_type",
            "subject_id" = excluded."subject_id",
            "content_hash" = excluded."content_hash",
            "last_run_id" = excluded."last_run_id",
            "subject_updated_at_at_import" = excluded."subject_updated_at_at_import",
            "missing_since" = null;
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
    end;
  end loop;

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
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
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit'] loop
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

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit'] loop
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
    "errors" = r."errors" || coalesce(v_result -> 'errors', '[]'::jsonb)
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
        update "better_supabase"."import_records" x set "missing_since" = coalesce(x."missing_since", now())
        where x."org_id" = v_run."org_id" and x."source" = v_run."source" and x."entity" = v_entity
          and x."last_run_id" <> v_run_id
          and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."org_id" = v_run."org_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  update "better_supabase"."import_runs" r set "status" = 'completed', "finished_at" = now(), "counts" = v_counts
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
    perform "better_supabase"."enqueue_job"(queue => '''imports''', payload => jsonb_build_object('run', v_run."id", 'entity', enqueue_import_chunks.entity, 'chunk', v_chunk), dedupe_key => v_run."id"::text || ':' || enqueue_import_chunks.entity || ':' || v_chunk::text, dedupe_running => false);
  end loop;
  return enqueue_import_chunks.chunks;
end;
$$;
revoke execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."enqueue_import_chunks"(uuid, text, integer) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."import_runs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_runs";
create policy bsb_tenant_scope_select on "better_supabase"."import_runs" as restrictive
  for select to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_runs";
create policy bsb_tenant_scope_insert on "better_supabase"."import_runs" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_runs";
create policy bsb_tenant_scope_update on "better_supabase"."import_runs" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_runs";
create policy bsb_tenant_scope_delete on "better_supabase"."import_runs" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."import_records";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."import_records";
create policy bsb_tenant_scope_select on "better_supabase"."import_records" as restrictive
  for select to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."import_records";
create policy bsb_tenant_scope_insert on "better_supabase"."import_records" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."import_records";
create policy bsb_tenant_scope_update on "better_supabase"."import_records" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."import_records";
create policy bsb_tenant_scope_delete on "better_supabase"."import_records" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

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
