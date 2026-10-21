SET local check_function_bodies = off;

REVOKE ALL ON FUNCTION "api"."acting_member"() FROM "anon";

REVOKE ALL ON FUNCTION "api"."acting_member"() FROM "authenticated";

REVOKE ALL ON FUNCTION "better_supabase"."acting_member"() FROM "anon";

REVOKE ALL ON FUNCTION "better_supabase"."acting_member"() FROM "authenticated";

REVOKE ALL ON FUNCTION "better_supabase"."acting_member"() FROM PUBLIC;
