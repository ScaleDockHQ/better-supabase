SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.onboard_with_program (
  tenant  uuid,
  attrs   jsonb,
  program text,
  dates   jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."onboard_with_program"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.onboard_with_program (
  tenant  uuid,
  attrs   jsonb,
  program text,
  dates   jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_employee jsonb;
  v_enrollment jsonb;
begin
  v_employee := "better_supabase"."create_employee"(onboard_with_program.tenant, onboard_with_program.attrs);
  v_enrollment := "better_supabase"."enroll"(onboard_with_program.tenant, onboard_with_program.program, 'employee', v_employee ->> 'id');
  if onboard_with_program.dates is not null and jsonb_typeof(onboard_with_program.dates) = 'object' and onboard_with_program.dates <> '{}'::jsonb then
    v_enrollment := "better_supabase"."set_enrollment_dates"((v_enrollment ->> 'id')::uuid, onboard_with_program.dates);
  end if;
  return jsonb_build_object('employee', v_employee, 'enrollment', v_enrollment);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."onboard_with_program"(uuid, jsonb, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."onboard_with_program"(uuid, jsonb, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."onboard_with_program"(uuid, jsonb, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."onboard_with_program"(uuid, jsonb, text, jsonb) TO "authenticated", "service_role";
