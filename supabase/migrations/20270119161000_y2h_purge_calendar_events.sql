SET local check_function_bodies = off;

DROP FUNCTION "api"."delete_calendar_event"(uuid);

DROP FUNCTION "better_supabase"."delete_calendar_event"(uuid);

CREATE OR REPLACE FUNCTION api.purge_calendar_event (
  event_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_calendar_event"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_calendar_event (
  event_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid := purge_calendar_event.event_id;
  v_tenant uuid;
  v_calendar uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "calendar_id" into v_tenant, v_calendar from "better_supabase"."calendar_events" where "id" = v_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "better_supabase"."calendar_events" where "id" = v_id;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'calendar_event' and "subject_id" = v_id::text;
  perform "better_supabase".emit_event('calendar_event.purged', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'calendarId', v_calendar), 'calendar-events/' || v_id::text, (v_tenant)::text, null, 'better-supabase/calendar');
  return true;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."purge_calendar_event"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_calendar_event"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_calendar_event"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_calendar_event"(uuid) TO "authenticated", "service_role";
