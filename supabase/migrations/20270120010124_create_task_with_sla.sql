SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.create_maintenance_request_with_sla (
  tenant       uuid,
  attrs        jsonb,
  assignees    uuid[],
  subject_type text,
  priority     text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_maintenance_request_with_sla"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.create_work_item_with_sla (
  tenant       uuid,
  attrs        jsonb,
  assignees    uuid[],
  subject_type text,
  priority     text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_work_item_with_sla"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION better_supabase.create_maintenance_request_with_sla (
  tenant       uuid,
  attrs        jsonb,
  assignees    uuid[],
  subject_type text,
  priority     text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_task jsonb;
  v_clocks jsonb;
begin
  v_task := "better_supabase"."create_maintenance_request"(create_maintenance_request_with_sla.tenant, create_maintenance_request_with_sla.attrs, create_maintenance_request_with_sla.assignees);
  v_clocks := "better_supabase"."start_sla_clocks"(create_maintenance_request_with_sla.subject_type, v_task ->> 'id', create_maintenance_request_with_sla.priority);
  return jsonb_build_object('task', v_task, 'clocks', v_clocks);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_work_item_with_sla (
  tenant       uuid,
  attrs        jsonb,
  assignees    uuid[],
  subject_type text,
  priority     text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_task jsonb;
  v_clocks jsonb;
begin
  v_task := "better_supabase"."create_work_item"(create_work_item_with_sla.tenant, create_work_item_with_sla.attrs, create_work_item_with_sla.assignees);
  v_clocks := "better_supabase"."start_sla_clocks"(create_work_item_with_sla.subject_type, v_task ->> 'id', create_work_item_with_sla.priority);
  return jsonb_build_object('task', v_task, 'clocks', v_clocks);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."create_maintenance_request_with_sla"(uuid, jsonb, uuid[], text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_maintenance_request_with_sla"(uuid, jsonb, uuid[], text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."create_work_item_with_sla"(uuid, jsonb, uuid[], text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_work_item_with_sla"(uuid, jsonb, uuid[], text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_maintenance_request_with_sla"(uuid, jsonb, uuid[], text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_maintenance_request_with_sla"(uuid, jsonb, uuid[], text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_work_item_with_sla"(uuid, jsonb, uuid[], text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_work_item_with_sla"(uuid, jsonb, uuid[], text, text) TO "authenticated", "service_role";
