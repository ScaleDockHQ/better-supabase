-- better-supabase module: care-plans
-- @bsb-block care-plans@1 managed
-- @bsb-hash sha256:40bf6c8900e3a89313c4160afd676fa293fe9edae07311f4bdcb3e8ba5142a3f
-- Care plans per client: problems with codes from your code systems, goals and the actions that reach them, evaluations over time, one active plan per client published as a version, agreement through a signature, and restrictive measures that start only once approved.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."care_plans";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."care_plans";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."care_plans";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."care_plans";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."care_plans";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."care_plan_problems";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."care_plan_problems";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."care_plan_problems";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."care_plan_problems";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."care_plan_problems";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."care_plan_goals";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."care_plan_goals";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."care_plan_goals";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."care_plan_goals";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."care_plan_goals";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."care_plan_actions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."care_plan_actions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."care_plan_actions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."care_plan_actions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."care_plan_actions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."care_plan_evaluations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."care_plan_evaluations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."care_plan_evaluations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."care_plan_evaluations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."care_plan_evaluations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Care plans per client: problems, goals and the actions that reach them,
-- evaluated over time, published as one active plan per client, agreed
-- through a signature, with restrictive measures started only on approval.

create table if not exists "better_supabase"."care_plans" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- The client the plan is for: any registered subject type.
  "subject_type" text not null check (length("subject_type") between 1 and 63),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "title" text not null check (length("title") between 1 and 300),
  "status" text not null default 'draft' check ("status" in ('draft', 'active', 'archived')),
  -- 1 for a subject's first plan, one more for each plan after it.
  "version" integer not null default 1 check ("version" >= 1),
  "starts_on" date,
  "review_on" date,
  "owner_id" uuid,
  -- The signature request asking the client side to agree to the plan.
  "signature_id" uuid,
  "agreed_at" timestamptz,
  "published_version_id" uuid references "better_supabase"."versions" ("id") on delete set null,
  "published_at" timestamptz,
  "published_by" uuid,
  "archived_at" timestamptz,
  -- The review date due_care_plan_reviews last reported, so each date reports once.
  "review_notified_for" date,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  check ("status" = 'draft' or "published_at" is not null),
  check ("status" <> 'archived' or "archived_at" is not null)
);
create unique index if not exists "care_plans_active_key" on "better_supabase"."care_plans" ("subject_type", "subject_id") where "status" = 'active';
create index if not exists "care_plans_subject_idx" on "better_supabase"."care_plans" ("tenant_id", "subject_type", "subject_id", "version" desc);
create index if not exists "care_plans_review_idx" on "better_supabase"."care_plans" ("review_on") where "status" = 'active';
create index if not exists "care_plans_signature_idx" on "better_supabase"."care_plans" ("signature_id") where "signature_id" is not null;
create index if not exists "care_plans_version_idx" on "better_supabase"."care_plans" ("published_version_id") where "published_version_id" is not null;
alter table "better_supabase"."care_plans" enable row level security;
revoke all on "better_supabase"."care_plans" from public, anon, authenticated;
grant select on "better_supabase"."care_plans" to authenticated;
grant all on "better_supabase"."care_plans" to service_role;
drop policy if exists care_plans_read on "better_supabase"."care_plans";
create policy care_plans_read on "better_supabase"."care_plans"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('care_plans.read')) and coalesce("better_supabase"."can_subject"("better_supabase"."care_plans"."subject_type", "better_supabase"."care_plans"."subject_id"::text, 'read'), false));

create table if not exists "better_supabase"."care_plan_problems" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "plan_id" uuid not null,
  -- One of options.codeSystems, such as icnp or snomed; the functions check it.
  "code_system" text not null default 'custom' check (length("code_system") between 1 and 63),
  "code" text check ("code" is null or length("code") <= 100),
  "title" text not null check (length("title") between 1 and 300),
  "description" text check ("description" is null or length("description") <= 10000),
  "status" text not null default 'active' check ("status" in ('active', 'resolved')),
  "rank" text collate "C" not null default 'V' check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "plan_id", "id"),
  foreign key ("tenant_id", "plan_id") references "better_supabase"."care_plans" ("tenant_id", "id") on delete cascade
);
create index if not exists "care_plan_problems_plan_idx" on "better_supabase"."care_plan_problems" ("tenant_id", "plan_id", "rank");
alter table "better_supabase"."care_plan_problems" enable row level security;
revoke all on "better_supabase"."care_plan_problems" from public, anon, authenticated;
grant select on "better_supabase"."care_plan_problems" to authenticated;
grant all on "better_supabase"."care_plan_problems" to service_role;
drop policy if exists care_plan_problems_read on "better_supabase"."care_plan_problems";
create policy care_plan_problems_read on "better_supabase"."care_plan_problems"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."care_plans" x where x."id" = "better_supabase"."care_plan_problems"."plan_id"));

create table if not exists "better_supabase"."care_plan_goals" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "plan_id" uuid not null,
  "problem_id" uuid not null,
  "title" text not null check (length("title") between 1 and 300),
  "target_on" date,
  "status" text not null default 'planned' check ("status" in ('planned', 'in_progress', 'achieved', 'not_achieved', 'canceled')),
  -- How progress is measured, such as { "kind": "score", "target": 3 }.
  "measure" jsonb check ("measure" is null or jsonb_typeof("measure") = 'object'),
  "rank" text collate "C" not null default 'V' check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "plan_id", "id"),
  foreign key ("tenant_id", "plan_id", "problem_id") references "better_supabase"."care_plan_problems" ("tenant_id", "plan_id", "id") on delete cascade
);
create index if not exists "care_plan_goals_problem_idx" on "better_supabase"."care_plan_goals" ("tenant_id", "plan_id", "problem_id");
alter table "better_supabase"."care_plan_goals" enable row level security;
revoke all on "better_supabase"."care_plan_goals" from public, anon, authenticated;
grant select on "better_supabase"."care_plan_goals" to authenticated;
grant all on "better_supabase"."care_plan_goals" to service_role;
drop policy if exists care_plan_goals_read on "better_supabase"."care_plan_goals";
create policy care_plan_goals_read on "better_supabase"."care_plan_goals"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."care_plans" x where x."id" = "better_supabase"."care_plan_goals"."plan_id"));

create table if not exists "better_supabase"."care_plan_actions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "plan_id" uuid not null,
  "goal_id" uuid not null,
  "kind" text not null default 'intervention' check ("kind" in ('intervention', 'appointment', 'task', 'measure')),
  "title" text not null check (length("title") between 1 and 300),
  "instructions" text check ("instructions" is null or length("instructions") <= 10000),
  -- How often, such as { "every": "P1D", "times": ["08:00", "20:00"] }.
  "frequency" jsonb check ("frequency" is null or jsonb_typeof("frequency") = 'object'),
  -- The team role that carries the action out, such as nurse.
  "team_role" text check ("team_role" is null or length("team_role") <= 63),
  -- For a measure: one of options.measureKinds when it lists any.
  "measure_kind" text check ("measure_kind" is null or length("measure_kind") <= 63),
  -- The work item a task action created, with the tasks block.
  "task_id" uuid,
  -- The bookings series an appointment action placed.
  "booking_series_id" uuid,
  -- A measure always needs an approval before it starts.
  "requires_approval" boolean not null default false,
  "approval_id" uuid,
  "review_every" interval check ("review_every" is null or "review_every" > interval '0'),
  "reviewed_at" timestamptz,
  -- The review moment due_care_plan_reviews last reported.
  "review_notified_at" timestamptz,
  "starts_on" date,
  "ends_on" date,
  "status" text not null default 'planned' check ("status" in ('planned', 'active', 'ended')),
  "started_at" timestamptz,
  "ended_at" timestamptz,
  "end_reason" text check ("end_reason" is null or length("end_reason") <= 2000),
  "rank" text collate "C" not null default 'V' check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("kind" <> 'measure' or "requires_approval"),
  check ("ends_on" is null or "starts_on" is null or "ends_on" >= "starts_on"),
  foreign key ("tenant_id", "plan_id", "goal_id") references "better_supabase"."care_plan_goals" ("tenant_id", "plan_id", "id") on delete cascade
);
create index if not exists "care_plan_actions_goal_idx" on "better_supabase"."care_plan_actions" ("tenant_id", "plan_id", "goal_id");
create index if not exists "care_plan_actions_measure_idx" on "better_supabase"."care_plan_actions" ("tenant_id", "status") where "kind" = 'measure';
create index if not exists "care_plan_actions_approval_idx" on "better_supabase"."care_plan_actions" ("approval_id") where "approval_id" is not null;
create index if not exists "care_plan_actions_review_idx" on "better_supabase"."care_plan_actions" ("status") where "review_every" is not null;
alter table "better_supabase"."care_plan_actions" enable row level security;
revoke all on "better_supabase"."care_plan_actions" from public, anon, authenticated;
grant select on "better_supabase"."care_plan_actions" to authenticated;
grant all on "better_supabase"."care_plan_actions" to service_role;
drop policy if exists care_plan_actions_read on "better_supabase"."care_plan_actions";
create policy care_plan_actions_read on "better_supabase"."care_plan_actions"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."care_plans" x where x."id" = "better_supabase"."care_plan_actions"."plan_id"));

create table if not exists "better_supabase"."care_plan_evaluations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "plan_id" uuid not null,
  "goal_id" uuid not null,
  "evaluated_at" timestamptz not null default now(),
  -- The goal's status the evaluation found.
  "status" text not null check ("status" in ('planned', 'in_progress', 'achieved', 'not_achieved', 'canceled')),
  "outcome" text check ("outcome" is null or length("outcome") <= 10000),
  -- The forms submission that recorded the evaluation, if one did.
  "submission_id" uuid,
  "author_id" uuid,
  foreign key ("tenant_id", "plan_id", "goal_id") references "better_supabase"."care_plan_goals" ("tenant_id", "plan_id", "id") on delete cascade
);
create index if not exists "care_plan_evaluations_goal_idx" on "better_supabase"."care_plan_evaluations" ("tenant_id", "plan_id", "goal_id", "evaluated_at" desc);
alter table "better_supabase"."care_plan_evaluations" enable row level security;
revoke all on "better_supabase"."care_plan_evaluations" from public, anon, authenticated;
grant select on "better_supabase"."care_plan_evaluations" to authenticated;
grant all on "better_supabase"."care_plan_evaluations" to service_role;
drop policy if exists care_plan_evaluations_read on "better_supabase"."care_plan_evaluations";
create policy care_plan_evaluations_read on "better_supabase"."care_plan_evaluations"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."care_plans" x where x."id" = "better_supabase"."care_plan_evaluations"."plan_id"));


-- A plan with its problems, goals, actions and evaluations. The other
-- functions call it after their checks; it is not an entry point.
create or replace function "better_supabase"."care_plan_json"(plan_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'status', x."status", 'version', x."version", 'startsOn', x."starts_on", 'reviewOn', x."review_on", 'ownerId', x."owner_id", 'signatureRequestId', x."signature_id", 'agreedAt', x."agreed_at", 'publishedVersionId', x."published_version_id", 'publishedAt', x."published_at", 'publishedBy', x."published_by", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('problems', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'planId', y."plan_id", 'codeSystem', y."code_system", 'code', y."code", 'title', y."title", 'description', y."description", 'status', y."status", 'rank', y."rank", 'createdAt', y."created_at", 'updatedAt', y."updated_at") || jsonb_build_object('goals', coalesce((select jsonb_agg(jsonb_build_object('id', z."id", 'planId', z."plan_id", 'problemId', z."problem_id", 'title', z."title", 'targetOn', z."target_on", 'status', z."status", 'measure', z."measure", 'rank', z."rank", 'createdAt', z."created_at", 'updatedAt', z."updated_at") || jsonb_build_object('actions', coalesce((select jsonb_agg(jsonb_build_object('id', w."id", 'planId', w."plan_id", 'goalId', w."goal_id", 'kind', w."kind", 'title', w."title", 'instructions', w."instructions", 'frequency', w."frequency", 'teamRole', w."team_role", 'measureKind', w."measure_kind", 'taskId', w."task_id", 'bookingSeriesId', w."booking_series_id", 'requiresApproval', w."requires_approval", 'approvalId', w."approval_id", 'reviewEvery', case when w."review_every" is null then null else format('P%sY%sM%sDT%sH%sM%sS', extract(year from w."review_every")::int, extract(month from w."review_every")::int, extract(day from w."review_every")::int, extract(hour from w."review_every")::int, extract(minute from w."review_every")::int, trim_scale(extract(second from w."review_every"))) end, 'reviewedAt', w."reviewed_at", 'startsOn', w."starts_on", 'endsOn', w."ends_on", 'status', w."status", 'startedAt', w."started_at", 'endedAt', w."ended_at", 'endReason', w."end_reason", 'rank', w."rank", 'createdAt', w."created_at", 'updatedAt', w."updated_at") order by w."rank", w."created_at") from "better_supabase"."care_plan_actions" w where w."tenant_id" = z."tenant_id" and w."plan_id" = z."plan_id" and w."goal_id" = z."id"), '[]'::jsonb)) order by z."rank", z."created_at") from "better_supabase"."care_plan_goals" z where z."tenant_id" = y."tenant_id" and z."plan_id" = y."plan_id" and z."problem_id" = y."id"), '[]'::jsonb)) order by y."rank", y."created_at") from "better_supabase"."care_plan_problems" y where y."tenant_id" = x."tenant_id" and y."plan_id" = x."id"), '[]'::jsonb), 'evaluations', coalesce((select jsonb_agg(jsonb_build_object('id', v."id", 'planId', v."plan_id", 'goalId', v."goal_id", 'evaluatedAt', v."evaluated_at", 'status', v."status", 'outcome', v."outcome", 'submissionId', v."submission_id", 'authorId', v."author_id") order by v."evaluated_at" desc) from "better_supabase"."care_plan_evaluations" v where v."tenant_id" = x."tenant_id" and v."plan_id" = x."id"), '[]'::jsonb))
  from "better_supabase"."care_plans" x where x."id" = care_plan_json.plan_id
$$;
revoke execute on function "better_supabase"."care_plan_json"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."care_plan_json"(uuid) to service_role;

-- A draft plan for a client the caller can read: input is { subjectType,
-- subjectId, title, startsOn, reviewOn, ownerId, copyFromPlanId, fields }.
-- Its version is one more than the client's last plan. copyFromPlanId copies
-- the problems, goals and actions of an earlier plan of the same client.
create or replace function "better_supabase"."create_care_plan"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."care_plans";
  v_source "better_supabase"."care_plans";
  v_type text := nullif(trim(create_care_plan.input ->> 'subjectType'), '');
  v_id text := nullif(trim(create_care_plan.input ->> 'subjectId'), '');
  v_title text := trim(create_care_plan.input ->> 'title');
  v_version integer;
  v_problem "better_supabase"."care_plan_problems";
  v_goal "better_supabase"."care_plan_goals";
  v_new_problem uuid;
  v_new_goal uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_care_plan.tenant is not null and coalesce(better_supabase.can('tenant', create_care_plan.tenant, 'care_plans.write'), false))) then
    raise exception 'not allowed to write care plans' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if jsonb_typeof(create_care_plan.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if v_type is null or v_id is null then
    raise exception 'a care plan needs a subjectType and a subjectId' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(v_type, v_id, 'read'), false)) then
    raise exception 'not allowed to read this client' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a care plan needs a title of 1 to 300 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if create_care_plan.input ? 'reviewOn' and create_care_plan.input ? 'startsOn'
    and (create_care_plan.input ->> 'reviewOn')::date < (create_care_plan.input ->> 'startsOn')::date then
    raise exception 'reviewOn can''t be before startsOn' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if create_care_plan.input ? 'fields' and jsonb_typeof(create_care_plan.input -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if create_care_plan.input ? 'copyFromPlanId' then
    select * into v_source from "better_supabase"."care_plans" x
    where x."id" = (create_care_plan.input ->> 'copyFromPlanId')::uuid
      and x."tenant_id" = create_care_plan.tenant;
    if not found then
      raise exception 'no such care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
    end if;
    if v_source."subject_type" <> v_type or v_source."subject_id" <> v_id then
      raise exception 'copyFromPlanId must be a plan of the same client' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_care_plan_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_care_plan.tenant, create_care_plan.input;
    end if;
  end;
  perform pg_advisory_xact_lock(hashtextextended('care_plan:' || v_type || ':' || v_id, 0));
  select coalesce(max(x."version"), 0) + 1 into v_version from "better_supabase"."care_plans" x
  where x."subject_type" = v_type and x."subject_id" = v_id;
  insert into "better_supabase"."care_plans" ("tenant_id", "subject_type", "subject_id", "title", "version", "starts_on", "review_on", "owner_id", "created_by")
  values (create_care_plan.tenant, v_type, v_id, v_title, v_version,
    nullif(create_care_plan.input ->> 'startsOn', '')::date,
    nullif(create_care_plan.input ->> 'reviewOn', '')::date,
    nullif(create_care_plan.input ->> 'ownerId', '')::uuid, auth.uid())
  returning * into v_row;
  if v_source."id" is not null then
    for v_problem in
      select * from "better_supabase"."care_plan_problems" y where y."tenant_id" = v_source."tenant_id" and y."plan_id" = v_source."id"
      order by y."rank"
    loop
      insert into "better_supabase"."care_plan_problems" ("tenant_id", "plan_id", "code_system", "code", "title", "description", "status", "rank")
      values (v_row."tenant_id", v_row."id", v_problem."code_system", v_problem."code", v_problem."title", v_problem."description", v_problem."status", v_problem."rank")
      returning "id" into v_new_problem;
      for v_goal in
        select * from "better_supabase"."care_plan_goals" z where z."tenant_id" = v_problem."tenant_id" and z."plan_id" = v_problem."plan_id" and z."problem_id" = v_problem."id"
        order by z."rank"
      loop
        insert into "better_supabase"."care_plan_goals" ("tenant_id", "plan_id", "problem_id", "title", "target_on", "status", "measure", "rank")
        values (v_row."tenant_id", v_row."id", v_new_problem, v_goal."title", v_goal."target_on", v_goal."status", v_goal."measure", v_goal."rank")
        returning "id" into v_new_goal;
        -- Copies start over: planned, without the old plan's work item, approval or reviews.
        insert into "better_supabase"."care_plan_actions" ("tenant_id", "plan_id", "goal_id", "kind", "title", "instructions", "frequency", "team_role", "measure_kind", "booking_series_id", "requires_approval", "review_every", "starts_on", "ends_on", "rank")
        select v_row."tenant_id", v_row."id", v_new_goal, w."kind", w."title", w."instructions", w."frequency", w."team_role", w."measure_kind", w."booking_series_id", w."requires_approval", w."review_every", w."starts_on", w."ends_on", w."rank"
        from "better_supabase"."care_plan_actions" w
        where w."tenant_id" = v_goal."tenant_id" and w."plan_id" = v_goal."plan_id" and w."goal_id" = v_goal."id" and w."status" <> 'ended';
      end loop;
    end loop;
  end if;
  perform "better_supabase".emit_event('care_plan.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'title', v_row."title", 'status', v_row."status", 'version', v_row."version"), 'care-plans/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/care-plans');
  perform better_supabase.audit_event(
    event_type => 'care_plan.created',
    category => 'data',
    target_type => 'care_plan',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'care plan created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'title', v_row."title", 'status', v_row."status", 'version', v_row."version")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_care_plan_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return "better_supabase"."care_plan_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."create_care_plan"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_care_plan"(uuid, jsonb) to authenticated, service_role;

-- Changes a draft or active plan's title, dates, owner or extra fields.
create or replace function "better_supabase"."update_care_plan"(plan_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan "better_supabase"."care_plans";
  v_title text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_plan from "better_supabase"."care_plans" x where x."id" = update_care_plan.plan_id for update;
  if not found then
    raise exception 'no such care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_plan."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_plan."tenant_id", 'care_plans.write'), false))) then
    raise exception 'not allowed to change this care plan' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(v_plan."subject_type", v_plan."subject_id", 'read'), false)) then
    raise exception 'not allowed to read this client' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if v_plan."status" = 'archived' then
    raise exception 'the care plan is archived' using errcode = '55000', hint = 'CARE_PLAN_ARCHIVED';
  end if;
  if jsonb_typeof(update_care_plan.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  v_title := case when update_care_plan.changes ? 'title' then trim(update_care_plan.changes ->> 'title') else v_plan."title" end;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a care plan needs a title of 1 to 300 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if update_care_plan.changes ? 'reviewOn' and update_care_plan.changes ? 'startsOn'
    and (update_care_plan.changes ->> 'reviewOn')::date < (update_care_plan.changes ->> 'startsOn')::date then
    raise exception 'reviewOn can''t be before startsOn' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if update_care_plan.changes ? 'fields' and jsonb_typeof(update_care_plan.changes -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  update "better_supabase"."care_plans" x set
    "title" = v_title,
    "starts_on" = case when update_care_plan.changes ? 'startsOn' then nullif(update_care_plan.changes ->> 'startsOn', '')::date else x."starts_on" end,
    "review_on" = case when update_care_plan.changes ? 'reviewOn' then nullif(update_care_plan.changes ->> 'reviewOn', '')::date else x."review_on" end,
    "owner_id" = case when update_care_plan.changes ? 'ownerId' then nullif(update_care_plan.changes ->> 'ownerId', '')::uuid else x."owner_id" end,
    "updated_at" = now()
  where x."id" = v_plan."id"
  returning * into v_plan;
  if v_plan."review_on" < v_plan."starts_on" then
    raise exception 'reviewOn can''t be before startsOn' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  perform "better_supabase".emit_event('care_plan.updated', jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id", 'title', v_plan."title", 'status', v_plan."status", 'version', v_plan."version"), 'care-plans/' || v_plan."id"::text, (v_plan."tenant_id")::text, null, 'better-supabase/care-plans');
  perform better_supabase.audit_event(
    event_type => 'care_plan.updated',
    category => 'data',
    target_type => 'care_plan',
    record_id => v_plan."id"::text,
    target_label => v_plan."title",
    summary => 'care plan updated',
    tenant => (v_plan."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id", 'title', v_plan."title", 'status', v_plan."status", 'version', v_plan."version")
  );
  return "better_supabase"."care_plan_json"(v_plan."id");
end;
$$;
revoke execute on function "better_supabase"."update_care_plan"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_care_plan"(uuid, jsonb) to authenticated, service_role;

-- A problem on a draft plan: input is { codeSystem, code, title,
-- description, rank }. codeSystem is one of options.codeSystems (the first
-- when left out); new problems go last unless rank says where.
create or replace function "better_supabase"."add_care_plan_problem"(plan_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan "better_supabase"."care_plans";
  v_row "better_supabase"."care_plan_problems";
  v_system text;
  v_title text := trim(add_care_plan_problem.input ->> 'title');
  v_last text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_plan from "better_supabase"."care_plans" x where x."id" = add_care_plan_problem.plan_id for update;
  if not found then
    raise exception 'no such care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_plan."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_plan."tenant_id", 'care_plans.write'), false))) then
    raise exception 'not allowed to change this care plan' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(v_plan."subject_type", v_plan."subject_id", 'read'), false)) then
    raise exception 'not allowed to read this client' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if v_plan."status" = 'archived' then
    raise exception 'the care plan is archived' using errcode = '55000', hint = 'CARE_PLAN_ARCHIVED';
  end if;
  if v_plan."status" <> 'draft' then
    raise exception 'only a draft care plan changes this way' using errcode = '55000', hint = 'CARE_PLAN_NOT_DRAFT';
  end if;
  if jsonb_typeof(add_care_plan_problem.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  v_system := coalesce(nullif(add_care_plan_problem.input ->> 'codeSystem', ''), (array['custom']::text[])[1]);
  if not (v_system = any (array['custom']::text[])) then
    raise exception 'the code system is not one of options.codeSystems' using errcode = '22023', hint = 'CARE_PLAN_CODE_SYSTEM_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a problem needs a title of 1 to 300 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if length(add_care_plan_problem.input ->> 'code') > 100 then
    raise exception 'code is at most 100 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if length(add_care_plan_problem.input ->> 'description') > 10000 then
    raise exception 'description is at most 10000 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if add_care_plan_problem.input ? 'rank' and (add_care_plan_problem.input ->> 'rank') !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a rank key' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  select max(y."rank") into v_last from "better_supabase"."care_plan_problems" y
  where y."tenant_id" = v_plan."tenant_id" and y."plan_id" = v_plan."id";
  insert into "better_supabase"."care_plan_problems" ("tenant_id", "plan_id", "code_system", "code", "title", "description", "rank")
  values (v_plan."tenant_id", v_plan."id", v_system,
    nullif(trim(add_care_plan_problem.input ->> 'code'), ''), v_title,
    nullif(trim(add_care_plan_problem.input ->> 'description'), ''),
    coalesce(add_care_plan_problem.input ->> 'rank', case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end))
  returning * into v_row;
  update "better_supabase"."care_plans" x set "updated_at" = now() where x."id" = v_plan."id";
  return jsonb_build_object('id', v_row."id", 'planId', v_row."plan_id", 'codeSystem', v_row."code_system", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'status', v_row."status", 'rank', v_row."rank", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."add_care_plan_problem"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."add_care_plan_problem"(uuid, jsonb) to authenticated, service_role;

-- Changes a problem. On a draft plan every key of { codeSystem, code, title,
-- description, status, rank } changes; once the plan is active, only status
-- (active or resolved), which needs the evaluate permission.
create or replace function "better_supabase"."update_care_plan_problem"(problem_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan "better_supabase"."care_plans";
  v_row "better_supabase"."care_plan_problems";
  v_system text;
  v_title text;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."care_plan_problems" y where y."id" = update_care_plan_problem.problem_id;
  if not found then
    raise exception 'no such problem on a care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
  end if;
  if jsonb_typeof(update_care_plan_problem.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  select * into v_plan from "better_supabase"."care_plans" x where x."id" = v_row."plan_id" for update;
  if not found then
    raise exception 'no such care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_plan."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_plan."tenant_id", case when (update_care_plan_problem.changes - 'status') = '{}'::jsonb then 'care_plans.evaluate' else 'care_plans.write' end), false))) then
    raise exception 'not allowed to change this care plan' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(v_plan."subject_type", v_plan."subject_id", 'read'), false)) then
    raise exception 'not allowed to read this client' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if v_plan."status" = 'archived' then
    raise exception 'the care plan is archived' using errcode = '55000', hint = 'CARE_PLAN_ARCHIVED';
  end if;
  if v_plan."status" <> 'draft' and (update_care_plan_problem.changes - 'status') <> '{}'::jsonb then
    raise exception 'only a draft care plan changes this way' using errcode = '55000', hint = 'CARE_PLAN_NOT_DRAFT';
  end if;
  v_system := case when update_care_plan_problem.changes ? 'codeSystem' then update_care_plan_problem.changes ->> 'codeSystem' else v_row."code_system" end;
  if not (v_system = any (array['custom']::text[])) then
    raise exception 'the code system is not one of options.codeSystems' using errcode = '22023', hint = 'CARE_PLAN_CODE_SYSTEM_UNKNOWN';
  end if;
  v_title := case when update_care_plan_problem.changes ? 'title' then trim(update_care_plan_problem.changes ->> 'title') else v_row."title" end;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a problem needs a title of 1 to 300 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if length(update_care_plan_problem.changes ->> 'code') > 100 then
    raise exception 'code is at most 100 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if length(update_care_plan_problem.changes ->> 'description') > 10000 then
    raise exception 'description is at most 10000 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if update_care_plan_problem.changes ? 'rank' and (update_care_plan_problem.changes ->> 'rank') !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a rank key' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  v_status := case when update_care_plan_problem.changes ? 'status' then update_care_plan_problem.changes ->> 'status' else v_row."status" end;
  if v_status is null or v_status not in ('active', 'resolved') then
    raise exception 'status is active or resolved' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  update "better_supabase"."care_plan_problems" y set
    "code_system" = v_system,
    "code" = case when update_care_plan_problem.changes ? 'code' then nullif(trim(update_care_plan_problem.changes ->> 'code'), '') else y."code" end,
    "title" = v_title,
    "description" = case when update_care_plan_problem.changes ? 'description' then nullif(trim(update_care_plan_problem.changes ->> 'description'), '') else y."description" end,
    "status" = v_status,
    "rank" = coalesce(update_care_plan_problem.changes ->> 'rank', y."rank"),
    "updated_at" = now()
  where y."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."care_plans" x set "updated_at" = now() where x."id" = v_plan."id";
  return jsonb_build_object('id', v_row."id", 'planId', v_row."plan_id", 'codeSystem', v_row."code_system", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'status', v_row."status", 'rank', v_row."rank", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_care_plan_problem"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_care_plan_problem"(uuid, jsonb) to authenticated, service_role;

-- A goal for a problem on a draft plan: input is { title, targetOn,
-- measure, rank }. It starts planned.
create or replace function "better_supabase"."add_care_plan_goal"(problem_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan "better_supabase"."care_plans";
  v_problem "better_supabase"."care_plan_problems";
  v_row "better_supabase"."care_plan_goals";
  v_title text := trim(add_care_plan_goal.input ->> 'title');
  v_last text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_problem from "better_supabase"."care_plan_problems" y where y."id" = add_care_plan_goal.problem_id;
  if not found then
    raise exception 'no such problem on a care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
  end if;
  select * into v_plan from "better_supabase"."care_plans" x where x."id" = v_problem."plan_id" for update;
  if not found then
    raise exception 'no such care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_plan."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_plan."tenant_id", 'care_plans.write'), false))) then
    raise exception 'not allowed to change this care plan' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(v_plan."subject_type", v_plan."subject_id", 'read'), false)) then
    raise exception 'not allowed to read this client' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if v_plan."status" = 'archived' then
    raise exception 'the care plan is archived' using errcode = '55000', hint = 'CARE_PLAN_ARCHIVED';
  end if;
  if v_plan."status" <> 'draft' then
    raise exception 'only a draft care plan changes this way' using errcode = '55000', hint = 'CARE_PLAN_NOT_DRAFT';
  end if;
  if jsonb_typeof(add_care_plan_goal.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a goal needs a title of 1 to 300 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if add_care_plan_goal.input ? 'measure' and jsonb_typeof(add_care_plan_goal.input -> 'measure') not in ('object', 'null') then
    raise exception 'measure must be an object' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if add_care_plan_goal.input ? 'rank' and (add_care_plan_goal.input ->> 'rank') !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a rank key' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  select max(z."rank") into v_last from "better_supabase"."care_plan_goals" z
  where z."tenant_id" = v_problem."tenant_id" and z."plan_id" = v_problem."plan_id" and z."problem_id" = v_problem."id";
  insert into "better_supabase"."care_plan_goals" ("tenant_id", "plan_id", "problem_id", "title", "target_on", "measure", "rank")
  values (v_problem."tenant_id", v_problem."plan_id", v_problem."id", v_title,
    nullif(add_care_plan_goal.input ->> 'targetOn', '')::date,
    nullif(add_care_plan_goal.input -> 'measure', 'null'::jsonb),
    coalesce(add_care_plan_goal.input ->> 'rank', case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end))
  returning * into v_row;
  update "better_supabase"."care_plans" x set "updated_at" = now() where x."id" = v_plan."id";
  return jsonb_build_object('id', v_row."id", 'planId', v_row."plan_id", 'problemId', v_row."problem_id", 'title', v_row."title", 'targetOn', v_row."target_on", 'status', v_row."status", 'measure', v_row."measure", 'rank', v_row."rank", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."add_care_plan_goal"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."add_care_plan_goal"(uuid, jsonb) to authenticated, service_role;

-- Changes a goal. On a draft plan every key of { title, targetOn, measure,
-- status, rank } changes; once the plan is active, only status, which needs
-- the evaluate permission. A new status records care_plan_goal.status_changed.
create or replace function "better_supabase"."update_care_plan_goal"(goal_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan "better_supabase"."care_plans";
  v_row "better_supabase"."care_plan_goals";
  v_title text;
  v_status text;
  v_previous text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."care_plan_goals" z where z."id" = update_care_plan_goal.goal_id;
  if not found then
    raise exception 'no such goal on a care plan' using errcode = 'P0002', hint = 'CARE_PLAN_GOAL_NOT_FOUND';
  end if;
  if jsonb_typeof(update_care_plan_goal.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  select * into v_plan from "better_supabase"."care_plans" x where x."id" = v_row."plan_id" for update;
  if not found then
    raise exception 'no such care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_plan."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_plan."tenant_id", case when (update_care_plan_goal.changes - 'status') = '{}'::jsonb then 'care_plans.evaluate' else 'care_plans.write' end), false))) then
    raise exception 'not allowed to change this care plan' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(v_plan."subject_type", v_plan."subject_id", 'read'), false)) then
    raise exception 'not allowed to read this client' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if v_plan."status" = 'archived' then
    raise exception 'the care plan is archived' using errcode = '55000', hint = 'CARE_PLAN_ARCHIVED';
  end if;
  if v_plan."status" <> 'draft' and (update_care_plan_goal.changes - 'status') <> '{}'::jsonb then
    raise exception 'only a draft care plan changes this way' using errcode = '55000', hint = 'CARE_PLAN_NOT_DRAFT';
  end if;
  v_title := case when update_care_plan_goal.changes ? 'title' then trim(update_care_plan_goal.changes ->> 'title') else v_row."title" end;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a goal needs a title of 1 to 300 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if update_care_plan_goal.changes ? 'measure' and jsonb_typeof(update_care_plan_goal.changes -> 'measure') not in ('object', 'null') then
    raise exception 'measure must be an object' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if update_care_plan_goal.changes ? 'rank' and (update_care_plan_goal.changes ->> 'rank') !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a rank key' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  v_previous := v_row."status";
  v_status := case when update_care_plan_goal.changes ? 'status' then update_care_plan_goal.changes ->> 'status' else v_previous end;
  if v_status is null or v_status not in ('planned', 'in_progress', 'achieved', 'not_achieved', 'canceled') then
    raise exception 'status is planned, in_progress, achieved, not_achieved or canceled' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  update "better_supabase"."care_plan_goals" z set
    "title" = v_title,
    "target_on" = case when update_care_plan_goal.changes ? 'targetOn' then nullif(update_care_plan_goal.changes ->> 'targetOn', '')::date else z."target_on" end,
    "measure" = case when update_care_plan_goal.changes ? 'measure' then nullif(update_care_plan_goal.changes -> 'measure', 'null'::jsonb) else z."measure" end,
    "status" = v_status,
    "rank" = coalesce(update_care_plan_goal.changes ->> 'rank', z."rank"),
    "updated_at" = now()
  where z."id" = v_row."id"
  returning * into v_row;
  if v_status is distinct from v_previous then
    perform "better_supabase".emit_event('care_plan_goal.status_changed', jsonb_build_object('organizationId', v_plan."tenant_id", 'planId', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id") || jsonb_build_object('goalId', v_row."id", 'title', v_row."title", 'status', v_row."status", 'previousStatus', v_previous), 'care-plans/' || v_plan."id"::text, (v_plan."tenant_id")::text, null, 'better-supabase/care-plans');
  perform better_supabase.audit_event(
    event_type => 'care_plan_goal.status_changed',
    category => 'data',
    target_type => 'care_plan',
    record_id => v_plan."id"::text,
    target_label => v_plan."title",
    summary => 'care plan goal status changed',
    tenant => (v_plan."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_plan."tenant_id", 'planId', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id") || jsonb_build_object('goalId', v_row."id", 'title', v_row."title", 'status', v_row."status", 'previousStatus', v_previous)
  );
  end if;
  update "better_supabase"."care_plans" x set "updated_at" = now() where x."id" = v_plan."id";
  return jsonb_build_object('id', v_row."id", 'planId', v_row."plan_id", 'problemId', v_row."problem_id", 'title', v_row."title", 'targetOn', v_row."target_on", 'status', v_row."status", 'measure', v_row."measure", 'rank', v_row."rank", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_care_plan_goal"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_care_plan_goal"(uuid, jsonb) to authenticated, service_role;

-- An action toward a goal on a draft plan: input is { kind, title,
-- instructions, frequency, teamRole, measureKind, bookingSeriesId,
-- requiresApproval, reviewEvery, startsOn, endsOn, rank }. A measure always
-- requires an approval before it starts.
create or replace function "better_supabase"."add_care_plan_action"(goal_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan "better_supabase"."care_plans";
  v_goal "better_supabase"."care_plan_goals";
  v_row "better_supabase"."care_plan_actions";
  v_kind text := coalesce(nullif(add_care_plan_action.input ->> 'kind', ''), 'intervention');
  v_title text := trim(add_care_plan_action.input ->> 'title');
  v_measure_kind text := nullif(trim(add_care_plan_action.input ->> 'measureKind'), '');
  v_starts_on date := nullif(add_care_plan_action.input ->> 'startsOn', '')::date;
  v_ends_on date := nullif(add_care_plan_action.input ->> 'endsOn', '')::date;
  v_last text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_goal from "better_supabase"."care_plan_goals" z where z."id" = add_care_plan_action.goal_id;
  if not found then
    raise exception 'no such goal on a care plan' using errcode = 'P0002', hint = 'CARE_PLAN_GOAL_NOT_FOUND';
  end if;
  select * into v_plan from "better_supabase"."care_plans" x where x."id" = v_goal."plan_id" for update;
  if not found then
    raise exception 'no such care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_plan."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_plan."tenant_id", 'care_plans.write'), false))) then
    raise exception 'not allowed to change this care plan' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(v_plan."subject_type", v_plan."subject_id", 'read'), false)) then
    raise exception 'not allowed to read this client' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if v_plan."status" = 'archived' then
    raise exception 'the care plan is archived' using errcode = '55000', hint = 'CARE_PLAN_ARCHIVED';
  end if;
  if v_plan."status" <> 'draft' then
    raise exception 'only a draft care plan changes this way' using errcode = '55000', hint = 'CARE_PLAN_NOT_DRAFT';
  end if;
  if jsonb_typeof(add_care_plan_action.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'an action needs a title of 1 to 300 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if add_care_plan_action.input ? 'frequency' and jsonb_typeof(add_care_plan_action.input -> 'frequency') not in ('object', 'null') then
    raise exception 'frequency must be an object' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if add_care_plan_action.input ? 'rank' and (add_care_plan_action.input ->> 'rank') !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a rank key' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if length(add_care_plan_action.input ->> 'instructions') > 10000 then
    raise exception 'instructions is at most 10000 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if length(add_care_plan_action.input ->> 'teamRole') > 63 or length(add_care_plan_action.input ->> 'measureKind') > 63 then
    raise exception 'teamRole and measureKind are at most 63 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if v_kind is null or v_kind not in ('intervention', 'appointment', 'task', 'measure') then
    raise exception 'kind is intervention, appointment, task or measure' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if v_kind <> 'measure' and v_measure_kind is not null then
    raise exception 'only a measure has a measureKind' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if v_ends_on < v_starts_on then
    raise exception 'endsOn can''t be before startsOn' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  select max(w."rank") into v_last from "better_supabase"."care_plan_actions" w
  where w."tenant_id" = v_goal."tenant_id" and w."plan_id" = v_goal."plan_id" and w."goal_id" = v_goal."id";
  insert into "better_supabase"."care_plan_actions" ("tenant_id", "plan_id", "goal_id", "kind", "title", "instructions", "frequency", "team_role", "measure_kind", "booking_series_id", "requires_approval", "review_every", "starts_on", "ends_on", "rank")
  values (v_goal."tenant_id", v_goal."plan_id", v_goal."id", v_kind, v_title,
    nullif(trim(add_care_plan_action.input ->> 'instructions'), ''),
    nullif(add_care_plan_action.input -> 'frequency', 'null'::jsonb),
    nullif(trim(add_care_plan_action.input ->> 'teamRole'), ''),
    v_measure_kind,
    nullif(add_care_plan_action.input ->> 'bookingSeriesId', '')::uuid,
    v_kind = 'measure' or coalesce((add_care_plan_action.input ->> 'requiresApproval')::boolean, false),
    nullif(add_care_plan_action.input ->> 'reviewEvery', '')::interval,
    v_starts_on, v_ends_on,
    coalesce(add_care_plan_action.input ->> 'rank', case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end))
  returning * into v_row;
  update "better_supabase"."care_plans" x set "updated_at" = now() where x."id" = v_plan."id";
  return jsonb_build_object('id', v_row."id", 'planId', v_row."plan_id", 'goalId', v_row."goal_id", 'kind', v_row."kind", 'title', v_row."title", 'instructions', v_row."instructions", 'frequency', v_row."frequency", 'teamRole', v_row."team_role", 'measureKind', v_row."measure_kind", 'taskId', v_row."task_id", 'bookingSeriesId', v_row."booking_series_id", 'requiresApproval', v_row."requires_approval", 'approvalId', v_row."approval_id", 'reviewEvery', case when v_row."review_every" is null then null else format('P%sY%sM%sDT%sH%sM%sS', extract(year from v_row."review_every")::int, extract(month from v_row."review_every")::int, extract(day from v_row."review_every")::int, extract(hour from v_row."review_every")::int, extract(minute from v_row."review_every")::int, trim_scale(extract(second from v_row."review_every"))) end, 'reviewedAt', v_row."reviewed_at", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'endReason', v_row."end_reason", 'rank', v_row."rank", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
exception when check_violation then
  raise exception 'reviewEvery must be a positive interval' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
end;
$$;
revoke execute on function "better_supabase"."add_care_plan_action"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."add_care_plan_action"(uuid, jsonb) to authenticated, service_role;

-- Changes an action. On a draft plan every input key of add_care_plan_action
-- changes; once the plan is active, only how it runs: bookingSeriesId,
-- endsOn, frequency, instructions, reviewEvery and teamRole.
create or replace function "better_supabase"."update_care_plan_action"(action_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan "better_supabase"."care_plans";
  v_row "better_supabase"."care_plan_actions";
  v_kind text;
  v_title text;
  v_measure_kind text;
  v_starts_on date;
  v_ends_on date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."care_plan_actions" w where w."id" = update_care_plan_action.action_id;
  if not found then
    raise exception 'no such action on a care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
  end if;
  if jsonb_typeof(update_care_plan_action.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  select * into v_plan from "better_supabase"."care_plans" x where x."id" = v_row."plan_id" for update;
  if not found then
    raise exception 'no such care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_plan."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_plan."tenant_id", 'care_plans.write'), false))) then
    raise exception 'not allowed to change this care plan' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(v_plan."subject_type", v_plan."subject_id", 'read'), false)) then
    raise exception 'not allowed to read this client' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if v_plan."status" = 'archived' then
    raise exception 'the care plan is archived' using errcode = '55000', hint = 'CARE_PLAN_ARCHIVED';
  end if;
  if v_plan."status" <> 'draft' and (update_care_plan_action.changes - '{bookingSeriesId,endsOn,frequency,instructions,reviewEvery,teamRole}'::text[]) <> '{}'::jsonb then
    raise exception 'only a draft care plan changes this way' using errcode = '55000', hint = 'CARE_PLAN_NOT_DRAFT';
  end if;
  if v_row."status" = 'ended' then
    raise exception 'the action has ended' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  v_kind := case when update_care_plan_action.changes ? 'kind' then update_care_plan_action.changes ->> 'kind' else v_row."kind" end;
  v_title := case when update_care_plan_action.changes ? 'title' then trim(update_care_plan_action.changes ->> 'title') else v_row."title" end;
  v_measure_kind := case when update_care_plan_action.changes ? 'measureKind' then nullif(trim(update_care_plan_action.changes ->> 'measureKind'), '') else v_row."measure_kind" end;
  v_starts_on := case when update_care_plan_action.changes ? 'startsOn' then nullif(update_care_plan_action.changes ->> 'startsOn', '')::date else v_row."starts_on" end;
  v_ends_on := case when update_care_plan_action.changes ? 'endsOn' then nullif(update_care_plan_action.changes ->> 'endsOn', '')::date else v_row."ends_on" end;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'an action needs a title of 1 to 300 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if update_care_plan_action.changes ? 'frequency' and jsonb_typeof(update_care_plan_action.changes -> 'frequency') not in ('object', 'null') then
    raise exception 'frequency must be an object' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if update_care_plan_action.changes ? 'rank' and (update_care_plan_action.changes ->> 'rank') !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a rank key' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if length(update_care_plan_action.changes ->> 'instructions') > 10000 then
    raise exception 'instructions is at most 10000 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if length(update_care_plan_action.changes ->> 'teamRole') > 63 or length(update_care_plan_action.changes ->> 'measureKind') > 63 then
    raise exception 'teamRole and measureKind are at most 63 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if v_kind is null or v_kind not in ('intervention', 'appointment', 'task', 'measure') then
    raise exception 'kind is intervention, appointment, task or measure' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if v_kind <> 'measure' and v_measure_kind is not null then
    raise exception 'only a measure has a measureKind' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if v_ends_on < v_starts_on then
    raise exception 'endsOn can''t be before startsOn' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  update "better_supabase"."care_plan_actions" w set
    "kind" = v_kind,
    "title" = v_title,
    "instructions" = case when update_care_plan_action.changes ? 'instructions' then nullif(trim(update_care_plan_action.changes ->> 'instructions'), '') else w."instructions" end,
    "frequency" = case when update_care_plan_action.changes ? 'frequency' then nullif(update_care_plan_action.changes -> 'frequency', 'null'::jsonb) else w."frequency" end,
    "team_role" = case when update_care_plan_action.changes ? 'teamRole' then nullif(trim(update_care_plan_action.changes ->> 'teamRole'), '') else w."team_role" end,
    "measure_kind" = v_measure_kind,
    "booking_series_id" = case when update_care_plan_action.changes ? 'bookingSeriesId' then nullif(update_care_plan_action.changes ->> 'bookingSeriesId', '')::uuid else w."booking_series_id" end,
    "requires_approval" = v_kind = 'measure' or case when update_care_plan_action.changes ? 'requiresApproval' then coalesce((update_care_plan_action.changes ->> 'requiresApproval')::boolean, false) else w."requires_approval" end,
    "review_every" = case when update_care_plan_action.changes ? 'reviewEvery' then nullif(update_care_plan_action.changes ->> 'reviewEvery', '')::interval else w."review_every" end,
    "starts_on" = v_starts_on,
    "ends_on" = v_ends_on,
    "rank" = coalesce(update_care_plan_action.changes ->> 'rank', w."rank"),
    "updated_at" = now()
  where w."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."care_plans" x set "updated_at" = now() where x."id" = v_plan."id";
  return jsonb_build_object('id', v_row."id", 'planId', v_row."plan_id", 'goalId', v_row."goal_id", 'kind', v_row."kind", 'title', v_row."title", 'instructions', v_row."instructions", 'frequency', v_row."frequency", 'teamRole', v_row."team_role", 'measureKind', v_row."measure_kind", 'taskId', v_row."task_id", 'bookingSeriesId', v_row."booking_series_id", 'requiresApproval', v_row."requires_approval", 'approvalId', v_row."approval_id", 'reviewEvery', case when v_row."review_every" is null then null else format('P%sY%sM%sDT%sH%sM%sS', extract(year from v_row."review_every")::int, extract(month from v_row."review_every")::int, extract(day from v_row."review_every")::int, extract(hour from v_row."review_every")::int, extract(minute from v_row."review_every")::int, trim_scale(extract(second from v_row."review_every"))) end, 'reviewedAt', v_row."reviewed_at", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'endReason', v_row."end_reason", 'rank', v_row."rank", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
exception when check_violation then
  raise exception 'reviewEvery must be a positive interval' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
end;
$$;
revoke execute on function "better_supabase"."update_care_plan_action"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_care_plan_action"(uuid, jsonb) to authenticated, service_role;

-- A plan with its problems, goals, actions and evaluations, for a caller
-- who reads plans and the client, or a guest with options.guestRead.
create or replace function "better_supabase"."get_care_plan"(plan_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."care_plans";
begin
  select * into v_row from "better_supabase"."care_plans" x where x."id" = get_care_plan.plan_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(v_row."subject_type", v_row."subject_id", 'read'), false))) then
    raise exception 'no such care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
  end if;
  return "better_supabase"."care_plan_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."get_care_plan"(uuid) from public, anon;
grant execute on function "better_supabase"."get_care_plan"(uuid) to authenticated, service_role;

-- A client's plans the caller reads, the newest version first, without
-- their problems. include_archived adds the archived ones.
create or replace function "better_supabase"."list_care_plans"(subject_type text, subject_id text, include_archived boolean default false)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'status', x."status", 'version', x."version", 'startsOn', x."starts_on", 'reviewOn', x."review_on", 'ownerId', x."owner_id", 'signatureRequestId', x."signature_id", 'agreedAt', x."agreed_at", 'publishedVersionId', x."published_version_id", 'publishedAt', x."published_at", 'publishedBy', x."published_by", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."version" desc), '[]'::jsonb)
  from "better_supabase"."care_plans" x
  where x."subject_type" = list_care_plans.subject_type
    and x."subject_id" = list_care_plans.subject_id
    and (list_care_plans.include_archived or x."status" <> 'archived')
    and ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
$$;
revoke execute on function "better_supabase"."list_care_plans"(text, text, boolean) from public, anon;
grant execute on function "better_supabase"."list_care_plans"(text, text, boolean) to authenticated, service_role;


-- Asks approvals to start a measure, under the organization's policy for
-- care_plan_action start or the default one: a holder of the manage permission.
create or replace function "better_supabase"."care_plan_action_request_approval"(action_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."care_plan_actions";
  v_payload jsonb;
  v_approval jsonb;
begin
  select * into v_row from "better_supabase"."care_plan_actions" w where w."id" = care_plan_action_request_approval.action_id;
  v_payload := jsonb_build_object('planId', v_row."plan_id", 'kind', v_row."kind", 'measureKind', v_row."measure_kind", 'title', v_row."title");
  v_approval := "better_supabase"."open_approval"(
    v_row."tenant_id", 'care_plan_action', v_row."id"::text, 'start',
    coalesce("better_supabase"."approval_effective_policy"(v_row."tenant_id", 'care_plan_action', 'start', v_payload), '{"steps":[{"approvers":{"permission":"care_plans.manage"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb),
    null, v_payload
  );
  update "better_supabase"."care_plan_actions" w set "approval_id" = (v_approval ->> 'id')::uuid, "updated_at" = now()
  where w."id" = v_row."id";
  return (v_approval ->> 'id')::uuid;
end;
$$;
revoke execute on function "better_supabase"."care_plan_action_request_approval"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."care_plan_action_request_approval"(uuid) to service_role;

-- Starts a planned action of an active plan: a task action creates its work
-- item (tasks block). The other functions call it after their checks.
create or replace function "better_supabase"."care_plan_action_start"(action_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."care_plan_actions";
  v_plan "better_supabase"."care_plans";
  v_task jsonb;
begin
  update "better_supabase"."care_plan_actions" w set "status" = 'active', "started_at" = now(), "updated_at" = now()
  where w."id" = care_plan_action_start.action_id and w."status" = 'planned'
  returning * into v_row;
  if not found then
    return;
  end if;
  select * into v_plan from "better_supabase"."care_plans" x where x."id" = v_row."plan_id";
  if v_row."kind" = 'task' and v_row."task_id" is null then
    v_task := "better_supabase"."create_work_item"(v_row."tenant_id",
      jsonb_strip_nulls(jsonb_build_object('title', v_row."title", 'body', v_row."instructions")),
      case when v_plan."owner_id" is null then '{}'::uuid[] else array[v_plan."owner_id"] end);
    update "better_supabase"."care_plan_actions" w set "task_id" = (v_task ->> 'id')::uuid where w."id" = v_row."id";
  end if;
  perform "better_supabase".emit_event('care_plan_action.started', jsonb_build_object('organizationId', v_plan."tenant_id", 'planId', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id") || jsonb_build_object('actionId', v_row."id", 'kind', v_row."kind", 'title', v_row."title"), 'care-plans/' || v_plan."id"::text, (v_plan."tenant_id")::text, null, 'better-supabase/care-plans');
  perform better_supabase.audit_event(
    event_type => 'care_plan_action.started',
    category => 'data',
    target_type => 'care_plan',
    record_id => v_plan."id"::text,
    target_label => v_plan."title",
    summary => 'care plan action started',
    tenant => (v_plan."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_plan."tenant_id", 'planId', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id") || jsonb_build_object('actionId', v_row."id", 'kind', v_row."kind", 'title', v_row."title")
  );
end;
$$;
revoke execute on function "better_supabase"."care_plan_action_start"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."care_plan_action_start"(uuid) to service_role;

-- Ends an action that hasn't ended. The other functions call it after their checks.
create or replace function "better_supabase"."care_plan_action_end"(action_id uuid, reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."care_plan_actions";
  v_plan "better_supabase"."care_plans";
begin
  update "better_supabase"."care_plan_actions" w set "status" = 'ended', "ended_at" = now(), "end_reason" = care_plan_action_end.reason, "updated_at" = now()
  where w."id" = care_plan_action_end.action_id and w."status" <> 'ended'
  returning * into v_row;
  if not found then
    return;
  end if;
  select * into v_plan from "better_supabase"."care_plans" x where x."id" = v_row."plan_id";
  perform "better_supabase".emit_event('care_plan_action.ended', jsonb_build_object('organizationId', v_plan."tenant_id", 'planId', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id") || jsonb_build_object('actionId', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'reason', v_row."end_reason"), 'care-plans/' || v_plan."id"::text, (v_plan."tenant_id")::text, null, 'better-supabase/care-plans');
  perform better_supabase.audit_event(
    event_type => 'care_plan_action.ended',
    category => 'data',
    target_type => 'care_plan',
    record_id => v_plan."id"::text,
    target_label => v_plan."title",
    summary => 'care plan action ended',
    tenant => (v_plan."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_plan."tenant_id", 'planId', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id") || jsonb_build_object('actionId', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'reason', v_row."end_reason")
  );
end;
$$;
revoke execute on function "better_supabase"."care_plan_action_end"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."care_plan_action_end"(uuid, text) to service_role;

-- Starts a measure once its approval is final. Approvals calls it; it isn't
-- granted to anyone.
create or replace function "better_supabase"."care_plan_action_approved"(action_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from "better_supabase"."care_plan_actions" w join "better_supabase"."care_plans" x on x."id" = w."plan_id"
    where w."id" = care_plan_action_approved.action_id and x."status" = 'active'
  ) then
    perform "better_supabase"."care_plan_action_start"(care_plan_action_approved.action_id);
  end if;
end;
$$;
revoke execute on function "better_supabase"."care_plan_action_approved"(uuid) from public, anon, authenticated;

-- Starts a planned action of an active plan. An action that requires an
-- approval starts once approved; without an open or granted approval, this asks for one and returns the action still planned.
create or replace function "better_supabase"."start_care_plan_action"(action_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."care_plan_actions";
  v_plan "better_supabase"."care_plans";
  v_status text;
begin
  select * into v_row from "better_supabase"."care_plan_actions" w where w."id" = start_care_plan_action.action_id for update;
  if not found then
    raise exception 'no such action on a care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
  end if;
  select * into v_plan from "better_supabase"."care_plans" x where x."id" = v_row."plan_id" for update;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_plan."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_plan."tenant_id", 'care_plans.write'), false))) then
    raise exception 'not allowed to change this care plan' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(v_plan."subject_type", v_plan."subject_id", 'read'), false)) then
    raise exception 'not allowed to read this client' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if v_plan."status" <> 'active' then
    raise exception 'only an active care plan does this' using errcode = '55000', hint = 'CARE_PLAN_INVALID';
  end if;
  if v_row."status" <> 'planned' then
    raise exception 'only a planned action starts' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if v_row."requires_approval" then
    select x."status" into v_status
    from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
    if v_status = 'pending' then
      raise exception 'the action waits for its approval' using errcode = '55000', hint = 'CARE_PLAN_ACTION_APPROVAL_REQUIRED';
    end if;
    if v_status is distinct from 'approved' then
      perform "better_supabase"."care_plan_action_request_approval"(v_row."id");
      select * into v_row from "better_supabase"."care_plan_actions" w where w."id" = v_row."id";
      return jsonb_build_object('id', v_row."id", 'planId', v_row."plan_id", 'goalId', v_row."goal_id", 'kind', v_row."kind", 'title', v_row."title", 'instructions', v_row."instructions", 'frequency', v_row."frequency", 'teamRole', v_row."team_role", 'measureKind', v_row."measure_kind", 'taskId', v_row."task_id", 'bookingSeriesId', v_row."booking_series_id", 'requiresApproval', v_row."requires_approval", 'approvalId', v_row."approval_id", 'reviewEvery', case when v_row."review_every" is null then null else format('P%sY%sM%sDT%sH%sM%sS', extract(year from v_row."review_every")::int, extract(month from v_row."review_every")::int, extract(day from v_row."review_every")::int, extract(hour from v_row."review_every")::int, extract(minute from v_row."review_every")::int, trim_scale(extract(second from v_row."review_every"))) end, 'reviewedAt', v_row."reviewed_at", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'endReason', v_row."end_reason", 'rank', v_row."rank", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
    end if;
  end if;
  perform "better_supabase"."care_plan_action_start"(v_row."id");
  select * into v_row from "better_supabase"."care_plan_actions" w where w."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'planId', v_row."plan_id", 'goalId', v_row."goal_id", 'kind', v_row."kind", 'title', v_row."title", 'instructions', v_row."instructions", 'frequency', v_row."frequency", 'teamRole', v_row."team_role", 'measureKind', v_row."measure_kind", 'taskId', v_row."task_id", 'bookingSeriesId', v_row."booking_series_id", 'requiresApproval', v_row."requires_approval", 'approvalId', v_row."approval_id", 'reviewEvery', case when v_row."review_every" is null then null else format('P%sY%sM%sDT%sH%sM%sS', extract(year from v_row."review_every")::int, extract(month from v_row."review_every")::int, extract(day from v_row."review_every")::int, extract(hour from v_row."review_every")::int, extract(minute from v_row."review_every")::int, trim_scale(extract(second from v_row."review_every"))) end, 'reviewedAt', v_row."reviewed_at", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'endReason', v_row."end_reason", 'rank', v_row."rank", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."start_care_plan_action"(uuid) from public, anon;
grant execute on function "better_supabase"."start_care_plan_action"(uuid) to authenticated, service_role;

-- Ends an action of a draft or active plan, with an optional reason.
create or replace function "better_supabase"."end_care_plan_action"(action_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."care_plan_actions";
  v_plan "better_supabase"."care_plans";
begin
  select * into v_row from "better_supabase"."care_plan_actions" w where w."id" = end_care_plan_action.action_id for update;
  if not found then
    raise exception 'no such action on a care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
  end if;
  select * into v_plan from "better_supabase"."care_plans" x where x."id" = v_row."plan_id" for update;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_plan."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_plan."tenant_id", 'care_plans.write'), false))) then
    raise exception 'not allowed to change this care plan' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(v_plan."subject_type", v_plan."subject_id", 'read'), false)) then
    raise exception 'not allowed to read this client' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if v_plan."status" = 'archived' then
    raise exception 'the care plan is archived' using errcode = '55000', hint = 'CARE_PLAN_ARCHIVED';
  end if;
  if v_row."status" = 'ended' then
    raise exception 'the action has already ended' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if length(end_care_plan_action.reason) > 2000 then
    raise exception 'reason is at most 2000 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  perform "better_supabase"."care_plan_action_end"(v_row."id", nullif(trim(end_care_plan_action.reason), ''));
  select * into v_row from "better_supabase"."care_plan_actions" w where w."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'planId', v_row."plan_id", 'goalId', v_row."goal_id", 'kind', v_row."kind", 'title', v_row."title", 'instructions', v_row."instructions", 'frequency', v_row."frequency", 'teamRole', v_row."team_role", 'measureKind', v_row."measure_kind", 'taskId', v_row."task_id", 'bookingSeriesId', v_row."booking_series_id", 'requiresApproval', v_row."requires_approval", 'approvalId', v_row."approval_id", 'reviewEvery', case when v_row."review_every" is null then null else format('P%sY%sM%sDT%sH%sM%sS', extract(year from v_row."review_every")::int, extract(month from v_row."review_every")::int, extract(day from v_row."review_every")::int, extract(hour from v_row."review_every")::int, extract(minute from v_row."review_every")::int, trim_scale(extract(second from v_row."review_every"))) end, 'reviewedAt', v_row."reviewed_at", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'endReason', v_row."end_reason", 'rank', v_row."rank", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."end_care_plan_action"(uuid, text) from public, anon;
grant execute on function "better_supabase"."end_care_plan_action"(uuid, text) to authenticated, service_role;

-- Records that an active action was reviewed, which restarts its
-- reviewEvery clock.
create or replace function "better_supabase"."review_care_plan_action"(action_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."care_plan_actions";
  v_plan "better_supabase"."care_plans";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."care_plan_actions" w where w."id" = review_care_plan_action.action_id for update;
  if not found then
    raise exception 'no such action on a care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
  end if;
  select * into v_plan from "better_supabase"."care_plans" x where x."id" = v_row."plan_id" for update;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_plan."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_plan."tenant_id", 'care_plans.evaluate'), false))) then
    raise exception 'not allowed to change this care plan' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(v_plan."subject_type", v_plan."subject_id", 'read'), false)) then
    raise exception 'not allowed to read this client' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'only an active action is reviewed' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if length(review_care_plan_action.note) > 2000 then
    raise exception 'note is at most 2000 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  update "better_supabase"."care_plan_actions" w set "reviewed_at" = now(), "updated_at" = now()
  where w."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('care_plan_action.reviewed', jsonb_build_object('organizationId', v_plan."tenant_id", 'planId', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id") || jsonb_build_object('actionId', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'note', review_care_plan_action.note), 'care-plans/' || v_plan."id"::text, (v_plan."tenant_id")::text, null, 'better-supabase/care-plans');
  perform better_supabase.audit_event(
    event_type => 'care_plan_action.reviewed',
    category => 'data',
    target_type => 'care_plan',
    record_id => v_plan."id"::text,
    target_label => v_plan."title",
    summary => 'care plan action reviewed',
    tenant => (v_plan."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_plan."tenant_id", 'planId', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id") || jsonb_build_object('actionId', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'note', review_care_plan_action.note)
  );
  return jsonb_build_object('id', v_row."id", 'planId', v_row."plan_id", 'goalId', v_row."goal_id", 'kind', v_row."kind", 'title', v_row."title", 'instructions', v_row."instructions", 'frequency', v_row."frequency", 'teamRole', v_row."team_role", 'measureKind', v_row."measure_kind", 'taskId', v_row."task_id", 'bookingSeriesId', v_row."booking_series_id", 'requiresApproval', v_row."requires_approval", 'approvalId', v_row."approval_id", 'reviewEvery', case when v_row."review_every" is null then null else format('P%sY%sM%sDT%sH%sM%sS', extract(year from v_row."review_every")::int, extract(month from v_row."review_every")::int, extract(day from v_row."review_every")::int, extract(hour from v_row."review_every")::int, extract(minute from v_row."review_every")::int, trim_scale(extract(second from v_row."review_every"))) end, 'reviewedAt', v_row."reviewed_at", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'endReason', v_row."end_reason", 'rank', v_row."rank", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."review_care_plan_action"(uuid, text) from public, anon;
grant execute on function "better_supabase"."review_care_plan_action"(uuid, text) to authenticated, service_role;

-- Makes a draft plan the client's active plan: the plan in force before it
-- is archived and its actions end, the plan is snapshotted as a version
-- (versions block), and its actions start. An action that requires an
-- approval waits for it (approvals block).
create or replace function "better_supabase"."publish_care_plan"(plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."care_plans";
  v_previous "better_supabase"."care_plans";
  v_action "better_supabase"."care_plan_actions";
  v_version uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."care_plans" x where x."id" = publish_care_plan.plan_id for update;
  if not found then
    raise exception 'no such care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'care_plans.publish'), false))) then
    raise exception 'not allowed to publish care plans' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(v_row."subject_type", v_row."subject_id", 'read'), false)) then
    raise exception 'not allowed to read this client' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if v_row."status" = 'archived' then
    raise exception 'the care plan is archived' using errcode = '55000', hint = 'CARE_PLAN_ARCHIVED';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft care plan changes this way' using errcode = '55000', hint = 'CARE_PLAN_NOT_DRAFT';
  end if;
  if not exists (select 1 from "better_supabase"."care_plan_problems" y where y."plan_id" = v_row."id") then
    raise exception 'a care plan needs a problem before it is published' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_care_plan_publish"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select * into v_previous from "better_supabase"."care_plans" x
  where x."subject_type" = v_row."subject_type" and x."subject_id" = v_row."subject_id" and x."status" = 'active'
  for update;
  if found then
    update "better_supabase"."care_plans" x set "status" = 'archived', "archived_at" = now(), "updated_at" = now()
    where x."id" = v_previous."id"
    returning * into v_previous;
    for v_action in
      select * from "better_supabase"."care_plan_actions" w where w."plan_id" = v_previous."id" and w."status" <> 'ended'
    loop
      perform "better_supabase"."care_plan_action_end"(v_action."id", 'superseded');
    end loop;
    perform "better_supabase".emit_event('care_plan.archived', jsonb_build_object('organizationId', v_previous."tenant_id", 'id', v_previous."id", 'subjectType', v_previous."subject_type", 'subjectId', v_previous."subject_id", 'title', v_previous."title", 'status', v_previous."status", 'version', v_previous."version"), 'care-plans/' || v_previous."id"::text, (v_previous."tenant_id")::text, null, 'better-supabase/care-plans');
  perform better_supabase.audit_event(
    event_type => 'care_plan.archived',
    category => 'data',
    target_type => 'care_plan',
    record_id => v_previous."id"::text,
    target_label => v_previous."title",
    summary => 'care plan archived',
    tenant => (v_previous."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_previous."tenant_id", 'id', v_previous."id", 'subjectType', v_previous."subject_type", 'subjectId', v_previous."subject_id", 'title', v_previous."title", 'status', v_previous."status", 'version', v_previous."version")
  );
  end if;
  update "better_supabase"."care_plans" x set "status" = 'active', "published_at" = now(), "published_by" = auth.uid(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  v_version := ("better_supabase"."version_insert"(v_row."tenant_id", 'care_plan', v_row."id"::text,
    "better_supabase"."care_plan_json"(v_row."id") - 'status' - 'updatedAt' - 'signatureRequestId' - 'agreedAt' - 'evaluations',
    null, 'Version ' || v_row."version"::text, 'manual', true, auth.uid()) ->> 'id')::uuid;
  update "better_supabase"."care_plans" x set "published_version_id" = v_version where x."id" = v_row."id"
  returning * into v_row;
  for v_action in
    select * from "better_supabase"."care_plan_actions" w where w."plan_id" = v_row."id" and w."status" = 'planned'
    order by w."rank"
  loop
    if v_action."requires_approval" then
      perform "better_supabase"."care_plan_action_request_approval"(v_action."id");
    else
      perform "better_supabase"."care_plan_action_start"(v_action."id");
    end if;
  end loop;
  perform "better_supabase".emit_event('care_plan.published', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'title', v_row."title", 'status', v_row."status", 'version', v_row."version", 'previousPlanId', v_previous."id", 'versionId', v_version), 'care-plans/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/care-plans');
  perform better_supabase.audit_event(
    event_type => 'care_plan.published',
    category => 'data',
    target_type => 'care_plan',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'care plan published',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'title', v_row."title", 'status', v_row."status", 'version', v_row."version", 'previousPlanId', v_previous."id", 'versionId', v_version)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_care_plan_publish"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return "better_supabase"."care_plan_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."publish_care_plan"(uuid) from public, anon;
grant execute on function "better_supabase"."publish_care_plan"(uuid) to authenticated, service_role;

-- Archives a draft or active plan; its actions that haven't ended end.
create or replace function "better_supabase"."archive_care_plan"(plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."care_plans";
  v_action "better_supabase"."care_plan_actions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."care_plans" x where x."id" = archive_care_plan.plan_id for update;
  if not found then
    raise exception 'no such care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'care_plans.publish'), false))) then
    raise exception 'not allowed to archive care plans' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(v_row."subject_type", v_row."subject_id", 'read'), false)) then
    raise exception 'not allowed to read this client' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if v_row."status" = 'archived' then
    raise exception 'the care plan is archived' using errcode = '55000', hint = 'CARE_PLAN_ARCHIVED';
  end if;
  update "better_supabase"."care_plans" x set "status" = 'archived', "archived_at" = now(),
    "published_at" = coalesce(x."published_at", now()), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
    for v_action in
      select * from "better_supabase"."care_plan_actions" w where w."plan_id" = v_row."id" and w."status" <> 'ended'
    loop
      perform "better_supabase"."care_plan_action_end"(v_action."id", 'plan archived');
    end loop;
  perform "better_supabase".emit_event('care_plan.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'title', v_row."title", 'status', v_row."status", 'version', v_row."version"), 'care-plans/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/care-plans');
  perform better_supabase.audit_event(
    event_type => 'care_plan.archived',
    category => 'data',
    target_type => 'care_plan',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'care plan archived',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'title', v_row."title", 'status', v_row."status", 'version', v_row."version")
  );
  return "better_supabase"."care_plan_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."archive_care_plan"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_care_plan"(uuid) to authenticated, service_role;

-- Records an evaluation of a goal on an active plan: the status found, an
-- outcome and the forms submission it came from, if any. A status the goal
-- doesn't have yet becomes the goal's status.
create or replace function "better_supabase"."record_care_plan_evaluation"(goal_id uuid, status text, outcome text default null, submission_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan "better_supabase"."care_plans";
  v_goal "better_supabase"."care_plan_goals";
  v_row "better_supabase"."care_plan_evaluations";
  v_previous text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_goal from "better_supabase"."care_plan_goals" z where z."id" = record_care_plan_evaluation.goal_id for update;
  if not found then
    raise exception 'no such goal on a care plan' using errcode = 'P0002', hint = 'CARE_PLAN_GOAL_NOT_FOUND';
  end if;
  select * into v_plan from "better_supabase"."care_plans" x where x."id" = v_goal."plan_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_plan."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_plan."tenant_id", 'care_plans.evaluate'), false))) then
    raise exception 'not allowed to evaluate care plans' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(v_plan."subject_type", v_plan."subject_id", 'read'), false)) then
    raise exception 'not allowed to read this client' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if v_plan."status" <> 'active' then
    raise exception 'only an active care plan does this' using errcode = '55000', hint = 'CARE_PLAN_INVALID';
  end if;
  if record_care_plan_evaluation.status is null or record_care_plan_evaluation.status not in ('planned', 'in_progress', 'achieved', 'not_achieved', 'canceled') then
    raise exception 'status is planned, in_progress, achieved, not_achieved or canceled' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if length(record_care_plan_evaluation.outcome) > 10000 then
    raise exception 'outcome is at most 10000 characters' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_care_plan_evaluation_create"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_goal."id", record_care_plan_evaluation.status;
    end if;
  end;
  insert into "better_supabase"."care_plan_evaluations" ("tenant_id", "plan_id", "goal_id", "status", "outcome", "submission_id", "author_id")
  values (v_goal."tenant_id", v_goal."plan_id", v_goal."id", record_care_plan_evaluation.status,
    nullif(trim(record_care_plan_evaluation.outcome), ''), record_care_plan_evaluation.submission_id, auth.uid())
  returning * into v_row;
  v_previous := v_goal."status";
  if v_previous is distinct from record_care_plan_evaluation.status then
    update "better_supabase"."care_plan_goals" z set "status" = record_care_plan_evaluation.status, "updated_at" = now()
    where z."id" = v_goal."id"
    returning * into v_goal;
    perform "better_supabase".emit_event('care_plan_goal.status_changed', jsonb_build_object('organizationId', v_plan."tenant_id", 'planId', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id") || jsonb_build_object('goalId', v_goal."id", 'title', v_goal."title", 'status', v_goal."status", 'previousStatus', v_previous), 'care-plans/' || v_plan."id"::text, (v_plan."tenant_id")::text, null, 'better-supabase/care-plans');
  perform better_supabase.audit_event(
    event_type => 'care_plan_goal.status_changed',
    category => 'data',
    target_type => 'care_plan',
    record_id => v_plan."id"::text,
    target_label => v_plan."title",
    summary => 'care plan goal status changed',
    tenant => (v_plan."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_plan."tenant_id", 'planId', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id") || jsonb_build_object('goalId', v_goal."id", 'title', v_goal."title", 'status', v_goal."status", 'previousStatus', v_previous)
  );
  end if;
  perform "better_supabase".emit_event('care_plan_evaluation.created', jsonb_build_object('organizationId', v_plan."tenant_id", 'planId', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id") || jsonb_build_object('evaluationId', v_row."id", 'goalId', v_goal."id", 'status', v_row."status"), 'care-plans/' || v_plan."id"::text, (v_plan."tenant_id")::text, null, 'better-supabase/care-plans');
  perform better_supabase.audit_event(
    event_type => 'care_plan_evaluation.created',
    category => 'data',
    target_type => 'care_plan',
    record_id => v_plan."id"::text,
    target_label => v_plan."title",
    summary => 'care plan evaluation recorded',
    tenant => (v_plan."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_plan."tenant_id", 'planId', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id") || jsonb_build_object('evaluationId', v_row."id", 'goalId', v_goal."id", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_care_plan_evaluation_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'planId', v_row."plan_id", 'goalId', v_row."goal_id", 'evaluatedAt', v_row."evaluated_at", 'status', v_row."status", 'outcome', v_row."outcome", 'submissionId', v_row."submission_id", 'authorId', v_row."author_id");
end;
$$;
revoke execute on function "better_supabase"."record_care_plan_evaluation"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."record_care_plan_evaluation"(uuid, text, text, uuid) to authenticated, service_role;

-- The organization's restrictive measures with their plan and client, for a
-- register: active_only keeps the ones in force, the others add planned and
-- ended ones. Only plans the caller reads count.
create or replace function "better_supabase"."list_care_plan_measures"(tenant uuid, active_only boolean default true)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', w."id", 'planId', w."plan_id", 'goalId', w."goal_id", 'kind', w."kind", 'title', w."title", 'instructions', w."instructions", 'frequency', w."frequency", 'teamRole', w."team_role", 'measureKind', w."measure_kind", 'taskId', w."task_id", 'bookingSeriesId', w."booking_series_id", 'requiresApproval', w."requires_approval", 'approvalId', w."approval_id", 'reviewEvery', case when w."review_every" is null then null else format('P%sY%sM%sDT%sH%sM%sS', extract(year from w."review_every")::int, extract(month from w."review_every")::int, extract(day from w."review_every")::int, extract(hour from w."review_every")::int, extract(minute from w."review_every")::int, trim_scale(extract(second from w."review_every"))) end, 'reviewedAt', w."reviewed_at", 'startsOn', w."starts_on", 'endsOn', w."ends_on", 'status', w."status", 'startedAt', w."started_at", 'endedAt', w."ended_at", 'endReason', w."end_reason", 'rank', w."rank", 'createdAt', w."created_at", 'updatedAt', w."updated_at") || jsonb_build_object('planTitle', x."title", 'planStatus', x."status", 'subjectType', x."subject_type", 'subjectId', x."subject_id")
    order by w."started_at" desc nulls last, w."created_at" desc), '[]'::jsonb)
  from "better_supabase"."care_plan_actions" w
  join "better_supabase"."care_plans" x on x."id" = w."plan_id"
  where w."tenant_id" = list_care_plan_measures.tenant
    and w."kind" = 'measure'
    and (not list_care_plan_measures.active_only or w."status" = 'active')
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_care_plan_measures.tenant is not null and coalesce(better_supabase.can('tenant', list_care_plan_measures.tenant, 'care_plans.read'), false)))
    and ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
$$;
revoke execute on function "better_supabase"."list_care_plan_measures"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_care_plan_measures"(uuid, boolean) to authenticated, service_role;

-- Asks members who speak for the client (the client, a representative) to
-- agree to an active plan: a signature request with meaning agreed on the
-- published version. The caller also needs the signatures request
-- permission. Completing it records care_plan.agreed.
create or replace function "better_supabase"."request_care_plan_agreement"(plan_id uuid, signers uuid[], message text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan "better_supabase"."care_plans";
  v_request uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_plan from "better_supabase"."care_plans" x where x."id" = request_care_plan_agreement.plan_id for update;
  if not found then
    raise exception 'no such care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_plan."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_plan."tenant_id", 'care_plans.publish'), false))) then
    raise exception 'not allowed to ask for agreement to care plans' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(v_plan."subject_type", v_plan."subject_id", 'read'), false)) then
    raise exception 'not allowed to read this client' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if v_plan."status" <> 'active' then
    raise exception 'only an active care plan does this' using errcode = '55000', hint = 'CARE_PLAN_INVALID';
  end if;
  v_request := ("better_supabase"."create_signature_request"(
    v_plan."tenant_id", 'care_plan', v_plan."id"::text,
    request_care_plan_agreement.signers, v_plan."published_version_id",
    message => request_care_plan_agreement.message, meaning => 'agreed'
  ) ->> 'id')::uuid;
  update "better_supabase"."care_plans" x set "signature_id" = v_request, "agreed_at" = null, "updated_at" = now()
  where x."id" = v_plan."id"
  returning * into v_plan;
  perform "better_supabase".emit_event('care_plan.updated', jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id", 'title', v_plan."title", 'status', v_plan."status", 'version', v_plan."version"), 'care-plans/' || v_plan."id"::text, (v_plan."tenant_id")::text, null, 'better-supabase/care-plans');
  perform better_supabase.audit_event(
    event_type => 'care_plan.updated',
    category => 'data',
    target_type => 'care_plan',
    record_id => v_plan."id"::text,
    target_label => v_plan."title",
    summary => 'care plan agreement requested',
    tenant => (v_plan."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id", 'title', v_plan."title", 'status', v_plan."status", 'version', v_plan."version")
  );
  return "better_supabase"."care_plan_json"(v_plan."id");
end;
$$;
revoke execute on function "better_supabase"."request_care_plan_agreement"(uuid, uuid[], text) from public, anon;
grant execute on function "better_supabase"."request_care_plan_agreement"(uuid, uuid[], text) to authenticated, service_role;

-- A completed agreement request marks its plan agreed.
create or replace function "better_supabase"."care_plan_signature_settled"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."care_plans";
begin
  for v_row in
    update "better_supabase"."care_plans" x set "agreed_at" = now(), "updated_at" = now()
    where x."signature_id" = new."id"
    returning *
  loop
    perform "better_supabase".emit_event('care_plan.agreed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'title', v_row."title", 'status', v_row."status", 'version', v_row."version", 'signatureRequestId', v_row."signature_id"), 'care-plans/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/care-plans');
  perform better_supabase.audit_event(
    event_type => 'care_plan.agreed',
    category => 'data',
    target_type => 'care_plan',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'care plan agreed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'title', v_row."title", 'status', v_row."status", 'version', v_row."version", 'signatureRequestId', v_row."signature_id")
  );
  end loop;
  return new;
end;
$$;
revoke execute on function "better_supabase"."care_plan_signature_settled"() from public, anon, authenticated;
drop trigger if exists "bsb_care_plans_signature_settled" on "better_supabase"."signature_requests";
create trigger "bsb_care_plans_signature_settled" after update of "status" on "better_supabase"."signature_requests"
  for each row when (old."status" = 'pending' and new."status" = 'completed')
  execute function "better_supabase"."care_plan_signature_settled"();

-- Reports each active plan whose review date has come, once per date, and
-- each active action whose reviewEvery has lapsed since its last review,
-- once per lapse: a review_date_reached event and, with notifications, a notification
-- to the plan's owner. Run it daily from a job (the care-plans.reviews timer).
create or replace function "better_supabase"."due_care_plan_reviews"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plan "better_supabase"."care_plans"%rowtype;
  v_row "better_supabase"."care_plan_actions"%rowtype;
  v_due timestamptz;
  v_claims text;
  v_count integer := 0;
begin
  for v_plan in
    select * from "better_supabase"."care_plans" x
    where x."status" = 'active' and x."review_on" <= current_date
      and x."review_notified_for" is distinct from x."review_on"
    for update skip locked
  loop
    perform "better_supabase".emit_event('care_plan.review_date_reached', jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id", 'title', v_plan."title", 'status', v_plan."status", 'version', v_plan."version", 'ownerId', v_plan."owner_id", 'reviewOn', v_plan."review_on"), 'care-plans/' || v_plan."id"::text, (v_plan."tenant_id")::text, null, 'better-supabase/care-plans');
  perform better_supabase.audit_event(
    event_type => 'care_plan.review_date_reached',
    category => 'data',
    target_type => 'care_plan',
    record_id => v_plan."id"::text,
    target_label => v_plan."title",
    summary => 'care plan review due',
    tenant => (v_plan."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id", 'title', v_plan."title", 'status', v_plan."status", 'version', v_plan."version", 'ownerId', v_plan."owner_id", 'reviewOn', v_plan."review_on")
  );
    if v_plan."owner_id" is not null then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'care_plan.review_date_reached',
        'tenant', v_plan."tenant_id",
        'actor', null,
        'subject_type', 'care_plan',
        'subject_id', v_plan."id"::text,
        'summary', v_plan."title",
        'recipients', to_jsonb(array[v_plan."owner_id"]),
        'key', 'care_plan.review_date_reached:' || v_plan."id"::text || ':' || v_plan."review_on"::text,
        'data', jsonb_build_object('planId', v_plan."id", 'reviewOn', v_plan."review_on")
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    update "better_supabase"."care_plans" x set "review_notified_for" = v_plan."review_on" where x."id" = v_plan."id";
    v_count := v_count + 1;
  end loop;
  for v_row in
    select w.* from "better_supabase"."care_plan_actions" w
    join "better_supabase"."care_plans" x on x."id" = w."plan_id" and x."status" = 'active'
    where w."status" = 'active' and w."review_every" is not null
      and coalesce(w."reviewed_at", w."started_at") + w."review_every" <= now()
      and w."review_notified_at" is distinct from coalesce(w."reviewed_at", w."started_at") + w."review_every"
    for update of w skip locked
  loop
    v_due := coalesce(v_row."reviewed_at", v_row."started_at") + v_row."review_every";
    select * into v_plan from "better_supabase"."care_plans" x where x."id" = v_row."plan_id";
    perform "better_supabase".emit_event('care_plan_action.review_date_reached', jsonb_build_object('organizationId', v_plan."tenant_id", 'planId', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id") || jsonb_build_object('actionId', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'ownerId', v_plan."owner_id", 'dueAt', v_due), 'care-plans/' || v_plan."id"::text, (v_plan."tenant_id")::text, null, 'better-supabase/care-plans');
  perform better_supabase.audit_event(
    event_type => 'care_plan_action.review_date_reached',
    category => 'data',
    target_type => 'care_plan',
    record_id => v_plan."id"::text,
    target_label => v_plan."title",
    summary => 'care plan action review due',
    tenant => (v_plan."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_plan."tenant_id", 'planId', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id") || jsonb_build_object('actionId', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'ownerId', v_plan."owner_id", 'dueAt', v_due)
  );
    if v_plan."owner_id" is not null then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'care_plan_action.review_date_reached',
        'tenant', v_plan."tenant_id",
        'actor', null,
        'subject_type', 'care_plan',
        'subject_id', v_plan."id"::text,
        'summary', v_plan."title",
        'recipients', to_jsonb(array[v_plan."owner_id"]),
        'key', 'care_plan_action.review_date_reached:' || v_row."id"::text || ':' || v_due::text,
        'data', jsonb_build_object('planId', v_plan."id", 'actionId', v_row."id", 'dueAt', v_due)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    update "better_supabase"."care_plan_actions" w set "review_notified_at" = v_due where w."id" = v_row."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."due_care_plan_reviews"() from public, anon, authenticated;
grant execute on function "better_supabase"."due_care_plan_reviews"() to service_role;

-- Moves this module's rows from one subject record to another when
-- better_supabase.merge_subject_refs merges them.
create or replace function "better_supabase"."care_plans_subject_merge"(subject_table text, keep text, drop text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.messages' then array['message'] when 'better_supabase.conversations' then array['conversation'] when 'better_supabase.channels' then array['channel'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.courses' then array['course'] when 'better_supabase.posts' then array['post'] when 'better_supabase.activities' then array['activity'] when 'better_supabase.quotes' then array['quote'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.invoices' then array['invoice'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.orders' then array['order'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.bookings' then array['booking'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.leases' then array['lease'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.compliance_policies' then array['compliance_policy'] when 'better_supabase.qualification_types' then array['qualification_type'] when 'better_supabase.risks' then array['risk'] when 'better_supabase.cases' then array['case'] when 'better_supabase.inspections' then array['inspection'] when 'better_supabase.inspection_programs' then array['inspection_program'] when 'better_supabase.inspection_findings' then array['inspection_finding'] when 'better_supabase.forms' then array['form'] when 'better_supabase.production_orders' then array['production_order'] when 'better_supabase.work_centers' then array['work_center'] when 'better_supabase.bank_accounts' then array['bank_account'] when 'better_supabase.care_plans' then array['care_plan'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.content_entries' then array['content_entry'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.change_requests' then array['change_request'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."care_plans" x set "status" = 'archived', "archived_at" = now(), "updated_at" = now()
    where x."subject_type" = v_type and x."subject_id" = v_drop and x."status" = 'active'
      and exists (select 1 from "better_supabase"."care_plans" y where y."subject_type" = v_type and y."subject_id" = v_keep and y."status" = 'active');
    update "better_supabase"."care_plans" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."care_plans_subject_merge"(text, text, text) from public, anon, authenticated;
comment on function "better_supabase"."care_plans_subject_merge"(text, text, text) is 'better-supabase:subject-merge';

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
drop policy if exists bsb_tenant_scope on "better_supabase"."care_plans";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."care_plans";
create policy bsb_tenant_scope_select on "better_supabase"."care_plans" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('care_plans.read')) and coalesce("better_supabase"."can_subject"("better_supabase"."care_plans"."subject_type", "better_supabase"."care_plans"."subject_id"::text, 'read'), false))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."care_plans";
create policy bsb_tenant_scope_insert on "better_supabase"."care_plans" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."care_plans";
create policy bsb_tenant_scope_update on "better_supabase"."care_plans" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."care_plans";
create policy bsb_tenant_scope_delete on "better_supabase"."care_plans" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."care_plan_problems";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."care_plan_problems";
create policy bsb_tenant_scope_select on "better_supabase"."care_plan_problems" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."care_plans" x where x."id" = "better_supabase"."care_plan_problems"."plan_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."care_plan_problems";
create policy bsb_tenant_scope_insert on "better_supabase"."care_plan_problems" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."care_plan_problems";
create policy bsb_tenant_scope_update on "better_supabase"."care_plan_problems" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."care_plan_problems";
create policy bsb_tenant_scope_delete on "better_supabase"."care_plan_problems" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."care_plan_goals";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."care_plan_goals";
create policy bsb_tenant_scope_select on "better_supabase"."care_plan_goals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."care_plans" x where x."id" = "better_supabase"."care_plan_goals"."plan_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."care_plan_goals";
create policy bsb_tenant_scope_insert on "better_supabase"."care_plan_goals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."care_plan_goals";
create policy bsb_tenant_scope_update on "better_supabase"."care_plan_goals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."care_plan_goals";
create policy bsb_tenant_scope_delete on "better_supabase"."care_plan_goals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."care_plan_actions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."care_plan_actions";
create policy bsb_tenant_scope_select on "better_supabase"."care_plan_actions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."care_plans" x where x."id" = "better_supabase"."care_plan_actions"."plan_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."care_plan_actions";
create policy bsb_tenant_scope_insert on "better_supabase"."care_plan_actions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."care_plan_actions";
create policy bsb_tenant_scope_update on "better_supabase"."care_plan_actions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."care_plan_actions";
create policy bsb_tenant_scope_delete on "better_supabase"."care_plan_actions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."care_plan_evaluations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."care_plan_evaluations";
create policy bsb_tenant_scope_select on "better_supabase"."care_plan_evaluations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."care_plans" x where x."id" = "better_supabase"."care_plan_evaluations"."plan_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."care_plan_evaluations";
create policy bsb_tenant_scope_insert on "better_supabase"."care_plan_evaluations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."care_plan_evaluations";
create policy bsb_tenant_scope_update on "better_supabase"."care_plan_evaluations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."care_plan_evaluations";
create policy bsb_tenant_scope_delete on "better_supabase"."care_plan_evaluations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.care-plans.api: entry points for the Data API.
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

create or replace function "api"."care_plan_json"(plan_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."care_plan_json"($1) $$;
revoke execute on function "api"."care_plan_json"(uuid) from public, anon, authenticated;
grant execute on function "api"."care_plan_json"(uuid) to service_role;

create or replace function "api"."create_care_plan"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_care_plan"($1, $2) $$;
revoke execute on function "api"."create_care_plan"(uuid, jsonb) from public, anon;
grant execute on function "api"."create_care_plan"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."update_care_plan"(plan_id uuid, changes jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_care_plan"($1, $2) $$;
revoke execute on function "api"."update_care_plan"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_care_plan"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."add_care_plan_problem"(plan_id uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_care_plan_problem"($1, $2) $$;
revoke execute on function "api"."add_care_plan_problem"(uuid, jsonb) from public, anon;
grant execute on function "api"."add_care_plan_problem"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."update_care_plan_problem"(problem_id uuid, changes jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_care_plan_problem"($1, $2) $$;
revoke execute on function "api"."update_care_plan_problem"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_care_plan_problem"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."add_care_plan_goal"(problem_id uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_care_plan_goal"($1, $2) $$;
revoke execute on function "api"."add_care_plan_goal"(uuid, jsonb) from public, anon;
grant execute on function "api"."add_care_plan_goal"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."update_care_plan_goal"(goal_id uuid, changes jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_care_plan_goal"($1, $2) $$;
revoke execute on function "api"."update_care_plan_goal"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_care_plan_goal"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."add_care_plan_action"(goal_id uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_care_plan_action"($1, $2) $$;
revoke execute on function "api"."add_care_plan_action"(uuid, jsonb) from public, anon;
grant execute on function "api"."add_care_plan_action"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."update_care_plan_action"(action_id uuid, changes jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_care_plan_action"($1, $2) $$;
revoke execute on function "api"."update_care_plan_action"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_care_plan_action"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."get_care_plan"(plan_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_care_plan"($1) $$;
revoke execute on function "api"."get_care_plan"(uuid) from public, anon;
grant execute on function "api"."get_care_plan"(uuid) to authenticated, service_role;

create or replace function "api"."list_care_plans"(subject_type text, subject_id text, include_archived boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_care_plans"($1, $2, $3) $$;
revoke execute on function "api"."list_care_plans"(text, text, boolean) from public, anon;
grant execute on function "api"."list_care_plans"(text, text, boolean) to authenticated, service_role;

create or replace function "api"."care_plan_action_request_approval"(action_id uuid)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."care_plan_action_request_approval"($1) $$;
revoke execute on function "api"."care_plan_action_request_approval"(uuid) from public, anon, authenticated;
grant execute on function "api"."care_plan_action_request_approval"(uuid) to service_role;

create or replace function "api"."care_plan_action_start"(action_id uuid)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."care_plan_action_start"($1) $$;
revoke execute on function "api"."care_plan_action_start"(uuid) from public, anon, authenticated;
grant execute on function "api"."care_plan_action_start"(uuid) to service_role;

create or replace function "api"."care_plan_action_end"(action_id uuid, reason text)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."care_plan_action_end"($1, $2) $$;
revoke execute on function "api"."care_plan_action_end"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."care_plan_action_end"(uuid, text) to service_role;

create or replace function "api"."start_care_plan_action"(action_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."start_care_plan_action"($1) $$;
revoke execute on function "api"."start_care_plan_action"(uuid) from public, anon;
grant execute on function "api"."start_care_plan_action"(uuid) to authenticated, service_role;

create or replace function "api"."end_care_plan_action"(action_id uuid, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."end_care_plan_action"($1, $2) $$;
revoke execute on function "api"."end_care_plan_action"(uuid, text) from public, anon;
grant execute on function "api"."end_care_plan_action"(uuid, text) to authenticated, service_role;

create or replace function "api"."review_care_plan_action"(action_id uuid, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."review_care_plan_action"($1, $2) $$;
revoke execute on function "api"."review_care_plan_action"(uuid, text) from public, anon;
grant execute on function "api"."review_care_plan_action"(uuid, text) to authenticated, service_role;

create or replace function "api"."publish_care_plan"(plan_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."publish_care_plan"($1) $$;
revoke execute on function "api"."publish_care_plan"(uuid) from public, anon;
grant execute on function "api"."publish_care_plan"(uuid) to authenticated, service_role;

create or replace function "api"."archive_care_plan"(plan_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_care_plan"($1) $$;
revoke execute on function "api"."archive_care_plan"(uuid) from public, anon;
grant execute on function "api"."archive_care_plan"(uuid) to authenticated, service_role;

create or replace function "api"."record_care_plan_evaluation"(goal_id uuid, status text, outcome text default null, submission_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_care_plan_evaluation"($1, $2, $3, $4) $$;
revoke execute on function "api"."record_care_plan_evaluation"(uuid, text, text, uuid) from public, anon;
grant execute on function "api"."record_care_plan_evaluation"(uuid, text, text, uuid) to authenticated, service_role;

create or replace function "api"."list_care_plan_measures"(tenant uuid, active_only boolean default true)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_care_plan_measures"($1, $2) $$;
revoke execute on function "api"."list_care_plan_measures"(uuid, boolean) from public, anon;
grant execute on function "api"."list_care_plan_measures"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."request_care_plan_agreement"(plan_id uuid, signers uuid[], message text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."request_care_plan_agreement"($1, $2, $3) $$;
revoke execute on function "api"."request_care_plan_agreement"(uuid, uuid[], text) from public, anon;
grant execute on function "api"."request_care_plan_agreement"(uuid, uuid[], text) to authenticated, service_role;

create or replace function "api"."due_care_plan_reviews"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."due_care_plan_reviews"() $$;
revoke execute on function "api"."due_care_plan_reviews"() from public, anon, authenticated;
grant execute on function "api"."due_care_plan_reviews"() to service_role;

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
