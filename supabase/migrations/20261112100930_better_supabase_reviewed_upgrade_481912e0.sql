-- better-supabase upgrade: steps pg-delta can't express (renames, backfills, expression changes).
-- Review them before you apply this migration; the module files hold everything else.
-- destructive: reviewed

-- queue: version 11 to 12. A schedule can name a probe, a function without arguments that returns whether there is work; a due schedule whose probe returns false stays due and enqueues nothing until it does. list_schedules returns the probe.
do $$ begin drop function if exists better_supabase.schedule_job(text, text, text, jsonb, text, timestamptz, text); exception when dependent_objects_still_exist then null; end $$;

do $$ begin drop function if exists better_supabase.list_schedules(text, text); exception when dependent_objects_still_exist then null; end $$;


-- notifications: version 10 to 11. notification_page sorts by order_by (newest, oldest, type, subject or status, each with a _desc form), filters on exclude_types, subject_ids and any_of groups, and returns the limit it applied; list_notifications and notification_page match search on the actor's name and return up to 500 items.
do $$ begin drop function if exists "better_supabase"."notification_page"(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean, timestamptz, uuid, integer); exception when dependent_objects_still_exist then null; end $$;

