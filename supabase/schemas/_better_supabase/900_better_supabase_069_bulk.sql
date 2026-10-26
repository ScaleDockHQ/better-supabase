-- better-supabase module: bulk
-- @bsb-block bulk@1 managed
-- @bsb-hash sha256:da078111ee1a6a993cae42672b3e83be03fa8a4ff89ece5b4dbb9ec26e8729fe
-- One action over many rows: up to a limit in one call with a result per row, and larger sets as a background run on the jobs queue that runs as the user who started it.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."bulk_runs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."bulk_runs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."bulk_runs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."bulk_runs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."bulk_runs";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."bulk_runs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "action" text not null,
  "args" jsonb not null default '{}'::jsonb,
  "ids" text[] not null,
  "position" integer not null default 0,
  "succeeded" integer not null default 0,
  "failed" integer not null default 0,
  "results" jsonb not null default '[]'::jsonb,
  "status" text not null default 'pending' check ("status" in ('pending', 'running', 'completed', 'failed')),
  "created_by" uuid not null,
  "created_at" timestamptz not null default now(),
  "finished_at" timestamptz
);
create index if not exists bulk_runs_created_by_idx on "better_supabase"."bulk_runs" ("created_by", "created_at" desc);
create index if not exists "bulk_runs_tenant_idx" on "better_supabase"."bulk_runs" ("tenant_id");
alter table "better_supabase"."bulk_runs" enable row level security;
revoke all on "better_supabase"."bulk_runs" from public, anon, authenticated;
grant select on "better_supabase"."bulk_runs" to authenticated;
grant all on "better_supabase"."bulk_runs" to service_role;
drop policy if exists bulk_runs_read on "better_supabase"."bulk_runs";
create policy bulk_runs_read on "better_supabase"."bulk_runs"
  for select to authenticated
  using ("created_by" = (select auth.uid()));

create or replace function "better_supabase"."bulk_row"(tenant uuid, subject_type text, subject_id text, action text, args jsonb)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_tag uuid;
begin
  case bulk_row.action
    when 'tags.set' then
      for v_tag in select value::uuid from jsonb_array_elements_text(coalesce(bulk_row.args -> 'add', '[]'::jsonb)) loop
        perform "better_supabase"."tag"(bulk_row.tenant, bulk_row.subject_type, bulk_row.subject_id, v_tag);
      end loop;
      for v_tag in select value::uuid from jsonb_array_elements_text(coalesce(bulk_row.args -> 'remove', '[]'::jsonb)) loop
        perform "better_supabase"."untag"(bulk_row.tenant, bulk_row.subject_type, bulk_row.subject_id, v_tag);
      end loop;
    when 'stateMachine.transition' then
      perform "better_supabase"."transition"(bulk_row.subject_type, bulk_row.subject_id, bulk_row.args ->> 'to', bulk_row.args ->> 'reason');
    when 'relations.link' then
      perform "better_supabase"."link"(bulk_row.tenant, bulk_row.args ->> 'kind', bulk_row.subject_type, bulk_row.subject_id, bulk_row.args ->> 'targetType', bulk_row.args ->> 'targetId', bulk_row.args -> 'data');
    when 'trash.trash' then
      perform "better_supabase"."trash"(bulk_row.tenant, bulk_row.subject_type, bulk_row.subject_id);
    else
      raise exception 'unknown bulk action' using errcode = '22023', hint = 'BULK_ACTION_UNKNOWN';
  end case;
end;
$$;
revoke execute on function "better_supabase"."bulk_row"(uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."bulk_row"(uuid, text, text, text, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."bulk_apply"(tenant uuid, subject_type text, ids text[], action text, args jsonb, atomic boolean)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_chunk text[] := coalesce(bulk_apply.ids, array[]::text[]);
  v_id text;
  v_ok integer := 0;
  v_failed integer := 0;
  v_results jsonb := '[]'::jsonb;
  v_message text;
  v_hint text;
  v_state text;
begin
  if not coalesce(better_supabase.can('tenant', bulk_apply.tenant, 'bulk.run'), false) then
    raise exception 'not allowed to run bulk actions' using errcode = '42501', hint = 'BULK_FORBIDDEN';
  end if;
  if not (bulk_apply.action = any (array['tags.set', 'stateMachine.transition', 'relations.link', 'trash.trash'])) then
    raise exception 'unknown bulk action' using errcode = '22023', hint = 'BULK_ACTION_UNKNOWN';
  end if;
  if cardinality(v_chunk) > 500 then
    raise exception 'more than 500 rows; start a background run' using errcode = '22023', hint = 'BULK_TOO_MANY';
  end if;
  foreach v_id in array v_chunk loop
    begin
      perform "better_supabase"."bulk_row"(bulk_apply.tenant, bulk_apply.subject_type, v_id, bulk_apply.action, coalesce(bulk_apply.args, '{}'::jsonb));
      v_ok := v_ok + 1;
      v_results := v_results || jsonb_build_array(jsonb_build_object('id', v_id, 'ok', true));
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint, v_state = returned_sqlstate;
      if coalesce(bulk_apply.atomic, false) then
        raise exception using message = v_message, hint = coalesce(v_hint, ''), errcode = v_state;
      end if;
      v_failed := v_failed + 1;
      v_results := v_results || jsonb_build_array(jsonb_build_object('id', v_id, 'ok', false, 'error', jsonb_build_object('code', nullif(v_hint, ''), 'message', v_message, 'sqlstate', v_state)));
    end;
  end loop;
  return jsonb_build_object('total', cardinality(v_chunk), 'succeeded', v_ok, 'failed', v_failed, 'results', v_results);
end;
$$;
revoke execute on function "better_supabase"."bulk_apply"(uuid, text, text[], text, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."bulk_apply"(uuid, text, text[], text, jsonb, boolean) to authenticated, service_role;

create or replace function "better_supabase"."start_bulk"(tenant uuid, subject_type text, ids text[], action text, args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_total integer := cardinality(coalesce(start_bulk.ids, array[]::text[]));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', start_bulk.tenant, 'bulk.run'), false) then
    raise exception 'not allowed to run bulk actions' using errcode = '42501', hint = 'BULK_FORBIDDEN';
  end if;
  if not (start_bulk.action = any (array['tags.set', 'stateMachine.transition', 'relations.link', 'trash.trash'])) then
    raise exception 'unknown bulk action' using errcode = '22023', hint = 'BULK_ACTION_UNKNOWN';
  end if;
  if v_total > 100000 then
    raise exception 'a background run takes at most 100000 rows' using errcode = '22023', hint = 'BULK_TOO_MANY';
  end if;
  
  insert into "better_supabase"."bulk_runs" ("tenant_id", "subject_type", "action", "args", "ids", "created_by")
  values (start_bulk.tenant, start_bulk.subject_type, start_bulk.action, coalesce(start_bulk.args, '{}'::jsonb), coalesce(start_bulk.ids, array[]::text[]), auth.uid())
  returning "id" into v_id;
  perform "better_supabase"."enqueue_job"(queue => 'bulk', payload => jsonb_build_object('run', v_id), dedupe_key => 'bulk:' || v_id::text, dedupe_running => false);
  return jsonb_build_object('id', v_id, 'total', v_total, 'topic', 'bulk:' || v_id::text);
end;
$$;
revoke execute on function "better_supabase"."start_bulk"(uuid, text, text[], text, jsonb) from public, anon;
grant execute on function "better_supabase"."start_bulk"(uuid, text, text[], text, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."bulk_run"(run_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'id', r."id", 'organizationId', r."tenant_id", 'subjectType', r."subject_type",
    'action', r."action", 'status', r."status", 'total', cardinality(r."ids"),
    'position', r."position", 'succeeded', r."succeeded", 'failed', r."failed",
    'results', r."results", 'createdAt', r."created_at", 'finishedAt', r."finished_at")
  from "better_supabase"."bulk_runs" r where r."id" = bulk_run.run_id;
$$;
revoke execute on function "better_supabase"."bulk_run"(uuid) from public, anon;
grant execute on function "better_supabase"."bulk_run"(uuid) to authenticated, service_role;

-- Runs the next rows of a background run as the user who started it, with
-- their claims and the authenticated role, so their permissions and policies apply.
create or replace function "better_supabase"."bulk_step"(run_id uuid, size integer)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_run "better_supabase"."bulk_runs"%rowtype;
  v_role text := current_user;
  v_claims text := current_setting('request.jwt.claims', true);
  v_size integer := least(greatest(coalesce(bulk_step.size, 200), 1), 500);
  v_chunk text[];
  v_id text;
  v_ok integer := 0;
  v_failed integer := 0;
  v_results jsonb := '[]'::jsonb;
  v_message text;
  v_hint text;
  v_state text;
  v_allowed boolean;
  v_status text;
  v_done boolean;
begin
  select * into v_run from "better_supabase"."bulk_runs" r where r."id" = bulk_step.run_id for update;
  if not found then
    raise exception 'bulk run not found' using errcode = 'P0002', hint = 'BULK_RUN_NOT_FOUND';
  end if;
  if v_run."status" in ('completed', 'failed') then
    return jsonb_build_object('id', v_run."id", 'status', v_run."status", 'done', true);
  end if;
  v_chunk := v_run."ids"[v_run."position" + 1 : v_run."position" + v_size];
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_run."created_by", 'role', 'authenticated', 'aud', 'authenticated')::text, true);
  set local role authenticated;
  v_allowed := coalesce(better_supabase.can('tenant', v_run."tenant_id", 'bulk.run'), false);
  if v_allowed then
    foreach v_id in array v_chunk loop
    begin
      perform "better_supabase"."bulk_row"(v_run."tenant_id", v_run."subject_type", v_id, v_run."action", v_run."args");
      v_ok := v_ok + 1;
      v_results := v_results || jsonb_build_array(jsonb_build_object('id', v_id, 'ok', true));
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint, v_state = returned_sqlstate;
      if false then
        raise exception using message = v_message, hint = coalesce(v_hint, ''), errcode = v_state;
      end if;
      v_failed := v_failed + 1;
      v_results := v_results || jsonb_build_array(jsonb_build_object('id', v_id, 'ok', false, 'error', jsonb_build_object('code', nullif(v_hint, ''), 'message', v_message, 'sqlstate', v_state)));
    end;
  end loop;
  end if;
  execute format('set local role %I', v_role);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  v_done := not v_allowed or v_run."position" + cardinality(coalesce(v_chunk, array[]::text[])) >= cardinality(v_run."ids");
  v_status := case when not v_allowed then 'failed' when v_done then 'completed' else 'running' end;
  update "better_supabase"."bulk_runs" set
    "position" = case when v_allowed then "position" + cardinality(coalesce(v_chunk, array[]::text[])) else "position" end,
    "succeeded" = "succeeded" + v_ok,
    "failed" = "failed" + v_failed,
    "results" = "results" || v_results,
    "status" = v_status,
    "finished_at" = case when v_done then now() else null end
  where "id" = v_run."id"
  returning * into v_run;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('id', v_run."id", 'status', v_status, 'position', v_run."position", 'total', cardinality(v_run."ids"), 'succeeded', v_run."succeeded", 'failed', v_run."failed"), 'progress', 'bulk:' || v_run."id"::text, true);
  end if;
  if v_done then
    perform "better_supabase".emit_event('bulk_run.completed', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run."id", 'kind', v_run."action", 'status', v_status, 'count', cardinality(v_run."ids"), 'failed', v_run."failed"), 'bulk-runs/' || v_run."id"::text, (v_run."tenant_id")::text, null, 'better-supabase/bulk');
  end if;
  return jsonb_build_object('id', v_run."id", 'status', v_status, 'position', v_run."position", 'total', cardinality(v_run."ids"), 'succeeded', v_run."succeeded", 'failed', v_run."failed", 'done', v_done);
end;
$$;
revoke execute on function "better_supabase"."bulk_step"(uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."bulk_step"(uuid, integer) to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."bulk_runs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."bulk_runs";
create policy bsb_tenant_scope_select on "better_supabase"."bulk_runs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("created_by" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."bulk_runs";
create policy bsb_tenant_scope_insert on "better_supabase"."bulk_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."bulk_runs";
create policy bsb_tenant_scope_update on "better_supabase"."bulk_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."bulk_runs";
create policy bsb_tenant_scope_delete on "better_supabase"."bulk_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.bulk.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

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

create or replace function "api"."bulk_row"(tenant uuid, subject_type text, subject_id text, action text, args jsonb)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."bulk_row"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."bulk_row"(uuid, text, text, text, jsonb) from public, anon;
grant execute on function "api"."bulk_row"(uuid, text, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."bulk_apply"(tenant uuid, subject_type text, ids text[], action text, args jsonb, atomic boolean)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."bulk_apply"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."bulk_apply"(uuid, text, text[], text, jsonb, boolean) from public, anon;
grant execute on function "api"."bulk_apply"(uuid, text, text[], text, jsonb, boolean) to authenticated, service_role;

create or replace function "api"."start_bulk"(tenant uuid, subject_type text, ids text[], action text, args jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."start_bulk"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."start_bulk"(uuid, text, text[], text, jsonb) from public, anon;
grant execute on function "api"."start_bulk"(uuid, text, text[], text, jsonb) to authenticated, service_role;

create or replace function "api"."bulk_run"(run_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."bulk_run"($1) $$;
revoke execute on function "api"."bulk_run"(uuid) from public, anon;
grant execute on function "api"."bulk_run"(uuid) to authenticated, service_role;

create or replace function "api"."bulk_step"(run_id uuid, size integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."bulk_step"($1, $2) $$;
revoke execute on function "api"."bulk_step"(uuid, integer) from public, anon, authenticated;
grant execute on function "api"."bulk_step"(uuid, integer) to service_role;

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
