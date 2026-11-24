SET local check_function_bodies = off;

REVOKE ALL ON FUNCTION "api"."rebuild_open_items"(uuid) FROM "authenticated";

REVOKE ALL ON FUNCTION "better_supabase"."rebuild_open_items"(uuid) FROM "authenticated";
