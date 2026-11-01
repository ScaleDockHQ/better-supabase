-- ==== alone: schema supabase/schemas/900_better_supabase_092_pipelines.sql
-- better-supabase module: pipelines
-- @bsb-block pipelines@1 managed
-- @bsb-hash sha256:821a02eb3f360be7e80e39b0a3a4ff6a4545f3e049ca3ff8d33b146cc99b2f98
-- Tenant-editable pipelines for any registered subject: ordered stages whose categories map to open, success or failure, a stage history with time in stage, board totals per currency and a status mapping that runs through state-machine.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipelines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stages";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_transitions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stage_history";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Pipelines (ADR 0028): tenant-editable stages per subject type, each with
-- a category that maps to a fixed outcome, a stage history and board totals.

create table if not exists "better_supabase"."pipelines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "scope_id" text,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "rank" text collate "C" not null default 'V',
  "is_default" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique nulls not distinct ("tenant_id", "subject_type", "scope_id", "key")
);
create unique index if not exists pipelines_default_idx on "better_supabase"."pipelines" ("tenant_id", "subject_type", coalesce("scope_id", ''))
  where "is_default" and "archived_at" is null;
alter table "better_supabase"."pipelines" enable row level security;
revoke all on "better_supabase"."pipelines" from public, anon, authenticated;
grant select on "better_supabase"."pipelines" to authenticated;
grant all on "better_supabase"."pipelines" to service_role;
drop policy if exists pipelines_read on "better_supabase"."pipelines";
create policy pipelines_read on "better_supabase"."pipelines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

create table if not exists "better_supabase"."pipeline_stages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "pipeline_id" uuid not null references "better_supabase"."pipelines" ("id") on delete cascade,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "system_key" text,
  "name" text not null check (length("name") between 1 and 200),
  "color" text,
  "rank" text collate "C" not null default 'V',
  "category" text not null,
  "outcome" text not null check ("outcome" in ('open', 'success', 'failure')),
  "probability" smallint check ("probability" >= 0 and "probability" <= 100),
  "rotting_after_days" integer check ("rotting_after_days" > 0),
  "wip_limit" integer check ("wip_limit" > 0),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("pipeline_id", "key")
);
create index if not exists pipeline_stages_pipeline_idx on "better_supabase"."pipeline_stages" ("pipeline_id", "rank");
alter table "better_supabase"."pipeline_stages" enable row level security;
revoke all on "better_supabase"."pipeline_stages" from public, anon, authenticated;
grant select on "better_supabase"."pipeline_stages" to authenticated;
grant all on "better_supabase"."pipeline_stages" to service_role;
drop policy if exists pipeline_stages_read on "better_supabase"."pipeline_stages";
create policy pipeline_stages_read on "better_supabase"."pipeline_stages"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

create table if not exists "better_supabase"."pipeline_transitions" (
  "tenant_id" uuid not null,
  "pipeline_id" uuid not null references "better_supabase"."pipelines" ("id") on delete cascade,
  "from_stage_id" uuid not null references "better_supabase"."pipeline_stages" ("id") on delete cascade,
  "to_stage_id" uuid not null references "better_supabase"."pipeline_stages" ("id") on delete cascade,
  primary key ("from_stage_id", "to_stage_id")
);
create index if not exists pipeline_transitions_pipeline_idx on "better_supabase"."pipeline_transitions" ("pipeline_id");
create index if not exists pipeline_transitions_to_idx on "better_supabase"."pipeline_transitions" ("to_stage_id");
alter table "better_supabase"."pipeline_transitions" enable row level security;
revoke all on "better_supabase"."pipeline_transitions" from public, anon, authenticated;
grant select on "better_supabase"."pipeline_transitions" to authenticated;
grant all on "better_supabase"."pipeline_transitions" to service_role;
drop policy if exists pipeline_transitions_read on "better_supabase"."pipeline_transitions";
create policy pipeline_transitions_read on "better_supabase"."pipeline_transitions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

create table if not exists "better_supabase"."pipeline_stage_history" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "pipeline_id" uuid not null,
  "from_stage_id" uuid,
  "to_stage_id" uuid not null,
  "stage_name" text not null,
  "category" text not null,
  "outcome" text not null,
  "amount" bigint,
  "currency" char(3),
  "actor_user_id" uuid,
  "entered_at" timestamptz not null default now(),
  "exited_at" timestamptz
);
create index if not exists pipeline_stage_history_subject_idx on "better_supabase"."pipeline_stage_history" ("subject_type", "subject_id", "entered_at");
create index if not exists pipeline_stage_history_pipeline_idx on "better_supabase"."pipeline_stage_history" ("pipeline_id", "entered_at");
create unique index if not exists pipeline_stage_history_open_idx on "better_supabase"."pipeline_stage_history" ("subject_type", "subject_id") where "exited_at" is null;
alter table "better_supabase"."pipeline_stage_history" enable row level security;
revoke all on "better_supabase"."pipeline_stage_history" from public, anon, authenticated;
grant select on "better_supabase"."pipeline_stage_history" to authenticated;
grant all on "better_supabase"."pipeline_stage_history" to service_role;
-- A history row is visible to whoever can read its record.
drop policy if exists pipeline_stage_history_read on "better_supabase"."pipeline_stage_history";
create policy pipeline_stage_history_read on "better_supabase"."pipeline_stage_history"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));

-- The default pipeline of a subject type in a tenant and scope. The first
-- call creates it from the type's stage template in on.
create or replace function "better_supabase"."default_pipeline"(tenant uuid, subject_type text, scope_id text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select x."id" into v_id from "better_supabase"."pipelines" x
  where x."tenant_id" = default_pipeline.tenant
    and x."subject_type" = default_pipeline.subject_type
    and x."scope_id" is not distinct from default_pipeline.scope_id
    and x."archived_at" is null
  order by x."is_default" desc, x."rank" collate "C"
  limit 1;
  if v_id is not null then
    return v_id;
  end if;
  raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."default_pipeline"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."default_pipeline"(uuid, text, text) to service_role;



-- Creates a pipeline (pipeline null) or renames one. The first pipeline of a
-- subject type and scope is its default. Returns its row.
drop function if exists "better_supabase"."save_pipeline"(uuid, uuid, text, text, text, text, boolean, jsonb);
create or replace function "better_supabase"."save_pipeline"(tenant uuid, pipeline uuid, subject_type text, key text, name text, scope_id text, is_default boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pipeline uuid := save_pipeline.pipeline;
  v_created boolean := save_pipeline.pipeline is null;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_pipeline.tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if not (save_pipeline.subject_type = any ('{}'::text[])) then
    raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_save"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using save_pipeline.tenant, save_pipeline.pipeline, save_pipeline.subject_type, save_pipeline.key;
    end if;
  end;
  if coalesce(save_pipeline.is_default, false) then
    update "better_supabase"."pipelines" x set "is_default" = false
    where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type
      and x."scope_id" is not distinct from save_pipeline.scope_id and x."is_default"
      and x."id" is distinct from save_pipeline.pipeline;
  end if;
  begin
    if v_created then
      insert into "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default", "rank")
      values (save_pipeline.tenant, save_pipeline.subject_type, save_pipeline.scope_id, save_pipeline.key, save_pipeline.name,
        coalesce(save_pipeline.is_default, false) or not exists (
          select 1 from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type
            and x."scope_id" is not distinct from save_pipeline.scope_id and x."archived_at" is null),
        case
    when (select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) from '^z*')) = length((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type)) then (select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) || 'V'
    else left((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_pipeline;
    else
      update "better_supabase"."pipelines" x set "key" = save_pipeline.key, "name" = save_pipeline.name,
        "is_default" = coalesce(save_pipeline.is_default, x."is_default"), "updated_at" = now()
      where x."id" = save_pipeline.pipeline and x."tenant_id" = save_pipeline.tenant
        and x."subject_type" = save_pipeline.subject_type;
      if not found then
        raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another pipeline of this type has this key' using errcode = '23505', hint = 'PIPELINE_KEY_TAKEN';
  end;
  if v_created then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_pipeline, v_created;
    end if;
  end;
  return (select to_jsonb(x) from "better_supabase"."pipelines" x where x."id" = v_pipeline);
end;
$$;
revoke execute on function "better_supabase"."save_pipeline"(uuid, uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."save_pipeline"(uuid, uuid, text, text, text, text, boolean) to authenticated, service_role;

-- Archives a pipeline. Records still in it must move to another first.
create or replace function "better_supabase"."archive_pipeline"(pipeline uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_subject_type text;
  v_used boolean;
  v_pipeline uuid := archive_pipeline.pipeline;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."subject_type" into v_tenant, v_subject_type
  from "better_supabase"."pipelines" x where x."id" = archive_pipeline.pipeline and x."archived_at" is null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  v_used := false;
  if v_used then
    raise exception 'records are still in this pipeline; move them first' using errcode = '23503', hint = 'PIPELINE_IN_USE';
  end if;
  update "better_supabase"."pipelines" x set "archived_at" = now(), "is_default" = false, "updated_at" = now()
  where x."id" = archive_pipeline.pipeline;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_pipeline"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_pipeline"(uuid) to authenticated, service_role;

-- Creates a stage at the end of a pipeline (stage null) or changes one.
-- The category must be one the subject type declares; it sets the outcome.
create or replace function "better_supabase"."save_pipeline_stage"(pipeline uuid, stage uuid, key text, name text, category text, probability integer, rotting_after_days integer, wip_limit integer, color text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_subject_type text;
  v_outcome text;
  v_stage uuid := save_pipeline_stage.stage;
  v_pipeline uuid := save_pipeline_stage.pipeline;
  v_used boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."subject_type" into v_tenant, v_subject_type
  from "better_supabase"."pipelines" x where x."id" = save_pipeline_stage.pipeline and x."archived_at" is null;
  if v_tenant is null then
    raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  if v_outcome is null then
    raise exception 'this subject type has no such category' using errcode = '22023', hint = 'PIPELINE_CATEGORY_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_save"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using save_pipeline_stage.pipeline, save_pipeline_stage.stage, save_pipeline_stage.key, save_pipeline_stage.category;
    end if;
  end;
  begin
    if v_stage is null then
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "probability", "rotting_after_days", "wip_limit", "color", "rank")
      values (v_tenant, save_pipeline_stage.pipeline, save_pipeline_stage.key, save_pipeline_stage.name, save_pipeline_stage.category, v_outcome, save_pipeline_stage.probability, save_pipeline_stage.rotting_after_days, save_pipeline_stage.wip_limit, save_pipeline_stage.color,
        case
    when (select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*')) = length((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline)) then (select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) || 'V'
    else left((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_stage;
    else
      -- A stage holding records keeps its outcome, so won stays won.
      if exists (select 1 from "better_supabase"."pipeline_stages" x where x."id" = v_stage and x."outcome" <> v_outcome) then
        v_used := false;
        if v_used then
          raise exception 'records are in this stage; its outcome can''t change' using errcode = '23503', hint = 'PIPELINE_STAGE_IN_USE';
        end if;
      end if;
      update "better_supabase"."pipeline_stages" x set "key" = save_pipeline_stage.key, "name" = save_pipeline_stage.name, "category" = save_pipeline_stage.category, "outcome" = v_outcome, "probability" = save_pipeline_stage.probability, "rotting_after_days" = save_pipeline_stage.rotting_after_days, "wip_limit" = save_pipeline_stage.wip_limit, "color" = save_pipeline_stage.color, "updated_at" = now()
      where x."id" = v_stage and x."pipeline_id" = save_pipeline_stage.pipeline;
      if not found then
        raise exception 'stage not found' using errcode = 'P0002', hint = 'PIPELINE_STAGE_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another stage of this pipeline has this key' using errcode = '23505', hint = 'PIPELINE_STAGE_KEY_TAKEN';
  end;
  if save_pipeline_stage.stage is null then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_stage;
    end if;
  end;
  return (select to_jsonb(x) from "better_supabase"."pipeline_stages" x where x."id" = v_stage);
end;
$$;
revoke execute on function "better_supabase"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text) from public, anon;
grant execute on function "better_supabase"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text) to authenticated, service_role;

-- Moves a stage to a rank key the client computed with rankBetween.
create or replace function "better_supabase"."rank_pipeline_stage"(stage uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."pipeline_stages" x where x."id" = rank_pipeline_stage.stage;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if rank_pipeline_stage.rank is null or rank_pipeline_stage.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'PIPELINE_RANK_INVALID';
  end if;
  update "better_supabase"."pipeline_stages" x set "rank" = rank_pipeline_stage.rank, "updated_at" = now()
  where x."id" = rank_pipeline_stage.stage;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_pipeline_stage"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_pipeline_stage"(uuid, text) to authenticated, service_role;

-- Archives an empty stage. The last open stage of a pipeline stays.
create or replace function "better_supabase"."archive_pipeline_stage"(stage uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_pipeline uuid;
  v_subject_type text;
  v_outcome text;
  v_used boolean;
  v_stage uuid := archive_pipeline_stage.stage;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."pipeline_id", x."outcome", y."subject_type"
    into v_tenant, v_pipeline, v_outcome, v_subject_type
  from "better_supabase"."pipeline_stages" x join "better_supabase"."pipelines" y on y."id" = x."pipeline_id"
  where x."id" = archive_pipeline_stage.stage and x."archived_at" is null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  v_used := false;
  if v_used then
    raise exception 'records are in this stage; move them first' using errcode = '23503', hint = 'PIPELINE_STAGE_IN_USE';
  end if;
  if v_outcome = 'open' and not exists (
    select 1 from "better_supabase"."pipeline_stages" x where x."pipeline_id" = v_pipeline and x."outcome" = 'open'
      and x."archived_at" is null and x."id" <> archive_pipeline_stage.stage
  ) then
    raise exception 'a pipeline keeps at least one open stage' using errcode = '23514', hint = 'PIPELINE_LAST_OPEN_STAGE';
  end if;
  update "better_supabase"."pipeline_stages" x set "archived_at" = now(), "updated_at" = now() where x."id" = archive_pipeline_stage.stage;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_pipeline_stage"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_pipeline_stage"(uuid) to authenticated, service_role;

-- Replaces the allowed stage changes of a pipeline. An empty list allows
-- every change; pairs is a list of { "from": stage id, "to": stage id }.
create or replace function "better_supabase"."set_pipeline_transitions"(pipeline uuid, pairs jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."pipelines" x where x."id" = set_pipeline_transitions.pipeline;
  if v_tenant is null then
    raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(set_pipeline_transitions.pairs, '[]')) <> 'array' then
    raise exception 'pairs must be a list of { from, to } stage ids' using errcode = '22023', hint = 'PIPELINE_TRANSITIONS_INVALID';
  end if;
  delete from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = set_pipeline_transitions.pipeline;
  insert into "better_supabase"."pipeline_transitions" ("tenant_id", "pipeline_id", "from_stage_id", "to_stage_id")
  select v_tenant, set_pipeline_transitions.pipeline, (pair ->> 'from')::uuid, (pair ->> 'to')::uuid
  from jsonb_array_elements(coalesce(set_pipeline_transitions.pairs, '[]')) pair
  on conflict do nothing;
  get diagnostics v_count = row_count;
  if exists (
    select 1 from "better_supabase"."pipeline_transitions" x
    left join "better_supabase"."pipeline_stages" a on a."id" = x."from_stage_id" and a."pipeline_id" = x."pipeline_id"
    left join "better_supabase"."pipeline_stages" b on b."id" = x."to_stage_id" and b."pipeline_id" = x."pipeline_id"
    where x."pipeline_id" = set_pipeline_transitions.pipeline and (a."id" is null or b."id" is null)
  ) then
    raise exception 'every stage must belong to the pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITIONS_INVALID';
  end if;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_pipeline_transitions"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_pipeline_transitions"(uuid, jsonb) to authenticated, service_role;

-- One entry per active stage, in board order: the count of records the
-- caller can see, and per currency the amount and the amount weighted by
-- probability. Amounts are text so bigint minor units survive JSON.
create or replace function "better_supabase"."pipeline_board"(subject_type text, pipeline uuid, owner uuid default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."pipeline_board"(text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."pipeline_board"(text, uuid, uuid) to authenticated, service_role;

-- Per stage, between since and until: how many records entered it, how long
-- the ones that left stayed on average, and the share that went on to a
-- success stage. Reads the history the caller can see.
create or replace function "better_supabase"."pipeline_stats"(pipeline uuid, since timestamptz, until timestamptz)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with window_rows as (
    select * from "better_supabase"."pipeline_stage_history" h
    where h."pipeline_id" = pipeline_stats.pipeline
      and h."entered_at" >= pipeline_stats.since and h."entered_at" < pipeline_stats.until
  ),
  per_stage as (
    select w."to_stage_id" as stage_id, count(*) as entered,
      avg(extract(epoch from (w."exited_at" - w."entered_at"))) filter (where w."exited_at" is not null) as avg_seconds
    from window_rows w group by w."to_stage_id"
  ),
  closed as (
    select count(*) filter (where w."outcome" = 'success') as won,
      count(*) filter (where w."outcome" = 'failure') as lost
    from window_rows w
  )
  select jsonb_build_object(
    'won', closed.won,
    'lost', closed.lost,
    'winRate', case when closed.won + closed.lost = 0 then null else round(closed.won::numeric / (closed.won + closed.lost), 4) end,
    'stages', coalesce((
      select jsonb_agg(jsonb_build_object('stageId', st."id", 'key', st."key", 'entered', coalesce(ps.entered, 0), 'averageSeconds', round(ps.avg_seconds)) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st left join per_stage ps on ps.stage_id = st."id"
      where st."pipeline_id" = pipeline_stats.pipeline
    ), '[]'::jsonb)
  )
  from closed;
$$;
revoke execute on function "better_supabase"."pipeline_stats"(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."pipeline_stats"(uuid, timestamptz, timestamptz) to authenticated, service_role;

-- The open records of a pipeline the caller can see, oldest entry first:
-- when each entered its stage and whether it sits longer than the stage's
-- rotting limit.
create or replace function "better_supabase"."pipeline_health"(pipeline uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subjectType', h."subject_type", 'subjectId', h."subject_id", 'stageId', h."to_stage_id",
    'enteredAt', h."entered_at",
    'daysInStage', (extract(epoch from now() - h."entered_at") / 86400)::integer,
    'rotting', st."rotting_after_days" is not null and now() - h."entered_at" > make_interval(days => st."rotting_after_days")
  ) order by h."entered_at"), '[]'::jsonb)
  from "better_supabase"."pipeline_stage_history" h
  join "better_supabase"."pipeline_stages" st on st."id" = h."to_stage_id"
  where h."pipeline_id" = pipeline_health.pipeline and h."exited_at" is null and h."outcome" = 'open';
$$;
revoke execute on function "better_supabase"."pipeline_health"(uuid) from public, anon;
grant execute on function "better_supabase"."pipeline_health"(uuid) to authenticated, service_role;

-- The tenant's active pipelines of a subject type, each with its active
-- stages in board order.
create or replace function "better_supabase"."list_pipelines"(tenant uuid, subject_type text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) order by x."rank" collate "C"), '[]'::jsonb)
  from "better_supabase"."pipelines" x
  where x."tenant_id" = list_pipelines.tenant
    and x."subject_type" = list_pipelines.subject_type
    and x."archived_at" is null;
$$;
revoke execute on function "better_supabase"."list_pipelines"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_pipelines"(uuid, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."pipelines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipelines";
create policy bsb_tenant_scope_select on "better_supabase"."pipelines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipelines";
create policy bsb_tenant_scope_insert on "better_supabase"."pipelines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipelines";
create policy bsb_tenant_scope_update on "better_supabase"."pipelines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipelines";
create policy bsb_tenant_scope_delete on "better_supabase"."pipelines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stages";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_select on "better_supabase"."pipeline_stages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_insert on "better_supabase"."pipeline_stages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_update on "better_supabase"."pipeline_stages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_delete on "better_supabase"."pipeline_stages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_transitions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_select on "better_supabase"."pipeline_transitions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_insert on "better_supabase"."pipeline_transitions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_update on "better_supabase"."pipeline_transitions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_delete on "better_supabase"."pipeline_transitions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stage_history";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_select on "better_supabase"."pipeline_stage_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_insert on "better_supabase"."pipeline_stage_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_update on "better_supabase"."pipeline_stage_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_delete on "better_supabase"."pipeline_stage_history" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_092_pipelines.sql
-- better-supabase module: pipelines
-- @bsb-block-data pipelines
-- @bsb-hash sha256:afbc833c2019b6deab1e41862c83cefb962a135052476adab19c5b7d64bafdad
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('pipelines', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_092_pipelines.sql
-- better-supabase module: pipelines
-- @bsb-block pipelines@1 managed
-- @bsb-hash sha256:4f767693065fd96dc5e07cda363ca84a4427c91078d7b00ba84ef34b2aab5ea9
-- Tenant-editable pipelines for any registered subject: ordered stages whose categories map to open, success or failure, a stage history with time in stage, board totals per currency and a status mapping that runs through state-machine.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipelines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stages";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_transitions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stage_history";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Pipelines (ADR 0028): tenant-editable stages per subject type, each with
-- a category that maps to a fixed outcome, a stage history and board totals.

create table if not exists "better_supabase"."pipelines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "scope_id" text,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "rank" text collate "C" not null default 'V',
  "is_default" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique nulls not distinct ("tenant_id", "subject_type", "scope_id", "key")
);
create unique index if not exists pipelines_default_idx on "better_supabase"."pipelines" ("tenant_id", "subject_type", coalesce("scope_id", ''))
  where "is_default" and "archived_at" is null;
alter table "better_supabase"."pipelines" enable row level security;
revoke all on "better_supabase"."pipelines" from public, anon, authenticated;
grant select on "better_supabase"."pipelines" to authenticated;
grant all on "better_supabase"."pipelines" to service_role;
drop policy if exists pipelines_read on "better_supabase"."pipelines";
create policy pipelines_read on "better_supabase"."pipelines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

create table if not exists "better_supabase"."pipeline_stages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "pipeline_id" uuid not null references "better_supabase"."pipelines" ("id") on delete cascade,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "system_key" text,
  "name" text not null check (length("name") between 1 and 200),
  "color" text,
  "rank" text collate "C" not null default 'V',
  "category" text not null,
  "outcome" text not null check ("outcome" in ('open', 'success', 'failure')),
  "probability" smallint check ("probability" >= 0 and "probability" <= 100),
  "rotting_after_days" integer check ("rotting_after_days" > 0),
  "wip_limit" integer check ("wip_limit" > 0),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("pipeline_id", "key")
);
create index if not exists pipeline_stages_pipeline_idx on "better_supabase"."pipeline_stages" ("pipeline_id", "rank");
alter table "better_supabase"."pipeline_stages" enable row level security;
revoke all on "better_supabase"."pipeline_stages" from public, anon, authenticated;
grant select on "better_supabase"."pipeline_stages" to authenticated;
grant all on "better_supabase"."pipeline_stages" to service_role;
drop policy if exists pipeline_stages_read on "better_supabase"."pipeline_stages";
create policy pipeline_stages_read on "better_supabase"."pipeline_stages"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

create table if not exists "better_supabase"."pipeline_transitions" (
  "tenant_id" uuid not null,
  "pipeline_id" uuid not null references "better_supabase"."pipelines" ("id") on delete cascade,
  "from_stage_id" uuid not null references "better_supabase"."pipeline_stages" ("id") on delete cascade,
  "to_stage_id" uuid not null references "better_supabase"."pipeline_stages" ("id") on delete cascade,
  primary key ("from_stage_id", "to_stage_id")
);
create index if not exists pipeline_transitions_pipeline_idx on "better_supabase"."pipeline_transitions" ("pipeline_id");
create index if not exists pipeline_transitions_to_idx on "better_supabase"."pipeline_transitions" ("to_stage_id");
alter table "better_supabase"."pipeline_transitions" enable row level security;
revoke all on "better_supabase"."pipeline_transitions" from public, anon, authenticated;
grant select on "better_supabase"."pipeline_transitions" to authenticated;
grant all on "better_supabase"."pipeline_transitions" to service_role;
drop policy if exists pipeline_transitions_read on "better_supabase"."pipeline_transitions";
create policy pipeline_transitions_read on "better_supabase"."pipeline_transitions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

create table if not exists "better_supabase"."pipeline_stage_history" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "pipeline_id" uuid not null,
  "from_stage_id" uuid,
  "to_stage_id" uuid not null,
  "stage_name" text not null,
  "category" text not null,
  "outcome" text not null,
  "amount" bigint,
  "currency" char(3),
  "actor_user_id" uuid,
  "entered_at" timestamptz not null default now(),
  "exited_at" timestamptz
);
create index if not exists pipeline_stage_history_subject_idx on "better_supabase"."pipeline_stage_history" ("subject_type", "subject_id", "entered_at");
create index if not exists pipeline_stage_history_pipeline_idx on "better_supabase"."pipeline_stage_history" ("pipeline_id", "entered_at");
create unique index if not exists pipeline_stage_history_open_idx on "better_supabase"."pipeline_stage_history" ("subject_type", "subject_id") where "exited_at" is null;
alter table "better_supabase"."pipeline_stage_history" enable row level security;
revoke all on "better_supabase"."pipeline_stage_history" from public, anon, authenticated;
grant select on "better_supabase"."pipeline_stage_history" to authenticated;
grant all on "better_supabase"."pipeline_stage_history" to service_role;
-- A history row is visible to whoever can read its record.
drop policy if exists pipeline_stage_history_read on "better_supabase"."pipeline_stage_history";
create policy pipeline_stage_history_read on "better_supabase"."pipeline_stage_history"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));

-- The default pipeline of a subject type in a tenant and scope. The first
-- call creates it from the type's stage template in on.
create or replace function "better_supabase"."default_pipeline"(tenant uuid, subject_type text, scope_id text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select x."id" into v_id from "better_supabase"."pipelines" x
  where x."tenant_id" = default_pipeline.tenant
    and x."subject_type" = default_pipeline.subject_type
    and x."scope_id" is not distinct from default_pipeline.scope_id
    and x."archived_at" is null
  order by x."is_default" desc, x."rank" collate "C"
  limit 1;
  if v_id is not null then
    return v_id;
  end if;
  case default_pipeline.subject_type
    when 'deal' then
      insert into "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default")
      values (default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id, 'default', 'Default', true)
      on conflict do nothing
      returning "id" into v_id;
      if v_id is null then
        return "better_supabase"."default_pipeline"(default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id);
      end if;
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "system_key", "name", "category", "outcome", "probability", "rank")
      select default_pipeline.tenant, v_id, x.key, x.key, x.name, x.category, x.outcome, x.probability, x.rank
      from (values
          ('qualified', 'Qualified', 'open', 'open', 20::smallint, '8'),
          ('discovery', 'Discovery', 'open', 'open', 35::smallint, 'G'),
          ('proposal', 'Proposal', 'open', 'open', 55::smallint, 'O'),
          ('negotiation', 'Negotiation', 'open', 'open', 75::smallint, 'W'),
          ('closed_won', 'Closed won', 'won', 'success', 100::smallint, 'e'),
          ('closed_lost', 'Closed lost', 'lost', 'failure', 0::smallint, 'm')
      ) x(key, name, category, outcome, probability, rank);
    when 'task' then
      insert into "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default")
      values (default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id, 'default', 'Default', true)
      on conflict do nothing
      returning "id" into v_id;
      if v_id is null then
        return "better_supabase"."default_pipeline"(default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id);
      end if;
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "system_key", "name", "category", "outcome", "probability", "rank")
      select default_pipeline.tenant, v_id, x.key, x.key, x.name, x.category, x.outcome, x.probability, x.rank
      from (values
          ('triage', 'Triage', 'triage', 'open', null::smallint, '7'),
          ('backlog', 'Backlog', 'backlog', 'open', null::smallint, 'E'),
          ('todo', 'Todo', 'unstarted', 'open', null::smallint, 'L'),
          ('in_progress', 'In progress', 'started', 'open', null::smallint, 'S'),
          ('in_review', 'In review', 'started', 'open', null::smallint, 'Z'),
          ('done', 'Done', 'completed', 'success', null::smallint, 'g'),
          ('canceled', 'Canceled', 'canceled', 'failure', null::smallint, 'n')
      ) x(key, name, category, outcome, probability, rank);
    when 'application' then
      insert into "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default")
      values (default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id, 'default', 'Default', true)
      on conflict do nothing
      returning "id" into v_id;
      if v_id is null then
        return "better_supabase"."default_pipeline"(default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id);
      end if;
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "system_key", "name", "category", "outcome", "probability", "rank")
      select default_pipeline.tenant, v_id, x.key, x.key, x.name, x.category, x.outcome, x.probability, x.rank
      from (values
          ('applied', 'Applied', 'active', 'open', null::smallint, '7'),
          ('screening', 'Screening', 'active', 'open', null::smallint, 'E'),
          ('interview', 'Interview', 'active', 'open', null::smallint, 'L'),
          ('offer', 'Offer', 'active', 'open', null::smallint, 'S'),
          ('hired', 'Hired', 'hired', 'success', null::smallint, 'Z'),
          ('rejected', 'Rejected', 'rejected', 'failure', null::smallint, 'g'),
          ('withdrawn', 'Withdrawn', 'withdrawn', 'failure', null::smallint, 'n')
      ) x(key, name, category, outcome, probability, rank);
    when 'case' then
      insert into "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default")
      values (default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id, 'default', 'Default', true)
      on conflict do nothing
      returning "id" into v_id;
      if v_id is null then
        return "better_supabase"."default_pipeline"(default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id);
      end if;
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "system_key", "name", "category", "outcome", "probability", "rank")
      select default_pipeline.tenant, v_id, x.key, x.key, x.name, x.category, x.outcome, x.probability, x.rank
      from (values
          ('reported', 'Reported', 'open', 'open', null::smallint, '8'),
          ('investigating', 'Investigating', 'open', 'open', null::smallint, 'G'),
          ('acting', 'Acting', 'open', 'open', null::smallint, 'O'),
          ('verifying', 'Verifying', 'open', 'open', null::smallint, 'W'),
          ('closed', 'Closed', 'closed', 'success', null::smallint, 'e'),
          ('canceled', 'Canceled', 'canceled', 'failure', null::smallint, 'm')
      ) x(key, name, category, outcome, probability, rank);
    else
      raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  end case;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."default_pipeline"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."default_pipeline"(uuid, text, text) to service_role;


create or replace function better_supabase.bsb_pipeline_deal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
  -- The owner watches the record; a level they already chose stays.
  if new."owner_user_id" is not null and (tg_op = 'INSERT' or new."owner_user_id" is distinct from old."owner_user_id") then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_user_id", 'deal', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'deal', null);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'deal'
    and p."scope_id" is not distinct from null;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'deal', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'deal' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_user_id")
    values (new."tenant_id", 'deal', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, new."amount", new."currency", auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'deal', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'deal',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'deal', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  -- The owner watches the record; a level they already chose stays.
  if new."owner_user_id" is not null and (tg_op = 'INSERT' or new."owner_user_id" is distinct from old."owner_user_id") then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_user_id", 'deal', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
  return new;
end;
$$;
drop trigger if exists bsb_pipeline_deal on "better_supabase"."deals";
create trigger bsb_pipeline_deal before insert or update of "stage_id", "pipeline_id", "owner_user_id" on "better_supabase"."deals"
for each row execute function better_supabase.bsb_pipeline_deal();

create or replace function better_supabase.bsb_pipeline_status_deal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  select case s."category" when 'open' then 'open' when 'won' then 'won' when 'lost' then 'lost' end into v_status
  from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
  if v_status is not null and v_status is distinct from new."outcome"::text then
    update "better_supabase"."deals" r set "outcome" = (jsonb_populate_record(null::"better_supabase"."deals", jsonb_build_object('outcome', v_status)))."outcome"
    where r."id" = new."id";
  end if;
  return null;
end;
$$;
drop trigger if exists bsb_pipeline_status_deal on "better_supabase"."deals";
create trigger bsb_pipeline_status_deal after insert or update of "stage_id" on "better_supabase"."deals"
for each row execute function better_supabase.bsb_pipeline_status_deal();

create or replace function better_supabase.bsb_pipeline_task()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'task', new."team_id"::text);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'task'
    and p."scope_id" is not distinct from new."team_id"::text;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'task', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'task' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_user_id")
    values (new."tenant_id", 'task', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'task', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'task',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'task', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  return new;
end;
$$;
drop trigger if exists bsb_pipeline_task on "better_supabase"."tasks";
create trigger bsb_pipeline_task before insert or update of "stage_id", "pipeline_id" on "better_supabase"."tasks"
for each row execute function better_supabase.bsb_pipeline_task();

create or replace function better_supabase.bsb_pipeline_status_task()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  select case s."category" when 'triage' then 'triage' when 'backlog' then 'backlog' when 'unstarted' then 'unstarted' when 'started' then 'started' when 'completed' then 'completed' when 'canceled' then 'canceled' end into v_status
  from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
  if v_status is not null and v_status is distinct from new."state"::text then
    update "better_supabase"."tasks" r set "state" = (jsonb_populate_record(null::"better_supabase"."tasks", jsonb_build_object('state', v_status)))."state"
    where r."id" = new."id";
  end if;
  return null;
end;
$$;
drop trigger if exists bsb_pipeline_status_task on "better_supabase"."tasks";
create trigger bsb_pipeline_status_task after insert or update of "stage_id" on "better_supabase"."tasks"
for each row execute function better_supabase.bsb_pipeline_status_task();

create or replace function better_supabase.bsb_pipeline_application()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
  -- The owner watches the record; a level they already chose stays.
  if new."owner_user_id" is not null and (tg_op = 'INSERT' or new."owner_user_id" is distinct from old."owner_user_id") then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_user_id", 'application', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'application', new."job_id"::text);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'application'
    and p."scope_id" is not distinct from new."job_id"::text;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'application', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'application' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_user_id")
    values (new."tenant_id", 'application', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'application', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'application',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'application', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  -- The owner watches the record; a level they already chose stays.
  if new."owner_user_id" is not null and (tg_op = 'INSERT' or new."owner_user_id" is distinct from old."owner_user_id") then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_user_id", 'application', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
  return new;
end;
$$;
drop trigger if exists bsb_pipeline_application on "better_supabase"."applications";
create trigger bsb_pipeline_application before insert or update of "stage_id", "pipeline_id", "owner_user_id" on "better_supabase"."applications"
for each row execute function better_supabase.bsb_pipeline_application();

create or replace function better_supabase.bsb_pipeline_status_application()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  select case s."category" when 'active' then 'active' when 'hired' then 'hired' when 'rejected' then 'rejected' when 'withdrawn' then 'withdrawn' end into v_status
  from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
  if v_status is not null and v_status is distinct from new."state"::text then
    update "better_supabase"."applications" r set "state" = (jsonb_populate_record(null::"better_supabase"."applications", jsonb_build_object('state', v_status)))."state"
    where r."id" = new."id";
  end if;
  return null;
end;
$$;
drop trigger if exists bsb_pipeline_status_application on "better_supabase"."applications";
create trigger bsb_pipeline_status_application after insert or update of "stage_id" on "better_supabase"."applications"
for each row execute function better_supabase.bsb_pipeline_status_application();

create or replace function better_supabase.bsb_pipeline_case()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'case', new."kind_id"::text);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'case'
    and p."scope_id" is not distinct from new."kind_id"::text;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'case', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'case' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_user_id")
    values (new."tenant_id", 'case', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'case', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'case',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'case', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  return new;
end;
$$;
drop trigger if exists bsb_pipeline_case on "better_supabase"."cases";
create trigger bsb_pipeline_case before insert or update of "stage_id", "pipeline_id" on "better_supabase"."cases"
for each row execute function better_supabase.bsb_pipeline_case();
drop trigger if exists bsb_pipeline_status_case on "better_supabase"."cases";
drop function if exists better_supabase.bsb_pipeline_status_case();

-- Creates a pipeline (pipeline null) or renames one. The first pipeline of a
-- subject type and scope is its default. Returns its row.
drop function if exists "better_supabase"."save_pipeline"(uuid, uuid, text, text, text, text, boolean, jsonb);
create or replace function "better_supabase"."save_pipeline"(tenant uuid, pipeline uuid, subject_type text, key text, name text, scope_id text, is_default boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pipeline uuid := save_pipeline.pipeline;
  v_created boolean := save_pipeline.pipeline is null;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_pipeline.tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if not (save_pipeline.subject_type = any ('{deal,task,application,case}'::text[])) then
    raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_save"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using save_pipeline.tenant, save_pipeline.pipeline, save_pipeline.subject_type, save_pipeline.key;
    end if;
  end;
  if coalesce(save_pipeline.is_default, false) then
    update "better_supabase"."pipelines" x set "is_default" = false
    where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type
      and x."scope_id" is not distinct from save_pipeline.scope_id and x."is_default"
      and x."id" is distinct from save_pipeline.pipeline;
  end if;
  begin
    if v_created then
      insert into "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default", "rank")
      values (save_pipeline.tenant, save_pipeline.subject_type, save_pipeline.scope_id, save_pipeline.key, save_pipeline.name,
        coalesce(save_pipeline.is_default, false) or not exists (
          select 1 from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type
            and x."scope_id" is not distinct from save_pipeline.scope_id and x."archived_at" is null),
        case
    when (select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) from '^z*')) = length((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type)) then (select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) || 'V'
    else left((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_pipeline;
    else
      update "better_supabase"."pipelines" x set "key" = save_pipeline.key, "name" = save_pipeline.name,
        "is_default" = coalesce(save_pipeline.is_default, x."is_default"), "updated_at" = now()
      where x."id" = save_pipeline.pipeline and x."tenant_id" = save_pipeline.tenant
        and x."subject_type" = save_pipeline.subject_type;
      if not found then
        raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another pipeline of this type has this key' using errcode = '23505', hint = 'PIPELINE_KEY_TAKEN';
  end;
  if v_created then
    perform "better_supabase".emit_event('pipeline.created', jsonb_build_object('organizationId', save_pipeline.tenant, 'pipelineId', v_pipeline, 'subjectType', save_pipeline.subject_type, 'key', save_pipeline.key), 'pipelines/' || v_pipeline::text, (save_pipeline.tenant::text)::text, null, 'better-supabase/pipelines');
  perform better_supabase.audit_event(
    event_type => 'pipeline.created',
    category => 'configuration',
    target_type => 'pipeline',
    record_id => v_pipeline::text,
    summary => 'created pipeline ' || save_pipeline.name,
    tenant => (save_pipeline.tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', save_pipeline.tenant, 'pipelineId', v_pipeline, 'subjectType', save_pipeline.subject_type, 'key', save_pipeline.key)
  );
  else
    perform "better_supabase".emit_event('pipeline.updated', jsonb_build_object('organizationId', save_pipeline.tenant, 'pipelineId', v_pipeline, 'subjectType', save_pipeline.subject_type, 'key', save_pipeline.key), 'pipelines/' || v_pipeline::text, (save_pipeline.tenant::text)::text, null, 'better-supabase/pipelines');
  perform better_supabase.audit_event(
    event_type => 'pipeline.updated',
    category => 'configuration',
    target_type => 'pipeline',
    record_id => v_pipeline::text,
    summary => 'updated pipeline ' || save_pipeline.name,
    tenant => (save_pipeline.tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', save_pipeline.tenant, 'pipelineId', v_pipeline, 'subjectType', save_pipeline.subject_type, 'key', save_pipeline.key)
  );
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_pipeline, v_created;
    end if;
  end;
  return (select to_jsonb(x) from "better_supabase"."pipelines" x where x."id" = v_pipeline);
end;
$$;
revoke execute on function "better_supabase"."save_pipeline"(uuid, uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."save_pipeline"(uuid, uuid, text, text, text, text, boolean) to authenticated, service_role;

-- Archives a pipeline. Records still in it must move to another first.
create or replace function "better_supabase"."archive_pipeline"(pipeline uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_subject_type text;
  v_used boolean;
  v_pipeline uuid := archive_pipeline.pipeline;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."subject_type" into v_tenant, v_subject_type
  from "better_supabase"."pipelines" x where x."id" = archive_pipeline.pipeline and x."archived_at" is null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  case v_subject_type
    when 'deal' then
      perform 1 from "better_supabase"."deals" r where r."pipeline_id" = archive_pipeline.pipeline limit 1;
      v_used := found;
    when 'task' then
      perform 1 from "better_supabase"."tasks" r where r."pipeline_id" = archive_pipeline.pipeline limit 1;
      v_used := found;
    when 'application' then
      perform 1 from "better_supabase"."applications" r where r."pipeline_id" = archive_pipeline.pipeline limit 1;
      v_used := found;
    when 'case' then
      perform 1 from "better_supabase"."cases" r where r."pipeline_id" = archive_pipeline.pipeline limit 1;
      v_used := found;
    else
      v_used := false;
  end case;
  if v_used then
    raise exception 'records are still in this pipeline; move them first' using errcode = '23503', hint = 'PIPELINE_IN_USE';
  end if;
  update "better_supabase"."pipelines" x set "archived_at" = now(), "is_default" = false, "updated_at" = now()
  where x."id" = archive_pipeline.pipeline;
  perform "better_supabase".emit_event('pipeline.archived', jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'subjectType', v_subject_type), 'pipelines/' || v_pipeline::text, (v_tenant::text)::text, null, 'better-supabase/pipelines');
  perform better_supabase.audit_event(
    event_type => 'pipeline.archived',
    category => 'configuration',
    target_type => 'pipeline',
    record_id => v_pipeline::text,
    summary => 'archived a pipeline',
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'subjectType', v_subject_type)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_pipeline"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_pipeline"(uuid) to authenticated, service_role;

-- Creates a stage at the end of a pipeline (stage null) or changes one.
-- The category must be one the subject type declares; it sets the outcome.
create or replace function "better_supabase"."save_pipeline_stage"(pipeline uuid, stage uuid, key text, name text, category text, probability integer, rotting_after_days integer, wip_limit integer, color text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_subject_type text;
  v_outcome text;
  v_stage uuid := save_pipeline_stage.stage;
  v_pipeline uuid := save_pipeline_stage.pipeline;
  v_used boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."subject_type" into v_tenant, v_subject_type
  from "better_supabase"."pipelines" x where x."id" = save_pipeline_stage.pipeline and x."archived_at" is null;
  if v_tenant is null then
    raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  case v_subject_type
    when 'deal' then
      v_outcome := case save_pipeline_stage.category
      when 'open' then 'open'
      when 'won' then 'success'
      when 'lost' then 'failure'
    end;
    when 'task' then
      v_outcome := case save_pipeline_stage.category
      when 'triage' then 'open'
      when 'backlog' then 'open'
      when 'unstarted' then 'open'
      when 'started' then 'open'
      when 'completed' then 'success'
      when 'canceled' then 'failure'
    end;
    when 'application' then
      v_outcome := case save_pipeline_stage.category
      when 'active' then 'open'
      when 'hired' then 'success'
      when 'rejected' then 'failure'
      when 'withdrawn' then 'failure'
    end;
    when 'case' then
      v_outcome := case save_pipeline_stage.category
      when 'open' then 'open'
      when 'closed' then 'success'
      when 'canceled' then 'failure'
    end;
    else
      raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  end case;
  if v_outcome is null then
    raise exception 'this subject type has no such category' using errcode = '22023', hint = 'PIPELINE_CATEGORY_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_save"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using save_pipeline_stage.pipeline, save_pipeline_stage.stage, save_pipeline_stage.key, save_pipeline_stage.category;
    end if;
  end;
  begin
    if v_stage is null then
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "probability", "rotting_after_days", "wip_limit", "color", "rank")
      values (v_tenant, save_pipeline_stage.pipeline, save_pipeline_stage.key, save_pipeline_stage.name, save_pipeline_stage.category, v_outcome, save_pipeline_stage.probability, save_pipeline_stage.rotting_after_days, save_pipeline_stage.wip_limit, save_pipeline_stage.color,
        case
    when (select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*')) = length((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline)) then (select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) || 'V'
    else left((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_stage;
    else
      -- A stage holding records keeps its outcome, so won stays won.
      if exists (select 1 from "better_supabase"."pipeline_stages" x where x."id" = v_stage and x."outcome" <> v_outcome) then
        case v_subject_type
    when 'deal' then
      perform 1 from "better_supabase"."deals" r where r."stage_id" = v_stage limit 1;
      v_used := found;
    when 'task' then
      perform 1 from "better_supabase"."tasks" r where r."stage_id" = v_stage limit 1;
      v_used := found;
    when 'application' then
      perform 1 from "better_supabase"."applications" r where r."stage_id" = v_stage limit 1;
      v_used := found;
    when 'case' then
      perform 1 from "better_supabase"."cases" r where r."stage_id" = v_stage limit 1;
      v_used := found;
    else
      v_used := false;
  end case;
        if v_used then
          raise exception 'records are in this stage; its outcome can''t change' using errcode = '23503', hint = 'PIPELINE_STAGE_IN_USE';
        end if;
      end if;
      update "better_supabase"."pipeline_stages" x set "key" = save_pipeline_stage.key, "name" = save_pipeline_stage.name, "category" = save_pipeline_stage.category, "outcome" = v_outcome, "probability" = save_pipeline_stage.probability, "rotting_after_days" = save_pipeline_stage.rotting_after_days, "wip_limit" = save_pipeline_stage.wip_limit, "color" = save_pipeline_stage.color, "updated_at" = now()
      where x."id" = v_stage and x."pipeline_id" = save_pipeline_stage.pipeline;
      if not found then
        raise exception 'stage not found' using errcode = 'P0002', hint = 'PIPELINE_STAGE_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another stage of this pipeline has this key' using errcode = '23505', hint = 'PIPELINE_STAGE_KEY_TAKEN';
  end;
  if save_pipeline_stage.stage is null then
    perform "better_supabase".emit_event('pipeline_stage.created', jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage, 'key', save_pipeline_stage.key, 'category', save_pipeline_stage.category), 'pipelines/' || v_pipeline::text, (v_tenant::text)::text, null, 'better-supabase/pipelines');
  perform better_supabase.audit_event(
    event_type => 'pipeline_stage.created',
    category => 'configuration',
    target_type => 'pipeline',
    record_id => v_pipeline::text,
    summary => 'created stage ' || save_pipeline_stage.name,
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage, 'key', save_pipeline_stage.key, 'category', save_pipeline_stage.category)
  );
  else
    perform "better_supabase".emit_event('pipeline_stage.updated', jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage, 'key', save_pipeline_stage.key, 'category', save_pipeline_stage.category), 'pipelines/' || v_pipeline::text, (v_tenant::text)::text, null, 'better-supabase/pipelines');
  perform better_supabase.audit_event(
    event_type => 'pipeline_stage.updated',
    category => 'configuration',
    target_type => 'pipeline',
    record_id => v_pipeline::text,
    summary => 'updated stage ' || save_pipeline_stage.name,
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage, 'key', save_pipeline_stage.key, 'category', save_pipeline_stage.category)
  );
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_stage;
    end if;
  end;
  return (select to_jsonb(x) from "better_supabase"."pipeline_stages" x where x."id" = v_stage);
end;
$$;
revoke execute on function "better_supabase"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text) from public, anon;
grant execute on function "better_supabase"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text) to authenticated, service_role;

-- Moves a stage to a rank key the client computed with rankBetween.
create or replace function "better_supabase"."rank_pipeline_stage"(stage uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."pipeline_stages" x where x."id" = rank_pipeline_stage.stage;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if rank_pipeline_stage.rank is null or rank_pipeline_stage.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'PIPELINE_RANK_INVALID';
  end if;
  update "better_supabase"."pipeline_stages" x set "rank" = rank_pipeline_stage.rank, "updated_at" = now()
  where x."id" = rank_pipeline_stage.stage;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_pipeline_stage"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_pipeline_stage"(uuid, text) to authenticated, service_role;

-- Archives an empty stage. The last open stage of a pipeline stays.
create or replace function "better_supabase"."archive_pipeline_stage"(stage uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_pipeline uuid;
  v_subject_type text;
  v_outcome text;
  v_used boolean;
  v_stage uuid := archive_pipeline_stage.stage;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."pipeline_id", x."outcome", y."subject_type"
    into v_tenant, v_pipeline, v_outcome, v_subject_type
  from "better_supabase"."pipeline_stages" x join "better_supabase"."pipelines" y on y."id" = x."pipeline_id"
  where x."id" = archive_pipeline_stage.stage and x."archived_at" is null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  case v_subject_type
    when 'deal' then
      perform 1 from "better_supabase"."deals" r where r."stage_id" = archive_pipeline_stage.stage limit 1;
      v_used := found;
    when 'task' then
      perform 1 from "better_supabase"."tasks" r where r."stage_id" = archive_pipeline_stage.stage limit 1;
      v_used := found;
    when 'application' then
      perform 1 from "better_supabase"."applications" r where r."stage_id" = archive_pipeline_stage.stage limit 1;
      v_used := found;
    when 'case' then
      perform 1 from "better_supabase"."cases" r where r."stage_id" = archive_pipeline_stage.stage limit 1;
      v_used := found;
    else
      v_used := false;
  end case;
  if v_used then
    raise exception 'records are in this stage; move them first' using errcode = '23503', hint = 'PIPELINE_STAGE_IN_USE';
  end if;
  if v_outcome = 'open' and not exists (
    select 1 from "better_supabase"."pipeline_stages" x where x."pipeline_id" = v_pipeline and x."outcome" = 'open'
      and x."archived_at" is null and x."id" <> archive_pipeline_stage.stage
  ) then
    raise exception 'a pipeline keeps at least one open stage' using errcode = '23514', hint = 'PIPELINE_LAST_OPEN_STAGE';
  end if;
  update "better_supabase"."pipeline_stages" x set "archived_at" = now(), "updated_at" = now() where x."id" = archive_pipeline_stage.stage;
  perform "better_supabase".emit_event('pipeline_stage.archived', jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage), 'pipelines/' || v_pipeline::text, (v_tenant::text)::text, null, 'better-supabase/pipelines');
  perform better_supabase.audit_event(
    event_type => 'pipeline_stage.archived',
    category => 'configuration',
    target_type => 'pipeline_stage',
    record_id => v_stage::text,
    summary => 'archived a pipeline stage',
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_pipeline_stage"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_pipeline_stage"(uuid) to authenticated, service_role;

-- Replaces the allowed stage changes of a pipeline. An empty list allows
-- every change; pairs is a list of { "from": stage id, "to": stage id }.
create or replace function "better_supabase"."set_pipeline_transitions"(pipeline uuid, pairs jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."pipelines" x where x."id" = set_pipeline_transitions.pipeline;
  if v_tenant is null then
    raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(set_pipeline_transitions.pairs, '[]')) <> 'array' then
    raise exception 'pairs must be a list of { from, to } stage ids' using errcode = '22023', hint = 'PIPELINE_TRANSITIONS_INVALID';
  end if;
  delete from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = set_pipeline_transitions.pipeline;
  insert into "better_supabase"."pipeline_transitions" ("tenant_id", "pipeline_id", "from_stage_id", "to_stage_id")
  select v_tenant, set_pipeline_transitions.pipeline, (pair ->> 'from')::uuid, (pair ->> 'to')::uuid
  from jsonb_array_elements(coalesce(set_pipeline_transitions.pairs, '[]')) pair
  on conflict do nothing;
  get diagnostics v_count = row_count;
  if exists (
    select 1 from "better_supabase"."pipeline_transitions" x
    left join "better_supabase"."pipeline_stages" a on a."id" = x."from_stage_id" and a."pipeline_id" = x."pipeline_id"
    left join "better_supabase"."pipeline_stages" b on b."id" = x."to_stage_id" and b."pipeline_id" = x."pipeline_id"
    where x."pipeline_id" = set_pipeline_transitions.pipeline and (a."id" is null or b."id" is null)
  ) then
    raise exception 'every stage must belong to the pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITIONS_INVALID';
  end if;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_pipeline_transitions"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_pipeline_transitions"(uuid, jsonb) to authenticated, service_role;

-- One entry per active stage, in board order: the count of records the
-- caller can see, and per currency the amount and the amount weighted by
-- probability. Amounts are text so bigint minor units survive JSON.
create or replace function "better_supabase"."pipeline_board"(subject_type text, pipeline uuid, owner uuid default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case pipeline_board.subject_type
    when 'deal' then
      return (
        with rows as (
          select r."stage_id" as stage_id, r."currency"::text as currency, r."amount"::bigint as amount,
            r."amount" * coalesce(r."probability", st."probability", 0) / 100.0 as weighted
          from "better_supabase"."deals" r
          join "better_supabase"."pipeline_stages" st on st."id" = r."stage_id"
          where r."pipeline_id" = pipeline_board.pipeline and (pipeline_board.owner is null or r."owner_user_id" = pipeline_board.owner)
        ),
        counts as (select stage_id, count(*) as n from rows group by stage_id),
        sums as (
          select stage_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount::text, 'weighted', round(weighted)::bigint::text) order by currency) as totals
          from (select stage_id, currency, coalesce(sum(amount), 0) as amount, coalesce(sum(weighted), 0) as weighted from rows where currency is not null group by stage_id, currency) x
          group by stage_id
        )
        select coalesce(jsonb_agg(jsonb_build_object(
          'stageId', st."id", 'key', st."key", 'name', st."name", 'color', st."color",
          'category', st."category", 'outcome', st."outcome", 'probability', st."probability",
          'wipLimit', st."wip_limit", 'count', coalesce(n.n, 0),
          'overLimit', st."wip_limit" is not null and coalesce(n.n, 0) > st."wip_limit",
          'totals', coalesce(m.totals, '[]'::jsonb)
        ) order by st."rank" collate "C"), '[]'::jsonb)
        from "better_supabase"."pipeline_stages" st
        left join counts n on n.stage_id = st."id"
        left join sums m on m.stage_id = st."id"
        where st."pipeline_id" = pipeline_board.pipeline and st."archived_at" is null
      );
    when 'task' then
      return (
        with rows as (
          select r."stage_id" as stage_id, null::text as currency, null::bigint as amount, null::numeric as weighted
          from "better_supabase"."tasks" r
          join "better_supabase"."pipeline_stages" st on st."id" = r."stage_id"
          where r."pipeline_id" = pipeline_board.pipeline
        ),
        counts as (select stage_id, count(*) as n from rows group by stage_id),
        sums as (
          select stage_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount::text, 'weighted', round(weighted)::bigint::text) order by currency) as totals
          from (select stage_id, currency, coalesce(sum(amount), 0) as amount, coalesce(sum(weighted), 0) as weighted from rows where currency is not null group by stage_id, currency) x
          group by stage_id
        )
        select coalesce(jsonb_agg(jsonb_build_object(
          'stageId', st."id", 'key', st."key", 'name', st."name", 'color', st."color",
          'category', st."category", 'outcome', st."outcome", 'probability', st."probability",
          'wipLimit', st."wip_limit", 'count', coalesce(n.n, 0),
          'overLimit', st."wip_limit" is not null and coalesce(n.n, 0) > st."wip_limit",
          'totals', coalesce(m.totals, '[]'::jsonb)
        ) order by st."rank" collate "C"), '[]'::jsonb)
        from "better_supabase"."pipeline_stages" st
        left join counts n on n.stage_id = st."id"
        left join sums m on m.stage_id = st."id"
        where st."pipeline_id" = pipeline_board.pipeline and st."archived_at" is null
      );
    when 'application' then
      return (
        with rows as (
          select r."stage_id" as stage_id, null::text as currency, null::bigint as amount, null::numeric as weighted
          from "better_supabase"."applications" r
          join "better_supabase"."pipeline_stages" st on st."id" = r."stage_id"
          where r."pipeline_id" = pipeline_board.pipeline and (pipeline_board.owner is null or r."owner_user_id" = pipeline_board.owner)
        ),
        counts as (select stage_id, count(*) as n from rows group by stage_id),
        sums as (
          select stage_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount::text, 'weighted', round(weighted)::bigint::text) order by currency) as totals
          from (select stage_id, currency, coalesce(sum(amount), 0) as amount, coalesce(sum(weighted), 0) as weighted from rows where currency is not null group by stage_id, currency) x
          group by stage_id
        )
        select coalesce(jsonb_agg(jsonb_build_object(
          'stageId', st."id", 'key', st."key", 'name', st."name", 'color', st."color",
          'category', st."category", 'outcome', st."outcome", 'probability', st."probability",
          'wipLimit', st."wip_limit", 'count', coalesce(n.n, 0),
          'overLimit', st."wip_limit" is not null and coalesce(n.n, 0) > st."wip_limit",
          'totals', coalesce(m.totals, '[]'::jsonb)
        ) order by st."rank" collate "C"), '[]'::jsonb)
        from "better_supabase"."pipeline_stages" st
        left join counts n on n.stage_id = st."id"
        left join sums m on m.stage_id = st."id"
        where st."pipeline_id" = pipeline_board.pipeline and st."archived_at" is null
      );
    when 'case' then
      return (
        with rows as (
          select r."stage_id" as stage_id, null::text as currency, null::bigint as amount, null::numeric as weighted
          from "better_supabase"."cases" r
          join "better_supabase"."pipeline_stages" st on st."id" = r."stage_id"
          where r."pipeline_id" = pipeline_board.pipeline
        ),
        counts as (select stage_id, count(*) as n from rows group by stage_id),
        sums as (
          select stage_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount::text, 'weighted', round(weighted)::bigint::text) order by currency) as totals
          from (select stage_id, currency, coalesce(sum(amount), 0) as amount, coalesce(sum(weighted), 0) as weighted from rows where currency is not null group by stage_id, currency) x
          group by stage_id
        )
        select coalesce(jsonb_agg(jsonb_build_object(
          'stageId', st."id", 'key', st."key", 'name', st."name", 'color', st."color",
          'category', st."category", 'outcome', st."outcome", 'probability', st."probability",
          'wipLimit', st."wip_limit", 'count', coalesce(n.n, 0),
          'overLimit', st."wip_limit" is not null and coalesce(n.n, 0) > st."wip_limit",
          'totals', coalesce(m.totals, '[]'::jsonb)
        ) order by st."rank" collate "C"), '[]'::jsonb)
        from "better_supabase"."pipeline_stages" st
        left join counts n on n.stage_id = st."id"
        left join sums m on m.stage_id = st."id"
        where st."pipeline_id" = pipeline_board.pipeline and st."archived_at" is null
      );
    else
      raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  end case;
end;
$$;
revoke execute on function "better_supabase"."pipeline_board"(text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."pipeline_board"(text, uuid, uuid) to authenticated, service_role;

-- Per stage, between since and until: how many records entered it, how long
-- the ones that left stayed on average, and the share that went on to a
-- success stage. Reads the history the caller can see.
create or replace function "better_supabase"."pipeline_stats"(pipeline uuid, since timestamptz, until timestamptz)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with window_rows as (
    select * from "better_supabase"."pipeline_stage_history" h
    where h."pipeline_id" = pipeline_stats.pipeline
      and h."entered_at" >= pipeline_stats.since and h."entered_at" < pipeline_stats.until
  ),
  per_stage as (
    select w."to_stage_id" as stage_id, count(*) as entered,
      avg(extract(epoch from (w."exited_at" - w."entered_at"))) filter (where w."exited_at" is not null) as avg_seconds
    from window_rows w group by w."to_stage_id"
  ),
  closed as (
    select count(*) filter (where w."outcome" = 'success') as won,
      count(*) filter (where w."outcome" = 'failure') as lost
    from window_rows w
  )
  select jsonb_build_object(
    'won', closed.won,
    'lost', closed.lost,
    'winRate', case when closed.won + closed.lost = 0 then null else round(closed.won::numeric / (closed.won + closed.lost), 4) end,
    'stages', coalesce((
      select jsonb_agg(jsonb_build_object('stageId', st."id", 'key', st."key", 'entered', coalesce(ps.entered, 0), 'averageSeconds', round(ps.avg_seconds)) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st left join per_stage ps on ps.stage_id = st."id"
      where st."pipeline_id" = pipeline_stats.pipeline
    ), '[]'::jsonb)
  )
  from closed;
$$;
revoke execute on function "better_supabase"."pipeline_stats"(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."pipeline_stats"(uuid, timestamptz, timestamptz) to authenticated, service_role;

-- The open records of a pipeline the caller can see, oldest entry first:
-- when each entered its stage and whether it sits longer than the stage's
-- rotting limit.
create or replace function "better_supabase"."pipeline_health"(pipeline uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subjectType', h."subject_type", 'subjectId', h."subject_id", 'stageId', h."to_stage_id",
    'enteredAt', h."entered_at",
    'daysInStage', (extract(epoch from now() - h."entered_at") / 86400)::integer,
    'rotting', st."rotting_after_days" is not null and now() - h."entered_at" > make_interval(days => st."rotting_after_days")
  ) order by h."entered_at"), '[]'::jsonb)
  from "better_supabase"."pipeline_stage_history" h
  join "better_supabase"."pipeline_stages" st on st."id" = h."to_stage_id"
  where h."pipeline_id" = pipeline_health.pipeline and h."exited_at" is null and h."outcome" = 'open';
$$;
revoke execute on function "better_supabase"."pipeline_health"(uuid) from public, anon;
grant execute on function "better_supabase"."pipeline_health"(uuid) to authenticated, service_role;

-- The tenant's active pipelines of a subject type, each with its active
-- stages in board order.
create or replace function "better_supabase"."list_pipelines"(tenant uuid, subject_type text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) order by x."rank" collate "C"), '[]'::jsonb)
  from "better_supabase"."pipelines" x
  where x."tenant_id" = list_pipelines.tenant
    and x."subject_type" = list_pipelines.subject_type
    and x."archived_at" is null;
$$;
revoke execute on function "better_supabase"."list_pipelines"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_pipelines"(uuid, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."pipelines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipelines";
create policy bsb_tenant_scope_select on "better_supabase"."pipelines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipelines";
create policy bsb_tenant_scope_insert on "better_supabase"."pipelines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipelines";
create policy bsb_tenant_scope_update on "better_supabase"."pipelines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipelines";
create policy bsb_tenant_scope_delete on "better_supabase"."pipelines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stages";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_select on "better_supabase"."pipeline_stages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_insert on "better_supabase"."pipeline_stages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_update on "better_supabase"."pipeline_stages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_delete on "better_supabase"."pipeline_stages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_transitions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_select on "better_supabase"."pipeline_transitions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_insert on "better_supabase"."pipeline_transitions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_update on "better_supabase"."pipeline_transitions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_delete on "better_supabase"."pipeline_transitions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stage_history";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_select on "better_supabase"."pipeline_stage_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_insert on "better_supabase"."pipeline_stage_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_update on "better_supabase"."pipeline_stage_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_delete on "better_supabase"."pipeline_stage_history" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_092_pipelines.sql
-- better-supabase module: pipelines
-- @bsb-block-data pipelines
-- @bsb-hash sha256:500735436af3b07e078f741b31c4b5cbfb52786b147142e567a3ddae0bcaa2bc
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.pipelines', target_type => 'pipeline', event_prefix => 'pipeline', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('pipelines', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_092_pipelines.sql
-- better-supabase module: pipelines
-- @bsb-block pipelines@1 managed
-- @bsb-hash sha256:74fe2d2691f731c3672aa33ad365a17cef691a7df0af278e50f2c3fa6a1e24ca
-- Tenant-editable pipelines for any registered subject: ordered stages whose categories map to open, success or failure, a stage history with time in stage, board totals per currency and a status mapping that runs through state-machine.
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
    drop policy if exists bsb_tenant_scope on "app_private"."pipelines";
    drop policy if exists bsb_tenant_scope_select on "app_private"."pipelines";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."pipelines";
    drop policy if exists bsb_tenant_scope_update on "app_private"."pipelines";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."pipelines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_select on "app_private"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_update on "app_private"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."pipeline_stages";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_select on "app_private"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_update on "app_private"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."pipeline_transitions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_select on "app_private"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_update on "app_private"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."pipeline_stage_history";
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
-- Pipelines (ADR 0028): tenant-editable stages per subject type, each with
-- a category that maps to a fixed outcome, a stage history and board totals.

create table if not exists "app_private"."pipelines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "scope_id" text,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "rank" text collate "C" not null default 'V',
  "is_default" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique nulls not distinct ("tenant_id", "subject_type", "scope_id", "key")
);
create unique index if not exists pipelines_default_idx on "app_private"."pipelines" ("tenant_id", "subject_type", coalesce("scope_id", ''))
  where "is_default" and "archived_at" is null;
alter table "app_private"."pipelines" enable row level security;
revoke all on "app_private"."pipelines" from public, anon, authenticated;
grant select on "app_private"."pipelines" to authenticated;
grant all on "app_private"."pipelines" to service_role;
drop policy if exists pipelines_read on "app_private"."pipelines";
create policy pipelines_read on "app_private"."pipelines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

create table if not exists "app_private"."pipeline_stages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "pipeline_id" uuid not null references "app_private"."pipelines" ("id") on delete cascade,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "system_key" text,
  "name" text not null check (length("name") between 1 and 200),
  "color" text,
  "rank" text collate "C" not null default 'V',
  "category" text not null,
  "outcome" text not null check ("outcome" in ('open', 'success', 'failure')),
  "probability" smallint check ("probability" >= 0 and "probability" <= 100),
  "rotting_after_days" integer check ("rotting_after_days" > 0),
  "wip_limit" integer check ("wip_limit" > 0),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("pipeline_id", "key")
);
create index if not exists pipeline_stages_pipeline_idx on "app_private"."pipeline_stages" ("pipeline_id", "rank");
alter table "app_private"."pipeline_stages" enable row level security;
revoke all on "app_private"."pipeline_stages" from public, anon, authenticated;
grant select on "app_private"."pipeline_stages" to authenticated;
grant all on "app_private"."pipeline_stages" to service_role;
drop policy if exists pipeline_stages_read on "app_private"."pipeline_stages";
create policy pipeline_stages_read on "app_private"."pipeline_stages"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

create table if not exists "app_private"."pipeline_transitions" (
  "tenant_id" uuid not null,
  "pipeline_id" uuid not null references "app_private"."pipelines" ("id") on delete cascade,
  "from_stage_id" uuid not null references "app_private"."pipeline_stages" ("id") on delete cascade,
  "to_stage_id" uuid not null references "app_private"."pipeline_stages" ("id") on delete cascade,
  primary key ("from_stage_id", "to_stage_id")
);
create index if not exists pipeline_transitions_pipeline_idx on "app_private"."pipeline_transitions" ("pipeline_id");
create index if not exists pipeline_transitions_to_idx on "app_private"."pipeline_transitions" ("to_stage_id");
alter table "app_private"."pipeline_transitions" enable row level security;
revoke all on "app_private"."pipeline_transitions" from public, anon, authenticated;
grant select on "app_private"."pipeline_transitions" to authenticated;
grant all on "app_private"."pipeline_transitions" to service_role;
drop policy if exists pipeline_transitions_read on "app_private"."pipeline_transitions";
create policy pipeline_transitions_read on "app_private"."pipeline_transitions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

create table if not exists "app_private"."pipeline_stage_history" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "pipeline_id" uuid not null,
  "from_stage_id" uuid,
  "to_stage_id" uuid not null,
  "stage_name" text not null,
  "category" text not null,
  "outcome" text not null,
  "amount" bigint,
  "currency" char(3),
  "actor_user_id" uuid,
  "entered_at" timestamptz not null default now(),
  "exited_at" timestamptz
);
create index if not exists pipeline_stage_history_subject_idx on "app_private"."pipeline_stage_history" ("subject_type", "subject_id", "entered_at");
create index if not exists pipeline_stage_history_pipeline_idx on "app_private"."pipeline_stage_history" ("pipeline_id", "entered_at");
create unique index if not exists pipeline_stage_history_open_idx on "app_private"."pipeline_stage_history" ("subject_type", "subject_id") where "exited_at" is null;
alter table "app_private"."pipeline_stage_history" enable row level security;
revoke all on "app_private"."pipeline_stage_history" from public, anon, authenticated;
grant select on "app_private"."pipeline_stage_history" to authenticated;
grant all on "app_private"."pipeline_stage_history" to service_role;
-- A history row is visible to whoever can read its record.
drop policy if exists pipeline_stage_history_read on "app_private"."pipeline_stage_history";
create policy pipeline_stage_history_read on "app_private"."pipeline_stage_history"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));

-- The default pipeline of a subject type in a tenant and scope. The first
-- call creates it from the type's stage template in on.
create or replace function "app_private"."default_pipeline"(tenant uuid, subject_type text, scope_id text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select x."id" into v_id from "app_private"."pipelines" x
  where x."tenant_id" = default_pipeline.tenant
    and x."subject_type" = default_pipeline.subject_type
    and x."scope_id" is not distinct from default_pipeline.scope_id
    and x."archived_at" is null
  order by x."is_default" desc, x."rank" collate "C"
  limit 1;
  if v_id is not null then
    return v_id;
  end if;
  raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  return v_id;
end;
$$;
revoke execute on function "app_private"."default_pipeline"(uuid, text, text) from public, anon, authenticated;
grant execute on function "app_private"."default_pipeline"(uuid, text, text) to service_role;



-- Creates a pipeline (pipeline null) or renames one. The first pipeline of a
-- subject type and scope is its default. Returns its row.
drop function if exists "app_private"."save_pipeline"(uuid, uuid, text, text, text, text, boolean, jsonb);
create or replace function "app_private"."save_pipeline"(tenant uuid, pipeline uuid, subject_type text, key text, name text, scope_id text, is_default boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pipeline uuid := save_pipeline.pipeline;
  v_created boolean := save_pipeline.pipeline is null;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_pipeline.tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if not (save_pipeline.subject_type = any ('{}'::text[])) then
    raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_save"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using save_pipeline.tenant, save_pipeline.pipeline, save_pipeline.subject_type, save_pipeline.key;
    end if;
  end;
  if coalesce(save_pipeline.is_default, false) then
    update "app_private"."pipelines" x set "is_default" = false
    where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type
      and x."scope_id" is not distinct from save_pipeline.scope_id and x."is_default"
      and x."id" is distinct from save_pipeline.pipeline;
  end if;
  begin
    if v_created then
      insert into "app_private"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default", "rank")
      values (save_pipeline.tenant, save_pipeline.subject_type, save_pipeline.scope_id, save_pipeline.key, save_pipeline.name,
        coalesce(save_pipeline.is_default, false) or not exists (
          select 1 from "app_private"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type
            and x."scope_id" is not distinct from save_pipeline.scope_id and x."archived_at" is null),
        case
    when (select max(x."rank" collate "C") from "app_private"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "app_private"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) from '^z*')) = length((select max(x."rank" collate "C") from "app_private"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type)) then (select max(x."rank" collate "C") from "app_private"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) || 'V'
    else left((select max(x."rank" collate "C") from "app_private"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type), length(substring((select max(x."rank" collate "C") from "app_private"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "app_private"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type), length(substring((select max(x."rank" collate "C") from "app_private"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_pipeline;
    else
      update "app_private"."pipelines" x set "key" = save_pipeline.key, "name" = save_pipeline.name,
        "is_default" = coalesce(save_pipeline.is_default, x."is_default"), "updated_at" = now()
      where x."id" = save_pipeline.pipeline and x."tenant_id" = save_pipeline.tenant
        and x."subject_type" = save_pipeline.subject_type;
      if not found then
        raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another pipeline of this type has this key' using errcode = '23505', hint = 'PIPELINE_KEY_TAKEN';
  end;
  if v_created then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_pipeline, v_created;
    end if;
  end;
  return (select to_jsonb(x) from "app_private"."pipelines" x where x."id" = v_pipeline);
end;
$$;
revoke execute on function "app_private"."save_pipeline"(uuid, uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "app_private"."save_pipeline"(uuid, uuid, text, text, text, text, boolean) to authenticated, service_role;

-- Archives a pipeline. Records still in it must move to another first.
create or replace function "app_private"."archive_pipeline"(pipeline uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_subject_type text;
  v_used boolean;
  v_pipeline uuid := archive_pipeline.pipeline;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."subject_type" into v_tenant, v_subject_type
  from "app_private"."pipelines" x where x."id" = archive_pipeline.pipeline and x."archived_at" is null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  v_used := false;
  if v_used then
    raise exception 'records are still in this pipeline; move them first' using errcode = '23503', hint = 'PIPELINE_IN_USE';
  end if;
  update "app_private"."pipelines" x set "archived_at" = now(), "is_default" = false, "updated_at" = now()
  where x."id" = archive_pipeline.pipeline;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."archive_pipeline"(uuid) from public, anon;
grant execute on function "app_private"."archive_pipeline"(uuid) to authenticated, service_role;

-- Creates a stage at the end of a pipeline (stage null) or changes one.
-- The category must be one the subject type declares; it sets the outcome.
create or replace function "app_private"."save_pipeline_stage"(pipeline uuid, stage uuid, key text, name text, category text, probability integer, rotting_after_days integer, wip_limit integer, color text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_subject_type text;
  v_outcome text;
  v_stage uuid := save_pipeline_stage.stage;
  v_pipeline uuid := save_pipeline_stage.pipeline;
  v_used boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."subject_type" into v_tenant, v_subject_type
  from "app_private"."pipelines" x where x."id" = save_pipeline_stage.pipeline and x."archived_at" is null;
  if v_tenant is null then
    raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  if v_outcome is null then
    raise exception 'this subject type has no such category' using errcode = '22023', hint = 'PIPELINE_CATEGORY_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_save"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using save_pipeline_stage.pipeline, save_pipeline_stage.stage, save_pipeline_stage.key, save_pipeline_stage.category;
    end if;
  end;
  begin
    if v_stage is null then
      insert into "app_private"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "probability", "rotting_after_days", "wip_limit", "color", "rank")
      values (v_tenant, save_pipeline_stage.pipeline, save_pipeline_stage.key, save_pipeline_stage.name, save_pipeline_stage.category, v_outcome, save_pipeline_stage.probability, save_pipeline_stage.rotting_after_days, save_pipeline_stage.wip_limit, save_pipeline_stage.color,
        case
    when (select max(x."rank" collate "C") from "app_private"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "app_private"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*')) = length((select max(x."rank" collate "C") from "app_private"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline)) then (select max(x."rank" collate "C") from "app_private"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) || 'V'
    else left((select max(x."rank" collate "C") from "app_private"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline), length(substring((select max(x."rank" collate "C") from "app_private"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "app_private"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline), length(substring((select max(x."rank" collate "C") from "app_private"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_stage;
    else
      -- A stage holding records keeps its outcome, so won stays won.
      if exists (select 1 from "app_private"."pipeline_stages" x where x."id" = v_stage and x."outcome" <> v_outcome) then
        v_used := false;
        if v_used then
          raise exception 'records are in this stage; its outcome can''t change' using errcode = '23503', hint = 'PIPELINE_STAGE_IN_USE';
        end if;
      end if;
      update "app_private"."pipeline_stages" x set "key" = save_pipeline_stage.key, "name" = save_pipeline_stage.name, "category" = save_pipeline_stage.category, "outcome" = v_outcome, "probability" = save_pipeline_stage.probability, "rotting_after_days" = save_pipeline_stage.rotting_after_days, "wip_limit" = save_pipeline_stage.wip_limit, "color" = save_pipeline_stage.color, "updated_at" = now()
      where x."id" = v_stage and x."pipeline_id" = save_pipeline_stage.pipeline;
      if not found then
        raise exception 'stage not found' using errcode = 'P0002', hint = 'PIPELINE_STAGE_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another stage of this pipeline has this key' using errcode = '23505', hint = 'PIPELINE_STAGE_KEY_TAKEN';
  end;
  if save_pipeline_stage.stage is null then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_stage;
    end if;
  end;
  return (select to_jsonb(x) from "app_private"."pipeline_stages" x where x."id" = v_stage);
end;
$$;
revoke execute on function "app_private"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text) from public, anon;
grant execute on function "app_private"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text) to authenticated, service_role;

-- Moves a stage to a rank key the client computed with rankBetween.
create or replace function "app_private"."rank_pipeline_stage"(stage uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "app_private"."pipeline_stages" x where x."id" = rank_pipeline_stage.stage;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if rank_pipeline_stage.rank is null or rank_pipeline_stage.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'PIPELINE_RANK_INVALID';
  end if;
  update "app_private"."pipeline_stages" x set "rank" = rank_pipeline_stage.rank, "updated_at" = now()
  where x."id" = rank_pipeline_stage.stage;
  return true;
end;
$$;
revoke execute on function "app_private"."rank_pipeline_stage"(uuid, text) from public, anon;
grant execute on function "app_private"."rank_pipeline_stage"(uuid, text) to authenticated, service_role;

-- Archives an empty stage. The last open stage of a pipeline stays.
create or replace function "app_private"."archive_pipeline_stage"(stage uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_pipeline uuid;
  v_subject_type text;
  v_outcome text;
  v_used boolean;
  v_stage uuid := archive_pipeline_stage.stage;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."pipeline_id", x."outcome", y."subject_type"
    into v_tenant, v_pipeline, v_outcome, v_subject_type
  from "app_private"."pipeline_stages" x join "app_private"."pipelines" y on y."id" = x."pipeline_id"
  where x."id" = archive_pipeline_stage.stage and x."archived_at" is null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  v_used := false;
  if v_used then
    raise exception 'records are in this stage; move them first' using errcode = '23503', hint = 'PIPELINE_STAGE_IN_USE';
  end if;
  if v_outcome = 'open' and not exists (
    select 1 from "app_private"."pipeline_stages" x where x."pipeline_id" = v_pipeline and x."outcome" = 'open'
      and x."archived_at" is null and x."id" <> archive_pipeline_stage.stage
  ) then
    raise exception 'a pipeline keeps at least one open stage' using errcode = '23514', hint = 'PIPELINE_LAST_OPEN_STAGE';
  end if;
  update "app_private"."pipeline_stages" x set "archived_at" = now(), "updated_at" = now() where x."id" = archive_pipeline_stage.stage;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."archive_pipeline_stage"(uuid) from public, anon;
grant execute on function "app_private"."archive_pipeline_stage"(uuid) to authenticated, service_role;

-- Replaces the allowed stage changes of a pipeline. An empty list allows
-- every change; pairs is a list of { "from": stage id, "to": stage id }.
create or replace function "app_private"."set_pipeline_transitions"(pipeline uuid, pairs jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "app_private"."pipelines" x where x."id" = set_pipeline_transitions.pipeline;
  if v_tenant is null then
    raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(set_pipeline_transitions.pairs, '[]')) <> 'array' then
    raise exception 'pairs must be a list of { from, to } stage ids' using errcode = '22023', hint = 'PIPELINE_TRANSITIONS_INVALID';
  end if;
  delete from "app_private"."pipeline_transitions" x where x."pipeline_id" = set_pipeline_transitions.pipeline;
  insert into "app_private"."pipeline_transitions" ("tenant_id", "pipeline_id", "from_stage_id", "to_stage_id")
  select v_tenant, set_pipeline_transitions.pipeline, (pair ->> 'from')::uuid, (pair ->> 'to')::uuid
  from jsonb_array_elements(coalesce(set_pipeline_transitions.pairs, '[]')) pair
  on conflict do nothing;
  get diagnostics v_count = row_count;
  if exists (
    select 1 from "app_private"."pipeline_transitions" x
    left join "app_private"."pipeline_stages" a on a."id" = x."from_stage_id" and a."pipeline_id" = x."pipeline_id"
    left join "app_private"."pipeline_stages" b on b."id" = x."to_stage_id" and b."pipeline_id" = x."pipeline_id"
    where x."pipeline_id" = set_pipeline_transitions.pipeline and (a."id" is null or b."id" is null)
  ) then
    raise exception 'every stage must belong to the pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITIONS_INVALID';
  end if;
  return v_count;
end;
$$;
revoke execute on function "app_private"."set_pipeline_transitions"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."set_pipeline_transitions"(uuid, jsonb) to authenticated, service_role;

-- One entry per active stage, in board order: the count of records the
-- caller can see, and per currency the amount and the amount weighted by
-- probability. Amounts are text so bigint minor units survive JSON.
create or replace function "app_private"."pipeline_board"(subject_type text, pipeline uuid, owner uuid default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
end;
$$;
revoke execute on function "app_private"."pipeline_board"(text, uuid, uuid) from public, anon;
grant execute on function "app_private"."pipeline_board"(text, uuid, uuid) to authenticated, service_role;

-- Per stage, between since and until: how many records entered it, how long
-- the ones that left stayed on average, and the share that went on to a
-- success stage. Reads the history the caller can see.
create or replace function "app_private"."pipeline_stats"(pipeline uuid, since timestamptz, until timestamptz)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with window_rows as (
    select * from "app_private"."pipeline_stage_history" h
    where h."pipeline_id" = pipeline_stats.pipeline
      and h."entered_at" >= pipeline_stats.since and h."entered_at" < pipeline_stats.until
  ),
  per_stage as (
    select w."to_stage_id" as stage_id, count(*) as entered,
      avg(extract(epoch from (w."exited_at" - w."entered_at"))) filter (where w."exited_at" is not null) as avg_seconds
    from window_rows w group by w."to_stage_id"
  ),
  closed as (
    select count(*) filter (where w."outcome" = 'success') as won,
      count(*) filter (where w."outcome" = 'failure') as lost
    from window_rows w
  )
  select jsonb_build_object(
    'won', closed.won,
    'lost', closed.lost,
    'winRate', case when closed.won + closed.lost = 0 then null else round(closed.won::numeric / (closed.won + closed.lost), 4) end,
    'stages', coalesce((
      select jsonb_agg(jsonb_build_object('stageId', st."id", 'key', st."key", 'entered', coalesce(ps.entered, 0), 'averageSeconds', round(ps.avg_seconds)) order by st."rank" collate "C")
      from "app_private"."pipeline_stages" st left join per_stage ps on ps.stage_id = st."id"
      where st."pipeline_id" = pipeline_stats.pipeline
    ), '[]'::jsonb)
  )
  from closed;
$$;
revoke execute on function "app_private"."pipeline_stats"(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function "app_private"."pipeline_stats"(uuid, timestamptz, timestamptz) to authenticated, service_role;

-- The open records of a pipeline the caller can see, oldest entry first:
-- when each entered its stage and whether it sits longer than the stage's
-- rotting limit.
create or replace function "app_private"."pipeline_health"(pipeline uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subjectType', h."subject_type", 'subjectId', h."subject_id", 'stageId', h."to_stage_id",
    'enteredAt', h."entered_at",
    'daysInStage', (extract(epoch from now() - h."entered_at") / 86400)::integer,
    'rotting', st."rotting_after_days" is not null and now() - h."entered_at" > make_interval(days => st."rotting_after_days")
  ) order by h."entered_at"), '[]'::jsonb)
  from "app_private"."pipeline_stage_history" h
  join "app_private"."pipeline_stages" st on st."id" = h."to_stage_id"
  where h."pipeline_id" = pipeline_health.pipeline and h."exited_at" is null and h."outcome" = 'open';
$$;
revoke execute on function "app_private"."pipeline_health"(uuid) from public, anon;
grant execute on function "app_private"."pipeline_health"(uuid) to authenticated, service_role;

-- The tenant's active pipelines of a subject type, each with its active
-- stages in board order.
create or replace function "app_private"."list_pipelines"(tenant uuid, subject_type text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "app_private"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) order by x."rank" collate "C"), '[]'::jsonb)
  from "app_private"."pipelines" x
  where x."tenant_id" = list_pipelines.tenant
    and x."subject_type" = list_pipelines.subject_type
    and x."archived_at" is null;
$$;
revoke execute on function "app_private"."list_pipelines"(uuid, text) from public, anon;
grant execute on function "app_private"."list_pipelines"(uuid, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."pipelines";
drop policy if exists bsb_tenant_scope_select on "app_private"."pipelines";
create policy bsb_tenant_scope_select on "app_private"."pipelines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."pipelines";
create policy bsb_tenant_scope_insert on "app_private"."pipelines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."pipelines";
create policy bsb_tenant_scope_update on "app_private"."pipelines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."pipelines";
create policy bsb_tenant_scope_delete on "app_private"."pipelines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."pipeline_stages";
drop policy if exists bsb_tenant_scope_select on "app_private"."pipeline_stages";
create policy bsb_tenant_scope_select on "app_private"."pipeline_stages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."pipeline_stages";
create policy bsb_tenant_scope_insert on "app_private"."pipeline_stages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."pipeline_stages";
create policy bsb_tenant_scope_update on "app_private"."pipeline_stages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."pipeline_stages";
create policy bsb_tenant_scope_delete on "app_private"."pipeline_stages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."pipeline_transitions";
drop policy if exists bsb_tenant_scope_select on "app_private"."pipeline_transitions";
create policy bsb_tenant_scope_select on "app_private"."pipeline_transitions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."pipeline_transitions";
create policy bsb_tenant_scope_insert on "app_private"."pipeline_transitions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."pipeline_transitions";
create policy bsb_tenant_scope_update on "app_private"."pipeline_transitions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."pipeline_transitions";
create policy bsb_tenant_scope_delete on "app_private"."pipeline_transitions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."pipeline_stage_history";
drop policy if exists bsb_tenant_scope_select on "app_private"."pipeline_stage_history";
create policy bsb_tenant_scope_select on "app_private"."pipeline_stage_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."pipeline_stage_history";
create policy bsb_tenant_scope_insert on "app_private"."pipeline_stage_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."pipeline_stage_history";
create policy bsb_tenant_scope_update on "app_private"."pipeline_stage_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."pipeline_stage_history";
create policy bsb_tenant_scope_delete on "app_private"."pipeline_stage_history" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_092_pipelines.sql
-- better-supabase module: pipelines
-- @bsb-block-data pipelines
-- @bsb-hash sha256:afbc833c2019b6deab1e41862c83cefb962a135052476adab19c5b7d64bafdad
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('pipelines', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_092_pipelines.sql
-- better-supabase module: pipelines
-- @bsb-block pipelines@1 managed
-- @bsb-hash sha256:b495a3af0669d4f8e6109abc9a77139cc725721e385c7519472e01ab46d6681c
-- Tenant-editable pipelines for any registered subject: ordered stages whose categories map to open, success or failure, a stage history with time in stage, board totals per currency and a status mapping that runs through state-machine.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipelines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stages";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_transitions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stage_history";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Pipelines (ADR 0028): tenant-editable stages per subject type, each with
-- a category that maps to a fixed outcome, a stage history and board totals.

create table if not exists "better_supabase"."pipelines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "scope_id" text,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "rank" text collate "C" not null default 'V',
  "is_default" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique nulls not distinct ("tenant_id", "subject_type", "scope_id", "key")
);
create unique index if not exists pipelines_default_idx on "better_supabase"."pipelines" ("tenant_id", "subject_type", coalesce("scope_id", ''))
  where "is_default" and "archived_at" is null;
alter table "better_supabase"."pipelines" enable row level security;
revoke all on "better_supabase"."pipelines" from public, anon, authenticated;
grant select on "better_supabase"."pipelines" to authenticated;
grant all on "better_supabase"."pipelines" to service_role;
drop policy if exists pipelines_read on "better_supabase"."pipelines";
create policy pipelines_read on "better_supabase"."pipelines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

create table if not exists "better_supabase"."pipeline_stages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "pipeline_id" uuid not null references "better_supabase"."pipelines" ("id") on delete cascade,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "system_key" text,
  "name" text not null check (length("name") between 1 and 200),
  "color" text,
  "rank" text collate "C" not null default 'V',
  "category" text not null,
  "outcome" text not null check ("outcome" in ('open', 'success', 'failure')),
  "probability" smallint check ("probability" >= 0 and "probability" <= 100),
  "rotting_after_days" integer check ("rotting_after_days" > 0),
  "wip_limit" integer check ("wip_limit" > 0),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("pipeline_id", "key")
);
create index if not exists pipeline_stages_pipeline_idx on "better_supabase"."pipeline_stages" ("pipeline_id", "rank");
alter table "better_supabase"."pipeline_stages" enable row level security;
revoke all on "better_supabase"."pipeline_stages" from public, anon, authenticated;
grant select on "better_supabase"."pipeline_stages" to authenticated;
grant all on "better_supabase"."pipeline_stages" to service_role;
drop policy if exists pipeline_stages_read on "better_supabase"."pipeline_stages";
create policy pipeline_stages_read on "better_supabase"."pipeline_stages"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

create table if not exists "better_supabase"."pipeline_transitions" (
  "tenant_id" uuid not null,
  "pipeline_id" uuid not null references "better_supabase"."pipelines" ("id") on delete cascade,
  "from_stage_id" uuid not null references "better_supabase"."pipeline_stages" ("id") on delete cascade,
  "to_stage_id" uuid not null references "better_supabase"."pipeline_stages" ("id") on delete cascade,
  primary key ("from_stage_id", "to_stage_id")
);
create index if not exists pipeline_transitions_pipeline_idx on "better_supabase"."pipeline_transitions" ("pipeline_id");
create index if not exists pipeline_transitions_to_idx on "better_supabase"."pipeline_transitions" ("to_stage_id");
alter table "better_supabase"."pipeline_transitions" enable row level security;
revoke all on "better_supabase"."pipeline_transitions" from public, anon, authenticated;
grant select on "better_supabase"."pipeline_transitions" to authenticated;
grant all on "better_supabase"."pipeline_transitions" to service_role;
drop policy if exists pipeline_transitions_read on "better_supabase"."pipeline_transitions";
create policy pipeline_transitions_read on "better_supabase"."pipeline_transitions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

create table if not exists "better_supabase"."pipeline_stage_history" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "pipeline_id" uuid not null,
  "from_stage_id" uuid,
  "to_stage_id" uuid not null,
  "stage_name" text not null,
  "category" text not null,
  "outcome" text not null,
  "amount" bigint,
  "currency" char(3),
  "actor_user_id" uuid,
  "entered_at" timestamptz not null default now(),
  "exited_at" timestamptz
);
create index if not exists pipeline_stage_history_subject_idx on "better_supabase"."pipeline_stage_history" ("subject_type", "subject_id", "entered_at");
create index if not exists pipeline_stage_history_pipeline_idx on "better_supabase"."pipeline_stage_history" ("pipeline_id", "entered_at");
create unique index if not exists pipeline_stage_history_open_idx on "better_supabase"."pipeline_stage_history" ("subject_type", "subject_id") where "exited_at" is null;
alter table "better_supabase"."pipeline_stage_history" enable row level security;
revoke all on "better_supabase"."pipeline_stage_history" from public, anon, authenticated;
grant select on "better_supabase"."pipeline_stage_history" to authenticated;
grant all on "better_supabase"."pipeline_stage_history" to service_role;
-- A history row is visible to whoever can read its record.
drop policy if exists pipeline_stage_history_read on "better_supabase"."pipeline_stage_history";
create policy pipeline_stage_history_read on "better_supabase"."pipeline_stage_history"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));

-- The default pipeline of a subject type in a tenant and scope. The first
-- call creates it from the type's stage template in on.
create or replace function "better_supabase"."default_pipeline"(tenant uuid, subject_type text, scope_id text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select x."id" into v_id from "better_supabase"."pipelines" x
  where x."tenant_id" = default_pipeline.tenant
    and x."subject_type" = default_pipeline.subject_type
    and x."scope_id" is not distinct from default_pipeline.scope_id
    and x."archived_at" is null
  order by x."is_default" desc, x."rank" collate "C"
  limit 1;
  if v_id is not null then
    return v_id;
  end if;
  raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."default_pipeline"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."default_pipeline"(uuid, text, text) to service_role;



-- Creates a pipeline (pipeline null) or renames one. The first pipeline of a
-- subject type and scope is its default. Returns its row.
drop function if exists "better_supabase"."save_pipeline"(uuid, uuid, text, text, text, text, boolean, jsonb);
create or replace function "better_supabase"."save_pipeline"(tenant uuid, pipeline uuid, subject_type text, key text, name text, scope_id text, is_default boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pipeline uuid := save_pipeline.pipeline;
  v_created boolean := save_pipeline.pipeline is null;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_pipeline.tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if not (save_pipeline.subject_type = any ('{}'::text[])) then
    raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_save"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using save_pipeline.tenant, save_pipeline.pipeline, save_pipeline.subject_type, save_pipeline.key;
    end if;
  end;
  if coalesce(save_pipeline.is_default, false) then
    update "better_supabase"."pipelines" x set "is_default" = false
    where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type
      and x."scope_id" is not distinct from save_pipeline.scope_id and x."is_default"
      and x."id" is distinct from save_pipeline.pipeline;
  end if;
  begin
    if v_created then
      insert into "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default", "rank")
      values (save_pipeline.tenant, save_pipeline.subject_type, save_pipeline.scope_id, save_pipeline.key, save_pipeline.name,
        coalesce(save_pipeline.is_default, false) or not exists (
          select 1 from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type
            and x."scope_id" is not distinct from save_pipeline.scope_id and x."archived_at" is null),
        case
    when (select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) from '^z*')) = length((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type)) then (select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) || 'V'
    else left((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_pipeline;
    else
      update "better_supabase"."pipelines" x set "key" = save_pipeline.key, "name" = save_pipeline.name,
        "is_default" = coalesce(save_pipeline.is_default, x."is_default"), "updated_at" = now()
      where x."id" = save_pipeline.pipeline and x."tenant_id" = save_pipeline.tenant
        and x."subject_type" = save_pipeline.subject_type;
      if not found then
        raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another pipeline of this type has this key' using errcode = '23505', hint = 'PIPELINE_KEY_TAKEN';
  end;
  if v_created then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_pipeline, v_created;
    end if;
  end;
  return (select to_jsonb(x) from "better_supabase"."pipelines" x where x."id" = v_pipeline);
end;
$$;
revoke execute on function "better_supabase"."save_pipeline"(uuid, uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."save_pipeline"(uuid, uuid, text, text, text, text, boolean) to authenticated, service_role;

-- Archives a pipeline. Records still in it must move to another first.
create or replace function "better_supabase"."archive_pipeline"(pipeline uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_subject_type text;
  v_used boolean;
  v_pipeline uuid := archive_pipeline.pipeline;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."subject_type" into v_tenant, v_subject_type
  from "better_supabase"."pipelines" x where x."id" = archive_pipeline.pipeline and x."archived_at" is null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  v_used := false;
  if v_used then
    raise exception 'records are still in this pipeline; move them first' using errcode = '23503', hint = 'PIPELINE_IN_USE';
  end if;
  update "better_supabase"."pipelines" x set "archived_at" = now(), "is_default" = false, "updated_at" = now()
  where x."id" = archive_pipeline.pipeline;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_pipeline"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_pipeline"(uuid) to authenticated, service_role;

-- Creates a stage at the end of a pipeline (stage null) or changes one.
-- The category must be one the subject type declares; it sets the outcome.
create or replace function "better_supabase"."save_pipeline_stage"(pipeline uuid, stage uuid, key text, name text, category text, probability integer, rotting_after_days integer, wip_limit integer, color text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_subject_type text;
  v_outcome text;
  v_stage uuid := save_pipeline_stage.stage;
  v_pipeline uuid := save_pipeline_stage.pipeline;
  v_used boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."subject_type" into v_tenant, v_subject_type
  from "better_supabase"."pipelines" x where x."id" = save_pipeline_stage.pipeline and x."archived_at" is null;
  if v_tenant is null then
    raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  if v_outcome is null then
    raise exception 'this subject type has no such category' using errcode = '22023', hint = 'PIPELINE_CATEGORY_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_save"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using save_pipeline_stage.pipeline, save_pipeline_stage.stage, save_pipeline_stage.key, save_pipeline_stage.category;
    end if;
  end;
  begin
    if v_stage is null then
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "probability", "rotting_after_days", "wip_limit", "color", "rank")
      values (v_tenant, save_pipeline_stage.pipeline, save_pipeline_stage.key, save_pipeline_stage.name, save_pipeline_stage.category, v_outcome, save_pipeline_stage.probability, save_pipeline_stage.rotting_after_days, save_pipeline_stage.wip_limit, save_pipeline_stage.color,
        case
    when (select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*')) = length((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline)) then (select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) || 'V'
    else left((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_stage;
    else
      -- A stage holding records keeps its outcome, so won stays won.
      if exists (select 1 from "better_supabase"."pipeline_stages" x where x."id" = v_stage and x."outcome" <> v_outcome) then
        v_used := false;
        if v_used then
          raise exception 'records are in this stage; its outcome can''t change' using errcode = '23503', hint = 'PIPELINE_STAGE_IN_USE';
        end if;
      end if;
      update "better_supabase"."pipeline_stages" x set "key" = save_pipeline_stage.key, "name" = save_pipeline_stage.name, "category" = save_pipeline_stage.category, "outcome" = v_outcome, "probability" = save_pipeline_stage.probability, "rotting_after_days" = save_pipeline_stage.rotting_after_days, "wip_limit" = save_pipeline_stage.wip_limit, "color" = save_pipeline_stage.color, "updated_at" = now()
      where x."id" = v_stage and x."pipeline_id" = save_pipeline_stage.pipeline;
      if not found then
        raise exception 'stage not found' using errcode = 'P0002', hint = 'PIPELINE_STAGE_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another stage of this pipeline has this key' using errcode = '23505', hint = 'PIPELINE_STAGE_KEY_TAKEN';
  end;
  if save_pipeline_stage.stage is null then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_stage;
    end if;
  end;
  return (select to_jsonb(x) from "better_supabase"."pipeline_stages" x where x."id" = v_stage);
end;
$$;
revoke execute on function "better_supabase"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text) from public, anon;
grant execute on function "better_supabase"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text) to authenticated, service_role;

-- Moves a stage to a rank key the client computed with rankBetween.
create or replace function "better_supabase"."rank_pipeline_stage"(stage uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."pipeline_stages" x where x."id" = rank_pipeline_stage.stage;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if rank_pipeline_stage.rank is null or rank_pipeline_stage.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'PIPELINE_RANK_INVALID';
  end if;
  update "better_supabase"."pipeline_stages" x set "rank" = rank_pipeline_stage.rank, "updated_at" = now()
  where x."id" = rank_pipeline_stage.stage;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_pipeline_stage"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_pipeline_stage"(uuid, text) to authenticated, service_role;

-- Archives an empty stage. The last open stage of a pipeline stays.
create or replace function "better_supabase"."archive_pipeline_stage"(stage uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_pipeline uuid;
  v_subject_type text;
  v_outcome text;
  v_used boolean;
  v_stage uuid := archive_pipeline_stage.stage;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."pipeline_id", x."outcome", y."subject_type"
    into v_tenant, v_pipeline, v_outcome, v_subject_type
  from "better_supabase"."pipeline_stages" x join "better_supabase"."pipelines" y on y."id" = x."pipeline_id"
  where x."id" = archive_pipeline_stage.stage and x."archived_at" is null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  v_used := false;
  if v_used then
    raise exception 'records are in this stage; move them first' using errcode = '23503', hint = 'PIPELINE_STAGE_IN_USE';
  end if;
  if v_outcome = 'open' and not exists (
    select 1 from "better_supabase"."pipeline_stages" x where x."pipeline_id" = v_pipeline and x."outcome" = 'open'
      and x."archived_at" is null and x."id" <> archive_pipeline_stage.stage
  ) then
    raise exception 'a pipeline keeps at least one open stage' using errcode = '23514', hint = 'PIPELINE_LAST_OPEN_STAGE';
  end if;
  update "better_supabase"."pipeline_stages" x set "archived_at" = now(), "updated_at" = now() where x."id" = archive_pipeline_stage.stage;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_pipeline_stage"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_pipeline_stage"(uuid) to authenticated, service_role;

-- Replaces the allowed stage changes of a pipeline. An empty list allows
-- every change; pairs is a list of { "from": stage id, "to": stage id }.
create or replace function "better_supabase"."set_pipeline_transitions"(pipeline uuid, pairs jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."pipelines" x where x."id" = set_pipeline_transitions.pipeline;
  if v_tenant is null then
    raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(set_pipeline_transitions.pairs, '[]')) <> 'array' then
    raise exception 'pairs must be a list of { from, to } stage ids' using errcode = '22023', hint = 'PIPELINE_TRANSITIONS_INVALID';
  end if;
  delete from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = set_pipeline_transitions.pipeline;
  insert into "better_supabase"."pipeline_transitions" ("tenant_id", "pipeline_id", "from_stage_id", "to_stage_id")
  select v_tenant, set_pipeline_transitions.pipeline, (pair ->> 'from')::uuid, (pair ->> 'to')::uuid
  from jsonb_array_elements(coalesce(set_pipeline_transitions.pairs, '[]')) pair
  on conflict do nothing;
  get diagnostics v_count = row_count;
  if exists (
    select 1 from "better_supabase"."pipeline_transitions" x
    left join "better_supabase"."pipeline_stages" a on a."id" = x."from_stage_id" and a."pipeline_id" = x."pipeline_id"
    left join "better_supabase"."pipeline_stages" b on b."id" = x."to_stage_id" and b."pipeline_id" = x."pipeline_id"
    where x."pipeline_id" = set_pipeline_transitions.pipeline and (a."id" is null or b."id" is null)
  ) then
    raise exception 'every stage must belong to the pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITIONS_INVALID';
  end if;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_pipeline_transitions"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_pipeline_transitions"(uuid, jsonb) to authenticated, service_role;

-- One entry per active stage, in board order: the count of records the
-- caller can see, and per currency the amount and the amount weighted by
-- probability. Amounts are text so bigint minor units survive JSON.
create or replace function "better_supabase"."pipeline_board"(subject_type text, pipeline uuid, owner uuid default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."pipeline_board"(text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."pipeline_board"(text, uuid, uuid) to authenticated, service_role;

-- Per stage, between since and until: how many records entered it, how long
-- the ones that left stayed on average, and the share that went on to a
-- success stage. Reads the history the caller can see.
create or replace function "better_supabase"."pipeline_stats"(pipeline uuid, since timestamptz, until timestamptz)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with window_rows as (
    select * from "better_supabase"."pipeline_stage_history" h
    where h."pipeline_id" = pipeline_stats.pipeline
      and h."entered_at" >= pipeline_stats.since and h."entered_at" < pipeline_stats.until
  ),
  per_stage as (
    select w."to_stage_id" as stage_id, count(*) as entered,
      avg(extract(epoch from (w."exited_at" - w."entered_at"))) filter (where w."exited_at" is not null) as avg_seconds
    from window_rows w group by w."to_stage_id"
  ),
  closed as (
    select count(*) filter (where w."outcome" = 'success') as won,
      count(*) filter (where w."outcome" = 'failure') as lost
    from window_rows w
  )
  select jsonb_build_object(
    'won', closed.won,
    'lost', closed.lost,
    'winRate', case when closed.won + closed.lost = 0 then null else round(closed.won::numeric / (closed.won + closed.lost), 4) end,
    'stages', coalesce((
      select jsonb_agg(jsonb_build_object('stageId', st."id", 'key', st."key", 'entered', coalesce(ps.entered, 0), 'averageSeconds', round(ps.avg_seconds)) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st left join per_stage ps on ps.stage_id = st."id"
      where st."pipeline_id" = pipeline_stats.pipeline
    ), '[]'::jsonb)
  )
  from closed;
$$;
revoke execute on function "better_supabase"."pipeline_stats"(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."pipeline_stats"(uuid, timestamptz, timestamptz) to authenticated, service_role;

-- The open records of a pipeline the caller can see, oldest entry first:
-- when each entered its stage and whether it sits longer than the stage's
-- rotting limit.
create or replace function "better_supabase"."pipeline_health"(pipeline uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subjectType', h."subject_type", 'subjectId', h."subject_id", 'stageId', h."to_stage_id",
    'enteredAt', h."entered_at",
    'daysInStage', (extract(epoch from now() - h."entered_at") / 86400)::integer,
    'rotting', st."rotting_after_days" is not null and now() - h."entered_at" > make_interval(days => st."rotting_after_days")
  ) order by h."entered_at"), '[]'::jsonb)
  from "better_supabase"."pipeline_stage_history" h
  join "better_supabase"."pipeline_stages" st on st."id" = h."to_stage_id"
  where h."pipeline_id" = pipeline_health.pipeline and h."exited_at" is null and h."outcome" = 'open';
$$;
revoke execute on function "better_supabase"."pipeline_health"(uuid) from public, anon;
grant execute on function "better_supabase"."pipeline_health"(uuid) to authenticated, service_role;

-- The tenant's active pipelines of a subject type, each with its active
-- stages in board order.
create or replace function "better_supabase"."list_pipelines"(tenant uuid, subject_type text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) order by x."rank" collate "C"), '[]'::jsonb)
  from "better_supabase"."pipelines" x
  where x."tenant_id" = list_pipelines.tenant
    and x."subject_type" = list_pipelines.subject_type
    and x."archived_at" is null;
$$;
revoke execute on function "better_supabase"."list_pipelines"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_pipelines"(uuid, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."pipelines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipelines";
create policy bsb_tenant_scope_select on "better_supabase"."pipelines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipelines";
create policy bsb_tenant_scope_insert on "better_supabase"."pipelines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipelines";
create policy bsb_tenant_scope_update on "better_supabase"."pipelines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipelines";
create policy bsb_tenant_scope_delete on "better_supabase"."pipelines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stages";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_select on "better_supabase"."pipeline_stages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_insert on "better_supabase"."pipeline_stages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_update on "better_supabase"."pipeline_stages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_delete on "better_supabase"."pipeline_stages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_transitions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_select on "better_supabase"."pipeline_transitions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_insert on "better_supabase"."pipeline_transitions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_update on "better_supabase"."pipeline_transitions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_delete on "better_supabase"."pipeline_transitions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stage_history";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_select on "better_supabase"."pipeline_stage_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_insert on "better_supabase"."pipeline_stage_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_update on "better_supabase"."pipeline_stage_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_delete on "better_supabase"."pipeline_stage_history" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.pipelines.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."save_pipeline"(uuid, uuid, text, text, text, text, boolean, jsonb);

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

create or replace function "api"."default_pipeline"(tenant uuid, subject_type text, scope_id text)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."default_pipeline"($1, $2, $3) $$;
revoke execute on function "api"."default_pipeline"(uuid, text, text) from public, anon, authenticated;
grant execute on function "api"."default_pipeline"(uuid, text, text) to service_role;

create or replace function "api"."save_pipeline"(tenant uuid, pipeline uuid, subject_type text, key text, name text, scope_id text, is_default boolean)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_pipeline"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."save_pipeline"(uuid, uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "api"."save_pipeline"(uuid, uuid, text, text, text, text, boolean) to authenticated, service_role;

create or replace function "api"."archive_pipeline"(pipeline uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_pipeline"($1) $$;
revoke execute on function "api"."archive_pipeline"(uuid) from public, anon;
grant execute on function "api"."archive_pipeline"(uuid) to authenticated, service_role;

create or replace function "api"."save_pipeline_stage"(pipeline uuid, stage uuid, key text, name text, category text, probability integer, rotting_after_days integer, wip_limit integer, color text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_pipeline_stage"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text) from public, anon;
grant execute on function "api"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text) to authenticated, service_role;

create or replace function "api"."rank_pipeline_stage"(stage uuid, rank text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rank_pipeline_stage"($1, $2) $$;
revoke execute on function "api"."rank_pipeline_stage"(uuid, text) from public, anon;
grant execute on function "api"."rank_pipeline_stage"(uuid, text) to authenticated, service_role;

create or replace function "api"."archive_pipeline_stage"(stage uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_pipeline_stage"($1) $$;
revoke execute on function "api"."archive_pipeline_stage"(uuid) from public, anon;
grant execute on function "api"."archive_pipeline_stage"(uuid) to authenticated, service_role;

create or replace function "api"."set_pipeline_transitions"(pipeline uuid, pairs jsonb)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_pipeline_transitions"($1, $2) $$;
revoke execute on function "api"."set_pipeline_transitions"(uuid, jsonb) from public, anon;
grant execute on function "api"."set_pipeline_transitions"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."pipeline_board"(subject_type text, pipeline uuid, owner uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."pipeline_board"($1, $2, $3) $$;
revoke execute on function "api"."pipeline_board"(text, uuid, uuid) from public, anon;
grant execute on function "api"."pipeline_board"(text, uuid, uuid) to authenticated, service_role;

create or replace function "api"."pipeline_stats"(pipeline uuid, since timestamptz, until timestamptz)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."pipeline_stats"($1, $2, $3) $$;
revoke execute on function "api"."pipeline_stats"(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function "api"."pipeline_stats"(uuid, timestamptz, timestamptz) to authenticated, service_role;

create or replace function "api"."pipeline_health"(pipeline uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."pipeline_health"($1) $$;
revoke execute on function "api"."pipeline_health"(uuid) from public, anon;
grant execute on function "api"."pipeline_health"(uuid) to authenticated, service_role;

create or replace function "api"."list_pipelines"(tenant uuid, subject_type text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_pipelines"($1, $2) $$;
revoke execute on function "api"."list_pipelines"(uuid, text) from public, anon;
grant execute on function "api"."list_pipelines"(uuid, text) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_092_pipelines.sql
-- better-supabase module: pipelines
-- @bsb-block-data pipelines
-- @bsb-hash sha256:afbc833c2019b6deab1e41862c83cefb962a135052476adab19c5b7d64bafdad
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('pipelines', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_092_pipelines.sql
-- better-supabase module: pipelines
-- @bsb-block pipelines@1 managed
-- @bsb-hash sha256:27c7b61547d5460e5ec4c9722af8f1310684fa992323d4ea1642e0137cd21952
-- Tenant-editable pipelines for any registered subject: ordered stages whose categories map to open, success or failure, a stage history with time in stage, board totals per currency and a status mapping that runs through state-machine.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipelines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stages";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_transitions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stage_history";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Pipelines (ADR 0028): tenant-editable stages per subject type, each with
-- a category that maps to a fixed outcome, a stage history and board totals.

-- better_supabase.pipelines is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."pipelines" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."pipelines" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."pipelines" add column if not exists "subject_type" text;
alter table "better_supabase"."pipelines" add column if not exists "scope_id" text;
alter table "better_supabase"."pipelines" add column if not exists "key" text check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$');
alter table "better_supabase"."pipelines" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."pipelines" add column if not exists "rank" text collate "C" not null default 'V';
alter table "better_supabase"."pipelines" add column if not exists "is_default" boolean not null default false;
alter table "better_supabase"."pipelines" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."pipelines" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."pipelines" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_pipelines_key_key" on "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key") nulls not distinct;
create unique index if not exists pipelines_default_idx on "better_supabase"."pipelines" ("tenant_id", "subject_type", coalesce("scope_id", ''))
  where "is_default" and "archived_at" is null;
alter table "better_supabase"."pipelines" enable row level security;
grant select on "better_supabase"."pipelines" to authenticated;
grant all on "better_supabase"."pipelines" to service_role;
drop policy if exists bsb_pipelines_select on "better_supabase"."pipelines";
create policy bsb_pipelines_select on "better_supabase"."pipelines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

-- better_supabase.pipeline_stages is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."pipeline_stages" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."pipeline_stages" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."pipeline_stages" add column if not exists "pipeline_id" uuid references "better_supabase"."pipelines" ("id") on delete cascade;
alter table "better_supabase"."pipeline_stages" add column if not exists "key" text check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$');
alter table "better_supabase"."pipeline_stages" add column if not exists "system_key" text;
alter table "better_supabase"."pipeline_stages" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."pipeline_stages" add column if not exists "color" text;
alter table "better_supabase"."pipeline_stages" add column if not exists "rank" text collate "C" not null default 'V';
alter table "better_supabase"."pipeline_stages" add column if not exists "category" text;
alter table "better_supabase"."pipeline_stages" add column if not exists "outcome" text check ("outcome" in ('open', 'success', 'failure'));
alter table "better_supabase"."pipeline_stages" add column if not exists "probability" smallint check ("probability" >= 0 and "probability" <= 100);
alter table "better_supabase"."pipeline_stages" add column if not exists "rotting_after_days" integer check ("rotting_after_days" > 0);
alter table "better_supabase"."pipeline_stages" add column if not exists "wip_limit" integer check ("wip_limit" > 0);
alter table "better_supabase"."pipeline_stages" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."pipeline_stages" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."pipeline_stages" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_pipeline_stages_key_key" on "better_supabase"."pipeline_stages" ("pipeline_id", "key");
create index if not exists pipeline_stages_pipeline_idx on "better_supabase"."pipeline_stages" ("pipeline_id", "rank");
alter table "better_supabase"."pipeline_stages" enable row level security;
grant select on "better_supabase"."pipeline_stages" to authenticated;
grant all on "better_supabase"."pipeline_stages" to service_role;
drop policy if exists bsb_pipeline_stages_select on "better_supabase"."pipeline_stages";
create policy bsb_pipeline_stages_select on "better_supabase"."pipeline_stages"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

-- better_supabase.pipeline_transitions is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."pipeline_transitions" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."pipeline_transitions" add column if not exists "pipeline_id" uuid references "better_supabase"."pipelines" ("id") on delete cascade;
alter table "better_supabase"."pipeline_transitions" add column if not exists "from_stage_id" uuid references "better_supabase"."pipeline_stages" ("id") on delete cascade;
alter table "better_supabase"."pipeline_transitions" add column if not exists "to_stage_id" uuid references "better_supabase"."pipeline_stages" ("id") on delete cascade;
create unique index if not exists "bsb_pipeline_transitions_pair_key" on "better_supabase"."pipeline_transitions" ("from_stage_id", "to_stage_id");
create index if not exists pipeline_transitions_pipeline_idx on "better_supabase"."pipeline_transitions" ("pipeline_id");
create index if not exists pipeline_transitions_to_idx on "better_supabase"."pipeline_transitions" ("to_stage_id");
alter table "better_supabase"."pipeline_transitions" enable row level security;
grant select on "better_supabase"."pipeline_transitions" to authenticated;
grant all on "better_supabase"."pipeline_transitions" to service_role;
drop policy if exists bsb_pipeline_transitions_select on "better_supabase"."pipeline_transitions";
create policy bsb_pipeline_transitions_select on "better_supabase"."pipeline_transitions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

-- better_supabase.pipeline_stage_history is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."pipeline_stage_history" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."pipeline_stage_history" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."pipeline_stage_history" add column if not exists "subject_type" text;
alter table "better_supabase"."pipeline_stage_history" add column if not exists "subject_id" text;
alter table "better_supabase"."pipeline_stage_history" add column if not exists "pipeline_id" uuid;
alter table "better_supabase"."pipeline_stage_history" add column if not exists "from_stage_id" uuid;
alter table "better_supabase"."pipeline_stage_history" add column if not exists "to_stage_id" uuid;
alter table "better_supabase"."pipeline_stage_history" add column if not exists "stage_name" text;
alter table "better_supabase"."pipeline_stage_history" add column if not exists "category" text;
alter table "better_supabase"."pipeline_stage_history" add column if not exists "outcome" text;
alter table "better_supabase"."pipeline_stage_history" add column if not exists "amount" bigint;
alter table "better_supabase"."pipeline_stage_history" add column if not exists "currency" char(3);
alter table "better_supabase"."pipeline_stage_history" add column if not exists "actor_user_id" uuid;
alter table "better_supabase"."pipeline_stage_history" add column if not exists "entered_at" timestamptz not null default now();
alter table "better_supabase"."pipeline_stage_history" add column if not exists "exited_at" timestamptz;
create index if not exists pipeline_stage_history_subject_idx on "better_supabase"."pipeline_stage_history" ("subject_type", "subject_id", "entered_at");
create index if not exists pipeline_stage_history_pipeline_idx on "better_supabase"."pipeline_stage_history" ("pipeline_id", "entered_at");
create unique index if not exists pipeline_stage_history_open_idx on "better_supabase"."pipeline_stage_history" ("subject_type", "subject_id") where "exited_at" is null;
alter table "better_supabase"."pipeline_stage_history" enable row level security;
grant select on "better_supabase"."pipeline_stage_history" to authenticated;
grant all on "better_supabase"."pipeline_stage_history" to service_role;
-- A history row is visible to whoever can read its record.
drop policy if exists bsb_pipeline_stage_history_select on "better_supabase"."pipeline_stage_history";
create policy bsb_pipeline_stage_history_select on "better_supabase"."pipeline_stage_history"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));

-- The default pipeline of a subject type in a tenant and scope. The first
-- call creates it from the type's stage template in on.
create or replace function "better_supabase"."default_pipeline"(tenant uuid, subject_type text, scope_id text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select x."id" into v_id from "better_supabase"."pipelines" x
  where x."tenant_id" = default_pipeline.tenant
    and x."subject_type" = default_pipeline.subject_type
    and x."scope_id" is not distinct from default_pipeline.scope_id
    and x."archived_at" is null
  order by x."is_default" desc, x."rank" collate "C"
  limit 1;
  if v_id is not null then
    return v_id;
  end if;
  raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."default_pipeline"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."default_pipeline"(uuid, text, text) to service_role;



-- Creates a pipeline (pipeline null) or renames one. The first pipeline of a
-- subject type and scope is its default. Returns its row.
drop function if exists "better_supabase"."save_pipeline"(uuid, uuid, text, text, text, text, boolean, jsonb);
create or replace function "better_supabase"."save_pipeline"(tenant uuid, pipeline uuid, subject_type text, key text, name text, scope_id text, is_default boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pipeline uuid := save_pipeline.pipeline;
  v_created boolean := save_pipeline.pipeline is null;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_pipeline.tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if not (save_pipeline.subject_type = any ('{}'::text[])) then
    raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_save"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using save_pipeline.tenant, save_pipeline.pipeline, save_pipeline.subject_type, save_pipeline.key;
    end if;
  end;
  if coalesce(save_pipeline.is_default, false) then
    update "better_supabase"."pipelines" x set "is_default" = false
    where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type
      and x."scope_id" is not distinct from save_pipeline.scope_id and x."is_default"
      and x."id" is distinct from save_pipeline.pipeline;
  end if;
  begin
    if v_created then
      insert into "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default", "rank")
      values (save_pipeline.tenant, save_pipeline.subject_type, save_pipeline.scope_id, save_pipeline.key, save_pipeline.name,
        coalesce(save_pipeline.is_default, false) or not exists (
          select 1 from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type
            and x."scope_id" is not distinct from save_pipeline.scope_id and x."archived_at" is null),
        case
    when (select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) from '^z*')) = length((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type)) then (select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) || 'V'
    else left((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."tenant_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_pipeline;
    else
      update "better_supabase"."pipelines" x set "key" = save_pipeline.key, "name" = save_pipeline.name,
        "is_default" = coalesce(save_pipeline.is_default, x."is_default"), "updated_at" = now()
      where x."id" = save_pipeline.pipeline and x."tenant_id" = save_pipeline.tenant
        and x."subject_type" = save_pipeline.subject_type;
      if not found then
        raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another pipeline of this type has this key' using errcode = '23505', hint = 'PIPELINE_KEY_TAKEN';
  end;
  if v_created then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_pipeline, v_created;
    end if;
  end;
  return (select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'subject_type', x."subject_type", 'scope_id', x."scope_id", 'key', x."key", 'name', x."name", 'rank', x."rank", 'is_default', x."is_default", 'archived_at', x."archived_at", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."pipelines" x where x."id" = v_pipeline);
end;
$$;
revoke execute on function "better_supabase"."save_pipeline"(uuid, uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."save_pipeline"(uuid, uuid, text, text, text, text, boolean) to authenticated, service_role;

-- Archives a pipeline. Records still in it must move to another first.
create or replace function "better_supabase"."archive_pipeline"(pipeline uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_subject_type text;
  v_used boolean;
  v_pipeline uuid := archive_pipeline.pipeline;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."subject_type" into v_tenant, v_subject_type
  from "better_supabase"."pipelines" x where x."id" = archive_pipeline.pipeline and x."archived_at" is null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  v_used := false;
  if v_used then
    raise exception 'records are still in this pipeline; move them first' using errcode = '23503', hint = 'PIPELINE_IN_USE';
  end if;
  update "better_supabase"."pipelines" x set "archived_at" = now(), "is_default" = false, "updated_at" = now()
  where x."id" = archive_pipeline.pipeline;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_pipeline"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_pipeline"(uuid) to authenticated, service_role;

-- Creates a stage at the end of a pipeline (stage null) or changes one.
-- The category must be one the subject type declares; it sets the outcome.
create or replace function "better_supabase"."save_pipeline_stage"(pipeline uuid, stage uuid, key text, name text, category text, probability integer, rotting_after_days integer, wip_limit integer, color text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_subject_type text;
  v_outcome text;
  v_stage uuid := save_pipeline_stage.stage;
  v_pipeline uuid := save_pipeline_stage.pipeline;
  v_used boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."subject_type" into v_tenant, v_subject_type
  from "better_supabase"."pipelines" x where x."id" = save_pipeline_stage.pipeline and x."archived_at" is null;
  if v_tenant is null then
    raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  if v_outcome is null then
    raise exception 'this subject type has no such category' using errcode = '22023', hint = 'PIPELINE_CATEGORY_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_save"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using save_pipeline_stage.pipeline, save_pipeline_stage.stage, save_pipeline_stage.key, save_pipeline_stage.category;
    end if;
  end;
  begin
    if v_stage is null then
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "probability", "rotting_after_days", "wip_limit", "color", "rank")
      values (v_tenant, save_pipeline_stage.pipeline, save_pipeline_stage.key, save_pipeline_stage.name, better_supabase.as_column_type(save_pipeline_stage.category, (null::"better_supabase"."pipeline_stages")."category"), better_supabase.as_column_type(v_outcome, (null::"better_supabase"."pipeline_stages")."outcome"), save_pipeline_stage.probability, save_pipeline_stage.rotting_after_days, save_pipeline_stage.wip_limit, save_pipeline_stage.color,
        case
    when (select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*')) = length((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline)) then (select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) || 'V'
    else left((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_stage;
    else
      -- A stage holding records keeps its outcome, so won stays won.
      if exists (select 1 from "better_supabase"."pipeline_stages" x where x."id" = v_stage and x."outcome" <> better_supabase.as_column_type(v_outcome, (null::"better_supabase"."pipeline_stages")."outcome")) then
        v_used := false;
        if v_used then
          raise exception 'records are in this stage; its outcome can''t change' using errcode = '23503', hint = 'PIPELINE_STAGE_IN_USE';
        end if;
      end if;
      update "better_supabase"."pipeline_stages" x set "key" = save_pipeline_stage.key, "name" = save_pipeline_stage.name, "category" = better_supabase.as_column_type(save_pipeline_stage.category, (null::"better_supabase"."pipeline_stages")."category"), "outcome" = better_supabase.as_column_type(v_outcome, (null::"better_supabase"."pipeline_stages")."outcome"), "probability" = save_pipeline_stage.probability, "rotting_after_days" = save_pipeline_stage.rotting_after_days, "wip_limit" = save_pipeline_stage.wip_limit, "color" = save_pipeline_stage.color, "updated_at" = now()
      where x."id" = v_stage and x."pipeline_id" = save_pipeline_stage.pipeline;
      if not found then
        raise exception 'stage not found' using errcode = 'P0002', hint = 'PIPELINE_STAGE_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another stage of this pipeline has this key' using errcode = '23505', hint = 'PIPELINE_STAGE_KEY_TAKEN';
  end;
  if save_pipeline_stage.stage is null then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_stage;
    end if;
  end;
  return (select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'pipeline_id', x."pipeline_id", 'key', x."key", 'system_key', x."system_key", 'name', x."name", 'color', x."color", 'rank', x."rank", 'category', x."category", 'outcome', x."outcome", 'probability', x."probability", 'rotting_after_days', x."rotting_after_days", 'wip_limit', x."wip_limit", 'archived_at', x."archived_at", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."pipeline_stages" x where x."id" = v_stage);
end;
$$;
revoke execute on function "better_supabase"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text) from public, anon;
grant execute on function "better_supabase"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text) to authenticated, service_role;

-- Moves a stage to a rank key the client computed with rankBetween.
create or replace function "better_supabase"."rank_pipeline_stage"(stage uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."pipeline_stages" x where x."id" = rank_pipeline_stage.stage;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if rank_pipeline_stage.rank is null or rank_pipeline_stage.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'PIPELINE_RANK_INVALID';
  end if;
  update "better_supabase"."pipeline_stages" x set "rank" = rank_pipeline_stage.rank, "updated_at" = now()
  where x."id" = rank_pipeline_stage.stage;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_pipeline_stage"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_pipeline_stage"(uuid, text) to authenticated, service_role;

-- Archives an empty stage. The last open stage of a pipeline stays.
create or replace function "better_supabase"."archive_pipeline_stage"(stage uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_pipeline uuid;
  v_subject_type text;
  v_outcome text;
  v_used boolean;
  v_stage uuid := archive_pipeline_stage.stage;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."pipeline_id", x."outcome", y."subject_type"
    into v_tenant, v_pipeline, v_outcome, v_subject_type
  from "better_supabase"."pipeline_stages" x join "better_supabase"."pipelines" y on y."id" = x."pipeline_id"
  where x."id" = archive_pipeline_stage.stage and x."archived_at" is null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  v_used := false;
  if v_used then
    raise exception 'records are in this stage; move them first' using errcode = '23503', hint = 'PIPELINE_STAGE_IN_USE';
  end if;
  if v_outcome = 'open' and not exists (
    select 1 from "better_supabase"."pipeline_stages" x where x."pipeline_id" = v_pipeline and x."outcome" = 'open'
      and x."archived_at" is null and x."id" <> archive_pipeline_stage.stage
  ) then
    raise exception 'a pipeline keeps at least one open stage' using errcode = '23514', hint = 'PIPELINE_LAST_OPEN_STAGE';
  end if;
  update "better_supabase"."pipeline_stages" x set "archived_at" = now(), "updated_at" = now() where x."id" = archive_pipeline_stage.stage;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_pipeline_stage"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_pipeline_stage"(uuid) to authenticated, service_role;

-- Replaces the allowed stage changes of a pipeline. An empty list allows
-- every change; pairs is a list of { "from": stage id, "to": stage id }.
create or replace function "better_supabase"."set_pipeline_transitions"(pipeline uuid, pairs jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."pipelines" x where x."id" = set_pipeline_transitions.pipeline;
  if v_tenant is null then
    raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(set_pipeline_transitions.pairs, '[]')) <> 'array' then
    raise exception 'pairs must be a list of { from, to } stage ids' using errcode = '22023', hint = 'PIPELINE_TRANSITIONS_INVALID';
  end if;
  delete from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = set_pipeline_transitions.pipeline;
  insert into "better_supabase"."pipeline_transitions" ("tenant_id", "pipeline_id", "from_stage_id", "to_stage_id")
  select v_tenant, set_pipeline_transitions.pipeline, (pair ->> 'from')::uuid, (pair ->> 'to')::uuid
  from jsonb_array_elements(coalesce(set_pipeline_transitions.pairs, '[]')) pair
  on conflict do nothing;
  get diagnostics v_count = row_count;
  if exists (
    select 1 from "better_supabase"."pipeline_transitions" x
    left join "better_supabase"."pipeline_stages" a on a."id" = x."from_stage_id" and a."pipeline_id" = x."pipeline_id"
    left join "better_supabase"."pipeline_stages" b on b."id" = x."to_stage_id" and b."pipeline_id" = x."pipeline_id"
    where x."pipeline_id" = set_pipeline_transitions.pipeline and (a."id" is null or b."id" is null)
  ) then
    raise exception 'every stage must belong to the pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITIONS_INVALID';
  end if;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_pipeline_transitions"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_pipeline_transitions"(uuid, jsonb) to authenticated, service_role;

-- One entry per active stage, in board order: the count of records the
-- caller can see, and per currency the amount and the amount weighted by
-- probability. Amounts are text so bigint minor units survive JSON.
create or replace function "better_supabase"."pipeline_board"(subject_type text, pipeline uuid, owner uuid default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."pipeline_board"(text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."pipeline_board"(text, uuid, uuid) to authenticated, service_role;

-- Per stage, between since and until: how many records entered it, how long
-- the ones that left stayed on average, and the share that went on to a
-- success stage. Reads the history the caller can see.
create or replace function "better_supabase"."pipeline_stats"(pipeline uuid, since timestamptz, until timestamptz)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with window_rows as (
    select * from "better_supabase"."pipeline_stage_history" h
    where h."pipeline_id" = pipeline_stats.pipeline
      and h."entered_at" >= pipeline_stats.since and h."entered_at" < pipeline_stats.until
  ),
  per_stage as (
    select w."to_stage_id" as stage_id, count(*) as entered,
      avg(extract(epoch from (w."exited_at" - w."entered_at"))) filter (where w."exited_at" is not null) as avg_seconds
    from window_rows w group by w."to_stage_id"
  ),
  closed as (
    select count(*) filter (where w."outcome" = 'success') as won,
      count(*) filter (where w."outcome" = 'failure') as lost
    from window_rows w
  )
  select jsonb_build_object(
    'won', closed.won,
    'lost', closed.lost,
    'winRate', case when closed.won + closed.lost = 0 then null else round(closed.won::numeric / (closed.won + closed.lost), 4) end,
    'stages', coalesce((
      select jsonb_agg(jsonb_build_object('stageId', st."id", 'key', st."key", 'entered', coalesce(ps.entered, 0), 'averageSeconds', round(ps.avg_seconds)) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st left join per_stage ps on ps.stage_id = st."id"
      where st."pipeline_id" = pipeline_stats.pipeline
    ), '[]'::jsonb)
  )
  from closed;
$$;
revoke execute on function "better_supabase"."pipeline_stats"(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."pipeline_stats"(uuid, timestamptz, timestamptz) to authenticated, service_role;

-- The open records of a pipeline the caller can see, oldest entry first:
-- when each entered its stage and whether it sits longer than the stage's
-- rotting limit.
create or replace function "better_supabase"."pipeline_health"(pipeline uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subjectType', h."subject_type", 'subjectId', h."subject_id", 'stageId', h."to_stage_id",
    'enteredAt', h."entered_at",
    'daysInStage', (extract(epoch from now() - h."entered_at") / 86400)::integer,
    'rotting', st."rotting_after_days" is not null and now() - h."entered_at" > make_interval(days => st."rotting_after_days")
  ) order by h."entered_at"), '[]'::jsonb)
  from "better_supabase"."pipeline_stage_history" h
  join "better_supabase"."pipeline_stages" st on st."id" = h."to_stage_id"
  where h."pipeline_id" = pipeline_health.pipeline and h."exited_at" is null and h."outcome" = 'open';
$$;
revoke execute on function "better_supabase"."pipeline_health"(uuid) from public, anon;
grant execute on function "better_supabase"."pipeline_health"(uuid) to authenticated, service_role;

-- The tenant's active pipelines of a subject type, each with its active
-- stages in board order.
create or replace function "better_supabase"."list_pipelines"(tenant uuid, subject_type text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'subject_type', x."subject_type", 'scope_id', x."scope_id", 'key', x."key", 'name', x."name", 'rank', x."rank", 'is_default', x."is_default", 'archived_at', x."archived_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('stages', coalesce((
      select jsonb_agg(jsonb_build_object('id', st."id", 'tenant_id', st."tenant_id", 'pipeline_id', st."pipeline_id", 'key', st."key", 'system_key', st."system_key", 'name', st."name", 'color', st."color", 'rank', st."rank", 'category', st."category", 'outcome', st."outcome", 'probability', st."probability", 'rotting_after_days', st."rotting_after_days", 'wip_limit', st."wip_limit", 'archived_at', st."archived_at", 'created_at', st."created_at", 'updated_at', st."updated_at") order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) order by x."rank" collate "C"), '[]'::jsonb)
  from "better_supabase"."pipelines" x
  where x."tenant_id" = list_pipelines.tenant
    and x."subject_type" = list_pipelines.subject_type
    and x."archived_at" is null;
$$;
revoke execute on function "better_supabase"."list_pipelines"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_pipelines"(uuid, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."pipelines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipelines";
create policy bsb_tenant_scope_select on "better_supabase"."pipelines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipelines";
create policy bsb_tenant_scope_insert on "better_supabase"."pipelines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipelines";
create policy bsb_tenant_scope_update on "better_supabase"."pipelines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipelines";
create policy bsb_tenant_scope_delete on "better_supabase"."pipelines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stages";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_select on "better_supabase"."pipeline_stages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_insert on "better_supabase"."pipeline_stages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_update on "better_supabase"."pipeline_stages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_delete on "better_supabase"."pipeline_stages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_transitions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_select on "better_supabase"."pipeline_transitions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_insert on "better_supabase"."pipeline_transitions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_update on "better_supabase"."pipeline_transitions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_delete on "better_supabase"."pipeline_transitions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stage_history";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_select on "better_supabase"."pipeline_stage_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_insert on "better_supabase"."pipeline_stage_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_update on "better_supabase"."pipeline_stage_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_delete on "better_supabase"."pipeline_stage_history" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_092_pipelines.sql
-- better-supabase module: pipelines
-- @bsb-block-data pipelines
-- @bsb-hash sha256:afbc833c2019b6deab1e41862c83cefb962a135052476adab19c5b7d64bafdad
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('pipelines', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_092_pipelines.sql
-- better-supabase module: pipelines
-- @bsb-block pipelines@1 managed
-- @bsb-hash sha256:924475fdc462ebfc5e332aec792837372a5608d356b5ef04299b11fbe1860d95
-- Tenant-editable pipelines for any registered subject: ordered stages whose categories map to open, success or failure, a stage history with time in stage, board totals per currency and a status mapping that runs through state-machine.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipelines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipelines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stages";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stages";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_transitions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_transitions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stage_history";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stage_history";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Pipelines (ADR 0028): tenant-editable stages per subject type, each with
-- a category that maps to a fixed outcome, a stage history and board totals.

create table if not exists "better_supabase"."pipelines" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null,
  "scope_id" text,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "rank" text collate "C" not null default 'V',
  "is_default" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique nulls not distinct ("org_id", "subject_type", "scope_id", "key")
);
create unique index if not exists pipelines_default_idx on "better_supabase"."pipelines" ("org_id", "subject_type", coalesce("scope_id", ''))
  where "is_default" and "archived_at" is null;
alter table "better_supabase"."pipelines" enable row level security;
revoke all on "better_supabase"."pipelines" from public, anon, authenticated;
grant select on "better_supabase"."pipelines" to authenticated;
grant all on "better_supabase"."pipelines" to service_role;
drop policy if exists pipelines_read on "better_supabase"."pipelines";
create policy pipelines_read on "better_supabase"."pipelines"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

create table if not exists "better_supabase"."pipeline_stages" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "pipeline_id" uuid not null references "better_supabase"."pipelines" ("id") on delete cascade,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "system_key" text,
  "name" text not null check (length("name") between 1 and 200),
  "color" text,
  "rank" text collate "C" not null default 'V',
  "category" text not null,
  "outcome" text not null check ("outcome" in ('open', 'success', 'failure')),
  "probability" smallint check ("probability" >= 0 and "probability" <= 100),
  "rotting_after_days" integer check ("rotting_after_days" > 0),
  "wip_limit" integer check ("wip_limit" > 0),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("pipeline_id", "key")
);
create index if not exists pipeline_stages_pipeline_idx on "better_supabase"."pipeline_stages" ("pipeline_id", "rank");
alter table "better_supabase"."pipeline_stages" enable row level security;
revoke all on "better_supabase"."pipeline_stages" from public, anon, authenticated;
grant select on "better_supabase"."pipeline_stages" to authenticated;
grant all on "better_supabase"."pipeline_stages" to service_role;
drop policy if exists pipeline_stages_read on "better_supabase"."pipeline_stages";
create policy pipeline_stages_read on "better_supabase"."pipeline_stages"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

create table if not exists "better_supabase"."pipeline_transitions" (
  "org_id" uuid not null,
  "pipeline_id" uuid not null references "better_supabase"."pipelines" ("id") on delete cascade,
  "from_stage_id" uuid not null references "better_supabase"."pipeline_stages" ("id") on delete cascade,
  "to_stage_id" uuid not null references "better_supabase"."pipeline_stages" ("id") on delete cascade,
  primary key ("from_stage_id", "to_stage_id")
);
create index if not exists pipeline_transitions_pipeline_idx on "better_supabase"."pipeline_transitions" ("pipeline_id");
create index if not exists pipeline_transitions_to_idx on "better_supabase"."pipeline_transitions" ("to_stage_id");
alter table "better_supabase"."pipeline_transitions" enable row level security;
revoke all on "better_supabase"."pipeline_transitions" from public, anon, authenticated;
grant select on "better_supabase"."pipeline_transitions" to authenticated;
grant all on "better_supabase"."pipeline_transitions" to service_role;
drop policy if exists pipeline_transitions_read on "better_supabase"."pipeline_transitions";
create policy pipeline_transitions_read on "better_supabase"."pipeline_transitions"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

create table if not exists "better_supabase"."pipeline_stage_history" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "pipeline_id" uuid not null,
  "from_stage_id" uuid,
  "to_stage_id" uuid not null,
  "stage_name" text not null,
  "category" text not null,
  "outcome" text not null,
  "amount" bigint,
  "currency" char(3),
  "actor_user_id" uuid,
  "entered_at" timestamptz not null default now(),
  "exited_at" timestamptz
);
create index if not exists pipeline_stage_history_subject_idx on "better_supabase"."pipeline_stage_history" ("subject_type", "subject_id", "entered_at");
create index if not exists pipeline_stage_history_pipeline_idx on "better_supabase"."pipeline_stage_history" ("pipeline_id", "entered_at");
create unique index if not exists pipeline_stage_history_open_idx on "better_supabase"."pipeline_stage_history" ("subject_type", "subject_id") where "exited_at" is null;
alter table "better_supabase"."pipeline_stage_history" enable row level security;
revoke all on "better_supabase"."pipeline_stage_history" from public, anon, authenticated;
grant select on "better_supabase"."pipeline_stage_history" to authenticated;
grant all on "better_supabase"."pipeline_stage_history" to service_role;
-- A history row is visible to whoever can read its record.
drop policy if exists pipeline_stage_history_read on "better_supabase"."pipeline_stage_history";
create policy pipeline_stage_history_read on "better_supabase"."pipeline_stage_history"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('pipelines.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));

-- The default pipeline of a subject type in a tenant and scope. The first
-- call creates it from the type's stage template in on.
create or replace function "better_supabase"."default_pipeline"(tenant uuid, subject_type text, scope_id text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select x."id" into v_id from "better_supabase"."pipelines" x
  where x."org_id" = default_pipeline.tenant
    and x."subject_type" = default_pipeline.subject_type
    and x."scope_id" is not distinct from default_pipeline.scope_id
    and x."archived_at" is null
  order by x."is_default" desc, x."rank" collate "C"
  limit 1;
  if v_id is not null then
    return v_id;
  end if;
  raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."default_pipeline"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."default_pipeline"(uuid, text, text) to service_role;



-- Creates a pipeline (pipeline null) or renames one. The first pipeline of a
-- subject type and scope is its default. Returns its row.
drop function if exists "better_supabase"."save_pipeline"(uuid, uuid, text, text, text, text, boolean, jsonb);
create or replace function "better_supabase"."save_pipeline"(tenant uuid, pipeline uuid, subject_type text, key text, name text, scope_id text, is_default boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pipeline uuid := save_pipeline.pipeline;
  v_created boolean := save_pipeline.pipeline is null;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_pipeline.tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if not (save_pipeline.subject_type = any ('{}'::text[])) then
    raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_save"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using save_pipeline.tenant, save_pipeline.pipeline, save_pipeline.subject_type, save_pipeline.key;
    end if;
  end;
  if coalesce(save_pipeline.is_default, false) then
    update "better_supabase"."pipelines" x set "is_default" = false
    where x."org_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type
      and x."scope_id" is not distinct from save_pipeline.scope_id and x."is_default"
      and x."id" is distinct from save_pipeline.pipeline;
  end if;
  begin
    if v_created then
      insert into "better_supabase"."pipelines" ("org_id", "subject_type", "scope_id", "key", "name", "is_default", "rank")
      values (save_pipeline.tenant, save_pipeline.subject_type, save_pipeline.scope_id, save_pipeline.key, save_pipeline.name,
        coalesce(save_pipeline.is_default, false) or not exists (
          select 1 from "better_supabase"."pipelines" x where x."org_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type
            and x."scope_id" is not distinct from save_pipeline.scope_id and x."archived_at" is null),
        case
    when (select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."org_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."org_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) from '^z*')) = length((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."org_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type)) then (select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."org_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) || 'V'
    else left((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."org_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."org_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."org_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipelines" x where x."org_id" = save_pipeline.tenant and x."subject_type" = save_pipeline.subject_type) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_pipeline;
    else
      update "better_supabase"."pipelines" x set "key" = save_pipeline.key, "name" = save_pipeline.name,
        "is_default" = coalesce(save_pipeline.is_default, x."is_default"), "updated_at" = now()
      where x."id" = save_pipeline.pipeline and x."org_id" = save_pipeline.tenant
        and x."subject_type" = save_pipeline.subject_type;
      if not found then
        raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another pipeline of this type has this key' using errcode = '23505', hint = 'PIPELINE_KEY_TAKEN';
  end;
  if v_created then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_pipeline, v_created;
    end if;
  end;
  return (select (to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) from "better_supabase"."pipelines" x where x."id" = v_pipeline);
end;
$$;
revoke execute on function "better_supabase"."save_pipeline"(uuid, uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."save_pipeline"(uuid, uuid, text, text, text, text, boolean) to authenticated, service_role;

-- Archives a pipeline. Records still in it must move to another first.
create or replace function "better_supabase"."archive_pipeline"(pipeline uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_subject_type text;
  v_used boolean;
  v_pipeline uuid := archive_pipeline.pipeline;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id", x."subject_type" into v_tenant, v_subject_type
  from "better_supabase"."pipelines" x where x."id" = archive_pipeline.pipeline and x."archived_at" is null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  v_used := false;
  if v_used then
    raise exception 'records are still in this pipeline; move them first' using errcode = '23503', hint = 'PIPELINE_IN_USE';
  end if;
  update "better_supabase"."pipelines" x set "archived_at" = now(), "is_default" = false, "updated_at" = now()
  where x."id" = archive_pipeline.pipeline;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_pipeline"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_pipeline"(uuid) to authenticated, service_role;

-- Creates a stage at the end of a pipeline (stage null) or changes one.
-- The category must be one the subject type declares; it sets the outcome.
create or replace function "better_supabase"."save_pipeline_stage"(pipeline uuid, stage uuid, key text, name text, category text, probability integer, rotting_after_days integer, wip_limit integer, color text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_subject_type text;
  v_outcome text;
  v_stage uuid := save_pipeline_stage.stage;
  v_pipeline uuid := save_pipeline_stage.pipeline;
  v_used boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id", x."subject_type" into v_tenant, v_subject_type
  from "better_supabase"."pipelines" x where x."id" = save_pipeline_stage.pipeline and x."archived_at" is null;
  if v_tenant is null then
    raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  if v_outcome is null then
    raise exception 'this subject type has no such category' using errcode = '22023', hint = 'PIPELINE_CATEGORY_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_save"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using save_pipeline_stage.pipeline, save_pipeline_stage.stage, save_pipeline_stage.key, save_pipeline_stage.category;
    end if;
  end;
  begin
    if v_stage is null then
      insert into "better_supabase"."pipeline_stages" ("org_id", "pipeline_id", "key", "name", "category", "outcome", "probability", "rotting_after_days", "wip_limit", "color", "rank")
      values (v_tenant, save_pipeline_stage.pipeline, save_pipeline_stage.key, save_pipeline_stage.name, save_pipeline_stage.category, v_outcome, save_pipeline_stage.probability, save_pipeline_stage.rotting_after_days, save_pipeline_stage.wip_limit, save_pipeline_stage.color,
        case
    when (select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*')) = length((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline)) then (select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) || 'V'
    else left((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_stage;
    else
      -- A stage holding records keeps its outcome, so won stays won.
      if exists (select 1 from "better_supabase"."pipeline_stages" x where x."id" = v_stage and x."outcome" <> v_outcome) then
        v_used := false;
        if v_used then
          raise exception 'records are in this stage; its outcome can''t change' using errcode = '23503', hint = 'PIPELINE_STAGE_IN_USE';
        end if;
      end if;
      update "better_supabase"."pipeline_stages" x set "key" = save_pipeline_stage.key, "name" = save_pipeline_stage.name, "category" = save_pipeline_stage.category, "outcome" = v_outcome, "probability" = save_pipeline_stage.probability, "rotting_after_days" = save_pipeline_stage.rotting_after_days, "wip_limit" = save_pipeline_stage.wip_limit, "color" = save_pipeline_stage.color, "updated_at" = now()
      where x."id" = v_stage and x."pipeline_id" = save_pipeline_stage.pipeline;
      if not found then
        raise exception 'stage not found' using errcode = 'P0002', hint = 'PIPELINE_STAGE_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another stage of this pipeline has this key' using errcode = '23505', hint = 'PIPELINE_STAGE_KEY_TAKEN';
  end;
  if save_pipeline_stage.stage is null then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_stage;
    end if;
  end;
  return (select (to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) from "better_supabase"."pipeline_stages" x where x."id" = v_stage);
end;
$$;
revoke execute on function "better_supabase"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text) from public, anon;
grant execute on function "better_supabase"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text) to authenticated, service_role;

-- Moves a stage to a rank key the client computed with rankBetween.
create or replace function "better_supabase"."rank_pipeline_stage"(stage uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id" into v_tenant from "better_supabase"."pipeline_stages" x where x."id" = rank_pipeline_stage.stage;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if rank_pipeline_stage.rank is null or rank_pipeline_stage.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'PIPELINE_RANK_INVALID';
  end if;
  update "better_supabase"."pipeline_stages" x set "rank" = rank_pipeline_stage.rank, "updated_at" = now()
  where x."id" = rank_pipeline_stage.stage;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_pipeline_stage"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_pipeline_stage"(uuid, text) to authenticated, service_role;

-- Archives an empty stage. The last open stage of a pipeline stays.
create or replace function "better_supabase"."archive_pipeline_stage"(stage uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_pipeline uuid;
  v_subject_type text;
  v_outcome text;
  v_used boolean;
  v_stage uuid := archive_pipeline_stage.stage;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id", x."pipeline_id", x."outcome", y."subject_type"
    into v_tenant, v_pipeline, v_outcome, v_subject_type
  from "better_supabase"."pipeline_stages" x join "better_supabase"."pipelines" y on y."id" = x."pipeline_id"
  where x."id" = archive_pipeline_stage.stage and x."archived_at" is null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  v_used := false;
  if v_used then
    raise exception 'records are in this stage; move them first' using errcode = '23503', hint = 'PIPELINE_STAGE_IN_USE';
  end if;
  if v_outcome = 'open' and not exists (
    select 1 from "better_supabase"."pipeline_stages" x where x."pipeline_id" = v_pipeline and x."outcome" = 'open'
      and x."archived_at" is null and x."id" <> archive_pipeline_stage.stage
  ) then
    raise exception 'a pipeline keeps at least one open stage' using errcode = '23514', hint = 'PIPELINE_LAST_OPEN_STAGE';
  end if;
  update "better_supabase"."pipeline_stages" x set "archived_at" = now(), "updated_at" = now() where x."id" = archive_pipeline_stage.stage;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_pipeline_stage"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_pipeline_stage"(uuid) to authenticated, service_role;

-- Replaces the allowed stage changes of a pipeline. An empty list allows
-- every change; pairs is a list of { "from": stage id, "to": stage id }.
create or replace function "better_supabase"."set_pipeline_transitions"(pipeline uuid, pairs jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id" into v_tenant from "better_supabase"."pipelines" x where x."id" = set_pipeline_transitions.pipeline;
  if v_tenant is null then
    raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(set_pipeline_transitions.pairs, '[]')) <> 'array' then
    raise exception 'pairs must be a list of { from, to } stage ids' using errcode = '22023', hint = 'PIPELINE_TRANSITIONS_INVALID';
  end if;
  delete from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = set_pipeline_transitions.pipeline;
  insert into "better_supabase"."pipeline_transitions" ("org_id", "pipeline_id", "from_stage_id", "to_stage_id")
  select v_tenant, set_pipeline_transitions.pipeline, (pair ->> 'from')::uuid, (pair ->> 'to')::uuid
  from jsonb_array_elements(coalesce(set_pipeline_transitions.pairs, '[]')) pair
  on conflict do nothing;
  get diagnostics v_count = row_count;
  if exists (
    select 1 from "better_supabase"."pipeline_transitions" x
    left join "better_supabase"."pipeline_stages" a on a."id" = x."from_stage_id" and a."pipeline_id" = x."pipeline_id"
    left join "better_supabase"."pipeline_stages" b on b."id" = x."to_stage_id" and b."pipeline_id" = x."pipeline_id"
    where x."pipeline_id" = set_pipeline_transitions.pipeline and (a."id" is null or b."id" is null)
  ) then
    raise exception 'every stage must belong to the pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITIONS_INVALID';
  end if;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_pipeline_transitions"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_pipeline_transitions"(uuid, jsonb) to authenticated, service_role;

-- One entry per active stage, in board order: the count of records the
-- caller can see, and per currency the amount and the amount weighted by
-- probability. Amounts are text so bigint minor units survive JSON.
create or replace function "better_supabase"."pipeline_board"(subject_type text, pipeline uuid, owner uuid default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."pipeline_board"(text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."pipeline_board"(text, uuid, uuid) to authenticated, service_role;

-- Per stage, between since and until: how many records entered it, how long
-- the ones that left stayed on average, and the share that went on to a
-- success stage. Reads the history the caller can see.
create or replace function "better_supabase"."pipeline_stats"(pipeline uuid, since timestamptz, until timestamptz)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with window_rows as (
    select * from "better_supabase"."pipeline_stage_history" h
    where h."pipeline_id" = pipeline_stats.pipeline
      and h."entered_at" >= pipeline_stats.since and h."entered_at" < pipeline_stats.until
  ),
  per_stage as (
    select w."to_stage_id" as stage_id, count(*) as entered,
      avg(extract(epoch from (w."exited_at" - w."entered_at"))) filter (where w."exited_at" is not null) as avg_seconds
    from window_rows w group by w."to_stage_id"
  ),
  closed as (
    select count(*) filter (where w."outcome" = 'success') as won,
      count(*) filter (where w."outcome" = 'failure') as lost
    from window_rows w
  )
  select jsonb_build_object(
    'won', closed.won,
    'lost', closed.lost,
    'winRate', case when closed.won + closed.lost = 0 then null else round(closed.won::numeric / (closed.won + closed.lost), 4) end,
    'stages', coalesce((
      select jsonb_agg(jsonb_build_object('stageId', st."id", 'key', st."key", 'entered', coalesce(ps.entered, 0), 'averageSeconds', round(ps.avg_seconds)) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st left join per_stage ps on ps.stage_id = st."id"
      where st."pipeline_id" = pipeline_stats.pipeline
    ), '[]'::jsonb)
  )
  from closed;
$$;
revoke execute on function "better_supabase"."pipeline_stats"(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."pipeline_stats"(uuid, timestamptz, timestamptz) to authenticated, service_role;

-- The open records of a pipeline the caller can see, oldest entry first:
-- when each entered its stage and whether it sits longer than the stage's
-- rotting limit.
create or replace function "better_supabase"."pipeline_health"(pipeline uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subjectType', h."subject_type", 'subjectId', h."subject_id", 'stageId', h."to_stage_id",
    'enteredAt', h."entered_at",
    'daysInStage', (extract(epoch from now() - h."entered_at") / 86400)::integer,
    'rotting', st."rotting_after_days" is not null and now() - h."entered_at" > make_interval(days => st."rotting_after_days")
  ) order by h."entered_at"), '[]'::jsonb)
  from "better_supabase"."pipeline_stage_history" h
  join "better_supabase"."pipeline_stages" st on st."id" = h."to_stage_id"
  where h."pipeline_id" = pipeline_health.pipeline and h."exited_at" is null and h."outcome" = 'open';
$$;
revoke execute on function "better_supabase"."pipeline_health"(uuid) from public, anon;
grant execute on function "better_supabase"."pipeline_health"(uuid) to authenticated, service_role;

-- The tenant's active pipelines of a subject type, each with its active
-- stages in board order.
create or replace function "better_supabase"."list_pipelines"(tenant uuid, subject_type text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg((to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) || jsonb_build_object('stages', coalesce((
      select jsonb_agg((to_jsonb(st) || jsonb_build_object('tenant_id', st."org_id")) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) order by x."rank" collate "C"), '[]'::jsonb)
  from "better_supabase"."pipelines" x
  where x."org_id" = list_pipelines.tenant
    and x."subject_type" = list_pipelines.subject_type
    and x."archived_at" is null;
$$;
revoke execute on function "better_supabase"."list_pipelines"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_pipelines"(uuid, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."pipelines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipelines";
create policy bsb_tenant_scope_select on "better_supabase"."pipelines" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipelines";
create policy bsb_tenant_scope_insert on "better_supabase"."pipelines" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipelines";
create policy bsb_tenant_scope_update on "better_supabase"."pipelines" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipelines";
create policy bsb_tenant_scope_delete on "better_supabase"."pipelines" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stages";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_select on "better_supabase"."pipeline_stages" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_insert on "better_supabase"."pipeline_stages" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_update on "better_supabase"."pipeline_stages" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stages";
create policy bsb_tenant_scope_delete on "better_supabase"."pipeline_stages" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_transitions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_select on "better_supabase"."pipeline_transitions" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_insert on "better_supabase"."pipeline_transitions" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_update on "better_supabase"."pipeline_transitions" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_transitions";
create policy bsb_tenant_scope_delete on "better_supabase"."pipeline_transitions" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pipeline_stage_history";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_select on "better_supabase"."pipeline_stage_history" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('pipelines.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_insert on "better_supabase"."pipeline_stage_history" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_update on "better_supabase"."pipeline_stage_history" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pipeline_stage_history";
create policy bsb_tenant_scope_delete on "better_supabase"."pipeline_stage_history" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_092_pipelines.sql
-- better-supabase module: pipelines
-- @bsb-block-data pipelines
-- @bsb-hash sha256:afbc833c2019b6deab1e41862c83cefb962a135052476adab19c5b7d64bafdad
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('pipelines', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
