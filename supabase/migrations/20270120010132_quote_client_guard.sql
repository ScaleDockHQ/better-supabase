SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.quote_client_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'INSERT' and not (better_supabase.import_run() is not null) and not (auth.role() = 'service_role') then
      new."token_hash" := null;
      new."decided_at" := null;
      new."decided_by" := null;
      new."decision_note" := null;
      new."decider_id" := null;
      new."decided_ip" := null;
      new."decided_user_agent" := null;
  end if;
  if new."variant_of" is not null and (tg_op = 'INSERT' or new."variant_of" is distinct from old."variant_of")
    and not exists (select 1 from "better_supabase"."quotes" s where s."id" = new."variant_of" and s."tenant_id" = new."tenant_id") then
    raise exception 'a variant belongs to a quote of the same organization' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  return new;
end;
$function$;

CREATE TRIGGER bsb_quote_client_guard
  BEFORE INSERT OR UPDATE OF variant_of ON better_supabase.quotes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.quote_client_guard();

REVOKE ALL ON FUNCTION "better_supabase"."quote_client_guard"() FROM PUBLIC;


CREATE OR REPLACE FUNCTION better_supabase.quote_client_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'INSERT' and not (better_supabase.import_run() is not null) and not (auth.role() = 'service_role') then
      new."token_hash" := null;
      new."decided_at" := null;
      new."decided_by" := null;
      new."decision_note" := null;
      new."decider_id" := null;
      new."decided_ip" := null;
      new."decided_user_agent" := null;
  end if;
  if new."variant_of" is not null and (tg_op = 'INSERT' or new."variant_of" is distinct from old."variant_of")
    and not exists (select 1 from "better_supabase"."quotes" s where s."id" = new."variant_of" and s."tenant_id" = new."tenant_id") then
    raise exception 'a variant belongs to a quote of the same organization' using errcode = '22023', hint = 'QUOTE_VARIANT_TENANT';
  end if;
  return new;
end;
$function$;
