SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.offboard_with_work (
  employee    uuid,
  end_date    date,
  reason      text,
  window_days integer DEFAULT 30
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."offboard_with_work"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.invite_within_seats (
  tenant        uuid,
  invitee_email text,
  invitee_role  text,
  valid_for     interval DEFAULT '7 days'::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  used integer;
  cap jsonb;
begin
  cap := "better_supabase"."entitlement_value"(tenant, 'seats');
  select count(*) into used from "public"."memberships" m where m."organization_id" = tenant;
  if cap is not null and jsonb_typeof(cap) = 'number' and used >= (cap #>> '{}')::numeric then
    raise exception 'The plan has no seat left' using errcode = '22023', hint = 'INVITATION_NO_SEAT';
  end if;
  return "better_supabase"."invite_member"(tenant, invitee_email, invitee_role, valid_for);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.offboard_with_work (
  employee    uuid,
  end_date    date,
  reason      text,
  window_days integer DEFAULT 30
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_employee jsonb;
  v_user uuid;
  v_id uuid;
  v_enrollments integer := 0;
  v_assignments integer := 0;
begin
  v_employee := "better_supabase"."offboard_employee"(offboard_with_work.employee, offboard_with_work.end_date, offboard_with_work.reason);
  select x."user_id" into v_user from "better_supabase"."employees" x where x."id" = offboard_with_work.employee;
  for v_id in
    select x."id" from "better_supabase"."enrollments" x
    where x."subject_type" = 'employee' and x."subject_id" = offboard_with_work.employee::text and x."status" = 'active'
      and position(':' in x."program") = 0
    order by x."id"
  loop
    perform "better_supabase"."cancel_enrollment"(v_id);
    v_enrollments := v_enrollments + 1;
  end loop;
  if v_user is not null then
    for v_id in
      select x."id" from "better_supabase"."shift_assignments" x
      where x."user_id" = v_user and x."status" in ('assigned', 'requested')
        and x."starts_at" >= current_date and x."starts_at" < current_date + offboard_with_work.window_days
      order by x."starts_at", x."id"
    loop
      perform "better_supabase"."unassign_shift"(v_id, offboard_with_work.reason);
      v_assignments := v_assignments + 1;
    end loop;
  end if;
  return jsonb_build_object('employee', v_employee, 'enrollments', v_enrollments, 'assignments', v_assignments);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."offboard_with_work"(uuid, date, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."offboard_with_work"(uuid, date, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."offboard_with_work"(uuid, date, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."offboard_with_work"(uuid, date, text, integer) TO "authenticated", "service_role";
