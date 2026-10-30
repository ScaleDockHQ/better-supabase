SET local check_function_bodies = off;

DROP FUNCTION "api"."save_calendar_event"(uuid, jsonb);

DROP FUNCTION "api"."update_maintenance_requests"(jsonb);

DROP FUNCTION "api"."update_work_items"(jsonb);

DROP FUNCTION "better_supabase"."save_calendar_event"(uuid, jsonb);

DROP FUNCTION "better_supabase"."update_maintenance_requests"(jsonb);

DROP FUNCTION "better_supabase"."update_work_items"(jsonb);

CREATE OR REPLACE FUNCTION api.save_calendar_event (
  calendar_id uuid,
  item        jsonb,
  actor       uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_calendar_event"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.update_maintenance_requests (
  changes jsonb,
  atomic  boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_maintenance_requests"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.update_work_items (
  changes jsonb,
  atomic  boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_work_items"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.save_calendar_event (
  calendar_id uuid,
  item        jsonb,
  actor       uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_calendar_event.item, '{}'::jsonb);
  v_tenant uuid;
  v_tz text;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
  v_master uuid := nullif(v_item ->> 'recurrenceId', '')::uuid;
  v_uid text := nullif(v_item ->> 'uid', '');
  v_created boolean := false;
  v_actor uuid := coalesce(save_calendar_event.actor, auth.uid());
  v_exdates timestamptz[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "tz" into v_tenant, v_tz from "better_supabase"."calendars" where "id" = save_calendar_event.calendar_id;
  if not found then
    raise exception 'calendar not found' using errcode = 'P0002', hint = 'CALENDAR_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if save_calendar_event.actor is not null and save_calendar_event.actor is distinct from auth.uid() and auth.role() <> 'service_role' then
    raise exception 'only the service role saves an event as another user' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;

  if v_item ? 'status' and v_item ->> 'status' not in ('confirmed', 'tentative', 'cancelled') then
    raise exception 'status must be confirmed, tentative or cancelled' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'kind' and v_item ->> 'kind' not in ('event', 'out_of_office', 'focus_time') then
    raise exception 'kind must be event, out_of_office or focus_time' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'transparency' and v_item ->> 'transparency' not in ('opaque', 'transparent') then
    raise exception 'transparency must be opaque or transparent' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names where name = v_item ->> 'tz') then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  select coalesce(array_agg(value::timestamptz order by value::timestamptz), '{}')
    into v_exdates from jsonb_array_elements_text(coalesce(v_item -> 'exdates', '[]'::jsonb));
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_calendar_event_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using v_tenant, save_calendar_event.calendar_id, v_item;
    end if;
  end;
  if v_id is null then
    if v_master is not null then
      select "uid" into v_uid from "better_supabase"."calendar_events"
        where "id" = v_master and "calendar_id" = save_calendar_event.calendar_id and "recurrence_id" is null and "rrule" is not null;
      if not found or v_item ->> 'originalStart' is null then
        raise exception 'an override needs a recurring event and an originalStart' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
      end if;
    end if;
    if v_item ->> 'startsAt' is null or v_item ->> 'endsAt' is null then
      raise exception 'an event needs startsAt and endsAt' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
    end if;
    v_id := gen_random_uuid();
    v_uid := coalesce(v_uid, v_id::text);
    insert into "better_supabase"."calendar_events" ("id", "tenant_id", "calendar_id", "uid", "recurrence_id", "original_start", "title", "starts_at", "ends_at", "all_day", "tz", "status", "rrule", "exdates", "description", "location", "color", "kind", "transparency", "auto_decline", "subject_type", "subject_id", "created_by")
    values (v_id, v_tenant, save_calendar_event.calendar_id, v_uid, v_master, (v_item ->> 'originalStart')::timestamptz, coalesce(v_item ->> 'title', ''), (v_item ->> 'startsAt')::timestamptz, (v_item ->> 'endsAt')::timestamptz, coalesce((v_item ->> 'allDay')::boolean, false), coalesce(v_item ->> 'tz', v_tz), coalesce(v_item ->> 'status', 'confirmed'), nullif(v_item ->> 'rrule', ''), v_exdates, v_item ->> 'description', v_item ->> 'location', v_item ->> 'color', coalesce(v_item ->> 'kind', 'event'), coalesce(v_item ->> 'transparency', 'opaque'), coalesce((v_item ->> 'autoDecline')::boolean, false), v_item ->> 'subjectType', v_item ->> 'subjectId', v_actor);
    v_created := true;
  else
    update "better_supabase"."calendar_events" set
    "title" = case when v_item ? 'title' then coalesce(v_item ->> 'title', '') else "title" end,
    "starts_at" = case when v_item ? 'startsAt' then (v_item ->> 'startsAt')::timestamptz else "starts_at" end,
    "ends_at" = case when v_item ? 'endsAt' then (v_item ->> 'endsAt')::timestamptz else "ends_at" end,
    "all_day" = case when v_item ? 'allDay' then coalesce((v_item ->> 'allDay')::boolean, false) else "all_day" end,
    "tz" = case when v_item ? 'tz' then coalesce(v_item ->> 'tz', v_tz) else "tz" end,
    "status" = case when v_item ? 'status' then coalesce(v_item ->> 'status', 'confirmed') else "status" end,
    "rrule" = case when v_item ? 'rrule' then nullif(v_item ->> 'rrule', '') else "rrule" end,
    "description" = case when v_item ? 'description' then v_item ->> 'description' else "description" end,
    "location" = case when v_item ? 'location' then v_item ->> 'location' else "location" end,
    "color" = case when v_item ? 'color' then v_item ->> 'color' else "color" end,
    "kind" = case when v_item ? 'kind' then coalesce(v_item ->> 'kind', 'event') else "kind" end,
    "transparency" = case when v_item ? 'transparency' then coalesce(v_item ->> 'transparency', 'opaque') else "transparency" end,
    "auto_decline" = case when v_item ? 'autoDecline' then coalesce((v_item ->> 'autoDecline')::boolean, false) else "auto_decline" end,
    "subject_type" = case when v_item ? 'subjectType' then v_item ->> 'subjectType' else "subject_type" end,
    "subject_id" = case when v_item ? 'subjectId' then v_item ->> 'subjectId' else "subject_id" end,
    "exdates" = case when v_item ? 'exdates' then v_exdates else "exdates" end,
    "updated_at" = now()
    where "id" = v_id and "calendar_id" = save_calendar_event.calendar_id
    returning "uid" into v_uid;
    if not found then
      raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
    end if;
  end if;
  if v_item ? 'alarms' then
    if jsonb_typeof(v_item -> 'alarms') <> 'array' or jsonb_array_length(v_item -> 'alarms') > 20 then
      raise exception 'alarms must be an array of at most 20' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
    end if;
    if exists (
      select 1 from jsonb_array_elements(v_item -> 'alarms') x
      where jsonb_typeof(x) <> 'object'
        or coalesce(x ->> 'method', 'display') not in ('display', 'email', 'audio')
        or coalesce(x ->> 'related', 'start') not in ('start', 'end')
        or (x ->> 'offsetMinutes' is null) = (x ->> 'at' is null)
        or abs(coalesce((x ->> 'offsetMinutes')::integer, 0)) > 525600
        or coalesce((x ->> 'repeat')::integer, 0) < 0
        or (coalesce((x ->> 'repeat')::integer, 0) > 0) <> (x ->> 'repeatMinutes' is not null)
        or coalesce((x ->> 'repeatMinutes')::integer, 1) <= 0
    ) then
      raise exception 'each alarm needs a method of display, email or audio, offsetMinutes or at, and repeat with repeatMinutes' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
    end if;
    delete from "better_supabase"."calendar_event_alarms" where "event_id" = v_id and "user_id" is null;
    insert into "better_supabase"."calendar_event_alarms" ("tenant_id", "event_id", "offset_minutes", "method", "related_to", "trigger_at", "repeat_count", "repeat_minutes", "description", "summary")
    select v_tenant, v_id, (x ->> 'offsetMinutes')::integer, coalesce(x ->> 'method', 'display'), coalesce(x ->> 'related', 'start'), (x ->> 'at')::timestamptz, coalesce((x ->> 'repeat')::integer, 0), (x ->> 'repeatMinutes')::integer, x ->> 'description', x ->> 'summary'
    from jsonb_array_elements(v_item -> 'alarms') x;
  end if;
  if exists (select 1 from "better_supabase"."calendar_events" where "id" = v_id and "ends_at" < "starts_at") then
    raise exception 'endsAt must not be before startsAt' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select e."tenant_id", 'calendar_event', e."id"::text, e."starts_at", e."tz", coalesce(e."rrule", 'FREQ=DAILY;COUNT=1')
  from "better_supabase"."calendar_events" e where e."id" = v_id
  on conflict ("tenant_id", "subject_type", "subject_id")
  do update set "dtstart" = excluded."dtstart", "tzid" = excluded."tzid", "rrule" = excluded."rrule";
  if v_created then
    perform "better_supabase".emit_event('calendar_event.created', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'calendarId', save_calendar_event.calendar_id), 'calendar-events/' || v_id::text, (v_tenant)::text, null, 'better-supabase/calendar');
  else
    perform "better_supabase".emit_event('calendar_event.updated', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'calendarId', save_calendar_event.calendar_id), 'calendar-events/' || v_id::text, (v_tenant)::text, null, 'better-supabase/calendar');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_calendar_event_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'uid', v_uid, 'created', v_created);
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
    raise exception 'changes must be a list of { maintenanceRequestId, field, value }' using errcode = '22023', hint = 'WORK_ITEM_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_maintenance_requests.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'maintenanceRequestId')::uuid;
      if not exists (select 1 from "better_supabase"."maintenance_requests" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance.write'), false)) and x."archived_at" is null) then
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
      when 'window' then
        if jsonb_typeof(v_change -> 'value') <> 'object' then
          raise exception 'window must be an object of startAt and endAt' using errcode = '22023', hint = 'WORK_ITEM_ATTRS_INVALID';
        end if;
        update "better_supabase"."maintenance_requests" x set
          "start_at" = case when v_change -> 'value' ? 'startAt' then (v_change -> 'value' ->> 'startAt')::timestamptz else x."start_at" end,
          "end_at" = case when v_change -> 'value' ? 'endAt' then (v_change -> 'value' ->> 'endAt')::timestamptz else x."end_at" end
        where x."id" = v_item;
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
      if update_maintenance_requests.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('maintenanceRequestId', v_change ->> 'maintenanceRequestId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."maintenance_requests" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('maintenance_request.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'maintenanceRequestId')::uuid = v_row."id")), 'maintenance-requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/maintenance');
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
    raise exception 'changes must be a list of { workItemId, field, value }' using errcode = '22023', hint = 'WORK_ITEM_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_work_items.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'workItemId')::uuid;
      if not exists (select 1 from "better_supabase"."work_items" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null) then
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
      when 'window' then
        if jsonb_typeof(v_change -> 'value') <> 'object' then
          raise exception 'window must be an object of startAt and endAt' using errcode = '22023', hint = 'WORK_ITEM_ATTRS_INVALID';
        end if;
        update "better_supabase"."work_items" x set
          "start_at" = case when v_change -> 'value' ? 'startAt' then (v_change -> 'value' ->> 'startAt')::timestamptz else x."start_at" end,
          "end_at" = case when v_change -> 'value' ? 'endAt' then (v_change -> 'value' ->> 'endAt')::timestamptz else x."end_at" end
        where x."id" = v_item;
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
      if update_work_items.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_change ->> 'workItemId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."work_items" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'workItemId')::uuid = v_row."id")), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."save_calendar_event"(uuid, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_calendar_event"(uuid, jsonb, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."update_maintenance_requests"(jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_maintenance_requests"(jsonb, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."update_work_items"(jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_work_items"(jsonb, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_calendar_event"(uuid, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_calendar_event"(uuid, jsonb, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_maintenance_requests"(jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_maintenance_requests"(jsonb, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_work_items"(jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_work_items"(jsonb, boolean) TO "authenticated", "service_role";
