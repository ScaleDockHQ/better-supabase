SET local check_function_bodies = off;

DROP TRIGGER "bsb_audit" ON "better_supabase"."maintenance_requests";

DROP TRIGGER "bsb_audit" ON "better_supabase"."work_items";

DROP FUNCTION "api"."archive_maintenance_request"(uuid, boolean);

DROP FUNCTION "api"."archive_work_item"(uuid, boolean);

DROP FUNCTION "api"."delete_maintenance_request"(uuid);

DROP FUNCTION "api"."delete_work_item"(uuid);

DROP FUNCTION "api"."get_maintenance_request"(uuid);

DROP FUNCTION "api"."get_work_item"(uuid);

DROP FUNCTION "api"."list_maintenance_request_checklist"(uuid);

DROP FUNCTION "api"."list_maintenance_request_watchers"(uuid);

DROP FUNCTION "api"."list_work_item_checklist"(uuid);

DROP FUNCTION "api"."list_work_item_watchers"(uuid);

DROP FUNCTION "api"."repeat_maintenance_request"(uuid, timestamp WITH time zone);

DROP FUNCTION "api"."repeat_work_item"(uuid, timestamp WITH time zone);

DROP FUNCTION "api"."save_maintenance_request_checklist_item"(uuid, uuid, jsonb);

DROP FUNCTION "api"."save_work_item_checklist_item"(uuid, uuid, jsonb);

DROP FUNCTION "api"."set_maintenance_request_assignees"(uuid, uuid[]);

DROP FUNCTION "api"."set_maintenance_request_recurrence"(uuid, text, text);

DROP FUNCTION "api"."set_work_item_assignees"(uuid, uuid[]);

DROP FUNCTION "api"."set_work_item_recurrence"(uuid, text, text);

DROP FUNCTION "api"."watch_maintenance_request"(uuid, text);

DROP FUNCTION "api"."watch_work_item"(uuid, text);

DROP FUNCTION "better_supabase"."archive_maintenance_request"(uuid, boolean);

DROP FUNCTION "better_supabase"."archive_work_item"(uuid, boolean);

DROP FUNCTION "better_supabase"."delete_maintenance_request"(uuid);

DROP FUNCTION "better_supabase"."delete_work_item"(uuid);

DROP FUNCTION "better_supabase"."get_maintenance_request"(uuid);

DROP FUNCTION "better_supabase"."get_work_item"(uuid);

DROP FUNCTION "better_supabase"."list_maintenance_request_checklist"(uuid);

DROP FUNCTION "better_supabase"."list_maintenance_request_watchers"(uuid);

DROP FUNCTION "better_supabase"."list_work_item_checklist"(uuid);

DROP FUNCTION "better_supabase"."list_work_item_watchers"(uuid);

DROP FUNCTION "better_supabase"."repeat_maintenance_request"(uuid, timestamp WITH time zone);

DROP FUNCTION "better_supabase"."repeat_work_item"(uuid, timestamp WITH time zone);

DROP FUNCTION "better_supabase"."save_maintenance_request_checklist_item"(uuid, uuid, jsonb);

DROP FUNCTION "better_supabase"."save_work_item_checklist_item"(uuid, uuid, jsonb);

DROP FUNCTION "better_supabase"."set_maintenance_request_assignees"(uuid, uuid[]);

DROP FUNCTION "better_supabase"."set_maintenance_request_recurrence"(uuid, text, text);

DROP FUNCTION "better_supabase"."set_work_item_assignees"(uuid, uuid[]);

DROP FUNCTION "better_supabase"."set_work_item_recurrence"(uuid, text, text);

DROP FUNCTION "better_supabase"."watch_maintenance_request"(uuid, text);

DROP FUNCTION "better_supabase"."watch_work_item"(uuid, text);

CREATE OR REPLACE FUNCTION api.archive_maintenance_request (
  task     uuid,
  archived boolean
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_maintenance_request"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.archive_work_item (
  task     uuid,
  archived boolean
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_work_item"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.delete_maintenance_request (
  task uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_maintenance_request"($1) $function$;

CREATE OR REPLACE FUNCTION api.delete_work_item (
  task uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_work_item"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_maintenance_request (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_maintenance_request"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_work_item (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_work_item"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_maintenance_request_checklist (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_maintenance_request_checklist"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_maintenance_request_watchers (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_maintenance_request_watchers"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_work_item_checklist (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_work_item_checklist"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_work_item_watchers (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_work_item_watchers"($1) $function$;

CREATE OR REPLACE FUNCTION api.repeat_maintenance_request (
  task   uuid,
  due_at timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."repeat_maintenance_request"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.repeat_work_item (
  task   uuid,
  due_at timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."repeat_work_item"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.save_maintenance_request_checklist_item (
  task           uuid,
  checklist_item uuid,
  attrs          jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_maintenance_request_checklist_item"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.save_work_item_checklist_item (
  task           uuid,
  checklist_item uuid,
  attrs          jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_work_item_checklist_item"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_maintenance_request_assignees (
  task  uuid,
  users uuid[]
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_maintenance_request_assignees"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_maintenance_request_recurrence (
  task  uuid,
  rrule text,
  tzid  text DEFAULT 'UTC'::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_maintenance_request_recurrence"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_work_item_assignees (
  task  uuid,
  users uuid[]
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_work_item_assignees"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_work_item_recurrence (
  task  uuid,
  rrule text,
  tzid  text DEFAULT 'UTC'::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_work_item_recurrence"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.watch_maintenance_request (
  task  uuid,
  level text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."watch_maintenance_request"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.watch_work_item (
  task  uuid,
  level text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."watch_work_item"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.add_meeting_action_item (
  meeting_id     uuid,
  task           jsonb,
  assignees      uuid[] DEFAULT '{}'::uuid[],
  agenda_item_id uuid   DEFAULT NULL::uuid,
  decision_id    uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."meetings";
  v_task jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = add_meeting_action_item.meeting_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to add action items to this meeting' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if add_meeting_action_item.agenda_item_id is not null and not exists (
    select 1 from "better_supabase"."meeting_agenda_items" y where y."id" = add_meeting_action_item.agenda_item_id and y."meeting_id" = v_row."id"
  ) then
    raise exception 'the agenda item belongs to another meeting' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if add_meeting_action_item.decision_id is not null and not exists (
    select 1 from "better_supabase"."meeting_decisions" y where y."id" = add_meeting_action_item.decision_id and y."meeting_id" = v_row."id"
  ) then
    raise exception 'the decision belongs to another meeting' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  v_task := "better_supabase"."create_work_item"(v_row."tenant_id", add_meeting_action_item.task, coalesce(add_meeting_action_item.assignees, '{}'));
  insert into "better_supabase"."meeting_action_items" ("task_id", "tenant_id", "meeting_id", "agenda_item_id", "decision_id")
  values ((v_task ->> 'id')::uuid, v_row."tenant_id", v_row."id", add_meeting_action_item.agenda_item_id, add_meeting_action_item.decision_id);
  perform "better_supabase".emit_event('meeting_action_item.created', jsonb_build_object('organizationId', v_row."tenant_id", 'meetingId', v_row."id", 'taskId', (v_task ->> 'id')::uuid, 'title', v_task ->> 'title'), 'meetings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/meetings');
  return v_task || jsonb_build_object('meetingId', v_row."id", 'agendaItemId', add_meeting_action_item.agenda_item_id, 'decisionId', add_meeting_action_item.decision_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_maintenance_request (
  task     uuid,
  archived boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."maintenance_requests" x set "archived_at" = case when archive_maintenance_request.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_maintenance_request.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_maintenance_request.archived then
    perform "better_supabase".emit_event('maintenance_request.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_maintenance_requests (
  ids      uuid[],
  archived boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_ids uuid[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  for v_row in
    with changed as (
      update "better_supabase"."maintenance_requests" x set "archived_at" = case when archive_maintenance_requests.archived then coalesce(x."archived_at", now()) end
      where x."id" = any (coalesce(archive_maintenance_requests.ids, '{}')) and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false))
      returning x.*
    )
    select * from changed
  loop
    v_ids := array_append(v_ids, v_row."id");
    if archive_maintenance_requests.archived then
      perform "better_supabase".emit_event('maintenance_request.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
    end if;
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(archive_maintenance_requests.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_work_item (
  task     uuid,
  archived boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."work_items" x set "archived_at" = case when archive_work_item.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_work_item.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_work_item.archived then
    perform "better_supabase".emit_event('work_item.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_work_items (
  ids      uuid[],
  archived boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_ids uuid[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
      perform "better_supabase".emit_event('work_item.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
    end if;
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(archive_work_items.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_maintenance_request_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'TASK_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "better_supabase"."maintenance_requests" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
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
      perform "better_supabase".emit_event('maintenance_request.closed', jsonb_build_object('organizationId', new."tenant_id", 'maintenanceRequestId', new."id", 'subjectType', 'maintenance_request', 'subjectId', new."id"::text, 'title', new."title", 'state', new."state", 'closeReason', new."close_reason"), 'maintenance_requests/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/facilities');
    elsif not (new."state" in ('completed', 'canceled')) and old."state" in ('completed', 'canceled') then
      new."closed_at" := null;
      new."close_reason" := null;
      perform "better_supabase".emit_event('maintenance_request.reopened', jsonb_build_object('organizationId', new."tenant_id", 'maintenanceRequestId', new."id", 'subjectType', 'maintenance_request', 'subjectId', new."id"::text, 'title', new."title"), 'maintenance_requests/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/facilities');
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_work_item_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
      if new."state" = 'completed' and new."progress" is not null then
        new."progress" := 100;
      end if;
      perform "better_supabase".emit_event('work_item.closed', jsonb_build_object('organizationId', new."tenant_id", 'workItemId', new."id", 'subjectType', 'work_item', 'subjectId', new."id"::text, 'title', new."title", 'state', new."state", 'closeReason', new."close_reason"), 'work_items/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/tasks');
    elsif not (new."state" in ('completed', 'canceled')) and old."state" in ('completed', 'canceled') then
      new."closed_at" := null;
      new."close_reason" := null;
      perform "better_supabase".emit_event('work_item.reopened', jsonb_build_object('organizationId', new."tenant_id", 'workItemId', new."id", 'subjectType', 'work_item', 'subjectId', new."id"::text, 'title', new."title"), 'work_items/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/tasks');
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_maintenance_request (
  tenant    uuid,
  attrs     jsonb,
  assignees uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_maintenance_request.tenant, 'facilities.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if nullif(trim(create_maintenance_request.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'TASK_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_maintenance_request_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_maintenance_request.tenant, create_maintenance_request.attrs;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'maintenance_request' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'maintenance_request' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_maintenance_request.tenant::text || ':maintenance_request', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."maintenance_requests" x where x."tenant_id" = create_maintenance_request.tenant;
  v_identifier := 'MR' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."maintenance_requests" ("tenant_id", "number", "identifier", "title", "body", "parent_id", "team_id", "project_id", "iteration_id",
      "priority", "estimate", "progress", "start_at", "end_at", "due_at", "pipeline_id", "stage_id", "created_by", "unit_id", "lease_id")
    values (create_maintenance_request.tenant, v_seq, v_identifier, trim(create_maintenance_request.attrs ->> 'title'), create_maintenance_request.attrs ->> 'body',
      (create_maintenance_request.attrs ->> 'parentId')::uuid, (create_maintenance_request.attrs ->> 'teamId')::uuid, (create_maintenance_request.attrs ->> 'projectId')::uuid,
      (create_maintenance_request.attrs ->> 'iterationId')::uuid, coalesce((create_maintenance_request.attrs ->> 'priority')::smallint, 0),
      (create_maintenance_request.attrs ->> 'estimate')::numeric, (create_maintenance_request.attrs ->> 'progress')::smallint,
      (create_maintenance_request.attrs ->> 'startAt')::timestamptz, (create_maintenance_request.attrs ->> 'endAt')::timestamptz, (create_maintenance_request.attrs ->> 'dueAt')::timestamptz,
      (create_maintenance_request.attrs ->> 'pipelineId')::uuid, (create_maintenance_request.attrs ->> 'stageId')::uuid, auth.uid(), case when (create_maintenance_request.attrs -> 'fields') ? 'unit_id' then (jsonb_populate_record(null::"better_supabase"."maintenance_requests", jsonb_build_object('unit_id', (create_maintenance_request.attrs -> 'fields') -> 'unit_id')))."unit_id" else better_supabase.column_default('"better_supabase"."maintenance_requests"', 'unit_id', (null::"better_supabase"."maintenance_requests")."unit_id") end, case when (create_maintenance_request.attrs -> 'fields') ? 'lease_id' then (jsonb_populate_record(null::"better_supabase"."maintenance_requests", jsonb_build_object('lease_id', (create_maintenance_request.attrs -> 'fields') -> 'lease_id')))."lease_id" else better_supabase.column_default('"better_supabase"."maintenance_requests"', 'lease_id', (null::"better_supabase"."maintenance_requests")."lease_id") end)
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  update "better_supabase"."maintenance_requests" x set "unit_id" = case when (create_maintenance_request.attrs -> 'fields') ? 'unit_id' then r."unit_id" else x."unit_id" end, "lease_id" = case when (create_maintenance_request.attrs -> 'fields') ? 'lease_id' then r."lease_id" else x."lease_id" end
  from jsonb_populate_record(null::"better_supabase"."maintenance_requests", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each((create_maintenance_request.attrs -> 'fields')) e where e.key in ('unit_id', 'lease_id'))) r
  where x."id" = v_id;
  if cardinality(coalesce(create_maintenance_request.assignees, '{}')) > 0 then
    perform "better_supabase"."set_maintenance_request_assignees"(v_id, create_maintenance_request.assignees);
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = v_id;
  if jsonb_typeof(coalesce((create_maintenance_request.attrs -> 'attachments'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((create_maintenance_request.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'maintenance_request', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((create_maintenance_request.attrs -> 'attachments'))::uuid))
        and f."tenant_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'maintenance_request' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((create_maintenance_request.attrs -> 'attachments')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
      end if;
    end if;
  perform "better_supabase".emit_event('maintenance_request.created', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_work_item (
  tenant    uuid,
  attrs     jsonb,
  assignees uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
  perform "better_supabase".emit_event('work_item.created', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_maintenance_request (
  task uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."maintenance_requests" x
  where x."id" = delete_maintenance_request.task
    and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  perform "better_supabase".emit_event('maintenance_request.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_maintenance_request_checklist_item (
  checklist_item uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x.* into v_row from "better_supabase"."maintenance_requests" x join "better_supabase"."maintenance_request_checklist_items" y on y."maintenance_request_id" = x."id"
  where y."id" = delete_maintenance_request_checklist_item.checklist_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    return false;
  end if;
  delete from "better_supabase"."maintenance_request_checklist_items" y where y."id" = delete_maintenance_request_checklist_item.checklist_item;
  perform "better_supabase".emit_event('maintenance_request.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist')), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_maintenance_requests (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_ids uuid[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  for v_row in
    with removed as (
      delete from "better_supabase"."maintenance_requests" x
      where x."id" = any (coalesce(delete_maintenance_requests.ids, '{}'))
        and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.manage'), false))
      returning x.*
    )
    select * from removed
  loop
    v_ids := array_append(v_ids, v_row."id");
    perform "better_supabase".emit_event('maintenance_request.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(delete_maintenance_requests.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_work_item (
  task uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
  perform "better_supabase".emit_event('work_item.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_work_item_checklist_item (
  checklist_item uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
  perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist')), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_work_items (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
    perform "better_supabase".emit_event('work_item.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(delete_work_items.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_asset (
  asset_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  select * into v_row from "better_supabase"."assets" x where x."id" = get_asset.asset_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text) || (select jsonb_build_object('accumulatedDepreciation', q.total::text, 'bookValue', case when v_row."acquisition_cost" is null then null else (v_row."acquisition_cost" - q.total)::text end) from (select coalesce(sum(y."amount"), 0) as total from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id") q) || jsonb_build_object(
    'locationPath', case when v_row."location_id" is null then '[]'::jsonb else coalesce((
    with recursive up as (
      select y."id" as id, y."parent_id" as parent, y."kind" as kind, y."name" as name, 0 as depth from "better_supabase"."asset_locations" y where y."id" = v_row."location_id"
      union all
      select y."id", y."parent_id", y."kind", y."name", up.depth + 1 from "better_supabase"."asset_locations" y join up on y."id" = up.parent where up.depth < 64
    )
    select jsonb_agg(jsonb_build_object('id', up.id, 'kind', up.kind, 'name', up.name) order by up.depth desc) from up
  ), '[]'::jsonb) end,
    'links', jsonb_build_object('bookingResources', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name") order by y."name") from "better_supabase"."booking_resources" y where y.asset_id = v_row."id"), '[]'::jsonb), 'tasks', coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'title', z.title) order by z.created_at desc) from (select y."id" as id, y."title" as title, y."created_at" as created_at from "better_supabase"."work_items" y where y.asset_id = v_row."id" and y."closed_at" is null order by y."created_at" desc limit 50) z), '[]'::jsonb)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_maintenance_request (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) from "better_supabase"."maintenance_requests" x where x."id" = get_maintenance_request.task
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_meeting (
  meeting_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."meetings";
begin
  select * into v_row from "better_supabase"."meetings" x where x."id" = get_meeting.meeting_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', v_row."room_code"))) || jsonb_build_object(
    'attendees', coalesce((
      select jsonb_agg(jsonb_build_object('meetingId', y."meeting_id", 'userId', y."user_id", 'role', y."role", 'attendance', y."attendance")
        order by case y."role" when 'chair' then 0 when 'secretary' then 1 when 'attendee' then 2 else 3 end, y."created_at")
      from "better_supabase"."meeting_attendees" y where y."tenant_id" = v_row."tenant_id" and y."meeting_id" = v_row."id"
    ), '[]'::jsonb),
    'agenda', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'meetingId', y."meeting_id", 'ordinal', y."ordinal", 'title', y."title", 'notes', y."notes", 'presenterId', y."presenter_id", 'minutes', y."minutes", 'status', y."status", 'outcome', y."outcome") order by y."ordinal")
      from "better_supabase"."meeting_agenda_items" y where y."tenant_id" = v_row."tenant_id" and y."meeting_id" = v_row."id"
    ), '[]'::jsonb),
    'decisions', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'meetingId', y."meeting_id", 'agendaItemId', y."agenda_item_id", 'title', y."title", 'body', y."body", 'status', y."status", 'decidedBy', y."decided_by", 'decidedAt', y."decided_at", 'createdAt', y."created_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(y."tenant_id", 'meeting_decision', y."id"::text)) order by y."created_at")
      from "better_supabase"."meeting_decisions" y where y."tenant_id" = v_row."tenant_id" and y."meeting_id" = v_row."id"
    ), '[]'::jsonb),
    'actionItems', coalesce((
      select jsonb_agg(jsonb_build_object('taskId', z."id", 'title', z."title", 'state', z."state", 'dueAt', z."due_at",
        'agendaItemId', y."agenda_item_id", 'decisionId', y."decision_id") order by y."created_at")
      from "better_supabase"."meeting_action_items" y join "better_supabase"."work_items" z on z."id" = y."task_id"
      where y."tenant_id" = v_row."tenant_id" and y."meeting_id" = v_row."id"
    ), '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_work_item (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) from "better_supabase"."work_items" x where x."id" = get_work_item.task
$function$;

CREATE OR REPLACE FUNCTION better_supabase.goal_progress (
  tenant  uuid,
  on_date date,
  owner   uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg((to_jsonb(p) || jsonb_build_object('goal', p."goal"::text, 'actual', p."actual"::text)) - 'period_start_order' - 'name_order' order by p.period_start_order, p.name_order), '[]'::jsonb)
  from (
    select x.*, v.value::text as progress, round(v.value::numeric / x."goal", 4) as attainment, x."period_start" as period_start_order, x."name" as name_order
    from "better_supabase"."goals" x
    cross join lateral (select case x."metric"
        when 'deals.won_amount' then (select coalesce(sum(d."amount"), 0) from "better_supabase"."deals" d where d."tenant_id" = x."tenant_id" and d."outcome" = 'won' and d."closed_at"::date between x."period_start" and x."period_end"
        and (x."owner_id" is null or d."owner_id" = x."owner_id") and d."currency" = x."currency")
        when 'deals.won_count' then (select count(*) from "better_supabase"."deals" d where d."tenant_id" = x."tenant_id" and d."outcome" = 'won' and d."closed_at"::date between x."period_start" and x."period_end"
        and (x."owner_id" is null or d."owner_id" = x."owner_id"))
        when 'tasks.completed' then (select count(*) from "better_supabase"."work_items" w
      where w."tenant_id" = x."tenant_id" and w."state" = 'completed' and w."closed_at"::date between x."period_start" and x."period_end"
        and (x."team_id" is null or w."team_id" = x."team_id")
        and (x."owner_id" is null or exists (select 1 from "better_supabase"."work_item_assignees" a where a."work_item_id" = w."id" and a."user_id" = x."owner_id")))
        when 'invoices.paid_amount' then (select coalesce(sum(e."amount"), 0) from "better_supabase"."ledger_entries" e
      join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
      join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
      where a."tenant_id" = x."tenant_id" and a."managed_by" = 'invoices' and a."code" = 'invoices:cash:' || x."currency" and y."effective_at"::date between x."period_start" and x."period_end")
        else x."actual"
      end as value) v
    where x."tenant_id" = goal_progress.tenant and x."archived_at" is null
      and coalesce(goal_progress.on_date, current_date) between x."period_start" and x."period_end"
      and (goal_progress.owner is null or x."owner_id" = goal_progress.owner)
  ) p
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_maintenance_request_checklist (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'maintenanceRequestId', y."maintenance_request_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") order by y."rank" collate "C", y."id"), '[]'::jsonb)
  from "better_supabase"."maintenance_request_checklist_items" y where y."maintenance_request_id" = list_maintenance_request_checklist.task
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_maintenance_request_watchers (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('userId', s."user_id", 'level', s."level") order by s."level", s."user_id"), '[]'::jsonb)
  from "better_supabase"."maintenance_requests" x
  join "better_supabase"."notification_subscriptions" s on s."subject_type" = 'maintenance_request' and s."subject_id" = x."id"::text
    and s."tenant_id" = x."tenant_id"
  where x."id" = list_maintenance_request_watchers.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.read'), false)) and s."level" in ('all', 'participating')
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_work_item_checklist (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'workItemId', y."work_item_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") order by y."rank" collate "C", y."id"), '[]'::jsonb)
  from "better_supabase"."work_item_checklist_items" y where y."work_item_id" = list_work_item_checklist.task
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_work_item_watchers (
  task uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('userId', s."user_id", 'level', s."level") order by s."level", s."user_id"), '[]'::jsonb)
  from "better_supabase"."work_items" x
  join "better_supabase"."notification_subscriptions" s on s."subject_type" = 'work_item' and s."subject_id" = x."id"::text
    and s."tenant_id" = x."tenant_id"
  where x."id" = list_work_item_watchers.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)) and s."level" in ('all', 'participating')
$function$;

CREATE OR REPLACE FUNCTION better_supabase.repeat_maintenance_request (
  task   uuid,
  due_at timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_src "better_supabase"."maintenance_requests";
  v_next jsonb;
  v_id uuid;
  v_shift interval;
begin
  select * into v_src from "better_supabase"."maintenance_requests" x where x."id" = repeat_maintenance_request.task for update;
  if v_src."id" is null then
    raise exception 'work item not found' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.repeat_work_item (
  task   uuid,
  due_at timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_maintenance_request_checklist_item (
  task           uuid,
  checklist_item uuid,
  attrs          jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_id uuid := save_maintenance_request_checklist_item.checklist_item;
  v_last text;
  v_done boolean := (save_maintenance_request_checklist_item.attrs ->> 'done')::boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = save_maintenance_request_checklist_item.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
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
        raise exception 'no such checklist item on this work item' using errcode = 'P0002', hint = 'TASK_CHECKLIST_ITEM_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a checklist item needs a title of 1 to 500 characters and a valid rank' using errcode = '22023', hint = 'TASK_CHECKLIST_ITEM_INVALID';
  end;
  perform "better_supabase".emit_event('maintenance_request.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist')), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  return (select jsonb_build_object('id', y."id", 'maintenanceRequestId', y."maintenance_request_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") from "better_supabase"."maintenance_request_checklist_items" y where y."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_work_item_checklist_item (
  task           uuid,
  checklist_item uuid,
  attrs          jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
  perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist')), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select jsonb_build_object('id', y."id", 'workItemId', y."work_item_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") from "better_supabase"."work_item_checklist_items" y where y."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_asset_link (
  target_type text,
  target_id   uuid,
  asset_id    uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  case set_asset_link.target_type
  when 'booking_resource' then
    select y."tenant_id" into v_tenant from "better_supabase"."booking_resources" y where y."id" = set_asset_link.target_id;
  when 'task' then
    select y."tenant_id" into v_tenant from "better_supabase"."work_items" y where y."id" = set_asset_link.target_id;
  else
    raise exception 'target_type must be booking_resource or task' using errcode = '22023', hint = 'ASSETS_LINK_UNSUPPORTED';
  end case;
  if v_tenant is null then
    raise exception 'the record to link doesn''t exist' using errcode = 'P0002', hint = 'ASSETS_LINK_TARGET_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if set_asset_link.asset_id is not null and not exists (
    select 1 from "better_supabase"."assets" y where y."id" = set_asset_link.asset_id and y."tenant_id" = v_tenant
  ) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if set_asset_link.target_type = 'booking_resource' then
    update "better_supabase"."booking_resources" y set asset_id = set_asset_link.asset_id where y."id" = set_asset_link.target_id;
  end if;
  if set_asset_link.target_type in ('task') then
    update "better_supabase"."work_items" y set asset_id = set_asset_link.asset_id where y."id" = set_asset_link.target_id;
  end if;
  return jsonb_build_object('targetType', set_asset_link.target_type, 'targetId', set_asset_link.target_id, 'assetId', set_asset_link.asset_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_maintenance_request_assignees (
  task  uuid,
  users uuid[]
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_maintenance_request_assignees.users, '{}')) x where x is not null);
  v_added uuid[];
  v_new uuid[];
  v_claims text;
  v_user uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = set_maintenance_request_assignees.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id" and y."user_id" = x));
  v_added := array(select x from unnest(v_users) x where not exists (
    select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."maintenance_request_assignees" ("tenant_id", "maintenance_request_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  foreach v_user in array v_users loop
    insert into "better_supabase"."notification_subscriptions" ("tenant_id", "user_id", "subject_type", "subject_id", "level")
    values (v_row."tenant_id", v_user, 'maintenance_request', v_row."id"::text, 'participating')
    on conflict do nothing;
  end loop;
  if cardinality(v_new) > 0 then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'maintenance_request.assigned',
      'tenant', v_row."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'maintenance_request',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."title",
      'summary', v_row."title",
      'action_path', null,
      'recipients', to_jsonb(v_new),
      'watchers', false,
      'key', 'maintenance_request.assigned:' || v_row."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('maintenanceRequestId', v_row."id")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if cardinality(v_added) > 0 then
    perform "better_supabase".emit_event('maintenance_request.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(v_users), 'addedIds', to_jsonb(v_added)), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  end if;
  return cardinality(v_users);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_maintenance_request_recurrence (
  task  uuid,
  rrule text,
  tzid  text DEFAULT 'UTC'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = set_maintenance_request_recurrence.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if set_maintenance_request_recurrence.rrule is null then
    delete from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = v_row."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = v_row."id"::text;
  else
    if set_maintenance_request_recurrence.rrule !~ '^(RRULE:)?FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)(;[A-Z]+=[-+,0-9A-Z]+)*$' then
      raise exception 'rrule must be an RRULE such as FREQ=WEEKLY;BYDAY=MO' using errcode = '22023', hint = 'TASK_RECURRENCE_INVALID';
    end if;
    if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = coalesce(set_maintenance_request_recurrence.tzid, 'UTC')) then
      raise exception 'tzid must be an IANA time zone' using errcode = '22023', hint = 'TASK_RECURRENCE_INVALID';
    end if;
    insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
    values (v_row."tenant_id", 'maintenance_request', v_row."id"::text, coalesce(v_row."due_at", now()), coalesce(set_maintenance_request_recurrence.tzid, 'UTC'), regexp_replace(set_maintenance_request_recurrence.rrule, '^RRULE:', ''))
    on conflict ("tenant_id", "subject_type", "subject_id")
    do update set "dtstart" = excluded."dtstart", "tzid" = excluded."tzid", "rrule" = excluded."rrule";
  end if;
  perform "better_supabase".emit_event('maintenance_request.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('recurrence')), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) -> 'recurrence' from "better_supabase"."maintenance_requests" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_work_item_assignees (
  task  uuid,
  users uuid[]
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
    perform "better_supabase".emit_event('work_item.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(v_users), 'addedIds', to_jsonb(v_added)), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return cardinality(v_users);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_work_item_recurrence (
  task  uuid,
  rrule text,
  tzid  text DEFAULT 'UTC'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
  perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('recurrence')), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) -> 'recurrence' from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_maintenance_requests (
  changes jsonb,
  atomic  boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
    raise exception 'changes must be a list of { maintenanceRequestId, field, value }' using errcode = '22023', hint = 'TASK_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_maintenance_requests.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'maintenanceRequestId')::uuid;
      if not exists (select 1 from "better_supabase"."maintenance_requests" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
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
      when 'window' then
        if jsonb_typeof(v_change -> 'value') <> 'object' then
          raise exception 'window must be an object of startAt and endAt' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
        end if;
        update "better_supabase"."maintenance_requests" x set
          "start_at" = case when v_change -> 'value' ? 'startAt' then (v_change -> 'value' ->> 'startAt')::timestamptz else x."start_at" end,
          "end_at" = case when v_change -> 'value' ? 'endAt' then (v_change -> 'value' ->> 'endAt')::timestamptz else x."end_at" end
        where x."id" = v_item;
      when 'attachments' then
        select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = v_item;
        if jsonb_typeof(coalesce((v_change -> 'value'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'maintenance_request', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((v_change -> 'value'))::uuid))
        and f."tenant_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'maintenance_request' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((v_change -> 'value')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
      end if;
    end if;
      when 'unit_id' then
        update "better_supabase"."maintenance_requests" x set "unit_id" = (jsonb_populate_record(null::"better_supabase"."maintenance_requests", jsonb_build_object('unit_id', v_change -> 'value')))."unit_id" where x."id" = v_item;
      when 'lease_id' then
        update "better_supabase"."maintenance_requests" x set "lease_id" = (jsonb_populate_record(null::"better_supabase"."maintenance_requests", jsonb_build_object('lease_id', v_change -> 'value')))."lease_id" where x."id" = v_item;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'TASK_FIELD_UNKNOWN';
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
      if update_maintenance_requests.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('maintenanceRequestId', v_change ->> 'maintenanceRequestId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."maintenance_requests" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('maintenance_request.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'maintenanceRequestId')::uuid = v_row."id")), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_work_items (
  changes jsonb,
  atomic  boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
    raise exception 'changes must be a list of { workItemId, field, value }' using errcode = '22023', hint = 'TASK_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_work_items.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'workItemId')::uuid;
      if not exists (select 1 from "better_supabase"."work_items" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
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
    perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'workItemId')::uuid = v_row."id")), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.watch_maintenance_request (
  task  uuid,
  level text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
begin
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = watch_maintenance_request.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.read'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can read' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  perform "better_supabase"."set_notification_subscription"('maintenance_request', v_row."id"::text, watch_maintenance_request.level, v_row."tenant_id");
  return watch_maintenance_request.level is not null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.watch_work_item (
  task  uuid,
  level text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.maintenance_requests DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"maintenance_request","event_prefix":"maintenance_request"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.work_items DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"work_item","event_prefix":"work_item"}');

CREATE TRIGGER bsb_notifications_change_request_cascade
  AFTER DELETE ON public.change_requests
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.notifications_subject_deleted('change_request', 'id', 'organization_id');

CREATE TRIGGER bsb_notifications_customer_cascade
  AFTER DELETE ON public.customers
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.notifications_subject_deleted('customer', 'id', 'organization_id');

CREATE TRIGGER bsb_notifications_project_cascade
  AFTER DELETE ON public.projects
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.notifications_subject_deleted('project', 'id', 'organization_id');

CREATE TRIGGER bsb_notifications_task_cascade
  AFTER DELETE ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.notifications_subject_deleted('task', 'id', 'organization_id');

REVOKE ALL ON FUNCTION "api"."archive_maintenance_request"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_maintenance_request"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."archive_work_item"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_work_item"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_maintenance_request"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_maintenance_request"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_work_item"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_work_item"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_maintenance_request"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_maintenance_request"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_work_item"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_work_item"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_maintenance_request_checklist"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_maintenance_request_checklist"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_maintenance_request_watchers"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_maintenance_request_watchers"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_work_item_checklist"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_work_item_checklist"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_work_item_watchers"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_work_item_watchers"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."repeat_maintenance_request"(uuid, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."repeat_maintenance_request"(uuid, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "api"."repeat_work_item"(uuid, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."repeat_work_item"(uuid, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "api"."save_maintenance_request_checklist_item"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_maintenance_request_checklist_item"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_work_item_checklist_item"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_work_item_checklist_item"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_maintenance_request_assignees"(uuid, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_maintenance_request_assignees"(uuid, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_maintenance_request_recurrence"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_maintenance_request_recurrence"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_work_item_assignees"(uuid, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_work_item_assignees"(uuid, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_work_item_recurrence"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_work_item_recurrence"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."watch_maintenance_request"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."watch_maintenance_request"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."watch_work_item"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."watch_work_item"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_maintenance_request"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_maintenance_request"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_work_item"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_work_item"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_maintenance_request"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_maintenance_request"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_work_item"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_work_item"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_maintenance_request"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_maintenance_request"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_work_item"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_work_item"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_maintenance_request_checklist"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_maintenance_request_checklist"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_maintenance_request_watchers"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_maintenance_request_watchers"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_work_item_checklist"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_work_item_checklist"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_work_item_watchers"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_work_item_watchers"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."repeat_maintenance_request"(uuid, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."repeat_maintenance_request"(uuid, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."repeat_work_item"(uuid, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."repeat_work_item"(uuid, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_maintenance_request_checklist_item"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_maintenance_request_checklist_item"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_work_item_checklist_item"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_work_item_checklist_item"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_maintenance_request_assignees"(uuid, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_maintenance_request_assignees"(uuid, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_maintenance_request_recurrence"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_maintenance_request_recurrence"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_work_item_assignees"(uuid, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_work_item_assignees"(uuid, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_work_item_recurrence"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_work_item_recurrence"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."watch_maintenance_request"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."watch_maintenance_request"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."watch_work_item"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."watch_work_item"(uuid, text) TO "authenticated", "service_role";
