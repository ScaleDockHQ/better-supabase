SET local check_function_bodies = off;

DROP FUNCTION "api"."list_my_reminders"(uuid, text, text);

DROP FUNCTION "better_supabase"."list_my_reminders"(uuid, text, text);

CREATE OR REPLACE FUNCTION api.list_my_reminders (
  tenant       uuid,
  subject_type text DEFAULT NULL::text,
  subject_id   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_my_reminders"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.list_my_reminders (
  tenant       uuid,
  subject_type text DEFAULT NULL::text,
  subject_id   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_my_reminders.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r."id",
      'subjectType', r."subject_type",
      'subjectId', r."subject_id",
      'method', r."method",
      'offsetMinutes', r."offset_minutes",
      'remindAt', r."remind_at"
    ) order by r."offset_minutes" desc, r."id"), '[]'::jsonb)
    from "better_supabase"."reminders" r
    where r."tenant_id" = list_my_reminders.tenant
      and (list_my_reminders.subject_type is null
        or r."subject_type" = list_my_reminders.subject_type)
      and (list_my_reminders.subject_id is null
        or r."subject_id" = list_my_reminders.subject_id)
      and r."user_id" = auth.uid()
  );
end;
$function$;

REVOKE ALL ON FUNCTION "api"."list_my_reminders"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_my_reminders"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_my_reminders"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_my_reminders"(uuid, text, text) TO "authenticated", "service_role";
