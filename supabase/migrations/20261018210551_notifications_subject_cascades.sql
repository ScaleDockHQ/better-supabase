SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.notifications_subject_deleted()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := tg_argv[0];
  v_id text := to_jsonb(old) ->> tg_argv[1];
  v_tenant text := case when tg_nargs > 2 then to_jsonb(old) ->> tg_argv[2] end;
begin
  if v_tenant is null then
    delete from "better_supabase"."notification_events" x where x."subject_type" = v_type and x."subject_id" = v_id;
    delete from "better_supabase"."notification_subscriptions" x where x."subject_type" = v_type and x."subject_id" = v_id;
  else
    delete from "better_supabase"."notification_events" x where x."organization_id" = v_tenant::uuid and x."subject_type" = v_type and x."subject_id" = v_id;
    delete from "better_supabase"."notification_subscriptions" x where x."organization_id" = v_tenant::uuid and x."subject_type" = v_type and x."subject_id" = v_id;
  end if;
  return null;
end;
$function$;

CREATE TRIGGER bs_notifications_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.notifications_subject_deleted('product_variant', 'id', 'tenant_id');

CREATE TRIGGER bs_notifications_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.notifications_subject_deleted('product', 'id', 'tenant_id');

REVOKE ALL ON FUNCTION "better_supabase"."notifications_subject_deleted"() FROM PUBLIC;
