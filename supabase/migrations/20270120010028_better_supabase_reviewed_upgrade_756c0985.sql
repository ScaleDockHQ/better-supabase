-- better-supabase upgrade: steps pg-delta can't express (renames, backfills, expression changes).
-- Review them before you apply this migration; the module files hold everything else.
-- destructive: reviewed

-- ai-schedules: version 2 to 3. Tasks gain source and external_id so another scheduler's tasks can be mirrored.
alter table "better_supabase"."ai_scheduled_tasks" add column if not exists "source" text not null default 'ai-schedules' check (length("source") between 1 and 64);
alter table "better_supabase"."ai_scheduled_tasks" add column if not exists "external_id" text check (length("external_id") between 1 and 200);
