SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.webhook_inbox_has_work()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."webhook_inbox_has_work"() $function$;

CREATE OR REPLACE FUNCTION better_supabase.webhook_inbox_has_work()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from better_supabase.webhook_inbox c
    where (c.status = 'pending' and c.available_at <= now())
      or (c.status = 'processing' and c.lock_expires_at < now())
  )
$function$;

REVOKE ALL ON FUNCTION "api"."webhook_inbox_has_work"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."webhook_inbox_has_work"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."webhook_inbox_has_work"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."webhook_inbox_has_work"() TO "service_role";
