SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.rs_finance_overview (
  p jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'reconciliation', to_jsonb("api"."bank_reconciliation_board"("account_id" => ((p->>'accountId')::uuid), "line_limit" => 100)),
    'stock', to_jsonb("api"."inventory_overview"("tenant" => ((p->>'organizationId')::uuid)))
  )
$function$;

REVOKE ALL ON FUNCTION "public"."rs_finance_overview"(jsonb) FROM PUBLIC, "anon", "service_role";

GRANT EXECUTE ON FUNCTION "public"."rs_finance_overview"(jsonb) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."rs_finance_overview"(jsonb) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."rs_finance_overview"(jsonb) TO "postgres";
