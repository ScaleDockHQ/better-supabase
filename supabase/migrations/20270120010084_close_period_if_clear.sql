SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.close_accounting_period_if_clear (
  period_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."close_accounting_period_if_clear"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.close_accounting_period_if_clear (
  period_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_blockers text[];
begin
  v_blockers := "better_supabase"."accounting_period_close_blockers"(close_accounting_period_if_clear.period_id);
  if cardinality(v_blockers) > 0 then
    return jsonb_build_object('closed', false, 'blockers', to_jsonb(v_blockers));
  end if;
  return jsonb_build_object('closed', true, 'period', "better_supabase"."close_accounting_period"(close_accounting_period_if_clear.period_id));
end;
$function$;

REVOKE ALL ON FUNCTION "api"."close_accounting_period_if_clear"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."close_accounting_period_if_clear"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."close_accounting_period_if_clear"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."close_accounting_period_if_clear"(uuid) TO "authenticated", "service_role";
