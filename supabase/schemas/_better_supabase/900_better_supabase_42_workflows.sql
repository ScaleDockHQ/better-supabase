-- better-supabase module: workflows
-- @bsb-block workflows@3 managed
-- Engine-neutral workflow runs that members read through RLS, with a Realtime ping per status change and workflow_run.completed, .failed and .cancelled outbox events; cron schedules with idempotent fires, counting semaphores, admission control for starts (concurrency, debounce, singleton) and a retention purge.
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
-- Workflow runs of any engine, one row per run. Engines write them through
-- record_workflow_run (the Workflow SDK World mirrors its own runs); members
-- read them through RLS.
create table if not exists "better_supabase"."workflow_runs" (
  "id" uuid primary key default gen_random_uuid(),
  "engine" text not null check (length("engine") between 1 and 100),
  "external_id" text not null check (length("external_id") between 1 and 200),
  "definition" text not null check (length("definition") between 1 and 200),
  "tenant_id" uuid,
  "actor_id" uuid references auth.users (id) on delete set null,
  "status" text not null default 'queued' check ("status" in ('queued', 'running', 'waiting', 'completed', 'failed', 'cancelled')),
  "attributes" jsonb not null default '{}'::jsonb,
  "error" text,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "started_at" timestamptz,
  "completed_at" timestamptz,
  "cancel_requested_at" timestamptz,
  constraint workflow_runs_engine_external_key unique ("engine", "external_id")
);
create index if not exists workflow_runs_tenant_idx on "better_supabase"."workflow_runs" ("tenant_id", "created_at" desc);
create index if not exists workflow_runs_actor_idx on "better_supabase"."workflow_runs" ("actor_id", "created_at" desc);
create index if not exists workflow_runs_status_idx on "better_supabase"."workflow_runs" ("status", "completed_at");
-- The record a run belongs to (subject_type and subject_id, both or
-- neither), who its steps run as (principal_kind and principal_id), whether
-- it is a test run, and the trigger node it started from. Test runs write
-- no outbox events and fire no alerts.
alter table "better_supabase"."workflow_runs" add column if not exists "subject_type" text check (length("subject_type") between 1 and 100);
alter table "better_supabase"."workflow_runs" add column if not exists "subject_id" text check (length("subject_id") between 1 and 200);
alter table "better_supabase"."workflow_runs" add column if not exists "principal_kind" text check ("principal_kind" in ('user', 'service_principal', 'system', 'external'));
alter table "better_supabase"."workflow_runs" add column if not exists "principal_id" text check (length("principal_id") between 1 and 200);
alter table "better_supabase"."workflow_runs" add column if not exists "mode" text not null default 'live' check ("mode" in ('live', 'test'));
alter table "better_supabase"."workflow_runs" add column if not exists "trigger_node" text check (length("trigger_node") between 1 and 100);
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."workflow_runs"'::regclass and c.conname = 'workflow_runs_subject_check'
  ), 'pg_constraint'), '') <> 'better-supabase check 9166c23a' then
    alter table "better_supabase"."workflow_runs" drop constraint if exists "workflow_runs_subject_check";
    alter table "better_supabase"."workflow_runs" add constraint "workflow_runs_subject_check" check (("subject_type" is null) = ("subject_id" is null));
    comment on constraint "workflow_runs_subject_check" on "better_supabase"."workflow_runs" is 'better-supabase check 9166c23a';
  end if;
end;
$$;
create index if not exists workflow_runs_subject_idx on "better_supabase"."workflow_runs" ("tenant_id", "subject_type", "subject_id", "created_at" desc) where "subject_type" is not null;
alter table "better_supabase"."workflow_runs" enable row level security;
revoke all on "better_supabase"."workflow_runs" from anon, authenticated;
grant select on "better_supabase"."workflow_runs" to authenticated;
grant all on "better_supabase"."workflow_runs" to service_role;
drop policy if exists workflow_runs_read on "better_supabase"."workflow_runs";
create policy workflow_runs_read on "better_supabase"."workflow_runs" for select to authenticated
  using (
    "actor_id" = (select auth.uid())
    or "tenant_id" in (select better_supabase.tenant_ids_with('workflow.read'))
  );

-- Recurring starts. The tick (createWorkflows().schedules.tick) claims due
-- rows, starts each run with the key schedule:<id>:<fire time> and moves
-- next_run_at on with the next cron time it computes.
create table if not exists "better_supabase"."workflow_schedules" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "name" text not null check (length("name") between 1 and 200),
  "workflow" text not null check (length("workflow") between 1 and 200),
  "input" jsonb not null default '[]'::jsonb,
  "cron" text not null check (length("cron") between 1 and 200),
  "timezone" text not null default 'UTC',
  "next_run_at" timestamptz not null,
  "last_run_at" timestamptz,
  "locked_until" timestamptz,
  "paused" boolean not null default false,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  constraint workflow_schedules_tenant_name_key unique nulls not distinct ("tenant_id", "name")
);
create index if not exists workflow_schedules_due_idx on "better_supabase"."workflow_schedules" ("next_run_at") where not "paused";
create index if not exists workflow_schedules_created_by_idx on "better_supabase"."workflow_schedules" ("created_by");
alter table "better_supabase"."workflow_schedules" enable row level security;
revoke all on "better_supabase"."workflow_schedules" from anon, authenticated;
grant select on "better_supabase"."workflow_schedules" to authenticated;
grant all on "better_supabase"."workflow_schedules" to service_role;
drop policy if exists workflow_schedules_read on "better_supabase"."workflow_schedules";
create policy workflow_schedules_read on "better_supabase"."workflow_schedules" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('workflow.read')));

-- Counting semaphores: at most limit holders per key, each until it releases
-- or its lease runs out.
create table if not exists "better_supabase"."workflow_semaphores" (
  "key" text not null check (length("key") between 1 and 200),
  "holder" text not null check (length("holder") between 1 and 200),
  "acquired_at" timestamptz not null default now(),
  "expires_at" timestamptz not null,
  primary key ("key", "holder")
);
alter table "better_supabase"."workflow_semaphores" enable row level security;
revoke all on "better_supabase"."workflow_semaphores" from anon, authenticated;
grant all on "better_supabase"."workflow_semaphores" to service_role;

-- Admission control for starts: a request waits here until its key has room
-- (concurrency), its debounce window passed, or is dropped while a run with
-- its key is active (singleton).
create table if not exists "better_supabase"."workflow_start_requests" (
  "id" uuid primary key default gen_random_uuid(),
  "key" text not null check (length("key") between 1 and 200),
  "workflow" text not null check (length("workflow") between 1 and 200),
  "input" jsonb not null default '[]'::jsonb,
  "tenant_id" uuid,
  "actor_id" uuid references auth.users (id) on delete set null,
  "concurrency" integer check ("concurrency" > 0),
  "status" text not null default 'pending' check ("status" in ('pending', 'started', 'superseded', 'dropped')),
  "not_before" timestamptz not null default now(),
  "claimed_until" timestamptz,
  "run_id" text,
  "created_at" timestamptz not null default now(),
  "started_at" timestamptz
);
create index if not exists workflow_start_requests_key_idx on "better_supabase"."workflow_start_requests" ("key", "status");
create index if not exists workflow_start_requests_due_idx on "better_supabase"."workflow_start_requests" ("not_before") where "status" = 'pending';
create index if not exists workflow_start_requests_actor_idx on "better_supabase"."workflow_start_requests" ("actor_id");
alter table "better_supabase"."workflow_start_requests" add column if not exists "subject_type" text check (length("subject_type") between 1 and 100);
alter table "better_supabase"."workflow_start_requests" add column if not exists "subject_id" text check (length("subject_id") between 1 and 200);
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."workflow_start_requests"'::regclass and c.conname = 'workflow_start_requests_subject_check'
  ), 'pg_constraint'), '') <> 'better-supabase check 9166c23a' then
    alter table "better_supabase"."workflow_start_requests" drop constraint if exists "workflow_start_requests_subject_check";
    alter table "better_supabase"."workflow_start_requests" add constraint "workflow_start_requests_subject_check" check (("subject_type" is null) = ("subject_id" is null));
    comment on constraint "workflow_start_requests_subject_check" on "better_supabase"."workflow_start_requests" is 'better-supabase check 9166c23a';
  end if;
end;
$$;
alter table "better_supabase"."workflow_start_requests" enable row level security;
revoke all on "better_supabase"."workflow_start_requests" from anon, authenticated;
grant all on "better_supabase"."workflow_start_requests" to service_role;

-- Pings the run's topic and its tenant's topic on every status change, and
-- writes workflow_run.completed, .failed or .cancelled to the outbox (not
-- for test runs).
create or replace function "better_supabase"."workflow_runs_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old."status" = new."status" then
    return null;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('id', new."id", 'status', new."status"), 'status', 'workflow-run:' || new."id"::text, true);
    if new."tenant_id" is not null then
      perform realtime.send(jsonb_build_object('id', new."id", 'status', new."status"), 'status', 'workflow-runs:' || new."tenant_id"::text, true);
    end if;
  end if;
  if new."mode" = 'test' then
    return null;
  end if;
  case new."status"
    when 'completed' then
      perform "better_supabase".emit_event('workflow_run.completed', jsonb_build_object('runId', new."id", 'organizationId', new."tenant_id"::text, 'engine', new."engine", 'externalId', new."external_id", 'definition', new."definition", 'status', new."status", 'error', new."error", 'subjectType', new."subject_type", 'subjectId', new."subject_id"), 'workflow-runs/' || new."id", (new."tenant_id")::text, 'workflow_run.completed:' || new."id", 'better-supabase/workflows');
    when 'failed' then
      perform "better_supabase".emit_event('workflow_run.failed', jsonb_build_object('runId', new."id", 'organizationId', new."tenant_id"::text, 'engine', new."engine", 'externalId', new."external_id", 'definition', new."definition", 'status', new."status", 'error', new."error", 'subjectType', new."subject_type", 'subjectId', new."subject_id"), 'workflow-runs/' || new."id", (new."tenant_id")::text, 'workflow_run.failed:' || new."id", 'better-supabase/workflows');
    when 'cancelled' then
      perform "better_supabase".emit_event('workflow_run.cancelled', jsonb_build_object('runId', new."id", 'organizationId', new."tenant_id"::text, 'engine', new."engine", 'externalId', new."external_id", 'definition', new."definition", 'status', new."status", 'error', new."error", 'subjectType', new."subject_type", 'subjectId', new."subject_id"), 'workflow-runs/' || new."id", (new."tenant_id")::text, 'workflow_run.cancelled:' || new."id", 'better-supabase/workflows');
    else null;
  end case;
  return null;
end;
$$;
revoke execute on function "better_supabase"."workflow_runs_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_workflow_runs_status" on "better_supabase"."workflow_runs";
create trigger "bsb_workflow_runs_status" after insert or update of "status" on "better_supabase"."workflow_runs"
  for each row execute function "better_supabase"."workflow_runs_changed"();

-- Creates or updates the run an engine reports. tenant, actor, the subject,
-- the principal, the trigger node and started_at keep their first non-null
-- value, mode keeps the first report's (default live); attributes merge.
drop function if exists "better_supabase"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamptz, timestamptz);
create or replace function "better_supabase"."record_workflow_run"(
  engine text,
  external_id text,
  definition text,
  status text,
  tenant uuid default null,
  actor uuid default null,
  attributes jsonb default '{}'::jsonb,
  error text default null,
  started_at timestamptz default null,
  completed_at timestamptz default null,
  subject_type text default null,
  subject_id text default null,
  principal_kind text default null,
  principal_id text default null,
  mode text default null,
  trigger_node text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
begin
  insert into "better_supabase"."workflow_runs" as x ("engine", "external_id", "definition", "status", "tenant_id", "actor_id", "attributes", "error", "started_at", "completed_at", "subject_type", "subject_id", "principal_kind", "principal_id", "mode", "trigger_node")
  values (engine, external_id, definition, status, tenant, actor, coalesce(attributes, '{}'::jsonb), left(error, 4000), started_at, completed_at, subject_type, subject_id, principal_kind, principal_id, coalesce(mode, 'live'), trigger_node)
  on conflict on constraint workflow_runs_engine_external_key do update set
    "definition" = excluded."definition",
    "status" = excluded."status",
    "tenant_id" = coalesce(x."tenant_id", excluded."tenant_id"),
    "actor_id" = coalesce(x."actor_id", excluded."actor_id"),
    "attributes" = x."attributes" || excluded."attributes",
    "error" = coalesce(excluded."error", x."error"),
    "started_at" = coalesce(x."started_at", excluded."started_at"),
    "completed_at" = coalesce(excluded."completed_at", x."completed_at"),
    "subject_type" = case when x."subject_type" is null then excluded."subject_type" else x."subject_type" end,
    "subject_id" = case when x."subject_type" is null then excluded."subject_id" else x."subject_id" end,
    "principal_kind" = case when x."principal_kind" is null then excluded."principal_kind" else x."principal_kind" end,
    "principal_id" = case when x."principal_kind" is null then excluded."principal_id" else x."principal_id" end,
    "trigger_node" = coalesce(x."trigger_node", excluded."trigger_node"),
    "updated_at" = now()
  returning x."id" into v_id;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamptz, timestamptz, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamptz, timestamptz, text, text, text, text, text, text) to service_role;

-- The runs the caller may read, newest first: max rows created before before.
-- subject_type and subject_id narrow to one record's runs; mode is live
-- (the default), test, or null for both.
drop function if exists "better_supabase"."workflow_runs_list"(uuid, text, text, integer, timestamptz);
create or replace function "better_supabase"."workflow_runs_list"(
  tenant uuid default null,
  definition text default null,
  status text default null,
  max integer default 50,
  before timestamptz default null,
  subject_type text default null,
  subject_id text default null,
  mode text default 'live'
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'engine', x."engine",
    'externalId', x."external_id",
    'definition', x."definition",
    'tenant', x."tenant_id",
    'actor', x."actor_id",
    'status', x."status",
    'attributes', x."attributes",
    'error', x."error",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at",
    'startedAt', x."started_at",
    'completedAt', x."completed_at",
    'cancelRequestedAt', x."cancel_requested_at",
    'subjectType', x."subject_type",
    'subjectId', x."subject_id",
    'principalKind', x."principal_kind",
    'principalId', x."principal_id",
    'mode', x."mode",
    'triggerNode', x."trigger_node"
  ) order by x."created_at" desc), '[]'::jsonb)
  from (
    select * from "better_supabase"."workflow_runs" y
    where (workflow_runs_list.tenant is null or y."tenant_id" = workflow_runs_list.tenant)
      and (workflow_runs_list.definition is null or y."definition" = workflow_runs_list.definition)
      and (workflow_runs_list.status is null or y."status" = workflow_runs_list.status)
      and (workflow_runs_list.before is null or y."created_at" < workflow_runs_list.before)
      and (workflow_runs_list.subject_type is null or y."subject_type" = workflow_runs_list.subject_type)
      and (workflow_runs_list.subject_id is null or y."subject_id" = workflow_runs_list.subject_id)
      and (workflow_runs_list.mode is null or y."mode" = workflow_runs_list.mode)
    order by y."created_at" desc
    limit least(greatest(coalesce(workflow_runs_list.max, 50), 1), 500)
  ) x;
$$;
revoke execute on function "better_supabase"."workflow_runs_list"(uuid, text, text, integer, timestamptz, text, text, text) from public, anon;
grant execute on function "better_supabase"."workflow_runs_list"(uuid, text, text, integer, timestamptz, text, text, text) to authenticated, service_role;

-- One run by its id or its engine's id, when the caller may read it.
create or replace function "better_supabase"."workflow_run_get"(run text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id",
    'engine', x."engine",
    'externalId', x."external_id",
    'definition', x."definition",
    'tenant', x."tenant_id",
    'actor', x."actor_id",
    'status', x."status",
    'attributes', x."attributes",
    'error', x."error",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at",
    'startedAt', x."started_at",
    'completedAt', x."completed_at",
    'cancelRequestedAt', x."cancel_requested_at",
    'subjectType', x."subject_type",
    'subjectId', x."subject_id",
    'principalKind', x."principal_kind",
    'principalId', x."principal_id",
    'mode', x."mode",
    'triggerNode', x."trigger_node"
  )
  from "better_supabase"."workflow_runs" x
  where x."id"::text = workflow_run_get.run or x."external_id" = workflow_run_get.run
  order by x."id"::text = workflow_run_get.run desc
  limit 1;
$$;
revoke execute on function "better_supabase"."workflow_run_get"(text) from public, anon;
grant execute on function "better_supabase"."workflow_run_get"(text) to authenticated, service_role;

-- Marks a run for cancellation and returns it, or null when the caller may
-- not cancel it: the service role, the actor, or workflow.admin in its
-- tenant. The engine does the cancelling.
create or replace function "better_supabase"."request_workflow_cancel"(run text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run "better_supabase"."workflow_runs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_run from "better_supabase"."workflow_runs" x
  where (x."id"::text = request_workflow_cancel.run or x."external_id" = request_workflow_cancel.run)
  order by x."id"::text = request_workflow_cancel.run desc
  limit 1
  for update;
  if not found then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    or v_run."actor_id" = (select auth.uid())
    or (v_run."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_run."tenant_id", 'workflow.admin'), false))) then
    raise exception 'You may not cancel this run' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if v_run."status" in ('completed', 'failed', 'cancelled') then
    return jsonb_build_object(
    'id', v_run."id",
    'engine', v_run."engine",
    'externalId', v_run."external_id",
    'definition', v_run."definition",
    'tenant', v_run."tenant_id",
    'actor', v_run."actor_id",
    'status', v_run."status",
    'attributes', v_run."attributes",
    'error', v_run."error",
    'createdAt', v_run."created_at",
    'updatedAt', v_run."updated_at",
    'startedAt', v_run."started_at",
    'completedAt', v_run."completed_at",
    'cancelRequestedAt', v_run."cancel_requested_at",
    'subjectType', v_run."subject_type",
    'subjectId', v_run."subject_id",
    'principalKind', v_run."principal_kind",
    'principalId', v_run."principal_id",
    'mode', v_run."mode",
    'triggerNode', v_run."trigger_node"
  );
  end if;
  update "better_supabase"."workflow_runs" set "cancel_requested_at" = coalesce("cancel_requested_at", now()), "updated_at" = now()
  where "id" = v_run."id"
  returning * into v_run;
  return jsonb_build_object(
    'id', v_run."id",
    'engine', v_run."engine",
    'externalId', v_run."external_id",
    'definition', v_run."definition",
    'tenant', v_run."tenant_id",
    'actor', v_run."actor_id",
    'status', v_run."status",
    'attributes', v_run."attributes",
    'error', v_run."error",
    'createdAt', v_run."created_at",
    'updatedAt', v_run."updated_at",
    'startedAt', v_run."started_at",
    'completedAt', v_run."completed_at",
    'cancelRequestedAt', v_run."cancel_requested_at",
    'subjectType', v_run."subject_type",
    'subjectId', v_run."subject_id",
    'principalKind', v_run."principal_kind",
    'principalId', v_run."principal_id",
    'mode', v_run."mode",
    'triggerNode', v_run."trigger_node"
  );
end;
$$;
revoke execute on function "better_supabase"."request_workflow_cancel"(text) from public, anon;
grant execute on function "better_supabase"."request_workflow_cancel"(text) to authenticated, service_role;

-- Deletes finished runs older than older_than and old start requests, at
-- most batch of each per call.
create or replace function "better_supabase"."purge_workflow_runs"(older_than interval default '30 days', batch integer default 1000)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_runs integer;
begin
  with doomed as (
    select "id" from "better_supabase"."workflow_runs"
    where "status" in ('completed', 'failed', 'cancelled')
      and (coalesce("completed_at", "updated_at") < now() - least(coalesce(older_than, interval '30 days'), "better_supabase"."retention_floor"('workflow_runs'))
      and coalesce("completed_at", "updated_at") < now() - coalesce("better_supabase"."retention_for"('workflow_runs', ("tenant_id")::text), coalesce(older_than, interval '30 days'))
      and not "better_supabase"."is_held"('workflow_runs', ("tenant_id")::text))
    limit greatest(coalesce(batch, 1000), 1)
  )
  delete from "better_supabase"."workflow_runs" x using doomed where x."id" = doomed."id";
  get diagnostics v_runs = row_count;
  with doomed as (
    select "id" from "better_supabase"."workflow_start_requests"
    where "status" <> 'pending'
      and "created_at" < now() - coalesce(older_than, interval '30 days')
    limit greatest(coalesce(batch, 1000), 1)
  )
  delete from "better_supabase"."workflow_start_requests" x using doomed where x."id" = doomed."id";
  delete from "better_supabase"."workflow_semaphores" where "expires_at" < now();
  return v_runs;
end;
$$;
revoke execute on function "better_supabase"."purge_workflow_runs"(interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_workflow_runs"(interval, integer) to service_role;

-- Creates a schedule, or replaces the one with the same tenant and name.
-- The service role, or workflow.admin in tenant. payload is { input }: the
-- workflow's arguments.
create or replace function "better_supabase"."create_workflow_schedule"(
  name text,
  workflow text,
  cron text,
  next_run timestamptz,
  payload jsonb default '{}'::jsonb,
  timezone text default 'UTC',
  tenant uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_schedules"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.admin'), false))) then
    raise exception 'You may not schedule workflows here' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  insert into "better_supabase"."workflow_schedules" as x ("tenant_id", "name", "workflow", "input", "cron", "timezone", "next_run_at", "created_by")
  values (tenant, name, workflow, coalesce(payload -> 'input', '[]'::jsonb), cron, coalesce(timezone, 'UTC'), next_run, (select auth.uid()))
  on conflict on constraint workflow_schedules_tenant_name_key do update set
    "workflow" = excluded."workflow",
    "input" = excluded."input",
    "cron" = excluded."cron",
    "timezone" = excluded."timezone",
    "next_run_at" = excluded."next_run_at",
    "locked_until" = null
  returning * into v_row;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'name', v_row."name",
    'workflow', v_row."workflow",
    'input', v_row."input",
    'cron', v_row."cron",
    'timezone', v_row."timezone",
    'nextRunAt', v_row."next_run_at",
    'lastRunAt', v_row."last_run_at",
    'paused', v_row."paused",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at"
  );
end;
$$;
revoke execute on function "better_supabase"."create_workflow_schedule"(text, text, text, timestamptz, jsonb, text, uuid) from public, anon;
grant execute on function "better_supabase"."create_workflow_schedule"(text, text, text, timestamptz, jsonb, text, uuid) to authenticated, service_role;

-- The schedules the caller may read, by name.
create or replace function "better_supabase"."workflow_schedules_list"(tenant uuid default null)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'name', x."name",
    'workflow', x."workflow",
    'input', x."input",
    'cron', x."cron",
    'timezone', x."timezone",
    'nextRunAt', x."next_run_at",
    'lastRunAt', x."last_run_at",
    'paused', x."paused",
    'createdBy', x."created_by",
    'createdAt', x."created_at"
  ) order by x."name"), '[]'::jsonb)
  from "better_supabase"."workflow_schedules" x
  where workflow_schedules_list.tenant is null or x."tenant_id" = workflow_schedules_list.tenant;
$$;
revoke execute on function "better_supabase"."workflow_schedules_list"(uuid) from public, anon;
grant execute on function "better_supabase"."workflow_schedules_list"(uuid) to authenticated, service_role;

-- Pauses or resumes a schedule; false when there is none the caller manages.
create or replace function "better_supabase"."pause_workflow_schedule"(schedule uuid, paused boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."workflow_schedules" x set "paused" = coalesce(paused, true)
  where x."id" = schedule
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'workflow.admin'), false)));
  return found;
end;
$$;
revoke execute on function "better_supabase"."pause_workflow_schedule"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."pause_workflow_schedule"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."remove_workflow_schedule"(schedule uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."workflow_schedules" x
  where x."id" = schedule
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'workflow.admin'), false)));
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_workflow_schedule"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_workflow_schedule"(uuid) to authenticated, service_role;

-- Leases up to batch due schedules for lease seconds:
-- [{ id, tenant, name, workflow, input, cron, timezone, fireAt }].
create or replace function "better_supabase"."claim_due_workflow_schedules"(lease integer default 60, batch integer default 50)
returns jsonb
language sql
set search_path = ''
as $$
  with due as (
    select "id" from "better_supabase"."workflow_schedules"
    where not "paused"
      and "next_run_at" <= now()
      and ("locked_until" is null or "locked_until" < now())
    order by "next_run_at"
    limit greatest(coalesce(batch, 50), 1)
    for update skip locked
  ),
  leased as (
    update "better_supabase"."workflow_schedules" x set "locked_until" = now() + make_interval(secs => greatest(coalesce(lease, 60), 1))
    from due where x."id" = due."id"
    returning x.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', leased."id",
    'tenant', leased."tenant_id",
    'name', leased."name",
    'workflow', leased."workflow",
    'input', leased."input",
    'cron', leased."cron",
    'timezone', leased."timezone",
    'nextRunAt', leased."next_run_at",
    'lastRunAt', leased."last_run_at",
    'paused', leased."paused",
    'createdBy', leased."created_by",
    'createdAt', leased."created_at"
  ) || jsonb_build_object('fireAt', leased."next_run_at") order by leased."next_run_at"), '[]'::jsonb)
  from leased;
$$;
revoke execute on function "better_supabase"."claim_due_workflow_schedules"(integer, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."claim_due_workflow_schedules"(integer, integer) to service_role;

-- Records a fire and moves the schedule to next_run. false when another tick
-- already advanced it past fired.
create or replace function "better_supabase"."advance_workflow_schedule"(schedule uuid, fired timestamptz, next_run timestamptz)
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
begin
  update "better_supabase"."workflow_schedules" x set "last_run_at" = fired, "next_run_at" = next_run, "locked_until" = null
  where x."id" = schedule and x."next_run_at" = fired;
  return found;
end;
$$;
revoke execute on function "better_supabase"."advance_workflow_schedule"(uuid, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."advance_workflow_schedule"(uuid, timestamptz, timestamptz) to service_role;

-- Takes one of max slots of key for holder until it releases or ttl passes.
-- true when holder holds a slot (again, for a holder that already held one).
create or replace function "better_supabase"."acquire_workflow_semaphore"(key text, holder text, max integer, ttl interval default '5 minutes')
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_held integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('workflow_semaphore'), pg_catalog.hashtext(key));
  delete from "better_supabase"."workflow_semaphores" x where x."key" = key and x."expires_at" < now();
  update "better_supabase"."workflow_semaphores" x set "expires_at" = now() + coalesce(ttl, interval '5 minutes')
  where x."key" = key and x."holder" = holder;
  if found then
    return true;
  end if;
  select count(*) into v_held from "better_supabase"."workflow_semaphores" x where x."key" = key;
  if v_held >= greatest(coalesce(max, 1), 1) then
    return false;
  end if;
  insert into "better_supabase"."workflow_semaphores" ("key", "holder", "expires_at")
  values (key, holder, now() + coalesce(ttl, interval '5 minutes'));
  return true;
end;
$$;
revoke execute on function "better_supabase"."acquire_workflow_semaphore"(text, text, integer, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."acquire_workflow_semaphore"(text, text, integer, interval) to service_role;

create or replace function "better_supabase"."release_workflow_semaphore"(key text, holder text)
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
begin
  delete from "better_supabase"."workflow_semaphores" x where x."key" = key and x."holder" = holder;
  return found;
end;
$$;
revoke execute on function "better_supabase"."release_workflow_semaphore"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."release_workflow_semaphore"(text, text) to service_role;

-- Whether a start request with key is active: waiting, leased, or started
-- with a run that hasn't finished (a run no engine reports counts for a day).
create or replace function "better_supabase"."workflow_admission_active"(key text)
returns integer
language sql
stable
set search_path = ''
as $$
  select count(*)::integer from "better_supabase"."workflow_start_requests" x
  where x."key" = workflow_admission_active.key
    and (
      (x."status" = 'pending' and x."claimed_until" >= now())
      or (x."status" = 'started' and not exists (
        select 1 from "better_supabase"."workflow_runs" y
        where y."external_id" = x."run_id" and y."status" in ('completed', 'failed', 'cancelled')
      ) and x."started_at" > now() - interval '1 day')
    );
$$;
revoke execute on function "better_supabase"."workflow_admission_active"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_admission_active"(text) to service_role;

-- Queues a start under key: { id, status }. payload is { input }, the
-- workflow's arguments. singleton drops it ('dropped') while a run with key
-- is active; debounce replaces the waiting request and waits that long;
-- concurrency caps the runs started at once. subject_type and subject_id
-- name the record the run belongs to.
drop function if exists "better_supabase"."request_workflow_start"(text, text, jsonb, uuid, uuid, integer, interval, boolean);
create or replace function "better_supabase"."request_workflow_start"(
  key text,
  workflow text,
  payload jsonb default '{}'::jsonb,
  tenant uuid default null,
  actor uuid default null,
  concurrency integer default null,
  debounce interval default null,
  singleton boolean default false,
  subject_type text default null,
  subject_id text default null
)
returns jsonb
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('workflow_admission'), pg_catalog.hashtext(key));
  if coalesce(singleton, false) and (
    "better_supabase"."workflow_admission_active"(key) > 0
    or exists (select 1 from "better_supabase"."workflow_start_requests" x where x."key" = key and x."status" = 'pending')
  ) then
    return jsonb_build_object('id', null, 'status', 'dropped');
  end if;
  if debounce is not null then
    update "better_supabase"."workflow_start_requests" x set "status" = 'superseded'
    where x."key" = key and x."status" = 'pending'
      and (x."claimed_until" is null or x."claimed_until" < now());
  end if;
  insert into "better_supabase"."workflow_start_requests" ("key", "workflow", "input", "tenant_id", "actor_id", "concurrency", "not_before", "subject_type", "subject_id")
  values (key, workflow, coalesce(payload -> 'input', '[]'::jsonb), tenant, actor, case when coalesce(singleton, false) then 1 else concurrency end, now() + coalesce(debounce, interval '0'), subject_type, subject_id)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id, 'status', 'pending');
end;
$$;
revoke execute on function "better_supabase"."request_workflow_start"(text, text, jsonb, uuid, uuid, integer, interval, boolean, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."request_workflow_start"(text, text, jsonb, uuid, uuid, integer, interval, boolean, text, text) to service_role;

-- Leases up to batch start requests whose time came and whose key has room:
-- [{ id, key, workflow, input, tenant, actor, subjectType, subjectId }]. Start each, then call
-- mark_workflow_start_request; a lease that runs out frees the request.
create or replace function "better_supabase"."claim_workflow_start_requests"(lease integer default 60, batch integer default 50)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_row "better_supabase"."workflow_start_requests"%rowtype;
  v_out jsonb := '[]'::jsonb;
  v_taken integer := 0;
begin
  for v_row in
    select * from "better_supabase"."workflow_start_requests"
    where "status" = 'pending'
      and "not_before" <= now()
      and ("claimed_until" is null or "claimed_until" < now())
    order by "created_at"
    for update skip locked
  loop
    exit when v_taken >= greatest(coalesce(batch, 50), 1);
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('workflow_admission'), pg_catalog.hashtext(v_row."key"));
    if v_row."concurrency" is null
      or "better_supabase"."workflow_admission_active"(v_row."key") < v_row."concurrency" then
      update "better_supabase"."workflow_start_requests" set "claimed_until" = now() + make_interval(secs => greatest(coalesce(lease, 60), 1))
      where "id" = v_row."id";
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'id', v_row."id",
        'key', v_row."key",
        'workflow', v_row."workflow",
        'input', v_row."input",
        'tenant', v_row."tenant_id",
        'actor', v_row."actor_id",
        'subjectType', v_row."subject_type",
        'subjectId', v_row."subject_id"
      ));
      v_taken := v_taken + 1;
    end if;
  end loop;
  return v_out;
end;
$$;
revoke execute on function "better_supabase"."claim_workflow_start_requests"(integer, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."claim_workflow_start_requests"(integer, integer) to service_role;

-- Records the run a claimed request started.
create or replace function "better_supabase"."mark_workflow_start_request"(request uuid, run text)
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
begin
  update "better_supabase"."workflow_start_requests" x set "status" = 'started', "run_id" = run, "started_at" = now(), "claimed_until" = null
  where x."id" = request and x."status" = 'pending';
  return found;
end;
$$;
revoke execute on function "better_supabase"."mark_workflow_start_request"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_workflow_start_request"(uuid, text) to service_role;

-- Members may join a run's topic when they can read the run, and a tenant's
-- topic with workflow.read in it. The pings carry the run id and status.
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bsb_workflow_runs_receive" on realtime.messages;
    create policy "bsb_workflow_runs_receive" on realtime.messages for select to authenticated
      using (
        realtime.messages.extension = 'broadcast'
        and (
          (
            (select realtime.topic()) like 'workflow-run:%'
            and exists (
              select 1 from "better_supabase"."workflow_runs" x
              where x."id"::text = substr((select realtime.topic()), 14)
            )
          )
          or (
            (select realtime.topic()) like 'workflow-runs:%'
            and substr((select realtime.topic()), 15) in (
              select t::text from better_supabase.tenant_ids_with('workflow.read') t
            )
          )
        )
      );
  end if;
end;
$$;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."workflow_runs";
create policy bsb_tenant_scope on "better_supabase"."workflow_runs" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("actor_id" = (select auth.uid())
    or "tenant_id" in (select better_supabase.tenant_ids_with('workflow.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."workflow_schedules";
create policy bsb_tenant_scope on "better_supabase"."workflow_schedules" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('workflow.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.workflows.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamptz, timestamptz);
drop function if exists "api"."workflow_runs_list"(uuid, text, text, integer, timestamptz);
drop function if exists "api"."request_workflow_start"(text, text, jsonb, uuid, uuid, integer, interval, boolean);

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

create or replace function "api"."record_workflow_run"(engine text, external_id text, definition text, status text, tenant uuid default null, actor uuid default null, attributes jsonb default '{}'::jsonb, error text default null, started_at timestamptz default null, completed_at timestamptz default null, subject_type text default null, subject_id text default null, principal_kind text default null, principal_id text default null, mode text default null, trigger_node text default null)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_workflow_run"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16) $$;
revoke execute on function "api"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamptz, timestamptz, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function "api"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamptz, timestamptz, text, text, text, text, text, text) to service_role;

create or replace function "api"."workflow_runs_list"(tenant uuid default null, definition text default null, status text default null, max integer default 50, before timestamptz default null, subject_type text default null, subject_id text default null, mode text default 'live')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_runs_list"($1, $2, $3, $4, $5, $6, $7, $8) $$;
revoke execute on function "api"."workflow_runs_list"(uuid, text, text, integer, timestamptz, text, text, text) from public, anon;
grant execute on function "api"."workflow_runs_list"(uuid, text, text, integer, timestamptz, text, text, text) to authenticated, service_role;

create or replace function "api"."workflow_run_get"(run text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_run_get"($1) $$;
revoke execute on function "api"."workflow_run_get"(text) from public, anon;
grant execute on function "api"."workflow_run_get"(text) to authenticated, service_role;

create or replace function "api"."request_workflow_cancel"(run text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."request_workflow_cancel"($1) $$;
revoke execute on function "api"."request_workflow_cancel"(text) from public, anon;
grant execute on function "api"."request_workflow_cancel"(text) to authenticated, service_role;

create or replace function "api"."purge_workflow_runs"(older_than interval default '30 days', batch integer default 1000)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_workflow_runs"($1, $2) $$;
revoke execute on function "api"."purge_workflow_runs"(interval, integer) from public, anon, authenticated;
grant execute on function "api"."purge_workflow_runs"(interval, integer) to service_role;

create or replace function "api"."create_workflow_schedule"(name text, workflow text, cron text, next_run timestamptz, payload jsonb default '{}'::jsonb, timezone text default 'UTC', tenant uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_workflow_schedule"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."create_workflow_schedule"(text, text, text, timestamptz, jsonb, text, uuid) from public, anon;
grant execute on function "api"."create_workflow_schedule"(text, text, text, timestamptz, jsonb, text, uuid) to authenticated, service_role;

create or replace function "api"."workflow_schedules_list"(tenant uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_schedules_list"($1) $$;
revoke execute on function "api"."workflow_schedules_list"(uuid) from public, anon;
grant execute on function "api"."workflow_schedules_list"(uuid) to authenticated, service_role;

create or replace function "api"."pause_workflow_schedule"(schedule uuid, paused boolean default true)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."pause_workflow_schedule"($1, $2) $$;
revoke execute on function "api"."pause_workflow_schedule"(uuid, boolean) from public, anon;
grant execute on function "api"."pause_workflow_schedule"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."remove_workflow_schedule"(schedule uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_workflow_schedule"($1) $$;
revoke execute on function "api"."remove_workflow_schedule"(uuid) from public, anon;
grant execute on function "api"."remove_workflow_schedule"(uuid) to authenticated, service_role;

create or replace function "api"."claim_due_workflow_schedules"(lease integer default 60, batch integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."claim_due_workflow_schedules"($1, $2) $$;
revoke execute on function "api"."claim_due_workflow_schedules"(integer, integer) from public, anon, authenticated;
grant execute on function "api"."claim_due_workflow_schedules"(integer, integer) to service_role;

create or replace function "api"."advance_workflow_schedule"(schedule uuid, fired timestamptz, next_run timestamptz)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."advance_workflow_schedule"($1, $2, $3) $$;
revoke execute on function "api"."advance_workflow_schedule"(uuid, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function "api"."advance_workflow_schedule"(uuid, timestamptz, timestamptz) to service_role;

create or replace function "api"."acquire_workflow_semaphore"(key text, holder text, max integer, ttl interval default '5 minutes')
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."acquire_workflow_semaphore"($1, $2, $3, $4) $$;
revoke execute on function "api"."acquire_workflow_semaphore"(text, text, integer, interval) from public, anon, authenticated;
grant execute on function "api"."acquire_workflow_semaphore"(text, text, integer, interval) to service_role;

create or replace function "api"."release_workflow_semaphore"(key text, holder text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."release_workflow_semaphore"($1, $2) $$;
revoke execute on function "api"."release_workflow_semaphore"(text, text) from public, anon, authenticated;
grant execute on function "api"."release_workflow_semaphore"(text, text) to service_role;

create or replace function "api"."workflow_admission_active"(key text)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_admission_active"($1) $$;
revoke execute on function "api"."workflow_admission_active"(text) from public, anon, authenticated;
grant execute on function "api"."workflow_admission_active"(text) to service_role;

create or replace function "api"."request_workflow_start"(key text, workflow text, payload jsonb default '{}'::jsonb, tenant uuid default null, actor uuid default null, concurrency integer default null, debounce interval default null, singleton boolean default false, subject_type text default null, subject_id text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."request_workflow_start"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $$;
revoke execute on function "api"."request_workflow_start"(text, text, jsonb, uuid, uuid, integer, interval, boolean, text, text) from public, anon, authenticated;
grant execute on function "api"."request_workflow_start"(text, text, jsonb, uuid, uuid, integer, interval, boolean, text, text) to service_role;

create or replace function "api"."claim_workflow_start_requests"(lease integer default 60, batch integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."claim_workflow_start_requests"($1, $2) $$;
revoke execute on function "api"."claim_workflow_start_requests"(integer, integer) from public, anon, authenticated;
grant execute on function "api"."claim_workflow_start_requests"(integer, integer) to service_role;

create or replace function "api"."mark_workflow_start_request"(request uuid, run text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mark_workflow_start_request"($1, $2) $$;
revoke execute on function "api"."mark_workflow_start_request"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."mark_workflow_start_request"(uuid, text) to service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;
