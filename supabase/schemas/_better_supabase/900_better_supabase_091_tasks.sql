-- better-supabase module: tasks
-- @bsb-block tasks@8 managed
-- @bsb-hash sha256:c991309a699a72c0453892948735b125a0497f5290fa343846e17cff6e1babf5
-- @bsb-names tasks task=work_item/work_items
-- Issues and tasks on pipelines: identifiers, parents without cycles, several assignees, priority 0 to 4, estimates, start, end and due dates, locking, projects, iterations, batched edits and a progress tree.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Work items on pipelines: issues and tasks with an identifier, a parent,
-- assignees, a priority, dates, projects and iterations.

create table "better_supabase"."work_projects" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null constraint bsb_work_projects_key_check check ("key" ~ '^[A-Z][A-Z0-9]{0,9}$'),
  "name" text not null constraint bsb_work_projects_name_check check (length("name") >= 1 and length("name") <= 200),
  "owner_id" uuid,
  "status" text not null default 'planned' constraint bsb_work_projects_status_check check ("status" in ('planned', 'active', 'paused', 'completed', 'canceled')),
  "start_on" date,
  "target_on" date,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  constraint bsb_work_projects_check check ("target_on" is null or "start_on" is null or "target_on" >= "start_on")
);
alter table "better_supabase"."work_projects" add column "budget_amount" bigint constraint bsb_work_projects_budget_amount_check check ("budget_amount" >= 0);
alter table "better_supabase"."work_projects" add column "budget_currency" text constraint bsb_work_projects_budget_currency_check check ("budget_currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."work_projects" add column "budget_hours" numeric(12, 2) constraint bsb_work_projects_budget_hours_check check ("budget_hours" >= 0);
alter table "better_supabase"."work_projects" enable row level security;
revoke all on "better_supabase"."work_projects" from public, anon, authenticated;
grant select on "better_supabase"."work_projects" to authenticated;
grant all on "better_supabase"."work_projects" to service_role;
create policy bsb_work_projects_read on "better_supabase"."work_projects"
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

create table "better_supabase"."work_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "title" text not null constraint bsb_work_items_title_check check (length("title") >= 1 and length("title") <= 500),
  "body" text,
  "parent_id" uuid references "better_supabase"."work_items" ("id") on delete cascade,
  "team_id" uuid,
  "project_id" uuid references "better_supabase"."work_projects" ("id") on delete set null,
  "iteration_id" uuid references "better_supabase"."iterations" ("id") on delete set null,
  "priority" smallint not null default 0 constraint bsb_work_items_priority_check check ("priority" >= 0 and "priority" <= 4),
  "estimate" numeric(10, 2) constraint bsb_work_items_estimate_check check ("estimate" >= 0),
  "estimated_minutes" integer constraint bsb_work_items_estimated_minutes_check check ("estimated_minutes" >= 0),
  "progress" smallint constraint bsb_work_items_progress_check check ("progress" >= 0 and "progress" <= 100),
  "start_at" timestamptz,
  "end_at" timestamptz,
  "due_at" timestamptz,
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  "state" text not null default 'backlog' constraint bsb_work_items_state_check check ("state" in ('triage', 'backlog', 'unstarted', 'started', 'completed', 'canceled')),
  "close_reason" text constraint bsb_work_items_close_reason_check check ("close_reason" in ('completed', 'not_planned', 'duplicate', 'failed')),
  "closed_at" timestamptz,
  "locked" boolean not null default false,
  "rank" text collate "C" not null default 'V',
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  constraint bsb_work_items_check check ("end_at" is null or "start_at" is null or "end_at" >= "start_at")
);
create index "work_items_board_idx" on "better_supabase"."work_items" ("pipeline_id", "stage_id", "rank");
create index "work_items_parent_idx" on "better_supabase"."work_items" ("parent_id");
create index "work_items_project_idx" on "better_supabase"."work_items" ("project_id");
create index "work_items_iteration_idx" on "better_supabase"."work_items" ("iteration_id");
create index "work_items_due_idx" on "better_supabase"."work_items" ("tenant_id", "due_at") where "closed_at" is null;
alter table "better_supabase"."work_items" enable row level security;
revoke all on "better_supabase"."work_items" from public, anon, authenticated;
grant select on "better_supabase"."work_items" to authenticated;
grant all on "better_supabase"."work_items" to service_role;
create policy bsb_work_items_read on "better_supabase"."work_items"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table "better_supabase"."work_item_assignees" (
  "tenant_id" uuid not null,
  "work_item_id" uuid not null references "better_supabase"."work_items" ("id") on delete cascade,
  "user_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("work_item_id", "user_id")
);
create index "work_item_assignees_user_idx" on "better_supabase"."work_item_assignees" ("user_id");
alter table "better_supabase"."work_item_assignees" enable row level security;
revoke all on "better_supabase"."work_item_assignees" from public, anon, authenticated;
grant select on "better_supabase"."work_item_assignees" to authenticated;
grant all on "better_supabase"."work_item_assignees" to service_role;
create policy bsb_work_item_assignees_read on "better_supabase"."work_item_assignees"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

alter table "better_supabase"."work_items" add column "recurs_from" uuid references "better_supabase"."work_items" ("id") on delete set null;
create unique index "work_items_recurs_from_idx" on "better_supabase"."work_items" ("recurs_from");

create table "better_supabase"."work_item_checklist_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "work_item_id" uuid not null references "better_supabase"."work_items" ("id") on delete cascade,
  "title" text not null constraint bsb_work_item_checklist_items_title_check check (length("title") >= 1 and length("title") <= 500),
  "done" boolean not null default false,
  "done_at" timestamptz,
  "done_by" uuid,
  "rank" text collate "C" not null constraint bsb_work_item_checklist_items_rank_check check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
create index "work_item_checklist_item_idx" on "better_supabase"."work_item_checklist_items" ("work_item_id", "rank");
alter table "better_supabase"."work_item_checklist_items" enable row level security;
revoke all on "better_supabase"."work_item_checklist_items" from public, anon, authenticated;
grant select on "better_supabase"."work_item_checklist_items" to authenticated;
grant all on "better_supabase"."work_item_checklist_items" to service_role;
create policy bsb_work_item_checklist_items_read on "better_supabase"."work_item_checklist_items"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));


create table "better_supabase"."work_item_specification_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "work_item_id" uuid not null references "better_supabase"."work_items" ("id") on delete cascade,
  "description" text not null constraint bsb_work_item_specification_lines_description_check check (char_length("description") >= 1 and char_length("description") <= 500),
  "quantity" numeric(12, 3) constraint bsb_work_item_specification_lines_quantity_check check ("quantity" >= 0),
  "unit" text constraint bsb_work_item_specification_lines_unit_check check (char_length("unit") >= 1 and char_length("unit") <= 30),
  "estimate" numeric(10, 2) constraint bsb_work_item_specification_lines_estimate_check check ("estimate" >= 0),
  "rank" text collate "C" not null constraint bsb_work_item_specification_lines_rank_check check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_at" timestamptz not null default now()
);
create index "bsb_work_item_specification_lines_item_idx" on "better_supabase"."work_item_specification_lines" ("work_item_id", "rank");
alter table "better_supabase"."work_item_specification_lines" enable row level security;
revoke all on "better_supabase"."work_item_specification_lines" from public, anon, authenticated;
grant select on "better_supabase"."work_item_specification_lines" to authenticated;
grant all on "better_supabase"."work_item_specification_lines" to service_role;
create policy bsb_work_item_specification_lines_read on "better_supabase"."work_item_specification_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));

create table "better_supabase"."work_item_material_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "work_item_id" uuid not null references "better_supabase"."work_items" ("id") on delete cascade,
  "variant_id" uuid references "better_supabase"."product_variants" ("id") on delete set null,
  "quantity" numeric(12, 3) not null constraint bsb_work_item_material_lines_quantity_check check ("quantity" >= 0),
  "unit" text constraint bsb_work_item_material_lines_unit_check check (char_length("unit") >= 1 and char_length("unit") <= 30),
  "rank" text collate "C" not null constraint bsb_work_item_material_lines_rank_check check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_at" timestamptz not null default now()
);
create index "bsb_work_item_material_lines_item_idx" on "better_supabase"."work_item_material_lines" ("work_item_id", "rank");
create index "bsb_work_item_material_lines_variant_idx" on "better_supabase"."work_item_material_lines" ("variant_id") where "variant_id" is not null;
alter table "better_supabase"."work_item_material_lines" enable row level security;
revoke all on "better_supabase"."work_item_material_lines" from public, anon, authenticated;
grant select on "better_supabase"."work_item_material_lines" to authenticated;
grant all on "better_supabase"."work_item_material_lines" to service_role;
create policy bsb_work_item_material_lines_read on "better_supabase"."work_item_material_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')));


-- Adds a specification line (the line id null) or changes one. A new line
-- without a rank goes after the last one. Needs tasks.write.
create or replace function "better_supabase"."save_work_item_specification_line"(task uuid, line_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."work_items";
  v_id uuid := save_work_item_specification_line.line_id;
  v_last text;
  v_line "better_supabase"."work_item_specification_lines";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(save_work_item_specification_line.attrs) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'TASK_LINE_INVALID';
  end if;
  select * into v_row from "better_supabase"."work_items" x
  where x."id" = save_work_item_specification_line.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'work item not found' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if v_id is null then
    select max(y."rank") into v_last from "better_supabase"."work_item_specification_lines" y where y."work_item_id" = v_row."id";
    insert into "better_supabase"."work_item_specification_lines" ("tenant_id", "work_item_id", "description", "quantity", "unit", "estimate", "rank")
    values (v_row."tenant_id", v_row."id", nullif(btrim(save_work_item_specification_line.attrs ->> 'description'), ''), nullif(save_work_item_specification_line.attrs ->> 'quantity', '')::numeric, nullif(btrim(save_work_item_specification_line.attrs ->> 'unit'), ''), nullif(save_work_item_specification_line.attrs ->> 'estimate', '')::numeric, coalesce(nullif(save_work_item_specification_line.attrs ->> 'rank', ''), case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end))
    returning * into v_line;
  else
    update "better_supabase"."work_item_specification_lines" y set "description" = coalesce(nullif(btrim(save_work_item_specification_line.attrs ->> 'description'), ''), "description"), "quantity" = coalesce(nullif(save_work_item_specification_line.attrs ->> 'quantity', '')::numeric, "quantity"), "unit" = case when save_work_item_specification_line.attrs ? 'unit' then nullif(btrim(save_work_item_specification_line.attrs ->> 'unit'), '') else "unit" end, "estimate" = case when save_work_item_specification_line.attrs ? 'estimate' then nullif(save_work_item_specification_line.attrs ->> 'estimate', '')::numeric else "estimate" end, "rank" = coalesce(nullif(save_work_item_specification_line.attrs ->> 'rank', ''), "rank")
    where y."id" = v_id and y."work_item_id" = v_row."id"
    returning * into v_line;
    if v_line."id" is null then
      raise exception 'no such line on this work item' using errcode = '22023', hint = 'TASK_LINE_INVALID';
    end if;
  end if;
  return jsonb_build_object('id', v_line."id", 'taskId', v_line."work_item_id", 'rank', v_line."rank");
end;
$$;
revoke execute on function "better_supabase"."save_work_item_specification_line"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_work_item_specification_line"(uuid, uuid, jsonb) to authenticated, service_role;


-- The specification lines of one work item, in rank order. Needs tasks.read.
create or replace function "better_supabase"."list_work_item_specification"(task uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'taskId', y."work_item_id", 'description', y."description", 'quantity', y."quantity", 'unit', y."unit", 'estimate', y."estimate", 'rank', y."rank") order by y."rank", y."id"), '[]'::jsonb)
  from "better_supabase"."work_items" x
  join "better_supabase"."work_item_specification_lines" y on y."work_item_id" = x."id"
  where x."id" = list_work_item_specification.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false))
$$;
revoke execute on function "better_supabase"."list_work_item_specification"(uuid) from public, anon;
grant execute on function "better_supabase"."list_work_item_specification"(uuid) to authenticated, service_role;


-- Adds a materials line (the line id null) or changes one. A new line
-- without a rank goes after the last one. Needs tasks.write.
create or replace function "better_supabase"."save_work_item_material_line"(task uuid, line_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."work_items";
  v_id uuid := save_work_item_material_line.line_id;
  v_last text;
  v_line "better_supabase"."work_item_material_lines";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(save_work_item_material_line.attrs) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'TASK_LINE_INVALID';
  end if;
  select * into v_row from "better_supabase"."work_items" x
  where x."id" = save_work_item_material_line.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'work item not found' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if v_id is null then
    select max(y."rank") into v_last from "better_supabase"."work_item_material_lines" y where y."work_item_id" = v_row."id";
    insert into "better_supabase"."work_item_material_lines" ("tenant_id", "work_item_id", "variant_id", "quantity", "unit", "rank")
    values (v_row."tenant_id", v_row."id", nullif(save_work_item_material_line.attrs ->> 'variantId', '')::uuid, nullif(save_work_item_material_line.attrs ->> 'quantity', '')::numeric, nullif(btrim(save_work_item_material_line.attrs ->> 'unit'), ''), coalesce(nullif(save_work_item_material_line.attrs ->> 'rank', ''), case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end))
    returning * into v_line;
  else
    update "better_supabase"."work_item_material_lines" y set "variant_id" = coalesce(nullif(save_work_item_material_line.attrs ->> 'variantId', '')::uuid, "variant_id"), "quantity" = coalesce(nullif(save_work_item_material_line.attrs ->> 'quantity', '')::numeric, "quantity"), "unit" = case when save_work_item_material_line.attrs ? 'unit' then nullif(btrim(save_work_item_material_line.attrs ->> 'unit'), '') else "unit" end, "rank" = coalesce(nullif(save_work_item_material_line.attrs ->> 'rank', ''), "rank")
    where y."id" = v_id and y."work_item_id" = v_row."id"
    returning * into v_line;
    if v_line."id" is null then
      raise exception 'no such line on this work item' using errcode = '22023', hint = 'TASK_LINE_INVALID';
    end if;
  end if;
  return jsonb_build_object('id', v_line."id", 'taskId', v_line."work_item_id", 'rank', v_line."rank");
end;
$$;
revoke execute on function "better_supabase"."save_work_item_material_line"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_work_item_material_line"(uuid, uuid, jsonb) to authenticated, service_role;


-- The materials lines of one work item, in rank order. Needs tasks.read.
create or replace function "better_supabase"."list_work_item_materials"(task uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'taskId', y."work_item_id", 'variantId', y."variant_id", 'quantity', y."quantity", 'unit', y."unit", 'rank', y."rank") order by y."rank", y."id"), '[]'::jsonb)
  from "better_supabase"."work_items" x
  join "better_supabase"."work_item_material_lines" y on y."work_item_id" = x."id"
  where x."id" = list_work_item_materials.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false))
$$;
revoke execute on function "better_supabase"."list_work_item_materials"(uuid) from public, anon;
grant execute on function "better_supabase"."list_work_item_materials"(uuid) to authenticated, service_role;

alter table "better_supabase"."work_items" add column "waiting_on" integer not null default 0 constraint bsb_work_items_waiting_on_check check ("waiting_on" >= 0);
alter table "better_supabase"."work_items" add column "held_at" timestamptz;
alter table "better_supabase"."work_items" add column "hold_kind" text;
alter table "better_supabase"."work_items" add column "hold_return_stage_id" uuid;
alter table "better_supabase"."work_items" add column "delegate_profile" jsonb;
alter table "better_supabase"."work_items" add column "close_note" text;
create index work_items_ready_idx on "better_supabase"."work_items" ("tenant_id", "number") where "waiting_on" = 0 and "closed_at" is null;
create table "better_supabase"."work_item_claims" (
  "work_item_id" uuid not null references "better_supabase"."work_items" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "token" uuid not null default gen_random_uuid(),
  "epoch" bigint not null default 1,
  "holder_id" uuid,
  "profile" jsonb,
  "claimed_at" timestamptz not null default now(),
  "expires_at" timestamptz not null,
  "expired_at" timestamptz
);
create unique index work_item_claims_unique_idx on "better_supabase"."work_item_claims" ("work_item_id");
create index work_item_claims_expires_idx on "better_supabase"."work_item_claims" ("expires_at");
create index work_item_claims_tenant_idx on "better_supabase"."work_item_claims" ("tenant_id", "holder_id");
-- The token is a secret, so the table has no read policy: the functions read it.
alter table "better_supabase"."work_item_claims" enable row level security;
revoke all on "better_supabase"."work_item_claims" from public, anon, authenticated;
grant all on "better_supabase"."work_item_claims" to service_role;
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
        select x."parent_id", up.depth + 1 from "better_supabase"."work_items" x join up on x."id" = up.id
        where x."parent_id" is not null and up.depth < 100
      )
      select 1 from up where up.id = new."id"
    ) then
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'TASK_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "better_supabase"."work_items" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
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
      new."close_note" := coalesce(nullif(current_setting('bsb.close_note', true), ''), new."close_note");
      new."held_at" := null;
      new."hold_kind" := null;
      new."hold_return_stage_id" := null;
      delete from "better_supabase"."work_item_claims" c where c."work_item_id" = new."id";
      new."delegate_profile" := null;
      if new."state" = 'completed' and new."progress" is not null then
        new."progress" := 100;
      end if;
      perform "better_supabase".emit_event('work_item.closed', jsonb_build_object('organizationId', new."tenant_id", 'workItemId', new."id", 'subjectType', 'work_item', 'subjectId', new."id"::text, 'title', new."title", 'state', new."state", 'closeReason', new."close_reason", 'note', coalesce(nullif(current_setting('bsb.close_note', true), ''), new."close_note"), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/tasks');
    elsif not (new."state" in ('completed', 'canceled')) and old."state" in ('completed', 'canceled') then
      new."closed_at" := null;
      new."close_reason" := null;
      new."close_note" := null;
      perform "better_supabase".emit_event('work_item.reopened', jsonb_build_object('organizationId', new."tenant_id", 'workItemId', new."id", 'subjectType', 'work_item', 'subjectId', new."id"::text, 'title', new."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/tasks');
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_work_item_guard() from public, anon, authenticated;
create trigger bsb_work_item_guard before insert or update on "better_supabase"."work_items"
for each row execute function better_supabase.bsb_work_item_guard();

create or replace function better_supabase.bsb_work_item_close_hook()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_close"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using new."id", case new."close_reason"::text when 'completed' then 'completed' when 'failed' then 'failed' else 'canceled' end, coalesce(nullif(current_setting('bsb.close_note', true), ''), new."close_note");
    end if;
  end;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_work_item_close_hook() from public, anon, authenticated;
create trigger bsb_work_item_close_hook after update on "better_supabase"."work_items"
for each row when (old."closed_at" is null and new."closed_at" is not null)
execute function better_supabase.bsb_work_item_close_hook();

-- The public part of a task's live claim: who holds it and until when. The
-- token stays out.
create or replace function "better_supabase"."work_item_claim"(task uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('epoch', c."epoch", 'holderId', c."holder_id", 'profile', c."profile", 'claimedAt', c."claimed_at", 'expiresAt', c."expires_at")
  from "better_supabase"."work_item_claims" c
  where c."work_item_id" = work_item_claim.task and c."expires_at" > now()
    and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', c."tenant_id", 'tasks.read'), false))
$$;
revoke execute on function "better_supabase"."work_item_claim"(uuid) from public, anon;
grant execute on function "better_supabase"."work_item_claim"(uuid) to authenticated, service_role;

-- Creates a work item. attrs: title (required), body, parentId, teamId,
-- projectId, iterationId, priority (0 none to 4 low, as Linear), estimate,
-- progress, startAt, endAt, dueAt, pipelineId, stageId, and fields (the
-- extra columns, by name). assignees: user ids.
create or replace function "better_supabase"."create_work_item"(tenant uuid, attrs jsonb, assignees uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seq bigint;
  v_identifier text;
  v_id uuid;
  v_row "better_supabase"."work_items";
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_work_item.tenant, 'tasks.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if nullif(trim(create_work_item.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'TASK_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_work_item.tenant, create_work_item.attrs;
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
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_work_item.tenant::text || ':work_item', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."work_items" x where x."tenant_id" = create_work_item.tenant;
  v_identifier := 'TASK-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."work_items" ("tenant_id", "number", "identifier", "title", "body", "parent_id", "team_id", "project_id", "iteration_id",
      "priority", "estimate", "progress", "start_at", "end_at", "due_at", "pipeline_id", "stage_id", "created_by")
    values (create_work_item.tenant, v_seq, v_identifier, trim(create_work_item.attrs ->> 'title'), create_work_item.attrs ->> 'body',
      (create_work_item.attrs ->> 'parentId')::uuid, (create_work_item.attrs ->> 'teamId')::uuid, (create_work_item.attrs ->> 'projectId')::uuid,
      (create_work_item.attrs ->> 'iterationId')::uuid, coalesce((create_work_item.attrs ->> 'priority')::smallint, 0),
      (create_work_item.attrs ->> 'estimate')::numeric, (create_work_item.attrs ->> 'progress')::smallint,
      (create_work_item.attrs ->> 'startAt')::timestamptz, (create_work_item.attrs ->> 'endAt')::timestamptz, (create_work_item.attrs ->> 'dueAt')::timestamptz,
      (create_work_item.attrs ->> 'pipelineId')::uuid, (create_work_item.attrs ->> 'stageId')::uuid, auth.uid())
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  if cardinality(coalesce(create_work_item.assignees, '{}')) > 0 then
    perform "better_supabase"."set_work_item_assignees"(v_id, create_work_item.assignees);
  end if;
  update "better_supabase"."work_items" x set "rank" = "better_supabase"."rank_between"((select max(y."rank" collate "C") from "better_supabase"."work_items" y where y."tenant_id" = x."tenant_id" and y."stage_id" is not distinct from x."stage_id" and y."archived_at" is null and y."id" <> x."id"), null)
  where x."id" = v_id and x."stage_id" is not null;
  if jsonb_typeof(create_work_item.attrs -> 'needs') = 'array' and jsonb_array_length(create_work_item.attrs -> 'needs') > 0 then
    perform "better_supabase"."set_work_item_needs"(v_id, array(select x::uuid from jsonb_array_elements_text(create_work_item.attrs -> 'needs') x));
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = v_id;
  if jsonb_typeof(coalesce((create_work_item.attrs -> 'attachments'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((create_work_item.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'work_item', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((create_work_item.attrs -> 'attachments'))::uuid))
        and f."tenant_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'work_item' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((create_work_item.attrs -> 'attachments')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
      end if;
    end if;
  perform "better_supabase".emit_event('work_item.created', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_work_item_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_work_item"(uuid, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."create_work_item"(uuid, jsonb, uuid[]) to authenticated, service_role;

-- Applies a batch of { taskId, field, value } changes, each on its
-- own. Returns { accepted: [{ taskId, field }], rejected: [{ taskId,
-- field, hint, reason }] }. With atomic, the first change that fails raises
-- its error and no change is kept. The window field ({ startAt, endAt })
-- writes both ends in one update, so the end-after-start check sees both.

create or replace function "better_supabase"."update_work_items"(changes jsonb, atomic boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_item uuid;
  v_field text;
  v_row "better_supabase"."work_items";
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
  if jsonb_typeof(coalesce(update_work_items.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { workItemId, field, value }' using errcode = '22023', hint = 'TASK_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_work_items.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'workItemId')::uuid;
      if not exists (select 1 from "better_supabase"."work_items" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
      end if;
      -- expectedVersion is the updatedAt the caller read. Every change of the
      -- batch compares to the row as it was before the batch, which an earlier
      -- change of the same item has already moved on.
      if not v_seen ? v_item::text then
        select x."updated_at" into v_was from "better_supabase"."work_items" x where x."id" = v_item for update;
        v_seen := v_seen || jsonb_build_object(v_item::text, v_was);
      end if;
      if v_change ? 'expectedVersion' and (v_seen ->> v_item::text)::timestamptz is distinct from (v_change ->> 'expectedVersion')::timestamptz then
        raise exception 'the work item changed since it was read' using errcode = 'BS409', hint = 'STALE_WRITE';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_item, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'title' then
        update "better_supabase"."work_items" x set "title" = trim(v_change -> 'value' #>> '{}') where x."id" = v_item;
      when 'body' then
        update "better_supabase"."work_items" x set "body" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'parentId' then
        update "better_supabase"."work_items" x set "parent_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'teamId' then
        update "better_supabase"."work_items" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'projectId' then
        update "better_supabase"."work_items" x set "project_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'iterationId' then
        update "better_supabase"."work_items" x set "iteration_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'priority' then
        update "better_supabase"."work_items" x set "priority" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'estimate' then
        update "better_supabase"."work_items" x set "estimate" = (v_change -> 'value' #>> '{}')::numeric where x."id" = v_item;
      when 'progress' then
        update "better_supabase"."work_items" x set "progress" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'startAt' then
        update "better_supabase"."work_items" x set "start_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'endAt' then
        update "better_supabase"."work_items" x set "end_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'dueAt' then
        update "better_supabase"."work_items" x set "due_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'stageId' then
        update "better_supabase"."work_items" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'closeReason' then
        update "better_supabase"."work_items" x set "close_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'window' then
        if jsonb_typeof(v_change -> 'value') <> 'object' then
          raise exception 'window must be an object of startAt and endAt' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
        end if;
        update "better_supabase"."work_items" x set
          "start_at" = case when v_change -> 'value' ? 'startAt' then (v_change -> 'value' ->> 'startAt')::timestamptz else x."start_at" end,
          "end_at" = case when v_change -> 'value' ? 'endAt' then (v_change -> 'value' ->> 'endAt')::timestamptz else x."end_at" end
        where x."id" = v_item;
      when 'attachments' then
        select * into v_row from "better_supabase"."work_items" x where x."id" = v_item;
        if jsonb_typeof(coalesce((v_change -> 'value'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'work_item', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((v_change -> 'value'))::uuid))
        and f."tenant_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'work_item' and f."subject_id" = v_row."id"::text))
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
    v_hook regprocedure := to_regprocedure('"public"."after_work_item_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_item, v_field;
    end if;
  end;
    exception when others then
      if update_work_items.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_change ->> 'workItemId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."work_items" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'workItemId')::uuid = v_row."id"), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "better_supabase"."update_work_items"(jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."update_work_items"(jsonb, boolean) to authenticated, service_role;

-- Replaces an item's assignees. Each one watches the item, and those who
-- weren't assigned before are notified. task.assigned is recorded only
-- when the call adds someone, with addedIds.
create or replace function "better_supabase"."set_work_item_assignees"(task uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_work_item_assignees.users, '{}')) x where x is not null);
  v_added uuid[];
  v_new uuid[];
  v_claims text;
  v_user uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = set_work_item_assignees.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and y."user_id" = x));
  v_added := array(select x from unnest(v_users) x where not exists (
    select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."work_item_assignees" ("tenant_id", "work_item_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  foreach v_user in array v_users loop
    insert into "better_supabase"."notification_subscriptions" ("tenant_id", "user_id", "subject_type", "subject_id", "level")
    values (v_row."tenant_id", v_user, 'work_item', v_row."id"::text, 'participating')
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
      'subject_type', 'work_item',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."title",
      'summary', v_row."title",
      'action_path', null,
      'recipients', to_jsonb(v_new),
      'watchers', false,
      'key', 'work_item.assigned:' || v_row."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('workItemId', v_row."id")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if cardinality(v_added) > 0 then
    perform "better_supabase".emit_event('work_item.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(v_users), 'addedIds', to_jsonb(v_added), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return cardinality(v_users);
end;
$$;
revoke execute on function "better_supabase"."set_work_item_assignees"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."set_work_item_assignees"(uuid, uuid[]) to authenticated, service_role;

create or replace function "better_supabase"."archive_work_item"(task uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
  v_was timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."archived_at" into v_was from "better_supabase"."work_items" x where x."id" = archive_work_item.task;
  update "better_supabase"."work_items" x set "archived_at" = case when archive_work_item.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_work_item.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_work_item.archived then
    perform "better_supabase".emit_event('work_item.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  elsif v_was is not null then
    perform "better_supabase".emit_event('work_item.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_work_item"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_work_item"(uuid, boolean) to authenticated, service_role;

-- The set form of archive_task: one update for every id, so the access check
-- runs once per statement. Returns { ids, skipped }: skipped lists the ids
-- that don't exist or that you can't edit.
create or replace function "better_supabase"."archive_work_items"(ids uuid[], archived boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
  v_ids uuid[] := '{}';
  v_was uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select coalesce(array_agg(x."id"), '{}') into v_was from "better_supabase"."work_items" x
  where x."id" = any (coalesce(archive_work_items.ids, '{}')) and x."archived_at" is not null;
  for v_row in
    with changed as (
      update "better_supabase"."work_items" x set "archived_at" = case when archive_work_items.archived then coalesce(x."archived_at", now()) end
      where x."id" = any (coalesce(archive_work_items.ids, '{}')) and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false))
      returning x.*
    )
    select * from changed
  loop
    v_ids := array_append(v_ids, v_row."id");
    if archive_work_items.archived then
      perform "better_supabase".emit_event('work_item.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
    elsif v_row."id" = any (v_was) then
      perform "better_supabase".emit_event('work_item.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
    end if;
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(archive_work_items.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$$;
revoke execute on function "better_supabase"."archive_work_items"(uuid[], boolean) from public, anon;
grant execute on function "better_supabase"."archive_work_items"(uuid[], boolean) to authenticated, service_role;

-- Deletes an item and its children. Needs tasks.manage, or its author.
create or replace function "better_supabase"."delete_work_item"(task uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."work_items" x
  where x."id" = delete_work_item.task
    and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  perform "better_supabase".emit_event('work_item.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_work_item"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_work_item"(uuid) to authenticated, service_role;

-- The set form of delete_task: one delete, one access check per statement.
-- Returns { ids, skipped } like archive_tasks.
create or replace function "better_supabase"."delete_work_items"(ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
  v_ids uuid[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  for v_row in
    with removed as (
      delete from "better_supabase"."work_items" x
      where x."id" = any (coalesce(delete_work_items.ids, '{}'))
        and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.manage'), false))
      returning x.*
    )
    select * from removed
  loop
    v_ids := array_append(v_ids, v_row."id");
    perform "better_supabase".emit_event('work_item.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(delete_work_items.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$$;
revoke execute on function "better_supabase"."delete_work_items"(uuid[]) from public, anon;
grant execute on function "better_supabase"."delete_work_items"(uuid[]) to authenticated, service_role;

-- An item and everything under it with its depth. An item without its own
-- progress takes the share of its open and completed children that are
-- completed, so a Gantt group shows a rollup.
create or replace function "better_supabase"."work_item_tree"(root uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with recursive tree as (
    select x.*, 0 as depth from "better_supabase"."work_items" x where x."id" = work_item_tree.root
    union all
    select y.*, tree.depth + 1 from "better_supabase"."work_items" y join tree on y."parent_id" = tree."id"
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
      from "better_supabase"."work_items" ch where ch."parent_id" = tree."id" and ch."archived_at" is null))
  ) order by tree.depth, tree."rank" collate "C", tree."id"), '[]'::jsonb)
  from tree
$$;
revoke execute on function "better_supabase"."work_item_tree"(uuid) from public, anon;
grant execute on function "better_supabase"."work_item_tree"(uuid) to authenticated, service_role;

-- A page of a tenant's active items, newest first. filter keys: teamId,
-- projectId, iterationId, parentId, assigneeId, states (a list), open
-- (only unclosed). search matches the title and identifier. after continues
-- after that item.
create or replace function "better_supabase"."list_work_items"(tenant uuid, filter jsonb, search text, after uuid, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.number desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as value, x."number" as number
    from "better_supabase"."work_items" x
    where x."tenant_id" = list_work_items.tenant and x."archived_at" is null
      and (list_work_items.filter ->> 'teamId' is null or x."team_id" = (list_work_items.filter ->> 'teamId')::uuid)
      and (list_work_items.filter ->> 'projectId' is null or x."project_id" = (list_work_items.filter ->> 'projectId')::uuid)
      and (list_work_items.filter ->> 'iterationId' is null or x."iteration_id" = (list_work_items.filter ->> 'iterationId')::uuid)
      and (list_work_items.filter ->> 'parentId' is null or x."parent_id" = (list_work_items.filter ->> 'parentId')::uuid)
      and (list_work_items.filter ->> 'assigneeId' is null or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and y."user_id" = (list_work_items.filter ->> 'assigneeId')::uuid))
      and (list_work_items.filter -> 'states' is null or x."state" = any (array(select jsonb_array_elements_text(list_work_items.filter -> 'states'))))
      and (coalesce((list_work_items.filter ->> 'open')::boolean, false) = false or x."closed_at" is null)
      and (coalesce((list_work_items.filter ->> 'ready')::boolean, false) = false or (x."waiting_on" = 0 and x."closed_at" is null))
      and (list_work_items.search is null or x."title" ilike '%' || list_work_items.search || '%' or x."identifier" ilike list_work_items.search || '%')
      and (list_work_items.after is null or x."number" < (select z."number" from "better_supabase"."work_items" z where z."id" = list_work_items.after))
    order by x."number" desc
    limit least(greatest(coalesce(list_work_items.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."list_work_items"(uuid, jsonb, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_work_items"(uuid, jsonb, text, uuid, integer) to authenticated, service_role;


-- A tenant's active items as a keyset page, newest number first (ADR 1077). It
-- runs as invoker, so the read policy decides which items are visible. filters
-- is { state, priority, teamId, projectId, iterationId, parentId, assigneeId
-- (each a value or a list), open (true keeps unclosed items), templates
-- (include, only), search (title, identifier), sort (number, title, dueAt,
-- createdAt), direction, facet, count, limit, after, offset, paged, total,
-- totalCap }.
create or replace function "better_supabase"."page_work_items"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_work_items.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('state', 'priority') then
      raise exception 'facet is one of state, priority' using errcode = '22023', hint = 'TASK_INVALID';
    end if;
    with s as (
      select (case v_facet when 'state' then (x."state")::text when 'priority' then (x."priority"::text)::text end) as v
      from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
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
      select 1 from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('number', 'title', 'dueAt', 'createdAt') then
    raise exception 'sort is one of number, title, dueAt, createdAt' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."number" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number" <= (v_after ->> 0)::bigint and ((x."number" < (v_after ->> 0)::bigint) or (x."number" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."number" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."number" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number" <= (v_after ->> 0)::bigint and ((x."number" < (v_after ->> 0)::bigint) or (x."number" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."number" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((coalesce(x."due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (coalesce(x."due_at", 'infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."due_at", 'infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((coalesce(x."due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (coalesce(x."due_at", 'infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."due_at", 'infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."due_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."due_at", 'infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_work_items"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_work_items"(uuid, jsonb) to authenticated, service_role;

-- Copies source into a new task. overrides replaces the fields the caller
-- edited. A template becomes a live task unless overrides.templateId is set.
create or replace function "better_supabase"."clone_work_item"(source uuid, overrides jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_src "better_supabase"."work_items"%rowtype;
  v_id uuid;
  v_created jsonb;
  v_child uuid;
  v_copy jsonb;
  v_users uuid[];
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."work_items" x where x."id" = clone_work_item.source;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_tenant := coalesce(nullif(coalesce(clone_work_item.overrides, '{}'::jsonb) ->> 'tenantId', '')::uuid, v_src."tenant_id");
  if v_tenant is distinct from v_src."tenant_id" and not ((auth.role() = 'service_role') or false) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_tenant, 'tasks.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_clone"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using clone_work_item.source, clone_work_item.overrides;
    end if;
  end;
  select coalesce(array_agg(ra."user_id"), '{}') into v_users from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = v_src."id";
  v_created := "better_supabase"."create_work_item"(v_tenant, jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title",
    'body', v_src."body",
    'parentId', v_src."parent_id",
    'teamId', v_src."team_id",
    'dueAt', v_src."due_at",
    'priority', v_src."priority",
    'templateId', null,
    'sourceTemplateId', null
  )) || (coalesce(clone_work_item.overrides, '{}'::jsonb) - 'templateId') || jsonb_strip_nulls(jsonb_build_object('templateId', null, 'sourceTemplateId', null)), v_users);
  v_id := (v_created ->> 'id')::uuid;
  insert into "better_supabase"."work_item_checklist_items" ("tenant_id", "work_item_id", "title", "done", "rank")
  select v_tenant, v_id, c."title", false, c."rank"
  from "better_supabase"."work_item_checklist_items" c where c."work_item_id" = clone_work_item.source;
  insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
  select v_tenant, g."tag_id", g."subject_type", v_id::text
  from "better_supabase"."taggings" g
  where g."subject_type" = 'work_item' and g."subject_id" = clone_work_item.source::text;
  for v_child in select c."id" from "better_supabase"."work_items" c where c."parent_id" = clone_work_item.source loop
    v_copy := "better_supabase"."clone_work_item"(v_child, coalesce(clone_work_item.overrides, '{}'::jsonb) - 'templateId' - 'parentId');
    update "better_supabase"."work_items" x set "parent_id" = v_id where x."id" = (v_copy ->> 'id')::uuid;
  end loop;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_work_item_clone"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."clone_work_item"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."clone_work_item"(uuid, jsonb) to authenticated, service_role;

-- Adds a checklist item (checklist_item null) or changes one: title, done,
-- rank. A new item without a rank goes last.
create or replace function "better_supabase"."save_work_item_checklist_item"(task uuid, checklist_item uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
  v_id uuid := save_work_item_checklist_item.checklist_item;
  v_last text;
  v_done boolean := (save_work_item_checklist_item.attrs ->> 'done')::boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = save_work_item_checklist_item.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  begin
    if v_id is null then
      select max(y."rank") into v_last from "better_supabase"."work_item_checklist_items" y where y."work_item_id" = v_row."id";
      insert into "better_supabase"."work_item_checklist_items" ("tenant_id", "work_item_id", "title", "done", "done_at", "done_by", "rank", "created_by")
      values (v_row."tenant_id", v_row."id", trim(save_work_item_checklist_item.attrs ->> 'title'), coalesce(v_done, false),
        case when v_done then now() end, case when v_done then auth.uid() end,
        coalesce(save_work_item_checklist_item.attrs ->> 'rank', case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end), auth.uid())
      returning "id" into v_id;
    else
      update "better_supabase"."work_item_checklist_items" y set
        "title" = coalesce(trim(save_work_item_checklist_item.attrs ->> 'title'), y."title"),
        "rank" = coalesce(save_work_item_checklist_item.attrs ->> 'rank', y."rank"),
        "done" = coalesce(v_done, y."done"),
        "done_at" = case when v_done is null then y."done_at" when v_done then coalesce(y."done_at", now()) end,
        "done_by" = case when v_done is null then y."done_by" when v_done then coalesce(y."done_by", auth.uid()) end
      where y."id" = v_id and y."work_item_id" = v_row."id";
      if not found then
        raise exception 'no such checklist item on this work item' using errcode = 'P0002', hint = 'TASK_CHECKLIST_ITEM_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a checklist item needs a title of 1 to 500 characters and a valid rank' using errcode = '22023', hint = 'TASK_CHECKLIST_ITEM_INVALID';
  end;
  perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist'), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select jsonb_build_object('id', y."id", 'workItemId', y."work_item_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") from "better_supabase"."work_item_checklist_items" y where y."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_work_item_checklist_item"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_work_item_checklist_item"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_work_item_checklist_item"(checklist_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x.* into v_row from "better_supabase"."work_items" x join "better_supabase"."work_item_checklist_items" y on y."work_item_id" = x."id"
  where y."id" = delete_work_item_checklist_item.checklist_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    return false;
  end if;
  delete from "better_supabase"."work_item_checklist_items" y where y."id" = delete_work_item_checklist_item.checklist_item;
  perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist'), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_work_item_checklist_item"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_work_item_checklist_item"(uuid) to authenticated, service_role;

-- An item's checklist, in rank order.
create or replace function "better_supabase"."list_work_item_checklist"(task uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'workItemId', y."work_item_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") order by y."rank" collate "C", y."id"), '[]'::jsonb)
  from "better_supabase"."work_item_checklist_items" y where y."work_item_id" = list_work_item_checklist.task
$$;
revoke execute on function "better_supabase"."list_work_item_checklist"(uuid) from public, anon;
grant execute on function "better_supabase"."list_work_item_checklist"(uuid) to authenticated, service_role;

-- One item the caller can read, or null.
create or replace function "better_supabase"."get_work_item"(task uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = get_work_item.task
$$;
revoke execute on function "better_supabase"."get_work_item"(uuid) from public, anon;
grant execute on function "better_supabase"."get_work_item"(uuid) to authenticated, service_role;

-- Makes an item repeat: rrule is an RFC 5545 RRULE starting at the item's
-- due date (now without one) in tzid. A null rrule stops it. Completing the
-- item then creates the next one through repeat_task.
create or replace function "better_supabase"."set_work_item_recurrence"(task uuid, rrule text, tzid text default 'UTC')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = set_work_item_recurrence.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if set_work_item_recurrence.rrule is null then
    delete from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = v_row."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = v_row."id"::text;
  else
    if set_work_item_recurrence.rrule !~ '^(RRULE:)?FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)(;[A-Z]+=[-+,0-9A-Z]+)*$' then
      raise exception 'rrule must be an RRULE such as FREQ=WEEKLY;BYDAY=MO' using errcode = '22023', hint = 'TASK_RECURRENCE_INVALID';
    end if;
    if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = coalesce(set_work_item_recurrence.tzid, 'UTC')) then
      raise exception 'tzid must be an IANA time zone' using errcode = '22023', hint = 'TASK_RECURRENCE_INVALID';
    end if;
    insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
    values (v_row."tenant_id", 'work_item', v_row."id"::text, coalesce(v_row."due_at", now()), coalesce(set_work_item_recurrence.tzid, 'UTC'), regexp_replace(set_work_item_recurrence.rrule, '^RRULE:', ''))
    on conflict ("tenant_id", "subject_type", "subject_id")
    do update set "dtstart" = excluded."dtstart", "tzid" = excluded."tzid", "rrule" = excluded."rrule";
  end if;
  perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('recurrence'), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) -> 'recurrence' from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."set_work_item_recurrence"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."set_work_item_recurrence"(uuid, text, text) to authenticated, service_role;

-- Creates the next item of a repeating item, due at due_at: a copy with its
-- dates shifted, its assignees and an unchecked checklist. The rule moves to
-- the copy. Runs once per item; a second call returns the same copy.
create or replace function "better_supabase"."repeat_work_item"(task uuid, due_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_src "better_supabase"."work_items";
  v_next jsonb;
  v_id uuid;
  v_shift interval;
begin
  select * into v_src from "better_supabase"."work_items" x where x."id" = repeat_work_item.task for update;
  if v_src."id" is null then
    raise exception 'work item not found' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  select x."id" into v_id from "better_supabase"."work_items" x where x."recurs_from" = v_src."id";
  if v_id is not null then
    return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_id);
  end if;
  v_shift := coalesce(repeat_work_item.due_at - coalesce(v_src."due_at", v_src."end_at", v_src."start_at"), interval '0');
  v_next := "better_supabase"."create_work_item"(v_src."tenant_id", jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title", 'body', v_src."body", 'parentId', v_src."parent_id", 'teamId', v_src."team_id",
    'projectId', v_src."project_id", 'priority', v_src."priority", 'estimate', v_src."estimate",
    'startAt', v_src."start_at" + v_shift, 'endAt', v_src."end_at" + v_shift, 'dueAt', repeat_work_item.due_at,
    'pipelineId', v_src."pipeline_id")),
    array(select y."user_id" from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_src."id"));
  v_id := (v_next ->> 'id')::uuid;
  update "better_supabase"."work_items" x set "recurs_from" = v_src."id" where x."id" = v_id;
  insert into "better_supabase"."work_item_checklist_items" ("tenant_id", "work_item_id", "title", "rank", "created_by")
  select y."tenant_id", v_id, y."title", y."rank", y."created_by" from "better_supabase"."work_item_checklist_items" y where y."work_item_id" = v_src."id";
  update "better_supabase"."recurrence_rules" rr set "subject_id" = v_id::text
  where rr."tenant_id" = v_src."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = v_src."id"::text;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."repeat_work_item"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."repeat_work_item"(uuid, timestamptz) to service_role;

-- Watches (all), follows (participating) or ignores an item the caller can
-- read; a null level removes the choice.
create or replace function "better_supabase"."watch_work_item"(task uuid, level text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
begin
  select * into v_row from "better_supabase"."work_items" x where x."id" = watch_work_item.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can read' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  perform "better_supabase"."set_notification_subscription"('work_item', v_row."id"::text, watch_work_item.level, v_row."tenant_id");
  return watch_work_item.level is not null;
end;
$$;
revoke execute on function "better_supabase"."watch_work_item"(uuid, text) from public, anon;
grant execute on function "better_supabase"."watch_work_item"(uuid, text) to authenticated, service_role;

-- Who watches (all) or follows (participating) an item: [{ userId, level }].
create or replace function "better_supabase"."list_work_item_watchers"(task uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', s."user_id", 'level', s."level") order by s."level", s."user_id"), '[]'::jsonb)
  from "better_supabase"."work_items" x
  join "better_supabase"."notification_subscriptions" s on s."subject_type" = 'work_item' and s."subject_id" = x."id"::text
    and s."tenant_id" = x."tenant_id"
  where x."id" = list_work_item_watchers.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)) and s."level" in ('all', 'participating')
$$;
revoke execute on function "better_supabase"."list_work_item_watchers"(uuid) from public, anon;
grant execute on function "better_supabase"."list_work_item_watchers"(uuid) to authenticated, service_role;

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
      insert into "better_supabase"."work_projects" ("tenant_id", "key", "name", "owner_id", "status", "start_on", "target_on", "budget_amount", "budget_currency", "budget_hours")
      values (save_project.tenant, upper(save_project.attrs ->> 'key'), save_project.attrs ->> 'name', (save_project.attrs ->> 'ownerId')::uuid,
        coalesce(save_project.attrs ->> 'status', 'planned'), (save_project.attrs ->> 'startOn')::date, (save_project.attrs ->> 'targetOn')::date,
        (save_project.attrs ->> 'budgetAmount')::bigint, upper(save_project.attrs ->> 'budgetCurrency'), (save_project.attrs ->> 'budgetHours')::numeric)
      returning "id" into v_id;
    else
      update "better_supabase"."work_projects" x set
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
      select 1 from "better_supabase"."work_projects" x
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
  from "better_supabase"."work_projects" x where x."id" = v_id;
  return (select to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) from "better_supabase"."work_projects" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_project"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_project"(uuid, uuid, jsonb) to authenticated, service_role;


-- A tenant's projects as a keyset page, by name (ADR 1077). It runs as
-- invoker. filters is { status, ownerId (each a value or a list), archived
-- (true adds archived ones), search (name, key), sort (name, key, createdAt),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_projects"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_projects.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status"::text)::text end) as v
      from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
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
      select 1 from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'key', 'createdAt') then
    raise exception 'sort is one of name, key, createdAt' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_projects"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_projects"(uuid, jsonb) to authenticated, service_role;

-- One project the caller can read, or null.
create or replace function "better_supabase"."get_project"(project uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) from "better_supabase"."work_projects" x where x."id" = get_project.project
$$;
revoke execute on function "better_supabase"."get_project"(uuid) from public, anon;
grant execute on function "better_supabase"."get_project"(uuid) to authenticated, service_role;


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


-- Who is acting, as { kind, name } for events and timelines. kind is the
-- profile's own (a short lowercase word), agent when the token's act claim says
-- so, service, system without a user, or user. It labels; no check reads it.
create or replace function "better_supabase"."work_item_actor"(profile jsonb default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'kind', case
      when work_item_actor.profile ->> 'kind' ~ '^[a-z][a-z_-]{0,31}$' then work_item_actor.profile ->> 'kind'
      when auth.jwt() -> 'act' ->> 'kind' = 'agent' then 'agent'
      when auth.role() = 'service_role' then 'service'
      when auth.uid() is null then 'system'
      else 'user' end,
    'name', left(coalesce(nullif(work_item_actor.profile ->> 'name', ''), auth.jwt() -> 'act' ->> 'name'), 120))
$$;
revoke execute on function "better_supabase"."work_item_actor"(jsonb) from public, anon;
grant execute on function "better_supabase"."work_item_actor"(jsonb) to authenticated, service_role;


-- Recounts the open prerequisites of the tasks in ids and records task.unblocked
-- for each open task whose count reaches zero. Cancelled and failed
-- prerequisites keep their dependents waiting.
create or replace function "better_supabase"."recount_work_item_needs"(ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
  v_next integer;
  v_was integer;
begin
  for v_row in select * from "better_supabase"."work_items" x where x."id" = any (coalesce(recount_work_item_needs.ids, '{}')) order by x."id" for update loop
    select count(*)::integer into v_next
    from "better_supabase"."relations" r
    join "better_supabase"."work_items" p on p."id"::text = r."source_id" and p."tenant_id" = v_row."tenant_id"
    where r."tenant_id" = v_row."tenant_id" and r."kind" = 'blocks'
      and r."source_type" = 'work_item' and r."target_type" = 'work_item'
      and r."target_id" = v_row."id"::text
      and not (p."state" = 'completed');
    v_was := v_row."waiting_on";
    if v_next is distinct from v_was then
      update "better_supabase"."work_items" x set "waiting_on" = v_next where x."id" = v_row."id" returning * into v_row;
      if v_next = 0 and v_row."closed_at" is null then
        perform "better_supabase".emit_event('work_item.unblocked', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'waitingOn', 0, 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
      end if;
    end if;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."recount_work_item_needs"(uuid[]) from public, anon, authenticated;

create or replace function "better_supabase"."work_item_needs_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and tg_table_name = 'work_items' then
    perform "better_supabase"."recount_work_item_needs"(array(
      select r."target_id"::uuid from "better_supabase"."relations" r
      where r."tenant_id" = old."tenant_id" and r."kind" = 'blocks'
        and r."source_type" = 'work_item' and r."source_id" = old."id"::text and r."target_type" = 'work_item'));
  elsif tg_table_name = 'work_items' then
    perform "better_supabase"."recount_work_item_needs"(array(
      select r."target_id"::uuid from "better_supabase"."relations" r
      where r."tenant_id" = new."tenant_id" and r."kind" = 'blocks'
        and r."source_type" = 'work_item' and r."source_id" = new."id"::text and r."target_type" = 'work_item'));
  elsif tg_op = 'DELETE' then
    if old."kind" = 'blocks' and old."target_type" = 'work_item' and old."source_type" = 'work_item' then
      perform "better_supabase"."recount_work_item_needs"(array[old."target_id"::uuid]);
    end if;
  elsif new."kind" = 'blocks' and new."target_type" = 'work_item' and new."source_type" = 'work_item' then
    perform "better_supabase"."recount_work_item_needs"(array[new."target_id"::uuid]);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."work_item_needs_changed"() from public, anon, authenticated;
create trigger "bsb_work_item_needs_state"
  after update of "state" or delete on "better_supabase"."work_items"
  for each row execute function "better_supabase"."work_item_needs_changed"();
create trigger "bsb_work_item_needs_relation"
  after insert or delete on "better_supabase"."relations"
  for each row execute function "better_supabase"."work_item_needs_changed"();

-- Replaces the prerequisites of a task: ids is a list of task ids. Each one is
-- a "blocks" relation from the prerequisite to this task, so the relations
-- block's permission and cycle checks apply. A prerequisite in another
-- organization is refused.
create or replace function "better_supabase"."set_work_item_needs"(task uuid, ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
  v_ids uuid[] := array(select distinct x from unnest(coalesce(set_work_item_needs.ids, '{}')) x where x is not null);
  v_old uuid[];
  v_id uuid;
begin
  select * into v_row from "better_supabase"."work_items" x where x."id" = set_work_item_needs.task and x."archived_at" is null;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if set_work_item_needs.task = any (v_ids) then
    raise exception 'a task can''t wait on itself' using errcode = '22023', hint = 'TASK_NEEDS_INVALID';
  end if;
  if exists (select 1 from unnest(v_ids) x where not exists (
    select 1 from "better_supabase"."work_items" p where p."id" = x and p."tenant_id" = v_row."tenant_id")) then
    raise exception 'a prerequisite doesn''t exist in this organization' using errcode = '22023', hint = 'TASK_NEEDS_INVALID';
  end if;
  v_old := array(select r."source_id"::uuid from "better_supabase"."relations" r
    where r."tenant_id" = v_row."tenant_id" and r."kind" = 'blocks' and r."source_type" = 'work_item'
      and r."target_type" = 'work_item' and r."target_id" = v_row."id"::text);
  foreach v_id in array array(select x from unnest(v_old) x where not (x = any (v_ids))) loop
    perform "better_supabase"."unlink"(v_row."tenant_id", 'blocks', 'work_item', v_id::text, 'work_item', v_row."id"::text);
  end loop;
  foreach v_id in array array(select x from unnest(v_ids) x where not (x = any (v_old))) loop
    perform "better_supabase"."link"(v_row."tenant_id", 'blocks', 'work_item', v_id::text, 'work_item', v_row."id"::text, '{}'::jsonb);
  end loop;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."set_work_item_needs"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."set_work_item_needs"(uuid, uuid[]) to authenticated, service_role;

-- Creates a plan of tasks in one transaction. items is a list of attrs for
-- create_task, each with an optional key, assignees and needs. parentId and
-- each needs entry are a task id or { "key": ... } naming another item of the
-- plan. At most 100 items. Returns { tasks, keys }.
create or replace function "better_supabase"."create_work_items"(tenant uuid, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
  v_pos integer := 0;
  v_keys jsonb := '{}';
  v_ids uuid[] := '{}';
  v_key text;
  v_task jsonb;
  v_id uuid;
  v_ref jsonb;
  v_prereqs uuid[];
  v_known text[] := array['key', 'title', 'body', 'parentId', 'teamId', 'projectId', 'iterationId', 'priority', 'estimate', 'progress', 'startAt', 'endAt', 'dueAt', 'pipelineId', 'stageId', 'fields', 'assignees', 'needs'];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(create_work_items.items) is distinct from 'array' then
    raise exception 'items must be a list of tasks' using errcode = '22023', hint = 'TASK_PLAN_INVALID';
  end if;
  if jsonb_array_length(create_work_items.items) > 100 then
    raise exception 'a plan holds at most 100 tasks' using errcode = '54000', hint = 'TASK_PLAN_TOO_LARGE';
  end if;
  for v_item in select value from jsonb_array_elements(create_work_items.items) loop
    v_pos := v_pos + 1;
    if jsonb_typeof(v_item) is distinct from 'object' then
      raise exception 'each item must be an object' using errcode = '22023', hint = 'TASK_PLAN_INVALID';
    end if;
    if exists (select 1 from jsonb_object_keys(v_item) k where not (k = any (v_known))) then
      raise exception 'an item has a property create can''t write' using errcode = '22023', hint = 'TASK_PLAN_INVALID';
    end if;
    v_key := v_item ->> 'key';
    if v_key is not null then
      if v_keys ? v_key then
        raise exception 'two items share a key' using errcode = '22023', hint = 'TASK_PLAN_INVALID';
      end if;
      v_keys := v_keys || jsonb_build_object(v_key, v_pos);
    end if;
  end loop;
  for v_item in select value from jsonb_array_elements(create_work_items.items) loop
    for v_ref in select value from jsonb_array_elements(coalesce(v_item -> 'needs', '[]'::jsonb)) union all select v_item -> 'parentId' where v_item ? 'parentId' loop
      if jsonb_typeof(v_ref) = 'object' and not (v_keys ? (v_ref ->> 'key')) then
        raise exception 'an item refers to a key the plan doesn''t have' using errcode = '22023', hint = 'TASK_PLAN_INVALID';
      end if;
    end loop;
  end loop;
  for v_item in select value from jsonb_array_elements(create_work_items.items) loop
    v_task := "better_supabase"."create_work_item"(
      create_work_items.tenant,
      (v_item - 'key' - 'needs' - 'assignees' - 'parentId'),
      coalesce(array(select x::uuid from jsonb_array_elements_text(coalesce(v_item -> 'assignees', '[]'::jsonb)) x), '{}'));
    v_ids := array_append(v_ids, (v_task ->> 'id')::uuid);
  end loop;
  v_pos := 0;
  for v_item in select value from jsonb_array_elements(create_work_items.items) loop
    v_pos := v_pos + 1;
    v_id := v_ids[v_pos];
    if v_item ? 'parentId' then
      v_ref := v_item -> 'parentId';
      update "better_supabase"."work_items" x set "parent_id" = case when jsonb_typeof(v_ref) = 'object' then v_ids[(v_keys ->> (v_ref ->> 'key'))::integer] else (v_ref #>> '{}')::uuid end
      where x."id" = v_id;
    end if;
    if jsonb_array_length(coalesce(v_item -> 'needs', '[]'::jsonb)) > 0 then
      v_prereqs := array(select case when jsonb_typeof(x) = 'object' then v_ids[(v_keys ->> (x ->> 'key'))::integer] else (x #>> '{}')::uuid end
        from jsonb_array_elements(v_item -> 'needs') x);
      perform "better_supabase"."set_work_item_needs"(v_id, v_prereqs);
    end if;
  end loop;
  return jsonb_build_object(
    'tasks', coalesce((select jsonb_agg(to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) order by array_position(v_ids, x."id")) from "better_supabase"."work_items" x where x."id" = any (v_ids)), '[]'::jsonb),
    'keys', coalesce((select jsonb_object_agg(k.key, v_ids[(k.value #>> '{}')::integer]) from jsonb_each(v_keys) k), '{}'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."create_work_items"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_work_items"(uuid, jsonb) to authenticated, service_role;



-- Takes the lease on a task. Returns { task, claim } with the claim's token,
-- which renew and release need. A live claim of someone else raises
-- TASK_CLAIMED; the same holder claiming again keeps the token. A task that
-- waits on prerequisites raises TASK_NOT_READY (with the needs option), a held
-- one TASK_HELD, a closed one TASK_CLOSED.
create or replace function "better_supabase"."claim_work_item"(task uuid, lease integer default null, profile jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
  v_claim "better_supabase"."work_item_claims";
  v_actor jsonb := "better_supabase"."work_item_actor"(claim_work_item.profile);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = claim_work_item.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if v_row."closed_at" is not null then
    raise exception 'a closed task can''t be claimed' using errcode = '55000', hint = 'TASK_CLOSED';
  end if;
  if coalesce(auth.jwt() -> 'act' ->> 'kind' = 'agent', false) and not exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and y."user_id" = auth.uid()) then
    raise exception 'an agent session claims only tasks assigned to its user' using errcode = '42501', hint = 'TASK_NOT_ASSIGNED';
  end if;
  if not (v_row."delegate_profile" is null or (v_row."delegate_profile" ->> 'name' is not distinct from v_actor ->> 'name' and (v_row."delegate_profile" ->> 'userId') is not distinct from auth.uid()::text) or (not coalesce(auth.jwt() -> 'act' ->> 'kind' = 'agent', false) and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)))) then
    raise exception 'the task is reserved for another profile' using errcode = '42501', hint = 'TASK_RESERVED';
  end if;
  if v_row."held_at" is not null then
    raise exception 'the task is on hold' using errcode = '55000', hint = 'TASK_HELD';
  end if;
  insert into "better_supabase"."work_item_claims" as c ("work_item_id", "tenant_id", "holder_id", "profile", "expires_at")
  values (v_row."id", v_row."tenant_id", auth.uid(), v_actor, now() + make_interval(secs => least(900, greatest(1, coalesce(claim_work_item.lease, 900)))))
  on conflict ("work_item_id") do update set
    "token" = case when c."expires_at" > now() then c."token" else gen_random_uuid() end,
    "epoch" = case when c."expires_at" > now() then c."epoch" else c."epoch" + 1 end,
    "holder_id" = excluded."holder_id",
    "profile" = excluded."profile",
    "claimed_at" = case when c."expires_at" > now() then c."claimed_at" else now() end,
    "expires_at" = excluded."expires_at",
    "expired_at" = null
  where not c."expires_at" > now()
    or (c."holder_id" is not distinct from excluded."holder_id" and c."profile" ->> 'name' is not distinct from excluded."profile" ->> 'name')
  returning * into v_claim;
  if not found then
    raise exception 'another holder has a live claim on the task' using errcode = '55P03', hint = 'TASK_CLAIMED';
  end if;
  if v_row."delegate_profile" is not null and not (v_row."delegate_profile" ->> 'name' is not distinct from v_actor ->> 'name' and (v_row."delegate_profile" ->> 'userId') is not distinct from auth.uid()::text) then
    update "better_supabase"."work_items" x set "delegate_profile" = null where x."id" = v_row."id";
  end if;
  perform "better_supabase".emit_event('work_item.claimed', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'holderId', v_claim."holder_id", 'epoch', v_claim."epoch", 'expiresAt', v_claim."expires_at", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(claim_work_item.profile) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(claim_work_item.profile) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return jsonb_build_object('task', (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id"), 'claim', jsonb_build_object('token', v_claim."token", 'epoch', v_claim."epoch", 'holderId', v_claim."holder_id", 'profile', v_claim."profile", 'claimedAt', v_claim."claimed_at", 'expiresAt', v_claim."expires_at"));
end;
$$;
revoke execute on function "better_supabase"."claim_work_item"(uuid, integer, jsonb) from public, anon;
grant execute on function "better_supabase"."claim_work_item"(uuid, integer, jsonb) to authenticated, service_role;

-- Claims the next ready task of a tenant: assigned to you first, then the
-- lowest number. With claims.next "assigned" (the default) and for an agent
-- session, only tasks assigned to you qualify. filter narrows the pick: teamId, projectId, parentId, stageId,
-- assigneeId. Concurrent callers skip each other's rows. Raises
-- TASK_NOTHING_READY when no task qualifies.
create or replace function "better_supabase"."claim_next_work_item"(tenant uuid, filter jsonb default null, lease integer default null, profile jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_lost uuid[] := '{}';
  v_name text := "better_supabase"."work_item_actor"(claim_next_work_item.profile) ->> 'name';
  v_writer boolean := (auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', claim_next_work_item.tenant, 'tasks.write'), false);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;

  if (coalesce(auth.jwt() -> 'act' ->> 'kind' = 'agent', false) or auth.uid() is not null) then
    if claim_next_work_item.filter ->> 'assigneeId' is not null and (claim_next_work_item.filter ->> 'assigneeId')::uuid is distinct from auth.uid() then
      raise exception 'this session picks only its own tasks' using errcode = '42501', hint = 'TASK_FILTER_FORBIDDEN';
    end if;
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', claim_next_work_item.tenant, 'tasks.write'), false)) then
    raise exception 'not allowed to claim work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  -- A claim committed after this statement's snapshot is invisible to it, so
  -- a row picked here can already be taken. Check again and pick another.
  loop
    select x."id" into v_id from "better_supabase"."work_items" x
    where x."id" <> all (v_lost) and x."tenant_id" = claim_next_work_item.tenant and x."archived_at" is null and x."closed_at" is null
      and x."held_at" is null
      and (not (coalesce(auth.jwt() -> 'act' ->> 'kind' = 'agent', false) or auth.uid() is not null) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and y."user_id" = auth.uid()))
      and (x."delegate_profile" is null or (x."delegate_profile" ->> 'name' is not distinct from v_name and (x."delegate_profile" ->> 'userId') is not distinct from auth.uid()::text) or (not coalesce(auth.jwt() -> 'act' ->> 'kind' = 'agent', false) and v_writer))
      and not exists (select 1 from "better_supabase"."work_item_claims" c where c."work_item_id" = x."id" and c."expires_at" > now())
      and (claim_next_work_item.filter ->> 'teamId' is null or x."team_id" = (claim_next_work_item.filter ->> 'teamId')::uuid)
      and (claim_next_work_item.filter ->> 'projectId' is null or x."project_id" = (claim_next_work_item.filter ->> 'projectId')::uuid)
      and (claim_next_work_item.filter ->> 'parentId' is null or x."parent_id" = (claim_next_work_item.filter ->> 'parentId')::uuid)
      and (claim_next_work_item.filter ->> 'stageId' is null or x."stage_id" = (claim_next_work_item.filter ->> 'stageId')::uuid)
      and (claim_next_work_item.filter ->> 'delegateProfile' is null or x."delegate_profile" ->> 'name' = claim_next_work_item.filter ->> 'delegateProfile')
      and (claim_next_work_item.filter ->> 'assigneeId' is null or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and y."user_id" = (claim_next_work_item.filter ->> 'assigneeId')::uuid))
    order by (case when exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and y."user_id" = auth.uid()) then 0 else 1 end), x."number"
    limit 1
    for update of x skip locked;
    exit when v_id is null or not exists (select 1 from "better_supabase"."work_item_claims" c where c."work_item_id" = v_id and c."expires_at" > now());
    v_lost := v_lost || v_id;
  end loop;
  if v_id is null then
    raise exception 'no task is ready to claim' using errcode = 'P0002', hint = 'TASK_NOTHING_READY';
  end if;
  return "better_supabase"."claim_work_item"(v_id, claim_next_work_item.lease, claim_next_work_item.profile);
end;
$$;
revoke execute on function "better_supabase"."claim_next_work_item"(uuid, jsonb, integer, jsonb) from public, anon;
grant execute on function "better_supabase"."claim_next_work_item"(uuid, jsonb, integer, jsonb) to authenticated, service_role;

-- Extends a live claim to now plus the lease. Raises TASK_CLAIM_LOST when the
-- token isn't the live claim's, because the lease ran out or someone took over.
create or replace function "better_supabase"."renew_work_item_claim"(task uuid, token uuid, lease integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claim "better_supabase"."work_item_claims";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."work_item_claims" c set "expires_at" = now() + make_interval(secs => least(900, greatest(1, coalesce(renew_work_item_claim.lease, 900))))
  where c."work_item_id" = renew_work_item_claim.task and c."token" = renew_work_item_claim.token and c."expires_at" > now()
    and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', c."tenant_id", 'tasks.write'), false))
  returning * into v_claim;
  if not found then
    raise exception 'the claim ran out or another holder took over' using errcode = '55000', hint = 'TASK_CLAIM_LOST';
  end if;
  return jsonb_build_object('token', v_claim."token", 'epoch', v_claim."epoch", 'holderId', v_claim."holder_id", 'profile', v_claim."profile", 'claimedAt', v_claim."claimed_at", 'expiresAt', v_claim."expires_at");
end;
$$;
revoke execute on function "better_supabase"."renew_work_item_claim"(uuid, uuid, integer) from public, anon;
grant execute on function "better_supabase"."renew_work_item_claim"(uuid, uuid, integer) to authenticated, service_role;

-- Gives a claim up. Raises TASK_CLAIM_NOT_HELD when nobody holds the task and
-- TASK_CLAIM_LOST when the token isn't the live claim's.
create or replace function "better_supabase"."release_work_item_claim"(task uuid, token uuid, note text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claim "better_supabase"."work_item_claims";
  v_row "better_supabase"."work_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."work_item_claims" c where c."work_item_id" = release_work_item_claim.task for update;
  if not found then
    raise exception 'nobody holds this task' using errcode = 'P0002', hint = 'TASK_CLAIM_NOT_HELD';
  end if;
  if v_claim."token" is distinct from release_work_item_claim.token or not (v_claim."expires_at" > now()) then
    raise exception 'the claim ran out or another holder took over' using errcode = '55000', hint = 'TASK_CLAIM_LOST';
  end if;
  update "better_supabase"."work_item_claims" c set "expires_at" = now(), "expired_at" = now() where c."work_item_id" = release_work_item_claim.task;
  select * into v_row from "better_supabase"."work_items" x where x."id" = release_work_item_claim.task;
  perform "better_supabase".emit_event('work_item.released', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'holderId', v_claim."holder_id", 'epoch', v_claim."epoch", 'expiresAt', v_claim."expires_at", 'note', nullif(trim(release_work_item_claim.note), ''), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(v_claim."profile") ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(v_claim."profile") ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return true;
end;
$$;
revoke execute on function "better_supabase"."release_work_item_claim"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."release_work_item_claim"(uuid, uuid, text) to authenticated, service_role;

-- Hands a task to a user: assigns them, notes who delegated, and drops a claim
-- held by someone else. The user needs tasks.read in the organization. With
-- to_profile the task is reserved for that profile of the user: only a claim
-- under that profile name by that user, or a person with write access, takes it
-- (TASK_RESERVED otherwise). Delegating again, unassigning the user and closing
-- the task clear the reservation.

create or replace function "better_supabase"."delegate_work_item"(task uuid, to_user uuid, profile jsonb default null, to_profile text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
  v_actor jsonb := "better_supabase"."work_item_actor"(delegate_work_item.profile);
  v_name text := nullif(btrim(delegate_work_item.to_profile), '');
  v_added boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = delegate_work_item.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if delegate_work_item.to_profile is not null and (v_name is null or length(v_name) > 120) then
    raise exception 'to_profile is a name of up to 120 characters' using errcode = '22023', hint = 'TASK_DELEGATE_INVALID';
  end if;
  if not coalesce(better_supabase.can_user(delegate_work_item.to_user, 'tenant', v_row."tenant_id", 'tasks.read'), false) then
    raise exception 'the user can''t read tasks in this organization' using errcode = '22023', hint = 'TASK_DELEGATE_INVALID';
  end if;
  insert into "better_supabase"."work_item_assignees" ("tenant_id", "work_item_id", "user_id") values (v_row."tenant_id", v_row."id", delegate_work_item.to_user)
  on conflict do nothing;
  v_added := found;
  delete from "better_supabase"."work_item_claims" c where c."work_item_id" = v_row."id" and c."holder_id" is distinct from delegate_work_item.to_user;
  update "better_supabase"."work_items" x set "delegate_profile" = case when v_name is null then null else jsonb_build_object('name', v_name, 'userId', delegate_work_item.to_user) end where x."id" = v_row."id";
  perform "better_supabase".emit_event('work_item.delegated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'delegateId', delegate_work_item.to_user, 'toProfile', v_name, 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(delegate_work_item.profile) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(delegate_work_item.profile) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  if v_added then
    perform "better_supabase".emit_event('work_item.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(array(select y."user_id" from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id")), 'addedIds', jsonb_build_array(delegate_work_item.to_user), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."delegate_work_item"(uuid, uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."delegate_work_item"(uuid, uuid, jsonb, text) to authenticated, service_role;

-- Unassigning the user a task is reserved for ends the reservation.
create or replace function better_supabase.bsb_work_item_reservation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "better_supabase"."work_items" x set "delegate_profile" = null
    where x."id" = old."work_item_id" and x."delegate_profile" ->> 'userId' = old."user_id"::text;
  return old;
end;
$$;
revoke execute on function better_supabase.bsb_work_item_reservation() from public, anon, authenticated;
create trigger bsb_work_item_reservation after delete on "better_supabase"."work_item_assignees"
for each row execute function better_supabase.bsb_work_item_reservation();

-- Deletes the claims whose lease ran out, moves each task to the expired stage
-- (the claims.expiredStage option) and records task.claim_expired.
create or replace function "better_supabase"."expire_work_item_claims"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claim "better_supabase"."work_item_claims";
  v_row "better_supabase"."work_items";
  v_count integer := 0;
begin
  for v_claim in update "better_supabase"."work_item_claims" c set "expired_at" = now() where c."expires_at" <= now() and c."expired_at" is null returning c.* loop
    v_count := v_count + 1;
    select * into v_row from "better_supabase"."work_items" x where x."id" = v_claim."work_item_id";
    if found and v_row."closed_at" is null then
      perform "better_supabase".emit_event('work_item.claim_expired', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'holderId', v_claim."holder_id", 'epoch', v_claim."epoch", 'expiresAt', v_claim."expires_at", 'returnStageId', v_row."stage_id", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(v_claim."profile") ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(v_claim."profile") ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_work_item_claims"() from public, anon, authenticated;
grant execute on function "better_supabase"."expire_work_item_claims"() to service_role;


-- Puts a task on hold: kind says what it waits for (a short lowercase word),
-- note reaches ask_user_ids through the task's conversation with mentions.
-- A live claim is dropped. Each asked user needs tasks.read.
create or replace function "better_supabase"."hold_work_item"(task uuid, kind text, note text default null, ask_user_ids uuid[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
  v_stage uuid;
  v_note text := nullif(trim(hold_work_item.note), '');
  v_ask uuid[] := array(select distinct x from unnest(coalesce(hold_work_item.ask_user_ids, '{}')) x where x is not null);
  v_conversation text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if hold_work_item.kind is null or hold_work_item.kind !~ '^[a-z][a-z_]{0,31}$' then
    raise exception 'kind must be a short lowercase word such as review or input' using errcode = '22023', hint = 'TASK_HOLD_INVALID';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = hold_work_item.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if v_row."closed_at" is not null then
    raise exception 'a closed task can''t be held' using errcode = '55000', hint = 'TASK_CLOSED';
  end if;
  if v_row."held_at" is not null then
    raise exception 'the task is already on hold' using errcode = '55000', hint = 'TASK_HELD';
  end if;
  if exists (select 1 from unnest(v_ask) x where not coalesce(better_supabase.can_user(x, 'tenant', v_row."tenant_id", 'tasks.read'), false)) then
    raise exception 'an asked user can''t read tasks in this organization' using errcode = '22023', hint = 'TASK_HOLD_INVALID';
  end if;
  delete from "better_supabase"."work_item_claims" c where c."work_item_id" = v_row."id";
  update "better_supabase"."work_items" x set "held_at" = now(), "hold_kind" = hold_work_item.kind where x."id" = v_row."id";
  if v_note is not null or cardinality(v_ask) > 0 then
    v_conversation := ("better_supabase"."open_conversation"(v_row."tenant_id", 'subject', jsonb_build_object('subjectType', 'work_item', 'subjectId', v_row."id"::text), '{}'))
      ->> 'id';
    perform "better_supabase"."send_message"(v_conversation::uuid, coalesce(v_note, 'On hold: ' || hold_work_item.kind),
      jsonb_build_object('mentions', to_jsonb(v_ask)), '{}');
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('work_item.held', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'kind', hold_work_item.kind, 'note', v_note, 'askUserIds', to_jsonb(v_ask), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."hold_work_item"(uuid, text, text, uuid[]) from public, anon;
grant execute on function "better_supabase"."hold_work_item"(uuid, text, text, uuid[]) to authenticated, service_role;

-- Ends a hold. With the hold stage option the task returns to the stage it
-- left. A pending approval request of the hold is cancelled, and
-- task.hold_released says so with approvalCancelled.
create or replace function "better_supabase"."release_work_item_hold"(task uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
  v_kind text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = release_work_item_hold.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if v_row."held_at" is null then
    raise exception 'the task isn''t on hold' using errcode = '55000', hint = 'TASK_NOT_HELD';
  end if;
  v_kind := v_row."hold_kind";
  update "better_supabase"."work_items" x set "held_at" = null, "hold_kind" = null, "hold_return_stage_id" = null where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('work_item.hold_released', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'kind', v_kind, 'returnStageId', v_row."stage_id", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."release_work_item_hold"(uuid) from public, anon;
grant execute on function "better_supabase"."release_work_item_hold"(uuid) to authenticated, service_role;


-- Closes or reopens a task with a note. outcome is completed, canceled, failed
-- or open. stage defaults to the first stage of the matching category in the
-- task's pipeline. failed lands in the canceled category with close reason
-- failed (not_planned where the column can't hold it). The note rides on
-- task.closed, and failed also records task.failed. The before_task_close hook
-- runs from the close trigger on the task, so every way of closing reaches it.
create or replace function "better_supabase"."close_work_item"(task uuid, outcome text, note text default null, stage uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
  v_stage uuid;
  v_note text := nullif(trim(close_work_item.note), '');
  v_constraint text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if close_work_item.outcome is null or close_work_item.outcome not in ('completed', 'canceled', 'failed', 'open') then
    raise exception 'outcome is completed, canceled, failed or open' using errcode = '22023', hint = 'TASK_OUTCOME_INVALID';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = close_work_item.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if close_work_item.outcome = 'open' and v_row."closed_at" is null then
    return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id");
  end if;
  if close_work_item.outcome <> 'open' and v_row."closed_at" is not null then
    raise exception 'the task is already closed' using errcode = '55000', hint = 'TASK_CLOSED';
  end if;
  v_stage := coalesce(close_work_item.stage, case close_work_item.outcome
    when 'completed' then (select s."id" from "better_supabase"."pipeline_stages" s where s."pipeline_id" = v_row."pipeline_id" and s."category"::text = 'completed' and s."archived_at" is null order by s."rank" collate "C", s."id" limit 1)
    when 'open' then (select s."id" from "better_supabase"."pipeline_stages" s where s."pipeline_id" = v_row."pipeline_id" and s."category"::text = 'unstarted' and s."archived_at" is null order by s."rank" collate "C", s."id" limit 1)
    else (select s."id" from "better_supabase"."pipeline_stages" s where s."pipeline_id" = v_row."pipeline_id" and s."category"::text = 'canceled' and s."archived_at" is null order by s."rank" collate "C", s."id" limit 1) end);
  if v_stage is null then
    raise exception 'the task''s pipeline has no stage for this outcome; pass a stage' using errcode = '22023', hint = 'TASK_STAGE_REQUIRED';
  end if;
  perform set_config('bsb.close_note', coalesce(v_note, ''), true);
  perform set_config('bsb.close_by', coalesce(auth.uid()::text, ''), true);
  begin
    if close_work_item.outcome = 'failed' then
      begin
        update "better_supabase"."work_items" x set "stage_id" = v_stage, "close_reason" = 'failed' where x."id" = v_row."id";
      exception when check_violation or invalid_text_representation then
        update "better_supabase"."work_items" x set "stage_id" = v_stage where x."id" = v_row."id";
      end;
    else
      update "better_supabase"."work_items" x set "stage_id" = v_stage where x."id" = v_row."id";
    end if;
  exception when check_violation or foreign_key_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint is null then
      raise;
    end if;
    raise exception 'the stage can''t be used for this task' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  perform set_config('bsb.close_note', '', true);
  select * into v_row from "better_supabase"."work_items" x where x."id" = v_row."id";
  if close_work_item.outcome = 'failed' then
    perform "better_supabase".emit_event('work_item.failed', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'note', v_note, 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."close_work_item"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."close_work_item"(uuid, text, text, uuid) to authenticated, service_role;


-- Puts a task at a place in a lane (a stage's column): after afterId, before
-- beforeId, or at the end. Moving to another stage with stageId changes its
-- stage. When the neighbours share a rank key the lane is rebalanced and the
-- move retried once.
create or replace function "better_supabase"."move_work_item"(task uuid, stage uuid default null, before uuid default null, after uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
  v_stage uuid;
  v_prev text;
  v_next text;
  v_rank text;
  v_tries integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = move_work_item.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if v_row."closed_at" is not null and move_work_item.stage is null then
    raise exception 'a closed task keeps its place' using errcode = '55000', hint = 'TASK_CLOSED';
  end if;
  v_stage := coalesce(move_work_item.stage, v_row."stage_id");
  loop
    v_prev := null;
    v_next := null;
    if move_work_item.after is not null then
      select x."rank" into v_prev from "better_supabase"."work_items" x where x."id" = move_work_item.after and x."tenant_id" = v_row."tenant_id" and x."stage_id" is not distinct from v_stage and x."archived_at" is null and x."id" <> v_row."id";
      if not found then
        raise exception 'the task to place after isn''t in that lane' using errcode = '22023', hint = 'TASK_MOVE_INVALID';
      end if;
    end if;
    if move_work_item.before is not null then
      select x."rank" into v_next from "better_supabase"."work_items" x where x."id" = move_work_item.before and x."tenant_id" = v_row."tenant_id" and x."stage_id" is not distinct from v_stage and x."archived_at" is null and x."id" <> v_row."id";
      if not found then
        raise exception 'the task to place before isn''t in that lane' using errcode = '22023', hint = 'TASK_MOVE_INVALID';
      end if;
    end if;
    if move_work_item.after is not null and move_work_item.before is null then
      select min(x."rank" collate "C") into v_next from "better_supabase"."work_items" x where x."tenant_id" = v_row."tenant_id" and x."stage_id" is not distinct from v_stage and x."archived_at" is null and x."id" <> v_row."id" and x."rank" collate "C" > v_prev collate "C";
    elsif move_work_item.before is not null and move_work_item.after is null then
      select max(x."rank" collate "C") into v_prev from "better_supabase"."work_items" x where x."tenant_id" = v_row."tenant_id" and x."stage_id" is not distinct from v_stage and x."archived_at" is null and x."id" <> v_row."id" and x."rank" collate "C" < v_next collate "C";
    elsif move_work_item.before is null and move_work_item.after is null then
      select max(x."rank" collate "C") into v_prev from "better_supabase"."work_items" x where x."tenant_id" = v_row."tenant_id" and x."stage_id" is not distinct from v_stage and x."archived_at" is null and x."id" <> v_row."id";
    end if;
    exit when v_prev is null or v_next is null or v_prev collate "C" < v_next collate "C";
    if v_tries > 0 then
      raise exception 'the neighbours share a rank key' using errcode = '22023', hint = 'TASK_RANK_CONFLICT';
    end if;
    v_tries := v_tries + 1;
    with ordered as (
      select x."id" as id, row_number() over (order by x."rank" collate "C", x."number", x."id") as nth, count(*) over () as total
      from "better_supabase"."work_items" x
      where x."tenant_id" = v_row."tenant_id" and x."stage_id" is not distinct from v_stage and x."archived_at" is null)
    update "better_supabase"."work_items" y set "rank" = "better_supabase"."rank_key"(o.nth, o.total) from ordered o where y."id" = o.id;
  end loop;
  v_rank := "better_supabase"."rank_between"(v_prev, v_next);
  update "better_supabase"."work_items" x set "stage_id" = v_stage, "rank" = v_rank where x."id" = v_row."id";
  select * into v_row from "better_supabase"."work_items" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('stageId', 'rank'), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."move_work_item"(uuid, uuid, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."move_work_item"(uuid, uuid, uuid, uuid) to authenticated, service_role;

-- Applies a list of { workItemId, stageId, beforeId, afterId } moves, each on
-- its own. Returns { accepted, rejected } like update_tasks.
create or replace function "better_supabase"."move_work_items"(moves jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_move jsonb;
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(move_work_items.moves, '[]')) <> 'array' then
    raise exception 'moves must be a list' using errcode = '22023', hint = 'TASK_CHANGES_INVALID';
  end if;
  for v_move in select value from jsonb_array_elements(move_work_items.moves) loop
    begin
      perform "better_supabase"."move_work_item"((v_move ->> 'workItemId')::uuid, (v_move ->> 'stageId')::uuid, (v_move ->> 'beforeId')::uuid, (v_move ->> 'afterId')::uuid);
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('workItemId', v_move ->> 'workItemId'));
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_move ->> 'workItemId', 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "better_supabase"."move_work_items"(jsonb) from public, anon;
grant execute on function "better_supabase"."move_work_items"(jsonb) to authenticated, service_role;


-- The stages a task has been in, oldest first, with the seconds spent in each.
-- The current stage is open: exitedAt is null and seconds run to now.
create or replace function "better_supabase"."work_item_stage_times"(task uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'stageId', h."to_stage_id", 'stageName', h."stage_name", 'category', h."category"::text,
    'enteredAt', h."entered_at", 'exitedAt', h."exited_at",
    'seconds', round(extract(epoch from (coalesce(h."exited_at", now()) - h."entered_at")))::bigint
  ) order by h."entered_at"), '[]'::jsonb)
  from "better_supabase"."pipeline_stage_history" h
  join "better_supabase"."work_items" x on x."id"::text = h."subject_id" and x."tenant_id" = h."tenant_id"
  where x."id" = work_item_stage_times.task and h."subject_type" = 'work_item'
    and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)));
end;
$$;
revoke execute on function "better_supabase"."work_item_stage_times"(uuid) from public, anon;
grant execute on function "better_supabase"."work_item_stage_times"(uuid) to authenticated, service_role;

-- Tells tasks:<tenant> that a task or its claim changed. The payload carries
-- ids only; readers fetch the rows through the API.
create or replace function "better_supabase"."work_items_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant text;
  v_task uuid;
begin
  if tg_op = 'DELETE' then
    v_tenant := old."tenant_id"::text;
    v_task := old."id";
  else
    v_tenant := new."tenant_id"::text;
    v_task := new."id";
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('id', v_task, 'change', lower(tg_op), 'table', tg_table_name), 'changed', 'tasks:' || v_tenant, true);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."work_items_changed"() from public, anon, authenticated;
create trigger "bsb_work_items_changed"
  after insert or update or delete on "better_supabase"."work_items"
  for each row execute function "better_supabase"."work_items_changed"();
create or replace function "better_supabase"."work_item_claims_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant text;
  v_task uuid;
begin
  if tg_op = 'DELETE' then
    v_tenant := old."tenant_id"::text;
    v_task := old."work_item_id";
  else
    v_tenant := new."tenant_id"::text;
    v_task := new."work_item_id";
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('id', v_task, 'change', lower(tg_op), 'table', tg_table_name), 'changed', 'tasks:' || v_tenant, true);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."work_item_claims_changed"() from public, anon, authenticated;
create trigger "bsb_work_item_claims_changed"
  after insert or update or delete on "better_supabase"."work_item_claims"
  for each row execute function "better_supabase"."work_item_claims_changed"();

-- Members join tasks:{tenant}.
create policy bsb_work_items_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'tasks:%'
        and substr((select realtime.topic()), 7) in (select x::text from better_supabase.tenant_ids_with('tasks.read') x));

-- Creates a work item (attrs and assignees as create_task) and starts its SLA
-- clocks on subject_type, at priority, in one transaction. Returns { task,
-- clocks }.
create or replace function "better_supabase"."create_work_item_with_sla"(tenant uuid, attrs jsonb, assignees uuid[], subject_type text, priority text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_task jsonb;
  v_clocks jsonb;
begin
  v_task := "better_supabase"."create_work_item"(create_work_item_with_sla.tenant, create_work_item_with_sla.attrs, create_work_item_with_sla.assignees);
  v_clocks := "better_supabase"."start_sla_clocks"(create_work_item_with_sla.subject_type, v_task ->> 'id', create_work_item_with_sla.priority);
  return jsonb_build_object('task', v_task, 'clocks', v_clocks);
end;
$$;
revoke execute on function "better_supabase"."create_work_item_with_sla"(uuid, jsonb, uuid[], text, text) from public, anon;
grant execute on function "better_supabase"."create_work_item_with_sla"(uuid, jsonb, uuid[], text, text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."work_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."work_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."work_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."work_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."work_item_specification_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."work_item_specification_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."work_item_specification_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."work_item_specification_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."work_item_material_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."work_item_material_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."work_item_material_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."work_item_material_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."work_item_checklist_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."work_item_checklist_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."work_item_checklist_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."work_item_checklist_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."work_item_assignees" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."work_item_assignees" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."work_item_assignees" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."work_item_assignees" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."work_projects" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tasks.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."work_projects" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."work_projects" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."work_projects" as restrictive
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
create trigger "bsb_search_work_item_index"
  after insert or delete on "better_supabase"."work_items"
  for each row execute function "better_supabase"."search_index_row"('work_item', 'id');
create trigger "bsb_search_work_item_index_u"
  after update of "id", "tenant_id", "title", "identifier", "body", "archived_at" on "better_supabase"."work_items"
  for each row when (old."id" is distinct from new."id" or old."tenant_id" is distinct from new."tenant_id" or old."title" is distinct from new."title" or old."identifier" is distinct from new."identifier" or old."body" is distinct from new."body" or old."archived_at" is distinct from new."archived_at")
  execute function "better_supabase"."search_index_row"('work_item', 'id');

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.work_items deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"work_item","event_prefix":"work_item","archive_column":"archived_at"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.work_projects deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"project","event_prefix":"project","archive_column":"archived_at"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.iterations deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"iteration","event_prefix":"iteration"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.work_item_checklist_items deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"checklist_item","event_prefix":"checklist_item"}');

-- Realtime for the module's entities (subject.realtime)
create trigger bsb_realtime_insert after insert on "better_supabase"."work_items" referencing new table as new_rows for each statement execute function better_supabase.broadcast_changes('tenant_id', 'tenant');
create trigger bsb_realtime_update after update on "better_supabase"."work_items" referencing old table as old_rows new table as new_rows for each statement execute function better_supabase.broadcast_changes('tenant_id', 'tenant');
create trigger bsb_realtime_delete after delete on "better_supabase"."work_items" referencing old table as old_rows for each statement execute function better_supabase.broadcast_changes('tenant_id', 'tenant');

-- blocks.tasks.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."save_work_item_specification_line"(task uuid, line_id uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_work_item_specification_line"($1, $2, $3) $$;
revoke execute on function "api"."save_work_item_specification_line"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_work_item_specification_line"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."list_work_item_specification"(task uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_work_item_specification"($1) $$;
revoke execute on function "api"."list_work_item_specification"(uuid) from public, anon;
grant execute on function "api"."list_work_item_specification"(uuid) to authenticated, service_role;

create or replace function "api"."save_work_item_material_line"(task uuid, line_id uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_work_item_material_line"($1, $2, $3) $$;
revoke execute on function "api"."save_work_item_material_line"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_work_item_material_line"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."list_work_item_materials"(task uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_work_item_materials"($1) $$;
revoke execute on function "api"."list_work_item_materials"(uuid) from public, anon;
grant execute on function "api"."list_work_item_materials"(uuid) to authenticated, service_role;

create or replace function "api"."work_item_claim"(task uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."work_item_claim"($1) $$;
revoke execute on function "api"."work_item_claim"(uuid) from public, anon;
grant execute on function "api"."work_item_claim"(uuid) to authenticated, service_role;

create or replace function "api"."create_work_item"(tenant uuid, attrs jsonb, assignees uuid[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_work_item"($1, $2, $3) $$;
revoke execute on function "api"."create_work_item"(uuid, jsonb, uuid[]) from public, anon;
grant execute on function "api"."create_work_item"(uuid, jsonb, uuid[]) to authenticated, service_role;

create or replace function "api"."update_work_items"(changes jsonb, atomic boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_work_items"($1, $2) $$;
revoke execute on function "api"."update_work_items"(jsonb, boolean) from public, anon;
grant execute on function "api"."update_work_items"(jsonb, boolean) to authenticated, service_role;

create or replace function "api"."set_work_item_assignees"(task uuid, users uuid[])
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_work_item_assignees"($1, $2) $$;
revoke execute on function "api"."set_work_item_assignees"(uuid, uuid[]) from public, anon;
grant execute on function "api"."set_work_item_assignees"(uuid, uuid[]) to authenticated, service_role;

create or replace function "api"."archive_work_item"(task uuid, archived boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_work_item"($1, $2) $$;
revoke execute on function "api"."archive_work_item"(uuid, boolean) from public, anon;
grant execute on function "api"."archive_work_item"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."archive_work_items"(ids uuid[], archived boolean default true)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_work_items"($1, $2) $$;
revoke execute on function "api"."archive_work_items"(uuid[], boolean) from public, anon;
grant execute on function "api"."archive_work_items"(uuid[], boolean) to authenticated, service_role;

create or replace function "api"."delete_work_item"(task uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_work_item"($1) $$;
revoke execute on function "api"."delete_work_item"(uuid) from public, anon;
grant execute on function "api"."delete_work_item"(uuid) to authenticated, service_role;

create or replace function "api"."delete_work_items"(ids uuid[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_work_items"($1) $$;
revoke execute on function "api"."delete_work_items"(uuid[]) from public, anon;
grant execute on function "api"."delete_work_items"(uuid[]) to authenticated, service_role;

create or replace function "api"."work_item_tree"(root uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."work_item_tree"($1) $$;
revoke execute on function "api"."work_item_tree"(uuid) from public, anon;
grant execute on function "api"."work_item_tree"(uuid) to authenticated, service_role;

create or replace function "api"."list_work_items"(tenant uuid, filter jsonb, search text, after uuid, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_work_items"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_work_items"(uuid, jsonb, text, uuid, integer) from public, anon;
grant execute on function "api"."list_work_items"(uuid, jsonb, text, uuid, integer) to authenticated, service_role;

create or replace function "api"."page_work_items"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_work_items"($1, $2) $$;
revoke execute on function "api"."page_work_items"(uuid, jsonb) from public, anon;
grant execute on function "api"."page_work_items"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."clone_work_item"(source uuid, overrides jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."clone_work_item"($1, $2) $$;
revoke execute on function "api"."clone_work_item"(uuid, jsonb) from public, anon;
grant execute on function "api"."clone_work_item"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."save_work_item_checklist_item"(task uuid, checklist_item uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_work_item_checklist_item"($1, $2, $3) $$;
revoke execute on function "api"."save_work_item_checklist_item"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_work_item_checklist_item"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_work_item_checklist_item"(checklist_item uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_work_item_checklist_item"($1) $$;
revoke execute on function "api"."delete_work_item_checklist_item"(uuid) from public, anon;
grant execute on function "api"."delete_work_item_checklist_item"(uuid) to authenticated, service_role;

create or replace function "api"."list_work_item_checklist"(task uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_work_item_checklist"($1) $$;
revoke execute on function "api"."list_work_item_checklist"(uuid) from public, anon;
grant execute on function "api"."list_work_item_checklist"(uuid) to authenticated, service_role;

create or replace function "api"."get_work_item"(task uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_work_item"($1) $$;
revoke execute on function "api"."get_work_item"(uuid) from public, anon;
grant execute on function "api"."get_work_item"(uuid) to authenticated, service_role;

create or replace function "api"."set_work_item_recurrence"(task uuid, rrule text, tzid text default 'UTC')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_work_item_recurrence"($1, $2, $3) $$;
revoke execute on function "api"."set_work_item_recurrence"(uuid, text, text) from public, anon;
grant execute on function "api"."set_work_item_recurrence"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."repeat_work_item"(task uuid, due_at timestamptz)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."repeat_work_item"($1, $2) $$;
revoke execute on function "api"."repeat_work_item"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "api"."repeat_work_item"(uuid, timestamptz) to service_role;

create or replace function "api"."watch_work_item"(task uuid, level text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."watch_work_item"($1, $2) $$;
revoke execute on function "api"."watch_work_item"(uuid, text) from public, anon;
grant execute on function "api"."watch_work_item"(uuid, text) to authenticated, service_role;

create or replace function "api"."list_work_item_watchers"(task uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_work_item_watchers"($1) $$;
revoke execute on function "api"."list_work_item_watchers"(uuid) from public, anon;
grant execute on function "api"."list_work_item_watchers"(uuid) to authenticated, service_role;

create or replace function "api"."save_project"(tenant uuid, project uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_project"($1, $2, $3) $$;
revoke execute on function "api"."save_project"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_project"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."page_projects"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_projects"($1, $2) $$;
revoke execute on function "api"."page_projects"(uuid, jsonb) from public, anon;
grant execute on function "api"."page_projects"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."get_project"(project uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_project"($1) $$;
revoke execute on function "api"."get_project"(uuid) from public, anon;
grant execute on function "api"."get_project"(uuid) to authenticated, service_role;

create or replace function "api"."save_iteration"(tenant uuid, iteration uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_iteration"($1, $2, $3) $$;
revoke execute on function "api"."save_iteration"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_iteration"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."work_item_actor"(profile jsonb default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."work_item_actor"($1) $$;
revoke execute on function "api"."work_item_actor"(jsonb) from public, anon;
grant execute on function "api"."work_item_actor"(jsonb) to authenticated, service_role;

create or replace function "api"."set_work_item_needs"(task uuid, ids uuid[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_work_item_needs"($1, $2) $$;
revoke execute on function "api"."set_work_item_needs"(uuid, uuid[]) from public, anon;
grant execute on function "api"."set_work_item_needs"(uuid, uuid[]) to authenticated, service_role;

create or replace function "api"."create_work_items"(tenant uuid, items jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_work_items"($1, $2) $$;
revoke execute on function "api"."create_work_items"(uuid, jsonb) from public, anon;
grant execute on function "api"."create_work_items"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."claim_work_item"(task uuid, lease integer default null, profile jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."claim_work_item"($1, $2, $3) $$;
revoke execute on function "api"."claim_work_item"(uuid, integer, jsonb) from public, anon;
grant execute on function "api"."claim_work_item"(uuid, integer, jsonb) to authenticated, service_role;

create or replace function "api"."claim_next_work_item"(tenant uuid, filter jsonb default null, lease integer default null, profile jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."claim_next_work_item"($1, $2, $3, $4) $$;
revoke execute on function "api"."claim_next_work_item"(uuid, jsonb, integer, jsonb) from public, anon;
grant execute on function "api"."claim_next_work_item"(uuid, jsonb, integer, jsonb) to authenticated, service_role;

create or replace function "api"."renew_work_item_claim"(task uuid, token uuid, lease integer default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."renew_work_item_claim"($1, $2, $3) $$;
revoke execute on function "api"."renew_work_item_claim"(uuid, uuid, integer) from public, anon;
grant execute on function "api"."renew_work_item_claim"(uuid, uuid, integer) to authenticated, service_role;

create or replace function "api"."release_work_item_claim"(task uuid, token uuid, note text default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."release_work_item_claim"($1, $2, $3) $$;
revoke execute on function "api"."release_work_item_claim"(uuid, uuid, text) from public, anon;
grant execute on function "api"."release_work_item_claim"(uuid, uuid, text) to authenticated, service_role;

create or replace function "api"."delegate_work_item"(task uuid, to_user uuid, profile jsonb default null, to_profile text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delegate_work_item"($1, $2, $3, $4) $$;
revoke execute on function "api"."delegate_work_item"(uuid, uuid, jsonb, text) from public, anon;
grant execute on function "api"."delegate_work_item"(uuid, uuid, jsonb, text) to authenticated, service_role;

create or replace function "api"."expire_work_item_claims"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."expire_work_item_claims"() $$;
revoke execute on function "api"."expire_work_item_claims"() from public, anon, authenticated;
grant execute on function "api"."expire_work_item_claims"() to service_role;

create or replace function "api"."hold_work_item"(task uuid, kind text, note text default null, ask_user_ids uuid[] default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."hold_work_item"($1, $2, $3, $4) $$;
revoke execute on function "api"."hold_work_item"(uuid, text, text, uuid[]) from public, anon;
grant execute on function "api"."hold_work_item"(uuid, text, text, uuid[]) to authenticated, service_role;

create or replace function "api"."release_work_item_hold"(task uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."release_work_item_hold"($1) $$;
revoke execute on function "api"."release_work_item_hold"(uuid) from public, anon;
grant execute on function "api"."release_work_item_hold"(uuid) to authenticated, service_role;

create or replace function "api"."close_work_item"(task uuid, outcome text, note text default null, stage uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."close_work_item"($1, $2, $3, $4) $$;
revoke execute on function "api"."close_work_item"(uuid, text, text, uuid) from public, anon;
grant execute on function "api"."close_work_item"(uuid, text, text, uuid) to authenticated, service_role;

create or replace function "api"."move_work_item"(task uuid, stage uuid default null, before uuid default null, after uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."move_work_item"($1, $2, $3, $4) $$;
revoke execute on function "api"."move_work_item"(uuid, uuid, uuid, uuid) from public, anon;
grant execute on function "api"."move_work_item"(uuid, uuid, uuid, uuid) to authenticated, service_role;

create or replace function "api"."move_work_items"(moves jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."move_work_items"($1) $$;
revoke execute on function "api"."move_work_items"(jsonb) from public, anon;
grant execute on function "api"."move_work_items"(jsonb) to authenticated, service_role;

create or replace function "api"."work_item_stage_times"(task uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."work_item_stage_times"($1) $$;
revoke execute on function "api"."work_item_stage_times"(uuid) from public, anon;
grant execute on function "api"."work_item_stage_times"(uuid) to authenticated, service_role;

create or replace function "api"."create_work_item_with_sla"(tenant uuid, attrs jsonb, assignees uuid[], subject_type text, priority text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_work_item_with_sla"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."create_work_item_with_sla"(uuid, jsonb, uuid[], text, text) from public, anon;
grant execute on function "api"."create_work_item_with_sla"(uuid, jsonb, uuid[], text, text) to authenticated, service_role;
