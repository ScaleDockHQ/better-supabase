SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.pause_enrollment (
  enrollment_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."pause_enrollment"($1) $function$;

CREATE OR REPLACE FUNCTION api.resume_enrollment (
  enrollment_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."resume_enrollment"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.pause_enrollment (
  enrollment_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."enrollments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."enrollments" x where x."id" = pause_enrollment.enrollment_id for update;
  if v_row."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.read'), false))) or (v_row."user_id" is not null and coalesce(v_row."user_id" = auth.uid(), false))) then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.enroll'), false))) or (v_row."user_id" is not null and coalesce(v_row."user_id" = auth.uid(), false))) then
    raise exception 'not allowed to change this enrollment' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if position(':' in v_row."program") > 0 then
    raise exception 'this enrollment belongs to a module and can''t be changed here' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'only an active enrollment can be paused' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if (v_row."paused_at" is not null) is distinct from false then
    return "better_supabase"."enrollment_json"(v_row."id");
  end if;
  update "better_supabase"."enrollments" x
  set "paused_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."tenant_id" is not null then
    perform "better_supabase".emit_event('enrollment.paused', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'program', v_row."program", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'step', null::text, 'completedSteps', v_row."completed_steps", 'totalSteps', cardinality(v_row."steps"), 'reason', null::text), 'enrollments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  end if;
  return "better_supabase"."enrollment_json"(v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resume_enrollment (
  enrollment_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."enrollments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."enrollments" x where x."id" = resume_enrollment.enrollment_id for update;
  if v_row."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.read'), false))) or (v_row."user_id" is not null and coalesce(v_row."user_id" = auth.uid(), false))) then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.enroll'), false))) or (v_row."user_id" is not null and coalesce(v_row."user_id" = auth.uid(), false))) then
    raise exception 'not allowed to change this enrollment' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if position(':' in v_row."program") > 0 then
    raise exception 'this enrollment belongs to a module and can''t be changed here' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'only an active enrollment can be resumed' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if (v_row."paused_at" is not null) is distinct from true then
    return "better_supabase"."enrollment_json"(v_row."id");
  end if;
  update "better_supabase"."enrollments" x
  set "paused_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."tenant_id" is not null then
    perform "better_supabase".emit_event('enrollment.resumed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'program', v_row."program", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'step', null::text, 'completedSteps', v_row."completed_steps", 'totalSteps', cardinality(v_row."steps"), 'reason', null::text), 'enrollments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  end if;
  return "better_supabase"."enrollment_json"(v_row."id");
end;
$function$;

REVOKE ALL ON FUNCTION "api"."pause_enrollment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."pause_enrollment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."resume_enrollment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."resume_enrollment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."pause_enrollment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."pause_enrollment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."resume_enrollment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."resume_enrollment"(uuid) TO "authenticated", "service_role";
