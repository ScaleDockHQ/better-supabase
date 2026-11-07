-- Columns the blocks add to centrakit.notification_events, declared in your schema.
-- better-supabase upgrade never rewrites this file.

alter table "centrakit"."notification_events" add column if not exists "actions" jsonb;
