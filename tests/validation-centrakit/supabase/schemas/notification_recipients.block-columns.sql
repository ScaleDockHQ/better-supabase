-- Columns the blocks add to centrakit.notification_recipients, declared in your schema.
-- better-supabase upgrade never rewrites this file.

alter table "centrakit"."notification_recipients" add column if not exists "resolution" jsonb;
