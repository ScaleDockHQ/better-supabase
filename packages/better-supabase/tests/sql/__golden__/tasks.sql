-- ==== alone: schema supabase/schemas/900_better_supabase_091_tasks.sql
-- better-supabase module: tasks
-- @bsb-block tasks@4 managed
-- @bsb-hash sha256:9126a31be22deaf5c77679154cca119712ddc426f3278462a0a270a58f06c510
-- Issues and tasks on pipelines: identifiers, parents without cycles, several assignees, priority 0 to 4, estimates, start, end and due dates, locking, projects, iterations, batched edits and a progress tree.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tasks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_checklist_items";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_assignees";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."projects";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."iterations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Work items on pipelines: issues and tasks with an identifier, a parent,
-- assignees, a priority, dates, projects and iterations.

create table if not exists "better_supabase"."projects" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[A-Z][A-Z0-9]{0,9}$'),
  "name" text not null check (length("name") between 1 and 200),
  "owner_user_id" uuid,
  "status" text not null default 'planned' check ("status" in ('planned', 'active', 'paused', 'completed', 'canceled')),
  "start_on" date,
  "target_on" date,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  check ("target_on" is null or "start_on" is null or "target_on" >= "start_on")
);
alter table "better_supabase"."projects" add column if not exists "budget_amount" bigint check ("budget_amount" >= 0);
alter table "better_supabase"."projects" add column if not exists "budget_currency" text check ("budget_currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."projects" add column if not exists "budget_hours" numeric(12, 2) check ("budget_hours" >= 0);
alter table "better_supabase"."projects" enable row level security;
revoke all on "better_supabase"."projects" from public, anon, authenticated;
grant select on "better_supabase"."projects" to authenticated;
grant all on "better_supabase"."projects" to service_role;
drop policy if exists projects_read on "better_supabase"."projects";
create policy projects_read on "better_supabase"."projects"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table if not exists "better_supabase"."iterations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "team_id" uuid,
  "name" text not null check (length("name") between 1 and 200),
  "starts_on" date not null,
  "ends_on" date not null,
  "created_at" timestamptz not null default now(),
  check ("ends_on" >= "starts_on")
);
create index if not exists iterations_tenant_idx on "better_supabase"."iterations" ("tenant_id", "team_id", "starts_on");
alter table "better_supabase"."iterations" enable row level security;
revoke all on "better_supabase"."iterations" from public, anon, authenticated;
grant select on "better_supabase"."iterations" to authenticated;
grant all on "better_supabase"."iterations" to service_role;
drop policy if exists iterations_read on "better_supabase"."iterations";
create policy iterations_read on "better_supabase"."iterations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table if not exists "better_supabase"."tasks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "title" text not null check (length("title") between 1 and 500),
  "body" text,
  "parent_id" uuid references "better_supabase"."tasks" ("id") on delete cascade,
  "team_id" uuid,
  "project_id" uuid references "better_supabase"."projects" ("id") on delete set null,
  "iteration_id" uuid references "better_supabase"."iterations" ("id") on delete set null,
  "priority" smallint not null default 0 check ("priority" between 0 and 4),
  "estimate" numeric(10, 2) check ("estimate" >= 0),
  "progress" smallint check ("progress" between 0 and 100),
  "start_at" timestamptz,
  "end_at" timestamptz,
  "due_at" timestamptz,
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  "state" text not null default 'backlog' check ("state" in ('triage', 'backlog', 'unstarted', 'started', 'completed', 'canceled')),
  "close_reason" text check ("close_reason" in ('completed', 'not_planned', 'duplicate')),
  "closed_at" timestamptz,
  "locked" boolean not null default false,
  "rank" text collate "C" not null default 'V',
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  check ("end_at" is null or "start_at" is null or "end_at" >= "start_at")
);
create index if not exists "tasks_board_idx" on "better_supabase"."tasks" ("pipeline_id", "stage_id", "rank");
create index if not exists "tasks_parent_idx" on "better_supabase"."tasks" ("parent_id");
create index if not exists "tasks_project_idx" on "better_supabase"."tasks" ("project_id");
create index if not exists "tasks_iteration_idx" on "better_supabase"."tasks" ("iteration_id");
create index if not exists "tasks_due_idx" on "better_supabase"."tasks" ("tenant_id", "due_at") where "closed_at" is null;
alter table "better_supabase"."tasks" enable row level security;
revoke all on "better_supabase"."tasks" from public, anon, authenticated;
grant select on "better_supabase"."tasks" to authenticated;
grant all on "better_supabase"."tasks" to service_role;
drop policy if exists tasks_read on "better_supabase"."tasks";
create policy tasks_read on "better_supabase"."tasks"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table if not exists "better_supabase"."task_assignees" (
  "tenant_id" uuid not null,
  "task_id" uuid not null references "better_supabase"."tasks" ("id") on delete cascade,
  "user_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("task_id", "user_id")
);
create index if not exists "task_assignees_user_idx" on "better_supabase"."task_assignees" ("user_id");
alter table "better_supabase"."task_assignees" enable row level security;
revoke all on "better_supabase"."task_assignees" from public, anon, authenticated;
grant select on "better_supabase"."task_assignees" to authenticated;
grant all on "better_supabase"."task_assignees" to service_role;
drop policy if exists task_assignees_read on "better_supabase"."task_assignees";
create policy task_assignees_read on "better_supabase"."task_assignees"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

alter table "better_supabase"."tasks" add column if not exists "recurs_from" uuid references "better_supabase"."tasks" ("id") on delete set null;
create unique index if not exists "tasks_recurs_from_idx" on "better_supabase"."tasks" ("recurs_from");

create table if not exists "better_supabase"."task_checklist_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "task_id" uuid not null references "better_supabase"."tasks" ("id") on delete cascade,
  "title" text not null check (length("title") between 1 and 500),
  "done" boolean not null default false,
  "done_at" timestamptz,
  "done_by" uuid,
  "rank" text collate "C" not null check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
create index if not exists "task_checklist_item_idx" on "better_supabase"."task_checklist_items" ("task_id", "rank");
alter table "better_supabase"."task_checklist_items" enable row level security;
revoke all on "better_supabase"."task_checklist_items" from public, anon, authenticated;
grant select on "better_supabase"."task_checklist_items" to authenticated;
grant all on "better_supabase"."task_checklist_items" to service_role;
drop policy if exists task_checklist_items_read on "better_supabase"."task_checklist_items";
create policy task_checklist_items_read on "better_supabase"."task_checklist_items"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create or replace function better_supabase.bsb_work_item_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."parent_id" is not null and (tg_op = 'INSERT' or new."parent_id" is distinct from old."parent_id") then
    if exists (
      with recursive up(id, depth) as (
        select new."parent_id", 1
        union all
        select x."parent_id", up.depth + 1 from "better_supabase"."tasks" x join up on x."id" = up.id
        where x."parent_id" is not null and up.depth < 100
      )
      select 1 from up where up.id = new."id"
    ) then
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'TASK_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "better_supabase"."tasks" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
      raise exception 'the parent is in another organization' using errcode = '22023', hint = 'TASK_PARENT_INVALID';
    end if;
  end if;
  if tg_op = 'UPDATE' and old."locked" and not (auth.role() = 'service_role') and (new."start_at" is distinct from old."start_at" or new."end_at" is distinct from old."end_at" or new."due_at" is distinct from old."due_at") then
    raise exception 'the item is locked; its dates can''t change' using errcode = '55000', hint = 'TASK_LOCKED';
  end if;
  if tg_op = 'INSERT' then
    if new."state" in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
    end if;
    return new;
  end if;
  if new."state" is distinct from old."state" then
    if new."state" in ('completed', 'canceled') and old."state" not in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
      if new."state" = 'completed' and new."progress" is not null then
        new."progress" := 100;
      end if;
      null;
    elsif not (new."state" in ('completed', 'canceled')) and old."state" in ('completed', 'canceled') then
      new."closed_at" := null;
      new."close_reason" := null;
      null;
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_work_item_guard() from public, anon, authenticated;
drop trigger if exists bsb_work_item_guard on "better_supabase"."tasks";
create trigger bsb_work_item_guard before insert or update on "better_supabase"."tasks"
for each row execute function better_supabase.bsb_work_item_guard();

-- Creates a work item. attrs: title (required), body, parentId, teamId,
-- projectId, iterationId, priority (0 none to 4 low, as Linear), estimate,
-- progress, startAt, endAt, dueAt, pipelineId, stageId, and fields (the
-- extra columns, by name). assignees: user ids.
create or replace function "better_supabase"."create_task"(tenant uuid, attrs jsonb, assignees uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seq bigint;
  v_identifier text;
  v_id uuid;
  v_row "better_supabase"."tasks";
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_task.tenant, 'tasks.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if nullif(trim(create_task.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'TASK_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_task_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_task.tenant, create_task.attrs;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'work_item' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'work_item' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_task.tenant::text || ':work_item', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."tasks" x where x."tenant_id" = create_task.tenant;
  v_identifier := 'TASK-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."tasks" ("tenant_id", "number", "identifier", "title", "body", "parent_id", "team_id", "project_id", "iteration_id",
      "priority", "estimate", "progress", "start_at", "end_at", "due_at", "pipeline_id", "stage_id", "created_by")
    values (create_task.tenant, v_seq, v_identifier, trim(create_task.attrs ->> 'title'), create_task.attrs ->> 'body',
      (create_task.attrs ->> 'parentId')::uuid, (create_task.attrs ->> 'teamId')::uuid, (create_task.attrs ->> 'projectId')::uuid,
      (create_task.attrs ->> 'iterationId')::uuid, coalesce((create_task.attrs ->> 'priority')::smallint, 0),
      (create_task.attrs ->> 'estimate')::numeric, (create_task.attrs ->> 'progress')::smallint,
      (create_task.attrs ->> 'startAt')::timestamptz, (create_task.attrs ->> 'endAt')::timestamptz, (create_task.attrs ->> 'dueAt')::timestamptz,
      (create_task.attrs ->> 'pipelineId')::uuid, (create_task.attrs ->> 'stageId')::uuid, auth.uid())
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  if cardinality(coalesce(create_task.assignees, '{}')) > 0 then
    perform "better_supabase"."set_task_assignees"(v_id, create_task.assignees);
  end if;
  select * into v_row from "better_supabase"."tasks" x where x."id" = v_id;
  if jsonb_array_length(coalesce((create_task.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      raise exception 'install the attachments block to attach files' using errcode = '0A000', hint = 'TASK_ATTACHMENTS_UNAVAILABLE';
    end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_task_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id")) from "better_supabase"."tasks" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_task"(uuid, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."create_task"(uuid, jsonb, uuid[]) to authenticated, service_role;

-- Applies a batch of { workItemId, field, value } changes, each on its
-- own. Returns { accepted: [{ workItemId, field }], rejected: [{ workItemId,
-- field, hint, reason }] }. With atomic, the first change that fails raises
-- its error and no change is kept. The window field ({ startAt, endAt })
-- writes both ends in one update, so the end-after-start check sees both.
drop function if exists "better_supabase"."update_tasks"(jsonb);
create or replace function "better_supabase"."update_tasks"(changes jsonb, atomic boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_item uuid;
  v_field text;
  v_row "better_supabase"."tasks";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_tasks.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { workItemId, field, value }' using errcode = '22023', hint = 'TASK_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_tasks.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'workItemId')::uuid;
      if not exists (select 1 from "better_supabase"."tasks" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_task_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_item, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'title' then
        update "better_supabase"."tasks" x set "title" = trim(v_change -> 'value' #>> '{}') where x."id" = v_item;
      when 'body' then
        update "better_supabase"."tasks" x set "body" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'parentId' then
        update "better_supabase"."tasks" x set "parent_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'teamId' then
        update "better_supabase"."tasks" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'projectId' then
        update "better_supabase"."tasks" x set "project_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'iterationId' then
        update "better_supabase"."tasks" x set "iteration_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'priority' then
        update "better_supabase"."tasks" x set "priority" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'estimate' then
        update "better_supabase"."tasks" x set "estimate" = (v_change -> 'value' #>> '{}')::numeric where x."id" = v_item;
      when 'progress' then
        update "better_supabase"."tasks" x set "progress" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'startAt' then
        update "better_supabase"."tasks" x set "start_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'endAt' then
        update "better_supabase"."tasks" x set "end_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'dueAt' then
        update "better_supabase"."tasks" x set "due_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'stageId' then
        update "better_supabase"."tasks" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'closeReason' then
        update "better_supabase"."tasks" x set "close_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'window' then
        if jsonb_typeof(v_change -> 'value') <> 'object' then
          raise exception 'window must be an object of startAt and endAt' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
        end if;
        update "better_supabase"."tasks" x set
          "start_at" = case when v_change -> 'value' ? 'startAt' then (v_change -> 'value' ->> 'startAt')::timestamptz else x."start_at" end,
          "end_at" = case when v_change -> 'value' ? 'endAt' then (v_change -> 'value' ->> 'endAt')::timestamptz else x."end_at" end
        where x."id" = v_item;
      when 'attachments' then
        select * into v_row from "better_supabase"."tasks" x where x."id" = v_item;
        if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      raise exception 'install the attachments block to attach files' using errcode = '0A000', hint = 'TASK_ATTACHMENTS_UNAVAILABLE';
    end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'TASK_FIELD_UNKNOWN';
      end case;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('workItemId', v_item, 'field', v_field));
      v_touched := array_append(v_touched, v_item);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_task_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_item, v_field;
    end if;
  end;
    exception when others then
      if update_tasks.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_change ->> 'workItemId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."tasks" x where x."id" = any (v_touched) loop
    null;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "better_supabase"."update_tasks"(jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."update_tasks"(jsonb, boolean) to authenticated, service_role;

-- Replaces an item's assignees. Each one watches the item, and those who
-- weren't assigned before are notified. task.assigned is recorded only
-- when the call adds someone, with addedIds.
create or replace function "better_supabase"."set_task_assignees"(work_item uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_task_assignees.users, '{}')) x where x is not null);
  v_added uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."tasks" x where x."id" = set_task_assignees.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_added := array(select x from unnest(v_users) x where not exists (
    select 1 from "better_supabase"."task_assignees" y where y."task_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."task_assignees" y where y."task_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."task_assignees" ("tenant_id", "task_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  if cardinality(v_added) > 0 then
    null;
  end if;
  return cardinality(v_users);
end;
$$;
revoke execute on function "better_supabase"."set_task_assignees"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."set_task_assignees"(uuid, uuid[]) to authenticated, service_role;

create or replace function "better_supabase"."archive_task"(work_item uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."tasks" x set "archived_at" = case when archive_task.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_task.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_task.archived then
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_task"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_task"(uuid, boolean) to authenticated, service_role;

-- Deletes an item and its children. Needs work_items.manage, or its author.
create or replace function "better_supabase"."delete_task"(work_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."tasks" x
  where x."id" = delete_task.work_item
    and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_task"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_task"(uuid) to authenticated, service_role;

-- An item and everything under it with its depth. An item without its own
-- progress takes the share of its open and completed children that are
-- completed, so a Gantt group shows a rollup.
create or replace function "better_supabase"."task_tree"(root uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with recursive tree as (
    select x.*, 0 as depth from "better_supabase"."tasks" x where x."id" = task_tree.root
    union all
    select y.*, tree.depth + 1 from "better_supabase"."tasks" y join tree on y."parent_id" = tree."id"
    where tree.depth < 100 and y."archived_at" is null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', tree."id", 'parentId', tree."parent_id", 'identifier', tree."identifier", 'title', tree."title",
    'state', tree."state", 'startAt', tree."start_at", 'endAt', tree."end_at", 'dueAt', tree."due_at",
    'locked', tree."locked", 'depth', tree.depth,
    'progress', coalesce(tree."progress", (
      select case when count(*) filter (where ch."state" <> 'canceled') = 0 then
          case tree."state" when 'completed' then 100 else 0 end
        else round(100.0 * count(*) filter (where ch."state" = 'completed') / count(*) filter (where ch."state" <> 'canceled'))::integer end
      from "better_supabase"."tasks" ch where ch."parent_id" = tree."id" and ch."archived_at" is null))
  ) order by tree.depth, tree."rank" collate "C", tree."id"), '[]'::jsonb)
  from tree
$$;
revoke execute on function "better_supabase"."task_tree"(uuid) from public, anon;
grant execute on function "better_supabase"."task_tree"(uuid) to authenticated, service_role;

-- A page of a tenant's active items, newest first. filter keys: teamId,
-- projectId, iterationId, parentId, assigneeId, states (a list), open
-- (only unclosed). search matches the title and identifier. after continues
-- after that item.
create or replace function "better_supabase"."list_tasks"(tenant uuid, filter jsonb, search text, after uuid, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.number desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id")) as value, x."number" as number
    from "better_supabase"."tasks" x
    where x."tenant_id" = list_tasks.tenant and x."archived_at" is null
      and (list_tasks.filter ->> 'teamId' is null or x."team_id" = (list_tasks.filter ->> 'teamId')::uuid)
      and (list_tasks.filter ->> 'projectId' is null or x."project_id" = (list_tasks.filter ->> 'projectId')::uuid)
      and (list_tasks.filter ->> 'iterationId' is null or x."iteration_id" = (list_tasks.filter ->> 'iterationId')::uuid)
      and (list_tasks.filter ->> 'parentId' is null or x."parent_id" = (list_tasks.filter ->> 'parentId')::uuid)
      and (list_tasks.filter ->> 'assigneeId' is null or exists (select 1 from "better_supabase"."task_assignees" y where y."task_id" = x."id" and y."user_id" = (list_tasks.filter ->> 'assigneeId')::uuid))
      and (list_tasks.filter -> 'states' is null or x."state" = any (array(select jsonb_array_elements_text(list_tasks.filter -> 'states'))))
      and (coalesce((list_tasks.filter ->> 'open')::boolean, false) = false or x."closed_at" is null)
      and (list_tasks.search is null or x."title" ilike '%' || list_tasks.search || '%' or x."identifier" ilike list_tasks.search || '%')
      and (list_tasks.after is null or x."number" < (select z."number" from "better_supabase"."tasks" z where z."id" = list_tasks.after))
    order by x."number" desc
    limit least(greatest(coalesce(list_tasks.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."list_tasks"(uuid, jsonb, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_tasks"(uuid, jsonb, text, uuid, integer) to authenticated, service_role;

-- Adds a checklist item (checklist_item null) or changes one: title, done,
-- rank. A new item without a rank goes last.
create or replace function "better_supabase"."save_task_checklist_item"(work_item uuid, checklist_item uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
  v_id uuid := save_task_checklist_item.checklist_item;
  v_last text;
  v_done boolean := (save_task_checklist_item.attrs ->> 'done')::boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."tasks" x where x."id" = save_task_checklist_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  begin
    if v_id is null then
      select max(y."rank") into v_last from "better_supabase"."task_checklist_items" y where y."task_id" = v_row."id";
      insert into "better_supabase"."task_checklist_items" ("tenant_id", "task_id", "title", "done", "done_at", "done_by", "rank", "created_by")
      values (v_row."tenant_id", v_row."id", trim(save_task_checklist_item.attrs ->> 'title'), coalesce(v_done, false),
        case when v_done then now() end, case when v_done then auth.uid() end,
        coalesce(save_task_checklist_item.attrs ->> 'rank', case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end), auth.uid())
      returning "id" into v_id;
    else
      update "better_supabase"."task_checklist_items" y set
        "title" = coalesce(trim(save_task_checklist_item.attrs ->> 'title'), y."title"),
        "rank" = coalesce(save_task_checklist_item.attrs ->> 'rank', y."rank"),
        "done" = coalesce(v_done, y."done"),
        "done_at" = case when v_done is null then y."done_at" when v_done then coalesce(y."done_at", now()) end,
        "done_by" = case when v_done is null then y."done_by" when v_done then coalesce(y."done_by", auth.uid()) end
      where y."id" = v_id and y."task_id" = v_row."id";
      if not found then
        raise exception 'no such checklist item on this work item' using errcode = 'P0002', hint = 'TASK_CHECKLIST_ITEM_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a checklist item needs a title of 1 to 500 characters and a valid rank' using errcode = '22023', hint = 'TASK_CHECKLIST_ITEM_INVALID';
  end;
  null;
  return (select jsonb_build_object('id', y."id", 'workItemId', y."task_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") from "better_supabase"."task_checklist_items" y where y."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_task_checklist_item"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_task_checklist_item"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_task_checklist_item"(checklist_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x.* into v_row from "better_supabase"."tasks" x join "better_supabase"."task_checklist_items" y on y."task_id" = x."id"
  where y."id" = delete_task_checklist_item.checklist_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    return false;
  end if;
  delete from "better_supabase"."task_checklist_items" y where y."id" = delete_task_checklist_item.checklist_item;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_task_checklist_item"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_task_checklist_item"(uuid) to authenticated, service_role;

-- An item's checklist, in rank order.
create or replace function "better_supabase"."list_task_checklist"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'workItemId', y."task_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") order by y."rank" collate "C", y."id"), '[]'::jsonb)
  from "better_supabase"."task_checklist_items" y where y."task_id" = list_task_checklist.work_item
$$;
revoke execute on function "better_supabase"."list_task_checklist"(uuid) from public, anon;
grant execute on function "better_supabase"."list_task_checklist"(uuid) to authenticated, service_role;

-- One item the caller can read, or null.
create or replace function "better_supabase"."get_task"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id")) from "better_supabase"."tasks" x where x."id" = get_task.work_item
$$;
revoke execute on function "better_supabase"."get_task"(uuid) from public, anon;
grant execute on function "better_supabase"."get_task"(uuid) to authenticated, service_role;

-- Creates a project (project null) or changes the keys attrs names: key,
-- name, ownerId, status, startOn, targetOn, archived, and the budget:
-- budgetAmount (minor units as text) with budgetCurrency, and budgetHours.
-- With accounting, the project is a value of the project dimension.
create or replace function "better_supabase"."save_project"(tenant uuid, project uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_project.project;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_project.tenant, 'tasks.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."projects" ("tenant_id", "key", "name", "owner_user_id", "status", "start_on", "target_on", "budget_amount", "budget_currency", "budget_hours")
      values (save_project.tenant, upper(save_project.attrs ->> 'key'), save_project.attrs ->> 'name', (save_project.attrs ->> 'ownerId')::uuid,
        coalesce(save_project.attrs ->> 'status', 'planned'), (save_project.attrs ->> 'startOn')::date, (save_project.attrs ->> 'targetOn')::date,
        (save_project.attrs ->> 'budgetAmount')::bigint, upper(save_project.attrs ->> 'budgetCurrency'), (save_project.attrs ->> 'budgetHours')::numeric)
      returning "id" into v_id;
    else
      update "better_supabase"."projects" x set
        "key" = coalesce(upper(save_project.attrs ->> 'key'), x."key"),
        "name" = coalesce(save_project.attrs ->> 'name', x."name"),
        "owner_user_id" = case when save_project.attrs ? 'ownerId' then (save_project.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
        "status" = coalesce(save_project.attrs ->> 'status', x."status"),
        "start_on" = case when save_project.attrs ? 'startOn' then (save_project.attrs ->> 'startOn')::date else x."start_on" end,
        "target_on" = case when save_project.attrs ? 'targetOn' then (save_project.attrs ->> 'targetOn')::date else x."target_on" end,
        "budget_amount" = case when save_project.attrs ? 'budgetAmount' then (save_project.attrs ->> 'budgetAmount')::bigint else x."budget_amount" end,
        "budget_currency" = case when save_project.attrs ? 'budgetCurrency' then upper(save_project.attrs ->> 'budgetCurrency') else x."budget_currency" end,
        "budget_hours" = case when save_project.attrs ? 'budgetHours' then (save_project.attrs ->> 'budgetHours')::numeric else x."budget_hours" end,
        "archived_at" = case when save_project.attrs ? 'archived' then (case when (save_project.attrs ->> 'archived')::boolean then coalesce(x."archived_at", now()) end) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_project.tenant;
      if not found then
        raise exception 'project not found' using errcode = 'P0002', hint = 'TASK_PROJECT_NOT_FOUND';
      end if;
    end if;
    if exists (
      select 1 from "better_supabase"."projects" x
      where x."id" = v_id and x."budget_amount" is not null and x."budget_currency" is null
    ) then
      raise exception 'a budget amount needs a currency' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
    end if;
  exception when unique_violation then
    raise exception 'another project has this key' using errcode = '23505', hint = 'TASK_PROJECT_KEY_TAKEN';
  when check_violation or not_null_violation then
    raise exception 'a project needs a key of capitals and a name, and ends after it starts' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end;

  return (select to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."tasks" y where y."project_id" = x."id" and y."archived_at" is null
    )) from "better_supabase"."projects" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_project"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_project"(uuid, uuid, jsonb) to authenticated, service_role;

-- Creates an iteration (a cycle or a sprint) or changes it: name, teamId,
-- startsOn, endsOn.
create or replace function "better_supabase"."save_iteration"(tenant uuid, iteration uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_iteration.iteration;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_iteration.tenant, 'tasks.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."iterations" ("tenant_id", "team_id", "name", "starts_on", "ends_on")
      values (save_iteration.tenant, (save_iteration.attrs ->> 'teamId')::uuid, save_iteration.attrs ->> 'name',
        (save_iteration.attrs ->> 'startsOn')::date, (save_iteration.attrs ->> 'endsOn')::date)
      returning "id" into v_id;
    else
      update "better_supabase"."iterations" x set
        "name" = coalesce(save_iteration.attrs ->> 'name', x."name"),
        "starts_on" = coalesce((save_iteration.attrs ->> 'startsOn')::date, x."starts_on"),
        "ends_on" = coalesce((save_iteration.attrs ->> 'endsOn')::date, x."ends_on")
      where x."id" = v_id and x."tenant_id" = save_iteration.tenant;
      if not found then
        raise exception 'iteration not found' using errcode = 'P0002', hint = 'TASK_ITERATION_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation then
    raise exception 'an iteration needs a name and ends on or after it starts' using errcode = '22023', hint = 'TASK_ITERATION_INVALID';
  end;
  return (select to_jsonb(x) from "better_supabase"."iterations" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_iteration"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_iteration"(uuid, uuid, jsonb) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."tasks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tasks";
create policy bsb_tenant_scope_select on "better_supabase"."tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tasks";
create policy bsb_tenant_scope_insert on "better_supabase"."tasks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tasks";
create policy bsb_tenant_scope_update on "better_supabase"."tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tasks";
create policy bsb_tenant_scope_delete on "better_supabase"."tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."task_checklist_items";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_select on "better_supabase"."task_checklist_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_insert on "better_supabase"."task_checklist_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_update on "better_supabase"."task_checklist_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_delete on "better_supabase"."task_checklist_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."task_assignees";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_select on "better_supabase"."task_assignees" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_insert on "better_supabase"."task_assignees" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_update on "better_supabase"."task_assignees" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_delete on "better_supabase"."task_assignees" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."projects";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."projects";
create policy bsb_tenant_scope_select on "better_supabase"."projects" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."projects";
create policy bsb_tenant_scope_insert on "better_supabase"."projects" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."projects";
create policy bsb_tenant_scope_update on "better_supabase"."projects" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."projects";
create policy bsb_tenant_scope_delete on "better_supabase"."projects" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."iterations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."iterations";
create policy bsb_tenant_scope_select on "better_supabase"."iterations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."iterations";
create policy bsb_tenant_scope_insert on "better_supabase"."iterations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."iterations";
create policy bsb_tenant_scope_update on "better_supabase"."iterations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."iterations";
create policy bsb_tenant_scope_delete on "better_supabase"."iterations" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_091_tasks.sql
-- better-supabase module: tasks
-- @bsb-block-data tasks
-- @bsb-hash sha256:ea8a7f6275992a7e6c1d4e1fb480479290ca96436b7d2cd1815c10fb28bbf310
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_members"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_members" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipelines"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipelines" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipeline_stage_history"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipeline_stage_history" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_091_tasks.sql
-- better-supabase module: tasks
-- @bsb-block tasks@4 managed
-- @bsb-hash sha256:85522a164cf39ff19333730284e694d9ae2ab99d247bd8ff073995ce10f87928
-- Issues and tasks on pipelines: identifiers, parents without cycles, several assignees, priority 0 to 4, estimates, start, end and due dates, locking, projects, iterations, batched edits and a progress tree.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tasks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_checklist_items";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_assignees";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."projects";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."iterations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Work items on pipelines: issues and tasks with an identifier, a parent,
-- assignees, a priority, dates, projects and iterations.

create table if not exists "better_supabase"."projects" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[A-Z][A-Z0-9]{0,9}$'),
  "name" text not null check (length("name") between 1 and 200),
  "owner_user_id" uuid,
  "status" text not null default 'planned' check ("status" in ('planned', 'active', 'paused', 'completed', 'canceled')),
  "start_on" date,
  "target_on" date,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  check ("target_on" is null or "start_on" is null or "target_on" >= "start_on")
);
alter table "better_supabase"."projects" add column if not exists "budget_amount" bigint check ("budget_amount" >= 0);
alter table "better_supabase"."projects" add column if not exists "budget_currency" text check ("budget_currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."projects" add column if not exists "budget_hours" numeric(12, 2) check ("budget_hours" >= 0);
alter table "better_supabase"."projects" enable row level security;
revoke all on "better_supabase"."projects" from public, anon, authenticated;
grant select on "better_supabase"."projects" to authenticated;
grant all on "better_supabase"."projects" to service_role;
drop policy if exists projects_read on "better_supabase"."projects";
create policy projects_read on "better_supabase"."projects"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table if not exists "better_supabase"."iterations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "team_id" uuid,
  "name" text not null check (length("name") between 1 and 200),
  "starts_on" date not null,
  "ends_on" date not null,
  "created_at" timestamptz not null default now(),
  check ("ends_on" >= "starts_on")
);
create index if not exists iterations_tenant_idx on "better_supabase"."iterations" ("tenant_id", "team_id", "starts_on");
alter table "better_supabase"."iterations" enable row level security;
revoke all on "better_supabase"."iterations" from public, anon, authenticated;
grant select on "better_supabase"."iterations" to authenticated;
grant all on "better_supabase"."iterations" to service_role;
drop policy if exists iterations_read on "better_supabase"."iterations";
create policy iterations_read on "better_supabase"."iterations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table if not exists "better_supabase"."tasks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "title" text not null check (length("title") between 1 and 500),
  "body" text,
  "parent_id" uuid references "better_supabase"."tasks" ("id") on delete cascade,
  "team_id" uuid,
  "project_id" uuid references "better_supabase"."projects" ("id") on delete set null,
  "iteration_id" uuid references "better_supabase"."iterations" ("id") on delete set null,
  "priority" smallint not null default 0 check ("priority" between 0 and 4),
  "estimate" numeric(10, 2) check ("estimate" >= 0),
  "progress" smallint check ("progress" between 0 and 100),
  "start_at" timestamptz,
  "end_at" timestamptz,
  "due_at" timestamptz,
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  "state" text not null default 'backlog' check ("state" in ('triage', 'backlog', 'unstarted', 'started', 'completed', 'canceled')),
  "close_reason" text check ("close_reason" in ('completed', 'not_planned', 'duplicate')),
  "closed_at" timestamptz,
  "locked" boolean not null default false,
  "rank" text collate "C" not null default 'V',
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  check ("end_at" is null or "start_at" is null or "end_at" >= "start_at")
);
create index if not exists "tasks_board_idx" on "better_supabase"."tasks" ("pipeline_id", "stage_id", "rank");
create index if not exists "tasks_parent_idx" on "better_supabase"."tasks" ("parent_id");
create index if not exists "tasks_project_idx" on "better_supabase"."tasks" ("project_id");
create index if not exists "tasks_iteration_idx" on "better_supabase"."tasks" ("iteration_id");
create index if not exists "tasks_due_idx" on "better_supabase"."tasks" ("tenant_id", "due_at") where "closed_at" is null;
alter table "better_supabase"."tasks" enable row level security;
revoke all on "better_supabase"."tasks" from public, anon, authenticated;
grant select on "better_supabase"."tasks" to authenticated;
grant all on "better_supabase"."tasks" to service_role;
drop policy if exists tasks_read on "better_supabase"."tasks";
create policy tasks_read on "better_supabase"."tasks"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table if not exists "better_supabase"."task_assignees" (
  "tenant_id" uuid not null,
  "task_id" uuid not null references "better_supabase"."tasks" ("id") on delete cascade,
  "user_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("task_id", "user_id")
);
create index if not exists "task_assignees_user_idx" on "better_supabase"."task_assignees" ("user_id");
alter table "better_supabase"."task_assignees" enable row level security;
revoke all on "better_supabase"."task_assignees" from public, anon, authenticated;
grant select on "better_supabase"."task_assignees" to authenticated;
grant all on "better_supabase"."task_assignees" to service_role;
drop policy if exists task_assignees_read on "better_supabase"."task_assignees";
create policy task_assignees_read on "better_supabase"."task_assignees"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

alter table "better_supabase"."tasks" add column if not exists "recurs_from" uuid references "better_supabase"."tasks" ("id") on delete set null;
create unique index if not exists "tasks_recurs_from_idx" on "better_supabase"."tasks" ("recurs_from");

create table if not exists "better_supabase"."task_checklist_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "task_id" uuid not null references "better_supabase"."tasks" ("id") on delete cascade,
  "title" text not null check (length("title") between 1 and 500),
  "done" boolean not null default false,
  "done_at" timestamptz,
  "done_by" uuid,
  "rank" text collate "C" not null check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
create index if not exists "task_checklist_item_idx" on "better_supabase"."task_checklist_items" ("task_id", "rank");
alter table "better_supabase"."task_checklist_items" enable row level security;
revoke all on "better_supabase"."task_checklist_items" from public, anon, authenticated;
grant select on "better_supabase"."task_checklist_items" to authenticated;
grant all on "better_supabase"."task_checklist_items" to service_role;
drop policy if exists task_checklist_items_read on "better_supabase"."task_checklist_items";
create policy task_checklist_items_read on "better_supabase"."task_checklist_items"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create or replace function better_supabase.bsb_work_item_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."parent_id" is not null and (tg_op = 'INSERT' or new."parent_id" is distinct from old."parent_id") then
    if exists (
      with recursive up(id, depth) as (
        select new."parent_id", 1
        union all
        select x."parent_id", up.depth + 1 from "better_supabase"."tasks" x join up on x."id" = up.id
        where x."parent_id" is not null and up.depth < 100
      )
      select 1 from up where up.id = new."id"
    ) then
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'TASK_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "better_supabase"."tasks" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
      raise exception 'the parent is in another organization' using errcode = '22023', hint = 'TASK_PARENT_INVALID';
    end if;
  end if;
  if tg_op = 'UPDATE' and old."locked" and not (auth.role() = 'service_role') and (new."start_at" is distinct from old."start_at" or new."end_at" is distinct from old."end_at" or new."due_at" is distinct from old."due_at") then
    raise exception 'the item is locked; its dates can''t change' using errcode = '55000', hint = 'TASK_LOCKED';
  end if;
  if tg_op = 'INSERT' then
    if new."state" in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
    end if;
    return new;
  end if;
  if new."state" is distinct from old."state" then
    if new."state" in ('completed', 'canceled') and old."state" not in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
      if new."state" = 'completed' and new."progress" is not null then
        new."progress" := 100;
      end if;
      perform "better_supabase".emit_event('task.closed', jsonb_build_object('organizationId', new."tenant_id", 'workItemId', new."id", 'subjectType', 'task', 'subjectId', new."id"::text, 'title', new."title", 'state', new."state", 'closeReason', new."close_reason"), 'work-items/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/tasks');
    elsif not (new."state" in ('completed', 'canceled')) and old."state" in ('completed', 'canceled') then
      new."closed_at" := null;
      new."close_reason" := null;
      perform "better_supabase".emit_event('task.reopened', jsonb_build_object('organizationId', new."tenant_id", 'workItemId', new."id", 'subjectType', 'task', 'subjectId', new."id"::text, 'title', new."title"), 'work-items/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/tasks');
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_work_item_guard() from public, anon, authenticated;
drop trigger if exists bsb_work_item_guard on "better_supabase"."tasks";
create trigger bsb_work_item_guard before insert or update on "better_supabase"."tasks"
for each row execute function better_supabase.bsb_work_item_guard();

-- Creates a work item. attrs: title (required), body, parentId, teamId,
-- projectId, iterationId, priority (0 none to 4 low, as Linear), estimate,
-- progress, startAt, endAt, dueAt, pipelineId, stageId, and fields (the
-- extra columns, by name). assignees: user ids.
create or replace function "better_supabase"."create_task"(tenant uuid, attrs jsonb, assignees uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seq bigint;
  v_identifier text;
  v_id uuid;
  v_row "better_supabase"."tasks";
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_task.tenant, 'tasks.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if nullif(trim(create_task.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'TASK_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_task_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_task.tenant, create_task.attrs;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'work_item' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'work_item' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_task.tenant::text || ':work_item', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."tasks" x where x."tenant_id" = create_task.tenant;
  v_identifier := 'TASK-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."tasks" ("tenant_id", "number", "identifier", "title", "body", "parent_id", "team_id", "project_id", "iteration_id",
      "priority", "estimate", "progress", "start_at", "end_at", "due_at", "pipeline_id", "stage_id", "created_by")
    values (create_task.tenant, v_seq, v_identifier, trim(create_task.attrs ->> 'title'), create_task.attrs ->> 'body',
      (create_task.attrs ->> 'parentId')::uuid, (create_task.attrs ->> 'teamId')::uuid, (create_task.attrs ->> 'projectId')::uuid,
      (create_task.attrs ->> 'iterationId')::uuid, coalesce((create_task.attrs ->> 'priority')::smallint, 0),
      (create_task.attrs ->> 'estimate')::numeric, (create_task.attrs ->> 'progress')::smallint,
      (create_task.attrs ->> 'startAt')::timestamptz, (create_task.attrs ->> 'endAt')::timestamptz, (create_task.attrs ->> 'dueAt')::timestamptz,
      (create_task.attrs ->> 'pipelineId')::uuid, (create_task.attrs ->> 'stageId')::uuid, auth.uid())
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  if cardinality(coalesce(create_task.assignees, '{}')) > 0 then
    perform "better_supabase"."set_task_assignees"(v_id, create_task.assignees);
  end if;
  select * into v_row from "better_supabase"."tasks" x where x."id" = v_id;
  if jsonb_typeof(coalesce((create_task.attrs -> 'attachments'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((create_task.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'task', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((create_task.attrs -> 'attachments'))::uuid))
        and f."organization_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'task' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((create_task.attrs -> 'attachments')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
      end if;
    end if;
  perform "better_supabase".emit_event('task.created', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'task', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_task_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'task' and rr."subject_id" = x."id"::text)) from "better_supabase"."tasks" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_task"(uuid, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."create_task"(uuid, jsonb, uuid[]) to authenticated, service_role;

-- Applies a batch of { workItemId, field, value } changes, each on its
-- own. Returns { accepted: [{ workItemId, field }], rejected: [{ workItemId,
-- field, hint, reason }] }. With atomic, the first change that fails raises
-- its error and no change is kept. The window field ({ startAt, endAt })
-- writes both ends in one update, so the end-after-start check sees both.
drop function if exists "better_supabase"."update_tasks"(jsonb);
create or replace function "better_supabase"."update_tasks"(changes jsonb, atomic boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_item uuid;
  v_field text;
  v_row "better_supabase"."tasks";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_tasks.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { workItemId, field, value }' using errcode = '22023', hint = 'TASK_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_tasks.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'workItemId')::uuid;
      if not exists (select 1 from "better_supabase"."tasks" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_task_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_item, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'title' then
        update "better_supabase"."tasks" x set "title" = trim(v_change -> 'value' #>> '{}') where x."id" = v_item;
      when 'body' then
        update "better_supabase"."tasks" x set "body" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'parentId' then
        update "better_supabase"."tasks" x set "parent_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'teamId' then
        update "better_supabase"."tasks" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'projectId' then
        update "better_supabase"."tasks" x set "project_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'iterationId' then
        update "better_supabase"."tasks" x set "iteration_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'priority' then
        update "better_supabase"."tasks" x set "priority" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'estimate' then
        update "better_supabase"."tasks" x set "estimate" = (v_change -> 'value' #>> '{}')::numeric where x."id" = v_item;
      when 'progress' then
        update "better_supabase"."tasks" x set "progress" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'startAt' then
        update "better_supabase"."tasks" x set "start_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'endAt' then
        update "better_supabase"."tasks" x set "end_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'dueAt' then
        update "better_supabase"."tasks" x set "due_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'stageId' then
        update "better_supabase"."tasks" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'closeReason' then
        update "better_supabase"."tasks" x set "close_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'window' then
        if jsonb_typeof(v_change -> 'value') <> 'object' then
          raise exception 'window must be an object of startAt and endAt' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
        end if;
        update "better_supabase"."tasks" x set
          "start_at" = case when v_change -> 'value' ? 'startAt' then (v_change -> 'value' ->> 'startAt')::timestamptz else x."start_at" end,
          "end_at" = case when v_change -> 'value' ? 'endAt' then (v_change -> 'value' ->> 'endAt')::timestamptz else x."end_at" end
        where x."id" = v_item;
      when 'attachments' then
        select * into v_row from "better_supabase"."tasks" x where x."id" = v_item;
        if jsonb_typeof(coalesce((v_change -> 'value'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'task', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((v_change -> 'value'))::uuid))
        and f."organization_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'task' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((v_change -> 'value')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
      end if;
    end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'TASK_FIELD_UNKNOWN';
      end case;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('workItemId', v_item, 'field', v_field));
      v_touched := array_append(v_touched, v_item);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_task_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_item, v_field;
    end if;
  end;
    exception when others then
      if update_tasks.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_change ->> 'workItemId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."tasks" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('task.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'task', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'workItemId')::uuid = v_row."id")), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "better_supabase"."update_tasks"(jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."update_tasks"(jsonb, boolean) to authenticated, service_role;

-- Replaces an item's assignees. Each one watches the item, and those who
-- weren't assigned before are notified. task.assigned is recorded only
-- when the call adds someone, with addedIds.
create or replace function "better_supabase"."set_task_assignees"(work_item uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_task_assignees.users, '{}')) x where x is not null);
  v_added uuid[];
  v_new uuid[];
  v_claims text;
  v_user uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."tasks" x where x."id" = set_task_assignees.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from "better_supabase"."task_assignees" y where y."task_id" = v_row."id" and y."user_id" = x));
  v_added := array(select x from unnest(v_users) x where not exists (
    select 1 from "better_supabase"."task_assignees" y where y."task_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."task_assignees" y where y."task_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."task_assignees" ("tenant_id", "task_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  foreach v_user in array v_users loop
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_row."tenant_id", v_user, 'task', v_row."id"::text, 'participating')
    on conflict do nothing;
  end loop;
  if cardinality(v_new) > 0 then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'work_item.assigned',
      'tenant', v_row."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'task',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."title",
      'summary', v_row."title",
      'action_path', null,
      'recipients', to_jsonb(v_new),
      'watchers', false,
      'key', 'task.assigned:' || v_row."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('workItemId', v_row."id")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if cardinality(v_added) > 0 then
    perform "better_supabase".emit_event('task.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'task', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(v_users), 'addedIds', to_jsonb(v_added)), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return cardinality(v_users);
end;
$$;
revoke execute on function "better_supabase"."set_task_assignees"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."set_task_assignees"(uuid, uuid[]) to authenticated, service_role;

create or replace function "better_supabase"."archive_task"(work_item uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."tasks" x set "archived_at" = case when archive_task.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_task.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_task.archived then
    perform "better_supabase".emit_event('task.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'task', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_task"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_task"(uuid, boolean) to authenticated, service_role;

-- Deletes an item and its children. Needs work_items.manage, or its author.
create or replace function "better_supabase"."delete_task"(work_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."tasks" x
  where x."id" = delete_task.work_item
    and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  perform "better_supabase".emit_event('task.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'task', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_task"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_task"(uuid) to authenticated, service_role;

-- An item and everything under it with its depth. An item without its own
-- progress takes the share of its open and completed children that are
-- completed, so a Gantt group shows a rollup.
create or replace function "better_supabase"."task_tree"(root uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with recursive tree as (
    select x.*, 0 as depth from "better_supabase"."tasks" x where x."id" = task_tree.root
    union all
    select y.*, tree.depth + 1 from "better_supabase"."tasks" y join tree on y."parent_id" = tree."id"
    where tree.depth < 100 and y."archived_at" is null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', tree."id", 'parentId', tree."parent_id", 'identifier', tree."identifier", 'title', tree."title",
    'state', tree."state", 'startAt', tree."start_at", 'endAt', tree."end_at", 'dueAt', tree."due_at",
    'locked', tree."locked", 'depth', tree.depth,
    'progress', coalesce(tree."progress", (
      select case when count(*) filter (where ch."state" <> 'canceled') = 0 then
          case tree."state" when 'completed' then 100 else 0 end
        else round(100.0 * count(*) filter (where ch."state" = 'completed') / count(*) filter (where ch."state" <> 'canceled'))::integer end
      from "better_supabase"."tasks" ch where ch."parent_id" = tree."id" and ch."archived_at" is null))
  ) order by tree.depth, tree."rank" collate "C", tree."id"), '[]'::jsonb)
  from tree
$$;
revoke execute on function "better_supabase"."task_tree"(uuid) from public, anon;
grant execute on function "better_supabase"."task_tree"(uuid) to authenticated, service_role;

-- A page of a tenant's active items, newest first. filter keys: teamId,
-- projectId, iterationId, parentId, assigneeId, states (a list), open
-- (only unclosed). search matches the title and identifier. after continues
-- after that item.
create or replace function "better_supabase"."list_tasks"(tenant uuid, filter jsonb, search text, after uuid, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.number desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'task' and rr."subject_id" = x."id"::text)) as value, x."number" as number
    from "better_supabase"."tasks" x
    where x."tenant_id" = list_tasks.tenant and x."archived_at" is null
      and (list_tasks.filter ->> 'teamId' is null or x."team_id" = (list_tasks.filter ->> 'teamId')::uuid)
      and (list_tasks.filter ->> 'projectId' is null or x."project_id" = (list_tasks.filter ->> 'projectId')::uuid)
      and (list_tasks.filter ->> 'iterationId' is null or x."iteration_id" = (list_tasks.filter ->> 'iterationId')::uuid)
      and (list_tasks.filter ->> 'parentId' is null or x."parent_id" = (list_tasks.filter ->> 'parentId')::uuid)
      and (list_tasks.filter ->> 'assigneeId' is null or exists (select 1 from "better_supabase"."task_assignees" y where y."task_id" = x."id" and y."user_id" = (list_tasks.filter ->> 'assigneeId')::uuid))
      and (list_tasks.filter -> 'states' is null or x."state" = any (array(select jsonb_array_elements_text(list_tasks.filter -> 'states'))))
      and (coalesce((list_tasks.filter ->> 'open')::boolean, false) = false or x."closed_at" is null)
      and (list_tasks.search is null or x."title" ilike '%' || list_tasks.search || '%' or x."identifier" ilike list_tasks.search || '%')
      and (list_tasks.after is null or x."number" < (select z."number" from "better_supabase"."tasks" z where z."id" = list_tasks.after))
    order by x."number" desc
    limit least(greatest(coalesce(list_tasks.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."list_tasks"(uuid, jsonb, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_tasks"(uuid, jsonb, text, uuid, integer) to authenticated, service_role;

-- Adds a checklist item (checklist_item null) or changes one: title, done,
-- rank. A new item without a rank goes last.
create or replace function "better_supabase"."save_task_checklist_item"(work_item uuid, checklist_item uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
  v_id uuid := save_task_checklist_item.checklist_item;
  v_last text;
  v_done boolean := (save_task_checklist_item.attrs ->> 'done')::boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."tasks" x where x."id" = save_task_checklist_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  begin
    if v_id is null then
      select max(y."rank") into v_last from "better_supabase"."task_checklist_items" y where y."task_id" = v_row."id";
      insert into "better_supabase"."task_checklist_items" ("tenant_id", "task_id", "title", "done", "done_at", "done_by", "rank", "created_by")
      values (v_row."tenant_id", v_row."id", trim(save_task_checklist_item.attrs ->> 'title'), coalesce(v_done, false),
        case when v_done then now() end, case when v_done then auth.uid() end,
        coalesce(save_task_checklist_item.attrs ->> 'rank', case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end), auth.uid())
      returning "id" into v_id;
    else
      update "better_supabase"."task_checklist_items" y set
        "title" = coalesce(trim(save_task_checklist_item.attrs ->> 'title'), y."title"),
        "rank" = coalesce(save_task_checklist_item.attrs ->> 'rank', y."rank"),
        "done" = coalesce(v_done, y."done"),
        "done_at" = case when v_done is null then y."done_at" when v_done then coalesce(y."done_at", now()) end,
        "done_by" = case when v_done is null then y."done_by" when v_done then coalesce(y."done_by", auth.uid()) end
      where y."id" = v_id and y."task_id" = v_row."id";
      if not found then
        raise exception 'no such checklist item on this work item' using errcode = 'P0002', hint = 'TASK_CHECKLIST_ITEM_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a checklist item needs a title of 1 to 500 characters and a valid rank' using errcode = '22023', hint = 'TASK_CHECKLIST_ITEM_INVALID';
  end;
  perform "better_supabase".emit_event('task.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'task', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist')), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select jsonb_build_object('id', y."id", 'workItemId', y."task_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") from "better_supabase"."task_checklist_items" y where y."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_task_checklist_item"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_task_checklist_item"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_task_checklist_item"(checklist_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x.* into v_row from "better_supabase"."tasks" x join "better_supabase"."task_checklist_items" y on y."task_id" = x."id"
  where y."id" = delete_task_checklist_item.checklist_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    return false;
  end if;
  delete from "better_supabase"."task_checklist_items" y where y."id" = delete_task_checklist_item.checklist_item;
  perform "better_supabase".emit_event('task.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'task', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist')), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_task_checklist_item"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_task_checklist_item"(uuid) to authenticated, service_role;

-- An item's checklist, in rank order.
create or replace function "better_supabase"."list_task_checklist"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'workItemId', y."task_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") order by y."rank" collate "C", y."id"), '[]'::jsonb)
  from "better_supabase"."task_checklist_items" y where y."task_id" = list_task_checklist.work_item
$$;
revoke execute on function "better_supabase"."list_task_checklist"(uuid) from public, anon;
grant execute on function "better_supabase"."list_task_checklist"(uuid) to authenticated, service_role;

-- One item the caller can read, or null.
create or replace function "better_supabase"."get_task"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'task' and rr."subject_id" = x."id"::text)) from "better_supabase"."tasks" x where x."id" = get_task.work_item
$$;
revoke execute on function "better_supabase"."get_task"(uuid) from public, anon;
grant execute on function "better_supabase"."get_task"(uuid) to authenticated, service_role;

-- Makes an item repeat: rrule is an RFC 5545 RRULE starting at the item's
-- due date (now without one) in tzid. A null rrule stops it. Completing the
-- item then creates the next one through repeat_task.
create or replace function "better_supabase"."set_task_recurrence"(work_item uuid, rrule text, tzid text default 'UTC')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."tasks" x where x."id" = set_task_recurrence.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if set_task_recurrence.rrule is null then
    delete from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = v_row."tenant_id" and rr."subject_type" = 'task' and rr."subject_id" = v_row."id"::text;
  else
    if set_task_recurrence.rrule !~ '^(RRULE:)?FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)(;[A-Z]+=[-+,0-9A-Z]+)*$' then
      raise exception 'rrule must be an RRULE such as FREQ=WEEKLY;BYDAY=MO' using errcode = '22023', hint = 'TASK_RECURRENCE_INVALID';
    end if;
    if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = coalesce(set_task_recurrence.tzid, 'UTC')) then
      raise exception 'tzid must be an IANA time zone' using errcode = '22023', hint = 'TASK_RECURRENCE_INVALID';
    end if;
    insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
    values (v_row."tenant_id", 'task', v_row."id"::text, coalesce(v_row."due_at", now()), coalesce(set_task_recurrence.tzid, 'UTC'), regexp_replace(set_task_recurrence.rrule, '^RRULE:', ''))
    on conflict ("tenant_id", "subject_type", "subject_id")
    do update set "dtstart" = excluded."dtstart", "tzid" = excluded."tzid", "rrule" = excluded."rrule";
  end if;
  perform "better_supabase".emit_event('task.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'task', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('recurrence')), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'task' and rr."subject_id" = x."id"::text)) -> 'recurrence' from "better_supabase"."tasks" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."set_task_recurrence"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."set_task_recurrence"(uuid, text, text) to authenticated, service_role;

-- Creates the next item of a repeating item, due at due_at: a copy with its
-- dates shifted, its assignees and an unchecked checklist. The rule moves to
-- the copy. Runs once per item; a second call returns the same copy.
create or replace function "better_supabase"."repeat_task"(work_item uuid, due_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_src "better_supabase"."tasks";
  v_next jsonb;
  v_id uuid;
  v_shift interval;
begin
  select * into v_src from "better_supabase"."tasks" x where x."id" = repeat_task.work_item for update;
  if v_src."id" is null then
    raise exception 'work item not found' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  select x."id" into v_id from "better_supabase"."tasks" x where x."recurs_from" = v_src."id";
  if v_id is not null then
    return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'task' and rr."subject_id" = x."id"::text)) from "better_supabase"."tasks" x where x."id" = v_id);
  end if;
  v_shift := coalesce(repeat_task.due_at - coalesce(v_src."due_at", v_src."end_at", v_src."start_at"), interval '0');
  v_next := "better_supabase"."create_task"(v_src."tenant_id", jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title", 'body', v_src."body", 'parentId', v_src."parent_id", 'teamId', v_src."team_id",
    'projectId', v_src."project_id", 'priority', v_src."priority", 'estimate', v_src."estimate",
    'startAt', v_src."start_at" + v_shift, 'endAt', v_src."end_at" + v_shift, 'dueAt', repeat_task.due_at,
    'pipelineId', v_src."pipeline_id")),
    array(select y."user_id" from "better_supabase"."task_assignees" y where y."task_id" = v_src."id"));
  v_id := (v_next ->> 'id')::uuid;
  update "better_supabase"."tasks" x set "recurs_from" = v_src."id" where x."id" = v_id;
  insert into "better_supabase"."task_checklist_items" ("tenant_id", "task_id", "title", "rank", "created_by")
  select y."tenant_id", v_id, y."title", y."rank", y."created_by" from "better_supabase"."task_checklist_items" y where y."task_id" = v_src."id";
  update "better_supabase"."recurrence_rules" rr set "subject_id" = v_id::text
  where rr."tenant_id" = v_src."tenant_id" and rr."subject_type" = 'task' and rr."subject_id" = v_src."id"::text;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'task' and rr."subject_id" = x."id"::text)) from "better_supabase"."tasks" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."repeat_task"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."repeat_task"(uuid, timestamptz) to service_role;

-- Watches (all), follows (participating) or ignores an item the caller can
-- read; a null level removes the choice.
create or replace function "better_supabase"."watch_task"(work_item uuid, level text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
begin
  select * into v_row from "better_supabase"."tasks" x where x."id" = watch_task.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can read' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  perform "better_supabase"."set_notification_subscription"('task', v_row."id"::text, watch_task.level, v_row."tenant_id");
  return watch_task.level is not null;
end;
$$;
revoke execute on function "better_supabase"."watch_task"(uuid, text) from public, anon;
grant execute on function "better_supabase"."watch_task"(uuid, text) to authenticated, service_role;

-- Who watches (all) or follows (participating) an item: [{ userId, level }].
create or replace function "better_supabase"."list_task_watchers"(work_item uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', s."user_id", 'level', s."level") order by s."level", s."user_id"), '[]'::jsonb)
  from "better_supabase"."tasks" x
  join "better_supabase"."notification_subscriptions" s on s."subject_type" = 'task' and s."subject_id" = x."id"::text
    and s."organization_id" = x."tenant_id"
  where x."id" = list_task_watchers.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)) and s."level" in ('all', 'participating')
$$;
revoke execute on function "better_supabase"."list_task_watchers"(uuid) from public, anon;
grant execute on function "better_supabase"."list_task_watchers"(uuid) to authenticated, service_role;

-- Creates a project (project null) or changes the keys attrs names: key,
-- name, ownerId, status, startOn, targetOn, archived, and the budget:
-- budgetAmount (minor units as text) with budgetCurrency, and budgetHours.
-- With accounting, the project is a value of the project dimension.
create or replace function "better_supabase"."save_project"(tenant uuid, project uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_project.project;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_project.tenant, 'tasks.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."projects" ("tenant_id", "key", "name", "owner_user_id", "status", "start_on", "target_on", "budget_amount", "budget_currency", "budget_hours")
      values (save_project.tenant, upper(save_project.attrs ->> 'key'), save_project.attrs ->> 'name', (save_project.attrs ->> 'ownerId')::uuid,
        coalesce(save_project.attrs ->> 'status', 'planned'), (save_project.attrs ->> 'startOn')::date, (save_project.attrs ->> 'targetOn')::date,
        (save_project.attrs ->> 'budgetAmount')::bigint, upper(save_project.attrs ->> 'budgetCurrency'), (save_project.attrs ->> 'budgetHours')::numeric)
      returning "id" into v_id;
    else
      update "better_supabase"."projects" x set
        "key" = coalesce(upper(save_project.attrs ->> 'key'), x."key"),
        "name" = coalesce(save_project.attrs ->> 'name', x."name"),
        "owner_user_id" = case when save_project.attrs ? 'ownerId' then (save_project.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
        "status" = coalesce(save_project.attrs ->> 'status', x."status"),
        "start_on" = case when save_project.attrs ? 'startOn' then (save_project.attrs ->> 'startOn')::date else x."start_on" end,
        "target_on" = case when save_project.attrs ? 'targetOn' then (save_project.attrs ->> 'targetOn')::date else x."target_on" end,
        "budget_amount" = case when save_project.attrs ? 'budgetAmount' then (save_project.attrs ->> 'budgetAmount')::bigint else x."budget_amount" end,
        "budget_currency" = case when save_project.attrs ? 'budgetCurrency' then upper(save_project.attrs ->> 'budgetCurrency') else x."budget_currency" end,
        "budget_hours" = case when save_project.attrs ? 'budgetHours' then (save_project.attrs ->> 'budgetHours')::numeric else x."budget_hours" end,
        "archived_at" = case when save_project.attrs ? 'archived' then (case when (save_project.attrs ->> 'archived')::boolean then coalesce(x."archived_at", now()) end) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_project.tenant;
      if not found then
        raise exception 'project not found' using errcode = 'P0002', hint = 'TASK_PROJECT_NOT_FOUND';
      end if;
    end if;
    if exists (
      select 1 from "better_supabase"."projects" x
      where x."id" = v_id and x."budget_amount" is not null and x."budget_currency" is null
    ) then
      raise exception 'a budget amount needs a currency' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
    end if;
  exception when unique_violation then
    raise exception 'another project has this key' using errcode = '23505', hint = 'TASK_PROJECT_KEY_TAKEN';
  when check_violation or not_null_violation then
    raise exception 'a project needs a key of capitals and a name, and ends after it starts' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end;

  perform "better_supabase"."accounting_sync_dimension_value"(x."tenant_id", 'project', 'Project', x."id"::text, x."key" || ' ' || x."name", x."archived_at" is not null)
  from "better_supabase"."projects" x where x."id" = v_id;
  return (select to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."tasks" y where y."project_id" = x."id" and y."archived_at" is null
    )) from "better_supabase"."projects" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_project"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_project"(uuid, uuid, jsonb) to authenticated, service_role;

-- Creates an iteration (a cycle or a sprint) or changes it: name, teamId,
-- startsOn, endsOn.
create or replace function "better_supabase"."save_iteration"(tenant uuid, iteration uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_iteration.iteration;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_iteration.tenant, 'tasks.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."iterations" ("tenant_id", "team_id", "name", "starts_on", "ends_on")
      values (save_iteration.tenant, (save_iteration.attrs ->> 'teamId')::uuid, save_iteration.attrs ->> 'name',
        (save_iteration.attrs ->> 'startsOn')::date, (save_iteration.attrs ->> 'endsOn')::date)
      returning "id" into v_id;
    else
      update "better_supabase"."iterations" x set
        "name" = coalesce(save_iteration.attrs ->> 'name', x."name"),
        "starts_on" = coalesce((save_iteration.attrs ->> 'startsOn')::date, x."starts_on"),
        "ends_on" = coalesce((save_iteration.attrs ->> 'endsOn')::date, x."ends_on")
      where x."id" = v_id and x."tenant_id" = save_iteration.tenant;
      if not found then
        raise exception 'iteration not found' using errcode = 'P0002', hint = 'TASK_ITERATION_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation then
    raise exception 'an iteration needs a name and ends on or after it starts' using errcode = '22023', hint = 'TASK_ITERATION_INVALID';
  end;
  return (select to_jsonb(x) from "better_supabase"."iterations" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_iteration"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_iteration"(uuid, uuid, jsonb) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."tasks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tasks";
create policy bsb_tenant_scope_select on "better_supabase"."tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tasks";
create policy bsb_tenant_scope_insert on "better_supabase"."tasks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tasks";
create policy bsb_tenant_scope_update on "better_supabase"."tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tasks";
create policy bsb_tenant_scope_delete on "better_supabase"."tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."task_checklist_items";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_select on "better_supabase"."task_checklist_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_insert on "better_supabase"."task_checklist_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_update on "better_supabase"."task_checklist_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_delete on "better_supabase"."task_checklist_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."task_assignees";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_select on "better_supabase"."task_assignees" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_insert on "better_supabase"."task_assignees" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_update on "better_supabase"."task_assignees" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_delete on "better_supabase"."task_assignees" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."projects";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."projects";
create policy bsb_tenant_scope_select on "better_supabase"."projects" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."projects";
create policy bsb_tenant_scope_insert on "better_supabase"."projects" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."projects";
create policy bsb_tenant_scope_update on "better_supabase"."projects" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."projects";
create policy bsb_tenant_scope_delete on "better_supabase"."projects" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."iterations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."iterations";
create policy bsb_tenant_scope_select on "better_supabase"."iterations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."iterations";
create policy bsb_tenant_scope_insert on "better_supabase"."iterations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."iterations";
create policy bsb_tenant_scope_update on "better_supabase"."iterations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."iterations";
create policy bsb_tenant_scope_delete on "better_supabase"."iterations" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_091_tasks.sql
-- better-supabase module: tasks
-- @bsb-block-data tasks
-- @bsb-hash sha256:afa514c68143e087fdd8cde8f66f4d0ac61cc6223787cd12d0111278b84c8594
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."notification_events"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."notification_events" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."notification_subscriptions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."notification_subscriptions" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."incoming_webhooks"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."incoming_webhooks" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."guest_grants"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."guest_grants" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."attachments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."attachments" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."data_exports"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."data_exports" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."enrollments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."enrollments" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."workflow_runs"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."workflow_runs" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."workflow_start_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."workflow_start_requests" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."knowledge_documents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."knowledge_documents" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."memories"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."memories" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."taggings"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."taggings" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."status_history"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."status_history" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."status_stages"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."status_stages" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_lifecycles"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_lifecycles" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."field_values"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."field_values" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."share_links"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."share_links" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_views"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_views" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_user_state"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_user_state" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."recurrence_rules"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."recurrence_rules" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."reminders"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."reminders" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."import_records"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."import_records" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_members"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_members" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."relations"') and attname = 'source_type' and not attisdropped) then update "better_supabase"."relations" set "source_type" = 'task' where "source_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."relations"') and attname = 'target_type' and not attisdropped) then update "better_supabase"."relations" set "target_type" = 'task' where "target_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."bulk_runs"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."bulk_runs" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."search_documents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."search_documents" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."calendar_events"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."calendar_events" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."calendar_attendees"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."calendar_attendees" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."versions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."versions" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."trash_items"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."trash_items" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."reactions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."reactions" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."reaction_scores"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."reaction_scores" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."approval_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."approval_requests" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."approval_policies"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."approval_policies" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."access_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."access_requests" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."documents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."documents" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."form_submissions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."form_submissions" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."signature_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."signature_requests" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."time_entries"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."time_entries" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."template_applications"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."template_applications" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipelines"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipelines" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipeline_stage_history"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipeline_stage_history" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."engagement_subjects"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."engagement_subjects" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."sla_policies"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."sla_policies" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."sla_clocks"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."sla_clocks" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_collections"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_collections" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_collection_entries"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_collection_entries" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."collection_favorites"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."collection_favorites" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."saved_items"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."saved_items" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."moderation_items"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."moderation_items" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."reviews"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."reviews" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."review_stats"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."review_stats" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."automations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."automations" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."automation_defaults"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."automation_defaults" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."automation_evaluations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."automation_evaluations" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."automation_fields"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."automation_fields" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."score_models"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."score_models" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."scores"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."scores" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."passes"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."passes" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."work_orders"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."work_orders" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."shipments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."shipments" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."conversations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."conversations" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."message_record_mentions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."message_record_mentions" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."channels"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."channels" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."timeline_entries"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."timeline_entries" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."mail_thread_subjects"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."mail_thread_subjects" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."segments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."segments" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."assignment_queues"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."assignment_queues" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."assignments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."assignments" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."field_changes"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."field_changes" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."lead_score_checks"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."lead_score_checks" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."qualification_requirements"') and attname = 'target_type' and not attisdropped) then update "better_supabase"."qualification_requirements" set "target_type" = 'task' where "target_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."acknowledgement_assignments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."acknowledgement_assignments" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."acknowledgements"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."acknowledgements" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."acknowledgement_notices"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."acknowledgement_notices" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."consents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."consents" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."observations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."observations" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."medication_orders"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."medication_orders" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."care_plans"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."care_plans" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."bank_matches"') and attname = 'target_type' and not attisdropped) then update "better_supabase"."bank_matches" set "target_type" = 'task' where "target_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."funding_awards"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."funding_awards" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."funding_deliveries"') and attname = 'source_type' and not attisdropped) then update "better_supabase"."funding_deliveries" set "source_type" = 'task' where "source_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."care_alerts"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."care_alerts" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
-- Gives each existing project its value of the accounting project dimension.
select "better_supabase"."accounting_sync_dimension_value"(x."tenant_id", 'project', 'Project', x."id"::text, x."key" || ' ' || x."name", x."archived_at" is not null)
from "better_supabase"."projects" x
where exists (select 1 from "better_supabase"."accounting_settings" s where s."tenant_id" = x."tenant_id");

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_091_tasks.sql
-- better-supabase module: tasks
-- @bsb-block tasks@4 managed
-- @bsb-hash sha256:dbf1bd34463aaa12e24d7e55f10f1965eac2a6fb460adbd5035052b69320811f
-- Issues and tasks on pipelines: identifiers, parents without cycles, several assignees, priority 0 to 4, estimates, start, end and due dates, locking, projects, iterations, batched edits and a progress tree.
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
    drop policy if exists bsb_tenant_scope on "app_private"."tasks";
    drop policy if exists bsb_tenant_scope_select on "app_private"."tasks";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."tasks";
    drop policy if exists bsb_tenant_scope_update on "app_private"."tasks";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."tasks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_select on "app_private"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_update on "app_private"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."task_checklist_items";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."task_assignees";
    drop policy if exists bsb_tenant_scope_select on "app_private"."task_assignees";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."task_assignees";
    drop policy if exists bsb_tenant_scope_update on "app_private"."task_assignees";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."task_assignees";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."projects";
    drop policy if exists bsb_tenant_scope_select on "app_private"."projects";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."projects";
    drop policy if exists bsb_tenant_scope_update on "app_private"."projects";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."projects";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."iterations";
    drop policy if exists bsb_tenant_scope_select on "app_private"."iterations";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."iterations";
    drop policy if exists bsb_tenant_scope_update on "app_private"."iterations";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."iterations";
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
-- Work items on pipelines: issues and tasks with an identifier, a parent,
-- assignees, a priority, dates, projects and iterations.

create table if not exists "app_private"."projects" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[A-Z][A-Z0-9]{0,9}$'),
  "name" text not null check (length("name") between 1 and 200),
  "owner_user_id" uuid,
  "status" text not null default 'planned' check ("status" in ('planned', 'active', 'paused', 'completed', 'canceled')),
  "start_on" date,
  "target_on" date,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  check ("target_on" is null or "start_on" is null or "target_on" >= "start_on")
);
alter table "app_private"."projects" add column if not exists "budget_amount" bigint check ("budget_amount" >= 0);
alter table "app_private"."projects" add column if not exists "budget_currency" text check ("budget_currency" ~ '^[A-Z]{3}$');
alter table "app_private"."projects" add column if not exists "budget_hours" numeric(12, 2) check ("budget_hours" >= 0);
alter table "app_private"."projects" enable row level security;
revoke all on "app_private"."projects" from public, anon, authenticated;
grant select on "app_private"."projects" to authenticated;
grant all on "app_private"."projects" to service_role;
drop policy if exists projects_read on "app_private"."projects";
create policy projects_read on "app_private"."projects"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table if not exists "app_private"."iterations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "team_id" uuid,
  "name" text not null check (length("name") between 1 and 200),
  "starts_on" date not null,
  "ends_on" date not null,
  "created_at" timestamptz not null default now(),
  check ("ends_on" >= "starts_on")
);
create index if not exists iterations_tenant_idx on "app_private"."iterations" ("tenant_id", "team_id", "starts_on");
alter table "app_private"."iterations" enable row level security;
revoke all on "app_private"."iterations" from public, anon, authenticated;
grant select on "app_private"."iterations" to authenticated;
grant all on "app_private"."iterations" to service_role;
drop policy if exists iterations_read on "app_private"."iterations";
create policy iterations_read on "app_private"."iterations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table if not exists "app_private"."tasks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "title" text not null check (length("title") between 1 and 500),
  "body" text,
  "parent_id" uuid references "app_private"."tasks" ("id") on delete cascade,
  "team_id" uuid,
  "project_id" uuid references "app_private"."projects" ("id") on delete set null,
  "iteration_id" uuid references "app_private"."iterations" ("id") on delete set null,
  "priority" smallint not null default 0 check ("priority" between 0 and 4),
  "estimate" numeric(10, 2) check ("estimate" >= 0),
  "progress" smallint check ("progress" between 0 and 100),
  "start_at" timestamptz,
  "end_at" timestamptz,
  "due_at" timestamptz,
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  "state" text not null default 'backlog' check ("state" in ('triage', 'backlog', 'unstarted', 'started', 'completed', 'canceled')),
  "close_reason" text check ("close_reason" in ('completed', 'not_planned', 'duplicate')),
  "closed_at" timestamptz,
  "locked" boolean not null default false,
  "rank" text collate "C" not null default 'V',
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  check ("end_at" is null or "start_at" is null or "end_at" >= "start_at")
);
create index if not exists "tasks_board_idx" on "app_private"."tasks" ("pipeline_id", "stage_id", "rank");
create index if not exists "tasks_parent_idx" on "app_private"."tasks" ("parent_id");
create index if not exists "tasks_project_idx" on "app_private"."tasks" ("project_id");
create index if not exists "tasks_iteration_idx" on "app_private"."tasks" ("iteration_id");
create index if not exists "tasks_due_idx" on "app_private"."tasks" ("tenant_id", "due_at") where "closed_at" is null;
alter table "app_private"."tasks" enable row level security;
revoke all on "app_private"."tasks" from public, anon, authenticated;
grant select on "app_private"."tasks" to authenticated;
grant all on "app_private"."tasks" to service_role;
drop policy if exists tasks_read on "app_private"."tasks";
create policy tasks_read on "app_private"."tasks"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table if not exists "app_private"."task_assignees" (
  "tenant_id" uuid not null,
  "task_id" uuid not null references "app_private"."tasks" ("id") on delete cascade,
  "user_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("task_id", "user_id")
);
create index if not exists "task_assignees_user_idx" on "app_private"."task_assignees" ("user_id");
alter table "app_private"."task_assignees" enable row level security;
revoke all on "app_private"."task_assignees" from public, anon, authenticated;
grant select on "app_private"."task_assignees" to authenticated;
grant all on "app_private"."task_assignees" to service_role;
drop policy if exists task_assignees_read on "app_private"."task_assignees";
create policy task_assignees_read on "app_private"."task_assignees"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

alter table "app_private"."tasks" add column if not exists "recurs_from" uuid references "app_private"."tasks" ("id") on delete set null;
create unique index if not exists "tasks_recurs_from_idx" on "app_private"."tasks" ("recurs_from");

create table if not exists "app_private"."task_checklist_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "task_id" uuid not null references "app_private"."tasks" ("id") on delete cascade,
  "title" text not null check (length("title") between 1 and 500),
  "done" boolean not null default false,
  "done_at" timestamptz,
  "done_by" uuid,
  "rank" text collate "C" not null check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
create index if not exists "task_checklist_item_idx" on "app_private"."task_checklist_items" ("task_id", "rank");
alter table "app_private"."task_checklist_items" enable row level security;
revoke all on "app_private"."task_checklist_items" from public, anon, authenticated;
grant select on "app_private"."task_checklist_items" to authenticated;
grant all on "app_private"."task_checklist_items" to service_role;
drop policy if exists task_checklist_items_read on "app_private"."task_checklist_items";
create policy task_checklist_items_read on "app_private"."task_checklist_items"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create or replace function better_supabase.bsb_work_item_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."parent_id" is not null and (tg_op = 'INSERT' or new."parent_id" is distinct from old."parent_id") then
    if exists (
      with recursive up(id, depth) as (
        select new."parent_id", 1
        union all
        select x."parent_id", up.depth + 1 from "app_private"."tasks" x join up on x."id" = up.id
        where x."parent_id" is not null and up.depth < 100
      )
      select 1 from up where up.id = new."id"
    ) then
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'TASK_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "app_private"."tasks" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
      raise exception 'the parent is in another organization' using errcode = '22023', hint = 'TASK_PARENT_INVALID';
    end if;
  end if;
  if tg_op = 'UPDATE' and old."locked" and not (auth.role() = 'service_role') and (new."start_at" is distinct from old."start_at" or new."end_at" is distinct from old."end_at" or new."due_at" is distinct from old."due_at") then
    raise exception 'the item is locked; its dates can''t change' using errcode = '55000', hint = 'TASK_LOCKED';
  end if;
  if tg_op = 'INSERT' then
    if new."state" in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
    end if;
    return new;
  end if;
  if new."state" is distinct from old."state" then
    if new."state" in ('completed', 'canceled') and old."state" not in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
      if new."state" = 'completed' and new."progress" is not null then
        new."progress" := 100;
      end if;
      null;
    elsif not (new."state" in ('completed', 'canceled')) and old."state" in ('completed', 'canceled') then
      new."closed_at" := null;
      new."close_reason" := null;
      null;
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_work_item_guard() from public, anon, authenticated;
drop trigger if exists bsb_work_item_guard on "app_private"."tasks";
create trigger bsb_work_item_guard before insert or update on "app_private"."tasks"
for each row execute function better_supabase.bsb_work_item_guard();

-- Creates a work item. attrs: title (required), body, parentId, teamId,
-- projectId, iterationId, priority (0 none to 4 low, as Linear), estimate,
-- progress, startAt, endAt, dueAt, pipelineId, stageId, and fields (the
-- extra columns, by name). assignees: user ids.
create or replace function "app_private"."create_task"(tenant uuid, attrs jsonb, assignees uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seq bigint;
  v_identifier text;
  v_id uuid;
  v_row "app_private"."tasks";
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_task.tenant, 'tasks.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if nullif(trim(create_task.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'TASK_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_task_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_task.tenant, create_task.attrs;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'work_item' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'work_item' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_task.tenant::text || ':work_item', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "app_private"."tasks" x where x."tenant_id" = create_task.tenant;
  v_identifier := 'TASK-' || v_seq::text;
  end if;
  begin
    insert into "app_private"."tasks" ("tenant_id", "number", "identifier", "title", "body", "parent_id", "team_id", "project_id", "iteration_id",
      "priority", "estimate", "progress", "start_at", "end_at", "due_at", "pipeline_id", "stage_id", "created_by")
    values (create_task.tenant, v_seq, v_identifier, trim(create_task.attrs ->> 'title'), create_task.attrs ->> 'body',
      (create_task.attrs ->> 'parentId')::uuid, (create_task.attrs ->> 'teamId')::uuid, (create_task.attrs ->> 'projectId')::uuid,
      (create_task.attrs ->> 'iterationId')::uuid, coalesce((create_task.attrs ->> 'priority')::smallint, 0),
      (create_task.attrs ->> 'estimate')::numeric, (create_task.attrs ->> 'progress')::smallint,
      (create_task.attrs ->> 'startAt')::timestamptz, (create_task.attrs ->> 'endAt')::timestamptz, (create_task.attrs ->> 'dueAt')::timestamptz,
      (create_task.attrs ->> 'pipelineId')::uuid, (create_task.attrs ->> 'stageId')::uuid, auth.uid())
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  if cardinality(coalesce(create_task.assignees, '{}')) > 0 then
    perform "app_private"."set_task_assignees"(v_id, create_task.assignees);
  end if;
  select * into v_row from "app_private"."tasks" x where x."id" = v_id;
  if jsonb_array_length(coalesce((create_task.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      raise exception 'install the attachments block to attach files' using errcode = '0A000', hint = 'TASK_ATTACHMENTS_UNAVAILABLE';
    end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_task_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "app_private"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "app_private"."task_checklist_items" rk where rk."task_id" = x."id")) from "app_private"."tasks" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."create_task"(uuid, jsonb, uuid[]) from public, anon;
grant execute on function "app_private"."create_task"(uuid, jsonb, uuid[]) to authenticated, service_role;

-- Applies a batch of { workItemId, field, value } changes, each on its
-- own. Returns { accepted: [{ workItemId, field }], rejected: [{ workItemId,
-- field, hint, reason }] }. With atomic, the first change that fails raises
-- its error and no change is kept. The window field ({ startAt, endAt })
-- writes both ends in one update, so the end-after-start check sees both.
drop function if exists "app_private"."update_tasks"(jsonb);
create or replace function "app_private"."update_tasks"(changes jsonb, atomic boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_item uuid;
  v_field text;
  v_row "app_private"."tasks";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_tasks.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { workItemId, field, value }' using errcode = '22023', hint = 'TASK_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_tasks.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'workItemId')::uuid;
      if not exists (select 1 from "app_private"."tasks" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_task_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_item, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'title' then
        update "app_private"."tasks" x set "title" = trim(v_change -> 'value' #>> '{}') where x."id" = v_item;
      when 'body' then
        update "app_private"."tasks" x set "body" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'parentId' then
        update "app_private"."tasks" x set "parent_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'teamId' then
        update "app_private"."tasks" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'projectId' then
        update "app_private"."tasks" x set "project_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'iterationId' then
        update "app_private"."tasks" x set "iteration_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'priority' then
        update "app_private"."tasks" x set "priority" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'estimate' then
        update "app_private"."tasks" x set "estimate" = (v_change -> 'value' #>> '{}')::numeric where x."id" = v_item;
      when 'progress' then
        update "app_private"."tasks" x set "progress" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'startAt' then
        update "app_private"."tasks" x set "start_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'endAt' then
        update "app_private"."tasks" x set "end_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'dueAt' then
        update "app_private"."tasks" x set "due_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'stageId' then
        update "app_private"."tasks" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'closeReason' then
        update "app_private"."tasks" x set "close_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'window' then
        if jsonb_typeof(v_change -> 'value') <> 'object' then
          raise exception 'window must be an object of startAt and endAt' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
        end if;
        update "app_private"."tasks" x set
          "start_at" = case when v_change -> 'value' ? 'startAt' then (v_change -> 'value' ->> 'startAt')::timestamptz else x."start_at" end,
          "end_at" = case when v_change -> 'value' ? 'endAt' then (v_change -> 'value' ->> 'endAt')::timestamptz else x."end_at" end
        where x."id" = v_item;
      when 'attachments' then
        select * into v_row from "app_private"."tasks" x where x."id" = v_item;
        if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      raise exception 'install the attachments block to attach files' using errcode = '0A000', hint = 'TASK_ATTACHMENTS_UNAVAILABLE';
    end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'TASK_FIELD_UNKNOWN';
      end case;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('workItemId', v_item, 'field', v_field));
      v_touched := array_append(v_touched, v_item);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_task_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_item, v_field;
    end if;
  end;
    exception when others then
      if update_tasks.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_change ->> 'workItemId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "app_private"."tasks" x where x."id" = any (v_touched) loop
    null;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "app_private"."update_tasks"(jsonb, boolean) from public, anon;
grant execute on function "app_private"."update_tasks"(jsonb, boolean) to authenticated, service_role;

-- Replaces an item's assignees. Each one watches the item, and those who
-- weren't assigned before are notified. task.assigned is recorded only
-- when the call adds someone, with addedIds.
create or replace function "app_private"."set_task_assignees"(work_item uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."tasks";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_task_assignees.users, '{}')) x where x is not null);
  v_added uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."tasks" x where x."id" = set_task_assignees.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_added := array(select x from unnest(v_users) x where not exists (
    select 1 from "app_private"."task_assignees" y where y."task_id" = v_row."id" and y."user_id" = x));
  delete from "app_private"."task_assignees" y where y."task_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "app_private"."task_assignees" ("tenant_id", "task_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  if cardinality(v_added) > 0 then
    null;
  end if;
  return cardinality(v_users);
end;
$$;
revoke execute on function "app_private"."set_task_assignees"(uuid, uuid[]) from public, anon;
grant execute on function "app_private"."set_task_assignees"(uuid, uuid[]) to authenticated, service_role;

create or replace function "app_private"."archive_task"(work_item uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "app_private"."tasks" x set "archived_at" = case when archive_task.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_task.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_task.archived then
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "app_private"."archive_task"(uuid, boolean) from public, anon;
grant execute on function "app_private"."archive_task"(uuid, boolean) to authenticated, service_role;

-- Deletes an item and its children. Needs work_items.manage, or its author.
create or replace function "app_private"."delete_task"(work_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "app_private"."tasks" x
  where x."id" = delete_task.work_item
    and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_task"(uuid) from public, anon;
grant execute on function "app_private"."delete_task"(uuid) to authenticated, service_role;

-- An item and everything under it with its depth. An item without its own
-- progress takes the share of its open and completed children that are
-- completed, so a Gantt group shows a rollup.
create or replace function "app_private"."task_tree"(root uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with recursive tree as (
    select x.*, 0 as depth from "app_private"."tasks" x where x."id" = task_tree.root
    union all
    select y.*, tree.depth + 1 from "app_private"."tasks" y join tree on y."parent_id" = tree."id"
    where tree.depth < 100 and y."archived_at" is null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', tree."id", 'parentId', tree."parent_id", 'identifier', tree."identifier", 'title', tree."title",
    'state', tree."state", 'startAt', tree."start_at", 'endAt', tree."end_at", 'dueAt', tree."due_at",
    'locked', tree."locked", 'depth', tree.depth,
    'progress', coalesce(tree."progress", (
      select case when count(*) filter (where ch."state" <> 'canceled') = 0 then
          case tree."state" when 'completed' then 100 else 0 end
        else round(100.0 * count(*) filter (where ch."state" = 'completed') / count(*) filter (where ch."state" <> 'canceled'))::integer end
      from "app_private"."tasks" ch where ch."parent_id" = tree."id" and ch."archived_at" is null))
  ) order by tree.depth, tree."rank" collate "C", tree."id"), '[]'::jsonb)
  from tree
$$;
revoke execute on function "app_private"."task_tree"(uuid) from public, anon;
grant execute on function "app_private"."task_tree"(uuid) to authenticated, service_role;

-- A page of a tenant's active items, newest first. filter keys: teamId,
-- projectId, iterationId, parentId, assigneeId, states (a list), open
-- (only unclosed). search matches the title and identifier. after continues
-- after that item.
create or replace function "app_private"."list_tasks"(tenant uuid, filter jsonb, search text, after uuid, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.number desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "app_private"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "app_private"."task_checklist_items" rk where rk."task_id" = x."id")) as value, x."number" as number
    from "app_private"."tasks" x
    where x."tenant_id" = list_tasks.tenant and x."archived_at" is null
      and (list_tasks.filter ->> 'teamId' is null or x."team_id" = (list_tasks.filter ->> 'teamId')::uuid)
      and (list_tasks.filter ->> 'projectId' is null or x."project_id" = (list_tasks.filter ->> 'projectId')::uuid)
      and (list_tasks.filter ->> 'iterationId' is null or x."iteration_id" = (list_tasks.filter ->> 'iterationId')::uuid)
      and (list_tasks.filter ->> 'parentId' is null or x."parent_id" = (list_tasks.filter ->> 'parentId')::uuid)
      and (list_tasks.filter ->> 'assigneeId' is null or exists (select 1 from "app_private"."task_assignees" y where y."task_id" = x."id" and y."user_id" = (list_tasks.filter ->> 'assigneeId')::uuid))
      and (list_tasks.filter -> 'states' is null or x."state" = any (array(select jsonb_array_elements_text(list_tasks.filter -> 'states'))))
      and (coalesce((list_tasks.filter ->> 'open')::boolean, false) = false or x."closed_at" is null)
      and (list_tasks.search is null or x."title" ilike '%' || list_tasks.search || '%' or x."identifier" ilike list_tasks.search || '%')
      and (list_tasks.after is null or x."number" < (select z."number" from "app_private"."tasks" z where z."id" = list_tasks.after))
    order by x."number" desc
    limit least(greatest(coalesce(list_tasks.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "app_private"."list_tasks"(uuid, jsonb, text, uuid, integer) from public, anon;
grant execute on function "app_private"."list_tasks"(uuid, jsonb, text, uuid, integer) to authenticated, service_role;

-- Adds a checklist item (checklist_item null) or changes one: title, done,
-- rank. A new item without a rank goes last.
create or replace function "app_private"."save_task_checklist_item"(work_item uuid, checklist_item uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."tasks";
  v_id uuid := save_task_checklist_item.checklist_item;
  v_last text;
  v_done boolean := (save_task_checklist_item.attrs ->> 'done')::boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."tasks" x where x."id" = save_task_checklist_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  begin
    if v_id is null then
      select max(y."rank") into v_last from "app_private"."task_checklist_items" y where y."task_id" = v_row."id";
      insert into "app_private"."task_checklist_items" ("tenant_id", "task_id", "title", "done", "done_at", "done_by", "rank", "created_by")
      values (v_row."tenant_id", v_row."id", trim(save_task_checklist_item.attrs ->> 'title'), coalesce(v_done, false),
        case when v_done then now() end, case when v_done then auth.uid() end,
        coalesce(save_task_checklist_item.attrs ->> 'rank', case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end), auth.uid())
      returning "id" into v_id;
    else
      update "app_private"."task_checklist_items" y set
        "title" = coalesce(trim(save_task_checklist_item.attrs ->> 'title'), y."title"),
        "rank" = coalesce(save_task_checklist_item.attrs ->> 'rank', y."rank"),
        "done" = coalesce(v_done, y."done"),
        "done_at" = case when v_done is null then y."done_at" when v_done then coalesce(y."done_at", now()) end,
        "done_by" = case when v_done is null then y."done_by" when v_done then coalesce(y."done_by", auth.uid()) end
      where y."id" = v_id and y."task_id" = v_row."id";
      if not found then
        raise exception 'no such checklist item on this work item' using errcode = 'P0002', hint = 'TASK_CHECKLIST_ITEM_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a checklist item needs a title of 1 to 500 characters and a valid rank' using errcode = '22023', hint = 'TASK_CHECKLIST_ITEM_INVALID';
  end;
  null;
  return (select jsonb_build_object('id', y."id", 'workItemId', y."task_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") from "app_private"."task_checklist_items" y where y."id" = v_id);
end;
$$;
revoke execute on function "app_private"."save_task_checklist_item"(uuid, uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_task_checklist_item"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "app_private"."delete_task_checklist_item"(checklist_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x.* into v_row from "app_private"."tasks" x join "app_private"."task_checklist_items" y on y."task_id" = x."id"
  where y."id" = delete_task_checklist_item.checklist_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    return false;
  end if;
  delete from "app_private"."task_checklist_items" y where y."id" = delete_task_checklist_item.checklist_item;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_task_checklist_item"(uuid) from public, anon;
grant execute on function "app_private"."delete_task_checklist_item"(uuid) to authenticated, service_role;

-- An item's checklist, in rank order.
create or replace function "app_private"."list_task_checklist"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'workItemId', y."task_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") order by y."rank" collate "C", y."id"), '[]'::jsonb)
  from "app_private"."task_checklist_items" y where y."task_id" = list_task_checklist.work_item
$$;
revoke execute on function "app_private"."list_task_checklist"(uuid) from public, anon;
grant execute on function "app_private"."list_task_checklist"(uuid) to authenticated, service_role;

-- One item the caller can read, or null.
create or replace function "app_private"."get_task"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "app_private"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "app_private"."task_checklist_items" rk where rk."task_id" = x."id")) from "app_private"."tasks" x where x."id" = get_task.work_item
$$;
revoke execute on function "app_private"."get_task"(uuid) from public, anon;
grant execute on function "app_private"."get_task"(uuid) to authenticated, service_role;

-- Creates a project (project null) or changes the keys attrs names: key,
-- name, ownerId, status, startOn, targetOn, archived, and the budget:
-- budgetAmount (minor units as text) with budgetCurrency, and budgetHours.
-- With accounting, the project is a value of the project dimension.
create or replace function "app_private"."save_project"(tenant uuid, project uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_project.project;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_project.tenant, 'tasks.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "app_private"."projects" ("tenant_id", "key", "name", "owner_user_id", "status", "start_on", "target_on", "budget_amount", "budget_currency", "budget_hours")
      values (save_project.tenant, upper(save_project.attrs ->> 'key'), save_project.attrs ->> 'name', (save_project.attrs ->> 'ownerId')::uuid,
        coalesce(save_project.attrs ->> 'status', 'planned'), (save_project.attrs ->> 'startOn')::date, (save_project.attrs ->> 'targetOn')::date,
        (save_project.attrs ->> 'budgetAmount')::bigint, upper(save_project.attrs ->> 'budgetCurrency'), (save_project.attrs ->> 'budgetHours')::numeric)
      returning "id" into v_id;
    else
      update "app_private"."projects" x set
        "key" = coalesce(upper(save_project.attrs ->> 'key'), x."key"),
        "name" = coalesce(save_project.attrs ->> 'name', x."name"),
        "owner_user_id" = case when save_project.attrs ? 'ownerId' then (save_project.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
        "status" = coalesce(save_project.attrs ->> 'status', x."status"),
        "start_on" = case when save_project.attrs ? 'startOn' then (save_project.attrs ->> 'startOn')::date else x."start_on" end,
        "target_on" = case when save_project.attrs ? 'targetOn' then (save_project.attrs ->> 'targetOn')::date else x."target_on" end,
        "budget_amount" = case when save_project.attrs ? 'budgetAmount' then (save_project.attrs ->> 'budgetAmount')::bigint else x."budget_amount" end,
        "budget_currency" = case when save_project.attrs ? 'budgetCurrency' then upper(save_project.attrs ->> 'budgetCurrency') else x."budget_currency" end,
        "budget_hours" = case when save_project.attrs ? 'budgetHours' then (save_project.attrs ->> 'budgetHours')::numeric else x."budget_hours" end,
        "archived_at" = case when save_project.attrs ? 'archived' then (case when (save_project.attrs ->> 'archived')::boolean then coalesce(x."archived_at", now()) end) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_project.tenant;
      if not found then
        raise exception 'project not found' using errcode = 'P0002', hint = 'TASK_PROJECT_NOT_FOUND';
      end if;
    end if;
    if exists (
      select 1 from "app_private"."projects" x
      where x."id" = v_id and x."budget_amount" is not null and x."budget_currency" is null
    ) then
      raise exception 'a budget amount needs a currency' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
    end if;
  exception when unique_violation then
    raise exception 'another project has this key' using errcode = '23505', hint = 'TASK_PROJECT_KEY_TAKEN';
  when check_violation or not_null_violation then
    raise exception 'a project needs a key of capitals and a name, and ends after it starts' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end;

  return (select to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "app_private"."tasks" y where y."project_id" = x."id" and y."archived_at" is null
    )) from "app_private"."projects" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."save_project"(uuid, uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_project"(uuid, uuid, jsonb) to authenticated, service_role;

-- Creates an iteration (a cycle or a sprint) or changes it: name, teamId,
-- startsOn, endsOn.
create or replace function "app_private"."save_iteration"(tenant uuid, iteration uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_iteration.iteration;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_iteration.tenant, 'tasks.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "app_private"."iterations" ("tenant_id", "team_id", "name", "starts_on", "ends_on")
      values (save_iteration.tenant, (save_iteration.attrs ->> 'teamId')::uuid, save_iteration.attrs ->> 'name',
        (save_iteration.attrs ->> 'startsOn')::date, (save_iteration.attrs ->> 'endsOn')::date)
      returning "id" into v_id;
    else
      update "app_private"."iterations" x set
        "name" = coalesce(save_iteration.attrs ->> 'name', x."name"),
        "starts_on" = coalesce((save_iteration.attrs ->> 'startsOn')::date, x."starts_on"),
        "ends_on" = coalesce((save_iteration.attrs ->> 'endsOn')::date, x."ends_on")
      where x."id" = v_id and x."tenant_id" = save_iteration.tenant;
      if not found then
        raise exception 'iteration not found' using errcode = 'P0002', hint = 'TASK_ITERATION_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation then
    raise exception 'an iteration needs a name and ends on or after it starts' using errcode = '22023', hint = 'TASK_ITERATION_INVALID';
  end;
  return (select to_jsonb(x) from "app_private"."iterations" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."save_iteration"(uuid, uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_iteration"(uuid, uuid, jsonb) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."tasks";
drop policy if exists bsb_tenant_scope_select on "app_private"."tasks";
create policy bsb_tenant_scope_select on "app_private"."tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."tasks";
create policy bsb_tenant_scope_insert on "app_private"."tasks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."tasks";
create policy bsb_tenant_scope_update on "app_private"."tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."tasks";
create policy bsb_tenant_scope_delete on "app_private"."tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."task_checklist_items";
drop policy if exists bsb_tenant_scope_select on "app_private"."task_checklist_items";
create policy bsb_tenant_scope_select on "app_private"."task_checklist_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."task_checklist_items";
create policy bsb_tenant_scope_insert on "app_private"."task_checklist_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."task_checklist_items";
create policy bsb_tenant_scope_update on "app_private"."task_checklist_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."task_checklist_items";
create policy bsb_tenant_scope_delete on "app_private"."task_checklist_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."task_assignees";
drop policy if exists bsb_tenant_scope_select on "app_private"."task_assignees";
create policy bsb_tenant_scope_select on "app_private"."task_assignees" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."task_assignees";
create policy bsb_tenant_scope_insert on "app_private"."task_assignees" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."task_assignees";
create policy bsb_tenant_scope_update on "app_private"."task_assignees" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."task_assignees";
create policy bsb_tenant_scope_delete on "app_private"."task_assignees" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."projects";
drop policy if exists bsb_tenant_scope_select on "app_private"."projects";
create policy bsb_tenant_scope_select on "app_private"."projects" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."projects";
create policy bsb_tenant_scope_insert on "app_private"."projects" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."projects";
create policy bsb_tenant_scope_update on "app_private"."projects" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."projects";
create policy bsb_tenant_scope_delete on "app_private"."projects" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."iterations";
drop policy if exists bsb_tenant_scope_select on "app_private"."iterations";
create policy bsb_tenant_scope_select on "app_private"."iterations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."iterations";
create policy bsb_tenant_scope_insert on "app_private"."iterations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."iterations";
create policy bsb_tenant_scope_update on "app_private"."iterations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."iterations";
create policy bsb_tenant_scope_delete on "app_private"."iterations" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_091_tasks.sql
-- better-supabase module: tasks
-- @bsb-block-data tasks
-- @bsb-hash sha256:ea8a7f6275992a7e6c1d4e1fb480479290ca96436b7d2cd1815c10fb28bbf310
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_members"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_members" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipelines"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipelines" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipeline_stage_history"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipeline_stage_history" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_091_tasks.sql
-- better-supabase module: tasks
-- @bsb-block tasks@4 managed
-- @bsb-hash sha256:6776c3a70e587d5f3987f3830b8a7873af38e77cf136aaffeb06a0c2e571dbb4
-- Issues and tasks on pipelines: identifiers, parents without cycles, several assignees, priority 0 to 4, estimates, start, end and due dates, locking, projects, iterations, batched edits and a progress tree.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tasks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_checklist_items";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_assignees";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."projects";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."iterations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Work items on pipelines: issues and tasks with an identifier, a parent,
-- assignees, a priority, dates, projects and iterations.

create table if not exists "better_supabase"."projects" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[A-Z][A-Z0-9]{0,9}$'),
  "name" text not null check (length("name") between 1 and 200),
  "owner_user_id" uuid,
  "status" text not null default 'planned' check ("status" in ('planned', 'active', 'paused', 'completed', 'canceled')),
  "start_on" date,
  "target_on" date,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  check ("target_on" is null or "start_on" is null or "target_on" >= "start_on")
);
alter table "better_supabase"."projects" add column if not exists "budget_amount" bigint check ("budget_amount" >= 0);
alter table "better_supabase"."projects" add column if not exists "budget_currency" text check ("budget_currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."projects" add column if not exists "budget_hours" numeric(12, 2) check ("budget_hours" >= 0);
alter table "better_supabase"."projects" enable row level security;
revoke all on "better_supabase"."projects" from public, anon, authenticated;
grant select on "better_supabase"."projects" to authenticated;
grant all on "better_supabase"."projects" to service_role;
drop policy if exists projects_read on "better_supabase"."projects";
create policy projects_read on "better_supabase"."projects"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table if not exists "better_supabase"."iterations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "team_id" uuid,
  "name" text not null check (length("name") between 1 and 200),
  "starts_on" date not null,
  "ends_on" date not null,
  "created_at" timestamptz not null default now(),
  check ("ends_on" >= "starts_on")
);
create index if not exists iterations_tenant_idx on "better_supabase"."iterations" ("tenant_id", "team_id", "starts_on");
alter table "better_supabase"."iterations" enable row level security;
revoke all on "better_supabase"."iterations" from public, anon, authenticated;
grant select on "better_supabase"."iterations" to authenticated;
grant all on "better_supabase"."iterations" to service_role;
drop policy if exists iterations_read on "better_supabase"."iterations";
create policy iterations_read on "better_supabase"."iterations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table if not exists "better_supabase"."tasks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "title" text not null check (length("title") between 1 and 500),
  "body" text,
  "parent_id" uuid references "better_supabase"."tasks" ("id") on delete cascade,
  "team_id" uuid,
  "project_id" uuid references "better_supabase"."projects" ("id") on delete set null,
  "iteration_id" uuid references "better_supabase"."iterations" ("id") on delete set null,
  "priority" smallint not null default 0 check ("priority" between 0 and 4),
  "estimate" numeric(10, 2) check ("estimate" >= 0),
  "progress" smallint check ("progress" between 0 and 100),
  "start_at" timestamptz,
  "end_at" timestamptz,
  "due_at" timestamptz,
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  "state" text not null default 'backlog' check ("state" in ('triage', 'backlog', 'unstarted', 'started', 'completed', 'canceled')),
  "close_reason" text check ("close_reason" in ('completed', 'not_planned', 'duplicate')),
  "closed_at" timestamptz,
  "locked" boolean not null default false,
  "rank" text collate "C" not null default 'V',
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  check ("end_at" is null or "start_at" is null or "end_at" >= "start_at")
);
create index if not exists "tasks_board_idx" on "better_supabase"."tasks" ("pipeline_id", "stage_id", "rank");
create index if not exists "tasks_parent_idx" on "better_supabase"."tasks" ("parent_id");
create index if not exists "tasks_project_idx" on "better_supabase"."tasks" ("project_id");
create index if not exists "tasks_iteration_idx" on "better_supabase"."tasks" ("iteration_id");
create index if not exists "tasks_due_idx" on "better_supabase"."tasks" ("tenant_id", "due_at") where "closed_at" is null;
alter table "better_supabase"."tasks" enable row level security;
revoke all on "better_supabase"."tasks" from public, anon, authenticated;
grant select on "better_supabase"."tasks" to authenticated;
grant all on "better_supabase"."tasks" to service_role;
drop policy if exists tasks_read on "better_supabase"."tasks";
create policy tasks_read on "better_supabase"."tasks"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table if not exists "better_supabase"."task_assignees" (
  "tenant_id" uuid not null,
  "task_id" uuid not null references "better_supabase"."tasks" ("id") on delete cascade,
  "user_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("task_id", "user_id")
);
create index if not exists "task_assignees_user_idx" on "better_supabase"."task_assignees" ("user_id");
alter table "better_supabase"."task_assignees" enable row level security;
revoke all on "better_supabase"."task_assignees" from public, anon, authenticated;
grant select on "better_supabase"."task_assignees" to authenticated;
grant all on "better_supabase"."task_assignees" to service_role;
drop policy if exists task_assignees_read on "better_supabase"."task_assignees";
create policy task_assignees_read on "better_supabase"."task_assignees"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

alter table "better_supabase"."tasks" add column if not exists "recurs_from" uuid references "better_supabase"."tasks" ("id") on delete set null;
create unique index if not exists "tasks_recurs_from_idx" on "better_supabase"."tasks" ("recurs_from");

create table if not exists "better_supabase"."task_checklist_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "task_id" uuid not null references "better_supabase"."tasks" ("id") on delete cascade,
  "title" text not null check (length("title") between 1 and 500),
  "done" boolean not null default false,
  "done_at" timestamptz,
  "done_by" uuid,
  "rank" text collate "C" not null check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
create index if not exists "task_checklist_item_idx" on "better_supabase"."task_checklist_items" ("task_id", "rank");
alter table "better_supabase"."task_checklist_items" enable row level security;
revoke all on "better_supabase"."task_checklist_items" from public, anon, authenticated;
grant select on "better_supabase"."task_checklist_items" to authenticated;
grant all on "better_supabase"."task_checklist_items" to service_role;
drop policy if exists task_checklist_items_read on "better_supabase"."task_checklist_items";
create policy task_checklist_items_read on "better_supabase"."task_checklist_items"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create or replace function better_supabase.bsb_work_item_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."parent_id" is not null and (tg_op = 'INSERT' or new."parent_id" is distinct from old."parent_id") then
    if exists (
      with recursive up(id, depth) as (
        select new."parent_id", 1
        union all
        select x."parent_id", up.depth + 1 from "better_supabase"."tasks" x join up on x."id" = up.id
        where x."parent_id" is not null and up.depth < 100
      )
      select 1 from up where up.id = new."id"
    ) then
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'TASK_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "better_supabase"."tasks" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
      raise exception 'the parent is in another organization' using errcode = '22023', hint = 'TASK_PARENT_INVALID';
    end if;
  end if;
  if tg_op = 'UPDATE' and old."locked" and not (auth.role() = 'service_role') and (new."start_at" is distinct from old."start_at" or new."end_at" is distinct from old."end_at" or new."due_at" is distinct from old."due_at") then
    raise exception 'the item is locked; its dates can''t change' using errcode = '55000', hint = 'TASK_LOCKED';
  end if;
  if tg_op = 'INSERT' then
    if new."state" in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
    end if;
    return new;
  end if;
  if new."state" is distinct from old."state" then
    if new."state" in ('completed', 'canceled') and old."state" not in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
      if new."state" = 'completed' and new."progress" is not null then
        new."progress" := 100;
      end if;
      null;
    elsif not (new."state" in ('completed', 'canceled')) and old."state" in ('completed', 'canceled') then
      new."closed_at" := null;
      new."close_reason" := null;
      null;
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_work_item_guard() from public, anon, authenticated;
drop trigger if exists bsb_work_item_guard on "better_supabase"."tasks";
create trigger bsb_work_item_guard before insert or update on "better_supabase"."tasks"
for each row execute function better_supabase.bsb_work_item_guard();

-- Creates a work item. attrs: title (required), body, parentId, teamId,
-- projectId, iterationId, priority (0 none to 4 low, as Linear), estimate,
-- progress, startAt, endAt, dueAt, pipelineId, stageId, and fields (the
-- extra columns, by name). assignees: user ids.
create or replace function "better_supabase"."create_task"(tenant uuid, attrs jsonb, assignees uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seq bigint;
  v_identifier text;
  v_id uuid;
  v_row "better_supabase"."tasks";
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_task.tenant, 'tasks.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if nullif(trim(create_task.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'TASK_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_task_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_task.tenant, create_task.attrs;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'work_item' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'work_item' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_task.tenant::text || ':work_item', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."tasks" x where x."tenant_id" = create_task.tenant;
  v_identifier := 'TASK-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."tasks" ("tenant_id", "number", "identifier", "title", "body", "parent_id", "team_id", "project_id", "iteration_id",
      "priority", "estimate", "progress", "start_at", "end_at", "due_at", "pipeline_id", "stage_id", "created_by")
    values (create_task.tenant, v_seq, v_identifier, trim(create_task.attrs ->> 'title'), create_task.attrs ->> 'body',
      (create_task.attrs ->> 'parentId')::uuid, (create_task.attrs ->> 'teamId')::uuid, (create_task.attrs ->> 'projectId')::uuid,
      (create_task.attrs ->> 'iterationId')::uuid, coalesce((create_task.attrs ->> 'priority')::smallint, 0),
      (create_task.attrs ->> 'estimate')::numeric, (create_task.attrs ->> 'progress')::smallint,
      (create_task.attrs ->> 'startAt')::timestamptz, (create_task.attrs ->> 'endAt')::timestamptz, (create_task.attrs ->> 'dueAt')::timestamptz,
      (create_task.attrs ->> 'pipelineId')::uuid, (create_task.attrs ->> 'stageId')::uuid, auth.uid())
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  if cardinality(coalesce(create_task.assignees, '{}')) > 0 then
    perform "better_supabase"."set_task_assignees"(v_id, create_task.assignees);
  end if;
  select * into v_row from "better_supabase"."tasks" x where x."id" = v_id;
  if jsonb_array_length(coalesce((create_task.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      raise exception 'install the attachments block to attach files' using errcode = '0A000', hint = 'TASK_ATTACHMENTS_UNAVAILABLE';
    end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_task_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id")) from "better_supabase"."tasks" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_task"(uuid, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."create_task"(uuid, jsonb, uuid[]) to authenticated, service_role;

-- Applies a batch of { workItemId, field, value } changes, each on its
-- own. Returns { accepted: [{ workItemId, field }], rejected: [{ workItemId,
-- field, hint, reason }] }. With atomic, the first change that fails raises
-- its error and no change is kept. The window field ({ startAt, endAt })
-- writes both ends in one update, so the end-after-start check sees both.
drop function if exists "better_supabase"."update_tasks"(jsonb);
create or replace function "better_supabase"."update_tasks"(changes jsonb, atomic boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_item uuid;
  v_field text;
  v_row "better_supabase"."tasks";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_tasks.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { workItemId, field, value }' using errcode = '22023', hint = 'TASK_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_tasks.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'workItemId')::uuid;
      if not exists (select 1 from "better_supabase"."tasks" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_task_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_item, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'title' then
        update "better_supabase"."tasks" x set "title" = trim(v_change -> 'value' #>> '{}') where x."id" = v_item;
      when 'body' then
        update "better_supabase"."tasks" x set "body" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'parentId' then
        update "better_supabase"."tasks" x set "parent_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'teamId' then
        update "better_supabase"."tasks" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'projectId' then
        update "better_supabase"."tasks" x set "project_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'iterationId' then
        update "better_supabase"."tasks" x set "iteration_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'priority' then
        update "better_supabase"."tasks" x set "priority" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'estimate' then
        update "better_supabase"."tasks" x set "estimate" = (v_change -> 'value' #>> '{}')::numeric where x."id" = v_item;
      when 'progress' then
        update "better_supabase"."tasks" x set "progress" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'startAt' then
        update "better_supabase"."tasks" x set "start_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'endAt' then
        update "better_supabase"."tasks" x set "end_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'dueAt' then
        update "better_supabase"."tasks" x set "due_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'stageId' then
        update "better_supabase"."tasks" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'closeReason' then
        update "better_supabase"."tasks" x set "close_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'window' then
        if jsonb_typeof(v_change -> 'value') <> 'object' then
          raise exception 'window must be an object of startAt and endAt' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
        end if;
        update "better_supabase"."tasks" x set
          "start_at" = case when v_change -> 'value' ? 'startAt' then (v_change -> 'value' ->> 'startAt')::timestamptz else x."start_at" end,
          "end_at" = case when v_change -> 'value' ? 'endAt' then (v_change -> 'value' ->> 'endAt')::timestamptz else x."end_at" end
        where x."id" = v_item;
      when 'attachments' then
        select * into v_row from "better_supabase"."tasks" x where x."id" = v_item;
        if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      raise exception 'install the attachments block to attach files' using errcode = '0A000', hint = 'TASK_ATTACHMENTS_UNAVAILABLE';
    end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'TASK_FIELD_UNKNOWN';
      end case;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('workItemId', v_item, 'field', v_field));
      v_touched := array_append(v_touched, v_item);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_task_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_item, v_field;
    end if;
  end;
    exception when others then
      if update_tasks.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_change ->> 'workItemId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."tasks" x where x."id" = any (v_touched) loop
    null;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "better_supabase"."update_tasks"(jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."update_tasks"(jsonb, boolean) to authenticated, service_role;

-- Replaces an item's assignees. Each one watches the item, and those who
-- weren't assigned before are notified. task.assigned is recorded only
-- when the call adds someone, with addedIds.
create or replace function "better_supabase"."set_task_assignees"(work_item uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_task_assignees.users, '{}')) x where x is not null);
  v_added uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."tasks" x where x."id" = set_task_assignees.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_added := array(select x from unnest(v_users) x where not exists (
    select 1 from "better_supabase"."task_assignees" y where y."task_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."task_assignees" y where y."task_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."task_assignees" ("tenant_id", "task_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  if cardinality(v_added) > 0 then
    null;
  end if;
  return cardinality(v_users);
end;
$$;
revoke execute on function "better_supabase"."set_task_assignees"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."set_task_assignees"(uuid, uuid[]) to authenticated, service_role;

create or replace function "better_supabase"."archive_task"(work_item uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."tasks" x set "archived_at" = case when archive_task.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_task.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_task.archived then
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_task"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_task"(uuid, boolean) to authenticated, service_role;

-- Deletes an item and its children. Needs work_items.manage, or its author.
create or replace function "better_supabase"."delete_task"(work_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."tasks" x
  where x."id" = delete_task.work_item
    and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_task"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_task"(uuid) to authenticated, service_role;

-- An item and everything under it with its depth. An item without its own
-- progress takes the share of its open and completed children that are
-- completed, so a Gantt group shows a rollup.
create or replace function "better_supabase"."task_tree"(root uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with recursive tree as (
    select x.*, 0 as depth from "better_supabase"."tasks" x where x."id" = task_tree.root
    union all
    select y.*, tree.depth + 1 from "better_supabase"."tasks" y join tree on y."parent_id" = tree."id"
    where tree.depth < 100 and y."archived_at" is null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', tree."id", 'parentId', tree."parent_id", 'identifier', tree."identifier", 'title', tree."title",
    'state', tree."state", 'startAt', tree."start_at", 'endAt', tree."end_at", 'dueAt', tree."due_at",
    'locked', tree."locked", 'depth', tree.depth,
    'progress', coalesce(tree."progress", (
      select case when count(*) filter (where ch."state" <> 'canceled') = 0 then
          case tree."state" when 'completed' then 100 else 0 end
        else round(100.0 * count(*) filter (where ch."state" = 'completed') / count(*) filter (where ch."state" <> 'canceled'))::integer end
      from "better_supabase"."tasks" ch where ch."parent_id" = tree."id" and ch."archived_at" is null))
  ) order by tree.depth, tree."rank" collate "C", tree."id"), '[]'::jsonb)
  from tree
$$;
revoke execute on function "better_supabase"."task_tree"(uuid) from public, anon;
grant execute on function "better_supabase"."task_tree"(uuid) to authenticated, service_role;

-- A page of a tenant's active items, newest first. filter keys: teamId,
-- projectId, iterationId, parentId, assigneeId, states (a list), open
-- (only unclosed). search matches the title and identifier. after continues
-- after that item.
create or replace function "better_supabase"."list_tasks"(tenant uuid, filter jsonb, search text, after uuid, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.number desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id")) as value, x."number" as number
    from "better_supabase"."tasks" x
    where x."tenant_id" = list_tasks.tenant and x."archived_at" is null
      and (list_tasks.filter ->> 'teamId' is null or x."team_id" = (list_tasks.filter ->> 'teamId')::uuid)
      and (list_tasks.filter ->> 'projectId' is null or x."project_id" = (list_tasks.filter ->> 'projectId')::uuid)
      and (list_tasks.filter ->> 'iterationId' is null or x."iteration_id" = (list_tasks.filter ->> 'iterationId')::uuid)
      and (list_tasks.filter ->> 'parentId' is null or x."parent_id" = (list_tasks.filter ->> 'parentId')::uuid)
      and (list_tasks.filter ->> 'assigneeId' is null or exists (select 1 from "better_supabase"."task_assignees" y where y."task_id" = x."id" and y."user_id" = (list_tasks.filter ->> 'assigneeId')::uuid))
      and (list_tasks.filter -> 'states' is null or x."state" = any (array(select jsonb_array_elements_text(list_tasks.filter -> 'states'))))
      and (coalesce((list_tasks.filter ->> 'open')::boolean, false) = false or x."closed_at" is null)
      and (list_tasks.search is null or x."title" ilike '%' || list_tasks.search || '%' or x."identifier" ilike list_tasks.search || '%')
      and (list_tasks.after is null or x."number" < (select z."number" from "better_supabase"."tasks" z where z."id" = list_tasks.after))
    order by x."number" desc
    limit least(greatest(coalesce(list_tasks.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."list_tasks"(uuid, jsonb, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_tasks"(uuid, jsonb, text, uuid, integer) to authenticated, service_role;

-- Adds a checklist item (checklist_item null) or changes one: title, done,
-- rank. A new item without a rank goes last.
create or replace function "better_supabase"."save_task_checklist_item"(work_item uuid, checklist_item uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
  v_id uuid := save_task_checklist_item.checklist_item;
  v_last text;
  v_done boolean := (save_task_checklist_item.attrs ->> 'done')::boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."tasks" x where x."id" = save_task_checklist_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  begin
    if v_id is null then
      select max(y."rank") into v_last from "better_supabase"."task_checklist_items" y where y."task_id" = v_row."id";
      insert into "better_supabase"."task_checklist_items" ("tenant_id", "task_id", "title", "done", "done_at", "done_by", "rank", "created_by")
      values (v_row."tenant_id", v_row."id", trim(save_task_checklist_item.attrs ->> 'title'), coalesce(v_done, false),
        case when v_done then now() end, case when v_done then auth.uid() end,
        coalesce(save_task_checklist_item.attrs ->> 'rank', case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end), auth.uid())
      returning "id" into v_id;
    else
      update "better_supabase"."task_checklist_items" y set
        "title" = coalesce(trim(save_task_checklist_item.attrs ->> 'title'), y."title"),
        "rank" = coalesce(save_task_checklist_item.attrs ->> 'rank', y."rank"),
        "done" = coalesce(v_done, y."done"),
        "done_at" = case when v_done is null then y."done_at" when v_done then coalesce(y."done_at", now()) end,
        "done_by" = case when v_done is null then y."done_by" when v_done then coalesce(y."done_by", auth.uid()) end
      where y."id" = v_id and y."task_id" = v_row."id";
      if not found then
        raise exception 'no such checklist item on this work item' using errcode = 'P0002', hint = 'TASK_CHECKLIST_ITEM_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a checklist item needs a title of 1 to 500 characters and a valid rank' using errcode = '22023', hint = 'TASK_CHECKLIST_ITEM_INVALID';
  end;
  null;
  return (select jsonb_build_object('id', y."id", 'workItemId', y."task_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") from "better_supabase"."task_checklist_items" y where y."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_task_checklist_item"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_task_checklist_item"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_task_checklist_item"(checklist_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x.* into v_row from "better_supabase"."tasks" x join "better_supabase"."task_checklist_items" y on y."task_id" = x."id"
  where y."id" = delete_task_checklist_item.checklist_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    return false;
  end if;
  delete from "better_supabase"."task_checklist_items" y where y."id" = delete_task_checklist_item.checklist_item;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_task_checklist_item"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_task_checklist_item"(uuid) to authenticated, service_role;

-- An item's checklist, in rank order.
create or replace function "better_supabase"."list_task_checklist"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'workItemId', y."task_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") order by y."rank" collate "C", y."id"), '[]'::jsonb)
  from "better_supabase"."task_checklist_items" y where y."task_id" = list_task_checklist.work_item
$$;
revoke execute on function "better_supabase"."list_task_checklist"(uuid) from public, anon;
grant execute on function "better_supabase"."list_task_checklist"(uuid) to authenticated, service_role;

-- One item the caller can read, or null.
create or replace function "better_supabase"."get_task"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id")) from "better_supabase"."tasks" x where x."id" = get_task.work_item
$$;
revoke execute on function "better_supabase"."get_task"(uuid) from public, anon;
grant execute on function "better_supabase"."get_task"(uuid) to authenticated, service_role;

-- Creates a project (project null) or changes the keys attrs names: key,
-- name, ownerId, status, startOn, targetOn, archived, and the budget:
-- budgetAmount (minor units as text) with budgetCurrency, and budgetHours.
-- With accounting, the project is a value of the project dimension.
create or replace function "better_supabase"."save_project"(tenant uuid, project uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_project.project;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_project.tenant, 'tasks.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."projects" ("tenant_id", "key", "name", "owner_user_id", "status", "start_on", "target_on", "budget_amount", "budget_currency", "budget_hours")
      values (save_project.tenant, upper(save_project.attrs ->> 'key'), save_project.attrs ->> 'name', (save_project.attrs ->> 'ownerId')::uuid,
        coalesce(save_project.attrs ->> 'status', 'planned'), (save_project.attrs ->> 'startOn')::date, (save_project.attrs ->> 'targetOn')::date,
        (save_project.attrs ->> 'budgetAmount')::bigint, upper(save_project.attrs ->> 'budgetCurrency'), (save_project.attrs ->> 'budgetHours')::numeric)
      returning "id" into v_id;
    else
      update "better_supabase"."projects" x set
        "key" = coalesce(upper(save_project.attrs ->> 'key'), x."key"),
        "name" = coalesce(save_project.attrs ->> 'name', x."name"),
        "owner_user_id" = case when save_project.attrs ? 'ownerId' then (save_project.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
        "status" = coalesce(save_project.attrs ->> 'status', x."status"),
        "start_on" = case when save_project.attrs ? 'startOn' then (save_project.attrs ->> 'startOn')::date else x."start_on" end,
        "target_on" = case when save_project.attrs ? 'targetOn' then (save_project.attrs ->> 'targetOn')::date else x."target_on" end,
        "budget_amount" = case when save_project.attrs ? 'budgetAmount' then (save_project.attrs ->> 'budgetAmount')::bigint else x."budget_amount" end,
        "budget_currency" = case when save_project.attrs ? 'budgetCurrency' then upper(save_project.attrs ->> 'budgetCurrency') else x."budget_currency" end,
        "budget_hours" = case when save_project.attrs ? 'budgetHours' then (save_project.attrs ->> 'budgetHours')::numeric else x."budget_hours" end,
        "archived_at" = case when save_project.attrs ? 'archived' then (case when (save_project.attrs ->> 'archived')::boolean then coalesce(x."archived_at", now()) end) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_project.tenant;
      if not found then
        raise exception 'project not found' using errcode = 'P0002', hint = 'TASK_PROJECT_NOT_FOUND';
      end if;
    end if;
    if exists (
      select 1 from "better_supabase"."projects" x
      where x."id" = v_id and x."budget_amount" is not null and x."budget_currency" is null
    ) then
      raise exception 'a budget amount needs a currency' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
    end if;
  exception when unique_violation then
    raise exception 'another project has this key' using errcode = '23505', hint = 'TASK_PROJECT_KEY_TAKEN';
  when check_violation or not_null_violation then
    raise exception 'a project needs a key of capitals and a name, and ends after it starts' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end;

  return (select to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."tasks" y where y."project_id" = x."id" and y."archived_at" is null
    )) from "better_supabase"."projects" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_project"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_project"(uuid, uuid, jsonb) to authenticated, service_role;

-- Creates an iteration (a cycle or a sprint) or changes it: name, teamId,
-- startsOn, endsOn.
create or replace function "better_supabase"."save_iteration"(tenant uuid, iteration uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_iteration.iteration;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_iteration.tenant, 'tasks.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."iterations" ("tenant_id", "team_id", "name", "starts_on", "ends_on")
      values (save_iteration.tenant, (save_iteration.attrs ->> 'teamId')::uuid, save_iteration.attrs ->> 'name',
        (save_iteration.attrs ->> 'startsOn')::date, (save_iteration.attrs ->> 'endsOn')::date)
      returning "id" into v_id;
    else
      update "better_supabase"."iterations" x set
        "name" = coalesce(save_iteration.attrs ->> 'name', x."name"),
        "starts_on" = coalesce((save_iteration.attrs ->> 'startsOn')::date, x."starts_on"),
        "ends_on" = coalesce((save_iteration.attrs ->> 'endsOn')::date, x."ends_on")
      where x."id" = v_id and x."tenant_id" = save_iteration.tenant;
      if not found then
        raise exception 'iteration not found' using errcode = 'P0002', hint = 'TASK_ITERATION_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation then
    raise exception 'an iteration needs a name and ends on or after it starts' using errcode = '22023', hint = 'TASK_ITERATION_INVALID';
  end;
  return (select to_jsonb(x) from "better_supabase"."iterations" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_iteration"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_iteration"(uuid, uuid, jsonb) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."tasks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tasks";
create policy bsb_tenant_scope_select on "better_supabase"."tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tasks";
create policy bsb_tenant_scope_insert on "better_supabase"."tasks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tasks";
create policy bsb_tenant_scope_update on "better_supabase"."tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tasks";
create policy bsb_tenant_scope_delete on "better_supabase"."tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."task_checklist_items";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_select on "better_supabase"."task_checklist_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_insert on "better_supabase"."task_checklist_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_update on "better_supabase"."task_checklist_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_delete on "better_supabase"."task_checklist_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."task_assignees";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_select on "better_supabase"."task_assignees" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_insert on "better_supabase"."task_assignees" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_update on "better_supabase"."task_assignees" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_delete on "better_supabase"."task_assignees" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."projects";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."projects";
create policy bsb_tenant_scope_select on "better_supabase"."projects" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."projects";
create policy bsb_tenant_scope_insert on "better_supabase"."projects" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."projects";
create policy bsb_tenant_scope_update on "better_supabase"."projects" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."projects";
create policy bsb_tenant_scope_delete on "better_supabase"."projects" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."iterations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."iterations";
create policy bsb_tenant_scope_select on "better_supabase"."iterations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."iterations";
create policy bsb_tenant_scope_insert on "better_supabase"."iterations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."iterations";
create policy bsb_tenant_scope_update on "better_supabase"."iterations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."iterations";
create policy bsb_tenant_scope_delete on "better_supabase"."iterations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.tasks.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."update_tasks"(jsonb);

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

create or replace function "api"."create_task"(tenant uuid, attrs jsonb, assignees uuid[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_task"($1, $2, $3) $$;
revoke execute on function "api"."create_task"(uuid, jsonb, uuid[]) from public, anon;
grant execute on function "api"."create_task"(uuid, jsonb, uuid[]) to authenticated, service_role;

create or replace function "api"."update_tasks"(changes jsonb, atomic boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_tasks"($1, $2) $$;
revoke execute on function "api"."update_tasks"(jsonb, boolean) from public, anon;
grant execute on function "api"."update_tasks"(jsonb, boolean) to authenticated, service_role;

create or replace function "api"."set_task_assignees"(work_item uuid, users uuid[])
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_task_assignees"($1, $2) $$;
revoke execute on function "api"."set_task_assignees"(uuid, uuid[]) from public, anon;
grant execute on function "api"."set_task_assignees"(uuid, uuid[]) to authenticated, service_role;

create or replace function "api"."archive_task"(work_item uuid, archived boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_task"($1, $2) $$;
revoke execute on function "api"."archive_task"(uuid, boolean) from public, anon;
grant execute on function "api"."archive_task"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."delete_task"(work_item uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_task"($1) $$;
revoke execute on function "api"."delete_task"(uuid) from public, anon;
grant execute on function "api"."delete_task"(uuid) to authenticated, service_role;

create or replace function "api"."task_tree"(root uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."task_tree"($1) $$;
revoke execute on function "api"."task_tree"(uuid) from public, anon;
grant execute on function "api"."task_tree"(uuid) to authenticated, service_role;

create or replace function "api"."list_tasks"(tenant uuid, filter jsonb, search text, after uuid, page_size integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_tasks"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_tasks"(uuid, jsonb, text, uuid, integer) from public, anon;
grant execute on function "api"."list_tasks"(uuid, jsonb, text, uuid, integer) to authenticated, service_role;

create or replace function "api"."save_task_checklist_item"(work_item uuid, checklist_item uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_task_checklist_item"($1, $2, $3) $$;
revoke execute on function "api"."save_task_checklist_item"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_task_checklist_item"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_task_checklist_item"(checklist_item uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_task_checklist_item"($1) $$;
revoke execute on function "api"."delete_task_checklist_item"(uuid) from public, anon;
grant execute on function "api"."delete_task_checklist_item"(uuid) to authenticated, service_role;

create or replace function "api"."list_task_checklist"(work_item uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_task_checklist"($1) $$;
revoke execute on function "api"."list_task_checklist"(uuid) from public, anon;
grant execute on function "api"."list_task_checklist"(uuid) to authenticated, service_role;

create or replace function "api"."get_task"(work_item uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_task"($1) $$;
revoke execute on function "api"."get_task"(uuid) from public, anon;
grant execute on function "api"."get_task"(uuid) to authenticated, service_role;

create or replace function "api"."save_project"(tenant uuid, project uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_project"($1, $2, $3) $$;
revoke execute on function "api"."save_project"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_project"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."save_iteration"(tenant uuid, iteration uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_iteration"($1, $2, $3) $$;
revoke execute on function "api"."save_iteration"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_iteration"(uuid, uuid, jsonb) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_091_tasks.sql
-- better-supabase module: tasks
-- @bsb-block-data tasks
-- @bsb-hash sha256:ea8a7f6275992a7e6c1d4e1fb480479290ca96436b7d2cd1815c10fb28bbf310
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_members"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_members" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipelines"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipelines" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipeline_stage_history"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipeline_stage_history" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_091_tasks.sql
-- better-supabase module: tasks
-- @bsb-block tasks@4 managed
-- @bsb-hash sha256:6f553874fd35aed7461546829c36538b34c24d57ac5b8b614e313dbe3b179d1b
-- Issues and tasks on pipelines: identifiers, parents without cycles, several assignees, priority 0 to 4, estimates, start, end and due dates, locking, projects, iterations, batched edits and a progress tree.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tasks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_checklist_items";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_assignees";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."projects";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."iterations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Work items on pipelines: issues and tasks with an identifier, a parent,
-- assignees, a priority, dates, projects and iterations.

-- better_supabase.projects is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."projects" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."projects" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."projects" add column if not exists "key" text check ("key" ~ '^[A-Z][A-Z0-9]{0,9}$');
alter table "better_supabase"."projects" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."projects" add column if not exists "owner_user_id" uuid;
alter table "better_supabase"."projects" add column if not exists "status" text not null default 'planned' check ("status" in ('planned', 'active', 'paused', 'completed', 'canceled'));
alter table "better_supabase"."projects" add column if not exists "start_on" date;
alter table "better_supabase"."projects" add column if not exists "target_on" date;
alter table "better_supabase"."projects" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."projects" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."projects" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "projects_tenant_id_key_key" on "better_supabase"."projects" ("tenant_id", "key");
alter table "better_supabase"."projects" add column if not exists "budget_amount" bigint check ("budget_amount" >= 0);
alter table "better_supabase"."projects" add column if not exists "budget_currency" text check ("budget_currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."projects" add column if not exists "budget_hours" numeric(12, 2) check ("budget_hours" >= 0);
alter table "better_supabase"."projects" enable row level security;
grant select on "better_supabase"."projects" to authenticated;
grant all on "better_supabase"."projects" to service_role;
drop policy if exists bsb_projects_select on "better_supabase"."projects";
create policy bsb_projects_select on "better_supabase"."projects"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

-- better_supabase.iterations is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."iterations" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."iterations" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."iterations" add column if not exists "team_id" uuid;
alter table "better_supabase"."iterations" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."iterations" add column if not exists "starts_on" date;
alter table "better_supabase"."iterations" add column if not exists "ends_on" date;
alter table "better_supabase"."iterations" add column if not exists "created_at" timestamptz not null default now();
create index if not exists iterations_tenant_idx on "better_supabase"."iterations" ("tenant_id", "team_id", "starts_on");
alter table "better_supabase"."iterations" enable row level security;
grant select on "better_supabase"."iterations" to authenticated;
grant all on "better_supabase"."iterations" to service_role;
drop policy if exists bsb_iterations_select on "better_supabase"."iterations";
create policy bsb_iterations_select on "better_supabase"."iterations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

-- better_supabase.tasks is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."tasks" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."tasks" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."tasks" add column if not exists "number" bigint;
alter table "better_supabase"."tasks" add column if not exists "identifier" text;
alter table "better_supabase"."tasks" add column if not exists "title" text check (length("title") between 1 and 500);
alter table "better_supabase"."tasks" add column if not exists "body" text;
alter table "better_supabase"."tasks" add column if not exists "parent_id" uuid references "better_supabase"."tasks" ("id") on delete cascade;
alter table "better_supabase"."tasks" add column if not exists "team_id" uuid;
alter table "better_supabase"."tasks" add column if not exists "project_id" uuid references "better_supabase"."projects" ("id") on delete set null;
alter table "better_supabase"."tasks" add column if not exists "iteration_id" uuid references "better_supabase"."iterations" ("id") on delete set null;
alter table "better_supabase"."tasks" add column if not exists "priority" smallint not null default 0 check ("priority" between 0 and 4);
alter table "better_supabase"."tasks" add column if not exists "estimate" numeric(10, 2) check ("estimate" >= 0);
alter table "better_supabase"."tasks" add column if not exists "progress" smallint check ("progress" between 0 and 100);
alter table "better_supabase"."tasks" add column if not exists "start_at" timestamptz;
alter table "better_supabase"."tasks" add column if not exists "end_at" timestamptz;
alter table "better_supabase"."tasks" add column if not exists "due_at" timestamptz;
alter table "better_supabase"."tasks" add column if not exists "pipeline_id" uuid;
alter table "better_supabase"."tasks" add column if not exists "stage_id" uuid;
alter table "better_supabase"."tasks" add column if not exists "stage_entered_at" timestamptz;
alter table "better_supabase"."tasks" add column if not exists "state" text not null default 'backlog' check ("state" in ('triage', 'backlog', 'unstarted', 'started', 'completed', 'canceled'));
alter table "better_supabase"."tasks" add column if not exists "close_reason" text check ("close_reason" in ('completed', 'not_planned', 'duplicate'));
alter table "better_supabase"."tasks" add column if not exists "closed_at" timestamptz;
alter table "better_supabase"."tasks" add column if not exists "locked" boolean not null default false;
alter table "better_supabase"."tasks" add column if not exists "rank" text collate "C" not null default 'V';
alter table "better_supabase"."tasks" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."tasks" add column if not exists "created_by" uuid;
alter table "better_supabase"."tasks" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."tasks" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "tasks_tenant_id_number_key" on "better_supabase"."tasks" ("tenant_id", "number");
create index if not exists "tasks_board_idx" on "better_supabase"."tasks" ("pipeline_id", "stage_id", "rank");
create index if not exists "tasks_parent_idx" on "better_supabase"."tasks" ("parent_id");
create index if not exists "tasks_project_idx" on "better_supabase"."tasks" ("project_id");
create index if not exists "tasks_iteration_idx" on "better_supabase"."tasks" ("iteration_id");
create index if not exists "tasks_due_idx" on "better_supabase"."tasks" ("tenant_id", "due_at") where "closed_at" is null;
alter table "better_supabase"."tasks" enable row level security;
grant select on "better_supabase"."tasks" to authenticated;
grant all on "better_supabase"."tasks" to service_role;
drop policy if exists bsb_tasks_select on "better_supabase"."tasks";
create policy bsb_tasks_select on "better_supabase"."tasks"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

-- better_supabase.task_assignees is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."task_assignees" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."task_assignees" add column if not exists "task_id" uuid references "better_supabase"."tasks" ("id") on delete cascade;
alter table "better_supabase"."task_assignees" add column if not exists "user_id" uuid;
alter table "better_supabase"."task_assignees" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists "task_assignees_task_id_user_id_key" on "better_supabase"."task_assignees" ("task_id", "user_id");
create index if not exists "task_assignees_user_idx" on "better_supabase"."task_assignees" ("user_id");
alter table "better_supabase"."task_assignees" enable row level security;
grant select on "better_supabase"."task_assignees" to authenticated;
grant all on "better_supabase"."task_assignees" to service_role;
drop policy if exists bsb_task_assignees_select on "better_supabase"."task_assignees";
create policy bsb_task_assignees_select on "better_supabase"."task_assignees"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

alter table "better_supabase"."tasks" add column if not exists "recurs_from" uuid references "better_supabase"."tasks" ("id") on delete set null;
create unique index if not exists "tasks_recurs_from_idx" on "better_supabase"."tasks" ("recurs_from");

-- better_supabase.task_checklist_items is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."task_checklist_items" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."task_checklist_items" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."task_checklist_items" add column if not exists "task_id" uuid references "better_supabase"."tasks" ("id") on delete cascade;
alter table "better_supabase"."task_checklist_items" add column if not exists "title" text check (length("title") between 1 and 500);
alter table "better_supabase"."task_checklist_items" add column if not exists "done" boolean not null default false;
alter table "better_supabase"."task_checklist_items" add column if not exists "done_at" timestamptz;
alter table "better_supabase"."task_checklist_items" add column if not exists "done_by" uuid;
alter table "better_supabase"."task_checklist_items" add column if not exists "rank" text collate "C" check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$');
alter table "better_supabase"."task_checklist_items" add column if not exists "created_by" uuid;
alter table "better_supabase"."task_checklist_items" add column if not exists "created_at" timestamptz not null default now();
create index if not exists "task_checklist_item_idx" on "better_supabase"."task_checklist_items" ("task_id", "rank");
alter table "better_supabase"."task_checklist_items" enable row level security;
grant select on "better_supabase"."task_checklist_items" to authenticated;
grant all on "better_supabase"."task_checklist_items" to service_role;
drop policy if exists bsb_task_checklist_items_select on "better_supabase"."task_checklist_items";
create policy bsb_task_checklist_items_select on "better_supabase"."task_checklist_items"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create or replace function better_supabase.bsb_work_item_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."parent_id" is not null and (tg_op = 'INSERT' or new."parent_id" is distinct from old."parent_id") then
    if exists (
      with recursive up(id, depth) as (
        select new."parent_id", 1
        union all
        select x."parent_id", up.depth + 1 from "better_supabase"."tasks" x join up on x."id" = up.id
        where x."parent_id" is not null and up.depth < 100
      )
      select 1 from up where up.id = new."id"
    ) then
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'TASK_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "better_supabase"."tasks" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
      raise exception 'the parent is in another organization' using errcode = '22023', hint = 'TASK_PARENT_INVALID';
    end if;
  end if;
  if tg_op = 'UPDATE' and old."locked" and not (auth.role() = 'service_role') and (new."start_at" is distinct from old."start_at" or new."end_at" is distinct from old."end_at" or new."due_at" is distinct from old."due_at") then
    raise exception 'the item is locked; its dates can''t change' using errcode = '55000', hint = 'TASK_LOCKED';
  end if;
  if tg_op = 'INSERT' then
    if new."state" in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", better_supabase.as_column_type(case new."state" when 'completed' then 'completed' else 'not_planned' end, (null::"better_supabase"."tasks")."close_reason"));
    end if;
    return new;
  end if;
  if new."state" is distinct from old."state" then
    if new."state" in ('completed', 'canceled') and old."state" not in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", better_supabase.as_column_type(case new."state" when 'completed' then 'completed' else 'not_planned' end, (null::"better_supabase"."tasks")."close_reason"));
      if new."state" = 'completed' and new."progress" is not null then
        new."progress" := 100;
      end if;
      null;
    elsif not (new."state" in ('completed', 'canceled')) and old."state" in ('completed', 'canceled') then
      new."closed_at" := null;
      new."close_reason" := null;
      null;
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_work_item_guard() from public, anon, authenticated;
drop trigger if exists bsb_work_item_guard on "better_supabase"."tasks";
create trigger bsb_work_item_guard before insert or update on "better_supabase"."tasks"
for each row execute function better_supabase.bsb_work_item_guard();

-- Creates a work item. attrs: title (required), body, parentId, teamId,
-- projectId, iterationId, priority (0 none to 4 low, as Linear), estimate,
-- progress, startAt, endAt, dueAt, pipelineId, stageId, and fields (the
-- extra columns, by name). assignees: user ids.
create or replace function "better_supabase"."create_task"(tenant uuid, attrs jsonb, assignees uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seq bigint;
  v_identifier text;
  v_id uuid;
  v_row "better_supabase"."tasks";
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_task.tenant, 'tasks.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if nullif(trim(create_task.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'TASK_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_task_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_task.tenant, create_task.attrs;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'work_item' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'work_item' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_task.tenant::text || ':work_item', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."tasks" x where x."tenant_id" = create_task.tenant;
  v_identifier := 'TASK-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."tasks" ("tenant_id", "number", "identifier", "title", "body", "parent_id", "team_id", "project_id", "iteration_id",
      "priority", "estimate", "progress", "start_at", "end_at", "due_at", "pipeline_id", "stage_id", "created_by")
    values (create_task.tenant, v_seq, v_identifier, trim(create_task.attrs ->> 'title'), create_task.attrs ->> 'body',
      (create_task.attrs ->> 'parentId')::uuid, (create_task.attrs ->> 'teamId')::uuid, (create_task.attrs ->> 'projectId')::uuid,
      (create_task.attrs ->> 'iterationId')::uuid, coalesce((create_task.attrs ->> 'priority')::smallint, 0),
      (create_task.attrs ->> 'estimate')::numeric, (create_task.attrs ->> 'progress')::smallint,
      (create_task.attrs ->> 'startAt')::timestamptz, (create_task.attrs ->> 'endAt')::timestamptz, (create_task.attrs ->> 'dueAt')::timestamptz,
      (create_task.attrs ->> 'pipelineId')::uuid, (create_task.attrs ->> 'stageId')::uuid, auth.uid())
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  if cardinality(coalesce(create_task.assignees, '{}')) > 0 then
    perform "better_supabase"."set_task_assignees"(v_id, create_task.assignees);
  end if;
  select * into v_row from "better_supabase"."tasks" x where x."id" = v_id;
  if jsonb_array_length(coalesce((create_task.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      raise exception 'install the attachments block to attach files' using errcode = '0A000', hint = 'TASK_ATTACHMENTS_UNAVAILABLE';
    end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_task_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id")) from "better_supabase"."tasks" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_task"(uuid, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."create_task"(uuid, jsonb, uuid[]) to authenticated, service_role;

-- Applies a batch of { workItemId, field, value } changes, each on its
-- own. Returns { accepted: [{ workItemId, field }], rejected: [{ workItemId,
-- field, hint, reason }] }. With atomic, the first change that fails raises
-- its error and no change is kept. The window field ({ startAt, endAt })
-- writes both ends in one update, so the end-after-start check sees both.
drop function if exists "better_supabase"."update_tasks"(jsonb);
create or replace function "better_supabase"."update_tasks"(changes jsonb, atomic boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_item uuid;
  v_field text;
  v_row "better_supabase"."tasks";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_tasks.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { workItemId, field, value }' using errcode = '22023', hint = 'TASK_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_tasks.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'workItemId')::uuid;
      if not exists (select 1 from "better_supabase"."tasks" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_task_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_item, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'title' then
        update "better_supabase"."tasks" x set "title" = trim(v_change -> 'value' #>> '{}') where x."id" = v_item;
      when 'body' then
        update "better_supabase"."tasks" x set "body" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'parentId' then
        update "better_supabase"."tasks" x set "parent_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'teamId' then
        update "better_supabase"."tasks" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'projectId' then
        update "better_supabase"."tasks" x set "project_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'iterationId' then
        update "better_supabase"."tasks" x set "iteration_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'priority' then
        update "better_supabase"."tasks" x set "priority" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'estimate' then
        update "better_supabase"."tasks" x set "estimate" = (v_change -> 'value' #>> '{}')::numeric where x."id" = v_item;
      when 'progress' then
        update "better_supabase"."tasks" x set "progress" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'startAt' then
        update "better_supabase"."tasks" x set "start_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'endAt' then
        update "better_supabase"."tasks" x set "end_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'dueAt' then
        update "better_supabase"."tasks" x set "due_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'stageId' then
        update "better_supabase"."tasks" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'closeReason' then
        update "better_supabase"."tasks" x set "close_reason" = better_supabase.as_column_type(nullif(trim(v_change -> 'value' #>> '{}'), ''), (null::"better_supabase"."tasks")."close_reason") where x."id" = v_item;
      when 'window' then
        if jsonb_typeof(v_change -> 'value') <> 'object' then
          raise exception 'window must be an object of startAt and endAt' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
        end if;
        update "better_supabase"."tasks" x set
          "start_at" = case when v_change -> 'value' ? 'startAt' then (v_change -> 'value' ->> 'startAt')::timestamptz else x."start_at" end,
          "end_at" = case when v_change -> 'value' ? 'endAt' then (v_change -> 'value' ->> 'endAt')::timestamptz else x."end_at" end
        where x."id" = v_item;
      when 'attachments' then
        select * into v_row from "better_supabase"."tasks" x where x."id" = v_item;
        if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      raise exception 'install the attachments block to attach files' using errcode = '0A000', hint = 'TASK_ATTACHMENTS_UNAVAILABLE';
    end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'TASK_FIELD_UNKNOWN';
      end case;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('workItemId', v_item, 'field', v_field));
      v_touched := array_append(v_touched, v_item);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_task_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_item, v_field;
    end if;
  end;
    exception when others then
      if update_tasks.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_change ->> 'workItemId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."tasks" x where x."id" = any (v_touched) loop
    null;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "better_supabase"."update_tasks"(jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."update_tasks"(jsonb, boolean) to authenticated, service_role;

-- Replaces an item's assignees. Each one watches the item, and those who
-- weren't assigned before are notified. task.assigned is recorded only
-- when the call adds someone, with addedIds.
create or replace function "better_supabase"."set_task_assignees"(work_item uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_task_assignees.users, '{}')) x where x is not null);
  v_added uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."tasks" x where x."id" = set_task_assignees.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_added := array(select x from unnest(v_users) x where not exists (
    select 1 from "better_supabase"."task_assignees" y where y."task_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."task_assignees" y where y."task_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."task_assignees" ("tenant_id", "task_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  if cardinality(v_added) > 0 then
    null;
  end if;
  return cardinality(v_users);
end;
$$;
revoke execute on function "better_supabase"."set_task_assignees"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."set_task_assignees"(uuid, uuid[]) to authenticated, service_role;

create or replace function "better_supabase"."archive_task"(work_item uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."tasks" x set "archived_at" = case when archive_task.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_task.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_task.archived then
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_task"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_task"(uuid, boolean) to authenticated, service_role;

-- Deletes an item and its children. Needs work_items.manage, or its author.
create or replace function "better_supabase"."delete_task"(work_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."tasks" x
  where x."id" = delete_task.work_item
    and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_task"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_task"(uuid) to authenticated, service_role;

-- An item and everything under it with its depth. An item without its own
-- progress takes the share of its open and completed children that are
-- completed, so a Gantt group shows a rollup.
create or replace function "better_supabase"."task_tree"(root uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with recursive tree as (
    select x.*, 0 as depth from "better_supabase"."tasks" x where x."id" = task_tree.root
    union all
    select y.*, tree.depth + 1 from "better_supabase"."tasks" y join tree on y."parent_id" = tree."id"
    where tree.depth < 100 and y."archived_at" is null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', tree."id", 'parentId', tree."parent_id", 'identifier', tree."identifier", 'title', tree."title",
    'state', tree."state", 'startAt', tree."start_at", 'endAt', tree."end_at", 'dueAt', tree."due_at",
    'locked', tree."locked", 'depth', tree.depth,
    'progress', coalesce(tree."progress", (
      select case when count(*) filter (where ch."state" <> 'canceled') = 0 then
          case tree."state" when 'completed' then 100 else 0 end
        else round(100.0 * count(*) filter (where ch."state" = 'completed') / count(*) filter (where ch."state" <> 'canceled'))::integer end
      from "better_supabase"."tasks" ch where ch."parent_id" = tree."id" and ch."archived_at" is null))
  ) order by tree.depth, tree."rank" collate "C", tree."id"), '[]'::jsonb)
  from tree
$$;
revoke execute on function "better_supabase"."task_tree"(uuid) from public, anon;
grant execute on function "better_supabase"."task_tree"(uuid) to authenticated, service_role;

-- A page of a tenant's active items, newest first. filter keys: teamId,
-- projectId, iterationId, parentId, assigneeId, states (a list), open
-- (only unclosed). search matches the title and identifier. after continues
-- after that item.
create or replace function "better_supabase"."list_tasks"(tenant uuid, filter jsonb, search text, after uuid, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.number desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id")) as value, x."number" as number
    from "better_supabase"."tasks" x
    where x."tenant_id" = list_tasks.tenant and x."archived_at" is null
      and (list_tasks.filter ->> 'teamId' is null or x."team_id" = (list_tasks.filter ->> 'teamId')::uuid)
      and (list_tasks.filter ->> 'projectId' is null or x."project_id" = (list_tasks.filter ->> 'projectId')::uuid)
      and (list_tasks.filter ->> 'iterationId' is null or x."iteration_id" = (list_tasks.filter ->> 'iterationId')::uuid)
      and (list_tasks.filter ->> 'parentId' is null or x."parent_id" = (list_tasks.filter ->> 'parentId')::uuid)
      and (list_tasks.filter ->> 'assigneeId' is null or exists (select 1 from "better_supabase"."task_assignees" y where y."task_id" = x."id" and y."user_id" = (list_tasks.filter ->> 'assigneeId')::uuid))
      and (list_tasks.filter -> 'states' is null or x."state"::text = any (array(select jsonb_array_elements_text(list_tasks.filter -> 'states'))))
      and (coalesce((list_tasks.filter ->> 'open')::boolean, false) = false or x."closed_at" is null)
      and (list_tasks.search is null or x."title" ilike '%' || list_tasks.search || '%' or x."identifier" ilike list_tasks.search || '%')
      and (list_tasks.after is null or x."number" < (select z."number" from "better_supabase"."tasks" z where z."id" = list_tasks.after))
    order by x."number" desc
    limit least(greatest(coalesce(list_tasks.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."list_tasks"(uuid, jsonb, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_tasks"(uuid, jsonb, text, uuid, integer) to authenticated, service_role;

-- Adds a checklist item (checklist_item null) or changes one: title, done,
-- rank. A new item without a rank goes last.
create or replace function "better_supabase"."save_task_checklist_item"(work_item uuid, checklist_item uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
  v_id uuid := save_task_checklist_item.checklist_item;
  v_last text;
  v_done boolean := (save_task_checklist_item.attrs ->> 'done')::boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."tasks" x where x."id" = save_task_checklist_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  begin
    if v_id is null then
      select max(y."rank") into v_last from "better_supabase"."task_checklist_items" y where y."task_id" = v_row."id";
      insert into "better_supabase"."task_checklist_items" ("tenant_id", "task_id", "title", "done", "done_at", "done_by", "rank", "created_by")
      values (v_row."tenant_id", v_row."id", trim(save_task_checklist_item.attrs ->> 'title'), coalesce(v_done, false),
        case when v_done then now() end, case when v_done then auth.uid() end,
        coalesce(save_task_checklist_item.attrs ->> 'rank', case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end), auth.uid())
      returning "id" into v_id;
    else
      update "better_supabase"."task_checklist_items" y set
        "title" = coalesce(trim(save_task_checklist_item.attrs ->> 'title'), y."title"),
        "rank" = coalesce(save_task_checklist_item.attrs ->> 'rank', y."rank"),
        "done" = coalesce(v_done, y."done"),
        "done_at" = case when v_done is null then y."done_at" when v_done then coalesce(y."done_at", now()) end,
        "done_by" = case when v_done is null then y."done_by" when v_done then coalesce(y."done_by", auth.uid()) end
      where y."id" = v_id and y."task_id" = v_row."id";
      if not found then
        raise exception 'no such checklist item on this work item' using errcode = 'P0002', hint = 'TASK_CHECKLIST_ITEM_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a checklist item needs a title of 1 to 500 characters and a valid rank' using errcode = '22023', hint = 'TASK_CHECKLIST_ITEM_INVALID';
  end;
  null;
  return (select jsonb_build_object('id', y."id", 'workItemId', y."task_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") from "better_supabase"."task_checklist_items" y where y."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_task_checklist_item"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_task_checklist_item"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_task_checklist_item"(checklist_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x.* into v_row from "better_supabase"."tasks" x join "better_supabase"."task_checklist_items" y on y."task_id" = x."id"
  where y."id" = delete_task_checklist_item.checklist_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    return false;
  end if;
  delete from "better_supabase"."task_checklist_items" y where y."id" = delete_task_checklist_item.checklist_item;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_task_checklist_item"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_task_checklist_item"(uuid) to authenticated, service_role;

-- An item's checklist, in rank order.
create or replace function "better_supabase"."list_task_checklist"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'workItemId', y."task_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") order by y."rank" collate "C", y."id"), '[]'::jsonb)
  from "better_supabase"."task_checklist_items" y where y."task_id" = list_task_checklist.work_item
$$;
revoke execute on function "better_supabase"."list_task_checklist"(uuid) from public, anon;
grant execute on function "better_supabase"."list_task_checklist"(uuid) to authenticated, service_role;

-- One item the caller can read, or null.
create or replace function "better_supabase"."get_task"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id")) from "better_supabase"."tasks" x where x."id" = get_task.work_item
$$;
revoke execute on function "better_supabase"."get_task"(uuid) from public, anon;
grant execute on function "better_supabase"."get_task"(uuid) to authenticated, service_role;

-- Creates a project (project null) or changes the keys attrs names: key,
-- name, ownerId, status, startOn, targetOn, archived, and the budget:
-- budgetAmount (minor units as text) with budgetCurrency, and budgetHours.
-- With accounting, the project is a value of the project dimension.
create or replace function "better_supabase"."save_project"(tenant uuid, project uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_project.project;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_project.tenant, 'tasks.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."projects" ("tenant_id", "key", "name", "owner_user_id", "status", "start_on", "target_on", "budget_amount", "budget_currency", "budget_hours")
      values (save_project.tenant, upper(save_project.attrs ->> 'key'), save_project.attrs ->> 'name', (save_project.attrs ->> 'ownerId')::uuid,
        better_supabase.as_column_type(coalesce(save_project.attrs ->> 'status', 'planned'), (null::"better_supabase"."projects")."status"), (save_project.attrs ->> 'startOn')::date, (save_project.attrs ->> 'targetOn')::date,
        (save_project.attrs ->> 'budgetAmount')::bigint, upper(save_project.attrs ->> 'budgetCurrency'), (save_project.attrs ->> 'budgetHours')::numeric)
      returning "id" into v_id;
    else
      update "better_supabase"."projects" x set
        "key" = coalesce(upper(save_project.attrs ->> 'key'), x."key"),
        "name" = coalesce(save_project.attrs ->> 'name', x."name"),
        "owner_user_id" = case when save_project.attrs ? 'ownerId' then (save_project.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
        "status" = coalesce(better_supabase.as_column_type(save_project.attrs ->> 'status', (null::"better_supabase"."projects")."status"), x."status"),
        "start_on" = case when save_project.attrs ? 'startOn' then (save_project.attrs ->> 'startOn')::date else x."start_on" end,
        "target_on" = case when save_project.attrs ? 'targetOn' then (save_project.attrs ->> 'targetOn')::date else x."target_on" end,
        "budget_amount" = case when save_project.attrs ? 'budgetAmount' then (save_project.attrs ->> 'budgetAmount')::bigint else x."budget_amount" end,
        "budget_currency" = case when save_project.attrs ? 'budgetCurrency' then upper(save_project.attrs ->> 'budgetCurrency') else x."budget_currency" end,
        "budget_hours" = case when save_project.attrs ? 'budgetHours' then (save_project.attrs ->> 'budgetHours')::numeric else x."budget_hours" end,
        "archived_at" = case when save_project.attrs ? 'archived' then (case when (save_project.attrs ->> 'archived')::boolean then coalesce(x."archived_at", now()) end) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_project.tenant;
      if not found then
        raise exception 'project not found' using errcode = 'P0002', hint = 'TASK_PROJECT_NOT_FOUND';
      end if;
    end if;
    if exists (
      select 1 from "better_supabase"."projects" x
      where x."id" = v_id and x."budget_amount" is not null and x."budget_currency" is null
    ) then
      raise exception 'a budget amount needs a currency' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
    end if;
  exception when unique_violation then
    raise exception 'another project has this key' using errcode = '23505', hint = 'TASK_PROJECT_KEY_TAKEN';
  when check_violation or not_null_violation then
    raise exception 'a project needs a key of capitals and a name, and ends after it starts' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end;

  return (select to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."tasks" y where y."project_id" = x."id" and y."archived_at" is null
    )) from "better_supabase"."projects" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_project"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_project"(uuid, uuid, jsonb) to authenticated, service_role;

-- Creates an iteration (a cycle or a sprint) or changes it: name, teamId,
-- startsOn, endsOn.
create or replace function "better_supabase"."save_iteration"(tenant uuid, iteration uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_iteration.iteration;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_iteration.tenant, 'tasks.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."iterations" ("tenant_id", "team_id", "name", "starts_on", "ends_on")
      values (save_iteration.tenant, (save_iteration.attrs ->> 'teamId')::uuid, save_iteration.attrs ->> 'name',
        (save_iteration.attrs ->> 'startsOn')::date, (save_iteration.attrs ->> 'endsOn')::date)
      returning "id" into v_id;
    else
      update "better_supabase"."iterations" x set
        "name" = coalesce(save_iteration.attrs ->> 'name', x."name"),
        "starts_on" = coalesce((save_iteration.attrs ->> 'startsOn')::date, x."starts_on"),
        "ends_on" = coalesce((save_iteration.attrs ->> 'endsOn')::date, x."ends_on")
      where x."id" = v_id and x."tenant_id" = save_iteration.tenant;
      if not found then
        raise exception 'iteration not found' using errcode = 'P0002', hint = 'TASK_ITERATION_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation then
    raise exception 'an iteration needs a name and ends on or after it starts' using errcode = '22023', hint = 'TASK_ITERATION_INVALID';
  end;
  return (select to_jsonb(x) from "better_supabase"."iterations" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_iteration"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_iteration"(uuid, uuid, jsonb) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."tasks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tasks";
create policy bsb_tenant_scope_select on "better_supabase"."tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tasks";
create policy bsb_tenant_scope_insert on "better_supabase"."tasks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tasks";
create policy bsb_tenant_scope_update on "better_supabase"."tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tasks";
create policy bsb_tenant_scope_delete on "better_supabase"."tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."task_checklist_items";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_select on "better_supabase"."task_checklist_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_insert on "better_supabase"."task_checklist_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_update on "better_supabase"."task_checklist_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_delete on "better_supabase"."task_checklist_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."task_assignees";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_select on "better_supabase"."task_assignees" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_insert on "better_supabase"."task_assignees" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_update on "better_supabase"."task_assignees" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_delete on "better_supabase"."task_assignees" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."projects";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."projects";
create policy bsb_tenant_scope_select on "better_supabase"."projects" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."projects";
create policy bsb_tenant_scope_insert on "better_supabase"."projects" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."projects";
create policy bsb_tenant_scope_update on "better_supabase"."projects" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."projects";
create policy bsb_tenant_scope_delete on "better_supabase"."projects" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."iterations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."iterations";
create policy bsb_tenant_scope_select on "better_supabase"."iterations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."iterations";
create policy bsb_tenant_scope_insert on "better_supabase"."iterations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."iterations";
create policy bsb_tenant_scope_update on "better_supabase"."iterations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."iterations";
create policy bsb_tenant_scope_delete on "better_supabase"."iterations" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_091_tasks.sql
-- better-supabase module: tasks
-- @bsb-block-data tasks
-- @bsb-hash sha256:ea8a7f6275992a7e6c1d4e1fb480479290ca96436b7d2cd1815c10fb28bbf310
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_members"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_members" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipelines"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipelines" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipeline_stage_history"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipeline_stage_history" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_091_tasks.sql
-- better-supabase module: tasks
-- @bsb-block tasks@4 managed
-- @bsb-hash sha256:bde621f22739d62562e4382c5e808648a543cdad881aedda60204f4ba7db9af3
-- Issues and tasks on pipelines: identifiers, parents without cycles, several assignees, priority 0 to 4, estimates, start, end and due dates, locking, projects, iterations, batched edits and a progress tree.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tasks";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tasks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_checklist_items";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_checklist_items";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_assignees";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_assignees";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."projects";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."projects";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."iterations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."iterations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Work items on pipelines: issues and tasks with an identifier, a parent,
-- assignees, a priority, dates, projects and iterations.

create table if not exists "better_supabase"."projects" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "key" text not null check ("key" ~ '^[A-Z][A-Z0-9]{0,9}$'),
  "name" text not null check (length("name") between 1 and 200),
  "owner_user_id" uuid,
  "status" text not null default 'planned' check ("status" in ('planned', 'active', 'paused', 'completed', 'canceled')),
  "start_on" date,
  "target_on" date,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "key"),
  check ("target_on" is null or "start_on" is null or "target_on" >= "start_on")
);
alter table "better_supabase"."projects" add column if not exists "budget_amount" bigint check ("budget_amount" >= 0);
alter table "better_supabase"."projects" add column if not exists "budget_currency" text check ("budget_currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."projects" add column if not exists "budget_hours" numeric(12, 2) check ("budget_hours" >= 0);
alter table "better_supabase"."projects" enable row level security;
revoke all on "better_supabase"."projects" from public, anon, authenticated;
grant select on "better_supabase"."projects" to authenticated;
grant all on "better_supabase"."projects" to service_role;
drop policy if exists projects_read on "better_supabase"."projects";
create policy projects_read on "better_supabase"."projects"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table if not exists "better_supabase"."iterations" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "team_id" uuid,
  "name" text not null check (length("name") between 1 and 200),
  "starts_on" date not null,
  "ends_on" date not null,
  "created_at" timestamptz not null default now(),
  check ("ends_on" >= "starts_on")
);
create index if not exists iterations_tenant_idx on "better_supabase"."iterations" ("org_id", "team_id", "starts_on");
alter table "better_supabase"."iterations" enable row level security;
revoke all on "better_supabase"."iterations" from public, anon, authenticated;
grant select on "better_supabase"."iterations" to authenticated;
grant all on "better_supabase"."iterations" to service_role;
drop policy if exists iterations_read on "better_supabase"."iterations";
create policy iterations_read on "better_supabase"."iterations"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table if not exists "better_supabase"."tasks" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "title" text not null check (length("title") between 1 and 500),
  "body" text,
  "parent_id" uuid references "better_supabase"."tasks" ("id") on delete cascade,
  "team_id" uuid,
  "project_id" uuid references "better_supabase"."projects" ("id") on delete set null,
  "iteration_id" uuid references "better_supabase"."iterations" ("id") on delete set null,
  "priority" smallint not null default 0 check ("priority" between 0 and 4),
  "estimate" numeric(10, 2) check ("estimate" >= 0),
  "progress" smallint check ("progress" between 0 and 100),
  "start_at" timestamptz,
  "end_at" timestamptz,
  "due_at" timestamptz,
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  "state" text not null default 'backlog' check ("state" in ('triage', 'backlog', 'unstarted', 'started', 'completed', 'canceled')),
  "close_reason" text check ("close_reason" in ('completed', 'not_planned', 'duplicate')),
  "closed_at" timestamptz,
  "locked" boolean not null default false,
  "rank" text collate "C" not null default 'V',
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "number"),
  check ("end_at" is null or "start_at" is null or "end_at" >= "start_at")
);
create index if not exists "tasks_board_idx" on "better_supabase"."tasks" ("pipeline_id", "stage_id", "rank");
create index if not exists "tasks_parent_idx" on "better_supabase"."tasks" ("parent_id");
create index if not exists "tasks_project_idx" on "better_supabase"."tasks" ("project_id");
create index if not exists "tasks_iteration_idx" on "better_supabase"."tasks" ("iteration_id");
create index if not exists "tasks_due_idx" on "better_supabase"."tasks" ("org_id", "due_at") where "closed_at" is null;
alter table "better_supabase"."tasks" enable row level security;
revoke all on "better_supabase"."tasks" from public, anon, authenticated;
grant select on "better_supabase"."tasks" to authenticated;
grant all on "better_supabase"."tasks" to service_role;
drop policy if exists tasks_read on "better_supabase"."tasks";
create policy tasks_read on "better_supabase"."tasks"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table if not exists "better_supabase"."task_assignees" (
  "org_id" uuid not null,
  "task_id" uuid not null references "better_supabase"."tasks" ("id") on delete cascade,
  "user_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("task_id", "user_id")
);
create index if not exists "task_assignees_user_idx" on "better_supabase"."task_assignees" ("user_id");
alter table "better_supabase"."task_assignees" enable row level security;
revoke all on "better_supabase"."task_assignees" from public, anon, authenticated;
grant select on "better_supabase"."task_assignees" to authenticated;
grant all on "better_supabase"."task_assignees" to service_role;
drop policy if exists task_assignees_read on "better_supabase"."task_assignees";
create policy task_assignees_read on "better_supabase"."task_assignees"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('tasks.read')));

alter table "better_supabase"."tasks" add column if not exists "recurs_from" uuid references "better_supabase"."tasks" ("id") on delete set null;
create unique index if not exists "tasks_recurs_from_idx" on "better_supabase"."tasks" ("recurs_from");

create table if not exists "better_supabase"."task_checklist_items" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "task_id" uuid not null references "better_supabase"."tasks" ("id") on delete cascade,
  "title" text not null check (length("title") between 1 and 500),
  "done" boolean not null default false,
  "done_at" timestamptz,
  "done_by" uuid,
  "rank" text collate "C" not null check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
create index if not exists "task_checklist_item_idx" on "better_supabase"."task_checklist_items" ("task_id", "rank");
alter table "better_supabase"."task_checklist_items" enable row level security;
revoke all on "better_supabase"."task_checklist_items" from public, anon, authenticated;
grant select on "better_supabase"."task_checklist_items" to authenticated;
grant all on "better_supabase"."task_checklist_items" to service_role;
drop policy if exists task_checklist_items_read on "better_supabase"."task_checklist_items";
create policy task_checklist_items_read on "better_supabase"."task_checklist_items"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create or replace function better_supabase.bsb_work_item_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."parent_id" is not null and (tg_op = 'INSERT' or new."parent_id" is distinct from old."parent_id") then
    if exists (
      with recursive up(id, depth) as (
        select new."parent_id", 1
        union all
        select x."parent_id", up.depth + 1 from "better_supabase"."tasks" x join up on x."id" = up.id
        where x."parent_id" is not null and up.depth < 100
      )
      select 1 from up where up.id = new."id"
    ) then
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'TASK_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "better_supabase"."tasks" x where x."id" = new."parent_id" and x."org_id" = new."org_id") then
      raise exception 'the parent is in another organization' using errcode = '22023', hint = 'TASK_PARENT_INVALID';
    end if;
  end if;
  if tg_op = 'UPDATE' and old."locked" and not (auth.role() = 'service_role') and (new."start_at" is distinct from old."start_at" or new."end_at" is distinct from old."end_at" or new."due_at" is distinct from old."due_at") then
    raise exception 'the item is locked; its dates can''t change' using errcode = '55000', hint = 'TASK_LOCKED';
  end if;
  if tg_op = 'INSERT' then
    if new."state" in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
    end if;
    return new;
  end if;
  if new."state" is distinct from old."state" then
    if new."state" in ('completed', 'canceled') and old."state" not in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
      if new."state" = 'completed' and new."progress" is not null then
        new."progress" := 100;
      end if;
      null;
    elsif not (new."state" in ('completed', 'canceled')) and old."state" in ('completed', 'canceled') then
      new."closed_at" := null;
      new."close_reason" := null;
      null;
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_work_item_guard() from public, anon, authenticated;
drop trigger if exists bsb_work_item_guard on "better_supabase"."tasks";
create trigger bsb_work_item_guard before insert or update on "better_supabase"."tasks"
for each row execute function better_supabase.bsb_work_item_guard();

-- Creates a work item. attrs: title (required), body, parentId, teamId,
-- projectId, iterationId, priority (0 none to 4 low, as Linear), estimate,
-- progress, startAt, endAt, dueAt, pipelineId, stageId, and fields (the
-- extra columns, by name). assignees: user ids.
create or replace function "better_supabase"."create_task"(tenant uuid, attrs jsonb, assignees uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seq bigint;
  v_identifier text;
  v_id uuid;
  v_row "better_supabase"."tasks";
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_task.tenant, 'tasks.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if nullif(trim(create_task.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'TASK_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_task_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_task.tenant, create_task.attrs;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'work_item' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'work_item' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_task.tenant::text || ':work_item', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."tasks" x where x."org_id" = create_task.tenant;
  v_identifier := 'TASK-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."tasks" ("org_id", "number", "identifier", "title", "body", "parent_id", "team_id", "project_id", "iteration_id",
      "priority", "estimate", "progress", "start_at", "end_at", "due_at", "pipeline_id", "stage_id", "created_by")
    values (create_task.tenant, v_seq, v_identifier, trim(create_task.attrs ->> 'title'), create_task.attrs ->> 'body',
      (create_task.attrs ->> 'parentId')::uuid, (create_task.attrs ->> 'teamId')::uuid, (create_task.attrs ->> 'projectId')::uuid,
      (create_task.attrs ->> 'iterationId')::uuid, coalesce((create_task.attrs ->> 'priority')::smallint, 0),
      (create_task.attrs ->> 'estimate')::numeric, (create_task.attrs ->> 'progress')::smallint,
      (create_task.attrs ->> 'startAt')::timestamptz, (create_task.attrs ->> 'endAt')::timestamptz, (create_task.attrs ->> 'dueAt')::timestamptz,
      (create_task.attrs ->> 'pipelineId')::uuid, (create_task.attrs ->> 'stageId')::uuid, auth.uid())
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  if cardinality(coalesce(create_task.assignees, '{}')) > 0 then
    perform "better_supabase"."set_task_assignees"(v_id, create_task.assignees);
  end if;
  select * into v_row from "better_supabase"."tasks" x where x."id" = v_id;
  if jsonb_array_length(coalesce((create_task.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      raise exception 'install the attachments block to attach files' using errcode = '0A000', hint = 'TASK_ATTACHMENTS_UNAVAILABLE';
    end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_task_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select (to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id")) from "better_supabase"."tasks" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_task"(uuid, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."create_task"(uuid, jsonb, uuid[]) to authenticated, service_role;

-- Applies a batch of { workItemId, field, value } changes, each on its
-- own. Returns { accepted: [{ workItemId, field }], rejected: [{ workItemId,
-- field, hint, reason }] }. With atomic, the first change that fails raises
-- its error and no change is kept. The window field ({ startAt, endAt })
-- writes both ends in one update, so the end-after-start check sees both.
drop function if exists "better_supabase"."update_tasks"(jsonb);
create or replace function "better_supabase"."update_tasks"(changes jsonb, atomic boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_item uuid;
  v_field text;
  v_row "better_supabase"."tasks";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_tasks.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { workItemId, field, value }' using errcode = '22023', hint = 'TASK_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_tasks.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'workItemId')::uuid;
      if not exists (select 1 from "better_supabase"."tasks" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."org_id", 'tasks.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_task_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_item, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'title' then
        update "better_supabase"."tasks" x set "title" = trim(v_change -> 'value' #>> '{}') where x."id" = v_item;
      when 'body' then
        update "better_supabase"."tasks" x set "body" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'parentId' then
        update "better_supabase"."tasks" x set "parent_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'teamId' then
        update "better_supabase"."tasks" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'projectId' then
        update "better_supabase"."tasks" x set "project_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'iterationId' then
        update "better_supabase"."tasks" x set "iteration_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'priority' then
        update "better_supabase"."tasks" x set "priority" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'estimate' then
        update "better_supabase"."tasks" x set "estimate" = (v_change -> 'value' #>> '{}')::numeric where x."id" = v_item;
      when 'progress' then
        update "better_supabase"."tasks" x set "progress" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'startAt' then
        update "better_supabase"."tasks" x set "start_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'endAt' then
        update "better_supabase"."tasks" x set "end_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'dueAt' then
        update "better_supabase"."tasks" x set "due_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'stageId' then
        update "better_supabase"."tasks" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'closeReason' then
        update "better_supabase"."tasks" x set "close_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'window' then
        if jsonb_typeof(v_change -> 'value') <> 'object' then
          raise exception 'window must be an object of startAt and endAt' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
        end if;
        update "better_supabase"."tasks" x set
          "start_at" = case when v_change -> 'value' ? 'startAt' then (v_change -> 'value' ->> 'startAt')::timestamptz else x."start_at" end,
          "end_at" = case when v_change -> 'value' ? 'endAt' then (v_change -> 'value' ->> 'endAt')::timestamptz else x."end_at" end
        where x."id" = v_item;
      when 'attachments' then
        select * into v_row from "better_supabase"."tasks" x where x."id" = v_item;
        if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      raise exception 'install the attachments block to attach files' using errcode = '0A000', hint = 'TASK_ATTACHMENTS_UNAVAILABLE';
    end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'TASK_FIELD_UNKNOWN';
      end case;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('workItemId', v_item, 'field', v_field));
      v_touched := array_append(v_touched, v_item);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_task_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_item, v_field;
    end if;
  end;
    exception when others then
      if update_tasks.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_change ->> 'workItemId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."tasks" x where x."id" = any (v_touched) loop
    null;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "better_supabase"."update_tasks"(jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."update_tasks"(jsonb, boolean) to authenticated, service_role;

-- Replaces an item's assignees. Each one watches the item, and those who
-- weren't assigned before are notified. task.assigned is recorded only
-- when the call adds someone, with addedIds.
create or replace function "better_supabase"."set_task_assignees"(work_item uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_task_assignees.users, '{}')) x where x is not null);
  v_added uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."tasks" x where x."id" = set_task_assignees.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."org_id", 'tasks.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_added := array(select x from unnest(v_users) x where not exists (
    select 1 from "better_supabase"."task_assignees" y where y."task_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."task_assignees" y where y."task_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."task_assignees" ("org_id", "task_id", "user_id")
  select v_row."org_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  if cardinality(v_added) > 0 then
    null;
  end if;
  return cardinality(v_users);
end;
$$;
revoke execute on function "better_supabase"."set_task_assignees"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."set_task_assignees"(uuid, uuid[]) to authenticated, service_role;

create or replace function "better_supabase"."archive_task"(work_item uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."tasks" x set "archived_at" = case when archive_task.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_task.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."org_id", 'tasks.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_task.archived then
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_task"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_task"(uuid, boolean) to authenticated, service_role;

-- Deletes an item and its children. Needs work_items.manage, or its author.
create or replace function "better_supabase"."delete_task"(work_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."tasks" x
  where x."id" = delete_task.work_item
    and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."org_id", 'tasks.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_task"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_task"(uuid) to authenticated, service_role;

-- An item and everything under it with its depth. An item without its own
-- progress takes the share of its open and completed children that are
-- completed, so a Gantt group shows a rollup.
create or replace function "better_supabase"."task_tree"(root uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with recursive tree as (
    select x.*, 0 as depth from "better_supabase"."tasks" x where x."id" = task_tree.root
    union all
    select y.*, tree.depth + 1 from "better_supabase"."tasks" y join tree on y."parent_id" = tree."id"
    where tree.depth < 100 and y."archived_at" is null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', tree."id", 'parentId', tree."parent_id", 'identifier', tree."identifier", 'title', tree."title",
    'state', tree."state", 'startAt', tree."start_at", 'endAt', tree."end_at", 'dueAt', tree."due_at",
    'locked', tree."locked", 'depth', tree.depth,
    'progress', coalesce(tree."progress", (
      select case when count(*) filter (where ch."state" <> 'canceled') = 0 then
          case tree."state" when 'completed' then 100 else 0 end
        else round(100.0 * count(*) filter (where ch."state" = 'completed') / count(*) filter (where ch."state" <> 'canceled'))::integer end
      from "better_supabase"."tasks" ch where ch."parent_id" = tree."id" and ch."archived_at" is null))
  ) order by tree.depth, tree."rank" collate "C", tree."id"), '[]'::jsonb)
  from tree
$$;
revoke execute on function "better_supabase"."task_tree"(uuid) from public, anon;
grant execute on function "better_supabase"."task_tree"(uuid) to authenticated, service_role;

-- A page of a tenant's active items, newest first. filter keys: teamId,
-- projectId, iterationId, parentId, assigneeId, states (a list), open
-- (only unclosed). search matches the title and identifier. after continues
-- after that item.
create or replace function "better_supabase"."list_tasks"(tenant uuid, filter jsonb, search text, after uuid, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.number desc), '[]'::jsonb)
  from (
    select (to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id")) as value, x."number" as number
    from "better_supabase"."tasks" x
    where x."org_id" = list_tasks.tenant and x."archived_at" is null
      and (list_tasks.filter ->> 'teamId' is null or x."team_id" = (list_tasks.filter ->> 'teamId')::uuid)
      and (list_tasks.filter ->> 'projectId' is null or x."project_id" = (list_tasks.filter ->> 'projectId')::uuid)
      and (list_tasks.filter ->> 'iterationId' is null or x."iteration_id" = (list_tasks.filter ->> 'iterationId')::uuid)
      and (list_tasks.filter ->> 'parentId' is null or x."parent_id" = (list_tasks.filter ->> 'parentId')::uuid)
      and (list_tasks.filter ->> 'assigneeId' is null or exists (select 1 from "better_supabase"."task_assignees" y where y."task_id" = x."id" and y."user_id" = (list_tasks.filter ->> 'assigneeId')::uuid))
      and (list_tasks.filter -> 'states' is null or x."state" = any (array(select jsonb_array_elements_text(list_tasks.filter -> 'states'))))
      and (coalesce((list_tasks.filter ->> 'open')::boolean, false) = false or x."closed_at" is null)
      and (list_tasks.search is null or x."title" ilike '%' || list_tasks.search || '%' or x."identifier" ilike list_tasks.search || '%')
      and (list_tasks.after is null or x."number" < (select z."number" from "better_supabase"."tasks" z where z."id" = list_tasks.after))
    order by x."number" desc
    limit least(greatest(coalesce(list_tasks.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."list_tasks"(uuid, jsonb, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_tasks"(uuid, jsonb, text, uuid, integer) to authenticated, service_role;

-- Adds a checklist item (checklist_item null) or changes one: title, done,
-- rank. A new item without a rank goes last.
create or replace function "better_supabase"."save_task_checklist_item"(work_item uuid, checklist_item uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
  v_id uuid := save_task_checklist_item.checklist_item;
  v_last text;
  v_done boolean := (save_task_checklist_item.attrs ->> 'done')::boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."tasks" x where x."id" = save_task_checklist_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."org_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  begin
    if v_id is null then
      select max(y."rank") into v_last from "better_supabase"."task_checklist_items" y where y."task_id" = v_row."id";
      insert into "better_supabase"."task_checklist_items" ("org_id", "task_id", "title", "done", "done_at", "done_by", "rank", "created_by")
      values (v_row."org_id", v_row."id", trim(save_task_checklist_item.attrs ->> 'title'), coalesce(v_done, false),
        case when v_done then now() end, case when v_done then auth.uid() end,
        coalesce(save_task_checklist_item.attrs ->> 'rank', case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end), auth.uid())
      returning "id" into v_id;
    else
      update "better_supabase"."task_checklist_items" y set
        "title" = coalesce(trim(save_task_checklist_item.attrs ->> 'title'), y."title"),
        "rank" = coalesce(save_task_checklist_item.attrs ->> 'rank', y."rank"),
        "done" = coalesce(v_done, y."done"),
        "done_at" = case when v_done is null then y."done_at" when v_done then coalesce(y."done_at", now()) end,
        "done_by" = case when v_done is null then y."done_by" when v_done then coalesce(y."done_by", auth.uid()) end
      where y."id" = v_id and y."task_id" = v_row."id";
      if not found then
        raise exception 'no such checklist item on this work item' using errcode = 'P0002', hint = 'TASK_CHECKLIST_ITEM_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a checklist item needs a title of 1 to 500 characters and a valid rank' using errcode = '22023', hint = 'TASK_CHECKLIST_ITEM_INVALID';
  end;
  null;
  return (select jsonb_build_object('id', y."id", 'workItemId', y."task_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") from "better_supabase"."task_checklist_items" y where y."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_task_checklist_item"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_task_checklist_item"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_task_checklist_item"(checklist_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x.* into v_row from "better_supabase"."tasks" x join "better_supabase"."task_checklist_items" y on y."task_id" = x."id"
  where y."id" = delete_task_checklist_item.checklist_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."org_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    return false;
  end if;
  delete from "better_supabase"."task_checklist_items" y where y."id" = delete_task_checklist_item.checklist_item;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_task_checklist_item"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_task_checklist_item"(uuid) to authenticated, service_role;

-- An item's checklist, in rank order.
create or replace function "better_supabase"."list_task_checklist"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'workItemId', y."task_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") order by y."rank" collate "C", y."id"), '[]'::jsonb)
  from "better_supabase"."task_checklist_items" y where y."task_id" = list_task_checklist.work_item
$$;
revoke execute on function "better_supabase"."list_task_checklist"(uuid) from public, anon;
grant execute on function "better_supabase"."list_task_checklist"(uuid) to authenticated, service_role;

-- One item the caller can read, or null.
create or replace function "better_supabase"."get_task"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select (to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id")) from "better_supabase"."tasks" x where x."id" = get_task.work_item
$$;
revoke execute on function "better_supabase"."get_task"(uuid) from public, anon;
grant execute on function "better_supabase"."get_task"(uuid) to authenticated, service_role;

-- Creates a project (project null) or changes the keys attrs names: key,
-- name, ownerId, status, startOn, targetOn, archived, and the budget:
-- budgetAmount (minor units as text) with budgetCurrency, and budgetHours.
-- With accounting, the project is a value of the project dimension.
create or replace function "better_supabase"."save_project"(tenant uuid, project uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_project.project;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_project.tenant, 'tasks.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."projects" ("org_id", "key", "name", "owner_user_id", "status", "start_on", "target_on", "budget_amount", "budget_currency", "budget_hours")
      values (save_project.tenant, upper(save_project.attrs ->> 'key'), save_project.attrs ->> 'name', (save_project.attrs ->> 'ownerId')::uuid,
        coalesce(save_project.attrs ->> 'status', 'planned'), (save_project.attrs ->> 'startOn')::date, (save_project.attrs ->> 'targetOn')::date,
        (save_project.attrs ->> 'budgetAmount')::bigint, upper(save_project.attrs ->> 'budgetCurrency'), (save_project.attrs ->> 'budgetHours')::numeric)
      returning "id" into v_id;
    else
      update "better_supabase"."projects" x set
        "key" = coalesce(upper(save_project.attrs ->> 'key'), x."key"),
        "name" = coalesce(save_project.attrs ->> 'name', x."name"),
        "owner_user_id" = case when save_project.attrs ? 'ownerId' then (save_project.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
        "status" = coalesce(save_project.attrs ->> 'status', x."status"),
        "start_on" = case when save_project.attrs ? 'startOn' then (save_project.attrs ->> 'startOn')::date else x."start_on" end,
        "target_on" = case when save_project.attrs ? 'targetOn' then (save_project.attrs ->> 'targetOn')::date else x."target_on" end,
        "budget_amount" = case when save_project.attrs ? 'budgetAmount' then (save_project.attrs ->> 'budgetAmount')::bigint else x."budget_amount" end,
        "budget_currency" = case when save_project.attrs ? 'budgetCurrency' then upper(save_project.attrs ->> 'budgetCurrency') else x."budget_currency" end,
        "budget_hours" = case when save_project.attrs ? 'budgetHours' then (save_project.attrs ->> 'budgetHours')::numeric else x."budget_hours" end,
        "archived_at" = case when save_project.attrs ? 'archived' then (case when (save_project.attrs ->> 'archived')::boolean then coalesce(x."archived_at", now()) end) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."org_id" = save_project.tenant;
      if not found then
        raise exception 'project not found' using errcode = 'P0002', hint = 'TASK_PROJECT_NOT_FOUND';
      end if;
    end if;
    if exists (
      select 1 from "better_supabase"."projects" x
      where x."id" = v_id and x."budget_amount" is not null and x."budget_currency" is null
    ) then
      raise exception 'a budget amount needs a currency' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
    end if;
  exception when unique_violation then
    raise exception 'another project has this key' using errcode = '23505', hint = 'TASK_PROJECT_KEY_TAKEN';
  when check_violation or not_null_violation then
    raise exception 'a project needs a key of capitals and a name, and ends after it starts' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end;

  return (select (to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."tasks" y where y."project_id" = x."id" and y."archived_at" is null
    )) from "better_supabase"."projects" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_project"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_project"(uuid, uuid, jsonb) to authenticated, service_role;

-- Creates an iteration (a cycle or a sprint) or changes it: name, teamId,
-- startsOn, endsOn.
create or replace function "better_supabase"."save_iteration"(tenant uuid, iteration uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_iteration.iteration;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_iteration.tenant, 'tasks.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."iterations" ("org_id", "team_id", "name", "starts_on", "ends_on")
      values (save_iteration.tenant, (save_iteration.attrs ->> 'teamId')::uuid, save_iteration.attrs ->> 'name',
        (save_iteration.attrs ->> 'startsOn')::date, (save_iteration.attrs ->> 'endsOn')::date)
      returning "id" into v_id;
    else
      update "better_supabase"."iterations" x set
        "name" = coalesce(save_iteration.attrs ->> 'name', x."name"),
        "starts_on" = coalesce((save_iteration.attrs ->> 'startsOn')::date, x."starts_on"),
        "ends_on" = coalesce((save_iteration.attrs ->> 'endsOn')::date, x."ends_on")
      where x."id" = v_id and x."org_id" = save_iteration.tenant;
      if not found then
        raise exception 'iteration not found' using errcode = 'P0002', hint = 'TASK_ITERATION_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation then
    raise exception 'an iteration needs a name and ends on or after it starts' using errcode = '22023', hint = 'TASK_ITERATION_INVALID';
  end;
  return (select (to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) from "better_supabase"."iterations" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_iteration"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_iteration"(uuid, uuid, jsonb) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."tasks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tasks";
create policy bsb_tenant_scope_select on "better_supabase"."tasks" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tasks";
create policy bsb_tenant_scope_insert on "better_supabase"."tasks" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tasks";
create policy bsb_tenant_scope_update on "better_supabase"."tasks" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tasks";
create policy bsb_tenant_scope_delete on "better_supabase"."tasks" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."task_checklist_items";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_select on "better_supabase"."task_checklist_items" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_insert on "better_supabase"."task_checklist_items" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_update on "better_supabase"."task_checklist_items" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_checklist_items";
create policy bsb_tenant_scope_delete on "better_supabase"."task_checklist_items" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."task_assignees";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_select on "better_supabase"."task_assignees" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_insert on "better_supabase"."task_assignees" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_update on "better_supabase"."task_assignees" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."task_assignees";
create policy bsb_tenant_scope_delete on "better_supabase"."task_assignees" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."projects";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."projects";
create policy bsb_tenant_scope_select on "better_supabase"."projects" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."projects";
create policy bsb_tenant_scope_insert on "better_supabase"."projects" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."projects";
create policy bsb_tenant_scope_update on "better_supabase"."projects" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."projects";
create policy bsb_tenant_scope_delete on "better_supabase"."projects" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."iterations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."iterations";
create policy bsb_tenant_scope_select on "better_supabase"."iterations" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."iterations";
create policy bsb_tenant_scope_insert on "better_supabase"."iterations" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."iterations";
create policy bsb_tenant_scope_update on "better_supabase"."iterations" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."iterations";
create policy bsb_tenant_scope_delete on "better_supabase"."iterations" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_091_tasks.sql
-- better-supabase module: tasks
-- @bsb-block-data tasks
-- @bsb-hash sha256:ea8a7f6275992a7e6c1d4e1fb480479290ca96436b7d2cd1815c10fb28bbf310
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_members"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_members" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipelines"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipelines" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipeline_stage_history"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipeline_stage_history" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
