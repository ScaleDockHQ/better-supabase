-- better-supabase module: maintenance
-- @bsb-block maintenance@2 managed tasks
-- @bsb-hash sha256:b7ae8761d623cb0207f338d4cba4251683d3cb66bb387c8cb5dc8d9540735feb
-- @bsb-names maintenance work_item=maintenance_request/maintenance_requests
-- Issues and tasks on pipelines: identifiers, parents without cycles, several assignees, priority 0 to 4, estimates, start, end and due dates, locking, projects, iterations, batched edits and a progress tree.
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
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Work items on pipelines: issues and tasks with an identifier, a parent,
-- assignees, a priority, dates, projects and iterations.

create table if not exists "better_supabase"."maintenance_requests" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "title" text not null check (length("title") between 1 and 500),
  "body" text,
  "parent_id" uuid references "better_supabase"."maintenance_requests" ("id") on delete cascade,
  "team_id" uuid,
  "project_id" uuid,
  "iteration_id" uuid,
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
create index if not exists maintenance_requests_board_idx on "better_supabase"."maintenance_requests" ("pipeline_id", "stage_id", "rank");
create index if not exists maintenance_requests_parent_idx on "better_supabase"."maintenance_requests" ("parent_id");
create index if not exists maintenance_requests_project_idx on "better_supabase"."maintenance_requests" ("project_id");
create index if not exists maintenance_requests_iteration_idx on "better_supabase"."maintenance_requests" ("iteration_id");
create index if not exists maintenance_requests_due_idx on "better_supabase"."maintenance_requests" ("tenant_id", "due_at") where "closed_at" is null;
alter table "better_supabase"."maintenance_requests" add column if not exists "unit_id" uuid;
alter table "better_supabase"."maintenance_requests" add column if not exists "lease_id" uuid;
alter table "better_supabase"."maintenance_requests" enable row level security;
revoke all on "better_supabase"."maintenance_requests" from anon, authenticated;
grant select on "better_supabase"."maintenance_requests" to authenticated;
grant all on "better_supabase"."maintenance_requests" to service_role;
drop policy if exists maintenance_requests_read on "better_supabase"."maintenance_requests";
create policy maintenance_requests_read on "better_supabase"."maintenance_requests" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('maintenance_requests.read')));

create table if not exists "better_supabase"."maintenance_request_assignees" (
  "tenant_id" uuid not null,
  "maintenance_request_id" uuid not null references "better_supabase"."maintenance_requests" ("id") on delete cascade,
  "user_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("maintenance_request_id", "user_id")
);
create index if not exists maintenance_request_assignees_user_idx on "better_supabase"."maintenance_request_assignees" ("user_id");
alter table "better_supabase"."maintenance_request_assignees" enable row level security;
revoke all on "better_supabase"."maintenance_request_assignees" from anon, authenticated;
grant select on "better_supabase"."maintenance_request_assignees" to authenticated;
grant all on "better_supabase"."maintenance_request_assignees" to service_role;
drop policy if exists maintenance_request_assignees_read on "better_supabase"."maintenance_request_assignees";
create policy maintenance_request_assignees_read on "better_supabase"."maintenance_request_assignees" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('maintenance_requests.read')));

alter table "better_supabase"."maintenance_requests" add column if not exists "recurs_from" uuid references "better_supabase"."maintenance_requests" ("id") on delete set null;
create unique index if not exists maintenance_requests_recurs_from_idx on "better_supabase"."maintenance_requests" ("recurs_from");

create table if not exists "better_supabase"."maintenance_request_checklist_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "maintenance_request_id" uuid not null references "better_supabase"."maintenance_requests" ("id") on delete cascade,
  "title" text not null check (length("title") between 1 and 500),
  "done" boolean not null default false,
  "done_at" timestamptz,
  "done_by" uuid,
  "rank" text collate "C" not null check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
create index if not exists maintenance_request_checklist_item_idx on "better_supabase"."maintenance_request_checklist_items" ("maintenance_request_id", "rank");
alter table "better_supabase"."maintenance_request_checklist_items" enable row level security;
revoke all on "better_supabase"."maintenance_request_checklist_items" from anon, authenticated;
grant select on "better_supabase"."maintenance_request_checklist_items" to authenticated;
grant all on "better_supabase"."maintenance_request_checklist_items" to service_role;
drop policy if exists maintenance_request_checklist_items_read on "better_supabase"."maintenance_request_checklist_items";
create policy maintenance_request_checklist_items_read on "better_supabase"."maintenance_request_checklist_items" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('maintenance_requests.read')));

create or replace function better_supabase.bsb_maintenance_request_guard()
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
        select x."parent_id", up.depth + 1 from "better_supabase"."maintenance_requests" x join up on x."id" = up.id
        where x."parent_id" is not null and up.depth < 100
      )
      select 1 from up where up.id = new."id"
    ) then
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'WORK_ITEM_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "better_supabase"."maintenance_requests" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
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
      perform "better_supabase".emit_event('maintenance_request.closed', jsonb_build_object('organizationId', new."tenant_id", 'maintenanceRequestId', new."id", 'subjectType', 'maintenance_request', 'subjectId', new."id"::text, 'title', new."title", 'state', new."state", 'closeReason', new."close_reason"), 'maintenance-requests/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/maintenance');
    elsif not (new."state" in ('completed', 'canceled')) and old."state" in ('completed', 'canceled') then
      new."closed_at" := null;
      new."close_reason" := null;
      perform "better_supabase".emit_event('maintenance_request.reopened', jsonb_build_object('organizationId', new."tenant_id", 'maintenanceRequestId', new."id", 'subjectType', 'maintenance_request', 'subjectId', new."id"::text, 'title', new."title"), 'maintenance-requests/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/maintenance');
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_maintenance_request_guard() from public, anon, authenticated;
drop trigger if exists bsb_maintenance_request_guard on "better_supabase"."maintenance_requests";
create trigger bsb_maintenance_request_guard before insert or update on "better_supabase"."maintenance_requests"
for each row execute function better_supabase.bsb_maintenance_request_guard();

-- Creates a work item. attrs: title (required), body, parentId, teamId,
-- projectId, iterationId, priority (0 none to 4 low, as Linear), estimate,
-- progress, startAt, endAt, dueAt, pipelineId, stageId, and fields (the
-- extra columns, by name). assignees: user ids.
create or replace function "better_supabase"."create_maintenance_request"(tenant uuid, attrs jsonb, assignees uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seq bigint;
  v_identifier text;
  v_id uuid;
  v_row "better_supabase"."maintenance_requests";
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_maintenance_request.tenant, 'maintenance_requests.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'WORK_ITEM_FORBIDDEN';
  end if;
  if nullif(trim(create_maintenance_request.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'WORK_ITEM_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_maintenance_request_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_maintenance_request.tenant, create_maintenance_request.attrs;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_maintenance_request.tenant::text || ':maintenance_request', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."maintenance_requests" x where x."tenant_id" = create_maintenance_request.tenant;
  v_identifier := 'MR' || v_seq::text;
  begin
    insert into "better_supabase"."maintenance_requests" ("tenant_id", "number", "identifier", "title", "body", "parent_id", "team_id", "project_id", "iteration_id",
      "priority", "estimate", "progress", "start_at", "end_at", "due_at", "pipeline_id", "stage_id", "created_by")
    values (create_maintenance_request.tenant, v_seq, v_identifier, trim(create_maintenance_request.attrs ->> 'title'), create_maintenance_request.attrs ->> 'body',
      (create_maintenance_request.attrs ->> 'parentId')::uuid, (create_maintenance_request.attrs ->> 'teamId')::uuid, (create_maintenance_request.attrs ->> 'projectId')::uuid,
      (create_maintenance_request.attrs ->> 'iterationId')::uuid, coalesce((create_maintenance_request.attrs ->> 'priority')::smallint, 0),
      (create_maintenance_request.attrs ->> 'estimate')::numeric, (create_maintenance_request.attrs ->> 'progress')::smallint,
      (create_maintenance_request.attrs ->> 'startAt')::timestamptz, (create_maintenance_request.attrs ->> 'endAt')::timestamptz, (create_maintenance_request.attrs ->> 'dueAt')::timestamptz,
      (create_maintenance_request.attrs ->> 'pipelineId')::uuid, (create_maintenance_request.attrs ->> 'stageId')::uuid, auth.uid())
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'WORK_ITEM_ATTRS_INVALID';
  end;
  update "better_supabase"."maintenance_requests" x set "unit_id" = case when (create_maintenance_request.attrs -> 'fields') ? 'unit_id' then r."unit_id" else x."unit_id" end, "lease_id" = case when (create_maintenance_request.attrs -> 'fields') ? 'lease_id' then r."lease_id" else x."lease_id" end
  from jsonb_populate_record(null::"better_supabase"."maintenance_requests", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each((create_maintenance_request.attrs -> 'fields')) e where e.key in ('unit_id', 'lease_id'))) r
  where x."id" = v_id;
  if cardinality(coalesce(create_maintenance_request.assignees, '{}')) > 0 then
    perform "better_supabase"."set_maintenance_request_assignees"(v_id, create_maintenance_request.assignees);
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = v_id;
  if jsonb_typeof(coalesce((create_maintenance_request.attrs -> 'attachments'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'WORK_ITEM_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((create_maintenance_request.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'maintenance_request', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((create_maintenance_request.attrs -> 'attachments'))::uuid))
        and f."organization_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'maintenance_request' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((create_maintenance_request.attrs -> 'attachments')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'WORK_ITEM_ATTACHMENTS_INVALID';
      end if;
    end if;
  perform "better_supabase".emit_event('maintenance_request.created', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'maintenance-requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/maintenance');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_maintenance_request_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) from "better_supabase"."maintenance_requests" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_maintenance_request"(uuid, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."create_maintenance_request"(uuid, jsonb, uuid[]) to authenticated, service_role;

-- Applies a batch of { workItemId, field, value } changes, each on its
-- own. Returns { accepted: [{ workItemId, field }], rejected: [{ workItemId,
-- field, hint, reason }] }.
create or replace function "better_supabase"."update_maintenance_requests"(changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_item uuid;
  v_field text;
  v_row "better_supabase"."maintenance_requests";
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
  if jsonb_typeof(coalesce(update_maintenance_requests.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { maintenanceRequestId, field, value }' using errcode = '22023', hint = 'WORK_ITEM_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_maintenance_requests.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'maintenanceRequestId')::uuid;
      if not exists (select 1 from "better_supabase"."maintenance_requests" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance_requests.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_maintenance_request_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_item, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'title' then
        update "better_supabase"."maintenance_requests" x set "title" = trim(v_change -> 'value' #>> '{}') where x."id" = v_item;
      when 'body' then
        update "better_supabase"."maintenance_requests" x set "body" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'parentId' then
        update "better_supabase"."maintenance_requests" x set "parent_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'teamId' then
        update "better_supabase"."maintenance_requests" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'projectId' then
        update "better_supabase"."maintenance_requests" x set "project_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'iterationId' then
        update "better_supabase"."maintenance_requests" x set "iteration_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'priority' then
        update "better_supabase"."maintenance_requests" x set "priority" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'estimate' then
        update "better_supabase"."maintenance_requests" x set "estimate" = (v_change -> 'value' #>> '{}')::numeric where x."id" = v_item;
      when 'progress' then
        update "better_supabase"."maintenance_requests" x set "progress" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'startAt' then
        update "better_supabase"."maintenance_requests" x set "start_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'endAt' then
        update "better_supabase"."maintenance_requests" x set "end_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'dueAt' then
        update "better_supabase"."maintenance_requests" x set "due_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'stageId' then
        update "better_supabase"."maintenance_requests" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'closeReason' then
        update "better_supabase"."maintenance_requests" x set "close_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'attachments' then
        select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = v_item;
        if jsonb_typeof(coalesce((v_change -> 'value'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'WORK_ITEM_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'maintenance_request', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((v_change -> 'value'))::uuid))
        and f."organization_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'maintenance_request' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((v_change -> 'value')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'WORK_ITEM_ATTACHMENTS_INVALID';
      end if;
    end if;
      when 'unit_id' then
        update "better_supabase"."maintenance_requests" x set "unit_id" = (jsonb_populate_record(null::"better_supabase"."maintenance_requests", jsonb_build_object('unit_id', v_change -> 'value')))."unit_id" where x."id" = v_item;
      when 'lease_id' then
        update "better_supabase"."maintenance_requests" x set "lease_id" = (jsonb_populate_record(null::"better_supabase"."maintenance_requests", jsonb_build_object('lease_id', v_change -> 'value')))."lease_id" where x."id" = v_item;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'WORK_ITEM_FIELD_UNKNOWN';
      end case;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('maintenanceRequestId', v_item, 'field', v_field));
      v_touched := array_append(v_touched, v_item);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_maintenance_request_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_item, v_field;
    end if;
  end;
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('maintenanceRequestId', v_change ->> 'maintenanceRequestId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."maintenance_requests" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('maintenance_request.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'maintenanceRequestId')::uuid = v_row."id")), 'maintenance-requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/maintenance');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "better_supabase"."update_maintenance_requests"(jsonb) from public, anon;
grant execute on function "better_supabase"."update_maintenance_requests"(jsonb) to authenticated, service_role;

-- Replaces an item's assignees. Each one watches the item, and those who
-- weren't assigned before are notified.
create or replace function "better_supabase"."set_maintenance_request_assignees"(work_item uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."maintenance_requests";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_maintenance_request_assignees.users, '{}')) x where x is not null);
  v_new uuid[];
  v_user uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = set_maintenance_request_assignees.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance_requests.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
  end if;
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."maintenance_request_assignees" ("tenant_id", "maintenance_request_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  foreach v_user in array v_users loop
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_row."tenant_id", v_user, 'maintenance_request', v_row."id"::text, 'participating')
    on conflict do nothing;
  end loop;
  if cardinality(v_new) > 0 then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'maintenance_request.assigned',
      'tenant', v_row."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'maintenance_request',
      'subject_id', v_row."id"::text,
      'summary', v_row."title",
      'recipients', to_jsonb(v_new),
      'watchers', false,
      'key', 'maintenance_request.assigned:' || v_row."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('maintenanceRequestId', v_row."id")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  perform "better_supabase".emit_event('maintenance_request.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(v_users)), 'maintenance-requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/maintenance');
  return cardinality(v_users);
end;
$$;
revoke execute on function "better_supabase"."set_maintenance_request_assignees"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."set_maintenance_request_assignees"(uuid, uuid[]) to authenticated, service_role;

create or replace function "better_supabase"."archive_maintenance_request"(work_item uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."maintenance_requests";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."maintenance_requests" x set "archived_at" = case when archive_maintenance_request.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_maintenance_request.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance_requests.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_maintenance_request.archived then
    perform "better_supabase".emit_event('maintenance_request.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'maintenance-requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/maintenance');
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_maintenance_request"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_maintenance_request"(uuid, boolean) to authenticated, service_role;

-- Deletes an item and its children. Needs work_items.manage, or its author.
create or replace function "better_supabase"."delete_maintenance_request"(work_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."maintenance_requests";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."maintenance_requests" x
  where x."id" = delete_maintenance_request.work_item
    and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance_requests.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  perform "better_supabase".emit_event('maintenance_request.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'maintenance-requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/maintenance');
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_maintenance_request"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_maintenance_request"(uuid) to authenticated, service_role;

-- An item and everything under it with its depth. An item without its own
-- progress takes the share of its open and completed children that are
-- completed, so a Gantt group shows a rollup.
create or replace function "better_supabase"."maintenance_request_tree"(root uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with recursive tree as (
    select x.*, 0 as depth from "better_supabase"."maintenance_requests" x where x."id" = maintenance_request_tree.root
    union all
    select y.*, tree.depth + 1 from "better_supabase"."maintenance_requests" y join tree on y."parent_id" = tree."id"
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
      from "better_supabase"."maintenance_requests" ch where ch."parent_id" = tree."id" and ch."archived_at" is null))
  ) order by tree.depth, tree."rank" collate "C", tree."id"), '[]'::jsonb)
  from tree
$$;
revoke execute on function "better_supabase"."maintenance_request_tree"(uuid) from public, anon;
grant execute on function "better_supabase"."maintenance_request_tree"(uuid) to authenticated, service_role;

-- A page of a tenant's active items, newest first. filter keys: teamId,
-- projectId, iterationId, parentId, assigneeId, states (a list), open
-- (only unclosed). search matches the title and identifier. after continues
-- after that item.
create or replace function "better_supabase"."list_maintenance_requests"(tenant uuid, filter jsonb, search text, after uuid, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.number desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) as value, x."number" as number
    from "better_supabase"."maintenance_requests" x
    where x."tenant_id" = list_maintenance_requests.tenant and x."archived_at" is null
      and (list_maintenance_requests.filter ->> 'teamId' is null or x."team_id" = (list_maintenance_requests.filter ->> 'teamId')::uuid)
      and (list_maintenance_requests.filter ->> 'projectId' is null or x."project_id" = (list_maintenance_requests.filter ->> 'projectId')::uuid)
      and (list_maintenance_requests.filter ->> 'iterationId' is null or x."iteration_id" = (list_maintenance_requests.filter ->> 'iterationId')::uuid)
      and (list_maintenance_requests.filter ->> 'parentId' is null or x."parent_id" = (list_maintenance_requests.filter ->> 'parentId')::uuid)
      and (list_maintenance_requests.filter ->> 'assigneeId' is null or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and y."user_id" = (list_maintenance_requests.filter ->> 'assigneeId')::uuid))
      and (list_maintenance_requests.filter -> 'states' is null or x."state" = any (array(select jsonb_array_elements_text(list_maintenance_requests.filter -> 'states'))))
      and (coalesce((list_maintenance_requests.filter ->> 'open')::boolean, false) = false or x."closed_at" is null)
      and (list_maintenance_requests.search is null or x."title" ilike '%' || list_maintenance_requests.search || '%' or x."identifier" ilike list_maintenance_requests.search || '%')
      and (list_maintenance_requests.after is null or x."number" < (select z."number" from "better_supabase"."maintenance_requests" z where z."id" = list_maintenance_requests.after))
    order by x."number" desc
    limit least(greatest(coalesce(list_maintenance_requests.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."list_maintenance_requests"(uuid, jsonb, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_maintenance_requests"(uuid, jsonb, text, uuid, integer) to authenticated, service_role;

-- Adds a checklist item (checklist_item null) or changes one: title, done,
-- rank. A new item without a rank goes last.
create or replace function "better_supabase"."save_maintenance_request_checklist_item"(work_item uuid, checklist_item uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."maintenance_requests";
  v_id uuid := save_maintenance_request_checklist_item.checklist_item;
  v_last text;
  v_done boolean := (save_maintenance_request_checklist_item.attrs ->> 'done')::boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = save_maintenance_request_checklist_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance_requests.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
  end if;
  begin
    if v_id is null then
      select max(y."rank") into v_last from "better_supabase"."maintenance_request_checklist_items" y where y."maintenance_request_id" = v_row."id";
      insert into "better_supabase"."maintenance_request_checklist_items" ("tenant_id", "maintenance_request_id", "title", "done", "done_at", "done_by", "rank", "created_by")
      values (v_row."tenant_id", v_row."id", trim(save_maintenance_request_checklist_item.attrs ->> 'title'), coalesce(v_done, false),
        case when v_done then now() end, case when v_done then auth.uid() end,
        coalesce(save_maintenance_request_checklist_item.attrs ->> 'rank', case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end), auth.uid())
      returning "id" into v_id;
    else
      update "better_supabase"."maintenance_request_checklist_items" y set
        "title" = coalesce(trim(save_maintenance_request_checklist_item.attrs ->> 'title'), y."title"),
        "rank" = coalesce(save_maintenance_request_checklist_item.attrs ->> 'rank', y."rank"),
        "done" = coalesce(v_done, y."done"),
        "done_at" = case when v_done is null then y."done_at" when v_done then coalesce(y."done_at", now()) end,
        "done_by" = case when v_done is null then y."done_by" when v_done then coalesce(y."done_by", auth.uid()) end
      where y."id" = v_id and y."maintenance_request_id" = v_row."id";
      if not found then
        raise exception 'no such checklist item on this work item' using errcode = 'P0002', hint = 'WORK_ITEM_CHECKLIST_ITEM_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a checklist item needs a title of 1 to 500 characters and a valid rank' using errcode = '22023', hint = 'WORK_ITEM_CHECKLIST_ITEM_INVALID';
  end;
  perform "better_supabase".emit_event('maintenance_request.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist')), 'maintenance-requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/maintenance');
  return (select jsonb_build_object('id', y."id", 'maintenanceRequestId', y."maintenance_request_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") from "better_supabase"."maintenance_request_checklist_items" y where y."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_maintenance_request_checklist_item"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_maintenance_request_checklist_item"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_maintenance_request_checklist_item"(checklist_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."maintenance_requests";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x.* into v_row from "better_supabase"."maintenance_requests" x join "better_supabase"."maintenance_request_checklist_items" y on y."maintenance_request_id" = x."id"
  where y."id" = delete_maintenance_request_checklist_item.checklist_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance_requests.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    return false;
  end if;
  delete from "better_supabase"."maintenance_request_checklist_items" y where y."id" = delete_maintenance_request_checklist_item.checklist_item;
  perform "better_supabase".emit_event('maintenance_request.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist')), 'maintenance-requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/maintenance');
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_maintenance_request_checklist_item"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_maintenance_request_checklist_item"(uuid) to authenticated, service_role;

-- An item's checklist, in rank order.
create or replace function "better_supabase"."list_maintenance_request_checklist"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'maintenanceRequestId', y."maintenance_request_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") order by y."rank" collate "C", y."id"), '[]'::jsonb)
  from "better_supabase"."maintenance_request_checklist_items" y where y."maintenance_request_id" = list_maintenance_request_checklist.work_item
$$;
revoke execute on function "better_supabase"."list_maintenance_request_checklist"(uuid) from public, anon;
grant execute on function "better_supabase"."list_maintenance_request_checklist"(uuid) to authenticated, service_role;

-- One item the caller can read, or null.
create or replace function "better_supabase"."get_maintenance_request"(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) from "better_supabase"."maintenance_requests" x where x."id" = get_maintenance_request.work_item
$$;
revoke execute on function "better_supabase"."get_maintenance_request"(uuid) from public, anon;
grant execute on function "better_supabase"."get_maintenance_request"(uuid) to authenticated, service_role;

-- Makes an item repeat: rrule is an RFC 5545 RRULE starting at the item's
-- due date (now without one) in tzid. A null rrule stops it. Completing the
-- item then creates the next one through repeat_work_item.
create or replace function "better_supabase"."set_maintenance_request_recurrence"(work_item uuid, rrule text, tzid text default 'UTC')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."maintenance_requests";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = set_maintenance_request_recurrence.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance_requests.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
  end if;
  if set_maintenance_request_recurrence.rrule is null then
    delete from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = v_row."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = v_row."id"::text;
  else
    if set_maintenance_request_recurrence.rrule !~ '^(RRULE:)?FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)(;[A-Z]+=[-+,0-9A-Z]+)*$' then
      raise exception 'rrule must be an RRULE such as FREQ=WEEKLY;BYDAY=MO' using errcode = '22023', hint = 'WORK_ITEM_RECURRENCE_INVALID';
    end if;
    if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = coalesce(set_maintenance_request_recurrence.tzid, 'UTC')) then
      raise exception 'tzid must be an IANA time zone' using errcode = '22023', hint = 'WORK_ITEM_RECURRENCE_INVALID';
    end if;
    insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
    values (v_row."tenant_id", 'maintenance_request', v_row."id"::text, coalesce(v_row."due_at", now()), coalesce(set_maintenance_request_recurrence.tzid, 'UTC'), regexp_replace(set_maintenance_request_recurrence.rrule, '^RRULE:', ''))
    on conflict ("tenant_id", "subject_type", "subject_id")
    do update set "dtstart" = excluded."dtstart", "tzid" = excluded."tzid", "rrule" = excluded."rrule";
  end if;
  perform "better_supabase".emit_event('maintenance_request.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('recurrence')), 'maintenance-requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/maintenance');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) -> 'recurrence' from "better_supabase"."maintenance_requests" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."set_maintenance_request_recurrence"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."set_maintenance_request_recurrence"(uuid, text, text) to authenticated, service_role;

-- Creates the next item of a repeating item, due at due_at: a copy with its
-- dates shifted, its assignees and an unchecked checklist. The rule moves to
-- the copy. Runs once per item; a second call returns the same copy.
create or replace function "better_supabase"."repeat_maintenance_request"(work_item uuid, due_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_src "better_supabase"."maintenance_requests";
  v_next jsonb;
  v_id uuid;
  v_shift interval;
begin
  select * into v_src from "better_supabase"."maintenance_requests" x where x."id" = repeat_maintenance_request.work_item for update;
  if v_src."id" is null then
    raise exception 'work item not found' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
  end if;
  select x."id" into v_id from "better_supabase"."maintenance_requests" x where x."recurs_from" = v_src."id";
  if v_id is not null then
    return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) from "better_supabase"."maintenance_requests" x where x."id" = v_id);
  end if;
  v_shift := coalesce(repeat_maintenance_request.due_at - coalesce(v_src."due_at", v_src."end_at", v_src."start_at"), interval '0');
  v_next := "better_supabase"."create_maintenance_request"(v_src."tenant_id", jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title", 'body', v_src."body", 'parentId', v_src."parent_id", 'teamId', v_src."team_id",
    'projectId', v_src."project_id", 'priority', v_src."priority", 'estimate', v_src."estimate",
    'startAt', v_src."start_at" + v_shift, 'endAt', v_src."end_at" + v_shift, 'dueAt', repeat_maintenance_request.due_at,
    'pipelineId', v_src."pipeline_id")) || jsonb_build_object('fields', jsonb_build_object('unit_id', v_src."unit_id", 'lease_id', v_src."lease_id")),
    array(select y."user_id" from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_src."id"));
  v_id := (v_next ->> 'id')::uuid;
  update "better_supabase"."maintenance_requests" x set "recurs_from" = v_src."id" where x."id" = v_id;
  insert into "better_supabase"."maintenance_request_checklist_items" ("tenant_id", "maintenance_request_id", "title", "rank", "created_by")
  select y."tenant_id", v_id, y."title", y."rank", y."created_by" from "better_supabase"."maintenance_request_checklist_items" y where y."maintenance_request_id" = v_src."id";
  update "better_supabase"."recurrence_rules" rr set "subject_id" = v_id::text
  where rr."tenant_id" = v_src."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = v_src."id"::text;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) from "better_supabase"."maintenance_requests" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."repeat_maintenance_request"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."repeat_maintenance_request"(uuid, timestamptz) to service_role;

-- Watches (all), follows (participating) or ignores an item the caller can
-- read; a null level removes the choice.
create or replace function "better_supabase"."watch_maintenance_request"(work_item uuid, level text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."maintenance_requests";
begin
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = watch_maintenance_request.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance_requests.read'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can read' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
  end if;
  perform "better_supabase"."set_notification_subscription"('maintenance_request', v_row."id"::text, watch_maintenance_request.level, v_row."tenant_id");
  return watch_maintenance_request.level is not null;
end;
$$;
revoke execute on function "better_supabase"."watch_maintenance_request"(uuid, text) from public, anon;
grant execute on function "better_supabase"."watch_maintenance_request"(uuid, text) to authenticated, service_role;

-- Who watches (all) or follows (participating) an item: [{ userId, level }].
create or replace function "better_supabase"."list_maintenance_request_watchers"(work_item uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', s."user_id", 'level', s."level") order by s."level", s."user_id"), '[]'::jsonb)
  from "better_supabase"."maintenance_requests" x
  join "better_supabase"."notification_subscriptions" s on s."subject_type" = 'maintenance_request' and s."subject_id" = x."id"::text
    and s."organization_id" = x."tenant_id"
  where x."id" = list_maintenance_request_watchers.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance_requests.read'), false)) and s."level" in ('all', 'participating')
$$;
revoke execute on function "better_supabase"."list_maintenance_request_watchers"(uuid) from public, anon;
grant execute on function "better_supabase"."list_maintenance_request_watchers"(uuid) to authenticated, service_role;

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

create or replace function "api"."create_maintenance_request"(tenant uuid, attrs jsonb, assignees uuid[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_maintenance_request"($1, $2, $3) $$;
revoke execute on function "api"."create_maintenance_request"(uuid, jsonb, uuid[]) from public, anon;
grant execute on function "api"."create_maintenance_request"(uuid, jsonb, uuid[]) to authenticated, service_role;

create or replace function "api"."update_maintenance_requests"(changes jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_maintenance_requests"($1) $$;
revoke execute on function "api"."update_maintenance_requests"(jsonb) from public, anon;
grant execute on function "api"."update_maintenance_requests"(jsonb) to authenticated, service_role;

create or replace function "api"."set_maintenance_request_assignees"(work_item uuid, users uuid[])
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_maintenance_request_assignees"($1, $2) $$;
revoke execute on function "api"."set_maintenance_request_assignees"(uuid, uuid[]) from public, anon;
grant execute on function "api"."set_maintenance_request_assignees"(uuid, uuid[]) to authenticated, service_role;

create or replace function "api"."archive_maintenance_request"(work_item uuid, archived boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_maintenance_request"($1, $2) $$;
revoke execute on function "api"."archive_maintenance_request"(uuid, boolean) from public, anon;
grant execute on function "api"."archive_maintenance_request"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."delete_maintenance_request"(work_item uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_maintenance_request"($1) $$;
revoke execute on function "api"."delete_maintenance_request"(uuid) from public, anon;
grant execute on function "api"."delete_maintenance_request"(uuid) to authenticated, service_role;

create or replace function "api"."maintenance_request_tree"(root uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."maintenance_request_tree"($1) $$;
revoke execute on function "api"."maintenance_request_tree"(uuid) from public, anon;
grant execute on function "api"."maintenance_request_tree"(uuid) to authenticated, service_role;

create or replace function "api"."list_maintenance_requests"(tenant uuid, filter jsonb, search text, after uuid, page_size integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_maintenance_requests"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_maintenance_requests"(uuid, jsonb, text, uuid, integer) from public, anon;
grant execute on function "api"."list_maintenance_requests"(uuid, jsonb, text, uuid, integer) to authenticated, service_role;

create or replace function "api"."save_maintenance_request_checklist_item"(work_item uuid, checklist_item uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_maintenance_request_checklist_item"($1, $2, $3) $$;
revoke execute on function "api"."save_maintenance_request_checklist_item"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_maintenance_request_checklist_item"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_maintenance_request_checklist_item"(checklist_item uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_maintenance_request_checklist_item"($1) $$;
revoke execute on function "api"."delete_maintenance_request_checklist_item"(uuid) from public, anon;
grant execute on function "api"."delete_maintenance_request_checklist_item"(uuid) to authenticated, service_role;

create or replace function "api"."list_maintenance_request_checklist"(work_item uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_maintenance_request_checklist"($1) $$;
revoke execute on function "api"."list_maintenance_request_checklist"(uuid) from public, anon;
grant execute on function "api"."list_maintenance_request_checklist"(uuid) to authenticated, service_role;

create or replace function "api"."get_maintenance_request"(work_item uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_maintenance_request"($1) $$;
revoke execute on function "api"."get_maintenance_request"(uuid) from public, anon;
grant execute on function "api"."get_maintenance_request"(uuid) to authenticated, service_role;

create or replace function "api"."set_maintenance_request_recurrence"(work_item uuid, rrule text, tzid text default 'UTC')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_maintenance_request_recurrence"($1, $2, $3) $$;
revoke execute on function "api"."set_maintenance_request_recurrence"(uuid, text, text) from public, anon;
grant execute on function "api"."set_maintenance_request_recurrence"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."repeat_maintenance_request"(work_item uuid, due_at timestamptz)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."repeat_maintenance_request"($1, $2) $$;
revoke execute on function "api"."repeat_maintenance_request"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "api"."repeat_maintenance_request"(uuid, timestamptz) to service_role;

create or replace function "api"."watch_maintenance_request"(work_item uuid, level text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."watch_maintenance_request"($1, $2) $$;
revoke execute on function "api"."watch_maintenance_request"(uuid, text) from public, anon;
grant execute on function "api"."watch_maintenance_request"(uuid, text) to authenticated, service_role;

create or replace function "api"."list_maintenance_request_watchers"(work_item uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_maintenance_request_watchers"($1) $$;
revoke execute on function "api"."list_maintenance_request_watchers"(uuid) from public, anon;
grant execute on function "api"."list_maintenance_request_watchers"(uuid) to authenticated, service_role;

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
