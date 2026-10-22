-- better-supabase module: imports
-- @bsb-block imports@1 adopt
-- Import runs. Parsing, mapping and the dry run live in TypeScript. runImport marks the run running, then records import.completed or import.failed.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create or replace function "better_supabase"."start_import"(tenant uuid, kind text, mapping jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', start_import.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  insert into "centrakit"."import_runs" ("tenant_id", "kind", "mapping", "created_by")
  values (start_import.tenant, start_import.kind, coalesce(start_import.mapping, '{}'::jsonb), auth.uid())
  returning "id" into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."start_import"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."start_import"(uuid, text, jsonb) to authenticated, service_role;

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
  update "centrakit"."import_runs" set "status" = 'running'
  where "id" = mark_import_running.id and "status" = 'pending';
  if not found then
    raise exception 'no pending import with this id' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."mark_import_running"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_import_running"(uuid) to service_role;

create or replace function "better_supabase"."finish_import"(id uuid, status text, count integer, error text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  update "centrakit"."import_runs" set "status" = finish_import.status,
    "counts" = jsonb_build_object('imported', finish_import.count),
    "errors" = case when finish_import.error is null then '[]'::jsonb else jsonb_build_array(finish_import.error) end
  where "id" = finish_import.id
  returning "tenant_id" into v_tenant;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if finish_import.status = 'failed' then
    perform "better_supabase".emit_event('import.failed', jsonb_build_object('organizationId', v_tenant, 'id', finish_import.id, 'error', finish_import.error), 'imports/' || finish_import.id::text, (v_tenant)::text, null, 'domain');
  else
    perform "better_supabase".emit_event('import.completed', jsonb_build_object('organizationId', v_tenant, 'id', finish_import.id, 'count', finish_import.count), 'imports/' || finish_import.id::text, (v_tenant)::text, null, 'domain');
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."finish_import"(uuid, text, integer, text) from public, anon, authenticated;
grant execute on function "better_supabase"."finish_import"(uuid, text, integer, text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;
