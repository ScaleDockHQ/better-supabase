SET local check_function_bodies = off;

DROP FUNCTION "api"."delete_course"(uuid);

DROP FUNCTION "api"."delete_meeting"(uuid);

DROP FUNCTION "better_supabase"."delete_course"(uuid);

DROP FUNCTION "better_supabase"."delete_meeting"(uuid);

ALTER TABLE "better_supabase"."meetings"
  ADD COLUMN "archived_at" timestamp WITH time zone;

CREATE OR REPLACE FUNCTION api.archive_course (
  course_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_course"($1) $function$;

CREATE OR REPLACE FUNCTION api.archive_meeting (
  meeting_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_meeting"($1) $function$;

CREATE OR REPLACE FUNCTION api.purge_course (
  course_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_course"($1) $function$;

CREATE OR REPLACE FUNCTION api.purge_meeting (
  meeting_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_meeting"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_course (
  course_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_course"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_meeting (
  meeting_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_meeting"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_course (
  course_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."courses";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."courses" x where x."id" = archive_course.course_id for update;
  if v_row."id" is null then
    raise exception 'course not found' using errcode = 'P0002', hint = 'COURSE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'courses.manage'), false))) then
    raise exception 'not allowed to manage courses' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  if v_row."status" <> 'archived' then
    update "better_supabase"."courses" x set "status" = 'archived', "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('course.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status"), 'courses/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/courses');
  perform better_supabase.audit_event(
    event_type => 'course.archived',
    category => 'data',
    target_type => 'course',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'archived a course',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status")
  );
  end if;
  return "better_supabase"."course_json"(v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_meeting (
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = archive_meeting.meeting_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to change this meeting' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'archivedAt', v_row."archived_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', v_row."room_code")));
  end if;
  if v_row."status" not in ('held', 'cancelled') then
    raise exception 'only a held or cancelled meeting is archived' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  update "better_supabase"."meetings" x set
    "archived_at" = now(),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('meeting.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'meetings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/meetings');
  perform better_supabase.audit_event(
    event_type => 'meeting.archived',
    category => 'data',
    target_type => 'meeting',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'meeting archived',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'archivedAt', v_row."archived_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', v_row."room_code")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_meeting (
  meeting_id uuid,
  reason     text DEFAULT NULL::text
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = cancel_meeting.meeting_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to cancel this meeting' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_row."status" in ('held', 'cancelled') then
    raise exception 'the meeting can''t move from % to %', v_row."status", 'cancelled' using errcode = '55000', hint = 'MEETING_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'cancelled')::text;
  end if;
  if length(cancel_meeting.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  update "better_supabase"."meetings" x set "status" = 'cancelled', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('meeting.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status", 'reason', nullif(trim(cancel_meeting.reason), '')), 'meetings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/meetings');
  perform better_supabase.audit_event(
    event_type => 'meeting.cancelled',
    category => 'data',
    target_type => 'meeting',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'meeting cancelled',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status", 'reason', nullif(trim(cancel_meeting.reason), ''))
  );
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'archivedAt', v_row."archived_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', v_row."room_code")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_meeting (
  tenant uuid,
  input  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."meetings";
  v_kind text;
  v_title text;
  v_starts timestamptz;
  v_ends timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_meeting.tenant is not null and coalesce(better_supabase.can('tenant', create_meeting.tenant, 'meetings.write'), false))) then
    raise exception 'not allowed to plan meetings' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if jsonb_typeof(create_meeting.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  begin
    v_kind := coalesce(nullif(trim(create_meeting.input ->> 'kind'), ''), (array['meeting', 'board', 'management_review', 'one_on_one', 'toolbox_talk']::text[])[1]);
    v_title := trim(create_meeting.input ->> 'title');
    v_starts := (create_meeting.input ->> 'startsAt')::timestamptz;
    v_ends := (create_meeting.input ->> 'endsAt')::timestamptz;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'startsAt and endsAt are timestamps' using errcode = '22023', hint = 'MEETING_INVALID';
  end;
  if v_kind is null or not (v_kind = any (array['meeting', 'board', 'management_review', 'one_on_one', 'toolbox_talk']::text[])) then
    raise exception 'the kind is not one of options.kinds' using errcode = '22023', hint = 'MEETING_KIND_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a meeting needs a title of 1 to 300 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_starts is null then
    raise exception 'a meeting needs a start time' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_ends < v_starts then
    raise exception 'endsAt is on or after startsAt' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if length(create_meeting.input ->> 'location') > 500 then
    raise exception 'location is at most 500 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if length(create_meeting.input ->> 'summary') > 20000 then
    raise exception 'summary is at most 20000 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if create_meeting.input ? 'fields' and jsonb_typeof(create_meeting.input -> 'fields') is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if create_meeting.input ? 'agenda' and jsonb_typeof(create_meeting.input -> 'agenda') is distinct from 'array' then
    raise exception 'agenda must be a list' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_meeting_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_meeting.tenant, create_meeting.input;
    end if;
  end;
  insert into "better_supabase"."meetings" ("tenant_id", "kind", "title", "starts_at", "ends_at", "location", "summary", "created_by", "room_code")
  values (create_meeting.tenant, v_kind, v_title, v_starts, v_ends, nullif(trim(create_meeting.input ->> 'location'), ''), nullif(trim(create_meeting.input ->> 'summary'), ''), auth.uid(), case when create_meeting.input -> 'fields' ? 'room_code' then (jsonb_populate_record(null::"better_supabase"."meetings", jsonb_build_object('room_code', create_meeting.input -> 'fields' -> 'room_code')))."room_code" else better_supabase.column_default('"better_supabase"."meetings"', 'room_code', (null::"better_supabase"."meetings")."room_code") end)
  returning * into v_row;
  perform "better_supabase"."meeting_set_attendees"(v_row."id", v_row."tenant_id", create_meeting.input -> 'attendees');
  insert into "better_supabase"."meeting_agenda_items" ("tenant_id", "meeting_id", "ordinal", "title", "notes", "presenter_id")
  select v_row."tenant_id", v_row."id", e.n, trim(e.value ->> 'title'), nullif(trim(e.value ->> 'notes'), ''), nullif(e.value ->> 'presenterId', '')::uuid
  from jsonb_array_elements(coalesce(create_meeting.input -> 'agenda', '[]'::jsonb)) with ordinality as e(value, n);
  perform "better_supabase".emit_event('meeting.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'meetings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/meetings');
  perform better_supabase.audit_event(
    event_type => 'meeting.created',
    category => 'data',
    target_type => 'meeting',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'meeting planned',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_meeting_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'archivedAt', v_row."archived_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', v_row."room_code")));
exception when check_violation or invalid_text_representation or not_null_violation then
  raise exception 'an attendee or an agenda item has an invalid value' using errcode = '22023', hint = 'MEETING_INVALID';
end;
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
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'archivedAt', v_row."archived_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', v_row."room_code"))) || jsonb_build_object(
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

CREATE OR REPLACE FUNCTION better_supabase.hold_meeting (
  meeting_id uuid,
  summary    text DEFAULT NULL::text
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = hold_meeting.meeting_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to close this meeting' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_row."status" not in ('planned', 'in_progress') then
    raise exception 'the meeting can''t move from % to %', v_row."status", 'held' using errcode = '55000', hint = 'MEETING_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'held')::text;
  end if;
  if length(hold_meeting.summary) > 20000 then
    raise exception 'summary is at most 20000 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_meeting_hold"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."meetings" x set
    "status" = 'held',
    "started_at" = coalesce(x."started_at", now()),
    "held_at" = now(),
    "summary" = coalesce(nullif(trim(hold_meeting.summary), ''), x."summary"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('meeting.concluded', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'meetings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/meetings');
  perform better_supabase.audit_event(
    event_type => 'meeting.concluded',
    category => 'data',
    target_type => 'meeting',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'meeting held',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_meeting_hold"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'archivedAt', v_row."archived_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', v_row."room_code")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_meetings (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_meetings.filters, '{}'::jsonb);
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
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_meetings.tenant is not null and coalesce(better_supabase.can('tenant', list_meetings.tenant, 'meetings.read'), false)));
begin
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if not v_all and auth.uid() is null then
    raise exception 'not allowed to read meetings' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind', 'status') then
      raise exception 'facet is one of kind, status' using errcode = '22023', hint = 'MEETING_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind")::text when 'status' then (x."status")::text end) as v
      from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."starts_at" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."starts_at" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '') is null or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
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
      select 1 from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."starts_at" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."starts_at" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '') is null or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsAt', 'title') then
    raise exception 'sort is one of startsAt, title' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'title', x."title", 'location', x."location", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'status', x."status", 'startedAt', x."started_at", 'heldAt', x."held_at", 'archivedAt', x."archived_at", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', x."room_code"))) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."starts_at" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."starts_at" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '') is null or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_after is null or (x."starts_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'title', x."title", 'location', x."location", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'status', x."status", 'startedAt', x."started_at", 'heldAt', x."held_at", 'archivedAt', x."archived_at", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', x."room_code"))) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."starts_at" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."starts_at" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '') is null or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_after is null or (x."starts_at" <= (v_after ->> 0)::timestamptz and ((x."starts_at" < (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'title', x."title", 'location', x."location", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'status', x."status", 'startedAt', x."started_at", 'heldAt', x."held_at", 'archivedAt', x."archived_at", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', x."room_code"))) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."starts_at" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."starts_at" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '') is null or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_after is null or (x."starts_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'title', x."title", 'location', x."location", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'status', x."status", 'startedAt', x."started_at", 'heldAt', x."held_at", 'archivedAt', x."archived_at", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', x."room_code"))) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."starts_at" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."starts_at" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '') is null or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_after is null or (x."starts_at" <= (v_after ->> 0)::timestamptz and ((x."starts_at" < (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'title', x."title", 'location', x."location", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'status', x."status", 'startedAt', x."started_at", 'heldAt', x."held_at", 'archivedAt', x."archived_at", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', x."room_code"))) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."starts_at" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."starts_at" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '') is null or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'title', x."title", 'location', x."location", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'status', x."status", 'startedAt', x."started_at", 'heldAt', x."held_at", 'archivedAt', x."archived_at", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', x."room_code"))) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."starts_at" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."starts_at" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '') is null or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."starts_at" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."starts_at" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '') is null or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_course (
  course_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."courses";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."courses" x where x."id" = purge_course.course_id for update;
  if v_row."id" is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'courses.manage'), false))) then
    raise exception 'not allowed to purge courses' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  delete from "better_supabase"."enrollments" x where x."tenant_id" = v_row."tenant_id" and x."program" = ('course:' || v_row."id"::text);
  delete from "better_supabase"."courses" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('course.purged', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status"), 'courses/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/courses');
  perform better_supabase.audit_event(
    event_type => 'course.purged',
    category => 'data',
    target_type => 'course',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'purged a course',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_meeting (
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = purge_meeting.meeting_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to purge this meeting' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_row."status" not in ('planned', 'cancelled') then
    raise exception 'only a planned or cancelled meeting can be purged' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  delete from "better_supabase"."meetings" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('meeting.purged', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'meetings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/meetings');
  perform better_supabase.audit_event(
    event_type => 'meeting.purged',
    category => 'data',
    target_type => 'meeting',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'meeting purged',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'archivedAt', v_row."archived_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', v_row."room_code")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_course (
  course_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."courses";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."courses" x where x."id" = restore_course.course_id for update;
  if v_row."id" is null then
    raise exception 'course not found' using errcode = 'P0002', hint = 'COURSE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'courses.manage'), false))) then
    raise exception 'not allowed to manage courses' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  if v_row."status" = 'archived' then
    update "better_supabase"."courses" x set "status" = 'draft', "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('course.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status"), 'courses/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/courses');
  perform better_supabase.audit_event(
    event_type => 'course.restored',
    category => 'data',
    target_type => 'course',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'restored a course',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status")
  );
  end if;
  return "better_supabase"."course_json"(v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_meeting (
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = restore_meeting.meeting_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to change this meeting' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'archivedAt', v_row."archived_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', v_row."room_code")));
  end if;
  update "better_supabase"."meetings" x set
    "archived_at" = null,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('meeting.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'meetings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/meetings');
  perform better_supabase.audit_event(
    event_type => 'meeting.restored',
    category => 'data',
    target_type => 'meeting',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'meeting restored',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'archivedAt', v_row."archived_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', v_row."room_code")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_meeting (
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = start_meeting.meeting_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to start this meeting' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_row."status" <> 'planned' then
    raise exception 'the meeting can''t move from % to %', v_row."status", 'in_progress' using errcode = '55000', hint = 'MEETING_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'in_progress')::text;
  end if;
  update "better_supabase"."meetings" x set "status" = 'in_progress', "started_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('meeting.started', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'meetings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/meetings');
  perform better_supabase.audit_event(
    event_type => 'meeting.started',
    category => 'data',
    target_type => 'meeting',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'meeting started',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'archivedAt', v_row."archived_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', v_row."room_code")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_meeting (
  meeting_id uuid,
  changes    jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."meetings";
  v_kind text;
  v_title text;
  v_starts timestamptz;
  v_ends timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = update_meeting.meeting_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to change this meeting' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_row."status" = 'cancelled' then
    raise exception 'a cancelled meeting takes no changes' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'an archived meeting takes no changes; restore it first' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if jsonb_typeof(update_meeting.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  begin
    v_kind := coalesce(nullif(trim(update_meeting.changes ->> 'kind'), ''), v_row."kind");
    v_title := case when update_meeting.changes ? 'title' then trim(update_meeting.changes ->> 'title') else v_row."title" end;
    v_starts := case when update_meeting.changes ? 'startsAt' then (update_meeting.changes ->> 'startsAt')::timestamptz else v_row."starts_at" end;
    v_ends := case when update_meeting.changes ? 'endsAt' then (update_meeting.changes ->> 'endsAt')::timestamptz else v_row."ends_at" end;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'startsAt and endsAt are timestamps' using errcode = '22023', hint = 'MEETING_INVALID';
  end;
  if v_kind is null or not (v_kind = any (array['meeting', 'board', 'management_review', 'one_on_one', 'toolbox_talk']::text[])) then
    raise exception 'the kind is not one of options.kinds' using errcode = '22023', hint = 'MEETING_KIND_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a meeting needs a title of 1 to 300 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_starts is null then
    raise exception 'a meeting needs a start time' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_ends < v_starts then
    raise exception 'endsAt is on or after startsAt' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if length(update_meeting.changes ->> 'location') > 500 then
    raise exception 'location is at most 500 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if length(update_meeting.changes ->> 'summary') > 20000 then
    raise exception 'summary is at most 20000 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if update_meeting.changes ? 'fields' and jsonb_typeof(update_meeting.changes -> 'fields') is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  update "better_supabase"."meetings" x set
    "kind" = v_kind,
    "title" = v_title,
    "location" = case when update_meeting.changes ? 'location' then nullif(trim(update_meeting.changes ->> 'location'), '') else x."location" end,
    "summary" = case when update_meeting.changes ? 'summary' then nullif(trim(update_meeting.changes ->> 'summary'), '') else x."summary" end,
    "starts_at" = v_starts,
    "ends_at" = v_ends,
    "updated_at" = now(), "room_code" = case when update_meeting.changes -> 'fields' ? 'room_code' then (jsonb_populate_record(null::"better_supabase"."meetings", jsonb_build_object('room_code', update_meeting.changes -> 'fields' -> 'room_code')))."room_code" else x."room_code" end
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('meeting.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'meetings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/meetings');
  perform better_supabase.audit_event(
    event_type => 'meeting.updated',
    category => 'data',
    target_type => 'meeting',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'meeting updated',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'archivedAt', v_row."archived_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', v_row."room_code")));
end;
$function$;

REVOKE ALL ON FUNCTION "api"."archive_course"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_course"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."archive_meeting"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_meeting"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_course"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_course"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_meeting"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_meeting"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_course"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_course"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_meeting"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_meeting"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_course"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_course"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_meeting"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_meeting"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_course"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_course"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_meeting"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_meeting"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_course"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_course"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_meeting"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_meeting"(uuid) TO "authenticated", "service_role";
