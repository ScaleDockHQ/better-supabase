SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.rs_pipeline_overview (
  p jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'customers', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::bigint as count from "public"."customers" as t0)),
    'board', to_jsonb("api"."deal_board"("pipeline" => ((p->>'pipelineId')::uuid)))
  )
$function$;

REVOKE ALL ON FUNCTION "public"."rs_pipeline_overview"(jsonb) FROM PUBLIC, "anon", "service_role";

GRANT EXECUTE ON FUNCTION "public"."rs_pipeline_overview"(jsonb) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."rs_pipeline_overview"(jsonb) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."rs_pipeline_overview"(jsonb) TO "postgres";
