SET local check_function_bodies = off;

COMMENT ON CONSTRAINT "bsb_attachments_bucket" ON "better_supabase"."attachments" IS NULL;

COMMENT ON CONSTRAINT "bsb_attachments_external" ON "better_supabase"."attachments" IS NULL;

COMMENT ON CONSTRAINT "bsb_attachments_size" ON "better_supabase"."attachments" IS NULL;

COMMENT ON CONSTRAINT "bsb_audit_op_check" ON "better_supabase"."audit_events" IS NULL;

COMMENT ON CONSTRAINT "bsb_drive_grants_role" ON "better_supabase"."drive_grants" IS NULL;

COMMENT ON CONSTRAINT "bsb_drive_nodes_document_file" ON "better_supabase"."drive_nodes" IS NULL;

COMMENT ON CONSTRAINT "bsb_drive_nodes_source" ON "better_supabase"."drive_nodes" IS NULL;

COMMENT ON CONSTRAINT "bsb_field_definitions_type" ON "better_supabase"."field_definitions" IS NULL;

COMMENT ON CONSTRAINT "bsb_import_runs_status" ON "better_supabase"."import_runs" IS NULL;

COMMENT ON CONSTRAINT "roles_scope_check" ON "better_supabase"."roles" IS NULL;

COMMENT ON CONSTRAINT "workflow_definitions_subject_types_check" ON "better_supabase"."workflow_definitions" IS NULL;

COMMENT ON CONSTRAINT "workflow_definitions_system_check" ON "better_supabase"."workflow_definitions" IS NULL;

COMMENT ON CONSTRAINT "workflow_runs_subject_check" ON "better_supabase"."workflow_runs" IS NULL;

COMMENT ON CONSTRAINT "workflow_start_requests_subject_check" ON "better_supabase"."workflow_start_requests" IS NULL;

DROP FUNCTION "api"."acting_member"();

DROP FUNCTION "api"."actor_may_write"();

DROP FUNCTION "api"."as_column_type"(text, anyelement);

DROP FUNCTION "api"."import_run"();

DROP FUNCTION "api"."raise_actor_readonly"();

CREATE OR REPLACE FUNCTION better_supabase.try_column_type (
  value  text,
  target anyelement
)
  RETURNS anyelement
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  result alias for $0;
begin
  result := value;
  return result;
exception when data_exception or check_violation then
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.value_unsupported (
  label text
)
  RETURNS text
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  raise exception 'the app does not support the value %', label
    using errcode = '22023', hint = 'VALUE_UNSUPPORTED';
end;
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."try_column_type"(text, anyelement) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."try_column_type"(text, anyelement) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."value_unsupported"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."value_unsupported"(text) TO "anon", "authenticated", "service_role";
