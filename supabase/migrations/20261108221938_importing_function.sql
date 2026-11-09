SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.importing()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select better_supabase.import_run() is not null;
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."importing"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."importing"() TO "anon", "authenticated", "service_role";
