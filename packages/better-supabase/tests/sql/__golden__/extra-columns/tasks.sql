-- ==== schema supabase/schemas/900_better_supabase_091_tasks.sql
-- better-supabase module: tasks
-- @bsb-block tasks@5 managed
-- @bsb-hash sha256:e9cb4115d77c5d9f42c71ff39d8600a936f4376c6cc0bad3c73f1843db605075
-- Issues and tasks on pipelines: identifiers, parents without cycles, several assignees, priority 0 to 4, estimates, start, end and due dates, locking, projects, iterations, batched edits and a progress tree.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Work items on pipelines: issues and tasks with an identifier, a parent,
-- assignees, a priority, dates, projects and iterations.

create table "better_supabase"."projects" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null constraint bsb_projects_key_check check ("key" ~ '^[A-Z][A-Z0-9]{0,9}$'),
  "name" text not null constraint bsb_projects_name_check check (length("name") >= 1 and length("name") <= 200),
  "owner_id" uuid,
  "status" text not null default 'planned' constraint bsb_projects_status_check check ("status" in ('planned', 'active', 'paused', 'completed', 'canceled')),
  "start_on" date,
  "target_on" date,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  constraint bsb_projects_check check ("target_on" is null or "start_on" is null or "target_on" >= "start_on")
);
alter table "better_supabase"."projects" add column "budget_amount" bigint constraint bsb_projects_budget_amount_check check ("budget_amount" >= 0);
alter table "better_supabase"."projects" add column "budget_currency" text constraint bsb_projects_budget_currency_check check ("budget_currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."projects" add column "budget_hours" numeric(12, 2) constraint bsb_projects_budget_hours_check check ("budget_hours" >= 0);
alter table "better_supabase"."projects" enable row level security;
revoke all on "better_supabase"."projects" from public, anon, authenticated;
grant select on "better_supabase"."projects" to authenticated;
grant all on "better_supabase"."projects" to service_role;
create policy bsb_projects_read on "better_supabase"."projects"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table "better_supabase"."iterations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "team_id" uuid,
  "name" text not null constraint bsb_iterations_name_check check (length("name") >= 1 and length("name") <= 200),
  "starts_on" date not null,
  "ends_on" date not null,
  "created_at" timestamptz not null default now(),
  constraint bsb_iterations_check check ("ends_on" >= "starts_on")
);
create index iterations_tenant_idx on "better_supabase"."iterations" ("tenant_id", "team_id", "starts_on");
alter table "better_supabase"."iterations" enable row level security;
revoke all on "better_supabase"."iterations" from public, anon, authenticated;
grant select on "better_supabase"."iterations" to authenticated;
grant all on "better_supabase"."iterations" to service_role;
create policy bsb_iterations_read on "better_supabase"."iterations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table "better_supabase"."tasks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "title" text not null constraint bsb_tasks_title_check check (length("title") >= 1 and length("title") <= 500),
  "body" text,
  "parent_id" uuid references "better_supabase"."tasks" ("id") on delete cascade,
  "team_id" uuid,
  "project_id" uuid references "better_supabase"."projects" ("id") on delete set null,
  "iteration_id" uuid references "better_supabase"."iterations" ("id") on delete set null,
  "priority" smallint not null default 0 constraint bsb_tasks_priority_check check ("priority" >= 0 and "priority" <= 4),
  "estimate" numeric(10, 2) constraint bsb_tasks_estimate_check check ("estimate" >= 0),
  "estimated_minutes" integer constraint bsb_tasks_estimated_minutes_check check ("estimated_minutes" >= 0),
  "progress" smallint constraint bsb_tasks_progress_check check ("progress" >= 0 and "progress" <= 100),
  "start_at" timestamptz,
  "end_at" timestamptz,
  "due_at" timestamptz,
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  "state" text not null default 'backlog' constraint bsb_tasks_state_check check ("state" in ('triage', 'backlog', 'unstarted', 'started', 'completed', 'canceled')),
  "close_reason" text constraint bsb_tasks_close_reason_check check ("close_reason" in ('completed', 'not_planned', 'duplicate')),
  "closed_at" timestamptz,
  "locked" boolean not null default false,
  "rank" text collate "C" not null default 'V',
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  constraint bsb_tasks_check check ("end_at" is null or "start_at" is null or "end_at" >= "start_at")
);
create index "tasks_board_idx" on "better_supabase"."tasks" ("pipeline_id", "stage_id", "rank");
create index "tasks_parent_idx" on "better_supabase"."tasks" ("parent_id");
create index "tasks_project_idx" on "better_supabase"."tasks" ("project_id");
create index "tasks_iteration_idx" on "better_supabase"."tasks" ("iteration_id");
create index "tasks_due_idx" on "better_supabase"."tasks" ("tenant_id", "due_at") where "closed_at" is null;
alter table "better_supabase"."tasks" enable row level security;
revoke all on "better_supabase"."tasks" from public, anon, authenticated;
grant select on "better_supabase"."tasks" to authenticated;
grant all on "better_supabase"."tasks" to service_role;
create policy bsb_tasks_read on "better_supabase"."tasks"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table "better_supabase"."task_assignees" (
  "tenant_id" uuid not null,
  "task_id" uuid not null references "better_supabase"."tasks" ("id") on delete cascade,
  "user_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("task_id", "user_id")
);
create index "task_assignees_user_idx" on "better_supabase"."task_assignees" ("user_id");
alter table "better_supabase"."task_assignees" enable row level security;
revoke all on "better_supabase"."task_assignees" from public, anon, authenticated;
grant select on "better_supabase"."task_assignees" to authenticated;
grant all on "better_supabase"."task_assignees" to service_role;
create policy bsb_task_assignees_read on "better_supabase"."task_assignees"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

alter table "better_supabase"."tasks" add column "recurs_from" uuid references "better_supabase"."tasks" ("id") on delete set null;
create unique index "tasks_recurs_from_idx" on "better_supabase"."tasks" ("recurs_from");

create table "better_supabase"."task_checklist_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "task_id" uuid not null references "better_supabase"."tasks" ("id") on delete cascade,
  "title" text not null constraint bsb_task_checklist_items_title_check check (length("title") >= 1 and length("title") <= 500),
  "done" boolean not null default false,
  "done_at" timestamptz,
  "done_by" uuid,
  "rank" text collate "C" not null constraint bsb_task_checklist_items_rank_check check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
create index "task_checklist_item_idx" on "better_supabase"."task_checklist_items" ("task_id", "rank");
alter table "better_supabase"."task_checklist_items" enable row level security;
revoke all on "better_supabase"."task_checklist_items" from public, anon, authenticated;
grant select on "better_supabase"."task_checklist_items" to authenticated;
grant all on "better_supabase"."task_checklist_items" to service_role;
create policy bsb_task_checklist_items_read on "better_supabase"."task_checklist_items"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));


create table "better_supabase"."task_specification_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "task_id" uuid not null references "better_supabase"."tasks" ("id") on delete cascade,
  "description" text not null constraint bsb_task_specification_lines_description_check check (char_length("description") >= 1 and char_length("description") <= 500),
  "quantity" numeric(12, 3) constraint bsb_task_specification_lines_quantity_check check ("quantity" >= 0),
  "unit" text constraint bsb_task_specification_lines_unit_check check (char_length("unit") >= 1 and char_length("unit") <= 30),
  "estimate" numeric(10, 2) constraint bsb_task_specification_lines_estimate_check check ("estimate" >= 0),
  "rank" text collate "C" not null constraint bsb_task_specification_lines_rank_check check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_at" timestamptz not null default now()
);
create index "bsb_task_specification_lines_item_idx" on "better_supabase"."task_specification_lines" ("task_id", "rank");
alter table "better_supabase"."task_specification_lines" enable row level security;
revoke all on "better_supabase"."task_specification_lines" from public, anon, authenticated;
grant select on "better_supabase"."task_specification_lines" to authenticated;
grant all on "better_supabase"."task_specification_lines" to service_role;
create policy bsb_task_specification_lines_read on "better_supabase"."task_specification_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table "better_supabase"."task_material_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "task_id" uuid not null references "better_supabase"."tasks" ("id") on delete cascade,
  "variant_id" uuid,
  "quantity" numeric(12, 3) not null constraint bsb_task_material_lines_quantity_check check ("quantity" >= 0),
  "unit" text constraint bsb_task_material_lines_unit_check check (char_length("unit") >= 1 and char_length("unit") <= 30),
  "rank" text collate "C" not null constraint bsb_task_material_lines_rank_check check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_at" timestamptz not null default now()
);
create index "bsb_task_material_lines_item_idx" on "better_supabase"."task_material_lines" ("task_id", "rank");
create index "bsb_task_material_lines_variant_idx" on "better_supabase"."task_material_lines" ("variant_id") where "variant_id" is not null;
alter table "better_supabase"."task_material_lines" enable row level security;
revoke all on "better_supabase"."task_material_lines" from public, anon, authenticated;
grant select on "better_supabase"."task_material_lines" to authenticated;
grant all on "better_supabase"."task_material_lines" to service_role;
create policy bsb_task_material_lines_read on "better_supabase"."task_material_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));


-- Adds a specification line (the line id null) or changes one. A new line
-- without a rank goes after the last one. Needs tasks.write.
create or replace function "better_supabase"."save_task_specification_line"(task uuid, line_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."tasks";
  v_id uuid := save_task_specification_line.line_id;
  v_last text;
  v_line "better_supabase"."task_specification_lines";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(save_task_specification_line.attrs) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'TASK_LINE_INVALID';
  end if;
  select * into v_row from "better_supabase"."tasks" x
  where x."id" = save_task_specification_line.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'work item not found' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if v_id is null then
    select max(y."rank") into v_last from "better_supabase"."task_specification_lines" y where y."task_id" = v_row."id";
    insert into "better_supabase"."task_specification_lines" ("tenant_id", "task_id", "description", "quantity", "unit", "estimate", "rank")
    values (v_row."tenant_id", v_row."id", nullif(btrim(save_task_specification_line.attrs ->> 'description'), ''), nullif(save_task_specification_line.attrs ->> 'quantity', '')::numeric, nullif(btrim(save_task_specification_line.attrs ->> 'unit'), ''), nullif(save_task_specification_line.attrs ->> 'estimate', '')::numeric, coalesce(nullif(save_task_specification_line.attrs ->> 'rank', ''), case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end))
    returning * into v_line;
  else
    update "better_supabase"."task_specification_lines" y set "description" = coalesce(nullif(btrim(save_task_specification_line.attrs ->> 'description'), ''), "description"), "quantity" = coalesce(nullif(save_task_specification_line.attrs ->> 'quantity', '')::numeric, "quantity"), "unit" = case when save_task_specification_line.attrs ? 'unit' then nullif(btrim(save_task_specification_line.attrs ->> 'unit'), '') else "unit" end, "estimate" = case when save_task_specification_line.attrs ? 'estimate' then nullif(save_task_specification_line.attrs ->> 'estimate', '')::numeric else "estimate" end, "rank" = coalesce(nullif(save_task_specification_line.attrs ->> 'rank', ''), "rank")
    where y."id" = v_id and y."task_id" = v_row."id"
    returning * into v_line;
    if v_line."id" is null then
      raise exception 'no such line on this work item' using errcode = '22023', hint = 'TASK_LINE_INVALID';
    end if;
  end if;
  return jsonb_build_object('id', v_line."id", 'taskId', v_line."task_id", 'rank', v_line."rank");
end;
$$;
revoke execute on function "better_supabase"."save_task_specification_line"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_task_specification_line"(uuid, uuid, jsonb) to authenticated, service_role;


-- The specification lines of one work item, in rank order. Needs tasks.read.
create or replace function "better_supabase"."list_task_specification"(task uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'taskId', y."task_id", 'description', y."description", 'quantity', y."quantity", 'unit', y."unit", 'estimate', y."estimate", 'rank', y."rank") order by y."rank", y."id"), '[]'::jsonb)
  from "better_supabase"."tasks" x
  join "better_supabase"."task_specification_lines" y on y."task_id" = x."id"
  where x."id" = list_task_specification.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false))
$$;
revoke execute on function "better_supabase"."list_task_specification"(uuid) from public, anon;
grant execute on function "better_supabase"."list_task_specification"(uuid) to authenticated, service_role;


-- Adds a materials line (the line id null) or changes one. A new line
-- without a rank goes after the last one. Needs tasks.write.
create or replace function "better_supabase"."save_task_material_line"(task uuid, line_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."tasks";
  v_id uuid := save_task_material_line.line_id;
  v_last text;
  v_line "better_supabase"."task_material_lines";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(save_task_material_line.attrs) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'TASK_LINE_INVALID';
  end if;
  select * into v_row from "better_supabase"."tasks" x
  where x."id" = save_task_material_line.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'work item not found' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if v_id is null then
    select max(y."rank") into v_last from "better_supabase"."task_material_lines" y where y."task_id" = v_row."id";
    insert into "better_supabase"."task_material_lines" ("tenant_id", "task_id", "variant_id", "quantity", "unit", "rank")
    values (v_row."tenant_id", v_row."id", nullif(save_task_material_line.attrs ->> 'variantId', '')::uuid, nullif(save_task_material_line.attrs ->> 'quantity', '')::numeric, nullif(btrim(save_task_material_line.attrs ->> 'unit'), ''), coalesce(nullif(save_task_material_line.attrs ->> 'rank', ''), case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end))
    returning * into v_line;
  else
    update "better_supabase"."task_material_lines" y set "variant_id" = coalesce(nullif(save_task_material_line.attrs ->> 'variantId', '')::uuid, "variant_id"), "quantity" = coalesce(nullif(save_task_material_line.attrs ->> 'quantity', '')::numeric, "quantity"), "unit" = case when save_task_material_line.attrs ? 'unit' then nullif(btrim(save_task_material_line.attrs ->> 'unit'), '') else "unit" end, "rank" = coalesce(nullif(save_task_material_line.attrs ->> 'rank', ''), "rank")
    where y."id" = v_id and y."task_id" = v_row."id"
    returning * into v_line;
    if v_line."id" is null then
      raise exception 'no such line on this work item' using errcode = '22023', hint = 'TASK_LINE_INVALID';
    end if;
  end if;
  return jsonb_build_object('id', v_line."id", 'taskId', v_line."task_id", 'rank', v_line."rank");
end;
$$;
revoke execute on function "better_supabase"."save_task_material_line"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_task_material_line"(uuid, uuid, jsonb) to authenticated, service_role;


-- The materials lines of one work item, in rank order. Needs tasks.read.
create or replace function "better_supabase"."list_task_materials"(task uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'taskId', y."task_id", 'variantId', y."variant_id", 'quantity', y."quantity", 'unit', y."unit", 'rank', y."rank") order by y."rank", y."id"), '[]'::jsonb)
  from "better_supabase"."tasks" x
  join "better_supabase"."task_material_lines" y on y."task_id" = x."id"
  where x."id" = list_task_materials.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false))
$$;
revoke execute on function "better_supabase"."list_task_materials"(uuid) from public, anon;
grant execute on function "better_supabase"."list_task_materials"(uuid) to authenticated, service_role;

create or replace function better_supabase.bsb_task_guard()
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
revoke execute on function better_supabase.bsb_task_guard() from public, anon, authenticated;
create trigger bsb_task_guard before insert or update on "better_supabase"."tasks"
for each row execute function better_supabase.bsb_task_guard();

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
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'task' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'task' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_task.tenant::text || ':task', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."tasks" x where x."tenant_id" = create_task.tenant;
  v_identifier := 'TASK-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."tasks" ("tenant_id", "number", "identifier", "title", "body", "parent_id", "team_id", "project_id", "iteration_id",
      "priority", "estimate", "progress", "start_at", "end_at", "due_at", "pipeline_id", "stage_id", "created_by", "app_note")
    values (create_task.tenant, v_seq, v_identifier, trim(create_task.attrs ->> 'title'), create_task.attrs ->> 'body',
      (create_task.attrs ->> 'parentId')::uuid, (create_task.attrs ->> 'teamId')::uuid, (create_task.attrs ->> 'projectId')::uuid,
      (create_task.attrs ->> 'iterationId')::uuid, coalesce((create_task.attrs ->> 'priority')::smallint, 0),
      (create_task.attrs ->> 'estimate')::numeric, (create_task.attrs ->> 'progress')::smallint,
      (create_task.attrs ->> 'startAt')::timestamptz, (create_task.attrs ->> 'endAt')::timestamptz, (create_task.attrs ->> 'dueAt')::timestamptz,
      (create_task.attrs ->> 'pipelineId')::uuid, (create_task.attrs ->> 'stageId')::uuid, auth.uid(), case when (create_task.attrs -> 'fields') ? 'app_note' then (jsonb_populate_record(null::"better_supabase"."tasks", jsonb_build_object('app_note', (create_task.attrs -> 'fields') -> 'app_note')))."app_note" else better_supabase.column_default('"better_supabase"."tasks"', 'app_note', (null::"better_supabase"."tasks")."app_note") end)
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  update "better_supabase"."tasks" x set "app_note" = case when (create_task.attrs -> 'fields') ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."tasks", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each((create_task.attrs -> 'fields')) e where e.key in ('app_note'))) r
  where x."id" = v_id;
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

-- Applies a batch of { taskId, field, value } changes, each on its
-- own. Returns { accepted: [{ taskId, field }], rejected: [{ taskId,
-- field, hint, reason }] }. With atomic, the first change that fails raises
-- its error and no change is kept. The window field ({ startAt, endAt })
-- writes both ends in one update, so the end-after-start check sees both.

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
  v_seen jsonb := '{}';
  v_was timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_tasks.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { taskId, field, value }' using errcode = '22023', hint = 'TASK_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_tasks.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'taskId')::uuid;
      if not exists (select 1 from "better_supabase"."tasks" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
      end if;
      -- expectedVersion is the updatedAt the caller read. Every change of the
      -- batch compares to the row as it was before the batch, which an earlier
      -- change of the same item has already moved on.
      if not v_seen ? v_item::text then
        select x."updated_at" into v_was from "better_supabase"."tasks" x where x."id" = v_item for update;
        v_seen := v_seen || jsonb_build_object(v_item::text, v_was);
      end if;
      if v_change ? 'expectedVersion' and (v_seen ->> v_item::text)::timestamptz is distinct from (v_change ->> 'expectedVersion')::timestamptz then
        raise exception 'the work item changed since it was read' using errcode = 'BS409', hint = 'STALE_WRITE';
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
      when 'app_note' then
        update "better_supabase"."tasks" x set "app_note" = (jsonb_populate_record(null::"better_supabase"."tasks", jsonb_build_object('app_note', v_change -> 'value')))."app_note" where x."id" = v_item;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'TASK_FIELD_UNKNOWN';
      end case;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('taskId', v_item, 'field', v_field));
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
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('taskId', v_change ->> 'taskId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
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
create or replace function "better_supabase"."set_task_assignees"(task uuid, users uuid[])
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
  select * into v_row from "better_supabase"."tasks" x where x."id" = set_task_assignees.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false));
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

create or replace function "better_supabase"."archive_task"(task uuid, archived boolean)
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
  where x."id" = archive_task.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false))
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

-- The set form of archive_task: one update for every id, so the access check
-- runs once per statement. Returns { ids, skipped }: skipped lists the ids
-- that don't exist or that you can't edit.
create or replace function "better_supabase"."archive_tasks"(ids uuid[], archived boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
  v_ids uuid[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  for v_row in
    with changed as (
      update "better_supabase"."tasks" x set "archived_at" = case when archive_tasks.archived then coalesce(x."archived_at", now()) end
      where x."id" = any (coalesce(archive_tasks.ids, '{}')) and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false))
      returning x.*
    )
    select * from changed
  loop
    v_ids := array_append(v_ids, v_row."id");
    if archive_tasks.archived then
      null;
    end if;
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(archive_tasks.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$$;
revoke execute on function "better_supabase"."archive_tasks"(uuid[], boolean) from public, anon;
grant execute on function "better_supabase"."archive_tasks"(uuid[], boolean) to authenticated, service_role;

-- Deletes an item and its children. Needs tasks.manage, or its author.
create or replace function "better_supabase"."delete_task"(task uuid)
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
  where x."id" = delete_task.task
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

-- The set form of delete_task: one delete, one access check per statement.
-- Returns { ids, skipped } like archive_tasks.
create or replace function "better_supabase"."delete_tasks"(ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tasks";
  v_ids uuid[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  for v_row in
    with removed as (
      delete from "better_supabase"."tasks" x
      where x."id" = any (coalesce(delete_tasks.ids, '{}'))
        and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.manage'), false))
      returning x.*
    )
    select * from removed
  loop
    v_ids := array_append(v_ids, v_row."id");
    null;
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(delete_tasks.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$$;
revoke execute on function "better_supabase"."delete_tasks"(uuid[]) from public, anon;
grant execute on function "better_supabase"."delete_tasks"(uuid[]) to authenticated, service_role;

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

-- Copies source into a new task. overrides replaces the fields the caller
-- edited. A template becomes a live task unless overrides.templateId is set.
create or replace function "better_supabase"."clone_task"(source uuid, overrides jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_src "better_supabase"."tasks"%rowtype;
  v_id uuid;
  v_created jsonb;
  v_child uuid;
  v_copy jsonb;
  v_users uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."tasks" x where x."id" = clone_task.source;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_src."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_task_clone"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using clone_task.source, clone_task.overrides;
    end if;
  end;
  select coalesce(array_agg(ra."user_id"), '{}') into v_users from "better_supabase"."task_assignees" ra where ra."task_id" = v_src."id";
  v_created := "better_supabase"."create_task"(v_src."tenant_id", jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title",
    'body', v_src."body",
    'parentId', v_src."parent_id",
    'teamId', v_src."team_id",
    'dueAt', v_src."due_at",
    'priority', v_src."priority",
    'templateId', null,
    'sourceTemplateId', null
  )) || (coalesce(clone_task.overrides, '{}'::jsonb) - 'templateId') || jsonb_strip_nulls(jsonb_build_object('templateId', null, 'sourceTemplateId', null)), v_users);
  v_id := (v_created ->> 'id')::uuid;
  insert into "better_supabase"."task_checklist_items" ("tenant_id", "task_id", "title", "done", "rank")
  select c."tenant_id", v_id, c."title", false, c."rank"
  from "better_supabase"."task_checklist_items" c where c."task_id" = clone_task.source;
  for v_child in select c."id" from "better_supabase"."tasks" c where c."parent_id" = clone_task.source loop
    v_copy := "better_supabase"."clone_task"(v_child, coalesce(clone_task.overrides, '{}'::jsonb) - 'templateId' - 'parentId');
    update "better_supabase"."tasks" x set "parent_id" = v_id where x."id" = (v_copy ->> 'id')::uuid;
  end loop;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_task_clone"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id")) from "better_supabase"."tasks" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."clone_task"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."clone_task"(uuid, jsonb) to authenticated, service_role;

-- Adds a checklist item (checklist_item null) or changes one: title, done,
-- rank. A new item without a rank goes last.
create or replace function "better_supabase"."save_task_checklist_item"(task uuid, checklist_item uuid, attrs jsonb)
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
  select * into v_row from "better_supabase"."tasks" x where x."id" = save_task_checklist_item.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
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
  return (select jsonb_build_object('id', y."id", 'taskId', y."task_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") from "better_supabase"."task_checklist_items" y where y."id" = v_id);
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
create or replace function "better_supabase"."list_task_checklist"(task uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'taskId', y."task_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") order by y."rank" collate "C", y."id"), '[]'::jsonb)
  from "better_supabase"."task_checklist_items" y where y."task_id" = list_task_checklist.task
$$;
revoke execute on function "better_supabase"."list_task_checklist"(uuid) from public, anon;
grant execute on function "better_supabase"."list_task_checklist"(uuid) to authenticated, service_role;

-- One item the caller can read, or null.
create or replace function "better_supabase"."get_task"(task uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."task_assignees" ra where ra."task_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."task_checklist_items" rk where rk."task_id" = x."id")) from "better_supabase"."tasks" x where x."id" = get_task.task
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
      insert into "better_supabase"."projects" ("tenant_id", "key", "name", "owner_id", "status", "start_on", "target_on", "budget_amount", "budget_currency", "budget_hours")
      values (save_project.tenant, upper(save_project.attrs ->> 'key'), save_project.attrs ->> 'name', (save_project.attrs ->> 'ownerId')::uuid,
        coalesce(save_project.attrs ->> 'status', 'planned'), (save_project.attrs ->> 'startOn')::date, (save_project.attrs ->> 'targetOn')::date,
        (save_project.attrs ->> 'budgetAmount')::bigint, upper(save_project.attrs ->> 'budgetCurrency'), (save_project.attrs ->> 'budgetHours')::numeric)
      returning "id" into v_id;
    else
      update "better_supabase"."projects" x set
        "key" = coalesce(upper(save_project.attrs ->> 'key'), x."key"),
        "name" = coalesce(save_project.attrs ->> 'name', x."name"),
        "owner_id" = case when save_project.attrs ? 'ownerId' then (save_project.attrs ->> 'ownerId')::uuid else x."owner_id" end,
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
create policy bsb_tenant_scope_select on "better_supabase"."tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."tasks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."task_specification_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."task_specification_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."task_specification_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."task_specification_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."task_material_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."task_material_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."task_material_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."task_material_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."task_checklist_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."task_checklist_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."task_checklist_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."task_checklist_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."task_assignees" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."task_assignees" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."task_assignees" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."task_assignees" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."projects" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."projects" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."projects" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."projects" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."iterations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."iterations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."iterations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."iterations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== data supabase/better-supabase-data/900_better_supabase_091_tasks.sql
-- better-supabase module: tasks
-- @bsb-block-data tasks
-- @bsb-hash sha256:30d4fdc921a2a04fab7a2e774ebaabc405d9c286090c292a5bcbc56b25540d84
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
