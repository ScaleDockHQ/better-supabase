-- better-supabase upgrade: steps pg-delta can't express (renames, backfills, expression changes).
-- Review them before you apply this migration; the module files hold everything else.
-- destructive: reviewed

-- time-entries: version 3 to 4. Entries can be archived (ADR 1046): the overlap constraint skips archived rows, and delete_time_entry becomes purge_time_entry.
do $$ begin drop function if exists "better_supabase"."delete_time_entry"(uuid); exception when dependent_objects_still_exist then null; end $$;

alter table "better_supabase"."time_entries" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."time_entries" drop constraint if exists "time_entries_no_overlap_excl";
alter table "better_supabase"."time_entries" drop constraint if exists "time_entries_no_overlap_excl";
alter table "better_supabase"."time_entries" add constraint "time_entries_no_overlap_excl" exclude using gist (
  "tenant_id" with =,
  "user_id" with =,
  tstzrange("started_at", coalesce("ended_at", 'infinity'::timestamptz)) with &&
) where ("archived_at" is null);
