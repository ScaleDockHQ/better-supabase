SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.get_eval_dataset (
  dataset uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_eval_dataset"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_eval_dataset (
  dataset uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."eval_datasets"%rowtype;
begin
  select x.* into v_row from "better_supabase"."eval_datasets" x where x."id" = get_eval_dataset.dataset;
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'name', v_row."name", 'description', v_row."description", 'created_at', v_row."created_at");
end;
$function$;

REVOKE ALL ON FUNCTION "api"."get_eval_dataset"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_eval_dataset"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_eval_dataset"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_eval_dataset"(uuid) TO "service_role";
