-- better-supabase upgrade: steps that run before the schema diff.

-- comments: version 8 to 9. list_comments takes include_deleted; false leaves deleted comments out instead of returning placeholders.
drop function if exists "better_supabase"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid);
