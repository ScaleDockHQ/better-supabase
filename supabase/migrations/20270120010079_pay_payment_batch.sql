SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.pay_payment_batch (
  tenant        uuid,
  input         jsonb,
  with_accounts boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."pay_payment_batch"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.pay_payment_batch (
  tenant        uuid,
  input         jsonb,
  with_accounts boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_batch jsonb;
begin
  v_batch := "better_supabase"."create_payment_batch"(pay_payment_batch.tenant, pay_payment_batch.input);
  v_batch := "better_supabase"."post_payment_batch"((v_batch ->> 'id')::uuid);
  return jsonb_build_object(
    'batch', v_batch,
    'accounts', case when pay_payment_batch.with_accounts
      then "better_supabase"."list_bank_accounts"(pay_payment_batch.tenant, true)
      else '[]'::jsonb end);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."pay_payment_batch"(uuid, jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."pay_payment_batch"(uuid, jsonb, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."pay_payment_batch"(uuid, jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."pay_payment_batch"(uuid, jsonb, boolean) TO "authenticated", "service_role";
