-- ==== alone: schema supabase/schemas/900_better_supabase_91_tasks.sql
-- better-supabase module: tasks
-- @bsb-block tasks@2 managed
-- Issues and tasks on pipelines: identifiers, parents without cycles, several assignees, priority 0 to 4, estimates, start, end and due dates, locking, projects, iterations, batched edits and a progress tree.
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
alter table "better_supabase"."projects" enable row level security;
revoke all on "better_supabase"."projects" from anon, authenticated;
grant select on "better_supabase"."projects" to authenticated;
grant all on "better_supabase"."projects" to service_role;
drop policy if exists projects_read on "better_supabase"."projects";
create policy projects_read on "better_supabase"."projects" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

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
revoke all on "better_supabase"."iterations" from anon, authenticated;
grant select on "better_supabase"."iterations" to authenticated;
grant all on "better_supabase"."iterations" to service_role;
drop policy if exists iterations_read on "better_supabase"."iterations";
create policy iterations_read on "better_supabase"."iterations" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

create table if not exists "better_supabase"."work_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "title" text not null check (length("title") between 1 and 500),
  "body" text,
  "parent_id" uuid references "better_supabase"."work_items" ("id") on delete cascade,
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
create index if not exists work_items_board_idx on "better_supabase"."work_items" ("pipeline_id", "stage_id", "rank");
create index if not exists work_items_parent_idx on "better_supabase"."work_items" ("parent_id");
create index if not exists work_items_project_idx on "better_supabase"."work_items" ("project_id");
create index if not exists work_items_iteration_idx on "better_supabase"."work_items" ("iteration_id");
create index if not exists work_items_due_idx on "better_supabase"."work_items" ("tenant_id", "due_at") where "closed_at" is null;
alter table "better_supabase"."work_items" enable row level security;
revoke all on "better_supabase"."work_items" from anon, authenticated;
grant select on "better_supabase"."work_items" to authenticated;
grant all on "better_supabase"."work_items" to service_role;
drop policy if exists work_items_read on "better_supabase"."work_items";
create policy work_items_read on "better_supabase"."work_items" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

create table if not exists "better_supabase"."work_item_assignees" (
  "tenant_id" uuid not null,
  "work_item_id" uuid not null references "better_supabase"."work_items" ("id") on delete cascade,
  "user_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("work_item_id", "user_id")
);
create index if not exists work_item_assignees_user_idx on "better_supabase"."work_item_assignees" ("user_id");
alter table "better_supabase"."work_item_assignees" enable row level security;
revoke all on "better_supabase"."work_item_assignees" from anon, authenticated;
grant select on "better_supabase"."work_item_assignees" to authenticated;
grant all on "better_supabase"."work_item_assignees" to service_role;
drop policy if exists work_item_assignees_read on "better_supabase"."work_item_assignees";
create policy work_item_assignees_read on "better_supabase"."work_item_assignees" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

alter table "better_supabase"."work_items" add column if not exists "recurs_from" uuid references "better_supabase"."work_items" ("id") on delete set null;
create unique index if not exists work_items_recurs_from_idx on "better_supabase"."work_items" ("recurs_from");

create table if not exists "better_supabase"."work_item_checklist_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "work_item_id" uuid not null references "better_supabase"."work_items" ("id") on delete cascade,
  "title" text not null check (length("title") between 1 and 500),
  "done" boolean not null default false,
  "done_at" timestamptz,
  "done_by" uuid,
  "rank" text collate "C" not null check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
create index if not exists work_item_checklist_item_idx on "better_supabase"."work_item_checklist_items" ("work_item_id", "rank");
alter table "better_supabase"."work_item_checklist_items" enable row level security;
revoke all on "better_supabase"."work_item_checklist_items" from anon, authenticated;
grant select on "better_supabase"."work_item_checklist_items" to authenticated;
grant all on "better_supabase"."work_item_checklist_items" to service_role;
drop policy if exists work_item_checklist_items_read on "better_supabase"."work_item_checklist_items";
create policy work_item_checklist_items_read on "better_supabase"."work_item_checklist_items" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

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
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'WORK_ITEM_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "better_supabase"."work_items" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
      raise exception 'the parent is in another organization' using errcode = '22023', hint = 'WORK_ITEM_PARENT_INVALID';
    end if;
  end if;
  if tg_op = 'UPDATE' and old."locked" and not (auth.role() = 'service_role') and (new."start_at" is distinct from old."start_at" or new."end_at" is distinct from old."end_at" or new."due_at" is distinct from old."due_at") then
    raise exception 'the item is locked; its dates can''t change' using errcode = '55000', hint = 'WORK_ITEM_LOCKED';
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
drop trigger if exists bsb_work_item_guard on "better_supabase"."work_items";
create trigger bsb_work_item_guard before insert or update on "better_supabase"."work_items"
for each row execute function better_supabase.bsb_work_item_guard();

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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_work_item.tenant, 'work_items.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'WORK_ITEM_FORBIDDEN';
  end if;
  if nullif(trim(create_work_item.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'WORK_ITEM_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_work_item.tenant, create_work_item.attrs;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_work_item.tenant::text || ':work_item', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."work_items" x where x."tenant_id" = create_work_item.tenant;
  v_identifier := 'TASK-' || v_seq::text;
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
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'WORK_ITEM_ATTRS_INVALID';
  end;
  if cardinality(coalesce(create_work_item.assignees, '{}')) > 0 then
    perform "better_supabase"."set_work_item_assignees"(v_id, create_work_item.assignees);
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = v_id;
  if jsonb_array_length(coalesce((create_work_item.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      raise exception 'install the attachments block to attach files' using errcode = '0A000', hint = 'WORK_ITEM_ATTACHMENTS_UNAVAILABLE';
    end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_work_item_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id")) from "better_supabase"."work_items" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_work_item"(uuid, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."create_work_item"(uuid, jsonb, uuid[]) to authenticated, service_role;

-- Applies a batch of { workItemId, field, value } changes, each on its
-- own. Returns { accepted: [{ workItemId, field }], rejected: [{ workItemId,
-- field, hint, reason }] }.
create or replace function "better_supabase"."update_work_items"(changes jsonb)
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
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_work_items.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { workItemId, field, value }' using errcode = '22023', hint = 'WORK_ITEM_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_work_items.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'workItemId')::uuid;
      if not exists (select 1 from "better_supabase"."work_items" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
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
      when 'attachments' then
        select * into v_row from "better_supabase"."work_items" x where x."id" = v_item;
        if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      raise exception 'install the attachments block to attach files' using errcode = '0A000', hint = 'WORK_ITEM_ATTACHMENTS_UNAVAILABLE';
    end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'WORK_ITEM_FIELD_UNKNOWN';
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
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_change ->> 'workItemId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."work_items" x where x."id" = any (v_touched) loop
    null;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "better_supabase"."update_work_items"(jsonb) from public, anon;
grant execute on function "better_supabase"."update_work_items"(jsonb) to authenticated, service_role;

-- Replaces an item's assignees. Each one watches the item, and those who
-- weren't assigned before are notified.
create or replace function "better_supabase"."set_work_item_assignees"(work_item uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_work_item_assignees.users, '{}')) x where x is not null);
  v_new uuid[];
  v_user uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = set_work_item_assignees.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
  end if;
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."work_item_assignees" ("tenant_id", "work_item_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  null;
  return cardinality(v_users);
end;
$$;
revoke execute on function "better_supabase"."set_work_item_assignees"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."set_work_item_assignees"(uuid, uuid[]) to authenticated, service_role;

create or replace function "better_supabase"."archive_work_item"(work_item uuid, archived boolean)
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
  update "better_supabase"."work_items" x set "archived_at" = case when archive_work_item.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_work_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_work_item.archived then
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_work_item"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_work_item"(uuid, boolean) to authenticated, service_role;

-- Deletes an item and its children. Needs work_items.manage, or its author.
create or replace function "better_supabase"."delete_work_item"(work_item uuid)
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
  where x."id" = delete_work_item.work_item
    and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_work_item"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_work_item"(uuid) to authenticated, service_role;

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
    select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id")) as value, x."number" as number
    from "better_supabase"."work_items" x
    where x."tenant_id" = list_work_items.tenant and x."archived_at" is null
      and (list_work_items.filter ->> 'teamId' is null or x."team_id" = (list_work_items.filter ->> 'teamId')::uuid)
      and (list_work_items.filter ->> 'projectId' is null or x."project_id" = (list_work_items.filter ->> 'projectId')::uuid)
      and (list_work_items.filter ->> 'iterationId' is null or x."iteration_id" = (list_work_items.filter ->> 'iterationId')::uuid)
      and (list_work_items.filter ->> 'parentId' is null or x."parent_id" = (list_work_items.filter ->> 'parentId')::uuid)
      and (list_work_items.filter ->> 'assigneeId' is null or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and y."user_id" = (list_work_items.filter ->> 'assigneeId')::uuid))
      and (list_work_items.filter -> 'states' is null or x."state" = any (array(select jsonb_array_elements_text(list_work_items.filter -> 'states'))))
      and (coalesce((list_work_items.filter ->> 'open')::boolean, false) = false or x."closed_at" is null)
      and (list_work_items.search is null or x."title" ilike '%' || list_work_items.search || '%' or x."identifier" ilike list_work_items.search || '%')
      and (list_work_items.after is null or x."number" < (select z."number" from "better_supabase"."work_items" z where z."id" = list_work_items.after))
    order by x."number" desc
    limit least(greatest(coalesce(list_work_items.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."list_work_items"(uuid, jsonb, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_work_items"(uuid, jsonb, text, uuid, integer) to authenticated, service_role;

-- Adds a checklist item (checklist_item null) or changes one: title, done,
-- rank. A new item without a rank goes last.
create or replace function "better_supabase"."save_work_item_checklist_item"(work_item uuid, checklist_item uuid, attrs jsonb)
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
  select * into v_row from "better_supabase"."work_items" x where x."id" = save_work_item_checklist_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
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
        raise exception 'no such checklist item on this work item' using errcode = 'P0002', hint = 'WORK_ITEM_CHECKLIST_ITEM_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a checklist item needs a title of 1 to 500 characters and a valid rank' using errcode = '22023', hint = 'WORK_ITEM_CHECKLIST_ITEM_INVALID';
  end;
  null;
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
  where y."id" = delete_work_item_checklist_item.checklist_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    return false;
  end if;
  delete from "better_supabase"."work_item_checklist_items" y where y."id" = delete_work_item_checklist_item.checklist_item;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_work_item_checklist_item"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_work_item_checklist_item"(uuid) to authenticated, service_role;

-- An item's checklist, in rank order.
create or replace function "better_supabase"."list_work_item_checklist"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'workItemId', y."work_item_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") order by y."rank" collate "C", y."id"), '[]'::jsonb)
  from "better_supabase"."work_item_checklist_items" y where y."work_item_id" = list_work_item_checklist.work_item
$$;
revoke execute on function "better_supabase"."list_work_item_checklist"(uuid) from public, anon;
grant execute on function "better_supabase"."list_work_item_checklist"(uuid) to authenticated, service_role;

-- One item the caller can read, or null.
create or replace function "better_supabase"."get_work_item"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id")) from "better_supabase"."work_items" x where x."id" = get_work_item.work_item
$$;
revoke execute on function "better_supabase"."get_work_item"(uuid) from public, anon;
grant execute on function "better_supabase"."get_work_item"(uuid) to authenticated, service_role;

-- Creates a project (project null) or changes the keys attrs names: key,
-- name, ownerId, status, startOn, targetOn, archived.
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_project.tenant, 'work_items.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'WORK_ITEM_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."projects" ("tenant_id", "key", "name", "owner_user_id", "status", "start_on", "target_on")
      values (save_project.tenant, upper(save_project.attrs ->> 'key'), save_project.attrs ->> 'name', (save_project.attrs ->> 'ownerId')::uuid,
        coalesce(save_project.attrs ->> 'status', 'planned'), (save_project.attrs ->> 'startOn')::date, (save_project.attrs ->> 'targetOn')::date)
      returning "id" into v_id;
    else
      update "better_supabase"."projects" x set
        "key" = coalesce(upper(save_project.attrs ->> 'key'), x."key"),
        "name" = coalesce(save_project.attrs ->> 'name', x."name"),
        "owner_user_id" = case when save_project.attrs ? 'ownerId' then (save_project.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
        "status" = coalesce(save_project.attrs ->> 'status', x."status"),
        "start_on" = case when save_project.attrs ? 'startOn' then (save_project.attrs ->> 'startOn')::date else x."start_on" end,
        "target_on" = case when save_project.attrs ? 'targetOn' then (save_project.attrs ->> 'targetOn')::date else x."target_on" end,
        "archived_at" = case when save_project.attrs ? 'archived' then (case when (save_project.attrs ->> 'archived')::boolean then coalesce(x."archived_at", now()) end) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_project.tenant;
      if not found then
        raise exception 'project not found' using errcode = 'P0002', hint = 'WORK_ITEM_PROJECT_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another project has this key' using errcode = '23505', hint = 'WORK_ITEM_PROJECT_KEY_TAKEN';
  when check_violation or not_null_violation then
    raise exception 'a project needs a key of capitals and a name, and ends after it starts' using errcode = '22023', hint = 'WORK_ITEM_PROJECT_INVALID';
  end;
  return (select to_jsonb(x) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_iteration.tenant, 'work_items.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'WORK_ITEM_FORBIDDEN';
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
        raise exception 'iteration not found' using errcode = 'P0002', hint = 'WORK_ITEM_ITERATION_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation then
    raise exception 'an iteration needs a name and ends on or after it starts' using errcode = '22023', hint = 'WORK_ITEM_ITERATION_INVALID';
  end;
  return (select to_jsonb(x) from "better_supabase"."iterations" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_iteration"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_iteration"(uuid, uuid, jsonb) to authenticated, service_role;

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_91_tasks.sql
-- better-supabase module: tasks
-- @bsb-block-data tasks
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_91_tasks.sql
-- better-supabase module: tasks
-- @bsb-block tasks@2 managed
-- Issues and tasks on pipelines: identifiers, parents without cycles, several assignees, priority 0 to 4, estimates, start, end and due dates, locking, projects, iterations, batched edits and a progress tree.
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
alter table "better_supabase"."projects" enable row level security;
revoke all on "better_supabase"."projects" from anon, authenticated;
grant select on "better_supabase"."projects" to authenticated;
grant all on "better_supabase"."projects" to service_role;
drop policy if exists projects_read on "better_supabase"."projects";
create policy projects_read on "better_supabase"."projects" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

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
revoke all on "better_supabase"."iterations" from anon, authenticated;
grant select on "better_supabase"."iterations" to authenticated;
grant all on "better_supabase"."iterations" to service_role;
drop policy if exists iterations_read on "better_supabase"."iterations";
create policy iterations_read on "better_supabase"."iterations" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

create table if not exists "better_supabase"."work_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "title" text not null check (length("title") between 1 and 500),
  "body" text,
  "parent_id" uuid references "better_supabase"."work_items" ("id") on delete cascade,
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
create index if not exists work_items_board_idx on "better_supabase"."work_items" ("pipeline_id", "stage_id", "rank");
create index if not exists work_items_parent_idx on "better_supabase"."work_items" ("parent_id");
create index if not exists work_items_project_idx on "better_supabase"."work_items" ("project_id");
create index if not exists work_items_iteration_idx on "better_supabase"."work_items" ("iteration_id");
create index if not exists work_items_due_idx on "better_supabase"."work_items" ("tenant_id", "due_at") where "closed_at" is null;
alter table "better_supabase"."work_items" enable row level security;
revoke all on "better_supabase"."work_items" from anon, authenticated;
grant select on "better_supabase"."work_items" to authenticated;
grant all on "better_supabase"."work_items" to service_role;
drop policy if exists work_items_read on "better_supabase"."work_items";
create policy work_items_read on "better_supabase"."work_items" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

create table if not exists "better_supabase"."work_item_assignees" (
  "tenant_id" uuid not null,
  "work_item_id" uuid not null references "better_supabase"."work_items" ("id") on delete cascade,
  "user_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("work_item_id", "user_id")
);
create index if not exists work_item_assignees_user_idx on "better_supabase"."work_item_assignees" ("user_id");
alter table "better_supabase"."work_item_assignees" enable row level security;
revoke all on "better_supabase"."work_item_assignees" from anon, authenticated;
grant select on "better_supabase"."work_item_assignees" to authenticated;
grant all on "better_supabase"."work_item_assignees" to service_role;
drop policy if exists work_item_assignees_read on "better_supabase"."work_item_assignees";
create policy work_item_assignees_read on "better_supabase"."work_item_assignees" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

alter table "better_supabase"."work_items" add column if not exists "recurs_from" uuid references "better_supabase"."work_items" ("id") on delete set null;
create unique index if not exists work_items_recurs_from_idx on "better_supabase"."work_items" ("recurs_from");

create table if not exists "better_supabase"."work_item_checklist_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "work_item_id" uuid not null references "better_supabase"."work_items" ("id") on delete cascade,
  "title" text not null check (length("title") between 1 and 500),
  "done" boolean not null default false,
  "done_at" timestamptz,
  "done_by" uuid,
  "rank" text collate "C" not null check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
create index if not exists work_item_checklist_item_idx on "better_supabase"."work_item_checklist_items" ("work_item_id", "rank");
alter table "better_supabase"."work_item_checklist_items" enable row level security;
revoke all on "better_supabase"."work_item_checklist_items" from anon, authenticated;
grant select on "better_supabase"."work_item_checklist_items" to authenticated;
grant all on "better_supabase"."work_item_checklist_items" to service_role;
drop policy if exists work_item_checklist_items_read on "better_supabase"."work_item_checklist_items";
create policy work_item_checklist_items_read on "better_supabase"."work_item_checklist_items" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

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
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'WORK_ITEM_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "better_supabase"."work_items" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
      raise exception 'the parent is in another organization' using errcode = '22023', hint = 'WORK_ITEM_PARENT_INVALID';
    end if;
  end if;
  if tg_op = 'UPDATE' and old."locked" and not (auth.role() = 'service_role') and (new."start_at" is distinct from old."start_at" or new."end_at" is distinct from old."end_at" or new."due_at" is distinct from old."due_at") then
    raise exception 'the item is locked; its dates can''t change' using errcode = '55000', hint = 'WORK_ITEM_LOCKED';
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
      perform "better_supabase".emit_event('work_item.closed', jsonb_build_object('organizationId', new."tenant_id", 'workItemId', new."id", 'subjectType', 'work_item', 'subjectId', new."id"::text, 'title', new."title", 'state', new."state", 'closeReason', new."close_reason"), 'work-items/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/tasks');
    elsif not (new."state" in ('completed', 'canceled')) and old."state" in ('completed', 'canceled') then
      new."closed_at" := null;
      new."close_reason" := null;
      perform "better_supabase".emit_event('work_item.reopened', jsonb_build_object('organizationId', new."tenant_id", 'workItemId', new."id", 'subjectType', 'work_item', 'subjectId', new."id"::text, 'title', new."title"), 'work-items/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/tasks');
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_work_item_guard() from public, anon, authenticated;
drop trigger if exists bsb_work_item_guard on "better_supabase"."work_items";
create trigger bsb_work_item_guard before insert or update on "better_supabase"."work_items"
for each row execute function better_supabase.bsb_work_item_guard();

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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_work_item.tenant, 'work_items.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'WORK_ITEM_FORBIDDEN';
  end if;
  if nullif(trim(create_work_item.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'WORK_ITEM_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_work_item.tenant, create_work_item.attrs;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_work_item.tenant::text || ':work_item', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."work_items" x where x."tenant_id" = create_work_item.tenant;
  v_identifier := 'TASK-' || v_seq::text;
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
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'WORK_ITEM_ATTRS_INVALID';
  end;
  if cardinality(coalesce(create_work_item.assignees, '{}')) > 0 then
    perform "better_supabase"."set_work_item_assignees"(v_id, create_work_item.assignees);
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = v_id;
  if jsonb_typeof(coalesce((create_work_item.attrs -> 'attachments'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'WORK_ITEM_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((create_work_item.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'work_item', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((create_work_item.attrs -> 'attachments'))::uuid))
        and f."organization_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'work_item' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((create_work_item.attrs -> 'attachments')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'WORK_ITEM_ATTACHMENTS_INVALID';
      end if;
    end if;
  perform "better_supabase".emit_event('work_item.created', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_work_item_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) from "better_supabase"."work_items" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_work_item"(uuid, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."create_work_item"(uuid, jsonb, uuid[]) to authenticated, service_role;

-- Applies a batch of { workItemId, field, value } changes, each on its
-- own. Returns { accepted: [{ workItemId, field }], rejected: [{ workItemId,
-- field, hint, reason }] }.
create or replace function "better_supabase"."update_work_items"(changes jsonb)
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
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_work_items.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { workItemId, field, value }' using errcode = '22023', hint = 'WORK_ITEM_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_work_items.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'workItemId')::uuid;
      if not exists (select 1 from "better_supabase"."work_items" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
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
      when 'attachments' then
        select * into v_row from "better_supabase"."work_items" x where x."id" = v_item;
        if jsonb_typeof(coalesce((v_change -> 'value'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'WORK_ITEM_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'work_item', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((v_change -> 'value'))::uuid))
        and f."organization_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'work_item' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((v_change -> 'value')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'WORK_ITEM_ATTACHMENTS_INVALID';
      end if;
    end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'WORK_ITEM_FIELD_UNKNOWN';
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
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_change ->> 'workItemId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."work_items" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'workItemId')::uuid = v_row."id")), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "better_supabase"."update_work_items"(jsonb) from public, anon;
grant execute on function "better_supabase"."update_work_items"(jsonb) to authenticated, service_role;

-- Replaces an item's assignees. Each one watches the item, and those who
-- weren't assigned before are notified.
create or replace function "better_supabase"."set_work_item_assignees"(work_item uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_work_item_assignees.users, '{}')) x where x is not null);
  v_new uuid[];
  v_user uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = set_work_item_assignees.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
  end if;
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."work_item_assignees" ("tenant_id", "work_item_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  foreach v_user in array v_users loop
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_row."tenant_id", v_user, 'work_item', v_row."id"::text, 'participating')
    on conflict do nothing;
  end loop;
  if cardinality(v_new) > 0 then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'work_item.assigned',
      'tenant', v_row."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'work_item',
      'subject_id', v_row."id"::text,
      'summary', v_row."title",
      'recipients', to_jsonb(v_new),
      'watchers', false,
      'key', 'work_item.assigned:' || v_row."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('workItemId', v_row."id")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  perform "better_supabase".emit_event('work_item.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(v_users)), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return cardinality(v_users);
end;
$$;
revoke execute on function "better_supabase"."set_work_item_assignees"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."set_work_item_assignees"(uuid, uuid[]) to authenticated, service_role;

create or replace function "better_supabase"."archive_work_item"(work_item uuid, archived boolean)
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
  update "better_supabase"."work_items" x set "archived_at" = case when archive_work_item.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_work_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_work_item.archived then
    perform "better_supabase".emit_event('work_item.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_work_item"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_work_item"(uuid, boolean) to authenticated, service_role;

-- Deletes an item and its children. Needs work_items.manage, or its author.
create or replace function "better_supabase"."delete_work_item"(work_item uuid)
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
  where x."id" = delete_work_item.work_item
    and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  perform "better_supabase".emit_event('work_item.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_work_item"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_work_item"(uuid) to authenticated, service_role;

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
    select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) as value, x."number" as number
    from "better_supabase"."work_items" x
    where x."tenant_id" = list_work_items.tenant and x."archived_at" is null
      and (list_work_items.filter ->> 'teamId' is null or x."team_id" = (list_work_items.filter ->> 'teamId')::uuid)
      and (list_work_items.filter ->> 'projectId' is null or x."project_id" = (list_work_items.filter ->> 'projectId')::uuid)
      and (list_work_items.filter ->> 'iterationId' is null or x."iteration_id" = (list_work_items.filter ->> 'iterationId')::uuid)
      and (list_work_items.filter ->> 'parentId' is null or x."parent_id" = (list_work_items.filter ->> 'parentId')::uuid)
      and (list_work_items.filter ->> 'assigneeId' is null or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and y."user_id" = (list_work_items.filter ->> 'assigneeId')::uuid))
      and (list_work_items.filter -> 'states' is null or x."state" = any (array(select jsonb_array_elements_text(list_work_items.filter -> 'states'))))
      and (coalesce((list_work_items.filter ->> 'open')::boolean, false) = false or x."closed_at" is null)
      and (list_work_items.search is null or x."title" ilike '%' || list_work_items.search || '%' or x."identifier" ilike list_work_items.search || '%')
      and (list_work_items.after is null or x."number" < (select z."number" from "better_supabase"."work_items" z where z."id" = list_work_items.after))
    order by x."number" desc
    limit least(greatest(coalesce(list_work_items.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."list_work_items"(uuid, jsonb, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_work_items"(uuid, jsonb, text, uuid, integer) to authenticated, service_role;

-- Adds a checklist item (checklist_item null) or changes one: title, done,
-- rank. A new item without a rank goes last.
create or replace function "better_supabase"."save_work_item_checklist_item"(work_item uuid, checklist_item uuid, attrs jsonb)
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
  select * into v_row from "better_supabase"."work_items" x where x."id" = save_work_item_checklist_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
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
        raise exception 'no such checklist item on this work item' using errcode = 'P0002', hint = 'WORK_ITEM_CHECKLIST_ITEM_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a checklist item needs a title of 1 to 500 characters and a valid rank' using errcode = '22023', hint = 'WORK_ITEM_CHECKLIST_ITEM_INVALID';
  end;
  perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist')), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
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
  where y."id" = delete_work_item_checklist_item.checklist_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    return false;
  end if;
  delete from "better_supabase"."work_item_checklist_items" y where y."id" = delete_work_item_checklist_item.checklist_item;
  perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist')), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_work_item_checklist_item"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_work_item_checklist_item"(uuid) to authenticated, service_role;

-- An item's checklist, in rank order.
create or replace function "better_supabase"."list_work_item_checklist"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'workItemId', y."work_item_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") order by y."rank" collate "C", y."id"), '[]'::jsonb)
  from "better_supabase"."work_item_checklist_items" y where y."work_item_id" = list_work_item_checklist.work_item
$$;
revoke execute on function "better_supabase"."list_work_item_checklist"(uuid) from public, anon;
grant execute on function "better_supabase"."list_work_item_checklist"(uuid) to authenticated, service_role;

-- One item the caller can read, or null.
create or replace function "better_supabase"."get_work_item"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) from "better_supabase"."work_items" x where x."id" = get_work_item.work_item
$$;
revoke execute on function "better_supabase"."get_work_item"(uuid) from public, anon;
grant execute on function "better_supabase"."get_work_item"(uuid) to authenticated, service_role;

-- Makes an item repeat: rrule is an RFC 5545 RRULE starting at the item's
-- due date (now without one) in tzid. A null rrule stops it. Completing the
-- item then creates the next one through repeat_work_item.
create or replace function "better_supabase"."set_work_item_recurrence"(work_item uuid, rrule text, tzid text default 'UTC')
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
  select * into v_row from "better_supabase"."work_items" x where x."id" = set_work_item_recurrence.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
  end if;
  if set_work_item_recurrence.rrule is null then
    delete from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = v_row."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = v_row."id"::text;
  else
    if set_work_item_recurrence.rrule !~ '^(RRULE:)?FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)(;[A-Z]+=[-+,0-9A-Z]+)*$' then
      raise exception 'rrule must be an RRULE such as FREQ=WEEKLY;BYDAY=MO' using errcode = '22023', hint = 'WORK_ITEM_RECURRENCE_INVALID';
    end if;
    if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = coalesce(set_work_item_recurrence.tzid, 'UTC')) then
      raise exception 'tzid must be an IANA time zone' using errcode = '22023', hint = 'WORK_ITEM_RECURRENCE_INVALID';
    end if;
    insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
    values (v_row."tenant_id", 'work_item', v_row."id"::text, coalesce(v_row."due_at", now()), coalesce(set_work_item_recurrence.tzid, 'UTC'), regexp_replace(set_work_item_recurrence.rrule, '^RRULE:', ''))
    on conflict ("tenant_id", "subject_type", "subject_id")
    do update set "dtstart" = excluded."dtstart", "tzid" = excluded."tzid", "rrule" = excluded."rrule";
  end if;
  perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('recurrence')), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) -> 'recurrence' from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."set_work_item_recurrence"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."set_work_item_recurrence"(uuid, text, text) to authenticated, service_role;

-- Creates the next item of a repeating item, due at due_at: a copy with its
-- dates shifted, its assignees and an unchecked checklist. The rule moves to
-- the copy. Runs once per item; a second call returns the same copy.
create or replace function "better_supabase"."repeat_work_item"(work_item uuid, due_at timestamptz)
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
  select * into v_src from "better_supabase"."work_items" x where x."id" = repeat_work_item.work_item for update;
  if v_src."id" is null then
    raise exception 'work item not found' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
  end if;
  select x."id" into v_id from "better_supabase"."work_items" x where x."recurs_from" = v_src."id";
  if v_id is not null then
    return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) from "better_supabase"."work_items" x where x."id" = v_id);
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
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) from "better_supabase"."work_items" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."repeat_work_item"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."repeat_work_item"(uuid, timestamptz) to service_role;

-- Watches (all), follows (participating) or ignores an item the caller can
-- read; a null level removes the choice.
create or replace function "better_supabase"."watch_work_item"(work_item uuid, level text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
begin
  select * into v_row from "better_supabase"."work_items" x where x."id" = watch_work_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.read'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can read' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
  end if;
  perform "better_supabase"."set_notification_subscription"('work_item', v_row."id"::text, watch_work_item.level, v_row."tenant_id");
  return watch_work_item.level is not null;
end;
$$;
revoke execute on function "better_supabase"."watch_work_item"(uuid, text) from public, anon;
grant execute on function "better_supabase"."watch_work_item"(uuid, text) to authenticated, service_role;

-- Who watches (all) or follows (participating) an item: [{ userId, level }].
create or replace function "better_supabase"."list_work_item_watchers"(work_item uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', s."user_id", 'level', s."level") order by s."level", s."user_id"), '[]'::jsonb)
  from "better_supabase"."work_items" x
  join "better_supabase"."notification_subscriptions" s on s."subject_type" = 'work_item' and s."subject_id" = x."id"::text
    and s."organization_id" = x."tenant_id"
  where x."id" = list_work_item_watchers.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.read'), false)) and s."level" in ('all', 'participating')
$$;
revoke execute on function "better_supabase"."list_work_item_watchers"(uuid) from public, anon;
grant execute on function "better_supabase"."list_work_item_watchers"(uuid) to authenticated, service_role;

-- Creates a project (project null) or changes the keys attrs names: key,
-- name, ownerId, status, startOn, targetOn, archived.
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_project.tenant, 'work_items.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'WORK_ITEM_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."projects" ("tenant_id", "key", "name", "owner_user_id", "status", "start_on", "target_on")
      values (save_project.tenant, upper(save_project.attrs ->> 'key'), save_project.attrs ->> 'name', (save_project.attrs ->> 'ownerId')::uuid,
        coalesce(save_project.attrs ->> 'status', 'planned'), (save_project.attrs ->> 'startOn')::date, (save_project.attrs ->> 'targetOn')::date)
      returning "id" into v_id;
    else
      update "better_supabase"."projects" x set
        "key" = coalesce(upper(save_project.attrs ->> 'key'), x."key"),
        "name" = coalesce(save_project.attrs ->> 'name', x."name"),
        "owner_user_id" = case when save_project.attrs ? 'ownerId' then (save_project.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
        "status" = coalesce(save_project.attrs ->> 'status', x."status"),
        "start_on" = case when save_project.attrs ? 'startOn' then (save_project.attrs ->> 'startOn')::date else x."start_on" end,
        "target_on" = case when save_project.attrs ? 'targetOn' then (save_project.attrs ->> 'targetOn')::date else x."target_on" end,
        "archived_at" = case when save_project.attrs ? 'archived' then (case when (save_project.attrs ->> 'archived')::boolean then coalesce(x."archived_at", now()) end) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_project.tenant;
      if not found then
        raise exception 'project not found' using errcode = 'P0002', hint = 'WORK_ITEM_PROJECT_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another project has this key' using errcode = '23505', hint = 'WORK_ITEM_PROJECT_KEY_TAKEN';
  when check_violation or not_null_violation then
    raise exception 'a project needs a key of capitals and a name, and ends after it starts' using errcode = '22023', hint = 'WORK_ITEM_PROJECT_INVALID';
  end;
  return (select to_jsonb(x) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_iteration.tenant, 'work_items.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'WORK_ITEM_FORBIDDEN';
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
        raise exception 'iteration not found' using errcode = 'P0002', hint = 'WORK_ITEM_ITERATION_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation then
    raise exception 'an iteration needs a name and ends on or after it starts' using errcode = '22023', hint = 'WORK_ITEM_ITERATION_INVALID';
  end;
  return (select to_jsonb(x) from "better_supabase"."iterations" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_iteration"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_iteration"(uuid, uuid, jsonb) to authenticated, service_role;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_91_tasks.sql
-- better-supabase module: tasks
-- @bsb-block-data tasks
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_91_tasks.sql
-- better-supabase module: tasks
-- @bsb-block tasks@2 managed
-- Issues and tasks on pipelines: identifiers, parents without cycles, several assignees, priority 0 to 4, estimates, start, end and due dates, locking, projects, iterations, batched edits and a progress tree.
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
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
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
alter table "app_private"."projects" enable row level security;
revoke all on "app_private"."projects" from anon, authenticated;
grant select on "app_private"."projects" to authenticated;
grant all on "app_private"."projects" to service_role;
drop policy if exists projects_read on "app_private"."projects";
create policy projects_read on "app_private"."projects" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

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
revoke all on "app_private"."iterations" from anon, authenticated;
grant select on "app_private"."iterations" to authenticated;
grant all on "app_private"."iterations" to service_role;
drop policy if exists iterations_read on "app_private"."iterations";
create policy iterations_read on "app_private"."iterations" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

create table if not exists "app_private"."work_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "title" text not null check (length("title") between 1 and 500),
  "body" text,
  "parent_id" uuid references "app_private"."work_items" ("id") on delete cascade,
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
create index if not exists work_items_board_idx on "app_private"."work_items" ("pipeline_id", "stage_id", "rank");
create index if not exists work_items_parent_idx on "app_private"."work_items" ("parent_id");
create index if not exists work_items_project_idx on "app_private"."work_items" ("project_id");
create index if not exists work_items_iteration_idx on "app_private"."work_items" ("iteration_id");
create index if not exists work_items_due_idx on "app_private"."work_items" ("tenant_id", "due_at") where "closed_at" is null;
alter table "app_private"."work_items" enable row level security;
revoke all on "app_private"."work_items" from anon, authenticated;
grant select on "app_private"."work_items" to authenticated;
grant all on "app_private"."work_items" to service_role;
drop policy if exists work_items_read on "app_private"."work_items";
create policy work_items_read on "app_private"."work_items" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

create table if not exists "app_private"."work_item_assignees" (
  "tenant_id" uuid not null,
  "work_item_id" uuid not null references "app_private"."work_items" ("id") on delete cascade,
  "user_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("work_item_id", "user_id")
);
create index if not exists work_item_assignees_user_idx on "app_private"."work_item_assignees" ("user_id");
alter table "app_private"."work_item_assignees" enable row level security;
revoke all on "app_private"."work_item_assignees" from anon, authenticated;
grant select on "app_private"."work_item_assignees" to authenticated;
grant all on "app_private"."work_item_assignees" to service_role;
drop policy if exists work_item_assignees_read on "app_private"."work_item_assignees";
create policy work_item_assignees_read on "app_private"."work_item_assignees" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

alter table "app_private"."work_items" add column if not exists "recurs_from" uuid references "app_private"."work_items" ("id") on delete set null;
create unique index if not exists work_items_recurs_from_idx on "app_private"."work_items" ("recurs_from");

create table if not exists "app_private"."work_item_checklist_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "work_item_id" uuid not null references "app_private"."work_items" ("id") on delete cascade,
  "title" text not null check (length("title") between 1 and 500),
  "done" boolean not null default false,
  "done_at" timestamptz,
  "done_by" uuid,
  "rank" text collate "C" not null check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
create index if not exists work_item_checklist_item_idx on "app_private"."work_item_checklist_items" ("work_item_id", "rank");
alter table "app_private"."work_item_checklist_items" enable row level security;
revoke all on "app_private"."work_item_checklist_items" from anon, authenticated;
grant select on "app_private"."work_item_checklist_items" to authenticated;
grant all on "app_private"."work_item_checklist_items" to service_role;
drop policy if exists work_item_checklist_items_read on "app_private"."work_item_checklist_items";
create policy work_item_checklist_items_read on "app_private"."work_item_checklist_items" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

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
        select x."parent_id", up.depth + 1 from "app_private"."work_items" x join up on x."id" = up.id
        where x."parent_id" is not null and up.depth < 100
      )
      select 1 from up where up.id = new."id"
    ) then
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'WORK_ITEM_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "app_private"."work_items" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
      raise exception 'the parent is in another organization' using errcode = '22023', hint = 'WORK_ITEM_PARENT_INVALID';
    end if;
  end if;
  if tg_op = 'UPDATE' and old."locked" and not (auth.role() = 'service_role') and (new."start_at" is distinct from old."start_at" or new."end_at" is distinct from old."end_at" or new."due_at" is distinct from old."due_at") then
    raise exception 'the item is locked; its dates can''t change' using errcode = '55000', hint = 'WORK_ITEM_LOCKED';
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
drop trigger if exists bsb_work_item_guard on "app_private"."work_items";
create trigger bsb_work_item_guard before insert or update on "app_private"."work_items"
for each row execute function better_supabase.bsb_work_item_guard();

-- Creates a work item. attrs: title (required), body, parentId, teamId,
-- projectId, iterationId, priority (0 none to 4 low, as Linear), estimate,
-- progress, startAt, endAt, dueAt, pipelineId, stageId, and fields (the
-- extra columns, by name). assignees: user ids.
create or replace function "app_private"."create_work_item"(tenant uuid, attrs jsonb, assignees uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seq bigint;
  v_identifier text;
  v_id uuid;
  v_row "app_private"."work_items";
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_work_item.tenant, 'work_items.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'WORK_ITEM_FORBIDDEN';
  end if;
  if nullif(trim(create_work_item.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'WORK_ITEM_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_work_item.tenant, create_work_item.attrs;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_work_item.tenant::text || ':work_item', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "app_private"."work_items" x where x."tenant_id" = create_work_item.tenant;
  v_identifier := 'TASK-' || v_seq::text;
  begin
    insert into "app_private"."work_items" ("tenant_id", "number", "identifier", "title", "body", "parent_id", "team_id", "project_id", "iteration_id",
      "priority", "estimate", "progress", "start_at", "end_at", "due_at", "pipeline_id", "stage_id", "created_by")
    values (create_work_item.tenant, v_seq, v_identifier, trim(create_work_item.attrs ->> 'title'), create_work_item.attrs ->> 'body',
      (create_work_item.attrs ->> 'parentId')::uuid, (create_work_item.attrs ->> 'teamId')::uuid, (create_work_item.attrs ->> 'projectId')::uuid,
      (create_work_item.attrs ->> 'iterationId')::uuid, coalesce((create_work_item.attrs ->> 'priority')::smallint, 0),
      (create_work_item.attrs ->> 'estimate')::numeric, (create_work_item.attrs ->> 'progress')::smallint,
      (create_work_item.attrs ->> 'startAt')::timestamptz, (create_work_item.attrs ->> 'endAt')::timestamptz, (create_work_item.attrs ->> 'dueAt')::timestamptz,
      (create_work_item.attrs ->> 'pipelineId')::uuid, (create_work_item.attrs ->> 'stageId')::uuid, auth.uid())
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'WORK_ITEM_ATTRS_INVALID';
  end;
  if cardinality(coalesce(create_work_item.assignees, '{}')) > 0 then
    perform "app_private"."set_work_item_assignees"(v_id, create_work_item.assignees);
  end if;
  select * into v_row from "app_private"."work_items" x where x."id" = v_id;
  if jsonb_array_length(coalesce((create_work_item.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      raise exception 'install the attachments block to attach files' using errcode = '0A000', hint = 'WORK_ITEM_ATTACHMENTS_UNAVAILABLE';
    end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_work_item_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "app_private"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "app_private"."work_item_checklist_items" rk where rk."work_item_id" = x."id")) from "app_private"."work_items" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."create_work_item"(uuid, jsonb, uuid[]) from public, anon;
grant execute on function "app_private"."create_work_item"(uuid, jsonb, uuid[]) to authenticated, service_role;

-- Applies a batch of { workItemId, field, value } changes, each on its
-- own. Returns { accepted: [{ workItemId, field }], rejected: [{ workItemId,
-- field, hint, reason }] }.
create or replace function "app_private"."update_work_items"(changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_item uuid;
  v_field text;
  v_row "app_private"."work_items";
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
  if jsonb_typeof(coalesce(update_work_items.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { workItemId, field, value }' using errcode = '22023', hint = 'WORK_ITEM_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_work_items.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'workItemId')::uuid;
      if not exists (select 1 from "app_private"."work_items" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
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
        update "app_private"."work_items" x set "title" = trim(v_change -> 'value' #>> '{}') where x."id" = v_item;
      when 'body' then
        update "app_private"."work_items" x set "body" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'parentId' then
        update "app_private"."work_items" x set "parent_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'teamId' then
        update "app_private"."work_items" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'projectId' then
        update "app_private"."work_items" x set "project_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'iterationId' then
        update "app_private"."work_items" x set "iteration_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'priority' then
        update "app_private"."work_items" x set "priority" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'estimate' then
        update "app_private"."work_items" x set "estimate" = (v_change -> 'value' #>> '{}')::numeric where x."id" = v_item;
      when 'progress' then
        update "app_private"."work_items" x set "progress" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'startAt' then
        update "app_private"."work_items" x set "start_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'endAt' then
        update "app_private"."work_items" x set "end_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'dueAt' then
        update "app_private"."work_items" x set "due_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'stageId' then
        update "app_private"."work_items" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'closeReason' then
        update "app_private"."work_items" x set "close_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'attachments' then
        select * into v_row from "app_private"."work_items" x where x."id" = v_item;
        if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      raise exception 'install the attachments block to attach files' using errcode = '0A000', hint = 'WORK_ITEM_ATTACHMENTS_UNAVAILABLE';
    end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'WORK_ITEM_FIELD_UNKNOWN';
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
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_change ->> 'workItemId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "app_private"."work_items" x where x."id" = any (v_touched) loop
    null;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "app_private"."update_work_items"(jsonb) from public, anon;
grant execute on function "app_private"."update_work_items"(jsonb) to authenticated, service_role;

-- Replaces an item's assignees. Each one watches the item, and those who
-- weren't assigned before are notified.
create or replace function "app_private"."set_work_item_assignees"(work_item uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."work_items";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_work_item_assignees.users, '{}')) x where x is not null);
  v_new uuid[];
  v_user uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."work_items" x where x."id" = set_work_item_assignees.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
  end if;
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from "app_private"."work_item_assignees" y where y."work_item_id" = v_row."id" and y."user_id" = x));
  delete from "app_private"."work_item_assignees" y where y."work_item_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "app_private"."work_item_assignees" ("tenant_id", "work_item_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  null;
  return cardinality(v_users);
end;
$$;
revoke execute on function "app_private"."set_work_item_assignees"(uuid, uuid[]) from public, anon;
grant execute on function "app_private"."set_work_item_assignees"(uuid, uuid[]) to authenticated, service_role;

create or replace function "app_private"."archive_work_item"(work_item uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."work_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "app_private"."work_items" x set "archived_at" = case when archive_work_item.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_work_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_work_item.archived then
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "app_private"."archive_work_item"(uuid, boolean) from public, anon;
grant execute on function "app_private"."archive_work_item"(uuid, boolean) to authenticated, service_role;

-- Deletes an item and its children. Needs work_items.manage, or its author.
create or replace function "app_private"."delete_work_item"(work_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."work_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "app_private"."work_items" x
  where x."id" = delete_work_item.work_item
    and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_work_item"(uuid) from public, anon;
grant execute on function "app_private"."delete_work_item"(uuid) to authenticated, service_role;

-- An item and everything under it with its depth. An item without its own
-- progress takes the share of its open and completed children that are
-- completed, so a Gantt group shows a rollup.
create or replace function "app_private"."work_item_tree"(root uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with recursive tree as (
    select x.*, 0 as depth from "app_private"."work_items" x where x."id" = work_item_tree.root
    union all
    select y.*, tree.depth + 1 from "app_private"."work_items" y join tree on y."parent_id" = tree."id"
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
      from "app_private"."work_items" ch where ch."parent_id" = tree."id" and ch."archived_at" is null))
  ) order by tree.depth, tree."rank" collate "C", tree."id"), '[]'::jsonb)
  from tree
$$;
revoke execute on function "app_private"."work_item_tree"(uuid) from public, anon;
grant execute on function "app_private"."work_item_tree"(uuid) to authenticated, service_role;

-- A page of a tenant's active items, newest first. filter keys: teamId,
-- projectId, iterationId, parentId, assigneeId, states (a list), open
-- (only unclosed). search matches the title and identifier. after continues
-- after that item.
create or replace function "app_private"."list_work_items"(tenant uuid, filter jsonb, search text, after uuid, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.number desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "app_private"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "app_private"."work_item_checklist_items" rk where rk."work_item_id" = x."id")) as value, x."number" as number
    from "app_private"."work_items" x
    where x."tenant_id" = list_work_items.tenant and x."archived_at" is null
      and (list_work_items.filter ->> 'teamId' is null or x."team_id" = (list_work_items.filter ->> 'teamId')::uuid)
      and (list_work_items.filter ->> 'projectId' is null or x."project_id" = (list_work_items.filter ->> 'projectId')::uuid)
      and (list_work_items.filter ->> 'iterationId' is null or x."iteration_id" = (list_work_items.filter ->> 'iterationId')::uuid)
      and (list_work_items.filter ->> 'parentId' is null or x."parent_id" = (list_work_items.filter ->> 'parentId')::uuid)
      and (list_work_items.filter ->> 'assigneeId' is null or exists (select 1 from "app_private"."work_item_assignees" y where y."work_item_id" = x."id" and y."user_id" = (list_work_items.filter ->> 'assigneeId')::uuid))
      and (list_work_items.filter -> 'states' is null or x."state" = any (array(select jsonb_array_elements_text(list_work_items.filter -> 'states'))))
      and (coalesce((list_work_items.filter ->> 'open')::boolean, false) = false or x."closed_at" is null)
      and (list_work_items.search is null or x."title" ilike '%' || list_work_items.search || '%' or x."identifier" ilike list_work_items.search || '%')
      and (list_work_items.after is null or x."number" < (select z."number" from "app_private"."work_items" z where z."id" = list_work_items.after))
    order by x."number" desc
    limit least(greatest(coalesce(list_work_items.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "app_private"."list_work_items"(uuid, jsonb, text, uuid, integer) from public, anon;
grant execute on function "app_private"."list_work_items"(uuid, jsonb, text, uuid, integer) to authenticated, service_role;

-- Adds a checklist item (checklist_item null) or changes one: title, done,
-- rank. A new item without a rank goes last.
create or replace function "app_private"."save_work_item_checklist_item"(work_item uuid, checklist_item uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."work_items";
  v_id uuid := save_work_item_checklist_item.checklist_item;
  v_last text;
  v_done boolean := (save_work_item_checklist_item.attrs ->> 'done')::boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."work_items" x where x."id" = save_work_item_checklist_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
  end if;
  begin
    if v_id is null then
      select max(y."rank") into v_last from "app_private"."work_item_checklist_items" y where y."work_item_id" = v_row."id";
      insert into "app_private"."work_item_checklist_items" ("tenant_id", "work_item_id", "title", "done", "done_at", "done_by", "rank", "created_by")
      values (v_row."tenant_id", v_row."id", trim(save_work_item_checklist_item.attrs ->> 'title'), coalesce(v_done, false),
        case when v_done then now() end, case when v_done then auth.uid() end,
        coalesce(save_work_item_checklist_item.attrs ->> 'rank', case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end), auth.uid())
      returning "id" into v_id;
    else
      update "app_private"."work_item_checklist_items" y set
        "title" = coalesce(trim(save_work_item_checklist_item.attrs ->> 'title'), y."title"),
        "rank" = coalesce(save_work_item_checklist_item.attrs ->> 'rank', y."rank"),
        "done" = coalesce(v_done, y."done"),
        "done_at" = case when v_done is null then y."done_at" when v_done then coalesce(y."done_at", now()) end,
        "done_by" = case when v_done is null then y."done_by" when v_done then coalesce(y."done_by", auth.uid()) end
      where y."id" = v_id and y."work_item_id" = v_row."id";
      if not found then
        raise exception 'no such checklist item on this work item' using errcode = 'P0002', hint = 'WORK_ITEM_CHECKLIST_ITEM_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a checklist item needs a title of 1 to 500 characters and a valid rank' using errcode = '22023', hint = 'WORK_ITEM_CHECKLIST_ITEM_INVALID';
  end;
  null;
  return (select jsonb_build_object('id', y."id", 'workItemId', y."work_item_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") from "app_private"."work_item_checklist_items" y where y."id" = v_id);
end;
$$;
revoke execute on function "app_private"."save_work_item_checklist_item"(uuid, uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_work_item_checklist_item"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "app_private"."delete_work_item_checklist_item"(checklist_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."work_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x.* into v_row from "app_private"."work_items" x join "app_private"."work_item_checklist_items" y on y."work_item_id" = x."id"
  where y."id" = delete_work_item_checklist_item.checklist_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    return false;
  end if;
  delete from "app_private"."work_item_checklist_items" y where y."id" = delete_work_item_checklist_item.checklist_item;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_work_item_checklist_item"(uuid) from public, anon;
grant execute on function "app_private"."delete_work_item_checklist_item"(uuid) to authenticated, service_role;

-- An item's checklist, in rank order.
create or replace function "app_private"."list_work_item_checklist"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'workItemId', y."work_item_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") order by y."rank" collate "C", y."id"), '[]'::jsonb)
  from "app_private"."work_item_checklist_items" y where y."work_item_id" = list_work_item_checklist.work_item
$$;
revoke execute on function "app_private"."list_work_item_checklist"(uuid) from public, anon;
grant execute on function "app_private"."list_work_item_checklist"(uuid) to authenticated, service_role;

-- One item the caller can read, or null.
create or replace function "app_private"."get_work_item"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "app_private"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "app_private"."work_item_checklist_items" rk where rk."work_item_id" = x."id")) from "app_private"."work_items" x where x."id" = get_work_item.work_item
$$;
revoke execute on function "app_private"."get_work_item"(uuid) from public, anon;
grant execute on function "app_private"."get_work_item"(uuid) to authenticated, service_role;

-- Creates a project (project null) or changes the keys attrs names: key,
-- name, ownerId, status, startOn, targetOn, archived.
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_project.tenant, 'work_items.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'WORK_ITEM_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "app_private"."projects" ("tenant_id", "key", "name", "owner_user_id", "status", "start_on", "target_on")
      values (save_project.tenant, upper(save_project.attrs ->> 'key'), save_project.attrs ->> 'name', (save_project.attrs ->> 'ownerId')::uuid,
        coalesce(save_project.attrs ->> 'status', 'planned'), (save_project.attrs ->> 'startOn')::date, (save_project.attrs ->> 'targetOn')::date)
      returning "id" into v_id;
    else
      update "app_private"."projects" x set
        "key" = coalesce(upper(save_project.attrs ->> 'key'), x."key"),
        "name" = coalesce(save_project.attrs ->> 'name', x."name"),
        "owner_user_id" = case when save_project.attrs ? 'ownerId' then (save_project.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
        "status" = coalesce(save_project.attrs ->> 'status', x."status"),
        "start_on" = case when save_project.attrs ? 'startOn' then (save_project.attrs ->> 'startOn')::date else x."start_on" end,
        "target_on" = case when save_project.attrs ? 'targetOn' then (save_project.attrs ->> 'targetOn')::date else x."target_on" end,
        "archived_at" = case when save_project.attrs ? 'archived' then (case when (save_project.attrs ->> 'archived')::boolean then coalesce(x."archived_at", now()) end) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_project.tenant;
      if not found then
        raise exception 'project not found' using errcode = 'P0002', hint = 'WORK_ITEM_PROJECT_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another project has this key' using errcode = '23505', hint = 'WORK_ITEM_PROJECT_KEY_TAKEN';
  when check_violation or not_null_violation then
    raise exception 'a project needs a key of capitals and a name, and ends after it starts' using errcode = '22023', hint = 'WORK_ITEM_PROJECT_INVALID';
  end;
  return (select to_jsonb(x) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "app_private"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_iteration.tenant, 'work_items.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'WORK_ITEM_FORBIDDEN';
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
        raise exception 'iteration not found' using errcode = 'P0002', hint = 'WORK_ITEM_ITERATION_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation then
    raise exception 'an iteration needs a name and ends on or after it starts' using errcode = '22023', hint = 'WORK_ITEM_ITERATION_INVALID';
  end;
  return (select to_jsonb(x) from "app_private"."iterations" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."save_iteration"(uuid, uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_iteration"(uuid, uuid, jsonb) to authenticated, service_role;

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_91_tasks.sql
-- better-supabase module: tasks
-- @bsb-block-data tasks
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_91_tasks.sql
-- better-supabase module: tasks
-- @bsb-block tasks@2 managed
-- Issues and tasks on pipelines: identifiers, parents without cycles, several assignees, priority 0 to 4, estimates, start, end and due dates, locking, projects, iterations, batched edits and a progress tree.
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
alter table "better_supabase"."projects" enable row level security;
revoke all on "better_supabase"."projects" from anon, authenticated;
grant select on "better_supabase"."projects" to authenticated;
grant all on "better_supabase"."projects" to service_role;
drop policy if exists projects_read on "better_supabase"."projects";
create policy projects_read on "better_supabase"."projects" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

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
revoke all on "better_supabase"."iterations" from anon, authenticated;
grant select on "better_supabase"."iterations" to authenticated;
grant all on "better_supabase"."iterations" to service_role;
drop policy if exists iterations_read on "better_supabase"."iterations";
create policy iterations_read on "better_supabase"."iterations" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

create table if not exists "better_supabase"."work_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "title" text not null check (length("title") between 1 and 500),
  "body" text,
  "parent_id" uuid references "better_supabase"."work_items" ("id") on delete cascade,
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
create index if not exists work_items_board_idx on "better_supabase"."work_items" ("pipeline_id", "stage_id", "rank");
create index if not exists work_items_parent_idx on "better_supabase"."work_items" ("parent_id");
create index if not exists work_items_project_idx on "better_supabase"."work_items" ("project_id");
create index if not exists work_items_iteration_idx on "better_supabase"."work_items" ("iteration_id");
create index if not exists work_items_due_idx on "better_supabase"."work_items" ("tenant_id", "due_at") where "closed_at" is null;
alter table "better_supabase"."work_items" enable row level security;
revoke all on "better_supabase"."work_items" from anon, authenticated;
grant select on "better_supabase"."work_items" to authenticated;
grant all on "better_supabase"."work_items" to service_role;
drop policy if exists work_items_read on "better_supabase"."work_items";
create policy work_items_read on "better_supabase"."work_items" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

create table if not exists "better_supabase"."work_item_assignees" (
  "tenant_id" uuid not null,
  "work_item_id" uuid not null references "better_supabase"."work_items" ("id") on delete cascade,
  "user_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("work_item_id", "user_id")
);
create index if not exists work_item_assignees_user_idx on "better_supabase"."work_item_assignees" ("user_id");
alter table "better_supabase"."work_item_assignees" enable row level security;
revoke all on "better_supabase"."work_item_assignees" from anon, authenticated;
grant select on "better_supabase"."work_item_assignees" to authenticated;
grant all on "better_supabase"."work_item_assignees" to service_role;
drop policy if exists work_item_assignees_read on "better_supabase"."work_item_assignees";
create policy work_item_assignees_read on "better_supabase"."work_item_assignees" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

alter table "better_supabase"."work_items" add column if not exists "recurs_from" uuid references "better_supabase"."work_items" ("id") on delete set null;
create unique index if not exists work_items_recurs_from_idx on "better_supabase"."work_items" ("recurs_from");

create table if not exists "better_supabase"."work_item_checklist_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "work_item_id" uuid not null references "better_supabase"."work_items" ("id") on delete cascade,
  "title" text not null check (length("title") between 1 and 500),
  "done" boolean not null default false,
  "done_at" timestamptz,
  "done_by" uuid,
  "rank" text collate "C" not null check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
create index if not exists work_item_checklist_item_idx on "better_supabase"."work_item_checklist_items" ("work_item_id", "rank");
alter table "better_supabase"."work_item_checklist_items" enable row level security;
revoke all on "better_supabase"."work_item_checklist_items" from anon, authenticated;
grant select on "better_supabase"."work_item_checklist_items" to authenticated;
grant all on "better_supabase"."work_item_checklist_items" to service_role;
drop policy if exists work_item_checklist_items_read on "better_supabase"."work_item_checklist_items";
create policy work_item_checklist_items_read on "better_supabase"."work_item_checklist_items" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('work_items.read')));

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
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'WORK_ITEM_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "better_supabase"."work_items" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
      raise exception 'the parent is in another organization' using errcode = '22023', hint = 'WORK_ITEM_PARENT_INVALID';
    end if;
  end if;
  if tg_op = 'UPDATE' and old."locked" and not (auth.role() = 'service_role') and (new."start_at" is distinct from old."start_at" or new."end_at" is distinct from old."end_at" or new."due_at" is distinct from old."due_at") then
    raise exception 'the item is locked; its dates can''t change' using errcode = '55000', hint = 'WORK_ITEM_LOCKED';
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
drop trigger if exists bsb_work_item_guard on "better_supabase"."work_items";
create trigger bsb_work_item_guard before insert or update on "better_supabase"."work_items"
for each row execute function better_supabase.bsb_work_item_guard();

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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_work_item.tenant, 'work_items.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'WORK_ITEM_FORBIDDEN';
  end if;
  if nullif(trim(create_work_item.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'WORK_ITEM_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_work_item.tenant, create_work_item.attrs;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_work_item.tenant::text || ':work_item', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."work_items" x where x."tenant_id" = create_work_item.tenant;
  v_identifier := 'TASK-' || v_seq::text;
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
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'WORK_ITEM_ATTRS_INVALID';
  end;
  if cardinality(coalesce(create_work_item.assignees, '{}')) > 0 then
    perform "better_supabase"."set_work_item_assignees"(v_id, create_work_item.assignees);
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = v_id;
  if jsonb_array_length(coalesce((create_work_item.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      raise exception 'install the attachments block to attach files' using errcode = '0A000', hint = 'WORK_ITEM_ATTACHMENTS_UNAVAILABLE';
    end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_work_item_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id")) from "better_supabase"."work_items" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_work_item"(uuid, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."create_work_item"(uuid, jsonb, uuid[]) to authenticated, service_role;

-- Applies a batch of { workItemId, field, value } changes, each on its
-- own. Returns { accepted: [{ workItemId, field }], rejected: [{ workItemId,
-- field, hint, reason }] }.
create or replace function "better_supabase"."update_work_items"(changes jsonb)
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
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_work_items.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { workItemId, field, value }' using errcode = '22023', hint = 'WORK_ITEM_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_work_items.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'workItemId')::uuid;
      if not exists (select 1 from "better_supabase"."work_items" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
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
      when 'attachments' then
        select * into v_row from "better_supabase"."work_items" x where x."id" = v_item;
        if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      raise exception 'install the attachments block to attach files' using errcode = '0A000', hint = 'WORK_ITEM_ATTACHMENTS_UNAVAILABLE';
    end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'WORK_ITEM_FIELD_UNKNOWN';
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
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_change ->> 'workItemId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."work_items" x where x."id" = any (v_touched) loop
    null;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "better_supabase"."update_work_items"(jsonb) from public, anon;
grant execute on function "better_supabase"."update_work_items"(jsonb) to authenticated, service_role;

-- Replaces an item's assignees. Each one watches the item, and those who
-- weren't assigned before are notified.
create or replace function "better_supabase"."set_work_item_assignees"(work_item uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."work_items";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_work_item_assignees.users, '{}')) x where x is not null);
  v_new uuid[];
  v_user uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = set_work_item_assignees.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
  end if;
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."work_item_assignees" ("tenant_id", "work_item_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  null;
  return cardinality(v_users);
end;
$$;
revoke execute on function "better_supabase"."set_work_item_assignees"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."set_work_item_assignees"(uuid, uuid[]) to authenticated, service_role;

create or replace function "better_supabase"."archive_work_item"(work_item uuid, archived boolean)
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
  update "better_supabase"."work_items" x set "archived_at" = case when archive_work_item.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_work_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_work_item.archived then
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_work_item"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_work_item"(uuid, boolean) to authenticated, service_role;

-- Deletes an item and its children. Needs work_items.manage, or its author.
create or replace function "better_supabase"."delete_work_item"(work_item uuid)
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
  where x."id" = delete_work_item.work_item
    and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_work_item"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_work_item"(uuid) to authenticated, service_role;

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
    select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id")) as value, x."number" as number
    from "better_supabase"."work_items" x
    where x."tenant_id" = list_work_items.tenant and x."archived_at" is null
      and (list_work_items.filter ->> 'teamId' is null or x."team_id" = (list_work_items.filter ->> 'teamId')::uuid)
      and (list_work_items.filter ->> 'projectId' is null or x."project_id" = (list_work_items.filter ->> 'projectId')::uuid)
      and (list_work_items.filter ->> 'iterationId' is null or x."iteration_id" = (list_work_items.filter ->> 'iterationId')::uuid)
      and (list_work_items.filter ->> 'parentId' is null or x."parent_id" = (list_work_items.filter ->> 'parentId')::uuid)
      and (list_work_items.filter ->> 'assigneeId' is null or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and y."user_id" = (list_work_items.filter ->> 'assigneeId')::uuid))
      and (list_work_items.filter -> 'states' is null or x."state" = any (array(select jsonb_array_elements_text(list_work_items.filter -> 'states'))))
      and (coalesce((list_work_items.filter ->> 'open')::boolean, false) = false or x."closed_at" is null)
      and (list_work_items.search is null or x."title" ilike '%' || list_work_items.search || '%' or x."identifier" ilike list_work_items.search || '%')
      and (list_work_items.after is null or x."number" < (select z."number" from "better_supabase"."work_items" z where z."id" = list_work_items.after))
    order by x."number" desc
    limit least(greatest(coalesce(list_work_items.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."list_work_items"(uuid, jsonb, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_work_items"(uuid, jsonb, text, uuid, integer) to authenticated, service_role;

-- Adds a checklist item (checklist_item null) or changes one: title, done,
-- rank. A new item without a rank goes last.
create or replace function "better_supabase"."save_work_item_checklist_item"(work_item uuid, checklist_item uuid, attrs jsonb)
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
  select * into v_row from "better_supabase"."work_items" x where x."id" = save_work_item_checklist_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
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
        raise exception 'no such checklist item on this work item' using errcode = 'P0002', hint = 'WORK_ITEM_CHECKLIST_ITEM_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a checklist item needs a title of 1 to 500 characters and a valid rank' using errcode = '22023', hint = 'WORK_ITEM_CHECKLIST_ITEM_INVALID';
  end;
  null;
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
  where y."id" = delete_work_item_checklist_item.checklist_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    return false;
  end if;
  delete from "better_supabase"."work_item_checklist_items" y where y."id" = delete_work_item_checklist_item.checklist_item;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_work_item_checklist_item"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_work_item_checklist_item"(uuid) to authenticated, service_role;

-- An item's checklist, in rank order.
create or replace function "better_supabase"."list_work_item_checklist"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'workItemId', y."work_item_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") order by y."rank" collate "C", y."id"), '[]'::jsonb)
  from "better_supabase"."work_item_checklist_items" y where y."work_item_id" = list_work_item_checklist.work_item
$$;
revoke execute on function "better_supabase"."list_work_item_checklist"(uuid) from public, anon;
grant execute on function "better_supabase"."list_work_item_checklist"(uuid) to authenticated, service_role;

-- One item the caller can read, or null.
create or replace function "better_supabase"."get_work_item"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id")) from "better_supabase"."work_items" x where x."id" = get_work_item.work_item
$$;
revoke execute on function "better_supabase"."get_work_item"(uuid) from public, anon;
grant execute on function "better_supabase"."get_work_item"(uuid) to authenticated, service_role;

-- Creates a project (project null) or changes the keys attrs names: key,
-- name, ownerId, status, startOn, targetOn, archived.
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_project.tenant, 'work_items.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'WORK_ITEM_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."projects" ("tenant_id", "key", "name", "owner_user_id", "status", "start_on", "target_on")
      values (save_project.tenant, upper(save_project.attrs ->> 'key'), save_project.attrs ->> 'name', (save_project.attrs ->> 'ownerId')::uuid,
        coalesce(save_project.attrs ->> 'status', 'planned'), (save_project.attrs ->> 'startOn')::date, (save_project.attrs ->> 'targetOn')::date)
      returning "id" into v_id;
    else
      update "better_supabase"."projects" x set
        "key" = coalesce(upper(save_project.attrs ->> 'key'), x."key"),
        "name" = coalesce(save_project.attrs ->> 'name', x."name"),
        "owner_user_id" = case when save_project.attrs ? 'ownerId' then (save_project.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
        "status" = coalesce(save_project.attrs ->> 'status', x."status"),
        "start_on" = case when save_project.attrs ? 'startOn' then (save_project.attrs ->> 'startOn')::date else x."start_on" end,
        "target_on" = case when save_project.attrs ? 'targetOn' then (save_project.attrs ->> 'targetOn')::date else x."target_on" end,
        "archived_at" = case when save_project.attrs ? 'archived' then (case when (save_project.attrs ->> 'archived')::boolean then coalesce(x."archived_at", now()) end) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_project.tenant;
      if not found then
        raise exception 'project not found' using errcode = 'P0002', hint = 'WORK_ITEM_PROJECT_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another project has this key' using errcode = '23505', hint = 'WORK_ITEM_PROJECT_KEY_TAKEN';
  when check_violation or not_null_violation then
    raise exception 'a project needs a key of capitals and a name, and ends after it starts' using errcode = '22023', hint = 'WORK_ITEM_PROJECT_INVALID';
  end;
  return (select to_jsonb(x) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_iteration.tenant, 'work_items.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'WORK_ITEM_FORBIDDEN';
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
        raise exception 'iteration not found' using errcode = 'P0002', hint = 'WORK_ITEM_ITERATION_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation then
    raise exception 'an iteration needs a name and ends on or after it starts' using errcode = '22023', hint = 'WORK_ITEM_ITERATION_INVALID';
  end;
  return (select to_jsonb(x) from "better_supabase"."iterations" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_iteration"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_iteration"(uuid, uuid, jsonb) to authenticated, service_role;

-- blocks.tasks.api: entry points for the Data API.
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

create or replace function "api"."create_work_item"(tenant uuid, attrs jsonb, assignees uuid[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_work_item"($1, $2, $3) $$;
revoke execute on function "api"."create_work_item"(uuid, jsonb, uuid[]) from public, anon;
grant execute on function "api"."create_work_item"(uuid, jsonb, uuid[]) to authenticated, service_role;

create or replace function "api"."update_work_items"(changes jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_work_items"($1) $$;
revoke execute on function "api"."update_work_items"(jsonb) from public, anon;
grant execute on function "api"."update_work_items"(jsonb) to authenticated, service_role;

create or replace function "api"."set_work_item_assignees"(work_item uuid, users uuid[])
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_work_item_assignees"($1, $2) $$;
revoke execute on function "api"."set_work_item_assignees"(uuid, uuid[]) from public, anon;
grant execute on function "api"."set_work_item_assignees"(uuid, uuid[]) to authenticated, service_role;

create or replace function "api"."archive_work_item"(work_item uuid, archived boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_work_item"($1, $2) $$;
revoke execute on function "api"."archive_work_item"(uuid, boolean) from public, anon;
grant execute on function "api"."archive_work_item"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."delete_work_item"(work_item uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_work_item"($1) $$;
revoke execute on function "api"."delete_work_item"(uuid) from public, anon;
grant execute on function "api"."delete_work_item"(uuid) to authenticated, service_role;

create or replace function "api"."work_item_tree"(root uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."work_item_tree"($1) $$;
revoke execute on function "api"."work_item_tree"(uuid) from public, anon;
grant execute on function "api"."work_item_tree"(uuid) to authenticated, service_role;

create or replace function "api"."list_work_items"(tenant uuid, filter jsonb, search text, after uuid, page_size integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_work_items"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_work_items"(uuid, jsonb, text, uuid, integer) from public, anon;
grant execute on function "api"."list_work_items"(uuid, jsonb, text, uuid, integer) to authenticated, service_role;

create or replace function "api"."save_work_item_checklist_item"(work_item uuid, checklist_item uuid, attrs jsonb)
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

create or replace function "api"."list_work_item_checklist"(work_item uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_work_item_checklist"($1) $$;
revoke execute on function "api"."list_work_item_checklist"(uuid) from public, anon;
grant execute on function "api"."list_work_item_checklist"(uuid) to authenticated, service_role;

create or replace function "api"."get_work_item"(work_item uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_work_item"($1) $$;
revoke execute on function "api"."get_work_item"(uuid) from public, anon;
grant execute on function "api"."get_work_item"(uuid) to authenticated, service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_91_tasks.sql
-- better-supabase module: tasks
-- @bsb-block-data tasks
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
