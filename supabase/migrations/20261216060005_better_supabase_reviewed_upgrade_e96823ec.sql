-- better-supabase upgrade: steps pg-delta can't express (renames, backfills, expression changes).
-- Review them before you apply this migration; the module files hold everything else.
-- destructive: reviewed

-- attachments: version 9 to 10. confirm_attachment takes an optional object ({ size, mimetype }) that only the service role may pass, for a file in another store such as Vercel Blob; the one-argument function goes.
do $$ begin drop function if exists "better_supabase"."confirm_attachment"(uuid); exception when dependent_objects_still_exist then null; end $$;

