-- ==== schema supabase/schemas/900_better_supabase_092_pipelines.sql
-- better-supabase module: pipelines
-- @bsb-block pipelines@1 managed
-- @bsb-hash sha256:de1e83877b31966be54f2b292b6e714fc775088d25780c0d0e6df6601109bf74
-- Tenant-editable pipelines for any registered subject: ordered stages whose categories map to open, success or failure, a stage history with time in stage, board totals per currency and a status mapping that runs through state-machine.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Pipelines (ADR 0028): tenant-editable stages per subject type, each with
-- a category that maps to a fixed outcome, a stage history and board totals.

create table "better_supabase"."pipelines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "scope_id" text,
  "key" text not null constraint bsb_pipelines_key_check check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null constraint bsb_pipelines_name_check check (length("name") >= 1 and length("name") <= 200),
  "rank" text collate "C" not null default 'V',
  "is_default" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique nulls not distinct ("tenant_id", "subject_type", "scope_id", "key")
);
create unique index pipelines_default_idx on "better_supabase"."pipelines" ("tenant_id", "subject_type", coalesce("scope_id", ''))
  where "is_default" and "archived_at" is null;
alter table "better_supabase"."pipelines" enable row level security;
revoke all on "better_supabase"."pipelines" from public, anon, authenticated;
grant select on "better_supabase"."pipelines" to authenticated;
grant all on "better_supabase"."pipelines" to service_role;
create policy bsb_pipelines_read on "better_supabase"."pipelines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

create table "better_supabase"."pipeline_stages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "pipeline_id" uuid not null references "better_supabase"."pipelines" ("id") on delete cascade,
  "key" text not null constraint bsb_pipeline_stages_key_check check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "system_key" text,
  "name" text not null constraint bsb_pipeline_stages_name_check check (length("name") >= 1 and length("name") <= 200),
  "color" text,
  "icon" text constraint bsb_pipeline_stages_icon_check check (length("icon") <= 100),
  "rank" text collate "C" not null default 'V',
  "category" text not null,
  "outcome" text not null constraint bsb_pipeline_stages_outcome_check check ("outcome" in ('open', 'success', 'failure')),
  "probability" smallint constraint bsb_pipeline_stages_probability_check check ("probability" >= 0 and "probability" <= 100),
  "rotting_after_days" integer constraint bsb_pipeline_stages_rotting_after_days_check check ("rotting_after_days" > 0),
  "wip_limit" integer constraint bsb_pipeline_stages_wip_limit_check check ("wip_limit" > 0),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("pipeline_id", "key")
);
create index pipeline_stages_pipeline_idx on "better_supabase"."pipeline_stages" ("pipeline_id", "rank");
alter table "better_supabase"."pipeline_stages" enable row level security;
revoke all on "better_supabase"."pipeline_stages" from public, anon, authenticated;
grant select on "better_supabase"."pipeline_stages" to authenticated;
grant all on "better_supabase"."pipeline_stages" to service_role;
create policy bsb_pipeline_stages_read on "better_supabase"."pipeline_stages"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

create table "better_supabase"."pipeline_transitions" (
  "tenant_id" uuid not null,
  "pipeline_id" uuid not null references "better_supabase"."pipelines" ("id") on delete cascade,
  "from_stage_id" uuid not null references "better_supabase"."pipeline_stages" ("id") on delete cascade,
  "to_stage_id" uuid not null references "better_supabase"."pipeline_stages" ("id") on delete cascade,
  primary key ("from_stage_id", "to_stage_id")
);
create index pipeline_transitions_pipeline_idx on "better_supabase"."pipeline_transitions" ("pipeline_id");
create index pipeline_transitions_to_idx on "better_supabase"."pipeline_transitions" ("to_stage_id");
alter table "better_supabase"."pipeline_transitions" enable row level security;
revoke all on "better_supabase"."pipeline_transitions" from public, anon, authenticated;
grant select on "better_supabase"."pipeline_transitions" to authenticated;
grant all on "better_supabase"."pipeline_transitions" to service_role;
create policy bsb_pipeline_transitions_read on "better_supabase"."pipeline_transitions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')));

create table "better_supabase"."pipeline_stage_history" (
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
  "actor_id" uuid,
  "entered_at" timestamptz not null default now(),
  "exited_at" timestamptz
);
create index pipeline_stage_history_subject_idx on "better_supabase"."pipeline_stage_history" ("subject_type", "subject_id", "entered_at");
create index pipeline_stage_history_pipeline_idx on "better_supabase"."pipeline_stage_history" ("pipeline_id", "entered_at");
create unique index pipeline_stage_history_open_idx on "better_supabase"."pipeline_stage_history" ("subject_type", "subject_id") where "exited_at" is null;
alter table "better_supabase"."pipeline_stage_history" enable row level security;
revoke all on "better_supabase"."pipeline_stage_history" from public, anon, authenticated;
grant select on "better_supabase"."pipeline_stage_history" to authenticated;
grant all on "better_supabase"."pipeline_stage_history" to service_role;
-- A history row is visible to whoever can read its record.
create policy bsb_pipeline_stage_history_read on "better_supabase"."pipeline_stage_history"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')) and coalesce("better_supabase"."can_subject"("better_supabase"."pipeline_stage_history"."subject_type", "better_supabase"."pipeline_stage_history"."subject_id", 'read'), false));

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

-- Restores an archived pipeline. It does not become the default again.
create or replace function "better_supabase"."restore_pipeline"(pipeline uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_subject_type text;
  v_pipeline uuid := restore_pipeline.pipeline;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."subject_type" into v_tenant, v_subject_type
  from "better_supabase"."pipelines" x where x."id" = restore_pipeline.pipeline and x."archived_at" is not null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  update "better_supabase"."pipelines" x set "archived_at" = null, "updated_at" = now()
  where x."id" = restore_pipeline.pipeline;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."restore_pipeline"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_pipeline"(uuid) to authenticated, service_role;

-- Creates a stage at the end of a pipeline (stage null) or changes one.
-- The category must be one the subject type declares; it sets the outcome.

create or replace function "better_supabase"."save_pipeline_stage"(pipeline uuid, stage uuid, key text, name text, category text, probability integer, rotting_after_days integer, wip_limit integer, color text, icon text default null)
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
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "probability", "rotting_after_days", "wip_limit", "color", "icon", "rank")
      values (v_tenant, save_pipeline_stage.pipeline, save_pipeline_stage.key, save_pipeline_stage.name, save_pipeline_stage.category, v_outcome, save_pipeline_stage.probability, save_pipeline_stage.rotting_after_days, save_pipeline_stage.wip_limit, save_pipeline_stage.color, save_pipeline_stage.icon,
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
      update "better_supabase"."pipeline_stages" x set "key" = save_pipeline_stage.key, "name" = save_pipeline_stage.name, "category" = save_pipeline_stage.category, "outcome" = v_outcome, "probability" = save_pipeline_stage.probability, "rotting_after_days" = save_pipeline_stage.rotting_after_days, "wip_limit" = save_pipeline_stage.wip_limit, "color" = save_pipeline_stage.color, "icon" = save_pipeline_stage.icon, "updated_at" = now()
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
revoke execute on function "better_supabase"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text, text) from public, anon;
grant execute on function "better_supabase"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text, text) to authenticated, service_role;

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

-- Archives a stage. Records in it move to move_to, a stage of the same
-- pipeline; without move_to a stage that holds records is refused. The last
-- open stage of a pipeline stays.

create or replace function "better_supabase"."archive_pipeline_stage"(stage uuid, move_to uuid default null)
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
  v_to uuid := archive_pipeline_stage.move_to;
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
  if archive_pipeline_stage.move_to is not null then
    if archive_pipeline_stage.move_to = archive_pipeline_stage.stage or not exists (
      select 1 from "better_supabase"."pipeline_stages" x
      where x."id" = archive_pipeline_stage.move_to and x."pipeline_id" = v_pipeline and x."archived_at" is null
    ) then
      raise exception 'move_to must be another active stage of the same pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_REPLACEMENT_INVALID';
    end if;
  end if;
  if v_used and archive_pipeline_stage.move_to is null then
    raise exception 'records are in this stage; move them first or name a stage to move them to' using errcode = '23503', hint = 'PIPELINE_STAGE_IN_USE';
  end if;
  if v_outcome = 'open' and not exists (
    select 1 from "better_supabase"."pipeline_stages" x where x."pipeline_id" = v_pipeline and x."outcome" = 'open'
      and x."archived_at" is null and x."id" <> archive_pipeline_stage.stage
  ) then
    raise exception 'a pipeline keeps at least one open stage' using errcode = '23514', hint = 'PIPELINE_LAST_OPEN_STAGE';
  end if;
  if v_used then
    -- The stage trigger lets this one change through even where the allowed
    -- stage changes would not.
    perform set_config('better_supabase.lane_move', v_stage::text || ':' || v_to::text, true);
    null;
    perform set_config('better_supabase.lane_move', '', true);
  end if;
  update "better_supabase"."pipeline_stages" x set "archived_at" = now(), "updated_at" = now() where x."id" = archive_pipeline_stage.stage;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_pipeline_stage"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."archive_pipeline_stage"(uuid, uuid) to authenticated, service_role;

-- Restores an archived stage of an active pipeline.
create or replace function "better_supabase"."restore_pipeline_stage"(stage uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_pipeline uuid;
  v_pipeline_archived timestamptz;
  v_stage uuid := restore_pipeline_stage.stage;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."pipeline_id", y."archived_at"
    into v_tenant, v_pipeline, v_pipeline_archived
  from "better_supabase"."pipeline_stages" x join "better_supabase"."pipelines" y on y."id" = x."pipeline_id"
  where x."id" = restore_pipeline_stage.stage and x."archived_at" is not null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if v_pipeline_archived is not null then
    raise exception 'the pipeline of this stage is archived; restore the pipeline first' using errcode = '55000', hint = 'PIPELINE_NOT_FOUND';
  end if;
  update "better_supabase"."pipeline_stages" x set "archived_at" = null, "updated_at" = now() where x."id" = restore_pipeline_stage.stage;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."restore_pipeline_stage"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_pipeline_stage"(uuid) to authenticated, service_role;

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

-- The tenant's active pipelines as a keyset page, in board order (ADR 1077).
-- Runs with the caller's rights, so row level security decides what shows.
-- filters is { subjectType, key, scopeId (each a value or a list), search
-- (name, key), sort (rank, name, key), direction, facet, count, limit, after,
-- offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_pipelines"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_pipelines.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('subjectType') then
      raise exception 'facet is one of subjectType' using errcode = '22023', hint = 'PIPELINE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'subjectType' then (x."subject_type")::text end) as v
      from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or (x."key")::text = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or (x."key")::text = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('rank', 'name', 'key') then
    raise exception 'sort is one of rank, name, key' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) as j, jsonb_build_array((x."rank" collate "C")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or (x."key")::text = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."rank" collate "C", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."rank" collate "C" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) as j, jsonb_build_array((x."rank" collate "C")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or (x."key")::text = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."rank" collate "C" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) as j, jsonb_build_array((x."rank" collate "C")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or (x."key")::text = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."rank" collate "C", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."rank" collate "C" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) as j, jsonb_build_array((x."rank" collate "C")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or (x."key")::text = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."rank" collate "C" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or (x."key")::text = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or (x."key")::text = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or (x."key")::text = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or (x."key")::text = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or (x."key")::text = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_pipelines"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_pipelines"(uuid, jsonb) to authenticated, service_role;

-- One active pipeline with its active stages, or a not-found error.
create or replace function "better_supabase"."get_pipeline"(pipeline uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row jsonb;
begin
  select to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) into v_row from "better_supabase"."pipelines" x
  where x."id" = get_pipeline.pipeline and x."archived_at" is null;
  if v_row is null then
    raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
  end if;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."get_pipeline"(uuid) from public, anon;
grant execute on function "better_supabase"."get_pipeline"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."pipelines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."pipelines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."pipelines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."pipelines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."pipeline_stages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."pipeline_stages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."pipeline_stages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."pipeline_stages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."pipeline_transitions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."pipeline_transitions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."pipeline_transitions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."pipeline_transitions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."pipeline_stage_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('pipelines.read')) and coalesce("better_supabase"."can_subject"("better_supabase"."pipeline_stage_history"."subject_type", "better_supabase"."pipeline_stage_history"."subject_id", 'read'), false))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."pipeline_stage_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."pipeline_stage_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."pipeline_stage_history" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

-- ==== data supabase/better-supabase-data/900_better_supabase_092_pipelines.sql
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
