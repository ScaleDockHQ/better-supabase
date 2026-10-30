SET local check_function_bodies = off;

REVOKE ALL ON FUNCTION "better_supabase"."column_default"(text, text, anyelement) FROM "anon";

REVOKE ALL ON FUNCTION "better_supabase"."column_default"(text, text, anyelement) FROM "authenticated";

REVOKE ALL ON FUNCTION "better_supabase"."column_default"(text, text, anyelement) FROM "service_role";

DROP FUNCTION "api"."column_default"(text, text, anyelement);
