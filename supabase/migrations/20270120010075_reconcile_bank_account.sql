SET local check_function_bodies = off;

REVOKE ALL ON TABLE "public"."plan_features" FROM "anon";

REVOKE ALL ON TABLE "public"."plans" FROM "anon";

CREATE OR REPLACE FUNCTION api.reconcile_bank_account (
  account_id uuid,
  min_score  numeric DEFAULT NULL::numeric,
  line_limit integer DEFAULT 20
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."reconcile_bank_account"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.reconcile_bank_account (
  account_id uuid,
  min_score  numeric DEFAULT NULL::numeric,
  line_limit integer DEFAULT 20
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_line jsonb;
  v_best jsonb;
  v_matched jsonb := '[]'::jsonb;
  v_unmatched jsonb := '[]'::jsonb;
  v_failed jsonb := '[]'::jsonb;
begin
  for v_line in
    select value from jsonb_array_elements("better_supabase"."list_bank_transactions"(
      reconcile_bank_account.account_id,
      jsonb_build_object('status', 'unmatched', 'limit', coalesce(reconcile_bank_account.line_limit, 20))))
  loop
    v_best := "better_supabase"."suggest_bank_matches"((v_line ->> 'id')::uuid) -> 0;
    if v_best is null
      or (reconcile_bank_account.min_score is not null and (v_best ->> 'score')::numeric < reconcile_bank_account.min_score) then
      v_unmatched := v_unmatched || to_jsonb(v_line ->> 'id');
      continue;
    end if;
    begin
      v_matched := v_matched || "better_supabase"."match_bank_transaction"(
        (v_line ->> 'id')::uuid,
        jsonb_build_array(jsonb_build_object('targetType', 'invoice', 'targetId', v_best ->> 'targetId')));
    exception when others then
      v_failed := v_failed || jsonb_build_object('transactionId', v_line ->> 'id', 'message', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('matched', v_matched, 'unmatched', v_unmatched, 'failed', v_failed);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."reconcile_bank_account"(uuid, numeric, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."reconcile_bank_account"(uuid, numeric, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."reconcile_bank_account"(uuid, numeric, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."reconcile_bank_account"(uuid, numeric, integer) TO "authenticated", "service_role";
