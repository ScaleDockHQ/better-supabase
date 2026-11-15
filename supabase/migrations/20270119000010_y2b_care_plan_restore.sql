SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.restore_care_plan (
  plan_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_care_plan"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_care_plan (
  plan_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."care_plans";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."care_plans" x where x."id" = restore_care_plan.plan_id for update;
  if not found then
    raise exception 'no such care plan' using errcode = 'P0002', hint = 'CARE_PLAN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'care_plans.publish'), false))) then
    raise exception 'not allowed to restore care plans' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(v_row."subject_type", v_row."subject_id", 'read'), false)) then
    raise exception 'not allowed to read this client' using errcode = '42501', hint = 'CARE_PLAN_FORBIDDEN';
  end if;
  if v_row."status" <> 'archived' then
    return "better_supabase"."care_plan_json"(v_row."id");
  end if;
  update "better_supabase"."care_plans" x set "status" = 'draft', "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('care_plan.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'title', v_row."title", 'status', v_row."status", 'version', v_row."version"), 'care-plans/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/care-plans');
  perform better_supabase.audit_event(
    event_type => 'care_plan.restored',
    category => 'data',
    target_type => 'care_plan',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'care plan restored',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'title', v_row."title", 'status', v_row."status", 'version', v_row."version")
  );
  return "better_supabase"."care_plan_json"(v_row."id");
end;
$function$;

REVOKE ALL ON FUNCTION "api"."restore_care_plan"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_care_plan"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_care_plan"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_care_plan"(uuid) TO "authenticated", "service_role";
