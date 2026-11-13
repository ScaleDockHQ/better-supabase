-- better-supabase upgrade: steps pg-delta can't express (renames, backfills, expression changes).
-- Review them before you apply this migration; the module files hold everything else.
-- destructive: reviewed

-- comments: version 9 to 10. comment_counts reads the records with one can_subjects call and finds their conversations by key (comment_count_keys) instead of checking each conversation.
do $$ begin drop function if exists "better_supabase"."comment_count_rows"(uuid[]); exception when dependent_objects_still_exist then null; end $$;

