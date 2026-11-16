SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.is_service_role()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') $function$;

REVOKE ALL ON FUNCTION "better_supabase"."is_service_role"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."is_service_role"() TO "anon", "authenticated", "service_role";
