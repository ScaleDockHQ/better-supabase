SET local check_function_bodies = off;

REVOKE ALL ON FUNCTION "better_supabase"."has_organization_role"(uuid, text[]) FROM "anon";

GRANT EXECUTE ON FUNCTION "better_supabase"."has_organization_role"(uuid, text[]) TO "anon";

REVOKE ALL ON FUNCTION "better_supabase"."member_organization_ids"(text[]) FROM "anon";

GRANT EXECUTE ON FUNCTION "better_supabase"."member_organization_ids"(text[]) TO "anon";
